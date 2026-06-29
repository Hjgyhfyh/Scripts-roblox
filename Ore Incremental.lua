--[[
	Ore Incremental — full-progression idle suite
	Collect • Upgrades • Trees • Runes • Tycoon • Totems • Reset ladder • Rank
]]

local CoreGui        = game:GetService("CoreGui")
local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService     = game:GetService("RunService")
local UserInput      = game:GetService("UserInputService")
local TweenService   = game:GetService("TweenService")
local HttpService    = game:GetService("HttpService")
local VirtualUser    = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- Singleton: unload a previous instance before starting a fresh one
----------------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G
if ENV.__OreIncrementalSuite and ENV.__OreIncrementalSuite.Unload then
	pcall(ENV.__OreIncrementalSuite.Unload)
end
local Suite = {}
ENV.__OreIncrementalSuite = Suite

----------------------------------------------------------------------
-- Bookkeeping for a clean unload
----------------------------------------------------------------------
local Alive = true
local Connections = {}
local Threads = {}
local function track(conn) Connections[#Connections+1] = conn return conn end
local function spawnLoop(fn)
	local co = task.spawn(function()
		while Alive do
			local ok, err = pcall(fn)
			if not ok then task.wait(0.5) end
			if not Alive then break end
		end
	end)
	Threads[#Threads+1] = co
	return co
end

----------------------------------------------------------------------
-- Game wiring (all paths verified present)
----------------------------------------------------------------------
local Knit = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index")
	:WaitForChild("sleitnick_knit@1.7.0"):WaitForChild("knit")
local Services = Knit:WaitForChild("Services")

local PDS          = Services.PlayerDataService
local US           = Services.UpgradeService
local ResetLayer   = Services.ResetLayerService
local PortalService= Services.PortalService
local RankService  = Services.RankService
local TotemService = Services.TotemService
local MineService  = Services.MineService
local SettingsSvc  = Services.SettingsService
local CodesService = Services.CodesService

local function req(path)
	local ok, m = pcall(require, path)
	return ok and m or nil
end

local CubesRemotes    = req(ReplicatedStorage.Shared.KnitByteNet.CubesRemotes)
local ClickerRemotes  = req(ReplicatedStorage.Shared.KnitByteNet.ClickerRemotes)
local ClickOreRemotes = req(ReplicatedStorage.Shared.KnitByteNet.ClickOreRemotes)
local RunesRemotes    = req(ReplicatedStorage.Shared.KnitByteNet.RunesRemotes)
local GroupLikeRemotes= req(ReplicatedStorage.Shared.KnitByteNet.GroupLikeRewardRemotes)

local UHR        = req(ReplicatedStorage.Congo.Handlers.UpgradeHandler.UpgradeHandlerRemotes)
local UHEnum     = req(ReplicatedStorage.Congo.Handlers.UpgradeHandler.UpgradeHandlerEnum)
local Tyc        = req(ReplicatedStorage.Congo.Handlers.TycoonHandler.TycoonHandlerClient)
local DailyClient= req(ReplicatedStorage.Congo.Handlers.DailyStreakHandler.DailyStreakHandlerClient)
local PotionClient = req(ReplicatedStorage.Congo.Handlers.PotionHandler.PotionHandlerClient)
local MonetizeClient = req(ReplicatedStorage.Congo.Handlers.MonetizeHandler.MonetizeHandlerClient)

local DataController = nil do
	local kn = req(ReplicatedStorage.Packages.knit)
	if kn and kn.GetController then pcall(function() DataController = kn.GetController("DataController") end) end
end

local UpgradesConfig = req(ReplicatedStorage.Shared.Configs.UpgradesConfig)
local ResetShared    = req(ReplicatedStorage.Shared.KnitShared.ResetLayerShared)
local MultShared     = req(ReplicatedStorage.Shared.Client.Utils.MultiplierUtils.MultiplierShared)
local MultRunes      = req(ReplicatedStorage.Shared.Client.Utils.MultiplierUtils.MultiplierRunes)
local Abbreviate     = req(ReplicatedStorage.Shared.Packages.Abbrievate)

----------------------------------------------------------------------
-- Character helpers
----------------------------------------------------------------------
local function character() return LocalPlayer.Character end
local function getHRP()
	local c = character()
	return c and c:FindFirstChild("HumanoidRootPart")
end

----------------------------------------------------------------------
-- Number formatting
----------------------------------------------------------------------
local function fmt(n)
	n = tonumber(n) or 0
	if Abbreviate then
		local ok, s = pcall(function()
			if type(Abbreviate) == "function" then return Abbreviate(n) end
			if Abbreviate.abbreviate then return Abbreviate.abbreviate(n) end
			if Abbreviate.Abbreviate then return Abbreviate.Abbreviate(n) end
		end)
		if ok and s then return tostring(s) end
	end
	local abs = math.abs(n)
	local units = {"","K","M","B","T","Qa","Qi","Sx","Sp","Oc","No","Dc"}
	local i = 1
	while abs >= 1000 and i < #units do abs = abs/1000; i = i+1 end
	if i == 1 then return tostring(math.floor(n)) end
	return string.format("%.2f%s", (n<0 and -abs or abs), units[i])
end

----------------------------------------------------------------------
-- State reads
----------------------------------------------------------------------
local function getData()
	local ok, d = pcall(function() return PDS.RF.GetData:InvokeServer() end)
	return ok and d or nil
end
local function getCached(pathTbl, default)
	if DataController and DataController.GetCached then
		local ok, v = pcall(function() return DataController:GetCached(pathTbl) end)
		if ok and v ~= nil then return v end
	end
	return default
end
local function getPath(pathTbl, default)
	local ok, v = pcall(function() return PDS.RF.GetPath:InvokeServer(pathTbl) end)
	if ok and v ~= nil then return v end
	return default
end
local function currency(name) return tonumber(getCached({name}, 0)) or 0 end

----------------------------------------------------------------------
-- Persistent config
----------------------------------------------------------------------
local CFG_DIR  = "OreIncremental"
local CFG_FILE = CFG_DIR .. "/config.json"

local Config = {
	master        = false,
	collect       = true,
	clicks        = true,  clicksRate = 50,
	fireStones    = true,  fireRate   = 18,
	runes         = true,
	tycoon        = true,
	upgrades      = true,
	trees         = true,
	totems        = true,
	rebirth       = true,
	prestige      = true,
	ascension     = true,
	sacrifice     = false,
	rank          = true,
	mine          = true,
	daily         = true,
	potions       = true,
	park          = "Auto",
	codes         = {},
	winPos        = {0.5, -230, 0.5, -190},
	minimized     = false,
}

local function hasFS()
	return writefile and readfile and isfolder and makefolder
end
local function saveConfig()
	if not hasFS() then return end
	pcall(function()
		if not isfolder(CFG_DIR) then makefolder(CFG_DIR) end
		writefile(CFG_FILE, HttpService:JSONEncode(Config))
	end)
end
local function loadConfig()
	if not hasFS() then return end
	pcall(function()
		if isfile and isfile(CFG_FILE) then
			local data = HttpService:JSONDecode(readfile(CFG_FILE))
			for k, v in pairs(data) do Config[k] = v end
		end
	end)
end
loadConfig()

local saveQueued = false
local function queueSave()
	if saveQueued then return end
	saveQueued = true
	task.delay(0.6, function() saveQueued = false saveConfig() end)
end

----------------------------------------------------------------------
-- Reset ladder definitions
----------------------------------------------------------------------
local RESET_INPUT = { Rebirth="Money", Prestige="Rebirth", Ascension="Prestige", Sacrifice="Ascension" }

local function readyToReset(key)
	if not (ResetShared and MultShared) then return false, 0 end
	local pd = MultShared.getProfileData(LocalPlayer)
	if not pd then return false, 0 end
	local input = pd[RESET_INPUT[key]] or 0
	local ok1, reward = pcall(ResetShared.GetReward, key, LocalPlayer, input)
	if not ok1 or not reward or reward <= 0 then return false, 0 end
	local ok2, meets = pcall(ResetShared.MeetsCurrencyRequirement, key, LocalPlayer)
	if not ok2 or not meets then return false, reward end
	return true, reward
end

local function tryReset(key, allowed)
	if not allowed then return end
	local ok, reward = readyToReset(key)
	if not ok then return end
	local hold = currency(key)
	local threshold = math.max(1, hold * 0.5)
	if reward >= threshold then
		pcall(function() ResetLayer.RE.BuyLayer:FireServer(key) end)
	end
end

----------------------------------------------------------------------
-- Rune stations
----------------------------------------------------------------------
local RUNE_STATIONS = {
	{ name="Basic",         cur="Crystals",         cost=1,      pos=Vector3.new(-84, 14, 405) },
	{ name="Core Crystals", cur="CoreCrystals",     cost=1,      pos=Vector3.new(-306, 12, -266) },
	{ name="Leaderboard",   cur="LeaderboardToken", cost=1,      pos=Vector3.new(-274, 11, 436) },
	{ name="Fire Stones",   cur="Fire Stones",      cost=200,    pos=Vector3.new(325, -38, -44) },
	{ name="Ascension",     cur="Ascension",        cost=500,    pos=Vector3.new(-52, 14, 82) },
	{ name="Prestige",      cur="Prestige",         cost=1000,   pos=Vector3.new(-274, 5, -134) },
	{ name="Clicks",        cur="Clicks",           cost=1500,   pos=Vector3.new(53, 14, -57) },
	{ name="Gems",          cur="Gems",             cost=1500,   pos=Vector3.new(323, -95, 268) },
	{ name="Rebirth",       cur="Rebirth",          cost=25000,  pos=Vector3.new(-168, 14, 449) },
	{ name="Sacrifice",     cur="Sacrifice",        cost=100000, pos=Vector3.new(396, -95, 364) },
}
local runeBusy = false

----------------------------------------------------------------------
-- Automation upgrades (bought first each sweep, by currency priority)
----------------------------------------------------------------------
local AUTOMATION = {
	"Auto Clicker", "Core Crystal Auto Pickup", "Fire Stones Auto Clicker",
	"Ore Auto Pickup", "Auto Upgrade", "Auto Rebirth", "Auto Prestige",
}

-- flatten the whole upgrade catalog once
local ALL_UPGRADE_KEYS = {}
if UpgradesConfig and UpgradesConfig.Upgrades then
	for _, cat in pairs(UpgradesConfig.Upgrades) do
		local sub = cat.Upgrades or cat
		for key in pairs(sub) do ALL_UPGRADE_KEYS[#ALL_UPGRADE_KEYS+1] = key end
	end
end

----------------------------------------------------------------------
-- Action primitives
----------------------------------------------------------------------
local stats = { collected = 0, clicks = 0, runes = 0, resets = 0 }

local function doCollect()
	local ores = workspace:FindFirstChild("SpawnedOres")
	if not ores then return end
	local g = {}
	for _, m in ipairs(ores:GetChildren()) do
		if m:IsA("Model") then g[#g+1] = m.Name end
	end
	if #g > 0 and CubesRemotes and CubesRemotes.collectCubes then
		pcall(function() CubesRemotes.collectCubes.send({ cubeGUIDs = g }) end)
		stats.collected = stats.collected + #g
	end
end

local function autoClickerMaxed()
	return (tonumber(getCached({"Upgrades","Auto Clicker"}, 0)) or 0) >= 10
end
local function doClick()
	if ClickerRemotes and ClickerRemotes.Click then
		pcall(function() ClickerRemotes.Click.send() end)
		stats.clicks = stats.clicks + 1
	end
end

local function fireStonesAutoOwned()
	return (tonumber(getCached({"Upgrades","Fire Stones Auto Clicker"}, 0)) or 0) > 0
end
local function doFireStone()
	if ClickOreRemotes and ClickOreRemotes.clickOre then
		pcall(function() ClickOreRemotes.clickOre.send({ currencyEnum = "Fire Stones" }) end)
	end
end

local function buyAutomationUpgrades()
	for _, name in ipairs(AUTOMATION) do
		pcall(function() US.RE.BuyMaxUpgrade:FireServer(name) end)
	end
end

-- sweep all board upgrades, spread out so we never burst the remote budget
local function sweepUpgrades()
	local i = 1
	local n = #ALL_UPGRADE_KEYS
	while i <= n and Alive and Config.upgrades and Config.master do
		for _ = 1, 4 do
			local key = ALL_UPGRADE_KEYS[i]
			if not key then break end
			pcall(function() US.RE.BuyMaxUpgrade:FireServer(key) end)
			i = i + 1
		end
		task.wait(0.08)
	end
end

local function sweepTrees()
	if not (UHR and UHEnum and UHEnum.LIST) then return end
	if UHEnum.LIST.TREE_1 and UHEnum.LIST.TREE_1.UPGRADES then
		for _, e in pairs(UHEnum.LIST.TREE_1.UPGRADES) do
			pcall(function() UHR.upgradeMax.send({ upgradeCategory = "Tree1", upgradeEnum = e }) end)
		end
	end
	local rank = tonumber(getPath({"Rank"}, 0)) or 0
	if rank >= 1 and UHEnum.LIST.SKILL_TREE and UHEnum.LIST.SKILL_TREE.UPGRADES then
		for _, e in pairs(UHEnum.LIST.SKILL_TREE.UPGRADES) do
			pcall(function() UHR.upgradeMax.send({ upgradeCategory = "SkillTree", upgradeEnum = e }) end)
		end
	end
end

local function openOneRune()
	if not (RunesRemotes and RunesRemotes.buyRune) then return 1 end
	for _, s in ipairs(RUNE_STATIONS) do
		if currency(s.cur) >= s.cost then
			local hrp = getHRP()
			if not hrp then return 1 end
			runeBusy = true
			local home = hrp.CFrame
			hrp.CFrame = CFrame.new(s.pos) + Vector3.new(0, 3, 0)
			task.wait(0.25)
			pcall(function() RunesRemotes.buyRune.send(s.name) end)
			stats.runes = stats.runes + 1
			task.wait(0.2)
			local h2 = getHRP()
			if h2 then h2.CFrame = home end
			runeBusy = false
			local cd = 1
			if MultRunes and MultRunes.getRuneCooldownSeconds then
				local ok, v = pcall(MultRunes.getRuneCooldownSeconds, LocalPlayer, false)
				if ok and v then cd = v end
			end
			return cd
		end
	end
	-- rarity rune consumes banked rolls, no currency
	local rolled = getCached({"RolledRarityCount"})
	if type(rolled) == "table" then
		for _, v in pairs(rolled) do
			if (tonumber(v) or 0) > 0 then
				pcall(function() RunesRemotes.buyRune.send("Rarity Rune") end)
				break
			end
		end
	end
	return 1
end

local function buyTotems()
	pcall(function() TotemService.RE.BuyTotem:FireServer("Rebirth") end)
	pcall(function() TotemService.RE.BuyTotem:FireServer("Ascension") end)
	pcall(function() TotemService.RE.BuyTotem:FireServer("Prestige") end)
end

local function tycoonUnlocked()
	local up = getCached({"UnlockedPortals"})
	if type(up) == "table" and up.Sacrifice == true then return true end
	local d = getData()
	return d and d.UnlockedPortals and d.UnlockedPortals.Sacrifice == true
end

local function buyTycoon()
	if not (Tyc and tycoonUnlocked()) then return end
	pcall(function() Tyc.buyDropper("ClickDropper") end)
	for _, u in ipairs({"Upgrader1","Upgrader2","Upgrader3","Upgrader4","Upgrader5"}) do
		pcall(function() Tyc.buyUpgrader(u) end)
	end
	for _, dn in ipairs({"Dropper1","Dropper2","Dropper3","Dropper4","Dropper5","Dropper6","Dropper7"}) do
		pcall(function() Tyc.buyDropper(dn) end)
	end
end

----------------------------------------------------------------------
-- Reset ladder + rank
----------------------------------------------------------------------
local function runResetLadder()
	tryReset("Rebirth",  Config.rebirth)
	tryReset("Prestige", Config.prestige)
	tryReset("Ascension",Config.ascension)
	tryReset("Sacrifice",Config.sacrifice)
	if Config.sacrifice then buyTycoon() end
end

local function doRankUp()
	local r = tonumber(getPath({"Rank"}, 0)) or 0
	local l = tonumber(getPath({"Level"}, 0)) or 0
	if l >= (r + 1) * 50 then
		pcall(function() RankService.RE.RequestRankUp:FireServer() end)
		task.wait(0.4)
		sweepTrees()
	end
end

----------------------------------------------------------------------
-- Positioning
----------------------------------------------------------------------
local function isUnlocked(portal)
	local ok, v = pcall(function() return PortalService.RF.IsPortalUnlocked:InvokeServer(portal) end)
	return ok and v == true
end
local function ownsUpg(key) return (tonumber(getCached({"Upgrades",key},0)) or 0) > 0 end

local function park()
	if runeBusy then return end
	local hrp = getHRP()
	if not hrp then return end
	local mode = Config.park
	if mode == "Off" then return end
	if mode == "CoreCrystals" or (mode == "Auto" and not ownsUpg("Core Crystal Auto Pickup") and isUnlocked("Cave")) then
		hrp.CFrame = CFrame.new(-361.05, 6.5, -241.15)
		return
	end
	if mode == "CubeSpawner" or (mode == "Auto" and not ownsUpg("Ore Auto Pickup")) then
		local cs = workspace:FindFirstChild("CubeSpawner")
		local hb = cs and cs:FindFirstChild("Hitbox")
		if hb then hrp.CFrame = hb.CFrame + Vector3.new(0, 3, 0) end
	end
end

----------------------------------------------------------------------
-- Misc one-shots
----------------------------------------------------------------------
local function claimDaily()
	if not (DailyClient and DailyClient.log) then return end
	local ds = getPath({"DailyStreak"}, {})
	local last = (type(ds) == "table" and tonumber(ds.LastClaimTime)) or 0
	if os.time() - last >= 86400 then pcall(DailyClient.log) end
end
local function drainPotions()
	if not (PotionClient and PotionClient.activatePotion) then return end
	local stored = getPath({"StoredPotions"}, {})
	if type(stored) ~= "table" then return end
	for enum, count in pairs(stored) do
		for _ = 1, (tonumber(count) or 0) do
			pcall(function() PotionClient.activatePotion(enum) end)
		end
	end
end
local function collectMine()
	if (tonumber(getPath({"Mine","Stored"}, 0)) or 0) >= 1 then
		pcall(function() MineService.RE.Collect:FireServer() end)
	end
end
local function redeemCodes()
	if type(Config.codes) ~= "table" then return end
	local done = getPath({"RedeemedCodes"}, {})
	local seen = {}
	if type(done) == "table" then for _, c in pairs(done) do seen[tostring(c)] = true end end
	for _, c in ipairs(Config.codes) do
		if c and c ~= "" and not seen[c] then
			pcall(function() CodesService.RE.RedeemCode:FireServer(c) end)
		end
	end
end

----------------------------------------------------------------------
-- Boot one-shots
----------------------------------------------------------------------
local booted = false
local function bootOnce()
	if booted then return end
	booted = true
	if CubesRemotes and CubesRemotes.startSpawning then pcall(function() CubesRemotes.startSpawning.send() end) end
	if ClickOreRemotes and ClickOreRemotes.startSpawningOres then pcall(function() ClickOreRemotes.startSpawningOres.send() end) end
	pcall(function() MineService.RE.StartMine:FireServer() end)
	if MonetizeClient and MonetizeClient.startReceivingTickets then pcall(MonetizeClient.startReceivingTickets) end
	if Tyc and Tyc.SpawnItemInstance then
		track(Tyc.SpawnItemInstance:Connect(function(info)
			if Config.tycoon and info and info.cubeId then pcall(function() Tyc.sellItem(info.cubeId) end) end
		end))
	end
	-- group-like reward (only fires if the account actually liked the group)
	if GroupLikeRemotes and GroupLikeRemotes.redeem then
		if getPath({"IsGroupLikeRewardRedeemed"}) ~= true then
			pcall(function() GroupLikeRemotes.redeem.send() end)
		end
	end
	redeemCodes()
end

----------------------------------------------------------------------
-- Anti-AFK
----------------------------------------------------------------------
track(LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

----------------------------------------------------------------------
-- Loops (each guarded by master + its toggle; rates configurable)
----------------------------------------------------------------------
-- continuous collect
spawnLoop(function()
	if Config.master and Config.collect then doCollect() end
	task.wait(0.2)
end)

-- clicks (rate-limited; stop once auto clicker maxed)
spawnLoop(function()
	if Config.master and Config.clicks and not autoClickerMaxed() then
		local rate = math.clamp(tonumber(Config.clicksRate) or 50, 1, 120)
		doClick()
		task.wait(1 / rate)
	else
		task.wait(0.5)
	end
end)

-- fire stones (rate-limited; stop once auto clicker owned)
spawnLoop(function()
	if Config.master and Config.fireStones and not fireStonesAutoOwned() then
		local rate = math.clamp(tonumber(Config.fireRate) or 18, 1, 60)
		doFireStone()
		task.wait(1 / rate)
	else
		task.wait(0.5)
	end
end)

-- manual tycoon dropper pulse while bootstrapping
spawnLoop(function()
	if Config.master and Config.tycoon and tycoonUnlocked() and Tyc and Tyc.activateManualDropper then
		local owned = nil
		pcall(function() owned = Tyc.getOwnedDroppers and Tyc.getOwnedDroppers() end)
		local hasReal = false
		if type(owned) == "table" then
			for _, d in pairs(owned) do
				if tostring(d):match("^Dropper") then hasReal = true break end
			end
		end
		if not hasReal then
			pcall(function() Tyc.activateManualDropper("ClickDropper") end)
			task.wait(0.2)
		else
			task.wait(1)
		end
	else
		task.wait(1)
	end
end)

-- automation upgrades (cheap, every cycle)
spawnLoop(function()
	if Config.master and Config.upgrades then buyAutomationUpgrades() end
	task.wait(1.2)
end)

-- full board sweep (spread out internally)
spawnLoop(function()
	if Config.master and Config.upgrades then sweepUpgrades() end
	task.wait(1.5)
end)

-- upgrade trees
spawnLoop(function()
	if Config.master and Config.trees then sweepTrees() end
	task.wait(2.5)
end)

-- runes rotation
spawnLoop(function()
	if Config.master and Config.runes then
		local cd = openOneRune()
		task.wait(math.max(0.4, cd or 1))
	else
		task.wait(1)
	end
end)

-- tycoon buys
spawnLoop(function()
	if Config.master and Config.tycoon then buyTycoon() end
	task.wait(3)
end)

-- totems
spawnLoop(function()
	if Config.master and Config.totems then buyTotems() end
	task.wait(5)
end)

-- reset ladder
spawnLoop(function()
	if Config.master then runResetLadder() end
	task.wait(1.5)
end)

-- rank up
spawnLoop(function()
	if Config.master and Config.rank then doRankUp() end
	task.wait(4)
end)

-- positioning
spawnLoop(function()
	if Config.master then park() end
	task.wait(2)
end)

-- mine / daily / potions (slow poll)
spawnLoop(function()
	if Config.master then
		if Config.mine then collectMine() end
		if Config.daily then claimDaily() end
		if Config.potions then drainPotions() end
	end
	task.wait(45)
end)

-- boot trigger when master turns on
spawnLoop(function()
	if Config.master and not booted then bootOnce() end
	task.wait(1)
end)

----------------------------------------------------------------------
--  GUI  —  Violet-Noir Acrylic
----------------------------------------------------------------------
local PAL = {
	bg="0C0C14", panel="13131E", card="191926", raise="20202F", well="0F0F18",
	line="2B2B3D", text="F4F5F7", sub="A9ADBE", dim="6B6E80",
	on="2BD17E", bad="F2555A", gold="FFD166", cyan="56C0FF", violet="8B6CFF", indigo="6E7BFF",
}
local function C(hex)
	hex = tostring(hex):gsub("#","")
	return Color3.fromRGB(
		tonumber(hex:sub(1,2),16) or 255,
		tonumber(hex:sub(3,4),16) or 255,
		tonumber(hex:sub(5,6),16) or 255)
end

local TI_FAST  = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_PILL  = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_KNOB  = TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(p, r) return mk("UICorner", {CornerRadius=UDim.new(0, r or 8)}, p) end
local function stroke(p, col, t, trans)
	return mk("UIStroke", {Color=C(col or PAL.line), Thickness=t or 1, Transparency=trans or 0,
		ApplyStrokeMode=Enum.ApplyStrokeMode.Border}, p)
end
local function pad(p, a) mk("UIPadding", {PaddingLeft=UDim.new(0,a),PaddingRight=UDim.new(0,a),PaddingTop=UDim.new(0,a),PaddingBottom=UDim.new(0,a)}, p) end
local function gradient(p, c1, c2, rot)
	return mk("UIGradient", {Color=ColorSequence.new(C(c1), C(c2)), Rotation=rot or 90}, p)
end

local function topSheen(parent)
	local s = mk("Frame", {BackgroundColor3=C("FFFFFF"), BorderSizePixel=0,
		Size=UDim2.new(1,0,1,0), ZIndex=parent.ZIndex+1}, parent)
	corner(s, 8)
	mk("UIGradient", {Rotation=90, Transparency=NumberSequence.new({
		NumberSequenceKeypoint.new(0,0.88), NumberSequenceKeypoint.new(0.5,0.97), NumberSequenceKeypoint.new(1,1)})}, s)
	return s
end

local function brandStroke(p, t)
	local s = stroke(p, PAL.violet, t or 1.2)
	mk("UIGradient", {Color=ColorSequence.new({
		ColorSequenceKeypoint.new(0, C(PAL.violet)),
		ColorSequenceKeypoint.new(0.5, C(PAL.indigo)),
		ColorSequenceKeypoint.new(1, C(PAL.cyan))}), Rotation=25}, s)
	return s
end

-- ScreenGui (hide from common detectors where possible)
local gui = mk("ScreenGui", {Name="OreSuite_"..tostring(math.random(1000,9999)),
	ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, IgnoreGuiInset=true})
pcall(function() gui.DisplayOrder = 9999 end)
do
	local parented = false
	if gethui then local ok = pcall(function() gui.Parent = gethui() end) parented = ok end
	if not parented then
		local ok = pcall(function() gui.Parent = CoreGui end)
		if not ok then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
	end
end

-- window shadow (sibling, behind window)
local shadowHolder = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(0,460,0,380),
	Position=UDim2.new(Config.winPos[1],Config.winPos[2],Config.winPos[3],Config.winPos[4]), ZIndex=1}, gui)
mk("ImageLabel", {BackgroundTransparency=1, Image="rbxassetid://6014261993",
	ImageColor3=C("000000"), ImageTransparency=0.45, ScaleType=Enum.ScaleType.Slice,
	SliceCenter=Rect.new(49,49,450,450), Size=UDim2.new(1,80,1,80), Position=UDim2.new(0,-40,0,-40),
	ZIndex=1}, shadowHolder)

-- main window
local win = mk("Frame", {BackgroundColor3=C(PAL.panel), BorderSizePixel=0,
	Size=UDim2.new(0,460,0,380), Position=UDim2.new(0,0,0,0), ZIndex=2}, shadowHolder)
corner(win, 12)
stroke(win, PAL.line, 1)
gradient(win, "15151F", "101019", 90)

-- header
local header = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,46), ZIndex=3}, win)
local logo = mk("Frame", {BackgroundColor3=C(PAL.violet), BorderSizePixel=0,
	Size=UDim2.new(0,26,0,26), Position=UDim2.new(0,14,0,10), ZIndex=4}, header)
