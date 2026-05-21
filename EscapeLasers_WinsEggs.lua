--[[
    Escape Lasers — Wins farm + авто-открытие яиц
    ───────────────────────────────────────────────
    K  — вкл/выкл фарм Wins (бесконечно касается блока Win.Touch текущего мира)
    L  — открыть МАКСИМУМ яиц за один раз, исходя из текущего баланса Wins

    Блок Wins:  workspace.DynamicObjects.Worlds.<Мир>.Win.Touch  (мир берётся из игрока)
    Яйцо:       EggService.open  через RemoteFunction
]]

--==================== НАСТРОЙКИ ====================--
local EGG_NAME       = "Egg12"   -- какое яйцо открывать
local EGG_COST       = 12        -- стоимость одного яйца в Wins
local FARM_DELAY     = 0.05      -- задержка между касаниями блока (сек)
local CHUNK          = 50        -- сколько яиц слать за один InvokeServer
local CHUNK_DELAY    = 0.15      -- пауза между пачками (меньше лагов)
local MAX_PER_PRESS  = 100000    -- предохранитель: макс. яиц за одно нажатие L
--===================================================--

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local UIS     = game:GetService("UserInputService")
local Http    = game:GetService("HttpService")

local lp = Players.LocalPlayer

local RemoteFunction = RS:WaitForChild("CommonModules"):WaitForChild("Systems")
    :WaitForChild("NetworkSystem"):WaitForChild("Network"):WaitForChild("RemoteFunction")

-- уведомление в углу экрана
local function notify(title, text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title, Text = text, Duration = 3,
        })
    end)
end

-- точный числовой баланс Wins из атрибута data (обновляется в реальном времени)
local function getWins()
    local d = lp:GetAttribute("data")
    if not d then return 0 end
    local ok, j = pcall(function() return Http:JSONDecode(d) end)
    if ok and j and j.stats and tonumber(j.stats.Wins) then
        return math.floor(tonumber(j.stats.Wins))
    end
    return 0
end

-- блок Win.Touch текущего мира игрока
local function getWinTouch()
    local world = lp:GetAttribute("worldName") or "White"
    local worlds = workspace:FindFirstChild("DynamicObjects")
    worlds = worlds and worlds:FindFirstChild("Worlds")
    local w = worlds and worlds:FindFirstChild(world)
    local win = w and w:FindFirstChild("Win")
    return win and win:FindFirstChild("Touch")
end

--==================== ФАРМ WINS (K) ====================--
local farming = false

local function farmStep()
    local ch  = lp.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local part = getWinTouch()
    if hrp and part then
        pcall(function()
            firetouchinterest(part, hrp, 0)
            firetouchinterest(part, hrp, 1)
        end)
    end
end

task.spawn(function()
    while true do
        if farming then
            farmStep()
            task.wait(FARM_DELAY)
        else
            task.wait(0.1)
        end
    end
end)

--==================== ОТКРЫТИЕ ЯИЦ (L) ====================--
local function openEggs()
    local wins = getWins()
    local affordable = math.floor(wins / EGG_COST)
    if affordable < 1 then
        notify("Яйца", "Недостаточно Wins (" .. wins .. ")")
        return
    end
    local toOpen = math.min(affordable, MAX_PER_PRESS)
    notify("Яйца", "Открываю " .. toOpen .. " шт. (баланс " .. wins .. ")")

    local opened = 0
    while opened < toOpen do
        local n = math.min(CHUNK, toOpen - opened)
        local list = table.create(n)
        for i = 1, n do
            list[i] = { name = EGG_NAME, type = "Egg" }
        end
        local ok = pcall(function()
            RemoteFunction:InvokeServer("EggService.open", list)
        end)
        if not ok then break end
        opened = opened + n
        task.wait(CHUNK_DELAY) -- не вешаем клиент
    end
    notify("Яйца", "Открыто: " .. opened .. " | осталось Wins: " .. getWins())
end

--==================== ХОТКЕИ ====================--
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.K then
        farming = not farming
        notify("Wins фарм", farming and "ВКЛ" or "ВЫКЛ")
    elseif input.KeyCode == Enum.KeyCode.L then
        openEggs()
    end
end)

notify("Escape Lasers", "K — фарм Wins | L — открыть макс. яиц")
print("[Wins/Eggs] Загружено. K = фарм Wins (вкл/выкл), L = открыть макс яиц.")
