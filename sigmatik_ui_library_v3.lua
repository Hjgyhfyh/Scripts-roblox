--!nonstrict
--[[
    Sigmatik UI Library v3.0.0
    Date: 2026-04-26
    Single-file Roblox Luau UI library.

    What's new vs v2 (10 improvements):
      1.  Control base class with Janitor lifecycle, OnChanged signal, Disabled/Loading/Tooltip helpers.
      2.  Plugin API: Library:RegisterComponent + Library.Hooks (OnControlChanged, OnSave, OnLoad, OnTabSwitch).
      3.  InputDispatcher: single UIS subscription per Window with priority chain (modal>palette>dropdown>keybind>drag).
      4.  ThemeService + design tokens (color/radius/spacing/typography/shadow), 5 presets, runtime SetTheme cascading
          via bindTheme(), Theme Editor with Export/Import.
      5.  Profiles + Cloud-share: ConfigManager UI (slots New/Rename/Delete/Load/Save/Duplicate), AutoLoad by PlaceId,
          autosave debounced 300ms, ExportConfig/ImportConfig via clipboard.
      6.  Virtualized list + fuzzy debounced search (used by Dropdown / CommandPalette / global search).
      7.  Expanded components: collapsible Section, Groupbox 2-col, Tabbox nested, Modal, ContextMenu, RadioGroup,
          NumberStepper, ProgressBar, Divider, SegmentedControl, PlayerDropdown, Image.
      8.  Global Search Ctrl+F (filter all controls across tabs/sections) — distinct from Ctrl+K command palette.
      9.  A11y: Tab navigation + focus ring, Enter/Space activates, UIScale auto by viewport, ReducedMotion support,
          touch-friendly hitboxes.
     10.  Robustness: Luau-typed exports, public API validation, Save/Load returns (ok,err), BlurEffect in janitor,
          hexCache LRU(256), i18n SetLocale, Webhook integration, Logger hook.

    Backwards compatible with v2 top-level API.
]]

local TweenService    = game:GetService("TweenService")
local UserInputService= game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local Players         = game:GetService("Players")
local Lighting        = game:GetService("Lighting")
local HttpService     = game:GetService("HttpService")
local CoreGui         = game:FindService("CoreGui")

local function safeService(name)
    local ok, svc = pcall(game.GetService, game, name)
    if ok then return svc end
    return nil
end
local GuiService = safeService("GuiService")
local Stats      = safeService("Stats")

local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() and Players.LocalPlayer

----------------------------------------------------------------
-- Types ---------------------------------------------------------
----------------------------------------------------------------
export type Signal = {
    Connect: (self:any, fn:(...any)->()) -> {Disconnect:(self:any)->()},
    Fire:    (self:any, ...any) -> (),
    DisconnectAll: (self:any) -> (),
}
export type Control = {
    Set:        (self:any, value:any, silent:boolean?) -> (),
    Get:        (self:any) -> any,
    OnChanged:  (self:any, fn:(value:any)->()) -> ()->(),
    SetTooltip: (self:any, text:string?) -> (),
    SetDisabled:(self:any, disabled:boolean) -> (),
    SetLoading: (self:any, loading:boolean) -> (),
    Destroy:    (self:any) -> (),
}
export type Theme = {
    name: string,
    color: {[string]:Color3|number},
    radius: {[string]:number},
    spacing:{[string]:number},
    typography:{family:Enum.Font, size:{[string]:number}},
    shadow: {[string]:any},
}

----------------------------------------------------------------
-- Logger / Webhook ---------------------------------------------
----------------------------------------------------------------
local Logger = { fn = function(level, ...) warn("[SigmatikUI]", level, ...) end }
local function log(level, ...) pcall(Logger.fn, level, ...) end

local function tryHttpRequest(opts)
    local fns = { (syn and syn.request), (http and http.request), http_request, (fluxus and fluxus.request), request }
    for _,fn in ipairs(fns) do
        if type(fn) == "function" then
            local ok, res = pcall(fn, opts)
            if ok then return true, res end
        end
    end
    return false, "no-http-api"
end

----------------------------------------------------------------
-- Signal --------------------------------------------------------
----------------------------------------------------------------
local Signal = {} ; Signal.__index = Signal
function Signal.new()
    return setmetatable({_h={}}, Signal)
end
function Signal:Connect(fn)
    local h = {fn=fn, alive=true}
    table.insert(self._h, h)
    return { Disconnect = function() h.alive=false end }
end
function Signal:Fire(...)
    for i = #self._h, 1, -1 do
        local h = self._h[i]
        if not h.alive then table.remove(self._h, i)
        else
            local ok, err = pcall(h.fn, ...)
            if not ok then log("error", "signal handler", err) end
        end
    end
end
function Signal:DisconnectAll() self._h = {} end

----------------------------------------------------------------
-- Janitor -------------------------------------------------------
----------------------------------------------------------------
local Janitor = {} ; Janitor.__index = Janitor
function Janitor.new() return setmetatable({_t={}, _dead=false}, Janitor) end
function Janitor:Add(obj, methodOrFn)
    if self._dead then
        -- already destroyed; immediately clean
        if typeof(obj) == "Instance" then pcall(obj.Destroy, obj)
        elseif type(obj) == "function" then pcall(obj)
        elseif type(obj) == "table" and obj.Disconnect then pcall(obj.Disconnect, obj) end
        return obj
    end
    table.insert(self._t, {obj=obj, m=methodOrFn})
    return obj
end
function Janitor:Cleanup()
    if self._dead then return end
    self._dead = true
    for i = #self._t, 1, -1 do
        local e = self._t[i]
        local ok, err = pcall(function()
            if type(e.obj) == "function" then e.obj()
            elseif e.m and type(e.m) == "string" then e.obj[e.m](e.obj)
            elseif typeof(e.obj) == "RBXScriptConnection" then e.obj:Disconnect()
            elseif typeof(e.obj) == "Instance" then e.obj:Destroy()
            elseif type(e.obj) == "table" then
                if e.obj.Destroy then e.obj:Destroy()
                elseif e.obj.Disconnect then e.obj:Disconnect()
                elseif e.obj.Cleanup then e.obj:Cleanup() end
            end
        end)
        if not ok then log("warn", "janitor item", err) end
    end
    self._t = {}
end
function Janitor:Destroy() self:Cleanup() end

----------------------------------------------------------------
-- LRU cache -----------------------------------------------------
----------------------------------------------------------------
local function newLRU(cap)
    local map, order, n = {}, {}, 0
    local function get(k)
        if map[k] ~= nil then return map[k] end
        return nil
    end
    local function set(k, v)
        if map[k] == nil then
            n = n + 1
            table.insert(order, k)
            if n > cap then
                local old = table.remove(order, 1); map[old]=nil; n = n - 1
            end
        end
        map[k] = v
    end
    return { get=get, set=set }
end

----------------------------------------------------------------
-- Hex parse with LRU -------------------------------------------
----------------------------------------------------------------
local hexCache = newLRU(256)
local function parseHex(hex)
    if type(hex) ~= "string" then return Color3.new(1,1,1), 0 end
    local cached = hexCache.get(hex)
    if cached then return cached[1], cached[2] end
    local s = hex:gsub("#",""):gsub("%s+","")
    local r,g,b,a = 255,255,255,255
    if #s == 6 then
        r = tonumber(s:sub(1,2),16) or 255
        g = tonumber(s:sub(3,4),16) or 255
        b = tonumber(s:sub(5,6),16) or 255
    elseif #s == 8 then
        r = tonumber(s:sub(1,2),16) or 255
        g = tonumber(s:sub(3,4),16) or 255
        b = tonumber(s:sub(5,6),16) or 255
        a = tonumber(s:sub(7,8),16) or 255
    elseif #s == 3 then
        r = tonumber(s:sub(1,1)..s:sub(1,1),16) or 255
        g = tonumber(s:sub(2,2)..s:sub(2,2),16) or 255
        b = tonumber(s:sub(3,3)..s:sub(3,3),16) or 255
    end
    local c, t = Color3.fromRGB(r,g,b), 1 - a/255
    hexCache.set(hex, {c, t})
    return c, t
end
local function color3ToHex(c)
    return string.format("%02X%02X%02X",
        math.clamp(math.floor(c.R*255+0.5),0,255),
        math.clamp(math.floor(c.G*255+0.5),0,255),
        math.clamp(math.floor(c.B*255+0.5),0,255))
end

----------------------------------------------------------------
-- Validation ----------------------------------------------------
----------------------------------------------------------------
local function assertType(v, expected, name)
    local t = typeof(v)
    if type(expected) == "string" then
        if t ~= expected then error(("[SigmatikUI] %s: expected %s, got %s"):format(name, expected, t), 3) end
    else
        for _,e in ipairs(expected) do if t==e then return end end
        error(("[SigmatikUI] %s: expected %s, got %s"):format(name, table.concat(expected,"/"), t), 3)
    end
end

----------------------------------------------------------------
-- Fuzzy match + debounce ---------------------------------------
----------------------------------------------------------------
local function fuzzyScore(query, target)
    if not query or query == "" then return 1 end
    if not target or target == "" then return 0 end
    local q = query:lower()
    local s = target:lower()
    local qi, score, streak, lastIdx = 1, 0, 0, -1
    local prevWordBreak = true
    for i = 1, #s do
        local ch = s:sub(i,i)
        if qi <= #q and ch == q:sub(qi,qi) then
            local bonus = 1
            if i == 1 or prevWordBreak then bonus = bonus + 2 end
            if lastIdx > 0 and i - lastIdx == 1 then streak = streak + 1; bonus = bonus + streak * 0.5
            else streak = 0 end
            score = score + bonus
            lastIdx = i
            qi = qi + 1
        end
        prevWordBreak = (ch == " " or ch == "_" or ch == "-" or ch == "/")
    end
    if qi <= #q then return 0 end
    return score
end
local function debounce(ms, fn)
    local v = 0
    return function(...)
        v = v + 1
        local my = v
        local args = {...}
        task.delay(ms/1000, function()
            if my == v then fn(table.unpack(args)) end
        end)
    end
end

----------------------------------------------------------------
-- Locales / i18n -----------------------------------------------
----------------------------------------------------------------
local Locales = {
    en = {
        search = "Search...", save="Save", load="Load", cancel="Cancel", confirm="Confirm",
        keybindConflict="Keybind conflict", configLoaded="Config loaded", configSaved="Config saved",
        noResults="No results", newProfile="New profile", rename="Rename", delete="Delete",
        duplicate="Duplicate", profile="Profile", import="Import", export="Export",
        themeEditor="Theme editor", reset="Reset", apply="Apply",
        loading="Loading...", searchAll="Search all controls (Esc to close)",
        commandPalette="Command palette", players="Players", custom="Custom",
        on="ON", off="OFF",
    },
    ru = {
        search = "Поиск...", save="Сохранить", load="Загрузить", cancel="Отмена", confirm="Подтвердить",
        keybindConflict="Конфликт клавиш", configLoaded="Конфиг загружен", configSaved="Конфиг сохранён",
        noResults="Ничего не найдено", newProfile="Новый профиль", rename="Переименовать", delete="Удалить",
        duplicate="Дублировать", profile="Профиль", import="Импорт", export="Экспорт",
        themeEditor="Редактор темы", reset="Сбросить", apply="Применить",
        loading="Загрузка...", searchAll="Поиск по всем элементам (Esc — закрыть)",
        commandPalette="Палитра команд", players="Игроки", custom="Свой",
        on="ВКЛ", off="ВЫКЛ",
    }
}
local CurrentLocale = "en"
local function L(k) return (Locales[CurrentLocale] and Locales[CurrentLocale][k]) or Locales.en[k] or k end

----------------------------------------------------------------
-- Themes / tokens ----------------------------------------------
----------------------------------------------------------------
local function makeTheme(name, c)
    return {
        name = name,
        color = {
            bg            = c.bg,
            surface       = c.surface,
            surfaceHover  = c.surfaceHover,
            surfaceMuted  = c.surfaceMuted or c.surface,
            primary       = c.primary,
            accent        = c.accent or c.primary,
            text          = c.text,
            textMuted     = c.textMuted,
            border        = c.border,
            danger        = c.danger or Color3.fromRGB(220,80,80),
            success       = c.success or Color3.fromRGB(80,200,120),
            warning       = c.warning or Color3.fromRGB(230,180,70),
            overlay       = c.overlay or Color3.fromRGB(0,0,0),
        },
        radius   = { sm=4, md=8, lg=14 },
        spacing  = { xs=4, sm=8, md=12, lg=16, xl=24 },
        typography = {
            family = Enum.Font.GothamMedium,
            familyBold = Enum.Font.GothamBold,
            size = { sm=12, md=14, lg=16, xl=20 },
        },
        shadow = {
            small  = { offset=Vector2.new(0,2), blur=6,  alpha=0.18 },
            medium = { offset=Vector2.new(0,6), blur=18, alpha=0.30 },
        },
    }
end

