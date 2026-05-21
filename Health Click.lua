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
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local SharedEnvironment = getgenv and getgenv() or _G
local PreviousContext = SharedEnvironment.SigmatikHealthClickContext

if PreviousContext and PreviousContext.Cleanup then
	pcall(PreviousContext.Cleanup)
end

local function loadLibrary()
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
	Connections = {},
	Controller = nil,
	Cached = {},
	-- click
	AutoClick = false, ClickInterval = 0.00001, Clicks = 0,
	-- damage / heal
	AutoDamage = false, DamageAmount = 50, DamageInterval = 0.00001,
	AutoHeal = false, HealAmount = 1, HealInterval = 0.00001,
	-- treadmill
	AutoTredmill = false, TredmillExponent = 12, TredmillInterval = 0.05,
	-- rebirth
	AutoRebirth = false, RebirthInterval = 0.5,
	-- move level
	AutoMoveLevel = false, MoveLevelAmount = 1, MoveLevelInterval = 0.5,
	-- spin
	AutoSpin = false, SpinInterval = 0.00001,
	-- wheel
	AutoWheel = false, WheelReward = 6, WheelInterval = 0.5,
	-- eco / wins
	AutoAddWins = false, AddWinsExponent = 9, AddWinsInterval = 0.5,
	-- daily claims
	AutoClaimDaily = false, AutoClaimGroup = false, AutoClaimFriend = false,
	AutoTipStartPack = false, AutoDailyLogin = false, ClaimsInterval = 5,
	-- rewards
	AutoTryGetReward = false, AutoTryGetDaily = false, RewardsInterval = 1,
	-- pets
	AutoPetPack1 = false, AutoPetPack2 = false, AutoIndexReward = false,
	AutoCraftAll = false, AutoEquipBest = false, AutoFruit = false, AutoToy = false,
	PetsInterval = 1,
	-- snowboard
	AutoTouchBoard = false, TouchBoardInterval = 0.1,
	-- world wins
	AutoRewardWins = false, AutoPremiumWins = false, AutoFunnel = false, AutoDoneGen = false,
	WorldWinsExponent = 9, WorldWinsInterval = 0.5,
	-- player
	FlyEnabled = false, FlySpeed = 60, WalkSpeed = 16, JumpPower = 50,
	SwimEnabled = false, NoclipEnabled = false,
	-- visuals
	EspEnabled = false, EspColor = Color3.fromRGB(0, 255, 0),
	FullBright = false, NoFog = false,
	-- TP
	AutoTpNearest = false, TpNearestInterval = 0.5,
	TpClickEnabled = false,
	-- anti damage
	AntiDamage = false, OriginalTakeDamageFire = nil,
	-- runtime caches
	EspHighlights = {},
	NoclipConn = nil,
	FlyBV = nil, FlyBG = nil, FlyConn = nil,
	LightingBackup = nil,
	TpClickConn = nil,
	-- loop ids (incremented to invalidate previous loops)
	Loops = {},
}

SharedEnvironment.SigmatikHealthClickContext = Context

local function nextLoopId(name)
	Context.Loops[name] = (Context.Loops[name] or 0) + 1
	return Context.Loops[name]
end

