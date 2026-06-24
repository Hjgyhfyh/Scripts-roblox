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
local zoneFilter = {}

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
            local zone = d[2] and d[2].Zone
            if next(zoneFilter) == nil or zoneFilter[zone] then
                trashBuf[#trashBuf+1] = d[1]
            end
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

----------------------------------------------------------------------
-- INTERFACE
----------------------------------------------------------------------

local C = {
    bg        = Color3.fromRGB(10, 10, 16),
    panel     = Color3.fromRGB(18, 18, 28),
    panelB    = Color3.fromRGB(24, 24, 38),
    panelHov  = Color3.fromRGB(28, 28, 44),
    section   = Color3.fromRGB(14, 14, 24),
    accent    = Color3.fromRGB(140, 100, 255),
    accentD   = Color3.fromRGB(95, 65, 215),
    accentDim = Color3.fromRGB(58, 44, 110),
    cyan      = Color3.fromRGB(80, 200, 220),
    cyanD     = Color3.fromRGB(26, 58, 66),
    green     = Color3.fromRGB(80, 220, 130),
    greenBg   = Color3.fromRGB(18, 44, 30),
    yellow    = Color3.fromRGB(240, 205, 95),
    yellowBg  = Color3.fromRGB(46, 40, 18),
    purple    = Color3.fromRGB(180, 140, 255),
    purpleBg  = Color3.fromRGB(34, 26, 56),
    red       = Color3.fromRGB(225, 75, 80),
    redD      = Color3.fromRGB(170, 50, 55),
    text      = Color3.fromRGB(235, 235, 248),
    sub       = Color3.fromRGB(128, 128, 162),
    border    = Color3.fromRGB(40, 40, 64),
    borderHov = Color3.fromRGB(78, 70, 130),
    knob      = Color3.fromRGB(186, 186, 206),
}

local ZONE_DATA = {
    ["Spawn"]         = Color3.fromRGB(80, 220, 130),
    ["The Forest"]    = Color3.fromRGB(60, 200, 180),
    ["Autumn Fall"]   = Color3.fromRGB(240, 150, 70),
    ["Blossom Realm"] = Color3.fromRGB(245, 120, 190),
}
local ZONE_ORDER = {"Spawn", "The Forest", "Autumn Fall", "Blossom Realm"}

local TW_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_MED  = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_SLOW = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tween(obj, info, props)
    local t = TweenService:Create(obj, info, props)
    t:Play()
    return t
end

local function corner(obj, r)
    local c = Instance.new("UICorner", obj)
    c.CornerRadius = UDim.new(0, r)
    return c
end

local function stroke(obj, color, thick, trans)
    local s = Instance.new("UIStroke", obj)
    s.Color = color
    s.Thickness = thick or 1
    s.Transparency = trans or 0
    return s
end

local function spaced(txt)
    local out = {}
    for _, ch in utf8.codes(txt) do
        out[#out+1] = utf8.char(ch)
    end
    return table.concat(out, " ")
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

----------------------------------------------------------------------
-- LAYERED SOFT DROP SHADOW
----------------------------------------------------------------------

local shadowFrames = {}
local function mkShadow(spread, trans, radius)
    local s = Instance.new("Frame")
    s.Size = UDim2.new(0, 440 + spread * 2, 0, 545 + spread * 2)
    s.Position = UDim2.new(0.5, -(220 + spread), 0.5, -(272 + spread))
    s.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    s.BackgroundTransparency = trans
    s.BorderSizePixel = 0
    s.ZIndex = 0
    s.Parent = GUI
    corner(s, radius)
    shadowFrames[#shadowFrames+1] = { obj = s, spread = spread }
    return s
end

local Shadow3 = mkShadow(18, 0.86, 26)
local Shadow2 = mkShadow(11, 0.74, 20)
local Shadow1 = mkShadow(5,  0.62, 15)

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------

local Win = Instance.new("Frame")
Win.Name = "Win"
Win.Size = UDim2.new(0, 440, 0, 545)
Win.Position = UDim2.new(0.5, -220, 0.5, -272)
Win.BackgroundColor3 = C.bg
Win.BorderSizePixel = 0
Win.ZIndex = 1
Win.Parent = GUI
corner(Win, 14)

local winGlow = stroke(Win, C.accent, 1.6, 0.45)
task.spawn(function()
    while running and Win.Parent do
        tween(winGlow, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.7})
        task.wait(1.5)
        if not (running and Win.Parent) then break end
        tween(winGlow, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.3})
        task.wait(1.5)
    end
end)

----------------------------------------------------------------------
-- TITLE BAR
----------------------------------------------------------------------

local TBar = Instance.new("Frame")
TBar.Name = "TBar"
TBar.Size = UDim2.new(1, 0, 0, 50)
TBar.BackgroundColor3 = C.panel
TBar.BorderSizePixel = 0
TBar.ZIndex = 2
TBar.Parent = Win
corner(TBar, 14)

local tBarGrad = Instance.new("UIGradient", TBar)
tBarGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, C.accentD),
    ColorSequenceKeypoint.new(0.5, C.panel),
    ColorSequenceKeypoint.new(1, C.bg),
})
tBarGrad.Rotation = 12

