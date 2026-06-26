local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

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

local TabMain = Window:CreateTab("🍖 Main", 4483362458)
local TabLobby = Window:CreateTab("🎁 Lobby", 4483362458)
local TabPlayer = Window:CreateTab("🚀 Player", 4483362458)
local TabTeleport = Window:CreateTab("🌐 Teleport", 4483362458)
local TabVisuals = Window:CreateTab("👁️ Visuals", 4483362458)
local TabEnvironment = Window:CreateTab("🌙 Environment", 4483362458)

local fastHoldEnabled = false
local promptConn

local function applyPromptSettings(prompt)
	prompt.HoldDuration = 0
end

local function startFastHold()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			applyPromptSettings(inst)
		end
	end
	if promptConn then promptConn:Disconnect() end
	promptConn = workspace.DescendantAdded:Connect(function(inst)
		if fastHoldEnabled and inst:IsA("ProximityPrompt") then
			applyPromptSettings(inst)
		end
	end)
end

local function stopFastHold()
	if promptConn then
		promptConn:Disconnect()
		promptConn = nil
	end
end

local anomalyEspEnabled = false
local anomalyObjects = {}
local anomalyTimer = 0

local function clearAnomalyEsp()
	for container, data in pairs(anomalyObjects) do
		if data.Label then data.Label:Destroy() end
		if data.HL then data.HL:Destroy() end
		anomalyObjects[container] = nil
	end
end

local function getStatusColor(name)
	local lower = string.lower(name or "")
	local hasMan = string.find(lower, "man") ~= nil
	local hasAnom = string.find(lower, "anom") ~= nil
	if hasAnom or not hasMan then
		return "Anomaly", Color3.fromRGB(255, 0, 0)
	end
	return "Save", Color3.fromRGB(0, 255, 0)
end

local function countParts(model)
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function findNpcModel(container)
	if not container then return nil end

	if container:IsA("Model") then
		local hum = container:FindFirstChildOfClass("Humanoid")
		if hum then
			return container
		end
	end

	local best, bestCount = nil, 0
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Model") then
			local hum = d:FindFirstChildOfClass("Humanoid")
			if hum then
				local c = countParts(d)
				if c > bestCount then
					best = d
					bestCount = c
				end
			end
		end
	end

	return best
end

local function getModelRoot(model)
	if not model then return nil end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
	local any = model:FindFirstChildWhichIsA("BasePart", true)
	return any
end

local function cleanupContainer(container)
	local data = anomalyObjects[container]
	if not data then return end
	if data.Label then data.Label:Destroy() end
	if data.HL then data.HL:Destroy() end
	anomalyObjects[container] = nil
end

local function updateAnomalyFor(container)
	if not container or not container.Parent then
		cleanupContainer(container)
		return
	end

	local npc = findNpcModel(container)
	if not npc or not npc.Parent then
		cleanupContainer(container)
		return
	end

	local root = getModelRoot(npc)
	if not root then
		cleanupContainer(container)
		return
	end

	local labelText, color = getStatusColor(container.Name)

	local data = anomalyObjects[container]
	if not data then
		data = {}
		anomalyObjects[container] = data
	end

	if not data.HL then
		local hl = Instance.new("Highlight")
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillTransparency = 0.85
		hl.OutlineTransparency = 0
		hl.Parent = workspace
		data.HL = hl
	end

	data.HL.Adornee = npc
	data.HL.FillColor = color
	data.HL.OutlineColor = color

	if not data.Label then
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, 160, 0, 32)
		gui.AlwaysOnTop = true
		gui.Parent = workspace

		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.new(1, 0, 1, 0)
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.Parent = gui

		data.Label = gui
		data.Text = text
	end

	local _, size = npc:GetBoundingBox()
	data.Label.Adornee = root
	data.Label.StudsOffset = Vector3.new(0, (size.Y * 0.5) + 1.5, 0)
	data.Text.Text = labelText
	data.Text.TextColor3 = color
	data.Text.TextStrokeTransparency = 0.2
end

