local LIBRARY_URL = "https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"
local LOCAL_LIBRARY_PATHS = {
	"sigmatik_ui_library.lua",
	"gui_lua/sigmatik_ui_library.lua",
	"../gui_lua/sigmatik_ui_library.lua",
	"..\\gui_lua\\sigmatik_ui_library.lua",
	"D:/Нужное/Скрипты роблокс/Делаем скрипты тут/gui_lua/sigmatik_ui_library.lua",
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer
local SharedEnvironment = (getgenv and getgenv()) or _G
local PreviousContext = SharedEnvironment.SigmatikFightInASupermarketContext

if PreviousContext and PreviousContext.Cleanup then
	pcall(PreviousContext.Cleanup)
end

local function loadLibrary()
	for _, path in ipairs(LOCAL_LIBRARY_PATHS) do
		if loadfile then
			local ok, chunk = pcall(loadfile, path)
			if ok and chunk then
				return chunk()
			end
		end
		if readfile and loadstring then
			local ok, source = pcall(readfile, path)
			if ok and source then
				return loadstring(source)()
			end
		end
	end
	if loadstring then
		local ok, source = pcall(function()
			return game:HttpGet(LIBRARY_URL)
		end)
		if ok and source then
			return loadstring(source)()
		end
	end
	error("Sigmatik UI library could not be loaded")
end

local Library = loadLibrary()

local function icon(codepoint)
	return utf8.char(codepoint)
end

local TAB_NAME = icon(0x1F956) .. " Supermarket"
local MODULE_VISUALS = icon(0x1F441) .. " Visuals"
local MODULE_COMBAT = icon(0x2694) .. " Combat"
local MODULE_ECONOMY = icon(0x1F4B0) .. " Economy"
local MODULE_MOVEMENT = icon(0x1F300) .. " Movement"

local SECTION_VISUALS = icon(0x1F441) .. " ESP"
local SECTION_COLORS = icon(0x1F3A8) .. " ESP Colors"
local SECTION_COMBAT = icon(0x2694) .. " Combat"
local SECTION_ECONOMY = icon(0x1F4B0) .. " Economy"
local SECTION_MOVEMENT = icon(0x1F300) .. " Movement"
local SECTION_INFO = icon(0x1F4CC) .. " Info"

local NAME_COIN_ESP = "Coin ESP"
local NAME_BEST_WEAPON_ESP = "Best Weapon ESP"
local NAME_STRONGEST_PLAYER_ESP = "Strongest Player ESP"
local NAME_FAST_ATTACK = "Fast Attack"
local NAME_ATTACK_SPEED = "Attack Speed"
local NAME_COIN_MAGNET = "Coin Magnet"
local NAME_SPIN = "Spin"
local NAME_SPIN_SPEED = "Spin Speed"
local NAME_NOCLIP = "Noclip"
local NAME_FAST_E = "Fast E"

local NAME_COIN_COLOR = "Coin Color"
local NAME_BEST_WEAPON_COLOR = "Best Weapon Color"
local NAME_STRONGEST_COLOR = "Strongest Player Color"

local NAME_INFO_BEST = "Best Affordable: -"
local NAME_INFO_STRONGEST = "Strongest: -"
local NAME_INFO_CASH = "Cash: 0"
local NAME_INFO_COINS = "Coins on map: 0"

local DEFAULT_COIN_COLOR = "#f6c343ff"
local DEFAULT_BEST_WEAPON_COLOR = "#a855f7ff"
local DEFAULT_STRONGEST_COLOR = "#ef4444ff"

local Ctx = {
	Alive = true,
	Window = nil,

	CoinESP = false,
	BestWeaponESP = false,
	StrongestESP = false,
	FastAttack = false,
	AttackSpeed = 2.0,
	CoinMagnet = false,
	Spin = false,
	SpinSpeed = 10,
	Noclip = false,
	FastE = false,

	CoinColor = Color3.fromRGB(246, 195, 67),
	BestWeaponColor = Color3.fromRGB(168, 85, 247),
	StrongestColor = Color3.fromRGB(239, 68, 68),

	BestWeaponName = nil,
	BestWeaponPrice = 0,
	BestWeaponShelf = nil,
	StrongestPlayer = nil,
	StrongestValue = 0,

	CoinAdornments = {},
	BestWeaponAdornments = {},
	PlayerAdornments = {},
	ESPFolder = nil,

	HeartbeatConn = nil,
	HumanoidConns = {},
	CharConn = nil,
	MagnetThread = nil,
	SpinConn = nil,
	NoclipConn = nil,

	CoinFolderConns = {},
	PatchedAttackFns = {},
	OriginalAnimTimes = {},
	BackpackConns = {},
	AttackHeartbeatConn = nil,
	PromptOriginalHold = {},
	PromptDescConn = nil,
	PromptShownConn = nil,
	PromptListConns = {},
}

SharedEnvironment.SigmatikFightInASupermarketContext = Ctx

local function hexToColor3(hex)
	if typeof(hex) == "Color3" then return hex end
	if type(hex) ~= "string" then return Color3.new(1, 1, 1) end
	local clean = hex:gsub("#", "")
	if #clean >= 6 then
		local r = tonumber(clean:sub(1, 2), 16) or 255
		local g = tonumber(clean:sub(3, 4), 16) or 255
		local b = tonumber(clean:sub(5, 6), 16) or 255
		return Color3.fromRGB(r, g, b)
	end
	return Color3.new(1, 1, 1)
end

local function getOrCreateESPFolder()
	if Ctx.ESPFolder and Ctx.ESPFolder.Parent then
		return Ctx.ESPFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "SigmatikSupermarketESP"
	folder.Parent = Workspace.CurrentCamera or Workspace
	Ctx.ESPFolder = folder
	return folder
end

local function getRootFromInstance(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		local pivot = inst.PrimaryPart
		if pivot then return pivot end
		for _, child in ipairs(inst:GetDescendants()) do
			if child:IsA("BasePart") then return child end
		end
	end
	return nil
end

local function makeHighlight(target, fillColor, outlineColor)
	local h = Instance.new("Highlight")
	h.Adornee = target
	h.FillColor = fillColor
	h.OutlineColor = outlineColor
	h.FillTransparency = 0.55
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = getOrCreateESPFolder()
	return h
end

local function makeBillboard(target, text, textColor, sizeY)
	local root = getRootFromInstance(target)
	if not root then return nil end
	local bg = Instance.new("BillboardGui")
	bg.Adornee = root
	bg.AlwaysOnTop = true
	bg.Size = UDim2.fromOffset(180, sizeY or 28)
	bg.StudsOffset = Vector3.new(0, 2.5, 0)
	bg.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = text
	label.Parent = bg
	bg.Parent = getOrCreateESPFolder()
	return bg, label
end

local function clearAdornmentTable(tbl)
	for k, entry in pairs(tbl) do
		if entry then
			if entry.Highlight then pcall(function() entry.Highlight:Destroy() end) end
			if entry.Billboard then pcall(function() entry.Billboard:Destroy() end) end
		end
		tbl[k] = nil
	end
end

local function clearAllAdornments()
	clearAdornmentTable(Ctx.CoinAdornments)
	clearAdornmentTable(Ctx.BestWeaponAdornments)
	clearAdornmentTable(Ctx.PlayerAdornments)
end

local function setInfoLabel(controlName, text)
	if not Ctx.Window then return end
	pcall(function()
		Ctx.Window:SetControlValue(TAB_NAME, MODULE_VISUALS, SECTION_INFO, controlName, text)
	end)
end

local function getShelvesFolder()
	return Workspace:FindFirstChild("Shelves")
end

local function getCoinsFolder()
	return Workspace:FindFirstChild("SpawnedCash")
end

local function getCash()
	if not LocalPlayer then return 0 end
	return tonumber(LocalPlayer:GetAttribute("Cash")) or 0
end

local function formatPrice(n)
	if not n then return "0" end
	if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
	if n >= 1e3 then return string.format("%.2fK", n / 1e3) end
	return string.format("%.0f", n)
end

local function parsePriceText(s)
	if type(s) ~= "string" then return nil end
	local digits = s:gsub("[^%d%.]", "")
	if digits == "" then return nil end
	return tonumber(digits)
end

local function getShelfPrice(shelf)
	local pt = shelf:FindFirstChild("PriceTags")
	if not pt then return nil end
	for _, tag in ipairs(pt:GetChildren()) do
		for _, d in ipairs(tag:GetDescendants()) do
			if d:IsA("TextLabel") and d.Name == "Price" then
				local v = parsePriceText(d.Text)
				if v then return v end
			end
		end
	end
	return nil
end

local function getShelfHighlightTarget(shelf)
	local sdm = shelf:FindFirstChild("ShelfDisplayModel")
	if sdm and sdm:IsA("Model") then return sdm end
	local sm = shelf:FindFirstChild("ShelfModel") or shelf:FindFirstChild("ShelfModelVertical")
	if sm and sm:IsA("Model") then return sm end
	return shelf:FindFirstChild("ShelfHitbox") or shelf
end

local function findBestAffordableShelf()
	local shelves = getShelvesFolder()
	if not shelves then
		Ctx.BestWeaponName = nil
		Ctx.BestWeaponPrice = 0
		Ctx.BestWeaponShelf = nil
		return
	end
	local cash = getCash()
	local bestPrice = -1
	local bestShelf = nil
	for _, shelf in ipairs(shelves:GetChildren()) do
		local price = getShelfPrice(shelf)
		if price and price <= cash and price > bestPrice then
			bestPrice = price
			bestShelf = shelf
		end
	end
	if bestShelf then
		Ctx.BestWeaponName = bestShelf.Name
		Ctx.BestWeaponPrice = bestPrice
		Ctx.BestWeaponShelf = bestShelf
	else
		Ctx.BestWeaponName = nil
		Ctx.BestWeaponPrice = 0
		Ctx.BestWeaponShelf = nil
	end
end

local function findStrongestPlayer()
	local bestValue = -1
	local bestPlayer = nil
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local v = tonumber(plr:GetAttribute("TotalValue")) or 0
			if v > bestValue then
				bestValue = v
				bestPlayer = plr
			end
		end
	end
	Ctx.StrongestPlayer = bestPlayer
	Ctx.StrongestValue = bestValue >= 0 and bestValue or 0
end

local function addCoinHighlight(model)
	if not Ctx.CoinESP then return end
	if not model or not model:IsA("Model") then return end
	if model.Name ~= "Money" then return end
	if Ctx.CoinAdornments[model] then
		local entry = Ctx.CoinAdornments[model]
		if entry.Highlight then
			entry.Highlight.FillColor = Ctx.CoinColor
			entry.Highlight.OutlineColor = Ctx.CoinColor
			entry.Highlight.Adornee = model
		end
		return
	end
	local hl = makeHighlight(model, Ctx.CoinColor, Ctx.CoinColor)
	Ctx.CoinAdornments[model] = { Highlight = hl }
end

local function removeCoinHighlight(model)
	local entry = Ctx.CoinAdornments[model]
	if entry then
		if entry.Highlight then pcall(function() entry.Highlight:Destroy() end) end
		Ctx.CoinAdornments[model] = nil
	end
end

local function disconnectCoinFolderConns()
	for _, c in ipairs(Ctx.CoinFolderConns) do
		pcall(function() c:Disconnect() end)
	end
	Ctx.CoinFolderConns = {}
end

local function bindCoinFolder()
	disconnectCoinFolderConns()
	local folder = getCoinsFolder()
	if not folder then return end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m.Name == "Money" then
			addCoinHighlight(m)
		end
	end
	table.insert(Ctx.CoinFolderConns, folder.ChildAdded:Connect(function(child)
		if Ctx.CoinESP and child:IsA("Model") and child.Name == "Money" then
			addCoinHighlight(child)
		end
	end))
	table.insert(Ctx.CoinFolderConns, folder.ChildRemoved:Connect(function(child)
		removeCoinHighlight(child)
	end))
end

local function refreshCoinESPColors()
	for _, entry in pairs(Ctx.CoinAdornments) do
		if entry.Highlight then
			entry.Highlight.FillColor = Ctx.CoinColor
			entry.Highlight.OutlineColor = Ctx.CoinColor
		end
	end
end

local function clearCoinESP()
	disconnectCoinFolderConns()
	clearAdornmentTable(Ctx.CoinAdornments)
end

local function refreshBestWeaponESP()
	findBestAffordableShelf()
	if Ctx.BestWeaponName then
		setInfoLabel(NAME_INFO_BEST, string.format("Best Affordable: %s ($%s)", Ctx.BestWeaponName, formatPrice(Ctx.BestWeaponPrice)))
	else
		setInfoLabel(NAME_INFO_BEST, "Best Affordable: none")
	end

	local seen = {}
	if Ctx.BestWeaponESP and Ctx.BestWeaponShelf then
		local shelf = Ctx.BestWeaponShelf
		local target = getShelfHighlightTarget(shelf)
		if target then
			seen[shelf] = true
			local entry = Ctx.BestWeaponAdornments[shelf]
			local labelText = string.format("BEST: %s ($%s)", Ctx.BestWeaponName or shelf.Name, formatPrice(Ctx.BestWeaponPrice))
			if not entry then
				local hl = makeHighlight(target, Ctx.BestWeaponColor, Ctx.BestWeaponColor)
				local bg, lab = makeBillboard(target, labelText, Ctx.BestWeaponColor)
				Ctx.BestWeaponAdornments[shelf] = { Highlight = hl, Billboard = bg, Label = lab, Target = target }
			else
				if entry.Highlight then
					entry.Highlight.FillColor = Ctx.BestWeaponColor
					entry.Highlight.OutlineColor = Ctx.BestWeaponColor
					entry.Highlight.Adornee = target
				end
				if entry.Label then
					entry.Label.TextColor3 = Ctx.BestWeaponColor
					entry.Label.Text = labelText
				end
				if entry.Billboard then
					entry.Billboard.Adornee = getRootFromInstance(target)
				end
			end
		end
	end
	for k, entry in pairs(Ctx.BestWeaponAdornments) do
		if not seen[k] or not Ctx.BestWeaponESP then
			if entry.Highlight then pcall(function() entry.Highlight:Destroy() end) end
			if entry.Billboard then pcall(function() entry.Billboard:Destroy() end) end
			Ctx.BestWeaponAdornments[k] = nil
		end
	end
end

local function refreshStrongestESP()
	findStrongestPlayer()
	if Ctx.StrongestPlayer then
		setInfoLabel(NAME_INFO_STRONGEST, string.format("Strongest: %s ($%s)", Ctx.StrongestPlayer.Name, formatPrice(Ctx.StrongestValue)))
	else
		setInfoLabel(NAME_INFO_STRONGEST, "Strongest: none")
	end

	local seen = {}
	if Ctx.StrongestESP and Ctx.StrongestPlayer then
		local plr = Ctx.StrongestPlayer
		local char = plr.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
			if hrp then
				seen[plr] = true
				local entry = Ctx.PlayerAdornments[plr]
				local labelText = string.format("[STRONGEST] %s ($%s)", plr.Name, formatPrice(Ctx.StrongestValue))
				if not entry then
					local hl = makeHighlight(char, Ctx.StrongestColor, Ctx.StrongestColor)
					local bg, lab = makeBillboard(hrp, labelText, Ctx.StrongestColor)
					Ctx.PlayerAdornments[plr] = { Highlight = hl, Billboard = bg, Label = lab }
				else
					if entry.Highlight then
						entry.Highlight.FillColor = Ctx.StrongestColor
						entry.Highlight.OutlineColor = Ctx.StrongestColor
						entry.Highlight.Adornee = char
					end
					if entry.Label then
						entry.Label.TextColor3 = Ctx.StrongestColor
						entry.Label.Text = labelText
					end
					if entry.Billboard then entry.Billboard.Adornee = hrp end
				end
			end
		end
	end
	for k, entry in pairs(Ctx.PlayerAdornments) do
		if not seen[k] or not Ctx.StrongestESP then
			if entry.Highlight then pcall(function() entry.Highlight:Destroy() end) end
			if entry.Billboard then pcall(function() entry.Billboard:Destroy() end) end
			Ctx.PlayerAdornments[k] = nil
		end
	end
end

-- WeaponLocalScript.tryAttack upvalues (8 total):
--   idx 1: nextAllowedTick (number)
--   idx 2: BaseCooldown (number) - кэш атрибута на момент equip
--   idx 3: AnimationTrack (Instance)
--   idx 4..6: tables / disconnect-fn (touch handlers) - НЕ ТРОГАТЬ
--   idx 7: AnimationTime (number) - используется как u16:AdjustSpeed(u16.Length/u8).
--          Уменьшая u8 (idx7) - анимация играет быстрее, маркеры HitboxStart/HitboxEnd
--          срабатывают раньше, и FireServer летит быстрее.
--   idx 8: ReplicatedStorage
local IDX_NEXT_TICK = 1
local IDX_BASE_COOLDOWN = 2
local IDX_ANIM_TIME = 7

-- В Roblox-executors debug.getupvalue нестандартен: некоторые возвращают (value),
-- некоторые (name, value). Берём первый non-nil number из двух возвратов.
local function readUpvalNumber(fn, idx)
	local ok, a, b = pcall(debug.getupvalue, fn, idx)
	if not ok then return nil end
	if type(a) == "number" then return a end
	if type(b) == "number" then return b end
	return nil
end

local function findAllTryAttackFns()
	-- Ищем все tryAttack функции через все Tool.Activated connections - это даёт ЖИВЫЕ
	-- closures, в отличие от getgc-сканирования (там много мёртвых copies).
	local out = {}
	local seen = {}
	if not (LocalPlayer and getconnections) then return out end
	local function scan(parent)
		if not parent then return end
		for _, t in ipairs(parent:GetChildren()) do
			if t:IsA("Tool") then
				local ok, conns = pcall(getconnections, t.Activated)
				if ok and type(conns) == "table" then
					for _, c in ipairs(conns) do
						local fn = nil
						pcall(function() fn = c.Function end)
						if not fn then pcall(function() fn = c.Func end) end
						if type(fn) == "function" and not seen[fn] then
							seen[fn] = true
							-- проверяем что это tryAttack
							local okn, name = pcall(debug.info, fn, "n")
							if okn and name == "tryAttack" then
								table.insert(out, { fn = fn, tool = t })
							end
						end
					end
				end
			end
		end
	end
	scan(LocalPlayer.Character)
	scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
	return out
end

local function patchAttackFn(fn, multiplier, tool)
	-- Оригинальный AnimationTime берём ТОЛЬКО из атрибута Tool - это исходное значение от
	-- сервера, оно НЕ меняется. Чтение через debug.getupvalue ненадёжно: может вернуть
	-- уже-патченное значение от предыдущего запуска скрипта.
	if Ctx.OriginalAnimTimes[fn] == nil then
		local origFromAttr = tool and tonumber(tool:GetAttribute("AnimationTime"))
		if not (origFromAttr and origFromAttr > 0) then
			-- fallback: только если атрибута нет (не должно случаться) - читаем upv
			origFromAttr = readUpvalNumber(fn, IDX_ANIM_TIME)
			if not (origFromAttr and origFromAttr > 0) then return false end
		end
		Ctx.OriginalAnimTimes[fn] = origFromAttr
	end
	local origAnim = Ctx.OriginalAnimTimes[fn]
	if not (origAnim and origAnim > 0) then return false end

	local newAnim = origAnim / multiplier
	if newAnim < 0.05 then newAnim = 0.05 end -- предохранитель против AdjustSpeed(huge)

	-- Cooldown - в 0. Сервер не валидирует cooldown, валидирует только сам hit-event,
	-- а маркер HitboxStart/HitboxEnd определяется анимацией - её мы и ускоряем.
	pcall(debug.setupvalue, fn, IDX_BASE_COOLDOWN, 0)
	pcall(debug.setupvalue, fn, IDX_NEXT_TICK, 0)
	pcall(debug.setupvalue, fn, IDX_ANIM_TIME, newAnim)
	Ctx.PatchedAttackFns[fn] = true
	return true
end

local function restoreAttackFn(fn)
	local orig = Ctx.OriginalAnimTimes[fn]
	if orig then
		pcall(debug.setupvalue, fn, IDX_ANIM_TIME, orig)
	end
	-- nextAllowedTick / BaseCooldown оставим - сервер не блочит, и при де-equip они
	-- всё равно перезапишутся при следующем equip; рестор в "0" безвреден.
	Ctx.PatchedAttackFns[fn] = nil
end

local function patchAllAttackFns()
	if not (debug and debug.getupvalue and debug.setupvalue) then return end
	for _, info in ipairs(findAllTryAttackFns()) do
		patchAttackFn(info.fn, Ctx.AttackSpeed, info.tool)
	end
	-- Также понижаем атрибут BaseCooldown на самих Tool-ах - удобно для visual indicators.
	if LocalPlayer then
		local function zeroAttr(parent)
			if not parent then return end
			for _, t in ipairs(parent:GetChildren()) do
				if t:IsA("Tool") then
					pcall(function() t:SetAttribute("BaseCooldown", 0) end)
				end
			end
		end
		zeroAttr(LocalPlayer.Character)
		zeroAttr(LocalPlayer:FindFirstChildOfClass("Backpack"))
	end
end

local function bindBackpackForFastAttack()
	for _, c in ipairs(Ctx.BackpackConns) do
		pcall(function() c:Disconnect() end)
	end
	Ctx.BackpackConns = {}
	if not LocalPlayer then return end

	local function bindContainer(container)
		if not container then return end
		table.insert(Ctx.BackpackConns, container.ChildAdded:Connect(function(child)
			if Ctx.FastAttack and child:IsA("Tool") then
				task.defer(function()
					-- tryAttack создаётся при equip; ретраим несколько раз.
					for _ = 1, 10 do
						task.wait(0.15)
						if not Ctx.FastAttack then return end
						patchAllAttackFns()
					end
				end)
			end
		end))
	end
	bindContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
	bindContainer(LocalPlayer.Character)
end

local function startAttackHeartbeat()
	if Ctx.AttackHeartbeatConn then return end
	if not (debug and debug.setupvalue) then return end
	-- Раз в ~0.2с пере-сканируем connections (для новых tools), плюс держим cooldown=0.
	local rescanAccum = 0
	Ctx.AttackHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not Ctx.FastAttack then return end
		local mult = Ctx.AttackSpeed or 2.0
		rescanAccum = rescanAccum + dt
		if rescanAccum >= 0.5 then
			rescanAccum = 0
			-- discover new live tryAttack closures (после equip нового tool)
			for _, info in ipairs(findAllTryAttackFns()) do
				if not Ctx.PatchedAttackFns[info.fn] then
					patchAttackFn(info.fn, mult, info.tool)
				end
			end
		end
		for fn, _ in pairs(Ctx.PatchedAttackFns) do
			local orig = Ctx.OriginalAnimTimes[fn]
			if orig and orig > 0 then
				local newAnim = orig / mult
				if newAnim < 0.05 then newAnim = 0.05 end
				pcall(debug.setupvalue, fn, IDX_NEXT_TICK, 0)
				pcall(debug.setupvalue, fn, IDX_BASE_COOLDOWN, 0)
				pcall(debug.setupvalue, fn, IDX_ANIM_TIME, newAnim)
			end
		end
	end)
end

local function stopAttackHeartbeat()
	if Ctx.AttackHeartbeatConn then
		pcall(function() Ctx.AttackHeartbeatConn:Disconnect() end)
		Ctx.AttackHeartbeatConn = nil
	end
end

local function applyFastAttack()
	if not Ctx.FastAttack then return end
	patchAllAttackFns()
	startAttackHeartbeat()
end

local function restoreAttack()
	stopAttackHeartbeat()
	for fn, _ in pairs(Ctx.PatchedAttackFns) do
		restoreAttackFn(fn)
	end
	Ctx.PatchedAttackFns = {}
end

local function disconnectHumanoidConns()
	for _, c in ipairs(Ctx.HumanoidConns) do
		pcall(function() c:Disconnect() end)
	end
	Ctx.HumanoidConns = {}
end

local function applyNoclipOnce(char)
	if not Ctx.Noclip or not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			if p.CanCollide then
				p.CanCollide = false
			end
		end
	end
end

local function startNoclip()
	if Ctx.NoclipConn then return end
	Ctx.NoclipConn = RunService.Stepped:Connect(function()
		if not Ctx.Noclip then return end
		local char = LocalPlayer and LocalPlayer.Character
		if not char then return end
		applyNoclipOnce(char)
	end)
end

local function stopNoclip()
	if Ctx.NoclipConn then
		pcall(function() Ctx.NoclipConn:Disconnect() end)
		Ctx.NoclipConn = nil
	end
end

local function disconnectPromptConns()
	for _, c in ipairs(Ctx.PromptListConns) do
		pcall(function() c:Disconnect() end)
	end
	Ctx.PromptListConns = {}
	if Ctx.PromptDescConn then
		pcall(function() Ctx.PromptDescConn:Disconnect() end)
		Ctx.PromptDescConn = nil
	end
	if Ctx.PromptShownConn then
		pcall(function() Ctx.PromptShownConn:Disconnect() end)
		Ctx.PromptShownConn = nil
	end
end

local function patchPrompt(p)
	if not p or not p:IsA("ProximityPrompt") then return end
	if Ctx.PromptOriginalHold[p] == nil then
		Ctx.PromptOriginalHold[p] = p.HoldDuration
	end
	pcall(function() p.HoldDuration = 0 end)
end

local function unpatchPrompt(p)
	if not p or not p:IsA("ProximityPrompt") then return end
	local orig = Ctx.PromptOriginalHold[p]
	if orig ~= nil then
		pcall(function() p.HoldDuration = orig end)
	end
	Ctx.PromptOriginalHold[p] = nil
end

local function applyFastEAll()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then patchPrompt(d) end
	end
end

local function restoreFastEAll()
	for p, _ in pairs(Ctx.PromptOriginalHold) do
		unpatchPrompt(p)
	end
	Ctx.PromptOriginalHold = {}
end

local function bindFastE()
	disconnectPromptConns()
	applyFastEAll()
	-- Все будущие prompts ловим через DescendantAdded и через PromptShown (как fallback)
	Ctx.PromptDescConn = Workspace.DescendantAdded:Connect(function(inst)
		if not Ctx.FastE then return end
		if inst:IsA("ProximityPrompt") then
			patchPrompt(inst)
		end
	end)
	Ctx.PromptShownConn = ProximityPromptService.PromptShown:Connect(function(prompt)
		if Ctx.FastE then
			patchPrompt(prompt)
		end
	end)
end

local function startSpin()
	if Ctx.SpinConn then return end
	Ctx.SpinConn = RunService.Heartbeat:Connect(function()
		if not Ctx.Spin then return end
		local char = LocalPlayer and LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local step = math.rad(Ctx.SpinSpeed or 10)
		pcall(function()
			hrp.CFrame = hrp.CFrame * CFrame.Angles(0, step, 0)
		end)
	end)
end

local function stopSpin()
	if Ctx.SpinConn then
		pcall(function() Ctx.SpinConn:Disconnect() end)
		Ctx.SpinConn = nil
	end
end

local function onCharacterAdded(char)
	disconnectHumanoidConns()
	task.wait(0.3)
	if Ctx.FastAttack then
		bindBackpackForFastAttack()
		applyFastAttack()
	end
	if Ctx.Noclip then
		applyNoclipOnce(char)
	end
end

local function startMagnetThread()
	if Ctx.MagnetThread then return end
	Ctx.MagnetThread = task.spawn(function()
		local lastTarget = nil
		local targetStuckSince = 0
		while Ctx.Alive do
			if Ctx.CoinMagnet then
				local char = LocalPlayer.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local folder = getCoinsFolder()
				if hrp and folder then
					local nearestModel, nearestHB, nd
					for _, m in ipairs(folder:GetChildren()) do
						if m:IsA("Model") and m.Name == "Money" then
							local hb = m:FindFirstChild("MoneyHitbox")
							if hb and hb:IsA("BasePart") then
								local d = (hb.Position - hrp.Position).Magnitude
								if not nd or d < nd then
									nd = d
									nearestHB = hb
									nearestModel = m
								end
							end
						end
					end
					if nearestHB and nearestModel then
						-- если та же монета "залипает" больше 0.6 сек — пропускаем её
						if lastTarget == nearestModel then
							targetStuckSince = targetStuckSince + 1
						else
							lastTarget = nearestModel
							targetStuckSince = 0
						end

						pcall(function()
							hrp.CFrame = CFrame.new(nearestHB.Position + Vector3.new(0, 2, 0))
						end)
						-- форсим Touch — большинство executors поддерживают firetouchinterest
						if firetouchinterest then
							pcall(function()
								firetouchinterest(hrp, nearestHB, 0)
								firetouchinterest(hrp, nearestHB, 1)
							end)
						end

						-- если после 4 итераций монета не пропала — игнорим её на этой итерации, но в следующий тик пересчитаем (она может уже измениться)
						if targetStuckSince > 4 then
							-- "пнём" чуть в сторону, чтобы Touch запустился через physics
							pcall(function()
								hrp.CFrame = CFrame.new(nearestHB.Position - Vector3.new(0, 0.5, 0))
							end)
							targetStuckSince = 0
						end
					else
						lastTarget = nil
						targetStuckSince = 0
					end
				end
			else
				lastTarget = nil
				targetStuckSince = 0
			end
			task.wait(0.1)
		end
	end)
end

local function startMainLoop()
	if Ctx.HeartbeatConn then return end
	local accum = 0
	local cashAccum = 0
	Ctx.HeartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if not Ctx.Alive then return end

		accum = accum + dt
		if accum >= 0.5 then
			accum = 0
			refreshBestWeaponESP()
			refreshStrongestESP()
		end

		cashAccum = cashAccum + dt
		if cashAccum >= 0.25 then
			cashAccum = 0
			setInfoLabel(NAME_INFO_CASH, "Cash: $" .. formatPrice(getCash()))
			local cf = getCoinsFolder()
			local coinCount = 0
			if cf then
				for _, m in ipairs(cf:GetChildren()) do
					if m:IsA("Model") and m.Name == "Money" then
						coinCount = coinCount + 1
					end
				end
			end
			setInfoLabel(NAME_INFO_COINS, "Coins on map: " .. coinCount)
		end
	end)
