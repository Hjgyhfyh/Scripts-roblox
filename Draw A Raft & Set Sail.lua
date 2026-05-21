local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
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

local TabMain = Window:CreateTab("🚢 Draw A Raft & Set Sail", 4483362458)

local player = Players.LocalPlayer

-- Variables
local sitamaModeEnabled = false
local sitamaModeConn = nil

local swapShovelEnabled = false
local swapShovelConn = nil
local currentShovelSide = "right"

local flyEnabled = false
local flySpeed = 50
local flyBodyGyro = nil
local flyBodyVelocity = nil

local nofogEnabled = false
local originalFogEnd = nil
local originalFogStart = nil
local originalAtmosphere = {}

-- Сохранённый цвет плота и данные последнего спавна
local selectedRaftColor = {R = 0.4745098054409027, G = 0.22352942824363708, B = 0.07450980693101883}
local lastRaftData = nil
local captureRaftSpawn = false

-- Sitama Mode Functions (бывший Auto Ragdoll)
local function toggleSitamaMode(state)
	sitamaModeEnabled = state
	if sitamaModeConn then
		sitamaModeConn:Disconnect()
		sitamaModeConn = nil
	end

	if sitamaModeEnabled then
		sitamaModeConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("Ragdoll"):FireServer()
			end)
		end)
	end
end

-- Swap Shovel Functions
local function toggleSwapShovel(state)
	swapShovelEnabled = state
	if swapShovelConn then
		swapShovelConn:Disconnect()
		swapShovelConn = nil
	end

	if swapShovelEnabled then
		swapShovelConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				if currentShovelSide == "right" then
					ReplicatedStorage:WaitForChild("PaddleGrip"):FireServer("right")
					currentShovelSide = "left"
				else
					ReplicatedStorage:WaitForChild("PaddleGrip"):FireServer("left")
					currentShovelSide = "right"
				end
			end)
		end)
	end
end

-- Fly Functions
local function startFly()
	local character = player.Character
	if not character then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoidRootPart or not humanoid then return end
	
	-- Отключаем физику падения
	humanoid.PlatformStand = true
	
	flyBodyGyro = Instance.new("BodyGyro")
	flyBodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	flyBodyGyro.P = 9e4
	flyBodyGyro.Parent = humanoidRootPart
	
	flyBodyVelocity = Instance.new("BodyVelocity")
	flyBodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	flyBodyVelocity.Velocity = Vector3.new(0, 0, 0)
	flyBodyVelocity.Parent = humanoidRootPart
end

local function stopFly()
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
	end
	
	if flyBodyGyro then
		flyBodyGyro:Destroy()
		flyBodyGyro = nil
	end
	if flyBodyVelocity then
		flyBodyVelocity:Destroy()
		flyBodyVelocity = nil
	end
end

