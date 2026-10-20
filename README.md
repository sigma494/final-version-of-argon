# Argon

A single-file UI library for Roblox executor scripts. Built around the dark shell from
luau.pro — icon rail, grouped sidebar, feature-card grid, sticky action bar, live theme
switcher — with an Iris-style compatibility layer for scripts that already use Iris.

v3 adds the two shell shapes (a narrow **square** menu and the wide **side** menu whose
sidebar slides in only while the pointer is over the window), the hover/press/selected
states for cards and buttons, and the wizard set: `Steps`, `StatCard`, `FileRow`,
`Callout`, `CardList`, `Footer`.

9,347 lines of plain Lua. No dependencies, no loader chain, no self-fetch, no nested
`loadstring`. Everything below ships in `Argon.lua`.

```lua
local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()

local Window = Argon:Window({
    Title = "luau.pro",
    Subtitle = "v3.0.0",
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
| **Shell** | two layouts (`side` / `square`), hover-driven sidebar, pointer-tracked chrome, draggable + resizable window, icon rail, grouped sidebar (MAIN / OTHER), logo, user card with tag, Light/Dark switch, minimize/close, toggle key |
| **Pages** | header with subtitle ("8 Features · synced 2m ago"), search field, filter pills (All/Free/Premium), scrolling sections, sticky action bar |
| **Sections** | collapsible cards with icon, element counter badge, header controls, two-column row packing |
| **Inputs** | Toggle, Checkbox, Slider (drag + editable value), Input, Textarea, Keybind, Dropdown (single/multi/search), ColorPicker (SV + hue + alpha + hex + presets), ThemePicker |
| **Content** | Card (thumbnail + status pill, hover/press/selected states), Banner, Table, Progress, Tag, UserRow, Label, Paragraph, Divider, Space, Image |
| **Wizard** | Steps (segmented progress), StatCard (labelled rows + meter + ⋯ menu), FileRow (Browse field), Callout (checkbox note box), CardList (selectable rows), Page:Footer (Back + Primary) |
| **Overlays** | toast notifications (kinds, actions), modal dialogs, tooltips, floating toolbar, watermark, loading bar |
| **State** | flags, listeners, JSON config round-trip (Color3/EnumItem/arrays), autosave, `BuildConfigPage` |
| **Extras** | global keybind registry, Iris compatibility layer, theme registration, safe unload |

## Install

Grab it from the repo:

```bash
curl -O https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua
```

Or straight from a script:

```lua
local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()
```

`main` carries the library, so that URL is the one to paste into a script. Until this PR
merges, `main` serves v2.0.0 and v3.0.0 lives on the session branch — swap the ref if you
want to try the new shell early:

```lua
local Argon = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/sigma494/final-version-of-argon/arena/12fe7d4f-final-version-of-argon/Argon.lua"
))()
```

You can also skip the network entirely: save the file and read it back.

```lua
local Argon = loadstring(readfile("Argon.lua"))()   -- or paste the source inline
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
    Layout = "side",                 -- "side" (rail+sidebar+page) or "square" (rail+page)
    HoverOpen = true,                -- sidebar slides in only while the pointer is inside
    CollapseDelay = 0.14,            -- grace period before collapsing (s: close instantly)
    RailOnly = true,                 -- collapse to the rail when no page is open
    AutoClosePage = true,            -- the page header X closes the pane instead of jumping to page 1
    Width = 660, Height = 520,       -- Width describes the *expanded* window
    ThemeSwitch = true,              -- Light/Dark pill in the sidebar
    DisplayOrder = 100,
    AutoLoad = "default",            -- load a config on build
    AutoSaveTo = "default",          -- persist flags as they change
})
```

Methods: `Page`, `SelectPage`, `ClosePage`, `GetPage`, `SetTitle`, `SetSubtitle`, `SetUser`,
`SetTheme`, `SetAccent`, `SetMinimized`, `SetVisible`, `Toggle`, `Refresh`, `Notify`,
`Dialog`, `OnFlagChanged`, `SetLayout`, `SetRailOnly`, `SetHovered`, `UpdateChrome`,
`CurrentWidth`, `PaneWidth`, `Destroy`.

### Shell shapes

`Layout = "side"` reproduces the reference exactly. Two booleans drive everything —
whether the pointer is over the window, and whether a page is open:

| pointer over window | page open | result |
| --- | --- | --- |
| no | yes | rail + page (sidebar collapsed) |
| yes | yes | rail + sidebar + page |
| no | no | rail alone |
| yes | no | rail + sidebar (nav only, no pane) |

The width grows and shrinks around a still left edge, so the rail never slides when you
reach for the menu. `HoverOpen = false` pins the sidebar open (v2 behaviour); on touch
devices hover is ignored automatically.

`Layout = "square"` builds one narrow column — rail plus page, no sidebar at all — for a
~380px menu:

```lua
local Square = Argon:Window({ Title = "Argon", Layout = "square", Width = 380, Height = 560 })
Square:SetLayout("side")     -- switch live, no rebuild
Square:SetRailOnly(true)     -- collapse to the icon rail
Square:SetHovered(true)      -- force the sidebar open (tests, scripts, keybinds)
Square:ClosePage()            -- hide the pane, keep the rail
Square:SetRailHideVisible(true)  -- the ⏋ control at the bottom of the rail
```

Collapsed to the rail the window is only ~52px wide, so the sidebar's logo drag handle and
the corner controls are clipped away. The rail therefore carries both jobs: pressing its
background moves the window (presses that start on a rail button do not, or clicking a page
would drag the shell), and `RailHide` at the bottom hides it. `ToggleKey` still works either
way.
```

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
Autobuilds:SetActionEnabled(false)                      -- dimmed, and clicks are refused

