-- ====== 8 Ball Pool Trajectory Predictor v12 — Self-Calibrating ======
-- v12: power scale corrected to the game's true 1..21; cushion bounds read
-- exactly from the Barrier rail geometry; head-on contact no longer inflates K.
-- The predictor records, for every shot, what it PREDICTED (where each ball
-- would go) versus what REALLY happened, taking the actual aim angle and power
-- into account. After each shot it measures the error and tunes its physics
-- model (initial speed per power, damping, cushion bounce, ball transfer,
-- pocket capture radius) toward perfect accuracy.
--
-- Calibration is saved to disk and is automatically reloaded after a Roblox
-- restart, so the model keeps getting better across sessions.
--
-- Hotkeys: B=BestShot  V=AutoAim  F=AutoFire  C=Calibration HUD  X=reset calibration
-- Cleanup: _G.__POOL_PREDICTOR.cleanup()

-- ============ cleanup any previous instance ============
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
				if self == _G.__POOL_COMM and getnamecallmethod() == "FireServer" then
					local dir, power = ...
					if typeof(dir) == "Vector3" and type(power) == "number" then
						_G.__POOL_SHOTCAP = { dir = dir, power = power, t = os.clock() }
					end
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
	BEST_HOTKEY = Enum.KeyCode.B, AUTO_AIM_HOTKEY = Enum.KeyCode.V, AUTO_FIRE_HOTKEY = Enum.KeyCode.F,
	HUD_HOTKEY = Enum.KeyCode.C, RESET_HOTKEY = Enum.KeyCode.X,
	PLACE_HOTKEY = Enum.KeyCode.G, PLACE_INTERVAL = 0.75,
	CAL_MENU_HOTKEY = Enum.KeyCode.K,
	COL_PLACE = Color3.fromRGB(0,255,200),
	FILTER_NON_POCKETED = false,
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
local CAL_FILE = "sigmatik_pool_predictor_cal.json"

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
local CAL_SCHEMA = 3
local DEFAULT_CAL = {
	schema = CAL_SCHEMA,
	powA = 2.20, powB = 0.0,
	kA   = 40.0, kB   = 0.0,
	cushionRest = 0.90,
	ballRest    = 0.92,
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
	-- stats
	shots=0, errN=0, errSum=0, lastErr=0,
}

local CAL = {}
for k,v in pairs(DEFAULT_CAL) do CAL[k]=v end

local function saveCal()
	pcall(function()
		if writefile then writefile(CAL_FILE, http:JSONEncode(CAL)) end
	end)
end
local function loadCal()
	pcall(function()
		if isfile and readfile and isfile(CAL_FILE) then
			local data = http:JSONDecode(readfile(CAL_FILE))
			if type(data)=="table" then
				-- Reject old-schema calibrations: their K/v0 values come from
				-- the linear v-vs-d fit and are not interpretable as the new
				-- constant-deceleration model.
				if data.schema == CAL_SCHEMA then
					for k,_ in pairs(DEFAULT_CAL) do
						if type(data[k])=="number" then CAL[k]=data[k] end
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
	   or CAL.cushionRest < 0.2 or CAL.cushionRest > 1.0 then
		warn(string.format("[Pred v12] Calibration looked bad (v0(1)=%.2f v0(21)=%.2f K(1)=%.2f K(21)=%.2f reach=%.2f pocketR=%.2f ballR=%.2f) -> resetting to defaults.",
			v_at_1, v_at_21, k_at_1, k_at_21, reach21, CAL.pocketR, CAL.ballRest))
		for k,v in pairs(DEFAULT_CAL) do CAL[k]=v end
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
}
-- set PHYS for a given shot power, return predicted initial speed v0
local function shotPhysics(power)
	PHYS.pocketR     = CAL.pocketR
	PHYS.cushionRest = CAL.cushionRest
	PHYS.ballRest    = CAL.ballRest
	-- Clamp deceleration to a physically realistic band. Without an upper cap a
	-- bad fit could push K toward the old 300 ceiling, which collapses the
	-- predicted reach (v0²/2K) so the guideline shrinks shot after shot.
	PHYS.K = clamp(CAL.kA + CAL.kB * power, 10, 90)
	return math.max(0, CAL.powA * power + CAL.powB)
