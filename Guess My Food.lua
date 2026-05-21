local LIBRARY_PATHS = {
	"C:\\Users\\lesab\\Downloads\\sigmatik_ui_library.lua",
	"C:/Users/lesab/Downloads/sigmatik_ui_library.lua",
	"sigmatik_ui_library.lua",
	"gui_lua/sigmatik_ui_library.lua",
	"D:/Нужное/Скрипты роблокс/Делаем скрипты тут/gui_lua/sigmatik_ui_library.lua",
}
local LIBRARY_URL = "https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local SharedEnv = (getgenv and getgenv()) or _G or getfenv(0) or {}

if SharedEnv.SigmatikGuessMyFoodCtx and SharedEnv.SigmatikGuessMyFoodCtx.Cleanup then
	pcall(SharedEnv.SigmatikGuessMyFoodCtx.Cleanup)
end

----------------------------------------------------------------
-- Library loader
----------------------------------------------------------------

local function loadLibrary()
	local g = (getgenv and getgenv()) or _G or getfenv(0) or {}
	local pre = rawget(g, "__SIGMATIK_LIB_PREINJECTED__")
	if type(pre) == "table" then return pre end
	for _, path in ipairs(LIBRARY_PATHS) do
		if loadfile then
			local ok, chunk = pcall(loadfile, path)
			if ok and chunk then
				local ok2, lib = pcall(chunk)
				if ok2 and type(lib) == "table" then return lib end
			end
		end
		if readfile and loadstring then
			local ok, source = pcall(readfile, path)
			if ok and source and #source > 100 then
				local fn = loadstring(source)
				if fn then
					local ok2, lib = pcall(fn)
					if ok2 and type(lib) == "table" then return lib end
				end
			end
		end
	end
	if loadstring then
		local ok, source = pcall(function() return game:HttpGet(LIBRARY_URL) end)
		if ok and source then
			local fn = loadstring(source)
			if fn then
				local ok2, lib = pcall(fn)
				if ok2 and type(lib) == "table" then return lib end
			end
		end
	end
	error("Sigmatik UI library could not be loaded")
end

local Library = loadLibrary()

----------------------------------------------------------------
-- Context
----------------------------------------------------------------

local Ctx = {
	Alive = true,
	AutoWin = false, AutoWinDelay = 0.5, AutoOpenGuess = true, WinUseImage = true, WinUseStatus = true,
	AutoSkip = false, SkipDelay = 0.5,
	WallhackCover = false,
	EspFood = false, EspFoodColor = "#22c55eff",
	EspPlayers = false, EspPlayersColor = "#ff4444ff",
	SpamRevealAll = false, SpamRevealOne = false, RevealDelay = 0.2,
	AutoDaily = false, DailyDay = 7,
	NetMod = nil, ImagesMod = nil, IdToName = nil, RemoteCache = {},
	EspGuis = {}, PlayerEspGuis = {}, AntiAfkConn = nil,
}
SharedEnv.SigmatikGuessMyFoodCtx = Ctx

----------------------------------------------------------------
-- Net / Images
----------------------------------------------------------------

local function getNet()
	if Ctx.NetMod then return Ctx.NetMod end
	local ok, m = pcall(function() return require(ReplicatedStorage.Shared.Modules.Net) end)
	if ok then Ctx.NetMod = m end
	return Ctx.NetMod
end

local function getImages()
	if Ctx.ImagesMod then return Ctx.ImagesMod end
	local ok, m = pcall(function() return require(ReplicatedStorage.Shared.Modules.Images) end)
	if ok and m then
		Ctx.ImagesMod = m
		Ctx.IdToName = {}
		for n, asset in pairs(m) do
			local id = tostring(asset):match("(%d+)")
			if id then Ctx.IdToName[id] = n end
		end
	end
	return Ctx.ImagesMod
end

local function getRE(name)
	local k = "RE:" .. name
	if Ctx.RemoteCache[k] then return Ctx.RemoteCache[k] end
	local net = getNet(); if not net then return nil end
	local ok, r = pcall(function() return net:RemoteEvent(name) end)
	if ok then Ctx.RemoteCache[k] = r; return r end
