-- 8 Ball Pool — Cue Library
-- Beautiful black-themed library that lets you equip ANY cue.
-- Uses the F-009 write-before-validate vector: server accepts ChangeCueEquipped
-- without verifying ownership.
--
-- Open: RightShift, or click the floating 🎱 button bottom-right.
-- Hidden by default.

local Players              = game:GetService("Players")
local UserInputService     = game:GetService("UserInputService")
local TweenService         = game:GetService("TweenService")
local RunService           = game:GetService("RunService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local LocalPlayer          = Players.LocalPlayer
local PlayerGui            = LocalPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------- Configuration
local TOGGLE_KEY      = Enum.KeyCode.RightShift
local OPEN_BY_DEFAULT = false

------------------------------------------------------------------- Data
local cuesIndex = require(ReplicatedStorage.Index.Cues)
local pdu       = ReplicatedStorage.Events.PlayerDataUpdate

local rarityRank = { Epic = 1, Rare = 2, Uncommon = 3, Common = 4 }
local rarityList = { "Epic", "Rare", "Uncommon", "Common" }
local rarityColor = {
    Common   = Color3.fromRGB(180, 180, 190),
    Uncommon = Color3.fromRGB(110, 220, 140),
    Rare     = Color3.fromRGB(80, 165, 255),
    Epic     = Color3.fromRGB(220, 110, 255),
}

------------------------------------------------------------------- Remote helpers
local function readData(timeoutSec)
    timeoutSec = timeoutSec or 1.5
    local result, done = nil, false
    task.spawn(function()
        local ok, data = pcall(function() return pdu:InvokeServer("ReadData") end)
        if ok and type(data) == "table" then result = data end
        done = true
    end)
    local elapsed = 0
    while not done and elapsed < timeoutSec do
        task.wait(0.05); elapsed = elapsed + 0.05
    end
    return result
end

local function getEquipped()
    local data = readData(0.8)
    if data and data.CueEquipped then return data.CueEquipped[1], data.CueEquipped[2] end
    return nil, nil
end

local function fireEquip(rarity, name)
    -- Fire-and-forget so a dead channel doesn't hang the GUI.
    task.spawn(function()
        pcall(function() pdu:InvokeServer("ChangeCueEquipped", { rarity, name }) end)
    end)
end

------------------------------------------------------------------- GUI parent
local function pickParent()
    if typeof(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return PlayerGui
end

local guiParent = pickParent()
local prev = guiParent:FindFirstChild("CueLibrary")
if prev then prev:Destroy() end

------------------------------------------------------------------- Template helpers
local function findTemplateRoot()
    local ifc = PlayerGui:FindFirstChild("Interface")
    if not ifc then return nil end
    local cs = ifc:FindFirstChild("Container")
    cs = cs and cs:FindFirstChild("Inventory")
    cs = cs and cs:FindFirstChild("Pages")
    cs = cs and cs:FindFirstChild("Cues")
    cs = cs and cs:FindFirstChild("CueSelection")
    return cs
end

local templateRoot = findTemplateRoot()

local function cloneTemplate(rarity, name, data)
    if not templateRoot then return nil end
    local t = templateRoot:FindFirstChild("CueTemplate_" .. rarity)
    if not t then return nil end
    local clone = t:Clone()
    clone.Name = "Card_" .. rarity .. "_" .. name
    clone.Visible = true
    clone.LayoutOrder = 0
    -- Strip aspect constraint — UIGridLayout sizes us
    local arc = clone:FindFirstChildOfClass("UIAspectRatioConstraint")
    if arc then arc:Destroy() end
    -- Update mesh texture
    local mesh = clone:FindFirstChild("Mesh", true)
    if mesh then mesh.TextureId = data[1] end
    -- Title
    local title = clone:FindFirstChild("Title")
    if title and title:IsA("TextLabel") then title.Text = name:lower() end
    -- Equipped initially hidden
    local eq = clone:FindFirstChild("Equipped")
    if eq then eq.Visible = false end
    -- Effect badge — only if cue has a server-side effect
    local effFolder = ReplicatedStorage:FindFirstChild("Effects")
    local effBadge = clone:FindFirstChild("Effect")
    if effBadge then
        effBadge.Visible = (effFolder ~= nil) and (effFolder:FindFirstChild(name) ~= nil)
    end
    return clone
end

------------------------------------------------------------------- Build GUI
local screen = Instance.new("ScreenGui")
screen.Name              = "CueLibrary"
screen.IgnoreGuiInset    = true
screen.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
screen.ResetOnSpawn      = false
screen.DisplayOrder      = 999
screen.Parent            = guiParent

------------------------------------------------------------------- Backdrop
local backdrop = Instance.new("TextButton")
backdrop.Name                  = "Backdrop"
backdrop.Size                  = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.35
backdrop.BorderSizePixel       = 0
backdrop.Text                  = ""
backdrop.AutoButtonColor       = false
backdrop.Visible               = OPEN_BY_DEFAULT
backdrop.Parent                = screen

------------------------------------------------------------------- Panel
local panel = Instance.new("Frame")
panel.Name                = "Panel"
panel.AnchorPoint         = Vector2.new(0.5, 0.5)
panel.Position            = UDim2.fromScale(0.5, 0.5)
panel.Size                = UDim2.fromOffset(880, 620)
panel.BackgroundColor3    = Color3.fromRGB(8, 8, 12)
panel.BorderSizePixel     = 0
panel.Parent              = backdrop

local panelCorner = Instance.new("UICorner", panel)
panelCorner.CornerRadius = UDim.new(0, 14)

local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(40, 40, 55)
panelStroke.Thickness = 1
panelStroke.Transparency = 0.2

local panelGrad = Instance.new("UIGradient", panel)
panelGrad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 28)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 8)),
}
panelGrad.Rotation = 95

