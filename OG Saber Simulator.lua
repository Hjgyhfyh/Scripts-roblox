--[[
	OG Saber Simulator — full progression autofarm
	Boss-swing farm -> smart upgrades (DNA cap first) -> pets -> daily -> auras.
	Built around the Warp network gateway. Persistent config, anti-AFK, clean unload.
]]

if _G.OG_SABER and _G.OG_SABER.unload then
	pcall(_G.OG_SABER.unload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- executor compatibility
----------------------------------------------------------------------
local readfile = readfile
local writefile = writefile
local isfile = isfile
local makefolder = makefolder
local isfolder = isfolder
local protectgui = (syn and syn.protect_gui) or (protect_gui) or function() end
local gethui = gethui
local firetouchinterest = firetouchinterest
local getloadedmodules = getloadedmodules
local getgc = getgc

local CONFIG_FILE = "OG_Saber_Simulator_config.json"
local HttpService = game:GetService("HttpService")

----------------------------------------------------------------------
-- runtime container / guard
----------------------------------------------------------------------
local OG = {
	connections = {},
	threads = {},
	running = true,
	flags = {},
}
_G.OG_SABER = OG
OG.Config = nil -- assigned after Config is built

local function track(conn)
	table.insert(OG.connections, conn)
	return conn
end

----------------------------------------------------------------------
-- config persistence
----------------------------------------------------------------------
local Config = {
	AutoFarm = true,        -- swing loop
	BossLock = true,        -- park on the boss arena floor and farm kills (safe: stands on the floor, never the kill zone)
	SwingRate = 13,         -- swings per second
	AutoDNA = true,         -- raise the strength cap
	AutoSaber = true,
	AutoClass = true,
	AutoAura = true,
	AutoPetAura = false,
	AutoBossHit = true,
	AutoJump = false,
	AutoPetsCraft = true,
	AutoPetsEquip = true,
	AutoSell = false,       -- sell weakest pets beyond the keep-cap (irreversible; never sells equipped/locked)
	SellKeep = 40,          -- how many strongest unequipped pets to keep
	AutoHatch = true,
	AutoDaily = true,
	AutoReconnect = true,
	HidePets = true,
	AntiAFK = true,
	Minimized = false,
}

local function loadConfig()
	local ok, data = pcall(function()
		if isfile and isfile(CONFIG_FILE) and readfile then
			return HttpService:JSONDecode(readfile(CONFIG_FILE))
		end
	end)
	if ok and type(data) == "table" then
		for k, v in pairs(data) do
			if Config[k] ~= nil then Config[k] = v end
		end
	end
end

local saveQueued = false
local function saveConfig()
	if saveQueued then return end
	saveQueued = true
	task.delay(0.5, function()
		saveQueued = false
		pcall(function()
			if writefile then writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end
		end)
	end)
end

loadConfig()
OG.Config = Config

----------------------------------------------------------------------
-- locate Warp / Data / storage configs
----------------------------------------------------------------------
local Warp
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Warp")).Client()
	end)
	if ok then Warp = mod end
end

local function Fire(...)
	if Warp then pcall(Warp.Fire, ...) end
end
local function Invoke(...)
	if Warp then
		local ok, res = pcall(Warp.Invoke, ...)
		if ok then return res end
	end
end

-- live Data accessor (returns the always-fresh Data table)
local DataFn
local function locateData()
	if getloadedmodules then
		for _, m in ipairs(getloadedmodules()) do
			if m.Name == "DataController" then
				local ok, mod = pcall(require, m)
				if ok and type(mod) == "table" and type(rawget(mod, "Data")) == "table" and rawget(mod.Data, "Statistics") then
					return function() return mod.Data end
				end
			end
		end
	end
	if getgc then
		for _, v in ipairs(getgc(true)) do
			if type(v) == "table" then
				local d = rawget(v, "Data")
				if type(d) == "table" and type(rawget(d, "Statistics")) == "table" then
					return function() return v.Data end
				end
			end
		end
	end
	return nil
end

DataFn = locateData()

-- Warp-mirror fallback if the module could not be located
local Mirror
if not DataFn and Warp then
	Mirror = nil
	pcall(function()
		Warp.Connect("DataEvent", function(kind, a, b)
			if kind == "link" then
				Mirror = a
			elseif kind == "update" and Mirror and Mirror[a] and b then
				for k, val in pairs(b) do Mirror[a][k] = val end
			end
		end)
		Warp.Fire("DataEvent", "RequestLink")
	end)
	DataFn = function() return Mirror end
