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

local function getCamera()
	return workspace.CurrentCamera
end

local aimEnabled = false
local unlockMouseEnabled = false

local cameraFOVWhenAiming = 55
local aimSensitivityPercent = 30
local aimAssistFOVPixels = 260
local aimAssistStrengthPercent = 90
local maxTargetDistance = 1500
local teamCheckEnabled = false
local targetPartName = "Head"

local savedFOV = nil
local savedSensitivity = nil

local function clamp01(v)
	if v < 0 then
		return 0
	end
	if v > 1 then
		return 1
	end
	return v
end

local function applyMouseBehavior()
	if unlockMouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		return
	end
	if aimEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

local function applyAimSettings()
	local cam = getCamera()
	if not cam then
		return
	end
	local targetSensitivity = math.clamp(aimSensitivityPercent / 100, 0.05, 5)
	if aimEnabled then
		if savedFOV == nil then
			savedFOV = cam.FieldOfView
		end
		if savedSensitivity == nil then
			savedSensitivity = UserInputService.MouseDeltaSensitivity
		end
		cam.FieldOfView = cameraFOVWhenAiming
		UserInputService.MouseDeltaSensitivity = targetSensitivity
	else
		if savedFOV ~= nil then
			cam.FieldOfView = savedFOV
		end
		if savedSensitivity ~= nil then
			UserInputService.MouseDeltaSensitivity = savedSensitivity
		end
		savedFOV = nil
		savedSensitivity = nil
	end
end

local function setAim(state)
	aimEnabled = state == true
	applyAimSettings()
	applyMouseBehavior()
end

local function toggleAim()
	setAim(not aimEnabled)
end

local function setUnlockMouse(state)
	unlockMouseEnabled = state == true
	applyMouseBehavior()
end

local function toggleUnlockMouse()
	setUnlockMouse(not unlockMouseEnabled)
end

local function getTargetPart(character)
	if not character then
		return nil
	end
	local part = character:FindFirstChild(targetPartName)
	if part and part:IsA("BasePart") then
		return part
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function isValidTarget(plr)
	if not plr then
		return false
	end
	if plr == LocalPlayer then
		return false
	end
	if teamCheckEnabled then
		if LocalPlayer.Team ~= nil and plr.Team ~= nil and LocalPlayer.Team == plr.Team then
			return false
		end
	end
	local char = plr.Character
	if not char then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	if hum.Health <= 0 then
		return false
	end
	local part = getTargetPart(char)
	if not part then
		return false
	end
	return true
end

local function getScreenCenter(cam)
	local vp = cam.ViewportSize
	return Vector2.new(vp.X * 0.5, vp.Y * 0.5)
end

local function getBestTarget(cam)
	local center = getScreenCenter(cam)
	local bestPlayer = nil
	local bestPart = nil
	local bestDist = nil

	for _, plr in ipairs(Players:GetPlayers()) do
		if isValidTarget(plr) then
			local char = plr.Character
			local part = getTargetPart(char)
			if part then
				local dist3d = (part.Position - cam.CFrame.Position).Magnitude
				if dist3d <= maxTargetDistance then
					local vpos, onScreen = cam:WorldToViewportPoint(part.Position)
					if onScreen then
						local d2 = (Vector2.new(vpos.X, vpos.Y) - center).Magnitude
						if d2 <= aimAssistFOVPixels then
							if bestDist == nil or d2 < bestDist then
								bestDist = d2
								bestPlayer = plr
								bestPart = part
							end
						end
					end
				end
			end
		end
	end

	return bestPlayer, bestPart
end

local currentTargetPlayer = nil
local currentTargetPart = nil

local function targetStillGood(cam)
	if not currentTargetPlayer or not currentTargetPart then
		return false
	end
	if not isValidTarget(currentTargetPlayer) then
		return false
	end
	local vpos, onScreen = cam:WorldToViewportPoint(currentTargetPart.Position)
	if not onScreen then
		return false
	end
	local d3 = (currentTargetPart.Position - cam.CFrame.Position).Magnitude
	if d3 > maxTargetDistance then
		return false
	end
	local center = getScreenCenter(cam)
	local d2 = (Vector2.new(vpos.X, vpos.Y) - center).Magnitude
	if d2 > aimAssistFOVPixels then
		return false
	end
	return true
end

local function aimAtTarget(cam, part)
	local strength = clamp01(aimAssistStrengthPercent / 100)
	local desired = CFrame.new(cam.CFrame.Position, part.Position)
	cam.CFrame = cam.CFrame:Lerp(desired, strength)
end

local MainTab = Window:CreateTab("Main", 4483362458)
MainTab:CreateSection("Combat")

MainTab:CreateToggle({
	Name = "Aim",
	CurrentValue = false,
	Flag = "AimToggle",
	Callback = function(Value)
		setAim(Value)
	end
})

MainTab:CreateKeybind({
	Name = "Aim Bind",
	CurrentKeybind = "Q",
	HoldToInteract = false,
	Flag = "AimBind",
	Callback = function()
		toggleAim()
	end
})

MainTab:CreateSlider({
	Name = "Aim Assist FOV",
	Range = {80, 650},
	Increment = 5,
	Suffix = "px",
	CurrentValue = aimAssistFOVPixels,
	Flag = "AimAssistFOV",
	Callback = function(Value)
		aimAssistFOVPixels = Value
	end
})

MainTab:CreateSlider({
	Name = "Aim Strength",
	Range = {10, 100},
	Increment = 1,
	Suffix = "%",
	CurrentValue = aimAssistStrengthPercent,
	Flag = "AimStrength",
	Callback = function(Value)
		aimAssistStrengthPercent = Value
	end
})

