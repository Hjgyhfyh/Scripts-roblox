local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
	Name = "tg: @sigmatik323",
	LoadingTitle = "tg: @sigmatik323",
	LoadingSubtitle = "by sigmatik323",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "SlimeIncremental"
	},
	Discord = {
		Enabled = false,
		Invite = "",
		RememberJoins = false
	},
	KeySystem = false
})

local flyEnabled = false
local flySpeed = 50
local flyConn = nil
local flyBodyGyro = nil
local flyBodyVel = nil

local speedEnabled = false
local speedValue = 16
local jumpPowerEnabled = false
local jumpPowerValue = 50
local swimEnabled = false
local swimConn = nil

local noclipEnabled = false
local noclipConn = nil

local fullBrightEnabled = false
local originalLighting = {}
local noFogEnabled = false
local originalFog = {}

local espPlayersEnabled = false
local espPlayerColor = Color3.fromRGB(255, 0, 0)
local espHighlights = {}

local tpClickEnabled = false
local tpClickBind = nil

local antiAfkEnabled = false
local antiAfkConn = nil

local autoRune1Enabled = false
local autoRune1Conn = nil
local originalRune1CFrame = nil

local autoRune2Enabled = false
local autoRune2Conn = nil
local originalRune2CFrame = nil

local autoRune3Enabled = false
local autoRune3Conn = nil
local originalRune3CFrame = nil

local autoRune5Enabled = false
local autoRune5Conn = nil
local originalRune5CFrame = nil

local autoStartW3Enabled = false
local autoStartW3Conn = nil

local autoLuckyBlockEnabled = false
local autoLuckyBlockConn = nil

local autoRuneEventEnabled = false
local autoRuneEventConn = nil
local originalRuneEventCFrame = nil

local autoBloomEnabled = false
local autoBloomConn = nil

local autoFarmEnabled = false
local autoFarmConn = nil
local autoFastPetFarmEnabled = false
local autoFastPetFarmConn = nil

local playerList = {}

local function getChar()
	local c = LocalPlayer.Character
	if not c then return nil end
	local h = c:FindFirstChildOfClass("Humanoid")
	local r = c:FindFirstChild("HumanoidRootPart")
	if not h or not r then return nil end
	return c, h, r
end

local function startFly()
	if flyConn then flyConn:Disconnect() end
	local c, h, r = getChar()
	if not c or not h or not r then return end
	
	flyBodyGyro = Instance.new("BodyGyro")
	flyBodyGyro.P = 9e4
	flyBodyGyro.maxTorque = Vector3.new(9e9, 9e9, 9e9)
	flyBodyGyro.cframe = r.CFrame
	flyBodyGyro.Parent = r
	
	flyBodyVel = Instance.new("BodyVelocity")
	flyBodyVel.velocity = Vector3.new(0, 0, 0)
	flyBodyVel.maxForce = Vector3.new(9e9, 9e9, 9e9)
	flyBodyVel.Parent = r
	
	flyConn = RunService.Heartbeat:Connect(function()
		if not flyEnabled then return end
		local c, h, r = getChar()
		if not c or not r or not flyBodyGyro or not flyBodyVel then return end
		
		flyBodyGyro.cframe = Camera.CFrame
		
		local moveDir = Vector3.new(0, 0, 0)
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			moveDir = moveDir + Camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			moveDir = moveDir - Camera.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			moveDir = moveDir - Camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			moveDir = moveDir + Camera.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			moveDir = moveDir + Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			moveDir = moveDir - Vector3.new(0, 1, 0)
		end
		
		if moveDir.Magnitude > 0 then
			flyBodyVel.velocity = moveDir.Unit * flySpeed
		else
			flyBodyVel.velocity = Vector3.new(0, 0, 0)
		end
	end)
end

local function stopFly()
	if flyConn then flyConn:Disconnect() flyConn = nil end
	if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
	if flyBodyVel then flyBodyVel:Destroy() flyBodyVel = nil end
end

local function startSwim()
	if swimConn then swimConn:Disconnect() end
	swimConn = RunService.Heartbeat:Connect(function()
		if not swimEnabled then return end
		local c, h, r = getChar()
		if not c or not h then return end
		h:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
		h:ChangeState(Enum.HumanoidStateType.Swimming)
	end)
end

local function stopSwim()
	if swimConn then swimConn:Disconnect() swimConn = nil end
end

