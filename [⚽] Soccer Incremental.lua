local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FrameworkRoot = Shared:WaitForChild("Util"):WaitForChild("modules"):WaitForChild("framework"):WaitForChild("")
local ClaimFootballRemote = FrameworkRoot:WaitForChild("Loop"):WaitForChild("RF"):WaitForChild("ClaimFootball")
local UpgradeRemote = FrameworkRoot:WaitForChild("Upgrades"):WaitForChild("RF"):WaitForChild("Upgrade")
local BuyBranchRemote = FrameworkRoot:WaitForChild("Upgrades"):WaitForChild("RF"):WaitForChild("BuyBranch")
local ResetRemote = FrameworkRoot:WaitForChild("Resets"):WaitForChild("RF"):WaitForChild("Reset")
local AscendRemote = FrameworkRoot:WaitForChild("Ascension"):WaitForChild("RF"):WaitForChild("Ascend")

local Window = Rayfield:CreateWindow({
   Name = "tg: @sigmatik323",
   LoadingTitle = "tg: @sigmatik323",
   LoadingSubtitle = "by sigmatik323",
   ConfigurationSaving = {
      Enabled = false,
      FolderName = nil,
      FileName = "tg: @sigmatik323"
   },
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = false
   },
   KeySystem = false,
   KeySettings = {
      Title = "tg: @sigmatik323",
      Subtitle = "Access",
      Note = "Disabled",
      FileName = "tg: @sigmatik323",
      SaveKey = false,
      GrabKeyFromSite = false,
      Key = {"disabled"}
   }
})

local MainTab = Window:CreateTab("Main", 4483362458)
local MainSection = MainTab:CreateSection("Main")
local AutoClickEnabled = false
local AutoClickConnection

local function StopAutoClick()
   if AutoClickConnection then
      AutoClickConnection:Disconnect()
      AutoClickConnection = nil
   end
end

local function StartAutoClick()
   StopAutoClick()
   AutoClickConnection = RunService.Heartbeat:Connect(function()
      if not AutoClickEnabled then
         StopAutoClick()
         return
      end
      local MousePosition = UserInputService:GetMouseLocation()
      VirtualInputManager:SendMouseButtonEvent(MousePosition.X, MousePosition.Y, 0, true, game, 0)
      VirtualInputManager:SendMouseButtonEvent(MousePosition.X, MousePosition.Y, 0, false, game, 0)
   end)
end

MainTab:CreateKeybind({
   Name = "Autoclicker Toggle",
   CurrentKeybind = "T",
   HoldToInteract = false,
   Flag = "AutoClickerToggle",
   Callback = function()
      AutoClickEnabled = not AutoClickEnabled
      if AutoClickEnabled then
         StartAutoClick()
      else
         StopAutoClick()
      end
   end
})

local AutoSection = MainTab:CreateSection("Auto Goal")
local AutoGoalEnabled = false
local AutoGoalConnection
local AutoGoalIgnore = {
   RadiusDisplay = true,
   LevelUp = true
}
local AutoGoalProcessing = false
local AutoGoalDelay = 0.02

local function StopAutoGoal()
   if AutoGoalConnection then
      AutoGoalConnection:Disconnect()
      AutoGoalConnection = nil
   end
end

local function AutoGoalLoop()
   StopAutoGoal()
   AutoGoalConnection = RunService.Heartbeat:Connect(function()
      if not AutoGoalEnabled then
         StopAutoGoal()
         return
      end
      if AutoGoalProcessing then
         return
      end
      local TempFolder = workspace:FindFirstChild("Temp")
      if TempFolder then
         AutoGoalProcessing = true
         local Children = TempFolder:GetChildren()
         for index = 1, #Children do
            local Child = Children[index]
            if Child and not AutoGoalIgnore[Child.Name] then
               pcall(function()
                  ClaimFootballRemote:InvokeServer(Child.Name)
               end)
               task.wait(AutoGoalDelay)
            end
         end
         AutoGoalProcessing = false
      end
   end)
end

local AutoGoalWarning = MainTab:CreateLabel("WARNING STUCK")
AutoGoalWarning.TextColor3 = Color3.fromRGB(255, 0, 0)

