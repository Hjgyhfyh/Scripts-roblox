if _G.__MUSCLE_LEGENDS_UNLOAD then
    pcall(_G.__MUSCLE_LEGENDS_UNLOAD)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local rEvents = ReplicatedStorage:WaitForChild("rEvents")
local globalFunctions = require(ReplicatedStorage:WaitForChild("globalFunctions"))

local R = {
    openCrystal = rEvents:WaitForChild("openCrystalRemote"),
    equipPet = rEvents:WaitForChild("equipPetEvent"),
    sellPet = rEvents:WaitForChild("sellPetEvent"),
    evolvePet = rEvents:WaitForChild("petEvolveEvent"),
    rebirth = rEvents:WaitForChild("rebirthRemote"),
    trading = rEvents:WaitForChild("tradingEvent"),
    freeGift = rEvents:WaitForChild("freeGiftClaimRemote"),
    chest = rEvents:WaitForChild("checkChestRemote"),
    wheel = rEvents:WaitForChild("openFortuneWheelRemote"),
    group = rEvents:WaitForChild("groupRemote"),
    changeSpeedSize = rEvents:WaitForChild("changeSpeedSizeRemote"),
    quests = rEvents:WaitForChild("questsEvent"),
}

local CONFIG = {
    autoLift = true,
    autoRebirth = true,
    autoGifts = true,
    autoChest = true,
    autoWheel = true,
    autoGroup = true,
    autoPets = true,
    autoEvolve = true,
    autoEquip = true,
    autoSellWeak = true,
    autoMaxSize = false,
    antiAFK = true,

    statStacker = false,
    statStackerPet = "",

    petOpensPerSec = 8,
    rebirthCheckEvery = 5,
    giftCheckEvery = 25,
    chestCheckEvery = 30,
    wheelCheckEvery = 45,
    groupCheckEvery = 120,
    keepCapacityFree = 1,

    rarityOrder = { Basic = 1, Rare = 2, Advanced = 3, Epic = 4, Unique = 5 },
    gemCrystals = {
        { name = "Galaxy Oracle Crystal", price = 1500000 },
        { name = "Muscle Elite Crystal", price = 1000000 },
        { name = "Jungle Crystal", price = 3000000 },
        { name = "Legends Crystal", price = 30000 },
        { name = "Inferno Crystal", price = 15000 },
        { name = "Mythical Crystal", price = 8000 },
        { name = "Frost Crystal", price = 5000 },
        { name = "Green Crystal", price = 3000 },
        { name = "Blue Crystal", price = 1000 },
    },
}

local threads = {}
local connections = {}
local running = true

local function spawnLoop(fn)
    local t = task.spawn(function()
        while running do
            local ok, err = pcall(fn)
            if not ok then
                task.wait(1)
            end
        end
    end)
    table.insert(threads, t)
    return t
end

local function safeInvoke(remote, ...)
    local args = { ... }
    local ok, a, b, c, d = pcall(function()
        return remote:InvokeServer(unpack(args))
    end)
    if ok then
        return a, b, c, d
    end
    return nil
end

local function safeFire(remote, ...)
    pcall(function(...)
        remote:FireServer(...)
    end, ...)
end

local function getStat(name)
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local o = ls and ls:FindFirstChild(name)
    return o and o.Value or 0
end

local function getGems()
    local o = LocalPlayer:FindFirstChild("Gems")
    return o and o.Value or 0
end

local function getTokens()
    local o = LocalPlayer:FindFirstChild("Tokens")
    return o and o.Value or 0
end

local logLines = {}
local logCallback
local function log(msg)
    table.insert(logLines, 1, ("[%s] %s"):format(os.date("%H:%M:%S"), msg))
    while #logLines > 8 do
        table.remove(logLines)
    end
    if logCallback then
        logCallback(table.concat(logLines, "\n"))
    end
end

