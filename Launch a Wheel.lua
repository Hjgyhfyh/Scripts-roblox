--[[
	[10M!] Launch a Wheel! — Auto Farm (Rayfield edition)
	placeId: 18916922845
	by tg: @sigmatik323

	Переписано на Rayfield, логика упрощена по живому тесту 2026-07-02:
	- Auto Throw: Throw() -> t~10s -> спам Finish() каждые 0.5s до банка (~12.6s серверный пол) -> сразу
	  новый бросок. Цикл ~13s (~40% быстрее старой схемы с одиночным ранним Finish — тот сервер игнорил).
	  Оба ремоута без аргументов, дистанция = f(Power), кэш подтверждается по пушу профиля.
	- Auto Train: Start("W|S") один раз обязателен (Train без сессии даёт 0 Power), затем ровный спам
	  Train("W|S") ~12/с (серверный кредит-кап ~10 тапов/с, быстрее — молча дропается). Авто-выбор лучшей
	  станции: max s с Required.Power<=Power ИЛИ Rebirth>=Required.Rebirth (OR-гейт). Смена станции:
	  Stop -> 1.6s -> Start. Во время InThrow трейн не кредитуется — пауза.
	- Auto Hatch / Auto Event Egg (10M): HatchEgg(name, "Triple"/"Octo") пока хватает Cash, шаг ~4.7s
	  (серверный дебаунс HatchTime 4.5s, чаще — дроп). Без бюджетов/процентов. EquipBest с дебаунсом.
	- Auto Event Pass: SeasonpassService.RE.Claim(track, level) — ФИКС: без (track, level) клейм был
	  тихим no-op, поэтому награды пасса никогда не собирались. Тиры 1..15, Free всегда, Premium по
	  атрибуту PremiumPass. Порог тира = Required[level] * 1.15^Resets.
	- Auto Buy (миры > колёса > апгрейды > rebirth-тиры), Redeem Codes (46 кодов + Timeless/Void Egg),
	  Auto Daily Spin, Auto Claim Rewards (Daily/Chest + Playtime по готовности атрибута; Achievement
	  исключён — его Claim требует id, формат не подтверждён), Auto Potions, Auto Class Roll,
	  Auto Rebirth, Anti-AFK, Live Stats — перенесены без переусложнений.
	- Плавающая draggable кнопка THR/TRN — дёргает те же Rayfield-тумблеры (Toggle:Set), единый стейт.
	- Глобальный rate-limiter (<=400/с), устойчивость к респавну, Unload с полным снятием коннектов.
	Тумблеры/слайдеры персистятся самим Rayfield (ConfigurationSaving SigmatikLW/LaunchAWheel).
]]

local PLACE_ID = 18916922845

--=========================== CLEANUP PREVIOUS ===========================
local SharedEnv = (getgenv and getgenv()) or _G
if SharedEnv.SigmatikLaunchWheelState and SharedEnv.SigmatikLaunchWheelState.Stop then
	pcall(SharedEnv.SigmatikLaunchWheelState.Stop)
	task.wait(0.2)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local function elevate()
	pcall(function()
		local set = setthreadidentity or setidentity or set_thread_identity or (syn and syn.set_thread_identity)
		if set then set(8) end
	end)
end
elevate()

--=========================== KNIT SERVICES ===========================
local KnitServices
do
	local ok, res = pcall(function()
		return ReplicatedStorage:WaitForChild("Library", 20):WaitForChild("Knit", 15):WaitForChild("Services", 15)
	end)
	if not ok or not res then
		warn("[Launch a Wheel] Knit Services not found — wrong game?")
		return
	end
	KnitServices = res
end

--=========================== STATE ===========================
local State = { Alive = true, Connections = {}, SpendBusy = false, LastSpendSerial = 0, MaxCashSeen = 0 }
SharedEnv.SigmatikLaunchWheelState = State
local RUNNING = {}

--=========================== PERSIST (формы аргументов / коды) ===========================
-- Тумблеры/слайдеры хранит Rayfield; тут только то, что Rayfield не умеет.
local PERSIST_FILE = "LaunchAWheel_" .. tostring(PLACE_ID) .. ".json"
local hasFS = (typeof(writefile) == "function") and (typeof(readfile) == "function")
local Persist = {}
do
	if hasFS then
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(PERSIST_FILE)) end)
		if ok and type(data) == "table" then
			-- совместимость со старым файлом ({modules,controls,persist}) — redeemed-коды не теряются
			Persist = type(data.persist) == "table" and data.persist or data
		end
	end
	Persist.redeemed = type(Persist.redeemed) == "table" and Persist.redeemed or {}
end
local saveScheduled = false
local function saveP()
	if not hasFS or saveScheduled then return end
	saveScheduled = true
	task.delay(0.5, function()
		saveScheduled = false
		pcall(function() writefile(PERSIST_FILE, HttpService:JSONEncode({ persist = Persist })) end)
	end)
end

--=========================== HELPERS ===========================
local function num(v) return tonumber(v) or 0 end

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No" }
local function fmt(n)
	n = tonumber(n) or 0
	local neg = n < 0
	n = math.abs(n)
	if n >= 1e33 then return (neg and "-" or "") .. string.format("%.2e", n) end
	if n < 1000 then
		local s = (n == math.floor(n)) and tostring(math.floor(n)) or string.format("%.1f", n)
		return (neg and "-" or "") .. s
	end
	local i = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return (neg and "-" or "") .. string.format("%.2f%s", n / (1000 ^ i), SUFFIX[i + 1])
end

local function attrTruthy(name)
	local ok, v = pcall(function() return LocalPlayer:GetAttribute(name) end)
	if not ok then return false end
	return v == true or (type(v) == "number" and v > 0)
end

local function killThread(th)
	if th then pcall(task.cancel, th) end
end
local function killThreads(t)
	for _, th in ipairs(t or {}) do killThread(th) end
end

--=========================== RATE LIMITER (жёсткий потолок <=400/с) ===========================
local RATE = { cap = 250, tokens = 250, last = os.clock() }
local function waitToken()
	local waited = 0
	while State.Alive do
		local now = os.clock()
		RATE.tokens = math.min(RATE.cap, RATE.tokens + (now - RATE.last) * RATE.cap)
		RATE.last = now
		if RATE.tokens >= 1 then
			RATE.tokens = RATE.tokens - 1
			return
		end
		task.wait(0.01)
		waited = waited + 0.01
		if waited > 4 then return end
	end
end

--=========================== REMOTES (Knit path) ===========================
local remoteCache = {}
local function getRemote(svcName, kind, remoteName)
	local key = svcName .. "/" .. kind .. "/" .. remoteName
	local cached = remoteCache[key]
	if cached and cached.Parent then return cached end
	local ok, remote = pcall(function()
		local svc = KnitServices:FindFirstChild(svcName) or KnitServices:WaitForChild(svcName, 3)
		local folder = svc and (svc:FindFirstChild(kind) or svc:WaitForChild(kind, 2))
		return folder and (folder:FindFirstChild(remoteName) or folder:WaitForChild(remoteName, 2)) or nil
	end)
	if ok and remote then
		remoteCache[key] = remote
		return remote
	end
	return nil