------------------------------------------------------------------- Header
local header = Instance.new("Frame", panel)
header.Name                = "Header"
header.Size                = UDim2.new(1, 0, 0, 64)
header.BackgroundTransparency = 1

local title = Instance.new("TextLabel", header)
title.Size                  = UDim2.new(1, -100, 0, 26)
title.Position              = UDim2.new(0, 24, 0, 14)
title.BackgroundTransparency= 1
title.Text                  = "CUE LIBRARY"
title.Font                  = Enum.Font.GothamBlack
title.TextSize              = 22
title.TextColor3            = Color3.fromRGB(255, 255, 255)
title.TextXAlignment        = Enum.TextXAlignment.Left

local subtitle = Instance.new("TextLabel", header)
subtitle.Size                  = UDim2.new(1, -100, 0, 14)
subtitle.Position              = UDim2.new(0, 24, 0, 38)
subtitle.BackgroundTransparency= 1
subtitle.Text                  = "click any cue to equip — you keep it across matches"
subtitle.Font                  = Enum.Font.Gotham
subtitle.TextSize              = 11
subtitle.TextColor3            = Color3.fromRGB(120, 120, 135)
subtitle.TextXAlignment        = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", header)
closeBtn.Size                = UDim2.fromOffset(36, 36)
closeBtn.Position            = UDim2.new(1, -52, 0, 14)
closeBtn.BackgroundColor3    = Color3.fromRGB(22, 22, 28)
closeBtn.BorderSizePixel     = 0
closeBtn.Text                = "✕"
closeBtn.TextColor3          = Color3.fromRGB(220, 220, 230)
closeBtn.Font                = Enum.Font.GothamBold
closeBtn.TextSize            = 16
closeBtn.AutoButtonColor     = false
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
closeBtn.MouseEnter:Connect(function()
    TweenService:Create(closeBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(220, 60, 60)}):Play()
end)
closeBtn.MouseLeave:Connect(function()
    TweenService:Create(closeBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(22, 22, 28)}):Play()
end)

