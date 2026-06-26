local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ReplicatedFirst    = game:GetService("ReplicatedFirst")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local VirtualUser        = game:GetService("VirtualUser")
local LocalPlayer        = Players.LocalPlayer

local connections = {}
local function track(c) connections[#connections + 1] = c; return c end

----------------------------------------------------------------------
-- Hashed-remote resolver (executor-agnostic, zero dependencies)
-- Every networked remote is named MD5(friendlyName .. JobId) and stored
-- flat in ReplicatedStorage. We compute that name with a built-in MD5,
-- so resolution needs no require / hookmetamethod / getnamecallmethod
-- and works on the weakest injectors exactly like on the strongest.
----------------------------------------------------------------------
local function md5(msg)
    local K = {
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
        0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
        0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
        0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
        0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
        0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
        0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391,
    }
    local S = {
        7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
        5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
        4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
        6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21,
    }
    local band,bor,bxor,bnot,lrotate = bit32.band,bit32.bor,bit32.bxor,bit32.bnot,bit32.lrotate
    local a0,b0,c0,d0 = 0x67452301,0xefcdab89,0x98badcfe,0x10325476
    local bitLen = #msg * 8
    msg = msg .. "\128"
    while (#msg % 64) ~= 56 do msg = msg .. "\0" end
    local function w32le(n) return string.char(n%256, math.floor(n/256)%256, math.floor(n/65536)%256, math.floor(n/16777216)%256) end
    msg = msg .. w32le(bitLen % 0x100000000) .. w32le(math.floor(bitLen / 0x100000000) % 0x100000000)
    for chunk = 1, #msg, 64 do
        local M = {}
        for j = 0, 15 do
            local p = chunk + j*4
            local b1,b2,b3,b4 = string.byte(msg, p, p+3)
            M[j] = b1 + b2*256 + b3*65536 + b4*16777216
        end
        local A,B,C,D = a0,b0,c0,d0
        for i = 0, 63 do
            local F,g
            if i < 16 then F = bor(band(B,C), band(bnot(B),D)); g = i
            elseif i < 32 then F = bor(band(D,B), band(bnot(D),C)); g = (5*i+1)%16
            elseif i < 48 then F = bxor(bxor(B,C),D); g = (3*i+5)%16
            else F = bxor(C, bor(B, bnot(D))); g = (7*i)%16 end
            F = (F + A + K[i+1] + M[g]) % 0x100000000
            A = D; D = C; C = B
            B = (B + lrotate(F, S[i+1])) % 0x100000000
        end
        a0=(a0+A)%0x100000000; b0=(b0+B)%0x100000000; c0=(c0+C)%0x100000000; d0=(d0+D)%0x100000000
    end
    local function hexle(n)
        local s = ""
        for i = 0, 3 do s = s .. string.format("%02x", math.floor(n/(256^i))%256) end
        return s
    end
    return hexle(a0)..hexle(b0)..hexle(c0)..hexle(d0)
end

local function resolveRemote(friendly)
    local jid = game.JobId
    local name = md5(friendly .. (jid == "" and "00000000-0000-0000-0000-000000000000" or jid))
    return ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 6)
end

----------------------------------------------------------------------
-- Game bindings
----------------------------------------------------------------------
local function optreq(path)
    local ok, m = pcall(require, path)
    return ok and m or nil
end

local Items   = optreq(workspace.Lib.Items.TGSItems)
local ItemCat = optreq(workspace.Lib.Items.ItemCategoryEnum)
local PetSys  = optreq(workspace.Lib.PetSystem.TGSPetSystem)

local CURRENCY_TARGET = "Currency_Knivsta"   -- 3 Knivsta = 1 Energy
local RATIO           = 3
local GIVE_KEY        = "Default"

----------------------------------------------------------------------
-- Remote registry
----------------------------------------------------------------------
local R = {}
local function bind()
    R.conv      = R.conv      or resolveRemote("CurrencyConverter_ExchangeCurrencyFund")
    R.strength  = R.strength  or resolveRemote("StrongMan_UpgradeStrength")
    R.workout   = R.workout   or resolveRemote("StrongmanWorkout_SetIsWorkingOut")
    R.rebirth   = R.rebirth   or resolveRemote("StrongMan_Rebirth")
    R.powerMax  = R.powerMax  or resolveRemote("BuyPowerUpgradeMax")
    R.roll      = R.roll      or resolveRemote("TGSPetShopRoll")
    R.petEquip  = R.petEquip  or resolveRemote("TGSPetSystem_EquipPet")
    R.petSell   = R.petSell   or resolveRemote("TGSPetSystem_SellMultiPets")
    R.petComb   = R.petComb   or resolveRemote("TGSPetSystem_CombinePets")
    R.spClaim   = R.spClaim   or resolveRemote("TGSSeasonPets_ClaimPet")
    R.spToggle  = R.spToggle  or resolveRemote("TGSSeasonPets_ToggleSeasonPet")
    R.session   = R.session   or resolveRemote("TGSSimpleSessionRewards_ClaimSessionRewardRemote")
    R.trailer   = R.trailer   or resolveRemote("TrailerReward_ClaimTrailerReward")
    R.community = R.community  or resolveRemote("CommunityRewards_claim")
    R.promo     = R.promo     or ReplicatedStorage:FindFirstChild("PromoCodeRequest")
    R.daily     = R.daily     or ReplicatedStorage:FindFirstChild("RepeatableRewards_Claim")
end
task.spawn(bind)

----------------------------------------------------------------------
-- Stat readers
----------------------------------------------------------------------
local function readItem(cat, key)
    if not Items or not ItemCat then return nil end
    local ok, v = pcall(Items.GetItemInfo, LocalPlayer, cat, key)
    if ok and type(v) == "number" then return v end
    return nil
end
local function readEnergy()   return readItem(ItemCat and ItemCat.Currency, "Default") end
local function readKnivsta()  return readItem(ItemCat and ItemCat.Currency, "Knivsta") end
local function readStrength() return readItem(ItemCat and ItemCat.Stat, "Default") end
local function readRebirth()  return readItem(ItemCat and ItemCat.Stat, "Rebirth") end

----------------------------------------------------------------------
-- Amount parsing: 1k · 1000 · 1.5m · 1sx · 1sp · 2kk · 1 000 000
----------------------------------------------------------------------
local SUFFIX = {
    [""] = 1,
    k = 1e3, m = 1e6, b = 1e9, t = 1e12,
    qd = 1e15, qn = 1e18, sx = 1e21, sp = 1e24, oc = 1e27, no = 1e30,
    dc = 1e33, ud = 1e36, dd = 1e39, td = 1e42, qad = 1e45, qnd = 1e48,
    sxd = 1e51, spd = 1e54, ocd = 1e57, nod = 1e60,
    vg = 1e63, uvg = 1e66, dvg = 1e69, tvg = 1e72, qavg = 1e75,
    qnvg = 1e78, sxvg = 1e81, spvg = 1e84, ocvg = 1e87, novg = 1e90,
    kk = 1e6, kkk = 1e9, q = 1e15, qa = 1e15, qi = 1e18,
    thousand = 1e3, million = 1e6, billion = 1e9, trillion = 1e12,
}

local function parseAmount(input)
    if type(input) ~= "string" then return nil end
    local s = input:lower():gsub("%s+", ""):gsub(",", ""):gsub("_", "")
    if s == "" then return nil end
    local num, suf = s:match("^(%d*%.?%d+)([a-z]*)$")
    if not num then return nil end
    local mult = SUFFIX[suf]
    if not mult then return nil end
    local n = tonumber(num)
    if not n then return nil end
    local total = n * mult
    if total <= 0 then return nil end
    return math.floor(total + 0.5)
end

local SCALE = {
    {1e90,"NoVg"},{1e87,"OcVg"},{1e84,"SpVg"},{1e81,"SxVg"},{1e78,"QnVg"},{1e75,"QaVg"},
    {1e72,"TVg"},{1e69,"DVg"},{1e66,"UVg"},{1e63,"Vg"},{1e60,"NoD"},{1e57,"OcD"},
    {1e54,"SpD"},{1e51,"SxD"},{1e48,"QnD"},{1e45,"QaD"},{1e42,"Td"},{1e39,"Dd"},
    {1e36,"Ud"},{1e33,"Dc"},{1e30,"No"},{1e27,"Oc"},{1e24,"Sp"},{1e21,"Sx"},
    {1e18,"Qn"},{1e15,"Qd"},{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"},
}

local function fmt(n)
    if type(n) ~= "number" then return "?" end
    if n ~= n then return "∞" end
    if n == math.huge then return "∞" end
    for _, e in ipairs(SCALE) do
        if n >= e[1] then return string.format("%.2f%s", n / e[1], e[2]) end
    end
    return tostring(math.floor(n))
end

----------------------------------------------------------------------
-- Currency: mint Knivsta via sign-bypass, then convert to energy
----------------------------------------------------------------------
local State = { alive = true, autoRebirth = false, autoHatch = false, busy = {} }

local function ensureKnivsta(needKnivsta)
    if not R.conv then return end
    if (readKnivsta() or 0) >= needKnivsta then return end
    local energy = readEnergy() or 0
    if energy == math.huge or energy ~= energy then energy = 0 end
    local mint = (energy + needKnivsta / RATIO + 1e6) * RATIO
    pcall(function() R.conv:InvokeServer(CURRENCY_TARGET, -mint) end)
    task.wait(0.55)
end

local function giveEnergy(target)
    if not R.conv then return false, 0 end
    local needKnivsta = target * RATIO
    ensureKnivsta(needKnivsta)
    local ok = pcall(function() R.conv:InvokeServer(CURRENCY_TARGET, needKnivsta) end)
    return ok, ok and target or 0
end

----------------------------------------------------------------------
-- Strength delivery. The server SUMS the cost of every strength level it
-- grants, looping once per requested count and once per rebirth tier; a
-- single huge count makes it loop tens of millions of times and freezes
-- the server. We cap each call to a measured no-freeze budget and deliver
-- the total across cooldown-spaced calls — progress shown live.
----------------------------------------------------------------------
local hookActive = true
local onStrengthCaptured

local function setStrengthRemote(remote)
    local wasEmpty = (R.strength == nil)
    R.strength = remote
    if wasEmpty and onStrengthCaptured then pcall(onStrengthCaptured) end
end

do
    if hookmetamethod and getnamecallmethod then
        local function wrap(f) return (newcclosure and newcclosure(f)) or f end
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            if hookActive then
                pcall(function(...)
                    if getnamecallmethod() == "InvokeServer" and self.ClassName == "RemoteFunction" then
                        local a1, a2 = ...
                        if type(a1) == "number" and a2 == GIVE_KEY then
                            setStrengthRemote(self)
                        end
                    end
                end, ...)
            end
            return oldNamecall(self, ...)
        end))
    end
