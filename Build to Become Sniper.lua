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
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local SharedEnv = (getgenv and getgenv()) or _G or getfenv(0) or {}

if SharedEnv.SigmatikSniperCtx and SharedEnv.SigmatikSniperCtx.Cleanup then
	pcall(SharedEnv.SigmatikSniperCtx.Cleanup)
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
	-- Combat
	FastFire = false, FireRate = 0.05, FireWhileEquippedOnly = true,
	SilentAim = false, AimRange = 1500, AimPart = "Head",
	-- ESP
	PlayerEsp = false, PlayerEspColor = "#ff4444ff", EspShowDistance = true,
	BulletTracers = false, TracerColor = "#ffaa00ff", TracerLifetime = 1.5,
	SniperTowerEsp = false, SniperTowerColor = "#22c55eff",
	-- Economy
	AutoRebirth = false, RebirthDelay = 5,
	MoneySpoof = false, MoneySpoofValue = "999999999",
	-- Movement
	WalkSpeed = 16, JumpPower = 50, InfiniteJump = false,
	Fly = false, FlySpeed = 60, SwimAir = false, Noclip = false,
	-- Teleport
	SelectedTpTarget = nil, TpClickKey = Enum.KeyCode.Unknown,
	-- Visuals
	FullBright = false, NoFog = false,
	-- Misc
	AntiAfk = false,
	-- Internal
	Connections = {},
	EspGuis = {},
	Tracers = {},
	BulletConn = nil,
	FireLoop = nil,
	NoclipConn = nil,
	FlyConn = nil,
	InfJumpConn = nil,
	AntiAfkConn = nil,
	EquippedTool = nil,
	OriginalFog = { Start = Lighting.FogStart, End = Lighting.FogEnd, Color = Lighting.FogColor },
	OriginalLighting = {
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		GlobalShadows = Lighting.GlobalShadows,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	},
}
SharedEnv.SigmatikSniperCtx = Ctx

----------------------------------------------------------------
-- Remote refs
----------------------------------------------------------------

local function safeGet(parent, ...)
	local cur = parent
	for _, name in ipairs({...}) do
		if not cur then return nil end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

local Funcs = ReplicatedStorage:FindFirstChild("Functions")
local Events = ReplicatedStorage:FindFirstChild("Events")

local Remotes = {
	Fire = Funcs and safeGet(Funcs, "RemoteEvents", "Fire"),
	BuyGear = Funcs and safeGet(Funcs, "RemoteFunctions", "BuyGear"),
	SniperShoot = Funcs and safeGet(Funcs, "RemoteFunctions", "SniperShoot"),
	GetSpeed = Funcs and safeGet(Funcs, "RemoteFunctions", "GetSpeed"),
	GetFreeRewardClaimed = Funcs and safeGet(Funcs, "RemoteFunctions", "GetFreeRewardClaimed"),
	Rebirth = Events and safeGet(Events, "RemoteEvents", "Rebirth"),
	ClaimFreeReward = Events and safeGet(Events, "RemoteEvents", "ClaimFreeReward"),
	ClaimLikeReward = Events and safeGet(Events, "RemoteEvents", "ClaimLikeReward"),
	RefillBullets = Events and safeGet(Events, "RemoteEvents", "RefillBullets"),
	ReplicateBullet = Events and safeGet(Events, "RemoteEvents", "ReplicateBullet"),
	UpdateMoneyGui = Events and safeGet(Events, "RemoteEvents", "UpdateMoneyGui"),
	SniperHitCharacter = Events and safeGet(Events, "RemoteEvents", "SniperHitCharacter"),
}

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function getCharacter()
	return LocalPlayer.Character
end

local function getRoot()
	local char = getCharacter()
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local char = getCharacter()
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function hexToColor3(hex)
	hex = (hex or "#ffffffff"):gsub("#", "")
	if #hex < 6 then return Color3.new(1,1,1) end
	local r = tonumber(hex:sub(1,2), 16) or 255
	local g = tonumber(hex:sub(3,4), 16) or 255
	local b = tonumber(hex:sub(5,6), 16) or 255
	return Color3.fromRGB(r, g, b)
end

