local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0,0), CFrame.new())
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0,0), CFrame.new())
end)

local function getRemote(name)
    for _, v in game:GetDescendants() do
        if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) and v.Name == name then
            return v
        end
    end
end

local TrashRemote      = getRemote("TrashEvent")
local SellRemote       = getRemote("SellEvent")
local EggRemote        = getRemote("EggEvent")
local CrateRemote      = getRemote("CrateEvent")
local PetRemote        = getRemote("PetEvent")
local PetsRemote       = getRemote("PetsEvent")
local RebirthRemote    = getRemote("RebirthsEvent")
local RankUpRemote     = getRemote("RankUpEvent")
local BackpackRemote   = getRemote("BackpackShopEvent")
local MagnetRemote     = getRemote("MagnetShopEvent")
local AchievRemote     = getRemote("ClaimAchievement")
local ChestRemote      = getRemote("LittleChestsEvent")
local ZoneDoorRemote   = getRemote("ZoneDoorEvent")
local GroupRemote      = getRemote("GroupEvent")
local HatRemote        = getRemote("HatEvent")

local cfg = {
    autoFarm   = false,
    autoSell   = false,
    autoRebirth = false,
    autoHatch  = false,
    autoCrate  = false,
    autoCraft  = false,
    autoRankUp = false,
    farmRate   = 50,
    sellRate   = 5,
    hatchRate  = 5,
    sellZone   = "The Forest",
    eggType    = "Common Egg",
    crateType  = "Common Crate",
}

local trashQueue = {}
local petGUIDs   = {}
local conns      = {}
local active     = {}

local function stopAll()
    for k in pairs(active) do active[k] = false end
    for _, c in ipairs(conns) do if c.Connected then c:Disconnect() end end
    table.clear(conns)
    table.clear(active)
    table.clear(trashQueue)
    table.clear(petGUIDs)
end

local function loop(key, fn)
    active[key] = true
    task.spawn(function()
        while active[key] do
            fn()
            task.wait()
        end
    end)
end

local function throttle(key, rate, fn)
    active[key] = true
    task.spawn(function()
        while active[key] do
            fn()
            task.wait(1 / math.max(rate, 0.1))
        end
    end)
end

-- FARM
local function startFarm()
    if TrashRemote then
        local c = TrashRemote.OnClientEvent:Connect(function(action, data)
            if action == "Render" and data and data[1] then
                trashQueue[data[1]] = true
            end
        end)
        table.insert(conns, c)
        loop("farm", function()
            for guid in pairs(trashQueue) do
                if not active.farm then break end
                pcall(function() TrashRemote:FireServer("Destroy", guid) end)
                trashQueue[guid] = nil
                task.wait(1 / cfg.farmRate)
            end
        end)
    end
end

-- SELL
local function startSell()
    if SellRemote then
        throttle("sell", cfg.sellRate, function()
            pcall(function() SellRemote:FireServer("Sell", cfg.sellZone) end)
        end)
    end
end

-- REBIRTH
local function startRebirth()
    if RebirthRemote then
        throttle("rebirth", 1, function()
            pcall(function() RebirthRemote:FireServer("Max") end)
        end)
    end
end

-- RANK UP
local function startRankUp()
    if RankUpRemote then
        throttle("rankup", 1, function()
            pcall(function() RankUpRemote:FireServer("RankUp") end)
        end)
    end
end

-- HATCH EGGS
local function startHatch()
    if EggRemote then
        throttle("hatch", cfg.hatchRate, function()
            pcall(function() EggRemote:FireServer("HatchMax", cfg.eggType) end)
        end)
    end
end

-- HATCH CRATES
local function startCrate()
    if CrateRemote then
        throttle("crate", cfg.hatchRate, function()
            pcall(function() CrateRemote:FireServer("HatchMax", cfg.crateType) end)
        end)
    end
end

