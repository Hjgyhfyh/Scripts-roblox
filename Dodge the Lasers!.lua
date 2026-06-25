local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local lp = Players.LocalPlayer

if _G.__DL and _G.__DL.unload then
    pcall(_G.__DL.unload)
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LaserHitClaim = Remotes:WaitForChild("LaserHitClaim")
local PracticeJoin = Remotes:WaitForChild("PracticeJoin")
local RoundResults = Remotes:WaitForChild("RoundResults")
local RoundResultsAck = Remotes:WaitForChild("RoundResultsAck")
local RoundStateRequest = Remotes:FindFirstChild("RoundStateRequest")
local MapVoteCast = Remotes:FindFirstChild("MapVoteCast")
local MapVoteState = Remotes:FindFirstChild("MapVoteState")
local MapVoteStateRequest = Remotes:FindFirstChild("MapVoteStateRequest")

local LaserBeamGeometry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LaserBeamGeometry"))

local LB_TARGETS = {
    { name = "Top-10 (4200s)", value = 4200 },
    { name = "Top-1 (13500s)", value = 13500 },
    { name = "Endless", value = math.huge },
}

local State = {
    loaded = true,
    god = true,
    antiAfk = true,
    antiKick = true,
    hbInsane = false,
    hbRate = 200,
    autoVote = true,
    voteMap = "Classic",
    mode = "idle",
    wantPractice = false,
    dying = false,
    lbTargetIndex = 1,
    connections = {},
}
_G.__DL = State

local function track(conn)
    State.connections[#State.connections + 1] = conn
    return conn
end

local function lbTarget()
    return LB_TARGETS[State.lbTargetIndex].value
end

_G.__DLHitClaim = LaserHitClaim
if not _G.__DLrealConfirm then
    _G.__DLrealConfirm = LaserBeamGeometry.clientConfirmedTouch
end
local realConfirm = _G.__DLrealConfirm
local ourConfirm = function(...)
    if _G.__DL and _G.__DL.god then
        return false
    end
    return realConfirm(...)
end
LaserBeamGeometry.clientConfirmedTouch = ourConfirm

if not _G.__DLNamecallHooked then
    _G.__DLNamecallHooked = true
    local ok = pcall(function()
        local nameMethod = getnamecallmethod
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if _G.__DL and _G.__DL.god and self == _G.__DLHitClaim and nameMethod() == "FireServer" then
                return
            end
            return oldNamecall(self, ...)
        end)
    end)
    if not ok then
        pcall(function()
            local mt = getrawmetatable(game)
            local old = mt.__namecall
            setreadonly(mt, false)
            mt.__namecall = newcclosure(function(self, ...)
                if _G.__DL and _G.__DL.god and self == _G.__DLHitClaim and getnamecallmethod() == "FireServer" then
                    return
                end
                return old(self, ...)
            end)
            setreadonly(mt, true)
        end)
    end
end

task.spawn(function()
    while State.loaded do
        if LaserBeamGeometry.clientConfirmedTouch ~= ourConfirm then
            LaserBeamGeometry.clientConfirmedTouch = ourConfirm
        end
        task.wait(3)
    end
end)

local function inPlay()
    return lp:GetAttribute("RoundRole") == "playing"
        or lp:GetAttribute("MatchHudActive") == true
        or lp:GetAttribute("PracticeActive") == true
end

local lastSafe = nil
track(lp.CharacterAdded:Connect(function()
    lastSafe = nil
end))

track(RunService.Heartbeat:Connect(function()
    if not (State.loaded and State.god) then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end
    if not inPlay() then lastSafe = nil; return end

    local vel = hrp.AssemblyLinearVelocity
    local xz = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
    if xz > 50 then
        hrp.AssemblyLinearVelocity = Vector3.new(0, math.min(vel.Y, 0), 0)
    end

    if hum.FloorMaterial ~= Enum.Material.Air then
        lastSafe = hrp.CFrame
    elseif lastSafe and hrp.Position.Y < lastSafe.Position.Y - 10 then
        hrp.CFrame = lastSafe
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end))

track(lp.Idled:Connect(function()
    if State.loaded and State.antiAfk then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end))

local function getTestPart()
    return Workspace:FindFirstChild("TEST") or Workspace:FindFirstChild("TEST", true)
end

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
            task.wait(1 / math.clamp(State.hbRate, 1, 300))
        elseif State.antiKick then
            pulseTest()
            task.wait(10)
        else
            task.wait(0.5)
        end
    end
end)

local refresh

