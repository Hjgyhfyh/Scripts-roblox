local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
	Name = "Blade Spin | tg: @sigmatik323",
	LoadingTitle = "Blade Spin",
	LoadingSubtitle = "by sigmatik323",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "BladeSpin"
	},
	Discord = {
		Enabled = false,
		Invite = "",
		RememberJoins = false
	},
	KeySystem = false
})

local Tab = Window:CreateTab("💰 Dupe", 4483362458)

-- Variables
local dupeEXPEnabled = false
local dupeMoneyEnabled = false

-- Dupe EXP Function
Tab:CreateToggle({
	Name = "Dupe EXP",
	CurrentValue = false,
	Flag = "DupeEXPToggle",
	Callback = function(Value)
		dupeEXPEnabled = Value
		if dupeEXPEnabled then
			task.spawn(function()
				while dupeEXPEnabled do
					pcall(function()
						local args = {
							99999
						}
						game:GetService("ReplicatedStorage"):WaitForChild("ReplicatedStorageHolders"):WaitForChild("Events"):WaitForChild("AddXP"):FireServer(unpack(args))
					end)
					task.wait(0.01)
				end
			end)
		end
	end
})

-- Dupe Money Function
Tab:CreateToggle({
	Name = "Dupe Money",
	CurrentValue = false,
	Flag = "DupeMoneyToggle",
	Callback = function(Value)
		dupeMoneyEnabled = Value
		if dupeMoneyEnabled then
			task.spawn(function()
				while dupeMoneyEnabled do
					pcall(function()
						local args = {
							99999
						}
						game:GetService("ReplicatedStorage"):WaitForChild("ReplicatedStorageHolders"):WaitForChild("Events"):WaitForChild("AddCoins"):FireServer(unpack(args))
					end)
					task.wait(0.01)
				end
			end)
		end
	end
})