-- CRAFT PETS
local function startCraft()
    if PetsRemote then
        local c = PetsRemote.OnClientEvent:Connect(function(action, playerName, data)
            if action == "XPUpdate" and type(data) == "table" then
                for guid in pairs(data) do
                    petGUIDs[guid] = playerName
                end
            end
        end)
        table.insert(conns, c)
    end
    if PetRemote then
        throttle("craft", 1, function()
            for guid in pairs(petGUIDs) do
                if not active.craft then break end
                pcall(function() PetRemote:FireServer("CraftSize", guid) end)
                task.wait(0.15)
            end
            pcall(function() PetRemote:FireServer("EquipBest") end)
        end)
    end
end

-- ONE-SHOTS
local function claimAchievements()
    if not AchievRemote then return end
    local cats = {
        "Cash","Rebirths","Super Rebirths","EggsHatched",
        "LegendariesHatched","SecretsHatched","GoldensCrafted",
        "RubiesCrafted","PotionsUsed","Gems","TimePlayed","Quests","Farm"
    }
    task.spawn(function()
        for _, cat in ipairs(cats) do
            for i = 1, 25 do
                pcall(function() AchievRemote:InvokeServer(cat, i) end)
                task.wait(0.4)
            end
        end
    end)
end

local function unlockZones()
    if not ZoneDoorRemote then return end
    local zones = {"The Forest","Desert","Farm","Snow","Volcano","Space","Ocean"}
    task.spawn(function()
        for _, z in ipairs(zones) do
            pcall(function() ZoneDoorRemote:FireServer("Buy", z) end)
            task.wait(0.3)
        end
    end)
end

local function buyAllBackpacks()
    if not BackpackRemote then return end
    local zones = {"Spawn","The Forest","Desert","Farm"}
    task.spawn(function()
        for _, z in ipairs(zones) do
            pcall(function() BackpackRemote:FireServer("BuyAll", z) end)
            task.wait(0.3)
        end
    end)
end

local function claimGroup()
    if GroupRemote then pcall(function() GroupRemote:FireServer("Claim") end) end
end

local function equipBest()
    if PetRemote then pcall(function() PetRemote:FireServer("EquipBest") end) end
    if HatRemote then pcall(function() HatRemote:FireServer("EquipBest") end) end
end

-- ======================================================
-- GUI
-- ======================================================

local C = {
    bg      = Color3.fromRGB(14, 14, 22),
    panel   = Color3.fromRGB(22, 22, 36),
    panelHi = Color3.fromRGB(28, 28, 46),
    accent  = Color3.fromRGB(108, 85, 255),
    accentD = Color3.fromRGB(78, 60, 200),
    green   = Color3.fromRGB(72, 199, 116),
    red     = Color3.fromRGB(220, 70, 70),
    text    = Color3.fromRGB(225, 225, 240),
    sub     = Color3.fromRGB(130, 130, 160),
    border  = Color3.fromRGB(42, 42, 65),
    tabOn   = Color3.fromRGB(108, 85, 255),
    tabOff  = Color3.fromRGB(28, 28, 46),
}

local GUI = Instance.new("ScreenGui")
GUI.Name = "MTS_Hub"
GUI.ResetOnSpawn = false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.IgnoreGuiInset = true
GUI.Parent = game:GetService("CoreGui")

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 430, 0, 530)
Main.Position = UDim2.new(0.5, -215, 0.5, -265)
Main.BackgroundColor3 = C.bg
Main.BorderSizePixel = 0
Main.Parent = GUI
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 12)
local ms = Instance.new("UIStroke", Main); ms.Color = C.border; ms.Thickness = 1

-- Title
local TBar = Instance.new("Frame")
TBar.Size = UDim2.new(1, 0, 0, 46)
TBar.BackgroundColor3 = C.panel
TBar.BorderSizePixel = 0
TBar.Parent = Main
Instance.new("UICorner", TBar).CornerRadius = UDim.new(0, 12)
local tfix = Instance.new("Frame")
tfix.Size = UDim2.new(1, 0, 0, 12)
tfix.Position = UDim2.new(0, 0, 1, -12)
tfix.BackgroundColor3 = C.panel
tfix.BorderSizePixel = 0
tfix.Parent = TBar

