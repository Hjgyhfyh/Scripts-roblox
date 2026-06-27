if _G.__NoobIncUnload then pcall(_G.__NoobIncUnload) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local NetFolder = ReplicatedStorage:WaitForChild("__Net")
local GetPlayerData = NetFolder:FindFirstChild("GetPlayerData")

local MAX_RATE = 400

local NOOB_NAMES = {
	"Starter", "Archer", "Cooker", "Farmer", "Soldier", "Fisherman",
	"Explorer", "Knight", "Magician", "Hacker 1", "Hacker 2", "Hacker 3", "Hacker 4",
}

local UPGRADE_KEYS = {
	Oof = { "MoreOof", "FasterNoobs", "MoreRebirth", "MoreOofBonus", "EvenMoreOof", "MoreWalkSpeed", "MoreCash", "MoreOofRealm2", "MoreWalkSpeedRealm2" },
	Cash = { "MoreCash", "FasterDropper", "MoreRuneLuck", "MoreMutationLuck", "MoreTierLuck", "MoreTierBulk", "MoreMutationLuck2" },
	Coin = { "MoreWheat", "MoreCoins2", "NewBreadUpgrade" },
	Gem = { "MoreOof", "MoreGems", "StrongerPickaxes", "MoreOreStats" },
	Wood = { "MoreWood", "BiggerWoodDeposit", "FasterWoodConversion", "SharperAxes", "MorePlanksFromWood" },
	Ice = { "MoreIce", "MoreOof", "WaterFromIce", "WaterPumpNoobHire" },
	Bread = { "MoreBread", "MoreWheat", "MoreTierLuck", "BiggerWheatDeposit", "MoreConsumption", "FasterWheatConversion", "MoreRuneLuck", "MoreBread2" },
	Fire = { "MoreFire", "MoreOof", "MoreRebirth", "MoreBulk", "MoreCashBonus", "MoreTierLuck", "PleaseMoreOof", "AlwaysMoreLuck", "MoreMoreMoreFire", "EvenMoreTierBulk", "EvenMoreRuneBulk" },
	Blaze = { "MoreBlaze", "MoreFire", "MoreOof", "MoreBulk", "MoreOofs", "AlwaysMoreFire", "EvenMoreMoney" },
	Water = { "MoreWater", "MoreOof", "MorePlanks", "MoreGems" },
	Planks = { "MorePlanks", "WaterFromPlanks", "MoreWood" },
	HackPoints = { "MoreRuneSpeed", "MoreRuneBulk", "MoreRuneLuck", "MoreHackPoints", "AutoHackPointsCollector" },
	Goals = { "MoreGoals" },
	Rebirth = { "MoreOof", "MoreRebirth", "MoreFire", "MoreMoreMoreOofs", "MorePrisms" },
}

local UPGRADE_ORDER = { "Oof", "Rebirth", "Fire", "Blaze", "Cash", "Bread", "Coin", "Gem", "Water", "Wood", "Ice", "Planks", "HackPoints", "Goals" }

local CONVERTERS = { "DepositWood", "DepositWheat", "WoodRankUp", "ExchangeAllMinerals", "ExchangeAllAnimalProducts" }

local RATES = {
	NoobUpgrade = 60,
	UpgradeSweep = 90,
	UITree = 30,
	LabTree = 30,
	Converters = 5,
	MergeFactories = 5,
}

local Config = {
	NoobUpgrade = true,
	UpgradeSweep = true,
	UITree = true,
	Converters = true,
	LabTree = false,
	MergeFactories = false,
	AuraAuto = false,
	ClaimQuests = false,
}

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

local allowance = MAX_RATE
local lastRefill = os.clock()
local function activeRate()
	local r = 0
	for key, value in RATES do
		if Config[key] then r += value end
	end
	if r < 1 then r = 1 end
	return r
end

local function waitToken()
	while running do
		local r = math.clamp(activeRate(), 1, MAX_RATE)
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
	if not running or not waitToken() then return false end
	return pcall(Net.Fire, ...)
end

local dataCache, dataAt = nil, 0
local function readData()
	if not GetPlayerData then return nil end
	local now = os.clock()
	if dataCache and (now - dataAt) < 2 then return dataCache end
	local ok, result = pcall(function()
		return GetPlayerData:InvokeServer()
	end)
	if ok and type(result) == "table" then
		dataCache = result
		dataAt = now
		return result
	end
	return nil
end

