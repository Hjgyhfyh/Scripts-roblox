local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = nil,
        FileName = "Leaf Collector"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = true
    },
    KeySystem = false
})

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CollectCurrency = Remotes:WaitForChild("CollectCurrency")
local Rebirth = Remotes:WaitForChild("Rebirth")

local completeGameEnabled = false

LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local MainTab = Window:CreateTab("Main", "leaf")

MainTab:CreateSection("🎮 Automation")

local CompleteGameToggle = MainTab:CreateToggle({
    Name = "Coplete game",
    CurrentValue = false,
    Flag = "CopleteGame",
    Callback = function(Value)
        completeGameEnabled = Value
    end
})

MainTab:CreateSection("🍃 Resources")

local GetInfLeafButton = MainTab:CreateButton({
    Name = "Get Inf. Leaf",
    Callback = function()
        local args = {
            "Collect",
            999999999999999999999999999999999999999999999999999999999999999999999,
            "Leaves",
            true
        }
        CollectCurrency:FireServer(unpack(args))
    end
})

local AddData = Remotes:WaitForChild("AddData")

local GetInfAppleButton = MainTab:CreateButton({
    Name = "Get Inf. Apple",
    Callback = function()
        local args = {
            "none",
            "Gift",
            99999999999999999999999999999999999999999999999999999999999999999
        }
        AddData:FireServer(unpack(args))
    end
})

task.spawn(function()
    while true do
        if completeGameEnabled then
            pcall(function()
                local collectArgs = {
                    "Collect",
                    999999999999999999999999999999999999999999999999999999999999999999999,
                    "Leaves",
                    true
                }
                CollectCurrency:FireServer(unpack(collectArgs))
            end)
            
            pcall(function()
                local rebirthArgs = {
                    "Rebirths",
                    "2ndIsland",
                    30000000000
                }
                Rebirth:FireServer(unpack(rebirthArgs))
            end)
        end
        task.wait(0.01)
    end
end)