end

local function getData()
	if DataFn then
		local ok, d = pcall(DataFn)
		if ok then return d end
	end
	return nil
end

local function getStats()
	local d = getData()
	return d and d.Statistics or nil
end

local function storage(name)
	local ok, mod = pcall(function()
		return require(ReplicatedStorage.Shared.Storage:FindFirstChild(name))
	end)
	if ok then return mod end
	return nil
end

local Sabers   = storage("Sabers")
local DNAs     = storage("DNAs")
local Classes  = storage("Classes")
local Auras    = storage("Auras")
local PetAuras = storage("PetAuras")
local JumpLvls = storage("DoubleJumpLevels")
local BossLvls = storage("BossDamageLevels")
local Eggs     = storage("Eggs")
local PetsCfg  = storage("Pets")
local GlobalCfg = storage("GlobalConfig")

local PetRemote
pcall(function()
	PetRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Remote_PetEvent")
end)

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function num(v)
	return tonumber(v) or 0
end

local function abbreviate(n)
	n = num(n)
	if n < 1000 then return string.format("%.0f", n) end
	local units = {"K","M","B","T","Qa","Qi","Sx","Sp","Oc","No","Dc"}
	local i = 0
	while n >= 1000 and i < #units do
		n = n / 1000
		i = i + 1
	end
	return string.format("%.2f%s", n, units[i])
end

local function character()
	local c = LocalPlayer.Character
	if not c then return nil end
	return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
end

local function findLiveBoss()
	local folder = Workspace:FindFirstChild("Boss")
	if not folder then return nil end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("Humanoid") and d.Health > 0 then
			local model = d.Parent
			local part = model:FindFirstChild("HumanoidRootPart")
				or model:FindFirstChild("Torso")
				or (model:IsA("Model") and model.PrimaryPart)
				or model:FindFirstChildWhichIsA("BasePart")
			if part then
				return model, part, d
			end
		end
	end
	return nil
end

-- maximum island id the player has unlocked (gate for eggs)
local function maxIsland(st)
	local m = 0
	if st and type(st.UnlockedIslands) == "table" then
		for _, v in ipairs(st.UnlockedIslands) do
			local n = tonumber(v)
			if n and n > m then m = n end
		end
	end
	return m
end