local tFix = Instance.new("Frame")
tFix.Size = UDim2.new(1, 0, 0, 14)
tFix.Position = UDim2.new(0, 0, 1, -14)
tFix.BackgroundColor3 = C.bg
tFix.BackgroundTransparency = 1
tFix.BorderSizePixel = 0
tFix.ZIndex = 2
tFix.Parent = TBar

local tBarLine = Instance.new("Frame")
tBarLine.Size = UDim2.new(1, 0, 0, 1)
tBarLine.Position = UDim2.new(0, 0, 1, -1)
tBarLine.BackgroundColor3 = C.border
tBarLine.BorderSizePixel = 0
tBarLine.ZIndex = 3
tBarLine.Parent = TBar

local logo = Instance.new("Frame")
logo.Size = UDim2.new(0, 4, 0, 26)
logo.Position = UDim2.new(0, 14, 0.5, -13)
logo.BackgroundColor3 = C.accent
logo.BorderSizePixel = 0
logo.ZIndex = 3
logo.Parent = TBar
corner(logo, 2)
local logoGrad = Instance.new("UIGradient", logo)
logoGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, C.accent),
    ColorSequenceKeypoint.new(1, C.cyan),
})
logoGrad.Rotation = 90

local TTitle = Instance.new("TextLabel")
TTitle.Text = "Magnet Trash Simulator"
TTitle.Size = UDim2.new(1, -150, 0, 20)
TTitle.Position = UDim2.new(0, 26, 0, 7)
TTitle.BackgroundTransparency = 1
TTitle.TextColor3 = C.text
TTitle.Font = Enum.Font.GothamBold
TTitle.TextSize = 15
TTitle.TextXAlignment = Enum.TextXAlignment.Left
TTitle.ZIndex = 3
TTitle.Parent = TBar

local shimmer = Instance.new("UIGradient", TTitle)
shimmer.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, C.text),
    ColorSequenceKeypoint.new(0.42, C.text),
    ColorSequenceKeypoint.new(0.5, C.accent),
    ColorSequenceKeypoint.new(0.58, C.text),
    ColorSequenceKeypoint.new(1, C.text),
})
shimmer.Offset = Vector2.new(-1.2, 0)
task.spawn(function()
    while running and TTitle.Parent do
        shimmer.Offset = Vector2.new(-1.2, 0)
        tween(shimmer, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Offset = Vector2.new(1.2, 0)})
        task.wait(4.2)
    end
end)

local TSub = Instance.new("TextLabel")
TSub.Text = "Remote Suite  ·  Magnet Trash"
TSub.Size = UDim2.new(1, -150, 0, 12)
TSub.Position = UDim2.new(0, 26, 0, 29)
TSub.BackgroundTransparency = 1
TSub.TextColor3 = C.sub
TSub.Font = Enum.Font.Gotham
TSub.TextSize = 10
TSub.TextXAlignment = Enum.TextXAlignment.Left
TSub.ZIndex = 3
TSub.Parent = TBar

local function mkTBtn(txt, bg, bgHover, xOff)
    local b = Instance.new("TextButton")
    b.Text = txt
    b.Size = UDim2.new(0, 28, 0, 28)
    b.Position = UDim2.new(1, xOff, 0, 11)
    b.BackgroundColor3 = bg
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.ZIndex = 3
    b.Parent = TBar
    corner(b, 7)
    addConn(b.MouseEnter:Connect(function()
        tween(b, TW_FAST, {BackgroundColor3 = bgHover})
    end))
    addConn(b.MouseLeave:Connect(function()
        tween(b, TW_FAST, {BackgroundColor3 = bg})
    end))
    return b
end

local CloseB = mkTBtn("✕", C.red, C.redD, -38)
local MinB   = mkTBtn("—", C.panelB, C.accentD, -70)

----------------------------------------------------------------------
-- DRAG
----------------------------------------------------------------------

local dragging, dStart, dPos
local function syncShadows(px, py)
    for _, s in ipairs(shadowFrames) do
        s.obj.Position = UDim2.new(px.Scale, px.Offset - s.spread, py.Scale, py.Offset - s.spread)
    end
end

addConn(TBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dStart = i.Position; dPos = Win.Position
    end
end))
addConn(UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dStart
        local px = UDim.new(dPos.X.Scale, dPos.X.Offset + d.X)
        local py = UDim.new(dPos.Y.Scale, dPos.Y.Offset + d.Y)
        Win.Position = UDim2.new(px.Scale, px.Offset, py.Scale, py.Offset)
        syncShadows(px, py)
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
    local h = minimized and 50 or 545
    tween(Win, TW_MED, {Size = UDim2.new(0, 440, 0, h)})
    for _, s in ipairs(shadowFrames) do
        tween(s.obj, TW_MED, {Size = UDim2.new(0, 440 + s.spread * 2, 0, h + s.spread * 2)})
    end
end))

