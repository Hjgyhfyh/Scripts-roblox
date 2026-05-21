local Sigmatik = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/source.lua.txt"))()

local Window = Sigmatik:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    Theme = "Green",
    ConfigurationSaving = {
        Enabled = false,
        FolderName = nil,
        FileName = "Catch_Farm_Test"
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
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Rng = Random.new()

local CatchingPresets = {
    Canvas = 1.9027777314186096,
    Fast = 1.35,
    Stable = 1.65,
    Wide = 2.30
}

local CastEffectPresets = {
    Canvas = 0.9027777314186096,
    Soft = 0.55,
    Stable = 0.75,
    Hard = 1.15
}

local StageProfiles = {
    ["Canvas Balanced"] = {
        durationMs = 4725,
        holdTransitions = 3,
        localSuccess = true,
        outsideMs = 1483,
        insideMs = 3242,
        holdTrace = {
            {t = 2275, h = 1},
            {t = 2763, h = 0},
            {t = 4517, h = 1}
        }
    },
    ["Perfect Hold"] = {
        durationMs = 4100,
        holdTransitions = 2,
        localSuccess = true,
        outsideMs = 680,
        insideMs = 3420,
        holdTrace = {
            {t = 640, h = 1},
            {t = 3780, h = 0}
        }
    },
    ["Short Hold"] = {
        durationMs = 3200,
        holdTransitions = 2,
        localSuccess = true,
        outsideMs = 910,
        insideMs = 2290,
        holdTrace = {
            {t = 850, h = 1},
            {t = 2870, h = 0}
        }
    },
    ["Long Hold"] = {
        durationMs = 6200,
        holdTransitions = 4,
        localSuccess = true,
        outsideMs = 1700,
        insideMs = 4500,
        holdTrace = {
            {t = 1200, h = 1},
            {t = 2100, h = 0},
            {t = 3925, h = 1},
            {t = 5660, h = 0}
        }
    }
}

local CanvasHotbarIds = {
    "c2fd07a6-60a5-4075-b0b1-3ce6cfc77403",
    "248ff8a2-6997-435a-9404-08411a345ffe",
    "794901db-7f63-4610-8cd6-3748c0c06871",
    "54b6c52a-1917-4530-aa94-fe8f167f9094",
    "2f9292fc-6247-4251-827e-53a63d06b277"
}

local CarbonHotbarId = "d91c75d1-96f6-42c5-9acc-c15e173d63d0"

local Settings = {
    CatchingPresetName = "Canvas",
    CastPresetName = "Canvas",
    CatchingValue = CatchingPresets.Canvas,
    CastEffectValue = CastEffectPresets.Canvas,
    StageProfileName = "Canvas Balanced",
    GroundDurationMs = 21500,
    SwatCount = 8,
    Area = "Grasslands",
    EquipNetName = "Carbon Net",
    NetTool = "FlimsyNet",
    HotbarPresetName = "Canvas",
    HotbarSlots = 6,
    LossReason = "timeout",
    NpcName = "Bob",
    WeatherName = "Heatwave",
    StepDelay = 0.15,
    LoopDelay = 1.00,
    BurstCount = 3,
    AutoRefreshSession = true,
    AlternateFirstRoute = "Win"
}

local Runtime = {
    SessionNonce = "496ed4fd-adee-4a8a-a2e0-5064d1d79c74",
    StageNonce = "31d7c1a5-1b61-4673-8fdb-9dfea4469fd1",
    CatchSid = 12788,
    CatchSeq = 9,
    StageSid = 13012,
    StageSeq = 17,
    HotbarIds = {},
    ActiveThreadId = 0,
    LastRoute = "None",
    RouteStatus = "Idle",
    LastTimeWeather = "Unknown",
    LastNextWeather = "Unknown"
}

local Labels = {}

local function cloneTable(source)
    local result = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = cloneTable(value)
        else
            result[key] = value
        end
    end
    return result
end

local function copyCanvasHotbarIds()
    Runtime.HotbarIds = cloneTable(CanvasHotbarIds)
end

copyCanvasHotbarIds()

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

local function shortId(value)
    local text = tostring(value or "")
    if #text <= 8 then
        return text
    end
    return text:sub(1, 8)
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

local function getQuestAction()
    return ReplicatedStorage:WaitForChild("Functions"):WaitForChild("QuestAction")
end

local function getAreaCompletion()
    return ReplicatedStorage:WaitForChild("Functions"):WaitForChild("GetAreaCompletion")
end

local function getTimeRequest()
    return ReplicatedStorage:WaitForChild("Functions"):WaitForChild("TimeRequest")
end

local function getRequestDevWeatherEvent()
    return ReplicatedStorage:WaitForChild("Functions"):WaitForChild("RequestDevWeatherEvent")
end

local function getNpcTalk()
    return ReplicatedStorage:WaitForChild("Functions"):WaitForChild("NPCTalk")
end

local function getBaitShopData()
    return ReplicatedStorage:WaitForChild("Functions"):WaitForChild("GetBaitShopData")
end

local function getPlayerBaitData()
    return ReplicatedStorage:WaitForChild("Functions"):WaitForChild("GetPlayerBaitData")
end

local function getCatchEvent()
    return ReplicatedStorage:WaitForChild("Events"):WaitForChild("CatchEvent")
end

local function getCastEffect()
    return ReplicatedStorage:WaitForChild("Events"):WaitForChild("CastEffect")
end

local function getAutoCatchEvent()
    return ReplicatedStorage:WaitForChild("Events"):WaitForChild("AutoCatchEvent")
end

local function getUpdateHotbarEvent()
    return ReplicatedStorage:WaitForChild("Events"):WaitForChild("UpdateHotbarEvent")
end

local function buildRemoteSummary()
    local functionsFolder = ReplicatedStorage:FindFirstChild("Functions")
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")

    local summary = {
        QuestAction = functionsFolder and functionsFolder:FindFirstChild("QuestAction") ~= nil,
        GetAreaCompletion = functionsFolder and functionsFolder:FindFirstChild("GetAreaCompletion") ~= nil,
        TimeRequest = functionsFolder and functionsFolder:FindFirstChild("TimeRequest") ~= nil,
        RequestDevWeatherEvent = functionsFolder and functionsFolder:FindFirstChild("RequestDevWeatherEvent") ~= nil,
        NPCTalk = functionsFolder and functionsFolder:FindFirstChild("NPCTalk") ~= nil,
        GetBaitShopData = functionsFolder and functionsFolder:FindFirstChild("GetBaitShopData") ~= nil,
        GetPlayerBaitData = functionsFolder and functionsFolder:FindFirstChild("GetPlayerBaitData") ~= nil,
        CatchEvent = eventsFolder and eventsFolder:FindFirstChild("CatchEvent") ~= nil,
        CastEffect = eventsFolder and eventsFolder:FindFirstChild("CastEffect") ~= nil,
        AutoCatchEvent = eventsFolder and eventsFolder:FindFirstChild("AutoCatchEvent") ~= nil,
        UpdateHotbarEvent = eventsFolder and eventsFolder:FindFirstChild("UpdateHotbarEvent") ~= nil
    }

    return summary
end

local function refreshRemoteStatus()
    local summary = buildRemoteSummary()
    local readyCount = 0
    local textParts = {}

    for _, name in ipairs({
        "QuestAction",
        "GetAreaCompletion",
        "TimeRequest",
        "RequestDevWeatherEvent",
        "NPCTalk",
        "GetBaitShopData",
        "GetPlayerBaitData",
        "CatchEvent",
        "CastEffect",
        "AutoCatchEvent",
        "UpdateHotbarEvent"
    }) do
        local ready = summary[name]
        if ready then
            readyCount = readyCount + 1
        end
        table.insert(textParts, name .. "=" .. (ready and "ok" or "missing"))
    end

    setLabel(Labels.RemoteStatus, string.format("Remote Status: %d/11 ready", readyCount))
    setLabel(Labels.CanvasStatus, "Canvas Status: " .. table.concat(textParts, " | "))
end

local function refreshPayloadStatus()
    local text = string.format(
        "Payload Status: Catching %.4f | Cast %.4f | Step %.2f",
        Settings.CatchingValue,
        Settings.CastEffectValue,
        Settings.StepDelay
    )
    setLabel(Labels.PayloadStatus, text)
end

local function refreshStageStatus()
    local profile = StageProfiles[Settings.StageProfileName] or StageProfiles["Canvas Balanced"]
    local text = string.format(
        "Stage Status: %s | %d ms | %d transitions",
        Settings.StageProfileName,
        profile.durationMs,
        profile.holdTransitions
    )
    setLabel(Labels.StageStatus, text)
end

local function refreshHotbarStatus()
    local text = string.format("Hotbar Status: %s | %s | %d slots", Settings.HotbarPresetName, Settings.NetTool, Settings.HotbarSlots)
    setLabel(Labels.HotbarStatus, text)
end

local function refreshSessionStatus()
    local text = string.format(
        "Session Status: %s / %s | SID %d-%d | Seq %d-%d",
        shortId(Runtime.SessionNonce),
        shortId(Runtime.StageNonce),
        Runtime.CatchSid,
        Runtime.StageSid,
        Runtime.CatchSeq,
        Runtime.StageSeq
    )
    setLabel(Labels.SessionStatus, text)
end

local function refreshLastRoute()
    setLabel(Labels.LastRoute, "Last Route: " .. Runtime.LastRoute)
end

local function setRouteStatus(text)
    Runtime.RouteStatus = text
    setLabel(Labels.RouteStatus, "Route Status: " .. text)
end

local function setLoopStatus(text)
    setLabel(Labels.LoopStatus, "Loop Status: " .. text)
end

local function refreshTimeWeatherStatus()
    setLabel(Labels.TimeWeatherStatus, "Time Weather Status: " .. Runtime.LastTimeWeather)
    setLabel(Labels.NextWeatherStatus, "Next Weather Status: " .. Runtime.LastNextWeather)
end

local function applyTimeWeatherResult(result)
    if type(result) ~= "table" then
        Runtime.LastTimeWeather = "Unexpected response"
        Runtime.LastNextWeather = "No weatherState data"
        refreshTimeWeatherStatus()
        return
    end

    local timeText = tostring(result.time or "Unknown")
    local phaseText = tostring(result.phase or "Unknown")
    local weatherText = tostring(result.weather or "Unknown")
    local progressValue = tonumber(result.progress)
    local progressText = progressValue and string.format("%.1f%%", progressValue * 100) or "n/a"

    Runtime.LastTimeWeather = string.format("%s | %s | %s | %s", timeText, phaseText, weatherText, progressText)

    local weatherState = result.weatherState
    if type(weatherState) == "table" then
        local nextName = tostring(weatherState.nextWeatherDisplayName or weatherState.nextWeatherId or "Unknown")
        local nextSeconds = tonumber(weatherState.nextWeatherStartsIn)
        local nextSecondsText = nextSeconds and tostring(math.max(0, math.floor(nextSeconds + 0.5))) or "n/a"
        local activeText = weatherState.isActive and "active" or "idle"
        Runtime.LastNextWeather = string.format("%s in %ss | %s", nextName, nextSecondsText, activeText)
    else
        Runtime.LastNextWeather = "No weatherState data"
    end

    refreshTimeWeatherStatus()
end

local function applyCanvasDefaults()
    Settings.CatchingPresetName = "Canvas"
    Settings.CastPresetName = "Canvas"
    Settings.CatchingValue = CatchingPresets.Canvas
    Settings.CastEffectValue = CastEffectPresets.Canvas
    Settings.StageProfileName = "Canvas Balanced"
    Settings.GroundDurationMs = 21500
    Settings.SwatCount = 8
    Settings.Area = "Grasslands"
    Settings.EquipNetName = "Carbon Net"
    Settings.NetTool = "FlimsyNet"
    Settings.HotbarPresetName = "Canvas"
    Settings.HotbarSlots = 6
    Settings.LossReason = "timeout"
    Settings.NpcName = "Bob"
    Settings.WeatherName = "Heatwave"
    Settings.StepDelay = 0.15
    Settings.LoopDelay = 1.00
    Settings.BurstCount = 3
    Settings.AutoRefreshSession = true
    Settings.AlternateFirstRoute = "Win"

    Runtime.SessionNonce = "496ed4fd-adee-4a8a-a2e0-5064d1d79c74"
    Runtime.StageNonce = "31d7c1a5-1b61-4673-8fdb-9dfea4469fd1"
    Runtime.CatchSid = 12788
    Runtime.CatchSeq = 9
    Runtime.StageSid = 13012
    Runtime.StageSeq = 17
    Runtime.LastRoute = "Canvas defaults loaded"
    copyCanvasHotbarIds()

    refreshPayloadStatus()
    refreshStageStatus()
    refreshHotbarStatus()
    refreshSessionStatus()
    refreshLastRoute()
    setLabel(Labels.AutoCatchStatus, "Auto Catch Status: Idle")
    Runtime.LastTimeWeather = "Unknown"
    Runtime.LastNextWeather = "Unknown"
    refreshTimeWeatherStatus()
    setRouteStatus("Canvas defaults loaded")
end

local function applyCarbonNetPreset()
    Settings.EquipNetName = "Carbon Net"
    Settings.NetTool = "CarbonNet"
    Settings.HotbarPresetName = "Carbon"
    Settings.HotbarSlots = 6
    Runtime.HotbarIds[1] = CarbonHotbarId
    Runtime.LastRoute = "Carbon preset loaded"

    refreshHotbarStatus()
    refreshLastRoute()
    setRouteStatus("Carbon preset loaded")
end

local function generateFreshSession()
    Runtime.SessionNonce = string.lower(HttpService:GenerateGUID(false))
    Runtime.StageNonce = string.lower(HttpService:GenerateGUID(false))
    Runtime.CatchSid = Rng:NextInteger(12000, 19999)
    Runtime.CatchSeq = Rng:NextInteger(7, 18)
    Runtime.StageSid = Runtime.CatchSid + Rng:NextInteger(100, 900)
    Runtime.StageSeq = Runtime.CatchSeq + Rng:NextInteger(4, 12)

    Runtime.HotbarIds = {}
    if Settings.HotbarPresetName == "Carbon" then
        Runtime.HotbarIds[1] = CarbonHotbarId
    else
        for index = 1, 5 do
            Runtime.HotbarIds[index] = string.lower(HttpService:GenerateGUID(false))
        end
    end

    Runtime.LastRoute = "Fresh session generated"
    refreshSessionStatus()
    refreshLastRoute()
    setRouteStatus("Fresh session generated")
end

local function prepareSession()
    if Settings.AutoRefreshSession then
        generateFreshSession()
    else
        refreshSessionStatus()
    end
end

local function getStagePayload()
    local profile = StageProfiles[Settings.StageProfileName] or StageProfiles["Canvas Balanced"]
    return {
        nonce = Runtime.StageNonce,
        durationMs = profile.durationMs,
        holdTransitions = profile.holdTransitions,
        localSuccess = profile.localSuccess,
        outsideMs = profile.outsideMs,
        holdTrace = cloneTable(profile.holdTrace),
        insideMs = profile.insideMs,
        seq = Runtime.StageSeq,
        sid = Runtime.StageSid
    }
end

local function getReeledPayload()
    return {
        groundDurationMs = Settings.GroundDurationMs,
        nonce = Runtime.SessionNonce,
        sid = Runtime.CatchSid,
        swatCount = Settings.SwatCount,
        seq = Runtime.CatchSeq,
        reason = Settings.LossReason
    }
end

local function getHotbarPayload()
    if Settings.HotbarPresetName == "Carbon" then
        return {
            ["1"] = "CarbonNet",
            _hotbarSlots = Settings.HotbarSlots,
            ["4"] = Runtime.HotbarIds[1] or CarbonHotbarId
        }
    end

    return {
        ["1"] = Settings.NetTool,
        ["4"] = Runtime.HotbarIds[1],
        ["5"] = Runtime.HotbarIds[2],
        ["6"] = Runtime.HotbarIds[3],
        ["7"] = Runtime.HotbarIds[4],
        ["8"] = Runtime.HotbarIds[5],
        _hotbarSlots = Settings.HotbarSlots
    }
end

local function encodeJson(data)
    local success, result = pcall(function()
        return HttpService:JSONEncode(data)
    end)

    if success then
        return result
    end

    return tostring(data)
end

local function runRemoteAction(name, callback)
    local success, result = pcall(callback)

    if success then
        setRouteStatus(name .. " sent")
        return true, result
    end

    warn("[Catch Farm Test] " .. name .. " failed: " .. tostring(result))
    setRouteStatus(name .. " failed")
    notify(name, tostring(result), 5)
    return false, result
end

local function sendCatchStart()
    return runRemoteAction("CatchStart", function()
        local args = {
            {
                type = "CatchStart"
            }
        }
        return getQuestAction():InvokeServer(unpack(args))
    end)
end

local function sendEquipNet()
    return runRemoteAction("EquipNet", function()
        local args = {
            {
                type = "EquipNet",
                netName = Settings.EquipNetName
            }
        }
        return getQuestAction():InvokeServer(unpack(args))
    end)
end

local function sendCatchingV2()
    return runRemoteAction("CatchingV2", function()
        return getCatchEvent():FireServer("CatchingV2", Settings.CatchingValue)
    end)
end

local function sendStartAutoCatch()
    return runRemoteAction("StartAutoCatch", function()
        local result = getAutoCatchEvent():FireServer("Start")
        setLabel(Labels.AutoCatchStatus, "Auto Catch Status: Running")
        return result
    end)
end

local function sendStopAutoCatch()
    return runRemoteAction("StopAutoCatch", function()
        local result = getAutoCatchEvent():FireServer("Stop")
        setLabel(Labels.AutoCatchStatus, "Auto Catch Status: Stopped")
        return result
    end)
end

local function sendCastEffect()
    return runRemoteAction("CastEffect", function()
        return getCastEffect():FireServer(Settings.CastEffectValue)
    end)
end

local function sendReeledV2()
    return runRemoteAction("ReeledV2", function()
        return getCatchEvent():FireServer("ReeledV2", getReeledPayload())
    end)
end

local function sendCancelCatchV2()
    return runRemoteAction("CancelCatchV2", function()
        return getCatchEvent():FireServer("CancelCatchV2")
    end)
end

local function sendStage2ResultV2()
    return runRemoteAction("Stage2ResultV2", function()
        return getCatchEvent():FireServer("Stage2ResultV2", getStagePayload())
    end)
end

local function requestAreaCompletion()
    return runRemoteAction("GetAreaCompletion", function()
        local args = {
            Settings.Area
        }
        return getAreaCompletion():InvokeServer(unpack(args))
    end)
end

local function requestTime()
    local success, result = runRemoteAction("TimeRequest", function()
        return getTimeRequest():InvokeServer()
    end)

    if success then
        applyTimeWeatherResult(result)
    end

    return success, result
end

local function requestDevWeather()
    return runRemoteAction("RequestDevWeatherEvent", function()
        local args = {
            Settings.WeatherName
        }
        return getRequestDevWeatherEvent():InvokeServer(unpack(args))
    end)
end

local function sendHotbarSync()
    return runRemoteAction("UpdateHotbarEvent", function()
        local args = {
            getHotbarPayload()
        }
        return getUpdateHotbarEvent():FireServer(unpack(args))
    end)
end

local function sendNpcTalk()
    return runRemoteAction("NPCTalk", function()
        local args = {
            Settings.NpcName
        }
        return getNpcTalk():InvokeServer(unpack(args))
    end)
end

local function requestBaitShopData()
    return runRemoteAction("GetBaitShopData", function()
        return getBaitShopData():InvokeServer()
    end)
end

local function requestPlayerBaitData()
    return runRemoteAction("GetPlayerBaitData", function()
        return getPlayerBaitData():InvokeServer()
    end)
end

local function waitStep()
    if Settings.StepDelay > 0 then
        task.wait(Settings.StepDelay)
    end
end

local function runSteps(steps)
    for index, step in ipairs(steps) do
        local success = step()
        if not success then
            return false
        end

        if index < #steps then
            waitStep()
        end
    end

    return true
end

local function runOpeningChain()
    prepareSession()

    local success = runSteps({
        function()
            return sendCatchStart()
        end,
        function()
            return sendCatchingV2()
        end,
        function()
            return sendCastEffect()
        end
    })

    if success then
        Runtime.LastRoute = "Opening chain"
        refreshLastRoute()
        setRouteStatus("Opening chain completed")
    end

    return success
end

local function runFullLossRoute()
    local success = runOpeningChain()
    if not success then
        return false
    end

    success = runSteps({
        function()
            return sendReeledV2()
        end,
        function()
            return sendReeledV2()
        end,
        function()
            return sendCancelCatchV2()
        end
    })

    if success then
        Runtime.LastRoute = "Full loss route"
        refreshLastRoute()
        setRouteStatus("Full loss route completed")
    end

    return success
end

local function runFullWinRoute()
    local success = runOpeningChain()
    if not success then
        return false
    end

    success = runSteps({
        function()
            return sendReeledV2()
        end,
        function()
            return sendStage2ResultV2()
        end,
        function()
            return requestAreaCompletion()
        end,
        function()
            return sendHotbarSync()
        end
    })

    if success then
        Runtime.LastRoute = "Full win route"
        refreshLastRoute()
        setRouteStatus("Full win route completed")
    end

    return success
end

local function runAutoCatchSetup()
    local success = runSteps({
        function()
            return sendEquipNet()
        end,
        function()
            return requestAreaCompletion()
        end,
        function()
            return sendHotbarSync()
        end,
        function()
            return sendStartAutoCatch()
        end
    })

    if success then
        Runtime.LastRoute = "Auto catch setup"
        refreshLastRoute()
        setRouteStatus("Auto catch setup completed")
    end

    return success
end

local function runNpcAndBaitSweep()
    local success = runSteps({
        function()
            return sendNpcTalk()
        end,
        function()
            return requestBaitShopData()
        end,
        function()
            return requestPlayerBaitData()
        end
    })

    if success then
        Runtime.LastRoute = "NPC and bait sweep"
        refreshLastRoute()
        setRouteStatus("NPC and bait sweep completed")
    end

    return success
end

local function runDevWeatherPurchaseFlow()
    local success = runSteps({
        function()
            return requestTime()
        end,
        function()
            return requestDevWeather()
        end
    })

    if success then
        Runtime.LastRoute = "Dev weather purchase flow"
        refreshLastRoute()
        setRouteStatus("Dev weather purchase flow completed")
    end

    return success
end

local function stopActiveLoops(showNotification)
    Runtime.ActiveThreadId = Runtime.ActiveThreadId + 1
    setLoopStatus("Idle")

    if showNotification ~= false then
        notify("Route Loop", "Active loops stopped", 3)
    end
end

local function runBurst(mode)
    stopActiveLoops(false)

    Runtime.ActiveThreadId = Runtime.ActiveThreadId + 1
    local threadId = Runtime.ActiveThreadId
    local burstCount = Settings.BurstCount

    setLoopStatus(mode .. " burst x" .. tostring(burstCount))
    notify("Route Burst", mode .. " burst started", 3)

    task.spawn(function()
        local nextAlternate = Settings.AlternateFirstRoute

        for index = 1, burstCount do
            if Runtime.ActiveThreadId ~= threadId then
                return
            end

            if mode == "Win" then
                runFullWinRoute()
            elseif mode == "Loss" then
                runFullLossRoute()
            else
                if nextAlternate == "Win" then
                    runFullWinRoute()
                    nextAlternate = "Loss"
                else
                    runFullLossRoute()
                    nextAlternate = "Win"
                end
            end

            if Runtime.ActiveThreadId ~= threadId then
                return
            end

            if index < burstCount then
                task.wait(Settings.LoopDelay)
            end
        end

        if Runtime.ActiveThreadId == threadId then
            setLoopStatus("Idle")
            notify("Route Burst", mode .. " burst finished", 3)
        end
    end)
end

local function startContinuousLoop(mode)
    stopActiveLoops(false)

    Runtime.ActiveThreadId = Runtime.ActiveThreadId + 1
    local threadId = Runtime.ActiveThreadId

    setLoopStatus(mode .. " loop")
    notify("Route Loop", mode .. " loop started", 3)

    task.spawn(function()
        local nextAlternate = Settings.AlternateFirstRoute

        while Runtime.ActiveThreadId == threadId do
            if mode == "Win" then
                runFullWinRoute()
            elseif mode == "Loss" then
                runFullLossRoute()
            elseif mode == "Alternate" then
                if nextAlternate == "Win" then
                    runFullWinRoute()
                    nextAlternate = "Loss"
                else
                    runFullLossRoute()
                    nextAlternate = "Win"
                end
            else
                runOpeningChain()
            end

            if Runtime.ActiveThreadId ~= threadId then
                return
            end

            task.wait(Settings.LoopDelay)
        end
    end)
end

local function printCurrentPayloads()
    print("[Catch Farm Test] CatchStart => " .. encodeJson({
        {
            type = "CatchStart"
        }
    }))
    print("[Catch Farm Test] EquipNet => " .. encodeJson({
        {
            type = "EquipNet",
            netName = Settings.EquipNetName
        }
    }))
    print("[Catch Farm Test] CatchingV2 => " .. encodeJson({
        "CatchingV2",
        Settings.CatchingValue
    }))
    print("[Catch Farm Test] CastEffect => " .. encodeJson({
        Settings.CastEffectValue
    }))
    print("[Catch Farm Test] AutoCatch Start => " .. encodeJson({
        "Start"
    }))
    print("[Catch Farm Test] AutoCatch Stop => " .. encodeJson({
        "Stop"
    }))
    print("[Catch Farm Test] ReeledV2 => " .. encodeJson({
        "ReeledV2",
        getReeledPayload()
    }))
    print("[Catch Farm Test] Stage2ResultV2 => " .. encodeJson({
        "Stage2ResultV2",
        getStagePayload()
    }))
    print("[Catch Farm Test] GetAreaCompletion => " .. encodeJson({
        Settings.Area
    }))
    print("[Catch Farm Test] TimeRequest => []")
    print("[Catch Farm Test] RequestDevWeatherEvent => " .. encodeJson({
        Settings.WeatherName
    }))
    print("[Catch Farm Test] UpdateHotbarEvent => " .. encodeJson({
        getHotbarPayload()
    }))
    print("[Catch Farm Test] NPCTalk => " .. encodeJson({
        Settings.NpcName
    }))
    print("[Catch Farm Test] GetBaitShopData => []")
    print("[Catch Farm Test] GetPlayerBaitData => []")
    notify("Payloads", "Current payloads printed to console", 4)
end

local function printRemoteSummary()
    local summary = buildRemoteSummary()
    for _, name in ipairs({
        "QuestAction",
        "GetAreaCompletion",
        "TimeRequest",
        "RequestDevWeatherEvent",
        "NPCTalk",
        "GetBaitShopData",
        "GetPlayerBaitData",
        "CatchEvent",
        "CastEffect",
        "AutoCatchEvent",
        "UpdateHotbarEvent"
    }) do
        print("[Catch Farm Test] " .. name .. " => " .. (summary[name] and "ready" or "missing"))
    end
    notify("Remotes", "Remote summary printed to console", 4)
end

local function quickSessionRefresh()
    generateFreshSession()
    refreshRemoteStatus()
    refreshPayloadStatus()
    refreshStageStatus()
    refreshHotbarStatus()
    notify("Session", "Fresh session and remote status updated", 4)
end

LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local StartTab = Window:CreateTab("Start", 4483362458)
local OutcomesTab = Window:CreateTab("Outcomes", 4483362458)
local AutomationTab = Window:CreateTab("Automation", 4483362458)
local DebugTab = Window:CreateTab("Debug", 4483362458)

StartTab:CreateSection("🎣 Opening Route")

StartTab:CreateButton({
    Name = "Refresh Route Remotes",
    Callback = function()
        refreshRemoteStatus()
        notify("Remotes", "Route remotes refreshed", 3)
    end
})

StartTab:CreateButton({
    Name = "Send EquipNet",
    Callback = function()
        sendEquipNet()
    end
})

StartTab:CreateButton({
    Name = "Send CatchStart",
    Callback = function()
        sendCatchStart()
    end
})

StartTab:CreateButton({
    Name = "Send CatchingV2",
    Callback = function()
        sendCatchingV2()
    end
})

StartTab:CreateButton({
    Name = "Send CastEffect",
    Callback = function()
        sendCastEffect()
    end
})

StartTab:CreateButton({
    Name = "Run Opening Chain",
    Callback = function()
        task.spawn(runOpeningChain)
    end
})

Labels.RemoteStatus = StartTab:CreateLabel("Remote Status: Not scanned")

StartTab:CreateSection("⚙ Opening Presets")

StartTab:CreateDropdown({
    Name = "Catching Preset",
    Options = {"Canvas", "Fast", "Stable", "Wide"},
    CurrentOption = {"Canvas"},
    MultipleOptions = false,
    Flag = "CFT_CatchingPreset",
    Callback = function(option)
        local selected = optionToString(option)
        Settings.CatchingPresetName = selected
        Settings.CatchingValue = CatchingPresets[selected] or CatchingPresets.Canvas
        refreshPayloadStatus()
    end
})

StartTab:CreateDropdown({
    Name = "Cast Effect Preset",
    Options = {"Canvas", "Soft", "Stable", "Hard"},
    CurrentOption = {"Canvas"},
    MultipleOptions = false,
    Flag = "CFT_CastPreset",
    Callback = function(option)
        local selected = optionToString(option)
        Settings.CastPresetName = selected
        Settings.CastEffectValue = CastEffectPresets[selected] or CastEffectPresets.Canvas
        refreshPayloadStatus()
    end
})

StartTab:CreateDropdown({
    Name = "Step Delay",
    Options = {"0.05", "0.15", "0.30", "0.50"},
    CurrentOption = {"0.15"},
    MultipleOptions = false,
    Flag = "CFT_StepDelay",
    Callback = function(option)
        Settings.StepDelay = optionToNumber(option, Settings.StepDelay)
        refreshPayloadStatus()
    end
})

StartTab:CreateToggle({
    Name = "Auto Refresh Session",
    CurrentValue = true,
    Flag = "CFT_AutoRefreshSession",
    Callback = function(value)
        Settings.AutoRefreshSession = value
    end
})

StartTab:CreateButton({
    Name = "Generate Fresh Session",
    Callback = function()
        generateFreshSession()
        notify("Session", "Fresh session generated", 3)
    end
})

StartTab:CreateButton({
    Name = "Reset Canvas Defaults",
    Callback = function()
        applyCanvasDefaults()
        notify("Canvas", "Canvas defaults restored", 3)
    end
})

StartTab:CreateButton({
    Name = "Use Carbon Net Preset",
    Callback = function()
        applyCarbonNetPreset()
        notify("Carbon", "Carbon net preset loaded", 3)
    end
})

Labels.PayloadStatus = StartTab:CreateLabel("Payload Status: Catching 1.9028 | Cast 0.9028 | Step 0.15")
Labels.SessionStatus = StartTab:CreateLabel("Session Status: Canvas IDs loaded")
Labels.AutoCatchStatus = StartTab:CreateLabel("Auto Catch Status: Idle")
StartTab:CreateLabel("Anti AFK is always active")

OutcomesTab:CreateSection("🏁 Route Finish")

OutcomesTab:CreateButton({
    Name = "Send ReeledV2",
    Callback = function()
        sendReeledV2()
    end
})

OutcomesTab:CreateButton({
    Name = "Send CancelCatchV2",
    Callback = function()
        sendCancelCatchV2()
    end
})

OutcomesTab:CreateButton({
    Name = "Send Stage2ResultV2",
    Callback = function()
        sendStage2ResultV2()
    end
})

OutcomesTab:CreateButton({
    Name = "Request Area Completion",
    Callback = function()
        requestAreaCompletion()
    end
})

OutcomesTab:CreateButton({
    Name = "Request Time",
    Callback = function()
        requestTime()
    end
})

OutcomesTab:CreateButton({
    Name = "Request Dev Weather",
    Callback = function()
        requestDevWeather()
    end
})

OutcomesTab:CreateButton({
    Name = "Send Hotbar Sync",
    Callback = function()
        sendHotbarSync()
    end
})

OutcomesTab:CreateButton({
    Name = "Start Auto Catch",
    Callback = function()
        sendStartAutoCatch()
    end
})

OutcomesTab:CreateButton({
    Name = "Stop Auto Catch",
    Callback = function()
        sendStopAutoCatch()
    end
})

OutcomesTab:CreateButton({
    Name = "Run Auto Catch Setup",
    Callback = function()
        task.spawn(runAutoCatchSetup)
    end
})

OutcomesTab:CreateButton({
    Name = "Run Dev Weather Flow",
    Callback = function()
        task.spawn(runDevWeatherPurchaseFlow)
    end
})

OutcomesTab:CreateButton({
    Name = "Run Full Loss Route",
    Callback = function()
        task.spawn(runFullLossRoute)
    end
})

OutcomesTab:CreateButton({
    Name = "Run Full Win Route",
    Callback = function()
        task.spawn(runFullWinRoute)
    end
})

Labels.LastRoute = OutcomesTab:CreateLabel("Last Route: None")

OutcomesTab:CreateSection("🧪 Finish Presets")

OutcomesTab:CreateDropdown({
    Name = "Stage Profile",
    Options = {"Canvas Balanced", "Perfect Hold", "Short Hold", "Long Hold"},
    CurrentOption = {"Canvas Balanced"},
    MultipleOptions = false,
    Flag = "CFT_StageProfile",
    Callback = function(option)
        Settings.StageProfileName = optionToString(option)
        refreshStageStatus()
    end
})

OutcomesTab:CreateDropdown({
    Name = "Ground Duration",
    Options = {"12500", "17500", "21500", "30000"},
    CurrentOption = {"21500"},
    MultipleOptions = false,
    Flag = "CFT_GroundDuration",
    Callback = function(option)
        Settings.GroundDurationMs = optionToNumber(option, Settings.GroundDurationMs)
    end
})

OutcomesTab:CreateDropdown({
    Name = "Swat Count",
    Options = {"4", "6", "8", "12"},
    CurrentOption = {"8"},
    MultipleOptions = false,
    Flag = "CFT_SwatCount",
    Callback = function(option)
        Settings.SwatCount = optionToNumber(option, Settings.SwatCount)
    end
})

OutcomesTab:CreateDropdown({
    Name = "Area Name",
    Options = {"Grasslands"},
    CurrentOption = {"Grasslands"},
    MultipleOptions = false,
    Flag = "CFT_AreaName",
    Callback = function(option)
        Settings.Area = optionToString(option)
    end
})

OutcomesTab:CreateDropdown({
    Name = "Weather Name",
    Options = {"Heatwave"},
    CurrentOption = {"Heatwave"},
    MultipleOptions = false,
    Flag = "CFT_WeatherName",
    Callback = function(option)
        Settings.WeatherName = optionToString(option)
    end
})

OutcomesTab:CreateDropdown({
    Name = "Equip Net Name",
    Options = {"Carbon Net"},
    CurrentOption = {"Carbon Net"},
    MultipleOptions = false,
    Flag = "CFT_EquipNetName",
    Callback = function(option)
        Settings.EquipNetName = optionToString(option)
    end
})

OutcomesTab:CreateDropdown({
    Name = "Net Tool",
    Options = {"FlimsyNet", "CarbonNet"},
    CurrentOption = {"FlimsyNet"},
    MultipleOptions = false,
    Flag = "CFT_NetTool",
    Callback = function(option)
        Settings.NetTool = optionToString(option)
        if Settings.NetTool == "CarbonNet" then
            Settings.HotbarPresetName = "Carbon"
            Runtime.HotbarIds[1] = Runtime.HotbarIds[1] or CarbonHotbarId
        elseif Settings.HotbarPresetName == "Carbon" then
            Settings.HotbarPresetName = "Canvas"
            if not Runtime.HotbarIds[2] then
                copyCanvasHotbarIds()
            end
        end
        refreshHotbarStatus()
    end
})

OutcomesTab:CreateDropdown({
    Name = "Hotbar Slots",
    Options = {"4", "5", "6", "8"},
    CurrentOption = {"6"},
    MultipleOptions = false,
    Flag = "CFT_HotbarSlots",
    Callback = function(option)
        Settings.HotbarSlots = optionToNumber(option, Settings.HotbarSlots)
        refreshHotbarStatus()
    end
})

Labels.StageStatus = OutcomesTab:CreateLabel("Stage Status: Canvas Balanced")
Labels.HotbarStatus = OutcomesTab:CreateLabel("Hotbar Status: Canvas | FlimsyNet | 6 slots")

AutomationTab:CreateSection("🔁 Burst Tests")

AutomationTab:CreateDropdown({
    Name = "Burst Count",
    Options = {"1", "3", "5", "10"},
    CurrentOption = {"3"},
    MultipleOptions = false,
    Flag = "CFT_BurstCount",
    Callback = function(option)
        Settings.BurstCount = optionToNumber(option, Settings.BurstCount)
    end
})

AutomationTab:CreateDropdown({
    Name = "Loop Delay",
    Options = {"0.25", "0.50", "1.00", "2.00", "4.00"},
    CurrentOption = {"1.00"},
    MultipleOptions = false,
    Flag = "CFT_LoopDelay",
    Callback = function(option)
        Settings.LoopDelay = optionToNumber(option, Settings.LoopDelay)
    end
})

AutomationTab:CreateDropdown({
    Name = "Alternate First Route",
    Options = {"Win", "Loss"},
    CurrentOption = {"Win"},
    MultipleOptions = false,
    Flag = "CFT_AlternateFirstRoute",
    Callback = function(option)
        Settings.AlternateFirstRoute = optionToString(option)
    end
})

AutomationTab:CreateButton({
    Name = "Run Win Burst",
    Callback = function()
        runBurst("Win")
    end
})

AutomationTab:CreateButton({
    Name = "Run Loss Burst",
    Callback = function()
        runBurst("Loss")
    end
})

AutomationTab:CreateButton({
    Name = "Run Alternate Burst",
    Callback = function()
        runBurst("Alternate")
    end
})

AutomationTab:CreateSection("🚀 Continuous Loops")

AutomationTab:CreateButton({
    Name = "Start Auto Win",
    Callback = function()
        startContinuousLoop("Win")
    end
})

AutomationTab:CreateButton({
    Name = "Start Auto Loss",
    Callback = function()
        startContinuousLoop("Loss")
    end
})

AutomationTab:CreateButton({
    Name = "Start Auto Alternate",
    Callback = function()
        startContinuousLoop("Alternate")
    end
})

AutomationTab:CreateButton({
    Name = "Start Auto Opening",
    Callback = function()
        startContinuousLoop("Opening")
    end
})

AutomationTab:CreateButton({
    Name = "Stop Active Loops",
    Callback = function()
        stopActiveLoops(true)
    end
})

AutomationTab:CreateKeybind({
    Name = "Stop Active Loops Key",
    CurrentKeybind = "None",
    HoldToInteract = false,
    Flag = "CFT_StopLoopsKey",
    Callback = function()
        stopActiveLoops(true)
    end
})

Labels.LoopStatus = AutomationTab:CreateLabel("Loop Status: Idle")

DebugTab:CreateSection("🛰 Diagnostics")

DebugTab:CreateButton({
    Name = "Print Current Payloads",
    Callback = function()
        printCurrentPayloads()
    end
})

DebugTab:CreateButton({
    Name = "Print Remote Summary",
    Callback = function()
        printRemoteSummary()
    end
})

DebugTab:CreateButton({
    Name = "Run Quick Session Refresh",
    Callback = function()
        quickSessionRefresh()
    end
})

DebugTab:CreateSection("🗣 NPC And Bait")

DebugTab:CreateButton({
    Name = "Talk To NPC",
    Callback = function()
        sendNpcTalk()
    end
})

DebugTab:CreateButton({
    Name = "Request Bait Shop Data",
    Callback = function()
        requestBaitShopData()
    end
})

DebugTab:CreateButton({
    Name = "Request Player Bait Data",
    Callback = function()
        requestPlayerBaitData()
    end
})

DebugTab:CreateButton({
    Name = "Run NPC And Bait Sweep",
    Callback = function()
        task.spawn(runNpcAndBaitSweep)
    end
})

DebugTab:CreateDropdown({
    Name = "NPC Name",
    Options = {"Bob"},
    CurrentOption = {"Bob"},
    MultipleOptions = false,
    Flag = "CFT_NpcName",
    Callback = function(option)
        Settings.NpcName = optionToString(option)
    end
})

Labels.CanvasStatus = DebugTab:CreateLabel("Canvas Status: Not checked")
Labels.RouteStatus = DebugTab:CreateLabel("Route Status: Idle")
Labels.TimeWeatherStatus = DebugTab:CreateLabel("Time Weather Status: Unknown")
Labels.NextWeatherStatus = DebugTab:CreateLabel("Next Weather Status: Unknown")
DebugTab:CreateLabel("Canvas Flow: CatchStart -> CatchingV2 -> CastEffect")
DebugTab:CreateLabel("Canvas Branches: ReeledV2 -> Loss / Win")

applyCanvasDefaults()
refreshRemoteStatus()
setLoopStatus("Idle")
