local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local VirtualUser        = game:GetService("VirtualUser")
local LocalPlayer        = Players.LocalPlayer

----------------------------------------------------------------------
-- Game bindings
----------------------------------------------------------------------
local TGSMisc do
    local ok, m = pcall(function() return require(workspace.Lib.TGSMisc) end)
    TGSMisc = ok and m or nil
end

local Items, ItemCat do
    local ok, m  = pcall(function() return require(workspace.Lib.Items.TGSItems) end)
    Items = ok and m or nil
    local ok2, c = pcall(function() return require(workspace.Lib.Items.ItemCategoryEnum) end)
    ItemCat = ok2 and c or nil
end

local DUP_TARGET     = "Currency_Knivsta"   -- 3 Knivsta = 1 Energy
local RATIO          = 3
local CHUNK_ENERGY   = 1e12                  -- energy delivered per redeem call
local CALLS_PER_SEC  = 200                   -- burst throttle, well under the 400/sec ceiling

local function getConverter()
    if TGSMisc and TGSMisc.RemoteFunction then
        local ok, r = pcall(TGSMisc.RemoteFunction, "CurrencyConverter_ExchangeCurrencyFund")
        if ok and r then return r end
    end
    return ReplicatedStorage:FindFirstChild("CurrencyConverter_ExchangeCurrencyFund")
end

local function readCurrency(key)
    if not Items or not ItemCat then return nil end
    local ok, v = pcall(Items.GetItemInfo, LocalPlayer, ItemCat.Currency, key)
    if ok and type(v) == "number" then return v end
    return nil
end

local function readEnergy()  return readCurrency("Default") end
local function readKnivsta() return readCurrency("Knivsta") end

----------------------------------------------------------------------
-- Amount parsing: 1k · 1000 · 90000SP · 1.5m · 2kk · 1 000 000 · 3b
----------------------------------------------------------------------
local SUFFIX = {
    [""]   = 1,
    k      = 1e3,  kk = 1e6, kkk = 1e9,
    m      = 1e6,  b  = 1e9, t   = 1e12,
    q      = 1e15, qa = 1e15, qi = 1e18,
    thousand = 1e3, million = 1e6, billion = 1e9, trillion = 1e12,
}

local function parseAmount(input)
    if type(input) ~= "string" then return nil end
    local s = input:lower():gsub("%s+", ""):gsub(",", ""):gsub("_", "")
    s = s:gsub("sp$", ""):gsub("energy$", "")
    if s == "" then return nil end
    local num, suf = s:match("^(%d*%.?%d+)([a-z]*)$")
    if not num then return nil end
    local mult = SUFFIX[suf]
    if not mult then return nil end
    local n = tonumber(num)
    if not n then return nil end
    local total = n * mult
    if total <= 0 then return nil end
    return math.floor(total + 0.5)
end

local function fmt(n)
    if n >= 1e18 then return string.format("%.2fQi", n / 1e18) end
    if n >= 1e15 then return string.format("%.2fQ",  n / 1e15) end
    if n >= 1e12 then return string.format("%.2fT",  n / 1e12) end
    if n >= 1e9  then return string.format("%.2fB",  n / 1e9)  end
    if n >= 1e6  then return string.format("%.2fM",  n / 1e6)  end
    if n >= 1e3  then return string.format("%.2fK",  n / 1e3)  end
    return tostring(math.floor(n))
end

----------------------------------------------------------------------
-- Delivery
----------------------------------------------------------------------
local State = { busy = false }

local function ensureKnivsta(cv, needKnivsta)
    if (readKnivsta() or 0) >= needKnivsta then return end
    local energy = readEnergy() or 0
    local mint = (energy + needKnivsta / RATIO + 1e6) * RATIO
    pcall(function() cv:InvokeServer(DUP_TARGET, -mint) end)
    task.wait(0.6)
end

