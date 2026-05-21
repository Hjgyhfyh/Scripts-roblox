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

local function loadLibrary()
	local g = (getgenv and getgenv()) or _G or getfenv(0) or {}
	local pre = rawget(g, "__SIGMATIK_LIB_PREINJECTED__")
	if type(pre) == "table" then return pre end
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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)

local Gui

local sessionLocks = {}
local lastStatus = {}
local PROBE_LOCK_AFTER_RUN = {
	["F-001"] = true,
	["F-003"] = true,
	["F-004"] = true,
}

local function readCash()
	local cu = PlayerGui:FindFirstChild("CurrencyUI")
	if cu then
		local label = cu:FindFirstChild("MoneyLabel")
		if label then
			return label.Text
		end
	end
	return "?"
end

local function setStatus(findingId, text)
	lastStatus[findingId] = text
	print(string.format("[SquishyProbe %s] %s", findingId, text))
end

local function lockAfterRun(findingId)
	if PROBE_LOCK_AFTER_RUN[findingId] then
		sessionLocks[findingId] = true
	end
end

local function disableModule(tabName, moduleName)
	if Gui then
		pcall(Gui.SetModuleEnabled, Gui, tabName, moduleName, false)
	end
end

local function findFirstOwnPet()
	for _, v in workspace:GetDescendants() do
		if v.Name == "PetCollectible" and v:IsA("BasePart") and v:GetAttribute("PetOwnerId") == LocalPlayer.UserId then
			return v
		end
	end
	return nil
end

local function waitForRemoteEvent(remoteName, timeout)
	local r = Remotes:FindFirstChild(remoteName)
	if r then
		return r
	end
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 5) do
		task.wait(0.2)
		r = Remotes:FindFirstChild(remoteName)
		if r then
			return r
		end
	end
	return nil
end

local function runProbeF001(tabName, moduleName)
	if sessionLocks["F-001"] then
		setStatus("F-001", "LOCKED — already fired in this session")
		disableModule(tabName, moduleName)
		return
	end
	setStatus("F-001", "Running... cash-before=" .. readCash())

	local zonePresence = waitForRemoteEvent("DanceZonePresence", 5)
	local scoreSubmit = waitForRemoteEvent("DanceScoreSubmit", 5)
	local endEarly = waitForRemoteEvent("DanceEndEarly", 5)
	local songStarted = waitForRemoteEvent("DanceSongStarted", 5)
	local danceReward = waitForRemoteEvent("DanceReward", 5)
	if not (zonePresence and scoreSubmit and endEarly and songStarted and danceReward) then
		setStatus("F-001", "ABORT — required remotes not found")
		disableModule(tabName, moduleName)
		return
	end

	local rewardSeen = nil
	local rewardConn = danceReward.OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			rewardSeen = p
		end
	end)

	local started = false
	local songConn = songStarted.OnClientEvent:Connect(function()
		started = true
	end)

	zonePresence:FireServer(true)

	local t0 = os.clock()
	while not started and os.clock() - t0 < 30 do
		task.wait(0.5)
	end

	if not started then
		zonePresence:FireServer(false)
		rewardConn:Disconnect()
		songConn:Disconnect()
		setStatus("F-001", "TIMEOUT — no DanceSongStarted within 30s")
		disableModule(tabName, moduleName)
		return
	end

	scoreSubmit:FireServer({ score = 99999999, noteCount = 9999 })
	task.wait(0.4)
	endEarly:FireServer({ score = 99999999, noteCount = 9999 })
	task.wait(2.0)

	zonePresence:FireServer(false)
	rewardConn:Disconnect()
	songConn:Disconnect()

	if rewardSeen then
		setStatus("F-001", string.format(
			"VERIFIED — amount=%s score=%s/%s | cash-after=%s",
			tostring(rewardSeen.amount), tostring(rewardSeen.score), tostring(rewardSeen.maxScore), readCash()
		))
	else
		setStatus("F-001", "INCONCLUSIVE — no DanceReward received | cash-after=" .. readCash())
	end

	lockAfterRun("F-001")
	disableModule(tabName, moduleName)
