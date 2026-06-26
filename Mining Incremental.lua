local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "tg: @sigmatik323",
   LoadingTitle = "tg: @sigmatik323",
   LoadingSubtitle = "by sigmatik323",
   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil,
      FileName = "Mining Incremental"
   },
   Discord = {
      Enabled = false,
      Invite = "noinvitelink",
      RememberJoins = true
   },
   KeySystem = false
})

local Tab = Window:CreateTab("⛏️ Mining", 4483362458)

local Section = Tab:CreateSection("Auto Farm")

local AutoMineRunning = false

local function findBlockByPrefix(prefix)
   local mineLayer = workspace:FindFirstChild("Mine") and workspace.Mine:FindFirstChild("MineLayer1")
   if not mineLayer then return nil end
   
   for _, child in pairs(mineLayer:GetChildren()) do
      if child.Name:sub(1, #prefix) == prefix then
         return child
      end
   end
   return nil
end

local AutoMineToggle = Tab:CreateToggle({
   Name = "Auto Mine",
   CurrentValue = false,
   Flag = "AutoMineToggle",
   Callback = function(Value)
      if Value and not AutoMineRunning then
         AutoMineRunning = true
         
         task.spawn(function()
            local MineBlockRemote = game:GetService("ReplicatedStorage"):WaitForChild("Assets"):WaitForChild("Events"):WaitForChild("MineBlock")
            
            for first = 0, 9 do
               for second = 0, 9 do
                  if not AutoMineRunning then break end
                  
                  local blockPrefix = tostring(first) .. "(" .. tostring(second) .. ")"
                  local block = findBlockByPrefix(blockPrefix)
                  
                  while block and AutoMineRunning do
                     pcall(function()
                        MineBlockRemote:InvokeServer(blockPrefix)
                     end)
                     task.wait()
                     block = findBlockByPrefix(blockPrefix)
                  end
               end
               if not AutoMineRunning then break end
            end
            
            AutoMineRunning = false
            AutoMineToggle:Set(false)
         end)
      elseif not Value then
         AutoMineRunning = false
      end
   end,
})
