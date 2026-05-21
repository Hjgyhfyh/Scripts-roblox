-- Saber Tsunami Auto Suite (sigmatik library + autoplay)
local SigmatikLibrary = (function()
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GUI_NAME = "SigmatikClickGui"
local BLUR_NAME = GUI_NAME .. "Blur"
local WHITE = "#ffffffff"
local CHECK_ICON = utf8.char(0x2713)

local DEFAULT_THEME = {
	Accent = "#3b82f6",
	AccentSoft = "#60a5fa",
	WindowFill = "#0b1020d9",
	DimBackground = "#02061766",
	BlurSize = 14,
}

local DEFAULT_PALETTE = {
	"#ff4444",
	"#22c55e",
	"#3b82f6",
	"#f59e0b",
	"#a855f7",
}

local FAST_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SOFT_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local PANEL_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Controller = {}
Controller.__index = Controller

local CYRILLIC_LOWER_MAP = {
	["А"]="а", ["Б"]="б", ["В"]="в", ["Г"]="г", ["Д"]="д", ["Е"]="е", ["Ё"]="ё",
	["Ж"]="ж", ["З"]="з", ["И"]="и", ["Й"]="й", ["К"]="к", ["Л"]="л", ["М"]="м",
	["Н"]="н", ["О"]="о", ["П"]="п", ["Р"]="р", ["С"]="с", ["Т"]="т", ["У"]="у",
	["Ф"]="ф", ["Х"]="х", ["Ц"]="ц", ["Ч"]="ч", ["Ш"]="ш", ["Щ"]="щ", ["Ъ"]="ъ",
	["Ы"]="ы", ["Ь"]="ь", ["Э"]="э", ["Ю"]="ю", ["Я"]="я",
}

local function lowerLocale(text)
	if type(text) ~= "string" then return "" end
	text = string.lower(text)
	-- Replace Cyrillic upper chars (UTF-8 two-byte) using literal byte sequences.
	for upper, lower in pairs(CYRILLIC_LOWER_MAP) do
		text = text:gsub(upper, lower)
	end
	return text
end

local function shallowCopy(source)
	local result = {}
	for key, value in pairs(source or {}) do
		result[key] = value
	end
	return result
end

local function arrayCopy(source)
	local result = {}
	for index, value in ipairs(source or {}) do
		result[index] = value
	end
	return result
end

local hexCache = {}

local function parseHex(hex)
	if type(hex) ~= "string" then
		return Color3.fromRGB(255, 255, 255), 0
	end
	local cached = hexCache[hex]
	if cached then
		return cached[1], cached[2]
	end
	local clean = hex:gsub("#", "")
	if #clean == 3 then
		clean = clean:sub(1,1):rep(2) .. clean:sub(2,2):rep(2) .. clean:sub(3,3):rep(2) .. "ff"
	end
	if #clean == 6 then
		clean = clean .. "ff"
	end
	if #clean < 8 then
		return Color3.fromRGB(255, 255, 255), 0
	end

	local r = tonumber(clean:sub(1, 2), 16) or 255
	local g = tonumber(clean:sub(3, 4), 16) or 255
	local b = tonumber(clean:sub(5, 6), 16) or 255
	local a = tonumber(clean:sub(7, 8), 16) or 255

	local color = Color3.fromRGB(r, g, b)
	local transparency = 1 - (a / 255)
	hexCache[hex] = { color, transparency }
	return color, transparency
end

local function colorToHex(color, alpha)
	local a = alpha or 1
	local r = math.clamp(math.floor(color.R * 255 + 0.5), 0, 255)
	local g = math.clamp(math.floor(color.G * 255 + 0.5), 0, 255)
	local b = math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	return string.format("#%02x%02x%02x%02x", r, g, b, math.floor(math.clamp(a, 0, 1) * 255))
end

local function hueToHex(hue, alpha, saturation, value)
	if hue ~= hue or hue == math.huge or hue == -math.huge then
		hue = 0
	end
	hue = math.clamp(hue, 0, 1)
	local s = saturation or 0.72
	local v = value or 1
	if s ~= s then s = 0.72 end
	if v ~= v then v = 1 end
	return colorToHex(Color3.fromHSV(hue, s, v), alpha)
end

local function hexToHue(hex)
	local color = select(1, parseHex(hex))
	local hue, sat, val = color:ToHSV()
	if sat < 0.05 then
		return 0, sat, val
	end
	return hue, sat, val
end

local function withAlpha(hex, alphaHex)
	local color = select(1, parseHex(hex))
	local r = math.clamp(math.floor(color.R * 255 + 0.5), 0, 255)
	local g = math.clamp(math.floor(color.G * 255 + 0.5), 0, 255)
	local b = math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	return string.format("#%02x%02x%02x%s", r, g, b, alphaHex)
end

local function mixColors(base, target, alpha)
	return Color3.new(
		base.R + (target.R - base.R) * alpha,
		base.G + (target.G - base.G) * alpha,
		base.B + (target.B - base.B) * alpha
	)
end

local function roundNearest(x)
	if x >= 0 then
		return math.floor(x + 0.5)
	end
	return -math.floor(-x + 0.5)
end

local function clampRound(value, minimum, maximum, increment)
	if value ~= value then value = minimum end
	if value == math.huge then value = maximum end
	if value == -math.huge then value = minimum end
	if maximum < minimum then
		maximum = minimum
	end
	local clamped = math.clamp(value, minimum, maximum)
	local step = increment and increment > 0 and increment or 1
	local rounded = minimum + roundNearest((clamped - minimum) / step) * step
	return math.clamp(rounded, minimum, maximum)
end

local function parseNumberInput(text)
	if type(text) == "number" then return text end
	if type(text) ~= "string" then return nil end
	local s = text:gsub(",", "."):gsub("%s+", "")
	local num, suffix = s:match("^(-?%d*%.?%d+)([kKmMbBтТмМкК]?)")
	if not num then return nil end
	local n = tonumber(num)
	if not n then return nil end
	suffix = suffix:lower()
	if suffix == "k" or suffix == "к" then n = n * 1e3
	elseif suffix == "m" or suffix == "м" then n = n * 1e6
	elseif suffix == "b" then n = n * 1e9
	elseif suffix == "т" then n = n * 1e9 end
	return n
end

local function formatSliderValue(value, increment)
	local step = increment or 1
	if step == math.floor(step) then
		return tostring(math.floor(roundNearest(value)))
	end
	local decimals = 0
	local s = tostring(step)
	local dot = s:find("%.")
	if dot then
		decimals = #s - dot
	end
	if decimals < 1 then decimals = 1 end
	if decimals > 6 then decimals = 6 end
	return string.format("%." .. decimals .. "f", value)
end

local function findColorValue(palette, value)
	if type(value) == "number" then
		return palette[value] or palette[1]
	end

	local wanted = string.lower(tostring(value or palette[1]))
	for _, hex in ipairs(palette) do
		if string.lower(hex) == wanted then
			return hex
		end
	end

	return palette[1]
end

local function getFillTransparency(hex)
	return select(2, parseHex(hex))
end

local function destroyExisting()
	local protectedParent = gethui and gethui()
	local existing = (protectedParent and protectedParent:FindFirstChild(GUI_NAME)) or CoreGui:FindFirstChild(GUI_NAME)
	if existing then
		pcall(function()
			existing:SetAttribute("SigmatikDestroyed", true)
		end)
		existing:Destroy()
	end

	local existingBlur = Lighting:FindFirstChild(BLUR_NAME)
	if existingBlur then
		existingBlur:Destroy()
	end
end

local function fontForWeight(weight)
	if weight >= 700 then
		return Enum.Font.GothamBold
	end

	if weight >= 500 then
		return Enum.Font.GothamMedium
	end

	return Enum.Font.Gotham
end

local function create(className, props)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	return instance
end

local function clearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function applyFill(guiObject, hex)
	local color, transparency = parseHex(hex)
	guiObject.BackgroundColor3 = color
	guiObject.BackgroundTransparency = transparency
end

local function applyTextColor(textObject, hex)
	local color, transparency = parseHex(hex)
	textObject.TextColor3 = color
	textObject.TextTransparency = transparency
end

local function applyStroke(stroke, hex)
	local color, transparency = parseHex(hex)
	stroke.Color = color
	stroke.Transparency = transparency
end

local function addCorner(parent, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius),
		Parent = parent,
	})
end

local function addStroke(parent, thickness, hex)
	local stroke = create("UIStroke", {
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
	applyStroke(stroke, hex)
	return stroke
end

local function addPadding(parent, left, right, top, bottom)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right),
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bottom),
		Parent = parent,
	})
end

local function addListLayout(parent, direction, padding)
	return create("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

local function addScale(parent, value)
	return create("UIScale", {
		Scale = value or 1,
		Parent = parent,
	})
end

local function addGradient(parent, rotation, hexList)
	local keypoints = {}
	if #hexList < 2 then
		local soleColor = select(1, parseHex(hexList[1] or WHITE))
		table.insert(keypoints, ColorSequenceKeypoint.new(0, soleColor))
		table.insert(keypoints, ColorSequenceKeypoint.new(1, soleColor))
	else
		local count = #hexList - 1
		for index, hex in ipairs(hexList) do
			table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / count, select(1, parseHex(hex))))
		end
	end

	return create("UIGradient", {
		Rotation = rotation or 0,
		Color = ColorSequence.new(keypoints),
		Parent = parent,
	})
end

local function createPaintFrame(parent, props, paints)
	local frame = create("Frame", props)
	table.insert(paints, { kind = "fill", object = frame })
	return frame
end

local function createPaintStroke(parent, thickness, hex, paints)
	local stroke = addStroke(parent, thickness, hex)
	table.insert(paints, { kind = "stroke", object = stroke })
	return stroke
end

local function addIconPart(parts, kind, object)
	table.insert(parts, { kind = kind, object = object })
	return object
end

local function updateGradient(gradient, firstHex, secondHex)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, select(1, parseHex(firstHex))),
		ColorSequenceKeypoint.new(1, select(1, parseHex(secondHex))),
	})
end

local function tween(object, info, props)
	local tweenObject = TweenService:Create(object, info, props)
	tweenObject:Play()
	return tweenObject
end

local function animateFill(guiObject, hex, info)
	local color, transparency = parseHex(hex)
	return tween(guiObject, info or SOFT_TWEEN, {
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
	})
end

local function animateText(textObject, hex, info)
	local color, transparency = parseHex(hex)
	return tween(textObject, info or SOFT_TWEEN, {
		TextColor3 = color,
		TextTransparency = transparency,
	})
end

local function animateStroke(stroke, hex, info)
	local color, transparency = parseHex(hex)
	return tween(stroke, info or SOFT_TWEEN, {
		Color = color,
		Transparency = transparency,
	})
end

local function animateSize(guiObject, size, info)
	return tween(guiObject, info or SOFT_TWEEN, {
		Size = size,
	})
end

local function animatePosition(guiObject, position, info)
	return tween(guiObject, info or SOFT_TWEEN, {
		Position = position,
	})
end

local function animateScale(scaleObject, scale, info)
	return tween(scaleObject, info or SOFT_TWEEN, {
		Scale = scale,
	})
end

local function pulse(scaleObject, peakScale, settleScale)
	if not scaleObject or not scaleObject.Parent then return end
	animateScale(scaleObject, peakScale, POP_TWEEN)
	task.delay(0.08, function()
		if scaleObject and scaleObject.Parent then
			animateScale(scaleObject, settleScale or 1, SOFT_TWEEN)
		end
	end)
end

local function fireCallback(callback, ...)
	if type(callback) == "function" then
		task.spawn(callback, ...)
	end
end

local function keyCodeToLabel(keyCode)
	if not keyCode or keyCode == Enum.KeyCode.Unknown then
		return "None"
	end

	local name = keyCode.Name
	name = name:gsub("Left", "L ")
	name = name:gsub("Right", "R ")
	return name
end

local function createIcon(parent, iconName, size, zIndex)
	local container = create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ZIndex = zIndex,
		Parent = parent,
	})
	local parts = {}
	local center = size / 2

	local function addBar(width, height, x, y, rotation)
		local bar = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, height),
			BorderSizePixel = 0,
			Rotation = rotation or 0,
			ZIndex = zIndex,
			Parent = container,
		})
		addCorner(bar, math.min(width, height))
		return addIconPart(parts, "fill", bar)
	end

	local function addRing(width, height, x, y, thickness)
		local ring = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, height),
			BackgroundTransparency = 1,
			ZIndex = zIndex,
			Parent = container,
		})
		addCorner(ring, math.min(width, height))
		local stroke = createPaintStroke(ring, thickness or 1.4, "#ffffff", parts)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		return ring
	end

	if iconName == "search" then
		addRing(size - 7, size - 7, center - 2, center - 2, 1.5)
		addBar(2, 7, center + 4, center + 4, -45)
	elseif iconName == "settings" then
		addRing(8, 8, center, center, 1.4)
		addBar(2, 4, center, center - 5, 0)
		addBar(2, 4, center, center + 5, 0)
		addBar(4, 2, center - 5, center, 0)
		addBar(4, 2, center + 5, center, 0)
	elseif iconName == "x" then
		addBar(2, size - 4, center, center, 45)
		addBar(2, size - 4, center, center, -45)
	elseif iconName == "combat" then
		addRing(size - 6, size - 6, center, center, 1.4)
		addBar(2, size - 10, center, center, 0)
		addBar(size - 10, 2, center, center, 0)
		addBar(4, 4, center, center, 0)
	elseif iconName == "defense" then
		addRing(size - 8, size - 6, center, center - 1, 1.4)
		addBar(2, size - 10, center, center, 0)
	elseif iconName == "visuals" then
		addRing(size - 4, size - 8, center, center, 1.4)
		addBar(4, 4, center, center, 0)
	elseif iconName == "movement" then
		addBar(size - 8, 2, center - 1, center, 0)
		addBar(2, 7, center + 4, center - 3, 45)
		addBar(2, 7, center + 4, center + 3, -45)
	else
		local diamond = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center, center),
			Size = UDim2.fromOffset(size - 8, size - 8),
			BorderSizePixel = 0,
			Rotation = 45,
			ZIndex = zIndex,
			Parent = container,
		})
		addCorner(diamond, 2)
		addIconPart(parts, "fill", diamond)
	end

	local icon = {
		frame = container,
		parts = parts,
	}

	function icon:setColor(hex, animate)
		for _, part in ipairs(self.parts) do
			if part.kind == "fill" then
				if animate then
					animateFill(part.object, hex, FAST_TWEEN)
				else
					applyFill(part.object, hex)
				end
			else
				if animate then
					animateStroke(part.object, hex, FAST_TWEEN)
				else
					applyStroke(part.object, hex)
				end
			end
		end
	end

	return icon
end

local VALID_CONTROL_KINDS = {
	toggle = true,
	checkbox = true,
	slider = true,
	input = true,
	colorpicker = true,
	paragraph = true,
	label = true,
}

local function normalizeControl(control)
	if type(control) ~= "table" then
		warn("[Sigmatik] control must be a table")
		return { Type = "label", Name = "?", Content = "invalid", CurrentValue = nil }
	end
	local kind = string.lower(tostring(control.Type or "toggle"))
	local normalized = shallowCopy(control)
	normalized.Name = control.Name or "Option"
	normalized.Description = control.Description
	normalized.Callback = control.Callback

	if not VALID_CONTROL_KINDS[kind] then
		normalized.Type = "label"
		normalized.Content = "Unknown control type: " .. tostring(control.Type)
		return normalized
	end
	normalized.Type = kind

	if kind == "slider" then
		normalized.Min = type(control.Min) == "number" and control.Min or 0
		normalized.Max = type(control.Max) == "number" and control.Max or 100
		if normalized.Min ~= normalized.Min then normalized.Min = 0 end
		if normalized.Max ~= normalized.Max then normalized.Max = 100 end
		normalized.Increment = type(control.Increment) == "number" and control.Increment or 1
		if normalized.Increment ~= normalized.Increment then normalized.Increment = 1 end
		if normalized.Increment <= 0 then
			normalized.Increment = 1
		end
		if normalized.Max < normalized.Min then
			normalized.Max = normalized.Min
		end
		local rawValue = control.Value or control.CurrentValue or normalized.Min
		if type(rawValue) ~= "number" then rawValue = normalized.Min end
		normalized.Value = clampRound(rawValue, normalized.Min, normalized.Max, normalized.Increment)
		normalized.CurrentValue = normalized.Value
	elseif kind == "input" then
		normalized.Placeholder = control.Placeholder
		normalized.Text = control.Text and true or false  -- text mode (string) vs number
		if normalized.Text then
			normalized.Value = tostring(control.Value or control.CurrentValue or "")
		else
			normalized.Min = type(control.Min) == "number" and control.Min or nil
			normalized.Max = type(control.Max) == "number" and control.Max or nil
			local rawValue = control.Value or control.CurrentValue or 0
			if type(rawValue) ~= "number" then rawValue = parseNumberInput(rawValue) or 0 end
			if normalized.Min then rawValue = math.max(normalized.Min, rawValue) end
			if normalized.Max then rawValue = math.min(normalized.Max, rawValue) end
			normalized.Value = rawValue
		end
		normalized.CurrentValue = normalized.Value
	elseif kind == "colorpicker" then
		normalized.Palette = arrayCopy(control.Palette or DEFAULT_PALETTE)
		local rawColor = control.Value or control.CurrentValue or normalized.Palette[1]
		if type(rawColor) ~= "string" then rawColor = normalized.Palette[1] or "#ffffffff" end
		normalized.Value = tostring(rawColor)
	elseif kind == "paragraph" then
		normalized.Content = control.Content or control.Text or ""
	elseif kind == "label" then
		normalized.Content = control.Content or control.Text or normalized.Name
	else
		normalized.Value = not not (control.Value or control.CurrentValue)
	end

	return normalized
end

local function normalizeSection(section)
	local normalized = {
		Name = section.Name or "General",
		Controls = {},
	}

	for _, control in ipairs(section.Controls or {}) do
		table.insert(normalized.Controls, normalizeControl(control))
	end

	return normalized
end

local function normalizeModule(module)
	local normalized = {
		Name = module.Name or "Module",
		Enabled = not not module.Enabled,
		Callback = module.Callback,
		Sections = {},
		SectionLookup = {},
	}

	for _, section in ipairs(module.Sections or {}) do
		local normalizedSection = normalizeSection(section)
		if normalized.SectionLookup[normalizedSection.Name] then
			warn("[Sigmatik] duplicate section name: " .. tostring(normalizedSection.Name))
		end
		table.insert(normalized.Sections, normalizedSection)
		normalized.SectionLookup[normalizedSection.Name] = normalizedSection
	end

	return normalized
end

local function normalizeTab(tab)
	local normalized = {
		Name = tab.Name or "Tab",
		Icon = tab.Icon or "misc",
		Modules = {},
		ModuleLookup = {},
	}

	for _, module in ipairs(tab.Modules or {}) do
		local normalizedModule = normalizeModule(module)
		if normalized.ModuleLookup[normalizedModule.Name] then
			warn("[Sigmatik] duplicate module name: " .. tostring(normalizedModule.Name))
		end
		table.insert(normalized.Modules, normalizedModule)
		normalized.ModuleLookup[normalizedModule.Name] = normalizedModule
	end

	return normalized
end

function Controller:_setConfigLabel(text)
	local label = self.ui.configLabel
	self.configLabelSerial = (self.configLabelSerial or 0) + 1
	local serial = self.configLabelSerial
	if self._configLabelTween then
		pcall(function() self._configLabelTween:Cancel() end)
	end
	self._configLabelTween = tween(label, FADE_TWEEN, { TextTransparency = 1 })
	task.delay(0.06, function()
		if self.closing then return end
		if not label.Parent or serial ~= self.configLabelSerial then
			return
		end

		label.Text = text
		if self._configLabelTween then
			pcall(function() self._configLabelTween:Cancel() end)
		end
		self._configLabelTween = tween(label, FADE_TWEEN, { TextTransparency = getFillTransparency("#ffffff80") })
	end)
	task.delay(1.2, function()
		if self.closing then return end
		if not label.Parent or serial ~= self.configLabelSerial then
			return
		end

		if self._configLabelTween then
			pcall(function() self._configLabelTween:Cancel() end)
		end
		self._configLabelTween = tween(label, FADE_TWEEN, { TextTransparency = 1 })
		task.delay(0.06, function()
			if self.closing then return end
			if label.Parent and serial == self.configLabelSerial then
				label.Text = self.config.ConfigName
				if self._configLabelTween then
					pcall(function() self._configLabelTween:Cancel() end)
				end
				self._configLabelTween = tween(label, FADE_TWEEN, { TextTransparency = getFillTransparency("#ffffff80") })
			end
		end)
	end)
end

function Controller:_getTabIcon(iconName)
	return iconName or "misc"
end

function Controller:_countEnabledModules()
	local count = 0
	for _, tab in ipairs(self.tabs) do
		for _, module in ipairs(tab.Modules) do
			if module.Enabled then
				count = count + 1
			end
		end
	end
	return count
end

function Controller:_refreshHeaderSummary()
	local count = self:_countEnabledModules()
	self.ui.activeLabel.Text = string.format("%d Active", count)

	animateText(self.ui.activeLabel, count > 0 and "#22c55e" or "#ffffff80", FAST_TWEEN)
	animateFill(self.ui.statusDot, count > 0 and "#22c55e" or "#ffffff30", FAST_TWEEN)
	animateStroke(self.ui.statusStroke, count > 0 and "#ffffff18" or "#ffffff12", FAST_TWEEN)

	if count ~= self.lastActiveCount then
		self.lastActiveCount = count
		pulse(self.ui.statusScale, 1.03)
	end
end

function Controller:_updateSearchPlaceholder(instant)
	local placeholder = self.ui.searchPlaceholder
	local empty = self.ui.searchInput.Text == ""
	placeholder.Visible = true
	self.placeholderSerial = (self.placeholderSerial or 0) + 1
	local serial = self.placeholderSerial

	if empty then
		if instant then
			placeholder.TextTransparency = getFillTransparency(self.searchFocused and self.theme.AccentSoft or "#ffffff80")
		else
			animateText(placeholder, self.searchFocused and self.theme.AccentSoft or "#ffffff80", FADE_TWEEN)
		end
		return
	end

	if instant then
		placeholder.Visible = false
		placeholder.TextTransparency = 1
		return
	end

	tween(placeholder, FADE_TWEEN, { TextTransparency = 1 })
	task.delay(0.14, function()
		if self.closing then return end
		if placeholder.Parent and self.ui.searchInput.Text ~= "" and serial == self.placeholderSerial then
			placeholder.Visible = false
		end
	end)
end

function Controller:_updateSearchVisual(focused)
	self.searchFocused = focused
	if focused then
		animateFill(self.ui.searchFrame, self.theme.Accent .. "18", FAST_TWEEN)
		animateStroke(self.ui.searchStroke, self.theme.Accent, FAST_TWEEN)
		self.ui.searchIcon:setColor(self.theme.Accent, true)
		animateScale(self.ui.searchScale, 1.015, FAST_TWEEN)
	else
		animateFill(self.ui.searchFrame, "#00000040", FAST_TWEEN)
		animateStroke(self.ui.searchStroke, "#ffffff1a", FAST_TWEEN)
		self.ui.searchIcon:setColor(self.ui.searchInput.Text ~= "" and self.theme.AccentSoft or "#ffffffb3", true)
		animateScale(self.ui.searchScale, 1, SOFT_TWEEN)
	end

	self:_updateSearchPlaceholder(false)
end

function Controller:_setSelectedTab(tab)
	self.selectedTab = tab
	self.selectedModule = tab and tab.Modules[1] or nil
	if self.ui and self.ui.searchInput then
		self.ui.searchInput.Text = ""
	end
	if self.settingsVisible then
		self.settingsVisible = false
		self:_updateModulePanelLayout()
	end
	self:_refreshCategoryTabs()
	self:_renderModuleRows(true)
	self:_renderSettingsPanel()
