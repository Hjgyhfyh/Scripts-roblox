local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "tg: @sigmatik323",
   LoadingTitle = "tg: @sigmatik323",
   LoadingSubtitle = "by sigmatik323",
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "Chicken Incremental Hub"
   },
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = true
   },
   KeySystem = false,
})

-- Anti AFK
spawn(function()
    local vu = game:GetService("VirtualUser")
    game:GetService("Players").LocalPlayer.Idled:connect(function()
        vu:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        wait(1)
        vu:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    end)
end)

local MainTab = Window:CreateTab("Main", 4483362458)
local UpgradesTab = Window:CreateTab("Egg Upgrades", 4483362458)
local PrestigeTab = Window:CreateTab("Prestige", 4483362458)
local RunesTab = Window:CreateTab("Runes", 4483362458)
local LocalTab = Window:CreateTab("Local Player", 4483362458)
local VisualsTab = Window:CreateTab("Visuals", 4483362458)
local TeleportTab = Window:CreateTab("Teleport", 4483362458)

-- Variables
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local AutoFarmChickens = false
local AutoEggValue = false
local AutoChickenRate = false
local AutoChickenCap = false

local AutoPrestigeEggValue = false
local AutoHatchRate = false
local AutoRadius = false

local AutoRollBasic = false
local AutoRollClick = false
local AutoRollGem = false
local AutoClicks = false
local AutoCoinFlip = false
local AutoRuneRebirth = false

-- Remote References (Wait for them to exist if needed, or just assume path as per request)
-- The user provided paths: game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents"):WaitForChild("...")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RequestUpgrade = RemoteEvents:WaitForChild("RequestUpgrade")
local RequestReset = RemoteEvents:WaitForChild("RequestReset")
local RollRune = RemoteEvents:WaitForChild("RollRune")
local CoinFlip = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("CoinFlip")

-- Main Tab
local SectionMain = MainTab:CreateSection("Farming")

local ToggleAutoFarm = MainTab:CreateToggle({
   Name = "Auto Farm Chickens",
   CurrentValue = false,
   Flag = "AutoFarmChickens",
   Callback = function(Value)
        AutoFarmChickens = Value
        spawn(function()
            while AutoFarmChickens do
                pcall(function()
                    if workspace:FindFirstChild("SpawnIsland") and workspace.SpawnIsland:FindFirstChild("ChickenSpawn") and workspace.SpawnIsland.ChickenSpawn:FindFirstChild("Chickens") then
                         for _, chicken in pairs(workspace.SpawnIsland.ChickenSpawn.Chickens:GetChildren()) do
                            if chicken:IsA("BasePart") or chicken:IsA("Model") then
                                local root = chicken:IsA("Model") and chicken.PrimaryPart or chicken
                                if root then
                                    root.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
                                end
                            end
                         end
                    end
                end)
                RunService.Heartbeat:Wait()
            end
        end)
   end,
})


local ToggleAutoClicks = MainTab:CreateToggle({
   Name = "Auto Clicks",
   CurrentValue = false,
   Flag = "AutoClicks",
   Callback = function(Value)
        AutoClicks = Value
        spawn(function()
            while AutoClicks do
                 pcall(function()
                    game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents"):WaitForChild("RequestClick"):FireServer()
                 end)
                 RunService.Heartbeat:Wait()
            end
        end)
   end,
})

local SectionMinigames = MainTab:CreateSection("Minigames")

local ToggleCoinFlip = MainTab:CreateToggle({
   Name = "Auto Coin Flip",
   CurrentValue = false,
   Flag = "AutoCoinFlip",
   Callback = function(Value)
        AutoCoinFlip = Value
        spawn(function()
             while AutoCoinFlip do
                 pcall(function()
                     CoinFlip:InvokeServer()
                 end)
                 wait(0.1)
             end
        end)
   end,
})

-- Upgrades Tab
local SectionUpgrades = UpgradesTab:CreateSection("Normal Upgrades")

local ToggleEggValue = UpgradesTab:CreateToggle({
   Name = "Egg Value",
   CurrentValue = false,
   Flag = "EggValue",
   Callback = function(Value)
      AutoEggValue = Value
      spawn(function()
         while AutoEggValue do
            local args = {
                "Egg",
                "EggValue",
                true
            }
            RequestUpgrade:FireServer(unpack(args))
            wait(0.1)
         end
      end)
   end,
})