local Weight, repTimeValue
local muscleEvent = LocalPlayer:FindFirstChild("muscleEvent")
local lastRep = 0
local function findWeight()
    local w = LocalPlayer.Backpack:FindFirstChild("Weight")
    if not w and LocalPlayer.Character then
        w = LocalPlayer.Character:FindFirstChild("Weight")
    end
    Weight = w
    if w then
        repTimeValue = w:FindFirstChild("repTime")
    end
    return w
end

local function ensureLifting()
    if not CONFIG.autoLift then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and hum and hum.Health > 0) then return end
    local w = findWeight()
    if not w then return end
    if w.Parent ~= char then
        pcall(function() hum:EquipTool(w) end)
    end
    local al = LocalPlayer:FindFirstChild("autoLiftEnabled")
    if al and al.Value ~= true then
        al.Value = true
    end
    if not muscleEvent or muscleEvent.Parent ~= LocalPlayer then
        muscleEvent = LocalPlayer:FindFirstChild("muscleEvent")
    end
    local cd = repTimeValue and repTimeValue.Value or 1
    if muscleEvent and tick() - lastRep >= cd then
        lastRep = tick()
        safeFire(muscleEvent, "rep")
    end
end

local function requiredRebirthStrength()
    local ok, v = pcall(function()
        return globalFunctions.calculateRequiredRebirthStrength(getStat("Rebirths"), LocalPlayer)
    end)
    if ok and v then return v end
    return math.huge
end

local function petValue(pet)
    local rarity = pet.Parent and pet.Parent.Name or "Basic"
    local level = pet:FindFirstChild("level") and pet.level.Value or 1
    local evolved = pet:FindFirstChild("evolved") ~= nil
    local ok, v = pcall(function()
        return globalFunctions.calculatePetValue(rarity, level, evolved)
    end)
    if ok and type(v) == "number" then return v end
    return (CONFIG.rarityOrder[rarity] or 0) * 1000 + level
end

local function petsFolder()
    return LocalPlayer:FindFirstChild("petsFolder")
end

local function capacityUsed()
    local pf = petsFolder()
    if not pf then return 0 end
    local ok, v = pcall(function()
        return globalFunctions.calculatePetCapacity(pf)
    end)
    if ok and v then return v end
    local n = 0
    for _, rar in ipairs(pf:GetChildren()) do
        n = n + #rar:GetChildren()
    end
    return n
end

local function maxCapacity()
    local o = LocalPlayer:FindFirstChild("maxPetCapacity")
    return o and o.Value or 20
end

local function isEquipped(pet)
    local eq = LocalPlayer:FindFirstChild("equippedPets")
    if not eq then return false end
    for _, ref in ipairs(eq:GetChildren()) do
        local r = ref:FindFirstChild("petReference")
        if r and r.Value == pet then
            return true
        end
    end
    return false
end

local function allPets()
    local list = {}
    local pf = petsFolder()
    if not pf then return list end
    for _, rar in ipairs(pf:GetChildren()) do
        for _, pet in ipairs(rar:GetChildren()) do
            if pet:FindFirstChild("level") then
                table.insert(list, pet)
            end
        end
    end
    return list
end

local function sellWeakest(amount)
    local pets = allPets()
    table.sort(pets, function(a, b)
        return petValue(a) < petValue(b)
    end)
    local sold = 0
    for _, pet in ipairs(pets) do
        if sold >= amount then break end
        if pet:FindFirstChild("unsellable") == nil and not isEquipped(pet) then
            safeFire(R.sellPet, "sellPet", pet)
            sold = sold + 1
            task.wait(0.05)
        end
    end
    return sold
end

local function bestAffordableCrystal()
    local gems = getGems()
    for _, c in ipairs(CONFIG.gemCrystals) do
        if gems >= c.price then
            return c
        end
    end
    return nil
end