end

local function buildWindow()
	return Library:Create({
		Title = "tg: @sigmatik323",
		ConfigName = "Fight in a Supermarket",
		SearchPlaceholder = "Search modules...",
		Accent = "#f6c343",
		AccentSoft = "#fcd34d",
		WindowFill = "#0b1020d9",
		DimBackground = "#02061766",
		GuiToggleKey = Enum.KeyCode.RightShift,
		Tabs = {
			{
				Name = TAB_NAME,
				Icon = "misc",
				Modules = {
					{
						Name = MODULE_VISUALS,
						Enabled = false,
						Sections = {
							{
								Name = SECTION_VISUALS,
								Controls = {
									{
										Type = "toggle",
										Name = NAME_COIN_ESP,
										CurrentValue = false,
										Callback = function(value)
											Ctx.CoinESP = not not value
											if Ctx.CoinESP then
												bindCoinFolder()
											else
												clearCoinESP()
											end
										end,
									},
									{
										Type = "toggle",
										Name = NAME_BEST_WEAPON_ESP,
										CurrentValue = false,
										Callback = function(value)
											Ctx.BestWeaponESP = not not value
											if not value then refreshBestWeaponESP() end
										end,
									},
									{
										Type = "toggle",
										Name = NAME_STRONGEST_PLAYER_ESP,
										CurrentValue = false,
										Callback = function(value)
											Ctx.StrongestESP = not not value
											if not value then refreshStrongestESP() end
										end,
									},
								},
							},
							{
								Name = SECTION_COLORS,
								Controls = {
									{
										Type = "colorpicker",
										Name = NAME_COIN_COLOR,
										CurrentValue = DEFAULT_COIN_COLOR,
										Callback = function(value)
											Ctx.CoinColor = hexToColor3(value)
											refreshCoinESPColors()
										end,
									},
									{
										Type = "colorpicker",
										Name = NAME_BEST_WEAPON_COLOR,
										CurrentValue = DEFAULT_BEST_WEAPON_COLOR,
										Callback = function(value)
											Ctx.BestWeaponColor = hexToColor3(value)
										end,
									},
									{
										Type = "colorpicker",
										Name = NAME_STRONGEST_COLOR,
										CurrentValue = DEFAULT_STRONGEST_COLOR,
										Callback = function(value)
											Ctx.StrongestColor = hexToColor3(value)
										end,
									},
								},
							},
							{
								Name = SECTION_INFO,
								Controls = {
									{
										Type = "label",
										Name = NAME_INFO_CASH,
										Content = NAME_INFO_CASH,
									},
									{
										Type = "label",
										Name = NAME_INFO_COINS,
										Content = NAME_INFO_COINS,
									},
									{
										Type = "label",
										Name = NAME_INFO_BEST,
										Content = NAME_INFO_BEST,
									},
									{
										Type = "label",
										Name = NAME_INFO_STRONGEST,
										Content = NAME_INFO_STRONGEST,
									},
								},
							},
						},
					},
					{
						Name = MODULE_COMBAT,
						Enabled = false,
						Sections = {
							{
								Name = SECTION_COMBAT,
								Controls = {
									{
										Type = "toggle",
										Name = NAME_FAST_ATTACK,
										CurrentValue = false,
										Callback = function(value)
											Ctx.FastAttack = not not value
											if Ctx.FastAttack then
												bindBackpackForFastAttack()
												applyFastAttack()
											else
												restoreAttack()
											end
										end,
									},
									{
										Type = "slider",
										Name = NAME_ATTACK_SPEED,
										Min = 1.0,
										Max = 2.5,
										Increment = 0.1,
										CurrentValue = 2.0,
										Callback = function(value)
											local v = tonumber(value) or 2.0
											if v < 1.0 then v = 1.0 end
											if v > 2.5 then v = 2.5 end
											Ctx.AttackSpeed = v
											if Ctx.FastAttack and debug and debug.setupvalue then
												for fn, _ in pairs(Ctx.PatchedAttackFns) do
													local orig = Ctx.OriginalAnimTimes[fn]
													if orig and orig > 0 then
														local newAnim = orig / v
														if newAnim < 0.05 then newAnim = 0.05 end
														pcall(debug.setupvalue, fn, IDX_ANIM_TIME, newAnim)
													end
												end
											end
										end,
									},
								},
							},
						},
					},
					{
						Name = MODULE_ECONOMY,
						Enabled = false,
						Sections = {
							{
								Name = SECTION_ECONOMY,
								Controls = {
									{
										Type = "toggle",
										Name = NAME_COIN_MAGNET,
										CurrentValue = false,
										Callback = function(value)
											Ctx.CoinMagnet = not not value
											if Ctx.CoinMagnet then
												startMagnetThread()
											end
										end,
									},
									{
										Type = "toggle",
										Name = NAME_FAST_E,
										CurrentValue = false,
										Callback = function(value)
											Ctx.FastE = not not value
											if Ctx.FastE then
												bindFastE()
											else
												disconnectPromptConns()
												restoreFastEAll()
											end
										end,
									},
								},
							},
						},
					},
					{
						Name = MODULE_MOVEMENT,
						Enabled = false,
						Sections = {
							{
								Name = SECTION_MOVEMENT,
								Controls = {
									{
										Type = "toggle",
										Name = NAME_SPIN,
										CurrentValue = false,
										Callback = function(value)
											Ctx.Spin = not not value
											if Ctx.Spin then
												startSpin()
											else
												stopSpin()
											end
										end,
									},
									{
										Type = "slider",
										Name = NAME_SPIN_SPEED,
										Min = 1,
										Max = 50,
										Increment = 1,
										CurrentValue = 10,
										Callback = function(value)
											local v = tonumber(value) or 10
											if v < 1 then v = 1 end
											if v > 50 then v = 50 end
											Ctx.SpinSpeed = v
										end,
									},
									{
										Type = "toggle",
										Name = NAME_NOCLIP,
										CurrentValue = false,
										Callback = function(value)
											Ctx.Noclip = not not value
											if Ctx.Noclip then
												startNoclip()
											else
												stopNoclip()
												local char = LocalPlayer and LocalPlayer.Character
												if char then
													for _, p in ipairs(char:GetDescendants()) do
														if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
															pcall(function() p.CanCollide = true end)
														end
													end
												end
											end
										end,
									},
								},
							},
						},
					},
				},
			},
		},
	})