local ToggleChickenRate = UpgradesTab:CreateToggle({
   Name = "Chicken Rate",
   CurrentValue = false,
   Flag = "ChickenRate",
   Callback = function(Value)
      AutoChickenRate = Value
      spawn(function()
         while AutoChickenRate do
            local args = {
                "Egg",
                "ChickenRate",
                true
            }
            RequestUpgrade:FireServer(unpack(args))
            wait(0.1)
         end
      end)
   end,
})

local ToggleChickenCap = UpgradesTab:CreateToggle({
   Name = "Chicken Cap",
   CurrentValue = false,
   Flag = "ChickenCap",
   Callback = function(Value)
      AutoChickenCap = Value
      spawn(function()
         while AutoChickenCap do
             local args = {
                "Egg",
                "ChickenCap",
                true
            }
            RequestUpgrade:FireServer(unpack(args))
            wait(0.1)
         end
      end)
   end,
})

-- Prestige Tab
local SectionPrestige = PrestigeTab:CreateSection("Prestige Options")

local ButtonPrestige = PrestigeTab:CreateButton({
   Name = "Do Prestige",
   Callback = function()
        local args = {
            "Prestige"
        }
        RequestReset:FireServer(unpack(args))
   end,
})

local SectionPrestigeUpgrades = PrestigeTab:CreateSection("Prestige Upgrades")

local TogglePrestigeEggValue = PrestigeTab:CreateToggle({
   Name = "Egg Value (Prestige)",
   CurrentValue = false,
   Flag = "PrestigeEggValue",
   Callback = function(Value)
      AutoPrestigeEggValue = Value
      spawn(function()
         while AutoPrestigeEggValue do
            local args = {
                "Prestige",
                "EggValue",
                true
            }
            RequestUpgrade:FireServer(unpack(args))
            wait(0.1)
         end
      end)
   end,
})

local ToggleHatchRate = PrestigeTab:CreateToggle({
   Name = "Hatch Rate",
   CurrentValue = false,
   Flag = "HatchRate",
   Callback = function(Value)
      AutoHatchRate = Value
      spawn(function()
         while AutoHatchRate do
            local args = {
                "Prestige",
                "HatchRate",
                true
            }
            RequestUpgrade:FireServer(unpack(args))
            wait(0.1)
         end
      end)
   end,
})

local ToggleRadius = PrestigeTab:CreateToggle({
   Name = "Radius",
   CurrentValue = false,
   Flag = "Radius",
   Callback = function(Value)
      AutoRadius = Value
      spawn(function()
         while AutoRadius do
            local args = {
                "Prestige",
                "Radius",
                true
            }
            RequestUpgrade:FireServer(unpack(args))
            wait(0.1)
         end
      end)
   end,
})

-- Runes Tab
local SectionRunes = RunesTab:CreateSection("Roll")

local ToggleRollBasic = RunesTab:CreateToggle({
   Name = "Basic Rune",
   CurrentValue = false,
   Flag = "AutoRollBasic",
   Callback = function(Value)
      AutoRollBasic = Value
      spawn(function()
         while AutoRollBasic do
            local args = {
                "Basic"
            }
            RollRune:FireServer(unpack(args))
            wait(0.0001)
         end
      end)
   end,
})

local ToggleRollClick = RunesTab:CreateToggle({
   Name = "Clicks Rune",
   CurrentValue = false,
   Flag = "AutoRollClick",
   Callback = function(Value)
      AutoRollClick = Value
      spawn(function()
         while AutoRollClick do
            local args = {
                "Click"
            }
            RollRune:FireServer(unpack(args))
            wait(0.0001)
         end
      end)
   end,
})

local ToggleRollGem = RunesTab:CreateToggle({
   Name = "Gem Rune",
   CurrentValue = false,
   Flag = "AutoRollGem",
   Callback = function(Value)
      AutoRollGem = Value
      spawn(function()
         while AutoRollGem do
            local args = {
                "Gem"
            }
            RollRune:FireServer(unpack(args))
            wait(0.0001)
         end
      end)
   end,
})

local ToggleRuneRebirth = RunesTab:CreateToggle({
   Name = "Auto Rune Rebirth",
   CurrentValue = false,
   Flag = "AutoRuneRebirth",
   Callback = function(Value)
      AutoRuneRebirth = Value
      spawn(function()
         while AutoRuneRebirth do
            local args = {
                "Rebirth"
            }
            RollRune:FireServer(unpack(args))
            wait(0.0001)
         end
      end)
   end,
})


