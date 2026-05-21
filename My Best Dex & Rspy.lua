--[[
    ROBLOX SPY SCRIPT
    Отправляет данные Explorer и Remote Spy на локальный сервер
    
    Использование:
    1. Запустите server.js (npm start)
    2. Откройте http://localhost:3847
    3. Выполните этот скрипт в Roblox через эксплойт
]]

-- Конфигурация
local CONFIG = {
    SERVER_URL = "http://localhost:3847",
    SEND_EXPLORER = true,
    SEND_REMOTES = true,
    EXPLORER_DEPTH = 5,
    UPDATE_INTERVAL = 30,
}

-- Определяем функцию HTTP запроса (зависит от эксплойта)
local httpRequest = nil

if syn and syn.request then
    httpRequest = syn.request
elseif request then
    httpRequest = request
elseif http_request then
    httpRequest = http_request
elseif http and http.request then
    httpRequest = http.request
elseif fluxus and fluxus.request then
    httpRequest = fluxus.request
end

if not httpRequest then
    warn("⚠️ No HTTP request function found! This exploit may not support HTTP.")
    return
end

-- Сервисы
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- Получаем ID игры
local gameId = tostring(game.PlaceId)
local gameName = "Loading..."

-- Получаем название игры
pcall(function()
    local info = MarketplaceService:GetProductInfo(game.PlaceId)
    if info and info.Name then
        gameName = info.Name
    end
end)

print("========================================")
print("🔶 ROBLOX SPY SCRIPT")
print("========================================")
print("📍 Game ID: " .. gameId)
print("📍 Game Name: " .. gameName)
print("🌐 Server: " .. CONFIG.SERVER_URL)
print("========================================")

-- HTTP POST функция
local function httpPost(url, data)
    local success, result = pcall(function()
        return httpRequest({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = data
        })
    end)
    
    return success, result
end

-- HTTP GET функция
local function httpGet(url)
    local success, result = pcall(function()
        return httpRequest({
            Url = url,
            Method = "GET"
        })
    end)
    
    return success, result
end

-- Тест подключения к серверу
local function testConnection()
    local success, result = httpGet(CONFIG.SERVER_URL .. "/api/games")
    
    if success and result and result.StatusCode == 200 then
        print("✅ Server connection OK!")
        return true
    else
        print("❌ Server connection FAILED!")
        if result then
            print("   Status: " .. tostring(result.StatusCode or "unknown"))
        end
        print("   Make sure server is running (npm start)")
        return false
    end
end

-- ============================================
-- EXPLORER
-- ============================================

local function getProperties(obj)
    local props = {}
    
    pcall(function()
        props.Name = obj.Name
        props.ClassName = obj.ClassName
        props.Parent = obj.Parent and obj.Parent.Name or "nil"
    end)
    
    pcall(function() props.Archivable = obj.Archivable end)
    
    pcall(function()
        if obj:IsA("BasePart") then
            props.Anchored = obj.Anchored
            props.CanCollide = obj.CanCollide
            props.Transparency = obj.Transparency
            props.Size = tostring(obj.Size)
            props.Position = tostring(obj.Position)
        end
    end)
    
    return props
end

local function buildTree(obj, depth)
    if depth <= 0 then return nil end
    
    local node = {
        name = obj.Name,
        className = obj.ClassName,
        properties = getProperties(obj),
        children = {}
    }
    
    pcall(function()
        for _, child in ipairs(obj:GetChildren()) do
            local childNode = buildTree(child, depth - 1)
            if childNode then
                table.insert(node.children, childNode)
            end
        end
    end)
    
    return node
end