------------------------------------------------------------------- Filter row
local filterRow = Instance.new("Frame", panel)
filterRow.Name                = "Filters"
filterRow.Position            = UDim2.new(0, 20, 0, 74)
filterRow.Size                = UDim2.new(1, -260, 0, 36)
filterRow.BackgroundTransparency = 1

local filterLayout = Instance.new("UIListLayout", filterRow)
filterLayout.FillDirection    = Enum.FillDirection.Horizontal
filterLayout.Padding          = UDim.new(0, 6)
filterLayout.VerticalAlignment= Enum.VerticalAlignment.Center

local activeFilter = "All"
local filterButtons = {}
local rebuildGrid -- forward decl

local function setFilter(f)
    activeFilter = f
    for fname, btn in pairs(filterButtons) do
        local active = (fname == f)
        TweenService:Create(btn, TweenInfo.new(0.16), {
            BackgroundColor3 = active and Color3.fromRGB(245, 245, 250) or Color3.fromRGB(22, 22, 28),
        }):Play()
        btn.TextColor3 = active and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(200, 200, 210)
        local s = btn:FindFirstChildOfClass("UIStroke")
        if s then s.Color = active and Color3.fromRGB(245,245,250) or Color3.fromRGB(45, 45, 55) end
    end
    if rebuildGrid then rebuildGrid() end
end

local function makeFilterBtn(name)
    local btn = Instance.new("TextButton", filterRow)
    btn.Size                = UDim2.fromOffset(name == "All" and 64 or 86, 32)
    btn.BackgroundColor3    = Color3.fromRGB(22, 22, 28)
    btn.BorderSizePixel     = 0
    btn.Text                = name
    btn.TextColor3          = Color3.fromRGB(200, 200, 210)
    btn.Font                = Enum.Font.GothamMedium
    btn.TextSize            = 12
    btn.AutoButtonColor     = false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(45, 45, 55)
    stroke.Thickness = 1
    btn.MouseButton1Click:Connect(function() setFilter(name) end)
    filterButtons[name] = btn
    return btn
end

makeFilterBtn("All")
for _, r in ipairs(rarityList) do makeFilterBtn(r) end

------------------------------------------------------------------- Search
local searchFrame = Instance.new("Frame", panel)
searchFrame.Position           = UDim2.new(1, -240, 0, 74)
searchFrame.Size               = UDim2.fromOffset(220, 36)
searchFrame.BackgroundColor3   = Color3.fromRGB(15, 15, 20)
searchFrame.BorderSizePixel    = 0
Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 8)
local sStroke = Instance.new("UIStroke", searchFrame)
sStroke.Color = Color3.fromRGB(45,45,55)
sStroke.Thickness = 1

local searchIcon = Instance.new("TextLabel", searchFrame)
searchIcon.Size                = UDim2.fromOffset(20, 36)
searchIcon.Position            = UDim2.new(0, 8, 0, 0)
searchIcon.BackgroundTransparency = 1
searchIcon.Text                = "⌕"
searchIcon.Font                = Enum.Font.GothamBold
searchIcon.TextSize            = 18
searchIcon.TextColor3          = Color3.fromRGB(120, 120, 135)

local search = Instance.new("TextBox", searchFrame)
search.Size                  = UDim2.new(1, -36, 1, 0)
search.Position              = UDim2.new(0, 30, 0, 0)
search.BackgroundTransparency= 1
search.PlaceholderText       = "search cue…"
search.PlaceholderColor3     = Color3.fromRGB(85, 85, 100)
search.Text                  = ""
search.Font                  = Enum.Font.Gotham
search.TextSize              = 13
search.TextColor3            = Color3.fromRGB(255, 255, 255)
search.TextXAlignment        = Enum.TextXAlignment.Left
search.ClearTextOnFocus      = false

