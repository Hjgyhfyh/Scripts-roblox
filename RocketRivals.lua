-- Rocket Rivals | Humanized Bot v2.1 | tg: @sigmatik323

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local VIM = (pcall(function() return game:GetService("VirtualInputManager") end) and game:GetService("VirtualInputManager")) or nil

-- ============================================================================
-- UTILITY
-- ============================================================================
local frand = function(min, max) return min + math.random() * (max - min) end

local function vary(base, variance)
    return base * (1 + (math.random() * 2 - 1) * variance)
end

local function tapKey(code)
    local dur = frand(0.012, 0.030)
    if VIM then
        VIM:SendKeyEvent(true, code, false, game)
        task.wait(dur)
        VIM:SendKeyEvent(false, code, false, game)
    else
        UserInputService:SendKeyEvent(true, code, false, game)
        task.wait(dur)
        UserInputService:SendKeyEvent(false, code, false, game)
    end
end

local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function findByNameCI(root, name)
    if not root then return nil end
    local ln = string.lower(name)
    for _, ch in ipairs(root:GetChildren()) do
        if string.lower(ch.Name) == ln then return ch end
    end
    for _, ch in ipairs(root:GetChildren()) do
        local f = findByNameCI(ch, name)
        if f then return f end
    end
    return nil
end

-- ============================================================================
-- CHARACTER
-- ============================================================================
local function getChar()
    local ch = LP.Character or LP.CharacterAdded:Wait()
    ch:WaitForChild("Humanoid")
    ch:WaitForChild("HumanoidRootPart")
    return ch
end

local c, hum, hrp

-- ============================================================================
-- CLEANUP
-- ============================================================================
pcall(function()
    for _, pg in ipairs({LP:FindFirstChildOfClass("PlayerGui"), game:GetService("CoreGui")}) do
        if pg then
            local old = pg:FindFirstChild("Helper_UI")
            if old then old:Destroy() end
        end
    end
end)

-- ============================================================================
-- BALL TRACKING
-- ============================================================================
local trackedBall = nil
local trackedBallConn = nil
local nextBallSearch = 0
local BALL_SEARCH_INTERVAL = 0.25

local function bindBall(ball)
    if trackedBallConn then trackedBallConn:Disconnect(); trackedBallConn = nil end
    trackedBall = ball
    if trackedBall then
        trackedBallConn = trackedBall.AncestryChanged:Connect(function(_, parent)
            if not parent then bindBall(nil) end
        end)
    end
end

workspace.DescendantAdded:Connect(function(inst)
    if trackedBall and trackedBall.Parent then return end
    if inst and string.lower(inst.Name) == "ballshadow" then bindBall(inst) end
end)

local function locateBall()
    local fx = workspace:FindFirstChild("fx") or workspace:FindFirstChild("Fx") or workspace:FindFirstChild("FX")
    local candidate = nil
    if fx then
        candidate = fx:FindFirstChild("BallShadow") or fx:FindFirstChild("ballshadow") or findByNameCI(fx, "BallShadow")
    end
    if not candidate then candidate = findByNameCI(workspace, "BallShadow") end
    bindBall(candidate)
end

local function getBall()
    if trackedBall and trackedBall.Parent then return trackedBall end
    if tick() < nextBallSearch then return nil end
    nextBallSearch = tick() + BALL_SEARCH_INTERVAL
    locateBall()
    return trackedBall
end

-- ============================================================================
-- COURT DETECTION
-- ============================================================================
local currentCourtNumber = 1

local function detectCurrentCourt()
    local ch = LP.Character
    if not ch then return currentCourtNumber end
    local root = ch:FindFirstChild("HumanoidRootPart")
    if not root then return currentCourtNumber end
    local pos = root.Position
    local courts = workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if not courts then return currentCourtNumber end
    local bestCourt, bestDist = 1, math.huge
    for i = 1, 5 do
        local cf = courts:FindFirstChild(tostring(i))
        if cf then
            local map = cf:FindFirstChild("Map")
            if map then
                local fl = map:FindFirstChild("OccludeFloor")
                if fl and fl:IsA("BasePart") then
                    local d = (pos - fl.Position).Magnitude
                    if d < bestDist then bestDist = d; bestCourt = i end
                end
            end
        end
    end
    currentCourtNumber = bestCourt
    return currentCourtNumber
end

local function getMapCenter()
    local cn = detectCurrentCourt()
    local courts = workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if courts then
        local cf = courts:FindFirstChild(tostring(cn))
        if cf then
            local map = cf:FindFirstChild("Map")
            if map then
                local fl = map:FindFirstChild("OccludeFloor")
                if fl and fl:IsA("BasePart") then return fl.Position end
            end
        end
    end
    return Vector3.new(-54, -511, -72)
end

local function getCurrentCourtMap()
    local cn = detectCurrentCourt()
    local courts = workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if not courts then return nil end
    local cf = courts:FindFirstChild(tostring(cn))
    if not cf then return nil end
    return cf:FindFirstChild("Map")
end

local function getTeamSpawns()
    local bs = Vector3.new(-54, -511, -41)
    local rs = Vector3.new(-54, -511, -103)
    local cn = detectCurrentCourt()
    local courts = workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if courts then
        local cf = courts:FindFirstChild(tostring(cn))
        if cf then
            local map = cf:FindFirstChild("Map")
            if map then
                local s1f = map:FindFirstChild("Spawns1") or map:FindFirstChild("Spawns")
                if s1f then
                    local s1 = s1f:FindFirstChild("1")
                    if s1 and s1:IsA("BasePart") then bs = s1.Position
                    elseif s1 then
                        local s11 = s1:FindFirstChild("1")
                        if s11 and s11:IsA("BasePart") then bs = s11.Position end
                    end
                end
                local s2f = map:FindFirstChild("Spawns2")
                if s2f then
                    local s2 = s2f:FindFirstChild("1")
                    if s2 and s2:IsA("BasePart") then rs = s2.Position
                    elseif s2 then
                        local s21 = s2:FindFirstChild("1")
                        if s21 and s21:IsA("BasePart") then rs = s21.Position end
                    end
                end
            end
        end
    end
    return bs, rs
