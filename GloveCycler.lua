local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local lp = Players.LocalPlayer

if _G.__GloveCyclerUnload then pcall(_G.__GloveCyclerUnload) end

local hostGui = (gethui and gethui()) or game:GetService("CoreGui")
local previous = hostGui:FindFirstChild("GloveCyclerUI")
if previous then previous:Destroy() end

local S = {
	running = true,
	rate = 10,
	idx = 0,
	total = 0,
	cur = "-",
}
local conns = {}

conns[#conns + 1] = lp.Idled:Connect(function()
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

local gui = Instance.new("ScreenGui")
gui.Name = "GloveCyclerUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
gui.Parent = hostGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(260, 168)
main.Position = UDim2.new(0.5, -130, 0.35, 0)
main.BackgroundColor3 = Color3.fromRGB(20, 21, 28)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(0, 175, 120)
stroke.Thickness = 1.5
stroke.Transparency = 0.25

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, 0, 0, 32)
header.BackgroundColor3 = Color3.fromRGB(0, 175, 120)
header.BorderSizePixel = 0
header.Text = "   Glove Cycler"
header.TextXAlignment = Enum.TextXAlignment.Left
header.Font = Enum.Font.GothamBold
header.TextSize = 15
header.TextColor3 = Color3.fromRGB(255, 255, 255)
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(26, 26)
closeBtn.Position = UDim2.new(1, -30, 0, 3)
closeBtn.BackgroundColor3 = Color3.fromRGB(205, 65, 65)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.AutoButtonColor = true
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 42)
status.Position = UDim2.new(0, 12, 0, 38)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 13
status.TextColor3 = Color3.fromRGB(225, 225, 225)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = "Перебор: 0 / 0"
status.Parent = main

local minus = Instance.new("TextButton")
minus.Size = UDim2.fromOffset(34, 30)
minus.Position = UDim2.new(0, 12, 0, 86)
minus.BackgroundColor3 = Color3.fromRGB(45, 47, 58)
minus.Text = "-"
minus.Font = Enum.Font.GothamBold
minus.TextSize = 20
minus.TextColor3 = Color3.fromRGB(255, 255, 255)
minus.Parent = main
Instance.new("UICorner", minus).CornerRadius = UDim.new(0, 7)

local rateLabel = Instance.new("TextLabel")
rateLabel.Size = UDim2.new(1, -116, 0, 30)
rateLabel.Position = UDim2.new(0, 50, 0, 86)
rateLabel.BackgroundColor3 = Color3.fromRGB(30, 31, 40)
rateLabel.Font = Enum.Font.GothamMedium
rateLabel.TextSize = 13
rateLabel.TextColor3 = Color3.fromRGB(0, 220, 150)
rateLabel.Text = "10/сек • 0.10с"
rateLabel.Parent = main
Instance.new("UICorner", rateLabel).CornerRadius = UDim.new(0, 7)

local plus = Instance.new("TextButton")
plus.Size = UDim2.fromOffset(34, 30)
plus.Position = UDim2.new(1, -46, 0, 86)
plus.BackgroundColor3 = Color3.fromRGB(45, 47, 58)
plus.Text = "+"
plus.Font = Enum.Font.GothamBold
plus.TextSize = 20
plus.TextColor3 = Color3.fromRGB(255, 255, 255)
plus.Parent = main
Instance.new("UICorner", plus).CornerRadius = UDim.new(0, 7)

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(1, -24, 0, 36)
toggle.Position = UDim2.new(0, 12, 1, -44)
toggle.BackgroundColor3 = Color3.fromRGB(0, 155, 105)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 15
toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggle.Text = "ВКЛ"
toggle.Parent = main
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 8)

local function refreshRate()
	rateLabel.Text = string.format("%d/сек • %.2fс", S.rate, 1 / S.rate)
end

minus.MouseButton1Click:Connect(function()
	S.rate = math.max(1, S.rate - 1)
	refreshRate()
end)

plus.MouseButton1Click:Connect(function()
	S.rate = math.min(100, S.rate + 1)
	refreshRate()
end)

toggle.MouseButton1Click:Connect(function()
	S.running = not S.running
	toggle.Text = S.running and "ВКЛ" or "ВЫКЛ"
	toggle.BackgroundColor3 = S.running and Color3.fromRGB(0, 155, 105) or Color3.fromRGB(150, 60, 60)
end)

conns[#conns + 1] = RunService.RenderStepped:Connect(function()
	status.Text = string.format("Перебор: %d / %d\nСейчас: %s", S.idx, S.total, S.cur)
end)

local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = main.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end)

local function unload()
	S.running = false
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	if gui then
		gui:Destroy()
	end
	_G.__GloveCyclerUnload = nil
end

_G.__GloveCyclerUnload = unload
closeBtn.MouseButton1Click:Connect(unload)

task.spawn(function()
	while gui.Parent do
		if S.running then
			local char = lp.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local bp = lp:FindFirstChild("Backpack")
			if hum and bp then
				local tools = {}
				for _, v in ipairs(bp:GetChildren()) do
					if v:IsA("Tool") then
						tools[#tools + 1] = v
					end
				end
				for _, v in ipairs(char:GetChildren()) do
					if v:IsA("Tool") then
						tools[#tools + 1] = v
					end
				end
				S.total = #tools
				if S.total == 0 then
					task.wait(0.3)
				else
					for i, tool in ipairs(tools) do
						if not S.running or not gui.Parent then
							break
						end
						S.idx = i
						if tool and tool.Parent then
							S.cur = tool.Name
							pcall(function()
								hum:EquipTool(tool)
							end)
						end
						task.wait(1 / S.rate)
					end
				end
			else
				task.wait(0.3)
			end
		else
			task.wait(0.1)
		end
	end
end)
