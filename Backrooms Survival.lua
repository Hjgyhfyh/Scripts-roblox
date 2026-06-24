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
	autoKill = false,
	autoBoxes = false,
	autoLockpick = false,
	autoLoot = false,
	autoMinigames = false,
	includeBoss = false,
	attackType = "M1",
	attacksPerSec = 3,

	autoHeal = false,
	hitRun = false,
	autoFlee = false,
	quickRespawn = false,
	healPct = 0.55,
	fleePct = 0.25,
	hopHeight = 16,

	autoRestock = false,
	fullBright = false,

	moveMode = "Teleport",
	moveSpeed = 200,
	lootSettle = 0.6,

	currentAction = "Idle",
	kills = 0,
	boxesBroken = 0,
	cratesOpened = 0,
	lootGrabbed = 0,
	startKills = 0,
	startEXP = 0,
	startCredits = 0,
}

local connections = {}
local function addConn(conn)
	connections[#connections + 1] = conn
	return conn
end

local function getHRP()
	local c = lp.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
	local c = lp.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end
local function hpPct()
	local h = getHum()
	if not h or h.MaxHealth <= 0 then return nil end
	return h.Health / h.MaxHealth
end

local Data
do
	local pf = lp:FindFirstChild("playerFolder")
	Data = pf and pf:FindFirstChild("Data")
end
local function statValue(name)
	if not Data then return 0 end
	local o = Data:FindFirstChild(name)
	return o and o.Value or 0
end
State.startKills = statValue("NPC Kills")
State.startEXP = statValue("EXP")
State.startCredits = statValue("Credits")

local function hasItem(name)
	if lp.Backpack:FindFirstChild(name) then return true end
	local c = lp.Character
	return c and c:FindFirstChild(name) ~= nil
end
local function foodCount()
	local n = 0
	local function scan(parent)
		if not parent then return end
		for _, t in ipairs(parent:GetChildren()) do
			if t:IsA("Tool") and t:FindFirstChild("ConsumableStats") then
				local ok, m = pcall(require, t.ConsumableStats)
				if ok and type(m) == "table" and (m.healPerUse or 0) > 0 then n = n + 1 end
			end
		end
	end
	scan(lp.Backpack)
	scan(lp.Character)
	return n
end

local function findMelee()
	local char = lp.Character
	if not char then return nil end
	local function valid(t)
		return t:IsA("Tool") and t:FindFirstChild("MeleeStats") and t:FindFirstChild("Remotes") and t.Remotes:FindFirstChild("OnHit")
	end
	local tool
	for _, t in ipairs(char:GetChildren()) do if valid(t) then tool = t break end end
	if not tool then
		for _, t in ipairs(lp.Backpack:GetChildren()) do if valid(t) then tool = t break end end
	end
	if not tool then return nil end
	if tool.Parent ~= char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum:EquipTool(tool) task.wait(0.12) end
	end
	local hitRange = 3.5
	pcall(function()
		local s = require(tool.MeleeStats)
		if type(s) == "table" and tonumber(s.hitRange) then hitRange = s.hitRange end
	end)
	return tool, tool.Remotes.OnHit, hitRange
end

local function gotoCFrame(dest, settle)
	local hrp = getHRP()
	if not hrp then return false end
	local mode = State.moveMode
	if mode == "Walk" then
		local hum = getHum()
		if hum then
			local t = 0
			repeat
				hum:MoveTo(dest.Position)
				task.wait(0.1)
				t = t + 0.1
				hrp = getHRP()
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
		task.wait(settle or 0.35)
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
		if u and u.Value <= 0 then
			food = bestFood()
			if not food then break end
			food.Parent = char
			task.wait(0.4)
		end
		pcall(function() food:Activate() end)
		task.wait(1.2)
	end
	pcall(function() hum:UnequipTools() end)
	task.wait(0.1)
	if prev and prev.Parent and prev ~= food then pcall(function() hum:EquipTool(prev) end) end
	return true
end

local function nearestNPC()
	local hrp = getHRP()
	if not hrp then return nil end
	local npcRoot = workspace:FindFirstChild("NPCs")
	if not npcRoot then return nil end
	local folders = { "Zombies", "Enemy", "Recon", "Neutrals" }
	if State.includeBoss then folders[#folders + 1] = "Boss" end
	local best, bestHum, bestRoot, bestDist
	for _, fn in ipairs(folders) do
		local folder = npcRoot:FindFirstChild(fn)
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if m:IsA("Model") then
					local h = m:FindFirstChildOfClass("Humanoid")
					local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
					if h and r and h.Health > 0 and h.Health < 1e6 then
						local d = (r.Position - hrp.Position).Magnitude
						if not bestDist or d < bestDist then best, bestHum, bestRoot, bestDist = m, h, r, d end
					end
				end
			end
		end
	end
	return best, bestHum, bestRoot, bestDist
end

local BOXNAMES = { Randomized = true, RaritySpecified = true, RaritySpecifiedFixed = true, RarityFixedCommon = true }
local function nearestBox()
	local hrp = getHRP()
	if not hrp then return nil end
	local g = workspace:FindFirstChild("Game")
	local items = g and g:FindFirstChild("Items")
	local boxes = items and items:FindFirstChild("Boxes")
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
	local hrp = getHRP()
	if not hrp then return nil end
	local g = workspace:FindFirstChild("Game")
	local items = g and g:FindFirstChild("Items")
	local lc = items and items:FindFirstChild("LockpickCrates")
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

local function nearestLoot()
	local hrp = getHRP()
	if not hrp then return nil end
	local g = workspace:FindFirstChild("Game")
	local items = g and g:FindFirstChild("Items")
	local cache = items and items:FindFirstChild("Cache")
	if not cache then return nil end
	local best, bestDist
	for _, m in ipairs(cache:GetChildren()) do
		local prompt
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled then prompt = d break end
		end
		if prompt then
			local part = (m:IsA("BasePart") and m) or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
			if part then
				local d = (part.Position - hrp.Position).Magnitude
				if not bestDist or d < bestDist then best, bestDist = { model = m, prompt = prompt, part = part }, d end
			end
		end
	end
	return best, bestDist
end

local function doKill(npc, hum, root)
	local tool, onhit, hitRange = findMelee()
	if not (tool and onhit) then return end
	local interval = 1 / math.clamp(State.attacksPerSec, 0.5, 12)
	local swings = 0
	while State.running and State.autoKill and npc.Parent and hum.Health > 0 and swings < 40 do
		local char = lp.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then break end
		local pct = hpPct()
		if pct and pct < math.max(State.healPct, State.fleePct) then break end
		if tool.Parent ~= char then
			local mh = char:FindFirstChildOfClass("Humanoid")
			if mh then mh:EquipTool(tool) end
			task.wait(0.12)
		end
		local dir = hrp.Position - root.Position
		dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, 1)
		hrp.CFrame = CFrame.new(root.Position + dir * (hitRange - 1.2), root.Position)
		task.wait(0.05)
		pcall(function() onhit:FireServer(hum, State.attackType) end)
		swings = swings + 1
		State.currentAction = "Killing " .. npc.Name
		if State.hitRun then
			pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
			hrp.CFrame = CFrame.new(root.Position + dir * 4 + Vector3.new(0, State.hopHeight, 0))
		end
		task.wait(interval)
	end
end

local function doBreakBox(box)
	local tool, onhit = findMelee()
	if not (tool and onhit) then return end
	local body = box:FindFirstChild("Body")
	if not body then return end
	gotoCFrame(CFrame.new(body.Position + Vector3.new(0, 0, 3)), 0.4)
	State.currentAction = "Breaking " .. box.Name
	for _ = 1, 12 do
		if not box.Parent or box:FindFirstChild("Destroyed") then break end
		local char = lp.Character
		if tool.Parent ~= char then break end
		pcall(function() onhit:FireServer(nil, "M1", box) end)
		task.wait(0.22)
	end
	if not box.Parent or box:FindFirstChild("Destroyed") then State.boxesBroken = State.boxesBroken + 1 end
end

local function doLockpick(crate, pos)
	if not hasItem("Lockpick") then return "need_lockpick" end
	local prompt = crate.PromptAttachment and crate.PromptAttachment:FindFirstChild("PromptLockpick")
	if not prompt then return end
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	gotoCFrame(CFrame.new(pos + Vector3.new(0, 0, 3)), 0.7)
	State.currentAction = "Lockpicking " .. crate.Name
	pcall(function() fireproximityprompt(prompt) end)
	local gui
	for _ = 1, 30 do
		gui = pg:FindFirstChild("Lockpicking")
		if gui and gui:FindFirstChild("FinishEvent") and gui:FindFirstChild("BodyPart") and gui.BodyPart.Value then break end
		task.wait(0.1)
	end
	if not (gui and gui:FindFirstChild("FinishEvent")) then
		local hrp = getHRP()
		if hrp then hrp.Anchored = false end
		return "no_gui"
	end
	task.wait(0.4)
	pcall(function() gui.FinishEvent:FireServer(gui.BodyPart.Value) end)
	task.wait(0.3)
	pcall(function() gui.CloseEvent:FireServer() end)
	pcall(function() gui.Enabled = false end)
	task.wait(0.2)
	local hrp = getHRP()
	if hrp then hrp.Anchored = false end
	pcall(function() gui:Destroy() end)
	if crate:FindFirstChild("Destroyed") then State.cratesOpened = State.cratesOpened + 1 end
end

local function doCollect(loot)
	gotoCFrame(CFrame.new(loot.part.Position + Vector3.new(0, 3, 0)), State.lootSettle)
	State.currentAction = "Looting " .. (loot.prompt.ActionText ~= "" and loot.prompt.ActionText or loot.model.Name)
	for _ = 1, 3 do
		if not loot.model.Parent then break end
		pcall(function() fireproximityprompt(loot.prompt) end)
		task.wait(0.22)
	end
	if not loot.model.Parent then State.lootGrabbed = State.lootGrabbed + 1 end
end

task.spawn(function()
	while State.running do
		local hrp = getHRP()
		if not hrp then State.currentAction = "Waiting respawn" task.wait(0.5) continue end

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
					State.currentAction = "Healing"
					healCycle(4, 0.9)
					continue
				elseif State.quickRespawn then
					local hum = getHum()
					if hum then State.currentAction = "Quick respawn" hum.Health = 0 pcall(function() hum:ChangeState(Enum.HumanoidStateType.Dead) end) end
					task.wait(1)
					continue
				end
			elseif pct < State.healPct and State.autoHeal and bestFood() then
				State.currentAction = "Healing"
				healCycle(4, 0.9)
				continue
			end
		end

		local candidates = {}
		if State.autoLoot then
			local l, d = nearestLoot()
			if l then candidates[#candidates + 1] = { kind = "loot", dist = d, prio = 0, loot = l } end
		end
		if State.autoKill then
			local n, h, r, d = nearestNPC()
			if n then candidates[#candidates + 1] = { kind = "kill", dist = d, prio = 1, npc = n, hum = h, root = r } end
		end
		if State.autoBoxes then
			local b, d = nearestBox()
			if b then candidates[#candidates + 1] = { kind = "box", dist = d, prio = 2, box = b } end
		end
		if State.autoLockpick and hasItem("Lockpick") then
			local c, d, p = nearestCrate()
			if c then candidates[#candidates + 1] = { kind = "crate", dist = d, prio = 3, crate = c, pos = p } end
		end

		if #candidates > 0 then
			table.sort(candidates, function(a, b)
				if math.abs(a.dist - b.dist) < 8 then return a.prio < b.prio end
				return a.dist < b.dist
			end)
			local c = candidates[1]
			if c.kind == "loot" then doCollect(c.loot)
			elseif c.kind == "kill" then doKill(c.npc, c.hum, c.root)
			elseif c.kind == "box" then doBreakBox(c.box)
			elseif c.kind == "crate" then doLockpick(c.crate, c.pos) end
		else
			State.currentAction = "Idle (searching)"
			task.wait(0.3)
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
						local ce = lock:FindFirstChild("CloseEvent")
						if ce then pcall(function() ce:FireServer() end) end
						local hrp = getHRP()
						if hrp then hrp.Anchored = false end
					end
				elseif swipe and swipe:FindFirstChild("Finished") then
					task.wait(0.8)
					if swipe.Parent then
						pcall(function() swipe.Finished:FireServer() end)
						local ce = swipe:FindFirstChild("CloseEvent")
						if ce then pcall(function() ce:FireServer() end) end
					end
				end
			end
		end
		task.wait(0.4)
	end
end)

local function shopRemote()
	local ok, r = pcall(function()
		return require(ReplicatedStorage.Game.Helpers.EventAccess):GetAllEventInClass("Remotes").ShopProcess
	end)
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
	local sp = shopRemote()
	if not sp then return 0 end
	local n = 0
	for _ = 1, (qty or 1) do
		if not State.running then break end
		local m = merchantWith(item)
		if not m then break end
		pcall(function() sp:FireServer(m, item) end)
		n = n + 1
		task.wait(0.35)
	end
	return n
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
	Lighting.Brightness = 2
	Lighting.ClockTime = 14
	Lighting.FogEnd = 1e9
	Lighting.FogStart = 1e9
	Lighting.Ambient = Color3.fromRGB(178, 178, 178)
	Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
	Lighting.GlobalShadows = false
	Lighting.ExposureCompensation = 0
	for _, v in ipairs(Lighting:GetChildren()) do
		if v:IsA("Atmosphere") then v.Density = 0 end
		if v:IsA("ColorCorrectionEffect") then v.Brightness = 0 v.Contrast = 0 v.TintColor = Color3.new(1, 1, 1) end
		if v:IsA("BlurEffect") then v.Size = 0 end
	end
end
local function setFullBright(on)
	if on then
		if not fbSaved then
			fbSaved = {
				Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
				FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
				Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
				GlobalShadows = Lighting.GlobalShadows, ExposureCompensation = Lighting.ExposureCompensation,
				atmos = {}, cc = {},
			}
			for _, v in ipairs(Lighting:GetChildren()) do
				if v:IsA("Atmosphere") then fbSaved.atmos[v] = v.Density end
				if v:IsA("ColorCorrectionEffect") then fbSaved.cc[v] = { v.Brightness, v.Contrast, v.TintColor } end
			end
		end
		applyFullBright()
	else
		if fbSaved then
			Lighting.Brightness = fbSaved.Brightness
			Lighting.ClockTime = fbSaved.ClockTime
			Lighting.FogEnd = fbSaved.FogEnd
			Lighting.FogStart = fbSaved.FogStart
			Lighting.Ambient = fbSaved.Ambient
			Lighting.OutdoorAmbient = fbSaved.OutdoorAmbient
			Lighting.GlobalShadows = fbSaved.GlobalShadows
			Lighting.ExposureCompensation = fbSaved.ExposureCompensation
			for v, d in pairs(fbSaved.atmos) do if v and v.Parent then v.Density = d end end
			for v, t in pairs(fbSaved.cc) do if v and v.Parent then v.Brightness, v.Contrast, v.TintColor = t[1], t[2], t[3] end end
		end
	end
end
task.spawn(function()
	while State.running do
		if State.fullBright then applyFullBright() end
		task.wait(0.5)
	end
end)

local COL = {
	bg = Color3.fromRGB(18, 18, 21),
	panel = Color3.fromRGB(30, 30, 35),
	panel2 = Color3.fromRGB(40, 40, 46),
	accent = Color3.fromRGB(240, 196, 25),
	on = Color3.fromRGB(64, 184, 99),
	off = Color3.fromRGB(72, 72, 80),
	danger = Color3.fromRGB(206, 70, 64),
	buy = Color3.fromRGB(70, 130, 200),
	text = Color3.fromRGB(236, 236, 238),
	sub = Color3.fromRGB(150, 150, 158),
	knob = Color3.fromRGB(246, 246, 248),
}
local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end
local function stroke(inst, col, thick, trans)
	local s = Instance.new("UIStroke")
	s.Color = col
	s.Thickness = thick or 1
	s.Transparency = trans or 0
	s.Parent = inst
end
local function label(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or COL.text
	l.Font = font or Enum.Font.Gotham
	l.TextSize = size or 14
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BackroomsAF_" .. tostring(math.random(1000, 9999))
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
do
	local mounted = false
	pcall(function()
		if syn and syn.protect_gui then syn.protect_gui(screenGui) end
		if gethui then screenGui.Parent = gethui() mounted = true end
	end)
	if not mounted then pcall(function() screenGui.Parent = game:GetService("CoreGui") mounted = true end) end
	if not mounted then screenGui.Parent = lp:WaitForChild("PlayerGui") end
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 360, 0, 524)
main.Position = UDim2.new(0, 24, 0.5, -262)
main.BackgroundColor3 = COL.bg
main.BorderSizePixel = 0
main.Active = true
main.Parent = screenGui
corner(main, 12)
stroke(main, Color3.fromRGB(55, 55, 62), 1, 0.2)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 42)
titleBar.BackgroundColor3 = COL.panel
titleBar.BorderSizePixel = 0
titleBar.Parent = main
corner(titleBar, 12)
local tbFix = Instance.new("Frame")
tbFix.Size = UDim2.new(1, 0, 0, 14)
tbFix.Position = UDim2.new(0, 0, 1, -14)
tbFix.BackgroundColor3 = COL.panel
tbFix.BorderSizePixel = 0
tbFix.Parent = titleBar

local dot = Instance.new("Frame")
dot.Size = UDim2.new(0, 10, 0, 10)
dot.Position = UDim2.new(0, 14, 0.5, -5)
dot.BackgroundColor3 = COL.accent
dot.BorderSizePixel = 0
dot.Parent = titleBar
corner(dot, 5)

local title = label(titleBar, "Backrooms: Survival", 15, COL.text, Enum.Font.GothamBold)
title.Position = UDim2.new(0, 34, 0, 6)
title.Size = UDim2.new(1, -120, 0, 18)
local subtitle = label(titleBar, "AutoFarm", 11, COL.sub, Enum.Font.Gotham)
subtitle.Position = UDim2.new(0, 34, 0, 22)
subtitle.Size = UDim2.new(1, -120, 0, 14)

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 26, 0, 26)
minBtn.Position = UDim2.new(1, -64, 0.5, -13)
minBtn.BackgroundColor3 = COL.panel2
minBtn.Text = "—"
minBtn.TextColor3 = COL.text
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.Parent = titleBar
corner(minBtn, 7)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.Position = UDim2.new(1, -32, 0.5, -13)
closeBtn.BackgroundColor3 = COL.danger
closeBtn.Text = "✕"
closeBtn.TextColor3 = COL.text
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.Parent = titleBar
corner(closeBtn, 7)

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 30)
tabBar.Position = UDim2.new(0, 8, 0, 48)
tabBar.BackgroundTransparency = 1
tabBar.Parent = main
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 0, 286)
content.Position = UDim2.new(0, 8, 0, 84)
content.BackgroundTransparency = 1
content.Parent = main

local tabs, tabButtons = {}, {}
local function showTab(name)
	for n, fr in pairs(tabs) do
		fr.Visible = (n == name)
		tabButtons[n].BackgroundColor3 = (n == name) and COL.accent or COL.panel2
		tabButtons[n].TextColor3 = (n == name) and COL.bg or COL.sub
	end
end
local function makeTab(name)
	local f = Instance.new("ScrollingFrame")
	f.Size = UDim2.new(1, 0, 1, 0)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ScrollBarThickness = 3
	f.ScrollBarImageColor3 = COL.accent
	f.CanvasSize = UDim2.new(0, 0, 0, 0)
	f.AutomaticCanvasSize = Enum.AutomaticSize.Y
	f.Visible = false
	f.Parent = content
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, 7)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	tabs[name] = f
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 80, 1, 0)
	b.BackgroundColor3 = COL.panel2
	b.Text = name
	b.TextColor3 = COL.sub
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.Parent = tabBar
	corner(b, 7)
	tabButtons[name] = b
	b.MouseButton1Click:Connect(function() showTab(name) end)
	return f