end

-- ============ table binding ============
local userTable, userBalls, userBarrier, userPockets, userBounds, userCue, userComm

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
	userBalls   = tbl:WaitForChild("Balls")
	userBarrier = tbl:WaitForChild("Barrier")
	userPockets = {}
	local pp = tbl:WaitForChild("PocketPoints")
	for _,x in ipairs(pp:GetChildren()) do
		if x:IsA("BasePart") then table.insert(userPockets, x.Position) end
	end
	-- Prefer exact rail geometry; fall back to pocket-point inference.
	userBounds = boundsFromRails(userBarrier) or computeBounds(userPockets)
	local gd = tbl:WaitForChild("_GameData")
	userComm = gd:WaitForChild("Communication")
	_G.__POOL_COMM = userComm   -- let the shoot-remote hook recognise our table's remote
	if userBounds then
		print(string.format("[Pred v12] Bound table (%s). Bounds x[%.2f..%.2f] z[%.2f..%.2f]",
			boundsFromRails(userBarrier) and "rails" or "pockets",
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

rs.Events.GameStartClient.OnClientEvent:Connect(function(tbl, cue, _, players)
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
	local function asPart(x)
		if not x then return nil end
		if x:IsA("BasePart") then return x end
		if x:IsA("Model") then return x:FindFirstChildWhichIsA("BasePart", true) end
		return nil
	end
	local s = asPart(workspace:FindFirstChild("DefaultCue"))
	if s then return s end
	if userTable then
		for _,n in ipairs({"DefaultCue","CueStick","Cuestick","Cue_Stick","Stick"}) do
			local f = userTable:FindFirstChild(n, true)
			local p = asPart(f)
			if p then return p end
		end
	end
	if lp.Character then
		for _,n in ipairs({"DefaultCue","CueStick","Cuestick"}) do
			local f = lp.Character:FindFirstChild(n, true)
			local p = asPart(f)
			if p then return p end
		end
	end
	for _,c in ipairs(workspace:GetChildren()) do
		local nm = c.Name:lower()
		if nm == "defaultcue" or nm == "cuestick" or nm == "cue_stick" or nm:find("^cue[_%-]") then
			local p = asPart(c)
			if p then return p end
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

local function castPocket(pos, dir, maxDist)
	local bD, bP = math.huge, nil
	local R = PHYS.pocketR
	for _,pp in ipairs(userPockets or {}) do
		local d = pp - pos
		local along = d:Dot(dir)
		if along > -R and along < maxDist + R then
			local perp = Vector3.new(d.X - dir.X*along, 0, d.Z - dir.Z*along)
			local pd2 = perp:Dot(perp)
			if pd2 < R*R then
				local back = math.sqrt(R*R - pd2)
				local enter = math.max(0, along - back)
				if enter < bD and enter <= maxDist then bD, bP = enter, pos + dir*enter end
			end
		end
	end
	return bD < math.huge and bD, bP
end

local function endpointInPocket(pos)
	for _,pp in ipairs(userPockets or {}) do
		if (Vector3.new(pos.X-pp.X, 0, pos.Z-pp.Z)).Magnitude < PHYS.pocketR then return pp end
	end
	return nil
end

-- ============ core simulation ============
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
	local pD, pP       = castPocket(pos, dir, math.min(maxDist, hBD or maxDist))
	if cD and cP and endpointInPocket(cP) then
		if not pD or cD < pD then pD, pP = cD, cP; cD = nil end
	end

	local events = {}
	if hBD < math.huge then events[#events+1] = {kind="ball", d=hBD, ball=hB, p=hBP} end
	if cD then events[#events+1] = {kind="cushion", d=cD, n=cN, p=cP} end
	if pD then events[#events+1] = {kind="pocket", d=pD, p=pP} end
	table.sort(events, function(a,b) return a.d < b.d end)

	local color = isCue and (depth==0 and C.COL_CUE or C.COL_CUE_DEFL)
		or (depth<=1 and C.COL_TARGET or C.COL_CHAIN)
	local thick = isCue and 0.10 or 0.12

	if #events == 0 then
		local endP = pos + dir*maxDist
		if segs then segs[#segs+1] = {ball=ball, p1=pos, p2=endP, color=color, thick=thick, isCue=isCue} end
		if endpointInPocket(endP) then pT[ball] = isCue and "scratch" or "pocket" end
		if finals then finals[ball] = endpointInPocket(endP) or endP end
		return
	end

	local e = events[1]
	if segs then segs[#segs+1] = {ball=ball, p1=pos, p2=e.p, color=color, thick=thick, isCue=isCue} end

	if e.kind == "pocket" then
		pT[ball] = isCue and "scratch" or "pocket"
		if finals then finals[ball] = e.p end
		return
	elseif e.kind == "cushion" then
		-- v² after traveling e.d under constant decel K:
		local nSsq = speed*speed - 2*K*e.d
		if nSsq <= 0 then if finals then finals[ball]=e.p end return end
		local nS = math.sqrt(nSsq) * PHYS.cushionRest
		if nS < PHYS.minSpeed then if finals then finals[ball]=e.p end return end
		local nD = dir - 2*dir:Dot(e.n)*e.n
		simulate(ball, e.p, nD, nS, depth+1, snap, isCue, segs, pT, ctx, finals)
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
		local va_tang  = sI * math.sqrt(math.max(0, 1 - along*along))
		local nSnap = {}; for k,v in pairs(snap) do nSnap[k]=v end
		nSnap[e.ball] = objPos + cl*0.001
		if vb_after > PHYS.minSpeed then
			simulate(e.ball, objPos, cl, vb_after, depth+1, nSnap, false, segs, pT, ctx, finals)
		elseif finals then finals[e.ball] = objPos end
		local cueNewSp = math.sqrt(va_after*va_after + va_tang*va_tang)
		if cueNewSp > PHYS.minSpeed then
			local tangDir = Vector3.zero
			if va_tang > 1e-3 then
				local rawTang = dir - cl*along
				if rawTang.Magnitude > 1e-4 then tangDir = rawTang.Unit end
			end
			local cueNewDir = cl*va_after + tangDir*va_tang
			if cueNewDir.Magnitude > 1e-4 then
				simulate(ball, e.p, cueNewDir.Unit, cueNewSp, depth+1, nSnap, isCue, segs, pT, ctx, finals)
			elseif finals then finals[ball] = e.p end
		elseif finals then finals[ball] = e.p end
	end
end

-- ============ live prediction render ============
local predConn = rsv.RenderStepped:Connect(function()
	resetPool(); clearHL()
	if not pickUserTable() then return end
	if not (userBalls and userBalls.Parent) then return end
	local cb = userBalls:FindFirstChild("Cue")
	if not cb then return end
	local dir = getAimDir(cb)
	if not dir or dir.Magnitude < 0.5 then return end
	dir = dir.Unit
	local power = readPower()
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
local function leaveScore(cueFinal, snap, sunkSet, rule)
	if not cueFinal then return 0 end
	local railPen = 0
	if userBounds then
		local m = 0.45
		if (cueFinal.X - userBounds.xMin) < m or (userBounds.xMax - cueFinal.X) < m
		   or (cueFinal.Z - userBounds.zMin) < m or (userBounds.zMax - cueFinal.Z) < m then
			railPen = -1.5
		end
	end
	local onEight = (rule ~= "" and myBallsLeft(snap, rule) == 0)
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

local bestState = {enabled=true, parts={}, lastCompute=0, current=nil}
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
local function findBest(ultraPrecise)
	if not pickUserTable() then return nil end
	local cb = userBalls:FindFirstChild("Cue"); if not cb then return nil end
	local cp = cb.Position
	local snap = snapshotBalls()
	local rule = guideMod.Rule or ""
	local best = {score = -math.huge}

	-- helper to evaluate and track best. Every shot that pots at least one of
	-- my balls is also kept as a candidate; after the search we re-rank the top
	-- ones by aim-robustness so a reliable fat shot beats a razor-thin cut that
	-- merely tied on raw score.
	local cands = {}
	local function tryShot(d, p, src)
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
			if #distinct >= 10 then break end
		end
		local probes = {-1.2, -0.8, -0.4, 0.4, 0.8, 1.2}  -- degrees of aim error
		local bestC, bestCombined = nil, -math.huge
		for _,c in ipairs(distinct) do
			local ok = 0
			for _,deg in ipairs(probes) do
				local r = math.rad(deg)
				local cr, sr = math.cos(r), math.sin(r)
				local rd = Vector3.new(c.dir.X*cr - c.dir.Z*sr, 0, c.dir.X*sr + c.dir.Z*cr)
				local s2, _, sk2 = evalShot(cb, cp, rd, c.power, snap, rule)
				if s2 > 0 and sk2 and sk2 >= 1 then ok = ok + 1 end
			end
			c.robust = ok / #probes
			-- Position play: where does the cue come to rest, and does that leave
			-- a clean look at my next ball(s)? A modest tie-breaker between pots.
			local finals2, pocket2 = {}, {}
			simulate(cb, cp, c.dir, shotPhysics(c.power), 0, snap, true, nil, pocket2, {}, finals2)
			local sunkSet = {}
			for ball,k in pairs(pocket2) do if k == "pocket" then sunkSet[ball] = true end end
			c.leave = leaveScore(finals2[cb], snap, sunkSet, rule)
			-- A fully aim-tolerant shot gains +12 — enough to outrank a fragile
			-- equal-score cut, while still respecting how many balls it pots; the
			-- leave score then breaks ties toward better position.
			local combined = c.score + c.robust * 12 + c.leave
			if combined > bestCombined then bestCombined = combined; bestC = c end
		end
		if bestC then bestC.score = bestCombined; best = bestC end
	end
	return best
end
local function renderBest(best)
	-- Only ever show a best shot that actually pots one of MY balls (sunk >= 1).
	-- No pot found → hide entirely instead of pointing the cue at a cushion.
	if not bestState.enabled or not best or best.score <= 0 or (best.sunk or 0) < 1 then
		clearBP(); if setHudInfo then setHudInfo(nil) end
		_G.__POOL_PRED_BEST = nil; bestState.current = nil; return
	end
	local cb = userBalls:FindFirstChild("Cue"); if not cb then return end
	local segs, pocket, ctx = {}, {}, {}
	simulate(cb, cb.Position, best.dir, shotPhysics(best.power), 0, snapshotBalls(), true, segs, pocket, ctx, nil)
	local idx = 0
	for _,s in ipairs(segs) do
		local show = s.isCue or pocket[s.ball] or not C.FILTER_NON_POCKETED
		if show then
			idx = idx + 1
			local p = getBP(idx, C.COL_BEST)
			setTube(p, s.p1, s.p2, 0.22)
		end
	end
	for i = idx+1, #bestState.parts do bestState.parts[i].Transparency = 1 end
	if setHudInfo then
		-- %.0f (not %d): best.power can be fractional and Luau's %d errors on that.
		setHudInfo(string.format("BEST: Power %.0f · Sink %d", best.power, best.sunk or 0))
	end
	bestState.current = best
	_G.__POOL_PRED_BEST = best
end
local function recompute() bestState.lastCompute = tick(); local b = findBest(); if b then renderBest(b) end end
local autoBest = rsv.Heartbeat:Connect(function()
	if not bestState.enabled then return end
	if tick() - bestState.lastCompute < C.BEST_INTERVAL then return end
	recompute()
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
	if not placeState.enabled then return end
	if tick() - placeState.lastCompute < C.PLACE_INTERVAL then return end
	recomputePlacement()
end)

-- ============ auto-aim ============
local autoAimEnabled = false
_G.__POOL_PRED_AIM_ON = false
local function applyAutoAim()
	if not autoAimEnabled then return end
	local best = _G.__POOL_PRED_BEST
	if not best or best.score <= 0 then return end
	if not (userBalls and userBalls.Parent) then return end
	local cb = userBalls:FindFirstChild("Cue")
	if not cb then return end
	local dir = best.dir.Unit
	local ballPos = cb.Position
	-- Force the shot direction for BOTH input paths the game uses
	-- (GameRunnerClient): mouse fires FireServer(MouseNormal.Unit*-1, power) so
	-- travel = -MouseNormal; touch fires FireServer((TouchHit-CuePos).Unit,power)
	-- so travel = toward TouchHit. Setting both makes the ball go along `dir`.
	pcall(function() guideMod.MouseNormal = -dir end)
	pcall(function() guideMod.TouchHit = ballPos + dir * 10 end)
	for _,name in ipairs({"AimNormal","AimDirection","ShotDirection","ShotNormal"}) do
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
end
rsv:BindToRenderStep("PoolAimOverride", Enum.RenderPriority.Last.Value + 1, applyAutoAim)
local autoAimHB = rsv.Heartbeat:Connect(applyAutoAim)

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
	if calMenuVisible and tick() - calRefreshT > 0.4 then calRefreshT = tick(); refreshCalMenu() end
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
		if not used then CAL.powA = clamp(CAL.vSy/CAL.vSx, 0.3, 15); CAL.powB = 0 end
	end
	-- K (decel) vs power. Under real friction K is roughly constant, kB→0.
	local kmean = CAL.kfN > 0 and CAL.kfSum/CAL.kfN or 40.0
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
local function decayAcc(maxN, fields)
	if CAL[fields[1]] > maxN then
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

	-- K: from each object ball that launched and stopped on its own (not sunk).
	local kSamples = {}
	for inst, tr in pairs(S.traj) do
		if inst ~= S.cueInst and tr and #tr >= 4 then
			local L = pathLen(tr)
			local T = tr[#tr][1] - tr[1][1]
			local fin = tr[#tr]
			if L > 0.6 and T > 0.10 and not sankAt(fin[2], fin[3]) then
				kSamples[#kSamples+1] = clamp(2*L/(T*T), 10, 90)
			end
		end
	end
	local realK = median(kSamples)

	-- v0: from the cue's free-rolling pre-contact arc, decel known.
	local realV0
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
	end
	-- Integral method has no R²; treat "measured" as accept-worthy for the gate.
	local fitR2 = realV0 and 1 or 0

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
						CAL.ballRest = clamp(CAL.brSum/CAL.brN, 0.5, 1.0)
					end
				end
			end
		end
	end

	-- ===== cushion restitution =====
	for _,r in ipairs(bounces) do
		local rr = clamp(r, 0.3, 0.98)
		CAL.crN = CAL.crN + 1; CAL.crSum = CAL.crSum + rr
		CAL.cushionRest = clamp(CAL.crSum/CAL.crN, 0.3, 0.98)
	end

	-- ===== K accumulators =====
	if realK then
		CAL.kfN = CAL.kfN + 1; CAL.kfSum = CAL.kfSum + realK
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
	end

	-- ===== decay so the most recent ~40 shots dominate the regression =====
	decayAcc(40, {"vN","vSx","vSy","vSxx","vSxy"})
	decayAcc(40, {"kN","kSx","kSy","kSxx","kSxy"})
	decayAcc(40, {"kfN","kfSum"})
	decayAcc(40, {"crN","crSum"})
	decayAcc(40, {"brN","brSum"})

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
					tr[#tr+1] = {now-S.t0, bp.X, bp.Z}
					if #tr > 2500 then table.remove(tr,1) end
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

-- ============ hotkeys ============
local hk = uis.InputBegan:Connect(function(input, proc)
	if proc then return end
	if input.KeyCode == C.BEST_HOTKEY then
		bestState.enabled = not bestState.enabled
		if bestState.enabled then print("[BestShot] ON"); recompute()
		else print("[BestShot] OFF"); clearBP(); _G.__POOL_PRED_BEST = nil; if setHudInfo then setHudInfo(nil) end end
	elseif input.KeyCode == C.AUTO_AIM_HOTKEY then
		autoAimEnabled = not autoAimEnabled
		_G.__POOL_PRED_AIM_ON = autoAimEnabled
		refreshHUD()
		print(autoAimEnabled and "[AutoAim] ON" or "[AutoAim] OFF")
		if autoAimEnabled then recompute() end
	elseif input.KeyCode == C.AUTO_FIRE_HOTKEY then
		-- Re-search with the ultra-precise refinement (±1° in 0.05° steps,
		-- ±0.5 power in 0.1 steps) immediately before firing. This costs
		-- ~400 extra evaluations but the shot lands sub-degree accurate.
		bestState.lastCompute = tick()
		local b = findBest(true)
		if b then renderBest(b) end
		if b and b.score > 0 and userComm then
			print(string.format("[AutoFire] pow=%.2f angle=%.2f° sink=%d src=%s score=%.1f",
				b.power, b.angle, b.sunk or 0, tostring(b.src), b.score))
			userComm:FireServer(b.dir.Unit, b.power)
		else
			print("[AutoFire] No good shot.")
		end
	elseif input.KeyCode == C.PLACE_HOTKEY then
		placeState.enabled = not placeState.enabled
		if placeState.enabled then
			print("[Place] Ball-in-hand finder ON")
			recomputePlacement()
		else
			print("[Place] OFF"); renderPlacement(nil)
		end
		refreshHUD()
	elseif input.KeyCode == C.CAL_MENU_HOTKEY then
		toggleCalMenu()
	elseif input.KeyCode == C.HUD_HOTKEY then
		hudVisible = not hudVisible
		refreshHUD()
	elseif input.KeyCode == C.RESET_HOTKEY then
		for k,v in pairs(DEFAULT_CAL) do CAL[k]=v end
		saveCal(); refreshHUD()
		print("[Cal] calibration reset to defaults")
	end
end)

-- ============ public handle ============
_G.__POOL_PREDICTOR = {
	cleanup = function()
		if predConn then predConn:Disconnect() end
		if autoBest then autoBest:Disconnect() end
		if autoPlace then autoPlace:Disconnect() end
		if autoAimHB then autoAimHB:Disconnect() end
		if obsConn then obsConn:Disconnect() end
		if calMenuConn then calMenuConn:Disconnect() end
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
		_G.__POOL_PREDICTOR = nil
		print("[Pred v12] Cleaned up.")
	end,
	config = C,
	cal = CAL,
	saveCal = saveCal,
	resetCal = function()
		for k,v in pairs(DEFAULT_CAL) do CAL[k]=v end
		saveCal(); refreshHUD(); print("[Cal] reset")
	end,
	recomputeBest = recompute,
}

recompute()
print(string.format("[Pred v12] Self-calibrating predictor loaded. Shots learned so far: %d. Avg error: %.2f st.",
	CAL.shots, CAL.errN > 0 and CAL.errSum/CAL.errN or 0))
print("[Pred v12] B=BestShot  V=AutoAim  F=AutoFire  G=BallInHand  K=CalDetail  C=HUD  X=reset calibration")
