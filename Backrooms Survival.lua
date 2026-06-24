local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local Lighting = game:GetService("Lighting")

local lp = Players.LocalPlayer
local SAFE_POS = Vector3.new(-882, 6.1, -167)

if getgenv then
	local prev = getgenv().__BackroomsAF
	if type(prev) == "function" then pcall(prev) end
end

local State = {
	running = true,
	autoKill = false, autoBoxes = false, autoLockpick = false, autoLoot = false,
	autoMinigames = false, autoBestWeapon = false, aoeMelee = true, includeBoss = false,
	attackType = "M1", attacksPerSec = 2.2, searchRadius = 16,
	godmode = false, godmodeMode = "Stealth", infStamina = false,
	autoHeal = false, hitRun = false, autoFlee = false, quickRespawn = false,
	healPct = 0.55, fleePct = 0.25, hopHeight = 16,
	autoRestock = false, fullBright = false,
	moveMode = "Teleport", moveSpeed = 220, lootSettle = 0.55,
	collectCurrency = true, biggestFirst = true,
	lootFilter = {},
	currentAction = "Idle",
	startKills = 0, startEXP = 0, startCredits = 0, startScraps = 0,
	gainExp = 0, gainCredits = 0, gainScraps = 0,
	boxesBroken = 0, cratesOpened = 0, lootGrabbed = 0, deaths = 0,
	perMob = {},
	startClock = os.clock(),
	weaponReadyAt = 0,
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
	local s = Data and Data:FindFirstChild("Skills")
	local e = s and s:FindFirstChild("Endurance")
	return e and e.Value or 0
end
State.startKills = statValue("NPC Kills")
State.startEXP = statValue("EXP")
State.startCredits = statValue("Credits")
State.startScraps = statValue("Scraps")

local function hasItem(name)
	if lp.Backpack:FindFirstChild(name) then return true end
	local c = lp.Character
	return c and c:FindFirstChild(name) ~= nil
end
local function foodCount()
	local n = 0
	local function scan(p) if not p then return end for _, t in ipairs(p:GetChildren()) do
		if t:IsA("Tool") and t:FindFirstChild("ConsumableStats") then
			local ok, m = pcall(require, t.ConsumableStats)
			if ok and type(m) == "table" and (m.healPerUse or 0) > 0 then n = n + 1 end
		end
	end end
	scan(lp.Backpack) scan(lp.Character)
	return n
end

local MeleeAssets = ReplicatedStorage.Game.Assets.Tools.Melee
local function bestOwnedWeapon(mode)
	mode = mode or "npc"
	local owned = {}
	local bs = lp.playerFolder:FindFirstChild("BackpackSave")
	if bs then for _, sv in ipairs(bs:GetChildren()) do owned[sv.Name] = true end end
	for _, where in ipairs({ lp.Backpack, lp.Character }) do
		if where then for _, t in ipairs(where:GetChildren()) do if t:IsA("Tool") then owned[t.Name] = true end end end
	end
	local best, bestScore = nil, -1
	for name in pairs(owned) do
		local a = MeleeAssets:FindFirstChild(name)
		local ms = a and a:FindFirstChild("MeleeStats")
		if ms then
			local ok, s = pcall(require, ms)
			if ok and s.damage and s.swingSpeed and not s.isAdminWeapon then
				local sc = (mode == "box") and (s.damage * s.swingSpeed) or (s.damage * (s.npcDamageMultiplier or 1) * s.swingSpeed)
				if sc > bestScore then best, bestScore = name, sc end
			end
		end
	end
	return best
end
local function findMelee()
	local char = lp.Character
	if not char then return nil end
	local function valid(t) return t:IsA("Tool") and t:FindFirstChild("MeleeStats") and t:FindFirstChild("Remotes") and t.Remotes:FindFirstChild("OnHit") end
	local equipped = char:FindFirstChildOfClass("Tool")
	if equipped and valid(equipped) and not State.autoBestWeapon then
		return equipped, equipped.Remotes.OnHit
	end
	local want = State.autoBestWeapon and bestOwnedWeapon("npc") or nil
	local tool
	if want then
		tool = char:FindFirstChild(want) or lp.Backpack:FindFirstChild(want)
		if tool and not valid(tool) then tool = nil end
	end
	if not tool then
		if equipped and valid(equipped) then tool = equipped end
	end
	if not tool then
		for _, t in ipairs(char:GetChildren()) do if valid(t) then tool = t break end end
		if not tool then for _, t in ipairs(lp.Backpack:GetChildren()) do if valid(t) then tool = t break end end end
	end
	if not tool then return nil end
	if tool.Parent ~= char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum:EquipTool(tool) end
		State.weaponReadyAt = os.clock() + 2.0
		task.wait(0.15)
	end
	return tool, tool:FindFirstChild("Remotes") and tool.Remotes:FindFirstChild("OnHit")
end

local God = { conns = {} }
local function godClear() for _, c in ipairs(God.conns) do pcall(function() c:Disconnect() end) end God.conns = {} end
local function godBind(char)
	godClear()
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
	pcall(function() hum.BreakJointsOnDeath = false end)
	if State.godmodeMode == "Full" then pcall(function() hum.MaxHealth = 1e9 hum.Health = 1e9 end) end
	God.conns[#God.conns + 1] = hum.HealthChanged:Connect(function(h)
		if State.godmode and h < hum.MaxHealth then hum.Health = hum.MaxHealth end
	end)
end
local function godDisable()
	godClear()
	local hum = getHum()
	if hum then
		pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
		if hum.MaxHealth ~= 100 then hum.MaxHealth = 100 hum.Health = 100 end
	end
end

local function gotoCFrame(dest, settle)
	local hrp = getHRP()
	if not hrp then return false end
	local mode = State.moveMode
	if mode == "Walk" then
		local hum = getHum()
		if hum then
			local t = 0
			repeat hum:MoveTo(dest.Position) task.wait(0.1) t = t + 0.1 hrp = getHRP()
			until (not State.running) or (not hrp) or (hrp.Position - dest.Position).Magnitude <= 5 or t >= 5
		end
		task.wait(settle or 0.1)
	elseif mode == "Tween" then
		local dist = (hrp.Position - dest.Position).Magnitude
		local dur = math.clamp(dist / math.max(State.moveSpeed, 10), 0.05, 5)
		local tw = TweenService:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = dest })
		local done = false
		tw.Completed:Connect(function() done = true end)
		tw:Play()
		local t = 0
		while State.running and not done and t < 6 do task.wait(0.03) t = t + 0.03 end
		if not done then pcall(function() tw:Cancel() end) end
		task.wait(settle or 0.2)
	else
		pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
		hrp.CFrame = dest
		task.wait(settle or 0.3)
	end
	return true
end
local function teleportToSafeZone()
	local hrp = getHRP()
	if not hrp then return false end
	pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
	hrp.CFrame = CFrame.new(SAFE_POS)
	task.wait(0.5)
	return true
end

