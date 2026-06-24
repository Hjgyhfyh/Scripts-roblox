--==============================================================--
--  Princess Tycoon  —  Autofarm
--  Auto Collect  •  Auto Buy (dependency aware)  •  Auto Crates
--==============================================================--

if _G.PT_Autofarm and _G.PT_Autofarm.Unload then
	pcall(_G.PT_Autofarm.Unload)
end

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local VirtualUser      = game:GetService("VirtualUser")
local LocalPlayer      = Players.LocalPlayer

--==============================================================--
--  State
--==============================================================--

local State = {
	running     = true,
	collect     = true,
	buy         = true,
	crates      = true,
	collectRate = 15,   -- touches / sec
	buyRate     = 20,   -- touches / sec
	crateRate   = 5,    -- actions / sec
}

local conns      = {}   -- every connection lives here, killed on unload
local attempts   = {}   -- objectId -> times we fired its button
local blacklist  = {}   -- objectId -> true (gamepass / stuck, stop retrying)
local lastFire   = {}   -- objectId -> os.clock() of last touch

--==============================================================--
--  Network budget  (total stays <= 400 requests / second)
--==============================================================--

local NET_CAP        = 400
local budgetSecond   = math.floor(os.clock())
local budgetUsed     = 0
local lastSecondUsed = 0

local function budgetTake(cost)
	local sec = math.floor(os.clock())
	if sec ~= budgetSecond then
		lastSecondUsed = budgetUsed
		budgetSecond   = sec
		budgetUsed     = 0
	end
	if budgetUsed + cost > NET_CAP then
		return false
	end
	budgetUsed = budgetUsed + cost
	return true
end

--==============================================================--
--  Helpers
--==============================================================--

local function getHRP()
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPlot()
	local root = workspace:FindFirstChild("Tycoons")
	root = root and root:FindFirstChild("Tycoons")
	if not root then return nil end
	for _, plot in ipairs(root:GetChildren()) do
		local owner = plot:FindFirstChild("Owner")
		if owner and owner:IsA("ObjectValue") and owner.Value == LocalPlayer then
			return plot
		end
	end
	return nil
end

local function getMoney()
	local folder = ReplicatedStorage:FindFirstChild("PlayerMoney")
	local val = folder and folder:FindFirstChild(LocalPlayer.Name)
	return (val and val.Value) or 0
end

local function touch(part, hrp)
	if not (part and hrp) then return end
	pcall(function()
		firetouchinterest(part, hrp, 0)
		firetouchinterest(part, hrp, 1)
	end)
end

--  picks the cheapest button that is unbuilt, unlocked, affordable and not gated
local function pickCandidate(plot)
	local owned = {}
	local po = plot:FindFirstChild("PurchasedObjects")
	if po then
		for _, c in ipairs(po:GetChildren()) do owned[c.Name] = true end
	end

	local buttons = plot:FindFirstChild("Buttons")
	if not buttons then return nil end

	local money = getMoney()
	local now   = os.clock()
	local best, bestPrice

	for _, b in ipairs(buttons:GetChildren()) do
		local head = b:FindFirstChild("Head")
		local objV = b:FindFirstChild("Object")
		if head and objV then
			local obj = objV.Value
			if owned[obj] then
				attempts[obj] = nil
			elseif not blacklist[obj] and not b:FindFirstChild("Gamepass") then
				local depV  = b:FindFirstChild("Dependency")
				local dep   = depV and depV.Value
				local depOk = (not dep) or dep == "" or owned[dep]
				local price = (b:FindFirstChild("Price") and b.Price.Value) or 0
				local cool  = lastFire[obj] and (now - lastFire[obj] < 0.5)
				if depOk and price <= money and not cool then
					if not bestPrice or price < bestPrice then
						best, bestPrice = b, price
					end
				end
			end
		end
	end

	if best then
		return best:FindFirstChild("Head"), best.Object.Value
	end
	return nil
end

--==============================================================--
--  Worker loops
--==============================================================--

