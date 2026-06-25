local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")

local lp = Players.LocalPlayer
local SAFE_POS = Vector3.new(-882, 6.1, -167)
local BUNKER_ENTRANCE = Vector3.new(-827, 3, -115)

if getgenv then local prev = getgenv().__BackroomsAF if type(prev) == "function" then pcall(prev) end end

local State = {
	running = true,
	autoKill = false, autoBoxes = false, autoLockpick = false, autoLoot = false,
	autoMinigames = false, autoBestWeapon = false, useMapWeapons = false, aoeMelee = true, includeBoss = false,
	attackType = "M1", attacksPerSec = 2.2, searchRadius = 16,
	godmode = false, godmodeMode = "Stealth", infStamina = false,
	autoHeal = false, autoBuyHeal = false, hitRun = false, autoFlee = false,
	healPct = 0.55, fleePct = 0.25, hopHeight = 14,
	hauler = false, haulKeep = "",
	autoRestock = false,
	fullBright = false, gamma = 1.0,
	moveMode = "Teleport", moveSpeed = 240, lootSettle = 0.6, noclipSafe = true,
	collectCurrency = true, biggestFirst = true, lootFilter = {},
	esp = false, espMobs = true, espLoot = true, espBoxes = true, espCrates = true, espPlayers = false, espBunker = true, espDistance = 600,
	currentAction = "Ожидание",
	startKills = 0, startEXP = 0, startCredits = 0, startScraps = 0,
	gainExp = 0, gainCredits = 0, gainScraps = 0,
	boxesBroken = 0, cratesOpened = 0, lootGrabbed = 0, deaths = 0,
	perMob = {}, startClock = os.clock(), weaponReadyAt = 0,
}

local connections = {}
local function addConn(c) connections[#connections + 1] = c return c end
local function new(class, props, parent)
	local i = Instance.new(class)
	if props then for k, v in pairs(props) do i[k] = v end end
	if parent then i.Parent = parent end
	return i
end

local function getChar() return lp.Character end
local function getHRP() local c = lp.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = lp.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function hpPct() local h = getHum() if not h or h.MaxHealth <= 0 then return nil end return h.Health / h.MaxHealth end

local Data
do local pf = lp:FindFirstChild("playerFolder") Data = pf and pf:FindFirstChild("Data") end
local function statValue(n) if not Data then return 0 end local o = Data:FindFirstChild(n) return o and o.Value or 0 end
local function endurance()
	local s = Data and Data:FindFirstChild("Skills") local e = s and s:FindFirstChild("Endurance")
	return e and e.Value or 0
end
State.startKills = statValue("NPC Kills") State.startEXP = statValue("EXP") State.startCredits = statValue("Credits") State.startScraps = statValue("Scraps")

local function hasItem(name)
	if lp.Backpack:FindFirstChild(name) then return true end
	local c = lp.Character return c and c:FindFirstChild(name) ~= nil
end
local function foodCount()
	local n = 0
	local function scan(p) if not p then return end for _, t in ipairs(p:GetChildren()) do
		if t:IsA("Tool") and t:FindFirstChild("ConsumableStats") then
			local ok, m = pcall(require, t.ConsumableStats) if ok and type(m) == "table" and (m.healPerUse or 0) > 0 then n = n + 1 end
		end end end
	scan(lp.Backpack) scan(lp.Character) return n
end

local notify
-- ============================ NOCLIP-SAFE MOVEMENT ============================
local function boxClear(pos)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { lp.Character }
	local parts = workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(3, 4.5, 3), params)
	for _, p in ipairs(parts) do if p.CanCollide then return false end end
	return true
end
local function safeTeleport(dest)
	local hrp = getHRP() if not hrp then return false end
	pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
	if not State.noclipSafe or boxClear(dest.Position) then hrp.CFrame = dest return true end
	local rot = dest - dest.Position
	for _, off in ipairs({ Vector3.new(0, 4, 0), Vector3.new(0, 7, 0), Vector3.new(0, 10, 0) }) do
		if boxClear(dest.Position + off) then hrp.CFrame = CFrame.new(dest.Position + off) * rot return true end
	end
	hrp.CFrame = dest
	return true
end
local function gotoCFrame(dest, settle)
	local hrp = getHRP() if not hrp then return false end
	local mode = State.moveMode
	if mode == "Walk" then
		local hum = getHum()
		if hum then local t = 0 repeat hum:MoveTo(dest.Position) task.wait(0.1) t = t + 0.1 hrp = getHRP() until (not State.running) or (not hrp) or (hrp.Position - dest.Position).Magnitude <= 5 or t >= 5 end
		task.wait(settle or 0.1)
	elseif mode == "Tween" then
		local dist = (hrp.Position - dest.Position).Magnitude
		local dur = math.clamp(dist / math.max(State.moveSpeed, 10), 0.05, 5)
		local tw = TweenService:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = dest })
		local done = false tw.Completed:Connect(function() done = true end) tw:Play()
		local t = 0 while State.running and not done and t < 6 do task.wait(0.03) t = t + 0.03 end
		if not done then pcall(function() tw:Cancel() end) end
		task.wait(settle or 0.2)
	else
		safeTeleport(dest)
		task.wait(settle or 0.3)
	end
	return true
end
local function teleportToSafeZone() local hrp = getHRP() if not hrp then return false end pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end) hrp.CFrame = CFrame.new(SAFE_POS) task.wait(0.5) return true end

-- ============================ GODMODE ============================
local God = { conns = {}, saved = {} }
local function godProtectPart(p)
	if p:IsA("BasePart") then
		if God.saved[p] == nil then God.saved[p] = { p.CanQuery, p.CanTouch } end
		p.CanQuery = false p.CanTouch = false
	end
end
local function godBind(char)
	for _, c in ipairs(God.conns) do pcall(function() c:Disconnect() end) end God.conns = {}
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) hum.BreakJointsOnDeath = false end) end
	for _, p in ipairs(char:GetDescendants()) do godProtectPart(p) end
	God.conns[#God.conns + 1] = char.DescendantAdded:Connect(function(d) if State.godmode then godProtectPart(d) end end)
	if hum then God.conns[#God.conns + 1] = hum.HealthChanged:Connect(function(h) if State.godmode and h < hum.MaxHealth then hum.Health = hum.MaxHealth end end) end
end
local function godDisable()
	for _, c in ipairs(God.conns) do pcall(function() c:Disconnect() end) end God.conns = {}
	for p, v in pairs(God.saved) do if p and p.Parent then pcall(function() p.CanQuery = v[1] p.CanTouch = v[2] end) end end
	God.saved = {}
	local hum = getHum() if hum then pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true) if hum.MaxHealth ~= 100 then hum.MaxHealth = 100 hum.Health = 100 end end) end
end

-- ============================ WEAPONS ============================
local Tools = ReplicatedStorage.Game.Assets.Tools
local function weaponPower(stats, kind)
	if kind == "melee" then return (stats.damage or 0) * (stats.npcDamageMultiplier or 1) * (stats.swingSpeed or 1) end
	return (stats.damage or 0) * ((stats.fireRate or 60) / 60) * (stats.shotgunPellets or 1)
