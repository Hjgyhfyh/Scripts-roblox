--==============================================================
--  Zero Gravity  —  fly script with adjustable settings
--==============================================================

local plr        = game:GetService("Players").LocalPlayer
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local normalGravity = workspace.Gravity

--==============================================================
--  SETTINGS (live-editable from the UI)
--==============================================================
local settings = {
	controlForce  = 12,    -- responsiveness: how fast you reach fly speed
	maxSpeed      = 100,   -- flight speed (studs/s) — this is the speed limit
	damping       = 8,     -- how fast you stop when no keys pressed (0 = drift forever)
	gravityValue  = 0,     -- workspace gravity while active
	tiltCharacter = false, -- align character to camera while flying
}

-- min / max / step ranges for each slider
local ranges = {
	controlForce = { min = 1,  max = 40,  step = 1 },
	maxSpeed     = { min = 10, max = 500, step = 5 },
	damping      = { min = 0,  max = 30,  step = 0.5 },
	gravityValue = { min = 0,  max = 196, step = 1 },
}

local toggleKey = Enum.KeyCode.F  -- hotkey to toggle on/off

--==============================================================
--  GUI
--==============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "ZeroGravityGui"
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

local main = Instance.new("Frame")
main.Name = "main"
main.Parent = gui
main.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
main.BorderSizePixel = 0
main.Position = UDim2.new(0.02, 0, 0.3, 0)
main.Size = UDim2.new(0, 260, 0, 360)
main.Active = true
main.Draggable = true

local UICornerMain = Instance.new("UICorner")
UICornerMain.CornerRadius = UDim.new(0, 8)
UICornerMain.Parent = main

-- header / title
local label = Instance.new("TextLabel")
label.Name = "label"
label.Parent = main
label.BackgroundColor3 = Color3.fromRGB(65, 65, 65)
label.BorderSizePixel = 0
label.Size = UDim2.new(1, 0, 0, 38)
label.Font = Enum.Font.GothamBold
label.Text = "Zero Gravity"
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextSize = 20
local UICornerTitle = Instance.new("UICorner")
UICornerTitle.CornerRadius = UDim.new(0, 8)
UICornerTitle.Parent = label

-- minimize button
local minBtn = Instance.new("TextButton")
minBtn.Name = "minBtn"
minBtn.Parent = label
minBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
minBtn.BorderSizePixel = 0
minBtn.AnchorPoint = Vector2.new(1, 0.5)
minBtn.Position = UDim2.new(1, -8, 0.5, 0)
minBtn.Size = UDim2.new(0, 24, 0, 24)
minBtn.Font = Enum.Font.GothamBold
minBtn.Text = "-"
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.TextSize = 20
local UICornerMin = Instance.new("UICorner")
UICornerMin.CornerRadius = UDim.new(0, 6)
UICornerMin.Parent = minBtn

-- enable / disable buttons
local buttonOn = Instance.new("TextButton")
buttonOn.Name = "buttonOn"
buttonOn.Parent = main
buttonOn.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
buttonOn.BorderSizePixel = 0
buttonOn.Position = UDim2.new(0.05, 0, 0, 46)
buttonOn.Size = UDim2.new(0.43, 0, 0, 30)
buttonOn.Font = Enum.Font.GothamBold
buttonOn.Text = "Enable"
buttonOn.TextColor3 = Color3.fromRGB(255, 255, 255)
buttonOn.TextSize = 16
local UICorner2 = Instance.new("UICorner")
UICorner2.CornerRadius = UDim.new(0, 6)
UICorner2.Parent = buttonOn

local buttonOff = Instance.new("TextButton")
buttonOff.Name = "buttonOff"
buttonOff.Parent = main
buttonOff.BackgroundColor3 = Color3.fromRGB(180, 80, 80)
buttonOff.BorderSizePixel = 0
buttonOff.Position = UDim2.new(0.52, 0, 0, 46)
buttonOff.Size = UDim2.new(0.43, 0, 0, 30)
buttonOff.Font = Enum.Font.GothamBold
buttonOff.Text = "Disable"
buttonOff.TextColor3 = Color3.fromRGB(255, 255, 255)
buttonOff.TextSize = 16
local UICorner3 = Instance.new("UICorner")
UICorner3.CornerRadius = UDim.new(0, 6)
UICorner3.Parent = buttonOff

-- container that holds all the settings widgets
local content = Instance.new("Frame")
content.Name = "content"
content.Parent = main
content.BackgroundTransparency = 1
content.Position = UDim2.new(0, 0, 0, 84)
content.Size = UDim2.new(1, 0, 1, -110)