local guiHidden = false
addConn(UIS.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.Insert then
        guiHidden = not guiHidden
        Win.Visible = not guiHidden
        for _, s in ipairs(shadowFrames) do s.obj.Visible = not guiHidden end
    end
end))

----------------------------------------------------------------------
-- TOASTS
----------------------------------------------------------------------

local ToastHolder = Instance.new("Frame")
ToastHolder.Name = "ToastHolder"
ToastHolder.AnchorPoint = Vector2.new(1, 1)
ToastHolder.Size = UDim2.new(0, 300, 0, 200)
ToastHolder.Position = UDim2.new(1, -12, 1, -46)
ToastHolder.BackgroundTransparency = 1
ToastHolder.ZIndex = 20
ToastHolder.Parent = Win

local thLayout = Instance.new("UIListLayout", ToastHolder)
thLayout.FillDirection = Enum.FillDirection.Vertical
thLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
thLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
thLayout.Padding = UDim.new(0, 6)
thLayout.SortOrder = Enum.SortOrder.LayoutOrder

local toastSeq = 0
local function toast(txt)
    toastSeq = toastSeq + 1
    local w = math.clamp(#txt * 7 + 56, 130, 290)

    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(0, w, 0, 32)
    holder.BackgroundTransparency = 1
    holder.LayoutOrder = toastSeq
    holder.ZIndex = 21
    holder.Parent = ToastHolder

    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(1, 0.5)
    f.Position = UDim2.new(1.3, 0, 0.5, 0)
    f.Size = UDim2.new(1, 0, 1, 0)
    f.BackgroundColor3 = C.panelB
    f.BackgroundTransparency = 0.04
    f.BorderSizePixel = 0
    f.ZIndex = 22
    f.Parent = holder
    corner(f, 9)
    local st = stroke(f, C.green, 1, 0.4)

    local dot = Instance.new("Frame", f)
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.Position = UDim2.new(0, 12, 0.5, -4)
    dot.BackgroundColor3 = C.green
    dot.BorderSizePixel = 0
    dot.ZIndex = 23
    corner(dot, 4)
    local dotGlow = stroke(dot, C.green, 2, 0.5)

    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(1, -34, 1, 0)
    l.Position = UDim2.new(0, 28, 0, 0)
    l.BackgroundTransparency = 1
    l.TextColor3 = C.text
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.ZIndex = 23
    l.Text = txt

    tween(f, TW_SLOW, {Position = UDim2.new(1, 0, 0.5, 0)})

    task.delay(2.2, function()
        if not (f and f.Parent) then return end
        tween(f, TW_MED, {Position = UDim2.new(1.4, 0, 0.5, 0), BackgroundTransparency = 1})
        tween(st, TW_MED, {Transparency = 1})
        tween(l, TW_MED, {TextTransparency = 1})
        tween(dot, TW_MED, {BackgroundTransparency = 1})
        tween(dotGlow, TW_MED, {Transparency = 1})
        task.wait(0.3)
        if holder then holder:Destroy() end
    end)
end

----------------------------------------------------------------------
-- STATS BAR
----------------------------------------------------------------------

local StatsBar = Instance.new("Frame")
StatsBar.Size = UDim2.new(1, -20, 0, 34)
StatsBar.Position = UDim2.new(0, 10, 0, 58)
StatsBar.BackgroundColor3 = C.panel
StatsBar.BorderSizePixel = 0
StatsBar.Parent = Win
corner(StatsBar, 9)
stroke(StatsBar, C.border, 1)

local sbLayout = Instance.new("UIListLayout", StatsBar)
sbLayout.FillDirection = Enum.FillDirection.Horizontal
sbLayout.Padding = UDim.new(0, 6)
sbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
sbLayout.SortOrder = Enum.SortOrder.LayoutOrder
local sbPad = Instance.new("UIPadding", StatsBar)
sbPad.PaddingLeft = UDim.new(0, 7)
sbPad.PaddingRight = UDim.new(0, 7)

local function mkBadge(bg, fg, order)
    local b = Instance.new("Frame")
    b.AutomaticSize = Enum.AutomaticSize.X
    b.Size = UDim2.new(0, 0, 0, 22)
    b.BackgroundColor3 = bg
    b.BorderSizePixel = 0
    b.LayoutOrder = order
    b.Parent = StatsBar
    corner(b, 6)
    local bp = Instance.new("UIPadding", b)
    bp.PaddingLeft = UDim.new(0, 9)
    bp.PaddingRight = UDim.new(0, 9)
    local l = Instance.new("TextLabel", b)
    l.AutomaticSize = Enum.AutomaticSize.X
    l.Size = UDim2.new(0, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.TextColor3 = fg
    l.Font = Enum.Font.GothamBold
    l.TextSize = 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = b
    return l
end

local statTrash = mkBadge(C.greenBg,  C.green,  1)
local statSells = mkBadge(C.yellowBg, C.yellow, 2)
local statPets  = mkBadge(C.purpleBg, C.purple, 3)
local statZone  = mkBadge(C.cyanD,    C.cyan,   4)

task.spawn(function()
    while running and GUI.Parent do
        local cnt = 0; for _ in pairs(petGUID) do cnt = cnt + 1 end
        statTrash.Text = string.format("🗑 %d", stats.trash)
        statSells.Text = string.format("💰 %d", stats.sells)
        statPets.Text  = string.format("🐾 %d", cnt)

        local zc = 0; local first
        for z in pairs(zoneFilter) do zc = zc + 1; first = first or z end
        if zc == 0 then
            statZone.Text = "🌍 All Zones"
        elseif zc == 1 then
            statZone.Text = "🌍 " .. first
        else
            statZone.Text = string.format("🌍 %d zones", zc)
        end
        task.wait(1)
    end
end)

----------------------------------------------------------------------
-- TABS
----------------------------------------------------------------------

local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -20, 0, 36)
TabBar.Position = UDim2.new(0, 10, 0, 98)
TabBar.BackgroundColor3 = C.panel
TabBar.BorderSizePixel = 0
TabBar.Parent = Win
corner(TabBar, 9)
stroke(TabBar, C.border, 1)
local tbl = Instance.new("UIListLayout", TabBar)
tbl.FillDirection = Enum.FillDirection.Horizontal
tbl.Padding = UDim.new(0, 3)
tbl.VerticalAlignment = Enum.VerticalAlignment.Center
tbl.SortOrder = Enum.SortOrder.LayoutOrder
local tbp = Instance.new("UIPadding", TabBar)
tbp.PaddingLeft = UDim.new(0, 4); tbp.PaddingRight = UDim.new(0, 4)
tbp.PaddingTop = UDim.new(0, 4); tbp.PaddingBottom = UDim.new(0, 4)

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -20, 1, -176)
Content.Position = UDim2.new(0, 10, 0, 142)
Content.BackgroundTransparency = 1
Content.Parent = Win

