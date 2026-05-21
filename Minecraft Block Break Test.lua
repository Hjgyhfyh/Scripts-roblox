local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"))()

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local BreakRemote
do
    local ok, remote = pcall(function()
        return ReplicatedStorage:WaitForChild("Systems", 10)
            :WaitForChild("ActionsSystem", 10)
            :WaitForChild("Network", 10)
            :WaitForChild("Break", 10)
    end)
    if ok then BreakRemote = remote end
end

local State = {
    autoReplay = false,
    replayDelay = 0.20,

    clickBreak = false,
    clickRange = 30,

    bruteForce = false,
    bruteAxisIndex = 3,
    bruteRange = 5,
    bruteDelay = 0.10,

    arg1 = 2,
    arg2 = 74,
    arg3 = 55874,
    arg4 = 8,
    arg5 = 6,

    logEnabled = false,
    logs = {},
    lastIncomingArgs = nil,

    successCount = 0,
    failCount = 0,
}

local UI

local function notify(title, content)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = tostring(title),
            Text = tostring(content),
            Duration = 3,
        })
    end)
end

local function getArgsFromState()
    local arg1Str = (State.arg1 >= 0)
        and (tostring(math.floor(State.arg1)) .. ".0")
        or ("-" .. tostring(math.abs(math.floor(State.arg1))) .. ".0")
    return {
        arg1Str,
        tostring(math.floor(State.arg2 + 0.5)),
        tostring(math.floor(State.arg3 + 0.5)),
        math.floor(State.arg4 + 0.5),
        math.floor(State.arg5 + 0.5),
    }
end

local function setSliderValue(tabName, moduleName, sectionName, controlName, value)
    if not UI then return end
    pcall(function()
        UI:SetControlValue(tabName, moduleName, sectionName, controlName, value)
    end)
end

local function pushArgsToState(args)
    if not args or #args < 5 then return end
    local y = tonumber(tostring(args[1]):match("^(-?%d+)")) or 0
    State.arg1 = y
    State.arg2 = tonumber(args[2]) or 0
    State.arg3 = tonumber(args[3]) or 0
    State.arg4 = tonumber(args[4]) or 0
    State.arg5 = tonumber(args[5]) or 0

    setSliderValue("Manual", "Manual Args", "Args", "arg1 Y", State.arg1)
    setSliderValue("Manual", "Manual Args", "Args", "arg2 ChunkX", State.arg2)
    setSliderValue("Manual", "Manual Args", "Args", "arg3 ChunkZ", State.arg3)
    setSliderValue("Manual", "Manual Args", "Args", "arg4", State.arg4)
    setSliderValue("Manual", "Manual Args", "Args", "arg5", State.arg5)
end

local function callBreak(args)
    if not BreakRemote then return false, "Break remote not found" end
    if not args or #args < 5 then return false, "Need 5 arguments" end
    local ok, err = pcall(function()
        BreakRemote:InvokeServer(args[1], args[2], args[3], args[4], args[5])
    end)
    if ok then
        State.successCount = State.successCount + 1
    else
        State.failCount = State.failCount + 1
    end
    return ok, err
end

local function fireOnce(tabName, moduleName, sectionName, controlName, fn)
    return function(state)
        if state then
            fn()
            task.delay(0.05, function()
                if UI then
                    pcall(function()
                        UI:SetControlValue(tabName, moduleName, sectionName, controlName, false)
                    end)
                end
            end)
        end
    end
end

pcall(function()
    local hookFn = function(self, ...)
        local method
        local ok = pcall(function() method = getnamecallmethod() end)
        if ok and self == BreakRemote and method == "InvokeServer" and State.logEnabled then
            local args = { ... }
            State.lastIncomingArgs = args
            table.insert(State.logs, 1, { t = os.time(), args = args })
            if #State.logs > 100 then table.remove(State.logs) end
        end
    end

    if hookmetamethod then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            hookFn(self, ...)
            return oldNamecall(self, ...)
        end)
    elseif getrawmetatable then
        local mt = getrawmetatable(game)
        if setreadonly then setreadonly(mt, false) end
        local oldNamecall = mt.__namecall
        mt.__namecall = function(self, ...)
            hookFn(self, ...)
            return oldNamecall(self, ...)
        end
        if setreadonly then setreadonly(mt, true) end
    end
end)