corner(logo, 7)
gradient(logo, PAL.violet, PAL.cyan, 35)
local gem = mk("Frame", {BackgroundColor3=C("FFFFFF"), BackgroundTransparency=0.08, BorderSizePixel=0,
	AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,11,0,11),
	Rotation=45, ZIndex=5}, logo)
mk("UICorner", {CornerRadius=UDim.new(0,2)}, gem)
local title = mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,50,0,7),
	Size=UDim2.new(1,-150,0,18), Text="ORE INCREMENTAL", TextColor3=C(PAL.text),
	Font=Enum.Font.GothamBold, TextSize=14, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4}, header)
local subtitle = mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,50,0,25),
	Size=UDim2.new(1,-150,0,14), Text="idle suite", TextColor3=C(PAL.dim),
	Font=Enum.Font.Gotham, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4}, header)

local function headerBtn(x, kind, col)
	local b = mk("TextButton", {BackgroundColor3=C(PAL.card), BorderSizePixel=0, AutoButtonColor=false,
		Size=UDim2.new(0,26,0,26), Position=UDim2.new(1,x,0,10), Text="", ZIndex=4}, header)
	corner(b, 7); stroke(b, PAL.line, 1)
	local ic = C(col or PAL.sub)
	if kind == "close" then
		for _, r in ipairs({45, -45}) do
			mk("Frame", {BackgroundColor3=ic, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5),
				Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,12,0,2), Rotation=r, ZIndex=5}, b)
		end
	else
		mk("Frame", {BackgroundColor3=ic, BorderSizePixel=0, AnchorPoint=Vector2.new(0.5,0.5),
			Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,12,0,2), ZIndex=5}, b)
	end
	track(b.MouseEnter:Connect(function() TweenService:Create(b,TI_FAST,{BackgroundColor3=C(PAL.raise)}):Play() end))
	track(b.MouseLeave:Connect(function() TweenService:Create(b,TI_FAST,{BackgroundColor3=C(PAL.card)}):Play() end))
	return b
