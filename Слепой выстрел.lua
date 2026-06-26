local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

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

local TabMain = Window:CreateTab("Main", 4483362458)
local TabCombat = Window:CreateTab("Combat & Misc", 4483362458)

local followConn
local savedAutoRotate
local aimTargetPart
local aimTargetAttachment
local aimIK
local aimMotor
local aimMotorPrevTransform
local bodySideOffset = -1.25
local armSideOffset = -2.2
local followOn = false
local autoFollowEnabled = false
local targetAimEnabled = false
local targetAimPlayer = nil
local targetAimRange = 60
local followAutoToggle
local targetAimToggle
local targetAimDropdown
local teleportDropdown
local teleportTarget
local moveSpeed = 16
local jumpPower = 50
local matchCounterEnabled = false
local matchCounterGui = nil
local matchCounterLabel = nil
local matchCounterContainer = nil
local antiTeleportEnabled = false
local lastSafeCFrame
local antiTeleportGrace = 0
local flyEnabled = false
local flySpeed = 80
local flyConn
local flyGyro
local flyVelocity
local noclipEnabled = false
local noclipConn
local autoWalkCenter = Vector3.new(0, -2, -10)
local autoWalkRadius = 22
local autoWalkStopDistance = 35
local autoWalkAngle = 0
local toggleGuard = false
local aimCameraEnabled = false
local swimEnabled = false
local swimSpeed = 45
local swimConn
local swimVelocity
local autoPlayEnabled = false
local autoPlayConn
local autoPlayFallback = Vector3.new(3, 3, 66)
local bigSpawnEnabled = false
local bigSpawnParts = {}
local baseplateOriginalSize
local baseplateOriginalCFrame
local moneyDrainEnabled = false
local moneyDrainConn
local espOn = false
local espColor = Color3.fromRGB(255, 0, 0)
local espObjects = {}
local lastPlayerCount = 0

local function getChar()
	local c = LocalPlayer.Character
	if not c then return nil end
	local h = c:FindFirstChildOfClass("Humanoid")
	local r = c:FindFirstChild("HumanoidRootPart")
	if not h or not r then return nil end
	return c, h, r
end

local function getCandidates()
	local c, h, r = getChar()
	if not c then return nil end
	local rp = r.Position
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local pc = p.Character
			local phrp = pc and pc:FindFirstChild("HumanoidRootPart")
			local ph = pc and pc:FindFirstChildOfClass("Humanoid")
			if pc and phrp and ph and ph.Health > 0 then
				local vec = phrp.Position - rp
				local dist = vec.Magnitude
				if dist > 0.01 then
					table.insert(list, {
						Player = p,
						Char = pc,
						HRP = phrp,
						Dist = dist,
						Dir = vec.Unit
					})
				end
			end
		end
	end
	return list
end

local function getBestTargetRoot()
	local candidates = getCandidates()
	if not candidates or #candidates == 0 then return nil end
	local cosThresh = 0.985
	local minGap = 2
	local bestHRP = nil
	local bestScore = math.huge
	for i = 1, #candidates do
		local a = candidates[i]
		local stackedFront = false
		for j = 1, #candidates do
			if i ~= j then
				local b = candidates[j]
				if a.Dir:Dot(b.Dir) >= cosThresh and b.Dist > (a.Dist + minGap) then
					stackedFront = true
					break
				end
			end
		end
		local score = a.Dist
		if stackedFront then
			score = score * 0.6
		end
		if score < bestScore then
			bestScore = score
			bestHRP = a.HRP
		end
	end
	return bestHRP
end

local function getPlayerOptions()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			table.insert(list, p.Name)
		end
	end
	table.sort(list)
	return list
end

