-- Strongman Simulator | Energy GUI
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")
local VirtualUser   = game:GetService("VirtualUser")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()

-- Anti-AFK
lp.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- Libs
local TGSItems = require(workspace.Lib.Items.TGSItems)
local ItemCat  = require(workspace.Lib.Items.ItemCategoryEnum)

-- Утилиты ------------------------------------------------------------------

local function getDragFolder()
    return workspace.PlayerDraggables:FindFirstChild(tostring(lp.UserId))
end

local function getDraggedItems()
    local f = getDragFolder()
    return f and f:GetChildren() or {}
end

local function findGoals()
    local goals = {}
    local function scan(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child.Name == "Goal" and child:IsA("BasePart") then
                goals[#goals + 1] = child
            end
            if child:IsA("Model") or child:IsA("Folder") then
                scan(child)
            end
        end
    end
    if workspace:FindFirstChild("Areas") then
        scan(workspace.Areas)
    end
    return goals
end

local function closestGoal(goals)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local pos = hrp.Position
    local best, bestD = nil, math.huge
    for _, g in ipairs(goals) do
        local d = (g.Position - pos).Magnitude
        if d < bestD then bestD = d; best = g end
    end
    return best, bestD
end

local function passItemThrough(item, goal)
    -- Берём Part предмета
    local part
    if item:IsA("Model") then
        part = item.PrimaryPart
    elseif item:IsA("BasePart") then
        part = item
    end
    if not part then return end

    -- Сначала кладём чуть снаружи Goal, потом внутрь — Touched сработает
    local gCF  = goal.CFrame
    local outsideCF = gCF * CFrame.new(0, 0, goal.Size.Z * 0.5 + 4)
    local insideCF  = gCF

    if item:IsA("Model") then
        item:PivotTo(CFrame.new(outsideCF.Position + Vector3.new(0, 3, 0)))
        task.wait(0.04)
        item:PivotTo(CFrame.new(insideCF.Position + Vector3.new(0, 3, 0)))
    else
        item.CFrame = CFrame.new(outsideCF.Position + Vector3.new(0, 3, 0))
        task.wait(0.04)
        item.CFrame = CFrame.new(insideCF.Position + Vector3.new(0, 3, 0))
    end
end

local function fmtNum(n)
    if n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9  then return string.format("%.2fB", n/1e9)
    elseif n >= 1e6  then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3  then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

-- GUI ----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "StrongmanEnergyGUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = lp.PlayerGui

local W, H = 270, 300

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, W, 0, H)
main.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
main.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

-- Тень (stroke)
local stroke = Instance.new("UIStroke")
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Color = Color3.fromRGB(0, 200, 100)
stroke.Thickness = 1.5
stroke.Transparency = 0.5
stroke.Parent = main

-- Шапка
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(0, 180, 90)
header.BorderSizePixel = 0
header.Parent = main
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = header
    local fix = Instance.new("Frame")
    fix.Size = UDim2.new(1, 0, 0.5, 0)
    fix.Position = UDim2.new(0, 0, 0.5, 0)
    fix.BackgroundColor3 = header.BackgroundColor3
    fix.BorderSizePixel = 0
    fix.Parent = header
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, 0, 1, 0)
    t.BackgroundTransparency = 1
    t.Text = "⚡  STRONGMAN  ·  ENERGY"
    t.Font = Enum.Font.GothamBold
    t.TextSize = 14
    t.TextColor3 = Color3.new(1,1,1)
    t.Parent = header
end

-- Панель энергии
local function mkFrame(py, ph, color)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -20, 0, ph)
    f.Position = UDim2.new(0, 10, 0, py)
    f.BackgroundColor3 = color or Color3.fromRGB(22, 22, 32)
    f.BorderSizePixel = 0
    f.Parent = main
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
    return f
end

local function mkLabel(parent, text, size, color, bold, ypos, xalign)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 0, size + 6)
    l.Position = UDim2.new(0, 8, 0, ypos or 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextSize = size
    l.TextColor3 = color or Color3.fromRGB(200, 200, 220)
    l.TextXAlignment = xalign or Enum.TextXAlignment.Center
    l.Parent = parent
    return l
end

-- Блок: текущая энергия
local eBox = mkFrame(50, 62)
mkLabel(eBox, "ТЕКУЩАЯ ЭНЕРГИЯ", 10, Color3.fromRGB(130,130,150), false, 4)
local eVal = mkLabel(eBox, "---", 22, Color3.fromRGB(255, 220, 50), true, 20)

-- Блок: скорость
local rBox = mkFrame(122, 50)
local rLbl = mkLabel(rBox, "Скорость: 5 /сек", 12, Color3.fromRGB(200,200,220), false, 6, Enum.TextXAlignment.Left)
rLbl.Size = UDim2.new(1, -90, 1, 0)
rLbl.Position = UDim2.new(0, 10, 0, 0)

local function mkBtn(parent, text, xPos, size, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, size, 0, size)
    b.Position = UDim2.new(1, xPos, 0.5, -size/2)
    b.BackgroundColor3 = color or Color3.fromRGB(35, 35, 55)
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 16
    b.TextColor3 = Color3.new(1,1,1)
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local rate   = 5
local minBtn = mkBtn(rBox, "−", -72, 32)
local plusBtn = mkBtn(rBox, "+", -35, 32)

-- Блок: статус
local sBox   = mkFrame(182, 40)
local sLbl   = mkLabel(sBox, "⏸  ожидание", 12, Color3.fromRGB(150,150,170), false, 4)

-- Кнопка старт/стоп
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 42)
toggleBtn.Position = UDim2.new(0, 10, 0, 232)
toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 185, 90)
toggleBtn.Text = "▶   СТАРТ"
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 15
toggleBtn.TextColor3 = Color3.new(1,1,1)
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = main
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)

