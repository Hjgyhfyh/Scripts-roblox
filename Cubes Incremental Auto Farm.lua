local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local SharedEnvironment = getgenv and getgenv() or _G
local PreviousState = SharedEnvironment.SigmatikCubesIncrementalState

if PreviousState and PreviousState.Stop then
	PreviousState.Stop()
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/sigmatik_ui_library.lua"))()

local Knit = ReplicatedStorage
	:WaitForChild("Packages")
	:WaitForChild("_Index")
	:WaitForChild("sleitnick_knit@1.7.0")
	:WaitForChild("knit")

local CollectCubeRemote = Knit
	:WaitForChild("Services")
	:WaitForChild("CubesService")
	:WaitForChild("RE")
	:WaitForChild("CollectCube")

local BuyRuneRemote = Knit
	:WaitForChild("Services")
	:WaitForChild("RunesService")
	:WaitForChild("RE")
	:WaitForChild("BuyRune")

local ConvertRemote = Knit
	:WaitForChild("Services")
	:WaitForChild("ConverterService")
	:WaitForChild("RE")
	:WaitForChild("Convert")

local CUBES_TAB_NAME = "💎 Cubes"
local RUNES_TAB_NAME = "🔮 Runes"
local CONVERSION_TAB_NAME = "🔄 Conversion"

local FARM_MODULE_NAME = "Auto Farm Cubes"
local FARM_MAIN_SECTION = "🚀 Main"
local FARM_SETTINGS_SECTION = "⚙ Settings"
local FARM_TOGGLE_NAME = "Auto Farm Cubes"
local FARM_STATUS_NAME = "Farm Status"
local FARM_COUNT_NAME = "Collected Cubes"
local FARM_RADIUS_NAME = "Collect Radius"
local FARM_DELAY_NAME = "Collect Delay"

local BRING_MODULE_NAME = "Bring Cubes To Player"
local BRING_MAIN_SECTION = "📦 Main"
local BRING_SETTINGS_SECTION = "⚙ Settings"
local BRING_TOGGLE_NAME = "Bring Cubes To Player"
local BRING_STATUS_NAME = "Bring Status"
local BRING_COUNT_NAME = "Moved Cubes"
local BRING_DELAY_NAME = "Bring Delay"

local RUNE_MODULE_NAME = "Open Basic Rune"
local RUNE_MAIN_SECTION = "🔮 Main"
local RUNE_SETTINGS_SECTION = "⚙ Settings"
local RUNE_TOGGLE_NAME = "Open Basic Rune"
local RUNE_STATUS_NAME = "Rune Status"
local RUNE_COUNT_NAME = "Opened Basic Runes"
local RUNE_DELAY_NAME = "Rune Open Delay"

local BLUEPRINT_RUNE_MODULE_NAME = "Buy Blueprint Runes"
local BLUEPRINT_RUNE_MAIN_SECTION = "🌈 Main"
local BLUEPRINT_RUNE_SETTINGS_SECTION = "⚙ Settings"
local BLUEPRINT_RUNE_TOGGLE_NAME = "Buy Blueprint Runes"
local BLUEPRINT_RUNE_STATUS_NAME = "Blueprint Rune Status"
local BLUEPRINT_RUNE_COUNT_NAME = "Bought Blueprint Runes"
local BLUEPRINT_RUNE_DELAY_NAME = "Blueprint Rune Delay"

local CONVERSION_MODULE_NAME = "Blueprint Conversion"
local CONVERSION_MAIN_SECTION = "🔁 Main"
local CONVERSION_SETTINGS_SECTION = "⚙ Settings"
local CONVERSION_CUBES_TOGGLE_NAME = "Buy Blueprint Cubes"
local CONVERSION_CUBES_STATUS_NAME = "Blueprint Cubes Status"
local CONVERSION_CUBES_COUNT_NAME = "Bought Blueprint Cubes"
local CONVERSION_CUBES_DELAY_NAME = "Blueprint Cube Delay"