------------------------------------------------------------------- Grid body
local body = Instance.new("ScrollingFrame", panel)
body.Name                    = "Grid"
body.Position                = UDim2.new(0, 20, 0, 122)
body.Size                    = UDim2.new(1, -40, 1, -160)
body.BackgroundTransparency  = 1
body.BorderSizePixel         = 0
body.ScrollBarThickness      = 5
body.ScrollBarImageColor3    = Color3.fromRGB(80, 80, 95)
body.ScrollBarImageTransparency = 0.2
body.CanvasSize              = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize     = Enum.AutomaticSize.Y

local gridLayout = Instance.new("UIGridLayout", body)
gridLayout.CellSize         = UDim2.fromOffset(196, 196)
gridLayout.CellPadding      = UDim2.fromOffset(12, 12)
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
gridLayout.SortOrder        = Enum.SortOrder.LayoutOrder

local gridPad = Instance.new("UIPadding", body)
gridPad.PaddingTop          = UDim.new(0, 4)
gridPad.PaddingBottom       = UDim.new(0, 12)
gridPad.PaddingRight        = UDim.new(0, 4)

------------------------------------------------------------------- Footer
local footer = Instance.new("Frame", panel)
footer.Position              = UDim2.new(0, 20, 1, -34)
footer.Size                  = UDim2.new(1, -40, 0, 24)
footer.BackgroundTransparency = 1

local equippedLbl = Instance.new("TextLabel", footer)
equippedLbl.Size              = UDim2.new(0.7, 0, 1, 0)
equippedLbl.BackgroundTransparency = 1
equippedLbl.Text              = "Equipped: …"
equippedLbl.Font              = Enum.Font.GothamMedium
equippedLbl.TextSize          = 12
equippedLbl.TextColor3        = Color3.fromRGB(160, 160, 175)
equippedLbl.TextXAlignment    = Enum.TextXAlignment.Left

local hint = Instance.new("TextLabel", footer)
hint.Size                = UDim2.new(0.3, 0, 1, 0)
hint.Position            = UDim2.new(0.7, 0, 0, 0)
hint.BackgroundTransparency = 1
hint.Text                = "RightShift to toggle"
hint.Font                = Enum.Font.Gotham
hint.TextSize            = 11
hint.TextColor3          = Color3.fromRGB(110, 110, 125)
hint.TextXAlignment      = Enum.TextXAlignment.Right

------------------------------------------------------------------- Toast
local toast = Instance.new("Frame", screen)
toast.Name                  = "Toast"
toast.AnchorPoint           = Vector2.new(0.5, 0)
toast.Position              = UDim2.new(0.5, 0, 0, -50)
toast.Size                  = UDim2.fromOffset(280, 44)
toast.BackgroundColor3      = Color3.fromRGB(20, 20, 28)
toast.BorderSizePixel       = 0
toast.Visible               = false
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)
local toastStroke = Instance.new("UIStroke", toast)
toastStroke.Color = Color3.fromRGB(80, 220, 130)
toastStroke.Thickness = 1
local toastTxt = Instance.new("TextLabel", toast)
toastTxt.Size                = UDim2.fromScale(1, 1)
toastTxt.BackgroundTransparency = 1
toastTxt.Text                = ""
toastTxt.Font                = Enum.Font.GothamMedium
toastTxt.TextSize            = 13
toastTxt.TextColor3          = Color3.fromRGB(255, 255, 255)

local toastTween = nil
local function showToast(msg, color)
    toastTxt.Text = msg
    toastStroke.Color = color or Color3.fromRGB(80, 220, 130)
    toast.Visible = true
    toast.Position = UDim2.new(0.5, 0, 0, -50)
    if toastTween then toastTween:Cancel() end
    local inT = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Position = UDim2.new(0.5, 0, 0, 24)})
    inT:Play()
    task.delay(1.6, function()
        local outT = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            {Position = UDim2.new(0.5, 0, 0, -50)})
        outT:Play()
        outT.Completed:Connect(function() toast.Visible = false end)
    end)
end

------------------------------------------------------------------- Card render
local cardByKey      = {}
local equippedCard   = nil
local currentEqRarity, currentEqName = nil, nil

