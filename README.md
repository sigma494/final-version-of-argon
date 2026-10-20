# Argon

A UI library for Roblox executors. One file, no dependencies, no loader chain, no
`loadstring` inside the library. Build a menu in ~15 lines and read every control's
state back with flags.

```lua
local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()

local Window = Argon:Window({ Title = "Argon", Subtitle = "v1.0.0", ToggleKey = Enum.KeyCode.RightShift })

local Tab = Window:Tab({ Name = "Main" })
local Section = Tab:Section({ Name = "Combat" })

Section:Toggle({ Name = "Aimbot", Flag = "aimbot" }, function(on)
    print("aimbot", on)
end)

Section:Slider({ Name = "FOV", Flag = "fov", Min = 10, Max = 360, Default = 90, Suffix = "°" })
Section:Keybind({ Name = "Aim key", Flag = "aimkey", Default = Enum.KeyCode.E })

Window:Notify({ Title = "Argon", Text = "Loaded." })
```

`Argon:GetFlag("fov")` is the value, anywhere in your script. That is the whole API
contract between the menu and your logic.

## Elements

| method | returns | notes |
| --- | --- | --- |
| `Tab:Toggle(config, cb)` | element | animates, `cb(value)` |
| `Tab:Slider(config, cb)` | element | drag or click the bar, `Step`, `Decimals`, `Suffix` |
| `Tab:Dropdown(config, cb)` | element | `Multi = true` for multi-select, `:SetOptions(t)` |
| `Tab:Input(config, cb)` | element | `Numeric = true` coerces to number, `Placeholder` |
| `Tab:Button(config, cb)` | element | `:SetText`, `:SetDisabled` |
| `Tab:ColorPicker(config, cb)` | element | saturation/value square + hue bar + hex box |
| `Tab:Keybind(config, cb)` | element | `cb(true)` on press, `cb(false)` on release, Backspace clears |
| `Tab:Search(config)` | element | emits on every keystroke |
| `Tab:Label`, `Tab:Paragraph`, `Tab:Divider`, `Tab:Space(h)` | element | static content |

Every element handle supports:

```lua
element:Set(value)          -- also :Set(value, true) to skip the callback
element:Get()               -- current value
element:SetVisible(bool)
element:SetDisabled(bool)
element:SetName(text)       -- renamed after creation
element:Destroy()
```

## Window

```lua
local Window = Argon:Window({
    Title = "Argon",
    Subtitle = "build 7",
    Width = 580, Height = 460,            -- optional
    Accent = Color3.fromRGB(88, 166, 255),-- optional
    ToggleKey = Enum.KeyCode.RightShift,  -- optional, nil to disable
    DisplayOrder = 999,                   -- optional
})

Window:Tab({ Name = "Main" })
Window:Notify({ Title = "T", Text = "Body", Duration = 4, Color = Argon.Theme.Success })
Window:SetTitle("Renamed")
Window:SetSubtitle("reloaded")
Window:SetAccent(Color3.fromRGB(255, 90, 120))
Window:SetVisible(true)   Window:Toggle()
Window:Destroy()
```

The window is draggable by its header, minimizable, closable, and remembers its
position only for the session (no file writes unless you save a config).

## Configs

Flags are serializable: booleans, numbers, strings, `Color3`, and arrays.

```lua
Window:SaveConfig("legit")        -- -> Argon/configs/legit.json (writefile)
Window:LoadConfig("legit")        -- reapplies flags and refreshes every widget
Window:GetConfigs()               -- { "legit", ... }
Window:DeleteConfig("legit")
```

Auto-save and auto-load:

```lua
Argon:Window({ Title = "Argon", AutoLoad = "default", AutoSaveTo = "default" })
```

`SaveConfig` needs `writefile` and `makefolder`; `LoadConfig` needs `readfile` and
`isfile`. Executors without filesystem access return `false` and warn instead of
throwing.

## Flags

```lua
Argon:GetFlag("fov")                       -- 90
Argon:SetFlag("fov", 120)                  -- updates the slider and fires listeners
Argon:GetFlags()                           -- snapshot table
Window:OnFlagChanged("fov", function(v) end)
```

## Lifecycle

```lua
Argon:Unload()   -- disconnects every connection, destroys every instance, clears flags
Argon:IsLoaded()
```

Re-executing the library auto-unloads the previous copy, so spamming the execute
button never stacks windows.

## Task scheduler

`Argon.Scheduler` is a tiny sequential task runner if your script wants one:

```lua
local task = Argon.Scheduler:Create({ IgnoreBusy = true })
task:Add("work", function(nextTask) print("running"); nextTask() end, true)
```

## Themes

```lua
Argon.Theme.Accent = Color3.fromRGB(45, 212, 191)   -- or Argon:SetAccent(color)
Argon.Theme.Surface = Color3.fromRGB(23, 25, 32)    -- set before building the window
```

## Executor support

| executor | status |
| --- | --- |
| Wave | tested |
| Delta | tested |
| Fluxus | tested |
| Krnl | tested |
| Synapse X / Xeno | tested (falls back to CoreGui parenting) |
| AWP | expected to work (same API surface) |

`gethui()` / `syn.protect_gui` are used when the executor provides them; otherwise the
ScreenGui parents to CoreGui and finally PlayerGui. Nothing is required to exist.

## Layout

```
Argon.lua                 the entire library
examples/example.lua      runnable demo using every element
tests/roblox_mock.lua     fake Roblox API (dev only, never loaded by the library)
tests/smoke.lua           builds a full UI and asserts behaviour
tests/test_argon_lua.py   pytest runner for the smoke suite
```

## Testing

The library is exercised outside Roblox against a mock of the API it uses:

```bash
python3 -m venv .venv && .venv/bin/pip install lupa pytest
.venv/bin/python -m pytest tests -q
```

The smoke suite builds a window with two tabs, every element type, drives toggles,
slider drags, dropdown selection, key capture, colour changes, config save/load, and
teardown, then asserts ~70 invariants. Running it in an executor is still the real
test — the mock cannot catch rendering differences.

## Notes

* Single file, ~2.7k lines, no `require`, no remote fetch at load time.
* Text is never rendered as rich text by default, so a config value cannot inject markup.
* All connections and instances are tracked; `Unload` leaves nothing running.
* Coordinates come from `UserInputService` + `AbsolutePosition`, so it works at any
  resolution and with executor-injected GUIs.