local function bestFood()
	local best, bestHeal
	local function consider(t)
		if t:IsA("Tool") and t:FindFirstChild("ConsumableStats") then
			local u = t:FindFirstChild("Stats") and t.Stats:FindFirstChild("Uses")
			if (not u) or u.Value > 0 then
				local ok, m = pcall(require, t.ConsumableStats)
				if ok and type(m) == "table" and (m.healPerUse or 0) > 0 then
					if not bestHeal or m.healPerUse > bestHeal then best, bestHeal = t, m.healPerUse end
				end
			end
		end
	end
	for _, t in ipairs(lp.Backpack:GetChildren()) do consider(t) end
	local c = lp.Character
	if c then for _, t in ipairs(c:GetChildren()) do consider(t) end end
	return best
end
local function healCycle(maxTries, target)
	local char = lp.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	local food = bestFood()
	if not food then return false end
	local prev = char:FindFirstChildOfClass("Tool")
	pcall(function() hum:UnequipTools() end)
	task.wait(0.25)
	food.Parent = char
	task.wait(0.5)
	pcall(function() food.Enabled = true end)
	target = target or 0.9
	for _ = 1, (maxTries or 4) do
		if not State.running then break end
		if (hum.Health / hum.MaxHealth) >= target then break end
		local u = food:FindFirstChild("Stats") and food.Stats:FindFirstChild("Uses")
		if u and u.Value <= 0 then food = bestFood() if not food then break end food.Parent = char task.wait(0.4) end
		pcall(function() food:Activate() end)
		task.wait(1.2)
	end
	pcall(function() hum:UnequipTools() end)
	task.wait(0.1)
	if prev and prev.Parent and prev ~= food then pcall(function() hum:EquipTool(prev) end) end
	State.weaponReadyAt = os.clock() + 2.0
	return true
end

local ENEMY_FOLDERS = { "Zombies", "Enemy", "Recon", "Neutrals" }
local BOXNAMES = { Randomized = true, RaritySpecified = true, RaritySpecifiedFixed = true, RarityFixedCommon = true }
local CUR_TIER = { Card3 = 5, Card2 = 4, Card1 = 3, Card = 2, Coin = 1 }

local function itemsFolder() local g = workspace:FindFirstChild("Game") return g and g:FindFirstChild("Items") end

