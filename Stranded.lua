local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

if _G.__MoreAuto and _G.__MoreAuto.Unload then
	pcall(_G.__MoreAuto.Unload)
end

local App = {}
_G.__MoreAuto = App

local connections = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

local State = {
	Master = 1,
	Chest = { on = false, settle = 0.9, offset = 6 },
	Melee = { on = false, cps = 8 },
	Grind = { on = false, cps = 5, priorityRare = true },
	Collect = { on = false, cps = 8, radius = 35 },
	Survival = { on = true, food = 40, hp = 0.4, o2 = 25 },
}

local Budget = { tokens = 400, max = 400 }
bind(RunService.Heartbeat, function(dt)
	Budget.tokens = math.min(Budget.max, Budget.tokens + Budget.max * dt)
end)
local function spend()
	while Budget.tokens < 1 do
		RunService.Heartbeat:Wait()
	end
	Budget.tokens = Budget.tokens - 1
end

local Network
local function resolveNetwork()
	local ok, drag = pcall(require, game.ReplicatedStorage.Modules.Systems.DragSystem)
	if ok and type(drag) == "table" and drag.Network and rawget(drag.Network, "RF") then
		return drag.Network
	end
	for _, o in ipairs(getgc(true)) do
		if type(o) == "table" then
			local good = pcall(function()
				return rawget(o, "RF") ~= nil and rawget(o, "RE") ~= nil and rawget(o, "InvokeServer") ~= nil and rawget(o, "EncodeData") ~= nil
			end)
			if good and rawget(o, "InvokeServer") and rawget(o, "RF") and rawget(o, "RE") then
				return o
			end
		end
	end
end
Network = resolveNetwork()

local function invoke(action, ...)
	if not Network then Network = resolveNetwork() end
	if not Network then return nil end
	spend()
	local args = { ... }
	local ok, res = pcall(function()
		return Network:InvokeServer(action, unpack(args))
	end)
	if ok then return res end
	return nil
end

local function fire(action, ...)
	if not Network then Network = resolveNetwork() end
	if not Network then return end
	spend()
	local args = { ... }
	pcall(function()
		Network:FireServer(action, unpack(args))
	end)
end

local function char()
	local c = LocalPlayer.Character
	if not c then return end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	return c, hrp, hum, c:FindFirstChild("Head")
end

local function alive()
	local _, hrp, hum = char()
	return hrp ~= nil and hum ~= nil and hum.Health > 0
end

local function tp(pos)
	local _, hrp = char()
	if hrp then hrp.CFrame = CFrame.new(pos) end
end

local safePos
do
	local si = workspace:FindFirstChild("SpawnIsland")
	if si then
		local okp = pcall(function() return si:GetPivot().Position end)
		if okp then safePos = si:GetPivot().Position + Vector3.new(0, 5, 0) end
	end
end

local function doubloons() return LocalPlayer:GetAttribute("Doubloons") or 0 end
local function foodStat() return LocalPlayer:GetAttribute("Food") or 100 end
local function o2Stat() return LocalPlayer:GetAttribute("O2") or 100 end
local function hpFrac()
	local _, _, hum = char()
	if hum and hum.MaxHealth > 0 then return hum.Health / hum.MaxHealth end
	return 1
end

local function chestsLeft()
	local f = workspace:FindFirstChild("Chests")
	if not f then return 0 end
	local n = 0
	local key = "Opened" .. LocalPlayer.Name
	for _, c in ipairs(f:GetChildren()) do
		if c.PrimaryPart and not c:GetAttribute(key) then n = n + 1 end
	end
	return n
end