local function hexAlpha(hex)
	hex = (hex or "#ffffffff"):gsub("#", "")
	if #hex < 8 then return 1 end
	local a = tonumber(hex:sub(7,8), 16) or 255
	return a / 255
end

local function trackConn(conn)
	table.insert(Ctx.Connections, conn)
	return conn
end

----------------------------------------------------------------
-- Combat: Fast Fire RPG + Silent Aim
----------------------------------------------------------------

local function nearestEnemy()
	local me = getRoot()
	if not me then return nil end
	local best, bestD = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p.Character then
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			local part = p.Character:FindFirstChild(Ctx.AimPart) or p.Character:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and part then
				local d = (part.Position - me.Position).Magnitude
				if d < Ctx.AimRange and d < bestD then
					best, bestD = part, d
				end
			end
		end
	end
	return best
end

local function fireOnce(targetPos)
	if not Remotes.Fire then return end
	local root = getRoot()
	if not root then return end
	if Ctx.FireWhileEquippedOnly then
		local char = getCharacter()
		local tool = char and char:FindFirstChildOfClass("Tool")
		if not tool then return end
	end
	local tp = targetPos
	if not tp then
		if Ctx.SilentAim then
			local part = nearestEnemy()
			tp = part and part.Position
		end
		if not tp then
			local mouse = LocalPlayer:GetMouse()
			tp = mouse.Hit and mouse.Hit.Position
		end
	end
	if not tp then return end
	local cf = CFrame.lookAt(root.Position, tp)
	pcall(function() Remotes.Fire:FireServer(cf) end)
end

local function startFastFire()
	if Ctx.FireLoop then return end
	Ctx.FireLoop = task.spawn(function()
		while Ctx.Alive and Ctx.FastFire do
			fireOnce(nil)
			task.wait(math.max(Ctx.FireRate, 0.01))
		end
		Ctx.FireLoop = nil
	end)
end

----------------------------------------------------------------
-- ESP: Players + Bullet Tracers + Sniper Tower
----------------------------------------------------------------

local function buildPlayerEspGui(player)
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SigmatikESP"
	gui.Adornee = head
	gui.Size = UDim2.new(0, 160, 0, 40)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextStrokeTransparency = 0.4
	label.TextColor3 = hexToColor3(Ctx.PlayerEspColor)
	label.Text = player.Name
	label.Parent = gui
	gui.Parent = head
	Ctx.EspGuis[player] = { Gui = gui, Label = label }
end

local function clearPlayerEsp()
	for p, data in pairs(Ctx.EspGuis) do
		if data.Gui then pcall(function() data.Gui:Destroy() end) end
		Ctx.EspGuis[p] = nil
	end
end

local function refreshPlayerEsp()
	for _, data in pairs(Ctx.EspGuis) do
		if data.Label then
			data.Label.TextColor3 = hexToColor3(Ctx.PlayerEspColor)
		end
	end
end

local function updatePlayerEsp()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local data = Ctx.EspGuis[p]
			if not data or not data.Gui or not data.Gui.Parent then
				buildPlayerEspGui(p)
				data = Ctx.EspGuis[p]
			end
			if data and data.Label then
				local label = data.Label
				local distText = ""
				if Ctx.EspShowDistance then
					local me, hp = getRoot(), p.Character and p.Character:FindFirstChild("Head")
					if me and hp then
						distText = string.format("  [%dm]", math.floor((hp.Position - me.Position).Magnitude))
					end
				end
				label.Text = p.Name .. distText
			end
		end
	end
	for p, _ in pairs(Ctx.EspGuis) do
		if not p or not p.Parent or not p.Character then
			local data = Ctx.EspGuis[p]
			if data and data.Gui then pcall(function() data.Gui:Destroy() end) end
			Ctx.EspGuis[p] = nil
		end
	end
end

local function loopPlayerEsp()
	task.spawn(function()
		while Ctx.Alive and Ctx.PlayerEsp do
			pcall(updatePlayerEsp)
			task.wait(0.5)
		end
		clearPlayerEsp()
	end)
end

