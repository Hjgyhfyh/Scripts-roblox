local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

if getgenv().GammaController and getgenv().GammaController.Unload then
	pcall(getgenv().GammaController.Unload)
end

local State = {
	Connections = {},
	Min = 0.20,
	Max = 3.00,
	Value = 1.00,
}
getgenv().GammaController = State

local function addConn(c)
	table.insert(State.Connections, c)
	return c
end

local originalExposure = Lighting.ExposureCompensation

local effect = Instance.new("ColorCorrectionEffect")
effect.Name = "GammaFX_" .. tostring(math.random(1000, 9999))
effect.Enabled = true
effect.Parent = Lighting
State.Effect = effect

local function applyGamma(g)
	State.Value = g
	effect.Brightness = (g - 1) * 0.22
	effect.Contrast = (g - 1) * -0.04
	effect.Saturation = (g - 1) * 0.05
	Lighting.ExposureCompensation = originalExposure + (g - 1) * 0.55
end

local gui = Instance.new("ScreenGui")
gui.Name = "GammaUI_" .. tostring(math.random(1000, 9999))
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
State.Gui = gui

do
	local ok = pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
			gui.Parent = game:GetService("CoreGui")
		elseif gethui then
			gui.Parent = gethui()
		else
			gui.Parent = game:GetService("CoreGui")
		end
	end)
	if not ok then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 270, 0, 150)
main.Position = UDim2.new(0.5, -135, 0.5, -75)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = main

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 170, 255)
stroke.Thickness = 1.4
stroke.Transparency = 0.35
stroke.Parent = main

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 16, 0, 12)
title.Size = UDim2.new(1, -120, 0, 24)
title.Font = Enum.Font.GothamBold
title.Text = "Гамма"
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(240, 240, 245)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local valueLabel = Instance.new("TextLabel")
valueLabel.BackgroundTransparency = 1
valueLabel.Position = UDim2.new(0, 0, 0, 12)
valueLabel.Size = UDim2.new(1, -52, 0, 24)
valueLabel.Font = Enum.Font.GothamBold
valueLabel.Text = "1.00"
valueLabel.TextSize = 16
valueLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
valueLabel.TextXAlignment = Enum.TextXAlignment.Right
valueLabel.Parent = main

local close = Instance.new("TextButton")
close.Size = UDim2.new(0, 28, 0, 28)
close.Position = UDim2.new(1, -38, 0, 11)
close.BackgroundColor3 = Color3.fromRGB(45, 45, 54)
close.Text = "X"
close.Font = Enum.Font.GothamBold
close.TextSize = 14
close.TextColor3 = Color3.fromRGB(235, 120, 120)
close.AutoButtonColor = true
close.Parent = main

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = close

local track = Instance.new("Frame")
track.Size = UDim2.new(1, -32, 0, 8)
track.Position = UDim2.new(0, 16, 0, 80)
track.BackgroundColor3 = Color3.fromRGB(48, 48, 58)
track.BorderSizePixel = 0
track.Parent = main

local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.Size = UDim2.new(0.32, 0, 1, 0)
fill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
fill.BorderSizePixel = 0
fill.Parent = track

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local knob = Instance.new("Frame")
knob.Size = UDim2.new(0, 18, 0, 18)
knob.Position = UDim2.new(0.32, -9, 0.5, -9)
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.BorderSizePixel = 0
knob.ZIndex = 3
knob.Parent = track

local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius = UDim.new(1, 0)
knobCorner.Parent = knob

local reset = Instance.new("TextButton")
reset.Size = UDim2.new(1, -32, 0, 30)
reset.Position = UDim2.new(0, 16, 1, -42)
reset.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
reset.Text = "Сброс (1.00)"
reset.Font = Enum.Font.GothamMedium
reset.TextSize = 14
reset.TextColor3 = Color3.fromRGB(220, 220, 225)
reset.AutoButtonColor = true
reset.Parent = main

local resetCorner = Instance.new("UICorner")
resetCorner.CornerRadius = UDim.new(0, 8)
resetCorner.Parent = reset

local dragBar = Instance.new("TextButton")
dragBar.BackgroundTransparency = 1
dragBar.Text = ""
dragBar.Size = UDim2.new(1, -46, 0, 44)
dragBar.Position = UDim2.new(0, 0, 0, 0)
dragBar.Parent = main

local function setValue(val)
	val = math.clamp(val, State.Min, State.Max)
	local frac = (val - State.Min) / (State.Max - State.Min)
	fill.Size = UDim2.new(frac, 0, 1, 0)
	knob.Position = UDim2.new(frac, -9, 0.5, -9)
	valueLabel.Text = string.format("%.2f", val)
	applyGamma(val)
end

function State.Unload()
	for _, c in ipairs(State.Connections) do
		pcall(function() c:Disconnect() end)
	end
	State.Connections = {}
	pcall(function() effect:Destroy() end)
	Lighting.ExposureCompensation = originalExposure
	pcall(function() gui:Destroy() end)
	getgenv().GammaController = nil
end

local dragging = false
local function updateFromX(px)
	local left = track.AbsolutePosition.X
	local width = track.AbsoluteSize.X
	local frac = math.clamp((px - left) / width, 0, 1)
	setValue(State.Min + frac * (State.Max - State.Min))
end

addConn(track.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		updateFromX(input.Position.X)
	end
end))

addConn(knob.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
	end
end))

local winDragging = false
local dragStart, startPos
addConn(dragBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		winDragging = true
		dragStart = input.Position
		startPos = main.Position
	end
end))

addConn(UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		if dragging then
			updateFromX(input.Position.X)
		end
		if winDragging then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end
end))

addConn(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
		winDragging = false
	end
end))

addConn(reset.MouseButton1Click:Connect(function()
	setValue(1.00)
end))

addConn(close.MouseButton1Click:Connect(function()
	State.Unload()
end))

addConn(LocalPlayer.Idled:Connect(function()
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end))

setValue(1.00)
