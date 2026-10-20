--[[ tests/smoke.lua
     Builds a full Argon UI on top of the mock and asserts behaviour:
     construction, callbacks, flag wiring, config save/load, teardown.
     Returns a table of {passed, failed, messages} for the Python runner.
]]

local results = { passed = 0, failed = 0, messages = {} }

local function check(condition, message)
    if condition then
        results.passed = results.passed + 1
    else
        results.failed = results.failed + 1
        table.insert(results.messages, "FAIL: " .. tostring(message))
    end
end

local function section(name)
    results.passed = results.passed + 0
    table.insert(results.messages, "-- " .. name)
end

local baselineInstances = robloxMock.countLive()  -- mock's own Player, etc.

local Argon = loadstring(ARGON_SOURCE)()
check(typeof(Argon) == "table", "Argon.lua returns a table")
check(Argon.Version == "1.0.0", "version is exposed")
check(getgenv().Argon == Argon, "library is published to getgenv()")
check(getgenv().ArgonLib == Argon, "legacy ArgonLib alias exists")

-- ---------------------------------------------------------------- window
section("window")

local window = Argon:Window({
    Title = "Argon Test",
    Subtitle = "smoke",
    Width = 560,
    Height = 420,
})
check(window ~= nil, "Window constructs")
check(#Argon:GetWindows() == 1, "window is registered")
check(#window.Tabs == 0, "no tabs yet")

local tabMain = window:Tab({ Name = "Main" })
local tabExtra = window:Tab({ Name = "Extra" })
check(#window.Tabs == 2, "two tabs registered")
check(window.ActiveTab == tabMain, "first tab auto-selected")

window:SelectTab(tabExtra)
check(window.ActiveTab == tabExtra, "SelectTab switches")
window:SelectTab(tabMain)
check(tabMain.Content.Visible == true, "active tab content visible")
check(tabExtra.Content.Visible == false, "inactive tab content hidden")

window:SetTitle("Renamed")
check(window.TitleLabel.Text == "Renamed", "SetTitle works")
window:SetSubtitle("still smoke")
check(window.SubtitleLabel.Text == "still smoke", "SetSubtitle works")

window:SetVisible(false)
check(window.Visible == false, "SetVisible(false) hides")
window:Toggle()
check(window.Visible == true, "Toggle restores")

-- ---------------------------------------------------------------- elements
section("elements")

local sectionMain = tabMain:Section({ Name = "Combat" })
check(#tabMain.Sections == 1, "section registered")

local toggleCalls = {}
local toggle = sectionMain:Toggle({ Name = "Aimbot", Flag = "aimbot", Default = true }, function(value)
    table.insert(toggleCalls, value)
end)
check(toggle:Get() == true, "toggle respects Default")
check(Argon:GetFlag("aimbot") == true, "toggle seeds its flag")

local switch = toggle.Row:FindFirstChild("Switch")
local clickArea = switch and switch:FindFirstChild("Click")
check(clickArea ~= nil, "toggle has a click target")
clickArea.MouseButton1Click:Fire()
check(toggle:Get() == false, "click flips the toggle")
check(#toggleCalls == 1 and toggleCalls[1] == false, "toggle callback fires with new value")
check(Argon:GetFlag("aimbot") == false, "flag follows the toggle")

local sliderCalls = {}
local slider = sectionMain:Slider({
    Name = "FOV", Flag = "fov", Min = 0, Max = 360, Default = 90, Step = 5, Suffix = "°",
}, function(value)
    table.insert(sliderCalls, value)
end)
check(slider:Get() == 90, "slider default")
slider:Set(45)
check(slider:Get() == 45, "slider Set clamps/assigns")
check(#sliderCalls == 1, "slider Set fires once")
slider:Set(45)
check(#sliderCalls == 1, "slider Set is a no-op when the value is unchanged")
slider:Set(9999)
check(slider:Get() == 360, "slider clamps to Max")
slider:Set(-50)
check(slider:Get() == 0, "slider clamps to Min")

-- drag simulation: hitbox is 200px wide starting at x=100
local track = slider.Row:FindFirstChild("Hitbox")
track.AbsolutePosition = Vector2.new(100, 0)
track.AbsoluteSize = Vector2.new(200, 20)
local function dragTo(x)
    track.InputBegan:Fire(robloxMock.input(Enum.UserInputType.MouseButton1, x, 5))
    UserInputService.InputChanged:Fire(robloxMock.input(Enum.UserInputType.MouseMovement, x, 5))
    UserInputService.InputEnded:Fire(robloxMock.input(Enum.UserInputType.MouseButton1, x, 5))
end
dragTo(200)
check(slider:Get() == 180, "drag to the midpoint yields 180 (step-snapped), got " .. tostring(slider:Get()))
dragTo(300)
check(slider:Get() == 360, "drag to the end clamps to 360")

local dropdownCalls = {}
local dropdown = sectionMain:Dropdown({
    Name = "Mode", Flag = "mode", Options = { "Silent", "Legit", "Rage" }, Default = "Silent",
}, function(value)
    table.insert(dropdownCalls, value)
end)
check(dropdown:Get() == "Silent", "dropdown default")
local option2 = dropdown.Row:FindFirstChild("List"):FindFirstChild("Option_2")
check(option2 ~= nil, "dropdown built its options")
option2.MouseButton1Click:Fire()
check(dropdown:Get() == "Legit", "option click selects")
check(#dropdownCalls == 1, "dropdown callback fires")

local multiCalls = {}
local multi = sectionMain:Dropdown({
    Name = "Targets", Flag = "targets", Multi = true, Options = { "Head", "Torso", "Legs" }, Default = {},
}, function(value)
    table.insert(multiCalls, value)
end)
local headButton = multi.Row:FindFirstChild("List"):FindFirstChild("Option_1")
local torsoButton = multi.Row:FindFirstChild("List"):FindFirstChild("Option_2")
headButton.MouseButton1Click:Fire()
torsoButton.MouseButton1Click:Fire()
check(#multi:Get() == 2, "multi dropdown collects selections")
headButton.MouseButton1Click:Fire()
check(#multi:Get() == 1 and multi:Get()[1] == "Torso", "clicking a selection removes it")

local inputElement = sectionMain:Input({ Name = "Webhook", Flag = "webhook", Default = "https://example.com" })
check(inputElement:Get() == "https://example.com", "input default")
inputElement:Set("https://hook.local")
check(inputElement:Get() == "https://hook.local", "input Set")

local buttonCalls = 0
local button = sectionMain:Button({ Name = "Run" }, function()
    buttonCalls = buttonCalls + 1
end)
button.Row:FindFirstChild("Button").MouseButton1Click:Fire()
check(buttonCalls == 1, "button fires once")
button:SetDisabled(true)
button.Row:FindFirstChild("Button").MouseButton1Click:Fire()
check(buttonCalls == 1, "disabled button does not fire")

local colorCalls = {}
local picker = sectionMain:ColorPicker({ Name = "ESP Color", Flag = "esp", Default = Color3.fromRGB(255, 0, 0) }, function(color)
    table.insert(colorCalls, color)
end)
check(picker:Get().R == 1 and picker:Get().G == 0, "color picker default")
picker:Set(Color3.fromRGB(0, 128, 255))
check(math.abs(picker:Get().G - 128 / 255) < 0.01, "color picker Set")
check(#colorCalls == 1, "color picker fires once")

local keyCalls = {}
local keybind = sectionMain:Keybind({ Name = "Menu Key", Flag = "menuKey", Default = Enum.KeyCode.RightControl }, function(state)
    table.insert(keyCalls, state)
end)
check(keybind:Get() == Enum.KeyCode.RightControl, "keybind default")
local keyButton = keybind.Row:FindFirstChild("KeyButton")
keyButton.MouseButton1Click:Fire()
check(keybind.Listening == true, "keybind enters listening mode")
UserInputService.InputBegan:Fire(robloxMock.input(Enum.UserInputType.Keyboard, 0, 0, Enum.KeyCode.F5), false)
check(keybind:Get() == Enum.KeyCode.F5, "keybind captures a key")
check(keybind.Listening == false, "keybind leaves listening mode")

sectionMain:Label({ Text = "Not a real aimbot." })
sectionMain:Paragraph({ Title = "Note", Text = "Left click to fire." })
sectionMain:Divider()
sectionMain:Space(12)
local search = sectionMain:Search({ Placeholder = "filter" })
check(#sectionMain.Elements == 13, "section tracks every element, got " .. tostring(#sectionMain.Elements))

-- ---------------------------------------------------------------- visibility
section("visibility")

toggle:SetVisible(false)
check(toggle.Row.Visible == false, "SetVisible(false) hides the row")
toggle:SetVisible(true)
check(toggle.Row.Visible == true, "SetVisible(true) shows the row")

local removed = sectionMain:Label({ Text = "temporary" })
local before = #sectionMain.Elements
removed:Destroy()
check(#sectionMain.Elements == before - 1, "Destroy unregisters the element")

-- ---------------------------------------------------------------- configs
section("configs")

check(window:SaveConfig("smoke") == true, "SaveConfig writes")
check(isfile(window:ConfigPath("smoke")), "config file exists on the fake fs")

slider:Set(270)
toggle:Set(true, true)
picker:Set(Color3.fromRGB(10, 20, 30), true)
Argon.Flags.fov = 270
Argon.Flags.aimbot = true
window:SaveConfig("smoke")

Argon.Flags.fov = 1
Argon.Flags.aimbot = false
check(window:LoadConfig("smoke") == true, "LoadConfig reads")
check(Argon:GetFlag("fov") == 270, "config restores numbers")
check(Argon:GetFlag("aimbot") == true, "config restores booleans")
check(typeof(Argon:GetFlag("esp")) == "Color3", "config restores Color3 values")
check(math.abs(Argon:GetFlag("esp").B - 30 / 255) < 0.01, "restored Color3 keeps its channels")

check(window:LoadConfig("does-not-exist") == false, "missing config returns false")
check(#window:GetConfigs() == 1, "GetConfigs lists saved configs")

-- ---------------------------------------------------------------- notifications
section("notifications")

window:Notify({ Title = "Loaded", Text = "Argon ready", Duration = 1 })
check(#Argon.Notifications == 1, "notification queued")
robloxMock.runScheduler()
check(#Argon.Notifications == 0, "notification retires after its duration")

-- ---------------------------------------------------------------- scheduler
section("scheduler")

local order = {}
local scheduler = Argon.Scheduler:Create({ Timeout = 2 })
scheduler:Add("first", function(nextTask)
    table.insert(order, "first")
    nextTask()
end)
scheduler:Add("second", function(nextTask)
    table.insert(order, "second")
    nextTask()
end)
scheduler:Run()
robloxMock.runScheduler(50)
check(#order == 2, "scheduler ran both tasks, got " .. tostring(#order))
check(order[1] == "first" and order[2] == "second", "scheduler preserves order")
check(scheduler.Running == false, "scheduler reports idle when drained")

-- ---------------------------------------------------------------- teardown
section("teardown")

local liveBefore = robloxMock.countLive()
window:Destroy()
check(window.Destroyed == true, "window marks itself destroyed")
check(#Argon:GetWindows() == 0, "window unregistered on destroy")
check(robloxMock.countLive() < liveBefore, "destroying the window frees instances")
check(baselineInstances <= liveBefore - 100, "a window creates a meaningful number of instances")

-- reload-safety: a second library instance must tear down the first
local Argon2 = loadstring(ARGON_SOURCE)()
check(Argon2 ~= nil, "second load succeeds")
check(getgenv().Argon == Argon2, "second load replaces the singleton")

Argon2:Unload()
check(Argon2.Unloaded == true, "Unload flips the flag")
check(getgenv().Argon == nil, "Unload clears getgenv().Argon")
check(
    robloxMock.countLive() == baselineInstances,
    "Unload leaves no live instances, got "
        .. tostring(robloxMock.countLive())
        .. " expected "
        .. tostring(baselineInstances)
)

results.mockErrors = robloxMock.errors
return results
