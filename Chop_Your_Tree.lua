local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
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

-- Вкладки
local TabMain = Window:CreateTab("🎮 Main", 4483362458)
local TabMovement = Window:CreateTab("🏃 Movement", 4483362458)
local TabVisuals = Window:CreateTab("👁 Visuals", 4483362458)
local TabTeleport = Window:CreateTab("🌀 Teleport", 4483362458)

-- ============================================
-- ПЕРЕМЕННЫЕ ДЛЯ AUTO ФУНКЦИЙ
-- ============================================

-- Auto Tap Button
local autoTapEnabled = false
local tapRemote = nil
local tapArgs = nil
local tapConnection = nil
local waitingForTap = false

-- Auto Upgrade LvL
local autoUpgradeEnabled = false
local upgradeRemote = nil
local upgradeArgs = nil
local upgradeConnection = nil
local waitingForUpgrade = false

-- Auto Buy LvL for 3 Watering
local autoBuyWateringEnabled = false
local buyWateringRemote = nil
local buyWateringArgs = nil
local buyWateringConnection = nil
local waitingForBuyWatering = false

-- Auto Swing Axe
local autoSwingEnabled = false
local swingConnection = nil

-- ============================================
-- ПЕРЕМЕННЫЕ ДЛЯ MOVEMENT
-- ============================================
local flyEnabled = false
local flySpeed = 50
local flyConnection = nil
local bodyGyro = nil
local bodyVelocity = nil

local noclipEnabled = false
local noclipConnection = nil

local swimEnabled = false
local swimConnection = nil

local currentSpeed = 16
local currentJumpPower = 50

-- ============================================
-- ПЕРЕМЕННЫЕ ДЛЯ VISUALS
-- ============================================
local noFogEnabled = false
local fullbrightEnabled = false
local originalFogEnd = Lighting.FogEnd
local originalAmbient = Lighting.Ambient
local originalBrightness = Lighting.Brightness

local playerEspEnabled = false
local playerEspColor = Color3.fromRGB(0, 255, 255)
local playerEspObjects = {}

-- ============================================
-- ПЕРЕМЕННЫЕ ДЛЯ TELEPORT
-- ============================================
local tpClickEnabled = false
local tpClickKeybind = nil

-- ============================================
-- HOOK ДЛЯ ПЕРЕХВАТА REMOTE'ОВ
-- ============================================
local oldNamecall
local hookSuccess = false

