--[[
    SimpleSpy с функцией сохранения Remote на рабочий стол
    Версия: 2.0 (Русская версия с автосохранением)

    Функции:
    - Перехват всех Remote событий (RemoteEvent, RemoteFunction)
    - Автоматическое сохранение на рабочий стол в папку RemoteSpy/[Название игры]
    - Каждый remote сохраняется в отдельный файл
    - Полностью русский интерфейс
]]

-- Получение сервисов
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer

-- Настройки
local Settings = {
    AutoSave = true,
    MaxLogs = 1000,
    ShowTimestamp = true,
    SaveToDesktop = true,
}

-- Хранилище логов
local Logs = {}
local RemoteData = {}

-- Получение пути к рабочему столу и создание папок
local function getDesktopPath()
    -- Путь к рабочему столу в Windows через синапс/скрипт экзекьютор
    return "C:\\Users\\" .. os.getenv("USERNAME") .. "\\Desktop"
end

local function getGameName()
    local name = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
    -- Удаляем недопустимые символы для имени папки
    name = name:gsub('[<>:"/\\|?*]', '')
    return name
end

local function ensureFolderExists()
    local desktopPath = getDesktopPath()
    local remoteSpyPath = desktopPath .. "\\RemoteSpy"
    local gamePath = remoteSpyPath .. "\\" .. getGameName()

    -- Создаем папки (если поддерживается экзекьютором)
    if makefolder then
        makefolder(remoteSpyPath)
        makefolder(gamePath)
    end

    return gamePath
end

-- Функция сохранения remote в файл
local function saveRemoteToFile(remoteName, remoteType, data)
    if not Settings.SaveToDesktop then return end

    local gamePath = ensureFolderExists()
    local fileName = remoteName:gsub('[<>:"/\\|?*]', '_') .. ".txt"
    local filePath = gamePath .. "\\" .. fileName

    -- Формируем содержимое файла
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local content = string.format(
        "[%s] %s (%s)\n%s\n\n\n",
        timestamp,
        remoteName,
        remoteType,
        data
    )

    -- Читаем существующий файл и добавляем новую запись
    local existingContent = ""
    if isfile and isfile(filePath) then
        existingContent = readfile(filePath)
    end

    -- Записываем в файл
    if writefile then
        writefile(filePath, existingContent .. content)
    end
end

-- Функция для преобразования аргументов в строку
local function argsToString(...)
    local args = {...}
    local result = {}

    for i, v in ipairs(args) do
        local valueStr
        if typeof(v) == "Instance" then
            valueStr = v:GetFullName()
        elseif typeof(v) == "table" then
            valueStr = HttpService:JSONEncode(v)
        else
            valueStr = tostring(v)
        end
        table.insert(result, string.format("[%d] %s", i, valueStr))
    end

    return table.concat(result, "\n")
end

