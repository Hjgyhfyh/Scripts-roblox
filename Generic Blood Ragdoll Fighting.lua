local Sigmatik = loadstring(game:HttpGet('https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/source.lua.txt'))()

local Window = Sigmatik:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    Theme = "Red",
    ConfigurationSaving = {
        Enabled = false,
        FolderName = nil,
        FileName = "GBRF"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = false
    },
    KeySystem = false
})

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local UserInputService     = game:GetService("UserInputService")
local Lighting             = game:GetService("Lighting")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Workspace            = game:GetService("Workspace")
local VirtualUser          = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Remotes = {
    meleeHit             = ReplicatedStorage.Assets.Remotes:WaitForChild("meleeHit"),
    MeleeHitVerification = ReplicatedStorage.Assets.Remotes:WaitForChild("MeleeHitVerification"),
    EquipWeapon          = ReplicatedStorage.Assets.Remotes:WaitForChild("EquipWeapon"),
    UnEquipWeapon        = ReplicatedStorage.Assets.Remotes:WaitForChild("UnEquipWeapon"),
    KickHit              = ReplicatedStorage.Assets.Remotes:FindFirstChild("KickHit"),
}

local function getCharacter()
    return Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild(LocalPlayer.Name)
        or LocalPlayer.Character
end

local function getRoot()
    local char = getCharacter()
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

local function getEquippedTool()
    local char = getCharacter()
    if not char then return nil end
    return char:FindFirstChildOfClass("Tool") or char:FindFirstChild("Katana")
end

local function distance(a, b)
    if not a or not b then return math.huge end
    return (a - b).Magnitude
end

-- ============================================================
-- State
-- ============================================================

local State = {
    autoAttack         = false,
    spamCount          = 50,
    hitRange           = 20,
    attackInterval     = 0.05,
    targetPlayers      = false,
    targetDummies      = true,

    autoFarm           = false,
    masteryGoal        = 1000,
    autoTeleportFarm   = false,
    autoReequip        = false,

    playerEsp          = false,
    playerEspColor     = Color3.fromRGB(255, 60, 60),
    dummyEsp           = false,
    dummyEspColor      = Color3.fromRGB(255, 200, 0),
    showDistance       = false,

    fly                = false,
    flySpeed           = 60,
    walkSpeed          = 16,
    jumpPower          = 50,
    noclip             = false,
    fullbright         = false,
    noFog              = false,
    antiAfk            = false,

    showNotifications  = true,
}

local Connections = {}
local EspObjects  = {}

-- ============================================================
-- Helpers
-- ============================================================

local function notify(title, content, duration)
    if not State.showNotifications then return end
    pcall(function()
        Sigmatik:Notify({ Title = title, Content = content, Duration = duration or 3 })
    end)
end

local function pickFreshTargets(maxCount)
    local root = getRoot()
    if not root then return {} end
    local origin = root.Position
    local list = {}
    local charsFolder = Workspace:FindFirstChild("Characters")
    if not charsFolder then return list end
    for _, model in ipairs(charsFolder:GetChildren()) do
        if model ~= getCharacter() then
            local hum = model:FindFirstChildOfClass("Humanoid")
            local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
            if hum and hrp and hum.Health > 0 then
                local isDummy = model.Name:match("^Dummy") ~= nil
                local isPlayer = Players:FindFirstChild(model.Name) ~= nil
                local include = (isDummy and State.targetDummies) or (isPlayer and State.targetPlayers)
                if include then
                    local d = (hrp.Position - origin).Magnitude
                    if d <= State.hitRange then
                        table.insert(list, { model = model, hum = hum, hrp = hrp, dist = d })
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    if maxCount then
        while #list > maxCount do table.remove(list) end
    end
    return list
end

local function fireMelee(target)
    local tool = getEquippedTool()
    if not tool or not target or not target.hum or not target.hrp then return end
    local part = target.model:FindFirstChild("Torso") or target.hrp
    for i = 1, State.spamCount do
        pcall(function() Remotes.MeleeHitVerification:FireServer(tool, part, ((i-1) % 4) + 1) end)
        pcall(function() Remotes.meleeHit:FireServer(tool, target.hum, ((i-1) % 4) + 1) end)
    end