local function findPlayerByName(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name == name then
			return p
		end
	end
	return nil
end

local function getChaoPart()
	local chao = workspace:FindFirstChild("chao", true)
	if not chao then return nil end
	if chao:IsA("BasePart") then return chao end
	if chao:IsA("Model") then
		if chao.PrimaryPart and chao.PrimaryPart:IsA("BasePart") then
			return chao.PrimaryPart
		end
		for _, inst in ipairs(chao:GetDescendants()) do
			if inst:IsA("BasePart") then
				return inst
			end
		end
	end
	return nil
end

local function isOnChao(position)
	local chaoPart = getChaoPart()
	if not chaoPart then return false end
	local relative = chaoPart.CFrame:PointToObjectSpace(position)
	local size = chaoPart.Size * 0.5 + Vector3.new(1, 1, 1)
	return math.abs(relative.X) <= size.X and math.abs(relative.Y) <= size.Y and math.abs(relative.Z) <= size.Z
end

local function countPlayersOnChao()
	local count = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and isOnChao(hrp.Position) then
			count = count + 1
		end
	end
	return count
end

local function ensureMatchCounterGui()
	if matchCounterGui and matchCounterGui.Parent then return end
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	
	matchCounterGui = Instance.new("ScreenGui")
	matchCounterGui.Name = "MatchCounterGui"
	matchCounterGui.ResetOnSpawn = false
	matchCounterGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	matchCounterGui.Parent = pg
	
	matchCounterContainer = Instance.new("Frame")
	matchCounterContainer.Size = UDim2.new(0, 200, 0, 50)
	matchCounterContainer.Position = UDim2.new(0.5, 0, 0, 70)
	matchCounterContainer.AnchorPoint = Vector2.new(0.5, 0)
	matchCounterContainer.BackgroundTransparency = 1
	matchCounterContainer.Parent = matchCounterGui
	
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = matchCounterContainer
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(100, 150, 255)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Transparency = 0.2
	stroke.Parent = frame
	
	matchCounterLabel = Instance.new("TextLabel")
	matchCounterLabel.Size = UDim2.new(1, 0, 1, 0)
	matchCounterLabel.BackgroundTransparency = 1
	matchCounterLabel.Font = Enum.Font.GothamBold
	matchCounterLabel.TextSize = 20
	matchCounterLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	matchCounterLabel.TextStrokeTransparency = 0.5
	matchCounterLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	matchCounterLabel.Text = "Players: 0"
	matchCounterLabel.Parent = frame
	
	local pulseTween = TweenService:Create(
		stroke,
		TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{Transparency = 0.6}
	)
	pulseTween:Play()
end

local function destroyMatchCounterGui()
	if matchCounterGui then
		matchCounterGui:Destroy()
	end
	matchCounterGui = nil
	matchCounterLabel = nil
	matchCounterContainer = nil
end

local function updateMatchCounter()
	if not matchCounterEnabled then return end
	ensureMatchCounterGui()
	if not matchCounterLabel then return end
	local playersOnChao = countPlayersOnChao()
	matchCounterLabel.Text = "On Platform: " .. tostring(playersOnChao)
	if playersOnChao ~= lastPlayerCount then
		lastPlayerCount = playersOnChao
		if matchCounterContainer then
			local scaleTween = TweenService:Create(
				matchCounterContainer,
				TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{Size = UDim2.new(0, 220, 0, 55)}
			)
			scaleTween:Play()
			scaleTween.Completed:Connect(function()
				local scaleBack = TweenService:Create(
					matchCounterContainer,
					TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In),
					{Size = UDim2.new(0, 200, 0, 50)}
				)
				scaleBack:Play()
			end)
		end
	end
end

local function setRootCFrame(cf, grace)
	local c, h, r = getChar()
	if not c or not h or not r then return end
	r.CFrame = cf
	lastSafeCFrame = cf
	antiTeleportGrace = math.max(antiTeleportGrace, grace or 2)
end

local function updateAntiTeleport()
	local c, h, r = getChar()
	if not c or not h or not r then return end
	if not lastSafeCFrame then
		lastSafeCFrame = r.CFrame
		return
	end
	if antiTeleportGrace > 0 then
		antiTeleportGrace = antiTeleportGrace - 1
		lastSafeCFrame = r.CFrame
		return
	end
	local delta = (r.Position - lastSafeCFrame.Position).Magnitude
	if delta > 12 then
		r.CFrame = lastSafeCFrame
		return
	end
	lastSafeCFrame = r.CFrame
end

local function refreshDropdownOptions()
	local opts = getPlayerOptions()
	if targetAimDropdown and targetAimDropdown.Refresh then
		targetAimDropdown:Refresh(opts, true)
	end
	if teleportDropdown and teleportDropdown.Refresh then
		teleportDropdown:Refresh(opts, true)
	end
end

local function setToggleState(toggle, state)
	if toggle and toggle.Set then
		if toggleGuard then return end
		toggleGuard = true
		pcall(function()
			toggle:Set(state)
		end)
		toggleGuard = false
	end
end

local function applyMovementStats()
	local _, h = getChar()
	if h then
		h.WalkSpeed = moveSpeed
		h.JumpPower = jumpPower
	end
end

local function updateFollowState()
	if autoFollowEnabled or targetAimEnabled then
		if not followOn then
			startFollow()
		end
	else
		stopFollow()
	end
end

local function disableTargetAimAndFallback()
	targetAimEnabled = false
	targetAimPlayer = nil
	setToggleState(targetAimToggle, false)
	autoFollowEnabled = true
	setToggleState(followAutoToggle, true)
	updateFollowState()
end

