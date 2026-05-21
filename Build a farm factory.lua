local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/sigmatik_ui_library.lua"))()

local SharedEnvironment = getgenv and getgenv() or _G
local PreviousContext = SharedEnvironment.SigmatikBuildAFarmFactoryContext

if PreviousContext and PreviousContext.Cleanup then
    pcall(PreviousContext.Cleanup)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- Per-player rate-limit on ClickPlant (~20-25 clicks/sec total budget across all
-- tiles — confirmed by burst test: 2.3M fires in 3s only landed 66 server-side
-- clicks). Parallel multi-tile fire is therefore wasteful. Best strategy: focus
-- the entire budget on the single tile with highest cash-per-click.
local SeedValue = {
    ["Strawberry Seeds"] = 5 / 5,         -- 1.00
    ["Carrot Seeds"]     = 12 / 8,        -- 1.50
    ["Tomato Seeds"]     = 20 / 14,       -- 1.43
    ["Corn Seeds"]       = 50 / 24,       -- 2.08
    ["Blueberry Seeds"]  = 130 / 40,      -- 3.25
    ["Potato Seeds"]     = 350 / 65,      -- 5.38
    ["Sugarcane Seeds"]  = 900 / 100,     -- 9.00
    ["Watermelon Seeds"] = 2500 / 160,    -- 15.6
    ["Blackberry Seeds"] = 7000 / 260,    -- 26.9
    ["Beet Seeds"]       = 20000 / 420,   -- 47.6
    ["Kiwi Seeds"]       = 65000 / 700,   -- 92.9
    ["Prickly Pear Seeds"] = 500000 / 5000, -- 100.0
    ["Pineapple Seeds"]  = 150000 / 1000, -- 150.0  <- best
}

local State = {
    Alive = true,
    SpeedUpAllPlants = false,
    ClickRate = 25,
    AutoPollinate = false,
    InfiniteJump = false,
    FullBright = false,
    NoFog = false,
    AntiAFK = false,
    AntiAFKInterval = 5,
    WalkSpeed = 16,
    JumpPower = 50,
    TpToPlot = false,
    TpToShop = false,
    ServerHopRequest = false,
    RejoinRequest = false,
    AutoRoll = false,
    AutoRollMinCost = 7000,
    AutoRollStats = { rolls = 0, buys = 0, spent = 0 },
    AutoRollLabel = nil,
    Connections = {},
    LightingDefaults = {},
    AntiAFKConn = nil,
    InfJumpConn = nil,
}

SharedEnvironment.SigmatikBuildAFarmFactoryContext = State

local function addConn(c)
    if c then
        table.insert(State.Connections, c)
    end
    return c
end

