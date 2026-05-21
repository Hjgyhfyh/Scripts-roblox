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
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local SharedEnvironment = getgenv and getgenv() or _G
local PreviousContext = SharedEnvironment.SigmatikRatWashingContext

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

local TAB_NAME = icon(0x1F400) .. " Rat Washing Tycoon"

local AUTO_COLLECT_NAME = "Auto Collect Rats"
local COLLECT_ONCE_NAME = "Collect Once"
local REFRESH_PLOT_NAME = "Refresh Plot"
local COLLECT_DELAY_NAME = "Collect Delay"
local PLOT_LABEL_TEXT = "Plot: searching..."
local RATS_FOUND_TEXT = "Rats Found: 0"
local RATS_COLLECTED_TEXT = "Rats Collected: 0"

local AUTO_SELL_NAME = "Auto Sell Rats"
local SELL_DELAY_NAME = "Sell Delay"
local ANTI_AFK_NAME = "Anti AFK is always active"

local Context = {
	Alive = true,
	CollectEnabled = false,
	SellEnabled = false,
	CollectDelay = 0.5,
	SellDelay = 1.0,
	PlotName = "Searching...",
	RatsFound = 0,
	RatsCollected = 0,
	Connections = {},
	CollectLoopId = 0,
	SellLoopId = 0,
	Window = nil,
	Controller = nil,
	Plot = nil,
	CachedCollectRemote = nil,
	CachedSellRemote = nil,
	AutoCollectToggle = nil,
	AutoSellToggle = nil,
	PlotLabel = nil,
	RatsFoundLabel = nil,
	RatsCollectedLabel = nil,
}

SharedEnvironment.SigmatikRatWashingContext = Context

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

local function getCollectRatRemote()
	if Context.CachedCollectRemote and Context.CachedCollectRemote.Parent then
		return Context.CachedCollectRemote
	end

	local ok, remote = pcall(function()
		return ReplicatedStorage
			:WaitForChild("Knit", 10)
			:WaitForChild("Services", 10)
			:WaitForChild("TycoonService", 10)
			:WaitForChild("RE", 10)
			:WaitForChild("CollectRat", 10)
	end)

	if ok and remote then
		Context.CachedCollectRemote = remote
		return remote
	end

	return nil
end

local function getSellRatsRemote()
	if Context.CachedSellRemote and Context.CachedSellRemote.Parent then
		return Context.CachedSellRemote
	end

	local ok, remote = pcall(function()
		return ReplicatedStorage
			:WaitForChild("Knit", 10)
			:WaitForChild("Services", 10)
			:WaitForChild("TycoonService", 10)
			:WaitForChild("RE", 10)
			:WaitForChild("SellRats", 10)
	end)

	if ok and remote then
		Context.CachedSellRemote = remote
		return remote
	end

	return nil
end

local function valueMatchesPlayer(val)
	if val == nil then
		return false
	end
	if val == LocalPlayer then
		return true
	end
	if val == LocalPlayer.Name then
		return true
	end
	if val == LocalPlayer.UserId then
		return true
	end
	if type(val) == "string" and val == tostring(LocalPlayer.UserId) then
		return true
	end
	return false
end

local function plotOwnershipMatches(plot)
	if plot.Name == LocalPlayer.Name or plot.Name == tostring(LocalPlayer.UserId) then
		return true
	end

	local okAttrs, attrs = pcall(function()
		return plot:GetAttributes()
	end)
	if okAttrs and attrs then
		for _, val in pairs(attrs) do
			if valueMatchesPlayer(val) then
				return true
			end
		end
	end

	local count = 0
	for _, desc in ipairs(plot:GetDescendants()) do
		count = count + 1
		if count > 3000 then
			break
		end

		if desc:IsA("ObjectValue") and desc.Value == LocalPlayer then
			return true
		end

		if desc:IsA("StringValue") then
			if desc.Value == LocalPlayer.Name or desc.Value == tostring(LocalPlayer.UserId) then
				return true
			end
		end

		if desc:IsA("IntValue") or desc:IsA("NumberValue") then
			if desc.Value == LocalPlayer.UserId then
				return true
			end
		end

		local okDescAttrs, descAttrs = pcall(function()
			return desc:GetAttributes()
		end)
		if okDescAttrs and descAttrs then
			for _, val in pairs(descAttrs) do
				if valueMatchesPlayer(val) then
					return true
				end
			end
		end
	end

	return false
end

local function findPlotByCharacter()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart")
	if not rootPart then
		return nil
	end

	local Tycoons = Workspace:FindFirstChild("Tycoons")
	if not Tycoons then
		return nil
	end

	local closestPlot = nil
	local closestDist = math.huge
	for _, plot in ipairs(Tycoons:GetChildren()) do
		local plotPart = plot:FindFirstChildWhichIsA("BasePart", true)
		if plotPart then
			local dist = (plotPart.Position - rootPart.Position).Magnitude
			if dist < closestDist then
				closestDist = dist
				closestPlot = plot
			end
		end
	end

	return closestPlot
end

local function findPlayerPlot()
	local Tycoons = Workspace:FindFirstChild("Tycoons")
	if not Tycoons then
		return nil
	end

	for _, plot in ipairs(Tycoons:GetChildren()) do
		if plotOwnershipMatches(plot) then
			return plot
		end
	end

	return findPlotByCharacter()
end

local function getRatsFolder()
	if not Context.Plot or not Context.Plot.Parent then
		Context.Plot = findPlayerPlot()
	end

	if not Context.Plot then
		return nil, nil
	end

	local ratsFolder = Context.Plot:FindFirstChild("Rats")
	return Context.Plot, ratsFolder
end

