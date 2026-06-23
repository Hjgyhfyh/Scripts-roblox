if getgenv and getgenv().GameTestBench then
    pcall(function() getgenv().GameTestBench.unload() end)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local unpack = table.unpack or unpack

local SPAM_GLOBAL_MAX = 400

local P = {
    bg      = Color3.fromRGB(17, 17, 22),
    panel   = Color3.fromRGB(25, 25, 31),
    panel2  = Color3.fromRGB(33, 33, 41),
    accent  = Color3.fromRGB(124, 96, 255),
    good    = Color3.fromRGB(86, 204, 157),
    text    = Color3.fromRGB(236, 236, 242),
    sub     = Color3.fromRGB(146, 146, 158),
    danger  = Color3.fromRGB(228, 86, 92),
    stroke  = Color3.fromRGB(48, 48, 60),
}

local Maid = { _items = {} }
function Maid:give(item) table.insert(self._items, item); return item end
function Maid:clean()
    for _, item in ipairs(self._items) do
        pcall(function()
            if typeof(item) == "RBXScriptConnection" then item:Disconnect()
            elseif typeof(item) == "Instance" then item:Destroy()
            elseif type(item) == "function" then item()
            elseif type(item) == "table" and item.Disconnect then item:Disconnect() end
        end)
    end
    self._items = {}
end

