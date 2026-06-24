if _G.MTS_Unload then _G.MTS_Unload() end
task.wait(0.1)

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local VU           = game:GetService("VirtualUser")
local lp           = Players.LocalPlayer
local RS           = game:GetService("ReplicatedStorage")
local ev           = RS.Events.RemoteEvents

local TR  = ev:WaitForChild("TrashEvent")
local SR  = ev:FindFirstChild("SellEvent")
local ER  = ev:FindFirstChild("EggEvent")
local CR  = ev:FindFirstChild("CrateEvent")
local PR  = ev:FindFirstChild("PetEvent")
local PSR = ev:FindFirstChild("PetsEvent")
local RBR = ev:FindFirstChild("RebirthsEvent")
local RUR = ev:FindFirstChild("RankUpEvent")
local BPR = ev:FindFirstChild("BackpackShopEvent")
local ZDR = ev:FindFirstChild("ZoneDoorEvent")
local GR  = ev:FindFirstChild("GroupEvent")
local HR  = ev:FindFirstChild("HatEvent")
local ACH = ev:FindFirstChild("ClaimAchievement")

local cfg = {
    farmRate    = 50,
    sellRate    = 5,
    hatchRate   = 5,
    crateRate   = 5,
}

local active  = {}
local conns   = {}
local petGUID = {}
local trashBuf = {}
local stats   = { trash = 0, sells = 0 }

lp.Idled:Connect(function()
    VU:Button2Down(Vector2.new(0,0), CFrame.new())
    task.wait(1)
    VU:Button2Up(Vector2.new(0,0), CFrame.new())
end)

