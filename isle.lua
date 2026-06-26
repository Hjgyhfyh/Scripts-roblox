local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "tg: @sigmatik323",
   LoadingTitle = "tg: @sigmatik323",
   LoadingSubtitle = "by sigmatik323",
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "Isle Hub"
   },
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = true
   },
   KeySystem = false,
})

-- Anti AFK
spawn(function()
    local vu = game:GetService("VirtualUser")
    game:GetService("Players").LocalPlayer.Idled:connect(function()
        vu:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        wait(1)
        vu:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    end)
end)

local VisualsTab = Window:CreateTab("Visuals", 4483362458)
local SectionESP = VisualsTab:CreateSection("ESP")

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local ESPItemsEnabled = false
local ESPItemsColor = Color3.fromRGB(0, 255, 0)
local ESPItemsContainer = Instance.new("Folder", workspace)
ESPItemsContainer.Name = "ESPItemsContainer"

local function UpdateESPItems()
    ESPItemsContainer:ClearAllChildren()
    if not ESPItemsEnabled then return end
    
    if workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Ignore") and workspace.Map.Ignore:FindFirstChild("Tools") then
         for _, tool in pairs(workspace.Map.Ignore.Tools:GetChildren()) do
            if tool:IsA("BasePart") or tool:IsA("Model") or tool:IsA("MeshPart") then
                local highlight = Instance.new("Highlight")
                highlight.Parent = ESPItemsContainer
                highlight.Adornee = tool
                highlight.FillColor = ESPItemsColor
                highlight.OutlineColor = Color3.new(1,1,1)
                highlight.FillTransparency = 0.5
                highlight.OutlineTransparency = 0
            end
         end
    end
end

RunService.RenderStepped:Connect(UpdateESPItems)

local ToggleESPItems = VisualsTab:CreateToggle({
   Name = "ESP Items",
   CurrentValue = false,
   Flag = "ESPItems",
   Callback = function(Value)
      ESPItemsEnabled = Value
   end,
})

local PickerESPItemsColor = VisualsTab:CreateColorPicker({
    Name = "ESP Items Color",
    Color = Color3.fromRGB(0, 255, 0),
    Flag = "ESPItemsColor", 
    Callback = function(Value)
        ESPItemsColor = Value
    end
})

local SectionLighting = VisualsTab:CreateSection("Lighting")

local FullBrightEnabled = false
local ToggleFullBright = VisualsTab:CreateToggle({
   Name = "FullBright",
   CurrentValue = false,
   Flag = "FullBright",
   Callback = function(Value)
      FullBrightEnabled = Value
      if FullBrightEnabled then
          spawn(function()
              while FullBrightEnabled do
                  Lighting.Brightness = 2
                  Lighting.ClockTime = 14
                  Lighting.FogEnd = 100000
                  Lighting.GlobalShadows = false
                  Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
                  wait(0.001)
              end
          end)
      end
   end,
})

local NoFogEnabled = false
local ToggleNoFog = VisualsTab:CreateToggle({
   Name = "No Fog",
   CurrentValue = false,
   Flag = "NoFog",
   Callback = function(Value)
      NoFogEnabled = Value
      if NoFogEnabled then
          spawn(function()
              while NoFogEnabled do
                  Lighting.FogEnd = 100000
                  wait(0.001)
              end
          end)
      end
   end,
})

local ItemsTab = Window:CreateTab("Items", 4483362458)
local SectionTeleportItems = ItemsTab:CreateSection("Teleport Items")

local ItemList = {}
local DropdownItems
local SelectedItemName = nil

local function RefreshItemList()
    ItemList = {}
    if workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Ignore") and workspace.Map.Ignore:FindFirstChild("Tools") then
        for _, tool in pairs(workspace.Map.Ignore.Tools:GetChildren()) do
            table.insert(ItemList, tool.Name)
        end
    end
    -- Rayfield dropdown update might need re-creation or specific update method if available
    -- Assuming Refresh method exists or we recreate. Rayfield standard usually has Refresh.
    if DropdownItems then
        DropdownItems:Refresh(ItemList)
    end
end

DropdownItems = ItemsTab:CreateDropdown({
    Name = "Item List",
    Options = ItemList,
    CurrentOption = {""},
    MultipleOptions = false,
    Flag = "ItemList",
    Callback = function(Option)
        if type(Option) == "table" then
            SelectedItemName = Option[1]
        else
            SelectedItemName = Option
        end
    end,
})

local ButtonRefreshItems = ItemsTab:CreateButton({
    Name = "Refresh Items",
    Callback = function()
        RefreshItemList()
    end,
})

local ButtonTeleportItem = ItemsTab:CreateButton({
    Name = "Teleport to Item",
    Callback = function()
        if SelectedItemName and workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Ignore") and workspace.Map.Ignore:FindFirstChild("Tools") then
            local tool = workspace.Map.Ignore.Tools:FindFirstChild(SelectedItemName)
            local character = game.Players.LocalPlayer.Character
            if tool and character and character:FindFirstChild("HumanoidRootPart") then
                local targetCFrame 
                if tool:IsA("Model") then
                    targetCFrame = tool:GetPivot()
                elseif tool:IsA("BasePart") or tool:IsA("MeshPart") then
                    targetCFrame = tool.CFrame
                end
                
                if targetCFrame then
                    character.HumanoidRootPart.CFrame = targetCFrame + Vector3.new(0, 3, 0)
                end
            end
        end
    end,
})

-- Initial Refresh
RefreshItemList()

Rayfield:LoadConfiguration()
