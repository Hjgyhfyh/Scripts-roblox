local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local UserInputService=game:GetService("UserInputService")
local HttpService=game:GetService("HttpService")
local VIM=pcall(function()return game:GetService("VirtualInputManager")end) and game:GetService("VirtualInputManager") or nil
local LocalPlayer=Players.LocalPlayer

pcall(function()
    local pg=LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local old=(pg and pg:FindFirstChild("Helper_UI")) or (game:GetService("CoreGui"):FindFirstChild("Helper_UI"))
    if old then old:Destroy() end
end)

local function getChar()
    local c=LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    c:WaitForChild("Humanoid")
    c:WaitForChild("HumanoidRootPart")
    return c
end

local c
local hum
local hrp

local function findByNameCI(root,name)
    if not root then return nil end
    local ln=string.lower(name)
    for _,ch in ipairs(root:GetChildren()) do
        if string.lower(ch.Name)==ln then return ch end
    end
    for _,ch in ipairs(root:GetChildren()) do
        local f=findByNameCI(ch,name)
        if f then return f end
    end
    return nil
end

local trackedBall=nil
local trackedBallConn=nil
local nextBallSearch=0
local BALL_SEARCH_INTERVAL=0.35

local function bindBall(ball)
    if trackedBallConn then
        trackedBallConn:Disconnect()
        trackedBallConn=nil
    end
    trackedBall=ball
    if trackedBall then
        trackedBallConn=trackedBall.AncestryChanged:Connect(function(_,parent)
            if not parent then
                bindBall(nil)
            end
        end)
    end
end

local function considerBallCandidate(inst)
    if inst and string.lower(inst.Name)=="ballshadow" then
        bindBall(inst)
    end
end

workspace.DescendantAdded:Connect(function(inst)
    if trackedBall and trackedBall.Parent then return end
    considerBallCandidate(inst)
end)

local function locateBall()
    local fx=workspace:FindFirstChild("fx") or workspace:FindFirstChild("Fx") or workspace:FindFirstChild("FX")
    local candidate=nil
    if fx then
        candidate=fx:FindFirstChild("BallShadow") or fx:FindFirstChild("ballshadow") or findByNameCI(fx,"BallShadow")
    end
    if not candidate then
        candidate=findByNameCI(workspace,"BallShadow")
    end
    bindBall(candidate)
end

local function getBall()
    if trackedBall and trackedBall.Parent then
        return trackedBall
    end
    if time()<nextBallSearch then
        return nil
    end
    nextBallSearch=time()+BALL_SEARCH_INTERVAL
    locateBall()
    return trackedBall
end

local function tapKey(code)
    if VIM then
        VIM:SendKeyEvent(true,code,false,game)
        task.wait(0.01)
        VIM:SendKeyEvent(false,code,false,game)
    else
        UserInputService:SendKeyEvent(true,code,false,game)
        task.wait(0.01)
        UserInputService:SendKeyEvent(false,code,false,game)
    end
end

local currentCourtNumber=1

local function detectCurrentCourt()
    local c=LocalPlayer.Character
    if not c then return currentCourtNumber end
    local hrp=c:FindFirstChild("HumanoidRootPart")
    if not hrp then return currentCourtNumber end
    local pos=hrp.Position
    local courts=workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if not courts then return currentCourtNumber end
    local bestCourt=1
    local bestDist=math.huge
    for i=1,5 do
        local courtFolder=courts:FindFirstChild(tostring(i))
        if courtFolder then
            local map=courtFolder:FindFirstChild("Map")
            if map then
                local floor=map:FindFirstChild("OccludeFloor")
                if floor and floor:IsA("BasePart") then
                    local dist=(pos-floor.Position).Magnitude
                    if dist<bestDist then
                        bestDist=dist
                        bestCourt=i
                    end
                end
            end
        end
    end
    currentCourtNumber=bestCourt
    return currentCourtNumber
end

local function getMapCenter()
    local courtNum=detectCurrentCourt()
    local courts=workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if courts then
        local courtFolder=courts:FindFirstChild(tostring(courtNum))
        if courtFolder then
            local map=courtFolder:FindFirstChild("Map")
            if map then
                local floor=map:FindFirstChild("OccludeFloor")
                if floor and floor:IsA("BasePart") then
                    return floor.Position
                end
            end
        end
    end
    return Vector3.new(-54,-511,-72)
end

local function getTeamSpawns()
    local blueSpawn=Vector3.new(-54,-511,-41)
    local redSpawn=Vector3.new(-54,-511,-103)
    local courtNum=detectCurrentCourt()
    local courts=workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if courts then
        local courtFolder=courts:FindFirstChild(tostring(courtNum))
        if courtFolder then
            local map=courtFolder:FindFirstChild("Map")
            if map then
                local spawns1=map:FindFirstChild("Spawns1") or map:FindFirstChild("Spawns")
                if spawns1 then
                    local s1=spawns1:FindFirstChild("1")
                    if s1 and s1:IsA("BasePart") then
                        blueSpawn=s1.Position
                    elseif s1 then
                        local s11=s1:FindFirstChild("1")
                        if s11 and s11:IsA("BasePart") then
                            blueSpawn=s11.Position
                        end
                    end
                end
                local spawns2=map:FindFirstChild("Spawns2")
                if spawns2 then
                    local s2=spawns2:FindFirstChild("1")
                    if s2 and s2:IsA("BasePart") then
                        redSpawn=s2.Position
                    elseif s2 then
                        local s21=s2:FindFirstChild("1")
                        if s21 and s21:IsA("BasePart") then
                            redSpawn=s21.Position
                        end
                    end
                end
            end
        end
    end
    return blueSpawn,redSpawn
end

local function getServeBounds()
    local bounds={}
    local courts=workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if courts then
        for _,courtFolder in ipairs(courts:GetChildren()) do
            if courtFolder:IsA("Folder") or courtFolder:IsA("Model") then
                local map=courtFolder:FindFirstChild("Map")
                if map then
                    local serveBounds=map:FindFirstChild("ServeBounds")
                    if serveBounds then
                        for _,folder in ipairs(serveBounds:GetChildren()) do
                            if folder:IsA("Folder") or folder:IsA("Model") then
                                local part=folder:FindFirstChild("Part")
                                if part and part:IsA("BasePart") then
                                    table.insert(bounds,part)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return bounds
end

