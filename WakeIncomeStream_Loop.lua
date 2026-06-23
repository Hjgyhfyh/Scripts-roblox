-- Auto WakeIncomeStream — вызывает remote раз в 0.05 сек
-- Tycoon9 / Remotes / WakeIncomeStream :InvokeServer("LemonStand")

local args = {
    "LemonStand"
}

local remote = workspace
    :WaitForChild("Tycoon9")
    :WaitForChild("Remotes")
    :WaitForChild("WakeIncomeStream")

-- Флаг, чтобы можно было остановить:  getgenv().WakeIncomeRunning = false
getgenv().WakeIncomeRunning = true

task.spawn(function()
    while getgenv().WakeIncomeRunning do
        -- каждый вызов в отдельном потоке, чтобы yield от InvokeServer
        -- не растягивал интервал, если сервер отвечает медленно
        task.spawn(function()
            pcall(function()
                remote:InvokeServer(unpack(args))
            end)
        end)
        task.wait(0.05)
    end
end)
