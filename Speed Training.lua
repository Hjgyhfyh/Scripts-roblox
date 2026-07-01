local SharedEnv = (getgenv and getgenv()) or _G
if SharedEnv.SpeedTrainingCleanup then pcall(SharedEnv.SpeedTrainingCleanup) end
if _G.__SpeedTrainingUnload then pcall(_G.__SpeedTrainingUnload) end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

pcall(function()
	local set = setthreadidentity or setidentity or set_thread_identity or (syn and syn.set_thread_identity)
	if set then set(8) end
end)

local Rayfield
do
	local ok, lib = pcall(function() return loadstring(game:HttpGet("https://sirius.menu/rayfield"))() end)
	if not ok or type(lib) ~= "table" then
		warn("[Speed Training] failed to load Rayfield UI")
		return
	end
	Rayfield = lib
end

local Paper
do
	local ok, mod = pcall(function() return require(ReplicatedStorage:WaitForChild("Paper", 15)) end)
	if not ok or type(mod) ~= "table" then
		warn("[Speed Training] Paper framework not found")
		return
	end
	Paper = mod
end
local Net = Paper.Network
local Tables = ReplicatedStorage:WaitForChild("Tables", 15)
local SharedMods = ReplicatedStorage:WaitForChild("Modules", 15):WaitForChild("Shared", 15)
local ValuesFolder = ReplicatedStorage:FindFirstChild("Values")

pcall(function()
	if Paper.Stats and Paper.Stats.LoadedAsync then
		Paper.Stats.LoadedAsync(nil, 15)
	end
end)

local moduleCache = {}
local function req(inst)
	if not inst then return nil end
	if moduleCache[inst] ~= nil then return moduleCache[inst] or nil end
	local ok, m = pcall(require, inst)
	moduleCache[inst] = ok and m or false
	return moduleCache[inst] or nil
end

local function GV(name)
	local ok, v = pcall(Paper.Stats.GetValue, name)
	if ok then return v end
	return nil
end
local function inRace()
	local ok, v = pcall(Paper.State.IsInState, LocalPlayer, "Race")
	return ok and v == true
end
local function getHRP()
	local c = LocalPlayer.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function fmt(n)
	n = tonumber(n) or 0
	local neg = n < 0
	n = math.abs(n)
	if n < 1000 then
		local s = (n == math.floor(n)) and tostring(math.floor(n)) or string.format("%.1f", n)
		return (neg and "-" or "") .. s
	end
	local i = math.clamp(math.floor(math.log(n, 1000)), 1, #SUFFIX - 1)
	return (neg and "-" or "") .. string.format("%.2f%s", n / (1000 ^ i), SUFFIX[i + 1])
end

--============================ RATE LIMITER (<=400/s total) ============================
local RATE = { cap = 200, tokens = 200, last = os.clock() }
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
	while not rateConsume() do
		task.wait(0.01)
		t = t + 0.01
		if t > 4 then break end
	end
end
local function fire(...)
	waitToken()
	pcall(Net.FireServer, ...)
end
local function invoke(...)
	waitToken()
	local ok, a, b = pcall(Net.InvokeServer, ...)
	if ok then return a, b end
	return false, nil
end

--============================ CONFIG PERSISTENCE ============================
local CONFIG_FILE = "SpeedTraining_config.json"
local hasFS = (typeof(writefile) == "function") and (typeof(readfile) == "function")
local Config = { modules = {}, controls = {} }
do
	local exists = hasFS and ((typeof(isfile) ~= "function") or isfile(CONFIG_FILE))
	if hasFS and exists then
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
		if ok and type(data) == "table" then
			Config.modules = data.modules or {}
			Config.controls = data.controls or {}
		end
	end
end
local function saveConfig()
	if not hasFS then return end
	pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end)
end
local function cfgCtl(key, default)
	local v = Config.controls[key]
	if v == nil then return default end
	return v
end
RATE.cap = math.clamp(cfgCtl("rate_limit", 200), 10, 400)
RATE.tokens = RATE.cap