local function resolveTargetRoot()
	local c, h, r = getChar()
	if not c or not r or not h then return nil end
	if targetAimEnabled and targetAimPlayer then
		local tChar = targetAimPlayer.Character
		local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
		local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
		if tChar and tHum and tRoot and tHum.Health > 0 then
			local dist = (r.Position - tRoot.Position).Magnitude
			if dist <= targetAimRange then
				return tRoot
			end
		end
		disableTargetAimAndFallback()
	end
	if autoFollowEnabled then
		return getBestTargetRoot()
	end
	return nil
end

local function stopRightArmAim()
	if aimIK and aimIK.Parent then aimIK:Destroy() end
	aimIK = nil
	if aimTargetPart and aimTargetPart.Parent then aimTargetPart:Destroy() end
	aimTargetPart = nil
	aimTargetAttachment = nil
	if aimMotor then
		pcall(function() aimMotor.Transform = aimMotorPrevTransform or CFrame.new() end)
	end
	aimMotor = nil
	aimMotorPrevTransform = nil
end

local function setupRightArmAim()
	stopRightArmAim()
	local c, h = getChar()
	if not c or not h then return end
	aimTargetPart = Instance.new("Part")
	aimTargetPart.Anchored = true
	aimTargetPart.CanCollide = false
	aimTargetPart.Transparency = 1
	aimTargetPart.Size = Vector3.new(0.2, 0.2, 0.2)
	aimTargetPart.Name = "AimTarget"
	aimTargetPart.Parent = workspace
	aimTargetAttachment = Instance.new("Attachment")
	aimTargetAttachment.Name = "AimAttachment"
	aimTargetAttachment.Parent = aimTargetPart
	if h.RigType == Enum.HumanoidRigType.R15 then
		local rua = c:FindFirstChild("RightUpperArm", true)
		local rh = c:FindFirstChild("RightHand", true)
		if rua and rh then
			aimIK = Instance.new("IKControl")
			aimIK.Type = Enum.IKControlType.LookAt
			aimIK.EndEffector = rh
			aimIK.ChainRoot = rua
			aimIK.Target = aimTargetAttachment
			aimIK.Weight = 1
			pcall(function() aimIK.SmoothTime = 0.05 end)
			aimIK.Enabled = true
			aimIK.Parent = h
		end
	else
		local torso = c:FindFirstChild("Torso")
		if torso then
			local m = torso:FindFirstChild("Right Shoulder") or torso:FindFirstChild("RightShoulder")
			if m and m:IsA("Motor6D") then
				aimMotor = m
				aimMotorPrevTransform = aimMotor.Transform
			end
		end
	end
end

local function updateRightArmAim(aimPos)
	if aimTargetPart then aimTargetPart.CFrame = CFrame.new(aimPos) end
	if aimMotor and aimMotor.Part0 and aimMotor.Part1 then
		local jointWorld = aimMotor.Part0.CFrame * aimMotor.C0
		local dirWorld = aimPos - jointWorld.Position
		if dirWorld.Magnitude > 1e-4 then
			local localDir = jointWorld:VectorToObjectSpace(dirWorld.Unit)
			local fromVec = Vector3.new(0, -1, 0)
			local dot = math.clamp(fromVec:Dot(localDir), -1, 1)
			local angle = math.acos(dot)
			local axis = fromVec:Cross(localDir)
			if axis.Magnitude > 1e-5 and angle == angle then
				aimMotor.Transform = CFrame.fromAxisAngle(axis.Unit, angle)
			else
				aimMotor.Transform = CFrame.new()
			end
		else
			aimMotor.Transform = CFrame.new()
		end
	end
end

function stopFollow()
	if followConn then followConn:Disconnect() followConn = nil end
	followOn = false
	local c, h = getChar()
	if h and savedAutoRotate ~= nil then h.AutoRotate = savedAutoRotate end
	savedAutoRotate = nil
	stopRightArmAim()
end

function startFollow()
	stopFollow()
	local c, h = getChar()
	if h then
		savedAutoRotate = h.AutoRotate
		h.AutoRotate = false
	end
	setupRightArmAim()
	followConn = RunService.Heartbeat:Connect(function()
		if not followOn then return end
		local c2, h2, r2 = getChar()
		if not c2 or not h2 or not r2 then return end
		local targetRoot = resolveTargetRoot()
		if not targetRoot then
			h2:Move(Vector3.new(0, 0, 0), false)
			return
		end
		local rp = r2.Position
		local tp = targetRoot.Position
		local targetFlat = Vector3.new(tp.X, rp.Y, tp.Z)
		local dir = targetFlat - rp
		local dist = dir.Magnitude
		if dist > 0.001 then
			local u = dir.Unit
			local right = Vector3.new(-u.Z, 0, u.X)
			local lookPoint = targetFlat + right * bodySideOffset
			r2.CFrame = CFrame.new(rp, lookPoint)
			local aimPos = Vector3.new(tp.X, tp.Y + 1.5, tp.Z) + right * armSideOffset
			updateRightArmAim(aimPos)
			if aimCameraEnabled then
				Camera.CFrame = CFrame.new(Camera.CFrame.Position, aimPos)
			end
			if dist > 3 then
				h2:Move(u, false)
			else
				h2:Move(Vector3.new(0, 0, 0), false)
			end
		else
			h2:Move(Vector3.new(0, 0, 0), false)
		end
	end)
	followOn = true