end

function Controller:_setSelectedModule(module, openSettings)
	if self.settingsPanelConnections then
		for _, conn in ipairs(self.settingsPanelConnections) do
			pcall(function() conn:Disconnect() end)
		end
		self.settingsPanelConnections = {}
	end
	self.selectedModule = module
	if openSettings ~= nil then
		self.settingsVisible = openSettings
	end

	self:_renderModuleRows(false)
	self:_renderSettingsPanel()
end

function Controller:_toggleSettings(force)
	if not self.selectedModule then
		return
	end

	if force == nil then
		self.settingsVisible = not self.settingsVisible
	else
		self.settingsVisible = force
	end

	self:_updateModulePanelLayout()
	self:_renderModuleRows(false)
	self:_renderSettingsPanel()
	self:_setConfigLabel(self.settingsVisible and "Settings Open" or "Settings Closed")
end

function Controller:_updateModulePanelLayout()
	local moduleWidth = self.settingsVisible and 360 or 708
	animateSize(self.ui.searchFrame, UDim2.fromOffset(moduleWidth, 40), PANEL_TWEEN)
	animateSize(self.ui.modulePanel, UDim2.fromOffset(moduleWidth, self.config.WindowHeight - 140), PANEL_TWEEN)

	if self.settingsVisible and self.selectedModule then
		self.ui.settingsPanel.Visible = true
		animatePosition(self.ui.settingsPanel, self.ui.settingsPanelShownPosition, PANEL_TWEEN)
		animateScale(self.ui.settingsPanelScale, 1, PANEL_TWEEN)
		animateFill(self.ui.settingsPanel, "#ffffff07", PANEL_TWEEN)
		animateStroke(self.ui.settingsPanelStroke, "#ffffff16", PANEL_TWEEN)
	else
		animatePosition(self.ui.settingsPanel, self.ui.settingsPanelHiddenPosition, PANEL_TWEEN)
		animateScale(self.ui.settingsPanelScale, 0.96, PANEL_TWEEN)
		animateFill(self.ui.settingsPanel, "#ffffff03", PANEL_TWEEN)
		animateStroke(self.ui.settingsPanelStroke, "#ffffff08", PANEL_TWEEN)
		task.delay(0.22, function()
			if self.ui.settingsPanel.Parent and not self.settingsVisible then
				self.ui.settingsPanel.Visible = false
			end
		end)
	end
end

function Controller:_setModuleEnabled(module, enabled, silent)
	module.Enabled = not not enabled
	if not silent then
		fireCallback(module.Callback, module.Enabled)
	end

	self:_refreshHeaderSummary()
	self:_renderModuleRows(false)
	if self.selectedModule == module then
		self:_renderSettingsPanel()
	end
end

function Controller:_setControlValue(control, value, silent)
	if control.Type == "label" or control.Type == "paragraph" then
		return
	end
	if control.Type == "slider" then
		control.Value = clampRound(value, control.Min, control.Max, control.Increment)
	elseif control.Type == "input" then
		if control.Text then
			control.Value = tostring(value or "")
		else
			local n = parseNumberInput(value)
			if n == nil then n = control.Value or control.Min or 0 end
			if control.Min then n = math.max(control.Min, n) end
			if control.Max then n = math.min(control.Max, n) end
			control.Value = n
		end
	elseif control.Type == "colorpicker" then
		control.Value = tostring(value)
	else
		control.Value = not not value
	end

	control.CurrentValue = control.Value

	if control._refresh then
		control._refresh(true)
	end

	if not silent then
		fireCallback(control.Callback, control.Value)
	end
end

function Controller:_createHeaderIconButton(parent, name, fillHex, iconName, iconHex)
	local frame = create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(32, 32),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = parent,
	})
	applyFill(frame, fillHex)
	addCorner(frame, 6)
	addGradient(frame, 90, { "#ffffff10", "#0f172a1c" })
	local stroke = addStroke(frame, 1, "#ffffff10")
	local scale = addScale(frame, 1)

	local icon = createIcon(frame, self:_getTabIcon(iconName), 16, 6)
	icon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.frame.Position = UDim2.fromScale(0.5, 0.5)
	icon:setColor(iconHex, false)

	local button = create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
		Parent = frame,
	})

	local control = {
		frame = frame,
		stroke = stroke,
		icon = icon,
		scale = scale,
		button = button,
		active = false,
		defaultFill = fillHex,
		defaultIcon = iconHex,
		name = name,
		window = self,
	}

	function control:applyVisual(mode)
		local fill = self.defaultFill
		local strokeHex = "#ffffff10"
		local iconHexValue = self.defaultIcon

		if self.active and self.name ~= "CloseButton" then
			fill = self.window.theme.Accent .. "14"
			strokeHex = self.window.theme.Accent .. "40"
			iconHexValue = self.window.theme.AccentSoft
		end

		if mode == "hover" then
			fill = self.name == "CloseButton" and "#ff444426" or (self.active and self.window.theme.Accent .. "1f" or "#ffffff14")
			strokeHex = self.active and self.window.theme.Accent .. "52" or "#ffffff18"
			iconHexValue = self.name == "CloseButton" and "#ff6666" or (self.active and WHITE or "#ffffffcc")
		elseif mode == "pressed" then
			fill = self.name == "CloseButton" and "#ff44441a" or (self.active and self.window.theme.Accent .. "18" or "#ffffff08")
			strokeHex = self.active and self.window.theme.Accent .. "40" or "#ffffff10"
			iconHexValue = self.name == "CloseButton" and "#ff6666" or (self.active and self.window.theme.AccentSoft or "#ffffff99")
		end

		animateFill(self.frame, fill, FAST_TWEEN)
		animateStroke(self.stroke, strokeHex, FAST_TWEEN)
		self.icon:setColor(iconHexValue, true)
		animateScale(self.scale, mode == "pressed" and 0.94 or (mode == "hover" and 1.06 or (self.active and 1.03 or 1)), FAST_TWEEN)
	end

	local pressed = false
	local hovering = false

	table.insert(self.connections, button.MouseEnter:Connect(function()
		hovering = true
		control:applyVisual("hover")
	end))
	table.insert(self.connections, button.MouseLeave:Connect(function()
		hovering = false
		pressed = false
		control:applyVisual("default")
	end))
	table.insert(self.connections, button.MouseButton1Down:Connect(function()
		pressed = true
		control:applyVisual("pressed")
	end))
	table.insert(self.connections, button.MouseButton1Up:Connect(function()
		pressed = false
		if button.Parent then
			control:applyVisual(hovering and "hover" or "default")
		end
	end))
	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) and pressed then
			pressed = false
			if button.Parent then
				control:applyVisual(hovering and "hover" or "default")
			end
		end
	end))

	control:applyVisual("default")
	return control
end

function Controller:_makeSwitch(parent, position, zIndex)
	local accent = self.theme.Accent

	local frame = create("Frame", {
		Name = "Switch",
		Position = position,
		Size = UDim2.fromOffset(42, 22),
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = parent,
	})
	applyFill(frame, "#ffffff1a")
	addCorner(frame, 999)
	addGradient(frame, 0, { "#ffffff14", "#0f172a30" })
	local stroke = addStroke(frame, 1, "#ffffff1f")
	stroke.Transparency = 0.88

	local glow = create("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = frame,
	})
	applyFill(glow, accent .. "00")
	addCorner(glow, 999)

	local thumb = create("Frame", {
		Name = "Thumb",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(18, 18),
		BorderSizePixel = 0,
		ZIndex = zIndex + 1,
		Parent = frame,
	})
	applyFill(thumb, WHITE)
	addCorner(thumb, 999)
	addGradient(thumb, 90, { WHITE, "#dbeafeff" })
	local thumbScale = addScale(thumb, 1)

	local button = create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex + 2,
		Parent = frame,
	})

	local control = {
		frame = frame,
		stroke = stroke,
		glow = glow,
		thumb = thumb,
		thumbScale = thumbScale,
		button = button,
		serial = 0,
	}

	function control:setState(enabled, instant)
		self.serial = self.serial + 1
		local serial = self.serial
		local frameColor = enabled and accent or "#ffffff1a"
		local strokeColor = enabled and accent .. "80" or "#ffffff1f"
		local thumbPosition = enabled and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2)
		local glowColor = enabled and accent .. "3a" or accent .. "00"

		if instant then
			applyFill(self.frame, frameColor)
			applyStroke(self.stroke, strokeColor)
			applyFill(self.glow, glowColor)
			self.thumb.Position = thumbPosition
			return
		end

		animateFill(self.frame, frameColor, SOFT_TWEEN)
		animateStroke(self.stroke, strokeColor, SOFT_TWEEN)
		animateFill(self.glow, glowColor, SOFT_TWEEN)
		animatePosition(self.thumb, thumbPosition, SOFT_TWEEN)
		animateScale(self.thumbScale, 0.92, FAST_TWEEN)
		task.delay(0.08, function()
			if self.thumbScale.Parent and self.serial == serial then
				animateScale(self.thumbScale, 1, POP_TWEEN)
			end
		end)
	end

	return control
end

function Controller:_makeCheckbox(parent, position, zIndex)
	local accent = self.theme.Accent

	local frame = create("Frame", {
		Name = "Checkbox",
		Position = position,
		Size = UDim2.fromOffset(16, 16),
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = parent,
	})
	applyFill(frame, "#ffffff1a")
	addCorner(frame, 4)
	local stroke = addStroke(frame, 1, "#ffffff2a")

	local check = create("TextLabel", {
		Name = "Check",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		Text = CHECK_ICON,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = zIndex + 1,
		Visible = false,
		Parent = frame,
	})
	applyTextColor(check, WHITE)
	check.TextTransparency = 1
	check.Rotation = -20
	local checkScale = addScale(check, 0.65)

	local button = create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex + 2,
		Parent = frame,
	})

	local control = {
		frame = frame,
		stroke = stroke,
		check = check,
		checkScale = checkScale,
		button = button,
		serial = 0,
	}

	function control:setState(enabled, instant)
		self.serial = self.serial + 1
		local serial = self.serial

		if instant then
			if enabled then
				applyFill(self.frame, accent)
				applyStroke(self.stroke, accent .. "80")
				self.check.Visible = true
				self.check.TextTransparency = 0
				self.check.Rotation = 0
				self.checkScale.Scale = 1
			else
				applyFill(self.frame, "#ffffff1a")
				applyStroke(self.stroke, "#ffffff2a")
				self.check.Visible = false
				self.check.Rotation = -20
				self.checkScale.Scale = 0.65
				self.check.TextTransparency = 1
			end
			return
		end

		if enabled then
			animateFill(self.frame, accent, SOFT_TWEEN)
			animateStroke(self.stroke, accent .. "80", SOFT_TWEEN)
			self.check.Visible = true
			animateText(self.check, WHITE, FAST_TWEEN)
			animateScale(self.checkScale, 1, POP_TWEEN)
			tween(self.check, FAST_TWEEN, { Rotation = 0 })
		else
			animateFill(self.frame, "#ffffff1a", SOFT_TWEEN)
			animateStroke(self.stroke, "#ffffff2a", SOFT_TWEEN)
			animateScale(self.checkScale, 0.7, FAST_TWEEN)
			tween(self.check, FAST_TWEEN, { Rotation = 16, TextTransparency = 1 })
			task.delay(0.12, function()
				if self.check.Parent and self.serial == serial then
					self.check.Visible = false
					self.check.Rotation = -20
					self.checkScale.Scale = 0.65
				end
			end)
		end
	end

	return control
end

function Controller:_createCategoryTab(tab)
	local frame = create("Frame", {
		Name = tab.Name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(192, 34),
		ZIndex = 4,
		Parent = self.ui.categoryContainer,
	})
	applyFill(frame, "#ffffff0d")
	addCorner(frame, 10)
	addGradient(frame, 90, { "#ffffff12", "#0f172a1e" })
	local stroke = addStroke(frame, 1, "#ffffff14")
	local scale = addScale(frame, 1)

	local icon = createIcon(frame, self:_getTabIcon(tab.Icon), 16, 5)
	icon.frame.Position = UDim2.fromOffset(17, 9)
	icon:setColor("#ffffffb3", false)

	local label = create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(46, 0),
		Size = UDim2.fromOffset(124, 34),
		Font = fontForWeight(600),
		Text = tab.Name,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
		Parent = frame,
	})
	applyTextColor(label, WHITE)

	local button = create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = frame,
	})

	local entry = {
		tab = tab,
		frame = frame,
		stroke = stroke,
		scale = scale,
		icon = icon,
		label = label,
		button = button,
		hovered = false,
	}

	table.insert(self.connections, button.MouseEnter:Connect(function()
		entry.hovered = true
		animateScale(scale, 1.015, FAST_TWEEN)
		if self.selectedTab ~= tab then
			animateFill(frame, "#ffffff14", FAST_TWEEN)
			animateStroke(stroke, "#ffffff18", FAST_TWEEN)
			icon:setColor(WHITE, true)
		end
	end))

	table.insert(self.connections, button.MouseLeave:Connect(function()
		entry.hovered = false
		animateScale(scale, self.selectedTab == tab and 1.02 or 1, SOFT_TWEEN)
		if self.selectedTab ~= tab then
			animateFill(frame, "#ffffff0d", SOFT_TWEEN)
			animateStroke(stroke, "#ffffff14", SOFT_TWEEN)
			icon:setColor("#ffffffb3", true)
		end
	end))

	table.insert(self.connections, button.MouseButton1Click:Connect(function()
		self:_setSelectedTab(tab)
	end))

	table.insert(self.ui.categoryEntries, entry)
end

function Controller:_refreshCategoryTabs()
	for _, entry in ipairs(self.ui.categoryEntries) do
		if entry.tab == self.selectedTab then
			animateFill(entry.frame, self.theme.Accent .. "14", SOFT_TWEEN)
			animateStroke(entry.stroke, self.theme.Accent .. "40", SOFT_TWEEN)
			entry.icon:setColor(self.theme.Accent, true)
			animateText(entry.label, self.theme.AccentSoft, SOFT_TWEEN)
			animateScale(entry.scale, 1.02, SOFT_TWEEN)
		else
			animateFill(entry.frame, entry.hovered and "#ffffff14" or "#ffffff0d", SOFT_TWEEN)
			animateStroke(entry.stroke, entry.hovered and "#ffffff18" or "#ffffff14", SOFT_TWEEN)
			entry.icon:setColor(entry.hovered and WHITE or "#ffffffb3", true)
			animateText(entry.label, WHITE, SOFT_TWEEN)
			animateScale(entry.scale, entry.hovered and 1.015 or 1, SOFT_TWEEN)
		end
	end
end

function Controller:_createModuleRow(module, order, animateEntrance)
	local rowWidth = self.settingsVisible and 360 or 708
	local selected = self.selectedModule == module
	local settingsActive = self.settingsVisible and selected

	local row = create("Frame", {
		Name = module.Name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(rowWidth, 46),
		ZIndex = 4,
		Parent = self.ui.moduleContainer,
	})
	applyFill(row, "#ffffff08")
	addCorner(row, 10)
	addGradient(row, 90, { "#ffffff10", "#0f172a22" })
	local stroke = addStroke(row, 1, "#ffffff12")
	local rowScale = addScale(row, 0.97)

	local settingsFrame = create("Frame", {
		Name = "SettingsToggle",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(26, 26),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = row,
	})
	applyFill(settingsFrame, "#ffffff0d")
	addCorner(settingsFrame, 8)
	addGradient(settingsFrame, 90, { "#ffffff12", "#0f172a1e" })
	local settingsStroke = addStroke(settingsFrame, 1, "#ffffff16")
	local settingsScale = addScale(settingsFrame, 1)

	local settingsIcon = createIcon(settingsFrame, "settings", 14, 7)
	settingsIcon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	settingsIcon.frame.Position = UDim2.fromScale(0.5, 0.5)
	settingsIcon:setColor("#ffffffb3", false)

	local settingsButton = create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 8,
		Parent = settingsFrame,
	})

	local label = create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.fromOffset(rowWidth - 146, 46),
		Font = fontForWeight(600),
		Text = module.Name,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 5,
		Parent = row,
	})
	applyTextColor(label, WHITE)

	local toggle = self:_makeSwitch(row, UDim2.fromOffset(rowWidth - 52, 12), 8)
	toggle:setState(module.Enabled, true)

	local rowButton = create("TextButton", {
		Name = "RowButton",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.fromOffset(rowWidth - 102, 46),
		ZIndex = 5,
		Parent = row,
	})

	local hovered = false
	local settingsHovered = false

	local function refreshVisual(animate)
		selected = self.selectedModule == module
		settingsActive = self.settingsVisible and selected
		local idleIcon = module.Enabled and self.theme.AccentSoft or (selected and WHITE or "#ffffffb3")
		local idleFill = module.Enabled and self.theme.Accent .. "10" or "#ffffff0d"
		local idleStroke = module.Enabled and self.theme.Accent .. "24" or "#ffffff16"
		local setRowFill = animate and animateFill or applyFill
		local setRowStroke = animate and animateStroke or applyStroke
		local setRowText = animate and animateText or applyTextColor
		local setRowScale = animate and animateScale or function(scaleObject, value)
			scaleObject.Scale = value
		end

		if settingsActive then
			if animate then
				animateFill(settingsFrame, self.theme.Accent .. "1a", FAST_TWEEN)
				animateStroke(settingsStroke, self.theme.Accent .. "40", FAST_TWEEN)
				settingsIcon:setColor(self.theme.AccentSoft, true)
			else
				applyFill(settingsFrame, self.theme.Accent .. "1a")
				applyStroke(settingsStroke, self.theme.Accent .. "40")
				settingsIcon:setColor(self.theme.AccentSoft, false)
			end
			if animate then
				animateScale(settingsScale, 1.08, POP_TWEEN)
			else
				settingsScale.Scale = 1.08
			end
		elseif settingsHovered then
			if animate then
				animateFill(settingsFrame, "#ffffff14", FAST_TWEEN)
				animateStroke(settingsStroke, "#ffffff20", FAST_TWEEN)
				settingsIcon:setColor(WHITE, true)
			else
				applyFill(settingsFrame, "#ffffff14")
				applyStroke(settingsStroke, "#ffffff20")
				settingsIcon:setColor(WHITE, false)
			end
			if animate then
				animateScale(settingsScale, 1.06, FAST_TWEEN)
			else
				settingsScale.Scale = 1.06
			end
		else
			if animate then
				animateFill(settingsFrame, idleFill, SOFT_TWEEN)
				animateStroke(settingsStroke, idleStroke, SOFT_TWEEN)
				settingsIcon:setColor(idleIcon, true)
			else
				applyFill(settingsFrame, idleFill)
				applyStroke(settingsStroke, idleStroke)
				settingsIcon:setColor(idleIcon, false)
			end
			if animate then
				animateScale(settingsScale, 1, SOFT_TWEEN)
			else
				settingsScale.Scale = 1
			end
		end

		if settingsActive then
			setRowFill(row, self.theme.Accent .. "16", SOFT_TWEEN)
			setRowStroke(stroke, self.theme.Accent .. "48", SOFT_TWEEN)
			setRowText(label, WHITE, SOFT_TWEEN)
			setRowScale(rowScale, hovered and 1.015 or 1.01, SOFT_TWEEN)
		elseif module.Enabled then
			setRowFill(row, self.theme.Accent .. "14", SOFT_TWEEN)
			setRowStroke(stroke, self.theme.Accent .. "40", SOFT_TWEEN)
			setRowText(label, self.theme.AccentSoft, SOFT_TWEEN)
			setRowScale(rowScale, hovered and 1.012 or 1, SOFT_TWEEN)
		elseif selected then
			setRowFill(row, hovered and "#ffffff14" or "#ffffff10", SOFT_TWEEN)
			setRowStroke(stroke, hovered and "#ffffff22" or "#ffffff18", SOFT_TWEEN)
			setRowText(label, WHITE, SOFT_TWEEN)
			setRowScale(rowScale, hovered and 1.012 or 1.005, SOFT_TWEEN)
		elseif hovered then
			setRowFill(row, "#ffffff0d", SOFT_TWEEN)
			setRowStroke(stroke, "#ffffff16", SOFT_TWEEN)
			setRowText(label, WHITE, SOFT_TWEEN)
			setRowScale(rowScale, 1.012, FAST_TWEEN)
		else
			setRowFill(row, "#ffffff08", SOFT_TWEEN)
			setRowStroke(stroke, "#ffffff12", SOFT_TWEEN)
			setRowText(label, WHITE, SOFT_TWEEN)
			setRowScale(rowScale, 1, SOFT_TWEEN)
		end
	end

	row.BackgroundTransparency = 1
	stroke.Transparency = 1
	label.TextTransparency = 1
	settingsFrame.BackgroundTransparency = 1
	settingsStroke.Transparency = 1
	if animateEntrance then
		for _, part in ipairs(settingsIcon.parts) do
			if part.kind == "fill" then
				part.object.BackgroundTransparency = 1
			else
				part.object.Transparency = 1
			end
		end
		task.delay((order or 1) * 0.02, function()
			if row.Parent then
				refreshVisual(true)
			end
		end)
	else
		refreshVisual(false)
	end

	table.insert(self.moduleRowConnections, rowButton.MouseEnter:Connect(function()
		hovered = true
		refreshVisual(true)
	end))
	table.insert(self.moduleRowConnections, rowButton.MouseLeave:Connect(function()
		hovered = false
		refreshVisual(true)
	end))
	table.insert(self.moduleRowConnections, rowButton.MouseButton1Click:Connect(function()
		self.selectedModule = module
		self.settingsVisible = true
		self:_updateModulePanelLayout()
		self:_renderModuleRows(false)
		self:_renderSettingsPanel()
		if rowScale.Parent then pulse(rowScale, 1.02) end
	end))

	table.insert(self.moduleRowConnections, settingsButton.MouseEnter:Connect(function()
		settingsHovered = true
		refreshVisual(true)
	end))
	table.insert(self.moduleRowConnections, settingsButton.MouseLeave:Connect(function()
		settingsHovered = false
		refreshVisual(true)
	end))
	table.insert(self.moduleRowConnections, settingsButton.MouseButton1Click:Connect(function()
		if self.selectedModule == module and self.settingsVisible then
			self.settingsVisible = false
		else
			self.selectedModule = module
			self.settingsVisible = true
		end

		self:_updateModulePanelLayout()
		self:_renderModuleRows(false)
		self:_renderSettingsPanel()
		if settingsScale.Parent then pulse(settingsScale, 1.12) end
	end))

	table.insert(self.moduleRowConnections, toggle.button.MouseButton1Click:Connect(function()
		self.selectedModule = module
		self:_setModuleEnabled(module, not module.Enabled, false)
		self:_setConfigLabel(module.Enabled and "Module Enabled" or "Module Disabled")
	end))
end

function Controller:_renderModuleRows(animateEntrance)
	if self.moduleRowConnections then
		for _, conn in ipairs(self.moduleRowConnections) do
			pcall(function() conn:Disconnect() end)
		end
		self.moduleRowConnections = {}
	else
		self.moduleRowConnections = {}
	end

	clearChildren(self.ui.moduleContainer)

	if not self.selectedTab then
		return
	end

	local query = lowerLocale(self.ui.searchInput.Text)
	local visibleIndex = 0
	local visibleModules = {}

	for _, module in ipairs(self.selectedTab.Modules) do
		if query == "" or string.find(lowerLocale(module.Name), query, 1, true) then
			visibleIndex = visibleIndex + 1
			table.insert(visibleModules, module)
			self:_createModuleRow(module, visibleIndex, animateEntrance)
		end
	end

	if self.selectedModule then
		local stillVisible = false
		for _, m in ipairs(visibleModules) do
			if m == self.selectedModule then
				stillVisible = true
				break
			end
		end
		if not stillVisible then
			self.selectedModule = visibleModules[1] or nil
		end
	end

	if not visibleModules[1] then
		self.selectedModule = nil
		if self.settingsVisible then
			self.settingsVisible = false
			if self.ui and self.ui.settingsPanel then
				self:_updateModulePanelLayout()
			end
		end
	end
