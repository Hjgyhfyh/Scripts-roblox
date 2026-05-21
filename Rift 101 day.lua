local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer

local Window = Rayfield:CreateWindow({
	Name = "tg: @sigmatik323",
	LoadingTitle = "tg: @sigmatik323",
	LoadingSubtitle = "by sigmatik323",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "Rift 101 day"
	},
	Discord = {
		Enabled = false,
		Invite = "",
		RememberJoins = false
	},
	KeySystem = false
})

local TabMovement = Window:CreateTab("🏃 Movement", 4483362458)
local TabCombat = Window:CreateTab("⚔️ Combat", 4483362458)
local TabSurvival = Window:CreateTab("🧰 Survival", 4483362458)
local TabVisuals = Window:CreateTab("✨ Visuals", 4483362458)
local TabTeleport = Window:CreateTab("🧭 Teleport", 4483362458)
local TabMisc = Window:CreateTab("🛡 Misc", 4483362458)

local function getChar()
	local character = LocalPlayer.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, root
end

local function getCamera()
	return workspace.CurrentCamera
end

local flyEnabled = false
local flySpeed = 60
local flyConn = nil
local flyGyro = nil
local flyVelocity = nil

local swimEnabled = false
local swimSpeed = 50
local swimConn = nil
local swimGyro = nil
local swimVelocity = nil

local noclipEnabled = false
local noclipConn = nil

local walkSpeed = 16
local jumpPower = 50

local tpClickEnabled = false
local tpClickKey = Enum.KeyCode.Unknown

local fullbrightEnabled = false
local noFogEnabled = false
local originalLighting = {}
local originalFog = {}

local playerEspEnabled = false
local playerEspColor = Color3.fromRGB(255, 0, 0)
local playerEspObjects = {}

local itemsEspEnabled = false
local itemsEspColor = Color3.fromRGB(0, 200, 255)
local itemsEspObjects = {}

local mobsEspEnabled = false
local mobsEspColor = Color3.fromRGB(255, 170, 0)
local mobsEspObjects = {}

local rareItemsEspEnabled = false
local rareItemsEspColor = Color3.fromRGB(255, 230, 100)
local rareItemsEspObjects = {}

local bossEspEnabled = false
local bossEspColor = Color3.fromRGB(200, 80, 255)
local bossEspObjects = {}

local autoAttackMobsEnabled = false
local autoAttackMobsConn = nil
local mobHitCounters = {}

local timeOfDayValue = 14
local lockTimeEnabled = false

local autoCollectEnabled = false
local autoCollectRadius = 60
local autoCollectDelay = 0.2
local autoCollectLast = 0
local autoCollectItemCooldown = 1.2
local autoCollectItemLast = {}

local sharkAlertEnabled = false
local lastSharkAlert = 0
local sharkAlertCooldown = 8

local healthLabel = nil
local hungerLabel = nil
local thirstLabel = nil
local dayLabel = nil

local statRefs = {
	Hunger = nil,
	Thirst = nil,
	Day = nil
}

local statTextRefs = {
	Hunger = nil,
	Thirst = nil,
	Day = nil
}

local carryablesFolders = {}
local carryablesLastRefresh = 0
local carryablesRefreshInterval = 5

local teleportTarget = nil
local teleportDropdown = nil

local function makeHighlight(color)
	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.5
	hl.OutlineTransparency = 0
	hl.FillColor = color
	hl.OutlineColor = color
	return hl
end

local function applyMovementStats()
	local _, humanoid = getChar()
	if humanoid then
		humanoid.WalkSpeed = walkSpeed
		humanoid.JumpPower = jumpPower
	end
end

local function startFly()
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	local character, humanoid, root = getChar()
	local camera = getCamera()
	if not character or not humanoid or not root or not camera then
		return
	end
	humanoid.PlatformStand = true
	if flyGyro then flyGyro:Destroy() end
	if flyVelocity then flyVelocity:Destroy() end
	flyGyro = Instance.new("BodyGyro")
	flyGyro.P = 9e4
	flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	flyGyro.CFrame = camera.CFrame
	flyGyro.Parent = root
	flyVelocity = Instance.new("BodyVelocity")
	flyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	flyVelocity.Velocity = Vector3.zero
	flyVelocity.Parent = root
	flyConn = RunService.Heartbeat:Connect(function()
		local cam = getCamera()
		if not cam or not flyGyro or not flyVelocity then
			return
		end
		flyGyro.CFrame = cam.CFrame
		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			dir += cam.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			dir -= cam.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			dir -= cam.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			dir += cam.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			dir += Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			dir -= Vector3.new(0, 1, 0)
		end
		if dir.Magnitude > 0 then
			dir = dir.Unit * flySpeed
		end
		flyVelocity.Velocity = dir
	end)