-- Two-button footer for wizards: ghost Back + accent Primary.
Autobuilds:Footer({
    Back = true,
    Primary = "Choose a build file",
    Disabled = true,
    OnBack = function() end,
    OnPrimary = function() end,
})
Autobuilds:SetPrimaryText("Continue")
Autobuilds:SetPrimaryEnabled(true)
Autobuilds:SetBackVisible(false)
Autobuilds:Search("autobuild")                          -- set the query programmatically
Autobuilds:ScrollToTop()
```

Cards carry a `Tier` (`"free"` / `"premium"`) and are hidden automatically when a pill
filter or the search query excludes them. Each card has four states, all theme derived:
idle, hovered (lighter fill + brighter hairline), pressed, and selected (accent ring,
2px stroke).

### Wizard set

The reference's "Autobuild Classic" screen is a 4-step wizard, so the library ships the
pieces for it. Every one of them is also available directly on a `Page` (`Page:Steps`,
`Page:StatCard`, …), which files them into an implicit section:

```lua
local Setup = Page:Section({ Name = "Setup" })

local Steps = Setup:Steps({ Total = 4, Current = 1, Caption = "Step 1 of 4 · Choose a build file" })
Steps:Next("Step 2 of 4 · Check blocks")
Steps:Prev()
Steps:SetCurrent(4)

local BuildFile = Setup:FileRow({
    Name = "Build file",
    Placeholder = "Choose a .Build file",
    Button = "Browse",
    OnBrowse = function(row) row:SetValue("plot_3.build") end,
})

local Buildability = Setup:StatCard({
    Name = "Buildability",
    Rows = {
        { Label = "You own 0 of 1 required blocks", Meter = true, Percent = 0 },
        { Label = "1 blocks · 0 types", Value = "—" },
    },
    OnMenu = function() end,      -- the "⋯" button on the card
})
Buildability:SetMeter(1, 100)
Buildability:SetRow(2, "12 blocks · 4 types")

local Infinite = Setup:Callout({
    Kind = "check",               -- "check" | "info" | "warn" | "danger"
    Name = "Infinite Blocks",
    Text = "Reuse scalable blocks without limit.",
    Flag = "wizard.infiniteBlocks",
})
Infinite:GetValue()
```

`CardList` is the selectable feature list — items without an `Image` get a placeholder
tile so rows never change height:

```lua
local Items = Setup:CardList({
    Select = true,                      -- single-select ring; false for plain rows
    PlaceholderGlyph = "▦",
    Items = {
        { Name = "Test 1", Text = "test" },
        { Name = "Test 2", Text = "test", Badge = "Soon" },
    },
    OnSelect = function(item, index) end,
    OnOpen = function(item) end,        -- e.g. open a page for that item
})

Items:GetSelected()        -- the item table, or nil
Items:SelectIndex(2)
Items:SetItems({})         -- rebuild
Items:Filter("test")       -- hide non-matching rows
```

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
Argon.lua                  the library (single file, 9,347 lines)
examples/
  basic.lua                smallest useful menu
  feature_menu.lua         full luau.pro-style shell: rail, sidebar, cards, pills, themes
  wizard.lua               square + side windows, selectable card list, 4-step wizard
  iris_style.lua           Iris-compatible call style
tests/
  roblox_mock.lua          fake Roblox API (instances, signals, enums, tweens, fs, JSON, task)
  smoke.lua                146 assertions covering every component
  chrome.lua               82 assertions on the hover / layout state machine and wizard set
  docs_api.lua             137 assertions running every snippet in this README
  test_argon_lua.py        pytest runner + static checks (self-containment, size, no markers)
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
12 passed
```

Three Lua suites run inside that: `smoke.lua` (146 assertions on components),
`chrome.lua` (82 on the hover/layout state machine and the wizard set) and `docs_api.lua`
(137, which executes every snippet in this file, so the docs cannot drift). Static checks in
the same run assert the file is self-contained (no `require`, no `HttpGet`, no nested
`loadstring`), at least 8,000 lines, and free of placeholders.

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
* Hover chrome is a pointer-rect test against the window bounds, not per-child
  `MouseEnter`. Per-child events strand the flag whenever a panel resizes under the cursor,
  which is what makes a collapsing sidebar stick half-open. Touch devices ignore it and pin
  the sidebar open, because there is no hover there.
* Roblox cannot backdrop-blur GUI, draw SVG icons, box-shadow a frame, round individual
  corners or letter-space text. Everything here is therefore built from translucent fills,
  1px `UIStroke` hairlines and glyph icons — a Figma glass mock can be matched in structure
  and tokens, but a real blur layer needs a pre-blurred wallpaper asset, and shadows need a
  9-slice image. That is a platform limit, not a shortcut.