local function disconnectAll()
    for _, c in ipairs(State.Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(State.Connections)
end

State.Cleanup = function()
    State.Alive = false
    State.SpeedUpAllPlants = false
    State.AutoPollinate = false
    State.InfiniteJump = false
    State.AntiAFK = false
    State.AutoRoll = false
    if State.AntiAFKConn then pcall(function() State.AntiAFKConn:Disconnect() end) end
    if State.InfJumpConn then pcall(function() State.InfJumpConn:Disconnect() end) end
    disconnectAll()
end

-- ItemData lookup (Cost per seed). Cached at first use.
local _ItemDataCache = nil
local function getItemData()
    if _ItemDataCache then return _ItemDataCache end
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == "ItemData" and d:IsA("ModuleScript") then
            local ok, mod = pcall(require, d)
            if ok and type(mod) == "table" then
                _ItemDataCache = mod.Items or mod
                return _ItemDataCache
            end
        end
    end
    return nil
end

local function getDoRoll()
    local comm = ReplicatedStorage:FindFirstChild("Communication")
    return comm and comm:FindFirstChild("DoRoll")
end

local function getBuySeeds()
    local comm = ReplicatedStorage:FindFirstChild("Communication")
    return comm and comm:FindFirstChild("BuySeeds")
end

local function getDataStoreGet()
    local comm = ReplicatedStorage:FindFirstChild("Communication")
    local ds = comm and comm:FindFirstChild("DataStore")
    return ds and ds:FindFirstChild("Get")
end

local function refreshAutoRollLabel()
    local lbl = State.AutoRollLabel
    if not lbl then return end
    local s = State.AutoRollStats
    local txt = string.format("Rolls: %d  |  Buys: %d  |  Spent: %s",
        s.rolls, s.buys, tostring(s.spent))
    pcall(function()
        if type(lbl.SetContent) == "function" then lbl:SetContent(txt)
        elseif type(lbl.SetText) == "function" then lbl:SetText(txt)
        elseif type(lbl.Set) == "function" then lbl:Set(txt) end
    end)
end

local function getCharacter()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return nil end
    return char, hrp, hum
end

local function getMyPlot()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    return plots:FindFirstChild(LocalPlayer.Name)
end

local function getClickPlantRemote()
    local comm = ReplicatedStorage:FindFirstChild("Communication")
    return comm and comm:FindFirstChild("ClickPlant")
end

local function getPollinateRemote()
    local comm = ReplicatedStorage:FindFirstChild("Communication")
    return comm and comm:FindFirstChild("PollinatePlant")
end

local function teleportTo(cframe)
    local char, hrp = getCharacter()
    if not char or not hrp then return false end
    pcall(function() hrp.CFrame = cframe end)
    return true
end

local function findPlotCFrame()
    local plot = getMyPlot()
    if plot then
        local primary = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart", true)
        if primary then
            return primary.CFrame + Vector3.new(0, 5, 0)
        end
    end
    return nil
end

local function findShopCFrame()
    local plot = getMyPlot()
    if plot then
        local sell = plot:FindFirstChild("Sell")
        if sell then
            local desk = sell:FindFirstChild("Desk")
            if desk then
                local primary = desk.PrimaryPart or desk:FindFirstChildWhichIsA("BasePart", true)
                if primary then
                    return primary.CFrame + Vector3.new(0, 5, 0)
                end
            end
            local primary = sell:IsA("Model") and (sell.PrimaryPart or sell:FindFirstChildWhichIsA("BasePart", true)) or (sell:IsA("BasePart") and sell or nil)
            if primary then
                return primary.CFrame + Vector3.new(0, 5, 0)
            end
        end
    end
    return nil
end

local function applyFullBright(enabled)
    if enabled then
        State.LightingDefaults.Brightness = State.LightingDefaults.Brightness or Lighting.Brightness
        State.LightingDefaults.ClockTime = State.LightingDefaults.ClockTime or Lighting.ClockTime
        State.LightingDefaults.GlobalShadows = State.LightingDefaults.GlobalShadows or Lighting.GlobalShadows
        State.LightingDefaults.Ambient = State.LightingDefaults.Ambient or Lighting.Ambient
        State.LightingDefaults.OutdoorAmbient = State.LightingDefaults.OutdoorAmbient or Lighting.OutdoorAmbient
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(150, 150, 150)
        Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
    else
        if State.LightingDefaults.Brightness then Lighting.Brightness = State.LightingDefaults.Brightness end
        if State.LightingDefaults.ClockTime then Lighting.ClockTime = State.LightingDefaults.ClockTime end
        if State.LightingDefaults.GlobalShadows ~= nil then Lighting.GlobalShadows = State.LightingDefaults.GlobalShadows end
        if State.LightingDefaults.Ambient then Lighting.Ambient = State.LightingDefaults.Ambient end
        if State.LightingDefaults.OutdoorAmbient then Lighting.OutdoorAmbient = State.LightingDefaults.OutdoorAmbient end
    end
end

local function applyNoFog(enabled)
    if enabled then
        State.LightingDefaults.FogEnd = State.LightingDefaults.FogEnd or Lighting.FogEnd
        State.LightingDefaults.FogStart = State.LightingDefaults.FogStart or Lighting.FogStart
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
    else
        if State.LightingDefaults.FogEnd then Lighting.FogEnd = State.LightingDefaults.FogEnd end
        if State.LightingDefaults.FogStart then Lighting.FogStart = State.LightingDefaults.FogStart end
    end
end

local function applyWalkSpeed(v)
    State.WalkSpeed = v
    local _, _, hum = getCharacter()
    if hum then pcall(function() hum.WalkSpeed = v end) end
end

local function applyJumpPower(v)
    State.JumpPower = v
    local _, _, hum = getCharacter()
    if hum then
        pcall(function()
            hum.UseJumpPower = true
            hum.JumpPower = v
        end)
    end
end

local function setInfiniteJump(v)
    State.InfiniteJump = v
    if State.InfJumpConn then
        pcall(function() State.InfJumpConn:Disconnect() end)
        State.InfJumpConn = nil
    end
    if v then
        State.InfJumpConn = UserInputService.JumpRequest:Connect(function()
            if not State.InfiniteJump then return end
            local _, _, hum = getCharacter()
            if hum then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
            end
        end)
    end
end

local function setAntiAFK(v)
    State.AntiAFK = v
    if State.AntiAFKConn then
        pcall(function() State.AntiAFKConn:Disconnect() end)
        State.AntiAFKConn = nil
    end
    if v then
        State.AntiAFKConn = LocalPlayer.Idled:Connect(function()
            if not State.AntiAFK then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
            local _, hrp, hum = getCharacter()
            if hum and hrp then
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end)
                pcall(function()
                    local offset = Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
                    hrp.CFrame = hrp.CFrame + offset
                end)
            end
        end)
    end
