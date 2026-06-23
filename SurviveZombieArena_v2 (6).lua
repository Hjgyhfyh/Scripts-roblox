local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local Stats             = game:GetService("Stats")
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    killKey       = Enum.KeyCode.K,
    gearKey       = Enum.KeyCode.P,
    worldEnderKey = Enum.KeyCode.R,
    gearName      = "SoulHarvester",
    zombieFolder  = "Zombies_Local",
    spawnFolder   = "SpawnCircle",
    statsFile     = "SurviveZombieArena_stats.json",
    currency1     = { name = "Ивент", path = "" },
}

local worldEnderArgs = {
    "WorldEnder",
    vector.create(-227.2508087158203, 464.9515686035156, -368.25848388671875),
    vector.create(-0.5517296195030212, 0, -0.8340230584144592),
}

local function destroyOldGuis()
    local parents = {}
    if gethui then parents[#parents+1] = gethui() end
    parents[#parents+1] = LocalPlayer:FindFirstChild("PlayerGui")
    pcall(function() parents[#parents+1] = game:GetService("CoreGui") end)
    for _, parent in ipairs(parents) do
        if parent then
            for _, child in ipairs(parent:GetChildren()) do
                if child.Name == "KillAuraUI" or child.Name == "ZA_KillHUD"
                   or (child.Name == "Rayfield" and child:GetAttribute("ZA_Owner")) then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
end

if _G.SurviveZombieArena and _G.SurviveZombieArena.unload then
    pcall(_G.SurviveZombieArena.unload)
end
destroyOldGuis()

local ALIVE = true
local connections = {}
local function track(c) connections[#connections+1] = c return c end

local stats = {
    rTotal = 0, pTotal = 0, hpTotal = 0,
    cur1Total = 0,
}
local session = { r = 0, p = 0, hp = 0, killaura = 0 }

local function loadStats()
    if isfile and isfile(CONFIG.statsFile) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CONFIG.statsFile)) end)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do if type(v) == "number" then stats[k] = v end end
        end
    end
end
local function saveStats()
    if writefile then pcall(function() writefile(CONFIG.statsFile, HttpService:JSONEncode(stats)) end) end
end
loadStats()

local opt = {
    mode = "All", targets = 20, speed = 0.1,
    rRate = 15, pRate = 15, hpRate = 20, maxReq = 400, walk = 16,
}
local state = { killaura=false, rspam=false, pspam=false, hpspam=false, noclip=false, nofog=false, fullbright=false, antilag=false }

local reqWindowStart = os.clock()
local reqThisWindow = 0
local function canFire()
    local now = os.clock()
    if now - reqWindowStart >= 1 then reqWindowStart = now; reqThisWindow = 0 end
    if reqThisWindow >= opt.maxReq then return false end
    reqThisWindow += 1
    return true
end

local GunHit       = ReplicatedStorage:WaitForChild("GunRemotes"):WaitForChild("GunHit")
local GearPurchase = ReplicatedStorage:WaitForChild("GearRemotes"):WaitForChild("GearPurchase")
local GunFire      = ReplicatedStorage:WaitForChild("NetRemotes"):WaitForChild("GunFire")
local HealthUpgrade = ReplicatedStorage:WaitForChild("UpgradeRemotes"):WaitForChild("PurchaseHealthUpgrade")

local function getZombieFolder() return Workspace:FindFirstChild(CONFIG.zombieFolder) end

local function getZombies()
    local out = {}
    local folder = getZombieFolder()
    if not folder then return out end
    for _, z in ipairs(folder:GetChildren()) do
        local id = tonumber(z.Name:match("(%d+)$"))
        local root = z:FindFirstChild("HumanoidRootPart") or z.PrimaryPart
        if id and root then out[#out+1] = { id = id, model = z, root = root } end
    end
    return out
end

local function zombieCount()
    local f = getZombieFolder()
    return f and #f:GetChildren() or 0
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

local function pickTargets()
    local zombies = getZombies()
    if opt.mode == "All" then return zombies
    elseif opt.mode == "Nearest" then
        local origin = myPos()
        if not origin then return {} end
        table.sort(zombies, function(a,b) return (a.root.Position-origin).Magnitude < (b.root.Position-origin).Magnitude end)
        local n = math.min(opt.targets, #zombies); local res = {}
        for i=1,n do res[i]=zombies[i] end
        return res
    else
        local n = math.min(opt.targets, #zombies)
        for i=1,n do local j = math.random(i,#zombies); zombies[i],zombies[j]=zombies[j],zombies[i] end
        local res = {}
        for i=1,n do res[i]=zombies[i] end
        return res
    end
end

local function killauraLoop()
    while state.killaura and ALIVE do
        local weapon = equippedWeapon()
        if weapon ~= "—" then
            for _, z in ipairs(pickTargets()) do
                if z.model.Parent and z.root.Parent and canFire() then
                    local p = z.root.Position
                    GunHit:FireServer(weapon, z.id, vector.create(p.X, p.Y, p.Z))
                    session.killaura += 1
                end
            end
        end
        task.wait(opt.speed)
    end
end

local function rLoop()
    while state.rspam and ALIVE do
        if canFire() then
            GunFire:FireServer(table.unpack(worldEnderArgs))
            session.r += 1; stats.rTotal += 1
        end
        task.wait(1 / math.clamp(opt.rRate, 1, 15))
    end
end

local function pLoop()
    while state.pspam and ALIVE do
        if canFire() then
            GearPurchase:FireServer(CONFIG.gearName)
            session.p += 1; stats.pTotal += 1
        end
        task.wait(1 / math.clamp(opt.pRate, 1, 15))
    end
end

local function hpLoop()
    while state.hpspam and ALIVE do
        if canFire() then
            HealthUpgrade:FireServer()
            session.hp += 1; stats.hpTotal += 1
        end
        task.wait(1 / math.clamp(opt.hpRate, 1, 20))
    end
end

local function resolveValue(pathStr)
    if not pathStr or pathStr == "" then return nil end
    local node = LocalPlayer
    if pathStr:sub(1,5) == "game." then node = game; pathStr = pathStr:sub(6) end
    for seg in pathStr:gmatch("[^%.]+") do
        if not node then return nil end
        node = node:FindFirstChild(seg)
    end
    if not node then return nil end
    if node:IsA("ValueBase") then return tonumber(node.Value) end
    if node:IsA("TextLabel") or node:IsA("TextButton") then
        return tonumber((node.Text:gsub("[^%d]", "")))
    end
    return nil
end
local lastCur1

local fps = 60
do
    local frames = 0
    local last = os.clock()
    track(RunService.RenderStepped:Connect(function()
        frames += 1
        local now = os.clock()
        if now - last >= 1 then fps = frames; frames = 0; last = now end
    end))
end
local function getPing()
    local ok, v = pcall(function() return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
    return ok and v or 0
end

local noclipConn
local function setNoclip(on)
    state.noclip = on
    if on and not noclipConn then
        noclipConn = RunService.Stepped:Connect(function()
            if not ALIVE then return end
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
                end
            end
        end)
    elseif not on and noclipConn then
        noclipConn:Disconnect(); noclipConn = nil
    end
end

local savedLighting = {
    Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
    Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
    GlobalShadows = Lighting.GlobalShadows,
}
local function applyNoFog()
    if state.nofog then
        Lighting.FogEnd = 1e9; Lighting.FogStart = 1e9
        for _, v in ipairs(Lighting:GetChildren()) do if v:IsA("Atmosphere") then v.Density = 0 end end
    else
        Lighting.FogEnd = savedLighting.FogEnd; Lighting.FogStart = savedLighting.FogStart
    end
end
local function applyFullBright()
    if state.fullbright then
        Lighting.Brightness = 2; Lighting.ClockTime = 14; Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(255,255,255); Lighting.OutdoorAmbient = Color3.fromRGB(255,255,255)
    else
        Lighting.Brightness = savedLighting.Brightness; Lighting.ClockTime = savedLighting.ClockTime
        Lighting.GlobalShadows = savedLighting.GlobalShadows
        Lighting.Ambient = savedLighting.Ambient; Lighting.OutdoorAmbient = savedLighting.OutdoorAmbient
    end
end
local function setWalkSpeed(v)
    opt.walk = v
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = v end
end
track(LocalPlayer.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then hum.WalkSpeed = opt.walk end
    if state.fullbright then applyFullBright() end
    if state.nofog then applyNoFog() end
end))

local restoreData = setmetatable({}, { __mode = "k" })
local function hideInstance(inst)
    if restoreData[inst] ~= nil then return end
    if inst:IsA("BasePart") then
        if restoreData[inst] == nil then restoreData[inst] = inst.Transparency end
        inst.LocalTransparencyModifier = 1
        inst.Transparency = 1
    elseif inst:IsA("Decal") or inst:IsA("Texture") then
        if restoreData[inst] == nil then restoreData[inst] = inst.Transparency end
        inst.Transparency = 1
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
        if restoreData[inst] == nil then restoreData[inst] = inst.Enabled end
        inst.Enabled = false
    elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") or inst:IsA("Highlight") then
        if restoreData[inst] == nil then restoreData[inst] = inst.Enabled end
        inst.Enabled = false
    end
end
local function sweepFolder()
    local f = getZombieFolder()
    if f then for _, d in ipairs(f:GetDescendants()) do hideInstance(d) end end
    local sc = Workspace:FindFirstChild(CONFIG.spawnFolder)
    if sc then
        hideInstance(sc)
        for _, d in ipairs(sc:GetDescendants()) do hideInstance(d) end
    end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("BillboardGui") then hideInstance(d) end
        end
    end
end
local function setAntiLag(on)
    state.antilag = on
    if on then
        pcall(function()
            UserSettings():GetService("UserGameSettings").SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
        sweepFolder()
    else
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
        for inst, val in pairs(restoreData) do
            if inst and inst.Parent then
                pcall(function()
                    if inst:IsA("BasePart") then inst.LocalTransparencyModifier = 0; inst.Transparency = val
                    elseif inst:IsA("Decal") or inst:IsA("Texture") then inst.Transparency = val
                    else inst.Enabled = val end
                end)
            end
        end
        restoreData = setmetatable({}, { __mode = "k" })
    end
end

local function maxZombieId()
    local f = getZombieFolder()
    if not f then return 0 end
    local m = 0
    for _, z in ipairs(f:GetChildren()) do
        local id = tonumber(z.Name:match("(%d+)$"))
        if id and id > m then m = id end
    end
    return m
end
local hud = Instance.new("ScreenGui")
hud.Name = "ZA_KillHUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = 9
hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hud.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 14)
bar.Size = UDim2.new(0, 0, 0, 46)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
bar.BackgroundTransparency = 0.08
bar.BorderSizePixel = 0
bar.Active = true
bar.Parent = hud
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 12)
local grad = Instance.new("UIGradient", bar)
grad.Color = ColorSequence.new(Color3.fromRGB(34, 34, 52), Color3.fromRGB(16, 16, 24))
grad.Rotation = 90
local barStroke = Instance.new("UIStroke", bar)
barStroke.Color = Color3.fromRGB(95, 115, 170); barStroke.Thickness = 1.4; barStroke.Transparency = 0.15
local barPad = Instance.new("UIPadding", bar)
barPad.PaddingLeft = UDim.new(0, 18); barPad.PaddingRight = UDim.new(0, 18)
local barLayout = Instance.new("UIListLayout", bar)
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
barLayout.Padding = UDim.new(0, 18)
barLayout.SortOrder = Enum.SortOrder.LayoutOrder

local function makeStat(order)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.AutomaticSize = Enum.AutomaticSize.X
    l.Size = UDim2.new(0, 0, 1, 0)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 16
    l.RichText = true
    l.TextColor3 = Color3.fromRGB(235, 235, 245)
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.LayoutOrder = order
    l.Parent = bar
    return l
end
local sPassed = makeStat(1)
local sFps    = makeStat(2)
local sPing   = makeStat(3)

do
    local dragging, dragStart, startPos
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startPos = bar.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            bar.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
end

local function updateHUD()
    local ping = getPing()
    sPassed.Text = "🧟 <font color='#ff8a8a'>Прошло</font>  <b>" .. maxZombieId() .. "</b>"
    sFps.Text    = "🎯 <font color='#8ab4ff'>FPS</font>  <b>" .. fps .. "</b>"
    local pc = ping < 80 and "#8affa0" or (ping < 160 and "#ffd27f" or "#ff8a8a")
    sPing.Text   = "📶 <font color='" .. pc .. "'>Пинг</font>  <b>" .. ping .. " мс</b>"
end

local function buildNativeLib()
    local UI = {}
    local ACCENT = Color3.fromRGB(90, 120, 255)
    local BG  = Color3.fromRGB(24, 24, 32)
    local BG2 = Color3.fromRGB(32, 32, 42)
    local BG3 = Color3.fromRGB(44, 44, 58)
    local TXT = Color3.fromRGB(235, 235, 245)
    local SUB = Color3.fromRGB(165, 165, 185)
    local function corner(p, r) local c = Instance.new("UICorner", p); c.CornerRadius = UDim.new(0, r or 8); return c end
    local function stroke(p, col, th) local s = Instance.new("UIStroke", p); s.Color = col or BG3; s.Thickness = th or 1; s.Transparency = 0.2; return s end

    local screen = Instance.new("ScreenGui")
    screen.Name = "ZA_NativeUI"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 10
    screen.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

    function UI:Destroy() pcall(function() screen:Destroy() end) end

    function UI:CreateWindow(o)
        local Window = {}
        local main = Instance.new("Frame")
        main.Size = UDim2.new(0, 540, 0, 400)
        main.Position = UDim2.new(0.5, -270, 0.5, -200)
        main.BackgroundColor3 = BG
        main.BorderSizePixel = 0
        main.Active = true
        main.Parent = screen
        corner(main, 12); stroke(main, BG3, 1.4)

        local top = Instance.new("Frame")
        top.Size = UDim2.new(1, 0, 0, 46)
        top.BackgroundColor3 = BG2
        top.BorderSizePixel = 0
        top.Parent = main
        corner(top, 12)
        local topFix = Instance.new("Frame")
        topFix.Size = UDim2.new(1, 0, 0, 16); topFix.Position = UDim2.new(0, 0, 1, -16)
        topFix.BackgroundColor3 = BG2; topFix.BorderSizePixel = 0; topFix.Parent = top
        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Position = UDim2.new(0, 16, 0, 0); title.Size = UDim2.new(1, -110, 1, 0)
        title.Font = Enum.Font.GothamBold; title.TextSize = 16
        title.TextXAlignment = Enum.TextXAlignment.Left; title.TextColor3 = TXT
        title.Text = o.Name or "Menu"; title.Parent = top

        do
            local dragging, ds, sp
            top.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                    dragging = true; ds = i.Position; sp = main.Position
                end
            end)
            UserInputService.InputChanged:Connect(function(i)
                if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                    local d = i.Position - ds
                    main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
                end
            end)
            UserInputService.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
            end)
        end

        local body
        local minimized = false
        local btnClose = Instance.new("TextButton")
        btnClose.Size = UDim2.new(0, 28, 0, 28); btnClose.Position = UDim2.new(1, -36, 0, 9)
        btnClose.BackgroundColor3 = Color3.fromRGB(200, 70, 70); btnClose.Text = "✕"; btnClose.TextColor3 = TXT
        btnClose.Font = Enum.Font.GothamBold; btnClose.TextSize = 14; btnClose.Parent = top; corner(btnClose, 6)
        local btnMin = Instance.new("TextButton")
        btnMin.Size = UDim2.new(0, 28, 0, 28); btnMin.Position = UDim2.new(1, -70, 0, 9)
        btnMin.BackgroundColor3 = BG3; btnMin.Text = "—"; btnMin.TextColor3 = TXT
        btnMin.Font = Enum.Font.GothamBold; btnMin.TextSize = 14; btnMin.Parent = top; corner(btnMin, 6)
        btnClose.MouseButton1Click:Connect(function() main.Visible = false end)
        btnMin.MouseButton1Click:Connect(function()
            minimized = not minimized
            if body then body.Visible = not minimized end
            main.Size = minimized and UDim2.new(0, 540, 0, 46) or UDim2.new(0, 540, 0, 400)
        end)

        body = Instance.new("Frame")
        body.BackgroundTransparency = 1
        body.Position = UDim2.new(0, 0, 0, 46); body.Size = UDim2.new(1, 0, 1, -46); body.Parent = main

        local side = Instance.new("Frame")
        side.Size = UDim2.new(0, 140, 1, 0); side.BackgroundColor3 = BG2; side.BorderSizePixel = 0; side.Parent = body
        local sideList = Instance.new("UIListLayout", side); sideList.Padding = UDim.new(0, 6); sideList.SortOrder = Enum.SortOrder.LayoutOrder
        local sidePad = Instance.new("UIPadding", side); sidePad.PaddingTop = UDim.new(0, 12); sidePad.PaddingLeft = UDim.new(0, 10); sidePad.PaddingRight = UDim.new(0, 10)

        local content = Instance.new("Frame")
        content.Position = UDim2.new(0, 140, 0, 0); content.Size = UDim2.new(1, -140, 1, 0); content.BackgroundTransparency = 1; content.Parent = body

        local tabs = {}
        local function selectTab(tab)
            for _, t in ipairs(tabs) do
                t.page.Visible = (t == tab)
                t.btn.BackgroundColor3 = (t == tab) and ACCENT or BG3
                t.btn.TextColor3 = (t == tab) and Color3.fromRGB(255, 255, 255) or SUB
            end
        end

        function Window:CreateTab(name)
            local Tab = {}
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 0, 34); btn.BackgroundColor3 = BG3; btn.Text = name
            btn.Font = Enum.Font.GothamMedium; btn.TextSize = 13; btn.TextColor3 = SUB; btn.AutoButtonColor = false
            btn.Parent = side; corner(btn, 7)

            local page = Instance.new("ScrollingFrame")
            page.Size = UDim2.new(1, 0, 1, 0); page.BackgroundTransparency = 1; page.BorderSizePixel = 0
            page.ScrollBarThickness = 4; page.ScrollBarImageColor3 = ACCENT
            page.CanvasSize = UDim2.new(0, 0, 0, 0); page.AutomaticCanvasSize = Enum.AutomaticSize.Y
            page.Visible = false; page.Parent = content
            local pl = Instance.new("UIListLayout", page); pl.Padding = UDim.new(0, 8); pl.SortOrder = Enum.SortOrder.LayoutOrder
            local pp = Instance.new("UIPadding", page); pp.PaddingTop = UDim.new(0, 14); pp.PaddingLeft = UDim.new(0, 14); pp.PaddingRight = UDim.new(0, 14); pp.PaddingBottom = UDim.new(0, 14)

            local tabObj = { btn = btn, page = page }
            tabs[#tabs + 1] = tabObj
            btn.MouseButton1Click:Connect(function() selectTab(tabObj) end)
            if #tabs == 1 then selectTab(tabObj) end

            local function card(h)
                local f = Instance.new("Frame")
                f.Size = UDim2.new(1, 0, 0, h or 44); f.BackgroundColor3 = BG2; f.BorderSizePixel = 0; f.Parent = page
                corner(f, 8)
                return f
            end

            function Tab:CreateSection(text)
                local l = Instance.new("TextLabel")
                l.Size = UDim2.new(1, 0, 0, 22); l.BackgroundTransparency = 1; l.Text = text
                l.Font = Enum.Font.GothamBold; l.TextSize = 12; l.TextColor3 = ACCENT; l.TextXAlignment = Enum.TextXAlignment.Left
                l.Parent = page
                return l
            end

            function Tab:CreateToggle(opt)
                local val = opt.CurrentValue and true or false
                local f = card(44)
                local lbl = Instance.new("TextLabel")
                lbl.BackgroundTransparency = 1; lbl.Position = UDim2.new(0, 14, 0, 0); lbl.Size = UDim2.new(1, -80, 1, 0)
                lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 14; lbl.TextColor3 = TXT; lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.Text = opt.Name; lbl.Parent = f
                local sw = Instance.new("TextButton")
                sw.Size = UDim2.new(0, 46, 0, 24); sw.Position = UDim2.new(1, -60, 0.5, -12); sw.AutoButtonColor = false
                sw.Text = ""; sw.BackgroundColor3 = val and ACCENT or BG3; sw.Parent = f; corner(sw, 12)
                local knob = Instance.new("Frame")
                knob.Size = UDim2.new(0, 18, 0, 18); knob.Position = val and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
                knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255); knob.Parent = sw; corner(knob, 9)
                local function apply()
                    sw.BackgroundColor3 = val and ACCENT or BG3
                    knob.Position = val and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
                end
                sw.MouseButton1Click:Connect(function() val = not val; apply(); pcall(opt.Callback, val) end)
                local obj = {}
                function obj:Set(v) val = v and true or false; apply(); pcall(opt.Callback, val) end
                return obj
            end

            function Tab:CreateButton(opt)
                local f = card(40)
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(1, 0, 1, 0); b.BackgroundTransparency = 1; b.Text = opt.Name
                b.Font = Enum.Font.GothamMedium; b.TextSize = 14; b.TextColor3 = TXT; b.Parent = f
                b.MouseButton1Click:Connect(function() pcall(opt.Callback) end)
                return {}
            end

            function Tab:CreateSlider(opt)
                local minv, maxv = opt.Range[1], opt.Range[2]
                local inc = opt.Increment or 1
                local val = opt.CurrentValue or minv
                local suffix = opt.Suffix or ""
                local f = card(54)
                local lbl = Instance.new("TextLabel")
                lbl.BackgroundTransparency = 1; lbl.Position = UDim2.new(0, 14, 0, 6); lbl.Size = UDim2.new(1, -110, 0, 18)
                lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 14; lbl.TextColor3 = TXT; lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.Text = opt.Name; lbl.Parent = f
                local valLbl = Instance.new("TextLabel")
                valLbl.BackgroundTransparency = 1; valLbl.Position = UDim2.new(1, -96, 0, 6); valLbl.Size = UDim2.new(0, 82, 0, 18)
                valLbl.Font = Enum.Font.GothamBold; valLbl.TextSize = 13; valLbl.TextColor3 = ACCENT; valLbl.TextXAlignment = Enum.TextXAlignment.Right
                valLbl.Parent = f
                local trackBar = Instance.new("Frame")
                trackBar.Position = UDim2.new(0, 14, 1, -18); trackBar.Size = UDim2.new(1, -28, 0, 8); trackBar.BackgroundColor3 = BG3; trackBar.BorderSizePixel = 0; trackBar.Parent = f
                corner(trackBar, 4)
                local fill = Instance.new("Frame")
                fill.BackgroundColor3 = ACCENT; fill.BorderSizePixel = 0; fill.Parent = trackBar; corner(fill, 4)
                local function refresh()
                    local p = (val - minv) / (maxv - minv)
                    fill.Size = UDim2.new(p, 0, 1, 0); valLbl.Text = tostring(val) .. suffix
                end
                refresh()
                local dragging = false
                local function setFromX(px)
                    local rel = math.clamp((px - trackBar.AbsolutePosition.X) / trackBar.AbsoluteSize.X, 0, 1)
                    local raw = minv + rel * (maxv - minv)
                    val = math.clamp(math.floor(raw / inc + 0.5) * inc, minv, maxv)
                    refresh(); pcall(opt.Callback, val)
                end
                trackBar.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true; setFromX(i.Position.X) end
                end)
                UserInputService.InputChanged:Connect(function(i)
                    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setFromX(i.Position.X) end
                end)
                UserInputService.InputEnded:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
                end)
                return {}
            end

            function Tab:CreateDropdown(opt)
                local options = opt.Options or {}
                local cur = (opt.CurrentOption and opt.CurrentOption[1]) or options[1] or ""
                local f = card(44)
                local open = false
                local lbl = Instance.new("TextLabel")
                lbl.BackgroundTransparency = 1; lbl.Position = UDim2.new(0, 14, 0, 0); lbl.Size = UDim2.new(0.5, -14, 0, 44)
                lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 14; lbl.TextColor3 = TXT; lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.Text = opt.Name; lbl.Parent = f
                local sel = Instance.new("TextButton")
                sel.Position = UDim2.new(0.5, 0, 0, 7); sel.Size = UDim2.new(0.5, -14, 0, 30); sel.BackgroundColor3 = BG3
                sel.Font = Enum.Font.GothamMedium; sel.TextSize = 13; sel.TextColor3 = TXT; sel.AutoButtonColor = false
                sel.Text = cur .. "  ▾"; sel.Parent = f; corner(sel, 6)
                local listHolder = Instance.new("Frame")
                listHolder.Position = UDim2.new(0.5, 0, 0, 40); listHolder.Size = UDim2.new(0.5, -14, 0, 0); listHolder.BackgroundColor3 = BG3
                listHolder.BorderSizePixel = 0; listHolder.ClipsDescendants = true; listHolder.Visible = false; listHolder.ZIndex = 5; listHolder.Parent = f
                corner(listHolder, 6)
                local lhl = Instance.new("UIListLayout", listHolder); lhl.SortOrder = Enum.SortOrder.LayoutOrder
                for _, name2 in ipairs(options) do
                    local b = Instance.new("TextButton")
                    b.Size = UDim2.new(1, 0, 0, 28); b.BackgroundTransparency = 1; b.Text = name2
                    b.Font = Enum.Font.Gotham; b.TextSize = 13; b.TextColor3 = TXT; b.ZIndex = 6; b.Parent = listHolder
                    b.MouseButton1Click:Connect(function()
                        cur = name2; sel.Text = cur .. "  ▾"
                        open = false; listHolder.Visible = false; f.Size = UDim2.new(1, 0, 0, 44)
                        pcall(opt.Callback, cur)
                    end)
                end
                sel.MouseButton1Click:Connect(function()
                    open = not open
                    listHolder.Visible = open
                    local h = open and (#options * 28) or 0
                    listHolder.Size = UDim2.new(0.5, -14, 0, h)
                    f.Size = open and UDim2.new(1, 0, 0, 44 + h + 6) or UDim2.new(1, 0, 0, 44)
                end)
                return {}
            end

            function Tab:CreateParagraph(opt)
                local f = card(10)
                f.AutomaticSize = Enum.AutomaticSize.Y
                local lay = Instance.new("UIListLayout", f); lay.Padding = UDim.new(0, 4); lay.SortOrder = Enum.SortOrder.LayoutOrder
                local ip = Instance.new("UIPadding", f); ip.PaddingTop = UDim.new(0, 10); ip.PaddingBottom = UDim.new(0, 10); ip.PaddingLeft = UDim.new(0, 14); ip.PaddingRight = UDim.new(0, 14)
                local t = Instance.new("TextLabel")
                t.BackgroundTransparency = 1; t.Size = UDim2.new(1, 0, 0, 18); t.AutomaticSize = Enum.AutomaticSize.Y
                t.Font = Enum.Font.GothamBold; t.TextSize = 14; t.TextColor3 = TXT; t.TextXAlignment = Enum.TextXAlignment.Left
                t.TextWrapped = true; t.Text = opt.Title or ""; t.Parent = f
                local c = Instance.new("TextLabel")
                c.BackgroundTransparency = 1; c.Size = UDim2.new(1, 0, 0, 18); c.AutomaticSize = Enum.AutomaticSize.Y
                c.Font = Enum.Font.Gotham; c.TextSize = 13; c.TextColor3 = SUB; c.TextXAlignment = Enum.TextXAlignment.Left
                c.TextYAlignment = Enum.TextYAlignment.Top; c.TextWrapped = true; c.Text = opt.Content or ""; c.Parent = f
                local obj = {}
                function obj:Set(d) if d.Title then t.Text = d.Title end; if d.Content then c.Text = d.Content end end
                return obj
            end

            return Tab
        end

        return Window
    end

    function UI:Notify(o)
        local toast = Instance.new("Frame")
        toast.Size = UDim2.new(0, 300, 0, 0); toast.AutomaticSize = Enum.AutomaticSize.Y
        toast.Position = UDim2.new(1, -316, 1, -96); toast.BackgroundColor3 = BG2; toast.BorderSizePixel = 0; toast.Parent = screen
        corner(toast, 10); stroke(toast, ACCENT, 1.2)
        local ip = Instance.new("UIPadding", toast); ip.PaddingTop = UDim.new(0, 10); ip.PaddingBottom = UDim.new(0, 10); ip.PaddingLeft = UDim.new(0, 12); ip.PaddingRight = UDim.new(0, 12)
        local lay = Instance.new("UIListLayout", toast); lay.Padding = UDim.new(0, 4)
        local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Size = UDim2.new(1, 0, 0, 18); t.AutomaticSize = Enum.AutomaticSize.Y
        t.Font = Enum.Font.GothamBold; t.TextSize = 14; t.TextColor3 = TXT; t.TextXAlignment = Enum.TextXAlignment.Left; t.TextWrapped = true; t.Text = o.Title or ""; t.Parent = toast
        local c = Instance.new("TextLabel"); c.BackgroundTransparency = 1; c.Size = UDim2.new(1, 0, 0, 18); c.AutomaticSize = Enum.AutomaticSize.Y
        c.Font = Enum.Font.Gotham; c.TextSize = 13; c.TextColor3 = SUB; c.TextXAlignment = Enum.TextXAlignment.Left; c.TextWrapped = true; c.Text = o.Content or ""; c.Parent = toast
        task.delay(o.Duration or 4, function() pcall(function() toast:Destroy() end) end)
    end

    return UI
end

local function chooseUI()
    local choice = nil
    local sg = Instance.new("ScreenGui")
    sg.Name = "ZA_Chooser"; sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.DisplayOrder = 11
    sg.Parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")
    local f = Instance.new("Frame")
    f.Size = UDim2.new(0, 340, 0, 210); f.Position = UDim2.new(0.5, -170, 0.5, -105)
    f.BackgroundColor3 = Color3.fromRGB(24, 24, 32); f.BorderSizePixel = 0; f.Parent = sg
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)
    local st = Instance.new("UIStroke", f); st.Color = Color3.fromRGB(90, 120, 255); st.Thickness = 1.4; st.Transparency = 0.1
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1; title.Position = UDim2.new(0, 0, 0, 18); title.Size = UDim2.new(1, 0, 0, 26)
    title.Font = Enum.Font.GothamBold; title.TextSize = 18; title.TextColor3 = Color3.fromRGB(235, 235, 245)
    title.Text = "Survive Zombie Arena"; title.Parent = f
    local sub = Instance.new("TextLabel")
    sub.BackgroundTransparency = 1; sub.Position = UDim2.new(0, 0, 0, 46); sub.Size = UDim2.new(1, 0, 0, 20)
    sub.Font = Enum.Font.Gotham; sub.TextSize = 13; sub.TextColor3 = Color3.fromRGB(165, 165, 185)
    sub.Text = "Выбери интерфейс"; sub.Parent = f
    local function mkBtn(text, desc, y, col)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -40, 0, 50); b.Position = UDim2.new(0, 20, 0, y); b.BackgroundColor3 = col
        b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Text = text; b.Parent = f; Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        local d = Instance.new("TextLabel")
        d.BackgroundTransparency = 1; d.Size = UDim2.new(1, -16, 0, 14); d.Position = UDim2.new(0, 8, 1, -16)
        d.Font = Enum.Font.Gotham; d.TextSize = 10; d.TextColor3 = Color3.fromRGB(225, 225, 250); d.TextXAlignment = Enum.TextXAlignment.Right
        d.Text = desc; d.Parent = b
        return b
    end
    local bRay = mkBtn("Rayfield", "красивое меню (нужен интернет)", 82, Color3.fromRGB(90, 120, 255))
    local bDef = mkBtn("Default", "встроенное меню (без интернета)", 144, Color3.fromRGB(58, 58, 78))
    bRay.MouseButton1Click:Connect(function() choice = "rayfield" end)
    bDef.MouseButton1Click:Connect(function() choice = "default" end)
    repeat task.wait() until choice ~= nil
    pcall(function() sg:Destroy() end)
    return choice
