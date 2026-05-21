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
		FileName = "EmoteRNG"
	},
	Discord = {
		Enabled = false,
		Invite = "",
		RememberJoins = false
	},
	KeySystem = false
})

local TabMain = Window:CreateTab("🎲 Auto Roll", 4483362458)
local TabMovement = Window:CreateTab("🏃 Movement", 4483362458)
local TabVisuals = Window:CreateTab("👁️ Visuals", 4483362458)
local TabTeleport = Window:CreateTab("🌀 Teleport", 4483362458)
local TabMisc = Window:CreateTab("⚙️ Misc", 4483362458)

local autoRollEnabled = false
local autoRollSpeed = 2
local autoRollConn = nil

local flyEnabled = false
local flySpeed = 50
local flyConn = nil
local flyBV = nil
local flyBG = nil

local noclipEnabled = false
local noclipConn = nil

local swimEnabled = false
local swimConn = nil
local swimBV = nil
local swimBG = nil

local espOn = false
local espColor = Color3.fromRGB(255, 0, 0)
local espObjects = {}

local fullbrightEnabled = false
local originalLighting = {}

local noFogEnabled = false
local originalFog = {}

local tpClickEnabled = false
local tpClickKey = Enum.KeyCode.Unknown
local tpClickConn = nil

local antiAfkConn = nil

local teleportTarget = nil
local teleportDropdown = nil

local function getChar()
	local c = LocalPlayer.Character
	if not c then return nil end
	local h = c:FindFirstChildOfClass("Humanoid")
	local r = c:FindFirstChild("HumanoidRootPart")
	if not h or not r then return nil end
	return c, h, r
end

local function startAutoRoll()
	if autoRollConn then autoRollConn:Disconnect() end
	autoRollConn = nil
	
	spawn(function()
		while autoRollEnabled do
			pcall(function()
				local args = {
					[1] = {
						["autoDeleteEnabled"] = false,
						["autoDeleteRarities"] = {}
					}
				}
				ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("RollRequest"):FireServer(unpack(args))
			end)
			wait(autoRollSpeed)
		end
	end)
end

local function stopAutoRoll()
	autoRollEnabled = false
	if autoRollConn then
		autoRollConn:Disconnect()
		autoRollConn = nil
	end
end

TabMain:CreateSection("Auto Roll System")

TabMain:CreateToggle({
	Name = "Auto Roll",
	CurrentValue = false,
	Flag = "AutoRoll",
	Callback = function(v)
		autoRollEnabled = v
		if v then
			startAutoRoll()
		else
			stopAutoRoll()
		end
	end
})

TabMain:CreateSlider({
	Name = "Roll Speed (seconds)",
	Range = {2, 5},
	Increment = 0.5,
	Suffix = "s",
	CurrentValue = 2,
	Flag = "RollSpeed",
	Callback = function(v)
		autoRollSpeed = v
	end
})

TabMain:CreateLabel("Min: 2 sec | Max: 5 sec")

local function startFly()
	if flyConn then flyConn:Disconnect() end
	local c, h, r = getChar()
	if not c or not h or not r then return end
	
	h.PlatformStand = true
	
	if not flyBV or not flyBV.Parent then
		flyBV = Instance.new("BodyVelocity")
		flyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		flyBV.Velocity = Vector3.new(0, 0, 0)
		flyBV.Parent = r
	end
	
	if not flyBG or not flyBG.Parent then
		flyBG = Instance.new("BodyGyro")
		flyBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		flyBG.P = 9e4
		flyBG.Parent = r
	end
	
	flyConn = RunService.Heartbeat:Connect(function()
		local c2, h2, r2 = getChar()
		if not c2 or not h2 or not r2 then return end
		
		local dir = Vector3.new()
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + Camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - Camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
		
		if dir.Magnitude > 0 then
			dir = dir.Unit * flySpeed
		end
		
		if flyBV and flyBV.Parent then flyBV.Velocity = dir end
		if flyBG and flyBG.Parent then flyBG.CFrame = Camera.CFrame end
	end)
end

local function stopFly()
	if flyConn then flyConn:Disconnect() flyConn = nil end
	local c, h, r = getChar()
	if h then h.PlatformStand = false end
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
end

