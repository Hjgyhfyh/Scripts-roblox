local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

if _G.__SHAWARMA_AFK and _G.__SHAWARMA_AFK.unload then
	pcall(_G.__SHAWARMA_AFK.unload)
end

local Suite = {}
_G.__SHAWARMA_AFK = Suite

local Codes = {

}

local Config = {
	AutoBoost = true,
	AutoServe = false,
	AutoBooger = false,
	BoostKeys = { "2xEarn", "Tips" },
}

local connections = {}
local threads = {}
local alive = true

local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

local function spawnLoop(fn)
	local t = task.spawn(fn)
	table.insert(threads, t)
	return t
end

local palette = {
	bg = Color3.fromRGB(20, 18, 30),
	panel = Color3.fromRGB(28, 25, 42),
	element = Color3.fromRGB(38, 34, 56),
	elementHi = Color3.fromRGB(48, 43, 70),
	violet = Color3.fromRGB(138, 99, 247),
	indigo = Color3.fromRGB(99, 102, 241),
	cyan = Color3.fromRGB(56, 189, 248),
	text = Color3.fromRGB(236, 233, 246),
	sub = Color3.fromRGB(150, 145, 172),
	green = Color3.fromRGB(74, 222, 128),
	red = Color3.fromRGB(248, 113, 113),
	amber = Color3.fromRGB(251, 191, 36),
}

local logLabel

local function pushLog(text, color)
	if logLabel then
		logLabel.TextColor3 = color or palette.sub
		logLabel.Text = text
	end
end

local function resolve(parent, name)
	if not parent then return nil end
	return parent:FindFirstChild(name)
end

local remotesFolder = resolve(ReplicatedStorage, "Remotes")
local mouseHolded = resolve(ReplicatedStorage, "MouseHolded")
local serverRemote = mouseHolded and resolve(mouseHolded, "Server")
local useBoost = resolve(ReplicatedStorage, "UseBoost")
local updateHint = resolve(ReplicatedStorage, "UpdateHint")
local redeemCode = remotesFolder and resolve(remotesFolder, "RedeemCode")
local boogerChoice = remotesFolder and resolve(remotesFolder, "BoogerChoice")
local totalDays = resolve(ReplicatedStorage, "TotalDays")
local adFolder = resolve(ReplicatedStorage, "AdRewardEvents")
local dailyClaim = adFolder and resolve(adFolder, "DailyClaim")

local kit = resolve(workspace, "Kit")
local kitGives = kit and resolve(kit, "GIVES")
local kitClients = kit and resolve(kit, "Clients")
local kitShift = kit and resolve(kit, "Shift")
local kitBooger = kit and resolve(kit, "BOOGER")
local kitTimer = kit and resolve(kit, "Timer")

local function getIncome()
	local stats = LocalPlayer:FindFirstChild("leaderstats")
	local inc = stats and stats:FindFirstChild("Income")
	return inc and inc.Value or nil
end

local function fireProx(prompt)
	if typeof(fireproximityprompt) == "function" then
		pcall(fireproximityprompt, prompt)
		return true
	end
	return false
end

local function antiAfk()
	bind(LocalPlayer.Idled, function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end)
end

local usedThisShift = {}

local function popBoosts()
	if not Config.AutoBoost or not useBoost then return end
	for _, key in ipairs(Config.BoostKeys) do
		if not usedThisShift[key] then
			usedThisShift[key] = true
			pcall(function() useBoost:FireServer(key) end)
			task.wait(0.4)
		end
	end
	pushLog("Бусты на смену отправлены (2xEarn / Tips)", palette.green)
end

local function setupBoosts()
	if dailyClaim then pcall(function() dailyClaim:FireServer() end) end
	popBoosts()
	if kitShift then
		bind(kitShift.Changed, function()
			if kitShift.Value == true then
				usedThisShift = {}
				task.wait(1)
				popBoosts()
			end
		end)
	end
end