spawnLoop(function()
	while running do
		if Config.NoobUpgrade then
			for _, name in NOOB_NAMES do
				if not running or not Config.NoobUpgrade then break end
				fire("UpgradeNoob", name)
				task.wait()
			end
		end
		task.wait(0.1)
	end
end)

spawnLoop(function()
	while running do
		if Config.UpgradeSweep then
			for _, cat in UPGRADE_ORDER do
				if not running or not Config.UpgradeSweep then break end
				local keys = UPGRADE_KEYS[cat]
				if keys then
					for _, key in keys do
						if not running or not Config.UpgradeSweep then break end
						fire("UpgradeUpgradeMax", cat, key)
					end
				end
			end
		end
		task.wait(0.2)
	end
end)

local function loadTreeNodes(moduleName)
	local list = {}
	local modules = ReplicatedStorage.Shared:FindFirstChild("Modules")
	local mod = modules and modules:FindFirstChild(moduleName)
	if not mod then return list end
	local ok, m = pcall(require, mod)
	if not ok or type(m) ~= "table" or type(m.Nodes) ~= "table" then return list end
	for nodeName in m.Nodes do
		if type(nodeName) == "string" then
			if nodeName == "TheStart" then
				table.insert(list, 1, nodeName)
			else
				table.insert(list, nodeName)
			end
		end
	end
	return list
end

local UI_TREE_NODES = loadTreeNodes("UIUpgradeTree")
local LAB_TREE_NODES = loadTreeNodes("LabUIUpgradeTree")

local function sweepTree(action, nodeList, enabledKey)
	spawnLoop(function()
		while running do
			if Config[enabledKey] and #nodeList > 0 then
				for _, node in nodeList do
					if not running or not Config[enabledKey] then break end
					fire(action, node)
					task.wait()
				end
			end
			task.wait(0.3)
		end
	end)
end

sweepTree("BuyUITreeNode", UI_TREE_NODES, "UITree")
sweepTree("BuyLabUITreeNode", LAB_TREE_NODES, "LabTree")

spawnLoop(function()
	while running do
		if Config.MergeFactories then
			local data = readData()
			local factories = data and data.FEATURES and data.FEATURES.FACTORIES
			if type(factories) == "table" then
				for tier = 1, 6 do
					if not running or not Config.MergeFactories then break end
					local v = factories[tier] or factories[tostring(tier)]
					if type(v) == "table" then v = v.Value or v[1] end
					local count = tonumber(v) or 0
					if count >= 5 then
						fire("MergeFactory", tier - 1, true)
						task.wait(0.1)
					end
				end
			end
		end
		task.wait(1)
	end
end)

spawnLoop(function()
	while running do
		if Config.Converters then
			for _, action in CONVERTERS do
				if not running or not Config.Converters then break end
				fire(action)
			end
		end
		task.wait(2)
	end
end)

local auraToggled = false
spawnLoop(function()
	while running do
		if Config.AuraAuto and not auraToggled then
			if fire("ToggleAuraAuto") then auraToggled = true end
		end
		task.wait(1)
	end
end)

spawnLoop(function()
	while running do
		if Config.ClaimQuests then
			local data = readData()
			local quests = data and data.EXTRA and data.EXTRA.QUESTS
			if type(quests) == "table" then
				for period, set in quests do
					if not running or not Config.ClaimQuests then break end
					if type(set) == "table" then
						for questName, info in set do
							if type(info) == "table" and info.Claimed ~= true then
								fire("ClaimQuest", period, questName)
							end
						end
					end
				end
			end
		end
		task.wait(20)
	end
end)

track(LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

local THEME = {
	bg = Color3.fromRGB(12, 12, 20),
	panel = Color3.fromRGB(19, 19, 30),
	card = Color3.fromRGB(25, 25, 38),
	well = Color3.fromRGB(15, 15, 24),
	line = Color3.fromRGB(43, 43, 61),
	text = Color3.fromRGB(244, 245, 247),
	dim = Color3.fromRGB(169, 173, 190),
	faint = Color3.fromRGB(107, 110, 128),
	on = Color3.fromRGB(43, 209, 126),
	off = Color3.fromRGB(58, 60, 80),
	bad = Color3.fromRGB(242, 85, 90),
	violet = Color3.fromRGB(139, 108, 255),
	cyan = Color3.fromRGB(86, 192, 255),
}

local TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or THEME.line
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function pad(parent, l, t, r, b)
	local u = Instance.new("UIPadding")
	u.PaddingLeft = UDim.new(0, l or 0)
	u.PaddingTop = UDim.new(0, t or 0)
	u.PaddingRight = UDim.new(0, r or 0)
	u.PaddingBottom = UDim.new(0, b or 0)
	u.Parent = parent
	return u
end

local function gradient(parent, c1, c2, rot)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c1, c2)
	g.Rotation = rot or 90
	g.Parent = parent
	return g
