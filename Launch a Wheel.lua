--[[
	[10M!] Launch a Wheel! — Auto Farm
	placeId: 18916922845
	by tg: @sigmatik323

	Функции:
	- Auto Train (Power): спам TrainingService.RE.Train("W|S") 15-18/с с разогревом и джиттером,
	  авто-выбор максимальной рабочей станции (валидация по дельте Power из серверных пушей),
	  авто-бенчмарк против серверного авто-трейна TrainingService.RE.Start (нулевой спам) — выбирает лучший режим.
	- Auto Throw (Cash): Throw -> Finish строго 1:1, цикл 10.5-11.2s (серверный кулдаун 10s), подтверждение
	  прироста Cash по пушу, один ретрай Finish. Дистанция 100% серверная = f(Power) + ~1-2% RNG:
	  аргументы Throw/Finish сервер игнорирует (проверено вживую junk-спуфом) — качается только через Power.
	- Auto Buy: жадная стейт-машина по приоритетам МИР > КОЛЕСО (по Required-цепочке) > PetEquip >
	  PowerBoost/CashBoost/TrainSpeed > RebirthButton, одно действие за тик, каждое подтверждается
	  следующим серверным пушем. Saving-mode на мир. Форма аргумента Upgrade подтверждается первым вызовом.
	- Auto Hatch Eggs: HatchEgg(<лучшее Cash-яйцо>, "Triple") на <=15% Cash, шаг >=4.6s, EquipBest с дебаунсом.
	- Event Egg (10M): авто-открытие ивентового "10M Egg" (HatchEgg, Triple/Octo по геймпассу) в рамках
	  бюджета % Cash, подтверждение по пушу, авто-стоп после MiscConfig.EventEndTimestamp
	  (охота на Midnight Kitty 0.001% x4,000,000 и Masquerade 0.0002%).
	- Redeem Codes + Free Eggs: прогон 46 промокодов (CodesService.RF.Claim, пауза 6s), гейт по каждому
	  коду отдельно (свежедобавленные коды доклеймятся даже после первого прогона), затем открытие всех
	  Timeless/Void Egg (OpenExclusiveEgg, шаг 4.6s) + EquipBest. Прогресс персистится.
	- Auto Daily Spin: SpinsService.RE.Spin раз в 24ч по DailySpinClaimedTime из профиля.
	- Auto Claim Rewards: DailyRewards/Chest/Achievement/Seasonpass .RE.Claim раз в ~12 мин;
	  PlaytimeReward — ОТДЕЛЬНЫЙ поллер (31s) по атрибуту игрока PlaytimeReward >= 900s: слепой Claim
	  до готовности — тихий серверный no-op, поэтому клейм строго по готовности (проверено вживую).
	- Floating Quick Bar: перетаскиваемый пузырь (gethui/CoreGui) с быстрыми тумблерами Train/Throw/Buy/Egg/Menu —
	  дёргают те же :Start()/:Stop() через Window:SetModuleEnabled (единый стейт RUNNING, меню синхронно),
	  снимается Unload'ом и закрытием окна.
	- Auto Potions: InventoryService.RE.Use("<Potion>", 1) под активные фармы, с подтверждением декремента.
	- Auto Class Roll: ClassesService.RE.Roll до выпадения Wheelborn / The Insane Wheeler, затем Equip + StopAuto.
	- Auto Rebirth: одноразовая туториал-проба (гейт фич) + steady-state по регринду Power, подтверждение по счётчику.
	- Anti-AFK, глобальный лимитер remotes (жёсткий потолок 400/с), персист настроек между перезапусками,
	  устойчивость к респавну, Unload с полным снятием коннектов.

	Вся логика решений — ТОЛЬКО по серверному зеркалу профиля (HandlerService.RE.Fruits push каждые ~2s).
	Балансом считается ТОЛЬКО top-level Cash (не TotalCash / не Tutorial.Cash).
	Никаких CFrame-телепортов: смена мира только MapsService.RE.Teleport.
	Admin*-сервисы не трогаются вообще.
]]

local PLACE_ID = 18916922845

--============================ CLEANUP PREVIOUS ============================
local SharedEnv = (getgenv and getgenv()) or _G
if SharedEnv.SigmatikLaunchWheelState and SharedEnv.SigmatikLaunchWheelState.Stop then
	pcall(SharedEnv.SigmatikLaunchWheelState.Stop)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local function elevate()
	pcall(function()
		local set = setthreadidentity or setidentity or set_thread_identity or (syn and syn.set_thread_identity)
		if set then set(8) end
	end)
end
elevate()

--============================ GUI LIBRARY ============================
local Library
do
	local ok, lib = pcall(function()
		return loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/sigmatik_ui_library.lua"))()
	end)
	if not ok or type(lib) ~= "table" then
		-- fallback: local copy in executor workspace
		ok, lib = pcall(function() return loadstring(readfile("sigmatik_ui_library.lua"))() end)
	end
	if not ok or type(lib) ~= "table" then
		warn("[Launch a Wheel] failed to load Sigmatik UI library")
		return
	end
	Library = lib
end

--============================ KNIT SERVICES ============================
local KnitServices
do
	local ok, res = pcall(function()
		return ReplicatedStorage:WaitForChild("Library", 20):WaitForChild("Knit", 15):WaitForChild("Services", 15)
	end)
	if not ok or not res then
		warn("[Launch a Wheel] Knit Services folder not found — wrong game?")
		return
	end
	KnitServices = res
end

--============================ STATE ============================
local State = {
	Alive = true,
	Connections = {},
	CharConnections = {},
	Paragraphs = {},		-- name -> { control, text }
	Window = nil,
	SpendBusy = false,
	LastSpendSerial = 0,	-- push serial at last spend; next spend requires a fresher push
	MaxCashSeen = 0,
	SessionStart = os.clock(),
	RejoinProbed = {},		-- AutoTrain/AutoShoot/AutoHatch fired once per session
}
SharedEnv.SigmatikLaunchWheelState = State

local RUNNING = {}

--============================ PERSISTENCE ============================
local CONFIG_FILE = "LaunchAWheel_" .. tostring(PLACE_ID) .. ".json"
local hasFS = (typeof(writefile) == "function") and (typeof(readfile) == "function")
local Config = { modules = {}, controls = {}, persist = {} }
do
	local exists = hasFS and ((typeof(isfile) ~= "function") or select(2, pcall(isfile, CONFIG_FILE)) == true)
	if hasFS and exists then
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
		if ok and type(data) == "table" then
			Config.modules = type(data.modules) == "table" and data.modules or {}
			Config.controls = type(data.controls) == "table" and data.controls or {}
			Config.persist = type(data.persist) == "table" and data.persist or {}
		end
	end
end
local saveScheduled = false
local function saveConfig()
	if not hasFS then return end
	if saveScheduled then return end
	saveScheduled = true
	task.delay(0.5, function()
		saveScheduled = false
		pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end)
	end)
end
local function cfgCtl(key, default)
	local v = Config.controls[key]
	if v == nil then return default end
	return v
end
local Persist = Config.persist
Persist.redeemed = type(Persist.redeemed) == "table" and Persist.redeemed or {}

--============================ HELPERS ============================
local function num(v) return tonumber(v) or 0 end

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No" }
local function fmt(n)
	n = tonumber(n) or 0
	local neg = n < 0
	n = math.abs(n)
	if n >= 1e33 then
		return (neg and "-" or "") .. string.format("%.2e", n)
	end
	if n < 1000 then
		local s = (n == math.floor(n)) and tostring(math.floor(n)) or string.format("%.1f", n)
		return (neg and "-" or "") .. s
	end
	local i = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return (neg and "-" or "") .. string.format("%.2f%s", n / (1000 ^ i), SUFFIX[i + 1])
end

--============================ RATE LIMITER (hard <=400/s total) ============================
local RATE = { cap = math.clamp(cfgCtl("rate_limit", 80), 30, 400), tokens = 80, last = os.clock() }
RATE.tokens = RATE.cap
local function rateConsume()
	local now = os.clock()
	RATE.tokens = math.min(RATE.cap, RATE.tokens + (now - RATE.last) * RATE.cap)
	RATE.last = now
	if RATE.tokens >= 1 then
		RATE.tokens = RATE.tokens - 1
		return true
	end
	return false
end
local function waitToken()
	local t = 0
	while State.Alive and not rateConsume() do
		task.wait(0.01)
		t = t + 0.01
		if t > 4 then break end
	end
end

--============================ REMOTE RESOLUTION (Knit path) ============================
local remoteCache = {}
local function getRemote(svcName, kind, remoteName)
	local key = svcName .. "/" .. kind .. "/" .. remoteName
	local cached = remoteCache[key]
	if cached and cached.Parent then return cached end
	local ok, remote = pcall(function()
		local svc = KnitServices:FindFirstChild(svcName) or KnitServices:WaitForChild(svcName, 3)
		if not svc then return nil end
		local folder = svc:FindFirstChild(kind) or svc:WaitForChild(kind, 2)
		if not folder then return nil end
		return folder:FindFirstChild(remoteName) or folder:WaitForChild(remoteName, 2)
	end)
	if ok and remote then
		remoteCache[key] = remote
		return remote
	end
	return nil
end

-- fire a RemoteEvent through the global budget; args exactly as passed
local function fireRE(svcName, remoteName, ...)
	local remote = getRemote(svcName, "RE", remoteName)
	if not remote then return false end
	waitToken()
	local args = table.pack(...)
	local ok = pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end)
	return ok
end

-- invoke a RemoteFunction with timeout guard (InvokeServer can hang)
local function invokeRF(svcName, remoteName, timeout, ...)
	local remote = getRemote(svcName, "RF", remoteName)
	if not remote then return false, nil end
	waitToken()
	local args = table.pack(...)
	local done, okRes, res = false, false, nil
	task.spawn(function()
		local ok, a = pcall(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end)
		okRes, res = ok, a
		done = true
	end)
	local t0 = os.clock()
	while State.Alive and not done and os.clock() - t0 < (timeout or 8) do
		task.wait(0.1)
	end
	return done and okRes, res
end

--============================ SERVER MIRROR (HandlerService.RE.Fruits) ============================
-- Full profile pushed every ~2s. Full replacement, never a delta. NEVER FireServer on it.
local Mirror = {
	profile = nil,
	serial = 0,
	at = 0,
	prevAt = 0,
	powerDelta = 0,
	cashDelta = 0,
	powerRate = nil,	-- EMA Power/sec from TotalPower (rebirth-proof)
	cashRate = nil,		-- EMA Cash/sec from TotalCash
	listeners = {},
}

local function Cash()
	local p = Mirror.profile
	return p and num(p.Cash) or 0 -- top-level Cash ONLY (never TotalCash/EventCash/Tutorial.Cash)
end
local function Power()
	local p = Mirror.profile
	return p and num(p.Power) or 0
end

