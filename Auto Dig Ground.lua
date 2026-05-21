local LIBRARY_URL = "https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"
local LOCAL_LIBRARY_PATHS = {
	"sigmatik_ui_library.lua",
	"gui_lua/sigmatik_ui_library.lua",
	"../gui_lua/sigmatik_ui_library.lua",
	"..\\gui_lua\\sigmatik_ui_library.lua",
	"D:/Нужное/Скрипты роблокс/Делаем скрипты тут/gui_lua/sigmatik_ui_library.lua",
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local SharedEnvironment = (getgenv and getgenv()) or _G
local PreviousContext = SharedEnvironment.SigmatikAutoDigGroundContext

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

local TAB_NAME = icon(0x26CF) .. " Auto Dig"
local MODULE_NAME = icon(0x1FAA8) .. " Ground Digger"
local MAIN_SECTION_NAME = icon(0x26CF) .. " Main"
local GRID_SECTION_NAME = icon(0x1F4D0) .. " Grid"
local TOOL_SECTION_NAME = icon(0x1F6E0) .. " Tool"
local STATUS_SECTION_NAME = icon(0x1F4CC) .. " Status"

local AUTO_DIG_NAME = "Auto Dig"
local DIG_ONCE_NAME = "Dig Once"
local AUTO_EQUIP_NAME = "Auto Equip Best Tool"
local STAY_IN_HOLE_NAME = "Only Inside DigPart"
local FOLLOW_PLAYER_NAME = "Follow Player"

local RADIUS_NAME = "Scan Radius"
local DEPTH_NAME = "Scan Depth"
local STEP_NAME = "Grid Step (4 = block)"
local Y_OFFSET_NAME = "Y Offset"
local FIRE_DELAY_NAME = "Fire Delay"
local LOOP_DELAY_NAME = "Loop Delay"

local TOOL_DROPDOWN_NAME = "Selected Tool"
local REFRESH_TOOLS_NAME = "Refresh Tools"

local STATUS_LABEL_NAME = "Status: Idle"
local LAST_POS_LABEL_NAME = "Last Position: -"
local FIRE_COUNT_LABEL_NAME = "Fires Sent: 0"
local DIG_HITS_LABEL_NAME = "Server Hits: 0"
local TOOL_LABEL_NAME = "Active Tool: -"
local ANTI_AFK_LABEL_NAME = "Anti AFK is always active"

local AUTO_TOOL_LABEL = "Auto"

local Context = {
	Alive = true,
	AutoDig = false,
	AutoEquip = true,
	StayInDigPart = true,
	FollowPlayer = true,
	Radius = 24,
	Depth = 4,
	Step = 4,
	YOffset = 0,
	FireDelay = 0.05,
	LoopDelay = 0.1,
	SelectedTool = AUTO_TOOL_LABEL,
	ActiveToolName = nil,
	FireCount = 0,
	DigHits = 0,
	LoopId = 0,
	Window = nil,
	Connections = {},
	ToolList = { AUTO_TOOL_LABEL },
	DigConn = nil,
	RequestDig = nil,
	DigResult = nil,
	ToolConfig = nil,
}

local function safeRequire(path)
	local ok, mod = pcall(require, path)
	if ok then return mod end
	return nil
end

local function loadGameModules()
	Context.ToolConfig = safeRequire(ReplicatedStorage:WaitForChild("shared", 5)
		and ReplicatedStorage.shared:WaitForChild("configs", 5)
		and ReplicatedStorage.shared.configs:WaitForChild("ToolConfig", 5))
	local invNet = ReplicatedStorage:WaitForChild("shared", 5)
		and ReplicatedStorage.shared:WaitForChild("network", 5)
		and ReplicatedStorage.shared.network:WaitForChild("InventoryNetwork", 5)
	local mod = invNet and safeRequire(invNet)
	if mod then
		Context.RequestDig = mod.RequestDig
		Context.DigResult = mod.DigResult
	end
end

loadGameModules()

local function isDigToolName(name)
	if not name then return false end
	if Context.ToolConfig and Context.ToolConfig.TOOLS and Context.ToolConfig.TOOLS[name] then
		return true
	end
	return false
end

local function listAvailableDigTools()
	local result = {}
	local seen = {}
	local function addFrom(container)
		if not container then return end
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("Tool") and isDigToolName(c.Name) and not seen[c.Name] then
				seen[c.Name] = true
				table.insert(result, c.Name)
			end
		end
	end
	addFrom(LocalPlayer and LocalPlayer.Character)
	addFrom(LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack"))
	if Context.ToolConfig and Context.ToolConfig.TOOLS then
		local fallback = {}
		for name in pairs(Context.ToolConfig.TOOLS) do
			if not seen[name] then
				table.insert(fallback, name)
			end
		end
		table.sort(fallback)
		for _, n in ipairs(fallback) do
			table.insert(result, n)
		end
	end
	return result
end

local function findTool(name)
	local char = LocalPlayer and LocalPlayer.Character
	local back = LocalPlayer and LocalPlayer:FindFirstChildOfClass("Backpack")
	if char then
		local t = char:FindFirstChild(name)
		if t and t:IsA("Tool") then return t, "char" end
	end
	if back then
		local t = back:FindFirstChild(name)
		if t and t:IsA("Tool") then return t, "back" end
	end
	return nil, nil
end

local function getEquippedTool()
	local char = LocalPlayer and LocalPlayer.Character
	if not char then return nil end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then return c end
	end
	return nil
end

local function pickBestDigToolName()
	local list = listAvailableDigTools()
	local best
	local bestLevel = -math.huge
	for _, name in ipairs(list) do
		local cfg = Context.ToolConfig and Context.ToolConfig.TOOLS and Context.ToolConfig.TOOLS[name]
		if cfg then
			local level = cfg.Level or 0
			local exists = findTool(name)
			if exists and level > bestLevel then
				best = name
				bestLevel = level
			end
		end
	end
	if not best then
		for _, name in ipairs(list) do
			if findTool(name) then best = name break end
		end
	end
	return best
end

local function ensureToolEquipped(name)
	if not name then return false end
	local equipped = getEquippedTool()
	if equipped and equipped.Name == name then return true end
	local tool, location = findTool(name)
	if not tool then return false end
	local char = LocalPlayer and LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	if location == "back" then
		pcall(function() hum:UnequipTools() end)
		task.wait()
		pcall(function() hum:EquipTool(tool) end)
		task.wait()
	end
	local now = getEquippedTool()
	return now and now.Name == name
end

local function resolveActiveToolName()
	local sel = Context.SelectedTool
	if sel == AUTO_TOOL_LABEL or not sel then
		return pickBestDigToolName()
	end
	return sel
end

local function addConnection(connection)
	if connection then
		table.insert(Context.Connections, connection)
	end
	return connection
end

local function disconnectAll()
	for _, connection in ipairs(Context.Connections) do
		pcall(function() connection:Disconnect() end)
	end
	Context.Connections = {}
end

local function getRoot()
	local character = LocalPlayer and LocalPlayer.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart")
end

local function getDigPart()
	local hole = workspace:FindFirstChild("Hole")
	if not hole then return nil end
	return hole:FindFirstChild("DigPart")
end

local function getUtilPart()
	local hole = workspace:FindFirstChild("Hole")
	if not hole then return nil end
	return hole:FindFirstChild("UtilPart")
end

local function isInsidePart(pos, part, tolerance)
	if not part then return false end
	local local_ = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	local t = tolerance or 1
	return math.abs(local_.X) <= h.X + t
		and math.abs(local_.Y) <= h.Y + t
		and math.abs(local_.Z) <= h.Z + t
end

local function snap4(v)
	return math.floor(v / 4) * 4 + 2
end

local function setStatusLabel(text)
	if not Context.Window then return end
	pcall(function()
		Context.Window:SetControlValue(TAB_NAME, MODULE_NAME, STATUS_SECTION_NAME, STATUS_LABEL_NAME, text)
	end)
end

local function setLastPosLabel(pos)
	if not Context.Window then return end
	local text
	if pos then
		text = string.format("Last Position: %.0f, %.0f, %.0f", pos.X, pos.Y, pos.Z)
	else
		text = "Last Position: -"
	end
	pcall(function()
		Context.Window:SetControlValue(TAB_NAME, MODULE_NAME, STATUS_SECTION_NAME, LAST_POS_LABEL_NAME, text)
	end)
end

local function bumpFireCount()
	Context.FireCount = Context.FireCount + 1
	if not Context.Window then return end
	pcall(function()
		Context.Window:SetControlValue(TAB_NAME, MODULE_NAME, STATUS_SECTION_NAME, FIRE_COUNT_LABEL_NAME, "Fires Sent: " .. tostring(Context.FireCount))
	end)
end

local function bumpDigHits()
	Context.DigHits = Context.DigHits + 1
	if not Context.Window then return end
	pcall(function()
		Context.Window:SetControlValue(TAB_NAME, MODULE_NAME, STATUS_SECTION_NAME, DIG_HITS_LABEL_NAME, "Server Hits: " .. tostring(Context.DigHits))
	end)
end

local function setToolLabel(name)
	if not Context.Window then return end
	pcall(function()
		Context.Window:SetControlValue(TAB_NAME, MODULE_NAME, STATUS_SECTION_NAME, TOOL_LABEL_NAME, "Active Tool: " .. tostring(name or "-"))
	end)
end

local function fireAt(position, toolName)
	if not Context.RequestDig then
		setStatusLabel("Status: RequestDig missing")
		return false
	end
	local payload = { position = position, toolName = toolName }
	local ok, err = pcall(function()
		Context.RequestDig:Fire(payload)
	end)
	if not ok then
		warn("[Auto Dig] RequestDig:Fire failed: " .. tostring(err))
		return false
	end
	bumpFireCount()
	setLastPosLabel(position)
	return true
end

local function buildOffsetList()
	local offsets = {}
	local step = math.max(1, Context.Step)
	local radius = math.max(0, Context.Radius)
	local depth = math.max(0, Context.Depth)
	local yOffset = Context.YOffset

	local dy = 0
	while dy <= depth do
		local dx = -radius
		while dx <= radius do
			local dz = -radius
			while dz <= radius do
				table.insert(offsets, { dx, yOffset - dy, dz })
				dz = dz + step
			end
			dx = dx + step
		end
		dy = dy + step
	end

	return offsets
end

local function pointFromOffset(centerVec3, offset)
	local raw = Vector3.new(centerVec3.X + offset[1], centerVec3.Y + offset[2], centerVec3.Z + offset[3])
	return Vector3.new(snap4(raw.X), snap4(raw.Y), snap4(raw.Z))
end

local function buildGrid(centerVec3)
	local offsets = buildOffsetList()
	local list = {}
	for _, offset in ipairs(offsets) do
		table.insert(list, pointFromOffset(centerVec3, offset))
	end
	return list
end

local function shouldFirePosition(pos)
	if not Context.StayInDigPart then return true end
	local digPart = getDigPart()
	local utilPart = getUtilPart()
	if not digPart and not utilPart then return true end
	if isInsidePart(pos, digPart, 1) then return true end
	if utilPart and isInsidePart(pos, utilPart, 1) then return true end
	return false
end

local function prepareTool()
	local name = resolveActiveToolName()
	if not name then
		Context.ActiveToolName = nil
		setToolLabel(nil)
		return nil
	end
	if Context.AutoEquip then
		ensureToolEquipped(name)
	end
	Context.ActiveToolName = name
	setToolLabel(name)
	return name
end

local function runOnePass(loopId)
	local toolName = prepareTool()
	if not toolName then
		setStatusLabel("Status: No dig tool found")
		return false
	end

	local root = getRoot()
	if not root then
		setStatusLabel("Status: No HumanoidRootPart")
		return false
	end

	local digPart = getDigPart()
	local center = (digPart and Context.StayInDigPart) and digPart.Position or root.Position
	local grid = buildGrid(center)
	local skipped = 0
	local fired = 0
	setStatusLabel("Status: Digging " .. tostring(#grid) .. " points")

	for _, position in ipairs(grid) do
		if not Context.Alive then return false end
		if loopId and loopId ~= Context.LoopId then return false end

		if shouldFirePosition(position) then
			fireAt(position, toolName)
			fired = fired + 1
		else
			skipped = skipped + 1
		end

		local d = math.max(0, Context.FireDelay)
		if d > 0 then
			task.wait(d)
		else
			task.wait()
		end
	end

	setStatusLabel(string.format("Status: Pass done (fired=%d, skipped=%d)", fired, skipped))
	return true
end

local function runAutoDigLoop(loopId)
	while Context.Alive and Context.AutoDig and loopId == Context.LoopId do
		local toolName = prepareTool()
		if not toolName then
			setStatusLabel("Status: Waiting for dig tool")
			task.wait(0.5)
		else
			local root = getRoot()
			if not root then
				setStatusLabel("Status: Waiting for character")
				task.wait(0.5)
			else
				local digPart = getDigPart()
				local snapshotCenter
				if digPart and Context.StayInDigPart then
					snapshotCenter = digPart.Position
				else
					snapshotCenter = root.Position
				end

				local offsets = buildOffsetList()
				setStatusLabel("Status: Auto Dig (" .. tostring(#offsets) .. " pts)")

				for _, offset in ipairs(offsets) do
					if not Context.Alive or not Context.AutoDig or loopId ~= Context.LoopId then
						break
					end

					local center
					if Context.FollowPlayer then
						local rNow = getRoot()
						if rNow and not (digPart and Context.StayInDigPart) then
							center = rNow.Position
						else
							center = snapshotCenter
						end
					else
						center = snapshotCenter
					end

					local position = pointFromOffset(center, offset)
					if shouldFirePosition(position) then
						fireAt(position, toolName)
					end

					local d = math.max(0, Context.FireDelay)
					if d > 0 then
						task.wait(d)
					else
						task.wait()
					end
				end

				local loopDelay = math.max(0, Context.LoopDelay)
				if loopDelay > 0 then
					task.wait(loopDelay)
				else
					task.wait()
				end
			end
		end
	end

	if Context.LoopId == loopId then
		setStatusLabel("Status: Idle")
	end
end

local function setAutoDig(value)
	Context.AutoDig = not not value
	if Context.AutoDig then
		Context.LoopId = Context.LoopId + 1
		local id = Context.LoopId
		task.spawn(function() runAutoDigLoop(id) end)
	else
		Context.LoopId = Context.LoopId + 1
		setStatusLabel("Status: Idle")
	end
end

local function triggerDigOnce()
	Context.LoopId = Context.LoopId + 1
	local id = Context.LoopId
	task.spawn(function() runOnePass(id) end)
end

local function refreshToolDropdown()
	local list = { AUTO_TOOL_LABEL }
	for _, n in ipairs(listAvailableDigTools()) do
		table.insert(list, n)
	end
	Context.ToolList = list
	if not Context.Window then return end
	pcall(function()
		Context.Window:SetControlOptions(TAB_NAME, MODULE_NAME, TOOL_SECTION_NAME, TOOL_DROPDOWN_NAME, list)
	end)
	if not table.find(list, Context.SelectedTool) then
		Context.SelectedTool = AUTO_TOOL_LABEL
		pcall(function()
			Context.Window:SetControlValue(TAB_NAME, MODULE_NAME, TOOL_SECTION_NAME, TOOL_DROPDOWN_NAME, AUTO_TOOL_LABEL)
		end)
	end
end

local function buildWindow()
	return Library:Create({
		Title = "tg: @sigmatik323",
		ConfigName = "Auto Dig Ground",
		SearchPlaceholder = "Search modules...",
		Accent = "#22c55e",
		AccentSoft = "#4ade80",
		WindowFill = "#0b1020d9",
		DimBackground = "#02061766",
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
										Name = AUTO_DIG_NAME,
										CurrentValue = false,
										Callback = function(value)
											setAutoDig(value)
										end,
									},
									{
										Type = "toggle",
										Name = DIG_ONCE_NAME,
										CurrentValue = false,
										Callback = function(value)
											if value then
												triggerDigOnce()
												task.delay(0.05, function()
													pcall(function()
														Context.Window:SetControlValue(TAB_NAME, MODULE_NAME, MAIN_SECTION_NAME, DIG_ONCE_NAME, false)
													end)
												end)
											end
										end,
									},
									{
										Type = "toggle",
										Name = AUTO_EQUIP_NAME,
										CurrentValue = true,
										Callback = function(value)
											Context.AutoEquip = not not value
										end,
									},
									{
										Type = "toggle",
										Name = STAY_IN_HOLE_NAME,
										CurrentValue = true,
										Callback = function(value)
											Context.StayInDigPart = not not value
										end,
									},
									{
										Type = "toggle",
										Name = FOLLOW_PLAYER_NAME,
										CurrentValue = true,
										Callback = function(value)
											Context.FollowPlayer = not not value
										end,
									},
								},
							},
							{
								Name = GRID_SECTION_NAME,
								Controls = {
									{
										Type = "slider",
										Name = RADIUS_NAME,
										Min = 4,
										Max = 120,
										Increment = 4,
										CurrentValue = 24,
										Callback = function(value)
											Context.Radius = value
										end,
									},
									{
										Type = "slider",
										Name = DEPTH_NAME,
										Min = 0,
										Max = 80,
										Increment = 4,
										CurrentValue = 4,
										Callback = function(value)
											Context.Depth = value
										end,
									},
									{
										Type = "slider",
										Name = STEP_NAME,
										Min = 4,
										Max = 24,
										Increment = 4,
										CurrentValue = 4,
										Callback = function(value)
											Context.Step = value
										end,
									},
									{
										Type = "slider",
										Name = Y_OFFSET_NAME,
										Min = -20,
										Max = 20,
										Increment = 4,
										CurrentValue = 0,
										Callback = function(value)
											Context.YOffset = value
										end,
									},
									{
										Type = "slider",
										Name = FIRE_DELAY_NAME,
										Min = 0,
										Max = 1,
										Increment = 0.01,
										CurrentValue = 0.05,
										Callback = function(value)
											Context.FireDelay = value
										end,
									},
									{
										Type = "slider",
										Name = LOOP_DELAY_NAME,
										Min = 0,
										Max = 5,
										Increment = 0.05,
										CurrentValue = 0.1,
										Callback = function(value)
											Context.LoopDelay = value
										end,
									},
								},
							},
							{
								Name = TOOL_SECTION_NAME,
								Controls = {
									{
										Type = "dropdown",
										Name = TOOL_DROPDOWN_NAME,
										Options = Context.ToolList,
										CurrentOption = AUTO_TOOL_LABEL,
										Callback = function(value)
											if type(value) == "table" then
												value = value[1]
											end
											Context.SelectedTool = value or AUTO_TOOL_LABEL
										end,
									},
									{
										Type = "button",
										Name = REFRESH_TOOLS_NAME,
										Callback = function()
											refreshToolDropdown()
										end,
									},
								},
							},
							{
								Name = STATUS_SECTION_NAME,
								Controls = {
									{
										Type = "label",
										Name = STATUS_LABEL_NAME,
										Content = STATUS_LABEL_NAME,
									},
									{
										Type = "label",
										Name = LAST_POS_LABEL_NAME,
										Content = LAST_POS_LABEL_NAME,
									},
									{
										Type = "label",
										Name = FIRE_COUNT_LABEL_NAME,
										Content = FIRE_COUNT_LABEL_NAME,
									},
									{
										Type = "label",
										Name = DIG_HITS_LABEL_NAME,
										Content = DIG_HITS_LABEL_NAME,
									},
									{
										Type = "label",
										Name = TOOL_LABEL_NAME,
										Content = TOOL_LABEL_NAME,
									},
									{
										Type = "label",
										Name = ANTI_AFK_LABEL_NAME,
										Content = ANTI_AFK_LABEL_NAME,
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
	Context.AutoDig = false
	Context.LoopId = Context.LoopId + 1
	disconnectAll()
	if Context.DigConn then
		pcall(function() Context.DigConn:Disconnect() end)
		Context.DigConn = nil
	end
	if Context.Window then
		pcall(function() Context.Window:Destroy() end)
		Context.Window = nil
	end
	SharedEnvironment.SigmatikAutoDigGroundContext = nil
end

Context.Cleanup = cleanup
Context.SetAutoDig = setAutoDig
Context.TriggerDigOnce = triggerDigOnce
Context.RefreshToolDropdown = refreshToolDropdown

if LocalPlayer then
	addConnection(LocalPlayer.Idled:Connect(function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)
	end))
	addConnection(LocalPlayer.CharacterAdded:Connect(function()
		task.wait(1.5)
		refreshToolDropdown()
	end))
end

if Context.DigResult and Context.DigResult.Connect then
	local ok, conn = pcall(function()
		return Context.DigResult:Connect(function() bumpDigHits() end)
	end)
	if ok then
		Context.DigConn = conn
	end
end

Context.Window = buildWindow()
SharedEnvironment.SigmatikAutoDigGroundContext = Context

setStatusLabel("Status: Idle")
setLastPosLabel(nil)
refreshToolDropdown()
prepareTool()

return Context