----------------------------------------------------------------------
-- anti-AFK (always available, gated by flag)
----------------------------------------------------------------------
track(LocalPlayer.Idled:Connect(function()
	if not Config.AntiAFK then return end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

----------------------------------------------------------------------
-- generic worker spawner
----------------------------------------------------------------------
local function spawnLoop(name, interval, fn)
	local th = task.spawn(function()
		while OG.running do
			local ok, err = pcall(fn)
			if not ok then
				-- swallow, keep the loop alive
			end
			task.wait(interval)
		end
	end)
	OG.threads[name] = th
end

----------------------------------------------------------------------
-- The game's EggController runs a postsimulation hook that indexes
-- PlayerGui.Billboards every frame and errors ~60x/s whenever the
-- character sits in the boss/egg area (reproducible without any script).
-- Disconnect its service group before we ever park on a boss so the
-- console isn't flooded during an overnight session. Done lazily — only
-- when boss farming is actually engaged. Hatching still works (we fire
-- EggEvent directly), only the buggy billboard refresh is silenced.
----------------------------------------------------------------------
local eggSilenced = false
local function silenceEggController()
	if eggSilenced then return end
	eggSilenced = true
	pcall(function()
		for _, m in ipairs(getloadedmodules and getloadedmodules() or {}) do
			if m.Name == "Service" then
				local ok, mod = pcall(require, m)
				if ok and type(mod) == "table" and type(rawget(mod, "groups")) == "table" and mod.groups.EggController then
					for _, conn in ipairs(mod.groups.EggController) do
						pcall(function() conn:Disconnect() end)
					end
				end
				break
			end
		end
	end)
end

----------------------------------------------------------------------
-- SABER guard: dying drops the saber tool and the game does NOT hand it
-- back on respawn. Re-equipping the same id is a no-op, but toggling to
-- another owned saber and back forces the server to re-issue the tool.
-- Without a saber, swings deal nothing.
----------------------------------------------------------------------
local function hasSaber()
	local char = LocalPlayer.Character
	if char then
		for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then return true end end
	end
	local bp = LocalPlayer:FindFirstChild("Backpack")
	if bp then
		for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then return true end end
	end
	return false
end

local function restoreSaber()
	local st = getStats()
	if not st then return end
	local lvl = num(st.SaberLevel)
	if lvl <= 1 then return end
	Fire("SaberShopEvent", "equip_item", 1)
	task.wait(0.8)
	Fire("SaberShopEvent", "equip_item", lvl)
end

local lastSaberRestore = 0
spawnLoop("saber", 4, function()
	local _, _, hum = character()
	if not hum or hum.Health <= 0 then return end
	-- only attempt occasionally — spamming equip trips the server's shop rate limit
	if not hasSaber() and (os.clock() - lastSaberRestore) > 25 then
		lastSaberRestore = os.clock()
		restoreSaber()
	end
end)

----------------------------------------------------------------------
-- FARM: swing in place (safe). Optional boss lock teleports onto the
-- GROUND under the boss — never up into the kill zone that floats above
-- it (flying/jumping near a boss is an instant kill in this game).
----------------------------------------------------------------------
local bossStatus = "—"
spawnLoop("farm", 0, function()
	if not Config.AutoFarm then
		bossStatus = "выкл"
		task.wait(0.3)
		return
	end
	local rate = math.clamp(Config.SwingRate, 1, 60)
	local delay = 1 / rate
	local char, hrp, hum = character()

	if Config.BossLock and hrp and hum and hum.Health > 0 then
		local model, part = findLiveBoss()
		if model and part then
			silenceEggController()
			-- The boss is a giant model: its root floats high but it stands on
			-- the arena floor (Boss.Place.Base ~Y183). Standing under/beside the
			-- root puts you in the air = instant death. Park on the arena floor,
			-- offset toward arena centre so we're next to the boss, not inside it.
			local bf = Workspace:FindFirstChild("Boss")
			local base = bf and bf:FindFirstChild("Place") and bf.Place:FindFirstChild("Base")
			local arenaTop = base and (base.Position.Y + base.Size.Y / 2) or (part.Position.Y - 30)
			local arenaCenter = base and base.Position or part.Position
			local bp = part.Position
			local horiz = Vector3.new(bp.X, arenaTop + 3, bp.Z)
			local dir = Vector3.new(arenaCenter.X - bp.X, 0, arenaCenter.Z - bp.Z)
			dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(1, 0, 0)
			local target = horiz + dir * 16
			bossStatus = model.Name
			if (hrp.Position - target).Magnitude > 8 then
				pcall(function() hrp.CFrame = CFrame.new(target) end)
			end
		else
			bossStatus = "жду босса"
		end
	else
		bossStatus = "свинг"
	end
	Fire("SwingEvent")
	task.wait(delay)
end)

----------------------------------------------------------------------
-- UPGRADES: smart, threshold-gated (no blind spam)
----------------------------------------------------------------------
-- climb a "buy_all" ladder paid in `currency`, then equip the top tier
local function climbLadder(cfg, sig, lastKey, equipKey, currencyKey, st, maxTier, gatedFn)
	if not cfg then return end
	local last = num(st[lastKey])
	local equipped = num(st[equipKey])
	local top = maxTier or #cfg
	-- buy next if affordable
	local nextId = last + 1
	if gatedFn then
		while cfg[nextId] and gatedFn(cfg[nextId]) do nextId = nextId + 1 end
	end
	if nextId <= top and cfg[nextId] then
		local price = num(cfg[nextId].Price)
		if num(st[currencyKey]) >= price then
			Fire(sig, "buy_all", 1)
		end
	end
	-- equip the highest owned if not equipped
	if num(st[lastKey]) > equipped then
		Fire(sig, "equip_item", num(st[lastKey]))
	end
end

spawnLoop("upgrades", 1.5, function()
	local st = getStats()
	if not st then return end

	-- 1) DNA first — it raises the Strength cap; without it swings stop paying.
	if Config.AutoDNA and DNAs then
		climbLadder(DNAs, "DnaShopEvent", "LastDna", "DnaLevel", "Coins", st, #DNAs, function(entry)
			return entry.IsVIP or entry.IsGamepass
		end)
	end

	-- 2) Saber — linear multiplier on Strength & Coins (paid in Coins).
	if Config.AutoSaber and Sabers then
		climbLadder(Sabers, "SaberShopEvent", "LastSaber", "SaberLevel", "Coins", st, #Sabers, function(entry)
			return entry.IsVIP or entry.IsGamepass
		end)
	end

	-- 3) Class — Strength multiplier (paid in Coins). No buy_all: purchase one then equip.
	if Config.AutoClass and Classes then
		local last = num(st.LastClass)
		local nextId = last + 1
		if Classes[nextId] and num(st.Coins) >= num(Classes[nextId].Price) then
			Fire("ClassShopEvent", "purchase_each", nextId)
		end
		if num(st.LastClass) > num(st.Class) then
			Fire("ClassShopEvent", "equip_item", num(st.LastClass))
		end
	end

	-- 4) Auras — Strength/Coins multiplier (paid in Crowns).
	if Config.AutoAura and Auras then
		climbLadder(Auras, "AuraEvent", "LastAura", "AuraLevel", "Crowns", st, #Auras)
	end

	-- 5) Pet-Auras — Crown/Coins multiplier (paid in Crowns, end-game).
	if Config.AutoPetAura and PetAuras then
		climbLadder(PetAuras, "PetAuraEvent", "LastPetAura", "PetAuraLevel", "Crowns", st, #PetAuras)
	end

	-- 6) Boss Hit — more boss damage = bigger share of kill rewards (paid in Strength).
	if Config.AutoBossHit and BossLvls then
		climbLadder(BossLvls, "BossHitSkillEvent", "LastBossDamageLevel", "BossDamageLevel", "Strength", st, #BossLvls)
	end

	-- 7) Double Jump — mobility (paid in Strength).
	if Config.AutoJump and JumpLvls then
		climbLadder(JumpLvls, "JumpSkillEvent", "LastJumpLevel", "JumpLevel", "Strength", st, #JumpLvls)
	end
end)

