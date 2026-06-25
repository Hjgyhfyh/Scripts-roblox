local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local lp = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LaserHitClaim = Remotes:WaitForChild("LaserHitClaim")
local PracticeJoin = Remotes:WaitForChild("PracticeJoin")
local RoundResults = Remotes:WaitForChild("RoundResults")
local RoundResultsAck = Remotes:WaitForChild("RoundResultsAck")
local RoundStateRequest = Remotes:FindFirstChild("RoundStateRequest")

local LaserBeamGeometry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LaserBeamGeometry"))

local State = {
    loaded = true,
    god = true,
    antiAfk = true,
    antiKick = true,
    mode = "idle",
    wantPractice = false,
    dying = false,
    hbInsane = false,
    hbRate = 200,
    connections = {},
}

local realConfirm = LaserBeamGeometry.clientConfirmedTouch
LaserBeamGeometry.clientConfirmedTouch = function(...)
    if State.loaded and State.god then
        return false
    end
    return realConfirm(...)
end

do
    local ok = pcall(function()
        local nameMethod = getnamecallmethod
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if State.loaded and State.god and self == LaserHitClaim and nameMethod() == "FireServer" then
                return
            end
            return oldNamecall(self, ...)
        end)
    end)
    if not ok then
        local mt = getrawmetatable(game)
        local old = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            if State.loaded and State.god and self == LaserHitClaim and getnamecallmethod() == "FireServer" then
                return
            end
            return old(self, ...)
        end)
        setreadonly(mt, true)
    end
end

