-- ============================ 8 BALL POOL — SUITE ============================
-- One script, three tools for the Roblox game "8 Ball Pool" (1v1 Pool):
--
--   1) Self-calibrating Trajectory Predictor — full physics overlay (cue + object
--      guidelines, cushion bounces off the REAL segmented cushions, ball transfer
--      on the exact 90° rule, pocket capture, scratch warnings), best-shot solver,
--      auto-aim, humanized auto-fire, ball-in-hand finder, ranked shot list, and a
--      self-learning loop that tunes the model from every shot and saves to disk.
--   2) Cue Library — equip ANY cue from a searchable grid (RightShift / 🎱 button).
--   3) Smooth Opponent Cue — interpolates the opponent's cue between sparse server
--      updates and re-broadcasts ours, so both cues move at ~60 Hz.
--
-- Built-in anti-AFK. Predictor hotkeys: B=BestShot  V=AutoAim  F=AutoFire
-- G=BallInHand  [ ]=cycle shot  , .=aim-nudge  /=reset-aim  K=CalDetail  C=HUD
-- H=Legend  X=reset calibration.  Full unload: _G.__EIGHTBALL_SUITE.unload()

-- ============ cleanup any previous instance ============
if _G.__EIGHTBALL_SUITE then pcall(_G.__EIGHTBALL_SUITE.unload) end
if _G.__POOL_PREDICTOR then pcall(_G.__POOL_PREDICTOR.cleanup) end
if _G.__POOL_LOG then for _,c in ipairs(_G.__POOL_LOG.conns or {}) do pcall(function() c:Disconnect() end) end _G.__POOL_LOG=nil end
if _G.__POOL_REC then pcall(function() _G.__POOL_REC.conn:Disconnect() end) _G.__POOL_REC=nil end
pcall(game:GetService("RunService").UnbindFromRenderStep, game:GetService("RunService"), "PoolAimOverride")
do
	local pg = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
	if pg then
		for _,n in ipairs({"AutoAimIndicator","AutoAimToast","PoolCalHUD"}) do
			local g = pg:FindFirstChild(n); if g then g:Destroy() end
		end
	end
end

local rs  = game:GetService("ReplicatedStorage")
local rsv = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local http = game:GetService("HttpService")
local lp  = game.Players.LocalPlayer

local guideModInst = rs:WaitForChild("GuidelinesRunner", 10)
if not guideModInst then
	warn("[Pred v12] GuidelinesRunner not found — open this script while inside 8 Ball Pool (1v1 Pool).")
	return
end
local guideMod = require(guideModInst)

local function clamp(v,a,b) return math.max(a, math.min(b, v)) end

-- ============ exact shot capture (hook the shoot remote) ============
-- The game fires Table._GameData.Communication:FireServer(travelDir, power[1..21])
-- for every shot (confirmed in GameRunnerClient). Watching that gives the EXACT
-- power AND launch direction of the player's own shots — far more reliable than
-- scraping the power UI (which can read 1.0). Installed once and left in place so
-- re-running the script doesn't stack hooks; it only writes a tiny table.
--   _G.__POOL_COMM     = the bound Communication remote (set in bindTable)
--   _G.__POOL_SHOTCAP  = {dir=Vector3, power=number, t=os.clock()} per fire
if not _G.__POOL_SHOTHOOK_INSTALLED then
	local canHook = getrawmetatable and setreadonly and newcclosure and getnamecallmethod
	if canHook then
		_G.__POOL_SHOTHOOK_INSTALLED = pcall(function()
			local mt = getrawmetatable(game)
			local oldNamecall = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				-- pointer compare first (cheap); only then ask the method name
				if self == _G.__POOL_COMM then
					local a1, a2 = ...
					pcall(function()
						if getnamecallmethod() == "FireServer" and typeof(a1) == "Vector3" and type(a2) == "number" then
							_G.__POOL_SHOTCAP = { dir = a1, power = a2, t = os.clock() }
						end
					end)
				end
				return oldNamecall(self, ...)
			end)
			setreadonly(mt, true)
		end)
	end
end

-- ============ static config (visuals / constants known from the game) ============
local C = {
	BALL_R = 0.2, MAX_DEPTH = 14, MIN_SPEED = 0.6,
	COL_CUE = Color3.fromRGB(255,255,255), COL_CUE_DEFL = Color3.fromRGB(255,180,60),
	COL_TARGET = Color3.fromRGB(80,200,255), COL_CHAIN = Color3.fromRGB(180,120,255),
	COL_POCKET = Color3.fromRGB(0,255,90), COL_SCRATCH = Color3.fromRGB(255,50,50),
	COL_BEST = Color3.fromRGB(255,215,0),
	BEST_INTERVAL = 1.5, BEST_ANGLE_STEP = 4, BEST_POWERS = {12, 17, 21},
	SEARCH = { COMBO = false, BANK = false, KICK = false, MAX_BALLS = 6, MAX_EVALS = 1400 },  -- combos/banks/kicks: opt-in, and never on a crowded table; MAX_EVALS caps findBest cost
	BEST_HOTKEY = Enum.KeyCode.B, AUTO_AIM_HOTKEY = Enum.KeyCode.V, AUTO_FIRE_HOTKEY = Enum.KeyCode.F,
	HUD_HOTKEY = Enum.KeyCode.C, RESET_HOTKEY = Enum.KeyCode.X,
	LEGEND_HOTKEY = Enum.KeyCode.H,
	PLACE_HOTKEY = Enum.KeyCode.G, PLACE_INTERVAL = 0.75,
	CAL_MENU_HOTKEY = Enum.KeyCode.K,
	AIM_STEP = 0.25,
	CYCLE_PREV_HOTKEY  = Enum.KeyCode.LeftBracket,
	CYCLE_NEXT_HOTKEY  = Enum.KeyCode.RightBracket,
	AIM_NUDGE_L_HOTKEY = Enum.KeyCode.Comma,
	AIM_NUDGE_R_HOTKEY = Enum.KeyCode.Period,
	AIM_RESET_HOTKEY   = Enum.KeyCode.Slash,
	COL_PLACE = Color3.fromRGB(0,255,200),
	FILTER_NON_POCKETED = false,
	CUSHION_TANG_KEEP = 0.78,
	CUE_TANG_KEEP     = 0.96,
	-- Match the game's own drawn guideline EXACTLY: the struck ball leaves on the
	-- pure line of centres and the cue ball deflects on the exact 90° tangent
	-- (verified against the decompiled GuidelinesRunner). Set false to fall back to
	-- the self-learned mass-split + cut-throw model.
	GUIDELINE_EXACT = true,
	POCKET = { ENABLED = true, CONE_CORNER = math.rad(80), CONE_SIDE = math.rad(52),
	           SIDE_R_FACTOR = 0.85, SPEED_SOFT = 16, SPEED_PEN = 0.010,
	           MIN_R_FACTOR = 0.6, ANGLE_MIN_SPEED = 7 },
	HUMANIZE = { ENABLED = true, MIN_DELAY = 0.25, MAX_DELAY = 0.9, ANGLE_JITTER = 0.4, POWER_JITTER = 0.3 },
}

-- Standard 8-ball-pool colour scheme, keyed by ball name. The game uses
-- decals/textures on white spheres so BasePart.Color is unusable (defaults
-- to red for everyone). Striped balls (9-15) carry the same hue as their
-- solid partner but slightly lighter so the user can still tell them apart.
local BALL_COLORS = {
	["Cue"] = Color3.fromRGB(255,255,255),
	["1"]   = Color3.fromRGB(245,200, 35),   -- yellow solid
	["2"]   = Color3.fromRGB( 30, 75,210),   -- blue solid
	["3"]   = Color3.fromRGB(220, 35, 45),   -- red solid
	["4"]   = Color3.fromRGB(120, 45,170),   -- purple solid
	["5"]   = Color3.fromRGB(245,120, 25),   -- orange solid
	["6"]   = Color3.fromRGB( 25,130, 55),   -- green solid
	["7"]   = Color3.fromRGB(130, 55, 30),   -- maroon solid
	["8"]   = Color3.fromRGB( 30, 30, 35),   -- black
	["9"]   = Color3.fromRGB(255,225,110),   -- yellow stripe
	["10"]  = Color3.fromRGB(110,160,240),   -- blue stripe
	["11"]  = Color3.fromRGB(240,110,120),   -- red stripe
	["12"]  = Color3.fromRGB(180,120,215),   -- purple stripe
	["13"]  = Color3.fromRGB(250,170, 90),   -- orange stripe
	["14"]  = Color3.fromRGB( 90,190,120),   -- green stripe
	["15"]  = Color3.fromRGB(180,115, 80),   -- maroon stripe
}
local function ballColor(ball)
	if not ball then return C.COL_TARGET end
	return BALL_COLORS[ball.Name] or C.COL_TARGET
end

-- ============ calibration model (persisted to disk) ============
local CAL_FILE = "sigmatik_8ballpool_cal.json"

-- v0(power)   = powA*power + powB        (initial cue speed, studs/sec)
-- K(power)    = kA + kB*power            (speed lost per stud travelled)
-- pocketR     bracketed by [pocketLow, pocketHigh] from real sink/miss data
-- Physics model: constant deceleration (matches real-billiard friction):
--   v² = v0² - 2*K*d   →   v(d) = sqrt(max(0, v0² - 2Kd))
--   stop_distance = v0² / (2K)
-- K (in stud/s²) is the deceleration and is normally roughly independent of
-- power; kB stays near 0. powA*p + powB models initial cue-ball speed.
-- Schema rev forces an automatic wipe of any persisted cal that was built
-- under the OLD linear v-vs-d model (incompatible parameters).
-- Schema 3: power is now the game's true 1..21 scale (was 1..18), so any cal
-- persisted under schema 2 has the wrong powA/K and must be wiped on load.
local CAL_SCHEMA = 4
local DEFAULT_CAL = {
	schema = CAL_SCHEMA,
	powA = 2.20, powB = 0.0,
	kA   = 40.0, kB   = 0.0,
	cushionRest = 0.90,
	ballRest    = 0.92,
	throwGain = 0.04,
	pocketR     = 0.50, pocketLow = 0.20, pocketHigh = 1.10,
	-- regression accumulators: v0 vs power
	vN=0, vSx=0, vSy=0, vSxx=0, vSxy=0,
	-- regression accumulators: K vs power
	kN=0, kSx=0, kSy=0, kSxx=0, kSxy=0,
	-- K fallback (mean over every shot, power known or not)
	kfN=0, kfSum=0,
	-- cushion / ball restitution running means
	crN=0, crSum=0,
	brN=0, brSum=0,
	-- robust sample buffers (median/MAD): ball rest, cushion rest, K fallback
	brBuf = {}, crBuf = {}, kfBuf = {},
	vRatioBuf = {}, tick = 0, kBias = 0, errEMA = 0,
	-- stats
	shots=0, errN=0, errSum=0, lastErr=0,
}

local function cloneDefaultCalInto(dst)
	for k,v in pairs(DEFAULT_CAL) do
		if type(v) == "table" then
			local t = {}; for i,x in ipairs(v) do t[i]=x end; dst[k] = t
		else dst[k] = v end
	end
end

local CAL = {}
cloneDefaultCalInto(CAL)

local lastSaveT = 0
local SAVE_MIN_INTERVAL = 8
local function saveCal(force)
	if not writefile then return end
	local now = os.clock()
	if not force and (now - lastSaveT) < SAVE_MIN_INTERVAL then return end
	lastSaveT = now
	pcall(function()
		local json = http:JSONEncode(CAL)
		local tmp = CAL_FILE .. ".tmp"
		writefile(tmp, json)
		local ok = pcall(function() return http:JSONDecode(readfile(tmp)) end)
		if ok then
			if isfile and readfile and isfile(CAL_FILE) then
				pcall(function() writefile(CAL_FILE .. ".bak", readfile(CAL_FILE)) end)
			end
			writefile(CAL_FILE, json)
		end
	end)