----------------------------------------------------------------------
-- PETS: craft (merge), equip best, hatch best affordable egg
----------------------------------------------------------------------
spawnLoop("pets", 4, function()
	local d = getData()
	if not d or not d.Pets then return end
	local st = d.Statistics

	-- merge duplicates (10 identical -> 1 of next variant), frees storage
	if Config.AutoPetsCraft and PetRemote then
		pcall(function() PetRemote:FireServer("craft_all") end)
	end

	-- equip best pets by strength score
	if Config.AutoPetsEquip and PetRemote and PetsCfg and d.Pets.Owned then
		local typeMul = (GlobalCfg and GlobalCfg.PetTypeMultiply) or {Normal=1,Golden=1.5,Shiny=2,Rainbow=2.5,Void=3}
		local scored = {}
		for uid, petId in pairs(d.Pets.Owned) do
			local base = PetsCfg[petId] and num(PetsCfg[petId].StrengthMultiplier) or 0
			local variant = d.Pets.OwnedType and d.Pets.OwnedType[uid] or "Normal"
			local score = base * (typeMul[variant] or 1)
			table.insert(scored, {uid = uid, score = score})
		end
		table.sort(scored, function(a, b) return a.score > b.score end)
		local equipped = d.Pets.Equipped or {}
		local equippedCount = 0
		for _ in pairs(equipped) do equippedCount = equippedCount + 1 end
		-- equip the strongest that are not yet equipped (server caps the count itself)
		local want = 8
		for i = 1, math.min(want, #scored) do
			local uid = scored[i].uid
			if not equipped[uid] then
				pcall(function() PetRemote:FireServer("toggle", uid) end)
				task.wait(0.15)
			end
		end
	end

	-- sell weakest surplus pets (irreversible) — never touches equipped or locked,
	-- keeps the strongest SellKeep. Runs after craft so merged groups survive.
	if Config.AutoSell and PetRemote and PetsCfg and d.Pets.Owned then
		local typeMul = (GlobalCfg and GlobalCfg.PetTypeMultiply) or {Normal=1,Golden=1.5,Shiny=2,Rainbow=2.5,Void=3}
		local equipped = d.Pets.Equipped or {}
		local locked = d.Pets.Locked or {}
		local sellable = {}
		for uid, petId in pairs(d.Pets.Owned) do
			if not equipped[uid] and not locked[uid] then
				local base = PetsCfg[petId] and num(PetsCfg[petId].StrengthMultiplier) or 0
				local variant = d.Pets.OwnedType and d.Pets.OwnedType[uid] or "Normal"
				table.insert(sellable, { uid = uid, score = base * (typeMul[variant] or 1) })
			end
		end
		table.sort(sellable, function(a, b) return a.score > b.score end)
		local keep = math.max(0, num(Config.SellKeep))
		local sold = 0
		for i = keep + 1, #sellable do
			if sold >= 12 then break end -- throttle so we never machine-gun the remote
			pcall(function() PetRemote:FireServer("delete", sellable[i].uid) end)
			sold = sold + 1
			task.wait(0.12)
		end
	end

	-- hatch the best egg the island + crown balance allow
	if Config.AutoHatch and Eggs and st then
		local island = maxIsland(st)
		local crowns = num(st.Crowns)
		local gp = d.GamePassesOwned or {}
		local hatchType = gp["x3 Egg Hatch"] and "Triple" or "One"
		local mult = hatchType == "Triple" and 3 or 1
		-- storage check
		local cap = 50
		if GlobalCfg and GlobalCfg.MaxPetCapacity then
			cap = GlobalCfg.MaxPetCapacity[gp["+200 Pet Storage"] == true] or 50
		end
		local owned = 0
		if d.Pets.Owned then for _ in pairs(d.Pets.Owned) do owned = owned + 1 end end
		if owned < cap - mult then
			local best
			for _, egg in pairs(Eggs) do
				if type(egg) == "table" and egg.Price and egg.ID then
					local reqIsland = num(egg.RequirementIsland)
					local currencyKey = egg.Currency or "Crowns"
					local bal = num(st[currencyKey])
					if reqIsland <= island and bal >= num(egg.Price) * mult then
						if not best or num(egg.Price) > num(best.Price) then
							best = egg
						end
					end
				end
			end
			if best then
				Fire("EggEvent", hatchType, best.ID, d.Pets.AutoDeletes)
			end
		end
	end
end)

----------------------------------------------------------------------
-- DAILY reward (zone-based, every 12h)
----------------------------------------------------------------------
spawnLoop("daily", 30, function()
	if not Config.AutoDaily then return end
	local st = getStats()
	if not st then return end
	local cd = (GlobalCfg and GlobalCfg.DailyRewardData and num(GlobalCfg.DailyRewardData.Cooldown)) or 43200
	local last = num(st.DailyReward)
	if last == 0 or (os.time() - last) >= cd then
		local zones = Workspace:FindFirstChild("Zones")
		local part = zones and zones:FindFirstChild("DailyReward")
		part = part and (part:FindFirstChild("DailyReward") or part:FindFirstChildWhichIsA("BasePart"))
		local _, hrp = character()
		if part and hrp then
			local saved = hrp.CFrame
			pcall(function() hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0) end)
			task.wait(2)
			-- the farm loop will pull us back to the boss afterwards
		end
	end
end)