end

local function fireRE(svcName, remoteName, ...)
	local remote = getRemote(svcName, "RE", remoteName)
	if not remote then return false end
	waitToken()
	local args = table.pack(...)
	return pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end)
end

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

--=========================== SERVER MIRROR (HandlerService.RE.Fruits, полный профиль ~2s) ===========================
local Mirror = { profile = nil, serial = 0, at = 0, powerRate = nil, cashRate = nil }

local function Cash()
	local p = Mirror.profile
	return p and num(p.Cash) or 0 -- ТОЛЬКО top-level Cash
end
local function Power()
	local p = Mirror.profile
	return p and num(p.Power) or 0
end
local function RebirthCount()
	local p = Mirror.profile
	return p and num(p.Rebirth) or 0
end

local function acceptProfile(data)
	if type(data) ~= "table" then return end
	if data.Cash == nil and data.Power == nil and data.Items == nil then return end
	local now = os.clock()
	local prev = Mirror.profile
	local dt = Mirror.at > 0 and (now - Mirror.at) or 0
	if prev and dt > 0.3 then
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
	Mirror.profile = data
	Mirror.at = now
	Mirror.serial = Mirror.serial + 1
	if num(data.Cash) > State.MaxCashSeen then State.MaxCashSeen = num(data.Cash) end
end

do
	local fruits = getRemote("HandlerService", "RE", "Fruits")
	if fruits then
		table.insert(State.Connections, fruits.OnClientEvent:Connect(acceptProfile))
	else
		warn("[Launch a Wheel] HandlerService.RE.Fruits not found — mirror unavailable")
	end
end

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

local function waitFreshPush(serialFloor, timeout)
	local t0 = os.clock()
	while State.Alive and Mirror.serial <= serialFloor and os.clock() - t0 < (timeout or 6) do
		task.wait(0.15)
	end
	return Mirror.serial > serialFloor
end

local function intervalLoop(runKey, interval, fn)
	return task.spawn(function()
		while State.Alive and RUNNING[runKey] do
			pcall(fn)
			task.wait(interval)
		end
	end)
end

--=========================== CONFIG MODULES (цены/пороги, деградирует без них) ===========================
local Configs = {}
do
	local WANTED = { TrainingConfig = true, ItemsConfig = true, MapsConfig = true, UpgradesConfig = true, EggsConfig = true, MiscConfig = true }
	local ok, descendants = pcall(function() return ReplicatedStorage:GetDescendants() end)
	if ok and descendants then
		for _, inst in ipairs(descendants) do
			if inst:IsA("ModuleScript") and WANTED[inst.Name] and Configs[inst.Name] == nil then
				local okR, mod = pcall(require, inst)
				if okR and type(mod) == "table" then Configs[inst.Name] = mod end
			end
		end
	end
end

--=========================== WORLDS / ITEMS / EGGS HELPERS ===========================
local WORLD_FALLBACK = {
	[2] = { price = 6.5e8, req = "Shuriken" },
	[3] = { price = 1e15, req = "Skull" },
	[4] = { price = 1e24, req = "Tractor Wheel" },
	[5] = { price = 2e29, req = "Blue PufferFish" },
	[6] = { price = 1e36, req = "UFO" },
}
local function worldInfo(w)
	local mc = Configs.MapsConfig
	if type(mc) == "table" then
		local def = mc[w] or mc[tostring(w)]
		if type(def) == "table" then
			local price = tonumber(def.Price or def.Cost)
			local req = def.RequiredItem or def.Required or def.Item
			if price and type(req) == "string" then return { price = price, req = req } end
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
			if v == true or type(v) == "table" then
				local n = tonumber(k)
				if n and n > maxW then maxW = n end
			end
		end
	end
	return maxW
end
local function worldArg(w)
	if Persist.world_form == "number" then return w end
	return tostring(w)
end
local function ownsItem(name)
	local p = Mirror.profile
	local items = p and p.Items
	return type(items) == "table" and items[name] == true
end

local lastTeleportW = nil
local function teleportToWorld(w)
	if w <= 1 or lastTeleportW == w then return end
	lastTeleportW = w
	fireRE("MapsService", "Teleport", worldArg(w))
end

local function wheelDefs()
	local ic = Configs.ItemsConfig
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
				robux = def.Robux == true,
			}
		end
	end
	return out
end
-- следующее колесо: идём по Required-цепочке от RequiredItem следующего мира
local function nextWheelTarget()
	local defs = wheelDefs()
	if not defs then return nil end
	local function chainFirstUnowned(goal)
		local cur, guard, first = goal, 0, nil
		while cur and guard < 60 do
			guard = guard + 1
			if ownsItem(cur) then break end
			local d = defs[cur]
			if not d or d.robux or not d.price then return nil end
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
	local best
	for name, d in pairs(defs) do
		if not ownsItem(name) and not d.robux and d.price and d.cashMult and (d.required == nil or ownsItem(d.required)) then
			if not best or d.price < best.def.price then best = { name = name, def = d } end
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

local function inventoryCount(name)
	local p = Mirror.profile
	local inv = p and p.Inventory
	if type(inv) ~= "table" then return 0 end
	local v = inv[name]
	if type(v) == "number" then return v end
	if type(v) == "table" then
		return tonumber(v.Count or v.Amount or v.Quantity) or #v
	end
	return 0
end

local lastEquipAt = 0
local function equipBest(force)
	if not force and os.clock() - lastEquipAt < 25 then return end
	lastEquipAt = os.clock()
	fireRE("PetsService", "EquipBest") -- verified: без аргументов
end

-- копим на следующий мир: яйца/апгрейды на паузе, когда собрано >=30% цены
local function savingMode()
	local nw = maxOwnedWorld() + 1
	local wd = worldInfo(nw)
	if wd and ownsItem(wd.req) and Cash() >= wd.price * 0.30 then return true, nw end
	return false, nil
end

local function eggPrice(name)
	local ec = Configs.EggsConfig
	local def = type(ec) == "table" and ec[name] or nil
	local p = type(def) == "table" and tonumber(def.Price or def.Cost) or nil
	if p then return p end
	if name == "Basic Egg" then return 75 end
	if name == "10M Egg" then return 1e7 end
	return nil
end
local function eggOptions()
	local out = {}
	local ec = Configs.EggsConfig
	if type(ec) == "table" then
		local list = {}
		for name, def in pairs(ec) do
			if type(name) == "string" and type(def) == "table" then
				local price = tonumber(def.Price or def.Cost)
				local robux = def.Robux == true or def.RobuxOnly == true
				local excl = def.Exclusive == true or name:find("Timeless") ~= nil or name:find("Void") ~= nil
				if price and price > 0 and not robux and not excl and name ~= "10M Egg" then
					table.insert(list, { name = name, price = price })
				end
			end
		end
		table.sort(list, function(a, b) return a.price < b.price end)
		for _, e in ipairs(list) do table.insert(out, e.name) end
	end
	local hasBasic = false
	for _, n in ipairs(out) do
		if n == "Basic Egg" then
			hasBasic = true
			break
		end
	end
	if not hasBasic then table.insert(out, 1, "Basic Egg") end
	return out