local function nearestNPC()
	local hrp = getHRP() if not hrp then return nil end
	local npcRoot = workspace:FindFirstChild("NPCs") if not npcRoot then return nil end
	local folders = { "Zombies", "Enemy", "Recon", "Neutrals" }
	if State.includeBoss then folders[#folders + 1] = "Boss" end
	local best, bestHum, bestRoot, bestDist
	for _, fn in ipairs(folders) do
		local folder = npcRoot:FindFirstChild(fn)
		if folder then for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				local h = m:FindFirstChildOfClass("Humanoid")
				local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
				if h and r and h.Health > 0 and h.Health < 1e6 then
					local d = (r.Position - hrp.Position).Magnitude
					if not bestDist or d < bestDist then best, bestHum, bestRoot, bestDist = m, h, r, d end
				end
			end
		end end
	end
	return best, bestHum, bestRoot, bestDist
end
local function nearestBox()
	local hrp = getHRP() if not hrp then return nil end
	local items = itemsFolder() local boxes = items and items:FindFirstChild("Boxes")
	if not boxes then return nil end
	local best, bestDist
	for _, m in ipairs(boxes:GetDescendants()) do
		if m:IsA("Model") and BOXNAMES[m.Name] and m:FindFirstChild("Body") and m.Body:IsA("BasePart")
			and not m:FindFirstChild("Indestructible") and not m:FindFirstChild("Destroyed") then
			local d = (m.Body.Position - hrp.Position).Magnitude
			if not bestDist or d < bestDist then best, bestDist = m, d end
		end
	end
	return best, bestDist
end
local function nearestCrate()
	local hrp = getHRP() if not hrp then return nil end
	local items = itemsFolder() local lc = items and items:FindFirstChild("LockpickCrates")
	if not lc then return nil end
	local best, bestDist, bestPos
	for _, m in ipairs(lc:GetDescendants()) do
		if m:IsA("Model") and m:FindFirstChild("PromptAttachment") and m.PromptAttachment:FindFirstChild("PromptLockpick")
			and not m:FindFirstChild("Destroyed") and not m:FindFirstChild("Contraband") then
			local body = m:FindFirstChild("Body")
			local pos = (body and body:IsA("BasePart") and body.Position) or m:GetPivot().Position
			local d = (pos - hrp.Position).Magnitude
			if not bestDist or d < bestDist then best, bestDist, bestPos = m, d, pos end
		end
	end
	return best, bestDist, bestPos
end

local function lootEligible(model, prompt)
	local tier = CUR_TIER[model.Name]
	if tier then return State.collectCurrency, tier end
	local nm = prompt.ActionText
	if next(State.lootFilter) == nil then return true, 0 end
	return State.lootFilter[nm] == true, 0
end
local function nearestLoot()
	local hrp = getHRP() if not hrp then return nil end
	local items = itemsFolder() local cache = items and items:FindFirstChild("Cache")
	if not cache then return nil end
	local best, bestScore
	for _, m in ipairs(cache:GetChildren()) do
		local prompt
		for _, d in ipairs(m:GetDescendants()) do if d:IsA("ProximityPrompt") and d.Enabled then prompt = d break end end
		if prompt then
			local ok, tier = lootEligible(m, prompt)
			if ok then
				local part = (m:IsA("BasePart") and m) or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				if part then
					local dist = (part.Position - hrp.Position).Magnitude
					local score = State.biggestFirst and (tier * 100000 - dist) or (-dist)
					if not bestScore or score > bestScore then best, bestScore = { model = m, prompt = prompt, part = part, dist = dist }, score end
				end
			end
		end
	end
	return best
end

local function doCollect(loot)
	State.currentAction = "Looting " .. (loot.prompt.ActionText ~= "" and loot.prompt.ActionText or loot.model.Name)
	gotoCFrame(CFrame.new(loot.part.Position + Vector3.new(0, 3, 0)), State.lootSettle)
	for _ = 1, 3 do
		if not loot.model.Parent then break end
		pcall(function() fireproximityprompt(loot.prompt) end)
		task.wait(0.22)
	end
	if not loot.model.Parent then State.lootGrabbed = State.lootGrabbed + 1 end
end
local function collectNearby(radius)
	if not State.autoLoot then return end
	local hrp = getHRP() if not hrp then return end
	for _ = 1, 10 do
		local l = nearestLoot()
		if not l or l.dist > radius then break end
		doCollect(l)
	end
end

local lastHit = setmetatable({}, { __mode = "k" })
local function aoeMeleeBurst()
	if os.clock() < State.weaponReadyAt then task.wait(0.1) return end
	local tool, onhit = findMelee()
	if not (tool and onhit) then return end
	local hrp = getHRP() if not hrp then return end
	local interval = 1 / math.clamp(State.attacksPerSec, 0.5, 8)
	local mode = State.attackType
	local radius = State.searchRadius
	local now = os.clock()
	local count = 0
	local npcRoot = workspace:FindFirstChild("NPCs")
	if State.autoKill and npcRoot then
		local folders = { "Zombies", "Enemy", "Recon", "Neutrals" }
		if State.includeBoss then folders[#folders + 1] = "Boss" end
		for _, fn in ipairs(folders) do
			local f = npcRoot:FindFirstChild(fn)
			if f then for _, m in ipairs(f:GetChildren()) do
				local h = m:FindFirstChildOfClass("Humanoid")
				local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
				if h and r and h.Health > 0 and h.Health < 1e6 and (r.Position - hrp.Position).Magnitude <= radius then
					if (now - (lastHit[h] or 0)) >= interval then
						pcall(function() onhit:FireServer(h, mode) end)
						lastHit[h] = now count = count + 1
						if not State.aoeMelee then break end
					end
				end
			end end
			if count > 0 and not State.aoeMelee then break end
		end
	end
	local items = itemsFolder()
	local boxes = items and items:FindFirstChild("Boxes")
	if State.autoBoxes and boxes then
		for _, m in ipairs(boxes:GetDescendants()) do
			if m:IsA("Model") and BOXNAMES[m.Name] and m:FindFirstChild("Body") and m.Body:IsA("BasePart")
				and not m:FindFirstChild("Indestructible") and not m:FindFirstChild("Destroyed")
				and (m.Body.Position - hrp.Position).Magnitude <= radius then
				if (now - (lastHit[m] or 0)) >= interval then
					pcall(function() onhit:FireServer(nil, mode, m) end)
					lastHit[m] = now
				end
			end
		end
	end
	task.wait(0.12)
end

local function doLockpick(crate, pos)
	if not hasItem("Lockpick") then return "need_lockpick" end
	local prompt = crate.PromptAttachment and crate.PromptAttachment:FindFirstChild("PromptLockpick")
	if not prompt then return end
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	State.currentAction = "Lockpicking " .. crate.Name
	gotoCFrame(CFrame.new(pos + Vector3.new(0, 0, 3)), 0.7)
	pcall(function() fireproximityprompt(prompt) end)
	local gui
	for _ = 1, 30 do
		gui = pg:FindFirstChild("Lockpicking")
		if gui and gui:FindFirstChild("FinishEvent") and gui:FindFirstChild("BodyPart") and gui.BodyPart.Value then break end
		task.wait(0.1)
	end
	if not (gui and gui:FindFirstChild("FinishEvent")) then
		local hrp = getHRP() if hrp then hrp.Anchored = false end
		return "no_gui"
	end
	task.wait(0.35)
	pcall(function() gui.FinishEvent:FireServer(gui.BodyPart.Value) end)
	task.wait(0.3)
	pcall(function() gui.CloseEvent:FireServer() end)
	pcall(function() gui.Enabled = false end)
	task.wait(0.2)
	local hrp = getHRP() if hrp then hrp.Anchored = false end
	pcall(function() gui:Destroy() end)
	if crate:FindFirstChild("Destroyed") then State.cratesOpened = State.cratesOpened + 1 end
	collectNearby(40)
end

task.spawn(function()
	while State.running do
		local hrp = getHRP()
		if not hrp then State.currentAction = "Waiting respawn" task.wait(0.5) continue end

		if not State.godmode then
			local pct = hpPct()
			if pct then
				if pct < State.fleePct then
					if State.autoFlee then
						State.currentAction = "Fleeing to bunker"
						teleportToSafeZone()
						local hum = getHum()
						local t = 0
						while State.running and hum and hum.Parent and (hum.Health / hum.MaxHealth) < 0.92 and t < 16 do
							if not healCycle(6, 0.95) then break end
							t = t + 2
						end
						continue
					elseif State.autoHeal and bestFood() then
						State.currentAction = "Healing" healCycle(4, 0.9) continue
					elseif State.quickRespawn then
						local hum = getHum()
						if hum then State.currentAction = "Quick respawn" hum.Health = 0 pcall(function() hum:ChangeState(Enum.HumanoidStateType.Dead) end) end
						task.wait(1) continue
					end
				elseif pct < State.healPct and State.autoHeal and bestFood() then
					State.currentAction = "Healing" healCycle(4, 0.9) continue
				end
			end
		end

		local candidates = {}
		if State.autoLoot then local l = nearestLoot() if l then candidates[#candidates + 1] = { kind = "loot", dist = l.dist, prio = 0, loot = l } end end
		if State.autoKill then local n, h, r, d = nearestNPC() if n then candidates[#candidates + 1] = { kind = "kill", dist = d, prio = 1, npc = n, hum = h, root = r } end end
		if State.autoBoxes then local b, d = nearestBox() if b then candidates[#candidates + 1] = { kind = "box", dist = d, prio = 2, box = b } end end
		if State.autoLockpick and hasItem("Lockpick") then local c, d, p = nearestCrate() if c then candidates[#candidates + 1] = { kind = "crate", dist = d, prio = 3, crate = c, pos = p } end end

		if #candidates > 0 then
			table.sort(candidates, function(a, b) if math.abs(a.dist - b.dist) < 8 then return a.prio < b.prio end return a.dist < b.dist end)
			local c = candidates[1]
			if c.kind == "loot" then
				doCollect(c.loot)
			elseif c.kind == "kill" then
				State.currentAction = "Killing " .. c.npc.Name
				local dir = (hrp.Position - c.root.Position)
				dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, 1)
				gotoCFrame(CFrame.new(c.root.Position + dir * 3, c.root.Position), 0.12)
				local guard = 0
				while State.running and State.autoKill and c.npc.Parent and c.hum.Health > 0 and guard < 30 do
					aoeMeleeBurst()
					if State.hitRun and not State.godmode then
						local hh = getHRP()
						if hh and c.root.Parent then
							pcall(function() hh.AssemblyLinearVelocity = Vector3.zero end)
							hh.CFrame = CFrame.new(c.root.Position + dir * 3 + Vector3.new(0, State.hopHeight, 0))
							task.wait(0.1)
							hh.CFrame = CFrame.new(c.root.Position + dir * 3, c.root.Position)
						end
					end
					guard = guard + 1
				end
				collectNearby(40)
			elseif c.kind == "box" then
				State.currentAction = "Breaking " .. c.box.Name
				gotoCFrame(CFrame.new(c.box.Body.Position + Vector3.new(0, 0, 3)), 0.3)
				local guard = 0
				while State.running and State.autoBoxes and c.box.Parent and not c.box:FindFirstChild("Destroyed") and guard < 20 do
					aoeMeleeBurst()
					guard = guard + 1
				end
				if not c.box.Parent or c.box:FindFirstChild("Destroyed") then State.boxesBroken = State.boxesBroken + 1 end
				collectNearby(45)
			elseif c.kind == "crate" then
				doLockpick(c.crate, c.pos)
			end
		else
			State.currentAction = "Idle (searching)" task.wait(0.3)
		end
	end
end)

task.spawn(function()
	while State.running do
		if State.autoMinigames then
			local pg = lp:FindFirstChild("PlayerGui")
			if pg then
				local lock = pg:FindFirstChild("Lockpicking")
				local swipe = pg:FindFirstChild("SwipeCard")
				if lock and lock:FindFirstChild("FinishEvent") then
					task.wait(0.8)
					if lock.Parent then
						local bp = lock:FindFirstChild("BodyPart")
						pcall(function() lock.FinishEvent:FireServer(bp and bp.Value) end)
						local ce = lock:FindFirstChild("CloseEvent") if ce then pcall(function() ce:FireServer() end) end
						local hrp = getHRP() if hrp then hrp.Anchored = false end
					end
				elseif swipe and swipe:FindFirstChild("Finished") then
					task.wait(0.8)
					if swipe.Parent then
						pcall(function() swipe.Finished:FireServer() end)
						local ce = swipe:FindFirstChild("CloseEvent") if ce then pcall(function() ce:FireServer() end) end
					end
				end
			end
		end
		task.wait(0.4)
	end
end)

local function shopRemote()
	local ok, r = pcall(function() return require(ReplicatedStorage.Game.Helpers.EventAccess):GetAllEventInClass("Remotes").ShopProcess end)
	if ok and r then return r end
	local g = ReplicatedStorage:FindFirstChild("Game")
	local ev = g and g:FindFirstChild("Events")
	local rem = ev and ev:FindFirstChild("Remotes")
	return rem and rem:FindFirstChild("ShopProcess")
end
local function merchantWith(item)
	local g = workspace:FindFirstChild("Game")
	local Shop = g and g:FindFirstChild("Shop")
	if not Shop then return nil end
	for _, m in ipairs(Shop:GetChildren()) do
		if m:IsA("Folder") then
			for _, cat in ipairs(m:GetChildren()) do
				if cat:IsA("Folder") then
					local nv = cat:FindFirstChild(item)
					if nv and nv:IsA("NumberValue") and nv.Value >= 1 then return m.Name end
				end
			end
		end
	end
	return nil
end
local function buySmart(item, qty)
	local sp = shopRemote() if not sp then return 0 end
	local n = 0
	for _ = 1, (qty or 1) do
		if not State.running then break end
		local m = merchantWith(item) if not m then break end
		pcall(function() sp:FireServer(m, item) end)
		n = n + 1
		task.wait(0.35)
	end
	return n
end
local function upgradeWeight()
	local cap = statValue("Max Backpack Inventory")
	if cap >= 10 then return false, "max" end
	pcall(function() require(ReplicatedStorage.Game.Helpers.EventAccess):GetAllEventInClass("Remotes").UpgradeWeight:FireServer("INVENTORY") end)
	return true
end
task.spawn(function()
	while State.running do
		if State.autoRestock then
			if State.autoLockpick and not hasItem("Lockpick") then buySmart("Lockpick", 1) end
			if foodCount() < 2 then buySmart("Almond Bottle", 2 - foodCount()) end
		end
		task.wait(8)
	end
end)

local fbSaved
local function applyFullBright()
	Lighting.Brightness = 2 Lighting.ClockTime = 14 Lighting.FogEnd = 1e9 Lighting.FogStart = 1e9
	Lighting.Ambient = Color3.fromRGB(178, 178, 178) Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
	Lighting.GlobalShadows = false Lighting.ExposureCompensation = 0
	for _, v in ipairs(Lighting:GetChildren()) do
		if v:IsA("Atmosphere") then v.Density = 0 end
		if v:IsA("ColorCorrectionEffect") then v.Brightness = 0 v.Contrast = 0 v.TintColor = Color3.new(1, 1, 1) end
		if v:IsA("BlurEffect") then v.Size = 0 end
	end
end
local function setFullBright(on)
	if on then
		if not fbSaved then
			fbSaved = { Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
				Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, GlobalShadows = Lighting.GlobalShadows,
				ExposureCompensation = Lighting.ExposureCompensation, atmos = {}, cc = {} }
			for _, v in ipairs(Lighting:GetChildren()) do
				if v:IsA("Atmosphere") then fbSaved.atmos[v] = v.Density end
				if v:IsA("ColorCorrectionEffect") then fbSaved.cc[v] = { v.Brightness, v.Contrast, v.TintColor } end
			end
		end
		applyFullBright()
	else
		if fbSaved then
			Lighting.Brightness = fbSaved.Brightness Lighting.ClockTime = fbSaved.ClockTime
			Lighting.FogEnd = fbSaved.FogEnd Lighting.FogStart = fbSaved.FogStart
			Lighting.Ambient = fbSaved.Ambient Lighting.OutdoorAmbient = fbSaved.OutdoorAmbient
			Lighting.GlobalShadows = fbSaved.GlobalShadows Lighting.ExposureCompensation = fbSaved.ExposureCompensation
			for v, d in pairs(fbSaved.atmos) do if v and v.Parent then v.Density = d end end
			for v, t in pairs(fbSaved.cc) do if v and v.Parent then v.Brightness, v.Contrast, v.TintColor = t[1], t[2], t[3] end end
		end
	end
end

do
	local function hook(name, field)
		local v = Data and Data:FindFirstChild(name) if not v then return end
		local prev = v.Value
		addConn(v.Changed:Connect(function(nv) local d = nv - prev prev = nv if d > 0 then State[field] = State[field] + d end end))
	end
	hook("EXP", "gainExp") hook("Credits", "gainCredits") hook("Scraps", "gainScraps")
	local LK = { t = -999 }
	local killed = ReplicatedStorage.Game.Events.Remotes:FindFirstChild("Killed")
	if killed then addConn(killed.OnClientEvent:Connect(function(_, credits) LK.t = os.clock() LK.credits = tonumber(credits) or 0 end)) end
	local function mobInfo(model)
		local nf = model:FindFirstChild("npc_folder")
		local r = nf and nf:FindFirstChild("Reward")
		return model.Name, r and r.Value or nil
	end
	local hooked = setmetatable({}, { __mode = "k" })
	local function hookNPC(model)
		if not model:IsA("Model") or hooked[model] then return end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		hooked[model] = true
		addConn(hum.Died:Connect(function()
			if os.clock() - LK.t <= 1.6 then
				local name, reward = mobInfo(model)
				local ok = (not reward) or (not LK.credits) or LK.credits == 0 or math.abs(LK.credits - reward) <= math.max(8, reward * 0.6)
				if ok then State.perMob[name] = (State.perMob[name] or 0) + 1 LK.t = -999 end
			end
		end))
	end
	local npcRoot = workspace:FindFirstChild("NPCs")
	if npcRoot then
		for _, f in ipairs(npcRoot:GetChildren()) do if f:IsA("Folder") then for _, m in ipairs(f:GetChildren()) do hookNPC(m) end end end
		addConn(npcRoot.DescendantAdded:Connect(function(d) if d:IsA("Humanoid") then task.defer(function() if d.Parent then hookNPC(d.Parent) end end) end end))
	end
	local function hookDeath(char) local h = char:FindFirstChildOfClass("Humanoid") if h then addConn(h.Died:Connect(function() State.deaths = State.deaths + 1 end)) end end
	if lp.Character then hookDeath(lp.Character) end
	addConn(lp.CharacterAdded:Connect(function(c) task.wait(0.3) hookDeath(c) if State.godmode then godBind(c) end end))
end

local Rarity = pcall(require, ReplicatedStorage.Game.Libraries.Rarity) and require(ReplicatedStorage.Game.Libraries.Rarity) or { rarityNames = {}, rarityColors = {} }
local function buildLootCatalog()
	local Tools = ReplicatedStorage.Game.Assets.Tools
	local statNames = { "WeaponStats", "MeleeStats", "ConsumableStats", "UtilityStats", "AmmoStats", "ArmorStats", "FlashlightStats" }
	local list = {}
	for _, cat in ipairs(Tools:GetChildren()) do
		for _, item in ipairs(cat:GetChildren()) do
			local rec = { name = item.Name, category = cat.Name }
			local r = item:FindFirstChild("Rarity") rec.rarity = r and r.Value or 1
			rec.rarityColor = Rarity.rarityColors and Rarity.rarityColors[rec.rarity] or Color3.new(1, 1, 1)
			for _, sn in ipairs(statNames) do
				local m = item:FindFirstChild(sn)
				if m then
					local ok, t = pcall(require, m)
					if ok and type(t) == "table" then
						if t.toolIcon then rec.icon = (string.find(t.toolIcon, "rbxassetid")) and t.toolIcon or ("rbxassetid://" .. t.toolIcon) end
						rec.cost = t.weaponCost
					end
					break
				end
			end
			list[#list + 1] = rec
		end
	end
	table.sort(list, function(a, b) if a.category ~= b.category then return a.category < b.category end return a.name < b.name end)
	return list
end

-- ============================ GUI ============================
local C = {
	void = Color3.fromRGB(5, 6, 10), glass = Color3.fromRGB(11, 15, 22), raised = Color3.fromRGB(16, 21, 31),
	hair = Color3.fromRGB(28, 36, 48), amber = Color3.fromRGB(255, 178, 35), amberHot = Color3.fromRGB(255, 211, 107),
	cyan = Color3.fromRGB(54, 226, 255), cyanDeep = Color3.fromRGB(10, 143, 176),
	text = Color3.fromRGB(234, 242, 255), sub = Color3.fromRGB(138, 151, 168), muted = Color3.fromRGB(84, 97, 111),
	good = Color3.fromRGB(59, 240, 160), warn = Color3.fromRGB(255, 138, 60), danger = Color3.fromRGB(255, 77, 94),
}
local function corner(i, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, i) end
local function stroke(i, col, th, tr) return new("UIStroke", { Color = col or C.hair, Thickness = th or 1, Transparency = tr or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, i) end
local function pad(i, p) new("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }, i) end

local screenGui = new("ScreenGui", { Name = "NULLROOM_" .. tostring(math.random(1000, 9999)), ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true, DisplayOrder = 9999 })
do
	local mounted = false
	pcall(function() if syn and syn.protect_gui then syn.protect_gui(screenGui) end if gethui then screenGui.Parent = gethui() mounted = true end end)
	if not mounted then pcall(function() screenGui.Parent = game:GetService("CoreGui") mounted = true end) end
	if not mounted then screenGui.Parent = lp:WaitForChild("PlayerGui") end
end

local shadow = new("ImageLabel", { Size = UDim2.fromOffset(680, 500), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1, Image = "rbxassetid://1316045217", ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.35,
	ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(10, 10, 118, 118) }, screenGui)

local main = new("Frame", { Size = UDim2.fromOffset(642, 462), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = C.glass, BackgroundTransparency = 0.06, Active = true, ClipsDescendants = true }, screenGui)
corner(main, 14)
do
	local g = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(26, 34, 48), C.void), Transparency = NumberSequence.new(0, 0.35) }, main)
end
stroke(main, C.hair, 1, 0.15)
local edge = stroke(main, Color3.new(1, 1, 1), 1.5, 0)
local edgeGrad = new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.amber), ColorSequenceKeypoint.new(0.5, C.cyan), ColorSequenceKeypoint.new(1, C.amber) }) }, edge)
addConn(RunService.Heartbeat:Connect(function() edgeGrad.Offset = Vector2.new((os.clock() * 0.18) % 1, 0) end)) ; shadow.Position = main.Position