local function setupRemoteHook()
	local success = pcall(function()
		if hookmetamethod then
			oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
				local method = getnamecallmethod()
				local args = {...}
				
				-- Перехват TapButtonClick
				if waitingForTap and method == "FireServer" and self:IsA("RemoteEvent") and self.Name == "TapButtonClick" then
					tapRemote = self
					tapArgs = args
					waitingForTap = false
					task.spawn(function()
						Rayfield:Notify({
							Title = "Auto Tap Button",
							Content = "Remote запомнен! Начинаю автоматический тап.",
							Duration = 3,
							Image = 4483362458,
						})
						if autoTapEnabled and tapRemote and tapArgs then
							if tapConnection then tapConnection:Disconnect() end
							tapConnection = RunService.Heartbeat:Connect(function()
								if autoTapEnabled and tapRemote and tapArgs then
									pcall(function()
										tapRemote:FireServer(unpack(tapArgs))
									end)
								end
							end)
						end
					end)
				end
				
				-- Перехват TapLevelUp
				if waitingForUpgrade and method == "InvokeServer" and self:IsA("RemoteFunction") and self.Name == "TapLevelUp" then
					upgradeRemote = self
					upgradeArgs = args
					waitingForUpgrade = false
					task.spawn(function()
						Rayfield:Notify({
							Title = "Auto Upgrade LvL",
							Content = "Remote запомнен! Начинаю автоматический апгрейд.",
							Duration = 3,
							Image = 4483362458,
						})
						if autoUpgradeEnabled and upgradeRemote and upgradeArgs then
							if upgradeConnection then upgradeConnection:Disconnect() end
							upgradeConnection = RunService.Heartbeat:Connect(function()
								if autoUpgradeEnabled and upgradeRemote and upgradeArgs then
									pcall(function()
										upgradeRemote:InvokeServer(unpack(upgradeArgs))
									end)
								end
							end)
						end
					end)
				end
				
				-- Перехват BuyBuilding (для Auto Buy LvL for 3 Watering)
				if waitingForBuyWatering and method == "InvokeServer" and self:IsA("RemoteFunction") and self.Name == "BuyBuilding" then
					buyWateringRemote = self
					buyWateringArgs = args
					waitingForBuyWatering = false
					task.spawn(function()
						Rayfield:Notify({
							Title = "Auto Buy LvL for 3 Watering",
							Content = "Remote запомнен! Начинаю автоматическую покупку.",
							Duration = 3,
							Image = 4483362458,
						})
						if autoBuyWateringEnabled and buyWateringRemote and buyWateringArgs then
							if buyWateringConnection then buyWateringConnection:Disconnect() end
							buyWateringConnection = RunService.Heartbeat:Connect(function()
								if autoBuyWateringEnabled and buyWateringRemote and buyWateringArgs then
									pcall(function()
										buyWateringRemote:InvokeServer(unpack(buyWateringArgs))
									end)
								end
							end)
						end
					end)
				end
				
				return oldNamecall(self, ...)
			end)
			hookSuccess = true
		elseif getrawmetatable then
			local mt = getrawmetatable(game)
			local oldNc = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				local method = getnamecallmethod and getnamecallmethod() or ""
				local args = {...}
				
				-- Перехват TapButtonClick
				if waitingForTap and method == "FireServer" and self:IsA("RemoteEvent") and self.Name == "TapButtonClick" then
					tapRemote = self
					tapArgs = args
					waitingForTap = false
					task.spawn(function()
						Rayfield:Notify({
							Title = "Auto Tap Button",
							Content = "Remote запомнен! Начинаю автоматический тап.",
							Duration = 3,
							Image = 4483362458,
						})
						if autoTapEnabled and tapRemote and tapArgs then
							if tapConnection then tapConnection:Disconnect() end
							tapConnection = RunService.Heartbeat:Connect(function()
								if autoTapEnabled and tapRemote and tapArgs then
									pcall(function()
										tapRemote:FireServer(unpack(tapArgs))
									end)
								end
							end)
						end
					end)
				end
				
				-- Перехват TapLevelUp
				if waitingForUpgrade and method == "InvokeServer" and self:IsA("RemoteFunction") and self.Name == "TapLevelUp" then
					upgradeRemote = self
					upgradeArgs = args
					waitingForUpgrade = false
					task.spawn(function()
						Rayfield:Notify({
							Title = "Auto Upgrade LvL",
							Content = "Remote запомнен! Начинаю автоматический апгрейд.",
							Duration = 3,
							Image = 4483362458,
						})
						if autoUpgradeEnabled and upgradeRemote and upgradeArgs then
							if upgradeConnection then upgradeConnection:Disconnect() end
							upgradeConnection = RunService.Heartbeat:Connect(function()
								if autoUpgradeEnabled and upgradeRemote and upgradeArgs then
									pcall(function()
										upgradeRemote:InvokeServer(unpack(upgradeArgs))
									end)
								end
							end)
						end
					end)
				end
				
				-- Перехват BuyBuilding (для Auto Buy LvL for 3 Watering)
				if waitingForBuyWatering and method == "InvokeServer" and self:IsA("RemoteFunction") and self.Name == "BuyBuilding" then
					buyWateringRemote = self
					buyWateringArgs = args
					waitingForBuyWatering = false
					task.spawn(function()
						Rayfield:Notify({
							Title = "Auto Buy LvL for 3 Watering",
							Content = "Remote запомнен! Начинаю автоматическую покупку.",
							Duration = 3,
							Image = 4483362458,
						})
						if autoBuyWateringEnabled and buyWateringRemote and buyWateringArgs then
							if buyWateringConnection then buyWateringConnection:Disconnect() end
							buyWateringConnection = RunService.Heartbeat:Connect(function()
								if autoBuyWateringEnabled and buyWateringRemote and buyWateringArgs then
									pcall(function()
										buyWateringRemote:InvokeServer(unpack(buyWateringArgs))
									end)
								end
							end)
						end
					end)
				end
				
				return oldNc(self, ...)
			end)
			setreadonly(mt, true)
			hookSuccess = true
		end
	end)
end

-- Инициализация hook
setupRemoteHook()