end
local function hatchMode()
	if attrTruthy("OctoHatch") then return "Octo", 8 end
	return "Triple", 3
end
local function eventOver()
	local mc = Configs.MiscConfig
	local ts = type(mc) == "table" and tonumber(mc.EventEndTimestamp) or nil
	return ts ~= nil and os.time() > ts
end

--=========================== AUTO TRAIN (Power) ===========================
-- Live-verified: Start("W|S") один раз -> спам Train("W|S") ~10-12/с (~7x быстрее серверного авто-лупа).
local TrainFarm = { thread = nil, w = nil, s = nil, rate = 12, needStart = true, lastStartAt = 0, repickNow = false, taps = 0, status = "idle" }

local function bestStation()
	local w = maxOwnedWorld()
	local best = 1
	local tc = Configs.TrainingConfig
	if type(tc) == "table" then
		local wt = tc[w] or tc[tostring(w)]
		if type(wt) == "table" then
			local pw, rb = Power(), RebirthCount()
			for i = 1, 30 do
				local st = wt[i] or wt[tostring(i)]
				if type(st) == "table" then
					local req = st.Required or st.Require
					local rp = (type(req) == "table" and tonumber(req.Power)) or tonumber(st.RequiredPower) or 0
					local rr = (type(req) == "table" and tonumber(req.Rebirth)) or nil
					if rp <= pw or (rr and rb >= rr) then best = i end -- OR-гейт (подтверждено)
				end
			end
		end
	end
	return w, best
end

function TrainFarm:loop()
	local nextPick = 0
	while State.Alive and RUNNING.train do
		if not Mirror.profile then
			self.status = "waiting profile"
			task.wait(0.5)
		elseif attrTruthy("InThrow") then
			self.needStart = true -- сессию сбросило броском
			self.status = "paused: InThrow"
			task.wait(0.4)
		else
			if self.repickNow or os.clock() >= nextPick then
				self.repickNow = false
				nextPick = os.clock() + 5
				local w, s = bestStation()
				if w ~= self.w or s ~= self.s then
					if self.w then
						fireRE("TrainingService", "Stop")
						task.wait(1.6) -- verified: пауза перед Start на новой станции
					end
					if w ~= self.w then teleportToWorld(w) end
					self.w, self.s = w, s
					self.needStart = true
				end
			end
			local arg = tostring(self.w) .. "|" .. tostring(self.s)
			if (self.needStart or not attrTruthy("Training")) and os.clock() - self.lastStartAt > 2.5 then
				self.lastStartAt = os.clock()
				self.needStart = false
				fireRE("TrainingService", "Start", arg) -- ОБЯЗАТЕЛЬНО: Train без сессии даёт 0
				task.wait(0.3)
			end
			fireRE("TrainingService", "Train", arg)
			self.taps = self.taps + 1
			self.status = string.format("station %s | taps %d", arg, self.taps)
			task.wait(1 / math.clamp(self.rate, 4, 20))
		end
	end
end
function TrainFarm:Start()
	if RUNNING.train then return end
	RUNNING.train = true
	self.needStart = true
	self.repickNow = true
	self.thread = task.spawn(function() self:loop() end)
end
function TrainFarm:Stop()
	if not RUNNING.train then return end
	RUNNING.train = false
	killThread(self.thread)
	self.thread = nil
	fireRE("TrainingService", "Stop")
	self.status = "idle"
end

--=========================== AUTO THROW (Cash) ===========================
-- Live-verified: жёсткий серверный пол ~12.6s на бросок; одиночный ранний Finish игнорится,
-- а спам Finish через отметку ~12.6s банкует на полу (вместо ~18.5s у клиентского авто-Finish).
local ThrowFarm = { thread = nil, cycleSec = 13, throws = 0, banked = 0, lastGain = 0, status = "idle" }

function ThrowFarm:loop()
	while State.Alive and RUNNING.throw do
		local throwR = getRemote("ThrowService", "RE", "Throw")
		local finishR = getRemote("ThrowService", "RE", "Finish")
		if not throwR or not finishR or not Mirror.profile then
			self.status = "waiting remotes/profile"
			task.wait(1)
		elseif attrTruthy("InThrow") then
			-- хвост прошлого полёта (респавн/перезапуск): добиваем Finish'ем
			self.status = "clearing leftover flight"
			local d = os.clock() + 20
			while State.Alive and RUNNING.throw and attrTruthy("InThrow") and os.clock() < d do
				waitToken()
				pcall(function() finishR:FireServer() end)
				task.wait(0.6)
			end
		else
			if attrTruthy("Training") then
				-- бросок из тренировочной сессии не идёт — снимаем её, трейн сам перезапустится
				fireRE("TrainingService", "Stop")
				TrainFarm.needStart = true
				task.wait(0.35)
			end
			local before = Cash()
			local t0 = os.clock()
			waitToken()
			pcall(function() throwR:FireServer() end) -- без аргументов
			self.throws = self.throws + 1
			self.status = string.format("flight... (throw #%d)", self.throws)
			while State.Alive and RUNNING.throw and os.clock() - t0 < 10 do
				task.wait(0.25)
			end
			-- спам Finish через серверный пол ~12.6s
			local banked = false
			while State.Alive and RUNNING.throw and os.clock() - t0 < 21 do
				waitToken()
				pcall(function() finishR:FireServer() end)
				task.wait(0.5)
				if Cash() > before then
					banked = true
					break
				end
				if os.clock() - t0 > 11 and not attrTruthy("InThrow") then break end
			end
			-- лёгкое подтверждение по пушу (~2s)
			local confirmUntil = os.clock() + 2.5
			while State.Alive and RUNNING.throw and not banked and os.clock() < confirmUntil do
				if Cash() > before then
					banked = true
					break
				end
				task.wait(0.2)
			end
			if banked then
				self.banked = self.banked + 1
				self.lastGain = math.max(0, Cash() - before)
			end
			self.status = string.format("throws %d | banked %d | last +%s", self.throws, self.banked, fmt(self.lastGain))
			local left = self.cycleSec - (os.clock() - t0)
			if left > 0 then task.wait(left) end
			task.wait(0.3)
		end
	end
end
function ThrowFarm:Start()
	if RUNNING.throw then return end
	RUNNING.throw = true
	self.thread = task.spawn(function() self:loop() end)
end
function ThrowFarm:Stop()
	if not RUNNING.throw then return end
	RUNNING.throw = false
	killThread(self.thread)
	self.thread = nil
	self.status = "idle"
end