local scan = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "rbxassetid://6644618143",
	ImageTransparency = 0.94, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(4, 4), ZIndex = 50, Active = false }, main)

local header = new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 }, main)
new("Frame", { Size = UDim2.fromOffset(11, 11), Position = UDim2.new(0, 16, 0.5, -6), BackgroundColor3 = C.amber, BorderSizePixel = 0, Rotation = 45 }, header)
local title = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 38, 0, 7), Size = UDim2.new(0, 280, 0, 20),
	Font = Enum.Font.Michroma, Text = "NULLROOM", TextSize = 18, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, header)
new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 38, 0, 26), Size = UDim2.new(0, 280, 0, 13),
	Font = Enum.Font.Code, Text = "backrooms.survival // autofarm", TextSize = 11, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left }, header)
local online = new("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 318, 0, 19), BackgroundColor3 = C.cyan, BorderSizePixel = 0 }, header)
corner(online, 4)
addConn(RunService.Heartbeat:Connect(function() online.BackgroundTransparency = 0.5 + 0.5 * math.abs(math.sin(os.clock() * 2)) end))

local minBtn = new("TextButton", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -62, 0.5, -13), BackgroundColor3 = C.raised, Text = "—", TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = true }, header)
corner(minBtn, 7)
local closeBtn = new("TextButton", { Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -32, 0.5, -13), BackgroundColor3 = Color3.fromRGB(40, 20, 24), Text = "✕", TextColor3 = C.danger, Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true }, header)
corner(closeBtn, 7)