end

local function makeToggle(parent, text, default, cb)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 36)
	row.BackgroundColor3 = COL.panel
	row.BorderSizePixel = 0
	row.Parent = parent
	corner(row, 8)
	local l = label(row, text, 13, COL.text, Enum.Font.GothamMedium)
	l.Position = UDim2.new(0, 12, 0, 0)
	l.Size = UDim2.new(1, -70, 1, 0)
	local pill = Instance.new("TextButton")
	pill.Size = UDim2.new(0, 44, 0, 22)
	pill.Position = UDim2.new(1, -54, 0.5, -11)
	pill.BackgroundColor3 = default and COL.on or COL.off
	pill.Text = ""
	pill.AutoButtonColor = false
	pill.Parent = row
	corner(pill, 11)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = default and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
	knob.BackgroundColor3 = COL.knob
	knob.BorderSizePixel = 0
	knob.Parent = pill
	corner(knob, 9)
	local st = default
	pill.MouseButton1Click:Connect(function()
		st = not st
		TweenService:Create(pill, TweenInfo.new(0.15), { BackgroundColor3 = st and COL.on or COL.off }):Play()
		TweenService:Create(knob, TweenInfo.new(0.15), { Position = st and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9) }):Play()
		cb(st)
	end)
end

local function makeCycle(parent, text, options, defaultIndex, cb)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 36)
	row.BackgroundColor3 = COL.panel
	row.BorderSizePixel = 0
	row.Parent = parent
	corner(row, 8)
	local l = label(row, text, 13, COL.text, Enum.Font.GothamMedium)
	l.Position = UDim2.new(0, 12, 0, 0)
	l.Size = UDim2.new(1, -130, 1, 0)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 108, 0, 24)
	btn.Position = UDim2.new(1, -118, 0.5, -12)
	btn.BackgroundColor3 = COL.panel2
	btn.Text = options[defaultIndex]
	btn.TextColor3 = COL.accent
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.Parent = row
	corner(btn, 7)
	local idx = defaultIndex
	cb(options[idx])
	btn.MouseButton1Click:Connect(function()
		idx = idx % #options + 1
		btn.Text = options[idx]
		cb(options[idx])
	end)