local function acceptProfile(data)
	if type(data) ~= "table" then return end
	if data.Cash == nil and data.Power == nil and data.Items == nil then return end -- not the profile shape
	local now = os.clock()
	local prev = Mirror.profile
	local dt = Mirror.at > 0 and (now - Mirror.at) or 0
	if prev then
		Mirror.powerDelta = num(data.Power) - num(prev.Power)
		Mirror.cashDelta = num(data.Cash) - num(prev.Cash)
		if dt > 0.3 then
			local dTp = num(data.TotalPower) - num(prev.TotalPower)
			if dTp >= 0 then
				local inst = dTp / dt
				Mirror.powerRate = Mirror.powerRate and (Mirror.powerRate * 0.7 + inst * 0.3) or inst
			end
			local dTc = num(data.TotalCash) - num(prev.TotalCash)
			if dTc >= 0 then
				local inst = dTc / dt
				Mirror.cashRate = Mirror.cashRate and (Mirror.cashRate * 0.7 + inst * 0.3) or inst
			end
		end
	end
	Mirror.profile = data
	Mirror.prevAt = Mirror.at
	Mirror.at = now
	Mirror.serial = Mirror.serial + 1
	if num(data.Cash) > State.MaxCashSeen then State.MaxCashSeen = num(data.Cash) end
	for _, fn in ipairs(Mirror.listeners) do
		pcall(fn)
	end
end

do
	local fruits = getRemote("HandlerService", "RE", "Fruits")
	if fruits then
		table.insert(State.Connections, fruits.OnClientEvent:Connect(function(a1)
			acceptProfile(a1)
		end))
	else
		warn("[Launch a Wheel] HandlerService.RE.Fruits not found — mirror unavailable")
	end
end

-- one getData on start (and used once more per minute only if the mirror goes stale)
local lastGetData = 0
local function pullProfileOnce()
	if os.clock() - lastGetData < 30 then return end
	lastGetData = os.clock()
	task.spawn(function()
		local ok, res = invokeRF("HandlerService", "getData", 10)
		if ok and type(res) == "table" then acceptProfile(res) end
	end)
end
pullProfileOnce()

-- wait until at least one fresh push lands after `serialFloor`
local function waitFreshPush(serialFloor, timeout)
	local t0 = os.clock()
	while State.Alive and Mirror.serial <= serialFloor and os.clock() - t0 < (timeout or 6) do
		task.wait(0.15)
	end
	return Mirror.serial > serialFloor
end

--============================ TASK BAG ============================
local function bag()
	local b = { conns = {}, alive = true }
	function b:track(c)
		table.insert(self.conns, c)
		return c
	end
	function b:every(interval, fn)
		local th = task.spawn(function()
			while self.alive and State.Alive do
				pcall(fn)
				task.wait(interval)
			end
		end)
		table.insert(self.conns, th)
	end
	function b:kill()
		self.alive = false
		for _, c in ipairs(self.conns) do
			local t = typeof(c)
			if t == "RBXScriptConnection" then
				pcall(function() c:Disconnect() end)
			elseif t == "thread" then
				pcall(task.cancel, c)
			elseif t == "function" then
				pcall(c)
			end
		end
		self.conns = {}
	end
	return b
end

--============================ STATUS PARAGRAPH BINDING ============================
local function setStatus(name, text)
	local entry = State.Paragraphs[name]
	if not entry then
		State.Paragraphs[name] = { pending = text }
		return
	end
	entry.pending = text
	if entry.control then entry.control.Content = text end
	if entry.text and entry.text.Parent then entry.text.Text = text end
end

--============================ CONFIG DISCOVERY ============================
-- Shared data ModuleScripts (prices/requirements). Searched by exact known names, required in pcall.
-- Everything degrades gracefully when a config is missing.
local ConfigModules = {}
do
	local WANTED = {
		TrainingConfig = true, ItemsConfig = true, MapsConfig = true, UpgradesConfig = true,
		EggsConfig = true, MiscConfig = true, ClassesConfig = true, PetsConfig = true,
	}
	task.spawn(function()
		local ok, descendants = pcall(function() return ReplicatedStorage:GetDescendants() end)
		if not ok then return end
		for _, inst in ipairs(descendants) do
			if not State.Alive then return end
			if inst:IsA("ModuleScript") and WANTED[inst.Name] and ConfigModules[inst.Name] == nil then
				task.spawn(function()
					local okR, mod = pcall(require, inst)
					if okR and type(mod) == "table" then
						ConfigModules[inst.Name] = mod
					end
				end)
			end
		end
	end)
end

--============================ WORLDS ============================
-- Verified fallback from dumps (config overrides when found).
local WORLD_FALLBACK = {
	[2] = { price = 6.5e8,  req = "Shuriken" },
	[3] = { price = 1e15,   req = "Skull" },
	[4] = { price = 1e24,   req = "Tractor Wheel" },
	[5] = { price = 2e29,   req = "Blue PufferFish" },
	[6] = { price = 1e36,   req = "UFO" },
}
local function worldInfo(w)
	local mc = ConfigModules.MapsConfig
	if type(mc) == "table" then
		local def = mc[w] or mc[tostring(w)]
		if type(def) == "table" then
			local price = tonumber(def.Price or def.Cost)
			local req = def.RequiredItem or def.Required or def.Item
			if price and type(req) == "string" then
				return { price = price, req = req }
			end
		end
	end
	return WORLD_FALLBACK[w]
end
local function maxOwnedWorld()
	local p = Mirror.profile
	local maxW = 1
	local maps = p and p.Maps
	if type(maps) == "table" then
		for k, v in pairs(maps) do
			if v == true or (type(v) == "table") then
				local n = tonumber(k)
				if n and n > maxW then maxW = n end
			end
		end
	end
	return maxW
end
local function worldArg(w)
	if Persist.world_form == "number" then return w end
	return tostring(w) -- Maps keys are strings; string form first, number fallback learned on Buy
end
local function ownsItem(name)
	local p = Mirror.profile
	local items = p and p.Items
	return type(items) == "table" and items[name] == true
end

local lastTeleportW = nil
local function teleportToWorld(w)
	if w <= 1 then return end
	fireRE("MapsService", "Teleport", worldArg(w))
	lastTeleportW = w
end

--============================ WHEELS (ItemsConfig) ============================
local function wheelDefs()
	local ic = ConfigModules.ItemsConfig
	if type(ic) ~= "table" then return nil end
	local out = {}
	for name, def in pairs(ic) do
		if type(name) == "string" and type(def) == "table" then
			local mults = def.Multipliers
			out[name] = {
				price = tonumber(def.Price or def.Cost),
				required = (type(def.Required) == "string" and def.Required)
					or (type(def.RequiredItem) == "string" and def.RequiredItem) or nil,
				cashMult = (type(mults) == "table" and tonumber(mults.Cash)) or nil,
				robux = def.Robux == true, -- flag only; "Robux Wheel" by NAME is a cash wheel!
			}
		end
	end
	return out
end

-- Next wheel to buy: walk the Required chain backwards from the next world's RequiredItem.
-- Handles the W1 fork automatically (Purple Sport dead-end never sits on the path).
local function nextWheelTarget()
	local defs = wheelDefs()
	if not defs then return nil, "no ItemsConfig" end
	local function chainFirstUnowned(goal)
		local cur, guard, first = goal, 0, nil
		while cur and guard < 60 do
			guard = guard + 1
			if ownsItem(cur) then break end
			local d = defs[cur]
			if not d or d.robux or not d.price then return nil end -- broken/robux link -> abort path
			first = { name = cur, def = d }
			cur = d.required
		end
		return first
	end
	local nw = maxOwnedWorld() + 1
	local wd = worldInfo(nw)
	if wd and defs[wd.req] and not ownsItem(wd.req) then
		local target = chainFirstUnowned(wd.req)
		if target then return target end
	end
	-- top world / no path: cheapest affordable-ish unowned cash wheel whose prerequisite is owned
	local best
	for name, d in pairs(defs) do
		if not ownsItem(name) and not d.robux and d.price and d.cashMult
			and (d.required == nil or ownsItem(d.required)) then
			if not best or d.price < best.def.price then
				best = { name = name, def = d }
			end
		end
	end
	return best
end
local function equippedCashMult()
	local p = Mirror.profile
	local eq = p and p.EquippedItem
	if type(eq) ~= "string" then return 0 end
	local defs = wheelDefs()
	local d = defs and defs[eq]
	return (d and d.cashMult) or 0
end

--============================ UPGRADES ============================
local UPG_FALLBACK = {
	PetEquip = { 1e5, 1e9, 2.5e18 },
	RebirthButton = { 800, 2000, 6500 },
	CashBoost = { 1000 },
	PowerBoost = { 550 },
	TrainSpeed = { 15000 },
}
local UPG_CAPS = { CashBoost = 40, PowerBoost = 40, TrainSpeed = 10, PetEquip = 3, RebirthButton = 9 }

local function upgLevel(track)
	local p = Mirror.profile
	local u = p and p.Upgrades
	return (type(u) == "table" and num(u[track])) or 0
end
-- price of level `lvl` (1-based next level), defensively across config shapes
local function upgPrice(track, lvl)
	local uc = ConfigModules.UpgradesConfig
	local def = type(uc) == "table" and uc[track]
	if type(def) == "table" then
		local candidates = { def.Prices, def.Price, def.Costs, def.Cost, def }
		for _, src in ipairs(candidates) do
			if type(src) == "table" then
				local v = src[lvl] or src[tostring(lvl)]
				if type(v) == "number" then return v end
				if type(v) == "table" then
					local pv = tonumber(v.Price or v.Cost)
					if pv then return pv end
				end
			end
		end
	end
	local fb = UPG_FALLBACK[track]
	return fb and fb[lvl] or nil
end

-- Argument-form confirmation: first Upgrade call must be observed bumping the level in the push.
-- Until confirmed, only single probes are allowed (no blind auto-spam).
local UpgradeState = {
	form = Persist.upgrade_form, -- "string" | "table" | "string1" | nil
	probing = false,
	broken = Persist.upgrade_broken == true,
}
local function sendUpgrade(track, form)
	if form == "table" then
		return fireRE("UpgradesService", "Upgrade", { track })
	elseif form == "string1" then
		return fireRE("UpgradesService", "Upgrade", track, 1)
	end
	return fireRE("UpgradesService", "Upgrade", track)
end
local function doUpgrade(track)
	if UpgradeState.broken then return false end
	if UpgradeState.form then
		State.LastSpendSerial = Mirror.serial
		sendUpgrade(track, UpgradeState.form)
		return true
	end
	if UpgradeState.probing then return false end
	UpgradeState.probing = true
	State.LastSpendSerial = Mirror.serial
	task.spawn(function()
		local before = upgLevel(track)
		for _, form in ipairs({ "string", "table", "string1" }) do
			if not State.Alive then break end
			local s = Mirror.serial
			sendUpgrade(track, form)
			waitFreshPush(s, 5)
			waitFreshPush(Mirror.serial, 3) -- give it a 2nd push
			if upgLevel(track) > before then
				UpgradeState.form = form
				Persist.upgrade_form = form
				saveConfig()
				setStatus("Buy Status", "Upgrade form confirmed: " .. form)
				UpgradeState.probing = false
				return
			end
		end
		-- no form worked with money in hand -> stop trying this session, retry next session
		UpgradeState.broken = true
		setStatus("Buy Status", "Upgrade no-op in all forms — auto-upgrades paused")
		UpgradeState.probing = false
	end)
	return true
end

--============================ EGGS ============================
local function eggList()
	local ec = ConfigModules.EggsConfig
	if type(ec) ~= "table" then return nil end
	local out = {}
	local maxW = maxOwnedWorld()
	for name, def in pairs(ec) do
		if type(name) == "string" and type(def) == "table" then
			local price = tonumber(def.Price or def.Cost)
			local isRobux = def.Robux == true or def.RobuxOnly == true
			local isExclusive = def.Exclusive == true or name:find("Timeless") ~= nil or name:find("Void") ~= nil
			local w = tonumber(def.World or def.Map)
			if price and price > 0 and not isRobux and not isExclusive and (w == nil or w <= maxW) then
				table.insert(out, { name = name, price = price })
			end
		end
	end
	table.sort(out, function(a, b) return a.price < b.price end)
	return out
