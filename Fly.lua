local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local lp = Players.LocalPlayer
local char, hum, root

local function refreshChar()
    char = lp.Character
    if not char then return false end
    hum = char:FindFirstChildOfClass("Humanoid")
    root = char:FindFirstChild("HumanoidRootPart")
    return hum ~= nil and root ~= nil
end

refreshChar()

lp.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local flying = false
local speed = 60
local SMIN, SMAX = 10, 400
local flyConns = {}
local bv, bg

local gui = Instance.new("ScreenGui")
gui.Name = "FlyGUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

if syn and syn.protect_gui then
    syn.protect_gui(gui)
    gui.Parent = game:GetService("CoreGui")
elseif gethui then
    gui.Parent = gethui()
else
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
end

local function mkFrame(parent, size, pos, color, zi)
    local f = Instance.new("Frame")
    f.Size = size
    f.Position = pos
    f.BackgroundColor3 = color or Color3.fromRGB(255,255,255)
    f.BorderSizePixel = 0
    if zi then f.ZIndex = zi end
    f.Parent = parent
    return f
end

local function mkCorner(parent, r)
    local c = Instance.new("UICorner", parent)
    c.CornerRadius = UDim.new(0, r or 12)
end

local function mkLabel(parent, size, pos, text, color, tsize, font, xalign, zi)
    local l = Instance.new("TextLabel")
    l.Size = size
    l.Position = pos
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.fromRGB(255,255,255)
    l.TextSize = tsize or 13
    l.Font = font or Enum.Font.Gotham
    if xalign then l.TextXAlignment = xalign end
    if zi then l.ZIndex = zi end
    l.Parent = parent
    return l
end

local W, H = 290, 330

local win = mkFrame(gui,
    UDim2.new(0, W, 0, H),
    UDim2.new(0.5, -W/2, 0.5, -H/2),
    Color3.fromRGB(10, 10, 20), 1)
mkCorner(win, 16)

local glow = Instance.new("ImageLabel", win)
glow.Size = UDim2.new(1, 80, 1, 80)
glow.Position = UDim2.new(0, -40, 0, -40)
glow.BackgroundTransparency = 1
glow.Image = "rbxassetid://5028857084"
glow.ImageColor3 = Color3.fromRGB(90, 25, 215)
glow.ImageTransparency = 0.55
glow.ScaleType = Enum.ScaleType.Slice
glow.SliceCenter = Rect.new(24, 24, 276, 276)
glow.ZIndex = 0

local head = mkFrame(win, UDim2.new(1, 0, 0, 52), UDim2.new(0,0,0,0), Color3.fromRGB(25,8,52), 2)
mkCorner(head, 16)
local headGrad = Instance.new("UIGradient", head)
headGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(105, 35, 230)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(50,  75, 220)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(15, 155, 250))
})

mkLabel(head, UDim2.new(0,32,0,32), UDim2.new(0,12,0.5,-16), "✈",
    Color3.fromRGB(255,255,255), 22, Enum.Font.GothamBold, nil, 3)
mkLabel(head, UDim2.new(1,-110,0,21), UDim2.new(0,48,0,7), "FLY  SCRIPT",
    Color3.fromRGB(255,255,255), 15, Enum.Font.GothamBold, Enum.TextXAlignment.Left, 3)
mkLabel(head, UDim2.new(1,-110,0,14), UDim2.new(0,48,0,30), "Universal  •  [F] toggle",
    Color3.fromRGB(205,180,255), 10, Enum.Font.Gotham, Enum.TextXAlignment.Left, 3)

local function mkHeaderBtn(xOff, col, txt)
    local b = Instance.new("TextButton", head)
    b.Size = UDim2.new(0, 28, 0, 28)
    b.Position = UDim2.new(1, xOff, 0.5, -14)
    b.BackgroundColor3 = col
    b.Text = txt
    b.TextColor3 = Color3.fromRGB(255,255,255)
    b.TextSize = 14
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.ZIndex = 4
    mkCorner(b, 7)
    return b
end

local closeBtn = mkHeaderBtn(-10, Color3.fromRGB(215, 50, 65), "✕")
local minBtn   = mkHeaderBtn(-42, Color3.fromRGB(190, 140, 0), "–")

local body = mkFrame(win, UDim2.new(1,0,1,-52), UDim2.new(0,0,0,52), Color3.fromRGB(0,0,0), 2)
body.BackgroundTransparency = 1

local sCard = mkFrame(body, UDim2.new(1,-24,0,64), UDim2.new(0,12,0,16), Color3.fromRGB(17,17,31), 2)
mkCorner(sCard, 12)

local sDot = mkFrame(sCard, UDim2.new(0,10,0,10), UDim2.new(0,16,0.5,-5), Color3.fromRGB(72,72,102), 3)
mkCorner(sDot, 10)