local sidebar = new("Frame", { Size = UDim2.new(0, 140, 1, -46 - 26), Position = UDim2.new(0, 8, 0, 46), BackgroundColor3 = C.raised, BackgroundTransparency = 0.25 }, main)
corner(sidebar, 10) stroke(sidebar, C.hair, 1, 0.3)
local sideList = new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, sidebar)

local content = new("Frame", { Size = UDim2.new(1, -140 - 24, 1, -46 - 26), Position = UDim2.new(0, 156, 0, 46), BackgroundTransparency = 1 }, main)

local footer = new("Frame", { Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 1, -24), BackgroundTransparency = 1 }, main)
local footL = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0.6, 0, 1, 0), Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left, Text = "scan: idle" }, footer)
local footR = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.new(0.6, 0, 0, 0), Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.cyan, TextXAlignment = Enum.TextXAlignment.Right, Text = "ONLINE" }, footer)

local tabs, tabButtons = {}, {}
local function showTab(name)
	for n, fr in pairs(tabs) do fr.Visible = (n == name) end
	for n, b in pairs(tabButtons) do
		local on = (n == name)
		TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = on and 0 or 1 }):Play()
		b.TextColor3 = on and C.void or C.sub
	end
end
local function makeTab(name)
	local f = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.cyan, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false }, content)
	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	tabs[name] = f
	local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.amber, BackgroundTransparency = 1, Text = name, TextColor3 = C.sub, Font = Enum.Font.Michroma, TextSize = 12, AutoButtonColor = false }, sidebar)
	corner(b, 8)
	tabButtons[name] = b
	b.MouseButton1Click:Connect(function() showTab(name) end)
	return f
