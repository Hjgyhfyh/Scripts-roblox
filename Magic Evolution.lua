--[[
	+1 Magic Evolution — Auto Progression Suite
	Полностью автономный фарм: магия → уровни → ребирсы → зоны, авто-экип лучшего
	снаряжения, авто-покупка палочек, выдача топ рун/брони, сбор халявы. Анти-афк встроен.
]]

if _G.__MAGICEVO_SUITE and _G.__MAGICEVO_SUITE.unload then
	pcall(_G.__MAGICEVO_SUITE.unload)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local GroupService = game:GetService("GroupService")

local LocalPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not Remotes then return end

local PLACE_MAIN = 116223724643557
local PLACE_DUNGEON = 140070560575882
local MODE = (game.PlaceId == PLACE_DUNGEON) and "dungeon" or "main"

----------------------------------------------------------------------
-- Данные игры (сняты из конфигов)
----------------------------------------------------------------------

-- Нужный Level для ребирса №i (RebirthConfig.LevelRequirements)
local REBIRTH_LEVELS = {
	8,12,16,21,26,31,36,42,48,54,60,67,74,81,88,96,104,112,120,128,
	136,144,152,160,169,178,187,196,205,214,224,234,244,254,265,276,287,298,310,322,
	334,346,358,371,384,397,410,423,437,451,465,479,493,508,523,538,553,568,584,600,
	616,632,648,664,680,697,714,731,748,765,783,801,819,837,855,
}
local MAX_REBIRTHS = 75

-- Порог Trophies для входа в зону N (TeleportConfig.TrophyRequirements)
local TROPHY_REQ = {
	[2]=1,[3]=3,[4]=10,[5]=25,[6]=100,[7]=800,[8]=2000,[9]=4500,[10]=15000,
	[11]=45000,[12]=80000,[13]=150000,[14]=300000,[15]=700000,[16]=1500000,
	[17]=3000000,[18]=7500000,[19]=15000000,[20]=45000000,[21]=75000000,
	[22]=120000000,[23]=200000000,[24]=350000000,[25]=550000000,[26]=800000000,
	[27]=1500000000,[28]=4000000000,[29]=9000000000,[30]=18000000000,[31]=40000000000,
}

-- Палочки: кнопка в workspace.StaffButtons -> {имя, цена в Wins}. Dragon Wand (21) пропущен (ловушка).
local WAND_BUTTONS = {
	{n=2,  wand="Thorn Wand",          cost=1},
	{n=3,  wand="Wooden Staff",        cost=3},
	{n=4,  wand="Moonlight Wand",      cost=10},
	{n=5,  wand="Crystal Branch Wand", cost=25},
	{n=6,  wand="Magic Lantern Staff", cost=100},
	{n=7,  wand="Mushroom Staff",      cost=500},
	{n=8,  wand="Spirit Wand",         cost=2000},
	{n=9,  wand="Rune Staff",          cost=7500},
	{n=10, wand="Ember Wand",          cost=25000},
	{n=11, wand="Storm Scepter",       cost=200000},
	{n=12, wand="Void Scepter",        cost=850000},
	{n=13, wand="Bone Staff",          cost=1800000},
	{n=14, wand="Lava Staff",          cost=5000000},
	{n=15, wand="Celestial Staff",     cost=25000000},
	{n=16, wand="Frost Staff",         cost=150000000},
	{n=17, wand="Astral Polearm",      cost=500000000},
	{n=18, wand="Ancient Wizard Staff",cost=1000000000},
	{n=19, wand="Demonic Staff",       cost=5000000000},
	{n=20, wand="Angelic Halo Staff",  cost=40000000000},
}

local EGG_COST = {
	["Basic Egg"]=400, ["Fire Egg"]=12000, ["Arcane Egg"]=225000,
	["Astral Egg"]=6500000, ["Demonic Egg"]=200000000,
}

-- Топ стат-руны для прогресса (Power = больше магии за клик; Health/Defense = выживание). По одной.
local GIVE_RUNES = {
	"Legendary Power Rune",
	"Legendary Health Rune",
	"Legendary Defense Rune",
}
-- Босс-руны (боевые проки) — опционально, по 1 шт
local BOSS_RUNES = {"Lunar Rune","Angelic Rune","Gladiator Gem","Molten Rune","Acid Rune","Demonic Rune"}
-- Топ броня — по одному предмету на слот
local GIVE_ARMOR = {
	"Angelic Chestplate",
	"Angelic Boots",
}

