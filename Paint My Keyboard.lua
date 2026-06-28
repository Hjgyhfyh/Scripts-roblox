--[[ Paint My Keyboard ]]--

if _G.PMK_Unload then pcall(_G.PMK_Unload) end

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local VirtualUser      = game:GetService("VirtualUser")

local lp = Players.LocalPlayer

local function notify(t)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {Title = "Paint My Keyboard", Text = t, Duration = 6})
	end)
end

local EV = ReplicatedStorage:FindFirstChild("shared/network/MiscNetwork@GlobalMiscEvents")
local FN = ReplicatedStorage:FindFirstChild("shared/network/MiscNetwork@GlobalMiscFunctions")
if not EV then notify("Сеть не найдена — зайди в игру и запусти снова") return end

local R = {
	Paint = EV:FindFirstChild("PaintKeycap"), Step = EV:FindFirstChild("StepKeycap"),
	Equip = EV:FindFirstChild("EquipPaint"), BuyP = EV:FindFirstChild("BuyPaint"),
	BuyU = EV:FindFirstChild("BuyUpgrade"), Hire = EV:FindFirstChild("HireWorker"),
	Afk = EV:FindFirstChild("AntiAFK"), BuyRNG = EV:FindFirstChild("BuyRNGUpgrade"),
	SetRoll = EV:FindFirstChild("SetRNGRolling"),
}
if not (R.Paint and R.Step) then notify("Ремоуты не найдены") return end

local DataNet, MiscNet, PaintCfg, UpCfg, WorkerCfg, RngUpCfg, AccCfg
pcall(function() DataNet  = require(lp.PlayerScripts.TS.network.DataNetwork) end)
pcall(function() MiscNet  = require(lp.PlayerScripts.TS.network.MiscNetwork) end)
pcall(function() PaintCfg = require(ReplicatedStorage.TS.constants.world.Paint) end)
pcall(function() UpCfg    = require(ReplicatedStorage.TS.constants.world.Upgrades) end)
pcall(function() WorkerCfg= require(ReplicatedStorage.TS.constants.world.Workers) end)
pcall(function() RngUpCfg = require(ReplicatedStorage.TS.constants.world.RNGUpgrades) end)
pcall(function() AccCfg   = require(ReplicatedStorage.TS.constants.world.Accessories) end)

local ACC_ATTR = (AccCfg and AccCfg.AccessoryConfig and AccCfg.AccessoryConfig.attribute) or "Accessory"
local NAME_MULT = {}
if AccCfg and type(AccCfg.Accessories) == "table" then
	for name, def in pairs(AccCfg.Accessories) do NAME_MULT[name] = tonumber(def.moneyMultiplier) or 1 end
end

local UPGRADE_PRIORITY = { "WorkerSpeed", "PaintTankSize", "RollerSize", "WalkSpeed" }
local RNG_KEYS = { "RollLuck", "RollSpeed" }
local MAX_TOTAL_RATE = 400
local TOP_K = 64

local State = {
	farm = false, priority = true, autoBuyPaint = true, autoUpgrade = true,
	autoHire = true, park = false, autoRoll = false, autoRngUp = false,
	paintRate = 66, stepRate = 330, rollRate = 90,
}
_G.PMK = State

local running = true
local conns = {}
local caps, sortedCaps, topCaps = {}, {}, {}
local paintIdx, stepIdx, paintAllIdx, paintTick = 1, 1, 1, 0
local pAcc, sAcc, rAcc = 0, 0, 0
local bestPaint = "Basic"
local lastData = nil
local hrp = nil
local refillCFrame = nil
local capsDirty = true