end

local UILib
local uiChoice = chooseUI()
if uiChoice == "rayfield" then
    local ok, lib = pcall(function() return loadstring(game:HttpGet("https://sirius.menu/rayfield"))() end)
    if ok and type(lib) == "table" then UILib = lib end
end
if not UILib then UILib = buildNativeLib() end

local Window = UILib:CreateWindow({
    Name = "Survive Zombie Arena",
    LoadingTitle = "Survive Zombie Arena",
    LoadingSubtitle = "by sigmatik323",
    ConfigurationSaving = { Enabled = false },
})
task.defer(function()
    local parent = (gethui and gethui()) or LocalPlayer:FindFirstChild("PlayerGui")
    if parent then
        local rg = parent:FindFirstChild("Rayfield")
        if rg then rg:SetAttribute("ZA_Owner", true) end
    end
end)

local tabMain = Window:CreateTab("Основные")
local tabConfig = Window:CreateTab("Конфигурация")
local tabExtra = Window:CreateTab("Дополнительно")
local tabStats = Window:CreateTab("Статистика")

tabMain:CreateSection("Главные функции")
tabMain:CreateToggle({
    Name = "Авто-удар по зомби (K)",
    CurrentValue = false,
    Callback = function(v) state.killaura = v; if v then task.spawn(killauraLoop) end end,
})
tabMain:CreateToggle({
    Name = "Призыв зомби (R)",
    CurrentValue = false,
    Callback = function(v) state.rspam = v; if v then task.spawn(rLoop) end end,
})
tabMain:CreateToggle({
    Name = "Сбор душ зомби (P)",
    CurrentValue = false,
    Callback = function(v) state.pspam = v; if v then task.spawn(pLoop) end end,
})
tabMain:CreateToggle({
    Name = "Авто-покупка ХП",
    CurrentValue = false,
    Callback = function(v) state.hpspam = v; if v then task.spawn(hpLoop) end end,
})
tabMain:CreateSection("Цели авто-удара")
local modeNames = { ["Все сразу"] = "All", ["Ближайшие"] = "Nearest", ["Случайные"] = "Random" }
tabMain:CreateDropdown({
    Name = "Кого атаковать",
    Options = { "Все сразу", "Ближайшие", "Случайные" },
    CurrentOption = { "Все сразу" },
    Callback = function(choice)
        local o = type(choice) == "table" and choice[1] or choice
        opt.mode = modeNames[o] or "All"
    end,
})
tabMain:CreateSlider({
    Name = "Сколько целей за раз",
    Range = { 1, 20 }, Increment = 1, CurrentValue = opt.targets, Suffix = " шт",
    Callback = function(v) opt.targets = math.floor(v) end,
})

