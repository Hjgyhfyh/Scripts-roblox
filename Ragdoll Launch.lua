local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Window = Rayfield:CreateWindow({
	Name = "tg: @sigmatik323",
	LoadingTitle = "tg: @sigmatik323",
	LoadingSubtitle = "by sigmatik323",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "main"
	},
	Discord = {
		Enabled = false,
		Invite = "",
		RememberJoins = false
	},
	KeySystem = false
})

local State = {
	Enabled = false,
	UseMouseClick = false,
	LaunchPower = 1.0,
	FlightTime = 1.2,
	RecoveryDelay = 0.5,
	RagdollJoints = true,
	SpinInAir = true,
	SpinStrength = 15,
	AutoStandUp = true,

	IsFlying = false,
	HeartbeatConn = nil,
	InputConn = nil,
	CharConn = nil,
	DiedConn = nil,

	SavedMotors = {},
	CreatedJointObjects = {},
	SavedCanCollide = {},
}

local function getMouse()
	return LocalPlayer:GetMouse()
end

local function getCharacter()
	local char = LocalPlayer.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return nil end
	return char, hrp, hum
end

local function getMouseTarget()
	local mouse = getMouse()
	local hit = mouse.Hit
	if hit then
		local pos = hit.Position
		local _, hrp = getCharacter()
		if hrp then
			local dist = (pos - hrp.Position).Magnitude
			if dist >= 5 then
				return pos
			end
		else
			return pos
		end
	end
	local ray = mouse.UnitRay
	return ray.Origin + ray.Direction * 100
end

local function computeLaunchVelocity(fromPos, toPos, flightTime, powerMul)
	local g = workspace.Gravity
	local T = math.max(0.1, flightTime)
	local dx = toPos.X - fromPos.X
	local dy = toPos.Y - fromPos.Y
	local dz = toPos.Z - fromPos.Z
	local vx = dx / T
	local vz = dz / T
	local vy = dy / T + 0.5 * g * T
	return Vector3.new(vx, vy, vz) * powerMul
end

local function clearJointObjects()
	for _, obj in ipairs(State.CreatedJointObjects) do
		pcall(function()
			if obj and obj.Parent then
				obj:Destroy()
			end
		end)
	end
	State.CreatedJointObjects = {}
end

local function restoreMotors()
	for _, info in ipairs(State.SavedMotors) do
		local motor = info.Motor
		if motor and motor.Parent then
			pcall(function()
				motor.Enabled = true
			end)
		end
	end
	State.SavedMotors = {}
end

local function restoreCanCollide()
	for part, prev in pairs(State.SavedCanCollide) do
		if part and part.Parent then
			pcall(function()
				part.CanCollide = prev
			end)
		end
	end
	State.SavedCanCollide = {}
end

