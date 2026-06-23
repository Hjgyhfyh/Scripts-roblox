do
    local VU = game:GetService("VirtualUser")
    game.Players.LocalPlayer.Idled:Connect(function()
        VU:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VU:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local me  = Players.LocalPlayer
local cam = workspace.CurrentCamera

local cfg = {
    mobs      = true,
    crates    = true,
    tracers   = false,
    healthBar = true,
    maxDist   = 800,
}

local HOSTILE = {
    Shrieker=true, Brute=true, Husk=true, Wanderer=true,
    Wretch=true, Rig=true, Bacteria=true, ["Skin Stealer"]=true,
    Phantom=true, Brute=true,
}
local SKIP = { Armory=true, Vendor=true }

local C = {
    hostile  = Color3.fromRGB(255, 65, 65),
    neutral  = Color3.fromRGB(255, 200, 50),
    crate_c  = Color3.fromRGB(50, 185, 255),
    crate_s  = Color3.fromRGB(200, 100, 255),
    crate_l  = Color3.fromRGB(255, 160, 40),
    text     = Color3.fromRGB(240, 240, 240),
    hp_hi    = Color3.fromRGB(55, 220, 55),
    hp_lo    = Color3.fromRGB(255, 55, 55),
    black    = Color3.fromRGB(0, 0, 0),
}

local function mkESP()
    local e = { lines = {} }
    for i = 1, 4 do
        local l = Drawing.new("Line")
        l.Visible   = false
        l.Thickness = 1.5
        l.ZIndex    = 5
        e.lines[i]  = l
    end
    e.name       = Drawing.new("Text")
    e.name.Visible = false; e.name.Size = 13; e.name.Font = 2
    e.name.Center = true; e.name.Outline = true; e.name.ZIndex = 6

    e.dist       = Drawing.new("Text")
    e.dist.Visible = false; e.dist.Size = 11; e.dist.Font = 2
    e.dist.Center = true; e.dist.Outline = true
    e.dist.Color  = C.text; e.dist.ZIndex = 6

    e.hpBg        = Drawing.new("Square")
    e.hpBg.Visible = false; e.hpBg.Color = C.black
    e.hpBg.Filled  = true; e.hpBg.Transparency = 1; e.hpBg.ZIndex = 5

    e.hpFg        = Drawing.new("Square")
    e.hpFg.Visible = false; e.hpFg.Filled = true
    e.hpFg.Transparency = 1; e.hpFg.ZIndex = 6

    e.trace       = Drawing.new("Line")
    e.trace.Visible = false; e.trace.Thickness = 1
    e.trace.Transparency = 0.55; e.trace.ZIndex = 4
    return e
end

local function rmESP(e)
    for _, l in ipairs(e.lines) do l:Remove() end
    e.name:Remove(); e.dist:Remove()
    e.hpBg:Remove(); e.hpFg:Remove(); e.trace:Remove()
end

local function hideESP(e)
    for _, l in ipairs(e.lines) do l.Visible = false end
    e.name.Visible = false; e.dist.Visible = false
    e.hpBg.Visible = false; e.hpFg.Visible = false; e.trace.Visible = false
end

local function drawLines(lines, x1, y1, x2, y2, col)
    local pts = {
        { Vector2.new(x1, y1), Vector2.new(x2, y1) },
        { Vector2.new(x2, y1), Vector2.new(x2, y2) },
        { Vector2.new(x2, y2), Vector2.new(x1, y2) },
        { Vector2.new(x1, y2), Vector2.new(x1, y1) },
    }
    for i, l in ipairs(lines) do
        l.From = pts[i][1]; l.To = pts[i][2]
        l.Color = col; l.Visible = true
    end
end

local function w2s(pos)
    local sp, on = cam:WorldToViewportPoint(pos)
    return Vector2.new(sp.X, sp.Y), on, sp.Z
end

local function getCharBox(hrp)
    local head, onS, depth = w2s(hrp.Position + Vector3.new(0, 2.6, 0))
    if not onS or depth < 0 then return end
    local feet = w2s(hrp.Position - Vector3.new(0, 3.1, 0))
    local h = math.abs(head.Y - feet.Y)
    local w = h * 0.52
    return head.X - w, head.Y, head.X + w, feet.Y, depth
end

local function getCrateBox(pos, depth)
    local sp, onS = w2s(pos)
    if not onS or depth < 0 then return end
    local half = math.clamp(900 / depth, 8, 50)
    return sp.X - half, sp.Y - half, sp.X + half, sp.Y + half, depth, sp
end

-- Tracked entries
local mobESP   = {}
local crateESP = {}

-- Crate folder list (pcall safe)
local function getCrateFolders()
    local folders = {}
    pcall(function() table.insert(folders, { folder = workspace.Game.Items.Boxes.Common,   color = C.crate_c, label = "Crate" }) end)
    pcall(function() table.insert(folders, { folder = workspace.Game.Items.Boxes.Special,  color = C.crate_s, label = "Special" }) end)
    pcall(function() table.insert(folders, { folder = workspace.Game.Items.LockpickCrates, color = C.crate_l, label = "Lockpick" }) end)
    pcall(function() table.insert(folders, { folder = workspace.Game.InteractableProps,    color = C.crate_c, label = "Prop" }) end)
    return folders
end

local CRATE_FOLDERS = getCrateFolders()

-- GUI
local gui = Instance.new("ScreenGui")
gui.Name = "BackroomsESP_GUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = me.PlayerGui

local WIN_W = 210
local win = Instance.new("Frame")
win.Size = UDim2.new(0, WIN_W, 0, 10)
win.Position = UDim2.new(0, 16, 0.45, 0)
win.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
win.BorderSizePixel = 0
win.ClipsDescendants = true
win.Parent = gui
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 9)
local winStroke = Instance.new("UIStroke", win)
winStroke.Color = Color3.fromRGB(55, 55, 90); winStroke.Thickness = 1

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 34)
bar.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
bar.BorderSizePixel = 0
bar.Parent = win
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 9)
local barFix = Instance.new("Frame")
barFix.Size = UDim2.new(1, 0, 0, 9)
barFix.Position = UDim2.new(0, 0, 1, -9)
barFix.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
barFix.BorderSizePixel = 0
barFix.Parent = bar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -36, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "BACKROOMS ESP"
title.TextColor3 = Color3.fromRGB(180, 180, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = bar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -29, 0.5, -11)
closeBtn.BackgroundColor3 = Color3.fromRGB(170, 45, 45)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = bar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(1, 0)
closeBtn.MouseEnter:Connect(function()
    TweenService:Create(closeBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(220, 60, 60) }):Play()