local function refreshAnomalyEsp()
	local humFolder = workspace:FindFirstChild("Hum")
	local active = {}

	if humFolder then
		for _, child in ipairs(humFolder:GetChildren()) do
			updateAnomalyFor(child)
			if anomalyObjects[child] then
				active[child] = true
			end
		end
	end

	for container, data in pairs(anomalyObjects) do
		if (not humFolder) or (not active[container]) or (not container:IsDescendantOf(humFolder)) then
			if data.Label then data.Label:Destroy() end
			if data.HL then data.HL:Destroy() end
			anomalyObjects[container] = nil
		end
	end
end

local playerEspEnabled = false
local playerEspColor = Color3.fromRGB(0, 255, 255)
local playerEspObjects = {}

local function clearPlayerEsp()
	for p, data in pairs(playerEspObjects) do
		if data.HL and data.HL.Parent then data.HL:Destroy() end
		if data.Label and data.Label.Parent then data.Label:Destroy() end
		playerEspObjects[p] = nil
	end
end

local function updatePlayerEsp()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if char and hum and hum.Health > 0 and root then
				local data = playerEspObjects[p]
				if not data then
					data = {}
					local hl = Instance.new("Highlight")
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.FillTransparency = 0.55
					hl.OutlineTransparency = 0
					hl.Parent = workspace
					data.HL = hl

					local gui = Instance.new("BillboardGui")
					gui.Size = UDim2.new(0, 200, 0, 50)
					gui.AlwaysOnTop = true
					gui.StudsOffset = Vector3.new(0, 3.5, 0)
					gui.Parent = workspace

					local nameLabel = Instance.new("TextLabel")
					nameLabel.BackgroundTransparency = 1
					nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
					nameLabel.Font = Enum.Font.GothamBold
					nameLabel.TextScaled = true
					nameLabel.TextStrokeTransparency = 0
					nameLabel.Parent = gui
					data.NameLabel = nameLabel

					local distLabel = Instance.new("TextLabel")
					distLabel.BackgroundTransparency = 1
					distLabel.Size = UDim2.new(1, 0, 0.5, 0)
					distLabel.Position = UDim2.new(0, 0, 0.5, 0)
					distLabel.Font = Enum.Font.Gotham
					distLabel.TextScaled = true
					distLabel.TextStrokeTransparency = 0
					distLabel.Parent = gui
					data.DistLabel = distLabel

					data.Label = gui
					playerEspObjects[p] = data
				end
				data.HL.Adornee = char
				data.HL.FillColor = playerEspColor
				data.HL.OutlineColor = playerEspColor
				data.Label.Adornee = root
				data.NameLabel.Text = p.Name
				data.NameLabel.TextColor3 = playerEspColor

				local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if myRoot then
					local dist = math.floor((root.Position - myRoot.Position).Magnitude)
					data.DistLabel.Text = "["..dist.." studs]"
					data.DistLabel.TextColor3 = playerEspColor
				end
			else
				local data = playerEspObjects[p]
				if data then
					if data.HL and data.HL.Parent then data.HL:Destroy() end
					if data.Label and data.Label.Parent then data.Label:Destroy() end
					playerEspObjects[p] = nil
				end
			end
		end
	end

	for p, data in pairs(playerEspObjects) do
		if not p.Parent then
			if data.HL and data.HL.Parent then data.HL:Destroy() end
			if data.Label and data.Label.Parent then data.Label:Destroy() end
			playerEspObjects[p] = nil
		end
	end
end

local noFogEnabled = false
local fullbrightEnabled = false

local lightingDefaults = {
	FogEnd = Lighting.FogEnd,
	FogStart = Lighting.FogStart,
	Brightness = Lighting.Brightness,
	ClockTime = Lighting.ClockTime,
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	GlobalShadows = Lighting.GlobalShadows
}

local atmosphereDefaults

local function ensureAtmosphere()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	return atm
end

local function applyNoFog()
	local atm = ensureAtmosphere()
	if not atmosphereDefaults then
		atmosphereDefaults = {
			Density = atm.Density,
			Offset = atm.Offset,
			Color = atm.Color,
			Decay = atm.Decay,
			Glare = atm.Glare,
			Haze = atm.Haze
		}
	end
	Lighting.FogStart = 0
	Lighting.FogEnd = 1e9
	atm.Density = 0
	atm.Offset = 0
	atm.Glare = 0
	atm.Haze = 0
