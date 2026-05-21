-- 8 Ball Pool — Smooth Opponent Cue
-- Server replicates the opponent's cue-stick CFrame only every ~0.8 s
-- (see GameRunnerClient line 78: task.wait(0.8) before CueCommunication:FireServer).
-- This client-side script interpolates that CFrame on Heartbeat so the opponent's cue
-- appears to update at ~60 Hz instead of ~1.25 Hz.
-- Also re-broadcasts our own cue every 0.05 s so the opponent sees us smooth too.
--
-- Implementation notes:
--   * Both players' cue sticks are loose in Workspace as `DefaultCue` (or other skin name).
--   * When NOT a player's turn, their client moves their cue to (0,-100,0) (hidden).
--   * Our own cue is identified via the GuidelinesRunner module's `u5` upvalue
--     (which it stores as the active cue stick passed to Create).
--   * Interpolation only runs if the cue is "active" (near our table cue ball).
--   * Position jumps > 10 studs are SNAPS (show/hide) — not interpolated.

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local LocalPlayer          = Players.LocalPlayer

local INTERP_TIME          = 0.85   -- match server outbound interval
local OUTBOUND_INTERVAL    = 0.05   -- our resend rate
local NEAR_TABLE_RADIUS    = 25     -- studs from cue ball — only interpolate cues that are "on the table"
local TELEPORT_THRESHOLD   = 10     -- studs — jumps larger than this are snaps (show/hide)
local DEBUG                = false

local function log(...)
    if DEBUG then print("[SmoothCue]", ...) end
end

local localTable     = nil
local cueComm        = nil
local outboundActive = false
local heartbeatConn  = nil
local addedConn      = nil
local removingConn   = nil
local tracked        = {}

-- ---------- Cue identification ------------------------------------------------

-- Read OUR cue from GuidelinesRunner.u5 upvalue. This is set inside
-- u1.Create(p6, u7) → u5 = u7. We can fetch it via debug.getupvalue / getupvalues
-- depending on what the host exposes.
local function getOurCueFromGuidelines()
    local ok, gl = pcall(require, ReplicatedStorage:FindFirstChild("GuidelinesRunner"))
    if not ok or type(gl) ~= "table" or not gl.GetCueCF then return nil end
    -- Try executor-provided getupvalues first (Synapse/Krnl/etc.)
    local getupvs = rawget(getfenv(), "getupvalues") or rawget(getfenv(), "debug") and rawget(getfenv(), "debug").getupvalues
    if getupvs then
        local upvs = getupvs(gl.GetCueCF)
        if type(upvs) == "table" then
            for _, v in ipairs(upvs) do
                if typeof(v) == "Instance" and v:IsA("BasePart") then return v end
            end
        end
    end
    -- Fallback: debug.getupvalue (loop indices 1..16)
    if debug and debug.getupvalue then
        for i = 1, 16 do
            local ok2, name, val = pcall(debug.getupvalue, gl.GetCueCF, i)
            if not ok2 or name == nil then break end
            if typeof(val) == "Instance" and val:IsA("BasePart") then return val end
        end
    end
    -- Last resort: call GetCueCF and back-resolve via DescendantOf
    local cf = gl.GetCueCF()
    if cf then
        for _, p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") and p.CFrame == cf and p.Name:lower():find("cue") then
                return p
            end
        end
    end
    return nil
end

local function isCueStickName(part)
    if not part:IsA("BasePart") then return false end
    local n = part.Name:lower()
    if not n:find("cue") then return false end
    if part.Parent and part.Parent.Name == "Balls" then return false end -- cue ball
    local s = part.Size
    if math.max(s.X, s.Y, s.Z) < 3.0 then return false end
    if math.min(s.X, s.Y, s.Z) > 1.0 then return false end
    return true
end

local function tableCueBallPos()
    if not localTable then return nil end
    local cb = localTable:FindFirstChild("Balls") and localTable.Balls:FindFirstChild("Cue")
    return cb and cb.Position or nil
end

-- ---------- Tracking ----------------------------------------------------------

local function untrack(part)
    local e = tracked[part]
    if not e then return end
    if e.conn then e.conn:Disconnect() end
    tracked[part] = nil
    log("Untrack", part and part.Name)
end

local function track(part)
    if tracked[part] then return end
    local entry = {
        targetCF      = part.CFrame,
        oldCF         = part.CFrame,
        lastInterpCF  = part.CFrame,
        startTime     = 0,
        suppress      = false,
        conn          = nil,
    }
    tracked[part] = entry
    entry.conn = part:GetPropertyChangedSignal("CFrame"):Connect(function()
        if entry.suppress then return end
        if part.Parent == nil then untrack(part); return end
        local newPos = part.Position
        local oldPos = entry.lastInterpCF.Position
        if (newPos - oldPos).Magnitude > TELEPORT_THRESHOLD then
            -- Show/hide jump — don't interpolate, just snap
            entry.lastInterpCF = part.CFrame
            entry.oldCF        = part.CFrame
            entry.targetCF     = part.CFrame
            entry.startTime    = 0
            return
        end
        entry.oldCF     = entry.lastInterpCF
        entry.targetCF  = part.CFrame
        entry.startTime = os.clock()
    end)
    log("Track", part:GetFullName())
end

-- Identify our own cue dynamically — recompute when needed.
-- We re-read the upvalue each time because between matches it may change.
local function isOurCue(part)
    local ours = getOurCueFromGuidelines()
    return ours == part
end