end
local function ownedWeapons()
	local out = {}
	local function scan(c) if not c then return end for _, t in ipairs(c:GetChildren()) do
		if t:IsA("Tool") then
			local mm = t:FindFirstChild("MeleeStats")
			if mm then local ok, s = pcall(require, mm) if ok and s.damage and not s.isAdminWeapon then
				local st = t:FindFirstChild("Stats") local d = st and st:FindFirstChild("Durability")
				local maxd = s.durability or 1
				out[#out + 1] = { tool = t, name = t.Name, kind = "melee", cur = d and d.Value or maxd, max = maxd, power = weaponPower(s, "melee") }
			end end
		end
	end end
	scan(lp.Backpack) scan(lp.Character)
	return out
end
local function strongestUsable()
	local best, score = nil, -1
	for _, w in ipairs(ownedWeapons()) do
		if w.cur > w.max * 0.03 and w.max < 1e13 then
			local sc = w.power
			if sc > score then best, score = w, sc end
		end
	end
	if not best then for _, w in ipairs(ownedWeapons()) do if w.name == "Fist" then best = w end end end
	return best
end
local function equipWeapon(tool)
	local char = lp.Character if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid") if not hum then return end
	if tool.Parent == char then return end
	pcall(function() hum:UnequipTools() end)
	task.wait(0.05)
	pcall(function() hum:EquipTool(tool) end)
	if tool.Parent ~= char then tool.Parent = char end
	State.weaponReadyAt = os.clock() + 2.0
end
local function ensureBestWeapon()
	if not State.autoBestWeapon then return end
	local char = lp.Character if not char then return end
	local equipped = char:FindFirstChildOfClass("Tool")
	local best = strongestUsable()
	if best and best.tool and (not equipped or equipped.Name ~= best.name) then equipWeapon(best.tool) end
end
local WEAPON_IDX
local function weaponIndex()
	if WEAPON_IDX then return WEAPON_IDX end
	WEAPON_IDX = {}
	local function add(folder, kind) if not folder then return end for _, t in ipairs(folder:GetChildren()) do
		local m = t:FindFirstChild("MeleeStats") or t:FindFirstChild("WeaponStats")
		if m then local ok, s = pcall(require, m) if ok then WEAPON_IDX[t.Name] = { kind = kind, power = weaponPower(s, kind == "melee" and "melee" or "gun"), reqLvl = s.requiredLevel } end end
	end end
	add(Tools:FindFirstChild("Melee"), "melee") add(Tools:FindFirstChild("Misc"), "melee") add(Tools:FindFirstChild("Weapons"), "gun")
	return WEAPON_IDX
end

-- ============================ HEAL ============================
local function bestFood()
	local best, bh
	local function consider(t) if t:IsA("Tool") and t:FindFirstChild("ConsumableStats") then
		local u = t:FindFirstChild("Stats") and t.Stats:FindFirstChild("Uses")
		if (not u) or u.Value > 0 then local ok, m = pcall(require, t.ConsumableStats)
			if ok and type(m) == "table" and (m.healPerUse or 0) > 0 then if not bh or m.healPerUse > bh then best, bh = t, m.healPerUse end end end
	end end
	for _, t in ipairs(lp.Backpack:GetChildren()) do consider(t) end
	local c = lp.Character if c then for _, t in ipairs(c:GetChildren()) do consider(t) end end
	return best
end
local shopRemote, buySmart
local function healCycle(maxTries, target)
	local char = lp.Character local hum = char and char:FindFirstChildOfClass("Humanoid") if not hum then return false end
	local food = bestFood()
	if not food and State.autoBuyHeal then buySmart("Almond Bottle", 3) task.wait(0.3) food = bestFood() end
	if not food then return false end
	local prev = char:FindFirstChildOfClass("Tool")
	pcall(function() hum:UnequipTools() end) task.wait(0.25)
	food.Parent = char task.wait(0.5) pcall(function() food.Enabled = true end)
	target = target or 0.95
	for _ = 1, (maxTries or 6) do
		if not State.running then break end
		if (hum.Health / hum.MaxHealth) >= target then break end
		local u = food:FindFirstChild("Stats") and food.Stats:FindFirstChild("Uses")
		if u and u.Value <= 0 then food = bestFood() if not food and State.autoBuyHeal then buySmart("Almond Bottle", 3) task.wait(0.3) food = bestFood() end if not food then break end food.Parent = char task.wait(0.4) end
		pcall(function() food:Activate() end) task.wait(1.2)
	end
	pcall(function() hum:UnequipTools() end) task.wait(0.1)
	if prev and prev.Parent and prev ~= food then pcall(function() hum:EquipTool(prev) end) end
	State.weaponReadyAt = os.clock() + 2.0
	return true
end

-- ============================ TARGET FINDERS ============================
local BOXNAMES = { Randomized = true, RaritySpecified = true, RaritySpecifiedFixed = true, RarityFixedCommon = true }
local CUR_TIER = { Card3 = 5, Card2 = 4, Card1 = 3, Card = 2, Coin = 1 }
local function itemsFolder() local g = workspace:FindFirstChild("Game") return g and g:FindFirstChild("Items") end
local function boxLootCache() local i = itemsFolder() return i and i:FindFirstChild("Cache") end
local function playerDropFolder() local g = workspace:FindFirstChild("Game") local c = g and g:FindFirstChild("Cache") return c and c:FindFirstChild("Items") end

local function nearestNPC()
	local hrp = getHRP() if not hrp then return nil end
	local npcRoot = workspace:FindFirstChild("NPCs") if not npcRoot then return nil end
	local folders = { "Zombies", "Enemy", "Recon", "Neutrals" } if State.includeBoss then folders[#folders + 1] = "Boss" end
	local best, bestHum, bestRoot, bestDist
	for _, fn in ipairs(folders) do local f = npcRoot:FindFirstChild(fn)
		if f then for _, m in ipairs(f:GetChildren()) do if m:IsA("Model") then
			local h = m:FindFirstChildOfClass("Humanoid") local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
			if h and r and h.Health > 0 and h.Health < 1e6 then local d = (r.Position - hrp.Position).Magnitude
				if not bestDist or d < bestDist then best, bestHum, bestRoot, bestDist = m, h, r, d end end
		end end end
	end
	return best, bestHum, bestRoot, bestDist
end
local function nearestBox()
	local hrp = getHRP() if not hrp then return nil end
	local items = itemsFolder() local boxes = items and items:FindFirstChild("Boxes") if not boxes then return nil end
	local best, bestDist
	for _, m in ipairs(boxes:GetDescendants()) do
		if m:IsA("Model") and BOXNAMES[m.Name] and m:FindFirstChild("Body") and m.Body:IsA("BasePart") and not m:FindFirstChild("Indestructible") and not m:FindFirstChild("Destroyed") then
			local d = (m.Body.Position - hrp.Position).Magnitude if not bestDist or d < bestDist then best, bestDist = m, d end
		end
	end
	return best, bestDist
end
local function nearestCrate()
	local hrp = getHRP() if not hrp then return nil end
	local items = itemsFolder() local lc = items and items:FindFirstChild("LockpickCrates") if not lc then return nil end
	local best, bestDist, bestPos
	for _, m in ipairs(lc:GetDescendants()) do
		if m:IsA("Model") and m:FindFirstChild("PromptAttachment") and m.PromptAttachment:FindFirstChild("PromptLockpick") and not m:FindFirstChild("Destroyed") and not m:FindFirstChild("Contraband") then
			local body = m:FindFirstChild("Body") local pos = (body and body:IsA("BasePart") and body.Position) or m:GetPivot().Position
			local d = (pos - hrp.Position).Magnitude if not bestDist or d < bestDist then best, bestDist, bestPos = m, d, pos end
		end
	end
	return best, bestDist, bestPos
end
local function lootEligible(model, prompt)
	local tier = CUR_TIER[model.Name] if tier then return State.collectCurrency, tier end
	local nm = prompt.ActionText if next(State.lootFilter) == nil then return true, 0 end
	return State.lootFilter[nm] == true, 0
end
local function nearestLoot()
	local hrp = getHRP() if not hrp then return nil end
	local cache = boxLootCache() if not cache then return nil end
	local best, bestScore
	for _, m in ipairs(cache:GetChildren()) do
		local prompt for _, d in ipairs(m:GetDescendants()) do if d:IsA("ProximityPrompt") and d.Enabled then prompt = d break end end
		if prompt then local ok, tier = lootEligible(m, prompt)
			if ok then local part = (m:IsA("BasePart") and m) or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				if part then local dist = (part.Position - hrp.Position).Magnitude
					local score = State.biggestFirst and (tier * 100000 - dist) or (-dist)
					if not bestScore or score > bestScore then best, bestScore = { model = m, prompt = prompt, part = part, dist = dist }, score end end end end
	end
	return best
end

local function doCollect(loot)
	State.currentAction = "Сбор: " .. (loot.prompt.ActionText ~= "" and loot.prompt.ActionText or loot.model.Name)
	gotoCFrame(CFrame.new(loot.part.Position + Vector3.new(0, 3, 0)), State.lootSettle)
	for _ = 1, 3 do if not loot.model.Parent then break end pcall(function() fireproximityprompt(loot.prompt) end) task.wait(0.22) end
	if not loot.model.Parent then State.lootGrabbed = State.lootGrabbed + 1 end
end
local function collectNearby(radius)
	if not State.autoLoot then return end
	local hrp = getHRP() if not hrp then return end
	for _ = 1, 10 do local l = nearestLoot() if not l or l.dist > radius then break end doCollect(l) end
end

-- ============================ MELEE (AOE, server-cap) ============================
local lastHit = setmetatable({}, { __mode = "k" })
local function getMeleeTool()
	local char = lp.Character if not char then return nil end
	local function valid(t) return t:IsA("Tool") and t:FindFirstChild("MeleeStats") and t:FindFirstChild("Remotes") and t.Remotes:FindFirstChild("OnHit") end
	local eq = char:FindFirstChildOfClass("Tool")
	if eq and valid(eq) then return eq, eq.Remotes.OnHit end
	for _, t in ipairs(char:GetChildren()) do if valid(t) then return t, t.Remotes.OnHit end end
	local fist = lp.Backpack:FindFirstChild("Fist")
	if fist and valid(fist) then local hum = char:FindFirstChildOfClass("Humanoid") if hum then hum:EquipTool(fist) State.weaponReadyAt = os.clock() + 2.0 task.wait(0.15) end return fist, fist:FindFirstChild("Remotes") and fist.Remotes:FindFirstChild("OnHit") end
	return nil
end
local function aoeMeleeBurst()
	if os.clock() < State.weaponReadyAt then task.wait(0.1) return end
	local tool, onhit = getMeleeTool() if not (tool and onhit) then return end
	local hrp = getHRP() if not hrp then return end
	local interval = 1 / math.clamp(State.attacksPerSec, 0.5, 6)
	local mode = State.attackType local radius = State.searchRadius local now = os.clock()
	local npcRoot = workspace:FindFirstChild("NPCs")
	if State.autoKill and npcRoot then
		local folders = { "Zombies", "Enemy", "Recon", "Neutrals" } if State.includeBoss then folders[#folders + 1] = "Boss" end
		for _, fn in ipairs(folders) do local f = npcRoot:FindFirstChild(fn)
			if f then for _, m in ipairs(f:GetChildren()) do
				local h = m:FindFirstChildOfClass("Humanoid") local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
				if h and r and h.Health > 0 and h.Health < 1e6 and (r.Position - hrp.Position).Magnitude <= radius then
					if (now - (lastHit[h] or 0)) >= interval then pcall(function() onhit:FireServer(h, mode) end) lastHit[h] = now if not State.aoeMelee then break end end
				end
			end end
		end
	end
	local items = itemsFolder() local boxes = items and items:FindFirstChild("Boxes")
	if State.autoBoxes and boxes then for _, m in ipairs(boxes:GetDescendants()) do
		if m:IsA("Model") and BOXNAMES[m.Name] and m:FindFirstChild("Body") and m.Body:IsA("BasePart") and not m:FindFirstChild("Indestructible") and not m:FindFirstChild("Destroyed") and (m.Body.Position - hrp.Position).Magnitude <= radius then
			if (now - (lastHit[m] or 0)) >= interval then pcall(function() onhit:FireServer(nil, mode, m) end) lastHit[m] = now end
		end
	end end
	task.wait(0.12)
end

local function doLockpick(crate, pos)
	if not hasItem("Lockpick") then
		notify("Для вскрытия ящиков нужна отмычка", "Купить x1", function() task.spawn(function() buySmart("Lockpick", 1) end) end)
		task.wait(1) return "need_lockpick"
	end
	local prompt = crate.PromptAttachment and crate.PromptAttachment:FindFirstChild("PromptLockpick") if not prompt then return end
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	State.currentAction = "Вскрытие: " .. crate.Name
	gotoCFrame(CFrame.new(pos + Vector3.new(0, 0, 3)), 0.7)
	pcall(function() fireproximityprompt(prompt) end)
	local gui for _ = 1, 30 do gui = pg:FindFirstChild("Lockpicking") if gui and gui:FindFirstChild("FinishEvent") and gui:FindFirstChild("BodyPart") and gui.BodyPart.Value then break end task.wait(0.1) end
	if not (gui and gui:FindFirstChild("FinishEvent")) then local hrp = getHRP() if hrp then hrp.Anchored = false end return "no_gui" end
	task.wait(0.35) pcall(function() gui.FinishEvent:FireServer(gui.BodyPart.Value) end)
	task.wait(0.3) pcall(function() gui.CloseEvent:FireServer() end) pcall(function() gui.Enabled = false end)
	task.wait(0.2) local hrp = getHRP() if hrp then hrp.Anchored = false end pcall(function() gui:Destroy() end)
	if crate:FindFirstChild("Destroyed") then State.cratesOpened = State.cratesOpened + 1 end
	collectNearby(45)
end

-- ============================ LOOT HAULER ============================
local haulStart, haulOwn = nil, setmetatable({}, { __mode = "k" })
local function carriedWeight()
	local w = 0 local char = lp.Character
	for _, t in ipairs(lp.Backpack:GetChildren()) do if t:IsA("Tool") then local ww = t:FindFirstChild("Weight") w = w + (ww and ww.Value or 1) end end
	if char then for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then local ww = t:FindFirstChild("Weight") w = w + (ww and ww.Value or 1) end end end
	return w
end
local function maxCap()
	local base = statValue("Max Backpack Inventory") local char = lp.Character local exp = 0
	if char then local ce = char:FindFirstChild("carryExpansion") if ce then exp = math.max(ce.Value, 0) end end
	return base + exp
end
local function isFull() return (maxCap() - carriedWeight()) < 0.25 end
local function dropTool(tool)
	local char = lp.Character if not (char and tool and tool.Parent) then return false end
	local DropItem = ReplicatedStorage.Game.Events.Remotes:FindFirstChild("DropItem") if not DropItem then return false end
	local dropFolder = playerDropFolder()
	local before = {} if dropFolder then for _, m in ipairs(dropFolder:GetChildren()) do before[m] = true end end
	tool.Parent = char task.wait(0.35)
	pcall(function() DropItem:FireServer(tool, Vector3.new(0, 0, 0)) end)
	if dropFolder then for _ = 1, 25 do task.wait(0.05)
		for _, m in ipairs(dropFolder:GetChildren()) do if not before[m] then haulOwn[m] = true end end
	end end
	return true
end
local function dropAllExceptKeep(keepName)
	local char = lp.Character if not char then return 0 end
	local list = {}
	for _, t in ipairs(lp.Backpack:GetChildren()) do if t:IsA("Tool") then list[#list + 1] = t end end
	for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then list[#list + 1] = t end end
	local n = 0
	for _, t in ipairs(list) do if t.Name ~= "Fist" and t.Name ~= keepName then if dropTool(t) then n = n + 1 task.wait(0.4) end end end
	return n
end
local function isOwnDrop(handle)
	if not handle then return true end
	local pdf = playerDropFolder()
	if pdf and handle:IsDescendantOf(pdf) then return true end
	if haulOwn[handle] then return true end
	if haulStart then local pos = handle:IsA("BasePart") and handle.Position or handle:GetPivot().Position if (pos - haulStart.Position).Magnitude < 18 then return true end end
	return false
end
local function haulStep()
	if not haulStart then local hrp = getHRP() if hrp then haulStart = hrp.CFrame end return end
	State.currentAction = "Хаулер: добыча"
	local guard = 0
	while State.running and State.hauler and not isFull() and guard < 40 do
		guard = guard + 1
		local cache = boxLootCache()
		local best, bd
		if cache then for _, m in ipairs(cache:GetChildren()) do
			if not isOwnDrop(m) then local part = (m:IsA("BasePart") and m) or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				local prompt for _, d in ipairs(m:GetDescendants()) do if d:IsA("ProximityPrompt") and d.Enabled then prompt = d break end end
				if part and prompt then local hrp = getHRP() local d = hrp and (part.Position - hrp.Position).Magnitude or 1e9
					if not bd or d < bd then best, bd = { model = m, prompt = prompt, part = part, dist = d }, d end end end
		end end
		if best then doCollect(best)
		else
			local box = nearestBox()
			if box then State.currentAction = "Хаулер: ломаю ящик"
				gotoCFrame(CFrame.new(box.Body.Position + Vector3.new(0, 0, 3)), 0.3)
				local g2 = 0 while State.running and State.hauler and box.Parent and not box:FindFirstChild("Destroyed") and g2 < 20 do aoeMeleeBurst() g2 = g2 + 1 end
				if not box.Parent or box:FindFirstChild("Destroyed") then State.boxesBroken = State.boxesBroken + 1 end
			else break end
		end
	end
	State.currentAction = "Хаулер: разгрузка"
	if haulStart then safeTeleport(haulStart) task.wait(0.5) end
	dropAllExceptKeep(State.haulKeep)
	task.wait(0.4)
end

-- ============================ MAIN LOOP ============================
task.spawn(function()
	while State.running do
		local hrp = getHRP()
		if not hrp then State.currentAction = "Ожидание респавна" task.wait(0.5) continue end

		if State.autoBestWeapon then ensureBestWeapon() end

		if not State.godmode then
			local pct = hpPct()
			if pct then
				if pct < State.fleePct then
					if State.autoFlee then State.currentAction = "Отступаю в бункер" teleportToSafeZone()
						local hum = getHum() local t = 0
						while State.running and hum and hum.Parent and (hum.Health / hum.MaxHealth) < 0.92 and t < 16 do if not healCycle(6, 0.95) then break end t = t + 2 end
						continue
					elseif State.autoHeal and (bestFood() or State.autoBuyHeal) then State.currentAction = "Лечусь" healCycle(6, 0.95) continue end
				elseif pct < State.healPct and State.autoHeal and (bestFood() or State.autoBuyHeal) then State.currentAction = "Лечусь" healCycle(6, 0.95) continue end
			end
		end

		if State.hauler then haulStep() continue end

		local candidates = {}
		if State.autoLoot then local l = nearestLoot() if l then candidates[#candidates + 1] = { kind = "loot", dist = l.dist, prio = 0, loot = l } end end
		if State.autoKill then local n, h, r, d = nearestNPC() if n then candidates[#candidates + 1] = { kind = "kill", dist = d, prio = 1, npc = n, hum = h, root = r } end end
		if State.autoBoxes then local b, d = nearestBox() if b then candidates[#candidates + 1] = { kind = "box", dist = d, prio = 2, box = b } end end
		if State.autoLockpick and hasItem("Lockpick") then local c, d, p = nearestCrate() if c then candidates[#candidates + 1] = { kind = "crate", dist = d, prio = 3, crate = c, pos = p } end end

		if #candidates > 0 then
			table.sort(candidates, function(a, b) if math.abs(a.dist - b.dist) < 8 then return a.prio < b.prio end return a.dist < b.dist end)
			local c = candidates[1]
			if c.kind == "loot" then doCollect(c.loot)
			elseif c.kind == "kill" then
				State.currentAction = "Убиваю: " .. c.npc.Name
				local dir = (hrp.Position - c.root.Position) dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, 1)
				gotoCFrame(CFrame.new(c.root.Position + dir * 3, c.root.Position), 0.12)
				local guard = 0
				while State.running and State.autoKill and c.npc.Parent and c.hum.Health > 0 and guard < 30 do
					aoeMeleeBurst()
					if State.hitRun and not State.godmode then local hh = getHRP() if hh and c.root.Parent then
						local up = math.min(State.hopHeight, 12)
						pcall(function() hh.AssemblyLinearVelocity = Vector3.zero end)
						hh.CFrame = CFrame.new(c.root.Position + dir * 3 + Vector3.new(0, up, 0)) task.wait(0.1)
						hh.CFrame = CFrame.new(c.root.Position + dir * 3, c.root.Position) end end
					guard = guard + 1
				end
				collectNearby(40)
			elseif c.kind == "box" then
				State.currentAction = "Ломаю: " .. c.box.Name
				gotoCFrame(CFrame.new(c.box.Body.Position + Vector3.new(0, 0, 3)), 0.3)
				local guard = 0 while State.running and State.autoBoxes and c.box.Parent and not c.box:FindFirstChild("Destroyed") and guard < 20 do aoeMeleeBurst() guard = guard + 1 end
				if not c.box.Parent or c.box:FindFirstChild("Destroyed") then State.boxesBroken = State.boxesBroken + 1 end
				collectNearby(45)
			elseif c.kind == "crate" then doLockpick(c.crate, c.pos) end
		else State.currentAction = "Поиск целей..." task.wait(0.3) end
	end
end)

task.spawn(function()
	while State.running do
		if State.autoMinigames then local pg = lp:FindFirstChild("PlayerGui")
			if pg then local lock = pg:FindFirstChild("Lockpicking") local swipe = pg:FindFirstChild("SwipeCard")
				if lock and lock:FindFirstChild("FinishEvent") then task.wait(0.8) if lock.Parent then local bp = lock:FindFirstChild("BodyPart") pcall(function() lock.FinishEvent:FireServer(bp and bp.Value) end) local ce = lock:FindFirstChild("CloseEvent") if ce then pcall(function() ce:FireServer() end) end local hrp = getHRP() if hrp then hrp.Anchored = false end end
				elseif swipe and swipe:FindFirstChild("Finished") then task.wait(0.8) if swipe.Parent then pcall(function() swipe.Finished:FireServer() end) local ce = swipe:FindFirstChild("CloseEvent") if ce then pcall(function() ce:FireServer() end) end end end
			end
		end
		task.wait(0.4)
	end
end)

-- ============================ SHOP ============================
function shopRemote()
	local ok, r = pcall(function() return require(ReplicatedStorage.Game.Helpers.EventAccess):GetAllEventInClass("Remotes").ShopProcess end)
	if ok and r then return r end
	local g = ReplicatedStorage:FindFirstChild("Game") local ev = g and g:FindFirstChild("Events") local rem = ev and ev:FindFirstChild("Remotes")
	return rem and rem:FindFirstChild("ShopProcess")
end
local function merchantWith(item)
	local g = workspace:FindFirstChild("Game") local Shop = g and g:FindFirstChild("Shop") if not Shop then return nil end
	for _, m in ipairs(Shop:GetChildren()) do if m:IsA("Folder") then for _, cat in ipairs(m:GetChildren()) do if cat:IsA("Folder") then
		local nv = cat:FindFirstChild(item) if nv and nv:IsA("NumberValue") and nv.Value >= 1 then return m.Name end end end end end
	return nil
end
function buySmart(item, qty)
	local sp = shopRemote() if not sp then return 0 end
	local n = 0
	for _ = 1, (qty or 1) do if not State.running then break end local m = merchantWith(item) if not m then break end pcall(function() sp:FireServer(m, item) end) n = n + 1 task.wait(0.35) end
	if n > 0 and notify then notify("Куплено: " .. item .. " x" .. n) end
	return n
end
local function upgradeWeight()
	local cap = statValue("Max Backpack Inventory") if cap >= 10 then return false, "max" end
	pcall(function() require(ReplicatedStorage.Game.Helpers.EventAccess):GetAllEventInClass("Remotes").UpgradeWeight:FireServer("INVENTORY") end) return true
end
task.spawn(function() while State.running do if State.autoRestock then if State.autoLockpick and not hasItem("Lockpick") then buySmart("Lockpick", 1) end if foodCount() < 2 then buySmart("Almond Bottle", 2 - foodCount()) end end task.wait(8) end end)

-- ============================ FULLBRIGHT + GAMMA ============================
local fbSaved, gammaCC
local function applyFullBright()
	Lighting.Brightness = 2 Lighting.ClockTime = 14 Lighting.FogEnd = 1e9 Lighting.FogStart = 1e9
	Lighting.Ambient = Color3.fromRGB(178, 178, 178) Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
	Lighting.GlobalShadows = false Lighting.ExposureCompensation = (State.gamma - 1)
	for _, v in ipairs(Lighting:GetChildren()) do
		if v:IsA("Atmosphere") then v.Density = 0 end
		if v:IsA("ColorCorrectionEffect") and v ~= gammaCC then v.Brightness = 0 v.Contrast = 0 v.TintColor = Color3.new(1, 1, 1) end
		if v:IsA("BlurEffect") then v.Size = 0 end
	end
	if gammaCC then gammaCC.Brightness = (State.gamma - 1) * 0.6 end
end
local function setFullBright(on)
	if on then
		if not fbSaved then
			fbSaved = { Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, GlobalShadows = Lighting.GlobalShadows, ExposureCompensation = Lighting.ExposureCompensation, atmos = {}, cc = {} }
			for _, v in ipairs(Lighting:GetChildren()) do if v:IsA("Atmosphere") then fbSaved.atmos[v] = v.Density end if v:IsA("ColorCorrectionEffect") then fbSaved.cc[v] = { v.Brightness, v.Contrast, v.TintColor } end end
		end
		if not gammaCC then gammaCC = new("ColorCorrectionEffect", { Name = "NR_Gamma", Brightness = 0 }, Lighting) end
		applyFullBright()
	else
		if gammaCC then gammaCC:Destroy() gammaCC = nil end
		if fbSaved then
			Lighting.Brightness = fbSaved.Brightness Lighting.ClockTime = fbSaved.ClockTime Lighting.FogEnd = fbSaved.FogEnd Lighting.FogStart = fbSaved.FogStart
			Lighting.Ambient = fbSaved.Ambient Lighting.OutdoorAmbient = fbSaved.OutdoorAmbient Lighting.GlobalShadows = fbSaved.GlobalShadows Lighting.ExposureCompensation = fbSaved.ExposureCompensation
			for v, d in pairs(fbSaved.atmos) do if v and v.Parent then v.Density = d end end
			for v, t in pairs(fbSaved.cc) do if v and v.Parent then v.Brightness, v.Contrast, v.TintColor = t[1], t[2], t[3] end end
		end
	end
end

-- ============================ STATS TRACKING ============================
do
	local function hook(name, field) local v = Data and Data:FindFirstChild(name) if not v then return end local prev = v.Value addConn(v.Changed:Connect(function(nv) local d = nv - prev prev = nv if d > 0 then State[field] = State[field] + d end end)) end
	hook("EXP", "gainExp") hook("Credits", "gainCredits") hook("Scraps", "gainScraps")
	local LK = { t = -999 }
	local killed = ReplicatedStorage.Game.Events.Remotes:FindFirstChild("Killed")
	if killed then addConn(killed.OnClientEvent:Connect(function(_, credits) LK.t = os.clock() LK.credits = tonumber(credits) or 0 end)) end
	local hooked = setmetatable({}, { __mode = "k" })
	local function hookNPC(model) if not model:IsA("Model") or hooked[model] then return end local hum = model:FindFirstChildOfClass("Humanoid") if not hum or hum.Health <= 0 then return end hooked[model] = true
		addConn(hum.Died:Connect(function() if os.clock() - LK.t <= 1.6 then local nf = model:FindFirstChild("npc_folder") local r = nf and nf:FindFirstChild("Reward") local reward = r and r.Value
			local ok = (not reward) or (not LK.credits) or LK.credits == 0 or math.abs(LK.credits - reward) <= math.max(8, reward * 0.6)
			if ok then State.perMob[model.Name] = (State.perMob[model.Name] or 0) + 1 LK.t = -999 end end end))
	end
	local npcRoot = workspace:FindFirstChild("NPCs")
	if npcRoot then for _, f in ipairs(npcRoot:GetChildren()) do if f:IsA("Folder") then for _, m in ipairs(f:GetChildren()) do hookNPC(m) end end end
		addConn(npcRoot.DescendantAdded:Connect(function(d) if d:IsA("Humanoid") then task.defer(function() if d.Parent then hookNPC(d.Parent) end end) end end)) end
	local function hookDeath(char) local h = char:FindFirstChildOfClass("Humanoid") if h then addConn(h.Died:Connect(function() State.deaths = State.deaths + 1 end)) end end
	if lp.Character then hookDeath(lp.Character) end
	addConn(lp.CharacterAdded:Connect(function(c) task.wait(0.3) hookDeath(c) if State.godmode then godBind(c) end end))
end

-- ============================ LOOT CATALOG ============================
local Rarity = (pcall(require, ReplicatedStorage.Game.Libraries.Rarity)) and require(ReplicatedStorage.Game.Libraries.Rarity) or { rarityNames = {}, rarityColors = {} }
local function buildLootCatalog()
	local statNames = { "WeaponStats", "MeleeStats", "ConsumableStats", "UtilityStats", "AmmoStats", "ArmorStats", "FlashlightStats" }
	local list = {}
	for _, cat in ipairs(Tools:GetChildren()) do for _, item in ipairs(cat:GetChildren()) do
		local rec = { name = item.Name, category = cat.Name }
		local r = item:FindFirstChild("Rarity") rec.rarity = r and r.Value or 1
		rec.rarityColor = (Rarity.rarityColors and Rarity.rarityColors[rec.rarity]) or Color3.new(1, 1, 1)
		for _, sn in ipairs(statNames) do local m = item:FindFirstChild(sn) if m then local ok, t = pcall(require, m) if ok and type(t) == "table" and t.toolIcon then rec.icon = (string.find(t.toolIcon, "rbxassetid")) and t.toolIcon or ("rbxassetid://" .. t.toolIcon) end break end end
		list[#list + 1] = rec
	end end
	table.sort(list, function(a, b) if a.category ~= b.category then return a.category < b.category end return a.name < b.name end)
	return list
end

-- ============================ ESP ============================
local espFolder
local espCache = {}
local function clearEsp() for k, v in pairs(espCache) do pcall(function() v:Destroy() end) end espCache = {} if espFolder then for _, c in ipairs(espFolder:GetChildren()) do if c.Name ~= "BunkerMarker" then end end end end
local bunkerMarker
local function ensureBunkerMarker()
	if bunkerMarker and bunkerMarker.Parent then return end
	bunkerMarker = new("Part", { Name = "NR_BunkerMarker", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 0.55, Size = Vector3.new(6, 60, 6), Position = BUNKER_ENTRANCE + Vector3.new(0, 28, 0), Color = Color3.fromRGB(59, 240, 160), Material = Enum.Material.Neon }, espFolder)
	local bb = new("BillboardGui", { Adornee = bunkerMarker, Size = UDim2.fromOffset(180, 40), StudsOffset = Vector3.new(0, 32, 0), AlwaysOnTop = true }, bunkerMarker)
	new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "🛡 БУНКЕР (вход)", TextSize = 15, TextColor3 = Color3.fromRGB(59, 240, 160), TextStrokeTransparency = 0.4 }, bb)
end
local function espRefresh()
	if not espFolder then return end
	if State.espBunker then ensureBunkerMarker() elseif bunkerMarker then bunkerMarker:Destroy() bunkerMarker = nil end
	local seen = {}
	local hrp = getHRP()
	local function add(inst, color, label)
		if not inst then return end
		seen[inst] = true
		local h = espCache[inst]
		if not h then
			h = new("Highlight", { Adornee = inst, FillColor = color, OutlineColor = Color3.new(1, 1, 1), FillTransparency = 0.6, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }, espFolder)
			local bb = new("BillboardGui", { Name = "lbl", Adornee = inst, Size = UDim2.fromOffset(150, 18), StudsOffset = Vector3.new(0, 2.5, 0), AlwaysOnTop = true }, h)
			new("TextLabel", { Name = "t", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamSemibold, TextSize = 12, TextColor3 = color, TextStrokeTransparency = 0.5 }, bb)
			espCache[inst] = h
		end
		h.FillColor = color
		local t = h:FindFirstChild("lbl") and h.lbl:FindFirstChildOfClass("TextLabel")
		if t then local dist = (hrp and inst:IsA("BasePart")) and math.floor((inst.Position - hrp.Position).Magnitude) or (hrp and inst:IsA("Model") and inst.PrimaryPart and math.floor((inst.PrimaryPart.Position - hrp.Position).Magnitude)) or nil
			t.Text = label .. (dist and ("  " .. dist .. "m") or "") t.TextColor3 = color end
	end
	if hrp then
		if State.espMobs then local npcs = workspace:FindFirstChild("NPCs") if npcs then for _, fn in ipairs({ "Zombies", "Enemy", "Recon", "Neutrals", "Boss" }) do local f = npcs:FindFirstChild(fn)
			if f then for _, m in ipairs(f:GetChildren()) do local h = m:FindFirstChildOfClass("Humanoid") local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
				if h and r and h.Health > 0 and h.Health < 1e6 and (r.Position - hrp.Position).Magnitude <= State.espDistance then add(m, Color3.fromRGB(255, 77, 94), m.Name .. " [" .. math.floor(h.Health) .. "]") end end end end end end
		if State.espBoxes then local items = itemsFolder() local boxes = items and items:FindFirstChild("Boxes") if boxes then for _, m in ipairs(boxes:GetDescendants()) do if m:IsA("Model") and BOXNAMES[m.Name] and m:FindFirstChild("Body") and not m:FindFirstChild("Destroyed") and (m.Body.Position - hrp.Position).Magnitude <= State.espDistance then add(m, Color3.fromRGB(255, 178, 35), "Ящик") end end end end
		if State.espCrates then local items = itemsFolder() local lc = items and items:FindFirstChild("LockpickCrates") if lc then for _, m in ipairs(lc:GetDescendants()) do if m:IsA("Model") and m:FindFirstChild("PromptAttachment") and not m:FindFirstChild("Destroyed") then local body = m:FindFirstChild("Body") local pos = body and body:IsA("BasePart") and body.Position or m:GetPivot().Position if (pos - hrp.Position).Magnitude <= State.espDistance then add(m, Color3.fromRGB(183, 0, 255), "Сундук") end end end end end
		if State.espLoot then local cache = boxLootCache() if cache then for _, m in ipairs(cache:GetChildren()) do local part = (m:IsA("BasePart") and m) or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
			if part and (part.Position - hrp.Position).Magnitude <= State.espDistance then local pp for _, d in ipairs(m:GetDescendants()) do if d:IsA("ProximityPrompt") then pp = d break end end
				local lbl = pp and pp.ActionText ~= "" and pp.ActionText or "Лут" add(m, Color3.fromRGB(54, 226, 255), lbl) end end end end
		if State.espPlayers then for _, pl in ipairs(Players:GetPlayers()) do if pl ~= lp and pl.Character then local r = pl.Character:FindFirstChild("HumanoidRootPart") if r and (r.Position - hrp.Position).Magnitude <= State.espDistance then add(pl.Character, Color3.fromRGB(255, 255, 255), pl.Name) end end end end
	end
	for inst, h in pairs(espCache) do if not seen[inst] or not inst.Parent then pcall(function() h:Destroy() end) espCache[inst] = nil end end
end

-- ============================ GUI ============================
local C = {
	void = Color3.fromRGB(5, 6, 10), glass = Color3.fromRGB(11, 15, 22), raised = Color3.fromRGB(16, 21, 31), hair = Color3.fromRGB(28, 36, 48),
	amber = Color3.fromRGB(255, 178, 35), cyan = Color3.fromRGB(54, 226, 255), cyanDeep = Color3.fromRGB(10, 143, 176),
	text = Color3.fromRGB(234, 242, 255), sub = Color3.fromRGB(138, 151, 168), muted = Color3.fromRGB(84, 97, 111),
	good = Color3.fromRGB(59, 240, 160), warn = Color3.fromRGB(255, 138, 60), danger = Color3.fromRGB(255, 77, 94),
}
local function corner(i, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, i) end
local function stroke(i, col, th, tr) return new("UIStroke", { Color = col or C.hair, Thickness = th or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, i) end
local function label(parent, text, size, color, font) return new("TextLabel", { BackgroundTransparency = 1, Text = text, TextColor3 = color or C.text, Font = font or Enum.Font.Gotham, TextSize = size or 14, TextXAlignment = Enum.TextXAlignment.Left }, parent) end

local screenGui = new("ScreenGui", { Name = "NULLROOM_" .. tostring(math.random(1000, 9999)), ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true, DisplayOrder = 9999 })
do local mounted = false
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(screenGui) end if gethui then screenGui.Parent = gethui() mounted = true end end)
	if not mounted then pcall(function() screenGui.Parent = game:GetService("CoreGui") mounted = true end) end
	if not mounted then screenGui.Parent = lp:WaitForChild("PlayerGui") end
end
espFolder = new("Folder", { Name = "NR_ESP" }, screenGui)

-- notifications
local toastHolder = new("Frame", { Size = UDim2.new(0, 320, 1, -20), Position = UDim2.new(0.5, -160, 0, 10), BackgroundTransparency = 1, ZIndex = 60 }, screenGui)
new("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)
function notify(text, actionLabel, actionFn)
	local t = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.raised, BackgroundTransparency = 1, ZIndex = 61 }, toastHolder)
	corner(t, 9) local s = stroke(t, C.cyan, 1, 1)
	local pad = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 61 }, t)
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9) }, pad)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pad)
	local msg = label(pad, text, 13, C.text, Enum.Font.GothamMedium) msg.Size = UDim2.new(1, 0, 0, 0) msg.AutomaticSize = Enum.AutomaticSize.Y msg.TextWrapped = true msg.ZIndex = 61
	if actionLabel and actionFn then
		local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.cyanDeep, Text = actionLabel, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 61, BackgroundTransparency = 1 }, pad)
		corner(b, 7)
		b.MouseButton1Click:Connect(function() pcall(actionFn) end)
		TweenService:Create(b, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
	end
	TweenService:Create(t, TweenInfo.new(0.2), { BackgroundTransparency = 0.06 }):Play()
	TweenService:Create(s, TweenInfo.new(0.2), { Transparency = 0.2 }):Play()
	task.delay(actionFn and 6 or 3.5, function() if t and t.Parent then TweenService:Create(t, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play() task.wait(0.26) t:Destroy() end end)
end

local shadow = new("ImageLabel", { Size = UDim2.fromOffset(680, 510), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = "rbxassetid://1316045217", ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.4, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(10, 10, 118, 118) }, screenGui)

local main = new("Frame", { Size = UDim2.fromOffset(648, 470), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.glass, BackgroundTransparency = 0.06, Active = true, ClipsDescendants = true }, screenGui)
corner(main, 14)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(26, 34, 48), C.void), Transparency = NumberSequence.new(0, 0.35) }, main)
stroke(main, C.hair, 1, 0.15)
local edge = stroke(main, Color3.new(1, 1, 1), 1.5, 0)
local edgeGrad = new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.amber), ColorSequenceKeypoint.new(0.5, C.cyan), ColorSequenceKeypoint.new(1, C.amber) }) }, edge)