end

local function makeSlider(parent, text, minV, maxV, default, decimals, suffix, cb)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 50)
	row.BackgroundColor3 = COL.panel
	row.BorderSizePixel = 0
	row.Parent = parent
	corner(row, 8)
	local l = label(row, text, 13, COL.text, Enum.Font.GothamMedium)
	l.Position = UDim2.new(0, 12, 0, 7)
	l.Size = UDim2.new(1, -90, 0, 16)
	local valLbl = label(row, "", 13, COL.accent, Enum.Font.GothamBold)
	valLbl.Position = UDim2.new(1, -80, 0, 7)
	valLbl.Size = UDim2.new(0, 68, 0, 16)
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	local trk = Instance.new("Frame")
	trk.Size = UDim2.new(1, -24, 0, 6)
	trk.Position = UDim2.new(0, 12, 0, 34)
	trk.BackgroundColor3 = COL.off
	trk.BorderSizePixel = 0
	trk.Parent = row
	corner(trk, 3)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COL.accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = trk
	corner(fill, 3)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.BackgroundColor3 = COL.knob
	knob.BorderSizePixel = 0
	knob.Parent = trk
	corner(knob, 7)
	local mult = 10 ^ decimals
	local function apply(alpha)
		alpha = math.clamp(alpha, 0, 1)
		local v = minV + (maxV - minV) * alpha
		v = math.floor(v * mult + 0.5) / mult
		local a = (maxV > minV) and (v - minV) / (maxV - minV) or 0
		fill.Size = UDim2.new(a, 0, 1, 0)
		knob.Position = UDim2.new(a, -7, 0.5, -7)
		valLbl.Text = tostring(v) .. (suffix or "")
		cb(v)
	end
	apply((default - minV) / (maxV - minV))
	local dragging = false
	local function fromInput(input)
		apply((input.Position.X - trk.AbsolutePosition.X) / math.max(trk.AbsoluteSize.X, 1))
	end
	trk.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromInput(input)
		end
	end)
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = true end
	end)
	addConn(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then fromInput(input) end
	end))
	addConn(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))
