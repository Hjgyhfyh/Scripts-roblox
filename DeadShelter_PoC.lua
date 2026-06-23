--[[
====================================================================
  Dead Shelter — Proof-of-Concept + GUI (security testing на СВОЕЙ игре)
====================================================================
   F-005  Pickup  — сбор любого Pickup-предмета без проверки дистанции
   F-006  Consume — употребление любого Consumable без дистанции
   F-009  DragDetector.Drag — remote-grab предмета к игроку
   F-010  SellPart — продажа без проверки близости (телепорт sellable -> Cash)
   F-007  SkipDayVote — один голос форсит пропуск дня
   F-004  CreateLobby — сервер доверяет клиентскому gamemode (лобби)

   Лобби: 94141670851856   |   Матч: 107802085750759
====================================================================
]]

--==================================================================
-- КОНФИГ
--==================================================================
local CONFIG = {
    VacuumLoot        = false,
    VacuumConsumables = false,
    AutoSellValuables = false,
    SkipDay           = false,

    MinSellPrice      = 30,
    SellDelay         = 0.35,
    StepDelay         = 0.03,
    Verbose           = true,

    Filter            = "ALL",  -- ALL / WEAPONS / VALUABLES / AMMO — что трогать
    MaxItems          = 0,      -- 0 = без лимита; иначе обработать не больше N предметов
    Selection         = {},     -- выбранные имена предметов для точечного подъёма

    SpoofGamemode     = "Easy",
    SpoofMaxPlayers   = 99,

    CenterPos         = Vector3.new(-2, 16, -2), -- центр выживания
    CenterRadius      = 15,   -- предметы ближе этого к центру не трогаем
    CenterSpread      = 12,   -- разброс по XZ, чтобы не складывать в одну точку

    ESP               = false, -- подсветка зомби
    Aim               = false, -- аим на ближайшего зомби (зажать ПКМ)
    AimFOV            = 250,   -- радиус захвата на экране (px)
    AimPart           = "Head",-- куда целиться: Head / HumanoidRootPart
}

--==================================================================
-- СЛУЖЕБНОЕ
--==================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local TeleportService   = game:GetService("TeleportService")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")

