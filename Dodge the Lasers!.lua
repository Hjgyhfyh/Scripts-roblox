local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

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
    mode = "idle",
    wantPractice = false,
    heartbeatInterval = 8,
    target = 4030,
    practiceStart = nil,
    connections = {},
    threads = {},
}

local TARGETS = {
    practiceTop10 = 4030,
    practiceTop1 = 13420,
    gameTop10 = 1610,
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
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end))

State.threads.heartbeat = task.spawn(function()
    while State.loaded do
        local test = getTestPart()
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if test and hrp and typeof(firetouchinterest) == "function" then
            pcall(function()
                firetouchinterest(hrp, test, 0)
                firetouchinterest(hrp, test, 1)
            end)
        end
        task.wait(State.heartbeatInterval)
    end
end)

State.threads.practice = task.spawn(function()
    while State.loaded do
        if State.wantPractice and lp:GetAttribute("PracticeActive") ~= true then
            pcall(function() PracticeJoin:FireServer() end)
        end
        task.wait(2)
    end
end)

track(lp:GetAttributeChangedSignal("PracticeActive"):Connect(function()
    if lp:GetAttribute("PracticeActive") == true then
        if not State.practiceStart then State.practiceStart = os.clock() end
    else
        State.practiceStart = nil
    end
end))

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
        State.practiceStart = State.practiceStart or os.clock()
        pcall(function() PracticeJoin:FireServer() end)
    elseif m == "farm" then
        State.wantPractice = false
        if lp:GetAttribute("PracticeActive") == true then
            pcall(function() PracticeJoin:FireServer() end)
            task.delay(2, function()
                if State.mode == "farm" and lp:GetAttribute("PracticeActive") == true then
                    local char = lp.Character
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if hum then hum.Health = 0 end
                end
            end)
        end
    else
        State.wantPractice = false
    end
end

local function fmt(sec)
    sec = math.floor(tonumber(sec) or 0)
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

local function comma(n)
    n = tostring(math.floor(tonumber(n) or 0))
    local out = n:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (out:gsub("^%s+", ""))
end

local CoreGui = game:GetService("CoreGui")
local parentGui = (gethui and gethui()) or CoreGui

local old = parentGui:FindFirstChild("DodgeLasersFarm")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DodgeLasersFarm"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = parentGui

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
    return c
end

local function stroke(p, col, t)
    local s = Instance.new("UIStroke")
    s.Color = col
    s.Thickness = t or 1
    s.Parent = p
    return s
end

local ACCENT = Color3.fromRGB(0, 220, 160)
local ACCENT2 = Color3.fromRGB(255, 90, 120)
local BG = Color3.fromRGB(18, 20, 26)
local PANEL = Color3.fromRGB(28, 31, 40)
local TXT = Color3.fromRGB(235, 238, 245)
local SUB = Color3.fromRGB(150, 158, 172)

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 320, 0, 466)
main.Position = UDim2.new(0, 24, 0.5, -233)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
corner(main, 12)
stroke(main, Color3.fromRGB(45, 50, 62), 1)

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

local dot = Instance.new("Frame")
dot.Size = UDim2.new(0, 10, 0, 10)
dot.Position = UDim2.new(0, 14, 0.5, -5)
dot.BackgroundColor3 = ACCENT
dot.BorderSizePixel = 0
dot.Parent = bar
corner(dot, 5)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 34, 0, 0)
title.Size = UDim2.new(1, -70, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextColor3 = TXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "DODGE THE LASERS — AUTOFARM"
title.Parent = bar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.Position = UDim2.new(1, -34, 0.5, -13)
closeBtn.BackgroundColor3 = ACCENT2
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

local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.new(0, 12, 0, 52)
body.Size = UDim2.new(1, -24, 1, -64)
body.Parent = main

local statBox = Instance.new("Frame")
statBox.BackgroundColor3 = PANEL
statBox.BorderSizePixel = 0
statBox.Size = UDim2.new(1, 0, 0, 96)
statBox.Parent = body
corner(statBox, 10)

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.new(0, 12, 0, 10)
grid.Size = UDim2.new(1, -24, 1, -20)
grid.Parent = statBox

local function statCell(x, y, name)
    local f = Instance.new("Frame")
    f.BackgroundTransparency = 1
    f.Size = UDim2.new(0.5, 0, 0.25, 0)
    f.Position = UDim2.new(x * 0.5, 0, y * 0.25, 0)
    f.Parent = grid
    local k = Instance.new("TextLabel")
    k.BackgroundTransparency = 1
    k.Size = UDim2.new(0.5, 0, 1, 0)
    k.Font = Enum.Font.Gotham
    k.TextSize = 12
    k.TextColor3 = SUB
    k.TextXAlignment = Enum.TextXAlignment.Left
    k.Text = name
    k.Parent = f
    local v = Instance.new("TextLabel")
    v.BackgroundTransparency = 1
    v.Position = UDim2.new(0.5, 0, 0, 0)
    v.Size = UDim2.new(0.5, 0, 1, 0)
    v.Font = Enum.Font.GothamBold
    v.TextSize = 12
    v.TextColor3 = TXT
    v.TextXAlignment = Enum.TextXAlignment.Right
    v.Text = "-"
    v.Parent = f
    return v
end

local vCash = statCell(0, 0, "Cash")
local vLevel = statCell(1, 0, "Level")
local vWins = statCell(0, 1, "Wins")
local vKills = statCell(1, 1, "Kills")
local vGpb = statCell(0, 2, "Game best")
local vPpb = statCell(1, 2, "Pract best")
local vSurv = statCell(0, 3, "Survival")
local vRole = statCell(1, 3, "State")

local function makeButton(parent, y, h, text, col)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, h)
    b.Position = UDim2.new(0, 0, 0, y)
    b.BackgroundColor3 = col
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Parent = parent
    corner(b, 8)
    return b
