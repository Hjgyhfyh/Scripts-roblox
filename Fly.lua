local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
	Name = "tg: @sigmatik323",
	LoadingTitle = "tg: @sigmatik323",
	LoadingSubtitle = "by sigmatik323",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "Hub"
	},
	Discord = {
		Enabled = false,
		Invite = "",
		RememberJoins = false
	},
	KeySystem = false
})

local TabMovement = Window:CreateTab("🏃 Movement", 4483362458)

local player = Players.LocalPlayer
local flyEnabled = false
local flySpeed = 60

local flyConn = nil
local flyGyro = nil
local flyVelocity = nil

local function getRoot()
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	return humanoid, root
end

local function stopFly()
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function startFly()
	stopFly()

	local humanoid, root = getRoot()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	humanoid.PlatformStand = true

	flyGyro = Instance.new("BodyGyro")
	flyGyro.P = 9e4
	flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	flyGyro.CFrame = camera.CFrame
	flyGyro.Parent = root

	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = root

	flyConn = RunService.Heartbeat:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam or not flyGyro or not flyVelocity then
			return
		end

		flyGyro.CFrame = cam.CFrame

		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			dir += cam.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			dir -= cam.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			dir -= cam.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			dir += cam.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			dir += Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			dir -= Vector3.new(0, 1, 0)
		end

		if dir.Magnitude > 0 then
			dir = dir.Unit * flySpeed
		end
		flyVelocity.Velocity = dir
	end)
end

TabMovement:CreateToggle({
	Name = "Fly",
	CurrentValue = false,
	Flag = "FlyToggle",
	Callback = function(Value)
		flyEnabled = Value
		if flyEnabled then
			startFly()
		else
			stopFly()
		end
	end
})

TabMovement:CreateSlider({
	Name = "Fly Speed",
	Range = {20, 150},
	Increment = 1,
	Suffix = "Speed",
	CurrentValue = flySpeed,
	Flag = "FlySpeed",
	Callback = function(Value)
		flySpeed = Value
	end
})

player.CharacterAdded:Connect(function()
	if flyEnabled then
		startFly()
	end
end)
