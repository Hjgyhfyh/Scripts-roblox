local LIBRARY_URL = "https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"
local LOCAL_LIBRARY_PATHS = {
	"sigmatik_ui_library.lua",
	"gui_lua/sigmatik_ui_library.lua",
	"../gui_lua/sigmatik_ui_library.lua",
	"..\\gui_lua\\sigmatik_ui_library.lua",
	"D:/Нужное/Скрипты роблокс/Делаем скрипты тут/gui_lua/sigmatik_ui_library.lua",
}

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local SharedEnvironment = getgenv and getgenv() or _G
local PreviousContext = SharedEnvironment.SigmatikStoneFarmContext

if PreviousContext and PreviousContext.Cleanup then
	pcall(PreviousContext.Cleanup)
end

local function loadLibrary()
	for _, path in ipairs(LOCAL_LIBRARY_PATHS) do
		if loadfile then
			local ok, chunk = pcall(loadfile, path)
			if ok and chunk then
				return chunk()
			end
		end

		if readfile and loadstring then
			local ok, source = pcall(readfile, path)
			if ok and source then
				return loadstring(source)()
			end
		end
	end

	if loadstring then
		local ok, source = pcall(function()
			return game:HttpGet(LIBRARY_URL)
		end)

		if ok and source then
			return loadstring(source)()
		end
	end

	error("Sigmatik UI library could not be loaded")
end

local Library = loadLibrary()

local function icon(codepoint)
	return utf8.char(codepoint)
end

local TAB_NAME = icon(0x26CF) .. " Stone Farm"
local MODULE_NAME = icon(0x1FAA8) .. " Stone Harvester"
local MAIN_SECTION_NAME = icon(0x26CF) .. " Main"
local SETTINGS_SECTION_NAME = icon(0x2699) .. " Settings"
local VISUAL_SECTION_NAME = icon(0x1F3A8) .. " Visuals"
local STATUS_SECTION_NAME = icon(0x1F4CC) .. " Status"

local AUTO_FARM_NAME = "Auto Farm Stones"
local USE_WORLD_INTERACTIONS_NAME = "Use World Interactions"
local USE_REMOTE_FALLBACK_NAME = "Use Remote Fallback"
local SCAN_ALL_DESCENDANTS_NAME = "Scan All Descendants"
local FARM_DELAY_NAME = "Farm Delay"
local REACH_DISTANCE_NAME = "Reach Distance"
local TOUCH_DURATION_NAME = "Touch Duration"
local COIN_COUNT_NAME = "Coin Count"
local ZONE_ID_NAME = "Zone Id"
local SHOW_TARGET_HIGHLIGHT_NAME = "Show Target Highlight"
local HIGHLIGHT_COLOR_NAME = "Stone Highlight Color"
local SESSION_STATUS_NAME = "Session Status: Idle"
local LAST_METHOD_NAME = "Last Harvest Method: None"
local HARVESTED_STONES_NAME = "Harvested Stones: 0"
local ANTI_AFK_NAME = "Anti AFK is always active"

local STONE_KEYWORDS = {
	"stone",
	"stones",
	"rock",
	"rocks",
	"ore",
	"ores",
	"mineral",
	"deposit",
	"node",
	"mine",
}

local DATA_KEYWORDS = {
	"rarity",
	"zone",
	"count",
	"reward",
	"coin",
	"uuid",
	"guid",
	"token",
}

local SEARCH_ROOT_KEYWORDS = {
	"stone",
	"rock",
	"ore",
	"mine",
	"node",
	"collect",
	"pickup",
	"spawn",
	"drop",
	"zone",
}