local function spawnTracer(origin, dir, maxDist)
	local color = hexToColor3(Ctx.TracerColor)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	local len = math.min(maxDist or 1000, 1000)
	part.Size = Vector3.new(0.15, 0.15, len)
	local mid = origin + dir.Unit * (len / 2)
	part.CFrame = CFrame.lookAt(mid, origin + dir.Unit * len)
	part.Parent = Workspace
	table.insert(Ctx.Tracers, part)
	task.delay(Ctx.TracerLifetime, function()
		if part and part.Parent then part:Destroy() end
	end)
end

local function setBulletTracers(on)
	if Ctx.BulletConn then Ctx.BulletConn:Disconnect(); Ctx.BulletConn = nil end
	if on and Remotes.ReplicateBullet then
		Ctx.BulletConn = trackConn(Remotes.ReplicateBullet.OnClientEvent:Connect(function(origin, dir, maxDist)
			if not Ctx.BulletTracers then return end
			if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then return end
			pcall(spawnTracer, origin, dir, maxDist)
		end))
	end
end

local SniperTowerGui = nil
local function setSniperTowerEsp(on)
	if SniperTowerGui then pcall(function() SniperTowerGui:Destroy() end); SniperTowerGui = nil end
	if not on then return end
	local target
	for _, m in ipairs(Workspace:GetDescendants()) do
		if m:IsA("Model") and (m.Name:lower():find("sniper") or m.Name:lower():find("tower")) then
			target = m:FindFirstChildWhichIsA("BasePart", true) or m.PrimaryPart
			if target then break end
		end
	end
	if not target then return end
	SniperTowerGui = Instance.new("BillboardGui")
	SniperTowerGui.Adornee = target
	SniperTowerGui.Size = UDim2.new(0, 200, 0, 50)
	SniperTowerGui.AlwaysOnTop = true
	SniperTowerGui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextStrokeTransparency = 0.4
	label.TextColor3 = hexToColor3(Ctx.SniperTowerColor)
	label.Text = "🎯 Sniper Tower"
	label.Parent = SniperTowerGui
	SniperTowerGui.Parent = target
end

----------------------------------------------------------------
-- Economy
----------------------------------------------------------------

local function claimFreeReward()
	if Remotes.ClaimFreeReward then pcall(function() Remotes.ClaimFreeReward:FireServer() end) end
end

local function claimLikeReward()
	if Remotes.ClaimLikeReward then pcall(function() Remotes.ClaimLikeReward:FireServer() end) end
end

local function refillBullets()
	if Remotes.RefillBullets then pcall(function() Remotes.RefillBullets:FireServer() end) end
end

local function rebirthOnce()
	if Remotes.Rebirth then pcall(function() Remotes.Rebirth:FireServer() end) end
end

local function loopAutoRebirth()
	task.spawn(function()
		while Ctx.Alive and Ctx.AutoRebirth do
			rebirthOnce()
			task.wait(math.max(Ctx.RebirthDelay, 1))
		end
	end)
end

local function applyMoneySpoof()
	local lbl = safeGet(LocalPlayer, "PlayerGui", "MoneyGui", "Objects", "ContentFrame", "BottomFrame", "MoneyFrame", "MoneyLabel")
	if lbl and lbl:IsA("TextLabel") then
		if Ctx.MoneySpoof then
			lbl.Text = "$" .. tostring(Ctx.MoneySpoofValue or "999999999")
		end
	end
end

local function loopMoneySpoof()
	task.spawn(function()
		while Ctx.Alive and Ctx.MoneySpoof do
			pcall(applyMoneySpoof)
			task.wait(0.3)
		end
	end)
end

----------------------------------------------------------------
-- Movement: Fly, WalkSpeed, JumpPower, Infinite Jump, Noclip, Swim Air
----------------------------------------------------------------

local function applySpeed()
	local hum = getHumanoid()
	if hum then hum.WalkSpeed = Ctx.WalkSpeed end
end

local function applyJump()
	local hum = getHumanoid()
	if hum then
		hum.UseJumpPower = true
		hum.JumpPower = Ctx.JumpPower
	end
end

local function setNoclip(on)
	if Ctx.NoclipConn then Ctx.NoclipConn:Disconnect(); Ctx.NoclipConn = nil end
	if not on then return end
	Ctx.NoclipConn = trackConn(RunService.Stepped:Connect(function()
		local char = getCharacter()
		if not char then return end
		for _, v in ipairs(char:GetDescendants()) do
			if v:IsA("BasePart") and v.CanCollide then
				v.CanCollide = false
			end
		end
	end))