local function addConn(c) if c then Context.Connections[#Context.Connections+1] = c end end
local function disconnectAll()
	for _,c in ipairs(Context.Connections) do pcall(function() c:Disconnect() end) end
	table.clear(Context.Connections)
end

----------------------------------------------------------------
-- Remote helpers
----------------------------------------------------------------

local function getRemoteByName(name)
	local cached = Context.Cached[name]
	if cached and cached.Parent then return cached end
	local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not Remotes then return nil end
	local r = Remotes:FindFirstChild(name)
	if r then Context.Cached[name] = r end
	return r
end

local function getCSRemote(folder, name)
	local key = "CS."..folder.."."..name
	local cached = Context.Cached[key]
	if cached and cached.Parent then return cached end
	local root = ReplicatedStorage:FindFirstChild("Remote")
	if not root then return nil end
	local ev = root:FindFirstChild("Event")
	if not ev then return nil end
	local f = ev:FindFirstChild(folder)
	if not f then return nil end
	local r = f:FindFirstChild(name)
	if r then Context.Cached[key] = r end
	return r
end

local function fireSafe(remote, ...)
	if not remote or not remote.Parent then return end
	local args = table.pack(...)
	pcall(function()
		if remote.ClassName == "RemoteEvent" then remote:FireServer(table.unpack(args, 1, args.n))
		elseif remote.ClassName == "RemoteFunction" then remote:InvokeServer(table.unpack(args, 1, args.n)) end
	end)
end

local function fireMHP() local r = getRemoteByName("MHP"); if r then fireSafe(r) end end
local function fireTakeDamage(n) local r = getRemoteByName("TakeDamage"); if r then fireSafe(r, n) end end
local function fireAddSpin() local r = getRemoteByName("AddSpin"); if r then fireSafe(r) end end
local function fireWheel(id) local r = getRemoteByName("SpinEventWheel"); if r then fireSafe(r, id) end end
local function fireMoveLevel(n) local r = getRemoteByName("Move Level"); if r then fireSafe(r, n) end end
local function fireTredmill(n) local r = getRemoteByName("Gain Hp From Tredmill"); if r then fireSafe(r, n) end end
local function fireRebirth() local r = ReplicatedStorage:FindFirstChild("RebirthRemote"); if r then fireSafe(r) end end
local function fireClaimDaily() local r = getRemoteByName("ClaimDaily"); if r then fireSafe(r) end end

local function fireWorldGenRemote(name, ...)
	local wg = ReplicatedStorage:FindFirstChild("Random World Generation")
	if not wg then return end
	local rs = wg:FindFirstChild("Remotes")
	if not rs then return end
	local r = rs:FindFirstChild(name)
	if r then fireSafe(r, ...) end
end

----------------------------------------------------------------
-- Loop helpers
----------------------------------------------------------------

local function waitInterval(n)
	if n and n >= 0.01 then task.wait(n) else RunService.Heartbeat:Wait() end
end

-- Single loop with name + flag check + per-tick action
local function startLoop(name, getEnabled, getInterval, action)
	local id = nextLoopId(name)
	task.spawn(function()
		while Context.Alive and getEnabled() and Context.Loops[name] == id do
			pcall(action)
			waitInterval(getInterval())
		end
	end)
end

local function syncLoop(name, flagKey, intervalKey, action)
	if Context[flagKey] then
		startLoop(name, function() return Context[flagKey] end, function() return Context[intervalKey] end, action)
	else
		nextLoopId(name) -- invalidate previous
	end
end

----------------------------------------------------------------
-- Click loop (counts clicks)
----------------------------------------------------------------

local function performClick()
	fireMHP()
	Context.Clicks = Context.Clicks + 1
end

local function syncClick()
	if Context.AutoClick then
		startLoop("click", function() return Context.AutoClick end, function() return Context.ClickInterval end, performClick)
	else
		nextLoopId("click")
	end
end

----------------------------------------------------------------
-- Player utilities
----------------------------------------------------------------

local function getCharacter() return LocalPlayer.Character end
local function getHumanoid() local c = getCharacter(); return c and c:FindFirstChildOfClass("Humanoid") end
local function getRoot() local c = getCharacter(); return c and c:FindFirstChild("HumanoidRootPart") end

local function applyWalkSpeed() local h = getHumanoid(); if h then h.WalkSpeed = Context.WalkSpeed end end
local function applyJumpPower() local h = getHumanoid(); if h then h.UseJumpPower = true; h.JumpPower = Context.JumpPower end end

local function startFly()
	local root = getRoot(); local h = getHumanoid()
	if not root or not h then return end
	if Context.FlyBV then pcall(function() Context.FlyBV:Destroy() end) end
	if Context.FlyBG then pcall(function() Context.FlyBG:Destroy() end) end
	if Context.FlyConn then pcall(function() Context.FlyConn:Disconnect() end) end
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = Vector3.zero
	bv.Parent = root
	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	bg.D = 50; bg.P = 10000; bg.CFrame = root.CFrame
	bg.Parent = root
	Context.FlyBV = bv; Context.FlyBG = bg
	h.PlatformStand = true
	Context.FlyConn = RunService.RenderStepped:Connect(function()
		if not Context.FlyEnabled then return end
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0,1,0) end
		if move.Magnitude > 0 then move = move.Unit * Context.FlySpeed end
		bv.Velocity = move
		bg.CFrame = cam.CFrame
	end)
end