local layout = Instance.new("UIListLayout")
layout.Parent = content
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

--------------------------------------------------------------------
-- Slider factory: returns nothing, writes to settings[key] live.
--------------------------------------------------------------------
local function createSlider(name, key, order)
	local r = ranges[key]

	local holder = Instance.new("Frame")
	holder.Name = key .. "Slider"
	holder.Parent = content
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(0.9, 0, 0, 38)
	holder.LayoutOrder = order

	local cap = Instance.new("TextLabel")
	cap.Parent = holder
	cap.BackgroundTransparency = 1
	cap.Size = UDim2.new(1, 0, 0, 16)
	cap.Font = Enum.Font.Gotham
	cap.TextColor3 = Color3.fromRGB(220, 220, 220)
	cap.TextSize = 13
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.Text = name .. ": " .. tostring(settings[key])

	local track = Instance.new("TextButton")
	track.Name = "track"
	track.Parent = holder
	track.AutoButtonColor = false
	track.Text = ""
	track.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 0, 0, 20)
	track.Size = UDim2.new(1, 0, 0, 12)
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "fill"
	fill.Parent = track
	fill.BackgroundColor3 = Color3.fromRGB(100, 170, 255)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new((settings[key] - r.min) / (r.max - r.min), 0, 1, 0)
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill

	local knob = Instance.new("Frame")
	knob.Name = "knob"
	knob.Parent = track
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.Position = UDim2.new((settings[key] - r.min) / (r.max - r.min), 0, 0.5, 0)
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local function setFromScale(scale)
		scale = math.clamp(scale, 0, 1)
		local raw = r.min + (r.max - r.min) * scale
		-- snap to step
		local val = math.floor((raw - r.min) / r.step + 0.5) * r.step + r.min
		val = math.clamp(val, r.min, r.max)
		settings[key] = val
		cap.Text = name .. ": " .. tostring(val)
		local s = (val - r.min) / (r.max - r.min)
		fill.Size = UDim2.new(s, 0, 1, 0)
		knob.Position = UDim2.new(s, 0, 0.5, 0)
	end

	local dragging = false
	local function updateFromInput(inputPos)
		local rel = (inputPos.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
		setFromScale(rel)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromInput(input.Position)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInput(input.Position)
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

--------------------------------------------------------------------
-- Toggle factory: boolean switch row.
--------------------------------------------------------------------
local function createToggle(name, key, order)
	local holder = Instance.new("Frame")
	holder.Name = key .. "Toggle"
	holder.Parent = content
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(0.9, 0, 0, 22)
	holder.LayoutOrder = order

	local cap = Instance.new("TextLabel")
	cap.Parent = holder
	cap.BackgroundTransparency = 1
	cap.Size = UDim2.new(0.7, 0, 1, 0)
	cap.Font = Enum.Font.Gotham
	cap.TextColor3 = Color3.fromRGB(220, 220, 220)
	cap.TextSize = 13
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.Text = name

	local btn = Instance.new("TextButton")
	btn.Parent = holder
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, 0, 0.5, 0)
	btn.Size = UDim2.new(0, 46, 0, 18)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = btn

	local function refresh()
		if settings[key] then
			btn.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
			btn.Text = "ON"
		else
			btn.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
			btn.Text = "OFF"
		end
	end
	refresh()

	btn.MouseButton1Click:Connect(function()
		settings[key] = not settings[key]
		refresh()
	end)
end

-- build the widgets
createSlider("Responsiveness", "controlForce", 1)
createSlider("Speed Limit",    "maxSpeed",     2)
createSlider("Brake / Damping","damping",      3)
createSlider("Gravity",       "gravityValue", 4)
createToggle("Tilt to Camera", "tiltCharacter", 5)

-- status bar pinned to the bottom of main
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "statusLabel"
statusLabel.Parent = main
statusLabel.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
statusLabel.BorderSizePixel = 0
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.new(0.5, 0, 1, -6)
statusLabel.Size = UDim2.new(0.9, 0, 0, 18)
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "OFF | WASD + Space/Shift | F to toggle"
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.TextSize = 11
local UICorner4 = Instance.new("UICorner")
UICorner4.CornerRadius = UDim.new(0, 4)
UICorner4.Parent = statusLabel

--==============================================================
--  FLIGHT LOGIC
--==============================================================
local zeroGravityActive = false
local flyConnection = nil

local keysDown = {
	W = false, A = false, S = false, D = false,
	Space = false, LeftShift = false,
}

local function getRoot()
	local character = plr.Character
	if not character then return nil, nil end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	local rootPart = humanoid and humanoid.RootPart
	return humanoid, rootPart
