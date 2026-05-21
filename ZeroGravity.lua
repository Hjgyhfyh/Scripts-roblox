local gui = Instance.new("ScreenGui")
local main = Instance.new("Frame")
local label = Instance.new("TextLabel")
local UITextSizeConstraint = Instance.new("UITextSizeConstraint")
local buttonOn = Instance.new("TextButton")
local buttonOff = Instance.new("TextButton")
local UITextSizeConstraint_2 = Instance.new("UITextSizeConstraint")
local UITextSizeConstraint_3 = Instance.new("UITextSizeConstraint")
local UICorner = Instance.new("UICorner")
local UICorner2 = Instance.new("UICorner")
local UICorner3 = Instance.new("UICorner")

gui.Name = "ZeroGravityGui"
gui.Parent = gethui()
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

main.Name = "main"
main.Parent = gui
main.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
main.BorderColor3 = Color3.fromRGB(0, 0, 0)
main.BorderSizePixel = 0
main.Position = UDim2.new(0.196, 0, 0.557, 0)
main.Size = UDim2.new(0.178, 0, 0.18, 0)
main.Active = true
main.Draggable = true

UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = main

label.Name = "label"
label.Parent = main
label.BackgroundColor3 = Color3.fromRGB(65, 65, 65)
label.BorderColor3 = Color3.fromRGB(0, 0, 0)
label.BorderSizePixel = 0
label.Size = UDim2.new(1, 0, 0.25, 0)
label.Font = Enum.Font.GothamBold
label.Text = "Zero Gravity"
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.TextSize = 29
label.TextWrapped = true

UITextSizeConstraint.Parent = label
UITextSizeConstraint.MaxTextSize = 29

buttonOn.Name = "buttonOn"
buttonOn.Parent = main
buttonOn.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
buttonOn.BorderColor3 = Color3.fromRGB(0, 0, 0)
buttonOn.BorderSizePixel = 0
buttonOn.Position = UDim2.new(0.05, 0, 0.35, 0)
buttonOn.Size = UDim2.new(0.43, 0, 0.28, 0)
buttonOn.Font = Enum.Font.GothamBold
buttonOn.Text = "Enable"
buttonOn.TextColor3 = Color3.fromRGB(255, 255, 255)
buttonOn.TextSize = 20
buttonOn.TextScaled = true
buttonOn.TextWrapped = true

UICorner2.CornerRadius = UDim.new(0, 6)
UICorner2.Parent = buttonOn

UITextSizeConstraint_2.Parent = buttonOn
UITextSizeConstraint_2.MaxTextSize = 24

buttonOff.Name = "buttonOff"
buttonOff.Parent = main
buttonOff.BackgroundColor3 = Color3.fromRGB(180, 80, 80)
buttonOff.BorderColor3 = Color3.fromRGB(0, 0, 0)
buttonOff.BorderSizePixel = 0
buttonOff.Position = UDim2.new(0.52, 0, 0.35, 0)
buttonOff.Size = UDim2.new(0.43, 0, 0.28, 0)
buttonOff.Font = Enum.Font.GothamBold
buttonOff.Text = "Disable"
buttonOff.TextColor3 = Color3.fromRGB(255, 255, 255)
buttonOff.TextSize = 20
buttonOff.TextScaled = true
buttonOff.TextWrapped = true

UICorner3.CornerRadius = UDim.new(0, 6)
UICorner3.Parent = buttonOff

UITextSizeConstraint_3.Parent = buttonOff
UITextSizeConstraint_3.MaxTextSize = 24

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "statusLabel"
statusLabel.Parent = main
statusLabel.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
statusLabel.BorderSizePixel = 0
statusLabel.Position = UDim2.new(0.05, 0, 0.7, 0)
statusLabel.Size = UDim2.new(0.9, 0, 0.22, 0)
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "Status: OFF | WASD to control"
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.TextScaled = true
statusLabel.TextSize = 14
statusLabel.TextWrapped = true

local UICorner4 = Instance.new("UICorner")
UICorner4.CornerRadius = UDim.new(0, 4)
UICorner4.Parent = statusLabel

local plr = game:GetService("Players").LocalPlayer
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local normalGravity = workspace.Gravity

local zeroGravityActive = false
local flyConnection = nil
local controlForce = 25

local keysDown = {
	W = false,
	A = false,
	S = false,
	D = false,
	Space = false,
	LeftShift = false
}

local function enableZeroGravity()
	if zeroGravityActive then return end
	
	local character = plr.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	if not rootPart then return end
	
	workspace.Gravity = 0
	zeroGravityActive = true
	
	humanoid.PlatformStand = true
	
	statusLabel.Text = "Status: ON | WASD to control"
	statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	
	flyConnection = RunService.Heartbeat:Connect(function(dt)
		if not zeroGravityActive then return end
		
		local character = plr.Character
		if not character then return end
		
		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		local rootPart = humanoid and humanoid.RootPart
		if not rootPart then return end
		
		local camera = workspace.CurrentCamera
		local camCFrame = camera.CFrame
		local forward = camCFrame.LookVector
		local right = camCFrame.RightVector
		local up = Vector3.new(0, 1, 0)
		
		local controlDirection = Vector3.new(0, 0, 0)
		
		if keysDown.W then
			controlDirection = controlDirection + forward
		end
		if keysDown.S then
			controlDirection = controlDirection - forward
		end
		if keysDown.A then
			controlDirection = controlDirection - right
		end
		if keysDown.D then
			controlDirection = controlDirection + right
		end
		if keysDown.Space then
			controlDirection = controlDirection + up
		end
		if keysDown.LeftShift then
			controlDirection = controlDirection - up
		end
		
		if controlDirection.Magnitude > 0 then
			controlDirection = controlDirection.Unit * controlForce
			rootPart:ApplyImpulse(controlDirection * rootPart.AssemblyMass * dt)
		end
	end)
end

local function disableZeroGravity()
	if not zeroGravityActive then return end
	
	zeroGravityActive = false
	workspace.Gravity = normalGravity
	
	local character = plr.Character
	if character then
		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
	end
	
	if flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
	
	statusLabel.Text = "Status: OFF | WASD to control"
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
end

buttonOn.MouseButton1Click:Connect(enableZeroGravity)
buttonOff.MouseButton1Click:Connect(disableZeroGravity)

UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.W then
		keysDown.W = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysDown.A = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysDown.S = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysDown.D = true
	elseif input.KeyCode == Enum.KeyCode.Space then
		keysDown.Space = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		keysDown.LeftShift = true
	end
end)

UIS.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.W then
		keysDown.W = false
	elseif input.KeyCode == Enum.KeyCode.A then
		keysDown.A = false
	elseif input.KeyCode == Enum.KeyCode.S then
		keysDown.S = false
	elseif input.KeyCode == Enum.KeyCode.D then
		keysDown.D = false
	elseif input.KeyCode == Enum.KeyCode.Space then
		keysDown.Space = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		keysDown.LeftShift = false
	end
end)

plr.CharacterAdded:Connect(function()
	if zeroGravityActive then
		disableZeroGravity()
	end
end)