local LP = Players.LocalPlayer
local connections = {}      -- соединения для очистки при unload
local function track(c) connections[#connections + 1] = c; return c end
local LOBBY_PLACE = 94141670851856
local MATCH_PLACE = 107802085750759

-- лог в GUI-консоль (определяется ниже)
local guiLog
local function log(...)
    local parts = {}
    for _, v in ipairs({...}) do parts[#parts+1] = tostring(v) end
    local msg = table.concat(parts, " ")
    if CONFIG.Verbose then print("[DS-PoC]", msg) end
    if guiLog then guiLog(msg) end
end

local function char() return LP.Character or LP.CharacterAdded:Wait() end
local function root()
    local c = char()
    return c:FindFirstChild("HumanoidRootPart") or c:WaitForChild("HumanoidRootPart", 5)
end
local function getCash()
    local ls = LP:FindFirstChild("leaderstats")
    return ls and ls:FindFirstChild("Cash") and ls.Cash.Value or 0
end
local function remote(path)
    local cur = game
    for seg in path:gmatch("[^%.]+") do
        if not cur then return nil end
        cur = cur:FindFirstChild(seg)
    end
    return cur
end
local function mainPart(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model end
    return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

-- ключевые слова категорий (имена предметов карты)
local KW = {
    WEAPONS = { "glock", "shotgun", "katana", "spiked bat", "dynamite", "molotov",
                "desert eagle", "sawed", "pump", "auto turret", "rusted pipe", "deagle" },
    AMMO    = { "ammo" },
    VALUABLES = { "bar", "vase", "painting", "laptop", "printer", "keycard" },
}
local FILTERS = { "ALL", "WEAPONS", "VALUABLES", "AMMO" }
local FILTER_RU = { ALL = "Всё", WEAPONS = "Оружие", VALUABLES = "Ценное", AMMO = "Патроны" }

local function nameHas(name, list)
    name = name:lower()
    for _, k in ipairs(list) do if name:find(k, 1, true) then return true end end
    return false
end

-- проходит ли предмет текущий фильтр CONFIG.Filter
local function matchesFilter(item)
    local f = CONFIG.Filter
    if f == "ALL" then return true end
    local nm = item.Name
    if f == "WEAPONS" then return nameHas(nm, KW.WEAPONS) end
    if f == "AMMO"    then return nameHas(nm, KW.AMMO) end
    if f == "VALUABLES" then
        local tag = item:FindFirstChild("PriceTag")
        return (tag and tag.Value >= CONFIG.MinSellPrice) or nameHas(nm, KW.VALUABLES)
    end
    return true
end

--==================================================================
-- ЭКСПЛОЙТЫ
--==================================================================
local function vacuumLoot()                     -- F-005
    local Pickup = remote("ReplicatedStorage.DragEvents.Pickup")
    local df = Workspace:FindFirstChild("DraggableFolder")
    if not (Pickup and df) then return 0 end
    local n = 0
    for _, item in ipairs(df:GetChildren()) do
        if item:FindFirstChild("Pickup", true) and matchesFilter(item) then
            pcall(function() Pickup:FireServer(item) end)
            n += 1; task.wait(CONFIG.StepDelay)
            if CONFIG.MaxItems > 0 and n >= CONFIG.MaxItems then break end
        end
    end
    log(("F-005: подобрано %d [%s]"):format(n, FILTER_RU[CONFIG.Filter])); return n
end

local function vacuumConsumables()              -- F-006
    local Consume = remote("ReplicatedStorage.DragEvents.Consume")
    local df = Workspace:FindFirstChild("DraggableFolder")
    if not (Consume and df) then return 0 end
    local n = 0
    for _, item in ipairs(df:GetChildren()) do
        if item:FindFirstChild("Consumable", true) and matchesFilter(item) then
            pcall(function() Consume:FireServer(item) end)
            n += 1; task.wait(CONFIG.StepDelay)
            if CONFIG.MaxItems > 0 and n >= CONFIG.MaxItems then break end
        end
    end
    log(("F-006: употреблено %d [%s]"):format(n, FILTER_RU[CONFIG.Filter])); return n
end

local function pickupSelected()                 -- поднять только выбранные имена
    local Pickup = remote("ReplicatedStorage.DragEvents.Pickup")
    local df = Workspace:FindFirstChild("DraggableFolder")
    if not (Pickup and df) then return 0 end
    local n = 0
    for _, item in ipairs(df:GetChildren()) do
        if CONFIG.Selection[item.Name] and item:FindFirstChild("Pickup", true) then
            pcall(function() Pickup:FireServer(item) end)
            n += 1; task.wait(CONFIG.StepDelay)
            if CONFIG.MaxItems > 0 and n >= CONFIG.MaxItems then break end
        end
    end
    log(("Поднято выбранных: %d"):format(n)); return n
end

local function collectDeadbucks()               -- собрать все Deadbuck
    local Pickup = remote("ReplicatedStorage.DragEvents.Pickup")
    local df = Workspace:FindFirstChild("DraggableFolder")
    if not (Pickup and df) then return 0 end
    local n = 0
    for _, it in ipairs(df:GetChildren()) do
        if it.Name == "Deadbuck" and it:FindFirstChild("Pickup", true) then
            pcall(function() Pickup:FireServer(it) end); n += 1; task.wait(CONFIG.StepDelay)
        end
    end
    log(("Собрано Deadbuck: %d"):format(n)); return n
end

local function throwDeadbucksFront()            -- стащить все Deadbuck к точке перед собой
    local df = Workspace:FindFirstChild("DraggableFolder")
    local r = root()
    if not (df and r) then return 0 end
    local target = (r.CFrame * CFrame.new(0, 0, -6)).Position -- 6 студов перед игроком
    local n = 0
    for _, it in ipairs(df:GetChildren()) do
        if it.Name == "Deadbuck" then
            local dd = it:FindFirstChild("DragDetector", true)
            if dd and dd:FindFirstChild("Drag") then pcall(function() dd.Drag:FireServer(true) end) end
            local off = Vector3.new(math.random(-3, 3), math.random(0, 3), math.random(-3, 3))
            pcall(function() it:PivotTo(CFrame.new(target + off)) end)
            if dd and dd:FindFirstChild("Drag") then pcall(function() dd.Drag:FireServer(false) end) end
            n += 1; task.wait(CONFIG.StepDelay)
        end
    end
    log(("Кинуто Deadbuck перед собой: %d"):format(n)); return n
end

-- зомби живут в Workspace.Enemies (исключаем игроков и мирных NPC вроде Noob)
local function getZombies()
    local list = {}
    local folder = Workspace:FindFirstChild("Enemies")
    local pool = folder and folder:GetChildren() or Workspace:GetChildren()
    for _, m in ipairs(pool) do
        if m:IsA("Model") and not Players:GetPlayerFromCharacter(m) then
            local hum = m:FindFirstChildOfClass("Humanoid")
            local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            if hum and hrp and hum.Health > 0 then
                list[#list + 1] = { model = m, hum = hum, hrp = hrp }
            end
        end
    end
    return list
end

local function getSellPart()
    local pawn = Workspace:FindFirstChild("Noob's Pawnshop")
    if not pawn then return nil end
    local extract = pawn:FindFirstChild("SellExtract")
    return extract and extract:FindFirstChild("SellPart")
end

local function sellOne(item, sellPart)          -- F-009 + F-010
    local part = mainPart(item)
    if not part then return false end
    local dd = item:FindFirstChild("DragDetector", true)
    if dd and dd:FindFirstChild("Drag") then pcall(function() dd.Drag:FireServer(true) end) end
    pcall(function() item:PivotTo(sellPart.CFrame * CFrame.new(0, 3, 0)) end)
    task.wait(0.1)
    local touchPart = part
    for _, d in ipairs(item:GetDescendants()) do
        if d:IsA("BasePart") and d.CanTouch then touchPart = d break end
    end
    pcall(function()
        firetouchinterest(touchPart, sellPart, 0)
        firetouchinterest(touchPart, sellPart, 1)
    end)
    if dd and dd:FindFirstChild("Drag") then pcall(function() dd.Drag:FireServer(false) end) end
    return true
end

local function autoSellValuables()
    local df = Workspace:FindFirstChild("DraggableFolder")
    local sellPart = getSellPart()
    if not (df and sellPart) then log("F-010: SellPart не найден"); return 0 end
    local valuables = {}
    for _, item in ipairs(df:GetChildren()) do
        local tag = item:FindFirstChild("PriceTag")
        if tag and tag.Value >= CONFIG.MinSellPrice and matchesFilter(item) then
            table.insert(valuables, { item = item, price = tag.Value })
        end
    end
    table.sort(valuables, function(a, b) return a.price > b.price end)
    local before = getCash(); local n = 0
    for _, e in ipairs(valuables) do
        if e.item and e.item.Parent then
            sellOne(e.item, sellPart); n += 1; task.wait(CONFIG.SellDelay)
            if CONFIG.MaxItems > 0 and n >= CONFIG.MaxItems then break end
        end
    end
    task.wait(1)
    log(("F-009/F-010: продано %d, Cash %d->%d (+%d)"):format(n, before, getCash(), getCash()-before))
    return n
end

local function skipDay()                        -- F-007
    local r = remote("ReplicatedStorage.RemoteEvents.Events.SkipDayVote")
    if not r then return false end
    pcall(function() r:FireServer() end); log("F-007: голос за пропуск дня"); return true
end

local function gatherToCenter(pos)              -- собрать все предметы карты в центр
    pos = pos or CONFIG.CenterPos
    local df = Workspace:FindFirstChild("DraggableFolder")
    if not df then log("DraggableFolder не найден"); return 0 end
    local n = 0
    for _, item in ipairs(df:GetChildren()) do
        local part = mainPart(item)
        if part and (part.Position - pos).Magnitude > CONFIG.CenterRadius and matchesFilter(item) then
            local dd = item:FindFirstChild("DragDetector", true)
            -- начать drag-сессию -> клиент получает контроль над позицией
            if dd and dd:FindFirstChild("Drag") then pcall(function() dd.Drag:FireServer(true) end) end
            local s = CONFIG.CenterSpread
            local off = Vector3.new(math.random(-s, s), math.random(0, 6), math.random(-s, s))
            pcall(function() item:PivotTo(CFrame.new(pos + off)) end)
            if dd and dd:FindFirstChild("Drag") then pcall(function() dd.Drag:FireServer(false) end) end
            n += 1; task.wait(CONFIG.StepDelay)
            if CONFIG.MaxItems > 0 and n >= CONFIG.MaxItems then break end
        end
    end
    log(("Собрано в центр (%d,%d,%d): %d [%s]"):format(pos.X, pos.Y, pos.Z, n, FILTER_RU[CONFIG.Filter])); return n
end

local function dropAllItems()                   -- выброс всех предметов
    local Drop = remote("ReplicatedStorage.DragEvents.Drop")
    if not Drop then log("Drop remote не найден"); return 0 end
    local sources = {}
    local c = LP.Character
    if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") then sources[#sources+1] = t end end end
    local bp = LP:FindFirstChild("Backpack")
    if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then sources[#sources+1] = t end end end
    local n = 0
    for _, tool in ipairs(sources) do
        if matchesFilter(tool) then
            pcall(function() Drop:FireServer(tool) end)
            n += 1; task.wait(CONFIG.StepDelay)
            if CONFIG.MaxItems > 0 and n >= CONFIG.MaxItems then break end
        end
    end
    log(("Выброшено предметов: %d [%s]"):format(n, FILTER_RU[CONFIG.Filter])); return n
end

local function createSpoofedMatch()             -- F-004
    local CreateLobby = remote("ReplicatedStorage.LobbyEvents.CreateLobby")
    local enter = remote("Workspace.Queues.1.Refs.Enter")
    if not CreateLobby then log("F-004: ты не в лобби"); return false end
    if enter then
        pcall(function() firetouchinterest(root(), enter, 0); firetouchinterest(root(), enter, 1) end)
        task.wait(1.5)
    end
    pcall(function() CreateLobby:FireServer("1", CONFIG.SpoofMaxPlayers, CONFIG.SpoofGamemode, "Public") end)
    log(("F-004: матч gamemode='%s' maxPlayers=%d"):format(CONFIG.SpoofGamemode, CONFIG.SpoofMaxPlayers))
    return true
end

local function runMatch()
    log("=== Матч: запуск ===")
    if CONFIG.VacuumLoot        then vacuumLoot() end
    if CONFIG.VacuumConsumables then vacuumConsumables() end
    if CONFIG.AutoSellValuables then autoSellValuables() end
    if CONFIG.SkipDay           then skipDay() end
    log("=== Готово. Cash = " .. getCash() .. " ===")
end

local function run()
    local pid = game.PlaceId
    if pid == MATCH_PLACE then runMatch()
    elseif pid == LOBBY_PLACE then createSpoofedMatch()
    else log("Не Dead Shelter (PlaceId " .. tostring(pid) .. ")") end
end

--==================================================================
-- GUI
--==================================================================
local COL = {
    bg     = Color3.fromRGB(22, 24, 30),
    bg2    = Color3.fromRGB(30, 33, 41),
    head   = Color3.fromRGB(176, 38, 46),
    on     = Color3.fromRGB(64, 170, 92),
    off    = Color3.fromRGB(70, 74, 86),
    btn    = Color3.fromRGB(44, 48, 60),
    btnHov = Color3.fromRGB(58, 63, 78),
    txt    = Color3.fromRGB(235, 237, 242),
    sub    = Color3.fromRGB(150, 155, 168),
}

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p
end
local function pad(p, n)
    local u = Instance.new("UIPadding")
    u.PaddingLeft=UDim.new(0,n); u.PaddingRight=UDim.new(0,n)
    u.PaddingTop=UDim.new(0,n); u.PaddingBottom=UDim.new(0,n); u.Parent=p
end

-- удалить старую копию
pcall(function()
    local old = (gethui and gethui() or game:GetService("CoreGui")):FindFirstChild("DS_PoC_GUI")
    if old then old:Destroy() end
end)

local screen = Instance.new("ScreenGui")
screen.Name = "DS_PoC_GUI"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.IgnoreGuiInset = true
pcall(function() screen.Parent = gethui and gethui() or game:GetService("CoreGui") end)
if not screen.Parent then screen.Parent = LP:WaitForChild("PlayerGui") end

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 320, 0, 500)
main.Position = UDim2.new(0, 40, 0.5, -250)
main.BackgroundColor3 = COL.bg
main.BorderSizePixel = 0
main.Active = true
main.Parent = screen
corner(main, 10)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0,0,0); stroke.Transparency = 0.5; stroke.Thickness = 1; stroke.Parent = main

-- HEADER (draggable)
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = COL.head
header.BorderSizePixel = 0
header.Parent = main
corner(header, 10)
local headFix = Instance.new("Frame")
headFix.Size = UDim2.new(1,0,0,12); headFix.Position = UDim2.new(0,0,1,-12)
headFix.BackgroundColor3 = COL.head; headFix.BorderSizePixel = 0; headFix.Parent = header

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -50, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15
title.TextColor3 = COL.txt; title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "DEAD SHELTER — PoC"
title.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 30, 0, 30); minBtn.Position = UDim2.new(1, -36, 0, 5)
minBtn.BackgroundColor3 = COL.bg2; minBtn.Text = "—"
minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 16; minBtn.TextColor3 = COL.txt
minBtn.Parent = header; corner(minBtn, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.Position = UDim2.new(1, -72, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(120, 30, 36); closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 14; closeBtn.TextColor3 = COL.txt
closeBtn.Parent = header; corner(closeBtn, 6)

-- перетаскивание
do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = main.Position
            i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

-- BODY
local body = Instance.new("ScrollingFrame")
body.Size = UDim2.new(1, 0, 1, -40); body.Position = UDim2.new(0, 0, 0, 40)
body.BackgroundTransparency = 1; body.BorderSizePixel = 0
body.ScrollBarThickness = 4; body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y; body.Parent = main
pad(body, 10)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = body

local order = 0
local function nextOrder() order += 1; return order end

-- статус места
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, 0, 0, 18); statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham; statusLbl.TextSize = 11; statusLbl.TextColor3 = COL.sub
statusLbl.TextXAlignment = Enum.TextXAlignment.Left; statusLbl.LayoutOrder = nextOrder()
statusLbl.Parent = body
local function refreshStatus()
    local pid = game.PlaceId
    local where = (pid == MATCH_PLACE and "МАТЧ") or (pid == LOBBY_PLACE and "ЛОББИ") or "?"
    statusLbl.Text = ("Место: %s   |   Cash: %d"):format(where, getCash())
end
refreshStatus()
task.spawn(function() while screen.Parent do refreshStatus(); task.wait(1) end end)

-- toggle row
local function makeToggle(text, key)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 34); row.BackgroundColor3 = COL.bg2
    row.AutoButtonColor = false; row.Text = ""; row.LayoutOrder = nextOrder(); row.Parent = body
    corner(row, 6)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -60, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.Font = Enum.Font.Gotham; lbl.TextSize = 13; lbl.TextColor3 = COL.txt
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = text; lbl.Parent = row
    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 40, 0, 20); pill.Position = UDim2.new(1, -50, 0.5, -10)
    pill.BorderSizePixel = 0; pill.Parent = row; corner(pill, 10)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16); knob.BorderSizePixel = 0; knob.Parent = pill; corner(knob, 8)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    local function render()
        local v = CONFIG[key]
        pill.BackgroundColor3 = v and COL.on or COL.off
        knob.Position = v and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    end
    render()
    row.MouseButton1Click:Connect(function() CONFIG[key] = not CONFIG[key]; render() end)