local function refreshEquippedLabel()
    if currentEqRarity and currentEqName then
        equippedLbl.Text = "Equipped:  " .. currentEqRarity .. "  ·  " .. currentEqName:lower()
    else
        equippedLbl.Text = "Equipped:  —"
    end
end

local function applyEquippedHighlight()
    if equippedCard then
        local s = equippedCard:FindFirstChildOfClass("UIStroke")
        if s then
            TweenService:Create(s, TweenInfo.new(0.15), {Color = Color3.fromRGB(55, 55, 70), Thickness = 1, Transparency = 0}):Play()
        end
        local eq = equippedCard:FindFirstChild("Equipped")
        if eq then eq.Visible = false end
        equippedCard = nil
    end
    if currentEqRarity and currentEqName then
        local card = cardByKey[currentEqRarity .. ":" .. currentEqName]
        if card then
            local s = card:FindFirstChildOfClass("UIStroke")
            if s then
                TweenService:Create(s, TweenInfo.new(0.18), {Color = Color3.fromRGB(80, 220, 130), Thickness = 2, Transparency = 0}):Play()
            end
            local eq = card:FindFirstChild("Equipped")
            if eq then eq.Visible = true end
            equippedCard = card
        end
    end
end

local function styleCard(card, rarity)
    -- Override the template stroke baseline so it pops against our dark panel
    local s = card:FindFirstChildOfClass("UIStroke")
    if s then s.Color = Color3.fromRGB(55, 55, 70); s.Thickness = 1 end
    -- Tint title with rarity color
    local title = card:FindFirstChild("Title")
    if title and title:IsA("TextLabel") then
        title.TextColor3 = rarityColor[rarity] or Color3.fromRGB(220,220,220)
    end
end

local function attachInteractions(card, rarity, name)
    local s = card:FindFirstChildOfClass("UIStroke")
    card.MouseEnter:Connect(function()
        if equippedCard ~= card and s then
            TweenService:Create(s, TweenInfo.new(0.12), {Color = rarityColor[rarity] or Color3.fromRGB(255,255,255), Thickness = 2}):Play()
        end
    end)
    card.MouseLeave:Connect(function()
        if equippedCard ~= card and s then
            TweenService:Create(s, TweenInfo.new(0.12), {Color = Color3.fromRGB(55,55,70), Thickness = 1}):Play()
        end
    end)
    card.MouseButton1Click:Connect(function()
        -- click ripple
        local origColor = card.BackgroundColor3
        TweenService:Create(card, TweenInfo.new(0.06), {BackgroundColor3 = Color3.fromRGB(40,40,55)}):Play()
        task.delay(0.08, function()
            TweenService:Create(card, TweenInfo.new(0.18), {BackgroundColor3 = origColor}):Play()
        end)
        fireEquip(rarity, name)
        currentEqRarity, currentEqName = rarity, name
        refreshEquippedLabel()
        applyEquippedHighlight()
        showToast(("Equipped  %s  (%s)"):format(name:lower(), rarity), rarityColor[rarity])
    end)
end

------------------------------------------------------------------- Build cue list
local allCues = {}
for _, rarity in ipairs(rarityList) do
    for name, data in pairs(cuesIndex[rarity] or {}) do
        table.insert(allCues, {rarity = rarity, name = name, data = data})
    end
end
table.sort(allCues, function(a, b)
    if a.rarity ~= b.rarity then return rarityRank[a.rarity] < rarityRank[b.rarity] end
    return a.name < b.name
end)

