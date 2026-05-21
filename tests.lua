local LIBRARY_URL = "https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"
local LOCAL_LIBRARY_PATHS = {
	"sigmatik_ui_library.lua",
	"gui_lua/sigmatik_ui_library.lua",
	"../gui_lua/sigmatik_ui_library.lua",
	"..\\gui_lua\\sigmatik_ui_library.lua",
	"D:/Нужное/Скрипты роблокс/Делаем скрипты тут/gui_lua/sigmatik_ui_library.lua",
}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

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

	if loadstring and game.HttpGet then
		local ok, source = pcall(function()
			return game:HttpGet(LIBRARY_URL)
		end)

		if ok and source then
			return loadstring(source)()
		end
	end

	error("Sigmatik UI library could not be loaded")
end

local previousContext = getgenv and getgenv().SigmatikTestsContext
if previousContext and previousContext.Cleanup then
	pcall(previousContext.Cleanup)
end

local Library = loadLibrary()

local function parseHex(hex)
	local clean = tostring(hex or "#ffffff"):gsub("#", "")
	if #clean < 6 then
		clean = clean .. string.rep("f", 6 - #clean)
	end

	local r = tonumber(clean:sub(1, 2), 16) or 255
	local g = tonumber(clean:sub(3, 4), 16) or 255
	local b = tonumber(clean:sub(5, 6), 16) or 255
	return Color3.fromRGB(r, g, b)
end

local function getRootPart()
	local character = LocalPlayer and LocalPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local character = LocalPlayer and LocalPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getCamera()
	return Workspace.CurrentCamera
end

local state = {
	gui = nil,
	runCount = 0,
	delay = 0.18,
	repeatChecks = false,
	autoModuleFlip = true,
	resetAfterRun = true,
	lastEvent = "Idle",
	checksRunning = false,
	preview = {
		enabled = false,
		spin = false,
		follow = true,
		pulseLight = false,
		rainbow = false,
		size = 8,
		spinSpeed = 90,
		heightOffset = 6,
		color = "#38bdf8",
		lightColor = "#22c55e",
	},
	visuals = {
		enabled = false,
		fullBright = false,
		noFog = false,
		fov = 78,
		clockTime = 14,
		ambient = "#dbeafe",
	},
}

local saved = {
	brightness = Lighting.Brightness,
	globalShadows = Lighting.GlobalShadows,
	fogStart = Lighting.FogStart,
	fogEnd = Lighting.FogEnd,
	clockTime = Lighting.ClockTime,
	ambient = Lighting.Ambient,
	outdoorAmbient = Lighting.OutdoorAmbient,
	fieldOfView = getCamera() and getCamera().FieldOfView or 70,
}

local runtime = {
	part = nil,
	light = nil,
	connection = nil,
	spinAngle = 0,
	hue = 0,
	lastPreviewPosition = nil,
}

local function logState(name, value)
	state.lastEvent = string.format("%s -> %s", name, tostring(value))
	print("[SigmatikUI/Tests] " .. state.lastEvent)
end

local function ensurePreviewPart()
	if runtime.part and runtime.part.Parent then
		return runtime.part
	end

	local part = Instance.new("Part")
	part.Name = "SigmatikTestsPreview"
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = Vector3.new(state.preview.size, state.preview.size, state.preview.size)
	part.Color = parseHex(state.preview.color)
	part.Parent = Workspace

	local light = Instance.new("PointLight")
	light.Name = "PreviewLight"
	light.Brightness = 0
	light.Range = 0
	light.Color = parseHex(state.preview.lightColor)
	light.Parent = part

	runtime.part = part
	runtime.light = light
	return part
end

local function clearPreviewPart()
	if runtime.part then
		runtime.part:Destroy()
		runtime.part = nil
	end

	runtime.light = nil
	runtime.lastPreviewPosition = nil
end

local function applyPreviewVisuals()
	local part = ensurePreviewPart()
	local light = runtime.light
	local previewColor = state.preview.rainbow and Color3.fromHSV(runtime.hue, 0.85, 1) or parseHex(state.preview.color)

	part.Size = Vector3.new(state.preview.size, state.preview.size, state.preview.size)
	part.Color = previewColor

	if light then
		light.Color = parseHex(state.preview.lightColor)
		light.Enabled = state.preview.pulseLight
		light.Range = state.preview.pulseLight and (state.preview.size * 5) or 0
	end
end

local function setPreviewEnabled(enabled)
	state.preview.enabled = not not enabled
	logState("Preview Module", state.preview.enabled)

	if state.preview.enabled then
		ensurePreviewPart()
		applyPreviewVisuals()
	else
		clearPreviewPart()
	end
end

local function applyVisuals()
	local camera = getCamera()

	if not state.visuals.enabled then
		Lighting.Brightness = saved.brightness
		Lighting.GlobalShadows = saved.globalShadows
		Lighting.FogStart = saved.fogStart
		Lighting.FogEnd = saved.fogEnd
		Lighting.ClockTime = saved.clockTime
		Lighting.Ambient = saved.ambient
		Lighting.OutdoorAmbient = saved.outdoorAmbient

		if camera then
			camera.FieldOfView = saved.fieldOfView
		end

		return
	end

	Lighting.ClockTime = state.visuals.clockTime
	Lighting.Ambient = parseHex(state.visuals.ambient)
	Lighting.OutdoorAmbient = parseHex(state.visuals.ambient)

	if state.visuals.fullBright then
		Lighting.Brightness = 4
		Lighting.GlobalShadows = false
	else
		Lighting.Brightness = saved.brightness
		Lighting.GlobalShadows = saved.globalShadows
	end

	if state.visuals.noFog then
		Lighting.FogStart = 0
		Lighting.FogEnd = 100000
	else
		Lighting.FogStart = saved.fogStart
		Lighting.FogEnd = saved.fogEnd
	end

	if camera then
		camera.FieldOfView = state.visuals.fov
	end
end

local function setVisualsEnabled(enabled)
	state.visuals.enabled = not not enabled
	logState("Scene Module", state.visuals.enabled)
	applyVisuals()
end

local function updateWalkSpeed(speed)
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

local function updatePreview(dt)
	if not state.preview.enabled then
		return
	end

	local part = ensurePreviewPart()
	local rootPart = getRootPart()

	runtime.hue = (runtime.hue + (dt * 0.15)) % 1

	if state.preview.follow and rootPart then
		runtime.lastPreviewPosition = rootPart.Position + rootPart.CFrame.LookVector * 8 + Vector3.new(0, state.preview.heightOffset, 0)
	elseif not runtime.lastPreviewPosition then
		runtime.lastPreviewPosition = rootPart and (rootPart.Position + Vector3.new(0, state.preview.heightOffset, -8)) or Vector3.new(0, state.preview.heightOffset, 0)
	end

	local targetPosition = runtime.lastPreviewPosition or Vector3.new(0, state.preview.heightOffset, 0)
	if state.preview.spin then
		runtime.spinAngle = runtime.spinAngle + (state.preview.spinSpeed * dt)
	end

	local rotation = CFrame.Angles(0, math.rad(runtime.spinAngle), 0)
	part.CFrame = CFrame.new(targetPosition) * rotation

	applyPreviewVisuals()

	if runtime.light and state.preview.pulseLight then
		runtime.light.Brightness = 1.5 + math.abs(math.sin(time() * 3)) * 4
	else
		if runtime.light then
			runtime.light.Brightness = 0
		end
	end
end

runtime.connection = RunService.RenderStepped:Connect(function(dt)
	updatePreview(dt)
	applyVisuals()
end)

local function stepWait()
	task.wait(state.delay)
end

local TAB_PREVIEW = "🧪 Preview"
local TAB_VISUALS = "🎨 Visuals"
local TAB_RUNTIME = "⚙️ Runtime"

local MODULE_PREVIEW = "Preview Part"
local MODULE_SCENE = "Scene Effects"
local MODULE_RUNTIME = "Runtime API"

local SECTION_PREVIEW_INFO = "🧩 Preview Info"
local SECTION_PREVIEW_BEHAVIOR = "🛸 Preview Behavior"
local SECTION_PREVIEW_STYLE = "🎨 Preview Style"
local SECTION_SCENE_INFO = "🌤️ Scene Info"
local SECTION_SCENE_CONTROL = "🌈 Scene Control"
local SECTION_RUNTIME_CONTROL = "⚙️ Scripted Checks"

local function runSinglePass(gui, passIndex)
	logState("Check Pass", passIndex)
	logState("GetTab", gui:GetTab(TAB_PREVIEW) ~= nil)
	logState("GetModule", gui:GetModule(TAB_PREVIEW, MODULE_PREVIEW) ~= nil)

	if state.autoModuleFlip then
		gui:SetModuleEnabled(TAB_PREVIEW, MODULE_PREVIEW, true)
		stepWait()
		gui:SetModuleEnabled(TAB_VISUALS, MODULE_SCENE, true)
		stepWait()
	end

	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_BEHAVIOR, "Follow Player", true)
	stepWait()
	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_BEHAVIOR, "Spin Preview", true)
	stepWait()
	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_BEHAVIOR, "Pulse Light", passIndex % 2 == 1)
	stepWait()
	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_BEHAVIOR, "Rainbow Color", passIndex % 2 == 0)
	stepWait()
	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Part Size", 14)
	stepWait()
	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Spin Speed", 180)
	stepWait()
	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Height Offset", 10)
	stepWait()
	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Part Color", passIndex % 2 == 1 and "#f97316" or "#38bdf8")
	stepWait()
	gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Light Color", passIndex % 2 == 1 and "#eab308" or "#22c55e")
	stepWait()

	gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "FullBright", true)
	stepWait()
	gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "No Fog", true)
	stepWait()
	gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "Field Of View", 110)
	stepWait()
	gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "Clock Time", 22)
	stepWait()
	gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "Ambient Color", passIndex % 2 == 1 and "#fca5a5" or "#dbeafe")
	stepWait()
	gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "Walk Speed", 34)
	stepWait()

	if state.resetAfterRun then
		gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_BEHAVIOR, "Spin Preview", false)
		stepWait()
		gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_BEHAVIOR, "Pulse Light", false)
		stepWait()
		gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_BEHAVIOR, "Rainbow Color", false)
		stepWait()
		gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Part Size", 8)
		stepWait()
		gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Spin Speed", 90)
		stepWait()
		gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Height Offset", 6)
		stepWait()
		gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Part Color", "#38bdf8")
		stepWait()
		gui:SetControlValue(TAB_PREVIEW, MODULE_PREVIEW, SECTION_PREVIEW_STYLE, "Light Color", "#22c55e")
		stepWait()
		gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "FullBright", false)
		stepWait()
		gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "No Fog", false)
		stepWait()
		gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "Field Of View", 78)
		stepWait()
		gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "Clock Time", 14)
		stepWait()
		gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "Ambient Color", "#dbeafe")
		stepWait()
		gui:SetControlValue(TAB_VISUALS, MODULE_SCENE, SECTION_SCENE_CONTROL, "Walk Speed", 16)
		stepWait()
	end

	if state.autoModuleFlip then
		gui:SetModuleEnabled(TAB_VISUALS, MODULE_SCENE, false)
		stepWait()
		gui:SetModuleEnabled(TAB_PREVIEW, MODULE_PREVIEW, false)
		stepWait()
	end
