-- Sigmatik UI Library v2
-- Полностью переработанная версия. Реализует:
--   1. ConnectionTracker + TweenManager (нет утечек)
--   2. Builder API (chained) + Component Registry
--   3. Тема с токенами + runtime SetTheme + пресеты Dark/Light/AMOLED
--   4. Компоненты: Button, Toggle, Slider, Dropdown, MultiDropdown, Textbox,
--      Keybind, ColorPicker(HSV+alpha), Label, Paragraph
--   5. Notifications/Toast + Tooltip + disabled/loading
--   6. Touch + keyboard nav + drag clamp/resize/snap
--   7. Config save/load (writefile + JSON), KeybindManager, Watermark/FPS,
--      Command Palette (Ctrl+K)
--   8. Дебаунс поиска, диффинг рендера, реальный Destroy
--   9. Обратная совместимость с декларативным Library:Create({Tabs=...})

local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Stats = game:FindService("Stats")

local LocalPlayer = Players.LocalPlayer

local GUI_NAME_BASE = "SigmatikUI"
local CHECK_ICON = utf8.char(0x2713)
local WHITE = "#ffffffff"

local FAST = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SOFT = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local PANEL = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

----------------------------------------------------------------
-- Утилиты
----------------------------------------------------------------

local function shallowCopy(t)
	local r = {}
	for k, v in pairs(t or {}) do r[k] = v end
	return r
end

local function arrayCopy(t)
	local r = {}
	for i, v in ipairs(t or {}) do r[i] = v end
	return r
end

local hexCache = {}
local function parseHex(hex)
	hex = hex or "#ffffffff"
	local cached = hexCache[hex]
	if cached then return cached[1], cached[2] end
	local clean = hex:gsub("#", "")
	if #clean == 3 then
		clean = clean:sub(1,1):rep(2) .. clean:sub(2,2):rep(2) .. clean:sub(3,3):rep(2) .. "ff"
	elseif #clean == 6 then
		clean = clean .. "ff"
	end
	local r = tonumber(clean:sub(1, 2), 16) or 255
	local g = tonumber(clean:sub(3, 4), 16) or 255
	local b = tonumber(clean:sub(5, 6), 16) or 255
	local a = tonumber(clean:sub(7, 8), 16) or 255
	local color = Color3.fromRGB(r, g, b)
	local trans = 1 - (a / 255)
	hexCache[hex] = { color, trans }
	return color, trans
end

local function colorToHex(c, alpha)
	alpha = alpha or 1
	return string.format("#%02x%02x%02x%02x",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5),
		math.floor(alpha * 255 + 0.5))
end

local function mix(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function clampRound(v, mn, mx, inc)
	v = math.clamp(v, mn, mx)
	local step = inc and inc > 0 and inc or 1
	return math.clamp(mn + math.floor(((v - mn) / step) + 0.5) * step, mn, mx)
end

local function fontFor(weight)
	if weight >= 700 then return Enum.Font.GothamBold end
	if weight >= 500 then return Enum.Font.GothamMedium end
	return Enum.Font.Gotham
end

local function create(class, props)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do i[k] = v end
	return i
end

local function addCorner(p, r) return create("UICorner", { CornerRadius = UDim.new(0, r), Parent = p }) end

local function addStroke(p, thickness, hex)
	local s = create("UIStroke", {
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = p,
	})
	local c, tr = parseHex(hex or "#ffffff20")
	s.Color = c
	s.Transparency = tr
	return s
end

local function addPadding(p, l, r, t, b)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r),
		PaddingTop = UDim.new(0, t),
		PaddingBottom = UDim.new(0, b),
		Parent = p,
	})
end

local function addList(p, dir, padding)
	return create("UIListLayout", {
		FillDirection = dir,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = p,
	})
end

local function applyFill(g, hex)
	local c, tr = parseHex(hex)
	g.BackgroundColor3 = c
	g.BackgroundTransparency = tr
end

local function applyText(t, hex)
	local c, tr = parseHex(hex)
	t.TextColor3 = c
	t.TextTransparency = tr
end

local function applyStroke(s, hex)
	local c, tr = parseHex(hex)
	s.Color = c
	s.Transparency = tr
end

local function pcallSafe(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Sigmatik] callback error:", err)
	end
end

local function safeFire(cb, ...)
	if type(cb) == "function" then
		local args = { ... }
		task.spawn(function() pcallSafe(cb, table.unpack(args)) end)
	end
end

local function keyName(key)
	if not key or key == Enum.KeyCode.Unknown then return "None" end
	local n = key.Name
	n = n:gsub("Left", "L")
	n = n:gsub("Right", "R")
	return n
end

----------------------------------------------------------------
-- ConnectionTracker / TweenManager
----------------------------------------------------------------

local function newConnectionTracker()
	local t = { _conns = {}, _alive = true }
	function t:add(conn)
		if not self._alive then conn:Disconnect() return conn end
		table.insert(self._conns, conn)
		return conn
	end
	function t:connect(signal, fn)
		return self:add(signal:Connect(fn))
	end
	function t:disconnectAll()
		self._alive = false
		for _, c in ipairs(self._conns) do
			pcall(function() c:Disconnect() end)
		end
		self._conns = {}
	end
	return t
end

local function newTweenManager()
	local m = { _active = setmetatable({}, { __mode = "k" }) }
	function m:tween(obj, info, props)
		if not obj or not obj.Parent then return end
		local key = self._active[obj]
		if key then
			for prop in pairs(props) do
				local existing = key[prop]
				if existing then pcall(function() existing:Cancel() end) end
				key[prop] = nil
			end
		else
			key = {}
			self._active[obj] = key
		end
		local tw = TweenService:Create(obj, info, props)
		for prop in pairs(props) do key[prop] = tw end
		tw.Completed:Connect(function()
			for prop in pairs(props) do
				if key[prop] == tw then key[prop] = nil end
			end
		end)
		tw:Play()
		return tw
	end
	function m:cancelAll(obj)
		local key = self._active[obj]
		if not key then return end
		for prop, tw in pairs(key) do pcall(function() tw:Cancel() end) end
		self._active[obj] = nil
	end
	return m
end

----------------------------------------------------------------
-- Темы (токены)
----------------------------------------------------------------

local function makeTheme(preset, accent)
	local p = preset or "Dark"
	local a = accent or "#3b82f6"
	local themes = {
		Dark = {
			Accent = a,
			AccentSoft = "#60a5fa",
			Surface = "#0b1020e6",
			SurfaceAlt = "#11182780",
			Elevated = "#ffffff08",
			ElevatedHover = "#ffffff14",
			Border = "#ffffff1a",
			BorderStrong = "#ffffff2a",
			TextPrimary = "#ffffffff",
			TextSecondary = "#ffffffcc",
			TextMuted = "#ffffff99",
			TextDim = "#ffffff60",
			Success = "#22c55e",
			Warning = "#f59e0b",
			Danger = "#ef4444",
			Info = "#3b82f6",
			Dim = "#02061799",
			BlurSize = 14,
			Disabled = 0.45,
		},
		Light = {
			Accent = a,
			AccentSoft = "#3b82f6",
			Surface = "#f8fafce6",
			SurfaceAlt = "#e2e8f0a0",
			Elevated = "#0f172a0d",
			ElevatedHover = "#0f172a18",
			Border = "#0f172a22",
			BorderStrong = "#0f172a40",
			TextPrimary = "#0f172aff",
			TextSecondary = "#1e293bcc",
			TextMuted = "#475569cc",
			TextDim = "#64748b99",
			Success = "#16a34a",
			Warning = "#d97706",
			Danger = "#dc2626",
			Info = "#2563eb",
			Dim = "#cbd5e1aa",
			BlurSize = 8,
			Disabled = 0.45,
		},
		AMOLED = {
			Accent = a,
			AccentSoft = "#60a5fa",
			Surface = "#000000f0",
			SurfaceAlt = "#0a0a0a",
			Elevated = "#ffffff06",
			ElevatedHover = "#ffffff10",
			Border = "#ffffff14",
			BorderStrong = "#ffffff24",
			TextPrimary = "#ffffffff",
			TextSecondary = "#ffffffc0",
			TextMuted = "#ffffff80",
			TextDim = "#ffffff50",
			Success = "#22c55e",
			Warning = "#f59e0b",
			Danger = "#ef4444",
			Info = "#3b82f6",
			Dim = "#000000cc",
			BlurSize = 18,
			Disabled = 0.4,
		},
	}
	local t = themes[p] or themes.Dark
	t.Preset = p
	return shallowCopy(t)
end

----------------------------------------------------------------
-- Component Registry
----------------------------------------------------------------

local Library = {}
Library._components = {}

function Library:RegisterComponent(name, builder)
	self._components[string.lower(name)] = builder
end

----------------------------------------------------------------
-- Workspace: служебные классы
----------------------------------------------------------------

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

----------------------------------------------------------------
-- Создание скелета окна
----------------------------------------------------------------

