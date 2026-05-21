local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    Theme = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {
        Enabled = false,
        FolderName = nil,
        FileName = "DungeonBugTest"
    },
    Discord = {
        Enabled = false,
        Invite = "",
        RememberJoins = true
    },
    KeySystem = false
})

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local netPath = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
local inventoryRF = ReplicatedStorage:WaitForChild("InventoryComm"):WaitForChild("RF")
local lootAnchor = Workspace:WaitForChild("LootAnchor")

local rebirthActive = false
local lootActive = false
local equipBestActive = false
local farmActive = false
local savedPosition = nil

local MainTab = Window:CreateTab("🔧 Exploits", 4483362458)

MainTab:CreateSection("Farm")

MainTab:CreateToggle({
    Name = "Auto Farm",
    CurrentValue = false,
    Flag = "AutoFarm",
    Callback = function(Value)
        farmActive = Value
        if Value then
            task.spawn(function()
                local char = LocalPlayer.Character
                if char and char:FindFirstChild("HumanoidRootPart") then
                    savedPosition = char.HumanoidRootPart.CFrame
                end
                while farmActive do
                    pcall(function()
                        local char = LocalPlayer.Character
                        if char and char:FindFirstChild("HumanoidRootPart") then
                            char.HumanoidRootPart.CFrame = CFrame.new(4, 254, 978)
                        end
                    end)
                    task.wait()
                end
                if savedPosition then
                    pcall(function()
                        local char = LocalPlayer.Character
                        if char and char:FindFirstChild("HumanoidRootPart") then
                            char.HumanoidRootPart.CFrame = savedPosition
                        end
                    end)
                    savedPosition = nil
                end
            end)
        end
    end
})

MainTab:CreateSection("Rebirth")

MainTab:CreateToggle({
    Name = "Auto Rebirth",
    CurrentValue = false,
    Flag = "AutoRebirth",
    Callback = function(Value)
        rebirthActive = Value
        if Value then
            task.spawn(function()
                while rebirthActive do
                    pcall(function()
                        netPath:WaitForChild("RE/Rebirth_Request"):FireServer()
                    end)
                    task.wait(0.1)
                end
            end)
        end
    end
})

MainTab:CreateSection("Inventory")

MainTab:CreateToggle({
    Name = "Auto Equip Best",
    CurrentValue = false,
    Flag = "AutoEquipBest",
    Callback = function(Value)
        equipBestActive = Value
        if Value then
            task.spawn(function()
                while equipBestActive do
                    pcall(function()
                        inventoryRF:WaitForChild("EquipBestWeapons"):InvokeServer()
                    end)
                    task.wait(1)
                end
            end)
        end
    end
})

MainTab:CreateSection("Loot Collect")

MainTab:CreateToggle({
    Name = "Auto Collect All Loot",
    CurrentValue = false,
    Flag = "AutoLoot",
    Callback = function(Value)
        lootActive = Value
        if Value then
            task.spawn(function()
                while lootActive do
                    pcall(function()
                        local ids = {}
                        for _, child in pairs(lootAnchor:GetChildren()) do
                            local num = child.Name:match("LootAttachment_(%d+)")
                            if num then
                                table.insert(ids, tonumber(num))
                            end
                        end
                        if #ids > 0 then
                            netPath:WaitForChild("RF/Loot_CollectBatch"):InvokeServer(ids)
                        end
                    end)
                    task.wait(0.1)
                end
            end)
        end
    end
})

MainTab:CreateSection("Misc")

MainTab:CreateToggle({
    Name = "Anti AFK",
    CurrentValue = false,
    Flag = "AntiAFK",
    Callback = function(Value)
        if Value then
            local VirtualUser = game:GetService("VirtualUser")
            local antiAfkConnection
            antiAfkConnection = LocalPlayer.Idled:Connect(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
            _G.AntiAFKConnection = antiAfkConnection
        else
            if _G.AntiAFKConnection then
                _G.AntiAFKConnection:Disconnect()
                _G.AntiAFKConnection = nil
            end
        end
    end
})

Rayfield:LoadConfiguration()