local State = {
	Alive = true,
	Syncing = {
		Farm = false,
		Bring = false,
		Rune = false,
		BlueprintRune = false,
		Conversion = false,
	},
	FarmEnabled = false,
	BringEnabled = false,
	RuneEnabled = false,
	BlueprintRuneEnabled = false,
	ConvertCubesEnabled = false,
	CollectRadius = 1000,
	CollectDelay = 0.1,
	BringDelay = 0.05,
	RuneDelay = 1,
	BlueprintRuneDelay = 1,
	ConvertCubesDelay = 1,
	CollectedCubes = 0,
	MovedCubes = 0,
	OpenedBasicRunes = 0,
	BoughtBlueprintCubes = 0,
	BoughtBlueprintRunes = 0,
	FarmStatus = "Idle",
	BringStatus = "Idle",
	RuneStatus = "Idle",
	BlueprintCubesStatus = "Idle",
	BlueprintRunesStatus = "Idle",
	Window = nil,
	CubeRecords = {},
	CubeRecordList = {},
	CubeCacheDirty = false,
	LastFullScan = 0,
	Connections = {},
	CharacterConnections = {},
	Character = nil,
	Humanoid = nil,
	RootPart = nil,
	CharacterAlive = false,
}

SharedEnvironment.SigmatikCubesIncrementalState = State

local Window
local FarmStatusControl
local FarmCountControl
local BringStatusControl
local BringCountControl
local RuneStatusControl
local RuneCountControl
local BlueprintRuneStatusControl
local BlueprintRuneCountControl
local BlueprintCubesStatusControl
local BlueprintCubesCountControl

local function disconnectConnections(connections)
	for index = 1, #connections do
		local connection = connections[index]
		if connection then
			connection:Disconnect()
		end
	end

	table.clear(connections)
end

local function refreshCharacterState(character)
	if State.Character ~= character then
		return
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") or nil

	State.Humanoid = humanoid
	State.RootPart = rootPart
	State.CharacterAlive = humanoid ~= nil and rootPart ~= nil and humanoid.Health > 0
end

local function attachCharacter(character)
	disconnectConnections(State.CharacterConnections)

	State.Character = character
	State.Humanoid = nil
	State.RootPart = nil
	State.CharacterAlive = false

	if not character then
		return
	end

	local boundHumanoid

	local function bindHumanoid(humanoid)
		if not humanoid or humanoid == boundHumanoid then
			return
		end

		boundHumanoid = humanoid
		State.CharacterConnections[#State.CharacterConnections + 1] = humanoid.Died:Connect(function()
			if State.Character == character then
				State.CharacterAlive = false
				State.RootPart = nil
			end
		end)
		State.CharacterConnections[#State.CharacterConnections + 1] = humanoid.HealthChanged:Connect(function()
			refreshCharacterState(character)
		end)
	end

	refreshCharacterState(character)
	bindHumanoid(State.Humanoid)

	State.CharacterConnections[#State.CharacterConnections + 1] = character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") or child.Name == "HumanoidRootPart" then
			refreshCharacterState(character)
			if child:IsA("Humanoid") then
				bindHumanoid(child)
			end
		end
	end)

	State.CharacterConnections[#State.CharacterConnections + 1] = character.ChildRemoved:Connect(function(child)
		if child == State.Humanoid or child == State.RootPart or child:IsA("Humanoid") or child.Name == "HumanoidRootPart" then
			refreshCharacterState(character)
		end
	end)

	State.CharacterConnections[#State.CharacterConnections + 1] = character.AncestryChanged:Connect(function(_, parent)
		if State.Character == character and parent == nil then
			State.Humanoid = nil
			State.RootPart = nil
			State.CharacterAlive = false
		end
	end)
end

State.Connections[#State.Connections + 1] = LocalPlayer.CharacterAdded:Connect(function(character)
	attachCharacter(character)
end)

State.Connections[#State.Connections + 1] = LocalPlayer.CharacterRemoving:Connect(function(character)
	if State.Character == character then
		attachCharacter(nil)
	end
end)

attachCharacter(LocalPlayer.Character)