end

local STRENGTH_CALL_BUDGET = 4000000

local function setServerWorkout(state)
    if R.workout then pcall(function() R.workout:FireServer(state) end) end
end

local function giveStrength(target, onProgress)
    local remote = R.strength
    if not remote then return false, 0, true end
    local char = LocalPlayer.Character
    local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))

    local wasWorkingOut = root and root.Anchored
    if root and not wasWorkingOut then
        root.Anchored = true
        setServerWorkout(true)
        task.wait(0.25)
    end

    local affordIters = math.max(1, math.min(math.floor((readRebirth() or 0) * 0.01), 50000))
    local perCall = math.max(1, math.floor(STRENGTH_CALL_BUDGET / affordIters))

    local remaining = math.max(1, math.floor(target))
    local delivered = 0
    local cd = 0.7
    local fails, calls = 0, 0
    local MAX_CALLS = 30
    while remaining > 0 and State.alive do
        local chunk = math.min(remaining, perCall)
        local ok, res = pcall(function() return remote:InvokeServer(chunk, GIVE_KEY) end)
        if ok and res == true then
            delivered = delivered + chunk
            remaining = remaining - chunk
            calls = calls + 1
            fails = 0
            if onProgress then pcall(onProgress, delivered) end
            if calls >= MAX_CALLS then break end
            task.wait(cd)
        else
            fails = fails + 1
            if fails >= 6 then break end
            cd = math.min(cd + 0.12, 1.2)
            task.wait(cd)
        end
    end

    if root and not wasWorkingOut then
        setServerWorkout(false)
        root.Anchored = false
    end
    return delivered > 0, delivered