local function stopFly()
	if Context.FlyConn then pcall(function() Context.FlyConn:Disconnect() end); Context.FlyConn = nil end
	if Context.FlyBV then pcall(function() Context.FlyBV:Destroy() end); Context.FlyBV = nil end
	if Context.FlyBG then pcall(function() Context.FlyBG:Destroy() end); Context.FlyBG = nil end
	local h = getHumanoid(); if h then h.PlatformStand = false end
end

local function setFly(v) Context.FlyEnabled = not not v; if Context.FlyEnabled then startFly() else stopFly() end end

local function setSwim(v)
	Context.SwimEnabled = not not v
	if Context.SwimEnabled then
		task.spawn(function()
			while Context.SwimEnabled and Context.Alive do
				local h = getHumanoid(); if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Swimming) end) end
				task.wait(0.1)
			end
		end)
	end
end

local function setNoclip(v)
	Context.NoclipEnabled = not not v
	if Context.NoclipConn then pcall(function() Context.NoclipConn:Disconnect() end); Context.NoclipConn = nil end
	if Context.NoclipEnabled then
		Context.NoclipConn = RunService.Stepped:Connect(function()
			local c = getCharacter(); if not c then return end
			for _,p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
			end
		end)
	end
end

local function applyEspToPlayer(p)
	if p == LocalPlayer then return end
	local char = p.Character; if not char then return end
	if Context.EspHighlights[p] and Context.EspHighlights[p].Parent then
		Context.EspHighlights[p].FillColor = Context.EspColor
		Context.EspHighlights[p].OutlineColor = Context.EspColor
		Context.EspHighlights[p].Adornee = char
		return
	end
	local hl = Instance.new("Highlight")
	hl.Name = "SigmatikESP"
	hl.FillColor = Context.EspColor; hl.OutlineColor = Context.EspColor
	hl.FillTransparency = 0.5; hl.OutlineTransparency = 0
	hl.Adornee = char; hl.Parent = char
	Context.EspHighlights[p] = hl
end

local function clearEsp()
	for p, hl in pairs(Context.EspHighlights) do
		pcall(function() hl:Destroy() end); Context.EspHighlights[p] = nil
	end
end

local function refreshEsp() for _,p in ipairs(Players:GetPlayers()) do applyEspToPlayer(p) end end

local function setEsp(v)
	Context.EspEnabled = not not v
	if Context.EspEnabled then
		refreshEsp()
		task.spawn(function() while Context.EspEnabled and Context.Alive do refreshEsp(); task.wait(2) end end)
	else clearEsp() end
end

local function backupLighting()
	if Context.LightingBackup then return end
	Context.LightingBackup = {
		Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
		FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
		Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
		GlobalShadows = Lighting.GlobalShadows,
	}
end

local function restoreLighting()
	if not Context.LightingBackup then return end
	for k,v in pairs(Context.LightingBackup) do pcall(function() Lighting[k] = v end) end
end

local function setFullBright(v)
	Context.FullBright = not not v
	backupLighting()
	if Context.FullBright then
		Lighting.Brightness = 2; Lighting.ClockTime = 14; Lighting.GlobalShadows = false
		Lighting.Ambient = Color3.new(1,1,1); Lighting.OutdoorAmbient = Color3.new(1,1,1)
	else
		restoreLighting()
		if Context.NoFog then Lighting.FogEnd = 1e9; Lighting.FogStart = 1e9 end
	end
end

local function setNoFog(v)
	Context.NoFog = not not v
	backupLighting()
	if Context.NoFog then Lighting.FogEnd = 1e9; Lighting.FogStart = 1e9
	else Lighting.FogEnd = Context.LightingBackup.FogEnd; Lighting.FogStart = Context.LightingBackup.FogStart end
end

-- TP Click via key X (default)
local function tpToMouse()
	local mroot = getRoot(); if not mroot then return end
	local mouse = LocalPlayer:GetMouse()
	if mouse and mouse.Hit then
		mroot.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0,3,0))
	end
end

local function setTpClick(v)
	Context.TpClickEnabled = not not v
	if Context.TpClickConn then pcall(function() Context.TpClickConn:Disconnect() end); Context.TpClickConn = nil end
	if Context.TpClickEnabled then
		Context.TpClickConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.KeyCode == Enum.KeyCode.X then tpToMouse() end
		end)
	end
end