local function startNoclip()
	if noclipConn then noclipConn:Disconnect() end
	noclipConn = RunService.Stepped:Connect(function()
		if not noclipEnabled then return end
		local c = LocalPlayer.Character
		if not c then return end
		for _, v in pairs(c:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = false
			end
		end
	end)
end

local function stopNoclip()
	if noclipConn then noclipConn:Disconnect() noclipConn = nil end
end

local function enableFullBright()
	originalLighting.Ambient = Lighting.Ambient
	originalLighting.Brightness = Lighting.Brightness
	originalLighting.OutdoorAmbient = Lighting.OutdoorAmbient
	Lighting.Ambient = Color3.fromRGB(255, 255, 255)
	Lighting.Brightness = 2
	Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
end

local function disableFullBright()
	if originalLighting.Ambient then Lighting.Ambient = originalLighting.Ambient end
	if originalLighting.Brightness then Lighting.Brightness = originalLighting.Brightness end
	if originalLighting.OutdoorAmbient then Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient end
end

local function enableNoFog()
	originalFog.FogEnd = Lighting.FogEnd
	originalFog.FogStart = Lighting.FogStart
	Lighting.FogEnd = 100000
	Lighting.FogStart = 100000
end

local function disableNoFog()
	if originalFog.FogEnd then Lighting.FogEnd = originalFog.FogEnd end
	if originalFog.FogStart then Lighting.FogStart = originalFog.FogStart end
end

local function createESPHighlight(player)
	if player == LocalPlayer then return end
	if player.Character then
		local highlight = Instance.new("Highlight")
		highlight.Name = "ESP_" .. player.Name
		highlight.FillColor = espPlayerColor
		highlight.OutlineColor = espPlayerColor
		highlight.FillTransparency = 0.5
		highlight.OutlineTransparency = 0
		highlight.Adornee = player.Character
		highlight.Parent = player.Character
		espHighlights[player] = highlight
	end
end

local function removeESPHighlight(player)
	if espHighlights[player] then
		espHighlights[player]:Destroy()
		espHighlights[player] = nil
	end
end

local function updateESPColor()
	for player, highlight in pairs(espHighlights) do
		if highlight and highlight.Parent then
			highlight.FillColor = espPlayerColor
			highlight.OutlineColor = espPlayerColor
		end
	end
end

local function enableESP()
	for _, player in pairs(Players:GetPlayers()) do
		createESPHighlight(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			if espPlayersEnabled then
				createESPHighlight(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		if espPlayersEnabled then
			player.CharacterAdded:Connect(function()
				task.wait(0.5)
				if espPlayersEnabled then
					createESPHighlight(player)
				end
			end)
		end
	end)
end

local function disableESP()
	for player, _ in pairs(espHighlights) do
		removeESPHighlight(player)
	end
end

local function refreshPlayerList()
	playerList = {}
	for _, player in pairs(Players:GetPlayers()) do
		if player ~= LocalPlayer then
			table.insert(playerList, player.Name)
		end
	end
	return playerList
end

local function teleportToPlayer(playerName)
	local targetPlayer = Players:FindFirstChild(playerName)
	if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
		local c, h, r = getChar()
		if r then
			r.CFrame = targetPlayer.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
		end
	end
end

local function startAntiAfk()
	if antiAfkConn then antiAfkConn:Disconnect() end
	antiAfkConn = LocalPlayer.Idled:Connect(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end

local function stopAntiAfk()
	if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end
end

local function getRune1Object()
	local worlds = workspace:FindFirstChild("Worlds")
	if not worlds then return nil end
	local world1 = worlds:FindFirstChild("World1")
	if not world1 then return nil end
	return world1:FindFirstChild("WORLD_1_RUNES")
end

local function getRune2Object()
	local worlds = workspace:FindFirstChild("Worlds")
	if not worlds then return nil end
	local world1 = worlds:FindFirstChild("World1")
	if not world1 then return nil end
	return world1:FindFirstChild("WORLD_2_RUNES")
end

local function getRune3Object()
	local worlds = workspace:FindFirstChild("Worlds")
	if not worlds then return nil end
	local world1 = worlds:FindFirstChild("World1")
	if not world1 then return nil end
	return world1:FindFirstChild("WORLD_3_RUNES")
end

local function getRune5Object()
	local worlds = workspace:FindFirstChild("Worlds")
	if not worlds then return nil end
	local world1 = worlds:FindFirstChild("World1")
	if not world1 then return nil end
	return world1:FindFirstChild("CANDY_RUNES")
end

local function getObjectCFrame(obj)
	if not obj then return nil end
	local cf = nil
	pcall(function()
		if obj:IsA("BasePart") then
			cf = obj.CFrame
		elseif obj:IsA("Model") then
			cf = obj:GetPivot()
		end
	end)
	return cf
end

local function setObjectCFrame(obj, cf)
	if not obj then return end
	pcall(function()
		if obj:IsA("BasePart") then
			obj.CFrame = cf
		elseif obj:IsA("Model") then
			obj:PivotTo(cf)
		end
	end)
end

local function moveRuneToPlayer(rune, playerPos)
	if not rune then return end
	pcall(function()
		if rune:IsA("BasePart") then
			rune.CFrame = CFrame.new(playerPos)
		elseif rune:IsA("Model") then
			rune:PivotTo(CFrame.new(playerPos))
		end
	end)
end

local function startAutoRune1()
	if autoRune1Conn then autoRune1Conn:Disconnect() end
	local rune = getRune1Object()
	if rune then originalRune1CFrame = getObjectCFrame(rune) end
	autoRune1Conn = RunService.Heartbeat:Connect(function()
		if not autoRune1Enabled then return end
		local c, h, r = getChar()
		if not r then return end
		local rune = getRune1Object()
		if rune then moveRuneToPlayer(rune, r.Position) end
	end)
end

local function stopAutoRune1()
	if autoRune1Conn then autoRune1Conn:Disconnect() autoRune1Conn = nil end
	if originalRune1CFrame then
		local rune = getRune1Object()
		if rune then setObjectCFrame(rune, originalRune1CFrame) end
		originalRune1CFrame = nil
	end
end

local function startAutoRune2()
	if autoRune2Conn then autoRune2Conn:Disconnect() end
	local rune = getRune2Object()
	if rune then originalRune2CFrame = getObjectCFrame(rune) end
	autoRune2Conn = RunService.Heartbeat:Connect(function()
		if not autoRune2Enabled then return end
		local c, h, r = getChar()
		if not r then return end
		local rune = getRune2Object()
		if rune then moveRuneToPlayer(rune, r.Position) end
	end)
end

local function stopAutoRune2()
	if autoRune2Conn then autoRune2Conn:Disconnect() autoRune2Conn = nil end
	if originalRune2CFrame then
		local rune = getRune2Object()
		if rune then setObjectCFrame(rune, originalRune2CFrame) end
		originalRune2CFrame = nil
	end
end

local function startAutoRune3()
	if autoRune3Conn then autoRune3Conn:Disconnect() end
	local rune = getRune3Object()
	if rune then originalRune3CFrame = getObjectCFrame(rune) end
	autoRune3Conn = RunService.Heartbeat:Connect(function()
		if not autoRune3Enabled then return end
		local c, h, r = getChar()
		if not r then return end
		local rune = getRune3Object()
		if rune then moveRuneToPlayer(rune, r.Position) end
	end)
end

local function stopAutoRune3()
	if autoRune3Conn then autoRune3Conn:Disconnect() autoRune3Conn = nil end
	if originalRune3CFrame then
		local rune = getRune3Object()
		if rune then setObjectCFrame(rune, originalRune3CFrame) end
		originalRune3CFrame = nil
	end
end

local function startAutoRune5()
	if autoRune5Conn then autoRune5Conn:Disconnect() end
	local rune = getRune5Object()
	if rune then originalRune5CFrame = getObjectCFrame(rune) end
	autoRune5Conn = RunService.Heartbeat:Connect(function()
		if not autoRune5Enabled then return end
		local c, h, r = getChar()
		if not r then return end
		local rune = getRune5Object()
		if rune then moveRuneToPlayer(rune, r.Position) end
	end)
end

local function stopAutoRune5()
	if autoRune5Conn then autoRune5Conn:Disconnect() autoRune5Conn = nil end
	if originalRune5CFrame then
		local rune = getRune5Object()
		if rune then setObjectCFrame(rune, originalRune5CFrame) end
		originalRune5CFrame = nil
	end
end

local function startAutoStartW3()
	if autoStartW3Conn then task.cancel(autoStartW3Conn) end
	autoStartW3Conn = task.spawn(function()
		while autoStartW3Enabled do
			pcall(function()
				game:GetService("ReplicatedStorage"):WaitForChild("Utility"):WaitForChild("Network"):WaitForChild("StartIceWorldSpawnEvent"):InvokeServer()
			end)
			task.wait(0.3)
		end
	end)
end

local function stopAutoStartW3()
	autoStartW3Enabled = false
	if autoStartW3Conn then task.cancel(autoStartW3Conn) autoStartW3Conn = nil end
end

local function startAutoLuckyBlock()
	if autoLuckyBlockConn then task.cancel(autoLuckyBlockConn) end
	autoLuckyBlockConn = task.spawn(function()
		while autoLuckyBlockEnabled do
			pcall(function()
				game:GetService("ReplicatedStorage"):WaitForChild("Utility"):WaitForChild("Network"):WaitForChild("ClaimLuckyBlock"):InvokeServer()
			end)
			task.wait(0.1)
		end
	end)
end

local function stopAutoLuckyBlock()
	autoLuckyBlockEnabled = false
	if autoLuckyBlockConn then task.cancel(autoLuckyBlockConn) autoLuckyBlockConn = nil end
end

local function getRuneEventObject()
	local worlds = workspace:FindFirstChild("Worlds")
	if not worlds then return nil end
	local world1 = worlds:FindFirstChild("World1")
	if not world1 then return nil end
	return world1:FindFirstChild("VALENTINE_RUNES")
end

local function startAutoRuneEvent()
	if autoRuneEventConn then autoRuneEventConn:Disconnect() end
	local rune = getRuneEventObject()
	if rune then originalRuneEventCFrame = getObjectCFrame(rune) end
	autoRuneEventConn = RunService.Heartbeat:Connect(function()
		if not autoRuneEventEnabled then return end
		local c, h, r = getChar()
		if not r then return end
		local rune = getRuneEventObject()
		if rune then moveRuneToPlayer(rune, r.Position) end
	end)
end

local function stopAutoRuneEvent()
	if autoRuneEventConn then autoRuneEventConn:Disconnect() autoRuneEventConn = nil end
	if originalRuneEventCFrame then
		local rune = getRuneEventObject()
		if rune then setObjectCFrame(rune, originalRuneEventCFrame) end
		originalRuneEventCFrame = nil
	end
end

local function startAutoBloom()
	if autoBloomConn then task.cancel(autoBloomConn) end
	autoBloomConn = task.spawn(function()
		while autoBloomEnabled do
			pcall(function()
				local args = {
					{
						invoke = function() end,
						listen = function() end
					}
				}
				game:GetService("ReplicatedStorage"):WaitForChild("Utility"):WaitForChild("Network"):WaitForChild("BloomService/bloom"):InvokeServer(unpack(args))
			end)
			task.wait(0.5)
		end
	end)
end

local function stopAutoBloom()
	autoBloomEnabled = false
	if autoBloomConn then task.cancel(autoBloomConn) autoBloomConn = nil end
end

local function findAllSlimes()
	local slimes = {}
	for _, folder in pairs(workspace:GetChildren()) do
		local name = folder.Name:lower()
		if string.find(name, "slime") then
			for _, child in pairs(folder:GetDescendants()) do
				if not child:IsA("Highlight") then
					if child:IsA("BasePart") and child.Transparency < 1 then
						table.insert(slimes, child)
					elseif child:IsA("Model") and child:FindFirstChildOfClass("BasePart") then
						table.insert(slimes, child)
					end
				end
			end
		end
	end
	return slimes
end

local function getSlimePosition(slime)
	if not slime then return nil end
	if slime:IsA("BasePart") then
		return slime.Position
	elseif slime:IsA("Model") then
		local part = slime:FindFirstChildOfClass("BasePart")
		if part then return part.Position end
		return slime:GetPivot().Position
	end
	return nil
end

local excludePosition = Vector3.new(-4061, 11, 397)
local excludeRadius = 10

local function isExcludedPosition(pos)
	if not pos then return false end
	return (pos - excludePosition).Magnitude <= excludeRadius
end

local function startAutoFarm()
	if autoFarmConn then autoFarmConn:Disconnect() end
	autoFarmConn = RunService.Heartbeat:Connect(function()
		if not autoFarmEnabled then return end
		local slimes = findAllSlimes()
		if #slimes > 0 then
			local c, h, r = getChar()
			if not r then return end
			
			local closest = nil
			local closestDist = math.huge
			local playerPos = r.Position
			
			for _, slime in ipairs(slimes) do
				local pos = getSlimePosition(slime)
				if pos and not isExcludedPosition(pos) then
					local dist = (pos - playerPos).Magnitude
					if dist < closestDist then
						closestDist = dist
						closest = slime
					end
				end
			end
			
			if closest then
				local pos = getSlimePosition(closest)
				if pos then
					r.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
				end
			end
		end
	end)
end

local function stopAutoFarm()
	autoFarmEnabled = false
	if autoFarmConn then autoFarmConn:Disconnect() autoFarmConn = nil end
end

local function startFastPetFarm()
	if autoFastPetFarmConn then task.cancel(autoFastPetFarmConn) end
	autoFastPetFarmConn = task.spawn(function()
		local remote = game:GetService("ReplicatedStorage"):WaitForChild("Utility"):WaitForChild("Network"):WaitForChild("PetCombatService/Position")
		while autoFastPetFarmEnabled do
			local slimes = findAllSlimes()
			if #slimes > 0 then
				for _, slime in ipairs(slimes) do
					if not autoFastPetFarmEnabled then break end
					local pos = getSlimePosition(slime)
					if pos and not isExcludedPosition(pos) then
						pcall(function()
							remote:FireServer(pos)
						end)
					end
				end
			end
			task.wait()
		end
	end)
end

local function stopFastPetFarm()
	autoFastPetFarmEnabled = false
	if autoFastPetFarmConn then task.cancel(autoFastPetFarmConn) autoFastPetFarmConn = nil end
end

local autoBuySlimeSpeedEnabled = false
local autoBuySlimeSpeedConn = nil
local autoBuySlimeCapEnabled = false
local autoBuySlimeCapConn = nil
local autoBuyCoinMultEnabled = false
local autoBuyCoinMultConn = nil
local autoBuyDamageEnabled = false
local autoBuyDamageConn = nil
local autoBuyRangeEnabled = false
local autoBuyRangeConn = nil
local autoBuySlimeLuckEnabled = false
local autoBuySlimeLuckConn = nil

local autoBuyRuneBulkEnabled = false
local autoBuyRuneBulkConn = nil
local autoBuyRuneLuckEnabled = false
local autoBuyRuneLuckConn = nil

local autoRebirthEnabled = false
local autoRebirthConn = nil
local autoRebirthDelay = 1
local autoBuyRebirthMultEnabled = false
local autoBuyRebirthMultConn = nil
local autoBuyDamageMultEnabled = false
local autoBuyDamageMultConn = nil
local autoBuyCoinMult2Enabled = false
local autoBuyCoinMult2Conn = nil
local autoBuyFireCoinMultEnabled = false
local autoBuyFireCoinMultConn = nil
local autoBuyLoc2Enabled = false
local autoBuyLoc2Conn = nil

local function startAutoBuyUpgrade(upgradeName)
	return task.spawn(function()
		while true do
			pcall(function()
				local args = {upgradeName, true}
				game:GetService("ReplicatedStorage"):WaitForChild("Utility"):WaitForChild("Network"):WaitForChild("PurchaseUpgradeBoard"):InvokeServer(unpack(args))
			end)
			task.wait(0.05)
		end
	end)
end

local function startAutoRebirth()
	return task.spawn(function()
		while autoRebirthEnabled do
			pcall(function()
				game:GetService("ReplicatedStorage"):WaitForChild("Utility"):WaitForChild("Network"):WaitForChild("RebirthEvent"):FireServer()
			end)
			task.wait(autoRebirthDelay)
		end
	end)
end

local function startAutoBuyLoc2()
	return task.spawn(function()
		while autoBuyLoc2Enabled do
			for i = 1, 65 do
				if not autoBuyLoc2Enabled then break end
				pcall(function()
					local args = {"1-" .. tostring(i)}
					game:GetService("ReplicatedStorage"):WaitForChild("Utility"):WaitForChild("Network"):WaitForChild("UpgradeNodePurchaseEvent"):InvokeServer(unpack(args))
				end)
				task.wait(0.02)
			end
			task.wait(0.1)
		end
	end)
end

local TabFarm = Window:CreateTab("🌾 Auto Farm", 4483362458)
local TabEvent = Window:CreateTab("🌹 Event", 4483362458)
local TabRunes = Window:CreateTab("🔮 Rune", 4483362458)
local TabBuyW1 = Window:CreateTab("💰 Buy W1", 4483362458)
local TabVisual = Window:CreateTab("👁️ Visual", 4483362458)
local TabTeleport = Window:CreateTab("🚀 Teleport", 4483362458)
local TabPlayer = Window:CreateTab("🏃 Player", 4483362458)
local TabMisc = Window:CreateTab("⚙️ Utility", 4483362458)

TabFarm:CreateSection("🐸 Slime Farm")

TabFarm:CreateToggle({
	Name = "Auto Farm",
	CurrentValue = false,
	Flag = "AutoFarm",
	Callback = function(v)
		autoFarmEnabled = v
		if v then
			startAutoFarm()
			Rayfield:Notify({Title = "Auto Farm", Content = "Farming slimes...", Duration = 2})
		else
			stopAutoFarm()
		end
	end
})

TabFarm:CreateToggle({
	Name = "Fast Pet Farm",
	CurrentValue = false,
	Flag = "FastPetFarm",
	Callback = function(v)
		autoFastPetFarmEnabled = v
		if v then
			startFastPetFarm()
			Rayfield:Notify({Title = "Fast Pet Farm", Content = "Spamming pet attack on slimes...", Duration = 2})
		else
			stopFastPetFarm()
		end
	end
})

TabFarm:CreateToggle({
	Name = "Auto Start",
	CurrentValue = false,
	Flag = "AutoStartW3",
	Callback = function(v)
		autoStartW3Enabled = v
		if v then startAutoStartW3() else stopAutoStartW3() end
	end
})

TabFarm:CreateSection("🎲 Lucky Block")

TabFarm:CreateToggle({
	Name = "Auto Lucky Block",
	CurrentValue = false,
	Flag = "AutoLuckyBlock",
	Callback = function(v)
		autoLuckyBlockEnabled = v
		if v then
			startAutoLuckyBlock()
			Rayfield:Notify({Title = "Auto Lucky Block", Content = "Claiming every 0.1s...", Duration = 2})
		else
			stopAutoLuckyBlock()
		end
	end
})

TabRunes:CreateSection("🌱 World 1")

TabRunes:CreateToggle({
	Name = "Auto Rune 1 World",
	CurrentValue = false,
	Flag = "AutoRune1World",
	Callback = function(v)
		autoRune1Enabled = v
		if v then startAutoRune1() else stopAutoRune1() end
	end
})

TabRunes:CreateSection("🌋 World 2")

TabRunes:CreateToggle({
	Name = "Auto Rune 2 World",
	CurrentValue = false,
	Flag = "AutoRune2World",
	Callback = function(v)
		autoRune2Enabled = v
		if v then startAutoRune2() else stopAutoRune2() end
	end
})

TabRunes:CreateSection("❄️ World 3")

TabRunes:CreateToggle({
	Name = "Auto Rune 3 World",
	CurrentValue = false,
	Flag = "AutoRune3World",
	Callback = function(v)
		autoRune3Enabled = v
		if v then startAutoRune3() else stopAutoRune3() end
	end
})

TabRunes:CreateSection("🍬 World 5")

TabRunes:CreateToggle({
	Name = "Auto Rune 5 World",
	CurrentValue = false,
	Flag = "AutoRune5World",
	Callback = function(v)
		autoRune5Enabled = v
		if v then startAutoRune5() else stopAutoRune5() end
	end
})

TabEvent:CreateSection("💘 Valentine")

TabEvent:CreateToggle({
	Name = "Auto Rune Valentine",
	CurrentValue = false,
	Flag = "AutoRuneValentine",
	Callback = function(v)
		autoRuneEventEnabled = v
		if v then startAutoRuneEvent() else stopAutoRuneEvent() end
	end
})

TabEvent:CreateToggle({
	Name = "Auto Bloom",
	CurrentValue = false,
	Flag = "AutoBloom",
	Callback = function(v)
		autoBloomEnabled = v
		if v then
			startAutoBloom()
			Rayfield:Notify({Title = "Auto Bloom", Content = "Enabled!", Duration = 2})
		else
			stopAutoBloom()
		end
	end
})

TabBuyW1:CreateSection("💵 Coin Upgrades")

TabBuyW1:CreateToggle({
	Name = "Auto Buy Slime Speed",
	CurrentValue = false,
	Flag = "AutoBuySlimeSpeed",
	Callback = function(v)
		autoBuySlimeSpeedEnabled = v
		if v then
			autoBuySlimeSpeedConn = startAutoBuyUpgrade("SLIME_SPAWN_SPEED")
		else
			if autoBuySlimeSpeedConn then task.cancel(autoBuySlimeSpeedConn) autoBuySlimeSpeedConn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Slime Cap",
	CurrentValue = false,
	Flag = "AutoBuySlimeCap",
	Callback = function(v)
		autoBuySlimeCapEnabled = v
		if v then
			autoBuySlimeCapConn = startAutoBuyUpgrade("SLIME_SPAWN_CAP")
		else
			if autoBuySlimeCapConn then task.cancel(autoBuySlimeCapConn) autoBuySlimeCapConn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Coin Mult",
	CurrentValue = false,
	Flag = "AutoBuyCoinMult",
	Callback = function(v)
		autoBuyCoinMultEnabled = v
		if v then
			autoBuyCoinMultConn = startAutoBuyUpgrade("COIN_MULTIPLIER")
		else
			if autoBuyCoinMultConn then task.cancel(autoBuyCoinMultConn) autoBuyCoinMultConn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Damage",
	CurrentValue = false,
	Flag = "AutoBuyDamage",
	Callback = function(v)
		autoBuyDamageEnabled = v
		if v then
			autoBuyDamageConn = startAutoBuyUpgrade("DAMAGE_INCREASE")
		else
			if autoBuyDamageConn then task.cancel(autoBuyDamageConn) autoBuyDamageConn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Range",
	CurrentValue = false,
	Flag = "AutoBuyRange",
	Callback = function(v)
		autoBuyRangeEnabled = v
		if v then
			autoBuyRangeConn = startAutoBuyUpgrade("RANGE_INCREASE_1")
		else
			if autoBuyRangeConn then task.cancel(autoBuyRangeConn) autoBuyRangeConn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Slime Luck",
	CurrentValue = false,
	Flag = "AutoBuySlimeLuck",
	Callback = function(v)
		autoBuySlimeLuckEnabled = v
		if v then
			autoBuySlimeLuckConn = startAutoBuyUpgrade("SLIME_LUCK")
		else
			if autoBuySlimeLuckConn then task.cancel(autoBuySlimeLuckConn) autoBuySlimeLuckConn = nil end
		end
	end
})

TabBuyW1:CreateSection("💎 Shard Upgrades")

TabBuyW1:CreateToggle({
	Name = "Auto Buy Rune Bulk",
	CurrentValue = false,
	Flag = "AutoBuyRuneBulk",
	Callback = function(v)
		autoBuyRuneBulkEnabled = v
		if v then
			autoBuyRuneBulkConn = startAutoBuyUpgrade("RUNE_BULK_1")
		else
			if autoBuyRuneBulkConn then task.cancel(autoBuyRuneBulkConn) autoBuyRuneBulkConn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Rune Luck",
	CurrentValue = false,
	Flag = "AutoBuyRuneLuck",
	Callback = function(v)
		autoBuyRuneLuckEnabled = v
		if v then
			autoBuyRuneLuckConn = startAutoBuyUpgrade("RUNE_LUCK")
		else
			if autoBuyRuneLuckConn then task.cancel(autoBuyRuneLuckConn) autoBuyRuneLuckConn = nil end
		end
	end
})

TabBuyW1:CreateSection("🔄 Rebirth Upgrades")

TabBuyW1:CreateToggle({
	Name = "Auto Rebirth",
	CurrentValue = false,
	Flag = "AutoRebirth",
	Callback = function(v)
		autoRebirthEnabled = v
		if v then
			autoRebirthConn = startAutoRebirth()
		else
			if autoRebirthConn then task.cancel(autoRebirthConn) autoRebirthConn = nil end
		end
	end
})

TabBuyW1:CreateSlider({
	Name = "Rebirth Delay",
	Range = {1, 60},
	Increment = 1,
	Suffix = " sec",
	CurrentValue = autoRebirthDelay,
	Flag = "RebirthDelay",
	Callback = function(v)
		autoRebirthDelay = v
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Rebirth Mult",
	CurrentValue = false,
	Flag = "AutoBuyRebirthMult",
	Callback = function(v)
		autoBuyRebirthMultEnabled = v
		if v then
			autoBuyRebirthMultConn = startAutoBuyUpgrade("REBIRTH_MULTIPLIER")
		else
			if autoBuyRebirthMultConn then task.cancel(autoBuyRebirthMultConn) autoBuyRebirthMultConn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Damage Mult",
	CurrentValue = false,
	Flag = "AutoBuyDamageMult",
	Callback = function(v)
		autoBuyDamageMultEnabled = v
		if v then
			autoBuyDamageMultConn = startAutoBuyUpgrade("DAMAGE_MULTIPLIER")
		else
			if autoBuyDamageMultConn then task.cancel(autoBuyDamageMultConn) autoBuyDamageMultConn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Coin Mult 2",
	CurrentValue = false,
	Flag = "AutoBuyCoinMult2",
	Callback = function(v)
		autoBuyCoinMult2Enabled = v
		if v then
			autoBuyCoinMult2Conn = startAutoBuyUpgrade("COIN_MULTIPLIER_2")
		else
			if autoBuyCoinMult2Conn then task.cancel(autoBuyCoinMult2Conn) autoBuyCoinMult2Conn = nil end
		end
	end
})

TabBuyW1:CreateToggle({
	Name = "Auto Buy Fire Coin Mult",
	CurrentValue = false,
	Flag = "AutoBuyFireCoinMult",
	Callback = function(v)
		autoBuyFireCoinMultEnabled = v
		if v then
			autoBuyFireCoinMultConn = startAutoBuyUpgrade("FIRE_COIN_MULTIPLIER_1")
		else
			if autoBuyFireCoinMultConn then task.cancel(autoBuyFireCoinMultConn) autoBuyFireCoinMultConn = nil end
		end
	end
})

TabBuyW1:CreateSection("🌋 World 2 Unlock")

TabBuyW1:CreateButton({
	Name = "Buy Lava World",
	Callback = function()
		pcall(function()
			local args = {"LAVA_WORLD"}
			game:GetService("ReplicatedStorage"):WaitForChild("Utility"):WaitForChild("Network"):WaitForChild("WorldServicePurchase"):InvokeServer(unpack(args))
		end)
		Rayfield:Notify({Title = "World 2", Content = "Purchased Lava World!", Duration = 2})
	end
})

TabBuyW1:CreateSection("🌐 Location 2 Upgrades")

TabBuyW1:CreateToggle({
	Name = "Auto Buy 1-1 - 1-65 Upgrades",
	CurrentValue = false,
	Flag = "AutoBuyLoc2",
	Callback = function(v)
		autoBuyLoc2Enabled = v
		if v then
			autoBuyLoc2Conn = startAutoBuyLoc2()
		else
			if autoBuyLoc2Conn then task.cancel(autoBuyLoc2Conn) autoBuyLoc2Conn = nil end
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
		if v then startFly() else stopFly() end
	end
})

TabPlayer:CreateSlider({
	Name = "Fly Speed",
	Range = {10, 500},
	Increment = 5,
	Suffix = " studs",
	CurrentValue = flySpeed,
	Flag = "FlySpeed",
	Callback = function(v)
		flySpeed = v
	end
})

TabPlayer:CreateToggle({
	Name = "Speed",
	CurrentValue = false,
	Flag = "SpeedEnabled",
	Callback = function(v)
		speedEnabled = v
		local c, h = getChar()
		if h then
			h.WalkSpeed = v and speedValue or 16
		end
	end
})

TabPlayer:CreateSlider({
	Name = "Speed Value",
	Range = {16, 100},
	Increment = 1,
	Suffix = "",
	CurrentValue = speedValue,
	Flag = "SpeedValue",
	Callback = function(v)
		speedValue = v
		if speedEnabled then
			local c, h = getChar()
			if h then h.WalkSpeed = v end
		end
	end
})

TabPlayer:CreateToggle({
	Name = "Jump Power",
	CurrentValue = false,
	Flag = "JumpPowerEnabled",
	Callback = function(v)
		jumpPowerEnabled = v
		local c, h = getChar()
		if h then
			h.JumpPower = v and jumpPowerValue or 50
		end
	end
})

TabPlayer:CreateSlider({
	Name = "Jump Power Value",
	Range = {50, 500},
	Increment = 5,
	Suffix = "",
	CurrentValue = jumpPowerValue,
	Flag = "JumpPowerValue",
	Callback = function(v)
		jumpPowerValue = v
		if jumpPowerEnabled then
			local c, h = getChar()
			if h then h.JumpPower = v end
		end
	end
})

TabPlayer:CreateToggle({
	Name = "Swim",
	CurrentValue = false,
	Flag = "Swim",
	Callback = function(v)
		swimEnabled = v
		if v then startSwim() else stopSwim() end
	end
})

TabPlayer:CreateToggle({
	Name = "Noclip",
	CurrentValue = false,
	Flag = "Noclip",
	Callback = function(v)
		noclipEnabled = v
		if v then startNoclip() else stopNoclip() end
	end
})

TabVisual:CreateSection("🔦 Lighting")

TabVisual:CreateToggle({
	Name = "FullBright",
	CurrentValue = false,
	Flag = "FullBright",
	Callback = function(v)
		fullBrightEnabled = v
		if v then enableFullBright() else disableFullBright() end
	end
})

TabVisual:CreateToggle({
	Name = "No Fog",
	CurrentValue = false,
	Flag = "NoFog",
	Callback = function(v)
		noFogEnabled = v
		if v then enableNoFog() else disableNoFog() end
	end
})

TabVisual:CreateSection("👤 ESP")

TabVisual:CreateToggle({
	Name = "ESP Players",
	CurrentValue = false,
	Flag = "ESPPlayers",
	Callback = function(v)
		espPlayersEnabled = v
		if v then enableESP() else disableESP() end
	end
})

TabVisual:CreateColorPicker({
	Name = "ESP Color",
	Color = espPlayerColor,
	Flag = "ESPColor",
	Callback = function(v)
		espPlayerColor = v
		updateESPColor()
	end
})

TabTeleport:CreateSection("👥 TP to Players")

local selectedPlayer = nil
local playerDropdown = TabTeleport:CreateDropdown({
	Name = "Select Player",
	Options = refreshPlayerList(),
	CurrentOption = {},
	MultipleOptions = false,
	Flag = "SelectedPlayer",
	Callback = function(opt)
		selectedPlayer = opt[1]
	end
})

TabTeleport:CreateButton({
	Name = "Refresh Players",
	Callback = function()
		playerDropdown:Set(refreshPlayerList())
	end
})

TabTeleport:CreateButton({
	Name = "Teleport to Player",
	Callback = function()
		if selectedPlayer then
			teleportToPlayer(selectedPlayer)
			Rayfield:Notify({Title = "Teleport", Content = "Teleported to " .. selectedPlayer, Duration = 2})
		end
	end
})

TabTeleport:CreateSection("🖱️ Click TP")

TabTeleport:CreateKeybind({
	Name = "TP Click",
	CurrentKeybind = "",
	HoldToInteract = false,
	Flag = "TPClick",
	Callback = function()
		local c, h, r = getChar()
		if r and Mouse.Hit then
			r.CFrame = Mouse.Hit + Vector3.new(0, 3, 0)
		end
	end
})

TabMisc:CreateSection("⚙️ Utility")

TabMisc:CreateToggle({
	Name = "Anti AFK",
	CurrentValue = false,
	Flag = "AntiAFK",
	Callback = function(v)
		antiAfkEnabled = v
		if v then
			startAntiAfk()
			Rayfield:Notify({Title = "Anti AFK", Content = "Enabled!", Duration = 2})
		else
			stopAntiAfk()
		end
	end
})

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	if flyEnabled then startFly() end
	if swimEnabled then startSwim() end
	if noclipEnabled then startNoclip() end
	if speedEnabled then
		local c, h = getChar()
		if h then h.WalkSpeed = speedValue end
	end
	if jumpPowerEnabled then
		local c, h = getChar()
		if h then h.JumpPower = jumpPowerValue end
	end
	if autoRune1Enabled then startAutoRune1() end
	if autoRune2Enabled then startAutoRune2() end
	if autoRune3Enabled then startAutoRune3() end
	if autoRune5Enabled then startAutoRune5() end
	if autoStartW3Enabled then startAutoStartW3() end
	if autoLuckyBlockEnabled then startAutoLuckyBlock() end
	if autoRuneEventEnabled then startAutoRuneEvent() end
	if autoBloomEnabled then startAutoBloom() end
	if autoFarmEnabled then startAutoFarm() end
	if autoFastPetFarmEnabled then startFastPetFarm() end
	if espPlayersEnabled then
		task.wait(0.5)
		enableESP()
	end
end)
