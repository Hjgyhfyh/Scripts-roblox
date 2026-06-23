local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local RS = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
local SELL_POS = Vector3.new(-172, 4, 46)
local sellType = "Trash"
local busy = false

local function getRemote(path)
	local node = RS
	for _, name in ipairs(path) do
		node = node:WaitForChild(name, 5)
		if not node then return nil end
	end
	return node
end

local ToolEvent = getRemote({ "Events", "ToolEvent" })
local SellFunc = getRemote({ "Events", "SellFunc" })

local function isAmountKey(k)
	if type(k) ~= "string" then return false end
	k = k:lower()
	return k == "amount" or k == "count" or k == "qty" or k == "quantity"
		or k == "stack" or k == "num" or k == "number" or k == "value"
		or k == "owned" or k == "have"
end

local function readToolCount(tool)
	for k, v in pairs(tool:GetAttributes()) do
		if isAmountKey(k) and type(v) == "number" then return v end
	end
	local best
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("IntValue") or d:IsA("NumberValue") then
			best = math.max(best or 0, d.Value)
		elseif d:IsA("TextLabel") or d:IsA("TextButton") then
			local txt = tostring(d.Text)
			local n = txt:match("[xXх]%s*(%d+)") or txt:match("(%d+)%s*[xXх]") or txt:match("^%s*(%d+)%s*$")
			if n then best = math.max(best or 0, tonumber(n)) end
		end
	end
	return best or 1
end

local function isTrashTool(tool)
	local t = tool:GetAttribute("TYPE") or tool:GetAttribute("Type")
	if type(t) == "string" and t:lower() == "trash" then return true end
	return tool.Name:match("^Trash_") ~= nil
end

local function isStickTool(tool)
	local t = tool:GetAttribute("TYPE") or tool:GetAttribute("Type")
	if type(t) == "string" and t:lower() == "stick" then return true end
	return tool.Name:match("^Stick_") ~= nil
end

local function scanTrash()
	local found = {}
	local function scan(container)
		if not container then return end
		for _, d in ipairs(container:GetChildren()) do
			if d:IsA("Tool") and isTrashTool(d) then
				local _, item = d.Name:match("^(%a+)_(.+)$")
				local key = item or d.Name
				found[key] = (found[key] or 0) + readToolCount(d)
			end
		end
	end
	scan(LP:FindFirstChild("Backpack"))
	scan(LP.Character)
	return found
end

local function inventoryTotal()
	local total = 0
	for _, v in pairs(scanTrash()) do total = total + v end
	return total
end

local function buildSellTable()
	local out = { Type = sellType }
	for name, v in pairs(scanTrash()) do
		if type(v) == "number" and v > 0 then out[name] = v end
	end
	return out
end

local function readCapacity(total)
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then return nil, nil end
	local exactCur, exactMax
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			local cur, mx = tostring(d.Text):match("^%s*(%d+)%s*/%s*(%d+)%s*$")
			if cur then
				cur, mx = tonumber(cur), tonumber(mx)
				if mx > 0 and mx >= cur and cur == total then
					if not exactMax or mx < exactMax then
						exactCur, exactMax = cur, mx
					end
				end
			end
		end
	end
	return exactCur, exactMax
end

local function getHumanoid()
	local char = LP.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function standUp()
	local hum = getHumanoid()
	if hum then
		hum.Sit = false
		hum.PlatformStand = false
		hum.AutoRotate = true
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	end
	return hum
end

local parent = (gethui and gethui()) or game:GetService("CoreGui")
if parent:FindFirstChild("RemoteFirerGui") then
	parent.RemoteFirerGui:Destroy()
end

local connections = {}
local function track(conn)
	table.insert(connections, conn)
	return conn
end

local gui = Instance.new("ScreenGui")
gui.Name = "RemoteFirerGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(300, 372)
main.Position = UDim2.fromScale(0.5, 0.5)
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(90, 120, 255)
stroke.Thickness = 1.5
stroke.Transparency = 0.3

local pad = Instance.new("UIPadding", main)
pad.PaddingTop = UDim.new(0, 12)
pad.PaddingBottom = UDim.new(0, 12)
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingRight = UDim.new(0, 12)

local list = Instance.new("UIListLayout", main)
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundTransparency = 1
title.Text = "Remote Firer"
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(235, 235, 245)
title.TextXAlignment = Enum.TextXAlignment.Left
title.LayoutOrder = 1
title.Parent = main

local function makeToggle(text, order)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 34)
	btn.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
	btn.AutoButtonColor = false
	btn.Text = text .. ": OFF"
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 14
	btn.TextColor3 = Color3.fromRGB(220, 220, 230)
	btn.LayoutOrder = order
	btn.Parent = main
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	local on = false
	track(btn.MouseButton1Click:Connect(function()
		on = not on
		btn.Text = text .. (on and ": ON" or ": OFF")
		btn.BackgroundColor3 = on and Color3.fromRGB(60, 130, 90) or Color3.fromRGB(32, 32, 44)
	end))
	return function() return on end
end

local toolOn = makeToggle("Авто-копание (ToolEvent)", 2)
local autoSellOn = makeToggle("Auto-Sell (полный рюкзак)", 3)
local keepEquipOn = makeToggle("Держать инструмент (слот 1)", 4)
local antiAfkOn = makeToggle("Anti-AFK", 5)

local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(1, 0, 0, 16)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Скорость: 10 /сек"
speedLabel.Font = Enum.Font.Gotham
speedLabel.TextSize = 13
speedLabel.TextColor3 = Color3.fromRGB(170, 170, 190)
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.LayoutOrder = 6
speedLabel.Parent = main