end

local function card(parent, titleText)
	local c = new("Frame", { Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.raised, BackgroundTransparency = 0.15 }, parent)
	corner(c, 8) stroke(c, C.hair, 1, 0.35)
	local hold = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, c)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, hold)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9) }, hold)
	if titleText then
		new("TextLabel", { Size = UDim2.new(1, 0, 0, 15), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = "▸ " .. string.upper(titleText), TextSize = 11, TextColor3 = C.amber, TextXAlignment = Enum.TextXAlignment.Left }, hold)
	end
	return hold
end

local function makeToggle(parent, label, default, cb)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, parent)
	new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, -56, 1, 0), Font = Enum.Font.Gotham, Text = label, TextSize = 13, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, row)
	local pill = new("TextButton", { Size = UDim2.fromOffset(44, 21), Position = UDim2.new(1, -46, 0.5, -10), BackgroundColor3 = C.glass, Text = "", AutoButtonColor = false }, row)
	corner(pill, 11) local ps = stroke(pill, C.hair, 1, 0)
	local knob = new("Frame", { Size = UDim2.fromOffset(15, 15), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = C.muted }, pill)
	corner(knob, 8)
	local st = default
	local function apply(anim)
		local kp = st and UDim2.new(1, -18, 0.5, -7.5) or UDim2.fromOffset(3, 3)
		local kc = st and C.cyan or C.muted
		local sc = st and C.cyan or C.hair
		if anim then
			TweenService:Create(knob, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Position = kp, BackgroundColor3 = kc }):Play()
			TweenService:Create(ps, TweenInfo.new(0.16), { Color = sc, Thickness = st and 1.5 or 1 }):Play()
		else knob.Position = kp knob.BackgroundColor3 = kc ps.Color = sc end
	end
	apply(false)
	pill.MouseButton1Click:Connect(function() st = not st apply(true) cb(st) end)
	return row
end

local function makeSlider(parent, label, minV, maxV, default, decimals, suffix, cb)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, parent)
	new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -70, 0, 16), Font = Enum.Font.Gotham, Text = label, TextSize = 13, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, row)
	local valL = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(1, -70, 0, 0), Size = UDim2.new(0, 70, 0, 16), Font = Enum.Font.Code, TextSize = 12, TextColor3 = C.cyan, TextXAlignment = Enum.TextXAlignment.Right }, row)
	local trk = new("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 28), BackgroundColor3 = C.glass }, row)
	corner(trk, 3)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.cyan }, trk) corner(fill, 3)
	new("UIGradient", { Color = ColorSequence.new(C.cyan, C.cyanDeep) }, fill)
	local knob = new("Frame", { Size = UDim2.fromOffset(13, 13), BackgroundColor3 = C.text }, trk) corner(knob, 7)
	local mult = 10 ^ decimals
	local function apply(a)
		a = math.clamp(a, 0, 1)
		local v = math.floor((minV + (maxV - minV) * a) * mult + 0.5) / mult
		local aa = (maxV > minV) and (v - minV) / (maxV - minV) or 0
		fill.Size = UDim2.fromScale(aa, 1) knob.Position = UDim2.new(aa, -6, 0.5, -6)
		valL.Text = tostring(v) .. (suffix or "") cb(v)
	end
	apply((default - minV) / (maxV - minV))
	local drag = false
	local function fromIn(i) apply((i.Position.X - trk.AbsolutePosition.X) / math.max(trk.AbsoluteSize.X, 1)) end
	trk.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true fromIn(i) end end)
	knob.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true end end)
	addConn(UserInputService.InputChanged:Connect(function(i) if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromIn(i) end end))
	addConn(UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end end))
end

local function makeCycle(parent, label, options, defaultIndex, cb)
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, parent)
	new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -120, 1, 0), Font = Enum.Font.Gotham, Text = label, TextSize = 13, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, row)
	local btn = new("TextButton", { Size = UDim2.fromOffset(108, 24), Position = UDim2.new(1, -110, 0.5, -12), BackgroundColor3 = C.glass, Text = options[defaultIndex], TextColor3 = C.amber, Font = Enum.Font.GothamBold, TextSize = 12 }, row)
	corner(btn, 7) stroke(btn, C.hair, 1, 0.3)
	local idx = defaultIndex cb(options[idx])
	btn.MouseButton1Click:Connect(function() idx = idx % #options + 1 btn.Text = options[idx] cb(options[idx]) end)
end

local function makeButton(parent, text, col, cb)
	local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = col or C.glass, Text = text, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = true }, parent)
	corner(b, 8) stroke(b, C.hair, 1, 0.4)
	b.MouseButton1Click:Connect(cb)
	return b