local function giveEnergy(target, onStep)
    local cv = getConverter()
    if not cv then return false, 0, "remote not found" end
    ensureKnivsta(cv, target * RATIO)
    local interval = 1 / CALLS_PER_SEC
    local given = 0
    while given < target do
        local chunkE = math.min(CHUNK_ENERGY, target - given)
        local chunkK = chunkE * RATIO
        ensureKnivsta(cv, chunkK)
        local ok = pcall(function() cv:InvokeServer(DUP_TARGET, chunkK) end)
        if not ok then break end
        given = given + chunkE
        if onStep then onStep(given, target) end
        if given < target then task.wait(interval) end
    end
    return given >= target, given
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local connections = {}
local function track(c) connections[#connections + 1] = c; return c end

local function resolveParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local ACCENT = Color3.fromRGB(34, 197, 94)
local GOOD   = Color3.fromRGB(120, 255, 160)
local WARN   = Color3.fromRGB(255, 190, 90)
local BAD    = Color3.fromRGB(255, 110, 110)
local MUTED  = Color3.fromRGB(150, 160, 185)

local gui = Instance.new("ScreenGui")
gui.Name = "StrongmanGiveGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 2147483000
gui.Parent = resolveParent()
if protect_gui then pcall(protect_gui, gui) end
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end

local window = Instance.new("Frame")
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(330, 196)
window.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
window.BorderSizePixel = 0
window.Parent = gui
Instance.new("UICorner", window).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke", window)
stroke.Thickness = 1.5
stroke.Color = ACCENT
stroke.Transparency = 0.25

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundTransparency = 1
titleBar.Parent = window

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(16, 0)
title.Size = UDim2.new(1, -56, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(235, 240, 250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Strongman · Выдача энергии"
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(26, 26)
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 22, 28)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.TextColor3 = BAD
closeBtn.Text = "✕"
closeBtn.AutoButtonColor = true
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

local box = Instance.new("TextBox")
box.Position = UDim2.fromOffset(16, 50)
box.Size = UDim2.new(1, -32, 0, 42)
box.BackgroundColor3 = Color3.fromRGB(20, 26, 42)
box.Font = Enum.Font.GothamMedium
box.TextSize = 16
box.TextColor3 = Color3.fromRGB(235, 240, 250)
box.PlaceholderText = "Сколько выдать?  напр. 1k · 1000 · 90000SP"
box.PlaceholderColor3 = MUTED
box.Text = ""
box.ClearTextOnFocus = false
box.TextXAlignment = Enum.TextXAlignment.Left
box.Parent = window
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)
do
    local p = Instance.new("UIPadding", box)
    p.PaddingLeft = UDim.new(0, 12)
    p.PaddingRight = UDim.new(0, 12)
    local s = Instance.new("UIStroke", box)
    s.Color = Color3.fromRGB(50, 60, 86)
    s.Transparency = 0.2
end

local giveBtn = Instance.new("TextButton")
giveBtn.Position = UDim2.fromOffset(16, 102)
giveBtn.Size = UDim2.new(1, -32, 0, 42)
giveBtn.BackgroundColor3 = ACCENT
giveBtn.Font = Enum.Font.GothamBold
giveBtn.TextSize = 16
giveBtn.TextColor3 = Color3.fromRGB(8, 16, 12)
giveBtn.Text = "Выдать"
giveBtn.AutoButtonColor = true
giveBtn.Parent = window
Instance.new("UICorner", giveBtn).CornerRadius = UDim.new(0, 10)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(16, 154)
status.Size = UDim2.new(1, -32, 0, 30)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.TextSize = 14
status.TextColor3 = MUTED
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true
status.Text = "Готов к выдаче"
status.Parent = window

local function setStatus(text, color)
    status.Text = text
    status.TextColor3 = color or MUTED
end

----------------------------------------------------------------------
-- Behaviour
----------------------------------------------------------------------
local function doGive()
    if State.busy then return end
    local target = parseAmount(box.Text)
    if not target then
        setStatus("Не понял число. Примеры: 1k, 1000, 90000SP", WARN)
        return
    end
    State.busy = true
    giveBtn.Text = "Выдаю..."
    setStatus("Выдаю " .. fmt(target) .. " ⚡", ACCENT)
    task.spawn(function()
        local ok, given = giveEnergy(target, function(g, t)
            setStatus(string.format("Выдаю... %s / %s", fmt(g), fmt(t)), ACCENT)
        end)
        if ok then
            setStatus("Готово: +" .. fmt(given) .. " энергии ⚡", GOOD)
        elseif given and given > 0 then
            setStatus("Частично: +" .. fmt(given) .. " (ремоут отказал)", WARN)
        else
            setStatus("Не вышло — ремоут не найден / отказал", BAD)
        end
        giveBtn.Text = "Выдать"
        State.busy = false
    end)
end

track(giveBtn.MouseButton1Click:Connect(doGive))
track(box.FocusLost:Connect(function(enter) if enter then doGive() end end))

local function unload()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    if gui then gui:Destroy() end
end
track(closeBtn.MouseButton1Click:Connect(unload))

----------------------------------------------------------------------
-- Drag
----------------------------------------------------------------------
do
    local dragging, dragStart, startPos
    track(titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = window.Position
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

----------------------------------------------------------------------
-- Anti-AFK
----------------------------------------------------------------------
track(LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end))