local function getParentGui()
	if gethui then return gethui() end
	if syn and syn.protect_gui then
		local sg = Instance.new("ScreenGui")
		syn.protect_gui(sg)
		sg.Parent = CoreGui
		return sg.Parent
	end
	return CoreGui
end

local function buildSkeleton(self)
	local cfg = self.config
	local theme = self.theme

	local guiName = GUI_NAME_BASE .. "_" .. tostring(math.random(100000, 999999))
	self.guiName = guiName

	local existingBlur = Lighting:FindFirstChild(guiName .. "Blur")
	if existingBlur then existingBlur:Destroy() end

	local screenGui = create("ScreenGui", {
		Name = guiName,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
		Parent = getParentGui(),
	})
	pcall(function() screenGui.Parent = getParentGui() end)
	self.screenGui = screenGui

	local dim = create("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = screenGui,
	})
	applyFill(dim, theme.Dim)
	dim.Visible = false
	self.dim = dim

	local blur = create("BlurEffect", {
		Name = guiName .. "Blur",
		Size = 0,
		Parent = Lighting,
	})
	self.blur = blur

	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(cfg.WindowWidth, cfg.WindowHeight),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = screenGui,
	})
	applyFill(window, theme.Surface)
	addCorner(window, 14)
	local windowStroke = addStroke(window, 1, theme.Border)
	self.window = window
	self.windowStroke = windowStroke

	local windowScale = create("UIScale", { Scale = 0.96, Parent = window })
	self.windowScale = windowScale

	-- Header
	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 48),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = window,
	})
	applyFill(header, theme.Elevated)
	addCorner(header, 14)
	local headerStroke = addStroke(header, 1, theme.Border)
	self.header = header
	self.headerStroke = headerStroke

	-- Header bottom mask (only top corners rounded)
	local headerMask = create("Frame", {
		Name = "HeaderMask",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 24),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = header,
	})
	applyFill(headerMask, theme.Elevated)

	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.fromOffset(280, 48),
		Font = fontFor(700),
		Text = cfg.Title or "Sigmatik",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = header,
	})
	applyText(title, theme.TextPrimary)
	self.title = title

	local subtitle = create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 28),
		Size = UDim2.fromOffset(280, 16),
		Font = fontFor(500),
		Text = cfg.Subtitle or "",
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = header,
	})
	applyText(subtitle, theme.TextMuted)
	subtitle.Visible = subtitle.Text ~= ""
	self.subtitle = subtitle

	-- Кнопки управления окном (right side)
	local controls = create("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(120, 32),
		ZIndex = 5,
		Parent = header,
	})
	local controlsLayout = addList(controls, Enum.FillDirection.Horizontal, 6)
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	local function makeIconButton(symbol, color, callback)
		local btn = create("TextButton", {
			Name = symbol .. "Btn",
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(28, 28),
			AutoButtonColor = false,
			Font = fontFor(700),
			Text = symbol,
			TextSize = 14,
			ZIndex = 6,
			Parent = controls,
		})
		applyFill(btn, theme.Elevated)
		applyText(btn, theme.TextSecondary)
		addCorner(btn, 6)
		local bs = addStroke(btn, 1, theme.Border)
		self.connTracker:connect(btn.MouseEnter, function()
			self.tweens:tween(btn, FAST, { BackgroundColor3 = select(1, parseHex(theme.ElevatedHover)), BackgroundTransparency = select(2, parseHex(theme.ElevatedHover)) })
			if color then self.tweens:tween(btn, FAST, { TextColor3 = select(1, parseHex(color)) }) end
		end)
		self.connTracker:connect(btn.MouseLeave, function()
			self.tweens:tween(btn, FAST, { BackgroundColor3 = select(1, parseHex(theme.Elevated)), BackgroundTransparency = select(2, parseHex(theme.Elevated)) })
			self.tweens:tween(btn, FAST, { TextColor3 = select(1, parseHex(theme.TextSecondary)) })
		end)
		self.connTracker:connect(btn.MouseButton1Click, callback)
		return btn
	end

	makeIconButton("—", nil, function() self:Hide() end)
	makeIconButton("✕", theme.Danger, function() self:Destroy() end)

	-- Resize handle (bottom-right)
	local resizeHandle = create("TextButton", {
		Name = "ResizeHandle",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -2, 1, -2),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
		Parent = window,
	})
	self.resizeHandle = resizeHandle

	-- Body: левая колонка (tabs), центр (контент), правая (settings)
	local body = create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		ZIndex = 3,
		Parent = window,
	})
	self.body = body

	local sidebar = create("Frame", {
		Name = "Sidebar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(180, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		ZIndex = 4,
		Parent = body,
	})
	sidebar.Size = UDim2.new(0, 180, 1, 0)
	addPadding(sidebar, 12, 12, 12, 12)
	local sidebarLayout = addList(sidebar, Enum.FillDirection.Vertical, 6)
	sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	self.sidebar = sidebar

	-- Content area
	local content = create("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(180, 0),
		Size = UDim2.new(1, -180, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 4,
		Parent = body,
	})
	addPadding(content, 16, 16, 12, 16)
	local contentLayout = addList(content, Enum.FillDirection.Vertical, 12)
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	self.content = content
	self.contentLayout = contentLayout

	-- Notification stack (top-right of screen)
	local toastStack = create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20),
		Size = UDim2.fromOffset(320, 0),
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 100,
		Parent = screenGui,
	})
	local toastLayout = addList(toastStack, Enum.FillDirection.Vertical, 8)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	self.toastStack = toastStack

	-- Tooltip layer (single floating tooltip)
	local tooltip = create("Frame", {
		Name = "Tooltip",
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 200,
		Parent = screenGui,
	})
	applyFill(tooltip, theme.Surface)
	addCorner(tooltip, 6)
	addStroke(tooltip, 1, theme.Border)
	addPadding(tooltip, 10, 10, 6, 6)
	local tooltipLabel = create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Font = fontFor(500),
		TextSize = 12,
		Text = "",
		ZIndex = 201,
		Parent = tooltip,
	})
	applyText(tooltipLabel, theme.TextSecondary)
	self.tooltip = tooltip
	self.tooltipLabel = tooltipLabel

	-- Watermark (bottom-left of screen)
	if cfg.Watermark then
		local wm = create("Frame", {
			Name = "Watermark",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -12),
			Size = UDim2.fromOffset(180, 26),
			BorderSizePixel = 0,
			ZIndex = 100,
			Parent = screenGui,
		})
		applyFill(wm, theme.Surface)
		addCorner(wm, 6)
		addStroke(wm, 1, theme.Border)
		addPadding(wm, 8, 8, 4, 4)
		local wmLabel = create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = fontFor(600),
			TextSize = 11,
			Text = cfg.WatermarkText or "Sigmatik",
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 101,
			Parent = wm,
		})
		applyText(wmLabel, theme.TextSecondary)
		self.watermark = wm
		self.watermarkLabel = wmLabel
	end

	-- Command palette overlay
	local palette = create("Frame", {
		Name = "Palette",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(480, 320),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 300,
		Parent = screenGui,
	})
	applyFill(palette, theme.Surface)
	addCorner(palette, 10)
	addStroke(palette, 1, theme.Border)
	local paletteInput = create("TextBox", {
		Name = "Input",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 32),
		Font = fontFor(500),
		TextSize = 14,
		Text = "",
		PlaceholderText = "Type a command...",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 301,
		Parent = palette,
	})
	applyText(paletteInput, theme.TextPrimary)
	paletteInput.PlaceholderColor3 = select(1, parseHex(theme.TextMuted))
	local paletteList = create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 301,
		Parent = palette,
	})
	addPadding(paletteList, 8, 8, 0, 8)
	addList(paletteList, Enum.FillDirection.Vertical, 4)
	self.palette = palette
	self.paletteInput = paletteInput
	self.paletteList = paletteList
end

----------------------------------------------------------------
-- Окно: жизненный цикл, drag, resize, темизация
----------------------------------------------------------------

function Window.new(config)
	local self = setmetatable({}, Window)
	config = config or {}
	self.config = {
		Title = config.Title or "Sigmatik",
		Subtitle = config.Subtitle,
		WindowWidth = config.WindowWidth or 720,
		WindowHeight = config.WindowHeight or 480,
		MinWidth = config.MinWidth or 480,
		MinHeight = config.MinHeight or 320,
		ToggleKey = config.ToggleKey or Enum.KeyCode.RightShift,
		Watermark = config.Watermark,
		WatermarkText = config.WatermarkText,
		ConfigName = config.ConfigName or "default",
		ConfigFolder = config.ConfigFolder or "SigmatikConfigs",
		AutoSave = config.AutoSave ~= false,
		EnableBlur = config.EnableBlur ~= false,
		EnableCommandPalette = config.EnableCommandPalette ~= false,
		ResponsiveBreakpoint = config.ResponsiveBreakpoint or 560,
	}

	self.theme = makeTheme(config.Theme or "Dark", config.Accent)
	self.themeListeners = {}
	self.tabs = {}
	self.tabLookup = {}
	self.controls = {}
	self.connTracker = newConnectionTracker()
	self.tweens = newTweenManager()
	self.visible = true
	self.disposed = false
	self.draggingSlider = nil
	self.waitingForBind = nil
	self.keybinds = {}
	self.commandIndex = {}
	self.lastFps = 0
	self.tooltipTarget = nil
	self.tooltipTimer = 0

	buildSkeleton(self)
	self:_wireInput()
	self:_setupSidebar()

	-- Появление
	self.tweens:tween(self.windowScale, POP, { Scale = 1 })

	if self.config.AutoSave then
		self:_loadConfig(self.config.ConfigName, true)
	end

	return self
