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
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local SharedEnv = (getgenv and getgenv()) or _G or getfenv(0) or {}

if SharedEnv.SigmatikLoadedLiesCtx and SharedEnv.SigmatikLoadedLiesCtx.Cleanup then
	pcall(SharedEnv.SigmatikLoadedLiesCtx.Cleanup)
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

	SpinReward = 7, SpinRunning = false,
	DailyAuto = false, DailyDay = 7,
	PlaytimeAuto = false,
	QuestAuto = false, QuestConn = nil, LastQuests = {},
	FreeCrateSpam = false, FreeCrateName = "GunCrate", FreeCrateRarity = "Common",
	BuyCrateSpam = false, BuyCrateName = "GunCrate", BuyCrateRarity = "Common", BuyCrateMode = "Buy1",
	CrateDelay = 0.5,

	EquipIndex = 1,
	WheelOpened = false,
	FollowerSpam = false, FollowerDelay = 1,
	RemoveLostStreak = false,
	NotifySpam = false, NotifyDelay = 1, NotifyText = "Server restart in 5", NotifyColor = "#ff4444ff",
	SfxSpam = false, SfxName = "HatchSound", SfxDelay = 0.1,
	TauntSpam = false, TauntName = "LOL", TauntDelay = 0.5,

	SkipObby = false,

	BulletSpy = false, BulletSpyConn = nil, BulletSpyHighlights = {}, BulletSpyColor = "#ff4444ff",
	RevealAllSpy = false, RevealAllConn = nil, RevealAllHighlights = {}, RevealAllColor = "#ff4444ff",

	RemoteCache = {},
	StatusLabel = nil,
}
SharedEnv.SigmatikLoadedLiesCtx = Ctx

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function hexToColor3(hex)
	local clean = (tostring(hex or "")):gsub("#", "")
	if #clean == 8 then clean = clean:sub(1, 6) end
	if #clean ~= 6 then return Color3.fromRGB(255, 255, 255) end
	local r = tonumber(clean:sub(1, 2), 16) or 255
	local g = tonumber(clean:sub(3, 4), 16) or 255
	local b = tonumber(clean:sub(5, 6), 16) or 255
	return Color3.fromRGB(r, g, b)
end

local function findRemote(parent, name)
	local key = tostring(parent) .. "/" .. name
	if Ctx.RemoteCache[key] then return Ctx.RemoteCache[key] end
	local ok, r = pcall(function() return parent:WaitForChild(name, 5) end)
	if ok and r then Ctx.RemoteCache[key] = r; return r end
end

local function getRemote(name)
	local r = ReplicatedStorage:FindFirstChild("Remotes")
	if not r then return nil end
	return findRemote(r, name)
end

local function getEvent(name)
	local r = ReplicatedStorage:FindFirstChild("Events")
	if not r then return nil end
	return findRemote(r, name)
end

local function getCrateRemote(name)
	local r = ReplicatedStorage:FindFirstChild("CrateAssets")
	if not r then return nil end
	local re = r:FindFirstChild("RemoteEvents")
	if not re then return nil end
	return findRemote(re, name)
end

local function safeFire(remote, ...)
	if not remote then return end
	local args = table.pack(...)
	pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end)
end

----------------------------------------------------------------
-- Skin lists (extracted from Shop client scripts)
----------------------------------------------------------------

local GUN_SKINS = {
	"Gold_Gun", "Kitty_Revolver", "Sukuna_Gun",
	"Rainbow_Revolver", "Binary_Revolver", "Valentine_Revolver",
}
local CHAIR_SKINS = {
	"Throne", "Sukuna_Chair", "Kitty_Teddy",
	"Rainbow_Chair", "Binary_Chair", "Valentine_Chair",
}
local EFFECT_SKINS = { "Cupid_Effect" }

local ALL_SKINS = {}
for _, n in ipairs(GUN_SKINS) do table.insert(ALL_SKINS, n) end
for _, n in ipairs(CHAIR_SKINS) do table.insert(ALL_SKINS, n) end
for _, n in ipairs(EFFECT_SKINS) do table.insert(ALL_SKINS, n) end

