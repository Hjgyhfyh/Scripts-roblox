local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInput = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local lp = Players.LocalPlayer

if _G.__MRTS_AI_UNLOAD then pcall(_G.__MRTS_AI_UNLOAD) end

local CONFIG = {
	antiAfkHz = 2.5,
	maxRemotePerSec = 220,
	targetBuilders = 4,
	perTypeCap = 24,
	houseSlack = 6,
	hutSlack = 6,
	expandSpareCash = 105,
	barracksMinCash = 55,
	siegeShopMinCash = 150,
	windmillUpgradeMinCash = 70,
	castleUpgradeMinCash = 260,
	fishingBoats = 3,
	marketCap = 3,
	armyOrder = { "Longbower", "Knight", "Crossbower", "Wizard" },
	army = { Longbower = 10, Knight = 18, Crossbower = 4, Wizard = 2 },
	siegeOrder = { "Trebuchet", "Catapult", "Ballista" },
	siege = { Trebuchet = 2, Catapult = 2, Ballista = 2 },
	towerCap = 3,
	watchtowerCap = 1,
	trapCap = 4,
	pushArmy = 10,
	pushSiege = 1,
	pushAnywayArmy = 16,
	scan = 1.2,
}

local state = {
	running = true,
	auto = { economy = true, market = true, tech = true, army = true, siege = true, upgrades = true, defense = true, rush = true, expand = false },
	conns = {}, threads = {}, gui = nil,
	rateWindow = 0, rateCount = 0,
	phase = "ECONOMY", income = 0, lastCash = 0, lastCashT = 0,
	hCache = {}, recruits = {}, invest = {},
}
_G.__MRTS = state
_G.__MRTSC = CONFIG

local function track(c) table.insert(state.conns, c) return c end

local function canFire()
	local now = os.clock()
	if now - state.rateWindow >= 1 then state.rateWindow = now; state.rateCount = 0 end
	if state.rateCount >= CONFIG.maxRemotePerSec then return false end
	state.rateCount = state.rateCount + 1
	return true
end

local function fire(remote, ...)
	if not canFire() then return end
	local a = table.pack(...)
	pcall(function() remote:FireServer(table.unpack(a, 1, a.n)) end)
end

local function myFolder()
	local g = workspace:FindFirstChild("Game")
	local pf = g and g:FindFirstChild("PlayerFolder")
	return pf and pf:FindFirstChild(lp.Name)
end

local function getCash()
	local ok, v = pcall(function() return RS.GetInfoCash:Invoke() end)
	return ok and tonumber(v) or 0
end

local function reclaim()
	pcall(function() workspace.Game.BotsEnabled.Value = false end)
	fire(RS.ChangeIdleState, false)
end

local function hitboxH(name)
	if state.hCache[name] then return state.hCache[name] end
	local h = 2
	local t = RS:FindFirstChild("Buildings") and RS.Buildings:FindFirstChild("Default") and RS.Buildings.Default:FindFirstChild(name)
	if t then
		local pp = t.PrimaryPart or t:FindFirstChild("Hitbox")
		if pp then h = pp.Size.Y end
	end
	state.hCache[name] = h
	return h
end

local function buildCost(name)
	local ok, m = pcall(function() return require(RS.Utilities.ObjectStats) end)
	if ok and m and m[name] and m[name].Cost then return m[name].Cost end
	return 9999
end

local function suppliesFolder()
	local g = workspace:FindFirstChild("Game")
	local m = g and g:FindFirstChild("Map")
	m = m and m:FindFirstChild("Map")
	return m and m:FindFirstChild("Supplies")
end

local rayDown = RaycastParams.new()
rayDown.FilterType = Enum.RaycastFilterType.Exclude
local function groundHit(x, z)
	rayDown.FilterDescendantsInstances = { myFolder(), workspace:FindFirstChild("TargetFilter"), suppliesFolder() }
	return workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -260, 0), rayDown)
end

