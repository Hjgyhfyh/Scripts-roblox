if _G.__NoobIncUnload then pcall(_G.__NoobIncUnload) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Modules = Shared:WaitForChild("Modules")

local NetFolder = ReplicatedStorage:WaitForChild("__Net")
local GetPlayerData = NetFolder:FindFirstChild("GetPlayerData")

local function safeRequire(inst)
	if not inst then return nil end
	local ok, m = pcall(require, inst)
	return ok and m or nil
end

local Upgrades = safeRequire(Modules:FindFirstChild("Upgrades"))
local Noobs = safeRequire(Modules:FindFirstChild("Noobs"))
local UITree = safeRequire(Modules:FindFirstChild("UIUpgradeTree"))
local LabTree = safeRequire(Modules:FindFirstChild("LabUIUpgradeTree"))
local Prestiges = safeRequire(Modules:FindFirstChild("Prestiges"))
local Realms = safeRequire(Modules:FindFirstChild("Realms"))

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

local CONV_NAMES = { "DepositWood", "WoodRankUp", "DepositWheat", "ExchangeAllMinerals", "ExchangeAllAnimalProducts" }
local EXPED_NAMES = { "Easy", "Medium", "Hard" }
local EQUIP_STATS = { "Oof", "Cash", "Prism" }

local RATES = {
	NoobUpgrade = 80,
	UpgradeSweep = 80,
	UITree = 50,
	LabTree = 50,
	Converters = 5,
	MergeFactories = 6,
	OpenChests = 10,
}

local SAVE_FILE = "NoobIncremental_config.json"

local Config = {
	NoobUpgrade = true,
	UpgradeSweep = true,
	UITree = true,
	LabTree = false,
	MergeFactories = false,
	Expeditions = false,
	Converters = true,
	OpenChests = true,
	EquipBest = true,
	ClaimQuests = true,
	Boosts = true,
	AuraAuto = false,
	noobs = {},
	cats = {},
	conv = {},
	exped = {},
	equip = {},
}

local function initDefaults()
	for _, n in NOOB_NAMES do if Config.noobs[n] == nil then Config.noobs[n] = true end end
	for _, c in UPGRADE_ORDER do if Config.cats[c] == nil then Config.cats[c] = true end end
	for _, a in CONV_NAMES do if Config.conv[a] == nil then Config.conv[a] = true end end
	for _, e in EXPED_NAMES do if Config.exped[e] == nil then Config.exped[e] = true end end
	for i, s in EQUIP_STATS do if Config.equip[s] == nil then Config.equip[s] = (i == 1) end end
end

local function loadConfig()
	if isfile and readfile and isfile(SAVE_FILE) then
		pcall(function()
			local saved = HttpService:JSONDecode(readfile(SAVE_FILE))
			if type(saved) == "table" then
				for k, v in pairs(saved) do Config[k] = v end
			end
		end)
	end
end

local function saveConfig()
	if not writefile then return end
	pcall(function() writefile(SAVE_FILE, HttpService:JSONEncode(Config)) end)
end

loadConfig()
initDefaults()

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

local function makeLimiter(rate)
	local allowance = rate
	local last = os.clock()
	return function()
		while running do
			local now = os.clock()
			allowance = math.min(rate, allowance + (now - last) * rate)
			last = now
			if allowance >= 1 then
				allowance -= 1
				return true
			end
			task.wait((1 - allowance) / rate)
		end
		return false
	end
end

local function send(...)
	return pcall(Net.Fire, ...)
end

local function invoke(...)
	if type(Net.Invoke) ~= "function" then return false end
	return pcall(Net.Invoke, ...)
end

local function num(x)
	if type(x) == "number" then return x end
	if type(x) == "string" then return tonumber(x) end
	if type(x) == "table" then
		local m, e = tonumber(x[1]), tonumber(x[2])
		if m and e then return m * 10 ^ e end
		if m then return m end
	end
	return nil
end

local function log10of(x)
	local s = tostring(x)
	local m, e = string.match(s, "^(-?[%d%.]+)[eE](-?%d+)$")
	if m and e then
		local mn = tonumber(m)
		if mn and mn > 0 then return math.log10(mn) + tonumber(e) end
	end
	local n = tonumber(s)
	if n and n > 0 then return math.log10(n) end
	return -math.huge
end