local TLabel = Instance.new("TextLabel")
TLabel.Text = "Magnet Trash Simulator"
TLabel.Size = UDim2.new(1, -110, 0, 22)
TLabel.Position = UDim2.new(0, 14, 0, 6)
TLabel.BackgroundTransparency = 1
TLabel.TextColor3 = C.text
TLabel.Font = Enum.Font.GothamBold
TLabel.TextSize = 15
TLabel.TextXAlignment = Enum.TextXAlignment.Left
TLabel.Parent = TBar

local TSub = Instance.new("TextLabel")
TSub.Text = "Remote Exploit Suite  |  54 remotes"
TSub.Size = UDim2.new(1, -110, 0, 14)
TSub.Position = UDim2.new(0, 14, 0, 28)
TSub.BackgroundTransparency = 1
TSub.TextColor3 = C.sub
TSub.Font = Enum.Font.Gotham
TSub.TextSize = 10
TSub.TextXAlignment = Enum.TextXAlignment.Left
TSub.Parent = TBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Text = "✕"
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -40, 0, 8)
CloseBtn.BackgroundColor3 = Color3.fromRGB(195, 55, 55)
CloseBtn.TextColor3 = Color3.fromRGB(255,255,255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = TBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local MinBtn = Instance.new("TextButton")
MinBtn.Text = "—"
MinBtn.Size = UDim2.new(0, 30, 0, 30)
MinBtn.Position = UDim2.new(1, -74, 0, 8)
MinBtn.BackgroundColor3 = C.border
MinBtn.TextColor3 = C.text
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 13
MinBtn.BorderSizePixel = 0
MinBtn.Parent = TBar
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(0, 6)

-- Drag
local drag, dragStart, dragPos
TBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        drag = true; dragStart = i.Position; dragPos = Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        Main.Position = UDim2.new(dragPos.X.Scale, dragPos.X.Offset+d.X, dragPos.Y.Scale, dragPos.Y.Offset+d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
end)

-- Minimize
local mini = false
MinBtn.MouseButton1Click:Connect(function()
    mini = not mini
    for _, c in ipairs(Main:GetChildren()) do
        if c ~= TBar then c.Visible = not mini end
    end
    Main.Size = mini and UDim2.new(0,430,0,46) or UDim2.new(0,430,0,530)
end)

-- Unload
local function unload()
    stopAll()
    if GUI and GUI.Parent then GUI:Destroy() end
end
CloseBtn.MouseButton1Click:Connect(unload)

-- Tab bar
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -20, 0, 34)
TabBar.Position = UDim2.new(0, 10, 0, 52)
TabBar.BackgroundColor3 = C.panel
TabBar.BorderSizePixel = 0
TabBar.Parent = Main
Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 8)
local tbl = Instance.new("UIListLayout", TabBar)
tbl.FillDirection = Enum.FillDirection.Horizontal
tbl.Padding = UDim.new(0, 3)
tbl.VerticalAlignment = Enum.VerticalAlignment.Center
local tbp = Instance.new("UIPadding", TabBar)
tbp.PaddingLeft = UDim.new(0,4); tbp.PaddingRight = UDim.new(0,4)
tbp.PaddingTop = UDim.new(0,4); tbp.PaddingBottom = UDim.new(0,4)

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1,-20,1,-100)
Content.Position = UDim2.new(0,10,0,92)
Content.BackgroundTransparency = 1
Content.Parent = Main

local tabs = {}; local pages = {}; local curTab

local function selTab(name)
    for n, p in pairs(pages) do p.Visible = (n==name) end
    for n, b in pairs(tabs) do
        b.BackgroundColor3 = (n==name) and C.tabOn or C.tabOff
        b.TextColor3 = (n==name) and Color3.new(1,1,1) or C.sub
    end
    curTab = name
end

local function mkTab(name)
    local btn = Instance.new("TextButton")
    btn.Text = name
    btn.Size = UDim2.new(0.245,0,1,0)
    btn.BackgroundColor3 = C.tabOff
    btn.TextColor3 = C.sub
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    btn.Parent = TabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
    tabs[name] = btn

    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1,0,1,0)
    sf.BackgroundTransparency = 1
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 3
    sf.ScrollBarImageColor3 = C.accent
    sf.CanvasSize = UDim2.new(0,0,0,0)
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.Visible = false
    sf.Parent = Content
    pages[name] = sf
    local ll = Instance.new("UIListLayout", sf)
    ll.Padding = UDim.new(0,6)
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    local lp = Instance.new("UIPadding", sf)
    lp.PaddingBottom = UDim.new(0,6)
    btn.MouseButton1Click:Connect(function() selTab(name) end)
    return sf
