local LIBRARY_URL = "https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"
local LOCAL_LIBRARY_PATHS = {
	"sigmatik_ui_library.lua",
	"gui_lua/sigmatik_ui_library.lua",
	"../gui_lua/sigmatik_ui_library.lua",
	"..\\gui_lua\\sigmatik_ui_library.lua",
	"C:/Users/lesab/Downloads/sigmatik_ui_library.lua",
	"C:\\Users\\lesab\\Downloads\\sigmatik_ui_library.lua",
	"D:/Нужное/Скрипты роблокс/Делаем скрипты тут/gui_lua/sigmatik_ui_library.lua",
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local SharedEnv = (getgenv and getgenv()) or _G or getfenv(0) or {}

if SharedEnv.SigmatikCamoOrSnipeContext and SharedEnv.SigmatikCamoOrSnipeContext.Cleanup then
	pcall(SharedEnv.SigmatikCamoOrSnipeContext.Cleanup)
end

----------------------------------------------------------------
-- Library loader
----------------------------------------------------------------

local function loadLibrary()
	local g = (getgenv and getgenv()) or _G or getfenv(0) or {}
	local pre = rawget(g, "__SIGMATIK_LIB_PREINJECTED__")
	if type(pre) == "table" then return pre end
	for _, path in ipairs(LOCAL_LIBRARY_PATHS) do
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

local Context = {
	Alive = true,
	AutoKill = false, AutoKillInterval = 1,
	AutoFarm = false, FarmInterval = 1,
	SelectedHiderName = nil,
	SelectedPlayerName = nil,
	NetFolder = nil,
	RemoteCache = {},
}
SharedEnv.SigmatikCamoOrSnipeContext = Context

----------------------------------------------------------------
-- Net helpers (sleitnick_net @ ReplicatedStorage.Packages._Index)
----------------------------------------------------------------

local function locateNetFolder()
	if Context.NetFolder and Context.NetFolder.Parent then return Context.NetFolder end
	local pkgs = ReplicatedStorage:FindFirstChild("Packages")
	if not pkgs then return nil end
	local idx = pkgs:FindFirstChild("_Index")
	if not idx then return nil end
	local netRoot = idx:FindFirstChild("sleitnick_net@0.2.0")
	if not netRoot then
		for _, ch in ipairs(idx:GetChildren()) do
			if ch.Name:sub(1, #"sleitnick_net@") == "sleitnick_net@" then
				netRoot = ch
				break
			end
		end
	end
	if not netRoot then return nil end
	local net = netRoot:FindFirstChild("net") or netRoot:FindFirstChild("Net")
	Context.NetFolder = net
	return net
end

local function getRE(name)
	local cached = Context.RemoteCache[name]
	if cached and cached.Parent then return cached end
	local net = locateNetFolder()
	if not net then return nil end
	local r = net:FindFirstChild("RE/" .. name) or net:FindFirstChild(name)
	if r then Context.RemoteCache[name] = r end
	return r
end

local function fireRE(name, ...)
	local r = getRE(name)
	if not r then return false end
	local ok = pcall(function(...) r:FireServer(...) end, ...)
	return ok
end

----------------------------------------------------------------
-- Player utilities
----------------------------------------------------------------

local function getHiderPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p:GetAttribute("Hider") and p.Character then
			list[#list+1] = p
		end
	end
	return list
end

local function getOtherPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then list[#list+1] = p end
	end
	return list
end

local function namesOf(list)
	local out = {}
	for i, p in ipairs(list) do out[i] = p.Name end
	return out
end

local function findPlayerByName(name)
	if not name or name == "" then return nil end
	return Players:FindFirstChild(name)
end

----------------------------------------------------------------
-- Sniper actions
----------------------------------------------------------------

local function killHider(player)
	if not player or not player.Parent then return end
	local char = player.Character
	if not char then return end
	fireRE("ShootSniper", char)
end

local function killAllHiders()
	for _, h in ipairs(getHiderPlayers()) do
		killHider(h)
	end
end

----------------------------------------------------------------
-- Trolling actions
----------------------------------------------------------------

local function trollPlayer(action, player)
	if not player then return end
	fireRE("TrollPlayerRequest", action, player)
end

local function trollEveryone(action)
	fireRE("TrollEveryoneRequest", action)
end

----------------------------------------------------------------
-- Cash actions
----------------------------------------------------------------

local function claimFreeCashOnce()
	fireRE("GiveFreeCash")
end

----------------------------------------------------------------
-- Loops
----------------------------------------------------------------

local LoopIds = { kill = 0, farm = 0 }

local function startKillLoop()
	LoopIds.kill = LoopIds.kill + 1
	local id = LoopIds.kill
	task.spawn(function()
		while Context.Alive and Context.AutoKill and LoopIds.kill == id do
			killAllHiders()
			task.wait(math.max(0.05, Context.AutoKillInterval))
		end
	end)
end

local function startFarmLoop()
	LoopIds.farm = LoopIds.farm + 1
	local id = LoopIds.farm
	task.spawn(function()
		while Context.Alive and Context.AutoFarm and LoopIds.farm == id do
			claimFreeCashOnce()
			task.wait(math.max(0.05, Context.FarmInterval))
		end
	end)
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------

local Window = Library:CreateWindow({
	Title = "tg: @sigmatik323",
	Subtitle = "by sigmatik323",
	ConfigName = "Camo Or Snipe",
	WindowWidth = 720,
	WindowHeight = 480,
})

Context.Cleanup = function()
	Context.Alive = false
	Context.AutoKill = false
	Context.AutoFarm = false
	pcall(function() Window:Destroy() end)
end

local SniperTab = Window:AddTab({ Name = "🔫 Sniper" })
local KillSection = SniperTab:AddSection({ Name = "🎯 Kill Hiders" })

local hiderDropdown = KillSection:AddDropdown({
	Name = "Target Hider",
	Items = namesOf(getHiderPlayers()),
	Default = nil,
	Callback = function(v) Context.SelectedHiderName = v end,
})

KillSection:AddButton({
	Name = "Refresh Hiders",
	Callback = function()
		local names = namesOf(getHiderPlayers())
		hiderDropdown:SetItems(names)
	end,
})

KillSection:AddButton({
	Name = "Kill Selected Hider",
	Callback = function()
		local p = findPlayerByName(Context.SelectedHiderName)
		killHider(p)
	end,
})

KillSection:AddButton({
	Name = "Kill All Hiders",
	Callback = killAllHiders,
})

local AutoKillSection = SniperTab:AddSection({ Name = "♻️ Auto Kill" })

AutoKillSection:AddToggle({
	Name = "Auto Kill All Hiders",
	Default = false,
	Callback = function(v)
		Context.AutoKill = v
		if v then startKillLoop() else LoopIds.kill = LoopIds.kill + 1 end
	end,
})

AutoKillSection:AddSlider({
	Name = "Auto Kill Interval",
	Min = 0.1, Max = 5, Increment = 0.1, Default = 1,
	Callback = function(v) Context.AutoKillInterval = v end,
})

local TrollTab = Window:AddTab({ Name = "😈 Trolling" })
local SinglePlayerSection = TrollTab:AddSection({ Name = "🎯 Single Player" })

local playerDropdown = SinglePlayerSection:AddDropdown({
	Name = "Target Player",
	Items = namesOf(getOtherPlayers()),
	Default = nil,
	Callback = function(v) Context.SelectedPlayerName = v end,
})

SinglePlayerSection:AddButton({
	Name = "Refresh Players",
	Callback = function()
		playerDropdown:SetItems(namesOf(getOtherPlayers()))
	end,
})

SinglePlayerSection:AddButton({
	Name = "Alert Player",
	Callback = function() trollPlayer("alert", findPlayerByName(Context.SelectedPlayerName)) end,
})

SinglePlayerSection:AddButton({
	Name = "Re-disguise Player",
	Callback = function() trollPlayer("redisguise", findPlayerByName(Context.SelectedPlayerName)) end,
})

SinglePlayerSection:AddButton({
	Name = "Force Jump Player",
	Callback = function() trollPlayer("jump", findPlayerByName(Context.SelectedPlayerName)) end,
})

SinglePlayerSection:AddButton({
	Name = "x2 Size Player",
	Callback = function() trollPlayer("x2size", findPlayerByName(Context.SelectedPlayerName)) end,
})

local EveryoneSection = TrollTab:AddSection({ Name = "🌍 Everyone" })

EveryoneSection:AddButton({
	Name = "Alert Everyone",
	Callback = function() trollEveryone("alert") end,
})

EveryoneSection:AddButton({
	Name = "Re-disguise Everyone",
	Callback = function() trollEveryone("redisguise") end,
})

EveryoneSection:AddButton({
	Name = "Force Jump Everyone",
	Callback = function() trollEveryone("jump") end,
})

EveryoneSection:AddButton({
	Name = "x2 Size Everyone",
	Callback = function() trollEveryone("x2size") end,
})

local CashTab = Window:AddTab({ Name = "💰 Cash" })
local CashSection = CashTab:AddSection({ Name = "💵 Free Cash Farm" })

CashSection:AddToggle({
	Name = "Auto Free Cash Farm",
	Default = false,
	Callback = function(v)
		Context.AutoFarm = v
		if v then startFarmLoop() else LoopIds.farm = LoopIds.farm + 1 end
	end,
})

CashSection:AddSlider({
	Name = "Farm Interval",
	Min = 0.1, Max = 10, Increment = 0.1, Default = 1,
	Callback = function(v) Context.FarmInterval = v end,
})

CashSection:AddButton({
	Name = "Claim Once",
	Callback = claimFreeCashOnce,
})