--============================ TASK BAG ============================
local RUNNING = {}
local function bag()
	local b = { conns = {}, alive = true }
	function b:track(c)
		table.insert(self.conns, c)
		return c
	end
	function b:every(interval, fn)
		local th = task.spawn(function()
			while self.alive do
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

--============================ RACE FARM ============================
local RaceFarm = {
	B = nil,
	boost = cfgCtl("race_boost", false),
	fallback = cfgCtl("race_fallback", true),
	vel = 0,
	lastZ = nil,
	hold = 0,
	nerf = 6,
	toggledNative = false,
}
local function raceWorldData()
	local data = req(Tables:FindFirstChild("Race"))
	local world = GV("CurrentWorld") or 1
	local r = data and data[world]
	if type(r) ~= "table" then return nil end
	return { nerf = r.DistanceNerf or 6 }
end
function RaceFarm:bind()
	if self.renderConn then return end
	self.renderConn = RunService.RenderStepped:Connect(function()
		if not (RUNNING.race and self.boost) then return end
		if not inRace() then
			self.inR = false
			return
		end
		local h = getHRP()
		if not h then return end
		if not self.inR then
			self.inR = true
			self.vel = 0
			self.lastZ = nil
			self.hold = 20
			local wd = raceWorldData()
			self.nerf = (wd and wd.nerf) or self.nerf or 6
		end
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local ws = (hum and hum.WalkSpeed) or 16
		local floorVel = ws * 3 / (self.nerf or 6)
		local z = h.Position.Z
		if self.hold > 0 then
			self.hold = self.hold - 1
		elseif self.lastZ and z < self.lastZ - 40 then
			if self.fallback then
				self.vel = math.max(floorVel, self.vel * 0.5)
				self.hold = 75
			end
		else
			self.vel = self.vel + math.max(4, self.vel * 0.01)
		end
		self.lastZ = z
		if self.vel < floorVel then self.vel = floorVel end
		if self.vel > 50000 then self.vel = 50000 end
		local av = h.AssemblyLinearVelocity
		h.AssemblyLinearVelocity = Vector3.new(av.X, av.Y, self.vel)
	end)
end
function RaceFarm:unbind()
	if self.renderConn then
		pcall(function() self.renderConn:Disconnect() end)
		self.renderConn = nil
	end
end
function RaceFarm:Start()
	if RUNNING.race then return end
	RUNNING.race = true
	self.inR = false
	self:bind()
	if GV("AutoRace") == false then
		fire("Toggle Setting", "AutoRace")
		self.toggledNative = true
	end
end
function RaceFarm:Stop()
	RUNNING.race = false
	self:unbind()
	if self.B then self.B:kill() self.B = nil end
	if self.toggledNative and GV("AutoRace") == true then
		fire("Toggle Setting", "AutoRace")
	end
	self.toggledNative = false
end

--============================ TREADMILL ============================
local Treadmill = { mounted = nil, B = nil }
local function treadmillWorld(i)
	local folder = Workspace:FindFirstChild("Treadmills")
	if folder then
		local node = folder:FindFirstChild(tostring(i))
		if node then
			local ok, w = pcall(function() return node:GetAttribute("World") end)
			if ok and type(w) == "number" then return w end
		end
	end
	return 1
end
function Treadmill:best()
	local data = req(Tables:FindFirstChild("Treadmills"))
	if type(data) ~= "table" then return 1 end
	local sp = GV("Speed") or 0
	local rb = GV("Rebirths") or 0
	local wu = GV("WorldsUnlocked") or 1
	for i = #data, 1, -1 do
		local t = data[i]
		local gate = (sp >= (t.Requirement or 0)) or (rb >= (t.Rebirths or 0))
		if gate and treadmillWorld(i) <= wu then
			return i
		end
	end
	return 1
end
function Treadmill:dismount()
	if self.mounted ~= nil then
		fire("Dismount Treadmill")
		self.mounted = nil
	end
end
function Treadmill:Start()
	if RUNNING.train then return end
	RUNNING.train = true
	if GV("AutoTrain") == true then
		fire("Toggle Setting", "AutoTrain")
	end
	self.B = bag()
	self.B:every(0.6, function()
		if inRace() then
			self:dismount()
			return
		end
		local b = self:best()
		if b >= 1 and LocalPlayer:GetAttribute("Treadmill") ~= b then
			fire("Use Treadmill", b)
			self.mounted = b
		end
	end)
end
function Treadmill:Stop()
	RUNNING.train = false
	if self.B then self.B:kill() self.B = nil end
	self:dismount()
end

--============================ REBIRTH ============================
local Rebirth = { B = nil, minAmount = cfgCtl("rebirth_min", 1) }
function Rebirth:Start()
	if RUNNING.rebirth then return end
	RUNNING.rebirth = true
	self.B = bag()
	self.B:every(3, function()
		if inRace() then return end
		local mod = req(SharedMods:FindFirstChild("Rebirths"))
		if type(mod) ~= "table" then return end
		local rb = GV("Rebirths") or 0
		local sp = GV("Speed") or 0
		local amt = 0
		local ok = pcall(function() amt = mod.GetMaxAmount(nil, rb, sp) or 0 end)
		if not ok or type(amt) ~= "number" then
			local per = 500 * (rb + 1)
			amt = per > 0 and math.floor(sp / per) or 0
		end
		if amt >= math.max(1, self.minAmount) then
			invoke("Rebirth", amt)
		end
	end)
end
function Rebirth:Stop()
	RUNNING.rebirth = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ WORLDS ============================
local WorldAdvance = { B = nil }
function WorldAdvance:Start()
	if RUNNING.world then return end
	RUNNING.world = true
	self.B = bag()
	self.B:every(5, function()
		if inRace() then return end
		local data = req(Tables:FindFirstChild("Worlds"))
		if type(data) ~= "table" then return end
		local rb = GV("Rebirths") or 0
		local cur = GV("CurrentWorld") or 1
		local best = 1
		for i, w in ipairs(data) do
			if rb >= (w.Req or 0) then best = i end
		end
		if best > cur then
			invoke("Set Current World", best)
		end
	end)
end
function WorldAdvance:Stop()
	RUNNING.world = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ GEAR (Shoes/Trails/Partners) ============================
local function buildGearList(tblName, powerField)
	local data = req(Tables:FindFirstChild(tblName))
	local list = {}
	if type(data) == "table" then
		for name, item in pairs(data) do
			if type(item) == "table" and not item.Exclusive and not item.ProductId and type(item.Cost) == "number" then
				table.insert(list, { name = name, cost = item.Cost, pow = item[powerField] or 0 })
			end
		end
		table.sort(list, function(a, b) return a.cost < b.cost end)
	end
	return list
end
local function cheapestUnbought(tblName, powerField, boughtStat)
	local list = buildGearList(tblName, powerField)
	local bought = GV(boughtStat) or {}
	for _, e in ipairs(list) do
		if not bought[e.name] then return e.cost end
	end
	return nil
end
local function autoGear(tblName, powerField, boughtStat, equipStat, buyRoute, equipRoute)
	local list = buildGearList(tblName, powerField)
	if #list == 0 then return end
	local bought = GV(boughtStat) or {}
	local wins = GV("Wins") or 0
	for _, e in ipairs(list) do
		if not bought[e.name] then
			if wins >= e.cost then
				local ok = invoke(buyRoute, e.name)
				if ok then
					bought[e.name] = true
					wins = wins - e.cost
				else
					break
				end
			else
				break
			end
		end
	end
	local best
	for i = #list, 1, -1 do
		if bought[list[i].name] then best = list[i].name break end
	end
	if best and GV(equipStat) ~= best then
		invoke(equipRoute, best)
	end
end
local function makeGearFeature(flag, tblName, powerField, boughtStat, equipStat, buyRoute, equipRoute)
	local F = { B = nil }
	function F:Start()
		if RUNNING[flag] then return end
		RUNNING[flag] = true
		self.B = bag()
		self.B:every(2, function()
			autoGear(tblName, powerField, boughtStat, equipStat, buyRoute, equipRoute)
		end)
	end
	function F:Stop()
		RUNNING[flag] = false
		if self.B then self.B:kill() self.B = nil end
	end
	return F
end
local Shoes = makeGearFeature("shoes", "Shoes", "Acceleration", "BoughtShoes", "EquippedShoe", "Buy Shoe", "Equip Shoe")
local Trails = makeGearFeature("trails", "Trails", "RaceSpeed", "BoughtTrails", "EquippedTrail", "Buy Trail", "Equip Trail")
local Partners = makeGearFeature("partners", "Partners", "TrainSpeed", "BoughtPartners", "EquippedPartner", "Buy Partner", "Equip Partner")

--============================ EGGS ============================
local Hatch = { B = nil }
function Hatch:gearReserve()
	local costs = {}
	if RUNNING.shoes then local c = cheapestUnbought("Shoes", "Acceleration", "BoughtShoes") if c then table.insert(costs, c) end end
	if RUNNING.trails then local c = cheapestUnbought("Trails", "RaceSpeed", "BoughtTrails") if c then table.insert(costs, c) end end
	if RUNNING.partners then local c = cheapestUnbought("Partners", "TrainSpeed", "BoughtPartners") if c then table.insert(costs, c) end end
	if #costs == 0 then return 0 end
	local m = costs[1]
	for _, c in ipairs(costs) do if c < m then m = c end end
	return m
end
function Hatch:Start()
	if RUNNING.hatch then return end
	RUNNING.hatch = true
	self.B = bag()
	self.B:every(2.5, function()
		local data = req(Tables:FindFirstChild("Eggs"))
		if type(data) ~= "table" then return end
		local wu = GV("WorldsUnlocked") or 1
		local wins = GV("Wins") or 0
		local reserveGear = self:gearReserve()
		local budget = math.max(0, wins - reserveGear)
		local best
		for name, egg in pairs(data) do
			if type(egg) == "table" and type(egg.Cost) == "number" and egg.WorldNumber then
				if egg.WorldNumber <= wu and egg.Cost <= budget then
					if not best or egg.Cost > best.cost then
						best = { name = name, cost = egg.Cost }
					end
				end
			end
		end
		if best then
			local ok = invoke("Hatch Egg", best.name, "Max")
			if not ok then
				local maxPer = GV("MaxEggOpen") or 3
				local n = math.min(math.floor(budget / best.cost), maxPer)
				if n >= 1 then invoke("Hatch Egg", best.name, n) end
			end
		end
	end)
end
function Hatch:Stop()
	RUNNING.hatch = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ UPGRADES ============================
local UPGRADE_PRIORITY = {
	"More Speed", "More Wins", "Gems Chance", "More Gems", "Top Speed",
	"Egg Luck", "Golden Chance", "Rainbow Chance", "Critical Gems", "More Rebirth Skips",
}
local Upgrade = { B = nil }
function Upgrade:Start()
	if RUNNING.upgrade then return end
	RUNNING.upgrade = true
	self.B = bag()
	self.B:every(2, function()
		local data = req(Tables:FindFirstChild("Upgrades"))
		if type(data) ~= "table" then return end
		local guard = 0
		local changed = true
		while changed and guard < 80 do
			changed = false
			guard = guard + 1
			for _, name in ipairs(UPGRADE_PRIORITY) do
				local def = data[name]
				if def and type(def.UpgradeCosts) == "function" then
					local level = GV(def.StatName) or 0
					if level < (def.Max or math.huge) then
						local cost
						pcall(function() cost = def.UpgradeCosts(level) end)
						local gems = GV("Gems") or 0
						if type(cost) == "number" and gems >= cost then
							if invoke("Upgrade", name) then
								changed = true
								break
							end
						end
					end
				end
			end
		end
	end)
end
function Upgrade:Stop()
	RUNNING.upgrade = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ PETS ============================
local EquipPets = { B = nil }
function EquipPets:Start()
	if RUNNING.equip then return end
	RUNNING.equip = true
	self.B = bag()
	self.B:every(4, function()
		invoke("Pet", { Action = "EquipBest", Sort = "Power" })
	end)
end
function EquipPets:Stop()
	RUNNING.equip = false
	if self.B then self.B:kill() self.B = nil end
end

local CraftPets = { B = nil }
function CraftPets:Start()
	if RUNNING.craft then return end
	RUNNING.craft = true
	self.B = bag()
	self.B:every(4, function()
		local guard = 0
		local changed = true
		while changed and guard < 60 do
			changed = false
			guard = guard + 1
			local pets = GV("Pets") or {}
			local buckets = {}
			for id, e in pairs(pets) do
				if type(e) == "table" and e.Locked ~= true and (e.Size or 1) < 4 then
					local k = tostring(e.PetName) .. "|" .. tostring(e.Tier) .. "|" .. tostring(e.Size)
					buckets[k] = buckets[k] or {}
					table.insert(buckets[k], id)
				end
			end
			for _, ids in pairs(buckets) do
				if #ids >= 3 then
					if invoke("Pet", { Action = "CraftSize", Pet = ids[1] }) then
						changed = true
					end
					break
				end
			end
		end
	end)
end
function CraftPets:Stop()
	RUNNING.craft = false
	if self.B then self.B:kill() self.B = nil end
end

local DeletePets = { B = nil, keep = cfgCtl("pets_keep", 30) }
local SIZE_MULT = { 1, 1.25, 1.5, 2 }
function DeletePets:power(e)
	local base = 1
	local lib = req(SharedMods:FindFirstChild("PetLib"))
	if lib and type(lib.GetPetPower) == "function" then
		local ok, b = pcall(lib.GetPetPower, e.PetName)
		if ok and type(b) == "number" and b > 0 then base = b end
	end
	return base * (2 ^ ((e.Tier or 1) - 1)) * (SIZE_MULT[e.Size or 1] or 1)
end
function DeletePets:Start()
	if RUNNING.delete then return end
	RUNNING.delete = true
	self.B = bag()
	self.B:every(6, function()
		local pets = GV("Pets") or {}
		local keep = math.max(1, self.keep)
		local unlocked = {}
		local buckets = {}
		for id, e in pairs(pets) do
			if type(e) == "table" and e.Locked ~= true then
				table.insert(unlocked, { id = id, e = e })
				local k = tostring(e.PetName) .. "|" .. tostring(e.Tier) .. "|" .. tostring(e.Size)
				buckets[k] = buckets[k] or {}
				table.insert(buckets[k], id)
			end
		end
		local deleteSet, toDelete = {}, {}
		local function mark(id)
			if not deleteSet[id] then
				deleteSet[id] = true
				table.insert(toDelete, id)
			end
		end
		for _, ids in pairs(buckets) do
			local e = pets[ids[1]]
			if e and (e.Size or 1) == 4 and #ids >= 2 then
				for i = 2, #ids do mark(ids[i]) end
			end
		end
		local remaining = {}
		for _, rec in ipairs(unlocked) do
			if not deleteSet[rec.id] then table.insert(remaining, rec) end
		end
		if #remaining > keep then
			table.sort(remaining, function(a, b) return self:power(a.e) > self:power(b.e) end)
			for i = keep + 1, #remaining do
				mark(remaining[i].id)
				if #toDelete >= 60 then break end
			end
		end
		if #toDelete > 0 then
			invoke("Pet", { Action = "Delete", Pets = toDelete })
		end
	end)
end
function DeletePets:Stop()
	RUNNING.delete = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ ACHIEVEMENTS ============================
local Achievements = { B = nil }
function Achievements:Start()
	if RUNNING.ach then return end
	RUNNING.ach = true
	self.B = bag()
	self.B:every(8, function()
		local data = req(Tables:FindFirstChild("Achievements"))
		if type(data) ~= "table" then return end
		for key, cat in pairs(data) do
			if type(cat) == "table" and cat.Rewards and cat.Stat and cat.AchievementStat then
				local claimed = GV(cat.AchievementStat) or 0
				if type(claimed) ~= "number" then claimed = 0 end
				local statVal = GV(cat.Stat) or 0
				for idx = claimed + 1, #cat.Rewards do
					local reward = cat.Rewards[idx]
					if reward and statVal >= (reward.Requirement or math.huge) then
						if not invoke("Claim Achievement", key, idx) then break end
					else
						break
					end
				end
			end
		end
	end)
end
function Achievements:Stop()
	RUNNING.ach = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ REWARDS (free / daily / group) ============================
local Rewards = { B = nil }
function Rewards:Start()
	if RUNNING.rewards then return end
	RUNNING.rewards = true
	self.B = bag()
	self.B:every(10, function()
		if (GV("FreeRewardTimer") or 0) >= 900 then
			invoke("Claim Free Reward")
		end
		local last = tonumber(Config.controls._lastDaily) or 0
		if os.time() - last >= 43200 then
			local ok = invoke("Claim Chest", "DailyChest")
			if ok then
				Config.controls._lastDaily = os.time()
				saveConfig()
			end
		end
		if GV("ClaimedGroupReward") ~= true then
			fire("Claim Group", "dont exploit me flis!")
		end
	end)
end
function Rewards:Stop()
	RUNNING.rewards = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ POTIONS ============================
local Potions = { B = nil }
local function itemCount(name)
	for _, s in ipairs({ "Items", "Inventory", "Potions" }) do
		local v = GV(s)
		if type(v) == "table" then
			local c = v[name]
			if type(c) == "number" then return c end
			if type(c) == "table" and type(c.Count) == "number" then return c.Count end
		end
	end
	local d = GV(name)
	if type(d) == "number" then return d end
	return nil
end
function Potions:Start()
	if RUNNING.potions then return end
	RUNNING.potions = true
	self.B = bag()
	self.B:every(12, function()
		local last = tonumber(Config.controls._lastPotion) or 0
		if os.time() - last < 290 then return end
		local count = itemCount("Speed Potion")
		local reserve = math.max(0, math.floor(cfgCtl("potion_reserve", 0)))
		if count ~= nil and count - reserve < 1 then return end
		local ok = invoke("Use Item", "Speed Potion", 1)
		if ok then
			Config.controls._lastPotion = os.time()
			saveConfig()
		end
	end)
end
function Potions:Stop()
	RUNNING.potions = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ REDEEM CODES ============================
local CODES = { "release", "update", "free", "likes", "speed", "training", "shutdown", "sorry" }
local Redeem = { B = nil }
function Redeem:Start()
	if RUNNING.redeem then return end
	RUNNING.redeem = true
	Config.controls.redeemed = Config.controls.redeemed or {}
	self.B = bag()
	task.spawn(function()
		for _, code in ipairs(CODES) do
			if not self.B or not self.B.alive then break end
			if not Config.controls.redeemed[code] then
				local ok = invoke("Redeem Code", code)
				if ok then
					Config.controls.redeemed[code] = true
					saveConfig()
				end
			end
			task.wait(1)
		end
	end)
end
function Redeem:Stop()
	RUNNING.redeem = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ LIVE INFO ============================
local INFO_FIELDS = {
	{ name = "Wins", get = function() return fmt(GV("Wins")) end },
	{ name = "Gems", get = function() return fmt(GV("Gems")) end },
	{ name = "Speed", get = function() return fmt(GV("Speed")) end },
	{ name = "Rebirths", get = function() return fmt(GV("Rebirths")) end },
	{ name = "World", get = function() return tostring(GV("CurrentWorld") or 1) .. " / " .. tostring(GV("WorldsUnlocked") or 1) end },
}
local InfoLabels = {}
local Info = { B = nil }
function Info:Start()
	if RUNNING.info then return end
	RUNNING.info = true
	self.B = bag()
	self.B:every(1, function()
		for _, f in ipairs(INFO_FIELDS) do
			local lbl = InfoLabels[f.name]
			if lbl then
				pcall(function() lbl:Set(f.name .. ": " .. f.get()) end)
			end
		end
	end)
end
function Info:Stop()
	RUNNING.info = false
	if self.B then self.B:kill() self.B = nil end
end

--============================ ANTI-AFK (always on) ============================
local antiAfk = {}
pcall(function()
	table.insert(antiAfk, LocalPlayer.Idled:Connect(function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end))
end)
do
	local lastPing = os.clock()
	table.insert(antiAfk, RunService.Heartbeat:Connect(function()
		if os.clock() - lastPing >= 90 then
			lastPing = os.clock()
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new(0, 0), Workspace.CurrentCamera and Workspace.CurrentCamera.CFrame)
			end)
		end
	end))