MainTab:CreateSlider({
	Name = "Aim Distance",
	Range = {150, 4000},
	Increment = 25,
	Suffix = "studs",
	CurrentValue = maxTargetDistance,
	Flag = "AimDistance",
	Callback = function(Value)
		maxTargetDistance = Value
	end
})

MainTab:CreateSlider({
	Name = "Camera FOV (Aim)",
	Range = {40, 80},
	Increment = 1,
	Suffix = "",
	CurrentValue = cameraFOVWhenAiming,
	Flag = "CameraFOVAim",
	Callback = function(Value)
		cameraFOVWhenAiming = Value
		if aimEnabled then
			applyAimSettings()
		end
	end
})

MainTab:CreateSlider({
	Name = "Aim Sensitivity",
	Range = {10, 200},
	Increment = 1,
	Suffix = "%",
	CurrentValue = aimSensitivityPercent,
	Flag = "AimSensitivity",
	Callback = function(Value)
		aimSensitivityPercent = Value
		if aimEnabled then
			applyAimSettings()
		end
	end
})

MainTab:CreateDropdown({
	Name = "Target Part",
	Options = {"Head", "HumanoidRootPart", "Torso", "UpperTorso"},
	CurrentOption = {targetPartName},
	MultipleOptions = false,
	Flag = "TargetPart",
	Callback = function(Option)
		if type(Option) == "table" then
			local first = Option[1]
			if type(first) == "string" then
				targetPartName = first
				currentTargetPlayer = nil
				currentTargetPart = nil
			end
		end
	end
})

MainTab:CreateToggle({
	Name = "Team Check",
	CurrentValue = false,
	Flag = "TeamCheck",
	Callback = function(Value)
		teamCheckEnabled = Value == true
		currentTargetPlayer = nil
		currentTargetPart = nil
	end
})

local killAllEnabled = false
MainTab:CreateToggle({
	Name = "Kill All",
	CurrentValue = false,
	Flag = "KillAll",
	Callback = function(Value)
		killAllEnabled = Value
		if Value then
			task.spawn(function()
				local map = workspace:WaitForChild("Map")
				local orangePart = map:WaitForChild("orange"):WaitForChild("Part")
				while killAllEnabled do
					local character = LocalPlayer.Character
					if character then
						local gunServer = character:FindFirstChild("_.GunServer")
						if gunServer then
							local shootRemote = gunServer:FindFirstChild("Shoot")
							if shootRemote then
								local cam = workspace.CurrentCamera
								for _, plr in ipairs(Players:GetPlayers()) do
									if plr ~= LocalPlayer and isValidTarget(plr) then
										local targetChar = plr.Character
										if targetChar then
											local targetPart = getTargetPart(targetChar)
											if targetPart and cam then
												local shootPos = cam.CFrame.Position
												local hitPos = targetPart.Position
												local direction = (hitPos - shootPos).Unit
												local args = {
													[1] = tick(),
													[2] = shootPos,
													[3] = direction,
													[4] = orangePart,
													[5] = hitPos,
													[6] = Vector3.yAxis,
													[7] = {
														["StatTrak"] = false,
														["Rarity"] = 0,
														["SubType"] = "AWP",
														["Kills"] = 0,
														["Name"] = "AWP",
														["GunStats"] = {
															["HeadShotDamage"] = 105,
															["Heat"] = 0,
															["Ammo"] = 5,
															["Range"] = 15000,
															["FireRate"] = 1,
															["ReloadTime1"] = 1.4,
															["Damage"] = 105,
															["Auto"] = false,
															["Scope"] = {
																[1] = 30,
																[2] = 10
															},
															["CurrentAmmo"] = 4,
															["EquipTime"] = 0.85,
															["ViewModelOffset"] = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
															["MaxHeat"] = 1,
															["Bloom"] = {
																["MinBloom"] = 0,
																["Snappiness"] = 0.8,
																["MaxBloom"] = 10,
																["StableSpeed"] = 0.2
															},
															["HeatIncrease"] = 1,
															["ReloadTime2"] = 1.3,
															["Recoil"] = {
																["RecoilX"] = 7,
																["Snappiness"] = 0.5,
																["RecoilY"] = 2,
																["ReturnSpeed"] = 0.1,
																["RecoilZ"] = 5
															}
														},
														["Float"] = 0,
														["Base"] = "AWP",
														["Serial"] = "{ff9cbafc-7562-4b13-b4c3-bf5f84c026a3}",
														["Pattern"] = 0
													},
													[12] = "Primary"
												}
												for i = 1, 100 do
													shootRemote:FireServer(unpack(args))
												end
											end
										end
									end
								end
							end
						end
					end
					RunService.Heartbeat:Wait()
				end
			end)
		end
	end
})

MainTab:CreateSection("Input")

MainTab:CreateToggle({
	Name = "Unlock Mouse",
	CurrentValue = false,
	Flag = "UnlockMouse",
	Callback = function(Value)
		setUnlockMouse(Value)
	end
})

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		toggleUnlockMouse()
	end
end)

RunService.RenderStepped:Connect(function()
	local cam = getCamera()
	if not cam then
		return
	end

	if aimEnabled then
		if not targetStillGood(cam) then
			currentTargetPlayer, currentTargetPart = getBestTarget(cam)
		end
		if currentTargetPart then
			aimAtTarget(cam, currentTargetPart)
		end
	end

	applyMouseBehavior()
end)

applyMouseBehavior()
