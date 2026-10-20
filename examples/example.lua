--[[ examples/example.lua
     A complete, runnable script that uses every Argon element.
     Drop it in your executor's script box, or run it from a file.

     LeftShift toggles the menu.
]]

local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()

local Window = Argon:Window({
    Title = "Argon",
    Subtitle = "example script",
    ToggleKey = Enum.KeyCode.LeftShift,
    Width = 560,
    Height = 440,
    Accent = Color3.fromRGB(88, 166, 255),
})

-- ============================================================================
-- state: one table, driven entirely by element callbacks
-- ============================================================================
local State = {
    esp = false,
    espColor = Color3.fromRGB(88, 166, 255),
    aim = false,
    fov = 120,
    target = "Head",
    key = Enum.KeyCode.E,
    webhook = "",
}

-- ============================================================================
-- Combat tab
-- ============================================================================
local Combat = Window:Tab({ Name = "Combat" })
local Aim = Combat:Section({ Name = "Aim assist" })

Aim:Toggle({
    Name = "Enabled",
    Description = "Snap toward the nearest player inside the FOV",
    Flag = "aim_enabled",
    Default = false,
}, function(on)
    State.aim = on
    print("aim assist:", on)
end)

Aim:Slider({
    Name = "Field of view",
    Description = "Radius in pixels around the crosshair",
    Flag = "aim_fov",
    Min = 10, Max = 500, Default = 120, Step = 5, Suffix = "px",
}, function(value)
    State.fov = value
end)

Aim:Dropdown({
    Name = "Hitbox",
    Flag = "aim_target",
    Options = { "Head", "Torso", "Closest" },
    Default = "Head",
}, function(value)
    State.target = value
end)

Aim:Keybind({
    Name = "Aim key",
    Flag = "aim_key",
    Default = Enum.KeyCode.E,
}, function(down)
    if down and State.aim then
        print("aiming at", State.target)
    end
end)

-- ============================================================================
-- Visuals tab
-- ============================================================================
local Visuals = Window:Tab({ Name = "Visuals" })
local Esp = Visuals:Section({ Name = "ESP" })

Esp:Toggle({
    Name = "Player boxes",
    Flag = "esp_enabled",
    Default = false,
}, function(on)
    State.esp = on
end)

Esp:ColorPicker({
    Name = "Box color",
    Flag = "esp_color",
    Default = Color3.fromRGB(88, 166, 255),
}, function(color)
    State.espColor = color
end)

Esp:Slider({
    Name = "Fill opacity",
    Flag = "esp_fill",
    Min = 0, Max = 100, Default = 25, Step = 1, Suffix = "%",
}, function() end)

local World = Visuals:Section({ Name = "World" })
World:Toggle({ Name = "Fullbright", Flag = "fullbright" }, function() end)
World:Toggle({ Name = "No fog", Flag = "no_fog" }, function() end)
World:Slider({ Name = "Field of view", Flag = "camera_fov", Min = 70, Max = 120, Default = 70, Step = 1 })

-- ============================================================================
-- Settings tab
-- ============================================================================
local Settings = Window:Tab({ Name = "Settings" })
local Configs = Settings:Section({ Name = "Config" })

local ConfigName = Configs:Input({
    Name = "Config name",
    Placeholder = "default",
    Default = "default",
})

Configs:Button({ Name = "Save config" }, function()
    local name = ConfigName:Get()
    if name == "" then
        return Argon:Notify({ Title = "Argon", Text = "Give the config a name first." })
    end
    local ok = Window:SaveConfig(name)
    Argon:Notify({
        Title = "Config",
        Text = ok and ("Saved " .. name) or ("Could not save " .. name),
        Color = ok and Argon.Theme.Success or Argon.Theme.Danger,
    })
end)

Configs:Button({ Name = "Load config" }, function()
    local name = ConfigName:Get()
    local ok = Window:LoadConfig(name)
    Argon:Notify({
        Title = "Config",
        Text = ok and ("Loaded " .. name) or ("No config named " .. name),
        Color = ok and Argon.Theme.Success or Argon.Theme.Danger,
    })
end)

Configs:Button({ Name = "Delete config" }, function()
    Window:DeleteConfig(ConfigName:Get())
end)

Configs:Divider()

local About = Settings:Section({ Name = "About" })
About:Paragraph({
    Title = "Argon " .. Argon.Version,
    Text = "Single-file UI library. Flags are readable from anywhere with Argon:GetFlag(\"aim_fov\").",
})
About:Label({ Text = "Press LeftShift to toggle this menu.", TextSize = 11, Color = Argon.Theme.TextMuted })
About:Button({ Name = "Unload UI" }, function()
    Argon:Unload()
end)

-- ============================================================================
-- live loop example: flags are the whole contract between UI and cheat logic
-- ============================================================================
local RunService = game:GetService("RunService")
RunService.RenderStepped:Connect(function()
    if Argon:GetFlag("esp_enabled") then
        -- draw boxes here; colors come straight from the picker
        local _ = Argon:GetFlag("esp_color")
    end
end)

Window:Notify({
    Title = "Argon loaded",
    Text = "LeftShift opens the menu.",
    Duration = 5,
})