end

function Window:_wireInput()
	local cfg = self.config
	local theme = self.theme

	-- Drag по header'у
	local dragging = false
	local dragStart, posStart
	self.connTracker:connect(self.header.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			posStart = self.window.Position
		end
	end)
	self.connTracker:connect(self.header.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	self.connTracker:connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			local viewport = self.screenGui.AbsoluteSize
			local sz = self.window.AbsoluteSize
			local newX = posStart.X.Offset + delta.X
			local newY = posStart.Y.Offset + delta.Y
			-- Clamp к viewport (с учётом anchor 0.5,0.5)
			local halfW, halfH = sz.X / 2, sz.Y / 2
			local minX, maxX = halfW - viewport.X / 2, viewport.X / 2 - halfW
			local minY, maxY = halfH - viewport.Y / 2, viewport.Y / 2 - halfH
			newX = math.clamp(newX, minX, maxX)
			newY = math.clamp(newY, minY, maxY)
			-- Snap к краям (если близко)
			local snap = 12
			if math.abs(newX - minX) < snap then newX = minX end
			if math.abs(newX - maxX) < snap then newX = maxX end
			if math.abs(newY - minY) < snap then newY = minY end
			if math.abs(newY - maxY) < snap then newY = maxY end
			self.window.Position = UDim2.new(0.5, newX, 0.5, newY)
		end
		if self.draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			self.draggingSlider.update(input.Position.X, input.Position.Y)
		end
	end)
	self.connTracker:connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if self.draggingSlider then
				local s = self.draggingSlider
				self.draggingSlider = nil
				if s.finish then s.finish() end
			end
			if self.resizing then self.resizing = nil end
		end
	end)

	-- Resize
	local resizing = false
	local resizeStart, sizeStart
	self.connTracker:connect(self.resizeHandle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			self.resizing = true
			resizeStart = input.Position
			sizeStart = self.window.AbsoluteSize
		end
	end)
	self.connTracker:connect(self.resizeHandle.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = false
		end
	end)
	self.connTracker:connect(UserInputService.InputChanged, function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - resizeStart
			local nw = math.max(cfg.MinWidth, sizeStart.X + delta.X)
			local nh = math.max(cfg.MinHeight, sizeStart.Y + delta.Y)
			self.window.Size = UDim2.fromOffset(nw, nh)
			self.config.WindowWidth = nw
			self.config.WindowHeight = nh
			self:_handleResponsive()
		end
	end)

	-- Toggle key + Escape
	self.connTracker:connect(UserInputService.InputBegan, function(input, processed)
		if processed then return end
		if self.waitingForBind and input.UserInputType == Enum.UserInputType.Keyboard then
			local cb = self.waitingForBind
			self.waitingForBind = nil
			cb(input.KeyCode)
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			if input.KeyCode == cfg.ToggleKey then
				self:Toggle()
			elseif input.KeyCode == Enum.KeyCode.Escape and self.palette.Visible then
				self:CloseCommandPalette()
			elseif input.KeyCode == Enum.KeyCode.K and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) and cfg.EnableCommandPalette then
				self:OpenCommandPalette()
			else
				-- Раздать в KeybindManager
				for _, kb in ipairs(self.keybinds) do
					if kb.key == input.KeyCode then
						if kb.mode == "Toggle" then
							kb.set(not kb.value)
						elseif kb.mode == "Hold" then
							kb.set(true)
						elseif kb.mode == "Always" then
							safeFire(kb.callback, input.KeyCode)
						end
					end
				end
			end
		end
	end)
	self.connTracker:connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			for _, kb in ipairs(self.keybinds) do
				if kb.key == input.KeyCode and kb.mode == "Hold" then
					kb.set(false)
				end
			end
		end
	end)

	-- Tooltip follow
	self.connTracker:connect(RunService.Heartbeat, function(dt)
		if self.disposed then return end
		self.tooltipTimer = self.tooltipTimer + dt
		if self.tooltipTarget and self.tooltipTimer >= 0.4 and not self.tooltip.Visible then
			self.tooltip.Visible = true
			self.tweens:tween(self.tooltip, FADE, { BackgroundTransparency = select(2, parseHex(self.theme.Surface)) })
		end
		if self.tooltip.Visible then
			local mp = UserInputService:GetMouseLocation()
			self.tooltip.Position = UDim2.fromOffset(mp.X + 14, mp.Y + 18)
		end
		-- Watermark FPS
		if self.watermarkLabel then
			self.lastFps = math.floor(1 / math.max(dt, 1e-6))
			local ping = "—"
			if Stats and Stats.PerformanceStats and Stats.PerformanceStats:FindFirstChild("Ping") then
				ping = string.format("%dms", math.floor(Stats.PerformanceStats.Ping:GetValue()))
			end
			self.watermarkLabel.Text = string.format("%s · %d FPS · %s", self.config.WatermarkText or "Sigmatik", self.lastFps, ping)
		end
	end)

	-- Cleanup blur при удалении
	self.connTracker:connect(self.screenGui.AncestryChanged, function(_, parent)
		if parent == nil then
			pcall(function() self.blur:Destroy() end)
		end
	end)
end

function Window:_handleResponsive()
	-- На узком окне прячем сайдбар-надписи (оставляем только иконки) — упрощённо
	local narrow = self.window.AbsoluteSize.X < self.config.ResponsiveBreakpoint
	if narrow ~= self._narrow then
		self._narrow = narrow
		for _, t in ipairs(self.tabs) do
			if t._label then t._label.Visible = not narrow end
		end
		self.sidebar.Size = UDim2.new(0, narrow and 56 or 180, 1, 0)
		self.content.Position = UDim2.fromOffset(narrow and 56 or 180, 0)
		self.content.Size = UDim2.new(1, narrow and -56 or -180, 1, 0)
	end
end

function Window:_setupSidebar()
	-- Сайдбар уже создан, табы будут добавляться через AddTab.
end

----------------------------------------------------------------
-- Темизация (apply ко всему UI)
----------------------------------------------------------------

function Window:_addThemeListener(fn)
	table.insert(self.themeListeners, fn)
	pcallSafe(fn, self.theme)
end

function Window:SetTheme(presetOrTable, accent)
	if type(presetOrTable) == "table" then
		for k, v in pairs(presetOrTable) do self.theme[k] = v end
	else
		self.theme = makeTheme(presetOrTable, accent or self.theme.Accent)
	end
	-- Обновить базовые элементы
	applyFill(self.window, self.theme.Surface)
	applyStroke(self.windowStroke, self.theme.Border)
	applyFill(self.header, self.theme.Elevated)
	applyStroke(self.headerStroke, self.theme.Border)
	applyText(self.title, self.theme.TextPrimary)
	applyText(self.subtitle, self.theme.TextMuted)
	applyFill(self.dim, self.theme.Dim)
	applyFill(self.tooltip, self.theme.Surface)
	applyText(self.tooltipLabel, self.theme.TextSecondary)
	if self.watermark then
		applyFill(self.watermark, self.theme.Surface)
		applyText(self.watermarkLabel, self.theme.TextSecondary)
	end
	for _, fn in ipairs(self.themeListeners) do pcallSafe(fn, self.theme) end
end

----------------------------------------------------------------
-- Visibility
----------------------------------------------------------------

function Window:Show()
	if self.disposed then return end
	self.visible = true
	self.window.Visible = true
	self.tweens:tween(self.windowScale, POP, { Scale = 1 })
	if self.config.EnableBlur then
		self.tweens:tween(self.blur, FADE, { Size = self.theme.BlurSize })
	end
end

function Window:Hide()
	if self.disposed then return end
	self.visible = false
	self.tweens:tween(self.windowScale, FAST, { Scale = 0.96 })
	self.tweens:tween(self.blur, FADE, { Size = 0 })
	task.delay(0.18, function()
		if not self.disposed and not self.visible then
			self.window.Visible = false
		end
	end)
end

function Window:Toggle()
	if self.visible then self:Hide() else self:Show() end
end

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------