end

function Controller:_createSectionHeader(parent, name)
	local section = create("Frame", {
		Name = name .. "Section",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 3,
		Parent = parent,
	})
	local layout = addListLayout(section, Enum.FillDirection.Vertical, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local label = create("TextLabel", {
		Name = "SectionTitle",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(308, 16),
		Font = fontForWeight(700),
		Text = name,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 4,
		Parent = section,
	})
	applyTextColor(label, "#ffffffcc")

	return section
end

function Controller:_createEnabledRow(parent, module)
	local row = create("Frame", {
		Name = "EnabledRow",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(308, 34),
		ZIndex = 4,
		Parent = parent,
	})
	applyFill(row, "#ffffff08")
	addCorner(row, 10)
	addGradient(row, 90, { "#ffffff10", "#0f172a20" })
	addStroke(row, 1, "#ffffff10")

	local label = create("TextLabel", {
		Name = "EnabledLabel",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.fromOffset(100, 34),
		Font = fontForWeight(600),
		Text = "Enabled",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = row,
	})
	applyTextColor(label, "#ffffffcc")

	local switch = self:_makeSwitch(row, UDim2.fromOffset(256, 6), 5)
	switch:setState(module.Enabled, true)
	table.insert(self.settingsPanelConnections, switch.button.MouseButton1Click:Connect(function()
		self:_setModuleEnabled(module, not module.Enabled, false)
	end))
end

function Controller:_createToggleRow(parent, control)
	local row = create("Frame", {
		Name = control.Name .. "Row",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(308, 34),
		ZIndex = 4,
		Parent = parent,
	})
	applyFill(row, "#ffffff08")
	addCorner(row, 10)
	addGradient(row, 90, { "#ffffff10", "#0f172a20" })
	addStroke(row, 1, "#ffffff10")

	local label = create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.fromOffset(190, 34),
		Font = fontForWeight(500),
		Text = control.Name,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = row,
	})
	applyTextColor(label, "#ffffffcc")

	local switch = self:_makeSwitch(row, UDim2.fromOffset(256, 6), 5)
	switch:setState(control.Value, true)

	control._refresh = function(instant)
		switch:setState(control.Value, instant)
	end

	table.insert(self.settingsPanelConnections, switch.button.MouseButton1Click:Connect(function()
		self:_setControlValue(control, not control.Value, false)
	end))
end

function Controller:_createCheckboxRow(parent, control)
	local row = create("Frame", {
		Name = control.Name .. "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(308, 20),
		ZIndex = 4,
		Parent = parent,
	})

	local label = create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(140, 20),
		Font = fontForWeight(500),
		Text = control.Name,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = row,
	})
	applyTextColor(label, "#ffffff99")

	local checkbox = self:_makeCheckbox(row, UDim2.fromOffset(292, 2), 5)
	checkbox:setState(control.Value, true)

	control._refresh = function(instant)
		checkbox:setState(control.Value, instant)
	end

	table.insert(self.settingsPanelConnections, checkbox.button.MouseButton1Click:Connect(function()
		self:_setControlValue(control, not control.Value, false)
	end))
end

function Controller:_createSliderCard(parent, control)
	local card = create("Frame", {
		Name = control.Name .. "Card",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(308, 54),
		ZIndex = 4,
		Parent = parent,
	})
	applyFill(card, "#ffffff08")
	addCorner(card, 10)
	addGradient(card, 90, { "#ffffff10", "#0f172a20" })
	addStroke(card, 1, "#ffffff10")
	local accentStroke = addStroke(card, 1, self.theme.Accent .. "10")

	local nameLabel = create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(150, 14),
		Font = fontForWeight(600),
		Text = control.Name,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = card,
	})
	applyTextColor(nameLabel, "#ffffffcc")

	local valueLabel = create("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(218, 10),
		Size = UDim2.fromOffset(80, 14),
		Font = fontForWeight(600),
		Text = tostring(control.Value),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = card,
	})
	applyTextColor(valueLabel, self.theme.Accent)

	local track = create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(10, 36),
		Size = UDim2.fromOffset(288, 8),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = card,
	})
	applyFill(track, "#11182780")
	addCorner(track, 999)
	addGradient(track, 0, { "#ffffff1a", "#0f172a80" })
	local trackScale = addScale(track, 1)

	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = track,
	})
	applyFill(fill, self.theme.Accent)
	addCorner(fill, 999)
	local fillGradient = addGradient(fill, 0, { self.theme.Accent, "#dbeafeff" })

	local knobGlow = create("Frame", {
		Name = "KnobGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = track,
	})
	applyFill(knobGlow, self.theme.Accent .. "38")
	addCorner(knobGlow, 999)
	local knobGlowScale = addScale(knobGlow, 1)

	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = track,
	})
	applyFill(knob, WHITE)
	addCorner(knob, 999)
	addGradient(knob, 90, { WHITE, "#dbeafeff" })
	local knobScale = addScale(knob, 1)

	local hitbox = create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(0, -2),
		Size = UDim2.new(1, 0, 1, 12),
		ZIndex = 8,
		Parent = track,
	})

	local hovered = false

	local function refresh(instant)
		local progress = math.clamp((control.Value - control.Min) / math.max(control.Max - control.Min, 0.001), 0, 1)
		local accentColor = select(1, parseHex(self.theme.Accent))
		local lightAccent = mixColors(accentColor, Color3.new(1, 1, 1), 0.42)
		updateGradient(fillGradient, self.theme.Accent, colorToHex(lightAccent))
		if type(control.Format) == "function" then
			local ok, formatted = pcall(control.Format, control.Value)
			valueLabel.Text = ok and tostring(formatted) or formatSliderValue(control.Value, control.Increment)
		else
			valueLabel.Text = formatSliderValue(control.Value, control.Increment)
		end

		if instant then
			fill.Size = UDim2.fromScale(progress, 1)
			knob.Position = UDim2.new(progress, 0, 0.5, 0)
			knobGlow.Position = UDim2.new(progress, 0, 0.5, 0)
			applyFill(knobGlow, self.theme.Accent .. "38")
			applyStroke(accentStroke, self.theme.Accent .. "20")
			applyTextColor(valueLabel, self.theme.Accent)
			return
		end

		animateSize(fill, UDim2.fromScale(progress, 1), FAST_TWEEN)
		animatePosition(knob, UDim2.new(progress, 0, 0.5, 0), FAST_TWEEN)
		animatePosition(knobGlow, UDim2.new(progress, 0, 0.5, 0), FAST_TWEEN)
		animateFill(knobGlow, self.theme.Accent .. "38", FAST_TWEEN)
		animateStroke(accentStroke, self.theme.Accent .. "20", FAST_TWEEN)
		animateText(valueLabel, self.theme.Accent, FAST_TWEEN)
	end

	control._refresh = refresh
	refresh(true)

	local function updateFromPointer(pointerX, instant)
		local relative = math.clamp((pointerX - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local nextValue = control.Min + ((control.Max - control.Min) * relative)
		control.Value = clampRound(nextValue, control.Min, control.Max, control.Increment)
		control.CurrentValue = control.Value
		refresh(instant)
	end

	local resetScales = function()
		if trackScale.Parent then animateScale(trackScale, hovered and 1.02 or 1, SOFT_TWEEN) end
		if knobScale.Parent then animateScale(knobScale, hovered and 1.08 or 1, SOFT_TWEEN) end
		if knobGlowScale.Parent then animateScale(knobGlowScale, hovered and 1.12 or 1, SOFT_TWEEN) end
	end

	table.insert(self.settingsPanelConnections, hitbox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.draggingSlider = {
				update = function(pointerX)
					updateFromPointer(pointerX, true)
				end,
				finish = function()
					if track.Parent then refresh(false) end
					fireCallback(control.Callback, control.Value)
				end,
				cancel = function()
					resetScales()
				end,
			}
			animateScale(trackScale, 1.03, FAST_TWEEN)
			animateScale(knobScale, 1.12, FAST_TWEEN)
			animateScale(knobGlowScale, 1.2, FAST_TWEEN)
			updateFromPointer(input.Position.X, true)
		end
	end))

	table.insert(self.settingsPanelConnections, hitbox.MouseEnter:Connect(function()
		hovered = true
		animateScale(trackScale, self.draggingSlider and 1.03 or 1.02, FAST_TWEEN)
		animateScale(knobScale, 1.08, FAST_TWEEN)
		animateScale(knobGlowScale, 1.14, FAST_TWEEN)
	end))

	table.insert(self.settingsPanelConnections, hitbox.MouseLeave:Connect(function()
		hovered = false
		if self.draggingSlider then
			return
		end

		animateScale(trackScale, 1, SOFT_TWEEN)
		animateScale(knobScale, 1, SOFT_TWEEN)
		animateScale(knobGlowScale, 1, SOFT_TWEEN)
	end))

	table.insert(self.sliderResetters, resetScales)
end

function Controller:_createInputCard(parent, control)
	local row = create("Frame", {
		Name = control.Name .. "Row",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(308, 34),
		ZIndex = 4,
		Parent = parent,
	})
	applyFill(row, "#ffffff08")
	addCorner(row, 10)
	addGradient(row, 90, { "#ffffff10", "#0f172a20" })
	addStroke(row, 1, "#ffffff10")

	local label = create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.fromOffset(170, 34),
		Font = fontForWeight(500),
		Text = control.Name,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = row,
	})
	applyTextColor(label, "#ffffffcc")

	local boxBG = create("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(108, 24),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = row,
	})
	applyFill(boxBG, "#11182780")
	addCorner(boxBG, 6)
	addStroke(boxBG, 1, "#ffffff14")

	local box = create("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		Font = fontForWeight(600),
		Text = "",
		PlaceholderText = control.Placeholder or "",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		ZIndex = 6,
		Parent = boxBG,
	})
	applyTextColor(box, self.theme.Accent)

	control._refresh = function()
		if type(control.Format) == "function" then
			local ok, formatted = pcall(control.Format, control.Value)
			box.Text = ok and tostring(formatted) or tostring(control.Value)
		else
			box.Text = tostring(control.Value)
		end
	end
	control._refresh(true)

	table.insert(self.settingsPanelConnections, box.FocusLost:Connect(function()
		self:_setControlValue(control, box.Text, false)
		control._refresh(true)
	end))
end

function Controller:_createColorPickerRow(parent, control)
	local row = create("Frame", {
		Name = control.Name .. "Row",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(308, 62),
		ZIndex = 4,
		Parent = parent,
	})
	applyFill(row, "#ffffff08")
	addCorner(row, 10)
	addGradient(row, 90, { "#ffffff10", "#0f172a20" })
	addStroke(row, 1, "#ffffff10")

	local label = create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(120, 14),
		Font = fontForWeight(500),
		Text = control.Name,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = row,
	})
	applyTextColor(label, "#ffffff99")

	local preview = create("Frame", {
		Name = "Preview",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0, 16),
		Size = UDim2.fromOffset(20, 20),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = row,
	})
	addCorner(preview, 999)
	local previewStroke = addStroke(preview, 1, "#ffffff40")

	local track = create("Frame", {
		Name = "PaletteTrack",
		Position = UDim2.fromOffset(10, 36),
		Size = UDim2.fromOffset(288, 12),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = row,
	})
	applyFill(track, "#0f172a80")
	addCorner(track, 999)
	local hueGradient = create("UIGradient", {
		Rotation = 0,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 68, 68)),
			ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 170, 17)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(34, 197, 94)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(59, 130, 246)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(96, 165, 250)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(168, 85, 247)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 68, 68)),
		}),
		Parent = track,
	})
	local trackStroke = addStroke(track, 1, "#ffffff18")

	local knobGlow = create("Frame", {
		Name = "KnobGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromOffset(24, 24),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = track,
	})
	addCorner(knobGlow, 999)
	local knobGlowScale = addScale(knobGlow, 1)

	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromOffset(16, 16),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = track,
	})
	applyFill(knob, WHITE)
	addCorner(knob, 999)
	addGradient(knob, 90, { WHITE, "#dbeafeff" })
	local knobScale = addScale(knob, 1)

	local hitbox = create("TextButton", {
		Name = "Hitbox",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(0, -4),
		Size = UDim2.new(1, 0, 1, 8),
		ZIndex = 8,
		Parent = track,
	})

	local hovered = false

	local function refresh(instant)
		local hue, sat, val = hexToHue(control.Value)
		local _, transparency = parseHex(control.Value)
		control._lastHSV = { sat, val }
		control._lastAlpha = math.floor((1 - transparency) * 255 + 0.5)
		local accent = control.Value
		local moveKnob = sat >= 0.05
		local offset = math.clamp(control._lastHue or hue, 0, 1) * track.AbsoluteSize.X
		if moveKnob then
			control._lastHue = hue
			offset = math.clamp(hue, 0, 1) * track.AbsoluteSize.X
		end

		if instant then
			preview.BackgroundColor3 = select(1, parseHex(accent))
			preview.BackgroundTransparency = select(2, parseHex(accent))
			applyStroke(previewStroke, "#ffffff60")
			if moveKnob then
				knob.Position = UDim2.fromOffset(offset, 6)
				knobGlow.Position = UDim2.fromOffset(offset, 6)
			end
			applyFill(knobGlow, withAlpha(accent, "38"))
			applyStroke(trackStroke, withAlpha(accent, "28"))
			return
		end

		animateFill(preview, accent, FAST_TWEEN)
		animateStroke(previewStroke, "#ffffff60", FAST_TWEEN)
		if moveKnob then
			animatePosition(knob, UDim2.fromOffset(offset, 6), FAST_TWEEN)
			animatePosition(knobGlow, UDim2.fromOffset(offset, 6), FAST_TWEEN)
		end
		animateFill(knobGlow, withAlpha(accent, "38"), FAST_TWEEN)
		animateStroke(trackStroke, withAlpha(accent, "28"), FAST_TWEEN)
	end

	local function updateFromPointer(pointerX, instant)
		local relative = math.clamp((pointerX - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		if not control._lastAlpha then
			local _, currentAlpha = parseHex(control.Value)
			control._lastAlpha = math.floor((1 - currentAlpha) * 255 + 0.5)
		end
		local alpha = control._lastAlpha / 255
		local sv = control._lastHSV or { 0.72, 1 }
		control._lastHue = relative
		control.Value = hueToHex(relative, alpha, sv[1], sv[2])
		control.CurrentValue = control.Value
		refresh(instant)
	end

	control._refresh = refresh
	refresh(true)

	local resetCpScales = function()
		if knobScale.Parent then animateScale(knobScale, hovered and 1.08 or 1, SOFT_TWEEN) end
		if knobGlowScale.Parent then animateScale(knobGlowScale, hovered and 1.16 or 1, SOFT_TWEEN) end
	end

	table.insert(self.settingsPanelConnections, hitbox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.draggingSlider = {
				update = function(pointerX)
					updateFromPointer(pointerX, true)
				end,
				finish = function()
					if track.Parent then refresh(false) end
					fireCallback(control.Callback, control.Value)
				end,
				cancel = function()
					resetCpScales()
				end,
			}
			animateScale(knobScale, 1.12, FAST_TWEEN)
			animateScale(knobGlowScale, 1.2, FAST_TWEEN)
			updateFromPointer(input.Position.X, true)
		end
	end))

	table.insert(self.settingsPanelConnections, hitbox.MouseEnter:Connect(function()
		hovered = true
		animateScale(knobScale, 1.08, FAST_TWEEN)
		animateScale(knobGlowScale, 1.16, FAST_TWEEN)
	end))

	table.insert(self.settingsPanelConnections, hitbox.MouseLeave:Connect(function()
		hovered = false
		if self.draggingSlider then
			return
		end
		animateScale(knobScale, 1, SOFT_TWEEN)
		animateScale(knobGlowScale, 1, SOFT_TWEEN)
	end))

	table.insert(self.sliderResetters, resetCpScales)

	-- Recompute knob position after layout pass so AbsoluteSize is valid
	task.defer(function()
		if track and track.Parent and not self.closing then
			refresh(true)
		end
	end)
end

function Controller:_createLabelRow(parent, control)
	local label = create("TextLabel", {
		Name = control.Name .. "Label",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(308, 18),
		Font = fontForWeight(500),
		Text = control.Content,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 4,
		Parent = parent,
	})
	applyTextColor(label, "#ffffff99")
end

function Controller:_createParagraphRow(parent, control)
	local card = create("Frame", {
		Name = control.Name .. "Paragraph",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(308, 56),
		ZIndex = 4,
		Parent = parent,
	})
	applyFill(card, "#ffffff08")
	addCorner(card, 10)
	addGradient(card, 90, { "#ffffff10", "#0f172a20" })
	addStroke(card, 1, "#ffffff10")

	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(288, 14),
		Font = fontForWeight(600),
		Text = control.Name,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = card,
	})
	applyTextColor(title, "#ffffffcc")

	local content = create("TextLabel", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 24),
		Size = UDim2.fromOffset(288, 24),
		Font = fontForWeight(400),
		Text = control.Content,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 5,
		Parent = card,
	})
	applyTextColor(content, "#ffffff99")
end

function Controller:_createControl(parent, control)
	if control.Type == "toggle" then
		self:_createToggleRow(parent, control)
	elseif control.Type == "checkbox" then
		self:_createCheckboxRow(parent, control)
	elseif control.Type == "slider" then
		self:_createSliderCard(parent, control)
	elseif control.Type == "input" then
		self:_createInputCard(parent, control)
	elseif control.Type == "colorpicker" then
		self:_createColorPickerRow(parent, control)
	elseif control.Type == "paragraph" then
		self:_createParagraphRow(parent, control)
	elseif control.Type == "label" then
		self:_createLabelRow(parent, control)
	end
end

function Controller:_renderSettingsPanel()
	if self.draggingSlider then
		if self.draggingSlider.cancel then
			pcall(self.draggingSlider.cancel)
		end
		self.draggingSlider = nil
	end
	if self.settingsPanelConnections then
		for _, conn in ipairs(self.settingsPanelConnections) do
			pcall(function() conn:Disconnect() end)
		end
		self.settingsPanelConnections = {}
	else
		self.settingsPanelConnections = {}
	end
	clearChildren(self.ui.settingsContent)
	for _, resetter in ipairs(self.sliderResetters or {}) do
		pcall(resetter)
	end
	self.sliderResetters = {}
	self.ui.settingsTitle = create("TextLabel", {
		Name = "SettingsTitle",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(308, 18),
		Font = fontForWeight(700),
		Text = "",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 4,
		Parent = self.ui.settingsContent,
	})
	applyTextColor(self.ui.settingsTitle, WHITE)

	if not self.selectedModule then
		self.ui.settingsTitle.Text = "No module selected"
		return
	end

	self.ui.settingsTitle.Text = self.selectedModule.Name

	if not self.settingsVisible then
		return
	end

	self:_createEnabledRow(self.ui.settingsContent, self.selectedModule)

	for _, section in ipairs(self.selectedModule.Sections) do
		if #section.Controls > 0 then
			local sectionFrame = self:_createSectionHeader(self.ui.settingsContent, section.Name)
			for _, control in ipairs(section.Controls) do
				self:_createControl(sectionFrame, control)
			end
		end
	end

	self.ui.settingsScroll.CanvasSize = UDim2.fromOffset(0, self.ui.settingsLayout.AbsoluteContentSize.Y + 28)

	task.defer(function()
		if self.closing then return end
		if self.ui and self.ui.settingsLayout and self.ui.settingsScroll and self.ui.settingsScroll.Parent then
			self.ui.settingsScroll.CanvasSize = UDim2.fromOffset(0, self.ui.settingsLayout.AbsoluteContentSize.Y + 28)
		end
	end)
end

function Controller:_close()
	if self.closing then
		return
	end

	self.closing = true
	self.appSettingsVisible = false

	if self.ui and self.ui.blur and self.ui.blur.Parent then
		pcall(function() self.ui.blur.Size = 0 end)
	end
	if self.connections then
		for _, conn in ipairs(self.connections) do
			pcall(function() conn:Disconnect() end)
		end
		self.connections = {}
	end
	if self.transientConnections then
		for _, conn in ipairs(self.transientConnections) do
			pcall(function() conn:Disconnect() end)
		end
		self.transientConnections = {}
	end
	if self.moduleRowConnections then
		for _, conn in ipairs(self.moduleRowConnections) do
			pcall(function() conn:Disconnect() end)
		end
		self.moduleRowConnections = {}
	end
	if self.settingsPanelConnections then
		for _, conn in ipairs(self.settingsPanelConnections) do
			pcall(function() conn:Disconnect() end)
		end
		self.settingsPanelConnections = {}
	end

	self.draggingWindow = false
	self.draggingSlider = nil

	animateFill(self.ui.backdrop, "#02061700", PANEL_TWEEN)
	animateScale(self.ui.mainScale, 0.94, PANEL_TWEEN)
	animateStroke(self.ui.mainStroke, "#ffffff08", PANEL_TWEEN)
	tween(self.ui.blur, PANEL_TWEEN, { Size = 0 })
	task.delay(0.24, function()
		if self.ui.blur.Parent then
			self.ui.blur:Destroy()
		end
		if self.ui.screenGui.Parent then
			self.ui.screenGui:Destroy()
		end
	end)
end

function Controller:_open()
	animateFill(self.ui.backdrop, self.theme.DimBackground, PANEL_TWEEN)
	animateScale(self.ui.mainScale, 1, PANEL_TWEEN)
	animateStroke(self.ui.mainStroke, "#ffffff1a", PANEL_TWEEN)
	tween(self.ui.blur, PANEL_TWEEN, { Size = self.theme.BlurSize })
end

function Controller:_getAppSettingsPosition(visible)
	local xOffset = (self.config.WindowWidth / 2) + (visible and 16 or 42)
	local yOffset = -(self.config.WindowHeight / 2)
	local panelWidth = 252
	local cam = workspace.CurrentCamera
	if cam and self.ui and self.ui.mainWindow then
		local vp = cam.ViewportSize
		local rightEdge = self.ui.mainWindow.AbsolutePosition.X + self.ui.mainWindow.AbsoluteSize.X + 16 + panelWidth
		if rightEdge > vp.X then
			xOffset = -(self.config.WindowWidth / 2) - panelWidth - (visible and 16 or 42)
		end
	end
	return self.ui.mainWindow.Position + UDim2.fromOffset(xOffset, yOffset)
end

function Controller:_updateAppSettingsPanelPosition(animate)
	if not self.ui.appSettingsPanel then
		return
	end

	local target = self:_getAppSettingsPosition(self.appSettingsVisible)

	if self.appSettingsVisible then
		self.ui.appSettingsPanel.Visible = true
		if animate then
			animatePosition(self.ui.appSettingsPanel, target, PANEL_TWEEN)
			animateScale(self.ui.appSettingsScale, 1, PANEL_TWEEN)
		else
			self.ui.appSettingsPanel.Position = target
			self.ui.appSettingsScale.Scale = 1
		end
	else
		if animate then
			animatePosition(self.ui.appSettingsPanel, target, PANEL_TWEEN)
			animateScale(self.ui.appSettingsScale, 0.96, PANEL_TWEEN)
		else
			self.ui.appSettingsPanel.Position = target
			self.ui.appSettingsScale.Scale = 0.96
		end
		task.delay(0.22, function()
			if self.ui.appSettingsPanel.Parent and not self.appSettingsVisible then
				self.ui.appSettingsPanel.Visible = false
			end
		end)
	end

	self.ui.settingsButton.active = self.appSettingsVisible
	self.ui.settingsButton:applyVisual("default")
end