task.spawn(function()
    while task.wait() do
        if State.autoReplay then
            local src = State.lastIncomingArgs or getArgsFromState()
            callBreak(src)
            task.wait(math.max(tonumber(State.replayDelay) or 0.2, 0.01))
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if State.bruteForce then
            local base = State.lastIncomingArgs or getArgsFromState()
            local copy = { base[1], base[2], base[3], base[4], base[5] }
            local idx = State.bruteAxisIndex
            local range = math.max(tonumber(State.bruteRange) or 1, 1)
            for delta = -range, range do
                if not State.bruteForce then break end
                local args = { copy[1], copy[2], copy[3], copy[4], copy[5] }
                if idx == 1 then
                    args[2] = tostring((tonumber(copy[2]) or 0) + delta)
                elseif idx == 2 then
                    args[3] = tostring((tonumber(copy[3]) or 0) + delta)
                elseif idx == 3 then
                    args[4] = (tonumber(copy[4]) or 0) + delta
                elseif idx == 4 then
                    args[5] = (tonumber(copy[5]) or 0) + delta
                elseif idx == 5 then
                    args[4] = (tonumber(copy[4]) or 0) + delta
                    args[5] = (tonumber(copy[5]) or 0) + delta
                end
                callBreak(args)
                task.wait(math.max(tonumber(State.bruteDelay) or 0.1, 0.01))
            end
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if not State.clickBreak then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

    local target = Mouse.Target
    if not target then
        notify("Click Break", "No target under mouse")
        return
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and (target.Position - hrp.Position).Magnitude > State.clickRange then
        notify("Click Break", "Target out of range")
        return
    end

    local args
    local attrs = target:GetAttributes() or {}
    if attrs.Y and attrs.ChunkX and attrs.ChunkZ and attrs.LocalX and attrs.LocalZ then
        args = {
            tostring(attrs.Y),
            tostring(attrs.ChunkX),
            tostring(attrs.ChunkZ),
            tonumber(attrs.LocalX) or 0,
            tonumber(attrs.LocalZ) or 0,
        }
    else
        local node = target.Parent
        for _ = 1, 5 do
            if not node then break end
            local a = node:GetAttributes() or {}
            if a.Y and (a.ChunkX or a.LocalX) then
                args = {
                    tostring(a.Y),
                    tostring(a.ChunkX or attrs.ChunkX or ""),
                    tostring(a.ChunkZ or attrs.ChunkZ or ""),
                    tonumber(a.LocalX or attrs.LocalX) or 0,
                    tonumber(a.LocalZ or attrs.LocalZ) or 0,
                }
                break
            end
            node = node.Parent
        end
    end

    if not args and State.lastIncomingArgs then
        args = State.lastIncomingArgs
        notify("Click Break", "No block attrs — using last hook args")
    end

    if not args then
        args = getArgsFromState()
        notify("Click Break", "No data — using manual args")
    end

    callBreak(args)
end)

local function scanMouseBlock()
    local target = Mouse.Target
    if not target then
        notify("Scanner", "No target under mouse")
        return
    end
    print("===== Block Scanner =====")
    print("FullName: " .. target:GetFullName())
    print("ClassName: " .. target.ClassName)
    print(("Position: %.2f, %.2f, %.2f"):format(target.Position.X, target.Position.Y, target.Position.Z))
    print(("Size: %.2f, %.2f, %.2f"):format(target.Size.X, target.Size.Y, target.Size.Z))
    local attrs = target:GetAttributes() or {}
    local n = 0
    for _ in pairs(attrs) do n = n + 1 end
    print(("Attributes (%d):"):format(n))
    for k, v in pairs(attrs) do
        print(("   %s = %s"):format(tostring(k), tostring(v)))
    end
    local node = target
    for i = 1, 6 do
        if not node.Parent then break end
        node = node.Parent
        local a = node:GetAttributes() or {}
        if next(a) ~= nil then
            print(("Ancestor[%d] %s attrs:"):format(i, node:GetFullName()))
            for k, v in pairs(a) do
                print(("   %s = %s"):format(tostring(k), tostring(v)))
            end
        end
    end
    notify("Scanner", "Block info printed in console (F9)")
end

local function findBlockSource()
    print("===== Block Source Search =====")
    local found = 0
    local sample = 0
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local attrs = descendant:GetAttributes() or {}
            local cnt = 0
            for _ in pairs(attrs) do cnt = cnt + 1 end
            if cnt >= 3 then
                found = found + 1
                if sample < 8 then
                    sample = sample + 1
                    print(descendant:GetFullName())
                    for k, v in pairs(attrs) do
                        print(("   %s = %s"):format(tostring(k), tostring(v)))
                    end
                end
            end
        end
    end
    print(("Total parts with 3+ attributes: %d"):format(found))
    notify("Find", ("Found %d parts with attributes"):format(found))
end

