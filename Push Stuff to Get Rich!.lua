local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
   Name = "tg: @sigmatik323",
   LoadingTitle = "tg: @sigmatik323",
   LoadingSubtitle = "by sigmatik323",
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "Push Stuff to Get Rich"
   },
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = true
   },
   KeySystem = false
})

local Tab = Window:CreateTab("🚀 Main", 4483362458)

local Section = Tab:CreateSection("Farming")

local RunService = game:GetService("RunService")
local pushConnection = nil

local Toggle = Tab:CreateToggle({
   Name = "Fast Push",
   CurrentValue = false,
   Flag = "FastPush",
   Callback = function(Value)
      if Value then
          if pushConnection then pushConnection:Disconnect() end
          pushConnection = RunService.RenderStepped:Connect(function()
              game:GetService("ReplicatedStorage"):WaitForChild("remotes"):WaitForChild("push"):FireServer()
          end)
      else
          if pushConnection then
              pushConnection:Disconnect()
              pushConnection = nil
          end
      end
   end,
})

-- Anti AFK
local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)