end

-- Single-tile focus loop. Each tick we pick the ready plant with the highest
-- cash-per-click and fire ClickPlant at it. Server enforces per-player rate
-- limit (~22 clicks/sec total), so spreading fires across tiles strictly hurts
-- $/sec. We iterate through ready plants in order of value; if the top tile's
-- HarvestTime is in the future, fall back to next-best.
local function pickBestReadyPlant()
    local plot = getMyPlot()
    local plants = plot and plot:FindFirstChild("Plants")
    if not plants then return nil end
    local now = os.time()
    local best, bestVal = nil, -1
    for _, p in ipairs(plants:GetChildren()) do
        local nm = p:GetAttribute("PlantName")
        local clicks = p:GetAttribute("Clicks")
        local needed = p:GetAttribute("ClicksNeeded")
        local ht = tonumber(p:GetAttribute("HarvestTime")) or 0
        if nm and clicks and ht <= now + 1 then
            -- Skip if already at max click count and waiting on game tick
            local v = SeedValue[nm] or 0.5
            if v > bestVal then
                bestVal = v
                best = p
            end
        end
    end
    return best
end

task.spawn(function()
    while State.Alive do
        if State.SpeedUpAllPlants then
            local clickRemote = getClickPlantRemote()
            local pollinateRemote = getPollinateRemote()
            local plot = getMyPlot()
            local tiles = plot and plot:FindFirstChild("Tiles")
            local plant = pickBestReadyPlant()
            if clickRemote and tiles and plant then
                local tile = tiles:FindFirstChild(plant.Name)
                if tile then
                    pcall(function() clickRemote:FireServer(tile) end)
                    if State.AutoPollinate and pollinateRemote then
                        pcall(function() pollinateRemote:FireServer(plant) end)
                    end
                end
            end
            local rate = State.ClickRate or 25
            if rate < 1 then rate = 1 end
            if rate > 30 then rate = 30 end -- server cap is ~22/s, no point firing faster
            task.wait(1 / rate)
        else
            task.wait(0.25)
        end
    end
end)

-- Auto Roll loop. DoRoll is a free RemoteFunction (verified F-007: no cost,
-- no cooldown). Each invocation rerolls 6 shop slots (RolledSeeds[1..6]).
-- BuySeeds:FireServer(slotIndex) buys whatever sits in that slot for full
-- ItemData.Items[seedName].Cost.
--
-- Wrong-seed-buy fix: server REPLACES the bought slot with a fresh roll on the
-- spot (verified by DataStore.Get probe: slot[i].Type changes after BuySeeds(i)).
-- Old code took the DoRoll-return array and pushed BuySeeds for every passing
-- slot back-to-back; nothing wrong with that path itself, but if the loop was
-- ever to read DataStore.RolledSeeds between buys (or another script triggered
-- an extra DoRoll), the slot index → seed mapping would desync. To eliminate
-- any chance of buying a re-rolled cheap seed, we now (a) capture the seed name
-- AND cost from the DoRoll return value before any FireServer call, (b) yield
-- one frame between buys so the server's slot replacement can settle, (c) use
-- a strict numeric threshold compare with tonumber on both sides.
task.spawn(function()
    while State.Alive do
        if State.AutoRoll then
            local doRoll = getDoRoll()
            local buyS = getBuySeeds()
            local items = getItemData()
            if doRoll and buyS and items then
                local ok, rolled = pcall(function() return doRoll:InvokeServer() end)
                if ok and typeof(rolled) == "table" then
                    State.AutoRollStats.rolls = State.AutoRollStats.rolls + 1
                    local thresh = tonumber(State.AutoRollMinCost) or 0
                    -- Pre-snapshot every slot's name+cost from DoRoll's return
                    -- (frozen view; immune to mid-loop server re-rolls).
                    for i = 1, 6 do
                        if not State.AutoRoll then break end
                        local slot = rolled[i]
                        local nm = (typeof(slot) == "table") and slot.Type or nil
                        local data = nm and items[nm]
                        local cost = tonumber(data and (data.Cost or data.cost)) or 0
                        if cost > 0 and cost >= thresh then
                            local ok2 = pcall(function() buyS:FireServer(i) end)
                            if ok2 then
                                State.AutoRollStats.buys = State.AutoRollStats.buys + 1
                                State.AutoRollStats.spent = State.AutoRollStats.spent + cost
                            end
                            -- One frame between buys: server replaces the bought
                            -- slot with a fresh seed; we don't care about that
                            -- new seed (we only buy from THIS DoRoll's snapshot).
                            task.wait()
                        end
                    end
                    if State.AutoRollStats.rolls % 5 == 0 then
                        refreshAutoRollLabel()
                    end
                end
            end
            task.wait()
        else
            task.wait(0.25)
        end
    end
end)

-- AntiAFK periodic mover (independent of Idled signal so it works even while active)
task.spawn(function()
    while State.Alive do
        task.wait(60 * (State.AntiAFKInterval or 5))
        if State.AntiAFK then
            local _, hrp, hum = getCharacter()
            if hum and hrp then
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    local offset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
                    hrp.CFrame = hrp.CFrame + offset
                end)
            end
        end
    end
end)