local Themes = {
    Dark = makeTheme("Dark", {
        bg=Color3.fromRGB(18,18,22), surface=Color3.fromRGB(28,28,34), surfaceHover=Color3.fromRGB(38,38,46),
        surfaceMuted=Color3.fromRGB(24,24,30),
        primary=Color3.fromRGB(99,102,241), accent=Color3.fromRGB(139,92,246),
        text=Color3.fromRGB(232,234,240), textMuted=Color3.fromRGB(150,152,160),
        border=Color3.fromRGB(48,48,56),
    }),
    Light = makeTheme("Light", {
        bg=Color3.fromRGB(244,245,247), surface=Color3.fromRGB(255,255,255), surfaceHover=Color3.fromRGB(238,239,243),
        surfaceMuted=Color3.fromRGB(248,249,251),
        primary=Color3.fromRGB(79,70,229), accent=Color3.fromRGB(124,58,237),
        text=Color3.fromRGB(20,22,30), textMuted=Color3.fromRGB(96,98,108),
        border=Color3.fromRGB(218,220,226),
    }),
    AMOLED = makeTheme("AMOLED", {
        bg=Color3.fromRGB(0,0,0), surface=Color3.fromRGB(8,8,10), surfaceHover=Color3.fromRGB(20,20,24),
        surfaceMuted=Color3.fromRGB(4,4,6),
        primary=Color3.fromRGB(120,80,255), accent=Color3.fromRGB(200,120,255),
        text=Color3.fromRGB(240,240,240), textMuted=Color3.fromRGB(140,140,144),
        border=Color3.fromRGB(28,28,32),
    }),
    Ocean = makeTheme("Ocean", {
        bg=Color3.fromRGB(11,22,38), surface=Color3.fromRGB(18,34,55), surfaceHover=Color3.fromRGB(28,52,80),
        surfaceMuted=Color3.fromRGB(14,28,46),
        primary=Color3.fromRGB(56,189,248), accent=Color3.fromRGB(34,211,238),
        text=Color3.fromRGB(220,236,250), textMuted=Color3.fromRGB(126,160,196),
        border=Color3.fromRGB(36,62,92),
    }),
    Sunset = makeTheme("Sunset", {
        bg=Color3.fromRGB(34,18,30), surface=Color3.fromRGB(50,28,46), surfaceHover=Color3.fromRGB(70,40,64),
        surfaceMuted=Color3.fromRGB(42,22,38),
        primary=Color3.fromRGB(244,114,182), accent=Color3.fromRGB(251,146,60),
        text=Color3.fromRGB(252,232,244), textMuted=Color3.fromRGB(192,150,180),
        border=Color3.fromRGB(80,46,72),
    }),
}

----------------------------------------------------------------
-- TweenInfo helpers + ReducedMotion -----------------------------
----------------------------------------------------------------
local Anim = {
    fast   = TweenInfo.new(0.12, Enum.EasingStyle.Quad,  Enum.EasingDirection.Out),
    smooth = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
    bounce = TweenInfo.new(0.32, Enum.EasingStyle.Back,  Enum.EasingDirection.Out),
    long   = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
    instant= TweenInfo.new(0.0001, Enum.EasingStyle.Linear),
}

local ReducedMotion = false
do
    local ok, settings = pcall(function() return UserSettings():GetService("UserGameSettings") end)
    if ok and settings and settings:FindFirstChild("ReducedMotion") then
        ReducedMotion = settings.ReducedMotion == true
    end
end
local function tween(obj, info, props)
    if ReducedMotion then
        for k,v in pairs(props) do
            pcall(function() obj[k] = v end)
        end
        return nil
    end
    local tw = TweenService:Create(obj, info or Anim.smooth, props)
    tw:Play()
    return tw
end

----------------------------------------------------------------
-- Instance helpers ---------------------------------------------
----------------------------------------------------------------
local function new(class, props, children)
    local inst = Instance.new(class)
    if props then
        for k,v in pairs(props) do
            if k ~= "Parent" then
                pcall(function() inst[k] = v end)
            end
        end
        if props.Parent then inst.Parent = props.Parent end
    end
    if children then
        for _,c in ipairs(children) do c.Parent = inst end
    end
    return inst
end
local function corner(r) return new("UICorner", {CornerRadius = UDim.new(0, r or 8)}) end
local function stroke(c, t, th) return new("UIStroke", {Color=c or Color3.new(1,1,1), Transparency=t or 0.5, Thickness=th or 1, ApplyStrokeMode=Enum.ApplyStrokeMode.Border}) end
local function padding(p) p = p or 8; return new("UIPadding", {PaddingTop=UDim.new(0,p), PaddingBottom=UDim.new(0,p), PaddingLeft=UDim.new(0,p), PaddingRight=UDim.new(0,p)}) end
local function listLayout(dir, gap, halign, valign)
    return new("UIListLayout", {
        FillDirection = dir or Enum.FillDirection.Vertical,
        Padding = UDim.new(0, gap or 6),
        HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
        VerticalAlignment   = valign or Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
end

----------------------------------------------------------------
-- ThemeService --------------------------------------------------
----------------------------------------------------------------
local ThemeService = {} ; ThemeService.__index = ThemeService
function ThemeService.new(initial)
    local self = setmetatable({
        current = Themes[initial] or Themes.Dark,
        bindings = setmetatable({},{__mode="k"}), -- weak: instance -> {map, getter, janitorRef}
        Changed = Signal.new(),
    }, ThemeService)
    return self
end
function ThemeService:Get() return self.current end
function ThemeService:Set(themeOrName)
    local t = typeof(themeOrName) == "string" and Themes[themeOrName] or themeOrName
    if not t then return end
    self.current = t
    self:_apply()
    self.Changed:Fire(t)
end
function ThemeService:Bind(inst, propMap, transformer)
    -- propMap: {Property = "color.bg" or function(theme)->value}
    self.bindings[inst] = { map = propMap, transform = transformer }
    self:_applyOne(inst, propMap, transformer)
end
function ThemeService:Unbind(inst) self.bindings[inst] = nil end
function ThemeService:_resolve(path)
    local t = self.current
    for seg in tostring(path):gmatch("[^%.]+") do
        if t == nil then return nil end
        t = t[seg]
    end
    return t
end
function ThemeService:_applyOne(inst, map, transformer)
    if not inst or not inst.Parent and not inst:IsA("ScreenGui") then return end
    for prop, src in pairs(map) do
        local v
        if type(src) == "function" then v = src(self.current)
        else v = self:_resolve(src) end
        if transformer then v = transformer(prop, v, self.current) end
        if v ~= nil then pcall(function() inst[prop] = v end) end
    end
end
function ThemeService:_apply()
    for inst, def in pairs(self.bindings) do
        if typeof(inst) == "Instance" and inst.Parent ~= nil then
            self:_applyOne(inst, def.map, def.transform)
        else
            self.bindings[inst] = nil
        end
    end
end

----------------------------------------------------------------
-- InputDispatcher ----------------------------------------------
----------------------------------------------------------------
local InputDispatcher = {} ; InputDispatcher.__index = InputDispatcher
function InputDispatcher.new()
    local self = setmetatable({
        subs = { InputBegan={}, InputChanged={}, InputEnded={} },
        keybindsByKey = {},
        _conns = {},
    }, InputDispatcher)
    self._conns[1] = UserInputService.InputBegan:Connect(function(i,g) self:_dispatch("InputBegan", i, g) end)
    self._conns[2] = UserInputService.InputChanged:Connect(function(i,g) self:_dispatch("InputChanged", i, g) end)
    self._conns[3] = UserInputService.InputEnded:Connect(function(i,g) self:_dispatch("InputEnded", i, g) end)
    return self
end
function InputDispatcher:Subscribe(eventType, priority, fn)
    local list = self.subs[eventType]
    if not list then return function() end end
    local entry = { p=priority or 0, fn=fn, alive=true }
    table.insert(list, entry)
    table.sort(list, function(a,b) return a.p > b.p end)
    return function() entry.alive = false end
end
function InputDispatcher:_dispatch(t, input, gp)
    local list = self.subs[t]
    if not list then return end
    for i = #list, 1, -1 do
        if not list[i].alive then table.remove(list, i) end
    end
    for _,h in ipairs(list) do
        if h.alive then
            local ok, stop = pcall(h.fn, input, gp)
            if ok and stop == true then return end
            if not ok then log("error", "input handler", stop) end
        end
    end
end
function InputDispatcher:RegisterKeybind(keyCode, modifiers, fn, mode)
    -- mode: "Toggle"|"Hold"
    local key = tostring(keyCode)
    self.keybindsByKey[key] = self.keybindsByKey[key] or {}
    local entry = { keyCode=keyCode, modifiers=modifiers or {}, fn=fn, mode=mode or "Toggle", state=false }
    table.insert(self.keybindsByKey[key], entry)
    return entry
end
function InputDispatcher:UnregisterKeybind(entry)
    for k,list in pairs(self.keybindsByKey) do
        for i,e in ipairs(list) do
            if e == entry then table.remove(list, i); return end
        end
    end
end
function InputDispatcher:CheckKeybind(input)
    local list = self.keybindsByKey[tostring(input.KeyCode)]
    if not list then return end
    for _,e in ipairs(list) do
        local modOk = true
        for _,mod in ipairs(e.modifiers) do
            if not UserInputService:IsKeyDown(mod) then modOk = false; break end
        end
        if modOk then
            if e.mode == "Toggle" then e.state = not e.state; pcall(e.fn, e.state)
            else pcall(e.fn, true) end
        end
    end
end
function InputDispatcher:Destroy()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    self.subs = {InputBegan={}, InputChanged={}, InputEnded={}}
    self.keybindsByKey = {}
end

----------------------------------------------------------------
-- VirtualList --------------------------------------------------
----------------------------------------------------------------
local VirtualList = {} ; VirtualList.__index = VirtualList
function VirtualList.new(parent, itemHeight, renderItem)
    local self = setmetatable({
        parent = parent,
        itemHeight = itemHeight,
        renderItem = renderItem,
        items = {},
        filtered = {},
        pool = {},
        used = {},
        query = "",
    }, VirtualList)
    self.scroll = parent
    self.scroll.CanvasSize = UDim2.new(0,0,0,0)
    self._conn = self.scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function() self:_render() end)
    self._sizeConn = self.scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:_render() end)
    return self
end
function VirtualList:SetItems(list)
    self.items = list or {}
    self:_recompute()
end
function VirtualList:SetFilter(q)
    self.query = q or ""
    self:_recompute()
