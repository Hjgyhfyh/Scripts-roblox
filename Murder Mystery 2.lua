-- Murder Mystery 2 Script
-- by @sigmatik323
-- tg: @sigmatik323

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Anti AFK
--------------------------------------------------------------------------------
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

--------------------------------------------------------------------------------
-- GUI Construction (Custom Beautiful UI)
--------------------------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MM2_Sigmatik_GUI"
ScreenGui.ResetOnSpawn = false
-- Use Sibling only if needed, usually Global is fine too, but Sibling is standard for UIs
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling 

pcall(function()
    if syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = game:GetService("CoreGui")
    elseif gethui then
        ScreenGui.Parent = gethui()
    else
        ScreenGui.Parent = game:GetService("CoreGui")
    end
end)
if not ScreenGui.Parent then ScreenGui.Parent = game:GetService("CoreGui") end

-- Constants & Theme
local THEME = {
    Background = Color3.fromRGB(20, 20, 25),
    Header = Color3.fromRGB(30, 30, 35),
    Accent = Color3.fromRGB(0, 120, 215),
    Text = Color3.fromRGB(240, 240, 240),
    TextDim = Color3.fromRGB(160, 160, 160),
    Button = Color3.fromRGB(40, 40, 45),
    ButtonHover = Color3.fromRGB(50, 50, 55),
    Section = Color3.fromRGB(25, 25, 30)
}

-- Main Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 480, 0, 350) -- Slightly wider
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -175)
MainFrame.BackgroundColor3 = THEME.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = MainFrame

-- Shadow (Optional, wrapped in pcall to prevent asset errors)
pcall(function()
    local Shadow = Instance.new("ImageLabel")
    Shadow.Name = "Shadow"
    Shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    Shadow.BackgroundTransparency = 1
    Shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
    Shadow.Size = UDim2.new(1, 40, 1, 40)
    Shadow.ZIndex = 0
    Shadow.Image = "rbxassetid://6015897843"
    Shadow.ImageColor3 = Color3.new(0, 0, 0)
    Shadow.ImageTransparency = 0.5
    Shadow.ScaleType = Enum.ScaleType.Slice
    Shadow.SliceCenter = Rect.new(49, 49, 450, 450)
    Shadow.Parent = MainFrame
end)

-- Header
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 40)
Header.BackgroundColor3 = THEME.Header
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 8)
HeaderCorner.Parent = Header

local HeaderFix = Instance.new("Frame") -- Covers bottom corners of header
HeaderFix.Size = UDim2.new(1, 0, 0, 10)
HeaderFix.Position = UDim2.new(0, 0, 1, -10)
HeaderFix.BackgroundColor3 = THEME.Header
HeaderFix.BorderSizePixel = 0
HeaderFix.Parent = Header

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Text = "tg: @sigmatik323"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextColor3 = THEME.Text
Title.Size = UDim2.new(1, -20, 1, 0)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent = Header

local SubTitle = Instance.new("TextLabel")
SubTitle.Name = "SubTitle"
SubTitle.Text = "by sigmatik323"
SubTitle.Font = Enum.Font.Gotham
SubTitle.TextSize = 12
SubTitle.TextColor3 = THEME.TextDim
SubTitle.Size = UDim2.new(0, 100, 1, 0)
SubTitle.Position = UDim2.new(1, -110, 0, 0)
SubTitle.TextXAlignment = Enum.TextXAlignment.Right
SubTitle.BackgroundTransparency = 1
SubTitle.Parent = Header

-- Content Container (Tabs)
local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Size = UDim2.new(1, 0, 1, -40)
Content.Position = UDim2.new(0, 0, 0, 40)
Content.BackgroundTransparency = 1
Content.Parent = MainFrame

-- Tab System
local TabButtons = Instance.new("Frame")
TabButtons.Name = "TabButtons"
TabButtons.Size = UDim2.new(0, 130, 1, -20)
TabButtons.Position = UDim2.new(0, 10, 0, 10)
TabButtons.BackgroundColor3 = THEME.Section
TabButtons.Parent = Content

local TabCorner = Instance.new("UICorner")
TabCorner.CornerRadius = UDim.new(0, 6)
TabCorner.Parent = TabButtons