local FREE_REWARDS_GROUP = 7955090

----------------------------------------------------------------------
-- Состояние
----------------------------------------------------------------------

local state = { run = true }
local conns = {}
local threads = {}
local busy = false -- идёт выдача гира
local Suite = {}

local S = {
	master       = true,
	autoClick    = true,
	clickRate    = 50,     -- вызовов GainMagicPower в секунду (суммарно по всем remote держим <=400)
	autoRebirth  = true,
	autoZone     = true,
	autoEquip    = true,
	autoWands    = true,
	autoClaim    = true,
	autoEgg      = false,  -- только когда персонаж сам стоит у яйца (без телепорта)
	giveBoss     = false,  -- добавлять босс-руны при выдаче рун
	-- Данж
	dgnAOE       = true,   -- урон по всем мобам волны сразу
	dgnRate      = 6,      -- проходов AOE в секунду
	dgnCards     = true,   -- авто-выбор карт усиления
	dgnMods      = false,  -- голосовать за модификаторы (усиливают мобов — риск)
	dgnReturn    = true,   -- при смерти выходить в лобби (без робукс-реврана)
}

-- Сохранение настроек между сессиями
local CONFIG_FILE = "MagicEvolution_config.json"

local function saveConfig()
	if typeof(writefile) ~= "function" then return end
	pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(S)) end)
end

local function loadConfig()
	if typeof(readfile) ~= "function" then return end
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok or type(raw) ~= "string" or raw == "" then return end
	local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok2 or type(data) ~= "table" then return end
	for k, v in pairs(data) do
		if S[k] ~= nil and type(v) == type(S[k]) then S[k] = v end
	end
end

loadConfig()