----------------------------------------------------------------------
-- AUTO RECONNECT (night-safe)
----------------------------------------------------------------------
spawnLoop("reconnect", 8, function()
	if not Config.AutoReconnect then return end
	local _, _, hum = character()
	-- ask the server to resync/keep us in; harmless when alive
	if not LocalPlayer.Parent then return end
end)

track(Players.PlayerRemoving:Connect(function(p)
	if p == LocalPlayer and Config.AutoReconnect then
		pcall(function() Invoke("Reconnect", 5, { auto = true }) end)
	end
end))

----------------------------------------------------------------------
-- one-shot setup: performance settings + codes
----------------------------------------------------------------------
task.spawn(function()
	task.wait(2)
	local d = getData()
	if d and d.Settings then
		if Config.HidePets then
			if d.Settings.HidePets == false then Fire("SettingEvent", "HidePets") end
			if d.Settings.HideOtherPets == false then Fire("SettingEvent", "HideOtherPets") end
		end
	end
end)

----------------------------------------------------------------------
-- GUI  (Violet-Noir acrylic, no backdrop blur)
----------------------------------------------------------------------
local PALETTE = {
	bg       = Color3.fromRGB(14, 14, 20),
	panel    = Color3.fromRGB(22, 22, 32),
	row      = Color3.fromRGB(30, 30, 44),
	stroke   = Color3.fromRGB(60, 58, 90),
	text     = Color3.fromRGB(232, 232, 245),
	subtext  = Color3.fromRGB(150, 150, 175),
	accentA  = Color3.fromRGB(138, 99, 246),
	accentB  = Color3.fromRGB(70, 200, 235),
	on       = Color3.fromRGB(124, 92, 250),
	off      = Color3.fromRGB(58, 58, 78),
	good     = Color3.fromRGB(110, 230, 160),
}

