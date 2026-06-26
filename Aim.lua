local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local aimEnabled = false
local aimPart = "HumanoidRootPart"
local aimSmoothing = 1 -- 1 = Instant, 0.1 = Smooth
local aimFOV = 400
local teamCheck = false
local aimKey = Enum.UserInputType.MouseButton2
local autoRotateCharacter = true -- Поворачивать персонажа к цели

local aimActive = false
local currentTarget = nil

local Window = Rayfield:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = nil,
        FileName = "AimHub"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = true
    },
    KeySystem = false
})

local MainTab = Window:CreateTab("🎯 Aim", 4483362458)

MainTab:CreateSection("Main Settings")

MainTab:CreateToggle({
    Name = "Enable Aim",
    CurrentValue = false,
    Flag = "AimToggle",
    Callback = function(Value)
        aimEnabled = Value
        if not Value then
            aimActive = false
            currentTarget = nil
        end
    end
})

MainTab:CreateDropdown({
    Name = "Aim Part",
    Options = {"Head", "HumanoidRootPart", "UpperTorso"},
    CurrentOption = {"HumanoidRootPart"},
    MultipleOptions = false,
    Flag = "AimPart",
    Callback = function(Option)
        aimPart = Option[1]
    end
})

MainTab:CreateSection("Sensitivity")

MainTab:CreateSlider({
    Name = "Smoothing (1 = Instant)",
    Range = {0.1, 1},
    Increment = 0.1,
    Suffix = "",
    CurrentValue = 1,
    Flag = "AimSmoothing",
    Callback = function(Value)
        aimSmoothing = Value
    end
})

MainTab:CreateSlider({
    Name = "FOV Radius",
    Range = {100, 2000},
    Increment = 50,
    Suffix = "px",
    CurrentValue = 400,
    Flag = "AimFOV",
    Callback = function(Value)
        aimFOV = Value
    end
})

MainTab:CreateSection("Extra")

MainTab:CreateToggle({
    Name = "Character Auto-Rotate",
    CurrentValue = true,
    Flag = "CharRotate",
    Callback = function(Value)
        autoRotateCharacter = Value
    end
})

MainTab:CreateToggle({
    Name = "Team Check",
    CurrentValue = false,
    Flag = "TeamCheck",
    Callback = function(Value)
        teamCheck = Value
    end
})

local function getClosestPlayer()
    local closest = nil
    local shortestDist = aimFOV
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                if teamCheck and p.Team == LocalPlayer.Team then
                    continue
                end

                local part = p.Character:FindFirstChild(aimPart) or p.Character:FindFirstChild("HumanoidRootPart")
                if part then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if dist < shortestDist then
                            shortestDist = dist
                            closest = p
                        end
                    end
                end
            end
        end
    end
    return closest
end

-- Input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not aimEnabled then return end
    if input.UserInputType == aimKey then
        aimActive = true
        currentTarget = getClosestPlayer() -- Grab initial target
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == aimKey then
        aimActive = false
        currentTarget = nil
    end
end)

-- High priority update loop
RunService:BindToRenderStep("AimLockHighPriority", Enum.RenderPriority.Camera.Value + 100, function()
    if aimEnabled and aimActive then
        -- Refresh target if lost or dead
        if not currentTarget or 
           not currentTarget.Character or 
           not currentTarget.Character:FindFirstChild("Humanoid") or 
           currentTarget.Character.Humanoid.Health <= 0 then
            currentTarget = getClosestPlayer()
        end

        if currentTarget and currentTarget.Character then
            local targetPart = currentTarget.Character:FindFirstChild(aimPart) or currentTarget.Character:FindFirstChild("HumanoidRootPart")
            if targetPart then
                local currentCFrame = Camera.CFrame
                local targetObserved = targetPart.Position
                
                -- Prediction (Basic velocity compensation)
                -- local velocity = targetPart.Velocity -- Uncomment if needed, but simple lock is usually preferred for robustness
                -- targetObserved = targetObserved + (velocity * 0.1)

                local desiredCFrame = CFrame.new(currentCFrame.Position, targetObserved)
                
                -- Apply to Camera
                if aimSmoothing >= 1 then
                   Camera.CFrame = desiredCFrame
                else
                   Camera.CFrame = currentCFrame:Lerp(desiredCFrame, aimSmoothing)
                end

                -- Apply to Character (Body Rotation)
                if autoRotateCharacter and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    local myRoot = LocalPlayer.Character.HumanoidRootPart
                    local flatLookAt = Vector3.new(targetObserved.X, myRoot.Position.Y, targetObserved.Z)
                    myRoot.CFrame = CFrame.new(myRoot.Position, flatLookAt)
                end
            end
        end
    end
end)

Rayfield:Notify({
    Title = "Aim Ready",
    Content = "Right Click to Lock On",
    Duration = 5
})