end)
closeBtn.MouseLeave:Connect(function()
    TweenService:Create(closeBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(170, 45, 45) }):Play()
end)

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -20, 0, 1)
divider.Position = UDim2.new(0, 10, 0, 34)
divider.BackgroundColor3 = Color3.fromRGB(45, 45, 70)
divider.BorderSizePixel = 0
divider.Parent = win

local toggleY = 42
local function makeToggle(label, key, colorOn)
    colorOn = colorOn or Color3.fromRGB(80, 255, 110)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 34)
    row.Position = UDim2.new(0, 10, 0, toggleY)
    row.BackgroundColor3 = Color3.fromRGB(20, 20, 32)
    row.BorderSizePixel = 0
    row.Parent = win
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(200, 200, 215)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 36, 0, 18)
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Position = UDim2.new(1, -10, 0.5, 0)
    pill.BackgroundColor3 = cfg[key] and colorOn or Color3.fromRGB(55, 55, 70)
    pill.BorderSizePixel = 0
    pill.Parent = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 12, 0, 12)
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = cfg[key] and UDim2.new(1, -9, 0.5, 0) or UDim2.new(0, 9, 0.5, 0)
    dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dot.BorderSizePixel = 0
    dot.Parent = pill
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = row

    btn.MouseButton1Click:Connect(function()
        cfg[key] = not cfg[key]
        local on = cfg[key]
        TweenService:Create(pill, TweenInfo.new(0.15), { BackgroundColor3 = on and colorOn or Color3.fromRGB(55, 55, 70) }):Play()
        TweenService:Create(dot, TweenInfo.new(0.15), { Position = on and UDim2.new(1, -9, 0.5, 0) or UDim2.new(0, 9, 0.5, 0) }):Play()
    end)

    toggleY = toggleY + 40
    return row
end

makeToggle("Мобы",     "mobs",      Color3.fromRGB(255, 80, 80))
makeToggle("Крейты",   "crates",    Color3.fromRGB(50, 185, 255))
makeToggle("Трейсеры", "tracers",   Color3.fromRGB(200, 200, 255))
makeToggle("HP бар",   "healthBar", Color3.fromRGB(55, 220, 55))

local WIN_H = toggleY + 6
TweenService:Create(win, TweenInfo.new(0.25, Enum.EasingStyle.Quart), { Size = UDim2.new(0, WIN_W, 0, WIN_H) }):Play()

-- Drag
local dragging, dragInput, dragStart, winStart
bar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = i.Position
        winStart  = win.Position
        i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        win.Position = UDim2.new(winStart.X.Scale, winStart.X.Offset + d.X, winStart.Y.Scale, winStart.Y.Offset + d.Y)
    end
end)

-- Helpers
local function getPlayerChars()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then t[p.Character] = true end
    end
    return t
end