local function track(c) if c then conns[#conns + 1] = c end return c end

local function readData()
	if not DataNet then return lastData end
	local ok, a, b = pcall(function() return DataNet.DataFunctions.requestDataUpdate:invoke():await() end)
	local d = (type(b) == "table" and b) or (type(a) == "table" and a)
	if type(d) == "table" then lastData = d end
	return lastData
end

local function getMyPlot()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return end
	for _, p in ipairs(plots:GetChildren()) do
		if p:GetAttribute("OwnerUserId") == lp.UserId then return p end
	end
end

local function refreshRefill()
	local plot = getMyPlot()
	if not plot then return end
	local tank = plot:FindFirstChild("PaintTank")
	local spot = tank and tank:FindFirstChild("RefillSpot")
	if spot then refillCFrame = CFrame.new(spot.Position + Vector3.new(0, 3, 0)) end
end

local function valueOf(cap)
	local a = cap:GetAttribute(ACC_ATTR)
	return (type(a) == "string" and NAME_MULT[a]) or 0
end

local function rebuildCaps()
	local plot = getMyPlot()
	local folder = plot and plot:FindFirstChild("Keycaps")
	if not folder then caps = {} sortedCaps = {} topCaps = {} return end
	local t = {}
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("MeshPart") and type(c:GetAttribute("PurchaseProduct")) ~= "string" then t[#t + 1] = c end
	end
	caps = t
	capsDirty = false
	track(folder.ChildAdded:Connect(function() capsDirty = true end))
	track(folder.ChildRemoved:Connect(function() capsDirty = true end))
end

local function resortCaps()
	local s = table.clone(caps)
	table.sort(s, function(a, b) return valueOf(a) > valueOf(b) end)
	sortedCaps = s
	local top = {}
	for i = 1, math.min(TOP_K, #s) do top[i] = s[i] end
	topCaps = top
	if paintIdx > #sortedCaps then paintIdx = 1 end
	if stepIdx > #sortedCaps then stepIdx = 1 end
end

local function bestOwnedPaint(d)
	local best, bestR = d.EquippedPaint or "Basic", -1
	for _, name in ipairs(d.OwnedPaints or {}) do
		local ok, r = pcall(PaintCfg.getEffectiveKeycapReward, name, d.OwnedPaints)
		if ok and type(r) == "number" and r > bestR then bestR, best = r, name end
	end
	return best, bestR
end

local function nextAffordablePaint(d)
	if not PaintCfg or type(PaintCfg.Paints) ~= "table" then return end
	local owned = {}
	for _, n in ipairs(d.OwnedPaints or {}) do owned[n] = true end
	local _, bestOwnedR = bestOwnedPaint(d)
	local money, rebirths = d.Money or 0, d.Rebirths or 0
	local pick, pickCost, pickR = nil, 0, bestOwnedR
	for name in pairs(PaintCfg.Paints) do
		if not owned[name] and name ~= PaintCfg.RAINBOW then
			local _, rb    = pcall(PaintCfg.getPaintRebirthRequirement, name)
			local _, price = pcall(PaintCfg.getPaintPrice, name)
			local _, eff   = pcall(PaintCfg.getEffectiveKeycapReward, name, d.OwnedPaints)
			rb = type(rb) == "number" and rb or 0
			price = type(price) == "number" and price or 0
			eff = type(eff) == "number" and eff or 0
			if price > 0 and rb <= rebirths and price <= money and eff > pickR then pick, pickCost, pickR = name, price, eff end
		end
	end
	return pick, pickCost
end

local function manage()
	local d = readData()
	if not d then return end
	resortCaps()
	local bo = bestOwnedPaint(d)
	if bo then
		bestPaint = bo
		if R.Equip and bo ~= d.EquippedPaint then pcall(R.Equip.FireServer, R.Equip, bo) end
	end
	local spendable = d.Money or 0
	if State.autoBuyPaint and R.BuyP then
		local target, cost = nextAffordablePaint(d)
		if target then pcall(R.BuyP.FireServer, R.BuyP, target) spendable = spendable - cost end
	end
	if State.autoUpgrade and R.BuyU and UpCfg and d.Upgrades then
		for _, key in ipairs(UPGRADE_PRIORITY) do
			local lvl = d.Upgrades[key]
			if type(lvl) == "number" then
				local _, isMax = pcall(UpCfg.isMaxLevel, key, lvl)
				local _, cost  = pcall(UpCfg.getUpgradeCost, key, lvl)
				if not isMax and type(cost) == "number" and cost <= spendable then pcall(R.BuyU.FireServer, R.BuyU, key) spendable = spendable - cost end
			end
		end
	end
	if State.autoRngUp and R.BuyRNG and RngUpCfg and d.RNGUpgrades then
		for _, key in ipairs(RNG_KEYS) do
			local lvl = d.RNGUpgrades[key]
			if type(lvl) == "number" then
				local _, isMax = pcall(RngUpCfg.isMaxLevel, key, lvl)
				local _, cost  = pcall(RngUpCfg.getRNGUpgradeCost, key, lvl)
				if not isMax and type(cost) == "number" and cost <= spendable then pcall(R.BuyRNG.FireServer, R.BuyRNG, key) spendable = spendable - cost end
			end
		end
	end
	if State.autoHire and R.Hire then
		local w, cap = d.Workers or 0, d.WorkerCapacity or 0
		if w < cap then
			local cost
			if WorkerCfg then local _, c = pcall(WorkerCfg.getHireCost, w) cost = c end
			if type(cost) ~= "number" or cost <= spendable then pcall(R.Hire.FireServer, R.Hire) end
		end
	end
	if R.Afk then pcall(R.Afk.FireServer, R.Afk) end
end

local function doRoll()
	if not MiscNet then return end
	pcall(function() MiscNet.MiscFunctions.RequestRNGRoll:invoke():await() end)
end

local function farmStep(dt)
	if not (running and State.farm) then return end
	if capsDirty then rebuildCaps() resortCaps() end
	local list = (#topCaps > 0) and topCaps or sortedCaps
	local nList = #list
	if nList == 0 then return end
	if State.park and refillCFrame then
		if not (hrp and hrp.Parent) then local char = lp.Character hrp = char and char:FindFirstChild("HumanoidRootPart") end
		if hrp then hrp.CFrame = refillCFrame end
	end
	local pr, sr, rr = State.paintRate, State.stepRate, (State.autoRoll and State.rollRate or 0)
	local total = pr + sr + rr
	if total > MAX_TOTAL_RATE then local k = MAX_TOTAL_RATE / total pr, sr, rr = pr * k, sr * k, rr * k end
	local cd = nList * 6.3
	if sr > cd then sr = cd end
	pAcc = pAcc + pr * dt
	local pc = math.floor(pAcc)
	if pc > 0 then pAcc = pAcc - pc
		for _ = 1, pc do if paintIdx > nList then paintIdx = 1 end local cap = list[paintIdx] paintIdx = paintIdx % nList + 1 if cap and cap.Parent then pcall(R.Paint.FireServer, R.Paint, cap, bestPaint) end end
	end
	sAcc = sAcc + sr * dt
	local sc = math.floor(sAcc)
	if sc > 0 then sAcc = sAcc - sc
		for _ = 1, sc do if stepIdx > nList then stepIdx = 1 end local cap = list[stepIdx] stepIdx = stepIdx % nList + 1 if cap and cap.Parent then pcall(R.Step.FireServer, R.Step, cap) end end
	end
	if State.autoRoll then
		rAcc = rAcc + rr * dt
		local rc = math.floor(rAcc)
		if rc > 0 then rAcc = rAcc - rc for _ = 1, math.min(rc, 12) do task.spawn(doRoll) end end
	end
end

local function onCharacter(char)
	task.wait(0.4)
	hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
	refreshRefill()
	capsDirty = true
end

--==================================================================
-- VIOLET-NOIR ACRYLIC CONSOLE  (GUI)
--==================================================================
local C = {
	void = Color3.fromRGB(7, 7, 11), win = Color3.fromRGB(12, 12, 20), panel = Color3.fromRGB(19, 19, 30),
	card = Color3.fromRGB(25, 25, 38), raise = Color3.fromRGB(32, 32, 47), well = Color3.fromRGB(15, 15, 24),
	hair = Color3.fromRGB(43, 43, 61), tx = Color3.fromRGB(244, 245, 247), tx2 = Color3.fromRGB(169, 173, 190),
	txM = Color3.fromRGB(107, 110, 128), on = Color3.fromRGB(43, 209, 126), bad = Color3.fromRGB(242, 85, 90),
	gold = Color3.fromRGB(255, 209, 102), cyan = Color3.fromRGB(86, 192, 255), violet = Color3.fromRGB(139, 108, 255),
}
local RARITY = {
	[2] = Color3.fromRGB(154, 160, 181), [3] = Color3.fromRGB(74, 222, 128), [4] = Color3.fromRGB(59, 158, 255),
	[7] = Color3.fromRGB(178, 107, 255), [60] = Color3.fromRGB(255, 176, 32), [125] = Color3.fromRGB(255, 84, 112),
}
local function rarityColor(mult)
	if mult >= 1000 then return Color3.fromRGB(255, 84, 112) end
	if mult >= 100 then return Color3.fromRGB(255, 176, 32) end
	if mult >= 30 then return Color3.fromRGB(178, 107, 255) end
	if mult >= 10 then return Color3.fromRGB(59, 158, 255) end
	if mult >= 4 then return Color3.fromRGB(74, 222, 128) end
	return Color3.fromRGB(154, 160, 181)
end
local GRAD_BRAND = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(139, 108, 255)), ColorSequenceKeypoint.new(.5, Color3.fromRGB(110, 123, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(86, 192, 255)) })
local GRAD_ON  = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(43, 209, 126)), ColorSequenceKeypoint.new(1, Color3.fromRGB(86, 192, 255)) })
local GRAD_HOT = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(178, 107, 255)), ColorSequenceKeypoint.new(.5, Color3.fromRGB(255, 84, 112)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 176, 32)) })
local GRAD_BODY = ColorSequence.new(Color3.fromRGB(22, 22, 31), Color3.fromRGB(12, 12, 20))
local GRAD_AURORA = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(139, 108, 255)), ColorSequenceKeypoint.new(.5, Color3.fromRGB(86, 192, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 106, 213)) })