-- TP nearest
local function tpToNearest()
	local mroot = getRoot(); if not mroot then return end
	local nearest, dist = nil, math.huge
	for _,p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			if r then
				local d = (r.Position - mroot.Position).Magnitude
				if d < dist then dist = d; nearest = r end
			end
		end
	end
	if nearest then mroot.CFrame = nearest.CFrame + Vector3.new(0,3,0) end
end

----------------------------------------------------------------
-- Anti-Damage
----------------------------------------------------------------

local function setAntiDamage(v)
	Context.AntiDamage = not not v
	local r = getRemoteByName("TakeDamage"); if not r then return end
	if Context.AntiDamage then
		if not Context.OriginalTakeDamageFire then
			Context.OriginalTakeDamageFire = r.FireServer
			r.FireServer = function() return nil end
		end
	else
		if Context.OriginalTakeDamageFire then
			r.FireServer = Context.OriginalTakeDamageFire
			Context.OriginalTakeDamageFire = nil
		end
	end
end

----------------------------------------------------------------
-- Sync helpers per category
----------------------------------------------------------------

local function syncDamage() syncLoop("damage", "AutoDamage", "DamageInterval", function() fireTakeDamage(Context.DamageAmount) end) end
local function syncHeal() syncLoop("heal", "AutoHeal", "HealInterval", function() fireTakeDamage(-math.abs(Context.HealAmount)) end) end
local function syncTredmill() syncLoop("tred", "AutoTredmill", "TredmillInterval", function() fireTredmill(10 ^ Context.TredmillExponent) end) end
local function syncRebirth() syncLoop("rebirth", "AutoRebirth", "RebirthInterval", fireRebirth) end
local function syncMoveLevel() syncLoop("movelv", "AutoMoveLevel", "MoveLevelInterval", function() fireMoveLevel(Context.MoveLevelAmount) end) end
local function syncSpin() syncLoop("spin", "AutoSpin", "SpinInterval", fireAddSpin) end
local function syncWheel() syncLoop("wheel", "AutoWheel", "WheelInterval", function() fireWheel(Context.WheelReward) end) end
local function syncAddWins()
	syncLoop("wins", "AutoAddWins", "AddWinsInterval", function()
		local r = getCSRemote("Eco", "[C-S]AddPlayerWins")
		if r then fireSafe(r, 10 ^ Context.AddWinsExponent) end
	end)
end
local function syncDailyClaims()
	syncLoop("claims", "AutoClaimDaily", "ClaimsInterval", fireClaimDaily)
	syncLoop("claimGroup", "AutoClaimGroup", "ClaimsInterval", function()
		local r = getCSRemote("Group", "[C-S]TryClaim"); if r then fireSafe(r) end
		local g = getRemoteByName("Group Reward Activator"); if g then fireSafe(g) end
		local s = getRemoteByName("StartGroupRewardEvent"); if s then fireSafe(s) end
	end)
	syncLoop("claimFriend", "AutoClaimFriend", "ClaimsInterval", function()
		local r = getCSRemote("Pem", "[C-S]TryClaimFriend"); if r then fireSafe(r) end
	end)
	syncLoop("tipPack", "AutoTipStartPack", "ClaimsInterval", function()
		local r = getCSRemote("Pem", "[C-S]TryTipStartPack"); if r then fireSafe(r) end
	end)
	syncLoop("dailyLogin", "AutoDailyLogin", "ClaimsInterval", function()
		local r = getCSRemote("DailyLogin", "[C-S]PlayerTryDailyLogin"); if r then fireSafe(r) end
	end)
end
local function syncRewardsLoop()
	syncLoop("getReward", "AutoTryGetReward", "RewardsInterval", function()
		local r = getCSRemote("Reward", "[C-S]TryGetReward")
		if r then for i=1,15 do fireSafe(r, i) end end
	end)
	syncLoop("getDaily", "AutoTryGetDaily", "RewardsInterval", function()
		local r = getCSRemote("Reward", "[C-S]TryGetDailyReward")
		if r then for i=1,7 do fireSafe(r, i) end end
	end)
