local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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

local TabMovement = Window:CreateTab("🏃 Movement", 4483362458)
local TabCombat = Window:CreateTab("⚔️ Combat", 4483362458)

local player = Players.LocalPlayer

-- Variables
local flyEnabled = false
local flySpeed = 60
local flyConn = nil
local flyGyro = nil
local flyVelocity = nil

local autoSpinEnabled = false
local autoSpinConn = nil

local noclipEnabled = false
local noclipLoop = nil

local trollEnabled = false
local selectedTrollTarget = nil
local trollConn = nil

local predictionEnabled = false
local predictionConn = nil
local predictionFolder = nil
local physicsMonitorConn = nil

-- Slide Distance Display
local slideDistanceEnabled = false
local slideDistanceGui = nil
local slideDistanceConn = nil
local slideDistanceData = {
	isSliding = false,
	startPosition = nil,
	currentDistance = 0,
	maxDistance = 0,
	lastDistance = 0,
	lastSpeed = 0
}

local DATA_FILE = "KnockoutPhysics.json"

local physicsData = {
	recordings = {},
	isRecording = false,
	recordingConn = nil,
	currentRecording = nil,
	lastSpeed = 0,
	avgFriction = 0.982,
	avgPushMultiplier = 8.5,
	pushCount = 0,
	totalSlides = 0,
	fixedPower = 3
}

local predictionSettings = {
	lineColor = Color3.fromRGB(0, 255, 255),
	dangerColor = Color3.fromRGB(255, 0, 0),
	safeColor = Color3.fromRGB(0, 255, 0),
	hitColor = Color3.fromRGB(255, 165, 0),
	stopColor = Color3.fromRGB(100, 200, 255),
	lineThickness = 0.15,
	segments = 60
}

-- Push Distance Table (power -> distance in studs)
local pushDistanceTable = {
	[1] = 5.51,
	[2] = 10.51,
	[3] = 17.03,
	[4] = 24.41,
	[5] = 33.88,
	[6] = 44.5,
	[7] = 56.3,
	[8] = 69.2,
	[9] = 83.2,
	[10] = 98.3
}

-- New Push Prediction System
local pushPredictEnabled = false
local pushPredictConn = nil
local pushPredictFolder = nil
local pushPredictSettings = {
	safeColor = Color3.fromRGB(0, 255, 100),        -- Green - safe stop
	dangerColor = Color3.fromRGB(255, 50, 50),      -- Red - fall off
	hitColor = Color3.fromRGB(50, 150, 255),        -- Blue - hit player
	lineWidth = 0.2,
	glowIntensity = 0.3
}

-- Function to read current push power from PowerGui
local function getCurrentPushPower()
	local powerGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("PowerGui")
	if powerGui then
		local powerText = powerGui:FindFirstChild("PowerText")
		if powerText and powerText:IsA("TextLabel") then
			local text = powerText.Text
			local num = tonumber(text:match("%d+"))
			if num and num >= 1 and num <= 10 then
				return num
			end
		end
	end
	return 3 -- Default power
end

-- Function to get slide distance for given power
local function getSlideDistanceForPower(power)
	power = math.clamp(math.floor(power), 1, 10)
	return pushDistanceTable[power] or 17.03
end

local function savePhysicsData()
	local success, err = pcall(function()
		if writefile then
			local data = {
				avgFriction = physicsData.avgFriction,
				avgPushMultiplier = physicsData.avgPushMultiplier,
				pushCount = physicsData.pushCount,
				totalSlides = physicsData.totalSlides,
				recordings = {}
			}
			for i, rec in ipairs(physicsData.recordings) do
				if i <= 20 then
					table.insert(data.recordings, {
						power = rec.power,
						startSpeed = rec.startSpeed,
						maxSpeed = rec.maxSpeed,
						endSpeed = rec.endSpeed,
						distance = rec.distance,
						duration = rec.duration,
						friction = rec.calculatedFriction,
						fell = rec.fell
					})
				end
			end
			local json = game:GetService("HttpService"):JSONEncode(data)
			writefile(DATA_FILE, json)
		end
	end)
end

local function loadPhysicsData()
	local success, err = pcall(function()
		if readfile and isfile and isfile(DATA_FILE) then
			local json = readfile(DATA_FILE)
			local data = game:GetService("HttpService"):JSONDecode(json)
			if data then
				physicsData.avgFriction = data.avgFriction or 0.985
				physicsData.avgPushMultiplier = data.avgPushMultiplier or 12
				physicsData.pushCount = data.pushCount or 0
				physicsData.totalSlides = data.totalSlides or 0
			end
		end
	end)
end

local function getIceRinkBounds()
	local iceRink = workspace:FindFirstChild("PlayArea") and workspace.PlayArea:FindFirstChild("IceRink")
	if not iceRink then return nil end
	
	local pos = iceRink.Position
	local size = iceRink.Size
	
	return {
		minX = pos.X - size.X / 2,
		maxX = pos.X + size.X / 2,
		minZ = pos.Z - size.Z / 2,
		maxZ = pos.Z + size.Z / 2,
		surfaceY = pos.Y + size.Y / 2
	}
end

local function isOutsideBounds(position, bounds)
	if not bounds then return false end
	return position.X < bounds.minX or position.X > bounds.maxX or
	       position.Z < bounds.minZ or position.Z > bounds.maxZ
end

local function isPlayerOnIceRink()
	local bounds = getIceRinkBounds()
	if not bounds then return false end
	
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	
	return not isOutsideBounds(root.Position, bounds)
end