end

--============================ UNLOAD ============================
local unloaded = false
local FEATURES = {
	RaceFarm, Treadmill, Rebirth, WorldAdvance,
	Shoes, Trails, Partners, Hatch, Upgrade,
	EquipPets, CraftPets, DeletePets, Achievements, Rewards, Potions, Redeem, Info,
}
local function unloadAll()
	if unloaded then return end
	unloaded = true
	for _, f in ipairs(FEATURES) do pcall(function() f:Stop() end) end
	for _, c in ipairs(antiAfk) do pcall(function() c:Disconnect() end) end
	pcall(function() Rayfield:Destroy() end)
	_G.__SpeedTrainingUnload = nil
end
_G.__SpeedTrainingUnload = unloadAll
SharedEnv.SpeedTrainingCleanup = unloadAll

--============================ GUI ============================
local autostart = {}
local function moduleToggle(tab, name, feature)
	local enabled = Config.modules[name] == true
	if enabled then table.insert(autostart, feature) end
	tab:CreateToggle({
		Name = name,
		CurrentValue = enabled,
		Callback = function(on)
			Config.modules[name] = on and true or false
			saveConfig()
			if on then pcall(function() feature:Start() end) else pcall(function() feature:Stop() end) end
		end,
	})
end
local function ctlSlider(tab, key, name, min, max, inc, default, apply)
	tab:CreateSlider({
		Name = name,
		Range = { min, max },
		Increment = inc,
		CurrentValue = cfgCtl(key, default),
		Callback = function(v)
			Config.controls[key] = v
			saveConfig()
			pcall(apply, v)
		end,
	})