local function track(c) conns[#conns+1] = c; return c end
local function spawnLoop(fn)
	local t = task.spawn(fn)
	threads[#threads+1] = t
	return t
end

----------------------------------------------------------------------
-- Утилиты
----------------------------------------------------------------------

local function attr(name, default)
	local v = LocalPlayer:GetAttribute(name)
	if v == nil then return default end
	return v
end

local function getWins()
	return tonumber(attr("Wins", attr("Trophies", 0))) or 0
end

local function getTrophies()
	return tonumber(attr("Trophies", attr("Wins", 0))) or 0
end

local function fmt(n)
	n = tonumber(n) or 0
	local neg = n < 0; n = math.abs(n)
	local units = {{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}}
	for _, u in ipairs(units) do
		if n >= u[1] then
			local v = n / u[1]
			return (neg and "-" or "") .. string.format(v >= 100 and "%.0f%s" or "%.2f%s", v, u[2])
		end
	end
	return (neg and "-" or "") .. string.format("%d", math.floor(n))
end

local function fire(name, ...)
	local r = Remotes:FindFirstChild(name)
	if not r then return false end
	local args = {...}
	return pcall(function() r:FireServer(table.unpack(args)) end)
end

local function invoke(name, ...)
	local r = Remotes:FindFirstChild(name)
	if not r then return nil end
	local args = {...}
	local ok, res = pcall(function() return r:InvokeServer(table.unpack(args)) end)
	if ok then return res end
	return nil
end

local function getHRP()
	local char = LocalPlayer.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function findTouchPart(model)
	if not model then return nil end
	local tp = model:FindFirstChild("TouchPart", true)
	if tp and tp:IsA("BasePart") then return tp end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d end
	end
	if model:IsA("BasePart") then return model end
	return nil
end

----------------------------------------------------------------------
-- Действия фарма
----------------------------------------------------------------------

local function canClick()
	return attr("ClientHatchingEgg", false) ~= true and (tostring(attr("ActiveEggName","")) == "")
end

local function tryRebirth()
	local reb = tonumber(attr("Rebirths", 0)) or 0
	if reb >= MAX_REBIRTHS then return end
	local need = REBIRTH_LEVELS[reb + 1]
	if not need then return end
	local lvl = tonumber(attr("Level", 1)) or 1
	if lvl >= need then
		fire("Rebirth")
	end
end

local lastZone = nil
local function tryZone()
	local troph = getTrophies()
	local mult2 = (tonumber(attr("WinsMultiplier", 1)) or 1) >= 2
	local maxN = 1
	for N = 2, 31 do
		local req = TROPHY_REQ[N]
		if req then
			if mult2 then req = req * 2 end
			if troph >= req then maxN = N end
		end
	end
	if maxN ~= lastZone then
		if fire("TeleportToStage", maxN) then
			lastZone = maxN
		end
	end
end

local function equipBest()
	fire("RequestEquipBestWand")
	fire("EquipBestRunes")
	fire("EquipBestArmor")
	fire("EquipBestPets")
end

local function getOwnedWands()
	local set = { ["Twig Wand"]=true, ["Wooden Staff"]=true }
	local raw = attr("OwnedWandsJSON", "")
	if type(raw) == "string" and raw ~= "" then
		local ok, t = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(t) == "table" then
			for _, v in ipairs(t) do
				if type(v) == "string" then set[v] = true
				elseif type(v) == "table" and v.Name then set[v.Name] = true end
			end
		end
	end
	return set
end

local function buyWand(buttonN)
	local sb = workspace:FindFirstChild("StaffButtons")
	if not sb then return false end
	local btn = sb:FindFirstChild("Staff Button" .. buttonN)
	if not btn then return false end
	local tp = findTouchPart(btn)
	local hrp = getHRP()
	if tp and hrp and typeof(firetouchinterest) == "function" then
		pcall(function()
			firetouchinterest(hrp, tp, 0)
			task.wait(0.06)
			firetouchinterest(hrp, tp, 1)
		end)
		return true
	end
	return false
end

local function tryBuyWands()
	if typeof(firetouchinterest) ~= "function" then return end
	local owned = getOwnedWands()
	local wins = getWins()
	local bought = false
	for _, w in ipairs(WAND_BUTTONS) do
		if not owned[w.wand] and wins >= w.cost then
			if buyWand(w.n) then
				bought = true
				task.wait(0.1)
			end
		end
	end
	if bought then fire("RequestEquipBestWand") end
end

local function tryEgg()
	local egg = tostring(attr("ActiveEggName", ""))
	if egg == "" then return end
	if attr("ClientHatchingEgg", false) == true then return end
	local cost = EGG_COST[egg]
	if not cost then return end
	if getWins() >= cost then
		invoke("OpenEgg", egg)
	end
end

-- Выдача гира: каждый предмет одним вызовом (по одной штуке)
local function giveGear(kind)
	if busy then return end
	busy = true
	spawnLoop(function()
		local rate = 12
		if kind == "runes" or kind == "all" then
			for _, name in ipairs(GIVE_RUNES) do
				if not state.run then busy=false; return end
				fire("RunePickedUp", name)
				task.wait(1 / rate)
			end
			if S.giveBoss then
				for _, name in ipairs(BOSS_RUNES) do
					if not state.run then busy=false; return end
					fire("RunePickedUp", name)
					task.wait(1 / rate)
				end
			end
			fire("EquipBestRunes")
		end
		if kind == "armor" or kind == "all" then
			for _, name in ipairs(GIVE_ARMOR) do
				if not state.run then busy=false; return end
				fire("ArmorPickedUp", name)
				task.wait(1 / rate)
			end
			fire("EquipBestArmor")
		end
		busy = false
		if Suite and Suite.setStatus then Suite.setStatus("Выдача завершена ✓") end
	end)
end

----------------------------------------------------------------------
-- Халява
----------------------------------------------------------------------

local dailyState = nil
local freeRewardsTried = false

local function setupClaims()
	local dro = Remotes:FindFirstChild("DailyRewardsOpen")
	if dro then track(dro.OnClientEvent:Connect(function(st) dailyState = st end)) end
	local drr = Remotes:FindFirstChild("DailyRewardsResult")
	if drr then track(drr.OnClientEvent:Connect(function(_,_,st) if st then dailyState = st end end)) end
	local frr = Remotes:FindFirstChild("FreeRewardsResult")
	if frr then
		track(frr.OnClientEvent:Connect(function(success, reason)
			if reason == "not_in_group" then
				Suite.setStatus("Free Rewards: вступи в группу " .. FREE_REWARDS_GROUP .. " вручную")
			end
		end))
	end
	-- спекулятивный клейм daily один раз на старте
	task.delay(3, function() if state.run then fire("DailyRewardsClaim") end end)
end

local function tryClaims()
	-- Daily
	if dailyState and dailyState.canClaim and not dailyState.completed then
		fire("DailyRewardsClaim")
		dailyState = nil
	end
	-- Free Auto Clicker (15 мин плейтайма)
	if attr("OwnsFreeAutoClicker", false) ~= true and attr("OwnsAutoClicker", false) ~= true then
		local pt = tonumber(attr("PlaytimeSeconds", 0)) or 0
		if pt >= 900 then fire("ClaimFreeAutoClicker") end
	end
	-- Free Rewards (группа) — одна попытка на старте
	if not freeRewardsTried and attr("HasClaimedFreeRewards", false) ~= true then
		freeRewardsTried = true
		fire("ClaimFreeRewards")
	end
end

----------------------------------------------------------------------
-- Анти-афк
----------------------------------------------------------------------

local function setupAntiAfk()
	track(LocalPlayer.Idled:Connect(function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end))
end

----------------------------------------------------------------------
-- Лупы
----------------------------------------------------------------------

local function startLoops()
	-- Клик-луп (высокочастотный)
	spawnLoop(function()
		while state.run do
			if S.master and S.autoClick and canClick() then
				fire("GainMagicPower")
			end
			local rate = math.clamp(tonumber(S.clickRate) or 50, 1, 250)
			task.wait(1 / rate)
		end
	end)

	-- Логика прогрессии (раз в ~1с)
	spawnLoop(function()
		while state.run do
			if S.master then
				if S.autoRebirth then pcall(tryRebirth) end
				if S.autoZone   then pcall(tryZone) end
				if S.autoEgg    then pcall(tryEgg) end
			end
			task.wait(1)
		end
	end)

	-- Экип + покупка палочек (раз в ~4с)
	spawnLoop(function()
		while state.run do
			if S.master then
				if S.autoEquip then pcall(equipBest) end
				if S.autoWands then pcall(tryBuyWands) end
			end
			task.wait(4)
		end
	end)

	-- Халява (раз в ~20с)
	spawnLoop(function()
		while state.run do
			if S.master and S.autoClaim then pcall(tryClaims) end
			task.wait(20)
		end
	end)
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------

local PAL = {
	bg      = Color3.fromRGB(16, 15, 24),
	panel   = Color3.fromRGB(26, 24, 38),
	panel2  = Color3.fromRGB(34, 31, 50),
	stroke  = Color3.fromRGB(60, 55, 90),
	text    = Color3.fromRGB(236, 234, 246),
	muted   = Color3.fromRGB(150, 148, 172),
	violet  = Color3.fromRGB(138, 99, 255),
	indigo  = Color3.fromRGB(99, 102, 241),
	cyan    = Color3.fromRGB(56, 189, 248),
	on      = Color3.fromRGB(74, 222, 128),
	off     = Color3.fromRGB(64, 62, 84),
	danger  = Color3.fromRGB(248, 113, 113),
}

local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p; return c end
local function stroke(p, col, th) local s = Instance.new("UIStroke"); s.Color = col or PAL.stroke; s.Thickness = th or 1; s.Parent = p; return s end
local function pad(p, n) local u = Instance.new("UIPadding"); u.PaddingLeft=UDim.new(0,n); u.PaddingRight=UDim.new(0,n); u.PaddingTop=UDim.new(0,n); u.PaddingBottom=UDim.new(0,n); u.Parent=p; return u end

local function gradient(p, rot)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, PAL.violet),
		ColorSequenceKeypoint.new(0.5, PAL.indigo),
		ColorSequenceKeypoint.new(1, PAL.cyan),
	})
	g.Rotation = rot or 0
	g.Parent = p
	return g