local dataCache, dataAt = nil, 0
local function readData()
	if not GetPlayerData then return nil end
	local now = os.clock()
	if dataCache and (now - dataAt) < 1 then return dataCache end
	local ok, result = pcall(function()
		return GetPlayerData:InvokeServer()
	end)
	if ok and type(result) == "table" then
		dataCache = result
		dataAt = now
		return result
	end
	return dataCache
end

local function balanceOf(data, currency)
	local c = data.CURRENCIES and data.CURRENCIES[currency]
	if c and c.Amount then return num(c.Amount[1]) or 0 end
	return 0
end

local function P(gate)
	if not Prestiges then return true end
	local ok, r = pcall(Prestiges.isUnlocked, LocalPlayer, gate)
	return ok and r == true
end

local function R(gate)
	if not Realms then return true end
	local ok, r = pcall(Realms.isUnlocked, LocalPlayer, gate)
	return ok and r == true
end

local function boardUnlocked(data, cat)
	if not Upgrades then return true end
	local pg = Upgrades.TypeUnlocks and Upgrades.TypeUnlocks[cat]
	local rg = Upgrades.TypeRealmUnlocks and Upgrades.TypeRealmUnlocks[cat]
	if pg and not P(pg) then return false end
	if rg then
		local ru = tonumber(data.FEATURES and data.FEATURES.REALMS and data.FEATURES.REALMS.RealmUnlockeds) or 1
		if ru < rg then return false end
	end
	return true
end

local function upgradeUnlocked(cat, key)
	local list = Upgrades and Upgrades.List
	local def = list and list[cat] and list[cat][key]
	if not def then return false end
	if type(def.unlock) ~= "function" then return true end
	local ok, r = pcall(def.unlock, LocalPlayer)
	return ok and r == true
end

local function sumTable(t)
	local s = 0
	if type(t) == "table" then
		for _, v in pairs(t) do s += (num(v) or 0) end
	end
	return s
end

local noobGate = makeLimiter(RATES.NoobUpgrade)
spawnLoop(function()
	while running do
		if Config.NoobUpgrade and Noobs and Noobs.List then
			local data = readData()
			if data and data.FEATURES and data.FEATURES.NOOBS then
				for _, name in NOOB_NAMES do
					if not running or not Config.NoobUpgrade then break end
					if Config.noobs[name] ~= false then
						local def = Noobs.List[name]
						local nd = data.FEATURES.NOOBS[name]
						if def and nd and tostring(nd.Unlocked) == "true" and type(def.noobPrice) == "function" then
							local lvl = tonumber(nd.Level) or 0
							local currency = def.currency or "Oof"
							local okc, price = pcall(def.noobPrice, lvl + 1)
							local p = okc and num(price)
							if p and balanceOf(data, currency) >= p then
								if noobGate() then send("UpgradeNoob", name) end
							end
						end
					end
				end
			end
		end
		task.wait(0.25)
	end
end)

local sweepGate = makeLimiter(RATES.UpgradeSweep)
spawnLoop(function()
	while running do
		if Config.UpgradeSweep and Upgrades and Upgrades.List then
			local data = readData()
			if data and data.UPGRADES then
				for _, cat in UPGRADE_ORDER do
					if not running or not Config.UpgradeSweep then break end
					if Config.cats[cat] ~= false and boardUnlocked(data, cat) then
						local list = Upgrades.List[cat]
						local catData = data.UPGRADES[cat]
						if list and catData then
							local bal = balanceOf(data, cat)
							for _, key in UPGRADE_KEYS[cat] do
								if not running or not Config.UpgradeSweep then break end
								local up = list[key]
								if up and type(up.cost) == "function" and upgradeUnlocked(cat, key) then
									local lvl = tonumber(catData[key]) or 0
									local okm, mx = pcall(up.max, LocalPlayer)
									if not okm then okm, mx = pcall(up.max) end
									mx = (okm and tonumber(mx)) or math.huge
									if lvl < mx then
										local okc, c = pcall(up.cost, lvl + 1)
										local price = okc and num(c)
										if price and bal >= price then
											if sweepGate() then send("UpgradeUpgradeMax", cat, key) end
										end
									end
								end
							end
						end
					end
				end
			end
		end
		task.wait(0.3)
	end
end)