local function sendExplorerData()
    if not CONFIG.SEND_EXPLORER then return end
    
    print("📦 Building explorer tree...")
    
    local tree = {
        name = "game",
        className = "DataModel",
        children = {}
    }
    
    local services = {
        "Workspace",
        "Players", 
        "Lighting",
        "ReplicatedStorage",
        "ReplicatedFirst",
        "StarterGui",
        "StarterPack",
        "StarterPlayer",
        "SoundService",
        "Chat",
    }
    
    for _, serviceName in ipairs(services) do
        pcall(function()
            local service = game:GetService(serviceName)
            local serviceTree = buildTree(service, CONFIG.EXPLORER_DEPTH)
            if serviceTree then
                table.insert(tree.children, serviceTree)
            end
        end)
    end
    
    local data = HttpService:JSONEncode({
        gameId = gameId,
        gameName = gameName,
        tree = tree
    })
    
    local success, result = httpPost(CONFIG.SERVER_URL .. "/api/explorer", data)
    
    if success and result and result.StatusCode == 200 then
        print("✅ Explorer data sent!")
    else
        print("❌ Failed to send explorer data")
    end
end

-- ============================================
-- REMOTE SPY
-- ============================================

local function formatArg(arg)
    local t = typeof(arg)
    
    if t == "string" then
        return arg
    elseif t == "number" or t == "boolean" then
        return arg
    elseif t == "nil" then
        return nil
    elseif t == "Instance" then
        return {_type = "Instance", path = arg:GetFullName(), class = arg.ClassName}
    elseif t == "Vector3" then
        return {_type = "Vector3", x = arg.X, y = arg.Y, z = arg.Z}
    elseif t == "CFrame" then
        return {_type = "CFrame", position = tostring(arg.Position)}
    elseif t == "Color3" then
        return {_type = "Color3", r = arg.R, g = arg.G, b = arg.B}
    elseif t == "table" then
        local result = {}
        for k, v in pairs(arg) do
            result[tostring(k)] = formatArg(v)
        end
        return result
    else
        return tostring(arg)
    end
end

local function sendRemoteEvent(remote, args, isFunction)
    if not CONFIG.SEND_REMOTES then return end
    
    local formattedArgs = {}
    for i, arg in ipairs(args) do
        formattedArgs[i] = formatArg(arg)
    end
    
    pcall(function()
        local path = remote:GetFullName():gsub("^game%.", "")
        
        local data = HttpService:JSONEncode({
            gameId = gameId,
            gameName = gameName,
            remote = {
                name = remote.Name,
                path = path,
                type = isFunction and "RemoteFunction" or "RemoteEvent",
                args = formattedArgs
            }
        })
        
        httpPost(CONFIG.SERVER_URL .. "/api/remote", data)
    end)
end

-- Хукаем ремоуты
local function hookRemotes()
    local mt = getrawmetatable(game)
    if not mt then
        print("⚠️ getrawmetatable not available - Remote Spy disabled")
        return false
    end
    
    local oldNamecall = mt.__namecall
    
    local success = pcall(function()
        setreadonly(mt, false)
        
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            
            if method == "FireServer" and self:IsA("RemoteEvent") then
                task.spawn(function()
                    sendRemoteEvent(self, args, false)
                end)
            elseif method == "InvokeServer" and self:IsA("RemoteFunction") then
                task.spawn(function()
                    sendRemoteEvent(self, args, true)
                end)
            end
            
            return oldNamecall(self, ...)
        end)
        
        setreadonly(mt, true)
    end)
    
    if success then
        print("✅ Remote hooks installed!")
        return true
    else
        print("⚠️ Failed to install remote hooks")
        return false
    end
end

-- ============================================
-- MAIN
-- ============================================

-- Тестируем подключение
if not testConnection() then
    warn("⚠️ Cannot connect to server! Make sure to run 'npm start' first!")
end

-- Отправляем данные explorer
task.spawn(function()
    task.wait(2)
    sendExplorerData()
    
    while task.wait(CONFIG.UPDATE_INTERVAL) do
        sendExplorerData()
    end
end)

-- Устанавливаем хуки на ремоуты
hookRemotes()

print("")
print("========================================")
print("✅ ROBLOX SPY READY!")
print("🌐 Open in browser: http://localhost:3847")
print("========================================")