local hintMap = {
	cheese = "Cheese",
	salad = "Salad",
	lavash = "Lavash",
	sauce = "Sauce",
	meat = "shawerma",
	fry = "Fry",
	fries = "Fry",
	roll = "Board",
	cola = "popcan",
	soda = "popcan",
	drink = "popcan",
}

local function triggerStation(model)
	if not model then return false end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			return fireProx(d)
		end
	end
	if serverRemote then
		local part = model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart", true)
		if part then
			pcall(function() serverRemote:FireServer(part) end)
			return true
		end
	end
	return false
end

local function handleHint(text)
	if not Config.AutoServe or not kit then return end
	if typeof(text) ~= "string" then return end
	local lower = text:lower()
	for keyword, station in pairs(hintMap) do
		if lower:find(keyword) then
			local model = kit:FindFirstChild(station)
			if triggerStation(model) then
				pushLog("Auto-serve: " .. text, palette.cyan)
			end
			return
		end
	end
	if lower:find("give") or lower:find("customer") then
		local pos = kit:FindFirstChild("POS")
		if pos then
			for _, d in ipairs(pos:GetDescendants()) do
				if d:IsA("ProximityPrompt") then fireProx(d) break end
			end
		end
		pushLog("Auto-serve: подача клиенту", palette.cyan)
	end
end

local function setupServe()
	if updateHint then
		bind(updateHint.OnClientEvent, function(text)
			task.wait(0.25)
			handleHint(text)
		end)
	end
end

local function setupBooger()
	if not kitBooger or not boogerChoice then return end
	bind(kitBooger.Changed, function()
		if Config.AutoBooger and kitBooger.Value == true then
			pcall(function() boogerChoice:FireServer("A1") end)
			pushLog("BOOGER: взял оплату (A1)", palette.amber)
		end
	end)
end

local function redeem(code)
	if redeemCode and typeof(code) == "string" and #code > 0 then
		pcall(function() redeemCode:FireServer(code) end)
		return true
	end
	return false
end

local function redeemAll()
	if not redeemCode then return end
	spawnLoop(function()
		for _, code in ipairs(Codes) do
			if not alive then return end
			redeem(code)
			task.wait(1.5)
		end
		if #Codes > 0 then
			pushLog("Промокоды отправлены (" .. #Codes .. ")", palette.green)
		end
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "ShawarmaAFK"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.DisplayOrder = 9999
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
if gethui then gui.Parent = gethui() else gui.Parent = PlayerGui end

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = p
	return c
end

local function stroke(p, col, t)
	local s = Instance.new("UIStroke")
	s.Color = col or palette.elementHi
	s.Thickness = t or 1
	s.Parent = p
	return s
end

local function brandGradient(p, rot)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.violet),
		ColorSequenceKeypoint.new(0.5, palette.indigo),
		ColorSequenceKeypoint.new(1, palette.cyan),
	})
	g.Rotation = rot or 0
	g.Parent = p
	return g
end

local window = Instance.new("Frame")
window.Size = UDim2.new(0, 326, 0, 446)
window.Position = UDim2.new(0.5, -163, 0.5, -223)
window.BackgroundColor3 = palette.bg
window.BorderSizePixel = 0
window.Parent = gui
corner(window, 14)
stroke(window, palette.element, 1)

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)
pad.Parent = window

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 9)
layout.Parent = window

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = palette.panel
header.BorderSizePixel = 0
header.LayoutOrder = 1
header.Parent = window
corner(header, 10)

local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(0, 4, 0.62, 0)
accentBar.Position = UDim2.new(0, 10, 0.19, 0)
accentBar.BackgroundColor3 = palette.violet
accentBar.BorderSizePixel = 0
accentBar.Parent = header
corner(accentBar, 2)
brandGradient(accentBar, 90)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 24, 0, 6)
title.Size = UDim2.new(1, -34, 0, 20)
title.Font = Enum.Font.GothamBold
title.Text = "SHAWARMA ANOMALY"
title.TextSize = 15
title.TextColor3 = palette.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header
brandGradient(title, 0)

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 24, 0, 24)
subtitle.Size = UDim2.new(1, -34, 0, 14)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "AFK Assistant"
subtitle.TextSize = 11
subtitle.TextColor3 = palette.sub
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = header