local function addConn(c) conns[#conns+1] = c end

local function startLoop(key, fn, getRate)
    active[key] = true
    task.spawn(function()
        while active[key] do
            pcall(fn)
            task.wait(1 / math.max(getRate(), 1))
        end
    end)
end

local function stopKey(key) active[key] = false end

-- FARM
local function startFarm()
    local c = TR.OnClientEvent:Connect(function(a, d)
        if a == "Render" and d and d[1] then
            trashBuf[#trashBuf+1] = d[1]
        end
    end)
    addConn(c)
    active.farm = true
    task.spawn(function()
        while active.farm do
            if #trashBuf > 0 then
                local b = trashBuf
                trashBuf = {}
                for i = 1, #b do
                    if not active.farm then break end
                    pcall(function() TR:FireServer("Destroy", b[i]) end)
                    stats.trash = stats.trash + 1
                    task.wait(1 / cfg.farmRate)
                end
            else
                task.wait(0.05)
            end
        end
    end)
end

-- SELL
local function startSell()
    startLoop("sell", function()
        if SR then SR:FireServer("Sell", "The Forest") end
        stats.sells = stats.sells + 1
    end, function() return cfg.sellRate end)
end

-- REBIRTH
local function startRebirth()
    startLoop("rebirth", function()
        if RBR then RBR:FireServer("Max") end
    end, function() return 1 end)
end

-- RANK UP
local function startRankUp()
    startLoop("rankup", function()
        if RUR then RUR:FireServer("RankUp") end
    end, function() return 1 end)
end

-- HATCH EGGS
local function startHatch()
    startLoop("hatch", function()
        if ER then ER:FireServer("HatchMax", "Common Egg") end
    end, function() return cfg.hatchRate end)
end

-- HATCH CRATES
local function startCrate()
    startLoop("crate", function()
        if CR then CR:FireServer("HatchMax", "Common Crate") end
    end, function() return cfg.crateRate end)
end

-- CRAFT PETS
local function startCraft()
    if PSR then
        local c = PSR.OnClientEvent:Connect(function(action, _, data)
            if action == "XPUpdate" and type(data) == "table" then
                for guid in pairs(data) do petGUID[guid] = true end
            end
        end)
        addConn(c)
    end
    active.craft = true
    task.spawn(function()
        while active.craft do
            for guid in pairs(petGUID) do
                if not active.craft then break end
                pcall(function() if PR then PR:FireServer("CraftSize", guid) end end)
                task.wait(0.15)
            end
            pcall(function() if PR then PR:FireServer("EquipBest") end end)
            task.wait(1)
        end
    end)
end

-- ONE-SHOTS
local function claimAll()
    task.spawn(function()
        if not ACH then return end
        local cats = {
            "Cash","Rebirths","Super Rebirths","EggsHatched",
            "LegendariesHatched","SecretsHatched","GoldensCrafted",
            "RubiesCrafted","PotionsUsed","Gems","TimePlayed","Quests","Farm"
        }
        for _, cat in ipairs(cats) do
            for i = 1, 25 do
                pcall(function() ACH:InvokeServer(cat, i) end)
                task.wait(0.4)
            end
        end
    end)
end

local function buyAllBP()
    task.spawn(function()
        for _, z in ipairs({"Spawn","The Forest","Desert","Farm"}) do
            pcall(function() if BPR then BPR:FireServer("BuyAll", z) end end)
            task.wait(0.3)
        end
    end)
end

local function unlockZones()
    task.spawn(function()
        for _, z in ipairs({"The Forest","Desert","Farm","Snow","Volcano"}) do
            pcall(function() if ZDR then ZDR:FireServer("Buy", z) end end)
            task.wait(0.3)
        end
    end)
end

local function claimGroup() pcall(function() if GR then GR:FireServer("Claim") end end) end

local function equipBest()
    pcall(function() if PR then PR:FireServer("EquipBest") end end)
    pcall(function() if HR then HR:FireServer("EquipBest") end end)
end

-- ============================================================
-- GUI
-- ============================================================

local C = {
    bg       = Color3.fromRGB(13, 13, 20),
    panel    = Color3.fromRGB(20, 20, 32),
    panelB   = Color3.fromRGB(26, 26, 44),
    accent   = Color3.fromRGB(120, 90, 255),
    accentD  = Color3.fromRGB(85, 60, 200),
    green    = Color3.fromRGB(65, 190, 110),
    red      = Color3.fromRGB(210, 65, 65),
    text     = Color3.fromRGB(230, 230, 245),
    sub      = Color3.fromRGB(120, 120, 155),
    border   = Color3.fromRGB(38, 38, 62),
    tabOn    = Color3.fromRGB(120, 90, 255),
    tabOff   = Color3.fromRGB(24, 24, 40),
    section  = Color3.fromRGB(16, 16, 28),
}

local GUI = Instance.new("ScreenGui")
GUI.Name = "MTS_Hub"
GUI.ResetOnSpawn = false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.IgnoreGuiInset = true
GUI.Parent = game:GetService("CoreGui")

_G.MTS_Unload = function()
    active = {}
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    if GUI and GUI.Parent then GUI:Destroy() end
    _G.MTS_Unload = nil
end

-- WINDOW
local Win = Instance.new("Frame")
Win.Name = "Win"
Win.Size = UDim2.new(0, 440, 0, 545)
Win.Position = UDim2.new(0.5, -220, 0.5, -272)
Win.BackgroundColor3 = C.bg
Win.BorderSizePixel = 0
Win.Parent = GUI
local winC = Instance.new("UICorner", Win); winC.CornerRadius = UDim.new(0, 12)
local winS = Instance.new("UIStroke", Win); winS.Color = C.border; winS.Thickness = 1

-- TITLE BAR
local TBar = Instance.new("Frame")
TBar.Size = UDim2.new(1, 0, 0, 48)
TBar.BackgroundColor3 = C.panel
TBar.BorderSizePixel = 0
TBar.Parent = Win
Instance.new("UICorner", TBar).CornerRadius = UDim.new(0, 12)
local tFix = Instance.new("Frame")
tFix.Size = UDim2.new(1, 0, 0, 12)
tFix.Position = UDim2.new(0, 0, 1, -12)
tFix.BackgroundColor3 = C.panel
tFix.BorderSizePixel = 0
tFix.Parent = TBar

-- Accent strip
local strip = Instance.new("Frame")
strip.Size = UDim2.new(0, 3, 0, 24)
strip.Position = UDim2.new(0, 0, 0.5, -12)
strip.BackgroundColor3 = C.accent
strip.BorderSizePixel = 0
strip.Parent = TBar
Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 2)

local TTitle = Instance.new("TextLabel")
TTitle.Text = "Magnet Trash Simulator"
TTitle.Size = UDim2.new(1, -120, 0, 22)
TTitle.Position = UDim2.new(0, 16, 0, 5)
TTitle.BackgroundTransparency = 1
TTitle.TextColor3 = C.text
TTitle.Font = Enum.Font.GothamBold
TTitle.TextSize = 15
TTitle.TextXAlignment = Enum.TextXAlignment.Left
TTitle.Parent = TBar

local TSub = Instance.new("TextLabel")
TSub.Text = "Remote Suite  ·  Magnet Trash"
TSub.Size = UDim2.new(1, -120, 0, 14)
TSub.Position = UDim2.new(0, 16, 0, 28)
TSub.BackgroundTransparency = 1
TSub.TextColor3 = C.sub
TSub.Font = Enum.Font.Gotham
TSub.TextSize = 10
TSub.TextXAlignment = Enum.TextXAlignment.Left
TSub.Parent = TBar

local function mkTBtn(txt, bg, xOff)
    local b = Instance.new("TextButton")
    b.Text = txt
    b.Size = UDim2.new(0, 28, 0, 28)
    b.Position = UDim2.new(1, xOff, 0, 10)
    b.BackgroundColor3 = bg
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.BorderSizePixel = 0
    b.Parent = TBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local CloseB = mkTBtn("✕", C.red, -38)
local MinB   = mkTBtn("—", C.border, -70)

-- Drag
local dragging, dStart, dPos
TBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dStart = i.Position; dPos = Win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dStart
        Win.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset+d.X, dPos.Y.Scale, dPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

CloseB.MouseButton1Click:Connect(function() _G.MTS_Unload() end)

local minimized = false
MinB.MouseButton1Click:Connect(function()
    minimized = not minimized
    for _, ch in ipairs(Win:GetChildren()) do
        if ch ~= TBar then ch.Visible = not minimized end
    end
    Win.Size = minimized and UDim2.new(0,440,0,48) or UDim2.new(0,440,0,545)
end)

-- STATS BAR
local StatsBar = Instance.new("Frame")
StatsBar.Size = UDim2.new(1, -20, 0, 28)
StatsBar.Position = UDim2.new(0, 10, 0, 54)
StatsBar.BackgroundColor3 = C.panelB
StatsBar.BorderSizePixel = 0
StatsBar.Parent = Win
Instance.new("UICorner", StatsBar).CornerRadius = UDim.new(0, 7)

local statsLbl = Instance.new("TextLabel")
statsLbl.Size = UDim2.new(1, -16, 1, 0)
statsLbl.Position = UDim2.new(0, 8, 0, 0)
statsLbl.BackgroundTransparency = 1
statsLbl.TextColor3 = C.sub
statsLbl.Font = Enum.Font.Code
statsLbl.TextSize = 11
statsLbl.TextXAlignment = Enum.TextXAlignment.Left
statsLbl.Parent = StatsBar

task.spawn(function()
    while GUI.Parent do
        local cnt = 0; for _ in pairs(petGUID) do cnt=cnt+1 end
        statsLbl.Text = string.format(
            "  🗑 Trash: %d   💰 Sells: %d   🐾 Pet GUIDs: %d",
            stats.trash, stats.sells, cnt
        )
        task.wait(1)
    end
end)

-- TABS
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -20, 0, 32)
TabBar.Position = UDim2.new(0, 10, 0, 88)
TabBar.BackgroundColor3 = C.panel
TabBar.BorderSizePixel = 0
TabBar.Parent = Win
Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 8)
local tbl = Instance.new("UIListLayout", TabBar)
tbl.FillDirection = Enum.FillDirection.Horizontal
tbl.Padding = UDim.new(0, 3)
tbl.VerticalAlignment = Enum.VerticalAlignment.Center
local tbp = Instance.new("UIPadding", TabBar)
tbp.PaddingLeft = UDim.new(0,4); tbp.PaddingRight = UDim.new(0,4)
tbp.PaddingTop = UDim.new(0,4); tbp.PaddingBottom = UDim.new(0,4)

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1,-20,1,-130)
Content.Position = UDim2.new(0,10,0,126)
Content.BackgroundTransparency = 1
Content.Parent = Win