end

local function restoreNoFog()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphereDefaults and atm then
		atm.Density = atmosphereDefaults.Density
		atm.Offset = atmosphereDefaults.Offset
		atm.Color = atmosphereDefaults.Color
		atm.Decay = atmosphereDefaults.Decay
		atm.Glare = atmosphereDefaults.Glare
		atm.Haze = atmosphereDefaults.Haze
	end
	Lighting.FogStart = lightingDefaults.FogStart
	Lighting.FogEnd = lightingDefaults.FogEnd
end

local function applyFullbright()
	Lighting.Brightness = 4
	Lighting.ClockTime = 12
	Lighting.Ambient = Color3.new(1, 1, 1)
	Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
	Lighting.GlobalShadows = false
end

local function restoreFullbright()
	Lighting.Brightness = lightingDefaults.Brightness
	Lighting.ClockTime = lightingDefaults.ClockTime
	Lighting.Ambient = lightingDefaults.Ambient
	Lighting.OutdoorAmbient = lightingDefaults.OutdoorAmbient
	Lighting.GlobalShadows = lightingDefaults.GlobalShadows
end

local skipTutorialEnabled = false
local skipConn

local function fireSkipTutorial()
	local r = ReplicatedStorage:WaitForChild("SkipTutorial", 5)
	if r then
		pcall(function()
			r:FireServer()
		end)
	end
end

local function startSkipTutorial()
	fireSkipTutorial()
	if skipConn then skipConn:Disconnect() end
	skipConn = LocalPlayer.CharacterAdded:Connect(function()
		fireSkipTutorial()
	end)
end

local function stopSkipTutorial()
	if skipConn then
		skipConn:Disconnect()
		skipConn = nil
	end
end

local autoClaimEnabled = false
local autoClaimTimer = 0
local autoClaimIndex = 1

local function claimReward(index)
	pcall(function()
		local remote = ReplicatedStorage:WaitForChild("DailyRewards", 5)
		if remote then
			local claim = remote:WaitForChild("Claim", 5)
			if claim then
				claim:FireServer(index)
			end
		end
	end)
end

local flyEnabled = false
local flySpeed = 50
local flyBodyGyro, flyBodyVel

local function startFly()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return end

	hum.PlatformStand = true

	flyBodyGyro = Instance.new("BodyGyro")
	flyBodyGyro.P = 9e4
	flyBodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	flyBodyGyro.CFrame = root.CFrame
	flyBodyGyro.Parent = root

	flyBodyVel = Instance.new("BodyVelocity")
	flyBodyVel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	flyBodyVel.Velocity = Vector3.zero
	flyBodyVel.Parent = root
end

local function stopFly()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand = false end
	if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
	if flyBodyVel then flyBodyVel:Destroy() flyBodyVel = nil end
end