end
local function petCount()
	local p = Mirror.profile
	local pets = p and p.Pets
	if type(pets) ~= "table" then return 0 end
	local c = 0
	for _ in pairs(pets) do c = c + 1 end
	return c
end
local function petStack()
	local p = Mirror.profile
	local eq = p and p.EquippedPets
	local pets = p and p.Pets
	if type(eq) ~= "table" or type(pets) ~= "table" then return nil end
	local stack = 1
	for _, id in pairs(eq) do
		local pet = (type(id) == "table" and id) or pets[id]
		local m = type(pet) == "table" and tonumber(pet.Multiplier)
		if m and m > 1 then stack = stack + (m - 1) end
	end
	return stack
end
local function inventoryCount(name)
	local p = Mirror.profile
	local inv = p and p.Inventory
	if type(inv) ~= "table" then return 0 end
	local v = inv[name]
	if type(v) == "number" then return v end
	if type(v) == "table" then
		local c = tonumber(v.Count or v.Amount or v.Quantity)
		if c then return c end
		return #v
	end
	return 0
end

local lastEquipBestAt = 0
local lastEquipBestCount = -1
local function equipBest(force)
	local count = petCount()
	if not force then
		if count == lastEquipBestCount then return end
		if os.clock() - lastEquipBestAt < 20 then return end
	end
	lastEquipBestAt = os.clock()
	lastEquipBestCount = count
	fireRE("PetsService", "EquipBest") -- VERIFIED: no args
end

--============================ SAVING MODE (shared) ============================
local function savingModeActive()
	if cfgCtl("buy_saving", true) ~= true then return false, nil end
	local nw = maxOwnedWorld() + 1
	local wd = worldInfo(nw)
	if wd and ownsItem(wd.req) and Cash() >= wd.price * 0.30 then
		return true, nw
	end
	return false, nil
end

-- one-shot Rejoin gamepass-auto probe (harmless single no-op if gated); never repeated in-session
local function probeRejoinAuto(name)
	if State.RejoinProbed[name] then return end
	State.RejoinProbed[name] = true
	if cfgCtl("probe_rejoin", true) ~= true then return end
	fireRE("RejoinService", name, true)
end

--============================ TRAIN FARM (Power) ============================
-- Manual: Train:FireServer("W|S") — ONE pipe string, warmup ~1/s -> 15-18/s over ~20 taps,
-- jitter 0.055-0.08s, stream is never interrupted (buff decays otherwise).
-- Server: Start("W|S") once = server-side auto train, Stop() to end (zero spam surface).
-- Mode "auto" benchmarks both once and persists the winner.
local TrainFarm = {
	B = nil,
	w = nil, s = nil,
	warm = 0,
	lastTapAt = 0,
	tapsSincePush = 0,
	failPushes = 0,
	okPushes = 0,
	lastProbeUpAt = 0,
	probing = false,        -- true while testing one station up (blind mode)
	serverActive = false,
	benchmarking = false,
	tapsPerSec = math.clamp(cfgCtl("train_tps", 16), 10, 18),
	mode = cfgCtl("train_mode", "auto"), -- "auto" | "manual" | "server"
	status = "idle",
}

local function stationInfo(w, s)
	local tc = ConfigModules.TrainingConfig
	if type(tc) ~= "table" then return nil end
	local wt = tc[w] or tc[tostring(w)]
	local st = wt and (wt[s] or wt[tostring(s)])
	if st == nil then st = tc[tostring(w) .. "|" .. tostring(s)] end
	if type(st) ~= "table" then return nil end
	local req = st.Required or st.Require
	local reqPower = (type(req) == "table" and tonumber(req.Power)) or tonumber(st.RequiredPower) or 0
	return { increment = tonumber(st.Increment) or 0, reqPower = reqPower }
end
local function stationCount(w)
	if type(ConfigModules.TrainingConfig) ~= "table" then return 12 end
	local cnt = 0
	for i = 1, 30 do
		if stationInfo(w, i) then cnt = i end
	end
	return cnt > 0 and cnt or 12
end

function TrainFarm:pickStation()
	local w = maxOwnedWorld()
	local cnt = stationCount(w)
	local s = cnt -- blind mode: start at the top and walk down on zero-delta
	if type(ConfigModules.TrainingConfig) == "table" then
		local pw = Power()
		s = 1
		-- highest station with Required.Power <= Power (Rebirth gate is NOT enforced — proven)
		for i = cnt, 1, -1 do
			local info = stationInfo(w, i)
			if info and info.reqPower <= pw then
				s = i
				break
			end
		end
	end
	return w, s
end

function TrainFarm:setStation(w, s, why)
	if self.w == w and self.s == s then return end
	self.w, self.s = w, s
	self.failPushes, self.okPushes, self.tapsSincePush = 0, 0, 0
	Config.controls.train_station = tostring(w) .. "|" .. tostring(s)
	saveConfig()
	self.status = string.format("station %d|%d (%s)", w, s, why or "select")
	if self.serverActive then -- restart server auto-train on the new station
		fireRE("TrainingService", "Stop")
		task.wait(0.3)
		fireRE("TrainingService", "Start", tostring(w) .. "|" .. tostring(s))
	end
end

function TrainFarm:stepDown()
	if not self.w or not self.s then return end
	if self.probing then
		-- probe of s+1 failed -> return to the proven station
		self.probing = false
		self:setStation(self.w, math.max(1, self.s - 1), "probe fail")
		self.lastProbeUpAt = os.clock() + 60 -- extra backoff after a failed probe
		return
	end
	if self.s > 1 then
		self:setStation(self.w, self.s - 1, "delta=0")
	elseif self.w > 1 then
		local nw = self.w - 1
		self:setStation(nw, stationCount(nw), "world down")
		teleportToWorld(nw)
	end
end

function TrainFarm:onPush()
	if not RUNNING.train or not self.w then return end
	local streaming = self.serverActive or (os.clock() - self.lastTapAt < 2)
	if not streaming then return end
	local delta = Mirror.powerDelta
	local enough = self.serverActive or self.tapsSincePush >= 5
	if enough then
		if delta <= 0 then
			self.failPushes = self.failPushes + 1
			self.okPushes = 0
			if self.failPushes >= (self.serverActive and 3 or 2) then
				self.failPushes = 0
				self:stepDown()
			end
		else
			self.failPushes = 0
			self.okPushes = self.okPushes + 1
			if self.probing then
				self.probing = false
				self.status = string.format("station %d|%d validated", self.w, self.s)
			end
		end
	end
	self.tapsSincePush = 0
	-- re-evaluate upward as Power grows / worlds unlock
	if self.okPushes >= 2 and not self.probing and os.clock() - self.lastProbeUpAt > 30 then
		self.lastProbeUpAt = os.clock()
		local cnt = stationCount(self.w)
		if type(ConfigModules.TrainingConfig) == "table" then
			local bw, bs = self:pickStation()
			if bw > self.w then
				self:setStation(bw, bs, "world up")
				teleportToWorld(bw)
			elseif bw == self.w and bs > self.s then
				self:setStation(bw, bs, "power up")
			end
		else
			local mw = maxOwnedWorld()
			if mw > self.w then
				-- new world unlocked: jump there and re-probe from its top station
				self:setStation(mw, stationCount(mw), "world up")
				teleportToWorld(mw)
			elseif self.s < cnt then
				self.probing = true
				self:setStation(self.w, self.s + 1, "probe up")
			end
		end
	end
end
table.insert(Mirror.listeners, function() TrainFarm:onPush() end)

function TrainFarm:tapLoop()
	while self.B and self.B.alive and State.Alive do
		if not RUNNING.train or self.serverActive or self.benchPause or not self.w then
			task.wait(0.25)
		else
			if os.clock() - self.lastTapAt > 1.5 then
				self.warm = 0 -- stream broke -> warm up again (mimics TrainBuffCount=20)
			end
			local arg = tostring(self.w) .. "|" .. tostring(self.s)
			waitToken()
			pcall(function()
				local r = getRemote("TrainingService", "RE", "Train")
				if r then r:FireServer(arg) end
			end)
			self.lastTapAt = os.clock()
			self.warm = self.warm + 1
			self.tapsSincePush = self.tapsSincePush + 1
			local base = 1 / math.clamp(self.tapsPerSec, 10, 18)
			local iv
			if self.warm < 20 then
				iv = math.max(base, 1.0 * (0.87 ^ self.warm))
			else
				iv = base * (0.95 + math.random() * 0.18) -- jitter, floor below
			end
			if iv < 0.055 then iv = 0.055 + math.random() * 0.012 end
			task.wait(iv)
		end
	end
end

-- one-time benchmark: manual spam vs server Start; >=90% of manual -> prefer server (quieter)
function TrainFarm:benchmark()
	if self.benchmarking then return end
	self.benchmarking = true
	task.spawn(function()
		local function powerAt() return num(Mirror.profile and Mirror.profile.TotalPower) end
		-- phase A: manual (must validate the station first)
		local t0 = os.clock()
		while State.Alive and RUNNING.train and self.okPushes < 2 and os.clock() - t0 < 40 do
			task.wait(0.5)
		end
		if not (State.Alive and RUNNING.train) then self.benchmarking = false return end
		self.status = "benchmark: manual phase"
		local mP, mT = powerAt(), os.clock()
		task.wait(16)
		if not (State.Alive and RUNNING.train) then self.benchmarking = false return end
		local manualRate = (powerAt() - mP) / math.max(0.1, os.clock() - mT)
		-- phase B: server Start
		self.benchPause = true
		self.status = "benchmark: server phase"
		fireRE("TrainingService", "Start", tostring(self.w) .. "|" .. tostring(self.s))
		self.serverActive = true
		task.wait(4) -- settle
		local sP, sT = powerAt(), os.clock()
		task.wait(16)
		local serverRate = (powerAt() - sP) / math.max(0.1, os.clock() - sT)
		local preferServer = serverRate > 0 and serverRate >= manualRate * 0.9
		Persist.train_server_ok = preferServer
		saveConfig()
		if preferServer and State.Alive and RUNNING.train then
			self.status = string.format("server auto-train (%s/s vs %s/s manual)", fmt(serverRate), fmt(manualRate))
			-- keep serverActive
		else
			fireRE("TrainingService", "Stop")
			self.serverActive = false
			self.benchPause = false
			self.warm = 0
			self.status = string.format("manual spam (%s/s vs %s/s server)", fmt(manualRate), fmt(serverRate))
		end
		self.benchmarking = false
	end)
end

function TrainFarm:Start()
	if RUNNING.train then return end
	RUNNING.train = true
	self.B = bag()
	self.warm = 0
	probeRejoinAuto("AutoTrain")
	self.B:track(task.spawn(function()
		-- wait for the mirror, then pick station + sit in the top owned world
		local t0 = os.clock()
		while State.Alive and RUNNING.train and not Mirror.profile and os.clock() - t0 < 30 do
			task.wait(0.5)
		end
		if not (State.Alive and RUNNING.train) then return end
		local w, s = self:pickStation()
		self:setStation(w, s, "init")
		if w > 1 and lastTeleportW ~= w then teleportToWorld(w) end
		local mode = self.mode
		if mode == "server" or (mode == "auto" and Persist.train_server_ok == true) then
			self.benchPause = true
			self.serverActive = true
			fireRE("TrainingService", "Start", tostring(w) .. "|" .. tostring(s))
			self.status = "server auto-train"
		elseif mode == "auto" and Persist.train_server_ok == nil then
			self:benchmark()
		else
			self.status = "manual spam"
		end
	end))
	self.B:track(task.spawn(function() self:tapLoop() end))
