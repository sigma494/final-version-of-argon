--[[ examples/basic.lua
     The smallest useful menu: one window, one page, one section, three controls,
     a notification and a flag read from a render loop.
]]

local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()

local Window = Argon:Window({
    Title = "Argon",
    Subtitle = "basic example",
    ToggleKey = Enum.KeyCode.RightShift,
    Width = 520,
    Height = 400,
    Theme = "Dark",
})

local Main = Window:Page({ Name = "Main", Icon = "▤" })
local Section = Main:Section({ Name = "Example" })

Section:Toggle({ Name = "Enabled", Flag = "example.enabled", Default = false }, function(on)
    print("enabled:", on)
end)

Section:Slider({
    Name = "Speed",
    Flag = "example.speed",
    Min = 1, Max = 50, Default = 16, Step = 1,
}, function(value)
    print("speed:", value)
end)

Section:Dropdown({
    Name = "Mode",
    Flag = "example.mode",
    Options = { "Silent", "Legit", "Rage" },
    Default = "Silent",
})

Section:Keybind({ Name = "Hotkey", Flag = "example.key", Default = Enum.KeyCode.E })
Section:Button({ Name = "Print flags", Primary = true }, function()
    local flags = Argon:GetFlags()
    local names = {}
    for key in pairs(flags) do
        names[#names + 1] = key
    end
    table.sort(names)
    for _, key in ipairs(names) do
        print(key, tostring(flags[key]))
    end
end)

local RunService = game:GetService("RunService")
RunService.RenderStepped:Connect(function()
    if Argon:GetFlag("example.enabled") then
        local _speed = Argon:GetFlag("example.speed")
        -- do the thing here
    end
end)

Window:Notify({ Kind = "success", Title = "Argon", Text = "RightShift opens the menu." })

return Window