local function doAutoPets()
    if not CONFIG.autoPets then return end
    local used = capacityUsed()
    local cap = maxCapacity()
    if used >= cap - CONFIG.keepCapacityFree then
        if CONFIG.autoSellWeak then
            sellWeakest(math.max(1, used - (cap - CONFIG.keepCapacityFree) + 1))
        else
            return
        end
    end
    local crystal = bestAffordableCrystal()
    if not crystal then return end
    local name, rarity = safeInvoke(R.openCrystal, "openCrystal", crystal.name)
    if name then
        log(("Открыт %s [%s] из %s"):format(tostring(name), tostring(rarity), crystal.name))
    end
end

local function doAutoEvolve()
    if not CONFIG.autoEvolve then return end
    local counts = {}
    for _, pet in ipairs(allPets()) do
        if pet:FindFirstChild("evolved") == nil then
            counts[pet.Name] = (counts[pet.Name] or 0) + 1
        end
    end
    for name, n in pairs(counts) do
        if n >= 5 then
            safeFire(R.evolvePet, "evolvePet", name)
            log(("Эволюция: %s (x%d)"):format(name, n))
            task.wait(0.3)
        end
    end
end

local equipTracked = {}
local function doAutoEquip()
    if not CONFIG.autoEquip then return end
    local pets = allPets()
    table.sort(pets, function(a, b)
        return petValue(a) > petValue(b)
    end)
    local rebirths = getStat("Rebirths")
    for i = 1, math.min(#pets, 12) do
        local pet = pets[i]
        local req = pet:FindFirstChild("requiredRebirths")
        local canUse = (not req) or rebirths >= req.Value
        if canUse and not isEquipped(pet) and not equipTracked[pet] then
            equipTracked[pet] = true
            safeFire(R.equipPet, "equipPet", pet)
            task.wait(0.1)
        end
    end
end

local function doAutoRebirth()
    if not CONFIG.autoRebirth then return end
    if getStat("Strength") >= requiredRebirthStrength() then
        local ok = safeInvoke(R.rebirth, "rebirthRequest")
        if ok == true then
            log(("Ребирт! Теперь: %d"):format(getStat("Rebirths")))
        end
    end
end

local function doAutoGifts()
    if not CONFIG.autoGifts then return end
    for i = 1, 8 do
        local ok, reward = safeInvoke(R.freeGift, "claimGift", i)
        if ok == true then
            log(("Подарок #%d получен"):format(i))
        end
        task.wait(0.1)
    end
end

local function doAutoChest()
    if not CONFIG.autoChest then return end
    local before = getGems()
    safeInvoke(R.chest, "checkChest")
    safeInvoke(R.chest)
    if getGems() > before then
        log("Сундук собран")
    end
end

local function doAutoWheel()
    if not CONFIG.autoWheel then return end
    local fw = ReplicatedStorage:FindFirstChild("fortuneWheelChances")
    local wheel = fw and fw:FindFirstChild("Fortune Wheel")
    if wheel then
        local r = safeInvoke(R.wheel, "openFortuneWheel", wheel)
        if r then
            log("Колесо Фортуны крутится")
        end
    end
end

local function doAutoGroup()
    if not CONFIG.autoGroup then return end
    safeInvoke(R.group, "groupRewards")
end

local function applyMaxSize()
    safeInvoke(R.changeSpeedSize, "changeSize", math.huge)
    safeInvoke(R.changeSpeedSize, "changeSpeed", math.huge)
    log("Запрошен макс. размер/скорость")
end

local function perkSum(pet)
    local pf = pet and pet:FindFirstChild("perksFolder")
    local s = 0
    if pf then
        for _, v in ipairs(pf:GetChildren()) do
            if v:IsA("IntValue") or v:IsA("NumberValue") then
                s = s + v.Value
            end
        end
    end
    return s
end

local function petThreshold(pet)
    local m = ReplicatedStorage:FindFirstChild("petExpMultipliers")
    m = m and m:FindFirstChild(pet.Parent.Name)
    return pet.level.Value * (m and m.Value or 0)
end

local StatStacker = { target = nil, lastPerk = nil, lastLevel = nil, stacks = 0 }
function StatStacker.pick()
    local pets = allPets()
    if CONFIG.statStackerPet ~= "" then
        for _, p in ipairs(pets) do
            if p.Name:lower() == CONFIG.statStackerPet:lower() then return p end
        end
    end
    table.sort(pets, function(a, b) return petValue(a) > petValue(b) end)
    return pets[1]
end
function StatStacker.step()
    if not CONFIG.statStacker then
        StatStacker.target = nil
        return
    end
    local pet = StatStacker.target
    if not pet or not pet.Parent then
        pet = StatStacker.pick()
        StatStacker.target = pet
        StatStacker.lastPerk = pet and perkSum(pet) or nil
        StatStacker.lastLevel = pet and pet.level.Value or nil
        return
    end
    if not isEquipped(pet) then
        safeFire(R.equipPet, "equipPet", pet)
    end
    if not muscleEvent or muscleEvent.Parent ~= LocalPlayer then
        muscleEvent = LocalPlayer:FindFirstChild("muscleEvent")
    end
    local curPerk = perkSum(pet)
    if StatStacker.lastPerk and curPerk > StatStacker.lastPerk and pet.level.Value == (StatStacker.lastLevel or pet.level.Value) then
        local d = curPerk - StatStacker.lastPerk
        StatStacker.stacks = StatStacker.stacks + d
        log(("STAT STACK +%d  %s perk=%d"):format(d, pet.Name, curPerk))
    end
    StatStacker.lastPerk = curPerk
    StatStacker.lastLevel = pet.level.Value
    local gap = petThreshold(pet) - pet.exp.Value
    if muscleEvent and gap > 0 and gap <= 28 then
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local w = findWeight()
        if w and hum and w.Parent ~= char then
            pcall(function() hum:EquipTool(w) end)
        end
        safeFire(muscleEvent, "rep")
    end
end

local TradeDupe = {}
function TradeDupe.run(partnerName, loopOffer)
    local partner = Players:FindFirstChild(partnerName)
    if not partner then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name:lower() == partnerName:lower() or p.DisplayName:lower() == partnerName:lower() then
                partner = p
                break
            end
        end
    end
    if not partner then
        log("Партнёр для трейда не найден: " .. tostring(partnerName))
        return
    end
    safeFire(R.trading, "sendTradeRequest", partner)
    safeFire(R.trading, "requestAccepted", partner)
    log("Запрос трейда отправлен: " .. partner.Name)
    if loopOffer then
        task.spawn(function()
            for _, pet in ipairs(allPets()) do
                if not running then break end
                if not isEquipped(pet) then
                    safeFire(R.trading, "offerItem", pet)
                    task.wait(0.2)
                end
            end
        end)
    end
end

spawnLoop(function()
    ensureLifting()
    task.wait(0.15)
end)

spawnLoop(function()
    doAutoRebirth()
    task.wait(CONFIG.rebirthCheckEvery)
end)

spawnLoop(function()
    if CONFIG.autoPets then
        doAutoPets()
        task.wait(1 / math.max(1, CONFIG.petOpensPerSec))
    else
        task.wait(1)
    end
end)

spawnLoop(function()
    doAutoEvolve()
    doAutoEquip()
    task.wait(8)
end)

spawnLoop(function()
    doAutoGifts()
    task.wait(CONFIG.giftCheckEvery)
end)

spawnLoop(function()
    doAutoChest()
    task.wait(CONFIG.chestCheckEvery)
end)

spawnLoop(function()
    doAutoWheel()
    task.wait(CONFIG.wheelCheckEvery)
end)

spawnLoop(function()
    doAutoGroup()
    task.wait(CONFIG.groupCheckEvery)
end)

spawnLoop(function()
    StatStacker.step()
    task.wait(0.25)
end)

if CONFIG.antiAFK then
    local idleConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
    table.insert(connections, idleConn)
end

-- Interface --------------------------------------------------------------

local PALETTE = {
    bg = Color3.fromRGB(17, 16, 28),
    panel = Color3.fromRGB(25, 23, 42),
    panel2 = Color3.fromRGB(33, 30, 54),
    stroke = Color3.fromRGB(60, 52, 102),
    text = Color3.fromRGB(232, 230, 245),
    sub = Color3.fromRGB(150, 144, 178),
    accent = Color3.fromRGB(140, 95, 255),
    accent2 = Color3.fromRGB(80, 200, 255),
    on = Color3.fromRGB(120, 95, 255),
    off = Color3.fromRGB(54, 49, 80),
    good = Color3.fromRGB(95, 220, 150),
}

local gui = Instance.new("ScreenGui")
gui.Name = "MuscleLegendsHub"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = PlayerGui

local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = parent
    return c
end
local function stroke(parent, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or PALETTE.stroke
    s.Thickness = th or 1
    s.Transparency = 0.2
    s.Parent = parent
    return s
end
local function pad(parent, p)
    local u = Instance.new("UIPadding")
    u.PaddingTop = UDim.new(0, p)
    u.PaddingBottom = UDim.new(0, p)
    u.PaddingLeft = UDim.new(0, p)
    u.PaddingRight = UDim.new(0, p)
    u.Parent = parent
    return u
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 360, 0, 470)
main.Position = UDim2.new(0, 40, 0.5, -235)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.Parent = gui
corner(main, 14)
stroke(main, PALETTE.stroke, 1.5)

local grad = Instance.new("UIGradient")
grad.Rotation = 55
grad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 20, 36)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 13, 24)),
})
grad.Parent = main

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 54)
header.BackgroundColor3 = PALETTE.panel
header.BorderSizePixel = 0
header.Parent = main
corner(header, 14)