local function predictTrajectory(startPos, velocity, bounds, steps, dt)
	local points = {}
	local pos = startPos
	local vel = velocity
	local willFall = false
	local fallPoint = nil
	local stopPoint = nil
	
	for i = 1, steps do
		table.insert(points, pos)
		
		vel = vel * physicsData.avgFriction
		pos = pos + vel * dt
		
		if bounds then
			pos = Vector3.new(pos.X, bounds.surfaceY + 3, pos.Z)
		end
		
		if bounds and isOutsideBounds(pos, bounds) then
			willFall = true
			fallPoint = pos
			break
		end
		
		if vel.Magnitude < 0.5 then
			stopPoint = pos
			break
		end
	end
	
	if not stopPoint and not willFall and #points > 0 then
		stopPoint = points[#points]
	end
	
	return points, willFall, fallPoint, stopPoint
end

local function createPredictionLine(parent, points, color, thickness)
	local line = Instance.new("Folder")
	line.Name = "PredictionLine"
	line.Parent = parent
	
	for i = 1, #points - 1 do
		local p1 = points[i]
		local p2 = points[i + 1]
		local distance = (p2 - p1).Magnitude
		
		if distance > 0.1 then
			local part = Instance.new("Part")
			part.Name = "LineSegment"
			part.Anchored = true
			part.CanCollide = false
			part.Material = Enum.Material.Neon
			part.Color = color
			part.Size = Vector3.new(thickness, thickness, distance)
			part.CFrame = CFrame.lookAt((p1 + p2) / 2, p2)
			part.Transparency = 0.3 + (i / #points) * 0.5
			part.Parent = line
		end
	end
	
	return line
end

local function createEndMarker(parent, position, willFall, isStopPoint)
	local marker = Instance.new("Part")
	marker.Name = "EndMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.Shape = Enum.PartType.Ball
	marker.Size = Vector3.new(1.5, 1.5, 1.5)
	
	if willFall then
		marker.Color = predictionSettings.dangerColor
	elseif isStopPoint then
		marker.Color = predictionSettings.stopColor
	else
		marker.Color = predictionSettings.safeColor
	end
	
	marker.Transparency = 0.2
	marker.Position = position
	marker.Parent = parent
	
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 100, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = marker
	
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	
	if willFall then
		text.Text = "⚠️ FALL!"
		text.TextColor3 = predictionSettings.dangerColor
	else
		text.Text = "🎯 STOP"
		text.TextColor3 = predictionSettings.stopColor
	end
	
	text.Parent = billboard
	
	return marker
end

local function getCurrentPower()
	return physicsData.fixedPower
end

local statsGui = nil
local statsLabels = {}

local function createStatsUI()
	if statsGui then statsGui:Destroy() end
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PredictionStatsGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player:WaitForChild("PlayerGui")
	
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "StatsPanel"
	mainFrame.Size = UDim2.new(0, 200, 0, 210)
	mainFrame.Position = UDim2.new(1, -210, 0.5, -105)
	mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	mainFrame.BackgroundTransparency = 0.1
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = mainFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 200, 255)
	stroke.Thickness = 2
	stroke.Parent = mainFrame
	
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Position = UDim2.new(0, 0, 0, 5)
	title.BackgroundTransparency = 1
	title.Text = "🎯 Prediction AI"
	title.TextColor3 = Color3.fromRGB(0, 220, 255)
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.Parent = mainFrame
	
	local progressBar = Instance.new("Frame")
	progressBar.Name = "ProgressBG"
	progressBar.Size = UDim2.new(0.9, 0, 0, 10)
	progressBar.Position = UDim2.new(0.05, 0, 0, 38)
	progressBar.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	progressBar.BorderSizePixel = 0
	progressBar.Parent = mainFrame
	
	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 5)
	progressCorner.Parent = progressBar
	
	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBar
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = progressFill
	
	local labels = {
		{name = "Accuracy", y = 55, text = "📈 Точность: 0%"},
		{name = "Friction", y = 75, text = "❄️ Трение: 0.985"},
		{name = "PushMult", y = 95, text = "💪 Сила: x12.0"},
		{name = "Slides", y = 115, text = "📊 Катаний: 0"},
		{name = "Status", y = 135, text = "⏳ Ожидание раунда..."},
		{name = "RoundStatus", y = 155, text = "🔴 Не в раунде"},
		{name = "Hint", y = 175, text = "💡 Толкни кого-нибудь!"}
	}
	
	for _, info in ipairs(labels) do
		local label = Instance.new("TextLabel")
		label.Name = info.name
		label.Size = UDim2.new(0.92, 0, 0, 18)
		label.Position = UDim2.new(0.04, 0, 0, info.y)
		label.BackgroundTransparency = 1
		label.Text = info.text
		label.TextColor3 = Color3.fromRGB(180, 180, 180)
		label.TextSize = 12
		label.Font = Enum.Font.Gotham
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = mainFrame
		statsLabels[info.name] = label
	end
	
	statsLabels.ProgressFill = progressFill
	statsGui = screenGui
end

local function updateStatsUI()
	if not statsGui then return end
	
	local accuracy = math.min(100, physicsData.totalSlides * 10)
	local progressFill = statsLabels.ProgressFill
	if progressFill then
		progressFill.Size = UDim2.new(accuracy / 100, 0, 1, 0)
		if accuracy < 30 then
			progressFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		elseif accuracy < 70 then
			progressFill.BackgroundColor3 = Color3.fromRGB(255, 180, 0)
		else
			progressFill.BackgroundColor3 = Color3.fromRGB(0, 255, 80)
		end
	end
	
	if statsLabels.Accuracy then
		statsLabels.Accuracy.Text = string.format("📈 Точность: %d%%", accuracy)
		statsLabels.Accuracy.TextColor3 = accuracy >= 70 and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(180, 180, 180)
	end
	if statsLabels.Friction then
		statsLabels.Friction.Text = string.format("❄️ Трение: %.4f", physicsData.avgFriction)
	end
	if statsLabels.PushMult then
		statsLabels.PushMult.Text = string.format("💪 Сила: x%.1f", physicsData.avgPushMultiplier)
	end
	if statsLabels.Slides then
		statsLabels.Slides.Text = string.format("📊 Катаний: %d", physicsData.totalSlides)
	end
	if statsLabels.Status then
		if physicsData.isRecording then
			statsLabels.Status.Text = "🔴 Записываю катание..."
			statsLabels.Status.TextColor3 = Color3.fromRGB(255, 100, 100)
		else
			statsLabels.Status.Text = "🟢 Готов к записи"
			statsLabels.Status.TextColor3 = Color3.fromRGB(100, 255, 100)
		end
	end
	local onRink = isPlayerOnIceRink()
	if statsLabels.RoundStatus then
		if onRink then
			statsLabels.RoundStatus.Text = "🟢 Раунд идёт"
			statsLabels.RoundStatus.TextColor3 = Color3.fromRGB(100, 255, 100)
		else
			statsLabels.RoundStatus.Text = "🔴 Не в раунде"
			statsLabels.RoundStatus.TextColor3 = Color3.fromRGB(255, 100, 100)
		end
	end
	if statsLabels.Hint then
		if not onRink then
			statsLabels.Hint.Text = "⏳ Ожидание раунда..."
			statsLabels.Hint.TextColor3 = Color3.fromRGB(180, 180, 180)
		elseif physicsData.totalSlides == 0 then
			statsLabels.Hint.Text = "💡 Толкни кого-нибудь!"
			statsLabels.Hint.TextColor3 = Color3.fromRGB(180, 180, 180)
		elseif physicsData.totalSlides < 5 then
			statsLabels.Hint.Text = "💡 Ещё " .. (5 - physicsData.totalSlides) .. " катаний..."
			statsLabels.Hint.TextColor3 = Color3.fromRGB(180, 180, 180)
		else
			statsLabels.Hint.Text = "✅ Калибровка готова!"
			statsLabels.Hint.TextColor3 = Color3.fromRGB(100, 255, 100)
		end
	end