-- Local Player Tab
local SectionLocal = LocalTab:CreateSection("Movement")

local WalkSpeedSlider = LocalTab:CreateSlider({
   Name = "WalkSpeed",
   Range = {16, 500},
   Increment = 1,
   Suffix = "Speed",
   CurrentValue = 16,
   Flag = "WalkSpeed",
   Callback = function(Value)
      if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
         LocalPlayer.Character.Humanoid.WalkSpeed = Value
      end
   end,
})

local JumpPowerSlider = LocalTab:CreateSlider({
   Name = "JumpPower",
   Range = {50, 500},
   Increment = 1,
   Suffix = "Power",
   CurrentValue = 50,
   Flag = "JumpPower",
   Callback = function(Value)
       if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
         LocalPlayer.Character.Humanoid.JumpPower = Value
      end
   end,
})

-- Fly Logic
local FlyToggle = LocalTab:CreateToggle({
   Name = "Fly",
   CurrentValue = false,
   Flag = "Fly",
   Callback = function(Value)
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid")
        local root = character:WaitForChild("HumanoidRootPart")

        if Value then
            local BodyGyro = Instance.new("BodyGyro", root)
            BodyGyro.P = 9e4
            BodyGyro.maxTorque = Vector3.new(9e9, 9e9, 9e9)
            BodyGyro.cframe = root.CFrame
            
            local BodyVelocity = Instance.new("BodyVelocity", root)
            BodyVelocity.velocity = Vector3.new(0, 0.1, 0)
            BodyVelocity.maxForce = Vector3.new(9e9, 9e9, 9e9)
            
            spawn(function()
                while Value and character:FindFirstChild("HumanoidRootPart") do
                    RunService.RenderStepped:Wait()
                    if not Value then break end
                    
                    humanoid.PlatformStand = true
                    
                    local camera = workspace.CurrentCamera
                    local moveDirection = Vector3.new()
                    
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                        moveDirection = moveDirection + camera.CFrame.LookVector
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                        moveDirection = moveDirection - camera.CFrame.LookVector
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                        moveDirection = moveDirection - camera.CFrame.RightVector
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                        moveDirection = moveDirection + camera.CFrame.RightVector
                    end
                    
                    BodyGyro.CFrame = camera.CFrame
                    BodyVelocity.Velocity = moveDirection * 50
                end
                
                if BodyGyro then BodyGyro:Destroy() end
                if BodyVelocity then BodyVelocity:Destroy() end
                humanoid.PlatformStand = false
            end)
        else
            for _, v in pairs(root:GetChildren()) do
                if v:IsA("BodyGyro") or v:IsA("BodyVelocity") then
                    v:Destroy()
                end
            end
            humanoid.PlatformStand = false
        end
   end,
})

local SwimToggle = LocalTab:CreateToggle({
   Name = "Swim (Fly Variant)",
   CurrentValue = false,
   Flag = "Swim",
   Callback = function(Value)
        -- Using Swim state as requested "Swim (по воздуху)"
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
             local humanoid = LocalPlayer.Character.Humanoid
             if Value then
                 humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
                 workspace.Gravity = 0
                 humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
             else
                 workspace.Gravity = 196.2
                 humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
                 humanoid:ChangeState(Enum.HumanoidStateType.Running)
             end
        end
   end,
})

local NoclipToggle = LocalTab:CreateToggle({
   Name = "Noclip",
   CurrentValue = false,
   Flag = "Noclip",
   Callback = function(Value)
        local Connection
        if Value then
            Connection = RunService.Stepped:Connect(function()
                if LocalPlayer.Character then
                    for _, v in pairs(LocalPlayer.Character:GetDescendants()) do
                        if v:IsA("BasePart") and v.CanCollide == true then
                            v.CanCollide = false
                        end
                    end
                end
            end)
        else
            if Connection then Connection:Disconnect() end
        end
   end,
})

local TPClickBind = LocalTab:CreateKeybind({
   Name = "TP Click",
   CurrentKeybind = "None",
   HoldToInteract = false,
   Flag = "TPClick",
   Callback = function(Keybind)
       local Mouse = LocalPlayer:GetMouse()
       if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
           LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(Mouse.Hit.p + Vector3.new(0, 3, 0))
       end
   end,
})

-- Visuals Tab
local SectionESP = VisualsTab:CreateSection("ESP")

