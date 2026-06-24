local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local lp = Players.LocalPlayer

if getgenv then
	local prev = getgenv().__BackroomsAF
	if type(prev) == "function" then pcall(prev) end
end

local State = {
	running = true,
	autoKill = false,
	autoTokens = false,
	autoMinigames = false,
	includeBoss = false,
	attackType = "M1",
	moveMode = "Teleport",
	moveSpeed = 180,
	killSettle = 0.18,
	tokenSettle = 0.6,
	actionsPerSec = 3,
	currentAction = "Idle",
	minigamesSolved = 0,
	tokensLooted = 0,
	startKills = 0,
	startEXP = 0,
	startCredits = 0,
}

local connections = {}
local function addConn(conn)
	connections[#connections + 1] = conn
	return conn
end

local function getChar()
	return lp.Character
end
local function getHRP()
	local c = lp.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
	local c = lp.Character
	return c and c:FindFirstChildOfClass("Humanoid")
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

local function findMelee()
	local char = lp.Character
	if not char then return nil end
	local function valid(t)
		return t:IsA("Tool") and t:FindFirstChild("MeleeStats") and t:FindFirstChild("Remotes") and t.Remotes:FindFirstChild("OnHit")
	end
	local tool
	for _, t in ipairs(char:GetChildren()) do
		if valid(t) then tool = t break end
	end
	if not tool then
		for _, t in ipairs(lp.Backpack:GetChildren()) do
			if valid(t) then tool = t break end
		end
	end
	if not tool then return nil end
	if tool.Parent ~= char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:EquipTool(tool)
			task.wait(0.15)
		end
	end
	local hitRange = 3.5
	pcall(function()
		local s = require(tool.MeleeStats)
		if type(s) == "table" and tonumber(s.hitRange) then hitRange = s.hitRange end
	end)
	return tool, tool.Remotes.OnHit, hitRange
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
						if not bestDist or d < bestDist then
							best, bestHum, bestRoot, bestDist = m, h, r, d
						end
					end
				end
			end
		end
	end
	return best, bestHum, bestRoot, bestDist
end

local function nearestToken()
	local hrp = getHRP()
	if not hrp then return nil end
	local g = workspace:FindFirstChild("Game")
	local items = g and g:FindFirstChild("Items")
	local cache = items and (items:FindFirstChild("Cache") or items)
	if not cache then return nil end
	local best, bestDist
	for _, m in ipairs(cache:GetChildren()) do
		if m:IsA("Model") and (m.Name == "Coin" or m.Name:match("^Card")) then
			local prompt
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d.Enabled then prompt = d break end
			end
			if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
				local dist = (prompt.Parent.Position - hrp.Position).Magnitude
				if not bestDist or dist < bestDist then
					best, bestDist = { model = m, prompt = prompt, part = prompt.Parent }, dist
				end
			end
		end
	end
	return best, bestDist
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
		while State.running and not done and t < 6 do
			task.wait(0.03)
			t = t + 0.03
		end
		if not done then pcall(function() tw:Cancel() end) end
		task.wait(settle or 0.2)
	else
		hrp.CFrame = dest
		task.wait(settle or 0.35)
	end
	return true
end

local function approachNPC(root, hitRange)
	local hrp = getHRP()
	if not hrp then return false end
	local dir = hrp.Position - root.Position
	dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, 1)
	local dest = CFrame.new(root.Position + dir * (hitRange - 1.2), root.Position)
	return gotoCFrame(dest, State.killSettle)
end

local function doKill(npc, hum, root, tool, onhit, hitRange)
	local interval = 1 / math.clamp(State.actionsPerSec, 0.5, 20)
	local swings = 0
	while State.running and State.autoKill and npc.Parent and hum.Health > 0 and swings < 40 do
		local hrp = getHRP()
		local char = lp.Character
		if not (hrp and char) then break end
		if tool.Parent ~= char then
			local myHum = char:FindFirstChildOfClass("Humanoid")
			if myHum then myHum:EquipTool(tool) end
			task.wait(0.15)
		end
		local dir = hrp.Position - root.Position
		dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, 1)
		hrp.CFrame = CFrame.new(root.Position + dir * (hitRange - 1.2), root.Position)
		task.wait(0.05)
		pcall(function() onhit:FireServer(hum, State.attackType) end)
		swings = swings + 1
		State.currentAction = "Killing " .. npc.Name
		task.wait(interval)
	end
end

local function grabToken(tk)
	State.currentAction = "Looting " .. tk.model.Name
	gotoCFrame(CFrame.new(tk.part.Position + Vector3.new(0, 3, 0)), State.tokenSettle)
	for _ = 1, 3 do
		if not tk.model.Parent then break end
		pcall(function() fireproximityprompt(tk.prompt) end)
		task.wait(0.22)
	end
	if not tk.model.Parent then
		State.tokensLooted = State.tokensLooted + 1
	end