local function collectRat(ratNumber)
	local remote = getCollectRatRemote()
	if not remote then
		return false
	end

	local args = { ratNumber }
	local ok = pcall(function()
		remote:FireServer(unpack(args))
	end)

	return ok
end

local function collectAllRats()
	local plot, ratsFolder = getRatsFolder()
	if not plot or not ratsFolder then
		return 0
	end

	local count = 0
	for _, rat in ipairs(ratsFolder:GetChildren()) do
		local ratNumber = tonumber(rat.Name)
		if ratNumber and collectRat(ratNumber) then
			count = count + 1
			Context.RatsCollected = Context.RatsCollected + 1
		end
	end

	return count
end

local function sellRats()
	local remote = getSellRatsRemote()
	if not remote then
		return false
	end

	return pcall(function()
		remote:FireServer()
	end)
end

local function refreshStatus()
	local plot, ratsFolder = getRatsFolder()
	Context.PlotName = plot and plot.Name or "Not found"
	Context.RatsFound = 0

	if ratsFolder then
		for _, rat in ipairs(ratsFolder:GetChildren()) do
			if tonumber(rat.Name) then
				Context.RatsFound = Context.RatsFound + 1
			end
		end
	end

	if Context.PlotLabel then
		pcall(function() Context.PlotLabel:Set("Plot: " .. Context.PlotName) end)
	end
	if Context.RatsFoundLabel then
		pcall(function() Context.RatsFoundLabel:Set("Rats Found: " .. tostring(Context.RatsFound)) end)
	end
	if Context.RatsCollectedLabel then
		pcall(function() Context.RatsCollectedLabel:Set("Rats Collected: " .. tostring(Context.RatsCollected)) end)
	end
end

local function autoCollectLoop(loopId)
	while Context.Alive and Context.CollectEnabled and Context.CollectLoopId == loopId do
		collectAllRats()
		refreshStatus()
		task.wait(Context.CollectDelay)
	end
end

local function setCollectEnabled(enabled)
	Context.CollectEnabled = not not enabled
	Context.CollectLoopId = Context.CollectLoopId + 1
	if Context.CollectEnabled then
		task.spawn(autoCollectLoop, Context.CollectLoopId)
	end
end

local function autoSellLoop(loopId)
	while Context.Alive and Context.SellEnabled and Context.SellLoopId == loopId do
		sellRats()
		task.wait(Context.SellDelay)
	end
end

local function setSellEnabled(enabled)
	Context.SellEnabled = not not enabled
	Context.SellLoopId = Context.SellLoopId + 1
	if Context.SellEnabled then
		task.spawn(autoSellLoop, Context.SellLoopId)
	end
end

local controller, window = Library:Create({
	Title = "tg: @sigmatik323",
	Subtitle = "by sigmatik323",
	ConfigName = "Rat Washing Tycoon",
	ToggleKey = Enum.KeyCode.RightShift,
	Theme = { Accent = "#f59e0b" },
	AutoSave = false,
})

Context.Controller = controller
Context.Window = window

local tab = window:AddTab({ Name = TAB_NAME, Icon = "misc" })

local collectSection = tab:AddSection({ Name = "Auto Collect Rats" })

Context.AutoCollectToggle = collectSection:AddToggle({
	Name = AUTO_COLLECT_NAME,
	Default = false,
	Callback = function(value)
		setCollectEnabled(value)
	end,
})

collectSection:AddButton({
	Name = COLLECT_ONCE_NAME,
	Callback = function()
		collectAllRats()
		refreshStatus()
	end,
})

collectSection:AddButton({
	Name = REFRESH_PLOT_NAME,
	Callback = function()
		Context.Plot = findPlayerPlot()
		refreshStatus()
	end,
})

collectSection:AddSlider({
	Name = COLLECT_DELAY_NAME,
	Min = 0.1,
	Max = 5.0,
	Increment = 0.05,
	Default = 0.5,
	Callback = function(value)
		Context.CollectDelay = value
	end,
})

Context.PlotLabel = collectSection:AddLabel({ Name = PLOT_LABEL_TEXT, Text = PLOT_LABEL_TEXT })
Context.RatsFoundLabel = collectSection:AddLabel({ Name = RATS_FOUND_TEXT, Text = RATS_FOUND_TEXT })
Context.RatsCollectedLabel = collectSection:AddLabel({ Name = RATS_COLLECTED_TEXT, Text = RATS_COLLECTED_TEXT })

local sellSection = tab:AddSection({ Name = "Auto Sell Rats" })

Context.AutoSellToggle = sellSection:AddToggle({
	Name = AUTO_SELL_NAME,
	Default = false,
	Callback = function(value)
		setSellEnabled(value)
	end,
})

sellSection:AddSlider({
	Name = SELL_DELAY_NAME,
	Min = 0.1,
	Max = 10.0,
	Increment = 0.1,
	Default = 1.0,
	Callback = function(value)
		Context.SellDelay = value
	end,
})

sellSection:AddLabel({ Name = ANTI_AFK_NAME, Text = ANTI_AFK_NAME })

local function cleanup()
	Context.Alive = false
	Context.CollectEnabled = false
	Context.SellEnabled = false
	Context.CollectLoopId = Context.CollectLoopId + 1
	Context.SellLoopId = Context.SellLoopId + 1
	disconnectAll()

	if Context.Window then
		pcall(function() Context.Window:Destroy() end)
		Context.Window = nil
	end

	SharedEnvironment.SigmatikRatWashingContext = nil
end

Context.Cleanup = cleanup

addConnection(LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
end))

Context.Plot = findPlayerPlot()
refreshStatus()

task.spawn(function()
	while Context.Alive do
		refreshStatus()
		task.wait(1)
	end
end)
