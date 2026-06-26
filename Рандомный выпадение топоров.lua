local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local RollNet = require(PlayerScripts.Roll.Network)
local RollStats = require(PlayerScripts.State.RollStats)
local PlayerData = require(PlayerScripts.State.PlayerData)
local BagNet = require(PlayerScripts.Bag.Network)
local ItemsNet = require(PlayerScripts.Items.Network)
local ZoneNet = require(PlayerScripts.Zone.Network)
local SkillTreeNet = require(PlayerScripts.SkillTree.Network)
local RebirthNet = require(PlayerScripts.Rebirth.Network)
local QuestsNet = require(PlayerScripts.Quests.Network)
local SocialNet = require(PlayerScripts.SocialReward.Network)
local CodesNet = require(PlayerScripts.Codes.Network)
local AxeIndexNet = require(PlayerScripts.Axe.IndexRewardsNetwork)
local ClaimableState = require(PlayerScripts.Index.ClaimableState)

local AxeData = require(ReplicatedStorage.Config.AxeData)
local ZoneData = require(ReplicatedStorage.Config.ZoneData)
local SkillTreeData = require(ReplicatedStorage.Config.SkillTreeData)
local SkillTreeState = require(ReplicatedStorage.SkillTree.State)
local ZoneState = require(ReplicatedStorage.Zone.State)
local RebirthState = require(ReplicatedStorage.Rebirth.State)
PlayerData.bind()
RollStats.bind()

if _G.__AcrylicUnload then pcall(_G.__AcrylicUnload) end
do
	local containers = { game:GetService("CoreGui"), LocalPlayer:FindFirstChild("PlayerGui") }
	local ok, hidden = pcall(function() return gethui() end)
	if ok and hidden then table.insert(containers, hidden) end
	for _, c in ipairs(containers) do
		if c then
			local existing = c:FindFirstChild("AcrylicDock")
			while existing do existing:Destroy() existing = c:FindFirstChild("AcrylicDock") end
		end
	end
end

local state = {
	chop = false, roll = false, equip = false, upgrade = false,
	zone = false, claim = false, potion = false, rebirth = false,
	logsPerSec = 0, rolls = 0,
}

local config = { clusterRadius = 5, holdHeight = 3, rebirthBuffer = 1 }

local FX_OFF = {
	"damageNumbersOn", "hitEffectsOn", "hitSoundsOn", "destroySoundsOn",
	"destroyDebrisOn", "destroyBreakOn", "currencyFlyoutsOn", "rollConfettiOn",
}

local UPGRADE_PRIORITY = {
	maxEquippedAxes = 1, logsMult = 2, reelSpeed = 3, spinSpeed = 4,
	doubleReelChance = 5, critChance = 6, critMultiplier = 7,
	doubleHitChance = 8, doubleHitUnlock = 8, luck = 9, collectRadius = 10,
	maxEquippedBees = 11, luckyRollChance = 11, honeyMult = 13, walkSpeed = 14,
}

local POTIONS = { "reel_speed_potion_2x_15m", "super_luck_potion_3x_15m", "luck_potion_2x_15m" }
local CODES = { "SORRY4FUSION", "SUMMERSOON", "BIGPLANS", "SOMETHINGISCOMING", "NOTIFY4EVENT" }
local AXE_FILTERS = { "base", "shiny", "frozen", "molten", "toxic", "galactic", "nimbus" }