function Controller:_refreshBindVisual()
	if not self.ui.bindValue then
		return
	end

	self.ui.bindValue.Text = self.waitingForBind and "Press key" or keyCodeToLabel(self.uiToggleKey)
	animateFill(self.ui.bindFrame, self.waitingForBind and self.theme.Accent .. "16" or "#ffffff08", FAST_TWEEN)
	animateStroke(self.ui.bindStroke, self.waitingForBind and self.theme.Accent .. "40" or "#ffffff14", FAST_TWEEN)
	animateText(self.ui.bindValue, self.waitingForBind and self.theme.AccentSoft or WHITE, FAST_TWEEN)
end

function Controller:_toggleAppSettings()
	self.appSettingsVisible = not self.appSettingsVisible
	self:_updateAppSettingsPanelPosition(true)
	self:_setConfigLabel(self.appSettingsVisible and "GUI Settings Open" or "GUI Settings Closed")
end

function Controller:_setWindowHidden(hidden)
	if self.windowHidden == hidden then
		return
	end

	self.windowHidden = hidden

	if hidden then
		animateFill(self.ui.backdrop, "#02061700", PANEL_TWEEN)
		tween(self.ui.blur, PANEL_TWEEN, { Size = 0 })
		self.ui.mainWindow.Visible = false
		if self.ui.appSettingsPanel then
			self.ui.appSettingsPanel.Visible = false
		end
	else
		self.ui.mainWindow.Visible = true
		self:_open()
		self:_updateAppSettingsPanelPosition(false)
	end
end

function Controller:_mount()
	local guiParent = gethui and gethui() or CoreGui
	local screenGui = create("ScreenGui", {
		Name = GUI_NAME,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = guiParent,
	})

	if syn and syn.protect_gui then
		local ok, err = pcall(syn.protect_gui, screenGui)
		if not ok then
			warn("[Sigmatik] syn.protect_gui failed: " .. tostring(err))
		end
	end

	local root = create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screenGui,
	})

	local backdrop = create("Frame", {
		Name = "Backdrop",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = root,
	})
	applyFill(backdrop, "#02061700")
	addGradient(backdrop, 45, { "#020617aa", "#000000aa", "#020617aa" })

	local blur = create("BlurEffect", {
		Name = BLUR_NAME,
		Enabled = true,
		Size = 0,
		Parent = Lighting,
	})

	local mainWindow = create("Frame", {
		Name = "MainWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(self.config.WindowWidth, self.config.WindowHeight),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = root,
	})
	applyFill(mainWindow, self.theme.WindowFill)
	addCorner(mainWindow, 16)
	addGradient(mainWindow, 90, { "#101729", "#0a0f1b", "#070b14" })
	local mainStroke = addStroke(mainWindow, 1, "#ffffff1a")
	local mainScale = addScale(mainWindow, 0.96)

	local header = create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		ZIndex = 2,
		Parent = mainWindow,
	})

	local headerBorder = create("Frame", {
		Name = "HeaderBorder",
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 2,
		Parent = header,
	})
	applyFill(headerBorder, "#ffffff14")

	local dragHandle = create("TextButton", {
		Name = "DragHandle",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -340, 0, 56),
		ZIndex = 2,
		Parent = header,
	})

	local titleLabel = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.fromOffset(220, 56),
		Font = fontForWeight(700),
		Text = self.config.Title,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = header,
	})
	applyTextColor(titleLabel, WHITE)

	local searchFrame = create("Frame", {
		Name = "SearchBar",
		Position = UDim2.fromOffset(313, 10),
		Size = UDim2.fromOffset(320, 36),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = header,
	})
	applyFill(searchFrame, "#00000040")
	addCorner(searchFrame, 10)
	addGradient(searchFrame, 90, { "#ffffff10", "#0f172a22" })
	local searchStroke = addStroke(searchFrame, 1, "#ffffff1a")
	local searchScale = addScale(searchFrame, 1)

	local searchIcon = createIcon(searchFrame, "search", 16, 4)
	searchIcon.frame.Position = UDim2.fromOffset(10, 12)
	searchIcon:setColor("#ffffffb3", false)

	local searchInput = create("TextBox", {
		Name = "SearchInput",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(34, 8),
		Size = UDim2.fromOffset(276, 20),
		Font = fontForWeight(400),
		Text = "",
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ClearTextOnFocus = false,
		PlaceholderText = "",
		ZIndex = 4,
		Parent = searchFrame,
	})
	applyTextColor(searchInput, WHITE)

	local searchPlaceholder = create("TextLabel", {
		Name = "Placeholder",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(34, 10),
		Size = UDim2.fromOffset(250, 16),
		Font = fontForWeight(400),
		Text = self.config.SearchPlaceholder,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = searchFrame,
	})
	applyTextColor(searchPlaceholder, "#ffffff80")

	local headerActions = create("Frame", {
		Name = "HeaderActions",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(320, 36),
		ZIndex = 3,
		Parent = header,
	})
	local headerLayout = addListLayout(headerActions, Enum.FillDirection.Horizontal, 10)
	headerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local statusCard = create("Frame", {
		Name = "StatusCard",
		Size = UDim2.fromOffset(236, 36),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = headerActions,
	})
	applyFill(statusCard, "#ffffff08")
	addCorner(statusCard, 10)
	addGradient(statusCard, 90, { "#ffffff10", "#0f172a20" })
	local statusStroke = addStroke(statusCard, 1, "#ffffff12")
	local statusScale = addScale(statusCard, 1)

	local activeLabel = create("TextLabel", {
		Name = "ActiveLabel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(54, 18),
		Size = UDim2.fromOffset(110, 18),
		Font = fontForWeight(600),
		Text = "0 Active",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = statusCard,
	})
	applyTextColor(activeLabel, "#22c55e")

	local statusDot = create("Frame", {
		Name = "StatusDot",
		Position = UDim2.fromOffset(116, 14),
		Size = UDim2.fromOffset(8, 8),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = statusCard,
	})
	applyFill(statusDot, "#22c55e")
	addCorner(statusDot, 999)

	local separator = create("Frame", {
		Name = "Separator",
		Position = UDim2.fromOffset(140, 10),
		Size = UDim2.fromOffset(1, 16),
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = statusCard,
	})
	applyFill(separator, "#ffffff14")

	local configLabel = create("TextLabel", {
		Name = "ConfigLabel",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(152, 0),
		Size = UDim2.fromOffset(74, 36),
		Font = fontForWeight(500),
		Text = self.config.ConfigName,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
		Parent = statusCard,
	})
	applyTextColor(configLabel, "#ffffff80")

	local settingsButton = self:_createHeaderIconButton(headerActions, "SettingsButton", "#ffffff08", "settings", "#ffffffb3")
	local closeButton = self:_createHeaderIconButton(headerActions, "CloseButton", "#ff44441a", "x", "#ff6666")

	local body = create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		ZIndex = 2,
		Parent = mainWindow,
	})

	local sidebar = create("Frame", {
		Name = "Sidebar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(220, self.config.WindowHeight - 56),
		ZIndex = 2,
		Parent = body,
	})

	local sidebarBorder = create("Frame", {
		Name = "SidebarBorder",
		BorderSizePixel = 0,
		Position = UDim2.new(1, -1, 0, 0),
		Size = UDim2.new(0, 1, 1, 0),
		ZIndex = 2,
		Parent = sidebar,
	})
	applyFill(sidebarBorder, "#ffffff14")

	local categoryContainer = create("Frame", {
		Name = "CategoryContainer",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(192, self.config.WindowHeight - 84),
		ZIndex = 3,
		Parent = sidebar,
	})
	addListLayout(categoryContainer, Enum.FillDirection.Vertical, 10)

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(220, 0),
		Size = UDim2.fromOffset(self.config.WindowWidth - 220, self.config.WindowHeight - 56),
		ZIndex = 2,
		Parent = body,
	})

	searchFrame.Parent = content
	searchFrame.Position = UDim2.fromOffset(16, 16)
	searchFrame.Size = UDim2.fromOffset(708, 40)

	local modulePanel = create("Frame", {
		Name = "Modules",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 68),
		Size = UDim2.fromOffset(708, self.config.WindowHeight - 140),
		ZIndex = 3,
		Parent = content,
	})

	local moduleContainer = create("Frame", {
		Name = "ModuleContainer",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 3,
		Parent = modulePanel,
	})
	addListLayout(moduleContainer, Enum.FillDirection.Vertical, 10)

	local settingsPanelHiddenPosition = UDim2.fromOffset(404, 68)
	local settingsPanelShownPosition = UDim2.fromOffset(388, 68)

	local settingsPanel = create("Frame", {
		Name = "SettingsPanel",
		Position = settingsPanelHiddenPosition,
		Size = UDim2.fromOffset(336, self.config.WindowHeight - 140),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 3,
		Parent = content,
	})
	applyFill(settingsPanel, "#ffffff05")
	addCorner(settingsPanel, 12)
	addGradient(settingsPanel, 90, { "#ffffff0f", "#0f172a20" })
	local settingsPanelStroke = addStroke(settingsPanel, 1, "#ffffff12")
	local settingsPanelScale = addScale(settingsPanel, 0.96)

	local settingsScroll = create("ScrollingFrame", {
		Name = "SettingsScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = settingsPanel,
	})

	local settingsContent = create("Frame", {
		Name = "SettingsContent",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 3,
		Parent = settingsScroll,
	})
	addPadding(settingsContent, 14, 14, 14, 14)
	local settingsLayout = addListLayout(settingsContent, Enum.FillDirection.Vertical, 10)

	local settingsTitle = create("TextLabel", {
		Name = "SettingsTitle",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(308, 18),
		Font = fontForWeight(700),
		Text = "No module selected",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 4,
		Parent = settingsContent,
	})
	applyTextColor(settingsTitle, WHITE)

	local appSettingsPanel = create("Frame", {
		Name = "AppSettingsPanel",
		AnchorPoint = Vector2.new(0, 0),
		Position = mainWindow.Position + UDim2.fromOffset((self.config.WindowWidth / 2) + 42, -(self.config.WindowHeight / 2)),
		Size = UDim2.fromOffset(252, 180),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = root,
	})
	applyFill(appSettingsPanel, "#0b1020e8")
	addCorner(appSettingsPanel, 16)
	addGradient(appSettingsPanel, 90, { "#101729", "#0a0f1b", "#070b14" })
	local appSettingsStroke = addStroke(appSettingsPanel, 1, "#ffffff14")
	local appSettingsScale = addScale(appSettingsPanel, 0.96)

	local appHeader = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.fromOffset(220, 18),
		Font = fontForWeight(700),
		Text = "GUI Settings",
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = appSettingsPanel,
	})
	applyTextColor(appHeader, WHITE)

	local appSubtitle = create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 36),
		Size = UDim2.fromOffset(220, 14),
		Font = fontForWeight(400),
		Text = "Manage GUI bind and panel info.",
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = appSettingsPanel,
	})
	applyTextColor(appSubtitle, "#ffffff80")

	local bindLabel = create("TextLabel", {
		Name = "BindLabel",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 72),
		Size = UDim2.fromOffset(140, 16),
		Font = fontForWeight(600),
		Text = "Open / Close GUI",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = appSettingsPanel,
	})
	applyTextColor(bindLabel, "#ffffffcc")

	local bindFrame = create("Frame", {
		Name = "BindFrame",
		Position = UDim2.fromOffset(16, 96),
		Size = UDim2.fromOffset(220, 36),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = appSettingsPanel,
	})
	applyFill(bindFrame, "#ffffff08")
	addCorner(bindFrame, 10)
	addGradient(bindFrame, 90, { "#ffffff10", "#0f172a1e" })
	local bindStroke = addStroke(bindFrame, 1, "#ffffff14")

	local bindValue = create("TextLabel", {
		Name = "BindValue",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromOffset(196, 36),
		Font = fontForWeight(600),
		Text = "K",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 4,
		Parent = bindFrame,
	})
	applyTextColor(bindValue, WHITE)

	local bindButton = create("TextButton", {
		Name = "BindButton",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = bindFrame,
	})

	local telegramLabel = create("TextLabel", {
		Name = "TelegramLabel",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 144),
		Size = UDim2.fromOffset(220, 14),
		Font = fontForWeight(500),
		Text = "Telegram: @sigmatik323",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = appSettingsPanel,
	})
	applyTextColor(telegramLabel, "#ffffffa6")

	table.insert(self.connections, settingsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		settingsScroll.CanvasSize = UDim2.fromOffset(0, settingsLayout.AbsoluteContentSize.Y + 28)
	end))

	self.ui = {
		screenGui = screenGui,
		root = root,
		backdrop = backdrop,
		blur = blur,
		mainWindow = mainWindow,
		mainStroke = mainStroke,
		mainScale = mainScale,
		dragHandle = dragHandle,
		searchFrame = searchFrame,
		searchStroke = searchStroke,
		searchScale = searchScale,
		searchIcon = searchIcon,
		searchInput = searchInput,
		searchPlaceholder = searchPlaceholder,
		activeLabel = activeLabel,
		statusDot = statusDot,
		statusStroke = statusStroke,
		statusScale = statusScale,
		configLabel = configLabel,
		settingsButton = settingsButton,
		closeButton = closeButton,
		categoryContainer = categoryContainer,
		categoryEntries = {},
		modulePanel = modulePanel,
		moduleContainer = moduleContainer,
		settingsPanel = settingsPanel,
		settingsPanelStroke = settingsPanelStroke,
		settingsPanelScale = settingsPanelScale,
		settingsPanelHiddenPosition = settingsPanelHiddenPosition,
		settingsPanelShownPosition = settingsPanelShownPosition,
		appSettingsPanel = appSettingsPanel,
		appSettingsStroke = appSettingsStroke,
		appSettingsScale = appSettingsScale,
		bindFrame = bindFrame,
		bindStroke = bindStroke,
		bindValue = bindValue,
		bindButton = bindButton,
		settingsScroll = settingsScroll,
		settingsContent = settingsContent,
		settingsLayout = settingsLayout,
		settingsTitle = settingsTitle,
	}

	table.insert(self.connections, searchInput.Focused:Connect(function()
		self:_updateSearchVisual(true)
	end))
	table.insert(self.connections, searchInput.FocusLost:Connect(function()
		self:_updateSearchVisual(false)
	end))
	table.insert(self.connections, searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		self:_updateSearchPlaceholder(false)
		searchIcon:setColor(searchInput.Text ~= "" and self.theme.AccentSoft or (self.searchFocused and self.theme.Accent or "#ffffffb3"), true)
		self.searchSerial = (self.searchSerial or 0) + 1
		local serial = self.searchSerial
		task.delay(0.08, function()
			if serial == self.searchSerial and not self.closing then
				self:_renderModuleRows(true)
			end
		end)
	end))

	local function handleClose()
		self:_close()
	end

	table.insert(self.connections, closeButton.button.MouseButton1Click:Connect(handleClose))
	table.insert(self.connections, settingsButton.button.MouseButton1Click:Connect(function()
		self:_toggleAppSettings()
	end))
	table.insert(self.connections, bindButton.MouseButton1Click:Connect(function()
		self.waitingForBind = true
		self:_refreshBindVisual()
	end))

	table.insert(self.connections, dragHandle.InputBegan:Connect(function(input)
		if self.closing then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.draggingWindow = true
			self.dragStart = input.Position
			self.startPosition = mainWindow.Position
		end
	end))

	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if self.closing then return end
		local isMove = input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
		if self.draggingWindow and isMove then
			local delta = input.Position - self.dragStart
			mainWindow.Position = UDim2.new(
				self.startPosition.X.Scale,
				self.startPosition.X.Offset + delta.X,
				self.startPosition.Y.Scale,
				self.startPosition.Y.Offset + delta.Y
			)
			self:_updateAppSettingsPanelPosition(false)
			return
		end

		if self.draggingSlider and isMove then
			self.draggingSlider.update(input.Position.X)
		end
	end))

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if self.closing then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if self.waitingForBind then
			-- Always consume the keystroke and clear the flag
			self.waitingForBind = false
			local kc = input.KeyCode
			local invalid = {
				[Enum.KeyCode.Unknown] = true,
				[Enum.KeyCode.Escape] = true,
				[Enum.KeyCode.LeftShift] = true,
				[Enum.KeyCode.RightShift] = true,
				[Enum.KeyCode.LeftControl] = true,
				[Enum.KeyCode.RightControl] = true,
				[Enum.KeyCode.LeftAlt] = true,
				[Enum.KeyCode.RightAlt] = true,
				[Enum.KeyCode.Tab] = true,
			}
			if not gameProcessed and not invalid[kc] then
				self.uiToggleKey = kc
				self:_refreshBindVisual()
				self:_setConfigLabel("GUI Key Updated")
			else
				self:_refreshBindVisual()
				self:_setConfigLabel("Bind Cancelled")
			end
			return
		end

		if gameProcessed then
			return
		end

		if input.KeyCode == self.uiToggleKey then
			self:_setWindowHidden(not self.windowHidden)
		end
	end))

	table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
		if self.closing then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if self.draggingSlider then
				self.draggingSlider.finish()
				self.draggingSlider = nil
			end

			for _, resetter in ipairs(self.sliderResetters) do
				pcall(resetter)
			end

			self.draggingWindow = false
		end
	end))

	table.insert(self.connections, UserInputService.WindowFocusReleased:Connect(function()
		self.draggingWindow = false
		self.draggingSlider = nil
	end))

	-- Intentionally NOT in self.connections so the cleanup survives _close().
	screenGui.AncestryChanged:Connect(function(_, parent)
		if parent == nil and blur.Parent then
			blur:Destroy()
		end
	end)

	for _, tab in ipairs(self.tabs) do
		self:_createCategoryTab(tab)
	end

	self:_updateSearchPlaceholder(true)
	self:_updateSearchVisual(false)
	self:_refreshCategoryTabs()
	self:_renderModuleRows(true)
	self:_refreshHeaderSummary()
	self:_updateModulePanelLayout()
	self:_renderSettingsPanel()
	self:_refreshBindVisual()
	self:_updateAppSettingsPanelPosition(false)
	self:_open()
end

function Controller:Destroy()
	self:_close()
end

function Controller:GetTab(name)
	return self.tabLookup[name]
end

function Controller:GetModule(tabName, moduleName)
	local tab = self.tabLookup[tabName]
	if not tab then
		return nil
	end

	return tab.ModuleLookup[moduleName]
end

function Controller:SetModuleEnabled(tabName, moduleName, enabled)
	local module = self:GetModule(tabName, moduleName)
	if module then
		self:_setModuleEnabled(module, enabled, false)
	end
end

function Controller:SetControlValue(tabName, moduleName, sectionName, controlName, value)
	local module = self:GetModule(tabName, moduleName)
	if not module then
		return
	end

	local section = module.SectionLookup[sectionName]
	if not section then
		return
	end

	for _, control in ipairs(section.Controls) do
		if control.Name == controlName then
			self:_setControlValue(control, value, false)
			return
		end
	end
end

local Library = {}

function Library:Create(config)
	config = config or {}
	destroyExisting()

	local controller = setmetatable({}, Controller)
	controller.config = {
		Title = config.Title or "Sigmatik UI",
		ConfigName = config.ConfigName or "Default Config",
		SearchPlaceholder = config.SearchPlaceholder or "Search modules...",
		WindowWidth = config.WindowWidth or 960,
		WindowHeight = config.WindowHeight or 540,
	}
	controller.theme = shallowCopy(DEFAULT_THEME)
	controller.theme.Accent = config.Accent or DEFAULT_THEME.Accent
	controller.theme.AccentSoft = config.AccentSoft or DEFAULT_THEME.AccentSoft
	controller.theme.WindowFill = config.WindowFill or DEFAULT_THEME.WindowFill
	controller.theme.DimBackground = config.DimBackground or DEFAULT_THEME.DimBackground
	controller.theme.BlurSize = config.BlurSize or DEFAULT_THEME.BlurSize
	controller.tabs = {}
	controller.tabLookup = {}
	controller.selectedTab = nil
	controller.selectedModule = nil
	controller.settingsVisible = false
	controller.appSettingsVisible = false
	controller.searchFocused = false
	controller.draggingWindow = false
	controller.draggingSlider = nil
	controller.sliderResetters = {}
	controller.connections = {}
	controller.transientConnections = {}
	controller.moduleRowConnections = {}
	controller.settingsPanelConnections = {}
	controller.lastActiveCount = -1
	controller.closing = false
	controller.waitingForBind = false
	controller.windowHidden = false
	local toggleKeyValid = typeof(config.GuiToggleKey) == "EnumItem"
		and tostring(config.GuiToggleKey.EnumType) == "Enum.KeyCode"
	controller.uiToggleKey = toggleKeyValid and config.GuiToggleKey or Enum.KeyCode.RightShift

	for _, tab in ipairs(config.Tabs or {}) do
		local normalizedTab = normalizeTab(tab)
		if controller.tabLookup[normalizedTab.Name] then
			warn("[Sigmatik] duplicate tab name: " .. tostring(normalizedTab.Name))
		end
		table.insert(controller.tabs, normalizedTab)
		controller.tabLookup[normalizedTab.Name] = normalizedTab
	end

	controller.selectedTab = controller.tabs[1]
	controller.selectedModule = controller.selectedTab and controller.selectedTab.Modules[1] or nil

	controller:_mount()
	return controller
end

return Library

end)()

-- ============================================================================
-- Saber Tsunami :: Auto Suite (uses sigmatik_ui_library, persists to disk)
-- ============================================================================
local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local RunService           = game:GetService("RunService")
local CollectionService    = game:GetService("CollectionService")
local CoreGui              = game:GetService("CoreGui")
local UserInputService     = game:GetService("UserInputService")
local HttpService          = game:GetService("HttpService")
local VirtualInputManager  = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

local Net          = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Packages"):WaitForChild("Network")
local KickEvent    = Net:WaitForChild("rev_KickEvent")
local CollectEvent = Net:WaitForChild("rev_B_Collect")
local SpeedUpgrade = Net:WaitForChild("rev_SPEED_UPGRADE")
local ShopBuy      = Net:WaitForChild("rev_Shop_Buy")
local WeightEquip  = Net:WaitForChild("rev_WeightEquip")
local SellFn       = Net:WaitForChild("ref_B_Sell")
local SellAllFn    = Net:WaitForChild("ref_B_SellAll")

local GameHandler          = require(ReplicatedStorage.Modules.HandlerLoader.GameHandler)
local WeightServiceClient  = require(ReplicatedStorage.Modules.ServicesLoader.WeightServiceClient)
local ClientBalanceService = require(ReplicatedStorage.Modules.ServicesLoader.ClientBalanceService)
local WeightsData          = require(ReplicatedStorage.Shared.Data.WeightsData)
local EntitiesData         = require(ReplicatedStorage.Shared.Data.EntitiesData)
local PlacedVisualizer     = require(ReplicatedStorage.Modules.ControllerLoader.PlacedVisualizer)
local GetOfflineCash       = require(ReplicatedStorage.Shared.Functional.GetOfflineCash)
local InfiniteMath         = require(ReplicatedStorage.Shared.Utility.InfiniteMath)
local MutationData         = require(ReplicatedStorage.Shared.Data.MutationData)
local PlotHitboxController = require(ReplicatedStorage.Modules.ControllerLoader.PlotHitboxController)
local ClientPlotService    = require(ReplicatedStorage.Modules.ServicesLoader.ClientPlotService)
local KickServiceClient    = require(ReplicatedStorage.Modules.ServicesLoader.KickServiceClient)
local RebirthServiceClient = require(ReplicatedStorage.Modules.ServicesLoader.RebirthServiceClient)
local RebirthData          = require(ReplicatedStorage.Shared.Data.RebirthData)
local SInteract            = Net:WaitForChild("rev_S_Interact")
local BUpgrade             = Net:WaitForChild("rev_B_Upgrade")
local RebirthRequest       = Net:WaitForChild("rev_RebirthRequest")