local function ragdollCharacter(char, hrp)
	clearJointObjects()
	State.SavedMotors = {}
	State.SavedCanCollide = {}

	for _, descendant in ipairs(char:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 and part1 then
				local a0 = Instance.new("Attachment")
				a0.CFrame = descendant.C0
				a0.Parent = part0

				local a1 = Instance.new("Attachment")
				a1.CFrame = descendant.C1
				a1.Parent = part1

				local socket = Instance.new("BallSocketConstraint")
				socket.Attachment0 = a0
				socket.Attachment1 = a1
				socket.LimitsEnabled = true
				socket.TwistLimitsEnabled = false
				socket.UpperAngle = 60
				socket.Parent = part0

				descendant.Enabled = false
				table.insert(State.SavedMotors, { Motor = descendant })
				table.insert(State.CreatedJointObjects, a0)
				table.insert(State.CreatedJointObjects, a1)
				table.insert(State.CreatedJointObjects, socket)
			end
		end
	end

	for _, descendant in ipairs(char:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= hrp then
			State.SavedCanCollide[descendant] = descendant.CanCollide
			pcall(function()
				descendant.CanCollide = true
			end)
		end
	end
end

local function unragdollCharacter()
	clearJointObjects()
	restoreMotors()
	restoreCanCollide()
end

local function disconnectHeartbeat()
	if State.HeartbeatConn then
		State.HeartbeatConn:Disconnect()
		State.HeartbeatConn = nil
	end
end

local function recoverFromFlight()
	disconnectHeartbeat()
	local char, hrp, hum = getCharacter()
	unragdollCharacter()
	if hum then
		pcall(function()
			hum.PlatformStand = false
			hum.AutoRotate = true
		end)
		if hrp then
			pcall(function()
				hrp.AssemblyAngularVelocity = Vector3.zero
			end)
		end
		if State.AutoStandUp then
			pcall(function()
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end)
		else
			pcall(function()
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end)
		end
	end
	State.IsFlying = false
end

local function startLandingWatch(hrp)
	disconnectHeartbeat()
	local startTime = tick()
	local landedAt = nil
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = false
	if hrp.Parent then
		rayParams.FilterDescendantsInstances = { hrp.Parent }
	end

	State.HeartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not State.IsFlying then
			disconnectHeartbeat()
			return
		end
		if not hrp or not hrp.Parent then
			recoverFromFlight()
			return
		end
		local now = tick()
		if now - startTime > 8 then
			recoverFromFlight()
			return
		end

		local origin = hrp.Position
		local direction = Vector3.new(0, -3.5, 0)
		local result = workspace:Raycast(origin, direction, rayParams)

		if result then
			if not landedAt then
				landedAt = now
			elseif now - landedAt >= State.RecoveryDelay then
				recoverFromFlight()
			end
		else
			landedAt = nil
		end
	end)
end

local function performLaunch()
	if not State.Enabled then return end
	if State.IsFlying then return end
	local char, hrp, hum = getCharacter()
	if not char or not hrp or not hum then return end
	if hum.Health <= 0 then return end

	local target = getMouseTarget()
	if not target then return end

	local velocity = computeLaunchVelocity(hrp.Position, target, State.FlightTime, State.LaunchPower)

	State.IsFlying = true

	pcall(function()
		hum.PlatformStand = true
		hum.AutoRotate = false
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	if State.RagdollJoints then
		ragdollCharacter(char, hrp)
	end

	local applied = pcall(function()
		hrp.AssemblyLinearVelocity = velocity
	end)
	if not applied then
		pcall(function()
			local mass = hrp.AssemblyMass or hrp:GetMass() or 1
			hrp:ApplyImpulse(velocity * mass)
		end)
	end

	if State.SpinInAir and State.SpinStrength > 0 then
		local s = State.SpinStrength
		pcall(function()
			hrp.AssemblyAngularVelocity = Vector3.new(
				math.random(-s, s),
				math.random(-s, s),
				math.random(-s, s)
			)
		end)
	end

	startLandingWatch(hrp)
end

local function disconnectInput()
	if State.InputConn then
		State.InputConn:Disconnect()
		State.InputConn = nil
	end
end

local function setupInput()
	disconnectInput()
	State.InputConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if not State.Enabled then return end
		if not State.UseMouseClick then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			performLaunch()
		end
	end)
end

local function resetCharacterState()
	disconnectHeartbeat()
	clearJointObjects()
	State.SavedMotors = {}
	State.SavedCanCollide = {}
	State.IsFlying = false
end

local function bindCharacter(char)
	resetCharacterState()
	if State.DiedConn then
		State.DiedConn:Disconnect()
		State.DiedConn = nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		State.DiedConn = hum.Died:Connect(function()
			disconnectHeartbeat()
			State.IsFlying = false
		end)
	end
end

if LocalPlayer.Character then
	bindCharacter(LocalPlayer.Character)
end

State.CharConn = LocalPlayer.CharacterAdded:Connect(function(char)
	bindCharacter(char)
end)

setupInput()

local Tab = Window:CreateTab("Ragdoll Launch", 4483362458)

Tab:CreateSection("Launch Settings")

Tab:CreateToggle({
	Name = "Enabled",
	CurrentValue = false,
	Flag = "RagdollLaunch_Enabled",
	Callback = function(Value)
		State.Enabled = Value
		if not Value and State.IsFlying then
			recoverFromFlight()
		end
	end
})

Tab:CreateKeybind({
	Name = "Launch Key",
	CurrentKeybind = "None",
	HoldToInteract = false,
	Flag = "RagdollLaunch_Key",
	Callback = function()
		performLaunch()
	end
})

Tab:CreateToggle({
	Name = "Use Mouse Click",
	CurrentValue = false,
	Flag = "RagdollLaunch_UseMouseClick",
	Callback = function(Value)
		State.UseMouseClick = Value
	end
})

Tab:CreateSlider({
	Name = "Launch Power",
	Range = {0.5, 3.0},
	Increment = 0.1,
	Suffix = "x",
	CurrentValue = 1.0,
	Flag = "RagdollLaunch_Power",
	Callback = function(Value)
		State.LaunchPower = Value
	end
})

Tab:CreateSlider({
	Name = "Flight Time",
	Range = {0.5, 3.0},
	Increment = 0.1,
	Suffix = "s",
	CurrentValue = 1.2,
	Flag = "RagdollLaunch_FlightTime",
	Callback = function(Value)
		State.FlightTime = Value
	end
})

Tab:CreateSlider({
	Name = "Recovery Delay",
	Range = {0, 3},
	Increment = 0.1,
	Suffix = "s",
	CurrentValue = 0.5,
	Flag = "RagdollLaunch_RecoveryDelay",
	Callback = function(Value)
		State.RecoveryDelay = Value
	end
})

Tab:CreateSection("Effects")

Tab:CreateToggle({
	Name = "Ragdoll Joints",
	CurrentValue = true,
	Flag = "RagdollLaunch_RagdollJoints",
	Callback = function(Value)
		State.RagdollJoints = Value
	end
})

Tab:CreateToggle({
	Name = "Spin In Air",
	CurrentValue = true,
	Flag = "RagdollLaunch_SpinInAir",
	Callback = function(Value)
		State.SpinInAir = Value
	end
})

Tab:CreateSlider({
	Name = "Spin Strength",
	Range = {0, 50},
	Increment = 1,
	Suffix = "",
	CurrentValue = 15,
	Flag = "RagdollLaunch_SpinStrength",
	Callback = function(Value)
		State.SpinStrength = Value
	end
})

Tab:CreateToggle({
	Name = "Auto Stand Up",
	CurrentValue = true,
	Flag = "RagdollLaunch_AutoStandUp",
	Callback = function(Value)
		State.AutoStandUp = Value
	end
})

Tab:CreateSection("Manual Trigger")

Tab:CreateButton({
	Name = "Launch Now",
	Callback = function()
		local prevEnabled = State.Enabled
		State.Enabled = true
		performLaunch()
		State.Enabled = prevEnabled
	end
})