end

local FAST_MAX_ITERS = 250000000

local function giveStrengthFast(target)
    local remote = R.strength
    if not remote then return false, 0, true end
    local char = LocalPlayer.Character
    local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))
    local wasWorkingOut = root and root.Anchored
    if root and not wasWorkingOut then
        root.Anchored = true
        setServerWorkout(true)
        task.wait(0.25)
    end

    local affordIters = math.max(1, math.min(math.floor((readRebirth() or 0) * 0.01), 50000))
    local count = math.min(math.max(1, math.floor(target)),
        math.max(1, math.floor(FAST_MAX_ITERS / affordIters)))

    local function fire()
        local ok, r = pcall(function() return remote:InvokeServer(count, GIVE_KEY) end)
        if ok then return r end
        return nil
    end
    local res = fire()
    if res ~= true then task.wait(0.25); res = fire() end

    if root and not wasWorkingOut then
        setServerWorkout(false)
        root.Anchored = false
    end
    local success = res == true
    return success, success and count or 0
end

----------------------------------------------------------------------
-- Rebirth. Cost is paid in Strength; each rebirth = +10% energy/coin
-- multiplier permanently. We pump strength a few bounded fast-calls then
-- fire the bulk rebirth, which grants every rebirth the strength affords.
----------------------------------------------------------------------
local function rebirthOnce()
    if R.rebirth then pcall(function() R.rebirth:FireServer() end) end
end

local function rebirthCycle(pumps)
    local root = LocalPlayer.Character and LocalPlayer.Character.PrimaryPart
    for _ = 1, math.max(1, pumps) do
        if not State.alive then return end
        giveStrengthFast(1e30)
        task.wait(0.2)
    end
    rebirthOnce()
    if root then setServerWorkout(false); root.Anchored = false end
    task.wait(2.15)
end

----------------------------------------------------------------------
-- Promo codes (plain-named RemoteFunction). Codes live server-side, so
-- we submit a candidate list; each returns (success, message).
----------------------------------------------------------------------
local PROMO_CODES = {
    "1500likes","5000likes","10000likes","10000","25k","10m","100m","400m",
    "season1","strongman","strongmansim","update","release","like","sub",
}

local function redeemCodes(report)
    if not R.promo then if report then report("PromoCodeRequest не найден", true) end return end
    local good = 0
    for _, code in ipairs(PROMO_CODES) do
        if not State.alive then break end
        local ok, success = pcall(function() return R.promo:InvokeServer(code) end)
        if ok and success == true then good = good + 1 end
        if report then report("Промокоды: " .. code .. "  (рабочих " .. good .. ")") end
        task.wait(0.35)
    end
    if report then report("Промокоды готовы — рабочих: " .. good .. " ✅", false, true) end
end

----------------------------------------------------------------------
-- Season pets — ClaimPet has no eligibility gate at all.
----------------------------------------------------------------------
local SEASON_PETS = {
    "Stalactort","RhinoBoy","Rex","Darnello","Pupador","FroolevMusic","Pitit",
    "Tazuni","Grizzelord","Fowl","Grumz1","Grumz2","Hyptad1","Froolev","Scarecrow",
}

