if _G.__TNT_INC and _G.__TNT_INC.unload then pcall(_G.__TNT_INC.unload) end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer

local function safeRequire(inst)
	if not inst then return nil end
	local ok, mod = pcall(require, inst)
	return ok and mod or nil
end

local Modules = RS:WaitForChild("Modules")
local Constants = Modules:WaitForChild("Constants")
local Utils = Modules:WaitForChild("Utils")
local External = Modules:WaitForChild("ExternalModules")
local PlayerModules = LP:WaitForChild("PlayerScripts"):WaitForChild("Modules")

local Packets = safeRequire(Constants:WaitForChild("Packets"))
local DM = safeRequire(PlayerModules:WaitForChild("DataManagerClient"))
local G = safeRequire(External:WaitForChild("GammaNum"))
local C = safeRequire(Utils:WaitForChild("CalcUtils"))
local UU = safeRequire(Utils:WaitForChild("UpgradeUtils"))
local PC = safeRequire(Constants:WaitForChild("ProgressionConfig"))
local BM = safeRequire(PlayerModules:WaitForChild("BlockManager"))

if not (Packets and DM and G and C and UU and PC) then
	warn("TNT Incremental: failed to load core modules, aborting.")
	return
end

pcall(function() DM.waitForLoaded() end)
local P = DM.Profile

local MC
local function miningConfig()
	if not MC then MC = safeRequire(Constants:FindFirstChild("MiningConfig")) end
	return MC
end
local TM
local function ticketManager()
	if not TM then TM = safeRequire(PlayerModules:FindFirstChild("TicketManager")) end
	return TM
end

local ZERO = G.fromNumber(0)
local ONE = G.fromNumber(1)

local function stat(name)
	local ok, v = pcall(C.getStat, P, name)
	if ok and v then return v end
	return ZERO
end

local function affordBuf(priceBuf, currencyName)
	if not priceBuf then return false end
	return G.lte(priceBuf, stat(currencyName))
end

local S = {
	cashRate = 5,
	enableCash = true,
	enableBlockMastery = true,
	enableSweep = true,
	enablePrestige = true,
	enableMining = true,
	enablePassives = true,
	enableClaims = true,
	enableAntiAfk = true,
}