-- Collect: drain CurrencyToCollect into spendable cash via the Giver pad
task.spawn(function()
	while State.running do
		if not State.collect then
			task.wait(0.2)
		else
			local plot, hrp = getPlot(), getHRP()
			if plot and hrp then
				local ess   = plot:FindFirstChild("Essentials")
				local giver = ess and ess:FindFirstChild("Giver")
				if giver and budgetTake(2) then
					touch(giver, hrp)
				end
			end
			task.wait(1 / math.clamp(State.collectRate, 1, 200))
		end
	end
end)

-- Buy: walk the dependency tree, cheapest first
task.spawn(function()
	while State.running do
		if not State.buy then
			task.wait(0.2)
		else
			local plot, hrp = getPlot(), getHRP()
			if plot and hrp then
				local head, obj = pickCandidate(plot)
				if head and budgetTake(2) then
					touch(head, hrp)
					lastFire[obj] = os.clock()
					attempts[obj] = (attempts[obj] or 0) + 1
					if attempts[obj] >= 12 then
						blacklist[obj] = true
					end
				end
			end
			task.wait(1 / math.clamp(State.buyRate, 1, 200))
		end
	end
end)

-- Crates: open collected crates + scoop up any world crate by touch
task.spawn(function()
	while State.running do
		if not State.crates then
			task.wait(0.3)
		else
			local events = ReplicatedStorage:FindFirstChild("Events")
			local open   = events and events:FindFirstChild("OpenCrate")
			local store  = LocalPlayer:FindFirstChild("Crates")
			if open and store then
				local cash = store:FindFirstChild("Cash")
				local gear = store:FindFirstChild("Gear")
				if cash and cash.Value > 0 and budgetTake(1) then
					pcall(function() open:FireServer("Cash") end)
				end
				if gear and gear.Value > 0 and budgetTake(1) then
					pcall(function() open:FireServer("Gear") end)
				end
			end

			local parent, hrp = workspace:FindFirstChild("CrateParent"), getHRP()
			if parent and hrp then
				for _, m in ipairs(parent:GetChildren()) do
					local part = m:IsA("BasePart") and m or m:FindFirstChildWhichIsA("BasePart", true)
					if part and budgetTake(2) then
						touch(part, hrp)
					end
				end
			end
			task.wait(1 / math.clamp(State.crateRate, 1, 60))
		end
	end
end)

--==============================================================--
--  Anti-AFK  (embedded, always on)
--==============================================================--

conns[#conns + 1] = LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end)

--==============================================================--
--  GUI
--==============================================================--

local COL = {
	bg      = Color3.fromRGB(28, 26, 38),
	bar     = Color3.fromRGB(38, 35, 52),
	panel   = Color3.fromRGB(44, 41, 60),
	track   = Color3.fromRGB(60, 56, 80),
	accent  = Color3.fromRGB(255, 111, 181),
	accent2 = Color3.fromRGB(150, 120, 255),
	text    = Color3.fromRGB(245, 244, 252),
	sub     = Color3.fromRGB(176, 172, 196),
	off     = Color3.fromRGB(70, 66, 92),
}

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = inst
	return c
end

local function getGuiParent()
	local ok, hui = pcall(function() return gethui() end)
	if ok and hui then return hui end
	local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and cg then return cg end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PT_Autofarm"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
pcall(function() ScreenGui.Parent = getGuiParent() end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 320, 0, 364)
Main.Position = UDim2.new(0, 40, 0.5, -182)
Main.BackgroundColor3 = COL.bg
Main.BorderSizePixel = 0
Main.Parent = ScreenGui
corner(Main, 12)
do
	local stroke = Instance.new("UIStroke")
	stroke.Color = COL.accent
	stroke.Transparency = 0.55
	stroke.Thickness = 1
	stroke.Parent = Main
end

-- Title bar
local Bar = Instance.new("Frame")
Bar.Size = UDim2.new(1, 0, 0, 46)
Bar.BackgroundColor3 = COL.bar
Bar.BorderSizePixel = 0
Bar.Parent = Main
corner(Bar, 12)
local barFix = Instance.new("Frame")
barFix.Size = UDim2.new(1, 0, 0, 14)
barFix.Position = UDim2.new(0, 0, 1, -14)
barFix.BackgroundColor3 = COL.bar
barFix.BorderSizePixel = 0
barFix.Parent = Bar

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 14, 0, 0)
Title.Size = UDim2.new(1, -96, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.Text = "\u{1F451} Princess Tycoon"
Title.TextSize = 16
Title.TextColor3 = COL.text
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Bar

local Sub = Instance.new("TextLabel")
Sub.BackgroundTransparency = 1
Sub.Position = UDim2.new(0, 15, 0, 24)
Sub.Size = UDim2.new(1, -96, 0, 14)
Sub.Font = Enum.Font.Gotham
Sub.Text = "Autofarm"
Sub.TextSize = 11
Sub.TextColor3 = COL.sub
Sub.TextXAlignment = Enum.TextXAlignment.Left
Sub.Parent = Bar

local function barButton(txt, xoff, col)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 28, 0, 28)
	b.Position = UDim2.new(1, xoff, 0.5, -14)
	b.BackgroundColor3 = col
	b.Text = txt
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = COL.text
	b.AutoButtonColor = true
	b.Parent = Bar
	corner(b, 8)
	return b