local tabBtns, tabPages = {}, {}
local activeTab = nil

local function selTab(name)
    activeTab = name
    for n, p in pairs(tabPages) do p.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        local on = (n == name)
        tween(b.btn, TW_FAST, {BackgroundColor3 = on and C.panelB or C.panel})
        tween(b.lbl, TW_FAST, {TextColor3 = on and C.accent or C.sub})
        tween(b.ind, TW_FAST, {
            BackgroundTransparency = on and 0 or 1,
            Size = on and UDim2.new(0, 26, 0, 2) or UDim2.new(0, 8, 0, 2),
        })
        tween(b.icoBg, TW_FAST, {BackgroundTransparency = on and 0.78 or 1})
    end
end

local function mkTab(name, icon, label, order)
    local btn = Instance.new("TextButton")
    btn.Text = ""
    btn.Size = UDim2.new(0.25, -3, 1, 0)
    btn.BackgroundColor3 = C.panel
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.LayoutOrder = order
    btn.Parent = TabBar
    corner(btn, 7)

    local icoBg = Instance.new("Frame", btn)
    icoBg.Size = UDim2.new(0, 18, 0, 18)
    icoBg.Position = UDim2.new(0, 8, 0.5, -9)
    icoBg.BackgroundColor3 = C.accent
    icoBg.BackgroundTransparency = 1
    icoBg.BorderSizePixel = 0
    corner(icoBg, 5)

    local ico = Instance.new("TextLabel", btn)
    ico.Size = UDim2.new(0, 18, 1, 0)
    ico.Position = UDim2.new(0, 8, 0, 0)
    ico.BackgroundTransparency = 1
    ico.Text = icon
    ico.TextColor3 = C.text
    ico.Font = Enum.Font.GothamBold
    ico.TextSize = 13

    local lbl = Instance.new("TextLabel", btn)
    lbl.Size = UDim2.new(1, -30, 1, 0)
    lbl.Position = UDim2.new(0, 28, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = C.sub
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local ind = Instance.new("Frame", btn)
    ind.AnchorPoint = Vector2.new(0.5, 1)
    ind.Position = UDim2.new(0.5, 0, 1, -2)
    ind.Size = UDim2.new(0, 8, 0, 2)
    ind.BackgroundColor3 = C.accent
    ind.BackgroundTransparency = 1
    ind.BorderSizePixel = 0
    corner(ind, 1)

    tabBtns[name] = { btn = btn, lbl = lbl, ind = ind, icoBg = icoBg }

    addConn(btn.MouseEnter:Connect(function()
        if activeTab ~= name then tween(btn, TW_FAST, {BackgroundColor3 = C.panelHov}) end
    end))
    addConn(btn.MouseLeave:Connect(function()
        if activeTab ~= name then tween(btn, TW_FAST, {BackgroundColor3 = C.panel}) end
    end))

    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1, 0, 1, 0)
    sf.BackgroundTransparency = 1
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 3
    sf.ScrollBarImageColor3 = C.accent
    sf.CanvasSize = UDim2.new(0, 0, 0, 0)
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.Visible = false
    sf.Parent = Content
    tabPages[name] = sf
    Instance.new("UIListLayout", sf).Padding = UDim.new(0, 6)
    local p = Instance.new("UIPadding", sf); p.PaddingBottom = UDim.new(0, 6); p.PaddingRight = UDim.new(0, 2)
    addConn(btn.MouseButton1Click:Connect(function() selTab(name) end))
    return sf
