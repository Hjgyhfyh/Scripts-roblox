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
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local SharedEnvironment = (getgenv and getgenv()) or _G
local PreviousContext = SharedEnvironment.SigmatikDontHackMeContext

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
-- Remote discovery
----------------------------------------------------------------

local Events = ReplicatedStorage:WaitForChild("Shared", 10):WaitForChild("Events", 10)
local SubmitCode      = Events:WaitForChild("SubmitCode", 10)
local StartInput      = Events:WaitForChild("StartInput", 10)
local UpdateGameState = Events:WaitForChild("UpdateGameState", 10)
local SetPrompt       = Events:WaitForChild("SetPrompt", 10)
local RequestHint     = Events:FindFirstChild("RequestHint")
local RequestReveal   = Events:FindFirstChild("RequestReveal")
local ClaimQuest      = Events:FindFirstChild("ClaimQuest")
local ClaimGroupReward= Events:FindFirstChild("ClaimGroupReward")
local PromptRsvp      = Events:FindFirstChild("PromptRsvp")

----------------------------------------------------------------
-- Context
----------------------------------------------------------------

local Context = {
	Alive = true,
	Connections = {},
	Controller = nil,

	-- Hack
	AutoSolve = false,
	AutoSolveDelay = 0.4,
	AutoSetPin = false,
	PinDigit1 = 1, PinDigit2 = 2, PinDigit3 = 3, PinDigit4 = 4,
	AutoSubmitManual = false,
	ShowOpponentInfo = false,

	-- Defense / spam
	AutoRequestHint = false,
	AutoRequestReveal = false,
	HintInterval = 1.0,

	-- Eco
	AutoClaimQuest = false,
	AutoClaimGroup = false,
	AutoAcceptRsvp = false,
	EcoInterval = 5,

	-- Player
	FlyEnabled = false, FlySpeed = 80, WalkSpeed = 16, JumpPower = 50,
	SwimEnabled = false, NoclipEnabled = false,

	-- Visuals
	EspEnabled = false, EspColor = Color3.fromRGB(0, 255, 255),
	FullBright = false, NoFog = false,

	-- TP
	AutoTpNearest = false, TpNearestInterval = 0.5,
	TpClickEnabled = false,

	-- Anti AFK is always active
	AntiAfkActive = true,

	-- Solver state from incoming events
	Solver = {
		side = nil, gameModel = nil, defenderName = nil,
		correctDigits = {}, knownDigits = {false,false,false,false},
		lockedNumbers = {{},{},{},{}},
		bannedAtPos = {{},{},{},{}}, -- our own deductions
		triedGuesses = {},
		lastGuess = nil,
		inGuessPhase = false, inCreatePhase = false,
		ownFinalCode = nil,
	},

	-- Runtime caches
	EspHighlights = {}, NoclipConn = nil,
	FlyBV = nil, FlyBG = nil, FlyConn = nil,
	LightingBackup = nil, TpClickConn = nil,
	AntiAfkConn = nil,
	Loops = {},
}
SharedEnvironment.SigmatikDontHackMeContext = Context

local function nextLoopId(name)
	Context.Loops[name] = (Context.Loops[name] or 0) + 1
	return Context.Loops[name]
end

local function addConn(c) if c then Context.Connections[#Context.Connections+1] = c end end
local function disconnectAll()
	for _, c in ipairs(Context.Connections) do pcall(function() c:Disconnect() end) end
	table.clear(Context.Connections)
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------

local function notify(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = tostring(title), Text = tostring(text), Duration = 3 })
	end)
end

local function waitInterval(n)
	if n and n >= 0.01 then task.wait(n) else RunService.Heartbeat:Wait() end
end

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
		nextLoopId(name)
	end
end

local function setControl(tab, mod, sec, ctrl, val)
	if not Context.Controller then return end
	pcall(function() Context.Controller:SetControlValue(tab, mod, sec, ctrl, val) end)
end

----------------------------------------------------------------
-- Game logic — submit / solve
----------------------------------------------------------------

local function buildPinFromManual()
	return {
		[1] = math.floor(Context.PinDigit1 + 0.5) % 10,
		[2] = math.floor(Context.PinDigit2 + 0.5) % 10,
		[3] = math.floor(Context.PinDigit3 + 0.5) % 10,
		[4] = math.floor(Context.PinDigit4 + 0.5) % 10,
	}
end

local function fireSubmit(pin)
	pcall(function() SubmitCode:FireServer(pin) end)
end

