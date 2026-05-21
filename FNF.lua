_G.autoplay = false
_G.arrows = 4
_G.offset = 17 --100 = 1 sekunda
_G.hitbadnotes = false

local repo = 'https://raw.githubusercontent.com/Skeleton19/LinoriaLib/refs/heads/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

local Window = Library:CreateWindow({
    Title = '',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

local Tabs = {
    Main = Window:AddTab('Main'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}
local LeftGroupBox = Tabs.Main:AddLeftGroupbox('Main')

LeftGroupBox:AddToggle('autoplay', {
    Text = 'AutoPlay Toggle',
    Default = _G.autoplay,

    Callback = function(Value)
        _G.autoplay = Value
    end
}):AddKeyPicker('autoplaybind', {
    Default = '',
    SyncToggleState = false,
    Mode = 'Toggle',
    Text = 'AutoPlay keybind',
    NoUI = false,
    Callback = function(Value)
        Toggles.autoplay:SetValue(Value)
    end,
    ChangedCallback = function(New)
    end
})
LeftGroupBox:AddSlider('arrows', {
    Text = 'Arrow',
    Default = _G.arrows,
    Min = 4,
    Max = 9,
    Rounding = 0,
    Compact = true,

    Callback = function(Value)
        _G.arrows = Value
    end
})
LeftGroupBox:AddSlider('offset', {
    Text = 'Offset',
    Default = _G.offset,
    Min = -50,
    Max = 200,
    Rounding = 1,
    Compact = true,

    Callback = function(Value)
        _G.offset = Value
    end
})
LeftGroupBox:AddToggle('hitbadnotes', {
    Text = 'Hit Bad Notes',
    Default = _G.hitbadnotes,

    Callback = function(Value)
        _G.hitbadnotes = Value
    end
})

Library:OnUnload(function()

    print('Unloaded!')
    Library.Unloaded = true
end)
local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')
MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })
Library.ToggleKeybind = Options.MenuKeybind -- Allows you to have a custom keybind for the menu
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
ThemeManager:SetFolder('MyScriptHub')
SaveManager:SetFolder('MyScriptHub/specific-game')
SaveManager:BuildConfigSection(Tabs['UI Settings'])
ThemeManager:ApplyToTab(Tabs['UI Settings'])
SaveManager:LoadAutoloadConfig()
print('Script')

 
local vim = Instance.new("VirtualInputManager")

 

local buttons

local module = require(game.ReplicatedStorage.Modules.Note)
local gamemodule = require(game.ReplicatedStorage.Modules.Conductor)
local func = module.SpawnNote


local event = Instance.new("BindableEvent")
 local sustainEvent = Instance.new("BindableEvent")
    local activeKeys = {}
 
event.Event:Connect(function(path,timer,l,isbad)
    if isbad and not _G.hitbadnotes then
        return
    end
    
    repeat
        task.wait()
    until gamemodule.SongPos >= timer-_G.offset
    
    local numb = path+1
if _G.arrows == 4 then
    buttons = {"F","G","H","J"}
elseif _G.arrows == 5 then
    buttons = {"F","G","Space","J","K"}
elseif _G.arrows == 6 then
    buttons = {"F","G","H","J","K","L"}
elseif _G.arrows == 7 then
    buttons = {"F","G","H","Space","J","K","L"}
elseif _G.arrows == 8 then
    buttons = {"F","G","H","J","K","L","Semicolon","Quote"}
elseif _G.arrows == 9 then
    buttons = {"F","G","H","J","Space","K","L","Semicolon","Quote"}
else
    warn('Недопустимое значение стрелок')
end
    
    local key = buttons[numb]
    
    if l > 0 then
        activeKeys[key] = true
        vim:SendKeyEvent(true,Enum.KeyCode[key],false,nil)
        sustainEvent:Fire(key,l)
    else
        while activeKeys[key] do
            task.wait(0.01)
        end
        vim:SendKeyEvent(true,Enum.KeyCode[key],false,nil)
        task.wait(0.02)
        vim:SendKeyEvent(false,Enum.KeyCode[key],false,nil)
    end
end)

sustainEvent.Event:Connect(function(key,length)
    task.wait(length/1000)
    vim:SendKeyEvent(false,Enum.KeyCode[key],false,nil)
    activeKeys[key] = nil
end)
 
local o
o = hookfunction(func, function(...)
    local args = {...}
    for _,arg in pairs(args) do
        if type(arg) == "table" and arg["MustPress"] == true and arg["shouldPress"] == true then
            --print(chet,arg["NoteData"],arg['Side'],arg['IsSustain'],arg['StrumTime'],gamemodule.SongPos)
                if _G.autoplay == true then
                    local isBadNote = arg["NoteType"] and (arg["NoteType"]:lower():find("bad") or arg["NoteType"]:lower():find("hurt") or arg["NoteType"]:lower():find("damage"))
                    event:Fire(arg["NoteData"],arg["StrumTime"],arg["SustainLength"] or 0,isBadNote)
            end
        end
    end
    return o(...)
end)