local function isInLobby()
    local c=LocalPlayer.Character
    if not c then return true end
    local hrp=c:FindFirstChild("HumanoidRootPart")
    if not hrp then return true end
    local pos=hrp.Position
    if pos.Y>-480 and pos.Y<-440 then
        if pos.X>80 and pos.X<260 and pos.Z>-140 and pos.Z<0 then
            return true
        end
    end
    local courts=workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if not courts then return true end
    local foundCourt=false
    for i=1,5 do
        local courtFolder=courts:FindFirstChild(tostring(i))
        if courtFolder then
            local map=courtFolder:FindFirstChild("Map")
            if map then
                local floor=map:FindFirstChild("OccludeFloor")
                if floor and floor:IsA("BasePart") then
                    local dist=(pos-floor.Position).Magnitude
                    if dist<150 then
                        foundCourt=true
                        break
                    end
                end
            end
        end
    end
    if not foundCourt then return true end
    return false
end

local function isInServeBounds(pos,myTeamBlue)
    local bounds=getServeBounds()
    for _,part in ipairs(bounds) do
        local size=part.Size
        local cf=part.CFrame
        local localPos=cf:PointToObjectSpace(pos)
        if math.abs(localPos.X)<=size.X/2 and math.abs(localPos.Y)<=size.Y/2 and math.abs(localPos.Z)<=size.Z/2 then
            return true,part
        end
    end
    return false,nil
end

local WAIT_POINTS={Vector3.new(-54,-511,-41),Vector3.new(-54,-511,-103)}
local MID=Vector3.new(-54,-511,-72)
local DIR=Vector3.new(0,0,1)
local lastMapUpdate=0
local MAP_UPDATE_INTERVAL=0.5
local predictLead
local HOME_SIGN=0
local IS_BLUE=false
local TEAM_BOUNDARY_Z=-146
local homeWaitIndex=1

local function flat(v)
    return Vector3.new(v.X,0,v.Z)
end

local function updateMapData()
    if time()-lastMapUpdate<MAP_UPDATE_INTERVAL then return end
    lastMapUpdate=time()
    local blueSpawn,redSpawn=getTeamSpawns()
    WAIT_POINTS[1]=blueSpawn
    WAIT_POINTS[2]=redSpawn
    MID=getMapCenter()
    local diff=flat(WAIT_POINTS[1]-WAIT_POINTS[2])
    if diff.Magnitude>1e-4 then
        DIR=diff.Unit
    else
        DIR=Vector3.new(0,0,1)
    end
end

local function sideSign(pos)
    local d=flat(pos-MID):Dot(DIR)
    if d>0 then
        return 1
    elseif d<0 then
        return -1
    end
    return 0
end

local function getCurrentCourtMap()
    local courtNum=detectCurrentCourt()
    local courts=workspace:FindFirstChild("Courts") or workspace:FindFirstChild("Courts1")
    if not courts then return nil end
    local courtFolder=courts:FindFirstChild(tostring(courtNum))
    if not courtFolder then return nil end
    return courtFolder:FindFirstChild("Map")
end

local function getLaneDir()
    local lane=Vector3.new(-DIR.Z,0,DIR.X)
    if lane.Magnitude>1e-4 then
        return lane.Unit
    end
    return Vector3.new(1,0,0)
end

local function getCourtHalfExtents()
    local halfWidth=18
    local halfLength=31
    local map=getCurrentCourtMap()
    if not map then
        return halfWidth,halfLength
    end
    local floor=map:FindFirstChild("OccludeFloor")
    if not floor or not floor:IsA("BasePart") then
        return halfWidth,halfLength
    end
    local right=flat(floor.CFrame.RightVector)
    local look=flat(floor.CFrame.LookVector)
    if right.Magnitude<=1e-4 or look.Magnitude<=1e-4 then
        return halfWidth,halfLength
    end
    right=right.Unit
    look=look.Unit
    local laneDir=getLaneDir()
    local sideDir=DIR
    halfWidth=math.abs(laneDir:Dot(right))*floor.Size.X*0.5+math.abs(laneDir:Dot(look))*floor.Size.Z*0.5
    halfLength=math.abs(sideDir:Dot(right))*floor.Size.X*0.5+math.abs(sideDir:Dot(look))*floor.Size.Z*0.5
    return math.max(8,halfWidth-2.75),math.max(10,halfLength-2.5)
end

local function resolveHomeWaitIndex(force)
    updateMapData()
    if not hrp or not hrp.Parent then
        return homeWaitIndex
    end
    local pos=hrp.Position
    local d1=(pos-WAIT_POINTS[1]).Magnitude
    local d2=(pos-WAIT_POINTS[2]).Magnitude
    local suggested=(d1<=d2) and 1 or 2
    if force or not homeWaitIndex then
        homeWaitIndex=suggested
    end
    IS_BLUE=homeWaitIndex==1
    HOME_SIGN=sideSign(WAIT_POINTS[homeWaitIndex])
    TEAM_BOUNDARY_Z=IS_BLUE and -146 or 7
    return homeWaitIndex
end

local function getHomeBase()
    resolveHomeWaitIndex(false)
    return WAIT_POINTS[homeWaitIndex or 1]
end

local function getHomeDefendDepth()
    local center=getMapCenter()
    local depth=math.abs(flat(getHomeBase()-center):Dot(DIR))
    return math.max(8,depth-4)
end

local function clampToCourt(pos,lanePadding,sidePadding)
    updateMapData()
    local center=getMapCenter()
    local laneDir=getLaneDir()
    local sideDir=DIR
    local halfWidth,halfLength=getCourtHalfExtents()
    local offset=flat(pos-center)
    local lane=offset:Dot(laneDir)
    local side=offset:Dot(sideDir)
    local safeLane=math.max(4,halfWidth-(lanePadding or 0))
    local safeSide=math.max(6,halfLength-(sidePadding or 0))
    lane=math.clamp(lane,-safeLane,safeLane)
    side=math.clamp(side,-safeSide,safeSide)
    return Vector3.new(center.X,pos.Y,center.Z)+laneDir*lane+sideDir*side
end

local function getHomeAnchor(referencePos,trackLane)
    updateMapData()
    local homeBase=getHomeBase()
    local center=getMapCenter()
    local laneDir=getLaneDir()
    local sideDir=DIR
    local halfWidth,halfLength=getCourtHalfExtents()
    local lane=flat(homeBase-center):Dot(laneDir)
    if trackLane and referencePos then
        local refLane=flat(referencePos-center):Dot(laneDir)
        lane=lane+(refLane-lane)*0.45
    end
    lane=math.clamp(lane,-math.max(6,halfWidth-3),math.max(6,halfWidth-3))
    local homeSide=HOME_SIGN
    if homeSide==0 then
        homeSide=sideSign(homeBase)
    end
    if homeSide==0 then
        homeSide=(homeWaitIndex==1) and 1 or -1
    end
    local baseSide=math.abs(flat(homeBase-center):Dot(sideDir))
    local side=homeSide*math.min(math.max(8,baseSide),math.max(10,halfLength-3))
    return clampToCourt(Vector3.new(center.X,homeBase.Y,center.Z)+laneDir*lane+sideDir*side,2.5,2.5)