end
function VirtualList:_recompute()
    if self.query == "" then
        self.filtered = self.items
    else
        local scored = {}
        for _,it in ipairs(self.items) do
            local s = fuzzyScore(self.query, tostring(it.label or it.text or it))
            if s > 0 then table.insert(scored, {it=it, s=s}) end
        end
        table.sort(scored, function(a,b) return a.s > b.s end)
        self.filtered = {}
        for _,e in ipairs(scored) do table.insert(self.filtered, e.it) end
    end
    self.scroll.CanvasSize = UDim2.new(0, 0, 0, #self.filtered * self.itemHeight)
    self:_render()
end
function VirtualList:_render()
    local first = math.max(1, math.floor(self.scroll.CanvasPosition.Y / self.itemHeight) - 4)
    local visible = math.ceil(self.scroll.AbsoluteSize.Y / self.itemHeight) + 8
    local last = math.min(#self.filtered, first + visible)
    local seen = {}
    for i = first, last do
        local item = self.filtered[i]
        if item then
            local btn = self.used[i] or table.remove(self.pool)
            if not btn then
                btn = self.renderItem(nil, item, i)
                btn.Parent = self.scroll
            else
                self.renderItem(btn, item, i)
            end
            btn.Position = UDim2.new(0, 0, 0, (i-1)*self.itemHeight)
            btn.Visible = true
            self.used[i] = btn
            seen[i] = true
        end
    end
    for i, b in pairs(self.used) do
        if not seen[i] then
            b.Visible = false
            table.insert(self.pool, b)
            self.used[i] = nil
        end
    end
end
function VirtualList:Destroy()
    if self._conn then self._conn:Disconnect() end
    if self._sizeConn then self._sizeConn:Disconnect() end
    for _,b in pairs(self.used) do b:Destroy() end
    for _,b in ipairs(self.pool) do b:Destroy() end
    self.used = {} ; self.pool = {}
end

----------------------------------------------------------------
-- Library skeleton + Hooks -------------------------------------
----------------------------------------------------------------
local Library = {}
Library.__index = Library
Library._version = "3.0.0"
Library._components = {}      -- registered factories
Library._windows = {}
Library._theme = ThemeService.new("Dark")
Library.ReducedMotion = ReducedMotion
Library.Hooks = {
    OnControlChanged = Signal.new(),
    OnSave           = Signal.new(),
    OnLoad           = Signal.new(),
    OnTabSwitch      = Signal.new(),
    OnThemeChanged   = Signal.new(),
}

function Library:SetLogger(fn) Logger.fn = fn end
function Library:SetLocale(loc) if Locales[loc] then CurrentLocale = loc end end
function Library:RegisterTheme(name, tokens) Themes[name] = tokens end
function Library:GetThemes() local list = {} ; for k in pairs(Themes) do table.insert(list,k) end; table.sort(list); return list end
function Library:SetTheme(themeOrName)
    Library._theme:Set(themeOrName)
    Library.Hooks.OnThemeChanged:Fire(Library._theme:Get())
end
function Library:GetTheme() return Library._theme:Get() end

local Webhook = { url = nil }
function Library:SetWebhook(url) Webhook.url = url end
function Library:SendWebhook(content)
    if not Webhook.url then return false, "no-url" end
    local body = HttpService:JSONEncode({ content = tostring(content) })
    return tryHttpRequest({
        Url = Webhook.url, Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = body,
    })
end

function Library:RegisterComponent(name, factory)
    assertType(name, "string", "RegisterComponent.name")
    assertType(factory, "function", "RegisterComponent.factory")
    Library._components[name:lower()] = factory
end

----------------------------------------------------------------
-- Mount target -------------------------------------------------
----------------------------------------------------------------
local function getParentGui()
    if RunService:IsStudio() then
        return LocalPlayer:WaitForChild("PlayerGui")
    end
    if CoreGui then
        local ok = pcall(function() return CoreGui:GetChildren() end)
        if ok then return CoreGui end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

----------------------------------------------------------------
-- Control base class -------------------------------------------
----------------------------------------------------------------
local Control = {} ; Control.__index = Control
function Control.new(opts, window)
    local self = setmetatable({
        opts        = opts or {},
        window      = window,
        _janitor    = Janitor.new(),
        _value      = nil,
        _disabled   = false,
        _loading    = false,
        _changed    = Signal.new(),
        _flag       = (opts and (opts.Flag or opts.Name)) or nil,
        _focusable  = true,
    }, Control)
    self._janitor:Add(self._changed, "DisconnectAll")
    return self
end
function Control:_fire(v)
    self._changed:Fire(v)
    Library.Hooks.OnControlChanged:Fire(self, v)
    if self.window and self.window.autoSaveEnabled then self.window:_autoSaveDebounced() end
end
function Control:Get() return self._value end
function Control:Set(v, silent)
    self._value = v
    if not silent then self:_fire(v) end
end
function Control:OnChanged(fn)
    local h = self._changed:Connect(fn)
    return function() h:Disconnect() end
end
function Control:SetTooltip(text)
    self._tooltipText = text
    if self.window and self._tooltipTarget then self.window:_attachTooltip(self._tooltipTarget, text) end
end
function Control:SetDisabled(b)
    self._disabled = b and true or false
    if self._frame then
        self._frame.Active = not self._disabled
        if self._frame:FindFirstChild("Hitbox") then self._frame.Hitbox.Active = not self._disabled end
    end
    if self._frame then
        for _,d in ipairs(self._frame:GetDescendants()) do
            if d:IsA("TextButton") or d:IsA("ImageButton") or d:IsA("TextBox") then
                pcall(function() d.Active = not self._disabled end)
                pcall(function() if d:IsA("TextBox") then d.TextEditable = not self._disabled end end)
            end
        end
        tween(self._frame, Anim.fast, { BackgroundTransparency = self._disabled and 0.5 or 0 })
    end
end
function Control:SetLoading(b)
    self._loading = b and true or false
    if self._loader then self._loader.Visible = self._loading end
    if self._loading then
        if self._loaderConn then self._loaderConn:Disconnect() end
        local rot = 0
        self._loaderConn = RunService.Heartbeat:Connect(function(dt)
            rot = (rot + dt*360) % 360
            if self._loader then self._loader.Rotation = rot end
        end)
        self._janitor:Add(self._loaderConn)
    elseif self._loaderConn then
        self._loaderConn:Disconnect(); self._loaderConn = nil
    end
end
function Control:Destroy()
    if self._frame then self._frame.Parent = nil end
    self._janitor:Cleanup()
    if self._frame then self._frame:Destroy() end
end

----------------------------------------------------------------
-- Component factory helpers ------------------------------------
----------------------------------------------------------------
local function makeRow(parent, height)
    local row = new("Frame", {
        Name = "Row",
        Size = UDim2.new(1, 0, 0, height or 36),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    new("UIPadding", { PaddingLeft=UDim.new(0,10), PaddingRight=UDim.new(0,10), PaddingTop=UDim.new(0,4), PaddingBottom=UDim.new(0,4), Parent = row })
    return row
end

local function bindHover(theme, btn, baseToken, hoverToken)
    btn.MouseEnter:Connect(function()
        local v = baseToken and theme:_resolve(hoverToken) or nil
        if v then tween(btn, Anim.fast, { BackgroundColor3 = v }) end
    end)
    btn.MouseLeave:Connect(function()
        local v = baseToken and theme:_resolve(baseToken) or nil
        if v then tween(btn, Anim.fast, { BackgroundColor3 = v }) end
    end)
end

----------------------------------------------------------------
-- Window -------------------------------------------------------
----------------------------------------------------------------
local Window = {} ; Window.__index = Window

function Library:CreateWindow(opts)
    opts = opts or {}
    assertType(opts, "table", "CreateWindow.opts")
    if opts.Theme then Library._theme:Set(opts.Theme) end
    local theme = Library._theme

    local w = setmetatable({
        opts = opts,
        title = opts.Name or opts.Title or "Sigmatik UI",
        subtitle = opts.SubTitle or ("v" .. Library._version),
        tabs = {},
        _activeTab = nil,
        _janitor = Janitor.new(),
        keybindsList = {}, -- list of keybind controls for "ToggleUI" etc
        _searchOpen = false,
        _paletteOpen = false,
        autoSaveEnabled = opts.AutoSave ~= false,
        configManager = opts.ConfigManager ~= false,
        autoLoadConfig = opts.AutoLoadConfig, -- string slot name
        _flagControls = {},
        _focusables = {},
        _focusIndex = 0,
        theme = theme,
    }, Window)

    w.dispatcher = InputDispatcher.new()
    w._janitor:Add(w.dispatcher)

    local screenGui = new("ScreenGui", {
        Name = "SigmatikUIv3_" .. tostring(math.random(100000, 999999)),
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 1000,
    })
    screenGui.Parent = getParentGui()
    w.screenGui = screenGui
    w._janitor:Add(screenGui)

    -- Blur effect
    local blur = new("BlurEffect", { Name = "SigmatikUIv3_Blur_" .. tostring(math.random(1000,9999)), Size = 0, Parent = Lighting })
    w.blur = blur
    w._janitor:Add(blur)
    if opts.Blur ~= false then tween(blur, Anim.long, { Size = 12 }) end

    -- Main frame
    local size = opts.Size or UDim2.fromOffset(640, 460)
    local main = new("Frame", {
        Name = "Main",
        Parent = screenGui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = opts.Position or UDim2.fromScale(0.5, 0.5),
        Size = size,
        BackgroundColor3 = theme:Get().color.bg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    })
    corner(theme:Get().radius.lg).Parent = main
    local mainStroke = stroke(theme:Get().color.border, 0.4, 1) ; mainStroke.Parent = main
    theme:Bind(main, { BackgroundColor3 = "color.bg" })
    theme:Bind(mainStroke, { Color = "color.border" })
    w.main = main

    -- UIScale (a11y / responsive)
    local scale = new("UIScale", { Scale = 1, Parent = main })
    w.scale = scale

    -- Title bar
    local titleBar = new("Frame", {
        Name = "TitleBar", Parent = main,
        BackgroundColor3 = theme:Get().color.surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 40),
    })
    theme:Bind(titleBar, { BackgroundColor3 = "color.surface" })
    new("UIPadding", { PaddingLeft = UDim.new(0,12), PaddingRight = UDim.new(0,8), Parent = titleBar })

    local titleLabel = new("TextLabel", {
        Parent = titleBar, BackgroundTransparency = 1,
        Size = UDim2.new(1, -120, 1, 0),
        Font = theme:Get().typography.familyBold, TextSize = 16,
        TextColor3 = theme:Get().color.text, TextXAlignment = Enum.TextXAlignment.Left,
        Text = w.title,
    })
    theme:Bind(titleLabel, { TextColor3 = "color.text" })

    local subLabel = new("TextLabel", {
        Parent = titleBar, BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, -120, 0, 14),
        Font = theme:Get().typography.family, TextSize = 11,
        TextColor3 = theme:Get().color.textMuted, TextXAlignment = Enum.TextXAlignment.Left,
        Text = w.subtitle,
    })
    theme:Bind(subLabel, { TextColor3 = "color.textMuted" })

    -- Title buttons (config gear, theme, search, close)
    local btnRow = new("Frame", { Parent = titleBar, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 130, 1, -8) })
    new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
        HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = btnRow })

    local function makeIconBtn(label, callback)
        local b = new("TextButton", {
            Parent = btnRow, AutoButtonColor = false,
            BackgroundColor3 = theme:Get().color.surfaceHover, BorderSizePixel = 0,
            Size = UDim2.new(0, 28, 0, 28),
            Font = theme:Get().typography.family, TextSize = 12,
            TextColor3 = theme:Get().color.text, Text = label,
        })
        corner(6).Parent = b
        theme:Bind(b, { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })
        b.MouseButton1Click:Connect(callback)
        return b
    end
    local searchBtn = makeIconBtn("⌕", function() w:ToggleGlobalSearch() end)
    if w.configManager then
        makeIconBtn("⚙", function() w:OpenConfigManager() end)
    end
    makeIconBtn("◐", function() w:OpenThemeMenu() end)
    makeIconBtn("✕", function() w:ToggleVisibility(false) end)

    -- Sidebar (tabs)
    local sidebar = new("Frame", {
        Name = "Sidebar", Parent = main,
        Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(0, 160, 1, -40),
        BackgroundColor3 = theme:Get().color.surfaceMuted, BorderSizePixel = 0,
    })
    theme:Bind(sidebar, { BackgroundColor3 = "color.surfaceMuted" })
    new("UIPadding", { PaddingTop=UDim.new(0,8), PaddingBottom=UDim.new(0,8), PaddingLeft=UDim.new(0,8), PaddingRight=UDim.new(0,8), Parent = sidebar })
    local tabsList = new("Frame", { Parent = sidebar, BackgroundTransparency = 1, Size = UDim2.new(1,0,1,0) })
    listLayout(Enum.FillDirection.Vertical, 4).Parent = tabsList
    w.tabsList = tabsList

    -- Content area
    local content = new("Frame", {
        Name = "Content", Parent = main,
        Position = UDim2.new(0, 160, 0, 40), Size = UDim2.new(1, -160, 1, -40),
        BackgroundTransparency = 1, ClipsDescendants = true,
    })
    w.content = content

    -- Resize handle
    local resize = new("ImageButton", {
        Parent = main, BackgroundTransparency = 1, AutoButtonColor = false,
        AnchorPoint = Vector2.new(1,1), Position = UDim2.new(1, -2, 1, -2),
        Size = UDim2.new(0, 22, 0, 22), Image = "",
    })
    local resizeMark = new("TextLabel", {
        Parent = resize, BackgroundTransparency = 1, Size = UDim2.new(1,0,1,0),
        Text = "◢", Font = theme:Get().typography.familyBold, TextSize = 16,
        TextColor3 = theme:Get().color.textMuted, TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Bottom,
    })
    theme:Bind(resizeMark, { TextColor3 = "color.textMuted" })

    -- Drag state
    w._drag = { active=false, start=nil, startPos=nil }
    w._resize = { active=false, start=nil, startSize=nil }

    -- Drag (titlebar) — handled via dispatcher
    titleBar.InputBegan:Connect(function(input)
        if w._disabled then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            w._drag.active = true
            w._drag.start = input.Position
            w._drag.startPos = main.Position
        end
    end)
    titleBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            w._drag.active = false
        end
    end)
    -- Resize
    resize.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            w._resize.active = true
            w._resize.start = input.Position
            w._resize.startSize = main.AbsoluteSize
        end
    end)
    resize.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            w._resize.active = false
        end
    end)
    w._janitor:Add(w.dispatcher:Subscribe("InputChanged", 20, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if w._drag.active then
                local d = input.Position - w._drag.start
                main.Position = UDim2.new(w._drag.startPos.X.Scale, w._drag.startPos.X.Offset + d.X,
                                          w._drag.startPos.Y.Scale, w._drag.startPos.Y.Offset + d.Y)
            elseif w._resize.active then
                local d = input.Position - w._resize.start
                main.Size = UDim2.fromOffset(
                    math.max(420, w._resize.startSize.X + d.X),
                    math.max(280, w._resize.startSize.Y + d.Y))
            end
        end
    end))

    -- Global keybinds: Ctrl+K (palette), Ctrl+F (search), Tab navigation
    w._janitor:Add(w.dispatcher:Subscribe("InputBegan", 80, function(input, gp)
        if gp then return end
        local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        if ctrl and input.KeyCode == Enum.KeyCode.K then
            w:ToggleCommandPalette(); return true
        elseif input.KeyCode == Enum.KeyCode.K and not ctrl then
            local focused = UserInputService:GetFocusedTextBox()
            if not focused then w:ToggleVisibility(); return true end
        elseif ctrl and input.KeyCode == Enum.KeyCode.F then
            w:ToggleGlobalSearch(); return true
        elseif input.KeyCode == Enum.KeyCode.Escape then
            if w._modalOpen then w:CloseModal(); return true end
            if w._paletteOpen then w:CloseCommandPalette(); return true end
            if w._searchOpen then w:CloseGlobalSearch(); return true end
        elseif input.KeyCode == Enum.KeyCode.Tab then
            w:_focusNext(UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)); return true
        elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
            local f = w._focusables[w._focusIndex]
            if f and f.activate then pcall(f.activate); return true end
        end
        -- Custom keybinds
        w.dispatcher:CheckKeybind(input)
    end))

    -- Watermark + FPS (throttled)
    w._watermarkLabel = new("TextLabel", {
        Parent = screenGui, BackgroundColor3 = theme:Get().color.surface, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0,0), Position = UDim2.new(0, 12, 0, 12),
        Size = UDim2.new(0, 180, 0, 24),
        Font = theme:Get().typography.family, TextSize = 12,
        TextColor3 = theme:Get().color.text, Text = w.title,
        Visible = opts.Watermark == true,
    })
    corner(6).Parent = w._watermarkLabel
    theme:Bind(w._watermarkLabel, { BackgroundColor3 = "color.surface", TextColor3 = "color.text" })

    do
        local accFps, samples, accTime = 0, 0, 0
        local fpsAvg = 60
        w._janitor:Add(RunService.Heartbeat:Connect(function(dt)
            accFps = accFps + 1/dt; samples = samples + 1; accTime = accTime + dt
            if accTime >= 0.5 then
                fpsAvg = accFps / samples
                accFps, samples, accTime = 0, 0, 0
                if w._watermarkLabel.Visible then
                    local ping = "—"
                    if Stats then
                        local pp = Stats:FindFirstChild("PerformanceStats") and Stats.PerformanceStats:FindFirstChild("Ping")
                        if pp then ping = ("%dms"):format(math.floor(pp:GetValue())) end
                    end
                    w._watermarkLabel.Text = ("%s · %d fps · %s"):format(w.title, math.floor(fpsAvg), ping)
                end
                if w._tooltip and w._tooltip.Visible then
                    local mp = UserInputService:GetMouseLocation()
                    w._tooltip.Position = UDim2.fromOffset(mp.X + 14, mp.Y + 18)
                end
            end
        end))
    end

    -- Tooltip
    local tip = new("TextLabel", {
        Parent = screenGui, BackgroundColor3 = theme:Get().color.surface, BorderSizePixel = 0,
        Visible = false, AutomaticSize = Enum.AutomaticSize.XY,
        Font = theme:Get().typography.family, TextSize = 12, TextColor3 = theme:Get().color.text,
        Text = "", ZIndex = 200,
    })
    corner(6).Parent = tip
    new("UIPadding", { PaddingLeft=UDim.new(0,8), PaddingRight=UDim.new(0,8), PaddingTop=UDim.new(0,4), PaddingBottom=UDim.new(0,4), Parent = tip })
    theme:Bind(tip, { BackgroundColor3 = "color.surface", TextColor3 = "color.text" })
    w._tooltip = tip

    -- Notifications container
    local notifContainer = new("Frame", {
        Parent = screenGui, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.new(0, 320, 1, -32),
    })
    new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder, Parent = notifContainer })
    w._notifContainer = notifContainer

    -- Modal layer
    local modalLayer = new("Frame", {
        Parent = screenGui, BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 1,
        Size = UDim2.fromScale(1,1), Visible = false, ZIndex = 300,
    })
    w._modalLayer = modalLayer

    -- Adaptive UIScale
    local function applyScale()
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        local s
        if vp.X < 600 then s = 0.8
        elseif vp.X < 900 then s = 0.9
        elseif vp.X < 1400 then s = 1.0
        elseif vp.X >= 1920 then s = 1.1
        else s = 1.0 end
        scale.Scale = s
    end
    applyScale()
    if workspace.CurrentCamera then
        w._janitor:Add(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale))
    end

    -- Connection tracker
    w._janitor:Add(function() Library._theme:Unbind(main); Library._theme:Unbind(mainStroke) end)
    Library._windows[#Library._windows+1] = w

    -- Auto-save debouncer
    w._autoSaveDebounced = debounce(300, function()
        if w.autoSaveEnabled and w._currentProfile then
            w:SaveConfig(w._currentProfile)
        end
    end)

    -- Auto-load profile
    if w.autoLoadConfig then
        task.delay(0.1, function() w:LoadConfig(w.autoLoadConfig) end)
    end

    return w
end

----------------------------------------------------------------
-- Tooltip attach -----------------------------------------------
----------------------------------------------------------------
function Window:_attachTooltip(target, text)
    if not text or text == "" then return end
    local tip = self._tooltip
    target.MouseEnter:Connect(function()
        tip.Text = text
        tip.Visible = true
        local mp = UserInputService:GetMouseLocation()
        tip.Position = UDim2.fromOffset(mp.X + 14, mp.Y + 18)
    end)
    target.MouseLeave:Connect(function() tip.Visible = false end)
end

----------------------------------------------------------------
-- Notify -------------------------------------------------------
----------------------------------------------------------------
function Window:Notify(opts)
    opts = opts or {}
    if type(opts) == "string" then opts = { Title = opts } end
    local theme = self.theme:Get()
    local frame = new("Frame", {
        Parent = self._notifContainer, BackgroundColor3 = theme.color.surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        ClipsDescendants = true,
    })
    corner(8).Parent = frame
    local accent = new("Frame", { Parent = frame, BackgroundColor3 = theme.color.primary, BorderSizePixel = 0,
        Size = UDim2.new(0, 3, 1, 0) })
    if opts.Type == "success" then accent.BackgroundColor3 = theme.color.success
    elseif opts.Type == "warning" then accent.BackgroundColor3 = theme.color.warning
    elseif opts.Type == "error" then accent.BackgroundColor3 = theme.color.danger end
    new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = frame })
    new("UIListLayout", { Padding = UDim.new(0, 4), Parent = frame })
    new("TextLabel", {
        Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18),
        Font = theme.typography.familyBold, TextSize = 14, TextColor3 = theme.color.text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(opts.Title or ""),
    })
    if opts.Content then
        new("TextLabel", {
            Parent = frame, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.textMuted,
            TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
            Text = tostring(opts.Content):sub(1, 500),
        })
    end
    -- progress bar of duration
    local duration = opts.Duration or 4
    local bar = new("Frame", { Parent = frame, BackgroundColor3 = theme.color.primary, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0,1), Position = UDim2.new(0,0,1,0), Size = UDim2.new(1,0,0,2) })
    tween(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) })
    task.delay(duration, function()
        local out = tween(frame, Anim.smooth, { BackgroundTransparency = 1 })
        task.delay(0.25, function() pcall(function() frame:Destroy() end) end)
    end)
    return frame