end

local function findFreshDummyAnywhere()
    local charsFolder = Workspace:FindFirstChild("Characters")
    if not charsFolder then return nil end
    local best, bestDist = nil, math.huge
    local root = getRoot()
    local origin = root and root.Position or Vector3.new()
    for _, model in ipairs(charsFolder:GetChildren()) do
        if model.Name:match("^Dummy") then
            local hum = model:FindFirstChildOfClass("Humanoid")
            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health == hum.MaxHealth then
                local d = (hrp.Position - origin).Magnitude
                if d < bestDist then
                    best, bestDist = model, d
                end
            end
        end
    end
    return best
end

-- ============================================================
-- 🩸 Combat Tab
-- ============================================================

local CombatTab = Window:CreateTab("🩸 Combat", 4483362458)
CombatTab:CreateSection("⚔️ Damage Exploits")

CombatTab:CreateToggle({
    Name = "Auto Attack Nearest",
    CurrentValue = false,
    Flag = "AutoAttack",
    Callback = function(v)
        State.autoAttack = v
        if v then
            notify("Combat", "Auto Attack enabled", 2)
        end
    end
})

CombatTab:CreateButton({
    Name = "🗡 Kill Closest (One-Shot)",
    Callback = function()
        local list = pickFreshTargets(1)
        if list[1] then
            fireMelee(list[1])
            notify("One-Shot", list[1].model.Name .. " (" .. math.floor(list[1].dist) .. " studs)", 2)
        else
            notify("One-Shot", "No target in range", 2)
        end
    end
})