end

local pFarm = mkTab("Farm")
local pShop = mkTab("Shop")
local pPets = mkTab("Pets")
local pMisc = mkTab("Misc")

-- UI helpers
local function row(parent, h, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,h)
    f.BackgroundColor3 = C.panel
    f.BorderSizePixel = 0
    f.LayoutOrder = order or 0
    f.Parent = parent
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local s = Instance.new("UIStroke", f); s.Color = C.border; s.Thickness = 1
    return f
end

local function section(parent, txt, order)
    local l = Instance.new("TextLabel")
    l.Text = "  " .. txt
    l.Size = UDim2.new(1,0,0,20)
    l.BackgroundColor3 = Color3.fromRGB(26,26,42)
    l.TextColor3 = C.accent
    l.Font = Enum.Font.GothamBold
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.BorderSizePixel = 0
    l.LayoutOrder = order or 0
    l.Parent = parent
    Instance.new("UICorner", l).CornerRadius = UDim.new(0,6)
end

local function lbl(parent, txt, size, color, x, y, w, h, bold)
    local l = Instance.new("TextLabel")
    l.Text = txt
    l.Size = UDim2.new(w or 0.7, 0, 0, h or 18)
    l.Position = UDim2.new(x or 0, 12, y or 0, 8)
    l.BackgroundTransparency = 1
    l.TextColor3 = color or C.text
    l.Font = bold == false and Enum.Font.Gotham or Enum.Font.GothamBold
    l.TextSize = size or 13
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function mkToggle(parent, title, sub, order, onToggle)
    local r = row(parent, sub and 56 or 42, order)
    lbl(r, title, 13, C.text, 0, sub and 0 or 0.5, 0.7, sub and 18 or 16)
    if sub then lbl(r, sub, 10, C.sub, 0, 0, 0.7, 14, false).Position = UDim2.new(0,12,0,28) end

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0,44,0,24)
    bg.Position = UDim2.new(1,-56,0.5,-12)
    bg.BackgroundColor3 = C.border
    bg.BorderSizePixel = 0
    bg.Parent = r
    Instance.new("UICorner", bg).CornerRadius = UDim.new(1,0)

    local kn = Instance.new("Frame")
    kn.Size = UDim2.new(0,18,0,18)
    kn.Position = UDim2.new(0,3,0.5,-9)
    kn.BackgroundColor3 = Color3.fromRGB(190,190,210)
    kn.BorderSizePixel = 0
    kn.Parent = bg
    Instance.new("UICorner", kn).CornerRadius = UDim.new(1,0)

    local state = false
    local function set(v)
        state = v
        bg.BackgroundColor3 = v and C.green or C.border
        kn.Position = v and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)
        kn.BackgroundColor3 = v and Color3.new(1,1,1) or Color3.fromRGB(190,190,210)
        onToggle(v)
    end

    local ob = Instance.new("TextButton")
    ob.Size = UDim2.new(1,0,1,0)
    ob.BackgroundTransparency = 1
    ob.Text = ""
    ob.Parent = r
    ob.MouseButton1Click:Connect(function() set(not state) end)
    return set
end

local function mkBtn(parent, title, sub, order, onClick)
    local h = sub and 56 or 42
    local r = row(parent, h, order)
    lbl(r, title, 13, C.text, 0, sub and 0 or 0.5, 0.65, sub and 18 or 16)
    if sub then lbl(r, sub, 10, C.sub, 0, 0, 0.65, 14, false).Position = UDim2.new(0,12,0,30) end

    local b = Instance.new("TextButton")
    b.Text = "Run"
    b.Size = UDim2.new(0,68,0,28)
    b.Position = UDim2.new(1,-80,0.5,-14)
    b.BackgroundColor3 = C.accent
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.BorderSizePixel = 0
    b.Parent = r
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
    b.MouseButton1Click:Connect(function()
        b.BackgroundColor3 = C.accentD
        pcall(onClick)
        task.wait(0.25)
        b.BackgroundColor3 = C.accent
    end)