tabConfig:CreateSection("Скорость вызовов")
tabConfig:CreateSlider({
    Name = "Пауза авто-удара",
    Range = { 1, 100 }, Increment = 1, CurrentValue = 10, Suffix = " сотых сек",
    Callback = function(v) opt.speed = v / 100 end,
})
tabConfig:CreateSlider({
    Name = "Призыв зомби — вызовов в секунду",
    Range = { 1, 15 }, Increment = 1, CurrentValue = opt.rRate, Suffix = "/сек",
    Callback = function(v) opt.rRate = v end,
})
tabConfig:CreateSlider({
    Name = "Сбор душ — вызовов в секунду",
    Range = { 1, 15 }, Increment = 1, CurrentValue = opt.pRate, Suffix = "/сек",
    Callback = function(v) opt.pRate = v end,
})
tabConfig:CreateSlider({
    Name = "Покупка ХП — вызовов в секунду",
    Range = { 1, 20 }, Increment = 1, CurrentValue = opt.hpRate, Suffix = "/сек",
    Callback = function(v) opt.hpRate = v end,
})
tabConfig:CreateSection("Защита")
tabConfig:CreateSlider({
    Name = "Общий лимит запросов в секунду",
    Range = { 50, 400 }, Increment = 10, CurrentValue = opt.maxReq, Suffix = "/сек",
    Callback = function(v) opt.maxReq = v end,
})