local statsRow = Instance.new("Frame")
statsRow.Size = UDim2.new(1, 0, 0, 50)
statsRow.BackgroundTransparency = 1
statsRow.LayoutOrder = 2
statsRow.Parent = window

local statsLayout = Instance.new("UIListLayout")
statsLayout.FillDirection = Enum.FillDirection.Horizontal
statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statsLayout.Padding = UDim.new(0, 8)
statsLayout.Parent = statsRow

local function makeStat(label)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 96, 1, 0)
	card.BackgroundColor3 = palette.panel
	card.BorderSizePixel = 0
	card.Parent = statsRow
	corner(card, 9)

	local val = Instance.new("TextLabel")
	val.BackgroundTransparency = 1
	val.Position = UDim2.new(0, 0, 0, 8)
	val.Size = UDim2.new(1, 0, 0, 20)
	val.Font = Enum.Font.GothamBold
	val.Text = "—"
	val.TextSize = 16
	val.TextColor3 = palette.text
	val.Parent = card

	local cap = Instance.new("TextLabel")
	cap.BackgroundTransparency = 1
	cap.Position = UDim2.new(0, 0, 0, 28)
	cap.Size = UDim2.new(1, 0, 0, 14)
	cap.Font = Enum.Font.Gotham
	cap.Text = label
	cap.TextSize = 10
	cap.TextColor3 = palette.sub
	cap.Parent = card

	return val
end

local statIncome = makeStat("INCOME")
local statClients = makeStat("CLIENTS")
local statDay = makeStat("DAY")

local function makeToggle(text, desc, default, order, callback)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundColor3 = palette.panel
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = window
	corner(row, 9)

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.new(0, 12, 0, 6)
	lbl.Size = UDim2.new(1, -70, 0, 18)
	lbl.Font = Enum.Font.GothamMedium
	lbl.Text = text
	lbl.TextSize = 13
	lbl.TextColor3 = palette.text
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 12, 0, 23)
	sub.Size = UDim2.new(1, -70, 0, 14)
	sub.Font = Enum.Font.Gotham
	sub.Text = desc
	sub.TextSize = 10
	sub.TextColor3 = palette.sub
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Parent = row

	local track = Instance.new("TextButton")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -12, 0.5, 0)
	track.Size = UDim2.new(0, 42, 0, 22)
	track.BackgroundColor3 = default and palette.violet or palette.element
	track.AutoButtonColor = false
	track.Text = ""
	track.Parent = row
	corner(track, 11)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = default and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.BackgroundColor3 = palette.text
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 9)

	local state = default
	track.MouseButton1Click:Connect(function()
		state = not state
		TweenService:Create(track, TweenInfo.new(0.18), {
			BackgroundColor3 = state and palette.violet or palette.element,
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.18), {
			Position = state and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		}):Play()
		callback(state)
	end)
end

makeToggle("Авто 2x / Tips", "Бусты дохода на каждую смену", Config.AutoBoost, 3, function(s)
	Config.AutoBoost = s
	if s then popBoosts() end
end)

makeToggle("Авто-подача [BETA]", "По подсказкам (не проверено вживую)", Config.AutoServe, 4, function(s)
	Config.AutoServe = s
	pushLog(s and "Auto-serve включён (эвристика)" or "Auto-serve выключен", s and palette.cyan or palette.sub)
end)

makeToggle("Авто BOOGER [BETA]", "Берёт оплату 1000/5000 (A1)", Config.AutoBooger, 5, function(s)
	Config.AutoBooger = s
end)

local promoRow = Instance.new("Frame")
promoRow.Size = UDim2.new(1, 0, 0, 36)
promoRow.BackgroundTransparency = 1
promoRow.LayoutOrder = 6
promoRow.Parent = window