local sliderBack = Instance.new("Frame")
sliderBack.Size = UDim2.new(1, 0, 0, 14)
sliderBack.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
sliderBack.LayoutOrder = 7
sliderBack.Active = true
sliderBack.Parent = main
Instance.new("UICorner", sliderBack).CornerRadius = UDim.new(1, 0)

local fillBar = Instance.new("Frame")
fillBar.Size = UDim2.fromScale(10 / 200, 1)
fillBar.BackgroundColor3 = Color3.fromRGB(90, 120, 255)
fillBar.BorderSizePixel = 0
fillBar.Parent = sliderBack
Instance.new("UICorner", fillBar).CornerRadius = UDim.new(1, 0)

local rate = 10
local dragging = false

local function setFromX(x)
	local rel = math.clamp((x - sliderBack.AbsolutePosition.X) / sliderBack.AbsoluteSize.X, 0, 1)
	rate = math.clamp(math.floor(rel * 200 + 0.5), 1, 200)
	fillBar.Size = UDim2.fromScale(rate / 200, 1)
	speedLabel.Text = "Скорость: " .. rate .. " /сек"
end

track(sliderBack.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		setFromX(i.Position.X)
	end
end))
track(UserInput.InputChanged:Connect(function(i)
	if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		setFromX(i.Position.X)
	end
end))
track(UserInput.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end))

local running = false
local startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.new(1, 0, 0, 38)
startBtn.BackgroundColor3 = Color3.fromRGB(70, 90, 220)
startBtn.AutoButtonColor = false
startBtn.Text = "СТАРТ"
startBtn.Font = Enum.Font.GothamBold
startBtn.TextSize = 16
startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
startBtn.LayoutOrder = 8
startBtn.Parent = main
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 8)

track(startBtn.MouseButton1Click:Connect(function()
	running = not running
	startBtn.Text = running and "СТОП" or "СТАРТ"
	startBtn.BackgroundColor3 = running and Color3.fromRGB(200, 70, 80) or Color3.fromRGB(70, 90, 220)
end))

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 16)
status.BackgroundTransparency = 1
status.Text = "Готов"
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(150, 150, 170)
status.TextXAlignment = Enum.TextXAlignment.Left
status.LayoutOrder = 9
status.Parent = main

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, 0, 0, 32)
unloadBtn.BackgroundColor3 = Color3.fromRGB(54, 30, 36)
unloadBtn.AutoButtonColor = false
unloadBtn.Text = "⏏ Unload"
unloadBtn.Font = Enum.Font.GothamMedium
unloadBtn.TextSize = 14
unloadBtn.TextColor3 = Color3.fromRGB(235, 180, 190)
unloadBtn.LayoutOrder = 10
unloadBtn.Parent = main
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 8)

local function unload()
	running = false
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
	if gui then gui:Destroy() end
end

track(unloadBtn.MouseButton1Click:Connect(unload))

local function autoSellSequence()
	if busy or not SellFunc then return end
	busy = true
	task.spawn(function()
		status.Text = "Продаю..."
		standUp()
		task.wait(0.15)
		local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
		local back
		if hrp then
			back = hrp.CFrame
			hrp.CFrame = CFrame.new(SELL_POS)
			pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
			task.wait(1)
		end
		pcall(function() SellFunc:InvokeServer("Sell", buildSellTable()) end)
		task.wait(0.45)
		if hrp and back then
			hrp.CFrame = back
			pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
		end
		task.wait(0.4)
		busy = false
	end)
end

track(LP.Idled:Connect(function()
	if antiAfkOn() then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end
end))

local armed = true
local lastAfk = tick()
task.spawn(function()
	while gui.Parent do
		task.wait(0.5)
		if keepEquipOn() and not busy then
			local hum = getHumanoid()
			local bp = LP:FindFirstChild("Backpack")
			if hum and bp then
				for _, t in ipairs(bp:GetChildren()) do
					if t:IsA("Tool") and isStickTool(t) then
						pcall(function() hum:EquipTool(t) end)
						break
					end
				end
			end
		end
		if antiAfkOn() and not busy and tick() - lastAfk > 45 then
			lastAfk = tick()
			local hum = standUp()
			if hum then hum.Jump = true end
		end
		local total = inventoryTotal()
		local cur, mx = readCapacity(total)
		local fill = cur or total
		if mx then
			if fill < mx then armed = true end
			if armed and autoSellOn() and not busy and fill > 0 and fill >= mx then
				armed = false
				autoSellSequence()
			end
		end
		if not busy then
			status.Text = running and "Авто-фарм ВКЛ" or "Готов"
		end
	end
end)

task.spawn(function()
	local acc = 0
	while gui.Parent do
		local dt = RunService.Heartbeat:Wait()
		if running and not busy then
			acc = acc + dt
			local interval = 1 / rate
			local guard = 0
			while acc >= interval and guard < 50 do
				acc = acc - interval
				guard = guard + 1
				if toolOn() and ToolEvent then
					pcall(function() ToolEvent:FireServer("Activated", true) end)
				end
			end
		else
			acc = 0
		end
	end
end)

do
	local dragStart, startPos
	local moveConn
	track(title.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragStart = i.Position
			startPos = main.Position
			if moveConn then moveConn:Disconnect() end
			moveConn = UserInput.InputChanged:Connect(function(m)
				if m.UserInputType == Enum.UserInputType.MouseMovement or m.UserInputType == Enum.UserInputType.Touch then
					local d = m.Position - dragStart
					main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
				end
			end)
		end
	end))
	track(title.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			if moveConn then moveConn:Disconnect() moveConn = nil end
		end
	end))
end