local running = true
local conns = {}
local function track(c) conns[#conns + 1] = c; return c end

local UPG = UU.getUpgradeTable()
local HEAT = {
	HeatMoreHeat = true, HeatMoreChickens = true, HeatMoreDamage = true,
	HeatMoreCoins = true, HeatMoreCrystals = true, HeatMoreAge = true, HeatBetterValue = true,
}
local upgCur, upgCat = {}, {}
for name in pairs(UPG) do
	local okc, cur = pcall(C.getUpgCurrency, name)
	upgCur[name] = okc and cur or nil
	local okk, cat = pcall(C.getUpgCat, name)
	upgCat[name] = okk and cat or nil
end

local ORE_KEYS = { Coal = true, Iron = true, Gold = true, Rubies = true, Emeralds = true, Crystals = true }
local RARITY = { "Transcendent", "Cosmic", "Celestial", "Divine", "Ancient", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }
local function rarityRank(id)
	for i, r in ipairs(RARITY) do
		if string.sub(id, 1, #r) == r then return i end
	end
	return 99
end

local function loop(interval, fn)
	track(true)
	task.spawn(function()
		while running do
			if not running then break end
			pcall(fn)
			local wait = interval
			if type(interval) == "function" then
				local ok, v = pcall(interval)
				wait = ok and v or 0.5
			end
			task.wait(wait)
		end
	end)
end

if P.Tier == 0 then
	for _ = 1, 60 do
		if P.Tier > 0 or not running then break end
		pcall(function()
			if G.gte(P.Cash, PC.Tiers[1].Price) then
				Packets.TierUp:Fire()
			else
				local box = workspace:FindFirstChild("TNTBox")
				local sp = box and box:FindFirstChild("TNTSpawn")
				if sp and BM then
					local idx = {}
					for i, b in pairs(BM.getBlocks()) do if b.part then idx[#idx + 1] = i end end
					if #idx > 0 then Packets.TNTExplode:Fire(idx, sp.Position) end
				end
			end
		end)
		task.wait(0.2)
	end
end

loop(function() return 1 / math.clamp(S.cashRate, 1, 8) end, function()
	if not S.enableCash then return end
	local box = workspace:FindFirstChild("TNTBox")
	local spawn = box and box:FindFirstChild("TNTSpawn")
	if not (spawn and BM) then return end
	local idx = {}
	for i, b in pairs(BM.getBlocks()) do
		if b.part then idx[#idx + 1] = i end
	end
	if #idx > 0 then
		Packets.TNTExplode:Fire(idx, spawn.Position)
	end
end)

loop(1.6, function()
	if not S.enableBlockMastery then return end
	pcall(function() Packets.SpawnTnt:Fire() end)
end)

loop(0.7, function()
	if not S.enableSweep then return end
	for name in pairs(UPG) do
		pcall(function()
			local lvl = C.getUpgLvl(P, name)
			local cap = C.getUpgLvlCap(P, name)
			if not (lvl and cap) or lvl >= cap then return end
			local price = C.getUpgPrice(P, name)
			if HEAT[name] then
				if affordBuf(price, "Heat") then Packets.AddHeat:Fire(name) end
			elseif name == "Smelters" then
				if affordBuf(price, "TreeCrystals") then Packets.BuySmelter:Fire(true) end
			else
				local cat = upgCat[name]
				local reach = true
				if cat == "HexagonTree" then
					reach = C.canReachHexagonUpgrade(P, name)
				elseif cat == "MiningTree" then
					reach = C.canReachMiningUpgrade(P, name)
				end
				if reach and not C.isUpgradeLocked(P, name) then
					local cur = upgCur[name] or C.getUpgCurrency(name)
					if affordBuf(price, cur) then Packets.BuyUpgrade:Fire(name, true) end
				end
			end
		end)
	end
end)

loop(1.0, function()
	if not S.enablePrestige then return end

	local didReset = false
	pcall(function()
		local nt = PC.Tiers[P.Tier + 1]
		if nt and G.gte(P.Cash, nt.Price) then
			local okReq = true
			if nt.Requirements and nt.Requirements.RunesOpened then
				okReq = G.toNumber(C.getTotalOpenedRunes(P)) >= nt.Requirements.RunesOpened
			end
			if okReq then Packets.TierUp:Fire(); didReset = true end
		end
	end)

	if not didReset then
		pcall(function()
			if P.Ascension < 1 and P.Tier >= 6 then
				local na = PC.Ascensions[P.Ascension + 1]
				if na and G.gte(P.Cash, na.Price) then
					Packets.Ascend:Fire()
					didReset = true
				end
			end
		end)
	end

	local milestone
	pcall(function()
		if P.Tier < 6 then
			local nt = PC.Tiers[P.Tier + 1]
			if nt then
				local okReq = (not nt.Requirements) or (not nt.Requirements.RunesOpened) or (G.toNumber(C.getTotalOpenedRunes(P)) >= nt.Requirements.RunesOpened)
				if okReq then milestone = nt.Price end
			end
		elseif P.Ascension < 1 then
			local na = PC.Ascensions[1]
			if na then milestone = na.Price end
		end
	end)
	local hoard = false
	if milestone then
		pcall(function() hoard = G.gte(G.mul(P.Cash, 1000), milestone) end)
	end

	if not didReset and not hoard then
		pcall(function()
			local g = C.getRebirthAmt(P)
			if g and G.gte(g, G.max(ONE, stat("Rebirths"))) then
				Packets.Rebirth:Fire()
				didReset = true
			end
		end)
	end
	if not didReset and not hoard and P.Tier >= 3 then
		pcall(function()
			local gain = G.mul(G.div(P.Cash, PC.TreeCrystalCost), C.getTreeCrystalMulti(P))
			if not G.isZero(gain) and G.gte(gain, G.max(ONE, stat("TreeCrystals"))) then
				Packets.ConvertCrystals:Fire()
			end
		end)
	end

	pcall(function()
		if C.getCobwebAmt(P) then Packets.Cobweb:Fire() end
	end)
	pcall(function()
		local tw = PC.Timewarps[P.Timewarp + 1]
		if tw and G.gte(stat("Age"), tw.Price) then Packets.TimewarpUp:Fire() end
	end)
end)

local depleted = {}
pcall(function()
	track(Packets.OreDestroyed.OnClientEvent:Connect(function(id) depleted[id] = true end))
	track(Packets.OreRespawned.OnClientEvent:Connect(function(id) depleted[id] = nil end))
end)

local function pickaxeAffordable(cost)
	for k, v in pairs(cost) do
		local need = (type(v) == "number") and v or G.toNumber(v)
		local have
		if ORE_KEYS[k] then
			have = (P.Mining and P.Mining[k]) or 0
			if type(have) ~= "number" then have = G.toNumber(have) end
		else
			have = G.toNumber(stat(k))
		end
		if have < need then return false end
	end
	return true
end

loop(function()
	local cd = 0.8
	pcall(function() cd = math.max(0.1, C.getSwingCooldown(P)) end)
	return cd
end, function()
	if not S.enableMining then return end
	local mc = miningConfig()
	local m = P.Mining
	if not (mc and m) then return end

	pcall(function()
		local nx = mc.Pickaxes[(m.Pickaxe or 0) + 1]
		if nx and nx.Cost and pickaxeAffordable(nx.Cost) then
			Packets.UpgradePickaxe:Fire()
		end
	end)

	if (m.Pickaxe or 0) < 1 then return end
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local nodes = workspace:FindFirstChild("OreNodes")
	if not (hrp and nodes) then return end

	local bp = (mc.Pickaxes[m.Pickaxe] and mc.Pickaxes[m.Pickaxe].BreakingPower) or 0
	local dmg = 0
	pcall(function() dmg = G.toNumber(C.getPickaxeDamage(P)) end)

	local best, bestDist
	for _, nd in ipairs(nodes:GetChildren()) do
		local def = mc.Nodes[nd.Name]
		if def and not depleted[nd.Name] and bp >= (def.RequiredBreakingPower or 0) then
			local ot = def.oreType
			local targeted = (not ot) or (m.TargetOres and m.TargetOres["Target" .. ot] ~= false)
			local clearable = (not def.MaxHP) or (dmg > 0 and (def.MaxHP / dmg) <= 15)
			if targeted and clearable then
				local cf = nd:GetBoundingBox()
				local d = (cf.Position - hrp.Position).Magnitude
				if not bestDist or d < bestDist then best, bestDist = nd, d end
			end
		end
	end
	if best then
		local cf = best:GetBoundingBox()
		hrp.CFrame = cf + Vector3.new(0, 3, 0)
		Packets.DamageOre:Fire(best.Name)
	end
end)

loop(25, function()
	if not S.enableMining then return end
	local m = P.Mining
	if not m then return end
	pcall(function()
		local nd = PC.Depth[(m.Depth or 0) + 1]
		if nd and affordBuf(nd.Price, "Coins") then Packets.DoDepth:Fire() end
	end)
	pcall(function()
		if (m.Pickaxe or 0) >= 1 then Packets.SellAllOres:Fire() end
	end)
	pcall(function()
		if G.toNumber(C.getAvailableCookedChickens(P)) > 0 then Packets.CookChickens:Fire() end
	end)
end)

pcall(function() Packets.SetPassiveRollBulk:Fire(C.getMaxPassiveBulk(P)) end)
pcall(function()
	if P.AutoDeleteRarities and P.AutoDeleteRarities.Uncommon ~= true then
		Packets.ToggleAutoDeleteRarity:Fire("Uncommon")
	end
end)

loop(0.5, function()
	if not S.enablePassives then return end
	pcall(function()
		local bulk = math.clamp(P.PassiveRollBulk or 1, 1, C.getMaxPassiveBulk(P))
		if G.gte(stat("Keys"), G.fromNumber(bulk)) then
			Packets.RollPassive:Fire()
		end
	end)
	pcall(function()
		local maxEq = C.getMaxEquipped(P) or 1
		local equipped = P.EquippedPassives or {}
		local ec = 0
		local worst, worstRank
		for id, v in pairs(equipped) do
			if v then
				ec = ec + 1
				local r = rarityRank(id)
				if not worstRank or r > worstRank then worst, worstRank = id, r end
			end
		end
		local bestU, bestRank
		for id, v in pairs(P.Passives or {}) do
			if v.Unlocked and not equipped[id] then
				local r = rarityRank(id)
				if not bestRank or r < bestRank then bestU, bestRank = id, r end
			end
		end
		if not bestU then return end
		if ec < maxEq then
			Packets.EquipPassive:Fire(bestU)
		elseif worst and bestRank < worstRank then
			Packets.EquipPassive:Fire(worst)
			task.wait(0.15)
			Packets.EquipPassive:Fire(bestU)
		end
	end)
end)

task.spawn(function()
	for _ = 1, 3 do
		if not running or P.ClaimedFreeAutoclicker then break end
		pcall(function() Packets.ClaimFreeAutocliker:Fire() end)
		task.wait(1)
	end
	pcall(function()
		if P.ClaimedFreeAutoclicker then Packets.ChangeSetting:Fire("Autoclicker", true) end
	end)
	for _, n in ipairs({ "Joxan_exe", "SharkqPL", "Onyrx1" }) do
		pcall(function() Packets.ClaimFollow:Fire(n) end)
		task.wait(0.3)
	end
	pcall(function() if not P.ClaimedFollowJoxan then Packets.ClaimFollowGemJoxan:Fire() end end)
	pcall(function() if not P.ClaimedFollowSharkq then Packets.ClaimFollowGemSharkq:Fire() end end)
	pcall(function() if not P.ClaimedNotifications then Packets.ClaimNotifications:Fire() end end)
end)

local bought = {}
local TICKET_PRIORITY = {
	{ "AutoGemCollect", 63 }, { "AutoOreMine", 108 }, { "Walkspeed", 27 }, { "StarterPack", 36 },
	{ "Super_Miner", 405 }, { "PassiveBulk_Pass", 180 }, { "PassiveEquip_Pass", 450 },
	{ "Super_Lucky", 180 }, { "PassiveLuck_Pass", 270 }, { "VIP", 360 }, { "Ultra_Lucky", 450 }, { "Stat_Master", 720 },
}
local BOOST_PASS = { Super_Lucky = true, Ultra_Lucky = true, PassiveLuck_Pass = true, VIP = true, Stat_Master = true }
local KEYS_BUNDLES = { { "Keys_500", 720 }, { "Keys_100", 180 }, { "Keys_10", 27 } }

loop(8, function()
	if not S.enableClaims then return end
	pcall(function()
		if (workspace:GetServerTimeNow() - (P.LastDailyGemClaim or 0)) >= 86400 then
			Packets.ClaimDailyGem:Fire()
		end
	end)
	pcall(function()
		local tm = ticketManager()
		local t = math.floor((tm and tm.getTickets()) or P.Tickets or 0)
		local p2w = false
		pcall(function() p2w = C.isP2WDisabled(P) end)
		local target
		for _, e in ipairs(TICKET_PRIORITY) do
			local id, cost = e[1], e[2]
			local owned = P.Gamepasses and P.Gamepasses[id]
			if not bought[id] and not owned and t >= cost and not (p2w and BOOST_PASS[id]) then
				target = id
				break
			end
		end
		if target then
			local ok = Packets.PurchaseWithTickets:Fire(target)
			if ok then bought[target] = true end
		else
			for _, e in ipairs(KEYS_BUNDLES) do
				if t >= e[2] then
					Packets.PurchaseWithTickets:Fire(e[1])
					break
				end
			end
		end
	end)
end)

pcall(function()
	local g = { VFX = false, LowGraphics = true, ExplosionSounds = false, CurrencyAnimation = false, PickupAnimation = false, HideOthers = true, OthersOverhead = false, Music = 0, Sfx = 0 }
	for k, v in pairs(g) do pcall(function() Packets.ChangeSetting:Fire(k, v) end) end
	pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
	pcall(function() UserSettings():GetService("UserGameSettings").SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1 end)
	pcall(function()
		for _, e in ipairs(game:GetService("Lighting"):GetDescendants()) do
			if e:IsA("PostEffect") then e.Enabled = false end
		end
	end)
end)

if S.enableAntiAfk then
	track(LP.Idled:Connect(function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end))
end

local palette = {
	bg = Color3.fromRGB(17, 16, 25),
	panel = Color3.fromRGB(25, 23, 36),
	row = Color3.fromRGB(33, 30, 47),
	stroke = Color3.fromRGB(58, 52, 84),
	text = Color3.fromRGB(236, 233, 246),
	dim = Color3.fromRGB(150, 144, 172),
	on = Color3.fromRGB(140, 99, 255),
	off = Color3.fromRGB(62, 57, 82),
	good = Color3.fromRGB(86, 214, 156),
}

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = p
	return c
end
local function stroke(p, col, th)
	local s = Instance.new("UIStroke")
	s.Color = col or palette.stroke
	s.Thickness = th or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end
local function pad(p, v)
	local u = Instance.new("UIPadding")
	u.PaddingTop = UDim.new(0, v); u.PaddingBottom = UDim.new(0, v)
	u.PaddingLeft = UDim.new(0, v); u.PaddingRight = UDim.new(0, v)
	u.Parent = p
	return u
end

local gui = Instance.new("ScreenGui")
gui.Name = "UI_" .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
local guiParent = CoreGui
pcall(function() if gethui then guiParent = gethui() end end)
gui.Parent = guiParent

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(300, 384)
main.Position = UDim2.new(0.5, -150, 0.5, -192)
main.BackgroundColor3 = palette.bg
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
corner(main, 14)
stroke(main, palette.stroke, 1.4)

local glow = Instance.new("UIGradient")
glow.Rotation = 90
glow.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 26, 46)),
	ColorSequenceKeypoint.new(1, palette.bg),
})
glow.Parent = main

