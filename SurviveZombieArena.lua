--// ZOMBIE KILLAURA
--// K — старт/стоп. Бьёт зомби из workspace.Zombies_Local (имя "Zombie_<ID>").
--// Оружие берётся ВЖИВУЮ из экипированного, координаты — реальные.
--// Справа: панель статистики + панель настроек (режим, кол-во целей, скорость).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local FORCE_WEAPON = nil          -- nil = авто (что в руках); или строка вроде "ShotGun"
local KEY          = Enum.KeyCode.K
local GEAR_KEY     = Enum.KeyCode.P     -- спам покупки гира
local GEAR_NAME    = "SoulHarvester"
local GEAR_SPEED   = 0.05              -- секунд между покупками

local GunHit = ReplicatedStorage:WaitForChild("GunRemotes"):WaitForChild("GunHit")
local GearPurchase = ReplicatedStorage:WaitForChild("GearRemotes"):WaitForChild("GearPurchase")

-- ===== Настройки (меняются из GUI) =====
local settings = {
    mode    = "All",   -- "All" | "Nearest" | "Random"
    targets = 20,      -- сколько зомби за волну (для Nearest/Random), 1..20
    speed   = 0.1,     -- секунд между волнами, 0.01..1
}

-- ===== Состояние / счётчики =====
local running    = false
local totalSent  = 0
local cps        = 0
local sentWindow = 0
local windowStart = os.clock()

local gearRunning = false   -- спам покупки гира (P)
local gearBought  = 0