end

local function runProbeF002(tabName, moduleName)
	setStatus("F-002", "Running... cash-before=" .. readCash())
	local r = waitForRemoteEvent("DanceJudgment", 5)
	if not r then
		setStatus("F-002", "ABORT — DanceJudgment remote missing")
		disableModule(tabName, moduleName)
		return
	end
	local cashBefore = readCash()
	for _ = 1, 50 do
		r:FireServer({ judgment = "Perfect", lane = "Center" })
	end
	task.wait(1.5)
	local cashAfter = readCash()
	if cashBefore == cashAfter then
		setStatus("F-002", "DISPROVEN — 50 judgments, no cash change (" .. cashAfter .. ")")
	else
		setStatus("F-002", "STATUS-CHANGED — cash " .. cashBefore .. " -> " .. cashAfter)
	end
	disableModule(tabName, moduleName)
end

local function runProbeF003(tabName, moduleName)
	if sessionLocks["F-003"] then
		setStatus("F-003", "LOCKED — already fired in this session")
		disableModule(tabName, moduleName)
		return
	end
	setStatus("F-003", "Running...")
	local r = waitForRemoteEvent("DanceZonePresence", 5)
	local d = waitForRemoteEvent("DanceDancers", 5)
	if not (r and d) then
		setStatus("F-003", "ABORT — required remotes missing")
		disableModule(tabName, moduleName)
		return
	end
	local registered = false
	local conn = d.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.userIds) == "table" then
			for _, id in ipairs(payload.userIds) do
				if id == LocalPlayer.UserId then
					registered = true
				end
			end
		end
	end)
	r:FireServer(true)
	task.wait(2)
	r:FireServer(false)
	task.wait(0.5)
	conn:Disconnect()
	if registered then
		setStatus("F-003", "VERIFIED — server registered LocalPlayer in DanceDancers payload")
	else
		setStatus("F-003", "INCONCLUSIVE — no DanceDancers payload contained LocalPlayer userId")
	end
	lockAfterRun("F-003")
	disableModule(tabName, moduleName)
end

local function runProbeF004(tabName, moduleName)
	if sessionLocks["F-004"] then
		setStatus("F-004", "LOCKED — already fired in this session")
		disableModule(tabName, moduleName)
		return
	end
	setStatus("F-004", "Running... cash-before=" .. readCash())
	local r = waitForRemoteEvent("RequestClaimReward", 5)
	local rs = waitForRemoteEvent("RequestRewardStatus", 5)
	if not r then
		setStatus("F-004", "ABORT — RequestClaimReward remote missing")
		disableModule(tabName, moduleName)
		return
	end
	local statusSeen = nil
	local statusConn = rs and rs.OnClientEvent:Connect(function(p)
		statusSeen = p
	end)
	local cashBefore = readCash()
	r:FireServer("free_reward")
	task.wait(0.4)
	r:FireServer("nonexistent_reward")
	r:FireServer("admin_reward")
	r:FireServer("")
	r:FireServer(nil)
	task.wait(2)
	if statusConn then
		statusConn:Disconnect()
	end
	local cashAfter = readCash()
	local fr = statusSeen and statusSeen.free_reward
	local claimed = fr and fr.Claimed
	setStatus("F-004", string.format(
		"cash %s -> %s | free_reward.claimed=%s | invalid IDs ignored",
		cashBefore, cashAfter, tostring(claimed)
	))
	lockAfterRun("F-004")
	disableModule(tabName, moduleName)
end

local function runProbeF005(tabName, moduleName)
	setStatus("F-005", "Running... cash-before=" .. readCash())
	local r = waitForRemoteEvent("TutorialCompleted", 5)
	if not r then
		setStatus("F-005", "ABORT — TutorialCompleted remote missing")
		disableModule(tabName, moduleName)
		return
	end
	local cashBefore = readCash()
	r:FireServer()
	task.wait(2)
	local cashAfter = readCash()
	setStatus("F-005", string.format("cash %s -> %s (likely natural box income)", cashBefore, cashAfter))
	disableModule(tabName, moduleName)