-- ============================================
-- ФУНКЦИИ AUTO TAP BUTTON
-- ============================================
local function startAutoTap()
	if not tapRemote or not tapArgs then
		waitingForTap = true
		Rayfield:Notify({
			Title = "Auto Tap Button",
			Content = "Нажмите 1 раз на кнопку, чтобы запомнить remote.",
			Duration = 5,
			Image = 4483362458,
		})
		return
	end
	
	if tapConnection then tapConnection:Disconnect() end
	tapConnection = RunService.Heartbeat:Connect(function()
		if autoTapEnabled and tapRemote and tapArgs then
			pcall(function()
				tapRemote:FireServer(unpack(tapArgs))
			end)
		end
	end)
end

local function stopAutoTap()
	if tapConnection then
		tapConnection:Disconnect()
		tapConnection = nil
	end
	waitingForTap = false
end

-- ============================================
-- ФУНКЦИИ AUTO UPGRADE LVL
-- ============================================
local function startAutoUpgrade()
	if not upgradeRemote or not upgradeArgs then
		waitingForUpgrade = true
		Rayfield:Notify({
			Title = "Auto Upgrade LvL",
			Content = "Нажмите 1 раз на кнопку апгрейда уровня.",
			Duration = 5,
			Image = 4483362458,
		})
		return
	end
	
	if upgradeConnection then upgradeConnection:Disconnect() end
	upgradeConnection = RunService.Heartbeat:Connect(function()
		if autoUpgradeEnabled and upgradeRemote and upgradeArgs then
			pcall(function()
				upgradeRemote:InvokeServer(unpack(upgradeArgs))
			end)
		end
	end)
end

local function stopAutoUpgrade()
	if upgradeConnection then
		upgradeConnection:Disconnect()
		upgradeConnection = nil
	end
	waitingForUpgrade = false
end

-- ============================================
-- ФУНКЦИИ AUTO BUY LVL FOR 3 WATERING
-- ============================================
local function startAutoBuyWatering()
	if not buyWateringRemote or not buyWateringArgs then
		waitingForBuyWatering = true
		Rayfield:Notify({
			Title = "Auto Buy LvL for 3 Watering",
			Content = "Нажмите 1 раз на кнопку покупки.",
			Duration = 5,
			Image = 4483362458,
		})
		return
	end
	
	if buyWateringConnection then buyWateringConnection:Disconnect() end
	buyWateringConnection = RunService.Heartbeat:Connect(function()
		if autoBuyWateringEnabled and buyWateringRemote and buyWateringArgs then
			pcall(function()
				buyWateringRemote:InvokeServer(unpack(buyWateringArgs))
			end)
		end
	end)
end

local function stopAutoBuyWatering()
	if buyWateringConnection then
		buyWateringConnection:Disconnect()
		buyWateringConnection = nil
	end
	waitingForBuyWatering = false
end

-- ============================================
-- ФУНКЦИИ GET FREE TOTEM
-- ============================================
local function getFreeTotem()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local freeTotemRemote = remotes:FindFirstChild("FreeTotem")
		if freeTotemRemote then
			pcall(function()
				freeTotemRemote:FireServer()
			end)
			Rayfield:Notify({
				Title = "Get Free Totem",
				Content = "FreeTotem вызван!",
				Duration = 2,
				Image = 4483362458,
			})
		else
			Rayfield:Notify({
				Title = "Get Free Totem",
				Content = "Не удалось найти FreeTotem remote.",
				Duration = 3,
				Image = 4483362458,
			})
		end
	end
end

-- ============================================
-- ФУНКЦИИ AUTO SWING AXE
-- ============================================
local function startAutoSwing()
	if swingConnection then swingConnection:Disconnect() end
	
	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local backpack = LocalPlayer:WaitForChild("Backpack", 10)
	
	-- Берем инструмент из 1 слота
	local tool = nil
	if backpack then
		local firstTool = backpack:FindFirstChildOfClass("Tool")
		if firstTool then
			firstTool.Parent = character
			tool = character:FindFirstChildOfClass("Tool")
		end
	end
	if not tool then
		tool = character:FindFirstChildOfClass("Tool")
	end
	
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local axeSwingRemote = remotes and remotes:WaitForChild("AxeSwing", 10)
	
	if not axeSwingRemote then
		Rayfield:Notify({
			Title = "Auto Swing Axe",
			Content = "Не удалось найти AxeSwing remote.",
			Duration = 3,
			Image = 4483362458,
		})
		return
	end
	
	swingConnection = RunService.Heartbeat:Connect(function()
		if autoSwingEnabled then
			pcall(function()
				axeSwingRemote:FireServer()
			end)
		end
	end)