end

local function destroyStatsUI()
	if statsGui then
		statsGui:Destroy()
		statsGui = nil
		statsLabels = {}
	end
end

-- Slide Distance Display Functions
local function createSlideDistanceUI()
	if slideDistanceGui then slideDistanceGui:Destroy() end
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SlideDistanceGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player:WaitForChild("PlayerGui")
	
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "SlideDistancePanel"
	mainFrame.Size = UDim2.new(0, 180, 0, 155)
	mainFrame.Position = UDim2.new(1, -190, 0.5, -77)
	mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
	mainFrame.BackgroundTransparency = 0.15
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = mainFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 200, 255)
	stroke.Thickness = 2
	stroke.Parent = mainFrame
	
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 25)
	title.Position = UDim2.new(0, 0, 0, 5)
	title.BackgroundTransparency = 1
	title.Text = "📏 Расстояние"
	title.TextColor3 = Color3.fromRGB(100, 200, 255)
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.Parent = mainFrame
	
	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Name = "Distance"
	distanceLabel.Size = UDim2.new(1, 0, 0, 30)
	distanceLabel.Position = UDim2.new(0, 0, 0, 35)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.Text = "0.00 studs"
	distanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	distanceLabel.TextSize = 22
	distanceLabel.Font = Enum.Font.GothamBold
	distanceLabel.Parent = mainFrame
	
	local maxLabel = Instance.new("TextLabel")
	maxLabel.Name = "MaxDistance"
	maxLabel.Size = UDim2.new(1, 0, 0, 16)
	maxLabel.Position = UDim2.new(0, 0, 0, 65)
	maxLabel.BackgroundTransparency = 1
	maxLabel.Text = "Max: 0.00 studs"
	maxLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	maxLabel.TextSize = 11
	maxLabel.Font = Enum.Font.Gotham
	maxLabel.Parent = mainFrame
	
	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "SlideCount"
	countLabel.Size = UDim2.new(1, 0, 0, 16)
	countLabel.Position = UDim2.new(0, 0, 0, 82)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "Записей: 0"
	countLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	countLabel.TextSize = 11
	countLabel.Font = Enum.Font.Gotham
	countLabel.Parent = mainFrame
	
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "RoundStatus"
	statusLabel.Size = UDim2.new(1, 0, 0, 16)
	statusLabel.Position = UDim2.new(0, 0, 0, 99)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "🔴 Не в раунде"
	statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	statusLabel.TextSize = 11
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Parent = mainFrame
	
	local copyButton = Instance.new("TextButton")
	copyButton.Name = "CopyButton"
	copyButton.Size = UDim2.new(0.9, 0, 0, 24)
	copyButton.Position = UDim2.new(0.05, 0, 0, 120)
	copyButton.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
	copyButton.Text = "📋 Копировать"
	copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	copyButton.TextSize = 12
	copyButton.Font = Enum.Font.GothamBold
	copyButton.Parent = mainFrame
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = copyButton
	
	copyButton.MouseButton1Click:Connect(function()
		local distValue = string.format("%.2f", slideDistanceData.lastDistance)
		if setclipboard then
			setclipboard(distValue)
			copyButton.Text = "✅ Скопировано!"
			task.delay(1, function()
				if copyButton and copyButton.Parent then
					copyButton.Text = "📋 Копировать"
				end
			end)
		end
	end)
	
	slideDistanceGui = screenGui
end

local function updateSlideDistance()
	if not slideDistanceGui then return end
	
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	local onRink = isPlayerOnIceRink()
	local mainFrame = slideDistanceGui:FindFirstChild("SlideDistancePanel")
	
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	
	-- Update round status UI and speed debug
	if mainFrame then
		local statusLabel = mainFrame:FindFirstChild("RoundStatus")
		if statusLabel then
			if onRink then
				statusLabel.Text = string.format("🟢 В раунде | %.1f", speed)
				statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
			else
				statusLabel.Text = string.format("🔴 Не в раунде | %.1f", speed)
				statusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			end
		end
	end
	
	-- Only track when on ice rink
	if not onRink then
		-- Reset sliding state when leaving rink
		if slideDistanceData.isSliding then
			slideDistanceData.isSliding = false
		end
		slideDistanceData.lastSpeed = 0
		return
	end
	
	-- Detect slide start (any movement with speed > 3)
	if not slideDistanceData.isSliding then
		if speed > 3 then
			slideDistanceData.isSliding = true
			slideDistanceData.startPosition = root.Position
			slideDistanceData.currentDistance = 0
		end
	else
		-- Update distance during slide
		if slideDistanceData.startPosition then
			local displacement = root.Position - slideDistanceData.startPosition
			slideDistanceData.currentDistance = Vector3.new(displacement.X, 0, displacement.Z).Magnitude
			
			if slideDistanceData.currentDistance > slideDistanceData.maxDistance then
				slideDistanceData.maxDistance = slideDistanceData.currentDistance
			end
		end
		
		-- Detect slide end (speed dropped below 0.5)
		if speed < 0.5 then
			slideDistanceData.lastDistance = slideDistanceData.currentDistance
			slideDistanceData.slideCount = (slideDistanceData.slideCount or 0) + 1
			slideDistanceData.isSliding = false
		end
	end
	
	slideDistanceData.lastSpeed = speed
	
	-- Update UI
	if mainFrame then
		local distLabel = mainFrame:FindFirstChild("Distance")
		local maxLabel = mainFrame:FindFirstChild("MaxDistance")
		local countLabel = mainFrame:FindFirstChild("SlideCount")
		
		if distLabel then
			local displayDist = slideDistanceData.isSliding and slideDistanceData.currentDistance or slideDistanceData.lastDistance
			distLabel.Text = string.format("%.2f studs", displayDist)
			
			if slideDistanceData.isSliding then
				distLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
			else
				distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
		
		if maxLabel then
			maxLabel.Text = string.format("Max: %.2f studs", slideDistanceData.maxDistance)
		end
		
		if countLabel then
			countLabel.Text = string.format("Записей: %d", slideDistanceData.slideCount or 0)
		end
	end
end

local function destroySlideDistanceUI()
	if slideDistanceGui then
		slideDistanceGui:Destroy()
		slideDistanceGui = nil
	end
end

local function toggleSlideDistance(state)
	slideDistanceEnabled = state
	
	if slideDistanceConn then
		slideDistanceConn:Disconnect()
		slideDistanceConn = nil
	end
	
	if slideDistanceEnabled then
		slideDistanceData.isSliding = false
		slideDistanceData.startPosition = nil
		slideDistanceData.currentDistance = 0
		slideDistanceData.lastDistance = 0
		slideDistanceData.lastSpeed = 0
		-- Don't reset maxDistance to keep tracking max
		
		createSlideDistanceUI()
		
		slideDistanceConn = RunService.Heartbeat:Connect(function()
			updateSlideDistance()
		end)
	else
		destroySlideDistanceUI()
	end
