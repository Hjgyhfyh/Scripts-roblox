local LIBRARY_URL = "https://raw.githubusercontent.com/Hjgyhfyh/Scripts-roblox/main/sigmatik_ui_library.lua"
local LOCAL_LIBRARY_PATHS = {
	"sigmatik_ui_library.lua",
	"gui_lua/sigmatik_ui_library.lua",
	"../gui_lua/sigmatik_ui_library.lua",
	"..\\gui_lua\\sigmatik_ui_library.lua",
	"D:/Нужное/Скрипты роблокс/Делаем скрипты тут/gui_lua/sigmatik_ui_library.lua",
}

local SharedEnvironment = getgenv and getgenv() or _G
local PreviousContext = SharedEnvironment.SigmatikGuiTestContext

if PreviousContext and PreviousContext.Cleanup then
	pcall(PreviousContext.Cleanup)
end

local function loadLibrary()
	for _, path in ipairs(LOCAL_LIBRARY_PATHS) do
		if loadfile then
			local ok, chunk = pcall(loadfile, path)
			if ok and chunk then
				return chunk()
			end
		end

		if readfile and loadstring then
			local ok, source = pcall(readfile, path)
			if ok and source then
				return loadstring(source)()
			end
		end
	end

	if loadstring then
		local ok, source = pcall(function()
			return game:HttpGet(LIBRARY_URL)
		end)

		if ok and source then
			return loadstring(source)()
		end
	end

	error("Sigmatik UI library could not be loaded")
end

local Library = loadLibrary()

local function icon(codepoint)
	return utf8.char(codepoint)
end

local Context = {
	Window = nil,
	Controller = nil,
}

SharedEnvironment.SigmatikGuiTestContext = Context

local controller, window = Library:Create({
	Title = "tg: @sigmatik323",
	Subtitle = "by sigmatik323",
	ConfigName = "GUI Test",
	ToggleKey = Enum.KeyCode.RightShift,
	AutoSave = false,
})

Context.Controller = controller
Context.Window = window

local mainTab = window:AddTab({ Name = icon(0x1F9EA) .. " Components", Icon = "test" })

local buttonsSection = mainTab:AddSection({ Name = icon(0x1F518) .. " Buttons & Toggles" })

buttonsSection:AddButton({
	Name = "Click Me",
	Callback = function()
		print("[GUI Test] Button clicked")
	end,
})

buttonsSection:AddToggle({
	Name = "Test Toggle",
	Default = false,
	Callback = function(value)
		print("[GUI Test] Toggle:", value)
	end,
})

local slidersSection = mainTab:AddSection({ Name = icon(0x1F39A) .. " Sliders" })

slidersSection:AddSlider({
	Name = "Integer Slider",
	Min = 0,
	Max = 100,
	Increment = 1,
	Default = 50,
	Callback = function(value)
		print("[GUI Test] Integer Slider:", value)
	end,
})

slidersSection:AddSlider({
	Name = "Float Slider",
	Min = 0,
	Max = 1,
	Increment = 0.01,
	Default = 0.25,
	Callback = function(value)
		print("[GUI Test] Float Slider:", value)
	end,
})

local inputsSection = mainTab:AddSection({ Name = icon(0x1F4DD) .. " Inputs" })

inputsSection:AddDropdown({
	Name = "Dropdown",
	Items = { "Option A", "Option B", "Option C", "Option D" },
	Default = "Option A",
	Callback = function(value)
		print("[GUI Test] Dropdown:", value)
	end,
})

inputsSection:AddTextbox({
	Name = "Textbox",
	Default = "",
	Placeholder = "Type something...",
	Callback = function(value)
		print("[GUI Test] Textbox:", value)
	end,
})

inputsSection:AddKeybind({
	Name = "Test Keybind",
	Default = Enum.KeyCode.F,
	Callback = function()
		print("[GUI Test] Keybind fired")
	end,
})

local extrasSection = mainTab:AddSection({ Name = icon(0x2728) .. " Extras" })

extrasSection:AddLabel({ Name = "This is a label", Text = "This is a label" })

local windowTab = window:AddTab({ Name = icon(0x1FA9F) .. " Window", Icon = "window" })

local controlsSection = windowTab:AddSection({ Name = icon(0x2699) .. " Window Controls" })

controlsSection:AddButton({
	Name = "Hide UI",
	Callback = function()
		if Context.Window then
			pcall(function() Context.Window:Hide() end)
		end
	end,
})

controlsSection:AddButton({
	Name = "Show UI",
	Callback = function()
		if Context.Window then
			pcall(function() Context.Window:Show() end)
		end
	end,
})

controlsSection:AddButton({
	Name = "Destroy UI",
	Callback = function()
		if Context.Cleanup then
			Context.Cleanup()
		end
	end,
})

local function cleanup()
	if Context.Window then
		pcall(function() Context.Window:Destroy() end)
		Context.Window = nil
	end
	SharedEnvironment.SigmatikGuiTestContext = nil
end

Context.Cleanup = cleanup
