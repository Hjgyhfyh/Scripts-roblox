local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
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
		FileName = "WoodIncremental"
	},
	Discord = {
		Enabled = false,
		Invite = "",
		RememberJoins = false
	},
	KeySystem = false
})

local TabMain = Window:CreateTab("🌳 Auto Farm", 4483362458)

local autoFarmTreeEnabled = false
local autoFarmConn = nil

local autoFarmSticksEnabled = false
local autoFarmSticksConn = nil
local autoFarmSticksTargets = {}
local autoFarmSticksTargetIndex = 1
local autoFarmSticksSpeed = 100

local antiAfkEnabled = false
local antiAfkConn = nil

local function getChar()
	local c = LocalPlayer.Character
	if not c then return nil end
	local h = c:FindFirstChildOfClass("Humanoid")
	local r = c:FindFirstChild("HumanoidRootPart")
	if not h or not r then return nil end
	return c, h, r
end

local function getTreeZone()
	local zones = workspace:FindFirstChild("Zones")
	if not zones then return nil end
	local treeZone = zones:FindFirstChild("TreeZone")
	return treeZone
end

local function moveTreeZoneToPlayer(playerPos)
	local treeZone = getTreeZone()
	if not treeZone then return end
	
	pcall(function()
		if treeZone:IsA("BasePart") then
			treeZone.CFrame = CFrame.new(playerPos)
		elseif treeZone:IsA("Model") then
			if treeZone.PrimaryPart then
				local offset = treeZone:GetPivot().Position - treeZone.PrimaryPart.Position
				treeZone:SetPrimaryPartCFrame(CFrame.new(playerPos + offset))
			else
				local firstPart = treeZone:FindFirstChildWhichIsA("BasePart", true)
				if firstPart then
					local pivot = treeZone:GetPivot()
					local offset = pivot.Position - firstPart.Position
					treeZone:PivotTo(CFrame.new(playerPos + offset))
				end
			end
		end
	end)
end

local function startAutoFarmTree()
	if autoFarmConn then autoFarmConn:Disconnect() end
	autoFarmConn = nil
	
	autoFarmConn = RunService.Heartbeat:Connect(function()
		if not autoFarmTreeEnabled then return end
		
		local c, h, r = getChar()
		if not c or not h or not r then return end
		
		local treeZone = getTreeZone()
		if not treeZone then return end
		
		local playerPos = r.Position
		moveTreeZoneToPlayer(playerPos)
	end)
end

local function stopAutoFarmTree()
	if autoFarmConn then
		autoFarmConn:Disconnect()
		autoFarmConn = nil
	end
end

local function getObjectPosition(obj)
	if not obj then return nil end
	
	local pos = nil
	pcall(function()
		if obj:IsA("BasePart") then
			pos = obj.Position
		elseif obj:IsA("Model") then
			if obj.PrimaryPart then
				pos = obj.PrimaryPart.Position
			else
				local firstPart = obj:FindFirstChildWhichIsA("BasePart", true)
				if firstPart then
					pos = firstPart.Position
				end
			end
		end
	end)
	return pos
end

local function getStickPositions()
	local positions = {}
	
	-- Находим все basic_stick, stone_stick, copper_stick
	local stickNames = {"basic_stick", "stone_stick", "copper_stick"}
	for _, name in ipairs(stickNames) do
		for _, obj in ipairs(workspace:GetChildren()) do
			if obj.Name == name then
				local pos = getObjectPosition(obj)
				if pos then
					table.insert(positions, pos)
				end
			end
		end
	end
	
	-- Находим StickZone
	local zones = workspace:FindFirstChild("Zones")
	if zones then
		local stickZone = zones:FindFirstChild("StickZone")
		if stickZone then
			local pos = getObjectPosition(stickZone)
			if pos then
				table.insert(positions, pos)
			end
		end
	end
	
	return positions
end

local function refreshStickTargets()
	autoFarmSticksTargets = getStickPositions()
	autoFarmSticksTargetIndex = 1
end