local trove = {}
local function track(conn) trove[#trove + 1] = conn return conn end

local function num(key) local ok, v = pcall(function() return PlayerData.number(key).get() end) return ok and type(v) == "number" and v or nil end
local function tbl(key) local ok, v = pcall(function() return PlayerData.table(key).get() end) return ok and type(v) == "table" and v or nil end
local function setBool(key, value) pcall(function() PlayerData.bool(key).set(value) end) end

local function rootPart()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return (root and root:IsA("BasePart")) and root or nil
end

local function equippedAxeCount()
	local axes, total = tbl("axes"), 0
	if axes then for _, e in pairs(axes) do if type(e) == "table" then total = total + (tonumber(e.equippedCount) or (e.equipped and 1 or 0)) end end end
	return total
end

-- ============ anti-lag ============
local function applyAntiLag()
	for _, k in ipairs(FX_OFF) do setBool(k, false) end
	setBool("lowGraphicsOn", true)
end

-- ============ chop positioning ============
local function highestZoneTrees()
	local zonesFolder = Workspace:FindFirstChild("Zones")
	if not zonesFolder then return nil end
	local zoneId = ZoneState.highestUnlockedZoneId(ZoneState.readUnlocks(tbl("zones")))
	for _, zf in ipairs(zonesFolder:GetChildren()) do
		local trees = zf:FindFirstChild("Trees")
		if trees and #trees:GetChildren() > 0 then
			local sample = trees:FindFirstChildWhichIsA("Model")
			if sample and ZoneData.zoneForInstance(sample) == zoneId then return trees end
		end
	end
	local folder = zonesFolder:FindFirstChild("Zone" .. ZoneData.zoneIndex(zoneId))
	return folder and folder:FindFirstChild("Trees")
end

local function densestCluster(folder)
	local pts = {}
	for _, m in ipairs(folder:GetChildren()) do
		if CollectionService:HasTag(m, "Choppable") then
			local ok, p = pcall(function() return m:GetPivot().Position end)
			if ok then pts[#pts + 1] = p end
		end
	end
	if #pts == 0 then return nil end
	local rsq = config.clusterRadius * config.clusterRadius
	local best, bestCount = pts[1], -1
	for i = 1, #pts do
		local count, pi = 0, pts[i]
		for j = 1, #pts do
			local d = pts[j] - pi
			if d.X * d.X + d.Z * d.Z <= rsq then count = count + 1 end
		end
		if count > bestCount then bestCount = count best = pi end
	end
	return best
end

-- ============ feature loops ============
task.spawn(function()
	local target, lastPick, lastFx = nil, 0, 0
	while trove ~= nil do
		if not state.chop then target = nil task.wait(0.2)
		else
			local root = rootPart()
			if root then
				local now = os.clock()
				if now - lastFx > 8 then applyAntiLag() lastFx = now end
				if not target or now - lastPick > 3 then
					local folder = highestZoneTrees()
					local c = folder and densestCluster(folder)
					if c then target = c lastPick = now end
				end
				if target then root.CFrame = CFrame.new(target + Vector3.new(0, config.holdHeight, 0)) end
			end
			task.wait()
		end
	end
end)

task.spawn(function()
	while trove ~= nil do
		if not state.roll then task.wait(0.25)
		else
			local cd = 3.75
			local ok, timing = pcall(function() return RollStats.readRollTiming() end)
			if ok and type(timing) == "table" and type(timing.cooldown) == "number" then cd = timing.cooldown end
			local rolled = pcall(function() return RollNet:fetch("requestRoll") end)
			if rolled then state.rolls = state.rolls + 1 end
			local t = 0
			while t < cd and state.roll and trove ~= nil do task.wait(0.1) t = t + 0.1 end
		end
	end
end)

task.spawn(function()
	local wasOn = false
	while trove ~= nil do
		if not state.equip then wasOn = false task.wait(0.3)
		else
			if not wasOn then
				wasOn = true
				pcall(function() BagNet.setAutoEquipBestAxesOn(true) end)
				pcall(function() BagNet.setAutoEquipBestBeesOn(true) end)
			end
			pcall(function() BagNet.equipBestAxes() end)
			pcall(function() BagNet.equipBestBees() end)
			task.wait(12)
		end
	end
end)

local function buyOneUpgrade()
	local owned = tbl("skillTree") or {}
	local ctx = { logs = num("logs") or 0, rebirths = math.floor(num("rebirthCount") or 0) }
	local pick, pickPri = nil, math.huge
	for id, node in pairs(SkillTreeData.nodes) do
		if not owned[id] and not node.gate then
			local eff = node.effects and node.effects[1]
			local pri = eff and eff.stat and UPGRADE_PRIORITY[eff.stat]
			if pri and pri < pickPri then
				local ok, can = pcall(function() return SkillTreeState.canPurchase(id, SkillTreeState.resolveTreeId(id), owned, ctx) end)
				if ok and can then pickPri = pri pick = id end
			end
		end
	end
	if pick then pcall(function() SkillTreeNet.purchaseNode(pick) end) return true end
	return false
end

task.spawn(function()
	while trove ~= nil do
		if not state.upgrade then task.wait(0.5)
		else
			local bought = 0
			while state.upgrade and trove ~= nil and buyOneUpgrade() and bought < 12 do bought = bought + 1 task.wait(0.18) end
			task.wait(1.5)
		end
	end
end)

task.spawn(function()
	while trove ~= nil do
		if not state.zone then task.wait(0.5)
		else
			local unlocks = ZoneState.readUnlocks(tbl("zones"))
			local logs = num("logs") or 0
			for _, id in ipairs(ZoneData.ZONE_ORDER) do
				if not ZoneState.isUnlocked(id, unlocks) and ZoneState.prerequisiteMet(id, unlocks) then
					if ZoneState.canPurchase(id, unlocks, { logs = logs }) then
						local ok = pcall(function() return ZoneNet.purchaseZone(id) end)
						if ok then pcall(function() ZoneNet.teleportToZone(id) end) end
					end
					break
				end
			end
			task.wait(2)
		end
	end
end)

local function claimAll()
	for _, period in ipairs({ "hourly", "daily", "weekly" }) do
		local ok, st = pcall(function() return QuestsNet.getState(period) end)
		if ok and type(st) == "table" and type(st.slots) == "table" then
			for idx, slot in pairs(st.slots) do
				if type(slot) == "table" and slot.canClaim and not slot.claimed then
					pcall(function() QuestsNet.claim(period, idx) end) task.wait(0.2)
				end
			end
		end
	end
	for _, f in ipairs(AXE_FILTERS) do
		local guard = 0
		while guard < 30 do
			local can = false
			pcall(function() can = ClaimableState.axeFilterCanClaim(f) end)
			if not can then break end
			local r = nil
			pcall(function() r = AxeIndexNet.claim(f) end)
			if not (type(r) == "table" and r.ok) then break end
			guard = guard + 1 task.wait(0.25)
		end
	end
	if LocalPlayer:IsInGroup(896806231) then pcall(function() SocialNet.claimSocialReward() end) end
	for _, code in ipairs(CODES) do pcall(function() CodesNet.redeem(code) end) task.wait(0.3) end
end

task.spawn(function()
	local didOnce = false
	while trove ~= nil do
		if not state.claim then didOnce = false task.wait(0.5)
		else
			if not didOnce then didOnce = true claimAll() end
			local t = 0
			while t < 60 and state.claim and trove ~= nil do task.wait(1) t = t + 1 end
			if state.claim then claimAll() end
		end
	end
end)

task.spawn(function()
	local lastUse = {}
	while trove ~= nil do
		if not state.potion then task.wait(1)
		else
			local items = tbl("items") or {}
			for _, id in ipairs(POTIONS) do
				local cnt = items[id]
				cnt = type(cnt) == "table" and cnt.count or cnt
				if type(cnt) == "number" and cnt >= 1 then
					if not lastUse[id] or os.clock() - lastUse[id] > 870 then
						local ok = false
						pcall(function() ok = ItemsNet.useItem(id) end)
						if ok then lastUse[id] = os.clock() end
					end
				end
			end
			task.wait(20)
		end
	end
end)

task.spawn(function()
	while trove ~= nil do
		if not state.rebirth then task.wait(1)
		else
			local rc = math.floor(num("rebirthCount") or 0)
			local honey = num("honey") or 0
			local cost = RebirthState.honeyCost(rc)
			local can = false
			pcall(function() can = RebirthState.canRebirth(ZoneState.readUnlocks(tbl("zones")), honey, rc) end)
			if can and honey >= cost * config.rebirthBuffer then
				pcall(function() RebirthNet.performRebirth() end)
				task.wait(2.5)
			end
			task.wait(1.5)
		end
	end
end)

task.spawn(function()
	local lastLogs = num("logs") or 0
	while trove ~= nil do
		task.wait(1)
		local logs = num("logs")
		if logs then state.logsPerSec = math.max(0, logs - lastLogs) lastLogs = logs end
	end
end)

track(LocalPlayer.Idled:Connect(function()
	pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end)
end))

-- ============ GUI ============
local accent1 = Color3.fromRGB(139, 92, 246)
local accent2 = Color3.fromRGB(99, 102, 241)
local accent3 = Color3.fromRGB(34, 211, 238)
local bgColor = Color3.fromRGB(17, 17, 23)
local panelColor = Color3.fromRGB(26, 26, 35)
local rowColor = Color3.fromRGB(32, 32, 43)
local strokeColor = Color3.fromRGB(48, 48, 66)
local textColor = Color3.fromRGB(236, 236, 245)
local subColor = Color3.fromRGB(150, 150, 168)
local offColor = Color3.fromRGB(58, 58, 74)

local function corner(parent, radius) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, radius) c.Parent = parent return c end
local function stroke(parent, color, thickness) local s = Instance.new("UIStroke") s.Color = color or strokeColor s.Thickness = thickness or 1 s.Transparency = 0.2 s.Parent = parent return s end
local function host() local ok, t = pcall(function() return gethui() end) if ok and t then return t end return game:GetService("CoreGui") end

