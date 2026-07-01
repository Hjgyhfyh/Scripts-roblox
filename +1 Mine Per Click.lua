--[[
    +1 Mine Per Click  —  full progression autofarm
    tg: @sigmatik323

    Mine (in-zone, server-validated) -> sell -> upgrade pickaxe -> auras -> rebirth,
    self-adapting to strength growth. Enable and forget.
]]

if getgenv().MinePerClick and getgenv().MinePerClick.unload then
    pcall(getgenv().MinePerClick.unload)
end
getgenv().MinePerClick = getgenv().MinePerClick or {}

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local HttpService        = game:GetService("HttpService")
local VirtualUser        = game:GetService("VirtualUser")
local Workspace          = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- executor compat
----------------------------------------------------------------------
local writefileFn = writefile or (syn and syn.writefile)
local readfileFn  = readfile  or (syn and syn.readfile)
local isfileFn    = isfile    or function(p) local ok,r = pcall(readfileFn, p); return ok and r ~= nil end
local queueTeleport = (syn and syn.queue_on_teleport) or queue_on_teleport or queueonteleport
local function setIdentity() pcall(function() (setthreadidentity or set_thread_identity or setidentity)(8) end) end

local CONFIG_FILE = "MinePerClick_config.json"

----------------------------------------------------------------------
-- default config (single source of truth, persisted to JSON)
----------------------------------------------------------------------
local DEFAULTS = {
    enabled          = false,
    autoMine         = true,
    autoClick        = true,
    autoSell         = true,
    autoSpend        = true,
    autoRebirth      = true,
    buyPickaxes      = true,
    buyAuras         = true,
    buyBackpack      = true,
    buyWalkspeed     = false,
    claimGroupReward = true,
    anchorWhileMining= true,

    totalBudget      = 350,   -- combined FireServer calls / sec (hard ceiling < 400)
    maxHitRate       = 150,   -- HitWall calls / sec cap
    maxClickRate     = 250,   -- Click calls / sec cap

    T_max            = 6.0,   -- max acceptable seconds to break a wall
    H_max            = 4000,  -- max acceptable hits to break a wall
    holdRadius       = 10,    -- studs before re-asserting position
    settleDelay      = 0.55,  -- seconds to let a teleport replicate before probing
    stuckTimeout     = 22,    -- seconds of no HP progress -> stage marked infeasible

    auraFraction     = 0.5,   -- buy aura only if price <= this * Cash
    backpackAbundance= 3,     -- buy slot only if Cash >= this * cost
    maxBackpack      = 10,
    maxExtraWalkspeed= 25,
    rebirthStopLevel = 0,     -- 0 = never stop chasing rebirth
    sellFraction     = 1.0,   -- sell when loot count >= ceil(size * this)

    keybind          = "RightShift",
    -- learned / runtime state (persisted, not user-facing)
    _dmgRatio        = false,
    _deepestReached  = 0,
    _sellMode        = "auto", -- auto | inplace | surface
    _bootTimes       = {},
}

local CFG = {}
for k, v in pairs(DEFAULTS) do CFG[k] = v end

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then deepMerge(dst[k], v)
        else dst[k] = v end
    end
end

local function saveConfig()
    if not writefileFn then return end
    pcall(function()
        local ok, enc = pcall(HttpService.JSONEncode, HttpService, CFG)
        if ok then
            writefileFn(CONFIG_FILE .. ".tmp", enc)
            writefileFn(CONFIG_FILE, enc)   -- write tmp then real; partial writes can't brick the live file
        end
    end)
end

local function loadConfig()
    if not (readfileFn and isfileFn and isfileFn(CONFIG_FILE)) then return end
    local ok, raw = pcall(readfileFn, CONFIG_FILE)
    if not ok or not raw then return end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok2 and type(data) == "table" then
        deepMerge(CFG, data)
    else
        pcall(function() if writefileFn then writefileFn(CONFIG_FILE .. ".bad", raw) end end)
        saveConfig()  -- rewrite a clean default file
    end
end
loadConfig()