end
local function ctlToggle(tab, key, name, default, apply)
	tab:CreateToggle({
		Name = name,
		CurrentValue = cfgCtl(key, default),
		Callback = function(v)
			Config.controls[key] = v
			saveConfig()
			pcall(apply, v)
		end,
	})
end

pcall(function()
	local set = setthreadidentity or setidentity or set_thread_identity or (syn and syn.set_thread_identity)
	if set then set(8) end
end)

local Window = Rayfield:CreateWindow({
	Name = "tg: @sigmatik323",
	LoadingTitle = "tg: @sigmatik323",
	LoadingSubtitle = "by sigmatik323",
	ConfigurationSaving = { Enabled = false },
	Discord = { Enabled = false },
	KeySystem = false,
})

local farmTab = Window:CreateTab("⚡ Farm")
farmTab:CreateSection("Auto Race")
moduleToggle(farmTab, "Auto Race", RaceFarm)
farmTab:CreateParagraph({ Title = "Distance Boost", Content = "Fully automatic — finds the fastest race speed the server allows and self-adjusts as you go. Just turn it on." })
ctlToggle(farmTab, "race_boost", "Distance Boost", false, function(v)
	RaceFarm.boost = v
	RaceFarm.inR = false
end)
ctlToggle(farmTab, "race_fallback", "Auto Fallback", true, function(v) RaceFarm.fallback = v end)
farmTab:CreateSection("Training & Progression")
moduleToggle(farmTab, "Auto Train", Treadmill)
moduleToggle(farmTab, "Auto Rebirth", Rebirth)
ctlSlider(farmTab, "rebirth_min", "Min Rebirth Amount", 1, 50, 1, 1, function(v) Rebirth.minAmount = v end)
moduleToggle(farmTab, "Auto Advance World", WorldAdvance)