local function pinKey(pin)
	return tostring(pin[1])..tostring(pin[2])..tostring(pin[3])..tostring(pin[4])
end

local function buildSolverGuess()
	local s = Context.Solver
	-- merge locked + our own banned
	local bannedSet = {{},{},{},{}}
	for i = 1, 4 do
		for _, d in ipairs(s.lockedNumbers[i] or {}) do bannedSet[i][d] = true end
		for _, d in ipairs(s.bannedAtPos[i] or {}) do bannedSet[i][d] = true end
	end
	-- placed positions and digits already used
	local guess = {}
	local placedDigit = {}
	for i = 1, 4 do
		if s.knownDigits[i] and s.knownDigits[i] ~= false then
			guess[i] = s.knownDigits[i]
			placedDigit[s.knownDigits[i]] = (placedDigit[s.knownDigits[i]] or 0) + 1
		end
	end
	-- collect floating correct digits (known to exist in PIN but position unknown)
	local floatDigits = {}
	for _, d in ipairs(s.correctDigits or {}) do
		floatDigits[d] = (floatDigits[d] or 0) + 1
	end
	-- subtract already placed
	for d, cnt in pairs(placedDigit) do
		floatDigits[d] = (floatDigits[d] or 0) - cnt
		if floatDigits[d] <= 0 then floatDigits[d] = nil end
	end

	-- fill empty positions: prefer placing floating digits
	local function pickFloating(pos)
		for d, cnt in pairs(floatDigits) do
			if not bannedSet[pos][d] then
				floatDigits[d] = cnt - 1
				if floatDigits[d] <= 0 then floatDigits[d] = nil end
				return d
			end
		end
		return nil
	end

	local function pickAny(pos)
		-- random unused digit not banned at this pos
		local pool = {}
		for d = 0, 9 do
			if not bannedSet[pos][d] then table.insert(pool, d) end
		end
		if #pool == 0 then
			for d = 0, 9 do table.insert(pool, d) end
		end
		return pool[math.random(1, #pool)]
	end

	for i = 1, 4 do
		if not guess[i] then
			local d = pickFloating(i) or pickAny(i)
			guess[i] = d
		end
	end
	return guess
end

local function trySubmitSolverGuess()
	local pin = buildSolverGuess()
	-- avoid resubmitting an already tried guess
	for _ = 1, 10 do
		local key = pinKey(pin)
		if not Context.Solver.triedGuesses[key] then break end
		pin = buildSolverGuess()
	end
	Context.Solver.triedGuesses[pinKey(pin)] = true
	Context.Solver.lastGuess = pin
	fireSubmit(pin)
end

----------------------------------------------------------------
-- Hook incoming events to update solver state
----------------------------------------------------------------

addConn(StartInput.OnClientEvent:Connect(function(action, payload)
	if action == "Create" then
		Context.Solver.inCreatePhase = true
		Context.Solver.inGuessPhase = false
		-- reset solver per match
		Context.Solver.correctDigits = {}
		Context.Solver.knownDigits = {false,false,false,false}
		Context.Solver.lockedNumbers = {{},{},{},{}}
		Context.Solver.bannedAtPos = {{},{},{},{}}
		Context.Solver.triedGuesses = {}
		Context.Solver.ownFinalCode = nil
		if payload then
			Context.Solver.side = payload.side
			Context.Solver.gameModel = payload.gameModel
		end
		if Context.AutoSetPin then
			task.delay(0.3, function()
				if Context.AutoSetPin and Context.Solver.inCreatePhase then
					fireSubmit(buildPinFromManual())
				end
			end)
		end
	elseif action == "ShowFinalCode" then
		Context.Solver.inCreatePhase = false
		if payload and type(payload.code) == "table" then
			Context.Solver.ownFinalCode = payload.code
		end
	elseif action == "Hide" then
		Context.Solver.inGuessPhase = false
	elseif action == "Guess" then
		Context.Solver.inGuessPhase = true
		Context.Solver.inCreatePhase = false
		if type(payload) == "table" then
			Context.Solver.side = payload.side or Context.Solver.side
			Context.Solver.gameModel = payload.gameModel or Context.Solver.gameModel
			Context.Solver.defenderName = payload.defenderName
			if type(payload.correctDigits) == "table" then
				Context.Solver.correctDigits = payload.correctDigits
			end
			if type(payload.knownDigits) == "table" then
				Context.Solver.knownDigits = payload.knownDigits
			end
			if type(payload.lockedNumbers) == "table" then
				Context.Solver.lockedNumbers = payload.lockedNumbers
			end
		end
		if Context.AutoSolve then
			task.delay(Context.AutoSolveDelay, function()
				if Context.AutoSolve and Context.Solver.inGuessPhase then
					trySubmitSolverGuess()
				end
			end)
		end
	elseif action == "Result" then
		if type(payload) == "table" and type(payload.guess) == "table" then
			-- learn from result: positions NOT in correctPositions are wrong here
			local correct = {}
			for _, p in ipairs(payload.correctPositions or {}) do correct[p] = true end
			for i = 1, 4 do
				local d = payload.guess[i]
				if d ~= nil and not correct[i] then
					-- digit d is NOT at position i
					table.insert(Context.Solver.bannedAtPos[i], d)
				end
			end
		end
	end
end))

addConn(UpdateGameState.OnClientEvent:Connect(function(state)
	if state == "End" then
		Context.Solver.inCreatePhase = false
		Context.Solver.inGuessPhase = false
		Context.Solver.triedGuesses = {}
	end
end))

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
			for _, p in ipairs(c:GetDescendants()) do
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

local function refreshEsp() for _, p in ipairs(Players:GetPlayers()) do applyEspToPlayer(p) end end

local function setEsp(v)
	Context.EspEnabled = not not v
	if Context.EspEnabled then
		refreshEsp()
		task.spawn(function() while Context.EspEnabled and Context.Alive do refreshEsp(); task.wait(2) end end)
	else
		clearEsp()
	end
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
	for k, v in pairs(Context.LightingBackup) do pcall(function() Lighting[k] = v end) end
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
	if Context.NoFog then
		Lighting.FogEnd = 1e9; Lighting.FogStart = 1e9
	else
		Lighting.FogEnd = Context.LightingBackup.FogEnd
		Lighting.FogStart = Context.LightingBackup.FogStart
	end
end

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

local function tpToNearest()
	local mroot = getRoot(); if not mroot then return end
	local nearest, dist = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
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

local function syncTpNearest() syncLoop("tpNear", "AutoTpNearest", "TpNearestInterval", tpToNearest) end

----------------------------------------------------------------
-- Anti AFK (always on)
----------------------------------------------------------------

local function startAntiAfk()
	if Context.AntiAfkConn then return end
	Context.AntiAfkConn = LocalPlayer.Idled:Connect(function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end)
end

----------------------------------------------------------------
-- Eco / Hint / Reveal loops
----------------------------------------------------------------

local function syncHintReveal()
	syncLoop("autoHint", "AutoRequestHint", "HintInterval", function()
		if RequestHint then pcall(function() RequestHint:FireServer() end) end
	end)
	syncLoop("autoReveal", "AutoRequestReveal", "HintInterval", function()
		if RequestReveal then pcall(function() RequestReveal:FireServer() end) end
	end)
end

local function syncEco()
	syncLoop("ecoQuest", "AutoClaimQuest", "EcoInterval", function()
		if ClaimQuest then
			for _, q in ipairs({"PlayGames","PlayWithFriend","Wins","Streak"}) do
				pcall(function() ClaimQuest:FireServer(q) end)
			end
			pcall(function() ClaimQuest:FireServer() end)
		end
	end)
	syncLoop("ecoGroup", "AutoClaimGroup", "EcoInterval", function()
		if ClaimGroupReward then pcall(function() ClaimGroupReward:FireServer() end) end
	end)
	syncLoop("ecoRsvp", "AutoAcceptRsvp", "EcoInterval", function()
		if PromptRsvp then pcall(function() PromptRsvp:FireServer(true) end) end
	end)
end

----------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------

local function makeToggle(name, key, sync)
	return { Type = "toggle", Name = name, Value = false, Callback = function(v)
		Context[key] = v; if sync then sync() end
	end }
end

local function makeSlider(name, key, mn, mx, inc, def, sync)
	return { Type = "slider", Name = name, Min = mn, Max = mx, Increment = inc, Value = def, Callback = function(v)
		Context[key] = v; if sync then sync() end
	end }
end

local function lbl(name, content) return { Type = "label", Name = name, Content = content or name } end
local function para(name, content) return { Type = "paragraph", Name = name, Content = content or name } end

-- One-shot toggle that auto-resets
local function oneShot(tab, mod, sec, name, action)
	return { Type = "toggle", Name = name, Value = false, Callback = function(v)
		if not v then return end
		pcall(action)
		task.delay(0.05, function() setControl(tab, mod, sec, name, false) end)
	end }
end

----------------------------------------------------------------
-- UI declarative tree
----------------------------------------------------------------

local controller = Library:Create({
	Title = "tg: @sigmatik323",
	LoadingTitle = "tg: @sigmatik323",
	LoadingSubtitle = "by sigmatik323",
	ConfigName = "Dont Hack Me",
	Accent = "#10b981",
	GuiToggleKey = Enum.KeyCode.RightShift,

	Tabs = {
		----------------------------------------------------------
		{
			Name = "🔓 Hack",
			Modules = {
				{
					Name = "Auto Solve PIN",
					Enabled = false,
					Callback = function(v) Context.AutoSolve = v end,
					Sections = {
						{ Name = "🧠 Solver", Controls = {
							para("Info", "Server leaks correctDigits/knownDigits/lockedNumbers in StartInput Guess. Bot reads them, places known digits in correct positions, fills floating correct digits in non-banned positions, and submits."),
							makeToggle("Auto Submit On Each Turn", "AutoSolve"),
							makeSlider("Submit Delay (s)", "AutoSolveDelay", 0.05, 3, 0.05, 0.4),
						}},
						{ Name = "📊 Live State", Controls = {
							lbl("Defender", "Defender: -"),
							lbl("Known Digits", "Pos: ? ? ? ?"),
							lbl("Correct Digits Pool", "Pool: -"),
							lbl("Last Guess", "Last: ----"),
						}},
					},
				},
				{
					Name = "Auto Set My PIN",
					Enabled = false,
					Callback = function(v) Context.AutoSetPin = v end,
					Sections = {
						{ Name = "🔢 Custom PIN", Controls = {
							para("Info", "When server sends StartInput Create, the bot fires SubmitCode with the chosen 4 digits below."),
							makeToggle("Auto Set On Create Phase", "AutoSetPin"),
							makeSlider("Digit 1", "PinDigit1", 0, 9, 1, 1),
							makeSlider("Digit 2", "PinDigit2", 0, 9, 1, 2),
							makeSlider("Digit 3", "PinDigit3", 0, 9, 1, 3),
							makeSlider("Digit 4", "PinDigit4", 0, 9, 1, 4),
						}},
					},
				},
				{
					Name = "Manual Submit",
					Enabled = false,
					Callback = function(v) end,
					Sections = {
						{ Name = "✋ Manual", Controls = {
							para("Info", "Fires SubmitCode with the 4 digits from Auto Set PIN sliders. Works for both Create and Guess phases (server uses current state)."),
							oneShot("🔓 Hack", "Manual Submit", "✋ Manual", "Submit Now", function()
								fireSubmit(buildPinFromManual())
								notify("Submit", "Sent " .. pinKey(buildPinFromManual()))
							end),
							oneShot("🔓 Hack", "Manual Submit", "✋ Manual", "Solve & Submit Once", function()
								trySubmitSolverGuess()
								local p = Context.Solver.lastGuess or {0,0,0,0}
								notify("Solver", "Sent " .. pinKey(p))
							end),
							oneShot("🔓 Hack", "Manual Submit", "✋ Manual", "Print Solver State", function()
								local s = Context.Solver
								print("=== Solver State ===")
								print("Defender:", s.defenderName, "Side:", s.side)
								print("knownDigits:", s.knownDigits[1], s.knownDigits[2], s.knownDigits[3], s.knownDigits[4])
								print("correctDigits:", table.concat(s.correctDigits or {}, ","))
								for i = 1, 4 do
									print("locked["..i.."]:", table.concat(s.lockedNumbers[i] or {}, ","))
									print("banned["..i.."]:", table.concat(s.bannedAtPos[i] or {}, ","))
								end
								print("lastGuess:", s.lastGuess and pinKey(s.lastGuess) or "-")
								print("ownFinalCode:", s.ownFinalCode and pinKey(s.ownFinalCode) or "-")
							end),
							oneShot("🔓 Hack", "Manual Submit", "✋ Manual", "Reset Tried Guesses", function()
								Context.Solver.triedGuesses = {}
								notify("Solver", "Tried set cleared")
							end),
						}},
					},
				},
			},
		},
		----------------------------------------------------------
		{
			Name = "🛡️ Defense",
			Modules = {
				{
					Name = "Spam Hint / Reveal",
					Enabled = false,
					Callback = function(v)
						Context.AutoRequestHint = v; Context.AutoRequestReveal = v
						syncHintReveal()
					end,
					Sections = {
						{ Name = "💡 Hint Loop", Controls = {
							para("Info", "Spams RequestHint and RequestReveal — server may award hints or reveal opponent digits free if rate-limit is missing."),
							makeToggle("Auto Request Hint", "AutoRequestHint", syncHintReveal),
							makeToggle("Auto Request Reveal", "AutoRequestReveal", syncHintReveal),
							makeSlider("Hint Interval (s)", "HintInterval", 0.1, 10, 0.1, 1.0, syncHintReveal),
						}},
					},
				},
			},
		},
		----------------------------------------------------------
		{
			Name = "💰 Eco",
			Modules = {
				{
					Name = "Auto Claim Quest",
					Enabled = false,
					Callback = function(v) Context.AutoClaimQuest = v; syncEco() end,
					Sections = {
						{ Name = "📜 Quest", Controls = {
							makeToggle("Claim Quest Loop", "AutoClaimQuest", syncEco),
							makeSlider("Eco Interval (s)", "EcoInterval", 1, 60, 1, 5, syncEco),
						}},
					},
				},
				{
					Name = "Auto Claim Group Reward",
					Enabled = false,
					Callback = function(v) Context.AutoClaimGroup = v; syncEco() end,
					Sections = {
						{ Name = "👥 Group", Controls = {
							makeToggle("Claim Group Reward Loop", "AutoClaimGroup", syncEco),
						}},
					},
				},
				{
					Name = "Auto Accept RSVP",
					Enabled = false,
					Callback = function(v) Context.AutoAcceptRsvp = v; syncEco() end,
					Sections = {
						{ Name = "🤝 RSVP", Controls = {
							para("Info", "Replies true to PromptRsvp events (joining a friend's match)."),
							makeToggle("Auto Accept Rsvp", "AutoAcceptRsvp", syncEco),
						}},
					},
				},
			},
		},
		----------------------------------------------------------
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
							makeSlider("Fly Speed", "FlySpeed", 10, 500, 5, 80),
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
							{ Type = "colorpicker", Name = "ESP Color", Value = "#00ffffff", Callback = function(hex)
								if type(hex) == "string" then
									local r = tonumber(hex:sub(2,3), 16) or 0
									local g = tonumber(hex:sub(4,5), 16) or 255
									local b = tonumber(hex:sub(6,7), 16) or 255
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
					Sections = {
						{ Name = "💤 Anti AFK", Controls = {
							lbl("Anti AFK is always active"),
						}},
					},
				},
			},
		},
	},
})