----------------------------------------------------------------------
-- boot circuit breaker (avoid tight crash/rejoin loops overnight)
----------------------------------------------------------------------
local nowClock = os.clock()
local nowEpoch = os.time()
do
    local recent = {}
    for _, t in ipairs(CFG._bootTimes or {}) do
        if nowEpoch - t < 300 then recent[#recent + 1] = t end
    end
    recent[#recent + 1] = nowEpoch
    CFG._bootTimes = recent
    if #recent > 5 then
        CFG.enabled = false   -- too many boots in 5 min -> start disabled (safe mode)
    end
    saveConfig()
end

----------------------------------------------------------------------
-- connection tracking + teardown scaffolding
----------------------------------------------------------------------
local unloaded = false
local conns = {}
local function conn(signal, fn)
    local c = signal:Connect(fn)
    conns[#conns + 1] = c
    return c
end
local function safeDelay(t, fn)
    task.delay(t, function() if not unloaded then fn() end end)
end

----------------------------------------------------------------------
-- wait for game data + modules
----------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Srv     = Remotes:WaitForChild("Server")
local Cli     = Remotes:WaitForChild("Client")

local function srvRemote(name) return Srv:WaitForChild(name, 10) end
local R = {
    Click            = srvRemote("Click"),
    HitWall          = srvRemote("HitWall"),
    SellAllLoot      = srvRemote("SellAllLoot"),
    PurchasePickaxe  = srvRemote("PurchasePickaxe"),
    EquipPickaxe     = srvRemote("EquipPickaxe"),
    Rebirth          = srvRemote("Rebirth"),
    UpgradeSlot      = srvRemote("UpgradeSlot"),
    UpgradeWalkspeed = srvRemote("UpgradeWalkspeed"),
    PurchaseAura     = srvRemote("PurchaseAura"),
    EquipAura        = srvRemote("EquipAura"),
    GotoSurface      = srvRemote("GotoSurface"),
    GroupReward      = srvRemote("GroupReward"),
}

local function reqByName(name)
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == name and d:IsA("ModuleScript") then
            local ok, m = pcall(require, d)
            if ok then return m end
        end
    end
end

local DataClient = reqByName("DataClient")
local PickaxeList = reqByName("PickaxeList") or {}
local AurasList   = reqByName("AurasList")   or {}
local UpgradesHelper = reqByName("UpgradesHelper")

-- live replica (re-acquired if it ever swaps)
local replica, Data
local function acquireReplica()
    if not DataClient then return end
    local ok, rep = pcall(function() return DataClient:GetReplica() end)
    if ok and rep and rep.Data then replica, Data = rep, rep.Data end
end
acquireReplica()
do
    local t0 = os.clock()
    while not Data and os.clock() - t0 < 15 do task.wait(0.2); acquireReplica() end
end
if not Data then Data = {} end

-- StagesList (mining map): try client module then descendants
local StagesList
do
    local ok, sc = pcall(function() return require(ReplicatedStorage.Client.StageClient) end)
    if ok and type(sc) == "table" then StagesList = sc.StagesList or sc.Stages end
    StagesList = StagesList or reqByName("StagesList")
end
StagesList = StagesList or {}

----------------------------------------------------------------------
-- catalogs from LIVE modules (exact server-accepted ids)
----------------------------------------------------------------------
local PICK = {}   -- id -> {price, str}
for id, d in pairs(PickaxeList) do
    if type(d) == "table" and d.Price ~= nil and d.Strength and not d.GamepassId then
        PICK[id] = { price = d.Price, str = d.Strength }   -- cash-buyable only
    end
end
local AURA = {}   -- id -> {price, mult}
for id, d in pairs(AurasList) do
    if type(d) == "table" and d.Price and d.Multiplier then
        AURA[id] = { price = d.Price, mult = d.Multiplier }
    end
end

local STAGE_N = 0
for s in pairs(StagesList) do if type(s) == "number" and s > STAGE_N then STAGE_N = s end end

----------------------------------------------------------------------
-- level math (LevelsHelper: base 45, growth 1.094) precomputed
----------------------------------------------------------------------
local LEVEL_CUM = { [1] = 0 }   -- cumulative strength needed to be AT level L
do
    local band, cum = 45.0, 0
    for L = 1, 600 do
        cum = cum + math.floor(band)
        LEVEL_CUM[L + 1] = cum
        band = band * 1.094
    end
end
local function getLevel(strength)
    strength = strength or 0
    local lo, hi = 1, #LEVEL_CUM
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if LEVEL_CUM[mid] <= strength then lo = mid else hi = mid - 1 end
    end
    return lo
end
local function rebirthGate(reb) return 25 * ((reb or 0) + 1) end

----------------------------------------------------------------------
-- generic helpers
----------------------------------------------------------------------
local function getChar()
    local c = LocalPlayer.Character
    if not c then return end
    return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildWhichIsA("Humanoid")
end

local function waitUntil(pred, timeout)
    local t0 = os.clock()
    while not pred() do
        if os.clock() - t0 > (timeout or 2) then return false end
        task.wait(0.05)
    end
    return true
end

-- works whether Data.Pickaxes/Auras is an array of ids or a set keyed by id
local function containerHas(container, id)
    if type(container) ~= "table" then return false end
    for k, v in pairs(container) do
        if v == id then return true end
        if k == id and v then return true end
    end
    return false
end
local function bestOwned(catalog, container, valField)
    local best, bestV = nil, -1
    if type(container) == "table" then
        for k, v in pairs(container) do
            local id = (type(v) == "string" and v) or (v == true and k) or nil
            if id and catalog[id] and catalog[id][valField] > bestV then
                best, bestV = id, catalog[id][valField]
            end
        end
    end
    return best, bestV
end

----------------------------------------------------------------------
-- shared budget: windowed hard cap + per-tick anti-burst
----------------------------------------------------------------------
local windowStart, windowCount = nowClock, 0
local function budgetLeft()
    local now = os.clock()
    if now - windowStart >= 1 then windowStart = now; windowCount = 0 end
    return CFG.totalBudget - windowCount
end
local function fire(remote, ...)
    windowCount = windowCount + 1
    pcall(function(...) remote:FireServer(...) end, ...)
end

----------------------------------------------------------------------
-- mining state
----------------------------------------------------------------------
local active           = false     -- master run flag (enabled AND started ok)
local curStage         = nil
local inZoneConfirmed  = false
local lastProbeTime    = 0
local probeFails       = 0
local nativeOnly       = false     -- fell back to game's own 0.5s loop
local BrokenWalls      = {}        -- [s][w]=true
local realMaxHP        = {}        -- [s][w]=max
local lastHP           = {}        -- ["s:w"]=hp
local pendingHits      = {}        -- ["s:w"]=n
local minHP            = {}        -- ["s:w"]=lowest seen (stuck detection)
local lastProgress     = {}        -- ["s:w"]=clock of last HP drop
local dmgRatio         = CFG._dmgRatio or nil
local stuckStages      = {}        -- [s]=true
local deepestReached   = CFG._deepestReached or 0
local hitboxCache      = {}
local suspendMine      = false

local function K(s, w) return s .. ":" .. w end
local function estDmg() return math.max(1, (dmgRatio or 1) * (Data.Strength or 1)) end
local function nWalls(s)
    local st = StagesList[s]
    if not (st and st.Stages) then return 3 end
    local n = 0; for _ in pairs(st.Stages) do n = n + 1 end
    return math.max(1, n)
end
local function wallMaxHP(s, w)
    if realMaxHP[s] and realMaxHP[s][w] then return realMaxHP[s][w] end
    local st = StagesList[s]
    if st and st.Stages and st.Stages[w] and st.Stages[w].MaxHealth then return st.Stages[w].MaxHealth end
    return 0
end
local function stageHardHP(s)
    local m = 0
    for w = 1, nWalls(s) do local hp = wallMaxHP(s, w); if hp > m then m = hp end end
    return m
end
local function getNextWall(s)
    BrokenWalls[s] = BrokenWalls[s] or {}
    for w = 1, nWalls(s) do if not BrokenWalls[s][w] then return w end end
    return nil
end
local function stageLuck(s) local st = StagesList[s]; return (st and st.Luck) or s end

local function resolveHitbox(s)
    if hitboxCache[s] then return hitboxCache[s] end
    local st = StagesList[s]; if not st then return end
    local h = st.Hitbox
    if not h and st.Folder then h = st.Folder:FindFirstChild("Hitbox") end   -- hitbox lives under the stage Folder
    local part
    if typeof(h) == "Instance" then
        if h:IsA("BasePart") then part = h
        elseif h:IsA("Model") then part = h.PrimaryPart or h:FindFirstChildWhichIsA("BasePart")
        else part = h:FindFirstChildWhichIsA("BasePart", true) end
    end
    if not part and st.Folder then part = st.Folder:FindFirstChildWhichIsA("BasePart", true) end
    hitboxCache[s] = part
    return part
end

local function safeStandCFrame(s)
    local part = resolveHitbox(s); if not part then return end
    local c = part.Position
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { LocalPlayer.Character }
    local hit = Workspace:Raycast(c + Vector3.new(0, 14, 0), Vector3.new(0, -3000, 0), rp)
    local y = (hit and hit.Position.Y + 3) or c.Y
    return CFrame.new(c.X, y, c.Z)
end

local function ensurePickaxeTool()
    local c, _, hum = getChar()
    if not (c and hum) then return end
    local held = c:FindFirstChildWhichIsA("Tool")
    if held and held:GetAttribute("Pickaxe") then return end
    local function find(where)
        if not where then return end
        for _, t in ipairs(where:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("Pickaxe") then return t end
        end
    end
    local t = find(LocalPlayer:FindFirstChild("Backpack")) or find(c)
    if t then pcall(function() hum:EquipTool(t) end) end
end

local function anchorHRP(on)
    local _, hrp = getChar()
    if hrp then pcall(function() hrp.Anchored = on and CFG.anchorWhileMining or false end) end
end

local function setStage(s)
    if not s or not StagesList[s] then return end
    curStage = s
    inZoneConfirmed = false
    lastProbeTime = os.clock()
    local _, hrp = getChar()
    if not hrp then return end
    local cf = safeStandCFrame(s)
    if cf then
        pcall(function()
            hrp.Anchored = false
            hrp.CFrame = cf
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
    end
    safeDelay(CFG.settleDelay, function()
        if unloaded or not active or curStage ~= s then return end
        ensurePickaxeTool()
        if CFG.anchorWhileMining then anchorHRP(true) end
        local w = getNextWall(s) or 1
        fire(R.HitWall, s, w)          -- probe; confirmed via UpdateWallHealth/BreakWall
    end)
end

local function feasible(s)
    if stuckStages[s] then return false end
    local hits = stageHardHP(s) / estDmg()
    local rate = math.min(CFG.maxHitRate, budgetLeft() > 0 and CFG.totalBudget or CFG.maxHitRate)
    if rate <= 0 then rate = CFG.maxHitRate end
    return hits <= CFG.H_max and (hits / rate) <= CFG.T_max, hits
end

local function chooseStage()
    local deepest = 1
    for s = 1, STAGE_N do if feasible(s) then deepest = s end end
    -- respect progression: only step one stage past what we've actually cleared
    local target = math.min(deepest, deepestReached + 1)
    if target < 1 then target = 1 end
    return target
end

local function reselectStage()
    if not (active and CFG.autoMine) or nativeOnly then return end
    local tgt = chooseStage()
    if tgt ~= curStage then setStage(tgt) end
end

----------------------------------------------------------------------
-- server -> client listeners (all pcall-guarded)
----------------------------------------------------------------------
local lootCount = 0

conn(Cli:WaitForChild("UpdateWallHealth").OnClientEvent, function(s, w, hp, max)
    pcall(function()
        realMaxHP[s] = realMaxHP[s] or {}; realMaxHP[s][w] = max
        local k = K(s, w)
        if hp >= max then
            BrokenWalls[s] = BrokenWalls[s] or {}; BrokenWalls[s][w] = nil  -- fresh / regenerated
        end
        if lastHP[k] and hp < lastHP[k] and (pendingHits[k] or 0) > 0 then
            local perHit = (lastHP[k] - hp) / pendingHits[k]
            local r = perHit / math.max(1, Data.Strength or 1)
            dmgRatio = dmgRatio and (0.75 * dmgRatio + 0.25 * r) or r
            CFG._dmgRatio = dmgRatio
        end
        if not minHP[k] or hp < minHP[k] then minHP[k] = hp; lastProgress[k] = os.clock() end
        lastHP[k] = hp; pendingHits[k] = 0
        if s == curStage then inZoneConfirmed = true; probeFails = 0 end
    end)
end)

conn(Cli:WaitForChild("BreakWall").OnClientEvent, function(s, w, broken)
    pcall(function()
        BrokenWalls[s] = BrokenWalls[s] or {}
        BrokenWalls[s][w] = broken and true or nil
        lastHP[K(s, w)] = nil; pendingHits[K(s, w)] = 0; minHP[K(s, w)] = nil
        if broken then
            if s > deepestReached then deepestReached = s; CFG._deepestReached = s end
        end
        if s == curStage then inZoneConfirmed = true; probeFails = 0 end
    end)
end)

conn(Cli:WaitForChild("LootAdded").OnClientEvent, function()
    lootCount = lootCount + 1
end)

do
    local lc = Cli:FindFirstChild("LootClaimed")
    if lc then conn(lc.OnClientEvent, function() lootCount = 0 end) end
end

-- anticheat / throttle notification watch
local warnText = ""
do
    local notif = Cli:FindFirstChild("Notification")
    if notif then
        conn(notif.OnClientEvent, function(_, text)
            pcall(function()
                local t = tostring(text):lower()
                if t:find("slow") or t:find("detect") or t:find("too fast") or t:find("ban") then
                    CFG.totalBudget = math.max(60, math.floor(CFG.totalBudget * 0.6))
                    CFG.maxHitRate  = math.min(CFG.maxHitRate, CFG.totalBudget)
                    warnText = "throttled: " .. tostring(text)
                    saveConfig()
                end
            end)
        end)
    end
end

----------------------------------------------------------------------
-- mining + click hot loop (single Heartbeat, anti-burst)
----------------------------------------------------------------------
local hitAccum, clickAccum = 0, 0
conn(RunService.Heartbeat, function(dt)
    if unloaded or not active then return end
    if dt > 0.5 then dt = 0.5 end

    -- position hold
    if CFG.autoMine and curStage and not suspendMine then
        local _, hrp = getChar()
        local part = resolveHitbox(curStage)
        if hrp and part and not hrp.Anchored then
            if (hrp.Position - part.Position).Magnitude > CFG.holdRadius then
                pcall(function() hrp.CFrame = safeStandCFrame(curStage) or hrp.CFrame; hrp.AssemblyLinearVelocity = Vector3.zero end)
            end
        end
    end

    -- in-zone confirm watchdog
    if CFG.autoMine and curStage and not suspendMine and not inZoneConfirmed and not nativeOnly then
        if os.clock() - lastProbeTime > 1.5 then
            probeFails = probeFails + 1
            if probeFails >= 5 then
                nativeOnly = true
                warnText = "in-zone probe failed -> native mining + click only"
            else
                setStage(curStage)
            end
        end
    end

    local maxPerTick = math.max(1, math.ceil(CFG.totalBudget * 0.12))
    local budget = math.min(maxPerTick, budgetLeft())
    if budget <= 0 then return end

    -- HitWall: only what still breaks the current wall, only when confirmed in-zone
    if CFG.autoMine and curStage and inZoneConfirmed and not suspendMine and not nativeOnly then
        local w = getNextWall(curStage)
        if w then
            local k = K(curStage, w)
            -- stuck-wall detection: hits landing but HP not dropping
            if (pendingHits[k] or 0) > 0 and lastProgress[k] and os.clock() - lastProgress[k] > CFG.stuckTimeout then
                stuckStages[curStage] = true
                warnText = "stage " .. curStage .. " stuck -> retreating"
                safeDelay(60, function() stuckStages[curStage] = false end)
                setStage(chooseStage())
            else
                hitAccum = hitAccum + CFG.maxHitRate * dt
                local knownHP = lastHP[k] or stageHardHP(curStage)
                local needed = math.ceil(knownHP / estDmg()) + 2 - (pendingHits[k] or 0)
                local n = math.min(math.floor(hitAccum), needed, budget)
                if n > 0 then
                    for _ = 1, n do fire(R.HitWall, curStage, w); pendingHits[k] = (pendingHits[k] or 0) + 1 end
                    hitAccum = hitAccum - n
                    budget = budget - n
                end
            end
        end
    end

    -- Click soaks remaining budget -> Strength (also rebirth-level progress)
    if CFG.autoClick and budget > 0 then
        clickAccum = clickAccum + CFG.maxClickRate * dt
        local n = math.min(math.floor(clickAccum), budget)
        if n > 0 then
            for _ = 1, n do fire(R.Click) end
            clickAccum = clickAccum - n
        end
    end
    if hitAccum > CFG.maxHitRate then hitAccum = CFG.maxHitRate end
    if clickAccum > CFG.maxClickRate then clickAccum = CFG.maxClickRate end
end)

----------------------------------------------------------------------
-- selling subsystem
----------------------------------------------------------------------
local backpackSize = function() return Data.BackpackSize or 3 end
local function full() return lootCount >= math.ceil(backpackSize() * CFG.sellFraction) end
local selling = false
local sellFails = 0

local function doSell()
    local before = Data.Cash or 0
    local mode = CFG._sellMode

    if mode ~= "surface" then                       -- try in-place first
        fire(R.SellAllLoot)
        if waitUntil(function() return (Data.Cash or 0) > before or lootCount == 0 end, 1.2) then
            if mode == "auto" then CFG._sellMode = "inplace"; saveConfig() end
            lootCount = 0; sellFails = 0
            return true
        end
    end

    -- surface round-trip
    local _, hrp = getChar()
    local back = hrp and hrp.CFrame
    fire(R.GotoSurface)
    task.wait(0.5)
    fire(R.SellAllLoot)
    local sold = waitUntil(function() return (Data.Cash or 0) > before or lootCount == 0 end, 1.5)
    if sold and CFG._sellMode == "auto" then CFG._sellMode = "surface"; saveConfig() end
    -- return to mining stage
    if active and curStage then
        setStage(curStage)
    elseif back then
        local _, hrp2 = getChar(); if hrp2 then pcall(function() hrp2.CFrame = back end) end
    end
    if sold then lootCount = 0; sellFails = 0; return true end

    sellFails = sellFails + 1
    if sellFails % 3 == 0 then                       -- escalate: flip mode + warn
        CFG._sellMode = (CFG._sellMode == "surface") and "inplace" or "surface"
        warnText = "sell failing -> mode " .. CFG._sellMode
        saveConfig()
    end
    return false
end

local function requestSell()
    if selling then return end
    selling = true
    suspendMine = true
    local ok = pcall(doSell)
    suspendMine = false                               -- always released
    selling = false
    return ok
end

----------------------------------------------------------------------
-- spending subsystem (backoff + session blacklist)
----------------------------------------------------------------------
local failCount = {}      -- key -> misses
local blacklist = {}      -- key -> true
local function noteFail(key)
    failCount[key] = (failCount[key] or 0) + 1
    if failCount[key] >= 4 then blacklist[key] = true end
end
local function noteOk(key) failCount[key] = 0 end

local function amult(id) return (id and AURA[id] and AURA[id].mult) or 1 end

local function backpackCost(size)
    if UpgradesHelper then local ok, c = pcall(function() return UpgradesHelper:GetBackpackUpgradeCost(size) end); if ok and type(c) == "number" then return c end end
    if size == 3 then return 180000 end   -- known anchor
end
local function walkspeedCost(extra)
    if UpgradesHelper then local ok, c = pcall(function() return UpgradesHelper:GetWalkspeedUpgradeCost(extra) end); if ok and type(c) == "number" then return c end end
    if extra == 0 then return 10000 end   -- known anchor
end

local rebirthBuffer = 0
local rebirthFails = 0

local function decideSpend()
    local Cash = Data.Cash or 0
    local eqPickStr = (Data.EquippedPickaxeId and PICK[Data.EquippedPickaxeId] and PICK[Data.EquippedPickaxeId].str) or 0
    local eqAuraMult = amult(Data.EquippedAuraId)

    -- 1) rebirth (free) when eligible
    if CFG.autoRebirth then
        local maxReb = CFG.rebirthStopLevel or 0   -- interpreted as max rebirths (0 = unlimited)
        if (maxReb == 0 or (Data.Rebirths or 0) < maxReb)
           and getLevel(Data.Strength) >= rebirthGate(Data.Rebirths or 0) + rebirthBuffer then
            return { act = "rebirth" }
        end
    end

    -- 2) re-equip best owned (free) - post rebirth / respawn safety
    local boP, boPs = bestOwned(PICK, Data.Pickaxes, "str")
    if boP and boPs > eqPickStr then return { act = "equipPick", id = boP } end
    local boA, boAm = bestOwned(AURA, Data.Auras, "mult")
    if boA and boAm > eqAuraMult then return { act = "equipAura", id = boA } end

    -- 3) buy top affordable pickaxe upgrade
    if CFG.buyPickaxes then
        local base = math.max(eqPickStr, boPs or 0)
        local pick, pickStr
        for id, d in pairs(PICK) do
            if not blacklist["buyPick:" .. id] and d.price <= Cash and d.str > base then
                if not pickStr or d.str > pickStr then pick, pickStr = id, d.str end
            end
        end
        if pick then return { act = "buyPick", id = pick } end
    end

    -- 4) buy aura only if no pickaxe affordable and cheap relative to cash
    if CFG.buyAuras then
        local base = math.max(eqAuraMult, boAm or 1)
        local aura, am
        for id, d in pairs(AURA) do
            if not blacklist["buyAura:" .. id] and not containerHas(Data.Auras, id)
               and d.price <= CFG.auraFraction * Cash and d.mult > base then
                if not am or d.mult > am then aura, am = id, d.mult end
            end
        end
        if aura then return { act = "buyAura", id = aura } end
    end

    -- 5) backpack when abundant (gated on real cost so it never thrashes)
    if CFG.buyBackpack and (Data.BackpackSize or 3) < math.min(15, CFG.maxBackpack) then
        local cost = backpackCost(Data.BackpackSize or 3)
        if cost and Cash >= CFG.backpackAbundance * cost then return { act = "backpack" } end
    end
    -- 6) walkspeed (walk-mode only)
    if CFG.buyWalkspeed and (Data.ExtraWalkSpeed or 0) < CFG.maxExtraWalkspeed then
        local cost = walkspeedCost(Data.ExtraWalkSpeed or 0)
        if cost and Cash >= cost then return { act = "walkspeed" } end
    end
    return nil
