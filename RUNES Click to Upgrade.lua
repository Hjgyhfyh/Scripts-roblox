local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/79e721b/sigmatik_ui_library.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events")
local PlayerClicked = Remotes:WaitForChild("PlayerClicked")
local AutoClickerClicked = Remotes:WaitForChild("AutoClickerClicked")

local autoClickEnabled = false
local autoClickerEnabled = false
local clicksPerSecond = 15
local clickThread = nil
local autoClickerThread = nil

local UI

UI = Library:Create({
    Title = "tg: @sigmatik323",
    ConfigName = "RUNES Click to Upgrade",
    SearchPlaceholder = "Search modules...",
    GuiToggleKey = Enum.KeyCode.RightShift,
    Accent = "#3b82f6",

    Tabs = {
        {
            Name = "Auto Click",
            Icon = "main",
            Modules = {
                {
                    Name = "Click Farm",
                    Enabled = false,
                    Callback = function(state)
                        autoClickEnabled = state
                        if state and not clickThread then
                            clickThread = task.spawn(function()
                                while autoClickEnabled do
                                    PlayerClicked:FireServer()
                                    task.wait(1 / math.max(1, clicksPerSecond))
                                end
                                clickThread = nil
                            end)
                        end
                    end,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                {
                                    Type = "slider",
                                    Name = "Clicks per second",
                                    Min = 1,
                                    Max = 66,
                                    Increment = 1,
                                    Value = 15,
                                    Callback = function(v)
                                        clicksPerSecond = v
                                    end,
                                },
                                {
                                    Type = "toggle",
                                    Name = "Auto Clicker (gamepass)",
                                    Value = false,
                                    Callback = function(state)
                                        autoClickerEnabled = state
                                        if state and not autoClickerThread then
                                            autoClickerThread = task.spawn(function()
                                                while autoClickerEnabled do
                                                    AutoClickerClicked:FireServer()
                                                    task.wait(1 / math.max(1, clicksPerSecond))
                                                end
                                                autoClickerThread = nil
                                            end)
                                        end
                                    end,
                                },
                            },
                        },
                        {
                            Name = "Stats",
                            Controls = {
                                { Type = "label", Name = "Money", Content = "Money: ..." },
                                { Type = "label", Name = "Total Clicks", Content = "Total Clicks: ..." },
                                { Type = "label", Name = "Playtime", Content = "Playtime: ..." },
                            },
                        },
                    },
                },
            },
        },
    },
})

task.spawn(function()
    while true do
        pcall(function()
            local ls = LocalPlayer:FindFirstChild("leaderstats")
            local hidden = LocalPlayer:FindFirstChild("hiddenstats")
            if ls and ls:FindFirstChild("Money") then
                UI:SetControlValue("Auto Click", "Click Farm", "Stats", "Money", "Money: " .. tostring(ls.Money.Value))
            end
            if hidden and hidden:FindFirstChild("TotalClicks") then
                UI:SetControlValue("Auto Click", "Click Farm", "Stats", "Total Clicks", "Total Clicks: " .. tostring(hidden.TotalClicks.Value))
            end
            if hidden and hidden:FindFirstChild("Playtime") then
                UI:SetControlValue("Auto Click", "Click Farm", "Stats", "Playtime", "Playtime: " .. tostring(hidden.Playtime.Value))
            end
        end)
        task.wait(0.5)
    end
end)

return UI