end

task.spawn(function()
	while State.running do
		local didSomething = false
		local hrp = getHRP()
		if hrp then
			local candidates = {}
			if State.autoKill then
				local npc, hum, root, dist = nearestNPC()
				if npc then candidates[#candidates + 1] = { kind = "kill", dist = dist, prio = 0, npc = npc, hum = hum, root = root } end
			end
			if State.autoTokens and fireproximityprompt then
				local tk, dist = nearestToken()
				if tk then candidates[#candidates + 1] = { kind = "token", dist = dist, prio = 1, tk = tk } end
			end
			if #candidates > 0 then
				table.sort(candidates, function(a, b)
					if math.abs(a.dist - b.dist) < 8 then return a.prio < b.prio end
					return a.dist < b.dist
				end)
				local c = candidates[1]
				if c.kind == "kill" then
					local tool, onhit, hitRange = findMelee()
					if tool and onhit then
						approachNPC(c.root, hitRange)
						doKill(c.npc, c.hum, c.root, tool, onhit, hitRange)
						didSomething = true
					end
				elseif c.kind == "token" then
					grabToken(c.tk)
					didSomething = true
				end
			end
		end
		if not didSomething then
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
						State.minigamesSolved = State.minigamesSolved + 1
					end
				elseif swipe and swipe:FindFirstChild("Finished") then
					task.wait(0.8)
					if swipe.Parent then
						pcall(function() swipe.Finished:FireServer() end)
						local ce = swipe:FindFirstChild("CloseEvent")
						if ce then pcall(function() ce:FireServer() end) end
						State.minigamesSolved = State.minigamesSolved + 1
					end
				end
			end
		end
		task.wait(0.4)
	end
end)

local COL = {
	bg = Color3.fromRGB(18, 18, 21),
	panel = Color3.fromRGB(30, 30, 35),
	panel2 = Color3.fromRGB(38, 38, 44),
	accent = Color3.fromRGB(240, 196, 25),
	on = Color3.fromRGB(64, 184, 99),
	off = Color3.fromRGB(72, 72, 80),
	danger = Color3.fromRGB(206, 70, 64),
	text = Color3.fromRGB(236, 236, 238),
	sub = Color3.fromRGB(150, 150, 158),
	knob = Color3.fromRGB(246, 246, 248),
}

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end
local function stroke(inst, col, thick, trans)
	local s = Instance.new("UIStroke")
	s.Color = col
	s.Thickness = thick or 1
	s.Transparency = trans or 0
	s.Parent = inst
	return s
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
	if not mounted then
		pcall(function() screenGui.Parent = game:GetService("CoreGui") mounted = true end)
	end
	if not mounted then
		screenGui.Parent = lp:WaitForChild("PlayerGui")
	end
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 332, 0, 484)
main.Position = UDim2.new(0, 24, 0.5, -242)
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
local titleBarFix = Instance.new("Frame")
titleBarFix.Size = UDim2.new(1, 0, 0, 14)
titleBarFix.Position = UDim2.new(0, 0, 1, -14)
titleBarFix.BackgroundColor3 = COL.panel
titleBarFix.BorderSizePixel = 0
titleBarFix.Parent = titleBar

local accentDot = Instance.new("Frame")
accentDot.Size = UDim2.new(0, 10, 0, 10)
accentDot.Position = UDim2.new(0, 14, 0.5, -5)
accentDot.BackgroundColor3 = COL.accent
accentDot.BorderSizePixel = 0
accentDot.Parent = titleBar
corner(accentDot, 5)

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
minBtn.AutoButtonColor = true
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
closeBtn.AutoButtonColor = true
closeBtn.Parent = titleBar
corner(closeBtn, 7)

local body = Instance.new("ScrollingFrame")
body.Size = UDim2.new(1, -16, 1, -52)
body.Position = UDim2.new(0, 8, 0, 48)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 3
body.ScrollBarImageColor3 = COL.accent
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = main
local bodyLayout = Instance.new("UIListLayout")
bodyLayout.Padding = UDim.new(0, 7)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Parent = body

local function section(text)
	local l = label(body, string.upper(text), 11, COL.accent, Enum.Font.GothamBold)
	l.Size = UDim2.new(1, -4, 0, 16)
	l.Text = string.upper(text)
end

local function makeToggle(text, default, cb)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 36)
	row.BackgroundColor3 = COL.panel
	row.BorderSizePixel = 0
	row.Parent = body
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

local function makeCycle(text, options, defaultIndex, cb)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 36)
	row.BackgroundColor3 = COL.panel
	row.BorderSizePixel = 0
	row.Parent = body
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
	btn.AutoButtonColor = true
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