local tabBtns = {}; local tabPages = {}

local function selTab(name)
    for n,p in pairs(tabPages) do p.Visible = (n==name) end
    for n,b in pairs(tabBtns) do
        b.BackgroundColor3 = (n==name) and C.tabOn or C.tabOff
        b.TextColor3 = (n==name) and Color3.new(1,1,1) or C.sub
    end
end

local function mkTab(name)
    local btn = Instance.new("TextButton")
    btn.Text = name
    btn.Size = UDim2.new(0.245, 0, 1, 0)
    btn.BackgroundColor3 = C.tabOff
    btn.TextColor3 = C.sub
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    btn.Parent = TabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    tabBtns[name] = btn

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
    tabPages[name] = sf
    Instance.new("UIListLayout", sf).Padding = UDim.new(0,6)
    local p = Instance.new("UIPadding", sf); p.PaddingBottom = UDim.new(0,6)
    btn.MouseButton1Click:Connect(function() selTab(name) end)
    return sf
end

local pFarm = mkTab("Farm")
local pShop = mkTab("Shop")
local pPets = mkTab("Pets")
local pMisc = mkTab("Misc")

-- ============================================================
-- WIDGET HELPERS
-- ============================================================

local function secLabel(parent, txt, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,22)
    f.BackgroundColor3 = C.section
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    local s = Instance.new("UIStroke",f); s.Color = C.border; s.Thickness = 1
    Instance.new("UICorner",f).CornerRadius = UDim.new(0,6)
    local l = Instance.new("TextLabel",f)
    l.Text = "  ▸  " .. txt
    l.Size = UDim2.new(1,0,1,0)
    l.BackgroundTransparency = 1
    l.TextColor3 = C.accent
    l.Font = Enum.Font.GothamBold
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
end

