local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
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
    return ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:WaitForChild(name, 8)
end

----------------------------------------------------------------------
-- Game bindings
----------------------------------------------------------------------
local TGSMisc do
    local ok, m = pcall(function() return require(workspace.Lib.TGSMisc) end)
    TGSMisc = ok and m or nil
end

local Items, ItemCat do
    local ok, m  = pcall(function() return require(workspace.Lib.Items.TGSItems) end)
    Items = ok and m or nil
    local ok2, c = pcall(function() return require(workspace.Lib.Items.ItemCategoryEnum) end)
    ItemCat = ok2 and c or nil
end

local CURRENCY_TARGET = "Currency_Knivsta"   -- 3 Knivsta = 1 Energy
local RATIO           = 3
local GIVE_KEY        = "Default"

local function getConverter()
    local r = resolveRemote("CurrencyConverter_ExchangeCurrencyFund")
    if r then return r end
    if TGSMisc and TGSMisc.RemoteFunction then
        local ok, r2 = pcall(TGSMisc.RemoteFunction, "CurrencyConverter_ExchangeCurrencyFund")
        if ok and typeof(r2) == "Instance" then return r2 end
    end
    return nil
end

local function readCurrency(key)
    if not Items or not ItemCat then return nil end
    local ok, v = pcall(Items.GetItemInfo, LocalPlayer, ItemCat.Currency, key)
    if ok and type(v) == "number" then return v end
    return nil
end

local function readEnergy()  return readCurrency(GIVE_KEY) end
local function readKnivsta() return readCurrency("Knivsta") end

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
    for _, e in ipairs(SCALE) do
        if n >= e[1] then return string.format("%.2f%s", n / e[1], e[2]) end
    end
    return tostring(math.floor(n))
end

----------------------------------------------------------------------
-- Energy delivery (mint Knivsta via sign-bypass, then convert)
----------------------------------------------------------------------
local State = { busy = false, alive = true }

local function ensureKnivsta(cv, needKnivsta)
    if (readKnivsta() or 0) >= needKnivsta then return end
    local energy = readEnergy() or 0
    local mint = (energy + needKnivsta / RATIO + 1e6) * RATIO
    pcall(function() cv:InvokeServer(CURRENCY_TARGET, -mint) end)
    task.wait(0.6)
end

local function giveEnergy(target)
    local cv = getConverter()
    if not cv then return false, 0 end
    local needKnivsta = target * RATIO
    ensureKnivsta(cv, needKnivsta)
    local ok = pcall(function() cv:InvokeServer(CURRENCY_TARGET, needKnivsta) end)
    return ok, ok and target or 0
end

----------------------------------------------------------------------
-- Strength delivery — the remote name is salted with the JobId per
-- session, so it is computed from MD5(name .. JobId) at startup. A
-- namecall hook stays as an optional self-healing fallback.
----------------------------------------------------------------------
local StrengthRemote
local WorkoutSetRemote               -- server event that anchors our server-side copy
local hookActive = true
local onStrengthCaptured            -- assigned by the GUI once it exists

local function setStrengthRemote(remote)
    local wasEmpty = (StrengthRemote == nil)
    StrengthRemote = remote
    if wasEmpty and onStrengthCaptured then pcall(onStrengthCaptured) end
end

-- Learn the training remote from the game's own call: the instant the player
-- lifts once, the game fires InvokeServer(amount, "Default") on its randomly
-- named RemoteFunction. We grab that exact object and reuse it for any amount,
-- so a changed name after a rejoin / new training spot fixes itself on the next lift.
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

-- Primary path: resolve the training remote directly by its hashed name,
-- so it is ready the instant the GUI opens on any executor. The namecall
-- hook above stays as a self-healing fallback if the name ever differs.
do
    local r = resolveRemote("StrongMan_UpgradeStrength")
    if r then setStrengthRemote(r) end
end

-- The server grants strength only while PrimaryPart.Anchored is true, so we
-- never drive the game's workout state machine (that desync left the dumbbell
-- pose stuck). We PRESERVE the original anchor state: already working out →
-- nothing changes, the workout keeps going; otherwise we briefly anchor, grant,
-- then restore exactly as it was.
--
-- The server also SUMS the cost of every strength level it grants, looping once
-- per requested workout-count, and once more per rebirth tier; a single huge
-- count makes it loop tens of millions of times and freezes/pings the server.
-- We cap each call to a measured no-freeze budget of cost-loop iterations (the
-- inner loop scales with rebirth, so we divide it out) and deliver the full
-- requested total across cooldown-spaced calls — the server never blocks long,
-- and progress is shown live. ~4M iterations/call measured at well under 100ms.
local STRENGTH_CALL_BUDGET = 4000000

local function readRebirth()
    if Items and ItemCat then
        local ok, v = pcall(Items.GetItemInfo, LocalPlayer, ItemCat.Stat, "Rebirth")
        if ok and type(v) == "number" then return v end
    end
    return 0
end

local function giveStrength(target, onProgress)
    local remote = StrengthRemote
    if not remote then return false, 0, true end
    local char = LocalPlayer.Character
    local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))
    local wasAnchored = root and root.Anchored
    if root and not wasAnchored then
        root.Anchored = true
        task.wait(0.12)
    end

    local affordIters = math.max(1, math.min(math.floor(readRebirth() * 0.01), 50000))
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

    if root and not wasAnchored then root.Anchored = false end
    return delivered > 0, delivered
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