end

local gui = Instance.new("ScreenGui")
gui.Name = "MagicEvoSuite"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
pcall(function()
	gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
end)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.new(0, 372, 0, 506)
root.Position = UDim2.new(0, 28, 0.5, -253)
root.BackgroundColor3 = PAL.bg
root.BorderSizePixel = 0
root.Active = true
root.Parent = gui
corner(root, 14)
stroke(root, PAL.stroke, 1.5)

-- Заголовок
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = PAL.panel
header.BorderSizePixel = 0
header.Parent = root
corner(header, 14)
local hfix = Instance.new("Frame")
hfix.Size = UDim2.new(1, 0, 0, 16); hfix.Position = UDim2.new(0, 0, 1, -16)
hfix.BackgroundColor3 = PAL.panel; hfix.BorderSizePixel = 0; hfix.Parent = header

local accent = Instance.new("Frame")
accent.Size = UDim2.new(1, -2, 0, 3); accent.Position = UDim2.new(0, 1, 0, 0)
accent.BorderSizePixel = 0; accent.Parent = header
corner(accent, 3); gradient(accent, 0)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 16, 0, 8)
title.Size = UDim2.new(1, -120, 0, 24)
title.Font = Enum.Font.GothamBold
title.Text = "Magic Evolution"
title.TextSize = 18
title.TextColor3 = PAL.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 16, 0, 30)
subtitle.Size = UDim2.new(1, -120, 0, 14)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "Auto Progression"
subtitle.TextSize = 11
subtitle.TextColor3 = PAL.muted
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = header