local function updateFly()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not flyBodyGyro or not flyBodyVel then return end

	local cam = workspace.CurrentCamera
	flyBodyGyro.CFrame = cam.CFrame

	local dir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		dir = dir + cam.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		dir = dir - cam.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		dir = dir - cam.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		dir = dir + cam.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		dir = dir + Vector3.new(0, 1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		dir = dir - Vector3.new(0, 1, 0)
	end

	if dir.Magnitude > 0 then
		flyBodyVel.Velocity = dir.Unit * flySpeed
	else
		flyBodyVel.Velocity = Vector3.zero
	end
end

local noclipEnabled = false
local noclipConn

local function startNoclip()
	if noclipConn then noclipConn:Disconnect() end
	noclipConn = RunService.Stepped:Connect(function()
		local char = LocalPlayer.Character
		if char then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end
		end
	end)
end

local function stopNoclip()
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
end

local swimEnabled = false
local swimConn

local function startSwim()
	if swimConn then swimConn:Disconnect() end
	swimConn = RunService.Heartbeat:Connect(function()
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
			hum:ChangeState(Enum.HumanoidStateType.Swimming)
		end
	end)
end

local function stopSwim()
	if swimConn then
		swimConn:Disconnect()
		swimConn = nil
	end
end

local tpClickEnabled = false
local tpClickBind = Enum.KeyCode.Unknown

local playerList = {}

local function refreshPlayerList()
	playerList = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			table.insert(playerList, p.Name)
		end
	end
	return playerList
end

local function teleportToPlayer(name)
	local target = Players:FindFirstChild(name)
	if target and target.Character then
		local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
		local myChar = LocalPlayer.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if targetRoot and myRoot then
			myRoot.CFrame = targetRoot.CFrame + Vector3.new(0, 3, 0)
		end
	end
end

TabMain:CreateSection("⚡ Game Features")

TabMain:CreateToggle({
	Name = "Skip Tutorial",
	CurrentValue = false,
	Flag = "SkipTutorial",
	Callback = function(v)
		skipTutorialEnabled = v
		if v then
			startSkipTutorial()
		else
			stopSkipTutorial()
		end
	end
})

TabMain:CreateToggle({
	Name = "Fast Hold",
	CurrentValue = false,
	Flag = "FastHold",
	Callback = function(v)
		fastHoldEnabled = v
		if v then
			startFastHold()
		else
			stopFastHold()
		end
	end
})

TabLobby:CreateSection("🎁 Rewards")

TabLobby:CreateToggle({
	Name = "Auto Claim Rewards",
	CurrentValue = false,
	Flag = "AutoClaimRewards",
	Callback = function(v)
		autoClaimEnabled = v
		if v then
			autoClaimTimer = 0
			autoClaimIndex = 1
		end
	end
})

TabPlayer:CreateSection("✈️ Movement")

TabPlayer:CreateToggle({
	Name = "Fly",
	CurrentValue = false,
	Flag = "Fly",
	Callback = function(v)
		flyEnabled = v
		if v then
			startFly()
		else
			stopFly()
		end
	end
})

TabPlayer:CreateSlider({
	Name = "Fly Speed",
	Range = {10, 500},
	Increment = 5,
	Suffix = " studs/s",
	CurrentValue = 50,
	Flag = "FlySpeed",
	Callback = function(v)
		flySpeed = v
	end
})

TabPlayer:CreateSlider({
	Name = "Walk Speed",
	Range = {16, 500},
	Increment = 1,
	Suffix = " studs/s",
	CurrentValue = 16,
	Flag = "WalkSpeed",
	Callback = function(v)
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = v
		end
	end
})

TabPlayer:CreateSlider({
	Name = "Jump Power",
	Range = {50, 500},
	Increment = 5,
	Suffix = " power",
	CurrentValue = 50,
	Flag = "JumpPower",
	Callback = function(v)
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.UseJumpPower = true
			hum.JumpPower = v
		end
	end
})

TabPlayer:CreateSection("🔮 Abilities")

TabPlayer:CreateToggle({
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

TabPlayer:CreateToggle({
	Name = "Air Swim",
	CurrentValue = false,
	Flag = "AirSwim",
	Callback = function(v)
		swimEnabled = v
		if v then
			startSwim()
		else
			stopSwim()
		end
	end
})

TabTeleport:CreateSection("🎯 Teleport Tools")

local selectedPlayer = nil
local playerDropdown

playerDropdown = TabTeleport:CreateDropdown({
	Name = "Select Player",
	Options = refreshPlayerList(),
	CurrentOption = {},
	MultiSelection = false,
	Flag = "SelectedPlayer",
	Callback = function(opt)
		if opt and opt[1] then
			selectedPlayer = opt[1]
		end
	end
})

TabTeleport:CreateButton({
	Name = "Refresh Players",
	Callback = function()
		playerDropdown:Refresh(refreshPlayerList(), true)
	end
})

TabTeleport:CreateButton({
	Name = "Teleport to Player",
	Callback = function()
		if selectedPlayer then
			teleportToPlayer(selectedPlayer)
		end
	end
})

TabTeleport:CreateSection("🖱️ Click Teleport")

TabTeleport:CreateKeybind({
	Name = "TP Click Bind",
	CurrentKeybind = "None",
	HoldToInteract = false,
	Flag = "TPClickBind",
	Callback = function(bind)
		local myChar = LocalPlayer.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if myRoot and Mouse.Hit then
			myRoot.CFrame = Mouse.Hit + Vector3.new(0, 3, 0)
		end
	end
})

TabVisuals:CreateSection("👥 Player ESP")

TabVisuals:CreateToggle({
	Name = "Player ESP",
	CurrentValue = false,
	Flag = "PlayerESP",
	Callback = function(v)
		playerEspEnabled = v
		if not v then
			clearPlayerEsp()
		end
	end
})

TabVisuals:CreateColorPicker({
	Name = "Player ESP Color",
	Color = playerEspColor,
	Flag = "PlayerESPColor",
	Callback = function(c)
		playerEspColor = c
		for _, data in pairs(playerEspObjects) do
			if data.HL then
				data.HL.FillColor = playerEspColor
				data.HL.OutlineColor = playerEspColor
			end
			if data.NameLabel then
				data.NameLabel.TextColor3 = playerEspColor
			end
			if data.DistLabel then
				data.DistLabel.TextColor3 = playerEspColor
			end
		end
	end
})

TabVisuals:CreateSection("👾 Game ESP")

TabVisuals:CreateToggle({
	Name = "Anomaly ESP",
	CurrentValue = false,
	Flag = "AnomalyESP",
	Callback = function(v)
		anomalyEspEnabled = v
		if not v then
			clearAnomalyEsp()
		else
			anomalyTimer = 0
			refreshAnomalyEsp()
		end
	end
})

TabEnvironment:CreateSection("🌫️ Atmosphere")

TabEnvironment:CreateToggle({
	Name = "No Fog",
	CurrentValue = false,
	Flag = "NoFog",
	Callback = function(v)
		noFogEnabled = v
		if v then
			applyNoFog()
		else
			restoreNoFog()
		end
	end
})

TabEnvironment:CreateToggle({
	Name = "Fullbright",
	CurrentValue = false,
	Flag = "Fullbright",
	Callback = function(v)
		fullbrightEnabled = v
		if v then
			applyFullbright()
		else
			restoreFullbright()
		end
	end
})

TabEnvironment:CreateSection("🎨 Custom Lighting")

TabEnvironment:CreateSlider({
	Name = "Time of Day",
	Range = {0, 24},
	Increment = 0.5,
	Suffix = " h",
	CurrentValue = Lighting.ClockTime,
	Flag = "TimeOfDay",
	Callback = function(v)
		if not fullbrightEnabled then
			Lighting.ClockTime = v
		end
	end
})

TabEnvironment:CreateSlider({
	Name = "Brightness",
	Range = {0, 10},
	Increment = 0.5,
	Suffix = "",
	CurrentValue = Lighting.Brightness,
	Flag = "CustomBrightness",
	Callback = function(v)
		if not fullbrightEnabled then
			Lighting.Brightness = v
		end
	end
})

TabEnvironment:CreateColorPicker({
	Name = "Ambient Color",
	Color = Lighting.Ambient,
	Flag = "AmbientColor",
	Callback = function(c)
		if not fullbrightEnabled then
			Lighting.Ambient = c
			Lighting.OutdoorAmbient = c
		end
	end
})

RunService.Heartbeat:Connect(function(dt)
	if anomalyEspEnabled then
		anomalyTimer = anomalyTimer + dt
		if anomalyTimer >= 0.35 then
			anomalyTimer = 0
			refreshAnomalyEsp()
		end
	end

	if playerEspEnabled then
		updatePlayerEsp()
	end

	if fastHoldEnabled then
		for _, inst in ipairs(Players:GetPlayers()) do
			local char = inst.Character
			if char then
				for _, prompt in ipairs(char:GetDescendants()) do
					if prompt:IsA("ProximityPrompt") then
						applyPromptSettings(prompt)
					end
				end
			end
		end
	end

	if flyEnabled then
		updateFly()
	end

	if noFogEnabled then
		applyNoFog()
	end

	if fullbrightEnabled then
		applyFullbright()
	end

	if autoClaimEnabled then
		autoClaimTimer = autoClaimTimer + dt
		if autoClaimTimer >= 1 then
			autoClaimTimer = 0
			claimReward(autoClaimIndex)
			autoClaimIndex = autoClaimIndex + 1
			if autoClaimIndex > 7 then
				autoClaimIndex = 1
			end
		end
	end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid", 5)
	if hum then
		if flyEnabled then
			task.wait(0.5)
			startFly()
		end
	end
end)