end

local function stopAutoSwing()
	if swingConnection then
		swingConnection:Disconnect()
		swingConnection = nil
	end
end

-- ============================================
-- ФУНКЦИИ FLY
-- ============================================
local function startFly()
	local character = LocalPlayer.Character
	if not character then return end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoidRootPart or not humanoid then return end
	
	-- Создаем BodyGyro и BodyVelocity
	bodyGyro = Instance.new("BodyGyro")
	bodyGyro.P = 9e4
	bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	bodyGyro.CFrame = humanoidRootPart.CFrame
	bodyGyro.Parent = humanoidRootPart
	
	bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Velocity = Vector3.new(0, 0, 0)
	bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bodyVelocity.Parent = humanoidRootPart
	
	humanoid.PlatformStand = true
	
	flyConnection = RunService.Heartbeat:Connect(function()
		if not flyEnabled then return end
		local camera = workspace.CurrentCamera
		local moveDirection = Vector3.new(0, 0, 0)
		
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			moveDirection = moveDirection + camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			moveDirection = moveDirection - camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			moveDirection = moveDirection - camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			moveDirection = moveDirection + camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			moveDirection = moveDirection + Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			moveDirection = moveDirection - Vector3.new(0, 1, 0)
		end
		
		if moveDirection.Magnitude > 0 then
			moveDirection = moveDirection.Unit
		end
		
		bodyVelocity.Velocity = moveDirection * flySpeed
		bodyGyro.CFrame = camera.CFrame
	end)
end

local function stopFly()
	local character = LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
	end
	
	if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
	if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
	if flyConnection then flyConnection:Disconnect() flyConnection = nil end
end

-- ============================================
-- ФУНКЦИИ NOCLIP
-- ============================================
local function startNoclip()
	noclipConnection = RunService.Stepped:Connect(function()
		if not noclipEnabled then return end
		local character = LocalPlayer.Character
		if character then
			for _, part in pairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
				end
			end
		end
	end)
end

local function stopNoclip()
	if noclipConnection then
		noclipConnection:Disconnect()
		noclipConnection = nil
	end
end

-- ============================================
-- ФУНКЦИИ SWIM (по воздуху)
-- ============================================
local function startSwim()
	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
	
	swimConnection = RunService.Heartbeat:Connect(function()
		if swimEnabled and humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
		end
	end)
end

local function stopSwim()
	if swimConnection then
		swimConnection:Disconnect()
		swimConnection = nil
	end
	local character = LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

-- ============================================
-- ФУНКЦИИ SPEED/JUMP
-- ============================================
local function updateSpeed()
	local character = LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = currentSpeed
		end
	end
end

local function updateJumpPower()
	local character = LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.JumpPower = currentJumpPower
		end
	end
end

-- ============================================
-- ФУНКЦИИ VISUALS
-- ============================================
local function applyNoFog()
	originalFogEnd = Lighting.FogEnd
	Lighting.FogEnd = 100000
end

local function restoreNoFog()
	Lighting.FogEnd = originalFogEnd
end

local function applyFullBright()
	originalAmbient = Lighting.Ambient
	originalBrightness = Lighting.Brightness
	Lighting.Ambient = Color3.fromRGB(255, 255, 255)
	Lighting.Brightness = 2
	Lighting.GlobalShadows = false
end

local function restoreFullBright()
	Lighting.Ambient = originalAmbient
	Lighting.Brightness = originalBrightness
	Lighting.GlobalShadows = true
end

-- ============================================
-- ФУНКЦИИ PLAYER ESP
-- ============================================
local function clearPlayerEsp()
	for p, data in pairs(playerEspObjects) do
		if data.Highlight then data.Highlight:Destroy() end
		if data.BillboardGui then data.BillboardGui:Destroy() end
		playerEspObjects[p] = nil
	end
end