end

local function getHomeIncomingSpeed(vel)
    if HOME_SIGN==0 then
        return 0
    end
    return flat(vel):Dot(DIR)*HOME_SIGN
end

local function clampGoalSide(side,halfLength,crossAllowance)
    local sideLimit=math.max(8,halfLength-1.75)
    local enemyAllowance=crossAllowance or 0.75
    if HOME_SIGN>0 then
        return math.clamp(side,-enemyAllowance,sideLimit)
    elseif HOME_SIGN<0 then
        return math.clamp(side,-sideLimit,enemyAllowance)
    end
    return math.clamp(side,-sideLimit,sideLimit)
end

local function getInterceptTarget(bpos,vel)
    updateMapData()
    local center=getMapCenter()
    local laneDir=getLaneDir()
    local sideDir=DIR
    local target=predictLead(bpos,vel)
    local incomingSpeed=getHomeIncomingSpeed(vel)
    local halfWidth,halfLength=getCourtHalfExtents()
    local laneLimit=math.max(6,halfWidth-2.5)
    local ballLane=flat(bpos-center):Dot(laneDir)
    local predictedLane=flat(target-center):Dot(laneDir)
    local ballSide=flat(bpos-center):Dot(sideDir)
    local predictedSide=flat(target-center):Dot(sideDir)
    local flatSpeed=flat(vel).Magnitude
    local chaseBlend=math.clamp(0.88+flatSpeed/120,0.88,1)
    local threat=(HOME_SIGN~=0 and (sideSign(bpos)==HOME_SIGN or sideSign(target)==HOME_SIGN or incomingSpeed>6))
    local lane
    local side
    if threat then
        lane=ballLane+(predictedLane-ballLane)*chaseBlend
        side=ballSide+(predictedSide-ballSide)*chaseBlend
        side=clampGoalSide(side,halfLength,2.75)
    else
        local anchor=getHomeAnchor(target,true)
        lane=flat(anchor-center):Dot(laneDir)
        side=flat(anchor-center):Dot(sideDir)
    end
    lane=math.clamp(lane,-laneLimit,laneLimit)
    target=Vector3.new(center.X,bpos.Y,center.Z)+laneDir*lane+sideDir*side
    return clampToCourt(target,2.2,2.2)
end

local function getServeAimPoint()
    updateMapData()
    local center=getMapCenter()
    local laneDir=getLaneDir()
    local sideDir=DIR
    local halfWidth,halfLength=getCourtHalfExtents()
    local enemySide=-HOME_SIGN
    if enemySide==0 then
        enemySide=(homeWaitIndex==1) and -1 or 1
    end
    local lane=math.clamp(flat(hrp.Position-center):Dot(laneDir),-math.max(6,halfWidth-4),math.max(6,halfWidth-4))
    lane=math.clamp(lane*1.35,-math.max(7,halfWidth-2.75),math.max(7,halfWidth-2.75))
    local side=enemySide*math.max(10,halfLength-5)
    return clampToCourt(Vector3.new(center.X,hrp.Position.Y,center.Z)+laneDir*lane+sideDir*side,2.2,2.2)
end

local config={
    sprintRadius=15,
    closeControlRadius=7,
    shootDistance=22,
    kickDelay=0.01,
    sprintSpamInterval=0.06,
    sprintJumpInterval=0.28,
    closeJumpInterval=0.22,
    predictionLeadMin=0.16,
    predictionLeadScale=0.26,
    predictionLeadMax=0.46,
    moveNearDistance=2,
    deadZone=0.5,
    minReissueDistance=0.75,
    minReissueTime=0.05,
    autoHitDistance=10,
    hitRange=10,
    returnDistance=5,
    trickCooldown=0.8,
    slideCooldown=0.8,
    focusLerp=0.35,
    orbitBrightness=0.35,
    billboardSize=3.5
}

local toggles={
    allowJump=true,
    allowSprint=true,
    allowSlide=true,
    allowTrick=true,
    autoFace=true,
    autoHit=true,
    quickReturn=true,
    enableGoalGuard=true,
    showBillboard=true,
    showAim=true,
    showTrail=true,
    showSprintRing=false,
    showGoalLine=false,
    showBallLine=true,
    showSpeedArrow=true,
    floatingGlow=true
}

local enabled=false
local toggleKey=Enum.KeyCode.G
local autoBSpam=false
local autoBInterval=0.065
local nextBSpam=0
local visualsDirty=true
local wasInLobby=false
local enabledBeforeLobby=false

local palette={
    primary=Color3.fromRGB(245,210,62),
    accent=Color3.fromRGB(255,244,196)
}

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "tg: @sigmatik323",
    LoadingTitle = "tg: @sigmatik323",
    LoadingSubtitle = "by sigmatik323",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "RocketRivals",
        FileName = "Config"
    },
    KeySystem = false
})

local ParametersTab = Window:CreateTab("Parameters", "sliders")
local ModesTab = Window:CreateTab("Modes", "toggle-left")
local VisualsTab = Window:CreateTab("Visuals", "eye")
local SettingsTab = Window:CreateTab("Settings", "settings")

ParametersTab:CreateSection("Movement")

ParametersTab:CreateSlider({
    Name = "Sprint Radius",
    Range = {4, 40},
    Increment = 1,
    CurrentValue = config.sprintRadius,
    Flag = "sprintRadius",
    Callback = function(v) config.sprintRadius=v visualsDirty=true end
})

ParametersTab:CreateSlider({
    Name = "Close Control Radius",
    Range = {2, 15},
    Increment = 1,
    CurrentValue = config.closeControlRadius,
    Flag = "closeControlRadius",
    Callback = function(v) config.closeControlRadius=v end
})

ParametersTab:CreateSlider({
    Name = "Shoot Distance",
    Range = {6, 40},
    Increment = 1,
    CurrentValue = config.shootDistance,
    Flag = "shootDistance",
    Callback = function(v) config.shootDistance=v end
})

ParametersTab:CreateSlider({
    Name = "Auto Hit Distance",
    Range = {2, 30},
    Increment = 1,
    CurrentValue = config.autoHitDistance,
    Flag = "autoHitDistance",
    Callback = function(v) config.autoHitDistance=v end
})