end

local function setInfiniteJump(on)
	if Ctx.InfJumpConn then Ctx.InfJumpConn:Disconnect(); Ctx.InfJumpConn = nil end
	if not on then return end
	Ctx.InfJumpConn = trackConn(UserInputService.JumpRequest:Connect(function()
		local hum = getHumanoid()
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end))
end

local FlyBV, FlyBG = nil, nil
local function killFly()
	if Ctx.FlyConn then Ctx.FlyConn:Disconnect(); Ctx.FlyConn = nil end
	if FlyBV then FlyBV:Destroy(); FlyBV = nil end
	if FlyBG then FlyBG:Destroy(); FlyBG = nil end
end

local function setFly(on)
	killFly()
	if not on then return end
	local root = getRoot()
	if not root then return end
	FlyBV = Instance.new("BodyVelocity")
	FlyBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	FlyBV.Velocity = Vector3.zero
	FlyBV.Parent = root
	FlyBG = Instance.new("BodyGyro")
	FlyBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	FlyBG.P = 9000
	FlyBG.D = 1000
	FlyBG.CFrame = root.CFrame
	FlyBG.Parent = root
	Ctx.FlyConn = trackConn(RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if not cam or not FlyBV or not FlyBV.Parent then return end
		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
		if dir.Magnitude > 0 then dir = dir.Unit * Ctx.FlySpeed end
		FlyBV.Velocity = dir
		FlyBG.CFrame = cam.CFrame
	end))
end

local SwimAirConn = nil
local function setSwimAir(on)
	if SwimAirConn then SwimAirConn:Disconnect(); SwimAirConn = nil end
	if not on then return end
	SwimAirConn = trackConn(RunService.Stepped:Connect(function()
		local hum = getHumanoid()
		if hum and hum:GetState() ~= Enum.HumanoidStateType.Swimming then
			hum:ChangeState(Enum.HumanoidStateType.Swimming)
		end
	end))
end

----------------------------------------------------------------
-- Teleport
----------------------------------------------------------------

local function teleportTo(pos)
	local root = getRoot()
	if root and pos then
		root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	end
end

local function tpToPlayer(name)
	if not name then return end
	local target = Players:FindFirstChild(name)
	if target and target.Character then
		local hp = target.Character:FindFirstChild("HumanoidRootPart")
		if hp then teleportTo(hp.Position) end
	end
end

local function refreshPlayerList(controller)
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then table.insert(list, p.Name) end
	end
	if #list == 0 then list = { "(no players)" } end
	pcall(function()
		controller:SetControlValue("🎯 Teleport", "Players Teleport", "Target", "Player List", list[1] or "(no players)")
	end)
end

local TpClickConn = nil
local function setTpClickBind(key)
	Ctx.TpClickKey = key
	if TpClickConn then TpClickConn:Disconnect(); TpClickConn = nil end
	if not key or key == Enum.KeyCode.Unknown then return end
	TpClickConn = trackConn(UserInputService.InputBegan:Connect(function(io, gp)
		if gp then return end
		if io.KeyCode == key then
			local mouse = LocalPlayer:GetMouse()
			if mouse.Hit then teleportTo(mouse.Hit.Position) end
		end
	end))
end

local function tpToSniperTower()
	for _, m in ipairs(Workspace:GetDescendants()) do
		if m:IsA("Model") and (m.Name:lower():find("sniper") or m.Name:lower():find("tower")) then
			local p = m:FindFirstChildWhichIsA("BasePart", true) or m.PrimaryPart
			if p then teleportTo(p.Position); return end
		end
	end
end

----------------------------------------------------------------
-- Visuals
----------------------------------------------------------------

local function setFullBright(on)
	if on then
		Lighting.Brightness = 3
		Lighting.ClockTime = 14
		Lighting.GlobalShadows = false
		Lighting.Ambient = Color3.fromRGB(170, 170, 170)
		Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
	else
		Lighting.Brightness = Ctx.OriginalLighting.Brightness
		Lighting.ClockTime = Ctx.OriginalLighting.ClockTime
		Lighting.GlobalShadows = Ctx.OriginalLighting.GlobalShadows
		Lighting.Ambient = Ctx.OriginalLighting.Ambient
		Lighting.OutdoorAmbient = Ctx.OriginalLighting.OutdoorAmbient
	end
