local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

if getgenv().ShowFPS and getgenv().ShowFPS.Unload then
	getgenv().ShowFPS.Unload()
end

local Controller = {}
getgenv().ShowFPS = Controller

local connections = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

local parent = (gethui and gethui()) or game:GetService("CoreGui")

local gui = Instance.new("ScreenGui")
gui.Name = "\0\0ShowFPS\0\0"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
if syn and syn.protect_gui then
	syn.protect_gui(gui)
elseif protectgui then
	protectgui(gui)
end
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Name = "Body"
frame.AnchorPoint = Vector2.new(1, 0)
frame.Position = UDim2.new(1, -16, 0, 16)
frame.Size = UDim2.fromOffset(168, 86)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
frame.BackgroundTransparency = 0.08
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 80)
stroke.Transparency = 0.4
stroke.Thickness = 1
stroke.Parent = frame

local accent = Instance.new("Frame")
accent.Name = "Accent"
accent.Position = UDim2.fromOffset(0, 0)
accent.Size = UDim2.new(1, 0, 0, 3)
accent.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
accent.BorderSizePixel = 0
accent.Parent = frame

local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(0, 12)
accentCorner.Parent = accent

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 14, 0, 10)
title.Size = UDim2.new(1, -50, 0, 16)
title.Font = Enum.Font.GothamMedium
title.Text = "FPS"
title.TextColor3 = Color3.fromRGB(150, 150, 170)
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

local close = Instance.new("TextButton")
close.Name = "Close"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -10, 0, 8)
close.Size = UDim2.fromOffset(20, 20)
close.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
close.BackgroundTransparency = 0.2
close.Font = Enum.Font.GothamBold
close.Text = "\u{00D7}"
close.TextColor3 = Color3.fromRGB(200, 200, 220)
close.TextSize = 14
close.AutoButtonColor = true
close.Parent = frame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = close

local value = Instance.new("TextLabel")
value.Name = "Value"
value.BackgroundTransparency = 1
value.Position = UDim2.new(0, 14, 0, 26)
value.Size = UDim2.new(1, -28, 0, 36)
value.Font = Enum.Font.GothamBold
value.Text = "0"
value.TextColor3 = Color3.fromRGB(255, 255, 255)
value.TextSize = 32
value.TextXAlignment = Enum.TextXAlignment.Left
value.Parent = frame

local details = Instance.new("TextLabel")
details.Name = "Details"
details.BackgroundTransparency = 1
details.Position = UDim2.new(0, 14, 1, -22)
details.Size = UDim2.new(1, -28, 0, 16)
details.Font = Enum.Font.Gotham
details.Text = "min - / avg - / ping -"
details.TextColor3 = Color3.fromRGB(130, 130, 150)
details.TextSize = 11
details.TextXAlignment = Enum.TextXAlignment.Left
details.Parent = frame

do
	local dragging, dragStart, startPos
	local function update(input)
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
	bind(frame.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	bind(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end)
end

local accum = 0
local count = 0
local timer = 0
local minFps = math.huge

local function colorFor(fps)
	if fps >= 50 then
		return Color3.fromRGB(90, 200, 120)
	elseif fps >= 30 then
		return Color3.fromRGB(230, 195, 90)
	else
		return Color3.fromRGB(230, 90, 90)
	end
end

local function getPing()
	local ok, ping = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and ping then
		return string.format("%d ms", math.floor(ping + 0.5))
	end
	return "-"
end

bind(RunService.RenderStepped, function(dt)
	if dt <= 0 then return end
	accum += 1 / dt
	count += 1
	timer += dt
	if timer >= 0.5 then
		local fps = math.floor(accum / count + 0.5)
		minFps = math.min(minFps, fps)
		value.Text = tostring(fps)
		value.TextColor3 = colorFor(fps)
		accent.BackgroundColor3 = colorFor(fps)
		details.Text = string.format("min %d / avg %d / %s", minFps, fps, getPing())
		accum, count, timer = 0, 0, 0
	end
end)

bind(LocalPlayer.Idled, function()
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

local function unload()
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	pcall(function() gui:Destroy() end)
	if getgenv().ShowFPS == Controller then
		getgenv().ShowFPS = nil
	end
end

Controller.Unload = unload
close.MouseButton1Click:Connect(unload)
