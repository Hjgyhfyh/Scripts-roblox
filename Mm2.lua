local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "tg: @sigmatik323",
   LoadingTitle = "tg: @sigmatik323",
   LoadingSubtitle = "by sigmatik323",
   ConfigurationSaving = {
      Enabled = false,
      FolderName = "Mm2_Sigmatik",
      FileName = "Mm2Config"
   },
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = true
   },
   KeySystem = false,
})

--------------------------------------------------------------------------------
-- Anti AFK
--------------------------------------------------------------------------------
local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

--------------------------------------------------------------------------------
-- Variables & Settings
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local Settings = {
    Murderer = {Enabled = false, Color = Color3.fromRGB(255, 0, 0)},
    Sheriff = {Enabled = false, Color = Color3.fromRGB(0, 0, 255)},
    Innocent = {Enabled = false, Color = Color3.fromRGB(0, 255, 0)}
}

local Roles = {
    Murderer = nil,
    Sheriff = nil
}

--------------------------------------------------------------------------------
-- UI Construction
--------------------------------------------------------------------------------
local Tab = Window:CreateTab("Visuals", 4483362458) 

local Section = Tab:CreateSection("ESP Roles")

-- Murderer
Tab:CreateToggle({
   Name = "ESP Murderer",
   CurrentValue = false,
   Flag = "ESPMurderer",
   Callback = function(Value)
       Settings.Murderer.Enabled = Value
   end,
})

Tab:CreateColorPicker({
    Name = "Murderer Color",
    Color = Settings.Murderer.Color,
    Flag = "ColorMurderer",
    Callback = function(Value)
        Settings.Murderer.Color = Value
    end
})

-- Sheriff
Tab:CreateToggle({
   Name = "ESP Sheriff",
   CurrentValue = false,
   Flag = "ESPSheriff",
   Callback = function(Value)
       Settings.Sheriff.Enabled = Value
   end,
})

Tab:CreateColorPicker({
    Name = "Sheriff Color",
    Color = Settings.Sheriff.Color,
    Flag = "ColorSheriff",
    Callback = function(Value)
        Settings.Sheriff.Color = Value
    end
})

-- Innocent
Tab:CreateToggle({
   Name = "ESP Innocent",
   CurrentValue = false,
   Flag = "ESPInnocent",
   Callback = function(Value)
       Settings.Innocent.Enabled = Value
   end,
})

Tab:CreateColorPicker({
    Name = "Innocent Color",
    Color = Settings.Innocent.Color,
    Flag = "ColorInnocent",
    Callback = function(Value)
        Settings.Innocent.Color = Value
    end
})

--------------------------------------------------------------------------------
-- Logic
--------------------------------------------------------------------------------

-- Checks for weapon by strictly or loosely name
local function HasWeapon(container, names)
    if not container then return false end
    for _, child in pairs(container:GetChildren()) do
        if child:IsA("Tool") then
             local n = string.lower(child.Name)
             for _, name in ipairs(names) do
                 if n == string.lower(name) then return true end
             end
        end
    end
    return false
end

local function DetermineRole(player)
    if not player then return "Innocent" end
    if player == Roles.Murderer then return "Murderer" end
    if player == Roles.Sheriff then return "Sheriff" end
    return "Innocent"
end

local function UpdateHighlights(player, role, config)
    if not player.Character then return end
    
    -- 1. Highlight
    local hl = player.Character:FindFirstChild("SigmatikHL")
    
    if config.Enabled then
        if not hl then
            hl = Instance.new("Highlight")
            hl.Name = "SigmatikHL"
            hl.FillTransparency = 0.5
            hl.OutlineTransparency = 0
            hl.Parent = player.Character
        end
        hl.FillColor = config.Color
        hl.OutlineColor = config.Color
        hl.Enabled = true
    else
        if hl then hl:Destroy() end -- Destroying is safer to ensure it's gone
    end

    -- 2. Billboard ESP (Text)
    local head = player.Character:FindFirstChild("Head")
    if head then
        local bg = head:FindFirstChild("SigmatikESP")
        if config.Enabled then
            if not bg then
                bg = Instance.new("BillboardGui")
                bg.Name = "SigmatikESP"
                bg.Size = UDim2.new(0, 100, 0, 50)
                bg.StudsOffset = Vector3.new(0, 3, 0)
                bg.AlwaysOnTop = true
                bg.Parent = head
                
                local lbl = Instance.new("TextLabel")
                lbl.Name = "Label"
                lbl.Size = UDim2.new(1,0,1,0)
                lbl.BackgroundTransparency = 1
                lbl.TextStrokeTransparency = 0
                lbl.TextColor3 = config.Color
                lbl.Font = Enum.Font.GothamBold
                lbl.TextSize = 14
                lbl.Parent = bg
            end
            
            local lbl = bg:FindFirstChild("Label")
            if lbl then
                lbl.Text = role .. "\n" .. player.Name
                lbl.TextColor3 = config.Color
            end
            bg.Enabled = true
        else
            if bg then bg:Destroy() end
        end
    end
end


RunService.RenderStepped:Connect(function()
    -- Scan for Roles
    -- We scan continuously because roles can change (droppped gun, etc)
    local foundMurderer = nil
    local foundSheriff = nil

    for _, p in pairs(Players:GetPlayers()) do
        if p.Character then
            -- Check Character and Backpack
            if HasWeapon(p.Character, {"Knife", "Dagger"}) or HasWeapon(p:FindFirstChild("Backpack"), {"Knife", "Dagger"}) then
                foundMurderer = p
            end
            if HasWeapon(p.Character, {"Gun", "Revolver", "Pistol"}) or HasWeapon(p:FindFirstChild("Backpack"), {"Gun", "Revolver", "Pistol"}) then
                foundSheriff = p
            end
        end
    end
    
    Roles.Murderer = foundMurderer
    Roles.Sheriff = foundSheriff

    -- Apply ESP
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local role = DetermineRole(p)
            local config = Settings[role]
            UpdateHighlights(p, role, config)
        end
    end
end)