function Window:Notify(opts)
	opts = opts or {}
	local theme = self.theme
	local typ = opts.Type or "info"
	local colorMap = { info = theme.Info, success = theme.Success, warning = theme.Warning, error = theme.Danger, danger = theme.Danger }
	local accent = colorMap[string.lower(typ)] or theme.Info

	local toast = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		BackgroundTransparency = 0,
		ZIndex = 100,
		Parent = self.toastStack,
	})
	applyFill(toast, theme.Surface)
	addCorner(toast, 8)
	addStroke(toast, 1, theme.Border)
	addPadding(toast, 12, 12, 10, 10)

	local accentBar = create("Frame", {
		Size = UDim2.fromOffset(3, 0),
		BorderSizePixel = 0,
		ZIndex = 101,
		Parent = toast,
	})
	accentBar.AutomaticSize = Enum.AutomaticSize.Y
	applyFill(accentBar, accent)
	addCorner(accentBar, 2)

	local content = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 101,
		Parent = toast,
	})
	addList(content, Enum.FillDirection.Vertical, 2)

	if opts.Title then
		local t = create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			Font = fontFor(700),
			TextSize = 13,
			Text = opts.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 102,
			Parent = content,
		})
		applyText(t, theme.TextPrimary)
	end
	if opts.Text then
		local t = create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = fontFor(400),
			TextSize = 12,
			Text = opts.Text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 102,
			Parent = content,
		})
		applyText(t, theme.TextSecondary)
	end

	-- Появление
	toast.Position = UDim2.fromOffset(40, 0)
	toast.BackgroundTransparency = 1
	self.tweens:tween(toast, FAST, { BackgroundTransparency = select(2, parseHex(theme.Surface)), Position = UDim2.fromOffset(0, 0) })

	local duration = opts.Duration or 4
	task.delay(duration, function()
		if toast.Parent then
			self.tweens:tween(toast, FADE, { BackgroundTransparency = 1, Position = UDim2.fromOffset(40, 0) })
			task.delay(0.25, function() pcall(function() toast:Destroy() end) end)
		end
	end)
end

----------------------------------------------------------------
-- Tooltip API
----------------------------------------------------------------

function Window:_attachTooltip(guiObject, text)
	if not text or text == "" then return end
	self.connTracker:connect(guiObject.MouseEnter, function()
		self.tooltipTarget = guiObject
		self.tooltipTimer = 0
		self.tooltipLabel.Text = text
	end)
	self.connTracker:connect(guiObject.MouseLeave, function()
		if self.tooltipTarget == guiObject then
			self.tooltipTarget = nil
			self.tooltip.Visible = false
		end
	end)
end

----------------------------------------------------------------
-- Config save/load
----------------------------------------------------------------

local function fsAvail()
	return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

function Window:_serialize()
	local data = { theme = { Preset = self.theme.Preset, Accent = self.theme.Accent }, controls = {} }
	for id, ctl in pairs(self.controls) do
		if ctl._serialize then
			data.controls[id] = ctl._serialize()
		end
	end
	return data
end

function Window:_deserialize(data)
	if not data then return end
	if data.theme and data.theme.Preset then
		self:SetTheme(data.theme.Preset, data.theme.Accent)
	end
	if data.controls then
		for id, val in pairs(data.controls) do
			local ctl = self.controls[id]
			if ctl and ctl._deserialize then
				pcallSafe(ctl._deserialize, val)
			end
		end
	end
end

local function configPath(folder, name)
	return string.format("%s/%s.json", folder, name)
end

function Window:SaveConfig(name)
	if not fsAvail() then return false, "filesystem not available" end
	name = name or self.config.ConfigName
	local folder = self.config.ConfigFolder
	pcall(function() if type(makefolder) == "function" and not isfolder(folder) then makefolder(folder) end end)
	local data = self:_serialize()
	local ok, encoded = pcall(function() return HttpService:JSONEncode(data) end)
	if not ok then return false, encoded end
	pcall(function() writefile(configPath(folder, name), encoded) end)
	return true
end

function Window:LoadConfig(name)
	return self:_loadConfig(name, false)
end

function Window:_loadConfig(name, silent)
	if not fsAvail() then return false end
	name = name or self.config.ConfigName
	local folder = self.config.ConfigFolder
	local path = configPath(folder, name)
	if not isfile(path) then return false end
	local ok, raw = pcall(function() return readfile(path) end)
	if not ok then return false end
	local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok2 then return false end
	self:_deserialize(data)
	if not silent then self:Notify({ Title = "Config Loaded", Text = name, Type = "success" }) end
	return true
end

function Window:_autoSave()
	if self.config.AutoSave then
		task.spawn(function() self:SaveConfig() end)
	end
end

function Window:ListConfigs()
	if not fsAvail() or type(listfiles) ~= "function" then return {} end
	local folder = self.config.ConfigFolder
	if not isfolder(folder) then return {} end
	local out = {}
	for _, p in ipairs(listfiles(folder)) do
		local n = string.match(p, "([^/\\]+)%.json$")
		if n then table.insert(out, n) end
	end
	return out
end

----------------------------------------------------------------
-- Command Palette
----------------------------------------------------------------

function Window:_registerCommand(label, callback, group)
	table.insert(self.commandIndex, { label = label, callback = callback, group = group })
end

function Window:OpenCommandPalette()
	if self.disposed then return end
	self.palette.Visible = true
	self.paletteInput.Text = ""
	self.paletteInput:CaptureFocus()
	self:_renderPalette("")
end

function Window:CloseCommandPalette()
	self.palette.Visible = false
	self.paletteInput:ReleaseFocus()
end

function Window:_renderPalette(query)
	for _, c in ipairs(self.paletteList:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	query = string.lower(query)
	for _, cmd in ipairs(self.commandIndex) do
		if query == "" or string.find(string.lower(cmd.label), query, 1, true) then
			local btn = create("TextButton", {
				Size = UDim2.new(1, 0, 0, 28),
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Font = fontFor(500),
				TextSize = 13,
				Text = "  " .. cmd.label .. (cmd.group and ("  ·  " .. cmd.group) or ""),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 302,
				Parent = self.paletteList,
			})
			applyText(btn, self.theme.TextSecondary)
			addCorner(btn, 4)
			self.connTracker:connect(btn.MouseEnter, function()
				applyFill(btn, self.theme.ElevatedHover)
				btn.BackgroundTransparency = select(2, parseHex(self.theme.ElevatedHover))
			end)
			self.connTracker:connect(btn.MouseLeave, function() btn.BackgroundTransparency = 1 end)
			self.connTracker:connect(btn.MouseButton1Click, function()
				self:CloseCommandPalette()
				safeFire(cmd.callback)
			end)
		end
	end
end

----------------------------------------------------------------
-- Tabs
----------------------------------------------------------------

function Window:AddTab(opts)
	opts = opts or {}
	local tab = setmetatable({
		window = self,
		name = opts.Name or "Tab",
		icon = opts.Icon,
		_button = nil,
		_label = nil,
		_page = nil,
		_sections = {},
	}, Tab)

	local btn = create("TextButton", {
		Name = tab.name,
		Size = UDim2.new(1, 0, 0, 32),
		AutoButtonColor = false,
		BackgroundTransparency = 0,
		Font = fontFor(600),
		TextSize = 12,
		Text = "  " .. tab.name,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = self.sidebar,
	})
	applyFill(btn, self.theme.Elevated)
	applyText(btn, self.theme.TextSecondary)
	btn.BackgroundTransparency = 1
	addCorner(btn, 6)
	tab._button = btn
	tab._label = btn

	local page = create("Frame", {
		Name = tab.name .. "Page",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = #self.tabs == 0,
		ZIndex = 4,
		Parent = self.content,
	})
	addList(page, Enum.FillDirection.Vertical, 12)
	tab._page = page

	self.connTracker:connect(btn.MouseEnter, function()
		if self.activeTab ~= tab then
			self.tweens:tween(btn, FAST, {
				BackgroundColor3 = select(1, parseHex(self.theme.ElevatedHover)),
				BackgroundTransparency = select(2, parseHex(self.theme.ElevatedHover)),
			})
		end
	end)
	self.connTracker:connect(btn.MouseLeave, function()
		if self.activeTab ~= tab then
			self.tweens:tween(btn, FAST, { BackgroundTransparency = 1 })
		end
	end)
	self.connTracker:connect(btn.MouseButton1Click, function()
		self:_selectTab(tab)
	end)

	table.insert(self.tabs, tab)
	self.tabLookup[tab.name] = tab
	if not self.activeTab then self:_selectTab(tab) end

	-- Регистрация в command palette
	self:_registerCommand("Switch to: " .. tab.name, function() self:_selectTab(tab) end, "Tabs")

	return tab
end

function Window:_selectTab(tab)
	self.activeTab = tab
	for _, t in ipairs(self.tabs) do
		t._page.Visible = (t == tab)
		if t == tab then
			self.tweens:tween(t._button, FAST, {
				BackgroundColor3 = select(1, parseHex(self.theme.Accent .. "20")),
				BackgroundTransparency = select(2, parseHex(self.theme.Accent .. "20")),
				TextColor3 = select(1, parseHex(self.theme.AccentSoft)),
			})
		else
			self.tweens:tween(t._button, FAST, {
				BackgroundTransparency = 1,
				TextColor3 = select(1, parseHex(self.theme.TextSecondary)),
			})
		end
	end
end

function Window:GetTab(name) return self.tabLookup[name] end

----------------------------------------------------------------
-- Section
----------------------------------------------------------------

function Tab:AddSection(opts)
	opts = opts or {}
	local section = setmetatable({
		tab = self,
		window = self.window,
		name = opts.Name or "Section",
		_controls = {},
	}, Section)

	local frame = create("Frame", {
		Name = section.name .. "Section",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = self._page,
	})
	applyFill(frame, self.window.theme.Elevated)
	addCorner(frame, 8)
	addStroke(frame, 1, self.window.theme.Border)
	addPadding(frame, 14, 14, 12, 14)

	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Font = fontFor(700),
		TextSize = 13,
		Text = section.name,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = frame,
	})
	applyText(title, self.window.theme.TextPrimary)

	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 5,
		Parent = frame,
	})
	addList(body, Enum.FillDirection.Vertical, 8)

	section._frame = frame
	section._title = title
	section._body = body

	self.window:_addThemeListener(function(theme)
		applyFill(frame, theme.Elevated)
		applyText(title, theme.TextPrimary)
	end)

	table.insert(self._sections, section)
	return section
