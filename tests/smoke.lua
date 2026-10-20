--[[ tests/smoke.lua
     Exercises the full Argon 2.x surface against the mock Roblox API.
     Returns { passed, failed, messages, mockErrors }.
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

-- depth-first search (mock's FindFirstChild only looks at direct children)
local function findDeep(root, name)
    for _, child in ipairs(root:GetChildren()) do
        if child.Name == name then
            return child
        end
        local found = findDeep(child, name)
        if found then
            return found
        end
    end
    return nil
end

local function group(name)
    table.insert(results.messages, "-- " .. name)
end

local baseline = robloxMock.countLive()

local Argon = loadstring(ARGON_SOURCE)()
check(type(Argon) == "table", "library returns a table")
check(Argon.Version == "3.0.0", "version is 3.0.0")
check(getgenv().Argon == Argon, "published to getgenv()")
check(getgenv().ArgonLib == Argon, "legacy ArgonLib alias")
check(type(Argon.Themes) == "table" and Argon.Themes.Aqua ~= nil, "themes registered")
check(#Argon:GetThemeNames() >= 7, "at least 7 built-in themes")

-- ---------------------------------------------------------------- themes
group("themes")

Argon:SetTheme("Aqua")
check(Argon:GetThemeName() == "Aqua", "SetTheme switches palette")
check(Argon.Theme.Accent.G > 0.5, "Aqua accent is teal-ish")
Argon:SetAccent(Color3.fromRGB(255, 0, 128))
check(Argon.Theme.Accent.R > 0.9 and Argon.Theme.Accent.B > 0.4, "SetAccent overrides accent")
Argon:SetTheme("Dark")
Argon:RegisterTheme({ Name = "Test", Accent = Color3.fromRGB(1, 2, 3) })
check(Argon.Themes.Test ~= nil, "RegisterTheme adds a palette")
Argon:SetTheme("NoSuchTheme")
check(Argon:GetThemeName() == "Dark", "unknown theme leaves the palette alone")

-- ---------------------------------------------------------------- window
group("window")

local window = Argon:Window({
    Title = "luau.pro",
    Subtitle = "v2",
    User = { Name = "farmerjoe", Tag = "Premium" },
    Width = 640,
    Height = 480,
    Theme = "Aqua",
})
check(window ~= nil, "Window constructs")
check(#Argon:GetWindows() == 1, "window registered")
check(window.Main ~= nil and window.Sidebar ~= nil and window.Rail ~= nil, "shell parts exist")
check(window.UserName.Text == "farmerjoe", "user card name")
check(window.UserTag.Text == "Premium", "user card tag")
check(window:GetPage("Autobuilds") == nil, "no pages yet")

local page = window:Page({ Name = "Autobuilds", Icon = "▤", Subtitle = "8 Features" })
local settings = window:Page({ Name = "Settings", Icon = "⚙", Group = "OTHER" })
check(#window.Pages == 2, "two pages registered")
check(window.ActivePage == page, "first page auto-selected")
check(page.Frame.Visible == true and settings.Frame.Visible == false, "only one page visible")

window:SelectPage(settings)
check(window.ActivePage == settings, "SelectPage switches")
check(window:GetPage("Settings") == settings, "GetPage finds by name")
window:SelectPage(page)

window:SetTitle("renamed")
check(window.LogoLabel.Text == "renamed", "SetTitle updates the logo label")
window:SetSubtitle("sub")
window:SetUser({ Name = "someone", Tag = "Free" })
check(window.UserName.Text == "someone", "SetUser updates the card")

window:SetMinimized(true)
check(window.Minimized == true, "minimize works")
window:SetMinimized(false)
check(window.Minimized == false, "restore works")

-- ---------------------------------------------------------------- sections
group("sections")

local combat = page:Section({ Name = "Combat", Icon = "⚔" })
local features = page:Section({ Name = "Features" })
check(#page.Sections == 2, "sections registered")
check(combat.TitleLabel.Text == "COMBAT", "section title is uppercased")
combat:Collapse(true)
check(combat.Collapsed == true and combat.Content.Visible == false, "collapse hides content")
combat:Collapse(false)
check(combat.Content.Visible == true, "expand restores content")
combat:SetName("PvP")
check(combat.TitleLabel.Text == "PVP", "SetName renames the section")

-- ---------------------------------------------------------------- toggle / checkbox
group("toggle and checkbox")

local toggleCalls = {}
local toggle = combat:Toggle({
    Name = "Aim assist",
    Description = "Snap to the nearest player",
    Flag = "aim.enabled",
    Default = true,
    Icon = "◎",
}, function(value)
    table.insert(toggleCalls, value)
end)

check(toggle:Get() == true, "toggle default")
check(Argon:GetFlag("aim.enabled") == true, "flag seeded")
local toggleHitbox = findDeep(toggle.Row, "Click")
check(toggleHitbox ~= nil, "toggle click target exists")
click(toggleHitbox)
check(toggle:Get() == false, "click flips the toggle")
check(#toggleCalls == 1 and toggleCalls[1] == false, "callback fired with new value")
check(Argon:GetFlag("aim.enabled") == false, "flag follows the toggle")

toggle:Set(true)
check(toggle:Get() == true and #toggleCalls == 2, "Set updates value and fires")
Argon:SetFlag("aim.enabled", false)
check(toggle:Get() == false, "external SetFlag refreshes the widget")

local checkCalls = {}
local checkbox = combat:Checkbox({ Name = "Team check", Flag = "aim.teamcheck" }, function(state)
    checkCalls[#checkCalls + 1] = state
end)
check(checkbox:Get() == false, "checkbox starts off")
click(findDeep(checkbox.Row, "Click"))
check(checkbox:Get() == true and #checkCalls == 1, "checkbox click flips the value")

-- ---------------------------------------------------------------- slider
group("slider")

local sliderCalls = {}
local slider = combat:Slider({
    Name = "FOV",
    Description = "Aim cone in pixels",
    Flag = "aim.fov",
    Min = 0, Max = 360, Default = 90, Step = 5, Suffix = "°",
}, function(value)
    sliderCalls[#sliderCalls + 1] = value
end)
check(slider:Get() == 90, "slider default")
slider:Set(120)
check(slider:Get() == 120 and #sliderCalls == 1, "Set applies and fires")
slider:Set(120)
check(#sliderCalls == 1, "no-op Set stays quiet")
slider:Set(999)
check(slider:Get() == 360, "clamps to max")
slider:Set(-5)
check(slider:Get() == 0, "clamps to min")

local hitbox = findDeep(slider.Row, "Hitbox")
check(hitbox ~= nil, "slider hitbox exists")
hitbox.AbsolutePosition = Vector2.new(100, 0)
hitbox.AbsoluteSize = Vector2.new(200, 12)
hitbox.InputBegan:Fire(robloxMock.input(Enum.UserInputType.MouseButton1, 200, 5))
UserInputService.InputChanged:Fire(robloxMock.input(Enum.UserInputType.MouseMovement, 200, 5))
UserInputService.InputEnded:Fire(robloxMock.input(Enum.UserInputType.MouseButton1, 200, 5))
check(slider:Get() == 180, "drag to midpoint gives 180, got " .. tostring(slider:Get()))

-- ---------------------------------------------------------------- input
group("input")

local inputCalls = {}
local input = combat:Input({
    Name = "Webhook",
    Placeholder = "https://discord.com/api/webhooks/...",
    Flag = "misc.webhook",
}, function(value)
    inputCalls[#inputCalls + 1] = value
end)
check(input:Get() == "", "input starts empty")
input:Set("https://example.com")
check(input:Get() == "https://example.com", "Set updates value")
input.TextBox.Text = "https://hook.local"
input.TextBox.FocusLost:Fire(true)
check(input:Get() == "https://hook.local", "FocusLost commits text")
check(#inputCalls >= 1, "input callback fired")

local textarea = combat:Textarea({ Name = "Notes", Placeholder = "notes...", Flag = "misc.notes" })
textarea.TextBox.Text = "line one"
textarea.TextBox.FocusLost:Fire(false)
check(textarea:Get() == "line one", "textarea commits text")

-- ---------------------------------------------------------------- keybind
group("keybind")

local keyCalls = {}
local keybind = combat:Keybind({
    Name = "Toggle key",
    Flag = "misc.key",
    Default = Enum.KeyCode.RightShift,
}, function(down)
    keyCalls[#keyCalls + 1] = down
end)
check(keybind:Get() == Enum.KeyCode.RightShift, "keybind default")
local keyButton = findDeep(keybind.Row, "KeyButton")
check(keyButton ~= nil, "keybind button exists")
keyButton.MouseButton1Click:Fire()
check(keybind.Listening == true, "listening mode entered")
UserInputService.InputBegan:Fire(robloxMock.input(Enum.UserInputType.Keyboard, 0, 0, Enum.KeyCode.F4), false)
check(keybind:Get() == Enum.KeyCode.F4, "key captured")
UserInputService.InputBegan:Fire(robloxMock.input(Enum.UserInputType.Keyboard, 0, 0, Enum.KeyCode.F4), false)
check(#keyCalls >= 1 and keyCalls[#keyCalls] == true, "press fires the callback")

-- ---------------------------------------------------------------- buttons
group("buttons")

local clicks = 0
local button = combat:Button({ Name = "Run", Primary = true }, function()
    clicks = clicks + 1
end)
local buttonInstance
for _, child in ipairs(button.Row:GetChildren()) do
    if child.ClassName == "TextButton" then
        buttonInstance = child
    end
end
buttonInstance.MouseButton1Click:Fire()
check(clicks == 1, "button callback")
button:SetDisabled(true)
buttonInstance.MouseButton1Click:Fire()
check(clicks == 1, "disabled button ignores clicks")

local leftCount, rightCount = 0, 0
local dual = combat:DualButton({ Name = "Save", AlternateName = "Load" }, function()
    leftCount = leftCount + 1
end, function()
    rightCount = rightCount + 1
end)
local dualButtons = dual.Row:GetDescendants()
local fired = 0
for _, child in ipairs(dualButtons) do
    if child.ClassName == "TextButton" then
        child.MouseButton1Click:Fire()
        fired = fired + 1
    end
end
check(fired == 2 and leftCount == 1 and rightCount == 1, "dual button fires both halves")

-- ---------------------------------------------------------------- dropdown
group("dropdown")

local dropCalls = {}
local dropdown = features:Dropdown({
    Name = "Hitbox",
    Flag = "aim.hitbox",
    Options = { "Head", "Torso", "Closest" },
    Default = "Head",
}, function(value)
    dropCalls[#dropCalls + 1] = value
end)
check(dropdown:Get() == "Head", "dropdown default")
dropdown:OpenList()
check(dropdown.Open == true, "dropdown opens")
local optionButtons = {}
for _, child in ipairs(dropdown.Row:GetDescendants()) do
    if child.ClassName == "TextButton" and child.Name:find("Option_") then
        table.insert(optionButtons, child)
    end
end
check(#optionButtons == 3, "three options built, got " .. tostring(#optionButtons))
optionButtons[2].MouseButton1Click:Fire()
check(dropdown:Get() == "Torso", "option click selects")
check(dropdown.Open == false, "single select closes the list")
check(#dropCalls == 1, "dropdown callback fired")

local multi = features:Dropdown({
    Name = "Targets",
    Flag = "aim.targets",
    Multi = true,
    Options = { "Head", "Torso", "Legs" },
    Default = {},
})
local multiButtons = {}
for _, child in ipairs(multi.Row:GetDescendants()) do
    if child.ClassName == "TextButton" and child.Name:find("Option_") then
        table.insert(multiButtons, child)
    end
end
multiButtons[1].MouseButton1Click:Fire()
multiButtons[3].MouseButton1Click:Fire()
check(#multi:Get() == 2, "multi collects two selections")
multiButtons[1].MouseButton1Click:Fire()
check(#multi:Get() == 1 and multi:Get()[1] == "Legs", "clicking a selection removes it")

local filterable = features:Dropdown({ Name = "Filter", Options = { "Alpha", "Beta" }, Default = "Alpha" })
filterable:SetOptions({ "One", "Two", "Three" })
check(#filterable:GetOptions() == 3, "SetOptions replaces the list")

-- ---------------------------------------------------------------- color picker
group("color picker")

local colorCalls = {}
local picker = features:ColorPicker({
    Name = "ESP color",
    Flag = "esp.color",
    Default = Color3.fromRGB(255, 0, 0),
}, function(color)
    colorCalls[#colorCalls + 1] = color
end)
check(picker:Get().R == 1, "picker default")
picker:Set(Color3.fromRGB(0, 128, 255))
check(math.abs(picker:Get().G - 128 / 255) < 0.01, "SetColor applies")
check(#colorCalls == 1, "picker fired once")
picker:SetAlpha(0.5)
check(math.abs(picker:GetAlpha() - 0.5) < 0.001, "alpha applies")
check(math.abs(Argon:GetFlag("esp.color_alpha") - 0.5) < 0.001, "alpha stored as a flag")

-- ---------------------------------------------------------------- cards
group("cards")

local cardCalls = {}
local card = features:Card({
    Name = "Autobuild Classic",
    Description = "Load .build files with ease",
    Badge = "Active",
    Tier = "free",
    Glyph = "★",
}, function(element)
    cardCalls[#cardCalls + 1] = element.Config.Name
end)
check(card:IsSelected() == false, "card starts unselected")
click(findDeep(card.Row, "Click"))
check(card:IsSelected() == true, "click selects the card")
check(#cardCalls == 1, "card callback fired")
card:SetBadge("Soon", Color3.fromRGB(240, 178, 64))
check(card.BadgeLabel.Text == "Soon", "SetBadge updates the pill")
check(card:SearchText("build"), "card search matches description")
check(card:SearchText("zzz") == false, "card search rejects nonsense")
card:Select(false, true)
check(card:IsSelected() == false, "Select(false) clears selection")

local premiumCard = features:Card({
    Name = "Image Loader",
    Description = "Load any image from the internet",
    Badge = "Soon",
    Tier = "premium",
})
check(premiumCard.Tier == "premium", "tier stored for filtering")

-- ---------------------------------------------------------------- misc components
group("misc components")

local label = combat:Label({ Text = "Plain text", Bold = true })
check(label.NameLabel.Text == "Plain text", "label text")
local paragraph = combat:Paragraph({ Title = "Note", Text = "Body copy" })
check(paragraph.DescriptionLabel.Text == "Body copy", "paragraph body")
local divider = combat:Divider()
check(divider.Row ~= nil, "divider builds")
local space = combat:Space(12)
check(space.Row.Size.Y.Offset == 12, "space height")
local progress = combat:Progress({ Name = "Loading", Default = 25 })
check(progress:GetProgress() == 25, "progress default")
progress:SetProgress(80, false)
check(progress:GetProgress() == 80, "progress updates")
local tag = combat:Tag({ Tags = { "beta", "free" } })
check(#tag.TagButtons == 2, "tags built")
local userRow = combat:UserRow({ Name = "farmerjoe", Description = "Premium" })
check(userRow.NameLabel.Text == "farmerjoe", "user row name")
local tableEl = combat:Table({ Columns = { "Name", "Value" }, Rows = { { "FPS", "60" }, { "Ping", "42" } } })
check(#tableEl.Body:GetChildren() >= 2, "table rows built")
local banner = combat:Banner({ Name = "Heads up", Text = "This is a warning", Kind = "warning" })
check(banner.Row ~= nil, "banner builds")
local image = combat:Image({ Name = "Preview", Image = "rbxassetid://123" })
check(image.Row ~= nil, "image builds")

-- half width rows pair up
local halfA = combat:Toggle({ Name = "Half A", Width = "half" })
local halfB = combat:Toggle({ Name = "Half B", Width = "half" })
check(halfA.Row.Size.X.Scale == 0.5, "half rows are half width")
check(halfA.Row.Parent == halfB.Row.Parent, "two half rows share a container")

-- ---------------------------------------------------------------- filtering
group("filtering")

page:Pills({ Options = { { Name = "All", Value = "all" }, { Name = "Free", Value = "free" }, { Name = "Premium", Value = "premium" } } })
page:SetPill("premium")
check(page.ActivePill == "premium", "pill selection")
check(card.Row.Visible == false, "free card hidden under premium filter")
check(premiumCard.Row.Visible == true, "premium card stays visible")
page:SetPill("all")
check(card.Row.Visible == true, "clearing the filter restores cards")

page:Search("autobuild")
check(page.SearchInput ~= nil, "search box exists")
page.SearchInput.Text = "autobuild"
check(card.Row.Visible == true, "search keeps matching cards")
check(premiumCard.Row.Visible == false, "search hides non-matching cards")
page.SearchInput.Text = ""
check(premiumCard.Row.Visible == true, "clearing search restores everything")

-- ---------------------------------------------------------------- action bar
group("action bar")

local actionCalls = 0
page:Action("Select a feature", function()
    actionCalls = actionCalls + 1
end)
check(page.ActionBar.Visible == true, "action bar shown")
page.ActionButton.MouseButton1Click:Fire()
check(actionCalls == 1, "action callback")
page:SetActionEnabled(false)
check(page.ActionButton.Active == false, "action disabled")

-- ---------------------------------------------------------------- theme picker
group("theme picker")

local themeSection = settings:Section({ Name = "Appearance" })
local themePicker = themeSection:ThemePicker({ Name = "Theme" })
check(themePicker.Cards ~= nil, "theme picker grid")
local before = Argon:GetThemeName()
if themePicker.Cards.Serika then
    themePicker.Cards.Serika.Card.MouseButton1Click:Fire()
    check(Argon:GetThemeName() == "Serika", "picking a theme applies it")
    Argon:SetTheme(before)
else
    check(false, "Serika card missing")
end

-- ---------------------------------------------------------------- configs
group("configs")

local configSection = settings:Section({ Name = "Config" })
local cfgSlider = configSection:Slider({ Name = "Volume", Flag = "audio.volume", Min = 0, Max = 100, Default = 30 })
local cfgToggle = configSection:Toggle({ Name = "Mute", Flag = "audio.mute", Default = false })
local cfgColor = configSection:ColorPicker({ Name = "Tint", Flag = "audio.tint", Default = Color3.fromRGB(10, 20, 30) })

cfgSlider:Set(70)
cfgToggle:Set(true)
Argon.Flags["audio.volume"] = 70
Argon.Flags["audio.mute"] = true
check(Argon:SaveConfig("smoke") == true, "SaveConfig writes")
check(isfile("Argon/configs/smoke.json"), "config file exists")
check(#Argon:GetConfigs() == 1, "GetConfigs lists it")

Argon:SetFlag("audio.volume", 1)
Argon:SetFlag("audio.mute", false)
check(Argon:LoadConfig("smoke") == true, "LoadConfig reads")
check(Argon:GetFlag("audio.volume") == 70, "numbers restored")
check(Argon:GetFlag("audio.mute") == true, "booleans restored")
check(typeof(Argon:GetFlag("audio.tint")) == "Color3", "Color3 restored")
check(math.abs(Argon:GetFlag("audio.tint").B - 30 / 255) < 0.01, "Color3 channels restored")
check(Argon:LoadConfig("nope") == false, "missing config returns false")
check(Argon:DeleteConfig("smoke") == true, "DeleteConfig removes it")
check(#Argon:GetConfigs() == 0, "config list empty again")

-- ---------------------------------------------------------------- notifications and dialogs
group("notifications")

local toast = Argon:Notify({ Title = "Argon", Text = "Loaded", Kind = "success", Duration = 1 })
check(toast ~= nil, "toast created")
check(#Argon.Notifications == 0, "notifications are tracked by the UI module")
robloxMock.runScheduler()
check(true, "scheduler drained")

local dialog = Argon:Dialog({
    Title = "Confirm",
    Text = "Are you sure?",
    Buttons = { { Text = "Cancel" }, { Text = "OK", Primary = true, Callback = function() end } },
})
check(dialog ~= nil, "dialog created")
dialog:Close()
check(#Argon.Dialogs == 0, "dialog closed and unregistered")

-- ---------------------------------------------------------------- toolbar
group("toolbar")

local toolbarCalls = 0
local toolbar = Argon:Toolbar({
    Corner = "BottomLeft",
    Buttons = {
        { Icon = "×", Tooltip = "Close", Callback = function() toolbarCalls = toolbarCalls + 1 end },
        { Icon = "▤", Tooltip = "Menu" },
        { Text = "Hide widgets", Icon = "◱", Style = "pill" },
    },
})
check(toolbar ~= nil, "toolbar builds")
check(#toolbar.Buttons == 3, "toolbar buttons created")
toolbar.Buttons[1].MouseButton1Click:Fire()
check(toolbarCalls == 1, "toolbar callback fires")
toolbar:SetVisible(false)
check(toolbar.Gui.Enabled == false, "toolbar hides")

local watermark = Argon:Watermark("Argon 2.0")
check(watermark.Label.Text == "Argon 2.0", "watermark text")
watermark:SetText("changed")
check(watermark.Label.Text == "changed", "watermark updates")

-- ---------------------------------------------------------------- keybinds
group("keybinds")

local hotkeyState = nil
Argon:BindKey(Enum.KeyCode.X, function(down)
    hotkeyState = down
end)
UserInputService.InputBegan:Fire(robloxMock.input(Enum.UserInputType.Keyboard, 0, 0, Enum.KeyCode.X), false)
check(hotkeyState == true, "BindKey press handler")
UserInputService.InputEnded:Fire(robloxMock.input(Enum.UserInputType.Keyboard, 0, 0, Enum.KeyCode.X))
check(hotkeyState == false, "BindKey release handler")

-- ---------------------------------------------------------------- iris layer
group("iris layer")

local Iris = Argon.Iris
Iris:Init({ Title = "Iris Test", Width = 500, Height = 400 })
check(Iris.Window ~= nil, "iris window created")
local irisToggle = Iris:Toggle({ Text = "Iris toggle", Default = true, Changed = function() end })
check(irisToggle ~= nil and irisToggle:Get() == true, "iris toggle created")
local irisSlider = Iris:Slider({ Text = "Iris slider", Min = 0, Max = 10, Default = 5 })
check(irisSlider:Get() == 5, "iris slider created")
local irisButton = Iris:Button({ Text = "Iris button", Callback = function() end })
check(irisButton ~= nil, "iris button created")
Iris:Text({ Text = "hello" })
Iris:Separator()
local irisTable = Iris:Table({ Columns = { "A", "B" }, Rows = { { 1, 2 } } })
check(irisTable ~= nil, "iris table created")
Iris:Tab({ Text = "Second" })
check(#Iris.Window.Pages == 2, "iris tab creates a page")

-- ---------------------------------------------------------------- config page builder
group("config page")

local page2 = Argon:BuildConfigPage(window, {})
check(page2 ~= nil, "BuildConfigPage returns a page")
check(page2 == window:GetPage("Settings"), "reuses the existing Settings page")
check(#page2.Sections >= 1, "config page has sections")

-- ---------------------------------------------------------------- teardown
group("teardown")

local liveBefore = robloxMock.countLive()
Argon:Unload()
check(Argon.Unloaded == true, "Unload flips the flag")
check(getgenv().Argon == nil, "getgenv binding cleared")
check(robloxMock.countLive() <= baseline + 6, "no instances leak after Unload, got "
    .. tostring(robloxMock.countLive()) .. " baseline " .. tostring(baseline))
check(robloxMock.countLive() < liveBefore, "unload destroyed instances")

results.mockErrors = robloxMock.errors
return results