end
local function note(parent, text, col)
	new("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = text, TextSize = 11, TextColor3 = col or C.muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left }, parent)
end

-- ===== Tabs =====
local farmTab = makeTab("FARM")
local combatTab = makeTab("COMBAT")
local surviveTab = makeTab("SURVIVE")
local shopTab = makeTab("SHOP")
local lootTab = makeTab("LOOT")
local statsTab = makeTab("STATS")
local visualTab = makeTab("VISUAL")

do
	local c = card(farmTab, "Auto Farm")
	makeToggle(c, "Auto Kill (EXP + Credits)", false, function(v) State.autoKill = v end)
	makeToggle(c, "Break Boxes (loot)", false, function(v) State.autoBoxes = v end)
	makeToggle(c, "Lockpick Crates", false, function(v) State.autoLockpick = v end)
	makeToggle(c, "Auto Loot (collect drops)", false, function(v) State.autoLoot = v end)
	makeToggle(c, "Auto-Solve Minigames", false, function(v) State.autoMinigames = v end)
	makeToggle(c, "Auto Best Weapon", false, function(v) State.autoBestWeapon = v end)
end

do
	local c = card(combatTab, "Combat")
	makeCycle(c, "Attack Type", { "M1", "M2" }, 1, function(v) State.attackType = v end)
	makeToggle(c, "AOE Melee (hit all nearby)", true, function(v) State.aoeMelee = v end)
	makeToggle(c, "Target Bosses Too", false, function(v) State.includeBoss = v end)
	makeSlider(c, "Attacks / sec", 1, 6, 2.2, 1, "", function(v) State.attacksPerSec = v end)
	makeSlider(c, "Search Radius", 6, 40, 16, 0, "", function(v) State.searchRadius = v end)
	note(c, "Server caps melee at ~0.4s per target — AOE hits many targets at once for real speed.", C.muted)
end

do
	local c = card(surviveTab, "Immortality")
	makeToggle(c, "God Mode", false, function(v)
		State.godmode = v
		if v then godBind(lp.Character) else godDisable() end
	end)
	makeCycle(c, "God Mode Type", { "Stealth", "Full" }, 1, function(v)
		State.godmodeMode = v
		if State.godmode then if v == "Stealth" then local h = getHum() if h and h.MaxHealth ~= 100 then h.MaxHealth = 100 h.Health = 100 end end godBind(lp.Character) end
	end)
	makeToggle(c, "Infinite Stamina", false, function(v) State.infStamina = v end)
	note(c, "Stealth = keeps MaxHP 100, instant heal (quiet). Full = MaxHP 1e9, unkillable but louder vs anticheat.", C.muted)
	local s = card(surviveTab, "Fallback (no God Mode)")
	makeToggle(s, "Auto-Heal (use food)", false, function(v) State.autoHeal = v end)
	makeToggle(s, "Hit & Run", false, function(v) State.hitRun = v end)
	makeToggle(s, "Auto-Flee to Bunker", false, function(v) State.autoFlee = v end)
	makeToggle(s, "Quick Respawn when doomed", false, function(v) State.quickRespawn = v end)
	makeSlider(s, "Heal at HP %", 10, 90, 55, 0, "%", function(v) State.healPct = v / 100 end)
	makeSlider(s, "Flee at HP %", 5, 60, 25, 0, "%", function(v) State.fleePct = v / 100 end)
	makeButton(s, "Teleport to Bunker", C.cyanDeep, function() task.spawn(teleportToSafeZone) end)
end

do
	local c = card(shopTab, "Quick Buy")
	makeButton(c, "Buy Lockpick", C.cyanDeep, function() task.spawn(function() buySmart("Lockpick", 1) end) end)
	makeButton(c, "Buy Food (Almond Bottle x3)", C.cyanDeep, function() task.spawn(function() buySmart("Almond Bottle", 3) end) end)
	makeButton(c, "Buy Crowbar", C.cyanDeep, function() task.spawn(function() buySmart("Crowbar", 1) end) end)
	makeButton(c, "Buy Light Vest", C.cyanDeep, function() task.spawn(function() buySmart("Light Vest", 1) end) end)
	makeButton(c, "Buy Handgun Ammo x3", C.cyanDeep, function() task.spawn(function() buySmart("Handgun Ammo", 3) end) end)
	makeToggle(c, "Auto-Restock (food + lockpick)", false, function(v) State.autoRestock = v end)
	local w = card(shopTab, "Carry Weight")
	makeButton(w, "Upgrade Inventory Weight (+1kg)", C.amber, function() task.spawn(function() local ok, why = upgradeWeight() if not ok and why == "max" then footL.Text = "weight at 10kg cap" end end) end)
	note(w, "The 7kg limit is server-side and cannot be bypassed. Max upgrade is 10kg (costs Credits). Use the Loot filter to skip junk.", C.warn)
end

do
	local top = card(lootTab, "Pickup Rules")
	makeToggle(top, "Pick Up Currency", true, function(v) State.collectCurrency = v end)
	makeToggle(top, "Biggest Coins First", true, function(v) State.biggestFirst = v end)
	note(top, "Select items below to ONLY collect those. None selected = collect everything.", C.sub)
	local rowChips = new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, top)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, rowChips)
	local catalog = buildLootCatalog()
	local cells = {}
	local function refreshCells() for _, fn in ipairs(cells) do fn() end end
	new("TextButton", { Size = UDim2.fromOffset(70, 26), BackgroundColor3 = C.glass, Text = "ALL", TextColor3 = C.cyan, Font = Enum.Font.GothamBold, TextSize = 11 }, rowChips).MouseButton1Click:Connect(function()
		State.lootFilter = {} for _, r in ipairs(catalog) do State.lootFilter[r.name] = true end refreshCells()
	end)
	new("TextButton", { Size = UDim2.fromOffset(70, 26), BackgroundColor3 = C.glass, Text = "NONE", TextColor3 = C.sub, Font = Enum.Font.GothamBold, TextSize = 11 }, rowChips).MouseButton1Click:Connect(function()
		State.lootFilter = {} refreshCells()
	end)
	local gridCard = card(lootTab, "Item Filter")
	local grid = new("ScrollingFrame", { Size = UDim2.new(1, 0, 0, 232), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.cyan, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, gridCard)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(50, 50), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for _, rec in ipairs(catalog) do
		local cell = new("ImageButton", { BackgroundColor3 = C.glass, AutoButtonColor = false, Image = "" }, grid)
		corner(cell, 8) local cs = stroke(cell, C.hair, 1, 0)
		if rec.icon then
			new("ImageLabel", { Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.14, 0.1), BackgroundTransparency = 1, Image = rec.icon, ImageTransparency = 0.4 }, cell)
		else
			new("TextLabel", { Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.06), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = rec.name:sub(1, 3):upper(), TextSize = 14, TextColor3 = rec.rarityColor }, cell)
		end
		new("TextLabel", { Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.7), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = rec.name, TextSize = 8, TextColor3 = C.sub, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd }, cell)
		local function upd()
			local sel = State.lootFilter[rec.name] == true
			cs.Color = sel and C.cyan or C.hair cs.Thickness = sel and 1.6 or 1
			cell.BackgroundColor3 = sel and Color3.fromRGB(14, 28, 40) or C.glass
		end
		cells[#cells + 1] = upd upd()
		cell.MouseButton1Click:Connect(function()
			State.lootFilter[rec.name] = not State.lootFilter[rec.name] or nil
			upd()
		end)
	end
end

local statRefs = {}
do
	local top = new("Frame", { Size = UDim2.new(1, -4, 0, 76), BackgroundTransparency = 1 }, statsTab)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(108, 36), CellPadding = UDim2.fromOffset(6, 6) }, top)
	local function counter(name)
		local cd = new("Frame", { BackgroundColor3 = C.raised, BackgroundTransparency = 0.15 }, top) corner(cd, 8) stroke(cd, C.hair, 1, 0.4)
		new("TextLabel", { Size = UDim2.new(1, -8, 0, 12), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = name, TextSize = 10, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left }, cd)
		local v = new("TextLabel", { Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(8, 15), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "0", TextSize = 17, TextColor3 = C.cyan, TextXAlignment = Enum.TextXAlignment.Left }, cd)
		return v
	end
	statRefs.kills = counter("NPC KILLS")
	statRefs.exp = counter("EXP GAINED")
	statRefs.credits = counter("CREDITS")
	statRefs.cpm = counter("CREDITS/MIN")
	local mc = card(statsTab, "Kills by Mob")
	statRefs.mobHolder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, mc)
	new("UIListLayout", { Padding = UDim.new(0, 4) }, statRefs.mobHolder)
	statRefs.mobBars = {}
	local sc = card(statsTab, "Session")
	statRefs.session = new("TextLabel", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "", TextSize = 12, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, sc)
	local gc = card(statsTab, "Vitals")
	local function gauge(name, col)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, gc)
		new("TextLabel", { Size = UDim2.new(0, 70, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = name, TextSize = 11, TextColor3 = C.sub, TextXAlignment = Enum.TextXAlignment.Left }, row)
		local trk = new("Frame", { Size = UDim2.new(1, -78, 0, 8), Position = UDim2.new(0, 74, 0.5, -4), BackgroundColor3 = C.glass }, row) corner(trk, 4)
		local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = col }, trk) corner(fill, 4)
		return fill
	end
	statRefs.gHP = gauge("HEALTH", C.good)
	statRefs.gSTM = gauge("STAMINA", C.cyan)
	statRefs.gHunger = gauge("HUNGER", C.amber)
	statRefs.gThirst = gauge("THIRST", C.cyanDeep)