local topbar = Instance.new("Frame")
topbar.Size = UDim2.new(1, 0, 0, 46)
topbar.BackgroundColor3 = palette.panel
topbar.BorderSizePixel = 0
topbar.Parent = main
corner(topbar, 14)
local topFix = Instance.new("Frame")
topFix.Size = UDim2.new(1, 0, 0, 16)
topFix.Position = UDim2.new(0, 0, 1, -16)
topFix.BackgroundColor3 = palette.panel
topFix.BorderSizePixel = 0
topFix.Parent = topbar

local accent = Instance.new("Frame")
accent.Size = UDim2.new(1, 0, 0, 2)
accent.Position = UDim2.new(0, 0, 1, 0)
accent.BorderSizePixel = 0
accent.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
accent.Parent = topbar
local ag = Instance.new("UIGradient")
ag.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 99, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(99, 102, 241)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(56, 189, 248)),
})
ag.Parent = accent

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 0)
title.Size = UDim2.new(1, -90, 1, 0)
title.Font = Enum.Font.GothamBold
title.Text = "TNT Incremental"
title.TextSize = 16
title.TextColor3 = palette.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = topbar

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.fromOffset(16, 24)
subtitle.Size = UDim2.new(1, -90, 0, 14)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "auto progression"
subtitle.TextSize = 11
subtitle.TextColor3 = palette.dim
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = topbar