end

----------------------------------------------------------------
-- Tab ----------------------------------------------------------
----------------------------------------------------------------
local Tab = {} ; Tab.__index = Tab

function Window:AddTab(opts)
    opts = opts or {}
    if type(opts) == "string" then opts = { Name = opts } end
    assertType(opts, "table", "AddTab.opts")
    local name = tostring(opts.Name or "Tab")
    local theme = self.theme:Get()

    local btn = new("TextButton", {
        Parent = self.tabsList, AutoButtonColor = false,
        BackgroundColor3 = theme.color.surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 32),
        Font = theme.typography.family, TextSize = 13, TextColor3 = theme.color.textMuted,
        Text = (opts.Icon and (opts.Icon .. "  ") or "") .. name,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    corner(6).Parent = btn
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = btn })
    self.theme:Bind(btn, { BackgroundColor3 = "color.surface", TextColor3 = "color.textMuted" })

    local page = new("ScrollingFrame", {
        Parent = self.content, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0), Visible = false,
        ScrollBarThickness = 4, ScrollBarImageColor3 = theme.color.border,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    })
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = page })
    listLayout(Enum.FillDirection.Vertical, 8).Parent = page

    local tab = setmetatable({
        window = self, name = name, btn = btn, page = page, sections = {}, _janitor = Janitor.new(),
    }, Tab)

    btn.MouseButton1Click:Connect(function() self:SelectTab(tab) end)
    btn.MouseEnter:Connect(function() if self._activeTab ~= tab then tween(btn, Anim.fast, { BackgroundColor3 = self.theme:Get().color.surfaceHover }) end end)
    btn.MouseLeave:Connect(function() if self._activeTab ~= tab then tween(btn, Anim.fast, { BackgroundColor3 = self.theme:Get().color.surface }) end end)

    table.insert(self.tabs, tab)
    if not self._activeTab then self:SelectTab(tab) end

    -- Register focusable
    table.insert(self._focusables, { instance = btn, activate = function() self:SelectTab(tab) end })

    return tab
end

function Window:SelectTab(tab)
    for _,t in ipairs(self.tabs) do
        t.page.Visible = (t == tab)
        if t == tab then
            self.theme:Bind(t.btn, { BackgroundColor3 = "color.primary", TextColor3 = function(th) return Color3.new(1,1,1) end })
        else
            self.theme:Bind(t.btn, { BackgroundColor3 = "color.surface", TextColor3 = "color.textMuted" })
        end
    end
    self._activeTab = tab
    Library.Hooks.OnTabSwitch:Fire(tab)
end

----------------------------------------------------------------
-- Section ------------------------------------------------------
----------------------------------------------------------------
local Section = {} ; Section.__index = Section

function Tab:AddSection(opts)
    opts = opts or {}
    if type(opts) == "string" then opts = { Name = opts } end
    assertType(opts, "table", "AddSection.opts")
    local theme = self.window.theme:Get()
    local name = tostring(opts.Name or "Section")

    local container = new("Frame", {
        Parent = self.page, BackgroundColor3 = theme.color.surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    })
    corner(8).Parent = container
    local sStroke = stroke(theme.color.border, 0.5, 1) ; sStroke.Parent = container
    self.window.theme:Bind(container, { BackgroundColor3 = "color.surface" })
    self.window.theme:Bind(sStroke, { Color = "color.border" })
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), Parent = container })

    local header = new("TextButton", {
        Parent = container, BackgroundTransparency = 1, AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, 22),
        Font = theme.typography.familyBold, TextSize = 13, TextColor3 = theme.color.text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = name,
    })
    self.window.theme:Bind(header, { TextColor3 = "color.text" })

    local body = new("Frame", { Parent = container, BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 28), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    listLayout(Enum.FillDirection.Vertical, 6).Parent = body

    local section = setmetatable({
        window = self.window, tab = self, name = name, container = container, body = body, header = header,
        controls = {}, collapsed = false, _janitor = Janitor.new(),
    }, Section)

    if opts.Collapsible then section:SetCollapsible(true) end
    table.insert(self.sections, section)
    return section
end

function Section:SetCollapsible(b)
    if not b then return end
    self.collapsible = true
    self.header.Text = (self.collapsed and "▸  " or "▾  ") .. self.name
    self.header.MouseButton1Click:Connect(function() self:Toggle() end)
end
function Section:Collapse()
    if not self.collapsible then return end
    self.collapsed = true
    self.body.Visible = false
    self.header.Text = "▸  " .. self.name
end
function Section:Expand()
    if not self.collapsible then return end
    self.collapsed = false
    self.body.Visible = true
    self.header.Text = "▾  " .. self.name
end
function Section:Toggle() if self.collapsed then self:Expand() else self:Collapse() end end

----------------------------------------------------------------
-- Section: makeControlBase + helpers ---------------------------
----------------------------------------------------------------
function Section:_register(ctl)
    table.insert(self.controls, ctl)
    if ctl._flag then self.window._flagControls[ctl._flag] = ctl end
    -- focusable
    if ctl._focusTarget then
        table.insert(self.window._focusables, { instance = ctl._focusTarget, activate = ctl._activate })
    end
    return ctl
end

local function rowFrame(parent, h, theme, themeService)
    local f = new("Frame", { Parent = parent, BackgroundColor3 = theme.color.surfaceMuted, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, h or 36) })
    corner(6).Parent = f
    themeService:Bind(f, { BackgroundColor3 = "color.surfaceMuted" })
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = f })
    return f
end

local function labelOf(parent, text, theme, themeService, bold)
    local lbl = new("TextLabel", { Parent = parent, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0.6, 0, 1, 0),
        Font = bold and theme.typography.familyBold or theme.typography.family, TextSize = 13,
        TextColor3 = theme.color.text, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(text) })
    themeService:Bind(lbl, { TextColor3 = "color.text" })
    return lbl
end

----------------------------------------------------------------
-- Components: Button -------------------------------------------
----------------------------------------------------------------
function Section:AddButton(opts)
    opts = opts or {} ; if type(opts) == "string" then opts = { Name = opts } end
    assertType(opts, "table", "AddButton.opts")
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)

    local frame = rowFrame(self.body, 36, theme, self.window.theme)
    local btn = new("TextButton", { Parent = frame, AutoButtonColor = false,
        BackgroundColor3 = theme.color.primary, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, -8), Position = UDim2.new(0, 0, 0, 4),
        Font = theme.typography.familyBold, TextSize = 13, TextColor3 = Color3.new(1,1,1),
        Text = tostring(opts.Name or "Button") })
    corner(6).Parent = btn
    self.window.theme:Bind(btn, { BackgroundColor3 = "color.primary" })

    btn.MouseEnter:Connect(function() tween(btn, Anim.fast, { BackgroundColor3 = self.window.theme:Get().color.accent }) end)
    btn.MouseLeave:Connect(function() tween(btn, Anim.fast, { BackgroundColor3 = self.window.theme:Get().color.primary }) end)
    btn.MouseButton1Click:Connect(function()
        if ctl._disabled then return end
        ctl:_fire(true)
        if opts.Callback then pcall(opts.Callback) end
    end)

    ctl._frame = frame ; ctl._tooltipTarget = btn ; ctl._focusTarget = btn ; ctl._activate = function() btn:Activate() ; if opts.Callback then pcall(opts.Callback) end end
    if opts.Tooltip then self.window:_attachTooltip(btn, opts.Tooltip) end
    return self:_register(ctl)
end

----------------------------------------------------------------
-- Toggle -------------------------------------------------------
----------------------------------------------------------------
function Section:AddToggle(opts)
    opts = opts or {} ; if type(opts) == "string" then opts = { Name = opts } end
    assertType(opts, "table", "AddToggle.opts")
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    ctl._value = opts.Default == true

    local frame = rowFrame(self.body, 32, theme, self.window.theme)
    labelOf(frame, opts.Name or "Toggle", theme, self.window.theme)

    local switch = new("TextButton", { Parent = frame, AutoButtonColor = false,
        BackgroundColor3 = theme.color.border, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 38, 0, 20), Text = "" })
    corner(10).Parent = switch
    self.window.theme:Bind(switch, { BackgroundColor3 = function(t) return ctl._value and t.color.primary or t.color.border end })

    local knob = new("Frame", { Parent = switch, BackgroundColor3 = Color3.new(1,1,1), BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0),
        Size = UDim2.new(0, 16, 0, 16) })
    corner(8).Parent = knob

    local function repaint()
        local t = self.window.theme:Get()
        tween(switch, Anim.fast, { BackgroundColor3 = ctl._value and t.color.primary or t.color.border })
        tween(knob, Anim.fast, { Position = ctl._value and UDim2.new(1, -18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) })
    end
    repaint()

    function ctl:Set(v, silent)
        self._value = v and true or false
        repaint()
        if not silent then self:_fire(self._value) ; if opts.Callback then pcall(opts.Callback, self._value) end end
    end
    function ctl:_serialize() return self._value end
    function ctl:_deserialize(v) if type(v)=="boolean" then self:Set(v) end end

    switch.MouseButton1Click:Connect(function() if not ctl._disabled then ctl:Set(not ctl._value) end end)
    Library.Hooks.OnThemeChanged:Connect(repaint)

    ctl._frame = frame ; ctl._tooltipTarget = frame ; ctl._focusTarget = switch ; ctl._activate = function() ctl:Set(not ctl._value) end
    if opts.Tooltip then self.window:_attachTooltip(frame, opts.Tooltip) end
    return self:_register(ctl)
end