local function updateFly()
	local character = player.Character
	if not character or not flyEnabled then return end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not humanoidRootPart or not camera or not flyBodyVelocity or not flyBodyGyro then return end
	
	local direction = Vector3.new(0, 0, 0)
	
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		direction = direction + camera.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		direction = direction - camera.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		direction = direction - camera.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		direction = direction + camera.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		direction = direction + Vector3.new(0, 1, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		direction = direction - Vector3.new(0, 1, 0)
	end
	
	if direction.Magnitude > 0 then
		direction = direction.Unit
	end
	
	flyBodyVelocity.Velocity = direction * flySpeed
	flyBodyGyro.CFrame = camera.CFrame
end

local flyUpdateConn = nil
local function toggleFly(state)
	flyEnabled = state
	
	if flyEnabled then
		startFly()
		flyUpdateConn = RunService.Heartbeat:Connect(updateFly)
	else
		if flyUpdateConn then
			flyUpdateConn:Disconnect()
			flyUpdateConn = nil
		end
		stopFly()
	end
end

-- Nofog Functions
local function toggleNofog(state)
	nofogEnabled = state
	
	if nofogEnabled then
		-- Сохраняем оригинальные значения
		originalFogEnd = Lighting.FogEnd
		originalFogStart = Lighting.FogStart
		
		-- Убираем туман
		Lighting.FogEnd = 1000000
		Lighting.FogStart = 1000000
		
		-- Убираем Atmosphere если есть
		for _, child in pairs(Lighting:GetChildren()) do
			if child:IsA("Atmosphere") then
				originalAtmosphere[child] = {
					Density = child.Density,
					Offset = child.Offset
				}
				child.Density = 0
				child.Offset = 0
			end
		end
	else
		-- Восстанавливаем оригинальные значения
		if originalFogEnd then
			Lighting.FogEnd = originalFogEnd
		end
		if originalFogStart then
			Lighting.FogStart = originalFogStart
		end
		
		-- Восстанавливаем Atmosphere
		for atmosphere, values in pairs(originalAtmosphere) do
			if atmosphere and atmosphere.Parent then
				atmosphere.Density = values.Density
				atmosphere.Offset = values.Offset
			end
		end
		originalAtmosphere = {}
	end
end

-- Raft Capture Functions
local function captureRaftData()
	captureRaftSpawn = true
	Rayfield:Notify({
		Title = "🚢 Capture Mode ON",
		Content = "Now spawn your raft in the game! The script will capture the data.",
		Duration = 5,
		Image = 4483362458
	})
end

local function spawnRaftWithColor()
	if not lastRaftData then
		Rayfield:Notify({
			Title = "❌ No Raft Data",
			Content = "First capture a raft spawn by clicking 'Capture Raft Spawn'",
			Duration = 3,
			Image = 4483362458
		})
		return
	end
	
	-- Создаём копию данных с новым цветом
	local modifiedData = {}
	modifiedData[1] = {
		compressedLen = lastRaftData[1].compressedLen,
		raftColor = {
			R = selectedRaftColor.R,
			G = selectedRaftColor.G,
			B = selectedRaftColor.B
		},
		size = lastRaftData[1].size,
		paintedCount = lastRaftData[1].paintedCount
	}
	modifiedData[2] = lastRaftData[2]
	
	-- Спавним плот с новым цветом
	pcall(function()
		ReplicatedStorage:WaitForChild("BuildRaftEvent"):FireServer(unpack(modifiedData))
	end)
	
	Rayfield:Notify({
		Title = "✅ Raft Spawned!",
		Content = string.format("Color: R=%.2f G=%.2f B=%.2f", selectedRaftColor.R, selectedRaftColor.G, selectedRaftColor.B),
		Duration = 3,
		Image = 4483362458
	})
end

-- Hook для перехвата спавна плота
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
	local args = {...}
	local method = getnamecallmethod()
	
	if method == "FireServer" and self.Name == "BuildRaftEvent" and captureRaftSpawn then
		captureRaftSpawn = false
		lastRaftData = args
		
		Rayfield:Notify({
			Title = "✅ Raft Captured!",
			Content = "Raft data saved. Now you can spawn with custom color!",
			Duration = 3,
			Image = 4483362458
		})
	end
	
	return oldNamecall(self, ...)
end)

-- UI Elements

-- Sitama Mode Section (бывший Auto Ragdoll)
TabMain:CreateSection("💥 Sitama Mode")

TabMain:CreateToggle({
	Name = "Sitama Mode",
	CurrentValue = false,
	Flag = "SitamaModeToggle",
	Callback = function(Value)
		toggleSitamaMode(Value)
	end
})

-- Swap Shovel Section
TabMain:CreateSection("🔨 Swap Shovel")

TabMain:CreateToggle({
	Name = "Swap Shovel",
	CurrentValue = false,
	Flag = "SwapShovelToggle",
	Callback = function(Value)
		toggleSwapShovel(Value)
	end
})

-- Fly Section
TabMain:CreateSection("🕊️ Fly")

TabMain:CreateToggle({
	Name = "Fly",
	CurrentValue = false,
	Flag = "FlyToggle",
	Callback = function(Value)
		toggleFly(Value)
	end
})

TabMain:CreateSlider({
	Name = "Fly Speed",
	Range = {10, 200},
	Increment = 5,
	Suffix = " studs/s",
	CurrentValue = 50,
	Flag = "FlySpeedSlider",
	Callback = function(Value)
		flySpeed = Value
	end
})

-- Nofog Section
TabMain:CreateSection("🌫️ Nofog")

TabMain:CreateToggle({
	Name = "Nofog",
	CurrentValue = false,
	Flag = "NofogToggle",
	Callback = function(Value)
		toggleNofog(Value)
	end
})

-- Raft Color Section
TabMain:CreateSection("🎨 Raft Color")

