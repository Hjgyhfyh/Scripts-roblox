if _G.__ChickenFarmUnload then pcall(_G.__ChickenFarmUnload) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Paper = require(ReplicatedStorage:WaitForChild("Paper"))
local Network = Paper.Network
local Stats = Paper.Stats
local ChickensData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shared"):WaitForChild("Chickens"))

Stats.LoadedAsync()

local EggsFolder = workspace:WaitForChild("Eggs", 15)
local BUY_AMOUNTS = { 100, 25, 5, 1 }
local MAX_RATE = 400

local LB_NAMES = { "TotalChickens", "Networth", "TimePlayed" }
local LB_LABEL = { TotalChickens = "Chickens", Networth = "Networth", TimePlayed = "Time" }
local LeaderboardsFolder = workspace:FindFirstChild("Leaderboards")
local LB_CUTOFF = {}
if LeaderboardsFolder then
	for _, board in LeaderboardsFolder:GetChildren() do
		local normal = board:FindFirstChild("Main")
		normal = normal and normal:FindFirstChild("UI")
		normal = normal and normal:FindFirstChild("Normal")
		local lastText, lastPlace = nil, -1
		if normal then
			for _, e in normal:GetChildren() do
				if e:IsA("Frame") then
					local p = e:FindFirstChild("Place", true)
					local a = e:FindFirstChild("Amount", true)
					if p and a then
						local num = tonumber((tostring(p.Text):gsub("#", ""):gsub("%s", "")))
						if num and num > lastPlace then
							lastPlace = num
							lastText = tostring(a.Text)
						end
					end
				end
			end
		end
		LB_CUTOFF[board.Name] = lastText
	end
end

local Config = {
	CollectEggs = true,
	DepositEggs = true,
	CollectCash = true,
	BuyChickens = true,
	MergeChickens = true,
	UpgradeProcess = true,
	GroupReward = true,
	LuckyBlocks = true,
	OpenPaidLucky = true,
	CallsPerSec = 300,
}

local Counters = { collected = 0, deposits = 0, cash = 0, buys = 0, merges = 0, upgrades = 0, lucky = 0 }

local running = true
local connections = {}
local threads = {}
local screenGui

local function track(conn)
	table.insert(connections, conn)
	return conn
end

local function spawnLoop(fn)
	local t = task.spawn(fn)
	table.insert(threads, t)
	return t
end

-- Rate limiting (token bucket, shared across every remote call)
local allowance = MAX_RATE
local lastRefill = os.clock()
local function waitToken()
	while running do
		local r = math.clamp(Config.CallsPerSec, 1, MAX_RATE)
		local now = os.clock()
		allowance = math.min(r, allowance + (now - lastRefill) * r)
		lastRefill = now
		if allowance >= 1 then
			allowance -= 1
			return true
		end
		task.wait((1 - allowance) / r)
	end
	return false
end

local function fire(...)
	if not running or not waitToken() then return end
	pcall(Network.FireServer, ...)
end

local function invoke(...)
	if not running or not waitToken() then return nil end
	local packed = { pcall(Network.InvokeServer, ...) }
	if packed[1] then
		return table.unpack(packed, 2)
	end
	return nil
end

local function stat(key)
	local ok, value = pcall(Stats.GetValue, key)
	if ok then return value end
	return nil
end

local function cost(fn, ...)
	local ok, value = pcall(fn, ...)
	if ok and type(value) == "number" then return value end
	return nil
end

local function unixTime()
	local ok, value = pcall(function() return Paper.Misc.GetUnixTime() end)
	if ok and type(value) == "number" then return value end
	return os.time()
end

local function formatNumber(n)
	local ok, value = pcall(function() return Paper.Number.format(n) end)
	if ok then return value end
	return tostring(n)
end

-- Egg collection
local function collectEgg(egg)
	if not Config.CollectEggs or not egg or not egg.Parent then return end
	if egg:GetAttribute("LuckyBlock") ~= nil then return end
	if egg:GetAttribute("Tier") == nil then return end
	fire("Collect Egg", egg.Name)
	Counters.collected += 1
	pcall(function() egg:Destroy() end)