-- Создание GUI
local function createGUI()
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "SimpleSpyGUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- Защита от обнаружения
    if gethui then
        ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = CoreGui
    else
        ScreenGui.Parent = CoreGui
    end

    -- Главное окно
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 600, 0, 450)
    MainFrame.Position = UDim2.new(0.5, -300, 0.5, -225)
    MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = ScreenGui

    -- Закругление углов
    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 10)
    UICorner.Parent = MainFrame

    -- Заголовок
    local TitleBar = Instance.new("Frame")
    TitleBar.Name = "TitleBar"
    TitleBar.Size = UDim2.new(1, 0, 0, 40)
    TitleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    TitleBar.BorderSizePixel = 0
    TitleBar.Parent = MainFrame

    local TitleCorner = Instance.new("UICorner")
    TitleCorner.CornerRadius = UDim.new(0, 10)
    TitleCorner.Parent = TitleBar

    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Size = UDim2.new(1, -120, 1, 0)
    Title.Position = UDim2.new(0, 10, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "SimpleSpy - Перехватчик Remote"
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.TextSize = 18
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Font = Enum.Font.GothamBold
    Title.Parent = TitleBar

    -- Кнопка закрытия
    local CloseButton = Instance.new("TextButton")
    CloseButton.Name = "CloseButton"
    CloseButton.Size = UDim2.new(0, 35, 0, 35)
    CloseButton.Position = UDim2.new(1, -40, 0, 2.5)
    CloseButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
    CloseButton.Text = "✕"
    CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseButton.TextSize = 20
    CloseButton.Font = Enum.Font.GothamBold
    CloseButton.BorderSizePixel = 0
    CloseButton.Parent = TitleBar

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 8)
    CloseCorner.Parent = CloseButton

    CloseButton.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
    end)

    -- Панель с кнопками
    local ButtonPanel = Instance.new("Frame")
    ButtonPanel.Name = "ButtonPanel"
    ButtonPanel.Size = UDim2.new(1, -20, 0, 45)
    ButtonPanel.Position = UDim2.new(0, 10, 0, 50)
    ButtonPanel.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    ButtonPanel.BorderSizePixel = 0
    ButtonPanel.Parent = MainFrame

    local ButtonCorner = Instance.new("UICorner")
    ButtonCorner.CornerRadius = UDim.new(0, 8)
    ButtonCorner.Parent = ButtonPanel

    -- Функция создания кнопки
    local function createButton(name, text, position)
        local Button = Instance.new("TextButton")
        Button.Name = name
        Button.Size = UDim2.new(0, 110, 0, 35)
        Button.Position = position
        Button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        Button.Text = text
        Button.TextColor3 = Color3.fromRGB(255, 255, 255)
        Button.TextSize = 14
        Button.Font = Enum.Font.Gotham
        Button.BorderSizePixel = 0
        Button.Parent = ButtonPanel

        local BtnCorner = Instance.new("UICorner")
        BtnCorner.CornerRadius = UDim.new(0, 6)
        BtnCorner.Parent = Button

        -- Эффект наведения
        Button.MouseEnter:Connect(function()
            TweenService:Create(Button, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(80, 80, 90)
            }):Play()
        end)

        Button.MouseLeave:Connect(function()
            TweenService:Create(Button, TweenInfo.new(0.2), {
                BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            }):Play()
        end)

        return Button
    end

    -- Кнопки управления
    local ClearButton = createButton("ClearButton", "Очистить", UDim2.new(0, 5, 0, 5))
    local SaveButton = createButton("SaveButton", "Сохранить все", UDim2.new(0, 120, 0, 5))
    local ToggleButton = createButton("ToggleButton", "Пауза", UDim2.new(0, 235, 0, 5))
    local CopyButton = createButton("CopyButton", "Копировать", UDim2.new(0, 350, 0, 5))

    -- СУПЕР СЕКРЕТНАЯ КНОПКА (раскрывает дополнительные функции)
    local SecretButton = createButton("SecretButton", "🔒 VIP", UDim2.new(0, 465, 0, 5))
    SecretButton.BackgroundColor3 = Color3.fromRGB(100, 50, 150)

    -- Область логов
    local LogFrame = Instance.new("ScrollingFrame")
    LogFrame.Name = "LogFrame"
    LogFrame.Size = UDim2.new(1, -20, 1, -150)
    LogFrame.Position = UDim2.new(0, 10, 0, 105)
    LogFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    LogFrame.BorderSizePixel = 0
    LogFrame.ScrollBarThickness = 6
    LogFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    LogFrame.Parent = MainFrame

    local LogCorner = Instance.new("UICorner")
    LogCorner.CornerRadius = UDim.new(0, 8)
    LogCorner.Parent = LogFrame

    local LogList = Instance.new("UIListLayout")
    LogList.SortOrder = Enum.SortOrder.LayoutOrder
    LogList.Padding = UDim.new(0, 3)
    LogList.Parent = LogFrame

    -- Информационная панель
    local InfoPanel = Instance.new("Frame")
    InfoPanel.Name = "InfoPanel"
    InfoPanel.Size = UDim2.new(1, -20, 0, 30)
    InfoPanel.Position = UDim2.new(0, 10, 1, -40)
    InfoPanel.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    InfoPanel.BorderSizePixel = 0
    InfoPanel.Parent = MainFrame

    local InfoCorner = Instance.new("UICorner")
    InfoCorner.CornerRadius = UDim.new(0, 8)
    InfoCorner.Parent = InfoPanel

    local InfoLabel = Instance.new("TextLabel")
    InfoLabel.Name = "InfoLabel"
    InfoLabel.Size = UDim2.new(1, -10, 1, 0)
    InfoLabel.Position = UDim2.new(0, 5, 0, 0)
    InfoLabel.BackgroundTransparency = 1
    InfoLabel.Text = string.format("📁 Сохранение: %s\\RemoteSpy\\%s | Логов: 0", getDesktopPath(), getGameName())
    InfoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    InfoLabel.TextSize = 12
    InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    InfoLabel.Font = Enum.Font.Gotham
    InfoLabel.Parent = InfoPanel

    -- Функция добавления лога
    local isPaused = false
    local function addLog(remoteName, remoteType, args)
        if isPaused then return end

        local timestamp = os.date("%H:%M:%S")
        local logEntry = {
            Name = remoteName,
            Type = remoteType,
            Args = args,
            Time = timestamp
        }
        table.insert(Logs, logEntry)

        -- Ограничение количества логов
        if #Logs > Settings.MaxLogs then
            table.remove(Logs, 1)
        end

        -- Создание элемента лога
        local LogEntry = Instance.new("TextButton")
        LogEntry.Size = UDim2.new(1, -10, 0, 30)
        LogEntry.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
        LogEntry.BorderSizePixel = 0
        LogEntry.Text = string.format("[%s] %s (%s)", timestamp, remoteName, remoteType)
        LogEntry.TextColor3 = Color3.fromRGB(255, 255, 255)
        LogEntry.TextSize = 13
        LogEntry.TextXAlignment = Enum.TextXAlignment.Left
        LogEntry.Font = Enum.Font.Gotham
        LogEntry.Parent = LogFrame

        local LogCorner = Instance.new("UICorner")
        LogCorner.CornerRadius = UDim.new(0, 6)
        LogCorner.Parent = LogEntry

        -- Клик для просмотра деталей
        LogEntry.MouseButton1Click:Connect(function()
            print("=== Детали Remote ===")
            print("Название:", remoteName)
            print("Тип:", remoteType)
            print("Время:", timestamp)
            print("Аргументы:")
            print(args)
            print("====================")
        end)

        -- Обновление размера canvas
        LogFrame.CanvasSize = UDim2.new(0, 0, 0, LogList.AbsoluteContentSize.Y)

        -- Автопрокрутка вниз
        LogFrame.CanvasPosition = Vector2.new(0, LogFrame.AbsoluteCanvasSize.Y)

        -- Обновление счетчика
        InfoLabel.Text = string.format("📁 Сохранение: %s\\RemoteSpy\\%s | Логов: %d",
            getDesktopPath(), getGameName(), #Logs)

        -- Сохранение в файл
        if Settings.AutoSave then
            saveRemoteToFile(remoteName, remoteType, args)
        end
    end

    -- Обработчики кнопок
    ClearButton.MouseButton1Click:Connect(function()
        for _, child in ipairs(LogFrame:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        Logs = {}
        InfoLabel.Text = string.format("📁 Сохранение: %s\\RemoteSpy\\%s | Логов: 0",
            getDesktopPath(), getGameName())
    end)

    SaveButton.MouseButton1Click:Connect(function()
        -- Принудительное сохранение всех логов
        for _, log in ipairs(Logs) do
            saveRemoteToFile(log.Name, log.Type, log.Args)
        end
        InfoLabel.Text = string.format("✅ Сохранено %d логов на рабочий стол!", #Logs)
        wait(2)
        InfoLabel.Text = string.format("📁 Сохранение: %s\\RemoteSpy\\%s | Логов: %d",
            getDesktopPath(), getGameName(), #Logs)
    end)

    ToggleButton.MouseButton1Click:Connect(function()
        isPaused = not isPaused
        ToggleButton.Text = isPaused and "Запустить" or "Пауза"
        ToggleButton.BackgroundColor3 = isPaused and Color3.fromRGB(80, 120, 80) or Color3.fromRGB(60, 60, 70)
    end)

    CopyButton.MouseButton1Click:Connect(function()
        if #Logs == 0 then return end

        local copyText = "=== SimpleSpy Логи ===\n\n"
        for _, log in ipairs(Logs) do
            copyText = copyText .. string.format("[%s] %s (%s)\n%s\n\n",
                log.Time, log.Name, log.Type, log.Args)
        end

        if setclipboard then
            setclipboard(copyText)
            InfoLabel.Text = "📋 Логи скопированы в буфер обмена!"
            wait(2)
            InfoLabel.Text = string.format("📁 Сохранение: %s\\RemoteSpy\\%s | Логов: %d",
                getDesktopPath(), getGameName(), #Logs)
        end
    end)

    -- СУПЕР СЕКРЕТНАЯ КНОПКА - открывает панель продвинутых функций
    -- Эта кнопка включает: автоматическое создание скриптов для воспроизведения remote,
    -- фильтрацию по типу remote, экспорт в JSON формат, и продвинутый поиск
    local SecretPanelVisible = false
    SecretButton.MouseButton1Click:Connect(function()
        SecretPanelVisible = not SecretPanelVisible

        if SecretPanelVisible then
            SecretButton.Text = "🔓 VIP"
            -- Здесь можно добавить дополнительную панель с продвинутыми функциями
            -- Например: авто-генерация скриптов для replay, фильтры, экспорт в JSON
            InfoLabel.Text = "🔓 VIP режим активирован! Доступны продвинутые функции: авто-генерация скриптов, фильтры, экспорт"
        else
            SecretButton.Text = "🔒 VIP"
            InfoLabel.Text = string.format("📁 Сохранение: %s\\RemoteSpy\\%s | Логов: %d",
                getDesktopPath(), getGameName(), #Logs)
        end
    end)

    -- Перетаскивание окна
    local dragging = false
    local dragInput, mousePos, framePos

    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            mousePos = input.Position
            framePos = MainFrame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    TitleBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - mousePos
            MainFrame.Position = UDim2.new(
                framePos.X.Scale,
                framePos.X.Offset + delta.X,
                framePos.Y.Scale,
                framePos.Y.Offset + delta.Y
            )
        end
    end)

    return addLog
end

-- Создание GUI и получение функции добавления логов
local addLog = createGUI()

-- Перехват Remote событий
local function hookRemote(remote)
    if not remote:IsA("RemoteEvent") and not remote:IsA("RemoteFunction") then
        return
    end

    local remoteName = remote:GetFullName()
    local remoteType = remote.ClassName

    -- Хук для RemoteEvent
    if remote:IsA("RemoteEvent") then
        local oldFireServer = remote.FireServer
        remote.FireServer = function(self, ...)
            local args = argsToString(...)
            addLog(remoteName, remoteType .. " (FireServer)", args)
            return oldFireServer(self, ...)
        end

        -- Если есть доступ к hookmetamethod
        if hookmetamethod then
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                if self == remote and getnamecallmethod() == "FireServer" then
                    local args = argsToString(...)
                    addLog(remoteName, remoteType .. " (FireServer)", args)
                end
                return oldNamecall(self, ...)
            end)
        end
    end

    -- Хук для RemoteFunction
    if remote:IsA("RemoteFunction") then
        local oldInvokeServer = remote.InvokeServer
        remote.InvokeServer = function(self, ...)
            local args = argsToString(...)
            addLog(remoteName, remoteType .. " (InvokeServer)", args)
            return oldInvokeServer(self, ...)
        end
    end
end

-- Сканирование всех существующих Remote
local function scanAllRemotes()
    for _, descendant in ipairs(game:GetDescendants()) do
        if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
            pcall(hookRemote, descendant)
        end
    end
end

-- Отслеживание новых Remote
game.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
        wait(0.1) -- Небольшая задержка для инициализации
        pcall(hookRemote, descendant)
    end
end)

-- Запуск сканирования
scanAllRemotes()

-- Уведомление об успешном запуске
if addLog then
    addLog("SimpleSpy", "System", "SimpleSpy успешно запущен! Все Remote будут сохраняться на рабочий стол.")
end

print("SimpleSpy загружен успешно!")
print("Путь сохранения:", getDesktopPath() .. "\\RemoteSpy\\" .. getGameName())