local function territoryBuildings()
	local mf = myFolder()
	local list = {}
	if not mf then return list end
	for _, b in ipairs(mf.Buildings:GetChildren()) do
		if (b.Name == "Castle" or b.Name == "Outpost") and b:GetAttribute("Built") == true and b:GetAttribute("Destroyed") ~= true and b.PrimaryPart then
			table.insert(list, { pos = b.PrimaryPart.Position, range = b:GetAttribute("Range") or 12 })
		end
	end
	return list
end

local function inTerritory(x, z, margin)
	margin = margin or 1
	for _, t in ipairs(territoryBuildings()) do
		local d = (Vector3.new(x, 0, z) - Vector3.new(t.pos.X, 0, t.pos.Z)).Magnitude
		if d <= t.range - margin then return true end
	end
	return false
end

local function occupiedCellSet()
	local mf = myFolder()
	local set = {}
	if not mf then return set end
	for _, b in ipairs(mf.Buildings:GetChildren()) do
		local raw = b:GetAttribute("OccupiedCells")
		if raw then
			local ok, cells = pcall(function() return HttpService:JSONDecode(raw) end)
			if ok then for _, c in ipairs(cells) do set[c.x .. "," .. c.z] = true end end
		end
	end
	return set
end

local function place(name, x, z, supply, rot)
	local mf = myFolder()
	if not mf then return false end
	reclaim()
	mf.Building.Value = true
	mf.CanPlace.Value = true
	local hit = groundHit(x, z)
	local gy = hit and hit.Position.Y or 0.2
	local pos = Vector3.new(x, gy + hitboxH(name) / 2 + 0.02, z)
	fire(RS.PlacementEvent, name, pos, math.rad(rot or 0), nil, supply)
	return true
end

local function buildingCount(name)
	local mf = myFolder()
	local n = 0
	if mf then for _, b in ipairs(mf.Buildings:GetChildren()) do if b.Name == name then n = n + 1 end end end
	return n
end

local function placeVerify(name, x, z, supply)
	local before = buildingCount(name)
	place(name, x, z, supply)
	local t = 0
	while t < 1.3 do task.wait(0.2); t = t + 0.2; if buildingCount(name) > before then return true end end
	return false
end

local function findOpenSpot(footprint)
	local terr = territoryBuildings()
	if #terr == 0 then return nil end
	local center = terr[1].pos
	local occ = occupiedCellSet()
	for radius = 3, 11 do
		for dx = -radius, radius do
			for dz = -radius, radius do
				if math.abs(dx) == radius or math.abs(dz) == radius then
					local x = math.floor(center.X + dx)
					local z = math.floor(center.Z + dz)
					if inTerritory(x, z, 1) then
						local clear = true
						for cx = -footprint, footprint do
							for cz = -footprint, footprint do
								if occ[(x + cx) .. "," .. (z + cz)] then clear = false break end
							end
							if not clear then break end
						end
						if clear then
							local hit = groundHit(x, z)
							if hit and hit.Instance and hit.Instance.Name == "Ground" and math.abs(hit.Position.Y - center.Y) < 6 then
								return x, z
							end
						end
					end
				end
			end
		end
	end
	return nil
end

local function freeSupplies(reachableOnly)
	local sf = suppliesFolder()
	local out = {}
	if not sf then return out end
	for _, s in ipairs(sf:GetChildren()) do
		if s:GetAttribute("Occupied") == false then
			local p = s:GetPivot().Position
			local reach = false
			for _, t in ipairs(territoryBuildings()) do
				if (Vector3.new(p.X, 0, p.Z) - Vector3.new(t.pos.X, 0, t.pos.Z)).Magnitude <= t.range then reach = true break end
			end
			if (reachableOnly and reach) or (not reachableOnly and not reach) then table.insert(out, s) end
		end
	end
	return out
end

local function countUnit(name)
	local mf = myFolder()
	local n = 0
	if mf then for _, u in ipairs(mf.Units:GetChildren()) do if u.Name == name then n = n + 1 end end end
	return n
end