local headerBar = Instance.new("Frame")
headerBar.Size = UDim2.new(1, 0, 0, 3)
headerBar.Position = UDim2.new(0, 0, 1, -3)
headerBar.BorderSizePixel = 0
headerBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
headerBar.Parent = header
local barGrad = Instance.new("UIGradient")
barGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, PALETTE.accent),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 120, 255)),
    ColorSequenceKeypoint.new(1, PALETTE.accent2),
})
barGrad.Parent = headerBar

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 18, 0, 0)
title.Size = UDim2.new(1, -120, 1, 0)
title.Font = Enum.Font.GothamBold
title.Text = "MUSCLE LEGENDS"
title.TextSize = 18
title.TextColor3 = PALETTE.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 18, 0, 30)
subtitle.Size = UDim2.new(1, -120, 0, 16)
subtitle.Font = Enum.Font.GothamMedium
subtitle.Text = "Auto Progression"
subtitle.TextSize = 11
subtitle.TextColor3 = PALETTE.sub
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -40, 0, 12)
closeBtn.BackgroundColor3 = PALETTE.panel2
closeBtn.Text = "✕"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.TextColor3 = PALETTE.text
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
corner(closeBtn, 8)

local stats = Instance.new("TextLabel")
stats.BackgroundColor3 = PALETTE.panel
stats.Position = UDim2.new(0, 12, 0, 62)
stats.Size = UDim2.new(1, -24, 0, 34)
stats.Font = Enum.Font.GothamMedium
stats.Text = ""
stats.TextSize = 12
stats.TextColor3 = PALETTE.accent2
stats.BorderSizePixel = 0
stats.Parent = main
corner(stats, 8)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.new(0, 12, 0, 104)
scroll.Size = UDim2.new(1, -24, 1, -230)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = PALETTE.accent
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