end

screenGui = Instance.new("ScreenGui")
screenGui.Name = "NI_" .. tostring(math.random(100000, 999999))
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 9999
pcall(function()
	screenGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not screenGui.Parent then
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local WIN_W, WIN_H = 300, 472
local HEADER_H = 52
local FOOTER_H = 50

local shadow = Instance.new("ImageLabel")
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://6014261993"
shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
shadow.ImageTransparency = 0.45
shadow.ScaleType = Enum.ScaleType.Slice
shadow.SliceCenter = Rect.new(49, 49, 450, 450)
shadow.Size = UDim2.fromOffset(WIN_W + 60, WIN_H + 60)
shadow.Position = UDim2.new(0.5, -(WIN_W + 60) / 2, 0.5, -(WIN_H + 60) / 2)
shadow.ZIndex = 0
shadow.Parent = screenGui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(WIN_W, WIN_H)
main.Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2)
main.BackgroundColor3 = THEME.bg
main.BorderSizePixel = 0
main.ZIndex = 1
main.Parent = screenGui
corner(main, 14)
stroke(main, THEME.line, 1, 0.1)
gradient(main, Color3.fromRGB(20, 20, 32), THEME.bg, 90)

local function syncShadow()
	shadow.Position = UDim2.new(main.Position.X.Scale, main.Position.X.Offset - 30, main.Position.Y.Scale, main.Position.Y.Offset - 30)
end

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = THEME.panel
header.BorderSizePixel = 0
header.Parent = main
corner(header, 14)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 16)
headerFix.Position = UDim2.new(0, 0, 1, -16)
headerFix.BackgroundColor3 = THEME.panel
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.fromOffset(4, 22)
accentBar.Position = UDim2.fromOffset(16, (HEADER_H - 22) / 2)
accentBar.BorderSizePixel = 0
accentBar.Parent = header
corner(accentBar, 2)
gradient(accentBar, THEME.violet, THEME.cyan, 90)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(30, 0)
title.Size = UDim2.new(1, -110, 0, HEADER_H)
title.Font = Enum.Font.GothamBold
title.Text = "Новичок-инкременталист"
title.TextColor3 = THEME.text
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextYAlignment = Enum.TextYAlignment.Center
title.Parent = header

local function makeIconButton(x, baseColor)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(28, 28)
	b.Position = UDim2.new(1, x, 0, (HEADER_H - 28) / 2)
	b.BackgroundColor3 = baseColor
	b.Text = ""
	b.AutoButtonColor = true
	b.Parent = header
	corner(b, 8)
	return b
end

local minBtn = makeIconButton(-76, THEME.card)
stroke(minBtn, THEME.line, 1, 0.2)
local minLine = Instance.new("Frame")
minLine.Size = UDim2.fromOffset(12, 2)
minLine.Position = UDim2.new(0.5, -6, 0.5, -1)
minLine.BackgroundColor3 = THEME.dim
minLine.BorderSizePixel = 0
minLine.Parent = minBtn
corner(minLine, 1)

local closeBtn = makeIconButton(-42, Color3.fromRGB(40, 24, 30))
stroke(closeBtn, THEME.bad, 1, 0.4)
for i = -1, 1, 2 do
	local x = Instance.new("Frame")
	x.Size = UDim2.fromOffset(14, 2)
	x.Position = UDim2.new(0.5, -7, 0.5, -1)
	x.BackgroundColor3 = THEME.bad
	x.BorderSizePixel = 0
	x.Rotation = 45 * i
	x.Parent = closeBtn
	corner(x, 1)
end

local body = Instance.new("ScrollingFrame")
body.Size = UDim2.new(1, 0, 1, -HEADER_H - FOOTER_H)
body.Position = UDim2.fromOffset(0, HEADER_H)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollBarImageColor3 = THEME.violet
body.ScrollBarImageTransparency = 0.3
body.CanvasSize = UDim2.new()
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.Parent = main
pad(body, 14, 12, 14, 12)

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.Padding = UDim.new(0, 8)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Parent = body