end

local function cleanup()
	Ctx.Alive = false
	Ctx.CoinESP = false
	Ctx.BestWeaponESP = false
	Ctx.StrongestESP = false
	Ctx.FastAttack = false
	Ctx.CoinMagnet = false
	Ctx.Spin = false
	Ctx.FastE = false
	local wasNoclip = Ctx.Noclip
	Ctx.Noclip = false

	disconnectPromptConns()
	restoreFastEAll()
	stopAttackHeartbeat()

	stopSpin()
	stopNoclip()
	if wasNoclip and LocalPlayer and LocalPlayer.Character then
		for _, p in ipairs(LocalPlayer.Character:GetDescendants()) do
			if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
				pcall(function() p.CanCollide = true end)
			end
		end
	end

	if Ctx.HeartbeatConn then
		pcall(function() Ctx.HeartbeatConn:Disconnect() end)
		Ctx.HeartbeatConn = nil
	end
	if Ctx.CharConn then
		pcall(function() Ctx.CharConn:Disconnect() end)
		Ctx.CharConn = nil
	end
	for _, c in ipairs(Ctx.BackpackConns) do
		pcall(function() c:Disconnect() end)
	end
	Ctx.BackpackConns = {}
	disconnectCoinFolderConns()
	disconnectHumanoidConns()
	restoreAttack()
	clearAllAdornments()
	if Ctx.ESPFolder then
		pcall(function() Ctx.ESPFolder:Destroy() end)
		Ctx.ESPFolder = nil
	end
	if Ctx.Window then
		pcall(function() Ctx.Window:Destroy() end)
		Ctx.Window = nil
	end
	SharedEnvironment.SigmatikFightInASupermarketContext = nil
end

Ctx.Cleanup = cleanup

Ctx.Window = buildWindow()
startMainLoop()
Ctx.CharConn = LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