local function castle()
	local mf = myFolder()
	return mf and mf.Buildings:FindFirstChild("Castle")
end

local function builtBuilding(name)
	local mf = myFolder()
	if not mf then return nil end
	for _, b in ipairs(mf.Buildings:GetChildren()) do
		if b.Name == name and b:GetAttribute("Built") == true and b.PrimaryPart then return b end
	end
	return nil
end

local function enemyCastle()
	local mf = myFolder()
	if not mf then return nil end
	local g = workspace.Game.PlayerFolder
	for _, f in ipairs(g:GetChildren()) do
		if f ~= mf and f:FindFirstChild("TeamValue") and mf:FindFirstChild("TeamValue") and f.TeamValue.Value ~= mf.TeamValue.Value then
			local b = f:FindFirstChild("Buildings")
			local c = b and b:FindFirstChild("Castle")
			if c and c:GetAttribute("Destroyed") ~= true and c.PrimaryPart then return c, f end
		end
	end
	return nil
end

local function enemyNearCastle(rangeStuds)
	local mf, c = myFolder(), castle()
	if not (mf and c and c.PrimaryPart) then return {} end
	local cp = c.PrimaryPart.Position
	local out = {}
	for _, f in ipairs(workspace.Game.PlayerFolder:GetChildren()) do
		if f ~= mf and f:FindFirstChild("TeamValue") and mf:FindFirstChild("TeamValue") and f.TeamValue.Value ~= mf.TeamValue.Value then
			local uf = f:FindFirstChild("Units")
			if uf then
				for _, u in ipairs(uf:GetChildren()) do
					if u.PrimaryPart and (u.PrimaryPart.Position - cp).Magnitude <= rangeStuds then table.insert(out, u) end
				end
			end
		end
	end
	return out
end

local function combatUnits()
	local mf = myFolder()
	local out = {}
	if not mf then return out end
	for _, u in ipairs(mf.Units:GetChildren()) do
		if u.Name ~= "Builder" and u.Name ~= "King" and u.PrimaryPart then table.insert(out, u) end
	end
	return out
end

local function siegeCount()
	local n = 0
	for k in pairs(CONFIG.siege) do n = n + countUnit(k) end
	return n
end

local function unitsNamed(name)
	local mf = myFolder()
	local out = {}
	if not mf then return out end
	for _, u in ipairs(mf.Units:GetChildren()) do
		if u.Name == name and u.PrimaryPart then table.insert(out, u) end
	end
	return out
end

local function unbuiltBuildings()
	local mf = myFolder()
	local out = {}
	if not mf then return out end
	for _, b in ipairs(mf.Buildings:GetChildren()) do
		if b:GetAttribute("Built") ~= true and b:GetAttribute("Destroyed") ~= true and b.PrimaryPart then
			table.insert(out, b)
		end
	end
	return out
end

local function fishingSpots()
	local g = workspace:FindFirstChild("Game")
	local m = g and g:FindFirstChild("Map")
	m = m and m:FindFirstChild("Map")
	local f = m and m:FindFirstChild("Fishing")
	local out = {}
	if f then for _, s in ipairs(f:GetChildren()) do table.insert(out, s) end end
	return out
end

local function threatened()
	return #enemyNearCastle(70) >= 4
end

local function econReady()
	return buildingCount("Market") >= 2 or threatened() or buildingCount("Windmill") >= 2
end

local function staticDefenseUp()
	return (buildingCount("Tower") + buildingCount("Watchtower")) >= 2
end

local function orderUnits(units, targetPos, attack)
	local goals = {}
	for _, u in ipairs(units) do if u.PrimaryPart then table.insert(goals, { u, targetPos }) end end
	if #goals == 0 then return end
	if not canFire() then return end
	pcall(function() RS.SendUnitGoals:InvokeServer(goals, attack and true or false, true) end)
end

local function upgrade(model)
	if not canFire() then return end
	pcall(function() RS.Upgrade:FireServer({ model }) end)
end