local function printLastArgs()
    local a = State.lastIncomingArgs
    if not a then
        notify("Logger", "No hook args yet — break a block first")
        return
    end
    print("===== Last Hooked Break Args =====")
    print(("[1] = %q (%s)"):format(tostring(a[1]), type(a[1])))
    print(("[2] = %q (%s)"):format(tostring(a[2]), type(a[2])))
    print(("[3] = %q (%s)"):format(tostring(a[3]), type(a[3])))
    print(("[4] = %s (%s)"):format(tostring(a[4]), type(a[4])))
    print(("[5] = %s (%s)"):format(tostring(a[5]), type(a[5])))
    notify("Logger", "Last args printed in console")
end

local function printAllLogs()
    print("===== All Hooked Break Calls =====")
    print(("Count: %d  | OK: %d  Fail: %d"):format(#State.logs, State.successCount, State.failCount))
    for i, log in ipairs(State.logs) do
        print(("[#%d] %s | %s, %s, %s, %s, %s"):format(
            i, os.date("%H:%M:%S", log.t),
            tostring(log.args[1]), tostring(log.args[2]),
            tostring(log.args[3]), tostring(log.args[4]), tostring(log.args[5])))
    end
    notify("Logger", ("Printed %d logs"):format(#State.logs))
end

local function clearLogs()
    State.logs = {}
    State.lastIncomingArgs = nil
    State.successCount = 0
    State.failCount = 0
    notify("Logger", "Logs cleared")
end

local function bumpArg(name, delta)
    State[name] = (tonumber(State[name]) or 0) + delta
    local map = { arg4 = "arg4", arg5 = "arg5" }
    if map[name] then
        setSliderValue("Manual", "Manual Args", "Args", map[name], State[name])
    end
end

UI = Library:Create({
    Title = "tg: @sigmatik323",
    ConfigName = "MinecraftBlockBreakTest",
    SearchPlaceholder = "Search...",
    GuiToggleKey = Enum.KeyCode.RightShift,
    Accent = "#3b82f6",

    Tabs = {
        {
            Name = "Break",
            Icon = "main",
            Modules = {
                {
                    Name = "Auto Replay",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Replay",
                            Controls = {
                                { Type = "toggle", Name = "Auto Replay Last", Value = false,
                                  Callback = function(v) State.autoReplay = v end },
                                { Type = "slider", Name = "Replay Delay",
                                  Min = 0.05, Max = 2, Increment = 0.05, Value = 0.20,
                                  Callback = function(v) State.replayDelay = v end },
                                { Type = "toggle", Name = "Replay Last Once", Value = false,
                                  Callback = fireOnce("Break", "Auto Replay", "Replay", "Replay Last Once", function()
                                      local src = State.lastIncomingArgs or getArgsFromState()
                                      local ok, err = callBreak(src)
                                      notify("Replay", ok and "Sent" or ("Fail: " .. tostring(err)))
                                  end) },
                            },
                        },
                    },
                },
                {
                    Name = "Click Break",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "toggle", Name = "Enable Click Break", Value = false,
                                  Callback = function(v) State.clickBreak = v end },
                                { Type = "label", Name = "Bind",
                                  Content = "Bind: Right Mouse Button" },
                                { Type = "slider", Name = "Click Range",
                                  Min = 5, Max = 100, Increment = 1, Value = 30,
                                  Callback = function(v) State.clickRange = v end },
                            },
                        },
                    },
                },
                {
                    Name = "Brute Force",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "toggle", Name = "Run Brute Force", Value = false,
                                  Callback = function(v) State.bruteForce = v end },
                                { Type = "label", Name = "Axis Map",
                                  Content = "1=arg2  2=arg3  3=arg4  4=arg5  5=arg4+arg5" },
                                { Type = "slider", Name = "Axis Index",
                                  Min = 1, Max = 5, Increment = 1, Value = 3,
                                  Callback = function(v) State.bruteAxisIndex = math.floor(v + 0.5) end },
                                { Type = "slider", Name = "Brute Range",
                                  Min = 1, Max = 50, Increment = 1, Value = 5,
                                  Callback = function(v) State.bruteRange = v end },
                                { Type = "slider", Name = "Brute Delay",
                                  Min = 0.05, Max = 1, Increment = 0.05, Value = 0.10,
                                  Callback = function(v) State.bruteDelay = v end },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Manual",
            Icon = "main",
            Modules = {
                {
                    Name = "Manual Args",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Args",
                            Controls = {
                                { Type = "label", Name = "Order",
                                  Content = "Each value is sent in Break:InvokeServer order" },
                                { Type = "slider", Name = "arg1 Y",
                                  Min = -50, Max = 50, Increment = 1, Value = 2,
                                  Callback = function(v) State.arg1 = v end },
                                { Type = "slider", Name = "arg2 ChunkX",
                                  Min = 0, Max = 300, Increment = 1, Value = 74,
                                  Callback = function(v) State.arg2 = v end },
                                { Type = "slider", Name = "arg3 ChunkZ",
                                  Min = 0, Max = 100000, Increment = 1, Value = 55874,
                                  Callback = function(v) State.arg3 = v end },
                                { Type = "slider", Name = "arg4",
                                  Min = 0, Max = 300, Increment = 1, Value = 8,
                                  Callback = function(v) State.arg4 = v end },
                                { Type = "slider", Name = "arg5",
                                  Min = 0, Max = 50, Increment = 1, Value = 6,
                                  Callback = function(v) State.arg5 = v end },
                            },
                        },
                        {
                            Name = "Actions",
                            Controls = {
                                { Type = "toggle", Name = "Execute Manual Break", Value = false,
                                  Callback = fireOnce("Manual", "Manual Args", "Actions", "Execute Manual Break", function()
                                      local ok, err = callBreak(getArgsFromState())
                                      notify("Manual", ok and "Sent" or ("Fail: " .. tostring(err)))
                                  end) },
                                { Type = "toggle", Name = "Load From Last Hook", Value = false,
                                  Callback = fireOnce("Manual", "Manual Args", "Actions", "Load From Last Hook", function()
                                      if not State.lastIncomingArgs then
                                          notify("Manual", "No hook args — break a block first")
                                          return
                                      end
                                      pushArgsToState(State.lastIncomingArgs)
                                      notify("Manual", "Loaded from last hook")
                                  end) },
                                { Type = "toggle", Name = "arg4 +1", Value = false,
                                  Callback = fireOnce("Manual", "Manual Args", "Actions", "arg4 +1", function() bumpArg("arg4", 1) end) },
                                { Type = "toggle", Name = "arg4 -1", Value = false,
                                  Callback = fireOnce("Manual", "Manual Args", "Actions", "arg4 -1", function() bumpArg("arg4", -1) end) },
                                { Type = "toggle", Name = "arg5 +1", Value = false,
                                  Callback = fireOnce("Manual", "Manual Args", "Actions", "arg5 +1", function() bumpArg("arg5", 1) end) },
                                { Type = "toggle", Name = "arg5 -1", Value = false,
                                  Callback = fireOnce("Manual", "Manual Args", "Actions", "arg5 -1", function() bumpArg("arg5", -1) end) },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Debug",
            Icon = "misc",
            Modules = {
                {
                    Name = "Logger",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Logging",
                            Controls = {
                                { Type = "toggle", Name = "Hook Outgoing Calls", Value = false,
                                  Callback = function(v) State.logEnabled = v end },
                                { Type = "toggle", Name = "Print Last Args", Value = false,
                                  Callback = fireOnce("Debug", "Logger", "Logging", "Print Last Args", printLastArgs) },
                                { Type = "toggle", Name = "Print All Logs", Value = false,
                                  Callback = fireOnce("Debug", "Logger", "Logging", "Print All Logs", printAllLogs) },
                                { Type = "toggle", Name = "Clear Logs", Value = false,
                                  Callback = fireOnce("Debug", "Logger", "Logging", "Clear Logs", clearLogs) },
                            },
                        },
                    },
                },
                {
                    Name = "Block Scanner",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Tools",
                            Controls = {
                                { Type = "toggle", Name = "Scan Mouse Block", Value = false,
                                  Callback = fireOnce("Debug", "Block Scanner", "Tools", "Scan Mouse Block", scanMouseBlock) },
                                { Type = "toggle", Name = "Find Block Source", Value = false,
                                  Callback = fireOnce("Debug", "Block Scanner", "Tools", "Find Block Source", findBlockSource) },
                            },
                        },
                    },
                },
                {
                    Name = "Info",
                    Enabled = false,
                    Sections = {
                        {
                            Name = "Hypothesis",
                            Controls = {
                                { Type = "paragraph", Name = "Args layout",
                                  Content = "args[1]=Y(string), args[2]=ChunkX(string), args[3]=ChunkZ(string), args[4]=LocalX(num), args[5]=LocalZ(num). Hook Outgoing → break a real block → Replay or Brute Force to verify." },
                            },
                        },
                    },
                },
            },
        },
    },
})

if not BreakRemote then
    notify("Init", "Break remote not found — check ReplicatedStorage path")
else
    notify("Init", "Ready. Hook Outgoing → break block → Replay/Brute.")
end