local function realCreatures()
	local cc = workspace:FindFirstChild("CreatureContainer")
	local t = {}
	if not cc then return t end
	for _, m in ipairs(cc:GetChildren()) do
		if not string.find(m.Name, "_CLIENT", 1, true) and m:FindFirstChild("CreatureID") and not m:GetAttribute("Dead") then
			local root = m.PrimaryPart or m:FindFirstChild("Root") or m:FindFirstChildWhichIsA("BasePart")
			if root then
				t[#t + 1] = { m = m, root = root, hp = m:FindFirstChild("Health") }
			end
		end
	end
	return t
end

local function findMelee()
	local function scan(parent)
		for _, t in ipairs(parent:GetChildren()) do
			if t:IsA("Tool") and CollectionService:HasTag(t, "Melee") then return t end
		end
	end
	local c = LocalPlayer.Character
	local bp = LocalPlayer:FindFirstChild("Backpack")
	return (c and scan(c)) or (bp and scan(bp))
end

local Status = { text = "idle" }
local function setStatus(s) Status.text = s end

local function survivalTick()
	if not State.Survival.on then return end
	local c, hrp, hum, head = char()
	if not hrp or not hum then return end

	if hum.Health / math.max(hum.MaxHealth, 1) < State.Survival.hp then
		if safePos then
			setStatus("survival: retreat (low hp)")
			tp(safePos)
			local t0 = os.clock()
			while os.clock() - t0 < 6 and hpFrac() < 0.85 do
				task.wait(0.3)
			end
		end
		return
	end

	if head and head.Position.Y < 142 and o2Stat() < State.Survival.o2 then
		setStatus("survival: surface (o2)")
		tp(Vector3.new(hrp.Position.X, 152, hrp.Position.Z))
		return
	end

	if foodStat() < State.Survival.food then
		local df = workspace:FindFirstChild("DebrisField")
		if df then
			for _, m in ipairs(df:GetChildren()) do
				local fattr = m:GetAttribute("Food")
				if fattr and m.PrimaryPart and (m.PrimaryPart.Position - hrp.Position).Magnitude < 60 then
					local nm = m:GetAttribute("Item") or m.Name
					fire("Collect", nm)
					task.wait(0.15)
					fire("Eat", nm)
					setStatus("survival: ate " .. tostring(nm))
					break
				end
			end
		end
	end
end

local function loopChest()
	local key = "Opened" .. LocalPlayer.Name
	local fails = {}
	while State.Chest.on do
		if not alive() then task.wait(0.5) end
		local folder = workspace:FindFirstChild("Chests")
		local _, hrp = char()
		if folder and hrp then
			local best, bestd
			for _, c in ipairs(folder:GetChildren()) do
				if c.PrimaryPart and not c:GetAttribute(key) and (fails[c] or 0) < 2 then
					local d = (c.PrimaryPart.Position - hrp.Position).Magnitude
					if not bestd or d < bestd then best, bestd = c, d end
				end
			end
			if best then
				setStatus("chest: " .. best.Name)
				local pp = best.PrimaryPart
				tp(pp.Position + Vector3.new(0, State.Chest.offset, 0))
				task.wait(State.Chest.settle)
				local ret = invoke("OpenChest", best)
				if ret ~= true and not best:GetAttribute(key) then
					task.wait(0.6)
					ret = invoke("OpenChest", best)
				end
				if ret ~= true and not best:GetAttribute(key) then
					fails[best] = (fails[best] or 0) + 1
				end
			else
				setStatus("chest: waiting for spawns")
				task.wait(2)
			end
		else
			task.wait(1)
		end
		task.wait(0.05)
	end
end

local function loopMelee()
	while State.Melee.on do
		local tool = findMelee()
		local c, hrp, hum = char()
		if tool and hrp and hum then
			if tool.Parent ~= c then
				pcall(function() hum:EquipTool(tool) end)
				task.wait(0.15)
			end
			local list = realCreatures()
			local target, td
			for _, e in ipairs(list) do
				local d = (e.root.Position - hrp.Position).Magnitude
				if not td or d < td then target, td = e, d end
			end
			if target and target.root and target.root.Parent then
				setStatus("melee: " .. target.m.Name)
				hrp.CFrame = CFrame.new(target.root.Position + Vector3.new(0, 0, 3.5), target.root.Position)
				spend()
				pcall(function() tool:Activate() end)
			else
				setStatus("melee: no target")
				task.wait(0.4)
			end
		else
			setStatus("melee: no weapon")
			task.wait(0.5)
		end
		local cps = math.clamp(State.Melee.cps * State.Master, 0.5, 60)
		task.wait(1 / cps)
	end
end

local function loopGrind()
	local box
	local function findBox()
		local si = workspace:FindFirstChild("SpawnIsland")
		local gr = si and si:FindFirstChild("Grinder")
		return gr and gr:FindFirstChild("Collection")
	end
	while State.Grind.on do
		box = box or findBox()
		local df = workspace:FindFirstChild("DebrisField")
		local _, hrp = char()
		if box and df and hrp then
			local rare = { Goo = 4, Metal = 3, Cloth = 2, Wood = 1 }
			local best, bestScore
			for _, m in ipairs(df:GetChildren()) do
				local res = m:GetAttribute("Resource")
				if res and m.PrimaryPart then
					local d = (m.PrimaryPart.Position - hrp.Position).Magnitude
					if d < 220 then
						local val = m:GetAttribute("Value") or 1
						local score
						if State.Grind.priorityRare then
							score = (rare[res] or 1) * 1000 + val * 10 - d * 0.01
						else
							score = val * 10 - d * 0.01
						end
						if not bestScore or score > bestScore then best, bestScore = m, score end
					end
				end
			end
			if best then
				setStatus("grind: " .. (best:GetAttribute("Item") or best.Name))
				tp(best.PrimaryPart.Position + Vector3.new(0, 3, 3))
				task.wait(0.45)
				local ok = invoke("AttemptDrag", best.PrimaryPart)
				if ok and best.Parent and best.PrimaryPart then
					best.PrimaryPart.CFrame = CFrame.new(box.Position)
					best.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
					best.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
					task.wait(0.2)
					if best.Parent and best.PrimaryPart then
						fire("GiveUpOwnership", best.PrimaryPart, Vector3.zero)
					end
					local t0 = os.clock()
					while os.clock() - t0 < 2.5 and best.Parent do task.wait(0.2) end
				end
			else
				setStatus("grind: no nearby resource")
				task.wait(1.5)
			end
		else
			setStatus("grind: no grinder")
			task.wait(2)
		end
		local cps = math.clamp(State.Grind.cps * State.Master, 0.5, 30)
		task.wait(1 / cps)
	end
end

local function loopCollect()
	while State.Collect.on do
		local df = workspace:FindFirstChild("DebrisField")
		local _, hrp = char()
		if df and hrp then
			for _, m in ipairs(df:GetChildren()) do
				if not State.Collect.on then break end
				local isLoot = m:IsA("Tool") or m:GetAttribute("Consumable")
				if isLoot then
					local part = m:IsA("BasePart") and m or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
					if part and (part.Position - hrp.Position).Magnitude < State.Collect.radius then
						fire("Collect", m.Name)
						local cps = math.clamp(State.Collect.cps * State.Master, 0.5, 60)
						task.wait(1 / cps)
					end
				end
			end
		end
		task.wait(0.4)
	end
end

bind(RunService.Heartbeat, (function()
	local acc = 0
	return function(dt)
		acc = acc + dt
		if acc >= 0.5 then
			acc = 0
			task.spawn(function() pcall(survivalTick) end)
		end
	end
end)())

bind(LocalPlayer.Idled, function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end)

local function start(feature, fn)
	if State[feature].on then return end
	State[feature].on = true
	task.spawn(function() pcall(fn) end)
end
local function stop(feature)
	State[feature].on = false
end

local CoreGui = gethui and gethui() or game:GetService("CoreGui")
local gui = Instance.new("ScreenGui")
gui.Name = "Sys" .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = CoreGui

local function corner(p, r)
	local u = Instance.new("UICorner")
	u.CornerRadius = UDim.new(0, r or 6)
	u.Parent = p
	return u
end
local function pad(p, n)
	local u = Instance.new("UIPadding")
	u.PaddingLeft = UDim.new(0, n)
	u.PaddingRight = UDim.new(0, n)
	u.PaddingTop = UDim.new(0, n)
	u.PaddingBottom = UDim.new(0, n)
	u.Parent = p
end

local COL_BG = Color3.fromRGB(18, 22, 28)
local COL_PANEL = Color3.fromRGB(28, 34, 42)
local COL_ACC = Color3.fromRGB(64, 156, 255)
local COL_ON = Color3.fromRGB(64, 200, 120)
local COL_OFF = Color3.fromRGB(70, 78, 90)
local COL_TXT = Color3.fromRGB(232, 238, 245)

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 300, 0, 472)
main.Position = UDim2.new(0, 24, 0, 80)
main.BackgroundColor3 = COL_BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
corner(main, 10)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(48, 56, 68)
stroke.Thickness = 1
stroke.Parent = main

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 40)
bar.BackgroundColor3 = COL_PANEL
bar.BorderSizePixel = 0
bar.Parent = main
corner(bar, 10)
local barFix = Instance.new("Frame")
barFix.Size = UDim2.new(1, 0, 0, 12)
barFix.Position = UDim2.new(0, 0, 1, -12)
barFix.BackgroundColor3 = COL_PANEL
barFix.BorderSizePixel = 0
barFix.Parent = bar

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold
title.Text = "Море • Auto"
title.TextSize = 15
title.TextColor3 = COL_TXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = bar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -36, 0, 6)
minBtn.BackgroundColor3 = COL_OFF
minBtn.Text = "—"
minBtn.TextColor3 = COL_TXT
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.AutoButtonColor = true
minBtn.Parent = bar
corner(minBtn, 6)