local function startAutoFarmSticks()
	if autoFarmSticksConn then
		autoFarmSticksConn:Disconnect()
		autoFarmSticksConn = nil
	end
	
	refreshStickTargets()
	
	autoFarmSticksConn = RunService.Heartbeat:Connect(function()
		if not autoFarmSticksEnabled then return end
		
		local c, h, r = getChar()
		if not c or not h or not r then return end
		
		-- Обновляем список целей, если закончились
		if #autoFarmSticksTargets == 0 or autoFarmSticksTargetIndex > #autoFarmSticksTargets then
			refreshStickTargets()
			if #autoFarmSticksTargets == 0 then return end
		end
		
		local targetPos = autoFarmSticksTargets[autoFarmSticksTargetIndex] + Vector3.new(0, 3, 0)
		local currentPos = r.Position
		local direction = (targetPos - currentPos)
		local distance = direction.Magnitude
		
		-- Если достигли цели, переходим к следующей
		if distance <= 5 then
			autoFarmSticksTargetIndex = autoFarmSticksTargetIndex + 1
			return
		end
		
		-- Плавно перемещаемся к цели
		local moveDistance = math.min(distance, (autoFarmSticksSpeed / 60)) -- Скорость в студах/сек
		local newPos = currentPos + direction.Unit * moveDistance
		
		pcall(function()
			r.CFrame = CFrame.new(newPos, targetPos)
		end)
	end)
end

local function stopAutoFarmSticks()
	if autoFarmSticksConn then
		autoFarmSticksConn:Disconnect()
		autoFarmSticksConn = nil
	end
	autoFarmSticksTargets = {}
	autoFarmSticksTargetIndex = 1
end

local function startAntiAfk()
	if antiAfkConn then
		antiAfkConn:Disconnect()
		antiAfkConn = nil
	end
	
	-- Подключаемся к событию Idled для предотвращения кика за бездействие
	antiAfkConn = LocalPlayer.Idled:Connect(function(time)
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end

local function stopAntiAfk()
	if antiAfkConn then
		antiAfkConn:Disconnect()
		antiAfkConn = nil
	end
end

TabMain:CreateSection("🌲 Tree Farming")

TabMain:CreateToggle({
	Name = "Auto Farm Tree",
	CurrentValue = false,
	Flag = "AutoFarmTree",
	Callback = function(v)
		autoFarmTreeEnabled = v
		if v then
			startAutoFarmTree()
			Rayfield:Notify({
				Title = "Auto Farm Tree",
				Content = "Moving TreeZone to player...",
				Duration = 2
			})
		else
			stopAutoFarmTree()
		end
	end
})

TabMain:CreateSection("🥢 Stick Farming")

TabMain:CreateSlider({
	Name = "Stick Move Speed",
	Info = "Speed of movement to sticks (studs per second)",
	Min = 50,
	Max = 500,
	Increment = 10,
	CurrentValue = autoFarmSticksSpeed,
	Flag = "StickMoveSpeed",
	Callback = function(v)
		autoFarmSticksSpeed = v
	end
})

TabMain:CreateToggle({
	Name = "Auto Farm Sticks",
	CurrentValue = false,
	Flag = "AutoFarmSticks",
	Callback = function(v)
		autoFarmSticksEnabled = v
		if v then
			startAutoFarmSticks()
			Rayfield:Notify({
				Title = "Auto Farm Sticks",
				Content = "Smoothly moving to all sticks (basic_stick, stone_stick, copper_stick, StickZone)...",
				Duration = 3
			})
		else
			stopAutoFarmSticks()
		end
	end
})

TabMain:CreateButton({
	Name = "Enable Stick Farm",
	Callback = function()
		autoFarmSticksEnabled = true
		startAutoFarmSticks()
		Rayfield:Notify({
			Title = "Auto Farm Sticks",
			Content = "Stick farming enabled via button!",
			Duration = 2
		})
	end
})

TabMain:CreateButton({
	Name = "Disable Stick Farm",
	Callback = function()
		autoFarmSticksEnabled = false
		stopAutoFarmSticks()
		Rayfield:Notify({
			Title = "Auto Farm Sticks",
			Content = "Stick farming disabled via button!",
			Duration = 2
		})
	end
})

TabMain:CreateSection("⚙️ Utility")

TabMain:CreateToggle({
	Name = "Anti AFK",
	CurrentValue = false,
	Flag = "AntiAFK",
	Callback = function(v)
		antiAfkEnabled = v
		if v then
			startAntiAfk()
			Rayfield:Notify({
				Title = "Anti AFK",
				Content = "Anti AFK enabled! You won't be kicked for inactivity.",
				Duration = 2
			})
		else
			stopAntiAfk()
		end
	end
})

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	if autoFarmTreeEnabled then
		startAutoFarmTree()
	end
	if autoFarmSticksEnabled then
		startAutoFarmSticks()
	end
	if antiAfkEnabled then
		startAntiAfk()
	end
end)