-- Main loop
local loopConn = RunService.RenderStepped:Connect(function()
    local myChar = me.Character
    local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myPos  = myHRP and myHRP.Position or Vector3.new(0, 0, 0)
    local vp     = cam.ViewportSize
    local origin = Vector2.new(vp.X / 2, vp.Y)
    local playerChars = getPlayerChars()

    -- MOB ESP
    local seenMobs = {}
    if cfg.mobs then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Humanoid") and obj.Health > 0 then
                local model = obj.Parent
                if model and not playerChars[model] and not SKIP[model.Name] then
                    local hrp = model:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local dist = (hrp.Position - myPos).Magnitude
                        if dist <= cfg.maxDist then
                            seenMobs[obj] = true
                            if not mobESP[obj] then mobESP[obj] = mkESP() end
                            local e   = mobESP[obj]
                            local x1, y1, x2, y2, depth = getCharBox(hrp)
                            if x1 then
                                local col = HOSTILE[model.Name] and C.hostile or C.neutral
                                drawLines(e.lines, x1, y1, x2, y2, col)

                                e.name.Text     = model.Name
                                e.name.Position = Vector2.new((x1 + x2) * 0.5, y1 - 17)
                                e.name.Color    = col
                                e.name.Visible  = true

                                e.dist.Text     = math.floor(dist) .. "m"
                                e.dist.Position = Vector2.new((x1 + x2) * 0.5, y2 + 3)
                                e.dist.Visible  = true

                                if cfg.healthBar and obj.MaxHealth > 0 then
                                    local pct = math.clamp(obj.Health / obj.MaxHealth, 0, 1)
                                    local bh  = math.abs(y2 - y1)
                                    e.hpBg.Size     = Vector2.new(4, bh)
                                    e.hpBg.Position = Vector2.new(x1 - 7, y1)
                                    e.hpBg.Visible  = true
                                    local fh = bh * pct
                                    e.hpFg.Size     = Vector2.new(4, fh)
                                    e.hpFg.Position = Vector2.new(x1 - 7, y2 - fh)
                                    e.hpFg.Color    = pct > 0.45 and C.hp_hi or C.hp_lo
                                    e.hpFg.Visible  = true
                                else
                                    e.hpBg.Visible = false; e.hpFg.Visible = false
                                end

                                if cfg.tracers then
                                    e.trace.From    = origin
                                    e.trace.To      = Vector2.new((x1 + x2) * 0.5, y2)
                                    e.trace.Color   = col
                                    e.trace.Visible = true
                                else
                                    e.trace.Visible = false
                                end
                            else
                                hideESP(e)
                            end
                        end
                    end
                end
            end
        end
    end
    for obj, e in pairs(mobESP) do
        if not seenMobs[obj] then
            hideESP(e); rmESP(e); mobESP[obj] = nil
        end
    end

    -- CRATE ESP
    local seenCrates = {}
    if cfg.crates then
        for _, fd in ipairs(CRATE_FOLDERS) do
            if fd.folder and fd.folder.Parent then
                for _, model in ipairs(fd.folder:GetChildren()) do
                    if model:IsA("Model") then
                        local body = model:FindFirstChild("Body") or model:FindFirstChildWhichIsA("BasePart")
                        if body then
                            local pos  = body.Position
                            local dist = (pos - myPos).Magnitude
                            if dist <= cfg.maxDist then
                                seenCrates[model] = true
                                if not crateESP[model] then crateESP[model] = mkESP() end
                                local e = crateESP[model]
                                local sp, onS, depth = w2s(pos)
                                if onS and depth > 0 then
                                    local half = math.clamp(900 / depth, 8, 48)
                                    local cx, cy = sp.X, sp.Y
                                    drawLines(e.lines, cx - half, cy - half, cx + half, cy + half, fd.color)

                                    e.name.Text     = fd.label
                                    e.name.Position = Vector2.new(cx, cy - half - 17)
                                    e.name.Color    = fd.color
                                    e.name.Visible  = true

                                    e.dist.Text     = math.floor(dist) .. "m"
                                    e.dist.Position = Vector2.new(cx, cy + half + 3)
                                    e.dist.Visible  = true

                                    e.hpBg.Visible = false; e.hpFg.Visible = false

                                    if cfg.tracers then
                                        e.trace.From    = origin
                                        e.trace.To      = Vector2.new(cx, cy + half)
                                        e.trace.Color   = fd.color
                                        e.trace.Visible = true
                                    else
                                        e.trace.Visible = false
                                    end
                                else
                                    hideESP(e)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for model, e in pairs(crateESP) do
        if not seenCrates[model] then
            hideESP(e); rmESP(e); crateESP[model] = nil
        end
    end
end)

-- UNLOAD
local function unload()
    loopConn:Disconnect()
    for _, e in pairs(mobESP)   do hideESP(e); rmESP(e) end
    for _, e in pairs(crateESP) do hideESP(e); rmESP(e) end
    mobESP = {}; crateESP = {}
    gui:Destroy()
end

closeBtn.MouseButton1Click:Connect(unload)

return unload