end

-- кнопка-переключатель фильтра категорий
local function makeFilterButton()
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 34); row.BackgroundColor3 = COL.bg2
    row.AutoButtonColor = false; row.Text = ""; row.LayoutOrder = nextOrder(); row.Parent = body
    corner(row, 6)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(0.5, -10, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.Font = Enum.Font.Gotham; lbl.TextSize = 13; lbl.TextColor3 = COL.txt
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = "Фильтр"; lbl.Parent = row
    local val = Instance.new("TextLabel")
    val.BackgroundTransparency = 1; val.Size = UDim2.new(0.5, -10, 1, 0); val.Position = UDim2.new(0.5, 0, 0, 0)
    val.Font = Enum.Font.GothamBold; val.TextSize = 13; val.TextColor3 = COL.on
    val.TextXAlignment = Enum.TextXAlignment.Right; val.Parent = row
    local function render() val.Text = FILTER_RU[CONFIG.Filter] .. "  ▸" end
    render()
    row.MouseButton1Click:Connect(function()
        local idx = table.find(FILTERS, CONFIG.Filter) or 1
        CONFIG.Filter = FILTERS[(idx % #FILTERS) + 1]
        render()
    end)
end

-- степпер числовых лимитов:  label   [-] value [+]
local function makeStepper(text, key, step, min, max, fmt)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 30); row.BackgroundColor3 = COL.bg2
    row.BorderSizePixel = 0; row.LayoutOrder = nextOrder(); row.Parent = body
    corner(row, 6)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -110, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.Font = Enum.Font.Gotham; lbl.TextSize = 12; lbl.TextColor3 = COL.txt
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = text; lbl.Parent = row
    local val = Instance.new("TextLabel")
    val.BackgroundTransparency = 1; val.Size = UDim2.new(0, 56, 1, 0); val.Position = UDim2.new(1, -86, 0, 0)
    val.Font = Enum.Font.GothamBold; val.TextSize = 12; val.TextColor3 = COL.txt; val.Parent = row
    local function render() val.Text = (fmt and fmt(CONFIG[key])) or tostring(CONFIG[key]) end
    local function mkBtn(t, x, d)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, 24, 0, 22); b.Position = UDim2.new(1, x, 0.5, -11)
        b.BackgroundColor3 = COL.btn; b.Text = t; b.Font = Enum.Font.GothamBold
        b.TextSize = 14; b.TextColor3 = COL.txt; b.Parent = row; corner(b, 5)
        b.MouseButton1Click:Connect(function()
            local v = CONFIG[key] + d
            if min then v = math.max(min, v) end
            if max then v = math.min(max, v) end
            v = math.floor(v * 1000 + 0.5) / 1000
            CONFIG[key] = v; render()
        end)
    end
    mkBtn("-", -30, -step)
    mkBtn("+", -2, step)
    render()
end

makeToggle("F-005  Vacuum Loot",        "VacuumLoot")
makeToggle("F-006  Vacuum Consumables", "VacuumConsumables")
makeToggle("F-009/010  Auto Sell",      "AutoSellValuables")
makeToggle("F-007  Skip Day",           "SkipDay")
makeToggle("ESP зомби",                 "ESP")
makeToggle("AIM зомби (зажать ПКМ)",    "Aim")

makeFilterButton()
makeStepper("Мин. цена продажи", "MinSellPrice", 5, 0, nil)
makeStepper("Лимит предметов (0=все)", "MaxItems", 5, 0, nil)
makeStepper("Радиус центра", "CenterRadius", 5, 1, nil)
makeStepper("Задержка продажи", "SellDelay", 0.05, 0, 5, function(v) return string.format("%.2fs", v) end)

-- action button
local function makeButton(text, color, fn)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 32); b.BackgroundColor3 = color or COL.btn
    b.AutoButtonColor = false; b.Font = Enum.Font.GothamBold; b.TextSize = 13
    b.TextColor3 = COL.txt; b.Text = text; b.LayoutOrder = nextOrder(); b.Parent = body
    corner(b, 6)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = COL.btnHov end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = color or COL.btn end)
    b.MouseButton1Click:Connect(function() task.spawn(fn) end)
    return b