local function new(class, props, children)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then o[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = o end
    if props and props.Parent then o.Parent = props.Parent end
    return o
end

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }) end
local function stroke(c, t) return new("UIStroke", { Color = c or P.stroke, Thickness = t or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function pad(v) return new("UIPadding", { PaddingTop = UDim.new(0, v), PaddingBottom = UDim.new(0, v), PaddingLeft = UDim.new(0, v), PaddingRight = UDim.new(0, v) }) end

local function repr(v)
    local t = typeof(v)
    if t == "Instance" then return v:GetFullName() .. " <" .. v.ClassName .. ">"
    elseif t == "Vector3" then return ("Vector3(%.2f, %.2f, %.2f)"):format(v.X, v.Y, v.Z)
    elseif t == "Vector2" then return ("Vector2(%.2f, %.2f)"):format(v.X, v.Y)
    elseif t == "Color3" then return ("Color3(%.2f, %.2f, %.2f)"):format(v.R, v.G, v.B)
    elseif t == "CFrame" then local p = v.Position; return ("CFrame@(%.1f, %.1f, %.1f)"):format(p.X, p.Y, p.Z)
    elseif t == "string" then return '"' .. v .. '"'
    elseif t == "nil" then return "nil"
    else return tostring(v) end
end

local function reprTuple(packed)
    if packed.n == 0 then return "(no return)" end
    local parts = {}
    for i = 1, packed.n do parts[i] = repr(packed[i]) end
    return table.concat(parts, ",  ")
end

local function buildEnv()
    return setmetatable({
        me = LocalPlayer,
        char = LocalPlayer.Character,
        pf = LocalPlayer:FindFirstChild("playerFolder"),
        ws = workspace,
        rs = ReplicatedStorage,
        Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame,
        Color3 = Color3, Instance = Instance, math = math,
        workspace = workspace, game = game,
    }, { __index = getfenv() })
end

local function parseArgs(text)
    if text == nil or text:gsub("%s", "") == "" then return { n = 0 } end
    local fn, err = loadstring("return " .. text)
    if not fn then return nil, err end
    setfenv(fn, buildEnv())
    local packed = table.pack(pcall(fn))
    if not packed[1] then return nil, packed[2] end
    local args = { n = packed.n - 1 }
    for i = 2, packed.n do args[i - 1] = packed[i] end
    return args
end

local function fireRemote(remote, args)
    local cls = remote.ClassName
    if cls == "RemoteEvent" or cls == "UnreliableRemoteEvent" then
        remote:FireServer(unpack(args, 1, args.n)); return "FireServer sent"
    elseif cls == "BindableEvent" then
        remote:Fire(unpack(args, 1, args.n)); return "Fire sent"
    elseif cls == "RemoteFunction" then
        return "InvokeServer -> " .. reprTuple(table.pack(remote:InvokeServer(unpack(args, 1, args.n))))
    elseif cls == "BindableFunction" then
        return "Invoke -> " .. reprTuple(table.pack(remote:Invoke(unpack(args, 1, args.n))))
    end
    return "unsupported class " .. cls
end

local HINTS = {
    HeadLook       = "yaw, pitch   ->   -0.76, -0.47",
    UpdateArm      = "number   ->   -0.6",
    UpdateSettings = 'categoryFolder, name, value   ->   pf.Settings.Graphics, "Performance Mode", false',
    PlaySound      = "soundInstance   ->   char.Fist.Handle.Attack",
    Throw          = "(arm a tool first, then read the spy)",
    Fire           = "(equip a gun and fire once to learn the real signature)",
    DropRequest    = "(open inventory and drop an item to learn args)",
    ShopProcess    = "(open shop and buy to learn args)",
    EmoteEvent     = "emoteName   ->   \"wave\"",
}

local spamJobs = {}
local spamConn
local function spamTotal()
    local s, c = 0, 0
    for _, j in pairs(spamJobs) do s = s + j.rate; c = c + 1 end
    return s, c
end
local function ensureSpamLoop()
    if spamConn then return end
    spamConn = Maid:give(RunService.Heartbeat:Connect(function(dt)
        if dt > 0.1 then dt = 0.1 end
        local total = spamTotal()
        if total <= 0 then return end
        local scale = total > SPAM_GLOBAL_MAX and (SPAM_GLOBAL_MAX / total) or 1
        for _, j in pairs(spamJobs) do
            local eff = j.rate * scale
            j.acc = j.acc + eff * dt
            if j.acc > eff + 1 then j.acc = eff end
            while j.acc >= 1 do
                j.acc = j.acc - 1
                task.spawn(function() pcall(fireRemote, j.remote, j.args) end)
            end
        end
    end))
end
local function stopAllSpam()
    spamJobs = {}
    if spamConn then spamConn:Disconnect(); spamConn = nil end
end

local guiParent
do
    local ok, hui = pcall(function() return gethui() end)
    guiParent = (ok and hui) or game:GetService("CoreGui")
end

local screenGui = new("ScreenGui", {
    Name = "GameTestBench",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999,
    Parent = guiParent,
})
Maid:give(screenGui)

local Main = new("Frame", {
    Parent = screenGui,
    Size = UDim2.new(0, 560, 0, 400),
    Position = UDim2.new(0.5, -280, 0.5, -200),
    BackgroundColor3 = P.bg,
    BorderSizePixel = 0,
}, { corner(12), stroke(P.stroke, 1) })

local titleBar = new("Frame", {
    Parent = Main,
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = P.panel,
    BorderSizePixel = 0,
}, { corner(12) })
new("Frame", { Parent = titleBar, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = P.panel, BorderSizePixel = 0 })

new("TextLabel", {
    Parent = titleBar,
    Size = UDim2.new(0, 300, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "TEST BENCH",
    TextColor3 = P.text,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
})
local spamMeter = new("TextLabel", {
    Parent = titleBar,
    Size = UDim2.new(0, 200, 1, 0),
    Position = UDim2.new(1, -290, 0, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "spam 0/400 r/s",
    TextColor3 = P.sub,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Right,
})

local function iconButton(parent, x, txt, col)
    return new("TextButton", {
        Parent = parent,
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(1, x, 0.5, -15),
        BackgroundColor3 = P.panel2,
        AutoButtonColor = true,
        Text = txt,
        Font = Enum.Font.GothamBold,
        TextColor3 = col or P.text,
        TextSize = 16,
        BorderSizePixel = 0,
    }, { corner(8) })
end
local minBtn = iconButton(titleBar, -78, "–")
local closeBtn = iconButton(titleBar, -42, "✕", P.danger)

local tabBar = new("Frame", {
    Parent = Main,
    Size = UDim2.new(1, -20, 0, 34),
    Position = UDim2.new(0, 10, 0, 50),
    BackgroundTransparency = 1,
}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local content = new("Frame", {
    Parent = Main,
    Size = UDim2.new(1, -20, 1, -96),
    Position = UDim2.new(0, 10, 0, 90),
    BackgroundTransparency = 1,
})

local pages, tabButtons = {}, {}
local function makePage(name, order)
    local btn = new("TextButton", {
        Parent = tabBar,
        Size = UDim2.new(0, 96, 1, 0),
        BackgroundColor3 = P.panel,
        Text = name,
        Font = Enum.Font.GothamMedium,
        TextColor3 = P.sub,
        TextSize = 13,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        LayoutOrder = order,
    }, { corner(8) })
    local page = new("Frame", {
        Parent = content,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
    })
    pages[name], tabButtons[name] = page, btn
    return page
end

local function showTab(name)
    for n, page in pairs(pages) do
        page.Visible = (n == name)
        local b = tabButtons[n]
        b.BackgroundColor3 = (n == name) and P.accent or P.panel
        b.TextColor3 = (n == name) and Color3.new(1, 1, 1) or P.sub
    end
end

local remotesPage = makePage("Remotes", 1)
local dataPage    = makePage("Data", 2)
local quickPage   = makePage("Quick", 3)
local consolePage = makePage("Console", 4)

local consoleList = new("ScrollingFrame", {
    Parent = consolePage,
    Size = UDim2.new(1, 0, 1, -36),
    BackgroundColor3 = P.panel,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
    ScrollBarImageColor3 = P.accent,
}, { corner(8), pad(8), new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

local logCount = 0
local function log(msg, col)
    logCount = logCount + 1
    if logCount > 250 then
        local kids = consoleList:GetChildren()
        for _, k in ipairs(kids) do if k:IsA("TextLabel") then k:Destroy(); break end end
    end
    new("TextLabel", {
        Parent = consoleList,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        Text = msg,
        TextColor3 = col or P.text,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = logCount,
    })
    task.defer(function()
        consoleList.CanvasPosition = Vector2.new(0, consoleList.AbsoluteCanvasSize.Y)
    end)
end

local clearLogBtn = new("TextButton", {
    Parent = consolePage,
    Size = UDim2.new(0, 90, 0, 28),
    Position = UDim2.new(1, -90, 1, -28),
    BackgroundColor3 = P.panel2,
    Text = "Clear",
    Font = Enum.Font.GothamMedium,
    TextColor3 = P.text,
    TextSize = 13,
    BorderSizePixel = 0,
}, { corner(8) })
clearLogBtn.MouseButton1Click:Connect(function()
    for _, k in ipairs(consoleList:GetChildren()) do if k:IsA("TextLabel") then k:Destroy() end end
    logCount = 0
end)

local searchBox = new("TextBox", {
    Parent = remotesPage,
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = P.panel2,
    Text = "",
    PlaceholderText = "search remote...",
    Font = Enum.Font.Gotham,
    TextColor3 = P.text,
    PlaceholderColor3 = P.sub,
    TextSize = 13,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
}, { corner(8), pad(6) })

local listScroll = new("ScrollingFrame", {
    Parent = remotesPage,
    Size = UDim2.new(1, 0, 1, -150),
    Position = UDim2.new(0, 0, 0, 34),
    BackgroundColor3 = P.panel,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
    ScrollBarImageColor3 = P.accent,
}, { corner(8), pad(6), new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }) })

local detail = new("Frame", {
    Parent = remotesPage,
    Size = UDim2.new(1, 0, 0, 108),
    Position = UDim2.new(0, 0, 1, -108),
    BackgroundColor3 = P.panel,
    BorderSizePixel = 0,
}, { corner(8), pad(8) })

local selLabel = new("TextLabel", {
    Parent = detail,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "select a remote above",
    TextColor3 = P.text,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
})
local argsBox = new("TextBox", {
    Parent = detail,
    Size = UDim2.new(1, 0, 0, 28),
    Position = UDim2.new(0, 0, 0, 22),
    BackgroundColor3 = P.panel2,
    Text = "",
    PlaceholderText = "args (lua) — use me, char, pf, ws, rs",
    Font = Enum.Font.Code,
    TextColor3 = P.text,
    PlaceholderColor3 = P.sub,
    TextSize = 12,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
}, { corner(8), pad(6) })

local fireBtn = new("TextButton", {
    Parent = detail,
    Size = UDim2.new(0, 120, 0, 30),
    Position = UDim2.new(0, 0, 0, 58),
    BackgroundColor3 = P.accent,
    Text = "Fire",
    Font = Enum.Font.GothamBold,
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 14,
    BorderSizePixel = 0,
}, { corner(8) })

local rateBox = new("TextBox", {
    Parent = detail,
    Size = UDim2.new(0, 70, 0, 30),
    Position = UDim2.new(0, 130, 0, 58),
    BackgroundColor3 = P.panel2,
    Text = "50",
    PlaceholderText = "r/s",
    Font = Enum.Font.Code,
    TextColor3 = P.text,
    TextSize = 13,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
}, { corner(8) })

local spamBtn = new("TextButton", {
    Parent = detail,
    Size = UDim2.new(0, 120, 0, 30),
    Position = UDim2.new(0, 210, 0, 58),
    BackgroundColor3 = P.panel2,
    Text = "Spam ▶",
    Font = Enum.Font.GothamBold,
    TextColor3 = P.text,
    TextSize = 14,
    BorderSizePixel = 0,
}, { corner(8) })

local selected
local function selectRemote(remote)
    selected = remote
    selLabel.Text = remote.Name .. "  <" .. remote.ClassName .. ">"
    argsBox.PlaceholderText = HINTS[remote.Name] or ("args (lua) — " .. remote.ClassName)
    if spamJobs[remote] then spamBtn.Text = "Stop ■"; spamBtn.BackgroundColor3 = P.danger
    else spamBtn.Text = "Spam ▶"; spamBtn.BackgroundColor3 = P.panel2 end
end

local function gatherRemotes()
    local groups, order = {}, {}
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent")
            or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
            local g = (d.Parent and d.Parent.Name) or "Misc"
            if not groups[g] then groups[g] = {}; table.insert(order, g) end
            table.insert(groups[g], d)
        end
    end
    table.sort(order)
    return groups, order
end

local function rebuildList(filter)
    for _, k in ipairs(listScroll:GetChildren()) do if not k:IsA("UIListLayout") and not k:IsA("UIPadding") then k:Destroy() end end
    filter = (filter or ""):lower()
    local groups, order = gatherRemotes()
    local idx = 0
    for _, g in ipairs(order) do
        local items = {}
        for _, r in ipairs(groups[g]) do
            if filter == "" or r.Name:lower():find(filter, 1, true) then table.insert(items, r) end
        end
        if #items > 0 then
            table.sort(items, function(a, b) return a.Name < b.Name end)
            idx = idx + 1
            new("TextLabel", {
                Parent = listScroll,
                Size = UDim2.new(1, 0, 0, 18),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                Text = g .. "  (" .. #items .. ")",
                TextColor3 = P.accent,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = idx,
            })
            for _, r in ipairs(items) do
                idx = idx + 1
                local isFn = r:IsA("RemoteFunction") or r:IsA("BindableFunction")
                local btn = new("TextButton", {
                    Parent = listScroll,
                    Size = UDim2.new(1, 0, 0, 24),
                    BackgroundColor3 = P.panel2,
                    Text = "  " .. r.Name,
                    Font = Enum.Font.Gotham,
                    TextColor3 = isFn and P.good or P.text,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    LayoutOrder = idx,
                }, { corner(6) })
                btn.MouseButton1Click:Connect(function() selectRemote(r) end)
            end
        end
    end
end

local searchDebounce
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local txt = searchBox.Text
    searchDebounce = txt
    task.delay(0.15, function() if searchDebounce == txt then rebuildList(txt) end end)
end)

local function doFire()
    if not selected then log("no remote selected", P.danger); return end
    local args, err = parseArgs(argsBox.Text)
    if not args then log("arg error: " .. tostring(err), P.danger); return end
    local target = selected
    task.spawn(function()
        local ok, info = pcall(fireRemote, target, args)
        if ok then log("[" .. target.Name .. "] " .. tostring(info), P.good)
        else log("[" .. target.Name .. "] ERROR: " .. tostring(info), P.danger) end
    end)
end
fireBtn.MouseButton1Click:Connect(doFire)

spamBtn.MouseButton1Click:Connect(function()
    if not selected then log("no remote selected", P.danger); return end
    if spamJobs[selected] then
        spamJobs[selected] = nil
        spamBtn.Text = "Spam ▶"; spamBtn.BackgroundColor3 = P.panel2
        log("[" .. selected.Name .. "] spam stopped", P.sub)
        return
    end
    local args, err = parseArgs(argsBox.Text)
    if not args then log("arg error: " .. tostring(err), P.danger); return end
    local rate = tonumber(rateBox.Text) or 50
    rate = math.clamp(rate, 1, SPAM_GLOBAL_MAX)
    spamJobs[selected] = { remote = selected, args = args, rate = rate, acc = 0 }
    ensureSpamLoop()
    spamBtn.Text = "Stop ■"; spamBtn.BackgroundColor3 = P.danger
    local total = spamTotal()
    if total > SPAM_GLOBAL_MAX then
        log(("[%s] spam @ %d r/s (global %d>400, auto-scaled down)"):format(selected.Name, rate, total), P.text)
    else
        log(("[%s] spam @ %d r/s"):format(selected.Name, rate), P.good)
    end
end)

local dataText = new("TextLabel", {
    Parent = new("ScrollingFrame", {
        Parent = dataPage,
        Size = UDim2.new(1, 0, 1, -36),
        BackgroundColor3 = P.panel,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollBarImageColor3 = P.accent,
    }, { corner(8), pad(8) }),
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    Text = "press Refresh",
    TextColor3 = P.text,
    TextSize = 12,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
})

local function folderToLines(inst, indent, lines)
    indent = indent or ""
    lines = lines or {}
    local kids = inst:GetChildren()
    table.sort(kids, function(a, b) return a.Name < b.Name end)
    for _, c in ipairs(kids) do
        if c:IsA("ValueBase") then
            lines[#lines + 1] = indent .. c.Name .. " = " .. repr(c.Value)
        elseif #c:GetChildren() > 0 then
            lines[#lines + 1] = indent .. c.Name .. ":"
            folderToLines(c, indent .. "   ", lines)
        else
            lines[#lines + 1] = indent .. c.Name .. " <" .. c.ClassName .. ">"
        end
    end
    return lines
end

local function refreshData()
    local lines = {}
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    lines[#lines + 1] = "PLAYER: " .. LocalPlayer.Name .. "  (id " .. LocalPlayer.UserId .. ")"
    if hum then
        lines[#lines + 1] = ("Health %.0f/%.0f   WalkSpeed %.1f"):format(hum.Health, hum.MaxHealth, hum.WalkSpeed)
    end
    if char then
        local attrs = char:GetAttributes()
        local keys = {}
        for k in pairs(attrs) do keys[#keys + 1] = k end
        table.sort(keys)
        if #keys > 0 then
            lines[#lines + 1] = "Character attributes:"
            for _, k in ipairs(keys) do lines[#lines + 1] = "   " .. k .. " = " .. repr(attrs[k]) end
        end
    end
    lines[#lines + 1] = ""
    local pf = LocalPlayer:FindFirstChild("playerFolder")
    if pf then
        lines[#lines + 1] = "playerFolder:"
        folderToLines(pf, "   ", lines)
    else
        lines[#lines + 1] = "playerFolder not found"
    end
    dataText.Text = table.concat(lines, "\n")
end

local refreshBtn = new("TextButton", {
    Parent = dataPage,
    Size = UDim2.new(0, 110, 0, 28),
    Position = UDim2.new(0, 0, 1, -28),
    BackgroundColor3 = P.accent,
    Text = "Refresh",
    Font = Enum.Font.GothamBold,
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 13,
    BorderSizePixel = 0,
}, { corner(8) })
refreshBtn.MouseButton1Click:Connect(refreshData)

local autoData = false
local autoBtn = new("TextButton", {
    Parent = dataPage,
    Size = UDim2.new(0, 110, 0, 28),
    Position = UDim2.new(0, 118, 1, -28),
    BackgroundColor3 = P.panel2,
    Text = "Auto: off",
    Font = Enum.Font.GothamMedium,
    TextColor3 = P.text,
    TextSize = 13,
    BorderSizePixel = 0,
}, { corner(8) })
autoBtn.MouseButton1Click:Connect(function()
    autoData = not autoData
    autoBtn.Text = "Auto: " .. (autoData and "on" or "off")
    autoBtn.BackgroundColor3 = autoData and P.good or P.panel2
end)
task.spawn(function()
    while screenGui.Parent do
        if autoData and dataPage.Visible then pcall(refreshData) end
        task.wait(1)
    end
end)

local quickScroll = new("ScrollingFrame", {
    Parent = quickPage,
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    ScrollBarThickness = 4,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
    ScrollBarImageColor3 = P.accent,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })

local function findFirst(name)
    return ReplicatedStorage:FindFirstChild(name, true)
end

local function quickAction(label, fn)
    local btn = new("TextButton", {
        Parent = quickScroll,
        Size = UDim2.new(1, -4, 0, 34),
        BackgroundColor3 = P.panel2,
        Text = label,
        Font = Enum.Font.GothamMedium,
        TextColor3 = P.text,
        TextSize = 13,
        BorderSizePixel = 0,
    }, { corner(8) })
    btn.MouseButton1Click:Connect(function()
        task.spawn(function()
            local ok, err = pcall(fn)
            if not ok then log("quick error: " .. tostring(err), P.danger) end
        end)
    end)
end

quickAction("Count all remotes/bindables", function()
    local groups, order = gatherRemotes()
    for _, g in ipairs(order) do log(g .. ": " .. #groups[g], P.text) end
    showTab("Console")
end)
quickAction("Dump player data to Console", function()
    refreshData()
    log(dataText.Text, P.text)
    showTab("Console")
end)
quickAction("Test HeadLook (random yaw/pitch)", function()
    local r = findFirst("HeadLook")
    if not r then log("HeadLook not found", P.danger); return end
    local yaw, pitch = (math.random() - 0.5) * 2, (math.random() - 0.5)
    r:FireServer(yaw, pitch)
    log(("HeadLook(%.3f, %.3f) sent"):format(yaw, pitch), P.good)
end)
quickAction("Toggle 'Performance Mode' setting", function()
    local r = findFirst("UpdateSettings")
    local pf = LocalPlayer:FindFirstChild("playerFolder")
    local cat = pf and pf:FindFirstChild("Settings") and pf.Settings:FindFirstChild("Graphics")
    if not (r and cat) then log("UpdateSettings/Graphics not found", P.danger); return end
    local cur = cat:FindFirstChild("Performance Mode")
    local val = cur and not cur.Value or true
    r:FireServer(cat, "Performance Mode", val)
    log("UpdateSettings Performance Mode -> " .. tostring(val), P.good)
end)
quickAction("Play Fist attack sound", function()
    local r = findFirst("PlaySound")
    local char = LocalPlayer.Character
    local fist = char and char:FindFirstChild("Fist")
    local snd = fist and fist:FindFirstChild("Handle") and fist.Handle:FindFirstChild("Attack")
    if not (r and snd) then log("PlaySound/Fist sound not found (equip Fist)", P.danger); return end
    r:FireServer(snd)
    log("PlaySound(Fist.Attack) sent", P.good)
end)

local dragging, dragStart, startPos
titleBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, i.Position, Main.Position
        i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
Maid:give(UserInputService.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end))

local collapsed = false
minBtn.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    tabBar.Visible = not collapsed
    content.Visible = not collapsed
    Main.Size = collapsed and UDim2.new(0, 560, 0, 42) or UDim2.new(0, 560, 0, 400)
    minBtn.Text = collapsed and "+" or "–"
end)

Maid:give(UserInputService.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightControl then Main.Visible = not Main.Visible end
end))

Maid:give(RunService.RenderStepped:Connect(function()
    local total, count = spamTotal()
    spamMeter.Text = ("spam %d/400 r/s · %d active"):format(math.floor(total + 0.5), count)
    spamMeter.TextColor3 = total > SPAM_GLOBAL_MAX and P.danger or P.sub
end))

Maid:give(LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end))

local unload
unload = function()
    stopAllSpam()
    Maid:clean()
    if getgenv then getgenv().GameTestBench = nil end
end
closeBtn.MouseButton1Click:Connect(unload)

if getgenv then getgenv().GameTestBench = { unload = unload } end

rebuildList("")
showTab("Remotes")
refreshData()
log("test bench ready — RightCtrl toggles, ✕ unloads", P.good)