end

local function setNoFog(on)
	if on then
		Lighting.FogStart = 1e9
		Lighting.FogEnd = 1e9
		Lighting.FogColor = Color3.new(1,1,1)
	else
		Lighting.FogStart = Ctx.OriginalFog.Start
		Lighting.FogEnd = Ctx.OriginalFog.End
		Lighting.FogColor = Ctx.OriginalFog.Color
	end
end

----------------------------------------------------------------
-- Anti AFK
----------------------------------------------------------------

local function setAntiAfk(on)
	if Ctx.AntiAfkConn then Ctx.AntiAfkConn:Disconnect(); Ctx.AntiAfkConn = nil end
	if not on then return end
	Ctx.AntiAfkConn = trackConn(LocalPlayer.Idled:Connect(function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end))
end

----------------------------------------------------------------
-- Character respawn handling
----------------------------------------------------------------

trackConn(LocalPlayer.CharacterAdded:Connect(function(char)
	task.wait(0.6)
	if Ctx.WalkSpeed ~= 16 then applySpeed() end
	if Ctx.JumpPower ~= 50 then applyJump() end
	if Ctx.Noclip then setNoclip(true) end
	if Ctx.InfiniteJump then setInfiniteJump(true) end
	if Ctx.Fly then setFly(true) end
	if Ctx.SwimAir then setSwimAir(true) end
end))

----------------------------------------------------------------
-- UI
----------------------------------------------------------------