local promoBox = Instance.new("TextBox")
promoBox.Size = UDim2.new(1, -82, 1, 0)
promoBox.Position = UDim2.new(0, 0, 0, 0)
promoBox.BackgroundColor3 = palette.panel
promoBox.BorderSizePixel = 0
promoBox.Font = Enum.Font.Gotham
promoBox.PlaceholderText = "Промокод…"
promoBox.PlaceholderColor3 = palette.sub
promoBox.Text = ""
promoBox.TextColor3 = palette.text
promoBox.TextSize = 13
promoBox.ClearTextOnFocus = false
promoBox.Parent = promoRow
corner(promoBox, 8)
local promoPad = Instance.new("UIPadding")
promoPad.PaddingLeft = UDim.new(0, 10)
promoPad.Parent = promoBox

local redeemBtn = Instance.new("TextButton")
redeemBtn.AnchorPoint = Vector2.new(1, 0)
redeemBtn.Position = UDim2.new(1, 0, 0, 0)
redeemBtn.Size = UDim2.new(0, 74, 1, 0)
redeemBtn.BackgroundColor3 = palette.indigo
redeemBtn.AutoButtonColor = true
redeemBtn.Font = Enum.Font.GothamBold
redeemBtn.Text = "Redeem"
redeemBtn.TextSize = 13
redeemBtn.TextColor3 = palette.text
redeemBtn.Parent = promoRow
corner(redeemBtn, 8)
brandGradient(redeemBtn, 20)

redeemBtn.MouseButton1Click:Connect(function()
	local code = promoBox.Text
	if redeem(code) then
		pushLog("Код отправлен: " .. code, palette.green)
		promoBox.Text = ""
	else
		pushLog(redeemCode and "Введи код" or "RedeemCode не найден", palette.red)
	end
end)

local logFrame = Instance.new("Frame")
logFrame.Size = UDim2.new(1, 0, 0, 40)
logFrame.BackgroundColor3 = palette.panel
logFrame.BorderSizePixel = 0
logFrame.LayoutOrder = 7
logFrame.Parent = window
corner(logFrame, 9)

logLabel = Instance.new("TextLabel")
logLabel.BackgroundTransparency = 1
logLabel.Size = UDim2.new(1, -20, 1, 0)
logLabel.Position = UDim2.new(0, 10, 0, 0)
logLabel.Font = Enum.Font.Gotham
logLabel.Text = "Запущено. Анти-АФК активен."
logLabel.TextSize = 11
logLabel.TextColor3 = palette.sub
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextWrapped = true
logLabel.Parent = logFrame

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, 0, 0, 36)
unloadBtn.BackgroundColor3 = palette.element
unloadBtn.AutoButtonColor = true
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.Text = "ВЫГРУЗИТЬ"
unloadBtn.TextSize = 13
unloadBtn.TextColor3 = palette.red
unloadBtn.LayoutOrder = 8
unloadBtn.Parent = window
corner(unloadBtn, 9)
stroke(unloadBtn, palette.red, 1)

do
	local dragging, dragStart, startPos
	local function update(input)
		local delta = input.Position - dragStart
		window.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
	bind(header.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = window.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	bind(header.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end)
	bind(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end)
end

local function formatNumber(n)
	if not n then return "—" end
	local s = tostring(math.floor(n))
	local k
	while true do
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1 %2")
		if k == 0 then break end
	end
	return s
end

local function statsUpdater()
	while alive do
		statIncome.Text = formatNumber(getIncome())
		statClients.Text = kitClients and tostring(kitClients.Value) or "—"
		statDay.Text = totalDays and tostring(totalDays.Value) or "—"
		task.wait(0.5)
	end
end

local function unload()
	alive = false
	for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
	for _, t in ipairs(threads) do pcall(function() task.cancel(t) end) end
	table.clear(threads)
	if gui then pcall(function() gui:Destroy() end) end
	_G.__SHAWARMA_AFK = nil
end

Suite.unload = unload
Suite.config = Config
Suite.redeem = redeem
unloadBtn.MouseButton1Click:Connect(unload)

antiAfk()
setupBoosts()
setupServe()
setupBooger()
redeemAll()
spawnLoop(statsUpdater)

pushLog("Готово. Анти-АФК + авто-бусты активны.", palette.green)