end

local function runChecks(gui)
	if state.checksRunning then
		logState("Checks Running", true)
		return
	end

	state.checksRunning = true
	state.runCount = state.runCount + 1
	logState("Run Count", state.runCount)

	local passes = state.repeatChecks and 2 or 1
	for passIndex = 1, passes do
		runSinglePass(gui, passIndex)
	end

	state.checksRunning = false
	logState("Checks Complete", true)
end

local Gui = Library:Create({
	Title = "tg: @sigmatik323",
	ConfigName = "by sigmatik323",
	SearchPlaceholder = "Search modules...",
	Accent = "#38bdf8",
	AccentSoft = "#7dd3fc",
	BlurSize = 14,
	DimBackground = "#02061766",
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = TAB_PREVIEW,
			Icon = "misc",
			Modules = {
				{
					Name = MODULE_PREVIEW,
					Enabled = false,
					Callback = function(enabled)
						setPreviewEnabled(enabled)
					end,
					Sections = {
						{
							Name = SECTION_PREVIEW_INFO,
							Controls = {
								{
									Type = "Paragraph",
									Name = "Overview",
									Content = "Enable the module to spawn a floating neon preview ball near your character. The controls below change it in real time.",
								},
								{
									Type = "Label",
									Name = "Preview Status",
									Content = "This module creates a visible test object, so every control now has an in-game effect.",
								},
							},
						},
						{
							Name = SECTION_PREVIEW_BEHAVIOR,
							Controls = {
								{
									Type = "Toggle",
									Name = "Follow Player",
									CurrentValue = true,
									Callback = function(value)
										state.preview.follow = value
										logState("Follow Player", value)
									end,
								},
								{
									Type = "Checkbox",
									Name = "Spin Preview",
									Value = false,
									Callback = function(value)
										state.preview.spin = value
										logState("Spin Preview", value)
									end,
								},
								{
									Type = "Checkbox",
									Name = "Pulse Light",
									Value = false,
									Callback = function(value)
										state.preview.pulseLight = value
										logState("Pulse Light", value)
									end,
								},
								{
									Type = "Toggle",
									Name = "Rainbow Color",
									Value = false,
									Callback = function(value)
										state.preview.rainbow = value
										logState("Rainbow Color", value)
									end,
								},
							},
						},
						{
							Name = SECTION_PREVIEW_STYLE,
							Controls = {
								{
									Type = "Slider",
									Name = "Part Size",
									Min = 2,
									Max = 20,
									Increment = 1,
									Value = state.preview.size,
									Callback = function(value)
										state.preview.size = value
										logState("Part Size", value)
									end,
								},
								{
									Type = "Slider",
									Name = "Spin Speed",
									Min = 0,
									Max = 360,
									Increment = 5,
									Value = state.preview.spinSpeed,
									Callback = function(value)
										state.preview.spinSpeed = value
										logState("Spin Speed", value)
									end,
								},
								{
									Type = "Slider",
									Name = "Height Offset",
									Min = 0,
									Max = 20,
									Increment = 0.5,
									CurrentValue = state.preview.heightOffset,
									Callback = function(value)
										state.preview.heightOffset = value
										logState("Height Offset", value)
									end,
								},
								{
									Type = "ColorPicker",
									Name = "Part Color",
									Value = state.preview.color,
									Callback = function(value)
										state.preview.color = value
										logState("Part Color", value)
									end,
								},
								{
									Type = "ColorPicker",
									Name = "Light Color",
									CurrentValue = state.preview.lightColor,
									Callback = function(value)
										state.preview.lightColor = value
										logState("Light Color", value)
									end,
								},
							},
						},
					},
				},
			},
		},
		{
			Name = TAB_VISUALS,
			Icon = "visuals",
			Modules = {
				{
					Name = MODULE_SCENE,
					Enabled = false,
					Callback = function(enabled)
						setVisualsEnabled(enabled)
					end,
					Sections = {
						{
							Name = SECTION_SCENE_INFO,
							Controls = {
								{
									Type = "Paragraph",
									Name = "Visual Note",
									Content = "This module changes Lighting, fog and camera FOV, so it is immediately visible even without checking console output.",
								},
								{
									Type = "Label",
									Name = "Visual Status",
									Content = "Disable the module to restore saved Lighting and camera values.",
								},
							},
						},
						{
							Name = SECTION_SCENE_CONTROL,
							Controls = {
								{
									Type = "Toggle",
									Name = "FullBright",
									Value = false,
									Callback = function(value)
										state.visuals.fullBright = value
										logState("FullBright", value)
										applyVisuals()
									end,
								},
								{
									Type = "Checkbox",
									Name = "No Fog",
									Value = false,
									Callback = function(value)
										state.visuals.noFog = value
										logState("No Fog", value)
										applyVisuals()
									end,
								},
								{
									Type = "Slider",
									Name = "Field Of View",
									Min = 40,
									Max = 120,
									Increment = 1,
									CurrentValue = state.visuals.fov,
									Callback = function(value)
										state.visuals.fov = value
										logState("Field Of View", value)
										applyVisuals()
									end,
								},
								{
									Type = "Slider",
									Name = "Clock Time",
									Min = 0,
									Max = 24,
									Increment = 0.5,
									Value = state.visuals.clockTime,
									Callback = function(value)
										state.visuals.clockTime = value
										logState("Clock Time", value)
										applyVisuals()
									end,
								},
								{
									Type = "ColorPicker",
									Name = "Ambient Color",
									CurrentValue = state.visuals.ambient,
									Callback = function(value)
										state.visuals.ambient = value
										logState("Ambient Color", value)
										applyVisuals()
									end,
								},
								{
									Type = "Slider",
									Name = "Walk Speed",
									Min = 16,
									Max = 60,
									Increment = 1,
									Value = 16,
									Callback = function(value)
										updateWalkSpeed(value)
										logState("Walk Speed", value)
									end,
								},
							},
						},
					},
				},
			},
		},
		{
			Name = TAB_RUNTIME,
			Icon = "movement",
			Modules = {
				{
					Name = MODULE_RUNTIME,
					Enabled = false,
					Callback = function(enabled)
						logState("Runtime API", enabled)

						if enabled and state.gui then
							task.spawn(function()
								runChecks(state.gui)
								stepWait()
								state.gui:SetModuleEnabled(TAB_RUNTIME, MODULE_RUNTIME, false)
							end)
						end
					end,
					Sections = {
						{
							Name = SECTION_RUNTIME_CONTROL,
							Controls = {
								{
									Type = "Toggle",
									Name = "Repeat Checks",
									Value = false,
									Callback = function(value)
										state.repeatChecks = value
										logState("Repeat Checks", value)
									end,
								},
								{
									Type = "Slider",
									Name = "Check Delay",
									Min = 0.05,
									Max = 1,
									Increment = 0.05,
									Value = state.delay,
									Callback = function(value)
										state.delay = value
										logState("Check Delay", value)
									end,
								},
								{
									Type = "Toggle",
									Name = "Auto Module Flip",
									Value = true,
									Callback = function(value)
										state.autoModuleFlip = value
										logState("Auto Module Flip", value)
									end,
								},
								{
									Type = "Checkbox",
									Name = "Reset After Run",
									Value = true,
									Callback = function(value)
										state.resetAfterRun = value
										logState("Reset After Run", value)
									end,
								},
								{
									Type = "Label",
									Name = "Runtime Status",
									Content = "Enable Runtime API to run scripted SetModuleEnabled and SetControlValue checks with visible world changes.",
								},
								{
									Type = "Paragraph",
									Name = "Runtime Coverage",
									Content = "The scripted run toggles preview behavior, updates sliders and colors, then changes Lighting, fog, camera FOV and walk speed.",
								},
							},
						},
					},
				},
			},
		},
	},
})

state.gui = Gui

local function cleanup()
	if runtime.connection then
		runtime.connection:Disconnect()
		runtime.connection = nil
	end

	clearPreviewPart()
	state.visuals.enabled = false
	applyVisuals()

	if getgenv and getgenv().SigmatikTestsContext == state then
		getgenv().SigmatikTestsContext = nil
	end
end

state.Cleanup = cleanup

if getgenv then
	getgenv().SigmatikTestsContext = state
end

return Gui
