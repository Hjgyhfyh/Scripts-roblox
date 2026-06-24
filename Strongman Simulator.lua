local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local VirtualUser        = game:GetService("VirtualUser")
local LocalPlayer        = Players.LocalPlayer

local connections = {}
local function track(c) connections[#connections + 1] = c; return c end

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

local CURRENCY_TARGET = "Currency_Knivsta"   -- 3 Knivsta = 1 Energy
local RATIO           = 3
local GIVE_KEY        = "Default"

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

local function readEnergy()  return readCurrency(GIVE_KEY) end
local function readKnivsta() return readCurrency("Knivsta") end

----------------------------------------------------------------------
-- Amount parsing: 1k · 1000 · 1.5m · 1sx · 1sp · 2kk · 1 000 000
----------------------------------------------------------------------
local SUFFIX = {
    [""] = 1,
    k = 1e3, m = 1e6, b = 1e9, t = 1e12,
    qd = 1e15, qn = 1e18, sx = 1e21, sp = 1e24, oc = 1e27, no = 1e30,
    dc = 1e33, ud = 1e36, dd = 1e39, td = 1e42, qad = 1e45, qnd = 1e48,
    sxd = 1e51, spd = 1e54, ocd = 1e57, nod = 1e60,
    vg = 1e63, uvg = 1e66, dvg = 1e69, tvg = 1e72, qavg = 1e75,
    qnvg = 1e78, sxvg = 1e81, spvg = 1e84, ocvg = 1e87, novg = 1e90,
    kk = 1e6, kkk = 1e9, q = 1e15, qa = 1e15, qi = 1e18,
    thousand = 1e3, million = 1e6, billion = 1e9, trillion = 1e12,
}

local function parseAmount(input)
    if type(input) ~= "string" then return nil end
    local s = input:lower():gsub("%s+", ""):gsub(",", ""):gsub("_", "")
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

local SCALE = {
    {1e90,"NoVg"},{1e87,"OcVg"},{1e84,"SpVg"},{1e81,"SxVg"},{1e78,"QnVg"},{1e75,"QaVg"},
    {1e72,"TVg"},{1e69,"DVg"},{1e66,"UVg"},{1e63,"Vg"},{1e60,"NoD"},{1e57,"OcD"},
    {1e54,"SpD"},{1e51,"SxD"},{1e48,"QnD"},{1e45,"QaD"},{1e42,"Td"},{1e39,"Dd"},
    {1e36,"Ud"},{1e33,"Dc"},{1e30,"No"},{1e27,"Oc"},{1e24,"Sp"},{1e21,"Sx"},
    {1e18,"Qn"},{1e15,"Qd"},{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"},
}

local function fmt(n)
    for _, e in ipairs(SCALE) do
        if n >= e[1] then return string.format("%.2f%s", n / e[1], e[2]) end
    end
    return tostring(math.floor(n))
end

----------------------------------------------------------------------
-- Energy delivery (mint Knivsta via sign-bypass, then convert)
----------------------------------------------------------------------
local State = { busy = false }

local function ensureKnivsta(cv, needKnivsta)
    if (readKnivsta() or 0) >= needKnivsta then return end
    local energy = readEnergy() or 0
    local mint = (energy + needKnivsta / RATIO + 1e6) * RATIO
    pcall(function() cv:InvokeServer(CURRENCY_TARGET, -mint) end)
    task.wait(0.6)
end

local function giveEnergy(target)
    local cv = getConverter()
    if not cv then return false, 0 end
    local needKnivsta = target * RATIO
    ensureKnivsta(cv, needKnivsta)
    local ok = pcall(function() cv:InvokeServer(CURRENCY_TARGET, needKnivsta) end)
    return ok, ok and target or 0
end

----------------------------------------------------------------------
-- Strength delivery — remote name is randomized per session, so it is
-- resolved live instead of hard-coded: scan for the hashed RemoteFunction
-- and learn it from the game's own calls via a namecall hook.
----------------------------------------------------------------------
local StrengthRemote
local hookActive = true

local function isHashedName(name)
    return type(name) == "string" and #name >= 24 and name:match("^%x+$") ~= nil
end

local function scanStrengthRemote()
    local hits = {}
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteFunction") and isHashedName(d.Name) then
            hits[#hits + 1] = d
        end
    end
    if #hits == 1 then return hits[1] end
    return nil
end

StrengthRemote = scanStrengthRemote()

do
    if hookmetamethod and getnamecallmethod then
        local function wrap(f) return (newcclosure and newcclosure(f)) or f end
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            if hookActive then
                pcall(function(...)
                    if getnamecallmethod() == "InvokeServer"
                        and typeof(self) == "Instance" and self:IsA("RemoteFunction")
                        and self:IsDescendantOf(ReplicatedStorage) then
                        local a = { ... }
                        if type(a[1]) == "number" and a[2] == GIVE_KEY then
                            StrengthRemote = self
                        end
                    end
                end, ...)
            end
            return oldNamecall(self, ...)
        end))
    end
end

local function giveStrength(target)
    local remote = StrengthRemote or scanStrengthRemote()
    if not remote then return false, 0 end
    StrengthRemote = remote
    local ok = pcall(function() remote:InvokeServer(target, GIVE_KEY) end)
    return ok, ok and target or 0
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
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
local STR    = Color3.fromRGB(249, 168, 64)
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
window.Size = UDim2.fromOffset(330, 328)
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
title.Text = "@sigmatik323"
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

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(16, 288)
status.Size = UDim2.new(1, -32, 0, 28)
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
local function runTask(box, btn, label, unit, worker)
    if State.busy then return end
    local target = parseAmount(box.Text)
    if not target then
        setStatus("Не понял число. Примеры: 1k · 1000 · 1sx", WARN)
        return
    end
    State.busy = true
    btn.Text = "Выдаю..."
    setStatus("Выдаю " .. fmt(target) .. " " .. unit .. "...", ACCENT)
    task.spawn(function()
        local ok, given = worker(target)
        if ok then
            setStatus("Готово: +" .. fmt(given) .. " " .. unit .. " ✅", GOOD)
        elseif given and given > 0 then
            setStatus("Частично: +" .. fmt(given) .. " " .. unit, WARN)
        else
            setStatus("Не вышло — remote не найден / отказал", BAD)
        end
        btn.Text = label
        State.busy = false
    end)
end

local function makeRow(yPrompt, ru, en, btnLabel, btnColor, unit, worker)
    local p = Instance.new("TextLabel")
    p.Position = UDim2.fromOffset(16, yPrompt)
    p.Size = UDim2.new(1, -32, 0, 34)
    p.BackgroundTransparency = 1
    p.Font = Enum.Font.GothamSemibold
    p.TextSize = 14
    p.TextColor3 = Color3.fromRGB(225, 232, 245)
    p.TextXAlignment = Enum.TextXAlignment.Left
    p.TextYAlignment = Enum.TextYAlignment.Top
    p.RichText = true
    p.Text = ru .. "\n<font color=\"rgb(150,160,185)\">" .. en .. "</font>"
    p.Parent = window

    local box = Instance.new("TextBox")
    box.Position = UDim2.fromOffset(16, yPrompt + 36)
    box.Size = UDim2.new(1, -32, 0, 38)
    box.BackgroundColor3 = Color3.fromRGB(20, 26, 42)
    box.Font = Enum.Font.GothamMedium
    box.TextSize = 16
    box.TextColor3 = Color3.fromRGB(235, 240, 250)
    box.PlaceholderText = "1k · 1000 · 1sx"
    box.PlaceholderColor3 = MUTED
    box.Text = ""
    box.ClearTextOnFocus = false
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.Parent = window
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)
    local pad = Instance.new("UIPadding", box)
    pad.PaddingLeft = UDim.new(0, 12)
    pad.PaddingRight = UDim.new(0, 12)
    local bs = Instance.new("UIStroke", box)
    bs.Color = Color3.fromRGB(50, 60, 86)
    bs.Transparency = 0.2

    local btn = Instance.new("TextButton")
    btn.Position = UDim2.fromOffset(16, yPrompt + 80)
    btn.Size = UDim2.new(1, -32, 0, 36)
    btn.BackgroundColor3 = btnColor
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.TextColor3 = Color3.fromRGB(8, 16, 12)
    btn.Text = btnLabel
    btn.AutoButtonColor = true
    btn.Parent = window
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

    track(btn.MouseButton1Click:Connect(function() runTask(box, btn, btnLabel, unit, worker) end))
    track(box.FocusLost:Connect(function(enter) if enter then runTask(box, btn, btnLabel, unit, worker) end end))
end

makeRow(46, "Сколько выдать энергии?", "How much energy to give?",
    "Выдать энергию", ACCENT, "энергии", giveEnergy)

makeRow(166, "Сколько выдать силы?", "How much strength to give?",
    "Выдать силу", STR, "силы", giveStrength)

----------------------------------------------------------------------
-- Unload
----------------------------------------------------------------------
local function unload()
    hookActive = false
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