local header = new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 }, main)
new("Frame", { Size = UDim2.fromOffset(11, 11), Position = UDim2.new(0, 16, 0.5, -6), BackgroundColor3 = C.amber, BorderSizePixel = 0, Rotation = 45 }, header)
label(header, "NULLROOM", 18, C.text, Enum.Font.Michroma).Position = UDim2.new(0, 38, 0, 7)
do local s2 = label(header, "backrooms: survival // автоферма", 11, C.sub, Enum.Font.Code) s2.Position = UDim2.new(0, 38, 0, 27) s2.Size = UDim2.new(0, 320, 0, 13) end
local online = new("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 318, 0, 19), BackgroundColor3 = C.cyan, BorderSizePixel = 0 }, header) corner(online, 4)

local minBtn = new("TextButton", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -62, 0.5, -13), BackgroundColor3 = C.raised, Text = "", AutoButtonColor = true }, header) corner(minBtn, 7)
new("Frame", { Size = UDim2.fromOffset(12, 2), Position = UDim2.new(0.5, -6, 0.5, -1), BackgroundColor3 = C.text, BorderSizePixel = 0 }, minBtn)
local closeBtn = new("TextButton", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -32, 0.5, -13), BackgroundColor3 = Color3.fromRGB(40, 20, 24), Text = "X", TextColor3 = C.danger, Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true }, header) corner(closeBtn, 7)