-- Heartbeat: only interpolate cues that are (1) currently near our table and
-- (2) not our own cue (which is already 60-Hz local-driven).
heartbeatConn = RunService.Heartbeat:Connect(function()
    local centerPos = tableCueBallPos()
    if not centerPos then return end
    local ours = getOurCueFromGuidelines()
    for part, e in pairs(tracked) do
        if part.Parent == nil then
            untrack(part)
        else
            local nearTable = (part.Position - centerPos).Magnitude <= NEAR_TABLE_RADIUS
            if not nearTable or part == ours then
                -- Update lastInterpCF so future re-entry doesn't snap from stale value
                e.lastInterpCF = part.CFrame
                e.oldCF        = part.CFrame
                e.targetCF     = part.CFrame
                e.startTime    = 0
            elseif e.startTime > 0 then
                local alpha = math.min((os.clock() - e.startTime) / INTERP_TIME, 1)
                local interp = e.oldCF:Lerp(e.targetCF, alpha)
                e.suppress = true
                part.CFrame = interp
                e.suppress = false
                e.lastInterpCF = interp
                if alpha >= 1 then e.startTime = 0 end
            end
        end
    end
end)

-- ---------- Outbound speed-up -------------------------------------------------

local function startOutbound()
    if outboundActive then return end
    outboundActive = true
    task.spawn(function()
        local lastCF = nil
        while outboundActive do
            task.wait(OUTBOUND_INTERVAL)
            if not (cueComm and cueComm.Parent) then outboundActive = false; return end
            local our = getOurCueFromGuidelines()
            if our and our.Parent then
                local cf = our.CFrame
                if cf ~= lastCF then
                    pcall(function() cueComm:FireServer(our, cf) end)
                    lastCF = cf
                end
            end
        end
    end)
end

-- ---------- Attach / detach ---------------------------------------------------

local function clearAll()
    for part in pairs(tracked) do untrack(part) end
    outboundActive = false
    localTable, cueComm = nil, nil
end

local function detectCurrentTable()
    local char = LocalPlayer.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head"))
    if not root then return nil end
    local myPos = root.Position
    local best, bestDist = nil, math.huge
    for _, container in ipairs({workspace:FindFirstChild("ClassicTables"), workspace:FindFirstChild("CompetitiveTables")}) do
        if container then
            for _, t in ipairs(container:GetChildren()) do
                local cb = t:FindFirstChild("Balls") and t.Balls:FindFirstChild("Cue")
                if cb then
                    local d = (cb.Position - myPos).Magnitude
                    if d < bestDist then bestDist = d; best = t end
                end
            end
        end
    end
    return best, bestDist
end

local function attach(tbl)
    clearAll()
    if not tbl then tbl = detectCurrentTable() end
    if not tbl then warn("[SmoothCue] No active table detected — are you in a match?"); return end
    localTable = tbl
    cueComm    = tbl:FindFirstChild("_GameData") and tbl._GameData:FindFirstChild("CueCommunication") or nil
    log("Attached to", tbl:GetFullName())

    -- Track every loose cue stick in workspace (top-level) — these are the ones
    -- that get teleported between (0,-100,0) and the active table during play.
    for _, p in ipairs(workspace:GetDescendants()) do
        if isCueStickName(p) then track(p) end
    end

    startOutbound()
    log(("Tracking %d candidate cue(s). Outbound: %s"):format(
        (function() local n=0 for _ in pairs(tracked) do n=n+1 end return n end)(),
        outboundActive and "ON" or "OFF"))
end

local function status()
    local ours = getOurCueFromGuidelines()
    print(("[SmoothCue] table=%s cueComm=%s outbound=%s tracked=%d ourCue=%s"):format(
        tostring(localTable and localTable:GetFullName()),
        tostring(cueComm and cueComm:GetFullName()),
        outboundActive and "ON" or "OFF",
        (function() local n=0 for _ in pairs(tracked) do n=n+1 end return n end)(),
        tostring(ours and ours:GetFullName())))
end

local function detach()
    if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
    if addedConn then addedConn:Disconnect(); addedConn = nil end
    if removingConn then removingConn:Disconnect(); removingConn = nil end
    clearAll()
    log("Detached.")
end

-- Watch for new cue parts (in case of match start / model swap)
addedConn = workspace.DescendantAdded:Connect(function(d)
    if not localTable then return end
    if d:IsA("BasePart") and d.Name:lower():find("cue") then
        task.wait(0.05)
        if isCueStickName(d) then track(d) end
    end
end)
removingConn = workspace.DescendantRemoving:Connect(function(d)
    if tracked[d] then untrack(d) end
end)

-- Hook GameStartClient for auto-attach on next match
local gscEvents = ReplicatedStorage:FindFirstChild("Events")
local gsc       = gscEvents and gscEvents:FindFirstChild("GameStartClient")
if gsc then
    gsc.OnClientEvent:Connect(function(_, _, gameData)
        local tbl = gameData and gameData.Parent or nil
        task.wait(0.3)
        attach(tbl)
    end)
end

_G.SmoothCue = {
    attach   = attach,
    detach   = detach,
    status   = status,
    setDebug = function(v) DEBUG = v end,
    INTERP_TIME = INTERP_TIME,
    OUTBOUND_INTERVAL = OUTBOUND_INTERVAL,
}

print(("[SmoothCue] Loaded. INTERP=%.2fs, OUTBOUND=%.2fs, NEAR=%d studs, TELEPORT=%d studs."):format(
    INTERP_TIME, OUTBOUND_INTERVAL, NEAR_TABLE_RADIUS, TELEPORT_THRESHOLD))
attach()