end

local function makeButton(parent, text, color, cb)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -4, 0, 32)
	b.BackgroundColor3 = color or COL.panel2
	b.Text = text
	b.TextColor3 = COL.text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 8)
	b.MouseButton1Click:Connect(cb)
	return b
end
local function header(parent, text)
	local l = label(parent, string.upper(text), 11, COL.accent, Enum.Font.GothamBold)
	l.Size = UDim2.new(1, -4, 0, 16)
end

local farmTab = makeTab("Farm")
local surviveTab = makeTab("Survive")
local shopTab = makeTab("Shop")
local visualTab = makeTab("Visual")

header(farmTab, "Farming")
makeToggle(farmTab, "Auto Kill  (EXP + Credits)", false, function(v) State.autoKill = v end)
makeToggle(farmTab, "Break Boxes  (loot)", false, function(v) State.autoBoxes = v end)
makeToggle(farmTab, "Lockpick Crates  (needs Lockpick)", false, function(v) State.autoLockpick = v end)
makeToggle(farmTab, "Auto Loot  (collect drops)", false, function(v) State.autoLoot = v end)
makeToggle(farmTab, "Auto-Solve Minigames", false, function(v) State.autoMinigames = v end)
header(farmTab, "Combat")
makeCycle(farmTab, "Attack Type", { "M1", "M2" }, 1, function(v) State.attackType = v end)
makeToggle(farmTab, "Target Bosses Too", false, function(v) State.includeBoss = v end)
makeSlider(farmTab, "Attacks / sec", 1, 12, 3, 0, "", function(v) State.attacksPerSec = v end)

