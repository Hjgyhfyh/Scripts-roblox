if _G.__CGM and _G.__CGM.unload then pcall(_G.__CGM.unload) end
local SESSION = {}
_G.__CGM = SESSION
_G.__CGM_LOADED = true

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local VirtualUser      = game:GetService("VirtualUser")

local lp  = Players.LocalPlayer
local Net = require(ReplicatedStorage.Modules.Networking)
local DM  = require(ReplicatedStorage.Modules.DataModule)
local data = DM.GetData(lp)

local startCircles  = data["NumberValues.Collects"] or 0
local startDiamonds = data["NumberValues.DiamondsCollected"] or 0

local state = {
    running  = true,
    circles  = true,
    diamonds = true,
    rate     = 15,
}
SESSION.state = state

local function alive() return state.running and _G.__CGM == SESSION end

local conns = {}
local function track(c) conns[#conns + 1] = c return c end

local function getCircleIds()
    local ok, buf = pcall(Net.Invoke, "GetCircles")
    if not ok or typeof(buf) ~= "buffer" then return nil end
    local s = buffer.tostring(buf)
    local ids = {}
    for i = 1, #s, 8 do
        local id = string.sub(s, i, i + 3)
        if #id == 4 then ids[#ids + 1] = id end
    end
    return ids
end

task.spawn(function()
    while state.running do
        if state.circles then
            local ids = getCircleIds()
            if ids and #ids > 0 then
                pcall(Net.Fire, "Collect", table.concat(ids))
            end
        end
        task.wait(1 / math.clamp(state.rate, 1, 30))
    end
end)

task.spawn(function()
    while state.running do
        if state.diamonds and typeof(firetouchinterest) == "function" then
            local char = lp.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local objs = workspace:FindFirstChild("Objects")
            if hrp and objs then
                for _, o in ipairs(objs:GetChildren()) do
                    if o.Name == "Diamond" then
                        local ti = o:FindFirstChildOfClass("TouchTransmitter")
                        if ti then
                            pcall(firetouchinterest, hrp, o, 0)
                            pcall(firetouchinterest, hrp, o, 1)
                        end
                    end
                end
            end
        end
        task.wait(0.4)
    end
end)

track(lp.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end))

local COL = {
    bg      = Color3.fromRGB(16, 16, 22),
    panel   = Color3.fromRGB(24, 24, 32),
    row     = Color3.fromRGB(31, 31, 42),
    text    = Color3.fromRGB(236, 236, 244),
    sub     = Color3.fromRGB(150, 150, 168),
    on      = Color3.fromRGB(132, 96, 255),
    on2     = Color3.fromRGB(64, 208, 255),
    off     = Color3.fromRGB(60, 60, 76),
}

local parentGui = (gethui and gethui()) or game:GetService("CoreGui")

local function corner(p, r)
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 8) c.Parent = p return c
end
local function stroke(p, col, t)
    local s = Instance.new("UIStroke") s.Color = col or Color3.fromRGB(70, 70, 92)
    s.Thickness = t or 1 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border s.Parent = p return s
end

local gui = Instance.new("ScreenGui")
gui.Name = "CGM_Suite"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = parentGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(300, 214)
main.Position = UDim2.new(0, 40, 0.5, -107)
main.BackgroundColor3 = COL.bg
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 12)
stroke(main, Color3.fromRGB(72, 64, 120), 1)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 46)
header.BackgroundColor3 = COL.panel
header.BorderSizePixel = 0
header.Parent = main
corner(header, 12)
local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 14)
headerFix.Position = UDim2.new(0, 0, 1, -14)
headerFix.BackgroundColor3 = COL.panel
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local accent = Instance.new("Frame")
accent.Size = UDim2.new(1, 0, 0, 2)
accent.Position = UDim2.new(0, 0, 1, -2)
accent.BorderSizePixel = 0
accent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
accent.Parent = header
local accentGrad = Instance.new("UIGradient")
accentGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, COL.on),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(96, 120, 255)),
    ColorSequenceKeypoint.new(1, COL.on2),
})
accentGrad.Parent = accent

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 16, 0, 7)
title.Size = UDim2.new(1, -70, 0, 20)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Circular Grinding Mill"
title.TextColor3 = COL.text
title.Parent = header
local titleGrad = Instance.new("UIGradient")
titleGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, COL.on),
    ColorSequenceKeypoint.new(1, COL.on2),
})
titleGrad.Parent = title

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 16, 0, 25)
subtitle.Size = UDim2.new(1, -70, 0, 14)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 11
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "Авто-сбор поля"
subtitle.TextColor3 = COL.sub
subtitle.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(26, 26)
closeBtn.Position = UDim2.new(1, -34, 0, 10)
closeBtn.BackgroundColor3 = COL.row
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.TextColor3 = COL.text
closeBtn.AutoButtonColor = true
closeBtn.Parent = header
corner(closeBtn, 7)