--=========================== AUTO BUY (мир > колесо > апгрейды > rebirth-тиры) ===========================
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
local function upgPrice(track, lvl)
	local uc = Configs.UpgradesConfig
	local def = type(uc) == "table" and uc[track]
	if type(def) == "table" then
		for _, src in ipairs({ def.Prices, def.Price, def.Costs, def.Cost, def }) do
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

local AutoBuy = { threads = nil, worldCooldownUntil = 0, wheelCooldown = {}, status = "idle" }

-- форма аргумента Upgrade подтверждается первым же вызовом (по росту уровня в пуше)
local UpgradeState = { form = Persist.upgrade_form, probing = false, broken = false }
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
			waitFreshPush(Mirror.serial, 3)
			if upgLevel(track) > before then
				UpgradeState.form = form
				Persist.upgrade_form = form
				saveP()
				UpgradeState.probing = false
				return
			end
		end
		UpgradeState.broken = true
		AutoBuy.status = "Upgrade no-op во всех формах — авто-апгрейды на паузе"
		UpgradeState.probing = false
	end)
	return true
end

function AutoBuy:buyWorld(w)
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
			s = Mirror.serial
			fireRE("MapsService", "Buy", w) -- одна проба number-формы, потом она запоминается
			waitFreshPush(s, 5)
			waitFreshPush(Mirror.serial, 4)
			if confirmed() then
				Persist.world_form = "number"
				saveP()
			end
		end
		if confirmed() then
			self.status = "bought world " .. tostring(w)
			lastTeleportW = nil
			teleportToWorld(w)
			TrainFarm.repickNow = true
		else
			self.status = "world " .. tostring(w) .. " no-op, backoff"
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
		fireRE("ItemsService", "Buy", name)
		waitFreshPush(s, 5)
		waitFreshPush(Mirror.serial, 4)
		if ownsItem(name) then
			self.status = "bought " .. name
			if (target.def.cashMult or 0) > equippedCashMult() then
				local s2 = Mirror.serial
				fireRE("ItemsService", "Equip", name)
				waitFreshPush(s2, 5)
				local p = Mirror.profile
				if not (p and p.EquippedItem == name) then
					fireRE("ItemsService", "Equip", name, "Wheel") -- fallback-форма, один раз
				end
			end
		else
			self.status = name .. " no-op, backoff"
			self.wheelCooldown[name] = os.clock() + 30
		end
		State.SpendBusy = false
	end)
end

function AutoBuy:tick()
	local p = Mirror.profile
	if not p or State.SpendBusy then return end
	if Mirror.serial <= State.LastSpendSerial then return end -- тратим только против свежего пуша
	local cash = Cash()
	-- 1) мир — доминирующий множитель
	if os.clock() > self.worldCooldownUntil then
		local nw = maxOwnedWorld() + 1
		local wd = worldInfo(nw)
		if wd and ownsItem(wd.req) and cash >= wd.price then
			self:buyWorld(nw)
			return
		end
	end
	local saving, savingW = savingMode()
	-- 2) цепочка колёс (разрешена и в saving-режиме)
	local target = nextWheelTarget()
	if target and target.name and target.def.price then
		local cd = self.wheelCooldown[target.name]
		if (not cd or os.clock() > cd) and cash >= target.def.price then
			self:buyWheel(target)
			return
		end
	end
	if saving then
		local wd = worldInfo(savingW)
		self.status = string.format("saving for world %d (%s / %s)", savingW, fmt(cash), fmt(wd and wd.price or 0))
		return
	end
	if UpgradeState.broken then return end
	-- 3) PetEquip (<=10% Cash) > PowerBoost/CashBoost/TrainSpeed (<=2%) > RebirthButton (<=1%)
	local lvl = upgLevel("PetEquip")
	if lvl < UPG_CAPS.PetEquip then
		local price = upgPrice("PetEquip", lvl + 1)
		if price and price <= cash * 0.10 and doUpgrade("PetEquip") then
			self.status = "PetEquip -> " .. tostring(lvl + 1)
			task.delay(6, function() equipBest(true) end)
			return
		end
	end
	for _, track in ipairs({ "PowerBoost", "CashBoost", "TrainSpeed" }) do
		local l = upgLevel(track)
		if l < (UPG_CAPS[track] or 40) then
			local price = upgPrice(track, l + 1)
			if price and price <= cash * 0.02 and doUpgrade(track) then
				self.status = track .. " -> " .. tostring(l + 1)
				return
			end
		end
	end
	local rl = upgLevel("RebirthButton")
	if rl < UPG_CAPS.RebirthButton then
		local price = upgPrice("RebirthButton", rl + 1)
		if price and price <= cash * 0.01 and doUpgrade("RebirthButton") then
			self.status = "RebirthButton -> " .. tostring(rl + 1)
			return
		end
	end
end

function AutoBuy:Start()
	if RUNNING.buy then return end
	RUNNING.buy = true
	self.threads = { intervalLoop("buy", 3.2, function() self:tick() end) }
end
function AutoBuy:Stop()
	RUNNING.buy = false
	killThreads(self.threads)
	self.threads = nil
	self.status = "idle"
end

--=========================== AUTO HATCH (обычные яйца, без бюджетов) ===========================
-- Live-verified: HatchEgg(name, mode) работает headless, серверный дебаунс ~4.5s (чаще — дроп).
local HatchFarm = { thread = nil, egg = "Basic Egg", hatches = 0, status = "idle" }
function HatchFarm:loop()
	while State.Alive and RUNNING.hatch do
		local step = 4.7 + math.random() * 0.4
		local p = Mirror.profile
		if not p then
			self.status = "waiting profile"
		elseif RUNNING.buy and savingMode() then
			self.status = "paused: saving for world"
		else
			local price = eggPrice(self.egg)
			local mode, mult = hatchMode()
			local cost = price and price * mult or nil
			if cost and Cash() >= cost then
				fireRE("EggsService", "HatchEgg", self.egg, mode) -- verified: (string, string)
				self.hatches = self.hatches + 1
				self.status = string.format("%s (%s) x%d", self.egg, mode, self.hatches)
				equipBest(false)
			elseif cost then
				self.status = string.format("waiting cash %s / %s", fmt(Cash()), fmt(cost))
			else
				self.status = "no price for " .. tostring(self.egg)
			end
		end
		task.wait(step)
	end
end
function HatchFarm:Start()
	if RUNNING.hatch then return end
	RUNNING.hatch = true
	self.thread = task.spawn(function() self:loop() end)
end
function HatchFarm:Stop()
	RUNNING.hatch = false
	killThread(self.thread)
	self.thread = nil
	self.status = "idle"
end