end

local function stopFly()
	if flyConn then flyConn:Disconnect() flyConn = nil end
	if flyGyro and flyGyro.Parent then flyGyro:Destroy() end
	if flyVelocity and flyVelocity.Parent then flyVelocity:Destroy() end
	flyGyro = nil
	flyVelocity = nil
end

local function startFly()
	stopFly()
	local c, h, r = getChar()
	if not c or not h or not r then return end
	flyGyro = Instance.new("BodyGyro")
	flyGyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
	flyGyro.P = 1e5
	flyGyro.CFrame = Camera.CFrame
	flyGyro.Parent = r
	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.MaxForce = Vector3.new(1e6, 1e6, 1e6)
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = r
	flyConn = RunService.Heartbeat:Connect(function()
		local c2, h2, r2 = getChar()
		if not c2 or not h2 or not r2 or not flyGyro or not flyVelocity then return end
		flyGyro.CFrame = Camera.CFrame
		local moveDir = h2.MoveDirection
		local vertical = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			vertical = vertical + 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
			vertical = vertical - 1
		end
		local vel = Vector3.new(moveDir.X, vertical, moveDir.Z)
		if vel.Magnitude > 0 then
			vel = vel.Unit * flySpeed
		end
		flyVelocity.Velocity = vel
		h2:ChangeState(Enum.HumanoidStateType.Physics)
	end)
end

local function stopNoclip()
	if noclipConn then noclipConn:Disconnect() noclipConn = nil end
end

local function startNoclip()
	stopNoclip()
	noclipConn = RunService.Stepped:Connect(function()
		local c = LocalPlayer.Character
		if not c then return end
		for _, part in ipairs(c:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)
end

local autoVoteEnabled = false
local selectedVoteMode = "Solo"

TabCombat:CreateSection("Auto Vote")
TabCombat:CreateDropdown({
	Name = "Vote Mode",
	Options = {"Solo", "GunnerRNG", "RedVsBlue"},
	CurrentOption = {"Solo"},
	MultipleOptions = false,
	Flag = "VoteDropdown",
	Callback = function(Option)
		selectedVoteMode = Option[1]
	end,
})

TabCombat:CreateToggle({
	Name = "Enable Auto Vote",
	CurrentValue = false,
	Flag = "AutoVote",
	Callback = function(v)
		autoVoteEnabled = v
	end,
})

task.spawn(function()
	while true do
		if autoVoteEnabled then
			pcall(function()
				local remote = ReplicatedStorage:FindFirstChild("SubmitVote")
				if remote then
					remote:FireServer(selectedVoteMode)
				end
			end)
		end
		task.wait(1)
	end
end)

local gunEspEnabled = false
local gunBeams = {}

local function createLaser(identifier)
	local beamPart = Instance.new("Part")
	beamPart.Name = "LaserBeam_" .. tostring(identifier)
	beamPart.Transparency = 1
	beamPart.CanCollide = false
	beamPart.Anchored = true
	beamPart.Size = Vector3.new(0.1, 0.1, 0.1)
	beamPart.Parent = workspace
	local att0 = Instance.new("Attachment")
	att0.Parent = beamPart
	local att1 = Instance.new("Attachment")
	att1.Parent = beamPart
	local beam = Instance.new("Beam")
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0))
	beam.Width0 = 0.15
	beam.Width1 = 0.15
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Parent = beamPart
	return {Part = beamPart, Beam = beam, A0 = att0, A1 = att1}
end

local function cleanupGunBeam(key)
	if gunBeams[key] then
		if gunBeams[key].Part then gunBeams[key].Part:Destroy() end
		gunBeams[key] = nil
	end
end

local function cleanupAllGunBeams()
	for key, data in pairs(gunBeams) do
		if data.Part then data.Part:Destroy() end
		gunBeams[key] = nil
	end
end

local function gatherWeapons(character)
	local weapons = {}
	for _, inst in ipairs(character:GetDescendants()) do
		if inst.Name:match("^Skin") then
			local origin = inst:FindFirstChild("Part", true)
			local target = inst:FindFirstChild("TargetPart", true)
			if origin and target and origin:IsA("BasePart") and target:IsA("BasePart") then
				table.insert(weapons, {Container = inst, Origin = origin, Target = target})
			end
		end
	end
	return weapons