local function getCharacterRoot()
	local rootPart = State.RootPart
	local humanoid = State.Humanoid

	if rootPart and rootPart.Parent and humanoid and humanoid.Parent and humanoid.Health > 0 then
		return rootPart
	end

	return nil
end

local function getClientCubesRoot()
	local scripted = Workspace:FindFirstChild("__Scripted")
	if not scripted then
		return nil
	end

	local clientCubes = scripted:FindFirstChild("__ClientCubes")
	if not clientCubes then
		return nil
	end

	return clientCubes
end

local IdKeys = {
	"CubeId",
	"Id",
	"UUID",
	"Guid",
	"UID",
}

local function getStringValue(instance, name)
	local valueObject = instance:FindFirstChild(name)
	if valueObject and valueObject:IsA("StringValue") and valueObject.Value ~= "" then
		return valueObject.Value
	end

	return nil
end

local function getCubeId(instance)
	local current = instance

	while current and current ~= Workspace do
		for index = 1, #IdKeys do
			local key = IdKeys[index]
			local attribute = current:GetAttribute(key)

			if typeof(attribute) == "string" and attribute ~= "" then
				return attribute
			end

			local value = getStringValue(current, key)
			if value then
				return value
			end
		end

		current = current.Parent
	end

	local path = instance:GetFullName()
	return path:match("[%w]+%-%w+%-%w+%-%w+%-%w+")
end

local function getObjectPosition(instance)
	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Model") then
		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok then
			return pivot.Position
		end

		local part = instance:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part.Position
		end
	end

	return nil
end

local function looksLikeCube(instance)
	local current = instance

	while current and current ~= Workspace do
		local lowerName = string.lower(current.Name)
		if lowerName:find("cube") then
			return true
		end

		for index = 1, #IdKeys do
			local key = IdKeys[index]
			local attribute = current:GetAttribute(key)
			if typeof(attribute) == "string" and attribute ~= "" then
				return true
			end

			if getStringValue(current, key) then
				return true
			end
		end

		current = current.Parent
	end

	return false
end