--=========================== AUTO EVENT EGG (10M Egg) ===========================
local EventEgg = { thread = nil, hatches = 0, status = "idle" }
function EventEgg:loop()
	while State.Alive and RUNNING.eventegg do
		local step = 4.7 + math.random() * 0.4
		local p = Mirror.profile
		if eventOver() then
			self.status = "event over (EventEndTimestamp)"
			task.wait(30)
		elseif not p then
			self.status = "waiting profile"
			task.wait(1)
		elseif RUNNING.buy and savingMode() then
			self.status = "paused: saving for world"
			task.wait(step)
		else
			local mode, mult = hatchMode()
			local cost = (eggPrice("10M Egg") or 1e7) * mult
			if Cash() >= cost then
				fireRE("EggsService", "HatchEgg", "10M Egg", mode) -- verified: ровно -10M за Single
				self.hatches = self.hatches + 1
				self.status = string.format("10M Egg (%s) x%d", mode, self.hatches)
				equipBest(false)
			else
				self.status = string.format("waiting cash %s / %s", fmt(Cash()), fmt(cost))
			end
			task.wait(step)
		end
	end
end
function EventEgg:Start()
	if RUNNING.eventegg then return end
	RUNNING.eventegg = true
	self.thread = task.spawn(function() self:loop() end)
end
function EventEgg:Stop()
	RUNNING.eventegg = false
	killThread(self.thread)
	self.thread = nil
	self.status = "idle"
end

--=========================== AUTO EVENT PASS (ФИКС: Claim(track, level)) ===========================
local PASS_REQ = { 200, 400, 650, 1000, 1400, 1850, 2400, 2950, 3625, 4300, 5000, 5800, 6750, 8000, 9500 }
local EventPass = { threads = nil, fires = 0, status = "idle" }
local function passBase(p)
	if p.Seasonpass2XP ~= nil then return "Seasonpass2" end
	for k in pairs(p) do
		if type(k) == "string" then
			local base = k:match("^(Seasonpass%d+)XP$")
			if base then return base end
		end
	end
	return nil
end
function EventPass:sweep()
	local p = Mirror.profile
	if not p then
		self.status = "waiting profile"
		return
	end
	local base = passBase(p)
	if not base then
		self.status = "no seasonpass keys in profile"
		return
	end
	local xp = num(p[base .. "XP"])
	local mult = 1.15 ^ num(p[base .. "Resets"])
	local claimed = p[base .. "ClaimedRewards"]
	local tracks = { "Free" }
	if attrTruthy("PremiumPass") then table.insert(tracks, "Premium") end
	local firedNow = 0
	for level = 1, #PASS_REQ do
		if xp >= PASS_REQ[level] * mult then
			for _, track in ipairs(tracks) do
				local ct = (type(claimed) == "table" and type(claimed[track]) == "table") and claimed[track] or {}
				if not (ct[tostring(level)] or ct[level]) then
					if not (State.Alive and RUNNING.pass) then return end
					fireRE("SeasonpassService", "Claim", track, level) -- verified: (track, level)
					firedNow = firedNow + 1
					self.fires = self.fires + 1
					task.wait(0.45)
				end
			end
		end
	end
	self.status = string.format("%s XP %s | claimed now %d | total %d", base, fmt(xp), firedNow, self.fires)
end
function EventPass:Start()
	if RUNNING.pass then return end
	RUNNING.pass = true
	self.threads = { intervalLoop("pass", 40, function() self:sweep() end) }
end
function EventPass:Stop()
	RUNNING.pass = false
	killThreads(self.threads)
	self.threads = nil
	self.status = "idle"
end

--=========================== REDEEM CODES + FREE EXCLUSIVE EGGS ===========================
local CODES = {
	"money", "release", "lucky", "power", "cash", "time", "void", "update1", "update3",
	"banana", "apple", "500k", "voidyy", "charmroot", "applepower", "coinbanana",
	"mixpotion", "darkegg", "darkduo", "ancient", "eraeggs", "riftage", "grateful", "crownpotion",
	"clovy", "applo", "banzy", "brewz", "vexon", "duovo", "tikto", "chron", "eclip", "thank",
	"rexal", "crown", "cheers", "riftpack", "agepack", "clockegg", "abyssduo", "abyssegg",
	"mixdrink", "richfruit", "powerfruit", "luckyroot",
}
local Codes = { thread = nil, status = "idle" }
function Codes:Start()
	if RUNNING.codes then return end
	RUNNING.codes = true
	self.thread = task.spawn(function()
		-- фаза 1: промокоды (клиентский кулдаун 5s -> шаг 6.2s; гейт по каждому коду, персистится)
		local total, done = #CODES, 0
		for _, code in ipairs(CODES) do
			if not (State.Alive and RUNNING.codes) then return end
			if Persist.redeemed[code] then
				done = done + 1
			else
				self.status = string.format("code %d/%d: %s", done + 1, total, code)
				invokeRF("CodesService", "Claim", 8, code) -- invalid/expired = скип
				Persist.redeemed[code] = true
				done = done + 1
				saveP()
				task.wait(6.2)
			end
		end
		-- фаза 2: открыть все Timeless/Void Egg из инвентаря
		task.wait(3)
		for _, eggName in ipairs({ "Timeless Egg", "Void Egg" }) do
			local misses = 0
			while State.Alive and RUNNING.codes do
				local count = inventoryCount(eggName)
				if count < 1 or misses >= 3 then break end
				self.status = string.format("opening %s (%d left)", eggName, count)
				fireRE("EggsService", "OpenExclusiveEgg", eggName)
				task.wait(4.7 + math.random() * 0.4)
				if inventoryCount(eggName) >= count then misses = misses + 1 else misses = 0 end
			end
		end
		equipBest(true)
		self.status = "done (codes + exclusive eggs)"
	end)
end
function Codes:Stop()
	RUNNING.codes = false
	killThread(self.thread)
	self.thread = nil
end

--=========================== AUTO DAILY SPIN ===========================
local DailySpin = { threads = nil, lastFireAt = 0, status = "idle" }
function DailySpin:Start()
	if RUNNING.spin then return end
	RUNNING.spin = true
	self.threads = { intervalLoop("spin", 60, function()
		local p = Mirror.profile
		if not p then return end
		local last = (type(p.DailySpinClaimedTime) == "number") and p.DailySpinClaimedTime or nil
		if last then
			local left = 86400 - (os.time() - last)
			if left <= 0 and os.clock() - self.lastFireAt > 600 then
				self.lastFireAt = os.clock()
				fireRE("SpinsService", "Spin")
				self.status = "spin fired"
			elseif left > 0 then
				self.status = string.format("next in %dh %dm", math.floor(left / 3600), math.floor(left % 3600 / 60))
			end
		else
			local today = os.date("%Y-%m-%d")
			if Persist.last_spin_day ~= today then
				Persist.last_spin_day = today
				saveP()
				fireRE("SpinsService", "Spin")
				self.status = "spin fired (day guard)"
			end
		end
	end) }
end
function DailySpin:Stop()
	RUNNING.spin = false
	killThreads(self.threads)
	self.threads = nil
	self.status = "idle"
end