local old = host():FindFirstChild("AcrylicDock")
if old then old:Destroy() end

local screen = Instance.new("ScreenGui")
screen.Name = "AcrylicDock"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.IgnoreGuiInset = true
screen.Parent = host()

local window = Instance.new("Frame")
window.Size = UDim2.fromOffset(322, 0)
window.AutomaticSize = Enum.AutomaticSize.Y
window.Position = UDim2.fromScale(0.5, 0.5)
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.BackgroundColor3 = bgColor
window.BorderSizePixel = 0
window.Parent = screen
corner(window, 14)
stroke(window, strokeColor, 1)

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 14) pad.PaddingBottom = UDim.new(0, 14)
pad.PaddingLeft = UDim.new(0, 14) pad.PaddingRight = UDim.new(0, 14)
pad.Parent = window

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = window

local order = 0
local function nextOrder() order = order + 1 return order end

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundTransparency = 1
header.LayoutOrder = nextOrder()
header.Parent = window

local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.fromOffset(4, 26) accentBar.Position = UDim2.fromOffset(0, 7)
accentBar.BorderSizePixel = 0 accentBar.Parent = header corner(accentBar, 2)
local ag = Instance.new("UIGradient")
ag.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, accent1), ColorSequenceKeypoint.new(0.5, accent2), ColorSequenceKeypoint.new(1, accent3) })
ag.Rotation = 90 ag.Parent = accentBar

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1 title.Position = UDim2.fromOffset(16, 2) title.Size = UDim2.new(1, -52, 0, 22)
title.Font = Enum.Font.GothamBold title.Text = "Топоры — Max Автофарм" title.TextColor3 = textColor
title.TextSize = 16 title.TextXAlignment = Enum.TextXAlignment.Left title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1 subtitle.Position = UDim2.fromOffset(16, 22) subtitle.Size = UDim2.new(1, -52, 0, 14)
subtitle.Font = Enum.Font.Gotham subtitle.Text = "рубка · ролл · прокачка · бонусы" subtitle.TextColor3 = subColor
subtitle.TextSize = 11 subtitle.TextXAlignment = Enum.TextXAlignment.Left subtitle.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28) closeBtn.Position = UDim2.new(1, -28, 0, 6) closeBtn.BackgroundColor3 = rowColor
closeBtn.Text = "✕" closeBtn.Font = Enum.Font.GothamBold closeBtn.TextColor3 = subColor closeBtn.TextSize = 15
closeBtn.AutoButtonColor = false closeBtn.Parent = header corner(closeBtn, 8)