local function equipBestSeasonPet()
    local folder = workspace.Lib.Seasons:FindFirstChild("SeasonPetSettings")
    if not folder then return end
    local best, bestScore = nil, -1
    for _, n in ipairs(SEASON_PETS) do
        local m = folder:FindFirstChild(n)
        if m then
            local ok, s = pcall(require, m)
            if ok and type(s) == "table" then
                local score = (tonumber(s.EnergyGain) or 0) + (tonumber(s.WorkoutGain) or 0)
                    + (tonumber(s.SeasonXPMultiplier) or 0) + (tonumber(s.WorkoutSpeedMultiplier) or 0)
                if score > bestScore then bestScore = score; best = n end
            end
        end
    end
    if best and R.spToggle then pcall(function() R.spToggle:InvokeServer(best) end) end
    return best
end

local function claimAllSeasonPets(report)
    if not R.spClaim then if report then report("Сезон-петы: remote не найден", true) end return end
    for i, n in ipairs(SEASON_PETS) do
        if not State.alive then break end
        pcall(function() R.spClaim:InvokeServer(n) end)
        if report then report("Сезон-петы: " .. i .. "/" .. #SEASON_PETS) end
        task.wait(0.15)
    end
    local best = equipBestSeasonPet()
    if report then report("Сезон-петы забраны, надет: " .. (best or "—") .. " ✅", false, true) end
end

----------------------------------------------------------------------
-- Power upgrade (Strength), max level. Paid in energy (which is endless).
----------------------------------------------------------------------
local function maxPower(report)
    if not R.powerMax then if report then report("Power upgrade: remote не найден", true) end return end
    giveEnergy(1e9)
    local ok, count = pcall(function() return R.powerMax:InvokeServer("Strength") end)
    if ok then
        report(("Power upgrade: куплено уровней %s ✅"):format(tostring(count or 0)), false, true)
    else
        report("Power upgrade не прошёл (нет серверного модуля)", true)
    end
end

----------------------------------------------------------------------
-- One-shot reward sweep
----------------------------------------------------------------------
local function claimRewards(report)
    local n = 0
    if R.trailer then pcall(function() R.trailer:InvokeServer("MLC") end); n = n + 1; task.wait(0.2) end
    if R.session then pcall(function() R.session:FireServer() end); n = n + 1; task.wait(0.2) end
    if R.community then
        pcall(function() R.community:InvokeServer("SeasonSummer", "Tier3") end); task.wait(0.2)
        pcall(function() R.community:InvokeServer("SeasonSummer", "Tier7") end); n = n + 1; task.wait(0.2)
    end
    if R.daily then pcall(function() R.daily:InvokeServer("DailyGroupReward") end); n = n + 1; task.wait(0.2) end
    if report then report("Награды собраны (" .. n .. " источников) ✅", false, true) end
end

----------------------------------------------------------------------
-- Pets: hatch / sell junk / equip best / combine duplicates
----------------------------------------------------------------------
local RARITY = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local function ownedPets()
    if not PetSys or not PetSys.GetOwnedPets then return {} end
    local ok, m = pcall(PetSys.GetOwnedPets, LocalPlayer)
    if not ok or type(m) ~= "table" then return {} end
    local arr = {}
    for _, p in pairs(m) do arr[#arr + 1] = p end
    return arr
end

local function idSet(getter)
    local s = {}
    if PetSys and PetSys[getter] then
        local ok, a = pcall(PetSys[getter], LocalPlayer)
        if ok and type(a) == "table" then
            for _, v in pairs(a) do
                if type(v) == "string" then s[v] = true
                elseif type(v) == "table" and v.Id then s[v.Id] = true end
            end
        end
    end
    return s
end

local function petCounts()
    local cnt, mx = 0, 30
    if PetSys then
        pcall(function() cnt = PetSys.GetOwnedPetCount(LocalPlayer) or cnt end)
        pcall(function() mx = PetSys.MaxOwnedPetCount(LocalPlayer) or mx end)
    end
    return cnt, mx
end

local function sellJunk(maxRarity)
    if not R.petSell then return end
    local eq, lk = idSet("GetEquippedPetIds"), idSet("GetLockedPets")
    local batch = {}
    local function flush()
        if #batch > 0 then
            local b = batch; batch = {}
            pcall(function() R.petSell:InvokeServer(b) end)
            task.wait(0.6)
        end
    end
    for _, p in ipairs(ownedPets()) do
        if not eq[p.Id] and not lk[p.Id] and (RARITY[p.Rarity] or 1) <= maxRarity then
            batch[#batch + 1] = { Id = p.Id, Name = p.Name, Rarity = p.Rarity }
            if #batch >= 40 then flush() end
        end
    end
    flush()
end

local function equipBestPets()
    if not R.petEquip then return end
    local cap = 2
    pcall(function() cap = PetSys.MaxEquippedPetCount(LocalPlayer) or cap end)
    local eq = idSet("GetEquippedPetIds")
    local equipped = 0
    for _ in pairs(eq) do equipped = equipped + 1 end
    local list = ownedPets()
    table.sort(list, function(a, b) return (RARITY[a.Rarity] or 1) > (RARITY[b.Rarity] or 1) end)
    for _, p in ipairs(list) do
        if equipped >= cap then break end
        if not eq[p.Id] then
            pcall(function() R.petEquip:InvokeServer(p.Id) end)
            equipped = equipped + 1
            task.wait(0.55)
        end
    end
end

local function combineDups()
    if not R.petComb then return end
    local groups = {}
    for _, p in ipairs(ownedPets()) do
        if p.Rarity ~= "Legendary" then
            local key = tostring(p.Name) .. "|" .. tostring(p.Rarity)
            groups[key] = groups[key] or {}
            table.insert(groups[key], p)
        end
    end
    for _, list in pairs(groups) do
        if not State.alive then return end
        local sample = list[1]
        local req = 6
        pcall(function() req = PetSys.RequiredCombine(LocalPlayer, sample) or req end)
        if #list >= req then
            pcall(function() R.petComb:FireServer({ Id = sample.Id, Name = sample.Name, Rarity = sample.Rarity }) end)
            task.wait(3.1)
        end
    end
end

local function hatchLoop(getShop, getRate)
    while State.autoHatch and State.alive do
        local cnt, mx = petCounts()
        if cnt >= mx - 1 then
            combineDups()
            sellJunk(1)
            if select(1, petCounts()) >= mx - 1 then sellJunk(2) end
            equipBestPets()
        end
        if R.roll then pcall(function() R.roll:InvokeServer(getShop()) end) end
        local rate = math.clamp(getRate(), 1, 20)
        task.wait(1 / rate)
    end
end

----------------------------------------------------------------------
-- Teleport targets (client-side; the strength gate is bypassed since
-- movement is a local PivotTo)
----------------------------------------------------------------------
local function gatherTeleports()
    local list = {}
    local folder = ReplicatedFirst:FindFirstChild("Teleporters")
    if folder then
        for _, d in ipairs(folder:GetDescendants()) do
            local id = d:FindFirstChild("TeleportID")
            if id and d:IsA("BasePart") then
                local req = d:FindFirstChild("StatRequired")
                local nice = d.Name:gsub("AreaTarget", ""):gsub("Target", "")
                list[#list + 1] = { name = nice, part = d, req = req and req.Value or 0 }
            end
        end
    end
    table.sort(list, function(a, b) return a.req < b.req end)
    return list
end

local function teleportTo(part)
    local char = LocalPlayer.Character
    if char and part then
        pcall(function() char:PivotTo(part.CFrame * CFrame.new(0, 5, 0)) end)
    end
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local function resolveParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local BG     = Color3.fromRGB(12, 16, 28)
local PANEL  = Color3.fromRGB(20, 26, 42)
local ACCENT = Color3.fromRGB(34, 197, 94)
local STR    = Color3.fromRGB(249, 168, 64)
local VIO    = Color3.fromRGB(150, 120, 255)
local CYAN   = Color3.fromRGB(80, 200, 255)
local RED     = Color3.fromRGB(224, 108, 96)
local GOOD   = Color3.fromRGB(120, 255, 160)
local WARN   = Color3.fromRGB(255, 190, 90)
local BAD    = Color3.fromRGB(255, 110, 110)
local MUTED  = Color3.fromRGB(150, 160, 185)
local TXT    = Color3.fromRGB(235, 240, 250)

local function corner(o, r) local c = Instance.new("UICorner", o); c.CornerRadius = UDim.new(0, r or 10); return c end
local function pad(o, l, r, t, b)
    local p = Instance.new("UIPadding", o)
    p.PaddingLeft = UDim.new(0, l or 0); p.PaddingRight = UDim.new(0, r or 0)
    p.PaddingTop = UDim.new(0, t or 0); p.PaddingBottom = UDim.new(0, b or 0)
    return p
end

local gui = Instance.new("ScreenGui")
gui.Name = "StrongmanGiveGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 2147483000
gui.Parent = resolveParent()
if protect_gui then pcall(protect_gui, gui) end
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end

local window = Instance.new("Frame")
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(360, 466)
window.BackgroundColor3 = BG
window.BorderSizePixel = 0
window.Parent = gui
corner(window, 14)
do
    local s = Instance.new("UIStroke", window)
    s.Thickness = 1.5; s.Color = ACCENT; s.Transparency = 0.25
end

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundTransparency = 1
titleBar.Parent = window

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 0)
title.Size = UDim2.new(1, -56, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = TXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "@sigmatik323"
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(26, 26)
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 22, 28)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.TextColor3 = BAD
closeBtn.Text = "✕"
closeBtn.AutoButtonColor = true
closeBtn.Parent = titleBar
corner(closeBtn, 8)

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0, 1)
status.Position = UDim2.new(0, 16, 1, -10)
status.Size = UDim2.new(1, -32, 0, 30)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.TextSize = 13
status.TextColor3 = MUTED
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true
status.Text = "Готов"
status.Parent = window

local function setStatus(text, color)
    status.Text = text
    status.TextColor3 = color or MUTED
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.fromOffset(12, 44)
tabBar.Size = UDim2.new(1, -24, 0, 32)
tabBar.BackgroundColor3 = PANEL
tabBar.BorderSizePixel = 0
tabBar.Parent = window
corner(tabBar, 9)
do
    local l = Instance.new("UIListLayout", tabBar)
    l.FillDirection = Enum.FillDirection.Horizontal
    l.HorizontalAlignment = Enum.HorizontalAlignment.Center
    l.VerticalAlignment = Enum.VerticalAlignment.Center
    l.Padding = UDim.new(0, 4)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    pad(tabBar, 4, 4, 0, 0)
end

local contentHolder = Instance.new("Frame")
contentHolder.Position = UDim2.fromOffset(12, 84)
contentHolder.Size = UDim2.new(1, -24, 1, -84 - 46)
contentHolder.BackgroundTransparency = 1
contentHolder.Parent = window

local tabs = {}
local function selectTab(name)
    for k, t in pairs(tabs) do
        local on = (k == name)
        t.page.Visible = on
        t.btn.BackgroundColor3 = on and t.color or PANEL
        t.btn.TextColor3 = on and Color3.fromRGB(10, 14, 22) or MUTED
    end
end

local function addTab(name, color)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 78, 1, -6)
    btn.BackgroundColor3 = PANEL
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = MUTED
    btn.Text = name
    btn.AutoButtonColor = false
    btn.Parent = tabBar
    corner(btn, 7)

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = color
    page.CanvasSize = UDim2.new()
    page.AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y
    page.Visible = false
    page.Parent = contentHolder
    local l = Instance.new("UIListLayout", page)
    l.Padding = UDim.new(0, 8)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    pad(page, 2, 8, 2, 8)

    tabs[name] = { btn = btn, page = page, color = color }
    track(btn.MouseButton1Click:Connect(function() selectTab(name) end))
    return page
end

----------------------------------------------------------------------
-- Component builders
----------------------------------------------------------------------
local function busyGuard(key, fn)
    if State.busy[key] then return end
    State.busy[key] = true
    task.spawn(function()
        local ok, err = pcall(fn)
        if not ok then setStatus("Ошибка: " .. tostring(err), BAD) end
        State.busy[key] = false
    end)
end

local function label(parent, ru, en)
    local p = Instance.new("TextLabel")
    p.Size = UDim2.new(1, 0, 0, en and 34 or 18)
    p.BackgroundTransparency = 1
    p.Font = Enum.Font.GothamSemibold
    p.TextSize = 13
    p.TextColor3 = Color3.fromRGB(225, 232, 245)
    p.TextXAlignment = Enum.TextXAlignment.Left
    p.TextYAlignment = Enum.TextYAlignment.Top
    p.RichText = true
    p.Text = en and (ru .. "\n<font color=\"rgb(150,160,185)\">" .. en .. "</font>") or ru
    p.Parent = parent
    return p
end

local function inputBox(parent, default, placeholder)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 36)
    box.BackgroundColor3 = PANEL
    box.Font = Enum.Font.GothamMedium
    box.TextSize = 15
    box.TextColor3 = TXT
    box.PlaceholderText = placeholder or "1k · 1000 · 1sx"
    box.PlaceholderColor3 = MUTED
    box.Text = default or ""
    box.ClearTextOnFocus = false
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Parent = parent
    corner(box, 9)
    pad(box, 12, 12, 0, 0)
    local s = Instance.new("UIStroke", box)
    s.Color = Color3.fromRGB(50, 60, 86); s.Transparency = 0.2
    return box