local ACCENT = Color3.fromRGB(34, 197, 94)
local STR    = Color3.fromRGB(249, 168, 64)
local GOOD   = Color3.fromRGB(120, 255, 160)
local WARN   = Color3.fromRGB(255, 190, 90)
local BAD    = Color3.fromRGB(255, 110, 110)
local MUTED  = Color3.fromRGB(150, 160, 185)

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
window.Size = UDim2.fromOffset(330, 328)
window.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
window.BorderSizePixel = 0
window.Parent = gui
Instance.new("UICorner", window).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke", window)
stroke.Thickness = 1.5
stroke.Color = ACCENT
stroke.Transparency = 0.25

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
title.TextColor3 = Color3.fromRGB(235, 240, 250)
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
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(16, 288)
status.Size = UDim2.new(1, -32, 0, 28)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.TextSize = 14
status.TextColor3 = MUTED
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true
status.Text = "Готов к выдаче"
status.Parent = window

local function setStatus(text, color)
    status.Text = text
    status.TextColor3 = color or MUTED
end

----------------------------------------------------------------------
-- Behaviour
----------------------------------------------------------------------
local function runTask(box, btn, label, unit, worker)
    if State.busy then return end
    local target = parseAmount(box.Text)
    if not target then
        setStatus("Не понял число. Примеры: 1k · 1000 · 1sx", WARN)
        return
    end
    State.busy = true
    btn.Text = "Выдаю..."
    setStatus("Выдаю " .. fmt(target) .. " " .. unit .. "...", ACCENT)
    task.spawn(function()
        local ok, given, needCapture = worker(target, function(done)
            setStatus("Выдаю " .. unit .. "… " .. fmt(done) .. " / " .. fmt(target), ACCENT)
        end)
        if ok then
            setStatus("Готово: +" .. fmt(given) .. " " .. unit .. " ✅", GOOD)
        elseif needCapture then
            setStatus("Покачайся 1 раз — ловлю remote, потом жми снова", WARN)
        else
            setStatus("Не вышло — remote не найден / отказал", BAD)
        end
        btn.Text = label
        State.busy = false
    end)
end

local function makeRow(yPrompt, ru, en, btnLabel, btnColor, unit, worker, defaultText)
    local p = Instance.new("TextLabel")
    p.Position = UDim2.fromOffset(16, yPrompt)
    p.Size = UDim2.new(1, -32, 0, 34)
    p.BackgroundTransparency = 1
    p.Font = Enum.Font.GothamSemibold
    p.TextSize = 14
    p.TextColor3 = Color3.fromRGB(225, 232, 245)
    p.TextXAlignment = Enum.TextXAlignment.Left
    p.TextYAlignment = Enum.TextYAlignment.Top
    p.RichText = true
    p.Text = ru .. "\n<font color=\"rgb(150,160,185)\">" .. en .. "</font>"
    p.Parent = window

    local box = Instance.new("TextBox")
    box.Position = UDim2.fromOffset(16, yPrompt + 36)
    box.Size = UDim2.new(1, -32, 0, 38)
    box.BackgroundColor3 = Color3.fromRGB(20, 26, 42)
    box.Font = Enum.Font.GothamMedium
    box.TextSize = 16
    box.TextColor3 = Color3.fromRGB(235, 240, 250)
    box.PlaceholderText = "1k · 1000 · 1sx"
    box.PlaceholderColor3 = MUTED
    box.Text = defaultText or ""
    box.ClearTextOnFocus = false
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Parent = window
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)
    local pad = Instance.new("UIPadding", box)
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    local bs = Instance.new("UIStroke", box)
    bs.Color = Color3.fromRGB(50, 60, 86)
    bs.Transparency = 0.2

    local btn = Instance.new("TextButton")
    btn.Position = UDim2.fromOffset(16, yPrompt + 80)
    btn.Size = UDim2.new(1, -32, 0, 36)
    btn.BackgroundColor3 = btnColor
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.TextColor3 = Color3.fromRGB(8, 16, 12)
    btn.Text = btnLabel
    btn.AutoButtonColor = true
    btn.Parent = window
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

    track(btn.MouseButton1Click:Connect(function() runTask(box, btn, btnLabel, unit, worker) end))
    track(box.FocusLost:Connect(function(enter) if enter then runTask(box, btn, btnLabel, unit, worker) end end))
end

makeRow(46, "Сколько выдать энергии?", "How much energy to give?",
    "Выдать энергию", ACCENT, "энергии", giveEnergy)

makeRow(166, "Сколько выдать силы?", "How much strength to give?",
    "Выдать силу", STR, "силы", giveStrength, "1111111")

onStrengthCaptured = function()
    setStatus("✅ Remote силы готов — можно выдавать", GOOD)
end

if StrengthRemote then
    setStatus("Готов к выдаче", MUTED)
else
    setStatus("Для силы: покачайся 1 раз, чтобы поймать remote", MUTED)
end

----------------------------------------------------------------------
-- Unload
----------------------------------------------------------------------
local function unload()
    hookActive = false
    State.alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    if gui then gui:Destroy() end
end
track(closeBtn.MouseButton1Click:Connect(unload))

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