end

local function mkRate(parent, title, key, default, order)
    local r = row(parent, 52, order)
    lbl(r, title, 13, C.text, 0, 0, 0.65, 18)
    lbl(r, "calls / sec", 10, C.sub, 0, 0, 0.65, 14, false).Position = UDim2.new(0,12,0,28)

    local box = Instance.new("TextBox")
    box.Text = tostring(default)
    box.Size = UDim2.new(0,68,0,28)
    box.Position = UDim2.new(1,-80,0.5,-14)
    box.BackgroundColor3 = C.bg
    box.TextColor3 = C.text
    box.Font = Enum.Font.GothamBold
    box.TextSize = 14
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = true
    box.Parent = r
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,6)
    local bs = Instance.new("UIStroke", box); bs.Color = C.accent; bs.Thickness = 1
    box.FocusLost:Connect(function()
        local v = tonumber(box.Text)
        if v and v > 0 then
            cfg[key] = math.clamp(v, 1, 400)
            box.Text = tostring(cfg[key])
        else
            box.Text = tostring(cfg[key])
        end
    end)
end

-- ============================================================
-- FARM PAGE
-- ============================================================
section(pFarm, "AUTO COLLECT", 1)
mkToggle(pFarm, "Auto Farm Trash", "Перехват Render → мгновенный Destroy", 2, function(v)
    cfg.autoFarm = v
    if v then active.farm = false; startFarm() else active.farm = false end
end)
mkRate(pFarm, "Farm Rate", "farmRate", 50, 3)

section(pFarm, "AUTO SELL", 4)
mkToggle(pFarm, "Auto Sell", "SellEvent → The Forest (max value)", 5, function(v)
    cfg.autoSell = v
    if v then active.sell = false; startSell() else active.sell = false end
end)
mkRate(pFarm, "Sell Rate", "sellRate", 5, 6)

section(pFarm, "REBIRTH & RANK", 7)
mkToggle(pFarm, "Auto Rebirth", "RebirthsEvent Max — по наличию cash", 8, function(v)
    cfg.autoRebirth = v
    if v then active.rebirth = false; startRebirth() else active.rebirth = false end
end)
mkToggle(pFarm, "Auto Rank Up", "RankUpEvent — при достаточных rebirths", 9, function(v)
    cfg.autoRankUp = v
    if v then active.rankup = false; startRankUp() else active.rankup = false end
end)

-- ============================================================
-- SHOP PAGE
-- ============================================================
section(pShop, "AUTO HATCH", 1)
mkToggle(pShop, "Auto Hatch Eggs", "EggEvent HatchMax — Common Egg", 2, function(v)
    cfg.autoHatch = v
    if v then active.hatch = false; startHatch() else active.hatch = false end
end)
mkToggle(pShop, "Auto Hatch Crates", "CrateEvent HatchMax — Common Crate", 3, function(v)
    cfg.autoCrate = v
    if v then active.crate = false; startCrate() else active.crate = false end
end)
mkRate(pShop, "Hatch Rate", "hatchRate", 5, 4)

section(pShop, "ONE-CLICK ACTIONS", 5)
mkBtn(pShop, "Claim All Achievements", "Перебор всех категорий × 25 тиров", 6, claimAchievements)
mkBtn(pShop, "Buy All Backpacks", "BackpackShopEvent BuyAll по всем зонам", 7, buyAllBackpacks)
mkBtn(pShop, "Unlock All Zones", "ZoneDoorEvent Buy для всех зон", 8, unlockZones)
mkBtn(pShop, "Claim Group Reward", "GroupEvent Claim", 9, claimGroup)

-- ============================================================
-- PETS PAGE
-- ============================================================
section(pPets, "AUTO MANAGE", 1)
mkToggle(pPets, "Auto Craft & Equip", "CraftSize всех GUID из XPUpdate потока", 2, function(v)
    cfg.autoCraft = v
    if v then active.craft = false; startCraft() else active.craft = false end
end)
mkBtn(pPets, "Equip Best (сейчас)", "PetEvent EquipBest + HatEvent EquipBest", 3, equipBest)

