local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

if getgenv then
    local prev = getgenv().StrengthHubUnload
    if type(prev) == "function" then
        pcall(prev)
    end
end

local BG      = Color3.fromRGB(22, 22, 30)
local CARD    = Color3.fromRGB(31, 31, 42)
local PANEL   = Color3.fromRGB(40, 40, 52)
local ACCENT  = Color3.fromRGB(124, 99, 255)
local TXT     = Color3.fromRGB(236, 237, 245)
local SUB     = Color3.fromRGB(150, 152, 170)
local OFF     = Color3.fromRGB(58, 58, 72)
local TRACK   = Color3.fromRGB(50, 50, 64)
local DANGER  = Color3.fromRGB(232, 76, 92)
local WHITE   = Color3.fromRGB(245, 245, 250)

local connections = {}
local moduleList = {}
local toggles = {}
local ScreenGui

local function track(conn)
    table.insert(connections, conn)
    return conn
end

local function create(class, props, children)
    local obj = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then
                obj[k] = v
            end
        end
    end
    if children then
        for _, c in ipairs(children) do
            c.Parent = obj
        end
    end
    if props and props.Parent then
        obj.Parent = props.Parent
    end
    return obj
end

local function safeRequire(inst)
    if not inst then return nil end
    local ok, mod = pcall(require, inst)
    if ok then return mod end
    return nil
end

local Events = ReplicatedStorage:WaitForChild("Events", 10)
local SwingSaber, SellStrength, CollectCurrencyPickup, UIAction
if Events then
    SwingSaber = Events:WaitForChild("SwingSaber", 10)
    SellStrength = Events:WaitForChild("SellStrength", 10)
    CollectCurrencyPickup = Events:WaitForChild("CollectCurrencyPickup", 10)
    UIAction = Events:WaitForChild("UIAction", 10)
end

local MainClient = LocalPlayer:FindFirstChild("PlayerScripts")
    and LocalPlayer.PlayerScripts:FindFirstChild("MainClient")
local cdm = safeRequire(MainClient and MainClient:FindFirstChild("ClientDataManager"))
local ItemInfo = safeRequire(ReplicatedStorage:FindFirstChild("Modules")
    and ReplicatedStorage.Modules:FindFirstChild("ItemInfo"))
local HitDetection = safeRequire(MainClient and MainClient:FindFirstChild("ClientTool")
    and MainClient.ClientTool:FindFirstChild("HitDetection"))

local classesTotal = (ItemInfo and ItemInfo.Classes_Order) and #ItemInfo.Classes_Order or 0

local CONFIG_PATH = "StrengthHub_config.json"
local configState = {}
do
    local canRead = isfile and readfile and isfile(CONFIG_PATH)
    if canRead then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(CONFIG_PATH))
        end)
        if ok and type(data) == "table" then
            configState = data
        end
    end
end

local configReady = false
local function saveConfig()
    if not (configReady and writefile) then return end
    pcall(function()
        writefile(CONFIG_PATH, HttpService:JSONEncode(configState))
    end)
end