local gui = Instance.new("ScreenGui")
gui.Name = "OG_Saber_UI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
pcall(function() protectgui(gui) end)
gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
OG.gui = gui

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = p
	return c
end
local function stroke(p, col, th)
	local s = Instance.new("UIStroke")
	s.Color = col or PALETTE.stroke
	s.Thickness = th or 1
	s.Parent = p
	return s
end
local function pad(p, n)
	local u = Instance.new("UIPadding")
	u.PaddingLeft = UDim.new(0, n); u.PaddingRight = UDim.new(0, n)
	u.PaddingTop = UDim.new(0, n); u.PaddingBottom = UDim.new(0, n)
	u.Parent = p
	return u
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 320, 0, 470)
main.Position = UDim2.new(0, 40, 0.5, -235)
main.BackgroundColor3 = PALETTE.bg
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
corner(main, 14)
stroke(main, PALETTE.stroke, 1.4)

-- header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = PALETTE.panel
header.BorderSizePixel = 0
header.Parent = main
corner(header, 14)
do
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(PALETTE.accentA, PALETTE.accentB)
	grad.Rotation = 12
	grad.Transparency = NumberSequence.new(0.86)
	grad.Parent = header
end

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 16, 0, 0)
title.Size = UDim2.new(1, -90, 1, 0)
title.Font = Enum.Font.GothamBold
title.Text = "OG Saber Simulator"
title.TextSize = 16
title.TextColor3 = PALETTE.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 16, 0, 28)
subtitle.Size = UDim2.new(1, -90, 0, 16)
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "auto progression"
subtitle.TextSize = 11
subtitle.TextColor3 = PALETTE.subtext
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = header

local function headerButton(txt, off, col)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 30, 0, 30)
	b.Position = UDim2.new(1, off, 0, 11)
	b.BackgroundColor3 = PALETTE.row
	b.Text = txt
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = col or PALETTE.text
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = header
	corner(b, 8)
	stroke(b, PALETTE.stroke, 1)
	return b
end
local closeBtn = headerButton("✕", -40, Color3.fromRGB(255, 120, 120))
local minBtn = headerButton("—", -76)

-- status panel
local status = Instance.new("Frame")
status.Position = UDim2.new(0, 12, 0, 62)
status.Size = UDim2.new(1, -24, 0, 70)
status.BackgroundColor3 = PALETTE.panel
status.BorderSizePixel = 0
status.Parent = main
corner(status, 10)
stroke(status, PALETTE.stroke, 1)

local function statLabel(x, w, name)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.new(x, 0, 0, 8)
	holder.Size = UDim2.new(w, 0, 1, -16)
	holder.Parent = status
	local cap = Instance.new("TextLabel")
	cap.BackgroundTransparency = 1
	cap.Size = UDim2.new(1, 0, 0, 14)
	cap.Font = Enum.Font.Gotham
	cap.Text = name
	cap.TextSize = 11
	cap.TextColor3 = PALETTE.subtext
	cap.Parent = holder
	local val = Instance.new("TextLabel")
	val.BackgroundTransparency = 1
	val.Position = UDim2.new(0, 0, 0, 16)
	val.Size = UDim2.new(1, 0, 0, 24)
	val.Font = Enum.Font.GothamBold
	val.Text = "—"
	val.TextSize = 16
	val.TextColor3 = PALETTE.text
	val.TextXAlignment = Enum.TextXAlignment.Left
	val.Parent = holder
	cap.TextXAlignment = Enum.TextXAlignment.Left
	return val
end
local stStrength = statLabel(0.04, 0.32, "Strength")
local stCoins    = statLabel(0.37, 0.32, "Coins")
local stCrowns   = statLabel(0.70, 0.30, "Crowns")

local bossLine = Instance.new("TextLabel")
bossLine.BackgroundTransparency = 1
bossLine.Position = UDim2.new(0, 12, 0, 136)
bossLine.Size = UDim2.new(1, -24, 0, 18)
bossLine.Font = Enum.Font.Gotham
bossLine.Text = "boss: —"
bossLine.TextSize = 12
bossLine.TextColor3 = PALETTE.subtext
bossLine.TextXAlignment = Enum.TextXAlignment.Left
bossLine.Parent = main