----------------------------------------------------------------
-- Vulnerability #1 — Spin Wheel reward spoof
----------------------------------------------------------------

local function fireSpin(rewardName)
	local ev = getEvent("Spin")
	safeFire(ev, "Reward" .. tostring(rewardName))
end

----------------------------------------------------------------
-- Vulnerability #2 — Daily_Claim
----------------------------------------------------------------

local function loopDaily()
	task.spawn(function()
		while Ctx.Alive and Ctx.DailyAuto do
			for d = 1, 7 do
				safeFire(getRemote("Daily_Claim"), d)
				task.wait(0.1)
			end
			task.wait(2)
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #3 — ClaimPlaytimeReward
----------------------------------------------------------------

local PLAYTIME_BUCKETS = { 300, 600, 900, 1200, 1500, 1800 }

local function loopPlaytime()
	task.spawn(function()
		while Ctx.Alive and Ctx.PlaytimeAuto do
			for _, sec in ipairs(PLAYTIME_BUCKETS) do
				safeFire(getRemote("ClaimPlaytimeReward"), sec)
				task.wait(0.1)
			end
			task.wait(2)
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #4 — ClaimQuest (auto-listen UpdateQuests)
----------------------------------------------------------------

local function startQuestSpy()
	if Ctx.QuestConn then return end
	local upd = getRemote("UpdateQuests")
	if not upd then return end
	Ctx.QuestConn = upd.OnClientEvent:Connect(function(data)
		if type(data) == "table" and type(data.quests) == "table" then
			Ctx.LastQuests = data.quests
		end
	end)
end

local function stopQuestSpy()
	if Ctx.QuestConn then pcall(function() Ctx.QuestConn:Disconnect() end) end
	Ctx.QuestConn = nil
end

local function loopQuest()
	startQuestSpy()
	task.spawn(function()
		while Ctx.Alive and Ctx.QuestAuto do
			local rem = getRemote("ClaimQuest")
			for _, q in ipairs(Ctx.LastQuests) do
				if q and q.Id and not q.Claimed then
					safeFire(rem, q.Id)
					task.wait(0.1)
				end
			end
			task.wait(3)
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #7 — BuyCrate / FreeCrate
----------------------------------------------------------------

local function loopFreeCrate()
	task.spawn(function()
		while Ctx.Alive and Ctx.FreeCrateSpam do
			safeFire(getCrateRemote("FreeCrate"), Ctx.FreeCrateName, Ctx.FreeCrateRarity, "Buy1")
			task.wait(math.max(0.1, Ctx.CrateDelay))
		end
	end)
end

local function loopBuyCrate()
	task.spawn(function()
		while Ctx.Alive and Ctx.BuyCrateSpam do
			safeFire(getCrateRemote("BuyCrate"), Ctx.BuyCrateName, Ctx.BuyCrateRarity, Ctx.BuyCrateMode)
			task.wait(math.max(0.1, Ctx.CrateDelay))
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #8 — Equip any skin
----------------------------------------------------------------

local function equipByIndex(idx)
	local name = ALL_SKINS[idx]
	if not name then return end
	safeFire(getRemote("Equip"), name)
end

local function equipAllSkins()
	task.spawn(function()
		for _, name in ipairs(ALL_SKINS) do
			safeFire(getRemote("Equip"), name)
			task.wait(0.2)
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #6 — Wheel:FireServer(true) free open
----------------------------------------------------------------

local function openWheelFree()
	safeFire(getRemote("Wheel"), true)
end

----------------------------------------------------------------
-- Vulnerability #13 — FollowerReward replay
----------------------------------------------------------------

local function loopFollower()
	task.spawn(function()
		while Ctx.Alive and Ctx.FollowerSpam do
			safeFire(getRemote("FollowerReward"))
			task.wait(math.max(0.2, Ctx.FollowerDelay))
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #5 — HandleAttribute
----------------------------------------------------------------

local function removeLostStreak()
	safeFire(getRemote("HandleAttribute"), "LostStreak", "Remove")
end

----------------------------------------------------------------
-- Vulnerability #9 — Notification broadcast spam
----------------------------------------------------------------

local function loopNotify()
	task.spawn(function()
		while Ctx.Alive and Ctx.NotifySpam do
			safeFire(getRemote("Notification"), hexToColor3(Ctx.NotifyColor), Ctx.NotifyText)
			task.wait(math.max(0.1, Ctx.NotifyDelay))
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #10 — SFX broadcast
----------------------------------------------------------------

local function loopSfx()
	task.spawn(function()
		while Ctx.Alive and Ctx.SfxSpam do
			safeFire(getRemote("SFX"), Ctx.SfxName)
			task.wait(math.max(0.05, Ctx.SfxDelay))
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #12 — Taunt spam
----------------------------------------------------------------

local function loopTaunt()
	task.spawn(function()
		while Ctx.Alive and Ctx.TauntSpam do
			safeFire(getRemote("Taunt"), Ctx.TauntName)
			task.wait(math.max(0.05, Ctx.TauntDelay))
		end
	end)
end

----------------------------------------------------------------
-- Vulnerability #11 — ResetStage / Obby skip
----------------------------------------------------------------

local function skipObby()
	local char = LocalPlayer.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local map = Workspace:FindFirstChild("Map")
	local obby = map and map:FindFirstChild("Obby")
	local tp = obby and obby:FindFirstChild("TP")
	if tp then
		hrp.CFrame = tp.CFrame * CFrame.new(0, 2, 0)
		safeFire(getRemote("ResetStage"), LocalPlayer)
	end
end

----------------------------------------------------------------
-- Vulnerability #15 — BulletPlaced highlight leak (passive spy)
----------------------------------------------------------------

local function clearBulletSpy()
	for _, h in pairs(Ctx.BulletSpyHighlights) do pcall(function() h:Destroy() end) end
	Ctx.BulletSpyHighlights = {}
end

local function startBulletSpy()
	if Ctx.BulletSpyConn then return end
	local re = getRemote("BulletPlaced")
	if not re then return end
	Ctx.BulletSpyConn = re.OnClientEvent:Connect(function(target)
		if not Ctx.BulletSpy then return end
		if typeof(target) ~= "Instance" then return end
		local color = hexToColor3(Ctx.BulletSpyColor)
		local hl = Instance.new("Highlight")
		hl.Name = "SigmatikBulletSpy"
		hl.Adornee = target
		hl.FillColor = color
		hl.OutlineColor = color
		hl.FillTransparency = 0.4
		hl.OutlineTransparency = 0
		hl.Parent = target
		table.insert(Ctx.BulletSpyHighlights, hl)
	end)
end

local function stopBulletSpy()
	if Ctx.BulletSpyConn then pcall(function() Ctx.BulletSpyConn:Disconnect() end) end
	Ctx.BulletSpyConn = nil
	clearBulletSpy()
end

----------------------------------------------------------------
-- Vulnerability #14 — RevealAllBullets / RevealSingleGun spy
----------------------------------------------------------------

local function clearRevealSpy()
	for _, h in pairs(Ctx.RevealAllHighlights) do pcall(function() h:Destroy() end) end
	Ctx.RevealAllHighlights = {}
end

local function startRevealSpy()
	if Ctx.RevealAllConn then return end
	local reAll = getRemote("RevealAllBullets")
	local reOne = getRemote("RevealSingleGun")
	local function highlight(target, loaded)
		if typeof(target) ~= "Instance" then return end
		local color = hexToColor3(Ctx.RevealAllColor)
		if loaded == false then color = Color3.fromRGB(0, 255, 0) end
		local hl = Instance.new("Highlight")
		hl.Name = "SigmatikRevealSpy"
		hl.Adornee = target
		hl.FillColor = color
		hl.OutlineColor = color
		hl.FillTransparency = 0.4
		hl.Parent = target
		table.insert(Ctx.RevealAllHighlights, hl)
	end
	Ctx.RevealAllConn = {}
	if reAll then
		table.insert(Ctx.RevealAllConn, reAll.OnClientEvent:Connect(function(list)
			if not Ctx.RevealAllSpy then return end
			if type(list) == "table" then
				for _, t in ipairs(list) do highlight(t, true) end
			end
		end))
	end
	if reOne then
		table.insert(Ctx.RevealAllConn, reOne.OnClientEvent:Connect(function(target, loaded)
			if not Ctx.RevealAllSpy then return end
			highlight(target, loaded)
		end))
	end
end

local function stopRevealSpy()
	if Ctx.RevealAllConn then
		for _, c in ipairs(Ctx.RevealAllConn) do pcall(function() c:Disconnect() end) end
	end
	Ctx.RevealAllConn = nil
	clearRevealSpy()
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------

local Controller = Library:Create({
	Title = "tg: @sigmatik323",
	ConfigName = "Loaded Lies",
	WindowWidth = 920,
	WindowHeight = 560,
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = "💰 Economy",
			Modules = {
				{
					Name = "Spin Wheel Spoof",
					Enabled = false,
					Callback = function(on)
						if on then
							fireSpin(Ctx.SpinReward)
							task.delay(0.1, function()
								pcall(function()
									Controller:SetModuleEnabled("💰 Economy", "Spin Wheel Spoof", false)
								end)
							end)
						end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Toggle ON to fire one Spin with chosen reward. Reward7 = 3 Premium Crates." },
								{ Type = "slider", Name = "Reward Index", Min = 1, Max = 7, Increment = 1, Value = 7,
									Callback = function(v) Ctx.SpinReward = v end },
							},
						},
					},
				},
				{
					Name = "Daily Reward Spam",
					Enabled = false,
					Callback = function(on)
						Ctx.DailyAuto = on
						if on then loopDaily() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Sends Daily_Claim for days 1..7 every 2s." },
							},
						},
					},
				},
				{
					Name = "Playtime Reward Spam",
					Enabled = false,
					Callback = function(on)
						Ctx.PlaytimeAuto = on
						if on then loopPlaytime() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Claims all 6 buckets (300..1800s) every 2s." },
							},
						},
					},
				},
				{
					Name = "Quest Auto Claim",
					Enabled = false,
					Callback = function(on)
						Ctx.QuestAuto = on
						if on then loopQuest() else stopQuestSpy() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Listens UpdateQuests, claims all quest IDs every 3s." },
							},
						},
					},
				},
				{
					Name = "Free Crate Spam",
					Enabled = false,
					Callback = function(on)
						Ctx.FreeCrateSpam = on
						if on then loopFreeCrate() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Spams FreeCrate:FireServer(name, rarity, 'Buy1')." },
								{ Type = "slider", Name = "Delay", Min = 0.1, Max = 5, Increment = 0.1, Value = 0.5,
									Callback = function(v) Ctx.CrateDelay = v end },
							},
						},
					},
				},
				{
					Name = "Buy Crate Spam",
					Enabled = false,
					Callback = function(on)
						Ctx.BuyCrateSpam = on
						if on then loopBuyCrate() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Spams BuyCrate:FireServer(name, rarity, 'Buy1')." },
								{ Type = "slider", Name = "Delay", Min = 0.1, Max = 5, Increment = 0.1, Value = 0.5,
									Callback = function(v) Ctx.CrateDelay = v end },
							},
						},
					},
				},
			},
		},
		{
			Name = "👕 Cosmetics",
			Modules = {
				{
					Name = "Equip Any Skin",
					Enabled = false,
					Callback = function(on)
						if on then
							equipByIndex(Ctx.EquipIndex)
							task.delay(0.1, function()
								pcall(function()
									Controller:SetModuleEnabled("👕 Cosmetics", "Equip Any Skin", false)
								end)
							end)
						end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info",
									Content = "1=Gold_Gun 2=Kitty_Revolver 3=Sukuna_Gun 4=Rainbow_Revolver 5=Binary_Revolver 6=Valentine_Revolver 7=Throne 8=Sukuna_Chair 9=Kitty_Teddy 10=Rainbow_Chair 11=Binary_Chair 12=Valentine_Chair 13=Cupid_Effect" },
								{ Type = "slider", Name = "Skin Index", Min = 1, Max = #ALL_SKINS, Increment = 1, Value = 1,
									Callback = function(v) Ctx.EquipIndex = v end },
							},
						},
					},
				},
				{
					Name = "Equip All Skins",
					Enabled = false,
					Callback = function(on)
						if on then
							equipAllSkins()
							task.delay(0.5, function()
								pcall(function()
									Controller:SetModuleEnabled("👕 Cosmetics", "Equip All Skins", false)
								end)
							end)
						end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Cycles through all 13 hardcoded skin names with Equip:FireServer." },
							},
						},
					},
				},
			},
		},
		{
			Name = "🎲 Misc Exploits",
			Modules = {
				{
					Name = "Open Wheel Free",
					Enabled = false,
					Callback = function(on)
						if on then
							openWheelFree()
							task.delay(0.1, function()
								pcall(function()
									Controller:SetModuleEnabled("🎲 Misc Exploits", "Open Wheel Free", false)
								end)
							end)
						end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Wheel:FireServer(true) — opens spin wheel UI without owning the gamepass." },
							},
						},
					},
				},
				{
					Name = "Follower Reward Replay",
					Enabled = false,
					Callback = function(on)
						Ctx.FollowerSpam = on
						if on then loopFollower() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Spams FollowerReward:FireServer() — re-claims group reward." },
								{ Type = "slider", Name = "Delay", Min = 0.2, Max = 5, Increment = 0.1, Value = 1,
									Callback = function(v) Ctx.FollowerDelay = v end },
							},
						},
					},
				},
				{
					Name = "Remove LostStreak Attribute",
					Enabled = false,
					Callback = function(on)
						if on then
							removeLostStreak()
							task.delay(0.1, function()
								pcall(function()
									Controller:SetModuleEnabled("🎲 Misc Exploits", "Remove LostStreak Attribute", false)
								end)
							end)
						end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "HandleAttribute:FireServer('LostStreak','Remove'). Server may also accept InRound/InObby." },
							},
						},
					},
				},
				{
					Name = "Skip Obby Teleport",
					Enabled = false,
					Callback = function(on)
						if on then
							skipObby()
							task.delay(0.1, function()
								pcall(function()
									Controller:SetModuleEnabled("🎲 Misc Exploits", "Skip Obby Teleport", false)
								end)
							end)
						end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Sets HRP CFrame to Obby.TP and fires ResetStage." },
							},
						},
					},
				},
			},
		},
		{
			Name = "📢 Broadcast Spam",
			Modules = {
				{
					Name = "Notification Broadcast",
					Enabled = false,
					Callback = function(on)
						Ctx.NotifySpam = on
						if on then loopNotify() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Server relays Notification text+color to ALL players. Confirmed via spy." },
								{ Type = "slider", Name = "Delay", Min = 0.1, Max = 5, Increment = 0.1, Value = 1,
									Callback = function(v) Ctx.NotifyDelay = v end },
								{ Type = "colorpicker", Name = "Color", Value = "#ff4444ff",
									Callback = function(v) Ctx.NotifyColor = v end },
							},
						},
					},
				},
				{
					Name = "SFX Broadcast",
					Enabled = false,
					Callback = function(on)
						Ctx.SfxSpam = on
						if on then loopSfx() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "SFX:FireServer(name) plays sound. Default = HatchSound." },
								{ Type = "slider", Name = "Delay", Min = 0.05, Max = 2, Increment = 0.05, Value = 0.1,
									Callback = function(v) Ctx.SfxDelay = v end },
							},
						},
					},
				},
				{
					Name = "Taunt Spam",
					Enabled = false,
					Callback = function(on)
						Ctx.TauntSpam = on
						if on then loopTaunt() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Taunt:FireServer(name) — server has no cooldown." },
								{ Type = "slider", Name = "Delay", Min = 0.05, Max = 3, Increment = 0.05, Value = 0.5,
									Callback = function(v) Ctx.TauntDelay = v end },
							},
						},
					},
				},
			},
		},
		{
			Name = "🔍 Recon",
			Modules = {
				{
					Name = "Bullet Placed Spy",
					Enabled = false,
					Callback = function(on)
						Ctx.BulletSpy = on
						if on then startBulletSpy() else stopBulletSpy() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Highlights every BulletPlaced event received. If opponent's bullets light up = wallhack leak confirmed." },
								{ Type = "colorpicker", Name = "Highlight Color", Value = "#ff4444ff",
									Callback = function(v) Ctx.BulletSpyColor = v end },
							},
						},
					},
				},
				{
					Name = "Reveal Spy",
					Enabled = false,
					Callback = function(on)
						Ctx.RevealAllSpy = on
						if on then startRevealSpy() else stopRevealSpy() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "paragraph", Name = "Info", Content = "Listens RevealAllBullets and RevealSingleGun. Highlights guns server reveals to you (after product purchase)." },
								{ Type = "colorpicker", Name = "Loaded Color", Value = "#ff4444ff",
									Callback = function(v) Ctx.RevealAllColor = v end },
							},
						},
					},
				},
			},
		},
		{
			Name = "ℹ️ Info",
			Modules = {
				{
					Name = "Vulnerability List",
					Enabled = false,
					Sections = {
						{
							Name = "Critical",
							Controls = {
								{ Type = "label", Name = "v1", Content = "1. Spin Wheel reward chosen by client" },
								{ Type = "label", Name = "v2", Content = "2. Daily_Claim accepts any day index" },
								{ Type = "label", Name = "v3", Content = "3. ClaimPlaytimeReward accepts any bucket" },
								{ Type = "label", Name = "v4", Content = "4. ClaimQuest no progress check" },
								{ Type = "label", Name = "v5", Content = "5. HandleAttribute name+action injection" },
								{ Type = "label", Name = "v6", Content = "6. Wheel:FireServer(true) free open" },
								{ Type = "label", Name = "v7", Content = "7. BuyCrate / FreeCrate cash on client" },
								{ Type = "label", Name = "v8", Content = "8. Equip any skin name" },
							},
						},
						{
							Name = "High",
							Controls = {
								{ Type = "label", Name = "v9", Content = "9. Notification broadcast spam (confirmed)" },
								{ Type = "label", Name = "v10", Content = "10. SFX broadcast spam" },
								{ Type = "label", Name = "v11", Content = "11. ResetStage + client CFrame" },
								{ Type = "label", Name = "v12", Content = "12. Taunt spam no cooldown" },
								{ Type = "label", Name = "v13", Content = "13. FollowerReward replay" },
							},
						},
						{
							Name = "Medium",
							Controls = {
								{ Type = "label", Name = "v14", Content = "14. RevealAll/Single broadcast risk" },
								{ Type = "label", Name = "v15", Content = "15. BulletPlaced highlight leak" },
								{ Type = "label", Name = "v16", Content = "16. CreateAnnouncement (server-side check needed)" },
							},
						},
					},
				},
			},
		},
	},
})

----------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------

Ctx.Cleanup = function()
	Ctx.Alive = false
	Ctx.DailyAuto = false; Ctx.PlaytimeAuto = false; Ctx.QuestAuto = false
	Ctx.FreeCrateSpam = false; Ctx.BuyCrateSpam = false
	Ctx.FollowerSpam = false; Ctx.NotifySpam = false; Ctx.SfxSpam = false; Ctx.TauntSpam = false
	Ctx.BulletSpy = false; Ctx.RevealAllSpy = false
	stopQuestSpy(); stopBulletSpy(); stopRevealSpy()
	if Controller and Controller.Destroy then pcall(function() Controller:Destroy() end) end
end