----------------------------------------------------------------
-- Slider -------------------------------------------------------
----------------------------------------------------------------
function Section:AddSlider(opts)
    opts = opts or {}
    assertType(opts, "table", "AddSlider.opts")
    local mn = tonumber(opts.Min) or 0
    local mx = tonumber(opts.Max) or 100
    if mx < mn then error("[SigmatikUI] Slider Max < Min", 2) end
    local step = tonumber(opts.Increment) or 1
    if step <= 0 then error("[SigmatikUI] Slider Increment must be > 0", 2) end
    local function clampRound(v)
        v = math.clamp(v, mn, mx)
        return math.floor((v - mn) / step + 0.5) * step + mn
    end
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    ctl._value = clampRound(tonumber(opts.Default) or mn)

    local frame = rowFrame(self.body, 50, theme, self.window.theme)
    new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = frame })

    local lbl = new("TextLabel", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, -60, 0, 14),
        Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(opts.Name or "Slider") })
    self.window.theme:Bind(lbl, { TextColor3 = "color.text" })
    local valLbl = new("TextLabel", { Parent = frame, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 60, 0, 14),
        Font = theme.typography.familyBold, TextSize = 12, TextColor3 = theme.color.textMuted,
        TextXAlignment = Enum.TextXAlignment.Right, Text = "" })
    self.window.theme:Bind(valLbl, { TextColor3 = "color.textMuted" })

    local track = new("Frame", { Parent = frame, BackgroundColor3 = theme.color.border, BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(1, 0, 0, 6) })
    corner(3).Parent = track
    self.window.theme:Bind(track, { BackgroundColor3 = "color.border" })
    local fill = new("Frame", { Parent = track, BackgroundColor3 = theme.color.primary, BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0) })
    corner(3).Parent = fill
    self.window.theme:Bind(fill, { BackgroundColor3 = "color.primary" })
    local hitbox = new("TextButton", { Parent = track, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 0.5, -10), Text = "", AutoButtonColor = false })

    local function repaint()
        local pct = (ctl._value - mn) / math.max(mx - mn, 1e-9)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        valLbl.Text = (opts.Suffix and tostring(ctl._value) .. opts.Suffix) or tostring(ctl._value)
    end
    repaint()

    function ctl:Set(v, silent)
        v = clampRound(tonumber(v) or mn)
        self._value = v
        repaint()
        if not silent then self:_fire(v) ; if opts.Callback then pcall(opts.Callback, v) end end
    end
    function ctl:_serialize() return self._value end
    function ctl:_deserialize(v) if type(v)=="number" then self:Set(v) end end

    local dragging = false
    local function setFromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        ctl:Set(mn + rel * (mx - mn))
    end
    hitbox.InputBegan:Connect(function(input)
        if ctl._disabled then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    hitbox.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    self._janitor:Add(self.window.dispatcher:Subscribe("InputChanged", 18, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end))

    ctl._frame = frame ; ctl._tooltipTarget = frame ; ctl._focusTarget = hitbox ; ctl._activate = function() end
    if opts.Tooltip then self.window:_attachTooltip(frame, opts.Tooltip) end
    return self:_register(ctl)
end

----------------------------------------------------------------
-- Dropdown -----------------------------------------------------
----------------------------------------------------------------
function Section:AddDropdown(opts)
    opts = opts or {}
    assertType(opts, "table", "AddDropdown.opts")
    local items = opts.Items or {}
    if type(items) ~= "table" then error("[SigmatikUI] Dropdown.Items must be table", 2) end
    local multi = opts.Multi == true
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    if multi then ctl._value = type(opts.Default)=="table" and opts.Default or {}
    else ctl._value = opts.Default end

    local frame = rowFrame(self.body, 32, theme, self.window.theme)
    labelOf(frame, opts.Name or "Dropdown", theme, self.window.theme)

    local btn = new("TextButton", { Parent = frame, AutoButtonColor = false,
        BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0.45, 0, 0, 24),
        Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.text,
        Text = "", TextXAlignment = Enum.TextXAlignment.Left })
    corner(6).Parent = btn
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = btn })
    self.window.theme:Bind(btn, { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })

    local function summary()
        if multi then
            if not ctl._value or #ctl._value == 0 then return "—" end
            return table.concat(ctl._value, ", "):sub(1, 32)
        end
        return tostring(ctl._value or "—")
    end
    local function repaint() btn.Text = summary() .. "  ▾" end
    repaint()

    -- Overlay dropdown menu
    local menu, vlist
    local open = false
    local searchBox

    local function close()
        open = false
        if menu then menu:Destroy() ; menu = nil end
        if vlist then vlist:Destroy() ; vlist = nil end
    end
    local function build()
        if menu then return end
        menu = new("Frame", { Parent = self.window.screenGui, BackgroundColor3 = theme.color.surface, BorderSizePixel = 0,
            Size = UDim2.new(0, 240, 0, 240), ZIndex = 150, ClipsDescendants = true })
        corner(8).Parent = menu
        local sbar = stroke(theme.color.border, 0.4, 1) ; sbar.Parent = menu
        self.window.theme:Bind(menu, { BackgroundColor3 = "color.surface" })
        self.window.theme:Bind(sbar, { Color = "color.border" })
        new("UIPadding", { PaddingTop = UDim.new(0,6), PaddingBottom = UDim.new(0,6), PaddingLeft = UDim.new(0,6), PaddingRight = UDim.new(0,6), Parent = menu })

        searchBox = new("TextBox", { Parent = menu, BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 24), PlaceholderText = L("search"),
            Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.text, Text = "",
            TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 151 })
        corner(6).Parent = searchBox
        new("UIPadding", { PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,8), Parent = searchBox })
        self.window.theme:Bind(searchBox, { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })

        local scroll = new("ScrollingFrame", { Parent = menu, BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 1, -30),
            ScrollBarThickness = 3, ScrollBarImageColor3 = theme.color.border, CanvasSize = UDim2.new(0, 0, 0, 0), ZIndex = 151 })

        vlist = VirtualList.new(scroll, 26, function(existing, item, idx)
            local b = existing
            if not b then
                b = new("TextButton", { AutoButtonColor = false,
                    BackgroundColor3 = self.window.theme:Get().color.surface, BorderSizePixel = 0,
                    Size = UDim2.new(1, -4, 0, 24), Position = UDim2.new(0, 2, 0, 0),
                    Font = self.window.theme:Get().typography.family, TextSize = 12,
                    TextColor3 = self.window.theme:Get().color.text, TextXAlignment = Enum.TextXAlignment.Left,
                    Text = "", ZIndex = 152 })
                corner(4).Parent = b
                new("UIPadding", { PaddingLeft = UDim.new(0,8), Parent = b })
                self.window.theme:Bind(b, { BackgroundColor3 = "color.surface", TextColor3 = "color.text" })
                b.MouseEnter:Connect(function() tween(b, Anim.fast, { BackgroundColor3 = self.window.theme:Get().color.surfaceHover }) end)
                b.MouseLeave:Connect(function() tween(b, Anim.fast, { BackgroundColor3 = self.window.theme:Get().color.surface }) end)
            end
            local label = tostring(item)
            local picked = false
            if multi then
                for _,v in ipairs(ctl._value or {}) do if v == item then picked = true; break end end
                b.Text = (picked and "✓  " or "    ") .. label
            else
                picked = (ctl._value == item)
                b.Text = (picked and "•  " or "   ") .. label
            end
            b._click = b._click or b.MouseButton1Click:Connect(function() end)
            -- rebind click
            if b._clickConn then b._clickConn:Disconnect() end
            b._clickConn = b.MouseButton1Click:Connect(function()
                if multi then
                    local arr = ctl._value or {}
                    local found = false
                    for i,v in ipairs(arr) do if v == item then table.remove(arr, i); found = true; break end end
                    if not found then table.insert(arr, item) end
                    ctl:Set(arr)
                    if vlist then vlist:_render() end
                else
                    ctl:Set(item)
                    close()
                end
                repaint()
            end)
            return b
        end)
        vlist:SetItems(items)

        searchBox:GetPropertyChangedSignal("Text"):Connect(debounce(120, function()
            if vlist then vlist:SetFilter(searchBox.Text) end
        end))

        -- Position
        local btnPos = btn.AbsolutePosition
        local btnSize = btn.AbsoluteSize
        menu.Position = UDim2.fromOffset(btnPos.X + btnSize.X - 240, btnPos.Y + btnSize.Y + 4)
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
        if btnPos.Y + btnSize.Y + 4 + 240 > vp.Y then
            menu.Position = UDim2.fromOffset(btnPos.X + btnSize.X - 240, btnPos.Y - 244)
        end
    end

    function ctl:Set(v, silent)
        if multi then
            if type(v) == "table" then self._value = v end
        else
            self._value = v
        end
        repaint()
        if not silent then self:_fire(self._value) ; if opts.Callback then pcall(opts.Callback, self._value) end end
    end
    function ctl:SetItems(list) items = list or {} ; if vlist then vlist:SetItems(items) end end
    function ctl:_serialize() return self._value end
    function ctl:_deserialize(v) self:Set(v) end

    btn.MouseButton1Click:Connect(function()
        if ctl._disabled then return end
        if open then close() else open = true; build() end
    end)
    self._janitor:Add(self.window.dispatcher:Subscribe("InputBegan", 60, function(input)
        if not open or not menu then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local mp = UserInputService:GetMouseLocation()
        local p, s = menu.AbsolutePosition, menu.AbsoluteSize
        local pb, sb = btn.AbsolutePosition, btn.AbsoluteSize
        local inMenu = mp.X >= p.X and mp.X <= p.X+s.X and mp.Y >= p.Y and mp.Y <= p.Y+s.Y
        local inBtn = mp.X >= pb.X and mp.X <= pb.X+sb.X and mp.Y >= pb.Y and mp.Y <= pb.Y+sb.Y
        if not inMenu and not inBtn then close() end
    end))

    ctl._frame = frame ; ctl._tooltipTarget = frame ; ctl._focusTarget = btn ; ctl._activate = function() btn:Activate() end
    ctl._janitor:Add(close)
    if opts.Tooltip then self.window:_attachTooltip(frame, opts.Tooltip) end
    return self:_register(ctl)
end

----------------------------------------------------------------
-- Textbox ------------------------------------------------------
----------------------------------------------------------------
function Section:AddTextbox(opts)
    opts = opts or {} ; if type(opts) == "string" then opts = { Name = opts } end
    assertType(opts, "table", "AddTextbox.opts")
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    ctl._value = tostring(opts.Default or "")
    local maxLen = tonumber(opts.MaxLength) or 256

    local frame = rowFrame(self.body, 32, theme, self.window.theme)
    labelOf(frame, opts.Name or "Text", theme, self.window.theme)
    local box = new("TextBox", { Parent = frame, BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.5, 0, 0, 24),
        Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.text, Text = ctl._value,
        PlaceholderText = opts.Placeholder or "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left })
    corner(6).Parent = box
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = box })
    self.window.theme:Bind(box, { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })

    box:GetPropertyChangedSignal("Text"):Connect(function()
        if utf8.len(box.Text) and utf8.len(box.Text) > maxLen then
            box.Text = box.Text:sub(1, maxLen)
        end
    end)
    box.FocusLost:Connect(function(enter)
        ctl._value = box.Text
        ctl:_fire(ctl._value)
        if opts.Callback then pcall(opts.Callback, ctl._value, enter) end
    end)
    function ctl:Set(v, silent) v = tostring(v or "") ; self._value = v ; box.Text = v ; if not silent then self:_fire(v) end end
    function ctl:_serialize() return self._value end
    function ctl:_deserialize(v) if type(v)=="string" then self:Set(v) end end

    ctl._frame = frame ; ctl._tooltipTarget = frame ; ctl._focusTarget = box ; ctl._activate = function() box:CaptureFocus() end
    if opts.Tooltip then self.window:_attachTooltip(frame, opts.Tooltip) end
    return self:_register(ctl)
end

----------------------------------------------------------------
-- Keybind ------------------------------------------------------
----------------------------------------------------------------
function Section:AddKeybind(opts)
    opts = opts or {} ; if type(opts)=="string" then opts = { Name = opts } end
    assertType(opts, "table", "AddKeybind.opts")
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    local default = opts.Default
    if type(default) == "string" then default = Enum.KeyCode[default] or Enum.KeyCode.Unknown end
    ctl._value = { key = default or Enum.KeyCode.Unknown, mode = opts.Mode or "Toggle" }

    local frame = rowFrame(self.body, 32, theme, self.window.theme)
    labelOf(frame, opts.Name or "Keybind", theme, self.window.theme)
    local btn = new("TextButton", { Parent = frame, AutoButtonColor = false,
        BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 110, 0, 24), Font = theme.typography.family, TextSize = 12,
        TextColor3 = theme.color.text, Text = "" })
    corner(6).Parent = btn
    self.window.theme:Bind(btn, { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })

    local function fmt() return ctl._value.key.Name .. "  ·  " .. ctl._value.mode end
    btn.Text = fmt()

    local entry
    local function bind()
        if entry then self.window.dispatcher:UnregisterKeybind(entry) end
        entry = self.window.dispatcher:RegisterKeybind(ctl._value.key, opts.Modifiers or {}, function(state)
            if opts.Callback then pcall(opts.Callback, state) end
            ctl:_fire({key = ctl._value.key.Name, mode = ctl._value.mode, state = state})
        end, ctl._value.mode)
    end
    bind()
    ctl._janitor:Add(function() if entry then self.window.dispatcher:UnregisterKeybind(entry) end end)

    local listening = false
    btn.MouseButton1Click:Connect(function()
        if ctl._disabled then return end
        listening = true
        btn.Text = "...press key..."
    end)
    self._janitor:Add(self.window.dispatcher:Subscribe("InputBegan", 90, function(input, gp)
        if not listening then return end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            ctl._value.key = input.KeyCode
            btn.Text = fmt()
            listening = false
            bind()
            return true
        end
    end))

    function ctl:Set(v, silent)
        if type(v)=="table" then
            if type(v.key)=="string" then ctl._value.key = Enum.KeyCode[v.key] or Enum.KeyCode.Unknown
            elseif typeof(v.key)=="EnumItem" then ctl._value.key = v.key end
            if v.mode then ctl._value.mode = v.mode end
        elseif typeof(v)=="EnumItem" then ctl._value.key = v
        elseif type(v)=="string" then ctl._value.key = Enum.KeyCode[v] or ctl._value.key end
        btn.Text = fmt()
        bind()
        if not silent then self:_fire(self._value) end
    end
    function ctl:_serialize() return { key = ctl._value.key.Name, mode = ctl._value.mode } end
    function ctl:_deserialize(v) self:Set(v) end

    ctl._frame = frame ; ctl._tooltipTarget = frame ; ctl._focusTarget = btn ; ctl._activate = function() btn:Activate() end
    if opts.Tooltip then self.window:_attachTooltip(frame, opts.Tooltip) end
    return self:_register(ctl)
end

----------------------------------------------------------------
-- ColorPicker (simplified HSV) ---------------------------------
----------------------------------------------------------------
local function rgbToHsv(c)
    local r,g,b = c.R, c.G, c.B
    local mx, mn = math.max(r,g,b), math.min(r,g,b)
    local d, h, s, v = mx-mn, 0, mx==0 and 0 or (mx-mn)/mx, mx
    if d ~= 0 then
        if mx == r then h = ((g-b)/d) % 6
        elseif mx == g then h = (b-r)/d + 2
        else h = (r-g)/d + 4 end
        h = h * 60
    end
    return h, s, v