end

if EggsFolder then
	track(EggsFolder.ChildAdded:Connect(function(child)
		task.defer(collectEgg, child)
	end))
end

spawnLoop(function()
	while running do
		if Config.CollectEggs and EggsFolder then
			for _, egg in EggsFolder:GetChildren() do
				if not running then break end
				collectEgg(egg)
			end
		end
		task.wait(0.4)
	end
end)

-- Lucky blocks
local function collectLuckyDrops()
	if not Config.LuckyBlocks or not EggsFolder then return end
	if stat("EquippedLuckyBlock") ~= 0 then return end
	for _, model in EggsFolder:GetChildren() do
		if not running then break end
		if model:GetAttribute("LuckyBlock") ~= nil then
			if invoke("Collect Lucky Block", model.Name) then
				Counters.lucky += 1
				pcall(function() model:Destroy() end)
				break
			end
		end
	end
end

local function tryOpenLucky()
	if not Config.LuckyBlocks then return end
	local equipped = stat("EquippedLuckyBlock")
	if not equipped or equipped == 0 then return end
	local canOpen = stat("IsCurrentLuckyBlockFree") == true
	if not canOpen and Config.OpenPaidLucky then
		local price = cost(ChickensData.GetLuckyBlockCost, stat("TotalChickens") or 0, equipped)
		if price and (stat("Cash") or 0) >= price then
			canOpen = true
		end
	end
	if canOpen then
		local ok, result = invoke("Open Lucky Block")
		if ok and type(result) == "number" then
			fire("Claim Opened Chicken")
			Counters.lucky += 1
		end
	end
end

-- Management
local lastMerge = 0
spawnLoop(function()
	while running do
		local cash = stat("Cash") or 0
		local totalChickens = stat("TotalChickens") or 0
		local level = stat("ProcessingLevel") or 0

		if Config.DepositEggs and (stat("Eggs") or 0) > 0 then
			if invoke("Deposit Eggs") then Counters.deposits += 1 end
		end

		if Config.CollectCash and (stat("CashCollect") or 0) > 0 then
			if invoke("Collect Cash") then Counters.cash += 1 end
		end

		cash = stat("Cash") or cash

		if Config.UpgradeProcess then
			local price = cost(ChickensData.GetProcessCost, level)
			if price and cash >= price then
				if invoke("Upgrade Process Level") then
					Counters.upgrades += 1
					cash -= price
				end
			end
		end

		if Config.BuyChickens then
			for _, amount in BUY_AMOUNTS do
				local price = cost(ChickensData.GetBuyChickenCost, totalChickens, amount)
				if price and cash >= price then
					if invoke("Buy Chickens", amount) then Counters.buys += 1 end
					break
				end
			end
		end

		if Config.MergeChickens and (os.clock() - lastMerge) >= 1 then
			local inventory = stat("Chickens")
			local eligible = false
			if type(inventory) == "table" then
				for tier, count in inventory do
					if type(tier) == "number" and type(count) == "number" and count >= 3 and tier < 26 then
						eligible = true
						break
					end
				end
			end
			if eligible then
				if invoke("Merge Chickens") then Counters.merges += 1 end
				lastMerge = os.clock()
			end
		end

		collectLuckyDrops()
		tryOpenLucky()

		task.wait(0.3)
	end
end)

-- Slow rewards
spawnLoop(function()
	task.wait(1)
	if running and (stat("OfflineEarnings") or 0) > 0 then
		invoke("Claim Offline Earnings")
	end
	while running do
		if Config.GroupReward and stat("InGroup") == true then
			if unixTime() >= (stat("LastGroupClaim") or 0) + 600 then
				invoke("Claim Group Reward")
			end
		end
		task.wait(15)
	end
end)