CombatTab:CreateButton({
    Name = "💀 Kill All In Range",
    Callback = function()
        local list = pickFreshTargets()
        for _, t in ipairs(list) do fireMelee(t) end
        notify("Kill All", "Hit " .. #list .. " targets", 2)
    end
})

CombatTab:CreateSlider({
    Name = "Spam Hits Per Tick",
    Min = 1,
    Max = 200,
    Increment = 1,
    Suffix = "hits",
    CurrentValue = 50,
    Flag = "SpamCount",
    Callback = function(v) State.spamCount = v end
})

CombatTab:CreateSlider({
    Name = "Hit Range",
    Min = 5,
    Max = 25,
    Increment = 1,
    Suffix = "studs",
    CurrentValue = 20,
    Flag = "HitRange",
    Callback = function(v) State.hitRange = v end
})

CombatTab:CreateSlider({
    Name = "Attack Interval",
    Min = 0.05,
    Max = 2,
    Increment = 0.05,
    Suffix = "sec",
    CurrentValue = 0.05,
    Flag = "AttackInterval",
    Callback = function(v) State.attackInterval = v end
})

CombatTab:CreateSection("🎯 Targeting")

CombatTab:CreateToggle({
    Name = "Target Dummies",
    CurrentValue = true,
    Flag = "TargetDummies",
    Callback = function(v) State.targetDummies = v end
})

CombatTab:CreateToggle({
    Name = "Target Players (PvP)",
    CurrentValue = false,
    Flag = "TargetPlayers",
    Callback = function(v) State.targetPlayers = v end
})

-- ============================================================
-- 🌾 Farm Tab
-- ============================================================

local FarmTab = Window:CreateTab("🌾 Farm", 4483362458)
FarmTab:CreateSection("🏆 Mastery Grind")

local masteryLabel = FarmTab:CreateLabel("Mastery: ?")

local function refreshMasteryLabel()
    local mk = LocalPlayer:FindFirstChild("MasteryKills")
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local dk = ls and ls:FindFirstChild("Dummy Kills")
    local pk = ls and ls:FindFirstChild("Player Kills")
    local text = string.format("Mastery: %s | Dummy: %s | Player: %s",
        tostring(mk and mk.Value or "?"),
        tostring(dk and dk.Value or "?"),
        tostring(pk and pk.Value or "?"))
    pcall(function() masteryLabel:Set(text) end)
end

FarmTab:CreateToggle({
    Name = "Auto Farm Mastery",
    CurrentValue = false,
    Flag = "AutoFarm",
    Callback = function(v)
        State.autoFarm = v
        if v then notify("Farm", "Auto-farm started (goal " .. State.masteryGoal .. ")", 2) end
    end
})

FarmTab:CreateToggle({
    Name = "Auto Teleport To Fresh Dummy",
    CurrentValue = false,
    Flag = "AutoTeleportFarm",
    Callback = function(v) State.autoTeleportFarm = v end
})

FarmTab:CreateToggle({
    Name = "Auto Re-Equip Weapon",
    CurrentValue = false,
    Flag = "AutoReequip",
    Callback = function(v) State.autoReequip = v end
})

FarmTab:CreateSlider({
    Name = "Mastery Goal",
    Min = 0,
    Max = 1500,
    Increment = 25,
    Suffix = "kills",
    CurrentValue = 1000,
    Flag = "MasteryGoal",
    Callback = function(v) State.masteryGoal = v end
})

FarmTab:CreateButton({
    Name = "🔁 Refresh Mastery Display",
    Callback = function() refreshMasteryLabel() end
})

FarmTab:CreateButton({
    Name = "📦 Equip Katana From Backpack",
    Callback = function()
        local kat = LocalPlayer.Backpack:FindFirstChild("Katana")
                 or LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
        if kat then
            local char = getCharacter()
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then hum:EquipTool(kat) end
            task.spawn(function() pcall(function() Remotes.EquipWeapon:InvokeServer(kat) end) end)
            notify("Equip", "Equipped " .. kat.Name, 2)
        else
            notify("Equip", "No tool in backpack", 2)
        end
    end
})

-- ============================================================
-- 👁 ESP Tab
-- ============================================================

local EspTab = Window:CreateTab("👁 ESP", 4483362458)
EspTab:CreateSection("💀 Player ESP")

EspTab:CreateToggle({
    Name = "Player ESP",
    CurrentValue = false,
    Flag = "PlayerESP",
    Callback = function(v) State.playerEsp = v end
})

EspTab:CreateColorPicker({
    Name = "Player ESP Color",
    Color = State.playerEspColor,
    Flag = "PlayerESPColor",
    Callback = function(c) State.playerEspColor = c end
})

EspTab:CreateSection("🤖 Dummy ESP")

EspTab:CreateToggle({
    Name = "Dummy ESP",
    CurrentValue = false,
    Flag = "DummyESP",
    Callback = function(v) State.dummyEsp = v end
})

EspTab:CreateColorPicker({
    Name = "Dummy ESP Color",
    Color = State.dummyEspColor,
    Flag = "DummyESPColor",
    Callback = function(c) State.dummyEspColor = c end
})

EspTab:CreateToggle({
    Name = "Show Distance",
    CurrentValue = false,
    Flag = "ShowDistance",
    Callback = function(v) State.showDistance = v end
})

-- ============================================================
-- 🏃 Movement Tab
-- ============================================================

local MoveTab = Window:CreateTab("🏃 Movement", 4483362458)
MoveTab:CreateSection("✈️ Flight")

MoveTab:CreateToggle({
    Name = "Fly",
    CurrentValue = false,
    Flag = "Fly",
    Callback = function(v) State.fly = v end
})

MoveTab:CreateSlider({
    Name = "Fly Speed",
    Min = 20,
    Max = 300,
    Increment = 5,
    Suffix = "speed",
    CurrentValue = 60,
    Flag = "FlySpeed",
    Callback = function(v) State.flySpeed = v end
})

MoveTab:CreateSection("🦘 Character")

MoveTab:CreateSlider({
    Name = "Walk Speed",
    Min = 16,
    Max = 200,
    Increment = 1,
    Suffix = "speed",
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Callback = function(v)
        State.walkSpeed = v
        local char = getCharacter() or LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = v end
    end
})

MoveTab:CreateSlider({
    Name = "Jump Power",
    Min = 50,
    Max = 500,
    Increment = 10,
    Suffix = "power",
    CurrentValue = 50,
    Flag = "JumpPower",
    Callback = function(v)
        State.jumpPower = v
        local char = getCharacter() or LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.UseJumpPower = true
            hum.JumpPower = v
        end
    end
})

MoveTab:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Flag = "Noclip",
    Callback = function(v) State.noclip = v end
})