local function topButton(txt, x, col)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(28, 28)
	b.Position = UDim2.new(1, x, 0, 9)
	b.BackgroundColor3 = palette.row
	b.Text = txt
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = col or palette.text
	b.AutoButtonColor = true
	b.Parent = topbar
	corner(b, 8)
	stroke(b, palette.stroke, 1)
	return b
end
local closeBtn = topButton("\u{2715}", -36, Color3.fromRGB(255, 120, 130))
local minBtn = topButton("\u{2212}", -68, palette.text)

local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 1, -46)
content.Position = UDim2.fromOffset(0, 46)
content.BackgroundTransparency = 1
content.Parent = main

local status = Instance.new("Frame")
status.Size = UDim2.new(1, -24, 0, 64)
status.Position = UDim2.fromOffset(12, 10)
status.BackgroundColor3 = palette.panel
status.BorderSizePixel = 0
status.Parent = content
corner(status, 10)
stroke(status, palette.stroke, 1)

local statText = Instance.new("TextLabel")
statText.BackgroundTransparency = 1
statText.Size = UDim2.new(1, 0, 1, 0)
statText.Font = Enum.Font.GothamMedium
statText.TextSize = 12
statText.TextColor3 = palette.text
statText.TextXAlignment = Enum.TextXAlignment.Left
statText.TextYAlignment = Enum.TextYAlignment.Center
statText.RichText = true
statText.Text = ""
statText.Parent = status
pad(statText, 10)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 1, -150)
list.Position = UDim2.fromOffset(12, 82)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 3
list.ScrollBarImageColor3 = palette.on
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = content
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local function toggleRow(label, key)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 34)
	row.BackgroundColor3 = palette.row
	row.BorderSizePixel = 0
	row.Parent = list
	corner(row, 8)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(12, 0)
	name.Size = UDim2.new(1, -64, 1, 0)
	name.Font = Enum.Font.GothamMedium
	name.Text = label
	name.TextSize = 13
	name.TextColor3 = palette.text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local sw = Instance.new("TextButton")
	sw.Size = UDim2.fromOffset(40, 20)
	sw.Position = UDim2.new(1, -50, 0.5, -10)
	sw.BackgroundColor3 = S[key] and palette.on or palette.off
	sw.Text = ""
	sw.AutoButtonColor = false
	sw.Parent = row
	corner(sw, 10)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = S[key] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = sw
	corner(knob, 8)

	sw.MouseButton1Click:Connect(function()
		S[key] = not S[key]
		TweenService:Create(sw, TweenInfo.new(0.15), { BackgroundColor3 = S[key] and palette.on or palette.off }):Play()
		TweenService:Create(knob, TweenInfo.new(0.15), { Position = S[key] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8) }):Play()
	end)
