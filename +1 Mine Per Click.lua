--[[
    +1 Mine Per Click  —  full progression autofarm
    tg: @sigmatik323

    Independent toggles (each runs on its own): Auto Click, Auto Mine (descend+collect+sell),
    Auto Rebirth, Auto Buy Pickaxe, Auto Buy Aura, Auto Upgrade Backpack/Walkspeed.
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
local CollectionService  = game:GetService("CollectionService")
local Workspace          = game:GetService("Workspace")
local LocalPlayer        = Players.LocalPlayer

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
-- config (each feature is an independent toggle)
----------------------------------------------------------------------
local DEFAULTS = {
    autoClick        = false,
    autoMine         = false,
    autoRebirth      = false,
    autoBuyPickaxe   = false,
    autoBuyAura      = false,
    autoBackpack     = false,
    autoWalkspeed    = false,

    totalBudget      = 350,   -- combined FireServer calls/sec (hard ceiling < 400)
    clickRate        = 250,   -- Click calls/sec
    hitRate          = 60,    -- extra HitWall calls/sec on tanky layers (native swing does the rest)

    H_max            = 400,   -- max hits to break a layer before a stage is "too deep"
    breakTimeout     = 12,    -- s to wait for a stage's layers before giving up/advancing
    collectHop       = 0.14,  -- s between ore-collection hops
    sellOnSurface    = true,  -- GotoSurface before SellAllLoot

    auraFraction     = 0.5,
    backpackAbundance= 2,
    maxBackpack      = 15,
    maxExtraWalkspeed= 25,
    maxRebirths      = 0,     -- 0 = unlimited

    _deepestReached  = 1,
    _bootTimes       = {},
}
local CFG = {}
for k, v in pairs(DEFAULTS) do CFG[k] = v end

local function mergeKnown(dst, src)   -- only accept keys that exist in DEFAULTS (drops stale/legacy config)
    for k, v in pairs(src) do if DEFAULTS[k] ~= nil then dst[k] = v end end
end
local function saveConfig()
    if not writefileFn then return end
    pcall(function()
        local ok, enc = pcall(HttpService.JSONEncode, HttpService, CFG)
        if ok then writefileFn(CONFIG_FILE .. ".tmp", enc); writefileFn(CONFIG_FILE, enc) end
    end)
end
local function loadConfig()
    if not (readfileFn and isfileFn and isfileFn(CONFIG_FILE)) then return end
    local ok, raw = pcall(readfileFn, CONFIG_FILE)
    if not ok or not raw then return end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if ok2 and type(data) == "table" then mergeKnown(CFG, data)
    else pcall(function() if writefileFn then writefileFn(CONFIG_FILE .. ".bad", raw) end end); saveConfig() end
end
loadConfig()

-- boot circuit breaker (avoid tight crash/rejoin loops overnight)
local nowEpoch = os.time()
do
    local recent = {}
    for _, t in ipairs(CFG._bootTimes or {}) do if nowEpoch - t < 300 then recent[#recent + 1] = t end end
    recent[#recent + 1] = nowEpoch
    CFG._bootTimes = recent
    if #recent > 6 then   -- safe mode: turn everything off
        for _, k in ipairs({ "autoClick","autoMine","autoRebirth","autoBuyPickaxe","autoBuyAura","autoBackpack","autoWalkspeed" }) do CFG[k] = false end
    end
    saveConfig()
end

----------------------------------------------------------------------
-- teardown scaffolding
----------------------------------------------------------------------
local unloaded = false
local conns = {}
local function conn(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end
local function safeDelay(t, fn) task.delay(t, function() if not unloaded then fn() end end) end

----------------------------------------------------------------------
-- game data + modules
----------------------------------------------------------------------
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Srv     = Remotes:WaitForChild("Server")
local Cli     = Remotes:WaitForChild("Client")
local function S_(n) return Srv:WaitForChild(n, 10) end
local R = {
    Click = S_("Click"), HitWall = S_("HitWall"), SellAllLoot = S_("SellAllLoot"),
    PurchasePickaxe = S_("PurchasePickaxe"), EquipPickaxe = S_("EquipPickaxe"),
    Rebirth = S_("Rebirth"), UpgradeSlot = S_("UpgradeSlot"), UpgradeWalkspeed = S_("UpgradeWalkspeed"),
    PurchaseAura = S_("PurchaseAura"), EquipAura = S_("EquipAura"),
    GotoSurface = S_("GotoSurface"), GroupReward = S_("GroupReward"),
}

local function reqByName(name)
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == name and d:IsA("ModuleScript") then
            local ok, m = pcall(require, d); if ok then return m end
        end
    end
end
local DataClient     = reqByName("DataClient")
local PickaxeList    = reqByName("PickaxeList") or {}
local AurasList      = reqByName("AurasList")   or {}
local UpgradesHelper = reqByName("UpgradesHelper")

local StageClient
do local ok, m = pcall(function() return require(ReplicatedStorage.Client.StageClient) end); if ok then StageClient = m end end
local StagesList
if StageClient then StagesList = StageClient.StagesList or StageClient.Stages end
StagesList = StagesList or reqByName("StagesList") or {}

local replica, Data
local function acquireReplica()
    if not DataClient then return end
    local ok, rep = pcall(function() return DataClient:GetReplica() end)
    if ok and rep and rep.Data then replica, Data = rep, rep.Data end
end
acquireReplica()
do local t0 = os.clock(); while not Data and os.clock() - t0 < 15 do task.wait(0.2); acquireReplica() end end
if not Data then Data = {} end

----------------------------------------------------------------------
-- catalogs (exact live ids) + level math
----------------------------------------------------------------------
local PICK = {}
for id, d in pairs(PickaxeList) do
    if type(d) == "table" and d.Price ~= nil and d.Strength and not d.GamepassId then PICK[id] = { price = d.Price, str = d.Strength } end
end
local AURA = {}
for id, d in pairs(AurasList) do
    if type(d) == "table" and d.Price and d.Multiplier then AURA[id] = { price = d.Price, mult = d.Multiplier } end
end
local STAGE_N = 0
for s in pairs(StagesList) do if type(s) == "number" and s > STAGE_N then STAGE_N = s end end

local LEVEL_CUM = { [1] = 0 }
do local band, cum = 45.0, 0
   for L = 1, 600 do cum = cum + math.floor(band); LEVEL_CUM[L + 1] = cum; band = band * 1.094 end
end
local function getLevel(str)
    str = str or 0; local lo, hi = 1, #LEVEL_CUM
    while lo < hi do local mid = math.floor((lo + hi + 1) / 2); if LEVEL_CUM[mid] <= str then lo = mid else hi = mid - 1 end end
    return lo
end
local function rebirthGate(r) return 25 * ((r or 0) + 1) end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function getChar()
    local c = LocalPlayer.Character; if not c then return end
    return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildWhichIsA("Humanoid")
end
local function waitUntil(pred, timeout)
    local t0 = os.clock()
    while not pred() do if os.clock() - t0 > (timeout or 2) then return false end; task.wait(0.05) end
    return true
end
local function containerHas(cont, id)
    if type(cont) ~= "table" then return false end
    for k, v in pairs(cont) do if v == id then return true end; if k == id and v then return true end end
    return false
end
local function bestOwned(catalog, cont, field)
    local best, bv = nil, -1
    if type(cont) == "table" then
        for k, v in pairs(cont) do
            local id = (type(v) == "string" and v) or (v == true and k) or nil
            if id and catalog[id] and catalog[id][field] > bv then best, bv = id, catalog[id][field] end
        end
    end
    return best, bv
end
local function backpackCost(size)
    if UpgradesHelper then local ok, c = pcall(function() return UpgradesHelper:GetBackpackUpgradeCost(size) end); if ok and type(c) == "number" then return c end end
    if size == 3 then return 180000 end
end
local function walkspeedCost(extra)
    if UpgradesHelper then local ok, c = pcall(function() return UpgradesHelper:GetWalkspeedUpgradeCost(extra) end); if ok and type(c) == "number" then return c end end
    if extra == 0 then return 10000 end
end

----------------------------------------------------------------------
-- shared budget (windowed hard cap)
----------------------------------------------------------------------
local windowStart, windowCount = os.clock(), 0
local function budgetLeft()
    local now = os.clock()
    if now - windowStart >= 1 then windowStart = now; windowCount = 0 end
    return CFG.totalBudget - windowCount
end
local function fire(remote, ...) windowCount = windowCount + 1; pcall(function(...) remote:FireServer(...) end, ...) end

----------------------------------------------------------------------
-- status (for the Stats tab)
----------------------------------------------------------------------
local status = { phase = "idle", stage = 0, warn = "", loot = 0 }
local lootCount = 0
do
    local la = Cli:FindFirstChild("LootAdded")
    if la then conn(la.OnClientEvent, function() lootCount = lootCount + 1 end) end
    local lc = Cli:FindFirstChild("LootClaimed")
    if lc then conn(lc.OnClientEvent, function() lootCount = 0 end) end
end
local function backpackCount() return math.max(lootCount, type(Data.Inventory) == "table" and #Data.Inventory or 0) end
local function backpackCap() return Data.BackpackSize or 3 end

----------------------------------------------------------------------
-- MINING  (verified recipe: raycast floor, force zone flags, damage == Strength)
----------------------------------------------------------------------
local function ensurePickaxeTool()
    local c, _, hum = getChar()
    if not (c and hum) then return end
    local held = c:FindFirstChildWhichIsA("Tool")
    if held and held:GetAttribute("Pickaxe") then return end
    local function find(where) if not where then return end for _, t in ipairs(where:GetChildren()) do if t:IsA("Tool") and t:GetAttribute("Pickaxe") then return t end end end
    local t = find(LocalPlayer:FindFirstChild("Backpack")) or find(c)
    if t then pcall(function() hum:EquipTool(t) end) end
end

-- Entering the mine: the server sets the Player attribute "IsInMine" (required for any HitWall to
-- register) when the character touches Workspace.Map.Markers.MineHitbox; that touch also drops us
-- at Stage 1. From there the game's own swing breaks the floor and we fall deeper on our own.
local MineHitbox
local function getMineHitbox()
    if MineHitbox and MineHitbox.Parent then return MineHitbox end
    local map = Workspace:FindFirstChild("Map")
    local markers = map and map:FindFirstChild("Markers")
    MineHitbox = markers and markers:FindFirstChild("MineHitbox")
    return MineHitbox
end
local function inMine() return LocalPlayer:GetAttribute("IsInMine") == true end
local firetouch = firetouchinterest or (syn and syn.firetouchinterest)
local function enterMine()
    local _, hrp = getChar(); if not hrp then return end
    local mh = getMineHitbox(); if not mh then return end
    if firetouch then pcall(function() firetouch(hrp, mh, 0); task.wait(); firetouch(hrp, mh, 1) end)
    else pcall(function() hrp.CFrame = mh.CFrame end) end
end

-- Ore is collected via each item's ProximityPrompt ("Pickup?"). Fire the enabled ones near us.
local fireprompt = fireproximityprompt or (syn and syn.fireproximityprompt)
local function collectOrePrompts()
    if not fireprompt then return end
    local _, hrp = getChar(); if not hrp then return end
    local S = StageClient and StageClient.CurrentStageId
    local root = (S and StagesList[S] and StagesList[S].Folder) or nil
    if not root then return end
    for _, d in ipairs(root:GetDescendants()) do
        if not CFG.autoMine or unloaded then break end
        if d:IsA("ProximityPrompt") and d.Enabled then
            local par = d.Parent; local pos
            if par and par:IsA("BasePart") then pos = par.Position
            elseif par and par:IsA("Model") then local ok, cf = pcall(function() return par:GetPivot() end); if ok then pos = cf.Position end end
            if pos and (pos - hrp.Position).Magnitude < 45 then pcall(function() fireprompt(d, d.HoldDuration or 0) end) end
        end
    end
end

local selling = false
local function sellTrip()
    if backpackCount() == 0 then return end
    selling = true
    status.phase = "selling"
    local before = Data.Cash or 0
    local _, hrp = getChar(); local back = hrp and hrp.CFrame
    if CFG.sellOnSurface then fire(R.GotoSurface); task.wait(0.6) end
    fire(R.SellAllLoot)
    if not waitUntil(function() return (Data.Cash or 0) > before or backpackCount() == 0 end, 1.5) and not CFG.sellOnSurface then
        fire(R.GotoSurface); task.wait(0.6); fire(R.SellAllLoot)
        waitUntil(function() return (Data.Cash or 0) > before or backpackCount() == 0 end, 1.5)
    end
    lootCount = 0
    selling = false
end
getgenv().MinePerClick.sellNow = function() task.spawn(function() pcall(sellTrip) end) end

----------------------------------------------------------------------
-- INDEPENDENT LOOPS
----------------------------------------------------------------------
local running = {}   -- guards so a loop isn't double-spawned
local function loop(name, body, period)
    if running[name] then return end
    running[name] = true
    task.spawn(function()
        while CFG[name] and not unloaded do
            local ok, err = pcall(body)
            if not ok then status.warn = name .. ": " .. tostring(err) end
            task.wait(period or 0.4)
        end
        running[name] = false
    end)
end

-- Auto Click: grow Strength (position-independent)
local clickAccum = 0
conn(RunService.Heartbeat, function(dt)
    if unloaded or not CFG.autoClick then clickAccum = 0; return end
    if dt > 0.3 then dt = 0.3 end
    clickAccum = clickAccum + CFG.clickRate * dt
    local n = math.min(math.floor(clickAccum), budgetLeft(), math.ceil(CFG.totalBudget * 0.15))
    if n > 0 then for _ = 1, n do fire(R.Click) end; clickAccum = clickAccum - n end
    if clickAccum > CFG.clickRate then clickAccum = CFG.clickRate end
end)

-- Auto Mine: enter the mine, let the game's own swing break the floor and drop us deeper, collect
-- ore via prompts, sell when full. No teleporting between stages, no manual HitWall (anticheat-safe).
local function mineBody()
    if selling then task.wait(0.4); return end
    local char, hrp, hum = getChar()
    if not (hrp and hum and hum.Health > 0) then task.wait(0.6); return end
    ensurePickaxeTool()
    if not inMine() then status.phase = "entering mine"; enterMine(); task.wait(0.8); return end
    if StageClient and StageClient.CurrentStageId then
        status.stage = StageClient.CurrentStageId
        if StageClient.CurrentStageId > (CFG._deepestReached or 1) then CFG._deepestReached = StageClient.CurrentStageId end
        if StageClient.IsMining ~= true then pcall(function() StageClient.IsMining = true end) end
    end
    status.phase = "mining"
    collectOrePrompts()
    if backpackCount() >= backpackCap() then
        sellTrip()
        if CFG.autoMine and not inMine() then enterMine() end
    end
    task.wait(0.5)
end

-- Auto Rebirth
local function rebirthBody()
    local maxR = CFG.maxRebirths or 0
    if maxR > 0 and (Data.Rebirths or 0) >= maxR then task.wait(2); return end
    if getLevel(Data.Strength) >= rebirthGate(Data.Rebirths or 0) then
        local before = Data.Rebirths or 0
        status.phase = "rebirth"
        fire(R.Rebirth, "Rebirth")
        if not waitUntil(function() return (Data.Rebirths or 0) > before end, 2) then
            fire(R.GotoSurface); task.wait(0.5); fire(R.Rebirth, "Rebirth")
            waitUntil(function() return (Data.Rebirths or 0) > before end, 2)
        end
        if (Data.Rebirths or 0) > before then
            local bp = bestOwned(PICK, Data.Pickaxes, "str"); if bp and Data.EquippedPickaxeId ~= bp then fire(R.EquipPickaxe, bp) end
            local ba = bestOwned(AURA, Data.Auras, "mult"); if ba and Data.EquippedAuraId ~= ba then fire(R.EquipAura, ba) end
            mineStage = 1
        end
    end
    task.wait(1)
end

-- Auto Buy Pickaxe
local function buyPickBody()
    local Cash = Data.Cash or 0
    local eq = (Data.EquippedPickaxeId and PICK[Data.EquippedPickaxeId] and PICK[Data.EquippedPickaxeId].str) or 0
    local bo, bos = bestOwned(PICK, Data.Pickaxes, "str")
    if bo and bos > eq then fire(R.EquipPickaxe, bo); return end
    local base, pick, ps = math.max(eq, bos or 0), nil, nil
    for id, d in pairs(PICK) do if d.price <= Cash and d.str > base and (not ps or d.str > ps) then pick, ps = id, d.str end end
    if pick then
        if not containerHas(Data.Pickaxes, pick) then fire(R.PurchasePickaxe, pick, "Cash"); waitUntil(function() return containerHas(Data.Pickaxes, pick) end, 1.2) end
        if containerHas(Data.Pickaxes, pick) then fire(R.EquipPickaxe, pick) end
    end
    task.wait(0.6)
end

-- Auto Buy Aura
local function buyAuraBody()
    local Cash = Data.Cash or 0
    local eq = (Data.EquippedAuraId and AURA[Data.EquippedAuraId] and AURA[Data.EquippedAuraId].mult) or 1
    local bo, bom = bestOwned(AURA, Data.Auras, "mult")
    if bo and (bom or 1) > eq then fire(R.EquipAura, bo); return end
    local base, aura, am = math.max(eq, bom or 1), nil, nil
    for id, d in pairs(AURA) do
        if not containerHas(Data.Auras, id) and d.price <= CFG.auraFraction * Cash and d.mult > base and (not am or d.mult > am) then aura, am = id, d.mult end
    end
    if aura then fire(R.PurchaseAura, aura); if waitUntil(function() return containerHas(Data.Auras, aura) end, 1.2) then if Data.EquippedAuraId ~= aura then fire(R.EquipAura, aura) end end end
    task.wait(0.8)
end

-- Auto Upgrade Backpack
local function backpackBody()
    if (Data.BackpackSize or 3) < math.min(15, CFG.maxBackpack) then
        local cost = backpackCost(Data.BackpackSize or 3)
        if cost and (Data.Cash or 0) >= CFG.backpackAbundance * cost then
            local s0 = Data.BackpackSize or 0; fire(R.UpgradeSlot, "Cash"); waitUntil(function() return (Data.BackpackSize or 0) > s0 end, 1)
        end
    end
    task.wait(1)
end

-- Auto Upgrade Walkspeed
local function walkspeedBody()
    if (Data.ExtraWalkSpeed or 0) < CFG.maxExtraWalkspeed then
        local cost = walkspeedCost(Data.ExtraWalkSpeed or 0)
        if cost and (Data.Cash or 0) >= cost then
            local w0 = Data.ExtraWalkSpeed or 0; fire(R.UpgradeWalkspeed, "Cash"); waitUntil(function() return (Data.ExtraWalkSpeed or 0) > w0 end, 1)
        end
    end
    task.wait(1)
end

local BODIES = {
    autoMine = mineBody, autoRebirth = rebirthBody, autoBuyPickaxe = buyPickBody,
    autoBuyAura = buyAuraBody, autoBackpack = backpackBody, autoWalkspeed = walkspeedBody,
}
local function startLoop(name) if BODIES[name] then loop(name, BODIES[name], 0.3) end end
local function setFeature(name, on)
    CFG[name] = on and true or false
    saveConfig()
    if on then startLoop(name) end
end
getgenv().MinePerClick.setFeature = setFeature

----------------------------------------------------------------------
-- notification anticheat watch
----------------------------------------------------------------------
do
    local notif = Cli:FindFirstChild("Notification")
    if notif then conn(notif.OnClientEvent, function(_, text)
        pcall(function()
            local t = tostring(text):lower()
            if t:find("slow") or t:find("detect") or t:find("too fast") or t:find("ban") then
                CFG.totalBudget = math.max(60, math.floor(CFG.totalBudget * 0.6)); status.warn = "throttled: " .. tostring(text); saveConfig()
            end
        end)
    end) end
end

----------------------------------------------------------------------
-- anti-afk + character recovery + teleport survival + group reward
----------------------------------------------------------------------
conn(LocalPlayer.Idled, function() pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end) end)
conn(LocalPlayer.CharacterAdded, function(c)
    c:WaitForChild("HumanoidRootPart", 10); task.wait(0.6)
    ensurePickaxeTool()   -- respawn lands us at the surface; mineBody re-enters the mine on its own
end)
if queueTeleport then
    conn(LocalPlayer.OnTeleport, function(state)
        if state == Enum.TeleportState.Started and not unloaded then
            local path = getgenv().MinePerClick_path or "+1 Mine Per Click.lua"
            pcall(function() queueTeleport('local ok,src=pcall(function() return readfile("' .. path .. '") end); if ok and src then local f=loadstring(src); if f then f() end end') end)
        end
    end)
end
safeDelay(4, function() if not (Data and Data.ClaimedFreeReward) then pcall(function() fire(R.GroupReward) end) end end)

local L = {}          -- Stats labels (populated by the GUI once it builds)
local Rayfield

----------------------------------------------------------------------
-- exports + background loops — defined BEFORE the GUI so a GUI hiccup can't drop them
----------------------------------------------------------------------
local function unload()
    if unloaded then return end
    unloaded = true
    pcall(saveConfig)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    local _, hrp = getChar()
    if hrp then pcall(function() hrp.Anchored = false; hrp.AssemblyLinearVelocity = Vector3.zero end) end
    if Rayfield then pcall(function() Rayfield:Destroy() end) end
    getgenv().MinePerClick = nil
end
getgenv().MinePerClick.unload = unload
getgenv().MinePerClick.CFG = CFG

task.spawn(function()   -- stats updater ~5 Hz (labels are nil-guarded until the GUI builds them)
    local function set(lbl, txt) if lbl then pcall(function() lbl:Set(txt) end) end end
    local function fmt(n) n = n or 0; if n >= 1e6 then return string.format("%.2fM", n / 1e6) elseif n >= 1e3 then return string.format("%.1fK", n / 1e3) end return string.format("%.0f", n) end
    while not unloaded do
        set(L.strength, "Strength: " .. fmt(Data.Strength))
        set(L.level,    "Level: " .. getLevel(Data.Strength or 0) .. "  (rebirth @ " .. rebirthGate(Data.Rebirths or 0) .. ")")
        set(L.cash,     "Cash: " .. fmt(Data.Cash))
        set(L.reb,      "Rebirths: " .. tostring(Data.Rebirths or 0))
        set(L.pick,     "Pickaxe: " .. tostring(Data.EquippedPickaxeId or "-"))
        set(L.aura,     "Aura: " .. tostring(Data.EquippedAuraId or "none"))
        set(L.stage,    "Mining stage: " .. (status.stage > 0 and status.stage or "-") .. " / deepest " .. (CFG._deepestReached or 1))
        set(L.pack,     "Backpack: " .. backpackCount() .. " / " .. backpackCap())
        set(L.calls,    "Calls this sec: " .. windowCount .. " / " .. CFG.totalBudget)
        set(L.phase,    "Phase: " .. status.phase)
        set(L.warn,     "Status: " .. (status.warn == "" and "ok" or status.warn))
        task.wait(0.2)
    end
end)
task.spawn(function() while not unloaded do task.wait(15); pcall(saveConfig) end end)   -- periodic save
for _, name in ipairs({ "autoMine","autoRebirth","autoBuyPickaxe","autoBuyAura","autoBackpack","autoWalkspeed" }) do
    if CFG[name] then startLoop(name) end                              -- auto-restore left-on features
end

----------------------------------------------------------------------
-- GUI (Rayfield). Fully pcall-guarded; Stats tab is LAST.
----------------------------------------------------------------------
local guiOk = pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
    setIdentity()
    local Window = Rayfield:CreateWindow({
        Name = "tg: @sigmatik323", LoadingTitle = "+1 Mine Per Click", LoadingSubtitle = "by sigmatik323",
        ConfigurationSaving = { Enabled = false }, KeySystem = false,
    })

    local function tog(tab, text, key)
        tab:CreateToggle({ Name = text, CurrentValue = CFG[key], Flag = "mpc_" .. key, Callback = function(v) setFeature(key, v) end })
    end

    pcall(function()   -- MINING
        local M = Window:CreateTab("⛏️ Mining", 4483362458)
        tog(M, "Auto Click (grow Strength)", "autoClick")
        tog(M, "Auto Mine (descend + collect + sell)", "autoMine")
        M:CreateSlider({ Name = "Click rate (calls/sec)", Range = {5, 380}, Increment = 5, CurrentValue = CFG.clickRate, Flag = "mpc_cr", Callback = function(v) CFG.clickRate = v; saveConfig() end })
    end)
    pcall(function()   -- ECONOMY
        local E = Window:CreateTab("💰 Economy", 4483362458)
        tog(E, "Auto Rebirth", "autoRebirth")
        tog(E, "Auto Buy Pickaxe", "autoBuyPickaxe")
        tog(E, "Auto Buy Aura", "autoBuyAura")
        tog(E, "Auto Upgrade Backpack", "autoBackpack")
        tog(E, "Auto Upgrade Walkspeed", "autoWalkspeed")
        E:CreateSlider({ Name = "Aura buy fraction of cash", Range = {0, 100}, Increment = 5, Suffix = "%", CurrentValue = CFG.auraFraction * 100, Flag = "mpc_af", Callback = function(v) CFG.auraFraction = v / 100; saveConfig() end })
        E:CreateSlider({ Name = "Max rebirths (0 = unlimited)", Range = {0, 50}, Increment = 1, CurrentValue = CFG.maxRebirths, Flag = "mpc_mr", Callback = function(v) CFG.maxRebirths = v; saveConfig() end })
    end)
    pcall(function()   -- SELLING
        local Se = Window:CreateTab("🧺 Selling", 4483362458)
        Se:CreateToggle({ Name = "Sell on surface (GotoSurface first)", CurrentValue = CFG.sellOnSurface, Flag = "mpc_sos", Callback = function(v) CFG.sellOnSurface = v; saveConfig() end })
        Se:CreateButton({ Name = "Sell now", Callback = function() getgenv().MinePerClick.sellNow() end })
    end)
    pcall(function()   -- BUDGET
        local B = Window:CreateTab("📊 Budget", 4483362458)
        B:CreateSlider({ Name = "Total budget (calls/sec, <400)", Range = {40, 395}, Increment = 5, CurrentValue = CFG.totalBudget, Flag = "mpc_tb", Callback = function(v) CFG.totalBudget = math.min(395, v); saveConfig() end })
    end)
    pcall(function()   -- SETTINGS
        local G = Window:CreateTab("⚙️ Settings", 4483362458)
        G:CreateParagraph({ Title = "Overnight survival", Content = "For survival across server restarts, place this file in your executor's autoexec folder — it re-runs on every join and restores your toggles." })
        G:CreateButton({ Name = "Reset to defaults", Callback = function() for k, v in pairs(DEFAULTS) do CFG[k] = v end; saveConfig() end })
        G:CreateButton({ Name = "UNLOAD", Callback = function() if getgenv().MinePerClick and getgenv().MinePerClick.unload then getgenv().MinePerClick.unload() end end })
    end)
    pcall(function()   -- STATS (LAST tab, per request)
        local T = Window:CreateTab("📈 Stats", 4483362458)
        L.strength = T:CreateLabel("Strength: -"); L.level = T:CreateLabel("Level: -"); L.cash = T:CreateLabel("Cash: -")
        L.reb = T:CreateLabel("Rebirths: -"); L.pick = T:CreateLabel("Pickaxe: -"); L.aura = T:CreateLabel("Aura: -")
        L.stage = T:CreateLabel("Mining stage: -"); L.pack = T:CreateLabel("Backpack: -"); L.calls = T:CreateLabel("Calls/sec: -")
        L.phase = T:CreateLabel("Phase: -"); L.warn = T:CreateLabel("Status: ok")
    end)
    pcall(function() Rayfield:Notify({ Title = "+1 Mine Per Click", Content = "Loaded. Toggle features independently. Stats tab is last.", Duration = 5 }) end)
end)
if not guiOk then status.warn = "GUI build failed — features still run (getgenv().MinePerClick.setFeature)" end