-- Anti-AFK
track(LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

-- Interface
local THEME = {
	bg = Color3.fromRGB(24, 26, 33),
	panel = Color3.fromRGB(31, 34, 43),
	row = Color3.fromRGB(38, 42, 53),
	accent = Color3.fromRGB(247, 188, 75),
	on = Color3.fromRGB(101, 184, 65),
	off = Color3.fromRGB(78, 84, 99),
	text = Color3.fromRGB(236, 239, 244),
	dim = Color3.fromRGB(150, 157, 172),
}

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function padding(parent, p)
	local u = Instance.new("UIPadding")
	u.PaddingTop = UDim.new(0, p)
	u.PaddingBottom = UDim.new(0, p)
	u.PaddingLeft = UDim.new(0, p)
	u.PaddingRight = UDim.new(0, p)
	u.Parent = parent
	return u
end

screenGui = Instance.new("ScreenGui")
screenGui.Name = "CF_" .. tostring(math.random(100000, 999999))
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
pcall(function()
	screenGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not screenGui.Parent then
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(320, 536)
main.Position = UDim2.new(0.5, -160, 0.5, -268)
main.BackgroundColor3 = THEME.bg
main.BorderSizePixel = 0
main.Parent = screenGui
corner(main, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 0, 0)
stroke.Transparency = 0.5
stroke.Thickness = 1
stroke.Parent = main

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 50)
header.BackgroundColor3 = THEME.panel
header.BorderSizePixel = 0
header.Parent = main
corner(header, 12)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 14)
headerFix.Position = UDim2.new(0, 0, 1, -14)
headerFix.BackgroundColor3 = THEME.panel
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 0)
title.Size = UDim2.new(1, -70, 1, 0)
title.Font = Enum.Font.GothamBold
title.Text = "🐣 Chicken Farm"
title.TextColor3 = THEME.text
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -38, 0, 11)
closeBtn.BackgroundColor3 = Color3.fromRGB(190, 70, 72)
closeBtn.Text = "✕"
closeBtn.TextColor3 = THEME.text
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.AutoButtonColor = true
closeBtn.Parent = header
corner(closeBtn, 8)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, 0, 1, -50 - 162)
list.Position = UDim2.fromOffset(0, 50)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = THEME.accent
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = main
padding(list, 12)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function makeToggle(labelText, key)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundColor3 = THEME.row
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = list
	corner(row, 8)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(1, -70, 1, 0)
	label.Font = Enum.Font.GothamMedium
	label.Text = labelText
	label.TextColor3 = THEME.text
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local switch = Instance.new("TextButton")
	switch.Size = UDim2.fromOffset(44, 22)
	switch.Position = UDim2.new(1, -56, 0.5, -11)
	switch.BackgroundColor3 = Config[key] and THEME.on or THEME.off
	switch.Text = ""
	switch.AutoButtonColor = false
	switch.Parent = row
	corner(switch, 11)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(18, 18)
	knob.Position = Config[key] and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = switch
	corner(knob, 9)

	track(switch.MouseButton1Click:Connect(function()
		Config[key] = not Config[key]
		local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
		TweenService:Create(switch, info, { BackgroundColor3 = Config[key] and THEME.on or THEME.off }):Play()
		TweenService:Create(knob, info, { Position = Config[key] and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9) }):Play()
	end))
end

makeToggle("Auto Collect Eggs", "CollectEggs")
makeToggle("Auto Deposit Eggs", "DepositEggs")
makeToggle("Auto Collect Cash", "CollectCash")
makeToggle("Auto Buy Chickens", "BuyChickens")
makeToggle("Auto Merge Chickens", "MergeChickens")
makeToggle("Auto Upgrade Process", "UpgradeProcess")
makeToggle("Auto Group Reward", "GroupReward")
makeToggle("Auto Lucky Blocks", "LuckyBlocks")
makeToggle("Open Paid Lucky Blocks", "OpenPaidLucky")

local rateRow = Instance.new("Frame")
rateRow.Size = UDim2.new(1, 0, 0, 38)
rateRow.BackgroundColor3 = THEME.row
rateRow.BorderSizePixel = 0
rateRow.LayoutOrder = nextOrder()
rateRow.Parent = list
corner(rateRow, 8)