end

-- ============================================
-- PUSH PREDICTION SYSTEM (Visual Trajectory)
-- ============================================

local function clearPushPredict()
	if pushPredictFolder then
		pushPredictFolder:ClearAllChildren()
	end
end

local function createPushPredictLine(parent, startPos, endPos, color, segments)
	local lineFolder = Instance.new("Folder")
	lineFolder.Name = "PredictLine"
	lineFolder.Parent = parent
	
	local direction = (endPos - startPos)
	local distance = direction.Magnitude
	local segmentLength = distance / segments
	
	for i = 0, segments - 1 do
		local t = i / segments
		local nextT = (i + 1) / segments
		
		local p1 = startPos + direction * t
		local p2 = startPos + direction * nextT
		local segDist = (p2 - p1).Magnitude
		
		-- Main line segment
		local part = Instance.new("Part")
		part.Name = "Segment" .. i
		part.Anchored = true
		part.CanCollide = false
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Size = Vector3.new(pushPredictSettings.lineWidth, pushPredictSettings.lineWidth, segDist)
		part.CFrame = CFrame.lookAt((p1 + p2) / 2, p2)
		part.Transparency = 0.1 + t * 0.4 -- Fade out towards end
		part.Parent = lineFolder
		
		-- Glow effect (larger transparent part)
		local glow = Instance.new("Part")
		glow.Name = "Glow" .. i
		glow.Anchored = true
		glow.CanCollide = false
		glow.Material = Enum.Material.Neon
		glow.Color = color
		glow.Size = Vector3.new(pushPredictSettings.lineWidth * 3, pushPredictSettings.lineWidth * 3, segDist)
		glow.CFrame = part.CFrame
		glow.Transparency = 0.85 + t * 0.1
		glow.Parent = lineFolder
	end
	
	return lineFolder
end

local function createPushEndMarker(parent, position, color, label)
	-- Main marker sphere
	local marker = Instance.new("Part")
	marker.Name = "EndMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.Shape = Enum.PartType.Ball
	marker.Color = color
	marker.Size = Vector3.new(2, 2, 2)
	marker.Position = position
	marker.Transparency = 0.2
	marker.Parent = parent
	
	-- Outer glow ring
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = color
	ring.Size = Vector3.new(0.2, 4, 4)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.5
	ring.Parent = parent
	
	-- Billboard label
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = marker
	
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Text = label
	text.TextColor3 = color
	text.TextSize = 18
	text.Font = Enum.Font.GothamBold
	text.TextStrokeTransparency = 0.5
	text.TextStrokeColor3 = Color3.new(0, 0, 0)
	text.Parent = billboard
	
	return marker
end

local function findClosestPlayerInDirection(myPos, direction, maxDist)
	local closestPlayer = nil
	local closestDist = maxDist
	
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			local targetRoot = p.Character:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				local toTarget = targetRoot.Position - myPos
				toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
				local dist = toTarget.Magnitude
				
				if dist < closestDist and dist > 1 then
					local dot = toTarget.Unit:Dot(direction)
					if dot > 0.95 then -- Very precise aim required
						closestPlayer = p
						closestDist = dist
					end
				end
			end
		end
	end
	
	return closestPlayer, closestDist
end

local function updatePushPredict()
	clearPushPredict()
	
	if not isPlayerOnIceRink() then return end
	
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	local bounds = getIceRinkBounds()
	if not bounds then return end
	
	-- Get current push power and slide distance
	local power = getCurrentPushPower()
	local slideDistance = getSlideDistanceForPower(power)
	
	-- Get aim direction from camera
	local camera = workspace.CurrentCamera
	if not camera then return end
	local lookDir = camera.CFrame.LookVector
	local aimDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	
	local startPos = root.Position
	local endPos = startPos + aimDir * slideDistance
	endPos = Vector3.new(endPos.X, bounds.surfaceY + 2, endPos.Z)
	
	-- Simple line through - just show trajectory
	local lineColor
	local markerLabel
	
	-- Add safety margin (3 studs from edge = danger)
	local safetyMargin = 3
	local safeBounds = {
		minX = bounds.minX + safetyMargin,
		maxX = bounds.maxX - safetyMargin,
		minZ = bounds.minZ + safetyMargin,
		maxZ = bounds.maxZ - safetyMargin
	}
	
	if isOutsideBounds(endPos, safeBounds) then
		lineColor = pushPredictSettings.dangerColor
		markerLabel = "⚠️ DANGER"
	else
		lineColor = pushPredictSettings.safeColor
		markerLabel = "✓ SAFE"
	end
	
	createPushPredictLine(pushPredictFolder, startPos, endPos, lineColor, 20)
	createPushEndMarker(pushPredictFolder, endPos, lineColor, markerLabel)
end

local function togglePushPredict(state)
	pushPredictEnabled = state
	
	if pushPredictConn then
		pushPredictConn:Disconnect()
		pushPredictConn = nil
	end
	
	if pushPredictFolder then
		pushPredictFolder:Destroy()
		pushPredictFolder = nil
	end
	
	if pushPredictEnabled then
		pushPredictFolder = Instance.new("Folder")
		pushPredictFolder.Name = "PushPrediction"
		pushPredictFolder.Parent = workspace
		
		pushPredictConn = RunService.Heartbeat:Connect(function()
			updatePushPredict()
		end)
	end
end

local function stopSlideRecording()
	if not physicsData.isRecording then return end
	if not physicsData.currentRecording then return end
	
	physicsData.isRecording = false
	local rec = physicsData.currentRecording
	
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		rec.endPosition = root.Position
		rec.endSpeed = root.AssemblyLinearVelocity.Magnitude
	end
	
	rec.duration = tick() - rec.startTime
	rec.distance = rec.endPosition and rec.startPosition and (rec.endPosition - rec.startPosition).Magnitude or 0
	
	if #rec.speeds > 10 then
		local frictionSamples = {}
		for i = 2, #rec.speeds do
			if rec.speeds[i-1] > 3 and rec.speeds[i] > 1 then
				local f = rec.speeds[i] / rec.speeds[i-1]
				if f > 0.9 and f < 1.0 then
					table.insert(frictionSamples, f)
				end
			end
		end
		
		if #frictionSamples > 3 then
			local sum = 0
			for _, f in ipairs(frictionSamples) do sum = sum + f end
			rec.calculatedFriction = sum / #frictionSamples
			
			local weight = math.min(0.3, 1 / (physicsData.totalSlides + 1))
			physicsData.avgFriction = physicsData.avgFriction * (1 - weight) + rec.calculatedFriction * weight
		end
		
		if rec.power > 0 and rec.maxSpeed > 5 then
			local mult = rec.maxSpeed / rec.power
			if mult > 5 and mult < 30 then
				local weight = math.min(0.3, 1 / (physicsData.totalSlides + 1))
				physicsData.avgPushMultiplier = physicsData.avgPushMultiplier * (1 - weight) + mult * weight
			end
		end
		
		table.insert(physicsData.recordings, rec)
		if #physicsData.recordings > 30 then
			table.remove(physicsData.recordings, 1)
		end
		
		physicsData.totalSlides = physicsData.totalSlides + 1
		savePhysicsData()
	end
	
	physicsData.currentRecording = nil