end

local pFarm = mkTab("Farm", "🌿", "Farm", 1)
local pShop = mkTab("Shop", "🛒", "Shop", 2)
local pPets = mkTab("Pets", "🐾", "Pets", 3)
local pMisc = mkTab("Misc", "⚙️", "Misc", 4)

----------------------------------------------------------------------
-- SECTION LABEL
----------------------------------------------------------------------

local function secLabel(parent, txt, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 28)
    f.BackgroundColor3 = C.section
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    corner(f, 7)
    stroke(f, C.border, 1)

    local bar = Instance.new("Frame", f)
    bar.Size = UDim2.new(0, 4, 0, 16)
    bar.Position = UDim2.new(0, 9, 0.5, -8)
    bar.BackgroundColor3 = C.accent
    bar.BorderSizePixel = 0
    corner(bar, 2)
    local bg = Instance.new("UIGradient", bar)
    bg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.accent),
        ColorSequenceKeypoint.new(1, C.cyan),
    })
    bg.Rotation = 90

    local l = Instance.new("TextLabel", f)
    l.Text = spaced(txt)
    l.Size = UDim2.new(1, -24, 1, 0)
    l.Position = UDim2.new(0, 19, 0, 0)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(200, 180, 255)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = f
end

----------------------------------------------------------------------
-- ROW
----------------------------------------------------------------------

local function mkRow(parent, h, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, h)
    f.BackgroundColor3 = C.panel
    f.BorderSizePixel = 0
    f.LayoutOrder = order
    f.Parent = parent
    corner(f, 9)
    local s = stroke(f, C.border, 1)
    return f, s
end

local function hoverRow(f, s)
    addConn(f.MouseEnter:Connect(function()
        tween(f, TW_FAST, {BackgroundColor3 = C.panelHov})
        tween(s, TW_FAST, {Color = C.borderHov})
    end))
    addConn(f.MouseLeave:Connect(function()
        tween(f, TW_FAST, {BackgroundColor3 = C.panel})
        tween(s, TW_FAST, {Color = C.border})
    end))
end

local function rowLabel(parent, title, sub)
    local t = Instance.new("TextLabel", parent)
    t.Text = title
    t.Size = UDim2.new(0.58, 0, 0, 18)
    t.BackgroundTransparency = 1
    t.TextColor3 = C.text
    t.Font = Enum.Font.GothamBold
    t.TextSize = 13
    t.TextXAlignment = Enum.TextXAlignment.Left
    if sub then
        t.Position = UDim2.new(0, 13, 0, 7)
        t.AnchorPoint = Vector2.new(0, 0)
        local s = Instance.new("TextLabel", parent)
        s.Text = sub
        s.Size = UDim2.new(0.58, 0, 0, 13)
        s.Position = UDim2.new(0, 13, 0, 27)
        s.BackgroundTransparency = 1
        s.TextColor3 = C.sub
        s.Font = Enum.Font.Gotham
        s.TextSize = 10
        s.TextXAlignment = Enum.TextXAlignment.Left
        s.Parent = parent
    else
        t.Position = UDim2.new(0, 13, 0.5, 0)
        t.AnchorPoint = Vector2.new(0, 0.5)
    end
end

----------------------------------------------------------------------
-- TOGGLE
----------------------------------------------------------------------