end

toggleRow("Cash Engine (TNT)", "enableCash")
toggleRow("Block Mastery feeder", "enableBlockMastery")
toggleRow("Auto Upgrades", "enableSweep")
toggleRow("Auto Prestige", "enablePrestige")
toggleRow("Auto Mining", "enableMining")
toggleRow("Auto Passives", "enablePassives")
toggleRow("Claims & Tickets", "enableClaims")
toggleRow("Anti-AFK", "enableAntiAfk")

local rateRow = Instance.new("Frame")
rateRow.Size = UDim2.new(1, -4, 0, 44)
rateRow.BackgroundColor3 = palette.row
rateRow.BorderSizePixel = 0
rateRow.Parent = list
corner(rateRow, 8)
local rateLbl = Instance.new("TextLabel")
rateLbl.BackgroundTransparency = 1
rateLbl.Position = UDim2.fromOffset(12, 4)
rateLbl.Size = UDim2.new(1, -24, 0, 16)
rateLbl.Font = Enum.Font.GothamMedium
rateLbl.TextSize = 12
rateLbl.TextColor3 = palette.text
rateLbl.TextXAlignment = Enum.TextXAlignment.Left
rateLbl.Text = "Cash rate: " .. S.cashRate .. "/s"
rateLbl.Parent = rateRow
local track2 = Instance.new("Frame")
track2.Size = UDim2.new(1, -24, 0, 6)
track2.Position = UDim2.fromOffset(12, 28)
track2.BackgroundColor3 = palette.off
track2.BorderSizePixel = 0
track2.Parent = rateRow
corner(track2, 3)
local fill = Instance.new("Frame")
fill.Size = UDim2.new((S.cashRate - 1) / 7, 0, 1, 0)
fill.BackgroundColor3 = palette.on
fill.BorderSizePixel = 0
fill.Parent = track2
corner(fill, 3)
local knob2 = Instance.new("TextButton")
knob2.Size = UDim2.fromOffset(14, 14)
knob2.Position = UDim2.new((S.cashRate - 1) / 7, -7, 0.5, -7)
knob2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob2.Text = ""
knob2.AutoButtonColor = false
knob2.Parent = track2
corner(knob2, 7)