local TabListLayout = Instance.new("UIListLayout")
TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabListLayout.Padding = UDim.new(0, 5)
TabListLayout.Parent = TabButtons

local TabPages = Instance.new("Frame")
TabPages.Name = "TabPages"
TabPages.Size = UDim2.new(1, -155, 1, -20)
TabPages.Position = UDim2.new(0, 150, 0, 10)
TabPages.BackgroundTransparency = 1
TabPages.Parent = Content

-- Custom Engine
local CurrentTab = nil

local function CreateTab(name, icon)
    local TabPage = Instance.new("ScrollingFrame")
    TabPage.Name = name .. "_Page"
    TabPage.Size = UDim2.new(1, 0, 1, 0)
    TabPage.BackgroundTransparency = 1
    TabPage.ScrollBarThickness = 2
    TabPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
    TabPage.CanvasSize = UDim2.new(0, 0, 0, 0)
    TabPage.Visible = false
    TabPage.Parent = TabPages
    
    local List = Instance.new("UIListLayout")
    List.SortOrder = Enum.SortOrder.LayoutOrder
    List.Padding = UDim.new(0, 8)
    List.Parent = TabPage
    
    local TabBtn = Instance.new("TextButton")
    TabBtn.Name = name .. "_Btn"
    TabBtn.Size = UDim2.new(1, 0, 0, 35)
    TabBtn.BackgroundColor3 = THEME.Background
    TabBtn.BackgroundTransparency = 1 -- Start transparent to show list color or handle click
    TabBtn.Text = "  " .. icon .. " " .. name
    TabBtn.Font = Enum.Font.GothamSemiBold
    TabBtn.TextSize = 14
    TabBtn.TextColor3 = THEME.TextDim
    TabBtn.TextXAlignment = Enum.TextXAlignment.Left
    TabBtn.AutoButtonColor = false
    TabBtn.Parent = TabButtons
    
    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 6)
    BtnCorner.Parent = TabBtn
    
    TabBtn.MouseButton1Click:Connect(function()
        if CurrentTab then
            CurrentTab.Btn.TextColor3 = THEME.TextDim
            CurrentTab.Btn.BackgroundColor3 = THEME.Background
            CurrentTab.Btn.BackgroundTransparency = 1
            CurrentTab.Page.Visible = false
        end
        
        CurrentTab = {Btn = TabBtn, Page = TabPage}
        TabBtn.BackgroundTransparency = 0
        TabBtn.BackgroundColor3 = THEME.Accent
        TabBtn.TextColor3 = THEME.Text
        TabPage.Visible = true
    end)
    
    -- Select first tab by default
    if not CurrentTab then
        CurrentTab = {Btn = TabBtn, Page = TabPage}
        TabBtn.BackgroundTransparency = 0
        TabBtn.BackgroundColor3 = THEME.Accent
        TabBtn.TextColor3 = THEME.Text
        TabPage.Visible = true
    end
    
    return TabPage
end

local function CreateButton(parent, text, callback)
    local Btn = Instance.new("TextButton")
    Btn.Name = text
    Btn.Size = UDim2.new(1, 0, 0, 35)
    Btn.BackgroundColor3 = THEME.Button
    Btn.Text = text
    Btn.Font = Enum.Font.GothamSemiBold
    Btn.TextSize = 14
    Btn.TextColor3 = THEME.Text
    Btn.Parent = parent
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Btn
    
    Btn.MouseButton1Click:Connect(function()
        local oldColor = Btn.BackgroundColor3
        Btn.BackgroundColor3 = THEME.ButtonHover
        callback()
        task.wait(0.1)
        Btn.BackgroundColor3 = oldColor
    end)
    return Btn
end