local KICK_LABELS = {
    { min = 0,    text = "Bad"       },
    { min = 0.2,  text = "Mid"       },
    { min = 0.4,  text = "Good"      },
    { min = 0.6,  text = "Great"     },
    { min = 0.8,  text = "Excellent" },
    { min = 0.97, text = "Perfect"   },
}
local function kickRating(v)
    local out = "Bad"
    for _, e in ipairs(KICK_LABELS) do
        if v >= e.min then out = e.text end
    end
    return out
end

local RARITY_INDEX = {
    Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5,
    Godly = 6, Secret = 7, Rainbow = 8, Hacked = 9, Demon = 10,
    Celestial = 11, Divine = 12, OG = 13, Exclusive = 14,
}

local MUTATION_CYCLE = {
    "OFF", "Any", "None",
    "Golden", "Diamond", "Plasma", "Molten",
    "Radioactive", "Shadow", "Electrified",
    "Rainbow", "Void", "Virus",
}

local MUTATION_COLOR = {
    Any        = Color3.fromRGB(120, 240, 130),
    None       = Color3.fromRGB(180, 200, 220),
    Golden     = Color3.fromRGB(255, 200,   0),
    Diamond    = Color3.fromRGB(  0, 229, 255),
    Plasma     = Color3.fromRGB(255,   0, 212),
    Molten     = Color3.fromRGB(255, 140,   0),
    Radioactive= Color3.fromRGB(153, 255,   0),
    Shadow     = Color3.fromRGB(120, 120, 130),
    Electrified= Color3.fromRGB(  7, 111, 163),
    Rainbow    = Color3.fromRGB(255, 100, 255),
    Void       = Color3.fromRGB( 80,  20, 120),
    Virus      = Color3.fromRGB( 50, 200,  60),
}

local SORT_NAMES = { "Rarity", "Price \xE2\x86\x93", "Price \xE2\x86\x91" }  -- ↓ ↑

local function bigToNumLocal(b)
    if type(b) == "number" then return b end
    if type(b) == "table" then return (b.first or 0) * (10 ^ (b.second or 0)) end
    return 0
end

local function effectiveCPS(name, mutation, level)
    local d = EntitiesData.Brainrots and EntitiesData.Brainrots[name]
    if not d then return 0 end
    local cps = bigToNumLocal(d.CPS)
    local mutBuff = 1
    if mutation and MutationData and MutationData.Buffs and MutationData.Buffs[mutation] then
        mutBuff = MutationData.Buffs[mutation].Value or 1
    end
    local lvlMult = 1
    if EntitiesData.GetMultiplierPerLevel then
        local ok, m = pcall(EntitiesData.GetMultiplierPerLevel, EntitiesData, level or 1)
        if ok and m then lvlMult = m end
    end
    return cps * mutBuff * lvlMult
end

local function brainrotSortValue(name, modeIdx, mutation, level)
    local d = EntitiesData.Brainrots and EntitiesData.Brainrots[name] or {}
    local cps = effectiveCPS(name, mutation, level)
    if modeIdx == 1 then        -- Rarity (high to low, cps tiebreak)
        local r = RARITY_INDEX[d.Rarity] or 0
        return r * 1e15 + cps
    elseif modeIdx == 2 then    -- Price Desc
        return cps
    else                        -- Price Asc (negate so higher key = better-for-sort)
        return -cps
    end
end

----------------------------------------------------------------- helpers
local function bigToNum(b)
    if type(b) == "number" then return b end
    if type(b) == "table" then return (b.first or 0) * (10 ^ (b.second or 0)) end
    return 0
end

local function getCharParts()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return nil end
    return char, hum, root
end

local function findToolWithTag(tag)
    local function pick(parent)
        if not parent then return nil end
        for _, v in ipairs(parent:GetChildren()) do
            if v:IsA("Tool") and CollectionService:HasTag(v, tag) then return v end
        end
    end
    return pick(LocalPlayer.Character) or pick(LocalPlayer.Backpack)
end

----------------------------------------------------------------- state
-- Save Zone bounds are internal (not user-facing): X=690, Z 172..290
local SAVE_X, SAVE_Z_MIN, SAVE_Z_MAX = 690, 172, 290

local Cfg = {
    KickPower = 1.0,
    KickWaitAfter = 4,
    AutoClaimInterval = 0.2,
    AutoClaimBatchSize = 10,
    AutoClaimMax = 40,
    AutoSpeedInterval = 0.1,
    AutoSpeedAmount = 1,
    AutoBuyWeightInterval = 1.0,
    AutoBuyWeightEquipAfter = true,
    AutoSellInterval = 0.5,
    AutoPopupEnabled = true,
    AutoEquipSort = 1,   -- 1=Rarity, 2=Price↓, 3=Price↑
    PickerSort    = 1,
    AutoUpgradeMode = 1, -- 1=All, 2=Sequential, 3=Cheapest, 4=Custom
    FlySpeed   = 50,
    WalkSpeed  = 32,
    JumpPower  = 50,
    BestSave   = false,
    BestSaveTriggerX = 564,
    BestSaveYOffset = 0,
    FastPlay   = false,
    FastPlayV2 = false,
    FastPlayKickMult = 1,           -- 1 = off (server timing-checks anything > 1)
    FastPlaySafeMargin = 0.5,       -- extra seconds wait after server-expected wave time
    GetOnlyEnabled = false,         -- only keep drops worth >= GetOnlyMin, dump the rest
    GetOnlyMin = 0,                 -- minimum brainrot CPS value to keep (0..48.9M)
    GetOnlyMode = 1,                -- where to dump low drops: 1=Tsunami (restart), 2=Safe Zone
    TgEnabled = false,              -- send a Telegram message on every successful catch
    ConnectKey = "",                -- personal key from the bot (/start) — links catches to your Telegram
}

local WaveData = require(ReplicatedStorage.Shared.Data.WaveData)
local RarityData = require(ReplicatedStorage.Shared.Data.RarityData)
local _activeWaveRarity = nil

local UPGRADE_MODE_NAMES = { "All at once", "Sequential", "Cheapest first", "Custom slots" }

local State = { AutoPlay = false, AutoWeight = false, AutoClaim = false,
                AutoBuySpeed = false, AutoBuyWeight = false, AutoSell = false,
                ShowEarnings = false, AntiAFK = false, AutoEquip = false,
                AutoUpgrade = false, AutoRebirth = false,
                Fly = false, Noclip = false, FastWalk = false, HighJump = false,
                FullBright = false, NoFog = false }

local SellWhitelist       = {}
local StopOnHitWhitelist  = {}
local UpgradeSlotWhitelist = {}  -- for Custom mode

local Threads = {}
local AntiAnchorConn

----------------------------------------------------------------- persistence
local CONFIG_PATH = "SaberAutoSuite.json"

local function safeRead(path)
    if isfile and isfile(path) then
        local ok, data = pcall(readfile, path)
        if ok then return data end
    end
    return nil
end

local function safeWrite(path, data)
    if writefile then pcall(writefile, path, data) end
end

local UI

local function plainSet(t)
    local out = {}
    for k, v in pairs(t) do if v then out[k] = true end end
    return out
end

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deepCopy(v) end
    return out
end

local function saveConfig()
    local payload = {
        Cfg = Cfg,
        SellWhitelist = plainSet(SellWhitelist),
        StopOnHitWhitelist = deepCopy(StopOnHitWhitelist),
        UpgradeSlotWhitelist = plainSet(UpgradeSlotWhitelist),
        Modules = {
            AutoPlay      = State.AutoPlay,
            AutoWeight    = State.AutoWeight,
            AutoClaim     = State.AutoClaim,
            AutoBuySpeed  = State.AutoBuySpeed,
            AutoBuyWeight = State.AutoBuyWeight,
            AutoSell      = State.AutoSell,
            ShowEarnings  = State.ShowEarnings,
            AntiAFK       = State.AntiAFK,
            AutoEquip     = State.AutoEquip,
            AutoUpgrade   = State.AutoUpgrade,
            AutoRebirth   = State.AutoRebirth,
            Fly           = State.Fly,
            Noclip        = State.Noclip,
            FastWalk      = State.FastWalk,
            HighJump      = State.HighJump,
            FullBright    = State.FullBright,
            NoFog         = State.NoFog,
        },
    }
    local ok, encoded = pcall(function() return HttpService:JSONEncode(payload) end)
    if ok then safeWrite(CONFIG_PATH, encoded) end
end

local function loadConfig()
    local raw = safeRead(CONFIG_PATH)
    if not raw then return nil end
    local ok, payload = pcall(function() return HttpService:JSONDecode(raw) end)
    if not ok or type(payload) ~= "table" then return nil end
    if type(payload.Cfg) == "table" then
        for k, v in pairs(payload.Cfg) do Cfg[k] = v end
    end
    if type(payload.SellWhitelist) == "table" then
        for k, v in pairs(payload.SellWhitelist) do SellWhitelist[k] = v and true or nil end
    end
    if type(payload.StopOnHitWhitelist) == "table" then
        for k, v in pairs(payload.StopOnHitWhitelist) do
            if type(v) == "table" then
                StopOnHitWhitelist[k] = deepCopy(v)
            elseif type(v) == "string" then
                StopOnHitWhitelist[k] = { [v] = true }
            elseif v == true then
                StopOnHitWhitelist[k] = { Any = true }
            end
        end
    end
    if type(payload.UpgradeSlotWhitelist) == "table" then
        for k, v in pairs(payload.UpgradeSlotWhitelist) do
            UpgradeSlotWhitelist[tonumber(k) or k] = v and true or nil
        end
    end
    return payload
end

local pendingSave = false
local function scheduleSave()
    if pendingSave then return end
    pendingSave = true
    task.delay(0.3, function() pendingSave = false; saveConfig() end)
end

----------------------------------------------------------------- TELEGRAM NOTIFY (via backend)
-- The bot token lives ONLY on the server (telepasta.ru) — never in this script.
-- We POST catches/stats to the backend using your personal Connect Key (from the
-- bot's /start). The backend formats and sends the Telegram message + Mini App data.
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
    or (fluxus and fluxus.request)

local BACKEND = "https://telepasta.ru/saber/api"

local function abbrevNum(v)
    v = v or 0
    if v >= 1e9 then return string.format("%.2fB", v / 1e9) end
    if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
    if v >= 1e3 then return string.format("%.1fK", v / 1e3) end
    return tostring(math.floor(v))
end

-- fire-and-forget JSON POST to the backend (never blocks the caller)
local function backendPost(path, tbl)
    if not httpRequest then return end
    task.spawn(function()
        pcall(httpRequest, {
            Url = BACKEND .. path,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(tbl),
        })
    end)
end

-- notify the backend about a successful (kept) catch → it sends the Telegram message
local function tgNotifyCatch(name, mut, value)
    if not Cfg.TgEnabled then return end
    if not Cfg.ConnectKey or Cfg.ConnectKey == "" then return end
    local d = EntitiesData.Brainrots and EntitiesData.Brainrots[name]
    backendPost("/catch", {
        key = Cfg.ConnectKey,
        name = name,
        rarity = d and d.Rarity or nil,
        value = value,
        mutation = (mut and mut ~= "None") and mut or nil,
    })
end

-- ---- play stats: Time Play (seconds while Auto Play is on) + games played -----
local Stats = { seconds = 0, games = 0 }

local function flushStats()
    if not Cfg.ConnectKey or Cfg.ConnectKey == "" then return end
    local s = math.floor(Stats.seconds)
    local g = Stats.games
    if s < 1 and g < 1 then return end
    Stats.seconds = Stats.seconds - s
    Stats.games = 0
    backendPost("/stat", { key = Cfg.ConnectKey, addSeconds = s, addGames = g })
end

task.spawn(function()
    local last = os.clock()
    while true do
        task.wait(30)
        local now = os.clock()
        if State.AutoPlay then Stats.seconds = Stats.seconds + (now - last) end
        last = now
        flushStats()
    end
end)

----------------------------------------------------------------- AUTO KICK
local function isInSaveZone()
    local _, _, root = getCharParts()
    if not root then return false end
    local p = root.Position
    return math.abs(p.X - SAVE_X) < 30 and p.Z >= SAVE_Z_MIN - 5 and p.Z <= SAVE_Z_MAX + 5
end

local function teleportToSaveZone()
    local _, _, root = getCharParts()
    if not root then return end
    local centerZ = (SAVE_Z_MIN + SAVE_Z_MAX) / 2
    root.CFrame = CFrame.new(SAVE_X, root.Position.Y, centerZ)
end

local function fireKick()
    KickEvent:FireServer(math.clamp(Cfg.KickPower, 0, 1))
end

local function moveToSafeZoneOnce()
    local _, hum, root = getCharParts()
    if not hum or not root then return end
    if root.Anchored then return end
    local z = math.clamp(root.Position.Z, SAVE_Z_MIN, SAVE_Z_MAX)
    hum:MoveTo(Vector3.new(SAVE_X, root.Position.Y, z))
end

local function feedToWaveOnce()
    local _, _, root = getCharParts()
    if not root or root.Anchored then return end
    local waves = workspace:FindFirstChild("Waves")
    if not waves then return end
    for _, m in ipairs(waves:GetChildren()) do
        local rp = m:FindFirstChild("RootPart") or m.PrimaryPart
        if rp then
            root.CFrame = rp.CFrame
            return
        end
    end
end

local function bestSavePhase()
    local _, hum, root = getCharParts()
    if not hum or not root then
        while State.AutoPlay and GameHandler.InGame do task.wait(0.1) end
        return
    end

    local centerZ = (SAVE_Z_MIN + SAVE_Z_MAX) / 2
    local z = math.clamp(root.Position.Z, SAVE_Z_MIN, SAVE_Z_MAX)
    if z == 0 then z = centerZ end

    -- 1. Single CFrame TP: only X+Z change, Y stays exactly as the game placed us
    root.CFrame = CFrame.new(SAVE_X - 10, root.Position.Y, z)

    -- 2. Wait for the wave to reach trigger X (default 564)
    -- If Fast Play is on, also enforce a server-side minimum time so we don't
    -- collect before the server's own wave reaches the trigger.
    local trigger = Cfg.BestSaveTriggerX or 564
    local serverMinTime = 0
    if Cfg.FastPlay and _activeWaveRarity and WaveData.Waves and WaveData.Waves[_activeWaveRarity] then
        local entry = WaveData.Waves[_activeWaveRarity]
        if entry.Start_X and entry.Speed and entry.Speed > 0 then
            serverMinTime = (trigger - entry.Start_X) / entry.Speed + (Cfg.FastPlaySafeMargin or 0.5)
        end
    end
    local phaseStart = os.clock()
    while State.AutoPlay and GameHandler.InGame do
        local waves = workspace:FindFirstChild("Waves")
        local hit = false
        if waves then
            for _, m in ipairs(waves:GetChildren()) do
                local r2 = m:FindFirstChild("RootPart") or m.PrimaryPart
                if r2 and r2.Position.X >= trigger then hit = true; break end
            end
        end
        local elapsedOk = os.clock() - phaseStart >= serverMinTime
        if hit and elapsedOk then break end
        task.wait(0.05)
    end

    -- 3. Walk to the Save Zone — natural humanoid movement, never touch Y
    while State.AutoPlay and GameHandler.InGame do
        local _, h, r = getCharParts()
        if h and r then
            local cz = math.clamp(r.Position.Z, SAVE_Z_MIN, SAVE_Z_MAX)
            h:MoveTo(Vector3.new(SAVE_X, r.Position.Y, cz))
        end
        task.wait(0.15)
    end
end

local AutoPlayEpoch = 0
-- declared before autoPlayLoop so the loop, the KickEvent handler and the
-- Get Only logic all share the SAME locals (not split global/local copies)
local SuicideMode = false      -- dump the current drop into the wave (restart)
local ForceSaveZone = false    -- hard-park the current drop in the Safe Zone (keep it)

local _lastSaveY = nil  -- remembered floor height of the Save Zone (anti under-map)
local function hardParkSaveZone()
    local char, _, root = getCharParts()
    if not root or root.Anchored then return end
    local centerZ = (SAVE_Z_MIN + SAVE_Z_MAX) / 2
    local z = math.clamp(root.Position.Z, SAVE_Z_MIN, SAVE_Z_MAX)
    if z == 0 then z = centerZ end

    -- find the real floor at the save spot so we never drop under the map:
    -- raycast straight down from well above, ignoring our character and the wave
    local foot = (root.Size and root.Size.Y / 2 + 1) or 3
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char, workspace:FindFirstChild("Waves") }
    local originY = math.max(root.Position.Y, _lastSaveY or root.Position.Y) + 300
    local hit = workspace:Raycast(Vector3.new(SAVE_X, originY, z),
        Vector3.new(0, -3000, 0), params)

    local targetY
    if hit then
        targetY = hit.Position.Y + foot
        _lastSaveY = targetY            -- cache the good height
    elseif _lastSaveY then
        targetY = _lastSaveY            -- reuse last good height if the ray missed
    else
        targetY = root.Position.Y       -- last resort: keep current height
    end

    -- zero velocity before teleporting so physics can't tunnel us through the floor
    pcall(function() root.AssemblyLinearVelocity = Vector3.zero end)
    pcall(function() root.AssemblyAngularVelocity = Vector3.zero end)
    root.CFrame = CFrame.new(SAVE_X, targetY, z)
end

local function autoPlayLoop(epoch)
    local function alive() return State.AutoPlay and AutoPlayEpoch == epoch end
    while alive() do
        if GameHandler.InGame then
            while alive() and GameHandler.InGame and GameHandler.Status ~= "Tsunami" do
                task.wait(0.1)
            end
            if not alive() then break end
            -- settle: let the KickEvent drop handler classify this wave first
            -- (sets SuicideMode / ForceSaveZone) before we pick the phase
            task.wait(0.2)
            if SuicideMode then
                while alive() and GameHandler.InGame do
                    feedToWaveOnce()
                    task.wait(0.2)
                end
            elseif ForceSaveZone then
                -- Get Only "Safe Zone": teleport to safety and hold there so the
                -- low-value brainrot survives the wave (no slow walking)
                while alive() and GameHandler.InGame do
                    hardParkSaveZone()
                    task.wait(0.15)
                end
            elseif Cfg.BestSave or Cfg.FastPlay then
                bestSavePhase()
            else
                while alive() and GameHandler.InGame do
                    moveToSafeZoneOnce()
                    task.wait(0.25)
                end
            end
            SuicideMode = false
            ForceSaveZone = false
            task.wait(0.4)
        else
            if not alive() then break end
            if not isInSaveZone() then
                teleportToSaveZone()
                task.wait(0.4)
            end
            if not alive() then break end
            fireKick()
            local t0 = os.clock()
            while alive() and not GameHandler.InGame and os.clock() - t0 < Cfg.KickWaitAfter do
                task.wait(0.1)
            end
        end
    end
    -- on exit: ensure character isn't left anchored from Best Save park
    local _, _, r = getCharParts()
    if r and r.Anchored then r.Anchored = false end
end

-- normalize legacy string entries to mutation-set tables
local function normalizeStopList()
    for k, v in pairs(StopOnHitWhitelist) do
        if type(v) == "string" then
            StopOnHitWhitelist[k] = { [v] = true }
        elseif v == true then
            StopOnHitWhitelist[k] = { Any = true }
        elseif type(v) ~= "table" then
            StopOnHitWhitelist[k] = nil
        end
    end
end
normalizeStopList()

local function hasStopTargets()
    for _, set in pairs(StopOnHitWhitelist) do
        if type(set) == "table" then
            for _ in pairs(set) do return true end
        end
    end
    return false
end

local function isStopMatch(name, mut)
    local entry = StopOnHitWhitelist[name]
    if type(entry) ~= "table" then return false end
    if entry.Any then return true end
    return entry[mut or "None"] == true
end

KickEvent.OnClientEvent:Connect(function(distance, brainrot, mutation)
    -- always cache the active wave's rarity so Fast Play V2 can match speed
    if type(distance) == "number" and RarityData and RarityData.GetRarityByDistance then
        local ok, r = pcall(RarityData.GetRarityByDistance, RarityData, distance)
        if ok then _activeWaveRarity = r end
    end

    if not State.AutoPlay then return end
    if type(brainrot) ~= "table" or not brainrot.Name then return end

    local effMut = mutation or "None"
    local mutArg = (effMut ~= "None") and effMut or nil
    local val = effectiveCPS(brainrot.Name, mutArg, brainrot.Level)

    -- Get Only: any drop worth less than the threshold is dumped (to the wave or the safe zone)
    if Cfg.GetOnlyEnabled and val < (Cfg.GetOnlyMin or 0) then
        if (Cfg.GetOnlyMode or 1) == 2 then
            -- Safe Zone: park the brainrot in safety (keeps it, no restart)
            SuicideMode = false
            ForceSaveZone = true
            print(("[Saber] Get Only: %s (%s) value %.0f < %.0f — sending to Safe Zone"):format(
                brainrot.Name, effMut, val, Cfg.GetOnlyMin or 0))
        else
            -- Tsunami: feed it to the wave so Auto Play restarts
            ForceSaveZone = false
            SuicideMode = true
            print(("[Saber] Get Only: %s (%s) value %.0f < %.0f — feeding to Tsunami"):format(
                brainrot.Name, effMut, val, Cfg.GetOnlyMin or 0))
        end
        return  -- below threshold: NOT a successful catch, no Telegram
    end

    -- past the value gate: decide keep vs dump via the stop-on-hit list
    SuicideMode = false
    ForceSaveZone = false

    local kept = true
    if hasStopTargets() then
        if isStopMatch(brainrot.Name, effMut) then
            print(("[Saber] Caught %s (mut=%s) — collecting"):format(brainrot.Name, effMut))
        elseif effMut == "None" then
            -- default brainrot, no match — collect normally
        else
            -- wrong mutated drop: let autoPlayLoop feed it to the wave (restart)
            SuicideMode = true
            kept = false
            print(("[Saber] Wrong mutated drop (%s+%s) — feeding to wave NOW"):format(brainrot.Name, effMut))
        end
    end

    -- successful catch (kept and at/above the Get Only threshold) → Telegram ping
    if kept then
        tgNotifyCatch(brainrot.Name, effMut, val)
    end
end)

-- reset suicide flag and wave rarity when game ends
local KickEventEnded = Net:WaitForChild("rev_KickEventEnded")
KickEventEnded.OnClientEvent:Connect(function()
    SuicideMode = false
    ForceSaveZone = false
    _activeWaveRarity = nil
    -- count a game the script played (for Time Play / games stats)
    if State.AutoPlay then Stats.games = Stats.games + 1 end
end)

----------------------------------------------------------------- AUTO SQUAT (weight bonus auto-clicker)
local function isBonusPopup(btn)
    if not btn or not btn.Parent then return false end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    local kickUI = pg:FindFirstChild("KickUpgrades")
    if not kickUI then return false end
    if not btn:IsDescendantOf(kickUI) then return false end
    return btn:IsA("ImageButton") or btn:IsA("TextButton")
end

local function clickBonusButton(btn)
    if not isBonusPopup(btn) then return end
    local ok = pcall(function() firesignal(btn.Activated) end)
    if ok then return end
    local pos = btn.AbsolutePosition + btn.AbsoluteSize / 2
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true,  game, 0)
        task.wait(0.04)
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
    end)
end

local function ensureUnanchored(root)
    if not root then return end
    if AntiAnchorConn then AntiAnchorConn:Disconnect() end
    AntiAnchorConn = root:GetPropertyChangedSignal("Anchored"):Connect(function()
        if State.AutoWeight and root.Anchored then root.Anchored = false end
    end)
    if root.Anchored then root.Anchored = false end
end

local function bindCharacterAnchor()
    local _, _, root = getCharParts()
    ensureUnanchored(root)
    Threads.AntiAnchorWatch = task.spawn(function()
        while State.AutoWeight do
            local char = LocalPlayer.CharacterAdded:Wait()
            if not State.AutoWeight then break end
            char:WaitForChild("HumanoidRootPart", 5)
            task.wait(0.3)
            local _, _, r = getCharParts()
            ensureUnanchored(r)
        end
    end)