end

local CloseBtn = barButton("\u{2715}", -36, Color3.fromRGB(214, 69, 96))
local MinBtn   = barButton("\u{2013}", -70, COL.panel)

-- Body
local Body = Instance.new("Frame")
Body.Size = UDim2.new(1, -20, 1, -56)
Body.Position = UDim2.new(0, 10, 0, 50)
Body.BackgroundTransparency = 1
Body.Parent = Main
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = Body

local order = 0
local function nextOrder() order = order + 1 return order end

-- Feature row: pill toggle + label + slider
local function featureRow(label, stateKey, rateKey, minR, maxR)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 56)
	row.BackgroundColor3 = COL.panel
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = Body
	corner(row, 10)

	-- pill toggle
	local pill = Instance.new("TextButton")
	pill.Size = UDim2.new(0, 44, 0, 24)
	pill.Position = UDim2.new(0, 12, 0, 9)
	pill.BackgroundColor3 = State[stateKey] and COL.accent or COL.off
	pill.Text = ""
	pill.AutoButtonColor = false
	pill.Parent = row
	corner(pill, 12)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = State[stateKey] and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
	knob.BackgroundColor3 = COL.text
	knob.BorderSizePixel = 0
	knob.Parent = pill
	corner(knob, 9)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 66, 0, 6)
	name.Size = UDim2.new(1, -130, 0, 20)
	name.Font = Enum.Font.GothamMedium
	name.Text = label
	name.TextSize = 14
	name.TextColor3 = COL.text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local rateVal = Instance.new("TextLabel")
	rateVal.BackgroundTransparency = 1
	rateVal.Position = UDim2.new(1, -56, 0, 6)
	rateVal.Size = UDim2.new(0, 48, 0, 20)
	rateVal.Font = Enum.Font.GothamBold
	rateVal.Text = State[rateKey] .. "/s"
	rateVal.TextSize = 13
	rateVal.TextColor3 = COL.accent
	rateVal.TextXAlignment = Enum.TextXAlignment.Right
	rateVal.Parent = row

	-- slider
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -78, 0, 6)
	track.Position = UDim2.new(0, 66, 0, 36)
	track.BackgroundColor3 = COL.track
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 3)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = COL.accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 3)
	local sknob = Instance.new("Frame")
	sknob.Size = UDim2.new(0, 12, 0, 12)
	sknob.AnchorPoint = Vector2.new(0.5, 0.5)
	sknob.BackgroundColor3 = COL.text
	sknob.BorderSizePixel = 0
	sknob.ZIndex = 2
	sknob.Parent = track
	corner(sknob, 6)

	local function render(a)
		fill.Size = UDim2.new(a, 0, 1, 0)
		sknob.Position = UDim2.new(a, 0, 0.5, 0)
	end
	render((State[rateKey] - minR) / (maxR - minR))

	local function setFromAlpha(a)
		a = math.clamp(a, 0, 1)
		local v = math.floor(minR + (maxR - minR) * a + 0.5)
		State[rateKey] = v
		rateVal.Text = v .. "/s"
		render(a)
	end

	local dragging = false
	local function updateFromInput(input)
		local a = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
		setFromAlpha(a)
	end
	conns[#conns + 1] = track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromInput(input)
		end
	end)
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInput(input)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- toggle
	conns[#conns + 1] = pill.MouseButton1Click:Connect(function()
		State[stateKey] = not State[stateKey]
		TweenService:Create(pill, TweenInfo.new(0.15), {
			BackgroundColor3 = State[stateKey] and COL.accent or COL.off,
		}):Play()
		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position = State[stateKey] and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
		}):Play()
	end)
