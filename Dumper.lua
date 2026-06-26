--[[ 
    SOLO PLAYER DUMPER
    Игнорирует всех игроков, кроме того, кто запустил скрипт.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- 1. Получаем имя игры
local success, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
local gameName = success and info.Name or "UnknownGame"
gameName = gameName:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")

local root = "Дампер_игр"
local gameFolder = root .. "\\" .. gameName

local function makePath(path)
    local parts = path:split("\\")
    local current = ""
    for i, part in pairs(parts) do
        current = (current == "" and part or current .. "\\" .. part)
        if not isfolder(current) then
            makefolder(current)
        end
    end
end

makePath(gameFolder .. "\\Workspace")
makePath(gameFolder .. "\\ReplicatedStorage")
makePath(gameFolder .. "\\CoreGui")
makePath(gameFolder .. "\\Players")

local function saveInfo(obj, folderPath)
    local content = string.format(
        "Name: %s\nClass: %s\nPath: %s\n",
        obj.Name, obj.ClassName, obj:GetFullName()
    )
    if obj:IsA("BasePart") then
        content = content .. string.format("Pos: %s\nSize: %s\n", tostring(obj.Position), tostring(obj.Size))
    end
    writefile(folderPath .. "\\_info.txt", content)
end

-- Функция проверки: является ли объект ЧУЖИМ игроком
local function isOtherPlayer(obj)
    local player = Players:GetPlayerFromCharacter(obj)
    if player and player ~= LocalPlayer then
        return true
    end
    return false
end

local function dump(obj, currentPath)
    -- Пропускаем, если это чужой персонаж
    if isOtherPlayer(obj) then return end

    local safeName = obj.Name:gsub("[^%w%s%-_]", ""):gsub("^%s*(.-)%s*$", "%1")
    if safeName == "" then safeName = "Unnamed_" .. obj.ClassName end
    
    local objPath = currentPath .. "\\" .. safeName
    
    if not isfolder(objPath) then
        makefolder(objPath)
    end
    
    pcall(function() saveInfo(obj, objPath) end)
    
    -- Рекурсия для контейнеров
    if obj:IsA("Folder") or obj:IsA("Model") or obj:IsA("Tool") or obj:IsA("Configuration") or obj:IsA("Workspace") or obj:IsA("ReplicatedStorage") then
        for _, child in pairs(obj:GetChildren()) do
            dump(child, objPath)
        end
    end
end

warn("--- СТАРТ ДАМПА (БЕЗ ЧУЖИХ ИГРОКОВ) ---")

pcall(function()
    for _, child in pairs(game.ReplicatedStorage:GetChildren()) do
        dump(child, gameFolder .. "\\ReplicatedStorage")
    end
    for _, child in pairs(game.Workspace:GetChildren()) do
        dump(child, gameFolder .. "\\Workspace")
    end
    for _, child in pairs(game:GetService("CoreGui"):GetChildren()) do
        dump(child, gameFolder .. "\\CoreGui")
    end
    for _, child in pairs(game:GetService("Players"):GetChildren()) do
        dump(child, gameFolder .. "\\Players")
    end
end)

warn("--- ГОТОВО! Лишние игроки отфильтрованы. ---")