end

local function autoWeightLoop()
    local addConn = CollectionService:GetInstanceAddedSignal("Button"):Connect(function(btn)
        if not State.AutoWeight then return end
        if not Cfg.AutoPopupEnabled then return end
        task.wait(0.15)
        if State.AutoWeight and Cfg.AutoPopupEnabled then clickBonusButton(btn) end
    end)
    if Cfg.AutoPopupEnabled then
        for _, btn in ipairs(CollectionService:GetTagged("Button")) do clickBonusButton(btn) end
    end

    bindCharacterAnchor()

    while State.AutoWeight do
        if not GameHandler.InGame then
            local _, hum = getCharParts()
            if hum then
                local tool = findToolWithTag("SquatTool")
                if tool and tool.Parent == LocalPlayer.Backpack then
                    hum:EquipTool(tool)
                end
            end
        end
        task.wait(1)
    end

    if addConn then addConn:Disconnect() end
    if AntiAnchorConn then AntiAnchorConn:Disconnect(); AntiAnchorConn = nil end
end

----------------------------------------------------------------- AUTO CLAIM CASH
local AutoClaimEpoch = 0
local function autoClaimLoop(epoch)
    local idx = 1
    while State.AutoClaim and AutoClaimEpoch == epoch do
        for j = 1, 10 do
            if not State.AutoClaim or AutoClaimEpoch ~= epoch then return end
            CollectEvent:FireServer(idx)
            idx = idx % 40 + 1
        end
        task.wait(0.2)
    end
end

----------------------------------------------------------------- AUTO EQUIP BEST BRAINROT
local function getInventoryBrainrots()
    local list = {}
    local function scan(parent)
        if not parent then return end
        for _, t in ipairs(parent:GetChildren()) do
            if t:IsA("Tool") and CollectionService:HasTag(t, "EntityTool") then
                local d = EntitiesData.Brainrots[t.Name] or {}
                table.insert(list, { tool = t, name = t.Name, cps = bigToNum(d.CPS) })
            end
        end
    end
    scan(LocalPlayer.Backpack)
    scan(LocalPlayer.Character)
    return list
end

local function getPlotSlots()
    local plot = ClientPlotService.Model
    if not plot then return {} end
    local slotsFolder = plot:FindFirstChild("Slots")
    if not slotsFolder then return {} end
    local out = {}
    for _, slot in ipairs(slotsFolder:GetChildren()) do
        local id = tonumber((slot.Name:gsub("Slot", "")))
        if id then
            local placed = slot:FindFirstChild("PlacedPart")
            local cur, cps
            if placed then
                local entry = PlacedVisualizer.MyBrainrots[placed]
                if entry then
                    cur = entry.Brainrot
                    cps = bigToNum((EntitiesData.Brainrots[cur] or {}).CPS)
                end
            end
            table.insert(out, { id = id, slot = slot, current = cur, cps = cps or 0 })
        end
    end
    return out
end

local function autoEquipBestLoop()
    local lastSwapTime = {}  -- slotId -> os.clock() of last swap (cooldown)
    local SWAP_COOLDOWN = 5  -- seconds before re-touching a slot

    local function readSlotAttrs(slot)
        local plot = ClientPlotService.Model
        local sl = plot and plot.Slots and plot.Slots:FindFirstChild("Slot" .. slot.id)
        local placed = sl and sl:FindFirstChild("PlacedPart")
        if not placed then return nil, 1 end
        return placed:GetAttribute("Mutation"), placed:GetAttribute("Level") or 1
    end

    -- signature ties a brainrot identity to its (name, mutation, level)
    -- so a placed item and the same item as a tool share one signature.
    local function sig(name, mut, lvl)
        return tostring(name) .. "|" .. tostring(mut) .. "|" .. tostring(lvl)
    end

    while State.AutoEquip do
        local slots = getPlotSlots()
        if #slots == 0 then
            task.wait(2)
        else
            table.sort(slots, function(a, b) return a.id < b.id end)
            local sortIdx = math.floor(Cfg.AutoEquipSort or 1)

            -- assemble all items (placed + tools)
            local items = {}
            for _, s in ipairs(slots) do
                if s.current then
                    local mut, lvl = readSlotAttrs(s)
                    table.insert(items, {
                        name = s.current, mut = mut, lvl = lvl,
                        score = brainrotSortValue(s.current, sortIdx, mut, lvl),
                        src = "slot", slot = s,
                    })
                end
            end
            for _, t in ipairs(getInventoryBrainrots()) do
                local mut = t.tool:GetAttribute("Mutation")
                local lvl = t.tool:GetAttribute("Level") or 1
                table.insert(items, {
                    name = t.name, mut = mut, lvl = lvl,
                    score = brainrotSortValue(t.name, sortIdx, mut, lvl),
                    src = "tool", tool = t.tool,
                })
            end
            table.sort(items, function(a, b) return a.score > b.score end)

            -- top-N "needed" multiset by signature
            local needed = {}
            for i = 1, math.min(#slots, #items) do
                local sg = sig(items[i].name, items[i].mut, items[i].lvl)
                needed[sg] = (needed[sg] or 0) + 1
            end

            -- consume needed by what's already placed correctly
            local happy = {}
            for _, s in ipairs(slots) do
                if s.current then
                    local mut, lvl = readSlotAttrs(s)
                    local sg = sig(s.current, mut, lvl)
                    if (needed[sg] or 0) > 0 then
                        needed[sg] = needed[sg] - 1
                        happy[s.id] = true
                    end
                end
            end

            local madeSwap = false
            for _, s in ipairs(slots) do
                if not State.AutoEquip then break end
                if happy[s.id] then continue end
                if (lastSwapTime[s.id] or 0) > os.clock() - SWAP_COOLDOWN then continue end

                -- pick the best tool whose signature is still in `needed`
                local invNow = getInventoryBrainrots()
                local pickTool, pickSig, pickScore
                for _, t in ipairs(invNow) do
                    local mut = t.tool:GetAttribute("Mutation")
                    local lvl = t.tool:GetAttribute("Level") or 1
                    local sg = sig(t.name, mut, lvl)
                    if (needed[sg] or 0) > 0 then
                        local sc = brainrotSortValue(t.name, sortIdx, mut, lvl)
                        if not pickScore or sc > pickScore then
                            pickTool, pickSig, pickScore = t.tool, sg, sc
                        end
                    end
                end
                if pickTool then
                    local _, hum = getCharParts()
                    if hum then
                        hum:EquipTool(pickTool)
                        task.wait(0.3)
                        if not State.AutoEquip then break end
                        SInteract:FireServer(s.id)
                        task.wait(0.8)
                        needed[pickSig] = (needed[pickSig] or 0) - 1
                        lastSwapTime[s.id] = os.clock()
                        madeSwap = true
                    end
                end
            end

            task.wait(madeSwap and 1.0 or 3)
        end
    end
end

----------------------------------------------------------------- AUTO UPGRADE
local function getMaxSlotId()
    local plot = ClientPlotService.Model
    if not plot then return 10 end
    local slots = plot:FindFirstChild("Slots")
    if not slots then return 10 end
    local maxId = 0
    for _, s in ipairs(slots:GetChildren()) do
        local n = tonumber((s.Name:gsub("Slot", "")))
        if n and n > maxId then maxId = n end
    end
    return math.min(40, math.max(10, maxId))
end

local function slotUpgradeCost(id)
    local plot = ClientPlotService.Model
    if not plot or not plot:FindFirstChild("Slots") then return math.huge end
    local slot = plot.Slots:FindFirstChild("Slot" .. id)
    local placed = slot and slot:FindFirstChild("PlacedPart")
    if not placed then return math.huge end

    -- read live attributes off the placed part — PlacedVisualizer.MyBrainrots
    -- only refreshes its level when the upgrade UI is open for that slot.
    local lvl = placed:GetAttribute("Level") or 1
    local mut = placed:GetAttribute("Mutation")
    local entry = PlacedVisualizer.MyBrainrots[placed]
    local brName = entry and entry.Brainrot
    if not brName then return math.huge end
    local data = EntitiesData.Brainrots and EntitiesData.Brainrots[brName]
    if not data then return math.huge end
    local maxLvl = EntitiesData.MAX_LEVEL or 75
    if lvl >= maxLvl then return math.huge end
    local ok, cost = pcall(EntitiesData.GetCostForUpgrade, EntitiesData, data, lvl, mut)
    return ok and bigToNum(cost) or math.huge
end

local function getSlotIdsForUpgrade()
    local mode = math.floor(Cfg.AutoUpgradeMode or 1)
    local plot = ClientPlotService.Model
    local maxId = getMaxSlotId()
    local list = {}
    if mode == 4 then
        -- Custom: only user-picked slots
        for id, on in pairs(UpgradeSlotWhitelist) do
            if on and tonumber(id) then table.insert(list, tonumber(id)) end
        end
        table.sort(list)
        return list
    end
    if plot and plot:FindFirstChild("Slots") then
        for _, slot in ipairs(plot.Slots:GetChildren()) do
            local id = tonumber((slot.Name:gsub("Slot", "")))
            if id then table.insert(list, id) end
        end
    end
    if #list == 0 then
        for i = 1, maxId do table.insert(list, i) end
    end
    if mode == 3 then
        table.sort(list, function(a, b) return slotUpgradeCost(a) < slotUpgradeCost(b) end)
    else
        table.sort(list)
    end
    return list
end

local function autoUpgradeLoop()
    while State.AutoUpgrade do
        local mode = math.floor(Cfg.AutoUpgradeMode or 1)
        local ids = getSlotIdsForUpgrade()
        if #ids == 0 then
            task.wait(0.5)
        elseif mode == 1 then
            -- All at once: rapid spam, small gap between
            for _, i in ipairs(ids) do
                if not State.AutoUpgrade then break end
                BUpgrade:FireServer(i)
                task.wait(0.05)
            end
            task.wait(0.1)
        elseif mode == 2 then
            -- Sequential: fire one slot at a time, wait, next
            for _, i in ipairs(ids) do
                if not State.AutoUpgrade then break end
                BUpgrade:FireServer(i)
                task.wait(0.4)
            end
        elseif mode == 3 then
            -- Cheapest first that we can AFFORD; level evens out toward MAX over time
            local balance = bigToNum(ClientBalanceService.Balance)
            local pickedId, pickedCost
            for _, sid in ipairs(ids) do
                local c = slotUpgradeCost(sid)
                if c <= balance and c < math.huge then
                    if not pickedCost or c < pickedCost then
                        pickedId, pickedCost = sid, c
                    end
                end
            end
            if pickedId then
                BUpgrade:FireServer(pickedId)
                task.wait(1.0)  -- give server time to deduct + replicate level
            else
                task.wait(2)    -- nothing affordable yet, wait
            end
        else
            -- Custom slots: spam only selected slots
            for _, i in ipairs(ids) do
                if not State.AutoUpgrade then break end
                BUpgrade:FireServer(i)
                task.wait(0.05)
            end
            task.wait(0.1)
        end
    end
end

----------------------------------------------------------------- FAST PLAY (kick + wave boost)
local _origKickSpeed
local FastPlayConn

local function applyFastPlay()
    if not KickServiceClient or not KickServiceClient.Multipliers then return end
    if Cfg.FastPlay then
        _origKickSpeed = _origKickSpeed or KickServiceClient.Multipliers.Speed or 1
        KickServiceClient.Multipliers.Speed = math.max(1, Cfg.FastPlayKickMult or 30)
    elseif _origKickSpeed then
        KickServiceClient.Multipliers.Speed = _origKickSpeed
        _origKickSpeed = nil
    end
end

local function startFastPlay()
    applyFastPlay()
    -- NOTE: wave-nudge / wave-pin removed. Server runs its own wave simulation —
    -- accelerating the client-side wave and then firing KickCollect early triggers
    -- the server's "(t_collect - t_transformed) >= traversal_time" check → kick.
end

local function stopFastPlay()
    applyFastPlay()  -- restore original kick speed
end

local function setFastPlay(s)
    Cfg.FastPlay = s
    if s then startFastPlay() else stopFastPlay() end
    scheduleSave()
end

----------------------------------------------------------------- FAST PLAY V2 (brainrot speed = wave speed)
local FastPlayV2Conn
local _origWalkSpeed

local function getCurrentWaveSpeed()
    -- preferred: rarity captured from KickEvent
    if _activeWaveRarity and WaveData.Waves and WaveData.Waves[_activeWaveRarity] then
        local s = WaveData.Waves[_activeWaveRarity].Speed
        if s then return s end
    end
    -- fallback: name match
    local waves = workspace:FindFirstChild("Waves")
    if waves then
        for _, m in ipairs(waves:GetChildren()) do
            local entry = WaveData.Waves and WaveData.Waves[m.Name]
            if entry and entry.Speed then return entry.Speed end
        end
    end
    return nil
end

local function startFastPlayV2()
    if FastPlayV2Conn then return end
    FastPlayV2Conn = RunService.Heartbeat:Connect(function()
        if not Cfg.FastPlayV2 then return end
        if not GameHandler.InGame then return end
        local _, hum = getCharParts()
        if not hum then return end
        local ws = getCurrentWaveSpeed()
        if ws and ws > 0 then
            _origWalkSpeed = _origWalkSpeed or hum.WalkSpeed
            hum.WalkSpeed = ws
        end
    end)
end

local function stopFastPlayV2()
    if FastPlayV2Conn then FastPlayV2Conn:Disconnect(); FastPlayV2Conn = nil end
    local _, hum = getCharParts()
    if hum and _origWalkSpeed then
        hum.WalkSpeed = State.FastWalk and (Cfg.WalkSpeed or 32) or 16
    end
    _origWalkSpeed = nil
end

local function setFastPlayV2(s)
    Cfg.FastPlayV2 = s
    if s then startFastPlayV2() else stopFastPlayV2() end
    scheduleSave()
end

----------------------------------------------------------------- AUTO REBIRTH
local function autoRebirthLoop()
    while State.AutoRebirth do
        local lvl = (RebirthServiceClient.RebirthLevel or 0) + 1
        local maxRb = RebirthData.MAX_REBIRTH or 10
        if lvl <= maxRb then
            local req = nil
            if RebirthData.GetKickRequirement then
                local ok, r = pcall(function() return RebirthData:GetKickRequirement(lvl) end)
                if ok then req = r end
            end
            local kickLvl = (KickServiceClient and KickServiceClient.Level) or 0
            if not req or kickLvl >= req then
                RebirthRequest:FireServer()
            end
        end
        task.wait(2)
    end
end

----------------------------------------------------------------- FLY
local FlyConn, FlyBV, FlyBG
local function startFly()
    local _, _, root = getCharParts()
    if not root then return end
    if FlyBV then FlyBV:Destroy() end
    if FlyBG then FlyBG:Destroy() end
    FlyBV = Instance.new("BodyVelocity")
    FlyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    FlyBV.Velocity = Vector3.zero
    FlyBV.Parent = root
    FlyBG = Instance.new("BodyGyro")
    FlyBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    FlyBG.P = 1000
    FlyBG.CFrame = root.CFrame
    FlyBG.Parent = root
    if FlyConn then FlyConn:Disconnect() end
    FlyConn = RunService.Heartbeat:Connect(function()
        if not State.Fly then return end
        local cam = workspace.CurrentCamera
        local move = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0, 1, 0) end
        if FlyBV then
            FlyBV.Velocity = (move.Magnitude > 0) and (move.Unit * (Cfg.FlySpeed or 50)) or Vector3.zero
        end
        if FlyBG then FlyBG.CFrame = cam.CFrame end
    end)
end
local function stopFly()
    if FlyConn then FlyConn:Disconnect(); FlyConn = nil end
    if FlyBV then FlyBV:Destroy(); FlyBV = nil end
    if FlyBG then FlyBG:Destroy(); FlyBG = nil end
end
local function setFly(s)
    if s == State.Fly then return end
    State.Fly = s
    if s then startFly() else stopFly() end
    scheduleSave()
end
LocalPlayer.CharacterAdded:Connect(function()
    if State.Fly then task.wait(0.5); startFly() end
end)

----------------------------------------------------------------- NOCLIP
local NoclipConn
local function applyNoclip(char)
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end
local function setNoclip(s)
    if s == State.Noclip then return end
    State.Noclip = s
    if NoclipConn then NoclipConn:Disconnect(); NoclipConn = nil end
    if s then
        NoclipConn = RunService.Stepped:Connect(function()
            if State.Noclip and LocalPlayer.Character then
                applyNoclip(LocalPlayer.Character)
            end
        end)
    end
    scheduleSave()
end

----------------------------------------------------------------- WALK SPEED + JUMP
local function applyWalkSpeed()
    local _, hum = getCharParts()
    if hum then hum.WalkSpeed = State.FastWalk and (Cfg.WalkSpeed or 32) or 16 end
end
local function applyJumpPower()
    local _, hum = getCharParts()
    if hum then hum.JumpPower = State.HighJump and (Cfg.JumpPower or 50) or 50 end
end
local function setFastWalk(s)
    if s == State.FastWalk then return end
    State.FastWalk = s
    applyWalkSpeed()
    scheduleSave()
end
local function setHighJump(s)
    if s == State.HighJump then return end
    State.HighJump = s
    applyJumpPower()
    scheduleSave()
end
LocalPlayer.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid", 5)
    task.wait(0.4)
    applyWalkSpeed()
    applyJumpPower()
end)

----------------------------------------------------------------- FULL BRIGHT + NO FOG
local Lighting = game:GetService("Lighting")
local _origLighting
local function snapshotLighting()
    if _origLighting then return end
    _origLighting = {
        Brightness = Lighting.Brightness,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        ColorShift_Top = Lighting.ColorShift_Top,
        ColorShift_Bottom = Lighting.ColorShift_Bottom,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        GlobalShadows = Lighting.GlobalShadows,
    }
end
local function setFullBright(s)
    if s == State.FullBright then return end
    snapshotLighting()
    State.FullBright = s
    if s then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        Lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
        Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
        Lighting.GlobalShadows = false
    elseif _origLighting then
        Lighting.Brightness         = _origLighting.Brightness
        Lighting.ClockTime          = _origLighting.ClockTime
        Lighting.Ambient            = _origLighting.Ambient
        Lighting.OutdoorAmbient     = _origLighting.OutdoorAmbient
        Lighting.ColorShift_Top     = _origLighting.ColorShift_Top
        Lighting.ColorShift_Bottom  = _origLighting.ColorShift_Bottom
        Lighting.GlobalShadows      = _origLighting.GlobalShadows
    end
    scheduleSave()
end
local function setNoFog(s)
    if s == State.NoFog then return end
    snapshotLighting()
    State.NoFog = s
    if s then
        Lighting.FogEnd = 1e6
        Lighting.FogStart = 1e6
    elseif _origLighting then
        Lighting.FogEnd = _origLighting.FogEnd
        Lighting.FogStart = _origLighting.FogStart
    end
    scheduleSave()
end

----------------------------------------------------------------- TP TO PLAYER
local function tpToPlayer(plr)
    if not plr or not plr.Character then return end
    local target = plr.Character:FindFirstChild("HumanoidRootPart")
    local _, _, root = getCharParts()
    if target and root then
        root.CFrame = target.CFrame + Vector3.new(0, 3, 3)
    end
end

local TPGui
local function buildTPPicker()
    if TPGui and TPGui.Parent then TPGui.Enabled = true; return end
    local host = getHostGui()
    TPGui = Instance.new("ScreenGui")
    TPGui.Name = "SaberTPPicker"
    TPGui.ResetOnSpawn = false
    TPGui.IgnoreGuiInset = true
    TPGui.Parent = host

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(320, 420)
    frame.Position = UDim2.new(0.5, -160, 0.5, -210)
    frame.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = TPGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    local fs = Instance.new("UIStroke", frame); fs.Color = Color3.fromRGB(60, 70, 100)

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(16, 10)
    title.Size = UDim2.fromOffset(220, 24)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextColor3 = Color3.fromRGB(240, 240, 250)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Teleport to player"
    title.Parent = frame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(28, 28)
    closeBtn.Position = UDim2.new(1, -36, 0, 8)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 16
    closeBtn.Text = "X"
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
    closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = frame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
    closeBtn.MouseButton1Click:Connect(function() TPGui.Enabled = false end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(12, 44)
    scroll.Size = UDim2.new(1, -24, 1, -56)
    scroll.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 5
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Parent = frame
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
    local layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 4)
    Instance.new("UIPadding", scroll).PaddingTop = UDim.new(0, 4)

    local function rebuild()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local b = Instance.new("TextButton")
                b.Size = UDim2.new(1, -8, 0, 32)
                b.BackgroundColor3 = Color3.fromRGB(28, 34, 52)
                b.Font = Enum.Font.Gotham
                b.TextSize = 13
                b.Text = "  " .. plr.DisplayName .. "  (@" .. plr.Name .. ")"
                b.TextColor3 = Color3.fromRGB(230, 235, 245)
                b.TextXAlignment = Enum.TextXAlignment.Left
                b.BorderSizePixel = 0
                b.Parent = scroll
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
                b.MouseButton1Click:Connect(function()
                    tpToPlayer(plr)
                end)
            end
        end
    end
    rebuild()
    Players.PlayerAdded:Connect(rebuild)
    Players.PlayerRemoving:Connect(rebuild)
end

----------------------------------------------------------------- ANTI AFK
local antiAfkConn
local function setAntiAFK(s)
    if s == State.AntiAFK then return end
    State.AntiAFK = s
    if s then
        if antiAfkConn then antiAfkConn:Disconnect() end
        antiAfkConn = LocalPlayer.Idled:Connect(function()
            local ok, VU = pcall(function() return game:GetService("VirtualUser") end)
            if ok and VU then
                pcall(function()
                    VU:CaptureController()
                    VU:ClickButton2(Vector2.new())
                end)
            end
        end)
    else
        if antiAfkConn then antiAfkConn:Disconnect(); antiAfkConn = nil end
    end
    scheduleSave()
end

----------------------------------------------------------------- AUTO BUY SPEED
local function autoBuySpeedLoop()
    while State.AutoBuySpeed do
        SpeedUpgrade:FireServer(math.max(1, math.floor(Cfg.AutoSpeedAmount)))
        task.wait(Cfg.AutoSpeedInterval)
    end
end

----------------------------------------------------------------- AUTO BUY WEIGHT
local function getOwnedSet()
    local set = {}
    for _, name in ipairs(WeightServiceClient.Owned or {}) do set[name] = true end
    return set
end

local function pickBestAffordableWeight()
    local owned = getOwnedSet()
    local balance = bigToNum(ClientBalanceService.Balance)
    local best, bestPPS
    for name, w in pairs(WeightsData.Weights or {}) do
        if not owned[name] then
            local cost = bigToNum(w.Cost)
            if cost <= balance and cost > 0 then
                if not bestPPS or (w.PPS or 0) > bestPPS then
                    best, bestPPS = name, w.PPS or 0
                end
            end
        end
    end
    return best
end

local function autoBuyWeightLoop()
    while State.AutoBuyWeight do
        local target = pickBestAffordableWeight()
        if target then
            ShopBuy:FireServer("WeightShop", target)
            task.wait(0.5)
            if Cfg.AutoBuyWeightEquipAfter then
                local owned = getOwnedSet()
                if owned[target] and WeightServiceClient.Equipped ~= target then
                    WeightEquip:FireServer(target)
                end
            end
        end
        task.wait(Cfg.AutoBuyWeightInterval)
    end
end

----------------------------------------------------------------- AUTO SELL
local function findBrainrotInBackpack(name)
    local function check(parent)
        if not parent then return nil end
        local t = parent:FindFirstChild(name)
        if t and t:IsA("Tool") and CollectionService:HasTag(t, "EntityTool") then return t end
    end
    return check(LocalPlayer.Backpack) or check(LocalPlayer.Character)
end