end

makeButton("▶  RUN (по тогглам)", COL.head, run)
makeButton("F-009/010  Продать всё ценное", nil, autoSellValuables)
makeButton("Собрать все предметы в центр", nil, gatherToCenter)
makeButton("Выбросить все предметы", nil, dropAllItems)
makeButton("Собрать все Deadbuck", COL.on, collectDeadbucks)
makeButton("Кинуть Deadbuck перед собой", nil, throwDeadbucksFront)
makeButton("F-004  Создать матч (gamemode spoof)", nil, createSpoofedMatch)

-- ===== Выборочный подъём предметов =====
local rebuildSelectionList -- forward
makeButton("⟳  Обновить список предметов", nil, function() rebuildSelectionList() end)
makeButton("Поднять выбранное", COL.on, pickupSelected)

local selContainer = Instance.new("Frame")
selContainer.Size = UDim2.new(1, 0, 0, 0); selContainer.AutomaticSize = Enum.AutomaticSize.Y
selContainer.BackgroundTransparency = 1; selContainer.LayoutOrder = nextOrder(); selContainer.Parent = body
local selLayout = Instance.new("UIListLayout")
selLayout.Padding = UDim.new(0, 3); selLayout.SortOrder = Enum.SortOrder.LayoutOrder; selLayout.Parent = selContainer