end

function TrainFarm:Stop()
	RUNNING.train = false
	if self.serverActive then
		fireRE("TrainingService", "Stop")
		self.serverActive = false
	end
	self.benchPause = false
	self.benchmarking = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ THROW FARM (Cash) ============================
-- Hard server cooldown ThrowTimeCooldown=10s. Strictly 1 Throw = 1 Finish, no args on either.
-- LIVE-VERIFIED 2026-07-02: distance is 100% server-authoritative = f(Power) + ~1-2% RNG jitter.
-- The client sends NOTHING tunable (no distance/power/angle/charge/timing); junk args on
-- Throw/Finish are ignored by the server (same distance at the same Power). So there is
-- deliberately NO "distance argument" here. The only throughput lever — Finish right after
-- Throw to skip the 15s roll — is already implemented below; payout grows only via
-- Power / world multiplier / Cash multipliers, not via throw arguments.
local ThrowFarm = {
	B = nil,
	cycleBase = math.clamp(cfgCtl("throw_interval", 10.7), 10.5, 15),
	throws = 0,
	credited = 0,
	retries = 0,
	status = "idle",
}
function ThrowFarm:Start()
	if RUNNING.throw then return end
	RUNNING.throw = true
	self.B = bag()
	probeRejoinAuto("AutoShoot")
	self.B:track(task.spawn(function()
		while self.B and self.B.alive and State.Alive and RUNNING.throw do
			local throwR = getRemote("ThrowService", "RE", "Throw")
			local finishR = getRemote("ThrowService", "RE", "Finish")
			if not throwR or not finishR or not Mirror.profile then
				self.status = "waiting for remotes/profile"
				task.wait(1)
			else
				local cashBefore = Cash()
				local tThrow = os.clock()
				waitToken()
				pcall(function() throwR:FireServer() end) -- NO args
				self.throws = self.throws + 1
				task.wait(0.55 + math.random() * 0.4)
				waitToken()
				pcall(function() finishR:FireServer() end) -- NO args, banks the Cash
				-- confirm the credit through the mirror; one retry Finish max
				local deadline = os.clock() + 2.6
				local credited = false
				while State.Alive and os.clock() < deadline do
					if Cash() > cashBefore then credited = true break end
					task.wait(0.2)
				end
				if credited then
					self.credited = self.credited + 1
				else
					self.retries = self.retries + 1
					waitToken()
					pcall(function() finishR:FireServer() end)
				end
				self.status = string.format("throws %d | credited %d | retries %d", self.throws, self.credited, self.retries)
				local cycle = math.max(10.5, self.cycleBase) + math.random() * 0.65
				local elapsed = os.clock() - tThrow
				task.wait(math.max(0.1, cycle - elapsed))
			end
		end
	end))
end
function ThrowFarm:Stop()
	RUNNING.throw = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ AUTO BUY (greedy state machine) ============================
-- One action per tick against a FRESH server push; every spend is confirmed by the next push.
-- Priorities: World > (saving) > Wheel chain > PetEquip > Power/Cash/TrainSpeed boosts > RebirthButton.
local AutoBuy = {
	B = nil,
	worldCooldownUntil = 0,
	wheelCooldown = {}, -- name -> os.clock deadline
	status = "idle",
}

function AutoBuy:buyWorld(w, wd)
	State.SpendBusy = true
	task.spawn(function()
		local function confirmed()
			local p = Mirror.profile
			local maps = p and p.Maps
			return type(maps) == "table" and (maps[tostring(w)] == true or maps[w] == true)
		end
		State.LastSpendSerial = Mirror.serial
		local s = Mirror.serial
		fireRE("MapsService", "Buy", worldArg(w))
		waitFreshPush(s, 5)
		waitFreshPush(Mirror.serial, 4)
		if not confirmed() and Persist.world_form ~= "number" then
			-- one number-form fallback, then learn it
			s = Mirror.serial
			fireRE("MapsService", "Buy", w)
			waitFreshPush(s, 5)
			waitFreshPush(Mirror.serial, 4)
			if confirmed() then
				Persist.world_form = "number"
				saveConfig()
			end
		end
		if confirmed() then
			self.status = "bought world " .. tostring(w)
			teleportToWorld(w)
			-- trainer re-picks on its next probe window
			TrainFarm.lastProbeUpAt = 0
		else
			self.status = "world " .. tostring(w) .. " buy no-op, backoff"
			self.worldCooldownUntil = os.clock() + 45
		end
		State.SpendBusy = false
	end)
end

function AutoBuy:buyWheel(target)
	State.SpendBusy = true
	task.spawn(function()
		local name = target.name
		State.LastSpendSerial = Mirror.serial
		local s = Mirror.serial
		fireRE("ItemsService", "Buy", name) -- one string name, no retry loop
		waitFreshPush(s, 5)
		waitFreshPush(Mirror.serial, 4)
		if ownsItem(name) then
			self.status = "bought " .. name
			-- equip if it beats the current wheel (Buy probably auto-equips; Equip is insurance)
			if (target.def.cashMult or 0) > equippedCashMult() then
				local s2 = Mirror.serial
				fireRE("ItemsService", "Equip", name)
				waitFreshPush(s2, 5)
				local p = Mirror.profile
				if not (p and p.EquippedItem == name) then
					fireRE("ItemsService", "Equip", name, "Wheel") -- inferred fallback form, once
				end
			end
		else
			self.status = name .. " buy no-op, backoff"
			self.wheelCooldown[name] = os.clock() + 30
		end
		State.SpendBusy = false
	end)
end

function AutoBuy:tick()
	local p = Mirror.profile
	if not p or State.SpendBusy then return end
	if Mirror.serial <= State.LastSpendSerial then return end -- never spend against a stale balance
	local cash = Cash()
	-- (1) WORLD — the dominant multiplier (x33k .. x3.3e34)
	if cfgCtl("buy_worlds", true) and os.clock() > self.worldCooldownUntil then
		local nw = maxOwnedWorld() + 1
		local wd = worldInfo(nw)
		if wd and ownsItem(wd.req) and cash >= wd.price then
			self:buyWorld(nw, wd)
			return
		end
	end
	-- (2) SAVING MODE — freeze upgrades/eggs while stacking toward the next world
	local saving, savingW = savingModeActive()
	-- (3) WHEEL chain (allowed even while saving)
	if cfgCtl("buy_wheels", true) then
		local target = nextWheelTarget()
		if target and target.name then
			local cd = self.wheelCooldown[target.name]
			if (not cd or os.clock() > cd) and target.def.price and cash >= target.def.price then
				self:buyWheel(target)
				return
			end
		end
	end
	if saving then
		local wd = worldInfo(savingW)
		self.status = string.format("saving for world %d (%s / %s)", savingW, fmt(cash), fmt(wd and wd.price or 0))
		return
	end
	if cfgCtl("buy_upgrades", true) and not UpgradeState.broken then
		-- (4) PetEquip slots — each slot adds the best unequipped pet to the additive stack
		local lvl = upgLevel("PetEquip")
		if lvl < UPG_CAPS.PetEquip then
			local price = upgPrice("PetEquip", lvl + 1)
			if price and price <= cash * 0.10 then
				if doUpgrade("PetEquip") then
					self.status = "PetEquip -> " .. tostring(lvl + 1)
					task.delay(6, function() equipBest(true) end)
					return
				end
			end
		end
		-- (5) PowerBoost (priority: distance curve ^2.26) > CashBoost > TrainSpeed, <=2% of Cash
		for _, track in ipairs({ "PowerBoost", "CashBoost", "TrainSpeed" }) do
			local l = upgLevel(track)
			if l < (UPG_CAPS[track] or 40) then
				local price = upgPrice(track, l + 1)
				if price and price <= cash * 0.02 then
					if doUpgrade(track) then
						self.status = track .. " -> " .. tostring(l + 1)
						return
					end
				end
			end
		end
	end
	-- (7) RebirthButton tiers, <=1% of Cash
	if cfgCtl("buy_rebirth_tiers", true) and not UpgradeState.broken then
		local l = upgLevel("RebirthButton")
		if l < UPG_CAPS.RebirthButton then
			local price = upgPrice("RebirthButton", l + 1)
			if price and price <= cash * 0.01 then
				if doUpgrade("RebirthButton") then
					self.status = "RebirthButton -> " .. tostring(l + 1)
					return
				end
			end
		end
	end
end

function AutoBuy:Start()
	if RUNNING.buy then return end
	RUNNING.buy = true
	self.B = bag()
	self.B:every(3.2, function()
		if RUNNING.buy then self:tick() end
	end)
end
function AutoBuy:Stop()
	RUNNING.buy = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ HATCH FARM (pets) ============================
local HatchFarm = {
	B = nil,
	budgetPct = math.clamp(cfgCtl("hatch_budget", 15), 5, 25),
	basicOnly = cfgCtl("hatch_basic_only", false),
	misses = 0,
	fallbackUntil = 0,
	hatches = 0,
	status = "idle",
}
function HatchFarm:pickEgg(budget)
	if self.basicOnly or os.clock() < self.fallbackUntil then
		return { name = "Basic Egg", price = 75 } -- VERIFIED arg; Cerberus x5000 lives here (0.02%)
	end
	local list = eggList()
	if not list or #list == 0 then
		return { name = "Basic Egg", price = 75 }
	end
	local best
	for _, egg in ipairs(list) do
		if egg.price * 3 <= budget then best = egg end
	end
	return best
end
function HatchFarm:Start()
	if RUNNING.hatch then return end
	RUNNING.hatch = true
	self.B = bag()
	probeRejoinAuto("AutoHatch")
	self.B:track(task.spawn(function()
		while self.B and self.B.alive and State.Alive and RUNNING.hatch do
			local waitFor = 4.7 + math.random() * 0.5 -- HatchTime=4.5 -> >=4.6s cadence
			local p = Mirror.profile
			local saving = savingModeActive()
			if p and not saving then
				local budget = Cash() * (self.budgetPct / 100)
				local egg = self:pickEgg(budget)
				if egg and egg.price * 3 <= budget then
					local cashBefore, petsBefore = Cash(), petCount()
					local s = Mirror.serial
					fireRE("EggsService", "HatchEgg", egg.name, "Triple") -- VERIFIED: (string, string)
					self.hatches = self.hatches + 1
					waitFreshPush(s, 4)
					if Cash() < cashBefore or petCount() > petsBefore then
						self.misses = 0
						self.status = string.format("hatched %s x3 (total %d)", egg.name, self.hatches)
					else
						self.misses = self.misses + 1
						self.status = egg.name .. " no-op x" .. tostring(self.misses)
						if self.misses >= 3 then
							self.misses = 0
							self.fallbackUntil = os.clock() + 60 -- cool off to Basic Egg
						end
					end
					equipBest(false)
				else
					self.status = "waiting for budget (" .. fmt(budget) .. ")"
				end
			elseif saving then
				self.status = "paused: saving mode"
			end
			task.wait(waitFor)
		end
	end))