end
local btnClose = headerBtn(-40, "close", PAL.bad)
local btnMin   = headerBtn(-72, "min", PAL.sub)

-- status strip with master toggle
local strip = mk("Frame", {BackgroundColor3=C(PAL.well), BorderSizePixel=0,
	Size=UDim2.new(1,-28,0,42), Position=UDim2.new(0,14,0,52), ZIndex=3}, win)
corner(strip, 9); stroke(strip, PAL.line, 1)
local statusDot = mk("Frame", {BackgroundColor3=C(PAL.dim), BorderSizePixel=0,
	Size=UDim2.new(0,10,0,10), Position=UDim2.new(0,14,0.5,-5), ZIndex=4}, strip)
corner(statusDot, 5)
local statusText = mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,34,0,0),
	Size=UDim2.new(1,-150,1,0), Text="Stopped", TextColor3=C(PAL.sub), Font=Enum.Font.GothamMedium,
	TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4}, strip)

-- master switch
local master = mk("TextButton", {BackgroundColor3=C(PAL.raise), BorderSizePixel=0, AutoButtonColor=false,
	Size=UDim2.new(0,108,0,30), Position=UDim2.new(1,-118,0.5,-15), Text="", ZIndex=4}, strip)
corner(master, 8); stroke(master, PAL.line, 1)
local masterLbl = mk("TextLabel", {BackgroundTransparency=1, Size=UDim2.new(1,0,1,0),
	Text="START", TextColor3=C(PAL.sub), Font=Enum.Font.GothamBold, TextSize=13, ZIndex=5}, master)