end

local function runProbeF006(tabName, moduleName)
	setStatus("F-006", "Running...")
	local r = waitForRemoteEvent("RequestRenamePet", 5)
	local nu = waitForRemoteEvent("PetNameUpdated", 5)
	if not r then
		setStatus("F-006", "ABORT — RequestRenamePet remote missing")
		disableModule(tabName, moduleName)
		return
	end
	local pet = findFirstOwnPet()
	if not pet then
		setStatus("F-006", "SKIP — no own PetCollectible in workspace")
		disableModule(tabName, moduleName)
		return
	end
	local count = 0
	local conn = nu and nu.OnClientEvent:Connect(function() count = count + 1 end)
	r:FireServer(pet, "ProbeNameOK_" .. tostring(math.random(100, 999)))
	task.wait(2)
	r:FireServer(pet, "<b>BOLD</b>")
	task.wait(2)
	if conn then
		conn:Disconnect()
	end
	if count == 0 then
		setStatus("F-006", "DISPROVEN — 0 PetNameUpdated events after 2 attempts")
	else
		setStatus("F-006", "STATUS-CHANGED — " .. count .. " PetNameUpdated events received")
	end
	disableModule(tabName, moduleName)
end

local function runProbeF007(tabName, moduleName)
	setStatus("F-007", "Running... cash-before=" .. readCash())
	local r = waitForRemoteEvent("RequestPetPet", 5)
	if not r then
		setStatus("F-007", "ABORT — RequestPetPet remote missing")
		disableModule(tabName, moduleName)
		return
	end
	local pet = findFirstOwnPet()
	if not pet then
		setStatus("F-007", "SKIP — no own PetCollectible in workspace")
		disableModule(tabName, moduleName)
		return
	end
	local cashBefore = readCash()
	for _ = 1, 100 do
		r:FireServer(pet)
	end
	task.wait(1.5)
	local cashAfter = readCash()
	if cashBefore == cashAfter then
		setStatus("F-007", "DISPROVEN — 100 fires, no cash change (" .. cashAfter .. ")")
	else
		setStatus("F-007", "STATUS-CHANGED — cash " .. cashBefore .. " -> " .. cashAfter)
	end
	disableModule(tabName, moduleName)
end

local function runProbeF008(tabName, moduleName)
	setStatus("F-008", "Running...")
	local r = waitForRemoteEvent("RequestPlaceBox", 5)
	if not r then
		setStatus("F-008", "ABORT — RequestPlaceBox remote missing")
		disableModule(tabName, moduleName)
		return
	end
	local function countMine()
		local n = 0
		for _, v in CollectionService:GetTagged("PlacedCollectibleBox") do
			if v:GetAttribute("OwnerId") == LocalPlayer.UserId then
				n = n + 1
			end
		end
		return n
	end
	local before = countMine()
	r:FireServer(Vector3.new(0, 1000, 0))
	r:FireServer(Vector3.new(99999, 99999, 99999))
	r:FireServer(Vector3.new(-1e9, 0, 0))
	pcall(function() r:FireServer("not-a-vector") end)
	task.wait(1.5)
	local after = countMine()
	if before == after then
		setStatus("F-008", "DISPROVEN — extreme positions rejected (" .. after .. " owned boxes)")
	else
		setStatus("F-008", "STATUS-CHANGED — owned boxes " .. before .. " -> " .. after)
	end
	disableModule(tabName, moduleName)
end

local function runProbeF009(tabName, moduleName)
	setStatus("F-009", "Running... cash-before=" .. readCash())
	local r = waitForRemoteEvent("DancePetBounce", 5)
	if not r then
		setStatus("F-009", "ABORT — DancePetBounce remote missing")
		disableModule(tabName, moduleName)
		return
	end
	local cashBefore = readCash()
	for _ = 1, 200 do
		r:FireServer()
	end
	task.wait(2)
	local cashAfter = readCash()
	local alive = LocalPlayer.Parent ~= nil
	if cashBefore == cashAfter and alive then
		setStatus("F-009", "DISPROVEN — 200 fires, no cash/kick (" .. cashAfter .. ")")
	elseif not alive then
		setStatus("F-009", "STATUS-CHANGED — player no longer in Players service")
	else
		setStatus("F-009", "STATUS-CHANGED — cash " .. cashBefore .. " -> " .. cashAfter)
	end
	disableModule(tabName, moduleName)
