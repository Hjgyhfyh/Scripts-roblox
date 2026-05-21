local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local SharedEnv = getgenv and getgenv() or _G
local Previous = SharedEnv.SigmatikCookieIncrementalState

if Previous and Previous.Stop then
    Previous.Stop()
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/sigmatik_ui_library.lua"))()

local CoinEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CoinEvent")
local UpgradeRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpgradeRequest")
local RuneRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RuneRequest")
local OreMined = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OreMined")

local State = {
    Alive = true,
    FarmEnabled = false,
    MagnetMode = false,
    AnchorOnSpawnCenter = false,
    TpDelay = 0.3,
    MaxRange = 300,
    Connections = {},
    CharConnections = {},
    Character = nil,
    Humanoid = nil,
    RootPart = nil,
    Collected = {},
    RecentTargets = {},
    AnchorCFrame = nil,

    UpgradeBuyEnabled = false,
    BuyMoreCoins = false,
    BuyMoreCoinSpawn = false,
    BuyFasterCoinSpawn = false,
    BuyInterval = 1.5,

    AutoOpenRune = false,
    RuneType = "Basic",
    OpenRuneInterval = 0.5,
    RuneInventories = {},
    RuneLabels = {},

    CandyFarmEnabled = false,
    CandyOreType = "Icecream",
    CandyCycleDelay = 0.15,
    CandyRateLabel = nil,
    CandyHistory = {},
    CandyMineCount = 0,
}

local RUNE_TYPES = { "Basic", "Candy", "Novice", "Sunken", "Void" }
local RUNE_RARITIES = {
    Basic   = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "???" },
    Candy   = { "Reincarnation", "Depth", "Burried", "Crucified", "Soulbounded", "Soul", "Reborn" },
    Novice  = { "Faded", "Worn", "Refined", "Powered", "Master", "Ancient", "Ascended" },
    Sunken  = { "Seabounded", "Riftide", "Abyssal", "Depthcore", "Deepsea", "Cthulhu", "Darkness" },
    Void    = { "Aether", "Riftbreaker", "Oblivion", "Nullmark", "Voidreaver", "Voidix", "????" },
}

local BASIC_BOOSTS = {
    Common = { { Stat = "Cash", Inc = 0.0004, Max = 4.5 } },
    Uncommon = { { Stat = "Cash", Inc = 0.00233, Max = 2.1 }, { Stat = "Coins", Inc = 0.000633, Max = 2.1 } },
    Rare = { { Stat = "Cash", Inc = 0.0044, Max = 2.77 }, { Stat = "RP", Inc = 0.004, Max = 1.99 } },
    Epic = { { Stat = "Energy", Inc = 0.015, Max = 2.2 }, { Stat = "RP", Inc = 0.015, Max = 1.9 } },
    Legendary = { { Stat = "Cash", Inc = 0.04, Max = 2.3 }, { Stat = "RP", Inc = 0.02, Max = 1.9 } },
    Mythical = { { Stat = "Coins", Inc = 0.15, Max = 1.88 }, { Stat = "Energy", Inc = 0.15, Max = 1.89 } },
    ["???"] = { { Stat = "Research", Inc = 1, Max = 2.4 }, { Stat = "RP", Inc = 1, Max = 2.3 } },
}

local function getRuneInventory(runeType)
    local inv = State.RuneInventories[runeType]
    if not inv then
        inv = {}
        State.RuneInventories[runeType] = inv
    end
    return inv
end

local function buildRuneContent(runeType, rarity, cnt)
    local lines = { string.format("Owned: %d", cnt) }
    if runeType == "Basic" then
        for _, boost in ipairs(BASIC_BOOSTS[rarity] or {}) do
            local mult = math.min(boost.Max, 1 + boost.Inc * cnt)
            table.insert(lines, string.format("%-9s %.4f×   max %.2f×", boost.Stat .. ":", mult, boost.Max))
        end
    end
    return table.concat(lines, "\n")
end