-- tab bar
local tabbar = mk("Frame", {BackgroundColor3=C(PAL.well), BorderSizePixel=0,
	Size=UDim2.new(1,-28,0,34), Position=UDim2.new(0,14,0,102), ZIndex=3}, win)
corner(tabbar, 9); stroke(tabbar, PAL.line, 1); pad(tabbar, 4)
local TABS = {"Main","Farm","Auto","Resets","More"}
local pill = mk("Frame", {BackgroundColor3=C(PAL.violet), BorderSizePixel=0, ZIndex=4}, tabbar)
corner(pill, 7); gradient(pill, PAL.violet, PAL.indigo, 20)
local tabBtns = {}
local pages = {}
local activeTab = 1

-- content area
local content = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,-28,1,-150),
	Position=UDim2.new(0,14,0,144), ClipsDescendants=true, ZIndex=3}, win)

local function makePage()
	local sf = mk("ScrollingFrame", {BackgroundTransparency=1, BorderSizePixel=0, Visible=false,
		Size=UDim2.new(1,0,1,0), CanvasSize=UDim2.new(0,0,0,0), ScrollBarThickness=3,
		ScrollBarImageColor3=C(PAL.line), ZIndex=3}, content)
	local list = mk("UIListLayout", {Padding=UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder}, sf)
	track(list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize = UDim2.new(0,0,0, list.AbsoluteContentSize.Y + 8)
	end))
	return sf
