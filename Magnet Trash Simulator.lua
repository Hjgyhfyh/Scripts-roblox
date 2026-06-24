if _G.MTS_Unload then _G.MTS_Unload() end
task.wait(0.1)

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local VU           = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")
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
local running = true

local function addConn(c) conns[#conns+1] = c end

addConn(lp.Idled:Connect(function()
    VU:Button2Down(Vector2.new(0,0), CFrame.new())
    task.wait(1)
    VU:Button2Up(Vector2.new(0,0), CFrame.new())
end))

local function startLoop(key, fn, getRate)
    if active[key] then return end
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
    if active.farm then return end
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
    if active.craft then return end
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
            local snap = {}
            for g in pairs(petGUID) do snap[#snap+1] = g end
            for i = 1, #snap do
                if not active.craft then break end
                pcall(function() if PR then PR:FireServer("CraftSize", snap[i]) end end)
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

local C = {
    bg       = Color3.fromRGB(13, 13, 20),
    panel    = Color3.fromRGB(20, 20, 32),
    panelB   = Color3.fromRGB(26, 26, 44),
    accent   = Color3.fromRGB(120, 90, 255),
    accentD  = Color3.fromRGB(85, 60, 200),
    green    = Color3.fromRGB(65, 190, 110),
    yellow   = Color3.fromRGB(235, 200, 90),
    purple   = Color3.fromRGB(170, 130, 255),
    red      = Color3.fromRGB(210, 65, 65),
    redD     = Color3.fromRGB(160, 45, 45),
    text     = Color3.fromRGB(230, 230, 245),
    sub      = Color3.fromRGB(120, 120, 155),
    border   = Color3.fromRGB(38, 38, 62),
    tabOn    = Color3.fromRGB(120, 90, 255),
    tabOff   = Color3.fromRGB(24, 24, 40),
    section  = Color3.fromRGB(16, 16, 28),
}

local TW_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_MED  = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function tween(obj, info, props)
    local t = TweenService:Create(obj, info, props)
    t:Play()
    return t
end

local GUI = Instance.new("ScreenGui")
GUI.Name = "MTS_Hub"
GUI.ResetOnSpawn = false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.IgnoreGuiInset = true
GUI.Parent = game:GetService("CoreGui")

_G.MTS_Unload = function()
    running = false
    active = {}
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    if GUI and GUI.Parent then GUI:Destroy() end
    _G.MTS_Unload = nil
end

local Shadow = Instance.new("Frame")
Shadow.Name = "Shadow"
Shadow.Size = UDim2.new(0, 448, 0, 553)
Shadow.Position = UDim2.new(0.5, -224, 0.5, -268)
Shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Shadow.BackgroundTransparency = 0.7
Shadow.BorderSizePixel = 0
Shadow.ZIndex = 0
Shadow.Parent = GUI
local shC = Instance.new("UICorner", Shadow); shC.CornerRadius = UDim.new(0, 16)

local Win = Instance.new("Frame")
Win.Name = "Win"
Win.Size = UDim2.new(0, 440, 0, 545)
Win.Position = UDim2.new(0.5, -220, 0.5, -272)
Win.BackgroundColor3 = C.bg
Win.BorderSizePixel = 0
Win.ZIndex = 1
Win.Parent = GUI
local winC = Instance.new("UICorner", Win); winC.CornerRadius = UDim.new(0, 12)
local winS = Instance.new("UIStroke", Win); winS.Color = C.border; winS.Thickness = 1

local TBar = Instance.new("Frame")
TBar.Size = UDim2.new(1, 0, 0, 48)
TBar.BackgroundColor3 = C.panel
TBar.BorderSizePixel = 0
TBar.Parent = Win
Instance.new("UICorner", TBar).CornerRadius = UDim.new(0, 12)
local tBarGrad = Instance.new("UIGradient", TBar)
tBarGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, C.accentD),
    ColorSequenceKeypoint.new(0.45, C.panel),
    ColorSequenceKeypoint.new(1, C.panel),
})
tBarGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.55),
    NumberSequenceKeypoint.new(0.5, 1),
    NumberSequenceKeypoint.new(1, 1),
})
local tFix = Instance.new("Frame")
tFix.Size = UDim2.new(1, 0, 0, 12)
tFix.Position = UDim2.new(0, 0, 1, -12)
tFix.BackgroundColor3 = C.panel
tFix.BorderSizePixel = 0
tFix.Parent = TBar