end

function Section:AddColorPicker(opts)
    opts = opts or {}
    assertType(opts, "table", "AddColorPicker.opts")
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    local default = opts.Default or Color3.fromRGB(255,255,255)
    if typeof(default) == "string" then default = Color3.new(parseHex(default).R or 1, 1, 1) end
    ctl._value = default

    local frame = rowFrame(self.body, 32, theme, self.window.theme)
    labelOf(frame, opts.Name or "Color", theme, self.window.theme)

    local swatch = new("TextButton", { Parent = frame, AutoButtonColor = false,
        BackgroundColor3 = ctl._value, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 36, 0, 22), Text = "" })
    corner(4).Parent = swatch
    local sStroke = stroke(theme.color.border, 0.4, 1) ; sStroke.Parent = swatch
    self.window.theme:Bind(sStroke, { Color = "color.border" })

    local picker
    local function build()
        if picker then picker:Destroy() end
        picker = new("Frame", { Parent = self.window.screenGui, BackgroundColor3 = theme.color.surface,
            BorderSizePixel = 0, Size = UDim2.fromOffset(220, 200), ZIndex = 200 })
        corner(8).Parent = picker
        new("UIPadding", { PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,8), PaddingTop = UDim.new(0,8), PaddingBottom = UDim.new(0,8), Parent = picker })

        local sv = new("ImageLabel", { Parent = picker, Size = UDim2.new(1, 0, 0, 110), BackgroundColor3 = Color3.new(1,0,0), BorderSizePixel = 0 })
        new("UIGradient", { Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(1,0,0)), Parent = sv, Rotation = 0 })
        local svDark = new("Frame", { Parent = sv, Size = UDim2.fromScale(1,1), BackgroundColor3 = Color3.new(0,0,0), BorderSizePixel = 0 })
        new("UIGradient", { Color = ColorSequence.new(Color3.new(0,0,0), Color3.new(0,0,0)),
            Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0)}), Rotation = 90, Parent = svDark })

        local hueBar = new("Frame", { Parent = picker, Position = UDim2.new(0, 0, 0, 118), Size = UDim2.new(1, 0, 0, 14), BorderSizePixel = 0 })
        new("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,Color3.fromRGB(255,0,0)),
                ColorSequenceKeypoint.new(0.17,Color3.fromRGB(255,255,0)),
                ColorSequenceKeypoint.new(0.33,Color3.fromRGB(0,255,0)),
                ColorSequenceKeypoint.new(0.5,Color3.fromRGB(0,255,255)),
                ColorSequenceKeypoint.new(0.66,Color3.fromRGB(0,0,255)),
                ColorSequenceKeypoint.new(0.83,Color3.fromRGB(255,0,255)),
                ColorSequenceKeypoint.new(1,Color3.fromRGB(255,0,0)),
            }), Parent = hueBar })

        local hex = new("TextBox", { Parent = picker, Position = UDim2.new(0, 0, 0, 140), Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
            Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.text,
            Text = color3ToHex(ctl._value), ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left })
        corner(4).Parent = hex
        new("UIPadding", { PaddingLeft = UDim.new(0, 6), Parent = hex })

        local close = new("TextButton", { Parent = picker, Position = UDim2.new(0,0,0,170), Size = UDim2.new(1,0,0,22),
            BackgroundColor3 = theme.color.primary, BorderSizePixel = 0,
            Font = theme.typography.familyBold, TextSize = 12, TextColor3 = Color3.new(1,1,1), Text = L("apply") })
        corner(4).Parent = close

        local h, s, v = rgbToHsv(ctl._value)
        local function apply() ctl:Set(Color3.fromHSV(h/360, s, v)) end
        local function setSV(x, y)
            local rel = sv.AbsolutePosition
            s = math.clamp((x - rel.X) / sv.AbsoluteSize.X, 0, 1)
            v = 1 - math.clamp((y - rel.Y) / sv.AbsoluteSize.Y, 0, 1)
            apply()
        end
        local function setHue(x)
            local rel = hueBar.AbsolutePosition
            local p = math.clamp((x - rel.X) / hueBar.AbsoluteSize.X, 0, 1)
            h = p * 360
            local g = sv:FindFirstChildOfClass("UIGradient")
            if g then g.Color = ColorSequence.new(Color3.new(1,1,1), Color3.fromHSV(h/360, 1, 1)) end
            apply()
        end
        sv.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then setSV(i.Position.X, i.Position.Y) end end)
        hueBar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then setHue(i.Position.X) end end)
        hex.FocusLost:Connect(function()
            local c = Color3.new(parseHex(hex.Text).R, parseHex(hex.Text).G, parseHex(hex.Text).B)
            ctl:Set(c)
        end)
        close.MouseButton1Click:Connect(function() picker:Destroy() ; picker = nil end)

        local p = swatch.AbsolutePosition
        picker.Position = UDim2.fromOffset(p.X - 200, p.Y + swatch.AbsoluteSize.Y + 4)
    end

    function ctl:Set(v, silent)
        if typeof(v) == "Color3" then self._value = v
        elseif type(v) == "string" then
            local c = Color3.fromRGB(0,0,0)
            local clr = parseHex(v) ; self._value = clr
        end
        swatch.BackgroundColor3 = self._value
        if not silent then self:_fire(self._value) ; if opts.Callback then pcall(opts.Callback, self._value) end end
    end
    function ctl:_serialize() return color3ToHex(self._value) end
    function ctl:_deserialize(v) self:Set(v) end

    swatch.MouseButton1Click:Connect(function() if not ctl._disabled then build() end end)

    ctl._frame = frame ; ctl._tooltipTarget = frame ; ctl._focusTarget = swatch ; ctl._activate = function() swatch:Activate() end
    ctl._janitor:Add(function() if picker then picker:Destroy() end end)
    if opts.Tooltip then self.window:_attachTooltip(frame, opts.Tooltip) end
    return self:_register(ctl)
end

----------------------------------------------------------------
-- Label / Paragraph / Divider / ProgressBar -------------------
----------------------------------------------------------------
function Section:AddLabel(opts)
    opts = opts or {} ; if type(opts)=="string" then opts = { Text = opts } end
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    local lbl = new("TextLabel", { Parent = self.body, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 22), Font = theme.typography.family, TextSize = 13,
        TextColor3 = theme.color.text, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(opts.Text or "") })
    self.window.theme:Bind(lbl, { TextColor3 = "color.text" })
    function ctl:Set(v, silent) lbl.Text = tostring(v or "") ; if not silent then self:_fire(v) end end
    ctl._frame = lbl
    return self:_register(ctl)
end
function Section:AddParagraph(opts)
    opts = opts or {}
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    local frame = new("Frame", { Parent = self.body, BackgroundColor3 = theme.color.surfaceMuted, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    corner(6).Parent = frame
    self.window.theme:Bind(frame, { BackgroundColor3 = "color.surfaceMuted" })
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = frame })
    new("TextLabel", { Parent = frame, BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18), Font = theme.typography.familyBold, TextSize = 13,
        TextColor3 = theme.color.text, TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(opts.Title or opts.Name or "") })
    local body = new("TextLabel", { Parent = frame, BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 22),
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.textMuted,
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
        Text = tostring(opts.Content or opts.Text or ""):sub(1, 2000) })
    self.window.theme:Bind(body, { TextColor3 = "color.textMuted" })
    ctl._frame = frame
    return self:_register(ctl)
end
function Section:AddDivider(opts)
    opts = opts or {}
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    local frame = new("Frame", { Parent = self.body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, opts.Text and 22 or 8) })
    if opts.Text then
        local lbl = new("TextLabel", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
            Font = theme.typography.familyBold, TextSize = 11, TextColor3 = theme.color.textMuted,
            TextXAlignment = Enum.TextXAlignment.Left, Text = string.upper(tostring(opts.Text)) })
        self.window.theme:Bind(lbl, { TextColor3 = "color.textMuted" })
    else
        local line = new("Frame", { Parent = frame, BackgroundColor3 = theme.color.border, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, 0, 0, 1) })
        self.window.theme:Bind(line, { BackgroundColor3 = "color.border" })
    end
    ctl._frame = frame
    return self:_register(ctl)
end
function Section:AddProgressBar(opts)
    opts = opts or {}
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    ctl._value = math.clamp(tonumber(opts.Value) or 0, 0, 1)
    local indeterminate = opts.Indeterminate == true

    local frame = rowFrame(self.body, 30, theme, self.window.theme)
    labelOf(frame, opts.Name or "", theme, self.window.theme)
    local track = new("Frame", { Parent = frame, BackgroundColor3 = theme.color.border, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.5, 0, 0, 8) })
    corner(4).Parent = track
    self.window.theme:Bind(track, { BackgroundColor3 = "color.border" })
    local fill = new("Frame", { Parent = track, BackgroundColor3 = theme.color.primary, BorderSizePixel = 0,
        Size = UDim2.new(ctl._value, 0, 1, 0) })
    corner(4).Parent = fill
    self.window.theme:Bind(fill, { BackgroundColor3 = "color.primary" })

    if indeterminate then
        fill.Size = UDim2.new(0.3, 0, 1, 0)
        local conn ; conn = RunService.Heartbeat:Connect(function()
            local p = (tick() % 2) / 2
            fill.Position = UDim2.new(p, 0, 0, 0)
        end)
        ctl._janitor:Add(conn)
    end

    function ctl:Set(v, silent) self._value = math.clamp(tonumber(v) or 0, 0, 1) ; fill.Size = UDim2.new(self._value, 0, 1, 0) ; if not silent then self:_fire(self._value) end end
    ctl._frame = frame
    return self:_register(ctl)
end

----------------------------------------------------------------
-- RadioGroup ---------------------------------------------------
----------------------------------------------------------------
function Section:AddRadioGroup(opts)
    opts = opts or {}
    assertType(opts, "table", "AddRadioGroup.opts")
    if type(opts.Items) ~= "table" then error("[SigmatikUI] RadioGroup.Items required", 2) end
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    ctl._value = opts.Default or opts.Items[1]

    local frame = new("Frame", { Parent = self.body, BackgroundColor3 = theme.color.surfaceMuted, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    corner(6).Parent = frame
    self.window.theme:Bind(frame, { BackgroundColor3 = "color.surfaceMuted" })
    new("UIPadding", { PaddingLeft = UDim.new(0,10), PaddingRight = UDim.new(0,10), PaddingTop = UDim.new(0,8), PaddingBottom = UDim.new(0,8), Parent = frame })
    new("UIListLayout", { Padding = UDim.new(0,4), Parent = frame })
    if opts.Name then
        new("TextLabel", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16),
            Font = theme.typography.familyBold, TextSize = 12, TextColor3 = theme.color.text,
            TextXAlignment = Enum.TextXAlignment.Left, Text = opts.Name })
    end

    local btns = {}
    local function repaint()
        for item, b in pairs(btns) do
            local picked = (item == ctl._value)
            b.Text = (picked and "●  " or "○  ") .. tostring(item)
            tween(b, Anim.fast, { TextColor3 = picked and self.window.theme:Get().color.primary or self.window.theme:Get().color.text })
        end
    end
    for _,item in ipairs(opts.Items) do
        local b = new("TextButton", { Parent = frame, BackgroundTransparency = 1, AutoButtonColor = false,
            Size = UDim2.new(1, 0, 0, 22), Font = theme.typography.family, TextSize = 12,
            TextColor3 = theme.color.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
        btns[item] = b
        b.MouseButton1Click:Connect(function() ctl:Set(item) end)
    end
    repaint()
    function ctl:Set(v, silent) self._value = v ; repaint() ; if not silent then self:_fire(v) ; if opts.Callback then pcall(opts.Callback, v) end end end
    function ctl:_serialize() return self._value end
    function ctl:_deserialize(v) self:Set(v) end

    ctl._frame = frame
    return self:_register(ctl)
end

----------------------------------------------------------------
-- NumberStepper ------------------------------------------------
----------------------------------------------------------------
function Section:AddNumberStepper(opts)
    opts = opts or {}
    assertType(opts, "table", "AddNumberStepper.opts")
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    local mn = tonumber(opts.Min) or -math.huge
    local mx = tonumber(opts.Max) or math.huge
    local step = tonumber(opts.Step) or 1
    ctl._value = math.clamp(tonumber(opts.Default) or 0, mn, mx)

    local frame = rowFrame(self.body, 32, theme, self.window.theme)
    labelOf(frame, opts.Name or "Number", theme, self.window.theme)

    local container = new("Frame", { Parent = frame, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 110, 0, 22) })
    new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = container })

    local minus = new("TextButton", { Parent = container, AutoButtonColor = false, BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
        Size = UDim2.new(0, 22, 0, 22), Font = theme.typography.familyBold, TextSize = 14, TextColor3 = theme.color.text, Text = "−" })
    corner(4).Parent = minus
    local box = new("TextBox", { Parent = container, BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
        Size = UDim2.new(0, 56, 0, 22), Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.text,
        Text = tostring(ctl._value), ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Center })
    corner(4).Parent = box
    local plus = new("TextButton", { Parent = container, AutoButtonColor = false, BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
        Size = UDim2.new(0, 22, 0, 22), Font = theme.typography.familyBold, TextSize = 14, TextColor3 = theme.color.text, Text = "+" })
    corner(4).Parent = plus
    self.window.theme:Bind(minus, { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })
    self.window.theme:Bind(plus,  { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })
    self.window.theme:Bind(box,   { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })

    function ctl:Set(v, silent) self._value = math.clamp(tonumber(v) or 0, mn, mx) ; box.Text = tostring(self._value) ; if not silent then self:_fire(self._value) ; if opts.Callback then pcall(opts.Callback, self._value) end end end
    function ctl:_serialize() return self._value end
    function ctl:_deserialize(v) if type(v)=="number" then self:Set(v) end end
    minus.MouseButton1Click:Connect(function() ctl:Set(ctl._value - step) end)
    plus.MouseButton1Click:Connect(function() ctl:Set(ctl._value + step) end)
    box.FocusLost:Connect(function() ctl:Set(tonumber(box.Text) or ctl._value) end)

    ctl._frame = frame
    return self:_register(ctl)