local function mkToggle(parent, title, sub, order, onToggle)
    local h = sub and 54 or 42
    local r, rs = mkRow(parent, h, order)
    hoverRow(r, rs)
    rowLabel(r, title, sub)

    local track = Instance.new("Frame", r)
    track.Size = UDim2.new(0, 48, 0, 24)
    track.Position = UDim2.new(1, -62, 0.5, -12)
    track.BackgroundColor3 = C.border
    track.BorderSizePixel = 0
    corner(track, 12)

    local glow = Instance.new("Frame", track)
    glow.Size = UDim2.new(0, 24, 0, 24)
    glow.Position = UDim2.new(0, 23, 0.5, -12)
    glow.BackgroundColor3 = C.green
    glow.BackgroundTransparency = 1
    glow.BorderSizePixel = 0
    glow.ZIndex = 2
    corner(glow, 12)

    local knShadow = Instance.new("Frame", track)
    knShadow.Size = UDim2.new(0, 18, 0, 18)
    knShadow.Position = UDim2.new(0, 4, 0.5, -8)
    knShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    knShadow.BackgroundTransparency = 0.6
    knShadow.BorderSizePixel = 0
    knShadow.ZIndex = 3
    corner(knShadow, 9)

    local kn = Instance.new("Frame", track)
    kn.Size = UDim2.new(0, 18, 0, 18)
    kn.Position = UDim2.new(0, 3, 0.5, -9)
    kn.BackgroundColor3 = C.knob
    kn.BorderSizePixel = 0
    kn.ZIndex = 4
    corner(kn, 9)

    local on = false
    local function set(v)
        on = v
        tween(track, TW_FAST, {BackgroundColor3 = v and C.green or C.border})
        tween(kn, TW_FAST, {
            Position = v and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
            BackgroundColor3 = v and Color3.new(1, 1, 1) or C.knob,
        })
        tween(knShadow, TW_FAST, {
            Position = v and UDim2.new(1, -22, 0.5, -8) or UDim2.new(0, 4, 0.5, -8),
        })
        tween(glow, TW_FAST, {
            Position = v and UDim2.new(1, -27, 0.5, -12) or UDim2.new(0, 23, 0.5, -12),
            BackgroundTransparency = v and 0.55 or 1,
        })
        onToggle(v)
    end
    local ob = Instance.new("TextButton", r)
    ob.Size = UDim2.new(1, 0, 1, 0)
    ob.BackgroundTransparency = 1
    ob.Text = ""
    ob.ZIndex = 5
    addConn(ob.MouseButton1Click:Connect(function() set(not on) end))
    return set
end

----------------------------------------------------------------------
-- ACTION BUTTON
----------------------------------------------------------------------

local function mkButton(parent, title, sub, order, onClick, toastTxt)
    local h = sub and 54 or 42
    local r, rs = mkRow(parent, h, order)
    hoverRow(r, rs)
    rowLabel(r, title, sub)

    local b = Instance.new("TextButton", r)
    b.Text = "▶ Run"
    b.Size = UDim2.new(0, 68, 0, 28)
    b.Position = UDim2.new(1, -80, 0.5, -14)
    b.BackgroundColor3 = C.accent
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.ClipsDescendants = true
    b.ZIndex = 3
    corner(b, 7)

    local bGrad = Instance.new("UIGradient", b)
    bGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.accent),
        ColorSequenceKeypoint.new(1, C.accentD),
    })
    bGrad.Rotation = 90

    local shine = Instance.new("UIGradient", b)
    shine.Color = ColorSequence.new(Color3.new(1, 1, 1))
    shine.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.42, 1),
        NumberSequenceKeypoint.new(0.5, 0.7),
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
        tween(b, TW_FAST, {BackgroundColor3 = C.accentD, Size = UDim2.new(0, 74, 0, 30), Position = UDim2.new(1, -83, 0.5, -15)})
        pcall(onClick)
        if toastTxt then toast(toastTxt) end
        task.wait(0.12)
        tween(b, TW_FAST, {Size = UDim2.new(0, 68, 0, 28), Position = UDim2.new(1, -80, 0.5, -14)})
        task.wait(0.1)
        tween(b, TW_FAST, {BackgroundColor3 = C.accent})
    end))
end

----------------------------------------------------------------------
-- RATE INPUT
----------------------------------------------------------------------

local function mkRate(parent, title, key, default, order)
    local r, rs = mkRow(parent, 52, order)
    hoverRow(r, rs)
    rowLabel(r, title, "throughput")

    local unit = Instance.new("TextLabel", r)
    unit.Size = UDim2.new(0, 32, 0, 26)
    unit.Position = UDim2.new(1, -44, 0.5, -13)
    unit.BackgroundTransparency = 1
    unit.Text = "/ sec"
    unit.TextColor3 = C.sub
    unit.Font = Enum.Font.GothamMedium
    unit.TextSize = 11
    unit.TextXAlignment = Enum.TextXAlignment.Left
    unit.ZIndex = 3

    local box = Instance.new("TextBox", r)
    box.Text = tostring(default)
    box.Size = UDim2.new(0, 56, 0, 28)
    box.Position = UDim2.new(1, -104, 0.5, -14)
    box.BackgroundColor3 = C.bg
    box.TextColor3 = C.text
    box.Font = Enum.Font.GothamBold
    box.TextSize = 13
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = true
    box.ZIndex = 3
    corner(box, 7)
    local bs = stroke(box, C.border, 1)

    addConn(box.Focused:Connect(function()
        tween(bs, TW_FAST, {Color = C.accent, Thickness = 1.6})
    end))
    addConn(box.FocusLost:Connect(function()
        tween(bs, TW_FAST, {Color = C.border, Thickness = 1})
        local v = tonumber(box.Text)
        if v and v >= 1 then
            cfg[key] = math.clamp(v, 1, 400)
            box.Text = tostring(cfg[key])
        else
            box.Text = tostring(cfg[key])
        end
    end))