end

local function getRF(name)
	local k = "RF:" .. name
	if Ctx.RemoteCache[k] then return Ctx.RemoteCache[k] end
	local net = getNet(); if not net then return nil end
	local ok, r = pcall(function() return net:RemoteFunction(name) end)
	if ok then Ctx.RemoteCache[k] = r; return r end
end

local function fireRE(name, ...)
	local r = getRE(name); if not r then return end
	local args = {...}
	pcall(function() r:FireServer(unpack(args)) end)
end

local function invokeRF(name, ...)
	local r = getRF(name); if not r then return end
	local args = {...}
	pcall(function() return r:InvokeServer(unpack(args)) end)
end

----------------------------------------------------------------
-- Food detection
----------------------------------------------------------------

local function nameByImage(img)
	if not img or img == "" then return nil end
	local id = tostring(img):match("(%d+)")
	if not id then return nil end
	getImages()
	return Ctx.IdToName and Ctx.IdToName[id]
end

local function getMyTable()
	local tables = Workspace:FindFirstChild("Tables"); if not tables then return end
	for _, tbl in ipairs(tables:GetChildren()) do
		for _, sName in ipairs({"Seat1", "Seat2"}) do
			local s = tbl:FindFirstChild(sName)
			if s and s.Occupant and s.Occupant.Parent and s.Occupant.Parent.Name == LocalPlayer.Name then
				return tbl, (sName == "Seat1") and "Image1" or "Image2", (sName == "Seat1") and "Image2" or "Image1"
			end
		end
	end
end

local function readSide(tbl, side)
	if not tbl or not side then return nil end
	local s = tbl:FindFirstChild(side); if not s then return nil end
	local g = s:FindFirstChild("FoodGui"); if not g then return nil end
	local f = g:FindFirstChild("Food"); if not f then return nil end
	return nameByImage(f.Image)
end

local function getMyFood()
	local tbl, mine = getMyTable(); return tbl and readSide(tbl, mine)
end

local function getOppFood()
	local tbl, _, opp = getMyTable(); return tbl and readSide(tbl, opp)
end

----------------------------------------------------------------
-- Auto Win
----------------------------------------------------------------

local AutoWinBusy = false
local function tryAutoWin()
	if AutoWinBusy or not LocalPlayer:GetAttribute("InRound") then return end
	local food
	if Ctx.WinUseImage then food = getMyFood() end
	if not food and Ctx.WinUseStatus then
		local s = LocalPlayer:GetAttribute("RoundStatusText")
		if s and s ~= "" and getImages() and Ctx.ImagesMod[s] then food = s end
	end
	if not food then return end
	AutoWinBusy = true
	task.spawn(function()
		if Ctx.AutoOpenGuess then fireRE("RoundAction", "__OPEN_GUESS__"); task.wait(0.05) end
		fireRE("RoundAction", food)
		task.wait(0.5); AutoWinBusy = false
	end)
end

local function loopAutoWin()
	task.spawn(function()
		while Ctx.Alive and Ctx.AutoWin do
			pcall(tryAutoWin); task.wait(math.max(0.1, Ctx.AutoWinDelay))
		end
	end)
end

local function loopAutoSkip()
	task.spawn(function()
		while Ctx.Alive and Ctx.AutoSkip do
			if LocalPlayer:GetAttribute("InRound") then fireRE("RoundAction", "__SKIP__") end
			task.wait(math.max(0.1, Ctx.SkipDelay))
		end
	end)
end

----------------------------------------------------------------
-- Wallhack Cover
----------------------------------------------------------------

local function setCovers(visible)
	local tables = Workspace:FindFirstChild("Tables"); if not tables then return end
	for _, tbl in ipairs(tables:GetChildren()) do
		for _, n in ipairs({"Image1","Image2"}) do
			local s = tbl:FindFirstChild(n)
			local g = s and s:FindFirstChild("FoodGui")
			local c = g and g:FindFirstChild("Cover")
			if c then pcall(function() c.Visible = visible end) end
		end
	end
end

