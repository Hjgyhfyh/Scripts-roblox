local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local BATCH_SIZE = 50
local BATCH_DELAY = 0.1
local processedCount = 0

local function getGameName()
    local success, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    if success and info and info.Name then
        local name = info.Name:gsub("[\\/:*?\"<>|]", "_")
        name = name:gsub("[^%w%s%-%_%.]", "")
        name = name:gsub("%s+", " ")
        name = name:match("^%s*(.-)%s*$")
        if name == "" then
            name = "Game_" .. tostring(game.PlaceId)
        end
        return name
    else
        return "UnknownGame_" .. tostring(game.PlaceId)
    end
end

local function saveToFile(path, content)
    if writefile then
        writefile(path, content)
        return true
    end
    return false
end

local function createFolder(path)
    if makefolder then
        pcall(function()
            makefolder(path)
        end)
        return true
    end
    return false
end

local function generateTreeView(instance, indent, lines)
    indent = indent or 0
    lines = lines or {}
    local tabs = string.rep("  ", indent)
    
    local icon = ""
    if instance.ClassName == "Folder" then icon = "[DIR]"
    elseif instance.ClassName == "Part" then icon = "[PART]"
    elseif instance.ClassName == "Model" then icon = "[MDL]"
    elseif instance.ClassName == "Script" then icon = "[S]"
    elseif instance.ClassName == "LocalScript" then icon = "[LS]"
    elseif instance.ClassName == "ModuleScript" then icon = "[MS]"
    elseif instance.ClassName == "RemoteEvent" then icon = "[RE]"
    elseif instance.ClassName == "RemoteFunction" then icon = "[RF]"
    elseif instance.ClassName == "BindableEvent" then icon = "[BE]"
    elseif instance.ClassName == "BindableFunction" then icon = "[BF]"
    else icon = "-" end
    
    table.insert(lines, tabs .. icon .. " [" .. instance.ClassName .. "] " .. instance.Name)
    
    processedCount = processedCount + 1
    if processedCount % BATCH_SIZE == 0 then
        task.wait(BATCH_DELAY)
    end
    
    for _, child in pairs(instance:GetChildren()) do
        generateTreeView(child, indent + 1, lines)
    end
    
    return lines
end

local function dumpInstance(instance, basePath)
    local queue = {{inst = instance, path = basePath}}
    local index = 1
    
    while index <= #queue do
        local current = queue[index]
        local inst = current.inst
        local currentPath = current.path
        
        local safeName = inst.Name:gsub("[\\/:*?\"<>|]", "_")
        local folderPath = currentPath .. "/" .. safeName
        
        createFolder(folderPath)
        
        local info = "ClassName: " .. inst.ClassName .. "\n"
        info = info .. "Name: " .. inst.Name .. "\n"
        info = info .. "FullName: " .. inst:GetFullName() .. "\n"
        info = info .. "Children Count: " .. #inst:GetChildren() .. "\n"
        
        pcall(function()
            for _, prop in pairs({"Position", "Size", "Color", "BrickColor", "Material", "Transparency", "Anchored", "CanCollide", "Value", "Text", "Source"}) do
                pcall(function()
                    info = info .. prop .. ": " .. tostring(inst[prop]) .. "\n"
                end)
            end
        end)
        
        saveToFile(folderPath .. "/_info.txt", info)
        
        if inst.ClassName == "ModuleScript" or inst.ClassName == "LocalScript" or inst.ClassName == "Script" then
            pcall(function()
                if inst.Source and inst.Source ~= "" then
                    saveToFile(folderPath .. "/" .. safeName .. ".lua", inst.Source)
                end
            end)
            pcall(function()
                local decompiled = decompile(inst)
                if decompiled then
                    saveToFile(folderPath .. "/" .. safeName .. "_decompiled.lua", decompiled)
                end
            end)
        end
        
        for _, child in pairs(inst:GetChildren()) do
            table.insert(queue, {inst = child, path = folderPath})
        end
        
        index = index + 1
        
        if index % BATCH_SIZE == 0 then
            task.wait(BATCH_DELAY)
        end
    end
end

local function dumpService(serviceName, workspacePath)
    print("[AutoDump] Dumping " .. serviceName .. "...")
    task.wait(0.5)
    
    processedCount = 0
    local service = game:GetService(serviceName)
    
    createFolder(workspacePath .. "/" .. serviceName)
    
    local tree = generateTreeView(service)
    saveToFile(workspacePath .. "/" .. serviceName .. "/_tree.txt", table.concat(tree, "\n"))
    
    task.wait(0.5)
    
    dumpInstance(service, workspacePath .. "/" .. serviceName)
    
    print("[AutoDump] " .. serviceName .. " done!")
    task.wait(1)
end

local function main()
    local gameName = getGameName()
    print("[AutoDump] Game Name: " .. gameName)
    
    local workspacePath = gameName
    createFolder(workspacePath)
    
    saveToFile(workspacePath .. "/Remotes.txt", "")
    
    task.wait(0.5)
    
    dumpService("Workspace", workspacePath)
    dumpService("ReplicatedStorage", workspacePath)
    
    pcall(function()
        dumpService("CoreGui", workspacePath)
    end)
    
    local summary = "=== AUTO DUMP SUMMARY ===\n"
    summary = summary .. "Game: " .. gameName .. "\n"
    summary = summary .. "PlaceId: " .. game.PlaceId .. "\n"
    summary = summary .. "Date: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    summary = summary .. "\nDumped Services:\n"
    summary = summary .. "- Workspace\n"
    summary = summary .. "- ReplicatedStorage\n"
    summary = summary .. "- CoreGui\n"
    saveToFile(workspacePath .. "/_summary.txt", summary)
    
    print("[AutoDump] Dump completed! Saved to: " .. workspacePath)
    print("[AutoDump] Check Remotes.txt to record remotes")
    
    local Player = Players.LocalPlayer
    local VirtualUser = game:GetService("VirtualUser")
    Player.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

main()