-- scrolling body
local body = Instance.new("ScrollingFrame")
body.Position = UDim2.new(0, 12, 0, 160)
body.Size = UDim2.new(1, -24, 1, -172)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 3
body.ScrollBarImageColor3 = PALETTE.accentA
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = main
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 7)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = body

local order = 0
local function nextOrder() order = order + 1 return order end

local function sectionHeader(txt)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 20)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.Text = txt:upper()
	l.TextSize = 11
	l.TextColor3 = PALETTE.accentB
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.LayoutOrder = nextOrder()
	l.Parent = body
end

local function toggleRow(label, key)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 38)
	row.BackgroundColor3 = PALETTE.row
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = body
	corner(row, 9)
	stroke(row, PALETTE.stroke, 1)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 12, 0, 0)
	name.Size = UDim2.new(1, -70, 1, 0)
	name.Font = Enum.Font.GothamMedium
	name.Text = label
	name.TextSize = 13
	name.TextColor3 = PALETTE.text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local track_ = Instance.new("Frame")
	track_.AnchorPoint = Vector2.new(1, 0.5)
	track_.Position = UDim2.new(1, -12, 0.5, 0)
	track_.Size = UDim2.new(0, 44, 0, 22)
	track_.BackgroundColor3 = Config[key] and PALETTE.on or PALETTE.off
	track_.BorderSizePixel = 0
	track_.Parent = row
	corner(track_, 11)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = Config[key] and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.BackgroundColor3 = Color3.fromRGB(245, 245, 255)
	knob.BorderSizePixel = 0
	knob.Parent = track_
	corner(knob, 9)

	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.Text = ""
	btn.Parent = row

	local function refresh(animate)
		local on = Config[key]
		local goalColor = on and PALETTE.on or PALETTE.off
		local goalPos = on and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		if animate then
			TweenService:Create(track_, TweenInfo.new(0.16), {BackgroundColor3 = goalColor}):Play()
			TweenService:Create(knob, TweenInfo.new(0.16), {Position = goalPos}):Play()
		else
			track_.BackgroundColor3 = goalColor
			knob.Position = goalPos
		end
	end

	track(btn.MouseButton1Click:Connect(function()
		Config[key] = not Config[key]
		refresh(true)
		saveConfig()
	end))
	return row
end

