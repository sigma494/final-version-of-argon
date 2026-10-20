--[[ examples/iris_style.lua
     Drop-in replacement for the Iris snippets most executor scripts copy around.
     Same call shapes, real widgets underneath.
]]

local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()
local Iris = Argon.Iris

Iris:Init({
    Title = "Iris-style menu",
    Width = 520,
    Height = 460,
    Theme = "Legacy",
})

local state = { aim = false, fov = 90 }

Iris:Tab({ Text = "Aimbot" })

Iris:Section_({ Text = "Targeting" })

Iris:Toggle({
    Text = "Enabled",
    Default = false,
    Changed = function(enabled)
        state.aim = enabled
        print("aim:", enabled)
    end,
})

Iris:Slider({
    Text = "FOV",
    Min = 10,
    Max = 360,
    Default = 90,
    Suffix = "°",
    Changed = function(value)
        state.fov = value
    end,
})

Iris:Dropdown({
    Text = "Hitbox",
    Values = { "Head", "Torso", "Closest" },
    Default = "Head",
    Changed = function(value)
        print("hitbox:", value)
    end,
})

Iris:Keybind({ Text = "Aim key", Default = Enum.KeyCode.E })

Iris:Separator()

Iris:Section_({ Text = "Appearance" })
Iris:ColorPicker({ Text = "Box color", Default = Color3.fromRGB(88, 166, 255) })
Iris:Checkbox({ Text = "Show FOV circle", Default = true })

Iris:Tab({ Text = "Misc" })
Iris:Section_({ Text = "Utility" })

Iris:Input({ Text = "Webhook", PlaceholderText = "https://discord.com/api/webhooks/…" })
Iris:Button({
    Text = "Send test",
    Primary = true,
    Callback = function()
        Iris:Notify({ Kind = "success", Title = "Iris layer", Text = "Button callback fired." })
    end,
})

Iris:Text({ Text = "Every Iris call above builds a real Argon widget with flags and configs." })

Iris:Table({
    Columns = { "Setting", "Value" },
    Rows = {
        { "aim", tostring(state.aim) },
        { "fov", tostring(state.fov) },
    },
})

return Iris