end

----------------------------------------------------------------
-- Базовый класс контрола
----------------------------------------------------------------

local function newControlBase(section, opts)
	local self = {
		section = section,
		window = section.window,
		name = opts.Name or "Control",
		description = opts.Description or opts.Tooltip,
		flag = opts.Flag,
		callbacks = {},
		disabled = false,
		loading = false,
		_destroyed = false,
	}
	function self:OnChanged(fn) table.insert(self.callbacks, fn); return self end
	function self:_fire(value)
		for _, cb in ipairs(self.callbacks) do safeFire(cb, value) end
	end
	function self:SetVisible(v) if self.frame then self.frame.Visible = v end end
	function self:SetDisabled(d)
		self.disabled = d and true or false
		if self.frame then
			self.frame.Active = not self.disabled
			for _, c in ipairs(self.frame:GetDescendants()) do
				if c:IsA("GuiObject") then
					c.Active = not self.disabled
				end
			end
			self.window.tweens:tween(self.frame, FAST, { BackgroundTransparency = self.disabled and 0.7 or select(2, parseHex(self.window.theme.Elevated)) })
		end
	end
	function self:SetLoading(l)
		self.loading = l and true or false
	end
	function self:Destroy()
		self._destroyed = true
		if self.frame then pcall(function() self.frame:Destroy() end) end
		if self.flag then self.window.controls[self.flag] = nil end
	end
	if self.flag then section.window.controls[self.flag] = self end
	return self
end

local function makeRow(section, height)
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, height or 32),
		BorderSizePixel = 0,
		BackgroundTransparency = 0,
		ZIndex = 5,
		Parent = section._body,
	})
	applyFill(row, section.window.theme.SurfaceAlt)
	addCorner(row, 6)
	addStroke(row, 1, section.window.theme.Border)
	addPadding(row, 10, 10, 6, 6)
	return row
end

----------------------------------------------------------------
-- Компоненты
----------------------------------------------------------------

-- Label
function Section:AddLabel(opts)
	opts = opts or {}
	local self_ = self
	local ctl = newControlBase(self, opts)
	local row = makeRow(self, 26)
	row.BackgroundTransparency = 1
	local lbl = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = fontFor(500),
		TextSize = 12,
		Text = opts.Text or opts.Name or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyText(lbl, self.window.theme.TextSecondary)
	ctl.frame = row
	ctl._label = lbl
	function ctl:Set(text) lbl.Text = text end
	self.window:_addThemeListener(function(t) applyText(lbl, t.TextSecondary) end)
	return ctl
end

-- Paragraph
function Section:AddParagraph(opts)
	opts = opts or {}
	local ctl = newControlBase(self, opts)
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		BackgroundTransparency = 0,
		ZIndex = 5,
		Parent = self._body,
	})
	applyFill(row, self.window.theme.SurfaceAlt)
	addCorner(row, 6)
	addStroke(row, 1, self.window.theme.Border)
	addPadding(row, 10, 10, 8, 8)
	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Font = fontFor(700),
		TextSize = 12,
		Text = opts.Name or opts.Title or "Note",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyText(title, self.window.theme.TextPrimary)
	local body = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = fontFor(400),
		TextSize = 12,
		TextWrapped = true,
		Text = opts.Content or opts.Text or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 6,
		Parent = row,
	})
	applyText(body, self.window.theme.TextMuted)
	ctl.frame = row
	function ctl:Set(text) body.Text = text end
	self.window:_addThemeListener(function(t)
		applyText(title, t.TextPrimary)
		applyText(body, t.TextMuted)
	end)
	return ctl
end

-- Button
function Section:AddButton(opts)
	opts = opts or {}
	local ctl = newControlBase(self, opts)
	local btn = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = fontFor(600),
		TextSize = 12,
		Text = opts.Name or "Button",
		ZIndex = 5,
		Parent = self._body,
	})
	applyFill(btn, self.window.theme.Accent .. "1f")
	applyText(btn, self.window.theme.AccentSoft)
	addCorner(btn, 6)
	local stroke = addStroke(btn, 1, self.window.theme.Accent .. "40")
	ctl.frame = btn

	self.window.connTracker:connect(btn.MouseEnter, function()
		if ctl.disabled then return end
		self.window.tweens:tween(btn, FAST, {
			BackgroundColor3 = select(1, parseHex(self.window.theme.Accent .. "30")),
			BackgroundTransparency = select(2, parseHex(self.window.theme.Accent .. "30")),
		})
	end)
	self.window.connTracker:connect(btn.MouseLeave, function()
		self.window.tweens:tween(btn, FAST, {
			BackgroundColor3 = select(1, parseHex(self.window.theme.Accent .. "1f")),
			BackgroundTransparency = select(2, parseHex(self.window.theme.Accent .. "1f")),
		})
	end)
	self.window.connTracker:connect(btn.MouseButton1Click, function()
		if ctl.disabled or ctl.loading then return end
		safeFire(opts.Callback)
		ctl:_fire(true)
	end)
	if ctl.description then self.window:_attachTooltip(btn, ctl.description) end
	self.window:_addThemeListener(function(t)
		applyFill(btn, t.Accent .. "1f")
		applyText(btn, t.AccentSoft)
		applyStroke(stroke, t.Accent .. "40")
	end)
	self.window:_registerCommand((opts.Name or "Button") .. " (run)", function() safeFire(opts.Callback) end, self.tab.name)
	return ctl
end

-- Toggle
function Section:AddToggle(opts)
	opts = opts or {}
	local ctl = newControlBase(self, opts)
	local row = makeRow(self, 32)
	local lbl = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -50, 1, 0),
		Font = fontFor(500),
		TextSize = 12,
		Text = opts.Name or "Toggle",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyText(lbl, self.window.theme.TextSecondary)

	local switch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(36, 18),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = row,
	})
	applyFill(switch, self.window.theme.Border)
	addCorner(switch, 999)
	local thumb = create("Frame", {
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.fromOffset(14, 14),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = switch,
	})
	applyFill(thumb, WHITE)
	addCorner(thumb, 999)
	local hit = create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 8,
		Parent = row,
	})

	ctl.value = opts.Default and true or false
	ctl.frame = row

	local function paint(instant)
		local fill = ctl.value and self.window.theme.Accent or self.window.theme.Border
		local pos = ctl.value and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
		if instant then
			applyFill(switch, fill)
			thumb.Position = pos
		else
			self.window.tweens:tween(switch, FAST, {
				BackgroundColor3 = select(1, parseHex(fill)),
				BackgroundTransparency = select(2, parseHex(fill)),
			})
			self.window.tweens:tween(thumb, FAST, { Position = pos })
		end
	end
	paint(true)

	function ctl:Set(v, silent)
		self.value = v and true or false
		paint(false)
		if not silent then
			safeFire(opts.Callback, self.value)
			self:_fire(self.value)
			self.window:_autoSave()
		end
	end
	function ctl:Get() return self.value end
	ctl._serialize = function() return ctl.value end
	ctl._deserialize = function(v) ctl:Set(v, true) end

	self.window.connTracker:connect(hit.MouseButton1Click, function()
		if ctl.disabled then return end
		ctl:Set(not ctl.value)
	end)
	if ctl.description then self.window:_attachTooltip(row, ctl.description) end
	self.window:_addThemeListener(function(t) paint(true); applyText(lbl, t.TextSecondary) end)
	self.window:_registerCommand("Toggle: " .. (opts.Name or ""), function() ctl:Set(not ctl.value) end, self.tab.name)
	return ctl
end

