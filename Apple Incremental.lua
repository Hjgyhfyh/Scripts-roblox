local Sigmatik = loadstring(game:HttpGet('https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/refs/heads/main/source.lua.txt'))()

local Window = Sigmatik:CreateWindow({
   Name = "tg: @sigmatik323",
   LoadingTitle = "tg: @sigmatik323",
   LoadingSubtitle = "by sigmatik323",
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "Apple Incremental"
   },
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = true
   },
   KeySystem = false
})

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local autoFarmEnabled = false
local farmConnection = nil

local Tab = Window:CreateTab("🍎 Farm", 4483362458)

local Section = Tab:CreateSection("Auto Farm")

local Toggle = Tab:CreateToggle({
   Name = "Auto Farm Apple",
   CurrentValue = false,
   Flag = "AutoFarmApple",
   Callback = function(Value)
      autoFarmEnabled = Value
      
      if Value then
         farmConnection = RunService.Heartbeat:Connect(function()
            if not autoFarmEnabled then return end
            
            local character = LocalPlayer.Character
            if not character then return end
            
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            if not humanoidRootPart then return end
            
            local playerName = LocalPlayer.Name
            local spawnsFolder = workspace:FindFirstChild(playerName .. "_Spawns")
            
            if spawnsFolder then
               for _, child in pairs(spawnsFolder:GetDescendants()) do
                  if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
                     child.CFrame = humanoidRootPart.CFrame
                  elseif child:IsA("Model") and child.PrimaryPart then
                     child:SetPrimaryPartCFrame(humanoidRootPart.CFrame)
                  elseif child:IsA("Model") then
                     local modelPart = child:FindFirstChildWhichIsA("BasePart")
                     if modelPart then
                        local offset = modelPart.Position - humanoidRootPart.Position
                        for _, part in pairs(child:GetDescendants()) do
                           if part:IsA("BasePart") then
                              part.CFrame = humanoidRootPart.CFrame
                           end
                        end
                     end
                  end
               end
            end
         end)
      else
         if farmConnection then
            farmConnection:Disconnect()
            farmConnection = nil
         end
      end
   end,
})

local dupeJuiceEnabled = false

local DupeToggle = Tab:CreateToggle({
   Name = "Auto Juice",
   CurrentValue = false,
   Flag = "DupeJuice",
   Callback = function(Value)
      dupeJuiceEnabled = Value
      if Value then
         spawn(function()
            local args = { false }
            local JuiceEvent = game:GetService("ReplicatedStorage"):WaitForChild("JuiceEvent")
            while dupeJuiceEnabled do
               JuiceEvent:FireServer(unpack(args))
               wait(0.25)
            end
         end)
      end
   end,
})