local econTab = Window:CreateTab("💰 Economy")
econTab:CreateSection("Gear (spends Wins)")
moduleToggle(econTab, "Auto Buy Shoes", Shoes)
moduleToggle(econTab, "Auto Buy Trails", Trails)
moduleToggle(econTab, "Auto Buy Partners", Partners)
econTab:CreateSection("Eggs & Upgrades")
moduleToggle(econTab, "Auto Hatch Eggs", Hatch)
moduleToggle(econTab, "Auto Upgrade", Upgrade)

local petTab = Window:CreateTab("🐾 Pets")
moduleToggle(petTab, "Auto Equip Best", EquipPets)
moduleToggle(petTab, "Auto Craft Sizes", CraftPets)
moduleToggle(petTab, "Auto Delete Weak", DeletePets)
ctlSlider(petTab, "pets_keep", "Keep Top N", 5, 200, 5, 30, function(v) DeletePets.keep = v end)

local rewardTab = Window:CreateTab("🎁 Rewards")
moduleToggle(rewardTab, "Auto Achievements", Achievements)
moduleToggle(rewardTab, "Auto Rewards", Rewards)
moduleToggle(rewardTab, "Auto Speed Potion", Potions)
ctlSlider(rewardTab, "potion_reserve", "Keep Reserve", 0, 25, 1, 0, function() end)
moduleToggle(rewardTab, "Redeem Codes", Redeem)

local infoTab = Window:CreateTab("📊 Info")
infoTab:CreateSection("Live Stats")
for _, f in ipairs(INFO_FIELDS) do
	InfoLabels[f.name] = infoTab:CreateLabel(f.name .. ": -")
end

local setTab = Window:CreateTab("⚙️ Settings")
setTab:CreateSection("Performance")
ctlSlider(setTab, "rate_limit", "Remote Rate (calls/sec)", 10, 400, 10, 200, function(v) RATE.cap = math.clamp(v, 10, 400) end)
setTab:CreateParagraph({ Title = "Remote budget", Content = "Total remote calls per second across every feature. Hard-capped at 400." })
setTab:CreateSection("Script")
setTab:CreateButton({ Name = "Unload Script", Callback = function() task.defer(unloadAll) end })
setTab:CreateParagraph({ Title = "Speed Training", Content = "Auto farm by sigmatik323. Enable Auto Race + Distance Boost, Auto Train, Auto Rebirth and the economy modules, then leave it overnight. Toggle this menu with the keybind." })

for _, feature in ipairs(autostart) do
	pcall(function() feature:Start() end)
end
Info:Start()