local function makeToggle(labelText, key, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundColor3 = PALETTE.panel
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = scroll
    corner(row, 8)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(1, -70, 1, 0)
    lbl.Font = Enum.Font.GothamMedium
    lbl.Text = labelText
    lbl.TextSize = 13
    lbl.TextColor3 = PALETTE.text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local sw = Instance.new("TextButton")
    sw.Size = UDim2.new(0, 44, 0, 22)
    sw.Position = UDim2.new(1, -56, 0.5, -11)
    sw.BackgroundColor3 = CONFIG[key] and PALETTE.on or PALETTE.off
    sw.Text = ""
    sw.BorderSizePixel = 0
    sw.AutoButtonColor = false
    sw.Parent = row
    corner(sw, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = CONFIG[key] and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = sw
    corner(knob, 9)

    sw.MouseButton1Click:Connect(function()
        CONFIG[key] = not CONFIG[key]
        TweenService:Create(sw, TweenInfo.new(0.15), {
            BackgroundColor3 = CONFIG[key] and PALETTE.on or PALETTE.off,
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = CONFIG[key] and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
        }):Play()
        if key == "autoMaxSize" and CONFIG[key] then
            applyMaxSize()
        end
    end)
    return row
end

makeToggle("Авто-лифт (сила)", "autoLift", 1)
makeToggle("Авто-ребирт", "autoRebirth", 2)
makeToggle("Авто-петы (открытие)", "autoPets", 3)
makeToggle("Авто-эволюция петов", "autoEvolve", 4)
makeToggle("Авто-экип лучших", "autoEquip", 5)
makeToggle("Авто-продажа слабых", "autoSellWeak", 6)
makeToggle("Авто-подарки (Gems)", "autoGifts", 7)
makeToggle("Авто-сундук", "autoChest", 8)
makeToggle("Авто-колесо фортуны", "autoWheel", 9)
makeToggle("Авто-группа", "autoGroup", 10)
makeToggle("Макс. размер/скорость", "autoMaxSize", 11)
makeToggle("Дюп статов (Stat Stacker)", "statStacker", 12)
makeToggle("Анти-AFK", "antiAFK", 13)

local logBox = Instance.new("TextLabel")
logBox.Position = UDim2.new(0, 12, 1, -120)
logBox.Size = UDim2.new(1, -24, 0, 76)
logBox.BackgroundColor3 = PALETTE.panel
logBox.Font = Enum.Font.Code
logBox.Text = ""
logBox.TextSize = 10
logBox.TextColor3 = PALETTE.sub
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextWrapped = true
logBox.BorderSizePixel = 0
logBox.Parent = main
corner(logBox, 8)
pad(logBox, 8)
logCallback = function(t) logBox.Text = t end

local unloadBtn = Instance.new("TextButton")
unloadBtn.Position = UDim2.new(0, 12, 1, -38)
unloadBtn.Size = UDim2.new(1, -24, 0, 28)
unloadBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 80)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.Text = "ВЫГРУЗИТЬ"
unloadBtn.TextSize = 13
unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
unloadBtn.BorderSizePixel = 0
unloadBtn.Parent = main
corner(unloadBtn, 8)

do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local statsConn = RunService.RenderStepped:Connect(function()
    stats.Text = ("  STR %s   •   GEMS %s   •   REB %d   •   PETS %d/%d"):format(
        globalFunctions.shortenNumber(getStat("Strength")),
        globalFunctions.shortenNumber(getGems()),
        getStat("Rebirths"),
        capacityUsed(),
        maxCapacity()
    )
end)
table.insert(connections, statsConn)

local function unload()
    running = false
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    for _, t in ipairs(threads) do
        pcall(function() task.cancel(t) end)
    end
    pcall(function() gui:Destroy() end)
    _G.__MUSCLE_LEGENDS_UNLOAD = nil
end
_G.__MUSCLE_LEGENDS_UNLOAD = unload

closeBtn.MouseButton1Click:Connect(unload)
unloadBtn.MouseButton1Click:Connect(unload)

_G.MuscleLegends = {
    config = CONFIG,
    tradeDupe = TradeDupe.run,
    sellWeakest = sellWeakest,
    maxSize = applyMaxSize,
    unload = unload,
}

log("Загружено. Автопрогресс активен.")
