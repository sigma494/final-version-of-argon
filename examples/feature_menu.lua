--[[ examples/feature_menu.lua
     The full luau.pro-style shell: icon rail, grouped sidebar, feature cards with
     status pills, filter pills, search, sticky action bar, theme picker, toolbar.

     Run it in an executor. RightShift toggles the UI.
]]

local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()

-- ============================================================================
-- window
-- ============================================================================
local Window = Argon:Window({
    Title = "luau.pro",
    Subtitle = "v2.0.0",
    Logo = "⚡",
    User = { Name = "farmerjoe", Tag = "Premium" },
    ToggleKey = Enum.KeyCode.RightShift,
    Theme = "Aqua",
    Width = 660,
    Height = 520,
    MinWidth = 560,
    MinHeight = 420,
    Resizable = true,
    Rail = true,
    ThemeSwitch = true,
})

-- ============================================================================
-- floating toolbar (bottom-left, like the reference)
-- ============================================================================
local Toolbar = Argon:Toolbar({
    Corner = "BottomLeft",
    Buttons = {
        { Icon = "◱", Tooltip = "Toggle menu", Callback = function() Window:Toggle() end },
        { Icon = "▤", Tooltip = "Autobuilds", Callback = function() 
            local page = Window:GetPage("Autobuilds")
            if page then Window:SelectPage(page) end
        end },
        { Icon = "♫", Tooltip = "Music", Callback = function()
            Argon:Notify({ Kind = "info", Title = "Music", Text = "Nothing queued." })
        end },
        { Text = "Close luau.pro", Icon = "✕", Style = "pill", Callback = function() Window:SetVisible(false) end },
    },
})

Argon:Watermark("luau.pro  ·  Argon " .. Argon.Version)

-- ============================================================================
-- data: every feature card in the reference
-- ============================================================================
local Features = {
    { Name = "Autobuild Classic", Description = "Load .build files with ease", Badge = "Active",
      Tier = "free", Glyph = "⚒", ThumbnailBadge = "v2.4", Selected = true },
    { Name = "Save Build", Description = "Save or steal from others", Badge = "Active",
      Tier = "free", Glyph = "▣", ThumbnailBadge = "v1.9" },
    { Name = "Image Loader", Description = "Load any image from the internet", Badge = "Active",
      Tier = "free", Glyph = "◨" },
    { Name = "Image Geometrizer", Description = "Looks like a painting", Badge = "Active",
      Tier = "premium", Glyph = "◇" },
    { Name = "Music Loader", Description = "Support .mid and .nbs files", Badge = "Soon",
      Tier = "premium", Glyph = "♫", BadgeColor = Color3.fromRGB(214, 158, 46) },
    { Name = "File Market", Description = "Browse community builds", Badge = "Soon",
      Tier = "premium", Glyph = "▦", BadgeColor = Color3.fromRGB(214, 158, 46) },
    { Name = "Auto Farm", Description = "Idle farming routines", Badge = "Soon",
      Tier = "premium", Glyph = "★", BadgeColor = Color3.fromRGB(214, 158, 46) },
}

-- ============================================================================
-- Autobuilds page
-- ============================================================================
local Autobuilds = Window:Page({
    Name = "Autobuilds",
    Icon = "⚒",
    Subtitle = "8 Features",
    Rail = true,
})

Autobuilds:Pills({
    Options = {
        { Name = "All", Value = "all" },
        { Name = "Free", Value = "free" },
        { Name = "Premium", Value = "premium" },
    },
    Default = "all",
})

local FeatureSection = Autobuilds:Section({ Name = "Features" })
local SelectedName = "Autobuild Classic"

for _, feature in ipairs(Features) do
    FeatureSection:Card(feature, function(element)
        SelectedName = element.Config.Name
        Autobuilds:Action("Continue with " .. SelectedName, function()
            Argon:Notify({
                Kind = "success",
                Title = "Autobuilds",
                Text = "Opening " .. SelectedName,
            })
        end)
    end)
end

Autobuilds:Action("Continue with " .. SelectedName, function()
    Argon:Notify({ Kind = "success", Title = "Autobuilds", Text = "Opening " .. SelectedName })
end)

-- ============================================================================
-- File Market page
-- ============================================================================
local Market = Window:Page({ Name = "File Market", Icon = "☁" })