end
local function syncPets()
	syncLoop("petPack1", "AutoPetPack1", "PetsInterval", function() local r = getCSRemote("Pet","[C-S]TryGetPetPack"); if r then fireSafe(r) end end)
	syncLoop("petPack2", "AutoPetPack2", "PetsInterval", function() local r = getCSRemote("Pet","[C-S]TryGetPetPack2"); if r then fireSafe(r) end end)
	syncLoop("indexRwd", "AutoIndexReward", "PetsInterval", function() local r = getCSRemote("Pet","[C-S]TryGetIndexReward"); if r then for i=1,30 do fireSafe(r, i) end end end)
	syncLoop("craftAll", "AutoCraftAll", "PetsInterval", function() local r = getCSRemote("Pet","[C-S]TryCraftAll"); if r then fireSafe(r) end end)
	syncLoop("equipBest", "AutoEquipBest", "PetsInterval", function() local r = getCSRemote("Pet","[C-S]TryEquipBest"); if r then fireSafe(r) end end)
	syncLoop("fruit", "AutoFruit", "PetsInterval", function() local r = getCSRemote("Pet","[C-S]TryFruit"); if r then fireSafe(r) end end)
	syncLoop("toy", "AutoToy", "PetsInterval", function() local r = getCSRemote("Pet","[C-S]TryToy"); if r then fireSafe(r) end end)
end
local function syncBoard() syncLoop("board", "AutoTouchBoard", "TouchBoardInterval", function()
	local r = getCSRemote("SnowBoard", "[C-S]TouchBoard"); if r then fireSafe(r) end
end) end
local function syncWorldWins()
	syncLoop("rwdWins", "AutoRewardWins", "WorldWinsInterval", function() fireWorldGenRemote("Reward Wins", 10 ^ Context.WorldWinsExponent) end)
	syncLoop("premWins", "AutoPremiumWins", "WorldWinsInterval", function() fireWorldGenRemote("Reward Premium Wins", 10 ^ Context.WorldWinsExponent) end)
	syncLoop("funnel", "AutoFunnel", "WorldWinsInterval", function() fireWorldGenRemote("Funnel Every 25th Step") end)
	syncLoop("doneGen", "AutoDoneGen", "WorldWinsInterval", function() fireWorldGenRemote("Done Generating") end)
end
local function syncTpNearest() syncLoop("tpNear", "AutoTpNearest", "TpNearestInterval", tpToNearest) end

----------------------------------------------------------------
-- UI declarative tree (V2 API)
----------------------------------------------------------------

local function makeToggle(name, key, sync)
	return { Type = "toggle", Name = name, Value = false, Callback = function(v) Context[key] = v; if sync then sync() end end }
end

local function makeSlider(name, key, mn, mx, inc, def, sync)
	return { Type = "slider", Name = name, Min = mn, Max = mx, Increment = inc, Value = def, Callback = function(v) Context[key] = v; if sync then sync() end end }
end

local function lbl(name, content) return { Type = "label", Name = name, Content = content or name } end