local function CreateToggle(parent, text, default, callback)
    local Frame = Instance.new("Frame")
    Frame.Name = text
    Frame.Size = UDim2.new(1, 0, 0, 35)
    Frame.BackgroundColor3 = THEME.Button
    Frame.Parent = parent
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Frame
    
    local Label = Instance.new("TextLabel")
    Label.Text = text
    Label.Size = UDim2.new(0.8, 0, 1, 0)
    Label.Position = UDim2.new(0, 10, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Font = Enum.Font.Gotham
    Label.TextSize = 14
    Label.TextColor3 = THEME.Text
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame
    
    local Indicator = Instance.new("Frame")
    Indicator.Size = UDim2.new(0, 20, 0, 20)
    Indicator.Position = UDim2.new(1, -30, 0.5, -10)
    Indicator.BackgroundColor3 = default and THEME.Accent or Color3.fromRGB(60,60,60)
    Indicator.Parent = Frame
    
    local IndCorner = Instance.new("UICorner")
    IndCorner.CornerRadius = UDim.new(0, 4)
    IndCorner.Parent = Indicator
    
    local Toggled = default
    
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 1, 0)
    Btn.BackgroundTransparency = 1
    Btn.Text = ""
    Btn.Parent = Frame
    
    Btn.MouseButton1Click:Connect(function()
        Toggled = not Toggled
        Indicator.BackgroundColor3 = Toggled and THEME.Accent or Color3.fromRGB(60,60,60)
        callback(Toggled)
    end)
    
    return Frame
end

local function CreateColorSlider(parent, text, defaultColor, callback)
    local Frame = Instance.new("Frame")
    Frame.Name = text .. "_ColorCfg"
    Frame.Size = UDim2.new(1, 0, 0, 95)
    Frame.BackgroundColor3 = THEME.Section
    Frame.Parent = parent
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Frame
    
    local Label = Instance.new("TextLabel")
    Label.Text = text .. " Color"
    Label.Size = UDim2.new(1, -20, 0, 25)
    Label.Position = UDim2.new(0, 10, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Font = Enum.Font.GothamBold
    Label.TextColor3 = THEME.Text
    Label.TextSize = 13
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame
    
    local CurrentColor = defaultColor
    local R, G, B = defaultColor.R, defaultColor.G, defaultColor.B
    
    local Preview = Instance.new("Frame")
    Preview.Size = UDim2.new(0, 25, 0, 25)
    Preview.Position = UDim2.new(1, -35, 0, 0)
    Preview.BackgroundColor3 = CurrentColor
    Preview.BorderSizePixel = 0
    Preview.Parent = Frame
    
    local PreviewCorner = Instance.new("UICorner")
    PreviewCorner.CornerRadius = UDim.new(0, 4)
    PreviewCorner.Parent = Preview
    
    local function Update()
        CurrentColor = Color3.new(R, G, B)
        Preview.BackgroundColor3 = CurrentColor
        callback(CurrentColor)
    end
    
    local function CreateSlider(yPos, color, initialVal, updateVal)
        local SlideBg = Instance.new("Frame")
        SlideBg.Size = UDim2.new(1, -20, 0, 6)
        SlideBg.Position = UDim2.new(0, 10, 0, yPos)
        SlideBg.BackgroundColor3 = Color3.fromRGB(50,50,50)
        SlideBg.BorderSizePixel = 0
        SlideBg.Parent = Frame
        
        local Corner = Instance.new("UICorner")
        Corner.CornerRadius = UDim.new(1, 0)
        Corner.Parent = SlideBg
        
        local Fill = Instance.new("Frame")
        Fill.Size = UDim2.new(initialVal, 0, 1, 0)
        Fill.BackgroundColor3 = color
        Fill.BorderSizePixel = 0
        Fill.Parent = SlideBg
        
        local FillCorner = Instance.new("UICorner")
        FillCorner.CornerRadius = UDim.new(1, 0)
        FillCorner.Parent = Fill
        
        local Trigger = Instance.new("TextButton")
        Trigger.Size = UDim2.new(1, 0, 2, 0)
        Trigger.Position = UDim2.new(0, 0, -0.5, 0)
        Trigger.BackgroundTransparency = 1
        Trigger.Text = ""
        Trigger.Parent = SlideBg
        
        local Dragging = false
        Trigger.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                Dragging = true
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                Dragging = false
            end
        end)
        
        -- Use a connection to RenderStepped or InputChanged on Service for reliability
        UserInputService.InputChanged:Connect(function(input)
            if Dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local relativeX = math.clamp(input.Position.X - SlideBg.AbsolutePosition.X, 0, SlideBg.AbsoluteSize.X)
                local pct = relativeX / SlideBg.AbsoluteSize.X
                Fill.Size = UDim2.new(pct, 0, 1, 0)
                updateVal(pct)
                Update()
            end
        end)
    end
    
    CreateSlider(35, Color3.fromRGB(255,100,100), R, function(v) R = v end)
    CreateSlider(55, Color3.fromRGB(100,255,100), G, function(v) G = v end)
    CreateSlider(75, Color3.fromRGB(100,100,255), B, function(v) B = v end)