rebuildGrid = function()
    for _, child in ipairs(body:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    cardByKey = {}
    equippedCard = nil

    local q = (search.Text or ""):lower()
    local idx = 1
    for _, c in ipairs(allCues) do
        local matchFilter = (activeFilter == "All") or (c.rarity == activeFilter)
        local matchSearch = (q == "") or (string.find(c.name:lower(), q, 1, true) ~= nil)
        if matchFilter and matchSearch then
            local card = cloneTemplate(c.rarity, c.name, c.data)
            if card then
                card.Parent     = body
                card.LayoutOrder = idx
                styleCard(card, c.rarity)
                attachInteractions(card, c.rarity, c.name)
                cardByKey[c.rarity .. ":" .. c.name] = card
                idx = idx + 1
            end
        end
    end
    applyEquippedHighlight()
end

search:GetPropertyChangedSignal("Text"):Connect(function() rebuildGrid() end)
setFilter("All")

------------------------------------------------------------------- Open / close
local opening = false
local function setOpen(open)
    if opening then return end
    opening = true
    if open then
        currentEqRarity, currentEqName = getEquipped()
        refreshEquippedLabel()
        applyEquippedHighlight()
        backdrop.Visible = true
        backdrop.BackgroundTransparency = 1
        panel.Size = UDim2.fromOffset(880 * 0.92, 620 * 0.92)
        TweenService:Create(backdrop, TweenInfo.new(0.18), {BackgroundTransparency = 0.35}):Play()
        TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Size = UDim2.fromOffset(880, 620)}):Play()
        task.wait(0.22)
    else
        TweenService:Create(backdrop, TweenInfo.new(0.16), {BackgroundTransparency = 1}):Play()
        TweenService:Create(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
            {Size = UDim2.fromOffset(880 * 0.92, 620 * 0.92)}):Play()
        task.wait(0.16)
        backdrop.Visible = false
    end
    opening = false
end

closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
backdrop.MouseButton1Click:Connect(function(input)
    -- click on backdrop (outside panel) closes — but only if NOT clicking through panel
    local mx, my = input and input.Position and input.Position.X or nil, nil
    -- Easier: just rely on a separate hit test. For now, ignore (close button + key are enough).
end)

------------------------------------------------------------------- Floating toggle
local toggleBtn = Instance.new("TextButton", screen)
toggleBtn.Name              = "Toggle"
toggleBtn.Size              = UDim2.fromOffset(56, 56)
toggleBtn.AnchorPoint       = Vector2.new(1, 1)
toggleBtn.Position          = UDim2.new(1, -22, 1, -22)
toggleBtn.BackgroundColor3  = Color3.fromRGB(15, 15, 20)
toggleBtn.BorderSizePixel   = 0
toggleBtn.AutoButtonColor   = false
toggleBtn.Text              = "🎱"
toggleBtn.Font              = Enum.Font.GothamBlack
toggleBtn.TextSize          = 28
toggleBtn.TextColor3        = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(1, 0)
local togStroke = Instance.new("UIStroke", toggleBtn)
togStroke.Color = Color3.fromRGB(80, 80, 95)
togStroke.Thickness = 1
toggleBtn.MouseEnter:Connect(function()
    TweenService:Create(toggleBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(35, 35, 48)}):Play()
    TweenService:Create(togStroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(220, 110, 255)}):Play()
end)
toggleBtn.MouseLeave:Connect(function()
    TweenService:Create(toggleBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(15, 15, 20)}):Play()
    TweenService:Create(togStroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(80, 80, 95)}):Play()
end)
toggleBtn.MouseButton1Click:Connect(function() setOpen(not backdrop.Visible) end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == TOGGLE_KEY then setOpen(not backdrop.Visible) end
end)

------------------------------------------------------------------- Slow rotation on viewport cards (eye-candy)
RunService.RenderStepped:Connect(function(dt)
    if not backdrop.Visible then return end
    for _, card in pairs(cardByKey) do
        local vf = card:FindFirstChild("CueFrame")
        if vf and vf:IsA("ViewportFrame") then
            local part = vf:FindFirstChildWhichIsA("BasePart")
            if part then
                part.CFrame = part.CFrame * CFrame.Angles(0, dt * 0.4, 0)
            end
        end
    end
end)

print("[CueLibrary] Loaded. Toggle: RightShift, or click the 🎱 button (bottom-right).")