local controller = Library:Create({
	Title = "tg: @sigmatik323",
	ConfigName = "Health Click",
	Accent = "#ef4444",
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = "❤️ Health Click",
			Modules = {
				{
					Name = "Auto +1 Health Per Click",
					Enabled = false,
					Callback = function(v) Context.AutoClick = v; syncClick() end,
					Sections = {
						{ Name = "❤️ Click", Controls = {
							makeSlider("Click Interval", "ClickInterval", 0.00001, 1, 0.00001, 0.00001, syncClick),
							lbl("Status", "Status: idle"),
							lbl("Clicks", "Clicks: 0"),
							lbl("Target", "Target: Remotes.MHP"),
						}},
						{ Name = "💥 Take Damage", Controls = {
							makeToggle("Auto Take Damage", "AutoDamage", syncDamage),
							makeSlider("Damage Amount", "DamageAmount", 1, 1000, 1, 50, syncDamage),
							makeSlider("Damage Interval", "DamageInterval", 0.00001, 1, 0.00001, 0.00001, syncDamage),
						}},
						{ Name = "💚 Heal", Controls = {
							makeToggle("Auto Heal", "AutoHeal", syncHeal),
							makeSlider("Heal Amount", "HealAmount", 1, 1000, 1, 1, syncHeal),
							makeSlider("Heal Interval", "HealInterval", 0.00001, 1, 0.00001, 0.00001, syncHeal),
						}},
					},
				},
				{
					Name = "Auto Treadmill HP",
					Enabled = false,
					Callback = function(v) Context.AutoTredmill = v; syncTredmill() end,
					Sections = {{ Name = "🏋️ Treadmill", Controls = {
						makeSlider("Amount Exponent (10^X)", "TredmillExponent", 0, 18, 1, 12, syncTredmill),
						makeSlider("Interval", "TredmillInterval", 0.001, 1, 0.001, 0.05, syncTredmill),
					}}},
				},
				{
					Name = "Auto Rebirth",
					Enabled = false,
					Callback = function(v) Context.AutoRebirth = v; syncRebirth() end,
					Sections = {{ Name = "🔄 Rebirth", Controls = {
						makeSlider("Interval", "RebirthInterval", 0.1, 10, 0.1, 0.5, syncRebirth),
					}}},
				},
				{
					Name = "Auto Move Level",
					Enabled = false,
					Callback = function(v) Context.AutoMoveLevel = v; syncMoveLevel() end,
					Sections = {{ Name = "🆔 Move Level", Controls = {
						makeSlider("Amount (positive drops!)", "MoveLevelAmount", -1000, 1000, 1, 1, syncMoveLevel),
						makeSlider("Interval", "MoveLevelInterval", 0.1, 10, 0.1, 0.5, syncMoveLevel),
					}}},
				},
			},
		},
		{
			Name = "💰 Money & Items",
			Modules = {
				{
					Name = "Auto Add Spin",
					Enabled = false,
					Callback = function(v) Context.AutoSpin = v; syncSpin() end,
					Sections = {{ Name = "🌀 Spin", Controls = {
						makeSlider("Spin Interval", "SpinInterval", 0.00001, 1, 0.00001, 0.00001, syncSpin),
					}}},
				},
				{
					Name = "Auto Spin Wheel",
					Enabled = false,
					Callback = function(v) Context.AutoWheel = v; syncWheel() end,
					Sections = {{ Name = "🎁 Wheel", Controls = {
						makeSlider("Reward (1=x2Win 2=10W 3=x2HP 4=10kW 5=Armor 6=SecPet)", "WheelReward", 1, 6, 1, 6, syncWheel),
						makeSlider("Wheel Interval", "WheelInterval", 0.1, 10, 0.1, 0.5, syncWheel),
					}}},
				},
				{
					Name = "Auto Add Wins",
					Enabled = false,
					Callback = function(v) Context.AutoAddWins = v; syncAddWins() end,
					Sections = {{ Name = "💵 Eco Wins", Controls = {
						makeSlider("Wins Exponent (10^X)", "AddWinsExponent", 1, 15, 1, 9, syncAddWins),
						makeSlider("Interval", "AddWinsInterval", 0.1, 10, 0.1, 0.5, syncAddWins),
					}}},
				},
				{
					Name = "Auto Daily Claims",
					Enabled = false,
					Callback = function(v)
						Context.AutoClaimDaily = v; Context.AutoClaimGroup = v
						Context.AutoClaimFriend = v; Context.AutoTipStartPack = v; Context.AutoDailyLogin = v
						syncDailyClaims()
					end,
					Sections = {{ Name = "📅 Claims", Controls = {
						makeToggle("Claim Daily", "AutoClaimDaily", syncDailyClaims),
						makeToggle("Claim Group", "AutoClaimGroup", syncDailyClaims),
						makeToggle("Claim Friend", "AutoClaimFriend", syncDailyClaims),
						makeToggle("Tip Start Pack", "AutoTipStartPack", syncDailyClaims),
						makeToggle("Daily Login", "AutoDailyLogin", syncDailyClaims),
						makeSlider("Claims Interval", "ClaimsInterval", 1, 60, 1, 5, syncDailyClaims),
					}}},
				},
				{
					Name = "Auto Reward Loop",
					Enabled = false,
					Callback = function(v) Context.AutoTryGetReward = v; Context.AutoTryGetDaily = v; syncRewardsLoop() end,
					Sections = {{ Name = "🏆 Rewards", Controls = {
						makeToggle("Try Get Reward", "AutoTryGetReward", syncRewardsLoop),
						makeToggle("Try Get Daily Reward", "AutoTryGetDaily", syncRewardsLoop),
						makeSlider("Rewards Interval", "RewardsInterval", 0.1, 10, 0.1, 1, syncRewardsLoop),
					}}},
				},
			},
		},
		{
			Name = "🐾 Pets & Stats",
			Modules = {
				{
					Name = "Auto Pet Operations",
					Enabled = false,
					Callback = function(v)
						Context.AutoPetPack1 = v; Context.AutoPetPack2 = v; Context.AutoIndexReward = v
						Context.AutoCraftAll = v; Context.AutoEquipBest = v
						Context.AutoFruit = v; Context.AutoToy = v
						syncPets()
					end,
					Sections = {{ Name = "🐾 Pets", Controls = {
						makeToggle("Pet Pack 1", "AutoPetPack1", syncPets),
						makeToggle("Pet Pack 2", "AutoPetPack2", syncPets),
						makeToggle("Index Reward (1..30)", "AutoIndexReward", syncPets),
						makeToggle("Craft All", "AutoCraftAll", syncPets),
						makeToggle("Equip Best", "AutoEquipBest", syncPets),
						makeToggle("Try Fruit", "AutoFruit", syncPets),
						makeToggle("Try Toy", "AutoToy", syncPets),
						makeSlider("Pets Interval", "PetsInterval", 0.1, 10, 0.1, 1, syncPets),
					}}},
				},
				{
					Name = "Auto Touch Board",
					Enabled = false,
					Callback = function(v) Context.AutoTouchBoard = v; syncBoard() end,
					Sections = {{ Name = "🏂 SnowBoard", Controls = {
						makeSlider("Touch Interval", "TouchBoardInterval", 0.05, 5, 0.05, 0.1, syncBoard),
					}}},
				},
			},
		},
		{
			Name = "🌍 World",
			Modules = {
				{
					Name = "Auto World Wins",
					Enabled = false,
					Callback = function(v)
						Context.AutoRewardWins = v; Context.AutoPremiumWins = v
						Context.AutoFunnel = v; Context.AutoDoneGen = v
						syncWorldWins()
					end,
					Sections = {{ Name = "🏆 World Gen Wins", Controls = {
						makeToggle("Reward Wins", "AutoRewardWins", syncWorldWins),
						makeToggle("Reward Premium Wins", "AutoPremiumWins", syncWorldWins),
						makeToggle("Funnel 25th Step", "AutoFunnel", syncWorldWins),
						makeToggle("Done Generating", "AutoDoneGen", syncWorldWins),
						makeSlider("Wins Exponent (10^X)", "WorldWinsExponent", 1, 15, 1, 9, syncWorldWins),
						makeSlider("World Wins Interval", "WorldWinsInterval", 0.1, 10, 0.1, 0.5, syncWorldWins),
					}}},
				},
				{
					Name = "Teleport To World 2",
					Enabled = false,
					Callback = function(v)
						if v then
							local w2 = ReplicatedStorage:FindFirstChild("World 2")
							if w2 then local r = w2:FindFirstChild("Teleport To World 2"); if r then fireSafe(r) end end
						end
					end,
					Sections = {{ Name = "🚀 Teleport", Controls = { lbl("Info", "Toggle on to teleport to World 2") }}},
				},
			},
		},
		{
			Name = "🏃 Player",
			Modules = {
				{
					Name = "Movement Mods",
					Enabled = false,
					Callback = function(v) end,
					Sections = {
						{ Name = "🛩️ Fly", Controls = {
							makeToggle("Fly", "FlyEnabled", function() setFly(Context.FlyEnabled) end),
							makeSlider("Fly Speed", "FlySpeed", 10, 500, 5, 60),
						}},
						{ Name = "🏃 Speed & Jump", Controls = {
							makeSlider("Walk Speed", "WalkSpeed", 16, 500, 1, 16, applyWalkSpeed),
							makeSlider("Jump Power", "JumpPower", 50, 500, 5, 50, applyJumpPower),
						}},
						{ Name = "🌊 Other", Controls = {
							makeToggle("Swim In Air", "SwimEnabled", function() setSwim(Context.SwimEnabled) end),
							makeToggle("Noclip", "NoclipEnabled", function() setNoclip(Context.NoclipEnabled) end),
						}},
					},
				},
				{
					Name = "Visuals",
					Enabled = false,
					Callback = function(v) end,
					Sections = {
						{ Name = "👁️ ESP", Controls = {
							makeToggle("ESP Players", "EspEnabled", function() setEsp(Context.EspEnabled) end),
							{ Type = "colorpicker", Name = "ESP Color", Value = "#00ff00ff", Callback = function(hex)
								if type(hex) == "string" then
									local r = tonumber(hex:sub(2,3), 16) or 0
									local g = tonumber(hex:sub(4,5), 16) or 255
									local b = tonumber(hex:sub(6,7), 16) or 0
									Context.EspColor = Color3.fromRGB(r, g, b)
									if Context.EspEnabled then refreshEsp() end
								end
							end },
						}},
						{ Name = "💡 Lighting", Controls = {
							makeToggle("FullBright", "FullBright", function() setFullBright(Context.FullBright) end),
							makeToggle("No Fog", "NoFog", function() setNoFog(Context.NoFog) end),
						}},
					},
				},
				{
					Name = "Teleport",
					Enabled = false,
					Callback = function(v) end,
					Sections = {
						{ Name = "🎯 TP", Controls = {
							makeToggle("Auto TP To Nearest Player", "AutoTpNearest", syncTpNearest),
							makeSlider("TP Nearest Interval", "TpNearestInterval", 0.1, 10, 0.1, 0.5, syncTpNearest),
							makeToggle("TP Click Bind (X key)", "TpClickEnabled", function() setTpClick(Context.TpClickEnabled) end),
						}},
					},
				},
				{
					Name = "Anti AFK",
					Enabled = true,
					Callback = function(v) end,
					Sections = {{ Name = "💤 Anti AFK", Controls = { lbl("Anti AFK is always active") }}},
				},
			},
		},
		{
			Name = "🛡️ Anti-Damage",
			Modules = {
				{
					Name = "Block TakeDamage",
					Enabled = false,
					Callback = function(v) setAntiDamage(v) end,
					Sections = {{ Name = "🛡️ Anti-Damage Hook", Controls = {
						lbl("Info", "Hooks Remotes.TakeDamage:FireServer to no-op"),
					}}},
				},
			},
		},
	},
})