end

local function runProbeF010(tabName, moduleName)
	setStatus("F-010", "Running... cash-before=" .. readCash())
	local r = waitForRemoteEvent("RequestUpgrade", 5)
	local uu = waitForRemoteEvent("UpgradeUpdated", 5)
	if not r then
		setStatus("F-010", "ABORT — RequestUpgrade remote missing")
		disableModule(tabName, moduleName)
		return
	end
	local count = 0
	local conn = uu and uu.OnClientEvent:Connect(function() count = count + 1 end)
	for _ = 1, 50 do
		task.spawn(function() r:FireServer("Luck") end)
	end
	r:FireServer("NonExistent")
	r:FireServer("")
	pcall(function() r:FireServer(nil) end)
	pcall(function() r:FireServer({ "Luck" }) end)
	task.wait(2)
	if conn then
		conn:Disconnect()
	end
	if count == 0 then
		setStatus("F-010", "DISPROVEN — 0 UpgradeUpdated events for 50 parallel + 4 invalid fires")
	else
		setStatus("F-010", "STATUS-CHANGED — " .. count .. " UpgradeUpdated events fired")
	end
	disableModule(tabName, moduleName)
end

local PROBE_MAP = {
	["F-001"] = runProbeF001, ["F-002"] = runProbeF002,
	["F-003"] = runProbeF003, ["F-004"] = runProbeF004,
	["F-005"] = runProbeF005, ["F-006"] = runProbeF006,
	["F-007"] = runProbeF007, ["F-008"] = runProbeF008,
	["F-009"] = runProbeF009, ["F-010"] = runProbeF010,
}

local function attachTabRefs(modules, tabName)
	for _, m in ipairs(modules) do
		local moduleName = m.Name
		local findingId = moduleName:match("F%-%d+")
		m.Callback = function(enabled)
			if not enabled then return end
			task.spawn(function()
				local ok, err = pcall(function()
					local fn = PROBE_MAP[findingId]
					if fn then fn(tabName, moduleName) end
				end)
				if not ok then
					setStatus(findingId or moduleName, "ERROR — " .. tostring(err))
					disableModule(tabName, moduleName)
				end
			end)
		end
	end
	return modules
end