TabMain:CreateColorPicker({
	Name = "Raft Color",
	Color = Color3.new(0.4745098054409027, 0.22352942824363708, 0.07450980693101883),
	Flag = "RaftColorPicker",
	Callback = function(Value)
		selectedRaftColor = {
			R = Value.R,
			G = Value.G,
			B = Value.B
		}
	end
})

TabMain:CreateButton({
	Name = "Capture Raft Spawn",
	Callback = function()
		captureRaftData()
	end
})

TabMain:CreateButton({
	Name = "Spawn Raft with Color",
	Callback = function()
		spawnRaftWithColor()
	end
})

-- Dupe Variables
local dupeMoney500Enabled = false
local dupeMoney500Conn = nil

local dupeMoney600Enabled = false
local dupeMoney600Conn = nil

local dupeMoney1000Enabled = false
local dupeMoney1000Conn = nil

local dupeMoney1200Enabled = false
local dupeMoney1200Conn = nil

local dupeMoney1500Enabled = false
local dupeMoney1500Conn = nil

local dupeMoney2000Enabled = false
local dupeMoney2000Conn = nil

local dupeArchelonEnabled = false
local dupeArchelonConn = nil

local dupeMetriorhynchusEnabled = false
local dupeMetriorhynchusConn = nil

local dupeLiopleurodonEnabled = false
local dupeLiopleurodonConn = nil

local dupePlesiosaurusEnabled = false
local dupePlesiosaurusConn = nil

local dupeMosasaurusEnabled = false
local dupeMosasaurusConn = nil

local dupePaddleBoostEnabled = false
local dupePaddleBoostConn = nil

local dupe2xPaddleBoostEnabled = false
local dupe2xPaddleBoostConn = nil

-- Dupe Toggle Functions
local function toggleDupeMoney500(state)
	dupeMoney500Enabled = state
	if dupeMoney500Conn then
		dupeMoney500Conn:Disconnect()
		dupeMoney500Conn = nil
	end
	if dupeMoney500Enabled then
		dupeMoney500Conn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "Money",
					rarity = "Common",
					color = Color3.new(0.8313725590705872, 0.8313725590705872, 0.8313725590705872),
					value = 500,
					icon = "💰",
					displayName = "500 Cash"
				})
			end)
		end)
	end
end

local function toggleDupeMoney600(state)
	dupeMoney600Enabled = state
	if dupeMoney600Conn then
		dupeMoney600Conn:Disconnect()
		dupeMoney600Conn = nil
	end
	if dupeMoney600Enabled then
		dupeMoney600Conn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "Money",
					rarity = "Common",
					color = Color3.new(0.8313725590705872, 0.8313725590705872, 0.8313725590705872),
					value = 600,
					icon = "💰",
					displayName = "600 Cash"
				})
			end)
		end)
	end
end

local function toggleDupeMoney1000(state)
	dupeMoney1000Enabled = state
	if dupeMoney1000Conn then
		dupeMoney1000Conn:Disconnect()
		dupeMoney1000Conn = nil
	end
	if dupeMoney1000Enabled then
		dupeMoney1000Conn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "Money",
					rarity = "Uncommon",
					color = Color3.new(0.3921568691730499, 0.7843137383460999, 0.3921568691730499),
					value = 1000,
					icon = "💵",
					displayName = "1,000 Cash"
				})
			end)
		end)
	end
end

local function toggleDupeMoney1200(state)
	dupeMoney1200Enabled = state
	if dupeMoney1200Conn then
		dupeMoney1200Conn:Disconnect()
		dupeMoney1200Conn = nil
	end
	if dupeMoney1200Enabled then
		dupeMoney1200Conn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "Money",
					rarity = "Uncommon",
					color = Color3.new(0.3921568691730499, 0.7843137383460999, 0.3921568691730499),
					value = 1200,
					icon = "💵",
					displayName = "1,200 Cash"
				})
			end)
		end)
	end
end

local function toggleDupeMoney1500(state)
	dupeMoney1500Enabled = state
	if dupeMoney1500Conn then
		dupeMoney1500Conn:Disconnect()
		dupeMoney1500Conn = nil
	end
	if dupeMoney1500Enabled then
		dupeMoney1500Conn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "Money",
					rarity = "Uncommon",
					color = Color3.new(0.3921568691730499, 0.7843137383460999, 0.3921568691730499),
					value = 1500,
					icon = "💵",
					displayName = "1,500 Cash"
				})
			end)
		end)
	end