local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.new(0, 12, 0, 56)
body.Size = UDim2.new(1, -24, 1, -68)
body.Parent = main
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local function makeToggle(labelText, order, default, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 38)
    row.BackgroundColor3 = COL.row
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = body
    corner(row, 8)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(1, -70, 1, 0)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = labelText
    lbl.TextColor3 = COL.text
    lbl.Parent = row

    local sw = Instance.new("TextButton")
    sw.Size = UDim2.fromOffset(44, 22)
    sw.Position = UDim2.new(1, -54, 0.5, -11)
    sw.AutoButtonColor = false
    sw.Text = ""
    sw.BackgroundColor3 = default and COL.on or COL.off
    sw.Parent = row
    corner(sw, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.Position = default and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
    knob.BorderSizePixel = 0
    knob.Parent = sw
    corner(knob, 8)

    local value = default
    local function render()
        TweenService:Create(sw, TweenInfo.new(0.16), {BackgroundColor3 = value and COL.on or COL.off}):Play()
        TweenService:Create(knob, TweenInfo.new(0.16), {Position = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)}):Play()
    end
    sw.MouseButton1Click:Connect(function()
        value = not value
        render()
        onChange(value)
    end)
    return row
end

makeToggle("Кружки (Circles)", 1, state.circles, function(v) state.circles = v end)
makeToggle("Алмазы (Diamonds)", 2, state.diamonds, function(v) state.diamonds = v end)

local sliderRow = Instance.new("Frame")
sliderRow.Size = UDim2.new(1, 0, 0, 46)
sliderRow.BackgroundColor3 = COL.row
sliderRow.BorderSizePixel = 0
sliderRow.LayoutOrder = 3
sliderRow.Parent = body
corner(sliderRow, 8)

local sliderLbl = Instance.new("TextLabel")
sliderLbl.BackgroundTransparency = 1
sliderLbl.Position = UDim2.new(0, 12, 0, 6)
sliderLbl.Size = UDim2.new(1, -24, 0, 16)
sliderLbl.Font = Enum.Font.GothamMedium
sliderLbl.TextSize = 13
sliderLbl.TextXAlignment = Enum.TextXAlignment.Left
sliderLbl.TextColor3 = COL.text
sliderLbl.Text = "Сбор/сек"
sliderLbl.Parent = sliderRow

local sliderVal = Instance.new("TextLabel")
sliderVal.BackgroundTransparency = 1
sliderVal.Position = UDim2.new(1, -54, 0, 6)
sliderVal.Size = UDim2.new(0, 42, 0, 16)
sliderVal.Font = Enum.Font.GothamBold
sliderVal.TextSize = 13
sliderVal.TextXAlignment = Enum.TextXAlignment.Right
sliderVal.TextColor3 = COL.on2
sliderVal.Text = tostring(state.rate)
sliderVal.Parent = sliderRow

local track_ = Instance.new("Frame")
track_.Position = UDim2.new(0, 12, 0, 30)
track_.Size = UDim2.new(1, -24, 0, 8)
track_.BackgroundColor3 = COL.off
track_.BorderSizePixel = 0
track_.Parent = sliderRow
corner(track_, 4)

local fill = Instance.new("Frame")
fill.Size = UDim2.new((state.rate - 1) / 29, 0, 1, 0)
fill.BackgroundColor3 = COL.on
fill.BorderSizePixel = 0
fill.Parent = track_
corner(fill, 4)
local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, COL.on),
    ColorSequenceKeypoint.new(1, COL.on2),
})
fillGrad.Parent = fill

local knobS = Instance.new("Frame")
knobS.Size = UDim2.fromOffset(14, 14)
knobS.AnchorPoint = Vector2.new(0.5, 0.5)
knobS.Position = UDim2.new((state.rate - 1) / 29, 0, 0.5, 0)
knobS.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
knobS.BorderSizePixel = 0
knobS.ZIndex = 3
knobS.Parent = track_
corner(knobS, 7)

local dragging = false
local function setFromX(px)
    local rel = math.clamp((px - track_.AbsolutePosition.X) / track_.AbsoluteSize.X, 0, 1)
    local v = math.floor(rel * 29 + 0.5) + 1
    state.rate = v
    sliderVal.Text = tostring(v)
    local a = (v - 1) / 29
    fill.Size = UDim2.new(a, 0, 1, 0)
    knobS.Position = UDim2.new(a, 0, 0.5, 0)
end
track_.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true setFromX(i.Position.X)
    end
end)
knobS.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
    end
end)
track(UserInputService.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        setFromX(i.Position.X)
    end
end))
track(UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end))

local stat = Instance.new("TextLabel")
stat.BackgroundTransparency = 1
stat.Size = UDim2.new(1, 0, 0, 16)
stat.LayoutOrder = 4
stat.Font = Enum.Font.Gotham
stat.TextSize = 12
stat.TextColor3 = COL.sub
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.Text = "Собрано: 0 кружков · 0 алмазов"
stat.Parent = body

task.spawn(function()
    while state.running do
        local c = (data["NumberValues.Collects"] or 0) - startCircles
        local d = (data["NumberValues.DiamondsCollected"] or 0) - startDiamonds
        stat.Text = string.format("Собрано: %d кружков · %d алмазов", math.max(c, 0), math.max(d, 0))
        task.wait(0.25)
    end
end)

local dragF, dragStart, startPos = false
header.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragF = true dragStart = i.Position startPos = main.Position
        i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then dragF = false end
        end)
    end
end)
track(UserInputService.InputChanged:Connect(function(i)
    if dragF and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local delta = i.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end))

local function unload()
    state.running = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    pcall(function() gui:Destroy() end)
    _G.__CGM_LOADED = nil
    _G.__CGM_UNLOAD = nil
end
_G.__CGM_UNLOAD = unload
closeBtn.MouseButton1Click:Connect(unload)
