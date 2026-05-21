local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/sigmatik_ui_library.lua"))()
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local SharedEnvironment = getgenv and getgenv() or _G
local PreviousState = SharedEnvironment.SigmatikCubesIncrementalState
local LocalPlayer = Players.LocalPlayer

if PreviousState and PreviousState.Stop then
	PreviousState.Stop()
end

local State = {
	AutoFarmEnabled = false,
	AutoFarmThread = nil,
	Syncing = false,
}

SharedEnvironment.SigmatikCubesIncrementalState = State

local TAB_MAIN = "💎 Cubes"
local MODULE_MAIN = "✨ Cube Automation"
local SECTION_MAIN = "🚀 Main"
local AUTO_FARM_NAME = "Auto Farm Cubes"

local Gui

local function getCharacterRoot()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getCubeContainer()
	local scripted = Workspace:FindFirstChild("__Scripted")
	if not scripted then
		return nil
	end

	local clientCubes = scripted:FindFirstChild("__ClientCubes")
	if not clientCubes then
		return nil
	end

	return clientCubes:FindFirstChild("Cube")
end

local function moveInstanceToTarget(instance, targetCFrame)
	pcall(function()
		if instance:IsA("Model") then
			instance:PivotTo(targetCFrame)
		elseif instance:IsA("BasePart") then
			instance.CFrame = targetCFrame
		end
	end)
end

local function translateContainerContents(container, positionOffset)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			pcall(function()
				child:PivotTo(child:GetPivot() + positionOffset)
			end)
		elseif child:IsA("BasePart") then
			pcall(function()
				child.CFrame = child.CFrame + positionOffset
			end)
		elseif child:IsA("Folder") then
			translateContainerContents(child, positionOffset)
		end
	end
end

local function ensureAutoFarmLoop()
	if State.AutoFarmThread then
		return
	end

	State.AutoFarmThread = task.spawn(function()
		while State.AutoFarmEnabled do
			local rootPart = getCharacterRoot()
			local cubeContainer = getCubeContainer()

			if rootPart and cubeContainer then
				local targetCFrame = rootPart.CFrame

				if cubeContainer:IsA("Model") or cubeContainer:IsA("BasePart") then
					moveInstanceToTarget(cubeContainer, targetCFrame)
				else
					local referencePart = cubeContainer:FindFirstChildWhichIsA("BasePart", true)
					if referencePart then
						local positionOffset = targetCFrame.Position - referencePart.Position
						translateContainerContents(cubeContainer, positionOffset)
					end
				end
			end

			task.wait(0.05)
		end

		State.AutoFarmThread = nil
	end)
end

local function setAutoFarmState(value, source)
	State.AutoFarmEnabled = value

	if State.AutoFarmEnabled then
		ensureAutoFarmLoop()
	end

	if not Gui or State.Syncing then
		return
	end

	State.Syncing = true

	if source ~= "module" then
		Gui:SetModuleEnabled(TAB_MAIN, MODULE_MAIN, value)
	end

	if source ~= "toggle" then
		Gui:SetControlValue(TAB_MAIN, MODULE_MAIN, SECTION_MAIN, AUTO_FARM_NAME, value)
	end

	State.Syncing = false
end

State.Stop = function()
	setAutoFarmState(false, "shutdown")
end

Gui = Library:Create({
	Title = "tg: @sigmatik323",
	ConfigName = "by sigmatik323",
	SearchPlaceholder = "Search modules...",
	Accent = "#22d3ee",
	AccentSoft = "#67e8f9",
	BlurSize = 14,
	DimBackground = "#02061766",
	GuiToggleKey = Enum.KeyCode.RightShift,
	Tabs = {
		{
			Name = TAB_MAIN,
			Icon = "misc",
			Modules = {
				{
					Name = MODULE_MAIN,
					Enabled = false,
					Callback = function(enabled)
						setAutoFarmState(enabled, "module")
					end,
					Sections = {
						{
							Name = SECTION_MAIN,
							Controls = {
								{
									Type = "Toggle",
									Name = AUTO_FARM_NAME,
									CurrentValue = false,
									Callback = function(value)
										setAutoFarmState(value, "toggle")
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