end

local function button(parent, text, color, fn)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = color
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.TextColor3 = Color3.fromRGB(10, 14, 22)
    btn.Text = text
    btn.AutoButtonColor = true
    btn.Parent = parent
    corner(btn, 9)
    track(btn.MouseButton1Click:Connect(function() fn(btn) end))
    return btn
end

local function dualButton(parent, t1, c1, f1, t2, c2, f2)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 36)
    holder.BackgroundTransparency = 1
    holder.Parent = parent
    local l = Instance.new("UIListLayout", holder)
    l.FillDirection = Enum.FillDirection.Horizontal
    l.Padding = UDim.new(0, 8)
    local function half(t, c, f)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5, -4, 1, 0)
        b.BackgroundColor3 = c
        b.Font = Enum.Font.GothamBold
        b.TextSize = 14
        b.TextColor3 = Color3.fromRGB(10, 14, 22)
        b.Text = t
        b.Parent = holder
        corner(b, 9)
        track(b.MouseButton1Click:Connect(function() f(b) end))
        return b
    end
    return half(t1, c1, f1), half(t2, c2, f2)
end

local function toggle(parent, text, color, fn)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = PANEL
    row.AutoButtonColor = false
    row.Text = ""
    row.Parent = parent
    corner(row, 9)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.fromOffset(12, 0)
    lbl.Size = UDim2.new(1, -64, 1, 0)
    lbl.Font = Enum.Font.GothamSemibold
    lbl.TextSize = 13
    lbl.TextColor3 = TXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = text
    lbl.Parent = row
    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(1, 0.5)
    knob.Position = UDim2.new(1, -12, 0.5, 0)
    knob.Size = UDim2.fromOffset(40, 22)
    knob.BackgroundColor3 = Color3.fromRGB(45, 52, 74)
    knob.Parent = row
    corner(knob, 11)
    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(0, 0.5)
    dot.Position = UDim2.new(0, 3, 0.5, 0)
    dot.Size = UDim2.fromOffset(16, 16)
    dot.BackgroundColor3 = Color3.fromRGB(200, 205, 220)
    dot.Parent = knob
    corner(dot, 8)
    local on = false
    local function render()
        TweenService:Create(knob, TweenInfo.new(0.15), { BackgroundColor3 = on and color or Color3.fromRGB(45, 52, 74) }):Play()
        TweenService:Create(dot, TweenInfo.new(0.15), { Position = on and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }):Play()
    end
    track(row.MouseButton1Click:Connect(function()
        on = not on
        render()
        fn(on)
    end))
    return function(v) on = v; render() end