local function refreshRuneLabels()
    local runeType = State.RuneType or "Basic"
    local rarities = RUNE_RARITIES[runeType] or {}
    local inv = getRuneInventory(runeType)
    -- Clear stale labels for hidden types and only update active type's labels.
    for _, rarity in ipairs(rarities) do
        local entry = State.RuneLabels[rarity]
        if entry then
            local content = buildRuneContent(runeType, rarity, inv[rarity] or 0)
            if entry.control then entry.control.Content = content end
            if entry.text and entry.text.Parent then entry.text.Text = content end
        end
    end
end

SharedEnv.SigmatikCookieIncrementalState = State

local function disconnectList(list)
    for _, c in ipairs(list) do
        if typeof(c) == "RBXScriptConnection" then pcall(function() c:Disconnect() end) end
    end
    table.clear(list)
end

local function attachCharacter(character)
    State.Character = character
    State.Humanoid = nil
    State.RootPart = nil
    disconnectList(State.CharConnections)
    if not character then return end
    local function refresh()
        State.RootPart = character:FindFirstChild("HumanoidRootPart")
        State.Humanoid = character:FindFirstChildOfClass("Humanoid")
    end
    refresh()
    table.insert(State.CharConnections, character.ChildAdded:Connect(refresh))
    table.insert(State.CharConnections, character.ChildRemoved:Connect(refresh))
end

table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(attachCharacter))
table.insert(State.Connections, LocalPlayer.CharacterRemoving:Connect(function() attachCharacter(nil) end))
attachCharacter(LocalPlayer.Character)

local function getRoot()
    local rp = State.RootPart
    local hum = State.Humanoid
    if rp and rp.Parent and hum and hum.Parent and hum.Health > 0 then
        return rp
    end
    return nil
end

table.insert(State.Connections, CoinEvent.OnClientEvent:Connect(function(action, payload)
    if action == "Collect" and type(payload) == "table" and type(payload.CoinId) == "number" then
        State.Collected[payload.CoinId] = os.clock()
    end
end))

local function parseCoinId(name)
    return tonumber(string.match(name or "", "ClientCoin_(%d+)$"))
end

local function listLiveCoins()
    local cc = workspace:FindFirstChild("ClientCoins")
    if not cc then return {} end
    local now = os.clock()
    local out = {}
    for _, child in ipairs(cc:GetChildren()) do
        local part
        if child:IsA("BasePart") then
            part = child
        elseif child:IsA("Model") then
            part = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
        end
        if part then
            local skip = false
            local recent = State.RecentTargets[part]
            if recent and now - recent < 2 then
                skip = true
            elseif recent then
                State.RecentTargets[part] = nil
            end
            local id = parseCoinId(child.Name)
            if not skip and id then
                local lastCollect = State.Collected[id]
                if lastCollect and now - lastCollect < 2 then skip = true end
            end
            if not skip then
                table.insert(out, { id = id, part = part, pos = part.Position })
            end
        end
    end
    return out
end