end

RunService.RenderStepped:Connect(function()
	if not gunEspEnabled then
		cleanupAllGunBeams()
		return
	end

	local active = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then
			for _, weapon in ipairs(gatherWeapons(char)) do
				local key = weapon.Container
				active[key] = true
				if not gunBeams[key] then
					gunBeams[key] = createLaser(key:GetDebugId())
				end
				local data = gunBeams[key]
				local offset = Vector3.new(0, 0.5, 0)
				data.A0.WorldPosition = weapon.Origin.Position + offset
				data.A1.WorldPosition = weapon.Target.Position + offset
			end
		end
	end

	for key, data in pairs(gunBeams) do
		if not active[key] then
			if data.Part then data.Part:Destroy() end
			gunBeams[key] = nil
		end
	end
end)

TabCombat:CreateSection("Visuals")
TabCombat:CreateToggle({
	Name = "Gun Trace ESP",
	CurrentValue = false,
	Flag = "GunESP",
	Callback = function(v)
		gunEspEnabled = v
		if not v then cleanupAllGunBeams() end
	end
})

local shiftLockFeatureEnabled = false
local shiftLockActive = false
local slConn = nil

TabCombat:CreateSection("Movement")
TabCombat:CreateToggle({
	Name = "Enable Shift Lock (Press Shift)",
	CurrentValue = false,
	Flag = "ShiftLock",
	Callback = function(v)
		shiftLockFeatureEnabled = v
		if not v then
			shiftLockActive = false
			if slConn then slConn:Disconnect() slConn = nil end
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
})

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not shiftLockFeatureEnabled then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		shiftLockActive = not shiftLockActive
		if shiftLockActive then
			if slConn then slConn:Disconnect() end
			slConn = RunService.RenderStepped:Connect(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				local _, _, r = getChar()
				if r then
					local lookVec = Camera.CFrame.LookVector
					r.CFrame = CFrame.new(r.Position, r.Position + Vector3.new(lookVec.X, 0, lookVec.Z))
				end
			end)
		else
			if slConn then slConn:Disconnect() slConn = nil end
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end)

TabCombat:CreateSlider({
	Name = "Speed",
	Range = {10, 200},
	Increment = 1,
	Suffix = "WalkSpeed",
	CurrentValue = moveSpeed,
	Flag = "SpeedSlider",
	Callback = function(v)
		moveSpeed = v
		applyMovementStats()
	end
})

TabCombat:CreateSlider({
	Name = "Jump Power",
	Range = {20, 200},
	Increment = 1,
	Suffix = "Power",
	CurrentValue = jumpPower,
	Flag = "JumpPowerSlider",
	Callback = function(v)
		jumpPower = v
		applyMovementStats()
	end
})

TabCombat:CreateToggle({
	Name = "Fly",
	CurrentValue = false,
	Flag = "FlyToggle",
	Callback = function(v)
		flyEnabled = v
		if v then
			startFly()
		else
			stopFly()
		end
	end
})

TabCombat:CreateSlider({
	Name = "Fly Speed",
	Range = {20, 200},
	Increment = 5,
	Suffix = "Speed",
	CurrentValue = flySpeed,
	Flag = "FlySpeed",
	Callback = function(v)
		flySpeed = v
	end
})

TabCombat:CreateToggle({
	Name = "Noclip",
	CurrentValue = false,
	Flag = "Noclip",
	Callback = function(v)
		noclipEnabled = v
		if v then
			startNoclip()
		else
			stopNoclip()
		end
	end
})

local autoWalkEnabled = false

local function stopSwim()
	if swimConn then swimConn:Disconnect() swimConn = nil end
	if swimVelocity and swimVelocity.Parent then swimVelocity:Destroy() end
	swimVelocity = nil
end

local function startSwim()
	stopSwim()
	local c, h, r = getChar()
	if not c or not h or not r then return end
	swimVelocity = Instance.new("BodyVelocity")
	swimVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	swimVelocity.Velocity = Vector3.zero
	swimVelocity.Parent = r
	swimConn = RunService.Heartbeat:Connect(function()
		local c2, h2, r2 = getChar()
		if not c2 or not h2 or not r2 or not swimVelocity then return end
		local moveDir = h2.MoveDirection
		local vertical = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			vertical = vertical + 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
			vertical = vertical - 1
		end
		local vel = Vector3.new(moveDir.X, vertical, moveDir.Z)
		if vel.Magnitude > 0 then
			vel = vel.Unit * swimSpeed
		end
		swimVelocity.Velocity = vel
		h2:ChangeState(Enum.HumanoidStateType.Swimming)
	end)