local function rebuildCubeRecordList()
	local records = {}

	for target, record in pairs(State.CubeRecords) do
		if target.Parent and target:IsDescendantOf(Workspace) and record.Id then
			records[#records + 1] = record
		else
			State.CubeRecords[target] = nil
		end
	end

	State.CubeRecordList = records
	State.CubeCacheDirty = false
end

local function registerCubeCandidate(instance)
	if not instance or not instance.Parent then
		return
	end

	if not (instance:IsA("Model") or instance:IsA("BasePart")) or not looksLikeCube(instance) then
		return
	end

	local ownerModel = instance:IsA("Model") and instance or instance:FindFirstAncestorOfClass("Model")
	local target = ownerModel or instance
	local cubeId = getCubeId(instance) or getCubeId(target)

	if not cubeId then
		return
	end

	local record = State.CubeRecords[target]
	if record then
		record.Id = cubeId
		return
	end

	State.CubeRecords[target] = {
		Target = target,
		Id = cubeId,
	}
	State.CubeCacheDirty = true
end

local function pruneCubeCache()
	local changed = false

	for target in pairs(State.CubeRecords) do
		if not target.Parent or not target:IsDescendantOf(Workspace) then
			State.CubeRecords[target] = nil
			changed = true
		end
	end

	if changed then
		State.CubeCacheDirty = true
	end

	if State.CubeCacheDirty then
		rebuildCubeRecordList()
	end
end

local function fullScanCubeCache()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		registerCubeCandidate(descendant)
	end

	pruneCubeCache()
	State.LastFullScan = os.clock()
end

local function collectNearbyCubes()
	local rootPart = getCharacterRoot()
	if not rootPart then
		State.FarmStatus = "Waiting for respawn"
		return
	end

	local sent = 0
	local rootPosition = rootPart.Position
	local maxDistanceSquared = State.CollectRadius * State.CollectRadius

	if (os.clock() - State.LastFullScan) >= 5 then
		fullScanCubeCache()
	else
		pruneCubeCache()
	end

	for index = 1, #State.CubeRecordList do
		local record = State.CubeRecordList[index]
		local cubePosition = getObjectPosition(record.Target)

		if cubePosition then
			local offset = rootPosition - cubePosition
			if offset:Dot(offset) <= maxDistanceSquared then
				local ok = pcall(function()
					CollectCubeRemote:FireServer(record.Id)
				end)

				if ok then
					sent = sent + 1
				end
			end
		else
			State.CubeRecords[record.Target] = nil
			State.CubeCacheDirty = true
		end
	end

	if State.CubeCacheDirty then
		rebuildCubeRecordList()
	end

	if sent > 0 then
		State.CollectedCubes = State.CollectedCubes + sent
		State.FarmStatus = "Collecting"
	elseif #State.CubeRecordList > 0 then
		State.FarmStatus = "Waiting for cubes"
	else
		State.FarmStatus = "Scanning cubes"
	end
end

State.Connections[#State.Connections + 1] = Workspace.DescendantAdded:Connect(function(instance)
	registerCubeCandidate(instance)
end)

State.Connections[#State.Connections + 1] = Workspace.DescendantRemoving:Connect(function(instance)
	if State.CubeRecords[instance] then
		State.CubeRecords[instance] = nil
		State.CubeCacheDirty = true
		return
	end

	for target in pairs(State.CubeRecords) do
		if target == instance or target:IsDescendantOf(instance) then
			State.CubeRecords[target] = nil
			State.CubeCacheDirty = true
		end
	end
end)

fullScanCubeCache()

local function moveInstanceToPlayer(instance, targetCFrame)
	if instance:IsA("Model") then
		local ok = pcall(function()
			instance:PivotTo(targetCFrame)
		end)
		return ok
	end

	if instance:IsA("BasePart") then
		local ok = pcall(function()
			instance.CFrame = targetCFrame
		end)
		return ok
	end

	return false
end

local function getMovableCubeTargets(searchRoot)
	local targets = {}
	local seenTargets = {}

	local function registerTarget(instance)
		if not (instance:IsA("Model") or instance:IsA("BasePart")) or not looksLikeCube(instance) then
			return
		end

		local ownerModel = instance:IsA("Model") and instance or instance:FindFirstAncestorOfClass("Model")
		local target = ownerModel or instance

		if not seenTargets[target] then
			seenTargets[target] = true
			targets[#targets + 1] = target
		end
	end

	if searchRoot:IsA("Model") or searchRoot:IsA("BasePart") then
		registerTarget(searchRoot)
	end

	for _, descendant in ipairs(searchRoot:GetDescendants()) do
		registerTarget(descendant)
	end

	return targets
end

local function bringCubesToPlayer()
	local rootPart = getCharacterRoot()
	if not rootPart then
		State.BringStatus = "Waiting for respawn"
		return
	end

	local clientCubesRoot = getClientCubesRoot() or Workspace

	if clientCubesRoot == nil then
		State.BringStatus = "Cube container missing"
		return
	end

	local targetCFrame = rootPart.CFrame
	local moved = 0
	local targets = getMovableCubeTargets(clientCubesRoot)

	if #targets == 0 then
		State.BringStatus = "No cube parts found"
		return
	end

	for index = 1, #targets do
		if moveInstanceToPlayer(targets[index], targetCFrame) then
			moved = moved + 1
		end
	end

	if moved > 0 then
		State.MovedCubes = State.MovedCubes + moved
		State.BringStatus = "Bringing cubes"
	else
		State.BringStatus = "Waiting for cubes"
	end
end

local function openBasicRune()
	local ok = pcall(function()
		BuyRuneRemote:FireServer("Basic")
	end)

	if ok then
		State.OpenedBasicRunes = State.OpenedBasicRunes + 1
		State.RuneStatus = State.RuneEnabled and "Opening" or "Opened"
	else
		State.RuneStatus = "Open failed"
	end
end

local function buyBlueprintCubes()
	local ok = pcall(function()
		ConvertRemote:FireServer()
	end)

	if ok then
		State.BoughtBlueprintCubes = State.BoughtBlueprintCubes + 1
		State.BlueprintCubesStatus = State.ConvertCubesEnabled and "Converting" or "Bought"
	else
		State.BlueprintCubesStatus = "Buy failed"
	end
end

local function buyBlueprintRunes()
	local ok = pcall(function()
		BuyRuneRemote:FireServer("Colors")
	end)

	if ok then
		State.BoughtBlueprintRunes = State.BoughtBlueprintRunes + 1
		State.BlueprintRunesStatus = State.BlueprintRuneEnabled and "Buying" or "Bought"
	else
		State.BlueprintRunesStatus = "Buy failed"
	end
end

local function setFarmState(enabled, source)
	State.FarmEnabled = enabled
	State.FarmStatus = enabled and "Collecting" or "Idle"

	if not Window or State.Syncing.Farm then
		return
	end

	State.Syncing.Farm = true

	if source ~= "module" then
		Window:SetModuleEnabled(CUBES_TAB_NAME, FARM_MODULE_NAME, enabled)
	end

	if source ~= "toggle" then
		Window:SetControlValue(CUBES_TAB_NAME, FARM_MODULE_NAME, FARM_MAIN_SECTION, FARM_TOGGLE_NAME, enabled)
	end

	State.Syncing.Farm = false
end

local function setBringState(enabled, source)
	State.BringEnabled = enabled
	State.BringStatus = enabled and "Bringing cubes" or "Idle"

	if not Window or State.Syncing.Bring then
		return
	end

	State.Syncing.Bring = true

	if source ~= "module" then
		Window:SetModuleEnabled(CUBES_TAB_NAME, BRING_MODULE_NAME, enabled)
	end

	if source ~= "toggle" then
		Window:SetControlValue(CUBES_TAB_NAME, BRING_MODULE_NAME, BRING_MAIN_SECTION, BRING_TOGGLE_NAME, enabled)
	end

	State.Syncing.Bring = false
end

local function setRuneState(enabled, source)
	State.RuneEnabled = enabled
	State.RuneStatus = enabled and "Opening" or "Idle"

	if not Window or State.Syncing.Rune then
		return
	end

	State.Syncing.Rune = true

	if source ~= "module" then
		Window:SetModuleEnabled(RUNES_TAB_NAME, RUNE_MODULE_NAME, enabled)
	end

	if source ~= "toggle" then
		Window:SetControlValue(RUNES_TAB_NAME, RUNE_MODULE_NAME, RUNE_MAIN_SECTION, RUNE_TOGGLE_NAME, enabled)
	end

	State.Syncing.Rune = false
end

local function setBlueprintRuneState(enabled, source)
	State.BlueprintRuneEnabled = enabled
	State.BlueprintRunesStatus = enabled and "Buying" or "Idle"

	if not Window or State.Syncing.BlueprintRune then
		return
	end

	State.Syncing.BlueprintRune = true

	if source ~= "module" then
		Window:SetModuleEnabled(RUNES_TAB_NAME, BLUEPRINT_RUNE_MODULE_NAME, enabled)
	end

	if source ~= "toggle" then
		Window:SetControlValue(RUNES_TAB_NAME, BLUEPRINT_RUNE_MODULE_NAME, BLUEPRINT_RUNE_MAIN_SECTION, BLUEPRINT_RUNE_TOGGLE_NAME, enabled)
	end

	State.Syncing.BlueprintRune = false
end

local function setConvertCubesState(enabled, source)
	State.ConvertCubesEnabled = enabled
	State.BlueprintCubesStatus = enabled and "Converting" or "Idle"

	if not Window or State.Syncing.Conversion then
		return
	end

	State.Syncing.Conversion = true

	if source ~= "module" then
		Window:SetModuleEnabled(CONVERSION_TAB_NAME, CONVERSION_MODULE_NAME, enabled)
	end

	if source ~= "toggle" then
		Window:SetControlValue(CONVERSION_TAB_NAME, CONVERSION_MODULE_NAME, CONVERSION_MAIN_SECTION, CONVERSION_CUBES_TOGGLE_NAME, enabled)
	end

	State.Syncing.Conversion = false
end

local function findControl(tabName, moduleName, sectionName, controlName)
	local module = Window and Window:GetModule(tabName, moduleName)
	local section = module and module.SectionLookup[sectionName]

	if not section then
		return nil
	end

	for _, control in ipairs(section.Controls) do
		if control.Name == controlName then
			return control
		end
	end

	return nil
end

local function refreshControl(control, content)
	if not control or control.Content == content then
		return
	end

	control.Content = content

	if control._refresh then
		control._refresh(true)
	end
end

State.Stop = function()
	State.Alive = false
	State.FarmEnabled = false
	State.BringEnabled = false
	State.RuneEnabled = false
	State.BlueprintRuneEnabled = false
	State.ConvertCubesEnabled = false

	disconnectConnections(State.CharacterConnections)
	disconnectConnections(State.Connections)

	if State.Window and State.Window.Destroy then
		pcall(function()
			State.Window:Destroy()
		end)
	end
end

Window = Library:Create({
	Title = "tg: @sigmatik323",
	ConfigName = "by sigmatik323",
	SearchPlaceholder = "Search modules...",
	Accent = "#22d3ee",
	AccentSoft = "#67e8f9",
	WindowWidth = 960,
	WindowHeight = 540,
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = CUBES_TAB_NAME,
			Icon = "misc",
			Modules = {
				{
					Name = FARM_MODULE_NAME,
					Enabled = false,
					Callback = function(enabled)
						setFarmState(enabled, "module")
					end,
					Sections = {
						{
							Name = FARM_MAIN_SECTION,
							Controls = {
								{
									Type = "Toggle",
									Name = FARM_TOGGLE_NAME,
									CurrentValue = false,
									Callback = function(enabled)
										setFarmState(enabled, "toggle")
									end,
								},
								{
									Type = "Paragraph",
									Name = FARM_STATUS_NAME,
									Content = "State: Idle",
								},
								{
									Type = "Label",
									Name = FARM_COUNT_NAME,
									Content = "Collected: 0",
								},
							},
						},
						{
							Name = FARM_SETTINGS_SECTION,
							Controls = {
								{
									Type = "Slider",
									Name = FARM_RADIUS_NAME,
									Min = 25,
									Max = 5000,
									Increment = 25,
									CurrentValue = 1000,
									Callback = function(value)
										State.CollectRadius = value
									end,
								},
								{
									Type = "Slider",
									Name = FARM_DELAY_NAME,
									Min = 0.05,
									Max = 2,
									Increment = 0.05,
									CurrentValue = 0.1,
									Callback = function(value)
										State.CollectDelay = value
									end,
								},
							},
						},
					},
				},
				{
					Name = BRING_MODULE_NAME,
					Enabled = false,
					Callback = function(enabled)
						setBringState(enabled, "module")
					end,
					Sections = {
						{
							Name = BRING_MAIN_SECTION,
							Controls = {
								{
									Type = "Toggle",
									Name = BRING_TOGGLE_NAME,
									CurrentValue = false,
									Callback = function(enabled)
										setBringState(enabled, "toggle")
									end,
								},
								{
									Type = "Paragraph",
									Name = BRING_STATUS_NAME,
									Content = "State: Idle",
								},
								{
									Type = "Label",
									Name = BRING_COUNT_NAME,
									Content = "Moved: 0",
								},
							},
						},
						{
							Name = BRING_SETTINGS_SECTION,
							Controls = {
								{
									Type = "Slider",
									Name = BRING_DELAY_NAME,
									Min = 0.02,
									Max = 1,
									Increment = 0.01,
									CurrentValue = 0.05,
									Callback = function(value)
										State.BringDelay = value
									end,
								},
							},
						},
					},
				},
			},
		},
		{
			Name = RUNES_TAB_NAME,
			Icon = "misc",
			Modules = {
				{
					Name = RUNE_MODULE_NAME,
					Enabled = false,
					Callback = function(enabled)
						setRuneState(enabled, "module")
					end,
					Sections = {
						{
							Name = RUNE_MAIN_SECTION,
							Controls = {
								{
									Type = "Toggle",
									Name = RUNE_TOGGLE_NAME,
									CurrentValue = false,
									Callback = function(enabled)
										setRuneState(enabled, "toggle")
									end,
								},
								{
									Type = "Paragraph",
									Name = RUNE_STATUS_NAME,
									Content = "State: Idle",
								},
								{
									Type = "Label",
									Name = RUNE_COUNT_NAME,
									Content = "Opened: 0",
								},
							},
						},
						{
							Name = RUNE_SETTINGS_SECTION,
							Controls = {
								{
									Type = "Slider",
									Name = RUNE_DELAY_NAME,
									Min = 0.0001,
									Max = 1,
									Increment = 0.0001,
									CurrentValue = 1,
									Callback = function(value)
										State.RuneDelay = value
									end,
								},
							},
						},
					},
				},
				{
					Name = BLUEPRINT_RUNE_MODULE_NAME,
					Enabled = false,
					Callback = function(enabled)
						setBlueprintRuneState(enabled, "module")
					end,
					Sections = {
						{
							Name = BLUEPRINT_RUNE_MAIN_SECTION,
							Controls = {
								{
									Type = "Toggle",
									Name = BLUEPRINT_RUNE_TOGGLE_NAME,
									CurrentValue = false,
									Callback = function(enabled)
										setBlueprintRuneState(enabled, "toggle")
									end,
								},
								{
									Type = "Paragraph",
									Name = BLUEPRINT_RUNE_STATUS_NAME,
									Content = "State: Idle",
								},
								{
									Type = "Label",
									Name = BLUEPRINT_RUNE_COUNT_NAME,
									Content = "Bought: 0",
								},
							},
						},
						{
							Name = BLUEPRINT_RUNE_SETTINGS_SECTION,
							Controls = {
								{
									Type = "Slider",
									Name = BLUEPRINT_RUNE_DELAY_NAME,
									Min = 0.0001,
									Max = 1,
									Increment = 0.0001,
									CurrentValue = 1,
									Callback = function(value)
										State.BlueprintRuneDelay = value
									end,
								},
							},
						},
					},
				},
			},
		},
		{
			Name = CONVERSION_TAB_NAME,
			Icon = "misc",
			Modules = {
				{
					Name = CONVERSION_MODULE_NAME,
					Enabled = false,
					Callback = function(enabled)
						setConvertCubesState(enabled, "module")
					end,
					Sections = {
						{
							Name = CONVERSION_MAIN_SECTION,
							Controls = {
								{
									Type = "Toggle",
									Name = CONVERSION_CUBES_TOGGLE_NAME,
									CurrentValue = false,
									Callback = function(enabled)
										setConvertCubesState(enabled, "toggle")
									end,
								},
								{
									Type = "Paragraph",
									Name = CONVERSION_CUBES_STATUS_NAME,
									Content = "State: Idle",
								},
								{
									Type = "Label",
									Name = CONVERSION_CUBES_COUNT_NAME,
									Content = "Bought: 0",
								},
							},
						},
						{
							Name = CONVERSION_SETTINGS_SECTION,
							Controls = {
								{
									Type = "Slider",
									Name = CONVERSION_CUBES_DELAY_NAME,
									Min = 0.0001,
									Max = 1,
									Increment = 0.0001,
									CurrentValue = 1,
									Callback = function(value)
										State.ConvertCubesDelay = value
									end,
								},
							},
						},
					},
				},
			},
		},
	},
})

