local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

local TabBrainrots = Window:CreateTab("Brainrots", 4483362458)
local TabAutomation = Window:CreateTab("Automation", 4483362458)
local TabUpgrades = Window:CreateTab("Upgrades", 4483362458)

local rarityDropdown
local brainrotDropdown
local selectedRarity
local selectedBrainrot
local fastHoldEnabled = true
local removeTsunamis = false
local autoClaimMoney = false
local autoBuySpeed = false
local selectedSpeedUpgrade = 1
local autoCarryUpgrade = false
local dupeEpicEnabled = false

local function getChar()
    local c = LocalPlayer.Character
    if not c then return nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    if not h or not r then return nil end
    return c, h, r
end

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

local function findRemote(name)
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if inst.Name == name and (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")) then
            return inst
        end
    end
    return nil
end

local function callRemote(name, ...)
    local remote = findRemote(name)
    if not remote then return end
    if remote:IsA("RemoteEvent") then
        remote:FireServer(...)
    else
        remote:InvokeServer(...)
    end
end

local function getBrainrotContainer()
    return workspace:FindFirstChild("ActiveBrainrots")
end

local function getBrainrotRarities()
    local rarities = {}
    local container = getBrainrotContainer()
    if container then
        for _, folder in ipairs(container:GetChildren()) do
            if folder:IsA("Folder") then
                rarities[#rarities + 1] = folder.Name
            end
        end
    end
    table.sort(rarities)
    return rarities
end

local function getBrainrotsByRarity(rarity)
    local list = {}
    local container = getBrainrotContainer()
    if not container then return list end
    local folder = container:FindFirstChild(rarity)
    if folder then
        for _, inst in ipairs(folder:GetChildren()) do
            list[#list + 1] = inst.Name
        end
    end
    table.sort(list)
    return list
end

local function refreshRarityOptions()
    local options = getBrainrotRarities()
    if rarityDropdown and rarityDropdown.Refresh then
        rarityDropdown:Refresh(options, true)
    end
    if #options > 0 then
        selectedRarity = selectedRarity or options[1]
    end
end

local function refreshBrainrotOptions()
    local options = {}
    if selectedRarity then
        options = getBrainrotsByRarity(selectedRarity)
    end
    if brainrotDropdown and brainrotDropdown.Refresh then
        brainrotDropdown:Refresh(options, true)
    end
    if #options > 0 then
        selectedBrainrot = selectedBrainrot or options[1]
    end
end

local function getBrainrotInstance()
    if not selectedRarity or not selectedBrainrot then return nil end
    local container = getBrainrotContainer()
    if not container then return nil end
    local folder = container:FindFirstChild(selectedRarity)
    if not folder then return nil end
    local target = folder:FindFirstChild(selectedBrainrot)
    if target then return target end
    for _, inst in ipairs(folder:GetDescendants()) do
        if inst.Name == selectedBrainrot then
            return inst
        end
    end
    return nil
end

local function getPromptFromBrainrot(brainrot)
    if not brainrot then return nil end
    if brainrot:IsA("ProximityPrompt") then return brainrot end
    for _, inst in ipairs(brainrot:GetDescendants()) do
        if inst:IsA("ProximityPrompt") then
            return inst
        end
    end
    return nil
end

local function getBrainrotCFrame(brainrot)
    if not brainrot then return nil end
    if brainrot:IsA("Model") then
        return brainrot:GetPivot()
    end
    if brainrot:IsA("BasePart") then
        return brainrot.CFrame
    end
    return nil
end

local function teleportToBrainrot()
    local c, h, r = getChar()
    if not c or not h or not r then return end
    local brainrot = getBrainrotInstance()
    if not brainrot then return end
    local prompt = getPromptFromBrainrot(brainrot)
    if prompt then
        applyFastHoldToPrompt(prompt)
    end
    local cf = getBrainrotCFrame(brainrot)
    if not cf then return end
    r.CFrame = CFrame.new(cf.Position + Vector3.new(0, 3, 0))
end

rarityDropdown = TabBrainrots:CreateDropdown({
    Name = "Brainrot Rarity",
    Options = getBrainrotRarities(),
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "BrainrotRarity",
    Callback = function(option)
        selectedRarity = option[1]
        selectedBrainrot = nil
        refreshBrainrotOptions()
    end
})

brainrotDropdown = TabBrainrots:CreateDropdown({
    Name = "Brainrot Name",
    Options = {},
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "BrainrotName",
    Callback = function(option)
        selectedBrainrot = option[1]
    end
})

TabBrainrots:CreateButton({
    Name = "Refresh Brainrots",
    Callback = function()
        refreshRarityOptions()
        refreshBrainrotOptions()
    end
})

TabBrainrots:CreateButton({
    Name = "Teleport Brainrot",
    Callback = function()
        teleportToBrainrot()
    end
})

TabBrainrots:CreateToggle({
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

TabBrainrots:CreateToggle({
    Name = "Remove Tsunamis",
    CurrentValue = false,
    Flag = "RemoveTsunamis",
    Callback = function(value)
        removeTsunamis = value
    end
})

TabAutomation:CreateToggle({
    Name = "Auto Claim Money",
    CurrentValue = false,
    Flag = "AutoClaimMoney",
    Callback = function(value)
        autoClaimMoney = value
    end
})

TabAutomation:CreateToggle({
    Name = "Dupe Epic",
    CurrentValue = false,
    Flag = "DupeEpic",
    Callback = function(value)
        dupeEpicEnabled = value
    end
})

TabUpgrades:CreateDropdown({
    Name = "Speed Upgrade",
    Options = {"1", "5", "10"},
    CurrentOption = {"1"},
    MultipleOptions = false,
    Flag = "SpeedUpgradeAmount",
    Callback = function(option)
        selectedSpeedUpgrade = tonumber(option[1]) or 1
    end
})

TabUpgrades:CreateToggle({
    Name = "Auto Buy Speed",
    CurrentValue = false,
    Flag = "AutoBuySpeed",
    Callback = function(value)
        autoBuySpeed = value
    end
})

TabUpgrades:CreateToggle({
    Name = "Auto Carry Upgrade",
    CurrentValue = false,
    Flag = "AutoCarryUpgrade",
    Callback = function(value)
        autoCarryUpgrade = value
    end
})

TabUpgrades:CreateButton({
    Name = "Sell All",
    Callback = function()
        callRemote("SellAll")
    end
})

local function clearTsunamis()
    local folder = workspace:FindFirstChild("ActiveTsunamis")
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            child:Destroy()
        end
        folder:Destroy()
    end
end

local function collectAllMoney()
    for i = 1, 40 do
        local slot = "Slot" .. tostring(i)
        callRemote("CollectMoney", slot)
    end
end

task.spawn(function()
    while true do
        if removeTsunamis then
            pcall(clearTsunamis)
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while true do
        if autoClaimMoney then
            collectAllMoney()
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while true do
        if autoBuySpeed then
            callRemote("UpgradeSpeed", selectedSpeedUpgrade)
        end
        task.wait(0.35)
    end
end)

task.spawn(function()
    while true do
        if autoCarryUpgrade then
            callRemote("UpgradeCarry")
        end
        task.wait(0.35)
    end
end)


task.spawn(function()
    while true do
        if dupeEpicEnabled then
            callRemote("TakeFreeEpic")
        end
        task.wait(0.001)
    end
end)

refreshRarityOptions()
refreshBrainrotOptions()