--=========================== AUTO CLAIM REWARDS (без сизонпасса — он отдельно) ===========================
-- Daily/Chest: Claim() без аргументов (verified). Achievement.Claim требует (id) — исключён.
-- Playtime: клейм строго по готовности атрибута PlaytimeReward (слепой клейм = тихий no-op).
local Claims = { threads = nil, rounds = 0, playtime = 0, status = "idle" }
function Claims:Start()
	if RUNNING.claims then return end
	RUNNING.claims = true
	self.threads = {
		intervalLoop("claims", 720, function()
			fireRE("DailyRewardsService", "Claim")
			task.wait(1.2)
			fireRE("ChestService", "Claim")
			self.rounds = self.rounds + 1
			self.status = string.format("rounds %d | playtime x%d", self.rounds, self.playtime)
		end),
		intervalLoop("claims", 31, function()
			local acc = 0
			pcall(function() acc = num(LocalPlayer:GetAttribute("PlaytimeReward")) end)
			local mc = Configs.MiscConfig
			local ready = (type(mc) == "table" and tonumber(mc.PlaytimeRewardTime)) or 900
			if acc >= ready then
				fireRE("PlaytimeRewardService", "Claim") -- verified: без аргументов, только по готовности
				self.playtime = self.playtime + 1
				self.status = string.format("rounds %d | playtime x%d", self.rounds, self.playtime)
			end
		end),
	}
end
function Claims:Stop()
	RUNNING.claims = false
	killThreads(self.threads)
	self.threads = nil
	self.status = "idle"
end

--=========================== AUTO POTIONS ===========================
local Potions = { threads = nil, timers = {}, pending = nil, status = "idle" }
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
	self.threads = { intervalLoop("potions", 20, function()
		local p = Mirror.profile
		local inv = p and p.Inventory
		if type(inv) ~= "table" then return end
		if self.pending then -- подтверждаем прошлый Use по декременту
			if inventoryCount(self.pending.name) < self.pending.count then
				self.timers[self.pending.name] = os.clock() + 305 -- PotionTime=300
				self.status = "active: " .. self.pending.name
			else
				self.timers[self.pending.name] = os.clock() + 120
			end
			self.pending = nil
			return
		end
		for name in pairs(inv) do
			if type(name) == "string" and name:find("Potion") then
				local cat = potionCategory(name)
				local wanted = (cat == "any" and (RUNNING.train or RUNNING.throw or RUNNING.hatch))
					or (cat == "train" and RUNNING.train)
					or (cat == "throw" and RUNNING.throw)
					or (cat == "hatch" and RUNNING.hatch)
				local cd = self.timers[name]
				if wanted and (not cd or os.clock() > cd) and inventoryCount(name) >= 1 then
					self.pending = { name = name, count = inventoryCount(name) }
					fireRE("InventoryService", "Use", name, 1) -- verified: (string, number)
					self.status = "using " .. name
					return
				end
			end
		end
	end) }
end
function Potions:Stop()
	RUNNING.potions = false
	killThreads(self.threads)
	self.threads = nil
	self.status = "idle"
end

--=========================== AUTO CLASS ROLL ===========================
local CLASS_TARGETS = { "Wheelborn", "The Insane Wheeler" }
local ClassRoll = { threads = nil, done = false, status = "idle" }
function ClassRoll:ownedTarget()
	local p = Mirror.profile
	if not p then return nil end
	for _, pool in ipairs({ p.Classes, p.OwnedClasses }) do
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
function ClassRoll:Start()
	if RUNNING.class then return end
	RUNNING.class = true
	self.threads = { intervalLoop("class", 50, function()
		if not Mirror.profile then return end
		local target = self:ownedTarget()
		if target then
			if not self.done then
				self.done = true
				fireRE("ClassesService", "StopAuto")
				task.wait(0.5)
				fireRE("ClassesService", "Equip", target)
			end
			self.status = "done: " .. target
			return
		end
		fireRE("ClassesService", "Roll")
		self.status = "rolling..."
	end) }
end
function ClassRoll:Stop()
	RUNNING.class = false
	killThreads(self.threads)
	self.threads = nil
	self.status = "idle"
end

--=========================== AUTO REBIRTH ===========================
local AutoRebirth = { threads = nil, maxRegrind = 120, lastPressAt = 0, backoffUntil = 0, status = "idle" }
function AutoRebirth:tutorialDone()
	if Persist.rebirth_tutorial_done then return true end
	local p = Mirror.profile
	local tut = p and p.Tutorial
	if (type(tut) == "table" and tut.Rebirth == true) or (p and num(p.Rebirth) > 0) then
		Persist.rebirth_tutorial_done = true
		saveP()
		return true
	end
	return false
end
function AutoRebirth:press()
	local before = RebirthCount()
	local cashBefore = Cash()
	local s = Mirror.serial
	if Persist.rebirth_form == "tier1" then
		fireRE("RebirthService", "Rebirth", 1)
	else
		fireRE("RebirthService", "Rebirth")
	end
	waitFreshPush(s, 5)
	waitFreshPush(Mirror.serial, 4)
	if RebirthCount() > before then
		Persist.rebirth_cash_resets = Cash() < cashBefore * 0.5
		saveP()
		return true
	end
	if Persist.rebirth_form ~= "tier1" then -- одна проба формы с тиром
		s = Mirror.serial
		fireRE("RebirthService", "Rebirth", 1)
		waitFreshPush(s, 5)
		waitFreshPush(Mirror.serial, 4)
		if RebirthCount() > before then
			Persist.rebirth_form = "tier1"
			Persist.rebirth_cash_resets = Cash() < cashBefore * 0.5
			saveP()
			return true
		end
	end
	return false
end
function AutoRebirth:step()
	if not Mirror.profile or State.SpendBusy then return end
	if os.clock() < self.backoffUntil then return end
	if not self:tutorialDone() then
		-- фаза 1: одноразовая туториал-проба (первый rebirth гейтит фичи игры)
		local probes = num(Persist.rebirth_probe_count)
		if probes >= 6 then
			self.status = "tutorial probe limit"
			return
		end
		if Cash() >= 2000 and Power() >= 1000 then
			Persist.rebirth_probe_count = probes + 1
			saveP()
			self.status = "tutorial rebirth probe..."
			if self:press() then
				Persist.rebirth_tutorial_done = true
				saveP()
				self.status = "tutorial rebirth DONE"
				self.lastPressAt = os.clock()
			else
				self.status = "tutorial probe no-op, backoff 10m"
				self.backoffUntil = os.clock() + 600
			end
		else
			self.status = string.format("tutorial gate: Cash>=2k (%s) & Power>=1k (%s)", fmt(Cash()), fmt(Power()))
		end
		return
	end
	-- фаза 2: только когда регринд Power дешёвый, каждое нажатие подтверждается счётчиком
	if os.clock() - self.lastPressAt < 600 then
		self.status = "cooldown between presses"
		return
	end
	local rate = Mirror.powerRate
	if not rate or rate <= 0 then
		self.status = "need power rate (enable Auto Train)"
		return
	end
	local regrind = Power() / rate
	if regrind >= self.maxRegrind then
		self.status = string.format("regrind %ds >= %ds cap", math.floor(regrind), self.maxRegrind)
		return
	end
	if Persist.rebirth_cash_resets == true and Cash() > State.MaxCashSeen * 0.15 then
		self.status = "cash resets: waiting low balance"
		return
	end
	self.status = "pressing rebirth..."
	self.lastPressAt = os.clock()
	if self:press() then
		self.status = "rebirth confirmed"
		TrainFarm.repickNow = true
		TrainFarm.needStart = true
		task.delay(4, function() -- вернуть лучшее колесо, если слетело
			local defs = wheelDefs()
			if not defs then return end
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
		end)
	else
		self.status = "press no-op, backoff 30m"
		self.backoffUntil = os.clock() + 1800
	end