end
function HatchFarm:Stop()
	RUNNING.hatch = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ EVENT EGG (10M Egg — limited event) ============================
-- LIVE-VERIFIED 2026-07-02: EggsService.RE.HatchEgg:FireServer("10M Egg", "Single"|"Triple"|"Octo")
-- works headless (no proximity check) and is fully server-validated: exactly -10M Cash per Single,
-- the pet is rolled + granted server-side. Costs top-level Cash (NOT Robux / NOT EventCash).
-- "Octo" (x8 price, up to 8 pets) needs the OctoHatch gamepass, otherwise "Triple" (x3) is best
-- pets-per-paid-open. Chases Midnight Kitty (0.001%, income x4,000,000) / Masquerade (0.0002%).
-- The loop parks itself once MiscConfig.EventEndTimestamp passes.
local EventEgg = {
	B = nil,
	eggName = "10M Egg",
	budgetPct = math.clamp(cfgCtl("eventegg_budget", 30), 5, 90),
	hatches = 0,
	misses = 0,
	backoffUntil = 0,
	status = "idle",
}
function EventEgg:price()
	local ec = ConfigModules.EggsConfig
	local def = type(ec) == "table" and ec[self.eggName] or nil
	local p = type(def) == "table" and tonumber(def.Price or def.Cost) or nil
	return p or 1e7
end
function EventEgg:mode()
	local octo = false
	pcall(function() octo = LocalPlayer:GetAttribute("OctoHatch") == true end)
	if octo then return "Octo", 8 end
	return "Triple", 3
end
function EventEgg:eventOver()
	local mc = ConfigModules.MiscConfig
	local ts = type(mc) == "table" and tonumber(mc.EventEndTimestamp) or nil
	return ts ~= nil and os.time() > ts
end
function EventEgg:Start()
	if RUNNING.eventegg then return end
	RUNNING.eventegg = true
	self.B = bag()
	self.B:track(task.spawn(function()
		while self.B and self.B.alive and State.Alive and RUNNING.eventegg do
			local step = 4.7 + math.random() * 0.5 -- server HatchTime=4.5 -> >=4.6s cadence
			local p = Mirror.profile
			if self:eventOver() then
				self.status = "event over (EventEndTimestamp passed)"
				task.wait(30)
			elseif not p then
				self.status = "waiting for profile push"
				task.wait(1)
			elseif os.clock() < self.backoffUntil then
				self.status = string.format("backoff %ds after no-ops", math.max(1, math.ceil(self.backoffUntil - os.clock())))
				task.wait(2)
			elseif savingModeActive() then
				self.status = "paused: saving mode"
				task.wait(step)
			else
				local mode, mult = self:mode()
				local cost = self:price() * mult
				if cost <= Cash() * (self.budgetPct / 100) then
					local cashBefore, petsBefore = Cash(), petCount()
					local s = Mirror.serial
					fireRE("EggsService", "HatchEgg", self.eggName, mode) -- VERIFIED form: (string, string)
					waitFreshPush(s, 4)
					if Cash() < cashBefore or petCount() > petsBefore then
						self.misses = 0
						self.hatches = self.hatches + 1
						self.status = string.format("hatched %s (%s) x%d", self.eggName, mode, self.hatches)
						equipBest(false)
					else
						self.misses = self.misses + 1
						self.status = string.format("%s no-op x%d", self.eggName, self.misses)
						if self.misses >= 3 then
							self.misses = 0
							self.backoffUntil = os.clock() + 60
						end
					end
					task.wait(step)
				else
					self.status = string.format("waiting budget: need %s <= %d%% of %s", fmt(cost), self.budgetPct, fmt(Cash()))
					task.wait(step)
				end
			end
		end
	end))
end
function EventEgg:Stop()
	RUNNING.eventegg = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ BOOTSTRAP: CODES + FREE EXCLUSIVE EGGS ============================
local CODES = {
	-- original batch (verified earlier)
	"money", "release", "lucky", "power", "cash", "time", "void", "update1", "update3",
	"banana", "apple", "500k", "voidyy", "charmroot", "applepower", "coinbanana",
	"mixpotion", "darkegg", "darkduo", "ancient", "eraeggs", "riftage", "grateful", "crownpotion",
	-- web wave 2026-07-02 (rocodes/pockettactics/robloxden/pcgamesn cross-checked as active)
	"clovy", "applo", "banzy", "brewz", "vexon", "duovo", "tikto", "chron", "eclip", "thank",
	"rexal", "crown", "cheers", "riftpack", "agepack", "clockegg", "abyssduo", "abyssegg",
	"mixdrink", "richfruit", "powerfruit", "luckyroot",
}
local Bootstrap = { B = nil, status = "idle" }
function Bootstrap:Start()
	if RUNNING.bootstrap then return end
	RUNNING.bootstrap = true
	self.B = bag()
	self.B:track(task.spawn(function()
		-- Phase 1: redeem codes (client cooldown 5s -> 6.2s spacing; expired = skip, no retry).
		-- Gate is PER CODE (Persist.redeemed), not the legacy codes_done flag: codes added in an
		-- update are picked up even on profiles where the original run already completed.
		local codesPending = false
		for _, code in ipairs(CODES) do
			if not Persist.redeemed[code] then codesPending = true break end
		end
		if codesPending then
			local total, done = #CODES, 0
			for _, code in ipairs(CODES) do
				if not (self.B and self.B.alive and State.Alive and RUNNING.bootstrap) then return end
				if Persist.redeemed[code] then
					done = done + 1
				else
					self.status = string.format("codes %d/%d: %s", done + 1, total, code)
					invokeRF("CodesService", "Claim", 8, code) -- read+ignore result; invalid/expired = skip
					Persist.redeemed[code] = true
					done = done + 1
					saveConfig()
					task.wait(6.2)
				end
			end
			Persist.codes_done = true
			saveConfig()
		end
		-- Phase 2: open every Timeless/Void Egg from the profile inventory (petStack ~1400 from minute one)
		task.wait(3) -- let the push refresh the inventory after the last code
		for _, eggName in ipairs({ "Timeless Egg", "Void Egg" }) do
			local misses = 0
			while self.B and self.B.alive and State.Alive and RUNNING.bootstrap do
				local count = inventoryCount(eggName)
				if count < 1 or misses >= 3 then break end
				self.status = string.format("opening %s (%d left)", eggName, count)
				fireRE("EggsService", "OpenExclusiveEgg", eggName)
				task.wait(4.7 + math.random() * 0.4)
				local newCount = inventoryCount(eggName)
				if newCount >= count then misses = misses + 1 else misses = 0 end
			end
		end
		equipBest(true)
		Persist.bootstrap_done = true
		saveConfig()
		self.status = "done (codes + exclusive eggs)"
	end))
end
function Bootstrap:Stop()
	RUNNING.bootstrap = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ DAILY SPIN ============================
local DailySpin = { B = nil, lastFireAt = 0, status = "idle" }
function DailySpin:lastClaimTime()
	local p = Mirror.profile
	if not p then return nil end
	local v = p.DailySpinClaimedTime
	if type(v) == "number" then return v end
	for k, val in pairs(p) do
		if type(k) == "string" and type(val) == "number" and val > 1e9
			and k:lower():find("spin") then
			return val
		end
	end
	return nil
end
function DailySpin:Start()
	if RUNNING.spin then return end
	RUNNING.spin = true
	self.B = bag()
	self.B:every(60, function()
		if not RUNNING.spin or not Mirror.profile then return end
		local last = self:lastClaimTime()
		if last then
			local left = 86400 - (os.time() - last)
			if left <= 0 and os.clock() - self.lastFireAt > 600 then
				self.lastFireAt = os.clock()
				fireRE("SpinsService", "Spin") -- no args; grants ONE random x2 boost for 1800s
				self.status = "spin fired"
			else
				self.status = left > 0 and ("next spin in " .. math.floor(left / 3600) .. "h") or "spin pending"
			end
		else
			-- field not found: at most once per calendar day, persisted
			local today = os.date("%Y-%m-%d")
			if Persist.last_spin_day ~= today then
				Persist.last_spin_day = today
				saveConfig()
				fireRE("SpinsService", "Spin")
				self.status = "spin fired (day guard)"
			end
		end
	end)
end
function DailySpin:Stop()
	RUNNING.spin = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ PERIODIC CLAIMS ============================
-- Invalid claim = quiet no-op; 12 min cadence is negligible traffic. Admin* services NEVER touched.
-- PlaytimeRewardService is NOT in the blind batch anymore: the server silently no-ops its Claim
-- while the Player attribute "PlaytimeReward" (accrued playtime seconds, unbounded past ready) is
-- < MiscConfig.PlaytimeRewardTime (900), and a ~12-min cadence never reliably lands the 15-min
-- window. LIVE-VERIFIED 2026-07-02: no-arg Claim at attr=1239 reset it to ~0 and granted the
-- reward, so it gets its own readiness poller below (claims within ~31s of every 15-min cycle).
local CLAIM_SERVICES = {
	"DailyRewardsService", "ChestService", "AchievementService", "SeasonpassService",
}
local function playtimeReadySec()
	local mc = ConfigModules.MiscConfig
	local t = type(mc) == "table" and tonumber(mc.PlaytimeRewardTime) or nil
	return t or 900
end
local Claims = { B = nil, rounds = 0, playtimeClaims = 0, status = "idle" }
function Claims:Start()
	if RUNNING.claims then return end
	RUNNING.claims = true
	self.B = bag()
	self.B:track(task.spawn(function()
		task.wait(10)
		while self.B and self.B.alive and State.Alive and RUNNING.claims do
			for _, svc in ipairs(CLAIM_SERVICES) do
				if not RUNNING.claims then break end
				fireRE(svc, "Claim")
				task.wait(1.2)
			end
			self.rounds = self.rounds + 1
			self.status = string.format("claim rounds: %d | playtime x%d", self.rounds, self.playtimeClaims)
			task.wait(700 + math.random(0, 60))
		end
	end))
	-- Playtime Reward: attribute-gated poller — fire ONLY when actually ready (attr resets on success)
	self.B:every(31, function()
		if not RUNNING.claims then return end
		local acc = 0
		pcall(function() acc = num(LocalPlayer:GetAttribute("PlaytimeReward")) end)
		if acc >= playtimeReadySec() then
			fireRE("PlaytimeRewardService", "Claim") -- VERIFIED form: no args, no tier/index
			self.playtimeClaims = self.playtimeClaims + 1
			self.status = string.format("playtime reward claimed x%d", self.playtimeClaims)
		end
	end)
end
function Claims:Stop()
	RUNNING.claims = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ AUTO POTIONS ============================
-- Use(<name>, 1) only when the matching farm is running and no own 300s timer is active.
-- Decrement is confirmed via the push; a failed use goes on a retry cooldown instead of burning spam.
local Potions = { B = nil, timers = {}, pending = nil, status = "idle" }
local function potionCategory(name)
	local l = name:lower()
	if l:find("power") then return "train" end
	if l:find("cash") or l:find("coin") or l:find("money") then return "throw" end
	if l:find("luck") then return "hatch" end
	if l:find("cocktail") or l:find("royal") then return "any" end
	return nil