MainTab:CreateToggle({
   Name = "Auto Goal",
   CurrentValue = false,
   Flag = "AutoGoal",
   Callback = function(Value)
      AutoGoalEnabled = Value
      if Value then
         AutoGoalLoop()
      else
         StopAutoGoal()
      end
   end
})

local AutoPurchasesTab = Window:CreateTab("Auto Purchases", 4483362458)
local UpgradeSection = AutoPurchasesTab:CreateSection("Upgrade 1")
local UpgradeStates = {
   BallSpawnRate = false,
   BallValue = false,
   BallAmount = false
}

local function UpgradeLoop(key, args)
   task.spawn(function()
      while UpgradeStates[key] do
         pcall(function()
            UpgradeRemote:InvokeServer(unpack(args))
         end)
         task.wait(1)
      end
   end)
end

AutoPurchasesTab:CreateToggle({
   Name = "Ball Spawn Rate",
   CurrentValue = false,
   Flag = "BallSpawnRate",
   Callback = function(Value)
      UpgradeStates.BallSpawnRate = Value
      if Value then
         UpgradeLoop("BallSpawnRate", {
            "Football/1",
            false
         })
      end
   end
})

AutoPurchasesTab:CreateToggle({
   Name = "Ball Value",
   CurrentValue = false,
   Flag = "BallValue",
   Callback = function(Value)
      UpgradeStates.BallValue = Value
      if Value then
         UpgradeLoop("BallValue", {
            "Football/2",
            true
         })
      end
   end
})

AutoPurchasesTab:CreateToggle({
   Name = "Ball Amount",
   CurrentValue = false,
   Flag = "BallAmount",
   Callback = function(Value)
      UpgradeStates.BallAmount = Value
      if Value then
         UpgradeLoop("BallAmount", {
            "Football/3",
            false
         })
      end
   end
})

local UpgradeBranchSection = AutoPurchasesTab:CreateSection("Upgrade 1 Branches")

local function BuyBranch(path)
   pcall(function()
      BuyBranchRemote:InvokeServer(path)
   end)
end

local UpgradeBranchOrder = {
   "1/1",
   "1/2",
   "1/3",
   "1/4",
   "1/6",
   "1/7",
   "1/8",
   "1/9",
   "1/10",
   "1/11",
   "1/12",
   "1/13",
   "1/14",
   "1/15",
   "1/16",
   "1/17",
   "1/18",
   "1/19",
   "1/20"
}

local BranchToggleStates = {}

local function BranchToggleLoop(path)
   task.spawn(function()
      while BranchToggleStates[path] do
         BuyBranch({
            path
         })
         task.wait(1)
      end
   end)
end

for index = 1, #UpgradeBranchOrder do
   local BranchPath = UpgradeBranchOrder[index]
   local BranchFlag = "BranchToggle" .. string.gsub(BranchPath, "/", "_")
   BranchToggleStates[BranchPath] = false
   AutoPurchasesTab:CreateToggle({
      Name = "Upgrade 1 - " .. string.split(BranchPath, "/")[2],
      CurrentValue = false,
      Flag = BranchFlag,
      Callback = function(Value)
         BranchToggleStates[BranchPath] = Value
         if Value then
            BranchToggleLoop(BranchPath)
         end
      end
   })
end

local function InvokeUpgrade(args)
   pcall(function()
      UpgradeRemote:InvokeServer(unpack(args))
   end)
end

local RebirthSection = AutoPurchasesTab:CreateSection("Rebirths")
local RebirthEnabled = false

local function RebirthLoop()
   task.spawn(function()
      while RebirthEnabled do
         local args = {
            1
         }
         pcall(function()
            ResetRemote:InvokeServer(unpack(args))
         end)
         task.wait(1)
      end
   end)
end

AutoPurchasesTab:CreateToggle({
   Name = "Rebirth",
   CurrentValue = false,
   Flag = "RebirthToggle",
   Callback = function(Value)
      RebirthEnabled = Value
      if Value then
         RebirthLoop()
      end
   end
})