end
for i = 1, #TABS do pages[i] = makePage() end

local function setTab(i)
	activeTab = i
	for j, p in ipairs(pages) do p.Visible = (j == i) end
	for j, b in ipairs(tabBtns) do
		TweenService:Create(b, TI_FAST, {TextColor3 = (j==i) and C(PAL.text) or C(PAL.dim)}):Play()
	end
	local w = tabbar.AbsoluteSize.X - 8
	local each = w / #TABS
	TweenService:Create(pill, TI_PILL, {Position=UDim2.new(0, (i-1)*each, 0, 0), Size=UDim2.new(0, each, 1, 0)}):Play()
end

for i, name in ipairs(TABS) do
	local b = mk("TextButton", {BackgroundTransparency=1, AutoButtonColor=false,
		Size=UDim2.new(1/#TABS,0,1,0), Position=UDim2.new((i-1)/#TABS,0,0,0), Text=name,
		TextColor3=C(PAL.dim), Font=Enum.Font.GothamBold, TextSize=12, ZIndex=6}, tabbar)
	tabBtns[i] = b
	track(b.MouseButton1Click:Connect(function() setTab(i) end))
end

----------------------------------------------------------------------
-- GUI building blocks
----------------------------------------------------------------------
local function sectionLabel(parent, text, order)
	local l = mk("TextLabel", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,16),
		Text=string.upper(text), TextColor3=C(PAL.dim), Font=Enum.Font.GothamBold, TextSize=11,
		TextXAlignment=Enum.TextXAlignment.Left, LayoutOrder=order or 0, ZIndex=4}, parent)
	return l