end

local function getServeBounds()
    local bounds = {}
    local courts = workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if courts then
        for _, cfd in ipairs(courts:GetChildren()) do
            if cfd:IsA("Folder") or cfd:IsA("Model") then
                local map = cfd:FindFirstChild("Map")
                if map then
                    local sb = map:FindFirstChild("ServeBounds")
                    if sb then
                        for _, folder in ipairs(sb:GetChildren()) do
                            if folder:IsA("Folder") or folder:IsA("Model") then
                                local part = folder:FindFirstChild("Part")
                                if part and part:IsA("BasePart") then table.insert(bounds, part) end
                            end
                        end
                    end
                end
            end
        end
    end
    return bounds
end

local function isInServeBounds(pos)
    for _, part in ipairs(getServeBounds()) do
        local lp = part.CFrame:PointToObjectSpace(pos)
        if math.abs(lp.X) <= part.Size.X / 2 and math.abs(lp.Y) <= part.Size.Y / 2 and math.abs(lp.Z) <= part.Size.Z / 2 then
            return true, part
        end
    end
    return false, nil
end

-- ============================================================================
-- LOBBY CHECK
-- ============================================================================
local function isInLobby()
    local ch = LP.Character
    if not ch then return true end
    local root = ch:FindFirstChild("HumanoidRootPart")
    if not root then return true end
    local pos = root.Position
    if pos.Y > -480 and pos.Y < -440 and pos.X > 80 and pos.X < 260 and pos.Z > -140 and pos.Z < 0 then
        return true
    end
    local courts = workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if not courts then return true end
    for i = 1, 5 do
        local cf = courts:FindFirstChild(tostring(i))
        if cf then
            local map = cf:FindFirstChild("Map")
            if map then
                local fl = map:FindFirstChild("OccludeFloor")
                if fl and fl:IsA("BasePart") and (pos - fl.Position).Magnitude < 150 then
                    return false
                end
            end
        end
    end
    return true
end

-- ============================================================================
-- NAVIGATION DATA
-- ============================================================================
local WAIT_POINTS = {Vector3.new(-54, -511, -41), Vector3.new(-54, -511, -103)}
local MID = Vector3.new(-54, -511, -72)
local DIR = Vector3.new(0, 0, 1)
local lastMapUpdate = 0
local MAP_UPDATE_INTERVAL = 0.4
local homeWaitIndex = 1
local HOME_SIGN = 0
local IS_BLUE = false

local function updateMapData()
    if tick() - lastMapUpdate < MAP_UPDATE_INTERVAL then return end
    lastMapUpdate = tick()
    MAP_UPDATE_INTERVAL = frand(0.3, 0.5)
    local bs, rs = getTeamSpawns()
    WAIT_POINTS[1] = bs
    WAIT_POINTS[2] = rs
    MID = getMapCenter()
    local diff = flat(WAIT_POINTS[1] - WAIT_POINTS[2])
    DIR = (diff.Magnitude > 1e-4) and diff.Unit or Vector3.new(0, 0, 1)
end

local function sideSign(pos)
    local d = flat(pos - MID):Dot(DIR)
    return (d > 0) and 1 or ((d < 0) and -1 or 0)
end

local function getLaneDir()
    local lane = Vector3.new(-DIR.Z, 0, DIR.X)
    return (lane.Magnitude > 1e-4) and lane.Unit or Vector3.new(1, 0, 0)
end

local function getCourtHalfExtents()
    local hw, hl = 18, 31
    local map = getCurrentCourtMap()
    if not map then return hw, hl end
    local fl = map:FindFirstChild("OccludeFloor")
    if not fl or not fl:IsA("BasePart") then return hw, hl end
    local right = flat(fl.CFrame.RightVector)
    local look = flat(fl.CFrame.LookVector)
    if right.Magnitude <= 1e-4 or look.Magnitude <= 1e-4 then return hw, hl end
    right, look = right.Unit, look.Unit
    local ld = getLaneDir()
    local sd = DIR
    hw = math.abs(ld:Dot(right)) * fl.Size.X * 0.5 + math.abs(ld:Dot(look)) * fl.Size.Z * 0.5
    hl = math.abs(sd:Dot(right)) * fl.Size.X * 0.5 + math.abs(sd:Dot(look)) * fl.Size.Z * 0.5
    return math.max(8, hw - 2.75), math.max(10, hl - 2.5)
end

local function resolveHomeWaitIndex(force)
    updateMapData()
    if not hrp or not hrp.Parent then return homeWaitIndex end
    local pos = hrp.Position
    local d1 = (pos - WAIT_POINTS[1]).Magnitude
    local d2 = (pos - WAIT_POINTS[2]).Magnitude
    if force or not homeWaitIndex then homeWaitIndex = (d1 <= d2) and 1 or 2 end
    IS_BLUE = (homeWaitIndex == 1)
    HOME_SIGN = sideSign(WAIT_POINTS[homeWaitIndex])
    return homeWaitIndex
end

local function getHomeBase()
    resolveHomeWaitIndex(false)
    return WAIT_POINTS[homeWaitIndex or 1]
end

local function clampToCourt(pos, lp, sp)
    updateMapData()
    local center = getMapCenter()
    local ld = getLaneDir()
    local sd = DIR
    local hw, hl = getCourtHalfExtents()
    local off = flat(pos - center)
    local lane = math.clamp(off:Dot(ld), -math.max(4, hw - (lp or 0)), math.max(4, hw - (lp or 0)))
    local side = math.clamp(off:Dot(sd), -math.max(6, hl - (sp or 0)), math.max(6, hl - (sp or 0)))
    return Vector3.new(center.X, pos.Y, center.Z) + ld * lane + sd * side
end