local sidebar = new("Frame", { Size = UDim2.new(0, 142, 1, -46 - 26), Position = UDim2.new(0, 8, 0, 46), BackgroundColor3 = C.raised, BackgroundTransparency = 0.25 }, main) corner(sidebar, 10) stroke(sidebar, C.hair, 1, 0.3)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, sidebar)

local content = new("Frame", { Size = UDim2.new(1, -142 - 24, 1, -46 - 26), Position = UDim2.new(0, 158, 0, 46), BackgroundTransparency = 1 }, main)
local footer = new("Frame", { Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 1, -24), BackgroundTransparency = 1 }, main)
local footL = label(footer, "статус: ожидание", 11, C.muted, Enum.Font.Code) footL.Size = UDim2.new(0.6, 0, 1, 0)
local footR = label(footer, "ОНЛАЙН", 11, C.cyan, Enum.Font.Code) footR.Size = UDim2.new(0.4, 0, 1, 0) footR.Position = UDim2.new(0.6, 0, 0, 0) footR.TextXAlignment = Enum.TextXAlignment.Right

local tabs, tabButtons = {}, {}
local function showTab(name) for n, fr in pairs(tabs) do fr.Visible = (n == name) end for n, b in pairs(tabButtons) do local on = (n == name) TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = on and 0 or 1 }):Play() b.TextColor3 = on and C.void or C.sub end end
local function makeTab(name)
	local f = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.cyan, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false }, content)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	tabs[name] = f
	local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.amber, BackgroundTransparency = 1, Text = name, TextColor3 = C.sub, Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false }, sidebar) corner(b, 8)
	tabButtons[name] = b b.MouseButton1Click:Connect(function() showTab(name) end)
	return f