end

local function applySpend(a)
    if a.act == "rebirth" then
        if lootCount > 0 then pcall(requestSell) end
        local before = Data.Rebirths or 0
        fire(R.Rebirth, "Rebirth")
        if not waitUntil(function() return (Data.Rebirths or 0) > before end, 2) then
            -- maybe surface-gated: try once from surface
            fire(R.GotoSurface); task.wait(0.5); fire(R.Rebirth, "Rebirth")
            waitUntil(function() return (Data.Rebirths or 0) > before end, 2)
        end
        if (Data.Rebirths or 0) > before then
            rebirthBuffer, rebirthFails = 0, 0
            local bp = bestOwned(PICK, Data.Pickaxes, "str")
            if bp and Data.EquippedPickaxeId ~= bp then fire(R.EquipPickaxe, bp) end
            local ba = bestOwned(AURA, Data.Auras, "mult")
            if ba and Data.EquippedAuraId ~= ba then fire(R.EquipAura, ba) end
            ensurePickaxeTool()
            reselectStage()
        else
            rebirthFails = rebirthFails + 1
            rebirthBuffer = math.min(rebirthBuffer + 1, 5)
            if rebirthFails >= 6 then warnText = "rebirth rejected repeatedly" end
        end

    elseif a.act == "equipPick" then
        fire(R.EquipPickaxe, a.id); waitUntil(function() return Data.EquippedPickaxeId == a.id end, 1)

    elseif a.act == "equipAura" then
        fire(R.EquipAura, a.id); waitUntil(function() return Data.EquippedAuraId == a.id end, 1)

    elseif a.act == "buyPick" then
        local key = "buyPick:" .. a.id
        if not containerHas(Data.Pickaxes, a.id) then
            local c0 = Data.Cash or 0
            fire(R.PurchasePickaxe, a.id, "Cash")
            if not waitUntil(function() return containerHas(Data.Pickaxes, a.id) end, 1.5) then
                if (Data.Cash or 0) >= c0 then noteFail(key) end   -- cash didn't drop -> real miss
                return
            end
        end
        fire(R.EquipPickaxe, a.id)
        waitUntil(function() return Data.EquippedPickaxeId == a.id end, 1)
        noteOk(key); reselectStage()

    elseif a.act == "buyAura" then
        local key = "buyAura:" .. a.id
        if not containerHas(Data.Auras, a.id) then
            fire(R.PurchaseAura, a.id)               -- never on an owned aura (smart-toggle unequips)
            if not waitUntil(function() return containerHas(Data.Auras, a.id) end, 1.5) then noteFail(key); return end
        end
        if Data.EquippedAuraId ~= a.id then
            fire(R.EquipAura, a.id); waitUntil(function() return Data.EquippedAuraId == a.id end, 1)
        end
        noteOk(key)

    elseif a.act == "backpack" then
        local s0 = Data.BackpackSize or 0
        fire(R.UpgradeSlot, "Cash")
        waitUntil(function() return (Data.BackpackSize or 0) > s0 end, 1)   -- affordability pre-gated; retry later if it misses

    elseif a.act == "walkspeed" then
        local w0 = Data.ExtraWalkSpeed or 0
        fire(R.UpgradeWalkspeed, "Cash")
        waitUntil(function() return (Data.ExtraWalkSpeed or 0) > w0 end, 1)
    end