local MarketSection = Market:Section({ Name = "Community builds" })
for index = 1, 5 do
    MarketSection:Card({
        Name = "Community build #" .. index,
        Description = "Uploaded " .. index .. "d ago · " .. (120 * index) .. " downloads",
        Badge = index % 3 == 0 and "Premium" or "Free",
        BadgeColor = index % 3 == 0 and Argon.Theme.Premium or Argon.Theme.Accent,
        Tier = index % 3 == 0 and "premium" or "free",
        Glyph = "▦",
    }, function(element)
        Market:Action("Install " .. element.Config.Name, function()
            Argon:Notify({ Title = "File Market", Text = element.Config.Name .. " installed." })
        end)
    end)
end

-- ============================================================================
-- Premium page
-- ============================================================================
local Premium = Window:Page({ Name = "Premium", Icon = "★", Badge = "PRO" })
local PremiumSection = Premium:Section({ Name = "Subscription" })
PremiumSection:Banner({
    Name = "Free plan",
    Text = "You are on the free plan. Premium unlocks 60+ features and config sync.",
    Kind = "warning",
})
PremiumSection:Progress({ Name = "Monthly usage", Default = 42, Description = "12 / 28 features used" })
PremiumSection:UserRow({ Name = "farmerjoe", Description = "Premium until 2027-01-01", Avatar = nil })
PremiumSection:DualButton({ Name = "Upgrade", AlternateName = "Restore" }, function()
    Argon:Dialog({
        Title = "Premium",
        Text = "This demo does not process payments.",
        Buttons = { { Text = "Close", Primary = true } },
    })
end, function()
    Argon:Notify({ Kind = "info", Title = "Premium", Text = "Nothing to restore." })
end)

-- ============================================================================
-- Auto Farm page
-- ============================================================================
local Farm = Window:Page({ Name = "Auto Farm", Icon = "♛" })
local FarmSection = Farm:Section({ Name = "Routine" })
FarmSection:Toggle({ Name = "Enabled", Flag = "farm.enabled", Default = false }, function(on)
    Argon:Notify({ Title = "Auto Farm", Text = on and "Started" or "Stopped" })
end)
FarmSection:Dropdown({
    Name = "Profile",
    Flag = "farm.profile",
    Options = { "Balanced", "Fast", "Safe" },
    Default = "Balanced",
})
FarmSection:Slider({ Name = "Tick rate", Flag = "farm.tick", Min = 0.1, Max = 2, Default = 0.5, Step = 0.1, Decimals = 1, Suffix = "s" })
FarmSection:Keybind({ Name = "Toggle key", Flag = "farm.key", Default = Enum.KeyCode.F2 })
FarmSection:Progress({ Name = "Session", Default = 0, Description = "Time farmed" })

-- ============================================================================
-- Players page
-- ============================================================================
local Players = Window:Page({ Name = "Players", Icon = "☺" })
local PlayersSection = Players:Section({ Name = "In this server" })
PlayersSection:Table({
    Columns = { "Player", "Distance", "Status" },
    ColumnWidths = { 0.5, 0.3, 0.2 },
    Rows = {
        { "farmerjoe", "0m", "you" },
        { "someone", "42m", "idle" },
        { "another", "118m", "moving" },
    },
})
PlayersSection:Input({ Name = "Filter", Placeholder = "name fragment", Flag = "players.filter" })

-- ============================================================================
-- Utilities page
-- ============================================================================
local Utilities = Window:Page({ Name = "Utilities", Icon = "▦" })
local UtilSection = Utilities:Section({ Name = "Server" })
UtilSection:Button({ Name = "Rejoin server", Primary = true }, function()
    Argon:Notify({ Title = "Utilities", Text = "game:GetService(\"TeleportService\"):TeleportToPlaceInstance(...)" })
end)
UtilSection:Button({ Name = "Copy job id", Confirm = true }, function()
    Argon:Notify({ Kind = "success", Title = "Copied", Text = game.JobId ~= "" and game.JobId or "job id hidden" })
end)
UtilSection:Divider()
UtilSection:Input({ Name = "Webhook URL", Placeholder = "https://discord.com/api/webhooks/…", Flag = "util.webhook" })
UtilSection:Textarea({ Name = "Notes", Placeholder = "Anything you want to keep around", Flag = "util.notes" })