local TI = {
	press = TweenInfo.new(.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	fast  = TweenInfo.new(.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	base  = TweenInfo.new(.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	smooth= TweenInfo.new(.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	spring= TweenInfo.new(.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	big   = TweenInfo.new(.40, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	color = TweenInfo.new(.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	exit  = TweenInfo.new(.20, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
}
local SHADOW = "rbxassetid://6014261993"
local GLOW = "rbxassetid://5028857084"

local activeTw = setmetatable({}, { __mode = "k" })
local loopTweens = {}
local function tw(o, info, p)
	local prev = activeTw[o] if prev then prev:Cancel() end
	local t = TweenService:Create(o, info, p) activeTw[o] = t t:Play() return t
end
local function loop(t) loopTweens[#loopTweens + 1] = t return t end

local function corner(o, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r) c.Parent = o return c end
local function pad(o, l, t, r, b) local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, l) p.PaddingRight = UDim.new(0, r or l) p.PaddingTop = UDim.new(0, t or l) p.PaddingBottom = UDim.new(0, b or t or l) p.Parent = o return p end
local function sheen(o, radius)
	local s = Instance.new("Frame") s.BackgroundColor3 = Color3.new(1, 1, 1) s.BorderSizePixel = 0 s.Size = UDim2.fromScale(1, 1) s.ZIndex = (o.ZIndex or 1) + 1 s.Active = false s.Parent = o
	corner(s, radius or 12)
	local g = Instance.new("UIGradient", s) g.Rotation = 90 g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .88), NumberSequenceKeypoint.new(.5, .97), NumberSequenceKeypoint.new(1, 1) })
	return s, g
end
local function makeCard(parent, height)
	local c = Instance.new("Frame") c.BackgroundColor3 = C.card c.BorderSizePixel = 0 c.Size = UDim2.new(1, 0, 0, height or 0)
	c.AutomaticSize = height and Enum.AutomaticSize.None or Enum.AutomaticSize.Y
	corner(c, 12)
	local g = Instance.new("UIGradient", c) g.Color = GRAD_BODY g.Rotation = 90 g.Offset = Vector2.new(0, -0.2)
	local s = Instance.new("UIStroke", c) s.Thickness = 1 s.Color = C.hair s.Transparency = .35 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sheen(c, 12)
	c.Parent = parent
	return c, s
end
local function listCard(parent, height)
	local card = makeCard(parent, height)
	local holder = Instance.new("Frame") holder.BackgroundTransparency = 1 holder.Size = UDim2.fromScale(1, 1) holder.ZIndex = 4 holder.Parent = card
	pad(holder, 0, 4, 0, 4)
	local l = Instance.new("UIListLayout", holder) l.SortOrder = Enum.SortOrder.LayoutOrder
	return holder, card
end
local function bloom(parent, col, baseTr)
	local g = Instance.new("ImageLabel") g.BackgroundTransparency = 1 g.Image = GLOW g.ImageColor3 = col g.ImageTransparency = baseTr or .6 g.ScaleType = Enum.ScaleType.Slice g.SliceCenter = Rect.new(24, 24, 276, 276) g.ZIndex = (parent.ZIndex or 1) - 1 g.Size = UDim2.new(1, 56, 1, 56) g.Position = UDim2.new(0, -28, 0, -28) g.Parent = parent
	return g
end
local function gradStroke(o, seq, th)
	local s = Instance.new("UIStroke", o) s.Thickness = th or 1.5 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border s.Color = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient", s) g.Color = seq g.Rotation = 0
	return s, g
end
local function gradText(label, seq, rot) label.TextColor3 = Color3.new(1, 1, 1) local g = Instance.new("UIGradient", label) g.Color = seq g.Rotation = rot or 0 return g end
local function divider(parent, inset)
	local d = Instance.new("Frame", parent) d.BackgroundColor3 = C.hair d.BorderSizePixel = 0 d.Size = UDim2.new(1, -(inset or 0), 0, 1)
	local g = Instance.new("UIGradient", d) g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.15, .35), NumberSequenceKeypoint.new(.85, .35), NumberSequenceKeypoint.new(1, 1) })
	return d
end
local function lbl(parent, font, size, color, text)
	local t = Instance.new("TextLabel") t.BackgroundTransparency = 1 t.Font = font t.TextSize = size t.TextColor3 = color t.Text = text or "" t.TextXAlignment = Enum.TextXAlignment.Left t.RichText = true t.Parent = parent
	return t
end
local function abbr(n)
	if type(n) ~= "number" then return "?" end
	local a = math.abs(n)
	if a >= 1e15 then return string.format("%.2fQ", n / 1e15) end
	if a >= 1e12 then return string.format("%.2fT", n / 1e12) end
	if a >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if a >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if a >= 1e3 then return string.format("%.1fK", n / 1e3) end
	return tostring(math.floor(n))
end

local gui = Instance.new("ScreenGui")
gui.Name = "PMK_" .. tostring(math.random(1000, 9999))
gui.ResetOnSpawn = false gui.IgnoreGuiInset = true gui.DisplayOrder = 999 gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end

local WIN_W, WIN_H = 360, 548
local win = Instance.new("Frame")
win.Size = UDim2.fromOffset(WIN_W, WIN_H) win.Position = UDim2.fromScale(0.5, 0.5) win.AnchorPoint = Vector2.new(0.5, 0.5)
win.BackgroundColor3 = C.win win.BorderSizePixel = 0 win.ClipsDescendants = true win.Parent = gui
corner(win, 16)
do local g = Instance.new("UIGradient", win) g.Color = GRAD_BODY g.Rotation = 90 end
do local s = Instance.new("UIStroke", win) s.Thickness = 1 s.Color = C.hair s.Transparency = .15 end
local winScale = Instance.new("UIScale", win)
do
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if UserInputService.TouchEnabled and vp then winScale.Scale = math.clamp((vp.X - 24) / WIN_W, 0.7, 1) end
end

-- window shadows (outside clip → parent to gui, follow win)
local function makeWinShadow(spread, tr, oy)
	local sh = Instance.new("ImageLabel") sh.BackgroundTransparency = 1 sh.Image = SHADOW sh.ImageColor3 = Color3.new(0, 0, 0) sh.ImageTransparency = tr sh.ScaleType = Enum.ScaleType.Slice sh.SliceCenter = Rect.new(49, 49, 450, 450) sh.ZIndex = 0 sh.Parent = gui
	return sh, spread, oy
end
local amb, ambS, ambOy = makeWinShadow(46, .52, 6)
local con, conS, conOy = makeWinShadow(20, .34, 8)
local function syncShadow()
	local p, s = win.AbsolutePosition, win.AbsoluteSize
	amb.Size = UDim2.fromOffset(s.X + ambS * 2, s.Y + ambS * 2) amb.Position = UDim2.fromOffset(p.X - ambS, p.Y - ambS + ambOy)
	con.Size = UDim2.fromOffset(s.X + conS * 2, s.Y + conS * 2) con.Position = UDim2.fromOffset(p.X - conS, p.Y - conS + conOy)
end

-- aurora background (inside, clipped)
local aurora = Instance.new("Frame") aurora.BackgroundColor3 = Color3.new(1, 1, 1) aurora.BorderSizePixel = 0 aurora.Size = UDim2.fromScale(1.6, 1.6) aurora.Position = UDim2.fromScale(.5, .5) aurora.AnchorPoint = Vector2.new(.5, .5) aurora.ZIndex = 1 aurora.Parent = win
do local g = Instance.new("UIGradient", aurora) g.Color = GRAD_AURORA g.Transparency = NumberSequence.new(0.9) loop(tw(g, TweenInfo.new(20, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false), { Rotation = 360 })) end

--====================== HEADER
local header = Instance.new("Frame") header.Size = UDim2.new(1, 0, 0, 52) header.BackgroundTransparency = 1 header.ZIndex = 3 header.Parent = win
pad(header, 16, 0, 12, 0)
local dotWrap = Instance.new("Frame") dotWrap.Size = UDim2.fromOffset(12, 12) dotWrap.Position = UDim2.new(0, 0, 0.5, -6) dotWrap.BackgroundTransparency = 1 dotWrap.ZIndex = 3 dotWrap.Parent = header
local dotGlow = Instance.new("ImageLabel") dotGlow.BackgroundTransparency = 1 dotGlow.Image = GLOW dotGlow.ImageColor3 = C.bad dotGlow.ImageTransparency = .4 dotGlow.ScaleType = Enum.ScaleType.Slice dotGlow.SliceCenter = Rect.new(24, 24, 276, 276) dotGlow.Size = UDim2.fromScale(2.6, 2.6) dotGlow.Position = UDim2.fromScale(-.8, -.8) dotGlow.ZIndex = 2 dotGlow.Parent = dotWrap
local dot = Instance.new("Frame") dot.Size = UDim2.fromOffset(10, 10) dot.Position = UDim2.fromScale(.5, .5) dot.AnchorPoint = Vector2.new(.5, .5) dot.BackgroundColor3 = C.bad dot.BorderSizePixel = 0 dot.ZIndex = 3 dot.Parent = dotWrap corner(dot, 5)
loop(tw(dotGlow, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { ImageTransparency = .82 }))

local word = lbl(header, Enum.Font.GothamBold, 16, C.tx, "Paint My Keyboard") word.Position = UDim2.fromOffset(22, 8) word.Size = UDim2.new(1, -110, 0, 20) word.ZIndex = 3
gradText(word, GRAD_BRAND, 12)
local sub = lbl(header, Enum.Font.Gotham, 11, C.txM, "авто-фарм") sub.Position = UDim2.fromOffset(22, 27) sub.Size = UDim2.new(1, -110, 0, 14) sub.ZIndex = 3

local function headerBtn(x)
	local b = Instance.new("TextButton") b.Size = UDim2.fromOffset(26, 26) b.Position = UDim2.new(1, x, 0.5, -13) b.BackgroundColor3 = C.raise b.Text = "" b.AutoButtonColor = false b.ZIndex = 3 b.Parent = header corner(b, 8)
	local s = Instance.new("UIStroke", b) s.Color = C.hair s.Transparency = .4
	b.MouseEnter:Connect(function() tw(b, TI.fast, { BackgroundColor3 = C.hair }) end)
	b.MouseLeave:Connect(function() tw(b, TI.fast, { BackgroundColor3 = C.raise }) end)
	return b
end
local closeBtn = headerBtn(-26)
do for _, r in ipairs({ 45, -45 }) do local p = Instance.new("Frame", closeBtn) p.AnchorPoint = Vector2.new(.5, .5) p.Position = UDim2.fromScale(.5, .5) p.Size = UDim2.fromOffset(12, 2) p.BackgroundColor3 = C.tx2 p.BorderSizePixel = 0 p.Rotation = r p.ZIndex = 4 corner(p, 1) end end
local minBtn = headerBtn(-58)
do local p = Instance.new("Frame", minBtn) p.AnchorPoint = Vector2.new(.5, .5) p.Position = UDim2.fromScale(.5, .5) p.Size = UDim2.fromOffset(12, 2) p.BackgroundColor3 = C.tx2 p.BorderSizePixel = 0 p.ZIndex = 4 corner(p, 1) end
closeBtn.MouseEnter:Connect(function() tw(closeBtn, TI.fast, { BackgroundColor3 = C.bad }) end)
closeBtn.MouseLeave:Connect(function() tw(closeBtn, TI.fast, { BackgroundColor3 = C.raise }) end)

--====================== HERO FARM BUTTON
local hero = Instance.new("Frame") hero.Size = UDim2.new(1, 0, 0, 68) hero.Position = UDim2.fromOffset(0, 52) hero.BackgroundTransparency = 1 hero.ZIndex = 3 hero.Parent = win
pad(hero, 16, 6, 16, 6)
local farmBtn = Instance.new("TextButton") farmBtn.Size = UDim2.fromScale(1, 1) farmBtn.BackgroundColor3 = C.panel farmBtn.Text = "" farmBtn.AutoButtonColor = false farmBtn.ZIndex = 3 farmBtn.Parent = hero corner(farmBtn, 12)
local farmScale = Instance.new("UIScale", farmBtn)
local farmGlow = Instance.new("ImageLabel") farmGlow.BackgroundTransparency = 1 farmGlow.Image = GLOW farmGlow.ImageColor3 = C.violet farmGlow.ImageTransparency = .6 farmGlow.ScaleType = Enum.ScaleType.Slice farmGlow.SliceCenter = Rect.new(24, 24, 276, 276) farmGlow.Size = UDim2.new(1, 44, 1, 44) farmGlow.Position = UDim2.new(0, -22, 0, -22) farmGlow.ZIndex = 2 farmGlow.Parent = hero
local farmFill = Instance.new("Frame") farmFill.Size = UDim2.fromScale(1, 1) farmFill.BackgroundColor3 = Color3.new(1, 1, 1) farmFill.BorderSizePixel = 0 farmFill.BackgroundTransparency = 1 farmFill.ZIndex = 3 farmFill.Parent = farmBtn corner(farmFill, 12)
do local g = Instance.new("UIGradient", farmFill) g.Color = GRAD_ON g.Rotation = 0 end
local farmStrokeObj, farmStrokeGrad = gradStroke(farmBtn, GRAD_BRAND, 1.6)
local _, farmSheenG = sheen(farmBtn, 12)
local farmDotW = Instance.new("Frame") farmDotW.Size = UDim2.fromOffset(28, 28) farmDotW.Position = UDim2.new(0, 14, 0.5, -14) farmDotW.BackgroundColor3 = Color3.fromRGB(255, 255, 255) farmDotW.BackgroundTransparency = .9 farmDotW.BorderSizePixel = 0 farmDotW.ZIndex = 4 farmDotW.Parent = farmBtn corner(farmDotW, 8)
local farmDot = Instance.new("Frame") farmDot.Size = UDim2.fromOffset(10, 10) farmDot.Position = UDim2.fromScale(.5, .5) farmDot.AnchorPoint = Vector2.new(.5, .5) farmDot.BackgroundColor3 = C.violet farmDot.BorderSizePixel = 0 farmDot.ZIndex = 5 farmDot.Parent = farmDotW corner(farmDot, 5)
local farmLabel = lbl(farmBtn, Enum.Font.GothamBold, 15, C.tx, "ЗАПУСТИТЬ ФАРМ") farmLabel.Position = UDim2.fromOffset(52, 13) farmLabel.Size = UDim2.new(1, -64, 0, 20) farmLabel.ZIndex = 4
local farmSub = lbl(farmBtn, Enum.Font.Gotham, 12, C.tx2, "остановлено") farmSub.Position = UDim2.fromOffset(52, 34) farmSub.Size = UDim2.new(1, -64, 0, 16) farmSub.ZIndex = 4

local farmAliveTweens = {}
local function stopAlive()
	for _, t in ipairs(farmAliveTweens) do pcall(function() t:Cancel() end) end
	farmAliveTweens = {}
end
local function startAlive()
	stopAlive()
	farmStrokeGrad.Color = GRAD_ON
	farmStrokeGrad.Rotation = 0
	farmAliveTweens[#farmAliveTweens + 1] = tw(farmStrokeGrad, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false), { Rotation = 360 })
	farmAliveTweens[#farmAliveTweens + 1] = tw(farmGlow, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { ImageTransparency = .38 })
	farmSheenG.Offset = Vector2.new(-1, 0)
	farmAliveTweens[#farmAliveTweens + 1] = tw(farmSheenG, TweenInfo.new(2.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 1.2), { Offset = Vector2.new(1, 0) })
end

--====================== TABS
local tabRegion = Instance.new("Frame") tabRegion.Size = UDim2.new(1, 0, 0, 44) tabRegion.Position = UDim2.fromOffset(0, 120) tabRegion.BackgroundTransparency = 1 tabRegion.ZIndex = 3 tabRegion.Parent = win
pad(tabRegion, 16, 4, 16, 6)
local well = Instance.new("Frame") well.Size = UDim2.fromScale(1, 1) well.BackgroundColor3 = C.well well.BorderSizePixel = 0 well.ZIndex = 3 well.Parent = tabRegion corner(well, 10)
do local s = Instance.new("UIStroke", well) s.Color = C.hair s.Transparency = .55 end
local pill = Instance.new("Frame") pill.Size = UDim2.new(0.25, -6, 1, -6) pill.Position = UDim2.new(0, 3, 0, 3) pill.BackgroundColor3 = C.raise pill.BorderSizePixel = 0 pill.ZIndex = 3 pill.Parent = well corner(pill, 8)
do local g = Instance.new("UIGradient", pill) g.Color = GRAD_BRAND g.Rotation = 0 pill.BackgroundColor3 = C.raise local f = Instance.new("Frame", pill) f.Size = UDim2.fromScale(1,1) f.BackgroundColor3 = Color3.new(1,1,1) f.BackgroundTransparency = .8 f.BorderSizePixel = 0 f.ZIndex = 3 corner(f, 8) local gg = Instance.new("UIGradient", f) gg.Color = GRAD_BRAND end
sheen(pill, 8)
local TAB_NAMES = { "Ферма", "RNG", "Шоп", "Стата" }
local tabButtons, pages = {}, {}
local content = Instance.new("Frame") content.Size = UDim2.new(1, 0, 1, -210) content.Position = UDim2.fromOffset(0, 164) content.BackgroundTransparency = 1 content.ClipsDescendants = true content.ZIndex = 3 content.Parent = win
local currentTab = 1
local function switchTab(idx)
	currentTab = idx
	tw(pill, TI.smooth, { Position = UDim2.new((idx - 1) * 0.25, 3, 0, 3) })
	for i, b in ipairs(tabButtons) do tw(b, TI.color, { TextColor3 = i == idx and C.tx or C.txM }) end
	for i, pg in ipairs(pages) do
		if i == idx then
			pg.Visible = true pg.GroupTransparency = 1
			tw(pg, TI.smooth, { GroupTransparency = 0 })
		else
			tw(pg, TI.exit, { GroupTransparency = 1 }).Completed:Once(function() if currentTab ~= i then pg.Visible = false end end)
		end
	end
end
for i, name in ipairs(TAB_NAMES) do
	local b = Instance.new("TextButton") b.Size = UDim2.new(0.25, 0, 1, 0) b.Position = UDim2.new((i - 1) * 0.25, 0, 0, 0) b.BackgroundTransparency = 1 b.Text = name b.Font = Enum.Font.GothamBold b.TextSize = 13 b.TextColor3 = i == 1 and C.tx or C.txM b.AutoButtonColor = false b.ZIndex = 4 b.Parent = well
	tabButtons[i] = b
	b.MouseButton1Click:Connect(function() switchTab(i) end)
end

local function makePage()
	local pg = Instance.new("CanvasGroup") pg.Size = UDim2.fromScale(1, 1) pg.BackgroundTransparency = 1 pg.BorderSizePixel = 0 pg.Visible = false pg.ZIndex = 3 pg.Parent = content
	local sf = Instance.new("ScrollingFrame") sf.Size = UDim2.fromScale(1, 1) sf.BackgroundTransparency = 1 sf.BorderSizePixel = 0 sf.ScrollBarThickness = 4 sf.ScrollBarImageColor3 = C.hair sf.ScrollBarImageTransparency = .4 sf.CanvasSize = UDim2.new() sf.AutomaticCanvasSize = Enum.AutomaticSize.Y sf.ZIndex = 3 sf.Parent = pg
	pad(sf, 16, 4, 16, 18)
	local list = Instance.new("UIListLayout", sf) list.Padding = UDim.new(0, 12) list.SortOrder = Enum.SortOrder.LayoutOrder
	pages[#pages + 1] = pg
	return sf
end
local function eyebrow(parent, text)
	local e = lbl(parent, Enum.Font.GothamBold, 11, C.txM, string.upper(text)) e.Size = UDim2.new(1, 0, 0, 14) e.ZIndex = 4
	return e
end

--====================== COMPONENTS
local switches = {}
local function addToggle(parent, labelText, key, onToggle)
	local row = Instance.new("Frame") row.Size = UDim2.new(1, 0, 0, 46) row.BackgroundTransparency = 1 row.ZIndex = 4 row.Parent = parent
	local lab = lbl(row, Enum.Font.GothamMedium, 14, C.tx, labelText) lab.Position = UDim2.fromOffset(14, 0) lab.Size = UDim2.new(1, -76, 1, 0) lab.ZIndex = 4
	local track = Instance.new("TextButton") track.Size = UDim2.fromOffset(46, 26) track.Position = UDim2.new(1, -60, 0.5, -13) track.BackgroundColor3 = State[key] and C.on or Color3.fromRGB(42, 42, 58) track.Text = "" track.AutoButtonColor = false track.ZIndex = 4 track.Parent = row corner(track, 13)
	local tg = Instance.new("UIGradient", track) tg.Color = GRAD_ON tg.Enabled = State[key]
	local glow = Instance.new("ImageLabel") glow.BackgroundTransparency = 1 glow.Image = GLOW glow.ImageColor3 = C.on glow.ImageTransparency = State[key] and .5 or 1 glow.ScaleType = Enum.ScaleType.Slice glow.SliceCenter = Rect.new(24, 24, 276, 276) glow.Size = UDim2.fromScale(1.8, 2.4) glow.Position = UDim2.fromScale(-.4, -.7) glow.ZIndex = 3 glow.Parent = track
	local knob = Instance.new("Frame") knob.Size = UDim2.fromOffset(20, 20) knob.Position = State[key] and UDim2.new(0, 23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10) knob.BackgroundColor3 = C.tx knob.BorderSizePixel = 0 knob.ZIndex = 5 knob.Parent = track corner(knob, 10)
	local function render(animate)
		tw(track, TI.spring, { BackgroundColor3 = State[key] and C.on or Color3.fromRGB(42, 42, 58) })
		tw(knob, TI.spring, { Position = State[key] and UDim2.new(0, 23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10) })
		tw(glow, TI.color, { ImageTransparency = State[key] and .5 or 1 })
		tg.Enabled = State[key]
	end
	track.MouseButton1Click:Connect(function() State[key] = not State[key] render(true) if onToggle then onToggle(State[key]) end end)
	switches[key] = render
	return row
end

local function addSlider(parent, labelText, key, maxV)
	local card = makeCard(parent, 58) pad(card, 14, 12, 14, 12)
	local lab = lbl(card, Enum.Font.GothamMedium, 14, C.tx, labelText) lab.Size = UDim2.new(1, -60, 0, 18) lab.ZIndex = 4
	local val = lbl(card, Enum.Font.Code, 14, C.violet, tostring(State[key])) val.Size = UDim2.new(0, 56, 0, 18) val.Position = UDim2.new(1, -56, 0, 0) val.TextXAlignment = Enum.TextXAlignment.Right val.ZIndex = 4
	local trk = Instance.new("Frame") trk.Size = UDim2.new(1, 0, 0, 6) trk.Position = UDim2.new(0, 0, 1, -8) trk.BackgroundColor3 = C.well trk.BorderSizePixel = 0 trk.ZIndex = 4 trk.Parent = card corner(trk, 3)
	local fill = Instance.new("Frame") fill.Size = UDim2.new(State[key] / maxV, 0, 1, 0) fill.BackgroundColor3 = Color3.new(1, 1, 1) fill.BorderSizePixel = 0 fill.ZIndex = 4 fill.Parent = trk corner(fill, 3)
	do local g = Instance.new("UIGradient", fill) g.Color = GRAD_BRAND end
	local knob = Instance.new("Frame") knob.Size = UDim2.fromOffset(16, 16) knob.AnchorPoint = Vector2.new(0.5, 0.5) knob.Position = UDim2.new(State[key] / maxV, 0, 0.5, 0) knob.BackgroundColor3 = C.tx knob.BorderSizePixel = 0 knob.ZIndex = 5 knob.Parent = trk corner(knob, 8)
	local hit = Instance.new("TextButton") hit.Size = UDim2.new(1, 20, 0, 28) hit.Position = UDim2.new(0, -10, 0.5, -14) hit.BackgroundTransparency = 1 hit.Text = "" hit.ZIndex = 6 hit.Parent = trk
	local dragging = false
	local function set(x)
		local rel = math.clamp((x - trk.AbsolutePosition.X) / trk.AbsoluteSize.X, 0, 1)
		local v = math.floor(rel * maxV / 10 + 0.5) * 10
		State[key] = v
		fill.Size = UDim2.new(v / maxV, 0, 1, 0)
		knob.Position = UDim2.new(v / maxV, 0, 0.5, 0)
		val.Text = tostring(v)
	end
	hit.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true tw(knob, TI.spring, { Size = UDim2.fromOffset(20, 20) }) set(i.Position.X) end end)
	track(UserInputService.InputChanged:Connect(function(i) if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then set(i.Position.X) end end))
	track(UserInputService.InputEnded:Connect(function(i) if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and dragging then dragging = false tw(knob, TI.spring, { Size = UDim2.fromOffset(16, 16) }) end end))
	return card
end

--====================== PAGE: FERMA
local pFarm = makePage()
eyebrow(pFarm, "Автоматизация")
local farmGroup = listCard(pFarm, 242)
local farmToggles = {
	{ "Спам дорогих кейкапов", "priority" }, { "Авто-покупка краски", "autoBuyPaint" },
	{ "Авто-апгрейды", "autoUpgrade" }, { "Авто-найм воркеров", "autoHire" }, { "Стоять на заправке", "park" },
}
for i, t in ipairs(farmToggles) do
	addToggle(farmGroup, t[1], t[2])
	if i < #farmToggles then divider(farmGroup, 28) end
end
eyebrow(pFarm, "Скорость (вызовов/сек, лимит 380)")
addSlider(pFarm, "Покраска", "paintRate", 380)
addSlider(pFarm, "Шаги", "stepRate", 380)

--====================== PAGE: RNG
local pRNG = makePage()
eyebrow(pRNG, "Настройки RNG")
local rngGroup = listCard(pRNG, 101)
addToggle(rngGroup, "Авто-ролл RNG", "autoRoll", function(on) if R.SetRoll then pcall(R.SetRoll.FireServer, R.SetRoll, on) end end)
divider(rngGroup, 28)
addToggle(rngGroup, "Авто-прокачка RNG", "autoRngUp")
addSlider(pRNG, "Скорость ролла", "rollRate", 200)
eyebrow(pRNG, "Улучшения")

local rngBlocks = {}
local function makeUpgradeBlock(parent, key, displayName)
	local card = makeCard(parent, 96) pad(card, 12, 12, 12, 12)
	local icon = Instance.new("Frame") icon.Size = UDim2.fromOffset(40, 40) icon.Position = UDim2.new(0, 0, 0, 0) icon.BackgroundColor3 = Color3.new(1, 1, 1) icon.BorderSizePixel = 0 icon.ZIndex = 4 icon.Parent = card corner(icon, 10)
	do local g = Instance.new("UIGradient", icon) g.Color = GRAD_HOT g.Rotation = 45 end
	local name = lbl(card, Enum.Font.GothamBold, 15, C.tx, displayName) name.Position = UDim2.fromOffset(52, 0) name.Size = UDim2.new(1, -148, 0, 20) name.ZIndex = 4
	local chip = Instance.new("Frame") chip.Size = UDim2.fromOffset(64, 18) chip.Position = UDim2.fromOffset(52, 24) chip.BackgroundColor3 = C.raise chip.BorderSizePixel = 0 chip.ZIndex = 4 chip.Parent = card corner(chip, 9)
	local chipT = lbl(chip, Enum.Font.GothamBold, 11, C.tx2, "ур. ?/?") chipT.Size = UDim2.fromScale(1, 1) chipT.TextXAlignment = Enum.TextXAlignment.Center chipT.ZIndex = 4
	local mult = lbl(card, Enum.Font.GothamBold, 13, C.cyan, "x?") mult.Position = UDim2.fromOffset(124, 24) mult.Size = UDim2.new(0, 80, 0, 18) mult.ZIndex = 4
	local barBg = Instance.new("Frame") barBg.Size = UDim2.new(1, -100, 0, 5) barBg.Position = UDim2.new(0, 52, 1, -10) barBg.BackgroundColor3 = C.well barBg.BorderSizePixel = 0 barBg.ZIndex = 4 barBg.Parent = card corner(barBg, 3)
	local barFill = Instance.new("Frame") barFill.Size = UDim2.new(0, 0, 1, 0) barFill.BackgroundColor3 = Color3.new(1, 1, 1) barFill.BorderSizePixel = 0 barFill.ZIndex = 4 barFill.Parent = barBg corner(barFill, 3)
	do local g = Instance.new("UIGradient", barFill) g.Color = GRAD_BRAND end
	local buy = Instance.new("TextButton") buy.Size = UDim2.fromOffset(80, 44) buy.Position = UDim2.new(1, -80, 0.5, -22) buy.BackgroundColor3 = Color3.new(1, 1, 1) buy.Text = "" buy.AutoButtonColor = false buy.ZIndex = 5 buy.Parent = card corner(buy, 10)
	local buyGrad = Instance.new("UIGradient", buy) buyGrad.Color = GRAD_BRAND buyGrad.Rotation = 90
	local buyT = lbl(buy, Enum.Font.GothamBold, 13, C.tx, "BUY") buyT.Size = UDim2.new(1, 0, 0, 16) buyT.Position = UDim2.fromOffset(0, 7) buyT.TextXAlignment = Enum.TextXAlignment.Center buyT.ZIndex = 5
	local buyP = lbl(buy, Enum.Font.Code, 11, Color3.fromRGB(255, 255, 255), "") buyP.Size = UDim2.new(1, 0, 0, 14) buyP.Position = UDim2.fromOffset(0, 23) buyP.TextXAlignment = Enum.TextXAlignment.Center buyP.ZIndex = 5
	buy.MouseButton1Click:Connect(function()
		if R.BuyRNG then pcall(R.BuyRNG.FireServer, R.BuyRNG, key) end
		tw(buy, TI.press, { Size = UDim2.fromOffset(74, 40) }).Completed:Once(function() tw(buy, TI.spring, { Size = UDim2.fromOffset(80, 44) }) end)
	end)
	rngBlocks[key] = { chip = chipT, mult = mult, bar = barFill, buy = buy, buyT = buyT, buyP = buyP, buyGrad = buyGrad }
end
makeUpgradeBlock(pRNG, "RollLuck", "Roll Luck")
makeUpgradeBlock(pRNG, "RollSpeed", "Roll Speed")

--====================== PAGE: SHOP
local pShop = makePage()
eyebrow(pShop, "Краска")
local shopPaintCard = makeCard(pShop, 76) pad(shopPaintCard, 14, 12, 14, 12)
local swatch = Instance.new("Frame") swatch.Size = UDim2.fromOffset(44, 44) swatch.Position = UDim2.fromOffset(0, 4) swatch.BackgroundColor3 = C.violet swatch.BorderSizePixel = 0 swatch.ZIndex = 4 swatch.Parent = shopPaintCard corner(swatch, 10)
do local s = Instance.new("UIStroke", swatch) s.Color = Color3.new(1, 1, 1) s.Transparency = .6 end
local shopPaintName = lbl(shopPaintCard, Enum.Font.GothamBold, 16, C.tx, "—") shopPaintName.Position = UDim2.fromOffset(56, 4) shopPaintName.Size = UDim2.new(1, -60, 0, 20) shopPaintName.ZIndex = 4
local shopPaintMult = lbl(shopPaintCard, Enum.Font.GothamMedium, 12, C.cyan, "") shopPaintMult.Position = UDim2.fromOffset(56, 26) shopPaintMult.Size = UDim2.new(1, -60, 0, 16) shopPaintMult.ZIndex = 4
local shopNext = lbl(shopPaintCard, Enum.Font.Gotham, 11, C.txM, "") shopNext.Position = UDim2.fromOffset(56, 44) shopNext.Size = UDim2.new(1, -60, 0, 16) shopNext.ZIndex = 4
eyebrow(pShop, "Апгрейды")
local shopUpCard = listCard(pShop, 171)
local shopUpRows = {}
for i, k in ipairs(UPGRADE_PRIORITY) do
	local row = Instance.new("Frame") row.Size = UDim2.new(1, 0, 0, 40) row.BackgroundTransparency = 1 row.ZIndex = 4 row.Parent = shopUpCard
	local n = lbl(row, Enum.Font.GothamMedium, 13, C.tx, k) n.Position = UDim2.fromOffset(14, 0) n.Size = UDim2.new(1, -120, 1, 0) n.ZIndex = 4
	local info = lbl(row, Enum.Font.Code, 12, C.tx2, "") info.Position = UDim2.new(1, -110, 0, 0) info.Size = UDim2.new(0, 96, 1, 0) info.TextXAlignment = Enum.TextXAlignment.Right info.ZIndex = 4
	if i < #UPGRADE_PRIORITY then divider(shopUpCard, 28) end
	shopUpRows[k] = info
end
eyebrow(pShop, "Производство")
local shopWorkCard = makeCard(pShop, 44) pad(shopWorkCard, 14, 0, 14, 0)
local shopWorkT = lbl(shopWorkCard, Enum.Font.GothamMedium, 13, C.tx, "") shopWorkT.Size = UDim2.fromScale(1, 1) shopWorkT.ZIndex = 4

--====================== PAGE: STATS
local pStats = makePage()
local statGrid = Instance.new("Frame") statGrid.Size = UDim2.new(1, 0, 0, 216) statGrid.BackgroundTransparency = 1 statGrid.ZIndex = 4 statGrid.Parent = pStats
local grid = Instance.new("UIGridLayout", statGrid) grid.CellSize = UDim2.new(0.5, -6, 0, 64) grid.CellPadding = UDim2.fromOffset(12, 12) grid.SortOrder = Enum.SortOrder.LayoutOrder
local statTiles = {}
local STAT_DEFS = { { "money", "Деньги", C.gold }, { "income", "Доход/сек", C.on }, { "fuel", "Топливо", Color3.fromRGB(255, 184, 76) }, { "workers", "Воркеры", C.cyan }, { "rebirths", "Ребёрты", C.violet }, { "rng", "RNG ур.", Color3.fromRGB(178, 107, 255) } }
for _, sd in ipairs(STAT_DEFS) do
	local tile = makeCard(statGrid, 64) pad(tile, 12, 10, 12, 10)
	local accent = Instance.new("Frame") accent.Size = UDim2.fromOffset(3, 28) accent.Position = UDim2.new(0, -6, 0.5, -14) accent.BackgroundColor3 = Color3.new(1, 1, 1) accent.BorderSizePixel = 0 accent.ZIndex = 4 accent.Parent = tile corner(accent, 2)
	do local g = Instance.new("UIGradient", accent) g.Color = GRAD_BRAND g.Rotation = 90 end
	local e = lbl(tile, Enum.Font.Gotham, 11, C.txM, string.upper(sd[2])) e.Size = UDim2.new(1, 0, 0, 14) e.ZIndex = 4
	local v = lbl(tile, Enum.Font.Code, 19, sd[3], "—") v.Position = UDim2.fromOffset(0, 18) v.Size = UDim2.new(1, 0, 0, 24) v.ZIndex = 4
	statTiles[sd[1]] = v
end
eyebrow(pStats, "Лучший аксессуар")
local bestCard = makeCard(pStats, 60) pad(bestCard, 12, 0, 12, 0)
local bestTile = Instance.new("Frame") bestTile.Size = UDim2.fromOffset(40, 40) bestTile.Position = UDim2.new(0, 0, 0.5, -20) bestTile.BackgroundColor3 = C.violet bestTile.BorderSizePixel = 0 bestTile.ZIndex = 4 bestTile.Parent = bestCard corner(bestTile, 10)
local bestName = lbl(bestCard, Enum.Font.GothamBold, 15, C.tx, "—") bestName.Position = UDim2.fromOffset(52, 12) bestName.Size = UDim2.new(1, -120, 0, 20) bestName.ZIndex = 4
local bestMult = lbl(bestCard, Enum.Font.Code, 16, C.gold, "") bestMult.Position = UDim2.new(1, -70, 0.5, -12) bestMult.Size = UDim2.fromOffset(60, 24) bestMult.TextXAlignment = Enum.TextXAlignment.Right bestMult.ZIndex = 4
eyebrow(pStats, "Топ аксессуаров")
local accListCard = listCard(pStats, 192)
local accRows = {}
for i = 1, 5 do
	local row = Instance.new("Frame") row.Size = UDim2.new(1, 0, 0, 36) row.BackgroundTransparency = 1 row.ZIndex = 4 row.Parent = accListCard
	local bar = Instance.new("Frame") bar.Size = UDim2.fromOffset(3, 18) bar.Position = UDim2.new(0, 10, 0.5, -9) bar.BackgroundColor3 = C.txM bar.BorderSizePixel = 0 bar.ZIndex = 4 bar.Parent = row corner(bar, 2)
	local rank = lbl(row, Enum.Font.Code, 12, C.txM, "#" .. i) rank.Position = UDim2.fromOffset(20, 0) rank.Size = UDim2.fromOffset(24, 36) rank.ZIndex = 4
	local nm = lbl(row, Enum.Font.GothamMedium, 13, C.tx, "—") nm.Position = UDim2.fromOffset(46, 0) nm.Size = UDim2.new(1, -130, 1, 0) nm.ZIndex = 4
	local vv = lbl(row, Enum.Font.Code, 13, C.tx2, "") vv.Position = UDim2.new(1, -76, 0, 0) vv.Size = UDim2.fromOffset(64, 36) vv.TextXAlignment = Enum.TextXAlignment.Right vv.ZIndex = 4
	if i < 5 then divider(accListCard, 24) end
	accRows[i] = { bar = bar, nm = nm, vv = vv }
end

--====================== FOOTER
local footer = Instance.new("Frame") footer.AnchorPoint = Vector2.new(0, 1) footer.Position = UDim2.fromScale(0, 1) footer.Size = UDim2.new(1, 0, 0, 46) footer.BackgroundColor3 = Color3.fromRGB(11, 11, 18) footer.BorderSizePixel = 0 footer.ZIndex = 3 footer.Parent = win
divider(footer, 0).Position = UDim2.new(0, 0, 0, 0)
pad(footer, 16, 0, 16, 0)
local footCells = {}
local FOOT_DEFS = { { "money", "ДЕНЬГИ", C.gold }, { "income", "ДОХОД/С", C.on }, { "paint", "КРАСКА", C.cyan }, { "caps", "КЕЙКАПЫ", C.tx2 } }
for i, fd in ipairs(FOOT_DEFS) do
	local cell = Instance.new("Frame") cell.Size = UDim2.new(0.25, 0, 1, 0) cell.Position = UDim2.new((i - 1) * 0.25, 0, 0, 0) cell.BackgroundTransparency = 1 cell.ZIndex = 3 cell.Parent = footer
	local e = lbl(cell, Enum.Font.GothamBold, 9, C.txM, fd[2]) e.Size = UDim2.new(1, 0, 0, 12) e.Position = UDim2.fromOffset(0, 9) e.ZIndex = 3
	local v = lbl(cell, Enum.Font.Code, 13, fd[3], "—") v.Size = UDim2.new(1, 0, 0, 16) v.Position = UDim2.fromOffset(0, 21) v.ZIndex = 3
	if i > 1 then local dv = Instance.new("Frame", cell) dv.Size = UDim2.fromOffset(1, 20) dv.Position = UDim2.new(0, -1, 0.5, -10) dv.BackgroundColor3 = C.hair dv.BackgroundTransparency = .4 dv.BorderSizePixel = 0 dv.ZIndex = 3 end
	footCells[fd[1]] = v
end

--====================== BEHAVIOR
local function setFarmVisual()
	if State.farm then
		farmLabel.Text = "ОСТАНОВИТЬ ФАРМ" farmSub.Text = "работает" farmFill.BackgroundTransparency = 0
		tw(farmDot, TI.fast, { BackgroundColor3 = C.on }) tw(farmDotW, TI.fast, { BackgroundColor3 = C.on })
		tw(dot, TI.fast, { BackgroundColor3 = C.on }) dotGlow.ImageColor3 = C.on
		startAlive()
	else
		farmLabel.Text = "ЗАПУСТИТЬ ФАРМ" farmSub.Text = "остановлено" tw(farmFill, TI.base, { BackgroundTransparency = 1 })
		farmStrokeGrad.Color = GRAD_BRAND
		tw(farmDot, TI.fast, { BackgroundColor3 = C.violet }) tw(farmDotW, TI.fast, { BackgroundColor3 = Color3.fromRGB(255,255,255) })
		tw(dot, TI.fast, { BackgroundColor3 = C.bad }) dotGlow.ImageColor3 = C.bad
		tw(farmGlow, TI.base, { ImageTransparency = .6 })
		stopAlive()
	end
end
farmBtn.MouseButton1Click:Connect(function()
	State.farm = not State.farm
	if State.farm then refreshRefill() capsDirty = true end
	tw(farmScale, TI.press, { Scale = 0.97 }).Completed:Once(function() tw(farmScale, TI.spring, { Scale = 1 }) end)
	setFarmVisual()
end)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	tw(win, TI.smooth, { Size = minimized and UDim2.fromOffset(WIN_W, 52) or UDim2.fromOffset(WIN_W, WIN_H) })
	task.delay(0.06, syncShadow)
end)

do
	local dragging, startPos, startMouse
	header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging, startPos, startMouse = true, win.Position, i.Position end
	end)
	track(UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local delta = i.Position - startMouse
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			syncShadow()
		end
	end))
	track(UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))
end

local prevMoney, incomePerSec, displayMoney = nil, 0, 0
local function bestAccessory()
	local best, bestM, counts = "—", 0, {}
	for _, c in ipairs(caps) do
		local a = c:GetAttribute(ACC_ATTR)
		if type(a) == "string" then counts[a] = (counts[a] or 0) + 1 local m = NAME_MULT[a] or 0 if m > bestM then bestM, best = m, a end end
	end
	return best, bestM, counts
end

local function refreshUI()
	local d = lastData
	if not d then return end
	local m = d.Money or 0
	if prevMoney then incomePerSec = incomePerSec * 0.6 + (m - prevMoney) * 0.4 end
	prevMoney = m
	displayMoney = displayMoney + (m - displayMoney) * 0.3
	local eq = d.EquippedPaint or "?"
	local _, bestR = bestOwnedPaint(d)

	footCells.money.Text = "$" .. abbr(displayMoney)
	footCells.income.Text = "+" .. abbr(incomePerSec)
	footCells.paint.Text = tostring(eq)
	footCells.caps.Text = tostring(#caps)

	statTiles.money.Text = "$" .. abbr(m)
	statTiles.income.Text = "+" .. abbr(incomePerSec)
	statTiles.fuel.Text = abbr(d.Paint or 0)
	statTiles.workers.Text = string.format("%d/%d", d.Workers or 0, d.WorkerCapacity or 0)
	statTiles.rebirths.Text = tostring(d.Rebirths or 0)
	statTiles.rng.Text = string.format("%s/%s", tostring(d.RNGUpgrades and d.RNGUpgrades.RollLuck or 0), tostring(d.RNGUpgrades and d.RNGUpgrades.RollSpeed or 0))

	-- shop
	local pcol
	pcall(function() local def = PaintCfg.Paints[eq] if def and def.color then pcol = def.color end end)
	if pcol then swatch.BackgroundColor3 = pcol end
	shopPaintName.Text = tostring(eq)
	shopPaintMult.Text = "×" .. tostring(bestR ~= -1 and bestR or "?") .. " за кейкап"
	local target, cost = nextAffordablePaint(d)
	shopNext.Text = target and ("след: " .. target .. "  $" .. abbr(cost)) or "лучшая доступная куплена"
	if d.Upgrades and UpCfg then
		for _, k in ipairs(UPGRADE_PRIORITY) do
			local lvl = d.Upgrades[k]
			local _, cst = pcall(UpCfg.getUpgradeCost, k, lvl or 0)
			local _, mx = pcall(UpCfg.getMaxLevel, k)
			local isMax = (type(mx) == "number" and type(lvl) == "number" and lvl >= mx)
			shopUpRows[k].Text = isMax and ("MAX " .. tostring(lvl)) or string.format("%s/%s $%s", tostring(lvl), tostring(mx), abbr(type(cst) == "number" and cst or 0))
		end
	end
	shopWorkT.Text = string.format("Воркеры <font color='#56C0FF'>%d/%d</font>      Топливо <font color='#FFB84C'>%s</font>", d.Workers or 0, d.WorkerCapacity or 0, abbr(d.Paint or 0))

	-- rng blocks
	if d.RNGUpgrades and RngUpCfg then
		for _, key in ipairs(RNG_KEYS) do
			local blk = rngBlocks[key]
			if blk then
				local lvl = d.RNGUpgrades[key] or 0
				local _, cst = pcall(RngUpCfg.getRNGUpgradeCost, key, lvl)
				local _, mx = pcall(RngUpCfg.getMaxLevel, key)
				local _, val = pcall(RngUpCfg.getRNGUpgradeValue, key, lvl)
				local isMax = (type(mx) == "number" and lvl >= mx)
				blk.chip.Text = "ур. " .. tostring(lvl) .. "/" .. tostring(mx)
				blk.mult.Text = "x" .. tostring(type(val) == "number" and math.floor(val * 100) / 100 or "?")
				blk.bar.Size = UDim2.new(type(mx) == "number" and mx > 0 and math.clamp(lvl / mx, 0, 1) or 0, 0, 1, 0)
				if isMax then
					blk.buyT.Text = "MAX" blk.buyP.Text = "" blk.buyGrad.Enabled = false blk.buy.BackgroundColor3 = C.raise
				else
					blk.buyT.Text = "BUY" blk.buyP.Text = "$" .. abbr(type(cst) == "number" and cst or 0) blk.buyGrad.Enabled = true blk.buy.BackgroundColor3 = Color3.new(1, 1, 1)
				end
			end
		end
	end

	-- stats: best + list
	local ba, bm, counts = bestAccessory()
	bestName.Text = tostring(ba) bestMult.Text = "x" .. tostring(bm)
	local bc = rarityColor(bm) bestTile.BackgroundColor3 = bc bestMult.TextColor3 = bc
	local arr = {}
	for n, cc in pairs(counts) do arr[#arr + 1] = { n, cc, NAME_MULT[n] or 0 } end
	table.sort(arr, function(a, b) return a[3] > b[3] end)
	for i = 1, 5 do
		local r = accRows[i]
		if arr[i] then
			local col = rarityColor(arr[i][3])
			r.bar.BackgroundColor3 = col r.nm.Text = arr[i][1] r.vv.Text = "x" .. tostring(arr[i][3]) .. "  ×" .. tostring(arr[i][2]) r.vv.TextColor3 = col
		else r.nm.Text = "—" r.vv.Text = "" r.bar.BackgroundColor3 = C.txM end
	end
end

--====================== START
track(RunService.Heartbeat:Connect(farmStep))
track(lp.CharacterAdded:Connect(onCharacter))
track(lp.Idled:Connect(function()
	pcall(function() VirtualUser:CaptureController() end)
	pcall(function() VirtualUser:ClickButton2(Vector2.new()) end)
end))

if lp.Character then hrp = lp.Character:FindFirstChild("HumanoidRootPart") end
refreshRefill() rebuildCaps() readData() resortCaps()
do local b = bestOwnedPaint(lastData or {}) if b then bestPaint = b end end
displayMoney = (lastData and lastData.Money) or 0
setFarmVisual()
switchTab(1)
task.defer(syncShadow)

winScale.Scale = winScale.Scale * 0.94
win.Position = UDim2.new(0.5, 0, 0.5, 14)
local introS = winScale.Scale / 0.94
tw(winScale, TI.big, { Scale = introS })
tw(win, TI.smooth, { Position = UDim2.fromScale(0.5, 0.5) }).Completed:Once(syncShadow)

task.spawn(function()
	while running do pcall(manage) pcall(refreshUI) for _ = 1, 18 do if not running then break end task.wait(0.1) end end
end)
task.spawn(function()
	while running do pcall(refreshUI) task.wait(0.15) end
end)

--====================== UNLOAD
local function unload()
	running = false
	State.farm = false
	if R.SetRoll then pcall(R.SetRoll.FireServer, R.SetRoll, false) end
	stopAlive()
	for _, t in ipairs(loopTweens) do pcall(function() t:Cancel() end) end
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	conns = {}
	tw(win, TI.exit, { Size = UDim2.fromOffset(WIN_W, 0) })
	tw(winScale, TI.exit, { Scale = 0.9 })
	pcall(function() amb:Destroy() end) pcall(function() con:Destroy() end)
	task.delay(0.22, function() pcall(function() gui:Destroy() end) end)
	_G.PMK_Unload = nil
	_G.PMK = nil
end
_G.PMK_Unload = unload
closeBtn.MouseButton1Click:Connect(unload)

notify("Загружено ✓")