local function tpRoot(root, targetPos)
    pcall(function()
        root.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function farmLoop()
    while State.Alive do
        if not State.FarmEnabled then
            State.AnchorCFrame = nil
            task.wait(0.2)
        else
            local root = getRoot()
            if not root then
                task.wait(0.4)
            else
                if not State.AnchorCFrame then
                    if State.AnchorOnSpawnCenter then
                        local sp = workspace:FindFirstChild("Features")
                        sp = sp and sp:FindFirstChild("Coins") and sp.Coins:FindFirstChild("SpawnPart")
                        if sp then
                            State.AnchorCFrame = CFrame.new(sp.Position + Vector3.new(0, 1, 0))
                            pcall(function()
                                root.CFrame = State.AnchorCFrame
                                root.AssemblyLinearVelocity = Vector3.zero
                            end)
                        else
                            State.AnchorCFrame = root.CFrame
                        end
                    else
                        State.AnchorCFrame = root.CFrame
                    end
                end
                local picked, pickedPart, pickedId, nearest = nil, nil, nil, math.huge
                for _, c in ipairs(listLiveCoins()) do
                    local dist = (root.Position - c.pos).Magnitude
                    if dist < nearest and dist <= State.MaxRange then
                        nearest = dist
                        picked = c.pos
                        pickedPart = c.part
                        pickedId = c.id
                    end
                end
                if not picked then
                    task.wait(0.4)
                else
                    State.RecentTargets[pickedPart] = os.clock()
                    if pickedId then State.Collected[pickedId] = os.clock() end
                    tpRoot(root, picked)
                    task.wait(0.15)
                    if State.MagnetMode and State.AnchorCFrame then
                        local rootNow = getRoot()
                        if rootNow then
                            pcall(function()
                                rootNow.CFrame = State.AnchorCFrame
                                rootNow.AssemblyLinearVelocity = Vector3.zero
                                rootNow.AssemblyAngularVelocity = Vector3.zero
                            end)
                        end
                    end
                    task.wait(State.TpDelay)
                end
            end
        end
    end
end

task.spawn(farmLoop)

local function buyLoop()
    while State.Alive do
        if not State.UpgradeBuyEnabled then
            task.wait(0.3)
        else
            local targets = {}
            if State.BuyMoreCoins then table.insert(targets, "MoreCoins") end
            if State.BuyMoreCoinSpawn then table.insert(targets, "MoreCoinSpawn") end
            if State.BuyFasterCoinSpawn then table.insert(targets, "FasterCoinSpawn") end
            if #targets == 0 then
                task.wait(0.5)
            else
                for _, upg in ipairs(targets) do
                    if not State.Alive or not State.UpgradeBuyEnabled then break end
                    pcall(function() UpgradeRequest:InvokeServer("BuyMax", upg) end)
                    task.wait(State.BuyInterval)
                end
            end
        end
    end
end

task.spawn(buyLoop)

local function captureInventory(runeType, res)
    if type(res) ~= "table" or type(res.Inventory) ~= "table" then return end
    local inv = getRuneInventory(runeType)
    table.clear(inv)
    for k, v in pairs(res.Inventory) do
        inv[k] = v
    end
    if runeType == State.RuneType then refreshRuneLabels() end
end

local function openRuneOnce()
    local rt = State.RuneType or "Basic"
    local ok, res = pcall(function() return RuneRequest:InvokeServer("OpenBatch", rt, 1) end)
    if ok then captureInventory(rt, res) end
end

-- pre-fetch inventory at startup for every rune type (best-effort, won't block if hangs)
task.spawn(function()
    task.wait(2)
    for _, runeType in ipairs(RUNE_TYPES) do
        local ok, res = pcall(function() return RuneRequest:InvokeServer("Get", runeType) end)
        if ok then captureInventory(runeType, res) end
    end
end)

local function runeLoop()
    while State.Alive do
        if not State.AutoOpenRune then
            -- task.wait clamps low values to ~1/60s; that's still a fine idle cadence.
            task.wait(0.2)
        else
            openRuneOnce()
            -- Even sub-frame delays are clamped by the scheduler to ~1/60s, but the slider
            -- still surfaces 0.001 step granularity for users who want "as fast as possible".
            task.wait(math.max(0.001, State.OpenRuneInterval))
        end
    end
end

task.spawn(runeLoop)

local CANDY_ORE_OPTIONS = { "Icecream", "Gingerbread", "Candycone", "Cookie", "Candy" }

local function readCandyBigNum()
    local data = ReplicatedStorage:FindFirstChild("PlayerData")
    if not data then return nil end
    local folder = data:FindFirstChild(tostring(LocalPlayer.UserId))
    if not folder then return nil end
    local stats = folder:FindFirstChild("Stats")
    if not stats then return nil end
    local candy = stats:FindFirstChild("Candy")
    if not candy then return nil end
    return candy.Value
end

local function bigNumToNumber(s)
    if type(s) ~= "string" then return tonumber(s) or 0 end
    local mant, exp = string.match(s, "^([%-%d%.]+),(%-?%d+)$")
    if mant and exp then
        local m = tonumber(mant) or 0
        local e = tonumber(exp) or 0
        if e > 30 then return math.huge end
        return m * (10 ^ e)
    end
    return tonumber(s) or 0
end

local function pushCandySample()
    local raw = readCandyBigNum()
    if not raw then return end
    local n = bigNumToNumber(raw)
    local now = os.clock()
    table.insert(State.CandyHistory, { t = now, v = n })
    while #State.CandyHistory > 0 and now - State.CandyHistory[1].t > 60 do
        table.remove(State.CandyHistory, 1)
    end
end

local function setCandyRateText(s)
    local entry = State.CandyRateLabel
    if not entry then return end
    if entry.control then entry.control.Content = s end
    if entry.text and entry.text.Parent then entry.text.Text = s end
end

local function refreshCandyRate()
    local hist = State.CandyHistory
    if #hist < 2 then
        setCandyRateText("Candy/min: …\nMined this session: " .. State.CandyMineCount)
        return
    end
    local first, last = hist[1], hist[#hist]
    local dt = last.t - first.t
    if dt < 1 then
        setCandyRateText("Candy/min: …\nMined this session: " .. State.CandyMineCount)
        return
    end
    local perMin = (last.v - first.v) * 60 / dt
    local function fmt(n)
        if n >= 1e15 then return string.format("%.2fe%d", n / 10 ^ math.floor(math.log10(n)), math.floor(math.log10(n))) end
        if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
        if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
        if n >= 1e3 then return string.format("%.2fK", n / 1e3) end
        return string.format("%.0f", n)
    end
    setCandyRateText(string.format("Candy/min: %s\nMined this session: %d", fmt(perMin), State.CandyMineCount))
end

local function candyLoop()
    while State.Alive do
        if not State.CandyFarmEnabled then
            task.wait(0.2)
        else
            local ore = State.CandyOreType or "Icecream"
            pcall(function() OreMined:FireServer(ore) end)
            State.CandyMineCount = State.CandyMineCount + 1
            -- Sub-frame delays are clamped by scheduler to ~1/60s; slider exposes finer step
            -- so the user can dial to "as fast as the engine allows" without ceremony.
            task.wait(math.max(0.001, State.CandyCycleDelay))
        end
    end
end

task.spawn(candyLoop)

task.spawn(function()
    while State.Alive do
        pushCandySample()
        refreshCandyRate()
        task.wait(1)
    end
end)

State.Stop = function()
    State.Alive = false
    State.FarmEnabled = false
    State.UpgradeBuyEnabled = false
    State.AutoOpenRune = false
    State.CandyFarmEnabled = false
    disconnectList(State.CharConnections)
    disconnectList(State.Connections)
    if State.Window and State.Window.Destroy then
        pcall(function() State.Window:Destroy() end)
    end
end

-- Union of every rune-type's rarity list, preserving order. We render one Paragraph per
-- rarity name; refreshRuneLabels() rewrites the content based on the active rune type.
local ALL_RARITIES = {}
do
    local seen = {}
    for _, runeType in ipairs(RUNE_TYPES) do
        for _, rarity in ipairs(RUNE_RARITIES[runeType] or {}) do
            if not seen[rarity] then
                seen[rarity] = true
                table.insert(ALL_RARITIES, rarity)
            end
        end
    end
end

local runeParagraphControls = {}
for _, rarity in ipairs(ALL_RARITIES) do
    table.insert(runeParagraphControls, {
        Type = "Paragraph",
        Name = rarity,
        Content = buildRuneContent(State.RuneType, rarity, 0),
    })
end

State.Window = Library:Create({
    Title = "tg: @sigmatik323",
    ConfigName = "by sigmatik323",
    SearchPlaceholder = "Search...",
    Accent = "#fbbf24",
    AccentSoft = "#fde68a",
    -- Wider window keeps the Settings panel comfortable for the per-module Enabled toggle
    -- (panel is fixed 336 px; the Switch sits at the right edge with only ~10 px buffer at
    -- the previous 960 px width, which clipped/hugged the edge on smaller viewports).
    WindowWidth = 1100,
    WindowHeight = 600,
    GuiToggleKey = Enum.KeyCode.RightShift,
    Tabs = {
        {
            Name = "Coins",
            Icon = "misc",
            Modules = {
                {
                    Name = "Auto Collect Coins",
                    Enabled = false,
                    Callback = function(v) State.FarmEnabled = v end,
                    Sections = {
                        {
                            Name = "Auto Collect",
                            Controls = {
                                {
                                    Type = "Toggle",
                                    Name = "Magnet Mode (return to anchor)",
                                    CurrentValue = false,
                                    Callback = function(v) State.MagnetMode = v end,
                                },
                                {
                                    Type = "Toggle",
                                    Name = "Anchor on Spawn Center",
                                    CurrentValue = false,
                                    Callback = function(v) State.AnchorOnSpawnCenter = v end,
                                },
                                {
                                    Type = "Slider",
                                    Name = "Teleport Delay (sec)",
                                    Min = 0.05,
                                    Max = 2,
                                    Increment = 0.05,
                                    CurrentValue = 0.3,
                                    Callback = function(v) State.TpDelay = v end,
                                },
                                {
                                    Type = "Slider",
                                    Name = "Max Coin Range",
                                    Min = 50,
                                    Max = 2000,
                                    Increment = 25,
                                    CurrentValue = 300,
                                    Callback = function(v) State.MaxRange = v end,
                                },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Upgrades",
            Icon = "misc",
            Modules = {
                {
                    Name = "Auto Buy Coin Upgrades",
                    Enabled = false,
                    Callback = function(v) State.UpgradeBuyEnabled = v end,
                    Sections = {
                        {
                            Name = "Auto Buy",
                            Controls = {
                                {
                                    Type = "Toggle",
                                    Name = "Buy MoreCoins",
                                    CurrentValue = false,
                                    Callback = function(v) State.BuyMoreCoins = v end,
                                },
                                {
                                    Type = "Toggle",
                                    Name = "Buy MoreCoinSpawn",
                                    CurrentValue = false,
                                    Callback = function(v) State.BuyMoreCoinSpawn = v end,
                                },
                                {
                                    Type = "Toggle",
                                    Name = "Buy FasterCoinSpawn",
                                    CurrentValue = false,
                                    Callback = function(v) State.BuyFasterCoinSpawn = v end,
                                },
                                {
                                    Type = "Slider",
                                    Name = "Buy Interval (sec)",
                                    Min = 0.5,
                                    Max = 5,
                                    Increment = 0.1,
                                    CurrentValue = 1.5,
                                    Callback = function(v) State.BuyInterval = v end,
                                },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Candy",
            Icon = "misc",
            Modules = {
                {
                    Name = "Candy Farm",
                    Enabled = false,
                    Callback = function(v) State.CandyFarmEnabled = v end,
                    Sections = {
                        {
                            Name = "Mining",
                            Controls = (function()
                                local controls = {
                                    {
                                        Type = "Slider",
                                        Name = "Cycle Delay (s)",
                                        Min = 0.001,
                                        Max = 2,
                                        Increment = 0.001,
                                        CurrentValue = 0.15,
                                        Callback = function(v) State.CandyCycleDelay = v end,
                                    },
                                }
                                return controls
                            end)(),
                        },
                        {
                            Name = "Ore Type (pick one)",
                            Controls = (function()
                                local list = {}
                                for _, ore in ipairs(CANDY_ORE_OPTIONS) do
                                    table.insert(list, {
                                        Type = "Checkbox",
                                        Name = ore,
                                        CurrentValue = (ore == "Icecream"),
                                        Callback = function(v)
                                            if v then
                                                State.CandyOreType = ore
                                                -- mutex: turn off all other ore checkboxes
                                                if State.Window and State.Window.SetControlValue then
                                                    for _, other in ipairs(CANDY_ORE_OPTIONS) do
                                                        if other ~= ore then
                                                            pcall(function()
                                                                State.Window:SetControlValue("Candy", "Candy Farm", "Ore Type (pick one)", other, false)
                                                            end)
                                                        end
                                                    end
                                                end
                                            else
                                                -- Don't allow deselecting the active ore — re-tick it.
                                                if State.CandyOreType == ore and State.Window and State.Window.SetControlValue then
                                                    task.defer(function()
                                                        pcall(function()
                                                            State.Window:SetControlValue("Candy", "Candy Farm", "Ore Type (pick one)", ore, true)
                                                        end)
                                                    end)
                                                end
                                            end
                                        end,
                                    })
                                end
                                return list
                            end)(),
                        },
                        {
                            Name = "Stats",
                            Controls = {
                                {
                                    Type = "Paragraph",
                                    Name = "Rate",
                                    Content = "Candy/min: …\nMined this session: 0",
                                },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Runes",
            Icon = "misc",
            Modules = {
                {
                    Name = "Auto Open Rune",
                    Enabled = false,
                    Callback = function(v) State.AutoOpenRune = v end,
                    Sections = {
                        {
                            Name = "Open",
                            Controls = {
                                {
                                    Type = "Slider",
                                    Name = "Open Interval (sec)",
                                    Min = 0.001,
                                    Max = 2,
                                    Increment = 0.001,
                                    CurrentValue = 0.15,
                                    Callback = function(v) State.OpenRuneInterval = v end,
                                },
                            },
                        },
                        {
                            Name = "Rune Type (pick one)",
                            Controls = (function()
                                local list = {}
                                for _, runeType in ipairs(RUNE_TYPES) do
                                    table.insert(list, {
                                        Type = "Checkbox",
                                        Name = runeType,
                                        CurrentValue = (runeType == "Basic"),
                                        Callback = function(v)
                                            if v then
                                                State.RuneType = runeType
                                                -- mutex: turn off all other rune type checkboxes
                                                if State.Window and State.Window.SetControlValue then
                                                    for _, other in ipairs(RUNE_TYPES) do
                                                        if other ~= runeType then
                                                            pcall(function()
                                                                State.Window:SetControlValue("Runes", "Auto Open Rune", "Rune Type (pick one)", other, false)
                                                            end)
                                                        end
                                                    end
                                                end
                                                refreshRuneLabels()
                                            else
                                                -- Don't allow deselecting the active rune type — re-tick it.
                                                if State.RuneType == runeType and State.Window and State.Window.SetControlValue then
                                                    task.defer(function()
                                                        pcall(function()
                                                            State.Window:SetControlValue("Runes", "Auto Open Rune", "Rune Type (pick one)", runeType, true)
                                                        end)
                                                    end)
                                                end
                                            end
                                        end,
                                    })
                                end
                                return list
                            end)(),
                        },
                        {
                            Name = "Inventory & Boost",
                            Controls = runeParagraphControls,
                        },
                    },
                },
            },
        },
    },
})

-- Bind paragraph controls to their rendered TextLabels so we can live-update content.
local function findParagraphTextLabel(controlName)
    local sgui = (gethui and gethui()) or game:GetService("CoreGui")
    local frame = sgui:FindFirstChild("SigmatikClickGui", true)
    if not frame then return nil end
    local card = frame:FindFirstChild(controlName .. "Paragraph", true)
    if not card then return nil end
    return card:FindFirstChild("Content", true)
end

local function bindParagraph(tabName, moduleName, sectionName, controlName)
    local entry = { control = nil, text = nil }
    if State.Window and State.Window.GetModule then
        local mod = State.Window:GetModule(tabName, moduleName)
        local sec = mod and mod.SectionLookup and mod.SectionLookup[sectionName]
        if sec then
            for _, c in ipairs(sec.Controls) do
                if c.Name == controlName then entry.control = c break end
            end
        end
    end
    -- Resolve the rendered TextLabel after a short defer so the mount completes first.
    task.defer(function()
        for _ = 1, 60 do
            if not State.Alive then return end
            local lbl = findParagraphTextLabel(controlName)
            if lbl then
                entry.text = lbl
                return
            end
            task.wait(0.1)
        end
    end)
    return entry
end

for _, rarity in ipairs(ALL_RARITIES) do
    State.RuneLabels[rarity] = bindParagraph("Runes", "Auto Open Rune", "Inventory & Boost", rarity)
end
State.CandyRateLabel = bindParagraph("Candy", "Candy Farm", "Stats", "Rate")

-- Push initial rune content (so labels reflect any inventory loaded before mount completed).
task.defer(function()
    task.wait(0.5)
    refreshRuneLabels()
    refreshCandyRate()
end)

print("[Cookie Incremental] loaded — open UI: RightShift")