local function nodeList(treeMod)
	local list = {}
	if treeMod and type(treeMod.Nodes) == "table" then
		for name in treeMod.Nodes do
			if type(name) == "string" then
				if name == "TheStart" then
					table.insert(list, 1, name)
				else
					table.insert(list, name)
				end
			end
		end
	end
	return list
end

local function treeLoop(treeMod, action, treeField, currency, enabledKey, rate)
	if not treeMod or type(treeMod.Nodes) ~= "table" then return end
	local names = nodeList(treeMod)
	local gate = makeLimiter(rate)
	spawnLoop(function()
		while running do
			if Config[enabledKey] then
				local data = readData()
				local levels = data and data[treeField]
				if type(levels) == "table" then
					local getLevel = function(n) return tonumber(levels[n]) or 0 end
					local bal = balanceOf(data, currency)
					for _, name in names do
						if not running or not Config[enabledKey] then break end
						local node = treeMod.Nodes[name]
						if type(node) == "table" then
							local lvl = getLevel(name)
							local mx = tonumber(node.maxLevel) or 1
							if lvl < mx then
								local unlocked = true
								if type(treeMod.IsNodeUnlocked) == "function" then
									local oku, u = pcall(treeMod.IsNodeUnlocked, name, getLevel)
									if oku then unlocked = u end
								end
								if unlocked then
									local price = 0
									if type(node.getCost) == "function" then
										local okg, g = pcall(node.getCost, lvl)
										price = (okg and num(g)) or 0
									end
									if bal >= price then
										if gate() then send(action, name) end
									end
								end
							end
						end
					end
				end
			else
				task.wait(0.3)
			end
			task.wait(0.3)
		end
	end)
end

treeLoop(UITree, "BuyUITreeNode", "UI_UPGRADE_TREE", "Prism", "UITree", RATES.UITree)
treeLoop(LabTree, "BuyLabUITreeNode", "LAB_UI_UPGRADE_TREE", "HackPoints", "LabTree", RATES.LabTree)

local mergeGate = makeLimiter(RATES.MergeFactories)
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
					if count >= 5 and mergeGate() then
						send("MergeFactory", tier - 1, true)
					end
				end
			end
		end
		task.wait(1)
	end
end)

local convertGate = makeLimiter(RATES.Converters)
local CONVERTERS = {
	DepositWood = function(data) return R("WoodConverter") and balanceOf(data, "Wood") > 0 end,
	WoodRankUp = function(data) return P("WoodRank") and R("Wood") and balanceOf(data, "Wood") > 0 end,
	DepositWheat = function(data) return P("WheatConverter") and balanceOf(data, "Wheat") > 0 end,
	ExchangeAllMinerals = function(data) return P("Mining") and R("Mining") and sumTable(data.FEATURES and data.FEATURES.MINING and data.FEATURES.MINING.Minerals) > 0 end,
	ExchangeAllAnimalProducts = function(data) return P("Animals") and sumTable(data.FEATURES and data.FEATURES.ANIMALS and data.FEATURES.ANIMALS.Products) > 0 end,
}
spawnLoop(function()
	while running do
		if Config.Converters then
			local data = readData()
			if data then
				for _, action in CONV_NAMES do
					if not running or not Config.Converters then break end
					if Config.conv[action] ~= false then
						local check = CONVERTERS[action]
						local ok, allowed = pcall(check, data)
						if ok and allowed and convertGate() then
							send(action)
						end
					end
				end
			end
		end
		task.wait(2)
	end
end)

local chestGate = makeLimiter(RATES.OpenChests)
spawnLoop(function()
	while running do
		if Config.OpenChests then
			local data = readData()
			if data and data.CURRENCIES then
				for _, kind in { "Chest", "GoldenChest" } do
					if not running or not Config.OpenChests then break end
					if balanceOf(data, kind) > 0 and chestGate() then
						send("OpenChest", kind)
					end
				end
			end
		end
		task.wait(1.5)
	end
end)