ParametersTab:CreateSlider({
    Name = "Hit Range",
    Range = {4, 24},
    Increment = 1,
    CurrentValue = config.hitRange,
    Flag = "hitRange",
    Callback = function(v) config.hitRange=v end
})

ParametersTab:CreateSection("Timing")

ParametersTab:CreateSlider({
    Name = "Sprint Interval",
    Range = {2, 25},
    Increment = 1,
    Suffix = "ms",
    CurrentValue = math.floor(config.sprintSpamInterval*100),
    Flag = "sprintInterval",
    Callback = function(v) config.sprintSpamInterval=v/100 end
})

ParametersTab:CreateSlider({
    Name = "Sprint Jump Interval",
    Range = {12, 60},
    Increment = 1,
    Suffix = "ms",
    CurrentValue = math.floor(config.sprintJumpInterval*100),
    Flag = "sprintJump",
    Callback = function(v) config.sprintJumpInterval=v/100 end
})

ParametersTab:CreateSlider({
    Name = "Close Jump Interval",
    Range = {8, 60},
    Increment = 1,
    Suffix = "ms",
    CurrentValue = math.floor(config.closeJumpInterval*100),
    Flag = "closeJump",
    Callback = function(v) config.closeJumpInterval=v/100 end
})

ParametersTab:CreateSection("Prediction")

ParametersTab:CreateSlider({
    Name = "Prediction Lead Min",
    Range = {5, 50},
    Increment = 1,
    Suffix = "%",
    CurrentValue = math.floor(config.predictionLeadMin*100),
    Flag = "predMin",
    Callback = function(v) config.predictionLeadMin=v/100 end
})

ParametersTab:CreateSlider({
    Name = "Prediction Lead Scale",
    Range = {5, 60},
    Increment = 1,
    Suffix = "%",
    CurrentValue = math.floor(config.predictionLeadScale*100),
    Flag = "predScale",
    Callback = function(v) config.predictionLeadScale=v/100 end
})

ParametersTab:CreateSlider({
    Name = "Prediction Lead Max",
    Range = {10, 80},
    Increment = 1,
    Suffix = "%",
    CurrentValue = math.floor(config.predictionLeadMax*100),
    Flag = "predMax",
    Callback = function(v) config.predictionLeadMax=v/100 end
})

ParametersTab:CreateSection("Other")

ParametersTab:CreateSlider({
    Name = "Move Near Distance",
    Range = {1, 6},
    Increment = 1,
    CurrentValue = config.moveNearDistance,
    Flag = "moveNear",
    Callback = function(v) config.moveNearDistance=v end
})

ParametersTab:CreateSlider({
    Name = "Dead Zone",
    Range = {1, 20},
    Increment = 1,
    Suffix = "/10",
    CurrentValue = math.floor(config.deadZone*10),
    Flag = "deadZone",
    Callback = function(v) config.deadZone=v/10 end
})

ParametersTab:CreateSlider({
    Name = "Return Distance",
    Range = {1, 12},
    Increment = 1,
    CurrentValue = config.returnDistance,
    Flag = "returnDist",
    Callback = function(v) config.returnDistance=v end
})

ParametersTab:CreateSlider({
    Name = "Focus Lerp",
    Range = {5, 80},
    Increment = 1,
    Suffix = "%",
    CurrentValue = math.floor(config.focusLerp*100),
    Flag = "focusLerp",
    Callback = function(v) config.focusLerp=v/100 end
})

ParametersTab:CreateSlider({
    Name = "Trick Cooldown",
    Range = {2, 25},
    Increment = 1,
    Suffix = "/10s",
    CurrentValue = math.floor(config.trickCooldown*10),
    Flag = "trickCd",
    Callback = function(v) config.trickCooldown=v/10 end
})

ParametersTab:CreateSlider({
    Name = "Slide Cooldown",
    Range = {2, 25},
    Increment = 1,
    Suffix = "/10s",
    CurrentValue = math.floor(config.slideCooldown*10),
    Flag = "slideCd",
    Callback = function(v) config.slideCooldown=v/10 end
})

ParametersTab:CreateSlider({
    Name = "Billboard Size",
    Range = {2, 6},
    Increment = 1,
    CurrentValue = math.floor(config.billboardSize),
    Flag = "billboardSize",
    Callback = function(v) config.billboardSize=v visualsDirty=true end
})

ParametersTab:CreateSlider({
    Name = "Orbit Brightness",
    Range = {10, 100},
    Increment = 5,
    Suffix = "%",
    CurrentValue = math.floor(config.orbitBrightness*100),
    Flag = "orbitBright",
    Callback = function(v) config.orbitBrightness=v/100 visualsDirty=true end
})

ModesTab:CreateSection("Bot Modes")

ModesTab:CreateToggle({
    Name = "Allow Jump",
    CurrentValue = toggles.allowJump,
    Flag = "allowJump",
    Callback = function(v) toggles.allowJump=v end
})

ModesTab:CreateToggle({
    Name = "Allow Sprint",
    CurrentValue = toggles.allowSprint,
    Flag = "allowSprint",
    Callback = function(v) toggles.allowSprint=v end
})

ModesTab:CreateToggle({
    Name = "Allow Slide",
    CurrentValue = toggles.allowSlide,
    Flag = "allowSlide",
    Callback = function(v) toggles.allowSlide=v end
})

ModesTab:CreateToggle({
    Name = "Allow Trick",
    CurrentValue = toggles.allowTrick,
    Flag = "allowTrick",
    Callback = function(v) toggles.allowTrick=v end
})

ModesTab:CreateToggle({
    Name = "Auto Face",
    CurrentValue = toggles.autoFace,
    Flag = "autoFace",
    Callback = function(v) toggles.autoFace=v end
})

ModesTab:CreateToggle({
    Name = "Auto Hit",
    CurrentValue = toggles.autoHit,
    Flag = "autoHit",
    Callback = function(v) toggles.autoHit=v end
})

ModesTab:CreateToggle({
    Name = "Quick Return",
    CurrentValue = toggles.quickReturn,
    Flag = "quickReturn",
    Callback = function(v) toggles.quickReturn=v end
})

ModesTab:CreateToggle({
    Name = "Goal Guard",
    CurrentValue = toggles.enableGoalGuard,
    Flag = "goalGuard",
    Callback = function(v) toggles.enableGoalGuard=v end
})

VisualsTab:CreateSection("Visual Settings")