end

local function toggleDupeMoney2000(state)
	dupeMoney2000Enabled = state
	if dupeMoney2000Conn then
		dupeMoney2000Conn:Disconnect()
		dupeMoney2000Conn = nil
	end
	if dupeMoney2000Enabled then
		dupeMoney2000Conn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "Money",
					rarity = "Rare",
					color = Color3.new(0.3921568691730499, 0.5882353186607361, 1),
					value = 2000,
					icon = "💎",
					displayName = "2,000 Cash"
				})
			end)
		end)
	end
end

local function toggleDupeArchelon(state)
	dupeArchelonEnabled = state
	if dupeArchelonConn then
		dupeArchelonConn:Disconnect()
		dupeArchelonConn = nil
	end
	if dupeArchelonEnabled then
		dupeArchelonConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "SeaCreature",
					rarity = "Common",
					creatureId = 1,
					color = Color3.new(0.8313725590705872, 0.8313725590705872, 0.8313725590705872),
					value = 1,
					icon = "🐢",
					displayName = "Archelon"
				})
			end)
		end)
	end
end

local function toggleDupeMetriorhynchus(state)
	dupeMetriorhynchusEnabled = state
	if dupeMetriorhynchusConn then
		dupeMetriorhynchusConn:Disconnect()
		dupeMetriorhynchusConn = nil
	end
	if dupeMetriorhynchusEnabled then
		dupeMetriorhynchusConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "SeaCreature",
					rarity = "Rare",
					creatureId = 2,
					color = Color3.new(0.3921568691730499, 0.5882353186607361, 1),
					value = 2,
					icon = "🐊",
					displayName = "Metriorhynchus"
				})
			end)
		end)
	end
end

local function toggleDupeLiopleurodon(state)
	dupeLiopleurodonEnabled = state
	if dupeLiopleurodonConn then
		dupeLiopleurodonConn:Disconnect()
		dupeLiopleurodonConn = nil
	end
	if dupeLiopleurodonEnabled then
		dupeLiopleurodonConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "SeaCreature",
					rarity = "Rare",
					creatureId = 5,
					color = Color3.new(0.3921568691730499, 0.5882353186607361, 1),
					value = 5,
					icon = "🦎",
					displayName = "Liopleurodon"
				})
			end)
		end)
	end
end

local function toggleDupePlesiosaurus(state)
	dupePlesiosaurusEnabled = state
	if dupePlesiosaurusConn then
		dupePlesiosaurusConn:Disconnect()
		dupePlesiosaurusConn = nil
	end
	if dupePlesiosaurusEnabled then
		dupePlesiosaurusConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "SeaCreature",
					rarity = "Uncommon",
					creatureId = 7,
					color = Color3.new(0.3921568691730499, 0.7843137383460999, 0.3921568691730499),
					value = 7,
					icon = "🦕",
					displayName = "Plesiosaurus"
				})
			end)
		end)
	end
end

local function toggleDupeMosasaurus(state)
	dupeMosasaurusEnabled = state
	if dupeMosasaurusConn then
		dupeMosasaurusConn:Disconnect()
		dupeMosasaurusConn = nil
	end
	if dupeMosasaurusEnabled then
		dupeMosasaurusConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "SeaCreature",
					rarity = "Legendary",
					creatureId = 3,
					color = Color3.new(1, 0.7843137383460999, 0.196078434586525),
					value = 3,
					icon = "🦖",
					displayName = "Mosasaurus"
				})
			end)
		end)
	end
end

local function toggleDupePaddleBoost(state)
	dupePaddleBoostEnabled = state
	if dupePaddleBoostConn then
		dupePaddleBoostConn:Disconnect()
		dupePaddleBoostConn = nil
	end
	if dupePaddleBoostEnabled then
		dupePaddleBoostConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "PaddleBoost",
					rarity = "Common",
					value = 1,
					color = Color3.new(0.8313725590705872, 0.8313725590705872, 0.8313725590705872),
					icon = "⚡",
					displayName = "Paddle Boost"
				})
			end)
		end)
	end
end