local function sliderRow(label, key, minV, maxV)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 48)
	row.BackgroundColor3 = PALETTE.row
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = body
	corner(row, 9)
	stroke(row, PALETTE.stroke, 1)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 12, 0, 6)
	name.Size = UDim2.new(1, -24, 0, 16)
	name.Font = Enum.Font.GothamMedium
	name.Text = label
	name.TextSize = 13
	name.TextColor3 = PALETTE.text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = row

	local valLbl = Instance.new("TextLabel")
	valLbl.BackgroundTransparency = 1
	valLbl.Position = UDim2.new(1, -54, 0, 6)
	valLbl.Size = UDim2.new(0, 42, 0, 16)
	valLbl.Font = Enum.Font.GothamBold
	valLbl.Text = tostring(Config[key])
	valLbl.TextSize = 13
	valLbl.TextColor3 = PALETTE.accentB
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Parent = row

	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 12, 0, 30)
	bar.Size = UDim2.new(1, -24, 0, 8)
	bar.BackgroundColor3 = PALETTE.off
	bar.BorderSizePixel = 0
	bar.Parent = row
	corner(bar, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new((Config[key] - minV) / (maxV - minV), 0, 1, 0)
	fill.BackgroundColor3 = PALETTE.on
	fill.BorderSizePixel = 0
	fill.Parent = bar
	corner(fill, 4)
	do
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(PALETTE.accentA, PALETTE.accentB)
		g.Parent = fill
	end

	local dragging = false
	local function setFromX(px)
		local rel = math.clamp((px - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local v = math.floor(minV + rel * (maxV - minV) + 0.5)
		Config[key] = v
		valLbl.Text = tostring(v)
		fill.Size = UDim2.new((v - minV) / (maxV - minV), 0, 1, 0)
		saveConfig()
	end
	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.new(0, 12, 0, 22)
	hit.Size = UDim2.new(1, -24, 0, 24)
	hit.Text = ""
	hit.Parent = row
	track(hit.MouseButton1Down:Connect(function() dragging = true end))
	track(UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	track(UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			setFromX(i.Position.X)
		end
	end))
	track(hit.MouseButton1Click:Connect(function()
		setFromX(UserInputService:GetMouseLocation().X)
	end))
end

-- build the panel
sectionHeader("Фарм")
toggleRow("Авто-фарм (свинг)", "AutoFarm")
toggleRow("Держаться у босса", "BossLock")
sliderRow("Свингов / сек", "SwingRate", 1, 40)

sectionHeader("Апгрейды")
toggleRow("DNA (снять кап силы)", "AutoDNA")
toggleRow("Сабли", "AutoSaber")
toggleRow("Классы", "AutoClass")
toggleRow("Ауры", "AutoAura")
toggleRow("Пет-ауры", "AutoPetAura")
toggleRow("Урон по боссам", "AutoBossHit")
toggleRow("Двойной прыжок", "AutoJump")

sectionHeader("Питомцы")
toggleRow("Авто-мердж", "AutoPetsCraft")
toggleRow("Авто-экип лучших", "AutoPetsEquip")
toggleRow("Авто-продажа слабых", "AutoSell")
toggleRow("Авто-вылупление", "AutoHatch")

sectionHeader("Прочее")
toggleRow("Дейли-награда", "AutoDaily")
toggleRow("Авто-реконнект", "AutoReconnect")
toggleRow("Скрыть петов (FPS)", "HidePets")
toggleRow("Анти-AFK", "AntiAFK")

-- unload button
local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, 0, 0, 36)
unloadBtn.BackgroundColor3 = Color3.fromRGB(48, 26, 34)
unloadBtn.Text = "Выгрузить скрипт"
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.TextSize = 13
unloadBtn.TextColor3 = Color3.fromRGB(255, 140, 140)
unloadBtn.BorderSizePixel = 0
unloadBtn.LayoutOrder = nextOrder()
unloadBtn.Parent = body
corner(unloadBtn, 9)
stroke(unloadBtn, Color3.fromRGB(120, 60, 70), 1)

----------------------------------------------------------------------
-- dragging
----------------------------------------------------------------------
do
	local dragging, dragStart, startPos
	track(header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = i.Position
			startPos = main.Position
		end
	end))
	track(UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local delta = i.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

----------------------------------------------------------------------
-- minimize / close
----------------------------------------------------------------------
local function applyMinimized(animate)
	local target = Config.Minimized and UDim2.new(main.Size.X.Scale, main.Size.X.Offset, 0, 52) or UDim2.new(0, 320, 0, 470)
	status.Visible = not Config.Minimized
	bossLine.Visible = not Config.Minimized
	body.Visible = not Config.Minimized
	if animate then
		TweenService:Create(main, TweenInfo.new(0.18), {Size = target}):Play()
	else
		main.Size = target
	end
end
track(minBtn.MouseButton1Click:Connect(function()
	Config.Minimized = not Config.Minimized
	applyMinimized(true)
	saveConfig()
end))
applyMinimized(false)

----------------------------------------------------------------------
-- live status updater
----------------------------------------------------------------------
spawnLoop("ui", 0.4, function()
	local st = getStats()
	if st then
		stStrength.Text = abbreviate(st.Strength)
		stCoins.Text = abbreviate(st.Coins)
		stCrowns.Text = abbreviate(st.Crowns)
	end
	bossLine.Text = "boss: " .. tostring(bossStatus)
end)

----------------------------------------------------------------------
-- unload
----------------------------------------------------------------------
local function unload()
	OG.running = false
	for _, c in ipairs(OG.connections) do pcall(function() c:Disconnect() end) end
	OG.connections = {}
	task.delay(0.1, function()
		if OG.gui then pcall(function() OG.gui:Destroy() end) end
	end)
	_G.OG_SABER = nil
end
OG.unload = unload
track(closeBtn.MouseButton1Click:Connect(unload))
track(unloadBtn.MouseButton1Click:Connect(unload))

----------------------------------------------------------------------
-- redeem codes once on boot (server validates / ignores used)
----------------------------------------------------------------------
task.spawn(function()
	task.wait(3)
	local codes = { "OG", "RELEASE", "LIKE", "FREE", "UPDATE", "SABER" }
	for _, c in ipairs(codes) do
		if not OG.running then break end
		Fire("CodesEvent", c)
		task.wait(1.5)
	end
end)

print("[OG Saber Simulator] загружен. Авто-фарм запущен.")
