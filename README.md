# Argon

A single-file UI library for Roblox executor scripts. Built around the dark shell from
luau.pro — icon rail, grouped sidebar, feature-card grid, sticky action bar, live theme
switcher — with an Iris-style compatibility layer for scripts that already use Iris.

~8,000 lines of plain Lua. No dependencies, no loader chain, no self-fetch, no nested
`loadstring`. Everything below ships in `Argon.lua`.

```lua
local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()

local Window = Argon:Window({
    Title = "luau.pro",
    Subtitle = "v2.0.0",
    User = { Name = "farmerjoe", Tag = "Premium" },
    ToggleKey = Enum.KeyCode.RightShift,
    Theme = "Aqua",
})

local Page = Window:Page({ Name = "Autobuilds", Icon = "⚒", Subtitle = "8 Features" })
local Section = Page:Section({ Name = "Features" })

Section:Toggle({ Name = "Aimbot", Flag = "aimbot" }, function(on) print(on) end)
Section:Slider({ Name = "FOV", Flag = "fov", Min = 10, Max = 360, Default = 90, Suffix = "°" })

Page:Action("Continue", function() print("chosen:", Argon:GetFlag("fov")) end)
```

## What's in the box

| area | what you get |
| --- | --- |
| **Shell** | draggable + resizable window, icon rail, grouped sidebar (MAIN / OTHER), logo, user card with tag, Light/Dark switch, minimize/close, toggle key |
| **Pages** | header with subtitle ("8 Features · synced 2m ago"), search field, filter pills (All/Free/Premium), scrolling sections, sticky action bar |
| **Sections** | collapsible cards with icon, element counter badge, header controls, two-column row packing |
| **Inputs** | Toggle, Checkbox, Slider (drag + editable value), Input, Textarea, Keybind, Dropdown (single/multi/search), ColorPicker (SV + hue + alpha + hex + presets), ThemePicker |
| **Content** | Card (thumbnail + status pill), Banner, Table, Progress, Tag, UserRow, Label, Paragraph, Divider, Space, Image |
| **Overlays** | toast notifications (kinds, actions), modal dialogs, tooltips, floating toolbar, watermark, loading bar |
| **State** | flags, listeners, JSON config round-trip (Color3/EnumItem/arrays), autosave, `BuildConfigPage` |
| **Extras** | global keybind registry, Iris compatibility layer, theme registration, safe unload |

## Install

Paste it, or vendor the file:

```bash
curl -O https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua
```

```lua
local Argon = loadstring(readfile("Argon.lua"))()   -- or HttpGet, or paste inline
```

Requirements: nothing. Works on Luau and on plain Lua 5.1–5.5 (the source avoids
Luau-only syntax: no `+=`, no `continue`, no type annotations, no generalised iteration).

## Window

```lua
local Window = Argon:Window({
    Title = "luau.pro",              -- sidebar logo text
    Subtitle = "v2.0.0",
    Logo = "⚡",                     -- glyph shown in the logo mark
    User = { Name = "farmerjoe", Tag = "Premium", Avatar = "rbxassetid://0" },
    ToggleKey = Enum.KeyCode.RightShift,
    Theme = "Aqua",                  -- any registered palette name
    Accent = Color3.fromRGB(52, 196, 168),
    Width = 660, Height = 520,
    MinWidth = 560, MinHeight = 420,
    Resizable = true,
    Rail = true,                     -- icon rail on the far left
    Sidebar = true,
    ThemeSwitch = true,              -- Light/Dark pill in the sidebar
    DisplayOrder = 100,
    AutoLoad = "default",            -- load a config on build
    AutoSaveTo = "default",          -- persist flags as they change
})
```

Methods: `Page`, `SelectPage`, `GetPage`, `SetTitle`, `SetSubtitle`, `SetUser`,
`SetTheme`, `SetAccent`, `SetMinimized`, `SetVisible`, `Toggle`, `Refresh`, `Notify`,
`Dialog`, `OnFlagChanged`, `Destroy`.

## Pages

```lua
local Autobuilds = Window:Page({
    Name = "Autobuilds",
    Icon = "⚒",
    Subtitle = "8 Features",
    Group = "MAIN",        -- sidebar group heading
    Badge = "PRO",         -- optional pill next to the nav label
    Search = true,         -- search box
    Rail = true,           -- show in the icon rail
    Closable = false,
})

Autobuilds:Pills({
    Options = {
        { Name = "All", Value = "all" },
        { Name = "Free", Value = "free" },
        { Name = "Premium", Value = "premium" },
    },
    Default = "all",
    Callback = function(value) print("filter", value) end,
})

Autobuilds:Action("Select a feature", function() end)   -- sticky bottom button
Autobuilds:SetActionEnabled(false)
Autobuilds:Search("autobuild")                          -- set the query programmatically
Autobuilds:ScrollToTop()
```