header(surviveTab, "Anti-Death")
makeToggle(surviveTab, "Auto-Heal  (use food)", false, function(v) State.autoHeal = v end)
makeToggle(surviveTab, "Hit & Run  (dodge between hits)", false, function(v) State.hitRun = v end)
makeToggle(surviveTab, "Auto-Flee to Bunker", false, function(v) State.autoFlee = v end)
makeToggle(surviveTab, "Quick Respawn when doomed", false, function(v) State.quickRespawn = v end)
makeSlider(surviveTab, "Heal at HP %", 10, 90, 55, 0, "%", function(v) State.healPct = v / 100 end)
makeSlider(surviveTab, "Flee at HP %", 5, 60, 25, 0, "%", function(v) State.fleePct = v / 100 end)
makeSlider(surviveTab, "Hop Height", 6, 40, 16, 0, "", function(v) State.hopHeight = v end)
makeButton(surviveTab, "Teleport to Bunker", COL.buy, function() task.spawn(teleportToSafeZone) end)

header(shopTab, "Quick Buy")
makeButton(shopTab, "Buy Lockpick", COL.buy, function() task.spawn(function() buySmart("Lockpick", 1) end) end)
makeButton(shopTab, "Buy Food  (Almond Bottle x3)", COL.buy, function() task.spawn(function() buySmart("Almond Bottle", 3) end) end)
makeButton(shopTab, "Buy Crowbar  (fast box breaker)", COL.buy, function() task.spawn(function() buySmart("Crowbar", 1) end) end)
makeButton(shopTab, "Buy Light Vest  (armor)", COL.buy, function() task.spawn(function() buySmart("Light Vest", 1) end) end)
header(shopTab, "Ammo  (x3 boxes)")
makeButton(shopTab, "Handgun Ammo", COL.buy, function() task.spawn(function() buySmart("Handgun Ammo", 3) end) end)
makeButton(shopTab, "Shotgun Shells", COL.buy, function() task.spawn(function() buySmart("Shotgun Shells", 3) end) end)
makeButton(shopTab, "Tactical Ammo", COL.buy, function() task.spawn(function() buySmart("Tactical Ammo", 3) end) end)
header(shopTab, "Auto")
makeToggle(shopTab, "Auto-Restock  (food + lockpick)", false, function(v) State.autoRestock = v end)