VisualsTab:CreateToggle({
    Name = "Show Billboard",
    CurrentValue = toggles.showBillboard,
    Flag = "showBillboard",
    Callback = function(v) toggles.showBillboard=v visualsDirty=true end
})

VisualsTab:CreateToggle({
    Name = "Show Aim",
    CurrentValue = toggles.showAim,
    Flag = "showAim",
    Callback = function(v) toggles.showAim=v visualsDirty=true end
})

VisualsTab:CreateToggle({
    Name = "Show Trail",
    CurrentValue = toggles.showTrail,
    Flag = "showTrail",
    Callback = function(v) toggles.showTrail=v visualsDirty=true end
})

VisualsTab:CreateToggle({
    Name = "Show Sprint Ring",
    CurrentValue = toggles.showSprintRing,
    Flag = "showSprintRing",
    Callback = function(v) toggles.showSprintRing=v visualsDirty=true end
})

VisualsTab:CreateToggle({
    Name = "Show Goal Line (WARNING: LAG)",
    CurrentValue = toggles.showGoalLine,
    Flag = "showGoalLine",
    Callback = function(v) toggles.showGoalLine=v visualsDirty=true end
})

VisualsTab:CreateToggle({
    Name = "Show Ball Line",
    CurrentValue = toggles.showBallLine,
    Flag = "showBallLine",
    Callback = function(v) toggles.showBallLine=v visualsDirty=true end
})

VisualsTab:CreateToggle({
    Name = "Show Speed Arrow",
    CurrentValue = toggles.showSpeedArrow,
    Flag = "showSpeedArrow",
    Callback = function(v) toggles.showSpeedArrow=v visualsDirty=true end
})

VisualsTab:CreateToggle({
    Name = "Floating Glow",
    CurrentValue = toggles.floatingGlow,
    Flag = "floatingGlow",
    Callback = function(v) toggles.floatingGlow=v visualsDirty=true end
})

SettingsTab:CreateSection("Controls")

SettingsTab:CreateKeybind({
    Name = "Toggle Bot",
    CurrentKeybind = "",
    HoldToInteract = false,
    Flag = "toggleBotKey",
    Callback = function()
        if enabled then
            enabled=false
            Rayfield:Notify({Title="Bot",Content="Disabled",Duration=2})
        else
            enabled=true
            Rayfield:Notify({Title="Bot",Content="Enabled",Duration=2})
        end
    end
})

SettingsTab:CreateToggle({
    Name = "Auto B-Spam",
    CurrentValue = autoBSpam,
    Flag = "autoBSpam",
    Callback = function(v) autoBSpam=v if v then nextBSpam=0 end end
})

SettingsTab:CreateToggle({
    Name = "Bot Enabled",
    CurrentValue = enabled,
    Flag = "botEnabled",
    Callback = function(v) enabled=v end
})

SettingsTab:CreateSection("Configuration")

SettingsTab:CreateButton({
    Name = "Reset All Settings",
    Callback = function()
        Rayfield:Notify({Title="Reset",Content="Resetting all settings...",Duration=2})
        pcall(function()
            local folder="RocketRivals"
            if delfile then
                pcall(function() delfile(folder.."/Config.json") end)
            end
            if delfolder then
                pcall(function() delfolder(folder) end)
            end
        end)
        Rayfield:Notify({Title="Reset",Content="Settings reset! Rejoin to apply.",Duration=3})
    end
})

c=getChar()
hum=c:WaitForChild("Humanoid")
hrp=c:WaitForChild("HumanoidRootPart")
resolveHomeWaitIndex(true)
hum.PlatformStand=false
hum.AutoRotate=true
pcall(function() hum.UseJumpPower=true hum.JumpPower=math.max(hum.JumpPower,50) end)
if hum.WalkSpeed<16 then hum.WalkSpeed=18 end

local visuals={}

visuals.billboard=Instance.new("BillboardGui")
visuals.billboard.Size=UDim2.new(0,0,0,0)
visuals.billboard.StudsOffset=Vector3.new(0,config.billboardSize,0)
visuals.billboard.AlwaysOnTop=true
visuals.billboard.Enabled=toggles.showBillboard
visuals.billboard.Parent=hrp

visuals.stateText=Instance.new("TextLabel")
visuals.stateText.Size=UDim2.new(1,0,1,0)
visuals.stateText.BackgroundTransparency=1
visuals.stateText.TextScaled=true
visuals.stateText.Font=Enum.Font.GothamBold
visuals.stateText.TextColor3=Color3.new(1,1,1)
visuals.stateText.TextStrokeTransparency=0.1
visuals.stateText.Text="WAIT"
visuals.stateText.Parent=visuals.billboard

visuals.aimDot=Instance.new("Part")
visuals.aimDot.Anchored=true
visuals.aimDot.CanCollide=false
visuals.aimDot.Material=Enum.Material.Neon
visuals.aimDot.Color=Color3.fromRGB(255,215,70)
visuals.aimDot.Size=Vector3.new(0.9,0.9,0.9)
visuals.aimDot.Transparency=toggles.showAim and 0.1 or 1
visuals.aimDot.Parent=workspace

visuals.predDot=Instance.new("Part")
visuals.predDot.Anchored=true
visuals.predDot.CanCollide=false
visuals.predDot.Material=Enum.Material.ForceField
visuals.predDot.Color=Color3.fromRGB(255,240,160)
visuals.predDot.Size=Vector3.new(1.1,0.5,1.1)
visuals.predDot.Transparency=toggles.showAim and 0.15 or 1
visuals.predDot.Parent=workspace

visuals.predDots={}
for i=1,10 do
    local p=Instance.new("Part")
    p.Anchored=true
    p.CanCollide=false
    p.Material=Enum.Material.Neon
    p.Color=Color3.fromRGB(255,230,140)
    p.Size=Vector3.new(0.5,0.2,0.5)
    p.Transparency=toggles.showTrail and 0.3 or 1
    p.Parent=workspace
    visuals.predDots[i]=p
end

visuals.orbitAdornment=Instance.new("CylinderHandleAdornment")
visuals.orbitAdornment.Radius=config.sprintRadius
visuals.orbitAdornment.Height=0.2
visuals.orbitAdornment.Color3=Color3.fromRGB(255,220,80)
visuals.orbitAdornment.AlwaysOnTop=true
visuals.orbitAdornment.Transparency=toggles.showSprintRing and (1-config.orbitBrightness) or 1
visuals.orbitAdornment.Adornee=hrp
visuals.orbitAdornment.Parent=hrp