local draggingRate = false
local function setRate(px)
	local rel = math.clamp((px - track2.AbsolutePosition.X) / track2.AbsoluteSize.X, 0, 1)
	S.cashRate = math.floor(rel * 7 + 0.5) + 1
	rateLbl.Text = "Cash rate: " .. S.cashRate .. "/s"
	fill.Size = UDim2.new((S.cashRate - 1) / 7, 0, 1, 0)
	knob2.Position = UDim2.new((S.cashRate - 1) / 7, -7, 0.5, -7)
end
knob2.MouseButton1Down:Connect(function() draggingRate = true end)
track2.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then setRate(i.Position.X) end
end)
track(UserInputService.InputChanged:Connect(function(i)
	if draggingRate and i.UserInputType == Enum.UserInputType.MouseMovement then setRate(i.Position.X) end
end))
track(UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then draggingRate = false end
end))

local codeRow = Instance.new("Frame")
codeRow.Size = UDim2.new(1, -24, 0, 34)
codeRow.Position = UDim2.new(0, 12, 1, -58)
codeRow.BackgroundColor3 = palette.row
codeRow.BorderSizePixel = 0
codeRow.Parent = content
corner(codeRow, 8)
local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(1, -78, 1, -8)
codeBox.Position = UDim2.fromOffset(8, 4)
codeBox.BackgroundColor3 = palette.bg
codeBox.Font = Enum.Font.Gotham
codeBox.PlaceholderText = "promo code"
codeBox.Text = ""
codeBox.TextSize = 12
codeBox.TextColor3 = palette.text
codeBox.PlaceholderColor3 = palette.dim
codeBox.ClearTextOnFocus = false
codeBox.Parent = codeRow
corner(codeBox, 6)
pad(codeBox, 6)
local redeem = Instance.new("TextButton")
redeem.Size = UDim2.fromOffset(58, 26)
redeem.Position = UDim2.new(1, -64, 0.5, -13)
redeem.BackgroundColor3 = palette.on
redeem.Font = Enum.Font.GothamBold
redeem.Text = "Redeem"
redeem.TextSize = 12
redeem.TextColor3 = Color3.fromRGB(255, 255, 255)
redeem.Parent = codeRow
corner(redeem, 6)
redeem.MouseButton1Click:Connect(function()
	local code = codeBox.Text
	if code and #code > 0 then
		pcall(function() Packets.RedeemCode:Fire(code) end)
		pcall(function() Packets.ClaimDiscordCode:Fire(code) end)
		codeBox.Text = ""
	end
end)

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -24, 0, 30)
unloadBtn.Position = UDim2.new(0, 12, 1, -38)
unloadBtn.BackgroundColor3 = Color3.fromRGB(48, 28, 38)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.Text = "Unload"
unloadBtn.TextSize = 13
unloadBtn.TextColor3 = Color3.fromRGB(255, 120, 130)
unloadBtn.Parent = content
corner(unloadBtn, 8)
stroke(unloadBtn, Color3.fromRGB(120, 50, 64), 1)