local function parseHexColor(hex)
	local clean = tostring(hex or "#ffffff"):gsub("#", "")
	if #clean == 3 then
		clean = clean:sub(1, 1) .. clean:sub(1, 1) .. clean:sub(2, 2) .. clean:sub(2, 2) .. clean:sub(3, 3) .. clean:sub(3, 3)
	end
	if #clean < 6 then
		clean = clean .. string.rep("f", 6 - #clean)
	end

	local r = tonumber(clean:sub(1, 2), 16) or 255
	local g = tonumber(clean:sub(3, 4), 16) or 255
	local b = tonumber(clean:sub(5, 6), 16) or 255
	return Color3.fromRGB(r, g, b)
end

local Context = {
	Alive = true,
	Enabled = false,
	UseWorldInteractions = true,
	UseRemoteFallback = true,
	ScanAllDescendants = true,
	ShowTargetHighlight = true,
	FarmDelay = 0.18,
	ReachDistance = 18,
	TouchDuration = 0.10,
	CoinCount = 1,
	ZoneId = 1,
	HighlightColor = "#f59e0b",
	HarvestedStones = 0,
	SessionStatus = "Idle",
	LastHarvestMethod = "None",
	CandidateScanDirty = true,
	LastCandidateScan = 0,
	Candidates = {},
	CandidateCooldowns = setmetatable({}, {__mode = "k"}),
	SeenTokens = {},
	Connections = {},
	HookInstalled = false,
	HookFunction = nil,
	CapturedPayload = nil,
	LoopId = 0,
	StatusRefreshQueued = false,
	Window = nil,
	Highlight = nil,
	CurrentTarget = nil,
}

SharedEnvironment.SigmatikStoneFarmContext = Context

local function addConnection(connection)
	if connection then
		Context.Connections[#Context.Connections + 1] = connection
	end
	return connection
end

local function disconnectAll()
	for index = 1, #Context.Connections do
		local connection = Context.Connections[index]
		if connection then
			connection:Disconnect()
		end
	end

	table.clear(Context.Connections)
end

local function getRequestEarnCoinsRemote()
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEvents then
		remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 5)
	end

	if not remoteEvents then
		return nil
	end

	local remote = remoteEvents:FindFirstChild("RequestEarnCoins")
	if not remote then
		remote = remoteEvents:WaitForChild("RequestEarnCoins", 5)
	end

	return remote
end

local function getRootPart()
	local character = LocalPlayer and LocalPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getCandidatePart(candidate)
	if not candidate then
		return nil
	end

	if candidate:IsA("BasePart") then
		return candidate
	end

	if candidate:IsA("Model") then
		return candidate.PrimaryPart or candidate:FindFirstChildWhichIsA("BasePart", true)
	end

	return candidate:FindFirstChildWhichIsA("BasePart", true)
end

local function getCandidateAdornee(candidate)
	if not candidate then
		return nil
	end

	if candidate:IsA("Model") or candidate:IsA("BasePart") then
		return candidate
	end

	return getCandidatePart(candidate)
end

local function hasKeyword(text, keywords)
	local lowered = string.lower(tostring(text or ""))
	if lowered == "" then
		return false
	end

	for _, keyword in ipairs(keywords) do
		if string.find(lowered, keyword, 1, true) then
			return true
		end
	end

	return false
end

local function isUuid(value)
	if type(value) ~= "string" then
		return false
	end

	return string.match(value, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local function candidateExists(candidate)
	return candidate ~= nil and candidate.Parent ~= nil
end

local function getDistanceToCandidate(candidate)
	local rootPart = getRootPart()
	local candidatePart = getCandidatePart(candidate)

	if not rootPart or not candidatePart then
		return math.huge
	end

	return (rootPart.Position - candidatePart.Position).Magnitude
end

local function setHelperStatus(text)
	if Context.SessionStatus == text then
		return
	end

	Context.SessionStatus = text
end

local function setCurrentTarget(candidate)
	Context.CurrentTarget = candidate

	if Context.Highlight then
		if not Context.ShowTargetHighlight or not candidateExists(candidate) then
			Context.Highlight.Adornee = nil
		else
			Context.Highlight.Adornee = getCandidateAdornee(candidate)
		end
	end
end

local function ensureHighlight()
	if not Context.ShowTargetHighlight then
		if Context.Highlight then
			Context.Highlight.Enabled = false
			Context.Highlight.Adornee = nil
		end
		return
	end

	if not Context.Highlight or not Context.Highlight.Parent then
		local highlight = Instance.new("Highlight")
		highlight.Name = "SigmatikStoneFarmHighlight"
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 0.72
		highlight.OutlineTransparency = 0.15
		highlight.Parent = (gethui and gethui()) or CoreGui
		Context.Highlight = highlight
	end

	Context.Highlight.Enabled = true
	Context.Highlight.FillColor = parseHexColor(Context.HighlightColor)
	Context.Highlight.OutlineColor = parseHexColor(Context.HighlightColor)
	Context.Highlight.Adornee = getCandidateAdornee(Context.CurrentTarget)
end

local function cleanupHighlight()
	if Context.Highlight then
		Context.Highlight:Destroy()
		Context.Highlight = nil
	end
end

local Window

local function findControl(tabName, moduleName, sectionName, controlName)
	if not Window then
		return nil, nil
	end

	local module = Window:GetModule(tabName, moduleName)
	if not module then
		return nil, nil
	end

	local section = module.SectionLookup[sectionName]
	if not section then
		return nil, module
	end

	for _, control in ipairs(section.Controls) do
		if control.Name == controlName then
			return control, module
		end
	end

	return nil, module
end

local function queueStatusRefresh()
	if Context.StatusRefreshQueued then
		return
	end

	Context.StatusRefreshQueued = true

	task.delay(0.12, function()
		Context.StatusRefreshQueued = false

		if not Context.Alive then
			return
		end

		local sessionControl, module = findControl(TAB_NAME, MODULE_NAME, STATUS_SECTION_NAME, SESSION_STATUS_NAME)
		if sessionControl then
			sessionControl.Content = "Session Status: " .. Context.SessionStatus
		end

		local lastMethodControl = findControl(TAB_NAME, MODULE_NAME, STATUS_SECTION_NAME, LAST_METHOD_NAME)
		if lastMethodControl then
			lastMethodControl.Content = "Last Harvest Method: " .. Context.LastHarvestMethod
		end

		local harvestedControl = findControl(TAB_NAME, MODULE_NAME, STATUS_SECTION_NAME, HARVESTED_STONES_NAME)
		if harvestedControl then
			harvestedControl.Content = "Harvested Stones: " .. tostring(Context.HarvestedStones)
		end

		if Window and module and Window.selectedModule == module then
			pcall(function()
				Window:_renderSettingsPanel()
			end)
		end
	end)
end

local function updateStatus(statusText, methodText)
	if statusText then
		Context.SessionStatus = statusText
	end

	if methodText then
		Context.LastHarvestMethod = methodText
	end

	queueStatusRefresh()
end

local function moveNearCandidate(candidatePart)
	local rootPart = getRootPart()
	if not rootPart or not candidatePart then
		return false
	end

	local currentDistance = (rootPart.Position - candidatePart.Position).Magnitude
	if currentDistance <= Context.ReachDistance then
		return true
	end

	local targetPosition = candidatePart.Position + Vector3.new(0, math.max(candidatePart.Size.Y * 0.5, 2) + 3, 0)
	rootPart.CFrame = CFrame.new(targetPosition)
	task.wait(0.05)
	return true
end

local function scanValue(result, key, value)
	local keyText = string.lower(tostring(key or ""))

	if type(value) == "string" then
		if not result.token and isUuid(value) then
			result.token = value
		end

		if not result.rarityName and string.find(keyText, "rarity", 1, true) then
			result.rarityName = value
		end

		local numericValue = tonumber(value)
		if numericValue then
			if not result.zoneId and string.find(keyText, "zone", 1, true) then
				result.zoneId = math.max(1, math.floor(numericValue))
			end

			if not result.count and (string.find(keyText, "count", 1, true) or string.find(keyText, "amount", 1, true) or string.find(keyText, "coin", 1, true)) then
				result.count = math.max(1, math.floor(numericValue))
			end
		end
	elseif type(value) == "number" then
		if not result.zoneId and string.find(keyText, "zone", 1, true) then
			result.zoneId = math.max(1, math.floor(value))
		end

		if not result.count and (string.find(keyText, "count", 1, true) or string.find(keyText, "amount", 1, true) or string.find(keyText, "coin", 1, true)) then
			result.count = math.max(1, math.floor(value))
		end
	end
end

local function extractCandidatePayload(candidate)
	local result = {
		rarityName = Context.CapturedPayload and Context.CapturedPayload.rarityName or "Common",
		zoneId = Context.CapturedPayload and Context.CapturedPayload.zoneId or Context.ZoneId,
		count = Context.CapturedPayload and Context.CapturedPayload.count or Context.CoinCount,
		token = nil,
	}

	local function scanInstance(instance)
		if not instance then
			return
		end

		if not result.token and isUuid(instance.Name) then
			result.token = instance.Name
		end

		local ok, attributes = pcall(function()
			return instance:GetAttributes()
		end)

		if ok and attributes then
			for key, value in pairs(attributes) do
				scanValue(result, key, value)
			end
		end

		if instance:IsA("StringValue") then
			scanValue(result, instance.Name, instance.Value)
		elseif instance:IsA("IntValue") or instance:IsA("NumberValue") then
			scanValue(result, instance.Name, instance.Value)
		elseif instance:IsA("ProximityPrompt") then
			if not result.rarityName and hasKeyword(instance.ObjectText, STONE_KEYWORDS) then
				result.rarityName = result.rarityName or "Common"
			end
		end
	end

	scanInstance(candidate)

	local scanned = 0
	for _, descendant in ipairs(candidate:GetDescendants()) do
		scanned = scanned + 1
		if scanned > 160 then
			break
		end

		scanInstance(descendant)
	end

	return result
end

local function candidateLooksLikeStone(candidate)
	if not candidate then
		return false
	end

	if hasKeyword(candidate.Name, STONE_KEYWORDS) then
		return true
	end

	local payload = extractCandidatePayload(candidate)
	if payload.token then
		return true
	end

	local scanned = 0
	for _, descendant in ipairs(candidate:GetDescendants()) do
		scanned = scanned + 1
		if scanned > 80 then
			break
		end

		if descendant:IsA("ProximityPrompt") then
			if hasKeyword(descendant.ActionText, STONE_KEYWORDS) or hasKeyword(descendant.ObjectText, STONE_KEYWORDS) or hasKeyword(descendant.Parent and descendant.Parent.Name, STONE_KEYWORDS) then
				return true
			end
		elseif descendant:IsA("ClickDetector") then
			if hasKeyword(descendant.Parent and descendant.Parent.Name, STONE_KEYWORDS) then
				return true
			end
		elseif descendant:IsA("StringValue") then
			if hasKeyword(descendant.Name, DATA_KEYWORDS) or hasKeyword(descendant.Name, STONE_KEYWORDS) or isUuid(descendant.Value) then
				return true
			end
		elseif descendant:IsA("IntValue") or descendant:IsA("NumberValue") then
			if hasKeyword(descendant.Name, DATA_KEYWORDS) then
				return true
			end
		elseif descendant:IsA("BasePart") and hasKeyword(descendant.Name, STONE_KEYWORDS) then
			return true
		end
	end

	return false
end

local function resolveCandidateRoot(instance)
	local current = instance
	local fallback

	while current and current ~= Workspace do
		if current:IsA("Model") or current:IsA("Folder") or current:IsA("BasePart") then
			fallback = fallback or current
			if hasKeyword(current.Name, STONE_KEYWORDS) then
				return current
			end
		end

		current = current.Parent
	end

	return fallback
end

local function isInterestingInstance(instance)
	if instance:IsA("ProximityPrompt") then
		return hasKeyword(instance.ActionText, STONE_KEYWORDS) or hasKeyword(instance.ObjectText, STONE_KEYWORDS) or hasKeyword(instance.Parent and instance.Parent.Name, STONE_KEYWORDS)
	end

	if instance:IsA("ClickDetector") then
		return hasKeyword(instance.Parent and instance.Parent.Name, STONE_KEYWORDS)
	end

	if instance:IsA("StringValue") then
		return hasKeyword(instance.Name, STONE_KEYWORDS) or hasKeyword(instance.Name, DATA_KEYWORDS) or isUuid(instance.Value)
	end

	if instance:IsA("IntValue") or instance:IsA("NumberValue") then
		return hasKeyword(instance.Name, DATA_KEYWORDS)
	end

	if instance:IsA("BasePart") or instance:IsA("Model") or instance:IsA("Folder") then
		return hasKeyword(instance.Name, STONE_KEYWORDS)
	end

	return false
end

local function getSearchRoots()
	if Context.ScanAllDescendants then
		return {Workspace}
	end

	local roots = {}
	for _, child in ipairs(Workspace:GetChildren()) do
		if hasKeyword(child.Name, SEARCH_ROOT_KEYWORDS) then
			roots[#roots + 1] = child
		end
	end

	if #roots == 0 then
		roots[1] = Workspace
	end

	return roots
end

local function rebuildCandidates()
	local bucket = {}
	local seen = {}

	local function tryAddCandidate(instance)
		local candidate = resolveCandidateRoot(instance)
		if not candidate or seen[candidate] then
			return
		end

		if candidateLooksLikeStone(candidate) then
			seen[candidate] = true
			bucket[#bucket + 1] = candidate
		end
	end

	for _, root in ipairs(getSearchRoots()) do
		tryAddCandidate(root)

		for _, descendant in ipairs(root:GetDescendants()) do
			if isInterestingInstance(descendant) then
				tryAddCandidate(descendant)
			end
		end
	end

	table.sort(bucket, function(left, right)
		return getDistanceToCandidate(left) < getDistanceToCandidate(right)
	end)

	Context.Candidates = bucket
	Context.CandidateScanDirty = false
	Context.LastCandidateScan = os.clock()

	if Context.Enabled then
		if #bucket == 0 then
			setHelperStatus("Waiting for stone targets")
		else
			setHelperStatus("Stone targets found: " .. tostring(#bucket))
		end
		queueStatusRefresh()
	end
end

local function refreshCandidatesIfNeeded(force)
	if force or Context.CandidateScanDirty or (os.clock() - Context.LastCandidateScan) >= 2 then
		rebuildCandidates()
	end
end

local function getNextCandidate()
	refreshCandidatesIfNeeded(false)

	local now = os.clock()
	local bestCandidate
	local bestDistance = math.huge
	local nextList = {}

	for _, candidate in ipairs(Context.Candidates) do
		if candidateExists(candidate) then
			nextList[#nextList + 1] = candidate
			local lastAttempt = Context.CandidateCooldowns[candidate] or 0
			if now - lastAttempt >= math.max(Context.FarmDelay, 0.35) then
				local distance = getDistanceToCandidate(candidate)
				if distance < bestDistance then
					bestDistance = distance
					bestCandidate = candidate
				end
			end
		end
	end

	Context.Candidates = nextList
	return bestCandidate
end

local function markCandidateCooldown(candidate)
	if candidate then
		Context.CandidateCooldowns[candidate] = os.clock()
	end
end

local function activatePrompt(prompt)
	if not prompt then
		return false
	end

	local success = false

	if fireproximityprompt then
		success = pcall(function()
			fireproximityprompt(prompt, prompt.HoldDuration)
		end)

		if not success then
			success = pcall(function()
				fireproximityprompt(prompt)
			end)
		end
	end

	if not success then
		success = pcall(function()
			prompt:InputHoldBegin()
			task.wait(math.max(prompt.HoldDuration, Context.TouchDuration))
			prompt:InputHoldEnd()
		end)
	end

	return success
end

local function activateClick(clickDetector)
	if not clickDetector or not fireclickdetector then
		return false
	end

	return pcall(function()
		fireclickdetector(clickDetector)
	end)
end

local function activateTouch(candidatePart)
	local rootPart = getRootPart()
	if not rootPart or not candidatePart then
		return false
	end

	if firetouchinterest then
		local ok = pcall(function()
			firetouchinterest(rootPart, candidatePart, 0)
			task.wait(Context.TouchDuration)
			firetouchinterest(rootPart, candidatePart, 1)
		end)

		if ok then
			return true
		end
	end

	local ok = pcall(function()
		rootPart.CFrame = candidatePart.CFrame + Vector3.new(0, math.max(candidatePart.Size.Y * 0.5, 2) + 1, 0)
	end)

	if ok then
		task.wait(Context.TouchDuration)
	end

	return ok
end

local function capturePayloadFromArgs(args)
	local entries = args[1]
	local entry = type(entries) == "table" and type(entries[1]) == "table" and entries[1] or nil
	local token = args[3]

	if type(entry) ~= "table" or type(token) ~= "string" or not isUuid(token) then
		return nil
	end

	local fallbackRarity = Context.CapturedPayload and Context.CapturedPayload.rarityName or "Common"

	return {
		rarityName = tostring(entry.rarityName or fallbackRarity),
		zoneId = math.max(1, math.floor(tonumber(entry.zoneId) or Context.ZoneId)),
		count = math.max(1, math.floor(tonumber(entry.count) or Context.CoinCount)),
		token = token,
	}
end

local function applyCapturedPayload(payload)
	if not payload then
		return
	end

	local wasNewToken = not Context.SeenTokens[payload.token]
	Context.CapturedPayload = payload
	Context.ZoneId = payload.zoneId
	Context.CoinCount = payload.count
	Context.SeenTokens[payload.token] = true

	if wasNewToken then
		Context.HarvestedStones = Context.HarvestedStones + 1
	end

	Context.SessionStatus = string.format("Captured %s token in zone %d", payload.rarityName, payload.zoneId)
	Context.LastHarvestMethod = "Live RequestEarnCoins"

	if Window then
		Window:SetControlValue(TAB_NAME, MODULE_NAME, SETTINGS_SECTION_NAME, ZONE_ID_NAME, Context.ZoneId)
		Window:SetControlValue(TAB_NAME, MODULE_NAME, SETTINGS_SECTION_NAME, COIN_COUNT_NAME, Context.CoinCount)
	end

	queueStatusRefresh()
end

local function installRemoteCapture()
	if Context.HookInstalled or not hookmetamethod or not getnamecallmethod then
		return
	end

	local originalNamecall
	originalNamecall = hookmetamethod(game, "__namecall", (newcclosure and newcclosure(function(self, ...)
		local args = {...}
		local method = getnamecallmethod()

		if method == "FireServer" then
			local requestRemote = getRequestEarnCoinsRemote()
			if requestRemote and self == requestRemote then
				local payload = capturePayloadFromArgs(args)
				applyCapturedPayload(payload)
			end
		end

		return originalNamecall(self, ...)
	end) or function(self, ...)
		local args = {...}
		local method = getnamecallmethod()

		if method == "FireServer" then
			local requestRemote = getRequestEarnCoinsRemote()
			if requestRemote and self == requestRemote then
				local payload = capturePayloadFromArgs(args)
				applyCapturedPayload(payload)
			end
		end

		return originalNamecall(self, ...)
	end))

	Context.HookInstalled = true
end

local function sendRemoteFallback(candidate)
	local requestRemote = getRequestEarnCoinsRemote()
	if not requestRemote then
		return false
	end

	local payload = extractCandidatePayload(candidate)
	if not payload.token then
		return false
	end

	if Context.SeenTokens[payload.token] then
		return false
	end

	local candidatePart = getCandidatePart(candidate)
	if candidatePart then
		moveNearCandidate(candidatePart)
	end

	local args = {
		{
			{
				rarityName = payload.rarityName or "Common",
				zoneId = math.max(1, math.floor(tonumber(payload.zoneId) or Context.ZoneId)),
				count = math.max(1, math.floor(tonumber(payload.count) or Context.CoinCount)),
			},
		},
		0,
		payload.token,
	}

	local ok = pcall(function()
		requestRemote:FireServer(unpack(args))
	end)

	if ok then
		Context.LastHarvestMethod = "Remote UUID Fallback"
		Context.SessionStatus = string.format("Sent %s token in zone %d", tostring(args[1][1].rarityName), tonumber(args[1][1].zoneId) or Context.ZoneId)
		Context.SeenTokens[payload.token] = true
		queueStatusRefresh()
	end

	return ok
end

local function tryWorldInteractions(candidate)
	local candidatePart = getCandidatePart(candidate)
	if candidatePart then
		moveNearCandidate(candidatePart)
	end

	for _, descendant in ipairs(candidate:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			if activatePrompt(descendant) then
				Context.LastHarvestMethod = "Proximity Prompt"
				Context.SessionStatus = "Triggered stone prompt"
				queueStatusRefresh()
				return true
			end
		end
	end

	for _, descendant in ipairs(candidate:GetDescendants()) do
		if descendant:IsA("ClickDetector") then
			if activateClick(descendant) then
				Context.LastHarvestMethod = "Click Detector"
				Context.SessionStatus = "Triggered stone click detector"
				queueStatusRefresh()
				return true
			end
		end
	end

	if candidatePart and activateTouch(candidatePart) then
		Context.LastHarvestMethod = "Touch Interest"
		Context.SessionStatus = "Triggered stone touch"
		queueStatusRefresh()
		return true
	end

	return false
end

local function harvestCandidate(candidate)
	if not candidateExists(candidate) then
		return false
	end

	setCurrentTarget(candidate)
	ensureHighlight()
	markCandidateCooldown(candidate)

	local interacted = false
	if Context.UseWorldInteractions then
		interacted = tryWorldInteractions(candidate)
	end

	if interacted then
		return true
	end

	if Context.UseRemoteFallback then
		return sendRemoteFallback(candidate)
	end

	return false
end

local function farmLoop(loopId)
	while Context.Alive and Context.Enabled and Context.LoopId == loopId do
		local candidate = getNextCandidate()
		if candidate then
			local ok = harvestCandidate(candidate)
			if not ok then
				updateStatus("Target found but no usable interaction path", "No valid path")
			end
		else
			updateStatus("Waiting for stone targets", Context.LastHarvestMethod)
		end

		task.wait(Context.FarmDelay)
	end

	if Context.LoopId == loopId and not Context.Enabled then
		setCurrentTarget(nil)
		ensureHighlight()
	end
end

local function setAutoFarmEnabled(enabled)
	Context.Enabled = not not enabled

	if Context.Enabled then
		Context.LoopId = Context.LoopId + 1
		updateStatus("Starting stone harvester", Context.LastHarvestMethod)
		refreshCandidatesIfNeeded(true)
		task.spawn(farmLoop, Context.LoopId)
	else
		Context.LoopId = Context.LoopId + 1
		setCurrentTarget(nil)
		updateStatus("Idle", Context.LastHarvestMethod)
	end
end

local function buildWindow()
	return Library:Create({
		Title = "tg: @sigmatik323",
		ConfigName = "Stone Farm",
		SearchPlaceholder = "Search modules...",
		Accent = "#f59e0b",
		AccentSoft = "#fbbf24",
		WindowFill = "#0f172acc",
		DimBackground = "#02061770",
		GuiToggleKey = Enum.KeyCode.RightShift,
		Tabs = {
			{
				Name = TAB_NAME,
				Icon = "misc",
				Modules = {
					{
						Name = MODULE_NAME,
						Enabled = false,
						Sections = {
							{
								Name = MAIN_SECTION_NAME,
								Controls = {
									{
										Type = "toggle",
										Name = AUTO_FARM_NAME,
										CurrentValue = false,
										Callback = function(value)
											setAutoFarmEnabled(value)
										end,
									},
									{
										Type = "toggle",
										Name = USE_WORLD_INTERACTIONS_NAME,
										CurrentValue = true,
										Callback = function(value)
											Context.UseWorldInteractions = value
										end,
									},
									{
										Type = "toggle",
										Name = USE_REMOTE_FALLBACK_NAME,
										CurrentValue = true,
										Callback = function(value)
											Context.UseRemoteFallback = value
										end,
									},
									{
										Type = "toggle",
										Name = SCAN_ALL_DESCENDANTS_NAME,
										CurrentValue = true,
										Callback = function(value)
											Context.ScanAllDescendants = value
											Context.CandidateScanDirty = true
										end,
									},
								},
							},
							{
								Name = SETTINGS_SECTION_NAME,
								Controls = {
									{
										Type = "slider",
										Name = FARM_DELAY_NAME,
										Min = 0.05,
										Max = 1.50,
										Increment = 0.01,
										CurrentValue = 0.18,
										Callback = function(value)
											Context.FarmDelay = value
										end,
									},
									{
										Type = "slider",
										Name = REACH_DISTANCE_NAME,
										Min = 6,
										Max = 60,
										Increment = 1,
										CurrentValue = 18,
										Callback = function(value)
											Context.ReachDistance = value
										end,
									},
									{
										Type = "slider",
										Name = TOUCH_DURATION_NAME,
										Min = 0.05,
										Max = 0.75,
										Increment = 0.01,
										CurrentValue = 0.10,
										Callback = function(value)
											Context.TouchDuration = value
										end,
									},
									{
										Type = "slider",
										Name = COIN_COUNT_NAME,
										Min = 1,
										Max = 100,
										Increment = 1,
										CurrentValue = 1,
										Callback = function(value)
											Context.CoinCount = value
										end,
									},
									{
										Type = "slider",
										Name = ZONE_ID_NAME,
										Min = 1,
										Max = 100,
										Increment = 1,
										CurrentValue = 1,
										Callback = function(value)
											Context.ZoneId = value
										end,
									},
								},
							},
							{
								Name = VISUAL_SECTION_NAME,
								Controls = {
									{
										Type = "toggle",
										Name = SHOW_TARGET_HIGHLIGHT_NAME,
										CurrentValue = true,
										Callback = function(value)
											Context.ShowTargetHighlight = value
											ensureHighlight()
										end,
									},
									{
										Type = "colorpicker",
										Name = HIGHLIGHT_COLOR_NAME,
										CurrentValue = "#f59e0b",
										Callback = function(value)
											Context.HighlightColor = value
											ensureHighlight()
										end,
									},
								},
							},
							{
								Name = STATUS_SECTION_NAME,
								Controls = {
									{
										Type = "label",
										Name = SESSION_STATUS_NAME,
										Content = SESSION_STATUS_NAME,
									},
									{
										Type = "label",
										Name = LAST_METHOD_NAME,
										Content = LAST_METHOD_NAME,
									},
									{
										Type = "label",
										Name = HARVESTED_STONES_NAME,
										Content = HARVESTED_STONES_NAME,
									},
									{
										Type = "label",
										Name = ANTI_AFK_NAME,
										Content = ANTI_AFK_NAME,
									},
								},
							},
						},
					},
				},
			},
		},
	})
end

local function cleanup()
	Context.Alive = false
	Context.Enabled = false
	Context.LoopId = Context.LoopId + 1
	disconnectAll()
	cleanupHighlight()

	if Context.Window then
		pcall(function()
			Context.Window:Destroy()
		end)
		Context.Window = nil
	end

	SharedEnvironment.SigmatikStoneFarmContext = nil
end

Context.Cleanup = cleanup

addConnection(LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
end))

addConnection(Workspace.DescendantAdded:Connect(function(instance)
	if isInterestingInstance(instance) then
		Context.CandidateScanDirty = true
	end
end))

addConnection(Workspace.DescendantRemoving:Connect(function(instance)
	if Context.CurrentTarget == instance or isInterestingInstance(instance) then
		Context.CandidateScanDirty = true
	end
end))

Window = buildWindow()
Context.Window = Window

installRemoteCapture()
ensureHighlight()
refreshCandidatesIfNeeded(true)
queueStatusRefresh()