local renderers = {}

local function makeToggle(featureKey, label, desc)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 44) row.BackgroundColor3 = rowColor row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder() row.Parent = window corner(row, 10) stroke(row, strokeColor, 1)
	local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, 12) p.PaddingRight = UDim.new(0, 12) p.Parent = row

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1 name.Position = UDim2.fromOffset(0, 6) name.Size = UDim2.new(1, -60, 0, 17)
	name.Font = Enum.Font.GothamMedium name.Text = label name.TextColor3 = textColor name.TextSize = 13.5
	name.TextXAlignment = Enum.TextXAlignment.Left name.Parent = row

	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1 info.Position = UDim2.fromOffset(0, 23) info.Size = UDim2.new(1, -60, 0, 13)
	info.Font = Enum.Font.Gotham info.Text = desc info.TextColor3 = subColor info.TextSize = 10.5
	info.TextXAlignment = Enum.TextXAlignment.Left info.Parent = row

	local pill = Instance.new("TextButton")
	pill.AnchorPoint = Vector2.new(1, 0.5) pill.Position = UDim2.new(1, 0, 0.5, 0) pill.Size = UDim2.fromOffset(44, 24)
	pill.BackgroundColor3 = offColor pill.Text = "" pill.AutoButtonColor = false pill.Parent = row corner(pill, 12)
	local pg = Instance.new("UIGradient")
	pg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, accent1), ColorSequenceKeypoint.new(1, accent3) })
	pg.Enabled = false pg.Parent = pill

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5) knob.Position = UDim2.fromOffset(3, 12) knob.Size = UDim2.fromOffset(18, 18)
	knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250) knob.BorderSizePixel = 0 knob.Parent = pill corner(knob, 9)

	local function render()
		local on = state[featureKey]
		pg.Enabled = on
		pill.BackgroundColor3 = on and accent2 or offColor
		TweenService:Create(knob, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Position = on and UDim2.fromOffset(23, 12) or UDim2.fromOffset(3, 12) }):Play()
	end
	renderers[featureKey] = render
	pill.MouseButton1Click:Connect(function() state[featureKey] = not state[featureKey] render() end)
	render()