local function inflight(name)
	local arr = state.recruits[name]
	if not arr then return 0 end
	local now = os.clock()
	local n = 0
	for i = #arr, 1, -1 do
		if now - arr[i] < 12 then n = n + 1 else table.remove(arr, i) end
	end
	return n
end

local function need(name, target)
	return (countUnit(name) + inflight(name)) < target
end

local function recruit(unitName, building)
	if building and building.PrimaryPart and canFire() then
		pcall(function() RS.Spawn:FireServer(unitName, building.PrimaryPart) end)
		state.recruits[unitName] = state.recruits[unitName] or {}
		table.insert(state.recruits[unitName], os.clock())
	end
end

local function ensureBuilding(name, footprint)
	if builtBuilding(name) then return builtBuilding(name) end
	if buildingCount(name) > 0 then return nil end
	if getCash() < buildCost(name) then return nil end
	local x, z = findOpenSpot(footprint or 2)
	if x then placeVerify(name, x, z) end
	return nil
end

local function spawnLoop(fn, interval)
	local th = task.spawn(function()
		while state.running do pcall(fn); task.wait(interval) end
	end)
	table.insert(state.threads, th)
end

reclaim()
spawnLoop(function() reclaim() end, 1 / CONFIG.antiAfkHz)

spawnLoop(function()
	local c = getCash()
	local now = os.clock()
	if state.lastCashT == 0 then state.lastCashT = now; state.lastCash = c end
	if now - state.lastCashT >= 6 then
		state.income = math.max(0, (c - state.lastCash)) / (now - state.lastCashT) * 60
		state.lastCash = c; state.lastCashT = now
	end
end, 2)

spawnLoop(function()
	if not state.auto.economy then return end
	local c = castle()
	if c and c.PrimaryPart and need("Builder", CONFIG.targetBuilders) and getCash() >= 10 then
		recruit("Builder", c)
	end
	if getCash() >= buildCost("Windmill") then
		for _, s in ipairs(freeSupplies(true)) do
			if getCash() < buildCost("Windmill") then break end
			if buildingCount("Windmill") >= CONFIG.perTypeCap then break end
			local p = s:GetPivot().Position
			placeVerify("Windmill", p.X, p.Z, s)
		end
	end
	local mf = myFolder()
	local st = mf and mf:FindFirstChild("Stats")
	if st then
		local cash = getCash()
		if st.MaxUnits.Value - st.CurrentUnits.Value <= CONFIG.houseSlack and cash >= buildCost("House") and buildingCount("House") < CONFIG.perTypeCap then
			local x, z = findOpenSpot(1)
			if x then placeVerify("House", x, z) end
		end
		if st.MaxBuildings.Value - st.CurrentBuildings.Value <= CONFIG.hutSlack and cash >= buildCost("Builder Hut") and buildingCount("Builder Hut") < CONFIG.perTypeCap then
			local x, z = findOpenSpot(0)
			if x then placeVerify("Builder Hut", x, z) end
		end
	end
end, CONFIG.scan)