-- Action handlers (toggles used as buttons — auto-reset)
local function doTpToPlot()
    local cframe = findPlotCFrame()
    if cframe then teleportTo(cframe) end
end

local function doTpToShop()
    local cframe = findShopCFrame()
    if cframe then teleportTo(cframe) end
end

local function doServerHop()
    local placeId = game.PlaceId
    local ok, result = pcall(function()
        local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
        local response = game:HttpGet(url)
        return HttpService:JSONDecode(response)
    end)
    if ok and result and result.data then
        for _, server in ipairs(result.data) do
            if server.id ~= game.JobId and server.playing and server.maxPlayers and server.playing < server.maxPlayers then
                pcall(function()
                    TeleportService:TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                end)
                return
            end
        end
    end
    pcall(function()
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
end

local function doRejoin()
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
    end)
end

addConn(LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            hum.WalkSpeed = State.WalkSpeed
            hum.UseJumpPower = true
            hum.JumpPower = State.JumpPower
        end)
    end
    if State.FullBright then applyFullBright(true) end
    if State.NoFog then applyNoFog(true) end
end))

local UI = Library:Create({
    Title = "tg: @sigmatik323",
    ConfigName = "by sigmatik323",
    SearchPlaceholder = "Search modules...",
    Accent = "#22d3ee",
    AccentSoft = "#67e8f9",
    GuiToggleKey = Enum.KeyCode.RightShift,
    Tabs = {
        {
            Name = "Farm",
            Icon = "main",
            Modules = {
                {
                    Name = "Plant Growth",
                    Enabled = false,
                    Callback = function(enabled)
                        State.SpeedUpAllPlants = enabled
                    end,
                    Sections = {
                        {
                            Name = "Auto Click",
                            Controls = {
                                {
                                    Type = "toggle",
                                    Name = "Speed Up All Plants",
                                    Value = false,
                                    Callback = function(v) State.SpeedUpAllPlants = v end,
                                },
                                {
                                    Type = "slider",
                                    Name = "Click Rate (per sec)",
                                    Min = 5,
                                    Max = 30,
                                    Increment = 1,
                                    CurrentValue = 25,
                                    Callback = function(v)
                                        local rate = tonumber(v) or 25
                                        if rate < 1 then rate = 1 end
                                        State.ClickRate = rate
                                    end,
                                },
                                {
                                    Type = "toggle",
                                    Name = "Auto Pollinate",
                                    Value = false,
                                    Callback = function(v) State.AutoPollinate = v end,
                                },
                                {
                                    Type = "paragraph",
                                    Name = "Info",
                                    Content = "Server rate-limits ClickPlant per-player (~22 cps total, NOT per-tile). Multi-tile parallel fire wastes the budget, so the loop focuses on the single ready plant with highest cash-per-click (Pineapple > Prickly Pear > Kiwi > Beet > Blackberry > Watermelon > Sugarcane > Potato > ...).",
                                },
                            },
                        },
                    },
                },
                {
                    Name = "Auto Roll",
                    Enabled = false,
                    Callback = function(enabled) State.AutoRoll = enabled end,
                    Sections = {
                        {
                            Name = "Shop Roller",
                            Controls = {
                                {
                                    Type = "toggle",
                                    Name = "Auto Roll",
                                    Value = false,
                                    Callback = function(v)
                                        State.AutoRoll = v
                                        if v then
                                            State.AutoRollStats.rolls = 0
                                            State.AutoRollStats.buys = 0
                                            State.AutoRollStats.spent = 0
                                            refreshAutoRollLabel()
                                        end
                                    end,
                                },
                                {
                                    Type = "input",
                                    Name = "Min Cost ($)",
                                    Placeholder = "7000",
                                    Value = tostring(State.AutoRollMinCost or 7000),
                                    Callback = function(text)
                                        local n = tonumber(text)
                                        if n and n >= 0 then
                                            State.AutoRollMinCost = n
                                        end
                                        -- If parse fails, keep previous value
                                        -- (don't clobber with 0 silently).
                                    end,
                                },
                                {
                                    Type = "label",
                                    Name = "Rolls: 0  |  Buys: 0  |  Spent: 0",
                                    Callback = function(self)
                                        State.AutoRollLabel = self
                                    end,
                                },
                                {
                                    Type = "paragraph",
                                    Name = "Info",
                                    Content = "Spams DoRoll (free RemoteFunction) and instantly buys every rolled slot whose seed Cost is greater than or equal to the threshold. BuySeeds debits the seed cost from your Cash. Type the minimum cost in the input above. Costs: Strawberry 15, Carrot 50, Tomato 180, Corn 600, Blueberry 2000, Potato 7000, Sugarcane 25000, Watermelon 80000, Blackberry 300000, Beet 1.2M, Kiwi 5M, Pineapple 12M, Prickly Pear 50M.",
                                },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Player",
            Icon = "player",
            Modules = {
                {
                    Name = "Movement",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Speed",
                            Controls = {
                                {
                                    Type = "slider",
                                    Name = "WalkSpeed",
                                    Min = 16,
                                    Max = 200,
                                    Increment = 1,
                                    Value = 16,
                                    Callback = function(v) applyWalkSpeed(v) end,
                                },
                                {
                                    Type = "slider",
                                    Name = "JumpPower",
                                    Min = 50,
                                    Max = 350,
                                    Increment = 5,
                                    Value = 50,
                                    Callback = function(v) applyJumpPower(v) end,
                                },
                                {
                                    Type = "toggle",
                                    Name = "Infinite Jump",
                                    Value = false,
                                    Callback = function(v) setInfiniteJump(v) end,
                                },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "World",
            Icon = "misc",
            Modules = {
                {
                    Name = "Teleport",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Locations",
                            Controls = {
                                {
                                    Type = "toggle",
                                    Name = "TP to Plot",
                                    Value = false,
                                    Callback = function(v)
                                        if v then doTpToPlot() end
                                    end,
                                },
                                {
                                    Type = "toggle",
                                    Name = "TP to Shop",
                                    Value = false,
                                    Callback = function(v)
                                        if v then doTpToShop() end
                                    end,
                                },
                                {
                                    Type = "paragraph",
                                    Name = "Hint",
                                    Content = "Toggle ON to teleport. Toggle OFF and ON again to repeat.",
                                },
                            },
                        },
                    },
                },
                {
                    Name = "Visuals",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Lighting",
                            Controls = {
                                {
                                    Type = "toggle",
                                    Name = "FullBright",
                                    Value = false,
                                    Callback = function(v)
                                        State.FullBright = v
                                        applyFullBright(v)
                                    end,
                                },
                                {
                                    Type = "toggle",
                                    Name = "No Fog",
                                    Value = false,
                                    Callback = function(v)
                                        State.NoFog = v
                                        applyNoFog(v)
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Misc",
            Icon = "misc",
            Modules = {
                {
                    Name = "Anti AFK",
                    Enabled = false,
                    Callback = function(enabled) setAntiAFK(enabled) end,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                {
                                    Type = "toggle",
                                    Name = "Anti AFK",
                                    Value = false,
                                    Callback = function(v) setAntiAFK(v) end,
                                },
                                {
                                    Type = "slider",
                                    Name = "Anti AFK Move Interval",
                                    Min = 1,
                                    Max = 15,
                                    Increment = 1,
                                    Value = 5,
                                    Callback = function(v) State.AntiAFKInterval = v end,
                                },
                            },
                        },
                    },
                },
                {
                    Name = "Server",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Actions",
                            Controls = {
                                {
                                    Type = "toggle",
                                    Name = "Server Hop",
                                    Value = false,
                                    Callback = function(v)
                                        if v then doServerHop() end
                                    end,
                                },
                                {
                                    Type = "toggle",
                                    Name = "Rejoin Server",
                                    Value = false,
                                    Callback = function(v)
                                        if v then doRejoin() end
                                    end,
                                },
                                {
                                    Type = "paragraph",
                                    Name = "Info",
                                    Content = "Toggle ON to fire action. Action runs once when toggled ON.",
                                },
                            },
                        },
                    },
                },
            },
        },
    },
})

return UI