local sText = mkLabel(sCard, UDim2.new(1,-100,1,0), UDim2.new(0,34,0,0), "ВЫКЛЮЧЕН",
    Color3.fromRGB(132,132,162), 13, Enum.Font.GothamBold, Enum.TextXAlignment.Left, 3)

local togTrack = Instance.new("TextButton", sCard)
togTrack.Size = UDim2.new(0, 56, 0, 30)
togTrack.Position = UDim2.new(1, -68, 0.5, -15)
togTrack.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
togTrack.Text = ""
togTrack.BorderSizePixel = 0
togTrack.ZIndex = 3
mkCorner(togTrack, 15)

local togKnob = mkFrame(togTrack, UDim2.new(0,24,0,24), UDim2.new(0,3,0.5,-12), Color3.fromRGB(100,100,132), 4)
mkCorner(togKnob, 12)

mkLabel(body, UDim2.new(1,-24,0,18), UDim2.new(0,12,0,96), "СКОРОСТЬ  ПОЛЁТА",
    Color3.fromRGB(122,122,158), 11, Enum.Font.GothamBold, Enum.TextXAlignment.Left, 2)

local speedLbl = mkLabel(body, UDim2.new(0,55,0,18), UDim2.new(1,-67,0,96), tostring(speed),
    Color3.fromRGB(130,65,245), 13, Enum.Font.GothamBold, Enum.TextXAlignment.Right, 2)

local slTrack = mkFrame(body, UDim2.new(1,-24,0,8), UDim2.new(0,12,0,122), Color3.fromRGB(24,24,42), 3)
mkCorner(slTrack, 4)

local initR = (speed - SMIN) / (SMAX - SMIN)
local slFill = mkFrame(slTrack, UDim2.new(initR,0,1,0), UDim2.new(0,0,0,0), Color3.fromRGB(130,55,245), 4)
mkCorner(slFill, 4)
local slGrad = Instance.new("UIGradient", slFill)
slGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(130, 55, 245)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 175, 255))
})

local slKnob = mkFrame(slTrack, UDim2.new(0,18,0,18), UDim2.new(initR,-9,0.5,-9), Color3.fromRGB(240,240,255), 5)
mkCorner(slKnob, 9)

mkLabel(body, UDim2.new(1,-24,0,18), UDim2.new(0,12,0,148), "БЫСТРЫЙ  ВЫБОР",
    Color3.fromRGB(122,122,158), 11, Enum.Font.GothamBold, Enum.TextXAlignment.Left, 2)

local pRow = mkFrame(body, UDim2.new(1,-24,0,34), UDim2.new(0,12,0,170), Color3.fromRGB(0,0,0), 2)
pRow.BackgroundTransparency = 1
local pLayout = Instance.new("UIListLayout", pRow)
pLayout.FillDirection = Enum.FillDirection.Horizontal
pLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
pLayout.Padding = UDim.new(0, 7)

local presets = { {"Тихо",20}, {"Норм",60}, {"Быстро",150}, {"Турбо",350} }
local pBtns = {}
for i, p in ipairs(presets) do
    local pb = Instance.new("TextButton", pRow)
    pb.Size = UDim2.new(0, 57, 0, 34)
    pb.BackgroundColor3 = Color3.fromRGB(20, 20, 38)
    pb.Text = p[1]
    pb.TextColor3 = Color3.fromRGB(162,162,202)
    pb.TextSize = 11
    pb.Font = Enum.Font.GothamBold
    pb.BorderSizePixel = 0
    pb.ZIndex = 3
    mkCorner(pb, 8)
    pBtns[i] = pb
    local s = p[2]
    pb.MouseButton1Click:Connect(function()
        speed = s
        local r = (s - SMIN) / (SMAX - SMIN)
        speedLbl.Text = tostring(s)
        slFill.Size = UDim2.new(r, 0, 1, 0)
        slKnob.Position = UDim2.new(r, -9, 0.5, -9)
        for _, b in ipairs(pBtns) do
            TweenService:Create(b, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(20,20,38),
                TextColor3 = Color3.fromRGB(162,162,202)
            }):Play()
        end
        TweenService:Create(pb, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(72,32,150),
            TextColor3 = Color3.fromRGB(210,180,255)
        }):Play()
    end)
end

local hCard = mkFrame(body, UDim2.new(1,-24,0,50), UDim2.new(0,12,0,218), Color3.fromRGB(12,12,24), 2)
mkCorner(hCard, 10)
local hLbl = mkLabel(hCard, UDim2.new(1,-16,1,0), UDim2.new(0,8,0,0),
    "WASD — горизонталь  •  Space — вверх\nShift — вниз  •  F — вкл / выкл",
    Color3.fromRGB(90,90,130), 10, Enum.Font.Gotham, Enum.TextXAlignment.Center, 3)
hLbl.TextWrapped = true