local function mkRow(parent, h, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,h)
    f.BackgroundColor3 = C.panel
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    Instance.new("UICorner",f).CornerRadius = UDim.new(0,8)
    local s = Instance.new("UIStroke",f); s.Color = C.border; s.Thickness = 1
    return f
end

local function rowLabel(parent, title, sub)
    local t = Instance.new("TextLabel",parent)
    t.Text = title
    t.Size = UDim2.new(0.62,0,0,18)
    t.Position = UDim2.new(0,12,0,sub and 6 or 0.5)
    t.AnchorPoint = sub and Vector2.new(0,0) or Vector2.new(0,0.5)
    if not sub then t.Position = UDim2.new(0,12,0.5,0); t.AnchorPoint = Vector2.new(0,0.5) end
    t.BackgroundTransparency = 1
    t.TextColor3 = C.text
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.TextXAlignment = Enum.TextXAlignment.Left
    if sub then
        local s = Instance.new("TextLabel",parent)
        s.Text = sub
        s.Size = UDim2.new(0.62,0,0,13)
        s.Position = UDim2.new(0,12,0,26)
        s.BackgroundTransparency = 1
        s.TextColor3 = C.sub
        s.Font = Enum.Font.Gotham
        s.TextSize = 10
        s.TextXAlignment = Enum.TextXAlignment.Left
    end
end