end
function AutoRebirth:Start()
	if RUNNING.rebirth then return end
	RUNNING.rebirth = true
	self.threads = { intervalLoop("rebirth", 6, function() self:step() end) }
end
function AutoRebirth:Stop()
	RUNNING.rebirth = false
	killThreads(self.threads)
	self.threads = nil
	self.status = "idle"
end

--=========================== ANTI-AFK ===========================
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
end
function AntiAfk:Stop()
	RUNNING.afk = false
	for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end
	self.conns = {}
end

--=========================== LIVE STATS TICKER ===========================
local updateUI -- назначается после сборки GUI
local Ticker = { threads = nil }
function Ticker:Start()
	if RUNNING.info then return end
	RUNNING.info = true
	self.threads = { intervalLoop("info", 1, function()
		if updateUI then updateUI() end
	end) }
end
function Ticker:Stop()
	RUNNING.info = false
	killThreads(self.threads)
	self.threads = nil
end

--=========================== WATCHDOGS (respawn / stale mirror) ===========================
table.insert(State.Connections, RunService.Heartbeat:Connect(function()
	if State.Alive and Mirror.at > 0 and os.clock() - Mirror.at > 20 and (RUNNING.train or RUNNING.throw or RUNNING.buy) then
		pullProfileOnce()
	end
end))
table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(function()
	task.delay(3, function()
		if not State.Alive then return end
		TrainFarm.needStart = true
		TrainFarm.repickNow = true
		if RUNNING.train or RUNNING.throw then
			local w = maxOwnedWorld()
			if w > 1 then
				lastTeleportW = nil
				teleportToWorld(w)
			end
		end
	end)
end))

--=========================== UNLOAD ===========================
local Rayfield
local QuickBarGui
local FEATURES = { TrainFarm, ThrowFarm, AutoBuy, HatchFarm, EventEgg, EventPass, Codes, DailySpin, Claims, Potions, ClassRoll, AutoRebirth, Ticker }
local unloaded = false
local function unloadAll()
	if unloaded then return end
	unloaded = true
	State.Alive = false
	for _, f in ipairs(FEATURES) do
		pcall(function() f:Stop() end)
	end
	pcall(function() AntiAfk:Stop() end)
	for _, c in ipairs(State.Connections) do
		local t = typeof(c)
		if t == "RBXScriptConnection" then
			pcall(function() c:Disconnect() end)
		elseif t == "thread" then
			pcall(task.cancel, c)
		end
	end
	State.Connections = {}
	pcall(function() if QuickBarGui then QuickBarGui:Destroy() end end)
	QuickBarGui = nil
	pcall(function() if Rayfield then Rayfield:Destroy() end end)
	pcall(function() writefile(PERSIST_FILE, HttpService:JSONEncode({ persist = Persist })) end)
	if SharedEnv.SigmatikLaunchWheelState == State then
		SharedEnv.SigmatikLaunchWheelState = nil
	end
end
State.Stop = unloadAll

--=========================== GUI (Rayfield) ===========================
elevate()
do
	local ok, lib = pcall(function()
		return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
	end)
	if ok and type(lib) == "table" then Rayfield = lib end
end
if not Rayfield then
	warn("[Launch a Wheel] failed to load Rayfield — unloading")
	unloadAll()
	return
end

local function onToggle(feature)
	return function(v)
		if v then
			pcall(function() feature:Start() end)
		else
			pcall(function() feature:Stop() end)
		end
	end
end

elevate() -- identity 8 прямо перед CreateWindow (yield сбрасывает identity)
local Window = Rayfield:CreateWindow({
	Name = "[10M] Launch a Wheel | tg: @sigmatik323",
	LoadingTitle = "Launch a Wheel — Auto Farm",
	LoadingSubtitle = "by @sigmatik323",
	ConfigurationSaving = { Enabled = true, FolderName = "SigmatikLW", FileName = "LaunchAWheel" },
	KeySystem = false,
})

-- Farm
local TabFarm = Window:CreateTab("Farm")
TabFarm:CreateSection("Auto Throw (Cash)")
local ThrowToggle = TabFarm:CreateToggle({
	Name = "Auto Throw",
	CurrentValue = false,
	Flag = "AutoThrow",
	Callback = onToggle(ThrowFarm),
})
TabFarm:CreateSlider({
	Name = "Min cycle",
	Range = { 13, 15 },
	Increment = 0.5,
	Suffix = "s",
	CurrentValue = 13,
	Flag = "ThrowCycle",
	Callback = function(v) ThrowFarm.cycleSec = math.clamp(tonumber(v) or 13, 13, 15) end,
})
TabFarm:CreateSection("Auto Train (Power)")
local TrainToggle = TabFarm:CreateToggle({
	Name = "Auto Train",
	CurrentValue = false,
	Flag = "AutoTrain",
	Callback = onToggle(TrainFarm),
})
TabFarm:CreateSlider({
	Name = "Train taps",
	Range = { 6, 14 },
	Increment = 1,
	Suffix = "/s",
	CurrentValue = 12,
	Flag = "TrainRate",
	Callback = function(v) TrainFarm.rate = math.clamp(tonumber(v) or 12, 4, 20) end,
})
local FarmPara = TabFarm:CreateParagraph({ Title = "Status", Content = "idle" })

-- Eggs
local TabEggs = Window:CreateTab("Eggs")
TabEggs:CreateSection("Auto Hatch")
TabEggs:CreateToggle({
	Name = "Auto Hatch",
	CurrentValue = false,
	Flag = "AutoHatch",
	Callback = onToggle(HatchFarm),
})
TabEggs:CreateDropdown({
	Name = "Egg",
	Options = eggOptions(),
	CurrentOption = { "Basic Egg" },
	MultipleOptions = false,
	Flag = "EggChoice",
	Callback = function(opt)
		local v = (type(opt) == "table") and opt[1] or opt
		if type(v) == "string" and #v > 0 then HatchFarm.egg = v end
	end,
})
TabEggs:CreateSection("Event")
TabEggs:CreateToggle({
	Name = "Auto Event Egg (10M)",
	CurrentValue = false,
	Flag = "AutoEventEgg",
	Callback = onToggle(EventEgg),
})
local EggPara = TabEggs:CreateParagraph({ Title = "Status", Content = "idle" })