local strip = Instance.new("Frame")
strip.Size = UDim2.new(0, 3, 0, 24)
strip.Position = UDim2.new(0, 0, 0.5, -12)
strip.BackgroundColor3 = C.accent
strip.BorderSizePixel = 0
strip.Parent = TBar
Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 2)
task.spawn(function()
    while running and strip.Parent do
        tween(strip, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.6})
        task.wait(1)
        if not (running and strip.Parent) then break end
        tween(strip, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0})
        task.wait(1)
    end
end)

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

local function mkTBtn(txt, bg, bgHover, xOff)
    local b = Instance.new("TextButton")
    b.Text = txt
    b.Size = UDim2.new(0, 28, 0, 28)
    b.Position = UDim2.new(1, xOff, 0, 10)
    b.BackgroundColor3 = bg
    b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.Parent = TBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    addConn(b.MouseEnter:Connect(function()
        tween(b, TW_FAST, {BackgroundColor3 = bgHover})
    end))
    addConn(b.MouseLeave:Connect(function()
        tween(b, TW_FAST, {BackgroundColor3 = bg})
    end))
    return b
end

local CloseB = mkTBtn("✕", C.red, C.redD, -38)
local MinB   = mkTBtn("—", C.border, C.accentD, -70)

local dragging, dStart, dPos
addConn(TBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dStart = i.Position; dPos = Win.Position
    end
end))
addConn(UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        Win.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset+d.X, dPos.Y.Scale, dPos.Y.Offset+d.Y)
        Shadow.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset+d.X-4, dPos.Y.Scale, dPos.Y.Offset+d.Y-4)
    end
end))
addConn(UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
end))

addConn(CloseB.MouseButton1Click:Connect(function() _G.MTS_Unload() end))

local minimized = false
addConn(MinB.MouseButton1Click:Connect(function()
    minimized = not minimized
    for _, ch in ipairs(Win:GetChildren()) do
        if ch ~= TBar and ch:IsA("GuiObject") then ch.Visible = not minimized end
    end
    local sz   = minimized and UDim2.new(0,440,0,48) or UDim2.new(0,440,0,545)
    local shSz = minimized and UDim2.new(0,448,0,56) or UDim2.new(0,448,0,553)
    tween(Win, TW_MED, {Size = sz})
    tween(Shadow, TW_MED, {Size = shSz})
end))

local guiHidden = false
addConn(UIS.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.Insert then
        guiHidden = not guiHidden
        Win.Visible = not guiHidden
        Shadow.Visible = not guiHidden
    end
end))

local ToastHolder = Instance.new("Frame")
ToastHolder.Name = "ToastHolder"
ToastHolder.Size = UDim2.new(1, -20, 0, 30)
ToastHolder.Position = UDim2.new(0, 10, 1, -52)
ToastHolder.BackgroundTransparency = 1
ToastHolder.ZIndex = 5
ToastHolder.Parent = Win