end

local function CreateInput(parent, placeholder, callback)
    local Box = Instance.new("TextBox")
    Box.Name = placeholder
    Box.Size = UDim2.new(1, 0, 0, 35)
    Box.BackgroundColor3 = THEME.Button
    Box.PlaceholderText = placeholder
    Box.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
    Box.Text = ""
    Box.Font = Enum.Font.Gotham
    Box.TextSize = 14
    Box.TextColor3 = THEME.Text
    Box.Parent = parent
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Box
    
    Box.FocusLost:Connect(function()
        callback(Box.Text)
    end)
    return Box
end

--------------------------------------------------------------------------------
-- Build UI Elements (Definitions first, then Usage)
--------------------------------------------------------------------------------

local Tab_Teleports = CreateTab("Teleports", "🌀")
local Tab_Visuals = CreateTab("Visuals", "👁️")

-- We define logic vars here so buttons can reference them
local MM2_Roles = {
    Murderer = nil,
    Sheriff = nil
}
local ESP_Settings = {
    Murderer = {Enabled = false, Color = Color3.fromRGB(255, 0, 0)},
    Sheriff = {Enabled = false, Color = Color3.fromRGB(0, 0, 255)},
    Innocent = {Enabled = false, Color = Color3.fromRGB(0, 255, 0)}
}

-- Teleport Logic Helper
local function TeleportToPlayer(target)
    if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
         if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
             LocalPlayer.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(0, 2, 0)
         end
    end
end

-- --- Teleports Tab Content ---

CreateButton(Tab_Teleports, "TP to Murderer 🔪", function()
    if MM2_Roles.Murderer then
        TeleportToPlayer(MM2_Roles.Murderer)
    end
end)

CreateButton(Tab_Teleports, "TP to Sheriff 🔫", function()
    if MM2_Roles.Sheriff then
        TeleportToPlayer(MM2_Roles.Sheriff)
    end
end)

local TargetName = ""
CreateInput(Tab_Teleports, "Player Name (Partial) 👤", function(t)
    TargetName = t
end)

CreateButton(Tab_Teleports, "TP to Player 🚀", function()
    for _, p in pairs(Players:GetPlayers()) do
        if TargetName ~= "" and (string.find(string.lower(p.Name), string.lower(TargetName)) or string.find(string.lower(p.DisplayName), string.lower(TargetName))) then
            TeleportToPlayer(p)
            break
        end
    end
end)

-- --- Visuals Tab Content ---

CreateToggle(Tab_Visuals, "ESP Murderer 🔪", false, function(v) ESP_Settings.Murderer.Enabled = v end)
CreateColorSlider(Tab_Visuals, "Murderer", ESP_Settings.Murderer.Color, function(c) ESP_Settings.Murderer.Color = c end)

CreateToggle(Tab_Visuals, "ESP Sheriff 🔫", false, function(v) ESP_Settings.Sheriff.Enabled = v end)
CreateColorSlider(Tab_Visuals, "Sheriff", ESP_Settings.Sheriff.Color, function(c) ESP_Settings.Sheriff.Color = c end)

CreateToggle(Tab_Visuals, "ESP Innocent 😇", false, function(v) ESP_Settings.Innocent.Enabled = v end)
CreateColorSlider(Tab_Visuals, "Innocent", ESP_Settings.Innocent.Color, function(c) ESP_Settings.Innocent.Color = c end)

--------------------------------------------------------------------------------
-- Logic Implementation (Loops & Updates)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Logic Implementation (Loops & Updates)
--------------------------------------------------------------------------------

local KnownRoles = {
    Murderer = nil,
    Sheriff = nil
}