end
local function cardOf(parent, titleText)
	local c = new("Frame", { Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.raised, BackgroundTransparency = 0.15 }, parent) corner(c, 8) stroke(c, C.hair, 1, 0.35)
	local hold = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, c)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, hold)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9) }, hold)
	if titleText then local row = new("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1 }, hold) new("Frame", { Size = UDim2.fromOffset(3, 13), Position = UDim2.fromOffset(0, 1), BackgroundColor3 = C.amber, BorderSizePixel = 0 }, row) local l = label(row, string.upper(titleText), 11, C.amber, Enum.Font.GothamBold) l.Position = UDim2.fromOffset(9, 0) l.Size = UDim2.new(1, -9, 1, 0) end
	return hold
end
local function mkToggle(parent, lbl, default, cb)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, parent)
	local tl = label(row, lbl, 13, C.text, Enum.Font.Gotham) tl.Size = UDim2.new(1, -56, 1, 0)
	local pill = new("TextButton", { Size = UDim2.fromOffset(44, 21), Position = UDim2.new(1, -46, 0.5, -10), BackgroundColor3 = C.glass, Text = "", AutoButtonColor = false }, row) corner(pill, 11) local ps = stroke(pill, C.hair, 1, 0)
	local knob = new("Frame", { Size = UDim2.fromOffset(15, 15), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = C.muted }, pill) corner(knob, 8)
	local st = default
	local function apply(anim) local kp = st and UDim2.new(1, -18, 0.5, -7.5) or UDim2.fromOffset(3, 3) local kc = st and C.cyan or C.muted local sc = st and C.cyan or C.hair
		if anim then TweenService:Create(knob, TweenInfo.new(0.16), { Position = kp, BackgroundColor3 = kc }):Play() TweenService:Create(ps, TweenInfo.new(0.16), { Color = sc, Thickness = st and 1.5 or 1 }):Play() else knob.Position = kp knob.BackgroundColor3 = kc ps.Color = sc end end
	apply(false)
	pill.MouseButton1Click:Connect(function() st = not st apply(true) cb(st) end)
	return row