local function updatePlayerEsp()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			
			if character and humanoid and humanoid.Health > 0 and rootPart then
				local data = playerEspObjects[player]
				if not data then
					data = {}
					
					-- Highlight
					local highlight = Instance.new("Highlight")
					highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					highlight.FillTransparency = 0.5
					highlight.OutlineTransparency = 0
					highlight.Parent = character
					data.Highlight = highlight
					
					-- BillboardGui для имени
					local billboard = Instance.new("BillboardGui")
					billboard.Size = UDim2.new(0, 100, 0, 40)
					billboard.AlwaysOnTop = true
					billboard.StudsOffset = Vector3.new(0, 3, 0)
					billboard.Adornee = rootPart
					billboard.Parent = character
					
					local nameLabel = Instance.new("TextLabel")
					nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
					nameLabel.BackgroundTransparency = 1
					nameLabel.TextColor3 = playerEspColor
					nameLabel.TextStrokeTransparency = 0
					nameLabel.Font = Enum.Font.GothamBold
					nameLabel.TextScaled = true
					nameLabel.Text = player.Name
					nameLabel.Parent = billboard
					
					local distLabel = Instance.new("TextLabel")
					distLabel.Size = UDim2.new(1, 0, 0.5, 0)
					distLabel.Position = UDim2.new(0, 0, 0.5, 0)
					distLabel.BackgroundTransparency = 1
					distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					distLabel.TextStrokeTransparency = 0
					distLabel.Font = Enum.Font.Gotham
					distLabel.TextScaled = true
					distLabel.Parent = billboard
					
					data.BillboardGui = billboard
					data.NameLabel = nameLabel
					data.DistLabel = distLabel
					
					playerEspObjects[player] = data
				end
				
				-- Обновляем цвет
				data.Highlight.FillColor = playerEspColor
				data.Highlight.OutlineColor = playerEspColor
				data.NameLabel.TextColor3 = playerEspColor
				
				-- Обновляем дистанцию
				local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if myRoot then
					local dist = math.floor((myRoot.Position - rootPart.Position).Magnitude)
					data.DistLabel.Text = dist .. " studs"
				end
			else
				-- Убираем ESP если игрок мертв или нет персонажа
				local data = playerEspObjects[player]
				if data then
					if data.Highlight then data.Highlight:Destroy() end
					if data.BillboardGui then data.BillboardGui:Destroy() end
					playerEspObjects[player] = nil
				end
			end
		end
	end
	
	-- Убираем ESP для ушедших игроков
	for player, data in pairs(playerEspObjects) do
		if not player.Parent then
			if data.Highlight then data.Highlight:Destroy() end
			if data.BillboardGui then data.BillboardGui:Destroy() end
			playerEspObjects[player] = nil
		end
	end
end

-- ============================================
-- ФУНКЦИИ TELEPORT
-- ============================================
local function teleportToMouse()
	local character = LocalPlayer.Character
	if not character then return end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return end
	
	local target = Mouse.Hit.p
	humanoidRootPart.CFrame = CFrame.new(target + Vector3.new(0, 3, 0))
end

-- ============================================
-- СПИСОК ИГРОКОВ ДЛЯ TP
-- ============================================
local playerList = {}

local function refreshPlayerList()
	playerList = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			table.insert(playerList, player.Name)
		end
	end
	return playerList
end

local function teleportToPlayer(playerName)
	local targetPlayer = Players:FindFirstChild(playerName)
	if targetPlayer and targetPlayer.Character then
		local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
		local myCharacter = LocalPlayer.Character
		local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
		if targetRoot and myRoot then
			myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
		end
	end
end

-- ============================================
-- GUI СЕКЦИИ - MAIN TAB
-- ============================================
TabMain:CreateSection("⚡ Auto Functions")

TabMain:CreateToggle({
	Name = "Auto Tap Button",
	CurrentValue = false,
	Flag = "AutoTapButton",
	Callback = function(v)
		autoTapEnabled = v
		if v then
			startAutoTap()
		else
			stopAutoTap()
		end
	end
})

TabMain:CreateToggle({
	Name = "Auto Upgrade LvL",
	CurrentValue = false,
	Flag = "AutoUpgradeLvL",
	Callback = function(v)
		autoUpgradeEnabled = v
		if v then
			startAutoUpgrade()
		else
			stopAutoUpgrade()
		end
	end
})