-- Slider
function Section:AddSlider(opts)
	opts = opts or {}
	local ctl = newControlBase(self, opts)
	local row = makeRow(self, 50)

	local lbl = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.6, 0, 0, 16),
		Font = fontFor(500),
		TextSize = 12,
		Text = opts.Name or "Slider",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyText(lbl, self.window.theme.TextSecondary)

	local valLbl = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = fontFor(600),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
		Parent = row,
	})
	applyText(valLbl, self.window.theme.AccentSoft)

	local track = create("Frame", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 6),
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = row,
	})
	applyFill(track, self.window.theme.Border)
	addCorner(track, 999)
	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = track,
	})
	applyFill(fill, self.window.theme.Accent)
	addCorner(fill, 999)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = track,
	})
	applyFill(knob, WHITE)
	addCorner(knob, 999)
	local hit = create("TextButton", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, -6),
		Size = UDim2.new(1, 0, 1, 12),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 9,
		Parent = track,
	})

	local mn = opts.Min or 0
	local mx = opts.Max or 100
	local inc = opts.Increment or 1
	local fmt = opts.ValueFormat or function(v) return tostring(v) end
	ctl.value = clampRound(opts.Default or mn, mn, mx, inc)
	ctl.min = mn
	ctl.max = mx
	ctl.frame = row

	local function paint(instant)
		local p = (ctl.value - mn) / math.max(mx - mn, 1e-9)
		valLbl.Text = fmt(ctl.value)
		if instant then
			fill.Size = UDim2.fromScale(p, 1)
			knob.Position = UDim2.new(p, 0, 0.5, 0)
		else
			self.window.tweens:tween(fill, FAST, { Size = UDim2.fromScale(p, 1) })
			self.window.tweens:tween(knob, FAST, { Position = UDim2.new(p, 0, 0.5, 0) })
		end
	end
	paint(true)

	function ctl:Set(v, silent)
		self.value = clampRound(v, mn, mx, inc)
		paint(false)
		if not silent then
			safeFire(opts.Callback, self.value)
			self:_fire(self.value)
			self.window:_autoSave()
		end
	end
	function ctl:Get() return self.value end
	ctl._serialize = function() return ctl.value end
	ctl._deserialize = function(v) ctl:Set(v, true) end

	self.window.connTracker:connect(hit.InputBegan, function(input)
		if ctl.disabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.window.draggingSlider = {
				update = function(px, _)
					local rel = math.clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
					ctl:Set(mn + (mx - mn) * rel, false)
				end,
				finish = function() end,
			}
			-- мгновенно по клику
			local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			ctl:Set(mn + (mx - mn) * rel, false)
		end
	end)
	if ctl.description then self.window:_attachTooltip(row, ctl.description) end
	self.window:_addThemeListener(function(t)
		applyText(lbl, t.TextSecondary); applyText(valLbl, t.AccentSoft)
		applyFill(track, t.Border); applyFill(fill, t.Accent)
		paint(true)
	end)
	return ctl
end

-- Textbox
function Section:AddTextbox(opts)
	opts = opts or {}
	local ctl = newControlBase(self, opts)
	local row = makeRow(self, 50)
	local lbl = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Font = fontFor(500),
		TextSize = 12,
		Text = opts.Name or "Textbox",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyText(lbl, self.window.theme.TextSecondary)
	local box = create("TextBox", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 22),
		BorderSizePixel = 0,
		Font = fontFor(500),
		TextSize = 12,
		Text = opts.Default or "",
		PlaceholderText = opts.Placeholder or "",
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyFill(box, self.window.theme.Surface)
	applyText(box, self.window.theme.TextPrimary)
	box.PlaceholderColor3 = select(1, parseHex(self.window.theme.TextMuted))
	addCorner(box, 4)
	local boxStroke = addStroke(box, 1, self.window.theme.Border)
	addPadding(box, 8, 8, 0, 0)

	ctl.value = opts.Default or ""
	ctl.frame = row

	function ctl:Set(v, silent)
		self.value = tostring(v or "")
		box.Text = self.value
		if not silent then
			safeFire(opts.Callback, self.value)
			self:_fire(self.value)
			self.window:_autoSave()
		end
	end
	function ctl:Get() return self.value end
	ctl._serialize = function() return ctl.value end
	ctl._deserialize = function(v) ctl:Set(v, true) end

	self.window.connTracker:connect(box.Focused, function()
		applyStroke(boxStroke, self.window.theme.Accent)
	end)
	self.window.connTracker:connect(box.FocusLost, function()
		applyStroke(boxStroke, self.window.theme.Border)
		ctl:Set(box.Text)
	end)
	if ctl.description then self.window:_attachTooltip(row, ctl.description) end
	return ctl
end

-- Dropdown / MultiDropdown
function Section:AddDropdown(opts)
	opts = opts or {}
	local multi = opts.Multi or opts.MultiSelect or false
	local ctl = newControlBase(self, opts)
	local row = makeRow(self, 50)

	local lbl = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 14),
		Font = fontFor(500),
		TextSize = 12,
		Text = opts.Name or "Dropdown",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyText(lbl, self.window.theme.TextSecondary)

	local btn = create("TextButton", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 22),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = fontFor(500),
		TextSize = 12,
		Text = "Select...",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyFill(btn, self.window.theme.Surface)
	applyText(btn, self.window.theme.TextPrimary)
	addCorner(btn, 4)
	local btnStroke = addStroke(btn, 1, self.window.theme.Border)
	addPadding(btn, 8, 8, 0, 0)

	local arrow = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		Font = fontFor(700),
		TextSize = 11,
		Text = "▾",
		ZIndex = 7,
		Parent = btn,
	})
	applyText(arrow, self.window.theme.TextMuted)

	local items = arrayCopy(opts.Items or opts.Options or {})
	local selected = multi and {} or nil
	if multi then
		for _, v in ipairs(opts.Default or {}) do selected[v] = true end
	else
		selected = opts.Default
	end

	local function refreshLabel()
		if multi then
			local list = {}
			for _, it in ipairs(items) do if selected[it] then table.insert(list, it) end end
			btn.Text = #list == 0 and "None" or table.concat(list, ", ")
		else
			btn.Text = selected and tostring(selected) or "Select..."
		end
	end
	refreshLabel()

	-- Dropdown menu (overlay)
	local menu = create("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 50,
		Parent = self.window.screenGui,
	})
	applyFill(menu, self.window.theme.Surface)
	addCorner(menu, 6)
	addStroke(menu, 1, self.window.theme.Border)
	addPadding(menu, 4, 4, 4, 4)

	local search
	if opts.Searchable ~= false then
		search = create("TextBox", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Font = fontFor(500),
			TextSize = 12,
			Text = "",
			PlaceholderText = "Search...",
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 51,
			Parent = menu,
		})
		applyFill(search, self.window.theme.SurfaceAlt)
		applyText(search, self.window.theme.TextPrimary)
		search.PlaceholderColor3 = select(1, parseHex(self.window.theme.TextMuted))
		addCorner(search, 4)
		addPadding(search, 8, 8, 0, 0)
	end

	local list = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, search and 26 or 0),
		Size = UDim2.new(1, 0, 0, 160),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 51,
		Parent = menu,
	})
	addList(list, Enum.FillDirection.Vertical, 2)

	local function rebuild(query)
		query = string.lower(query or "")
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for _, it in ipairs(items) do
			if query == "" or string.find(string.lower(tostring(it)), query, 1, true) then
				local isSel = multi and selected[it] or selected == it
				local item = create("TextButton", {
					Size = UDim2.new(1, 0, 0, 24),
					BorderSizePixel = 0,
					AutoButtonColor = false,
					BackgroundTransparency = isSel and 0 or 1,
					Font = fontFor(500),
					TextSize = 12,
					Text = "  " .. tostring(it) .. (isSel and "  ✓" or ""),
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 52,
					Parent = list,
				})
				if isSel then applyFill(item, self.window.theme.Accent .. "20") end
				applyText(item, isSel and self.window.theme.AccentSoft or self.window.theme.TextSecondary)
				addCorner(item, 4)
				self.window.connTracker:connect(item.MouseButton1Click, function()
					if multi then
						selected[it] = not selected[it] or nil
						if not selected[it] then selected[it] = nil end
					else
						selected = it
					end
					refreshLabel()
					rebuild(search and search.Text or "")
					if multi then
						local out = {}
						for _, v in ipairs(items) do if selected[v] then table.insert(out, v) end end
						safeFire(opts.Callback, out)
						ctl:_fire(out)
					else
						safeFire(opts.Callback, selected)
						ctl:_fire(selected)
						menu.Visible = false
					end
					self.window:_autoSave()
				end)
			end
		end
	end
	rebuild("")

	if search then
		self.window.connTracker:connect(search:GetPropertyChangedSignal("Text"), function() rebuild(search.Text) end)
	end

	local function place()
		local pos = btn.AbsolutePosition
		local size = btn.AbsoluteSize
		menu.Position = UDim2.fromOffset(pos.X, pos.Y + size.Y + 4)
		menu.Size = UDim2.fromOffset(size.X, (search and 26 or 0) + 168)
	end

	self.window.connTracker:connect(btn.MouseButton1Click, function()
		if ctl.disabled then return end
		menu.Visible = not menu.Visible
		if menu.Visible then place() end
	end)
	-- Закрытие по клику вне
	self.window.connTracker:connect(UserInputService.InputBegan, function(input)
		if menu.Visible and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			local mp = UserInputService:GetMouseLocation()
			local m1 = menu.AbsolutePosition
			local m2 = m1 + menu.AbsoluteSize
			local b1 = btn.AbsolutePosition
			local b2 = b1 + btn.AbsoluteSize
			local inMenu = mp.X >= m1.X and mp.X <= m2.X and mp.Y >= m1.Y and mp.Y <= m2.Y
			local inBtn = mp.X >= b1.X and mp.X <= b2.X and mp.Y >= b1.Y and mp.Y <= b2.Y
			if not inMenu and not inBtn then menu.Visible = false end
		end
	end)

	ctl.value = selected
	ctl.frame = row
	function ctl:Set(v, silent)
		if multi then
			selected = {}
			for _, x in ipairs(v or {}) do selected[x] = true end
		else
			selected = v
		end
		refreshLabel()
		rebuild(search and search.Text or "")
		if not silent then
			if multi then
				local out = {}
				for _, x in ipairs(items) do if selected[x] then table.insert(out, x) end end
				safeFire(opts.Callback, out); self:_fire(out)
			else
				safeFire(opts.Callback, selected); self:_fire(selected)
			end
			self.window:_autoSave()
		end
	end
	function ctl:Get()
		if multi then
			local out = {}
			for _, x in ipairs(items) do if selected[x] then table.insert(out, x) end end
			return out
		end
		return selected
	end
	function ctl:SetItems(newItems)
		items = arrayCopy(newItems)
		rebuild(search and search.Text or "")
	end
	ctl._serialize = function() return ctl:Get() end
	ctl._deserialize = function(v) ctl:Set(v, true) end
	if ctl.description then self.window:_attachTooltip(row, ctl.description) end
	return ctl