local EXPED_GATE = {
	Easy = function() return P("EasyExpedition") end,
	Medium = function() return P("MediumExpedition") end,
	Hard = function(data) return (tonumber(data.LAB_UI_UPGRADE_TREE and data.LAB_UI_UPGRADE_TREE.UnlockHardExpedition) or 0) >= 1 end,
}
local EXPED_OOF_LOG = { Easy = 125, Medium = 350, Hard = 1300 }
spawnLoop(function()
	while running do
		if Config.Expeditions then
			local data = readData()
			local ex = data and data.FEATURES and data.FEATURES.EXPEDITIONS
			local noobs = data and data.FEATURES and data.FEATURES.NOOBS
			if type(ex) == "table" and type(noobs) == "table" then
				local busy = {}
				for _, info in pairs(ex) do
					if type(info) == "table" and info.Noob and info.Noob ~= "" then busy[info.Noob] = true end
				end
				local oofLog = log10of(data.CURRENCIES and data.CURRENCIES.Oof and data.CURRENCIES.Oof.Amount and data.CURRENCIES.Oof.Amount[1])
				for _, diff in EXPED_NAMES do
					if not running or not Config.Expeditions then break end
					if Config.exped[diff] ~= false then
						local slot = ex[diff]
						local gateOk = false
						local okg, g = pcall(EXPED_GATE[diff], data)
						gateOk = okg and g == true
						if type(slot) == "table" and (slot.Noob == nil or slot.Noob == "") and gateOk and oofLog >= (EXPED_OOF_LOG[diff] or 0) then
							for _, name in NOOB_NAMES do
								if name ~= "Starter" and not busy[name] then
									local nd = noobs[name]
									if nd and tostring(nd.Unlocked) == "true" then
										send("SendNoobExpedition", diff, name)
										busy[name] = true
										break
									end
								end
							end
						end
					end
				end
			end
		end
		task.wait(5)
	end
end)

spawnLoop(function()
	while running do
		if Config.EquipBest then
			for _, stat in EQUIP_STATS do
				if not running or not Config.EquipBest then break end
				if Config.equip[stat] then
					send("EquipBest", stat)
				end
			end
		end
		task.wait(8)
	end
end)

spawnLoop(function()
	while running do
		if Config.ClaimQuests then
			local data = readData()
			local quests = data and data.FEATURES and data.FEATURES.QUESTS
			if type(quests) == "table" then
				for period, block in pairs(quests) do
					if not running or not Config.ClaimQuests then break end
					local set = type(block) == "table" and block.Quests
					if type(set) == "table" then
						for questName, q in pairs(set) do
							if type(q) == "table" then
								local goal = tonumber(q.Goal) or 0
								local prog = tonumber(q.Progress) or 0
								if goal > 0 and prog >= goal and q.Claimed ~= true then
									send("ClaimQuest", period, questName)
								end
							end
						end
					end
				end
			end
			local extra = data and data.EXTRA
			if extra and extra.GuildID and extra.GuildID ~= "" and extra.GUILD_WEEKLY_HAS_CLAIMABLE == true then
				invoke("ClaimAllGuildWeeklyRewards")
			end
		end
		task.wait(15)
	end
end)

local boostsDone = false
spawnLoop(function()
	while running do
		if Config.Boosts and not boostsDone then
			send("CheckAllFollows")
			send("CheckGroupRank", true)
			boostsDone = true
		end
		task.wait(60)
		boostsDone = false
	end
end)

local auraToggled = false
spawnLoop(function()
	while running do
		if Config.AuraAuto and not auraToggled then
			if send("ToggleAuraAuto") then auraToggled = true end
		end
		task.wait(1)
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
	well = Color3.fromRGB(16, 16, 26),
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

local WIN_W, WIN_H = 312, 506
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
end

local function makeSwitch(parent, w, h, get)
	local switch = Instance.new("TextButton")
	switch.Size = UDim2.fromOffset(w, h)
	switch.BackgroundColor3 = get() and THEME.on or THEME.off
	switch.Text = ""
	switch.AutoButtonColor = false
	switch.Parent = parent
	corner(switch, h / 2)
	local knob = Instance.new("Frame")
	local k = h - 6
	knob.Size = UDim2.fromOffset(k, k)
	knob.Position = get() and UDim2.new(1, -(k + 3), 0.5, -k / 2) or UDim2.new(0, 3, 0.5, -k / 2)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = switch
	corner(knob, k / 2)
	local function refresh()
		local on = get()
		TweenService:Create(switch, TWEEN, { BackgroundColor3 = on and THEME.on or THEME.off }):Play()
		TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = on and UDim2.new(1, -(k + 3), 0.5, -k / 2) or UDim2.new(0, 3, 0.5, -k / 2),
		}):Play()
	end
	return switch, refresh