-- ============================================================================
-- About page
-- ============================================================================
local About = Window:Page({ Name = "About", Icon = "i" })
local AboutSection = About:Section({ Name = "Argon", Icon = "i" })
AboutSection:Paragraph({
    Title = "Argon " .. Argon.Version,
    Text = "Single-file UI library for executor scripts. Themes, flags, configs,\n"
        .. "notifications and every component in this menu are built in.",
})
AboutSection:Tag({ Tags = { { Text = "2.0.0", Color = Argon.Theme.Accent }, { Text = "stable", Color = Argon.Theme.Success } } })
AboutSection:Button({ Name = "Unload UI" }, function()
    Argon:Unload()
end)

-- ============================================================================
-- OTHER group: Actions and Modules
-- ============================================================================
local Actions = Window:Page({ Name = "Actions", Icon = "✳", Group = "OTHER" })
local ActionSection = Actions:Section({ Name = "Quick actions" })
ActionSection:Button({ Name = "Test notification", Primary = true }, function()
    Argon:Notify({ Kind = "success", Title = "Argon", Text = "Notifications are working." })
end)
ActionSection:Button({ Name = "Show dialog" }, function()
    Argon:Dialog({
        Title = "Dialog",
        Text = "Dialogs are built in and stack safely.",
        Buttons = { { Text = "Cancel" }, { Text = "OK", Primary = true } },
    })
end)

local Modules = Window:Page({ Name = "Modules", Icon = "◈", Group = "OTHER" })
local ModuleSection = Modules:Section({ Name = "Loaded modules" })
for _, name in ipairs({ "autobuild", "esp", "aim", "teleport" }) do
    ModuleSection:Toggle({ Name = name, Flag = "module." .. name, Default = name == "autobuild" })
end
ModuleSection:Banner({ Name = "Hot reload", Text = "Re-executing the loader replaces this UI instead of stacking it.", Kind = "info", Dismissible = true })

-- ============================================================================
-- Settings page: theme picker + config management
-- ============================================================================
local Settings = Window:Page({ Name = "Settings", Icon = "⚙", Group = "OTHER", Search = false })

local Appearance = Settings:Section({ Name = "Appearance", Icon = "◐" })
Appearance:ThemePicker({ Name = "Theme", Columns = 5 })
Appearance:Toggle({ Name = "Reduce motion", Flag = "ui.reduceMotion", Default = false }, function(on)
    Argon.Config.ReduceMotion = on
end)
Appearance:Slider({
    Name = "Animation speed", Flag = "ui.animationSpeed",
    Min = 0.5, Max = 3, Default = 1, Step = 0.1, Decimals = 1, Suffix = "x",
}, function(speed)
    Argon.Config.AnimationSpeed = speed
end)

local Configs = Settings:Section({ Name = "Configuration", Icon = "▤" })
local ConfigName = Configs:Input({ Name = "Config name", Placeholder = "default", Flag = "ui.configName", Default = "default" })
local ConfigList = Configs:Dropdown({ Name = "Saved configs", Options = Argon:GetConfigs(), Flag = "ui.configSelected" })

Configs:DualButton({ Name = "Save", AlternateName = "Load" }, function()
    local name = ConfigName:Get()
    local ok = Argon:SaveConfig(name)
    ConfigList:SetOptions(Argon:GetConfigs())
    Argon:Notify({
        Kind = ok and "success" or "danger",
        Title = "Config",
        Text = ok and ("Saved \"" .. name .. "\"") or "writefile unavailable",
    })
end, function()
    local name = ConfigList:Get() or ConfigName:Get()
    local ok = Argon:LoadConfig(name)
    Argon:Notify({
        Kind = ok and "success" or "warning",
        Title = "Config",
        Text = ok and ("Loaded \"" .. tostring(name) .. "\"") or ("No config named \"" .. tostring(name) .. "\""),
    })
end)

Configs:DualButton({ Name = "Delete", AlternateName = "Refresh" }, function()
    Argon:DeleteConfig(ConfigList:Get() or ConfigName:Get())
    ConfigList:SetOptions(Argon:GetConfigs())
end, function()
    ConfigList:SetOptions(Argon:GetConfigs())
end)

-- ============================================================================
-- boot
-- ============================================================================
Window:SelectPage(Autobuilds)
Argon:Notify({
    Kind = "success",
    Title = "luau.pro",
    Text = "RightShift toggles the menu.",
    Duration = 5,
})

-- Optional: persist every change once a flag has been touched.
-- Argon:EnableAutoSave("default", 2)

return { Argon = Argon, Window = Window, Toolbar = Toolbar }