function rebuildSelectionList()
    for _, c in ipairs(selContainer:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
    local df = Workspace:FindFirstChild("DraggableFolder")
    if not df then log("DraggableFolder не найден"); return end
    local counts = {}
    for _, item in ipairs(df:GetChildren()) do counts[item.Name] = (counts[item.Name] or 0) + 1 end
    local names = {}
    for nm in pairs(counts) do names[#names + 1] = nm end
    table.sort(names)
    for _, nm in ipairs(names) do
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 24); row.AutoButtonColor = false; row.Text = ""
        row.LayoutOrder = 1; row.Parent = selContainer; corner(row, 5)
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, -28, 1, 0); lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.Font = Enum.Font.Gotham; lbl.TextSize = 11; lbl.TextColor3 = COL.txt
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = ("%s  x%d"):format(nm, counts[nm]); lbl.Parent = row
        local mark = Instance.new("TextLabel")
        mark.BackgroundTransparency = 1; mark.Size = UDim2.new(0, 22, 1, 0); mark.Position = UDim2.new(1, -24, 0, 0)
        mark.Font = Enum.Font.GothamBold; mark.TextSize = 13; mark.TextColor3 = COL.on; mark.Parent = row
        local function render()
            local on = CONFIG.Selection[nm]
            mark.Text = on and "✔" or ""
            row.BackgroundColor3 = on and Color3.fromRGB(38, 58, 44) or COL.bg2
        end
        render()
        row.MouseButton1Click:Connect(function()
            CONFIG.Selection[nm] = (not CONFIG.Selection[nm]) or nil
            render()
        end)
    end
    log(("Список предметов: %d типов"):format(#names))
end

-- консоль-лог
local logBox = Instance.new("ScrollingFrame")
logBox.Size = UDim2.new(1, 0, 0, 96); logBox.BackgroundColor3 = COL.bg2
logBox.BorderSizePixel = 0; logBox.ScrollBarThickness = 4
logBox.CanvasSize = UDim2.new(0,0,0,0); logBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
logBox.LayoutOrder = nextOrder(); logBox.Parent = body
corner(logBox, 6); pad(logBox, 6)
local logLayout = Instance.new("UIListLayout"); logLayout.Padding = UDim.new(0, 2); logLayout.Parent = logBox

guiLog = function(msg)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1; l.Size = UDim2.new(1, 0, 0, 14)
    l.Font = Enum.Font.Code; l.TextSize = 11; l.TextColor3 = COL.sub
    l.TextXAlignment = Enum.TextXAlignment.Left; l.TextWrapped = true
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.Text = os.date("%H:%M:%S ") .. msg; l.Parent = logBox
    task.wait()
    logBox.CanvasPosition = Vector2.new(0, logBox.AbsoluteCanvasSize.Y)
end

-- свернуть/развернуть
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    main.Size = minimized and UDim2.new(0, 320, 0, 40) or UDim2.new(0, 320, 0, 500)
    minBtn.Text = minimized and "+" or "—"
end)

-- ===== ESP + AIM (зомби) =====
local camera = Workspace.CurrentCamera
local espFolder = Instance.new("Folder"); espFolder.Name = "DS_ESP"; espFolder.Parent = screen
local highlights = {} -- model -> Highlight

local function updateESP()
    local present = {}
    if CONFIG.ESP then
        for _, z in ipairs(getZombies()) do
            present[z.model] = true
            if not highlights[z.model] then
                local h = Instance.new("Highlight")
                h.FillColor = Color3.fromRGB(255, 60, 60)
                h.OutlineColor = Color3.fromRGB(255, 255, 255)
                h.FillTransparency = 0.6; h.OutlineTransparency = 0
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Adornee = z.model; h.Parent = espFolder
                highlights[z.model] = h
            end
        end
    end
    for model, h in pairs(highlights) do
        if not present[model] or not model.Parent then h:Destroy(); highlights[model] = nil end
    end
end

local function aimStep()
    if not CONFIG.Aim then return end
    if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
    local center = camera.ViewportSize / 2
    local best, bestDist
    for _, z in ipairs(getZombies()) do
        local part = z.model:FindFirstChild(CONFIG.AimPart) or z.hrp
        if part then
            local sp, on = camera:WorldToViewportPoint(part.Position)
            if on then
                local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                if d <= CONFIG.AimFOV and (not bestDist or d < bestDist) then best, bestDist = part, d end
            end
        end
    end
    if best then camera.CFrame = CFrame.lookAt(camera.CFrame.Position, best.Position) end
end

track(RunService.RenderStepped:Connect(aimStep))
task.spawn(function()
    while espFolder.Parent do updateESP(); task.wait(0.4) end
end)

-- выгрузка скрипта (✕)
local function unload()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    pcall(function() espFolder:Destroy() end)
    pcall(function() screen:Destroy() end)
    if typeof(getgenv) == "function" then getgenv().DSPoC = nil end
    print("[DS-PoC] выгружен")
end
closeBtn.MouseButton1Click:Connect(unload)

--==================================================================
-- API + автозапуск
--==================================================================
local API = {
    run = run, vacuumLoot = vacuumLoot, vacuumConsumables = vacuumConsumables,
    autoSellValuables = autoSellValuables, skipDay = skipDay,
    dropAllItems = dropAllItems, gatherToCenter = gatherToCenter,
    pickupSelected = pickupSelected,
    collectDeadbucks = collectDeadbucks, throwDeadbucksFront = throwDeadbucksFront,
    createSpoofedMatch = createSpoofedMatch, config = CONFIG, getCash = getCash,
    gui = screen, unload = unload,
}
if typeof(getgenv) == "function" then getgenv().DSPoC = API end

log("GUI загружен. PlaceId " .. game.PlaceId)
return API