visuals.glowTrail=Instance.new("ParticleEmitter")
visuals.glowTrail.LightEmission=0.95
visuals.glowTrail.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.6,0.1),NumberSequenceKeypoint.new(0.5,1.2,0.2),NumberSequenceKeypoint.new(1,0)})
visuals.glowTrail.Color=ColorSequence.new(palette.primary,Color3.fromRGB(255,255,240))
visuals.glowTrail.Rate=toggles.floatingGlow and 18 or 0
visuals.glowTrail.Lifetime=NumberRange.new(0.8,1.2)
visuals.glowTrail.Speed=NumberRange.new(0,0)
visuals.glowTrail.SpreadAngle=Vector2.new(360,360)
visuals.glowTrail.Parent=visuals.aimDot

visuals.hrpAttachment=Instance.new("Attachment")
visuals.hrpAttachment.Parent=hrp

visuals.aimAttachment=Instance.new("Attachment")
visuals.aimAttachment.Parent=visuals.aimDot

visuals.ballBeam=Instance.new("Beam")
visuals.ballBeam.Attachment0=visuals.hrpAttachment
visuals.ballBeam.Attachment1=visuals.aimAttachment
visuals.ballBeam.Width0=0.22
visuals.ballBeam.Width1=0.12
visuals.ballBeam.FaceCamera=true
visuals.ballBeam.Color=ColorSequence.new(palette.primary)
visuals.ballBeam.Transparency=NumberSequence.new(toggles.showBallLine and 0.05 or 1)
visuals.ballBeam.LightEmission=1
visuals.ballBeam.Enabled=toggles.showBallLine
visuals.ballBeam.Parent=visuals.hrpAttachment

visuals.speedAttachment=Instance.new("Attachment")
visuals.speedAttachment.Parent=visuals.predDot

visuals.speedBeam=Instance.new("Beam")
visuals.speedBeam.Attachment0=visuals.aimAttachment
visuals.speedBeam.Attachment1=visuals.speedAttachment
visuals.speedBeam.Width0=0.15
visuals.speedBeam.Width1=0
visuals.speedBeam.Color=ColorSequence.new(Color3.fromRGB(255,248,180),Color3.fromRGB(255,120,60))
visuals.speedBeam.Enabled=toggles.showSpeedArrow
visuals.speedBeam.Parent=visuals.aimAttachment

visuals.goalLinePart=Instance.new("Part")
visuals.goalLinePart.Anchored=true
visuals.goalLinePart.CanCollide=false
visuals.goalLinePart.Transparency=1
visuals.goalLinePart.Size=Vector3.new(0.2,0.2,0.2)
visuals.goalLinePart.Parent=workspace

visuals.goalAttachment=Instance.new("Attachment")
visuals.goalAttachment.Parent=visuals.goalLinePart

visuals.goalBeam=Instance.new("Beam")
visuals.goalBeam.Attachment0=visuals.aimAttachment
visuals.goalBeam.Attachment1=visuals.goalAttachment
visuals.goalBeam.Width0=0.18
visuals.goalBeam.Width1=0.08
visuals.goalBeam.Color=ColorSequence.new(Color3.fromRGB(255,230,150),Color3.fromRGB(255,198,82))
visuals.goalBeam.Enabled=toggles.showGoalLine
visuals.goalBeam.Parent=visuals.aimAttachment

local rparams=RaycastParams.new()
rparams.FilterType=Enum.RaycastFilterType.Exclude
rparams.FilterDescendantsInstances={c}

local function isGrounded()
    local res=workspace:Raycast(hrp.Position,Vector3.new(0,-6,0),rparams)
    return res~=nil
end

local state="WAIT"
local lastBallPos=nil
local lastBallT=0
local currentGoal=nil
local moving=false
local lastIssue=0
local lastPos=hrp.Position
local lastT=time()
local nextF=0
local hadBall=false
local nextSprintPress=0
local nextSprintJump=0
local nextCloseJump=0
local nextTrick=0
local nextSlide=0
local previousBallPresent=false
local goalTarget=nil
local lastSprintTime=0
local sprintCooldown=0.3
local netCollisionTime=0
local netCooldown=0.5
local nextServePress=0
local currentGoalNetAllowance=0.75
local ballVisibleSince=0
local lastBallVel=Vector3.zero
local lastDirectionFlip=0

local HOME_NET_ALLOWANCE=0.75
local INTERCEPT_NET_ALLOWANCE=2.75
local BALL_SPRINT_GRACE=0.18
local BALL_FLIP_SPRINT_GRACE=0.1
local SPRINT_NEAR_BALL_BUFFER=3.5
local SPRINT_TARGET_BUFFER=1.75

local function setState(s)
    state=s
    visuals.stateText.Text=s
end

local function refreshBillboard()
    visuals.billboard.Enabled=toggles.showBillboard
    visuals.billboard.Size=UDim2.new(0,math.floor(config.billboardSize*26),0,math.floor(config.billboardSize*26))
    visuals.billboard.StudsOffset=Vector3.new(0,config.billboardSize,0)
end

local function refreshVisuals()
    visuals.aimDot.Transparency=toggles.showAim and 0.1 or 1
    visuals.predDot.Transparency=toggles.showAim and 0.15 or 1
    for _,p in ipairs(visuals.predDots) do
        p.Transparency=toggles.showTrail and 0.3 or 1
    end
    visuals.orbitAdornment.Radius=config.sprintRadius
    visuals.orbitAdornment.Transparency=toggles.showSprintRing and (1-config.orbitBrightness) or 1
    visuals.ballBeam.Enabled=toggles.showBallLine
    visuals.ballBeam.Transparency=NumberSequence.new(toggles.showBallLine and 0.05 or 1)
    visuals.goalBeam.Enabled=toggles.showGoalLine
    visuals.speedBeam.Enabled=toggles.showSpeedArrow
    visuals.glowTrail.Rate=toggles.floatingGlow and 18 or 0
    refreshBillboard()
end

local function doJump()
    if not toggles.allowJump then return end
    hum.Jump=true
    hum:ChangeState(Enum.HumanoidStateType.Jumping)
    if VIM then
        VIM:SendKeyEvent(true,Enum.KeyCode.Space,false,game)
        task.wait()
        VIM:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
    else
        UserInputService:SendKeyEvent(true,Enum.KeyCode.Space,false,game)
        task.wait()
        UserInputService:SendKeyEvent(false,Enum.KeyCode.Space,false,game)
    end
end

local function doSlide()
    if not toggles.allowSlide then return end
    if time()<nextSlide then return end
    nextSlide=time()+config.slideCooldown
    tapKey(Enum.KeyCode.E)
end