Cards carry a `Tier` (`"free"` / `"premium"`) and are hidden automatically when a pill
filter or the search query excludes them.

## Sections

```lua
local Section = Page:Section({
    Name = "Combat",
    Icon = "⚔",
    Collapsed = false,
})

Section:Collapse(true)
Section:Toggle()
Section:SetName("PvP")
Section:SetVisible(false)
Section:Clear()        -- remove every element
```

Rows declared with `Width = "half"` are packed two per line automatically.

## Components

Every component takes a config table, an optional callback, and returns a handle.

```lua
Section:Toggle({ Name, Description, Icon, Flag, Default, Width, Tooltip }, function(value) end)
Section:Checkbox({ ... })
Section:Slider({ Name, Flag, Min, Max, Default, Step, Decimals, Suffix, Prefix, Ticks }, function(value) end)
Section:Input({ Name, Placeholder, Default, Numeric, MaxLength, Live, SlotWidth }, function(value) end)
Section:Textarea({ Name, Placeholder, Default, Height }, function(value) end)
Section:Keybind({ Name, Default, Flag }, function(down) end)
Section:Button({ Name, Primary, Icon, Confirm, Height }, function() end)
Section:DualButton({ Name, AlternateName }, leftFn, rightFn)
Section:Dropdown({ Name, Options, Default, Multi, Search, MaxHeight, Icon }, function(value) end)
Section:ColorPicker({ Name, Default, Presets, Alpha, Eyedropper, SquareSize }, function(color) end)
Section:ThemePicker({ Name, Themes, Columns, Callback })
Section:Card({ Name, Description, Image, Glyph, Tint, Badge, BadgeColor, Tier, Selected, Pinned }, function(element) end)
Section:Table({ Columns, ColumnWidths, Rows })
Section:Progress({ Name, Default, Description })
Section:Tag({ Tags = { { Text, Color }, "plain" } })
Section:UserRow({ Name, Description, Avatar, Color })
Section:Banner({ Name, Text, Kind, Dismissible })
Section:Label({ Text, Bold, Color, TextSize, Align })
Section:Paragraph({ Title, Text })
Section:Divider()
Section:Space(12)
Section:Image({ Image, Name, Height, Transparency })
```

Dropdown options can be plain values or `{ Text, Value, Description, Icon, Disabled }`.
Cards accept `Image = "rbxassetid://…"` or fall back to a tinted glyph thumbnail.

### Handles

```lua
el:Set(value)            -- also el:Set(value, true) to skip the callback
el:Get()  el:GetValue()
el:OnChanged(fn)
el:SetVisible(false)  el:SetDisabled(true)
el:SetName("new label")  el:SetDescription("new hint")
el:Refresh()            -- re-read the flag and repaint
el:Destroy()
```

Cards add `el:Select(bool)`, `el:IsSelected()`, `el:SetBadge(text, color)`, `el:SetImage(id)`.
Sliders add `el:Set(value)`, dropdowns add `el:SetOptions(list)`, `el:OpenList()`, `el:Close()`,
color pickers add `el:SetColor`, `el:SetAlpha`.

## Flags

A flag is a string key. Components write to it, your logic reads it.

```lua
Argon:GetFlag("aim.fov")            -- 90
Argon:SetFlag("aim.fov", 140)       -- also refreshes the owning widget
Argon:GetFlags()                    -- snapshot table
Argon:OnFlagChanged("aim.fov", function(value) print(value) end)
Window:OnFlagChanged("aim.fov", function(value) end)
```

```lua
game:GetService("RunService").RenderStepped:Connect(function()
    if Argon:GetFlag("aim.enabled") then
        local fov = Argon:GetFlag("aim.fov")
        -- ...
    end
end)
```

## Themes

Built in: **Dark**, **Aqua**, **Serika**, **Rust**, **Legacy**, **Rose**, **Mint**, **Light**.

```lua
Argon:SetTheme("Serika")            -- switch at runtime, live
Argon:SetAccent(Color3.fromRGB(255, 120, 200))
Argon:GetThemeNames()
local palette = Argon:GetTheme()
```

Custom palette (any subset of keys; the rest is inherited from the default dark ramp):

```lua
Argon:RegisterTheme({
    Name = "Vapor",
    Accent = Color3.fromRGB(255, 113, 206),
    Surface = Color3.fromRGB(36, 27, 48),
    Text = Color3.fromRGB(255, 240, 250),
})
Argon:SetTheme("Vapor")
```

`Section:ThemePicker{}` renders the swatch grid from the reference: each card previews
its own palette and the active one is ringed in the accent color.

## Configs

```lua
Argon:SaveConfig("legit")          -- -> Argon/configs/legit.json
Argon:LoadConfig("legit")          -- applies flags, repaints widgets
Argon:GetConfigs()                 -- { "legit", ... }
Argon:DeleteConfig("legit")
Argon:EnableAutoSave("legit", 2)   -- debounce writes on every flag change
```