end

local function startSlideRecording(startSpeed)
	if physicsData.isRecording then return end
	
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	physicsData.isRecording = true
	physicsData.currentRecording = {
		startTime = tick(),
		startPosition = root.Position,
		startSpeed = startSpeed,
		maxSpeed = startSpeed,
		endSpeed = 0,
		power = getCurrentPower(),
		speeds = {startSpeed},
		fell = false,
		endPosition = nil,
		distance = 0,
		duration = 0,
		calculatedFriction = nil
	}
end

local function monitorPhysics()
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	
	if not physicsData.isRecording then
		if speed > 10 and physicsData.lastSpeed < 5 then
			startSlideRecording(speed)
		end
	else
		if physicsData.currentRecording then
			table.insert(physicsData.currentRecording.speeds, speed)
			if speed > physicsData.currentRecording.maxSpeed then
				physicsData.currentRecording.maxSpeed = speed
			end
			
			local bounds = getIceRinkBounds()
			if bounds and isOutsideBounds(root.Position, bounds) then
				physicsData.currentRecording.fell = true
			end
			
			if speed < 1 and #physicsData.currentRecording.speeds > 15 then
				stopSlideRecording()
			end
		end
	end
	
	physicsData.lastSpeed = speed
end

local function isAiming()
	return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
end

local function clearPrediction()
	if predictionFolder then
		predictionFolder:ClearAllChildren()
	end
end

local function getAimDirection()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	
	local lookDir = camera.CFrame.LookVector
	return Vector3.new(lookDir.X, 0, lookDir.Z).Unit
end

local function findTargetInAim(myPos, aimDir, bounds)
	local closestTarget = nil
	local closestDist = 30
	
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			local targetRoot = p.Character:FindFirstChild("HumanoidRootPart")
			if targetRoot and not isOutsideBounds(targetRoot.Position, bounds) then
				local toTarget = (targetRoot.Position - myPos)
				toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
				local dist = toTarget.Magnitude
				
				if dist < closestDist and dist > 1 then
					local dot = toTarget.Unit:Dot(aimDir)
					if dot > 0.6 then
						closestTarget = targetRoot
						closestDist = dist
					end
				end
			end
		end
	end
	
	return closestTarget
end

local function updatePrediction()
	clearPrediction()
	
	if not isAiming() then return end
	
	local power = getCurrentPower()
	
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	local bounds = getIceRinkBounds()
	if not bounds then return end
	
	local aimDir = getAimDirection()
	if not aimDir then return end
	
	local target = findTargetInAim(root.Position, aimDir, bounds)
	
	if target then
		local pushDir = (target.Position - root.Position)
		pushDir = Vector3.new(pushDir.X, 0, pushDir.Z).Unit
		
		local pushVelocity = pushDir * power * physicsData.avgPushMultiplier
		
		local points, willFall, fallPoint, stopPoint = predictTrajectory(
			target.Position,
			pushVelocity,
			bounds,
			predictionSettings.segments,
			0.1
		)
		
		if #points > 1 then
			createPredictionLine(predictionFolder, points, predictionSettings.hitColor, predictionSettings.lineThickness)
			if willFall then
				createEndMarker(predictionFolder, fallPoint, true, false)
			elseif stopPoint then
				createEndMarker(predictionFolder, stopPoint, false, true)
			end
		end
	else
		local pushVelocity = aimDir * power * physicsData.avgPushMultiplier
		
		local points, willFall, fallPoint, stopPoint = predictTrajectory(
			root.Position,
			pushVelocity,
			bounds,
			predictionSettings.segments,
			0.1
		)
		
		if #points > 1 then
			createPredictionLine(predictionFolder, points, predictionSettings.lineColor, predictionSettings.lineThickness)
			if willFall then
				createEndMarker(predictionFolder, fallPoint, true, false)
			elseif stopPoint then
				createEndMarker(predictionFolder, stopPoint, false, true)
			end
		end
	end
end

local function togglePrediction(state)
	predictionEnabled = state
	
	if predictionEnabled then
		loadPhysicsData()
		
		if predictionFolder then predictionFolder:Destroy() end
		predictionFolder = Instance.new("Folder")
		predictionFolder.Name = "TrajectoryPrediction"
		predictionFolder.Parent = workspace
		
		createStatsUI()
		
		physicsMonitorConn = RunService.Heartbeat:Connect(function()
			monitorPhysics()
		end)
		
		predictionConn = RunService.Heartbeat:Connect(function()
			updatePrediction()
			updateStatsUI()
		end)
	else
		if predictionConn then
			predictionConn:Disconnect()
			predictionConn = nil
		end
		if physicsMonitorConn then
			physicsMonitorConn:Disconnect()
			physicsMonitorConn = nil
		end
		if predictionFolder then
			predictionFolder:Destroy()
			predictionFolder = nil
		end
		stopSlideRecording()
		destroyStatsUI()
	end
end

-- Fly Functions
local function getRoot()
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	return humanoid, root
end

local function stopFly()
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function startFly()
	stopFly()

	local humanoid, root = getRoot()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	humanoid.PlatformStand = true

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
		local cam = workspace.CurrentCamera
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

-- Auto Spin Functions
local function toggleAutoSpin(state)
	autoSpinEnabled = state
	if autoSpinEnabled then
		task.spawn(function()
			while autoSpinEnabled do
				pcall(function()
					game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunctions"):WaitForChild("SpinRequest"):InvokeServer()
				end)
				task.wait(0.4)
			end
		end)
	end
end

-- Noclip Functions (Smart Noclip: Does not disable legs/feet to allow walking on floor)
local function toggleNoclip(state)
	noclipEnabled = state
	if noclipLoop then
		noclipLoop:Disconnect()
		noclipLoop = nil
	end

	if noclipEnabled then
		noclipLoop = RunService.Stepped:Connect(function()
			if player.Character then
				for _, v in pairs(player.Character:GetDescendants()) do
					if v:IsA("BasePart") and v.CanCollide == true then
						-- Filter out legs/feet/Heels to prevent falling through floor
						local name = v.Name
						if not (string.find(name, "Leg") or string.find(name, "Foot") or string.find(name, "Heel") or string.find(name, "Ankle")) then
							v.CanCollide = false
						end
					end
				end
			end
		end)
	end