local function toggleDupe2xPaddleBoost(state)
	dupe2xPaddleBoostEnabled = state
	if dupe2xPaddleBoostConn then
		dupe2xPaddleBoostConn:Disconnect()
		dupe2xPaddleBoostConn = nil
	end
	if dupe2xPaddleBoostEnabled then
		dupe2xPaddleBoostConn = RunService.Heartbeat:Connect(function()
			pcall(function()
				ReplicatedStorage:WaitForChild("GrantReward"):InvokeServer({
					type = "PaddleBoost",
					rarity = "Epic",
					value = 2,
					color = Color3.new(0.7843137383460999, 0.3921568691730499, 1),
					icon = "⚡⚡",
					displayName = "2x Paddle Boost"
				})
			end)
		end)
	end
end

-- Dupe UI Section
TabMain:CreateSection("💎 Dupe Rewards")

TabMain:CreateToggle({
	Name = "💰 Dupe 500 Cash",
	CurrentValue = false,
	Flag = "Dupe500Toggle",
	Callback = function(Value)
		toggleDupeMoney500(Value)
	end
})

TabMain:CreateToggle({
	Name = "💰 Dupe 600 Cash",
	CurrentValue = false,
	Flag = "Dupe600Toggle",
	Callback = function(Value)
		toggleDupeMoney600(Value)
	end
})

TabMain:CreateToggle({
	Name = "💵 Dupe 1,000 Cash",
	CurrentValue = false,
	Flag = "Dupe1000Toggle",
	Callback = function(Value)
		toggleDupeMoney1000(Value)
	end
})

TabMain:CreateToggle({
	Name = "💵 Dupe 1,200 Cash",
	CurrentValue = false,
	Flag = "Dupe1200Toggle",
	Callback = function(Value)
		toggleDupeMoney1200(Value)
	end
})

TabMain:CreateToggle({
	Name = "💵 Dupe 1,500 Cash",
	CurrentValue = false,
	Flag = "Dupe1500Toggle",
	Callback = function(Value)
		toggleDupeMoney1500(Value)
	end
})

TabMain:CreateToggle({
	Name = "💎 Dupe 2,000 Cash",
	CurrentValue = false,
	Flag = "Dupe2000Toggle",
	Callback = function(Value)
		toggleDupeMoney2000(Value)
	end
})

TabMain:CreateToggle({
	Name = "🐢 Dupe Archelon",
	CurrentValue = false,
	Flag = "DupeArchelonToggle",
	Callback = function(Value)
		toggleDupeArchelon(Value)
	end
})

TabMain:CreateToggle({
	Name = "🐊 Dupe Metriorhynchus",
	CurrentValue = false,
	Flag = "DupeMetriorhynchusToggle",
	Callback = function(Value)
		toggleDupeMetriorhynchus(Value)
	end
})

TabMain:CreateToggle({
	Name = "🦎 Dupe Liopleurodon",
	CurrentValue = false,
	Flag = "DupeLiopleurodonToggle",
	Callback = function(Value)
		toggleDupeLiopleurodon(Value)
	end
})

TabMain:CreateToggle({
	Name = "🦕 Dupe Plesiosaurus",
	CurrentValue = false,
	Flag = "DupePlesiosaurusToggle",
	Callback = function(Value)
		toggleDupePlesiosaurus(Value)
	end
})

TabMain:CreateToggle({
	Name = "🦖 Dupe Mosasaurus",
	CurrentValue = false,
	Flag = "DupeMosasaurusToggle",
	Callback = function(Value)
		toggleDupeMosasaurus(Value)
	end
})

TabMain:CreateToggle({
	Name = "⚡ Dupe Paddle Boost",
	CurrentValue = false,
	Flag = "DupePaddleBoostToggle",
	Callback = function(Value)
		toggleDupePaddleBoost(Value)
	end
})

TabMain:CreateToggle({
	Name = "⚡⚡ Dupe 2x Paddle Boost",
	CurrentValue = false,
	Flag = "Dupe2xPaddleBoostToggle",
	Callback = function(Value)
		toggleDupe2xPaddleBoost(Value)
	end
})

-- Events
player.CharacterAdded:Connect(function()
	-- Пересоздаём fly при респавне
	if flyEnabled then
		task.wait(0.5)
		startFly()
	end
	
	if sitamaModeEnabled then
		toggleSitamaMode(true)
	end
	if swapShovelEnabled then
		toggleSwapShovel(true)
	end
end)