tabExtra:CreateSection("Дополнительные функции")
tabExtra:CreateToggle({
    Name = "Noclip",
    CurrentValue = false, Callback = function(v) setNoclip(v) end,
})
tabExtra:CreateToggle({
    Name = "Убрать туман",
    CurrentValue = false, Callback = function(v) state.nofog = v; applyNoFog() end,
})
tabExtra:CreateToggle({
    Name = "Полная яркость",
    CurrentValue = false, Callback = function(v) state.fullbright = v; applyFullBright() end,
})
tabExtra:CreateToggle({
    Name = "Анти-лаг",
    CurrentValue = false, Callback = function(v) setAntiLag(v) end,
})
tabExtra:CreateSlider({
    Name = "Скорость передвижения",
    Range = { 16, 100 }, Increment = 1, CurrentValue = 16, Suffix = "",
    Callback = function(v) setWalkSpeed(v) end,
})
tabExtra:CreateSection("Очистка")
tabExtra:CreateButton({
    Name = "Выгрузить скрипт",
    Callback = function() if _G.SurviveZombieArena then _G.SurviveZombieArena.unload() end end,
})

tabStats:CreateSection("Статистика (сохраняется на ПК)")
local statPara = tabStats:CreateParagraph({ Title = "Общая статистика", Content = "..." })
local curPara = tabStats:CreateParagraph({ Title = "Валюта собрана за всё время", Content = "..." })
tabStats:CreateButton({
    Name = "Сбросить статистику",
    Callback = function()
        stats.rTotal, stats.pTotal, stats.hpTotal = 0, 0, 0
        stats.cur1Total = 0
        session.r, session.p, session.hp, session.killaura = 0, 0, 0, 0
        saveStats()
    end,
})