end

local function makeSubRow(subTable, subKey)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = THEME.well
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Visible = false
	row.Parent = body
	corner(row, 8)

	local mark = Instance.new("Frame")
	mark.Size = UDim2.fromOffset(3, 16)
	mark.Position = UDim2.fromOffset(10, 7)
	mark.BackgroundColor3 = THEME.violet
	mark.BorderSizePixel = 0
	mark.Parent = row
	corner(mark, 2)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(22, 0)
	label.Size = UDim2.new(1, -70, 1, 0)
	label.Font = Enum.Font.Gotham
	label.Text = subKey
	label.TextColor3 = THEME.dim
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local switch, refresh = makeSwitch(row, 34, 18, function() return Config[subTable][subKey] end)
	switch.Position = UDim2.new(1, -44, 0.5, -9)
	track(switch.MouseButton1Click:Connect(function()
		Config[subTable][subKey] = not Config[subTable][subKey]
		refresh()
		saveConfig()
	end))
	return row
end

local function addToggle(labelText, key, desc, subTable, subKeys)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, desc and 50 or 40)
	row.BackgroundColor3 = THEME.card
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = body
	corner(row, 10)
	stroke(row, THEME.line, 1, 0.35)

	local hasSub = subTable ~= nil and subKeys ~= nil

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(hasSub and 22 or 12, desc and 8 or 0)
	label.Size = UDim2.new(1, -84, 0, desc and 16 or 40)
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
		d.Position = UDim2.fromOffset(hasSub and 22 or 12, 26)
		d.Size = UDim2.new(1, -84, 0, 16)
		d.Font = Enum.Font.Gotham
		d.Text = desc
		d.TextColor3 = THEME.faint
		d.TextSize = 11
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Parent = row
	end

	local switch, refresh = makeSwitch(row, 42, 22, function() return Config[key] end)
	switch.Position = UDim2.new(1, -54, 0.5, -11)
	track(switch.MouseButton1Click:Connect(function()
		Config[key] = not Config[key]
		refresh()
		saveConfig()
	end))

	if hasSub then
		local caret = Instance.new("TextLabel")
		caret.BackgroundTransparency = 1
		caret.Position = UDim2.fromOffset(9, 0)
		caret.Size = UDim2.fromOffset(12, row.Size.Y.Offset)
		caret.Font = Enum.Font.GothamBold
		caret.Text = "+"
		caret.TextColor3 = THEME.violet
		caret.TextSize = 15
		caret.Parent = row

		local subRows = {}
		for _, sk in ipairs(subKeys) do
			table.insert(subRows, makeSubRow(subTable, sk))
		end
		local expanded = false
		local function toggleExpand()
			expanded = not expanded
			caret.Text = expanded and "−" or "+"
			for _, r in ipairs(subRows) do r.Visible = expanded end
		end
		track(row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				toggleExpand()
			end
		end))
		track(switch.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				toggleExpand()
			end
		end))
	end
end

sectionLabel("Автофарм")
addToggle("Прокачка нубиков", "NoobUpgrade", "ПКМ — выбрать нубиков", "noobs", NOOB_NAMES)
addToggle("Апгрейды", "UpgradeSweep", "ПКМ — выбрать категории", "cats", UPGRADE_ORDER)
addToggle("Prism дерево", "UITree", "Узлы за Prism")
addToggle("Lab дерево", "LabTree", "Узлы за HackPoints")
addToggle("Слияние фабрик", "MergeFactories", "При 5+ в тире (необратимо)")
addToggle("Экспедиции", "Expeditions", "ПКМ — сложности", "exped", EXPED_NAMES)

sectionLabel("Сбор и клейм")
addToggle("Конвертеры / обмен", "Converters", "ПКМ — выбрать", "conv", CONV_NAMES)
addToggle("Открытие сундуков", "OpenChests", "Chest / GoldenChest при наличии")
addToggle("Авто-экип лучшего", "EquipBest", "ПКМ — статы", "equip", EQUIP_STATS)
addToggle("Клейм квестов", "ClaimQuests", "Daily / Weekly + гильдия")
addToggle("Бусты фоллоу/группа", "Boosts", "Активация бустов")
addToggle("Авто-ауры", "AuraAuto", "Серверный авто-ролл")

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

saveConfig()