local function homeClampSide(sideVal, hl, crossAllow)
    local sl = math.max(8, hl - 1.75)
    local ea = crossAllow or 0.75
    if HOME_SIGN > 0 then return math.clamp(sideVal, -ea, sl) end
    if HOME_SIGN < 0 then return math.clamp(sideVal, -sl, ea) end
    return math.clamp(sideVal, -sl, sl)
end

local function getHomeAnchor(refPos, trackLane)
    updateMapData()
    local hb = getHomeBase()
    local center = getMapCenter()
    local ld = getLaneDir()
    local sd = DIR
    local hw, hl = getCourtHalfExtents()
    local lane = flat(hb - center):Dot(ld)
    if trackLane and refPos then
        local rl = flat(refPos - center):Dot(ld)
        lane = lane + (rl - lane) * vary(0.35, 0.3)
    end
    lane = math.clamp(lane, -math.max(6, hw - 3), math.max(6, hw - 3))
    local hs = HOME_SIGN
    if hs == 0 then hs = sideSign(hb) end
    if hs == 0 then hs = (homeWaitIndex == 1) and 1 or -1 end
    local bs = math.abs(flat(hb - center):Dot(sd))
    local side = hs * math.min(math.max(8, bs), math.max(10, hl - 3))
    return clampToCourt(Vector3.new(center.X, hb.Y, center.Z) + ld * lane + sd * side, 2.5, 2.5)
end

local function getHomeIncomingSpeed(vel)
    return (HOME_SIGN ~= 0) and (flat(vel):Dot(DIR) * HOME_SIGN) or 0
end

-- ============================================================================
-- PREDICTION
-- ============================================================================
local function predictLead(bpos, vel)
    local myPos = hrp.Position
    local dist = (bpos - myPos).Magnitude
    local cfg = config
    local lead = math.clamp(cfg.predictionLeadMin + dist / 48 * cfg.predictionLeadScale, cfg.predictionLeadMin, cfg.predictionLeadMax)
    lead = vary(lead, 0.08)
    return bpos + Vector3.new(vel.X, 0, vel.Z) * lead
end

local function getInterceptTarget(bpos, vel)
    updateMapData()
    local center = getMapCenter()
    local ld = getLaneDir()
    local sd = DIR
    local target = predictLead(bpos, vel)
    local incomingSpeed = getHomeIncomingSpeed(vel)
    local hw, hl = getCourtHalfExtents()
    local laneLimit = math.max(6, hw - 2.5)
    local flatSpeed = flat(vel).Magnitude
    local chaseBlend = math.clamp(0.85 + flatSpeed / 130, 0.85, 1)
    local ballLane = flat(bpos - center):Dot(ld)
    local predictedLane = flat(target - center):Dot(ld)
    local ballSide = flat(bpos - center):Dot(sd)
    local predictedSide = flat(target - center):Dot(sd)
    local threat = (HOME_SIGN ~= 0 and (sideSign(bpos) == HOME_SIGN or sideSign(target) == HOME_SIGN or incomingSpeed > 6))
    local lane, side
    if threat then
        lane = ballLane + (predictedLane - ballLane) * chaseBlend
        side = ballSide + (predictedSide - ballSide) * chaseBlend
        side = homeClampSide(side, hl, 2.75)
    else
        local anchor = getHomeAnchor(target, true)
        lane = flat(anchor - center):Dot(ld)
        side = flat(anchor - center):Dot(sd)
    end
    lane = math.clamp(lane, -laneLimit, laneLimit)
    target = Vector3.new(center.X, bpos.Y, center.Z) + ld * lane + sd * side
    return clampToCourt(target, 2.2, 2.2)
end

local function getServeAimPoint()
    updateMapData()
    local center = getMapCenter()
    local ld = getLaneDir()
    local sd = DIR
    local hw, hl = getCourtHalfExtents()
    local es = -HOME_SIGN
    if es == 0 then es = (homeWaitIndex == 1) and -1 or 1 end
    local lane = math.clamp(flat(hrp.Position - center):Dot(ld), -math.max(6, hw - 4), math.max(6, hw - 4))
    lane = math.clamp(lane * vary(1.35, 0.15), -math.max(7, hw - 2.75), math.max(7, hw - 2.75))
    local side = es * math.max(10, hl - 5)
    return clampToCourt(Vector3.new(center.X, hrp.Position.Y, center.Z) + ld * lane + sd * side, 2.2, 2.2)
end

-- ============================================================================
-- CONFIG & TOGGLES
-- ============================================================================
local config = {
    sprintRadius = 15, closeControlRadius = 7, shootDistance = 22, kickDelay = 0.01,
    sprintSpamInterval = 0.06, sprintJumpInterval = 0.28, closeJumpInterval = 0.22,
    predictionLeadMin = 0.16, predictionLeadScale = 0.26, predictionLeadMax = 0.46,
    moveNearDistance = 2, deadZone = 0.5, minReissueDistance = 0.75, minReissueTime = 0.05,
    autoHitDistance = 10, hitRange = 10, returnDistance = 5,
    trickCooldown = 0.8, slideCooldown = 0.8, focusLerp = 0.35,
}

local toggles = {
    allowJump = true, allowSprint = true, allowSlide = true, allowTrick = true,
    autoFace = true, autoHit = true, quickReturn = true, enableGoalGuard = true,
    showAim = false, showTrail = false, showSprintRing = false,
    showGoalLine = false, showBallLine = false, showSpeedArrow = false, floatingGlow = false,
}

local enabled = false
local autoBSpam = false
local nextBSpam = 0
local wasInLobby = false
local enabledBeforeLobby = true