end

----------------------------------------------------------------------
-- supervisor (control loop, ~0.6s) - one action per tick
----------------------------------------------------------------------
task.spawn(function()
    local ticks = 0
    while not unloaded do
        if active then
            local ok, err = pcall(function()
                if not Data or not replica then acquireReplica() end
                -- full backpack preempts everything (a full pack halts income)
                if CFG.autoSell and full() then
                    requestSell()
                elseif CFG.autoSpend then
                    local a = decideSpend()
                    if a then applySpend(a) end
                end
                reselectStage()
            end)
            if not ok then warnText = "supervisor: " .. tostring(err) end
        end
        ticks = ticks + 1
        if ticks % 20 == 0 then pcall(saveConfig) end   -- persist learned dmgRatio / deepestReached
        task.wait(0.6)
    end
end)

-- event-driven sell backstop (fires the instant a drop fills the pack)
do
    local la = Cli:FindFirstChild("LootAdded")
    if la then conn(la.OnClientEvent, function()
        if active and CFG.autoSell and full() then task.spawn(function() pcall(requestSell) end) end
    end) end
end

----------------------------------------------------------------------
-- character recovery
----------------------------------------------------------------------
conn(LocalPlayer.CharacterAdded, function(c)
    c:WaitForChild("HumanoidRootPart", 10)
    local hum = c:FindFirstChildWhichIsA("Humanoid")
    suspendMine = false
    task.wait(0.4)
    ensurePickaxeTool()
    if active and curStage and CFG.autoMine and not nativeOnly then
        inZoneConfirmed = false
        setStage(curStage)
    end
end)