State.Window = Window

FarmStatusControl = findControl(CUBES_TAB_NAME, FARM_MODULE_NAME, FARM_MAIN_SECTION, FARM_STATUS_NAME)
FarmCountControl = findControl(CUBES_TAB_NAME, FARM_MODULE_NAME, FARM_MAIN_SECTION, FARM_COUNT_NAME)
BringStatusControl = findControl(CUBES_TAB_NAME, BRING_MODULE_NAME, BRING_MAIN_SECTION, BRING_STATUS_NAME)
BringCountControl = findControl(CUBES_TAB_NAME, BRING_MODULE_NAME, BRING_MAIN_SECTION, BRING_COUNT_NAME)
RuneStatusControl = findControl(RUNES_TAB_NAME, RUNE_MODULE_NAME, RUNE_MAIN_SECTION, RUNE_STATUS_NAME)
RuneCountControl = findControl(RUNES_TAB_NAME, RUNE_MODULE_NAME, RUNE_MAIN_SECTION, RUNE_COUNT_NAME)
BlueprintRuneStatusControl = findControl(RUNES_TAB_NAME, BLUEPRINT_RUNE_MODULE_NAME, BLUEPRINT_RUNE_MAIN_SECTION, BLUEPRINT_RUNE_STATUS_NAME)
BlueprintRuneCountControl = findControl(RUNES_TAB_NAME, BLUEPRINT_RUNE_MODULE_NAME, BLUEPRINT_RUNE_MAIN_SECTION, BLUEPRINT_RUNE_COUNT_NAME)
BlueprintCubesStatusControl = findControl(CONVERSION_TAB_NAME, CONVERSION_MODULE_NAME, CONVERSION_MAIN_SECTION, CONVERSION_CUBES_STATUS_NAME)
BlueprintCubesCountControl = findControl(CONVERSION_TAB_NAME, CONVERSION_MODULE_NAME, CONVERSION_MAIN_SECTION, CONVERSION_CUBES_COUNT_NAME)