end

TabCombat:CreateToggle({
	Name = "Auto Walk",
	CurrentValue = false,
	Flag = "AutoWalk",
	Callback = function(v)
		autoWalkEnabled = v
	end
})

TabCombat:CreateToggle({
	Name = "Swim",
	CurrentValue = false,
	Flag = "SwimToggle",
	Callback = function(v)
		swimEnabled = v
		if v then
			startSwim()
		else
			stopSwim()
		end
	end
})

RunService.Heartbeat:Connect(function(dt)
	if not autoWalkEnabled then return end
	local c, h, r = getChar()
	if not c or not r or not h then return end
	local flatCenter = Vector3.new(autoWalkCenter.X, 0, autoWalkCenter.Z)
	local flatPos = Vector3.new(r.Position.X, 0, r.Position.Z)
	local centerDist = (flatPos - flatCenter).Magnitude
	if centerDist > autoWalkStopDistance then
		h:Move(Vector3.new(0, 0, 0), false)
		return
	end
	autoWalkAngle = autoWalkAngle + (dt * 1.5)
	local targetPos = autoWalkCenter + Vector3.new(math.cos(autoWalkAngle), 0, math.sin(autoWalkAngle)) * autoWalkRadius
	local dir = Vector3.new(targetPos.X - r.Position.X, 0, targetPos.Z - r.Position.Z)
	if dir.Magnitude > 0.5 then
		h:Move(dir.Unit, false)
	else
		autoWalkAngle = autoWalkAngle + math.pi * 0.5
	end
end)

local function makeHighlight()
	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.25
	hl.OutlineTransparency = 0
	hl.FillColor = espColor
	hl.OutlineColor = espColor
	return hl
end

local function clearESP()
	for p, obj in pairs(espObjects) do
		if obj.Highlight and obj.Highlight.Parent then obj.Highlight:Destroy() end
		espObjects[p] = nil
	end
end

local function refreshESPColors()
	for _, obj in pairs(espObjects) do
		if obj.Highlight then
			obj.Highlight.FillColor = espColor
			obj.Highlight.OutlineColor = espColor
		end
	end
end

TabMain:CreateSection("Follow System")

targetAimDropdown = TabMain:CreateDropdown({
	Name = "Target Aim Player",
	Options = getPlayerOptions(),
	CurrentOption = {},
	MultipleOptions = false,
	Flag = "TargetAimPlayer",
	Callback = function(Option)
		local choice = Option[1]
		targetAimPlayer = findPlayerByName(choice)
		if targetAimEnabled and not targetAimPlayer then
			targetAimEnabled = false
			setToggleState(targetAimToggle, false)
			updateFollowState()
		end
	end
})

targetAimToggle = TabMain:CreateToggle({
	Name = "Target Aim",
	CurrentValue = false,
	Flag = "TargetAim",
	Callback = function(v)
		if toggleGuard then return end
		if v and not targetAimPlayer then
			setToggleState(targetAimToggle, false)
			return
		end
		targetAimEnabled = v
		if v then
			autoFollowEnabled = false
			setToggleState(followAutoToggle, false)
		end
		updateFollowState()
	end
})

TabMain:CreateToggle({
	Name = "Aim Camera",
	CurrentValue = false,
	Flag = "AimCamera",
	Callback = function(v)
		aimCameraEnabled = v
	end
})

followAutoToggle = TabMain:CreateToggle({
	Name = "Auto Follow Nearest Player",
	CurrentValue = false,
	Flag = "AutoFollowNearest",
	Callback = function(v)
		if toggleGuard then return end
		autoFollowEnabled = v
		if v and targetAimEnabled then
			targetAimEnabled = false
			setToggleState(targetAimToggle, false)
		end
		updateFollowState()
	end
})

TabMain:CreateSection("Match Info")

TabMain:CreateToggle({
	Name = "Match Counter",
	CurrentValue = false,
	Flag = "MatchCounter",
	Callback = function(v)
		matchCounterEnabled = v
		if not v then
			destroyMatchCounterGui()
		else
			updateMatchCounter()
		end
	end
})

TabMain:CreateToggle({
	Name = "Anti Teleport",
	CurrentValue = false,
	Flag = "AntiTeleport",
	Callback = function(v)
		antiTeleportEnabled = v
		if not v then
			antiTeleportGrace = 0
		end
	end
})

TabMain:CreateSection("Utility")

TabMain:CreateButton({
	Name = "Complete obby",
	Callback = function()
		local c, h, r = getChar()
		if not c or not h or not r then return end
		setRootCFrame(CFrame.new(73, 65, 118), 3)
	end
})