track(bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	body.CanvasSize = UDim2.new(0, 0, 0, bodyLayout.AbsoluteContentSize.Y + 24)
end))

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function sectionLabel(text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.Text = string.upper(text)
	l.TextColor3 = THEME.faint
	l.TextSize = 10
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = nextOrder()
	l.Parent = body
	return l
end

local function makeToggle(labelText, key, desc)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, desc and 50 or 40)
	row.BackgroundColor3 = THEME.card
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = body
	corner(row, 10)
	stroke(row, THEME.line, 1, 0.35)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, desc and 8 or 0)
	label.Size = UDim2.new(1, -68, 0, desc and 16 or 40)
	label.Font = Enum.Font.GothamMedium
	label.Text = labelText
	label.TextColor3 = THEME.text
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = row

	if desc then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Position = UDim2.fromOffset(12, 26)
		d.Size = UDim2.new(1, -68, 0, 16)
		d.Font = Enum.Font.Gotham
		d.Text = desc
		d.TextColor3 = THEME.faint
		d.TextSize = 11
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Parent = row
	end

	local switch = Instance.new("TextButton")
	switch.Size = UDim2.fromOffset(42, 22)
	switch.Position = UDim2.new(1, -54, 0.5, -11)
	switch.BackgroundColor3 = Config[key] and THEME.on or THEME.off
	switch.Text = ""
	switch.AutoButtonColor = false
	switch.Parent = row
	corner(switch, 11)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = Config[key] and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = switch
	corner(knob, 8)

	track(switch.MouseButton1Click:Connect(function()
		Config[key] = not Config[key]
		TweenService:Create(switch, TWEEN, { BackgroundColor3 = Config[key] and THEME.on or THEME.off }):Play()
		TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = Config[key] and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
		}):Play()
	end))
end

sectionLabel("Автофарм")
makeToggle("Прокачка нубиков", "NoobUpgrade", "Главный доход Oof (UpgradeNoob)")
makeToggle("Апгрейды (Max)", "UpgradeSweep", "Все валюты × все апгрейды")
makeToggle("Prism дерево", "UITree", "Скупка узлов за Prism")
makeToggle("Lab дерево", "LabTree", "Узлы за HackPoints")
makeToggle("Слияние фабрик", "MergeFactories", "Только при 5+ в тире (необратимо)")

sectionLabel("Сбор и обмен")
makeToggle("Конвертеры / обмен", "Converters", "Wood / Wheat / минералы / продукты")
makeToggle("Авто-ауры", "AuraAuto", "Серверный авто-ролл (тратит dice)")
makeToggle("Сбор квестов", "ClaimQuests", "Daily / Weekly награды")

local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
footer.Position = UDim2.new(0, 0, 1, -FOOTER_H)
footer.BackgroundColor3 = THEME.panel
footer.BorderSizePixel = 0
footer.Parent = main
corner(footer, 14)

local footerTop = Instance.new("Frame")
footerTop.Size = UDim2.new(1, 0, 0, 16)
footerTop.BackgroundColor3 = THEME.panel
footerTop.BorderSizePixel = 0
footerTop.Parent = footer

local footerLine = Instance.new("Frame")
footerLine.Size = UDim2.new(1, -28, 0, 1)
footerLine.Position = UDim2.fromOffset(14, 0)
footerLine.BackgroundColor3 = THEME.line
footerLine.BackgroundTransparency = 0.4
footerLine.BorderSizePixel = 0
footerLine.Parent = footer

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -28, 0, 30)
unloadBtn.Position = UDim2.new(0, 14, 0.5, -13)
unloadBtn.BackgroundColor3 = Color3.fromRGB(40, 24, 30)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.Text = "ВЫГРУЗИТЬ"
unloadBtn.TextColor3 = THEME.bad
unloadBtn.TextSize = 13
unloadBtn.AutoButtonColor = true
unloadBtn.Parent = footer
corner(unloadBtn, 9)
stroke(unloadBtn, THEME.bad, 1, 0.5)

local collapsed = false
track(minBtn.MouseButton1Click:Connect(function()
	collapsed = not collapsed
	body.Visible = not collapsed
	footer.Visible = not collapsed
	local h = collapsed and HEADER_H or WIN_H
	TweenService:Create(main, TWEEN, { Size = UDim2.fromOffset(WIN_W, h) }):Play()
	task.delay(0.17, syncShadow)
	shadow.Visible = not collapsed
end))

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
			syncShadow()
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

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
	_G.__NoobIncUnload = nil
end

track(closeBtn.MouseButton1Click:Connect(unload))
track(unloadBtn.MouseButton1Click:Connect(unload))
_G.__NoobIncUnload = unload