end

do
	local c = card(visualTab, "Visual")
	makeToggle(c, "FullBright", false, function(v) State.fullBright = v setFullBright(v) end)
	local m = card(visualTab, "Movement")
	makeCycle(m, "Mode", { "Teleport", "Tween", "Walk" }, 1, function(v) State.moveMode = v end)
	makeSlider(m, "Tween Speed", 60, 400, 220, 0, "", function(v) State.moveSpeed = v end)
	makeSlider(m, "Loot Settle", 0.2, 1.2, 0.55, 2, "s", function(v) State.lootSettle = v end)
end

showTab("FARM")

local function fmt(n) n = math.floor(n) if n >= 1000000 then return string.format("%.1fM", n / 1e6) elseif n >= 1000 then return string.format("%.1fk", n / 1000) end return tostring(n) end
do
	local acc = 0
	addConn(RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.5 then return end
		acc = 0
		if State.godmode then
			local hum = getHum()
			if hum then
				if State.godmodeMode == "Full" then if hum.MaxHealth ~= 1e9 then hum.MaxHealth = 1e9 end if hum.Health < 1e9 then hum.Health = 1e9 end
				else if hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end end
				local st = hum.Parent and hum.Parent:FindFirstChild("States")
				if st then local d = st:FindFirstChild("Downed") if d and d.Value then d.Value = false end end
			end
		end
		if State.infStamina then
			local ch = lp.Character
			local vals = ch and ch:FindFirstChild("Values")
			local stm = vals and vals:FindFirstChild("STM")
			if stm then local cap = 100 + 5 * endurance() if stm.Value < cap then stm.Value = cap end end
		end
		if State.fullBright then applyFullBright() end
		-- stats
		statRefs.kills.Text = tostring(statValue("NPC Kills") - State.startKills)
		statRefs.exp.Text = fmt(State.gainExp)
		statRefs.credits.Text = fmt(State.gainCredits)
		local mins = math.max((os.clock() - State.startClock) / 60, 0.01)
		statRefs.cpm.Text = fmt(State.gainCredits / mins)
		statRefs.session.Text = string.format("Boxes  %d\nCrates %d\nLoot   %d\nScraps +%d\nDeaths %d\nUptime %dm %ds",
			State.boxesBroken, State.cratesOpened, State.lootGrabbed, State.gainScraps, State.deaths, math.floor(mins), math.floor((os.clock() - State.startClock) % 60))
		local maxKills = 1
		for _, n in pairs(State.perMob) do if n > maxKills then maxKills = n end end
		for name, n in pairs(State.perMob) do
			local bar = statRefs.mobBars[name]
			if not bar then
				local row = new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, statRefs.mobHolder)
				local b = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15 }, row) corner(b, 4)
				new("UIGradient", { Color = ColorSequence.new(C.amber, C.cyan) }, b)
				new("TextLabel", { Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = name, TextSize = 11, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, row)
				local cnt = new("TextLabel", { Size = UDim2.fromOffset(40, 24), Position = UDim2.new(1, -42, 0, 0), BackgroundTransparency = 1, Font = Enum.Font.Code, Text = "0", TextSize = 11, TextColor3 = C.cyan, TextXAlignment = Enum.TextXAlignment.Right }, row)
				bar = { fill = b, cnt = cnt } statRefs.mobBars[name] = bar
			end
			bar.cnt.Text = tostring(n)
			TweenService:Create(bar.fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(n / maxKills, 1) }):Play()
		end
		-- vitals
		local ch = lp.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local vals = ch and ch:FindFirstChild("Values")
		local function setG(g, frac) if g then g.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1) end end
		setG(statRefs.gHP, hum and hum.MaxHealth > 0 and (hum.Health / math.min(hum.MaxHealth, 100)) or 0)
		if vals then
			local stm = vals:FindFirstChild("STM") setG(statRefs.gSTM, stm and stm.Value / (100 + 5 * endurance()) or 0)
			local hu = vals:FindFirstChild("Hunger") setG(statRefs.gHunger, hu and hu.Value / 100 or 0)
			local th = vals:FindFirstChild("Thirst") setG(statRefs.gThirst, th and th.Value / 100 or 0)
		end
		footL.Text = "scan: " .. State.currentAction:lower()
	end))
end

do
	local dragging, dragStart, startPos
	header.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true dragStart = i.Position startPos = main.Position end end)
	header.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end end)
	addConn(UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			shadow.Position = main.Position
		end
	end))
end

local minimized, savedSize = false, main.Size
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		savedSize = main.Size
		sidebar.Visible = false content.Visible = false footer.Visible = false
		TweenService:Create(main, TweenInfo.new(0.18), { Size = UDim2.fromOffset(savedSize.X.Offset, 46) }):Play()
	else
		TweenService:Create(main, TweenInfo.new(0.18), { Size = savedSize }):Play()
		task.wait(0.18)
		sidebar.Visible = true content.Visible = true footer.Visible = true
	end
end)

addConn(lp.Idled:Connect(function() pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end) end))

local function unload()
	State.running = false
	State.autoKill = false State.autoBoxes = false State.autoLockpick = false State.autoLoot = false
	State.autoMinigames = false State.autoRestock = false State.autoHeal = false State.autoFlee = false
	if State.godmode then State.godmode = false godDisable() end
	if State.fullBright then setFullBright(false) end
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
	pcall(function() screenGui:Destroy() end)
	pcall(function() shadow:Destroy() end)
	if getgenv then getgenv().__BackroomsAF = nil end
end

closeBtn.MouseButton1Click:Connect(unload)
if getgenv then getgenv().__BackroomsAF = unload end

do
	local s = new("UIScale", { Scale = 0.93 }, main)
	main.BackgroundTransparency = 1
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(main, TweenInfo.new(0.3), { BackgroundTransparency = 0.06 }):Play()
end