Context.Controller = controller

----------------------------------------------------------------
-- Re-apply on respawn
----------------------------------------------------------------

addConn(LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	applyWalkSpeed(); applyJumpPower()
	if Context.FlyEnabled then startFly() end
	if Context.EspEnabled then refreshEsp() end
end))

addConn(Players.PlayerAdded:Connect(function(p)
	if Context.EspEnabled then
		p.CharacterAdded:Connect(function() task.wait(0.5); applyEspToPlayer(p) end)
	end
end))

addConn(Players.PlayerRemoving:Connect(function(p)
	local hl = Context.EspHighlights[p]
	if hl then pcall(function() hl:Destroy() end); Context.EspHighlights[p] = nil end
end))

addConn(LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
end))

----------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------

local function cleanup()
	Context.Alive = false
	Context.AutoClick = false; Context.AutoDamage = false; Context.AutoHeal = false
	Context.AutoTredmill = false; Context.AutoRebirth = false; Context.AutoMoveLevel = false
	Context.AutoSpin = false; Context.AutoWheel = false; Context.AutoAddWins = false
	Context.AutoClaimDaily = false; Context.AutoClaimGroup = false; Context.AutoClaimFriend = false
	Context.AutoTipStartPack = false; Context.AutoDailyLogin = false
	Context.AutoTryGetReward = false; Context.AutoTryGetDaily = false
	Context.AutoPetPack1 = false; Context.AutoPetPack2 = false; Context.AutoIndexReward = false
	Context.AutoCraftAll = false; Context.AutoEquipBest = false; Context.AutoFruit = false; Context.AutoToy = false
	Context.AutoTouchBoard = false
	Context.AutoRewardWins = false; Context.AutoPremiumWins = false
	Context.AutoFunnel = false; Context.AutoDoneGen = false
	Context.FlyEnabled = false; Context.SwimEnabled = false; Context.NoclipEnabled = false
	Context.EspEnabled = false; Context.AutoTpNearest = false; Context.TpClickEnabled = false
	Context.AntiDamage = false; Context.FullBright = false; Context.NoFog = false

	stopFly(); clearEsp(); restoreLighting()
	if Context.NoclipConn then pcall(function() Context.NoclipConn:Disconnect() end); Context.NoclipConn = nil end
	if Context.TpClickConn then pcall(function() Context.TpClickConn:Disconnect() end); Context.TpClickConn = nil end

	local r = getRemoteByName("TakeDamage")
	if r and Context.OriginalTakeDamageFire then
		r.FireServer = Context.OriginalTakeDamageFire; Context.OriginalTakeDamageFire = nil
	end

	disconnectAll()

	if Context.Controller and Context.Controller.Destroy then
		pcall(function() Context.Controller:Destroy() end)
	end
	Context.Controller = nil

	SharedEnvironment.SigmatikHealthClickContext = nil
end

Context.Cleanup = cleanup