end
function Potions:Start()
	if RUNNING.potions then return end
	RUNNING.potions = true
	self.B = bag()
	self.B:every(20, function()
		if not RUNNING.potions then return end
		local p = Mirror.profile
		local inv = p and p.Inventory
		if type(inv) ~= "table" then return end
		-- confirm a pending use first
		if self.pending then
			if inventoryCount(self.pending.name) < self.pending.count then
				self.timers[self.pending.name] = os.clock() + 305 -- PotionTime=300
				self.status = "active: " .. self.pending.name
			else
				self.timers[self.pending.name] = os.clock() + 120 -- no-op -> retry later
			end
			self.pending = nil
			return
		end
		for name in pairs(inv) do
			if type(name) == "string" and name:find("Potion") then
				local cat = potionCategory(name)
				local wanted = cat == "any" and (RUNNING.train or RUNNING.throw or RUNNING.hatch)
					or (cat == "train" and RUNNING.train)
					or (cat == "throw" and RUNNING.throw)
					or (cat == "hatch" and RUNNING.hatch)
				local cd = self.timers[name]
				if wanted and (not cd or os.clock() > cd) then
					local count = inventoryCount(name)
					if count >= 1 then
						self.pending = { name = name, count = count }
						fireRE("InventoryService", "Use", name, 1) -- VERIFIED form: (string, number)
						self.status = "using " .. name
						return -- one per tick
					end
				end
			end
		end
	end)
end
function Potions:Stop()
	RUNNING.potions = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ CLASS ROLL ============================
-- Shards drip from throws (~1 per 17 min). Roll until Wheelborn / The Insane Wheeler, then Equip + StopAuto.
local CLASS_TARGETS = { "Wheelborn", "The Insane Wheeler" }
local ClassRoll = { B = nil, minShards = math.max(0, cfgCtl("class_min_shards", 1)), doneFired = false, status = "idle" }
function ClassRoll:ownedTarget()
	local p = Mirror.profile
	if not p then return nil end
	local pools = { p.Classes, p.OwnedClasses }
	for _, pool in ipairs(pools) do
		if type(pool) == "table" then
			for _, target in ipairs(CLASS_TARGETS) do
				if pool[target] ~= nil and pool[target] ~= false then return target end
				for _, v in pairs(pool) do
					if v == target or (type(v) == "table" and (v.Name == target or v.Class == target)) then
						return target
					end
				end
			end
		end
	end
	return nil
end
function ClassRoll:shards()
	local p = Mirror.profile
	if not p then return nil end
	if type(p.Shards) == "number" then return p.Shards end
	for k, v in pairs(p) do
		if type(k) == "string" and type(v) == "number" and k:lower():find("shard") then
			return v
		end
	end
	return nil
end
function ClassRoll:Start()
	if RUNNING.class then return end
	RUNNING.class = true
	self.B = bag()
	self.B:every(50, function()
		if not RUNNING.class or not Mirror.profile then return end
		local target = self:ownedTarget()
		if target then
			if not self.doneFired then
				self.doneFired = true
				fireRE("ClassesService", "StopAuto")
				task.wait(0.5)
				fireRE("ClassesService", "Equip", target)
				self.status = "done: " .. target .. " equipped"
			end
			return
		end
		local shards = self:shards()
		if shards == nil or shards >= self.minShards then
			fireRE("ClassesService", "Roll")
			self.status = "rolled (shards: " .. tostring(shards or "?") .. ")"
		else
			self.status = string.format("waiting shards %s/%d", tostring(shards), self.minShards)
		end
	end)
end
function ClassRoll:Stop()
	RUNNING.class = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ AUTO REBIRTH ============================
-- Phase 1: one-shot tutorial probe (first Rebirth completes the tutorial and gates features).
-- Phase 2: steady-state press ONLY when the Power regrind is cheap; every press is confirmed
-- by the counter in the push. Never on a timer, never in a loop.
local AutoRebirth = {
	B = nil,
	maxRegrind = math.clamp(cfgCtl("rebirth_regrind", 120), 30, 300),
	allowTutorialProbe = cfgCtl("rebirth_tutorial_probe", true),
	lastPressAt = 0,
	backoffUntil = 0,
	status = "idle",
}
function AutoRebirth:tutorialDone()
	if Persist.rebirth_tutorial_done then return true end
	local p = Mirror.profile
	local tut = p and p.Tutorial
	if type(tut) == "table" and tut.Rebirth == true then
		Persist.rebirth_tutorial_done = true
		saveConfig()
		return true
	end
	-- some profiles may not carry Tutorial at all but already have rebirths
	if p and num(p.Rebirth) > 0 then
		Persist.rebirth_tutorial_done = true
		saveConfig()
		return true
	end
	return false
end
function AutoRebirth:press()
	-- returns true if the counter grew (confirmed by push diff)
	local before = num(Mirror.profile and Mirror.profile.Rebirth)
	local cashBefore = Cash()
	local form = Persist.rebirth_form
	local s = Mirror.serial
	if form == "tier1" then
		fireRE("RebirthService", "Rebirth", 1)
	else
		fireRE("RebirthService", "Rebirth") -- inferred: no args
	end
	waitFreshPush(s, 5)
	waitFreshPush(Mirror.serial, 4)
	local after = num(Mirror.profile and Mirror.profile.Rebirth)
	if after > before then
		Persist.rebirth_cash_resets = Cash() < cashBefore * 0.5
		saveConfig()
		return true
	end
	if form ~= "tier1" then
		-- single tier-argument probe
		s = Mirror.serial
		fireRE("RebirthService", "Rebirth", 1)
		waitFreshPush(s, 5)
		waitFreshPush(Mirror.serial, 4)
		after = num(Mirror.profile and Mirror.profile.Rebirth)
		if after > before then
			Persist.rebirth_form = "tier1"
			Persist.rebirth_cash_resets = Cash() < cashBefore * 0.5
			saveConfig()
			return true
		end
	end
	return false
end
function AutoRebirth:Start()
	if RUNNING.rebirth then return end
	RUNNING.rebirth = true
	self.B = bag()
	self.B:every(6, function()
		if not RUNNING.rebirth or not Mirror.profile or State.SpendBusy then return end
		if os.clock() < self.backoffUntil then return end
		local p = Mirror.profile
		if not self:tutorialDone() then
			-- PHASE 1: tutorial probe. Observed player got stuck at Power 729k with Tutorial.Rebirth=false.
			if not self.allowTutorialProbe then
				self.status = "tutorial probe disabled"
				return
			end
			local probes = num(Persist.rebirth_probe_count)
			if probes >= 6 then
				self.status = "tutorial probe limit reached"
				return
			end
			if Cash() >= 2000 and Power() >= 1000 then
				Persist.rebirth_probe_count = probes + 1
				saveConfig()
				self.status = "tutorial rebirth probe..."
				if self:press() then
					Persist.rebirth_tutorial_done = true
					saveConfig()
					self.status = "tutorial rebirth DONE"
					self.lastPressAt = os.clock()
				else
					self.status = "tutorial probe no-op (pre-steps left?), backoff 10m"
					self.backoffUntil = os.clock() + 600
				end
			else
				self.status = string.format("tutorial gate: need Cash>=2k (%s) & Power>=1k (%s)", fmt(Cash()), fmt(Power()))
			end
			return
		end
		-- PHASE 2: steady-state
		if os.clock() - self.lastPressAt < 600 then
			self.status = "cooldown between presses"
			return
		end
		local rate = Mirror.powerRate
		if not rate or rate <= 0 then
			self.status = "no power rate yet (enable Auto Train)"
			return
		end
		local regrind = Power() / rate
		if regrind >= self.maxRegrind then
			self.status = string.format("regrind %ds >= %ds cap", math.floor(regrind), self.maxRegrind)
			return
		end
		-- tier price gate when known: press only if the NEXT RebirthButton tier is not trivially buyable first
		if Persist.rebirth_cash_resets == true then
			-- cash resets on rebirth -> only press at the bottom of the balance
			if Cash() > State.MaxCashSeen * 0.15 then
				self.status = "cash resets: waiting for a low balance window"
				return
			end
		end
		self.status = "pressing rebirth..."
		self.lastPressAt = os.clock()
		if self:press() then
			self.status = "rebirth confirmed (+counter)"
			TrainFarm.lastProbeUpAt = 0 -- re-pick station after the reset
			TrainFarm.warm = 0
			task.delay(4, function()
				-- re-equip top wheel if it slipped
				local defs = wheelDefs()
				if defs then
					local bestName, bestMult
					for name, d in pairs(defs) do
						if ownsItem(name) and d.cashMult and (not bestMult or d.cashMult > bestMult) then
							bestName, bestMult = name, d.cashMult
						end
					end
					local pNow = Mirror.profile
					if bestName and pNow and pNow.EquippedItem ~= bestName then
						fireRE("ItemsService", "Equip", bestName)
					end
				end
			end)
		else
			self.status = "press no-op, backoff 30m"
			self.backoffUntil = os.clock() + 1800
		end
	end)
end
function AutoRebirth:Stop()
	RUNNING.rebirth = false
	if self.B then self.B:kill() self.B = nil end
	self.status = "idle"
end

--============================ ANTI-AFK ============================
local AntiAfk = { conns = {} }
function AntiAfk:Start()
	if RUNNING.afk then return end
	RUNNING.afk = true
	pcall(function()
		table.insert(self.conns, LocalPlayer.Idled:Connect(function()
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end))
	end)
	local lastPing = os.clock()
	table.insert(self.conns, RunService.Heartbeat:Connect(function()
		if RUNNING.afk and os.clock() - lastPing >= 90 then
			lastPing = os.clock()
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new(0, 0), Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame)
			end)
		end
	end))
end
function AntiAfk:Stop()
	RUNNING.afk = false
	for _, c in ipairs(self.conns) do
		pcall(function() c:Disconnect() end)
	end
	self.conns = {}
end

--============================ WATCHDOG + RESPAWN RESILIENCE ============================
do
	-- stale mirror -> single getData resync (never a poll loop)
	table.insert(State.Connections, RunService.Heartbeat:Connect(function()
		if not State.Alive then return end
		if Mirror.at > 0 and os.clock() - Mirror.at > 20 and (RUNNING.train or RUNNING.throw or RUNNING.buy) then
			pullProfileOnce()
		end
	end))
	-- respawn: worlds/warmup recover (character may drop back to spawn)
	table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(function()
		task.delay(3, function()
			if not State.Alive then return end
			TrainFarm.warm = 0
			local w = maxOwnedWorld()
			if w > 1 and (RUNNING.train or RUNNING.throw) then
				teleportToWorld(w)
			end
			if TrainFarm.serverActive and TrainFarm.w then
				fireRE("TrainingService", "Start", tostring(TrainFarm.w) .. "|" .. tostring(TrainFarm.s))
			end
		end)
	end))
end

--============================ INFO TICKER (GUI updates only, no remotes) ============================
local InfoTicker = { B = nil }
local function liveStats()
	local p = Mirror.profile
	if not p then return "waiting for profile push (HandlerService.RE.Fruits)..." end
	local stack = petStack()
	local lines = {
		"Cash: " .. fmt(p.Cash) .. "   (session max " .. fmt(State.MaxCashSeen) .. ")",
		"Power: " .. fmt(p.Power) .. "   Rebirth: " .. tostring(num(p.Rebirth)),
		"World: " .. tostring(maxOwnedWorld()) .. "   Pet stack: x" .. (stack and fmt(stack) or "?"),
		"Power/min: " .. (Mirror.powerRate and fmt(Mirror.powerRate * 60) or "-")
			.. "   Cash/min: " .. (Mirror.cashRate and fmt(Mirror.cashRate * 60) or "-"),
		"Station: " .. tostring(TrainFarm.w or "-") .. "|" .. tostring(TrainFarm.s or "-")
			.. (TrainFarm.serverActive and " (server auto)" or ""),
		"Push age: " .. (Mirror.at > 0 and string.format("%.1fs", os.clock() - Mirror.at) or "-"),
	}
	return table.concat(lines, "\n")