end

local function card(parent, height, order)
	local c = mk("Frame", {BackgroundColor3=C(PAL.card), BorderSizePixel=0,
		Size=UDim2.new(1,0,0,height), LayoutOrder=order or 0, ZIndex=4}, parent)
	corner(c, 9); stroke(c, PAL.line, 1)
	mk("UIGradient", {Rotation=90, Color=ColorSequence.new(C("1C1C2A"), C("16161F"))}, c)
	return c
end

-- toggle row -> returns a setter to reflect external state
local function toggleRow(parent, label, desc, key, order, onChange)
	local c = card(parent, desc and 52 or 42, order)
	pad(c, 0)
	local txt = mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,14,0,desc and 8 or 0),
		Size=UDim2.new(1,-80,0, desc and 18 or 42), Text=label, TextColor3=C(PAL.text),
		Font=Enum.Font.GothamMedium, TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, c)
	if desc then
		mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,14,0,28),
			Size=UDim2.new(1,-80,0,16), Text=desc, TextColor3=C(PAL.dim), Font=Enum.Font.Gotham,
			TextSize=11, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, c)
	end
	local track_ = mk("TextButton", {BackgroundColor3=C(PAL.well), BorderSizePixel=0, AutoButtonColor=false,
		Size=UDim2.new(0,46,0,24), Position=UDim2.new(1,-60,0.5,-12), Text="", ZIndex=5}, c)
	corner(track_, 12); stroke(track_, PAL.line, 1)
	local knob = mk("Frame", {BackgroundColor3=C(PAL.dim), BorderSizePixel=0,
		Size=UDim2.new(0,18,0,18), Position=UDim2.new(0,3,0.5,-9), ZIndex=6}, track_)
	corner(knob, 9)
	local function render(v, instant)
		local ti = instant and TweenInfo.new(0) or TI_KNOB
		if v then
			TweenService:Create(track_, TI_FAST, {BackgroundColor3=C(PAL.on)}):Play()
			TweenService:Create(knob, ti, {Position=UDim2.new(1,-21,0.5,-9), BackgroundColor3=C("FFFFFF")}):Play()
		else
			TweenService:Create(track_, TI_FAST, {BackgroundColor3=C(PAL.well)}):Play()
			TweenService:Create(knob, ti, {Position=UDim2.new(0,3,0.5,-9), BackgroundColor3=C(PAL.dim)}):Play()
		end
	end
	track(track_.MouseButton1Click:Connect(function()
		Config[key] = not Config[key]
		render(Config[key])
		queueSave()
		if onChange then onChange(Config[key]) end
	end))
	render(Config[key], true)
	return render
end

-- slider row
local function sliderRow(parent, label, key, min, max, order)
	local c = card(parent, 54, order)
	mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,14,0,8),
		Size=UDim2.new(1,-80,0,18), Text=label, TextColor3=C(PAL.text), Font=Enum.Font.GothamMedium,
		TextSize=13, TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, c)
	local val = mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(1,-64,0,8),
		Size=UDim2.new(0,50,0,18), Text=tostring(Config[key]).."/s", TextColor3=C(PAL.cyan),
		Font=Enum.Font.Code, TextSize=13, TextXAlignment=Enum.TextXAlignment.Right, ZIndex=5}, c)
	local bar = mk("Frame", {BackgroundColor3=C(PAL.well), BorderSizePixel=0,
		Size=UDim2.new(1,-28,0,8), Position=UDim2.new(0,14,0,36), ZIndex=5}, c)
	corner(bar, 4); stroke(bar, PAL.line, 1)
	local fill = mk("Frame", {BackgroundColor3=C(PAL.violet), BorderSizePixel=0,
		Size=UDim2.new((Config[key]-min)/(max-min),0,1,0), ZIndex=6}, bar)
	corner(fill, 4); gradient(fill, PAL.violet, PAL.cyan, 0)
	local dragging = false
	local function setFromX(px)
		local rel = math.clamp((px - bar.AbsolutePosition.X)/bar.AbsoluteSize.X, 0, 1)
		local v = math.floor(min + rel*(max-min) + 0.5)
		Config[key] = v
		val.Text = tostring(v).."/s"
		fill.Size = UDim2.new((v-min)/(max-min),0,1,0)
		queueSave()
	end
	track(bar.InputBegan:Connect(function(io)
		if io.UserInputType==Enum.UserInputType.MouseButton1 or io.UserInputType==Enum.UserInputType.Touch then
			dragging=true setFromX(io.Position.X)
		end
	end))
	track(UserInput.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType==Enum.UserInputType.MouseMovement or io.UserInputType==Enum.UserInputType.Touch) then
			setFromX(io.Position.X)
		end
	end))
	track(UserInput.InputEnded:Connect(function(io)
		if io.UserInputType==Enum.UserInputType.MouseButton1 or io.UserInputType==Enum.UserInputType.Touch then dragging=false end
	end))
end

