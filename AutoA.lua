local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "tg: @sigmatik323",
   LoadingTitle = "tg: @sigmatik323",
   LoadingSubtitle = "by sigmatik323",
   ConfigurationSaving = {
      Enabled = false,
      FolderName = nil,
      FileName = "AutoA"
   },
   Discord = {
      Enabled = false,
      Invite = "noinv",
      RememberJoins = true
   },
   KeySystem = false,
})

local Tab = Window:CreateTab("Main 🛠️", 4483362458) -- Main tab

_G.AutoAPressed = false

Tab:CreateToggle({
   Name = "Auto Press A",
   CurrentValue = false,
   Flag = "AutoA",
   Callback = function(Value)
      _G.AutoAPressed = Value
   end,
})

-- Логика нажатия
local vim = game:GetService("VirtualInputManager")

task.spawn(function()
    while true do
        if _G.AutoAPressed then
            pcall(function()
                vim:SendKeyEvent(true, Enum.KeyCode.A, false, game)
                task.wait(0.1) -- Удержание кнопки для надежности
                vim:SendKeyEvent(false, Enum.KeyCode.A, false, game)
            end)
        end
        task.wait(1)
    end
end)