TabMain:CreateToggle({
	Name = "Auto Buy LvL for 3 Watering",
	CurrentValue = false,
	Flag = "AutoBuyWatering",
	Callback = function(v)
		autoBuyWateringEnabled = v
		if v then
			startAutoBuyWatering()
		else
			stopAutoBuyWatering()
		end
	end
})

TabMain:CreateToggle({
	Name = "Auto Swing Axe",
	CurrentValue = false,
	Flag = "AutoSwingAxe",
	Callback = function(v)
		autoSwingEnabled = v
		if v then
			startAutoSwing()
		else
			stopAutoSwing()
		end
	end
})

TabMain:CreateSection("🎁 Misc")

TabMain:CreateButton({
	Name = "Get Free Totem",
	Callback = function()
		getFreeTotem()
	end
})

-- ============================================
-- GUI СЕКЦИИ - MOVEMENT TAB
-- ============================================
TabMovement:CreateSection("✈️ Flight")

TabMovement:CreateToggle({
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

TabMovement:CreateSlider({
	Name = "Fly Speed",
	Range = {10, 200},
	Increment = 5,
	CurrentValue = 50,
	Flag = "FlySpeed",
	Callback = function(v)
		flySpeed = v
	end
})

TabMovement:CreateSection("🚀 Speed & Jump")

TabMovement:CreateSlider({
	Name = "Walk Speed",
	Range = {16, 500},
	Increment = 1,
	CurrentValue = 16,
	Flag = "WalkSpeed",
	Callback = function(v)
		currentSpeed = v
		updateSpeed()
	end
})

TabMovement:CreateSlider({
	Name = "Jump Power",
	Range = {50, 500},
	Increment = 5,
	CurrentValue = 50,
	Flag = "JumpPower",
	Callback = function(v)
		currentJumpPower = v
		updateJumpPower()
	end
})

TabMovement:CreateSection("🌊 Other")

TabMovement:CreateToggle({
	Name = "Swim (Air)",
	CurrentValue = false,
	Flag = "Swim",
	Callback = function(v)
		swimEnabled = v
		if v then
			startSwim()
		else
			stopSwim()
		end
	end
})

TabMovement:CreateToggle({
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

-- ============================================
-- GUI СЕКЦИИ - VISUALS TAB
-- ============================================
TabVisuals:CreateSection("🌍 Environment")

TabVisuals:CreateToggle({
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

TabVisuals:CreateToggle({
	Name = "Fullbright",
	CurrentValue = false,
	Flag = "Fullbright",
	Callback = function(v)
		fullbrightEnabled = v
		if v then
			applyFullBright()
		else
			restoreFullBright()
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
	Name = "ESP Color",
	Color = playerEspColor,
	Flag = "ESPColor",
	Callback = function(c)
		playerEspColor = c
	end
})

-- ============================================
-- GUI СЕКЦИИ - TELEPORT TAB
-- ============================================
TabTeleport:CreateSection("🎯 Teleport Click")

TabTeleport:CreateKeybind({
	Name = "TP Click",
	CurrentKeybind = "",
	HoldToInteract = false,
	Flag = "TPClick",
	Callback = function()
		teleportToMouse()
	end
})

TabTeleport:CreateSection("👥 Teleport to Player")

refreshPlayerList()

local playerDropdown = TabTeleport:CreateDropdown({
	Name = "Select Player",
	Options = playerList,
	CurrentOption = {},
	MultipleOptions = false,
	Flag = "PlayerSelect",
	Callback = function(opt)
		if opt and #opt > 0 then
			teleportToPlayer(opt[1])
		end
	end
})

TabTeleport:CreateButton({
	Name = "Refresh Players",
	Callback = function()
		local newList = refreshPlayerList()
		playerDropdown:Set(newList)
		Rayfield:Notify({
			Title = "Player List",
			Content = "Список игроков обновлен!",
			Duration = 2,
			Image = 4483362458,
		})
	end
})

-- ============================================
-- ОБНОВЛЕНИЕ ESP
-- ============================================
RunService.Heartbeat:Connect(function()
	if playerEspEnabled then
		updatePlayerEsp()
	end
end)

-- Обновляем скорость и прыжок при респавне
LocalPlayer.CharacterAdded:Connect(function(char)
	task.wait(0.5)
	if currentSpeed ~= 16 then
		updateSpeed()
	end
	if currentJumpPower ~= 50 then
		updateJumpPower()
	end
end)