-- ============================================================================
-- VISUALS (LIGHTWEIGHT, ALL OFF BY DEFAULT)
-- ============================================================================
local visuals = {}
local function setupVisuals()
    local v = visuals
    v.aimDot = Instance.new("Part")
    v.aimDot.Anchored, v.aimDot.CanCollide = true, false
    v.aimDot.Material = Enum.Material.Neon
    v.aimDot.Color = Color3.fromRGB(255, 215, 70)
    v.aimDot.Size = Vector3.new(0.4, 0.4, 0.4)
    v.aimDot.Transparency = toggles.showAim and 0.3 or 1
    v.aimDot.Parent = workspace

    v.predDot = Instance.new("Part")
    v.predDot.Anchored, v.predDot.CanCollide = true, false
    v.predDot.Material = Enum.Material.ForceField
    v.predDot.Color = Color3.fromRGB(255, 240, 160)
    v.predDot.Size = Vector3.new(0.5, 0.25, 0.5)
    v.predDot.Transparency = toggles.showAim and 0.4 or 1
    v.predDot.Parent = workspace

    v.predDots = {}
    for i = 1, 5 do
        local p = Instance.new("Part")
        p.Anchored, p.CanCollide = true, false
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(255, 230, 140)
        p.Size = Vector3.new(0.2, 0.08, 0.2)
        p.Transparency = toggles.showTrail and 0.55 or 1
        p.Parent = workspace
        v.predDots[i] = p
    end

    v.orbitAdorn = Instance.new("CylinderHandleAdornment")
    v.orbitAdorn.Radius = config.sprintRadius
    v.orbitAdorn.Height = 0.12
    v.orbitAdorn.Color3 = Color3.fromRGB(255, 220, 80)
    v.orbitAdorn.AlwaysOnTop = true
    v.orbitAdorn.Transparency = toggles.showSprintRing and 0.65 or 1
    pcall(function() v.orbitAdorn.Adornee = hrp; v.orbitAdorn.Parent = hrp end)

    v.glowTrail = Instance.new("ParticleEmitter")
    v.glowTrail.LightEmission = 0.9
    v.glowTrail.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3, 0.08), NumberSequenceKeypoint.new(0.5, 0.6, 0.1), NumberSequenceKeypoint.new(1, 0)})
    v.glowTrail.Color = ColorSequence.new(Color3.fromRGB(245, 210, 62), Color3.fromRGB(255, 255, 240))
    v.glowTrail.Rate = toggles.floatingGlow and 8 or 0
    v.glowTrail.Lifetime = NumberRange.new(0.4, 0.7)
    v.glowTrail.Speed = NumberRange.new(0, 0)
    v.glowTrail.SpreadAngle = Vector2.new(360, 360)
    v.glowTrail.Parent = v.aimDot

    v.hrpAtt = Instance.new("Attachment"); pcall(function() v.hrpAtt.Parent = hrp end)
    v.aimAtt = Instance.new("Attachment"); v.aimAtt.Parent = v.aimDot

    v.ballBeam = Instance.new("Beam")
    v.ballBeam.Attachment0, v.ballBeam.Attachment1 = v.hrpAtt, v.aimAtt
    v.ballBeam.Width0, v.ballBeam.Width1 = 0.12, 0.06
    v.ballBeam.FaceCamera = true
    v.ballBeam.Color = ColorSequence.new(Color3.fromRGB(245, 210, 62))
    v.ballBeam.Transparency = NumberSequence.new(toggles.showBallLine and 0.15 or 1)
    v.ballBeam.Enabled = toggles.showBallLine
    v.ballBeam.Parent = v.hrpAtt

    v.speedAtt = Instance.new("Attachment"); v.speedAtt.Parent = v.predDot
    v.speedBeam = Instance.new("Beam")
    v.speedBeam.Attachment0, v.speedBeam.Attachment1 = v.aimAtt, v.speedAtt
    v.speedBeam.Width0, v.speedBeam.Width1 = 0.08, 0
    v.speedBeam.Color = ColorSequence.new(Color3.fromRGB(255, 248, 180), Color3.fromRGB(255, 120, 60))
    v.speedBeam.Enabled = toggles.showSpeedArrow
    v.speedBeam.Parent = v.aimAtt

    v.goalPart = Instance.new("Part")
    v.goalPart.Anchored, v.goalPart.CanCollide = true, false
    v.goalPart.Transparency = 1; v.goalPart.Size = Vector3.new(0.1, 0.1, 0.1)
    v.goalPart.Parent = workspace
    v.goalAtt = Instance.new("Attachment"); v.goalAtt.Parent = v.goalPart
    v.goalBeam = Instance.new("Beam")
    v.goalBeam.Attachment0, v.goalBeam.Attachment1 = v.aimAtt, v.goalAtt
    v.goalBeam.Width0, v.goalBeam.Width1 = 0.1, 0.04
    v.goalBeam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 198, 82))
    v.goalBeam.Enabled = toggles.showGoalLine
    v.goalBeam.Parent = v.aimAtt
end

local function refreshVisuals()
    local v = visuals
    if not v.aimDot then return end
    v.aimDot.Transparency = toggles.showAim and 0.3 or 1
    v.predDot.Transparency = toggles.showAim and 0.4 or 1
    for _, p in ipairs(v.predDots) do p.Transparency = toggles.showTrail and 0.55 or 1 end
    v.orbitAdorn.Radius = config.sprintRadius
    v.orbitAdorn.Transparency = toggles.showSprintRing and 0.65 or 1
    v.ballBeam.Enabled = toggles.showBallLine
    v.ballBeam.Transparency = NumberSequence.new(toggles.showBallLine and 0.15 or 1)
    v.goalBeam.Enabled = toggles.showGoalLine
    v.speedBeam.Enabled = toggles.showSpeedArrow
    v.glowTrail.Rate = toggles.floatingGlow and 8 or 0
end