local function sellOne(name)
    local _, hum = getCharParts()
    if not hum then return false end
    local tool = findBrainrotInBackpack(name)
    if not tool then return false end
    if tool.Parent ~= LocalPlayer.Character then
        hum:EquipTool(tool)
        task.wait(0.2)
    end
    pcall(function() SellFn:InvokeServer() end)
    task.wait(0.15)
    return true
end

local function sellHeldNow()  pcall(function() SellFn:InvokeServer()    end) end
local function sellAllNow()   pcall(function() SellAllFn:InvokeServer() end) end

local function autoSellLoop()
    while State.AutoSell do
        local sold = false
        for name in pairs(SellWhitelist) do
            if not State.AutoSell then break end
            if findBrainrotInBackpack(name) then
                sellOne(name)
                sold = true
            end
        end
        if not sold then task.wait(Cfg.AutoSellInterval) end
    end
end

----------------------------------------------------------------- SHOW EARNINGS (overrides native InPlot label)
local earningsBrainrotConn, earningsPlotConn

local function fmtInf(num)
    if not num then return "0" end
    local ok, s = pcall(function() return num:GetSuffix(true) end)
    if ok and s then return tostring(s) end
    if type(num) == "number" then return tostring(num) end
    return "0"
end

local function getEarningsLabel()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local hud = pg:FindFirstChild("HUD")
    if not hud then return nil end
    local topBar = hud:FindFirstChild("TopBar")
    if not topBar then return nil end
    local inPlot = topBar:FindFirstChild("InPlot")
    if not inPlot then return nil end
    return inPlot:FindFirstChild("TextLabel")
end

local function paintEarningsLabel()
    if not State.ShowEarnings then return end
    if not PlotHitboxController.IsInPlot then return end
    local label = getEarningsLabel()
    if not label then return end
    local data = PlacedVisualizer.MyBrainrots
    if not data then return end
    local ok, daily = pcall(GetOfflineCash, data)
    if not ok or not daily then return end
    local okDiv, hour, minute, sec, ms = pcall(function()
        return daily / 24, daily / 1440, daily / 86400, daily / 86400000
    end)
    if not okDiv then return end
    label.RichText = true
    label.Text = string.format(
        "Earn  <font color=\"#71ff13\">$%s</font>/Day  •  <font color=\"#71ff13\">$%s</font>/Hr  •  <font color=\"#71ff13\">$%s</font>/Min  •  <font color=\"#71ff13\">$%s</font>/Sec  •  <font color=\"#71ff13\">$%s</font>/Ms \240\159\152\136",
        fmtInf(daily), fmtInf(hour), fmtInf(minute), fmtInf(sec), fmtInf(ms)
    )
end

local function startShowEarnings()
    if earningsBrainrotConn then earningsBrainrotConn:Disconnect() end
    if earningsPlotConn     then earningsPlotConn:Disconnect()     end
    earningsBrainrotConn = PlacedVisualizer.MyBrainrotsChanged:Connect(function()
        task.defer(paintEarningsLabel)
    end)
    earningsPlotConn = PlotHitboxController.PlayerInPlot:Connect(function()
        task.defer(paintEarningsLabel)
    end)
    task.defer(paintEarningsLabel)
    -- realtime repaint via Heartbeat
    Threads.EarningsLoop = task.spawn(function()
        while State.ShowEarnings do
            paintEarningsLabel()
            RunService.Heartbeat:Wait()
        end
    end)
end

local function stopShowEarnings()
    if earningsBrainrotConn then earningsBrainrotConn:Disconnect(); earningsBrainrotConn = nil end
    if earningsPlotConn     then earningsPlotConn:Disconnect();     earningsPlotConn = nil     end
end

local function setShowEarnings(s)
    if s == State.ShowEarnings then return end
    State.ShowEarnings = s
    if s then startShowEarnings() else stopShowEarnings() end
    scheduleSave()
end

----------------------------------------------------------------- toggles
local function setAutoPlay(s)
    if s == State.AutoPlay then return end
    State.AutoPlay = s
    AutoPlayEpoch = AutoPlayEpoch + 1
    if s then
        local myEpoch = AutoPlayEpoch
        Threads.AutoPlay = task.spawn(function() autoPlayLoop(myEpoch) end)
    end
    scheduleSave()
end
local function setAutoWeight(s)     if s ~= State.AutoWeight    then State.AutoWeight    = s; if s then Threads.AutoWeight    = task.spawn(autoWeightLoop)    end; scheduleSave() end end
local function setAutoBuySpeed(s)   if s ~= State.AutoBuySpeed  then State.AutoBuySpeed  = s; if s then Threads.AutoBuySpeed  = task.spawn(autoBuySpeedLoop)  end; scheduleSave() end end
local function setAutoBuyWeight(s)  if s ~= State.AutoBuyWeight then State.AutoBuyWeight = s; if s then Threads.AutoBuyWeight = task.spawn(autoBuyWeightLoop) end; scheduleSave() end end
local function setAutoSell(s)       if s ~= State.AutoSell      then State.AutoSell      = s; if s then Threads.AutoSell      = task.spawn(autoSellLoop)      end; scheduleSave() end end
local function setAutoEquip(s)      if s ~= State.AutoEquip     then State.AutoEquip     = s; if s then Threads.AutoEquip     = task.spawn(autoEquipBestLoop) end; scheduleSave() end end
local function setAutoUpgrade(s)    if s ~= State.AutoUpgrade   then State.AutoUpgrade   = s; if s then Threads.AutoUpgrade   = task.spawn(autoUpgradeLoop)   end; scheduleSave() end end
local function setAutoRebirth(s)    if s ~= State.AutoRebirth   then State.AutoRebirth   = s; if s then Threads.AutoRebirth   = task.spawn(autoRebirthLoop)   end; scheduleSave() end end

local function setAutoClaim(s)
    if s == State.AutoClaim then return end
    State.AutoClaim = s
    AutoClaimEpoch = AutoClaimEpoch + 1
    if s then
        local myEpoch = AutoClaimEpoch
        Threads.AutoClaim = task.spawn(function() autoClaimLoop(myEpoch) end)
    end
    scheduleSave()
end

----------------------------------------------------------------- BRAINROT PICKER (generic)
local function getHostGui()
    local ok, hui = pcall(function() return gethui() end)
    if ok and hui then return hui end
    return CoreGui
end

local PickerGuis = {}

local function buildOrTogglePicker(key, title, listRef, opts)
    opts = opts or {}
    local mutationMode = opts.mutation == true
    local existing = PickerGuis[key]
    if existing and existing.gui and existing.gui.Parent then
        existing.gui.Enabled = true
        if existing.refresh then existing.refresh() end
        return
    end

    local host = getHostGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "SaberPicker_" .. key
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = host

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(540, 460)
    frame.Position = UDim2.new(0.5, -270, 0.5, -230)
    frame.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    local fs = Instance.new("UIStroke", frame); fs.Color = Color3.fromRGB(60, 70, 100); fs.Thickness = 1

    local titleLbl = Instance.new("TextLabel")
    titleLbl.BackgroundTransparency = 1
    titleLbl.Position = UDim2.fromOffset(16, 10)
    titleLbl.Size = UDim2.fromOffset(420, 24)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 16
    titleLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Text = title
    titleLbl.Parent = frame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(28, 28)
    closeBtn.Position = UDim2.new(1, -36, 0, 8)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 16
    closeBtn.Text = "X"
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
    closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = frame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    local searchBox = Instance.new("TextBox")
    searchBox.Position = UDim2.fromOffset(16, 44)
    searchBox.Size = UDim2.new(1, -32, 0, 30)
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 13
    searchBox.PlaceholderText = "Search by name..."
    searchBox.PlaceholderColor3 = Color3.fromRGB(120, 130, 150)
    searchBox.Text = ""
    searchBox.TextColor3 = Color3.fromRGB(240, 240, 250)
    searchBox.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.BorderSizePixel = 0
    searchBox.Parent = frame
    Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 6)
    local sbPad = Instance.new("UIPadding", searchBox); sbPad.PaddingLeft = UDim.new(0, 10)

    local actionsRow = Instance.new("Frame")
    actionsRow.BackgroundTransparency = 1
    actionsRow.Position = UDim2.fromOffset(16, 84)
    actionsRow.Size = UDim2.new(1, -32, 0, 26)
    actionsRow.Parent = frame
    local actLayout = Instance.new("UIListLayout", actionsRow)
    actLayout.FillDirection = Enum.FillDirection.Horizontal
    actLayout.Padding = UDim.new(0, 8)

    local function makeMiniBtn(text, color, cb)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(150, 26)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.Text = text
        b.BackgroundColor3 = color
        b.TextColor3 = Color3.fromRGB(240, 245, 255)
        b.BorderSizePixel = 0
        b.Parent = actionsRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    local cards = {}
    local rebuild

    makeMiniBtn("Select All", Color3.fromRGB(40, 80, 110), function()
        for name in pairs(EntitiesData.Brainrots or {}) do
            listRef[name] = mutationMode and "Any" or true
        end
        scheduleSave(); if rebuild then rebuild() end
    end)
    makeMiniBtn("Clear All",  Color3.fromRGB(70, 50, 50), function()
        for k in pairs(listRef) do listRef[k] = nil end
        scheduleSave(); if rebuild then rebuild() end
    end)
    local sortBtn = makeMiniBtn("Sort: " .. SORT_NAMES[Cfg.PickerSort or 1], Color3.fromRGB(40, 60, 90), function() end)
    sortBtn.MouseButton1Click:Connect(function()
        Cfg.PickerSort = (Cfg.PickerSort or 1) % #SORT_NAMES + 1
        sortBtn.Text = "Sort: " .. SORT_NAMES[Cfg.PickerSort]
        scheduleSave(); if rebuild then rebuild() end
    end)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(12, 122)
    scroll.Size = UDim2.new(1, -24, 1, -134)
    scroll.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Parent = frame
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)

    local grid = Instance.new("UIGridLayout", scroll)
    grid.CellSize = UDim2.fromOffset(120, 96)
    grid.CellPadding = UDim2.fromOffset(8, 8)
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    Instance.new("UIPadding", scroll).PaddingTop = UDim.new(0, 8)

    local function buildCard(name, info)
        local card = Instance.new("Frame")
        card.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
        card.BorderSizePixel = 0
        card.Parent = scroll
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
        local cs = Instance.new("UIStroke", card); cs.Thickness = 1; cs.Color = Color3.fromRGB(60, 70, 100)

        local img = Instance.new("ImageLabel")
        img.BackgroundTransparency = 1
        img.Position = UDim2.fromOffset(8, 6)
        img.Size = UDim2.fromOffset(60, 60)
        img.Image = info.Image or ""
        img.Parent = card

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.fromOffset(72, 6)
        lbl.Size = UDim2.fromOffset(46, 54)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 10
        lbl.TextColor3 = Color3.fromRGB(220, 225, 235)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Top
        lbl.TextWrapped = true
        lbl.Text = name
        lbl.Parent = card

        local btn = Instance.new("TextButton")
        btn.BackgroundTransparency = 1
        btn.Size = UDim2.fromScale(1, 1)
        btn.Text = ""
        btn.Parent = card

        local chk = Instance.new("Frame")
        chk.Position = UDim2.fromOffset(8, 72)
        chk.Size = UDim2.fromOffset(104, 18)
        chk.BackgroundColor3 = Color3.fromRGB(40, 60, 80)
        chk.BorderSizePixel = 0
        chk.Parent = card
        Instance.new("UICorner", chk).CornerRadius = UDim.new(0, 4)

        local chkLbl = Instance.new("TextLabel")
        chkLbl.BackgroundTransparency = 1
        chkLbl.Size = UDim2.fromScale(1, 1)
        chkLbl.Font = Enum.Font.GothamBold
        chkLbl.TextSize = 11
        chkLbl.Text = "OFF"
        chkLbl.TextColor3 = Color3.fromRGB(220, 225, 235)
        chkLbl.Parent = chk

        local function refresh()
            local v = listRef[name]
            if mutationMode then
                if not v or v == "OFF" then
                    cs.Color = Color3.fromRGB(60, 70, 100)
                    chk.BackgroundColor3 = Color3.fromRGB(40, 60, 80)
                    chkLbl.Text = "OFF"
                    chkLbl.TextColor3 = Color3.fromRGB(180, 190, 210)
                else
                    local col = MUTATION_COLOR[v] or Color3.fromRGB(80, 200, 120)
                    cs.Color = col
                    chk.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.4)
                    chkLbl.Text = tostring(v)
                    chkLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
                end
            else
                if v then
                    cs.Color = Color3.fromRGB(80, 200, 120)
                    chk.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
                    chkLbl.Text = "ON"
                else
                    cs.Color = Color3.fromRGB(60, 70, 100)
                    chk.BackgroundColor3 = Color3.fromRGB(40, 60, 80)
                    chkLbl.Text = "OFF"
                end
            end
        end
        refresh()
        btn.MouseButton1Click:Connect(function()
            if mutationMode then
                local cur = listRef[name] or "OFF"
                local idx = 1
                for i, v in ipairs(MUTATION_CYCLE) do if v == cur then idx = i; break end end
                idx = (idx % #MUTATION_CYCLE) + 1
                local nxt = MUTATION_CYCLE[idx]
                listRef[name] = (nxt == "OFF") and nil or nxt
            else
                listRef[name] = (not listRef[name]) or nil
                if not listRef[name] then listRef[name] = nil end
            end
            refresh()
            scheduleSave()
        end)
        return refresh
    end

    rebuild = function()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        cards = {}
        local q = string.lower(searchBox.Text or "")
        local list = {}
        for n, info in pairs(EntitiesData.Brainrots or {}) do
            if q == "" or string.find(string.lower(n), q, 1, true) then
                table.insert(list, { name = n, info = info })
            end
        end
        local sortIdx = Cfg.PickerSort or 1
        table.sort(list, function(a, b)
            local va = brainrotSortValue(a.name, sortIdx)
            local vb = brainrotSortValue(b.name, sortIdx)
            if va == vb then return a.name < b.name end
            return va > vb
        end)
        for _, e in ipairs(list) do
            cards[e.name] = buildCard(e.name, e.info)
        end
    end

    rebuild()
    searchBox:GetPropertyChangedSignal("Text"):Connect(rebuild)
    closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

    PickerGuis[key] = { gui = gui, refresh = rebuild }
end

----------------------------------------------------------------- STOP PICKER (brainrot list + mutation panel)
local function buildOrToggleStopPicker(key, title, listRef)
    local existing = PickerGuis[key]
    if existing and existing.gui and existing.gui.Parent then
        existing.gui.Enabled = true
        if existing.refresh then existing.refresh() end
        return
    end

    local host = getHostGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "SaberStopPicker_" .. key
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = host

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(720, 480)
    frame.Position = UDim2.new(0.5, -360, 0.5, -240)
    frame.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    local fs = Instance.new("UIStroke", frame); fs.Color = Color3.fromRGB(60, 70, 100); fs.Thickness = 1

    local titleLbl = Instance.new("TextLabel")
    titleLbl.BackgroundTransparency = 1
    titleLbl.Position = UDim2.fromOffset(16, 10)
    titleLbl.Size = UDim2.fromOffset(560, 24)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 16
    titleLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Text = title
    titleLbl.Parent = frame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(28, 28)
    closeBtn.Position = UDim2.new(1, -36, 0, 8)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 16
    closeBtn.Text = "X"
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
    closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = frame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    -- left side: search + sort + scrolling brainrot list
    local LEFT_W = 400
    local searchBox = Instance.new("TextBox")
    searchBox.Position = UDim2.fromOffset(12, 44)
    searchBox.Size = UDim2.fromOffset(LEFT_W - 12, 30)
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextSize = 13
    searchBox.PlaceholderText = "Search by name..."
    searchBox.PlaceholderColor3 = Color3.fromRGB(120, 130, 150)
    searchBox.Text = ""
    searchBox.TextColor3 = Color3.fromRGB(240, 240, 250)
    searchBox.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.BorderSizePixel = 0
    searchBox.Parent = frame
    Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 6)
    local sbPad = Instance.new("UIPadding", searchBox); sbPad.PaddingLeft = UDim.new(0, 10)

    local sortBtn = Instance.new("TextButton")
    sortBtn.Position = UDim2.fromOffset(12, 82)
    sortBtn.Size = UDim2.fromOffset(140, 24)
    sortBtn.Font = Enum.Font.GothamBold
    sortBtn.TextSize = 11
    sortBtn.Text = "Sort: " .. SORT_NAMES[Cfg.PickerSort or 1]
    sortBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 90)
    sortBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
    sortBtn.BorderSizePixel = 0
    sortBtn.Parent = frame
    Instance.new("UICorner", sortBtn).CornerRadius = UDim.new(0, 6)

    local clearBtn = Instance.new("TextButton")
    clearBtn.Position = UDim2.fromOffset(160, 82)
    clearBtn.Size = UDim2.fromOffset(120, 24)
    clearBtn.Font = Enum.Font.GothamBold
    clearBtn.TextSize = 11
    clearBtn.Text = "Clear All"
    clearBtn.BackgroundColor3 = Color3.fromRGB(70, 50, 50)
    clearBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
    clearBtn.BorderSizePixel = 0
    clearBtn.Parent = frame
    Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 6)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(12, 116)
    scroll.Size = UDim2.fromOffset(LEFT_W - 12, 480 - 128)
    scroll.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Parent = frame
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
    local listLayout = Instance.new("UIListLayout", scroll)
    listLayout.Padding = UDim.new(0, 4)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    Instance.new("UIPadding", scroll).PaddingTop = UDim.new(0, 4)

    -- right side: mutation panel
    local right = Instance.new("Frame")
    right.Position = UDim2.fromOffset(LEFT_W + 12, 44)
    right.Size = UDim2.fromOffset(720 - LEFT_W - 24, 480 - 56)
    right.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
    right.BorderSizePixel = 0
    right.Parent = frame
    Instance.new("UICorner", right).CornerRadius = UDim.new(0, 8)

    local rImg = Instance.new("ImageLabel")
    rImg.BackgroundTransparency = 1
    rImg.Position = UDim2.fromOffset(12, 10)
    rImg.Size = UDim2.fromOffset(48, 48)
    rImg.Parent = right

    local rName = Instance.new("TextLabel")
    rName.BackgroundTransparency = 1
    rName.Position = UDim2.fromOffset(68, 10)
    rName.Size = UDim2.fromOffset(220, 48)
    rName.Font = Enum.Font.GothamBold
    rName.TextSize = 14
    rName.TextColor3 = Color3.fromRGB(240, 245, 255)
    rName.TextXAlignment = Enum.TextXAlignment.Left
    rName.TextYAlignment = Enum.TextYAlignment.Center
    rName.TextWrapped = true
    rName.Text = "Pick a brainrot from the list"
    rName.Parent = right

    local rHint = Instance.new("TextLabel")
    rHint.BackgroundTransparency = 1
    rHint.Position = UDim2.fromOffset(12, 64)
    rHint.Size = UDim2.new(1, -24, 0, 16)
    rHint.Font = Enum.Font.Gotham
    rHint.TextSize = 11
    rHint.TextColor3 = Color3.fromRGB(160, 175, 200)
    rHint.TextXAlignment = Enum.TextXAlignment.Left
    rHint.Text = "Tick mutations you want to catch:"
    rHint.Parent = right

    local mutScroll = Instance.new("ScrollingFrame")
    mutScroll.Position = UDim2.fromOffset(12, 86)
    mutScroll.Size = UDim2.new(1, -24, 1, -98)
    mutScroll.BackgroundTransparency = 1
    mutScroll.BorderSizePixel = 0
    mutScroll.ScrollBarThickness = 5
    mutScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    mutScroll.CanvasSize = UDim2.new()
    mutScroll.Parent = right
    local mutLayout = Instance.new("UIListLayout", mutScroll)
    mutLayout.Padding = UDim.new(0, 4)

    local selectedBrainrot = nil
    local cardRefreshers = {}
    local mutCheckboxes = {}

    local function ensureEntry(name)
        if type(StopOnHitWhitelist[name]) ~= "table" then
            StopOnHitWhitelist[name] = {}
        end
        return StopOnHitWhitelist[name]
    end

    local function entryHasAny(name)
        local e = StopOnHitWhitelist[name]
        if type(e) ~= "table" then return false end
        for _ in pairs(e) do return true end
        return false
    end

    local function refreshCardRow(name)
        if cardRefreshers[name] then cardRefreshers[name]() end
    end

    local function renderMutationPanel()
        for _, c in ipairs(mutScroll:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
        mutCheckboxes = {}
        if not selectedBrainrot then
            rImg.Image = ""
            rName.Text = "Pick a brainrot from the list"
            return
        end
        local info = EntitiesData.Brainrots and EntitiesData.Brainrots[selectedBrainrot] or {}
        rImg.Image = info.Image or ""
        rName.Text = selectedBrainrot
        local entry = ensureEntry(selectedBrainrot)

        local options = { "Any", "None", "Golden", "Diamond", "Plasma", "Molten", "Radioactive", "Shadow", "Electrified", "Rainbow", "Void", "Virus" }
        for _, mut in ipairs(options) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -8, 0, 26)
            row.BackgroundColor3 = Color3.fromRGB(28, 34, 50)
            row.BorderSizePixel = 0
            row.Parent = mutScroll
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

            local box = Instance.new("Frame")
            box.Position = UDim2.fromOffset(8, 5)
            box.Size = UDim2.fromOffset(16, 16)
            box.BackgroundColor3 = Color3.fromRGB(50, 60, 80)
            box.BorderSizePixel = 0
            box.Parent = row
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)

            local check = Instance.new("TextLabel")
            check.BackgroundTransparency = 1
            check.Size = UDim2.fromScale(1, 1)
            check.Font = Enum.Font.GothamBold
            check.TextSize = 14
            check.Text = "✓"
            check.TextColor3 = Color3.fromRGB(255, 255, 255)
            check.Visible = entry[mut] == true
            check.Parent = box

            local lbl = Instance.new("TextLabel")
            lbl.BackgroundTransparency = 1
            lbl.Position = UDim2.fromOffset(32, 0)
            lbl.Size = UDim2.new(1, -40, 1, 0)
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 12
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Text = mut
            lbl.TextColor3 = MUTATION_COLOR[mut] or Color3.fromRGB(220, 225, 235)
            lbl.Parent = row

            local btn = Instance.new("TextButton")
            btn.BackgroundTransparency = 1
            btn.Size = UDim2.fromScale(1, 1)
            btn.Text = ""
            btn.Parent = row

            btn.MouseButton1Click:Connect(function()
                local cur = entry[mut] == true
                entry[mut] = not cur or nil
                if not entry[mut] then entry[mut] = nil end
                check.Visible = entry[mut] == true
                box.BackgroundColor3 = entry[mut] and (MUTATION_COLOR[mut] or Color3.fromRGB(80, 200, 120)) or Color3.fromRGB(50, 60, 80)
                if not entryHasAny(selectedBrainrot) then
                    StopOnHitWhitelist[selectedBrainrot] = nil
                end
                refreshCardRow(selectedBrainrot)
                scheduleSave()
            end)

            box.BackgroundColor3 = entry[mut] and (MUTATION_COLOR[mut] or Color3.fromRGB(80, 200, 120)) or Color3.fromRGB(50, 60, 80)
            mutCheckboxes[mut] = { box = box, check = check }
        end
    end

    local function buildBrainrotRow(name, info)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 44)
        row.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
        row.BorderSizePixel = 0
        row.Parent = scroll
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
        local rs = Instance.new("UIStroke", row); rs.Color = Color3.fromRGB(60, 70, 100); rs.Thickness = 1

        local img = Instance.new("ImageLabel")
        img.BackgroundTransparency = 1
        img.Position = UDim2.fromOffset(6, 4)
        img.Size = UDim2.fromOffset(36, 36)
        img.Image = info.Image or ""
        img.Parent = row

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.fromOffset(50, 4)
        lbl.Size = UDim2.new(1, -130, 0, 18)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextColor3 = Color3.fromRGB(230, 235, 245)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = name
        lbl.Parent = row

        local sub = Instance.new("TextLabel")
        sub.BackgroundTransparency = 1
        sub.Position = UDim2.fromOffset(50, 22)
        sub.Size = UDim2.new(1, -130, 0, 16)
        sub.Font = Enum.Font.Gotham
        sub.TextSize = 10
        sub.TextColor3 = Color3.fromRGB(150, 165, 195)
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.Text = (info.Rarity or "—") .. " · " .. tostring(bigToNum(info.CPS) or 0) .. "/s"
        sub.Parent = row

        local status = Instance.new("TextLabel")
        status.BackgroundTransparency = 1
        status.Position = UDim2.new(1, -76, 0, 0)
        status.Size = UDim2.fromOffset(70, 44)
        status.Font = Enum.Font.GothamBold
        status.TextSize = 10
        status.TextXAlignment = Enum.TextXAlignment.Right
        status.Text = ""
        status.Parent = row

        local function refreshRow()
            local entry = StopOnHitWhitelist[name]
            local muts = {}
            if type(entry) == "table" then
                for k in pairs(entry) do table.insert(muts, k) end
            end
            if #muts == 0 then
                status.Text = "—"
                status.TextColor3 = Color3.fromRGB(110, 120, 140)
                rs.Color = Color3.fromRGB(60, 70, 100)
            else
                local first = muts[1]
                status.Text = (#muts == 1) and first or (first .. " +" .. (#muts - 1))
                status.TextColor3 = MUTATION_COLOR[first] or Color3.fromRGB(120, 240, 130)
                rs.Color = MUTATION_COLOR[first] or Color3.fromRGB(80, 200, 120)
            end
            if selectedBrainrot == name then
                row.BackgroundColor3 = Color3.fromRGB(30, 50, 80)
            else
                row.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
            end
        end
        refreshRow()
        cardRefreshers[name] = refreshRow

        local btn = Instance.new("TextButton")
        btn.BackgroundTransparency = 1
        btn.Size = UDim2.fromScale(1, 1)
        btn.Text = ""
        btn.Parent = row
        btn.MouseButton1Click:Connect(function()
            local prev = selectedBrainrot
            selectedBrainrot = name
            -- default to Any mutation match if user hasn't set anything
            local entry = StopOnHitWhitelist[name]
            if type(entry) ~= "table" or next(entry) == nil then
                StopOnHitWhitelist[name] = { Any = true }
                scheduleSave()
            end
            renderMutationPanel()
            if prev and cardRefreshers[prev] then cardRefreshers[prev]() end
            refreshRow()
        end)
        return row
    end

    local function rebuild()
        for _, c in ipairs(scroll:GetChildren()) do
            if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
        end
        cardRefreshers = {}
        local q = string.lower(searchBox.Text or "")
        local list = {}
        for n, info in pairs(EntitiesData.Brainrots or {}) do
            if q == "" or string.find(string.lower(n), q, 1, true) then
                table.insert(list, { name = n, info = info })
            end
        end
        local sortIdx = Cfg.PickerSort or 1
        table.sort(list, function(a, b)
            local va = brainrotSortValue(a.name, sortIdx)
            local vb = brainrotSortValue(b.name, sortIdx)
            if va == vb then return a.name < b.name end
            return va > vb
        end)
        for _, e in ipairs(list) do buildBrainrotRow(e.name, e.info) end
        if selectedBrainrot then renderMutationPanel() end
    end

    sortBtn.MouseButton1Click:Connect(function()
        Cfg.PickerSort = (Cfg.PickerSort or 1) % #SORT_NAMES + 1
        sortBtn.Text = "Sort: " .. SORT_NAMES[Cfg.PickerSort]
        scheduleSave()
        rebuild()
    end)
    clearBtn.MouseButton1Click:Connect(function()
        for k in pairs(StopOnHitWhitelist) do StopOnHitWhitelist[k] = nil end
        scheduleSave()
        rebuild()
        renderMutationPanel()
    end)
    searchBox:GetPropertyChangedSignal("Text"):Connect(rebuild)
    closeBtn.MouseButton1Click:Connect(function() gui.Enabled = false end)

    rebuild()

    PickerGuis[key] = { gui = gui, refresh = rebuild }
end

----------------------------------------------------------------- SLOT PICKER (for Auto Upgrade Custom mode)
local SlotPickerGui

local function buildSlotPicker(slotRef)
    if SlotPickerGui and SlotPickerGui.Parent then
        SlotPickerGui.Enabled = true
        return
    end
    local host = getHostGui()

    SlotPickerGui = Instance.new("ScreenGui")
    SlotPickerGui.Name = "SaberSlotPicker"
    SlotPickerGui.ResetOnSpawn = false
    SlotPickerGui.IgnoreGuiInset = true
    SlotPickerGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    SlotPickerGui.Parent = host

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(360, 420)
    frame.Position = UDim2.new(0.5, -180, 0.5, -210)
    frame.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = SlotPickerGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
    local fs = Instance.new("UIStroke", frame); fs.Color = Color3.fromRGB(60, 70, 100); fs.Thickness = 1

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(16, 10)
    title.Size = UDim2.fromOffset(260, 24)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextColor3 = Color3.fromRGB(240, 240, 250)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "Pick slots to upgrade"
    title.Parent = frame

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(28, 28)
    closeBtn.Position = UDim2.new(1, -36, 0, 8)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 16
    closeBtn.Text = "X"
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
    closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200)
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = frame
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Position = UDim2.fromOffset(12, 44)
    row.Size = UDim2.new(1, -24, 0, 26)
    row.Parent = frame
    local rl = Instance.new("UIListLayout", row)
    rl.FillDirection = Enum.FillDirection.Horizontal
    rl.Padding = UDim.new(0, 6)

    local function makeBtn(text, color, parent)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(110, 26)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.Text = text
        b.BackgroundColor3 = color
        b.TextColor3 = Color3.fromRGB(240, 245, 255)
        b.BorderSizePixel = 0
        b.Parent = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        return b
    end

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(12, 78)
    scroll.Size = UDim2.new(1, -24, 1, -90)
    scroll.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 5
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new()
    scroll.Parent = frame
    Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)

    local grid = Instance.new("UIGridLayout", scroll)
    grid.CellSize = UDim2.fromOffset(64, 38)
    grid.CellPadding = UDim2.fromOffset(6, 6)
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    Instance.new("UIPadding", scroll).PaddingTop = UDim.new(0, 8)

    local cards = {}
    local function rebuild()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        cards = {}
        local plot = ClientPlotService.Model
        local ids = {}
        if plot and plot:FindFirstChild("Slots") then
            for _, s in ipairs(plot.Slots:GetChildren()) do
                local id = tonumber((s.Name:gsub("Slot", "")))
                if id then table.insert(ids, id) end
            end
        end
        if #ids == 0 then
            for i = 1, 16 do table.insert(ids, i) end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local card = Instance.new("Frame")
            card.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
            card.BorderSizePixel = 0
            card.Parent = scroll
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
            local cs = Instance.new("UIStroke", card); cs.Thickness = 1; cs.Color = Color3.fromRGB(60, 70, 100)

            local lbl = Instance.new("TextLabel")
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.fromScale(1, 1)
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 14
            lbl.Text = tostring(id)
            lbl.TextColor3 = Color3.fromRGB(220, 230, 245)
            lbl.Parent = card

            local btn = Instance.new("TextButton")
            btn.BackgroundTransparency = 1
            btn.Size = UDim2.fromScale(1, 1)
            btn.Text = ""
            btn.Parent = card

            local function refresh()
                if slotRef[id] then
                    cs.Color = Color3.fromRGB(80, 200, 120)
                    card.BackgroundColor3 = Color3.fromRGB(40, 110, 60)
                else
                    cs.Color = Color3.fromRGB(60, 70, 100)
                    card.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
                end
            end
            refresh()
            cards[id] = refresh
            btn.MouseButton1Click:Connect(function()
                slotRef[id] = not slotRef[id] or nil
                if not slotRef[id] then slotRef[id] = nil end
                refresh()
                scheduleSave()
            end)
        end
    end

    makeBtn("Select All", Color3.fromRGB(40, 80, 110), row).MouseButton1Click:Connect(function()
        local plot = ClientPlotService.Model
        if plot and plot:FindFirstChild("Slots") then
            for _, s in ipairs(plot.Slots:GetChildren()) do
                local id = tonumber((s.Name:gsub("Slot", "")))
                if id then slotRef[id] = true end
            end
        end
        scheduleSave(); rebuild()
    end)
    makeBtn("Clear", Color3.fromRGB(70, 50, 50), row).MouseButton1Click:Connect(function()
        for k in pairs(slotRef) do slotRef[k] = nil end
        scheduleSave(); rebuild()
    end)

    closeBtn.MouseButton1Click:Connect(function() SlotPickerGui.Enabled = false end)
    rebuild()