section(pPets, "СТАТУС", 4)

local petInfo = Instance.new("TextLabel")
petInfo.Size = UDim2.new(1,0,0,80)
petInfo.BackgroundColor3 = C.panel
petInfo.TextColor3 = C.sub
petInfo.Font = Enum.Font.Code
petInfo.TextSize = 11
petInfo.TextXAlignment = Enum.TextXAlignment.Left
petInfo.TextYAlignment = Enum.TextYAlignment.Top
petInfo.TextWrapped = true
petInfo.BorderSizePixel = 0
petInfo.LayoutOrder = 5
petInfo.Parent = pPets
Instance.new("UICorner", petInfo).CornerRadius = UDim.new(0,8)
local pip = Instance.new("UIPadding", petInfo)
pip.PaddingAll = UDim.new(0,8)

task.spawn(function()
    while GUI.Parent do
        local cnt = 0
        for _ in pairs(petGUIDs) do cnt = cnt + 1 end
        petInfo.Text = string.format(
            "Pet GUIDs (свои + чужие из XPUpdate): %d\n\nXPUpdate рассылается ВСЕМ — собираем GUID\nвсех игроков, пробуем CraftSize на каждый.\nСервер отклонит чужие, но своих прокачает.",
            cnt
        )
        task.wait(1)
    end
end)

-- ============================================================
-- MISC PAGE
-- ============================================================
section(pMisc, "ДВИЖЕНИЕ", 1)
mkBtn(pMisc, "Speed x2.5", "WalkSpeed 40 / JumpPower 80", 2, function()
    local c = LocalPlayer.Character
    if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = 40; h.JumpPower = 80 end
    end
end)
mkBtn(pMisc, "Speed x5", "WalkSpeed 80 / JumpPower 100", 3, function()
    local c = LocalPlayer.Character
    if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = 80; h.JumpPower = 100 end
    end
end)
mkBtn(pMisc, "Reset Speed", "Восстановить WalkSpeed 16 / JumpPower 50", 4, function()
    local c = LocalPlayer.Character
    if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = 16; h.JumpPower = 50 end
    end
end)

section(pMisc, "REMOTE СТАТУС", 5)

local remInfo = Instance.new("TextLabel")
remInfo.Size = UDim2.new(1,0,0,165)
remInfo.BackgroundColor3 = C.panel
remInfo.TextColor3 = C.sub
remInfo.Font = Enum.Font.Code
remInfo.TextSize = 10
remInfo.TextXAlignment = Enum.TextXAlignment.Left
remInfo.TextYAlignment = Enum.TextYAlignment.Top
remInfo.BorderSizePixel = 0
remInfo.LayoutOrder = 6
remInfo.Parent = pMisc
Instance.new("UICorner", remInfo).CornerRadius = UDim.new(0,8)
local rip = Instance.new("UIPadding", remInfo); rip.PaddingAll = UDim.new(0,8)

local function tick(r) return r and "✓" or "✗" end
remInfo.Text = string.format(
    "TrashEvent    %s     SellEvent     %s\n" ..
    "EggEvent      %s     CrateEvent    %s\n" ..
    "PetEvent      %s     PetsEvent     %s\n" ..
    "RebirthsEvent %s     RankUpEvent   %s\n" ..
    "BackpackShop  %s     MagnetShop    %s\n" ..
    "ClaimAchiev   %s     LittleChests  %s\n" ..
    "ZoneDoorEvent %s     GroupEvent    %s\n" ..
    "HatEvent      %s",
    tick(TrashRemote), tick(SellRemote),
    tick(EggRemote),   tick(CrateRemote),
    tick(PetRemote),   tick(PetsRemote),
    tick(RebirthRemote), tick(RankUpRemote),
    tick(BackpackRemote), tick(MagnetRemote),
    tick(AchievRemote), tick(ChestRemote),
    tick(ZoneDoorRemote), tick(GroupRemote),
    tick(HatRemote)
)

selTab("Farm")