end

local function stopFly()
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	local _, humanoid = getChar()
	if humanoid then
		humanoid.PlatformStand = false
	end
	if flyGyro then flyGyro:Destroy() flyGyro = nil end
	if flyVelocity then flyVelocity:Destroy() flyVelocity = nil end
end

local function startSwim()
	if swimConn then
		swimConn:Disconnect()
		swimConn = nil
	end
	local character, humanoid, root = getChar()
	local camera = getCamera()
	if not character or not humanoid or not root or not camera then
		return
	end
	if swimGyro then swimGyro:Destroy() end
	if swimVelocity then swimVelocity:Destroy() end
	swimGyro = Instance.new("BodyGyro")
	swimGyro.P = 9e4
	swimGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	swimGyro.CFrame = camera.CFrame
	swimGyro.Parent = root
	swimVelocity = Instance.new("BodyVelocity")
	swimVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	swimVelocity.Velocity = Vector3.zero
	swimVelocity.Parent = root
	swimConn = RunService.Heartbeat:Connect(function()
		local cam = getCamera()
		if not cam or not swimGyro or not swimVelocity then
			return
		end
		swimGyro.CFrame = cam.CFrame
		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			dir += cam.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			dir -= cam.CFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			dir -= cam.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			dir += cam.CFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			dir += Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			dir -= Vector3.new(0, 1, 0)
		end
		if dir.Magnitude > 0 then
			dir = dir.Unit * swimSpeed
		end
		swimVelocity.Velocity = dir
	end)
end

local function stopSwim()
	if swimConn then
		swimConn:Disconnect()
		swimConn = nil
	end
	if swimGyro then swimGyro:Destroy() swimGyro = nil end
	if swimVelocity then swimVelocity:Destroy() swimVelocity = nil end
end

