pcall(function()
	local CG = game:GetService("CoreGui")
	for _, v in ipairs(CG:GetChildren()) do
		if v.Name == "Rayfield" then v:Destroy() end
	end
	local plr = game:GetService("Players").LocalPlayer
	if plr and plr:FindFirstChild("PlayerGui") then
		for _, p in ipairs(plr.PlayerGui:GetChildren()) do
			if p.Name == "Rayfield" then p:Destroy() end
		end
	end
end)

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

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
	FlyEnabled = false,
	FlySpeed = 250,
	LimpStrength = 200,
	FollowMouse = true,

	PhantomEnabled = false,
	JitterRadius = 8,
	JitterRate = 30,
	PhantomAccumulator = 0,

	SpinEnabled = false,
	SpinSpeed = 400,
	SpinX = false,
	SpinY = true,
	SpinZ = false,

	IsFlying = false,
	IsPhantom = false,
	IsSpinning = false,

	FlyConn = nil,
	PhantomConn = nil,
	SpinConn = nil,

	CharConn = nil,
	DiedConn = nil,

	FlyAnim = nil,
	FlyTrack = nil,
	FlyStateTick = 0,
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

local function getAnimator(char, hum)
	if not char or not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then return animator end
	local ok, result = pcall(function()
		return hum:WaitForChild("Animator", 2)
	end)
	if ok and result then return result end
	local ok2, created = pcall(function()
		local a = Instance.new("Animator")
		a.Parent = hum
		return a
	end)
	if ok2 then return created end
	return nil
end

local function disconnectFly()
	if State.FlyConn then
		State.FlyConn:Disconnect()
		State.FlyConn = nil
	end
end

local function disconnectPhantom()
	if State.PhantomConn then
		State.PhantomConn:Disconnect()
		State.PhantomConn = nil
	end
end

local function disconnectSpin()
	if State.SpinConn then
		State.SpinConn:Disconnect()
		State.SpinConn = nil
	end
end

local function stopFlyAnim()
	if State.FlyTrack then
		pcall(function()
			State.FlyTrack:Stop()
			State.FlyTrack:Destroy()
		end)
		State.FlyTrack = nil
	end
	if State.FlyAnim then
		pcall(function()
			State.FlyAnim:Destroy()
		end)
		State.FlyAnim = nil
	end
end

local function getFlyTarget(hrp)
	if State.FollowMouse then
		local mouse = getMouse()
		if mouse and mouse.Hit then
			return mouse.Hit.Position
		end
		if mouse then
			local ray = mouse.UnitRay
			return ray.Origin + ray.Direction * 200
		end
	end
	if Camera then
		return Camera.CFrame.Position + Camera.CFrame.LookVector * 60
	end
	return hrp.Position + Vector3.new(0, 5, 0)
end