end

----------------------------------------------------------------
-- SegmentedControl ---------------------------------------------
----------------------------------------------------------------
function Section:AddSegmentedControl(opts)
    opts = opts or {}
    assertType(opts, "table", "AddSegmentedControl.opts")
    if type(opts.Items) ~= "table" then error("[SigmatikUI] SegmentedControl.Items required", 2) end
    local theme = self.window.theme:Get()
    local ctl = Control.new(opts, self.window)
    ctl._value = opts.Default or opts.Items[1]

    local frame = rowFrame(self.body, 36, theme, self.window.theme)
    if opts.Name then labelOf(frame, opts.Name, theme, self.window.theme) end

    local row = new("Frame", { Parent = frame, BackgroundColor3 = theme.color.bg, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(opts.Name and 0.5 or 1, 0, 0, 26) })
    corner(6).Parent = row
    self.window.theme:Bind(row, { BackgroundColor3 = "color.bg" })
    new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Parent = row })
    new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), Parent = row })

    local segs = {}
    local function repaint()
        local th = self.window.theme:Get()
        for item, b in pairs(segs) do
            local on = (item == ctl._value)
            tween(b, Anim.fast, { BackgroundColor3 = on and th.color.primary or th.color.bg })
            b.TextColor3 = on and Color3.new(1,1,1) or th.color.textMuted
        end
    end
    local n = #opts.Items
    for _,item in ipairs(opts.Items) do
        local b = new("TextButton", { Parent = row, AutoButtonColor = false, BackgroundTransparency = 0,
            BackgroundColor3 = theme.color.bg, BorderSizePixel = 0, Size = UDim2.new(1/n, -4, 1, 0),
            Font = theme.typography.family, TextSize = 12, TextColor3 = theme.color.textMuted, Text = tostring(item) })
        corner(4).Parent = b
        b.MouseButton1Click:Connect(function() ctl:Set(item) end)
        segs[item] = b
    end
    repaint()
    function ctl:Set(v, silent) self._value = v ; repaint() ; if not silent then self:_fire(v) ; if opts.Callback then pcall(opts.Callback, v) end end end
    function ctl:_serialize() return self._value end
    function ctl:_deserialize(v) self:Set(v) end
    ctl._frame = frame
    return self:_register(ctl)
end

----------------------------------------------------------------
-- PlayerDropdown -----------------------------------------------
----------------------------------------------------------------
function Section:AddPlayerDropdown(opts)
    opts = opts or {}
    opts.Items = {}
    for _,p in ipairs(Players:GetPlayers()) do table.insert(opts.Items, p.Name) end
    opts.Name = opts.Name or L("players")
    local ctl = self:AddDropdown(opts)
    local function refresh()
        local items = {}
        for _,p in ipairs(Players:GetPlayers()) do table.insert(items, p.Name) end
        if ctl.SetItems then ctl:SetItems(items) end
    end
    ctl._janitor:Add(Players.PlayerAdded:Connect(refresh))
    ctl._janitor:Add(Players.PlayerRemoving:Connect(refresh))
    return ctl
end

----------------------------------------------------------------
-- Image --------------------------------------------------------
----------------------------------------------------------------
function Section:AddImage(opts)
    opts = opts or {}
    assertType(opts, "table", "AddImage.opts")
    local ctl = Control.new(opts, self.window)
    local size = opts.Size or UDim2.new(1, 0, 0, 120)
    local img = new("ImageLabel", { Parent = self.body, BackgroundTransparency = 1,
        Size = size, Image = tostring(opts.Asset or ""), ScaleType = opts.ScaleType or Enum.ScaleType.Fit })
    if opts.Corner then corner(opts.Corner).Parent = img end
    function ctl:Set(v) img.Image = tostring(v or "") end
    ctl._frame = img
    return self:_register(ctl)
end

----------------------------------------------------------------
-- Custom (plugin) ---------------------------------------------
----------------------------------------------------------------
function Section:AddCustom(name, opts)
    local fac = Library._components[tostring(name):lower()]
    if not fac then error("[SigmatikUI] No registered component: " .. tostring(name), 2) end
    local ctl = fac(self, opts or {})
    if ctl then self:_register(ctl) end
    return ctl
end

----------------------------------------------------------------
-- Modal --------------------------------------------------------
----------------------------------------------------------------
function Window:OpenModal(opts)
    opts = opts or {}
    self:CloseModal()
    self._modalOpen = true
    self._modalLayer.Visible = true
    self._modalLayer.BackgroundTransparency = 1
    tween(self._modalLayer, Anim.fast, { BackgroundTransparency = 0.4 })

    local theme = self.theme:Get()
    local card = new("Frame", { Parent = self._modalLayer, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(360, 0),
        AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = theme.color.surface, BorderSizePixel = 0, ZIndex = 301 })
    corner(10).Parent = card
    new("UIPadding", { PaddingLeft = UDim.new(0,16), PaddingRight = UDim.new(0,16), PaddingTop = UDim.new(0,14), PaddingBottom = UDim.new(0,14), Parent = card })
    new("UIListLayout", { Padding = UDim.new(0,8), Parent = card })

    new("TextLabel", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1,0,0,22),
        Font = theme.typography.familyBold, TextSize = 16, TextColor3 = theme.color.text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = tostring(opts.Title or "") })
    if opts.Body then
        new("TextLabel", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1,0,0,0),
            AutomaticSize = Enum.AutomaticSize.Y, Font = theme.typography.family, TextSize = 13,
            TextColor3 = theme.color.textMuted, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
            Text = tostring(opts.Body) })
    end
    local btnRow = new("Frame", { Parent = card, BackgroundTransparency = 1, Size = UDim2.new(1,0,0,32) })
    new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,8),
        HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = btnRow })
    local self2 = self
    for _,b in ipairs(opts.Buttons or { {Text="OK", Style="primary"} }) do
        local style = b.Style or "neutral"
        local color = (style == "primary" and theme.color.primary)
            or (style == "danger" and theme.color.danger)
            or theme.color.surfaceHover
        local btn = new("TextButton", { Parent = btnRow, AutoButtonColor = false,
            BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 90, 1, 0),
            Font = theme.typography.familyBold, TextSize = 13, TextColor3 = Color3.new(1,1,1), Text = b.Text or "" })
        corner(6).Parent = btn
        btn.MouseButton1Click:Connect(function()
            if b.Callback then pcall(b.Callback) end
            if b.Close ~= false then self2:CloseModal() end
        end)
    end
    self._modalCard = card
end
function Window:CloseModal()
    if not self._modalOpen then return end
    self._modalOpen = false
    if self._modalCard then self._modalCard:Destroy() ; self._modalCard = nil end
    tween(self._modalLayer, Anim.fast, { BackgroundTransparency = 1 })
    task.delay(0.15, function() if not self._modalOpen then self._modalLayer.Visible = false end end)
end

----------------------------------------------------------------
-- Command Palette (Ctrl+K) -------------------------------------
----------------------------------------------------------------
function Window:_collectCommands()
    local list = {}
    for _,t in ipairs(self.tabs) do
        table.insert(list, { label = "Tab: " .. t.name, exec = function() self:SelectTab(t) end })
    end
    for name in pairs(Themes) do
        table.insert(list, { label = "Theme: " .. name, exec = function() self.theme:Set(name) end })
    end
    table.insert(list, { label = L("themeEditor"), exec = function() self:OpenThemeEditor() end })
    if self.configManager then table.insert(list, { label = L("profile"), exec = function() self:OpenConfigManager() end }) end
    return list
end
function Window:ToggleCommandPalette() if self._paletteOpen then self:CloseCommandPalette() else self:OpenCommandPalette() end end
function Window:OpenCommandPalette()
    self:CloseCommandPalette()
    self._paletteOpen = true
    local theme = self.theme:Get()
    local pal = new("Frame", { Parent = self.screenGui, BackgroundColor3 = theme.color.surface, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 80), Size = UDim2.fromOffset(420, 280), ZIndex = 250 })
    corner(10).Parent = pal
    new("UIPadding", { PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,8), PaddingTop = UDim.new(0,8), PaddingBottom = UDim.new(0,8), Parent = pal })
    self.theme:Bind(pal, { BackgroundColor3 = "color.surface" })

    local box = new("TextBox", { Parent = pal, BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 30), PlaceholderText = L("commandPalette"),
        Font = theme.typography.family, TextSize = 13, TextColor3 = theme.color.text, Text = "",
        ClearTextOnFocus = false, ZIndex = 251 })
    corner(6).Parent = box
    new("UIPadding", { PaddingLeft = UDim.new(0,10), Parent = box })
    self.theme:Bind(box, { BackgroundColor3 = "color.surfaceHover", TextColor3 = "color.text" })

    local scroll = new("ScrollingFrame", { Parent = pal, BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, 0, 1, -36),
        ScrollBarThickness = 3, CanvasSize = UDim2.new(0,0,0,0), ZIndex = 251 })
    local cmds = self:_collectCommands()
    local vlist = VirtualList.new(scroll, 28, function(existing, item, idx)
        local b = existing
        if not b then
            b = new("TextButton", { AutoButtonColor = false, BackgroundColor3 = self.theme:Get().color.surface,
                BorderSizePixel = 0, Size = UDim2.new(1, -4, 0, 26), Font = self.theme:Get().typography.family,
                TextSize = 13, TextColor3 = self.theme:Get().color.text, TextXAlignment = Enum.TextXAlignment.Left,
                Text = "", ZIndex = 252 })
            corner(4).Parent = b
            new("UIPadding", { PaddingLeft = UDim.new(0,8), Parent = b })
            self.theme:Bind(b, { BackgroundColor3 = "color.surface", TextColor3 = "color.text" })
            b.MouseEnter:Connect(function() tween(b, Anim.fast, { BackgroundColor3 = self.theme:Get().color.surfaceHover }) end)
            b.MouseLeave:Connect(function() tween(b, Anim.fast, { BackgroundColor3 = self.theme:Get().color.surface }) end)
        end
        b.Text = item.label
        if b._clickConn then b._clickConn:Disconnect() end
        b._clickConn = b.MouseButton1Click:Connect(function() pcall(item.exec); self:CloseCommandPalette() end)
        return b
    end)
    vlist:SetItems(cmds)
    box:GetPropertyChangedSignal("Text"):Connect(debounce(120, function() vlist:SetFilter(box.Text) end))
    box:CaptureFocus()

    self._palette = pal ; self._paletteVlist = vlist
end
function Window:CloseCommandPalette()
    self._paletteOpen = false
    if self._paletteVlist then self._paletteVlist:Destroy() ; self._paletteVlist = nil end
    if self._palette then self._palette:Destroy() ; self._palette = nil end
end

----------------------------------------------------------------
-- Global Search (Ctrl+F) ---------------------------------------
----------------------------------------------------------------
function Window:ToggleGlobalSearch() if self._searchOpen then self:CloseGlobalSearch() else self:OpenGlobalSearch() end end
function Window:OpenGlobalSearch()
    self:CloseGlobalSearch()
    self._searchOpen = true
    local theme = self.theme:Get()
    local bar = new("Frame", { Parent = self.main, BackgroundColor3 = theme.color.surfaceHover, BorderSizePixel = 0,
        Position = UDim2.new(0, 160, 0, 40), Size = UDim2.new(1, -160, 0, 32), ZIndex = 50 })
    self.theme:Bind(bar, { BackgroundColor3 = "color.surfaceHover" })
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = bar })
    local box = new("TextBox", { Parent = bar, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0),
        Font = theme.typography.family, TextSize = 13, TextColor3 = theme.color.text, Text = "",
        PlaceholderText = L("searchAll"), ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left })
    self.theme:Bind(box, { TextColor3 = "color.text" })

    -- shift content down
    self.content.Position = UDim2.new(0, 160, 0, 72)
    self.content.Size = UDim2.new(1, -160, 1, -72)

    local function applyFilter(q)
        q = (q or ""):lower()
        for _,t in ipairs(self.tabs) do
            local anyVisibleSection = false
            for _,sec in ipairs(t.sections) do
                local anyVisible = false
                for _,c in ipairs(sec.controls) do
                    local label = c.opts and (c.opts.Name or c.opts.Title or c.opts.Text) or ""
                    local match = (q == "" or fuzzyScore(q, tostring(label)) > 0)
                    if c._frame then c._frame.Visible = match end
                    if match then anyVisible = true end
                end
                sec.container.Visible = anyVisible or q == ""
                if anyVisible or q == "" then anyVisibleSection = true end
            end
            -- keep tab buttons available
        end
    end

    box:GetPropertyChangedSignal("Text"):Connect(debounce(100, function() applyFilter(box.Text) end))
    box:CaptureFocus()
    self._searchBar = bar
    self._searchRestore = function()
        for _,t in ipairs(self.tabs) do
            for _,sec in ipairs(t.sections) do
                sec.container.Visible = true
                for _,c in ipairs(sec.controls) do if c._frame then c._frame.Visible = true end end
            end
        end
    end
end
function Window:CloseGlobalSearch()
    if not self._searchOpen then return end
    self._searchOpen = false
    if self._searchBar then self._searchBar:Destroy() ; self._searchBar = nil end
    if self._searchRestore then self._searchRestore() ; self._searchRestore = nil end
    self.content.Position = UDim2.new(0, 160, 0, 40)
    self.content.Size = UDim2.new(1, -160, 1, -40)
end

----------------------------------------------------------------
-- Theme Menu / Theme Editor ------------------------------------
----------------------------------------------------------------
function Window:OpenThemeMenu()
    local items = {}
    for _,name in ipairs(Library:GetThemes()) do
        table.insert(items, { Text = name, Callback = function() self.theme:Set(name) end })
    end
    table.insert(items, { Text = L("themeEditor"), Callback = function() self:OpenThemeEditor() end })
    self:OpenContextMenuAt(items, UserInputService:GetMouseLocation())
end