local function curLine(cfg, total, now)
    if cfg.path == "" then return cfg.name .. ": путь не задан" end
    return cfg.name .. ": +" .. total .. "  (сейчас " .. (now or "?") .. ")"
end
local function updateRayfieldStats()
    statPara:Set({
        Title = "Общая статистика",
        Content =
            "Зомби на карте: " .. zombieCount() ..
            "\nОружие: " .. equippedWeapon() ..
            "\nПрошло зомби: " .. maxZombieId() ..
            "\nПризыв зомби R (сессия): " .. session.r .. "  |  всего: " .. stats.rTotal ..
            "\nСбор душ P (сессия): " .. session.p .. "  |  всего: " .. stats.pTotal ..
            "\nПокупка ХП (сессия): " .. session.hp .. "  |  всего: " .. stats.hpTotal ..
            "\nУдаров авто-удара (сессия): " .. session.killaura,
    })
    curPara:Set({
        Title = "Ивентовая валюта за всё время",
        Content = curLine(CONFIG.currency1, stats.cur1Total, lastCur1),
    })
end

local hudAcc, statAcc, rayAcc = 0, 0, 0
track(RunService.Heartbeat:Connect(function(dt)
    if not ALIVE then return end
    hudAcc += dt; statAcc += dt; rayAcc += dt
    if hudAcc >= 0.2 then hudAcc = 0; updateHUD() end
    if statAcc >= 1 then
        statAcc = 0
        local v1 = resolveValue(CONFIG.currency1.path)
        if v1 then if lastCur1 and v1 > lastCur1 then stats.cur1Total += (v1 - lastCur1) end; lastCur1 = v1 end
        if state.antilag then sweepFolder() end
        saveStats()
    end
    if rayAcc >= 3 then rayAcc = 0; updateRayfieldStats() end
end))

track(UserInputService.InputBegan:Connect(function(input, gpe)
    if not ALIVE or gpe then return end
    if input.KeyCode == CONFIG.killKey then
        state.killaura = not state.killaura
        if state.killaura then task.spawn(killauraLoop) end
    elseif input.KeyCode == CONFIG.worldEnderKey then
        state.rspam = not state.rspam
        if state.rspam then task.spawn(rLoop) end
    elseif input.KeyCode == CONFIG.gearKey then
        state.pspam = not state.pspam
        if state.pspam then task.spawn(pLoop) end
    end
end))

_G.SurviveZombieArena = {
    unload = function()
        ALIVE = false
        state.killaura, state.rspam, state.pspam, state.hpspam = false, false, false, false
        setNoclip(false)
        if state.antilag then setAntiLag(false) end
        state.nofog = false; applyNoFog()
        state.fullbright = false; applyFullBright()
        saveStats()
        for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        if hud then pcall(function() hud:Destroy() end) end
        pcall(function() UILib:Destroy() end)
        _G.SurviveZombieArena = nil
    end,
}

UILib:Notify({
    Title = "Survive Zombie Arena",
    Content = "Загружено. K — авто-удар, R — призыв зомби, P — сбор душ.",
    Duration = 5,
})