end


-- Troll Function
local trollBodyVelocity = nil
local trollBodyGyro = nil
local trollNoclipConn = nil

local function startTroll()
	if trollConn then trollConn:Disconnect() end
	if not trollEnabled or selectedTrollTarget == nil then return end

	local localPlayer = Players.LocalPlayer
	local character = localPlayer.Character
	if not character then return end
	local root = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	
	-- Enable PlatformStand to disable gravity/physics
	if humanoid then
		humanoid.PlatformStand = true
	end
	
	-- Create BodyVelocity for stable upward movement
	if trollBodyVelocity then trollBodyVelocity:Destroy() end
	trollBodyVelocity = Instance.new("BodyVelocity")
	trollBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	trollBodyVelocity.Velocity = Vector3.new(0, 0, 0)
	trollBodyVelocity.Parent = root
	
	-- Create BodyGyro to keep orientation stable (belly up - lying on back)
	if trollBodyGyro then trollBodyGyro:Destroy() end
	trollBodyGyro = Instance.new("BodyGyro")
	trollBodyGyro.P = 9e4
	trollBodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
	-- Rotate -90 degrees on X axis to lie on back (belly facing up)
	trollBodyGyro.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(-90), 0, 0)
	trollBodyGyro.Parent = root
	
	-- Enable Noclip for troll (disable all collisions)
	if trollNoclipConn then trollNoclipConn:Disconnect() end
	trollNoclipConn = RunService.Stepped:Connect(function()
		if character then
			for _, v in pairs(character:GetDescendants()) do
				if v:IsA("BasePart") then
					v.CanCollide = false
				end
			end
		end
	end)
	
	-- Initial Teleport (directly under feet)
	local targetPlayer = Players:FindFirstChild(selectedTrollTarget)
	if targetPlayer and targetPlayer.Character then
		local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			root.CFrame = targetRoot.CFrame * CFrame.new(0, -6, 0)
		end
	end
	
	trollConn = RunService.Heartbeat:Connect(function(dt)
		local targetPlayer = Players:FindFirstChild(selectedTrollTarget)
		if not targetPlayer or not targetPlayer.Character then return end
		local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not targetRoot then return end
		
		-- Track target position
		local targetPos = targetRoot.Position
		local myPos = root.Position
		
		-- Rise speed (studs per second)
		local riseSpeed = 15
		
		-- Calculate velocity to move towards target X/Z and rise in Y
		local moveX = (targetPos.X - myPos.X) * 10
		local moveZ = (targetPos.Z - myPos.Z) * 10
		
		-- Set velocity: track X/Z, constant rise Y
		if trollBodyVelocity then
			trollBodyVelocity.Velocity = Vector3.new(moveX, riseSpeed, moveZ)
		end
	end)
end

local function stopTroll()
	if trollConn then
		trollConn:Disconnect()
		trollConn = nil
	end
	
	if trollNoclipConn then
		trollNoclipConn:Disconnect()
		trollNoclipConn = nil
	end
	
	if trollBodyVelocity then
		trollBodyVelocity:Destroy()
		trollBodyVelocity = nil
	end
	
	if trollBodyGyro then
		trollBodyGyro:Destroy()
		trollBodyGyro = nil
	end
	
	local character = Players.LocalPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
		if character:FindFirstChild("HumanoidRootPart") then
			character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
		end
		for _, v in pairs(character:GetDescendants()) do
			if v:IsA("BasePart") then
				v.CanCollide = true
			end
		end
	end
end

-- Bring All Function (fly into players on IceRink)
local function isOnIceRink(targetRoot)
	local iceRink = workspace:FindFirstChild("PlayArea") and workspace.PlayArea:FindFirstChild("IceRink")
	if not iceRink then return false end
	
	-- Check if player is within IceRink bounds (using simple distance check)
	local rinkPos = iceRink.Position
	local rinkSize = iceRink.Size
	local playerPos = targetRoot.Position
	
	-- Check horizontal bounds (X and Z)
	local halfX = rinkSize.X / 2
	local halfZ = rinkSize.Z / 2
	
	return math.abs(playerPos.X - rinkPos.X) <= halfX and math.abs(playerPos.Z - rinkPos.Z) <= halfZ
end