MoveTab:CreateSection("🔆 Visuals")

MoveTab:CreateToggle({
    Name = "Fullbright",
    CurrentValue = false,
    Flag = "Fullbright",
    Callback = function(v)
        State.fullbright = v
        if v then
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(180, 180, 180)
        else
            Lighting.Brightness = 1
            Lighting.GlobalShadows = true
            Lighting.Ambient = Color3.fromRGB(0, 0, 0)
        end
    end
})

MoveTab:CreateToggle({
    Name = "No Fog",
    CurrentValue = false,
    Flag = "NoFog",
    Callback = function(v)
        State.noFog = v
        if v then
            Lighting.FogEnd = 100000
            Lighting.FogStart = 100000
        else
            Lighting.FogEnd = 1000
            Lighting.FogStart = 0
        end
    end
})

MoveTab:CreateSection("📍 Utility")

MoveTab:CreateKeybind({
    Name = "TP To Mouse",
    CurrentKeybind = "None",
    HoldToInteract = false,
    Flag = "TPClick",
    Callback = function()
        local mouse = LocalPlayer:GetMouse()
        local root = getRoot()
        if root and mouse.Hit then
            root.CFrame = CFrame.new(mouse.Hit.p + Vector3.new(0, 3, 0))
        end
    end
})

MoveTab:CreateToggle({
    Name = "Anti AFK",
    CurrentValue = false,
    Flag = "AntiAFK",
    Callback = function(v) State.antiAfk = v end
})

-- ============================================================
-- ⚙️ Misc Tab
-- ============================================================

local MiscTab = Window:CreateTab("⚙️ Misc", 4483362458)
MiscTab:CreateSection("🔔 Settings")

MiscTab:CreateToggle({
    Name = "Show Notifications",
    CurrentValue = true,
    Flag = "ShowNotifications",
    Callback = function(v) State.showNotifications = v end
})

MiscTab:CreateButton({
    Name = "🛑 Stop All Loops",
    Callback = function()
        State.autoAttack       = false
        State.autoFarm         = false
        State.autoTeleportFarm = false
        State.autoReequip      = false
        State.fly              = false
        State.noclip           = false
        State.antiAfk          = false
        notify("Stop", "All loops stopped", 2)
    end
})

MiscTab:CreateLabel("F-001 Critical | F-003 + F-004 High")
MiscTab:CreateLabel("by @sigmatik323")

-- ============================================================
-- Loops
-- ============================================================

-- Auto Attack
task.spawn(function()
    while true do
        if State.autoAttack then
            local list = pickFreshTargets()
            for _, t in ipairs(list) do fireMelee(t) end
        end
        task.wait(State.attackInterval)
    end
end)

-- Auto Farm
task.spawn(function()
    while true do
        if State.autoFarm then
            local mk = LocalPlayer:FindFirstChild("MasteryKills")
            if mk and mk.Value < State.masteryGoal then
                local target = nil
                if State.autoTeleportFarm then
                    local dummy = findFreshDummyAnywhere()
                    if dummy then
                        local dh = dummy:FindFirstChild("HumanoidRootPart")
                        local root = getRoot()
                        if dh and root then
                            root.CFrame = dh.CFrame * CFrame.new(0, 0, 4)
                            task.wait(0.2)
                        end
                    end
                end
                local list = pickFreshTargets(1)
                target = list[1]
                if target then fireMelee(target) end
            else
                State.autoFarm = false
                notify("Farm", "Mastery goal reached", 4)
            end
        end
        task.wait(0.3)
    end
end)

-- Auto Re-Equip
task.spawn(function()
    while true do
        if State.autoReequip then
            local equipped = getEquippedTool()
            if not equipped then
                local kat = LocalPlayer.Backpack:FindFirstChild("Katana")
                          or LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
                if kat then
                    pcall(function()
                        local char = getCharacter()
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if hum then hum:EquipTool(kat) end
                    end)
                end
            end
        end
        task.wait(1)
    end
end)