local function mkToggle(parent, title, sub, order, onToggle)
    local h = sub and 52 or 40
    local r = mkRow(parent, h, order)
    rowLabel(r, title, sub)

    local bg = Instance.new("Frame",r)
    bg.Size = UDim2.new(0,42,0,22)
    bg.Position = UDim2.new(1,-54,0.5,-11)
    bg.BackgroundColor3 = C.border
    bg.BorderSizePixel = 0
    Instance.new("UICorner",bg).CornerRadius = UDim.new(1,0)

    local kn = Instance.new("Frame",bg)
    kn.Size = UDim2.new(0,16,0,16)
    kn.Position = UDim2.new(0,3,0.5,-8)
    kn.BackgroundColor3 = Color3.fromRGB(180,180,200)
    kn.BorderSizePixel = 0
    Instance.new("UICorner",kn).CornerRadius = UDim.new(1,0)

    local on = false
    local function set(v)
        on = v
        bg.BackgroundColor3 = v and C.green or C.border
        kn.Position = v and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)
        kn.BackgroundColor3 = v and Color3.new(1,1,1) or Color3.fromRGB(180,180,200)
        onToggle(v)
    end
    local ob = Instance.new("TextButton",r)
    ob.Size = UDim2.new(1,0,1,0)
    ob.BackgroundTransparency = 1
    ob.Text = ""
    ob.MouseButton1Click:Connect(function() set(not on) end)
    return set
end

local function mkButton(parent, title, sub, order, onClick)
    local h = sub and 52 or 40
    local r = mkRow(parent, h, order)
    rowLabel(r, title, sub)
    local b = Instance.new("TextButton",r)
    b.Text = "Run"
    b.Size = UDim2.new(0,62,0,26)
    b.Position = UDim2.new(1,-74,0.5,-13)
    b.BackgroundColor3 = C.accent
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.BorderSizePixel = 0
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,6)
    b.MouseButton1Click:Connect(function()
        b.BackgroundColor3 = C.accentD
        pcall(onClick)
        task.wait(0.2); b.BackgroundColor3 = C.accent
    end)
end

local function mkRate(parent, title, key, default, order)
    local r = mkRow(parent, 50, order)
    rowLabel(r, title, "calls / sec")
    local box = Instance.new("TextBox",r)
    box.Text = tostring(default)
    box.Size = UDim2.new(0,62,0,26)
    box.Position = UDim2.new(1,-74,0.5,-13)
    box.BackgroundColor3 = C.bg
    box.TextColor3 = C.text
    box.Font = Enum.Font.GothamBold
    box.TextSize = 13
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = true
    Instance.new("UICorner",box).CornerRadius = UDim.new(0,6)
    local bs = Instance.new("UIStroke",box); bs.Color = C.accent; bs.Thickness = 1
    box.FocusLost:Connect(function()
        local v = tonumber(box.Text)
        if v and v >= 1 then
            cfg[key] = math.clamp(v, 1, 400)
            box.Text = tostring(cfg[key])
        else
            box.Text = tostring(cfg[key])
        end
    end)
end

-- ============================================================
-- FARM TAB
-- ============================================================
secLabel(pFarm, "СБОР МУСОРА", 1)
mkToggle(pFarm, "Auto Farm Trash", "Render → мгновенный Destroy", 2, function(v)
    if v then startFarm() else active.farm = false end
end)
mkRate(pFarm, "Farm Rate", "farmRate", 50, 3)

secLabel(pFarm, "ПРОДАЖА", 4)
mkToggle(pFarm, "Auto Sell", "SellEvent The Forest", 5, function(v)
    if v then startSell() else stopKey("sell") end
end)
mkRate(pFarm, "Sell Rate", "sellRate", 5, 6)

secLabel(pFarm, "ПРОГРЕССИЯ", 7)
mkToggle(pFarm, "Auto Rebirth", "Max ребёрс за раз", 8, function(v)
    if v then startRebirth() else stopKey("rebirth") end
end)
mkToggle(pFarm, "Auto Rank Up", "RankUpEvent", 9, function(v)
    if v then startRankUp() else stopKey("rankup") end
end)

-- ============================================================
-- SHOP TAB
-- ============================================================
secLabel(pShop, "ХАТЧИНГ", 1)
mkToggle(pShop, "Auto Hatch Eggs", "EggEvent HatchMax Common Egg", 2, function(v)
    if v then startHatch() else stopKey("hatch") end
end)
mkToggle(pShop, "Auto Hatch Crates", "CrateEvent HatchMax Common Crate", 3, function(v)
    if v then startCrate() else stopKey("crate") end
end)
mkRate(pShop, "Hatch Rate", "hatchRate", 5, 4)

