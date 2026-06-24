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
	GammaMin = -5.00,
	GammaMax = 3.00,
	GammaValue = 1.00,
	UIMin = -5.00,
	UIMax = 5.00,
	UIValue = 0.00,
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
	State.GammaValue = g
	effect.Brightness = (g - 1) * 0.22
	effect.Contrast = (g - 1) * -0.04
	effect.Saturation = (g - 1) * 0.05
	Lighting.ExposureCompensation = originalExposure + (g - 1) * 0.55
end

local tintReg = {}
local function reg(obj, prop)
	tintReg[#tintReg + 1] = { obj = obj, prop = prop, base = obj[prop] }
end

local function applyUIBrightness(b)
	State.UIValue = b
	local t = (math.abs(b) / 5) * 0.85
	local target = (b >= 0) and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
	for _, e in ipairs(tintReg) do
		e.obj[e.prop] = e.base:Lerp(target, t)
	end
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
main.Size = UDim2.new(0, 270, 0, 192)
main.Position = UDim2.new(0.5, -135, 0.5, -96)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
reg(main, "BackgroundColor3")

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = main

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 170, 255)
stroke.Thickness = 1.4
stroke.Transparency = 0.35
stroke.Parent = main
reg(stroke, "Color")

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
reg(close, "BackgroundColor3")
reg(close, "TextColor3")

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = close

local function makeSlider(opts)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 16, 0, opts.yLabel)
	lbl.Size = UDim2.new(1, -120, 0, 24)
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = opts.name
	lbl.TextSize = 16
	lbl.TextColor3 = Color3.fromRGB(240, 240, 245)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = main
	reg(lbl, "TextColor3")

	local val = Instance.new("TextLabel")
	val.BackgroundTransparency = 1
	val.Position = UDim2.new(0, 0, 0, opts.yLabel)
	val.Size = UDim2.new(1, -52, 0, 24)
	val.Font = Enum.Font.GothamBold
	val.Text = "0"
	val.TextSize = 15
	val.TextColor3 = Color3.fromRGB(0, 200, 255)
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = main
	reg(val, "TextColor3")

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -32, 0, 8)
	track.Position = UDim2.new(0, 16, 0, opts.yTrack)
	track.BackgroundColor3 = Color3.fromRGB(48, 48, 58)
	track.BorderSizePixel = 0
	track.Parent = main
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track
	reg(track, "BackgroundColor3")

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0.5, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill
	reg(fill, "BackgroundColor3")

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = UDim2.new(0.5, -9, 0.5, -9)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.ZIndex = 3
	knob.Parent = track
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local function setVal(v)
		v = math.clamp(v, opts.min, opts.max)
		local frac = (v - opts.min) / (opts.max - opts.min)
		fill.Size = UDim2.new(frac, 0, 1, 0)
		knob.Position = UDim2.new(frac, -9, 0.5, -9)
		val.Text = string.format(opts.fmt, v)
		opts.onChange(v)
	end

	local dragging = false
	local function updateFromX(px)
		local left = track.AbsolutePosition.X
		local width = track.AbsoluteSize.X
		local frac = math.clamp((px - left) / width, 0, 1)
		setVal(opts.min + frac * (opts.max - opts.min))
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
	addConn(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(input.Position.X)
		end
	end))
	addConn(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	return setVal
end

local gammaSet = makeSlider({
	name = "Гамма",
	yLabel = 14,
	yTrack = 44,
	min = State.GammaMin,
	max = State.GammaMax,
	default = 1.00,
	fmt = "%.2f",
	onChange = applyGamma,
})

local uiSet = makeSlider({
	name = "Яркость UI",
	yLabel = 76,
	yTrack = 106,
	min = State.UIMin,
	max = State.UIMax,
	default = 0.00,
	fmt = "%.1f",
	onChange = applyUIBrightness,
})

local reset = Instance.new("TextButton")
reset.Size = UDim2.new(1, -32, 0, 30)
reset.Position = UDim2.new(0, 16, 1, -40)
reset.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
reset.Text = "Сброс"
reset.Font = Enum.Font.GothamMedium
reset.TextSize = 14
reset.TextColor3 = Color3.fromRGB(220, 220, 225)
reset.AutoButtonColor = true
reset.Parent = main
local resetCorner = Instance.new("UICorner")
resetCorner.CornerRadius = UDim.new(0, 8)
resetCorner.Parent = reset
reg(reset, "BackgroundColor3")
reg(reset, "TextColor3")

local dragBar = Instance.new("TextButton")
dragBar.BackgroundTransparency = 1
dragBar.Text = ""
dragBar.Size = UDim2.new(1, -46, 0, 42)
dragBar.Position = UDim2.new(0, 0, 0, 0)
dragBar.Parent = main

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
	if winDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end))
addConn(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		winDragging = false
	end
end))

addConn(reset.MouseButton1Click:Connect(function()
	gammaSet(1.00)
	uiSet(0.00)
end))

addConn(close.MouseButton1Click:Connect(function()
	State.Unload()
end))

addConn(LocalPlayer.Idled:Connect(function()
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end))

gammaSet(1.00)
uiSet(0.00)