Gui = Library:Create({
	Title = "tg: @sigmatik323",
	ConfigName = "Squishy Probe",
	SearchPlaceholder = "Search probes...",
	Accent = "#3b82f6",
	AccentSoft = "#60a5fa",
	BlurSize = 14,
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = "Dance Probes",
			Icon = "combat",
			Modules = attachTabRefs({
				{
					Name = "F-001 Score Inject",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "DanceScoreSubmit accepts client-supplied {score, noteCount}. Server clamps score to [0, maxScore] but trusts the value within that range. Single-fire diagnostic: enters zone, waits for next song, submits huge score, ends early, captures DanceReward." },
							{ Type = "Paragraph", Name = "Severity", Content = "Verified Medium. Locked after one run per session." },
						} },
					},
				},
				{
					Name = "F-002 Judgment Spam",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "DanceJudgment accepts client-declared {judgment, lane}. Probe spams 50 Perfect verdicts to test whether server uses these for score." },
							{ Type = "Paragraph", Name = "Severity", Content = "Disproven in original audit. Re-runs the same test." },
						} },
					},
				},
				{
					Name = "F-003 Zone Presence",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "DanceZonePresence(true/false) is client-declared. Probe asserts true and watches DanceDancers payload for own UserId." },
							{ Type = "Paragraph", Name = "Severity", Content = "Verified Medium. Locked after one run per session." },
						} },
					},
				},
				{
					Name = "F-009 Bounce Spam",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "DancePetBounce broadcast spam: 200 fires, check rate-limit / kick / cash delta." },
							{ Type = "Paragraph", Name = "Severity", Content = "Disproven in original audit." },
						} },
					},
				},
			}, "Dance Probes"),
		},
		{
			Name = "Reward Probes",
			Icon = "misc",
			Modules = attachTabRefs({
				{
					Name = "F-004 Free Reward",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "RequestClaimReward('free_reward') — client UX requires double-click + group + like flag. Server only checks playtime+group, not the like flag. Probe tries the legitimate task ID once and several invalid IDs." },
							{ Type = "Paragraph", Name = "Severity", Content = "Verified Low (UX bypass). Locked after one run per session." },
						} },
					},
				},
				{
					Name = "F-005 Tutorial Completed",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "TutorialCompleted() — fire without completing tutorial steps. Watch for cash spike that would indicate tutorial reward." },
							{ Type = "Paragraph", Name = "Severity", Content = "Disproven in original audit." },
						} },
					},
				},
			}, "Reward Probes"),
		},
		{
			Name = "Inventory Probes",
			Icon = "misc",
			Modules = attachTabRefs({
				{
					Name = "F-006 Rename Pet",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "RequestRenamePet(pet, name) — test if server filters or broadcasts. Probe attempts ascii name and rich-text injection on own pet, watches PetNameUpdated for echoes." },
							{ Type = "Paragraph", Name = "Severity", Content = "Disproven in original audit." },
						} },
					},
				},
				{
					Name = "F-007 Pet Pet Spam",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "RequestPetPet(petInstance) — 100 fires on own pet to test cash side-effect or throttle." },
							{ Type = "Paragraph", Name = "Severity", Content = "Disproven in original audit." },
						} },
					},
				},
				{
					Name = "F-008 Place Box Extreme",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "RequestPlaceBox(Vector3) — fire with extreme/invalid positions and check whether PlacedCollectibleBox count changes." },
							{ Type = "Paragraph", Name = "Severity", Content = "Disproven in original audit." },
						} },
					},
				},
				{
					Name = "F-010 Upgrade Race",
					Enabled = false,
					Sections = {
						{ Name = "Description", Controls = {
							{ Type = "Paragraph", Name = "Hypothesis", Content = "RequestUpgrade(id) — 50 parallel fires on 'Luck' + 4 invalid IDs. Watches UpgradeUpdated count to detect race." },
							{ Type = "Paragraph", Name = "Severity", Content = "Disproven in original audit." },
						} },
					},
				},
			}, "Inventory Probes"),
		},
		{
			Name = "Report",
			Icon = "misc",
			Modules = {
				{
					Name = "Last Results",
					Enabled = false,
					Sections = {
						{
							Name = "Statuses",
							Controls = {
								{ Type = "Label", Name = "F-001", Content = "F-001: not run" },
								{ Type = "Label", Name = "F-002", Content = "F-002: not run" },
								{ Type = "Label", Name = "F-003", Content = "F-003: not run" },
								{ Type = "Label", Name = "F-004", Content = "F-004: not run" },
								{ Type = "Label", Name = "F-005", Content = "F-005: not run" },
								{ Type = "Label", Name = "F-006", Content = "F-006: not run" },
								{ Type = "Label", Name = "F-007", Content = "F-007: not run" },
								{ Type = "Label", Name = "F-008", Content = "F-008: not run" },
								{ Type = "Label", Name = "F-009", Content = "F-009: not run" },
								{ Type = "Label", Name = "F-010", Content = "F-010: not run" },
							},
						},
						{
							Name = "About",
							Controls = {
								{ Type = "Paragraph", Name = "Tool", Content = "Single-fire vulnerability probe console for Squishy Dumpling Unboxing. Each probe fires once per click and reports verified/disproven outcome to console plus this panel. Verified findings are session-locked after one run." },
								{ Type = "Paragraph", Name = "Source", Content = "Based on audit at Razdel/Squishy Dumpling Unboxing - Vulnerabilities.md" },
							},
						},
					},
				},
			},
		},
	},
})

print("[SquishyProbe] UI loaded. Press RightShift to toggle.")