local function doTrick()
    if not toggles.allowTrick then return end
    if time()<nextTrick then return end
    nextTrick=time()+config.trickCooldown
    tapKey(Enum.KeyCode.R)
end

local function faceXZ(toPos)
    if not toggles.autoFace then return end
    local here=hrp.Position
    local look=Vector3.new(toPos.X,here.Y,toPos.Z)
    hrp.CFrame=hrp.CFrame:Lerp(CFrame.new(here,look),config.focusLerp)
end

local function requestMoveTo(goal,crossAllowance)
    if not goal then return end
    local allowance=crossAllowance
    if allowance==nil then
        allowance=currentGoalNetAllowance or HOME_NET_ALLOWANCE
    end
    goal=clampToCourt(goal,2.2,2.2)
    if HOME_SIGN~=0 then
        local center=getMapCenter()
        local laneDir=getLaneDir()
        local _,halfLength=getCourtHalfExtents()
        local lane=flat(goal-center):Dot(laneDir)
        local side=flat(goal-center):Dot(DIR)
        side=clampGoalSide(side,halfLength,allowance)
        goal=Vector3.new(center.X,goal.Y,center.Z)+laneDir*lane+DIR*side
        goal=clampToCourt(goal,2.2,2.2)
    end
    local here=hrp.Position
    local g=Vector3.new(goal.X,here.Y,goal.Z)
    local needDist=(not currentGoal) or (g-currentGoal).Magnitude>=config.minReissueDistance
    local needTime=(time()-lastIssue)>=config.minReissueTime
    if needDist or (not moving) or needTime then
        currentGoal=g
        currentGoalNetAllowance=allowance
        hum.WalkToPoint=g
        hum:MoveTo(g)
        lastIssue=time()
        moving=true
    end
end

hum.MoveToFinished:Connect(function()
    moving=false
end)

local function steerClose(goal)
    local here=hrp.Position
    local g=Vector3.new(goal.X,here.Y,goal.Z)
    local delta=g-here
    local dist=delta.Magnitude
    if dist>0.1 then
        hum:Move(delta.Unit,false)
    else
        hum:Move(Vector3.zero,false)
    end
end

predictLead=function(bpos,vel)
    local myPos=hrp.Position
    local dist=(bpos-myPos).Magnitude
    local lead=math.clamp(config.predictionLeadMin+dist/48*config.predictionLeadScale,config.predictionLeadMin,config.predictionLeadMax)
    local vxz=Vector3.new(vel.X,0,vel.Z)
    return bpos+vxz*lead
end

local function drawPrediction(bpos,ppos)
    visuals.aimDot.Position=bpos
    visuals.predDot.Position=ppos
    visuals.aimAttachment.WorldPosition=bpos
    visuals.speedAttachment.WorldPosition=ppos
    for i=1,#visuals.predDots do
        local a=i/#visuals.predDots
        visuals.predDots[i].Position=bpos+(ppos-bpos)*a
    end
end

local function goWait(referencePos)
    local t=getHomeAnchor(referencePos,false)
    visuals.aimDot.Position=t
    visuals.predDot.Position=t
    for i=1,#visuals.predDots do
        visuals.predDots[i].Position=t
    end
    requestMoveTo(t,HOME_NET_ALLOWANCE)
    steerClose(t)
end

local function isNearNet(pos)
    local center=getMapCenter()
    local distToCenter=math.abs(flat((pos or hrp.Position)-center):Dot(DIR))
    return distToCenter<3.25
end

local function sprintLogic(targetDist,incomingSpeed,ballDist,targetPoint,bpos,ballAge)
    if not toggles.allowSprint then return end
    if time()<netCollisionTime+netCooldown then return end
    if ballAge<BALL_SPRINT_GRACE then return end
    if time()<lastDirectionFlip+BALL_FLIP_SPRINT_GRACE then return end
    if isNearNet() then
        netCollisionTime=time()
        return
    end
    local predictionGap=flat(targetPoint-bpos).Magnitude
    local ballIsClose=ballDist<=config.autoHitDistance+SPRINT_NEAR_BALL_BUFFER
    local sprintNeed=(targetDist>config.sprintRadius or incomingSpeed>18) and not ballIsClose and predictionGap>SPRINT_TARGET_BUFFER
    if sprintNeed then
        if isGrounded() and time()>=nextSprintJump then
            doJump()
            nextSprintJump=time()+config.sprintJumpInterval
        end
        if time()>=nextSprintPress then
            tapKey(Enum.KeyCode.Q)
            nextSprintPress=time()+config.sprintSpamInterval
            lastSprintTime=time()
        end
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.4)
    c=getChar()
    hum=c:WaitForChild("Humanoid")
    hrp=c:WaitForChild("HumanoidRootPart")
    rparams.FilterDescendantsInstances={c}
    currentGoal=nil
    moving=false
    lastBallPos=nil
    lastBallT=0
    nextSprintPress=0
    nextServePress=0
    currentGoalNetAllowance=HOME_NET_ALLOWANCE
    ballVisibleSince=0
    lastBallVel=Vector3.zero
    lastDirectionFlip=0
    resolveHomeWaitIndex(true)
end)

refreshVisuals()
visualsDirty=false

local VirtualUser = game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