local function toast(txt)
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(1, 0.5)
    f.Position = UDim2.new(1, 0, 0.5, 0)
    f.Size = UDim2.new(0, 0, 0, 30)
    f.BackgroundColor3 = C.panelB
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.ZIndex = 6
    f.Parent = ToastHolder
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 7)
    local st = Instance.new("UIStroke", f); st.Color = C.green; st.Thickness = 1; st.Transparency = 1
    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1, -16, 1, 0)
    l.Position = UDim2.new(0, 10, 0, 0)
    l.BackgroundTransparency = 1
    l.TextColor3 = C.green
    l.TextTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.ZIndex = 7
    l.Text = "✓  " .. txt

    local w = math.clamp(#l.Text * 8 + 30, 90, 280)
    tween(f, TW_MED, {Size = UDim2.new(0, w, 0, 30), BackgroundTransparency = 0.05})
    tween(st, TW_MED, {Transparency = 0})
    tween(l, TW_MED, {TextTransparency = 0})

    task.delay(2, function()
        if f and f.Parent then
            tween(f, TW_MED, {BackgroundTransparency = 1})
            tween(st, TW_MED, {Transparency = 1})
            tween(l, TW_MED, {TextTransparency = 1})
            task.wait(0.25)
            if f then f:Destroy() end
        end
    end)
end

local StatsBar = Instance.new("Frame")
StatsBar.Size = UDim2.new(1, -20, 0, 28)
StatsBar.Position = UDim2.new(0, 10, 0, 54)
StatsBar.BackgroundColor3 = C.panelB
StatsBar.BorderSizePixel = 0
StatsBar.Parent = Win
Instance.new("UICorner", StatsBar).CornerRadius = UDim.new(0, 7)
local sbStroke = Instance.new("UIStroke", StatsBar); sbStroke.Color = C.border; sbStroke.Thickness = 1

local sbLayout = Instance.new("UIListLayout", StatsBar)
sbLayout.FillDirection = Enum.FillDirection.Horizontal
sbLayout.Padding = UDim.new(0, 8)
sbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
local sbPad = Instance.new("UIPadding", StatsBar)
sbPad.PaddingLeft = UDim.new(0, 10)

local function mkStat(color, order)
    local l = Instance.new("TextLabel")
    l.AutomaticSize = Enum.AutomaticSize.X
    l.Size = UDim2.new(0, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.TextColor3 = color
    l.Font = Enum.Font.Code
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = order
    l.Parent = StatsBar
    return l
end

local statTrash = mkStat(C.green, 1)
local statSells = mkStat(C.yellow, 2)
local statPets  = mkStat(C.purple, 3)

task.spawn(function()
    while running and GUI.Parent do
        local cnt = 0; for _ in pairs(petGUID) do cnt=cnt+1 end
        statTrash.Text = string.format("🗑 Trash: %d", stats.trash)
        statSells.Text = string.format("💰 Sells: %d", stats.sells)
        statPets.Text  = string.format("🐾 Pets: %d", cnt)
        task.wait(1)
    end
end)

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
        local on = (n==name)
        tween(b, TW_FAST, {BackgroundColor3 = on and C.tabOn or C.tabOff, TextColor3 = on and Color3.new(1,1,1) or C.sub})
    end
end

local function mkTab(name, label)
    local btn = Instance.new("TextButton")
    btn.Text = label
    btn.Size = UDim2.new(0.245, 0, 1, 0)
    btn.BackgroundColor3 = C.tabOff
    btn.TextColor3 = C.sub
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = TabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    tabBtns[name] = btn

    addConn(btn.MouseEnter:Connect(function()
        if not tabPages[name].Visible then
            tween(btn, TW_FAST, {BackgroundColor3 = C.border})
        end
    end))
    addConn(btn.MouseLeave:Connect(function()
        if not tabPages[name].Visible then
            tween(btn, TW_FAST, {BackgroundColor3 = C.tabOff})
        end
    end))

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
    addConn(btn.MouseButton1Click:Connect(function() selTab(name) end))
    return sf
end

local pFarm = mkTab("Farm", "🌿 Farm")
local pShop = mkTab("Shop", "🛒 Shop")
local pPets = mkTab("Pets", "🐾 Pets")
local pMisc = mkTab("Misc", "⚙️ Misc")

local function secLabel(parent, txt, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,26)
    f.BackgroundColor3 = C.section
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    local s = Instance.new("UIStroke",f); s.Color = C.border; s.Thickness = 1
    Instance.new("UICorner",f).CornerRadius = UDim.new(0,6)
    local bar = Instance.new("Frame", f)
    bar.Size = UDim2.new(0, 3, 0, 14)
    bar.Position = UDim2.new(0, 8, 0.5, -7)
    bar.BackgroundColor3 = C.accent
    bar.BorderSizePixel = 0
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)
    local l = Instance.new("TextLabel",f)
    l.Text = txt
    l.Size = UDim2.new(1,-22,1,0)
    l.Position = UDim2.new(0,18,0,0)
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
    t.BackgroundTransparency = 1
    t.TextColor3 = C.text
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.TextXAlignment = Enum.TextXAlignment.Left
    if sub then
        t.Position = UDim2.new(0,12,0,6)
        t.AnchorPoint = Vector2.new(0,0)
        local s = Instance.new("TextLabel",parent)
        s.Text = sub
        s.Size = UDim2.new(0.62,0,0,13)
        s.Position = UDim2.new(0,12,0,26)
        s.BackgroundTransparency = 1
        s.TextColor3 = C.sub
        s.Font = Enum.Font.Gotham
        s.TextSize = 10
        s.TextXAlignment = Enum.TextXAlignment.Left
    else
        t.Position = UDim2.new(0,12,0.5,0)
        t.AnchorPoint = Vector2.new(0,0.5)
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
        tween(bg, TW_FAST, {BackgroundColor3 = v and C.green or C.border})
        tween(kn, TW_FAST, {
            Position = v and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8),
            BackgroundColor3 = v and Color3.new(1,1,1) or Color3.fromRGB(180,180,200),
        })
        onToggle(v)
    end
    local ob = Instance.new("TextButton",r)
    ob.Size = UDim2.new(1,0,1,0)
    ob.BackgroundTransparency = 1
    ob.Text = ""
    addConn(ob.MouseButton1Click:Connect(function() set(not on) end))
    return set
end