end

local function makeSection(text)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 16) lbl.BackgroundTransparency = 1 lbl.LayoutOrder = nextOrder()
	lbl.Font = Enum.Font.GothamBold lbl.Text = string.upper(text) lbl.TextColor3 = accent3 lbl.TextSize = 10.5
	lbl.TextXAlignment = Enum.TextXAlignment.Left lbl.Parent = window
end

local masterBtn = Instance.new("TextButton")
masterBtn.Size = UDim2.new(1, 0, 0, 32) masterBtn.BackgroundColor3 = accent2 masterBtn.Text = "ВКЛЮЧИТЬ ВЕСЬ ФАРМ"
masterBtn.Font = Enum.Font.GothamBold masterBtn.TextColor3 = Color3.fromRGB(250, 250, 255) masterBtn.TextSize = 13
masterBtn.AutoButtonColor = true masterBtn.LayoutOrder = nextOrder() masterBtn.Parent = window corner(masterBtn, 10)
local mg = Instance.new("UIGradient")
mg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, accent1), ColorSequenceKeypoint.new(1, accent3) })
mg.Parent = masterBtn

makeSection("Фарм")
makeToggle("chop", "Авто-руб + сбор", "кластер лучшей зоны, без лагов")
makeToggle("roll", "Авто-ролл", "катит на кулдауне (свежие топоры)")
makeSection("Прокачка")
makeToggle("equip", "Авто-экип лучших", "топоры + пчёлы, держит максимум")
makeToggle("upgrade", "Авто-апгрейд", "скилл-древо за логи (приоритет)")
makeToggle("zone", "Авто-зоны", "покупка + телепорт в лучшую")
makeSection("Бонусы")
makeToggle("claim", "Авто-клейм наград", "квесты, индекс, коды, группа")
makeToggle("potion", "Авто-зелья", "скорость ролла и удача")
makeToggle("rebirth", "Авто-ребёрт", "за мёд, удача ×1.75 (сброс логов!)")

