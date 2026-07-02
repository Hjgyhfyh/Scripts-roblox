--[[
    Anti AFK (Universal) — автоэкзек, работает в любой игре.

    Слой 1: каждые 30с глушит ВСЕ чужие коннекты на LocalPlayer.Idled —
            включая корскриптовый 20-минутный idle-kick и игровые AFK-детекты,
            висящие на Idled.
    Слой 2: свой коннект на Idled — виртуальный правый клик через VirtualUser,
            сбрасывает таймер бездействия (работает даже там, где нет getconnections).

    Без GUI, «включил-и-забыл», один раз за инжект (guard в getgenv).
]]

if getgenv().__ANTI_AFK_ARMED then return end
getgenv().__ANTI_AFK_ARMED = true

local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

local lp = Players.LocalPlayer
while not lp do
    task.wait(0.2)
    lp = Players.LocalPlayer
end

-- имитация ввода: Roblox считает игрока активным, idle-таймер сбрасывается
local function bump()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

local myConn
local function sweep()
    -- порядок важен: сносим свой, глушим всё что висит на Idled, создаём свой заново —
    -- в итоге живым остаётся только наш коннект, без сравнения полей прокси
    if myConn then
        pcall(function() myConn:Disconnect() end)
    end
    if type(getconnections) == "function" then
        pcall(function()
            for _, c in ipairs(getconnections(lp.Idled)) do
                pcall(function() c:Disable() end)
            end
        end)
    end
    myConn = lp.Idled:Connect(bump)
end

sweep()
task.spawn(function()
    -- корскрипт/игра могут подцепиться к Idled позже автоэкзека — чистим периодически
    while true do
        task.wait(30)
        sweep()
    end
end)

print("[AntiAFK] armed: idle-kick заглушен, VirtualUser на подхвате")