-- Кнопка выгрузки
local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -20, 0, 26)
unloadBtn.Position = UDim2.new(0, 10, 0, 264)
unloadBtn.BackgroundColor3 = Color3.fromRGB(50, 20, 20)
unloadBtn.Text = "✕  выгрузить скрипт"
unloadBtn.Font = Enum.Font.Gotham
unloadBtn.TextSize = 11
unloadBtn.TextColor3 = Color3.fromRGB(180, 80, 80)
unloadBtn.BorderSizePixel = 0
unloadBtn.AutoButtonColor = false
unloadBtn.Parent = main
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 6)

-- Логика ---------------------------------------------------------------

local running   = false
local farmCo

-- Обновление энергии каждый кадр
RunService.Heartbeat:Connect(function()
    pcall(function()
        local v = TGSItems.GetItemInfo(lp, ItemCat.Currency, "Default") or 0
        eVal.Text = fmtNum(v)
    end)
end)

-- Кнопки скорости
local function updateRateLbl()
    rLbl.Text = "Скорость: " .. rate .. " /сек"
end

minBtn.MouseButton1Click:Connect(function()
    rate = math.max(1, rate - 1)
    updateRateLbl()
end)
plusBtn.MouseButton1Click:Connect(function()
    rate = math.min(30, rate + 1)
    updateRateLbl()
end)

-- Hover-анимации кнопок
local function hoverEffect(btn, base, hov)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = hov}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = base}):Play()
    end)
end
hoverEffect(toggleBtn, Color3.fromRGB(0,185,90), Color3.fromRGB(0,210,105))
hoverEffect(unloadBtn, Color3.fromRGB(50,20,20), Color3.fromRGB(70,30,30))
hoverEffect(minBtn, Color3.fromRGB(35,35,55), Color3.fromRGB(55,55,80))
hoverEffect(plusBtn, Color3.fromRGB(35,35,55), Color3.fromRGB(55,55,80))

-- Основной цикл фарма
local allGoals = findGoals()

local function farmLoop()
    while running do
        -- Обновляем цели на случай смены зоны
        allGoals = findGoals()
        local goal, goalDist = closestGoal(allGoals)

        if not goal then
            sLbl.Text = "❌  Goal не найдена в этой зоне"
            task.wait(1)
            continue
        end

        local items = getDraggedItems()

        if #items == 0 then
            sLbl.Text = "⏳  Нет предметов — подними их в стартовой зоне"
            task.wait(0.4)
            continue
        end

        sLbl.Text = string.format("✅  %d предм. | до Goal: %dm", #items, math.round(goalDist))

        local wait = 1 / rate
        for _, item in ipairs(items) do
            if not running then break end
            pcall(passItemThrough, item, goal)
            task.wait(wait)
        end

        -- Небольшая пауза между итерациями
        task.wait(0.1)
    end
end

local function startFarm()
    running = true
    allGoals = findGoals()
    toggleBtn.BackgroundColor3 = Color3.fromRGB(185, 50, 50)
    toggleBtn.Text = "⏹   СТОП"
    farmCo = task.spawn(farmLoop)
end

local function stopFarm()
    running = false
    if farmCo then task.cancel(farmCo); farmCo = nil end
    toggleBtn.BackgroundColor3 = Color3.fromRGB(0, 185, 90)
    toggleBtn.Text = "▶   СТАРТ"
    sLbl.Text = "⏸  остановлен"
end

toggleBtn.MouseButton1Click:Connect(function()
    if running then stopFarm() else startFarm() end
end)

-- Обновление символа персонажа при респауне
lp.CharacterAdded:Connect(function(c)
    char = c
    stopFarm()
    sLbl.Text = "⏸  персонаж обновлён"
end)

-- Выгрузка
unloadBtn.MouseButton1Click:Connect(function()
    stopFarm()
    gui:Destroy()
end)