local stats = Instance.new("Frame")
stats.Size = UDim2.new(1, 0, 0, 66) stats.BackgroundColor3 = panelColor stats.BorderSizePixel = 0
stats.LayoutOrder = nextOrder() stats.Parent = window corner(stats, 10) stroke(stats, strokeColor, 1)
local sp = Instance.new("UIPadding") sp.PaddingLeft = UDim.new(0, 12) sp.PaddingTop = UDim.new(0, 8) sp.Parent = stats
local line1 = Instance.new("TextLabel")
line1.BackgroundTransparency = 1 line1.Size = UDim2.new(1, -12, 0, 17) line1.Font = Enum.Font.GothamMedium
line1.Text = "" line1.TextColor3 = textColor line1.TextSize = 13 line1.TextXAlignment = Enum.TextXAlignment.Left line1.Parent = stats
local line2 = Instance.new("TextLabel")
line2.BackgroundTransparency = 1 line2.Position = UDim2.fromOffset(0, 22) line2.Size = UDim2.new(1, -12, 0, 15) line2.Font = Enum.Font.Gotham
line2.Text = "" line2.TextColor3 = subColor line2.TextSize = 11.5 line2.TextXAlignment = Enum.TextXAlignment.Left line2.Parent = stats
local line3 = Instance.new("TextLabel")
line3.BackgroundTransparency = 1 line3.Position = UDim2.fromOffset(0, 40) line3.Size = UDim2.new(1, -12, 0, 15) line3.Font = Enum.Font.Gotham
line3.Text = "" line3.TextColor3 = subColor line3.TextSize = 11.5 line3.TextXAlignment = Enum.TextXAlignment.Left line3.Parent = stats

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, 0, 0, 32) unloadBtn.BackgroundColor3 = Color3.fromRGB(48, 26, 32) unloadBtn.Text = "Выгрузить"
unloadBtn.Font = Enum.Font.GothamMedium unloadBtn.TextColor3 = Color3.fromRGB(248, 162, 170) unloadBtn.TextSize = 13
unloadBtn.LayoutOrder = nextOrder() unloadBtn.Parent = window corner(unloadBtn, 10) stroke(unloadBtn, Color3.fromRGB(90, 44, 54), 1)

local function fmt(n)
	if not n then return "—" end
	if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.2fK", n / 1e3) end
	return string.format("%d", n)
end

track(RunService.Heartbeat:Connect(function()
	if screen.Parent == nil then pcall(function() screen.Parent = game:GetService("CoreGui") end) end
	local logs = num("logs")
	local zoneId = ZoneState.highestUnlockedZoneId(ZoneState.readUnlocks(tbl("zones")))
	line1.Text = string.format("Логи: %s    +%s/сек", fmt(logs), fmt(state.logsPerSec))
	line2.Text = string.format("Зона: %s    топоры: %d/%d", ZoneData.formatTitle(zoneId or "?"), equippedAxeCount(), math.floor(num("maxEquippedAxes") or 1))
	line3.Text = string.format("Ребёрты: %d    мёд: %s    роллов: %d", math.floor(num("rebirthCount") or 0), fmt(num("honey")), state.rolls)
end))

masterBtn.MouseButton1Click:Connect(function()
	for _, k in ipairs({ "chop", "roll", "equip", "upgrade", "zone", "claim" }) do
		state[k] = true
		if renderers[k] then renderers[k]() end
	end
end)

do
	local dragging, dragStart, startPos = false, nil, nil
	track(header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true dragStart = input.Position startPos = window.Position
			input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
end

local function unload()
	for k in pairs(state) do if type(state[k]) == "boolean" then state[k] = false end end
	local conns = trove
	trove = nil
	for _, conn in ipairs(conns) do pcall(function() conn:Disconnect() end) end
	pcall(function() screen:Destroy() end)
end
closeBtn.MouseButton1Click:Connect(unload)
unloadBtn.MouseButton1Click:Connect(unload)

_G.__AcrylicUnload = unload
_G.__AcrylicState = state
