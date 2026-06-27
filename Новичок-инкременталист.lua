if _G.__NoobIncUnload then pcall(_G.__NoobIncUnload) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local MainRemote = ReplicatedStorage:WaitForChild("__Net"):WaitForChild("MainRemote")
local GetPlayerData = ReplicatedStorage.__Net:FindFirstChild("GetPlayerData")

local MAX_RATE = 400

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

local CONVERTERS = {
	{ key = "DepositWood", action = "DepositWood" },
	{ key = "DepositWheat", action = "DepositWheat" },
	{ key = "WoodRankUp", action = "WoodRankUp" },
	{ key = "ExchangeMinerals", action = "ExchangeAllMinerals" },
	{ key = "ExchangeAnimals", action = "ExchangeAllAnimalProducts" },
}

local Config = {
	UpgradeSweep = true,
	UITree = true,
	LabTree = false,
	MergeFactories = false,
	Converters = true,
	AuraAuto = false,
	ClaimQuests = false,

	SweepRate = 120,
	TreeRate = 24,
	ConvertRate = 4,
	MergeMinCount = 5,
}

local Counters = { sweep = 0, tree = 0, lab = 0, merge = 0, convert = 0, aura = 0, quest = 0 }

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
	if Config.UpgradeSweep then r += Config.SweepRate end
	if Config.UITree then r += Config.TreeRate end
	if Config.LabTree then r += Config.TreeRate end
	if Config.Converters then r += Config.ConvertRate end
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

local function getLevel(data, cat, key)
	if not data then return 0 end
	local up = data.UPGRADES
	if type(up) ~= "table" then return 0 end
	local c = up[cat]
	if type(c) ~= "table" then return 0 end
	local v = c[key]
	if type(v) == "table" then v = v.Value or v[1] end
	return tonumber(v) or 0
end

local function featureCount(data, path)
	if not data or type(data.FEATURES) ~= "table" then return 0 end
	local node = data.FEATURES
	for _, seg in path do
		if type(node) ~= "table" then return 0 end
		node = node[seg]
	end
	if type(node) == "table" then node = node.Value or node[1] end
	return tonumber(node) or 0
end

spawnLoop(function()
	while running do
		if Config.UpgradeSweep then
			local data = readData()
			for _, cat in UPGRADE_ORDER do
				if not running or not Config.UpgradeSweep then break end
				local keys = UPGRADE_KEYS[cat]
				if keys then
					for _, key in keys do
						if not running or not Config.UpgradeSweep then break end
						if fire("UpgradeUpgradeMax", cat, key) then
							Counters.sweep += 1
						end
					end
				end
			end
		end
		task.wait(0.2)
	end
end)

local function sweepTree(action, counterKey, treeField, enabledKey)
	spawnLoop(function()
		while running do
			if Config[enabledKey] then
				local data = readData()
				local nodes = data and data[treeField]
				if type(nodes) == "table" then
					for node, lvl in nodes do
						if not running or not Config[enabledKey] then break end
						if type(node) == "string" and tonumber(lvl) ~= nil then
							if fire(action, node) then
								Counters[counterKey] += 1
							end
							task.wait()
						end
					end
				end
			end
			task.wait(0.3)
		end
	end)
end

sweepTree("BuyUITreeNode", "tree", "UI_UPGRADE_TREE", "UITree")
sweepTree("BuyLabUITreeNode", "lab", "LAB_UI_UPGRADE_TREE", "LabTree")

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
					if count >= math.max(5, Config.MergeMinCount) then
						if fire("MergeFactory", tier - 1, true) then
							Counters.merge += 1
						end
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
			for _, conv in CONVERTERS do
				if not running or not Config.Converters then break end
				if fire(conv.action) then
					Counters.convert += 1
				end
			end
		end
		task.wait(2)
	end
end)

