local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

if _G.__pmController then
    pcall(function() _G.__pmController:Destroy() end)
    _G.__pmController = nil
end
_G.__poundMochiToken = nil
task.wait(0.4)

local SCRIPT_TOKEN = {}
_G.__poundMochiToken = SCRIPT_TOKEN
local function alive() return _G.__poundMochiToken == SCRIPT_TOKEN end

local autoHarvest = false
local autoPound = false
local farmDelay = 1000
local plantIndex = 1
local poundIndex = 1

local function getPacketEvent()
    local pkg = ReplicatedStorage:FindFirstChild("Packages")
    if not pkg then return nil end
    local pp = pkg:FindFirstChild("PacketPlus")
    if not pp then return nil end
    return pp:FindFirstChild("RemoteEvent")
end

local function makeBuf(target, action)
    return string.char(0x06)
        .. string.char(#target)
        .. target
        .. string.char(#action)
        .. action
        .. string.char(0)
end

local function fireBuffer(ev, bufStr)
    if not ev or not bufStr or #bufStr == 0 then return false end
    return pcall(function()
        ev:FireServer(buffer.fromstring(bufStr))
    end)
end

task.spawn(function()
    while alive() do
        if autoHarvest then
            local ev = getPacketEvent()
            if ev then
                local target = "RICE" .. tostring(plantIndex)
                fireBuffer(ev, makeBuf(target, "Harvest"))
            end
            task.wait(farmDelay / 1000)
        else
            task.wait(0.15)
        end
    end
end)

task.spawn(function()
    while alive() do
        if autoPound then
            local ev = getPacketEvent()
            if ev then
                local target = poundIndex == 1 and "USU" or ("USU" .. tostring(poundIndex))
                fireBuffer(ev, makeBuf(target, "Pound"))
            end
            task.wait(farmDelay / 1000)
        else
            task.wait(0.15)
        end
    end
end)

local antiAfkConn = nil
local function setAntiAfk(enabled)
    if antiAfkConn then
        antiAfkConn:Disconnect()
        antiAfkConn = nil
    end
    if enabled then
        antiAfkConn = LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end
end

local Sigmatik = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"))()

local controller
controller = Sigmatik:Create({
    Title = "tg: @sigmatik323",
    Tabs = {
        {
            Name = "🌾 Farming",
            Icon = "combat",
            Modules = {
                {
                    Name = "Auto Harvest",
                    Enabled = false,
                    Callback = function(enabled)
                        autoHarvest = enabled
                    end,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                {
                                    Type = "slider",
                                    Name = "Rice Plot Index",
                                    Min = 1,
                                    Max = 12,
                                    Increment = 1,
                                    Value = 1,
                                    Callback = function(value)
                                        plantIndex = math.floor(value)
                                    end,
                                },
                            },
                        },
                    },
                },
                {
                    Name = "Auto Pound (Money)",
                    Enabled = false,
                    Callback = function(enabled)
                        autoPound = enabled
                    end,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                {
                                    Type = "slider",
                                    Name = "USU Index",
                                    Min = 1,
                                    Max = 6,
                                    Increment = 1,
                                    Value = 1,
                                    Callback = function(value)
                                        poundIndex = math.floor(value)
                                    end,
                                },
                            },
                        },
                    },
                },
                {
                    Name = "Farm Speed",
                    Enabled = true,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                {
                                    Type = "slider",
                                    Name = "Farm Delay (ms)",
                                    Min = 300,
                                    Max = 3000,
                                    Increment = 50,
                                    Value = 1000,
                                    Callback = function(value)
                                        farmDelay = value
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "⚙️ Misc",
            Icon = "movement",
            Modules = {
                {
                    Name = "Anti-AFK",
                    Enabled = false,
                    Callback = function(enabled)
                        setAntiAfk(enabled)
                    end,
                },
            },
        },
    },
})

_G.__pmController = controller