local function headerBtn(txt, x, col)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 30, 0, 30)
	b.Position = UDim2.new(1, x, 0, 11)
	b.BackgroundColor3 = PAL.panel2
	b.Text = txt
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = col or PAL.text
	b.AutoButtonColor = true
	b.Parent = header
	corner(b, 8); stroke(b, PAL.stroke, 1)
	return b
end
local minBtn = headerBtn("–", -40)
local closeBtn = headerBtn("✕", -74, PAL.danger)

-- Тело со скроллом
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.new(0, 0, 0, 52)
body.Size = UDim2.new(1, 0, 1, -52)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollBarImageColor3 = PAL.violet
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = root
pad(body, 12)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body

local order = 0
local function nextOrder() order = order + 1; return order end

local function section(label)
	local t = Instance.new("TextLabel")
	t.LayoutOrder = nextOrder()
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 18)
	t.Font = Enum.Font.GothamBold
	t.Text = label
	t.TextSize = 12
	t.TextColor3 = PAL.cyan
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = body
end

local function makeToggle(label, key, desc)
	local row = Instance.new("Frame")
	row.LayoutOrder = nextOrder()
	row.Size = UDim2.new(1, 0, 0, desc and 46 or 34)
	row.BackgroundColor3 = PAL.panel
	row.BorderSizePixel = 0
	row.Parent = body
	corner(row, 10); stroke(row, PAL.stroke, 1)

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 12, 0, desc and 6 or 0)
	lbl.Size = UDim2.new(1, -70, 0, desc and 18 or 34)
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = label
	lbl.TextSize = 13
	lbl.TextColor3 = PAL.text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = desc and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
	lbl.Parent = row

	if desc then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Position = UDim2.new(0, 12, 0, 24)
		d.Size = UDim2.new(1, -70, 0, 16)
		d.Font = Enum.Font.Gotham
		d.Text = desc
		d.TextSize = 10
		d.TextColor3 = PAL.muted
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Parent = row
	end

	local sw = Instance.new("TextButton")
	sw.AnchorPoint = Vector2.new(1, 0.5)
	sw.Position = UDim2.new(1, -12, 0.5, 0)
	sw.Size = UDim2.new(0, 46, 0, 24)
	sw.Text = ""
	sw.BackgroundColor3 = S[key] and PAL.on or PAL.off
	sw.AutoButtonColor = false
	sw.Parent = row
	corner(sw, 12)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = S[key] and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
	knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
	knob.BorderSizePixel = 0
	knob.Parent = sw
	corner(knob, 9)

	local function render()
		TweenService:Create(sw, TweenInfo.new(0.16), {BackgroundColor3 = S[key] and PAL.on or PAL.off}):Play()
		TweenService:Create(knob, TweenInfo.new(0.16), {Position = S[key] and UDim2.new(1,-21,0.5,-9) or UDim2.new(0,3,0.5,-9)}):Play()
	end
	sw.MouseButton1Click:Connect(function()
		S[key] = not S[key]
		render()
		saveConfig()
	end)
	return row
end

local function makeButton(label, col, cb)
	local b = Instance.new("TextButton")
	b.LayoutOrder = nextOrder()
	b.Size = UDim2.new(1, 0, 0, 36)
	b.BackgroundColor3 = PAL.panel2
	b.Text = label
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = col or PAL.text
	b.AutoButtonColor = true
	b.Parent = body
	corner(b, 10); stroke(b, col or PAL.stroke, 1)
	b.MouseButton1Click:Connect(function() pcall(cb) end)
	return b