end

----------------------------------------------------------------- MINIMIZED ICON
local MinimizedGui
local function buildMinimizedTab()
    if MinimizedGui then return end
    local host = getHostGui()
    MinimizedGui = Instance.new("ScreenGui")
    MinimizedGui.Name = "SaberMinimized"
    MinimizedGui.ResetOnSpawn = false
    MinimizedGui.IgnoreGuiInset = true
    MinimizedGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    MinimizedGui.Enabled = false
    MinimizedGui.Parent = host

    local btn = Instance.new("TextButton")
    btn.AnchorPoint = Vector2.new(0, 0)
    btn.Size = UDim2.fromOffset(60, 60)
    btn.Position = UDim2.fromOffset(40, 40)
    btn.Text = "S"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 26
    btn.BackgroundColor3 = Color3.fromRGB(35, 50, 90)
    btn.TextColor3 = Color3.fromRGB(220, 230, 255)
    btn.BorderSizePixel = 0
    btn.Active = true
    btn.Draggable = true
    btn.AutoButtonColor = true
    btn.Parent = MinimizedGui
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 14)
    local s = Instance.new("UIStroke", btn); s.Color = Color3.fromRGB(80, 110, 180); s.Thickness = 2
    local g = Instance.new("UIGradient", btn)
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.fromRGB(60, 90, 160), Color3.fromRGB(20, 30, 60))

    btn.MouseButton1Click:Connect(function()
        MinimizedGui.Enabled = false
        if UI and UI.ui and UI.ui.screenGui then
            UI.ui.screenGui.Enabled = true
            if UI.ui.blur then UI.ui.blur.Enabled = true end
            if UI.windowHidden then
                pcall(function() UI:_setWindowHidden(false) end)
            end
        end
    end)
end

local function showMinimized()
    buildMinimizedTab()
    MinimizedGui.Enabled = true
    if UI and UI.ui and UI.ui.screenGui then
        UI.ui.screenGui.Enabled = false
        if UI.ui.blur then UI.ui.blur.Enabled = false end
    end
end

----------------------------------------------------------------- LOAD CONFIG (before UI build so defaults match)
loadConfig()

----------------------------------------------------------------- UI BUILD
local function momentaryBtn(name, description, action)
    return {
        Type = "toggle",
        Name = name,
        Description = description,
        Value = false,
        Callback = function(v)
            if not v then return end
            task.spawn(action)
            task.delay(0.05, function()
                if not UI then return end
                for _, tab in ipairs(UI.tabs) do
                    for _, mod in ipairs(tab.Modules) do
                        for _, sec in ipairs(mod.Sections) do
                            for _, ctrl in ipairs(sec.Controls) do
                                if ctrl.Name == name then
                                    UI:_setControlValue(ctrl, false, true)
                                end
                            end
                        end
                    end
                end
            end)
        end,
    }
end

local cb = function(field, fn)
    return function(v)
        Cfg[field] = v
        if fn then fn(v) end
        scheduleSave()
    end
end

UI = SigmatikLibrary:Create({
    Title = "Saber Tsunami",
    ConfigName = "Saved",
    SearchPlaceholder = "Search features...",
    WindowWidth = 960,
    WindowHeight = 540,
    Accent = "#3b82f6",
    AccentSoft = "#60a5fa",
    GuiToggleKey = Enum.KeyCode.K,
    Tabs = {
        {
            Name = "Main", Icon = "combat",
            Modules = {
                {
                    Name = "Auto Play", Enabled = false, Callback = setAutoPlay,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider",  Name = "Kick Power", Min = 0, Max = 1, Increment = 0.1, Value = Cfg.KickPower,
                                    Format = function(v) return string.format("%.1f — %s", v, kickRating(v)) end,
                                    Callback = cb("KickPower") },
                                { Type = "toggle", Name = "Best Save", Value = Cfg.BestSave,
                                    Callback = cb("BestSave") },
                                { Type = "slider", Name = "Best Save trigger X", Min = 0, Max = 690, Increment = 5,
                                    Value = Cfg.BestSaveTriggerX,
                                    Callback = cb("BestSaveTriggerX") },
                                { Type = "toggle", Name = "Fast Play", Value = Cfg.FastPlay,
                                    Callback = setFastPlay },
                                { Type = "slider", Name = "Fast Play kick mult (1=safe)", Min = 1, Max = 30, Increment = 1,
                                    Value = Cfg.FastPlayKickMult,
                                    Callback = function(v) Cfg.FastPlayKickMult = v; if Cfg.FastPlay then applyFastPlay() end; scheduleSave() end },
                                { Type = "slider", Name = "Fast Play safety margin (s)", Min = 0, Max = 5, Increment = 0.1,
                                    Value = Cfg.FastPlaySafeMargin,
                                    Callback = cb("FastPlaySafeMargin") },
                                { Type = "toggle", Name = "Fast Play V2 (match wave speed)", Value = Cfg.FastPlayV2,
                                    Callback = setFastPlayV2 },
                                { Type = "toggle", Name = "Get Only", Value = Cfg.GetOnlyEnabled,
                                    Description = "Dump drops worth less than the value below",
                                    Callback = cb("GetOnlyEnabled") },
                                { Type = "input", Name = "Get Only min value", Min = 0, Max = 48900000,
                                    Value = Cfg.GetOnlyMin, Placeholder = "0 - 48.9M",
                                    Format = function(v) return abbrevNum(v) end,
                                    Callback = cb("GetOnlyMin") },
                                { Type = "slider", Name = "Get Only dump to", Min = 1, Max = 2, Increment = 1,
                                    Value = Cfg.GetOnlyMode,
                                    Format = function(v) return ({ "Tsunami", "Safe Zone" })[math.floor(v)] or "Tsunami" end,
                                    Callback = cb("GetOnlyMode") },
                            },
                        },
                        {
                            Name = "Stop on Got Brainrot",
                            Controls = {
                                momentaryBtn("Choose brainrots to stop at", "Open list", function()
                                    buildOrToggleStopPicker("stop", "Stop Auto Play on these brainrots & mutations", StopOnHitWhitelist)
                                end),
                            },
                        },
                        {
                            Name = "Telegram Notify",
                            Controls = {
                                { Type = "toggle", Name = "Telegram Notify", Value = Cfg.TgEnabled,
                                    Description = "Message me on every successful catch (above the Get Only value)",
                                    Callback = cb("TgEnabled") },
                                { Type = "input", Name = "Connect Key", Value = Cfg.ConnectKey, Text = true,
                                    Placeholder = "open @cheat_speed_amongus1bot → /start",
                                    Callback = cb("ConnectKey") },
                                momentaryBtn("Send Test Catch", "Send a test notification to your Telegram", function()
                                    if not Cfg.ConnectKey or Cfg.ConnectKey == "" then
                                        print("[Saber] Set your Connect Key first (open the bot → /start)")
                                        return
                                    end
                                    backendPost("/catch", {
                                        key = Cfg.ConnectKey, name = "Noobini Pizzanini",
                                        rarity = "Common", value = 2, mutation = "Golden",
                                    })
                                    print("[Saber] Test catch sent — check your Telegram & Mini App")
                                end),
                            },
                        },
                    },
                },
                {
                    Name = "Auto Farm Weight", Enabled = false, Callback = setAutoWeight,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "toggle", Name = "Auto Popup", Value = Cfg.AutoPopupEnabled,
                                    Callback = cb("AutoPopupEnabled") },
                            },
                        },
                    },
                },
                {
                    Name = "Auto Equip Best Brainrot", Enabled = false, Callback = setAutoEquip,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider", Name = "Sort by", Min = 1, Max = 3, Increment = 1,
                                    Value = Cfg.AutoEquipSort or 1,
                                    Format = function(v) return SORT_NAMES[math.floor(v)] or "Rarity" end,
                                    Callback = cb("AutoEquipSort") },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Buy & Sell", Icon = "movement",
            Modules = {
                {
                    Name = "Auto Claim Cash", Enabled = false, Callback = setAutoClaim,
                    Sections = {
                        { Name = "Settings", Controls = {} },
                    },
                },
                {
                    Name = "Auto Buy Speed", Enabled = false, Callback = setAutoBuySpeed,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider", Name = "Speed amount per buy", Min = 1, Max = 100, Increment = 1, Value = Cfg.AutoSpeedAmount,
                                    Callback = cb("AutoSpeedAmount") },
                                { Type = "slider", Name = "How often (sec)", Min = 0.05, Max = 2, Increment = 0.05, Value = Cfg.AutoSpeedInterval,
                                    Callback = cb("AutoSpeedInterval") },
                            },
                        },
                    },
                },
                {
                    Name = "Auto Upgrade Brainrots", Enabled = false, Callback = setAutoUpgrade,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider", Name = "Mode", Min = 1, Max = 4, Increment = 1,
                                    Value = Cfg.AutoUpgradeMode or 1,
                                    Format = function(v) return UPGRADE_MODE_NAMES[math.floor(v)] or "All" end,
                                    Callback = cb("AutoUpgradeMode") },
                                momentaryBtn("Pick custom slots", "Open slot picker", function()
                                    buildSlotPicker(UpgradeSlotWhitelist)
                                end),
                            },
                        },
                    },
                },
                {
                    Name = "Auto Rebirth", Enabled = false, Callback = setAutoRebirth,
                    Sections = { { Name = "Settings", Controls = {} } },
                },
                {
                    Name = "Auto Buy Weight", Enabled = false, Callback = setAutoBuyWeight,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider", Name = "How often (sec)", Min = 0.5, Max = 10, Increment = 0.5, Value = Cfg.AutoBuyWeightInterval,
                                    Callback = cb("AutoBuyWeightInterval") },
                                { Type = "toggle", Name = "Equip after buying", Value = Cfg.AutoBuyWeightEquipAfter,
                                    Callback = cb("AutoBuyWeightEquipAfter") },
                            },
                        },
                    },
                },
                {
                    Name = "Auto Sell Brainrots", Enabled = false, Callback = setAutoSell,
                    Sections = {
                        {
                            Name = "Quick Buttons",
                            Controls = {
                                momentaryBtn("Sell what's in my hand", "Sells one held brainrot", sellHeldNow),
                                momentaryBtn("Sell ALL my brainrots",  "Sells everything in inventory", sellAllNow),
                                momentaryBtn("Choose brainrots to auto-sell", "Open list", function()
                                    buildOrTogglePicker("sell", "Brainrots to Auto-Sell", SellWhitelist)
                                end),
                            },
                        },
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider", Name = "How often (sec)", Min = 0.1, Max = 5, Increment = 0.1, Value = Cfg.AutoSellInterval,
                                    Callback = cb("AutoSellInterval") },
                            },
                        },
                    },
                },
            },
        },
        {
            Name = "Player", Icon = "movement",
            Modules = {
                {
                    Name = "Fly", Enabled = false, Callback = setFly,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider", Name = "Fly speed", Min = 10, Max = 300, Increment = 5,
                                    Value = Cfg.FlySpeed,
                                    Callback = cb("FlySpeed") },
                                { Type = "label", Name = "Controls",
                                    Content = "WASD = move, Space = up, Ctrl = down" },
                            },
                        },
                    },
                },
                {
                    Name = "Noclip", Enabled = false, Callback = setNoclip,
                    Sections = { { Name = "Settings", Controls = {} } },
                },
                {
                    Name = "Fast Walk", Enabled = false, Callback = setFastWalk,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider", Name = "Walk speed", Min = 16, Max = 250, Increment = 2,
                                    Value = Cfg.WalkSpeed,
                                    Callback = function(v) Cfg.WalkSpeed = v; if State.FastWalk then applyWalkSpeed() end; scheduleSave() end },
                            },
                        },
                    },
                },
                {
                    Name = "High Jump", Enabled = false, Callback = setHighJump,
                    Sections = {
                        {
                            Name = "Settings",
                            Controls = {
                                { Type = "slider", Name = "Jump power", Min = 50, Max = 500, Increment = 10,
                                    Value = Cfg.JumpPower,
                                    Callback = function(v) Cfg.JumpPower = v; if State.HighJump then applyJumpPower() end; scheduleSave() end },
                            },
                        },
                    },
                },
                {
                    Name = "Teleport to Player", Enabled = false,
                    Callback = function(v)
                        if v then
                            buildTPPicker()
                            task.delay(0.1, function()
                                if UI then UI:SetModuleEnabled("Player", "Teleport to Player", false) end
                            end)
                        end
                    end,
                    Sections = { { Name = "Settings", Controls = {} } },
                },
                {
                    Name = "Full Bright", Enabled = false, Callback = setFullBright,
                    Sections = { { Name = "Settings", Controls = {} } },
                },
                {
                    Name = "No Fog", Enabled = false, Callback = setNoFog,
                    Sections = { { Name = "Settings", Controls = {} } },
                },
            },
        },
        {
            Name = "Misc", Icon = "settings",
            Modules = {
                {
                    Name = "Anti AFK", Enabled = false, Callback = setAntiAFK,
                    Sections = { { Name = "Settings", Controls = {} } },
                },
                {
                    Name = "Show Earnings", Enabled = false, Callback = setShowEarnings,
                    Sections = { { Name = "Settings", Controls = {} } },
                },
            },
        },
    },
})

-- Hijack close: minimize instead of destroy
UI._close = function(self)
    showMinimized()
end

-- Apply saved module enabled states
do
    local saved = (function()
        local raw = safeRead(CONFIG_PATH)
        if not raw then return nil end
        local ok, payload = pcall(function() return HttpService:JSONDecode(raw) end)
        return ok and type(payload) == "table" and payload or nil
    end)()
    if saved and type(saved.Modules) == "table" then
        local m = saved.Modules
        local apply = function(tab, mod, key)
            if m[key] ~= nil then UI:SetModuleEnabled(tab, mod, m[key] == true) end
        end
        apply("Main",       "Auto Play",                 "AutoPlay")
        apply("Main",       "Auto Farm Weight",          "AutoWeight")
        apply("Main",       "Auto Equip Best Brainrot",  "AutoEquip")
        apply("Buy & Sell", "Auto Claim Cash",           "AutoClaim")
        apply("Buy & Sell", "Auto Buy Speed",            "AutoBuySpeed")
        apply("Buy & Sell", "Auto Buy Weight",           "AutoBuyWeight")
        apply("Buy & Sell", "Auto Upgrade Brainrots",    "AutoUpgrade")
        apply("Buy & Sell", "Auto Rebirth",              "AutoRebirth")
        apply("Buy & Sell", "Auto Sell Brainrots",       "AutoSell")
        apply("Misc",       "Show Earnings",             "ShowEarnings")
        apply("Misc",       "Anti AFK",                  "AntiAFK")
        apply("Player",     "Fly",                       "Fly")
        apply("Player",     "Noclip",                    "Noclip")
        apply("Player",     "Fast Walk",                 "FastWalk")
        apply("Player",     "High Jump",                 "HighJump")
        apply("Player",     "Full Bright",               "FullBright")
        apply("Player",     "No Fog",                    "NoFog")
    end
end


print("[SaberAutoSuite] loaded — press K to toggle, X to minimize")