end
local function loadCal()
	pcall(function()
		if isfile and readfile and isfile(CAL_FILE) then
			local raw = readfile(CAL_FILE)
			local okd, data = pcall(function() return http:JSONDecode(raw) end)
			if not okd and isfile(CAL_FILE..".bak") then
				okd, data = pcall(function() return http:JSONDecode(readfile(CAL_FILE..".bak")) end)
			end
			if not okd then data = nil end
			if type(data)=="table" then
				-- Reject old-schema calibrations: their K/v0 values come from
				-- the linear v-vs-d fit and are not interpretable as the new
				-- constant-deceleration model.
				if data.schema == CAL_SCHEMA then
					for k,_ in pairs(DEFAULT_CAL) do
						if type(data[k])=="number" then CAL[k]=data[k] end
					end
					for _,bk in ipairs({"brBuf","crBuf","kfBuf","vRatioBuf"}) do
						if type(data[bk]) == "table" then
							local t = {}; for _,x in ipairs(data[bk]) do if type(x)=="number" then t[#t+1]=x end end
							CAL[bk] = t
						end
					end
				else
					warn("[Pred v12] Persisted cal is for an older physics model — starting fresh under constant-deceleration model.")
				end
			end
		end
	end)
end
loadCal()

-- If the persisted calibration drifted into unusable values (e.g. ball reaches
-- only fractions of a stud at full power, or pocketR collapsed), fall back to
-- defaults so the predictor keeps drawing.
local function sanityCheckCal()
	local v_at_1  = CAL.powA * 1  + CAL.powB
	local v_at_21 = CAL.powA * 21 + CAL.powB
	local k_at_1  = CAL.kA + CAL.kB * 1
	local k_at_21 = CAL.kA + CAL.kB * 21
	-- Constant-decel reach: stop distance = v0² / (2K)
	local reach21 = (k_at_21 > 0.01) and (v_at_21*v_at_21 / (2*k_at_21)) or 0
	if v_at_1 < 0.7 or v_at_21 < 5 or v_at_21 > 500
	   or k_at_1 < 5 or k_at_21 < 5 or k_at_21 > 120 or reach21 < 5
	   or CAL.pocketR < 0.15 or CAL.pocketR > 1.5
	   or CAL.ballRest < 0.5 or CAL.ballRest > 1.0
	   or CAL.cushionRest < 0.2 or CAL.cushionRest > 1.0
	   or CAL.throwGain < 0 or CAL.throwGain > 0.15
	   or CAL.kBias < -30 or CAL.kBias > 30 then
		warn(string.format("[Pred v12] Calibration looked bad (v0(1)=%.2f v0(21)=%.2f K(1)=%.2f K(21)=%.2f reach=%.2f pocketR=%.2f ballR=%.2f) -> resetting to defaults.",
			v_at_1, v_at_21, k_at_1, k_at_21, reach21, CAL.pocketR, CAL.ballRest))
		cloneDefaultCalInto(CAL)
		pcall(function() if writefile then writefile(CAL_FILE, http:JSONEncode(CAL)) end end)
	end
end
sanityCheckCal()

-- ============ physics state fed into simulate() ============
-- PHYS.K is constant deceleration (stud/s²). Real billiard friction is well
-- approximated as v² = v0² - 2K·d (kinematics under a constant force).
local PHYS = {
	ballR = C.BALL_R, maxDepth = C.MAX_DEPTH, minSpeed = C.MIN_SPEED,
	K = 40.0, cushionRest = 0.9, ballRest = 0.92, pocketR = 0.5,
	throwGain = 0.04, cushionTangKeep = 0.78, cueTangKeep = 0.96,
}
-- set PHYS for a given shot power, return predicted initial speed v0
local function shotPhysics(power)
	PHYS.pocketR     = CAL.pocketR
	PHYS.cushionRest = CAL.cushionRest
	PHYS.ballRest    = CAL.ballRest
	-- Clamp deceleration to a physically realistic band. Without an upper cap a
	-- bad fit could push K toward the old 300 ceiling, which collapses the
	-- predicted reach (v0²/2K) so the guideline shrinks shot after shot.
	PHYS.K = clamp(CAL.kA + CAL.kB * power + (CAL.kBias or 0), 10, 90)
	PHYS.throwGain       = CAL.throwGain or 0
	PHYS.cushionTangKeep = C.CUSHION_TANG_KEEP
	PHYS.cueTangKeep     = C.CUE_TANG_KEEP
	return math.max(0, CAL.powA * power + CAL.powB)
end

-- ============ table binding ============
local userTable, userBalls, userBarrier, userPockets, userBounds, userCue, userComm, userPocketsX
local cachedStick = nil  -- findCueStick result cache; invalidated on table rebind

-- EXACT cushion bounds straight from the Barrier rail geometry. The Barrier is
-- four axis-aligned box parts (the cushions). A ball-CENTRE reflects when it is
-- one radius from a rail's inner face, so the reflective rectangle is each inner
-- face pulled inward by BALL_R. This is pixel-accurate and replaces the old
-- pocket-point inference, which was ~0.9 stud too tight and bounced balls early.
local function boundsFromRails(bar)
	if not bar then return nil end
	local cx, cz, n = 0, 0, 0
	local rails = {}
	for _,c in ipairs(bar:GetChildren()) do
		if c:IsA("BasePart") then
			rails[#rails+1] = c; cx = cx + c.Position.X; cz = cz + c.Position.Z; n = n + 1
		end
	end
	if n < 4 then return nil end
	cx, cz = cx/n, cz/n                       -- table centre
	local xLeft, xRight, zLow, zHigh
	for _,r in ipairs(rails) do
		local sx, sz, px, pz = r.Size.X, r.Size.Z, r.Position.X, r.Position.Z
		if sx < sz then                       -- vertical rail → constrains X
			if px < cx then xLeft  = math.max(xLeft  or -math.huge, px + sx*0.5)
			else            xRight = math.min(xRight or  math.huge, px - sx*0.5) end
		elseif sz < sx then                   -- horizontal rail → constrains Z
			if pz < cz then zLow   = math.max(zLow   or -math.huge, pz + sz*0.5)
			else            zHigh  = math.min(zHigh  or  math.huge, pz - sz*0.5) end
		end
	end
	if not (xLeft and xRight and zLow and zHigh) then return nil end
	local R = C.BALL_R
	return { xMin = xLeft + R, xMax = xRight - R, zMin = zLow + R, zMax = zHigh - R }
end

local function computeBounds(pocketList)
	if #pocketList < 4 then return nil end
	local xs = {}
	for _,p in ipairs(pocketList) do xs[#xs+1]=p.X end
	table.sort(xs)
	local xMin, xMax = xs[1], xs[#xs]
	local cz = {}
	for _,p in ipairs(pocketList) do
		if math.abs(p.X-xMin)<0.6 or math.abs(p.X-xMax)<0.6 then cz[#cz+1]=p.Z end
	end
	table.sort(cz)
	if #cz < 2 then return nil end
	local zMin, zMax = cz[1], cz[#cz]
	local R = C.BALL_R
	return { xMin=xMin+R, xMax=xMax-R, zMin=zMin+R, zMax=zMax-R }
end

local function bindTable(tbl)
	userTable   = tbl
	cachedStick = nil
	userBalls   = tbl:WaitForChild("Balls")
	userBarrier = tbl:WaitForChild("Barrier")
	userPockets = {}
	local pp = tbl:WaitForChild("PocketPoints")
	for _,x in ipairs(pp:GetChildren()) do
		if x:IsA("BasePart") then table.insert(userPockets, x.Position) end
	end
	-- Prefer exact rail geometry; fall back to pocket-point inference.
	local railB = boundsFromRails(userBarrier)
	userBounds = railB or computeBounds(userPockets)
	userPocketsX = {}
	local cx = userBounds and (userBounds.xMin+userBounds.xMax)*0.5 or 0
	local cz = userBounds and (userBounds.zMin+userBounds.zMax)*0.5 or 0
	if not userBounds then
		local sx,sz,n=0,0,0
		for _,p in ipairs(userPockets) do sx=sx+p.X; sz=sz+p.Z; n=n+1 end
		if n>0 then cx,cz = sx/n, sz/n end
	end
	for _,p in ipairs(userPockets) do
		local throat = Vector3.new(cx-p.X, 0, cz-p.Z)
		throat = (throat.Magnitude > 1e-3) and throat.Unit or Vector3.new(0,0,1)
		local kind = "corner"
		if userBounds then
			local nearX = (math.abs(p.X-userBounds.xMin) < 1.2) or (math.abs(p.X-userBounds.xMax) < 1.2)
			local nearZ = (math.abs(p.Z-userBounds.zMin) < 1.2) or (math.abs(p.Z-userBounds.zMax) < 1.2)
			if nearX and nearZ then kind = "corner"
			elseif nearX or nearZ then kind = "side" end
		end
		userPocketsX[#userPocketsX+1] = { pos = p, kind = kind, throat = throat,
			rfac = (kind == "side") and C.POCKET.SIDE_R_FACTOR or 1.0 }
	end
	local gd = tbl:WaitForChild("_GameData")
	userComm = gd:WaitForChild("Communication")
	_G.__POOL_COMM = userComm   -- let the shoot-remote hook recognise our table's remote
	if userBounds then
		print(string.format("[Pred v12] Bound table (%s). Bounds x[%.2f..%.2f] z[%.2f..%.2f]",
			railB and "rails" or "pockets",
			userBounds.xMin, userBounds.xMax, userBounds.zMin, userBounds.zMax))
	end
end

local function pickUserTable()
	if userTable and userTable.Parent then return true end
	local ct = workspace:FindFirstChild("ClassicTables")
	if not ct then return false end
	for _,tbl in ipairs(ct:GetChildren()) do
		local b   = tbl:FindFirstChild("Balls")
		local cue = b and b:FindFirstChild("Cue")
		local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		if b and cue and hrp and (cue.Position-hrp.Position).Magnitude < 30 then
			bindTable(tbl); return true
		end
	end
	return false
end

local gameStartConn = rs.Events.GameStartClient.OnClientEvent:Connect(function(tbl, cue, _, players)
	for _,p in ipairs(players) do
		if p == lp then bindTable(tbl); userCue = cue; return end
	end
end)
pickUserTable()

-- ============ power readout ============
local lastKnownPower = 1
local function readPower()
	for _,gui in ipairs(lp.PlayerGui:GetChildren()) do
		if gui.Name == "_GameInterface" or gui.Name == "_GameInterfaceCompetitive" then
			local pw = gui:FindFirstChild("Power")
			if pw then
				local ind = pw:FindFirstChild("Indicator")
				if ind and pw.AbsoluteSize.Y > 0 then
					-- Match the game EXACTLY (GameRunnerClient): power is
					-- Indicator.Offset / Power.AbsoluteSize.Y * 21, clamped 1..21.
					-- The old code used *18 and clamped 18, under-reading every
					-- shot and capping below the real max — which is what made
					-- the speed model and auto-fire wrong.
					local p = ind.Position.Y.Offset / pw.AbsoluteSize.Y * 21
					local v = clamp(p, 1, 21)
					if pw.Visible then lastKnownPower = v end
					return v, pw.Visible
				end
			end
		end
	end
	-- Fallback: the game keeps CueOffset lerped toward power*0.15, so
	-- CueOffset/0.15 recovers the same 1..21 power when the UI isn't readable.
	local v = clamp(guideMod.CueOffset / 0.15, 1, 21)
	if v > 1.5 then lastKnownPower = v end
	return v, false
end

-- ============ aim / cue-stick discovery ============
-- guideMod.MouseNormal can drop to nil/zero while the player is pulling the
-- cue back to set power. We resolve the aim direction from several sources
-- and cache the last good value so the trajectory keeps rendering.
local lastAimDir, lastAimDirT = nil, 0

local function findCueStick()
	if cachedStick and cachedStick.Parent then return cachedStick end
	local function asPart(x)
		if not x then return nil end
		if x:IsA("BasePart") then return x end
		if x:IsA("Model") then return x:FindFirstChildWhichIsA("BasePart", true) end
		return nil
	end
	local s = asPart(workspace:FindFirstChild("DefaultCue"))
	if s then cachedStick = s; return s end
	if userTable then
		for _,n in ipairs({"DefaultCue","CueStick","Cuestick","Cue_Stick","Stick"}) do
			local f = userTable:FindFirstChild(n, true)
			local p = asPart(f)
			if p then cachedStick = p; return p end
		end
	end
	if lp.Character then
		for _,n in ipairs({"DefaultCue","CueStick","Cuestick"}) do
			local f = lp.Character:FindFirstChild(n, true)
			local p = asPart(f)
			if p then cachedStick = p; return p end
		end
	end
	for _,c in ipairs(workspace:GetChildren()) do
		local nm = c.Name:lower()
		if nm == "defaultcue" or nm == "cuestick" or nm == "cue_stick" or nm:find("^cue[_%-]") then
			local p = asPart(c)
			if p then cachedStick = p; return p end
		end
	end
	return nil
end

local function getAimDir(cb)
	-- 1. Module fields (matches the convention predConn was already using)
	if guideMod then
		for _,name in ipairs({"MouseNormal","AimNormal","AimDirection","ShotDirection","ShotNormal"}) do
			local v = guideMod[name]
			if typeof(v) == "Vector3" and v.Magnitude > 0.5 then
				local f = Vector3.new(v.X, 0, v.Z)
				if f.Magnitude > 0.1 then
					lastAimDir = f.Unit; lastAimDirT = tick()
					return lastAimDir
				end
			end
		end
	end
	-- 2. Cue stick -> cue ball: stable while the player is pulling the cue
	local stick = findCueStick()
	if stick and cb then
		local d = cb.Position - stick.Position
		local flat = Vector3.new(d.X, 0, d.Z)
		if flat.Magnitude > 0.3 then
			lastAimDir = flat.Unit; lastAimDirT = tick()
			return lastAimDir
		end
	end
	-- 3. Last known good direction (caps at 3s so a stale aim isn't held forever)
	if lastAimDir and tick() - lastAimDirT < 3 then return lastAimDir end
	return nil
end

-- ============ drawing pool ============
local pool, poolIdx = {}, 0
local function getPart()
	poolIdx = poolIdx + 1
	if pool[poolIdx] then pool[poolIdx].Transparency = 0.25; return pool[poolIdx] end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Material = Enum.Material.Neon; p.Transparency = 0.25
	p.Size = Vector3.new(0.08, 0.04, 0.1); p.Parent = workspace
	pool[poolIdx] = p; return p
end
local function resetPool() for _,p in ipairs(pool) do p.Transparency = 1 end; poolIdx = 0 end

-- Lines are drawn down at cloth level so they read as clean guidelines instead
-- of square blocks slicing through the balls at centre height.
local LINE_Y = -C.BALL_R + 0.03
-- Configure a part as a rounded neon tube spanning p1->p2. A Cylinder's length
-- runs along its local X axis, so we take the lookAt frame (whose -Z faces the
-- target) and rotate it 90° about Y to put that length axis onto the segment.
local function setTube(part, p1, p2, dia)
	local a = Vector3.new(p1.X, p1.Y + LINE_Y, p1.Z)
	local b = Vector3.new(p2.X, p2.Y + LINE_Y, p2.Z)
	local len = (b - a).Magnitude
	if len < 0.05 then part.Transparency = 1; return false end
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Size = Vector3.new(len, dia, dia)
	part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	return true
end

local function drawSeg(p1, p2, color, thick)
	local part = getPart(); part.Color = color
	if setTube(part, p1, p2, (thick or 0.07) * 1.7) then
		part.Transparency = 0.1
	end
end

-- Resting position shown as a translucent ghost of the ball — far prettier and
-- clearer than a flat square decal on the cloth.
local function drawDot(pos, color)
	if not pos then return end
	local part = getPart()
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.ForceField
	part.Color = color
	part.Transparency = 0.2
	local dia = 2 * C.BALL_R * 1.06
	part.Size = Vector3.new(dia, dia, dia)
	part.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
end

local hl = {}
local function getHL(b, c)
	local h = hl[b]
	if not h or not h.Parent then
		h = Instance.new("Highlight"); h.FillTransparency = 0.5; h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Parent = b; hl[b] = h
	end
	h.FillColor = c; h.OutlineColor = c
	h.Adornee = b; h.Enabled = true
end
local function clearHL() for _,h in pairs(hl) do h.Enabled = false end end

-- ============ on-table visual polish (make-% tag, pocket marker, replay) ============
-- All parented to workspace (NOT sg), so cleanup() destroys them explicitly.
-- Everything here is event/recompute-driven; no per-frame loop is created.

-- Reusable make-% billboard on a tiny invisible anchor part.
local makeTagPart, makeTagLabel
local function getMakeTag()
	if makeTagPart and makeTagPart.Parent and makeTagLabel and makeTagLabel.Parent then
		return makeTagPart, makeTagLabel
	end
	local part = Instance.new("Part")
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Transparency = 1; part.Size = Vector3.new(0.05, 0.05, 0.05)
	part.Name = "PoolMakeTagAnchor"; part.Parent = workspace
	local bb = Instance.new("BillboardGui")
	bb.Name = "MakeTag"; bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 70, 0, 28); bb.StudsOffsetWorldSpace = Vector3.new(0, 0.9, 0)
	bb.Parent = part
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1; lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true
	lbl.TextStrokeTransparency = 0.2; lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.Text = ""; lbl.Parent = bb
	makeTagPart, makeTagLabel = part, lbl
	return part, lbl
end

-- Reusable neon pocket marker (ForceField ball at the target pocket).
local pocketMarker
local function getPocketMarker()
	if pocketMarker and pocketMarker.Parent then return pocketMarker end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Material = Enum.Material.ForceField; p.Color = C.COL_POCKET
	p.Transparency = 0.2; p.Size = Vector3.new(0.5, 0.5, 0.5)
	p.Name = "PoolPocketMarker"; p.Parent = workspace
	pocketMarker = p; return p
end

-- ===== predicted-vs-actual replay (CHANGE 2) =====
-- Own small reusable pool of parts; faded out after ~3s via task.delay (NO loop).
local replayParts = {}
local replayIdx = 0
local function getReplayPart()
	replayIdx = replayIdx + 1
	local p = replayParts[replayIdx]
	if not p then
		p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.Material = Enum.Material.Neon
		p.Parent = workspace
		replayParts[replayIdx] = p
	end
	p.Transparency = 0.2
	return p
end
-- showReplay is defined here (above finalizeShot) so it is in scope at the call.
local function showReplay(predFinals, realFinal, moved)
	if not predFinals or not realFinal or not moved then return end
	if next(moved) == nil then return end
	replayIdx = 0
	local drewAny = false
	for inst in pairs(moved) do
		local pf = predFinals[inst]
		local rf = realFinal[inst]
		if pf and rf then
			drewAny = true
			local col = ballColor(inst)
			-- hollow ghost at predicted resting position
			local ghost = getReplayPart()
			ghost.Shape = Enum.PartType.Ball
			ghost.Material = Enum.Material.ForceField
			ghost.Color = col
			ghost.Transparency = 0.55
			local gd = 2 * C.BALL_R * 1.08
			ghost.Size = Vector3.new(gd, gd, gd)
			ghost.CFrame = CFrame.new(pf.X, pf.Y, pf.Z)
			-- solid marker at the actual resting position
			local solid = getReplayPart()
			solid.Shape = Enum.PartType.Ball
			solid.Material = Enum.Material.Neon
			solid.Color = col
			solid.Transparency = 0.1
			local sd = 2 * C.BALL_R * 0.7
			solid.Size = Vector3.new(sd, sd, sd)
			solid.CFrame = CFrame.new(rf.X, rf.Y, rf.Z)
			-- error tube coloured by stud error
			local err = (Vector3.new(pf.X, 0, pf.Z) - Vector3.new(rf.X, 0, rf.Z)).Magnitude
			local errCol = (err < 0.3 and C.COL_POCKET)
				or (err < 0.8 and Color3.fromRGB(255, 200, 40))
				or Color3.fromRGB(255, 60, 60)
			local tube = getReplayPart()
			tube.Color = errCol
			if not setTube(tube, pf, rf, 0.06) then tube.Transparency = 1 end
		end
	end
	-- hide any leftover parts from a previous (larger) replay
	for i = replayIdx + 1, #replayParts do replayParts[i].Transparency = 1 end
	if not drewAny then return end
	task.delay(3, function()
		for _, p in ipairs(replayParts) do
			if p and p.Parent then p.Transparency = 1 end
		end
	end)
end

-- ============ snapshot ============
local function snapshotBalls()
	local list = {}
	if not userBalls then return list end
	for _,b in ipairs(userBalls:GetChildren()) do
		if b:IsA("BasePart") and (tonumber(b.Name) or b.Name == "Cue") then
			list[b] = b.Position
		end
	end
	return list
end

-- Cheap layout fingerprint: collapses every relevant ball's X/Z into one number.
-- Used to skip re-predicting / re-solving when nothing on the table has moved.
local function ballHashQuick()
	if not userBalls then return 0 end
	local h, n = 0.0, 0
	for _, b in ipairs(userBalls:GetChildren()) do
		if b:IsA("BasePart") and (tonumber(b.Name) or b.Name == "Cue") then
			local p = b.Position
			h = h + p.X * 0.7349 + p.Z * 1.3171
			n = n + 1
		end
	end
	return math.floor(h * 16) + n * 1000000
end

-- ============ ray casters ============
local function castCushion(pos, dir, maxDist)
	if not userBounds then return nil end
	local b = userBounds
	local bT, bN = math.huge, nil
	if dir.X > 1e-6 then
		local t = (b.xMax - pos.X) / dir.X
		if t > 0 and t < bT then bT = t; bN = Vector3.new(-1,0,0) end
	elseif dir.X < -1e-6 then
		local t = (b.xMin - pos.X) / dir.X
		if t > 0 and t < bT then bT = t; bN = Vector3.new(1,0,0) end
	end
	if dir.Z > 1e-6 then
		local t = (b.zMax - pos.Z) / dir.Z
		if t > 0 and t < bT then bT = t; bN = Vector3.new(0,0,-1) end
	elseif dir.Z < -1e-6 then
		local t = (b.zMin - pos.Z) / dir.Z
		if t > 0 and t < bT then bT = t; bN = Vector3.new(0,0,1) end
	end
	if bT < math.huge and bT <= maxDist then return bT, bN, pos + dir*bT end
	return nil
end

local function castBall(orig, pos, dir, maxDist, snap)
	local hit, hD, hP = nil, math.huge, nil
	local rsq = (2*PHYS.ballR)^2
	for ball, bp in pairs(snap) do
		if ball ~= orig then
			local d = bp - pos
			local along = d:Dot(dir)
			if along > 0 and along - 2*PHYS.ballR < maxDist then
				local perp = d - dir*along
				local m2 = perp:Dot(perp)
				if m2 < rsq then
					local back = math.sqrt(rsq - m2)
					local enter = along - back
					if enter >= 0 and enter < hD then hD, hit = enter, ball; hP = pos + dir*enter end
				end
			end
		end
	end
	return hit, hD, hP
end

local function castPocket(pos, dir, maxDist, speed, K)
	local bD, bP = math.huge, nil
	local baseR = PHYS.pocketR
	local PK = C.POCKET
	for _,info in ipairs(userPocketsX or {}) do
		local pp = info.pos
		local R = baseR * info.rfac
		local d = pp - pos
		local along = d:Dot(dir)
		if along > -R and along < maxDist + R then
			local perp = Vector3.new(d.X - dir.X*along, 0, d.Z - dir.Z*along)
			local pd2 = perp:Dot(perp)
			local Reff = R
			if PK.ENABLED and speed and K then
				local enter0 = math.max(0, along)
				local vAtSq = speed*speed - 2*K*enter0
				local vAt = vAtSq > 0 and math.sqrt(vAtSq) or 0
				Reff = R * clamp(1 - PK.SPEED_PEN*math.max(0, vAt - PK.SPEED_SOFT), PK.MIN_R_FACTOR, 1)
				if vAt > PK.ANGLE_MIN_SPEED then
					local cone = (info.kind == "side") and PK.CONE_SIDE or PK.CONE_CORNER
					if dir:Dot(info.throat) > -math.cos(cone) then Reff = -1 end
				end
			end
			if Reff > 0 and pd2 < Reff*Reff then
				local back = math.sqrt(Reff*Reff - pd2)
				local enter = math.max(0, along - back)
				if enter < bD and enter <= maxDist then bD, bP = enter, pos + dir*enter end
			end
		end
	end
	return bD < math.huge and bD, bP
end

local function endpointInPocket(pos)
	for _,info in ipairs(userPocketsX or {}) do
		local pp = info.pos
		if (Vector3.new(pos.X-pp.X, 0, pos.Z-pp.Z)).Magnitude < PHYS.pocketR * info.rfac then return pp end
	end
	return nil
end

-- ============ core simulation ============
-- Cut-induced throw: object departs a few degrees off the line-of-centers toward
-- the cue's tangential motion. along=cos(cut); sin·cos peaks at 45°, 0 at straight/90°.
local function throwAngle(along)
	local s = math.sqrt(math.max(0, 1 - along*along))
	return PHYS.throwGain * s * along
end

-- finals[ball] = predicted resting position. pT[ball] = "pocket"/"scratch".
local function simulate(ball, pos, dir, speed, depth, snap, isCue, segs, pT, ctx, finals)
	if depth > PHYS.maxDepth or speed < PHYS.minSpeed then
		if finals then finals[ball] = pos end
		return
	end
	if dir.Magnitude < 1e-3 then if finals then finals[ball]=pos end return end
	dir = dir.Unit
	local K = math.max(0.5, PHYS.K)            -- constant deceleration (stud/s²)
	local maxDist = speed * speed / (2 * K)    -- v² = 2K·d_stop
	if maxDist < 0.03 then if finals then finals[ball]=pos end return end

	local hB, hBD, hBP = castBall(ball, pos, dir, maxDist, snap)
	local cD, cN, cP   = castCushion(pos, dir, math.min(maxDist, hBD or maxDist))
	local pD, pP       = castPocket(pos, dir, math.min(maxDist, hBD or maxDist), speed, K)
	if cD and cP and endpointInPocket(cP) then
		if not pD or cD < pD then pD, pP = cD, cP; cD = nil end
	end

	local e = nil
	if hBD < math.huge then e = {kind="ball", d=hBD, ball=hB, p=hBP} end
	if cD and (not e or cD < e.d) then e = {kind="cushion", d=cD, n=cN, p=cP} end
	if pD and (not e or pD < e.d) then e = {kind="pocket", d=pD, p=pP} end

	local color = isCue and (depth==0 and C.COL_CUE or C.COL_CUE_DEFL)
		or (depth<=1 and C.COL_TARGET or C.COL_CHAIN)
	local thick = isCue and 0.10 or 0.12

	if not e then
		local endP = pos + dir*maxDist
		if segs then segs[#segs+1] = {ball=ball, p1=pos, p2=endP, color=color, thick=thick, isCue=isCue} end
		local pin = endpointInPocket(endP)
		if pin then pT[ball] = isCue and "scratch" or "pocket" end
		if finals then finals[ball] = pin or endP end
		return
	end

	if segs then segs[#segs+1] = {ball=ball, p1=pos, p2=e.p, color=color, thick=thick, isCue=isCue} end

	if e.kind == "pocket" then
		pT[ball] = isCue and "scratch" or "pocket"
		if finals then finals[ball] = e.p end
		return
	elseif e.kind == "cushion" then
		local vInSq = speed*speed - 2*K*e.d
		if vInSq <= 0 then if finals then finals[ball]=e.p end return end
		local vIn = math.sqrt(vInSq)
		local dn = dir:Dot(e.n)
		local tx, tz = dir.X - e.n.X*dn, dir.Z - e.n.Z*dn
		local outVx = e.n.X*(-dn)*PHYS.cushionRest + tx*PHYS.cushionTangKeep
		local outVz = e.n.Z*(-dn)*PHYS.cushionRest + tz*PHYS.cushionTangKeep
		local mag = math.sqrt(outVx*outVx + outVz*outVz)
		if mag < 1e-4 then if finals then finals[ball]=e.p end return end
		local nS = vIn * mag
		if nS < PHYS.minSpeed then if finals then finals[ball]=e.p end return end
		if ctx then ctx.railTouched = true end
		simulate(ball, e.p, Vector3.new(outVx/mag, 0, outVz/mag), nS, depth+1, snap, isCue, segs, pT, ctx, finals)
	elseif e.kind == "ball" then
		if isCue and ctx and not ctx.firstHit then ctx.firstHit = e.ball end
		local sIsq = speed*speed - 2*K*e.d
		if sIsq <= 0 then if finals then finals[ball]=e.p end return end
		local sI = math.sqrt(sIsq)
		if sI < PHYS.minSpeed then if finals then finals[ball]=e.p end return end
		local objPos = snap[e.ball]
		local cl = objPos - e.p
		if cl.Magnitude < 1e-4 then if finals then finals[ball]=e.p end return end
		cl = cl.Unit
		local along = dir:Dot(cl)
		if along < 0 then if finals then finals[ball]=e.p end return end
		local restE = PHYS.ballRest
		local va_along = sI * along
		local va_after = (1 - restE) / 2 * va_along
		local vb_after = (1 + restE) / 2 * va_along
		local va_tang  = sI * math.sqrt(math.max(0, 1 - along*along)) * PHYS.cueTangKeep
		local rawTang = dir - cl*along
		local tangDir = (rawTang.Magnitude > 1e-4) and rawTang.Unit or Vector3.zero
		local objDir = cl
		local th = throwAngle(along)
		if th > 1e-4 and tangDir.Magnitude > 0.5 then
			local rot = cl*math.cos(th) + tangDir*math.sin(th)
			if rot.Magnitude > 1e-4 then objDir = rot.Unit end
		end
		local savedBall = snap[e.ball]
		snap[e.ball] = objPos + cl*0.02
		if vb_after > PHYS.minSpeed then
			simulate(e.ball, objPos, objDir, vb_after, depth+1, snap, false, segs, pT, ctx, finals)
		elseif finals then finals[e.ball] = objPos end
		local cueNewSp = math.sqrt(va_after*va_after + va_tang*va_tang)
		if cueNewSp > PHYS.minSpeed then
			local cueNewDir = cl*va_after + tangDir*va_tang
			if cueNewDir.Magnitude > 1e-4 then
				simulate(ball, e.p, cueNewDir.Unit, cueNewSp, depth+1, snap, isCue, segs, pT, ctx, finals)
			elseif finals then finals[ball] = e.p end
		elseif finals then finals[ball] = e.p end
		snap[e.ball] = savedBall
	end
end

-- ============ live prediction render ============
local __lastWarnT = 0
local function poolWarn(e)
	local t = os.clock()
	if t - __lastWarnT > 1 then __lastWarnT = t; warn("[Pred v12] loop error: " .. tostring(e)) end
end
local lastDir, lastPower, lastPredHash = nil, -1, nil
local predConn = rsv.RenderStepped:Connect(function()
	local __ok, __e = pcall(function()
	if not pickUserTable() then resetPool(); clearHL(); return end
	if not (userBalls and userBalls.Parent) then resetPool(); clearHL(); return end
	local cb = userBalls:FindFirstChild("Cue")
	if not cb then resetPool(); clearHL(); return end
	local dir = getAimDir(cb)
	if not dir or dir.Magnitude < 0.5 then resetPool(); clearHL(); return end
	dir = dir.Unit
	local power = readPower()
	-- Dirty-state gate: when the aim, power and table layout are all unchanged the
	-- last frame's drawing is still valid, so skip the whole simulate+redraw (and
	-- crucially do NOT clear the pool, leaving the existing guideline on screen).
	local h = ballHashQuick()
	if lastDir and h == lastPredHash and math.abs(power - lastPower) < 0.05 and dir:Dot(lastDir) > 0.99995 then
		return
	end
	lastDir, lastPower, lastPredHash = dir, power, h
	resetPool(); clearHL()
	local v0 = shotPhysics(power)
	-- Ensure we always have enough speed to draw at least the first segment,
	-- even when the player is still at minimum power.
	if v0 < PHYS.minSpeed + 0.5 then v0 = PHYS.minSpeed + 0.5 end
	local snap = snapshotBalls()
	local segs, pocket, ctx, finals = {}, {}, {}, {}
	simulate(cb, cb.Position, dir, v0, 0, snap, true, segs, pocket, ctx, finals)
	-- Each segment is colour-coded by the ball it represents (cue stays
	-- white/orange; object balls take the standard 8-ball pool palette so
	-- you can immediately see which ball ends up where).
	for _,s in ipairs(segs) do
		local show = s.isCue or pocket[s.ball] or not C.FILTER_NON_POCKETED
		if show then
			local col = s.isCue and s.color or ballColor(s.ball)
			drawSeg(s.p1, s.p2, col, s.thick)
		end
	end
	-- Endpoint markers: cue → red (scratch) or white, object ball → its palette colour
	if finals[cb] then
		drawDot(finals[cb], pocket[cb] == "scratch" and C.COL_SCRATCH or C.COL_CUE)
	end
	for ball, fp in pairs(finals) do
		if ball ~= cb and (pocket[ball] or not C.FILTER_NON_POCKETED) then
			drawDot(fp, ballColor(ball))
		end
	end
	-- Highlight pocketed balls with green / scratched cue with red
	for ball, k in pairs(pocket) do
		getHL(ball, k == "scratch" and C.COL_SCRATCH or C.COL_POCKET)
	end
	end)
	if not __ok then poolWarn(__e) end
end)

-- ============ best-shot evaluation ============
local function isMy(name, rule)
	local n = tonumber(name); if not n then return false end
	if rule == "<9" then return n >= 1 and n <= 7
	elseif rule == ">7" then return n >= 9 and n <= 15
	else return n >= 1 and n <= 7 or n >= 9 and n <= 15 end
end
local function isOpp(name, rule)
	local n = tonumber(name); if not n then return false end
	if rule == "<9" then return n >= 9 and n <= 15
	elseif rule == ">7" then return n >= 1 and n <= 7
	else return false end
end
-- How many of my balls are still on the table. When this hits 0 (and a group is
-- assigned) I'm "on the 8" — the black ball becomes the target, not a hazard.
local function myBallsLeft(snap, rule)
	local n = 0
	for ball,_ in pairs(snap) do
		if ball.Name ~= "Cue" and isMy(ball.Name, rule) then n = n + 1 end
	end
	return n
end
local function evalShot(cb, cp, dir, power, snap, rule)
	local pocket, ctx = {}, {firstHit=nil}
	local v0 = shotPhysics(power)
	simulate(cb, cp, dir, v0, 0, snap, true, nil, pocket, ctx, nil)
	local s, sc, foul = 0, 0, false
	-- Endgame: all my colours cleared and I have a group → the 8 is my ball.
	local onEight = (rule ~= "" and myBallsLeft(snap, rule) == 0)
	if ctx.firstHit then
		local fh = ctx.firstHit.Name
		if onEight then
			if fh ~= "8" then foul = true end          -- must contact the 8 first
		else
			if isOpp(fh, rule) or fh == "8" then foul = true end
		end
	else foul = true end
	if foul then return -20, pocket, 0 end
	for ball, k in pairs(pocket) do
		if k == "scratch" then s = s - 8
		elseif ball.Name == "8" then
			if onEight then s = s + 100; sc = sc + 1    -- sinking the 8 now WINS
			else s = s - 100 end                         -- otherwise it's a loss
		elseif isMy(ball.Name, rule) then s = s + 10; sc = sc + 1
		elseif isOpp(ball.Name, rule) then s = s - 4 end
	end
	-- A shot that pots NOTHING is not a "best shot" — give it no positive base,
	-- so when no real pot exists the suggestion is hidden instead of pointing the
	-- cue at a random cushion. The gentle power penalty only tie-breaks between
	-- real pots toward softer, more controllable shots.
	if sc == 0 then return -1 - power * 0.02, pocket, 0 end
	s = s - power * 0.02
	return s, pocket, sc
end

-- Is the straight line a→b clear of every ball except the two endpoints' balls?
local function pathClear(a, b, snap, ignoreA, ignoreB)
	local dx, dz = b.X - a.X, b.Z - a.Z
	local L = math.sqrt(dx*dx + dz*dz)
	if L < 1e-3 then return true end
	local ux, uz = dx / L, dz / L
	local rr = 2 * C.BALL_R
	for ball, bp in pairs(snap) do
		if ball ~= ignoreA and ball ~= ignoreB then
			local rx, rz = bp.X - a.X, bp.Z - a.Z
			local along = rx*ux + rz*uz
			if along > rr*0.5 and along < L - rr*0.5 then
				local perp = math.abs(rx*(-uz) + rz*ux)
				if perp < rr then return false end
			end
		end
	end
	return true
end

-- Position ("leave") quality after a shot: reward a cue resting spot that has a
-- clean look at my remaining balls (each with a clear line to a pocket); penalise
-- ending buried on a rail. Cheap heuristic used only on the final candidates.
local function leaveScore(cueFinal, snap, sunkSet, rule, forceEight)
	if not cueFinal then return 0 end
	local railPen = 0
	if userBounds then
		local m = 0.45
		if (cueFinal.X - userBounds.xMin) < m or (userBounds.xMax - cueFinal.X) < m
		   or (cueFinal.Z - userBounds.zMin) < m or (userBounds.zMax - cueFinal.Z) < m then
			railPen = -1.5
		end
	end
	local onEight = forceEight or (rule ~= "" and myBallsLeft(snap, rule) == 0)
	local makeable = 0
	for ball, bp in pairs(snap) do
		local isTarget = (onEight and ball.Name == "8") or (not onEight and isMy(ball.Name, rule))
		if isTarget and not (sunkSet and sunkSet[ball]) and pathClear(cueFinal, bp, snap, nil, ball) then
			for _, pp in ipairs(userPockets or {}) do
				if pathClear(bp, pp, snap, ball, nil) then makeable = makeable + 1; break end
			end
		end
	end
	return railPen + math.min(makeable, 3) * 1.2
end

-- Best/placement info is shown in the side HUD panel (assigned where the HUD is
-- built, below) — never as floating text on the table.
local setHudInfo
local refreshShotList
local toggleLegend
-- Aim fine-tune offset (degrees) applied on top of the chosen shot's direction
-- in applyAutoAim. Declared here so both recompute() (which resets it) and
-- applyAutoAim() (far below, in the auto-aim section) share the same upvalue.
local aimOffsetDeg = 0

local bestState = {enabled=true, parts={}, lastCompute=0, current=nil, list={}, selIdx=1, safetyEnabled=true}
local lastBestHash = nil   -- layout fingerprint at last recompute() (best-shot solver)
local lastPlaceHash = nil  -- layout fingerprint at last recomputePlacement()
local function getBP(idx, c)
	if not bestState.parts[idx] then
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.Material = Enum.Material.Neon; p.Transparency = 0.05
		p.Parent = workspace; bestState.parts[idx] = p
	end
	local p = bestState.parts[idx]; p.Color = c or C.COL_BEST; p.Transparency = 0.05; return p
end
local function clearBP() for _,p in ipairs(bestState.parts) do p.Transparency = 1 end end
-- ===== precise shot finder (ultraPrecise=true → ±0.05° final grid) =====
-- Strategy:
--   1) Ghost-ball candidates  — for each (my-ball, pocket) pair compute the
--      contact point and the required cue direction analytically. Direction
--      precision is independent of the friction calibration.
--   2) Brute-force angle grid — catches combos, banked, and clearance shots
--      the geometric step doesn't consider.
--   3) Refine the top candidate with progressively finer angle/power grids.
local function aimToSend(cuePos, ballPos, targetDir)
	if targetDir.Magnitude < 1e-4 then return nil end
	targetDir = targetDir.Unit
	local R2 = 2 * C.BALL_R
	local ghost = ballPos - targetDir * R2
	local toGhost = Vector3.new(ghost.X - cuePos.X, 0, ghost.Z - cuePos.Z)
	if toGhost.Magnitude < 0.5 then return nil end
	local dir = toGhost.Unit
	local along = dir:Dot(targetDir)
	if along > 0.05 then
		local th = throwAngle(along)
		if th > 1e-4 then
			local rawTang = dir - targetDir*along
			if rawTang.Magnitude > 1e-4 then
				local tang = rawTang.Unit
				local cl2 = targetDir*math.cos(th) - tang*math.sin(th)
				if cl2.Magnitude > 1e-4 then
					cl2 = cl2.Unit
					local ghost2 = ballPos - cl2*R2
					local tg2 = Vector3.new(ghost2.X - cuePos.X, 0, ghost2.Z - cuePos.Z)
					if tg2.Magnitude > 0.5 then dir = tg2.Unit end
				end
			end
		end
	end
	return dir
end
local function detectBreak(snap)
	local n, minx, maxx, minz, maxz = 0, math.huge, -math.huge, math.huge, -math.huge
	for ball, bp in pairs(snap) do
		if ball.Name ~= "Cue" and tonumber(ball.Name) then
			n = n + 1
			minx = math.min(minx, bp.X); maxx = math.max(maxx, bp.X)
			minz = math.min(minz, bp.Z); maxz = math.max(maxz, bp.Z)
		end
	end
	if n < 14 then return false end
	return math.max(maxx - minx, maxz - minz) < 6
end
local function breakShot(cb, cp, snap)
	local cx, cz, n = 0, 0, 0
	for ball, bp in pairs(snap) do
		if ball.Name ~= "Cue" and tonumber(ball.Name) then cx = cx + bp.X; cz = cz + bp.Z; n = n + 1 end
	end
	if n == 0 then return nil end
	cx, cz = cx / n, cz / n
	local base = Vector3.new(cx - cp.X, 0, cz - cp.Z)
	if base.Magnitude < 0.5 then return nil end
	base = base.Unit
	for _, off in ipairs({0, -3, 3, -6, 6}) do
		local r = math.rad(off)
		local d = Vector3.new(base.X*math.cos(r) - base.Z*math.sin(r), 0, base.X*math.sin(r) + base.Z*math.cos(r))
		local pocket = {}
		simulate(cb, cp, d, shotPhysics(21), 0, snap, true, nil, pocket, {}, {})
		if pocket[cb] ~= "scratch" then
			return { dir = d, power = 21, sunk = 0, score = 1, ["break"] = true,
			         angle = math.deg(math.atan2(d.Z, d.X)) }
		end
	end
	return nil
end
local function safetyScore(cueFinal, snap, rule)
	local reach, nearestOpp = 0, math.huge
	for ball, bp in pairs(snap) do
		if ball.Name ~= "Cue" and isOpp(ball.Name, rule) then
			local dist = (Vector3.new(cueFinal.X - bp.X, 0, cueFinal.Z - bp.Z)).Magnitude
			if dist < nearestOpp then nearestOpp = dist end
			if pathClear(cueFinal, bp, snap, nil, ball) then reach = reach + 1 end
		end
	end
	local railBonus = 0
	if userBounds then
		local m = 0.5
		if (cueFinal.X - userBounds.xMin) < m or (userBounds.xMax - cueFinal.X) < m
		   or (cueFinal.Z - userBounds.zMin) < m or (userBounds.zMax - cueFinal.Z) < m then railBonus = 1.0 end
	end
	if nearestOpp == math.huge then nearestOpp = 0 end
	return -reach * 3 + math.min(nearestOpp, 20) * 0.1 + railBonus
end
local function findSafety()
	if not pickUserTable() then return nil end
	local cb = userBalls:FindFirstChild("Cue"); if not cb then return nil end
	local cp = cb.Position
	local snap = snapshotBalls()
	local rule = guideMod.Rule or ""
	local onEight = (rule ~= "" and myBallsLeft(snap, rule) == 0)
	local best = { score = -math.huge }
	for ang = 0, 359, 6 do
		local r = math.rad(ang)
		local d = Vector3.new(math.cos(r), 0, math.sin(r))
		for _, p in ipairs({4, 7, 10}) do
			local pocket, ctx, finals = {}, { firstHit = nil }, {}
			simulate(cb, cp, d, shotPhysics(p), 0, snap, true, nil, pocket, ctx, finals)
			local legal = false
			if ctx.firstHit then
				local fh = ctx.firstHit.Name
				if onEight then legal = (fh == "8") else legal = not (isOpp(fh, rule) or fh == "8") end
			end
			local scratched = pocket[cb] == "scratch"
			if legal and not scratched and (ctx.railTouched or next(pocket) ~= nil) then
				local cueFinal = finals[cb] or cp
				local sc = safetyScore(cueFinal, snap, rule)
				if sc > best.score then
					best = { score = sc, dir = d, power = p, cueFinal = cueFinal, safety = true, sunk = 0,
					         angle = math.deg(math.atan2(d.Z, d.X)) }
				end
			end
		end
	end
	if best.score == -math.huge then return nil end
	return best
end
local function findBest(ultraPrecise)
	if not pickUserTable() then return nil end
	local cb = userBalls:FindFirstChild("Cue"); if not cb then return nil end
	local cp = cb.Position
	local snap = snapshotBalls()
	local rule = guideMod.Rule or ""
	local best = {score = -math.huge}
	bestState.list = {}
	if detectBreak(snap) then
		local bs = breakShot(cb, cp, snap)
		if bs then bestState.list = { bs }; bestState.selIdx = 1; return bs end
	end

	-- helper to evaluate and track best. Every shot that pots at least one of
	-- my balls is also kept as a candidate; after the search we re-rank the top
	-- ones by aim-robustness so a reliable fat shot beats a razor-thin cut that
	-- merely tied on raw score.
	local cands = {}
	local evalN = 0
	local function tryShot(d, p, src)
		-- hard budget so one findBest can never explode (and freeze the client),
		-- whatever generators/flags are on. Refinement/re-rank run after this.
		evalN = evalN + 1
		if evalN > (C.SEARCH.MAX_EVALS or 1400) then return end
		local s, pk, sk = evalShot(cb, cp, d, p, snap, rule)
		if s > best.score then
			best = {score=s, dir=d, power=p, pocketed=pk, sunk=sk,
				angle=math.deg(math.atan2(d.Z, d.X)), src=src}
		end
		if s > 0 and sk and sk > 0 then
			cands[#cands+1] = {score=s, dir=d, power=p, pocketed=pk, sunk=sk,
				angle=math.deg(math.atan2(d.Z, d.X)), src=src}
		end
	end

	-- --- (1) GHOST-BALL CANDIDATES ---
	-- For each of my balls and each pocket: find the cue direction that sends
	-- the ball straight into the pocket. Pick a power that ensures the ball
	-- has enough energy to reach the pocket (overshoot is harmless).
	local R = C.BALL_R
	local Kref = math.max(1, CAL.kA + CAL.kB * 12)  -- pick a mid-power K
	local ghostCount = 0
	for ball, bp in pairs(snap) do
		if ball ~= cb and isMy(ball.Name, rule) then
			for _, pp in ipairs(userPockets or {}) do
				local toPocket = Vector3.new(pp.X - bp.X, 0, pp.Z - bp.Z)
				local toPocketLen = toPocket.Magnitude
				if toPocketLen > 0.5 then
					local toPocketDir = toPocket.Unit
					-- Ghost ball position: cue ball CENTRE at moment of contact
					local ghost = Vector3.new(bp.X, bp.Y, bp.Z) - toPocketDir * (2*R)
					local cueToGhost = Vector3.new(ghost.X - cp.X, 0, ghost.Z - cp.Z)
					local cueToGhostLen = cueToGhost.Magnitude
					if cueToGhostLen > 0.5 then
						local dir = cueToGhost.Unit
						dir = aimToSend(cp, bp, toPocketDir) or dir
						-- Required object-ball launch speed to reach pocket:
						--   vB0² = 2·K·toPocketLen  → vB0 = sqrt(2K·D)
						-- Plus comfort margin so the ball clearly enters the pocket.
						local vB_needed = math.sqrt(2 * Kref * toPocketLen) + 2.5
						-- Cue speed at contact along LoC = 2·vB / (1+e)
						local va_contact = 2 * vB_needed / (1 + CAL.ballRest)
						-- Cue v0 = sqrt(va_contact² + 2K·cueToGhostLen)
						local v0_needed = math.sqrt(va_contact*va_contact + 2*Kref*cueToGhostLen)
						-- Solve power: v0 = powA·p + powB
						local p_needed = (v0_needed - CAL.powB) / math.max(0.1, CAL.powA)
						p_needed = clamp(p_needed, 4, 21)
						tryShot(dir, p_needed, "ghost")
						-- Also try a slightly harder power for safety overshoot
						if p_needed < 19 then
							tryShot(dir, math.min(21, p_needed + 2.5), "ghost+")
						end
						ghostCount = ghostCount + 1
					end
				end
			end
		end
	end

	-- --- (1b) SHOT-TYPE GENERATORS (combo / bank / kick) ---
	local function powerForDist(D, bounces)
		local v = math.sqrt(2 * Kref * D) + 3
		if bounces and bounces > 0 then v = v / (math.max(0.4, CAL.cushionRest) ^ bounces) end
		return clamp((v - CAL.powB) / math.max(0.1, CAL.powA), 6, 21)
	end
	-- combos/banks/kicks are O(myballs²·pockets) and explode on a crowded/just-broken
	-- rack (with no group assigned, isMy matches all 15 balls). They matter mainly in
	-- the endgame, so HARD-skip them when many target balls remain — this guard is what
	-- keeps a single findBest from freezing the client. (They are also off by default.)
	local myCount = 0
	for _b, _ in pairs(snap) do if _b ~= cb and isMy(_b.Name, rule) then myCount = myCount + 1 end end
	local deepOK = myCount <= (C.SEARCH.MAX_BALLS or 6)
	if C.SEARCH.COMBO and deepOK then
		for ballA, posA in pairs(snap) do
			if ballA ~= cb and isMy(ballA.Name, rule) then
				for ballB, posB in pairs(snap) do
					if ballB ~= cb and ballB ~= ballA and isMy(ballB.Name, rule) then
						for _, pp in ipairs(userPockets or {}) do
							local toP = Vector3.new(pp.X - posB.X, 0, pp.Z - posB.Z)
							if toP.Magnitude > 0.5 then
								local tpd = toP.Unit
								local ghostB = Vector3.new(posB.X - tpd.X*2*R, posB.Y, posB.Z - tpd.Z*2*R)
								local aToB = Vector3.new(ghostB.X - posA.X, 0, ghostB.Z - posA.Z)
								if aToB.Magnitude > 0.5 then
									local aToBdir = aToB.Unit
									local pPos = Vector3.new(pp.X, posB.Y, pp.Z)
									if pathClear(posA, ghostB, snap, ballA, ballB)
									   and pathClear(posB, pPos, snap, ballB, nil) then
										local dir = aimToSend(cp, posA, aToBdir)
										if dir and aToBdir:Dot(tpd) > 0.35 and dir:Dot(aToBdir) > 0.35 then
											local Dtot = toP.Magnitude + aToB.Magnitude
												+ (Vector3.new(posA.X-cp.X,0,posA.Z-cp.Z)).Magnitude
											tryShot(dir, powerForDist(Dtot, 0), "combo")
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	local function mirror(pt, axis, c)
		if axis == "x" then return Vector3.new(2*c - pt.X, pt.Y, pt.Z)
		else return Vector3.new(pt.X, pt.Y, 2*c - pt.Z) end
	end
	if userBounds and deepOK and (C.SEARCH.BANK or C.SEARCH.KICK) then
		local rails = { {"x", userBounds.xMin}, {"x", userBounds.xMax},
		                {"z", userBounds.zMin}, {"z", userBounds.zMax} }
		for ball, bp in pairs(snap) do
			if ball ~= cb and isMy(ball.Name, rule) then
				for _, pp in ipairs(userPockets or {}) do
					local pPos = Vector3.new(pp.X, bp.Y, pp.Z)
					if C.SEARCH.BANK then
						for _, rl in ipairs(rails) do
							local Pm = mirror(pPos, rl[1], rl[2])
							local aim = Vector3.new(Pm.X - bp.X, 0, Pm.Z - bp.Z)
							if aim.Magnitude > 0.5 then
								local dir = aimToSend(cp, bp, aim.Unit)
								if dir then tryShot(dir, powerForDist(aim.Magnitude, 1), "bank") end
							end
						end
					end
					if C.SEARCH.KICK then
						local toP = Vector3.new(pp.X - bp.X, 0, pp.Z - bp.Z)
						if toP.Magnitude > 0.5 then
							local tpd = toP.Unit
							local ghostA = Vector3.new(bp.X - tpd.X*2*R, bp.Y, bp.Z - tpd.Z*2*R)
							for _, rl in ipairs(rails) do
								local Gm = mirror(ghostA, rl[1], rl[2])
								local cd = Vector3.new(Gm.X - cp.X, 0, Gm.Z - cp.Z)
								if cd.Magnitude > 0.5 then
									local D = (Vector3.new(ghostA.X-cp.X,0,ghostA.Z-cp.Z)).Magnitude + toP.Magnitude
									tryShot(cd.Unit, powerForDist(D, 1), "kick")
								end
							end
						end
					end
				end
			end
		end
	end

	-- --- (2) BRUTE-FORCE GRID ---
	-- For combos / cushion-bounced shots the geometric step misses.
	for ang = 0, 359, C.BEST_ANGLE_STEP do
		local r = math.rad(ang)
		local d = Vector3.new(math.cos(r), 0, math.sin(r))
		for _,p in ipairs(C.BEST_POWERS) do
			tryShot(d, p, "grid")
		end
	end

	if best.score <= 0 then return best end

	-- --- (3) PROGRESSIVE REFINEMENT ---
	local function refine(rangeAng, stepAng, rangePow, stepPow)
		local ca, cp_ = best.angle, best.power
		local da = -rangeAng
		while da <= rangeAng + 1e-6 do
			local ang = ca + da
			local r = math.rad(ang)
			local d = Vector3.new(math.cos(r), 0, math.sin(r))
			local dp = -rangePow
			while dp <= rangePow + 1e-6 do
				tryShot(d, clamp(cp_ + dp, 1, 21), "refined")
				dp = dp + stepPow
			end
			da = da + stepAng
		end
	end
	-- Coarse refinement (always)
	refine(C.BEST_ANGLE_STEP, 0.5, 1.5, 0.5)
	-- Ultra-fine pass — used by F (Auto Fire) to extract sub-degree precision.
	if ultraPrecise then
		refine(1.0, 0.05, 0.5, 0.1)
	end

	-- ===== robustness re-rank (the fix for "best shot won't go in") =====
	-- The raw score ties every shot that pots one ball at +10, so the old
	-- power bias decided the winner — usually the least reliable hard shot.
	-- Instead, take the distinct high-scoring candidates and probe each by
	-- nudging the aim a little either way: the one that keeps potting under
	-- aim error is the one a human can actually make.
	if #cands > 0 then
		table.sort(cands, function(a,b) return a.score > b.score end)
		-- de-duplicate near-identical candidates (angle within 0.6°, power within 0.6)
		local distinct = {}
		for _,c in ipairs(cands) do
			local dup = false
			for _,d in ipairs(distinct) do
				local da = math.abs(((c.angle - d.angle + 180) % 360) - 180)
				if da < 0.6 and math.abs(c.power - d.power) < 0.6 then dup = true; break end
			end
			if not dup then distinct[#distinct+1] = c end
			if #distinct >= 6 then break end
		end
		local probes = {-1.2, -0.8, -0.4, 0.4, 0.8, 1.2}  -- degrees of aim error
		local bestC, bestCombined = nil, -math.huge
		for _,c in ipairs(distinct) do
			local ok, scr, foul = 0, 0, 0
			for _,deg in ipairs(probes) do
				local r = math.rad(deg)
				local cr, sr = math.cos(r), math.sin(r)
				local rd = Vector3.new(c.dir.X*cr - c.dir.Z*sr, 0, c.dir.X*sr + c.dir.Z*cr)
				local s2, pk2, sk2 = evalShot(cb, cp, rd, c.power, snap, rule)
				if s2 > 0 and sk2 and sk2 >= 1 then ok = ok + 1 end
				if s2 <= -20 then foul = foul + 1 end
				if pk2 then for _,k in pairs(pk2) do if k == "scratch" then scr = scr + 1; break end end end
			end
			local nP = #probes
			c.robust   = ok / nP
			c.makePct  = c.robust
			c.pScratch = scr / nP
			c.pFoul    = foul / nP
			-- Position play: where does the cue come to rest, and does that leave
			-- a clean look at my next ball(s)? A modest tie-breaker between pots.
			local finals2, pocket2 = {}, {}
			simulate(cb, cp, c.dir, shotPhysics(c.power), 0, snap, true, nil, pocket2, {}, finals2)
			local sunkSet = {}
			for ball,k in pairs(pocket2) do if k == "pocket" then sunkSet[ball] = true end end
			local sunkMy = 0
			for _b, _k in pairs(pocket2) do if _k == "pocket" and isMy(_b.Name, rule) then sunkMy = sunkMy + 1 end end
			local forceEight = (rule ~= "" and (myBallsLeft(snap, rule) - sunkMy) <= 0)
			c.leave = leaveScore(finals2[cb], snap, sunkSet, rule, forceEight)
			-- A fully aim-tolerant shot gains +12 — enough to outrank a fragile
			-- equal-score cut, while still respecting how many balls it pots; the
			-- leave score then breaks ties toward better position. Scratch/foul
			-- probabilities (from the aim-error probes) now dock the shot directly.
			c.ev = (c.sunk or 1) * c.robust * (1 - c.pScratch) * (1 + 0.15 * math.min((c.leave or 0), 3.6)/3.6)
			       - c.pScratch * 0.8 - c.pFoul * 0.6
			local combined = c.score + c.robust * 12 + (c.leave or 0) - c.pScratch * 6 - c.pFoul * 4
				+ (forceEight and (c.leave > 0 and 4 or -2) or 0)
			if combined > bestCombined then bestCombined = combined; bestC = c end
			c.combined = combined
		end
		if bestC then bestC.score = bestCombined; best = bestC end
		if bestC then
			local f2, pk2 = {}, {}
			simulate(cb, cp, bestC.dir, shotPhysics(bestC.power), 0, snap, true, nil, pk2, {}, f2)
			local cueAfter = f2[cb]
			if cueAfter then
				local snap2 = {}; for k, v in pairs(snap) do snap2[k] = v end
				for b, k in pairs(pk2) do if k == "pocket" then snap2[b] = nil end end
				snap2[cb] = cueAfter
				local nextMakeable = 0
				for ball, bp in pairs(snap2) do
					if ball ~= cb and isMy(ball.Name, rule) then
						for _, pp in ipairs(userPockets or {}) do
							if pathClear(bp, Vector3.new(pp.X, bp.Y, pp.Z), snap2, ball, nil)
							   and pathClear(cueAfter, bp, snap2, cb, ball) then
								nextMakeable = nextMakeable + 1; break
							end
						end
					end
				end
				bestC.next2 = nextMakeable
				bestC.score = bestC.score + math.min(nextMakeable, 2) * 0.6
			end
		end
		table.sort(distinct, function(a,b) return (a.combined or a.score) > (b.combined or b.score) end)
		bestState.list = {}
		for _,c in ipairs(distinct) do
			bestState.list[#bestState.list+1] = c
			if #bestState.list >= 6 then break end
		end
		bestState.selIdx = 1
	end
	return best
end
local function renderBest(best)
	-- Only ever show a best shot that actually pots one of MY balls (sunk >= 1).
	-- No pot found → hide entirely instead of pointing the cue at a cushion.
	if not bestState.enabled or not best
	   or (not best.safety and not best["break"] and (best.score <= 0 or (best.sunk or 0) < 1)) then
		clearBP(); if setHudInfo then setHudInfo(nil) end
		if makeTagLabel then makeTagLabel.Text = "" end
		if makeTagPart then makeTagPart.Transparency = 1 end
		if pocketMarker then pocketMarker.Transparency = 1 end
		_G.__POOL_PRED_BEST = nil; bestState.current = nil; return
	end
	local cb = userBalls:FindFirstChild("Cue"); if not cb then return end
	local segs, pocket, ctx, finals = {}, {}, {}, {}
	simulate(cb, cb.Position, best.dir, shotPhysics(best.power), 0, snapshotBalls(), true, segs, pocket, ctx, finals)
	-- Normal best-shot colour is shaded by make-%: high → gold, low → hot red, with
	-- a touch more transparency on weak shots. Safety keeps its dedicated orange.
	local isNormal = (not best.safety) and (not best["break"])
	local mp = best.makePct
	local tubeTransp = 0.05
	local col
	if best.safety then
		col = Color3.fromRGB(255,150,40)
	elseif isNormal and mp ~= nil then
		local t = clamp(mp, 0, 1)
		col = C.COL_BEST:Lerp(Color3.fromRGB(255,80,40), 1 - t)
		tubeTransp = clamp(0.05 + (1 - t) * 0.30, 0.05, 0.4)
	else
		col = C.COL_BEST
	end
	local idx = 0
	for _,s in ipairs(segs) do
		local show = s.isCue or pocket[s.ball] or not C.FILTER_NON_POCKETED
		if show then
			idx = idx + 1
			local p = getBP(idx, col)
			p.Transparency = tubeTransp
			setTube(p, s.p1, s.p2, 0.22)
		end
	end
	for i = idx+1, #bestState.parts do bestState.parts[i].Transparency = 1 end
	-- (a) make-% billboard + (c) target-pocket highlight (off the per-frame path).
	do
		-- locate the potted object ball (first non-cue ball flagged as a pot)
		local potInst
		for ball, k in pairs(pocket) do
			if k == "pocket" and ball ~= cb then potInst = ball; break end
		end
		if isNormal and mp ~= nil then
			local part, lbl = getMakeTag()
			local anchorPos = (potInst and finals[potInst]) or finals[cb]
				or (cb.Position + best.dir * 2)
			part.CFrame = CFrame.new(anchorPos.X, anchorPos.Y, anchorPos.Z)
			part.Transparency = 1   -- anchor stays invisible; only the label shows
			lbl.Text = string.format("%d%%", math.floor(clamp(mp, 0, 1) * 100))
			lbl.TextColor3 = (mp >= 0.7 and Color3.fromRGB(60,235,90))
				or (mp >= 0.4 and Color3.fromRGB(255,205,60))
				or Color3.fromRGB(255,70,70)
		else
			if makeTagLabel then makeTagLabel.Text = "" end
			if makeTagPart then makeTagPart.Transparency = 1 end
		end
		-- target-pocket neon marker
		local potPocket = potInst and finals[potInst] and endpointInPocket(finals[potInst])
		if potPocket then
			local pm = getPocketMarker()
			pm.Transparency = 0.2
			pm.CFrame = CFrame.new(potPocket.X, potPocket.Y, potPocket.Z)
		elseif pocketMarker then
			pocketMarker.Transparency = 1
		end
	end
	if setHudInfo then
		if best.safety then
			setHudInfo(string.format("SAFETY: Power %.0f · no clean pot", best.power))
		elseif best["break"] then
			setHudInfo(string.format("BREAK: Power %.0f", best.power))
		else
			setHudInfo(string.format("BEST: Power %.0f · Sink %d · %d%% make",
				best.power, best.sunk or 0, math.floor((best.makePct or 0) * 100)))
		end
	end
	bestState.current = best
	_G.__POOL_PRED_BEST = best
end
local function selectedShot()
	local L = bestState.list
	if not L or #L == 0 then return nil end
	local i = math.max(1, math.min(bestState.selIdx or 1, #L))
	return L[i]
end
local function renderSelected()
	local sel = selectedShot()
	if sel then renderBest(sel) end
	if refreshShotList then refreshShotList() end
end
local function recompute()
	aimOffsetDeg = 0
	lastBestHash = ballHashQuick()
	bestState.lastCompute = tick()
	local b = findBest()
	local sel = selectedShot()
	if sel then
		renderBest(sel)
	elseif b and (b["break"] or (b.score > 0 and (b.sunk or 0) >= 1)) then
		renderBest(b)
	else
		local alt = (bestState.safetyEnabled ~= false) and findSafety() or nil
		renderBest(alt or b)
	end
	if refreshShotList then refreshShotList() end
end
local autoBest = rsv.Heartbeat:Connect(function()
	local __ok, __e = pcall(function()
	if not bestState.enabled then return end
	if tick() - bestState.lastCompute < C.BEST_INTERVAL then return end
	local h = ballHashQuick()
	if bestState.current and h == lastBestHash then bestState.lastCompute = tick(); return end
	recompute()
	end)
	if not __ok then poolWarn(__e) end
end)

-- ============ ball-in-hand placement finder ============
-- After the opponent scratches (sinks the cue ball) you get to place the cue
-- ball anywhere. This searches good placements — for every (my-ball, pocket)
-- pair it positions the cue ball BEHIND the object ball on the pocket line, so
-- the resulting shot is dead straight — then keeps the placement whose shot is
-- most robust to aim error. Toggle with the PLACE hotkey (G).
local placeState = {enabled=false, parts={}, ghost=nil, lastCompute=0, current=nil}

local function getPlacePart(idx)
	if not placeState.parts[idx] then
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		p.Material = Enum.Material.Neon; p.Transparency = 0.05
		p.Parent = workspace; placeState.parts[idx] = p
	end
	local p = placeState.parts[idx]; p.Color = C.COL_PLACE; p.Transparency = 0.05; return p
end
local function clearPlaceParts() for _,p in ipairs(placeState.parts) do p.Transparency = 1 end end
local function getGhostBall()
	if placeState.ghost and placeState.ghost.Parent then return placeState.ghost end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Material = Enum.Material.ForceField; p.Color = C.COL_PLACE; p.Transparency = 0.25
	p.Size = Vector3.new(2*C.BALL_R, 2*C.BALL_R, 2*C.BALL_R); p.Parent = workspace
	placeState.ghost = p; return p
end

-- Evaluate one candidate cue-ball position firing along `dir`. Returns the best
-- power (with robustness) that pots a ball, or nil if none does.
local function evalPlacementCandidate(cb, cuePos, dir, snap, rule)
	local sc = {}; for k,v in pairs(snap) do sc[k]=v end; sc[cb] = cuePos
	local best = {score = -math.huge}
	for _,p in ipairs({10, 14, 18, 21}) do
		local s, pk, sk = evalShot(cb, cuePos, dir, p, sc, rule)
		if sk and sk > 0 and s > best.score then
			best = {score=s, power=p, dir=dir, pocketed=pk, sunk=sk}
		end
	end
	if best.score == -math.huge then return nil end
	-- aim-error robustness probe (same idea as findBest)
	local probes = {-1.2, -0.8, -0.4, 0.4, 0.8, 1.2}
	local ok = 0
	for _,deg in ipairs(probes) do
		local r = math.rad(deg)
		local crr, srr = math.cos(r), math.sin(r)
		local rd = Vector3.new(dir.X*crr - dir.Z*srr, 0, dir.X*srr + dir.Z*crr)
		local s2, _, sk2 = evalShot(cb, cuePos, rd, best.power, sc, rule)
		if s2 > 0 and sk2 and sk2 >= 1 then ok = ok + 1 end
	end
	best.robust = ok / #probes
	best.combined = best.score + best.robust * 12
	best.cuePos = cuePos
	return best
end

local function findBestPlacement()
	if not pickUserTable() or not userBounds then return nil end
	local cb = userBalls:FindFirstChild("Cue"); if not cb then return nil end
	local snap = snapshotBalls()
	local rule = guideMod.Rule or ""
	local R = C.BALL_R
	local best = nil
	local function consider(pos, dir)
		if pos.X < userBounds.xMin or pos.X > userBounds.xMax
		   or pos.Z < userBounds.zMin or pos.Z > userBounds.zMax then return end
		-- not overlapping another ball
		for ball, bp in pairs(snap) do
			if ball ~= cb and (Vector3.new(pos.X-bp.X, 0, pos.Z-bp.Z)).Magnitude < 2*R + 0.05 then return end
		end
		-- not sitting in a pocket
		for _,pp in ipairs(userPockets or {}) do
			if (Vector3.new(pos.X-pp.X, 0, pos.Z-pp.Z)).Magnitude < CAL.pocketR + R then return end
		end
		local c = evalPlacementCandidate(cb, pos, dir, snap, rule)
		if c and (not best or c.combined > best.combined) then best = c end
	end
	for ball, bp in pairs(snap) do
		if ball ~= cb and isMy(ball.Name, rule) then
			for _,pp in ipairs(userPockets or {}) do
				local toP = Vector3.new(pp.X-bp.X, 0, pp.Z-bp.Z)
				if toP.Magnitude > 0.5 then
					local tpd = toP.Unit
					-- place the cue behind the ball, on the pocket line → straight shot
					for _,dist in ipairs({2.0, 3.0, 4.5, 6.0}) do
						consider(Vector3.new(bp.X - tpd.X*dist, bp.Y, bp.Z - tpd.Z*dist), tpd)
					end
				end
			end
		end
	end
	return best
end

local function renderPlacement(best)
	clearPlaceParts()
	if not best then
		if placeState.ghost then placeState.ghost.Transparency = 1 end
		if setHudInfo then setHudInfo(nil) end
		return
	end
	local cb = userBalls:FindFirstChild("Cue"); if not cb then return end
	local g = getGhostBall(); g.Transparency = 0.25; g.CFrame = CFrame.new(best.cuePos)
	-- trajectory from the placement
	local sc = {}; local snap = snapshotBalls()
	for k,v in pairs(snap) do sc[k]=v end; sc[cb] = best.cuePos
	local segs, pocket = {}, {}
	simulate(cb, best.cuePos, best.dir, shotPhysics(best.power), 0, sc, true, segs, pocket, {}, nil)
	local idx = 0
	for _,s in ipairs(segs) do
		if s.isCue or pocket[s.ball] or not C.FILTER_NON_POCKETED then
			idx = idx + 1
			local p = getPlacePart(idx)
			setTube(p, s.p1, s.p2, 0.2)
		end
	end
	for i = idx+1, #placeState.parts do placeState.parts[i].Transparency = 1 end
	if setHudInfo then
		setHudInfo(string.format("PLACE CUE: Power %.0f · Sink %d · %.0f%% safe",
			best.power, best.sunk or 0, (best.robust or 0)*100))
	end
	placeState.current = best
end

local function recomputePlacement()
	placeState.lastCompute = tick()
	renderPlacement(findBestPlacement())
end
local autoPlace = rsv.Heartbeat:Connect(function()
	local __ok, __e = pcall(function()
	if not placeState.enabled then return end
	if tick() - placeState.lastCompute < C.PLACE_INTERVAL then return end
	local h = ballHashQuick()
	if placeState.current and h == lastPlaceHash then placeState.lastCompute = tick(); return end
	lastPlaceHash = h
	recomputePlacement()
	end)
	if not __ok then poolWarn(__e) end
end)

-- ============ auto-aim ============
local autoAimEnabled = false
_G.__POOL_PRED_AIM_ON = false
local AIM_FIELD_NAMES = {"AimNormal","AimDirection","ShotDirection","ShotNormal"}
local function applyAutoAim()
	local __ok, __e = pcall(function()
	if not autoAimEnabled then return end
	local best = _G.__POOL_PRED_BEST
	if not best or best.score <= 0 then return end
	if not (userBalls and userBalls.Parent) then return end
	local cb = userBalls:FindFirstChild("Cue")
	if not cb then return end
	local bdir = best.dir.Unit
	if aimOffsetDeg ~= 0 then
		local r = math.rad(aimOffsetDeg); local cr, sr = math.cos(r), math.sin(r)
		bdir = Vector3.new(bdir.X*cr - bdir.Z*sr, 0, bdir.X*sr + bdir.Z*cr)
	end
	local dir = bdir
	local ballPos = cb.Position
	-- Force the shot direction for BOTH input paths the game uses
	-- (GameRunnerClient): mouse fires FireServer(MouseNormal.Unit*-1, power) so
	-- travel = -MouseNormal; touch fires FireServer((TouchHit-CuePos).Unit,power)
	-- so travel = toward TouchHit. Setting both makes the ball go along `dir`.
	pcall(function() guideMod.MouseNormal = -dir end)
	pcall(function() guideMod.TouchHit = ballPos + dir * 10 end)
	for _,name in ipairs(AIM_FIELD_NAMES) do
		pcall(function()
			if typeof(guideMod[name]) == "Vector3" then guideMod[name] = -dir end
		end)
	end
	-- Visually lock the game's OWN cue (workspace.DefaultCue — the exact part the
	-- game renders, so there is no second cue) behind the ball along the aim.
	-- We run at RenderPriority.Last+1, after the game's own update, so our pose
	-- wins the frame.
	local stick = workspace:FindFirstChild("DefaultCue")
	if stick and stick:IsA("BasePart") then
		local back = ballPos - dir * 3 + Vector3.new(0, 0.2, 0)
		stick.CFrame = CFrame.lookAt(back, ballPos) * CFrame.Angles(math.pi, 0, 0)
	end
	-- Cache so the live predictor (getAimDir) immediately reflects the override.
	lastAimDir = dir; lastAimDirT = tick()
	end)
	if not __ok then poolWarn(__e) end
end
rsv:BindToRenderStep("PoolAimOverride", Enum.RenderPriority.Last.Value + 1, applyAutoAim)
local autoAimHB = nil  -- (removed redundant Heartbeat copy; RenderStep at Last+1 wins the frame)

-- ============ HUD ============
local hudVisible = true
local sg = Instance.new("ScreenGui")
sg.Name = "PoolCalHUD"; sg.ResetOnSpawn = false; sg.Parent = lp.PlayerGui
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 270, 0, 160); frame.Position = UDim2.new(0, 10, 0.5, -100)
frame.BackgroundColor3 = Color3.fromRGB(18,18,24); frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0; frame.Parent = sg
local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0,8); cor.Parent = frame
local strk = Instance.new("UIStroke"); strk.Thickness = 2; strk.Color = Color3.fromRGB(0,200,120); strk.Parent = frame
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0,10); pad.PaddingTop = UDim.new(0,8)
pad.PaddingRight = UDim.new(0,10); pad.Parent = frame
local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1; title.Size = UDim2.new(1,0,0,20)
title.Font = Enum.Font.GothamBold; title.TextScaled = true; title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(0,255,140); title.Text = "🎱 SELF-CALIBRATING PREDICTOR"; title.Parent = frame
-- Best-shot / ball-in-hand info shows here in the panel (gold), not on the table.
local infoLine = Instance.new("TextLabel")
infoLine.BackgroundTransparency = 1; infoLine.Position = UDim2.new(0,0,0,22); infoLine.Size = UDim2.new(1,0,0,18)
infoLine.Font = Enum.Font.GothamBold; infoLine.TextSize = 14; infoLine.TextXAlignment = Enum.TextXAlignment.Left
infoLine.TextColor3 = C.COL_BEST; infoLine.Text = ""; infoLine.Parent = frame
local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1; body.Position = UDim2.new(0,0,0,42); body.Size = UDim2.new(1,0,1,-42)
body.Font = Enum.Font.Code; body.TextSize = 13; body.TextYAlignment = Enum.TextYAlignment.Top
body.TextXAlignment = Enum.TextXAlignment.Left; body.TextColor3 = Color3.fromRGB(220,220,225)
body.Text = ""; body.Parent = frame
local aimLine = Instance.new("TextLabel")
aimLine.BackgroundTransparency = 1; aimLine.Position = UDim2.new(0,0,1,-20); aimLine.Size = UDim2.new(1,0,0,18)
aimLine.Font = Enum.Font.GothamBold; aimLine.TextSize = 13; aimLine.TextXAlignment = Enum.TextXAlignment.Left
aimLine.TextColor3 = Color3.fromRGB(180,180,180); aimLine.Text = "AUTO-AIM OFF"; aimLine.Parent = frame

-- Assign the forward-declared setter so renderBest/renderPlacement can post
-- their one-line summary into the panel. nil clears it.
setHudInfo = function(text)
	infoLine.Text = text or ""
end

-- ===== draggable + collapsible main HUD =====
-- Collapse button shrinks the panel to just its title bar; the title doubles as
-- a drag handle (touch-friendly, so it works on iOS). No render loop — purely
-- the GUI objects' own input events.
local hudOrigSize = frame.Size
local hudCollapsed = false
local collapseBtn = Instance.new("TextButton")
collapseBtn.Name = "Collapse"
collapseBtn.Size = UDim2.new(0,20,0,20); collapseBtn.Position = UDim2.new(1,-22,0,0)
collapseBtn.BackgroundColor3 = Color3.fromRGB(40,40,50); collapseBtn.BackgroundTransparency = 0.2
collapseBtn.BorderSizePixel = 0; collapseBtn.AutoButtonColor = true
collapseBtn.Font = Enum.Font.GothamBold; collapseBtn.TextSize = 16
collapseBtn.TextColor3 = Color3.fromRGB(230,230,235); collapseBtn.Text = "_"
collapseBtn.ZIndex = 3; collapseBtn.Parent = frame
local cbCor = Instance.new("UICorner"); cbCor.CornerRadius = UDim.new(0,4); cbCor.Parent = collapseBtn
collapseBtn.MouseButton1Click:Connect(function()
	hudCollapsed = not hudCollapsed
	if hudCollapsed then
		frame.Size = UDim2.new(0,270,0,28)
		infoLine.Visible = false; body.Visible = false; aimLine.Visible = false
	else
		frame.Size = hudOrigSize
		infoLine.Visible = true; body.Visible = true; aimLine.Visible = true
	end
end)

do  -- scope drag locals (keeps them out of the 200-local main-chunk budget)
local dragging, dragStart, startPos
title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true; dragStart = input.Position; startPos = frame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then dragging = false end
		end)
	end
end)
title.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - dragStart
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)
end

-- ============ ranked shot-list panel ============
-- A compact board listing the top candidate shots from findBest's re-rank.
-- [ ] cycle through them; clicking a row selects it. Sits just below the HUD.
local shotFrame = Instance.new("Frame")
shotFrame.Name = "ShotList"
shotFrame.Position = UDim2.new(0, 10, 0.5, 72); shotFrame.Size = UDim2.new(0, 270, 0, 150)
shotFrame.BackgroundColor3 = Color3.fromRGB(18,18,24); shotFrame.BackgroundTransparency = 0.15
shotFrame.BorderSizePixel = 0; shotFrame.Visible = false; shotFrame.Parent = sg
local sfcor = Instance.new("UICorner"); sfcor.CornerRadius = UDim.new(0,8); sfcor.Parent = shotFrame
local sfstr = Instance.new("UIStroke"); sfstr.Thickness = 1; sfstr.Color = Color3.fromRGB(70,70,85); sfstr.Parent = shotFrame
local sfTitle = Instance.new("TextLabel")
sfTitle.BackgroundTransparency = 1; sfTitle.Position = UDim2.new(0,8,0,4); sfTitle.Size = UDim2.new(1,-16,0,16)
sfTitle.Font = Enum.Font.GothamBold; sfTitle.TextSize = 12; sfTitle.TextXAlignment = Enum.TextXAlignment.Left
sfTitle.TextColor3 = Color3.fromRGB(150,150,160); sfTitle.Text = "SHOTS  ([ ] cycle)"; sfTitle.Parent = shotFrame
local shotRows = {}
for i = 1, 6 do
	local row = Instance.new("TextButton")
	row.Name = "Row"..i
	row.Position = UDim2.new(0,6,0,20 + (i-1)*21); row.Size = UDim2.new(1,-12,0,21)
	row.BackgroundColor3 = Color3.fromRGB(18,18,24); row.BackgroundTransparency = 0.2
	row.BorderSizePixel = 0; row.AutoButtonColor = false
	row.Font = Enum.Font.Code; row.TextSize = 13; row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextColor3 = Color3.fromRGB(220,220,225); row.Text = ""; row.Visible = false
	row.Parent = shotFrame
	local rcor = Instance.new("UICorner"); rcor.CornerRadius = UDim.new(0,4); rcor.Parent = row
	local idx = i
	row.MouseButton1Click:Connect(function()
		bestState.selIdx = idx
		renderSelected()
	end)
	shotRows[i] = row
end
refreshShotList = function()
	if (not bestState.enabled) or (#bestState.list == 0) then
		shotFrame.Visible = false; return
	end
	shotFrame.Visible = true
	for i = 1, 6 do
		local sh = bestState.list[i]
		local row = shotRows[i]
		if sh then
			row.Visible = true
			local tag = (sh.sunk and sh.sunk > 0) and ("pot"..sh.sunk) or (sh.safety and "safe" or "·")
			row.Text = string.format("#%d  %d%%  P%.0f  %s",
				i, math.floor((sh.makePct or 0)*100), sh.power, tag)
			if i == bestState.selIdx then
				row.BackgroundColor3 = C.COL_BEST; row.BackgroundTransparency = 0.05
				row.TextColor3 = Color3.fromRGB(20,20,20)
			else
				row.BackgroundColor3 = Color3.fromRGB(18,18,24); row.BackgroundTransparency = 0.2
				row.TextColor3 = Color3.fromRGB(220,220,225)
			end
		else
			row.Visible = false
		end
	end
end
refreshShotList()

local function refreshHUD()
	frame.Visible = hudVisible
	if not hudVisible then return end
	local avg = CAL.errN > 0 and CAL.errSum/CAL.errN or 0
	body.Text = string.format(
		"Shots learned : %d\nLast error    : %.2f st\nAvg  error    : %.2f st\nv0  = %.2f*p %+0.1f\nK   = %.2f %+0.3f*p\npocketR = %.2f  [%.2f..%.2f]\ncushion=%.2f  ball=%.2f",
		CAL.shots, CAL.lastErr, avg,
		CAL.powA, CAL.powB, CAL.kA, CAL.kB,
		CAL.pocketR, CAL.pocketLow, CAL.pocketHigh,
		CAL.cushionRest, CAL.ballRest)
	if autoAimEnabled then
		aimLine.Text = "🎯 AUTO-AIM ON"; aimLine.TextColor3 = Color3.fromRGB(0,255,90)
		strk.Color = Color3.fromRGB(0,255,90)
	else
		aimLine.Text = "OFF (B/V/F/G · C hud · K cal · X reset)"; aimLine.TextColor3 = Color3.fromRGB(160,160,160)
		strk.Color = Color3.fromRGB(0,200,120)
	end
end
refreshHUD()

-- ============ hotkey legend overlay (toggle: H / "?" button / MENU) ============
-- A static cheat-sheet of every control. Built once, parented to sg, hidden by
-- default; toggleLegend flips its visibility. No render loop.
local legendFrame = Instance.new("Frame")
legendFrame.Name = "Legend"
legendFrame.Position = UDim2.new(0,290,0,8); legendFrame.Size = UDim2.new(0,260,0,150)
legendFrame.AutomaticSize = Enum.AutomaticSize.Y
legendFrame.BackgroundColor3 = Color3.fromRGB(12,12,18); legendFrame.BackgroundTransparency = 0.08
legendFrame.BorderSizePixel = 0; legendFrame.Visible = false; legendFrame.Parent = sg
local lgCor = Instance.new("UICorner"); lgCor.CornerRadius = UDim.new(0,8); lgCor.Parent = legendFrame
local lgStr = Instance.new("UIStroke"); lgStr.Thickness = 2; lgStr.Color = C.COL_BEST; lgStr.Parent = legendFrame
local lgPad = Instance.new("UIPadding")
lgPad.PaddingLeft = UDim.new(0,12); lgPad.PaddingTop = UDim.new(0,10)
lgPad.PaddingRight = UDim.new(0,12); lgPad.PaddingBottom = UDim.new(0,10); lgPad.Parent = legendFrame
local lgList = Instance.new("UIListLayout")
lgList.SortOrder = Enum.SortOrder.LayoutOrder; lgList.Padding = UDim.new(0,4); lgList.Parent = legendFrame
local function legendLine(order, txt, col, bold)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Size = UDim2.new(1,0,0,16); t.AutomaticSize = Enum.AutomaticSize.Y
	t.LayoutOrder = order; t.TextWrapped = true
	t.Font = bold and Enum.Font.GothamBold or Enum.Font.Code
	t.TextSize = bold and 15 or 13; t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = col or Color3.fromRGB(210,220,228); t.Text = txt; t.Parent = legendFrame
	return t
end
legendLine(1, "CONTROLS (H)", C.COL_BEST, true)
legendLine(2, "B BestShot · V AutoAim · F AutoFire · G BallInHand")
legendLine(3, "K CalDetail · C HUD · X ResetCal · H Legend")
legendLine(4, "[ ] cycle shot  ·  , . aim nudge  ·  / reset aim")

toggleLegend = function() legendFrame.Visible = not legendFrame.Visible end

local legendBtn = Instance.new("TextButton")
legendBtn.Name = "LegendBtn"
legendBtn.Position = UDim2.new(1,-34,0,8); legendBtn.Size = UDim2.new(0,26,0,26)
legendBtn.BackgroundColor3 = Color3.fromRGB(40,40,50); legendBtn.BackgroundTransparency = 0.15
legendBtn.BorderSizePixel = 0; legendBtn.AutoButtonColor = true
legendBtn.Font = Enum.Font.GothamBold; legendBtn.TextSize = 16
legendBtn.TextColor3 = C.COL_BEST; legendBtn.Text = "?"; legendBtn.Parent = sg
local lgbCor = Instance.new("UICorner"); lgbCor.CornerRadius = UDim.new(0,6); lgbCor.Parent = legendBtn
local lgbStr = Instance.new("UIStroke"); lgbStr.Thickness = 1; lgbStr.Color = Color3.fromRGB(70,70,85); lgbStr.Parent = legendBtn
legendBtn.MouseButton1Click:Connect(function() toggleLegend() end)

-- Briefly reveal the legend on load so new users see the controls, then hide.
legendFrame.Visible = true
task.delay(6, function() if legendFrame and legendFrame.Parent then legendFrame.Visible = false end end)

-- ============ calibration detail panel (toggle: K) ============
-- A read-out of EVERYTHING that feeds the calibration: the learned model, how
-- many samples back each parameter, the last shot's raw measurements, and what
-- the FireServer hook captured. LASTSHOT is filled by finalizeShot below.
local LASTSHOT = {}
local calMenuVisible = false
local calFrame = Instance.new("Frame")
calFrame.Name = "CalDetail"
calFrame.Size = UDim2.new(0, 376, 0, 432); calFrame.Position = UDim2.new(0, 290, 0.5, -216)
calFrame.BackgroundColor3 = Color3.fromRGB(12,12,18); calFrame.BackgroundTransparency = 0.08
calFrame.BorderSizePixel = 0; calFrame.Visible = false; calFrame.Parent = sg
local ccor = Instance.new("UICorner"); ccor.CornerRadius = UDim.new(0,8); ccor.Parent = calFrame
local cstrk = Instance.new("UIStroke"); cstrk.Thickness = 2; cstrk.Color = C.COL_BEST; cstrk.Parent = calFrame
local cpad = Instance.new("UIPadding")
cpad.PaddingLeft = UDim.new(0,12); cpad.PaddingTop = UDim.new(0,10)
cpad.PaddingRight = UDim.new(0,12); cpad.Parent = calFrame
local cTitle = Instance.new("TextLabel")
cTitle.BackgroundTransparency = 1; cTitle.Size = UDim2.new(1,0,0,20)
cTitle.Font = Enum.Font.GothamBold; cTitle.TextSize = 15; cTitle.TextXAlignment = Enum.TextXAlignment.Left
cTitle.TextColor3 = C.COL_BEST; cTitle.Text = "🔬 CALIBRATION DETAIL  ·  K to close"; cTitle.Parent = calFrame
local cBody = Instance.new("TextLabel")
cBody.BackgroundTransparency = 1; cBody.Position = UDim2.new(0,0,0,28); cBody.Size = UDim2.new(1,0,1,-28)
cBody.Font = Enum.Font.Code; cBody.TextSize = 13; cBody.TextYAlignment = Enum.TextYAlignment.Top
cBody.TextXAlignment = Enum.TextXAlignment.Left; cBody.TextColor3 = Color3.fromRGB(210,220,228)
cBody.Text = ""; cBody.Parent = calFrame

local function refreshCalMenu()
	if not calMenuVisible then return end
	local v0_21 = CAL.powA*21 + CAL.powB
	local k_21  = clamp(CAL.kA + CAL.kB*21, 10, 90)
	local reach21 = (k_21 > 0) and (v0_21*v0_21/(2*k_21)) or 0
	local avg = CAL.errN > 0 and CAL.errSum/CAL.errN or 0
	local ls = LASTSHOT
	local cap = _G.__POOL_SHOTCAP
	local L = {}
	local function add(s) L[#L+1] = s end
	add("── LEARNED MODEL ──────────────")
	add(string.format(" v0(p)    = %.3f*p %+0.2f", CAL.powA, CAL.powB))
	add(string.format(" K(p)     = %.2f %+0.3f*p", CAL.kA, CAL.kB))
	add(string.format(" reach@21 = %.1f st  (v0=%.0f K=%.0f)", reach21, v0_21, k_21))
	add(string.format(" pocketR  = %.2f  [%.2f .. %.2f]", CAL.pocketR, CAL.pocketLow, CAL.pocketHigh))
	add(string.format(" cushion  = %.2f    ball = %.2f", CAL.cushionRest, CAL.ballRest))
	add("── SAMPLES BACKING EACH PARAM ──")
	add(string.format(" v0 fit   : N=%.1f  (only R2>0.85)", CAL.vN))
	add(string.format(" K fit    : N=%.1f   K-mean N=%.1f", CAL.kN, CAL.kfN))
	add(string.format(" cushion  : N=%.1f    ball N=%.1f", CAL.crN, CAL.brN))
	add("── LAST SHOT RECORDED ─────────")
	if ls.shot then
		add(string.format(" #%d  power=%.1f  via %s", ls.shot, ls.power or 0, ls.src or "?"))
		add(string.format(" launch = (%.2f, %.2f)", ls.lx or 0, ls.lz or 0))
		add(string.format(" v0 meas= %.1f  R2=%.2f  -> %s", ls.v0 or 0, ls.r2 or 0, ls.v0ok and "ACCEPTED" or "rejected"))
		add(string.format(" K  meas= %.1f  (%d ball samples)", ls.k or 0, ls.kn or 0))
		add(string.format(" pred err = %.2f st  (max %.2f)", ls.err or 0, ls.errMax or 0))
	else
		add(" (take a shot to record one)")
	end
	add("── SHOT CAPTURE (FireServer hook) ─")
	add(string.format(" hook installed = %s", _G.__POOL_SHOTHOOK_INSTALLED and "YES" or "no (UI fallback)"))
	if cap then
		add(string.format(" last fire: power %.2f, %.0fs ago", cap.power, os.clock()-cap.t))
	else
		add(" last fire: none captured yet")
	end
	add("── STATS ──────────────────────")
	add(string.format(" shots learned = %d", CAL.shots))
	add(string.format(" avg err = %.2f st   last = %.2f st", avg, CAL.lastErr))
	cBody.Text = table.concat(L, "\n")
end
local function toggleCalMenu()
	calMenuVisible = not calMenuVisible
	calFrame.Visible = calMenuVisible
	if calMenuVisible then refreshCalMenu() end
end
-- keep the panel live while open (throttled — it's just text)
local calRefreshT = 0
local calMenuConn = rsv.Heartbeat:Connect(function()
	local __ok, __e = pcall(function()
	if calMenuVisible and tick() - calRefreshT > 0.4 then calRefreshT = tick(); refreshCalMenu() end
	end)
	if not __ok then poolWarn(__e) end
end)

-- ============ recording-status dot (top centre) ============
-- A live tell-tale so you can SEE the calibrator working: grey IDLE, yellow
-- ARMED (rest captured, waiting for your shot), red ● REC (recording the shot),
-- cyan SAVED #N (a shot was learned), orange DROPPED (a detected shot was thrown
-- out — e.g. teleport/too-short — so you know why the count didn't move).
local recFrame = Instance.new("Frame")
recFrame.Size = UDim2.new(0, 158, 0, 28); recFrame.Position = UDim2.new(0.5, -79, 0, 8)
recFrame.BackgroundColor3 = Color3.fromRGB(15,15,20); recFrame.BackgroundTransparency = 0.25
recFrame.BorderSizePixel = 0; recFrame.Parent = sg
local rfcor = Instance.new("UICorner"); rfcor.CornerRadius = UDim.new(0,14); rfcor.Parent = recFrame
local rfstr = Instance.new("UIStroke"); rfstr.Thickness = 1; rfstr.Color = Color3.fromRGB(60,60,70); rfstr.Parent = recFrame
local recDot = Instance.new("Frame")
recDot.Size = UDim2.new(0,14,0,14); recDot.Position = UDim2.new(0,8,0.5,-7)
recDot.BackgroundColor3 = Color3.fromRGB(110,110,120); recDot.BorderSizePixel = 0; recDot.Parent = recFrame
local rdcor = Instance.new("UICorner"); rdcor.CornerRadius = UDim.new(1,0); rdcor.Parent = recDot
local recLbl = Instance.new("TextLabel")
recLbl.BackgroundTransparency = 1; recLbl.Position = UDim2.new(0,28,0,0); recLbl.Size = UDim2.new(1,-32,1,0)
recLbl.Font = Enum.Font.GothamBold; recLbl.TextSize = 13; recLbl.TextXAlignment = Enum.TextXAlignment.Left
recLbl.TextColor3 = Color3.fromRGB(180,180,185); recLbl.Text = "IDLE"; recLbl.Parent = recFrame

local recFlashUntil = 0
local function paintDot(c, txt, tc) recDot.BackgroundColor3 = c; recLbl.Text = txt; recLbl.TextColor3 = tc end
local function setRecDot(state, n)
	if state == "saved" then
		recFlashUntil = tick() + 1.4
		paintDot(Color3.fromRGB(0,220,255), "SAVED #"..tostring(n or 0), Color3.fromRGB(120,235,255)); return
	elseif state == "dropped" then
		recFlashUntil = tick() + 1.4
		paintDot(Color3.fromRGB(255,140,0), "DROPPED", Color3.fromRGB(255,185,95)); return
	end
	if tick() < recFlashUntil then return end   -- let a saved/dropped flash linger
	if state == "rec" then paintDot(Color3.fromRGB(255,60,60), "● REC SHOT", Color3.fromRGB(255,120,120))
	elseif state == "armed" then paintDot(Color3.fromRGB(255,210,60), "ARMED", Color3.fromRGB(255,225,140))
	else paintDot(Color3.fromRGB(110,110,120), "IDLE", Color3.fromRGB(170,170,175)) end
end

-- ============ shot observer + auto-calibration ============
-- Records every shot at the bound table: pre-shot layout, real per-ball
-- trajectories, then compares prediction vs reality and tunes CAL.

local OBS = {
	shot = nil,            -- active shot being recorded
	cuePrev = nil,         -- last cue position
	restCue = nil,         -- cue position while at rest
	restSnap = nil,        -- {inst=pos} captured while balls at rest
	restStable = 0,        -- seconds the cue has been still
	lastPower = nil,       -- {v=power, t=clock} captured while aiming
}

local function ballInstByName()
	local m = {}
	if userBalls then
		for _,b in ipairs(userBalls:GetChildren()) do
			if b:IsA("BasePart") and (tonumber(b.Name) or b.Name=="Cue") then m[b.Name]=b end
		end
	end
	return m
end

-- linear fit y = a*x + b over points {{x,y},...}; returns a,b,r2
local function linfit(pts)
	local n = #pts
	if n < 2 then return nil end
	local sx,sy,sxx,sxy = 0,0,0,0
	for _,p in ipairs(pts) do sx=sx+p[1]; sy=sy+p[2]; sxx=sxx+p[1]*p[1]; sxy=sxy+p[1]*p[2] end
	local den = n*sxx - sx*sx
	if math.abs(den) < 1e-9 then return nil end
	local a = (n*sxy - sx*sy)/den
	local b = (sy - a*sx)/n
	local mean = sy/n; local sst,ssr = 0,0
	for _,p in ipairs(pts) do
		local pr = a*p[1]+b
		ssr = ssr + (p[2]-pr)^2; sst = sst + (p[2]-mean)^2
	end
	return a, b, (sst > 0 and 1-ssr/sst or 0)
end

-- median of a list (sorted, ignores empty list)
local function median(list)
	if not list or #list == 0 then return nil end
	local c = {}
	for i,v in ipairs(list) do c[i] = v end
	table.sort(c)
	local n = #c
	if n % 2 == 1 then return c[math.ceil(n/2)] end
	return (c[n/2] + c[n/2 + 1]) * 0.5
end

local function robustPush(buf, v, cap)
	cap = cap or 25
	if #buf >= 6 then
		local m = median(buf)
		if m then
			local devs = {}
			for i,x in ipairs(buf) do devs[i] = math.abs(x - m) end
			local mad = median(devs) or 0
			if mad > 1e-6 and math.abs(v - m) > 3 * 1.4826 * mad then return m end
		end
	end
	buf[#buf+1] = v
	while #buf > cap do table.remove(buf, 1) end
	return median(buf)
end

local function calConfidence()
	local function conf(n, nFull, buf)
		local c = clamp(n / nFull, 0, 1)
		if buf and #buf >= 3 then
			local m = median(buf)
			if m and math.abs(m) > 1e-6 then
				local s = 0
				for _,x in ipairs(buf) do s = s + (x - m)^2 end
				local sd = math.sqrt(s / #buf)
				c = c * clamp(1 - sd/math.abs(m), 0.2, 1)
			end
		end
		return c
	end
	local v0c   = conf(CAL.vN, 12, CAL.vRatioBuf)
	local kc    = conf(#CAL.kfBuf, 12, CAL.kfBuf)
	local ballc = conf(#CAL.brBuf, 10, CAL.brBuf)
	local overall = clamp((v0c + kc + ballc)/3 * clamp(CAL.shots/15, 0.3, 1), 0, 1)
	return { v0 = v0c, k = kc, ball = ballc, overall = overall }
end

-- smoothed speed/direction series for a trajectory {{t,x,z},...}
-- returns sp[], cum[], dirx[], dirz[] for i=1..#tr-1
-- (kept for bounce/contact analysis where per-frame direction is needed)
local function buildSeries(tr, smoothWin)
	if not tr or #tr < 3 then return nil end
	smoothWin = smoothWin or 1
	local sp, cum, dirx, dirz = {}, {}, {}, {}
	local cd = 0
	for i = 1, #tr-1 do
		local dt = tr[i+1][1] - tr[i][1]
		if dt < 1e-4 then dt = 1e-4 end
		local dx, dz = tr[i+1][2]-tr[i][2], tr[i+1][3]-tr[i][3]
		local d = math.sqrt(dx*dx + dz*dz)
		sp[i] = d/dt; cd = cd + d; cum[i] = cd
		dirx[i] = d>0 and dx/d or 0; dirz[i] = d>0 and dz/d or 0
	end
	if smoothWin > 0 then
		local raw = sp; sp = {}
		for i = 1, #raw do
			local lo = math.max(1, i - smoothWin)
			local hi = math.min(#raw, i + smoothWin)
			local s, c = 0, 0
			for j = lo, hi do s = s + raw[j]; c = c + 1 end
			sp[i] = s / c
		end
	end
	return sp, cum, dirx, dirz
end

-- Position-vs-time quadratic fit for a straight ball run.
-- Network-replicated objects in Roblox arrive at ~20–30 Hz while Heartbeat
-- samples at 60 Hz, so per-frame Δd/Δt velocities are extremely noisy
-- (R²~0.35 on real data). Fitting position directly (R²~0.998 measured)
-- recovers v0 and the constant deceleration K exactly:
--   d(t) = v0·t − ½K·t²  →  v0 = a, K = −2b after fitting d = a·t + b·t²
-- samples: array of {tAbs, x, z}; tStart: absolute time of motion start;
-- p0: starting position (Vector3-like with X,Z); dir: unit launch direction
-- (Vector3-like). maxPerp: stop accepting samples once perpendicular
-- deviation from `dir` exceeds this (a contact ended the straight run).
local function fitConstDecel(samples, tStart, p0x, p0z, dx, dz, maxPerp)
	if not samples or #samples < 4 then return nil end
	maxPerp = maxPerp or 0.18
	local pts = {}
	-- normal of dir in 2D: (-dz, dx)
	local prevAlong, prevStep = nil, nil
	for _, s in ipairs(samples) do
		local rx, rz = s[2]-p0x, s[3]-p0z
		local along = rx*dx + rz*dz
		local perp  = math.abs(rx*(-dz) + rz*dx)
		if along < -0.05 then break end
		if perp > maxPerp then break end
		-- Head-on contact guard: a real friction run loses speed gradually, so
		-- the along-step shrinks only a little frame to frame. A sudden collapse
		-- (>55%) means the ball hit something head-on — stop before that frame so
		-- the impact isn't mistaken for friction (which would inflate K).
		if prevAlong then
			local step = along - prevAlong
			if step < -0.02 then break end
			-- Only trim on a sudden step collapse once we already have a usable
			-- window (≥4 pts) — otherwise short clean runs got cut to nothing.
			if #pts >= 4 and prevStep and prevStep > 0.05 and step < prevStep * 0.4 then break end
			prevStep = step
		end
		prevAlong = along
		pts[#pts+1] = {s[1] - tStart, along}
	end
	if #pts < 4 then return nil end
	-- Solve [Σt², Σt³; Σt³, Σt⁴]·[a;b] = [Σtd; Σt²d] (through-origin quadratic)
	local s2,s3,s4,std,st2d = 0,0,0,0,0
	for _,p in ipairs(pts) do
		local t,d = p[1], p[2]
		local t2 = t*t; local t3 = t2*t; local t4 = t3*t
		s2=s2+t2; s3=s3+t3; s4=s4+t4
		std=std+t*d; st2d=st2d+t2*d
	end
	local det = s2*s4 - s3*s3
	if math.abs(det) < 1e-9 then return nil end
	local a = (s4*std - s3*st2d) / det
	local b = (s2*st2d - s3*std) / det
	-- Compute R²
	local mean = 0; for _,p in ipairs(pts) do mean = mean + p[2] end; mean = mean/#pts
	local sst, ssr = 0, 0
	for _,p in ipairs(pts) do
		local pred = a*p[1] + b*p[1]*p[1]
		ssr = ssr + (p[2]-pred)^2
		sst = sst + (p[2]-mean)^2
	end
	local r2 = sst > 0 and 1 - ssr/sst or 0
	-- Valid only if v0>0 and decel>0
	if a <= 0 or b >= 0 then return nil end
	return a, -2*b, r2, #pts
end

local function nearestPocketDist(x, z)
	local best = math.huge
	for _,pp in ipairs(userPockets or {}) do
		local d = math.sqrt((x-pp.X)^2 + (z-pp.Z)^2)
		if d < best then best = d end
	end
	return best
end

-- Variance check: full-line regression on a cluster of nearly-identical
-- powers is degenerate (any slope through the cluster fits equally well).
-- Coefficient of variation < 0.25 → fall back to through-origin.
local function powerCV(N, Sx, Sxx)
	if N < 2 or Sx <= 0 then return 0 end
	local mean = Sx / N
	local var  = Sxx / N - mean*mean
	if var <= 0 then return 0 end
	return math.sqrt(var) / mean
end

-- recompute regressed parameters from accumulators
local function refitCal()
	-- v0 vs power
	if CAL.vN >= 1 and CAL.vSx > 0 then
		local cv = powerCV(CAL.vN, CAL.vSx, CAL.vSxx)
		local used = false
		if CAL.vN >= 4 and cv >= 0.25 then
			local den = CAL.vN*CAL.vSxx - CAL.vSx*CAL.vSx
			if math.abs(den) > 1e-6 then
				local a = (CAL.vN*CAL.vSxy - CAL.vSx*CAL.vSy)/den
				local b = (CAL.vSy - a*CAL.vSx)/CAL.vN
				if a > 0.3 then CAL.powA = clamp(a,0.3,15); CAL.powB = clamp(b,-30,40); used = true end
			end
		end
		-- Through-origin fallback (always physically reasonable: v0=0 at power=0)
		if not used then
			local mr = (#CAL.vRatioBuf > 0) and median(CAL.vRatioBuf) or (CAL.vSx > 0 and CAL.vSy/CAL.vSx or CAL.powA)
			CAL.powA = clamp(mr, 0.3, 15); CAL.powB = 0
		end
	end
	-- K (decel) vs power. Under real friction K is roughly constant, kB→0.
	local kmean = (#CAL.kfBuf > 0) and median(CAL.kfBuf) or (CAL.kfN > 0 and CAL.kfSum/CAL.kfN or 40.0)
	local used = false
	if CAL.kN >= 5 then
		local cv = powerCV(CAL.kN, CAL.kSx, CAL.kSxx)
		if cv >= 0.25 then
			local den = CAL.kN*CAL.kSxx - CAL.kSx*CAL.kSx
			if math.abs(den) > 1e-6 then
				local a = (CAL.kN*CAL.kSxy - CAL.kSx*CAL.kSy)/den
				local b = (CAL.kSy - a*CAL.kSx)/CAL.kN
				if b > 0.5 and b < 120 then
					CAL.kB = clamp(a,-3,3); CAL.kA = clamp(b,10,90); used = true
				end
			end
		end
	end
	if not used then CAL.kA = clamp(kmean,10,90); CAL.kB = 0 end
end

-- decay an online-regression accumulator group so that the most recent ~maxN
-- shots dominate the fit (otherwise early shots, taken with a default model,
-- pollute the regression forever).
local function decayAcc(maxN, fields, trigger)
	local t = trigger or CAL[fields[1]]
	if t > maxN then
		local f = (maxN - 1) / maxN
		for _,fld in ipairs(fields) do CAL[fld] = CAL[fld] * f end
	end
end

local function finalizeShot()
	local S = OBS.shot; OBS.shot = nil
	if not S or not S.preSnap or not S.cueInst then return end
	local cueTraj = S.traj[S.cueInst]
	if not cueTraj or #cueTraj < 4 then setRecDot("dropped"); return end

	-- ===== guard against teleports / re-racks =====
	local cueDist = 0
	for i = 2, #cueTraj do
		local step = math.sqrt((cueTraj[i][2]-cueTraj[i-1][2])^2 + (cueTraj[i][3]-cueTraj[i-1][3])^2)
		if step > 4.0 then setRecDot("dropped"); return end
		cueDist = cueDist + step
	end
	if cueDist < 0.5 or cueDist > 80 then setRecDot("dropped"); return end

	-- ===== launch direction =====
	-- Use the EXACT direction the game sent to the server when we captured it;
	-- otherwise infer it from the early cue trajectory (noisier).
	local p0 = S.preCue
	local launch
	if S.firedDir and S.firedDir.Magnitude > 0.5 then
		launch = S.firedDir.Unit
	else
		for i = 1, #cueTraj do
			local dx, dz = cueTraj[i][2]-p0.X, cueTraj[i][3]-p0.Z
			if dx*dx + dz*dz > 0.35*0.35 then launch = Vector3.new(dx,0,dz).Unit; break end
		end
	end
	if not launch then setRecDot("dropped"); return end

	-- ===== smoothed cue ball speed series =====
	local sp, cum, dirx, dirz = buildSeries(cueTraj, 1)
	if not sp then setRecDot("dropped"); return end
	local m = #sp

	-- ===== earliest object-ball contact (caps the cue's "straight run") =====
	local firstHitT, firstHit = math.huge, nil
	for inst, tr in pairs(S.traj) do
		if inst ~= S.cueInst and tr and #tr >= 1 then
			if tr[1][1] < firstHitT then firstHitT = tr[1][1]; firstHit = inst end
		end
	end

	-- ===== cushion bounces + runEnd =====
	local bounces = {}
	local runEnd = m
	if firstHit then
		for i = 1, m do
			if cueTraj[i] and cueTraj[i][1] >= firstHitT - 0.02 then
				runEnd = math.min(runEnd, math.max(2, i-1))
				break
			end
		end
	end
	for i = 1, m-1 do
		local dot = dirx[i]*dirx[i+1] + dirz[i]*dirz[i+1]
		if dot < 0.85 and sp[i] > 2 and sp[i+1] > 1 then
			local x, z = cueTraj[i+1][2], cueTraj[i+1][3]
			local nearRail = userBounds and (
				math.abs(x-userBounds.xMin) < 0.7 or math.abs(x-userBounds.xMax) < 0.7 or
				math.abs(z-userBounds.zMin) < 0.7 or math.abs(z-userBounds.zMax) < 0.7)
			if nearRail and sp[i] > 0 then
				-- Constant-decel bounce: v_before² = v_after_sample² + 2K·seg
				-- backwards from sample i toward bounce; symmetric for v_after.
				local K_guess = math.max(0.5, CAL.kA + CAL.kB * (S.power or 8))
				local prev = cum[i-1] or 0
				local seg = math.max(0.01, (cum[i+1] or cum[i]) - prev) * 0.5
				local vBeforeSq = sp[i]^2   - 2*K_guess*seg
				local vAfterSq  = sp[i+1]^2 + 2*K_guess*seg
				if vBeforeSq > 0.25 and vAfterSq > 0 then
					local vBefore = math.sqrt(vBeforeSq)
					local vAfter  = math.sqrt(vAfterSq)
					bounces[#bounces+1] = vAfter / vBefore
				end
			end
			if runEnd == m then runEnd = i end
		end
	end

	-- ===== robust v0 / K from PATH-LENGTH & TIME (integral, noise-resistant) =====
	-- Per-frame velocity fitting failed on network-replicated data (most shots
	-- gave R²=0 and the calibration starved). Instead use integral quantities
	-- that stay steady under jitter: a ball rolling freely under constant
	-- deceleration K covers total path L in moving-time T with
	--     v0 = 2L/T      and      K = 2L/T².
	-- This is exactly the "start → stop" data you described, measured along the
	-- recorded path. K comes from object balls (each launches once and rolls to
	-- a free stop); the cue's v0 comes from its pre-contact arc (before it sheds
	-- energy into the object ball).
	local function pathLen(tr, iEnd)
		local L = 0
		for i = 2, (iEnd or #tr) do
			L = L + math.sqrt((tr[i][2]-tr[i-1][2])^2 + (tr[i][3]-tr[i-1][3])^2)
		end
		return L
	end
	local function sankAt(x, z) return nearestPocketDist(x, z) < (CAL.pocketR + 0.15) end

	-- A clipped/teleport-tail trajectory shows a sudden speed jump frame-to-frame;
	-- such a run is not free-rolling friction and would corrupt K. Reject it.
	local function monotonicRoll(tr)
		local sp = buildSeries(tr, 1)
		if not sp or #sp < 3 then return true end
		for i = 2, #sp - 1 do
			if sp[i+1] > sp[i] * 1.5 + 1.0 then return false end
		end
		return true
	end

	-- K: from each object ball that launched and stopped on its own (not sunk).
	local kSamples = {}
	for inst, tr in pairs(S.traj) do
		if inst ~= S.cueInst and tr and #tr >= 4 then
			local L = pathLen(tr)
			local T = tr[#tr][1] - tr[1][1]
			local fin = tr[#tr]
			if L > 0.6 and T > 0.10 and not sankAt(fin[2], fin[3]) and monotonicRoll(tr) then
				kSamples[#kSamples+1] = clamp(2*L/(T*T), 10, 90)
			end
		end
	end
	local realK = median(kSamples)

	-- v0: from the cue's free-rolling pre-contact arc, decel known.
	local realV0
	local fitR2 = 0
	do
		local idxContact = #cueTraj
		if firstHit and firstHitT < math.huge then
			for i = 1, #cueTraj do
				if cueTraj[i][1] >= firstHitT then idxContact = math.max(2, i-1); break end
			end
		end
		local Kuse = realK or (CAL.kA + CAL.kB*(S.power or 12))
		local Lpre = pathLen(cueTraj, idxContact)
		local Tpre = cueTraj[idxContact][1] - cueTraj[1][1]
		if Tpre > 0.06 and Lpre > 0.4 then
			-- free decel over the pre-contact arc: d = v0·t − ½K·t² → v0 = d/t + ½K·t
			realV0 = clamp(Lpre/Tpre + 0.5*Kuse*Tpre, 1, 400)
		end
		-- Cue never hit anything and stopped freely → whole roll gives v0 and K.
		if not firstHit then
			local L = pathLen(cueTraj)
			local T = cueTraj[#cueTraj][1] - cueTraj[1][1]
			local fin = cueTraj[#cueTraj]
			if L > 0.6 and T > 0.10 and not sankAt(fin[2], fin[3]) then
				realV0 = clamp(2*L/T, 1, 400)
				if not realK then realK = clamp(2*L/(T*T), 10, 90) end
			end
		end
		if realV0 then
			local arc = {}
			for i = 1, idxContact do arc[i] = cueTraj[i] end
			local aFit, _kFit, r2Fit = fitConstDecel(arc, 0, p0.X, p0.Z, launch.X, launch.Z, 0.30)
			if r2Fit then
				fitR2 = r2Fit
				if r2Fit > 0.9 and aFit and aFit > 0 then realV0 = clamp(aFit, 1, 400) end
			end
		end
	end

	-- ===== real outcomes per ball =====
	local realFinal, moved = {}, {}
	for inst,_ in pairs(S.preSnap) do
		local tr = S.traj[inst]
		if tr and #tr > 0 then
			realFinal[inst] = Vector3.new(tr[#tr][2], (S.preSnap[inst]).Y, tr[#tr][3])
			local mv = (Vector3.new(tr[#tr][2],0,tr[#tr][3]) - Vector3.new(S.preSnap[inst].X,0,S.preSnap[inst].Z)).Magnitude
			if mv > 0.25 then moved[inst] = true end
		else
			realFinal[inst] = S.preSnap[inst]
		end
	end

	-- ===== calibration accumulators — only on shots we can attribute to ME =====
	-- With the FireServer hook installed, capFresh proves the shot was fired from
	-- this client. The opponent's replicated ball motion would otherwise feed the
	-- model wrong power/launch and rot the calibration; gate the whole accumulator
	-- block on S.trusted. refitCal/sanityCheck and the error stats stay outside.
	if S.trusted then
	CAL.tick = (CAL.tick or 0) + 1
	-- ===== pocketR bracket =====
	-- Leak the bracket back toward defaults every shot (~35-shot half-life) so
	-- it FORGETS old extremes. Without this the bracket is a monotonic ratchet
	-- (pocketLow only rises, pocketHigh only falls): a single fluke — a ball
	-- rolling past a pocket along a rail without dropping — would permanently
	-- tighten it, which is why the model rotted after dozens of games.
	CAL.pocketLow  = CAL.pocketLow  + (DEFAULT_CAL.pocketLow  - CAL.pocketLow)  * 0.02
	CAL.pocketHigh = CAL.pocketHigh + (DEFAULT_CAL.pocketHigh - CAL.pocketHigh) * 0.02
	for inst,_ in pairs(moved) do
		local tr = S.traj[inst]
		local closest = math.huge
		for _,pt in ipairs(tr) do
			local d = nearestPocketDist(pt[2], pt[3])
			if d < closest then closest = d end
		end
		local fin = realFinal[inst]
		local sank = nearestPocketDist(fin.X, fin.Z) < 0.6
		if closest < math.huge then
			if sank then
				if closest > CAL.pocketLow then CAL.pocketLow = math.min(closest, 1.0) end
			else
				if closest < CAL.pocketHigh then CAL.pocketHigh = math.max(closest, 0.25) end
			end
		end
	end
	if CAL.pocketHigh <= CAL.pocketLow then CAL.pocketHigh = CAL.pocketLow + 0.15 end
	CAL.pocketR = clamp((CAL.pocketLow + CAL.pocketHigh)/2, 0.25, 1.0)

	-- ===== ball restitution: median speeds + decel back-extrapolation =====
	-- Both va (cue speed) and vb (object ball speed) are measured a few frames
	-- AFTER contact, by which time both have already decelerated. Without
	-- compensation, the measured ballRest is biased low. We back-extrapolate
	-- under the constant-deceleration model: v_at_contact² = v_measured² + 2K·d_to_contact
	if firstHit and realV0 then
		local tr = S.traj[firstHit]
		local KforBack = math.max(0.5, realK or (CAL.kA + CAL.kB*(S.power or 8)))
		-- Object ball: speed estimates from {tr[i-1], tr[i+1]} centred at tr[i]
		local vbSamples = {}
		for i = 2, math.min(6, #tr-1) do
			local dt = tr[i+1][1] - tr[i-1][1]
			if dt > 1e-3 then
				local d = math.sqrt((tr[i+1][2]-tr[i-1][2])^2 + (tr[i+1][3]-tr[i-1][3])^2)
				local vm = d/dt
				-- back-extrapolate to t = first sample of object trajectory (≈ contact)
				local distFromContact = 0
				for j = 2, i do
					distFromContact = distFromContact + math.sqrt(
						(tr[j][2]-tr[j-1][2])^2 + (tr[j][3]-tr[j-1][3])^2)
				end
				local vsq = vm*vm + 2*KforBack*distFromContact
				vbSamples[#vbSamples+1] = math.sqrt(math.max(0, vsq))
			end
		end
		local vb = median(vbSamples)
		-- Cue speed just before contact: pick sample idx s.t. cueTraj[idx].t < firstHitT
		local idx = 1
		for i = 1, m do
			if cueTraj[i] and cueTraj[i][1] >= firstHitT - 0.05 then idx = math.max(1, i-1); break end
		end
		local vaSamples = {}
		for i = math.max(1, idx-2), math.min(m, idx) do
			if sp[i] then vaSamples[#vaSamples+1] = sp[i] end
		end
		local va = median(vaSamples) or realV0
		local cuePt = cueTraj[math.min(idx+1, #cueTraj)]
		local objPt = tr[1]
		if vb and cuePt then
			local cl = Vector3.new(objPt[2]-cuePt[2], 0, objPt[3]-cuePt[3])
			if cl.Magnitude > 0.05 then
				cl = cl.Unit
				local cueDir = Vector3.new(dirx[idx] or launch.X, 0, dirz[idx] or launch.Z)
				if cueDir.Magnitude > 0.1 then
					local along = cueDir.Unit:Dot(cl)
					if along > 0.25 and va*along > 1 then
						local e = clamp(2*vb/(va*along) - 1, 0.5, 1.0)
						CAL.brN = CAL.brN + 1; CAL.brSum = CAL.brSum + e
						CAL.ballRest = clamp(robustPush(CAL.brBuf, e, 25) or CAL.ballRest, 0.5, 1.0)
					end
				end
			end
		end
	end

	-- ===== cushion restitution =====
	for _,r in ipairs(bounces) do
		local rr = clamp(r, 0.3, 0.98)
		CAL.crN = CAL.crN + 1; CAL.crSum = CAL.crSum + rr
		robustPush(CAL.crBuf, rr, 25)
	end
	if #CAL.crBuf > 0 then CAL.cushionRest = clamp(median(CAL.crBuf), 0.3, 0.98) end

	-- ===== K accumulators =====
	if realK then
		CAL.kfN = CAL.kfN + 1; CAL.kfSum = CAL.kfSum + realK
		robustPush(CAL.kfBuf, realK, 25)
		if S.power then
			CAL.kN=CAL.kN+1; CAL.kSx=CAL.kSx+S.power; CAL.kSy=CAL.kSy+realK
			CAL.kSxx=CAL.kSxx+S.power*S.power; CAL.kSxy=CAL.kSxy+S.power*realK
		end
	end

	-- ===== v0 accumulators (gated by fit quality; the new t-vs-d fit
	--       typically gives R² > 0.99 on clean straight runs, so 0.85 is
	--       a strict yet realistic acceptance bar)
	if realV0 and S.power and fitR2 and fitR2 > 0.85 then
		CAL.vN=CAL.vN+1; CAL.vSx=CAL.vSx+S.power; CAL.vSy=CAL.vSy+realV0
		CAL.vSxx=CAL.vSxx+S.power*S.power; CAL.vSxy=CAL.vSxy+S.power*realV0
		robustPush(CAL.vRatioBuf, realV0 / S.power, 25)
	end

	-- ===== decay so the most recent ~40 shots dominate the regression =====
	decayAcc(40, {"vN","vSx","vSy","vSxx","vSxy"}, CAL.tick)
	decayAcc(40, {"kN","kSx","kSy","kSxx","kSxy"}, CAL.tick)
	decayAcc(40, {"kfN","kfSum"}, CAL.tick)
	decayAcc(40, {"crN","crSum"}, CAL.tick)
	decayAcc(40, {"brN","brSum"}, CAL.tick)
	end -- S.trusted

	refitCal()
	-- Safety net: if the regression has drifted into physically impossible
	-- values (a known long-run failure mode), snap back to defaults instead of
	-- predicting nonsense for the rest of the session.
	sanityCheckCal()

	-- ===== validate prediction vs reality (per-ball error) =====
	local predV0
	if S.power then predV0 = shotPhysics(S.power) else shotPhysics(8); predV0 = realV0 end
	local predFinals, predPocket = {}, {}
	simulate(S.cueInst, S.preCue, launch, predV0 or 1, 0, S.preSnap, true, nil, predPocket, {}, predFinals)

	local errSum, errCnt, errMax = 0, 0, 0
	for inst,_ in pairs(moved) do
		local pf = predFinals[inst] or S.preSnap[inst]
		local rf = realFinal[inst]
		if pf and rf then
			local d = (Vector3.new(pf.X,0,pf.Z) - Vector3.new(rf.X,0,rf.Z)).Magnitude
			errSum = errSum + d; errCnt = errCnt + 1
			if d > errMax then errMax = d end
		end
	end
	local err = errCnt > 0 and errSum/errCnt or 0

	if S.trusted then
		local pf = predFinals[S.cueInst]
		local rf = realFinal[S.cueInst]
		if pf and rf and launch then
			local eLong = (Vector3.new(pf.X - rf.X, 0, pf.Z - rf.Z)):Dot(launch)
			CAL.errEMA = (CAL.errEMA or 0) * 0.9 + eLong * 0.1
			if CAL.shots > 15 and math.abs(CAL.errEMA) > 0.4 then
				CAL.kBias = clamp((CAL.kBias or 0) + (CAL.errEMA > 0 and 0.25 or -0.25), -25, 25)
			end
		end
	end

	CAL.shots  = CAL.shots + 1
	CAL.lastErr = err
	CAL.errN = CAL.errN + 1; CAL.errSum = CAL.errSum + err
	if CAL.errN > 30 then CAL.errSum = CAL.errSum * (29/30); CAL.errN = 30 end
	saveCal()

	-- Snapshot the raw measurements for the K detail panel.
	LASTSHOT = {
		shot = CAL.shots, power = S.power, src = S.firedDir and "hook" or "UI",
		lx = launch.X, lz = launch.Z,
		v0 = realV0, r2 = fitR2,
		v0ok = (realV0 and S.power and fitR2 and fitR2 > 0.85) and true or false,
		k = realK, kn = #kSamples, err = err, errMax = errMax,
	}
	setRecDot("saved", CAL.shots)
	refreshHUD()
	refreshCalMenu()

	print(string.format(
		"[Cal] #%d  pow=%s  v0=%.1f (R2=%.2f)  K=%.2f (n=%d)  ball=%.2f  cushion=%.2f  pocketR=%.2f  err=%.2f st (max=%.2f)",
		CAL.shots,
		S.power and string.format("%.1f",S.power) or "?",
		realV0 or 0, fitR2 or 0,
		realK or 0, #kSamples,
		CAL.ballRest, CAL.cushionRest, CAL.pocketR,
		err, errMax))
	pcall(showReplay, predFinals, realFinal, moved)
end

-- A shot is "mine" iff the Power UI was visible on my client recently. The
-- game hides _GameInterface.Power on the local client while it's the
-- opponent's turn, so a recent visible reading is the cleanest signal that
-- the incoming cue-ball motion came from MY click. Without this filter the
-- opponent's shots would be recorded with whatever power I last aimed at,
-- poisoning the calibration.
local MINE_RECENT_S = 2.0   -- max age of last visible Power reading
local lastInvisibleT = 0    -- when the UI was last NOT visible

local obsConn = rsv.Heartbeat:Connect(function(dt)
	local __ok, __e = pcall(function()
	if not userBalls or not userBalls.Parent then OBS.shot = nil; return end
	local cue = userBalls:FindFirstChild("Cue")
	if not cue then return end
	local now = os.clock()
	local p = cue.Position

	-- track aim power while the player is aiming
	local pw, vis = readPower()
	if vis then OBS.lastPower = {v=pw, t=now}
	else lastInvisibleT = now end

	if not OBS.shot then
		-- update rest snapshot while everything is still
		if OBS.cuePrev and (p-OBS.cuePrev).Magnitude < 0.01 then
			OBS.restStable = OBS.restStable + dt
			if OBS.restStable > 0.12 then
				OBS.restCue  = p
				OBS.restSnap = snapshotBalls()
			end
		else
			OBS.restStable = 0
		end
		-- detect the start of a shot
		if OBS.restCue and (p-OBS.restCue).Magnitude > 0.12 and OBS.restSnap then
			-- Prefer the EXACT shot captured from the FireServer hook (it is
			-- unambiguously mine and carries true power + launch direction).
			local cap = _G.__POOL_SHOTCAP
			local capFresh = cap and (os.clock() - cap.t) < 1.2
			local mine = capFresh or (OBS.lastPower and (now - OBS.lastPower.t) < MINE_RECENT_S)
			if not mine then
				-- Not my turn — drop the rest snapshot and keep waiting.
				OBS.restCue = nil; OBS.restSnap = nil; OBS.restStable = 0
			else
				local S = {
					t0 = now, cueInst = cue, preCue = OBS.restCue,
					preSnap = OBS.restSnap, traj = {}, lastPos = {}, lastMoveT = now,
					power = capFresh and clamp(cap.power, 1, 21) or (OBS.lastPower and OBS.lastPower.v),
					firedDir = capFresh and Vector3.new(cap.dir.X, 0, cap.dir.Z) or nil,
					trusted = capFresh or (not _G.__POOL_SHOTHOOK_INSTALLED),
				}
				for inst,pos in pairs(S.preSnap) do
					S.traj[inst]  = {}
					S.lastPos[inst] = pos
				end
				OBS.shot = S
			end
		end
	else
		local S = OBS.shot
		local anyMove = false
		for _,b in ipairs(userBalls:GetChildren()) do
			if b:IsA("BasePart") and (tonumber(b.Name) or b.Name=="Cue") and S.traj[b] then
				local bp = b.Position
				local lpos = S.lastPos[b]
				if not lpos or math.abs(bp.X-lpos.X) > 1e-4 or math.abs(bp.Z-lpos.Z) > 1e-4 then
					local tr = S.traj[b]
					if #tr >= 2000 then
						tr[#tr] = {now - S.t0, bp.X, bp.Z}
					else
						tr[#tr + 1] = {now - S.t0, bp.X, bp.Z}
					end
					if lpos then anyMove = true end
					S.lastPos[b] = bp
				end
			end
		end
		if anyMove then S.lastMoveT = now end
		if now - S.lastMoveT > 0.55 and now - S.t0 > 0.35 then
			finalizeShot()
			OBS.restStable = 0; OBS.restCue = nil
		elseif now - S.t0 > 20 then
			OBS.shot = nil; OBS.restStable = 0; OBS.restCue = nil
		end
	end
	-- live recording-status dot
	if OBS.shot then setRecDot("rec")
	elseif OBS.restCue and OBS.restSnap then setRecDot("armed")
	else setRecDot("idle") end
	OBS.cuePrev = p
	end)
	if not __ok then poolWarn(__e) end
end)

-- ============ hotkeys ============
local function doToggleBest()
	bestState.enabled = not bestState.enabled
	if bestState.enabled then print("[BestShot] ON"); recompute()
	else print("[BestShot] OFF"); clearBP(); _G.__POOL_PRED_BEST = nil; if setHudInfo then setHudInfo(nil) end end
end
local function doToggleAim()
	autoAimEnabled = not autoAimEnabled
	_G.__POOL_PRED_AIM_ON = autoAimEnabled
	refreshHUD()
	print(autoAimEnabled and "[AutoAim] ON" or "[AutoAim] OFF")
	if autoAimEnabled then recompute() end
end
-- Is it actually my turn and is the table at rest? (don't fire on the opponent's
-- turn or while balls are still moving.)
local function canShootNow()
	local _, vis = readPower()
	if not vis then return false end
	if OBS.shot ~= nil then return false end
	return true
end
-- Fire `shot` like a human: small randomized delay, slight aim/power jitter inside
-- the shot's proven tolerance, re-validated so jitter never turns a make into a miss.
local function humanFire(shot)
	if not (shot and shot.dir and userComm) then print("[AutoFire] No good shot."); return end
	if not canShootNow() then print("[AutoFire] not my turn / table not at rest."); return end
	if not C.HUMANIZE.ENABLED then
		userComm:FireServer(shot.dir.Unit, shot.power); return
	end
	task.spawn(function()
		local H = C.HUMANIZE
		task.wait(clamp(H.MIN_DELAY + math.random()*(H.MAX_DELAY - H.MIN_DELAY), 0.15, 2.0))
		if not canShootNow() then return end
		local ang = (math.random()*2 - 1) * H.ANGLE_JITTER
		local pw  = clamp(shot.power + (math.random()*2 - 1) * H.POWER_JITTER, 1, 21)
		local r = math.rad(ang); local cr, sr = math.cos(r), math.sin(r)
		local jd = Vector3.new(shot.dir.X*cr - shot.dir.Z*sr, 0, shot.dir.X*sr + shot.dir.Z*cr)
		if jd.Magnitude > 1e-4 then jd = jd.Unit else jd = shot.dir.Unit end
		-- re-validate the jittered shot; if it no longer pots, fire the exact one
		local cb = userBalls and userBalls:FindFirstChild("Cue")
		if cb and not shot.safety and not shot["break"] then
			local s2, _, sk2 = evalShot(cb, cb.Position, jd, pw, snapshotBalls(), guideMod.Rule or "")
			if not (s2 > 0 and sk2 and sk2 >= 1) then jd = shot.dir.Unit; pw = shot.power end
		end
		userComm:FireServer(jd, pw)
		print(string.format("[AutoFire] fired pow=%.2f jitter=%.2f°", pw, ang))
	end)
end
local function doFire()
	bestState.lastCompute = tick()
	local b = _G.__POOL_PRED_BEST
	if not b then recompute(); b = _G.__POOL_PRED_BEST end
	humanFire(b)
end
local function doTogglePlace()
	placeState.enabled = not placeState.enabled
	if placeState.enabled then
		print("[Place] Ball-in-hand finder ON")
		recomputePlacement()
	else
		print("[Place] OFF"); renderPlacement(nil)
	end
	refreshHUD()
end
local function doToggleHud()
	hudVisible = not hudVisible
	refreshHUD()
end
local function doResetCal()
	cloneDefaultCalInto(CAL)
	saveCal(true); refreshHUD()
	print("[Cal] calibration reset to defaults")
end
local function doCycle(delta)
	local n = #bestState.list
	if n == 0 then return end
	bestState.selIdx = ((bestState.selIdx - 1 + delta) % n) + 1
	renderSelected()
end
local function doAimNudge(d)
	aimOffsetDeg = math.clamp(aimOffsetDeg + d, -15, 15)
	if aimLine then aimLine.Text = string.format("AIM %+.2f°  (, . nudge · / reset)", aimOffsetDeg) end
end
local hk = uis.InputBegan:Connect(function(input, proc)
	if proc then return end
	local kc = input.KeyCode
	if kc == C.BEST_HOTKEY then doToggleBest()
	elseif kc == C.AUTO_AIM_HOTKEY then doToggleAim()
	elseif kc == C.AUTO_FIRE_HOTKEY then doFire()
	elseif kc == C.PLACE_HOTKEY then doTogglePlace()
	elseif kc == C.CAL_MENU_HOTKEY then toggleCalMenu()
	elseif kc == C.HUD_HOTKEY then doToggleHud()
	elseif kc == C.LEGEND_HOTKEY then toggleLegend()
	elseif kc == C.RESET_HOTKEY then doResetCal()
	elseif kc == C.CYCLE_PREV_HOTKEY then doCycle(-1)
	elseif kc == C.CYCLE_NEXT_HOTKEY then doCycle(1)
	elseif kc == C.AIM_NUDGE_L_HOTKEY then doAimNudge(-C.AIM_STEP)
	elseif kc == C.AIM_NUDGE_R_HOTKEY then doAimNudge(C.AIM_STEP)
	elseif kc == C.AIM_RESET_HOTKEY then aimOffsetDeg = 0; if aimLine then aimLine.Text = "AIM 0.00°" end
	end
end)

-- ============ mobile tap bar ============
-- Big touch targets (>=44px tall) along the bottom centre, mirroring the
-- keyboard hotkeys so the script is fully usable on iOS. Static buttons — every
-- click body is pcall-wrapped so a transient nil never breaks the bar.
do  -- scope tap-bar construction locals out of the 200-local main-chunk budget
local tapBar = Instance.new("Frame")
tapBar.Name = "TapBar"
tapBar.AnchorPoint = Vector2.new(0.5,1)
tapBar.Position = UDim2.new(0.5,0,1,-8); tapBar.Size = UDim2.new(0,0,0,44)
tapBar.AutomaticSize = Enum.AutomaticSize.X
tapBar.BackgroundColor3 = Color3.fromRGB(15,15,20); tapBar.BackgroundTransparency = 0.25
tapBar.BorderSizePixel = 0; tapBar.Parent = sg
local tbCor = Instance.new("UICorner"); tbCor.CornerRadius = UDim.new(0,10); tbCor.Parent = tapBar
local tbStr = Instance.new("UIStroke"); tbStr.Thickness = 1; tbStr.Color = Color3.fromRGB(60,60,70); tbStr.Parent = tapBar
local tbPad = Instance.new("UIPadding")
tbPad.PaddingLeft = UDim.new(0,6); tbPad.PaddingRight = UDim.new(0,6)
tbPad.PaddingTop = UDim.new(0,0); tbPad.PaddingBottom = UDim.new(0,0); tbPad.Parent = tapBar
local tbList = Instance.new("UIListLayout")
tbList.FillDirection = Enum.FillDirection.Horizontal
tbList.HorizontalAlignment = Enum.HorizontalAlignment.Center
tbList.VerticalAlignment = Enum.VerticalAlignment.Center
tbList.SortOrder = Enum.SortOrder.LayoutOrder; tbList.Padding = UDim.new(0,6); tbList.Parent = tapBar
local function tapBtn(order, label, cb)
	local b = Instance.new("TextButton")
	b.Name = label; b.LayoutOrder = order
	b.Size = UDim2.new(0,58,0,44)
	b.BackgroundColor3 = Color3.fromRGB(35,35,45); b.BackgroundTransparency = 0.05
	b.BorderSizePixel = 0; b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.TextColor3 = Color3.fromRGB(230,230,235)
	b.Text = label; b.Parent = tapBar
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,8); bc.Parent = b
	b.MouseButton1Click:Connect(function() pcall(cb) end)
	return b
end
tapBtn(1, "AIM",  doToggleAim)
tapBtn(2, "FIRE", doFire)
tapBtn(3, "BEST", doToggleBest)
tapBtn(4, "HAND", doTogglePlace)
tapBtn(5, "SAFE", function()
	if _G.__POOL_PREDICTOR and _G.__POOL_PREDICTOR.toggleSafety then
		_G.__POOL_PREDICTOR.toggleSafety()
	end
end)
tapBtn(6, "◀", function() doCycle(-1) end)
tapBtn(7, "▶", function() doCycle(1) end)
tapBtn(8, "MENU", toggleLegend)
end  -- tap-bar scope

-- ============ public handle ============
_G.__POOL_PREDICTOR = {
	cleanup = function()
		if predConn then predConn:Disconnect() end
		if autoBest then autoBest:Disconnect() end
		if autoPlace then autoPlace:Disconnect() end
		if autoAimHB then autoAimHB:Disconnect() end
		if obsConn then obsConn:Disconnect() end
		if calMenuConn then calMenuConn:Disconnect() end
		if gameStartConn then gameStartConn:Disconnect() end
		if hk then hk:Disconnect() end
		pcall(rsv.UnbindFromRenderStep, rsv, "PoolAimOverride")
		if sg then sg:Destroy() end
		for _,p in ipairs(pool) do p:Destroy() end
		for _,p in ipairs(bestState.parts) do p:Destroy() end
		if bestState.label then bestState.label:Destroy() end
		for _,p in ipairs(placeState.parts) do p:Destroy() end
		if placeState.ghost then placeState.ghost:Destroy() end
		if placeState.label then placeState.label:Destroy() end
		for _,h in pairs(hl) do if h.Parent then h:Destroy() end end
		-- on-table polish parts live under workspace, so sg:Destroy() misses them
		if makeTagPart then makeTagPart:Destroy() end
		if pocketMarker then pocketMarker:Destroy() end
		for _,p in ipairs(replayParts) do if p then p:Destroy() end end
		_G.__POOL_COMM = nil
		_G.__POOL_SHOTCAP = nil
		_G.__POOL_PRED_BEST = nil
		_G.__POOL_PRED_AIM_ON = false
		_G.__POOL_PREDICTOR = nil
		print("[Pred v12] Cleaned up.")
	end,
	config = C,
	cal = CAL,
	saveCal = saveCal,
	resetCal = function()
		cloneDefaultCalInto(CAL)
		saveCal(true); refreshHUD(); print("[Cal] reset")
	end,
	recomputeBest = recompute,
	toggleSafety = function() bestState.safetyEnabled = not bestState.safetyEnabled; recompute() end,
	cycleShot = function(delta)
		local n = #bestState.list
		if n == 0 then return end
		bestState.selIdx = ((bestState.selIdx - 1 + (delta or 1)) % n) + 1
		renderSelected()
	end,
	shotList = function() return bestState.list end,
	confidence = calConfidence,
	actions = { best = doToggleBest, aim = doToggleAim, fire = doFire, place = doTogglePlace, cal = toggleCalMenu, hud = doToggleHud, reset = doResetCal },
}

recompute()
print(string.format("[Pred v12] Self-calibrating predictor loaded. Shots learned so far: %d. Avg error: %.2f st.",
	CAL.shots, CAL.errN > 0 and CAL.errSum/CAL.errN or 0))
print("[Pred v12] B=BestShot  V=AutoAim  F=AutoFire  G=BallInHand  |  [ ]=cycle shot  , .=aim-nudge  /=reset-aim  |  K=CalDetail  C=HUD  H=Legend  X=reset  (tap bar on mobile)")