local function drawPrediction(bpos, ppos)
    local v = visuals
    v.aimDot.Position = bpos
    v.predDot.Position = ppos
    v.aimAtt.WorldPosition = bpos
    if v.speedAtt then v.speedAtt.WorldPosition = ppos end
    for i = 1, #v.predDots do
        v.predDots[i].Position = bpos + (ppos - bpos) * (i / #v.predDots)
    end
end

-- ============================================================================
-- MOVEMENT
-- ============================================================================
local rparams = RaycastParams.new()
rparams.FilterType = Enum.RaycastFilterType.Exclude
rparams.FilterDescendantsInstances = {}

local function isGrounded()
    return workspace:Raycast(hrp.Position, Vector3.new(0, -6, 0), rparams) ~= nil
end

local function isNearNet(pos)
    local sd = flat(((pos or hrp.Position) - getMapCenter())):Dot(DIR)
    return math.abs(sd) < 3.25
end

local function doJump()
    if not toggles.allowJump then return end
    hum.Jump = true
    hum:ChangeState(Enum.HumanoidStateType.Jumping)
    tapKey(Enum.KeyCode.Space)
end

local function doSlide()
    if not toggles.allowSlide then return end
    tapKey(Enum.KeyCode.E)
end

local function doTrick()
    if not toggles.allowTrick then return end
    tapKey(Enum.KeyCode.R)
end

local function faceXZ(toPos)
    if not toggles.autoFace then return end
    local here = hrp.Position
    local look = Vector3.new(toPos.X, here.Y, toPos.Z)
    hrp.CFrame = hrp.CFrame:Lerp(CFrame.new(here, look), vary(config.focusLerp, 0.2))
end

local state = "WAIT"
local moving = false
local lastIssue = 0
local currentGoal = nil
local currentGoalNetAllowance = 0.75

local function requestMoveTo(goal, crossAllowance)
    if not goal then return end
    local allowance = crossAllowance or currentGoalNetAllowance or 0.75
    goal = clampToCourt(goal, 2.2, 2.2)
    if HOME_SIGN ~= 0 then
        local center = getMapCenter()
        local ld = getLaneDir()
        local _, hl = getCourtHalfExtents()
        local lane = flat(goal - center):Dot(ld)
        local side = flat(goal - center):Dot(DIR)
        side = homeClampSide(side, hl, allowance)
        goal = Vector3.new(center.X, goal.Y, center.Z) + ld * lane + DIR * side
        goal = clampToCourt(goal, 2.2, 2.2)
    end
    local here = hrp.Position
    local g = Vector3.new(goal.X, here.Y, goal.Z)
    local needDist = (not currentGoal) or (g - currentGoal).Magnitude >= vary(config.minReissueDistance, 0.4)
    local needTime = (tick() - lastIssue) >= vary(config.minReissueTime, 0.3)
    if needDist or (not moving) or needTime then
        currentGoal = g
        currentGoalNetAllowance = allowance
        hum.WalkToPoint = g
        hum:MoveTo(g)
        lastIssue = tick()
        moving = true
    end
end

local function steerClose(goal)
    local here = hrp.Position
    local g = Vector3.new(goal.X, here.Y, goal.Z)
    local delta = g - here
    if delta.Magnitude > 0.1 then
        hum:Move(delta.Unit, false)
    else
        hum:Move(Vector3.zero, false)
    end
end

local function goWait(refPos)
    local t = getHomeAnchor(refPos, false)
    drawPrediction(t, t)
    requestMoveTo(t, 0.75)
    steerClose(t)
end

-- ============================================================================
-- SPRINT LOGIC
-- ============================================================================
local HOME_NET_ALLOWANCE = 0.75
local INTERCEPT_NET_ALLOWANCE = 2.75
local BALL_SPRINT_GRACE = 0.18
local BALL_FLIP_SPRINT_GRACE = 0.1
local SPRINT_NEAR_BALL_BUFFER = 3.5
local SPRINT_TARGET_BUFFER = 1.75

local function sprintLogic(targetDist, incomingSpeed, ballDist, targetPoint, bpos, ballAge)
    if not toggles.allowSprint then return end
    if ballAge < BALL_SPRINT_GRACE then return end
    if isNearNet() then return end
    local predictionGap = flat(targetPoint - bpos).Magnitude
    local ballIsClose = ballDist <= config.autoHitDistance + SPRINT_NEAR_BALL_BUFFER
    local sprintNeed = (targetDist > vary(config.sprintRadius, 0.12) or incomingSpeed > vary(18, 0.15)) and not ballIsClose and predictionGap > SPRINT_TARGET_BUFFER
    if sprintNeed then
        if isGrounded() and tick() >= nextSprintJump then
            doJump()
            nextSprintJump = tick() + vary(config.sprintJumpInterval, 0.25)
        end
        if tick() >= nextSprintPress then
            tapKey(Enum.KeyCode.Q)
            nextSprintPress = tick() + vary(config.sprintSpamInterval, 0.2)
        end
    end
end

-- ============================================================================
-- RAYFIELD UI
-- ============================================================================
pcall(function()
    local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
    if not Rayfield then return end

    local Window = Rayfield:CreateWindow({
        Name = "tg: @sigmatik323",
        LoadingTitle = "tg: @sigmatik323",
        LoadingSubtitle = "by sigmatik323",
        ConfigurationSaving = { Enabled = true, FolderName = "RocketRivals", FileName = "Config" },
        KeySystem = false
    })

    local PTab = Window:CreateTab("Parameters", "sliders")
    local MTab = Window:CreateTab("Modes", "toggle-left")
    local VTab = Window:CreateTab("Visuals", "eye")
    local STab = Window:CreateTab("Settings", "settings")

    PTab:CreateSection("Movement")
    PTab:CreateSlider({Name="Sprint Radius",Range={4,40},Increment=1,CurrentValue=config.sprintRadius,Flag="sprintRadius",Callback=function(v)config.sprintRadius=v end})
    PTab:CreateSlider({Name="Close Control Radius",Range={2,15},Increment=1,CurrentValue=config.closeControlRadius,Flag="closeControlRadius",Callback=function(v)config.closeControlRadius=v end})
    PTab:CreateSlider({Name="Shoot Distance",Range={6,40},Increment=1,CurrentValue=config.shootDistance,Flag="shootDistance",Callback=function(v)config.shootDistance=v end})
    PTab:CreateSlider({Name="Auto Hit Distance",Range={2,30},Increment=1,CurrentValue=config.autoHitDistance,Flag="autoHitDistance",Callback=function(v)config.autoHitDistance=v end})
    PTab:CreateSlider({Name="Hit Range",Range={4,24},Increment=1,CurrentValue=config.hitRange,Flag="hitRange",Callback=function(v)config.hitRange=v end})

    PTab:CreateSection("Timing")
    PTab:CreateSlider({Name="Sprint Interval",Range={2,25},Increment=1,Suffix="ms",CurrentValue=math.floor(config.sprintSpamInterval*100),Flag="sprintInterval",Callback=function(v)config.sprintSpamInterval=v/100 end})
    PTab:CreateSlider({Name="Sprint Jump Interval",Range={12,60},Increment=1,Suffix="ms",CurrentValue=math.floor(config.sprintJumpInterval*100),Flag="sprintJump",Callback=function(v)config.sprintJumpInterval=v/100 end})
    PTab:CreateSlider({Name="Close Jump Interval",Range={8,60},Increment=1,Suffix="ms",CurrentValue=math.floor(config.closeJumpInterval*100),Flag="closeJump",Callback=function(v)config.closeJumpInterval=v/100 end})

    PTab:CreateSection("Prediction")
    PTab:CreateSlider({Name="Prediction Lead Min",Range={5,50},Increment=1,Suffix="%",CurrentValue=math.floor(config.predictionLeadMin*100),Flag="predMin",Callback=function(v)config.predictionLeadMin=v/100 end})
    PTab:CreateSlider({Name="Prediction Lead Scale",Range={5,60},Increment=1,Suffix="%",CurrentValue=math.floor(config.predictionLeadScale*100),Flag="predScale",Callback=function(v)config.predictionLeadScale=v/100 end})
    PTab:CreateSlider({Name="Prediction Lead Max",Range={10,80},Increment=1,Suffix="%",CurrentValue=math.floor(config.predictionLeadMax*100),Flag="predMax",Callback=function(v)config.predictionLeadMax=v/100 end})

    PTab:CreateSection("Other")
    PTab:CreateSlider({Name="Move Near Distance",Range={1,6},Increment=1,CurrentValue=config.moveNearDistance,Flag="moveNear",Callback=function(v)config.moveNearDistance=v end})
    PTab:CreateSlider({Name="Dead Zone",Range={1,20},Increment=1,Suffix="/10",CurrentValue=math.floor(config.deadZone*10),Flag="deadZone",Callback=function(v)config.deadZone=v/10 end})
    PTab:CreateSlider({Name="Return Distance",Range={1,12},Increment=1,CurrentValue=config.returnDistance,Flag="returnDist",Callback=function(v)config.returnDistance=v end})
    PTab:CreateSlider({Name="Focus Lerp",Range={5,80},Increment=1,Suffix="%",CurrentValue=math.floor(config.focusLerp*100),Flag="focusLerp",Callback=function(v)config.focusLerp=v/100 end})
    PTab:CreateSlider({Name="Trick Cooldown",Range={2,25},Increment=1,Suffix="/10s",CurrentValue=math.floor(config.trickCooldown*10),Flag="trickCd",Callback=function(v)config.trickCooldown=v/10 end})
    PTab:CreateSlider({Name="Slide Cooldown",Range={2,25},Increment=1,Suffix="/10s",CurrentValue=math.floor(config.slideCooldown*10),Flag="slideCd",Callback=function(v)config.slideCooldown=v/10 end})

    MTab:CreateSection("Bot Modes")
    MTab:CreateToggle({Name="Allow Jump",CurrentValue=toggles.allowJump,Flag="allowJump",Callback=function(v)toggles.allowJump=v end})
    MTab:CreateToggle({Name="Allow Sprint",CurrentValue=toggles.allowSprint,Flag="allowSprint",Callback=function(v)toggles.allowSprint=v end})
    MTab:CreateToggle({Name="Allow Slide",CurrentValue=toggles.allowSlide,Flag="allowSlide",Callback=function(v)toggles.allowSlide=v end})
    MTab:CreateToggle({Name="Allow Trick",CurrentValue=toggles.allowTrick,Flag="allowTrick",Callback=function(v)toggles.allowTrick=v end})
    MTab:CreateToggle({Name="Auto Face",CurrentValue=toggles.autoFace,Flag="autoFace",Callback=function(v)toggles.autoFace=v end})
    MTab:CreateToggle({Name="Auto Hit",CurrentValue=toggles.autoHit,Flag="autoHit",Callback=function(v)toggles.autoHit=v end})
    MTab:CreateToggle({Name="Quick Return",CurrentValue=toggles.quickReturn,Flag="quickReturn",Callback=function(v)toggles.quickReturn=v end})
    MTab:CreateToggle({Name="Goal Guard",CurrentValue=toggles.enableGoalGuard,Flag="goalGuard",Callback=function(v)toggles.enableGoalGuard=v end})

    VTab:CreateSection("Visual Settings")
    VTab:CreateToggle({Name="Show Aim",CurrentValue=toggles.showAim,Flag="showAim",Callback=function(v)toggles.showAim=v refreshVisuals()end})
    VTab:CreateToggle({Name="Show Trail",CurrentValue=toggles.showTrail,Flag="showTrail",Callback=function(v)toggles.showTrail=v refreshVisuals()end})
    VTab:CreateToggle({Name="Show Sprint Ring",CurrentValue=toggles.showSprintRing,Flag="showSprintRing",Callback=function(v)toggles.showSprintRing=v refreshVisuals()end})
    VTab:CreateToggle({Name="Show Goal Line",CurrentValue=toggles.showGoalLine,Flag="showGoalLine",Callback=function(v)toggles.showGoalLine=v refreshVisuals()end})
    VTab:CreateToggle({Name="Show Ball Line",CurrentValue=toggles.showBallLine,Flag="showBallLine",Callback=function(v)toggles.showBallLine=v refreshVisuals()end})
    VTab:CreateToggle({Name="Show Speed Arrow",CurrentValue=toggles.showSpeedArrow,Flag="showSpeedArrow",Callback=function(v)toggles.showSpeedArrow=v refreshVisuals()end})
    VTab:CreateToggle({Name="Floating Glow",CurrentValue=toggles.floatingGlow,Flag="floatingGlow",Callback=function(v)toggles.floatingGlow=v refreshVisuals()end})

    STab:CreateSection("Controls")
    STab:CreateKeybind({Name="Toggle Bot",CurrentKeybind="",HoldToInteract=false,Flag="toggleBotKey",Callback=function()enabled=not enabled;Rayfield:Notify({Title="Bot",Content=enabled and"Enabled"or"Disabled",Duration=2})end})
    STab:CreateToggle({Name="Auto B-Spam",CurrentValue=false,Flag="autoBSpam",Callback=function(v)autoBSpam=v;if v then nextBSpam=0 end end})
    STab:CreateToggle({Name="Bot Enabled",CurrentValue=true,Flag="botEnabled",Callback=function(v)enabled=v end})

    STab:CreateSection("Configuration")
    STab:CreateButton({Name="Reset All Settings",Callback=function()
        Rayfield:Notify({Title="Reset",Content="Resetting... rejoin to apply.",Duration=3})
        pcall(function()if delfile then pcall(function()delfile("RocketRivals/Config.json")end)end;if delfolder then pcall(function()delfolder("RocketRivals")end)end end)
    end})
end)

-- ============================================================================
-- INIT
-- ============================================================================
c = getChar()
hum = c:WaitForChild("Humanoid")
hrp = c:WaitForChild("HumanoidRootPart")
rparams.FilterDescendantsInstances = {c}
resolveHomeWaitIndex(true)
hum.PlatformStand = false
hum.AutoRotate = true
pcall(function() hum.UseJumpPower = true; hum.JumpPower = math.max(hum.JumpPower, 50) end)
if hum.WalkSpeed < 16 then hum.WalkSpeed = 18 end
hum.MoveToFinished:Connect(function() moving = false end)

setupVisuals()

-- ============================================================================
-- CHARACTER RESPAWN
-- ============================================================================
LP.CharacterAdded:Connect(function()
    task.wait(0.3)
    c = getChar()
    hum = c:WaitForChild("Humanoid")
    hrp = c:WaitForChild("HumanoidRootPart")
    rparams.FilterDescendantsInstances = {c}
    pcall(function() visuals.hrpAtt.Parent = hrp end)
    pcall(function() visuals.orbitAdorn.Adornee = hrp; visuals.orbitAdorn.Parent = hrp end)
    currentGoal, moving = nil, false
    lastBallPos, lastBallT = nil, 0
    ballVisibleSince, lastBallVel = 0, Vector3.zero
    lastDirectionFlip, netCollisionTime = 0, 0
    resolveHomeWaitIndex(true)
    hum.PlatformStand = false
    hum.AutoRotate = true
    pcall(function() hum.UseJumpPower = true; hum.JumpPower = math.max(hum.JumpPower, 50) end)
    if hum.WalkSpeed < 16 then hum.WalkSpeed = 18 end
    hum.MoveToFinished:Connect(function() moving = false end)
end)

-- ============================================================================
-- STATE TRACKING
-- ============================================================================
local lastBallPos, lastBallT = nil, 0
local hadBall = false
local ballVisibleSince = 0
local lastBallVel = Vector3.zero
local lastDirectionFlip = 0
local lastPos = Vector3.zero
local lastSpeedT = tick()
local nextSprintPress = 0
local nextSprintJump = 0
local nextCloseJump = 0
local nextF = 0
local nextTrick = 0
local nextSlide = 0
local nextServePress = 0
local netCollisionTime = 0
local goalTarget = nil

local function setState(s)
    state = s
end

-- ============================================================================
-- ANTI-AFK (LIGHT)
-- ============================================================================
LP.Idled:Connect(function()
    local cam = workspace.CurrentCamera
    if cam then
        local cf = cam.CFrame
        cam.CFrame = CFrame.new(cf.Position, cf.Position + cf.LookVector + Vector3.new(frand(-0.005, 0.005), frand(-0.005, 0.005), frand(-0.005, 0.005)))
    end
end)

-- ============================================================================
-- MAIN LOOP
-- ============================================================================
RunService.Heartbeat:Connect(function(dt)
    dt = dt or 0.016

    local inLobby = isInLobby()
    if inLobby and not wasInLobby then
        enabledBeforeLobby = enabled
        enabled = false
    elseif not inLobby and wasInLobby then
        enabled = enabledBeforeLobby
    end
    wasInLobby = inLobby

    if not enabled then return end
    if inLobby then return end

    -- Auto B-spam
    if autoBSpam and tick() >= nextBSpam then
        tapKey(Enum.KeyCode.B)
        nextBSpam = tick() + vary(0.065, 0.25)
    end

    hum.PlatformStand = false
    hum.AutoRotate = true
    resolveHomeWaitIndex(false)

    local ball = getBall()
    local ballPresent = ball and ball.Parent ~= nil
    local now = tick()

    -- Goal line target (lazy)
    if ballPresent and toggles.showGoalLine then
        if not goalTarget or not goalTarget.Parent then
            goalTarget = findByNameCI(workspace, "Goal") or findByNameCI(workspace, "Gate")
        end
        if goalTarget and goalTarget:IsA("BasePart") then
            visuals.goalPart.CFrame = goalTarget.CFrame
            visuals.goalAtt.WorldPosition = goalTarget.Position
        else
            visuals.goalBeam.Enabled = false
        end
    end

    if not ballPresent then
        visuals.goalBeam.Enabled = false
        visuals.speedBeam.Enabled = false
    end

    -- Ball just appeared
    if ballPresent and not hadBall then
        ballVisibleSince = now
        currentGoal = nil
        moving = false
        lastBallVel = Vector3.zero
        if toggles.allowJump and isGrounded() then
            doJump()
            nextSprintJump = tick() + vary(config.sprintJumpInterval, 0.3)
            nextCloseJump = tick() + vary(config.closeJumpInterval, 0.3)
        end
        nextSprintPress = math.max(nextSprintPress, now + BALL_SPRINT_GRACE)
    end
    hadBall = ballPresent

    -- No ball
    if not ballPresent then
        lastBallPos, lastBallT = nil, 0
        ballVisibleSince, lastBallVel = 0, Vector3.zero
        currentGoalNetAllowance = HOME_NET_ALLOWANCE
        if state ~= "WAIT" then setState("WAIT") end
        goWait()
        return
    end

    -- Velocity calc
    local bpos = ball.Position
    local vel = Vector3.new()
    if lastBallPos and lastBallT > 0 then
        local dtn = now - lastBallT
        if dtn > 0 then vel = (bpos - lastBallPos) / dtn end
    end
    lastBallPos, lastBallT = bpos, now

    -- Direction flip detection
    local fv = flat(vel)
    local flv = flat(lastBallVel)
    if fv.Magnitude > 8 and flv.Magnitude > 8 and fv.Unit:Dot(flv.Unit) < -0.15 then
        currentGoal = nil
        moving = false
        lastDirectionFlip = now
        nextSprintPress = math.max(nextSprintPress, now + BALL_FLIP_SPRINT_GRACE)
    end
    lastBallVel = vel

    -- Goal guard
    local center = getMapCenter()
    local _, hl = getCourtHalfExtents()
    local bsc = flat(bpos - center):Dot(DIR)
    if toggles.enableGoalGuard and HOME_SIGN ~= 0 then
        if (HOME_SIGN > 0 and bsc < (-hl - 2)) or (HOME_SIGN < 0 and bsc > (hl + 2)) then
            if state ~= "WAIT" then setState("WAIT") end
            goWait(bpos)
            return
        end
    end

    local interceptPoint = getInterceptTarget(bpos, vel)
    drawPrediction(bpos, interceptPoint)

    local here = hrp.Position
    local hereXZ = flat(here)
    local ballXZ = flat(bpos)
    local distXZ = (ballXZ - hereXZ).Magnitude

    -- Serve state
    local inServe = isInServeBounds(bpos)
    if inServe and HOME_SIGN ~= 0 and sideSign(bpos) == HOME_SIGN then
        local serveHold = getHomeAnchor(nil, false)
        local serveAim = getServeAimPoint()
        if state ~= "SERVE" then setState("SERVE") end
        faceXZ(serveAim)
        requestMoveTo(serveHold, HOME_NET_ALLOWANCE)
        steerClose(serveHold)
        if distXZ <= config.autoHitDistance + 8 and tick() >= nextServePress then
            tapKey(Enum.KeyCode.F)
            nextServePress = tick() + vary(0.12, 0.35)
        end
        return
    end

    -- Chase
    local targetPoint = (distXZ > config.closeControlRadius) and interceptPoint or bpos
    targetPoint = clampToCourt(targetPoint, 2.2, 2.2)
    local targetDist = (flat(targetPoint) - hereXZ).Magnitude
    local incomingSpeed = getHomeIncomingSpeed(vel)
    local ballAge = (ballVisibleSince > 0) and (now - ballVisibleSince) or 0

    if toggles.autoFace then faceXZ(targetPoint) end

    if toggles.autoHit and distXZ <= config.autoHitDistance then
        if tick() >= nextF then
            tapKey(Enum.KeyCode.F)
            nextF = tick() + vary(config.kickDelay, 0.4)
        end
    end

    if distXZ <= config.closeControlRadius and toggles.allowJump and isGrounded() and tick() >= nextCloseJump then
        doJump()
        nextCloseJump = tick() + vary(config.closeJumpInterval, 0.25)
    end

    if distXZ <= config.closeControlRadius and not toggles.autoHit then
        if tick() >= nextSlide + vary(config.slideCooldown, 0.3) then
            doSlide()
            nextSlide = tick()
        end
        if tick() >= nextTrick + vary(config.trickCooldown, 0.35) then
            doTrick()
            nextTrick = tick()
        end
    end

    local ballSign = sideSign(bpos)
    local interceptSign = sideSign(interceptPoint)
    local onMyHalf = (HOME_SIGN ~= 0 and (ballSign == HOME_SIGN or interceptSign == HOME_SIGN))
    local shouldIntercept = onMyHalf or incomingSpeed > 8

    if shouldIntercept then
        sprintLogic(targetDist, incomingSpeed, distXZ, targetPoint, bpos, ballAge)
        if targetDist > config.moveNearDistance then
            requestMoveTo(targetPoint, INTERCEPT_NET_ALLOWANCE)
        end
        steerClose(targetPoint)
        if distXZ <= config.hitRange and ball.Size.X > 8.8 and ball.Size.Z > 8.8 then
            if state ~= "SPAM" then setState("SPAM") end
        else
            if state ~= "CHASE" then setState("CHASE") end
        end
    else
        if toggles.quickReturn then
            if state ~= "WAIT" then setState("WAIT") end
            goWait(bpos)
        end
    end

    -- Dead zone / stuck recovery
    if currentGoal then
        if (currentGoal - hrp.Position).Magnitude <= vary(config.deadZone, 0.3) then
            moving = false
        else
            if tick() - lastIssue >= 0.4 then requestMoveTo(currentGoal) end
        end
    end

    local s = hrp.Position
    local spd = ((s - lastPos).Magnitude) / math.max(0.0001, tick() - lastSpeedT)
    lastPos, lastSpeedT = s, tick()
    if spd < 0.15 and currentGoal and (currentGoal - hrp.Position).Magnitude > config.returnDistance then
        if toggles.allowJump and isGrounded() and math.random() < 0.6 then doJump() end
        if isNearNet() then
            local unstuck = getHomeAnchor(nil, false)
            requestMoveTo(unstuck, HOME_NET_ALLOWANCE)
            steerClose(unstuck)
        else
            requestMoveTo(currentGoal)
            steerClose(currentGoal)
        end
    end

    if state == "RETURN" then
        local wp = getHomeAnchor()
        goWait(wp)
        if (wp - hrp.Position).Magnitude <= config.returnDistance then setState("WAIT") end
    end
end)

-- ============================================================================
-- LAUNCH
-- ============================================================================
task.wait(1.5)
enabled = true