local UpgradeSectionTwo = AutoPurchasesTab:CreateSection("Upgrades 2")
local UpgradeStatesTwo = {
   DoubleBallValue = false,
   IncreaseKickRadius = false,
   IncreaseSpawnRate = false
}

local function UpgradeLoopTwo(key, args)
   task.spawn(function()
      while UpgradeStatesTwo[key] do
         pcall(function()
            UpgradeRemote:InvokeServer(unpack(args))
         end)
         task.wait(1)
      end
   end)
end

AutoPurchasesTab:CreateToggle({
   Name = "Double Ball Value",
   CurrentValue = false,
   Flag = "DoubleBallValue",
   Callback = function(Value)
      UpgradeStatesTwo.DoubleBallValue = Value
      if Value then
         UpgradeLoopTwo("DoubleBallValue", {
            "Football/4",
            false
         })
      end
   end
})

AutoPurchasesTab:CreateToggle({
   Name = "Increase Kick Radius",
   CurrentValue = false,
   Flag = "IncreaseKickRadius",
   Callback = function(Value)
      UpgradeStatesTwo.IncreaseKickRadius = Value
      if Value then
         UpgradeLoopTwo("IncreaseKickRadius", {
            "Football/5",
            false
         })
      end
   end
})

AutoPurchasesTab:CreateToggle({
   Name = "Increase Spawn Rate",
   CurrentValue = false,
   Flag = "IncreaseSpawnRate",
   Callback = function(Value)
      UpgradeStatesTwo.IncreaseSpawnRate = Value
      if Value then
         UpgradeLoopTwo("IncreaseSpawnRate", {
            "Football/6",
            false
         })
      end
   end
})

local SiuSection = AutoPurchasesTab:CreateSection("Siu")
local AdditionalUpgradeStates = {
   Siu1 = false,
   Football7 = false,
   Rebirth1 = false,
   Siu2 = false
}

local function AdditionalUpgradeLoop(stateKey, args)
   task.spawn(function()
      while AdditionalUpgradeStates[stateKey] do
         InvokeUpgrade(args)
         task.wait(1)
      end
   end)
end

AutoPurchasesTab:CreateToggle({
   Name = "Buy Siu",
   CurrentValue = false,
   Flag = "BuySiu",
   Callback = function(Value)
      AdditionalUpgradeStates.Siu1 = Value
      if Value then
         AdditionalUpgradeLoop("Siu1", {
            "Siu/1",
            false
         })
      end
   end
})

AutoPurchasesTab:CreateToggle({
   Name = "Double Ball Value",
   CurrentValue = false,
   Flag = "DoubleBallValueSingle",
   Callback = function(Value)
      AdditionalUpgradeStates.Football7 = Value
      if Value then
         AdditionalUpgradeLoop("Football7", {
            "Football/7",
            false
         })
      end
   end
})

AutoPurchasesTab:CreateToggle({
   Name = "Double Rebirth Value",
   CurrentValue = false,
   Flag = "DoubleRebirthValue",
   Callback = function(Value)
      AdditionalUpgradeStates.Rebirth1 = Value
      if Value then
         AdditionalUpgradeLoop("Rebirth1", {
            "Rebirth/1",
            false
         })
      end
   end
})

AutoPurchasesTab:CreateToggle({
   Name = "Increase Siu Value",
   CurrentValue = false,
   Flag = "IncreaseSiuValue",
   Callback = function(Value)
      AdditionalUpgradeStates.Siu2 = Value
      if Value then
         AdditionalUpgradeLoop("Siu2", {
            "Siu/2",
            false
         })
      end
   end
})

local TierSection = AutoPurchasesTab:CreateSection("Tier")
local TierToggleEnabled = false

local function TierLoop()
   task.spawn(function()
      while TierToggleEnabled do
         pcall(function()
            AscendRemote:InvokeServer(1)
         end)
         task.wait(1)
      end
   end)
end

AutoPurchasesTab:CreateToggle({
   Name = "Tier",
   CurrentValue = false,
   Flag = "TierToggle",
   Callback = function(Value)
      TierToggleEnabled = Value
      if Value then
         TierLoop()
      end
   end
})
