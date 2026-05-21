local Sigmatik = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/source.lua.txt"))()

local SharedEnvironment = getgenv and getgenv() or _G
local PreviousContext = SharedEnvironment.SigmatikGoldenCornFarmContext

if PreviousContext and PreviousContext.Cleanup then
    pcall(PreviousContext.Cleanup)
end

local Window = Sigmatik:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    Theme = "Default",
    ConfigurationSaving = {
        Enabled = false,
        FolderName = nil,
        FileName = "Golden_Corn_Farm"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = false
    },
    KeySystem = false
})

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Settings = {
    ItemName = "GoldenCorn",
    BurstCount = 75,
    BurstDelay = 0.01,
    PresetName = "Turbo"
}

local Runtime = {
    Alive = true,
    AutoCollectEnabled = false,
    LoopId = 0,
    TotalCalls = 0,
    LastBurstCount = 0,
    LastError = "None",
    RemoteCache = nil,
    Connections = {}
}

SharedEnvironment.SigmatikGoldenCornFarmContext = Runtime

local Labels = {}
local Controls = {}

local function addConnection(connection)
    if connection then
        Runtime.Connections[#Runtime.Connections + 1] = connection
    end
    return connection
end

local function disconnectAll()
    for _, connection in ipairs(Runtime.Connections) do
        if connection then
            connection:Disconnect()
        end
    end

    table.clear(Runtime.Connections)
end

local function optionToString(option)
    if type(option) == "table" then
        return tostring(option[1] or "")
    end

    return tostring(option or "")
end

local function optionToNumber(option, fallback)
    local value = tonumber(optionToString(option))
    return value or fallback
end

local function setLabel(labelObject, text)
    if labelObject and labelObject.Set then
        labelObject:Set(text)
    end
end

local function notify(title, content, duration)
    pcall(function()
        Sigmatik:Notify({
            Title = title,
            Content = content,
            Duration = duration or 4
        })
    end)
end

local function getCollectCornEvent()
    local cachedRemote = Runtime.RemoteCache

    if cachedRemote and cachedRemote.Parent then
        return cachedRemote
    end

    local remote = ReplicatedStorage:FindFirstChild("CollectCornEvent")

    if not remote then
        remote = ReplicatedStorage:WaitForChild("CollectCornEvent", 2)
    end

    if remote and remote:IsA("RemoteEvent") then
        Runtime.RemoteCache = remote
        return remote
    end

    Runtime.RemoteCache = nil
    return nil
end

local function refreshRemoteStatus()
    local remote = getCollectCornEvent()

    if remote then
        setLabel(Labels.RemoteStatus, "Remote Status: CollectCornEvent ready")
    else
        setLabel(Labels.RemoteStatus, "Remote Status: CollectCornEvent missing")
    end
end

local function refreshPayloadStatus()
    setLabel(
        Labels.PayloadStatus,
        string.format(
            "Payload Status: %s | %d calls | %.4fs delay | %s",
            Settings.ItemName,
            Settings.BurstCount,
            Settings.BurstDelay,
            Settings.PresetName
        )
    )
end

local function refreshSessionStatus(text)
    setLabel(Labels.SessionStatus, "Session Status: " .. tostring(text))
end

local function refreshLoopStatus()
    if Runtime.AutoCollectEnabled then
        setLabel(
            Labels.LoopStatus,
            string.format("Loop Status: Running %d calls every %.4fs", Settings.BurstCount, Settings.BurstDelay)
        )
    else
        setLabel(Labels.LoopStatus, "Loop Status: Idle")
    end
end

local function refreshCounters()
    setLabel(Labels.TotalCalls, "Total Calls: " .. tostring(Runtime.TotalCalls))
    setLabel(Labels.LastBurst, "Last Burst: " .. tostring(Runtime.LastBurstCount))
    setLabel(Labels.LastError, "Last Error: " .. tostring(Runtime.LastError))
end

local function applyPreset(name)
    if name == "Balanced" then
        Settings.BurstCount = 25
        Settings.BurstDelay = 0.05
    elseif name == "Fast" then
        Settings.BurstCount = 50
        Settings.BurstDelay = 0.02
    elseif name == "Insane" then
        Settings.BurstCount = 120
        Settings.BurstDelay = 0.005
    else
        name = "Turbo"
        Settings.BurstCount = 75
        Settings.BurstDelay = 0.01
    end

    Settings.PresetName = name
    refreshPayloadStatus()
    refreshLoopStatus()
end

local function fireCollectCorn()
    local remote = getCollectCornEvent()

    if not remote then
        Runtime.LastError = "CollectCornEvent missing"
        refreshRemoteStatus()
        refreshCounters()
        refreshSessionStatus("CollectCornEvent missing")
        return false
    end

    local ok, errorMessage = pcall(function()
        remote:FireServer(Settings.ItemName)
    end)

    if not ok then
        Runtime.LastError = tostring(errorMessage)
        refreshCounters()
        refreshSessionStatus("FireServer failed")
        return false
    end

    Runtime.TotalCalls = Runtime.TotalCalls + 1
    Runtime.LastError = "None"
    return true
end

local function runBurst(silent)
    local successfulCalls = 0

    for _ = 1, Settings.BurstCount do
        if not Runtime.Alive then
            break
        end

        if fireCollectCorn() then
            successfulCalls = successfulCalls + 1
        else
            break
        end
    end

    Runtime.LastBurstCount = successfulCalls
    refreshCounters()

    if successfulCalls > 0 then
        refreshSessionStatus("Burst sent: " .. tostring(successfulCalls))
        if not silent then
            notify("Golden Corn", "Burst sent: " .. tostring(successfulCalls), 3)
        end
    elseif not silent then
        notify("Golden Corn", "Burst failed", 3)
    end
end

local function stopAutoCollect()
    Runtime.AutoCollectEnabled = false
    Runtime.LoopId = Runtime.LoopId + 1
    refreshLoopStatus()
    refreshSessionStatus("Auto collect stopped")
end

local function autoCollectLoop(loopId)
    while Runtime.Alive and Runtime.AutoCollectEnabled and Runtime.LoopId == loopId do
        runBurst(true)
        task.wait(Settings.BurstDelay)
    end
end

local function setAutoCollectEnabled(state)
    Runtime.AutoCollectEnabled = state == true
    Runtime.LoopId = Runtime.LoopId + 1

    if Runtime.AutoCollectEnabled then
        refreshSessionStatus("Auto collect started")
        refreshLoopStatus()
        task.spawn(autoCollectLoop, Runtime.LoopId)
    else
        refreshLoopStatus()
        refreshSessionStatus("Auto collect stopped")
    end
end

local MainTab = Window:CreateTab("Golden Corn", 4483362458)

MainTab:CreateSection("Main")

Controls.AutoGoldenCorn = MainTab:CreateToggle({
    Name = "Auto Golden Corn",
    CurrentValue = false,
    Flag = "GCF_AutoGoldenCorn",
    Callback = function(value)
        setAutoCollectEnabled(value)
    end
})

MainTab:CreateButton({
    Name = "Collect Once",
    Callback = function()
        local ok = fireCollectCorn()
        Runtime.LastBurstCount = ok and 1 or 0
        refreshCounters()

        if ok then
            refreshSessionStatus("Single collect sent")
            notify("Golden Corn", "Single collect sent", 3)
        else
            notify("Golden Corn", "CollectCornEvent missing or failed", 3)
        end
    end
})

MainTab:CreateButton({
    Name = "Collect Burst",
    Callback = function()
        task.spawn(function()
            runBurst(false)
        end)
    end
})

MainTab:CreateButton({
    Name = "Stop Auto Collect",
    Callback = function()
        if Controls.AutoGoldenCorn and Controls.AutoGoldenCorn.Set then
            Controls.AutoGoldenCorn:Set(false)
        else
            stopAutoCollect()
        end
    end
})

MainTab:CreateButton({
    Name = "Refresh Remote",
    Callback = function()
        refreshRemoteStatus()
        notify("Golden Corn", "Remote status refreshed", 2)
    end
})

Labels.RemoteStatus = MainTab:CreateLabel("Remote Status: Checking")

MainTab:CreateSection("Settings")

Controls.SpeedPreset = MainTab:CreateDropdown({
    Name = "Speed Preset",
    Options = {"Balanced", "Fast", "Turbo", "Insane"},
    CurrentOption = {"Turbo"},
    MultipleOptions = false,
    Flag = "GCF_SpeedPreset",
    Callback = function(option)
        applyPreset(optionToString(option))
    end
})

Controls.BurstCount = MainTab:CreateDropdown({
    Name = "Calls Per Burst",
    Options = {"10", "25", "50", "75", "100", "120", "150", "250"},
    CurrentOption = {"75"},
    MultipleOptions = false,
    Flag = "GCF_BurstCount",
    Callback = function(option)
        Settings.BurstCount = math.max(1, optionToNumber(option, Settings.BurstCount))
        refreshPayloadStatus()
        refreshLoopStatus()
    end
})

Controls.BurstDelay = MainTab:CreateDropdown({
    Name = "Burst Delay",
    Options = {"0.1000", "0.0500", "0.0200", "0.0100", "0.0050"},
    CurrentOption = {"0.0100"},
    MultipleOptions = false,
    Flag = "GCF_BurstDelay",
    Callback = function(option)
        Settings.BurstDelay = math.max(0.005, optionToNumber(option, Settings.BurstDelay))
        refreshPayloadStatus()
        refreshLoopStatus()
    end
})

MainTab:CreateButton({
    Name = "Apply Turbo Preset",
    Callback = function()
        applyPreset("Turbo")
        notify("Golden Corn", "Turbo preset applied", 2)
    end
})

Labels.PayloadStatus = MainTab:CreateLabel("Payload Status: GoldenCorn | 75 calls | 0.0100s delay | Turbo")

MainTab:CreateSection("Status")

Labels.SessionStatus = MainTab:CreateLabel("Session Status: Idle")
Labels.LoopStatus = MainTab:CreateLabel("Loop Status: Idle")
Labels.TotalCalls = MainTab:CreateLabel("Total Calls: 0")
Labels.LastBurst = MainTab:CreateLabel("Last Burst: 0")
Labels.LastError = MainTab:CreateLabel("Last Error: None")
MainTab:CreateLabel("Anti AFK is always active")

addConnection(LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end))

addConnection(ReplicatedStorage.ChildAdded:Connect(function(child)
    if child.Name == "CollectCornEvent" then
        Runtime.RemoteCache = nil
        refreshRemoteStatus()
    end
end))

addConnection(ReplicatedStorage.ChildRemoved:Connect(function(child)
    if child == Runtime.RemoteCache or child.Name == "CollectCornEvent" then
        Runtime.RemoteCache = nil
        refreshRemoteStatus()
    end
end))

addConnection(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    refreshRemoteStatus()
end))

local function cleanup()
    Runtime.Alive = false
    Runtime.AutoCollectEnabled = false
    Runtime.LoopId = Runtime.LoopId + 1
    disconnectAll()

    pcall(function()
        Window:Destroy()
    end)

    SharedEnvironment.SigmatikGoldenCornFarmContext = nil
end

Runtime.Cleanup = cleanup

applyPreset(Settings.PresetName)
refreshRemoteStatus()
refreshPayloadStatus()
refreshLoopStatus()
refreshCounters()