local rateLabel = Instance.new("TextLabel")
rateLabel.BackgroundTransparency = 1
rateLabel.Position = UDim2.fromOffset(12, 0)
rateLabel.Size = UDim2.new(1, -90, 1, 0)
rateLabel.Font = Enum.Font.GothamMedium
rateLabel.Text = "Calls / sec"
rateLabel.TextColor3 = THEME.text
rateLabel.TextSize = 14
rateLabel.TextXAlignment = Enum.TextXAlignment.Left
rateLabel.Parent = rateRow

local rateBox = Instance.new("TextBox")
rateBox.Size = UDim2.fromOffset(64, 24)
rateBox.Position = UDim2.new(1, -76, 0.5, -12)
rateBox.BackgroundColor3 = THEME.bg
rateBox.Font = Enum.Font.GothamBold
rateBox.Text = tostring(Config.CallsPerSec)
rateBox.TextColor3 = THEME.accent
rateBox.TextSize = 14
rateBox.ClearTextOnFocus = false
rateBox.Parent = rateRow
corner(rateBox, 6)

track(rateBox.FocusLost:Connect(function()
	local value = tonumber(rateBox.Text)
	if value then
		Config.CallsPerSec = math.clamp(math.floor(value), 1, MAX_RATE)
	end
	rateBox.Text = tostring(Config.CallsPerSec)
end))

local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, 0, 0, 96)
footer.Position = UDim2.new(0, 0, 1, -96)
footer.BackgroundColor3 = THEME.panel
footer.BorderSizePixel = 0
footer.Parent = main
corner(footer, 12)

local statsLabel = Instance.new("TextLabel")
statsLabel.BackgroundTransparency = 1
statsLabel.Position = UDim2.fromOffset(14, 8)
statsLabel.Size = UDim2.new(1, -28, 0, 56)
statsLabel.Font = Enum.Font.Gotham
statsLabel.Text = ""
statsLabel.TextColor3 = THEME.dim
statsLabel.TextSize = 12
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.TextYAlignment = Enum.TextYAlignment.Top
statsLabel.RichText = true
statsLabel.Parent = footer

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -28, 0, 26)
unloadBtn.Position = UDim2.new(0, 14, 1, -32)
unloadBtn.BackgroundColor3 = Color3.fromRGB(190, 70, 72)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.Text = "Unload"
unloadBtn.TextColor3 = THEME.text
unloadBtn.TextSize = 14
unloadBtn.Parent = footer
corner(unloadBtn, 8)

spawnLoop(function()
	while running do
		local cash = stat("Cash") or 0
		local held = stat("Eggs") or 0
		local tc = stat("TotalChickens") or 0
		local lvl = stat("ProcessingLevel") or 0
		pcall(function()
			statsLabel.Text = string.format(
				"<font color='#F7BC4B'>Cash</font> %s   <font color='#F7BC4B'>Eggs</font> %s\n<font color='#F7BC4B'>Chickens</font> %s   <font color='#F7BC4B'>Process Lv</font> %d\n<font color='#65B841'>Collected</font> %d  <font color='#65B841'>Deposits</font> %d  <font color='#65B841'>Buys</font> %d",
				formatNumber(cash), formatNumber(held), formatNumber(tc), lvl,
				Counters.collected, Counters.deposits, Counters.buys
			)
		end)
		task.wait(0.5)
	end
end)

-- Dragging
do
	local dragging, dragStart, startPos
	track(header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

-- Unload
local function unload()
	if not running then return end
	running = false
	for _, conn in connections do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(connections)
	for _, t in threads do
		pcall(task.cancel, t)
	end
	table.clear(threads)
	if screenGui then
		pcall(function() screenGui:Destroy() end)
	end
	_G.__ChickenFarmUnload = nil
end

track(closeBtn.MouseButton1Click:Connect(unload))
track(unloadBtn.MouseButton1Click:Connect(unload))
_G.__ChickenFarmUnload = unload