local function track(conn)
    State.connections[#State.connections + 1] = conn
    return conn
end

local function getTestPart()
    return Workspace:FindFirstChild("TEST") or Workspace:FindFirstChild("TEST", true)
end

track(lp.Idled:Connect(function()
    if State.loaded and State.antiAfk then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end))

local function pulseTest()
    local test = getTestPart()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if test and hrp and typeof(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(hrp, test, 0)
            firetouchinterest(hrp, test, 1)
        end)
    end
end

task.spawn(function()
    while State.loaded do
        if State.hbInsane then
            pulseTest()
            task.wait(1 / math.clamp(State.hbRate, 1, 350))
        elseif State.antiKick then
            pulseTest()
            task.wait(8)
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while State.loaded do
        if State.wantPractice and lp:GetAttribute("PracticeActive") ~= true then
            pcall(function() PracticeJoin:FireServer() end)
        end
        task.wait(2)
    end
end)

track(RoundResults.OnClientEvent:Connect(function()
    if State.loaded and State.mode == "farm" then
        task.delay(0.4, function()
            pcall(function() RoundResultsAck:FireServer() end)
        end)
    end
end))

if RoundStateRequest then
    pcall(function() RoundStateRequest:FireServer() end)
end

local function setMode(m)
    State.mode = m
    if m == "lb" then
        State.wantPractice = true
        pcall(function() PracticeJoin:FireServer() end)
    else
        State.wantPractice = false
        if m == "farm" and lp:GetAttribute("PracticeActive") == true then
            pcall(function() PracticeJoin:FireServer() end)
            task.delay(2, function()
                if State.mode == "farm" and lp:GetAttribute("PracticeActive") == true then
                    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
                    if hum then hum.Health = 0 end
                end
            end)
        end
    end
end

local parentGui = (gethui and gethui()) or CoreGui
for _, n in ipairs(parentGui:GetChildren()) do
    if n.Name == "DodgeLasersFarm" then n:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "DodgeLasersFarm"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = parentGui

local ACCENT = Color3.fromRGB(0, 220, 160)
local OFFCOL = Color3.fromRGB(70, 76, 90)
local DANGER = Color3.fromRGB(255, 90, 120)
local BG = Color3.fromRGB(18, 20, 26)
local PANEL = Color3.fromRGB(30, 33, 43)
local TXT = Color3.fromRGB(235, 238, 245)

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local ROWS = {
    { key = "god",   label = "Immortality (godmode)" },
    { key = "farm",  label = "Farm Cash / XP / Wins" },
    { key = "lb",    label = "Leaderboard grind (survival)" },
    { key = "afk",   label = "Anti-AFK" },
    { key = "kick",  label = "Anti-Kick" },
}

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 286, 0, 44 + (#ROWS * 44) + 12 + 44 + 12)
main.Position = UDim2.new(0, 24, 0.5, -160)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
corner(main, 12)
do
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(45, 50, 62)
    s.Parent = main
end

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 44)
bar.BackgroundColor3 = PANEL
bar.BorderSizePixel = 0
bar.Parent = main
corner(bar, 12)
local barFix = Instance.new("Frame")
barFix.Size = UDim2.new(1, 0, 0, 14)
barFix.Position = UDim2.new(0, 0, 1, -14)
barFix.BackgroundColor3 = PANEL
barFix.BorderSizePixel = 0
barFix.Parent = bar

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 14, 0, 0)
title.Size = UDim2.new(1, -52, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = TXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "DODGE THE LASERS"
title.Parent = bar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.Position = UDim2.new(1, -34, 0.5, -13)
closeBtn.BackgroundColor3 = DANGER
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.BorderSizePixel = 0
closeBtn.Parent = bar
corner(closeBtn, 6)

do
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local switches = {}
local knobs = {}

local function isOn(key)
    if key == "god" then return State.god
    elseif key == "afk" then return State.antiAfk
    elseif key == "kick" then return State.antiKick
    elseif key == "farm" then return State.mode == "farm"
    elseif key == "lb" then return State.mode == "lb" end
    return false
end

local function refresh()
    for key, sw in pairs(switches) do
        local on = isOn(key)
        sw.BackgroundColor3 = on and ACCENT or OFFCOL
        sw.Text = on and "ON" or "OFF"
        sw.TextColor3 = on and Color3.fromRGB(10, 12, 16) or TXT
        knobs[key].Position = on and UDim2.new(1, -20, 0.5, -8) or UDim2.new(0, 4, 0.5, -8)
    end
end

local function toggle(key)
    if key == "god" then State.god = not State.god
    elseif key == "afk" then State.antiAfk = not State.antiAfk
    elseif key == "kick" then State.antiKick = not State.antiKick
    elseif key == "farm" then setMode(State.mode == "farm" and "idle" or "farm")
    elseif key == "lb" then setMode(State.mode == "lb" and "idle" or "lb") end
    refresh()
end

for idx, row in ipairs(ROWS) do
    local f = Instance.new("Frame")
    f.BackgroundColor3 = PANEL
    f.BorderSizePixel = 0
    f.Position = UDim2.new(0, 12, 0, 44 + 8 + (idx - 1) * 44)
    f.Size = UDim2.new(1, -24, 0, 36)
    f.Parent = main
    corner(f, 8)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(1, -76, 1, 0)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 13
    lbl.TextColor3 = TXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = row.label
    lbl.Parent = f

    local sw = Instance.new("TextButton")
    sw.Position = UDim2.new(1, -56, 0.5, -12)
    sw.Size = UDim2.new(0, 48, 0, 24)
    sw.BackgroundColor3 = OFFCOL
    sw.Text = "OFF"
    sw.Font = Enum.Font.GothamBold
    sw.TextSize = 11
    sw.TextColor3 = TXT
    sw.BorderSizePixel = 0
    sw.AutoButtonColor = false
    sw.Parent = f
    corner(sw, 12)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = UDim2.new(0, 4, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = sw
    corner(knob, 8)
    knobs[row.key] = knob

    switches[row.key] = sw
    sw.MouseButton1Click:Connect(function() toggle(row.key) end)
end

local unloadBtn = Instance.new("TextButton")
unloadBtn.Position = UDim2.new(0, 12, 1, -48)
unloadBtn.Size = UDim2.new(1, -24, 0, 36)
unloadBtn.BackgroundColor3 = DANGER
unloadBtn.Text = "UNLOAD"
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.TextSize = 13
unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
unloadBtn.BorderSizePixel = 0
unloadBtn.Parent = main
corner(unloadBtn, 8)

local function unload()
    State.loaded = false
    State.god = false
    State.antiAfk = false
    State.antiKick = false
    State.wantPractice = false
    State.mode = "idle"
    LaserBeamGeometry.clientConfirmedTouch = realConfirm
    for _, c in ipairs(State.connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(State.connections)
    if gui then gui:Destroy() end
end

closeBtn.MouseButton1Click:Connect(unload)
unloadBtn.MouseButton1Click:Connect(unload)

refresh()
