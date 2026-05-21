-- Remote Caller - выполняет код и выводит полный ответ с возможностью копирования
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
	Name = "Remote Caller",
	LoadingTitle = "Remote Caller",
	LoadingSubtitle = "by sigmatik323",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "RemoteCaller"
	},
	KeySystem = false
})

local TabMain = Window:CreateTab("📞 Remote Caller", 4483362458)

-- Переменные для хранения последнего результата
local lastResult = nil
local lastResultString = ""

-- Функция для глубокой конвертации в строку (полная версия)
local function deepToString(value, indent)
	indent = indent or 0
	local indentStr = string.rep("\t", indent)
	local nextIndent = string.rep("\t", indent + 1)
	
	local valueType = typeof(value)
	
	if valueType == "string" then
		return '"' .. value .. '"'
	elseif valueType == "number" then
		return tostring(value)
	elseif valueType == "boolean" then
		return tostring(value)
	elseif valueType == "nil" then
		return "nil"
	elseif valueType == "table" then
		local parts = {}
		local isArray = true
		local maxIndex = 0
		
		-- Проверяем, массив ли это
		for k, v in pairs(value) do
			if type(k) ~= "number" then
				isArray = false
				break
			end
			if k > maxIndex then maxIndex = k end
		end
		
		if isArray and maxIndex > 0 then
			-- Массив
			for i = 1, maxIndex do
				table.insert(parts, nextIndent .. deepToString(value[i], indent + 1))
			end
		else
			-- Словарь
			for k, v in pairs(value) do
				local keyStr
				if type(k) == "string" then
					if k:match("^[%a_][%w_]*$") then
						keyStr = k
					else
						keyStr = '["' .. k .. '"]'
					end
				else
					keyStr = "[" .. tostring(k) .. "]"
				end
				table.insert(parts, nextIndent .. keyStr .. " = " .. deepToString(v, indent + 1))
			end
		end
		
		if #parts == 0 then
			return "{}"
		else
			return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indentStr .. "}"
		end
		
	elseif valueType == "Instance" then
		return 'game:GetService("' .. value.ClassName .. '") -- ' .. value:GetFullName()
	elseif valueType == "Vector3" then
		return string.format("Vector3.new(%.10g, %.10g, %.10g)", value.X, value.Y, value.Z)
	elseif valueType == "Vector2" then
		return string.format("Vector2.new(%.10g, %.10g)", value.X, value.Y)
	elseif valueType == "CFrame" then
		local components = {value:GetComponents()}
		return string.format("CFrame.new(%.10g, %.10g, %.10g, %.10g, %.10g, %.10g, %.10g, %.10g, %.10g, %.10g, %.10g, %.10g)", 
			unpack(components))
	elseif valueType == "Color3" then
		return string.format("Color3.new(%.16g, %.16g, %.16g)", value.R, value.G, value.B)
	elseif valueType == "BrickColor" then
		return 'BrickColor.new("' .. value.Name .. '")'
	elseif valueType == "UDim" then
		return string.format("UDim.new(%.10g, %d)", value.Scale, value.Offset)
	elseif valueType == "UDim2" then
		return string.format("UDim2.new(%.10g, %d, %.10g, %d)", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
	elseif valueType == "Rect" then
		return string.format("Rect.new(%.10g, %.10g, %.10g, %.10g)", value.Min.X, value.Min.Y, value.Max.X, value.Max.Y)
	elseif valueType == "EnumItem" then
		return tostring(value)
	elseif valueType == "NumberSequence" then
		local keypoints = {}
		for _, kp in ipairs(value.Keypoints) do
			table.insert(keypoints, string.format("NumberSequenceKeypoint.new(%.10g, %.10g, %.10g)", kp.Time, kp.Value, kp.Envelope))
		end
		return "NumberSequence.new({" .. table.concat(keypoints, ", ") .. "})"
	elseif valueType == "ColorSequence" then
		local keypoints = {}
		for _, kp in ipairs(value.Keypoints) do
			table.insert(keypoints, string.format("ColorSequenceKeypoint.new(%.10g, Color3.new(%.10g, %.10g, %.10g))", 
				kp.Time, kp.Value.R, kp.Value.G, kp.Value.B))
		end
		return "ColorSequence.new({" .. table.concat(keypoints, ", ") .. "})"
	else
		return "-- " .. valueType .. ": " .. tostring(value)
	end
end

-- Функция для выполнения кода
local function executeCode(code)
	-- Оборачиваем код чтобы получить return
	local wrappedCode = "return " .. code
	
	local func, compileError = loadstring(wrappedCode)
	if not func then
		-- Попробуем без return (если это statement)
		func, compileError = loadstring(code)
		if not func then
			return false, "Compile error: " .. tostring(compileError)
		end
	end
	
	local success, result = pcall(func)
	return success, result
end

-- UI
TabMain:CreateSection("📞 Execute Code")

local codeInput = ""
TabMain:CreateInput({
	Name = "Lua Code",
	PlaceholderText = 'game:GetService("ReplicatedStorage"):WaitForChild("RollReward"):InvokeServer()',
	RemoveTextAfterFocusLost = false,
	Callback = function(Text)
		codeInput = Text
	end
})

TabMain:CreateButton({
	Name = "🚀 Execute & Get Result",
	Callback = function()
		if codeInput == "" then
			Rayfield:Notify({
				Title = "❌ Error",
				Content = "Enter code first!",
				Duration = 3
			})
			return
		end
		
		Rayfield:Notify({
			Title = "⏳ Executing...",
			Content = "Running code...",
			Duration = 2
		})
		
		local success, result = executeCode(codeInput)
		
		if success then
			lastResult = result
			lastResultString = deepToString(result, 0)
			
			print("═══════════════════════════════════════════════════════════")
			print("📞 Code: " .. codeInput)
			print("📥 Result:")
			print(lastResultString)
			print("═══════════════════════════════════════════════════════════")
			
			Rayfield:Notify({
				Title = "✅ Success!",
				Content = "Result printed to console (F9). Click 'Copy Result' to copy.",
				Duration = 4
			})
		else
			lastResultString = "ERROR: " .. tostring(result)
			print("❌ ERROR: " .. tostring(result))
			
			Rayfield:Notify({
				Title = "❌ Error",
				Content = tostring(result),
				Duration = 4
			})
		end
	end
})

TabMain:CreateSection("📋 Result")

TabMain:CreateButton({
	Name = "📋 Copy Result to Clipboard",
	Callback = function()
		if lastResultString == "" then
			Rayfield:Notify({
				Title = "❌ No Result",
				Content = "Execute code first!",
				Duration = 3
			})
			return
		end
		
		if setclipboard then
			setclipboard(lastResultString)
			Rayfield:Notify({
				Title = "✅ Copied!",
				Content = "Result copied to clipboard",
				Duration = 3
			})
		else
			Rayfield:Notify({
				Title = "❌ Error",
				Content = "setclipboard not available",
				Duration = 3
			})
		end
	end
})

TabMain:CreateButton({
	Name = "📋 Copy as Lua Table",
	Callback = function()
		if lastResultString == "" then
			Rayfield:Notify({
				Title = "❌ No Result",
				Content = "Execute code first!",
				Duration = 3
			})
			return
		end
		
		local luaCode = "local result = " .. lastResultString
		
		if setclipboard then
			setclipboard(luaCode)
			Rayfield:Notify({
				Title = "✅ Copied!",
				Content = "Lua code copied to clipboard",
				Duration = 3
			})
		else
			Rayfield:Notify({
				Title = "❌ Error",
				Content = "setclipboard not available",
				Duration = 3
			})
		end
	end
})

TabMain:CreateButton({
	Name = "🔄 Print Last Result Again",
	Callback = function()
		if lastResultString == "" then
			Rayfield:Notify({
				Title = "❌ No Result",
				Content = "Execute code first!",
				Duration = 3
			})
			return
		end
		
		print("═══════════════════════════════════════════════════════════")
		print("📥 Last Result:")
		print(lastResultString)
		print("═══════════════════════════════════════════════════════════")
	end
})

print("📞 Remote Caller loaded! Enter full Lua code and click 'Execute & Get Result'")