local function disableFly()
	disconnectFly()
	stopFlyAnim()
	local _, hrp, hum = getCharacter()
	if hum then
		pcall(function()
			hum.PlatformStand = false
			hum.AutoRotate = true
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end
	if hrp then
		pcall(function()
			if not State.IsSpinning then
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
		end)
	end
	State.IsFlying = false
end

local function enableFly()
	if State.IsFlying then return end
	local char, hrp, hum = getCharacter()
	if not char or not hrp or not hum then return end
	if hum.Health <= 0 then return end

	local animator = getAnimator(char, hum)

	pcall(function()
		hum.AutoRotate = false
		hum.PlatformStand = true
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	stopFlyAnim()
	if animator then
		local fallbackIds = { "rbxassetid://507771019", "rbxassetid://507776043" }
		for _, animId in ipairs(fallbackIds) do
			local ok = pcall(function()
				local anim = Instance.new("Animation")
				anim.AnimationId = animId
				local track = animator:LoadAnimation(anim)
				if not track or track.Length <= 0 then
					anim:Destroy()
					if track then track:Destroy() end
					error("zero length")
				end
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Action4
				track:Play(0)
				track:AdjustSpeed(0.1)
				State.FlyAnim = anim
				State.FlyTrack = track
			end)
			if ok and State.FlyTrack then break end
		end
	end

	State.IsFlying = true
	State.FlyStateTick = 0

	State.FlyConn = RunService.Heartbeat:Connect(function(dt)
		local c, h, hu = getCharacter()
		if not c or not h or not hu then
			disableFly()
			return
		end
		if hu.Health <= 0 then
			return
		end

		State.FlyStateTick = State.FlyStateTick + 1
		if State.FlyStateTick >= 10 then
			State.FlyStateTick = 0
			pcall(function()
				if hu:GetState() ~= Enum.HumanoidStateType.Physics then
					hu:ChangeState(Enum.HumanoidStateType.Physics)
				end
				if not hu.PlatformStand then
					hu.PlatformStand = true
				end
			end)
		end

		local target = getFlyTarget(h)
		local dir = target - h.Position
		local dist = dir.Magnitude
		local v
		if dist < 1 then
			v = Vector3.zero
		else
			v = dir.Unit * math.min(State.FlySpeed, dist * 5)
		end

		pcall(function()
			h.AssemblyLinearVelocity = v + Vector3.new(0, Workspace.Gravity, 0)
			if not State.IsSpinning then
				local L = State.LimpStrength
				h.AssemblyAngularVelocity = Vector3.new(
					(math.random(-100, 100) / 100) * L,
					(math.random(-100, 100) / 100) * L,
					(math.random(-100, 100) / 100) * L
				)
			end
		end)
	end)
end

local function enablePhantom()
	if State.IsPhantom then return end
	State.IsPhantom = true
	State.PhantomAccumulator = 0

	State.PhantomConn = RunService.Heartbeat:Connect(function(dt)
		local _, hrp = getCharacter()
		if not hrp then return end

		State.PhantomAccumulator = State.PhantomAccumulator + dt
		local rate = math.max(1, math.min(30, State.JitterRate))
		local period = 1 / rate
		local radius = State.JitterRadius

		while State.PhantomAccumulator >= period do
			local jx = (math.random() * 2 - 1) * radius
			local jy = (math.random() * 2 - 1) * radius * 0.4
			local jz = (math.random() * 2 - 1) * radius
			pcall(function()
				-- replicated via HRP network ownership; visible as flickering to other clients
				hrp.CFrame = hrp.CFrame + Vector3.new(jx, jy, jz)
			end)
			State.PhantomAccumulator = State.PhantomAccumulator - period
		end
	end)
end

local function disablePhantom()
	disconnectPhantom()
	State.IsPhantom = false
	State.PhantomAccumulator = 0
end

local function enableSpin()
	if State.IsSpinning then return end
	State.IsSpinning = true

	State.SpinConn = RunService.Heartbeat:Connect(function()
		local _, hrp = getCharacter()
		if not hrp then return end
		local s = State.SpinSpeed
		local vec = Vector3.new(
			State.SpinX and s or 0,
			State.SpinY and s or 0,
			State.SpinZ and s or 0
		)
		pcall(function()
			hrp.AssemblyAngularVelocity = vec
		end)
	end)
end

local function disableSpin()
	disconnectSpin()
	State.IsSpinning = false
	local _, hrp = getCharacter()
	if hrp then
		pcall(function()
			hrp.AssemblyAngularVelocity = Vector3.zero
		end)
	end
end

local function fullReset()
	disableFly()
	disablePhantom()
	disableSpin()
	State.FlyEnabled = false
	State.PhantomEnabled = false
	State.SpinEnabled = false
	local _, hrp, hum = getCharacter()
	if hrp then
		pcall(function()
			hrp.AssemblyAngularVelocity = Vector3.zero
			hrp.AssemblyLinearVelocity = Vector3.zero
		end)
	end
	if hum then
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end
end

local function bindCharacter(char)
	disconnectFly()
	disconnectPhantom()
	disconnectSpin()
	stopFlyAnim()
	State.IsFlying = false
	State.IsPhantom = false
	State.IsSpinning = false

	if State.DiedConn then
		State.DiedConn:Disconnect()
		State.DiedConn = nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		State.DiedConn = hum.Died:Connect(function()
			disconnectFly()
			disconnectPhantom()
			disconnectSpin()
			stopFlyAnim()
			State.IsFlying = false
			State.IsPhantom = false
			State.IsSpinning = false
		end)
	end

	task.wait(0.5)

	if State.FlyEnabled then
		enableFly()
	end
	if State.PhantomEnabled then
		enablePhantom()
	end
	if State.SpinEnabled then
		enableSpin()
	end
end

if LocalPlayer.Character then
	task.spawn(function()
		bindCharacter(LocalPlayer.Character)
	end)
end

State.CharConn = LocalPlayer.CharacterAdded:Connect(function(char)
	bindCharacter(char)
end)

local Tab = Window:CreateTab("Chaos", 4483362458)

Tab:CreateSection("🪂 Ragdoll Fly")

Tab:CreateToggle({
	Name = "Enabled",
	CurrentValue = false,
	Flag = "ChaosEffects_FlyEnabled",
	Callback = function(Value)
		State.FlyEnabled = Value
		if Value then
			enableFly()
		else
			disableFly()
		end
	end
})

Tab:CreateSlider({
	Name = "Fly Speed",
	Range = {5, 500},
	Increment = 5,
	Suffix = "",
	CurrentValue = 250,
	Flag = "ChaosEffects_FlySpeed",
	Callback = function(Value)
		State.FlySpeed = Value
	end
})

Tab:CreateSlider({
	Name = "Limp Strength",
	Range = {0, 500},
	Increment = 10,
	Suffix = "",
	CurrentValue = 200,
	Flag = "ChaosEffects_LimpStrength",
	Callback = function(Value)
		State.LimpStrength = Value
	end
})

Tab:CreateToggle({
	Name = "Follow Mouse",
	CurrentValue = true,
	Flag = "ChaosEffects_FollowMouse",
	Callback = function(Value)
		State.FollowMouse = Value
	end
})

Tab:CreateKeybind({
	Name = "Toggle Fly",
	CurrentKeybind = "None",
	HoldToInteract = false,
	Flag = "ChaosEffects_ToggleFlyKey",
	Callback = function()
		State.FlyEnabled = not State.FlyEnabled
		if State.FlyEnabled then
			enableFly()
		else
			disableFly()
		end
	end
})

Tab:CreateSection("👻 Phantom")

Tab:CreateToggle({
	Name = "Enabled",
	CurrentValue = false,
	Flag = "ChaosEffects_PhantomEnabled",
	Callback = function(Value)
		State.PhantomEnabled = Value
		if Value then
			enablePhantom()
		else
			disablePhantom()
		end
	end
})

Tab:CreateSlider({
	Name = "Jitter Radius",
	Range = {1, 25},
	Increment = 1,
	Suffix = "",
	CurrentValue = 8,
	Flag = "ChaosEffects_JitterRadius",
	Callback = function(Value)
		State.JitterRadius = Value
	end
})

Tab:CreateSlider({
	Name = "Jitter Rate",
	Range = {5, 30},
	Increment = 1,
	Suffix = "",
	CurrentValue = 30,
	Flag = "ChaosEffects_JitterRate",
	Callback = function(Value)
		State.JitterRate = Value
	end
})

Tab:CreateSection("🚁 Spinbot")

Tab:CreateToggle({
	Name = "Enabled",
	CurrentValue = false,
	Flag = "ChaosEffects_SpinEnabled",
	Callback = function(Value)
		State.SpinEnabled = Value
		if Value then
			enableSpin()
		else
			disableSpin()
		end
	end
})

Tab:CreateSlider({
	Name = "Spin Speed",
	Range = {10, 1000},
	Increment = 10,
	Suffix = "",
	CurrentValue = 400,
	Flag = "ChaosEffects_SpinSpeed",
	Callback = function(Value)
		State.SpinSpeed = Value
	end
})

Tab:CreateToggle({
	Name = "Spin X",
	CurrentValue = false,
	Flag = "ChaosEffects_SpinX",
	Callback = function(Value)
		State.SpinX = Value
	end
})

Tab:CreateToggle({
	Name = "Spin Y",
	CurrentValue = true,
	Flag = "ChaosEffects_SpinY",
	Callback = function(Value)
		State.SpinY = Value
	end
})

Tab:CreateToggle({
	Name = "Spin Z",
	CurrentValue = false,
	Flag = "ChaosEffects_SpinZ",
	Callback = function(Value)
		State.SpinZ = Value
	end
})

Tab:CreateSection("⚙️ General")

Tab:CreateButton({
	Name = "Reset Character",
	Callback = function()
		fullReset()
	end
})