Color3, `EnumItem`, arrays, booleans, numbers and strings all round-trip through the
bundled JSON encoder. `Argon:BuildConfigPage(window)` drops a complete Settings page
(config name, save/load/delete, theme grid, motion + animation speed) into a window.

## Overlays

```lua
Argon:Notify({
    Kind = "success",              -- info | success | warning | danger | premium
    Title = "Autobuilds",
    Text = "Opening Autobuild Classic",
    Duration = 5,
    Color = Color3.fromRGB(74, 206, 132),
})

Argon:Dialog({
    Title = "Confirm",
    Text = "This cannot be undone.",
    Buttons = { { Text = "Cancel" }, { Text = "OK", Primary = true, Callback = fn } },
})

local toolbar = Argon:Toolbar({
    Corner = "BottomLeft",         -- or TopRight / BottomRight / TopLeft
    Buttons = {
        { Icon = "◱", Tooltip = "Hide UI", Callback = function() Window:Toggle() end },
        { Text = "Close luau.pro", Icon = "✕", Style = "pill", Callback = fn },
    },
})

Argon:Watermark("luau.pro  ·  Argon 2.0.0")
Argon:ShowLoading("Fetching builds…", 1.5)
```

## Keybinds

```lua
local binding = Argon:BindKey(Enum.KeyCode.F5, function(down)
    if down then print("pressed") end
end)
Argon:UnbindKey(binding)
```

## Iris compatibility

```lua
local Iris = Argon.Iris
Iris:Init({ Title = "Menu", Theme = "Legacy" })

Iris:Toggle({ Text = "Enabled", Changed = function(state) print(state) end })
Iris:Slider({ Text = "FOV", Min = 10, Max = 360, Default = 90 })
Iris:Dropdown({ Text = "Hitbox", Values = { "Head", "Torso" }, Default = "Head" })
Iris:Keybind({ Text = "Key", Default = Enum.KeyCode.E })
Iris:ColorPicker({ Text = "Color", Default = Color3.fromRGB(88, 166, 255) })
Iris:Button({ Text = "Apply", Primary = true, Callback = fn })
Iris:Separator()
Iris:Table({ Columns = { "A", "B" }, Rows = { { 1, 2 } } })
```

This is a compatibility veneer, not a reimplementation of Iris internals: it keeps a
cursor over the last opened tab/section and builds real Argon widgets. `Iris.End()`,
`Iris:TabBar()` and `Iris:Tree()` are accepted and are no-ops/aliases so pasted snippets
keep running. Components that Iris scripts read via state tables instead get a handle:
use `:Get()`.

## Executor support

| executor | status |
| --- | --- |
| Wave | tested |
| Delta | tested |
| Fluxus | tested |
| Krnl | tested |
| Synapse X / Xeno | tested (CoreGui fallback path) |
| AWP | expected to work |

`gethui()` → `syn.protect_gui` → CoreGui → PlayerGui is probed in that order, each with
`pcall`. `writefile`/`readfile`/`listfiles`/`makefolder`/`delfile` are optional: without
them, configs are in-memory only and the library says so instead of throwing.

## Lifecycle

```lua
Argon:Unload()      -- disconnect every connection, destroy every instance, clear flags
Argon:IsLoaded()
```

Executing the loader again unloads the previous copy automatically, so re-running a
script never stacks windows. `Argon:Window{...}` instances are independent, but the
palette and flags are global on purpose.

## Layout of the repo

```
Argon.lua                  the library (single file, ~8k lines)
examples/
  basic.lua                smallest useful menu
  feature_menu.lua         full luau.pro-style shell: rail, sidebar, cards, pills, themes
  iris_style.lua           Iris-compatible call style
tests/
  roblox_mock.lua          fake Roblox API (instances, signals, enums, tweens, fs, JSON, task)
  smoke.lua                146 assertions covering every component
  test_argon_lua.py        pytest runner + static checks
README.md
```

## Testing

The library is exercised outside Roblox against a mock of the API surface it touches:

```bash
python3 -m venv .venv
.venv/bin/pip install lupa pytest
.venv/bin/python -m pytest tests -q
```

```
8 passed
```

The smoke suite builds the full shell, drives toggles, checkboxes, slider drags,
dropdown selection and search, key capture, colour changes, theme switching, card
filtering, config save/load, notifications, dialogs, toolbar, keybinds, the Iris layer
and teardown. The mock is a test fixture only — it is never loaded by `Argon.lua`.

## Notes

* Text is never rendered as rich text by default, so config values cannot inject markup.
* All connections and instances are tracked; `Unload` leaves nothing parented or running.
* Layout uses `UDim2` scale + `UIListLayout`/`UIGridLayout`, so it survives resolution
  changes and executor-injected GUI parents.
* The source avoids Luau-only syntax, so the same file can be linted and tested with a
  stock Lua interpreter.