local auraToggled = false
spawnLoop(function()
	while running do
		if Config.AuraAuto and not auraToggled then
			if fire("ToggleAuraAuto") then
				auraToggled = true
				Counters.aura += 1
			end
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
								if fire("ClaimQuest", period, questName) then
									Counters.quest += 1
								end
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
	gold = Color3.fromRGB(255, 209, 102),
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

local WIN_W, WIN_H = 332, 540
local HEADER_H = 52
local FOOTER_H = 116

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

local function makeRate(labelText, key)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = THEME.card
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = body
	corner(row, 10)
	stroke(row, THEME.line, 1, 0.35)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(1, -92, 1, 0)
	label.Font = Enum.Font.GothamMedium
	label.Text = labelText
	label.TextColor3 = THEME.text
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(64, 26)
	box.Position = UDim2.new(1, -76, 0.5, -13)
	box.BackgroundColor3 = THEME.well
	box.Font = Enum.Font.Code
	box.Text = tostring(Config[key])
	box.TextColor3 = THEME.cyan
	box.TextSize = 13
	box.ClearTextOnFocus = false
	box.Parent = row
	corner(box, 7)
	stroke(box, THEME.line, 1, 0.2)

	track(box.FocusLost:Connect(function()
		local v = tonumber(box.Text)
		if v then
			Config[key] = math.clamp(math.floor(v), 1, MAX_RATE)
		end
		box.Text = tostring(Config[key])
	end))
end

sectionLabel("Автофарм апгрейдов")
makeToggle("Upgrade Sweep (Max)", "UpgradeSweep", "Все валюты x все апгрейды")
makeToggle("Prism Tree (UI)", "UITree", "Скупка узлов за Prism")
makeToggle("Lab Tree (HackPoints)", "LabTree", "Узлы за HackPoints")
makeToggle("Merge Factories", "MergeFactories", "Только при 5+ в тире")

sectionLabel("Конвертеры и сбор")
makeToggle("Converters / Exchange", "Converters", "Wood / Wheat / Minerals / Products")
makeToggle("Auto Aura Roll", "AuraAuto", "Серверный авто-ролл (тратит dice)")
makeToggle("Claim Quests", "ClaimQuests", "Daily / Weekly награды")

sectionLabel("Лимит запросов (в секунду)")
makeRate("Sweep rate", "SweepRate")
makeRate("Tree rate", "TreeRate")
makeRate("Convert rate", "ConvertRate")

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

local statsLabel = Instance.new("TextLabel")
statsLabel.BackgroundTransparency = 1
statsLabel.Position = UDim2.fromOffset(14, 12)
statsLabel.Size = UDim2.new(1, -28, 0, 60)
statsLabel.Font = Enum.Font.Code
statsLabel.Text = ""
statsLabel.TextColor3 = THEME.dim
statsLabel.TextSize = 11
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.TextYAlignment = Enum.TextYAlignment.Top
statsLabel.RichText = true
statsLabel.LineHeight = 1.25
statsLabel.Parent = footer

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -28, 0, 30)
unloadBtn.Position = UDim2.new(0, 14, 1, -40)
unloadBtn.BackgroundColor3 = Color3.fromRGB(40, 24, 30)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.Text = "ВЫГРУЗИТЬ"
unloadBtn.TextColor3 = THEME.bad
unloadBtn.TextSize = 13
unloadBtn.AutoButtonColor = true
unloadBtn.Parent = footer
corner(unloadBtn, 9)
stroke(unloadBtn, THEME.bad, 1, 0.5)

local function fmtRate()
	return string.format("%d", activeRate())
end

spawnLoop(function()
	while running do
		pcall(function()
			local data = readData()
			local oofMul = "?"
			local prism = "?"
			if data and type(data.CURRENCIES) == "table" then
				local oof = data.CURRENCIES.Oof
				if type(oof) == "table" and oof.TotalMultiplier then
					oofMul = tostring(oof.TotalMultiplier)
				end
				local pr = data.CURRENCIES.Prism
				if type(pr) == "table" and type(pr.Amount) == "table" then
					prism = tostring(pr.Amount[1])
				end
			end
			statsLabel.Text = string.format(
				"<font color='#8B6CFF'>OofMul</font> %s   <font color='#8B6CFF'>Prism</font> %s\n<font color='#56C0FF'>Up</font> %d  <font color='#56C0FF'>Tree</font> %d  <font color='#56C0FF'>Merge</font> %d  <font color='#56C0FF'>Conv</font> %d\n<font color='#2BD17E'>rate</font> %s/s  <font color='#6B6E80'>limit 400</font>",
				oofMul, prism, Counters.sweep, Counters.tree, Counters.merge, Counters.convert, fmtRate()
			)
		end)
		task.wait(0.6)
	end
end)

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