----------------------------------------------------------------------
-- anti-afk (always on)
----------------------------------------------------------------------
conn(LocalPlayer.Idled, function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

----------------------------------------------------------------------
-- teleport survival (re-run from file on in-experience server hops)
----------------------------------------------------------------------
if queueTeleport then
    conn(LocalPlayer.OnTeleport, function(state)
        if state == Enum.TeleportState.Started and not unloaded then
            local path = getgenv().MinePerClick_path or "+1 Mine Per Click.lua"
            pcall(function()
                queueTeleport('local ok,src=pcall(function() return readfile("' .. path .. '") end); if ok and src then local f=loadstring(src); if f then f() end end')
            end)
        end
    end)
end

----------------------------------------------------------------------
-- group reward (one-time, at startup)
----------------------------------------------------------------------
safeDelay(4, function()
    if CFG.claimGroupReward and not (Data and Data.ClaimedFreeReward) then
        pcall(function() fire(R.GroupReward) end)
    end
end)

----------------------------------------------------------------------
-- warmup: seed damage ratio at a trivial stage, then start engine
----------------------------------------------------------------------
local function warmupAndStart()
    if STAGE_N == 0 then
        nativeOnly = true
        warnText = "no StagesList -> click only"
    else
        -- seed dmgRatio at a guaranteed-trivial shallow stage
        local seed = math.min(3, STAGE_N)
        local _, hrp = getChar()
        if hrp then
            local cf = safeStandCFrame(seed)
            if cf then pcall(function() hrp.CFrame = cf; hrp.AssemblyLinearVelocity = Vector3.zero end) end
        end
        ensurePickaxeTool()
        task.wait(CFG.settleDelay)
        local w = getNextWall(seed) or 1
        for _ = 1, 10 do fire(R.HitWall, seed, w); task.wait(0.06) end
        task.wait(0.4)
    end
    active = true
    if not nativeOnly then reselectStage() end
end

local function setEnabled(on)
    CFG.enabled = on and true or false
    saveConfig()
    if on then
        if not active then task.spawn(warmupAndStart) end
    else
        active = false
        suspendMine = false
        anchorHRP(false)
    end
end

----------------------------------------------------------------------
-- GUI (Rayfield, house style) - throttled meters, no background blur
----------------------------------------------------------------------
local Rayfield
local guiOk = pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

local dash = {}
if guiOk and Rayfield then
    setIdentity()
    local Window = Rayfield:CreateWindow({
        Name = "tg: @sigmatik323",
        LoadingTitle = "+1 Mine Per Click",
        LoadingSubtitle = "by sigmatik323",
        ConfigurationSaving = { Enabled = false },
        KeySystem = false,
    })

    -- DASHBOARD
    local T = Window:CreateTab("⛏️ Dashboard", 4483362458)
    T:CreateToggle({ Name = "ENABLE (master)", CurrentValue = CFG.enabled, Flag = "mpc_enabled",
        Callback = function(v) setEnabled(v) end })
    dash.phase   = T:CreateLabel("Phase: idle")
    dash.stage   = T:CreateLabel("Stage: -")
    dash.strength= T:CreateLabel("Strength: -")
    dash.level   = T:CreateLabel("Level: -")
    dash.cash    = T:CreateLabel("Cash: -")
    dash.reb     = T:CreateLabel("Rebirths: -")
    dash.rate    = T:CreateLabel("Calls/sec: -")
    dash.pack    = T:CreateLabel("Backpack: -")
    dash.warn    = T:CreateLabel("Status: ok")

    -- MINING
    local M = Window:CreateTab("Mining", 4483362458)
    M:CreateToggle({ Name = "Auto Mine", CurrentValue = CFG.autoMine, Flag = "mpc_mine",
        Callback = function(v) CFG.autoMine = v; saveConfig() end })
    M:CreateToggle({ Name = "Auto Click (grow strength)", CurrentValue = CFG.autoClick, Flag = "mpc_click",
        Callback = function(v) CFG.autoClick = v; saveConfig() end })
    M:CreateToggle({ Name = "Anchor while mining", CurrentValue = CFG.anchorWhileMining, Flag = "mpc_anchor",
        Callback = function(v) CFG.anchorWhileMining = v; saveConfig(); if not v then anchorHRP(false) end end })
    M:CreateSlider({ Name = "Max HitWall rate", Range = {5, 380}, Increment = 5, CurrentValue = CFG.maxHitRate, Flag = "mpc_hr",
        Callback = function(v) CFG.maxHitRate = v; saveConfig() end })
    M:CreateSlider({ Name = "Max Click rate", Range = {5, 380}, Increment = 5, CurrentValue = CFG.maxClickRate, Flag = "mpc_cr",
        Callback = function(v) CFG.maxClickRate = v; saveConfig() end })
    M:CreateSlider({ Name = "Max wall break time (s)", Range = {2, 20}, Increment = 1, CurrentValue = CFG.T_max, Flag = "mpc_tmax",
        Callback = function(v) CFG.T_max = v; saveConfig() end })
    M:CreateButton({ Name = "Re-probe zone / re-teleport", Callback = function()
        if active and curStage then inZoneConfirmed = false; probeFails = 0; nativeOnly = false; setStage(curStage) end end })

    -- ECONOMY
    local E = Window:CreateTab("Economy", 4483362458)
    E:CreateToggle({ Name = "Auto Spend", CurrentValue = CFG.autoSpend, Flag = "mpc_spend",
        Callback = function(v) CFG.autoSpend = v; saveConfig() end })
    E:CreateToggle({ Name = "Auto Rebirth", CurrentValue = CFG.autoRebirth, Flag = "mpc_reb",
        Callback = function(v) CFG.autoRebirth = v; saveConfig() end })
    E:CreateToggle({ Name = "Buy Pickaxes", CurrentValue = CFG.buyPickaxes, Flag = "mpc_bp",
        Callback = function(v) CFG.buyPickaxes = v; saveConfig() end })
    E:CreateToggle({ Name = "Buy Auras", CurrentValue = CFG.buyAuras, Flag = "mpc_ba",
        Callback = function(v) CFG.buyAuras = v; saveConfig() end })
    E:CreateToggle({ Name = "Buy Backpack", CurrentValue = CFG.buyBackpack, Flag = "mpc_bbp",
        Callback = function(v) CFG.buyBackpack = v; saveConfig() end })
    E:CreateToggle({ Name = "Buy Walkspeed", CurrentValue = CFG.buyWalkspeed, Flag = "mpc_bws",
        Callback = function(v) CFG.buyWalkspeed = v; saveConfig() end })
    E:CreateSlider({ Name = "Aura buy fraction (of cash)", Range = {0, 100}, Increment = 5, Suffix = "%", CurrentValue = CFG.auraFraction * 100, Flag = "mpc_af",
        Callback = function(v) CFG.auraFraction = v / 100; saveConfig() end })
    E:CreateInput({ Name = "Max rebirths (0 = unlimited)", CurrentValue = tostring(CFG.rebirthStopLevel), RemoveTextAfterFocusLost = false, Flag = "mpc_rsl",
        Callback = function(t) CFG.rebirthStopLevel = tonumber(t) or 0; saveConfig() end })
    dash.nextbuy = E:CreateLabel("Next: -")

    -- SELLING
    local S = Window:CreateTab("Selling", 4483362458)
    S:CreateToggle({ Name = "Auto Sell", CurrentValue = CFG.autoSell, Flag = "mpc_sell",
        Callback = function(v) CFG.autoSell = v; saveConfig() end })
    S:CreateToggle({ Name = "Claim Group Reward", CurrentValue = CFG.claimGroupReward, Flag = "mpc_gr",
        Callback = function(v) CFG.claimGroupReward = v; saveConfig() end })
    S:CreateButton({ Name = "Sell now", Callback = function() task.spawn(function() pcall(requestSell) end) end })
    dash.sellmode = S:CreateLabel("Sell mode: " .. CFG._sellMode)

    -- BUDGET
    local B = Window:CreateTab("Budget", 4483362458)
    B:CreateSlider({ Name = "Total budget (calls/sec, <400)", Range = {40, 395}, Increment = 5, CurrentValue = CFG.totalBudget, Flag = "mpc_tb",
        Callback = function(v) CFG.totalBudget = math.min(395, v); saveConfig() end })
    dash.meter = B:CreateLabel("Combined: -")

    -- SETTINGS
    local G = Window:CreateTab("Settings", 4483362458)
    G:CreateParagraph({ Title = "Overnight survival", Content = "For guaranteed survival across server restarts, place this file in your executor's autoexec folder — it re-runs on every join and auto-starts (enabled state is saved)." })
    G:CreateButton({ Name = "Reset to defaults", Callback = function()
        for k, v in pairs(DEFAULTS) do CFG[k] = v end; saveConfig() end })
    G:CreateButton({ Name = "UNLOAD", Callback = function() if getgenv().MinePerClick.unload then getgenv().MinePerClick.unload() end end })
end

-- throttled GUI updater (~5 Hz, no formatting in the hot loop)
task.spawn(function()
    local function setL(lbl, txt) if lbl and lbl.Set then pcall(function() lbl:Set(txt) end) end end
    while not unloaded do
        if guiOk then
            local lvl = getLevel(Data.Strength or 0)
            local phase = not active and "idle" or (suspendMine and "selling") or (nativeOnly and "click-only")
                or (curStage and ("mining s" .. curStage)) or "warmup"
            setL(dash.phase,   "Phase: " .. phase .. (inZoneConfirmed and " ✓" or ""))
            setL(dash.stage,   "Stage: " .. tostring(curStage or "-") .. "  Luck x" .. (curStage and stageLuck(curStage) or "-") .. "  deepest " .. deepestReached)
            setL(dash.strength,"Strength: " .. string.format("%.0f", Data.Strength or 0) .. "  dmg/hit≈" .. string.format("%.0f", estDmg()))
            setL(dash.level,   "Level: " .. lvl .. " / rebirth@" .. rebirthGate(Data.Rebirths or 0))
            setL(dash.cash,    "Cash: " .. string.format("%.0f", Data.Cash or 0))
            setL(dash.reb,     "Rebirths: " .. tostring(Data.Rebirths or 0))
            setL(dash.rate,    "Calls this sec: " .. windowCount .. " / " .. CFG.totalBudget)
            setL(dash.meter,   "Combined: " .. windowCount .. "/" .. CFG.totalBudget .. " per sec")
            setL(dash.pack,    "Backpack: " .. lootCount .. " / " .. backpackSize())
            setL(dash.warn,    "Status: " .. (warnText == "" and "ok" or warnText))
            setL(dash.sellmode,"Sell mode: " .. CFG._sellMode)
            local a = active and decideSpend()
            setL(dash.nextbuy, "Next: " .. (a and (a.act .. (a.id and (" " .. a.id) or "")) or "save/none"))
        end
        task.wait(0.2)
    end
end)

----------------------------------------------------------------------
-- unload
----------------------------------------------------------------------
local function unload()
    if unloaded then return end
    unloaded = true
    active = false
    suspendMine = false
    pcall(saveConfig)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    anchorHRP(false)
    local _, hrp = getChar()
    if hrp then pcall(function() hrp.Anchored = false; hrp.AssemblyLinearVelocity = Vector3.zero end) end
    if guiOk and Rayfield then pcall(function() Rayfield:Destroy() end) end
    getgenv().MinePerClick = nil
end

getgenv().MinePerClick.unload = unload
getgenv().MinePerClick.CFG = CFG
getgenv().MinePerClick.setEnabled = setEnabled

----------------------------------------------------------------------
-- auto-start if previously enabled
----------------------------------------------------------------------
if CFG.enabled then
    task.spawn(function() task.wait(1); setEnabled(true) end)
end

if guiOk and Rayfield then pcall(function() Rayfield:Notify({ Title = "+1 Mine Per Click", Content = "Loaded. Toggle ENABLE on the Dashboard.", Duration = 5 }) end) end