TabMain:CreateButton({
	Name = "Complete obby V2",
	Callback = function()
		local trophy = workspace:FindFirstChild("Trophy")
		local c, h, r = getChar()
		if not trophy or not c or not h or not r then return end
		local basePart
		if trophy:IsA("BasePart") then
			basePart = trophy
		elseif trophy:IsA("Model") then
			basePart = trophy.PrimaryPart
			if not basePart then
				basePart = trophy:FindFirstChildWhichIsA("BasePart", true)
			end
		end
		if not basePart then return end
		local originalCFrame = basePart.CFrame
		local originalPrimary = trophy:IsA("Model") and trophy.PrimaryPart or nil
		if trophy:IsA("Model") and not trophy.PrimaryPart then
			trophy.PrimaryPart = basePart
		end
		if trophy:IsA("BasePart") then
			trophy.CFrame = CFrame.new(r.Position + Vector3.new(0, 3, 0))
		else
			trophy:SetPrimaryPartCFrame(CFrame.new(r.Position + Vector3.new(0, 3, 0)))
		end
		task.delay(3, function()
			if not trophy or not trophy.Parent then return end
			if basePart and basePart.Parent and trophy:IsA("Model") then
				if not trophy.PrimaryPart then
					trophy.PrimaryPart = basePart
				end
				trophy:SetPrimaryPartCFrame(originalCFrame)
				trophy.PrimaryPart = originalPrimary
			elseif trophy:IsA("BasePart") then
				trophy.CFrame = originalCFrame
			end
		end)
	end
})

teleportDropdown = TabMain:CreateDropdown({
	Name = "Teleport Target",
	Options = getPlayerOptions(),
	CurrentOption = {},
	MultipleOptions = false,
	Flag = "TeleportTarget",
	Callback = function(Option)
		local choice = Option[1]
		teleportTarget = findPlayerByName(choice)
	end
})

TabMain:CreateButton({
	Name = "Teleport to Player",
	Callback = function()
		local c, h, r = getChar()
		if not c or not h or not r then return end
		if teleportTarget and teleportTarget.Character then
			local tRoot = teleportTarget.Character:FindFirstChild("HumanoidRootPart")
			if tRoot then
				setRootCFrame(CFrame.new(tRoot.Position + Vector3.new(0, 3, 0)), 3)
			end
		end
	end
})

TabMain:CreateSection("Visuals")

TabMain:CreateToggle({
	Name = "Player ESP",
	CurrentValue = false,
	Flag = "PlayerESP",
	Callback = function(v)
		espOn = v
		if not v then clearESP() end
	end
})

TabMain:CreateColorPicker({
	Name = "ESP Color",
	Color = espColor,
	Flag = "ESPColor",
	Callback = function(c)
		espColor = c
		refreshESPColors()
	end
})

RunService.Heartbeat:Connect(function()
	if espOn then
		local validPlayers = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Parent then
				local c = p.Character
				if c and c.Parent then
					local hum = c:FindFirstChildOfClass("Humanoid")
					local hrp = c:FindFirstChild("HumanoidRootPart")
					if hum and hrp then
						validPlayers[p] = true
						local obj = espObjects[p]
						if not obj then
							obj = {}
							espObjects[p] = obj
						end
						
						if not obj.Highlight or not obj.Highlight.Parent then
							obj.Highlight = makeHighlight()
							obj.Highlight.Parent = workspace
						end
						obj.Highlight.Adornee = c
						obj.Highlight.FillColor = espColor
						obj.Highlight.OutlineColor = espColor
					else
						local obj = espObjects[p]
						if obj then
							if obj.Highlight and obj.Highlight.Parent then obj.Highlight:Destroy() end
							espObjects[p] = nil
						end
					end
				end
			end
		end
		
		for p, obj in pairs(espObjects) do
			if not p.Parent or not validPlayers[p] then
				if obj.Highlight and obj.Highlight.Parent then obj.Highlight:Destroy() end
				espObjects[p] = nil
			end
		end
	else
		if next(espObjects) ~= nil then clearESP() end
	end
end)

RunService.Heartbeat:Connect(function()
	if matchCounterEnabled then
		updateMatchCounter()
	end
	if antiTeleportEnabled then
		updateAntiTeleport()
	else
		local c, h, r = getChar()
		if c and h and r then
			lastSafeCFrame = r.CFrame
			antiTeleportGrace = 0
		end
	end
end)

local function stopAutoPlay()
	if autoPlayConn then autoPlayConn:Disconnect() autoPlayConn = nil end
end

