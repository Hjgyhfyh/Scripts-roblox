--[[
	[10M!] Launch a Wheel! — Auto Farm
	placeId: 18916922845
	by tg: @sigmatik323

	Функции:
	- Auto Train (Power): спам TrainingService.RE.Train("W|S") 15-18/с с разогревом и джиттером,
	  авто-выбор максимальной рабочей станции (валидация по дельте Power из серверных пушей),
	  авто-бенчмарк против серверного авто-трейна TrainingService.RE.Start (нулевой спам) — выбирает лучший режим.
	- Auto Throw (Cash): Throw -> Finish строго 1:1, цикл 10.5-11.2s (серверный кулдаун 10s), подтверждение
	  прироста Cash по пушу, один ретрай Finish.
	- Auto Buy: жадная стейт-машина по приоритетам МИР > КОЛЕСО (по Required-цепочке) > PetEquip >
	  PowerBoost/CashBoost/TrainSpeed > RebirthButton, одно действие за тик, каждое подтверждается
	  следующим серверным пушем. Saving-mode на мир. Форма аргумента Upgrade подтверждается первым вызовом.
	- Auto Hatch Eggs: HatchEgg(<лучшее Cash-яйцо>, "Triple") на <=15% Cash, шаг >=4.6s, EquipBest с дебаунсом.
	- Redeem Codes + Free Eggs: одноразовый прогон 24 промокодов (CodesService.RF.Claim, пауза 6s),
	  затем открытие всех Timeless/Void Egg (OpenExclusiveEgg, шаг 4.6s) + EquipBest. Прогресс персистится.
	- Auto Daily Spin: SpinsService.RE.Spin раз в 24ч по DailySpinClaimedTime из профиля.
	- Auto Claim Rewards: DailyRewards/Chest/PlaytimeReward/Achievement/Seasonpass .RE.Claim раз в ~12 мин.
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

-- ####CHUNK2####