-- Economy
local TabEco = Window:CreateTab("Economy")
TabEco:CreateToggle({
	Name = "Auto Buy (worlds > wheels > upgrades)",
	CurrentValue = false,
	Flag = "AutoBuy",
	Callback = onToggle(AutoBuy),
})
TabEco:CreateToggle({
	Name = "Auto Rebirth",
	CurrentValue = false,
	Flag = "AutoRebirth",
	Callback = onToggle(AutoRebirth),
})
local EcoPara = TabEco:CreateParagraph({ Title = "Status", Content = "idle" })

-- Rewards
local TabRew = Window:CreateTab("Rewards")
TabRew:CreateToggle({
	Name = "Auto Event Pass",
	CurrentValue = false,
	Flag = "AutoPass",
	Callback = onToggle(EventPass),
})
TabRew:CreateToggle({
	Name = "Auto Claim Rewards",
	CurrentValue = false,
	Flag = "AutoClaims",
	Callback = onToggle(Claims),
})
TabRew:CreateToggle({
	Name = "Auto Daily Spin",
	CurrentValue = false,
	Flag = "AutoSpin",
	Callback = onToggle(DailySpin),
})
TabRew:CreateToggle({
	Name = "Redeem Codes + Free Eggs",
	CurrentValue = false,
	Flag = "AutoCodes",
	Callback = onToggle(Codes),
})
local RewPara = TabRew:CreateParagraph({ Title = "Status", Content = "idle" })

-- Misc
local TabMisc = Window:CreateTab("Misc")
TabMisc:CreateToggle({
	Name = "Auto Potions",
	CurrentValue = false,
	Flag = "AutoPotions",
	Callback = onToggle(Potions),
})
TabMisc:CreateToggle({
	Name = "Auto Class Roll",
	CurrentValue = false,
	Flag = "AutoClass",
	Callback = onToggle(ClassRoll),
})
TabMisc:CreateToggle({
	Name = "Anti-AFK",
	CurrentValue = true,
	Flag = "AntiAFK",
	Callback = onToggle(AntiAfk),
})
local StatsPara = TabMisc:CreateParagraph({ Title = "Live Stats", Content = "waiting..." })
TabMisc:CreateButton({
	Name = "Unload Script",
	Callback = function() task.defer(unloadAll) end,
})

-- обновление параграфов (GUI-only, без ремоутов)
local lastTexts = {}
local function setPara(obj, key, title, text)
	if lastTexts[key] == text then return end
	lastTexts[key] = text
	pcall(function() obj:Set({ Title = title, Content = text }) end)
end
updateUI = function()
	local p = Mirror.profile
	local stats
	if p then
		stats = table.concat({
			"Cash: " .. fmt(p.Cash) .. " (max " .. fmt(State.MaxCashSeen) .. ")",
			"Power: " .. fmt(p.Power) .. " | Rebirth: " .. tostring(RebirthCount()) .. " | World: " .. tostring(maxOwnedWorld()),
			"Power/min: " .. (Mirror.powerRate and fmt(Mirror.powerRate * 60) or "-") .. " | Cash/min: " .. (Mirror.cashRate and fmt(Mirror.cashRate * 60) or "-"),
			"Push age: " .. (Mirror.at > 0 and string.format("%.1fs", os.clock() - Mirror.at) or "-"),
			"Potions: " .. Potions.status .. " | Class: " .. ClassRoll.status,
		}, "\n")
	else
		stats = "waiting for profile push (HandlerService.RE.Fruits)..."
	end
	setPara(StatsPara, "stats", "Live Stats", stats)
	setPara(FarmPara, "farm", "Status", "Throw: " .. ThrowFarm.status .. "\nTrain: " .. TrainFarm.status)
	setPara(EggPara, "eggs", "Status", "Hatch: " .. HatchFarm.status .. "\nEvent Egg: " .. EventEgg.status)
	setPara(EcoPara, "eco", "Status", "Buy: " .. AutoBuy.status .. "\nRebirth: " .. AutoRebirth.status)
	setPara(RewPara, "rew", "Status", "Pass: " .. EventPass.status .. "\nClaims: " .. Claims.status
		.. "\nSpin: " .. DailySpin.status .. "\nCodes: " .. Codes.status)
end

--=========================== FLOATING QUICK BAR (THR/TRN, общий стейт с Rayfield) ===========================
local function buildQuickBar()
	elevate()
	local ok, sgui = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
	if not ok or not sgui then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SigmatikLWQuickBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999999999

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(152, 34)
	holder.Position = UDim2.fromOffset(24, 280)
	holder.Parent = gui

	local ORANGE = Color3.fromRGB(249, 115, 22)
	local GRAY = Color3.fromRGB(52, 52, 60)
	local WHITE = Color3.fromRGB(255, 255, 255)
	local DIM = Color3.fromRGB(200, 200, 210)
	local function mkBtn(text, x, w)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(w, 34)
		b.Position = UDim2.fromOffset(x, 0)
		b.BackgroundColor3 = GRAY
		b.TextColor3 = DIM
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.Text = text
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = b
		b.Parent = holder
		return b
	end

	local dragBtn = mkBtn("LW", 0, 40)
	dragBtn.BackgroundColor3 = ORANGE
	dragBtn.TextColor3 = WHITE
	local thrBtn = mkBtn("THR", 46, 50)
	local trnBtn = mkBtn("TRN", 102, 50)

	-- клики идут через Rayfield-тумблеры => один код-путь, меню синхронно
	thrBtn.MouseButton1Click:Connect(function()
		pcall(function() ThrowToggle:Set(not (RUNNING.throw == true)) end)
	end)
	trnBtn.MouseButton1Click:Connect(function()
		pcall(function() TrainToggle:Set(not (RUNNING.train == true)) end)
	end)

	-- drag за LW
	local dragging, dragStart, startPos = false, nil, nil
	dragBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, holder.Position
		end
	end)
	dragBtn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	table.insert(State.Connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and dragStart and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			holder.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
		end
	end))

	-- цвет по общему стейту RUNNING (ловит и переключения из меню)
	table.insert(State.Connections, task.spawn(function()
		while State.Alive and gui.Parent do
			thrBtn.BackgroundColor3 = RUNNING.throw and ORANGE or GRAY
			thrBtn.TextColor3 = RUNNING.throw and WHITE or DIM
			trnBtn.BackgroundColor3 = RUNNING.train and ORANGE or GRAY
			trnBtn.TextColor3 = RUNNING.train and WHITE or DIM
			task.wait(0.4)
		end
	end))

	gui.Parent = sgui
	QuickBarGui = gui
end
buildQuickBar()

--=========================== BOOT (включил-и-забыл) ===========================
Ticker:Start()
AntiAfk:Start() -- on по умолчанию; сохранённый конфиг может выключить через callback
-- Rayfield сам восстановит тумблеры/слайдеры из конфига и дёрнет их callbacks (авто-старт фарма)
pcall(function() Rayfield:LoadConfiguration() end)