function Window:OpenThemeEditor()
    local cur = self.theme:Get()
    local copy = {}
    for k,v in pairs(cur.color) do copy[k] = v end
    self:OpenModal({
        Title = L("themeEditor"),
        Body = "Edit color tokens. Export copies JSON to clipboard.",
        Buttons = {
            { Text = L("export"), Style = "primary", Close = false, Callback = function()
                local hex = {}
                for k,v in pairs(copy) do
                    if typeof(v) == "Color3" then hex[k] = "#" .. color3ToHex(v) end
                end
                pcall(function() setclipboard(HttpService:JSONEncode(hex)) end)
                self:Notify({ Title = "Theme exported", Type = "success" })
            end },
            { Text = L("import"), Style = "neutral", Close = false, Callback = function()
                local raw
                pcall(function() raw = (getclipboard or readclipboard or function() return "" end)() end)
                if not raw then self:Notify({ Title = "Clipboard empty", Type = "warning" }); return end
                local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
                if ok and type(data) == "table" then
                    for k,v in pairs(data) do
                        if type(v) == "string" then copy[k] = parseHex(v) end
                    end
                    local newTheme = makeTheme("Custom", copy)
                    self.theme:Set(newTheme)
                    self:Notify({ Title = "Theme imported", Type = "success" })
                end
            end },
            { Text = L("apply"), Style = "primary", Callback = function()
                local newTheme = makeTheme("Custom", copy)
                Library:RegisterTheme("Custom", newTheme)
                self.theme:Set(newTheme)
            end },
            { Text = L("cancel"), Style = "neutral" },
        }
    })
end

----------------------------------------------------------------
-- ContextMenu --------------------------------------------------
----------------------------------------------------------------
function Window:OpenContextMenuAt(items, pos)
    if self._contextMenu then self._contextMenu:Destroy() end
    local theme = self.theme:Get()
    local m = new("Frame", { Parent = self.screenGui, BackgroundColor3 = theme.color.surface, BorderSizePixel = 0,
        Size = UDim2.fromOffset(160, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 280 })
    corner(6).Parent = m
    new("UIPadding", { PaddingLeft = UDim.new(0,4), PaddingRight = UDim.new(0,4), PaddingTop = UDim.new(0,4), PaddingBottom = UDim.new(0,4), Parent = m })
    new("UIListLayout", { Padding = UDim.new(0,2), Parent = m })
    self.theme:Bind(m, { BackgroundColor3 = "color.surface" })
    for _,it in ipairs(items) do
        if it.Separator then
            new("Frame", { Parent = m, BackgroundColor3 = theme.color.border, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1) })
        else
            local b = new("TextButton", { Parent = m, AutoButtonColor = false,
                BackgroundColor3 = theme.color.surface, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 24), Font = theme.typography.family, TextSize = 12,
                TextColor3 = theme.color.text, TextXAlignment = Enum.TextXAlignment.Left,
                Text = "  " .. tostring(it.Text or "") })
            corner(4).Parent = b
            self.theme:Bind(b, { BackgroundColor3 = "color.surface", TextColor3 = "color.text" })
            b.MouseEnter:Connect(function() tween(b, Anim.fast, { BackgroundColor3 = self.theme:Get().color.surfaceHover }) end)
            b.MouseLeave:Connect(function() tween(b, Anim.fast, { BackgroundColor3 = self.theme:Get().color.surface }) end)
            b.MouseButton1Click:Connect(function() if it.Callback then pcall(it.Callback) end ; m:Destroy() ; self._contextMenu = nil end)
        end
    end
    m.Position = UDim2.fromOffset(pos.X, pos.Y)
    self._contextMenu = m

    local conn
    conn = self.dispatcher:Subscribe("InputBegan", 90, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local mp = UserInputService:GetMouseLocation()
            local p, s = m.AbsolutePosition, m.AbsoluteSize
            local inside = mp.X >= p.X and mp.X <= p.X+s.X and mp.Y >= p.Y and mp.Y <= p.Y+s.Y
            if not inside then m:Destroy() ; self._contextMenu = nil ; conn() end
        end
    end)
end

function Section:AddContextMenu(target, items)
    local self2 = self
    target.MouseButton2Click:Connect(function()
        self2.window:OpenContextMenuAt(items, UserInputService:GetMouseLocation())
    end)
end

----------------------------------------------------------------
-- Groupbox / Tabbox --------------------------------------------
----------------------------------------------------------------
function Tab:AddGroupbox(opts)
    opts = opts or {} ; if type(opts)=="string" then opts = { Name = opts } end
    -- Two-column layout: lazily create columns frame on first call
    if not self._cols then
        local frame = new("Frame", { Parent = self.page, BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
        new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
        local left = new("Frame", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(0.5, -4, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
        listLayout(Enum.FillDirection.Vertical, 8).Parent = left
        local right = new("Frame", { Parent = frame, BackgroundTransparency = 1, Size = UDim2.new(0.5, -4, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
        listLayout(Enum.FillDirection.Vertical, 8).Parent = right
        self._cols = { container = frame, left = left, right = right }
    end
    -- Wrap as a Section under chosen column
    local side = (opts.Side == "right") and self._cols.right or self._cols.left
    -- Temporarily redirect AddSection's parent
    local prevPage = self.page
    self.page = side
    local sec = self:AddSection({ Name = opts.Name, Collapsible = opts.Collapsible })
    self.page = prevPage
    return sec
end

function Tab:AddTabbox(opts)
    opts = opts or {}
    local theme = self.window.theme:Get()
    local container = new("Frame", { Parent = self.page, BackgroundColor3 = theme.color.surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
    corner(8).Parent = container
    self.window.theme:Bind(container, { BackgroundColor3 = "color.surface" })
    new("UIPadding", { PaddingLeft = UDim.new(0,6), PaddingRight = UDim.new(0,6), PaddingTop = UDim.new(0,6), PaddingBottom = UDim.new(0,6), Parent = container })
    local tabsRow = new("Frame", { Parent = container, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26) })
    new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = tabsRow })
    local body = new("Frame", { Parent = container, BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, 30),
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })

    local tabbox = { tabs = {} }
    function tabbox:AddTab(name)
        local theme = self.window and self.window.theme:Get() or theme
        local btn = new("TextButton", { Parent = tabsRow, AutoButtonColor = false, BackgroundColor3 = theme.color.surfaceMuted,
            BorderSizePixel = 0, Size = UDim2.new(0, 80, 1, 0), Font = theme.typography.family, TextSize = 12,
            TextColor3 = theme.color.textMuted, Text = name })
        corner(4).Parent = btn
        local page = new("Frame", { Parent = body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
        listLayout(Enum.FillDirection.Vertical, 6).Parent = page
        local sec = setmetatable({ window = ((tabbox._owner and tabbox._owner.window) or nil), name = name, body = page,
            container = page, controls = {}, header = btn, _janitor = Janitor.new() }, Section)
        table.insert(tabbox.tabs, { btn = btn, page = page, section = sec })
        btn.MouseButton1Click:Connect(function() tabbox:Select(name) end)
        if #tabbox.tabs == 1 then tabbox:Select(name) end
        return sec
    end
    function tabbox:Select(name)
        for _,t in ipairs(self.tabs) do
            t.page.Visible = (t.section.name == name)
            t.btn.BackgroundColor3 = (t.section.name == name) and theme.color.primary or theme.color.surfaceMuted
            t.btn.TextColor3 = (t.section.name == name) and Color3.new(1,1,1) or theme.color.textMuted
        end
    end
    tabbox._owner = self
    -- patch sections to use parent window/section behaviour
    local origAdd = tabbox.AddTab
    tabbox.AddTab = function(_, n)
        local sec = origAdd(tabbox, tostring(n))
        sec.window = self.window
        sec.tab = self
        return sec
    end
    return tabbox
end

----------------------------------------------------------------
-- Profile / Config Manager -------------------------------------
----------------------------------------------------------------
local function configFolder()
    local folder = "SigmatikUI/" .. tostring(game.PlaceId)
    if isfolder and not isfolder("SigmatikUI") then pcall(makefolder, "SigmatikUI") end
    if isfolder and not isfolder(folder) then pcall(makefolder, folder) end
    return folder
end
local function listFiles(folder)
    if not listfiles then return {} end
    local out = {}
    local ok, files = pcall(listfiles, folder)
    if ok and type(files)=="table" then
        for _,f in ipairs(files) do
            local n = tostring(f):gsub(".*[/\\]", ""):gsub("%.json$", "")
            table.insert(out, n)
        end
    end
    return out
end

function Window:_collectConfig()
    local data = { _version = Library._version, _theme = self.theme:Get().name, controls = {} }
    for _,t in ipairs(self.tabs) do
        for _,sec in ipairs(t.sections) do
            for _,c in ipairs(sec.controls) do
                if c._serialize and c._flag then
                    local ok, v = pcall(c._serialize, c)
                    if ok then data.controls[c._flag] = v end
                end
            end
        end
    end
    return data
end
function Window:_applyConfig(data)
    if type(data) ~= "table" then return end
    if data._theme and Themes[data._theme] then self.theme:Set(data._theme) end
    if type(data.controls) == "table" then
        for flag, value in pairs(data.controls) do
            local c = self._flagControls[flag]
            if c and c._deserialize then pcall(c._deserialize, c, value) end
        end
    end
    Library.Hooks.OnLoad:Fire(self, data)
end

function Window:SaveConfig(slot)
    slot = tostring(slot or "default")
    if not writefile then return false, "no-fs" end
    local folder = configFolder()
    local data = self:_collectConfig()
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then return false, encoded end
    local ok2, err = pcall(writefile, folder .. "/" .. slot .. ".json", encoded)
    if not ok2 then return false, err end
    self._currentProfile = slot
    Library.Hooks.OnSave:Fire(self, slot, data)
    return true
end
function Window:LoadConfig(slot)
    slot = tostring(slot or "default")
    if not readfile or not isfile then return false, "no-fs" end
    local path = configFolder() .. "/" .. slot .. ".json"
    if not isfile(path) then return false, "missing" end
    local ok, raw = pcall(readfile, path)
    if not ok then return false, raw end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 then return false, data end
    self:_applyConfig(data)
    self._currentProfile = slot
    return true
end
function Window:ListProfiles() return listFiles(configFolder()) end
function Window:DeleteProfile(slot)
    if not delfile then return false, "no-fs" end
    local ok, err = pcall(delfile, configFolder() .. "/" .. tostring(slot) .. ".json")
    return ok, err
end
function Library:ExportConfig(window)
    window = window or Library._windows[1]
    if not window then return false end
    local data = window:_collectConfig()
    local s = HttpService:JSONEncode(data)
    pcall(function() setclipboard(s) end)
    return true, s
end
function Library:ImportConfig(window, str)
    window = window or Library._windows[1]
    if not window then return false end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, str)
    if not ok then return false, data end
    window:_applyConfig(data)
    return true
end

function Window:OpenConfigManager()
    local profiles = self:ListProfiles()
    table.insert(profiles, "+ " .. L("newProfile"))
    local self2 = self
    -- Build modal listing profiles
    local items = {}
    for _,p in ipairs(profiles) do table.insert(items, p) end
    self:OpenModal({
        Title = L("profile"),
        Body = table.concat(profiles, "\n"),
        Buttons = {
            { Text = L("save") .. " (default)", Style = "primary", Close = false, Callback = function()
                local ok = self2:SaveConfig("default")
                self2:Notify({ Title = ok and L("configSaved") or "Save failed", Type = ok and "success" or "error" })
            end },
            { Text = L("load") .. " (default)", Style = "neutral", Close = false, Callback = function()
                local ok = self2:LoadConfig("default")
                self2:Notify({ Title = ok and L("configLoaded") or "Load failed", Type = ok and "success" or "error" })
            end },
            { Text = L("export"), Style = "neutral", Close = false, Callback = function()
                Library:ExportConfig(self2) ; self2:Notify({ Title = "Copied to clipboard", Type = "success" })
            end },
            { Text = L("cancel"), Style = "neutral" },
        }
    })
end

----------------------------------------------------------------
-- A11y focus navigation ----------------------------------------
----------------------------------------------------------------
function Window:_focusNext(reverse)
    if #self._focusables == 0 then return end
    local step = reverse and -1 or 1
    self._focusIndex = ((self._focusIndex + step - 1) % #self._focusables) + 1
    local f = self._focusables[self._focusIndex]
    if f and f.instance then
        if GuiService then pcall(function() GuiService.SelectedObject = f.instance end) end
        -- visible focus ring
        if self._focusRing then self._focusRing:Destroy() end
        local theme = self.theme:Get()
        self._focusRing = stroke(theme.color.primary, 0, 2)
        self._focusRing.Parent = f.instance
    end
end

----------------------------------------------------------------
-- Visibility (close button hides, K toggles) -------------------
----------------------------------------------------------------
function Window:ToggleVisibility(forceState)
    local target
    if forceState == nil then target = not self.main.Visible
    else target = forceState and true or false end
    self.main.Visible = target
    if self._watermarkLabel then self._watermarkLabel.Visible = target and (self.opts.Watermark == true) end
    if self.blur then
        if target and (self.opts.Blur ~= false) then tween(self.blur, Anim.long, { Size = 12 })
        else tween(self.blur, Anim.fast, { Size = 0 }) end
    end
    if not target then
        if self._paletteOpen then self:CloseCommandPalette() end
        if self._searchOpen then self:CloseGlobalSearch() end
        if self._modalOpen then self:CloseModal() end
        if self._contextMenu then self._contextMenu:Destroy() ; self._contextMenu = nil end
    end
end

----------------------------------------------------------------
-- Window:Destroy ------------------------------------------------
----------------------------------------------------------------
function Window:Destroy()
    self._janitor:Cleanup()
    for i,w in ipairs(Library._windows) do if w == self then table.remove(Library._windows, i); break end end
end

----------------------------------------------------------------
-- Library:Destroy / Notify (global) ----------------------------
----------------------------------------------------------------
function Library:Notify(o)
    local w = Library._windows[1]
    if w then return w:Notify(o) end
end
function Library:Destroy()
    for i = #Library._windows, 1, -1 do Library._windows[i]:Destroy() end
end

----------------------------------------------------------------
return Library