end
local function mkSlider(parent, lbl, minV, maxV, default, decimals, suffix, cb)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, parent)
	label(row, lbl, 13, C.text, Enum.Font.Gotham).Size = UDim2.new(1, -70, 0, 16)
	local valL = label(row, "", 12, C.cyan, Enum.Font.Code) valL.Position = UDim2.new(1, -70, 0, 0) valL.Size = UDim2.new(0, 70, 0, 16) valL.TextXAlignment = Enum.TextXAlignment.Right
	local trk = new("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 28), BackgroundColor3 = C.glass }, row) corner(trk, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.cyan }, trk) corner(fill, 3) new("UIGradient", { Color = ColorSequence.new(C.cyan, C.cyanDeep) }, fill)
	local knob = new("Frame", { Size = UDim2.fromOffset(13, 13), BackgroundColor3 = C.text }, trk) corner(knob, 7)
	local mult = 10 ^ decimals
	local function apply(a) a = math.clamp(a, 0, 1) local v = math.floor((minV + (maxV - minV) * a) * mult + 0.5) / mult local aa = (maxV > minV) and (v - minV) / (maxV - minV) or 0 fill.Size = UDim2.fromScale(aa, 1) knob.Position = UDim2.new(aa, -6, 0.5, -6) valL.Text = tostring(v) .. (suffix or "") cb(v) end
	apply((default - minV) / (maxV - minV))
	local drag = false
	local function fromIn(i) apply((i.Position.X - trk.AbsolutePosition.X) / math.max(trk.AbsoluteSize.X, 1)) end
	trk.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true fromIn(i) end end)
	knob.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true end end)
	addConn(UserInputService.InputChanged:Connect(function(i) if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromIn(i) end end))
	addConn(UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end end))
end
local function mkCycle(parent, lbl, options, di, cb)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, parent)
	label(row, lbl, 13, C.text, Enum.Font.Gotham).Size = UDim2.new(1, -120, 1, 0)
	local btn = new("TextButton", { Size = UDim2.fromOffset(108, 24), Position = UDim2.new(1, -110, 0.5, -12), BackgroundColor3 = C.glass, Text = options[di], TextColor3 = C.amber, Font = Enum.Font.GothamBold, TextSize = 12 }, row) corner(btn, 7) stroke(btn, C.hair, 1, 0.3)
	local idx = di cb(options[idx]) btn.MouseButton1Click:Connect(function() idx = idx % #options + 1 btn.Text = options[idx] cb(options[idx]) end)
end
local function mkButton(parent, text, col, cb)
	local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = col or C.glass, Text = text, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true }, parent) corner(b, 8) stroke(b, C.hair, 1, 0.4) b.MouseButton1Click:Connect(cb) return b
end
local function noteOf(parent, text, col) local l = label(parent, text, 11, col or C.muted, Enum.Font.Gotham) l.Size = UDim2.new(1, 0, 0, 0) l.AutomaticSize = Enum.AutomaticSize.Y l.TextWrapped = true return l end

local farmTab = makeTab("ФАРМ")
local combatTab = makeTab("БОЙ")
local surviveTab = makeTab("ВЫЖИТЬ")
local shopTab = makeTab("МАГАЗИН")
local lootTab = makeTab("ЛУТ")
local espTab = makeTab("ESP")
local statsTab = makeTab("СТАТЫ")
local visualTab = makeTab("ВИЗУАЛ")