local dragging, dragStart, startPos
topbar.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = i.Position
		startPos = main.Position
	end
end)
track(UserInputService.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dragStart
		main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end))
topbar.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	content.Visible = not minimized
	TweenService:Create(main, TweenInfo.new(0.2), { Size = minimized and UDim2.fromOffset(300, 46) or UDim2.fromOffset(300, 384) }):Play()
end)

local function fmt(buf)
	local ok, s = pcall(G.toSuffix, buf)
	return ok and s or "0"
end
loop(0.4, function()
	local tier = P.Tier or 0
	local asc = P.Ascension or 0
	local rps = 0
	pcall(function() rps = G.toNumber(C.getRPS(P)) end)
	statText.Text = string.format(
		'<font color="#9c84ff">Cash</font>  %s     <font color="#9c84ff">Reb</font>  %s\n<font color="#56d6f0">Tier</font>  %d     <font color="#56d6f0">Asc</font>  %d     <font color="#56d6f0">RPS</font>  %.1f\n<font color="#8c63ff">Tickets</font>  %d     <font color="#8c63ff">Keys</font>  %s',
		fmt(P.Cash), fmt(stat("Rebirths")), tier, asc, rps,
		math.floor((P.Tickets) or 0), fmt(stat("Keys"))
	)
end)

local raceBar = Instance.new("Frame")
raceBar.AnchorPoint = Vector2.new(0.5, 0)
raceBar.Position = UDim2.new(0.5, 0, 0, 8)
raceBar.Size = UDim2.fromOffset(460, 48)
raceBar.BackgroundColor3 = palette.bg
raceBar.BorderSizePixel = 0
raceBar.Active = true
raceBar.Parent = gui
corner(raceBar, 10)
stroke(raceBar, palette.stroke, 1.2)

local raceTitle = Instance.new("TextLabel")
raceTitle.BackgroundTransparency = 1
raceTitle.Position = UDim2.fromOffset(14, 5)
raceTitle.Size = UDim2.new(1, -28, 0, 14)
raceTitle.Font = Enum.Font.GothamBold
raceTitle.TextSize = 11
raceTitle.TextColor3 = palette.text
raceTitle.TextXAlignment = Enum.TextXAlignment.Left
raceTitle.Text = "TOP-100 CASH RACE"
raceTitle.Parent = raceBar