-- ===== Хелперы =====
local function getZombies()
    local out = {}
    local folder = Workspace:FindFirstChild("Zombies_Local")
    if not folder then return out end
    for _, z in ipairs(folder:GetChildren()) do
        local id = tonumber(z.Name:match("(%d+)$"))
        local root = z:FindFirstChild("HumanoidRootPart") or z.PrimaryPart
        if id and root then
            out[#out + 1] = { id = id, model = z, root = root }
        end
    end
    return out
end

local function zombieCount()
    local folder = Workspace:FindFirstChild("Zombies_Local")
    return folder and #folder:GetChildren() or 0
end

local function equippedWeapon()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    return tool and tool.Name or "—"
end

local function myPos()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position
end

-- Выбор целей по режиму
local function pickTargets()
    local zombies = getZombies()
    if settings.mode == "All" then
        return zombies
    elseif settings.mode == "Nearest" then
        local origin = myPos()
        if not origin then return {} end
        table.sort(zombies, function(a, b)
            return (a.root.Position - origin).Magnitude < (b.root.Position - origin).Magnitude
        end)
        local n = math.min(settings.targets, #zombies)
        local res = {}
        for i = 1, n do res[i] = zombies[i] end
        return res
    else -- Random
        -- частичное перемешивание Фишера-Йетса до нужного количества
        local n = math.min(settings.targets, #zombies)
        for i = 1, n do
            local j = math.random(i, #zombies)
            zombies[i], zombies[j] = zombies[j], zombies[i]
        end
        local res = {}
        for i = 1, n do res[i] = zombies[i] end
        return res
    end
end

-- ===== GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "KillAuraUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

local function makePanel(sizeY, posY)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(0, 240, 0, sizeY)
    f.Position = UDim2.new(1, -252, 0, posY)
    f.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    f.BackgroundTransparency = 0.12
    f.BorderSizePixel = 0
    f.Parent = gui
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
    local s = Instance.new("UIStroke", f)
    s.Color = Color3.fromRGB(80, 90, 120); s.Thickness = 1; s.Transparency = 0.3
    local p = Instance.new("UIPadding", f)
    p.PaddingTop = UDim.new(0, 10); p.PaddingBottom = UDim.new(0, 10)
    p.PaddingLeft = UDim.new(0, 12); p.PaddingRight = UDim.new(0, 12)
    local l = Instance.new("UIListLayout", f)
    l.Padding = UDim.new(0, 5); l.SortOrder = Enum.SortOrder.LayoutOrder
    return f
end

local function makeLabel(parent, order, size, bold)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, size)
    lbl.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    lbl.TextSize = size - 4
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextColor3 = Color3.fromRGB(235, 235, 245)
    lbl.LayoutOrder = order
    lbl.Parent = parent
    return lbl
end

-- ---- Панель статистики ----
local statsPanel = makePanel(194, 16)
local title = makeLabel(statsPanel, 1, 22, true); title.Text = "⚡ ZOMBIE KILLAURA"
title.TextColor3 = Color3.fromRGB(120, 200, 255)
local lStatus  = makeLabel(statsPanel, 2, 18)
local lWeapon  = makeLabel(statsPanel, 3, 18)
local lZombies = makeLabel(statsPanel, 4, 18)
local lRate    = makeLabel(statsPanel, 5, 18)
local lSent    = makeLabel(statsPanel, 6, 18)
local lGear    = makeLabel(statsPanel, 7, 18)
local lHint    = makeLabel(statsPanel, 8, 16); lHint.Text = "[K] килл-аура  [P] гир"
lHint.TextColor3 = Color3.fromRGB(150, 150, 165)

-- ---- Панель настроек ----
local cfgPanel = makePanel(232, 222)
local cTitle = makeLabel(cfgPanel, 1, 20, true); cTitle.Text = "⚙ Настройки режима"
cTitle.TextColor3 = Color3.fromRGB(255, 200, 120)

-- режимы (кнопки)
local modeLbl = makeLabel(cfgPanel, 2, 16); modeLbl.Text = "Режим:"
modeLbl.TextColor3 = Color3.fromRGB(180, 180, 195)

local modeRow = Instance.new("Frame")
modeRow.Size = UDim2.new(1, 0, 0, 28)
modeRow.BackgroundTransparency = 1
modeRow.LayoutOrder = 3
modeRow.Parent = cfgPanel
local modeRowLayout = Instance.new("UIListLayout", modeRow)
modeRowLayout.FillDirection = Enum.FillDirection.Horizontal
modeRowLayout.Padding = UDim.new(0, 4)

local modeButtons = {}
local modeDefs = { {"Nearest", "Ближние"}, {"Random", "Рандом"}, {"All", "Все"} }
local function refreshModeButtons()
    for _, b in ipairs(modeButtons) do
        local active = (b.mode == settings.mode)
        b.btn.BackgroundColor3 = active and Color3.fromRGB(80, 140, 220) or Color3.fromRGB(40, 40, 52)
        b.btn.TextColor3 = active and Color3.fromRGB(255,255,255) or Color3.fromRGB(190,190,200)
    end
end
for i, def in ipairs(modeDefs) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.333, -3, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.Text = def[2]
    btn.TextColor3 = Color3.fromRGB(190,190,200)
    btn.LayoutOrder = i
    btn.Parent = modeRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseButton1Click:Connect(function()
        settings.mode = def[1]
        refreshModeButtons()
    end)
    modeButtons[#modeButtons+1] = { mode = def[1], btn = btn }
end

-- универсальный ползунок
local function makeSlider(order, label, minV, maxV, default, decimals, onChange)
    local lbl = makeLabel(cfgPanel, order, 16)
    local function fmt(v)
        if decimals > 0 then return string.format("%."..decimals.."f", v) else return tostring(math.floor(v)) end
    end
    lbl.Text = label .. ": " .. fmt(default)
    lbl.TextColor3 = Color3.fromRGB(200, 200, 215)

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, 0, 0, 14)
    track.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
    track.BorderSizePixel = 0
    track.LayoutOrder = order + 0.5
    track.Parent = cfgPanel
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new((default-minV)/(maxV-minV), 0, 1, 0)
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new((default-minV)/(maxV-minV), 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 2
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local function setFromX(px)
        local rel = math.clamp((px - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local v = minV + rel * (maxV - minV)
        if decimals == 0 then v = math.floor(v + 0.5) end
        fill.Size = UDim2.new((v-minV)/(maxV-minV), 0, 1, 0)
        knob.Position = UDim2.new((v-minV)/(maxV-minV), 0, 0.5, 0)
        lbl.Text = label .. ": " .. fmt(v)
        onChange(v)
    end
    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true; setFromX(inp.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            setFromX(inp.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

makeSlider(4, "Целей одновременно", 1, 20, settings.targets, 0, function(v)
    settings.targets = math.floor(v)
end)
makeSlider(6, "Скорость (сек)", 0.01, 1, settings.speed, 2, function(v)
    settings.speed = v
end)

refreshModeButtons()

-- ===== Обновление статистики =====
RunService.RenderStepped:Connect(function()
    local now = os.clock()
    if now - windowStart >= 1 then
        cps = math.floor(sentWindow / (now - windowStart))
        sentWindow = 0
        windowStart = now
    end
    local modeName = ({All="Все", Nearest="Ближние", Random="Рандом"})[settings.mode]
    lStatus.Text  = "Статус: " .. (running and "🟢 АКТИВНА" or "🔴 выкл") .. " | " .. modeName
    lStatus.TextColor3 = running and Color3.fromRGB(120, 235, 140) or Color3.fromRGB(235, 120, 120)
    lWeapon.Text  = "Оружие: " .. equippedWeapon()
    lZombies.Text = "Зомби на карте: " .. zombieCount()
    lRate.Text    = "Вызовов/сек: " .. (running and cps or 0)
    lSent.Text    = "Всего отправлено: " .. totalSent
    lGear.Text    = "Гир [P]: " .. (gearRunning and ("🟢 ВКЛ ("..gearBought..")") or "🔴 выкл")
    lGear.TextColor3 = gearRunning and Color3.fromRGB(120, 235, 140) or Color3.fromRGB(150, 150, 165)
end)

-- ===== Основной цикл =====
local function loop()
    while running do
        local weapon = FORCE_WEAPON or equippedWeapon()
        if weapon ~= "—" then
            for _, z in ipairs(pickTargets()) do
                if z.model.Parent and z.root.Parent then
                    local p = z.root.Position
                    GunHit:FireServer(weapon, z.id, vector.create(p.X, p.Y, p.Z))
                    totalSent += 1
                    sentWindow += 1
                end
            end
        end
        task.wait(settings.speed)
    end
end

-- цикл спама покупки гира
local function gearLoop()
    while gearRunning do
        GearPurchase:FireServer(GEAR_NAME)
        gearBought += 1
        task.wait(GEAR_SPEED)
    end
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == KEY then
        running = not running
        if running then print("[KillAura] ВКЛ"); task.spawn(loop)
        else print("[KillAura] ВЫКЛ") end
    elseif input.KeyCode == GEAR_KEY then
        gearRunning = not gearRunning
        if gearRunning then
            print("[KillAura] спам гира '"..GEAR_NAME.."' ВКЛ")
            task.spawn(gearLoop)
        else
            print("[KillAura] спам гира ВЫКЛ")
        end
    end
end)

print("[KillAura] загружен. K — килл-аура, P — спам покупки '"..GEAR_NAME.."'. Панели справа.")