end

local farmBtn = makeButton(body, 108, 38, "FARM CASH / XP / WINS", PANEL)
local lbBtn = makeButton(body, 152, 38, "LEADERBOARD GRIND (PRACTICE)", PANEL)

local tgtBox = Instance.new("Frame")
tgtBox.BackgroundColor3 = PANEL
tgtBox.BorderSizePixel = 0
tgtBox.Position = UDim2.new(0, 0, 0, 198)
tgtBox.Size = UDim2.new(1, 0, 0, 30)
tgtBox.Parent = body
corner(tgtBox, 8)

local function tgtButton(x, w, text, val)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = Color3.fromRGB(38, 42, 53)
    b.Position = UDim2.new(x, 4, 0, 4)
    b.Size = UDim2.new(w, -8, 1, -8)
    b.Text = text
    b.Font = Enum.Font.Gotham
    b.TextSize = 11
    b.TextColor3 = TXT
    b.BorderSizePixel = 0
    b.Parent = tgtBox
    corner(b, 6)
    b.MouseButton1Click:Connect(function()
        State.target = val
    end)
    return b
end

tgtButton(0, 1 / 3, "Top-10 67:00", TARGETS.practiceTop10)
tgtButton(1 / 3, 1 / 3, "#1 223:40", TARGETS.practiceTop1)
tgtButton(2 / 3, 1 / 3, "Endless", 999999)

local pbBack = Instance.new("Frame")
pbBack.BackgroundColor3 = Color3.fromRGB(38, 42, 53)
pbBack.BorderSizePixel = 0
pbBack.Position = UDim2.new(0, 0, 0, 236)
pbBack.Size = UDim2.new(1, 0, 0, 22)
pbBack.Parent = body
corner(pbBack, 6)

local pbFill = Instance.new("Frame")
pbFill.BackgroundColor3 = ACCENT
pbFill.BorderSizePixel = 0
pbFill.Size = UDim2.new(0, 0, 1, 0)
pbFill.Parent = pbBack
corner(pbFill, 6)

local pbText = Instance.new("TextLabel")
pbText.BackgroundTransparency = 1
pbText.Size = UDim2.new(1, 0, 1, 0)
pbText.Font = Enum.Font.GothamBold
pbText.TextSize = 11
pbText.TextColor3 = Color3.fromRGB(255, 255, 255)
pbText.Text = "—"
pbText.ZIndex = 2
pbText.Parent = pbBack

local godRow = Instance.new("Frame")
godRow.BackgroundColor3 = PANEL
godRow.BorderSizePixel = 0
godRow.Position = UDim2.new(0, 0, 0, 266)
godRow.Size = UDim2.new(1, 0, 0, 32)
godRow.Parent = body
corner(godRow, 8)

local godLbl = Instance.new("TextLabel")
godLbl.BackgroundTransparency = 1
godLbl.Position = UDim2.new(0, 12, 0, 0)
godLbl.Size = UDim2.new(1, -70, 1, 0)
godLbl.Font = Enum.Font.GothamBold
godLbl.TextSize = 12
godLbl.TextColor3 = TXT
godLbl.TextXAlignment = Enum.TextXAlignment.Left
godLbl.Text = "Immortality (godmode)"
godLbl.Parent = godRow

local godTog = Instance.new("TextButton")
godTog.Position = UDim2.new(1, -56, 0.5, -11)
godTog.Size = UDim2.new(0, 46, 0, 22)
godTog.BackgroundColor3 = ACCENT
godTog.Text = "ON"
godTog.Font = Enum.Font.GothamBold
godTog.TextSize = 11
godTog.TextColor3 = Color3.fromRGB(10, 12, 16)
godTog.BorderSizePixel = 0
godTog.Parent = godRow
corner(godTog, 6)