do local c = cardOf(farmTab, "Авто-фарм")
	mkToggle(c, "Убивать мобов (опыт+кредиты)", false, function(v) State.autoKill = v end)
	mkToggle(c, "Ломать ящики (лут)", false, function(v) State.autoBoxes = v end)
	mkToggle(c, "Вскрывать сундуки отмычкой", false, function(v) State.autoLockpick = v if v and not hasItem("Lockpick") then notify("Нет отмычки для сундуков", "Купить x1", function() task.spawn(function() buySmart("Lockpick", 1) end) end) end end)
	mkToggle(c, "Собирать лут", false, function(v) State.autoLoot = v end)
	mkToggle(c, "Авто-решение мини-игр", false, function(v) State.autoMinigames = v end)
	local h = cardOf(farmTab, "Лут-хаулер")
	mkToggle(h, "Носить лут в точку старта", false, function(v) State.hauler = v if v then haulStart = nil notify("Хаулер запущен с текущей точки") end end)
	noteOf(h, "Открывает ящики, заполняет инвентарь, возвращается в точку включения и выкидывает всё. Свои дропы не подбирает.", C.sub)
end
do local c = cardOf(combatTab, "Бой")
	mkToggle(c, "Авто лучшее оружие", false, function(v) State.autoBestWeapon = v end)
	mkCycle(c, "Тип удара", { "M1 (лёгкий)", "M2 (тяжёлый)" }, 1, function(v) State.attackType = v:sub(1, 2) end)
	mkToggle(c, "AOE: бить всех рядом", true, function(v) State.aoeMelee = v end)
	mkToggle(c, "Атаковать боссов", false, function(v) State.includeBoss = v end)
	mkSlider(c, "Ударов/сек", 1, 6, 2.2, 1, "", function(v) State.attacksPerSec = v end)
	mkSlider(c, "Радиус поиска", 6, 40, 16, 0, "", function(v) State.searchRadius = v end)
	noteOf(c, "Сервер ограничивает удар ~0.4с на цель. AOE бьёт много целей разом — так реально быстрее.", C.muted)
end
do local c = cardOf(surviveTab, "Бессмертие")
	mkToggle(c, "Режим бога", false, function(v) State.godmode = v if v then godBind(lp.Character) notify("Режим бога: анти-хитбокс активен") else godDisable() end end)
	mkToggle(c, "Бесконечная стамина", false, function(v) State.infStamina = v end)
	noteOf(c, "Режим бога делает части тела невидимыми для попаданий (CanQuery/CanTouch) + сбрасывает Downed. Урон по HP серверный, поэтому держи Авто-хил включённым как страховку.", C.warn)
	local s = cardOf(surviveTab, "Авто-хил и страховка")
	mkToggle(s, "Авто-хил (пить еду)", false, function(v) State.autoHeal = v end)
	mkToggle(s, "Докупать бутылки если кончились", false, function(v) State.autoBuyHeal = v end)
	mkToggle(s, "Hit & Run (отскок между ударами)", false, function(v) State.hitRun = v end)
	mkToggle(s, "Отступать в бункер при HP", false, function(v) State.autoFlee = v end)
	mkSlider(s, "Хилиться при HP %", 10, 95, 55, 0, "%", function(v) State.healPct = v / 100 end)
	mkSlider(s, "Бежать при HP %", 5, 60, 25, 0, "%", function(v) State.fleePct = v / 100 end)
	mkButton(s, "Телепорт в бункер", C.cyanDeep, function() task.spawn(teleportToSafeZone) end)
end
do local c = cardOf(shopTab, "Быстрая покупка")
	mkButton(c, "Купить отмычку", C.cyanDeep, function() task.spawn(function() buySmart("Lockpick", 1) end) end)
	mkButton(c, "Купить еду (Almond Bottle x3)", C.cyanDeep, function() task.spawn(function() buySmart("Almond Bottle", 3) end) end)
	mkButton(c, "Купить Crowbar (ломать ящики)", C.cyanDeep, function() task.spawn(function() buySmart("Crowbar", 1) end) end)
	mkButton(c, "Купить лёгкий жилет (броня)", C.cyanDeep, function() task.spawn(function() buySmart("Light Vest", 1) end) end)
	mkButton(c, "Купить патроны 9мм x3", C.cyanDeep, function() task.spawn(function() buySmart("Handgun Ammo", 3) end) end)
	mkToggle(c, "Авто-докупка (еда+отмычка)", false, function(v) State.autoRestock = v end)
	local w = cardOf(shopTab, "Вес инвентаря")
	mkButton(w, "Апгрейд веса (+1кг)", C.amber, function() task.spawn(function() local ok, why = upgradeWeight() if ok then notify("Апгрейд веса куплен") elseif why == "max" then notify("Вес уже на максимуме (10кг)") end end) end)
	noteOf(w, "Лимит 7кг серверный, обойти НЕЛЬЗЯ. Максимум апгрейда — 10кг (за кредиты). Используй фильтр лута, чтобы не таскать мусор.", C.warn)
end
do local top = cardOf(lootTab, "Правила сбора")
	mkToggle(top, "Собирать монеты", true, function(v) State.collectCurrency = v end)
	mkToggle(top, "Сначала крупные монеты", true, function(v) State.biggestFirst = v end)
	noteOf(top, "Выбери предметы ниже — будут собираться ТОЛЬКО они. Ничего не выбрано = собирать всё.", C.sub)
	local catalog = buildLootCatalog() local cells = {}
	local chips = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, top) new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, chips)
	local function refresh() for _, fn in ipairs(cells) do fn() end end
	new("TextButton", { Size = UDim2.fromOffset(80, 26), BackgroundColor3 = C.glass, Text = "ВСЕ", TextColor3 = C.cyan, Font = Enum.Font.GothamBold, TextSize = 11 }, chips).MouseButton1Click:Connect(function() State.lootFilter = {} for _, r in ipairs(catalog) do State.lootFilter[r.name] = true end refresh() end)
	new("TextButton", { Size = UDim2.fromOffset(80, 26), BackgroundColor3 = C.glass, Text = "СБРОС", TextColor3 = C.sub, Font = Enum.Font.GothamBold, TextSize = 11 }, chips).MouseButton1Click:Connect(function() State.lootFilter = {} refresh() end)
	local gridCard = cardOf(lootTab, "Фильтр предметов")
	local grid = new("ScrollingFrame", { Size = UDim2.new(1, 0, 0, 232), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.cyan, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, gridCard)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(50, 50), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for _, rec in ipairs(catalog) do
		local cell = new("ImageButton", { BackgroundColor3 = C.glass, AutoButtonColor = false, Image = "" }, grid) corner(cell, 8) local cs = stroke(cell, C.hair, 1, 0)
		if rec.icon then new("ImageLabel", { Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.08), BackgroundTransparency = 1, Image = rec.icon, ImageTransparency = 0.35 }, cell)
		else new("TextLabel", { Size = UDim2.fromScale(1, 0.66), Position = UDim2.fromScale(0, 0.05), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = rec.name:sub(1, 3):upper(), TextSize = 14, TextColor3 = rec.rarityColor }, cell) end
		new("TextLabel", { Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.68), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = rec.name, TextSize = 8, TextColor3 = C.sub, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd }, cell)
		local function upd() local sel = State.lootFilter[rec.name] == true cs.Color = sel and C.cyan or C.hair cs.Thickness = sel and 1.6 or 1 cell.BackgroundColor3 = sel and Color3.fromRGB(14, 28, 40) or C.glass end
		cells[#cells + 1] = upd upd()
		cell.MouseButton1Click:Connect(function() State.lootFilter[rec.name] = (not State.lootFilter[rec.name]) or nil upd() end)
	end
end
do local c = cardOf(espTab, "ESP")
	mkToggle(c, "Включить ESP", false, function(v) State.esp = v if not v then clearEsp() if bunkerMarker then bunkerMarker:Destroy() bunkerMarker = nil end end end)
	mkToggle(c, "Мобы (красный + HP)", true, function(v) State.espMobs = v end)
	mkToggle(c, "Лут (циан)", true, function(v) State.espLoot = v end)
	mkToggle(c, "Ящики (янтарь)", true, function(v) State.espBoxes = v end)
	mkToggle(c, "Сундуки (фиолет)", true, function(v) State.espCrates = v end)
	mkToggle(c, "Игроки (белый)", false, function(v) State.espPlayers = v end)
	mkToggle(c, "Бункер (вход)", true, function(v) State.espBunker = v if not v and bunkerMarker then bunkerMarker:Destroy() bunkerMarker = nil end end)
	mkSlider(c, "Дальность ESP", 100, 2000, 600, 0, "", function(v) State.espDistance = v end)
end
local statRefs = {}
do local top = new("Frame", { Size = UDim2.new(1, -4, 0, 76), BackgroundTransparency = 1 }, statsTab) new("UIGridLayout", { CellSize = UDim2.fromOffset(108, 36), CellPadding = UDim2.fromOffset(6, 6) }, top)
	local function counter(name) local cd = new("Frame", { BackgroundColor3 = C.raised, BackgroundTransparency = 0.15 }, top) corner(cd, 8) stroke(cd, C.hair, 1, 0.4)
		label(cd, name, 10, C.sub, Enum.Font.Gotham).Position = UDim2.fromOffset(8, 4) local v = label(cd, "0", 17, C.cyan, Enum.Font.Code) v.Position = UDim2.fromOffset(8, 15) v.Size = UDim2.new(1, -8, 0, 18) return v end
	statRefs.kills = counter("УБИЙСТВА") statRefs.exp = counter("ОПЫТ") statRefs.credits = counter("КРЕДИТЫ") statRefs.cpm = counter("КРЕД/МИН")
	local mc = cardOf(statsTab, "Убийства по типам")
	statRefs.mobHolder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, mc) new("UIListLayout", { Padding = UDim.new(0, 4) }, statRefs.mobHolder) statRefs.mobBars = {}
	local sc = cardOf(statsTab, "Сессия") statRefs.session = label(sc, "", 12, C.text, Enum.Font.Code) statRefs.session.Size = UDim2.new(1, 0, 0, 0) statRefs.session.AutomaticSize = Enum.AutomaticSize.Y
	local gc = cardOf(statsTab, "Состояние")
	local function gauge(name, col) local row = new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, gc) label(row, name, 11, C.sub, Enum.Font.Gotham).Size = UDim2.new(0, 80, 1, 0)
		local trk = new("Frame", { Size = UDim2.new(1, -88, 0, 8), Position = UDim2.new(0, 84, 0.5, -4), BackgroundColor3 = C.glass }, row) corner(trk, 4) local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = col }, trk) corner(fill, 4) return fill end
	statRefs.gHP = gauge("ЗДОРОВЬЕ", C.good) statRefs.gSTM = gauge("СТАМИНА", C.cyan) statRefs.gHunger = gauge("ГОЛОД", C.amber) statRefs.gThirst = gauge("ЖАЖДА", C.cyanDeep)