local dDrag, dOff = false, Vector2.new()
head.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dDrag = true
        dOff = Vector2.new(i.Position.X - win.AbsolutePosition.X, i.Position.Y - win.AbsolutePosition.Y)
    end
end)
head.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dDrag = false end
end)
UserInputService.InputChanged:Connect(function(i)
    if dDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
        win.Position = UDim2.new(0, i.Position.X - dOff.X, 0, i.Position.Y - dOff.Y)
    end
end)

local slActive = false
local function applySlider(x)
    local r = math.clamp((x - slTrack.AbsolutePosition.X) / slTrack.AbsoluteSize.X, 0, 1)
    speed = math.floor(SMIN + r * (SMAX - SMIN))
    speedLbl.Text = tostring(speed)
    slFill.Size = UDim2.new(r, 0, 1, 0)
    slKnob.Position = UDim2.new(r, -9, 0.5, -9)
end
slTrack.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then slActive = true; applySlider(i.Position.X) end
end)
slTrack.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then slActive = false end
end)
UserInputService.InputChanged:Connect(function(i)
    if slActive and i.UserInputType == Enum.UserInputType.MouseMovement then applySlider(i.Position.X) end
end)

local function startFly()
    if not refreshChar() then return end
    hum.PlatformStand = true
    bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bv.Velocity = Vector3.new()
    bv.Parent = root
    bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    bg.D = 600
    bg.P = 50000
    bg.CFrame = root.CFrame
    bg.Parent = root
    table.insert(flyConns, RunService.RenderStepped:Connect(function()
        if not flying or not root or not root.Parent then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local cf = cam.CFrame
        local v = Vector3.new()
        if UserInputService:IsKeyDown(Enum.KeyCode.W)         then v = v + cf.LookVector  * speed end
        if UserInputService:IsKeyDown(Enum.KeyCode.S)         then v = v - cf.LookVector  * speed end
        if UserInputService:IsKeyDown(Enum.KeyCode.D)         then v = v + cf.RightVector * speed end
        if UserInputService:IsKeyDown(Enum.KeyCode.A)         then v = v - cf.RightVector * speed end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)     then v = v + Vector3.new(0, speed, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then v = v - Vector3.new(0, speed, 0) end
        bv.Velocity = v
        if v.Magnitude > 0.1 then bg.CFrame = CFrame.new(Vector3.new(), v) end
    end))
end

local function stopFly()
    for _, c in ipairs(flyConns) do c:Disconnect() end
    flyConns = {}
    if bv then bv:Destroy(); bv = nil end
    if bg then bg:Destroy(); bg = nil end
    if refreshChar() then hum.PlatformStand = false end
end

local ti = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function setFly(on)
    flying = on
    if on then
        startFly()
        TweenService:Create(togKnob, ti, {Position = UDim2.new(1,-27,0.5,-12), BackgroundColor3 = Color3.fromRGB(255,255,255)}):Play()
        TweenService:Create(togTrack, ti, {BackgroundColor3 = Color3.fromRGB(108,42,240)}):Play()
        sDot.BackgroundColor3 = Color3.fromRGB(50, 210, 90)
        sText.Text = "ВКЛЮЧЁН"
        sText.TextColor3 = Color3.fromRGB(50, 210, 90)
    else
        stopFly()
        TweenService:Create(togKnob, ti, {Position = UDim2.new(0,3,0.5,-12), BackgroundColor3 = Color3.fromRGB(100,100,132)}):Play()
        TweenService:Create(togTrack, ti, {BackgroundColor3 = Color3.fromRGB(30,30,50)}):Play()
        sDot.BackgroundColor3 = Color3.fromRGB(72, 72, 102)
        sText.Text = "ВЫКЛЮЧЕН"
        sText.TextColor3 = Color3.fromRGB(132, 132, 162)
    end
end

togTrack.MouseButton1Click:Connect(function() setFly(not flying) end)

local kConn = UserInputService.InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.F then setFly(not flying) end
end)

local minim = false
minBtn.MouseButton1Click:Connect(function()
    minim = not minim
    if minim then
        TweenService:Create(win, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0,W,0,52)}):Play()
        minBtn.Text = "+"
    else
        TweenService:Create(win, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0,W,0,H)}):Play()
        minBtn.Text = "–"
    end
end)

lp.CharacterAdded:Connect(function(c)
    char = c
    hum = c:WaitForChild("Humanoid")
    root = c:WaitForChild("HumanoidRootPart")
    if flying then
        task.wait(0.5)
        for _, cn in ipairs(flyConns) do cn:Disconnect() end
        flyConns = {}
        if bv then bv:Destroy(); bv = nil end
        if bg then bg:Destroy(); bg = nil end
        startFly()
    end
end)

local function unload()
    setFly(false)
    kConn:Disconnect()
    gui:Destroy()
end

closeBtn.MouseButton1Click:Connect(unload)
