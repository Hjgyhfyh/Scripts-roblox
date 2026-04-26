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

local function parseHex(hex)
	if type(hex) ~= "string" then
		return Color3.fromRGB(255, 255, 255), 0
	end
	local clean = (hex or "#ffffffff"):gsub("#", "")
	if #clean == 6 then
		clean = clean .. "ff"
	end

	local r = tonumber(clean:sub(1, 2), 16) or 255
	local g = tonumber(clean:sub(3, 4), 16) or 255
	local b = tonumber(clean:sub(5, 6), 16) or 255
	local a = tonumber(clean:sub(7, 8), 16) or 255

	return Color3.fromRGB(r, g, b), 1 - (a / 255)
end

local function colorToHex(color, alpha)
	local a = alpha or 1
	return string.format("#%02x%02x%02x%02x", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255), math.floor(math.clamp(a, 0, 1) * 255))
end

local function hueToHex(hue, alpha)
	return colorToHex(Color3.fromHSV(hue, 0.72, 1), alpha)
end

local function hexToHue(hex)
	local color = select(1, parseHex(hex))
	local hue, sat = color:ToHSV()
	if sat < 0.05 then
		return 0, sat
	end
	return hue, sat
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
	if maximum < minimum then
		maximum = minimum
	end
	local clamped = math.clamp(value, minimum, maximum)
	local step = increment and increment > 0 and increment or 1
	local rounded = minimum + roundNearest((clamped - minimum) / step) * step
	return math.clamp(rounded, minimum, maximum)
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
	animateScale(scaleObject, peakScale, POP_TWEEN)
	task.delay(0.08, function()
		if scaleObject.Parent then
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

local function normalizeControl(control)
	local kind = string.lower(control.Type or "toggle")
	local normalized = shallowCopy(control)
	normalized.Type = kind
	normalized.Name = control.Name or "Option"
	normalized.Description = control.Description
	normalized.Callback = control.Callback

	if kind == "slider" then
		normalized.Min = control.Min or 0
		normalized.Max = control.Max or 100
		normalized.Increment = control.Increment or 1
		if normalized.Increment <= 0 then
			normalized.Increment = 1
		end
		if normalized.Max < normalized.Min then
			normalized.Max = normalized.Min
		end
		normalized.Value = clampRound(control.Value or control.CurrentValue or normalized.Min, normalized.Min, normalized.Max, normalized.Increment)
		normalized.CurrentValue = normalized.Value
	elseif kind == "colorpicker" then
		normalized.Palette = arrayCopy(control.Palette or DEFAULT_PALETTE)
		normalized.Value = tostring(control.Value or control.CurrentValue or normalized.Palette[1])
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
	tween(label, FADE_TWEEN, { TextTransparency = 1 })
	task.delay(0.06, function()
		if self.closing then return end
		if not label.Parent or serial ~= self.configLabelSerial then
			return
		end

		label.Text = text
		tween(label, FADE_TWEEN, { TextTransparency = getFillTransparency("#ffffff80") })
	end)
	task.delay(1.2, function()
		if self.closing then return end
		if not label.Parent or serial ~= self.configLabelSerial then
			return
		end

		tween(label, FADE_TWEEN, { TextTransparency = 1 })
		task.delay(0.06, function()
			if self.closing then return end
			if label.Parent and serial == self.configLabelSerial then
				label.Text = self.config.ConfigName
				tween(label, FADE_TWEEN, { TextTransparency = getFillTransparency("#ffffff80") })
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
	if self.settingsVisible then
		self.settingsVisible = false
		self:_updateModulePanelLayout()
	end
	self:_refreshCategoryTabs()
	self:_renderModuleRows(true)
	self:_renderSettingsPanel()
end

function Controller:_setSelectedModule(module, openSettings)
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
	if control.Type == "slider" then
		control.Value = clampRound(value, control.Min, control.Max, control.Increment)
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

	table.insert(self.connections, button.MouseEnter:Connect(function()
		control:applyVisual("hover")
	end))
	table.insert(self.connections, button.MouseLeave:Connect(function()
		control:applyVisual("default")
	end))
	table.insert(self.connections, button.MouseButton1Down:Connect(function()
		control:applyVisual("pressed")
	end))
	table.insert(self.connections, button.MouseButton1Up:Connect(function()
		if button.Parent then
			control:applyVisual("hover")
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
	}

	function control:setState(enabled, instant)
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
			if self.thumbScale.Parent then
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

	table.insert(self.transientConnections, rowButton.MouseEnter:Connect(function()
		hovered = true
		refreshVisual(true)
	end))
	table.insert(self.transientConnections, rowButton.MouseLeave:Connect(function()
		hovered = false
		refreshVisual(true)
	end))
	table.insert(self.transientConnections, rowButton.MouseButton1Click:Connect(function()
		self.selectedModule = module
		self:_renderModuleRows(false)
		self:_renderSettingsPanel()
		pulse(rowScale, 1.02)
	end))

	table.insert(self.transientConnections, settingsButton.MouseEnter:Connect(function()
		settingsHovered = true
		refreshVisual(true)
	end))
	table.insert(self.transientConnections, settingsButton.MouseLeave:Connect(function()
		settingsHovered = false
		refreshVisual(true)
	end))
	table.insert(self.transientConnections, settingsButton.MouseButton1Click:Connect(function()
		if self.selectedModule == module and self.settingsVisible then
			self.settingsVisible = false
		else
			self.selectedModule = module
			self.settingsVisible = true
		end

		self:_updateModulePanelLayout()
		self:_renderModuleRows(false)
		self:_renderSettingsPanel()
		pulse(settingsScale, 1.12)
	end))

	table.insert(self.transientConnections, toggle.button.MouseButton1Click:Connect(function()
		self.selectedModule = module
		self:_setModuleEnabled(module, not module.Enabled, false)
		self:_setConfigLabel(module.Enabled and "Module Enabled" or "Module Disabled")
	end))
end

function Controller:_renderModuleRows(animateEntrance)
	if self.transientConnections then
		for _, conn in ipairs(self.transientConnections) do
			pcall(function() conn:Disconnect() end)
		end
		self.transientConnections = {}
	else
		self.transientConnections = {}
	end

	clearChildren(self.ui.moduleContainer)

	if not self.selectedTab then
		return
	end

	local query = string.lower(self.ui.searchInput.Text)
	local visibleIndex = 0
	local visibleModules = {}

	for _, module in ipairs(self.selectedTab.Modules) do
		if query == "" or string.find(string.lower(module.Name), query, 1, true) then
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
	table.insert(self.transientConnections, switch.button.MouseButton1Click:Connect(function()
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

	table.insert(self.transientConnections, switch.button.MouseButton1Click:Connect(function()
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

	table.insert(self.transientConnections, checkbox.button.MouseButton1Click:Connect(function()
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
		valueLabel.Text = formatSliderValue(control.Value, control.Increment)

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

	table.insert(self.transientConnections, hitbox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.draggingSlider = {
				update = function(pointerX)
					updateFromPointer(pointerX, true)
				end,
				finish = function()
					refresh(false)
					fireCallback(control.Callback, control.Value)
				end,
			}
			animateScale(trackScale, 1.03, FAST_TWEEN)
			animateScale(knobScale, 1.12, FAST_TWEEN)
			animateScale(knobGlowScale, 1.2, FAST_TWEEN)
			updateFromPointer(input.Position.X, true)
		end
	end))

	table.insert(self.transientConnections, hitbox.MouseEnter:Connect(function()
		hovered = true
		animateScale(trackScale, self.draggingSlider and 1.03 or 1.02, FAST_TWEEN)
		animateScale(knobScale, 1.08, FAST_TWEEN)
		animateScale(knobGlowScale, 1.14, FAST_TWEEN)
	end))

	table.insert(self.transientConnections, hitbox.MouseLeave:Connect(function()
		hovered = false
		if self.draggingSlider then
			return
		end

		animateScale(trackScale, 1, SOFT_TWEEN)
		animateScale(knobScale, 1, SOFT_TWEEN)
		animateScale(knobGlowScale, 1, SOFT_TWEEN)
	end))

	table.insert(self.sliderResetters, function()
		animateScale(trackScale, hovered and 1.02 or 1, SOFT_TWEEN)
		animateScale(knobScale, hovered and 1.08 or 1, SOFT_TWEEN)
		animateScale(knobGlowScale, hovered and 1.12 or 1, SOFT_TWEEN)
	end)
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
		local hue, sat = hexToHue(control.Value)
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
			applyFill(knobGlow, accent:sub(1, 7) .. "38")
			applyStroke(trackStroke, accent:sub(1, 7) .. "28")
			return
		end

		animateFill(preview, accent, FAST_TWEEN)
		animateStroke(previewStroke, "#ffffff60", FAST_TWEEN)
		if moveKnob then
			animatePosition(knob, UDim2.fromOffset(offset, 6), FAST_TWEEN)
			animatePosition(knobGlow, UDim2.fromOffset(offset, 6), FAST_TWEEN)
		end
		animateFill(knobGlow, accent:sub(1, 7) .. "38", FAST_TWEEN)
		animateStroke(trackStroke, accent:sub(1, 7) .. "28", FAST_TWEEN)
	end

	local function updateFromPointer(pointerX, instant)
		local relative = math.clamp((pointerX - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local _, currentAlpha = parseHex(control.Value)
		local alpha = 1 - currentAlpha
		control._lastHue = relative
		control.Value = hueToHex(relative, alpha)
		control.CurrentValue = control.Value
		refresh(instant)
	end

	control._refresh = refresh
	refresh(true)

	table.insert(self.transientConnections, hitbox.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.draggingSlider = {
				update = function(pointerX)
					updateFromPointer(pointerX, true)
				end,
				finish = function()
					refresh(false)
					fireCallback(control.Callback, control.Value)
				end,
			}
			animateScale(knobScale, 1.12, FAST_TWEEN)
			animateScale(knobGlowScale, 1.2, FAST_TWEEN)
			updateFromPointer(input.Position.X, true)
		end
	end))

	table.insert(self.transientConnections, hitbox.MouseEnter:Connect(function()
		hovered = true
		animateScale(knobScale, 1.08, FAST_TWEEN)
		animateScale(knobGlowScale, 1.16, FAST_TWEEN)
	end))

	table.insert(self.transientConnections, hitbox.MouseLeave:Connect(function()
		hovered = false
		if self.draggingSlider then
			return
		end
		animateScale(knobScale, 1, SOFT_TWEEN)
		animateScale(knobGlowScale, 1, SOFT_TWEEN)
	end))

	table.insert(self.sliderResetters, function()
		animateScale(knobScale, hovered and 1.08 or 1, SOFT_TWEEN)
		animateScale(knobGlowScale, hovered and 1.16 or 1, SOFT_TWEEN)
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
	elseif control.Type == "colorpicker" then
		self:_createColorPickerRow(parent, control)
	elseif control.Type == "paragraph" then
		self:_createParagraphRow(parent, control)
	elseif control.Type == "label" then
		self:_createLabelRow(parent, control)
	end
end

function Controller:_renderSettingsPanel()
	if self.transientConnections then
		for _, conn in ipairs(self.transientConnections) do
			pcall(function() conn:Disconnect() end)
		end
		self.transientConnections = {}
	else
		self.transientConnections = {}
	end
	clearChildren(self.ui.settingsContent)
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
		Size = UDim2.fromOffset(280, 56),
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
		Size = UDim2.fromOffset(86, 18),
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
		Text = "Right Shift",
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
		self:_renderModuleRows(true)
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
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.draggingWindow = true
			self.dragStart = input.Position
			self.startPosition = mainWindow.Position
		end
	end))

	table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
		if self.closing then return end
		if self.draggingWindow and input.UserInputType == Enum.UserInputType.MouseMovement then
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

		if self.draggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
			self.draggingSlider.update(input.Position.X)
		end
	end))

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if self.closing then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if self.waitingForBind and input.KeyCode ~= Enum.KeyCode.Unknown then
			if gameProcessed then
				return
			end
			self.waitingForBind = false
			self.uiToggleKey = input.KeyCode
			self:_refreshBindVisual()
			self:_setConfigLabel("GUI Key Updated")
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
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self.draggingSlider then
				self.draggingSlider.finish()
				self.draggingSlider = nil
			end

			for _, resetter in ipairs(self.sliderResetters) do
				resetter()
			end

			self.draggingWindow = false
		end
	end))

	table.insert(self.connections, UserInputService.WindowFocusReleased:Connect(function()
		self.draggingWindow = false
		self.draggingSlider = nil
	end))

	table.insert(self.connections, screenGui.AncestryChanged:Connect(function(_, parent)
		if parent == nil and blur.Parent then
			blur:Destroy()
		end
	end))

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