secLabel(pShop, "БЫСТРЫЕ ДЕЙСТВИЯ", 5)
mkButton(pShop, "Claim All Achievements", "Все категории × 25 тиров", 6, claimAll)
mkButton(pShop, "Buy All Backpacks", "BuyAll по всем зонам", 7, buyAllBP)
mkButton(pShop, "Unlock All Zones", "ZoneDoorEvent Buy", 8, unlockZones)
mkButton(pShop, "Claim Group Reward", "GroupEvent Claim", 9, claimGroup)

-- ============================================================
-- PETS TAB
-- ============================================================
secLabel(pPets, "ПИТОМЦЫ", 1)
mkToggle(pPets, "Auto Craft & Equip", "CraftSize из XPUpdate потока", 2, function(v)
    if v then startCraft() else active.craft = false end
end)
mkButton(pPets, "Equip Best (сейчас)", "PetEvent + HatEvent EquipBest", 3, equipBest)

secLabel(pPets, "СТАТУС", 4)
local petInfoRow = mkRow(pPets, 70, 5)
local petInfoLbl = Instance.new("TextLabel", petInfoRow)
petInfoLbl.Size = UDim2.new(1,-20,1,-16)
petInfoLbl.Position = UDim2.new(0,10,0,8)
petInfoLbl.BackgroundTransparency = 1
petInfoLbl.TextColor3 = C.sub
petInfoLbl.Font = Enum.Font.Code
petInfoLbl.TextSize = 11
petInfoLbl.TextXAlignment = Enum.TextXAlignment.Left
petInfoLbl.TextYAlignment = Enum.TextYAlignment.Top
petInfoLbl.TextWrapped = true
task.spawn(function()
    while GUI.Parent do
        local cnt = 0; for _ in pairs(petGUID) do cnt=cnt+1 end
        petInfoLbl.Text = string.format(
            "Pet GUIDs (свои + чужие из XPUpdate): %d\nCraftSize пробует каждый — чужие сервер отклонит",
            cnt
        )
        task.wait(1)
    end
end)

-- ============================================================
-- MISC TAB
-- ============================================================
secLabel(pMisc, "ДВИЖЕНИЕ", 1)
mkButton(pMisc, "Speed ×2.5", "WalkSpeed 40 / JumpPower 75", 2, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed=40; h.JumpPower=75 end
    end
end)
mkButton(pMisc, "Speed ×5", "WalkSpeed 80 / JumpPower 100", 3, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed=80; h.JumpPower=100 end
    end
end)
mkButton(pMisc, "Reset Speed", "WalkSpeed 16 / JumpPower 50", 4, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed=16; h.JumpPower=50 end
    end
end)

secLabel(pMisc, "REMOTE СТАТУС", 5)
local remRow = mkRow(pMisc, 155, 6)
local remLbl = Instance.new("TextLabel", remRow)
remLbl.Size = UDim2.new(1,-20,1,-16)
remLbl.Position = UDim2.new(0,10,0,8)
remLbl.BackgroundTransparency = 1
remLbl.TextColor3 = C.sub
remLbl.Font = Enum.Font.Code
remLbl.TextSize = 10
remLbl.TextXAlignment = Enum.TextXAlignment.Left
remLbl.TextYAlignment = Enum.TextYAlignment.Top
remLbl.TextWrapped = false
local function t(r) return r and "✓" or "✗" end
remLbl.Text = string.format(
    "TrashEvent    %s     SellEvent     %s\nEggEvent      %s     CrateEvent    %s\nPetEvent      %s     PetsEvent     %s\nRebirthsEvent %s     RankUpEvent   %s\nBackpackShop  %s     ZoneDoor      %s\nGroupEvent    %s     HatEvent      %s\nClaimAchiev   %s",
    t(TR),t(SR),t(ER),t(CR),t(PR),t(PSR),t(RBR),t(RUR),t(BPR),t(ZDR),t(GR),t(HR),t(ACH)
)

-- ============================================================
selTab("Farm")