do
	local dragging, startPos, startMouse
	bind(bar.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = main.Position
			startMouse = i.Position
		end
	end)
	bind(UserInputService.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startMouse
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	bind(UserInputService.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -40)
body.Position = UDim2.new(0, 0, 0, 40)
body.BackgroundTransparency = 1
body.Parent = main
pad(body, 12)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = body

local order = 0
local function nextOrder() order = order + 1 return order end

local function makeToggle(text, feature, fn)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = COL_PANEL
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = body
	corner(row, 6)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -70, 1, 0)
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = text
	lbl.TextSize = 13
	lbl.TextColor3 = COL_TXT
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row
	local sw = Instance.new("TextButton")
	sw.Size = UDim2.new(0, 46, 0, 22)
	sw.Position = UDim2.new(1, -58, 0.5, -11)
	sw.BackgroundColor3 = State[feature].on and COL_ON or COL_OFF
	sw.Text = ""
	sw.AutoButtonColor = false
	sw.Parent = row
	corner(sw, 11)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = State[feature].on and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Parent = sw
	corner(knob, 9)
	bind(sw.MouseButton1Click, function()
		local nowOn = not State[feature].on
		if nowOn then
			start(feature, fn)
		else
			stop(feature)
		end
		TweenService:Create(sw, TweenInfo.new(0.15), { BackgroundColor3 = nowOn and COL_ON or COL_OFF }):Play()
		TweenService:Create(knob, TweenInfo.new(0.15), { Position = nowOn and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9) }):Play()
	end)
	return row