local function bringAll()
	local localPlayer = Players.LocalPlayer
	local character = localPlayer.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Get list of players on IceRink
	local targets = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			local targetRoot = p.Character.HumanoidRootPart
			if isOnIceRink(targetRoot) then
				table.insert(targets, targetRoot)
			end
		end
	end

	-- Enable Noclip
	local noclipConn
	noclipConn = RunService.Stepped:Connect(function()
		for _, v in pairs(character:GetDescendants()) do
			if v:IsA("BasePart") and v.CanCollide == true then
				v.CanCollide = false
			end
		end
	end)

	if #targets == 0 then
		if noclipConn then noclipConn:Disconnect() end
		return
	end

	-- Fly through each target
	
	-- Quick fly-through each target (no PlatformStand to avoid lag)
	for _, targetRoot in ipairs(targets) do
		if targetRoot and targetRoot.Parent and root and root.Parent then
			-- Get target's look direction
			local targetCFrame = targetRoot.CFrame
			local lookVector = targetCFrame.LookVector
			
			-- Calculate start position (3 studs behind)
			local startPos = targetRoot.Position - (lookVector * 3)
			-- Calculate end position (3 studs ahead)
			local endPos = targetRoot.Position + (lookVector * 3)
			
			-- Teleport to start
			root.CFrame = CFrame.new(startPos, targetRoot.Position)
			
			-- Quick teleport through (3 steps, no waits that cause lag)
			root.CFrame = CFrame.new(targetRoot.Position, endPos)
			task.wait(0.03)
			root.CFrame = CFrame.new(endPos, endPos + lookVector)
			
			-- Small delay between targets
			task.wait(0.1)
		end
	end
	
	-- Disable Noclip and re-enable collisions
	if noclipConn then noclipConn:Disconnect() end
	
	-- Re-enable collisions to prevent falling through ground
	for _, v in pairs(character:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CanCollide = true
		end
	end
	
	-- Zero velocity after re-enabling collisions
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	-- Teleport to center
	local iceRink = workspace:FindFirstChild("PlayArea") and workspace.PlayArea:FindFirstChild("IceRink")
	if iceRink then
		root.CFrame = iceRink.CFrame + Vector3.new(0, 5, 0)
	end
end

-- UI Elements

-- Fly Tab
TabMovement:CreateToggle({
	Name = "Fly",
	CurrentValue = false,
	Flag = "FlyToggle",
	Callback = function(Value)
		flyEnabled = Value
		if flyEnabled then
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
	Callback = function(Value)
		flySpeed = Value
	end
})

TabMovement:CreateToggle({
	Name = "Noclip",
	CurrentValue = false,
	Flag = "NoclipToggle",
	Callback = function(Value)
		toggleNoclip(Value)
	end
})

-- Combat Tab
TabCombat:CreateToggle({
	Name = "Auto Spin",
	CurrentValue = false,
	Flag = "AutoSpin",
	Callback = function(Value)
		toggleAutoSpin(Value)
	end
})

TabCombat:CreateToggle({
	Name = "Slide Distance",
	CurrentValue = false,
	Flag = "SlideDistanceToggle",
	Callback = function(Value)
		toggleSlideDistance(Value)
	end
})

TabCombat:CreateToggle({
	Name = "Push Predict",
	CurrentValue = false,
	Flag = "PushPredictToggle",
	Callback = function(Value)
		togglePushPredict(Value)
	end
})


local PlayerDropdown = TabCombat:CreateDropdown({
	Name = "Select Troll Target",
	Options = {},
	CurrentOption = "",
	Flag = "TrollTarget",
	Callback = function(Option)
		selectedTrollTarget = Option[1]
		if trollEnabled then
			startTroll()
		end
	end
})

local function refreshPlayerList()
	local options = {}
	for _, p in pairs(Players:GetPlayers()) do
		if p ~= player then
			table.insert(options, p.Name)
		end
	end
	PlayerDropdown:Refresh(options, true)
end

TabCombat:CreateButton({
	Name = "Refresh Players",
	Callback = function()
		refreshPlayerList()
	end
})

TabCombat:CreateToggle({
	Name = "Troll Target",
	CurrentValue = false,
	Flag = "TrollToggle",
	Callback = function(Value)
		trollEnabled = Value
		if trollEnabled then
			if selectedTrollTarget then
				startTroll()
			end
		else
			stopTroll()
		end
	end
})


local platformBoundsFolder = nil
local showingBounds = false
local boundsConnection = nil
local boundsParts = {}

local function updatePlatformBounds()
	local bounds = getIceRinkBounds()
	if not bounds or not platformBoundsFolder then return end
	
	local corners = {
		{bounds.minX, bounds.minZ},
		{bounds.maxX, bounds.minZ},
		{bounds.maxX, bounds.maxZ},
		{bounds.minX, bounds.maxZ}
	}
	
	for i = 1, 4 do
		local p1 = corners[i]
		local p2 = corners[i % 4 + 1]
		
		local start = Vector3.new(p1[1], bounds.surfaceY + 1, p1[2])
		local finish = Vector3.new(p2[1], bounds.surfaceY + 1, p2[2])
		local dist = (finish - start).Magnitude
		
		if boundsParts["line" .. i] then
			boundsParts["line" .. i].Size = Vector3.new(0.3, 0.3, dist)
			boundsParts["line" .. i].CFrame = CFrame.lookAt((start + finish) / 2, finish)
		end
		
		if boundsParts["corner" .. i] then
			boundsParts["corner" .. i].Position = Vector3.new(corners[i][1], bounds.surfaceY + 1, corners[i][2])
		end
	end
	
	local centerX = (bounds.minX + bounds.maxX) / 2
	local centerZ = (bounds.minZ + bounds.maxZ) / 2
	
	if boundsParts.center then
		boundsParts.center.CFrame = CFrame.new(centerX, bounds.surfaceY + 1, centerZ) * CFrame.Angles(0, 0, math.rad(90))
	end
	
	if boundsParts.crossX then
		local crossLen = bounds.maxX - bounds.minX
		boundsParts.crossX.Size = Vector3.new(0.2, 0.2, crossLen)
		boundsParts.crossX.CFrame = CFrame.new(centerX, bounds.surfaceY + 1, centerZ) * CFrame.Angles(0, math.rad(90), 0)
	end
	
	if boundsParts.crossZ then
		local crossLen = bounds.maxZ - bounds.minZ
		boundsParts.crossZ.Size = Vector3.new(0.2, 0.2, crossLen)
		boundsParts.crossZ.CFrame = CFrame.new(centerX, bounds.surfaceY + 1, centerZ)
	end
end

local function createBoundsVisuals()
	local bounds = getIceRinkBounds()
	if not bounds then return end
	
	platformBoundsFolder = Instance.new("Folder")
	platformBoundsFolder.Name = "PlatformBounds"
	platformBoundsFolder.Parent = workspace
	
	local corners = {
		{bounds.minX, bounds.minZ},
		{bounds.maxX, bounds.minZ},
		{bounds.maxX, bounds.maxZ},
		{bounds.minX, bounds.maxZ}
	}
	
	for i = 1, 4 do
		local p1 = corners[i]
		local p2 = corners[i % 4 + 1]
		
		local start = Vector3.new(p1[1], bounds.surfaceY + 1, p1[2])
		local finish = Vector3.new(p2[1], bounds.surfaceY + 1, p2[2])
		local dist = (finish - start).Magnitude
		
		local line = Instance.new("Part")
		line.Name = "BoundLine" .. i
		line.Anchored = true
		line.CanCollide = false
		line.Material = Enum.Material.Neon
		line.Color = Color3.fromRGB(255, 0, 0)
		line.Size = Vector3.new(0.3, 0.3, dist)
		line.CFrame = CFrame.lookAt((start + finish) / 2, finish)
		line.Transparency = 0.3
		line.Parent = platformBoundsFolder
		boundsParts["line" .. i] = line
	end
	
	for i = 1, 4 do
		local c = corners[i]
		local marker = Instance.new("Part")
		marker.Name = "CornerMarker" .. i
		marker.Anchored = true
		marker.CanCollide = false
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(255, 0, 0)
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(1, 1, 1)
		marker.Position = Vector3.new(c[1], bounds.surfaceY + 1, c[2])
		marker.Transparency = 0.2
		marker.Parent = platformBoundsFolder
		boundsParts["corner" .. i] = marker
	end
	
	local center = Instance.new("Part")
	center.Name = "CenterMarker"
	center.Anchored = true
	center.CanCollide = false
	center.Material = Enum.Material.Neon
	center.Color = Color3.fromRGB(0, 255, 0)
	center.Shape = Enum.PartType.Cylinder
	center.Size = Vector3.new(0.5, 2, 2)
	local centerX = (bounds.minX + bounds.maxX) / 2
	local centerZ = (bounds.minZ + bounds.maxZ) / 2
	center.CFrame = CFrame.new(centerX, bounds.surfaceY + 1, centerZ) * CFrame.Angles(0, 0, math.rad(90))
	center.Transparency = 0.3
	center.Parent = platformBoundsFolder
	boundsParts.center = center
	
	local crossLenX = bounds.maxX - bounds.minX
	local crossX = Instance.new("Part")
	crossX.Name = "CrossX"
	crossX.Anchored = true
	crossX.CanCollide = false
	crossX.Material = Enum.Material.Neon
	crossX.Color = Color3.fromRGB(255, 255, 0)
	crossX.Size = Vector3.new(0.2, 0.2, crossLenX)
	crossX.CFrame = CFrame.new(centerX, bounds.surfaceY + 1, centerZ) * CFrame.Angles(0, math.rad(90), 0)
	crossX.Transparency = 0.3
	crossX.Parent = platformBoundsFolder
	boundsParts.crossX = crossX
	
	local crossLenZ = bounds.maxZ - bounds.minZ
	local crossZ = Instance.new("Part")
	crossZ.Name = "CrossZ"
	crossZ.Anchored = true
	crossZ.CanCollide = false
	crossZ.Material = Enum.Material.Neon
	crossZ.Color = Color3.fromRGB(255, 255, 0)
	crossZ.Size = Vector3.new(0.2, 0.2, crossLenZ)
	crossZ.CFrame = CFrame.new(centerX, bounds.surfaceY + 1, centerZ)
	crossZ.Transparency = 0.3
	crossZ.Parent = platformBoundsFolder
	boundsParts.crossZ = crossZ
end

TabCombat:CreateToggle({
	Name = "Show Platform Bounds",
	CurrentValue = false,
	Flag = "ShowBoundsToggle",
	Callback = function(Value)
		showingBounds = Value
		
		if boundsConnection then
			boundsConnection:Disconnect()
			boundsConnection = nil
		end
		
		if platformBoundsFolder then
			platformBoundsFolder:Destroy()
			platformBoundsFolder = nil
		end
		boundsParts = {}
		
		if Value then
			createBoundsVisuals()
			boundsConnection = RunService.Heartbeat:Connect(function()
				updatePlatformBounds()
			end)
		end
	end
})

TabCombat:CreateButton({
	Name = "TP to Center",
	Callback = function()
		local character = player.Character
		if not character then return end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		
		local bounds = getIceRinkBounds()
		if bounds then
			local centerX = (bounds.minX + bounds.maxX) / 2
			local centerZ = (bounds.minZ + bounds.maxZ) / 2
			root.CFrame = CFrame.new(centerX, bounds.surfaceY + 3, centerZ)
		else
			local iceRink = workspace:FindFirstChild("PlayArea") and workspace.PlayArea:FindFirstChild("IceRink")
			if iceRink then
				root.CFrame = iceRink.CFrame + Vector3.new(0, 5, 0)
			end
		end
	end
})

local autoPlayEnabled = false
local autoPlayConn = nil
local autoPlayEdgeOffset = 1

TabCombat:CreateToggle({
	Name = "RTP",
	CurrentValue = false,
	Flag = "RTPToggle",
	Callback = function(Value)
		autoPlayEnabled = Value
		
		if autoPlayConn then
			autoPlayConn = false
		end
		
		if Value then
			autoPlayConn = true
			task.spawn(function()
				while autoPlayConn and autoPlayEnabled do
					local character = player.Character
					if character then
						local root = character:FindFirstChild("HumanoidRootPart")
						if root then
							local bounds = getIceRinkBounds()
							if bounds then
								local centerX = (bounds.minX + bounds.maxX) / 2
								local centerZ = (bounds.minZ + bounds.maxZ) / 2
								
								local edges = {
									{bounds.minX + autoPlayEdgeOffset, centerZ},
									{bounds.maxX - autoPlayEdgeOffset, centerZ},
									{centerX, bounds.minZ + autoPlayEdgeOffset},
									{centerX, bounds.maxZ - autoPlayEdgeOffset},
									{bounds.minX + autoPlayEdgeOffset, bounds.minZ + autoPlayEdgeOffset},
									{bounds.maxX - autoPlayEdgeOffset, bounds.minZ + autoPlayEdgeOffset},
									{bounds.minX + autoPlayEdgeOffset, bounds.maxZ - autoPlayEdgeOffset},
									{bounds.maxX - autoPlayEdgeOffset, bounds.maxZ - autoPlayEdgeOffset}
								}
								
								local randomEdge = edges[math.random(1, #edges)]
								local targetPos = Vector3.new(randomEdge[1], bounds.surfaceY + 3, randomEdge[2])
								local centerPos = Vector3.new(centerX, bounds.surfaceY + 3, centerZ)
								
								root.CFrame = CFrame.lookAt(targetPos, centerPos)
								
								local camera = workspace.CurrentCamera
								if camera then
									camera.CFrame = CFrame.lookAt(targetPos + Vector3.new(0, 5, 0), centerPos)
								end
							end
						end
					end
					task.wait(0.3) -- 3x slower (was instant on heartbeat)
				end
			end)
		end
	end
})

TabCombat:CreateButton({
	Name = "TP to Random Edge",
	Callback = function()
		local character = player.Character
		if not character then return end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		
		local bounds = getIceRinkBounds()
		if not bounds then return end
		
		local centerX = (bounds.minX + bounds.maxX) / 2
		local centerZ = (bounds.minZ + bounds.maxZ) / 2
		
		local edges = {
			{bounds.minX + autoPlayEdgeOffset, centerZ},
			{bounds.maxX - autoPlayEdgeOffset, centerZ},
			{centerX, bounds.minZ + autoPlayEdgeOffset},
			{centerX, bounds.maxZ - autoPlayEdgeOffset}
		}
		
		local randomEdge = edges[math.random(1, #edges)]
		local targetPos = Vector3.new(randomEdge[1], bounds.surfaceY + 3, randomEdge[2])
		local centerPos = Vector3.new(centerX, bounds.surfaceY + 3, centerZ)
		
		root.CFrame = CFrame.lookAt(targetPos, centerPos)
	end
})

refreshPlayerList()

-- Events
player.CharacterAdded:Connect(function()
	if flyEnabled then
		startFly()
	end
end)

-- Anti-Void (Safety Net)
task.spawn(function()
	while true do
		task.wait(1)
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local root = player.Character.HumanoidRootPart
			-- If fallen far below reasonable map height
			if root.Position.Y < -50 then
				local iceRink = workspace:FindFirstChild("PlayArea") and workspace.PlayArea:FindFirstChild("IceRink")
				if iceRink then
					root.AssemblyLinearVelocity = Vector3.zero 
					root.CFrame = iceRink.CFrame + Vector3.new(0, 10, 0)
				else
					-- Fallback if no rink found
					root.AssemblyLinearVelocity = Vector3.zero
					root.CFrame = CFrame.new(0, 50, 0)
				end
			end
		end
	end
end)