-- Clear roles on round restart or when players leave/respawn
local function CheckRoleValidity()
    if KnownRoles.Murderer and (not KnownRoles.Murderer.Parent or not KnownRoles.Murderer.Character or KnownRoles.Murderer.Character.Humanoid.Health <= 0) then
        KnownRoles.Murderer = nil
    end
    if KnownRoles.Sheriff and (not KnownRoles.Sheriff.Parent or not KnownRoles.Sheriff.Character or KnownRoles.Sheriff.Character.Humanoid.Health <= 0) then
        KnownRoles.Sheriff = nil
    end
end

local function ScanRoles()
    -- We update the global exposed roles for Teleport usage
    MM2_Roles.Murderer = KnownRoles.Murderer
    MM2_Roles.Sheriff = KnownRoles.Sheriff
    
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character then
            -- Check Backpack (if accessible) and Character (Equipped)
            local b = p:FindFirstChild("Backpack")
            local c = p.Character
            
            local knife = c:FindFirstChild("Knife") or (b and b:FindFirstChild("Knife"))
            local gun = c:FindFirstChild("Gun") or (b and b:FindFirstChild("Gun")) or c:FindFirstChild("Revolver") or (b and b:FindFirstChild("Revolver"))
            
            -- Specifically for MM2, gun/knife might be named differently in some clones, but usually "Knife" and "Gun"
            -- Also check for "Toy" or specific mesh ids if needed, but names are standard.
            
            if knife then KnownRoles.Murderer = p end
            if gun then KnownRoles.Sheriff = p end
        end
    end
end

local function CreateBillboard(player, text, color)
    if not player.Character then return end
    local head = player.Character:FindFirstChild("Head")
    if not head then return end
    
    local bg = head:FindFirstChild("Sigmatik_ESP_Tag")
    if not bg then
        bg = Instance.new("BillboardGui")
        bg.Name = "Sigmatik_ESP_Tag"
        bg.Adornee = head
        bg.Size = UDim2.new(0, 100, 0, 50)
        bg.StudsOffset = Vector3.new(0, 3, 0)
        bg.AlwaysOnTop = true
        bg.Parent = head
        
        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextStrokeTransparency = 0.5
        label.TextStrokeColor3 = Color3.new(0,0,0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 14
        label.Parent = bg
    end
    
    local label = bg:FindFirstChild("Label")
    if label then
        label.Text = text .. "\n" .. player.Name
        label.TextColor3 = color
    end
    
    return bg
end

local function UpdateESP()
    CheckRoleValidity()
    ScanRoles() -- Scan every frame to catch weapon drawing
    
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local role = "Innocent"
            if p == KnownRoles.Murderer then role = "Murderer"
            elseif p == KnownRoles.Sheriff then role = "Sheriff" end
            
            local config = ESP_Settings[role]
            local hl = p.Character:FindFirstChild("Sigmatik_Highlight")
            local bg = p.Character:FindFirstChild("Head") and p.Character.Head:FindFirstChild("Sigmatik_ESP_Tag")
            
            if config.Enabled then
                -- Highlight
                if not hl then
                    hl = Instance.new("Highlight")
                    hl.Name = "Sigmatik_Highlight"
                    hl.FillTransparency = 0.5
                    hl.OutlineTransparency = 0.1
                    hl.Parent = p.Character
                end
                hl.FillColor = config.Color
                hl.OutlineColor = config.Color
                hl.Enabled = true
                
                -- Billboard Text
                CreateBillboard(p, role, config.Color)
                if bg then bg.Enabled = true end
            else
                if hl then hl.Enabled = false end
                if bg then bg.Enabled = false end
            end
        end
    end
end

-- Cleanup on respawn
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        -- Reset role if this player was a special role? 
        -- Actually, keep them until they die.
        if player == KnownRoles.Murderer then KnownRoles.Murderer = nil end
        if player == KnownRoles.Sheriff then KnownRoles.Sheriff = nil end
    end)
end)

-- Main Loop
RunService.RenderStepped:Connect(function()
    pcall(function()
        UpdateESP()
    end)
end)

-- Keybind to hide
UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.RightControl then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)