spawnLoop(function()
	if not state.auto.expand then return end
	if #unbuiltBuildings() > 0 then return end
	if #freeSupplies(true) > 0 then return end
	local far = freeSupplies(false)
	if #far == 0 then return end
	if getCash() < CONFIG.expandSpareCash or buildingCount("Outpost") >= CONFIG.perTypeCap then return end
	local terr = territoryBuildings()
	if #terr == 0 then return end
	local target, td
	for _, s in ipairs(far) do
		local p = s.PrimaryPart and s.PrimaryPart.Position or s:GetPivot().Position
		for _, t in ipairs(terr) do
			local d = (Vector3.new(t.pos.X, 0, t.pos.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
			if not td or d < td then td = d; target = { p = p, from = t } end
		end
	end
	if target then
		local b = target.from
		local dir = (Vector3.new(target.p.X, 0, target.p.Z) - Vector3.new(b.pos.X, 0, b.pos.Z)).Unit
		local px = math.floor(b.pos.X + dir.X * (b.range - 0.4))
		local pz = math.floor(b.pos.Z + dir.Z * (b.range - 0.4))
		placeVerify("Outpost", px, pz)
	end
end, CONFIG.scan + 1.3)

spawnLoop(function()
	if not state.auto.market then return end
	local mf = myFolder()
	if not mf then return end
	if #unbuiltBuildings() > 0 then return end
	local cash = getCash()
	if buildingCount("Market") < CONFIG.marketCap and cash >= buildCost("Market") + 15 then
		local x, z = findOpenSpot(2)
		if x then placeVerify("Market", x, z) end
		return
	end
	for _, b in ipairs(mf.Buildings:GetChildren()) do
		if b.Name == "Market" and b:GetAttribute("Built") == true then
			local last = state.invest[b]
			if not last or (os.clock() - last) > 95 then
				cash = getCash()
				local tier
				if cash >= 330 then tier = "Metal"
				elseif cash >= 180 then tier = "Wood"
				elseif cash >= 95 then tier = "Wheat" end
				if tier and canFire() then
					pcall(function() RS.Invest:FireServer(b, tier) end)
					state.invest[b] = os.clock()
				end
			end
		end
	end
end, 2.5)

spawnLoop(function()
	if not state.auto.tech then return end
	if not econReady() then return end
	if not builtBuilding("Barracks") and buildingCount("Barracks") == 0 and getCash() >= CONFIG.barracksMinCash then
		local x, z = findOpenSpot(2)
		if x then placeVerify("Barracks", x, z) end
		return
	end
	if state.auto.siege and not builtBuilding("Siege Workshop") and buildingCount("Siege Workshop") == 0 and getCash() >= CONFIG.siegeShopMinCash then
		local x, z = findOpenSpot(2)
		if x then placeVerify("Siege Workshop", x, z) end
	end
end, CONFIG.scan + 0.6)

spawnLoop(function()
	local ub = unbuiltBuildings()
	if #ub == 0 then return end
	local blds = unitsNamed("Builder")
	if #blds == 0 then return end
	local c = castle()
	local cp = c and c.PrimaryPart and c.PrimaryPart.Position
	local target, td
	for _, b in ipairs(ub) do
		local bp = b.PrimaryPart.Position
		local d = cp and (bp - cp).Magnitude or 0
		if not td or d < td then td = d; target = bp end
	end
	if target then
		local goals = {}
		for _, u in ipairs(blds) do table.insert(goals, { u, target }) end
		if #goals > 0 and canFire() then
			pcall(function() RS.SendUnitGoals:InvokeServer(goals, false, true) end)
		end
	end
end, 2)

spawnLoop(function()
	if not state.auto.army then return end
	local bar = builtBuilding("Barracks")
	if bar then
		for _, unit in ipairs(CONFIG.armyOrder) do
			if need(unit, CONFIG.army[unit] or 0) then
				if getCash() >= buildCost(unit) then recruit(unit, bar) end
				break
			end
		end
	end
end, 1.4)

spawnLoop(function()
	if not state.auto.siege then return end
	if not econReady() then return end
	local sw = builtBuilding("Siege Workshop")
	if not sw then return end
	for _, unit in ipairs(CONFIG.siegeOrder) do
		if need(unit, CONFIG.siege[unit] or 0) and getCash() >= buildCost(unit) then
			recruit(unit, sw)
			break
		end
	end
end, 1.6)

spawnLoop(function()
	if not state.auto.upgrades then return end
	local mf = myFolder()
	if not mf then return end
	if buildingCount("Market") < 1 and not (buildingCount("Windmill") >= 2) then return end
	if getCash() >= CONFIG.windmillUpgradeMinCash then
		for _, b in ipairs(mf.Buildings:GetChildren()) do
			if b.Name == "Windmill" and b:GetAttribute("Built") == true and (b:GetAttribute("UpgradeIndex") or 0) == 0 then
				upgrade(b)
				task.wait(0.25)
				break
			end
		end
	end
	if getCash() >= CONFIG.castleUpgradeMinCash then
		local c = castle()
		if c and c:GetAttribute("Built") == true and (c:GetAttribute("UpgradeIndex") or 0) == 0 then
			upgrade(c)
		end
	end
end, 2.5)

spawnLoop(function()
	if not state.auto.defense then return end
	if staticDefenseUp() and #combatUnits() >= CONFIG.pushAnywayArmy then return end
	local threats = enemyNearCastle(75)
	if #threats == 0 then return end
	local c = castle()
	if not (c and c.PrimaryPart) then return end
	local cp = c.PrimaryPart.Position
	local tp = threats[1].PrimaryPart.Position
	local dir = (Vector3.new(tp.X, 0, tp.Z) - Vector3.new(cp.X, 0, cp.Z))
	if dir.Magnitude > 0 then dir = dir.Unit else dir = Vector3.new(0, 0, 1) end
	local rally = Vector3.new(cp.X + dir.X * 11, cp.Y, cp.Z + dir.Z * 11)
	orderUnits(combatUnits(), rally, false)
end, 1.8)

spawnLoop(function()
	if not state.auto.defense then return end
	if not threatened() then return end
	if #unbuiltBuildings() > 0 then return end
	local c = castle()
	if not (c and c.PrimaryPart) then return end
	local cp = c.PrimaryPart.Position
	if buildingCount("Tower") < CONFIG.towerCap and getCash() >= buildCost("Tower") then
		local x, z = findOpenSpot(2)
		if x then placeVerify("Tower", x, z); return end
	end
	if buildingCount("Watchtower") < CONFIG.watchtowerCap and getCash() >= buildCost("Watchtower") then
		local x, z = findOpenSpot(2)
		if x then placeVerify("Watchtower", x, z); return end
	end
	if buildingCount("Trap") < CONFIG.trapCap and getCash() >= buildCost("Trap") then
		local threats = enemyNearCastle(75)
		if #threats > 0 then
			local tp = threats[1].PrimaryPart.Position
			local dir = (Vector3.new(tp.X, 0, tp.Z) - Vector3.new(cp.X, 0, cp.Z))
			if dir.Magnitude > 0 then dir = dir.Unit else dir = Vector3.new(0, 0, 1) end
			placeVerify("Trap", math.floor(cp.X + dir.X * 15), math.floor(cp.Z + dir.Z * 15))
		end
	end
end, 2)

spawnLoop(function()
	if not state.auto.rush then return end
	local ec = enemyCastle()
	if not (ec and ec.PrimaryPart) then return end
	local army = combatUnits()
	local canPush = #army >= CONFIG.pushAnywayArmy
		or (not threatened() and #army >= CONFIG.pushArmy and siegeCount() >= CONFIG.pushSiege)
	if canPush then
		state.phase = "SIEGE"
		orderUnits(army, ec.PrimaryPart.Position, false)
	end
end, 3)

spawnLoop(function()
	local b = buildingCount("Windmill")
	if state.phase ~= "SIEGE" then
		if b < 3 then state.phase = "ECONOMY"
		elseif not builtBuilding("Siege Workshop") then state.phase = "TECH"
		else state.phase = "ARMY" end
	end
end, 1)

local function unload()
	state.running = false
	_G.__MRTS_AFK = false
	_G.__MRTS_AI_UNLOAD = nil
	for _, c in ipairs(state.conns) do pcall(function() c:Disconnect() end) end
	state.conns = {}
	pcall(function() workspace.Game.BotsEnabled.Value = true end)
	if state.gui then pcall(function() state.gui:Destroy() end) end
end
_G.__MRTS_AI_UNLOAD = unload

local PALETTE = {
	bg = Color3.fromRGB(15, 14, 22), panel = Color3.fromRGB(23, 21, 34), row = Color3.fromRGB(31, 28, 46),
	text = Color3.fromRGB(232, 230, 245), dim = Color3.fromRGB(150, 146, 172),
	on = Color3.fromRGB(150, 110, 255), off = Color3.fromRGB(60, 56, 80),
	accentA = Color3.fromRGB(150, 90, 255), accentB = Color3.fromRGB(70, 200, 255),
}
local function corner(p, r) local u = Instance.new("UICorner"); u.CornerRadius = UDim.new(0, r or 8); u.Parent = p end
local function pad(p, n) local u = Instance.new("UIPadding"); u.PaddingLeft = UDim.new(0, n); u.PaddingRight = UDim.new(0, n); u.PaddingTop = UDim.new(0, n); u.PaddingBottom = UDim.new(0, n); u.Parent = p end

local function build()
	local parent = (gethui and gethui()) or game:GetService("CoreGui")
	local sg = Instance.new("ScreenGui")
	sg.Name = "MedievalRTS_AI"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.IgnoreGuiInset = true
	if syn and syn.protect_gui then pcall(syn.protect_gui, sg) end
	sg.Parent = parent
	state.gui = sg

	local main = Instance.new("Frame")
	main.Size = UDim2.new(0, 312, 0, 548)
	main.Position = UDim2.new(0, 40, 0.5, -274)
	main.BackgroundColor3 = PALETTE.panel
	main.BorderSizePixel = 0
	main.Parent = sg
	corner(main, 14)
	local stroke = Instance.new("UIStroke"); stroke.Color = PALETTE.accentA; stroke.Transparency = 0.4; stroke.Thickness = 1.4; stroke.Parent = main

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 46); bar.BackgroundColor3 = PALETTE.bg; bar.BorderSizePixel = 0; bar.Parent = main
	corner(bar, 14)
	local grad = Instance.new("UIGradient"); grad.Color = ColorSequence.new(PALETTE.accentA, PALETTE.accentB); grad.Rotation = 20; grad.Parent = bar
	local barOv = Instance.new("Frame"); barOv.Size = UDim2.new(1, 0, 0, 24); barOv.Position = UDim2.new(0, 0, 1, -24); barOv.BackgroundColor3 = PALETTE.bg; barOv.BorderSizePixel = 0; barOv.Parent = bar

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1; title.Size = UDim2.new(1, -50, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
	title.Font = Enum.Font.GothamBold; title.Text = "MEDIEVAL RTS  ·  MATCH AI"; title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(255, 255, 255); title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = bar

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.Position = UDim2.new(1, -38, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 90); closeBtn.Text = "X"; closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14; closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255); closeBtn.Parent = bar
	corner(closeBtn, 8); track(closeBtn.MouseButton1Click:Connect(unload))

	local status = Instance.new("TextLabel")
	status.BackgroundColor3 = PALETTE.row; status.BackgroundTransparency = 0.2; status.Size = UDim2.new(1, -20, 0, 92)
	status.Position = UDim2.new(0, 10, 0, 54); status.Font = Enum.Font.GothamMedium; status.TextSize = 12
	status.TextColor3 = PALETTE.text; status.TextXAlignment = Enum.TextXAlignment.Left; status.TextYAlignment = Enum.TextYAlignment.Top
	status.Text = ""; status.Parent = main; corner(status, 10); pad(status, 10)

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1; list.Size = UDim2.new(1, -20, 1, -212); list.Position = UDim2.new(0, 10, 0, 154); list.Parent = main
	local layout = Instance.new("UIListLayout"); layout.Padding = UDim.new(0, 7); layout.Parent = list

	local function toggleRow(label, key)
		local row = Instance.new("Frame"); row.Size = UDim2.new(1, 0, 0, 30); row.BackgroundColor3 = PALETTE.row; row.BorderSizePixel = 0; row.Parent = list
		corner(row, 9)
		local lbl = Instance.new("TextLabel"); lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -66, 1, 0); lbl.Position = UDim2.new(0, 12, 0, 0)
		lbl.Font = Enum.Font.GothamMedium; lbl.Text = label; lbl.TextSize = 12.5; lbl.TextColor3 = PALETTE.text; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = row
		local sw = Instance.new("TextButton"); sw.Size = UDim2.new(0, 44, 0, 21); sw.Position = UDim2.new(1, -54, 0.5, -10.5)
		sw.BackgroundColor3 = state.auto[key] and PALETTE.on or PALETTE.off; sw.Text = ""; sw.AutoButtonColor = false; sw.Parent = row; corner(sw, 11)
		local knob = Instance.new("Frame"); knob.Size = UDim2.new(0, 17, 0, 17); knob.Position = state.auto[key] and UDim2.new(1, -19, 0.5, -8.5) or UDim2.new(0, 2, 0.5, -8.5)
		knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255); knob.BorderSizePixel = 0; knob.Parent = sw; corner(knob, 9)
		track(sw.MouseButton1Click:Connect(function()
			state.auto[key] = not state.auto[key]
			TweenService:Create(sw, TweenInfo.new(0.15), { BackgroundColor3 = state.auto[key] and PALETTE.on or PALETTE.off }):Play()
			TweenService:Create(knob, TweenInfo.new(0.15), { Position = state.auto[key] and UDim2.new(1, -19, 0.5, -8.5) or UDim2.new(0, 2, 0.5, -8.5) }):Play()
		end))
	end

	toggleRow("Экономика (мельницы/дома)", "economy")
	toggleRow("Маркет-инвест (компаунд)", "market")
	toggleRow("Экспансия (Outpost к supply)", "expand")
	toggleRow("Тех (Barracks/Siege/Stables)", "tech")
	toggleRow("Армия (контр-состав)", "army")
	toggleRow("Осада (Catapult/Ballista/Ram)", "siege")
	toggleRow("Апгрейды (мельницы/замок)", "upgrades")
	toggleRow("Оборона замка", "defense")
	toggleRow("Раш вражеского замка", "rush")

	local unloadBtn = Instance.new("TextButton")
	unloadBtn.Size = UDim2.new(1, -20, 0, 34); unloadBtn.Position = UDim2.new(0, 10, 1, -44)
	unloadBtn.BackgroundColor3 = Color3.fromRGB(40, 36, 58); unloadBtn.Font = Enum.Font.GothamBold; unloadBtn.Text = "ВЫГРУЗИТЬ"
	unloadBtn.TextSize = 13; unloadBtn.TextColor3 = Color3.fromRGB(255, 120, 140); unloadBtn.Parent = main; corner(unloadBtn, 10)
	local ust = Instance.new("UIStroke"); ust.Color = Color3.fromRGB(220, 70, 90); ust.Transparency = 0.5; ust.Parent = unloadBtn
	track(unloadBtn.MouseButton1Click:Connect(unload))

	local dragging, dragStart, startPos
	track(bar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true; dragStart = i.Position; startPos = main.Position
		end
	end))
	track(UserInput.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	track(UserInput.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))

	spawnLoop(function()
		local mf = myFolder()
		local st = mf and mf:FindFirstChild("Stats")
		local afk = (workspace.Game.BotsEnabled.Value == false) and "контроль ✓" or "ЛАТЧ ⚠"
		local ec = select(1, enemyCastle())
		local ehp = ec and ec.PrimaryPart and (ec.PrimaryPart.Health and math.floor(ec.PrimaryPart.Health)) or "-"
		local army = #combatUnits()
		if st then
			status.Text = string.format(
				"ФАЗА: %s    %s\n💰 %d$  (~%d/мин)   👥 %d/%d  🏰 %d/%d\nмельниц:%d  армия:%d  осада:%d\nвраж.замок HP: %s",
				state.phase, afk, getCash(), math.floor(state.income),
				st.CurrentUnits.Value, st.MaxUnits.Value, st.CurrentBuildings.Value, st.MaxBuildings.Value,
				buildingCount("Windmill"), army, siegeCount(), tostring(ehp))
		else
			status.Text = "Ожидание королевства...  " .. afk
		end
	end, 0.5)
end

build()