end

-- Слайдер скорости клика (кнопки -/+)
local function makeRate()
	local row = Instance.new("Frame")
	row.LayoutOrder = nextOrder()
	row.Size = UDim2.new(1, 0, 0, 46)
	row.BackgroundColor3 = PAL.panel
	row.BorderSizePixel = 0
	row.Parent = body
	corner(row, 10); stroke(row, PAL.stroke, 1)

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 12, 0, 6)
	lbl.Size = UDim2.new(1, -24, 0, 16)
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = "Скорость клика (вызовов/сек)"
	lbl.TextSize = 12
	lbl.TextColor3 = PAL.text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local minus = Instance.new("TextButton")
	minus.Position = UDim2.new(0, 12, 0, 24)
	minus.Size = UDim2.new(0, 30, 0, 18)
	minus.BackgroundColor3 = PAL.panel2
	minus.Text = "−"; minus.Font = Enum.Font.GothamBold; minus.TextSize = 16; minus.TextColor3 = PAL.text
	minus.Parent = row; corner(minus, 6)

	local val = Instance.new("TextLabel")
	val.BackgroundTransparency = 1
	val.Position = UDim2.new(0, 48, 0, 24)
	val.Size = UDim2.new(0, 60, 0, 18)
	val.Font = Enum.Font.GothamBold
	val.Text = tostring(S.clickRate)
	val.TextSize = 14
	val.TextColor3 = PAL.cyan
	val.TextXAlignment = Enum.TextXAlignment.Center
	val.Parent = row

	local plus = Instance.new("TextButton")
	plus.Position = UDim2.new(0, 114, 0, 24)
	plus.Size = UDim2.new(0, 30, 0, 18)
	plus.BackgroundColor3 = PAL.panel2
	plus.Text = "+"; plus.Font = Enum.Font.GothamBold; plus.TextSize = 16; plus.TextColor3 = PAL.text
	plus.Parent = row; corner(plus, 6)

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, -12, 0, 24)
	hint.Size = UDim2.new(0, 150, 0, 18)
	hint.Font = Enum.Font.Gotham
	hint.Text = "безопасно ≤ 60"
	hint.TextSize = 10
	hint.TextColor3 = PAL.muted
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Parent = row

	local function set(v)
		S.clickRate = math.clamp(v, 5, 200)
		val.Text = tostring(S.clickRate)
		saveConfig()
	end
	minus.MouseButton1Click:Connect(function() set(S.clickRate - 5) end)
	plus.MouseButton1Click:Connect(function() set(S.clickRate + 5) end)
end

-- Статус-панель
local statusBox
local function makeStatus()
	local row = Instance.new("Frame")
	row.LayoutOrder = nextOrder()
	row.Size = UDim2.new(1, 0, 0, 78)
	row.BackgroundColor3 = PAL.panel
	row.BorderSizePixel = 0
	row.Parent = body
	corner(row, 10); stroke(row, PAL.stroke, 1)

	local stats = Instance.new("TextLabel")
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.new(0, 12, 0, 8)
	stats.Size = UDim2.new(1, -24, 0, 52)
	stats.Font = Enum.Font.GothamMedium
	stats.TextSize = 12
	stats.TextColor3 = PAL.text
	stats.TextXAlignment = Enum.TextXAlignment.Left
	stats.TextYAlignment = Enum.TextYAlignment.Top
	stats.RichText = true
	stats.Text = ""
	stats.Parent = row

	statusBox = Instance.new("TextLabel")
	statusBox.BackgroundTransparency = 1
	statusBox.Position = UDim2.new(0, 12, 1, -22)
	statusBox.Size = UDim2.new(1, -24, 0, 16)
	statusBox.Font = Enum.Font.Gotham
	statusBox.TextSize = 11
	statusBox.TextColor3 = PAL.cyan
	statusBox.TextXAlignment = Enum.TextXAlignment.Left
	statusBox.Text = "Готов к работе"
	statusBox.Parent = row

	spawnLoop(function()
		while state.run do
			local lvl = fmt(attr("Level", 0))
			local reb = tostring(attr("Rebirths", 0))
			local troph = fmt(getTrophies())
			local wins = fmt(getWins())
			local mp = fmt(attr("MagicPower", 0))
			local wand = tostring(attr("EquippedWand", "—"))
			stats.Text = string.format(
				"<font color='#9a9ab8'>Уровень</font> %s   <font color='#9a9ab8'>Ребирс</font> %s/75\n<font color='#9a9ab8'>Трофеи</font> %s   <font color='#9a9ab8'>Wins</font> %s\n<font color='#9a9ab8'>Магия</font> %s   <font color='#9a9ab8'>Палочка</font> %s",
				lvl, reb, troph, wins, mp, wand)
			task.wait(0.5)
		end
	end)
