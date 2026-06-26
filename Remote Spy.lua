-- Remote Spy - логирует все вызовы RemoteEvent и RemoteFunction
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
	Name = "Remote Spy",
	LoadingTitle = "Remote Spy",
	LoadingSubtitle = "by sigmatik323",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "RemoteSpy"
	},
	KeySystem = false
})

local TabMain = Window:CreateTab("🔍 Remote Spy", 4483362458)

-- Variables
local spyEnabled = false
local logEvents = true
local logFunctions = true
local filterName = ""

-- Сохраняем оригинальные методы
local oldNamecall
local oldIndex

-- Функция для конвертации значения в строку
local function valueToString(value, depth)
	depth = depth or 0
	if depth > 3 then return "..." end
	
	local valueType = typeof(value)
	
	if valueType == "string" then
		return '"' .. value .. '"'
	elseif valueType == "number" or valueType == "boolean" then
		return tostring(value)
	elseif valueType == "nil" then
		return "nil"
	elseif valueType == "table" then
		local parts = {}
		local count = 0
		for k, v in pairs(value) do
			count = count + 1
			if count > 10 then
				table.insert(parts, "...")
				break
			end
			local keyStr = type(k) == "number" and "[" .. k .. "]" or k
			table.insert(parts, keyStr .. " = " .. valueToString(v, depth + 1))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif valueType == "Instance" then
		return value:GetFullName()
	elseif valueType == "Vector3" then
		return string.format("Vector3.new(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
	elseif valueType == "CFrame" then
		return string.format("CFrame.new(%.2f, %.2f, %.2f)", value.Position.X, value.Position.Y, value.Position.Z)
	elseif valueType == "Color3" then
		return string.format("Color3.new(%.3f, %.3f, %.3f)", value.R, value.G, value.B)
	elseif valueType == "BrickColor" then
		return "BrickColor.new(\"" .. value.Name .. "\")"
	elseif valueType == "EnumItem" then
		return tostring(value)
	else
		return tostring(valueType) .. "<" .. tostring(value) .. ">"
	end
end

-- Функция для логирования аргументов
local function logArgs(args)
	local argStrings = {}
	for i, arg in ipairs(args) do
		table.insert(argStrings, valueToString(arg))
	end
	return table.concat(argStrings, ", ")
end

-- Функция для логирования
local function logRemote(remoteName, remoteType, args, returnValue)
	if filterName ~= "" and not string.find(string.lower(remoteName), string.lower(filterName)) then
		return
	end
	
	print("══════════════════════════════════════")
	print("📡 Remote: " .. remoteName)
	print("🏷️ Type: " .. remoteType)
	print("📤 Args: " .. logArgs(args))
	
	if returnValue ~= nil then
		if type(returnValue) == "table" then
			print("📥 Return:")
			for i, v in ipairs(returnValue) do
				print("  [" .. i .. "] = " .. valueToString(v))
			end
		else
			print("📥 Return: " .. valueToString(returnValue))
		end
	end
	
	print("══════════════════════════════════════")
end

local function enableSpy()
	if oldNamecall then return end
	
	oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
		local args = {...}
		local method = getnamecallmethod()
		
		if spyEnabled then
			if method == "FireServer" and self:IsA("RemoteEvent") and logEvents then
				logRemote(self.Name, "RemoteEvent", args, nil)
			elseif method == "InvokeServer" and self:IsA("RemoteFunction") and logFunctions then
				local results = {oldNamecall(self, ...)}
				logRemote(self.Name, "RemoteFunction", args, results)
				return unpack(results)
			end
		end
		
		return oldNamecall(self, ...)
	end)
	
	print("✅ Remote Spy hook installed!")
end

-- UI Elements
TabMain:CreateSection("⚙️ Settings")

TabMain:CreateToggle({
	Name = "Enable Remote Spy",
	CurrentValue = false,
	Flag = "RemoteSpyToggle",
	Callback = function(Value)
		spyEnabled = Value
		if Value then
			enableSpy()
			Rayfield:Notify({
				Title = "🔍 Remote Spy",
				Content = "Spy enabled! Check console (F9)",
				Duration = 3
			})
		else
			Rayfield:Notify({
				Title = "🔍 Remote Spy",
				Content = "Spy disabled",
				Duration = 2
			})
		end
	end
})

TabMain:CreateToggle({
	Name = "Log RemoteEvents",
	CurrentValue = true,
	Flag = "LogEventsToggle",
	Callback = function(Value)
		logEvents = Value
	end
})

TabMain:CreateToggle({
	Name = "Log RemoteFunctions",
	CurrentValue = true,
	Flag = "LogFunctionsToggle",
	Callback = function(Value)
		logFunctions = Value
	end
})

TabMain:CreateSection("🔎 Filter")

TabMain:CreateInput({
	Name = "Filter by Name",
	PlaceholderText = "Remote name filter...",
	RemoveTextAfterFocusLost = false,
	Callback = function(Text)
		filterName = Text
		if Text ~= "" then
			Rayfield:Notify({
				Title = "🔎 Filter Set",
				Content = "Only showing remotes containing: " .. Text,
				Duration = 2
			})
		end
	end
})

TabMain:CreateButton({
	Name = "Clear Filter",
	Callback = function()
		filterName = ""
		Rayfield:Notify({
			Title = "🔎 Filter Cleared",
			Content = "Showing all remotes",
			Duration = 2
		})
	end
})

TabMain:CreateSection("📋 Actions")

TabMain:CreateButton({
	Name = "Clear Console",
	Callback = function()
		-- Очистка консоли (работает в некоторых эксплойтах)
		if clearconsole then
			clearconsole()
		elseif consoleclear then
			consoleclear()
		else
			for i = 1, 50 do
				print("")
			end
		end
	end
})

print("📡 Remote Spy loaded! Toggle 'Enable Remote Spy' to start logging.")