RunService.Heartbeat:Connect(function(dt)
    dt=dt or 0.016
    if visualsDirty then
        refreshVisuals()
        visualsDirty=false
    end
    
    local inLobby=isInLobby()
    if inLobby and not wasInLobby then
        enabledBeforeLobby=enabled
        enabled=false
    elseif not inLobby and wasInLobby then
        enabled=enabledBeforeLobby
    end
    wasInLobby=inLobby
    
    if not enabled then return end
    if inLobby then return end
    
    if autoBSpam and time()>=nextBSpam then
        tapKey(Enum.KeyCode.B)
        nextBSpam=time()+autoBInterval
    end
    hum.PlatformStand=false
    hum.AutoRotate=true
    if hum.WalkSpeed<16 then hum.WalkSpeed=18 end
    resolveHomeWaitIndex(false)
    local ball=getBall()
    local ballPresent=ball and ball.Parent~=nil
    local now=time()

    if ballPresent then
        if toggles.showGoalLine then
            if not goalTarget or not goalTarget.Parent then
                local goal=findByNameCI(workspace,"Goal") or findByNameCI(workspace,"Gate")
                goalTarget=goal
            end
            if goalTarget and goalTarget:IsA("BasePart") then
                visuals.goalLinePart.CFrame=goalTarget.CFrame
                visuals.goalAttachment.WorldPosition=goalTarget.Position
            else
                visuals.goalBeam.Enabled=false
            end
        end
        if toggles.showSpeedArrow then
            visuals.speedBeam.Enabled=true
        end
    else
        visuals.goalBeam.Enabled=false
        visuals.speedBeam.Enabled=false
    end
    if ballPresent and not hadBall then
        ballVisibleSince=now
        currentGoal=nil
        moving=false
        lastBallVel=Vector3.zero
        if toggles.allowJump and isGrounded() then
            doJump()
            nextSprintJump=time()+config.sprintJumpInterval
            nextCloseJump=time()+config.closeJumpInterval
        end
        nextSprintPress=math.max(nextSprintPress,now+BALL_SPRINT_GRACE)
    end
    hadBall=ballPresent
    previousBallPresent=ballPresent
    if not ballPresent then
        lastBallPos=nil
        lastBallT=0
        ballVisibleSince=0
        lastBallVel=Vector3.zero
        currentGoalNetAllowance=HOME_NET_ALLOWANCE
        if state~="WAIT" then setState("WAIT") end
        goWait()
        return
    end
    local bpos=ball.Position
    local vel=nil
    if lastBallPos and lastBallT>0 then
        local dtn=now-lastBallT
        if dtn>0 then
            vel=(bpos-lastBallPos)/dtn
        end
    end
    lastBallPos=bpos
    lastBallT=now
    if not vel then
        vel=Vector3.new()
    end
    local flatVel=flat(vel)
    local flatLastVel=flat(lastBallVel)
    if flatVel.Magnitude>8 and flatLastVel.Magnitude>8 and flatVel.Unit:Dot(flatLastVel.Unit)<-0.15 then
        currentGoal=nil
        moving=false
        lastDirectionFlip=now
        nextSprintPress=math.max(nextSprintPress,now+BALL_FLIP_SPRINT_GRACE)
    end
    lastBallVel=vel
    local center=getMapCenter()
    local _,halfLength=getCourtHalfExtents()
    local ballSideCoord=flat(bpos-center):Dot(DIR)
    if toggles.enableGoalGuard and HOME_SIGN~=0 then
        if HOME_SIGN>0 and ballSideCoord<(-halfLength-2) then
            if state~="WAIT" then setState("WAIT") end
            goWait(bpos)
            return
        end
        if HOME_SIGN<0 and ballSideCoord>(halfLength+2) then
            if state~="WAIT" then setState("WAIT") end
            goWait(bpos)
            return
        end
    end
    local interceptPoint=getInterceptTarget(bpos,vel)
    drawPrediction(bpos,interceptPoint)
    local here=hrp.Position
    local hereXZ=Vector3.new(here.X,0,here.Z)
    local ballXZ=Vector3.new(bpos.X,0,bpos.Z)
    local distXZ=(ballXZ-hereXZ).Magnitude
    local inServe=isInServeBounds(bpos,IS_BLUE)
    if inServe and HOME_SIGN~=0 and sideSign(bpos)==HOME_SIGN then
        local serveHold=getHomeAnchor(nil,false)
        local serveAim=getServeAimPoint()
        if state~="SERVE" then setState("SERVE") end
        faceXZ(serveAim)
        requestMoveTo(serveHold,HOME_NET_ALLOWANCE)
        steerClose(serveHold)
        if distXZ<=config.autoHitDistance+8 and time()>=nextServePress then
            tapKey(Enum.KeyCode.F)
            nextServePress=time()+0.12
        end
        return
    end
    local targetPoint=(distXZ>config.closeControlRadius) and interceptPoint or bpos
    targetPoint=clampToCourt(targetPoint,2.2,2.2)
    local targetXZ=Vector3.new(targetPoint.X,0,targetPoint.Z)
    local targetDist=(targetXZ-hereXZ).Magnitude
    local incomingSpeed=getHomeIncomingSpeed(vel)
    local ballAge=(ballVisibleSince>0) and (now-ballVisibleSince) or 0
    if toggles.autoFace then
        faceXZ(targetPoint)
    end
    if toggles.autoHit and distXZ<=config.autoHitDistance then
        if time()>=nextF then
            tapKey(Enum.KeyCode.F)
            nextF=time()+config.kickDelay
        end
    end
    if distXZ<=config.closeControlRadius and toggles.allowJump and isGrounded() and time()>=nextCloseJump then
        doJump()
        nextCloseJump=time()+config.closeJumpInterval
    end
    if distXZ<=config.closeControlRadius then
        if not toggles.autoHit then
            doSlide()
            doTrick()
        end
    end
    local ballSign=sideSign(bpos)
    local interceptSign=sideSign(interceptPoint)
    local onMyHalf=(HOME_SIGN~=0 and (ballSign==HOME_SIGN or interceptSign==HOME_SIGN))
    local shouldIntercept=onMyHalf or incomingSpeed>8
    if shouldIntercept then
        sprintLogic(targetDist,incomingSpeed,distXZ,targetPoint,bpos,ballAge)
        if targetDist>config.moveNearDistance then
            requestMoveTo(targetPoint,INTERCEPT_NET_ALLOWANCE)
        end
        steerClose(targetPoint)
        if distXZ<=config.hitRange and ball.Size.X>8.8 and ball.Size.Z>8.8 then
            setState("SPAM")
        else
            if state~="CHASE" then
                setState("CHASE")
            end
        end
    else
        if toggles.quickReturn then
            if state~="WAIT" then setState("WAIT") end
            goWait(bpos)
        end
    end
    if currentGoal then
        local here2=hrp.Position
        local distToGoal=(currentGoal-here2).Magnitude
        if distToGoal<=config.deadZone then
            moving=false
        else
            if time()-lastIssue>=0.4 then
                requestMoveTo(currentGoal)
            end
        end
    end
    local s=hrp.Position
    local spd=((s-lastPos).Magnitude)/math.max(0.0001,(time()-lastT))
    lastPos=s
    lastT=time()
    if spd<0.15 and currentGoal and (currentGoal-hrp.Position).Magnitude>config.returnDistance then
        if toggles.allowJump and isGrounded() then doJump() end
        if isNearNet() then
            local unstuck=getHomeAnchor(nil,false)
            requestMoveTo(unstuck,HOME_NET_ALLOWANCE)
            steerClose(unstuck)
        else
            requestMoveTo(currentGoal)
            steerClose(currentGoal)
        end
    end
    if state=="RETURN" then
        local waitPoint=getHomeAnchor()
        goWait(waitPoint)
        if (waitPoint-hrp.Position).Magnitude<=config.returnDistance then setState("WAIT") end
    end
end)

enabled=true
refreshVisuals()