----------------------------------------------------------------------
-- PAGE 1: Main (live stats)
----------------------------------------------------------------------
do
	local p = pages[1]
	sectionLabel(p, "Live Stats", 1)
	local grid = mk("Frame", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,140), LayoutOrder=2, ZIndex=4}, p)
	local g = mk("UIGridLayout", {CellSize=UDim2.new(0.5,-4,0,44), CellPadding=UDim2.new(0,8,0,8),
		SortOrder=Enum.SortOrder.LayoutOrder}, grid)
	local statCards = {}
	local STATKEYS = {
		{"Money","Money",PAL.gold}, {"Crystals","Crystals",PAL.cyan},
		{"Rebirth","Rebirth",PAL.violet}, {"Prestige","Prestige",PAL.indigo},
		{"Ascension","Ascension",PAL.on}, {"Gems","Gems",PAL.bad},
	}
	for i, s in ipairs(STATKEYS) do
		local c = mk("Frame", {BackgroundColor3=C(PAL.card), BorderSizePixel=0, LayoutOrder=i, ZIndex=4}, grid)
		corner(c, 8); stroke(c, PAL.line, 1)
		mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,12,0,6), Size=UDim2.new(1,-16,0,12),
			Text=string.upper(s[1]), TextColor3=C(PAL.dim), Font=Enum.Font.GothamBold, TextSize=10,
			TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, c)
		local v = mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,12,0,20), Size=UDim2.new(1,-16,0,18),
			Text="0", TextColor3=C(s[3]), Font=Enum.Font.Code, TextSize=15,
			TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, c)
		statCards[s[2]] = v
	end
	sectionLabel(p, "Progress", 3)
	local prog = card(p, 76, 4)
	local clicksLbl = mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,14,0,10), Size=UDim2.new(1,-28,0,16),
		Text="Clicks → Ascension", TextColor3=C(PAL.sub), Font=Enum.Font.GothamMedium, TextSize=12,
		TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, prog)
	local clicksBar = mk("Frame", {BackgroundColor3=C(PAL.well), BorderSizePixel=0,
		Size=UDim2.new(1,-28,0,8), Position=UDim2.new(0,14,0,34), ZIndex=5}, prog)
	corner(clicksBar,4); stroke(clicksBar, PAL.line,1)
	local clicksFill = mk("Frame", {BackgroundColor3=C(PAL.on), BorderSizePixel=0, Size=UDim2.new(0,0,1,0), ZIndex=6}, clicksBar)
	corner(clicksFill,4); gradient(clicksFill, PAL.on, PAL.cyan, 0)
	local sessionLbl = mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,14,0,48), Size=UDim2.new(1,-28,0,18),
		Text="Session: 0 ores · 0 runes", TextColor3=C(PAL.dim), Font=Enum.Font.Gotham, TextSize=11,
		TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, prog)

	-- HUD refresh loop
	spawnLoop(function()
		if gui.Parent then
			for cur, lbl in pairs(statCards) do lbl.Text = fmt(currency(cur)) end
			local d = getData()
			local earnedClicks = 0
			if d and d.TotalCurrencyEarned then earnedClicks = tonumber(d.TotalCurrencyEarned.Clicks) or 0 end
			clicksFill.Size = UDim2.new(math.clamp(earnedClicks/250000,0,1),0,1,0)
			clicksLbl.Text = string.format("Clicks → Ascension   %s / 250K", fmt(earnedClicks))
			sessionLbl.Text = string.format("Session: %s ores · %d runes · %d clicks", fmt(stats.collected), stats.runes, stats.clicks)
		end
		task.wait(0.6)
	end)
end

----------------------------------------------------------------------
-- PAGE 2: Farm
----------------------------------------------------------------------
do
	local p = pages[2]
	sectionLabel(p, "Collection", 1)
	toggleRow(p, "Collect Ores", "Grabs every spawned cube each tick", "collect", 2)
	toggleRow(p, "Tycoon Auto-Sell", "Instantly sells tycoon drops for Gems", "tycoon", 3)
	sectionLabel(p, "Clicking", 4)
	toggleRow(p, "Click Farm", "Builds Clicks for the Ascension gate", "clicks", 5)
	sliderRow(p, "Click Rate", "clicksRate", 1, 120, 6)
	toggleRow(p, "Fire Stones", "Mines the Underworld fire stone", "fireStones", 7)
	sliderRow(p, "Fire Stone Rate", "fireRate", 1, 60, 8)
	sectionLabel(p, "Runes", 9)
	toggleRow(p, "Auto-Open Runes", "Rotates rune stations (teleports briefly)", "runes", 10)
end