end

local function enableZeroGravity()
	if zeroGravityActive then return end

	local humanoid, rootPart = getRoot()
	if not rootPart then return end

	workspace.Gravity = settings.gravityValue
	zeroGravityActive = true
	humanoid.PlatformStand = true

	statusLabel.Text = "ON | WASD + Space/Shift | F to toggle"
	statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)

	flyConnection = RunService.Heartbeat:Connect(function(dt)
		if not zeroGravityActive then return end

		local hum, root = getRoot()
		if not root then return end

		-- gravity may have been changed via the slider while flying
		if workspace.Gravity ~= settings.gravityValue then
			workspace.Gravity = settings.gravityValue
		end

		local camera   = workspace.CurrentCamera
		local camCF    = camera.CFrame
		local forward  = camCF.LookVector
		local right    = camCF.RightVector
		local up       = Vector3.new(0, 1, 0)

		local dir = Vector3.new(0, 0, 0)
		if keysDown.W         then dir = dir + forward end
		if keysDown.S         then dir = dir - forward end
		if keysDown.A         then dir = dir - right   end
		if keysDown.D         then dir = dir + right    end
		if keysDown.Space     then dir = dir + up       end
		if keysDown.LeftShift then dir = dir - up       end

		-- velocity-based control: set velocity directly so the speed limit
		-- and damping are exact and not fighting the physics solver.
		local current = root.AssemblyLinearVelocity
		if dir.Magnitude > 0 then
			-- accelerate toward (direction * speed limit)
			local target = dir.Unit * settings.maxSpeed
			local alpha = math.clamp(settings.controlForce * dt, 0, 1)
			root.AssemblyLinearVelocity = current:Lerp(target, alpha)
		elseif settings.damping > 0 then
			-- no input: ease velocity down to zero (auto-brake)
			local alpha = math.clamp(settings.damping * dt, 0, 1)
			root.AssemblyLinearVelocity = current:Lerp(Vector3.zero, alpha)
		end

		-- hard speed cap (covers external pushes / overshoot)
		do
			local v = root.AssemblyLinearVelocity
			if v.Magnitude > settings.maxSpeed then
				root.AssemblyLinearVelocity = v.Unit * settings.maxSpeed
			end
		end

		-- optionally align the body to where the camera looks
		if settings.tiltCharacter then
			local flatLook = Vector3.new(forward.X, 0, forward.Z)
			if flatLook.Magnitude > 0 then
				local goal = CFrame.lookAt(root.Position, root.Position + flatLook)
				root.CFrame = root.CFrame:Lerp(goal, math.clamp(8 * dt, 0, 1))
			end
		end
	end)
end

local function disableZeroGravity()
	if not zeroGravityActive then return end

	zeroGravityActive = false
	workspace.Gravity = normalGravity

	local humanoid = select(1, getRoot())
	if humanoid then
		humanoid.PlatformStand = false
	end

	if flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end

	statusLabel.Text = "OFF | WASD + Space/Shift | F to toggle"
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
end

--==============================================================
--  INPUT
--==============================================================
buttonOn.MouseButton1Click:Connect(enableZeroGravity)
buttonOff.MouseButton1Click:Connect(disableZeroGravity)

-- minimize / restore the settings panel
local minimized = false
minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	content.Visible = not minimized
	buttonOn.Visible = not minimized
	buttonOff.Visible = not minimized
	statusLabel.Visible = not minimized
	if minimized then
		main.Size = UDim2.new(0, 260, 0, 38)
		minBtn.Text = "+"
	else
		main.Size = UDim2.new(0, 260, 0, 360)
		minBtn.Text = "-"
	end
end)

local keyMap = {
	[Enum.KeyCode.W]         = "W",
	[Enum.KeyCode.A]         = "A",
	[Enum.KeyCode.S]         = "S",
	[Enum.KeyCode.D]         = "D",
	[Enum.KeyCode.Space]     = "Space",
	[Enum.KeyCode.LeftShift] = "LeftShift",
}

UIS.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == toggleKey and not gameProcessed then
		if zeroGravityActive then disableZeroGravity() else enableZeroGravity() end
		return
	end
	if gameProcessed then return end
	local k = keyMap[input.KeyCode]
	if k then keysDown[k] = true end
end)

UIS.InputEnded:Connect(function(input)
	local k = keyMap[input.KeyCode]
	if k then keysDown[k] = false end
end)

plr.CharacterAdded:Connect(function()
	if zeroGravityActive then
		disableZeroGravity()
	end
end)