local Controller
Controller = Library:Create({
	Name = "tg: @sigmatik323",
	LoadingTitle = "tg: @sigmatik323",
	LoadingSubtitle = "by sigmatik323",
	Title = "tg: @sigmatik323",
	ConfigName = "Build to Become Sniper",
	WindowWidth = 880,
	WindowHeight = 540,
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = "🔫 Combat",
			Modules = {
				{
					Name = "Fast Fire RPG",
					Enabled = false,
					Callback = function(on)
						Ctx.FastFire = on
						if on then startFastFire() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Fire Rate", Min = 0.02, Max = 1, Increment = 0.01, Value = 0.05, Callback = function(v) Ctx.FireRate = v end },
								{ Type = "toggle", Name = "Only When Tool Equipped", Value = true, Callback = function(v) Ctx.FireWhileEquippedOnly = v end },
								{ Type = "button", Name = "Manual Single Shot", Callback = function() fireOnce(nil) end },
							},
						},
					},
				},
				{
					Name = "Silent Aim",
					Enabled = false,
					Callback = function(on) Ctx.SilentAim = on end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Aim Range", Min = 50, Max = 5000, Increment = 50, Value = 1500, Callback = function(v) Ctx.AimRange = v end },
								{ Type = "dropdown", Name = "Aim Part", Items = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" }, Value = "Head", Callback = function(v) Ctx.AimPart = v end },
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
					Name = "Players ESP",
					Enabled = false,
					Callback = function(on)
						Ctx.PlayerEsp = on
						if on then loopPlayerEsp() else clearPlayerEsp() end
					end,
					Sections = {
						{
							Name = "Style",
							Controls = {
								{ Type = "colorpicker", Name = "ESP Color", Value = "#ff4444ff", Callback = function(hex) Ctx.PlayerEspColor = hex; refreshPlayerEsp() end },
								{ Type = "toggle", Name = "Show Distance", Value = true, Callback = function(v) Ctx.EspShowDistance = v end },
							},
						},
					},
				},
				{
					Name = "Bullet Tracers",
					Enabled = false,
					Callback = function(on)
						Ctx.BulletTracers = on
						setBulletTracers(on)
					end,
					Sections = {
						{
							Name = "Style",
							Controls = {
								{ Type = "colorpicker", Name = "Tracer Color", Value = "#ffaa00ff", Callback = function(hex) Ctx.TracerColor = hex end },
								{ Type = "slider", Name = "Tracer Lifetime", Min = 0.5, Max = 5, Increment = 0.1, Value = 1.5, Callback = function(v) Ctx.TracerLifetime = v end },
							},
						},
					},
				},
				{
					Name = "Sniper Tower ESP",
					Enabled = false,
					Callback = function(on)
						Ctx.SniperTowerEsp = on
						setSniperTowerEsp(on)
					end,
					Sections = {
						{
							Name = "Style",
							Controls = {
								{ Type = "colorpicker", Name = "Tower Color", Value = "#22c55eff", Callback = function(hex) Ctx.SniperTowerColor = hex; if Ctx.SniperTowerEsp then setSniperTowerEsp(true) end end },
							},
						},
					},
				},
			},
		},
		{
			Name = "💰 Economy",
			Modules = {
				{
					Name = "Free Rewards",
					Enabled = false,
					Callback = function() end,
					Sections = {
						{
							Name = "Actions",
							Controls = {
								{ Type = "button", Name = "Claim Free Reward", Callback = claimFreeReward },
								{ Type = "button", Name = "Claim Like Reward", Callback = claimLikeReward },
								{ Type = "button", Name = "Refill Bullets", Callback = refillBullets },
							},
						},
					},
				},
				{
					Name = "Auto Rebirth",
					Enabled = false,
					Callback = function(on)
						Ctx.AutoRebirth = on
						if on then loopAutoRebirth() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Rebirth Delay", Min = 1, Max = 60, Increment = 1, Value = 5, Callback = function(v) Ctx.RebirthDelay = v end },
								{ Type = "button", Name = "Rebirth Now", Callback = rebirthOnce },
							},
						},
					},
				},
				{
					Name = "Money Display Spoof",
					Enabled = false,
					Callback = function(on)
						Ctx.MoneySpoof = on
						if on then loopMoneySpoof() end
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "textbox", Name = "Spoof Value", Placeholder = "999999999", Callback = function(v) Ctx.MoneySpoofValue = v end },
								{ Type = "label", Name = "Spoof Note", Content = "Visual only — server balance unchanged." },
							},
						},
					},
				},
			},
		},
		{
			Name = "🚀 Movement",
			Modules = {
				{
					Name = "Walk Speed",
					Enabled = false,
					Callback = function(on)
						if on then Ctx.WalkSpeed = math.max(Ctx.WalkSpeed, 50) else Ctx.WalkSpeed = 16 end
						applySpeed()
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Walk Speed Value", Min = 16, Max = 300, Increment = 1, Value = 16, Callback = function(v) Ctx.WalkSpeed = v; applySpeed() end },
							},
						},
					},
				},
				{
					Name = "Jump Power",
					Enabled = false,
					Callback = function(on)
						if on then Ctx.JumpPower = math.max(Ctx.JumpPower, 100) else Ctx.JumpPower = 50 end
						applyJump()
					end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Jump Power Value", Min = 50, Max = 500, Increment = 5, Value = 50, Callback = function(v) Ctx.JumpPower = v; applyJump() end },
							},
						},
					},
				},
				{
					Name = "Infinite Jump",
					Enabled = false,
					Callback = function(on) Ctx.InfiniteJump = on; setInfiniteJump(on) end,
				},
				{
					Name = "Fly",
					Enabled = false,
					Callback = function(on) Ctx.Fly = on; setFly(on) end,
					Sections = {
						{
							Name = "Settings",
							Controls = {
								{ Type = "slider", Name = "Fly Speed", Min = 10, Max = 300, Increment = 5, Value = 60, Callback = function(v) Ctx.FlySpeed = v end },
							},
						},
					},
				},
				{
					Name = "Swim Air",
					Enabled = false,
					Callback = function(on) Ctx.SwimAir = on; setSwimAir(on) end,
				},
				{
					Name = "Noclip",
					Enabled = false,
					Callback = function(on) Ctx.Noclip = on; setNoclip(on) end,
				},
			},
		},
		{
			Name = "🎯 Teleport",
			Modules = {
				{
					Name = "Players Teleport",
					Enabled = true,
					Callback = function() end,
					Sections = {
						{
							Name = "Target",
							Controls = {
								{ Type = "dropdown", Name = "Player List", Items = { "(no players)" }, Value = "(no players)", Callback = function(v) Ctx.SelectedTpTarget = v end },
								{ Type = "button", Name = "Refresh Players", Callback = function() refreshPlayerList(Controller) end },
								{ Type = "button", Name = "Teleport To Player", Callback = function() tpToPlayer(Ctx.SelectedTpTarget) end },
							},
						},
					},
				},
				{
					Name = "Sniper Tower Teleport",
					Enabled = false,
					Callback = function() end,
					Sections = {
						{
							Name = "Actions",
							Controls = {
								{ Type = "button", Name = "TP To Sniper Tower", Callback = tpToSniperTower },
							},
						},
					},
				},
				{
					Name = "Click Teleport",
					Enabled = false,
					Callback = function() end,
					Sections = {
						{
							Name = "Bind",
							Controls = {
								{ Type = "keybind", Name = "TP Click Key", Value = Enum.KeyCode.Unknown, Mode = "Toggle", Callback = function(key) setTpClickBind(key) end },
								{ Type = "label", Name = "TP Click Hint", Content = "Press the bind to teleport to mouse position." },
							},
						},
					},
				},
			},
		},
		{
			Name = "🌐 Visuals",
			Modules = {
				{
					Name = "Full Bright",
					Enabled = false,
					Callback = function(on) Ctx.FullBright = on; setFullBright(on) end,
				},
				{
					Name = "No Fog",
					Enabled = false,
					Callback = function(on) Ctx.NoFog = on; setNoFog(on) end,
				},
			},
		},
		{
			Name = "⚙️ Misc",
			Modules = {
				{
					Name = "Anti AFK",
					Enabled = false,
					Callback = function(on) Ctx.AntiAfk = on; setAntiAfk(on) end,
				},
				{
					Name = "Server",
					Enabled = false,
					Callback = function() end,
					Sections = {
						{
							Name = "Actions",
							Controls = {
								{ Type = "button", Name = "Rejoin Server", Callback = function()
									pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
								end },
								{ Type = "button", Name = "Server Hop", Callback = function()
									local ok, srv = pcall(function()
										local req = (syn and syn.request) or (http and http.request) or (request) or (fluxus and fluxus.request)
										if not req then return nil end
										local res = req({ Url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId), Method = "GET" })
										if res and res.Body then
											local data = game:GetService("HttpService"):JSONDecode(res.Body)
											for _, s in ipairs(data.data or {}) do
												if s.playing and s.maxPlayers and s.playing < s.maxPlayers and s.id ~= game.JobId then
													return s.id
												end
											end
										end
									end)
									if ok and srv then
										pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, srv, LocalPlayer) end)
									end
								end },
							},
						},
					},
				},
			},
		},
	},
})