end

-- Keybind
function Section:AddKeybind(opts)
	opts = opts or {}
	local ctl = newControlBase(self, opts)
	local row = makeRow(self, 32)
	local lbl = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -120, 1, 0),
		Font = fontFor(500),
		TextSize = 12,
		Text = opts.Name or "Keybind",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyText(lbl, self.window.theme.TextSecondary)

	local btn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -56, 0.5, 0),
		Size = UDim2.fromOffset(56, 22),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = fontFor(600),
		TextSize = 11,
		ZIndex = 6,
		Parent = row,
	})
	applyFill(btn, self.window.theme.Surface)
	applyText(btn, self.window.theme.TextPrimary)
	addCorner(btn, 4)
	addStroke(btn, 1, self.window.theme.Border)

	local modeBtn = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(50, 22),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = fontFor(600),
		TextSize = 10,
		ZIndex = 6,
		Parent = row,
	})
	applyFill(modeBtn, self.window.theme.Surface)
	applyText(modeBtn, self.window.theme.TextMuted)
	addCorner(modeBtn, 4)
	addStroke(modeBtn, 1, self.window.theme.Border)

	local key = opts.Default or Enum.KeyCode.Unknown
	local mode = opts.Mode or "Toggle"
	local value = false
	btn.Text = keyName(key)
	modeBtn.Text = mode

	local kbEntry = {
		key = key,
		mode = mode,
		value = false,
		callback = opts.Callback,
		set = function(v)
			value = v
			safeFire(opts.Callback, v, key)
			ctl:_fire(v)
		end,
	}
	table.insert(self.window.keybinds, kbEntry)

	local function updateBtn()
		btn.Text = keyName(kbEntry.key)
		modeBtn.Text = kbEntry.mode
	end

	self.window.connTracker:connect(btn.MouseButton1Click, function()
		if ctl.disabled then return end
		btn.Text = "..."
		self.window.waitingForBind = function(newKey)
			-- Конфликт-детектор
			for _, kb in ipairs(self.window.keybinds) do
				if kb ~= kbEntry and kb.key == newKey then
					self.window:Notify({ Title = "Keybind conflict", Text = keyName(newKey) .. " уже используется", Type = "warning" })
				end
			end
			kbEntry.key = newKey
			updateBtn()
			self.window:_autoSave()
		end
	end)
	self.window.connTracker:connect(modeBtn.MouseButton1Click, function()
		local order = { "Toggle", "Hold", "Always" }
		local idx = 1
		for i, m in ipairs(order) do if m == kbEntry.mode then idx = i end end
		kbEntry.mode = order[(idx % #order) + 1]
		updateBtn()
		self.window:_autoSave()
	end)

	ctl.frame = row
	function ctl:Set(k, m, silent)
		if k then kbEntry.key = k end
		if m then kbEntry.mode = m end
		updateBtn()
		if not silent then self.window:_autoSave() end
	end
	function ctl:Get() return kbEntry.key, kbEntry.mode end
	ctl._serialize = function() return { key = kbEntry.key.Name, mode = kbEntry.mode } end
	ctl._deserialize = function(v)
		if v and v.key then
			local code = Enum.KeyCode[v.key]
			if code then kbEntry.key = code end
		end
		if v and v.mode then kbEntry.mode = v.mode end
		updateBtn()
	end
	if ctl.description then self.window:_attachTooltip(row, ctl.description) end
	return ctl
end

-- ColorPicker (HSV + Alpha)
function Section:AddColorPicker(opts)
	opts = opts or {}
	local ctl = newControlBase(self, opts)
	local row = makeRow(self, 36)

	local lbl = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -50, 1, 0),
		Font = fontFor(500),
		TextSize = 12,
		Text = opts.Name or "Color",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	applyText(lbl, self.window.theme.TextSecondary)

	local preview = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(36, 20),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 6,
		Parent = row,
	})
	addCorner(preview, 4)
	addStroke(preview, 1, self.window.theme.Border)

	local h, s, v, a
	local function fromHex(hex)
		local c, tr = parseHex(hex)
		h, s, v = Color3.toHSV(c)
		a = 1 - tr
	end
	fromHex(opts.Default or "#3b82f6ff")

	local function currentHex()
		return colorToHex(Color3.fromHSV(h, s, v), a)
	end
	local function paintPreview()
		local c = Color3.fromHSV(h, s, v)
		preview.BackgroundColor3 = c
		preview.BackgroundTransparency = 1 - a
	end
	paintPreview()

	-- Popup picker
	local pop = create("Frame", {
		Visible = false,
		Size = UDim2.fromOffset(220, 200),
		BorderSizePixel = 0,
		ZIndex = 50,
		Parent = self.window.screenGui,
	})
	applyFill(pop, self.window.theme.Surface)
	addCorner(pop, 6)
	addStroke(pop, 1, self.window.theme.Border)
	addPadding(pop, 8, 8, 8, 8)

	-- SV plane
	local plane = create("Frame", {
		Size = UDim2.fromOffset(204, 120),
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = pop,
	})
	addCorner(plane, 4)
	-- Color: gradient hue (horizontal) blended with white→hue, then dark overlay
	local hueGradient = create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(h, 1, 1)),
		}),
		Parent = plane,
	})
	plane.BackgroundColor3 = Color3.new(1, 1, 1)
	local darkOverlay = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 52,
		Parent = plane,
	})
	addCorner(darkOverlay, 4)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(0, 0, 0)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = darkOverlay,
	})
	local svKnob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 53,
		Parent = plane,
	})
	addCorner(svKnob, 999)
	addStroke(svKnob, 2, "#000000ff")
	local svHit = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 54,
		Parent = plane,
	})

	-- Hue bar
	local hueBar = create("Frame", {
		Position = UDim2.fromOffset(0, 128),
		Size = UDim2.fromOffset(204, 12),
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = pop,
	})
	addCorner(hueBar, 999)
	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
			ColorSequenceKeypoint.new(1/6, Color3.fromHSV(1/6, 1, 1)),
			ColorSequenceKeypoint.new(2/6, Color3.fromHSV(2/6, 1, 1)),
			ColorSequenceKeypoint.new(3/6, Color3.fromHSV(3/6, 1, 1)),
			ColorSequenceKeypoint.new(4/6, Color3.fromHSV(4/6, 1, 1)),
			ColorSequenceKeypoint.new(5/6, Color3.fromHSV(5/6, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
		}),
		Parent = hueBar,
	})
	local hueKnob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(4, 16),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 52,
		Parent = hueBar,
	})
	local hueHit = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 53,
		Parent = hueBar,
	})

	-- Alpha bar
	local alphaBar = create("Frame", {
		Position = UDim2.fromOffset(0, 148),
		Size = UDim2.fromOffset(204, 12),
		BorderSizePixel = 0,
		ZIndex = 51,
		Parent = pop,
	})
	addCorner(alphaBar, 999)
	local alphaGrad = create("UIGradient", {
		Color = ColorSequence.new(Color3.fromHSV(h, s, v)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		Parent = alphaBar,
	})
	alphaBar.BackgroundColor3 = Color3.fromHSV(h, s, v)
	local alphaKnob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(a, 0, 0.5, 0),
		Size = UDim2.fromOffset(4, 16),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 52,
		Parent = alphaBar,
	})
	local alphaHit = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 53,
		Parent = alphaBar,
	})

	-- Hex input
	local hexInput = create("TextBox", {
		Position = UDim2.fromOffset(0, 168),
		Size = UDim2.fromOffset(204, 22),
		BorderSizePixel = 0,
		Font = fontFor(500),
		TextSize = 12,
		Text = currentHex(),
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 51,
		Parent = pop,
	})
	applyFill(hexInput, self.window.theme.SurfaceAlt)
	applyText(hexInput, self.window.theme.TextPrimary)
	addCorner(hexInput, 4)

	local function repaint()
		hueGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(h, 1, 1)),
		})
		svKnob.Position = UDim2.fromScale(s, 1 - v)
		hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
		alphaKnob.Position = UDim2.new(a, 0, 0.5, 0)
		alphaBar.BackgroundColor3 = Color3.fromHSV(h, s, v)
		alphaGrad.Color = ColorSequence.new(Color3.fromHSV(h, s, v))
		hexInput.Text = currentHex()
		paintPreview()
	end
	repaint()

	local function commit(silent)
		ctl.value = currentHex()
		repaint()
		if not silent then
			safeFire(opts.Callback, ctl.value)
			ctl:_fire(ctl.value)
			self.window:_autoSave()
		end
	end

	local draggingSV, draggingHue, draggingAlpha
	self.window.connTracker:connect(svHit.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSV = true
		end
	end)
	self.window.connTracker:connect(hueHit.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingHue = true
		end
	end)
	self.window.connTracker:connect(alphaHit.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingAlpha = true
		end
	end)
	self.window.connTracker:connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if draggingSV or draggingHue or draggingAlpha then commit(false) end
			draggingSV, draggingHue, draggingAlpha = nil, nil, nil
		end
	end)
	self.window.connTracker:connect(UserInputService.InputChanged, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local pos = input.Position
		if draggingSV then
			s = math.clamp((pos.X - plane.AbsolutePosition.X) / plane.AbsoluteSize.X, 0, 1)
			v = 1 - math.clamp((pos.Y - plane.AbsolutePosition.Y) / plane.AbsoluteSize.Y, 0, 1)
			repaint()
		elseif draggingHue then
			h = math.clamp((pos.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 1)
			repaint()
		elseif draggingAlpha then
			a = math.clamp((pos.X - alphaBar.AbsolutePosition.X) / alphaBar.AbsoluteSize.X, 0, 1)
			repaint()
		end
	end)

	self.window.connTracker:connect(hexInput.FocusLost, function()
		local ok, c = pcall(function() return parseHex(hexInput.Text) end)
		if ok and c then
			fromHex(hexInput.Text)
			commit(false)
		else
			hexInput.Text = currentHex()
		end
	end)

	self.window.connTracker:connect(preview.MouseButton1Click, function()
		if ctl.disabled then return end
		pop.Visible = not pop.Visible
		if pop.Visible then
			local p = preview.AbsolutePosition
			pop.Position = UDim2.fromOffset(p.X - 184, p.Y + 24)
		end
	end)
	self.window.connTracker:connect(UserInputService.InputBegan, function(input)
		if pop.Visible and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			local mp = UserInputService:GetMouseLocation()
			local p1 = pop.AbsolutePosition; local p2 = p1 + pop.AbsoluteSize
			local b1 = preview.AbsolutePosition; local b2 = b1 + preview.AbsoluteSize
			local inPop = mp.X >= p1.X and mp.X <= p2.X and mp.Y >= p1.Y and mp.Y <= p2.Y
			local inBtn = mp.X >= b1.X and mp.X <= b2.X and mp.Y >= b1.Y and mp.Y <= b2.Y
			if not inPop and not inBtn then pop.Visible = false end
		end
	end)

	ctl.value = currentHex()
	ctl.frame = row
	function ctl:Set(hex, silent)
		fromHex(hex)
		commit(silent)
	end
	function ctl:Get() return ctl.value end
	ctl._serialize = function() return ctl.value end
	ctl._deserialize = function(v) ctl:Set(v, true) end
	if ctl.description then self.window:_attachTooltip(row, ctl.description) end
	return ctl
end

----------------------------------------------------------------
-- Public Library API
----------------------------------------------------------------

function Library:CreateWindow(config)
	return Window.new(config)
end

-- Window:Destroy
function Window:Destroy()
	if self.disposed then return end
	self.disposed = true
	self.connTracker:disconnectAll()
	pcall(function() self.tweens:tween(self.windowScale, FAST, { Scale = 0.94 }) end)
	pcall(function() self.tweens:tween(self.blur, FADE, { Size = 0 }) end)
	task.delay(0.2, function()
		pcall(function() self.screenGui:Destroy() end)
		pcall(function() self.blur:Destroy() end)
	end)
end

----------------------------------------------------------------
-- Legacy compat: Library:Create({ Title, Tabs={ {Name, Modules={ {Name, Sections={ {Controls={...}} } }} } } })
----------------------------------------------------------------

local function legacyAddControl(section, control)
	local kind = string.lower(control.Type or "toggle")
	local opts = {
		Name = control.Name,
		Description = control.Description,
		Default = control.Value or control.CurrentValue,
		Callback = control.Callback,
	}
	if kind == "slider" then
		opts.Min = control.Min or 0
		opts.Max = control.Max or 100
		opts.Increment = control.Increment or 1
		return section:AddSlider(opts)
	elseif kind == "colorpicker" then
		opts.Default = control.Value or control.CurrentValue or "#3b82f6ff"
		return section:AddColorPicker(opts)
	elseif kind == "label" then
		opts.Text = control.Content or control.Text or control.Name
		return section:AddLabel(opts)
	elseif kind == "paragraph" then
		opts.Content = control.Content or control.Text
		return section:AddParagraph(opts)
	elseif kind == "checkbox" or kind == "toggle" then
		return section:AddToggle(opts)
	elseif kind == "dropdown" then
		opts.Items = control.Items or control.Options
		return section:AddDropdown(opts)
	elseif kind == "textbox" or kind == "input" then
		opts.Placeholder = control.Placeholder
		return section:AddTextbox(opts)
	elseif kind == "keybind" then
		opts.Default = control.Value or Enum.KeyCode.Unknown
		opts.Mode = control.Mode or "Toggle"
		return section:AddKeybind(opts)
	elseif kind == "button" then
		return section:AddButton(opts)
	end
	return section:AddToggle(opts)
end

function Library:Create(cfg)
	cfg = cfg or {}
	local window = Window.new({
		Title = cfg.Title or "Sigmatik",
		Subtitle = cfg.Subtitle,
		WindowWidth = cfg.WindowWidth or 720,
		WindowHeight = cfg.WindowHeight or 480,
		Theme = cfg.ThemePreset,
		Accent = cfg.Theme and cfg.Theme.Accent,
		ToggleKey = cfg.ToggleKey,
		Watermark = cfg.Watermark,
		WatermarkText = cfg.WatermarkText,
		ConfigName = cfg.ConfigName,
		AutoSave = cfg.AutoSave,
	})

	for _, tabCfg in ipairs(cfg.Tabs or {}) do
		local tab = window:AddTab({ Name = tabCfg.Name, Icon = tabCfg.Icon })
		for _, modCfg in ipairs(tabCfg.Modules or {}) do
			-- Legacy "module" → представляем как Section с тогглом Enabled
			local modSection = tab:AddSection({ Name = modCfg.Name })
			local enableToggle = modSection:AddToggle({
				Name = "Enabled",
				Default = modCfg.Enabled,
				Callback = modCfg.Callback,
				Flag = modCfg.Flag,
			})
			for _, secCfg in ipairs(modCfg.Sections or {}) do
				local section = tab:AddSection({ Name = modCfg.Name .. " · " .. (secCfg.Name or "General") })
				for _, ctlCfg in ipairs(secCfg.Controls or {}) do
					legacyAddControl(section, ctlCfg)
				end
			end
		end
		-- Если у таба Modules нет, но есть Sections напрямую
		for _, secCfg in ipairs(tabCfg.Sections or {}) do
			local section = tab:AddSection({ Name = secCfg.Name or "General" })
			for _, ctlCfg in ipairs(secCfg.Controls or {}) do
				legacyAddControl(section, ctlCfg)
			end
		end
	end

	-- Совместимый минимальный controller-API
	local controller = {
		_window = window,
		Destroy = function(_) window:Destroy() end,
		Hide = function(_) window:Hide() end,
		Show = function(_) window:Show() end,
		Toggle = function(_) window:Toggle() end,
		Notify = function(_, opts) window:Notify(opts) end,
		SetTheme = function(_, p, a) window:SetTheme(p, a) end,
		SaveConfig = function(_, n) return window:SaveConfig(n) end,
		LoadConfig = function(_, n) return window:LoadConfig(n) end,
		GetTab = function(_, name) return window:GetTab(name) end,
	}
	return controller, window
end

return Library