local fireTimes = {}
local function fire(remote, ...)
    if not remote then return end
    fireTimes[#fireTimes + 1] = os.clock()
    remote:FireServer(...)
end

local function fireBoss()
    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then return end
    local remote = tool:FindFirstChild("RemoteClick")
    if not remote then return end

    local targets
    if HitDetection then
        local ok, res = pcall(function()
            return HitDetection:GetBossesAndMobsHit(LocalPlayer)
        end)
        if ok and type(res) == "table" then
            targets = res
        end
    end
    if not targets or #targets == 0 then
        targets = {}
        local tag = LocalPlayer:GetAttribute("InEventBoss") == true and "EventBoss" or "Boss"
        for _, b in ipairs(CollectionService:GetTagged(tag)) do
            if (b:GetAttribute("Health") or 0) > 0 then
                targets[#targets + 1] = b
            end
        end
    end
    if #targets > 0 then
        fire(remote, targets)
    end
end

local function fireFarm()
    fire(SwingSaber)
end

local function fireSell()
    fire(SellStrength)
end

local MAX_BATCH = 60
local collectSent = setmetatable({}, { __mode = "k" })
local function fireCollect()
    if not CollectCurrencyPickup then return end
    local batch = {}
    for _, pickup in ipairs(CollectionService:GetTagged("CurrencyPickup")) do
        if pickup.Parent and pickup.Name ~= "Crown" and not collectSent[pickup] then
            collectSent[pickup] = true
            batch[#batch + 1] = pickup
            if #batch >= MAX_BATCH then break end
        end
    end
    if #batch > 0 then
        fire(CollectCurrencyPickup, batch)
    end
end

local function fireBuyClass()
    if not (UIAction and cdm and ItemInfo and ItemInfo.Classes_Order) then return end
    local nextIndex = (cdm.Data.Best_Class_Index or 0) + 1
    local nextKey = ItemInfo.Classes_Order[nextIndex]
    if nextKey then
        fire(UIAction, "BuyClass", nextKey)
    end
end

local function fireBuyDNA()
    fire(UIAction, "BuyAllDNAs")
end

local function fireBuyWeapon()
    fire(UIAction, "BuyAllWeapons")
end

local function fireCombine()
    fire(UIAction, "CombineAllPets")
end

local function fireBuyEgg()
    fire(UIAction, "BuyEgg", "GM Egg")
end

local GLOBAL_LIMIT = 400
local tokens = GLOBAL_LIMIT
track(RunService.Heartbeat:Connect(function(dt)
    tokens = math.min(GLOBAL_LIMIT, tokens + dt * GLOBAL_LIMIT)
end))
local function takeToken()
    if tokens >= 1 then
        tokens = tokens - 1
        return true
    end
    return false
end

local function makeModule(fireFn, defaultRate)
    local m = { enabled = false, rate = defaultRate, acc = 0 }
    m.conn = track(RunService.Heartbeat:Connect(function(dt)
        if not m.enabled then return end
        m.acc = math.min(m.acc + dt * m.rate, m.rate + 1)
        local count = math.floor(m.acc)
        if count > 0 then
            m.acc = m.acc - count
            if count > 250 then count = 250 end
            for _ = 1, count do
                if not takeToken() then break end
                pcall(fireFn)
            end
        end
    end))
    table.insert(moduleList, m)
    return m
end

ScreenGui = create("ScreenGui", {
    Name = "StrengthHub",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
})

do
    local ok = pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(ScreenGui)
            ScreenGui.Parent = CoreGui
        elseif gethui then
            ScreenGui.Parent = gethui()
        else
            ScreenGui.Parent = CoreGui
        end
    end)
    if not ok or not ScreenGui.Parent then
        pcall(function() ScreenGui.Parent = CoreGui end)
    end
    if not ScreenGui.Parent then
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local FULL = UDim2.fromOffset(344, 500)
local MINI = UDim2.fromOffset(344, 40)

local Main = create("Frame", {
    Parent = ScreenGui,
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = FULL,
    BackgroundColor3 = BG,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, {
    create("UICorner", { CornerRadius = UDim.new(0, 12) }),
    create("UIStroke", { Color = Color3.fromRGB(48, 48, 62), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
})

local TitleBar = create("Frame", {
    Parent = Main,
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Color3.fromRGB(27, 27, 37),
    BorderSizePixel = 0,
}, {
    create("UICorner", { CornerRadius = UDim.new(0, 12) }),
})
create("Frame", {
    Parent = TitleBar,
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Color3.fromRGB(27, 27, 37),
    BorderSizePixel = 0,
})

create("Frame", {
    Parent = TitleBar,
    Size = UDim2.fromOffset(10, 10),
    Position = UDim2.fromOffset(14, 15),
    BackgroundColor3 = ACCENT,
    BorderSizePixel = 0,
}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

create("TextLabel", {
    Parent = TitleBar,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(32, 0),
    Size = UDim2.fromOffset(118, 40),
    Font = Enum.Font.GothamBold,
    Text = "Strength Hub",
    TextSize = 15,
    TextColor3 = TXT,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local rateLabel = create("TextLabel", {
    Parent = TitleBar,
    BackgroundColor3 = PANEL,
    Position = UDim2.fromOffset(158, 8),
    Size = UDim2.fromOffset(112, 24),
    Font = Enum.Font.GothamBold,
    Text = "0 / 400 rps",
    TextSize = 12,
    TextColor3 = SUB,
    TextXAlignment = Enum.TextXAlignment.Center,
}, { create("UICorner", { CornerRadius = UDim.new(0, 8) }) })

local function iconButton(symbol, xOff, color)
    return create("TextButton", {
        Parent = TitleBar,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(26, 26),
        Position = UDim2.fromOffset(xOff, 7),
        BackgroundColor3 = PANEL,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = symbol,
        TextSize = 16,
        TextColor3 = color or TXT,
    }, { create("UICorner", { CornerRadius = UDim.new(0, 8) }) })
end

local minBtn = iconButton("–", 278, SUB)
local closeBtn = iconButton("×", 310, DANGER)

local InfoBar = create("Frame", {
    Parent = Main,
    Name = "InfoBar",
    Position = UDim2.fromOffset(0, 40),
    Size = UDim2.new(1, 0, 0, 26),
    BackgroundColor3 = Color3.fromRGB(24, 24, 33),
    BorderSizePixel = 0,
})
local classLabel = create("TextLabel", {
    Parent = InfoBar,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(14, 0),
    Size = UDim2.new(1, -28, 1, 0),
    Font = Enum.Font.GothamMedium,
    Text = "Классы пройдено: …",
    TextSize = 12,
    TextColor3 = SUB,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local ScrollList = create("ScrollingFrame", {
    Parent = Main,
    Name = "List",
    Position = UDim2.fromOffset(0, 66),
    Size = UDim2.new(1, 0, 1, -112),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = ACCENT,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ElasticBehavior = Enum.ElasticBehavior.Never,
}, {
    create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 6) }),
    create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local footer = create("Frame", {
    Parent = Main,
    Name = "Footer",
    Position = UDim2.new(0, 0, 1, -46),
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = Color3.fromRGB(27, 27, 37),
    BorderSizePixel = 0,
}, {
    create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 6) }),
})

local function hoverable(btn, base, hover)
    track(btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play()
    end))
    track(btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
    end))
end

local function buildCard(order, id, name, desc, defaultRate, fireFn, unit, maxRate)
    local m = makeModule(fireFn, defaultRate)
    local saved = (type(configState[id]) == "table") and configState[id] or {}
    local function commit()
        configState[id] = { enabled = m.enabled, rate = m.rate }
        saveConfig()
    end

    local card = create("Frame", {
        Parent = ScrollList,
        LayoutOrder = order,
        Size = UDim2.new(1, 0, 0, 96),
        BackgroundColor3 = CARD,
        BorderSizePixel = 0,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 10) }),
        create("UIStroke", { Color = Color3.fromRGB(44, 44, 58), Thickness = 1 }),
    })

    create("TextLabel", {
        Parent = card,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 10),
        Size = UDim2.fromOffset(232, 20),
        Font = Enum.Font.GothamBold,
        Text = name,
        TextSize = 14,
        TextColor3 = TXT,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    create("TextLabel", {
        Parent = card,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 31),
        Size = UDim2.fromOffset(232, 16),
        Font = Enum.Font.Gotham,
        Text = desc,
        TextSize = 11,
        TextColor3 = SUB,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local toggleBtn = create("TextButton", {
        Parent = card,
        AutoButtonColor = false,
        Text = "",
        Position = UDim2.fromOffset(260, 13),
        Size = UDim2.fromOffset(46, 24),
        BackgroundColor3 = OFF,
        BorderSizePixel = 0,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local knob = create("Frame", {
        Parent = toggleBtn,
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    local function renderToggle()
        TweenService:Create(toggleBtn, TweenInfo.new(0.16), { BackgroundColor3 = m.enabled and ACCENT or OFF }):Play()
        TweenService:Create(knob, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Position = m.enabled and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3) }):Play()
    end
    local function setEnabled(v)
        m.enabled = v and true or false
        if not m.enabled then m.acc = 0 end
        renderToggle()
        commit()
    end
    track(toggleBtn.MouseButton1Click:Connect(function()
        setEnabled(not m.enabled)
    end))
    table.insert(toggles, setEnabled)

    create("TextLabel", {
        Parent = card,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 52),
        Size = UDim2.fromOffset(220, 14),
        Font = Enum.Font.Gotham,
        Text = "Скорость, " .. (unit or "вызовов/сек"),
        TextSize = 11,
        TextColor3 = SUB,
        TextXAlignment = Enum.TextXAlignment.Left,
    })

    local trackBar = create("Frame", {
        Parent = card,
        Position = UDim2.fromOffset(14, 74),
        Size = UDim2.fromOffset(220, 6),
        BackgroundColor3 = TRACK,
        BorderSizePixel = 0,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local fill = create("Frame", {
        Parent = trackBar,
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = ACCENT,
        BorderSizePixel = 0,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
    local sknob = create("Frame", {
        Parent = trackBar,
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.new(0, -7, 0.5, -7),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

    local box = create("TextBox", {
        Parent = card,
        Position = UDim2.fromOffset(246, 64),
        Size = UDim2.fromOffset(60, 26),
        BackgroundColor3 = PANEL,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = TXT,
        Text = tostring(defaultRate),
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, {
        create("UICorner", { CornerRadius = UDim.new(0, 8) }),
        create("UIStroke", { Color = Color3.fromRGB(60, 60, 76), Thickness = 1 }),
    })

    local MINV, MAXV = 1, maxRate or 1000

    local function applyRate(v, fromBox)
        v = math.clamp(math.floor(v + 0.5), MINV, MAXV)
        m.rate = v
        local alpha = (v - MINV) / (MAXV - MINV)
        fill.Size = UDim2.fromScale(alpha, 1)
        sknob.Position = UDim2.new(alpha, -7, 0.5, -7)
        if not fromBox then
            box.Text = tostring(v)
        end
    end

    applyRate(tonumber(saved.rate) or defaultRate, false)

    local dragging = false
    local function updateFromInput(input)
        local rel = (input.Position.X - trackBar.AbsolutePosition.X) / trackBar.AbsoluteSize.X
        rel = math.clamp(rel, 0, 1)
        applyRate(MINV + rel * (MAXV - MINV), false)
    end
    track(trackBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input)
        end
    end))
    track(sknob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                commit()
            end
        end
    end))
    track(box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then
            applyRate(n, true)
        end
        box.Text = tostring(m.rate)
        commit()
    end))

    if saved.enabled then
        setEnabled(true)
    end

    return m
end

buildCard(1, "boss", "Дамаг ивент-босса", "RemoteClick → Boss", 20, fireBoss)
buildCard(2, "farm", "Фарм силы", "SwingSaber", 30, fireFarm)
buildCard(3, "sell", "Продажа силы", "SellStrength", 5, fireSell)
buildCard(4, "collect", "Авто-сбор ракушек", "CollectCurrencyPickup", 5, fireCollect, "проверок/сек")
buildCard(5, "class", "Авто-покупка класса", "BuyClass → следующий · СБРОС прогресса!", 10, fireBuyClass, "проверок/сек", 20)
buildCard(6, "dna", "Авто-покупка DNA", "BuyAllDNAs", 10, fireBuyDNA, "проверок/сек", 20)
buildCard(7, "saber", "Авто-покупка сейбера", "BuyAllWeapons", 10, fireBuyWeapon, "проверок/сек", 20)
buildCard(8, "combine", "Авто-крафт питомцев", "CombineAllPets", 10, fireCombine, "проверок/сек", 20)
buildCard(9, "egg", "Авто-открытие яиц (GM Egg, 250 ракушек)", "BuyEgg → GM Egg", 5, fireBuyEgg, "яиц/сек", 20)

configReady = true

local stopBtn = create("TextButton", {
    Parent = footer,
    AutoButtonColor = false,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(150, 34),
    BackgroundColor3 = PANEL,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "Стоп всё",
    TextSize = 13,
    TextColor3 = TXT,
}, { create("UICorner", { CornerRadius = UDim.new(0, 8) }) })
local unloadBtn = create("TextButton", {
    Parent = footer,
    AutoButtonColor = false,
    Position = UDim2.fromOffset(160, 0),
    Size = UDim2.fromOffset(150, 34),
    BackgroundColor3 = DANGER,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "Выгрузить",
    TextSize = 13,
    TextColor3 = Color3.fromRGB(255, 255, 255),
}, { create("UICorner", { CornerRadius = UDim.new(0, 8) }) })

hoverable(stopBtn, PANEL, Color3.fromRGB(52, 52, 66))
hoverable(unloadBtn, DANGER, Color3.fromRGB(245, 92, 108))
hoverable(closeBtn, PANEL, Color3.fromRGB(74, 42, 50))
hoverable(minBtn, PANEL, Color3.fromRGB(52, 52, 66))

track(stopBtn.MouseButton1Click:Connect(function()
    for _, setter in ipairs(toggles) do
        setter(false)
    end
end))

do
    local dragging, dragStart, startPos
    track(TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
        end
    end))
    track(TitleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

local minimized = false
track(minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    InfoBar.Visible = not minimized
    ScrollList.Visible = not minimized
    footer.Visible = not minimized
    TweenService:Create(Main, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Size = minimized and MINI or FULL }):Play()
    minBtn.Text = minimized and "+" or "–"
end))

track(RunService.Heartbeat:Connect(function()
    local cutoff = os.clock() - 1
    local first = 1
    local total = #fireTimes
    while first <= total and fireTimes[first] < cutoff do
        first = first + 1
    end
    if first > 1 then
        local kept = {}
        for i = first, total do
            kept[#kept + 1] = fireTimes[i]
        end
        fireTimes = kept
    end
    local rate = #fireTimes
    rateLabel.Text = rate .. " / 400 rps"
    if cdm and cdm.Data then
        classLabel.Text = string.format("Классы пройдено: %d / %d", cdm.Data.Best_Class_Index or 0, classesTotal)
    end
    if rate >= 380 then
        rateLabel.TextColor3 = DANGER
    elseif rate >= 200 then
        rateLabel.TextColor3 = Color3.fromRGB(255, 184, 84)
    elseif rate > 0 then
        rateLabel.TextColor3 = Color3.fromRGB(120, 220, 150)
    else
        rateLabel.TextColor3 = SUB
    end
end))

track(LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end))

local function unload()
    for _, m in ipairs(moduleList) do
        m.enabled = false
    end
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connections)
    if ScreenGui then
        pcall(function() ScreenGui:Destroy() end)
    end
    if getgenv then
        getgenv().StrengthHubUnload = nil
    end
end

track(closeBtn.MouseButton1Click:Connect(unload))
track(unloadBtn.MouseButton1Click:Connect(unload))

if getgenv then
    getgenv().StrengthHubUnload = unload
end

Main.Size = UDim2.fromOffset(344, 0)
TweenService:Create(Main, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Size = FULL }):Play()