end

local function makeSlider(text, min, max, get, set, fmt)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 42)
	row.BackgroundColor3 = COL_PANEL
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = body
	corner(row, 6)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -20, 0, 18)
	lbl.Position = UDim2.new(0, 12, 0, 4)
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 12
	lbl.TextColor3 = COL_TXT
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -24, 0, 6)
	track.Position = UDim2.new(0, 12, 0, 28)
	track.BackgroundColor3 = COL_OFF
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 3)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COL_ACC
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 3)
	local function refresh()
		local v = get()
		local a = (v - min) / (max - min)
		fill.Size = UDim2.new(math.clamp(a, 0, 1), 0, 1, 0)
		lbl.Text = text .. ":  " .. (fmt and fmt(v) or tostring(v))
	end
	refresh()
	local dragging = false
	local function apply(px)
		local a = math.clamp((px - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		set(min + (max - min) * a)
		refresh()
	end
	bind(track.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			apply(i.Position.X)
		end
	end)
	bind(UserInputService.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			apply(i.Position.X)
		end
	end)
	bind(UserInputService.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return row
end

makeToggle("Авто-сундуки (Doubloons)", "Chest", loopChest)
makeToggle("Авто-килл (ближний бой)", "Melee", loopMelee)
makeToggle("Авто-грайнд ресурсов", "Grind", loopGrind)
makeToggle("Авто-сбор лута", "Collect", loopCollect)
makeToggle("Выживание (авто)", "Survival", function() end)

makeSlider("Скорость (master)", 0.25, 4, function() return State.Master end, function(v) State.Master = v end, function(v) return string.format("x%.2f", v) end)
makeSlider("Killer CPS", 1, 20, function() return State.Melee.cps end, function(v) State.Melee.cps = math.floor(v + 0.5) end)
makeSlider("Grind CPS", 1, 15, function() return State.Grind.cps end, function(v) State.Grind.cps = math.floor(v + 0.5) end)

local stats = Instance.new("TextLabel")
stats.Size = UDim2.new(1, 0, 0, 78)
stats.BackgroundColor3 = COL_PANEL
stats.BorderSizePixel = 0
stats.LayoutOrder = nextOrder()
stats.Font = Enum.Font.Code
stats.TextSize = 11.5
stats.TextColor3 = Color3.fromRGB(180, 220, 255)
stats.TextXAlignment = Enum.TextXAlignment.Left
stats.TextYAlignment = Enum.TextYAlignment.Top
stats.Text = ""
stats.Parent = body
corner(stats, 6)
pad(stats, 8)

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, 0, 0, 32)
unloadBtn.BackgroundColor3 = Color3.fromRGB(196, 64, 72)
unloadBtn.Text = "Выгрузить (Unload)"
unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.TextSize = 13
unloadBtn.LayoutOrder = nextOrder()
unloadBtn.Parent = body
corner(unloadBtn, 6)

local minimized = false
bind(minBtn.MouseButton1Click, function()
	minimized = not minimized
	body.Visible = not minimized
	main.Size = minimized and UDim2.new(0, 300, 0, 40) or UDim2.new(0, 300, 0, 472)
end)

local startD = doubloons()
local startT = os.clock()
bind(RunService.Heartbeat, (function()
	local acc = 0
	return function(dt)
		acc = acc + dt
		if acc < 0.4 then return end
		acc = 0
		local elapsed = math.max(os.clock() - startT, 1)
		local gained = doubloons() - startD
		local perHr = math.floor(gained / elapsed * 3600)
		stats.Text = string.format(
			"Doubloons: %d   (+%d, ~%d/ч)\nFood: %d%%   O2: %d%%   HP: %d%%\nСундуков осталось: %d\n%s",
			doubloons(), gained, perHr,
			math.floor(foodStat()), math.floor(o2Stat()), math.floor(hpFrac() * 100),
			chestsLeft(),
			Status.text
		)
	end
end)())

function App.Unload()
	for k in pairs(State) do
		if type(State[k]) == "table" and State[k].on ~= nil then State[k].on = false end
	end
	task.wait(0.1)
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	connections = {}
	pcall(function() gui:Destroy() end)
	_G.__MoreAuto = nil
end

bind(unloadBtn.MouseButton1Click, function()
	App.Unload()
end)

setStatus("готов")