task.spawn(function()
    while State.loaded do
        if State.mode == "lb" then
            local best = lp:GetAttribute("PracticePersonalBest") or 0
            if lbTarget() ~= math.huge and best >= lbTarget() then
                State.wantPractice = false
                State.mode = "idle"
                local prevGod = State.god
                State.god = false
                task.delay(10, function()
                    if State.loaded then State.god = prevGod end
                end)
                if refresh then refresh() end
            elseif State.wantPractice
                and lp:GetAttribute("PracticeActive") ~= true
                and lp:GetAttribute("RunStartTime") == nil then
                pcall(function() PracticeJoin:FireServer() end)
            end
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

local lastVoteKey = nil
if MapVoteState and MapVoteCast then
    track(MapVoteState.OnClientEvent:Connect(function(st)
        if not (State.loaded and State.autoVote) then return end
        if type(st) ~= "table" or st.phase ~= "active" then return end
        local opts = st.options
        if type(opts) ~= "table" or #opts == 0 then return end
        local key = st.voteEndsAt or st.voteOpensAt or (table.concat(opts, ",") .. "|" .. tostring(st.phase))
        if lastVoteKey == key then return end
        lastVoteKey = key
        local idx = 1
        if State.voteMap ~= "Any" then
            for i, name in ipairs(opts) do
                if name == State.voteMap then idx = i break end
            end
        end
        pcall(function() MapVoteCast:FireServer(idx) end)
    end))
end

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
        if m == "farm" then
            task.spawn(function()
                local t0 = os.clock()
                while State.mode == "farm" and lp:GetAttribute("PracticeActive") == true and os.clock() - t0 < 12 do
                    local char = lp.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local spawn = Workspace:FindFirstChild("SpawnLocation") or Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
                    if hrp and spawn then
                        hrp.CFrame = spawn.CFrame + Vector3.new(0, 3, 0)
                    elseif hrp then
                        hrp.CFrame = hrp.CFrame + Vector3.new(0, 0, -130)
                    end
                    task.wait(1)
                end
            end)
        end
    end
end

local function simulateDeath()
    if State.dying or not State.loaded or State.mode == "lb" then return end
    State.dying = true
    local prevGod = State.god
    State.god = false
    if refresh then refresh() end
    task.spawn(function()
        local t0 = os.clock()
        while State.loaded and State.dying do
            local role = lp:GetAttribute("RoundRole")
            local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
            if role == "eliminated" or (hum and hum.Health <= 0) then break end
            if os.clock() - t0 > 6 then break end
            task.wait(0.1)
        end
        task.wait(0.4)
        if State.loaded and not State.god then State.god = prevGod end
        State.dying = false
        if State.loaded and refresh then refresh() end
    end)
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
local AMBER = Color3.fromRGB(245, 170, 60)
local BG = Color3.fromRGB(18, 20, 26)
local PANEL = Color3.fromRGB(30, 33, 43)
local TXT = Color3.fromRGB(235, 238, 245)

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local ROWS = {
    { key = "god",   label = "Immortality (godmode + anti-fall)" },
    { key = "farm",  label = "Farm Cash / XP / Wins" },
    { key = "lb",    label = "Leaderboard grind (survival)" },
    { key = "afk",   label = "Anti-AFK" },
    { key = "kick",  label = "Anti-Kick" },
    { key = "hb",    label = "Heartbeat farm (insane)" },
    { key = "vote",  label = "Auto map vote" },
}

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 290, 0, 44 + 8 + (#ROWS * 44) + 44 * 3 + 36 + 12)
main.Position = UDim2.new(0, 24, 0.5, -270)
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
    track(bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = main.Position
        end
    end))
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

local switches = {}
local knobs = {}

local function isOn(key)
    if key == "god" then return State.god
    elseif key == "afk" then return State.antiAfk
    elseif key == "kick" then return State.antiKick
    elseif key == "farm" then return State.mode == "farm"
    elseif key == "lb" then return State.mode == "lb"
    elseif key == "hb" then return State.hbInsane
    elseif key == "vote" then return State.autoVote end
    return false
end

refresh = function()
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
    elseif key == "lb" then setMode(State.mode == "lb" and "idle" or "lb")
    elseif key == "hb" then State.hbInsane = not State.hbInsane
    elseif key == "vote" then
        State.autoVote = not State.autoVote
        if State.autoVote and MapVoteStateRequest then
            lastVoteKey = nil
            pcall(function() MapVoteStateRequest:FireServer() end)
        end
    end
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
    track(sw.MouseButton1Click:Connect(function() toggle(row.key) end))
end

local function actionButton(y, text, col, txtCol)
    local b = Instance.new("TextButton")
    b.Position = UDim2.new(0, 12, 0, y)
    b.Size = UDim2.new(1, -24, 0, 36)
    b.BackgroundColor3 = col
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = txtCol
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Parent = main
    corner(b, 8)
    return b
end

local base = 44 + 8 + (#ROWS * 44)

local VOTE_MAPS = { "Any", "Classic", "Rounded", "Squared", "Tiles" }
local mapBtn = actionButton(base, "Vote map: " .. State.voteMap, PANEL, TXT)
track(mapBtn.MouseButton1Click:Connect(function()
    local cur = 1
    for i, name in ipairs(VOTE_MAPS) do
        if name == State.voteMap then cur = i break end
    end
    State.voteMap = VOTE_MAPS[(cur % #VOTE_MAPS) + 1]
    mapBtn.Text = "Vote map: " .. State.voteMap
end))

local lbBtn = actionButton(base + 44, "LB target: " .. LB_TARGETS[State.lbTargetIndex].name, PANEL, TXT)
track(lbBtn.MouseButton1Click:Connect(function()
    State.lbTargetIndex = (State.lbTargetIndex % #LB_TARGETS) + 1
    lbBtn.Text = "LB target: " .. LB_TARGETS[State.lbTargetIndex].name
end))

local simBtn = actionButton(base + 88, "SIMULATE LASER DEATH", AMBER, Color3.fromRGB(20, 16, 8))
track(simBtn.MouseButton1Click:Connect(simulateDeath))

local unloadBtn = actionButton(base + 132, "UNLOAD", DANGER, Color3.fromRGB(255, 255, 255))

local function unload()
    State.loaded = false
    State.god = false
    State.antiAfk = false
    State.antiKick = false
    State.hbInsane = false
    State.autoVote = false
    State.wantPractice = false
    State.mode = "idle"
    if _G.__DLrealConfirm then
        LaserBeamGeometry.clientConfirmedTouch = _G.__DLrealConfirm
    end
    for _, c in ipairs(State.connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(State.connections)
    if _G.__DL == State then _G.__DL = nil end
    if gui then gui:Destroy() end
end
State.unload = unload

track(closeBtn.MouseButton1Click:Connect(unload))
track(unloadBtn.MouseButton1Click:Connect(unload))

refresh()