header(visualTab, "Visual")
makeToggle(visualTab, "FullBright", false, function(v) State.fullBright = v setFullBright(v) end)
header(visualTab, "Movement")
makeCycle(visualTab, "Mode", { "Teleport", "Tween", "Walk" }, 1, function(v) State.moveMode = v end)
makeSlider(visualTab, "Tween Speed", 60, 400, 200, 0, "", function(v) State.moveSpeed = v end)
makeSlider(visualTab, "Loot Settle", 0.2, 1.2, 0.6, 2, "s", function(v) State.lootSettle = v end)

showTab("Farm")

local statusPanel = Instance.new("Frame")
statusPanel.Size = UDim2.new(1, -16, 0, 100)
statusPanel.Position = UDim2.new(0, 8, 0, 378)
statusPanel.BackgroundColor3 = COL.panel
statusPanel.BorderSizePixel = 0
statusPanel.Parent = main
corner(statusPanel, 8)
local sPad = Instance.new("UIPadding")
sPad.PaddingLeft = UDim.new(0, 12)
sPad.PaddingTop = UDim.new(0, 8)
sPad.Parent = statusPanel
local sList = Instance.new("UIListLayout")
sList.Padding = UDim.new(0, 3)
sList.Parent = statusPanel
local function statLine()
	local l = label(statusPanel, "", 12, COL.text, Enum.Font.GothamMedium)
	l.Size = UDim2.new(1, -16, 0, 15)
	return l