end
local function refreshParagraphLabels()
	local ok, sgui = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
	if not ok or not sgui then return end
	local root = sgui:FindFirstChild("SigmatikClickGui")
	if not root then return end
	for name, entry in pairs(State.Paragraphs) do
		if entry.pending then
			if not (entry.text and entry.text.Parent) then
				local card = root:FindFirstChild(name .. "Paragraph", true)
				entry.text = card and card:FindFirstChild("Content", true) or nil
			end
			if entry.text and entry.text.Parent then
				entry.text.Text = entry.pending
			end
			if entry.control then entry.control.Content = entry.pending end
		end
	end
end
function InfoTicker:Start()
	if RUNNING.info then return end
	RUNNING.info = true
	self.B = bag()
	self.B:every(1, function()
		if not RUNNING.info then return end
		setStatus("Live Stats", liveStats())
		setStatus("Train Status", TrainFarm.status)
		setStatus("Throw Status", ThrowFarm.status)
		setStatus("Buy Status", AutoBuy.status)
		setStatus("Hatch Status", HatchFarm.status)
		setStatus("EventEgg Status", EventEgg.status)
		setStatus("Bootstrap Status", Bootstrap.status)
		setStatus("Spin Status", DailySpin.status)
		setStatus("Claims Status", Claims.status)
		setStatus("Potion Status", Potions.status)
		setStatus("Class Status", ClassRoll.status)
		setStatus("Rebirth Status", AutoRebirth.status)
		refreshParagraphLabels()
	end)
end
function InfoTicker:Stop()
	RUNNING.info = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ FLOATING QUICK BAR (client-only) ============================
-- Draggable bubble + compact quick toggles in gethui()/CoreGui. Every toggle goes through
-- Window:SetModuleEnabled -> the SAME modDef Callback as a click in the main menu (one code
-- path, one RUNNING state, main-menu checkbox stays in sync automatically). Button colors are
-- polled from RUNNING, so menu-side toggles reflect here too. Zero remotes. Removed by
-- unloadAll / window close (QuickBar is listed in FEATURES).
local UserInputService = game:GetService("UserInputService")

local QuickBar = {
	gui = nil,
	B = nil,
	expanded = cfgCtl("quickbar_expanded", true) == true,
	items = {},
}
local QUICK_DEFS = {
	{ label = "TRN", running = "train", feature = TrainFarm, tab = "Farm", module = "Auto Train (Power)" },
	{ label = "THR", running = "throw", feature = ThrowFarm, tab = "Farm", module = "Auto Throw (Cash)" },
	{ label = "BUY", running = "buy", feature = AutoBuy, tab = "Economy", module = "Auto Buy" },
	{ label = "EGG", running = "eventegg", feature = EventEgg, tab = "Economy", module = "Event Egg (10M)" },
	{ label = "UI", special = "menu" },
}
local function mainGuiRoot()
	local ok, sgui = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
	if not ok or not sgui then return nil end
	return sgui:FindFirstChild("SigmatikClickGui")
end
function QuickBar:toggle(def)
	if def.special == "menu" then
		local root = mainGuiRoot()
		if root then root.Enabled = not root.Enabled end
		return
	end
	local on = not (RUNNING[def.running] == true)
	local synced = false
	pcall(function()
		if State.Window and State.Window.SetModuleEnabled then
			-- fires the module Callback (Config.modules save + feature Start/Stop) + menu visuals
			State.Window:SetModuleEnabled(def.tab, def.module, on)
			synced = true
		end
	end)
	if not synced then -- window object unavailable: drive the exact same state keys directly
		Config.modules[def.module] = on
		saveConfig()
		if on then
			pcall(function() def.feature:Start() end)
		else
			pcall(function() def.feature:Stop() end)
		end
	end
end
function QuickBar:applyColors()
	if not self.gui then return end
	for _, item in ipairs(self.items) do
		local on
		if item.def.special == "menu" then
			local root = mainGuiRoot()
			on = root ~= nil and root.Enabled == true
		else
			on = RUNNING[item.def.running] == true
		end
		item.btn.BackgroundColor3 = on and Color3.fromRGB(249, 115, 22) or Color3.fromRGB(52, 52, 60)
		item.btn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(168, 168, 178)
	end
end
function QuickBar:Build()
	if self.gui or not State.Alive then return end
	elevate() -- identity 8 right before touching gethui()/CoreGui
	local ok, sgui = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
	if not ok or not sgui then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SigmatikLWQuickBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999999999

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(46 + 6 + #QUICK_DEFS * 50, 46)
	local pos = Config.controls.quickbar_pos
	local px = (type(pos) == "table" and tonumber(pos[1])) or 24
	local py = (type(pos) == "table" and tonumber(pos[2])) or 300
	pcall(function()
		local cam = Workspace.CurrentCamera
		if cam then
			px = math.clamp(px, 0, math.max(0, cam.ViewportSize.X - 60))
			py = math.clamp(py, 0, math.max(0, cam.ViewportSize.Y - 60))
		end
	end)
	holder.Position = UDim2.fromOffset(px, py)
	holder.Parent = gui

	local bubble = Instance.new("TextButton")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.fromOffset(46, 46)
	bubble.BackgroundColor3 = Color3.fromRGB(249, 115, 22)
	bubble.Text = "LW"
	bubble.Font = Enum.Font.GothamBold
	bubble.TextSize = 15
	bubble.TextColor3 = Color3.fromRGB(255, 255, 255)
	bubble.AutoButtonColor = true
	bubble.BorderSizePixel = 0
	bubble.Parent = holder
	do
		local c = Instance.new("UICorner") c.CornerRadius = UDim.new(1, 0) c.Parent = bubble
		local s = Instance.new("UIStroke") s.Color = Color3.fromRGB(24, 24, 28) s.Thickness = 1.5 s.Parent = bubble
	end

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(52, 8)
	row.Size = UDim2.fromOffset(#QUICK_DEFS * 50, 30)
	row.Visible = self.expanded
	row.Parent = holder
	do
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.Padding = UDim.new(0, 4)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = row
	end

	self.items = {}
	for i, def in ipairs(QUICK_DEFS) do
		local btn = Instance.new("TextButton")
		btn.Name = def.label
		btn.LayoutOrder = i
		btn.Size = UDim2.fromOffset(46, 30)
		btn.BackgroundColor3 = Color3.fromRGB(52, 52, 60)
		btn.Text = def.label
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.TextColor3 = Color3.fromRGB(168, 168, 178)
		btn.AutoButtonColor = true
		btn.BorderSizePixel = 0
		btn.Parent = row
		local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 8) c.Parent = btn
		local s = Instance.new("UIStroke") s.Color = Color3.fromRGB(24, 24, 28) s.Thickness = 1 s.Parent = btn
		btn.MouseButton1Click:Connect(function()
			self:toggle(def)
			self:applyColors()
		end)
		table.insert(self.items, { def = def, btn = btn })
	end

	-- drag on the bubble; a press without movement (<=6 px) toggles collapse/expand instead
	local dragging, moved, dragStart, startPos = false, false, nil, nil
	bubble.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, moved = true, false
			dragStart = input.Position
			startPos = holder.Position
		end
	end)
	bubble.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragging and not moved then
				self.expanded = not self.expanded
				row.Visible = self.expanded
				Config.controls.quickbar_expanded = self.expanded
				saveConfig()
			elseif dragging and moved then
				Config.controls.quickbar_pos = { holder.Position.X.Offset, holder.Position.Y.Offset }
				saveConfig()
			end
			dragging = false
		end
	end)
	self.B = bag()
	self.B:track(UserInputService.InputChanged:Connect(function(input)
		if not dragging or not dragStart then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			if math.abs(delta.X) + math.abs(delta.Y) > 6 then moved = true end
			if moved then
				holder.Position = UDim2.fromOffset(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y)
			end
		end
	end))
	self.B:every(0.4, function() self:applyColors() end)

	gui.Parent = sgui
	self.gui = gui
	self:applyColors()
end
function QuickBar:Start()
	self:Build()
end
function QuickBar:Stop()
	if self.B then self.B:kill() self.B = nil end
	pcall(function() if self.gui then self.gui:Destroy() end end)
	self.gui = nil
	self.items = {}
end

--============================ UNLOAD ============================
local unloaded = false
local FEATURES = {
	TrainFarm, ThrowFarm, AutoBuy, HatchFarm, EventEgg, Bootstrap,
	DailySpin, Claims, Potions, ClassRoll, AutoRebirth, InfoTicker, QuickBar,
}
local function unloadAll()
	if unloaded then return end
	unloaded = true
	State.Alive = false
	for _, f in ipairs(FEATURES) do
		pcall(function() f:Stop() end)
	end
	pcall(function() AntiAfk:Stop() end)
	for _, c in ipairs(State.Connections) do
		pcall(function() c:Disconnect() end)
	end
	State.Connections = {}
	for _, c in ipairs(State.CharConnections) do
		pcall(function() c:Disconnect() end)
	end
	State.CharConnections = {}
	pcall(function()
		if State.Window and State.Window.Destroy then State.Window:Destroy() end
	end)
	pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end)
	if SharedEnv.SigmatikLaunchWheelState == State then
		SharedEnv.SigmatikLaunchWheelState = nil
	end
end
State.Stop = unloadAll

--============================ GUI ============================
local autostart = {}
local function modDef(name, feature, defaultOn, sections)
	local saved = Config.modules[name]
	local enabled = (saved == nil) and (defaultOn == true) or (saved == true)
	if enabled then table.insert(autostart, feature) end
	return {
		Name = name,
		Enabled = enabled,
		Callback = function(v)
			Config.modules[name] = v and true or false
			saveConfig()
			if v then pcall(function() feature:Start() end) else pcall(function() feature:Stop() end) end
		end,
		Sections = sections or {},
	}
end
local function ctlToggle(key, name, default, apply)
	return {
		Type = "Toggle",
		Name = name,
		CurrentValue = cfgCtl(key, default) == true,
		Callback = function(v)
			Config.controls[key] = v
			saveConfig()
			pcall(apply, v)
		end,
	}
end
local function ctlSlider(key, name, min, max, inc, default, apply)
	return {
		Type = "Slider",
		Name = name,
		Min = min, Max = max, Increment = inc,
		CurrentValue = cfgCtl(key, default),
		Callback = function(v)
			Config.controls[key] = v
			saveConfig()
			pcall(apply, v)
		end,
	}
end
local function para(name, content)
	return { Type = "Paragraph", Name = name, Content = content or "..." }
end

-- Train mode mutex checkboxes
local TRAIN_MODE_NAMES = { ["Auto (benchmark once)"] = "auto", ["Manual spam (verified)"] = "manual", ["Server Start (zero spam)"] = "server" }
local function applyTrainMode(mode)
	TrainFarm.mode = mode
	Config.controls.train_mode = mode
	saveConfig()
	if RUNNING.train then
		TrainFarm:Stop()
		task.wait(0.4)
		TrainFarm:Start()
	end