end

function Suite.setStatus(txt)
	if statusBox then statusBox.Text = txt end
end

-- Сборка UI
makeStatus()
section("ПРОГРЕССИЯ")
makeToggle("Авто-клик (магия)", "autoClick", "Качает магию, уровни, трофеи и wins")
makeRate()
makeToggle("Авто-ребирс", "autoRebirth", "По достижению нужного уровня")
makeToggle("Авто-зоны", "autoZone", "Переход в лучшую зону по трофеям")
makeToggle("Авто-экип лучшего", "autoEquip", "Палочка, руны, броня, петы")

section("ПАЛОЧКИ")
makeToggle("Авто-покупка палочек", "autoWands", "Лучшая доступная за Wins")

section("ВЫДАЧА СНАРЯЖЕНИЯ")
makeToggle("Добавлять босс-руны", "giveBoss", "Боевые проки (опционально)")
makeButton("Выдать топ-руны + надеть", PAL.violet, function()
	Suite.setStatus("Выдаю руны...")
	giveGear("runes")
end)
makeButton("Выдать топ-броню + надеть", PAL.violet, function()
	Suite.setStatus("Выдаю броню...")
	giveGear("armor")
end)
makeButton("Выдать ВСЁ снаряжение", PAL.indigo, function()
	Suite.setStatus("Выдаю руны и броню...")
	giveGear("all")
end)

section("ХАЛЯВА")
makeToggle("Авто-сбор наград", "autoClaim", "Daily, free-автокликер, group-награда")

section("ОПЦИОНАЛЬНО")
makeToggle("Авто-открытие яиц", "autoEgg", "Только когда стоишь у яйца (без ТП)")

section("УПРАВЛЕНИЕ")
local masterBtn = makeButton(S.master and "■  ПАУЗА" or "▶  ЗАПУСК", PAL.on, function() end)
masterBtn.MouseButton1Click:Connect(function()
	S.master = not S.master
	masterBtn.Text = S.master and "■  ПАУЗА" or "▶  ЗАПУСК"
	masterBtn.TextColor3 = S.master and PAL.on or PAL.muted
	Suite.setStatus(S.master and "Фарм активен" or "Фарм на паузе")
	saveConfig()
end)
makeButton("Выгрузить (Unload)", PAL.danger, function()
	if _G.__MAGICEVO_SUITE and _G.__MAGICEVO_SUITE.unload then _G.__MAGICEVO_SUITE.unload() end
end)

----------------------------------------------------------------------
-- Перетаскивание + свернуть
----------------------------------------------------------------------

do
	local dragging, dragStart, startPos
	local function update(input)
		local d = input.Position - dragStart
		root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
	track(header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true; dragStart = input.Position; startPos = root.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end))
end

local collapsed = false
minBtn.MouseButton1Click:Connect(function()
	collapsed = not collapsed
	body.Visible = not collapsed
	TweenService:Create(root, TweenInfo.new(0.2), {Size = collapsed and UDim2.new(0,372,0,52) or UDim2.new(0,372,0,506)}):Play()
	minBtn.Text = collapsed and "+" or "–"
end)
closeBtn.MouseButton1Click:Connect(function()
	if _G.__MAGICEVO_SUITE and _G.__MAGICEVO_SUITE.unload then _G.__MAGICEVO_SUITE.unload() end
end)

----------------------------------------------------------------------
-- Unload
----------------------------------------------------------------------

local function unload()
	state.run = false
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
	task.wait(0.1)
	pcall(function() gui:Destroy() end)
	_G.__MAGICEVO_SUITE = nil
end

_G.__MAGICEVO_SUITE = { unload = unload, S = S }

----------------------------------------------------------------------
-- Старт
----------------------------------------------------------------------

setupAntiAfk()
setupClaims()
startLoops()
Suite.setStatus("Фарм запущен ✓")