local function startNoclip()
	if noclipConn then
		noclipConn:Disconnect()
	end
	noclipConn = RunService.Stepped:Connect(function()
		local character = LocalPlayer.Character
		if not character then
			return
		end
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
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

local function enableFullbright()
	originalLighting.Ambient = Lighting.Ambient
	originalLighting.Brightness = Lighting.Brightness
	originalLighting.OutdoorAmbient = Lighting.OutdoorAmbient
	Lighting.Ambient = Color3.fromRGB(255, 255, 255)
	Lighting.Brightness = 2
	Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
end

local function disableFullbright()
	if originalLighting.Ambient then Lighting.Ambient = originalLighting.Ambient end
	if originalLighting.Brightness then Lighting.Brightness = originalLighting.Brightness end
	if originalLighting.OutdoorAmbient then Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient end
end

local function enableNoFog()
	originalFog.FogStart = Lighting.FogStart
	originalFog.FogEnd = Lighting.FogEnd
	Lighting.FogStart = 100000
	Lighting.FogEnd = 100000
end

local function disableNoFog()
	if originalFog.FogStart then Lighting.FogStart = originalFog.FogStart end
	if originalFog.FogEnd then Lighting.FogEnd = originalFog.FogEnd end
end

local function clearPlayerESP()
	for p, hl in pairs(playerEspObjects) do
		if hl and hl.Parent then
			hl:Destroy()
		end
		playerEspObjects[p] = nil
	end
end

local function clearItemsESP()
	for item, hl in pairs(itemsEspObjects) do
		if hl and hl.Parent then
			hl:Destroy()
		end
		itemsEspObjects[item] = nil
	end
end

local function clearMobsESP()
	for mob, hl in pairs(mobsEspObjects) do
		if hl and hl.Parent then
			hl:Destroy()
		end
		mobsEspObjects[mob] = nil
	end
end

local function clearRareItemsESP()
	for item, hl in pairs(rareItemsEspObjects) do
		if hl and hl.Parent then
			hl:Destroy()
		end
		rareItemsEspObjects[item] = nil
	end
end

local function clearBossESP()
	for mob, hl in pairs(bossEspObjects) do
		if hl and hl.Parent then
			hl:Destroy()
		end
		bossEspObjects[mob] = nil
	end
end

local function updatePlayerESP()
	local validPlayers = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local c = p.Character
			if c and c.Parent then
				local hum = c:FindFirstChildOfClass("Humanoid")
				local hrp = c:FindFirstChild("HumanoidRootPart")
				if hum and hrp then
					validPlayers[p] = true
					local hl = playerEspObjects[p]
					if not hl or not hl.Parent then
						hl = makeHighlight(playerEspColor)
						hl.Parent = workspace
						playerEspObjects[p] = hl
					end
					hl.Adornee = c
					hl.FillColor = playerEspColor
					hl.OutlineColor = playerEspColor
				end
			end
		end
	end
	for p, hl in pairs(playerEspObjects) do
		if not validPlayers[p] then
			if hl and hl.Parent then
				hl:Destroy()
			end
			playerEspObjects[p] = nil
		end
	end
end

local function updateItemsESP()
	if #carryablesFolders == 0 then
		clearItemsESP()
		return
	end
	local validItems = {}
	for _, folder in ipairs(carryablesFolders) do
		for _, item in ipairs(folder:GetChildren()) do
			if item:IsA("Model") or item:IsA("BasePart") then
				validItems[item] = true
				local hl = itemsEspObjects[item]
				if not hl or not hl.Parent then
					hl = makeHighlight(itemsEspColor)
					hl.Parent = workspace
					itemsEspObjects[item] = hl
				end
				hl.Adornee = item
				hl.FillColor = itemsEspColor
				hl.OutlineColor = itemsEspColor
			end
		end
	end
	for item, hl in pairs(itemsEspObjects) do
		if not validItems[item] then
			if hl and hl.Parent then
				hl:Destroy()
			end
			itemsEspObjects[item] = nil
		end
	end
end

local function updateMobsESP()
	local debris = workspace:FindFirstChild("_Debris")
	local folder = debris and debris:FindFirstChild("NPCs")
	if not folder then
		clearMobsESP()
		return
	end
	local validMobs = {}
	for _, mob in ipairs(folder:GetChildren()) do
		if mob:IsA("Model") or mob:IsA("BasePart") then
			validMobs[mob] = true
			local hl = mobsEspObjects[mob]
			if not hl or not hl.Parent then
				hl = makeHighlight(mobsEspColor)
				hl.Parent = workspace
				mobsEspObjects[mob] = hl
			end
			hl.Adornee = mob
			hl.FillColor = mobsEspColor
			hl.OutlineColor = mobsEspColor
		end
	end
	for mob, hl in pairs(mobsEspObjects) do
		if not validMobs[mob] then
			if hl and hl.Parent then
				hl:Destroy()
			end
			mobsEspObjects[mob] = nil
		end
	end
end

local function isRareItemName(name)
	local n = string.lower(name)
	return n:find("barrel") or n:find("crate") or n:find("gift") or n:find("chest") or n:find("totem")
		or n:find("keycard") or n:find("key card") or n:find("crystal") or n:find("present")
		or n:find("supply") or n:find("loot") or n:find("box")
end

local function isRareByAttribute(item)
	local rarity = item:GetAttribute("Rarity") or item:GetAttribute("rarity")
	if type(rarity) == "string" then
		local r = string.lower(rarity)
		return r:find("rare") or r:find("epic") or r:find("legendary") or r:find("myth")
	end
	return false
end

local function updateRareItemsESP()
	if #carryablesFolders == 0 then
		clearRareItemsESP()
		return
	end
	local validItems = {}
	for _, folder in ipairs(carryablesFolders) do
		for _, item in ipairs(folder:GetChildren()) do
			if item:IsA("Model") or item:IsA("BasePart") then
				if isRareItemName(item.Name) or isRareByAttribute(item) then
					validItems[item] = true
					local hl = rareItemsEspObjects[item]
					if not hl or not hl.Parent then
						hl = makeHighlight(rareItemsEspColor)
						hl.Parent = workspace
						rareItemsEspObjects[item] = hl
					end
					hl.Adornee = item
					hl.FillColor = rareItemsEspColor
					hl.OutlineColor = rareItemsEspColor
				end
			end
		end
	end
	for item, hl in pairs(rareItemsEspObjects) do
		if not validItems[item] then
			if hl and hl.Parent then
				hl:Destroy()
			end
			rareItemsEspObjects[item] = nil
		end
	end
end

local function isBossName(name)
	local n = string.lower(name)
	return n:find("kraken") or n:find("octopus") or n:find("boss") or n:find("pirate") or n:find("raider") or n:find("shark")
end

local function updateBossESP()
	local folder = getMobsFolder()
	if not folder then
		clearBossESP()
		return
	end
	local validMobs = {}
	for _, mob in ipairs(folder:GetChildren()) do
		if (mob:IsA("Model") or mob:IsA("BasePart")) and isBossName(mob.Name) then
			validMobs[mob] = true
			local hl = bossEspObjects[mob]
			if not hl or not hl.Parent then
				hl = makeHighlight(bossEspColor)
				hl.Parent = workspace
				bossEspObjects[mob] = hl
			end
			hl.Adornee = mob
			hl.FillColor = bossEspColor
			hl.OutlineColor = bossEspColor
		end
	end
	for mob, hl in pairs(bossEspObjects) do
		if not validMobs[mob] then
			if hl and hl.Parent then
				hl:Destroy()
			end
			bossEspObjects[mob] = nil
		end
	end
end

local function getMobsFolder()
	local debris = workspace:FindFirstChild("_Debris")
	return debris and debris:FindFirstChild("NPCs")
end

local function autoAttackMobsStep()
	local folder = getMobsFolder()
	if not folder then
		return
	end
	local axeHit = ReplicatedStorage:FindFirstChild("AxeHit")
	if not axeHit then
		return
	end
	local activeMobs = {}
	for _, mob in ipairs(folder:GetChildren()) do
		if mob:IsA("Model") or mob:IsA("BasePart") then
			activeMobs[mob] = true
			local hitIndex = (mobHitCounters[mob] or 0) + 1
			mobHitCounters[mob] = hitIndex
			local args = {
				Instance.new("Model", nil),
				mob.Name,
				hitIndex
			}
			if axeHit:IsA("RemoteEvent") then
				axeHit:FireServer(unpack(args))
			elseif axeHit:IsA("RemoteFunction") then
				axeHit:InvokeServer(unpack(args))
			end
		end
	end
	for mob, _ in pairs(mobHitCounters) do
		if not activeMobs[mob] or mob.Parent ~= folder then
			mobHitCounters[mob] = nil
		end
	end
end

local function refreshCarryables()
	local now = time()
	if (now - carryablesLastRefresh) < carryablesRefreshInterval then
		return
	end
	carryablesLastRefresh = now
	local folders = {}
	local directNames = {
		"_Carryables",
		"Carryables",
		"FloatingItems",
		"Floating",
		"Loot",
		"Drops",
		"Items"
	}
	for _, name in ipairs(directNames) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(folders, f)
		end
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Model") then
			local n = string.lower(child.Name)
			if n:find("carry") or n:find("float") or n:find("loot") or n:find("drop") then
				table.insert(folders, child)
			end
		end
	end
	carryablesFolders = folders
end

local function getItemPart(item)
	if item:IsA("BasePart") then
		return item
	end
	if item:IsA("Model") then
		if item.PrimaryPart then
			return item.PrimaryPart
		end
		for _, part in ipairs(item:GetDescendants()) do
			if part:IsA("BasePart") then
				return part
			end
		end
	end
	return nil
end

local function tryPickupItem(item, part, root)
	local now = time()
	local last = autoCollectItemLast[item]
	if last and (now - last) < autoCollectItemCooldown then
		return
	end
	for _, desc in ipairs(item:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			autoCollectItemLast[item] = now
			pcall(function()
				fireproximityprompt(desc)
			end)
			return
		end
		if desc:IsA("ClickDetector") then
			autoCollectItemLast[item] = now
			pcall(function()
				fireclickdetector(desc)
			end)
			return
		end
	end
	if part and root then
		autoCollectItemLast[item] = now
		pcall(function()
			firetouchinterest(root, part, 0)
			firetouchinterest(root, part, 1)
		end)
	end
end

local function autoCollectStep()
	local _, _, root = getChar()
	if #carryablesFolders == 0 or not root then
		return
	end
	for _, folder in ipairs(carryablesFolders) do
		for _, item in ipairs(folder:GetChildren()) do
			local part = getItemPart(item)
			if part and (part.Position - root.Position).Magnitude <= autoCollectRadius then
				tryPickupItem(item, part, root)
			end
		end
	end
end

local function findValueByNames(root, names)
	if not root then
		return nil
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("NumberValue") or desc:IsA("IntValue") then
			for _, name in ipairs(names) do
				if string.lower(desc.Name) == name then
					return desc
				end
			end
		end
	end
	return nil
end

local function findTextByNames(root, names)
	if not root then
		return nil
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") then
			local t = desc.Text
			if t and t ~= "" then
				local lt = string.lower(t)
				for _, name in ipairs(names) do
					if lt:find(name) then
						return desc
					end
				end
			end
		end
	end
	return nil
end

local function parseNumberFromText(text)
	local num = string.match(text, "(%d+)")
	if num then
		return tonumber(num)
	end
	return nil
end

local function refreshStatRefs()
	local roots = {
		LocalPlayer,
		LocalPlayer.Character,
		LocalPlayer:FindFirstChild("PlayerGui"),
		ReplicatedStorage,
		workspace
	}
	local hungerNames = {"hunger", "food"}
	local thirstNames = {"thirst", "water", "hydration"}
	local dayNames = {"day", "days", "daycount", "daycounter"}
	local function findInRoots(names)
		for _, root in ipairs(roots) do
			local val = findValueByNames(root, names)
			if val then
				return val
			end
		end
		return nil
	end
	local function findTextInRoots(names)
		for _, root in ipairs(roots) do
			local val = findTextByNames(root, names)
			if val then
				return val
			end
		end
		return nil
	end
	statRefs.Hunger = findInRoots(hungerNames)
	statRefs.Thirst = findInRoots(thirstNames)
	statRefs.Day = findInRoots(dayNames)
	statTextRefs.Hunger = findTextInRoots(hungerNames)
	statTextRefs.Thirst = findTextInRoots(thirstNames)
	statTextRefs.Day = findTextInRoots(dayNames)
end

local function updateStatLabels()
	local _, humanoid = getChar()
	local healthText = "Health: N/A"
	if humanoid then
		healthText = string.format("Health: %d/%d", math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
	end
	if healthLabel then
		healthLabel:Set(healthText)
	end
	if hungerLabel then
		if statRefs.Hunger then
			hungerLabel:Set(string.format("Hunger: %d", math.floor(statRefs.Hunger.Value)))
		elseif statTextRefs.Hunger then
			local n = parseNumberFromText(statTextRefs.Hunger.Text)
			if n then
				hungerLabel:Set(string.format("Hunger: %d", n))
			else
				hungerLabel:Set("Hunger: N/A")
			end
		else
			hungerLabel:Set("Hunger: N/A")
		end
	end
	if thirstLabel then
		if statRefs.Thirst then
			thirstLabel:Set(string.format("Thirst: %d", math.floor(statRefs.Thirst.Value)))
		elseif statTextRefs.Thirst then
			local n = parseNumberFromText(statTextRefs.Thirst.Text)
			if n then
				thirstLabel:Set(string.format("Thirst: %d", n))
			else
				thirstLabel:Set("Thirst: N/A")
			end
		else
			thirstLabel:Set("Thirst: N/A")
		end
	end
	if dayLabel then
		if statRefs.Day then
			dayLabel:Set(string.format("Day: %d", math.floor(statRefs.Day.Value)))
		elseif statTextRefs.Day then
			local n = parseNumberFromText(statTextRefs.Day.Text)
			if n then
				dayLabel:Set(string.format("Day: %d", n))
			else
				dayLabel:Set("Day: N/A")
			end
		else
			dayLabel:Set("Day: N/A")
		end
	end
end

local function findLocalRaft()
	local candidates = {}
	local function addModel(model)
		if model and model:IsA("Model") then
			table.insert(candidates, model)
		end
	end
	for _, tag in ipairs({"Raft", "PlayerRaft", "Rafts"}) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			addModel(model)
		end
	end
	local directFolders = {"Rafts", "Boats", "PlayersRafts", "PlayerRafts"}
	for _, name in ipairs(directFolders) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			for _, model in ipairs(folder:GetChildren()) do
				addModel(model)
			end
		end
	end
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") then
			local n = string.lower(obj.Name)
			if n:find("raft") or n:find("boat") then
				addModel(obj)
			end
		end
	end
	local _, _, root = getChar()
	local bestModel = nil
	local bestDist = math.huge
	for _, obj in ipairs(candidates) do
		local owner = obj:FindFirstChild("Owner") or obj:FindFirstChild("owner")
		if owner and owner:IsA("ObjectValue") and owner.Value == LocalPlayer then
			return obj
		end
		local ownerId = obj:GetAttribute("OwnerId") or obj:GetAttribute("ownerId") or obj:GetAttribute("UserId")
		if ownerId and ownerId == LocalPlayer.UserId then
			return obj
		end
		if root then
			local pos = getModelCenter(obj)
			local dist = (pos - root.Position).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestModel = obj
			end
		end
	end
	return bestModel
end

local function getModelCenter(model)
	if model.PrimaryPart then
		return model.PrimaryPart.Position
	end
	local cf, size = model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

local function sharkAlertStep()
	local folder = getMobsFolder()
	if not folder then
		return
	end
	local now = time()
	if now - lastSharkAlert < sharkAlertCooldown then
		return
	end
	for _, mob in ipairs(folder:GetChildren()) do
		if mob:IsA("Model") or mob:IsA("BasePart") then
			local n = string.lower(mob.Name)
			if n:find("shark") or n:find("kraken") or n:find("octopus") then
				lastSharkAlert = now
				Rayfield:Notify({
					Title = "Warning",
					Content = "Sea threat detected!",
					Duration = 3
				})
				break
			end
		end
	end
end

local function getPlayerOptions()
	local options = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			table.insert(options, p.Name)
		end
	end
	if #options == 0 then
		table.insert(options, "None")
	end
	return options
end

local function findPlayerByName(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name == name then
			return p
		end
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

TabMovement:CreateSection("Movement 🏃")

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
	Range = {20, 150},
	Increment = 1,
	Suffix = "Speed",
	CurrentValue = flySpeed,
	Flag = "FlySpeed",
	Callback = function(v)
		flySpeed = v
	end
})

TabMovement:CreateSlider({
	Name = "Walk Speed",
	Range = {5, 100},
	Increment = 1,
	Suffix = "Speed",
	CurrentValue = walkSpeed,
	Flag = "WalkSpeed",
	Callback = function(v)
		walkSpeed = v
		applyMovementStats()
	end
})

TabMovement:CreateSlider({
	Name = "Jump Power",
	Range = {20, 150},
	Increment = 1,
	Suffix = "Power",
	CurrentValue = jumpPower,
	Flag = "JumpPower",
	Callback = function(v)
		jumpPower = v
		applyMovementStats()
	end
})

TabMovement:CreateSection("Air Swim 🌊")

TabMovement:CreateToggle({
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

TabMovement:CreateSlider({
	Name = "Swim Speed",
	Range = {10, 150},
	Increment = 1,
	Suffix = "Speed",
	CurrentValue = swimSpeed,
	Flag = "SwimSpeed",
	Callback = function(v)
		swimSpeed = v
	end
})

TabMovement:CreateSection("Collision 🧱")

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

TabCombat:CreateSection("Auto Attack ⚔️")

TabCombat:CreateToggle({
	Name = "Auto Attack Mobs",
	CurrentValue = false,
	Flag = "AutoAttackMobs",
	Callback = function(v)
		autoAttackMobsEnabled = v
		if v then
			if autoAttackMobsConn then
				autoAttackMobsConn:Disconnect()
			end
			autoAttackMobsConn = RunService.Heartbeat:Connect(function()
				if autoAttackMobsEnabled then
					autoAttackMobsStep()
				end
			end)
		else
			if autoAttackMobsConn then
				autoAttackMobsConn:Disconnect()
				autoAttackMobsConn = nil
			end
		end
	end
})

TabSurvival:CreateSection("Status 🧠")

healthLabel = TabSurvival:CreateLabel("Health: N/A")
hungerLabel = TabSurvival:CreateLabel("Hunger: N/A")
thirstLabel = TabSurvival:CreateLabel("Thirst: N/A")
dayLabel = TabSurvival:CreateLabel("Day: N/A")

TabSurvival:CreateSection("Resources 🧲")

TabSurvival:CreateToggle({
	Name = "Auto Collect Items",
	CurrentValue = false,
	Flag = "AutoCollectItems",
	Callback = function(v)
		autoCollectEnabled = v
	end
})

TabSurvival:CreateSlider({
	Name = "Collect Radius",
	Range = {10, 200},
	Increment = 1,
	Suffix = "Studs",
	CurrentValue = autoCollectRadius,
	Flag = "CollectRadius",
	Callback = function(v)
		autoCollectRadius = v
	end
})

TabSurvival:CreateSection("Raft 🛶")

TabSurvival:CreateButton({
	Name = "Teleport to Raft",
	Callback = function()
		local raft = findLocalRaft()
		local _, _, root = getChar()
		if raft and root then
			local pos = getModelCenter(raft)
			root.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
		end
	end
})

TabSurvival:CreateSection("Alerts 🚨")

TabSurvival:CreateToggle({
	Name = "Shark Alert",
	CurrentValue = false,
	Flag = "SharkAlert",
	Callback = function(v)
		sharkAlertEnabled = v
	end
})

TabVisuals:CreateSection("Player ESP 👥")

TabVisuals:CreateToggle({
	Name = "Player ESP",
	CurrentValue = false,
	Flag = "PlayerESP",
	Callback = function(v)
		playerEspEnabled = v
		if not v then
			clearPlayerESP()
		end
	end
})

TabVisuals:CreateColorPicker({
	Name = "Player ESP Color",
	Color = playerEspColor,
	Flag = "PlayerESPColor",
	Callback = function(c)
		playerEspColor = c
	end
})

TabVisuals:CreateSection("Items ESP 📦")

TabVisuals:CreateToggle({
	Name = "ESP Items",
	CurrentValue = false,
	Flag = "ESPItems",
	Callback = function(v)
		itemsEspEnabled = v
		if not v then
			clearItemsESP()
		end
	end
})

TabVisuals:CreateColorPicker({
	Name = "Items ESP Color",
	Color = itemsEspColor,
	Flag = "ItemsESPColor",
	Callback = function(c)
		itemsEspColor = c
	end
})

TabVisuals:CreateSection("Rare Items ESP 💎")

TabVisuals:CreateToggle({
	Name = "ESP Rare Items",
	CurrentValue = false,
	Flag = "ESPRareItems",
	Callback = function(v)
		rareItemsEspEnabled = v
		if not v then
			clearRareItemsESP()
		end
	end
})

TabVisuals:CreateColorPicker({
	Name = "Rare Items ESP Color",
	Color = rareItemsEspColor,
	Flag = "RareItemsESPColor",
	Callback = function(c)
		rareItemsEspColor = c
	end
})

TabVisuals:CreateSection("Mobs ESP 👾")

TabVisuals:CreateToggle({
	Name = "ESP Mobs",
	CurrentValue = false,
	Flag = "ESPMobs",
	Callback = function(v)
		mobsEspEnabled = v
		if not v then
			clearMobsESP()
		end
	end
})

TabVisuals:CreateColorPicker({
	Name = "Mobs ESP Color",
	Color = mobsEspColor,
	Flag = "MobsESPColor",
	Callback = function(c)
		mobsEspColor = c
	end
})

TabVisuals:CreateSection("Boss ESP 🐙")

TabVisuals:CreateToggle({
	Name = "ESP Boss",
	CurrentValue = false,
	Flag = "ESPBoss",
	Callback = function(v)
		bossEspEnabled = v
		if not v then
			clearBossESP()
		end
	end
})

TabVisuals:CreateColorPicker({
	Name = "Boss ESP Color",
	Color = bossEspColor,
	Flag = "BossESPColor",
	Callback = function(c)
		bossEspColor = c
	end
})

TabVisuals:CreateSection("World 🌤️")

TabVisuals:CreateSlider({
	Name = "Time of Day",
	Range = {0, 24},
	Increment = 1,
	Suffix = "h",
	CurrentValue = timeOfDayValue,
	Flag = "TimeOfDay",
	Callback = function(v)
		timeOfDayValue = v
		Lighting.ClockTime = timeOfDayValue
	end
})

TabVisuals:CreateToggle({
	Name = "FullBright",
	CurrentValue = false,
	Flag = "FullBright",
	Callback = function(v)
		fullbrightEnabled = v
		if v then
			enableFullbright()
		else
			disableFullbright()
		end
	end
})

TabVisuals:CreateToggle({
	Name = "No Fog",
	CurrentValue = false,
	Flag = "NoFog",
	Callback = function(v)
		noFogEnabled = v
		if v then
			enableNoFog()
		else
			disableNoFog()
		end
	end
})

TabVisuals:CreateToggle({
	Name = "Lock Time",
	CurrentValue = false,
	Flag = "LockTime",
	Callback = function(v)
		lockTimeEnabled = v
		if v then
			Lighting.ClockTime = timeOfDayValue
		end
	end
})

TabTeleport:CreateSection("Players 🧭")

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
		local _, _, root = getChar()
		if teleportTarget and teleportTarget.Character and root then
			local tRoot = teleportTarget.Character:FindFirstChild("HumanoidRootPart")
			if tRoot then
				root.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, 3, 0))
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

TabTeleport:CreateSection("TP Click 🖱️")

TabTeleport:CreateKeybind({
	Name = "TP Click Key",
	CurrentKeybind = "None",
	Flag = "TPClickKey",
	Callback = function(key)
		if typeof(key) == "EnumItem" then
			tpClickKey = key
		else
			tpClickKey = Enum.KeyCode.Unknown
		end
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

TabMisc:CreateSection("Anti AFK ⏳")

TabMisc:CreateLabel("Anti AFK is always active")

RunService.Heartbeat:Connect(function()
	refreshCarryables()
	if playerEspEnabled then
		updatePlayerESP()
	else
		if next(playerEspObjects) ~= nil then
			clearPlayerESP()
		end
	end
	if itemsEspEnabled then
		updateItemsESP()
	else
		if next(itemsEspObjects) ~= nil then
			clearItemsESP()
		end
	end
	if mobsEspEnabled then
		updateMobsESP()
	else
		if next(mobsEspObjects) ~= nil then
			clearMobsESP()
		end
	end
	if rareItemsEspEnabled then
		updateRareItemsESP()
	else
		if next(rareItemsEspObjects) ~= nil then
			clearRareItemsESP()
		end
	end
	if bossEspEnabled then
		updateBossESP()
	else
		if next(bossEspObjects) ~= nil then
			clearBossESP()
		end
	end
	if lockTimeEnabled then
		Lighting.ClockTime = timeOfDayValue
	end
	if autoCollectEnabled and (time() - autoCollectLast) >= autoCollectDelay then
		autoCollectLast = time()
		autoCollectStep()
	end
	if sharkAlertEnabled then
		sharkAlertStep()
	end
	updateStatLabels()
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if tpClickEnabled and input.KeyCode == tpClickKey then
		local mouse = LocalPlayer:GetMouse()
		local _, _, root = getChar()
		if root and mouse.Hit then
			root.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
		end
	end
end)

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
	local hl = playerEspObjects[p]
	if hl and hl.Parent then
		hl:Destroy()
		playerEspObjects[p] = nil
	end
	refreshDropdownOptions()
end)

LocalPlayer.CharacterAdded:Connect(function()
	applyMovementStats()
	if flyEnabled then startFly() end
	if swimEnabled then startSwim() end
	if noclipEnabled then startNoclip() end
end)

applyMovementStats()
Lighting.ClockTime = timeOfDayValue
refreshDropdownOptions()
refreshStatRefs()

task.spawn(function()
	while true do
		refreshStatRefs()
		task.wait(5)
	end
end)