local function loopWallhack()
	task.spawn(function()
		while Ctx.Alive and Ctx.WallhackCover do
			setCovers(false); task.wait(0.3)
		end
		if Ctx.Alive then setCovers(true) end
	end)
end

----------------------------------------------------------------
-- ESP Food
----------------------------------------------------------------

local function clearFoodEsp()
	for _, g in pairs(Ctx.EspGuis) do pcall(function() g:Destroy() end) end
	Ctx.EspGuis = {}
end

local function hexToColor3(hex)
	hex = (hex or "#ffffffff"):gsub("#",""):sub(1,6)
	local r = tonumber(hex:sub(1,2),16) or 255
	local g = tonumber(hex:sub(3,4),16) or 255
	local b = tonumber(hex:sub(5,6),16) or 255
	return Color3.fromRGB(r,g,b)
end

local function refreshFoodEsp()
	clearFoodEsp(); if not Ctx.EspFood then return end
	local tables = Workspace:FindFirstChild("Tables"); if not tables then return end
	local color = hexToColor3(Ctx.EspFoodColor)
	for _, tbl in ipairs(tables:GetChildren()) do
		for _, n in ipairs({"Image1","Image2"}) do
			local s = tbl:FindFirstChild(n)
			if s then
				local part = s:IsA("BasePart") and s or s:FindFirstChildWhichIsA("BasePart")
				if part then
					local food = readSide(tbl, n) or "?"
					local bb = Instance.new("BillboardGui")
					bb.Name = "SigmatikFoodESP"
					bb.AlwaysOnTop = true
					bb.Size = UDim2.new(0, 220, 0, 50)
					bb.StudsOffset = Vector3.new(0, 4, 0)
					bb.Adornee = part
					bb.Parent = part
					local lbl = Instance.new("TextLabel")
					lbl.BackgroundTransparency = 1
					lbl.Size = UDim2.fromScale(1,1)
					lbl.Font = Enum.Font.GothamBold
					lbl.TextSize = 18
					lbl.TextStrokeTransparency = 0.4
					lbl.TextColor3 = color
					lbl.Text = food
					lbl.Parent = bb
					Ctx.EspGuis[#Ctx.EspGuis+1] = bb
				end
			end
		end
	end
end

local function loopFoodEsp()
	task.spawn(function()
		while Ctx.Alive and Ctx.EspFood do
			pcall(refreshFoodEsp); task.wait(1)
		end
		if Ctx.Alive then clearFoodEsp() end
	end)
end

----------------------------------------------------------------
-- ESP Players
----------------------------------------------------------------

local function clearPlayerEsp()
	for _, h in pairs(Ctx.PlayerEspGuis) do pcall(function() h:Destroy() end) end
	Ctx.PlayerEspGuis = {}
end

local function refreshPlayerEsp()
	clearPlayerEsp(); if not Ctx.EspPlayers then return end
	local color = hexToColor3(Ctx.EspPlayersColor)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p.Character then
			local hl = Instance.new("Highlight")
			hl.Name = "SigmatikPlayerESP"
			hl.Adornee = p.Character
			hl.FillColor = color
			hl.OutlineColor = color
			hl.FillTransparency = 0.55
			hl.Parent = p.Character
			Ctx.PlayerEspGuis[p.Name] = hl
		end
	end
end

local function loopPlayerEsp()
	task.spawn(function()
		while Ctx.Alive and Ctx.EspPlayers do
			pcall(refreshPlayerEsp); task.wait(2)
		end
		if Ctx.Alive then clearPlayerEsp() end
	end)
end

----------------------------------------------------------------
-- Reveal / Daily spam
----------------------------------------------------------------

local function loopReveal(kind)
	task.spawn(function()
		while Ctx.Alive and ((kind == "All" and Ctx.SpamRevealAll) or (kind == "One" and Ctx.SpamRevealOne)) do
			pcall(function() invokeRF("TryUseReveal", kind == "All" and "Reveal All" or "Reveal 1 More") end)
			task.wait(math.max(0.05, Ctx.RevealDelay))
		end
	end)
end

local function loopDaily()
	task.spawn(function()
		while Ctx.Alive and Ctx.AutoDaily do
			pcall(function() invokeRF("ClaimDailyReward", Ctx.DailyDay) end)
			task.wait(2)
		end
	end)
end

----------------------------------------------------------------
-- Anti AFK
----------------------------------------------------------------

local function setAntiAfk(on)
	if Ctx.AntiAfkConn then pcall(function() Ctx.AntiAfkConn:Disconnect() end); Ctx.AntiAfkConn = nil end
	if on then
		Ctx.AntiAfkConn = LocalPlayer.Idled:Connect(function()
			local vu = game:FindService("VirtualUser")
			if vu then
				pcall(function()
					vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
					task.wait(1)
					vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
				end)
			end
		end)
	end
end

----------------------------------------------------------------
-- Live info labels
----------------------------------------------------------------

local InfoCtrls = { my = nil, opp = nil, status = nil, money = nil, wins = nil, oppName = nil }

local function infoString()
	return getMyFood() or "-",
		getOppFood() or "-",
		LocalPlayer:GetAttribute("RoundOpponentName") or "-",
		LocalPlayer:GetAttribute("RoundStatusText") or "-"
end

local Controller
local function refreshInfoLabels()
	if not Controller then return end
	local mine, opp, oppName, status = infoString()
	local money, wins = "-", "-"
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	if ls then
		if ls:FindFirstChild("Money") then money = tostring(ls.Money.Value) end
		if ls:FindFirstChild("Wins") then wins = tostring(ls.Wins.Value) end
	end
	pcall(function()
		Controller:SetControlValue("📊 Info", "Live Info", "Round", "My Food", 0)
	end)
	-- The library doesn't update Label content via SetControlValue; rebuild approach unavailable.
	-- Instead mutate Content directly through tab structure:
	local tab = Controller:GetTab("📊 Info")
	if tab then
		local mod = tab.ModuleLookup["Live Info"]
		if mod then
			local sec = mod.SectionLookup["Round"]
			if sec then
				for _, c in ipairs(sec.Controls) do
					if c.Type == "label" then
						if c.Name == "My Food" then c.Content = "My Food: " .. mine
						elseif c.Name == "Opponent Food" then c.Content = "Opponent Food: " .. opp
						elseif c.Name == "Opponent Name" then c.Content = "Opponent: " .. oppName
						elseif c.Name == "Status Text" then c.Content = "Status: " .. status
						elseif c.Name == "Money" then c.Content = "Money: " .. money
						elseif c.Name == "Wins" then c.Content = "Wins: " .. wins
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------

Controller = Library:Create({
	Title = "tg: @sigmatik323",
	ConfigName = "Guess My Food",
	WindowWidth = 880,
	WindowHeight = 540,
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = "🎯 Win",
			Modules = {
				{
					Name = "Auto Win",
					Enabled = false,
					Callback = function(on)
						Ctx.AutoWin = on
						if on then loopAutoWin() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "toggle", Name = "Use Image Source", Value = true, Callback = function(v) Ctx.WinUseImage = v end },
								{ Type = "toggle", Name = "Use Status Source", Value = true, Callback = function(v) Ctx.WinUseStatus = v end },
								{ Type = "toggle", Name = "Auto Open Guess", Value = true, Callback = function(v) Ctx.AutoOpenGuess = v end },
								{ Type = "slider", Name = "Win Delay", Min = 0.1, Max = 3, Increment = 0.1, Value = 0.5, Callback = function(v) Ctx.AutoWinDelay = v end },
							},
						},
					},
				},
				{
					Name = "Auto Skip",
					Enabled = false,
					Callback = function(on)
						Ctx.AutoSkip = on
						if on then loopAutoSkip() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Skip Delay", Min = 0.1, Max = 5, Increment = 0.1, Value = 0.5, Callback = function(v) Ctx.SkipDelay = v end },
							},
						},
					},
				},
			},
		},
		{
			Name = "👁️ ESP",
			Modules = {
				{
					Name = "Cover Wallhack",
					Enabled = false,
					Callback = function(on)
						Ctx.WallhackCover = on
						if on then loopWallhack() else setCovers(true) end
					end,
					Sections = {
						{
							Name = "Info",
							Controls = {
								{ Type = "label", Name = "About", Content = "Removes the 6x6 cover frame on every food card." },
							},
						},
					},
				},
				{
					Name = "Food Names ESP",
					Enabled = false,
					Callback = function(on)
						Ctx.EspFood = on
						if on then loopFoodEsp() else clearFoodEsp() end
					end,
					Sections = {
						{
							Name = "Style",
							Controls = {
								{ Type = "colorpicker", Name = "ESP Color", Value = "#22c55eff", Callback = function(hex) Ctx.EspFoodColor = hex; if Ctx.EspFood then refreshFoodEsp() end end },
							},
						},
					},
				},
				{
					Name = "Players ESP",
					Enabled = false,
					Callback = function(on)
						Ctx.EspPlayers = on
						if on then loopPlayerEsp() else clearPlayerEsp() end
					end,
					Sections = {
						{
							Name = "Style",
							Controls = {
								{ Type = "colorpicker", Name = "Players Color", Value = "#ff4444ff", Callback = function(hex) Ctx.EspPlayersColor = hex; if Ctx.EspPlayers then refreshPlayerEsp() end end },
							},
						},
					},
				},
			},
		},
		{
			Name = "💎 Rewards",
			Modules = {
				{
					Name = "Auto Daily Reward",
					Enabled = false,
					Callback = function(on)
						Ctx.AutoDaily = on
						if on then loopDaily() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Daily Day", Min = 1, Max = 7, Increment = 1, Value = 7, Callback = function(v) Ctx.DailyDay = v end },
							},
						},
					},
				},
				{
					Name = "Spam Reveal All",
					Enabled = false,
					Callback = function(on)
						Ctx.SpamRevealAll = on
						if on then loopReveal("All") end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Reveal Delay", Min = 0.05, Max = 2, Increment = 0.05, Value = 0.2, Callback = function(v) Ctx.RevealDelay = v end },
							},
						},
					},
				},
				{
					Name = "Spam Reveal One More",
					Enabled = false,
					Callback = function(on)
						Ctx.SpamRevealOne = on
						if on then loopReveal("One") end
					end,
					Sections = {
						{
							Name = "Info",
							Controls = {
								{ Type = "label", Name = "About", Content = "Continuously calls TryUseReveal('Reveal 1 More')." },
							},
						},
					},
				},
			},
		},
		{
			Name = "📊 Info",
			Modules = {
				{
					Name = "Live Info",
					Enabled = true,
					Callback = function() end,
					Sections = {
						{
							Name = "Round",
							Controls = {
								{ Type = "label", Name = "My Food", Content = "My Food: -" },
								{ Type = "label", Name = "Opponent Food", Content = "Opponent Food: -" },
								{ Type = "label", Name = "Opponent Name", Content = "Opponent: -" },
								{ Type = "label", Name = "Status Text", Content = "Status: -" },
								{ Type = "label", Name = "Money", Content = "Money: -" },
								{ Type = "label", Name = "Wins", Content = "Wins: -" },
							},
						},
					},
				},
			},
		},
		{
			Name = "⚙️ Misc",
			Modules = {
				{
					Name = "Anti AFK",
					Enabled = false,
					Callback = function(on) setAntiAfk(on) end,
					Sections = {
						{
							Name = "Info",
							Controls = {
								{ Type = "label", Name = "About", Content = "Prevents idle disconnect (20 min)." },
							},
						},
					},
				},
			},
		},
	},
})

----------------------------------------------------------------
-- Cleanup + info loop
----------------------------------------------------------------

Ctx.Cleanup = function()
	Ctx.Alive = false
	Ctx.AutoWin = false; Ctx.AutoSkip = false
	Ctx.WallhackCover = false; Ctx.EspFood = false; Ctx.EspPlayers = false
	Ctx.SpamRevealAll = false; Ctx.SpamRevealOne = false; Ctx.AutoDaily = false
	clearFoodEsp(); clearPlayerEsp(); setCovers(true); setAntiAfk(false)
	pcall(function() Controller:Destroy() end)
end

task.spawn(function()
	while Ctx.Alive do
		pcall(refreshInfoLabels); task.wait(1)
	end
end)