task.spawn(function()
	while State.Alive do
		if State.FarmEnabled then
			collectNearbyCubes()
		end

		task.wait(State.CollectDelay)
	end
end)

task.spawn(function()
	while State.Alive do
		if State.BringEnabled then
			bringCubesToPlayer()
		end

		task.wait(State.BringDelay)
	end
end)

task.spawn(function()
	while State.Alive do
		if State.RuneEnabled then
			openBasicRune()
		end

		task.wait(State.RuneDelay)
	end
end)

task.spawn(function()
	while State.Alive do
		if State.BlueprintRuneEnabled then
			buyBlueprintRunes()
		end

		task.wait(State.BlueprintRuneDelay)
	end
end)

task.spawn(function()
	while State.Alive do
		if State.ConvertCubesEnabled then
			buyBlueprintCubes()
		end

		task.wait(State.ConvertCubesDelay)
	end
end)

task.spawn(function()
	while State.Alive do
		refreshControl(
			FarmStatusControl,
			"State: " .. State.FarmStatus .. " | Radius: " .. tostring(State.CollectRadius) .. " | Delay: " .. string.format("%.2f", State.CollectDelay)
		)
		refreshControl(FarmCountControl, "Collected: " .. tostring(State.CollectedCubes))
		refreshControl(
			BringStatusControl,
			"State: " .. State.BringStatus .. " | Delay: " .. string.format("%.2f", State.BringDelay)
		)
		refreshControl(BringCountControl, "Moved: " .. tostring(State.MovedCubes))
		refreshControl(
			RuneStatusControl,
			"State: " .. State.RuneStatus .. " | Delay: " .. string.format("%.4f", State.RuneDelay)
		)
		refreshControl(RuneCountControl, "Opened: " .. tostring(State.OpenedBasicRunes))
		refreshControl(
			BlueprintRuneStatusControl,
			"State: " .. State.BlueprintRunesStatus .. " | Delay: " .. string.format("%.4f", State.BlueprintRuneDelay)
		)
		refreshControl(BlueprintRuneCountControl, "Bought: " .. tostring(State.BoughtBlueprintRunes))
		refreshControl(
			BlueprintCubesStatusControl,
			"State: " .. State.BlueprintCubesStatus .. " | Delay: " .. string.format("%.4f", State.ConvertCubesDelay)
		)
		refreshControl(BlueprintCubesCountControl, "Bought: " .. tostring(State.BoughtBlueprintCubes))

		task.wait(0.15)
	end
end)
