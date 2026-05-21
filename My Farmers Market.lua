local Sigmatik = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/source.lua.txt"))()

local Window = Sigmatik:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    Theme = "Default",
    ConfigurationSaving = {
        Enabled = false,
        FolderName = nil,
        FileName = "My_Farmers_Market"
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
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Settings = {
    AuditCategory = "All",
    BurstCount = 12,
    RemoteLimit = 20,
    PayloadSize = 96,
    BurstDelay = 0.10,
    LoopDelay = 4,
    WatchDelay = 2,
    UseTablePayloads = true,
    UseStringPayloads = true,
    UseHugeNumbers = true,
    UseNegativeNumbers = true,
    ProbeEconomy = true,
    ProbeReward = true,
    ProbeFarm = true,
    ProbeData = true,
    ProbeAdmin = false,
    PresetName = "Medium"
}

local Runtime = {
    Logs = {},
    SeverityCounts = {
        INFO = 0,
        WARN = 0,
        ALERT = 0
    },
    Baseline = nil,
    LastDiffs = {},
    LastTargets = {},
    LastRemoteCount = 0,
    LoopStressEnabled = false,
    WatchNewRemotesEnabled = false,
    WatchLeaderstatsEnabled = false,
    LoopThreadId = 0,
    StateWatchThreadId = 0,
    RemoteWatchConnections = {}
}

local Labels = {}
local Toggles = {}

local RemoteRoots = {
    ReplicatedStorage,
    ReplicatedFirst,
    Workspace
}

local CategoryKeywords = {
    Economy = {"buy", "purchase", "sell", "market", "shop", "cash", "coin", "money", "gold", "price", "checkout", "crate", "stand"},
    Reward = {"reward", "claim", "gift", "daily", "bonus", "quest", "achievement", "mail", "code", "spin"},
    Farm = {"farm", "seed", "plant", "crop", "harvest", "water", "fruit", "apple", "field", "plot", "barn", "grow", "tree"},
    Data = {"data", "save", "load", "profile", "inventory", "item", "storage", "stats", "sync"},
    Admin = {"admin", "staff", "mod", "moderator", "ban", "kick", "shutdown", "owner"},
    Teleport = {"teleport", "warp", "travel", "spawn"}
}

local SensitiveContainerKeywords = {
    "admin",
    "data",
    "profile",
    "invent",
    "market",
    "shop",
    "reward",
    "quest",
    "remote",
    "farm",
    "crop",
    "seed",
    "plot",
    "currency"
}

local function getTimestamp()
    local success, value = pcall(function()
        return DateTime.now():FormatLocalTime("HH:mm:ss", "en-us")
    end)

    if success and value then
        return value
    end

    return string.format("%.2f", os.clock())
end

local function truncate(text, limit)
    local textString = tostring(text or "")
    local maxLength = limit or 70
    if #textString <= maxLength then
        return textString
    end
    return textString:sub(1, maxLength - 3) .. "..."
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

local function refreshLoopStatus()
    local active = {}

    if Runtime.LoopStressEnabled then
        table.insert(active, "Stress")
    end
    if Runtime.WatchNewRemotesEnabled then
        table.insert(active, "Remotes")
    end
    if Runtime.WatchLeaderstatsEnabled then
        table.insert(active, "State")
    end

    if #active == 0 then
        setLabel(Labels.LoopStatus, "Loop Status: Idle")
    else
        setLabel(Labels.LoopStatus, "Loop Status: " .. table.concat(active, " / "))
    end
end

local function refreshPresetStatus()
    local summary = string.format(
        "Preset Status: %s | Burst %d | Limit %d | Payload %d | Delay %.2f",
        Settings.PresetName,
        Settings.BurstCount,
        Settings.RemoteLimit,
        Settings.PayloadSize,
        Settings.BurstDelay
    )
    setLabel(Labels.PresetStatus, summary)
end

local function selectedCategoriesToText()
    local categories = {}

    if Settings.ProbeEconomy then
        table.insert(categories, "Economy")
    end
    if Settings.ProbeReward then
        table.insert(categories, "Reward")
    end
    if Settings.ProbeFarm then
        table.insert(categories, "Farm")
    end
    if Settings.ProbeData then
        table.insert(categories, "Data")
    end
    if Settings.ProbeAdmin then
        table.insert(categories, "Admin")
    end

    if #categories == 0 then
        categories = {"Economy", "Reward", "Farm", "Data"}
    end

    return table.concat(categories, "/")
end

local function refreshCategoryStatus()
    setLabel(Labels.CategoryStatus, "Category Status: " .. selectedCategoriesToText())
end

local function setLastAlert(text)
    setLabel(Labels.LastAlert, "Last Alert: " .. truncate(text, 80))
end

local function addLog(level, category, message)
    local logLine = string.format("[%s] [%s] [%s] %s", getTimestamp(), level, category, message)

    Runtime.SeverityCounts[level] = (Runtime.SeverityCounts[level] or 0) + 1
    table.insert(Runtime.Logs, logLine)
    print(logLine)

    if level == "WARN" or level == "ALERT" then
        setLastAlert(category .. " - " .. message)
    end
end

local function collectToolNames(container)
    local names = {}

    if not container then
        return names
    end

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Tool") then
            table.insert(names, child.Name)
        end
    end

    table.sort(names)
    return names
end

local function collectValueObjects(root, prefix, bucket, depth)
    if not root or depth > 4 then
        return
    end

    for _, child in ipairs(root:GetChildren()) do
        local nextPrefix = prefix == "" and child.Name or (prefix .. "/" .. child.Name)

        if child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue") or child:IsA("BoolValue") then
            bucket[nextPrefix] = child.Value
        elseif child:IsA("Folder") or child:IsA("Configuration") then
            collectValueObjects(child, nextPrefix, bucket, depth + 1)
        end
    end
end

local function capturePlayerState()
    local snapshot = {
        Leaderstats = {},
        Attributes = {},
        Values = {},
        BackpackTools = collectToolNames(LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:FindFirstChild("Backpack")),
        CharacterTools = collectToolNames(LocalPlayer.Character)
    }

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        for _, child in ipairs(leaderstats:GetChildren()) do
            if child:IsA("ValueBase") then
                snapshot.Leaderstats[child.Name] = child.Value
            end
        end
    end

    for name, value in pairs(LocalPlayer:GetAttributes()) do
        local valueType = typeof(value)
        if valueType == "number" or valueType == "string" or valueType == "boolean" then
            snapshot.Attributes[name] = value
        end
    end

    collectValueObjects(LocalPlayer, "Player", snapshot.Values, 0)
    return snapshot
end

local function diffMaps(beforeMap, afterMap, prefix, diffs)
    local seen = {}

    for key, beforeValue in pairs(beforeMap or {}) do
        seen[key] = true
        local afterValue = afterMap and afterMap[key]
        if afterValue ~= beforeValue then
            table.insert(diffs, string.format("%s%s: %s -> %s", prefix, key, tostring(beforeValue), tostring(afterValue)))
        end
    end

    for key, afterValue in pairs(afterMap or {}) do
        if not seen[key] then
            table.insert(diffs, string.format("%s%s: nil -> %s", prefix, key, tostring(afterValue)))
        end
    end
end

local function flattenList(list)
    if not list or #list == 0 then
        return "None"
    end
    return table.concat(list, ", ")
end

local function diffLists(beforeList, afterList, prefix, diffs)
    local beforeText = flattenList(beforeList)
    local afterText = flattenList(afterList)

    if beforeText ~= afterText then
        table.insert(diffs, string.format("%s: %s -> %s", prefix, beforeText, afterText))
    end
end

local function buildStateDiff(beforeState, afterState)
    local diffs = {}

    diffMaps(beforeState.Leaderstats, afterState.Leaderstats, "Leaderstats/", diffs)
    diffMaps(beforeState.Attributes, afterState.Attributes, "Attributes/", diffs)
    diffMaps(beforeState.Values, afterState.Values, "Values/", diffs)
    diffLists(beforeState.BackpackTools, afterState.BackpackTools, "BackpackTools", diffs)
    diffLists(beforeState.CharacterTools, afterState.CharacterTools, "CharacterTools", diffs)

    return diffs
end

local function classifyRemote(instance)
    local nameLower = string.lower(instance.Name)
    local fullNameLower = string.lower(instance:GetFullName())
    local categories = {}
    local reasons = {}
    local score = 0

    for category, keywords in pairs(CategoryKeywords) do
        for _, keyword in ipairs(keywords) do
            if string.find(nameLower, keyword, 1, true) or string.find(fullNameLower, keyword, 1, true) then
                if not table.find(categories, category) then
                    table.insert(categories, category)
                end
                if not table.find(reasons, keyword) then
                    table.insert(reasons, keyword)
                end
                score = score + (category == "Admin" and 5 or 3)
            end
        end
    end

    if instance:IsA("RemoteFunction") then
        score = score + 2
    end
    if string.find(fullNameLower, "replicatedstorage", 1, true) then
        score = score + 1
    end

    return categories, score, reasons
end

local function collectRemotes()
    local remotes = {}

    for _, root in ipairs(RemoteRoots) do
        if root then
            for _, instance in ipairs(root:GetDescendants()) do
                if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
                    local categories, score, reasons = classifyRemote(instance)
                    table.insert(remotes, {
                        Instance = instance,
                        Name = instance.Name,
                        FullName = instance:GetFullName(),
                        Type = instance.ClassName,
                        Categories = categories,
                        Score = score,
                        Reasons = reasons
                    })
                end
            end
        end
    end

    table.sort(remotes, function(left, right)
        if left.Score == right.Score then
            return left.FullName < right.FullName
        end
        return left.Score > right.Score
    end)

    Runtime.LastRemoteCount = #remotes
    Runtime.LastTargets = remotes

    return remotes
end

local function targetMatchesCategory(target, category)
    if category == "All" then
        return true
    end

    for _, targetCategory in ipairs(target.Categories) do
        if targetCategory == category then
            return true
        end
    end

    return false
end

local function targetMatchesAnyCategory(target, categories)
    if not categories or #categories == 0 then
        return true
    end

    for _, category in ipairs(categories) do
        if targetMatchesCategory(target, category) then
            return true
        end
    end

    return false
end

local function topTargets(remotes, limit, categories)
    local results = {}

    for _, target in ipairs(remotes) do
        if targetMatchesAnyCategory(target, categories) then
            table.insert(results, target)
            if #results >= limit then
                break
            end
        end
    end

    return results
end

local function buildStressCategories()
    local categories = {}

    if Settings.ProbeEconomy then
        table.insert(categories, "Economy")
    end
    if Settings.ProbeReward then
        table.insert(categories, "Reward")
    end
    if Settings.ProbeFarm then
        table.insert(categories, "Farm")
    end
    if Settings.ProbeData then
        table.insert(categories, "Data")
    end
    if Settings.ProbeAdmin then
        table.insert(categories, "Admin")
    end

    if #categories == 0 then
        categories = {"Economy", "Reward", "Farm", "Data"}
    end

    return categories
end

local function payloadPreview(arguments)
    local parts = {}

    for index, value in ipairs(arguments) do
        local valueType = typeof(value)

        if valueType == "table" then
            table.insert(parts, "table")
        elseif valueType == "string" then
            table.insert(parts, string.format("string(%d)", #value))
        else
            table.insert(parts, tostring(value))
        end

        if index >= 3 then
            break
        end
    end

    return "[" .. table.concat(parts, ", ") .. "]"
end

local function buildPayloads(target)
    local largeNumber = 999999999
    local largeString = string.rep("A", Settings.PayloadSize)
    local payloads = {
        {},
        {0},
        {1},
        {target.Name},
        {LocalPlayer.UserId},
        {LocalPlayer.Name},
        {target.Name, 1}
    }

    if Settings.UseNegativeNumbers then
        table.insert(payloads, {-1})
        table.insert(payloads, {target.Name, -1})
    end

    if Settings.UseHugeNumbers then
        table.insert(payloads, {largeNumber})
        table.insert(payloads, {target.Name, largeNumber})
        table.insert(payloads, {LocalPlayer.UserId, largeNumber, largeNumber})
    end

    if Settings.UseStringPayloads then
        table.insert(payloads, {largeString})
        table.insert(payloads, {target.Name, largeString})
    end

    if Settings.UseTablePayloads then
        table.insert(payloads, {{
            Player = LocalPlayer.Name,
            UserId = LocalPlayer.UserId,
            Item = "Apple",
            Crop = "Apple",
            Reward = "Daily",
            Amount = largeNumber,
            Count = largeNumber,
            Plot = 1,
            Slot = 1
        }})
        table.insert(payloads, {
            target.Name,
            {
                Amount = largeNumber,
                Count = largeNumber,
                Item = "Apple",
                Plot = 1,
                Slot = 1
            }
        })
    end

    return payloads
end

local function invokeWithTimeout(remoteFunction, arguments, timeoutSeconds)
    local finished = false
    local success = false
    local result = nil
    local timeout = timeoutSeconds or 2
    local started = os.clock()

    task.spawn(function()
        success, result = pcall(function()
            return remoteFunction:InvokeServer(table.unpack(arguments))
        end)
        finished = true
    end)

    while not finished and os.clock() - started < timeout do
        task.wait(0.05)
    end

    return finished, success, result
end

local function probeRemote(target)
    local payloads = buildPayloads(target)
    local attempts = target.Type == "RemoteFunction" and math.min(Settings.BurstCount, 2) or Settings.BurstCount
    local successCount = 0
    local errorCount = 0
    local responseCount = 0

    for index = 1, attempts do
        local arguments = payloads[((index - 1) % #payloads) + 1]

        if target.Type == "RemoteEvent" then
            local success = pcall(function()
                target.Instance:FireServer(table.unpack(arguments))
            end)

            if success then
                successCount = successCount + 1
            else
                errorCount = errorCount + 1
            end
        else
            local finished, success, result = invokeWithTimeout(target.Instance, arguments, 2)

            if not finished then
                errorCount = errorCount + 1
                addLog("WARN", "Probe", target.Name .. " timed out on " .. payloadPreview(arguments))
            elseif success then
                successCount = successCount + 1
                if result ~= nil then
                    responseCount = responseCount + 1
                    addLog(
                        "WARN",
                        "Probe",
                        target.Name .. " returned " .. typeof(result) .. " for " .. payloadPreview(arguments)
                    )
                end
            else
                errorCount = errorCount + 1
            end
        end

        if Settings.BurstDelay > 0 then
            task.wait(Settings.BurstDelay)
        end
    end

    if responseCount > 0 then
        addLog(
            "ALERT",
            "Probe",
            string.format("%s returned data during stress attempts (%d/%d)", target.FullName, responseCount, attempts)
        )
    elseif successCount == attempts and target.Score >= 6 then
        addLog(
            "WARN",
            "Probe",
            string.format("%s accepted %d/%d stress attempts [%s]", target.FullName, successCount, attempts, target.Type)
        )
    else
        addLog(
            "INFO",
            "Probe",
            string.format("%s success=%d error=%d", target.FullName, successCount, errorCount)
        )
    end
end

local function printTopTargets(limit)
    local maxTargets = limit or 15
    local remotes = Runtime.LastTargets

    if #remotes == 0 then
        remotes = collectRemotes()
    end

    print("========== MY FARMERS MARKET TOP TARGETS ==========")

    local printed = 0
    for _, target in ipairs(remotes) do
        if target.Score > 0 then
            print(string.format(
                "[%02d] %s | %s | score=%d | categories=%s | reasons=%s",
                printed + 1,
                target.Type,
                target.FullName,
                target.Score,
                #target.Categories > 0 and table.concat(target.Categories, "/") or "None",
                #target.Reasons > 0 and table.concat(target.Reasons, ", ") or "None"
            ))
            printed = printed + 1
            if printed >= maxTargets then
                break
            end
        end
    end

    if printed == 0 then
        print("No suspicious remotes were found.")
    end
end

local function reportDiffs(diffs, category)
    if #diffs == 0 then
        addLog("INFO", category, "No visible player-state delta was detected")
        return
    end

    for index, diff in ipairs(diffs) do
        if index > 20 then
            break
        end
        addLog("ALERT", category, diff)
    end
end

local function runProbeForCategories(categories, runName, silent)
    local remotes = collectRemotes()
    local targets = topTargets(remotes, Settings.RemoteLimit, categories)

    if #targets == 0 then
        addLog("WARN", runName, "No matching remotes were found")
        setLabel(Labels.RemoteStatus, "Remote Status: No targets")
        if not silent then
            notify(runName, "No matching remotes were found", 4)
        end
        return
    end

    local beforeState = capturePlayerState()

    addLog(
        "INFO",
        runName,
        string.format("Starting probe on %d remotes (%s)", #targets, table.concat(categories, "/"))
    )

    for _, target in ipairs(targets) do
        probeRemote(target)
    end

    task.wait(0.35)

    local afterState = capturePlayerState()
    local diffs = buildStateDiff(beforeState, afterState)
    Runtime.LastDiffs = diffs

    reportDiffs(diffs, runName)
    setLabel(Labels.RemoteStatus, "Remote Status: " .. runName .. " " .. tostring(#targets))

    if not silent then
        notify(runName, string.format("Checked %d targets | Diffs %d", #targets, #diffs), 5)
    end
end

local function applyPreset(name)
    if name == "Soft" then
        Settings.BurstCount = 4
        Settings.RemoteLimit = 10
        Settings.PayloadSize = 32
        Settings.BurstDelay = 0.20
    elseif name == "Hard" then
        Settings.BurstCount = 20
        Settings.RemoteLimit = 50
        Settings.PayloadSize = 512
        Settings.BurstDelay = 0.02
    else
        name = "Medium"
        Settings.BurstCount = 12
        Settings.RemoteLimit = 20
        Settings.PayloadSize = 96
        Settings.BurstDelay = 0.10
    end

    Settings.PresetName = name
    refreshPresetStatus()
    addLog(
        "INFO",
        "Preset",
        string.format(
            "%s preset applied (burst=%d limit=%d payload=%d delay=%.2f)",
            name,
            Settings.BurstCount,
            Settings.RemoteLimit,
            Settings.PayloadSize,
            Settings.BurstDelay
        )
    )
    notify("Preset", name .. " preset applied", 3)
end

local function scanAllRemotes()
    local remotes = collectRemotes()
    local remoteEvents = 0
    local remoteFunctions = 0
    local suspicious = 0

    for _, target in ipairs(remotes) do
        if target.Type == "RemoteEvent" then
            remoteEvents = remoteEvents + 1
        else
            remoteFunctions = remoteFunctions + 1
        end

        if target.Score > 0 then
            suspicious = suspicious + 1
        end
    end

    addLog(
        "INFO",
        "Scan",
        string.format("RemoteEvent=%d | RemoteFunction=%d | suspicious=%d", remoteEvents, remoteFunctions, suspicious)
    )

    setLabel(Labels.RemoteStatus, string.format("Remote Status: %d remotes / %d suspicious", #remotes, suspicious))
    notify("Remote Scan", string.format("Total %d | Suspicious %d", #remotes, suspicious), 5)
end

local function scanSmartTargets()
    local remotes = collectRemotes()
    local printed = 0

    for _, target in ipairs(remotes) do
        if target.Score > 0 then
            addLog(
                "WARN",
                "Targets",
                string.format(
                    "%s [%s] score=%d categories=%s",
                    target.FullName,
                    target.Type,
                    target.Score,
                    #target.Categories > 0 and table.concat(target.Categories, "/") or "None"
                )
            )
            printed = printed + 1
            if printed >= 20 then
                break
            end
        end
    end

    if printed == 0 then
        addLog("INFO", "Targets", "No suspicious names were detected in client-visible remotes")
    end

    setLabel(Labels.RemoteStatus, "Remote Status: Top targets " .. tostring(printed))
    notify("Smart Targets", "Printed " .. tostring(printed) .. " targets to console", 5)
end

local function scanSensitiveContainers()
    local roots = {
        ReplicatedStorage,
        ReplicatedFirst,
        Workspace,
        LocalPlayer,
        LocalPlayer:FindFirstChild("PlayerGui")
    }

    local hits = {}

    for _, root in ipairs(roots) do
        if root then
            for _, instance in ipairs(root:GetDescendants()) do
                if instance:IsA("Folder")
                    or instance:IsA("Configuration")
                    or instance:IsA("ModuleScript")
                    or instance:IsA("RemoteEvent")
                    or instance:IsA("RemoteFunction") then
                    local fullNameLower = string.lower(instance:GetFullName())

                    for _, keyword in ipairs(SensitiveContainerKeywords) do
                        if string.find(fullNameLower, keyword, 1, true) then
                            table.insert(hits, instance:GetFullName() .. " [" .. instance.ClassName .. "]")
                            break
                        end
                    end
                end
            end
        end
    end

    table.sort(hits)

    local printed = 0
    for _, hit in ipairs(hits) do
        addLog("WARN", "Containers", hit)
        printed = printed + 1
        if printed >= 35 then
            break
        end
    end

    addLog("INFO", "Containers", "Visible sensitive containers: " .. tostring(#hits))
    setLabel(Labels.RemoteStatus, "Remote Status: Sensitive scan " .. tostring(#hits))
    notify("Sensitive Scan", "Visible containers: " .. tostring(#hits), 5)
end

local function saveBaseline()
    Runtime.Baseline = capturePlayerState()
    setLabel(Labels.StateStatus, "State Status: Baseline captured")
    addLog("INFO", "State", "Baseline snapshot captured")
    notify("Baseline", "Current state saved", 3)
end

local function compareWithBaseline()
    if not Runtime.Baseline then
        addLog("WARN", "State", "Baseline is missing")
        setLabel(Labels.StateStatus, "State Status: No baseline")
        notify("State Diff", "Create baseline first", 4)
        return
    end

    local diffs = buildStateDiff(Runtime.Baseline, capturePlayerState())
    Runtime.LastDiffs = diffs

    reportDiffs(diffs, "State")
    setLabel(Labels.StateStatus, "State Status: Diffs " .. tostring(#diffs))
    notify("State Diff", "Differences found: " .. tostring(#diffs), 4)
end

local function runSmartAudit()
    local categories

    if Settings.AuditCategory == "All" then
        categories = {"Economy", "Reward", "Farm", "Data", "Admin"}
    else
        categories = {Settings.AuditCategory}
    end

    scanAllRemotes()
    scanSmartTargets()
    runProbeForCategories(categories, "Smart Audit", false)
end

local function stopRemoteWatch()
    for _, connection in ipairs(Runtime.RemoteWatchConnections) do
        if connection then
            connection:Disconnect()
        end
    end

    Runtime.RemoteWatchConnections = {}
    Runtime.WatchNewRemotesEnabled = false
    refreshLoopStatus()
end

local function startRemoteWatch()
    stopRemoteWatch()
    Runtime.WatchNewRemotesEnabled = true

    for _, root in ipairs(RemoteRoots) do
        if root then
            local connection = root.DescendantAdded:Connect(function(instance)
                if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
                    local categories, score = classifyRemote(instance)
                    addLog(
                        score > 0 and "WARN" or "INFO",
                        "Remote Watch",
                        string.format(
                            "New %s: %s | categories=%s",
                            instance.ClassName,
                            instance:GetFullName(),
                            #categories > 0 and table.concat(categories, "/") or "None"
                        )
                    )
                end
            end)

            table.insert(Runtime.RemoteWatchConnections, connection)
        end
    end

    refreshLoopStatus()
    notify("Remote Watch", "Watching for new remotes", 3)
end

local function stopLeaderstatWatch()
    Runtime.WatchLeaderstatsEnabled = false
    Runtime.StateWatchThreadId = Runtime.StateWatchThreadId + 1
    refreshLoopStatus()
end

local function startLeaderstatWatch()
    Runtime.WatchLeaderstatsEnabled = true
    Runtime.StateWatchThreadId = Runtime.StateWatchThreadId + 1

    local watchId = Runtime.StateWatchThreadId
    local previousState = capturePlayerState()

    refreshLoopStatus()

    task.spawn(function()
        while Runtime.WatchLeaderstatsEnabled and Runtime.StateWatchThreadId == watchId do
            task.wait(Settings.WatchDelay)

            local currentState = capturePlayerState()
            local diffs = buildStateDiff(previousState, currentState)

            if #diffs > 0 then
                Runtime.LastDiffs = diffs
                for index, diff in ipairs(diffs) do
                    if index > 10 then
                        break
                    end
                    addLog("WARN", "State Watch", diff)
                end
                setLabel(Labels.StateStatus, "State Status: Live diffs " .. tostring(#diffs))
            end

            previousState = currentState
        end
    end)

    notify("State Watch", "Watching player state", 3)
end

local function stopLoopStressInternal()
    Runtime.LoopStressEnabled = false
    Runtime.LoopThreadId = Runtime.LoopThreadId + 1
    refreshLoopStatus()
end

local function startLoopStress()
    Runtime.LoopStressEnabled = true
    Runtime.LoopThreadId = Runtime.LoopThreadId + 1

    local loopId = Runtime.LoopThreadId
    refreshLoopStatus()
    notify("Loop Stress", "Loop stress enabled", 3)

    task.spawn(function()
        while Runtime.LoopStressEnabled and Runtime.LoopThreadId == loopId do
            local categories = buildStressCategories()
            runProbeForCategories(categories, "Loop Stress", true)
            task.wait(Settings.LoopDelay)
        end
    end)
end

local function stopAllLoops()
    stopLoopStressInternal()
    stopRemoteWatch()
    stopLeaderstatWatch()

    if Toggles.LoopStress then
        Toggles.LoopStress:Set(false)
    end
    if Toggles.WatchNewRemotes then
        Toggles.WatchNewRemotes:Set(false)
    end
    if Toggles.WatchLeaderstats then
        Toggles.WatchLeaderstats:Set(false)
    end

    notify("Stress Stop", "All active loops were stopped", 3)
end

local function printSummary()
    print("========== MY FARMERS MARKET SECURITY SUMMARY ==========")
    print("Remote count: " .. tostring(Runtime.LastRemoteCount))
    print("Logs: " .. tostring(#Runtime.Logs))
    print(
        string.format(
            "Severity -> INFO=%d WARN=%d ALERT=%d",
            Runtime.SeverityCounts.INFO,
            Runtime.SeverityCounts.WARN,
            Runtime.SeverityCounts.ALERT
        )
    )
    print("Preset: " .. Settings.PresetName)
    print("Selected stress categories: " .. selectedCategoriesToText())
    print("Last diffs: " .. tostring(#Runtime.LastDiffs))

    if #Runtime.LastDiffs > 0 then
        print("----- LAST STATE DIFFS -----")
        for index, diff in ipairs(Runtime.LastDiffs) do
            if index > 20 then
                break
            end
            print(diff)
        end
    end

    notify("Summary", "Exported summary to console", 4)
end

local function clearLogs()
    Runtime.Logs = {}
    Runtime.SeverityCounts.INFO = 0
    Runtime.SeverityCounts.WARN = 0
    Runtime.SeverityCounts.ALERT = 0
    Runtime.LastDiffs = {}
    Runtime.LastTargets = {}
    Runtime.LastRemoteCount = 0

    setLabel(Labels.RemoteStatus, "Remote Status: Cleared")
    setLabel(Labels.StateStatus, Runtime.Baseline and "State Status: Baseline saved" or "State Status: No baseline")
    setLastAlert("None")

    addLog("INFO", "Logs", "Logs were cleared")
    notify("Logs", "Logs cleared", 3)
end

LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local AuditTab = Window:CreateTab("Audit", 4483362458)
local StressTab = Window:CreateTab("Stress", 4483362458)
local ReportTab = Window:CreateTab("Report", 4483362458)

AuditTab:CreateSection("📸 Snapshot")

AuditTab:CreateButton({
    Name = "Baseline Snapshot",
    Callback = function()
        task.spawn(saveBaseline)
    end
})

AuditTab:CreateButton({
    Name = "Compare With Baseline",
    Callback = function()
        task.spawn(compareWithBaseline)
    end
})

Labels.StateStatus = AuditTab:CreateLabel("State Status: No baseline")
AuditTab:CreateLabel("Anti AFK is always active")

AuditTab:CreateSection("🛰 Discovery")

AuditTab:CreateButton({
    Name = "Scan All Remotes",
    Callback = function()
        task.spawn(scanAllRemotes)
    end
})

AuditTab:CreateButton({
    Name = "Scan Smart Targets",
    Callback = function()
        task.spawn(scanSmartTargets)
    end
})

AuditTab:CreateButton({
    Name = "Scan Sensitive Containers",
    Callback = function()
        task.spawn(scanSensitiveContainers)
    end
})

Labels.RemoteStatus = AuditTab:CreateLabel("Remote Status: Idle")

AuditTab:CreateSection("🧠 Smart Audit")

AuditTab:CreateDropdown({
    Name = "Audit Category",
    Options = {"All", "Economy", "Reward", "Farm", "Data", "Admin", "Teleport"},
    CurrentOption = {"All"},
    MultipleOptions = false,
    Flag = "MFM_AuditCategory",
    Callback = function(option)
        Settings.AuditCategory = optionToString(option)
    end
})

AuditTab:CreateDropdown({
    Name = "Burst Count",
    Options = {"4", "8", "12", "20"},
    CurrentOption = {"12"},
    MultipleOptions = false,
    Flag = "MFM_BurstCount",
    Callback = function(option)
        Settings.BurstCount = optionToNumber(option, Settings.BurstCount)
        Settings.PresetName = "Custom"
        refreshPresetStatus()
    end
})

AuditTab:CreateDropdown({
    Name = "Remote Limit",
    Options = {"10", "20", "35", "50"},
    CurrentOption = {"20"},
    MultipleOptions = false,
    Flag = "MFM_RemoteLimit",
    Callback = function(option)
        Settings.RemoteLimit = optionToNumber(option, Settings.RemoteLimit)
        Settings.PresetName = "Custom"
        refreshPresetStatus()
    end
})

AuditTab:CreateDropdown({
    Name = "Payload Size",
    Options = {"32", "96", "256", "512"},
    CurrentOption = {"96"},
    MultipleOptions = false,
    Flag = "MFM_PayloadSize",
    Callback = function(option)
        Settings.PayloadSize = optionToNumber(option, Settings.PayloadSize)
        Settings.PresetName = "Custom"
        refreshPresetStatus()
    end
})

AuditTab:CreateDropdown({
    Name = "Burst Delay",
    Options = {"0.02", "0.05", "0.10", "0.20"},
    CurrentOption = {"0.10"},
    MultipleOptions = false,
    Flag = "MFM_BurstDelay",
    Callback = function(option)
        Settings.BurstDelay = optionToNumber(option, Settings.BurstDelay)
        Settings.PresetName = "Custom"
        refreshPresetStatus()
    end
})

AuditTab:CreateToggle({
    Name = "Use Table Payloads",
    CurrentValue = true,
    Flag = "MFM_UseTablePayloads",
    Callback = function(value)
        Settings.UseTablePayloads = value
    end
})

AuditTab:CreateToggle({
    Name = "Use String Payloads",
    CurrentValue = true,
    Flag = "MFM_UseStringPayloads",
    Callback = function(value)
        Settings.UseStringPayloads = value
    end
})

AuditTab:CreateToggle({
    Name = "Use Huge Numbers",
    CurrentValue = true,
    Flag = "MFM_UseHugeNumbers",
    Callback = function(value)
        Settings.UseHugeNumbers = value
    end
})

AuditTab:CreateToggle({
    Name = "Use Negative Numbers",
    CurrentValue = true,
    Flag = "MFM_UseNegativeNumbers",
    Callback = function(value)
        Settings.UseNegativeNumbers = value
    end
})

AuditTab:CreateButton({
    Name = "Set Soft Preset",
    Callback = function()
        applyPreset("Soft")
    end
})

AuditTab:CreateButton({
    Name = "Set Medium Preset",
    Callback = function()
        applyPreset("Medium")
    end
})

AuditTab:CreateButton({
    Name = "Set Hard Preset",
    Callback = function()
        applyPreset("Hard")
    end
})

AuditTab:CreateButton({
    Name = "Run Smart Audit",
    Callback = function()
        task.spawn(runSmartAudit)
    end
})

AuditTab:CreateButton({
    Name = "Run Category Probe",
    Callback = function()
        task.spawn(function()
            local categories
            if Settings.AuditCategory == "All" then
                categories = {"Economy", "Reward", "Farm", "Data", "Admin"}
            else
                categories = {Settings.AuditCategory}
            end
            runProbeForCategories(categories, "Category Probe", false)
        end)
    end
})

Labels.PresetStatus = AuditTab:CreateLabel("Preset Status: Medium")

StressTab:CreateSection("⚡ Stress Loops")

StressTab:CreateDropdown({
    Name = "Loop Delay",
    Options = {"1", "2", "4", "8"},
    CurrentOption = {"4"},
    MultipleOptions = false,
    Flag = "MFM_LoopDelay",
    Callback = function(option)
        Settings.LoopDelay = optionToNumber(option, Settings.LoopDelay)
    end
})

StressTab:CreateDropdown({
    Name = "Watch Delay",
    Options = {"0.5", "1", "2", "5"},
    CurrentOption = {"2"},
    MultipleOptions = false,
    Flag = "MFM_WatchDelay",
    Callback = function(option)
        Settings.WatchDelay = optionToNumber(option, Settings.WatchDelay)
    end
})

Toggles.LoopStress = StressTab:CreateToggle({
    Name = "Loop Stress",
    CurrentValue = false,
    Flag = "MFM_LoopStress",
    Callback = function(value)
        if value then
            startLoopStress()
        else
            stopLoopStressInternal()
        end
    end
})

Toggles.WatchNewRemotes = StressTab:CreateToggle({
    Name = "Watch New Remotes",
    CurrentValue = false,
    Flag = "MFM_WatchNewRemotes",
    Callback = function(value)
        if value then
            startRemoteWatch()
        else
            stopRemoteWatch()
        end
    end
})

Toggles.WatchLeaderstats = StressTab:CreateToggle({
    Name = "Watch Leaderstats",
    CurrentValue = false,
    Flag = "MFM_WatchLeaderstats",
    Callback = function(value)
        if value then
            startLeaderstatWatch()
        else
            stopLeaderstatWatch()
        end
    end
})

StressTab:CreateKeybind({
    Name = "Stop Active Loops",
    CurrentKeybind = "None",
    HoldToInteract = false,
    Flag = "MFM_StopLoops",
    Callback = function()
        stopAllLoops()
    end
})

StressTab:CreateButton({
    Name = "Stop Stress Now",
    Callback = function()
        stopAllLoops()
    end
})

Labels.LoopStatus = StressTab:CreateLabel("Loop Status: Idle")

StressTab:CreateSection("🍎 Market Focus")

StressTab:CreateToggle({
    Name = "Probe Economy Remotes",
    CurrentValue = true,
    Flag = "MFM_ProbeEconomy",
    Callback = function(value)
        Settings.ProbeEconomy = value
        refreshCategoryStatus()
    end
})

StressTab:CreateToggle({
    Name = "Probe Reward Remotes",
    CurrentValue = true,
    Flag = "MFM_ProbeReward",
    Callback = function(value)
        Settings.ProbeReward = value
        refreshCategoryStatus()
    end
})

StressTab:CreateToggle({
    Name = "Probe Farm Remotes",
    CurrentValue = true,
    Flag = "MFM_ProbeFarm",
    Callback = function(value)
        Settings.ProbeFarm = value
        refreshCategoryStatus()
    end
})

StressTab:CreateToggle({
    Name = "Probe Data Remotes",
    CurrentValue = true,
    Flag = "MFM_ProbeData",
    Callback = function(value)
        Settings.ProbeData = value
        refreshCategoryStatus()
    end
})

StressTab:CreateToggle({
    Name = "Probe Admin Remotes",
    CurrentValue = false,
    Flag = "MFM_ProbeAdmin",
    Callback = function(value)
        Settings.ProbeAdmin = value
        refreshCategoryStatus()
    end
})

StressTab:CreateButton({
    Name = "Run Market Stress",
    Callback = function()
        task.spawn(function()
            runProbeForCategories(buildStressCategories(), "Market Stress", false)
        end)
    end
})

Labels.CategoryStatus = StressTab:CreateLabel("Category Status: Economy/Reward/Farm/Data")

ReportTab:CreateSection("📝 Report")

ReportTab:CreateButton({
    Name = "Print Summary",
    Callback = function()
        printSummary()
    end
})

ReportTab:CreateButton({
    Name = "Print Top Targets",
    Callback = function()
        printTopTargets(15)
        notify("Top Targets", "Printed top targets to console", 4)
    end
})

ReportTab:CreateButton({
    Name = "Clear Logs",
    Callback = function()
        clearLogs()
    end
})

ReportTab:CreateLabel("Logs are exported to console")
Labels.LastAlert = ReportTab:CreateLabel("Last Alert: None")

refreshPresetStatus()
refreshCategoryStatus()
refreshLoopStatus()
