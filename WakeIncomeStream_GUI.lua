-- Auto WakeIncomeStream + GUI управление
-- Tycoon9 / Remotes / WakeIncomeStream :InvokeServer("LemonStand")

--========================== ЛОГИКА ==========================--
local args = { "LemonStand" }

local remote = workspace
    :WaitForChild("Tycoon9")
    :WaitForChild("Remotes")
    :WaitForChild("WakeIncomeStream")

local State = getgenv().WakeIncome or {}
getgenv().WakeIncome = State
State.Running   = State.Running   or false
State.Interval  = State.Interval  or 0.05
State.TotalCalls = State.TotalCalls or 0
State.Loop      = nil  -- активный поток

-- если старый цикл из прошлого скрипта ещё крутится — гасим
getgenv().WakeIncomeRunning = false

local function startLoop()
    if State.Running then return end
    State.Running = true
    State.Loop = task.spawn(function()
        while State.Running do
            task.spawn(function()
                local ok = pcall(function()
                    remote:InvokeServer(unpack(args))
                end)
                if ok then
                    State.TotalCalls = State.TotalCalls + 1
                end
            end)
            task.wait(State.Interval)
        end
    end)
end

local function stopLoop()
    State.Running = false
end

--========================== GUI ==========================--
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- удалить старый GUI если был
local parentGui = (gethui and gethui()) or game:GetService("CoreGui")
local old = parentGui:FindFirstChild("WakeIncomeGUI")
if old then old:Destroy() end

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
    return c
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WakeIncomeGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = parentGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, 260, 0, 200)
Main.Position = UDim2.new(0, 40, 0, 120)
Main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = ScreenGui
corner(Main, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 75)
stroke.Thickness = 1
stroke.Parent = Main

-- Заголовок
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main
corner(TitleBar, 12)

local TitleFix = Instance.new("Frame") -- скрыть нижние скругления у тайтла
TitleFix.Size = UDim2.new(1, 0, 0, 12)
TitleFix.Position = UDim2.new(0, 0, 1, -12)
TitleFix.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
TitleFix.BorderSizePixel = 0
TitleFix.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.Text = "🍋 Wake Income"
Title.TextColor3 = Color3.fromRGB(235, 235, 245)
Title.TextSize = 15
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -32, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 70)
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = TitleBar
corner(CloseBtn, 6)

-- Статус
local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -24, 0, 22)
Status.Position = UDim2.new(0, 12, 0, 44)
Status.BackgroundTransparency = 1
Status.Font = Enum.Font.Gotham
Status.Text = "Статус: остановлен"
Status.TextColor3 = Color3.fromRGB(180, 180, 195)
Status.TextSize = 13
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Main

-- Счётчики
local Counter = Instance.new("TextLabel")
Counter.Size = UDim2.new(1, -24, 0, 20)
Counter.Position = UDim2.new(0, 12, 0, 66)
Counter.BackgroundTransparency = 1
Counter.Font = Enum.Font.Gotham
Counter.Text = "Вызовов: 0   |   0/сек"
Counter.TextColor3 = Color3.fromRGB(120, 200, 140)
Counter.TextSize = 13
Counter.TextXAlignment = Enum.TextXAlignment.Left
Counter.Parent = Main

-- Toggle кнопка
local Toggle = Instance.new("TextButton")
Toggle.Size = UDim2.new(1, -24, 0, 40)
Toggle.Position = UDim2.new(0, 12, 0, 94)
Toggle.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
Toggle.Text = "▶ СТАРТ"
Toggle.Font = Enum.Font.GothamBold
Toggle.TextSize = 16
Toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
Toggle.BorderSizePixel = 0
Toggle.Parent = Main
corner(Toggle, 8)

-- Интервал
local IntLabel = Instance.new("TextLabel")
IntLabel.Size = UDim2.new(0, 110, 0, 30)
IntLabel.Position = UDim2.new(0, 12, 0, 146)
IntLabel.BackgroundTransparency = 1
IntLabel.Font = Enum.Font.Gotham
IntLabel.Text = "Интервал (сек):"
IntLabel.TextColor3 = Color3.fromRGB(180, 180, 195)
IntLabel.TextSize = 13
IntLabel.TextXAlignment = Enum.TextXAlignment.Left
IntLabel.Parent = Main

local IntBox = Instance.new("TextBox")
IntBox.Size = UDim2.new(0, 110, 0, 30)
IntBox.Position = UDim2.new(1, -122, 0, 146)
IntBox.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
IntBox.Text = tostring(State.Interval)
IntBox.Font = Enum.Font.GothamMedium
IntBox.TextSize = 14
IntBox.TextColor3 = Color3.fromRGB(235, 235, 245)
IntBox.ClearTextOnFocus = false
IntBox.BorderSizePixel = 0
IntBox.Parent = Main
corner(IntBox, 6)

--========================== ПОВЕДЕНИЕ ==========================--
local function refresh()
    if State.Running then
        Toggle.Text = "■ СТОП"
        Toggle.BackgroundColor3 = Color3.fromRGB(200, 70, 80)
        Status.Text = "Статус: РАБОТАЕТ"
        Status.TextColor3 = Color3.fromRGB(120, 200, 140)
    else
        Toggle.Text = "▶ СТАРТ"
        Toggle.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
        Status.Text = "Статус: остановлен"
        Status.TextColor3 = Color3.fromRGB(180, 180, 195)
    end
end

Toggle.MouseButton1Click:Connect(function()
    if State.Running then
        stopLoop()
    else
        startLoop()
    end
    refresh()
end)

IntBox.FocusLost:Connect(function()
    local n = tonumber(IntBox.Text)
    if n and n > 0 then
        State.Interval = math.clamp(n, 0.01, 60)
    end
    IntBox.Text = tostring(State.Interval)
end)

CloseBtn.MouseButton1Click:Connect(function()
    stopLoop()
    ScreenGui:Destroy()
end)

-- счётчик вызовов в секунду
task.spawn(function()
    local last = State.TotalCalls
    while ScreenGui.Parent do
        task.wait(1)
        local now = State.TotalCalls
        local perSec = now - last
        last = now
        Counter.Text = string.format("Вызовов: %d   |   %d/сек", now, perSec)
    end
end)

--========================== DRAG ==========================--
local dragging, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

refresh()
print("[WakeIncome] GUI загружен ✅")
