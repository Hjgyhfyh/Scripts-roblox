local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    ConfigurationSaving = {
        Enabled = false,
        FolderName = nil,
        FileName = "Hub"
    },
    Discord = {
        Enabled = false,
        Invite = "",
        RememberJoins = false
    },
    KeySystem = false
})

local TabMain = Window:CreateTab("Main", 4483362458)

local fastHoldEnabled = true

local function applyFastHoldToPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    prompt.HoldDuration = 0
    prompt.RequiresLineOfSight = false
    if prompt.MaxActivationDistance < 12 then
        prompt.MaxActivationDistance = 12
    end
end

local function applyFastHoldInTree(root)
    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("ProximityPrompt") then
            applyFastHoldToPrompt(inst)
        end
    end
end

applyFastHoldInTree(workspace)
workspace.DescendantAdded:Connect(function(inst)
    if fastHoldEnabled and inst:IsA("ProximityPrompt") then
        applyFastHoldToPrompt(inst)
    end
end)

TabMain:CreateSection("⚡ Prompts")

TabMain:CreateToggle({
    Name = "Fast Hold",
    CurrentValue = true,
    Flag = "FastHold",
    Callback = function(value)
        fastHoldEnabled = value
        if value then
            applyFastHoldInTree(workspace)
        end
    end
})

TabMain:CreateSection("🛡️ Anti AFK")

LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)