Context.Controller = controller

----------------------------------------------------------------
-- Live state label updater
----------------------------------------------------------------

task.spawn(function()
	while Context.Alive do
		if Context.Controller then
			local s = Context.Solver
			local k = function(x) return (x == false or x == nil) and "?" or tostring(x) end
			pcall(function()
				Context.Controller:SetControlValue("🔓 Hack", "Auto Solve PIN", "📊 Live State", "Defender", "Defender: " .. (s.defenderName or "-"))
				Context.Controller:SetControlValue("🔓 Hack", "Auto Solve PIN", "📊 Live State", "Known Digits",
					("Pos: %s %s %s %s"):format(k(s.knownDigits[1]), k(s.knownDigits[2]), k(s.knownDigits[3]), k(s.knownDigits[4])))
				Context.Controller:SetControlValue("🔓 Hack", "Auto Solve PIN", "📊 Live State", "Correct Digits Pool",
					"Pool: " .. (s.correctDigits and #s.correctDigits > 0 and table.concat(s.correctDigits, ",") or "-"))
				Context.Controller:SetControlValue("🔓 Hack", "Auto Solve PIN", "📊 Live State", "Last Guess",
					"Last: " .. (s.lastGuess and pinKey(s.lastGuess) or "----"))
			end)
		end
		task.wait(0.5)
	end
end)

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

startAntiAfk()

----------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------

Context.Cleanup = function()
	Context.Alive = false
	disconnectAll()
	stopFly(); clearEsp(); restoreLighting()
	if Context.NoclipConn then pcall(function() Context.NoclipConn:Disconnect() end) end
	if Context.TpClickConn then pcall(function() Context.TpClickConn:Disconnect() end) end
	if Context.AntiAfkConn then pcall(function() Context.AntiAfkConn:Disconnect() end) end
	if Context.Controller and Context.Controller.Destroy then
		pcall(function() Context.Controller:Destroy() end)
	end
	SharedEnvironment.SigmatikDontHackMeContext = nil
end

notify("Dont Hack Me", "Loaded. RightShift toggles UI.")