local function startAutoPlay()
	stopAutoPlay()
	autoPlayConn = RunService.Heartbeat:Connect(function()
		local c, h, r = getChar()
		if not c or not h or not r then return end
		local targetPart = workspace:FindFirstChild("InvisibleWalls")
		if targetPart then
			targetPart = targetPart:FindFirstChild("Ceiling")
		end
		if targetPart and targetPart:IsA("BasePart") then
			local pos = targetPart.Position + Vector3.new(0, targetPart.Size.Y * 0.5 + 6, 0)
			setRootCFrame(CFrame.new(pos), 3)
		else
			setRootCFrame(CFrame.new(autoPlayFallback), 3)
		end
	end)
end

local function stopMoneyDrain()
	if moneyDrainConn then moneyDrainConn:Disconnect() moneyDrainConn = nil end
end

local function startMoneyDrain()
	stopMoneyDrain()
	moneyDrainConn = RunService.RenderStepped:Connect(function()
		if not moneyDrainEnabled then return end
		local remote = ReplicatedStorage:FindFirstChild("Forcefield")
		if remote and remote.FireServer then
			for _ = 1, 100 do
				pcall(function()
					remote:FireServer()
				end)
			end
		end
	end)
end

TabMain:CreateToggle({
	Name = "Auto Play",
	CurrentValue = false,
	Flag = "AutoPlay",
	Callback = function(v)
		autoPlayEnabled = v
		if v then
			startAutoPlay()
		else
			stopAutoPlay()
		end
	end
})

TabMain:CreateSection("Balance Control")

TabMain:CreateToggle({
	Name = "GOD MODE (Warning: balance decreases)",
	CurrentValue = false,
	Flag = "MoneyDrain",
	Callback = function(v)
		moneyDrainEnabled = v
		if v then
			Rayfield:Notify({
				Title = "Money Drain Enabled",
				Content = "Balance will decrease while this is on.",
				Duration = 6,
				Image = 4483362458
			})
			startMoneyDrain()
		else
			stopMoneyDrain()
		end
	end
})

local function resetBigSpawn()
	if bigSpawnParts then
		for _, part in pairs(bigSpawnParts) do
			if part and part.Parent then part:Destroy() end
		end
	end
	bigSpawnParts = {}
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplateOriginalSize and baseplateOriginalCFrame then
		baseplate.Size = baseplateOriginalSize
		baseplate.CFrame = baseplateOriginalCFrame
	end
end

local function applyBigSpawn()
	resetBigSpawn()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if not baseplate then return end
	if not baseplateOriginalSize then
		baseplateOriginalSize = baseplate.Size
	end
	if not baseplateOriginalCFrame then
		baseplateOriginalCFrame = baseplate.CFrame
	end
	baseplate.Size = Vector3.new(150, 2046, 110)
	local part1 = Instance.new("Part")
	part1.Anchored = true
	part1.CanCollide = true
	part1.Size = Vector3.new(10.397000312805176, 0.4520000219345093, 16.905000686645508)
	part1.CFrame = CFrame.new(0.296078593, -2.98762679, 7.25533962, 1, 0, 0, 0, 0.945518553, 0.325568557, 0, -0.325568557, 0.945518553)
	part1.Parent = workspace
	local part2 = Instance.new("Part")
	part2.Anchored = true
	part2.CanCollide = true
	part2.Size = Vector3.new(10.372000694274902, 1.0499999523162842, 5.630000114440918)
	part2.CFrame = CFrame.new(0.202190876, -5.5423646, -2.21597338, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	part2.Parent = workspace
	bigSpawnParts[1] = part1
	bigSpawnParts[2] = part2
end

TabMain:CreateToggle({
	Name = "Big Spawn",
	CurrentValue = false,
	Flag = "BigSpawn",
	Callback = function(v)
		bigSpawnEnabled = v
		if v then
			applyBigSpawn()
		else
			resetBigSpawn()
		end
	end
})

LocalPlayer.CharacterAdded:Connect(function()
	applyMovementStats()
	if flyEnabled then startFly() end
	if noclipEnabled then startNoclip() end
	if swimEnabled then startSwim() end
	updateFollowState()
end)

Players.PlayerAdded:Connect(function()
	refreshDropdownOptions()
end)

Players.PlayerRemoving:Connect(function(p)
	if targetAimPlayer == p then
		targetAimPlayer = nil
		if targetAimEnabled then
			disableTargetAimAndFallback()
		end
	end
	if teleportTarget == p then
		teleportTarget = nil
	end
	local obj = espObjects[p]
	if obj then
		if obj.Highlight and obj.Highlight.Parent then obj.Highlight:Destroy() end
		espObjects[p] = nil
	end
	refreshDropdownOptions()
end)

refreshDropdownOptions()
applyMovementStats()
if swimEnabled then startSwim() end