end

local function cycle(parent, getItems, getIndex, setIndex)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = PANEL
    row.Parent = parent
    corner(row, 9)
    local left = Instance.new("TextButton")
    left.Size = UDim2.fromOffset(34, 38)
    left.BackgroundTransparency = 1
    left.Font = Enum.Font.GothamBold
    left.TextSize = 18
    left.TextColor3 = MUTED
    left.Text = "‹"
    left.Parent = row
    local right = Instance.new("TextButton")
    right.AnchorPoint = Vector2.new(1, 0)
    right.Position = UDim2.fromScale(1, 0)
    right.Size = UDim2.fromOffset(34, 38)
    right.BackgroundTransparency = 1
    right.Font = Enum.Font.GothamBold
    right.TextSize = 18
    right.TextColor3 = MUTED
    right.Text = "›"
    right.Parent = row
    local lbl = Instance.new("TextLabel")
    lbl.Position = UDim2.fromOffset(34, 0)
    lbl.Size = UDim2.new(1, -68, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.TextColor3 = TXT
    lbl.Text = ""
    lbl.Parent = row
    local function render()
        local items = getItems()
        local i = getIndex()
        lbl.Text = items[i] and tostring(items[i].label or items[i]) or "—"
    end
    track(left.MouseButton1Click:Connect(function()
        local items = getItems()
        if #items == 0 then return end
        setIndex(((getIndex() - 2) % #items) + 1); render()
    end))
    track(right.MouseButton1Click:Connect(function()
        local items = getItems()
        if #items == 0 then return end
        setIndex((getIndex() % #items) + 1); render()
    end))
    render()
    return render
end

----------------------------------------------------------------------
-- Tab: ГЕЙН (energy / strength / rebirth)
----------------------------------------------------------------------
do
    local page = addTab("ГЕЙН", ACCENT)

    label(page, "Сколько выдать энергии?", "How much energy")
    local energyBox = inputBox(page, "1m")
    button(page, "Выдать энергию", ACCENT, function(b)
        busyGuard("energy", function()
            local target = parseAmount(energyBox.Text)
            if not target then setStatus("Не понял число: 1k · 1000 · 1sx", WARN); return end
            b.Text = "Выдаю…"; setStatus("Энергия: " .. fmt(target) .. "…", ACCENT)
            local ok = giveEnergy(target)
            setStatus(ok and ("Энергия +" .. fmt(target) .. " ✅") or "Энергия: не вышло", ok and GOOD or BAD)
            b.Text = "Выдать энергию"
        end)
    end)

    label(page, "Сколько выдать силы?", "How much strength")
    local strBox = inputBox(page, "1111111")
    dualButton(page,
        "Safe", STR, function(b)
            busyGuard("strength", function()
                local target = parseAmount(strBox.Text)
                if not target then setStatus("Не понял число", WARN); return end
                b.Text = "…"; setStatus("Сила: " .. fmt(target) .. "…", STR)
                local ok, given, need = giveStrength(target, function(d)
                    setStatus("Сила… " .. fmt(d) .. " / " .. fmt(target), STR)
                end)
                if ok then setStatus("Сила +" .. fmt(given) .. " ✅", GOOD)
                elseif need then setStatus("Покачайся 1 раз — ловлю remote", WARN)
                else setStatus("Сила: remote не найден", BAD) end
                b.Text = "Safe"
            end)
        end,
        "Обычно", RED, function(b)
            busyGuard("strength", function()
                local target = parseAmount(strBox.Text)
                if not target then setStatus("Не понял число", WARN); return end
                b.Text = "…"; setStatus("Сила (быстро): " .. fmt(target) .. "…", STR)
                local ok, given = giveStrengthFast(target)
                setStatus(ok and ("Сила +" .. fmt(given) .. " ✅") or "Сила: не вышло", ok and GOOD or BAD)
                b.Text = "Обычно"
            end)
        end
    )

    label(page, "Ребёрты", "Сила сбрасывается, +10% энергии за ребёрт")
    button(page, "Ребёрт сейчас", VIO, function(b)
        busyGuard("rebirth", function()
            b.Text = "Качаю + ребёрчу…"; setStatus("Ребёрт: качаю силу…", VIO)
            rebirthCycle(6)
            setStatus("Ребёртов: " .. fmt(readRebirth() or 0) .. " ✅", GOOD)
            b.Text = "Ребёрт сейчас"
        end)
    end)
    toggle(page, "Авто-ребёрт", VIO, function(on)
        State.autoRebirth = on
        if on then
            setStatus("Авто-ребёрт включён", VIO)
            task.spawn(function()
                while State.autoRebirth and State.alive do
                    rebirthCycle(6)
                end
            end)
        else
            setStatus("Авто-ребёрт выключен", MUTED)
        end
    end)
end

----------------------------------------------------------------------
-- Tab: БУСТЫ (codes / season pets / power / rewards)
----------------------------------------------------------------------
do
    local page = addTab("БУСТЫ", CYAN)

    label(page, "Промокоды", "Перебор всех известных кодов")
    button(page, "Активировать все коды", CYAN, function(b)
        busyGuard("codes", function()
            b.Text = "Ввожу…"
            redeemCodes(function(t, isErr, done) setStatus(t, isErr and BAD or (done and GOOD or CYAN)) end)
            b.Text = "Активировать все коды"
        end)
    end)

    label(page, "Сезонные питомцы", "Забрать всех (без условий) + надеть лучшего")
    button(page, "Забрать всех сезон-петов", VIO, function(b)
        busyGuard("seasonpets", function()
            b.Text = "Забираю…"
            claimAllSeasonPets(function(t, isErr, done) setStatus(t, isErr and BAD or (done and GOOD or VIO)) end)
            b.Text = "Забрать всех сезон-петов"
        end)
    end)

    label(page, "Прокачка силы", "Power Upgrade до максимума")
    button(page, "Прокачать силу (макс)", STR, function(b)
        busyGuard("power", function()
            b.Text = "Качаю…"
            maxPower(function(t, isErr, done) setStatus(t, isErr and WARN or (done and GOOD or STR)) end)
            b.Text = "Прокачать силу (макс)"
        end)
    end)

    label(page, "Награды", "Трейлер · сессия · комьюнити · группа")
    button(page, "Собрать все награды", ACCENT, function(b)
        busyGuard("rewards", function()
            b.Text = "Собираю…"; setStatus("Награды: собираю…", ACCENT)
            claimRewards(function(t, isErr, done) setStatus(t, isErr and BAD or (done and GOOD or ACCENT)) end)
            b.Text = "Собрать все награды"
        end)
    end)
end

----------------------------------------------------------------------
-- Tab: ПЕТЫ (hatch / equip / sell / combine)
----------------------------------------------------------------------
do
    local page = addTab("ПЕТЫ", VIO)

    local EGGS = {
        "29Superhero","28Bank","27Prison","26Football","25Magic","24Robo","23Mineshaft",
        "22Sewer","21Kitchen","20Asian","19Princess","18Treasury","17Apartment","16WildWest",
        "15DeepSea","14Winter","13Retro","12Dino","11Tropical","10Science","9Candyland",
        "8Space","7Disco","6Steampunk","5Medieval","4Farm","3Arcade","2Food","1Training","LobbyShop",
    }
    local eggIndex = 1
    local rate = 4

    label(page, "Яйцо для авто-вылупления", "Энергия бесконечная — хватит на любое")
    cycle(page, function() return EGGS end, function() return eggIndex end, function(i) eggIndex = i end)

    label(page, "Вылуплений в секунду", nil)
    local rateBox = inputBox(page, "4", "4")
    track(rateBox.FocusLost:Connect(function()
        rate = math.clamp(tonumber(rateBox.Text) or 4, 1, 20)
        rateBox.Text = tostring(rate)
    end))

    toggle(page, "Авто-вылупление (+слияние/продажа)", VIO, function(on)
        State.autoHatch = on
        if on then
            setStatus("Авто-вылупление: " .. EGGS[eggIndex], VIO)
            task.spawn(function()
                hatchLoop(function() return EGGS[eggIndex] end, function() return rate end)
            end)
        else
            setStatus("Авто-вылупление выключено", MUTED)
        end
    end)

    button(page, "Надеть лучших петов", ACCENT, function(b)
        busyGuard("equipbest", function()
            b.Text = "Надеваю…"; equipBestPets()
            setStatus("Лучшие петы надеты ✅", GOOD); b.Text = "Надеть лучших петов"
        end)
    end)
    dualButton(page,
        "Слить дубли", CYAN, function(b)
            busyGuard("combine", function()
                b.Text = "Сливаю…"; combineDups()
                setStatus("Дубли слиты ✅", GOOD); b.Text = "Слить дубли"
            end)
        end,
        "Продать Common", RED, function(b)
            busyGuard("selljunk", function()
                b.Text = "Продаю…"; sellJunk(1)
                setStatus("Common проданы ✅", GOOD); b.Text = "Продать Common"
            end)
        end
    )
end

----------------------------------------------------------------------
-- Tab: ТП (teleport to areas)
----------------------------------------------------------------------
do
    local page = addTab("ТП", CYAN)
    local areas = gatherTeleports()
    local areaIndex = 1

    label(page, "Зона", "Сила обходит порог — телепорт куда угодно")
    cycle(page,
        function()
            local out = {}
            for i, a in ipairs(areas) do out[i] = { label = a.name .. "  (" .. fmt(a.req) .. ")" } end
            return out
        end,
        function() return areaIndex end,
        function(i) areaIndex = i end
    )
    button(page, "Телепорт", CYAN, function()
        local a = areas[areaIndex]
        if a then teleportTo(a.part); setStatus("ТП → " .. a.name, CYAN) end
    end)

    if #areas == 0 then
        label(page, "Телепортеры не найдены", "Зайди в игру и попробуй снова")
    end
end

selectTab("ГЕЙН")

onStrengthCaptured = function() setStatus("✅ Remote силы готов", GOOD) end
setStatus("Готов · энергия/сила/ребёрт/петы/коды", MUTED)

----------------------------------------------------------------------
-- Drag
----------------------------------------------------------------------
do
    local dragging, dragStart, startPos
    track(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = window.Position
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

----------------------------------------------------------------------
-- Anti-AFK
----------------------------------------------------------------------
track(LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end))

----------------------------------------------------------------------
-- Unload
----------------------------------------------------------------------
local function unload()
    hookActive = false
    State.alive = false
    State.autoRebirth = false
    State.autoHatch = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    if gui then gui:Destroy() end
end
track(closeBtn.MouseButton1Click:Connect(unload))