local racePct = Instance.new("TextLabel")
racePct.BackgroundTransparency = 1
racePct.Position = UDim2.fromOffset(14, 5)
racePct.Size = UDim2.new(1, -28, 0, 14)
racePct.Font = Enum.Font.GothamBold
racePct.TextSize = 11
racePct.TextColor3 = palette.on
racePct.TextXAlignment = Enum.TextXAlignment.Right
racePct.Text = "--"
racePct.Parent = raceBar

local raceTrack = Instance.new("Frame")
raceTrack.Position = UDim2.fromOffset(14, 23)
raceTrack.Size = UDim2.new(1, -28, 0, 9)
raceTrack.BackgroundColor3 = palette.off
raceTrack.BorderSizePixel = 0
raceTrack.Parent = raceBar
corner(raceTrack, 4)

local raceFill = Instance.new("Frame")
raceFill.Size = UDim2.new(0, 0, 1, 0)
raceFill.BackgroundColor3 = palette.on
raceFill.BorderSizePixel = 0
raceFill.Parent = raceTrack
corner(raceFill, 4)
local fillGrad = Instance.new("UIGradient")
fillGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 99, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(99, 102, 241)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(56, 189, 248)),
})
fillGrad.Parent = raceFill

local raceInfo = Instance.new("TextLabel")
raceInfo.BackgroundTransparency = 1
raceInfo.Position = UDim2.fromOffset(14, 34)
raceInfo.Size = UDim2.new(1, -28, 0, 12)
raceInfo.Font = Enum.Font.Gotham
raceInfo.TextSize = 10
raceInfo.TextColor3 = palette.dim
raceInfo.TextXAlignment = Enum.TextXAlignment.Left
raceInfo.Text = "reading leaderboard..."
raceInfo.Parent = raceBar

local function orderOf(buf)
	local ok, s = pcall(G.toScientific, buf)
	if not ok or type(s) ~= "string" then return 0 end
	local e = s:match("[eE]([%+%-]?%d+)")
	if e then return tonumber(e) or 0 end
	local n = tonumber(s)
	return (n and n > 0) and math.log10(n) or 0
end

local function top100Threshold()
	local lb = workspace:FindFirstChild("Leaderboards")
	local board = lb and lb:FindFirstChild("CashLeadeboard")
	if not board then return nil end
	local minVal, minStr
	for _, d in ipairs(board:GetDescendants()) do
		if d:IsA("TextLabel") then
			local t = d.Text
			if t and #t >= 2 and t:sub(1, 1):match("%d") and t:sub(-1):match("%a") then
				local ok, val = pcall(G.fromSuffix, t)
				if ok and val and not G.isZero(val) then
					if not minVal or G.lt(val, minVal) then minVal, minStr = val, t end
				end
			end
		end
	end
	return minVal, minStr
end

local peakOrder = 0
loop(2, function()
	local co = orderOf(P.Cash)
	if co > peakOrder then peakOrder = co end
	local thr, thrStr = top100Threshold()
	if not thr then
		raceInfo.Text = "leaderboard loading..."
		racePct.Text = "--"
		return
	end
	local to = orderOf(thr)
	local useOrder = math.max(co, peakOrder)
	local prog = (to > 0) and math.clamp(useOrder / to, 0, 1) or 0
	TweenService:Create(raceFill, TweenInfo.new(0.4), { Size = UDim2.new(prog, 0, 1, 0) }):Play()
	racePct.Text = string.format("%.1f%%", prog * 100)
	if useOrder >= to then
		raceInfo.Text = "IN TOP-100!   peak x10^" .. string.format("%.0f", useOrder) .. "   |   #100 = " .. (thrStr or "?")
		racePct.TextColor3 = palette.good
	else
		raceInfo.Text = "you " .. fmt(P.Cash) .. "   |   #100 " .. (thrStr or "?") .. "   |   need x10^" .. string.format("%.0f", to - useOrder) .. " more"
		racePct.TextColor3 = palette.on
	end
end)

local function unload()
	running = false
	for _, c in ipairs(conns) do
		if typeof(c) == "RBXScriptConnection" then pcall(function() c:Disconnect() end) end
	end
	conns = {}
	pcall(function() gui:Destroy() end)
	_G.__TNT_INC = nil
end
closeBtn.MouseButton1Click:Connect(unload)
unloadBtn.MouseButton1Click:Connect(unload)

_G.__TNT_INC = { unload = unload }