local info = Instance.new("TextLabel")
info.BackgroundTransparency = 1
info.Position = UDim2.new(0, 2, 0, 304)
info.Size = UDim2.new(1, -4, 0, 56)
info.Font = Enum.Font.Gotham
info.TextSize = 11
info.TextColor3 = SUB
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextWrapped = true
info.Text = ""
info.Parent = body

local unloadBtn = makeButton(body, 366, 36, "UNLOAD", ACCENT2)

local function setActiveButtons()
    farmBtn.BackgroundColor3 = (State.mode == "farm") and ACCENT or PANEL
    farmBtn.TextColor3 = (State.mode == "farm") and Color3.fromRGB(10, 12, 16) or TXT
    lbBtn.BackgroundColor3 = (State.mode == "lb") and ACCENT or PANEL
    lbBtn.TextColor3 = (State.mode == "lb") and Color3.fromRGB(10, 12, 16) or TXT
end

farmBtn.MouseButton1Click:Connect(function()
    setMode("farm")
    setActiveButtons()
end)
lbBtn.MouseButton1Click:Connect(function()
    setMode("lb")
    setActiveButtons()
end)
godTog.MouseButton1Click:Connect(function()
    State.god = not State.god
    godTog.Text = State.god and "ON" or "OFF"
    godTog.BackgroundColor3 = State.god and ACCENT or Color3.fromRGB(70, 76, 90)
    godTog.TextColor3 = State.god and Color3.fromRGB(10, 12, 16) or TXT
    dot.BackgroundColor3 = State.god and ACCENT or ACCENT2
end)

local function unload()
    State.loaded = false
    State.god = false
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

State.threads.ui = task.spawn(function()
    while State.loaded do
        local ls = lp:FindFirstChild("leaderstats")
        local cash = ls and ls:FindFirstChild("Cash")
        local level = ls and ls:FindFirstChild("Level")
        local wins = ls and ls:FindFirstChild("Wins")
        local kills = ls and ls:FindFirstChild("Kills")
        vCash.Text = cash and comma(cash.Value) or "-"
        vLevel.Text = level and tostring(level.Value) or "-"
        vWins.Text = wins and tostring(wins.Value) or "-"
        vKills.Text = kills and tostring(kills.Value) or "-"
        vGpb.Text = fmt(lp:GetAttribute("GamePersonalBest") or 0)
        vPpb.Text = fmt(lp:GetAttribute("PracticePersonalBest") or 0)

        local survNow = 0
        if State.practiceStart and lp:GetAttribute("PracticeActive") == true then
            survNow = os.clock() - State.practiceStart
        end
        vSurv.Text = fmt(survNow)

        local role = lp:GetAttribute("RoundRole") or "lobby"
        local practiceActive = lp:GetAttribute("PracticeActive") == true
        vRole.Text = practiceActive and "practice" or role

        local lvNum = level and level.Value or 0
        if State.mode == "lb" then
            local best = math.max(survNow, lp:GetAttribute("PracticePersonalBest") or 0)
            local frac = math.clamp(best / State.target, 0, 1)
            pbFill.Size = UDim2.new(frac, 0, 1, 0)
            pbFill.BackgroundColor3 = frac >= 1 and ACCENT or Color3.fromRGB(90, 170, 255)
            pbText.Text = fmt(best) .. " / " .. fmt(State.target)
            if lvNum < 10 then
                info.TextColor3 = ACCENT2
                info.Text = "Level " .. lvNum .. " < 10 — для зачёта в лидерборд аккаунт должен быть Lvl 10+ и 30+ дней. Сначала фарми Cash/XP."
            else
                info.TextColor3 = SUB
                info.Text = "Practice top-10 = 67:00, #1 = 223:40. Лучшее пишется на лету. Не выходи из практики — таймер сбросится."
            end
        elseif State.mode == "farm" then
            pbFill.Size = UDim2.new(0, 0, 1, 0)
            pbText.Text = "round farm"
            info.TextColor3 = SUB
            info.Text = "Иммортал в раундах: побеждаешь каждый раунд → Cash+XP+Wins+квесты. Каждая секунда выживания ≈ 1 cash / 2 xp + бонус победителя."
        else
            pbFill.Size = UDim2.new(0, 0, 1, 0)
            pbText.Text = "выбери режим"
            info.TextColor3 = SUB
            info.Text = "FARM — качать Cash/XP/Wins/уровень. LEADERBOARD — встать в топ практики (выживание). Анти-чит и анти-афк уже активны."
        end

        task.wait(0.4)
    end
end)

setActiveButtons()