local ESPEnabled = false
local ESPColor = Color3.fromRGB(255, 0, 0)
local ESPContainer = Instance.new("Folder", workspace)
ESPContainer.Name = "ESPContainer"

local function UpdateESP()
    ESPContainer:ClearAllChildren()
    if not ESPEnabled then return end
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local highlight = Instance.new("Highlight")
            highlight.Parent = ESPContainer
            highlight.Adornee = player.Character
            highlight.FillColor = ESPColor
            highlight.OutlineColor = Color3.new(1,1,1)
            highlight.FillTransparency = 0.5
            highlight.OutlineTransparency = 0
            
            -- Basic Box/Text could be added, but Highlight is cleanest for "ESP Players"
        end
    end
end

RunService.RenderStepped:Connect(UpdateESP)

local ToggleESP = VisualsTab:CreateToggle({
   Name = "ESP Players",
   CurrentValue = false,
   Flag = "ESPPlayers",
   Callback = function(Value)
      ESPEnabled = Value
   end,
})

local PickerESPColor = VisualsTab:CreateColorPicker({
    Name = "ESP Color",
    Color = Color3.fromRGB(255, 0, 0),
    Flag = "ESPColor", 
    Callback = function(Value)
        ESPColor = Value
    end
})

local SectionLighting = VisualsTab:CreateSection("Lighting")

local ToggleFullBright = VisualsTab:CreateToggle({
   Name = "FullBright",
   CurrentValue = false,
   Flag = "FullBright",
   Callback = function(Value)
      if Value then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
      else
        Lighting.Brightness = 1
        -- Resetting to random default or keeping it, hard to revert perfectly without saving old state
        Lighting.GlobalShadows = true
      end
   end,
})

local ToggleNoFog = VisualsTab:CreateToggle({
   Name = "No Fog",
   CurrentValue = false,
   Flag = "NoFog",
   Callback = function(Value)
      if Value then
          Lighting.FogEnd = 100000
      else
          Lighting.FogEnd = 1000 -- Approximate default
      end
   end,
})

-- Teleport Tab
local SectionTP = TeleportTab:CreateSection("Player Teleport")

local PlayerDropdown
local PlayerList = {}

local function RefreshPlayerList()
    PlayerList = {}
    for _, v in pairs(Players:GetPlayers()) do
        if v ~= LocalPlayer then
            table.insert(PlayerList, v.Name)
        end
    end
    if PlayerDropdown then
        PlayerDropdown:Refresh(PlayerList)
    end
end

local DropdownPlayers = TeleportTab:CreateDropdown({
   Name = "Player List",
   Options = PlayerList,
   CurrentOption = {""},
   MultipleOptions = false,
   Flag = "PlayerList",
   Callback = function(Option)
   end,
})
PlayerDropdown = DropdownPlayers

local ButtonRefresh = TeleportTab:CreateButton({
   Name = "Refresh Players",
   Callback = function()
       RefreshPlayerList()
   end,
})

local ButtonTP = TeleportTab:CreateButton({
   Name = "Teleport to Player",
   Callback = function()
       -- Get selected user
       -- Rayfield dropdown returns table? Checking Rayfield docs usage in my memory
       -- Usually returns table of strings or single string depending on MultiOption. 
       -- Let's assume table of strings for MultipleOptions=false too based on docs or common use.
       -- Wait, implementation plan said "Option" is a table of strings.
       
       -- Actually, we need to access the CurrentOption properly.
       -- Since we don't have direct access to the internal state easily, we rely on the Callback updating a var if needed, 
       -- OR we can try to assume DropdownPlayers.CurrentOption might work if the lib exposes it?
       -- Safer to store selection in a variable in the Callback.
   end,
})

-- Refactoring Dropdown to capture selection
local SelectedPlayer = nil
DropdownPlayers = TeleportTab:CreateDropdown({
   Name = "Player List",
   Options = PlayerList,
   CurrentOption = {""},
   MultipleOptions = false,
   Flag = "PlayerList",
   Callback = function(Option)
       if type(Option) == "table" then
           SelectedPlayer = Option[1]
       else
           SelectedPlayer = Option
       end
   end,
})
PlayerDropdown = DropdownPlayers

ButtonTP = TeleportTab:CreateButton({
   Name = "Teleport to Player",
   Callback = function()
       if SelectedPlayer then
           local target = Players:FindFirstChild(SelectedPlayer)
           if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
               LocalPlayer.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame
           end
       end
   end,
})

RefreshPlayerList()

Rayfield:LoadConfiguration()