local function mkButton(parent, title, sub, order, onClick, toastTxt)
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
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.ClipsDescendants = true
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,6)

    local shine = Instance.new("UIGradient", b)
    shine.Color = ColorSequence.new(Color3.new(1,1,1))
    shine.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.42, 1),
        NumberSequenceKeypoint.new(0.5, 0.65),
        NumberSequenceKeypoint.new(0.58, 1),
        NumberSequenceKeypoint.new(1, 1),
    })
    shine.Rotation = 22
    shine.Offset = Vector2.new(-1, 0)

    addConn(b.MouseEnter:Connect(function()
        tween(b, TW_FAST, {BackgroundColor3 = C.accentD})
        shine.Offset = Vector2.new(-1, 0)
        tween(shine, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Offset = Vector2.new(1, 0)})
    end))
    addConn(b.MouseLeave:Connect(function()
        tween(b, TW_FAST, {BackgroundColor3 = C.accent})
    end))

    addConn(b.MouseButton1Click:Connect(function()
        tween(b, TW_FAST, {BackgroundColor3 = C.accentD})
        pcall(onClick)
        if toastTxt then toast(toastTxt) end
        task.wait(0.2)
        tween(b, TW_FAST, {BackgroundColor3 = C.accent})
    end))
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
    local bs = Instance.new("UIStroke",box); bs.Color = C.border; bs.Thickness = 1
    addConn(box.Focused:Connect(function()
        tween(bs, TW_FAST, {Color = C.accent})
    end))
    addConn(box.FocusLost:Connect(function()
        tween(bs, TW_FAST, {Color = C.border})
        local v = tonumber(box.Text)
        if v and v >= 1 then
            cfg[key] = math.clamp(v, 1, 400)
            box.Text = tostring(cfg[key])
        else
            box.Text = tostring(cfg[key])
        end
    end))
end

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

secLabel(pShop, "ХАТЧИНГ", 1)
mkToggle(pShop, "Auto Hatch Eggs", "EggEvent HatchMax Common Egg", 2, function(v)
    if v then startHatch() else stopKey("hatch") end
end)
mkToggle(pShop, "Auto Hatch Crates", "CrateEvent HatchMax Common Crate", 3, function(v)
    if v then startCrate() else stopKey("crate") end
end)
mkRate(pShop, "Hatch Rate", "hatchRate", 5, 4)

secLabel(pShop, "БЫСТРЫЕ ДЕЙСТВИЯ", 5)
mkButton(pShop, "Claim All Achievements", "Все категории × 25 тиров", 6, claimAll, "Achievements claimed")
mkButton(pShop, "Buy All Backpacks", "BuyAll по всем зонам", 7, buyAllBP, "Backpacks bought")
mkButton(pShop, "Unlock All Zones", "ZoneDoorEvent Buy", 8, unlockZones, "Zones unlocked")
mkButton(pShop, "Claim Group Reward", "GroupEvent Claim", 9, claimGroup, "Group reward claimed")

secLabel(pPets, "ПИТОМЦЫ", 1)
mkToggle(pPets, "Auto Craft & Equip", "CraftSize из XPUpdate потока", 2, function(v)
    if v then startCraft() else active.craft = false end
end)
mkButton(pPets, "Equip Best (сейчас)", "PetEvent + HatEvent EquipBest", 3, equipBest, "Equipped best")

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
    while running and GUI.Parent do
        local cnt = 0; for _ in pairs(petGUID) do cnt=cnt+1 end
        petInfoLbl.Text = string.format(
            "Pet GUIDs (свои + чужие из XPUpdate): %d\nCraftSize пробует каждый — чужие сервер отклонит",
            cnt
        )
        task.wait(1)
    end
end)

secLabel(pMisc, "ДВИЖЕНИЕ", 1)
mkButton(pMisc, "Speed ×2.5", "WalkSpeed 40 / JumpPower 75", 2, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed=40; h.JumpPower=75 end
    end
end, "Speed ×2.5")
mkButton(pMisc, "Speed ×5", "WalkSpeed 80 / JumpPower 100", 3, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed=80; h.JumpPower=100 end
    end
end, "Speed ×5")
mkButton(pMisc, "Reset Speed", "WalkSpeed 16 / JumpPower 50", 4, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed=16; h.JumpPower=50 end
    end
end, "Speed reset")

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

local hintLbl = Instance.new("TextLabel")
hintLbl.Size = UDim2.new(1, -20, 0, 14)
hintLbl.Position = UDim2.new(0, 10, 1, -18)
hintLbl.BackgroundTransparency = 1
hintLbl.TextColor3 = C.sub
hintLbl.Font = Enum.Font.Gotham
hintLbl.TextSize = 10
hintLbl.TextXAlignment = Enum.TextXAlignment.Center
hintLbl.Text = "[INSERT] to toggle  ·  drag the title bar to move"
hintLbl.Parent = Win

selTab("Farm")