end
do local c = cardOf(visualTab, "Свет")
	mkToggle(c, "FullBright (убрать тьму)", false, function(v) State.fullBright = v setFullBright(v) end)
	mkSlider(c, "Гамма / яркость", 0.5, 3, 1, 1, "", function(v) State.gamma = v if State.fullBright then applyFullBright() end end)
	local m = cardOf(visualTab, "Перемещение")
	mkCycle(m, "Режим", { "Teleport", "Tween", "Walk" }, 1, function(v) State.moveMode = v end)
	mkToggle(m, "Защита от застревания в стенах", true, function(v) State.noclipSafe = v end)
	mkSlider(m, "Скорость Tween", 60, 400, 240, 0, "", function(v) State.moveSpeed = v end)
	mkSlider(m, "Задержка сбора", 0.2, 1.2, 0.6, 2, "s", function(v) State.lootSettle = v end)
end
showTab("ФАРМ")

-- ============================ TICKERS ============================
local function fmt(n) n = math.floor(n) if n >= 1000000 then return string.format("%.1fM", n / 1e6) elseif n >= 1000 then return string.format("%.1fk", n / 1000) end return tostring(n) end
addConn(RunService.Heartbeat:Connect(function() edgeGrad.Offset = Vector2.new((os.clock() * 0.18) % 1, 0) online.BackgroundTransparency = 0.5 + 0.5 * math.abs(math.sin(os.clock() * 2)) end))
do local acc, espAcc = 0, 0
	addConn(RunService.Heartbeat:Connect(function(dt)
		if State.godmode then local hum = getHum() if hum then if State.godmodeMode == "Full" then if hum.MaxHealth ~= 1e9 then hum.MaxHealth = 1e9 end if hum.Health < 1e9 then hum.Health = 1e9 end else if hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end end local st = hum.Parent and hum.Parent:FindFirstChild("States") if st then local d = st:FindFirstChild("Downed") if d and d.Value then d.Value = false end end end end
		if State.infStamina then local ch = lp.Character local vals = ch and ch:FindFirstChild("Values") local stm = vals and vals:FindFirstChild("STM") if stm then local cap = 100 + 5 * endurance() if stm.Value < cap then stm.Value = cap end end end
		espAcc = espAcc + dt if State.esp and espAcc >= 0.35 then espAcc = 0 pcall(espRefresh) end
		acc = acc + dt if acc < 0.5 then return end acc = 0
		if State.fullBright then applyFullBright() end
		statRefs.kills.Text = tostring(statValue("NPC Kills") - State.startKills)
		statRefs.exp.Text = fmt(State.gainExp) statRefs.credits.Text = fmt(State.gainCredits)
		local mins = math.max((os.clock() - State.startClock) / 60, 0.01) statRefs.cpm.Text = fmt(State.gainCredits / mins)
		statRefs.session.Text = string.format("Ящики  %d\nСундуки %d\nЛут    %d\nСкрап  +%d\nСмерти %d\nВремя  %dм %dс", State.boxesBroken, State.cratesOpened, State.lootGrabbed, State.gainScraps, State.deaths, math.floor(mins), math.floor((os.clock() - State.startClock) % 60))
		local maxK = 1 for _, n in pairs(State.perMob) do if n > maxK then maxK = n end end
		for name, n in pairs(State.perMob) do local bar = statRefs.mobBars[name]
			if not bar then local row = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, statRefs.mobHolder)
				local b = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15 }, row) corner(b, 4) new("UIGradient", { Color = ColorSequence.new(C.amber, C.cyan) }, b)
				label(row, name, 11, C.text, Enum.Font.Gotham).Size = UDim2.new(1, -44, 1, 0) local cnt = label(row, "0", 11, C.cyan, Enum.Font.Code) cnt.Position = UDim2.new(1, -42, 0, 0) cnt.Size = UDim2.fromOffset(40, 24) cnt.TextXAlignment = Enum.TextXAlignment.Right
				bar = { fill = b, cnt = cnt } statRefs.mobBars[name] = bar end
			bar.cnt.Text = tostring(n) TweenService:Create(bar.fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(n / maxK, 1) }):Play() end
		local ch = lp.Character local hum = ch and ch:FindFirstChildOfClass("Humanoid") local vals = ch and ch:FindFirstChild("Values")
		local function setG(g, f) if g then g.Size = UDim2.fromScale(math.clamp(f, 0, 1), 1) end end
		setG(statRefs.gHP, (hum and hum.MaxHealth > 0) and (hum.Health / math.min(hum.MaxHealth, 100)) or 0)
		if vals then local stm = vals:FindFirstChild("STM") setG(statRefs.gSTM, stm and stm.Value / (100 + 5 * endurance()) or 0) local hu = vals:FindFirstChild("Hunger") setG(statRefs.gHunger, hu and hu.Value / 100 or 0) local th = vals:FindFirstChild("Thirst") setG(statRefs.gThirst, th and th.Value / 100 or 0) end
		footL.Text = "статус: " .. string.lower(State.currentAction)
	end))
end

-- ============================ DRAG / MINIMIZE / ANTI-AFK / UNLOAD ============================
do local dragging, dragStart, startPos
	header.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true dragStart = i.Position startPos = main.Position end end)
	header.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end end)
	addConn(UserInputService.InputChanged:Connect(function(i) if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then local d = i.Position - dragStart main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y) shadow.Position = main.Position end end))
end

local orb = new("ImageButton", { Size = UDim2.fromOffset(52, 52), Position = UDim2.new(0, 24, 0, 24), BackgroundColor3 = C.glass, AutoButtonColor = false, Visible = false, Image = "" }, screenGui)
corner(orb, 14) stroke(orb, C.cyan, 1.5, 0.1)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(26, 34, 48), C.void) }, orb)
new("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0.5, -8, 0.5, -8), BackgroundColor3 = C.amber, BorderSizePixel = 0, Rotation = 45 }, orb)
local function setMain(vis) main.Visible = vis shadow.Visible = vis end
minBtn.MouseButton1Click:Connect(function()
	local sc = new("UIScale", { Scale = 1 }, main)
	TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.4 }):Play()
	TweenService:Create(main, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	task.delay(0.2, function() setMain(false) main.BackgroundTransparency = 0.06 sc:Destroy() orb.Visible = true orb.Size = UDim2.fromOffset(0, 0)
		TweenService:Create(orb, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(52, 52) }):Play() end)
end)
orb.MouseButton1Click:Connect(function()
	TweenService:Create(orb, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = UDim2.fromOffset(0, 0) }):Play()
	task.delay(0.18, function() orb.Visible = false setMain(true) local sc = new("UIScale", { Scale = 0.4 }, main) main.BackgroundTransparency = 1
		TweenService:Create(sc, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(main, TweenInfo.new(0.26), { BackgroundTransparency = 0.06 }):Play()
		task.delay(0.28, function() sc:Destroy() end) end)
end)
do local od, ods, ops
	orb.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then od = true ods = i.Position ops = orb.Position end end)
	orb.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then od = false end end)
	addConn(UserInputService.InputChanged:Connect(function(i) if od and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then local d = i.Position - ods orb.Position = UDim2.new(ops.X.Scale, ops.X.Offset + d.X, ops.Y.Scale, ops.Y.Offset + d.Y) end end))
end

addConn(lp.Idled:Connect(function() pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end) end))

local function unload()
	State.running = false
	State.autoKill = false State.autoBoxes = false State.autoLockpick = false State.autoLoot = false State.autoMinigames = false State.autoRestock = false State.autoHeal = false State.autoFlee = false State.hauler = false State.esp = false
	if State.godmode then State.godmode = false godDisable() end
	if State.fullBright then setFullBright(false) end
	clearEsp() if bunkerMarker then pcall(function() bunkerMarker:Destroy() end) end
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end connections = {}
	pcall(function() screenGui:Destroy() end) pcall(function() shadow:Destroy() end)
	if getgenv then getgenv().__BackroomsAF = nil end
end
closeBtn.MouseButton1Click:Connect(unload)
if getgenv then getgenv().__BackroomsAF = unload end

do local sc = new("UIScale", { Scale = 0.93 }, main) main.BackgroundTransparency = 1
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(main, TweenInfo.new(0.3), { BackgroundTransparency = 0.06 }):Play()
	task.delay(0.32, function() sc:Destroy() end)
end