end

----------------------------------------------------------------------
-- FARM TAB
----------------------------------------------------------------------

secLabel(pFarm, "СБОР МУСОРА", 1)
mkToggle(pFarm, "Auto Farm Trash", "Render → мгновенный Destroy", 2, function(v)
    if v then startFarm() else active.farm = false end
end)
mkRate(pFarm, "Farm Rate", "farmRate", 50, 3)

do
    secLabel(pFarm, "ФИЛЬТР ЗОН", 3.2)
    local zoneRow, zoneRowS = mkRow(pFarm, 102, 3.4)
    hoverRow(zoneRow, zoneRowS)

    local zBtns = {}

    local grid = Instance.new("Frame", zoneRow)
    grid.Size = UDim2.new(1, -20, 1, -28)
    grid.Position = UDim2.new(0, 10, 0, 9)
    grid.BackgroundTransparency = 1
    local gl = Instance.new("UIGridLayout", grid)
    gl.CellSize = UDim2.new(0.5, -4, 0, 30)
    gl.CellPadding = UDim2.new(0, 6, 0, 6)
    gl.SortOrder = Enum.SortOrder.LayoutOrder

    local hintZ = Instance.new("TextLabel", zoneRow)
    hintZ.Size = UDim2.new(1, -20, 0, 12)
    hintZ.Position = UDim2.new(0, 10, 1, -16)
    hintZ.BackgroundTransparency = 1
    hintZ.TextColor3 = C.sub
    hintZ.Font = Enum.Font.GothamMedium
    hintZ.TextSize = 9
    hintZ.TextXAlignment = Enum.TextXAlignment.Center
    hintZ.RichText = true
    hintZ.Text = "Ничего не выбрано = все зоны"

    local function rgbStr(c)
        return string.format('rgb(%d,%d,%d)', math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5))
    end

    local function refreshZoneHint()
        local parts = {}
        for _, z in ipairs(ZONE_ORDER) do
            if zoneFilter[z] then
                parts[#parts+1] = string.format('<font color="#%s">%s</font>',
                    string.format('%02X%02X%02X', math.floor(ZONE_DATA[z].R*255+0.5), math.floor(ZONE_DATA[z].G*255+0.5), math.floor(ZONE_DATA[z].B*255+0.5)),
                    z)
            end
        end
        if #parts == 0 then
            hintZ.Text = "Ничего не выбрано = все зоны"
        else
            hintZ.Text = "Только:  " .. table.concat(parts, "  ·  ")
        end
    end

    for i, zoneName in ipairs(ZONE_ORDER) do
        local zCol = ZONE_DATA[zoneName]

        local btn = Instance.new("TextButton", grid)
        btn.LayoutOrder = i
        btn.Text = ""
        btn.BackgroundColor3 = C.panelB
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        corner(btn, 7)
        local bs = stroke(btn, C.border, 1)

        local ind = Instance.new("Frame", btn)
        ind.Size = UDim2.new(0, 4, 0, 16)
        ind.Position = UDim2.new(0, 7, 0.5, -8)
        ind.BackgroundColor3 = zCol
        ind.BorderSizePixel = 0
        corner(ind, 2)

        local lbl = Instance.new("TextLabel", btn)
        lbl.Size = UDim2.new(1, -22, 1, 0)
        lbl.Position = UDim2.new(0, 17, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = zoneName
        lbl.TextColor3 = C.sub
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd

        zBtns[zoneName] = btn

        addConn(btn.MouseEnter:Connect(function()
            if not zoneFilter[zoneName] then tween(btn, TW_FAST, {BackgroundColor3 = C.panelHov}) end
        end))
        addConn(btn.MouseLeave:Connect(function()
            if not zoneFilter[zoneName] then tween(btn, TW_FAST, {BackgroundColor3 = C.panelB}) end
        end))

        addConn(btn.MouseButton1Click:Connect(function()
            if zoneFilter[zoneName] then
                zoneFilter[zoneName] = nil
                tween(btn, TW_FAST, {BackgroundColor3 = C.panelB})
                tween(lbl, TW_FAST, {TextColor3 = C.sub})
                tween(bs, TW_FAST, {Color = C.border, Thickness = 1})
            else
                zoneFilter[zoneName] = true
                tween(btn, TW_FAST, {BackgroundColor3 = zCol:Lerp(C.bg, 0.78)})
                tween(lbl, TW_FAST, {TextColor3 = zCol})
                tween(bs, TW_FAST, {Color = zCol, Thickness = 1.4})
            end
            refreshZoneHint()
        end))
    end
end

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

----------------------------------------------------------------------
-- SHOP TAB
----------------------------------------------------------------------

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

----------------------------------------------------------------------
-- PETS TAB
----------------------------------------------------------------------

secLabel(pPets, "ПИТОМЦЫ", 1)
mkToggle(pPets, "Auto Craft & Equip", "CraftSize из XPUpdate потока", 2, function(v)
    if v then startCraft() else active.craft = false end
end)
mkButton(pPets, "Equip Best (сейчас)", "PetEvent + HatEvent EquipBest", 3, equipBest, "Equipped best")

secLabel(pPets, "СТАТУС", 4)
local petInfoRow = mkRow(pPets, 72, 5)
local petInfoLbl = Instance.new("TextLabel", petInfoRow)
petInfoLbl.Size = UDim2.new(1, -24, 1, -18)
petInfoLbl.Position = UDim2.new(0, 12, 0, 9)
petInfoLbl.BackgroundTransparency = 1
petInfoLbl.TextColor3 = C.sub
petInfoLbl.Font = Enum.Font.Code
petInfoLbl.TextSize = 11
petInfoLbl.TextXAlignment = Enum.TextXAlignment.Left
petInfoLbl.TextYAlignment = Enum.TextYAlignment.Top
petInfoLbl.TextWrapped = true
task.spawn(function()
    while running and GUI.Parent do
        local cnt = 0; for _ in pairs(petGUID) do cnt = cnt + 1 end
        petInfoLbl.Text = string.format(
            "Pet GUIDs (свои + чужие из XPUpdate): %d\nCraftSize пробует каждый — чужие сервер отклонит",
            cnt
        )
        task.wait(1)
    end
end)

----------------------------------------------------------------------
-- MISC TAB
----------------------------------------------------------------------

secLabel(pMisc, "ДВИЖЕНИЕ", 1)
mkButton(pMisc, "Speed ×2.5", "WalkSpeed 40 / JumpPower 75", 2, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = 40; h.JumpPower = 75 end
    end
end, "Speed ×2.5")
mkButton(pMisc, "Speed ×5", "WalkSpeed 80 / JumpPower 100", 3, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = 80; h.JumpPower = 100 end
    end
end, "Speed ×5")
mkButton(pMisc, "Reset Speed", "WalkSpeed 16 / JumpPower 50", 4, function()
    local c = lp.Character; if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then h.WalkSpeed = 16; h.JumpPower = 50 end
    end
end, "Speed reset")

secLabel(pMisc, "REMOTE СТАТУС", 5)
local remRow = mkRow(pMisc, 160, 6)
local remLbl = Instance.new("TextLabel", remRow)
remLbl.Size = UDim2.new(1, -24, 1, -18)
remLbl.Position = UDim2.new(0, 12, 0, 9)
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
    t(TR), t(SR), t(ER), t(CR), t(PR), t(PSR), t(RBR), t(RUR), t(BPR), t(ZDR), t(GR), t(HR), t(ACH)
)