end

featureRow("Auto Collect", "collect", "collectRate", 1, 60)
featureRow("Auto Buy",     "buy",     "buyRate",     1, 60)
featureRow("Auto Crates",  "crates",  "crateRate",   1, 20)

-- Stats panel
local Stats = Instance.new("Frame")
Stats.Size = UDim2.new(1, 0, 0, 100)
Stats.BackgroundColor3 = COL.panel
Stats.BorderSizePixel = 0
Stats.LayoutOrder = nextOrder()
Stats.Parent = Body
corner(Stats, 10)
local statPad = Instance.new("UIPadding")
statPad.PaddingTop = UDim.new(0, 9)
statPad.PaddingLeft = UDim.new(0, 12)
statPad.PaddingRight = UDim.new(0, 12)
statPad.Parent = Stats
local statList = Instance.new("UIListLayout")
statList.Padding = UDim.new(0, 4)
statList.Parent = Stats

local function statLine()
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 16)
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = COL.sub
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = Stats
	return l
end
local sCash  = statLine()
local sPend  = statLine()
local sBuilt = statLine()
local sNet   = statLine()
local sPlot  = statLine()

-- Stats updater
task.spawn(function()
	while State.running do
		local plot = getPlot()
		sCash.Text = "\u{1F48E} Cash:  " .. tostring(getMoney())
		if plot then
			local ctc = plot:FindFirstChild("CurrencyToCollect")
			sPend.Text = "\u{23F3} Pending:  " .. tostring(ctc and ctc.Value or 0)
			local po = plot:FindFirstChild("PurchasedObjects")
			local buttons = plot:FindFirstChild("Buttons")
			local built = po and #po:GetChildren() or 0
			local left = 0
			if buttons then
				for _, b in ipairs(buttons:GetChildren()) do
					if b:FindFirstChild("Head") and b:FindFirstChild("Object") and not b:FindFirstChild("Gamepass") then
						left = left + 1
					end
				end
			end
			sBuilt.Text = "\u{1F3D7} Built:  " .. built .. "    Buttons left:  " .. left
			sPlot.Text  = "\u{1F4CD} Plot:  " .. plot.Name
		else
			sPend.Text  = "\u{23F3} Pending:  -"
			sBuilt.Text = "\u{1F3D7} Built:  -"
			sPlot.Text  = "\u{1F4CD} Plot:  searching..."
		end
		sNet.Text = "\u{1F4E1} Net:  " .. lastSecondUsed .. " / " .. NET_CAP .. " req/s"
		task.wait(0.25)
	end
end)

--==============================================================--
--  Window behaviour: drag, minimise, hotkey, close
--==============================================================--

do
	local dragging, dragStart, startPos = false, nil, nil
	conns[#conns + 1] = Bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = Main.Position
		end
	end)
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			Main.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local minimised = false
conns[#conns + 1] = MinBtn.MouseButton1Click:Connect(function()
	minimised = not minimised
	Body.Visible = not minimised
	TweenService:Create(Main, TweenInfo.new(0.18), {
		Size = minimised and UDim2.new(0, 320, 0, 46) or UDim2.new(0, 320, 0, 364),
	}):Play()
end)

conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		Main.Visible = not Main.Visible
	end
end)

--==============================================================--
--  Unload
--==============================================================--

local function Unload()
	State.running = false
	State.collect, State.buy, State.crates = false, false, false
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(conns)
	pcall(function() ScreenGui:Destroy() end)
	_G.PT_Autofarm = nil
end

conns[#conns + 1] = CloseBtn.MouseButton1Click:Connect(Unload)

_G.PT_Autofarm = { Unload = Unload, State = State }