end
local lblAction = statLine()
local lblKE = statLine()
local lblCredits = statLine()
local lblLoot = statLine()
local lblHP = statLine()

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -16, 0, 36)
unloadBtn.Position = UDim2.new(0, 8, 0, 482)
unloadBtn.BackgroundColor3 = COL.danger
unloadBtn.Text = "Unload"
unloadBtn.TextColor3 = COL.text
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.TextSize = 14
unloadBtn.Parent = main
corner(unloadBtn, 8)

addConn(RunService.Heartbeat:Connect(function()
	lblAction.Text = "Action:  " .. State.currentAction
	lblKE.Text = "Kills +" .. (statValue("NPC Kills") - State.startKills) .. "    EXP +" .. (statValue("EXP") - State.startEXP)
	lblCredits.Text = "Credits +" .. (statValue("Credits") - State.startCredits)
	lblLoot.Text = "Boxes " .. State.boxesBroken .. "   Crates " .. State.cratesOpened .. "   Loot " .. State.lootGrabbed
	local p = hpPct()
	lblHP.Text = "HP:  " .. (p and (math.floor(p * 100) .. "%") or "-")
end))

do
	local dragging, dragStart, startPos
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	titleBar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
	addConn(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
end

local minimized = false
local savedSize = main.Size
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		savedSize = main.Size
		tabBar.Visible = false content.Visible = false statusPanel.Visible = false unloadBtn.Visible = false
		TweenService:Create(main, TweenInfo.new(0.18), { Size = UDim2.new(savedSize.X.Scale, savedSize.X.Offset, 0, 42) }):Play()
	else
		TweenService:Create(main, TweenInfo.new(0.18), { Size = savedSize }):Play()
		task.wait(0.18)
		tabBar.Visible = true content.Visible = true statusPanel.Visible = true unloadBtn.Visible = true
	end
end)

addConn(lp.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

local function unload()
	State.running = false
	State.autoKill = false State.autoBoxes = false State.autoLockpick = false
	State.autoLoot = false State.autoMinigames = false State.autoHeal = false
	State.autoFlee = false State.autoRestock = false
	if State.fullBright then setFullBright(false) end
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
	pcall(function() screenGui:Destroy() end)
	if getgenv then getgenv().__BackroomsAF = nil end
end

closeBtn.MouseButton1Click:Connect(unload)
unloadBtn.MouseButton1Click:Connect(unload)

if getgenv then getgenv().__BackroomsAF = unload end