----------------------------------------------------------------------
-- FOOTER HINT BAR
----------------------------------------------------------------------

local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, 0, 0, 28)
footer.Position = UDim2.new(0, 0, 1, -28)
footer.BackgroundColor3 = C.panel
footer.BorderSizePixel = 0
footer.Parent = Win
corner(footer, 14)

local footFix = Instance.new("Frame")
footFix.Size = UDim2.new(1, 0, 0, 14)
footFix.Position = UDim2.new(0, 0, 0, 0)
footFix.BackgroundColor3 = C.panel
footFix.BorderSizePixel = 0
footFix.Parent = footer

local footLine = Instance.new("Frame")
footLine.Size = UDim2.new(1, 0, 0, 1)
footLine.Position = UDim2.new(0, 0, 0, 0)
footLine.BackgroundColor3 = C.border
footLine.BorderSizePixel = 0
footLine.ZIndex = 2
footLine.Parent = footer

local hintLbl = Instance.new("TextLabel")
hintLbl.Size = UDim2.new(1, -24, 1, 0)
hintLbl.Position = UDim2.new(0, 12, 0, 0)
hintLbl.BackgroundTransparency = 1
hintLbl.TextColor3 = C.sub
hintLbl.Font = Enum.Font.GothamMedium
hintLbl.TextSize = 10
hintLbl.TextXAlignment = Enum.TextXAlignment.Center
hintLbl.RichText = true
hintLbl.ZIndex = 2
hintLbl.Text = '<font color="#8C8CA2"><b>[INSERT]</b> toggle UI</font>  ·  drag the title bar to move'
hintLbl.Parent = footer

selTab("Farm")