local function startNoclip()
	if noclipConn then noclipConn:Disconnect() end
	noclipConn = RunService.Stepped:Connect(function()
		local c = LocalPlayer.Character
		if c then
			for _, part in ipairs(c:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end
		end
	end)
end

local function stopNoclip()
	if noclipConn then noclipConn:Disconnect() noclipConn = nil end
end

local function startSwim()
	if swimConn then swimConn:Disconnect() end
	local c, h, r = getChar()
	if not c or not h or not r then return end
	
	if not swimBV or not swimBV.Parent then
		swimBV = Instance.new("BodyVelocity")
		swimBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		swimBV.Velocity = Vector3.new(0, 0, 0)
		swimBV.Parent = r
	end
	
	if not swimBG or not swimBG.Parent then
		swimBG = Instance.new("BodyGyro")
		swimBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		swimBG.P = 9e4
		swimBG.Parent = r
	end
	
	swimConn = RunService.Heartbeat:Connect(function()
		local c2, h2, r2 = getChar()
		if not c2 or not h2 or not r2 then return end
		
		local dir = Vector3.new()
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + Camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - Camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
		
		if dir.Magnitude > 0 then
			dir = dir.Unit * flySpeed
		end
		
		if swimBV and swimBV.Parent then swimBV.Velocity = dir end
		if swimBG and swimBG.Parent then swimBG.CFrame = Camera.CFrame end
		
		local anim = h2:FindFirstChildOfClass("Animator")
		if anim then
			for _, track in pairs(anim:GetPlayingAnimationTracks()) do
				if track.Name:lower():find("swim") then
					return
				end
			end
		end
	end)
end

local function stopSwim()
	if swimConn then swimConn:Disconnect() swimConn = nil end
	if swimBV then swimBV:Destroy() swimBV = nil end
	if swimBG then swimBG:Destroy() swimBG = nil end
end

TabMovement:CreateSection("Movement")

TabMovement:CreateToggle({
	Name = "Fly",
	CurrentValue = false,
	Flag = "Fly",
	Callback = function(v)
		flyEnabled = v
		if v then startFly() else stopFly() end
	end
})

TabMovement:CreateSlider({
	Name = "Fly Speed",
	Range = {10, 200},
	Increment = 5,
	Suffix = "",
	CurrentValue = 50,
	Flag = "FlySpeed",
	Callback = function(v)
		flySpeed = v
	end
})

TabMovement:CreateSlider({
	Name = "Walk Speed",
	Range = {16, 200},
	Increment = 1,
	Suffix = "",
	CurrentValue = 16,
	Flag = "WalkSpeed",
	Callback = function(v)
		local c, h = getChar()
		if h then h.WalkSpeed = v end
	end
})

TabMovement:CreateSlider({
	Name = "Jump Power",
	Range = {50, 300},
	Increment = 5,
	Suffix = "",
	CurrentValue = 50,
	Flag = "JumpPower",
	Callback = function(v)
		local c, h = getChar()
		if h then h.JumpPower = v end
	end
})

TabMovement:CreateToggle({
	Name = "Noclip",
	CurrentValue = false,
	Flag = "Noclip",
	Callback = function(v)
		noclipEnabled = v
		if v then startNoclip() else stopNoclip() end
	end
})

TabMovement:CreateToggle({
	Name = "Air Swim",
	CurrentValue = false,
	Flag = "AirSwim",
	Callback = function(v)
		swimEnabled = v
		if v then startSwim() else stopSwim() end
	end
})

local function makeHighlight()
	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.5
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

local function enableFullbright()
	local lighting = game:GetService("Lighting")
	originalLighting.Ambient = lighting.Ambient
	originalLighting.Brightness = lighting.Brightness
	originalLighting.OutdoorAmbient = lighting.OutdoorAmbient
	lighting.Ambient = Color3.fromRGB(255, 255, 255)
	lighting.Brightness = 2
	lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
end

local function disableFullbright()
	local lighting = game:GetService("Lighting")
	if originalLighting.Ambient then lighting.Ambient = originalLighting.Ambient end
	if originalLighting.Brightness then lighting.Brightness = originalLighting.Brightness end
	if originalLighting.OutdoorAmbient then lighting.OutdoorAmbient = originalLighting.OutdoorAmbient end
end

local function enableNoFog()
	local lighting = game:GetService("Lighting")
	originalFog.FogStart = lighting.FogStart
	originalFog.FogEnd = lighting.FogEnd
	lighting.FogStart = 100000
	lighting.FogEnd = 100000
end

local function disableNoFog()
	local lighting = game:GetService("Lighting")
	if originalFog.FogStart then lighting.FogStart = originalFog.FogStart end
	if originalFog.FogEnd then lighting.FogEnd = originalFog.FogEnd end
end

TabVisuals:CreateSection("ESP")

TabVisuals:CreateToggle({
	Name = "Player ESP",
	CurrentValue = false,
	Flag = "PlayerESP",
	Callback = function(v)
		espOn = v
		if not v then clearESP() end
	end
})

TabVisuals:CreateColorPicker({
	Name = "ESP Color",
	Color = espColor,
	Flag = "ESPColor",
	Callback = function(c)
		espColor = c
		refreshESPColors()
	end
})

TabVisuals:CreateSection("World")

TabVisuals:CreateToggle({
	Name = "FullBright",
	CurrentValue = false,
	Flag = "FullBright",
	Callback = function(v)
		fullbrightEnabled = v
		if v then enableFullbright() else disableFullbright() end
	end
})

TabVisuals:CreateToggle({
	Name = "No Fog",
	CurrentValue = false,
	Flag = "NoFog",
	Callback = function(v)
		noFogEnabled = v
		if v then enableNoFog() else disableNoFog() end
	end
})

local function getPlayerOptions()
	local options = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			table.insert(options, p.Name)
		end
	end
	if #options == 0 then table.insert(options, "None") end
	return options
end

local function findPlayerByName(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name == name then return p end
	end
	return nil
end

local function refreshDropdownOptions()
	if teleportDropdown then
		pcall(function()
			teleportDropdown:Set(getPlayerOptions())
		end)
	end
end

TabTeleport:CreateSection("Teleport")

teleportDropdown = TabTeleport:CreateDropdown({
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

TabTeleport:CreateButton({
	Name = "Teleport to Player",
	Callback = function()
		local c, h, r = getChar()
		if not c or not h or not r then return end
		if teleportTarget and teleportTarget.Character then
			local tRoot = teleportTarget.Character:FindFirstChild("HumanoidRootPart")
			if tRoot then
				r.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, 3, 0))
			end
		end
	end
})

TabTeleport:CreateButton({
	Name = "Refresh Players",
	Callback = function()
		refreshDropdownOptions()
		Rayfield:Notify({
			Title = "Players",
			Content = "Player list refreshed!",
			Duration = 2
		})
	end
})

TabTeleport:CreateSection("TP Click")

TabTeleport:CreateKeybind({
	Name = "TP Click Key",
	CurrentKeybind = "None",
	Flag = "TPClickKey",
	Callback = function(key)
		tpClickKey = key
	end
})

TabTeleport:CreateToggle({
	Name = "TP Click Enabled",
	CurrentValue = false,
	Flag = "TPClickEnabled",
	Callback = function(v)
		tpClickEnabled = v
	end
})

TabMisc:CreateSection("Anti AFK")

TabMisc:CreateLabel("Anti AFK is always active")

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

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if tpClickEnabled and input.KeyCode == tpClickKey then
		local mouse = LocalPlayer:GetMouse()
		local c, h, r = getChar()
		if c and h and r and mouse.Hit then
			r.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
		end
	end
end)

local VirtualUser = game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
	VirtualUser:CaptureController()
	VirtualUser:ClickButton2(Vector2.new())
end)

Players.PlayerAdded:Connect(function()
	refreshDropdownOptions()
end)

Players.PlayerRemoving:Connect(function(p)
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

LocalPlayer.CharacterAdded:Connect(function()
	if flyEnabled then startFly() end
	if noclipEnabled then startNoclip() end
	if swimEnabled then startSwim() end
end)

refreshDropdownOptions()