----------------------------------------------------------------------
-- PAGE 3: Auto (upgrades / trees / totems)
----------------------------------------------------------------------
do
	local p = pages[3]
	sectionLabel(p, "Upgrades", 1)
	toggleRow(p, "Auto Upgrades", "Buys every board upgrade + automations", "upgrades", 2)
	toggleRow(p, "Upgrade Trees", "Tree1 + Skill Tree (unlocks islands)", "trees", 3)
	toggleRow(p, "Auto Totems", "Buys reset-protecting totems", "totems", 4)
	sectionLabel(p, "Positioning", 5)
	local parkCard = card(p, 46, 6)
	mk("TextLabel", {BackgroundTransparency=1, Position=UDim2.new(0,14,0,0), Size=UDim2.new(0,120,1,0),
		Text="Park Mode", TextColor3=C(PAL.text), Font=Enum.Font.GothamMedium, TextSize=13,
		TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, parkCard)
	local modes = {"Auto","CoreCrystals","CubeSpawner","Off"}
	local parkBtn = mk("TextButton", {BackgroundColor3=C(PAL.raise), BorderSizePixel=0, AutoButtonColor=false,
		Size=UDim2.new(0,150,0,30), Position=UDim2.new(1,-164,0.5,-15), Text=Config.park,
		TextColor3=C(PAL.cyan), Font=Enum.Font.GothamBold, TextSize=12, ZIndex=5}, parkCard)
	corner(parkBtn,8); stroke(parkBtn, PAL.line,1)
	track(parkBtn.MouseButton1Click:Connect(function()
		local idx = 1
		for i,m in ipairs(modes) do if m==Config.park then idx=i break end end
		Config.park = modes[(idx % #modes)+1]
		parkBtn.Text = Config.park
		queueSave()
	end))
end

----------------------------------------------------------------------
-- PAGE 4: Resets
----------------------------------------------------------------------
do
	local p = pages[4]
	sectionLabel(p, "Reset Ladder", 1)
	toggleRow(p, "Auto Rebirth", "Money → Rebirth", "rebirth", 2)
	toggleRow(p, "Auto Prestige", "Rebirth → Prestige", "prestige", 3)
	toggleRow(p, "Auto Ascension", "Prestige → Ascension", "ascension", 4)
	local sac = toggleRow(p, "Auto Sacrifice", "DESTRUCTIVE: wipes tycoon + Gems", "sacrifice", 5)
	sectionLabel(p, "Rank", 6)
	toggleRow(p, "Auto Rank Up", "Spends Level for LevelCrystal income", "rank", 7)
	-- danger highlight on sacrifice card
	local dangerNote = mk("TextLabel", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), LayoutOrder=8,
		Text="⚠ Sacrifice resets the whole tycoon. Off by default.", TextColor3=C(PAL.gold),
		Font=Enum.Font.Gotham, TextSize=11, TextWrapped=true, ZIndex=4}, p)
end

----------------------------------------------------------------------
-- PAGE 5: More (mine/daily/potions/codes/unload)
----------------------------------------------------------------------
do
	local p = pages[5]
	sectionLabel(p, "Passives", 1)
	toggleRow(p, "Collect Mine", "Banks mine cycles (Rainbow Crystals)", "mine", 2)
	toggleRow(p, "Daily Streak", "Claims the daily reward", "daily", 3)
	toggleRow(p, "Auto Potions", "Activates stored potions", "potions", 4)
	sectionLabel(p, "Codes", 5)
	local codeCard = card(p, 46, 6)
	local box = mk("TextBox", {BackgroundColor3=C(PAL.well), BorderSizePixel=0, ClearTextOnFocus=false,
		Size=UDim2.new(1,-86,0,30), Position=UDim2.new(0,12,0.5,-15), PlaceholderText="enter a code…",
		Text="", TextColor3=C(PAL.text), PlaceholderColor3=C(PAL.dim), Font=Enum.Font.Gotham, TextSize=12,
		TextXAlignment=Enum.TextXAlignment.Left, ZIndex=5}, codeCard)
	corner(box,7); stroke(box, PAL.line,1); pad(box,8)
	local addBtn = mk("TextButton", {BackgroundColor3=C(PAL.violet), BorderSizePixel=0, AutoButtonColor=false,
		Size=UDim2.new(0,60,0,30), Position=UDim2.new(1,-72,0.5,-15), Text="ADD",
		TextColor3=C("FFFFFF"), Font=Enum.Font.GothamBold, TextSize=12, ZIndex=5}, codeCard)
	corner(addBtn,7); gradient(addBtn, PAL.violet, PAL.indigo, 20)
	local codesLbl = mk("TextLabel", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,16), LayoutOrder=7,
		Text="Saved: "..tostring(#Config.codes), TextColor3=C(PAL.dim), Font=Enum.Font.Gotham, TextSize=11,
		TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4}, p)
	track(addBtn.MouseButton1Click:Connect(function()
		local c = box.Text:gsub("%s+","")
		if c ~= "" then
			table.insert(Config.codes, c)
			box.Text = ""
			codesLbl.Text = "Saved: "..tostring(#Config.codes)
			queueSave()
			pcall(function() CodesService.RE.RedeemCode:FireServer(c) end)
		end
	end))

	sectionLabel(p, "Session", 8)
	local unloadBtn = mk("TextButton", {BackgroundColor3=C(PAL.card), BorderSizePixel=0, AutoButtonColor=false,
		Size=UDim2.new(1,0,0,40), LayoutOrder=9, Text="UNLOAD SUITE", TextColor3=C(PAL.bad),
		Font=Enum.Font.GothamBold, TextSize=13, ZIndex=4}, p)
	corner(unloadBtn,9); stroke(unloadBtn, PAL.bad, 1, 0.4)
	track(unloadBtn.MouseButton1Click:Connect(function() Suite.Unload() end))
	mk("TextLabel", {BackgroundTransparency=1, Size=UDim2.new(1,0,0,16), LayoutOrder=10,
		Text="state auto-saves · restores on next launch", TextColor3=C(PAL.dim), Font=Enum.Font.Gotham,
		TextSize=10, ZIndex=4}, p)
end

----------------------------------------------------------------------
-- Master switch behaviour
----------------------------------------------------------------------
local function renderMaster()
	if Config.master then
		masterLbl.Text = "RUNNING"
		masterLbl.TextColor3 = C("FFFFFF")
		TweenService:Create(master, TI_FAST, {BackgroundColor3=C(PAL.on)}):Play()
		TweenService:Create(statusDot, TI_FAST, {BackgroundColor3=C(PAL.on)}):Play()
		statusText.Text = "Running — full progression"
		statusText.TextColor3 = C(PAL.text)
	else
		masterLbl.Text = "START"
		masterLbl.TextColor3 = C(PAL.sub)
		TweenService:Create(master, TI_FAST, {BackgroundColor3=C(PAL.raise)}):Play()
		TweenService:Create(statusDot, TI_FAST, {BackgroundColor3=C(PAL.dim)}):Play()
		statusText.Text = "Stopped"
		statusText.TextColor3 = C(PAL.sub)
	end
end
track(master.MouseButton1Click:Connect(function()
	Config.master = not Config.master
	renderMaster()
	queueSave()
	if Config.master then bootOnce() end
end))

----------------------------------------------------------------------
-- Dragging
----------------------------------------------------------------------
do
	local dragging, dragStart, startPos = false, nil, nil
	track(header.InputBegan:Connect(function(io)
		if io.UserInputType==Enum.UserInputType.MouseButton1 or io.UserInputType==Enum.UserInputType.Touch then
			dragging=true dragStart=io.Position startPos=shadowHolder.Position
		end
	end))
	track(UserInput.InputChanged:Connect(function(io)
		if dragging and (io.UserInputType==Enum.UserInputType.MouseMovement or io.UserInputType==Enum.UserInputType.Touch) then
			local d = io.Position - dragStart
			shadowHolder.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
		end
	end))
	track(UserInput.InputEnded:Connect(function(io)
		if io.UserInputType==Enum.UserInputType.MouseButton1 or io.UserInputType==Enum.UserInputType.Touch then
			if dragging then
				dragging=false
				local pos = shadowHolder.Position
				Config.winPos = {pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset}
				queueSave()
			end
		end
	end))
end

----------------------------------------------------------------------
-- Minimize / close
----------------------------------------------------------------------
local minimized = Config.minimized
local function renderMin()
	win.Visible = not minimized
	-- keep a small restore handle when minimized
end
local handle
local function makeHandle()
	handle = mk("TextButton", {BackgroundColor3=C(PAL.panel), BorderSizePixel=0, AutoButtonColor=false,
		Size=UDim2.new(0,150,0,40), Position=shadowHolder.Position, Text="Ore Suite",
		TextColor3=C(PAL.text), Font=Enum.Font.GothamBold, TextSize=13, Visible=minimized, ZIndex=3}, gui)
	corner(handle, 10); brandStroke(handle, 1.2)
	local hgemBox = mk("Frame", {BackgroundColor3=C(PAL.violet), BorderSizePixel=0,
		Size=UDim2.new(0,22,0,22), Position=UDim2.new(0,12,0.5,-11), ZIndex=4}, handle)
	corner(hgemBox, 6); gradient(hgemBox, PAL.violet, PAL.cyan, 35)
	local hgem = mk("Frame", {BackgroundColor3=C("FFFFFF"), BackgroundTransparency=0.08, BorderSizePixel=0,
		AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.5,0), Size=UDim2.new(0,9,0,9),
		Rotation=45, ZIndex=5}, hgemBox)
	mk("UICorner", {CornerRadius=UDim.new(0,2)}, hgem)
	track(handle.MouseButton1Click:Connect(function()
		minimized=false Config.minimized=false handle.Visible=false win.Visible=true queueSave()
	end))
end
makeHandle()
track(btnMin.MouseButton1Click:Connect(function()
	minimized=true Config.minimized=true win.Visible=false
	handle.Position = shadowHolder.Position
	handle.Visible=true queueSave()
end))
track(btnClose.MouseButton1Click:Connect(function() Suite.Unload() end))

----------------------------------------------------------------------
-- Unload
----------------------------------------------------------------------
function Suite.Unload()
	if not Alive then return end
	Alive = false
	saveConfig()
	for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
	table.clear(Connections)
	task.delay(0.1, function() pcall(function() gui:Destroy() end) end)
	ENV.__OreIncrementalSuite = nil
end

----------------------------------------------------------------------
-- Init UI state
----------------------------------------------------------------------
renderMaster()
setTab(1)
win.Visible = not minimized
if handle then handle.Visible = minimized end
if Config.master then booted = false end -- bootOnce fires from the boot loop

-- restore window size each frame guard against AbsoluteSize 0 at start
task.defer(function() setTab(activeTab) end)