-- Mastery label refresh
task.spawn(function()
    while true do
        refreshMasteryLabel()
        task.wait(2)
    end
end)

-- Fly
local flyConn, flyBV, flyBG
local function startFly()
    local char = getCharacter() or LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = root
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    flyBG.P = 9000
    flyBG.D = 200
    flyBG.Parent = root
    flyConn = RunService.Heartbeat:Connect(function()
        if not State.fly then return end
        local cam = Workspace.CurrentCamera
        local move = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0, 1, 0) end
        flyBV.Velocity = move * State.flySpeed
        flyBG.CFrame = cam.CFrame
    end)
end
local function stopFly()
    if flyConn then flyConn:Disconnect() flyConn = nil end
    if flyBV  then flyBV:Destroy()  flyBV  = nil end
    if flyBG  then flyBG:Destroy()  flyBG  = nil end
end

task.spawn(function()
    while true do
        if State.fly and not flyConn then
            startFly()
        elseif not State.fly and flyConn then
            stopFly()
        end
        task.wait(0.2)
    end
end)

-- Noclip
RunService.Stepped:Connect(function()
    if State.noclip then
        local char = getCharacter() or LocalPlayer.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then
                    p.CanCollide = false
                end
            end
        end
    end
end)

-- Anti AFK
LocalPlayer.Idled:Connect(function()
    if State.antiAfk then
        pcall(function() VirtualUser:CaptureController() end)
        pcall(function() VirtualUser:ClickButton2(Vector2.new()) end)
    end
end)

-- ESP
local function clearEsp(model)
    local data = EspObjects[model]
    if data then
        if data.box then data.box:Destroy() end
        if data.label then data.label:Destroy() end
        EspObjects[model] = nil
    end
end

local function ensureEsp(model, color)
    local data = EspObjects[model]
    local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    if not hrp then clearEsp(model) return end
    if not data then
        local box = Instance.new("BoxHandleAdornment")
        box.Name = "GBRF_ESP"
        box.Adornee = hrp
        box.AlwaysOnTop = true
        box.ZIndex = 10
        box.Size = Vector3.new(4, 6, 2)
        box.Transparency = 0.4
        box.Color3 = color
        box.Parent = hrp
        local bb = Instance.new("BillboardGui")
        bb.Adornee = hrp
        bb.Size = UDim2.new(0, 120, 0, 40)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.fromScale(1, 1)
        tl.BackgroundTransparency = 1
        tl.TextColor3 = color
        tl.TextStrokeTransparency = 0.4
        tl.TextScaled = true
        tl.Font = Enum.Font.GothamBold
        tl.Parent = bb
        bb.Parent = hrp
        EspObjects[model] = { box = box, label = bb, text = tl }
        data = EspObjects[model]
    end
    data.box.Color3 = color
    data.text.TextColor3 = color
    local hum = model:FindFirstChildOfClass("Humanoid")
    local hp = hum and math.floor(hum.Health) or 0
    local root = getRoot()
    local distText = ""
    if State.showDistance and root then
        distText = string.format(" | %d s", (hrp.Position - root.Position).Magnitude)
    end
    data.text.Text = string.format("%s [%d HP]%s", model.Name, hp, distText)
end

RunService.RenderStepped:Connect(function()
    local charsFolder = Workspace:FindFirstChild("Characters")
    if not charsFolder then return end
    local seen = {}
    for _, model in ipairs(charsFolder:GetChildren()) do
        if model ~= getCharacter() then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local isDummy = model.Name:match("^Dummy") ~= nil
                local isPlayer = Players:FindFirstChild(model.Name) ~= nil
                local color = nil
                if isPlayer and State.playerEsp then color = State.playerEspColor end
                if isDummy and State.dummyEsp  then color = State.dummyEspColor end
                if color then
                    ensureEsp(model, color)
                    seen[model] = true
                end
            end
        end
    end
    for model in pairs(EspObjects) do
        if not seen[model] or not model.Parent then
            clearEsp(model)
        end
    end
end)

notify("GBRF", "tg: @sigmatik323 loaded", 4)