local function makeSlider(text, minV, maxV, default, decimals, suffix, cb)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -4, 0, 50)
	row.BackgroundColor3 = COL.panel
	row.BorderSizePixel = 0
	row.Parent = body
	corner(row, 8)
	local l = label(row, text, 13, COL.text, Enum.Font.GothamMedium)
	l.Position = UDim2.new(0, 12, 0, 7)
	l.Size = UDim2.new(1, -90, 0, 16)
	local valLbl = label(row, "", 13, COL.accent, Enum.Font.GothamBold)
	valLbl.Position = UDim2.new(1, -80, 0, 7)
	valLbl.Size = UDim2.new(0, 68, 0, 16)
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -24, 0, 6)
	track.Position = UDim2.new(0, 12, 0, 34)
	track.BackgroundColor3 = COL.off
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 3)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COL.accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track
	corner(fill, 3)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.BackgroundColor3 = COL.knob
	knob.BorderSizePixel = 0
	knob.Parent = track
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
		apply((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1))
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromInput(input)
		end
	end)
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	addConn(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input)
		end
	end))
	addConn(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

section("Farming")
makeToggle("Auto Kill  (EXP + Credits)", false, function(v) State.autoKill = v end)
makeToggle("Auto Loot Tokens  (Credits)", false, function(v) State.autoTokens = v end)
makeToggle("Auto-Solve Minigames", false, function(v) State.autoMinigames = v end)

section("Combat")
makeCycle("Attack Type", { "M1", "M2" }, 1, function(v) State.attackType = v end)
makeToggle("Target Bosses Too", false, function(v) State.includeBoss = v end)
makeSlider("Attacks / sec", 1, 12, 3, 0, "", function(v) State.actionsPerSec = v end)

section("Movement")
makeCycle("Mode", { "Teleport", "Tween", "Walk" }, 1, function(v) State.moveMode = v end)
makeSlider("Tween Speed", 60, 400, 180, 0, "", function(v) State.moveSpeed = v end)
makeSlider("Token Settle", 0.2, 1.2, 0.6, 2, "s", function(v) State.tokenSettle = v end)

section("Status")
local statusPanel = Instance.new("Frame")
statusPanel.Size = UDim2.new(1, -4, 0, 116)
statusPanel.BackgroundColor3 = COL.panel
statusPanel.BorderSizePixel = 0
statusPanel.Parent = body
corner(statusPanel, 8)
local statePad = Instance.new("UIPadding")
statePad.PaddingLeft = UDim.new(0, 12)
statePad.PaddingTop = UDim.new(0, 8)
statePad.Parent = statusPanel
local stateList = Instance.new("UIListLayout")
stateList.Padding = UDim.new(0, 3)
stateList.Parent = statusPanel
local function statLine()
	local l = label(statusPanel, "", 12, COL.text, Enum.Font.GothamMedium)
	l.Size = UDim2.new(1, -16, 0, 16)
	return l
end
local lblAction = statLine()
local lblKills = statLine()
local lblEXP = statLine()
local lblCredits = statLine()
local lblExtra = statLine()

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -4, 0, 38)
unloadBtn.BackgroundColor3 = COL.danger
unloadBtn.Text = "Unload"
unloadBtn.TextColor3 = COL.text
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.TextSize = 14
unloadBtn.AutoButtonColor = true
unloadBtn.Parent = body
corner(unloadBtn, 8)

track(RunService.Heartbeat:Connect(function()
	lblAction.Text = "Action:  " .. State.currentAction
	lblKills.Text = "Kills:  +" .. (statValue("NPC Kills") - State.startKills)
	lblEXP.Text = "EXP:  +" .. (statValue("EXP") - State.startEXP)
	lblCredits.Text = "Credits:  +" .. (statValue("Credits") - State.startCredits)
	lblExtra.Text = "Tokens:  " .. State.tokensLooted .. "    Minigames:  " .. State.minigamesSolved
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
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	track(UserInputService.InputChanged:Connect(function(input)
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
		body.Visible = false
		TweenService:Create(main, TweenInfo.new(0.18), { Size = UDim2.new(savedSize.X.Scale, savedSize.X.Offset, 0, 42) }):Play()
	else
		TweenService:Create(main, TweenInfo.new(0.18), { Size = savedSize }):Play()
		task.wait(0.18)
		body.Visible = true
	end
end)

local afkConn = lp.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end)
track(afkConn)

local function unload()
	State.running = false
	State.autoKill = false
	State.autoTokens = false
	State.autoMinigames = false
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	pcall(function() screenGui:Destroy() end)
	if getgenv then getgenv().__BackroomsAF = nil end
end

closeBtn.MouseButton1Click:Connect(unload)
unloadBtn.MouseButton1Click:Connect(unload)

if getgenv then getgenv().__BackroomsAF = unload end
