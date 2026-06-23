-- Спам Remote_Event (skill activation, weaponType=Sword) с GUI-переключателем
-- ТУРБО: rate-based, несколько fire за кадр (Heartbeat), цель до 300 fire/сек

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local RemoteEvent = ReplicatedStorage:WaitForChild("Remote_Event")

local args = {
    buffer.fromstring("\147\022\204\140\145\137\162tp\199\002\147\203@\142\177\030\192\000\000\000\203@K\254\028\000\000\000\000\203\192iL\153@\000\000\000\172activationId\020\168actionId\169\233\149\191\229\137\145/C1\162we\195\172skillUseType\166manual\168position\199\002\147\203@\142\130\v\224\000\000\000\203@LC\231\000\000\000\000\203\192k&Z \000\000\000\166facing\199\002\147\203?\236c\129\192\000\000\000\000\203?\221\137\001\224\000\000\000\170weaponType\165Sword\174basisDirection\199\002\147\203?\215\163l\224\000\000\000\000\203?\237\188\191`\000\000\000")
}

----------------------------------------------------------------------
-- Состояние
----------------------------------------------------------------------
local enabled = false
local targetRate = 300          -- цель fire/сек
local MAX_RATE = 300            -- потолок
local MAX_PER_FRAME = 50        -- защита: не больше N fire за один кадр

local fireCount = 0             -- счётчик за последнюю секунду (для индикатора)

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local parentGui = (gethui and gethui()) or game:GetService("CoreGui")

local old = parentGui:FindFirstChild("SwordSkillSpamGUI")
if old then old:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SwordSkillSpamGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = parentGui

local Frame = Instance.new("Frame")
Frame.Size = UDim2.fromOffset(250, 200)
Frame.Position = UDim2.fromScale(0.5, 0.4)
Frame.AnchorPoint = Vector2.new(0.5, 0.5)
Frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = Frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(70, 70, 80)
stroke.Thickness = 1
stroke.Parent = Frame

-- Заголовок
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundTransparency = 1
Title.Text = "Sword Skill Spam — TURBO"
Title.TextColor3 = Color3.fromRGB(235, 235, 240)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = Frame

-- Кнопка вкл/выкл
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, -20, 0, 42)
ToggleBtn.Position = UDim2.fromOffset(10, 38)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
ToggleBtn.Text = "OFF"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 18
ToggleBtn.Parent = Frame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 8)
btnCorner.Parent = ToggleBtn

-- Подпись цели
local RateLabel = Instance.new("TextLabel")
RateLabel.Size = UDim2.new(1, -20, 0, 20)
RateLabel.Position = UDim2.fromOffset(10, 88)
RateLabel.BackgroundTransparency = 1
RateLabel.Text = "Цель fire/сек (1-300):"
RateLabel.TextColor3 = Color3.fromRGB(200, 200, 205)
RateLabel.Font = Enum.Font.Gotham
RateLabel.TextSize = 13
RateLabel.TextXAlignment = Enum.TextXAlignment.Left
RateLabel.Parent = Frame

-- Поле ввода цели
local RateBox = Instance.new("TextBox")
RateBox.Size = UDim2.new(1, -20, 0, 28)
RateBox.Position = UDim2.fromOffset(10, 110)
RateBox.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
RateBox.Text = tostring(targetRate)
RateBox.PlaceholderText = "300"
RateBox.TextColor3 = Color3.fromRGB(235, 235, 240)
RateBox.Font = Enum.Font.Gotham
RateBox.TextSize = 14
RateBox.ClearTextOnFocus = false
RateBox.Parent = Frame

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 6)
boxCorner.Parent = RateBox

-- Индикатор реальной частоты
local StatLabel = Instance.new("TextLabel")
StatLabel.Size = UDim2.new(1, -20, 0, 34)
StatLabel.Position = UDim2.fromOffset(10, 148)
StatLabel.BackgroundTransparency = 1
StatLabel.Text = "Факт: 0 fire/сек   [F — вкл/выкл]"
StatLabel.TextColor3 = Color3.fromRGB(150, 220, 150)
StatLabel.Font = Enum.Font.Gotham
StatLabel.TextSize = 13
StatLabel.TextWrapped = true
StatLabel.Parent = Frame

----------------------------------------------------------------------
-- Логика
----------------------------------------------------------------------
local function setEnabled(state)
    enabled = state
    if enabled then
        ToggleBtn.Text = "ON"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 170, 80)
    else
        ToggleBtn.Text = "OFF"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
    end
end

ToggleBtn.MouseButton1Click:Connect(function()
    setEnabled(not enabled)
end)

RateBox.FocusLost:Connect(function()
    local n = tonumber(RateBox.Text)
    if n then
        n = math.clamp(math.floor(n), 1, MAX_RATE)
        targetRate = n
    end
    RateBox.Text = tostring(targetRate)
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.F then
        setEnabled(not enabled)
    end
end)

----------------------------------------------------------------------
-- ТУРБО-цикл: квота по dt, несколько fire за кадр
----------------------------------------------------------------------
local accumulator = 0
local statTimer = 0

local conn
conn = RunService.Heartbeat:Connect(function(dt)
    if not ScreenGui.Parent then
        conn:Disconnect()
        return
    end

    if enabled then
        accumulator = accumulator + dt * targetRate
        local toFire = math.floor(accumulator)
        if toFire > MAX_PER_FRAME then toFire = MAX_PER_FRAME end
        accumulator = accumulator - toFire
        for _ = 1, toFire do
            RemoteEvent:FireServer(unpack(args))
            fireCount = fireCount + 1
        end
    else
        accumulator = 0
    end

    -- индикатор раз в секунду
    statTimer = statTimer + dt
    if statTimer >= 1 then
        StatLabel.Text = string.format("Факт: %d fire/сек   [F — вкл/выкл]", fireCount)
        fireCount = 0
        statTimer = 0
    end
end)