----------------------------------------------------------------
-- Auto refresh teleport list
----------------------------------------------------------------

task.spawn(function()
	while Ctx.Alive do
		pcall(function() refreshPlayerList(Controller) end)
		task.wait(8)
	end
end)

----------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------

Ctx.Cleanup = function()
	Ctx.Alive = false
	Ctx.FastFire = false; Ctx.SilentAim = false
	Ctx.PlayerEsp = false; Ctx.BulletTracers = false; Ctx.SniperTowerEsp = false
	Ctx.AutoRebirth = false; Ctx.MoneySpoof = false
	Ctx.Fly = false; Ctx.Noclip = false; Ctx.InfiniteJump = false; Ctx.SwimAir = false
	Ctx.FullBright = false; Ctx.NoFog = false; Ctx.AntiAfk = false
	clearPlayerEsp(); killFly(); setNoclip(false); setInfiniteJump(false); setSwimAir(false)
	setBulletTracers(false); setSniperTowerEsp(false); setFullBright(false); setNoFog(false); setAntiAfk(false)
	setTpClickBind(Enum.KeyCode.Unknown)
	for _, p in ipairs(Ctx.Tracers) do pcall(function() p:Destroy() end) end
	Ctx.Tracers = {}
	for _, c in ipairs(Ctx.Connections) do pcall(function() c:Disconnect() end) end
	Ctx.Connections = {}
	pcall(function() Controller:Destroy() end)
end