end
local function trainModeControls()
	local list = {}
	local current = cfgCtl("train_mode", "auto")
	for _, displayName in ipairs({ "Auto (benchmark once)", "Manual spam (verified)", "Server Start (zero spam)" }) do
		local mode = TRAIN_MODE_NAMES[displayName]
		table.insert(list, {
			Type = "Checkbox",
			Name = displayName,
			CurrentValue = (mode == current),
			Callback = function(v)
				if v then
					applyTrainMode(mode)
					if State.Window then
						for other, otherMode in pairs(TRAIN_MODE_NAMES) do
							if otherMode ~= mode then
								pcall(function()
									State.Window:SetControlValue("Farm", "Auto Train (Power)", "Mode (pick one)", other, false)
								end)
							end
						end
					end
				else
					if TrainFarm.mode == mode and State.Window then
						task.defer(function()
							pcall(function()
								State.Window:SetControlValue("Farm", "Auto Train (Power)", "Mode (pick one)", displayName, true)
							end)
						end)
					end
				end
			end,
		})
	end
	return list
end

elevate() -- re-elevate RIGHT before window creation (yields reset thread identity)

State.Window = Library:Create({
	Title = "tg: @sigmatik323",
	ConfigName = "Launch a Wheel",
	SearchPlaceholder = "Search...",
	Accent = "#f97316",
	AccentSoft = "#fdba74",
	WindowWidth = 1100,
	WindowHeight = 600,
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = "Farm",
			Icon = "combat",
			Modules = {
				modDef("Auto Train (Power)", TrainFarm, false, {
					{ Name = "Mode (pick one)", Controls = trainModeControls() },
					{ Name = "Tuning", Controls = {
						ctlSlider("train_tps", "Taps per second (manual)", 10, 18, 0.5, 16, function(v)
							TrainFarm.tapsPerSec = math.clamp(v, 10, 18)
						end),
					} },
					{ Name = "Status", Controls = {
						para("Train Status", "idle"),
						para("Train Info", "Train(\"W|S\") spam with warmup + jitter; station auto-picked and validated by Power delta from server pushes. Auto mode benchmarks the server-side Start() once and keeps the quieter option if income matches."),
					} },
				}),
				modDef("Auto Throw (Cash)", ThrowFarm, false, {
					{ Name = "Tuning", Controls = {
						ctlSlider("throw_interval", "Cycle seconds", 10.5, 13, 0.1, 10.7, function(v)
							ThrowFarm.cycleBase = v
						end),
					} },
					{ Name = "Status", Controls = {
						para("Throw Status", "idle"),
						para("Throw Info", "Server cooldown is a hard 10s. One Throw = one Finish, both argument-free; Cash credit is confirmed via the profile push, with a single Finish retry."),
					} },
				}),
			},
		},
		{
			Name = "Economy",
			Icon = "misc",
			Modules = {
				modDef("Auto Buy", AutoBuy, false, {
					{ Name = "Priorities", Controls = {
						ctlToggle("buy_worlds", "Worlds (dominant lever)", true, function() end),
						ctlToggle("buy_wheels", "Wheels (Required chain)", true, function() end),
						ctlToggle("buy_upgrades", "Upgrades (Pow/Cash/TrainSpeed/PetEquip)", true, function() end),
						ctlToggle("buy_rebirth_tiers", "RebirthButton tiers", true, function() end),
						ctlToggle("buy_saving", "Saving mode before a world", true, function() end),
					} },
					{ Name = "Status", Controls = {
						para("Buy Status", "idle"),
						para("Buy Info", "One purchase per tick, always against a fresh server push. World > wheel chain > PetEquip (10%) > boosts (2%) > rebirth tiers (1%). Robux-flagged wheels are skipped by config flag, never by name."),
					} },
				}),
				modDef("Auto Hatch Eggs", HatchFarm, false, {
					{ Name = "Tuning", Controls = {
						ctlSlider("hatch_budget", "Budget % of Cash", 5, 25, 1, 15, function(v)
							HatchFarm.budgetPct = v
						end),
						ctlToggle("hatch_basic_only", "Basic Egg only (Cerberus x5000 hunt)", false, function(v)
							HatchFarm.basicOnly = v
						end),
					} },
					{ Name = "Status", Controls = {
						para("Hatch Status", "idle"),
						para("Hatch Info", "HatchEgg(<best cash egg>, \"Triple\") every >=4.6s within the budget, EquipBest debounced. Pauses in saving mode."),
					} },
				}),
				modDef("Event Egg (10M)", EventEgg, false, {
					{ Name = "Tuning", Controls = {
						ctlSlider("eventegg_budget", "Batch budget % of Cash", 5, 90, 5, 30, function(v)
							EventEgg.budgetPct = math.clamp(v, 5, 90)
						end),
					} },
					{ Name = "Status", Controls = {
						para("EventEgg Status", "idle"),
						para("EventEgg Info", "Limited-event 10M Egg: HatchEgg(\"10M Egg\", Triple/Octo-with-gamepass) every >=4.6s while the batch cost fits the budget %. Price and rolls are fully server-side (live-verified: exact -10M per Single), credit confirmed via the profile push with no-op backoff. Chases Midnight Kitty (0.001%, x4,000,000 income) and Masquerade (0.0002%, Best +200). Pauses in saving mode and parks after EventEndTimestamp."),
					} },
				}),
			},
		},
		{
			Name = "Boosts",
			Icon = "visuals",
			Modules = {
				modDef("Redeem Codes + Free Eggs", Bootstrap, false, {
					{ Name = "Status", Controls = {
						para("Bootstrap Status", "idle"),
						para("Bootstrap Info", "Runs " .. tostring(#CODES) .. " promo codes via CodesService.RF.Claim (6.2s spacing, expired = skip; per-code gate, so freshly added codes redeem even after the first run), then every Timeless/Void Egg is opened (4.7s step) and EquipBest fires. Progress persists across restarts."),
					} },
				}),
				modDef("Auto Daily Spin", DailySpin, false, {
					{ Name = "Status", Controls = {
						para("Spin Status", "idle"),
					} },
				}),
				modDef("Auto Claim Rewards", Claims, false, {
					{ Name = "Status", Controls = {
						para("Claims Status", "idle"),
						para("Claims Info", "Daily/Chest/Achievement/Seasonpass Claim() every ~12 min. Playtime Reward has its own 31s poller: it claims the moment the PlaytimeReward attribute reaches 900s (blind claims before readiness are a silent server no-op — that was why it never collected). Admin services are never touched."),
					} },
				}),
				modDef("Auto Potions", Potions, false, {
					{ Name = "Status", Controls = {
						para("Potion Status", "idle"),
						para("Potion Info", "Power potions under Auto Train, Cash under Auto Throw, Luck under Auto Hatch, Cocktail/Royal under any. 300s own timer + decrement confirmation, no refresh-waste."),
					} },
				}),
			},
		},
		{
			Name = "Progress",
			Icon = "movement",
			Modules = {
				modDef("Auto Rebirth", AutoRebirth, false, {
					{ Name = "Tuning", Controls = {
						ctlToggle("rebirth_tutorial_probe", "Allow tutorial probe (one-shot)", true, function(v)
							AutoRebirth.allowTutorialProbe = v
						end),
						ctlSlider("rebirth_regrind", "Max Power regrind (sec)", 30, 300, 10, 120, function(v)
							AutoRebirth.maxRegrind = v
						end),
					} },
					{ Name = "Status", Controls = {
						para("Rebirth Status", "idle"),
						para("Rebirth Info", "Phase 1: single tutorial probe (first rebirth gates game features). Phase 2: press only when the Power regrind estimate is under the cap; every press must be confirmed by the counter, otherwise 30 min backoff. Never on a timer."),
					} },
				}),
				modDef("Auto Class Roll", ClassRoll, false, {
					{ Name = "Tuning", Controls = {
						ctlSlider("class_min_shards", "Min shards to roll", 0, 25, 1, 1, function(v)
							ClassRoll.minShards = v
						end),
					} },
					{ Name = "Status", Controls = {
						para("Class Status", "idle"),
						para("Class Info", "Rolls until Wheelborn or The Insane Wheeler drops, then StopAuto + Equip. Shards drip from throws (~1 per 17 min) — this is a background goal."),
					} },
				}),
			},
		},
		{
			Name = "Misc",
			Icon = "settings",
			Modules = {
				modDef("Anti-AFK", AntiAfk, true, {
					{ Name = "Global limits", Controls = {
						ctlSlider("rate_limit", "Max remotes/sec (hard cap 400)", 30, 400, 10, 80, function(v)
							RATE.cap = math.clamp(v, 30, 400)
						end),
						ctlToggle("probe_rejoin", "Probe Rejoin gamepass autos (1x/session)", true, function() end),
					} },
				}),
				modDef("Live Stats", InfoTicker, true, {
					{ Name = "Stats", Controls = {
						para("Live Stats", "waiting..."),
					} },
				}),
				{
					Name = "Unload Script",
					Enabled = false,
					Callback = function(v)
						if v then task.defer(unloadAll) end
					end,
					Sections = {
						{ Name = "Info", Controls = {
							para("Unload Info", "Flip the toggle to fully unload: stops every loop, disconnects all events, sends TrainingService.Stop if the server auto-train is active and destroys the GUI. Closing the window with X does the same."),
						} },
					},
				},
			},
		},
	},
})

-- bind paragraph control tables for live updates
do
	local BINDINGS = {
		{ "Farm", "Auto Train (Power)", "Status", "Train Status" },
		{ "Farm", "Auto Throw (Cash)", "Status", "Throw Status" },
		{ "Economy", "Auto Buy", "Status", "Buy Status" },
		{ "Economy", "Auto Hatch Eggs", "Status", "Hatch Status" },
		{ "Boosts", "Redeem Codes + Free Eggs", "Status", "Bootstrap Status" },
		{ "Boosts", "Auto Daily Spin", "Status", "Spin Status" },
		{ "Boosts", "Auto Claim Rewards", "Status", "Claims Status" },
		{ "Boosts", "Auto Potions", "Status", "Potion Status" },
		{ "Progress", "Auto Rebirth", "Status", "Rebirth Status" },
		{ "Progress", "Auto Class Roll", "Status", "Class Status" },
		{ "Misc", "Live Stats", "Stats", "Live Stats" },
	}
	for _, b in ipairs(BINDINGS) do
		local entry = State.Paragraphs[b[4]] or {}
		State.Paragraphs[b[4]] = entry
		pcall(function()
			local mod = State.Window:GetModule(b[1], b[2])
			local sec = mod and mod.SectionLookup and mod.SectionLookup[b[3]]
			if sec then
				for _, c in ipairs(sec.Controls) do
					if c.Name == b[4] then entry.control = c break end
				end
			end
		end)
	end
end

-- closing the window with X = full unload (no orphaned loops)
task.defer(function()
	pcall(function()
		local sgui = (gethui and gethui()) or game:GetService("CoreGui")
		local root = sgui and sgui:FindFirstChild("SigmatikClickGui")
		if root then
			table.insert(State.Connections, root.AncestryChanged:Connect(function(_, parent)
				if parent == nil and State.Alive then
					task.defer(unloadAll)
				end
			end))
		end
	end)
end)

--============================ AUTOSTART (включил-и-забыл) ============================
for _, feature in ipairs(autostart) do
	pcall(function() feature:Start() end)
end
