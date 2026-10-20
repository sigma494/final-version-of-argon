--[[ tests/docs_api.lua
     Every call in README.md and examples/ must actually work. This script mirrors
     the documented API surface (config keys, component signatures, handle methods)
     so the docs cannot drift away from the implementation.
]]

local passed, failed = 0, 0
local messages = {}

local function check(label, ok, detail)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        messages[#messages + 1] = label .. (detail and (": " .. tostring(detail)) or "")
    end
end

local function safe(label, fn)
    local ok, err = pcall(fn)
    check(label, ok, err)
    return ok
end

local Argon = loadstring()()

-- --------------------------------------------------------------------------
-- window config keys from the README
-- --------------------------------------------------------------------------
local Window = Argon:Window({
    Title = "luau.pro",
    Subtitle = "v2.0.0",
    Logo = "A",
    User = { Name = "farmerjoe", Tag = "Premium" },
    ToggleKey = Enum.KeyCode.RightShift,
    Theme = "Aqua",
    Accent = Color3.fromRGB(52, 196, 168),
    Width = 660,
    Height = 520,
    MinWidth = 560,
    MinHeight = 420,
    Resizable = true,
    Rail = true,
    Sidebar = true,
    ThemeSwitch = true,
    DisplayOrder = 100,
})
check("window build", Window ~= nil)

-- --------------------------------------------------------------------------
-- page config keys + every documented page method
-- --------------------------------------------------------------------------
local Page = Window:Page({
    Name = "Autobuilds",
    Icon = "x",
    Subtitle = "8 Features",
    Group = "MAIN",
    Badge = "PRO",
    Search = true,
    Rail = true,
    Closable = false,
})

safe("Page:Pills", function()
    Page:Pills({
        Options = {
            { Name = "All", Value = "all" },
            { Name = "Free", Value = "free" },
            { Name = "Premium", Value = "premium" },
        },
        Default = "all",
        Callback = function() end,
    })
end)

safe("Page:Action", function() Page:Action("Select a feature", function() end) end)
safe("Page:SetActionEnabled", function() Page:SetActionEnabled(false) Page:SetActionEnabled(true) end)
safe("Page:Search", function() Page:Search("build") Page:Search("") end)
safe("Page:SetPill", function() Page:SetPill("free") Page:SetPill("all") end)
safe("Page:ApplyFilter", function() Page:ApplyFilter("all") end)
safe("Page:ScrollToTop", function() Page:ScrollToTop() end)
safe("Page:SetSubtitle", function() Page:SetSubtitle("8 Features") end)
safe("Page:Refresh", function() Page:Refresh() end)
safe("Page:GetSection", function() Page:Section({ Name = "probe" }) end)

-- --------------------------------------------------------------------------
-- section config keys + documented section methods
-- --------------------------------------------------------------------------
local Section = Page:Section({
    Name = "Combat",
    Icon = "x",
    Collapsed = false,
})

safe("Section:Collapse", function() Section:Collapse(true) Section:Collapse(false) end)
safe("Section:Toggle", function() Section:Toggle() Section:Toggle() end)
safe("Section:SetName", function() Section:SetName("PvP") Section:SetName("Combat") end)
safe("Section:SetVisible", function() Section:SetVisible(true) end)
safe("Section:UpdateOrder", function() Section:UpdateOrder() end)

-- --------------------------------------------------------------------------
-- every component signature documented in the README
-- --------------------------------------------------------------------------
local handles = {}

safe("Toggle", function()
    handles.toggle = Section:Toggle({
        Name = "Aimbot", Description = "auto aim", Icon = "x",
        Flag = "docs.aimbot", Default = false, Width = "half", Tooltip = "hint",
    }, function() end)
end)

safe("Checkbox", function()
    handles.checkbox = Section:Checkbox({ Name = "Show FOV", Flag = "docs.fov", Default = true, Width = "half" })
end)

safe("Slider", function()
    handles.slider = Section:Slider({
        Name = "FOV", Flag = "docs.fovValue", Min = 10, Max = 360, Default = 90,
        Step = 1, Decimals = 0, Suffix = "deg", Prefix = "", Ticks = 4,
    }, function() end)
end)

safe("Input", function()
    handles.input = Section:Input({
        Name = "Name", Placeholder = "type", Default = "", Numeric = false,
        MaxLength = 32, Live = true, SlotWidth = 170, Flag = "docs.input",
    }, function() end)
end)

safe("Textarea", function()
    handles.textarea = Section:Textarea({
        Name = "Notes", Placeholder = "notes", Default = "", Height = 72, Flag = "docs.notes",
    }, function() end)
end)

safe("Keybind", function()
    handles.keybind = Section:Keybind({ Name = "Key", Default = Enum.KeyCode.F2, Flag = "docs.key" }, function() end)
end)

safe("Button", function()
    handles.button = Section:Button({
        Name = "Apply", Primary = true, Icon = "x", Confirm = false, Height = 32,
    }, function() end)
end)

safe("DualButton", function()
    handles.dual = Section:DualButton({ Name = "Save", AlternateName = "Load" }, function() end, function() end)
end)

safe("Dropdown", function()
    handles.dropdown = Section:Dropdown({
        Name = "Mode", Icon = "x", MaxHeight = 200, Multi = false, Search = true,
        Default = "Free",
        Options = {
            "Free",
            { Text = "Premium", Value = "premium", Description = "paid", Icon = "x", Disabled = false },
        },
        Flag = "docs.mode",
    }, function() end)
end)

safe("Dropdown handle", function()
    handles.dropdown:SetOptions({ "A", "B" })
    check("Dropdown:GetOptions", type(handles.dropdown:GetOptions()) == "table")
    handles.dropdown:OpenList()
    handles.dropdown:Close()
end)

safe("ColorPicker", function()
    handles.color = Section:ColorPicker({
        Name = "Box color", Default = Color3.fromRGB(88, 166, 255), Alpha = true,
        Eyedropper = true, SquareSize = 132, Presets = { Color3.fromRGB(255, 0, 0) },
        Flag = "docs.color",
    }, function() end)
end)

safe("ColorPicker handle", function()
    handles.color:SetColor(Color3.fromRGB(10, 20, 30))
    handles.color:SetAlpha(0.5)
end)

safe("ThemePicker", function()
    handles.themes = Section:ThemePicker({ Name = "Theme", Themes = { "Dark", "Light" }, Columns = 2 }, function() end)
end)

safe("Card", function()
    handles.card = Section:Card({
        Name = "Autobuild Classic", Description = "Load .build files", Image = "rbxassetid://1",
        Glyph = "x", Tint = Color3.fromRGB(40, 40, 40), Badge = "Active",
        BadgeColor = Color3.fromRGB(74, 206, 132), Tier = "free", Selected = true, Pinned = false,
    }, function() end)
end)

safe("Card handle", function()
    handles.card:Select(true)
    check("Card:IsSelected", handles.card:IsSelected() == true)
    handles.card:SetBadge("Soon", Color3.fromRGB(214, 158, 46))
    handles.card:SetImage("rbxassetid://2")
end)

safe("Table", function()
    handles.table = Section:Table({
        Columns = { "Player", "Distance" },
        ColumnWidths = { 0.6, 0.4 },
        Rows = { { "farmerjoe", "0m" } },
    })
end)

safe("Progress", function()
    handles.progress = Section:Progress({ Name = "Session", Default = 0, Description = "Time farmed" })
    handles.progress:SetProgress(40)
    check("Progress:GetProgress", tonumber(handles.progress:GetProgress()) == 40)
end)

safe("Tag", function()
    Section:Tag({ Tags = { { Text = "2.0.0", Color = Argon.Theme.Accent }, "stable" } })
end)

safe("UserRow", function()
    Section:UserRow({ Name = "farmerjoe", Description = "Premium", Avatar = nil, Color = Color3.fromRGB(30, 30, 30) })
end)

safe("Banner", function()
    Section:Banner({ Name = "Hot reload", Text = "Re-running replaces the UI.", Kind = "info", Dismissible = true })
end)

safe("Label", function()
    Section:Label({ Text = "hello", Bold = true, Color = Color3.fromRGB(255, 255, 255), TextSize = 13, Align = "left" })
end)

safe("Paragraph", function()
    Section:Paragraph({ Title = "Argon", Text = "single file library" })
end)

safe("Divider", function() Section:Divider() end)
safe("Space", function() Section:Space(12) end)

safe("Image", function()
    Section:Image({ Image = "rbxassetid://1", Name = "preview", Height = 60, Transparency = 0 })
end)

-- --------------------------------------------------------------------------
-- generic handle contract
-- --------------------------------------------------------------------------
safe("handle:Set/Get", function()
    handles.toggle:Set(true)
    check("Toggle:Get", handles.toggle:Get() == true)
    handles.toggle:Set(false, true)
    handles.slider:Set(120)
    check("Slider:Get", tonumber(handles.slider:Get()) == 120)
    handles.input:Set("abc")
    check("Input:Get", handles.input:Get() == "abc")
    handles.dropdown:Set("A")
end)

safe("handle:OnChanged", function()
    local fired = false
    handles.slider:OnChanged(function() fired = true end)
    handles.slider:Set(140)
    check("OnChanged fired", fired == true)
end)

safe("handle:SetVisible/SetDisabled", function()
    handles.input:SetVisible(true)
    handles.input:SetDisabled(true)
    handles.input:SetDisabled(false)
end)

safe("handle:SetName/SetDescription/Refresh", function()
    handles.checkbox:SetName("Renamed")
    handles.checkbox:SetDescription("desc")
    handles.checkbox:Refresh()
end)

safe("handle:GetValue", function()
    check("GetValue", handles.checkbox:GetValue() == true)
end)

-- --------------------------------------------------------------------------
-- flags, themes, configs
-- --------------------------------------------------------------------------
safe("flags", function()
    Argon:SetFlag("docs.flag", 5)
    check("GetFlag", tonumber(Argon:GetFlag("docs.flag")) == 5)
    check("GetFlags", type(Argon:GetFlags()) == "table")
    Argon:OnFlagChanged("docs.flag", function() end)
    Window:OnFlagChanged("docs.flag", function() end)
end)

safe("themes", function()
    for _, name in ipairs({ "Dark", "Aqua", "Serika", "Rust", "Legacy", "Rose", "Mint", "Light" }) do
        check("SetTheme " .. name, Argon:SetTheme(name) ~= false)
    end
    check("GetThemeNames", type(Argon:GetThemeNames()) == "table")
    check("GetTheme", type(Argon:GetTheme()) == "table")
    Argon:SetAccent(Color3.fromRGB(255, 120, 200))
    safe("RegisterTheme", function()
        Argon:RegisterTheme({
            Name = "Vapor",
            Accent = Color3.fromRGB(255, 113, 206),
            Surface = Color3.fromRGB(36, 27, 48),
            Text = Color3.fromRGB(255, 240, 250),
        })
        Argon:SetTheme("Vapor")
    end)
    check("ThemeTemplate", type(Argon:ThemeTemplate()) == "table")
    Argon:SetTheme("Dark")
end)

safe("configs", function()
    Argon:SetConfigFolder("Argon/configs")
    check("SaveConfig", Argon:SaveConfig("docs") == true)
    check("LoadConfig", Argon:LoadConfig("docs") == true)
    check("GetConfigs", type(Argon:GetConfigs()) == "table")
    check("DeleteConfig", Argon:DeleteConfig("docs") == true)
    Argon:EnableAutoSave("docs", 2)
    Argon:EnableAutoSave(nil)
end)

safe("BuildConfigPage", function()
    local extra = Argon:Window({ Title = "Settings host" })
    check("BuildConfigPage", Argon:BuildConfigPage(extra) ~= nil)
    extra:Destroy()
end)

-- --------------------------------------------------------------------------
-- overlays
-- --------------------------------------------------------------------------
safe("Notify", function()
    Argon:Notify({
        Kind = "success", Title = "Autobuilds", Text = "Opening", Duration = 5,
        Color = Color3.fromRGB(74, 206, 132),
    })
    for _, kind in ipairs({ "info", "success", "warning", "danger", "premium" }) do
        Argon:Notify({ Kind = kind, Title = kind, Text = "kind check" })
    end
end)

safe("Dialog", function()
    Argon:Dialog({
        Title = "Confirm", Text = "This cannot be undone.",
        Buttons = { { Text = "Cancel" }, { Text = "OK", Primary = true, Callback = function() end } },
    })
end)

safe("Toolbar", function()
    local toolbar = Argon:Toolbar({
        Corner = "BottomLeft",
        Buttons = {
            { Icon = "x", Tooltip = "Hide UI", Callback = function() end },
            { Text = "Close luau.pro", Icon = "x", Style = "pill", Callback = function() end },
        },
    })
    check("toolbar built", toolbar ~= nil)
end)

for _, corner in ipairs({ "TopRight", "BottomRight", "TopLeft" }) do
    safe("Toolbar corner " .. corner, function()
        Argon:Toolbar({ Corner = corner, Buttons = { { Icon = "x", Callback = function() end } } })
    end)
end

safe("Watermark", function() Argon:Watermark("luau.pro  -  Argon 2.0.0") end)
safe("ShowLoading", function() Argon:ShowLoading("Fetching builds...", 1.5) end)

-- --------------------------------------------------------------------------
-- keybinds + misc
-- --------------------------------------------------------------------------
safe("BindKey", function()
    local binding = Argon:BindKey(Enum.KeyCode.F5, function() end)
    check("binding id", binding ~= nil)
    Argon:UnbindKey(binding)
    Argon:BindKey(Enum.KeyCode.F6, function() end)
    Argon:ClearKeys()
end)

check("GetUptime", type(Argon:GetUptime()) == "number")
check("IsMobile", type(Argon:IsMobile()) == "boolean")
safe("GetViewportSize", function() check("viewport", Argon:GetViewportSize() ~= nil) end)
check("GetVersion", type(Argon:GetVersion()) == "string")
check("IsLoaded", Argon:IsLoaded() == true)
safe("GetWindows", function() check("GetWindows", #Argon:GetWindows() >= 1) end)

-- --------------------------------------------------------------------------
-- window methods from the README
-- --------------------------------------------------------------------------
safe("Window methods", function()
    Window:SetTitle("luau.pro")
    Window:SetSubtitle("v2.0.0")
    Window:SetUser({ Name = "farmerjoe", Tag = "Premium" })
    Window:SetTheme("Aqua")
    Window:SetAccent(Color3.fromRGB(52, 196, 168))
    Window:SetMinimized(true)
    Window:SetMinimized(false)
    Window:SetVisible(false)
    Window:SetVisible(true)
    Window:Toggle()
    Window:Toggle()
    Window:SelectPage(Page)
    check("GetPage", Window:GetPage("Autobuilds") == Page)
    Window:Notify({ Title = "hi", Text = "there" })
    Window:Dialog({ Title = "hi", Text = "there" })
    Window:Refresh()
end)

-- --------------------------------------------------------------------------
-- Iris compatibility
-- --------------------------------------------------------------------------
safe("Iris layer", function()
    local Iris = Argon.Iris
    Iris:Init({ Title = "Iris-style menu", Width = 520, Height = 460, Theme = "Legacy" })
    Iris:Tab({ Text = "Aimbot" })
    Iris:Section_({ Text = "Targeting" })
    Iris:Toggle({ Text = "Enabled", Default = false, Changed = function() end })
    Iris:Slider({ Text = "FOV", Min = 10, Max = 360, Default = 90, Suffix = "deg", Changed = function() end })
    Iris:Dropdown({ Text = "Hitbox", Values = { "Head", "Torso" }, Default = "Head", Changed = function() end })
    Iris:Keybind({ Text = "Aim key", Default = Enum.KeyCode.E })
    Iris:Separator()
    Iris:ColorPicker({ Text = "Box color", Default = Color3.fromRGB(88, 166, 255) })
    Iris:Checkbox({ Text = "Show FOV circle", Default = true })
    Iris:Tab({ Text = "Misc" })
    Iris:Input({ Text = "Webhook", PlaceholderText = "https://example.test" })
    Iris:Button({ Text = "Send test", Primary = true, Callback = function() end })
    Iris:Text({ Text = "text" })
    Iris:ProgressBar({ Text = "progress", Value = 0.5 })
    Iris:InputText({ Text = "input text" })
    Iris:Table({ Columns = { "A", "B" }, Rows = { { "1", "2" } } })
    Iris:TabBar()
    Iris:Tree()
    Iris:End()
end)

-- --------------------------------------------------------------------------
-- section clear/visibility + teardown
-- --------------------------------------------------------------------------
safe("Section:Clear", function() Section:Clear() end)
safe("destroy handles", function()
    for _, handle in pairs(handles) do
        if type(handle) == "table" and handle.Destroy then
            handle:Destroy()
        end
    end
end)

local before = #Argon:GetWindows()
check("windows tracked", before >= 2, before)
Argon:Unload()
check("unload clears windows", #Argon:GetWindows() == 0, #Argon:GetWindows())
check("IsLoaded after unload", Argon:IsLoaded() == false)

local mock = robloxMock or nil
return {
    passed = passed,
    failed = failed,
    messages = messages,
    mockErrors = mock and mock.errors or {},
}
