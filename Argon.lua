--[[
================================================================================
    Argon — a component library for Roblox executor scripts.

    Version 2.0.0
    Single file. No dependencies. No self-fetch. No nested loadstring.
    Written in plain Lua 5.1-compatible syntax so it runs on Luau and everywhere
    else without a transpile step.

    --------------------------------------------------------------------------
    QUICK START
    --------------------------------------------------------------------------

        local Argon = loadstring(game:HttpGet(".../Argon.lua"))()

        local Window = Argon:Window({
            Title = "luau.pro",
            Subtitle = "v2.0.0",
            User = { Name = "farmerjoe", Tag = "Premium" },
            ToggleKey = Enum.KeyCode.RightShift,
            Theme = "Aqua",
        })

        local Page = Window:Page({ Name = "Autobuilds", Icon = "▤" })
        local Section = Page:Section({ Name = "Features" })

        Section:Toggle({ Name = "Aimbot", Flag = "aimbot" }, function(on) end)

        Page:Action("Select a feature", function() end)

    --------------------------------------------------------------------------
    API SURFACE
    --------------------------------------------------------------------------

    Argon:Window(config)                 window with rail + sidebar + content
    Argon:Notify(config)                 toast notification
    Argon:Dialog(config)                 modal dialog with buttons
    Argon:Toolbar(config)                floating circular icon toolbar
    Argon:Watermark(text)                corner watermark
    Argon:SetTheme(name)                 switch palette at runtime
    Argon:GetTheme()                     current palette table
    Argon:SetAccent(Color3)              override the accent of the current theme
    Argon:GetFlag(flag)                  read a flag
    Argon:SetFlag(flag, value)           write a flag (updates widgets)
    Argon:SaveConfig(name)               persist all flags to disk
    Argon:LoadConfig(name)               apply a saved config
    Argon:GetConfigs()                   list saved configs
    Argon:DeleteConfig(name)             delete a config
    Argon:Unload()                       destroy everything, disconnect everything

    Window:Page(config)                  add a page
    Window:SelectPage(page)              navigate
    Window:Section?                      (sections belong to pages)
    Window:Notify(config)                convenience
    Window:SetUser({ Name, Tag, Avatar })
    Window:SetTitle(text)  SetSubtitle(text)
    Window:SetTheme(name)  SetAccent(color)
    Window:SetVisible(bool)  Toggle()  Destroy()

    Page:Section(config)                 add a collapsible section
    Page:Pills(config)                   filter pill row (All / Free / Premium)
    Page:Search(config)                  search field bound to a flag
    Page:Action(text, callback)          sticky bottom action button
    Page:SetVisible(bool)  Refresh()  Destroy()

    Section:Toggle(config, cb)           on/off switch
    Section:Checkbox(config, cb)         square checkbox
    Section:Slider(config, cb)           numeric slider with editable value
    Section:Dropdown(config, cb)         single or multi select, searchable
    Section:Input(config, cb)            single line text
    Section:Textarea(config, cb)         multi line text
    Section:Keybind(config, cb)          key picker, hold detection
    Section:Button(config, cb)           full width button
    Section:DualButton(config, cb1, cb2) split two-action button
    Section:ColorPicker(config, cb)      SV square + hue + alpha + hex + eyedropper
    Section:ThemePicker(config)          theme grid picker
    Section:Card(config, cb)             media card with badge and status pill
    Section:Label(config)                one line label
    Section:Paragraph(config)            wrapped text block
    Section:Divider()                    horizontal rule
    Section:Space(height)                vertical gap
    Section:Progress(config)             progress bar with label
    Section:Tag(config)                  inline tag/badge row
    Section:UserRow(config)              avatar + name + role row
    Section:Table(config)                simple two/three column table
    Section:Collapse(bool)               collapse the whole section
    Section:SetName(text)  SetVisible(bool)  UpdateOrder()

    Every element returns a handle:

        el:Set(value [, silent])   el:Get()   el:GetValue()
        el:SetVisible(bool)        el:SetDisabled(bool)
        el:SetName(text)           el:SetDescription(text)
        el:OnChanged(cb)           el:Destroy()

    --------------------------------------------------------------------------
    THEMING
    --------------------------------------------------------------------------

    Built-in palettes (all in the same near-black shell, different accents and
    surface ramps): Dark, Aqua, Serika, Rust, Legacy, Rose, Mint, Light.

    Match the reference look:

        Argon:SetTheme("Aqua")          -- teal accent, luau.pro-ish
        Argon:SetTheme("Serika")        -- yellow
        Argon:SetTheme("Rust")          -- orange
        Argon:SetTheme("Legacy")        -- purple
        Argon:SetTheme("Light")         -- light sidebar, dark content optional

    Per-window override:

        Window:SetTheme("Serika")
        Window:SetAccent(Color3.fromRGB(255, 120, 200))

    Custom palette:

        Argon.Themes.MyTheme = Argon.ThemeTemplate({
            Accent = Color3.fromRGB(0, 255, 170),
            Background = Color3.fromRGB(10, 12, 16),
        })
        Argon:SetTheme("MyTheme")

    --------------------------------------------------------------------------
    FLAGS AND CONFIGS
    --------------------------------------------------------------------------

    A flag is a string path to a value. Components write to it automatically.
    You never read widget state directly:

        Argon:GetFlag("aimbot.fov")
        Argon:SetFlag("aimbot.fov", 140)

    Saving is handled by the library. Color3, EnumItem, arrays, booleans, numbers
    and strings all round-trip through JSON:

        Argon:SaveConfig("legit")
        Argon:LoadConfig("legit")

    --------------------------------------------------------------------------
    IRIS COMPATIBILITY
    --------------------------------------------------------------------------

    If your script already uses Iris, the bundled compatibility layer maps its
    immediate-mode calls onto Argon's retained-mode widgets:

        Argon.Iris.Toggle{ Text = "Enabled", Changed = function(state) end }

    See the IRIS LAYER section near the bottom of this file.

    --------------------------------------------------------------------------
    THREADING / LIFECYCLE
    --------------------------------------------------------------------------

    All connections and instances are owned and tracked. Argon:Unload() leaves
    nothing connected and nothing parented. Loading the library twice unloads the
    first copy automatically, so spamming Execute cannot stack windows.

    Nothing in this file requires a specific executor; every optional capability
    (gethui, syn.protect_gui, writefile, ...) is probed with pcall and degrades.
================================================================================
]]

-- ============================================================================
-- 0. GLOBAL SHIELD AND SINGLETON
-- ============================================================================

local GENV = (typeof and typeof(getgenv) == "function" and getgenv()) or _G

if GENV.Argon and type(GENV.Argon) == "table" and type(GENV.Argon.Unload) == "function" then
    pcall(function()
        GENV.Argon:Unload()
    end)
end

-- ============================================================================
-- 1. SERVICES
-- ============================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local ContentProvider = game:GetService("ContentProvider")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- 2. LIBRARY ROOT
-- ============================================================================

local Argon = {
    Name = "Argon",
    Version = "3.0.0",
    Build = "stable",

    -- runtime state
    Flags = {},
    Connections = {},
    Instances = {},
    Windows = {},
    Notifications = {},
    Dialogs = {},
    Tooltips = {},
    ThemeAppliers = {},
    Unloaded = false,
    Debug = false,

    -- configuration
    Config = {
        Folder = "Argon",
        ConfigFolder = "Argon/configs",
        DefaultConfig = "default",
        AutoSave = false,
        AutoSaveDelay = 1.5,
        NotificationDuration = 4,
        NotificationLimit = 6,
        TooltipDelay = 0.35,
        AnimationSpeed = 1,
        ReduceMotion = false,
    },
}

-- ============================================================================
-- 3. LUA COMPATIBILITY SHIMS
-- ============================================================================

local unpack = unpack or table.unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function isCallable(value)
    return type(value) == "function" or (type(value) == "table" and type(value.__call) == "function")
end

local function isArray(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" then
            return false
        end
        count = count + 1
    end
    for index in ipairs(value) do
        if index > count then
            return false
        end
    end
    return count == #value
end

local function shallowCopy(source)
    local out = {}
    for key, value in pairs(source or {}) do
        out[key] = value
    end
    return out
end

local function deepCopy(source, seen)
    if type(source) ~= "table" then
        return source
    end
    seen = seen or {}
    if seen[source] then
        return seen[source]
    end
    local out = {}
    seen[source] = out
    for key, value in pairs(source) do
        out[deepCopy(key, seen)] = deepCopy(value, seen)
    end
    return out
end

local function merge(target, ...)
    for _, source in ipairs({ ... }) do
        if type(source) == "table" then
            for key, value in pairs(source) do
                target[key] = value
            end
        end
    end
    return target
end

local function typed(value)
    if typeof then
        return typeof(value)
    end
    local ok, result = pcall(function()
        return typeof(value)
    end)
    if ok then
        return result
    end
    return type(value)
end

local function isColor(value)
    return typed(value) == "Color3"
end

local function isEnumItem(value)
    return typed(value) == "EnumItem"
end

local function isInstance(value)
    return typed(value) == "Instance"
end

local function isNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- ============================================================================
-- 4. MATH AND STRING UTILITIES
-- ============================================================================

local Math = {}

function Math.round(value, step)
    step = step or 1
    if step <= 0 then
        return value
    end
    if value >= 0 then
        return math.floor(value / step + 0.5) * step
    end
    return math.ceil(value / step - 0.5) * step
end

function Math.floorTo(value, step)
    step = step or 1
    if step <= 0 then
        return value
    end
    return math.floor(value / step) * step
end

function Math.ceilTo(value, step)
    step = step or 1
    if step <= 0 then
        return value
    end
    return math.ceil(value / step) * step
end

function Math.clamp(value, minimum, maximum)
    if minimum and value < minimum then
        return minimum
    end
    if maximum and value > maximum then
        return maximum
    end
    return value
end

function Math.lerp(a, b, alpha)
    return a + (b - a) * alpha
end

function Math.inverseLerp(a, b, value)
    if b == a then
        return 0
    end
    return (value - a) / (b - a)
end

function Math.map(value, inMin, inMax, outMin, outMax)
    return Math.lerp(outMin, outMax, Math.clamp(Math.inverseLerp(inMin, inMax, value), 0, 1))
end

function Math.sign(value)
    if value == 0 then
        return 0
    end
    return value > 0 and 1 or -1
end

function Math.snap(value, step)
    return Math.round(value, step)
end

function Math.decimals(value, places)
    places = places or 0
    local multiplier = 10 ^ places
    return math.floor(value * multiplier + 0.5) / multiplier
end

function Math.wrap(value, minimum, maximum)
    local range = maximum - minimum
    if range <= 0 then
        return minimum
    end
    local result = value
    while result < minimum do
        result = result + range
    end
    while result >= maximum do
        result = result - range
    end
    return result
end

function Math.approach(current, target, delta)
    if current < target then
        return math.min(current + delta, target)
    end
    return math.max(current - delta, target)
end

function Math.percent(value, total)
    if total == 0 then
        return 0
    end
    return value / total * 100
end

local String = {}

function String.trim(text)
    text = tostring(text or "")
    return (text:gsub("^%s*(.-)%s*$", "%1"))
end

function String.split(text, separator)
    text = tostring(text or "")
    local out = {}
    if separator == nil or separator == "" then
        for index = 1, #text do
            out[#out + 1] = text:sub(index, index)
        end
        return out
    end
    local position = 1
    while true do
        local startIndex, endIndex = text:find(separator, position, true)
        if not startIndex then
            out[#out + 1] = text:sub(position)
            break
        end
        out[#out + 1] = text:sub(position, startIndex - 1)
        position = endIndex + 1
    end
    return out
end

function String.startsWith(text, prefix)
    return text:sub(1, #prefix) == prefix
end

function String.endsWith(text, suffix)
    return suffix == "" or text:sub(-#suffix) == suffix
end

function String.capitalize(text)
    text = tostring(text or "")
    if text == "" then
        return text
    end
    return text:sub(1, 1):upper() .. text:sub(2)
end

function String.padLeft(text, width, fill)
    text = tostring(text)
    fill = fill or " "
    while #text < width do
        text = fill .. text
    end
    return text
end

function String.padRight(text, width, fill)
    text = tostring(text)
    fill = fill or " "
    while #text < width do
        text = text .. fill
    end
    return text
end

function String.truncate(text, limit)
    text = tostring(text or "")
    if #text <= limit then
        return text
    end
    return text:sub(1, math.max(limit - 1, 0)) .. "…"
end

function String.formatNumber(value, places)
    if type(value) ~= "number" then
        return tostring(value)
    end
    places = places or 0
    if places > 0 then
        return string.format("%." .. places .. "f", value)
    end
    if value % 1 == 0 then
        return tostring(math.floor(value))
    end
    return string.format("%.2f", value)
end

function String.formatCompact(value)
    local absolute = math.abs(value)
    if absolute >= 1e9 then
        return string.format("%.1fB", value / 1e9)
    elseif absolute >= 1e6 then
        return string.format("%.1fM", value / 1e6)
    elseif absolute >= 1e3 then
        return string.format("%.1fk", value / 1e3)
    end
    return String.formatNumber(value, absolute < 10 and 1 or 0)
end

function String.commas(value)
    local formatted = tostring(math.floor(tonumber(value) or 0))
    local out = formatted:reverse():gsub("(%d%d%d)", "%1,")
    out = out:reverse()
    if out:sub(1, 1) == "," then
        out = out:sub(2)
    end
    return out
end

function String.timeAgo(timestamp)
    if not timestamp then
        return "never"
    end
    local delta = os.time() - timestamp
    if delta < 0 then
        delta = 0
    end
    if delta < 60 then
        return tostring(math.floor(delta)) .. "s ago"
    elseif delta < 3600 then
        return tostring(math.floor(delta / 60)) .. "m ago"
    elseif delta < 86400 then
        return tostring(math.floor(delta / 3600)) .. "h ago"
    end
    return tostring(math.floor(delta / 86400)) .. "d ago"
end

function String.uuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (template:gsub("[xy]", function(char)
        local value = math.random(0, 15)
        if char == "x" then
            return string.format("%x", value)
        end
        return string.format("%x", (value % 4) + 8)
    end))
end

local function assertType(value, expected, name)
    if type(value) ~= expected then
        error(string.format("Argon: %s must be a %s (got %s)", name or "value", expected, type(value)), 3)
    end
    return value
end

local function warnOnce(message, bucket)
    bucket = bucket or "general"
    Argon._warnedBuckets = Argon._warnedBuckets or {}
    if Argon._warnedBuckets[bucket] then
        return
    end
    Argon._warnedBuckets[bucket] = true
    warn("[Argon] " .. tostring(message))
end

local function debugLog(...)
    if not Argon.Debug then
        return
    end
    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    warn("[Argon:debug] " .. table.concat(parts, " "))
end

-- ============================================================================
-- 5. COLOR UTILITIES
-- ============================================================================

local Color = {}

function Color.new(r, g, b)
    return Color3.fromRGB(
        Math.round(Math.clamp(r, 0, 255)),
        Math.round(Math.clamp(g, 0, 255)),
        Math.round(Math.clamp(b, 0, 255))
    )
end

function Color.hex(hex)
    local cleaned = tostring(hex or ""):gsub("#", ""):gsub("%s", "")
    if #cleaned == 3 then
        cleaned = cleaned:sub(1, 1):rep(2) .. cleaned:sub(2, 2):rep(2) .. cleaned:sub(3, 3):rep(2)
    end
    if #cleaned ~= 6 or cleaned:match("^%x+$") == nil then
        return nil
    end
    return Color3.fromRGB(
        tonumber(cleaned:sub(1, 2), 16),
        tonumber(cleaned:sub(3, 4), 16),
        tonumber(cleaned:sub(5, 6), 16)
    )
end

function Color.toHex(color)
    if not isColor(color) then
        return "000000"
    end
    return string.format(
        "%02X%02X%02X",
        Math.round(Math.clamp(color.R, 0, 1) * 255),
        Math.round(Math.clamp(color.G, 0, 1) * 255),
        Math.round(Math.clamp(color.B, 0, 1) * 255)
    )
end

function Color.toRgbString(color)
    return string.format(
        "%d, %d, %d",
        Math.round(color.R * 255),
        Math.round(color.G * 255),
        Math.round(color.B * 255)
    )
end

function Color.hsvToRgb(hue, saturation, value)
    hue = hue % 1
    local index = math.floor(hue * 6)
    local fraction = hue * 6 - index
    local p = value * (1 - saturation)
    local q = value * (1 - fraction * saturation)
    local t = value * (1 - (1 - fraction) * saturation)
    local r, g, b
    if index == 0 then
        r, g, b = value, t, p
    elseif index == 1 then
        r, g, b = q, value, p
    elseif index == 2 then
        r, g, b = p, value, t
    elseif index == 3 then
        r, g, b = p, q, value
    elseif index == 4 then
        r, g, b = t, p, value
    else
        r, g, b = value, p, q
    end
    return Color3.new(r, g, b)
end

function Color.rgbToHsv(color)
    local r, g, b = color.R, color.G, color.B
    local maximum = math.max(r, g, b)
    local minimum = math.min(r, g, b)
    local delta = maximum - minimum
    local hue, saturation, value

    value = maximum
    saturation = maximum == 0 and 0 or delta / maximum

    if delta == 0 then
        hue = 0
    elseif maximum == r then
        hue = ((g - b) / delta) % 6
    elseif maximum == g then
        hue = (b - r) / delta + 2
    else
        hue = (r - g) / delta + 4
    end

    return hue / 6, saturation, value
end

function Color.lerp(a, b, alpha)
    alpha = Math.clamp(alpha, 0, 1)
    return Color3.new(
        a.R + (b.R - a.R) * alpha,
        a.G + (b.G - a.G) * alpha,
        a.B + (b.B - a.B) * alpha
    )
end

function Color.darken(color, amount)
    amount = amount or 0.2
    return Color3.new(
        Math.clamp(color.R * (1 - amount), 0, 1),
        Math.clamp(color.G * (1 - amount), 0, 1),
        Math.clamp(color.B * (1 - amount), 0, 1)
    )
end

function Color.lighten(color, amount)
    amount = amount or 0.2
    return Color3.new(
        Math.clamp(color.R + (1 - color.R) * amount, 0, 1),
        Math.clamp(color.G + (1 - color.G) * amount, 0, 1),
        Math.clamp(color.B + (1 - color.B) * amount, 0, 1)
    )
end

function Color.luminance(color)
    return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

function Color.readableOn(color, darkColor, lightColor)
    if Color.luminance(color) > 0.55 then
        return darkColor or Color3.fromRGB(10, 11, 14)
    end
    return lightColor or Color3.fromRGB(245, 247, 250)
end

function Color.withTransparency(color, transparency)
    return color, transparency
end

function Color.invert(color)
    return Color3.new(1 - color.R, 1 - color.G, 1 - color.B)
end

function Color.average(a, b)
    return Color3.new((a.R + b.R) / 2, (a.G + b.G) / 2, (a.B + b.B) / 2)
end

function Color.isDark(color)
    return Color.luminance(color) < 0.5
end

-- ============================================================================
-- 6. CONNECTION AND INSTANCE MANAGEMENT
-- ============================================================================

local Connections = Argon.Connections
local Instances = Argon.Instances

local function track(instance)
    table.insert(Instances, instance)
    return instance
end

local function Connect(signal, callback)
    if not signal then
        return nil
    end
    local connection = signal:Connect(function(...)
        if Argon.Unloaded then
            return
        end
        local results = pack(pcall(callback, ...))
        if not results[1] then
            warn("[Argon] connection error: " .. tostring(results[2]))
            if Argon.Debug then
                print(debug.traceback())
            end
        end
    end)
    table.insert(Connections, connection)
    return connection
end

local function Disconnect(connection)
    if not connection then
        return
    end
    pcall(function()
        connection:Disconnect()
    end)
    for index, existing in ipairs(Connections) do
        if existing == connection then
            table.remove(Connections, index)
            break
        end
    end
end

local function New(className, properties, children)
    local instance = Instance.new(className)

    for key, value in pairs(properties or {}) do
        if key ~= "Parent" and value ~= nil then
            local ok = pcall(function()
                instance[key] = value
            end)
            if not ok then
                debugLog("failed to set", key, "on", className)
            end
        end
    end

    for _, child in ipairs(children or {}) do
        if child then
            child.Parent = instance
        end
    end

    if properties and properties.Parent then
        instance.Parent = properties.Parent
    end

    track(instance)
    return instance
end

local function DestroyInstance(instance)
    if not instance then
        return
    end
    pcall(function()
        instance:Destroy()
    end)
    for index, existing in ipairs(Instances) do
        if existing == instance then
            table.remove(Instances, index)
            break
        end
    end
end

-- ============================================================================
-- 7. ANIMATION
-- ============================================================================

local Animation = {
    Active = {},
    Speed = 1,
}

local EasingStyle = Enum.EasingStyle
local EasingDirection = Enum.EasingDirection

local function animate(instance, properties, duration, style, direction, onComplete)
    if not instance or not instance.Parent then
        return nil
    end

    if Argon.Config.ReduceMotion then
        for key, value in pairs(properties) do
            pcall(function()
                instance[key] = value
            end)
        end
        if onComplete then
            onComplete()
        end
        return nil
    end

    duration = (duration or 0.16) / (Argon.Config.AnimationSpeed * Animation.Speed)
    local info = TweenInfo.new(
        duration,
        style or EasingStyle.Quad,
        direction or EasingDirection.Out
    )
    local tween = TweenService:Create(instance, info, properties)
    tween:Play()
    if onComplete then
        task.delay(duration, function()
            if not Argon.Unloaded then
                pcall(onComplete)
            end
        end)
    end
    return tween
end

local function animateColor(instance, property, color, duration)
    if not instance then
        return
    end
    local properties = {}
    properties[property] = color
    return animate(instance, properties, duration or 0.16)
end

-- ============================================================================
-- 8. GUI HOST RESOLUTION
-- ============================================================================

local function resolveGuiParent()
    local okHui, hui = pcall(function()
        if gethui then
            return gethui()
        end
        return nil
    end)
    if okHui and hui then
        return hui
    end

    local okCore, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and coreGui then
        return coreGui
    end

    local okPlayer, playerGui = pcall(function()
        return LocalPlayer:WaitForChild("PlayerGui")
    end)
    if okPlayer and playerGui then
        return playerGui
    end

    return nil
end

local GUI_PARENT = resolveGuiParent()

local function createScreenGui(name, displayOrder, ignoreInset)
    local gui = New("ScreenGui", {
        Name = name,
        ResetOnSpawn = false,
        IgnoreGuiInset = ignoreInset ~= false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = displayOrder or 100,
    })

    gui.Parent = GUI_PARENT

    if syn and syn.protect_gui then
        pcall(syn.protect_gui, gui)
    end
    if protectgui then
        pcall(protectgui, gui)
    end

    return gui
end

-- ============================================================================
-- 9. PRIMITIVE BUILDERS
-- ============================================================================
-- These return bare Instances. Every component below composes them, which keeps
-- the component code short and makes restyling a single-file change.

local UI = {}

function UI.corner(radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = radius or UDim.new(0, 8)
    return corner
end

function UI.stroke(color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Color3.fromRGB(45, 48, 58)
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    return stroke
end

function UI.padding(top, right, bottom, left)
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, tonumber(top) or 0)
    padding.PaddingRight = UDim.new(0, tonumber(right) or tonumber(top) or 0)
    padding.PaddingBottom = UDim.new(0, tonumber(bottom) or tonumber(top) or 0)
    padding.PaddingLeft = UDim.new(0, tonumber(left) or tonumber(right) or tonumber(top) or 0)
    return padding
end

function UI.listLayout(padding, horizontal, alignment)
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, padding or 0)
    if horizontal then
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.HorizontalAlignment = alignment or Enum.HorizontalAlignment.Left
    else
        layout.VerticalAlignment = alignment or Enum.VerticalAlignment.Top
    end
    return layout
end

function UI.gridLayout(cellSize, cellPadding)
    local layout = Instance.new("UIGridLayout")
    layout.CellSize = cellSize or UDim2.new(0, 100, 0, 30)
    layout.CellPadding = cellPadding or UDim2.new(0, 8, 0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    return layout
end

function UI.aspectRatio(ratio)
    local aspect = Instance.new("UIAspectRatioConstraint")
    aspect.AspectRatio = ratio or 1
    aspect.AspectType = Enum.AspectType.FitWithinMaxSize
    return aspect
end

function UI.sizeConstraint(mode)
    local constraint = Instance.new("UISizeConstraint")
    if mode == "min" then
        constraint.MinSize = Vector2.new(0, 0)
    end
    return constraint
end

function UI.gradient(colorA, colorB, rotation, transparencyA, transparencyB)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new(colorA, colorB)
    gradient.Rotation = rotation or 0
    if transparencyA ~= nil then
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, transparencyA),
            NumberSequenceKeypoint.new(1, transparencyB or transparencyA),
        })
    end
    return gradient
end

function UI.frame(properties, children)
    local defaults = {
        BackgroundColor3 = Argon.Theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
    }
    return New("Frame", merge(defaults, properties), children)
end

function UI.transparent(properties, children)
    return New("Frame", merge({
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, properties), children)
end

function UI.label(properties)
    local defaults = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        TextColor3 = Argon.Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        RichText = false,
        Text = "",
    }
    return New("TextLabel", merge(defaults, properties))
end

function UI.button(properties)
    local defaults = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Gotham,
        TextColor3 = Argon.Theme.Text,
        TextSize = 13,
        Text = "",
        ClipsDescendants = true,
    }
    return New("TextButton", merge(defaults, properties))
end

function UI.textBox(properties)
    local defaults = {
        BackgroundColor3 = Argon.Theme.SurfaceHigh,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        TextColor3 = Argon.Theme.Text,
        TextSize = 12,
        Text = "",
        PlaceholderText = "",
        PlaceholderColor3 = Argon.Theme.TextDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ClipsDescendants = true,
        MultiLine = false,
    }
    return New("TextBox", merge(defaults, properties))
end

function UI.image(properties)
    local defaults = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ImageTransparency = 0,
        ScaleType = Enum.ScaleType.Crop,
    }
    return New("ImageLabel", merge(defaults, properties))
end

function UI.imageButton(properties)
    local defaults = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        ImageTransparency = 0,
        ScaleType = Enum.ScaleType.Crop,
    }
    return New("ImageButton", merge(defaults, properties))
end

function UI.scroller(properties, children)
    local defaults = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Argon.Theme.StrokeLight,
        ScrollBarImageTransparency = 0.35,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ClipsDescendants = true,
    }
    return New("ScrollingFrame", merge(defaults, properties), children)
end

-- A rounded icon-ish glyph label. Executors cannot rely on image assets, so
-- glyphs are the default and images are opt-in.
function UI.glyph(text, size, color, properties)
    return UI.label(merge({
        Text = text,
        TextSize = size or 16,
        TextColor3 = color or Argon.Theme.TextMuted,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, properties))
end

function UI.hline(parent, color, transparency)
    return UI.frame({
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = color or Argon.Theme.Stroke,
        BackgroundTransparency = transparency or 0,
        BorderSizePixel = 0,
    })
end

function UI.vline(parent, color, transparency)
    return UI.frame({
        Parent = parent,
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = color or Argon.Theme.Stroke,
        BackgroundTransparency = transparency or 0,
        BorderSizePixel = 0,
    })
end

function UI.dot(parent, size, color)
    local dot = UI.frame({
        Parent = parent,
        Size = UDim2.new(0, size or 6, 0, size or 6),
        BackgroundColor3 = color or Argon.Theme.Success,
        BorderSizePixel = 0,
    })
    UI.corner(UDim.new(1, 0)).Parent = dot
    return dot
end

function UI.badge(text, color, textColor, properties)
    properties = properties or {}
    local badge = UI.frame({
        Size = UDim2.new(0, properties.Width or 0, 0, properties.Height or 18),
        AutomaticSize = properties.Width and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
        BackgroundColor3 = color or Argon.Theme.Accent,
        BackgroundTransparency = properties.Transparency or 0.82,
        BorderSizePixel = 0,
        Parent = properties.Parent,
        LayoutOrder = properties.LayoutOrder,
    })
    UI.corner(UDim.new(0, properties.Radius or 4)).Parent = badge
    UI.stroke(color or Argon.Theme.Accent, 1, properties.StrokeTransparency or 0.6).Parent = badge
    local label = UI.label({
        Parent = badge,
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = text,
        TextSize = properties.TextSize or 10,
        Font = Enum.Font.GothamBold,
        TextColor3 = textColor or color or Argon.Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    UI.padding(0, properties.PaddingX or 6, 0, properties.PaddingX or 6).Parent = badge
    return badge, label
end

function UI.shadow(parent, color, transparency, size)
    local shadow = UI.frame({
        Parent = parent,
        BackgroundColor3 = color or Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = transparency or 0.6,
        BorderSizePixel = 0,
        Size = UDim2.new(1, size or 0, 1, size or 0),
        Position = UDim2.new(0, 0, 0, 0),
    })
    UI.corner(UDim.new(0, 14)).Parent = shadow
    return shadow
end

-- ============================================================================
-- 10. THEME SYSTEM
-- ============================================================================
-- One palette = one flat table of Color3s. Components never hardcode colors;
-- they read Argon.Theme and register a re-apply function so live theme switches
-- cost one pass over the appliers instead of a rebuild.

local function rgb(r, g, b)
    return Color3.fromRGB(r, g, b)
end

local ThemeDefaults = {
    Name = "Custom",

    -- shell
    Background = rgb(16, 17, 21),
    BackgroundAlt = rgb(20, 21, 26),
    Sidebar = rgb(20, 21, 26),
    SidebarAlt = rgb(25, 26, 32),
    Rail = rgb(14, 15, 19),
    Content = rgb(16, 17, 21),
    Overlay = rgb(8, 9, 12),

    -- surfaces
    Surface = rgb(23, 24, 30),
    SurfaceHigh = rgb(29, 31, 38),
    SurfaceHover = rgb(34, 36, 45),
    SurfaceActive = rgb(40, 43, 53),
    Input = rgb(19, 20, 25),

    -- lines
    Stroke = rgb(38, 41, 50),
    StrokeLight = rgb(52, 56, 68),
    StrokeFocus = rgb(72, 78, 94),

    -- text
    Text = rgb(235, 238, 244),
    TextMuted = rgb(150, 157, 172),
    TextDim = rgb(105, 112, 128),
    TextInverse = rgb(12, 13, 17),

    -- semantic
    Accent = rgb(56, 132, 255),
    AccentSoft = rgb(34, 68, 128),
    AccentText = rgb(255, 255, 255),
    Success = rgb(74, 206, 132),
    Warning = rgb(240, 178, 64),
    Danger = rgb(240, 92, 96),
    Info = rgb(96, 165, 250),
    Premium = rgb(178, 122, 255),
    Soon = rgb(214, 158, 46),

    -- misc
    Shadow = rgb(0, 0, 0),
    ShadowTransparency = 0.55,
    Glow = rgb(56, 132, 255),

    -- geometry
    Corner = 8,
    CornerSmall = 6,
    CornerLarge = 12,
    StrokeWidth = 1,

    -- type
    Font = Enum.Font.Gotham,
    FontMedium = Enum.Font.GothamMedium,
    FontBold = Enum.Font.GothamBold,
    FontMono = Enum.Font.Code,

    -- sizing
    TextSize = 13,
    TextSizeSmall = 11,
    TextSizeTiny = 10,
    TextSizeHeader = 15,
    TextSizeTitle = 20,
    RowHeight = 44,
    SidebarWidth = 196,
    RailWidth = 52,
}

local function themeFrom(overrides)
    local palette = deepCopy(ThemeDefaults)
    for key, value in pairs(overrides or {}) do
        palette[key] = value
    end
    return palette
end

Argon.ThemeTemplate = function(overrides)
    return themeFrom(overrides)
end

Argon.Themes = {}

Argon.Themes.Dark = themeFrom({
    Name = "Dark",
    Accent = rgb(62, 130, 255),
    Glow = rgb(62, 130, 255),
})

Argon.Themes.Aqua = themeFrom({
    Name = "Aqua",
    Accent = rgb(52, 196, 168),
    AccentSoft = rgb(22, 82, 72),
    Glow = rgb(52, 196, 168),
    Premium = rgb(168, 128, 255),
    Background = rgb(14, 18, 20),
    BackgroundAlt = rgb(18, 23, 26),
    Sidebar = rgb(18, 23, 26),
    SidebarAlt = rgb(22, 29, 32),
    Rail = rgb(12, 16, 18),
    Surface = rgb(22, 28, 32),
    SurfaceHigh = rgb(28, 35, 40),
    SurfaceHover = rgb(33, 42, 47),
    SurfaceActive = rgb(39, 50, 56),
    Input = rgb(17, 22, 25),
    Stroke = rgb(35, 44, 49),
    StrokeLight = rgb(48, 60, 67),
})

Argon.Themes.Serika = themeFrom({
    Name = "Serika",
    Accent = rgb(226, 183, 74),
    AccentSoft = rgb(92, 72, 22),
    AccentText = rgb(24, 20, 10),
    Glow = rgb(226, 183, 74),
    Background = rgb(22, 21, 18),
    BackgroundAlt = rgb(27, 26, 22),
    Sidebar = rgb(27, 26, 22),
    SidebarAlt = rgb(32, 31, 26),
    Rail = rgb(18, 17, 15),
    Surface = rgb(31, 30, 26),
    SurfaceHigh = rgb(38, 36, 31),
    SurfaceHover = rgb(45, 43, 37),
    SurfaceActive = rgb(53, 50, 43),
    Input = rgb(25, 24, 20),
    Stroke = rgb(48, 45, 38),
    StrokeLight = rgb(63, 59, 50),
    Text = rgb(240, 236, 226),
    TextMuted = rgb(166, 159, 143),
    TextDim = rgb(120, 114, 100),
})

Argon.Themes.Rust = themeFrom({
    Name = "Rust",
    Accent = rgb(226, 106, 60),
    AccentSoft = rgb(92, 40, 22),
    Glow = rgb(226, 106, 60),
    Background = rgb(23, 18, 16),
    Sidebar = rgb(28, 22, 19),
    SidebarAlt = rgb(33, 26, 23),
    Rail = rgb(18, 14, 12),
    Surface = rgb(32, 25, 22),
    SurfaceHigh = rgb(39, 31, 27),
    SurfaceHover = rgb(46, 37, 32),
    SurfaceActive = rgb(54, 43, 37),
    Input = rgb(26, 20, 17),
    Stroke = rgb(49, 39, 33),
    StrokeLight = rgb(64, 51, 43),
    Text = rgb(243, 233, 227),
    TextMuted = rgb(171, 156, 145),
})

Argon.Themes.Legacy = themeFrom({
    Name = "Legacy",
    Accent = rgb(146, 118, 255),
    AccentSoft = rgb(58, 44, 110),
    Glow = rgb(146, 118, 255),
    Background = rgb(19, 18, 26),
    Sidebar = rgb(24, 22, 32),
    SidebarAlt = rgb(29, 27, 38),
    Rail = rgb(15, 14, 21),
    Surface = rgb(28, 26, 38),
    SurfaceHigh = rgb(35, 32, 47),
    SurfaceHover = rgb(42, 39, 56),
    SurfaceActive = rgb(50, 46, 66),
    Input = rgb(22, 20, 30),
    Stroke = rgb(45, 41, 60),
    StrokeLight = rgb(60, 55, 78),
    Text = rgb(233, 232, 245),
    TextMuted = rgb(154, 150, 176),
})

Argon.Themes.Rose = themeFrom({
    Name = "Rose",
    Accent = rgb(238, 120, 168),
    AccentSoft = rgb(96, 40, 62),
    Glow = rgb(238, 120, 168),
    Background = rgb(22, 17, 21),
    Sidebar = rgb(27, 21, 26),
    SidebarAlt = rgb(32, 25, 31),
    Rail = rgb(17, 13, 16),
    Surface = rgb(31, 24, 29),
    SurfaceHigh = rgb(38, 30, 36),
    SurfaceHover = rgb(45, 36, 43),
    SurfaceActive = rgb(53, 42, 50),
    Input = rgb(25, 19, 23),
    Stroke = rgb(48, 38, 45),
    StrokeLight = rgb(63, 50, 59),
})

Argon.Themes.Mint = themeFrom({
    Name = "Mint",
    Accent = rgb(92, 214, 154),
    AccentSoft = rgb(30, 84, 60),
    AccentText = rgb(10, 26, 19),
    Glow = rgb(92, 214, 154),
    Background = rgb(15, 20, 18),
    Sidebar = rgb(19, 25, 22),
    SidebarAlt = rgb(23, 30, 27),
    Rail = rgb(12, 16, 14),
    Surface = rgb(23, 30, 27),
    SurfaceHigh = rgb(29, 37, 33),
    SurfaceHover = rgb(35, 44, 40),
    SurfaceActive = rgb(41, 52, 47),
    Input = rgb(18, 24, 21),
    Stroke = rgb(36, 45, 41),
    StrokeLight = rgb(49, 60, 55),
})

Argon.Themes.Light = themeFrom({
    Name = "Light",
    Background = rgb(246, 247, 249),
    BackgroundAlt = rgb(240, 242, 245),
    Sidebar = rgb(252, 252, 253),
    SidebarAlt = rgb(244, 245, 248),
    Rail = rgb(236, 238, 242),
    Content = rgb(246, 247, 249),
    Overlay = rgb(30, 32, 38),
    Surface = rgb(255, 255, 255),
    SurfaceHigh = rgb(243, 244, 247),
    SurfaceHover = rgb(236, 238, 242),
    SurfaceActive = rgb(228, 231, 237),
    Input = rgb(246, 247, 249),
    Stroke = rgb(222, 225, 231),
    StrokeLight = rgb(203, 208, 216),
    StrokeFocus = rgb(160, 168, 180),
    Text = rgb(24, 27, 33),
    TextMuted = rgb(92, 99, 112),
    TextDim = rgb(133, 140, 153),
    TextInverse = rgb(250, 250, 252),
    Accent = rgb(46, 108, 240),
    AccentSoft = rgb(214, 227, 255),
    AccentText = rgb(255, 255, 255),
    Success = rgb(22, 163, 100),
    Warning = rgb(196, 132, 12),
    Danger = rgb(214, 62, 66),
    Info = rgb(37, 99, 235),
    Premium = rgb(130, 78, 226),
    Shadow = rgb(120, 126, 140),
    ShadowTransparency = 0.82,
    Glow = rgb(46, 108, 240),
})

Argon.Theme = deepCopy(Argon.Themes.Dark)
Argon.ThemeName = "Dark"

local function registerThemed(callback)
    table.insert(Argon.ThemeAppliers, callback)
    return callback
end

local function removeThemed(callback)
    for index, existing in ipairs(Argon.ThemeAppliers) do
        if existing == callback then
            table.remove(Argon.ThemeAppliers, index)
            return
        end
    end
end

local function applyTheme(palette, notify)
    Argon.Theme = palette
    Argon.ThemeName = palette.Name

    for _, applier in ipairs(Argon.ThemeAppliers) do
        local ok, err = pcall(applier, palette)
        if not ok then
            debugLog("theme applier failed:", err)
        end
    end

    if notify then
        for _, window in ipairs(Argon.Windows) do
            if window.ApplyTheme then
                pcall(window.ApplyTheme, window, palette)
            end
        end
    end
end

function Argon:SetTheme(name)
    if type(name) == "table" then
        applyTheme(themeFrom(name), true)
        return self
    end

    local palette = self.Themes[name]
    if not palette then
        warnOnce("unknown theme " .. tostring(name), "theme-" .. tostring(name))
        return self
    end
    applyTheme(deepCopy(palette), true)
    return self
end

function Argon:GetTheme()
    return self.Theme
end

function Argon:GetThemeName()
    return self.ThemeName
end

function Argon:GetThemeNames()
    local names = {}
    for name in pairs(self.Themes) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function Argon:SetAccent(color)
    if not isColor(color) then
        return self
    end
    local palette = deepCopy(self.Theme)
    palette.Accent = color
    palette.Glow = color
    palette.AccentSoft = Color.darken(color, 0.62)
    palette.AccentText = Color.readableOn(color)
    applyTheme(palette, true)
    return self
end

function Argon:RegisterTheme(entry)
    if type(entry) ~= "table" then
        return self
    end
    local name = entry.Name
    if not name then
        error("Argon:RegisterTheme requires a Name", 2)
    end
    self.Themes[name] = themeFrom(entry)
    return self
end

-- A theme-aware color helper: returns the current palette value, so components
-- never cache colors at construction time.
local function C(key)
    return Argon.Theme[key] or Color3.new(1, 0, 1)
end

local function accent()
    return Argon.Theme.Accent
end

-- ============================================================================
-- 11. FLAGS
-- ============================================================================
-- Flags are the single source of truth for component state. Reading component
-- state directly is discouraged: a saved config or a script can write the flag
-- and the widget refreshes.

local Flags = {
    listeners = {},
    owners = {},
    history = {},
}

local function resolveFlagPath(flag)
    if type(flag) == "table" then
        local parts = {}
        for index, segment in ipairs(flag) do
            parts[index] = tostring(segment)
        end
        return table.concat(parts, ".")
    end
    return tostring(flag)
end

local function addFlagListener(flag, callback)
    flag = resolveFlagPath(flag)
    Flags.listeners[flag] = Flags.listeners[flag] or {}
    table.insert(Flags.listeners[flag], callback)
    return callback
end

local function fireFlag(flag, value, origin)
    local listeners = Flags.listeners[flag]
    if not listeners then
        return
    end
    for _, callback in ipairs(listeners) do
        local ok, err = pcall(callback, value, origin)
        if not ok then
            warn("[Argon] flag listener for " .. flag .. " failed: " .. tostring(err))
        end
    end
end

function Argon:GetFlag(flag)
    return self.Flags[resolveFlagPath(flag)]
end

function Argon:SetFlag(flag, value, silent)
    flag = resolveFlagPath(flag)
    self.Flags[flag] = value

    local owners = Flags.owners[flag]
    if owners then
        for element in pairs(owners) do
            if not element.Destroyed then
                element.Value = value
                if element.Refresh then
                    pcall(element.Refresh, element)
                end
            end
        end
    end

    if not silent then
        fireFlag(flag, value, "api")
    end
    return self
end

function Argon:GetFlags()
    return shallowCopy(self.Flags)
end

function Argon:ClearFlags()
    self.Flags = {}
    return self
end

function Argon:OnFlagChanged(flag, callback)
    addFlagListener(flag, callback)
    return self
end

local function registerFlagOwner(flag, element)
    flag = resolveFlagPath(flag)
    Flags.owners[flag] = Flags.owners[flag] or {}
    Flags.owners[flag][element] = true
end

local function unregisterFlagOwner(flag, element)
    flag = resolveFlagPath(flag)
    if Flags.owners[flag] then
        Flags.owners[flag][element] = nil
    end
end

-- ============================================================================
-- 12. FILESYSTEM AND JSON
-- ============================================================================

local FS = {
    available = {
        read = type(readfile) == "function",
        write = type(writefile) == "function",
        list = type(listfiles) == "function",
        isFile = type(isfile) == "function",
        isFolder = type(isfolder) == "function",
        makeFolder = type(makefolder) == "function",
        delete = type(delfile) == "function",
        append = type(appendfile) == "function",
    },
}

function FS.ensureFolder(path)
    if not FS.available.makeFolder or not FS.available.isFolder then
        return false
    end
    local okExists, exists = pcall(isfolder, path)
    if okExists and exists then
        return true
    end
    local ok = pcall(makefolder, path)
    return ok
end

function FS.write(path, contents)
    if not FS.available.write then
        warnOnce("writefile is unavailable in this executor; configs are memory-only", "writefile")
        return false
    end
    local ok = pcall(writefile, path, contents)
    if not ok then
        warn("[Argon] could not write " .. tostring(path))
    end
    return ok
end

function FS.read(path)
    if not FS.available.read then
        warnOnce("readfile is unavailable in this executor", "readfile")
        return nil
    end
    local ok, contents = pcall(readfile, path)
    if not ok then
        return nil
    end
    return contents
end

function FS.exists(path)
    if not FS.available.isFile then
        return false
    end
    local ok, exists = pcall(isfile, path)
    return ok and exists or false
end

function FS.list(path)
    if not FS.available.list then
        return {}
    end
    local ok, files = pcall(listfiles, path)
    if not ok or type(files) ~= "table" then
        return {}
    end
    return files
end

function FS.delete(path)
    if not FS.available.delete then
        return false
    end
    local ok = pcall(delfile, path)
    return ok
end

local Json = {}

local function encodeValue(value, depth)
    depth = depth or 0
    if depth > 24 then
        return "null"
    end

    local valueType = type(value)

    if value == nil then
        return "null"
    elseif valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "0"
        end
        if value % 1 == 0 and math.abs(value) < 1e15 then
            return string.format("%d", value)
        end
        return string.format("%.14g", value)
    elseif valueType == "string" then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
            if char == '"' then
                return '\\"'
            elseif char == "\\" then
                return "\\\\"
            elseif char == "\n" then
                return "\\n"
            elseif char == "\r" then
                return "\\r"
            elseif char == "\t" then
                return "\\t"
            end
            return string.format("\\u%04x", char:byte())
        end) .. '"'
    elseif valueType == "table" then
        if isColor(value) then
            return string.format(
                '{"__type":"Color3","R":%.6f,"G":%.6f,"B":%.6f}',
                value.R, value.G, value.B
            )
        end
        if isEnumItem(value) then
            return string.format(
                '{"__type":"EnumItem","Name":"%s","EnumType":"%s"}',
                tostring(value.Name),
                tostring(value.EnumType)
            )
        end

        local parts = {}
        if isArray(value) then
            for _, item in ipairs(value) do
                parts[#parts + 1] = encodeValue(item, depth + 1)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end

        for key, item in pairs(value) do
            if type(key) == "string" or type(key) == "number" then
                parts[#parts + 1] = encodeValue(tostring(key), depth + 1) .. ":" .. encodeValue(item, depth + 1)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    return "null"
end

function Json.encode(value)
    local ok, result = pcall(encodeValue, value, 0)
    if not ok then
        warn("[Argon] JSON encode failed: " .. tostring(result))
        return "{}"
    end
    return result
end

local function decodeString(text, startIndex)
    local out = {}
    local index = startIndex + 1
    while index <= #text do
        local char = text:sub(index, index)
        if char == '"' then
            return table.concat(out), index + 1
        elseif char == "\\" then
            local escape = text:sub(index + 1, index + 1)
            if escape == "n" then
                out[#out + 1] = "\n"
                index = index + 2
            elseif escape == "t" then
                out[#out + 1] = "\t"
                index = index + 2
            elseif escape == "r" then
                out[#out + 1] = "\r"
                index = index + 2
            elseif escape == "u" then
                local hex = text:sub(index + 2, index + 5)
                out[#out + 1] = string.char(tonumber(hex, 16) or 32)
                index = index + 6
            else
                out[#out + 1] = escape
                index = index + 2
            end
        else
            out[#out + 1] = char
            index = index + 1
        end
    end
    error("unterminated string")
end

local JsonDecode

local function decodeValue(text, index)
    while index <= #text and text:sub(index, index):match("%s") do
        index = index + 1
    end
    local char = text:sub(index, index)

    if char == "{" then
        local object = {}
        index = index + 1
        while true do
            while index <= #text and text:sub(index, index):match("%s") do
                index = index + 1
            end
            if text:sub(index, index) == "}" then
                return object, index + 1
            end
            local key
            key, index = decodeString(text, index)
            while index <= #text and text:sub(index, index):match("%s") do
                index = index + 1
            end
            if text:sub(index, index) ~= ":" then
                error("expected ':' in object")
            end
            index = index + 1
            local value
            value, index = decodeValue(text, index)
            object[key] = value
            while index <= #text and text:sub(index, index):match("%s") do
                index = index + 1
            end
            local separator = text:sub(index, index)
            index = index + 1
            if separator == "}" then
                return object, index
            end
            if separator ~= "," then
                error("expected ',' or '}' in object")
            end
        end
    elseif char == "[" then
        local array = {}
        index = index + 1
        while true do
            while index <= #text and text:sub(index, index):match("%s") do
                index = index + 1
            end
            if text:sub(index, index) == "]" then
                return array, index + 1
            end
            local value
            value, index = decodeValue(text, index)
            array[#array + 1] = value
            while index <= #text and text:sub(index, index):match("%s") do
                index = index + 1
            end
            local separator = text:sub(index, index)
            index = index + 1
            if separator == "]" then
                return array, index
            end
            if separator ~= "," then
                error("expected ',' or ']' in array")
            end
        end
    elseif char == '"' then
        return decodeString(text, index)
    elseif text:sub(index, index + 3) == "true" then
        return true, index + 4
    elseif text:sub(index, index + 4) == "false" then
        return false, index + 5
    elseif text:sub(index, index + 3) == "null" then
        return nil, index + 4
    end

    local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", index)
    if not number or number == "" then
        error("unexpected token at position " .. index)
    end
    return tonumber(number), index + #number
end

JsonDecode = function(text)
    local value, index = decodeValue(text, 1)
    while index <= #text and text:sub(index, index):match("%s") do
        index = index + 1
    end
    if index <= #text then
        error("trailing characters after JSON value")
    end
    return value
end

function Json.decode(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local ok, result = pcall(JsonDecode, text)
    if not ok then
        warn("[Argon] JSON decode failed: " .. tostring(result))
        return nil
    end
    return result
end

Argon.Json = Json
Argon.FS = FS

-- ============================================================================
-- 13. CONFIG STORE
-- ============================================================================

local ConfigStore = {}

local function decodeFlags(encoded)
    local decoded = Json.decode(encoded)
    if type(decoded) ~= "table" then
        return {}
    end
    local flags = {}
    for key, value in pairs(decoded) do
        if type(value) == "table" and value.__type == "Color3" then
            flags[key] = Color3.new(value.R or 0, value.G or 0, value.B or 0)
        elseif type(value) == "table" and value.__type == "EnumItem" then
            local enum = Enum[value.EnumType or ""]
            if enum and enum[value.Name or ""] then
                flags[key] = enum[value.Name]
            end
        else
            flags[key] = value
        end
    end
    return flags
end

function ConfigStore.path(name)
    return Argon.Config.ConfigFolder .. "/" .. tostring(name) .. ".json"
end

function ConfigStore.save(name)
    name = name or Argon.Config.DefaultConfig
    FS.ensureFolder(Argon.Config.Folder)
    FS.ensureFolder(Argon.Config.ConfigFolder)

    local snapshot = {}
    for key, value in pairs(Argon.Flags) do
        snapshot[key] = value
    end

    local payload = Json.encode({
        format = "argon-config",
        version = 2,
        savedAt = os.time(),
        flags = snapshot,
    })

    local ok = FS.write(ConfigStore.path(name), payload)
    if ok then
        debugLog("saved config", name)
    end
    return ok
end

function ConfigStore.load(name, silent)
    name = name or Argon.Config.DefaultConfig
    local payload = FS.read(ConfigStore.path(name))
    if not payload then
        if not silent then
            warnOnce("no config named " .. tostring(name), "config-" .. tostring(name))
        end
        return false
    end

    local decoded = Json.decode(payload)
    if type(decoded) ~= "table" then
        return false
    end

    local flags = decoded.flags or {}
    for key, value in pairs(flags) do
        local resolved = value
        if type(value) == "table" and value.__type == "Color3" then
            resolved = Color3.new(value.R or 0, value.G or 0, value.B or 0)
        elseif type(value) == "table" and value.__type == "EnumItem" then
            local enum = Enum[value.EnumType or ""]
            if enum and enum[value.Name or ""] then
                resolved = enum[value.Name]
            else
                resolved = nil
            end
        end
        if resolved ~= nil then
            Argon:SetFlag(key, resolved)
        end
    end

    debugLog("loaded config", name)
    return true
end

function ConfigStore.list()
    local names = {}
    for _, path in ipairs(FS.list(Argon.Config.ConfigFolder)) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function ConfigStore.delete(name)
    return FS.delete(ConfigStore.path(name))
end

function ConfigStore.scheduleSave(name)
    if not Argon.Config.AutoSave then
        return
    end
    ConfigStore._pendingName = name or ConfigStore._pendingName or Argon.Config.DefaultConfig
    if ConfigStore._pending then
        return
    end
    ConfigStore._pending = true
    task.delay(Argon.Config.AutoSaveDelay, function()
        ConfigStore._pending = false
        ConfigStore.save(ConfigStore._pendingName)
    end)
end

function Argon:SaveConfig(name)
    return ConfigStore.save(name)
end

function Argon:LoadConfig(name)
    return ConfigStore.load(name)
end

function Argon:GetConfigs()
    return ConfigStore.list()
end

function Argon:DeleteConfig(name)
    return ConfigStore.delete(name)
end

Argon.ConfigStore = ConfigStore

-- ============================================================================
-- 14. NOTIFICATIONS
-- ============================================================================

local NotificationUI = {
    gui = nil,
    holder = nil,
    list = {},
}

local function notificationGui()
    if not NotificationUI.gui or not NotificationUI.gui.Parent then
        NotificationUI.gui = createScreenGui("ArgonNotifications", 5000)
        NotificationUI.holder = UI.transparent({
            Parent = NotificationUI.gui,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -16, 1, -16),
            Size = UDim2.new(0, 300, 1, -32),
        })
        UI.listLayout(8).Parent = NotificationUI.holder
        local align = Instance.new("UIListLayout")
        align.Parent = NotificationUI.holder
        align.SortOrder = Enum.SortOrder.LayoutOrder
        align.VerticalAlignment = Enum.VerticalAlignment.Bottom
        align.FillDirection = Enum.FillDirection.Vertical
        align.Padding = UDim.new(0, 8)
        align.HorizontalAlignment = Enum.HorizontalAlignment.Right
    end
    return NotificationUI.gui, NotificationUI.holder
end

local NotificationKind = {
    info = { Icon = "i", Color = "Accent" },
    success = { Icon = "✓", Color = "Success" },
    warning = { Icon = "!", Color = "Warning" },
    danger = { Icon = "×", Color = "Danger" },
    premium = { Icon = "★", Color = "Premium" },
}

function Argon:Notify(config)
    if type(config) == "string" then
        config = { Text = config }
    end
    config = config or {}

    local kind = tostring(config.Kind or config.Type or "info")
    local preset = NotificationKind[kind] or NotificationKind.info
    local accentColor = config.Color or C(preset.Color) or accent()
    local duration = tonumber(config.Duration) or self.Config.NotificationDuration

    local _, holder = notificationGui()

    if #NotificationUI.list >= self.Config.NotificationLimit then
        local oldest = table.remove(NotificationUI.list, 1)
        if oldest then
            pcall(function()
                oldest:Destroy()
            end)
        end
    end

    local card = UI.frame({
        Parent = holder,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C("Surface"),
        BackgroundTransparency = 0.04,
        LayoutOrder = -math.floor(os.clock() * 1000),
    })
    UI.corner(UDim.new(0, Argon.Theme.CornerLarge)).Parent = card
    UI.stroke(C("Stroke"), 1, 0).Parent = card

    local accentBar = UI.frame({
        Parent = card,
        Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = accentColor,
        BorderSizePixel = 0,
    })
    UI.corner(UDim.new(0, 2)).Parent = accentBar

    local iconBox = UI.frame({
        Parent = card,
        Position = UDim2.new(0, 14, 0, 14),
        Size = UDim2.new(0, 22, 0, 22),
        BackgroundColor3 = accentColor,
        BackgroundTransparency = 0.85,
    })
    UI.corner(UDim.new(1, 0)).Parent = iconBox
    UI.glyph(preset.Icon, 11, accentColor, {
        Parent = iconBox,
        Size = UDim2.new(1, 0, 1, 0),
    })

    local textHolder = UI.transparent({
        Parent = card,
        Position = UDim2.new(0, 46, 0, 0),
        Size = UDim2.new(1, -60, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    UI.padding(12, 0, 12, 0).Parent = textHolder
    UI.listLayout(2).Parent = textHolder

    if config.Title and config.Title ~= "" then
        UI.label({
            Parent = textHolder,
            Size = UDim2.new(1, 0, 0, 16),
            Text = tostring(config.Title),
            TextSize = Argon.Theme.TextSize,
            Font = Argon.Theme.FontBold,
            TextColor3 = C("Text"),
            LayoutOrder = 1,
        })
    end

    if config.Text and config.Text ~= "" then
        UI.label({
            Parent = textHolder,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = tostring(config.Text),
            TextSize = Argon.Theme.TextSizeSmall,
            TextColor3 = C("TextMuted"),
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
        })
    end

    local progressTrack = UI.frame({
        Parent = card,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 3, 1, 0),
        Size = UDim2.new(0, 0, 0, 2),
        BackgroundColor3 = accentColor,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
    })

    local closeButton = UI.button({
        Parent = card,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.new(0, 18, 0, 18),
        Text = "×",
        TextSize = 13,
        TextColor3 = C("TextDim"),
    })
    Connect(closeButton.MouseButton1Click, function()
        pcall(function()
            card:Destroy()
        end)
    end)

    table.insert(NotificationUI.list, card)

    card.BackgroundTransparency = 1
    card.Position = UDim2.new(0, 12, 0, 0)
    animate(card, { BackgroundTransparency = 0.04, Position = UDim2.new(0, 0, 0, 0) }, 0.18,
        EasingStyle.Quart, EasingDirection.Out)

    if duration > 0 then
        animate(progressTrack, { Size = UDim2.new(1, -3, 0, 2) }, duration, EasingStyle.Linear)
        task.delay(duration, function()
            if not card.Parent then
                return
            end
            animate(card, { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 0) }, 0.16,
                EasingStyle.Quart, EasingDirection.In, function()
                    pcall(function()
                        card:Destroy()
                    end)
                end)
            for index, existing in ipairs(NotificationUI.list) do
                if existing == card then
                    table.remove(NotificationUI.list, index)
                    break
                end
            end
        end)
    end

    return card
end

function Argon:SetNotificationLimit(limit)
    self.Config.NotificationLimit = tonumber(limit) or 6
    return self
end

-- ============================================================================
-- 15. TOOLTIPS
-- ============================================================================

local TooltipUI = {
    gui = nil,
    frame = nil,
    label = nil,
    pending = nil,
    target = nil,
}

local function ensureTooltip()
    if TooltipUI.frame and TooltipUI.frame.Parent then
        return TooltipUI.frame
    end

    TooltipUI.gui = createScreenGui("ArgonTooltips", 6000)
    TooltipUI.frame = UI.frame({
        Parent = TooltipUI.gui,
        Size = UDim2.new(0, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundColor3 = C("SurfaceHigh"),
        BackgroundTransparency = 0.02,
        Visible = false,
        ZIndex = 50,
    })
    UI.corner(UDim.new(0, 6)).Parent = TooltipUI.frame
    UI.stroke(C("StrokeLight"), 1, 0.2).Parent = TooltipUI.frame
    UI.padding(6, 8, 6, 8).Parent = TooltipUI.frame

    TooltipUI.label = UI.label({
        Parent = TooltipUI.frame,
        Size = UDim2.new(0, 0, 0, 14),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "",
        TextSize = Argon.Theme.TextSizeTiny,
        TextColor3 = C("Text"),
        ZIndex = 51,
    })

    return TooltipUI.frame
end

local function showTooltip(text, x, y)
    if not text or text == "" then
        return
    end
    local frame = ensureTooltip()
    TooltipUI.label.Text = tostring(text)
    frame.Position = UDim2.new(0, (x or 0) + 14, 0, (y or 0) + 18)
    frame.Visible = true
    frame.BackgroundTransparency = 1
    animate(frame, { BackgroundTransparency = 0.02 }, 0.1)
end

local function hideTooltip()
    if TooltipUI.pending then
        task.cancel(TooltipUI.pending)
        TooltipUI.pending = nil
    end
    if TooltipUI.frame then
        TooltipUI.frame.Visible = false
    end
    TooltipUI.target = nil
end

local function attachTooltip(instance, text)
    if not text or text == "" or not instance then
        return
    end
    Connect(instance.MouseEnter, function()
        if TooltipUI.pending then
            task.cancel(TooltipUI.pending)
        end
        TooltipUI.pending = task.delay(Argon.Config.TooltipDelay, function()
            local mouse = UserInputService:GetMouseLocation()
            showTooltip(text, mouse.X, mouse.Y)
        end)
    end)
    Connect(instance.MouseLeave, function()
        hideTooltip()
    end)
    Connect(instance.MouseMoved, function()
        if TooltipUI.frame and TooltipUI.frame.Visible then
            local mouse = UserInputService:GetMouseLocation()
            TooltipUI.frame.Position = UDim2.new(0, mouse.X + 14, 0, mouse.Y + 18)
        end
    end)
end

Argon.AttachTooltip = attachTooltip

-- ============================================================================
-- 16. DIALOGS
-- ============================================================================

function Argon:Dialog(config)
    config = config or {}
    local parent = GUI_PARENT
    local gui = createScreenGui("ArgonDialog" .. tostring(#self.Dialogs + 1), 7000)

    local overlay = UI.button({
        Parent = gui,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = C("Overlay"),
        BackgroundTransparency = 0.35,
        Text = "",
        ZIndex = 1,
    })

    local card = UI.frame({
        Parent = overlay,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, config.Width or 340, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C("BackgroundAlt"),
        ZIndex = 2,
    })
    UI.corner(UDim.new(0, Argon.Theme.CornerLarge)).Parent = card
    UI.stroke(C("Stroke"), 1, 0).Parent = card
    UI.padding(20).Parent = card
    UI.listLayout(10).Parent = card

    UI.label({
        Parent = card,
        Size = UDim2.new(1, 0, 0, 20),
        Text = tostring(config.Title or "Notice"),
        TextSize = Argon.Theme.TextSizeHeader,
        Font = Argon.Theme.FontBold,
        LayoutOrder = 1,
    })

    if config.Text then
        UI.label({
            Parent = card,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = tostring(config.Text),
            TextSize = Argon.Theme.TextSizeSmall,
            TextColor3 = C("TextMuted"),
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
        })
    end

    local buttonsHolder = UI.transparent({
        Parent = card,
        Size = UDim2.new(1, 0, 0, 32),
        LayoutOrder = 3,
    })

    local dialog = { Gui = gui, Card = card }

    function dialog:Close()
        pcall(function()
            gui:Destroy()
        end)
        for index, existing in ipairs(Argon.Dialogs) do
            if existing == self then
                table.remove(Argon.Dialogs, index)
                break
            end
        end
    end

    local actions = config.Buttons or { { Text = "OK", Primary = true } }
    local function layoutButtons()
        local count = #actions
        local gap = 8
        local width = (1 - gap * (count - 1) / 100) / count
        for index, action in ipairs(actions) do
            local button = UI.button({
                Parent = buttonsHolder,
                Size = UDim2.new(width - gap / 100, 0, 1, 0),
                Position = UDim2.new((index - 1) * (width + gap / 100), 0, 0, 0),
                BackgroundColor3 = action.Primary and accent() or C("SurfaceHigh"),
                Text = tostring(action.Text or "OK"),
                TextSize = Argon.Theme.TextSizeSmall,
                Font = Argon.Theme.FontMedium,
                TextColor3 = action.Primary and C("AccentText") or C("Text"),
            })
            UI.corner(UDim.new(0, 6)).Parent = button
            Connect(button.MouseButton1Click, function()
                if action.Callback then
                    pcall(action.Callback)
                end
                if action.Close ~= false then
                    dialog:Close()
                end
            end)
        end
    end
    layoutButtons()

    table.insert(self.Dialogs, dialog)
    return dialog
end

-- ============================================================================
-- 17. DRAG AND RESIZE CONTROLLERS
-- ============================================================================

local function makeDraggable(frame, handle, options)
    options = options or {}
    handle = handle or frame
    local dragging = false
    local dragStart
    local startPosition
    local startSize = frame.Size

    Connect(handle.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if options.shouldDrag and not options.shouldDrag() then
            return
        end
        dragging = true
        dragStart = input.Position
        startPosition = frame.Position
        if options.onStart then
            options.onStart()
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            if dragging and options.onEnd then
                options.onEnd()
            end
            dragging = false
        end
    end)

    Connect(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - dragStart
        local position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
        )

        if options.bounds then
            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
                or Vector2.new(1920, 1080)
            local frameSize = frame.AbsoluteSize
            local absoluteX = position.X.Offset + position.X.Scale * viewport.X
            local absoluteY = position.Y.Offset + position.Y.Scale * viewport.Y
            absoluteX = Math.clamp(absoluteX, -frameSize.X + 80, viewport.X - 80)
            absoluteY = Math.clamp(absoluteY, 0, viewport.Y - 40)
            position = UDim2.new(0, absoluteX, 0, absoluteY)
        end

        frame.Position = position

        if options.onDrag then
            options.onDrag(position)
        end
    end)
end

local function makeResizable(frame, handle, options)
    options = options or {}
    local resizing = false
    local startInput
    local startSize
    local minimum = options.Min or Vector2.new(360, 260)
    local maximum = options.Max or Vector2.new(1600, 1200)

    Connect(handle.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        resizing = true
        startInput = input.Position
        startSize = frame.AbsoluteSize
    end)

    Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if resizing and options.onEnd then
                options.onEnd(frame.AbsoluteSize)
            end
            resizing = false
        end
    end)

    Connect(UserInputService.InputChanged, function(input)
        if not resizing then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        local delta = input.Position - startInput
        local width = Math.clamp(startSize.X + delta.X, minimum.X, maximum.X)
        local height = Math.clamp(startSize.Y + delta.Y, minimum.Y, maximum.Y)
        frame.Size = UDim2.new(0, width, 0, height)
        if options.onResize then
            options.onResize(Vector2.new(width, height))
        end
    end)
end

-- ============================================================================
-- 18. SCROLLING HELPERS
-- ============================================================================

local function bindCanvas(scroller, layout, bottomPadding)
    local function update()
        if not scroller.Parent then
            return
        end
        local content = layout.AbsoluteContentSize
        scroller.CanvasSize = UDim2.new(0, 0, 0, content.Y + (bottomPadding or 12))
    end
    Connect(scroller:GetPropertyChangedSignal("AbsoluteSize"), update)
    Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), update)
    update()
    return update
end

local function scrollToElement(scroller, element)
    if not scroller or not element or not element.Parent then
        return
    end
    local target = element.AbsolutePosition.Y - scroller.AbsolutePosition.Y + scroller.CanvasPosition.Y
    animate(scroller, { CanvasPosition = Vector3.new(0, math.max(target - 40, 0), 0) }, 0.25,
        EasingStyle.Quart, EasingDirection.Out)
end

-- ============================================================================
-- 19. ELEMENT BASE
-- ============================================================================

local Element = {}
Element.__index = Element

function Element.new(section, config)
    local self = setmetatable({}, Element)

    self.Section = section
    self.Page = section.Page
    self.Window = section.Window
    self.Config = config or {}
    self.Flag = self.Config.Flag and resolveFlagPath(self.Config.Flag) or nil
    self.Value = self.Config.Default
    self.Callbacks = {}
    self.ThemeAppliers = {}
    self.Destroyed = false
    self.Disabled = false
    self.Visible = true
    self.Width = self.Config.Width or "full"

    if self.Flag and Argon.Flags[self.Flag] ~= nil then
        self.Value = Argon.Flags[self.Flag]
    end
    if self.Flag then
        Argon.Flags[self.Flag] = self.Value
        registerFlagOwner(self.Flag, self)
    end

    if isCallable(self.Config.Callback) then
        table.insert(self.Callbacks, self.Config.Callback)
    end

    self.Row = UI.transparent({
        Name = tostring(self.Config.Name or "Element") .. "Row",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })

    self.RowLayout = UI.listLayout(0)
    self.RowLayout.Parent = self.Row

    table.insert(section.Elements, self)
    section:PlaceElement(self)
    section:UpdateOrder()

    return self
end

function Element:OnChanged(callback)
    if isCallable(callback) then
        table.insert(self.Callbacks, callback)
    end
    return self
end

function Element:Set(value, silent)
    return self:SetValue(value, silent)
end

function Element:Get()
    return self.Value
end

function Element:GetValue()
    return self.Value
end

function Element:SetValue(value, silent)
    self.Value = value
    if self.Flag then
        Argon.Flags[self.Flag] = value
    end
    if not silent then
        self:Fire(value)
    end
    return self
end

function Element:Fire(...)
    if self.Destroyed then
        return
    end
    for _, callback in ipairs(self.Callbacks) do
        local results = pack(pcall(callback, ...))
        if not results[1] then
            warn("[Argon] element callback failed: " .. tostring(results[2]))
        end
    end
    if self.Flag then
        fireFlag(self.Flag, self.Value, "element")
        ConfigStore.scheduleSave()
    end
    if self.Window then
        self.Window:FireFlagChanged(self.Flag, self.Value)
    end
end

function Element:Refresh()
    return self
end

function Element:SetVisible(visible)
    self.Visible = visible ~= false
    self.Row.Visible = self.Visible
    self.Section:UpdateOrder()
    return self
end

function Element:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    if self.Row then
        self.Row.Active = not self.Disabled
    end
    return self
end

function Element:SetName(name)
    if self.NameLabel then
        self.NameLabel.Text = tostring(name)
    end
    return self
end

function Element:SetDescription(text)
    if self.DescriptionLabel then
        self.DescriptionLabel.Text = tostring(text)
        self.DescriptionLabel.Visible = text ~= nil and text ~= ""
    end
    return self
end

function Element:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    if self.Flag then
        unregisterFlagOwner(self.Flag, self)
    end
    for _, applier in ipairs(self.ThemeAppliers) do
        removeThemed(applier)
    end
    for index, element in ipairs(self.Section.Elements) do
        if element == self then
            table.remove(self.Section.Elements, index)
            break
        end
    end
    if self.Row then
        DestroyInstance(self.Row)
    end
    self.Section:UpdateOrder()
end

function Element:applyTheme(fn)
    table.insert(self.ThemeAppliers, fn)
    registerThemed(fn)
    return self
end

-- Shared row chrome: name, description, optional icon, optional hover state.
-- Returns the right-hand slot frame where the control is built.
function Element:buildRow(options)
    options = options or {}
    local height = options.Height or Argon.Theme.RowHeight

    self.Row.Size = UDim2.new(self.Width == "half" and 0.5 or 1, self.Width == "half" and -3 or 0, 0, height)
    self.Row.AutomaticSize = Enum.AutomaticSize.None
    self.Row.BackgroundColor3 = C("Surface")
    self.Row.BackgroundTransparency = 0.35
    self.Row.ClipsDescendants = true

    local corner = UI.corner(UDim.new(0, Argon.Theme.Corner))
    corner.Parent = self.Row

    local stroke = UI.stroke(C("Stroke"), 1, 0.55)
    stroke.Parent = self.Row
    self.RowStroke = stroke

    local padding = UI.padding(0, 10, 0, options.Icon and 8 or 12)
    padding.Parent = self.Row
    self.RowPadding = padding

    if options.Icon then
        local iconBox = UI.transparent({
            Parent = self.Row,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(0, 22, 1, 0),
        })
        UI.glyph(tostring(options.Icon), options.IconSize or 14, C("TextMuted"), {
            Parent = iconBox,
            Size = UDim2.new(1, 0, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        padding.PaddingLeft = UDim.new(0, 38)
    end

    local textHolder = UI.transparent({
        Parent = self.Row,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, options.Reserved or -110, 1, 0),
    })
    self.TextHolder = textHolder

    self.NameLabel = UI.label({
        Parent = textHolder,
        Position = UDim2.new(0, 0, 0.5, options.HasDescription and -8 or 0),
        AnchorPoint = UDim2.new(0, options.HasDescription and 0 or 0.5, 0, 0),
        Size = UDim2.new(1, 0, 0, 16),
        Text = tostring(self.Config.Name or ""),
        TextSize = Argon.Theme.TextSize,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("Text"),
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    if options.Description ~= false and self.Config.Description and self.Config.Description ~= "" then
        self.DescriptionLabel = UI.label({
            Parent = textHolder,
            Position = UDim2.new(0, 0, 0.5, 8),
            Size = UDim2.new(1, 0, 0, 14),
            Text = tostring(self.Config.Description),
            TextSize = Argon.Theme.TextSizeTiny,
            TextColor3 = C("TextDim"),
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextYAlignment = Enum.TextYAlignment.Center,
        })
    end

    self.RightSlot = UI.transparent({
        Parent = self.Row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, options.SlotWidth or 104, 1, 0),
    })

    if self.Config.Tooltip then
        attachTooltip(self.Row, self.Config.Tooltip)
    end

    if options.Hover ~= false then
        Connect(self.Row.MouseEnter, function()
            if self.Disabled then
                return
            end
            animate(self.Row, { BackgroundTransparency = 0 }, 0.12)
            animate(self.RowStroke, { Transparency = 0.3 }, 0.12)
        end)
        Connect(self.Row.MouseLeave, function()
            animate(self.Row, { BackgroundTransparency = 0.35 }, 0.12)
            animate(self.RowStroke, { Transparency = 0.55 }, 0.12)
        end)
    end

    self:applyTheme(function(theme)
        self.Row.BackgroundColor3 = theme.Surface
        self.RowStroke.Color = theme.Stroke
        self.NameLabel.TextColor3 = theme.Text
        if self.DescriptionLabel then
            self.DescriptionLabel.TextColor3 = theme.TextDim
        end
    end)

    return self.RightSlot
end

Argon.Element = Element
Argon.UI = UI
Argon.Math = Math
Argon.String = String
Argon.Color = Color

-- ============================================================================
-- 20. SECTION
-- ============================================================================
-- A section is a titled, collapsible card that owns a vertical list of rows.
-- Half-width rows are packed two per line automatically.

local Section = {}
Section.__index = Section

function Section.new(page, config)
    local self = setmetatable({}, Section)

    self.Page = page
    self.Window = page.Window
    self.Name = tostring(config.Name or "Section")
    self.Icon = config.Icon
    self.Elements = {}
    self.Containers = {}
    self.Collapsed = config.Collapsed and true or false
    self.Index = #page.Sections + 1
    self.PairFrame = nil
    self.PairCount = 0
    self.Destroyed = false

    self:Build(config)
    table.insert(page.Sections, self)
    page:UpdateOrder()

    return self
end

function Section:Build(config)
    local theme = Argon.Theme

    self.Frame = UI.frame({
        Parent = self.Page.Content,
        Name = "Section_" .. tostring(self.Index),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.25,
        LayoutOrder = self.Index,
    })
    UI.corner(UDim.new(0, theme.CornerLarge)).Parent = self.Frame
    self.Stroke = UI.stroke(theme.Stroke, 1, 0.45)
    self.Stroke.Parent = self.Frame

    -- header ------------------------------------------------------------
    self.Header = UI.button({
        Parent = self.Frame,
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        Text = "",
        ClipsDescendants = true,
    })

    if self.Icon then
        self.IconLabel = UI.glyph(tostring(self.Icon), 14, theme.TextMuted, {
            Parent = self.Header,
            Position = UDim2.new(0, 12, 0, 0),
            Size = UDim2.new(0, 20, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
        })
    end

    self.TitleLabel = UI.label({
        Parent = self.Header,
        Position = UDim2.new(0, self.Icon and 38 or 14, 0, 0),
        Size = UDim2.new(1, self.Icon and -100 or -76, 1, 0),
        Text = self.Name:upper(),
        TextSize = Argon.Theme.TextSizeTiny,
        Font = theme.FontBold,
        TextColor3 = theme.TextMuted,
    })

    self.CountBadge = UI.frame({
        Parent = self.Header,
        Position = UDim2.new(0, self.Icon and 38 or 14, 0, 0),
        Size = UDim2.new(0, 0, 0, 0),
        Visible = false,
        BackgroundColor3 = theme.SurfaceHigh,
    })
    UI.corner(UDim.new(0, 4)).Parent = self.CountBadge

    self.Chevron = UI.glyph("⌄", 14, theme.TextDim, {
        Parent = self.Header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0, 16, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    if self.Collapsed then
        self.Chevron.Rotation = -90
    end

    self.HeaderControls = UI.transparent({
        Parent = self.Header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -34, 0.5, 0),
        Size = UDim2.new(0, 0, 0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
    })
    UI.listLayout(6, true, Enum.HorizontalAlignment.Right).Parent = self.HeaderControls

    -- content -----------------------------------------------------------
    self.Content = UI.transparent({
        Parent = self.Frame,
        Position = UDim2.new(0, 0, 0, 38),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = not self.Collapsed,
    })
    UI.padding(0, 8, 10, 8).Parent = self.Content
    self.ContentLayout = UI.listLayout(4)
    self.ContentLayout.Parent = self.Content

    Connect(self.Header.MouseButton1Click, function()
        self:Collapse(not self.Collapsed)
    end)
    Connect(self.Header.MouseEnter, function()
        animate(self.Header, { BackgroundTransparency = 0.93 }, 0.12)
    end)
    Connect(self.Header.MouseLeave, function()
        animate(self.Header, { BackgroundTransparency = 1 }, 0.12)
    end)

    registerThemed(function(palette)
        self.Frame.BackgroundColor3 = palette.Surface
        self.Stroke.Color = palette.Stroke
        self.TitleLabel.TextColor3 = palette.TextMuted
        self.Chevron.TextColor3 = palette.TextDim
        if self.IconLabel then
            self.IconLabel.TextColor3 = palette.TextMuted
        end
    end)
end

function Section:Collapse(collapsed)
    self.Collapsed = collapsed and true or false
    self.Content.Visible = not self.Collapsed
    animate(self.Chevron, { Rotation = self.Collapsed and -90 or 0 }, 0.14)
    return self
end

function Section:Toggle()
    return self:Collapse(not self.Collapsed)
end

function Section:SetName(name)
    self.Name = tostring(name)
    self.TitleLabel.Text = self.Name:upper()
    return self
end

function Section:SetVisible(visible, anim)
    self.Frame.Visible = visible ~= false
    if anim and visible then
        self.Frame.BackgroundTransparency = 1
        animate(self.Frame, { BackgroundTransparency = 0.25 }, 0.15)
    end
    self:UpdateOrder()
    return self
end

function Section:AddHeaderControl(instance, width)
    instance.Parent = self.HeaderControls
    instance.Size = UDim2.new(0, width or 22, 0, 20)
    self.HeaderControls.Size = UDim2.new(0, 0, 0, 22)
    return instance
end

-- Place a row either in the content stack or in a transient two-column pair.
function Section:PlaceElement(element)
    if element.Width == "half" then
        if not self.PairFrame or self.PairCount >= 2 then
            self.PairFrame = UI.transparent({
                Parent = self.Content,
                Size = UDim2.new(1, 0, 0, Argon.Theme.RowHeight),
            })
            self.PairLayout = UI.listLayout(6, true)
            self.PairLayout.Parent = self.PairFrame
            self.PairCount = 0
            table.insert(self.Containers, self.PairFrame)
        end
        element.Row.Parent = self.PairFrame
        element.Row.Size = UDim2.new(0.5, -3, 1, 0)
        element.Row.AutomaticSize = Enum.AutomaticSize.None
        self.PairCount = self.PairCount + 1
        if self.PairCount >= 2 then
            self.PairFrame = nil
            self.PairCount = 0
        end
    else
        self.PairFrame = nil
        self.PairCount = 0
        element.Row.Parent = self.Content
        table.insert(self.Containers, element.Row)
    end
    return element
end

function Section:UpdateOrder()
    local order = 0
    for _, container in ipairs(self.Containers) do
        if container.Parent then
            order = order + 1
            container.LayoutOrder = order
        end
    end
    local visible = 0
    for _, element in ipairs(self.Elements) do
        if element.Row and element.Row.Visible then
            visible = visible + 1
        end
    end
    if self.CountBadge then
        self.CountBadge.Visible = visible > 0
        self.CountBadge.Size = UDim2.new(0, 6 + #tostring(visible) * 7, 0, 16)
        self.CountBadge.Position = UDim2.new(0, (self.Icon and 38 or 14) + self.TitleLabel.TextBounds.X + 8, 0.5, -8)
        local existing = self.CountBadge:FindFirstChild("Count")
        if not existing then
            existing = UI.label({
                Name = "Count",
                Parent = self.CountBadge,
                Size = UDim2.new(1, 0, 1, 0),
                TextSize = 9,
                Font = Argon.Theme.FontBold,
                TextColor3 = Argon.Theme.TextMuted,
                TextXAlignment = Enum.TextXAlignment.Center,
            })
        end
        existing.Text = tostring(visible)
    end
end

function Section:Refresh()
    for _, element in ipairs(self.Elements) do
        if element.Refresh then
            pcall(element.Refresh, element)
        end
    end
    return self
end

function Section:Clear()
    local elements = {}
    for index, element in ipairs(self.Elements) do
        elements[index] = element
    end
    for _, element in ipairs(elements) do
        if element.Destroy then
            pcall(element.Destroy, element)
        end
    end
    for _, container in ipairs(self.Containers) do
        if container.Parent then
            DestroyInstance(container)
        end
    end
    self.Elements = {}
    self.Containers = {}
    self.PairFrame = nil
    self.PairCount = 0
    return self
end

function Section:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    self:Clear()
    for index, existing in ipairs(self.Page.Sections) do
        if existing == self then
            table.remove(self.Page.Sections, index)
            break
        end
    end
    DestroyInstance(self.Frame)
    self.Page:UpdateOrder()
end

-- ============================================================================
-- 21. PAGE
-- ============================================================================
-- A page is one navigable screen: header, optional search + filter pills, a
-- scrolling section stack, and a sticky action bar.

local Page = {}
Page.__index = Page

function Page.new(window, config)
    local self = setmetatable({}, Page)

    self.Window = window
    self.Name = tostring(config.Name or "Page")
    self.Subtitle = config.Subtitle or ""
    self.Icon = config.Icon or "▤"
    self.RailIcon = config.RailIcon or self.Icon
    self.Sections = {}
    self.Elements = {}
    self.Index = #window.Pages + 1
    self.Group = config.Group or "MAIN"
    self.Visible = false
    self.Destroyed = false
    self.Filter = nil
    self.Query = ""
    self.SyncedAt = os.time()
    self.ShowSearch = config.Search ~= false
    self.ShowRail = config.Rail ~= false
    self.Closable = config.Closable and true or false
    self.Options = config

    self:Build(config)
    table.insert(window.Pages, self)
    if self.Window.NavHolder then
        self.Window:RebuildNav()
    end
    return self
end

function Page:Build(config)
    local theme = Argon.Theme

    self.Frame = UI.transparent({
        Parent = self.Window.Content,
        Name = "Page_" .. tostring(self.Index),
        Size = UDim2.new(1, 0, 1, 0),
        Visible = false,
    })

    -- page header -------------------------------------------------------
    self.Header = UI.transparent({
        Parent = self.Frame,
        Size = UDim2.new(1, 0, 0, 54),
    })

    if self.Icon then
        self.HeaderIcon = UI.frame({
            Parent = self.Header,
            Position = UDim2.new(0, 0, 0, 10),
            Size = UDim2.new(0, 28, 0, 28),
            BackgroundColor3 = theme.Accent,
            BackgroundTransparency = 0.88,
        })
        UI.corner(UDim.new(0, 7)).Parent = self.HeaderIcon
        UI.glyph(tostring(self.Icon), 13, theme.Accent, {
            Parent = self.HeaderIcon,
            Size = UDim2.new(1, 0, 1, 0),
        })
    end

    self.TitleLabel = UI.label({
        Parent = self.Header,
        Position = UDim2.new(0, self.Icon and 38 or 0, 0, 8),
        Size = UDim2.new(1, -160, 0, 20),
        Text = self.Name,
        TextSize = Argon.Theme.TextSizeTitle,
        Font = theme.FontBold,
        TextColor3 = theme.Text,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    self.SubtitleLabel = UI.label({
        Parent = self.Header,
        Position = UDim2.new(0, self.Icon and 38 or 0, 0, 29),
        Size = UDim2.new(1, -160, 0, 14),
        Text = "",
        TextSize = Argon.Theme.TextSizeTiny,
        TextColor3 = theme.TextDim,
    })
    self:SetSubtitle(self.Subtitle)

    self.HeaderButtons = UI.transparent({
        Parent = self.Header,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -70, 0, 10),
        Size = UDim2.new(0, 0, 0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
    })
    UI.listLayout(6, true, Enum.HorizontalAlignment.Right).Parent = self.HeaderButtons

    self.RefreshButton = self:MakeHeaderButton("⟳", "Refresh", function()
        self:Refresh()
        self.SyncedAt = os.time()
        self:SetSubtitle(self.Subtitle)
    end)

    if self.Closable then
        self.CloseButton = self:MakeHeaderButton("×", "Close", function()
            if self.Window.AutoClosePage then
                self.Window:ClosePage()
            else
                self.Window:SelectPage(self.Window.Pages[1])
            end
        end)
    end

    -- toolbar row: search + pills ---------------------------------------
    self.Toolbar = UI.transparent({
        Parent = self.Frame,
        Position = UDim2.new(0, 0, 0, 54),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    self.ToolbarLayout = UI.listLayout(8)
    self.ToolbarLayout.Parent = self.Toolbar

    if self.ShowSearch then
        self.SearchBox = self:BuildSearch()
    end

    self.Pills = nil

    -- scroll body -------------------------------------------------------
    self.Body = UI.transparent({
        Parent = self.Frame,
        Position = UDim2.new(0, 0, 0, 54),
        Size = UDim2.new(1, 0, 1, -54),
    })

    self.Scroller = UI.scroller({
        Parent = self.Body,
        Size = UDim2.new(1, 0, 1, 0),
    })
    self.Scroller.Position = UDim2.new(0, 0, 0, 0)
    self.Content = UI.transparent({
        Parent = self.Scroller,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    UI.padding(0, 2, 10, 2).Parent = self.Content
    self.ContentLayout = UI.listLayout(8)
    self.ContentLayout.Parent = self.Content
    self.UpdateCanvas = bindCanvas(self.Scroller, self.ContentLayout, 16)

    self.UpdateBodyBounds = function()
        local top = 54 + math.max(self.Toolbar.AbsoluteSize.Y, 0)
        local bottom = (self.ActionBar and self.ActionBar.Visible) and 56 or 0
        self.Body.Position = UDim2.new(0, 0, 0, top)
        self.Body.Size = UDim2.new(1, 0, 1, -(top + bottom))
    end
    Connect(self.Toolbar:GetPropertyChangedSignal("AbsoluteSize"), self.UpdateBodyBounds)
    self.UpdateBodyBounds()

    -- sticky action bar --------------------------------------------------
    self.ActionBar = UI.transparent({
        Parent = self.Frame,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = false,
    })

    registerThemed(function(palette)
        self.TitleLabel.TextColor3 = palette.Text
        self.SubtitleLabel.TextColor3 = palette.TextDim
        if self.HeaderIcon then
            self.HeaderIcon.BackgroundColor3 = palette.Accent
        end
        if self.SearchFrame then
            self.SearchFrame.BackgroundColor3 = palette.Input
            self.SearchFrameStroke.Color = palette.Stroke
        end
    end)
end

function Page:MakeHeaderButton(glyph, tooltip, callback)
    local button = UI.button({
        Parent = self.HeaderButtons,
        Size = UDim2.new(0, 28, 0, 28),
        BackgroundColor3 = C("Surface"),
        BackgroundTransparency = 0.4,
        Text = glyph,
        TextSize = 14,
        TextColor3 = C("TextMuted"),
        Font = Argon.Theme.FontBold,
    })
    UI.corner(UDim.new(0, 7)).Parent = button
    Connect(button.MouseEnter, function()
        animate(button, { BackgroundTransparency = 0, BackgroundColor3 = C("SurfaceHover") }, 0.1)
    end)
    Connect(button.MouseLeave, function()
        animate(button, { BackgroundTransparency = 0.4, BackgroundColor3 = C("Surface") }, 0.1)
    end)
    Connect(button.MouseButton1Click, function()
        pcall(callback)
    end)
    if tooltip then
        attachTooltip(button, tooltip)
    end
    return button
end

function Page:BuildSearch()
    self.SearchFrame = UI.frame({
        Parent = self.Toolbar,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C("Input"),
        BackgroundTransparency = 0,
        LayoutOrder = 1,
    })
    UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = self.SearchFrame
    self.SearchFrameStroke = UI.stroke(C("Stroke"), 1, 0.2)
    self.SearchFrameStroke.Parent = self.SearchFrame
    UI.padding(0, 10, 0, 10).Parent = self.SearchFrame

    UI.glyph("⌕", 14, C("TextDim"), {
        Parent = self.SearchFrame,
        Position = UDim2.new(0, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 16, 0, 16),
    })

    self.SearchInput = UI.textBox({
        Parent = self.SearchFrame,
        Position = UDim2.new(0, 22, 0, 0),
        Size = UDim2.new(1, -52, 1, 0),
        BackgroundTransparency = 1,
        Font = Argon.Theme.Font,
        TextSize = Argon.Theme.TextSizeSmall,
        PlaceholderText = "Search features",
        TextColor3 = C("Text"),
        PlaceholderColor3 = C("TextDim"),
    })

    self.SearchClear = UI.button({
        Parent = self.SearchFrame,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 18, 0, 18),
        BackgroundColor3 = C("SurfaceHigh"),
        Text = "×",
        TextSize = 11,
        TextColor3 = C("TextMuted"),
        Visible = false,
    })
    UI.corner(UDim.new(1, 0)).Parent = self.SearchClear

    Connect(self.SearchInput:GetPropertyChangedSignal("Text"), function()
        self.Query = self.SearchInput.Text
        self.SearchClear.Visible = self.Query ~= ""
        self:ApplyFilter()
    end)

    Connect(self.SearchClear.MouseButton1Click, function()
        self.SearchInput.Text = ""
        self.Query = ""
        self.SearchClear.Visible = false
        self:ApplyFilter()
    end)

    Connect(self.SearchInput.Focused, function()
        animate(self.SearchFrameStroke, { Color = C("Accent"), Transparency = 0.4 }, 0.12)
    end)
    Connect(self.SearchInput.FocusLost, function()
        animate(self.SearchFrameStroke, { Color = C("Stroke"), Transparency = 0.2 }, 0.12)
    end)

    return self.SearchFrame
end

function Page:AutoSection(name)
    name = tostring(name or "Content")
    self._autoSections = self._autoSections or {}
    local existing = self._autoSections[name]
    if existing and not existing.Destroyed then
        return existing
    end
    local section = self:Section({ Name = name, Collapsible = false })
    self._autoSections[name] = section
    return section
end

-- Every page-level component factory forwards to the section the script names,
-- or to an implicit one, so `Page:StatCard{...}` works without bookkeeping.
local function pageForward(page, method, config)
    config = config or {}
    local section = page:AutoSection(config.Section)
    return section[method](section, config)
end

function Page:Steps(config)
    return pageForward(self, "Steps", config)
end

function Page:StatCard(config)
    return pageForward(self, "StatCard", config)
end

function Page:FileRow(config)
    return pageForward(self, "FileRow", config)
end

function Page:Callout(config)
    return pageForward(self, "Callout", config)
end

function Page:CardList(config)
    return pageForward(self, "CardList", config)
end

function Page:Section(config)
    local section = Section.new(self, config or {})
    return section
end

function Page:Search(config)
    if not self.SearchInput then
        return nil
    end
    if type(config) == "table" and config.Placeholder then
        self.SearchInput.PlaceholderText = tostring(config.Placeholder)
    end
    if type(config) == "string" then
        self.SearchInput.Text = config
    end
    return self.SearchInput
end

function Page:Pills(config)
    config = config or {}
    local options = config.Options or {
        { Name = "All", Value = "all" },
        { Name = "Free", Value = "free" },
        { Name = "Premium", Value = "premium" },
    }

    self.PillRow = UI.transparent({
        Parent = self.Toolbar,
        Size = UDim2.new(1, 0, 0, 28),
        LayoutOrder = 2,
    })
    self.PillRowLayout = UI.listLayout(6, true)
    self.PillRowLayout.Parent = self.PillRow

    self.PillButtons = {}
    self.ActivePill = config.Default or options[1].Value

    for index, option in ipairs(options) do
        local button = UI.button({
            Parent = self.PillRow,
            Size = UDim2.new(0, 46, 0, 26),
            BackgroundColor3 = C("Surface"),
            Text = tostring(option.Name),
            TextSize = Argon.Theme.TextSizeTiny,
            Font = Argon.Theme.FontMedium,
            TextColor3 = C("TextMuted"),
            LayoutOrder = index,
        })
        UI.corner(UDim.new(0, 6)).Parent = button
        self.PillButtons[option.Value] = { Button = button, Option = option }

        Connect(button.MouseButton1Click, function()
            self:SetPill(option.Value)
            if config.Callback then
                pcall(config.Callback, option.Value)
            end
        end)
    end

    self:SetPill(self.ActivePill)
    return self.PillRow
end

function Page:SetPill(value)
    self.ActivePill = value
    for key, entry in pairs(self.PillButtons) do
        local active = key == value
        entry.Button.BackgroundColor3 = active and C("SurfaceActive") or C("Surface")
        entry.Button.TextColor3 = active and C("Text") or C("TextMuted")
        entry.Button.Size = UDim2.new(0, entry.Option.Width or 46, 0, 26)
        if entry.Option.Name == "All" then
            entry.Button.Size = UDim2.new(0, 40, 0, 26)
        end
    end
    self:ApplyFilter()
    return self
end

function Page:Action(text, callback)
    self.ActionBar.Visible = true
    self.ActionBar.Size = UDim2.new(1, 0, 0, 56)

    if self._actionMode == "split" and self.PrimaryButton then
        self.PrimaryButton.Text = tostring(text or "")
        for _, connection in ipairs(self.ActionConnections or {}) do
            Disconnect(connection)
        end
        self.ActionConnections = {}
        table.insert(self.ActionConnections, Connect(self.PrimaryButton.MouseButton1Click, function()
            if isCallable(callback) then
                pcall(callback)
            end
        end))
        return self.PrimaryButton
    end

    if not self.ActionButton then
        local split = self._actionMode == "split"
        self.ActionButton = UI.button({
            Parent = self.ActionBar,
            Position = split and UDim2.new(0, 104, 0, 10) or UDim2.new(0, 0, 0, 10),
            Size = split and UDim2.new(1, -104, 0, 36) or UDim2.new(1, 0, 0, 36),
            BackgroundColor3 = accent(),
            Text = "",
            TextSize = Argon.Theme.TextSize,
            Font = Argon.Theme.FontMedium,
            TextColor3 = C("AccentText"),
        })
        UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = self.ActionButton
        self.ActionStroke = UI.stroke(C("Text"), 1, 0.9)
        self.ActionStroke.Parent = self.ActionButton

        -- Four visual states, all of them theme derived: resting, hovered
        -- (lighter + hairline inner stroke), pressed (darker) and disabled
        -- (accent washed out, text at 45%). The disabled state also opts out of
        -- every hover animation, which is what makes a locked button read as
        -- locked instead of "dead but bright".
        local function renderActionButton()
            local disabled = self.ActionEnabled == false
            if disabled then
                self.ActionButton.BackgroundColor3 = accent()
                self.ActionButton.BackgroundTransparency = 0.68
                self.ActionButton.TextColor3 = C("AccentText")
                self.ActionStroke.Transparency = 1
                return
            end
            self.ActionButton.BackgroundTransparency = 0
            self.ActionButton.TextColor3 = C("AccentText")
            if self.ActionPressed then
                self.ActionButton.BackgroundColor3 = Color.darken(accent(), 0.1)
                self.ActionStroke.Transparency = 1
            elseif self.ActionHovered then
                self.ActionButton.BackgroundColor3 = Color.lighten(accent(), 0.1)
                self.ActionStroke.Transparency = 0.82
            else
                self.ActionButton.BackgroundColor3 = accent()
                self.ActionStroke.Transparency = 1
            end
        end
        self.RenderActionButton = renderActionButton

        Connect(self.ActionButton.MouseEnter, function()
            self.ActionHovered = true
            if self.ActionEnabled ~= false then
                animate(self.ActionButton, { BackgroundColor3 = Color.lighten(accent(), 0.1) }, 0.12)
                self.ActionStroke.Transparency = 0.82
            end
        end)
        Connect(self.ActionButton.MouseLeave, function()
            self.ActionHovered = false
            self.ActionPressed = false
            if self.ActionEnabled ~= false then
                animate(self.ActionButton, { BackgroundColor3 = accent(), BackgroundTransparency = 0 }, 0.12)
                self.ActionStroke.Transparency = 1
            end
        end)
        Connect(self.ActionButton.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                self.ActionPressed = true
                if self.ActionEnabled ~= false then
                    animate(self.ActionButton, { BackgroundColor3 = Color.darken(accent(), 0.1) }, 0.08)
                end
            end
        end)
        Connect(self.ActionButton.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                self.ActionPressed = false
                if self.ActionEnabled ~= false then
                    animate(self.ActionButton, {
                        BackgroundColor3 = self.ActionHovered and Color.lighten(accent(), 0.1) or accent(),
                    }, 0.1)
                end
            end
        end)
    end

    self.ActionButton.Text = tostring(text or "")
    for _, connection in ipairs(self.ActionConnections or {}) do
        Disconnect(connection)
    end
    self.ActionConnections = {}
    table.insert(self.ActionConnections, Connect(self.ActionButton.MouseButton1Click, function()
        -- Executors deliver clicks straight to the signal, so `Active = false`
        -- is only cosmetic: the handler has to refuse the click itself.
        if self.ActionEnabled == false then
            return
        end
        if callback then
            pcall(callback)
        end
    end))

    if self.UpdateBodyBounds then
        self.UpdateBodyBounds()
    end
    return self.ActionButton
end

-- A two-button footer: a ghost Back and an accent Primary. Named `Footer`
-- because `ActionBar` is the frame that hosts it. A locked wizard step has to
-- look locked, so it shares Page:Action's state model.
function Page:Footer(config)
    config = config or {}
    self._actionMode = "split"
    self.ActionBar.Visible = true
    self.ActionBar.Size = UDim2.new(1, 0, 0, 56)

    if not self.BackButton then
        self.BackButton = UI.button({
            Parent = self.ActionBar,
            Position = UDim2.new(0, 0, 0, 10),
            Size = UDim2.new(0, 96, 0, 36),
            BackgroundColor3 = C("SurfaceHigh"),
            BackgroundTransparency = 0.25,
            Text = tostring(config.Back == true and "Back" or (config.Back or "")),
            TextSize = Argon.Theme.TextSizeSmall,
            Font = Argon.Theme.FontMedium,
            TextColor3 = C("Text"),
        })
        UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = self.BackButton
        self.BackStroke = UI.stroke(C("Stroke"), 1, 0.35)
        self.BackStroke.Parent = self.BackButton

        Connect(self.BackButton.MouseEnter, function()
            animate(self.BackButton, { BackgroundColor3 = C("SurfaceActive"), BackgroundTransparency = 0 }, 0.1)
            animate(self.BackStroke, { Transparency = 0.15 }, 0.1)
        end)
        Connect(self.BackButton.MouseLeave, function()
            animate(self.BackButton, { BackgroundColor3 = C("SurfaceHigh"), BackgroundTransparency = 0.25 }, 0.1)
            animate(self.BackStroke, { Transparency = 0.35 }, 0.1)
        end)
        Connect(self.BackButton.MouseButton1Click, function()
            if isCallable(config.OnBack) then
                pcall(config.OnBack, self)
            end
        end)
    end

    local primary = self:Action(tostring(config.Primary or config.Next or "Continue"), config.OnPrimary)
    self.PrimaryButton = primary
    self:SetPrimaryEnabled(config.Disabled == false and true or (config.Enabled ~= false and config.Disabled ~= true))
    self:SetBackVisible(config.Back ~= false and config.Back ~= nil)
    return self
end

function Page:SetPrimaryText(text)
    if self.PrimaryButton then
        self.PrimaryButton.Text = tostring(text or "")
    end
    return self
end

function Page:SetPrimaryEnabled(enabled)
    if self.PrimaryButton then
        self.ActionEnabled = enabled ~= false
        self.PrimaryButton.Active = self.ActionEnabled
        if self.RenderActionButton then
            self.RenderActionButton()
        end
    end
    return self
end

function Page:SetBackVisible(visible)
    if self.BackButton then
        self.BackButton.Visible = visible ~= false
    end
    return self
end

function Page:SetBackText(text)
    if self.BackButton then
        self.BackButton.Text = tostring(text or "")
    end
    return self
end

function Page:SetActionEnabled(enabled)
    self.ActionEnabled = enabled ~= false
    if not self.ActionButton then
        return self
    end
    self.ActionButton.Active = self.ActionEnabled
    if self.RenderActionButton then
        self.RenderActionButton()
    end
    return self
end

function Page:IsActionEnabled()
    return self.ActionEnabled ~= false
end

function Page:SetSubtitle(text)
    self.Subtitle = tostring(text or "")
    local parts = {}
    if self.Subtitle ~= "" then
        parts[#parts + 1] = self.Subtitle
    end
    if self.ShowCount ~= false then
        local count = 0
        for _, section in ipairs(self.Sections) do
            count = count + #section.Elements
        end
        if count > 0 then
            parts[#parts + 1] = tostring(count) .. (count == 1 and " feature" or " features")
        end
    end
    parts[#parts + 1] = "synced " .. String.timeAgo(self.SyncedAt)
    self.SubtitleLabel.Text = table.concat(parts, "  ·  ")
    return self
end

function Page:ApplyFilter()
    local query = String.trim(self.Query or ""):lower()
    local pill = self.ActivePill or "all"

    for _, section in ipairs(self.Sections) do
        local anyVisible = false
        for _, element in ipairs(section.Elements) do
            local visible = true

            if query ~= "" and element.SearchText then
                visible = element:SearchText(query)
            elseif query ~= "" then
                local name = (element.Config and element.Config.Name or ""):lower()
                local description = (element.Config and element.Config.Description or ""):lower()
                visible = name:find(query, 1, true) ~= nil or description:find(query, 1, true) ~= nil
            end

            if visible and pill ~= "all" and element.Tier then
                visible = element.Tier == pill
            end

            if visible and element.IsCard and element.Config.Searchable == false then
                visible = true
            end

            if element.SetVisible and not (element.IsCard and element.Pinned) then
                element:SetVisible(visible)
            end
            if visible then
                anyVisible = true
            end
        end
        section:SetVisible(anyVisible or (#section.Elements == 0 and query == ""))
    end

    if self.UpdateCanvas then
        self.UpdateCanvas()
    end
    self:SetSubtitle(self.Subtitle)
    return self
end

function Page:UpdateOrder()
    local order = 0
    for _, section in ipairs(self.Sections) do
        if section.Frame.Parent then
            order = order + 1
            section.Frame.LayoutOrder = order
        end
    end
    if self.Window then
        self:SetSubtitle(self.Subtitle)
    end
end

function Page:Refresh()
    for _, section in ipairs(self.Sections) do
        section:Refresh()
    end
    self:ApplyFilter()
    self:SetSubtitle(self.Subtitle)
    return self
end

function Page:SetVisible(visible)
    self.Visible = visible ~= false
    self.Frame.Visible = self.Visible
    if self.Visible then
        self.SyncedAt = self.SyncedAt or os.time()
        self:Refresh()
    end
    return self
end

function Page:ScrollToTop()
    self.Scroller.CanvasPosition = Vector3.new(0, 0, 0)
    return self
end

function Page:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for _, section in ipairs(self.Sections) do
        section:Destroy()
    end
    for index, existing in ipairs(self.Window.Pages) do
        if existing == self then
            table.remove(self.Window.Pages, index)
            break
        end
    end
    if self.Window.ActivePage == self then
        self.Window.ActivePage = nil
    end
    DestroyInstance(self.Frame)
    self.Window:RebuildNav()
    if not self.Window.Destroyed then
        self.Window:UpdateChrome(false)
    end
end

-- ============================================================================
-- 22. WINDOW
-- ============================================================================

local Window = {}
Window.__index = Window

local WindowZ = 100

function Window.new(options)
    local self = setmetatable({}, Window)

    options = options or {}
    self.Options = options
    self.Pages = {}
    self.FlagListeners = {}
    self.Destroyed = false
    self.Visible = true
    self.Minimized = false
    self.ActivePage = nil
    self.Width = tonumber(options.Width) or 640
    self.Height = tonumber(options.Height) or 480

    self.Title = tostring(options.Title or "Argon")
    self.Subtitle = tostring(options.Subtitle or ("v" .. Argon.Version))
    self.User = options.User or { Name = LocalPlayer and LocalPlayer.Name or "user", Tag = "User" }
    self.ShowRail = options.Rail ~= false
    self.ShowSidebar = options.Sidebar ~= false
    self.ShowUser = options.User ~= false
    self.ShowThemeSwitch = options.ThemeSwitch ~= false
    self.Resizable = options.Resizable ~= false
    self.RailWidth = tonumber(options.RailWidth) or Argon.Theme.RailWidth
    self.SidebarWidth = tonumber(options.SidebarWidth) or Argon.Theme.SidebarWidth

    -- chrome layout -------------------------------------------------------
    -- Layout = "side"  : rail + sidebar + page pane, luau.pro style. While the
    --                    pointer is outside the window the sidebar is collapsed,
    --                    and when no page is open the window is the rail alone.
    -- Layout = "square" : one narrow column -- rail + page pane, no sidebar.
    -- `Width` always describes the *expanded* window, so the opened state is
    -- exactly the size the script asked for.
    self.Layout = (options.Layout == "square") and "square" or "side"
    self.HoverOpen = options.HoverOpen ~= false
    self.CollapseDelay = tonumber(options.CollapseDelay) or 0.14
    self.AutoClosePage = options.AutoClosePage ~= false
    if type(options.RailOnly) == "boolean" then
        self.RailOnly = options.RailOnly
    else
        self.RailOnly = self.Layout == "side"
    end
    if self.Layout == "square" then
        self.HoverOpen = false
        self.ShowSidebar = false
        self.AutoClosePage = false
    end
    if Argon.IsMobile and Argon:IsMobile() then
        self.HoverOpen = false
    end
    self.hovered = false
    self.SidebarShown = not self.HoverOpen
    self.EffectiveWidth = tonumber(options.Width) or self.Width
    self._chromeShift = 0
    self._hoverToken = nil
    self._hoverProbe = nil

    WindowZ = WindowZ + 1
    self.Gui = createScreenGui("Argon_" .. tostring(WindowZ), (options.DisplayOrder or 100) + WindowZ)

    self:BuildShell()

    table.insert(Argon.Windows, self)
    table.insert(Argon.Instances, self.Gui)

    if options.Theme and Argon.Themes[options.Theme] then
        Argon:SetTheme(options.Theme)
    end
    if options.Accent and isColor(options.Accent) then
        Argon:SetAccent(options.Accent)
    end

    self.ToggleKey = options.ToggleKey
    if self.ToggleKey then
        Connect(UserInputService.InputBegan, function(input, processed)
            if processed then
                return
            end
            if input.KeyCode == self.ToggleKey then
                self:Toggle()
            end
        end)
    end

    if options.AutoLoad then
        pcall(function()
            Argon:LoadConfig(options.AutoLoad)
        end)
    end
    if options.AutoSaveTo then
        Argon.Config.AutoSave = true
        ConfigStore._pendingName = options.AutoSaveTo
        for flag in pairs(Argon.Flags) do
            Argon:OnFlagChanged(flag, function()
                ConfigStore.scheduleSave(options.AutoSaveTo)
            end)
        end
    end

    return self
end

-- ---------------------------------------------------------------------------
-- 15b. WINDOW CHROME -- rail / sidebar / page visibility
--
-- The whole shell is driven by two booleans, exactly like the reference:
--
--   SidebarShown = hovered          (only when HoverOpen, otherwise always true)
--   PageShown    = ActivePage ~= nil (only when RailOnly, otherwise always true)
--
-- Everything else -- width, content offset, shadow, position compensation -- is
-- derived, so a page can never end up half outside the window.
-- ---------------------------------------------------------------------------

function Window:IsHoverLayout()
    return self.Layout == "side" and self.HoverOpen and self.ShowSidebar == true
end

function Window:RailWidthPx()
    return self.ShowRail and self.RailWidth or 0
end

function Window:SidebarWidthPx()
    if self.ShowSidebar and self.SidebarShown then
        return self.SidebarWidth
    end
    return 0
end

function Window:PageShown()
    if not self.RailOnly then
        return true
    end
    return self.ActivePage ~= nil and true or false
end

-- The page pane is whatever is left of the requested (expanded) width once the
-- rail and the sidebar have taken their share.
function Window:PaneWidth()
    local pane = self.Width - self:RailWidthPx()
    if self.ShowSidebar then
        pane = pane - self.SidebarWidth
    end
    return math.max(280, pane)
end

function Window:CurrentWidth()
    if self.Layout == "square" or (not self:IsHoverLayout() and not self.RailOnly) then
        return self.Width
    end
    local width = self:RailWidthPx() + self:SidebarWidthPx()
    if self:PageShown() then
        width = width + self:PaneWidth()
    end
    if width <= self:RailWidthPx() then
        -- nothing but the rail: report the rail exactly, like the reference does
        return self:RailWidthPx() > 0 and self:RailWidthPx() or 200
    end
    return width
end

function Window:CurrentHeight()
    return self.Minimized and 54 or self.Height
end

-- Growing the window has to keep the *left* edge still, the way the reference
-- does, otherwise the rail visibly slides every time the pointer comes near.
-- The window is anchored at its centre, so half of the delta is pushed right.
function Window:_applyPosition(animated)
    if not self.Main then
        return
    end
    local width = self:CurrentWidth()
    local delta = width - (self._lastWidth or width)
    self._lastWidth = width
    if delta ~= 0 then
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
            or Vector2.new(1920, 1080)
        self._chromeShift = self._chromeShift + delta / 2
        local left = viewport.X / 2 + self._chromeShift - width / 2
        if left < 8 then
            self._chromeShift = self._chromeShift + (8 - left)
        elseif left + width > viewport.X - 8 then
            self._chromeShift = self._chromeShift - (left + width - (viewport.X - 8))
        end
    end
    local position = UDim2.new(0.5, self._chromeShift, 0.5, 0)
    local size = UDim2.new(0, width, 0, self:CurrentHeight())
    if animated then
        animate(self.Main, { Size = size, Position = position }, 0.14)
    else
        self.Main.Size = size
        self.Main.Position = position
    end
    if self.Shadow then
        local shadowSize = UDim2.new(0, width + 6, 0, self:CurrentHeight() + 10)
        local shadowPosition = UDim2.new(0.5, self._chromeShift, 0.5, 6)
        if animated then
            animate(self.Shadow, { Size = shadowSize, Position = shadowPosition }, 0.14)
        else
            self.Shadow.Size = shadowSize
            self.Shadow.Position = shadowPosition
        end
    end
end

function Window:UpdateChrome(animated)
    if self.Destroyed or not self.Main then
        return self
    end

    self.EffectiveWidth = self:CurrentWidth()

    if self.Sidebar then
        local sidebarWidth = self:SidebarWidthPx()
        local size = UDim2.new(0, sidebarWidth, 1, 0)
        local visible = self.SidebarShown and sidebarWidth > 0
        if animated then
            animate(self.Sidebar, { Size = size }, 0.14)
        else
            self.Sidebar.Size = size
        end
        self.Sidebar.Visible = visible
        if self.RailDivider then
            self.RailDivider.Visible = true
        end
    end

    if self.Content then
        local offset = self:RailWidthPx() + self:SidebarWidthPx()
        local size = UDim2.new(1, -offset, 1, 0)
        if animated then
            animate(self.Content, { Position = UDim2.new(0, offset, 0, 0) }, 0.14)
        else
            self.Content.Position = UDim2.new(0, offset, 0, 0)
        end
        self.Content.Size = size
        self.Content.Visible = self:PageShown()
    end

    self:_applyPosition(animated)
    return self
end

function Window:PaneVisible()
    return self.Content ~= nil and self.Content.Visible == true
end

-- The hover flag is a single pointer/rect test, not MouseEnter/MouseLeave.
-- Per-child enter/leave is what makes a collapsing panel stick: the topmost
-- object under the cursor changes as the sidebar slides, MouseLeave fires on
-- the frame the pointer never left, and the flag is stranded mid-transition.
function Window:ProbePointer(immediate)
    if self.Destroyed or not self.Main or not self:GetVisible() then
        return
    end
    local ok, location = pcall(function()
        return UserInputService:GetMouseLocation()
    end)
    if not ok or not location then
        return
    end
    local position = self.Main.AbsolutePosition
    local size = self.Main.AbsoluteSize
    local inside = location.X >= position.X - 2
        and location.X <= position.X + size.X + 2
        and location.Y >= position.Y - 2
        and location.Y <= position.Y + size.Y + 2
    if inside ~= self.hovered then
        self:SetHovered(inside, immediate)
    end
end

function Window:SetHovered(hovered, immediate)
    hovered = hovered and true or false
    if self.hovered == hovered then
        return self
    end

    if self._hoverToken then
        task.cancel(self._hoverToken)
        self._hoverToken = nil
    end

    -- Leaving is delayed and re-probed, so crossing onto a tooltip or a
    -- transient child can't close the sidebar the user is reaching for.
    if not hovered and not immediate and self.CollapseDelay > 0 then
        self._hoverToken = task.delay(self.CollapseDelay, function()
            self._hoverToken = nil
            -- Re-probe and apply: a second deferred call would defer again and
            -- the sidebar would never close.
            self:ProbePointer(true)
        end)
        return self
    end

    self.hovered = hovered
    if self:IsHoverLayout() then
        self.SidebarShown = hovered
    end
    self:UpdateChrome(true)
    return self
end

function Window:StartPointerTracking()
    if not self:IsHoverLayout() or self._hoverProbe then
        return self
    end

    self._hoverProbe = {
        Connect(UserInputService.InputChanged, function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement then
                self:ProbePointer()
            end
        end),
        Connect(UserInputService.InputBegan, function()
            self:ProbePointer()
        end),
    }

    -- A window opened under a stationary cursor never receives a movement
    -- event, so the first few frames are probed by hand.
    local frame = 0
    local step
    step = function()
        if self.Destroyed then
            return
        end
        self:ProbePointer()
        frame = frame + 1
        if frame < 3 then
            task.defer(step)
        end
    end
    task.defer(step)
    return self
end

function Window:SetLayout(layout)
    self.Layout = (layout == "square") and "square" or "side"
    if self.Layout == "square" then
        self.HoverOpen = false
        self.ShowSidebar = false
        self.AutoClosePage = false
        self.SidebarShown = false
    else
        self.ShowSidebar = true
        self.HoverOpen = true
        self.AutoClosePage = true
        self.SidebarShown = self.hovered
    end
    if self.Sidebar then
        self.Sidebar.Visible = self.SidebarShown
    end
    self:UpdateChrome(true)
    self:StartPointerTracking()
    return self
end

-- Rail only: the shell collapses to the icon rail, exactly like the reference
-- with the pointer away and no page open.
function Window:SetRailOnly(railOnly)
    self.RailOnly = railOnly and true or false
    if self.RailOnly and self.ActivePage then
        self.ActivePage:SetVisible(false)
        self.ActivePage = nil
    end
    self:UpdateChrome(true)
    return self
end

function Window:GetVisible()
    return self.Visible ~= false and self.Gui ~= nil and self.Gui.Enabled ~= false
end

function Window:OpenPage(page)
    self:SelectPage(page)
    return self
end

function Window:ClosePage()
    if self.ActivePage then
        local page = self.ActivePage
        page:SetVisible(false)
        if page.NavItem then
            page.NavItem.BackgroundColor3 = C("Surface")
            page.NavItem.BackgroundTransparency = 1
            page.NavLabel.TextColor3 = C("TextMuted")
            page.NavIcon.TextColor3 = C("TextMuted")
        end
        if page.RailButton then
            page.RailButton.BackgroundTransparency = 1
            page.RailIconLabel.TextColor3 = C("TextDim")
            if page.RailIndicator then
                page.RailIndicator.Visible = false
            end
        end
        self.ActivePage = nil
    end
    self:UpdateChrome(true)
    return self
end

function Window:BuildShell()
    local theme = Argon.Theme

    self.Shadow = UI.frame({
        Parent = self.Gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 6),
        Size = UDim2.new(0, self.Width + 6, 0, self.Height + 10),
        BackgroundColor3 = theme.Accent,
        BackgroundTransparency = 0.9,
        BorderSizePixel = 0,
    })
    UI.corner(UDim.new(0, 16)).Parent = self.Shadow

    self.Main = UI.frame({
        Parent = self.Gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, self.Width, 0, self.Height),
        BackgroundColor3 = theme.Background,
        ClipsDescendants = true,
    })
    UI.corner(UDim.new(0, 12)).Parent = self.Main
    self.MainStroke = UI.stroke(theme.Stroke, 1, 0)
    self.MainStroke.Parent = self.Main

    -- rail --------------------------------------------------------------
    if self.ShowRail then
        self.Rail = UI.frame({
            Parent = self.Main,
            Size = UDim2.new(0, self.RailWidth, 1, 0),
            BackgroundColor3 = theme.Rail,
            BorderSizePixel = 0,
        })
        self.RailButtons = {}
        self.RailList = UI.transparent({
            Parent = self.Rail,
            Position = UDim2.new(0, 0, 0, 14),
            Size = UDim2.new(1, 0, 1, -110),
        })
        self.RailListLayout = UI.listLayout(6)
        self.RailListLayout.Parent = self.RailList

        self.RailBottom = UI.transparent({
            Parent = self.Rail,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, -10),
            Size = UDim2.new(1, 0, 0, 84),
        })

        local avatar = UI.frame({
            Parent = self.RailBottom,
            Position = UDim2.new(0.5, -15, 0, 46),
            Size = UDim2.new(0, 30, 0, 30),
            BackgroundColor3 = theme.Accent,
        })
        UI.corner(UDim.new(1, 0)).Parent = avatar
        UI.glyph((self.User.Name or "U"):sub(1, 1):upper(), 12, theme.AccentText, {
            Parent = avatar,
            Size = UDim2.new(1, 0, 1, 0),
        })

        self.RailSettings = UI.button({
            Parent = self.RailBottom,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 8),
            Size = UDim2.new(0, 32, 0, 30),
            BackgroundTransparency = 1,
            Text = "⚙",
            TextSize = 15,
            TextColor3 = theme.TextDim,
        })
        attachTooltip(self.RailSettings, "Settings")
        Connect(self.RailSettings.MouseButton1Click, function()
            self:ShowSettings()
        end)
    end

    -- sidebar -----------------------------------------------------------
    local sidebarOffset = self.ShowRail and self.RailWidth or 0
    if self.ShowSidebar then
        self.Sidebar = UI.frame({
            Parent = self.Main,
            Position = UDim2.new(0, sidebarOffset, 0, 0),
            Size = UDim2.new(0, self.SidebarWidth, 1, 0),
            BackgroundColor3 = theme.Sidebar,
            BorderSizePixel = 0,
        })

        self.LogoRow = UI.transparent({
            Parent = self.Sidebar,
            Size = UDim2.new(1, 0, 0, 54),
        })
        self.LogoMark = UI.frame({
            Parent = self.LogoRow,
            Position = UDim2.new(0, 14, 0, 15),
            Size = UDim2.new(0, 24, 0, 24),
            BackgroundColor3 = theme.Accent,
        })
        UI.corner(UDim.new(0, 6)).Parent = self.LogoMark
        UI.glyph(self.Options.Logo or "⚡", 13, theme.AccentText, {
            Parent = self.LogoMark,
            Size = UDim2.new(1, 0, 1, 0),
        })

        self.LogoLabel = UI.label({
            Parent = self.LogoRow,
            Position = UDim2.new(0, 46, 0, 17),
            Size = UDim2.new(1, -56, 0, 20),
            Text = self.Title,
            TextSize = 14,
            Font = theme.FontBold,
            TextColor3 = theme.Text,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })

        self.NavScroller = UI.scroller({
            Parent = self.Sidebar,
            Position = UDim2.new(0, 0, 0, 54),
            Size = UDim2.new(1, 0, 1, -54 - (self.ShowUser and 96 or (self.ShowThemeSwitch and 52 or 10))),
            ScrollBarThickness = 2,
        })
        self.NavHolder = UI.transparent({
            Parent = self.NavScroller,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
        })
        UI.padding(0, 8, 8, 8).Parent = self.NavHolder
        self.NavLayout = UI.listLayout(2)
        self.NavLayout.Parent = self.NavHolder
        bindCanvas(self.NavScroller, self.NavLayout, 8)

        local bottomOffset = 0
        if self.ShowUser then
            self.UserCard = UI.frame({
                Parent = self.Sidebar,
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, 0, 1, 0),
                Size = UDim2.new(1, 0, 0, 58),
                BackgroundColor3 = theme.SidebarAlt,
                BackgroundTransparency = 0,
            })
            local avatar = UI.frame({
                Parent = self.UserCard,
                Position = UDim2.new(0, 12, 0.5, -13),
                Size = UDim2.new(0, 26, 0, 26),
                BackgroundColor3 = theme.SurfaceActive,
            })
            UI.corner(UDim.new(1, 0)).Parent = avatar
            self.UserAvatarFrame = avatar
            if self.User.Avatar then
                self.UserAvatarImage = UI.image({
                    Parent = avatar,
                    Size = UDim2.new(1, 0, 1, 0),
                    Image = tostring(self.User.Avatar),
                })
                UI.corner(UDim.new(1, 0)).Parent = self.UserAvatarImage
            else
                UI.glyph((self.User.Name or "U"):sub(1, 1):upper(), 11, theme.Text, {
                    Parent = avatar,
                    Size = UDim2.new(1, 0, 1, 0),
                })
            end

            self.UserName = UI.label({
                Parent = self.UserCard,
                Position = UDim2.new(0, 46, 0, 11),
                Size = UDim2.new(1, -80, 0, 16),
                Text = tostring(self.User.Name or "user"),
                TextSize = Argon.Theme.TextSizeSmall,
                Font = theme.FontMedium,
                TextColor3 = theme.Text,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            self.UserTag = UI.label({
                Parent = self.UserCard,
                Position = UDim2.new(0, 46, 0, 27),
                Size = UDim2.new(1, -80, 0, 14),
                Text = tostring(self.User.Tag or "Free"),
                TextSize = Argon.Theme.TextSizeTiny,
                TextColor3 = theme.TextDim,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            self.UserGear = UI.button({
                Parent = self.UserCard,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -10, 0.5, 0),
                Size = UDim2.new(0, 20, 0, 20),
                BackgroundTransparency = 1,
                Text = "⚙",
                TextSize = 13,
                TextColor3 = theme.TextDim,
            })
            Connect(self.UserGear.MouseButton1Click, function()
                self:ShowSettings()
            end)
            bottomOffset = 58
        end

        if self.ShowThemeSwitch then
            self.ThemeSwitch = UI.frame({
                Parent = self.Sidebar,
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, 10, 1, -(bottomOffset + 8)),
                Size = UDim2.new(1, -20, 0, 30),
                BackgroundColor3 = theme.Surface,
                BackgroundTransparency = 0.2,
            })
            UI.corner(UDim.new(0, 7)).Parent = self.ThemeSwitch
            UI.padding(3).Parent = self.ThemeSwitch

            self.LightButton = UI.button({
                Parent = self.ThemeSwitch,
                Size = UDim2.new(0.5, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "Light",
                TextSize = Argon.Theme.TextSizeTiny,
                TextColor3 = theme.TextDim,
                Font = theme.FontMedium,
            })
            self.DarkButton = UI.button({
                Parent = self.ThemeSwitch,
                Position = UDim2.new(0.5, 0, 0, 0),
                Size = UDim2.new(0.5, 0, 1, 0),
                BackgroundColor3 = theme.SurfaceActive,
                Text = "Dark",
                TextSize = Argon.Theme.TextSizeTiny,
                TextColor3 = theme.Text,
                Font = theme.FontMedium,
            })
            UI.corner(UDim.new(0, 5)).Parent = self.DarkButton
            Connect(self.LightButton.MouseButton1Click, function()
                Argon:SetTheme("Light")
                self:RefreshThemeSwitch()
            end)
            Connect(self.DarkButton.MouseButton1Click, function()
                if Argon.ThemeName == "Light" then
                    Argon:SetTheme(self.LastDarkTheme or "Dark")
                end
                self:RefreshThemeSwitch()
            end)
        end
    end

    -- content -----------------------------------------------------------
    local contentOffset = sidebarOffset + (self.ShowSidebar and self.SidebarWidth or 0)
    self.Content = UI.transparent({
        Parent = self.Main,
        Position = UDim2.new(0, contentOffset, 0, 0),
        Size = UDim2.new(1, -contentOffset, 1, 0),
    })
    UI.padding(16, 16, 0, 16).Parent = self.Content

    -- window controls overlay -------------------------------------------
    self.WindowControls = UI.transparent({
        Parent = self.Main,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.new(0, 62, 0, 26),
    })

    self.MinimizeButton = UI.button({
        Parent = self.WindowControls,
        Size = UDim2.new(0, 26, 0, 26),
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.3,
        Text = "–",
        TextSize = 13,
        TextColor3 = theme.TextMuted,
    })
    UI.corner(UDim.new(0, 6)).Parent = self.MinimizeButton

    self.CloseButton = UI.button({
        Parent = self.WindowControls,
        Position = UDim2.new(0, 32, 0, 0),
        Size = UDim2.new(0, 26, 0, 26),
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0.3,
        Text = "×",
        TextSize = 14,
        TextColor3 = theme.TextMuted,
    })
    UI.corner(UDim.new(0, 6)).Parent = self.CloseButton

    Connect(self.MinimizeButton.MouseButton1Click, function()
        self:SetMinimized(not self.Minimized)
    end)
    Connect(self.CloseButton.MouseButton1Click, function()
        self:SetVisible(false)
    end)
    Connect(self.CloseButton.MouseEnter, function()
        animate(self.CloseButton, { BackgroundColor3 = theme.Danger, TextColor3 = theme.Text, BackgroundTransparency = 0 }, 0.1)
    end)
    Connect(self.CloseButton.MouseLeave, function()
        animate(self.CloseButton, { BackgroundColor3 = theme.Surface, TextColor3 = theme.TextMuted, BackgroundTransparency = 0.3 }, 0.1)
    end)

    -- resize handle ------------------------------------------------------
    if self.Resizable then
        self.ResizeHandle = UI.button({
            Parent = self.Main,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, 0, 1, 0),
            Size = UDim2.new(0, 16, 0, 16),
            BackgroundTransparency = 1,
            Text = "",
        })
        makeResizable(self.Main, self.ResizeHandle, {
            Min = Vector2.new(
                tonumber(self.Options.MinWidth) or (self.Layout == "square" and 300 or 520),
                tonumber(self.Options.MinHeight) or 360
            ),
            Max = Vector2.new(1600, 1000),
            onResize = function(size)
                self.Width, self.Height = size.X, size.Y
                self.Shadow.Size = UDim2.new(0, self:CurrentWidth() + 6, 0, size.Y + 10)
                self:UpdateChrome(false)
                if self.UpdateLayout then
                    self:UpdateLayout()
                end
            end,
        })
    end

    makeDraggable(self.Main, self.Sidebar and self.LogoRow or self.Main, { bounds = true })

    self:UpdateChrome(false)
    self:StartPointerTracking()

    if self.ShowThemeSwitch then
        self:RefreshThemeSwitch()
    end

    registerThemed(function(palette)
        self.Main.BackgroundColor3 = palette.Background
        self.MainStroke.Color = palette.Stroke
        self.Shadow.BackgroundColor3 = palette.Accent
        if self.Rail then
            self.Rail.BackgroundColor3 = palette.Rail
        end
        if self.Sidebar then
            self.Sidebar.BackgroundColor3 = palette.Sidebar
            self.LogoMark.BackgroundColor3 = palette.Accent
            self.LogoLabel.TextColor3 = palette.Text
            if self.UserCard then
                self.UserCard.BackgroundColor3 = palette.SidebarAlt
                self.UserName.TextColor3 = palette.Text
                self.UserTag.TextColor3 = palette.TextDim
            end
            if self.ThemeSwitch then
                self.ThemeSwitch.BackgroundColor3 = palette.Surface
                self.LightButton.TextColor3 = palette.TextDim
                self.DarkButton.TextColor3 = palette.Text
                self.DarkButton.BackgroundColor3 = palette.SurfaceActive
            end
        end
        self.MinimizeButton.BackgroundColor3 = palette.Surface
        self.CloseButton.BackgroundColor3 = palette.Surface
        self.MinimizeButton.TextColor3 = palette.TextMuted
        self.CloseButton.TextColor3 = palette.TextMuted
    end)
end

function Window:RefreshThemeSwitch()
    if not self.ThemeSwitch then
        return
    end
    local light = Argon.ThemeName == "Light"
    if light then
        self.LastLightTheme = self.LastLightTheme or "Light"
    else
        self.LastDarkTheme = Argon.ThemeName
    end
    self.LightButton.BackgroundColor3 = light and C("SurfaceActive") or C("Surface")
    self.LightButton.BackgroundTransparency = light and 0 or 1
    self.DarkButton.BackgroundColor3 = light and C("Surface") or C("SurfaceActive")
    self.DarkButton.BackgroundTransparency = light and 1 or 0
    self.LightButton.TextColor3 = light and C("Text") or C("TextDim")
    self.DarkButton.TextColor3 = light and C("TextDim") or C("Text")
    if self.LightButton:FindFirstChildOfClass("UICorner") == nil then
        UI.corner(UDim.new(0, 5)).Parent = self.LightButton
    end
    return self
end

function Window:ApplyTheme(palette)
    self:RefreshThemeSwitch()
    for _, page in ipairs(self.Pages) do
        if page.Visible then
            page:Refresh()
        end
    end
end

function Window:Page(config)
    local page = Page.new(self, config or {})
    if #self.Pages == 1 then
        self:SelectPage(page)
    end
    return page
end

function Window:GetPage(name)
    for _, page in ipairs(self.Pages) do
        if page.Name == name then
            return page
        end
    end
    return nil
end

function Window:RebuildNav()
    if not self.ShowSidebar or not self.NavHolder then
        return
    end

    for _, child in ipairs(self.NavHolder:GetChildren()) do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end

    self.NavItems = {}
    self.RailButtons = {}

    local groups = {}
    local groupOrder = {}
    for _, page in ipairs(self.Pages) do
        if not groups[page.Group] then
            groups[page.Group] = {}
            table.insert(groupOrder, page.Group)
        end
        table.insert(groups[page.Group], page)
    end

    local order = 0
    for _, groupName in ipairs(groupOrder) do
        order = order + 1
        local heading = UI.label({
            Parent = self.NavHolder,
            Size = UDim2.new(1, 0, 0, 20),
            Text = string.upper(tostring(groupName)),
            TextSize = 9,
            Font = Argon.Theme.FontBold,
            TextColor3 = C("TextDim"),
            LayoutOrder = order,
        })
        UI.padding(0, 6, 0, 0).Parent = heading
        self.NavItems[#self.NavItems + 1] = { Heading = heading, Group = groupName }

        for _, page in ipairs(groups[groupName]) do
            order = order + 1
            local item = UI.button({
                Parent = self.NavHolder,
                Size = UDim2.new(1, 0, 0, 32),
                BackgroundTransparency = 1,
                Text = "",
                LayoutOrder = order,
            })
            UI.corner(UDim.new(0, 7)).Parent = item

            local icon = UI.glyph(tostring(page.Icon or "▤"), 13, C("TextMuted"), {
                Parent = item,
                Position = UDim2.new(0, 8, 0, 0),
                Size = UDim2.new(0, 20, 1, 0),
                TextXAlignment = Enum.TextXAlignment.Center,
            })

            local label = UI.label({
                Parent = item,
                Position = UDim2.new(0, 34, 0, 0),
                Size = UDim2.new(1, -42, 1, 0),
                Text = page.Name,
                TextSize = Argon.Theme.TextSizeSmall,
                Font = Argon.Theme.FontMedium,
                TextColor3 = C("TextMuted"),
                TextTruncate = Enum.TextTruncate.AtEnd,
            })

            local badge = UI.frame({
                Parent = item,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.new(0, 0, 0, 0),
                BackgroundColor3 = C("Premium"),
                BackgroundTransparency = 0.85,
                Visible = page.Options and page.Options.Badge ~= nil,
            })
            UI.corner(UDim.new(0, 4)).Parent = badge
            if page.Options and page.Options.Badge then
                badge.Size = UDim2.new(0, 0, 0, 14)
                badge.AutomaticSize = Enum.AutomaticSize.X
                UI.padding(0, 4, 0, 4).Parent = badge
                UI.label({
                    Parent = badge,
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = tostring(page.Options.Badge),
                    TextSize = 8,
                    Font = Argon.Theme.FontBold,
                    TextColor3 = C("Premium"),
                    TextXAlignment = Enum.TextXAlignment.Center,
                })
            end

            page.NavItem = item
            page.NavIcon = icon
            page.NavLabel = label

            Connect(item.MouseEnter, function()
                if self.ActivePage ~= page then
                    animate(item, { BackgroundTransparency = 0.92 }, 0.1)
                end
            end)
            Connect(item.MouseLeave, function()
                if self.ActivePage ~= page then
                    animate(item, { BackgroundTransparency = 1 }, 0.1)
                end
            end)
            Connect(item.MouseButton1Click, function()
                self:SelectPage(page)
            end)

            self.NavItems[#self.NavItems + 1] = { Page = page, Button = item }

            -- rail shortcut
            if self.ShowRail and page.ShowRail then
                local railButton = UI.button({
                    Parent = self.RailList,
                    Size = UDim2.new(1, -12, 0, 34),
                    BackgroundTransparency = 1,
                    Text = "",
                })
                UI.corner(UDim.new(0, 8)).Parent = railButton
                local railIcon = UI.glyph(tostring(page.RailIcon or "▤"), 15, C("TextDim"), {
                    Parent = railButton,
                    Size = UDim2.new(1, 0, 1, 0),
                    TextXAlignment = Enum.TextXAlignment.Center,
                })
                local indicator = UI.frame({
                    Parent = railButton,
                    Position = UDim2.new(0, 0, 0.5, -9),
                    Size = UDim2.new(0, 3, 0, 18),
                    BackgroundColor3 = accent(),
                    Visible = false,
                })
                UI.corner(UDim.new(1, 0)).Parent = indicator

                page.RailButton = railButton
                page.RailIconLabel = railIcon
                page.RailIndicator = indicator
                table.insert(self.RailButtons, railButton)

                Connect(railButton.MouseButton1Click, function()
                    self:SelectPage(page)
                end)
                Connect(railButton.MouseEnter, function()
                    if self.ActivePage ~= page then
                        animate(railButton, { BackgroundTransparency = 0.9 }, 0.1)
                    end
                end)
                Connect(railButton.MouseLeave, function()
                    if self.ActivePage ~= page then
                        animate(railButton, { BackgroundTransparency = 1 }, 0.1)
                    end
                end)
            end
        end
    end

    self:SelectPage(self.ActivePage or self.Pages[1])
end

function Window:SelectPage(page)
    if not page or page.Destroyed then
        return self
    end

    self.ActivePage = page
    self:UpdateChrome(true)

    for _, candidate in ipairs(self.Pages) do
        candidate:SetVisible(candidate == page)
        if candidate.NavItem then
            local active = candidate == page
            candidate.NavItem.BackgroundColor3 = active and C("SurfaceActive") or C("Surface")
            candidate.NavItem.BackgroundTransparency = active and 0 or 1
            candidate.NavLabel.TextColor3 = active and C("Text") or C("TextMuted")
            candidate.NavIcon.TextColor3 = active and C("Accent") or C("TextMuted")
        end
        if candidate.RailButton then
            candidate.RailButton.BackgroundColor3 = C("Surface")
            candidate.RailButton.BackgroundTransparency = (candidate == page) and 0.6 or 1
            candidate.RailIconLabel.TextColor3 = (candidate == page) and C("Accent") or C("TextDim")
            candidate.RailIndicator.Visible = candidate == page
            candidate.RailIndicator.BackgroundColor3 = C("Accent")
        end
    end

    return self
end

function Window:FireFlagChanged(flag, value)
    if not flag then
        return
    end
    local listeners = self.FlagListeners[flag]
    if listeners then
        for _, callback in ipairs(listeners) do
            pcall(callback, value)
        end
    end
end

function Window:OnFlagChanged(flag, callback)
    flag = resolveFlagPath(flag)
    self.FlagListeners[flag] = self.FlagListeners[flag] or {}
    table.insert(self.FlagListeners[flag], callback)
    return self
end

function Window:SetTitle(title)
    self.Title = tostring(title or "")
    if self.LogoLabel then
        self.LogoLabel.Text = self.Title
    end
    return self
end

function Window:SetSubtitle(subtitle)
    self.Subtitle = tostring(subtitle or "")
    return self
end

function Window:SetUser(user)
    if type(user) ~= "table" then
        return self
    end
    self.User = user
    if self.UserName then
        self.UserName.Text = tostring(user.Name or "")
    end
    if self.UserTag then
        self.UserTag.Text = tostring(user.Tag or "")
    end
    return self
end

function Window:SetTheme(name)
    Argon:SetTheme(name)
    self:RefreshThemeSwitch()
    return self
end

function Window:SetAccent(color)
    Argon:SetAccent(color)
    return self
end

function Window:SetMinimized(minimized)
    self.Minimized = minimized and true or false
    self:UpdateChrome(false)
    return self
end

function Window:SetVisible(visible)
    self.Visible = visible ~= false
    self.Gui.Enabled = self.Visible
    return self
end

function Window:Toggle()
    return self:SetVisible(not self.Visible)
end

function Window:Notify(config)
    return Argon:Notify(config)
end

function Window:Dialog(config)
    return Argon:Dialog(config)
end

function Window:ShowSettings()
    local page = self:GetPage("Settings")
    if page then
        self:SelectPage(page)
    else
        Argon:Dialog({
            Title = "Settings",
            Text = "Create a page named \"Settings\" to own this button, or open the theme picker from your own UI.",
            Buttons = { { Text = "Close", Primary = true } },
        })
    end
    return self
end

function Window:Refresh()
    for _, page in ipairs(self.Pages) do
        if page.Visible then
            page:Refresh()
        end
    end
    return self
end

function Window:DestroyProbe()
    if self._hoverToken then
        pcall(task.cancel, self._hoverToken)
        self._hoverToken = nil
    end
    for _, connection in ipairs(self._hoverProbe or {}) do
        Disconnect(connection)
    end
    self._hoverProbe = nil
end

function Window:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    self:DestroyProbe()
    for _, page in ipairs(self.Pages) do
        page.Destroyed = true
    end
    for index, existing in ipairs(Argon.Windows) do
        if existing == self then
            table.remove(Argon.Windows, index)
            break
        end
    end
    DestroyInstance(self.Gui)
end

Argon.WindowClass = Window
Argon.SectionClass = Section
Argon.PageClass = Page

function Argon:Window(options)
    return Window.new(options)
end

-- ============================================================================
-- 23. COMPONENTS — TOGGLE
-- ============================================================================

function Section:Toggle(config, callback)
    config = config or {}
    config.Default = config.Default and true or false

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    local slot = element:buildRow({
        Height = config.Height or Argon.Theme.RowHeight,
        Icon = config.Icon,
        HasDescription = config.Description ~= nil,
        Reserved = -62,
        SlotWidth = 48,
    })

    local track = UI.frame({
        Name = "Switch",
        Parent = slot,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 38, 0, 21),
        BackgroundColor3 = C("SurfaceHigh"),
        BackgroundTransparency = 0,
    })
    UI.corner(UDim.new(1, 0)).Parent = track
    local trackStroke = UI.stroke(C("StrokeLight"), 1, 0.4)
    trackStroke.Parent = track

    local knob = UI.frame({
        Name = "Knob",
        Parent = track,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 2, 0.5, 0),
        Size = UDim2.new(0, 17, 0, 17),
        BackgroundColor3 = C("TextMuted"),
        BorderSizePixel = 0,
    })
    UI.corner(UDim.new(1, 0)).Parent = knob

    local hitbox = UI.button({
        Name = "Click",
        Parent = track,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
    })

    local function render(animated)
        local on = element.Value and true or false
        local trackColor = on and C("Accent") or C("SurfaceHigh")
        local knobColor = on and C("AccentText") or C("TextMuted")
        local knobPosition = UDim2.new(0, on and 19 or 2, 0.5, 0)

        if animated then
            animate(track, { BackgroundColor3 = trackColor }, 0.16)
            animate(knob, { Position = knobPosition, BackgroundColor3 = knobColor }, 0.16,
                EasingStyle.Quart, EasingDirection.Out)
        else
            track.BackgroundColor3 = trackColor
            knob.Position = knobPosition
            knob.BackgroundColor3 = knobColor
        end

        element.Value = on
        if element.Flag then
            Argon.Flags[element.Flag] = on
        end
        trackStroke.Transparency = on and 1 or 0.4
    end

    function element:Refresh()
        render(false)
        return self
    end

    Connect(hitbox.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element:SetValue(not element.Value)
        render(true)
    end)

    element:applyTheme(function()
        render(false)
    end)

    render(false)
    return element
end

-- ============================================================================
-- 24. COMPONENTS — CHECKBOX
-- ============================================================================

function Section:Checkbox(config, callback)
    config = config or {}
    config.Default = config.Default and true or false

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    local slot = element:buildRow({
        Height = config.Height or 38,
        Icon = config.Icon,
        HasDescription = config.Description ~= nil,
        Reserved = -40,
        SlotWidth = 26,
    })

    local box = UI.frame({
        Name = "Box",
        Parent = slot,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 18, 0, 18),
        BackgroundColor3 = C("SurfaceHigh"),
        BorderSizePixel = 0,
    })
    UI.corner(UDim.new(0, 5)).Parent = box
    local boxStroke = UI.stroke(C("StrokeLight"), 1, 0)
    boxStroke.Parent = box

    local tick = UI.glyph("✓", 12, C("AccentText"), {
        Parent = box,
        Size = UDim2.new(1, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Center,
        Visible = false,
    })

    local hitbox = UI.button({
        Name = "Click",
        Parent = element.Row,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
    })

    local function render(animated)
        local on = element.Value and true or false
        local targetColor = on and C("Accent") or C("SurfaceHigh")
        if animated then
            animate(box, { BackgroundColor3 = targetColor }, 0.14)
        else
            box.BackgroundColor3 = targetColor
        end
        tick.Visible = on
        boxStroke.Transparency = on and 1 or 0
        element.Value = on
        if element.Flag then
            Argon.Flags[element.Flag] = on
        end
    end

    function element:Refresh()
        render(false)
        return self
    end

    Connect(hitbox.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element:SetValue(not element.Value)
        render(true)
    end)

    element:applyTheme(function()
        render(false)
    end)

    render(false)
    return element
end

-- ============================================================================
-- 25. COMPONENTS — SLIDER
-- ============================================================================

function Section:Slider(config, callback)
    config = config or {}

    local minimum = tonumber(config.Min) or 0
    local maximum = tonumber(config.Max) or 100
    if maximum <= minimum then
        maximum = minimum + 1
    end

    config.Min = minimum
    config.Max = maximum
    config.Default = tonumber(config.Default) or minimum

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    element.Step = tonumber(config.Step) or 1
    element.Decimals = tonumber(config.Decimals) or 0
    element.Suffix = tostring(config.Suffix or "")
    element.Prefix = tostring(config.Prefix or "")
    element.IsSlider = true

    local height = tonumber(config.Height) or 60
    element:buildRow({
        Height = height,
        Icon = config.Icon,
        HasDescription = config.Description ~= nil,
        Reserved = -96,
        SlotWidth = 88,
        Hover = true,
    })

    local valueBox = UI.frame({
        Name = "ValueBox",
        Parent = element.RightSlot,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 8),
        Size = UDim2.new(0, 74, 0, 22),
        BackgroundColor3 = C("Input"),
        BorderSizePixel = 0,
    })
    UI.corner(UDim.new(0, 5)).Parent = valueBox
    local valueStroke = UI.stroke(C("Stroke"), 1, 0.2)
    valueStroke.Parent = valueBox

    local valueInput = UI.textBox({
        Name = "ValueInput",
        Parent = valueBox,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextSize = Argon.Theme.TextSizeTiny,
        TextColor3 = C("Text"),
        Font = Argon.Theme.FontMono,
        TextXAlignment = Enum.TextXAlignment.Center,
        PlaceholderText = "",
    })

    local trackHolder = UI.transparent({
        Parent = element.Row,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -12),
        Size = UDim2.new(1, 0, 0, 12),
    })

    local track = UI.frame({
        Name = "Track",
        Parent = trackHolder,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 4),
        BackgroundColor3 = C("SurfaceHigh"),
    })
    UI.corner(UDim.new(1, 0)).Parent = track

    local fill = UI.frame({
        Name = "Fill",
        Parent = track,
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = C("Accent"),
    })
    UI.corner(UDim.new(1, 0)).Parent = fill

    local knob = UI.frame({
        Name = "Knob",
        Parent = track,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 12),
        BackgroundColor3 = C("Text"),
        BorderSizePixel = 0,
    })
    UI.corner(UDim.new(1, 0)).Parent = knob
    local knobStroke = UI.stroke(C("Background"), 2, 0)
    knobStroke.Parent = knob

    if config.Ticks then
        for index = 0, config.Ticks do
            local ratio = index / config.Ticks
            local tick = UI.frame({
                Parent = trackHolder,
                AnchorPoint = Vector2.new(0.5, 1),
                Position = UDim2.new(ratio, 0, 0, -2),
                Size = UDim2.new(0, 1, 0, 3),
                BackgroundColor3 = C("StrokeLight"),
                BackgroundTransparency = 0.3,
            })
            tick.Name = "Tick" .. tostring(index)
        end
    end

    local hitbox = UI.button({
        Name = "Hitbox",
        Parent = trackHolder,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
    })

    local function ratio()
        return Math.clamp((element.Value - minimum) / (maximum - minimum), 0, 1)
    end

    local function displayValue()
        local text = element.Prefix .. String.formatNumber(element.Value, element.Decimals) .. element.Suffix
        return text
    end

    local function render()
        local position = ratio()
        fill.Size = UDim2.new(position, 0, 1, 0)
        knob.Position = UDim2.new(position, 0, 0.5, 0)
        if not valueInput:IsFocused() then
            valueInput.Text = displayValue()
        end
        element.Value = Math.clamp(element.Value, minimum, maximum)
        if element.Flag then
            Argon.Flags[element.Flag] = element.Value
        end
    end

    function element:Refresh()
        render()
        return self
    end

    function element:Set(value, silent)
        local numeric = tonumber(value)
        if not numeric then
            return self
        end
        numeric = Math.clamp(numeric, minimum, maximum)
        if element.Decimals <= 0 then
            numeric = Math.round(numeric, element.Step)
        else
            numeric = Math.decimals(numeric, element.Decimals)
        end
        if numeric ~= element.Value then
            element:SetValue(numeric, silent)
        end
        render()
        return self
    end

    local function setFromX(absoluteX)
        local width = math.max(hitbox.AbsoluteSize.X, 1)
        local alpha = Math.clamp((absoluteX - hitbox.AbsolutePosition.X) / width, 0, 1)
        local value = minimum + (maximum - minimum) * alpha
        value = Math.round(value, element.Step)
        if element.Decimals > 0 then
            value = Math.decimals(value, element.Decimals)
        end
        value = Math.clamp(value, minimum, maximum)
        if value ~= element.Value then
            element:SetValue(value)
        end
        render()
    end

    local dragging = false

    Connect(hitbox.InputBegan, function(input)
        if element.Disabled then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    Connect(UserInputService.InputChanged, function(input)
        if not dragging or element.Disabled then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            setFromX(input.Position.X)
        end
    end)

    Connect(valueInput.Focused, function()
        animate(valueStroke, { Color = C("Accent"), Transparency = 0.2 }, 0.1)
        valueInput.Text = String.formatNumber(element.Value, element.Decimals)
    end)

    Connect(valueInput.FocusLost, function()
        animate(valueStroke, { Color = C("Stroke"), Transparency = 0.2 }, 0.1)
        local numeric = tonumber(valueInput.Text)
        if numeric then
            element:Set(numeric)
        else
            render()
        end
    end)

    element:applyTheme(function()
        track.BackgroundColor3 = C("SurfaceHigh")
        fill.BackgroundColor3 = C("Accent")
        knob.BackgroundColor3 = C("Text")
        knobStroke.Color = C("Background")
        valueBox.BackgroundColor3 = C("Input")
        valueStroke.Color = C("Stroke")
        valueInput.TextColor3 = C("Text")
        render()
    end)

    render()
    return element
end

-- ============================================================================
-- 26. COMPONENTS — INPUT AND TEXTAREA
-- ============================================================================

function Section:Input(config, callback)
    config = config or {}
    config.Default = config.Default or ""

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    local slotWidth = tonumber(config.SlotWidth) or 170
    element:buildRow({
        Height = tonumber(config.Height) or 44,
        Icon = config.Icon,
        HasDescription = config.Description ~= nil,
        Reserved = -(slotWidth + 18),
        SlotWidth = slotWidth,
    })

    local box = UI.frame({
        Name = "Box",
        Parent = element.RightSlot,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = C("Input"),
    })
    UI.corner(UDim.new(0, 6)).Parent = box
    local boxStroke = UI.stroke(C("Stroke"), 1, 0.1)
    boxStroke.Parent = box
    UI.padding(0, 8, 0, 8).Parent = box

    local textBox = UI.textBox({
        Parent = box,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(element.Value or ""),
        PlaceholderText = config.Placeholder or "",
        TextSize = Argon.Theme.TextSizeSmall,
        TextColor3 = C("Text"),
        PlaceholderColor3 = C("TextDim"),
    })

    function element:Refresh()
        if not textBox:IsFocused() then
            textBox.Text = tostring(element.Value or "")
        end
        return self
    end

    function element:Set(value, silent)
        element:SetValue(value, silent)
        textBox.Text = tostring(value or "")
        return self
    end

    local committing = false

    local function commit(fireChanged)
        -- Writing to textBox.Text fires Changed again; without this guard a
        -- MaxLength clip or a live writeback recurses until the stack dies.
        if committing then
            return
        end
        committing = true
        local value = textBox.Text
        if config.Numeric then
            value = tonumber(value) or element.Value
        end
        if config.MaxLength and type(value) == "string" then
            value = value:sub(1, config.MaxLength)
            if textBox.Text ~= value then
                textBox.Text = value
            end
        end
        if value ~= element.Value then
            element:SetValue(value)
        elseif fireChanged then
            element:Fire(value)
        end
        committing = false
    end

    Connect(textBox.Focused, function()
        animate(boxStroke, { Color = C("Accent"), Transparency = 0.3 }, 0.12)
    end)

    Connect(textBox.FocusLost, function(enterPressed)
        animate(boxStroke, { Color = C("Stroke"), Transparency = 0.1 }, 0.12)
        commit(enterPressed and true or false)
    end)

    Connect(textBox:GetPropertyChangedSignal("Text"), function()
        if config.Live then
            commit(false)
        end
    end)

    element.TextBox = textBox

    element:applyTheme(function()
        box.BackgroundColor3 = C("Input")
        boxStroke.Color = C("Stroke")
        textBox.TextColor3 = C("Text")
        textBox.PlaceholderColor3 = C("TextDim")
    end)

    return element
end

function Section:Textarea(config, callback)
    config = config or {}
    config.Default = config.Default or ""

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    local height = tonumber(config.Height) or 108
    element.Row.Size = UDim2.new(element.Width == "half" and 0.5 or 1, element.Width == "half" and -3 or 0, 0, height)
    element.Row.BackgroundColor3 = C("Surface")
    element.Row.BackgroundTransparency = 0.35
    UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = element.Row
    local stroke = UI.stroke(C("Stroke"), 1, 0.5)
    stroke.Parent = element.Row
    UI.padding(10).Parent = element.Row
    UI.listLayout(6).Parent = element.Row

    if config.Name then
        element.NameLabel = UI.label({
            Parent = element.Row,
            Size = UDim2.new(1, 0, 0, 16),
            Text = tostring(config.Name),
            TextSize = Argon.Theme.TextSizeSmall,
            Font = Argon.Theme.FontMedium,
            TextColor3 = C("Text"),
        })
    end

    local box = UI.frame({
        Name = "Box",
        Parent = element.Row,
        Size = UDim2.new(1, 0, 1, -(config.Name and 22 or 0)),
        BackgroundColor3 = C("Input"),
    })
    UI.corner(UDim.new(0, 6)).Parent = box
    local boxStroke = UI.stroke(C("Stroke"), 1, 0.1)
    boxStroke.Parent = box
    UI.padding(6, 8, 6, 8).Parent = box

    local textBox = UI.textBox({
        Parent = box,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(element.Value or ""),
        PlaceholderText = config.Placeholder or "",
        MultiLine = true,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextSize = Argon.Theme.TextSizeSmall,
        TextColor3 = C("Text"),
    })

    function element:Refresh()
        if not textBox:IsFocused() then
            textBox.Text = tostring(element.Value or "")
        end
        return self
    end

    function element:Set(value, silent)
        element:SetValue(value, silent)
        textBox.Text = tostring(value or "")
        return self
    end

    Connect(textBox.Focused, function()
        animate(boxStroke, { Color = C("Accent"), Transparency = 0.3 }, 0.12)
    end)
    Connect(textBox.FocusLost, function()
        animate(boxStroke, { Color = C("Stroke"), Transparency = 0.1 }, 0.12)
        local value = textBox.Text
        if value ~= element.Value then
            element:SetValue(value)
        end
    end)

    element.TextBox = textBox

    element:applyTheme(function()
        element.Row.BackgroundColor3 = C("Surface")
        stroke.Color = C("Stroke")
        box.BackgroundColor3 = C("Input")
        boxStroke.Color = C("Stroke")
        textBox.TextColor3 = C("Text")
        if element.NameLabel then
            element.NameLabel.TextColor3 = C("Text")
        end
    end)

    return element
end

-- ============================================================================
-- 27. COMPONENTS — KEYBIND
-- ============================================================================

function Section:Keybind(config, callback)
    config = config or {}

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    element.Listening = false
    element.Mode = config.Mode or "toggle"

    local slot = element:buildRow({
        Height = tonumber(config.Height) or 44,
        Icon = config.Icon,
        HasDescription = config.Description ~= nil,
        Reserved = -120,
        SlotWidth = 108,
    })

    local keyButton = UI.button({
        Name = "KeyButton",
        Parent = slot,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = C("SurfaceHigh"),
        Text = "",
        TextSize = Argon.Theme.TextSizeSmall,
        TextColor3 = C("Text"),
        Font = Argon.Theme.FontMedium,
    })
    UI.corner(UDim.new(0, 6)).Parent = keyButton
    local keyStroke = UI.stroke(C("Stroke"), 1, 0)
    keyStroke.Parent = keyButton

    local function keyText()
        if element.Listening then
            return "Press a key…"
        end
        if element.Value == nil then
            return "None"
        end
        local name = tostring(element.Value.Name or element.Value)
        return name:gsub("KeyCode", ""):gsub("Enum.", "")
    end

    local function render()
        keyButton.Text = keyText()
        keyButton.TextColor3 = element.Listening and C("Accent") or (element.Value and C("Text") or C("TextDim"))
        if element.Flag then
            Argon.Flags[element.Flag] = element.Value
        end
    end

    function element:Refresh()
        render()
        return self
    end

    function element:Set(value, silent)
        if value == nil or isEnumItem(value) then
            element:SetValue(value, silent)
            render()
        end
        return self
    end

    function element:StartListening()
        element.Listening = true
        render()
        return self
    end

    function element:StopListening()
        element.Listening = false
        render()
        return self
    end

    Connect(keyButton.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element.Listening = not element.Listening
        render()
    end)

    Connect(UserInputService.InputBegan, function(input, processed)
        if element.Listening then
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            element.Listening = false
            if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                element:SetValue(nil)
            else
                element:SetValue(input.KeyCode)
            end
            render()
            return
        end

        if processed or element.Disabled then
            return
        end
        if element.Value and input.KeyCode == element.Value then
            element.Held = true
            element:Fire(true)
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if element.Value and input.KeyCode == element.Value then
            element.Held = false
            element:Fire(false)
        end
    end)

    element:applyTheme(function()
        keyButton.BackgroundColor3 = C("SurfaceHigh")
        keyStroke.Color = C("Stroke")
        render()
    end)

    render()
    return element
end

-- ============================================================================
-- 28. COMPONENTS — BUTTONS
-- ============================================================================

function Section:Button(config, callback)
    config = config or {}

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    local height = tonumber(config.Height) or 34
    element.Row.Size = UDim2.new(element.Width == "half" and 0.5 or 1, element.Width == "half" and -3 or 0, 0, height)

    local button = UI.button({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = config.Primary and C("Accent") or C("SurfaceHigh"),
        Text = tostring(config.Name or "Button"),
        TextSize = Argon.Theme.TextSize,
        TextColor3 = config.Primary and C("AccentText") or C("Text"),
        Font = Argon.Theme.FontMedium,
        ClipsDescendants = true,
    })
    UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = button
    local stroke = UI.stroke(C("Stroke"), 1, config.Primary and 1 or 0.9)
    stroke.Parent = button

    if config.Icon then
        UI.glyph(config.Icon, 13, config.Primary and C("AccentText") or C("TextMuted"), {
            Parent = button,
            Position = UDim2.new(0, 12, 0, 0),
            Size = UDim2.new(0, 16, 1, 0),
        })
        UI.padding(0, 0, 0, 16).Parent = button
    end

    local function baseColor()
        if config.Primary then
            return C("Accent")
        end
        return C("SurfaceHigh")
    end

    Connect(button.MouseEnter, function()
        if element.Disabled then
            return
        end
        animate(button, { BackgroundColor3 = config.Primary and Color.lighten(C("Accent"), 0.1) or C("SurfaceHover") }, 0.12)
        animate(stroke, { Color = config.Primary and C("Accent") or C("StrokeLight") }, 0.12)
    end)

    Connect(button.MouseLeave, function()
        animate(button, { BackgroundColor3 = baseColor() }, 0.12)
        animate(stroke, { Color = C("Stroke") }, 0.12)
    end)

    Connect(button.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        if config.Confirm then
            local pending = button.Text
            button.Text = "Click again to confirm"
            task.delay(2, function()
                if button.Parent then
                    button.Text = pending
                end
            end)
            if not element._confirming then
                element._confirming = true
                task.delay(2, function()
                    element._confirming = false
                end)
                return
            end
            element._confirming = false
            button.Text = pending
        end
        element:Fire()
    end)

    function element:SetText(text)
        button.Text = tostring(text)
        return self
    end

    function element:SetDisabled(disabled)
        element.Disabled = disabled and true or false
        button.Active = not element.Disabled
        button.TextTransparency = element.Disabled and 0.45 or 0
        button.BackgroundTransparency = element.Disabled and 0.4 or 0
        return self
    end

    element:applyTheme(function()
        button.BackgroundColor3 = baseColor()
        button.TextColor3 = config.Primary and C("AccentText") or C("Text")
        stroke.Color = C("Stroke")
    end)

    return element
end

function Section:DualButton(config, callbackLeft, callbackRight)
    config = config or {}

    local element = Element.new(self, config)
    local height = tonumber(config.Height) or 32

    element.Row.Size = UDim2.new(element.Width == "half" and 0.5 or 1, element.Width == "half" and -3 or 0, 0, height)

    local holder = UI.frame({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = C("SurfaceHigh"),
    })
    UI.corner(UDim.new(0, 6)).Parent = holder
    UI.stroke(C("Stroke"), 1, 0.9).Parent = holder

    local left = UI.button({
        Parent = holder,
        Size = UDim2.new(0.5, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(config.Name or "Left"),
        TextSize = Argon.Theme.TextSizeSmall,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("Text"),
    })

    local divider = UI.frame({
        Parent = holder,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 1, 1, -12),
        BackgroundColor3 = C("Stroke"),
    })

    local right = UI.button({
        Parent = holder,
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = tostring(config.AlternateName or config.SecondName or "Right"),
        TextSize = Argon.Theme.TextSizeSmall,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("TextMuted"),
    })

    Connect(left.MouseEnter, function()
        animate(left, { BackgroundColor3 = C("SurfaceHover"), BackgroundTransparency = 0.5 }, 0.1)
    end)
    Connect(left.MouseLeave, function()
        animate(left, { BackgroundTransparency = 1 }, 0.1)
    end)
    Connect(right.MouseEnter, function()
        animate(right, { BackgroundColor3 = C("SurfaceHover"), BackgroundTransparency = 0.5 }, 0.1)
    end)
    Connect(right.MouseLeave, function()
        animate(right, { BackgroundTransparency = 1 }, 0.1)
    end)

    Connect(left.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element:Fire("left")
        if callbackLeft then
            pcall(callbackLeft)
        end
    end)
    Connect(right.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element:Fire("right")
        if callbackRight then
            pcall(callbackRight)
        end
    end)

    function element:SetTexts(leftText, rightText)
        left.Text = tostring(leftText)
        right.Text = tostring(rightText)
        return self
    end

    element:applyTheme(function()
        holder.BackgroundColor3 = C("SurfaceHigh")
        divider.BackgroundColor3 = C("Stroke")
        left.TextColor3 = C("Text")
        right.TextColor3 = C("TextMuted")
    end)

    return element
end

-- ============================================================================
-- 29. COMPONENTS — STATIC CONTENT
-- ============================================================================

function Section:Label(config)
    if type(config) == "string" then
        config = { Text = config }
    end
    config = config or {}

    local element = Element.new(self, config)
    element.Row.Size = UDim2.new(1, 0, 0, tonumber(config.Height) or 20)
    element.Row.AutomaticSize = Enum.AutomaticSize.Y
    UI.padding(config.Padding or 2).Parent = element.Row

    element.NameLabel = UI.label({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(config.Text or ""),
        TextSize = config.TextSize or Argon.Theme.TextSizeSmall,
        Font = config.Bold and Argon.Theme.FontBold or Argon.Theme.Font,
        TextColor3 = config.Color or C("TextMuted"),
        TextWrapped = config.Wrap ~= false,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextXAlignment = config.Align == "center" and Enum.TextXAlignment.Center
            or (config.Align == "right" and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left),
    })

    element:applyTheme(function(theme)
        element.NameLabel.TextColor3 = config.Color or theme.TextMuted
    end)

    return element
end

function Section:Paragraph(config)
    config = config or {}

    local element = Element.new(self, config)
    element.Row.Size = UDim2.new(1, 0, 0, 0)
    element.Row.AutomaticSize = Enum.AutomaticSize.Y
    UI.padding(2).Parent = element.Row
    UI.listLayout(3).Parent = element.Row

    if config.Title and config.Title ~= "" then
        element.NameLabel = UI.label({
            Parent = element.Row,
            Size = UDim2.new(1, 0, 0, 16),
            Text = tostring(config.Title),
            TextSize = Argon.Theme.TextSizeSmall,
            Font = Argon.Theme.FontMedium,
            TextColor3 = C("Text"),
            LayoutOrder = 1,
        })
    end

    element.DescriptionLabel = UI.label({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(config.Text or config.Content or ""),
        TextSize = config.TextSize or Argon.Theme.TextSizeTiny,
        TextColor3 = C("TextDim"),
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 2,
    })

    element:applyTheme(function(theme)
        if element.NameLabel then
            element.NameLabel.TextColor3 = theme.Text
        end
        element.DescriptionLabel.TextColor3 = theme.TextDim
    end)

    return element
end

function Section:Divider()
    local element = Element.new(self, { Name = "Divider" })
    element.Row.Size = UDim2.new(1, 0, 0, 9)

    local line = UI.frame({
        Parent = element.Row,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = C("Stroke"),
        BackgroundTransparency = 0.3,
    })

    element:applyTheme(function(theme)
        line.BackgroundColor3 = theme.Stroke
    end)

    return element
end

function Section:Space(height)
    local element = Element.new(self, { Name = "Space" })
    element.Row.Size = UDim2.new(1, 0, 0, tonumber(height) or 8)
    return element
end

function Section:Progress(config)
    config = config or {}

    local element = Element.new(self, config)
    element.Progress = tonumber(config.Default) or 0

    element:buildRow({
        Height = tonumber(config.Height) or 52,
        Icon = config.Icon,
        HasDescription = config.Description ~= nil,
        Reserved = -60,
        SlotWidth = 52,
    })

    local valueLabel = UI.label({
        Parent = element.RightSlot,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 8),
        Size = UDim2.new(1, 0, 0, 18),
        Text = "0%",
        TextSize = Argon.Theme.TextSizeTiny,
        Font = Argon.Theme.FontBold,
        TextColor3 = C("Accent"),
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    local track = UI.frame({
        Parent = element.Row,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -14),
        Size = UDim2.new(1, 0, 0, 5),
        BackgroundColor3 = C("SurfaceHigh"),
    })
    UI.corner(UDim.new(1, 0)).Parent = track

    local fill = UI.frame({
        Parent = track,
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = C("Accent"),
    })
    UI.corner(UDim.new(1, 0)).Parent = fill

    local function render(animated)
        local alpha = Math.clamp(element.Progress / 100, 0, 1)
        if animated then
            animate(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, 0.3)
        else
            fill.Size = UDim2.new(alpha, 0, 1, 0)
        end
        valueLabel.Text = tostring(math.floor(alpha * 100)) .. "%"
    end

    function element:SetProgress(value, animated)
        element.Progress = Math.clamp(tonumber(value) or 0, 0, 100)
        render(animated ~= false)
        return self
    end

    function element:GetProgress()
        return element.Progress
    end

    function element:Refresh()
        render(false)
        return self
    end

    element:applyTheme(function()
        track.BackgroundColor3 = C("SurfaceHigh")
        fill.BackgroundColor3 = C("Accent")
        valueLabel.TextColor3 = C("Accent")
    end)

    render(false)
    return element
end

function Section:Tag(config)
    config = config or {}
    if type(config) == "string" then
        config = { Name = config }
    end

    local element = Element.new(self, config)
    element.Row.Size = UDim2.new(1, 0, 0, 28)
    element.Row.AutomaticSize = Enum.AutomaticSize.Y

    local holder = UI.transparent({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 0, 0),
    })
    local layout = UI.listLayout(6, true)
    layout.Parent = holder

    local tags = config.Tags or {
        { Text = config.Name or "tag", Color = accent() },
    }

    element.TagButtons = {}
    for index, tag in ipairs(tags) do
        if type(tag) == "string" then
            tag = { Text = tag }
        end
        local badge, label = UI.badge(tag.Text or "", tag.Color or C("Accent"), nil, {
            Parent = holder,
            LayoutOrder = index,
            TextSize = 10,
        })
        table.insert(element.TagButtons, { Badge = badge, Label = label, Data = tag })
    end

    return element
end

function Section:UserRow(config)
    config = config or {}

    local element = Element.new(self, config)
    element:buildRow({
        Height = tonumber(config.Height) or 52,
        Icon = config.Icon,
        HasDescription = false,
        Reserved = -(config.SlotWidth or 40),
        SlotWidth = config.SlotWidth or 40,
    })

    local avatar = UI.frame({
        Parent = element.Row,
        Position = UDim2.new(0, 0, 0.5, -15),
        Size = UDim2.new(0, 30, 0, 30),
        BackgroundColor3 = config.Color or C("Accent"),
    })
    UI.corner(UDim.new(1, 0)).Parent = avatar

    if config.Avatar then
        UI.image({
            Parent = avatar,
            Size = UDim2.new(1, 0, 1, 0),
            Image = tostring(config.Avatar),
        })
    else
        UI.glyph((config.Name or "U"):sub(1, 1):upper(), 12, C("AccentText"), {
            Parent = avatar,
            Size = UDim2.new(1, 0, 1, 0),
        })
    end

    element.NameLabel.Position = UDim2.new(0, 0, 0.5, -6)
    element.NameLabel.AnchorPoint = Vector2.new(0, 0)
    element.NameLabel.Parent = element.Row
    element.NameLabel.Position = UDim2.new(0, 40, 0, 9)
    element.NameLabel.Size = UDim2.new(1, -90, 0, 16)

    element.DescriptionLabel = UI.label({
        Parent = element.Row,
        Position = UDim2.new(0, 40, 0, 26),
        Size = UDim2.new(1, -90, 0, 14),
        Text = tostring(config.Description or config.Role or ""),
        TextSize = Argon.Theme.TextSizeTiny,
        TextColor3 = C("TextDim"),
    })

    return element
end

-- ============================================================================
-- 30. COMPONENTS — DROPDOWN
-- ============================================================================

local function normalizeOption(option, index)
    if type(option) == "table" then
        return {
            Text = tostring(option.Text or option.Name or option.Value or ("Option " .. index)),
            Value = option.Value ~= nil and option.Value or option.Text or option.Name,
            Description = option.Description,
            Icon = option.Icon,
            Disabled = option.Disabled,
        }
    end
    return {
        Text = tostring(option),
        Value = option,
    }
end

function Section:Dropdown(config, callback)
    config = config or {}

    local multi = config.Multi and true or false
    if multi then
        config.Default = type(config.Default) == "table" and config.Default or {}
    end

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    element.Multi = multi
    element.Options = {}
    element.Open = false
    element.MaxHeight = tonumber(config.MaxHeight) or 160
    element.SearchEnabled = config.Search ~= false

    for index, option in ipairs(config.Options or {}) do
        element.Options[index] = normalizeOption(option, index)
    end

    local header = UI.button({
        Name = "Header",
        Parent = element.Row,
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = C("Surface"),
        BackgroundTransparency = 0.35,
        Text = "",
        ClipsDescendants = true,
    })
    UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = header
    local headerStroke = UI.stroke(C("Stroke"), 1, 0.55)
    headerStroke.Parent = header
    UI.padding(0, 10, 0, 12).Parent = header

    if config.Icon then
        UI.glyph(tostring(config.Icon), 14, C("TextMuted"), {
            Parent = header,
            Position = UDim2.new(0, 24, 0, 0),
            Size = UDim2.new(0, 16, 1, 0),
        })
    end

    element.NameLabel = UI.label({
        Parent = header,
        Position = UDim2.new(0, config.Icon and 46 or 32, 0, 0),
        Size = UDim2.new(1, -140, 1, 0),
        Text = tostring(config.Name or ""),
        TextSize = Argon.Theme.TextSize,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("Text"),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local summary = UI.label({
        Parent = header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -22, 0.5, 0),
        Size = UDim2.new(0, 120, 0, 16),
        Text = "None",
        TextSize = Argon.Theme.TextSizeTiny,
        TextColor3 = C("TextDim"),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local chevron = UI.glyph("⌄", 14, C("TextDim"), {
        Parent = header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.new(0, 14, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local listHolder = UI.frame({
        Name = "List",
        Parent = element.Row,
        Position = UDim2.new(0, 6, 0, 46),
        Size = UDim2.new(1, -12, 0, 0),
        BackgroundColor3 = C("SurfaceHigh"),
        Visible = false,
        ClipsDescendants = true,
    })
    UI.corner(UDim.new(0, 6)).Parent = listHolder
    UI.stroke(C("Stroke"), 1, 0.3).Parent = listHolder
    UI.padding(4).Parent = listHolder

    local searchBox
    local optionsScroller
    local optionsHolder
    local optionsLayout

    local function isSelected(value)
        if multi then
            for _, selected in ipairs(element.Value or {}) do
                if selected == value then
                    return true
                end
            end
            return false
        end
        return element.Value == value
    end

    local function summaryText()
        if multi then
            local selected = element.Value or {}
            if #selected == 0 then
                return "None"
            end
            if #selected <= 2 then
                local names = {}
                for _, value in ipairs(selected) do
                    names[#names + 1] = tostring(value)
                end
                return table.concat(names, ", ")
            end
            return tostring(#selected) .. " selected"
        end
        if element.Value == nil then
            return "None"
        end
        for _, option in ipairs(element.Options) do
            if option.Value == element.Value then
                return option.Text
            end
        end
        return tostring(element.Value)
    end

    local optionRows = {}

    local function applyQuery(query)
        query = String.trim(tostring(query or "")):lower()
        for _, entry in ipairs(optionRows) do
            local matches = query == "" or entry.Option.Text:lower():find(query, 1, true) ~= nil
            entry.Button.Visible = matches
        end
    end

    local function buildOptions()
        for _, child in ipairs(optionsHolder:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end
        optionRows = {}

        for index, option in ipairs(element.Options) do
            local rowButton = UI.button({
                Name = "Option_" .. tostring(index),
                Parent = optionsHolder,
                Size = UDim2.new(1, 0, 0, option.Description and 40 or 28),
                BackgroundColor3 = C("SurfaceHigh"),
                Text = "",
                LayoutOrder = index,
            })
            UI.corner(UDim.new(0, 5)).Parent = rowButton
            UI.padding(0, 8, 0, 8).Parent = rowButton

            local label = UI.label({
                Parent = rowButton,
                Position = UDim2.new(0, option.Icon and 22 or 0, 0, option.Description and 5 or 0),
                Size = UDim2.new(1, -26, 0, 16),
                Text = option.Text,
                TextSize = Argon.Theme.TextSizeSmall,
                Font = Argon.Theme.FontMedium,
                TextColor3 = C("Text"),
                TextTruncate = Enum.TextTruncate.AtEnd,
            })

            if option.Icon then
                UI.glyph(tostring(option.Icon), 12, C("TextMuted"), {
                    Parent = rowButton,
                    Position = UDim2.new(0, 0, 0, 6),
                    Size = UDim2.new(0, 16, 0, 16),
                })
            end

            if option.Description then
                UI.label({
                    Parent = rowButton,
                    Position = UDim2.new(0, option.Icon and 22 or 0, 0, 21),
                    Size = UDim2.new(1, -26, 0, 14),
                    Text = tostring(option.Description),
                    TextSize = Argon.Theme.TextSizeTiny,
                    TextColor3 = C("TextDim"),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                })
            end

            local tick = UI.glyph(multi and "✓" or "•", 12, C("Accent"), {
                Parent = rowButton,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.new(0, 14, 0, 14),
                TextXAlignment = Enum.TextXAlignment.Center,
                Visible = false,
            })

            local entry = {
                Option = option,
                Button = rowButton,
                Label = label,
                Tick = tick,
            }
            table.insert(optionRows, entry)

            Connect(rowButton.MouseEnter, function()
                if not isSelected(option.Value) then
                    animate(rowButton, { BackgroundColor3 = C("SurfaceActive") }, 0.1)
                end
            end)
            Connect(rowButton.MouseLeave, function()
                if not isSelected(option.Value) then
                    animate(rowButton, { BackgroundColor3 = C("SurfaceHigh") }, 0.1)
                end
            end)
            Connect(rowButton.MouseButton1Click, function()
                if option.Disabled or element.Disabled then
                    return
                end
                if multi then
                    local selected = {}
                    local found = false
                    for _, value in ipairs(element.Value or {}) do
                        if value == option.Value then
                            found = true
                        else
                            selected[#selected + 1] = value
                        end
                    end
                    if not found then
                        selected[#selected + 1] = option.Value
                    end
                    element:SetValue(selected)
                else
                    element:SetValue(option.Value)
                    element:Close()
                end
                element:renderOptions()
            end)
        end

        element:renderOptions()
    end

    function element:renderOptions()
        summary.Text = summaryText()
        for _, entry in ipairs(optionRows) do
            local selected = isSelected(entry.Option.Value)
            entry.Button.BackgroundColor3 = selected and C("SurfaceActive") or C("SurfaceHigh")
            entry.Label.TextColor3 = selected and C("Accent") or C("Text")
            entry.Tick.Visible = selected
            if entry.Option.Disabled then
                entry.Label.TextColor3 = C("TextDim")
            end
        end
        if element.Flag then
            Argon.Flags[element.Flag] = element.Value
        end
    end

    function element:Refresh()
        self:renderOptions()
        return self
    end

    function element:OpenList()
        if element.Open then
            return self
        end
        element.Open = true
        listHolder.Visible = true
        animate(chevron, { Rotation = 180 }, 0.12)

        local height = 8
        if searchBox then
            height = height + 34
        end
        local contentHeight = optionsLayout.AbsoluteContentSize.Y
        height = height + math.min(contentHeight, element.MaxHeight)
        listHolder.Size = UDim2.new(1, -12, 0, height)
        listHolder.BackgroundTransparency = 1
        animate(listHolder, { BackgroundTransparency = 0 }, 0.12)

        if scrollToElement and element.Section and element.Section.Page then
            scrollToElement(element.Section.Page.Scroller, element.Row)
        end
        return self
    end

    function element:Close()
        if not element.Open then
            return self
        end
        element.Open = false
        listHolder.Visible = false
        listHolder.Size = UDim2.new(1, -12, 0, 0)
        animate(chevron, { Rotation = 0 }, 0.12)
        return self
    end

    function element:ToggleList()
        if element.Open then
            return self:Close()
        end
        return self:OpenList()
    end

    function element:SetOptions(options)
        if type(options) ~= "table" then
            return self
        end
        element.Options = {}
        for index, option in ipairs(options) do
            element.Options[index] = normalizeOption(option, index)
        end
        buildOptions()
        return self
    end

    function element:GetOptions()
        return element.Options
    end

    function element:Set(value, silent)
        element:SetValue(value, silent)
        element:renderOptions()
        return self
    end

    optionsScroller = UI.scroller({
        Name = "Options",
        Parent = listHolder,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
    })
    optionsHolder = UI.transparent({
        Parent = optionsScroller,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    optionsLayout = UI.listLayout(2)
    optionsLayout.Parent = optionsHolder
    bindCanvas(optionsScroller, optionsLayout, 0)

    if element.SearchEnabled then
        local searchFrame = UI.frame({
            Parent = listHolder,
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundColor3 = C("Input"),
            LayoutOrder = 0,
        })
        UI.corner(UDim.new(0, 5)).Parent = searchFrame
        UI.padding(0, 8, 0, 8).Parent = searchFrame
        searchBox = UI.textBox({
            Parent = searchFrame,
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            PlaceholderText = "Search…",
            TextSize = Argon.Theme.TextSizeTiny,
            TextColor3 = C("Text"),
        })
        Connect(searchBox:GetPropertyChangedSignal("Text"), function()
            applyQuery(searchBox.Text)
        end)
        optionsScroller.Position = UDim2.new(0, 0, 0, 34)
        optionsScroller.Size = UDim2.new(1, 0, 1, -34)
    end

    Connect(header.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element:ToggleList()
    end)
    Connect(header.MouseEnter, function()
        if not element.Open then
            animate(header, { BackgroundColor3 = C("SurfaceHover"), BackgroundTransparency = 0.2 }, 0.12)
        end
    end)
    Connect(header.MouseLeave, function()
        if not element.Open then
            animate(header, { BackgroundColor3 = C("Surface"), BackgroundTransparency = 0.35 }, 0.12)
            animate(headerStroke, { Transparency = 0.55 }, 0.12)
        end
    end)

    buildOptions()

    -- close when clicking elsewhere
    Connect(UserInputService.InputBegan, function(input)
        if not element.Open then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            local position = input.Position
            local minX = listHolder.AbsolutePosition.X
            local minY = listHolder.AbsolutePosition.Y
            local maxX = minX + listHolder.AbsoluteSize.X
            local maxY = minY + listHolder.AbsoluteSize.Y + 46
            if position.X < minX or position.X > maxX or position.Y < minY or position.Y > maxY then
                element:Close()
            end
        end
    end)

    element:applyTheme(function()
        header.BackgroundColor3 = C("Surface")
        headerStroke.Color = C("Stroke")
        summary.TextColor3 = C("TextDim")
        chevron.TextColor3 = C("TextDim")
        listHolder.BackgroundColor3 = C("SurfaceHigh")
        element:renderOptions()
    end)

    return element
end

-- ============================================================================
-- 31. COMPONENTS — COLOR PICKER
-- ============================================================================

function Section:ColorPicker(config, callback)
    config = config or {}
    config.Default = isColor(config.Default) and config.Default or Color3.fromRGB(56, 132, 255)

    local element = Element.new(self, config)
    if isCallable(callback) then
        element:OnChanged(callback)
    end

    element.Open = false
    element.Alpha = tonumber(config.Alpha) or 1
    element.Hue, element.Saturation, element.Brightness = Color.rgbToHsv(element.Value)
    element.Rainbow = false
    element.EyedropperCallback = config.Eyedropper

    local swatchSize = tonumber(config.SwatchSize) or 34
    element:buildRow({
        Height = tonumber(config.Height) or 44,
        Icon = config.Icon,
        HasDescription = config.Description ~= nil,
        Reserved = -(swatchSize + 40),
        SlotWidth = swatchSize + 24,
    })

    local swatch = UI.frame({
        Name = "Swatch",
        Parent = element.RightSlot,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, swatchSize, 0, 24),
        BackgroundColor3 = element.Value,
    })
    UI.corner(UDim.new(0, 6)).Parent = swatch
    local swatchStroke = UI.stroke(C("StrokeLight"), 1, 0.2)
    swatchStroke.Parent = swatch

    local swatchButton = UI.button({
        Parent = swatch,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
    })

    local chevron = UI.glyph("⌄", 12, C("TextDim"), {
        Parent = element.RightSlot,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -36, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 12),
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    -- panel -------------------------------------------------------------
    local panel = UI.frame({
        Name = "Panel",
        Parent = element.Row,
        Position = UDim2.new(0, 6, 0, 46),
        Size = UDim2.new(1, -12, 0, 0),
        BackgroundColor3 = C("SurfaceHigh"),
        Visible = false,
        ClipsDescendants = true,
    })
    UI.corner(UDim.new(0, 8)).Parent = panel
    UI.stroke(C("Stroke"), 1, 0.3).Parent = panel
    UI.padding(10).Parent = panel

    local satValSize = tonumber(config.SquareSize) or 132
    local satVal = UI.frame({
        Parent = panel,
        Size = UDim2.new(1, 0, 0, satValSize),
        BackgroundColor3 = Color.hsvToRgb(element.Hue, 1, 1),
        ClipsDescendants = true,
    })
    UI.corner(UDim.new(0, 6)).Parent = satVal

    local whiteOverlay = UI.frame({
        Parent = satVal,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
    })
    local whiteGradient = UI.gradient(Color3.new(1, 1, 1), Color3.new(1, 1, 1), 0, 0, 1)
    whiteGradient.Parent = whiteOverlay

    local blackOverlay = UI.frame({
        Parent = satVal,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
    })
    local blackGradient = UI.gradient(Color3.new(0, 0, 0), Color3.new(0, 0, 0), 90, 0, 1)
    blackGradient.Parent = blackOverlay

    local marker = UI.frame({
        Parent = satVal,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.new(0, 10, 0, 10),
        BackgroundTransparency = 1,
    })
    UI.corner(UDim.new(1, 0)).Parent = marker
    UI.stroke(Color3.new(1, 1, 1), 2, 0).Parent = marker

    local satValHitbox = UI.button({
        Parent = satVal,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
    })

    local hueBar = UI.frame({
        Parent = panel,
        Position = UDim2.new(0, 0, 0, satValSize + 10),
        Size = UDim2.new(1, -54, 0, 12),
        BackgroundColor3 = Color3.new(1, 0, 0),
    })
    UI.corner(UDim.new(1, 0)).Parent = hueBar
    local hueGradient = Instance.new("UIGradient")
    hueGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
    })
    hueGradient.Parent = hueBar

    local hueMarker = UI.frame({
        Parent = hueBar,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(element.Hue, 0, 0.5, 0),
        Size = UDim2.new(0, 6, 0, 16),
        BackgroundColor3 = Color3.new(1, 1, 1),
    })
    UI.corner(UDim.new(1, 0)).Parent = hueMarker

    local hueHitbox = UI.button({
        Parent = hueBar,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
    })

    local alphaBar = UI.frame({
        Parent = panel,
        Position = UDim2.new(0, 0, 0, satValSize + 30),
        Size = UDim2.new(1, -54, 0, 12),
        BackgroundColor3 = Color3.new(1, 1, 1),
    })
    UI.corner(UDim.new(1, 0)).Parent = alphaBar
    local alphaFill = UI.frame({
        Parent = alphaBar,
        Size = UDim2.new(element.Alpha, 0, 1, 0),
        BackgroundColor3 = element.Value,
    })
    UI.corner(UDim.new(1, 0)).Parent = alphaFill
    local alphaHitbox = UI.button({
        Parent = alphaBar,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
    })

    local hexBox = UI.frame({
        Parent = panel,
        Position = UDim2.new(0, 0, 0, satValSize + 50),
        Size = UDim2.new(0, 96, 0, 26),
        BackgroundColor3 = C("Input"),
    })
    UI.corner(UDim.new(0, 5)).Parent = hexBox
    UI.padding(0, 6, 0, 6).Parent = hexBox

    local hexInput = UI.textBox({
        Parent = hexBox,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "3884FF",
        TextSize = Argon.Theme.TextSizeTiny,
        Font = Argon.Theme.FontMono,
        TextColor3 = C("Text"),
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local rainbowButton = UI.button({
        Parent = panel,
        Position = UDim2.new(0, 102, 0, satValSize + 50),
        Size = UDim2.new(0, 26, 0, 26),
        BackgroundColor3 = C("Input"),
        Text = "◌",
        TextSize = 13,
        TextColor3 = C("TextMuted"),
    })
    UI.corner(UDim.new(0, 5)).Parent = rainbowButton
    attachTooltip(rainbowButton, "Cycle hue")

    local eyedropperButton = UI.button({
        Parent = panel,
        Position = UDim2.new(0, 132, 0, satValSize + 50),
        Size = UDim2.new(0, 26, 0, 26),
        BackgroundColor3 = C("Input"),
        Text = "⊙",
        TextSize = 13,
        TextColor3 = C("TextMuted"),
    })
    UI.corner(UDim.new(0, 5)).Parent = eyedropperButton
    attachTooltip(eyedropperButton, "Pick a color")

    local presets = config.Presets or {
        Color3.fromRGB(56, 132, 255),
        Color3.fromRGB(52, 196, 168),
        Color3.fromRGB(146, 118, 255),
        Color3.fromRGB(240, 92, 96),
        Color3.fromRGB(240, 178, 64),
        Color3.fromRGB(92, 214, 154),
        Color3.fromRGB(255, 255, 255),
        Color3.fromRGB(20, 21, 26),
    }

    local presetHolder = UI.transparent({
        Parent = panel,
        Position = UDim2.new(0, 0, 0, satValSize + 84),
        Size = UDim2.new(1, 0, 0, 20),
    })
    local presetLayout = UI.listLayout(6, true)
    presetLayout.Parent = presetHolder

    for index, presetColor in ipairs(presets) do
        local swatchButtonSmall = UI.button({
            Parent = presetHolder,
            Size = UDim2.new(0, 18, 0, 18),
            BackgroundColor3 = presetColor,
            Text = "",
        })
        UI.corner(UDim.new(0, 5)).Parent = swatchButtonSmall
        UI.stroke(C("StrokeLight"), 1, 0.4).Parent = swatchButtonSmall
        Connect(swatchButtonSmall.MouseButton1Click, function()
            element:SetColor(presetColor)
        end)
    end

    local function alphaColor()
        return element.Value
    end

    local function render()
        local hueColor = Color.hsvToRgb(element.Hue, 1, 1)
        satVal.BackgroundColor3 = hueColor
        marker.Position = UDim2.new(element.Saturation, 0, 1 - element.Brightness, 0)
        hueMarker.Position = UDim2.new(element.Hue, 0, 0.5, 0)
        swatch.BackgroundColor3 = element.Value
        swatch.BackgroundTransparency = 1 - element.Alpha
        alphaFill.BackgroundColor3 = alphaColor()
        alphaFill.Size = UDim2.new(element.Alpha, 0, 1, 0)
        if not hexInput:IsFocused() then
            hexInput.Text = Color.toHex(element.Value)
        end
        if element.Flag then
            Argon.Flags[element.Flag] = element.Value
        end
    end

    function element:Refresh()
        local color = element.Value
        if isColor(color) then
            element.Hue, element.Saturation, element.Brightness = Color.rgbToHsv(color)
        end
        render()
        return self
    end

    function element:SetColor(color, silent)
        if not isColor(color) then
            return self
        end
        element.Hue, element.Saturation, element.Brightness = Color.rgbToHsv(color)
        element:SetValue(color, silent)
        render()
        return self
    end

    function element:Set(value, silent)
        return self:SetColor(value, silent)
    end

    function element:SetAlpha(alpha, silent)
        element.Alpha = Math.clamp(tonumber(alpha) or 1, 0, 1)
        if element.Flag then
            Argon.Flags[element.Flag .. "_alpha"] = element.Alpha
        end
        if not silent then
            element:Fire(element.Value)
        end
        render()
        return self
    end

    function element:GetAlpha()
        return element.Alpha
    end

    local function applyHsv()
        local color = Color.hsvToRgb(element.Hue, element.Saturation, element.Brightness)
        element:HsvChanged(color)
    end

    function element:HsvChanged(color)
        element.Value = color
        if element.Flag then
            Argon.Flags[element.Flag] = color
        end
        element:Fire(color)
        render()
    end

    local function updateSatVal(x, y)
        local size = satVal.AbsoluteSize
        element.Saturation = Math.clamp((x - satVal.AbsolutePosition.X) / math.max(size.X, 1), 0, 1)
        element.Brightness = 1 - Math.clamp((y - satVal.AbsolutePosition.Y) / math.max(size.Y, 1), 0, 1)
        applyHsv()
    end

    local function updateHue(x)
        local size = hueBar.AbsoluteSize
        element.Hue = Math.clamp((x - hueBar.AbsolutePosition.X) / math.max(size.X, 1), 0, 1)
        applyHsv()
    end

    local function updateAlpha(x)
        local size = alphaBar.AbsoluteSize
        element.Alpha = Math.clamp((x - alphaBar.AbsolutePosition.X) / math.max(size.X, 1), 0, 1)
        if element.Flag then
            Argon.Flags[element.Flag .. "_alpha"] = element.Alpha
        end
        render()
    end

    local draggingSV, draggingHue, draggingAlpha = false, false, false

    Connect(satValHitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV = true
            updateSatVal(input.Position.X, input.Position.Y)
        end
    end)
    Connect(hueHitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingHue = true
            updateHue(input.Position.X)
        end
    end)
    Connect(alphaHitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingAlpha = true
            updateAlpha(input.Position.X)
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV, draggingHue, draggingAlpha = false, false, false
        end
    end)

    Connect(UserInputService.InputChanged, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if draggingSV then
            updateSatVal(input.Position.X, input.Position.Y)
        elseif draggingHue then
            updateHue(input.Position.X)
        elseif draggingAlpha then
            updateAlpha(input.Position.X)
        end
    end)

    Connect(hexInput.FocusLost, function()
        local parsed = Color.hex(hexInput.Text)
        if parsed then
            element:SetColor(parsed)
        else
            render()
        end
    end)

    Connect(rainbowButton.MouseButton1Click, function()
        element.Hue = (element.Hue + 0.08) % 1
        applyHsv()
    end)

    Connect(eyedropperButton.MouseButton1Click, function()
        if isCallable(element.EyedropperCallback) then
            local ok, picked = pcall(element.EyedropperCallback)
            if ok and isColor(picked) then
                element:SetColor(picked)
                return
            end
        end
        if isCallable(config.OnEyedropper) then
            pcall(config.OnEyedropper, element)
        else
            Argon:Notify({
                Kind = "info",
                Title = "Color picker",
                Text = "Pass Eyedropper = function() return Color3.new(...) end to sample colors.",
                Duration = 5,
            })
        end
    end)

    Connect(swatchButton.MouseButton1Click, function()
        element.Open = not element.Open
        panel.Visible = element.Open
        panel.Size = UDim2.new(1, -12, 0, element.Open and (satValSize + 114) or 0)
        animate(chevron, { Rotation = element.Open and 180 or 0 }, 0.12)
    end)

    element:applyTheme(function()
        panel.BackgroundColor3 = C("SurfaceHigh")
        hexBox.BackgroundColor3 = C("Input")
        hexInput.TextColor3 = C("Text")
        rainbowButton.BackgroundColor3 = C("Input")
        eyedropperButton.BackgroundColor3 = C("Input")
        render()
    end)

    render()
    return element
end

-- ============================================================================
-- 32. COMPONENTS — THEME PICKER
-- ============================================================================

function Section:ThemePicker(config)
    config = config or {}

    local element = Element.new(self, config)
    element.Row.Size = UDim2.new(1, 0, 0, 0)
    element.Row.AutomaticSize = Enum.AutomaticSize.Y
    element.Row.BackgroundColor3 = C("Surface")
    element.Row.BackgroundTransparency = 0.35
    UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = element.Row
    element.Stroke = UI.stroke(C("Stroke"), 1, 0.55)
    element.Stroke.Parent = element.Row
    UI.padding(12).Parent = element.Row
    UI.listLayout(10).Parent = element.Row

    if config.Name then
        element.NameLabel = UI.label({
            Parent = element.Row,
            Size = UDim2.new(1, 0, 0, 16),
            Text = tostring(config.Name),
            TextSize = Argon.Theme.TextSizeSmall,
            Font = Argon.Theme.FontMedium,
            TextColor3 = C("Text"),
        })
    end

    local names = config.Themes or Argon:GetThemeNames()
    local columns = tonumber(config.Columns) or 5
    local rows = math.ceil(#names / columns)
    local cellHeight = 74
    local grid = UI.transparent({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 0, rows * (cellHeight + 8)),
    })
    local gridLayout = UI.gridLayout(
        UDim2.new(1 / columns, -6, 0, cellHeight),
        UDim2.new(0, 6, 0, 8)
    )
    gridLayout.Parent = grid

    element.Cards = {}

    local function refreshSelection()
        for name, entry in pairs(element.Cards) do
            local selected = name == Argon.ThemeName
            entry.Stroke.Color = selected and C("Accent") or C("Stroke")
            entry.Stroke.Thickness = selected and 2 or 1
            entry.Label.TextColor3 = selected and C("Text") or C("TextMuted")
            entry.Card.BackgroundColor3 = selected and C("SurfaceActive") or C("SurfaceHigh")
        end
    end

    for index, name in ipairs(names) do
        local palette = Argon.Themes[name]
        if palette then
            local card = UI.button({
                Parent = grid,
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = C("SurfaceHigh"),
                Text = "",
                LayoutOrder = index,
            })
            UI.corner(UDim.new(0, 8)).Parent = card
            local stroke = UI.stroke(C("Stroke"), 1, 0)
            stroke.Parent = card
            UI.padding(8).Parent = card

            local preview = UI.transparent({
                Parent = card,
                Size = UDim2.new(1, 0, 0, 30),
            })
            UI.listLayout(3).Parent = preview

            local bars = {
                { Color = palette.Accent, Width = 0.55 },
                { Color = palette.Text, Width = 0.75 },
                { Color = palette.SurfaceHigh, Width = 0.95 },
            }
            for barIndex, bar in ipairs(bars) do
                local fill = UI.frame({
                    Parent = preview,
                    Size = UDim2.new(bar.Width, 0, 0, 5),
                    BackgroundColor3 = bar.Color,
                })
                UI.corner(UDim.new(1, 0)).Parent = fill
                fill.Name = "Bar" .. tostring(barIndex)
            end

            local label = UI.label({
                Parent = card,
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, 0, 1, 0),
                Size = UDim2.new(1, 0, 0, 14),
                Text = name,
                TextSize = Argon.Theme.TextSizeTiny,
                TextColor3 = C("TextMuted"),
                TextXAlignment = Enum.TextXAlignment.Center,
            })

            element.Cards[name] = { Card = card, Stroke = stroke, Label = label }

            Connect(card.MouseEnter, function()
                if Argon.ThemeName ~= name then
                    animate(card, { BackgroundColor3 = C("SurfaceHover") }, 0.1)
                end
            end)
            Connect(card.MouseLeave, function()
                if Argon.ThemeName ~= name then
                    animate(card, { BackgroundColor3 = C("SurfaceHigh") }, 0.1)
                end
            end)
            Connect(card.MouseButton1Click, function()
                Argon:SetTheme(name)
                refreshSelection()
                if config.Callback then
                    pcall(config.Callback, name)
                end
            end)
        end
    end

    refreshSelection()
    registerThemed(refreshSelection)

    return element
end

-- ============================================================================
-- 33. COMPONENTS — CARD (feature / asset entry)
-- ============================================================================

function Section:Card(config, callback)
    config = config or {}

    local element = Element.new(self, config)
    element.CardCallback = isCallable(callback) and callback or nil

    element.IsCard = true
    element.Tier = config.Tier or "free"
    element.Pinned = config.Pinned and true or false
    element.Selected = config.Selected and true or false
    element.BadgeText = config.Badge
    element.BadgeColor = config.BadgeColor

    local height = tonumber(config.Height) or 72
    element.Row.Size = UDim2.new(1, 0, 0, height)
    element.Row.AutomaticSize = Enum.AutomaticSize.None
    element.Row.BackgroundColor3 = C("Surface")
    element.Row.BackgroundTransparency = 0.4
    element.Row.ClipsDescendants = true
    UI.corner(UDim.new(0, 10)).Parent = element.Row

    element.Stroke = UI.stroke(C("Stroke"), 1, 0.3)
    element.Stroke.Parent = element.Row

    local thumbSize = height - 16
    local thumbnail = UI.frame({
        Name = "Thumbnail",
        Parent = element.Row,
        Position = UDim2.new(0, 8, 0.5, -thumbSize / 2),
        Size = UDim2.new(0, thumbSize, 0, thumbSize),
        BackgroundColor3 = C("SurfaceHigh"),
        ClipsDescendants = true,
    })
    UI.corner(UDim.new(0, 8)).Parent = thumbnail
    element.Thumbnail = thumbnail

    if config.Image then
        element.Image = UI.image({
            Parent = thumbnail,
            Size = UDim2.new(1, 0, 1, 0),
            Image = tostring(config.Image),
        })
    else
        local gradientFill = UI.frame({
            Parent = thumbnail,
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = config.Tint or C("Accent"),
            BackgroundTransparency = 0.65,
        })
        UI.corner(UDim.new(0, 8)).Parent = gradientFill
        UI.gradient(config.Tint or C("Accent"), C("SurfaceHigh"), 45, 0.45, 0.9).Parent = gradientFill
        UI.glyph(config.Glyph or "★", math.floor(thumbSize * 0.45), config.Tint or C("Accent"), {
            Parent = thumbnail,
            Size = UDim2.new(1, 0, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
        })
    end

    if config.ThumbnailBadge then
        local badge = UI.frame({
            Parent = thumbnail,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -4, 0, 4),
            Size = UDim2.new(0, 0, 0, 14),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = C("Background"),
            BackgroundTransparency = 0.15,
        })
        UI.corner(UDim.new(0, 4)).Parent = badge
        UI.padding(0, 4, 0, 4).Parent = badge
        UI.label({
            Parent = badge,
            Size = UDim2.new(1, 0, 1, 0),
            Text = tostring(config.ThumbnailBadge),
            TextSize = 8,
            Font = Argon.Theme.FontBold,
            TextColor3 = C("Text"),
            TextXAlignment = Enum.TextXAlignment.Center,
        })
    end

    element.NameLabel = UI.label({
        Parent = element.Row,
        Position = UDim2.new(0, thumbSize + 20, 0, height / 2 - 16),
        Size = UDim2.new(1, -(thumbSize + 130), 0, 16),
        Text = tostring(config.Name or "Card"),
        TextSize = Argon.Theme.TextSize,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("Text"),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    element.DescriptionLabel = UI.label({
        Parent = element.Row,
        Position = UDim2.new(0, thumbSize + 20, 0, height / 2 + 1),
        Size = UDim2.new(1, -(thumbSize + 130), 0, 14),
        Text = tostring(config.Description or ""),
        TextSize = Argon.Theme.TextSizeTiny,
        TextColor3 = C("TextDim"),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local badgeHolder = UI.transparent({
        Parent = element.Row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, 0, 0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
    })

    element.Badge, element.BadgeLabel = UI.badge(
        element.BadgeText or "",
        element.BadgeColor or C("Accent"),
        nil,
        { Parent = badgeHolder, LayoutOrder = 1, TextSize = 9, PaddingX = 7, Height = 18 }
    )
    element.BadgeHolder = badgeHolder
    if not element.BadgeText then
        element.Badge.Visible = false
    end

    local hitbox = UI.button({
        Name = "Click",
        Parent = element.Row,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
    })
    element.Hitbox = hitbox

    local function renderSelection(animated)
        local targetStroke = element.Selected and C("Accent") or C("Stroke")
        local targetThickness = element.Selected and 2 or 1
        local targetBackground = element.Selected and C("SurfaceActive") or C("Surface")

        if animated then
            animate(element.Stroke, { Color = targetStroke, Thickness = targetThickness }, 0.14)
            animate(element.Row, { BackgroundColor3 = targetBackground }, 0.14)
        else
            element.Stroke.Color = targetStroke
            element.Stroke.Thickness = targetThickness
            element.Row.BackgroundColor3 = targetBackground
        end
    end

    function element:Select(selected, silent)
        element.Selected = selected and true or false
        renderSelection(true)
        if not silent then
            element:Fire(element.Selected, element)
        end
        return self
    end

    function element:IsSelected()
        return element.Selected
    end

    function element:SetBadge(text, color)
        element.BadgeText = text
        element.BadgeColor = color or element.BadgeColor
        element.Badge.Visible = text ~= nil and text ~= ""
        element.BadgeLabel.Text = tostring(text or "")
        element.Badge.BackgroundColor3 = element.BadgeColor or C("Accent")
        element.BadgeLabel.TextColor3 = element.BadgeColor or C("Accent")
        local stroke = element.Badge:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = element.BadgeColor or C("Accent")
        end
        return self
    end

    function element:SetImage(image)
        if element.Image then
            element.Image.Image = tostring(image)
        elseif image then
            element.Image = UI.image({
                Parent = thumbnail,
                Size = UDim2.new(1, 0, 1, 0),
                Image = tostring(image),
            })
        end
        return self
    end

    function element:SearchText(query)
        local haystack = (tostring(config.Name or "") .. " " .. tostring(config.Description or "")):lower()
        return haystack:find(query, 1, true) ~= nil
    end

    function element:Refresh()
        renderSelection(false)
        return self
    end

    Connect(hitbox.MouseEnter, function()
        if not element.Selected then
            animate(element.Row, { BackgroundColor3 = C("SurfaceHover"), BackgroundTransparency = 0.15 }, 0.12)
            animate(element.Stroke, { Color = C("StrokeLight"), Transparency = 0.2 }, 0.12)
        end
    end)

    Connect(hitbox.MouseLeave, function()
        if not element.Selected then
            animate(element.Row, { BackgroundColor3 = C("Surface"), BackgroundTransparency = 0.4 }, 0.12)
            animate(element.Stroke, { Color = C("Stroke"), Transparency = 0.3 }, 0.12)
        end
    end)

    Connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            element.Pressed = true
            if not element.Selected then
                animate(element.Row, { BackgroundColor3 = C("SurfaceActive") }, 0.08)
            end
        end
    end)

    Connect(hitbox.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            element.Pressed = false
            if not element.Selected then
                animate(element.Row, {
                    BackgroundColor3 = element.Hovering and C("SurfaceHover") or C("Surface"),
                    BackgroundTransparency = element.Hovering and 0.15 or 0.4,
                }, 0.1)
            end
        end
    end)

    Connect(hitbox.MouseEnter, function()
        element.Hovering = true
    end)
    Connect(hitbox.MouseLeave, function()
        element.Hovering = false
    end)

    Connect(hitbox.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element:Select(true, true)
        element:Fire(true, element)
        if element.CardCallback then
            pcall(element.CardCallback, element, config)
        end
    end)

    element:applyTheme(function(theme)
        element.Row.BackgroundColor3 = element.Selected and theme.SurfaceActive or theme.Surface
        element.Stroke.Color = element.Selected and theme.Accent or theme.Stroke
        element.NameLabel.TextColor3 = theme.Text
        element.DescriptionLabel.TextColor3 = theme.TextDim
    end)

    renderSelection(false)
    return element
end

-- ============================================================================
-- 33b. COMPONENTS -- WIZARD, STAT CARDS, FILE PICKERS, CALLOUTS, CARD LISTS
--
-- These exist because the reference shell is not just toggles and sliders: the
-- "Autobuild Classic" screen is a 4-step wizard with a file picker, a stat card
-- with its own menu button, a checkbox callout and a Back / Continue footer.
-- ============================================================================

-- Segmented progress: `n` bars, filled up to `Current`. The active bar is the
-- accent, completed bars are the accent at lower alpha, pending bars are the
-- surface stroke. Caption sits under the bars in tiny type.
function Section:Steps(config, callback)
    config = config or {}

    local element = Element.new(self, config)
    local total = math.max(1, math.floor(tonumber(config.Total) or 4))
    local current = Math.clamp(math.floor(tonumber(config.Current) or 1), 0, total)
    local height = tonumber(config.Height) or 46

    element.Total = total
    element.Current = current
    element.Caption = tostring(config.Caption or "")

    element.Row.Size = UDim2.new(1, 0, 0, height)
    element.Row.AutomaticSize = Enum.AutomaticSize.None

    local barHolder = UI.transparent({
        Parent = element.Row,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 4),
    })
    element.BarLayout = UI.listLayout(6, true, Enum.HorizontalAlignment.Left)
    element.BarLayout.Parent = barHolder
    element.Segments = {}

    for index = 1, total do
        local segment = UI.frame({
            Parent = barHolder,
            Size = UDim2.new(1 / total, -6, 0, 4),
            BackgroundColor3 = C("Stroke"),
            BackgroundTransparency = 0.2,
        })
        UI.corner(UDim.new(0, 3)).Parent = segment
        table.insert(element.Segments, segment)
    end

    element.CaptionLabel = UI.label({
        Parent = element.Row,
        Position = UDim2.new(0, 0, 0, 14),
        Size = UDim2.new(1, 0, 0, 14),
        Text = element.Caption,
        TextSize = Argon.Theme.TextSizeTiny,
        TextColor3 = C("TextDim"),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    function element:Render()
        for index, segment in ipairs(element.Segments) do
            if index < element.Current then
                segment.BackgroundColor3 = C("Accent")
                segment.BackgroundTransparency = 0.45
            elseif index == element.Current then
                segment.BackgroundColor3 = C("Accent")
                segment.BackgroundTransparency = 0
            else
                segment.BackgroundColor3 = C("Stroke")
                segment.BackgroundTransparency = 0.2
            end
        end
        element.CaptionLabel.Text = element.Caption
    end

    function element:SetCurrent(current, caption)
        element.Current = Math.clamp(math.floor(tonumber(current) or 1), 0, element.Total)
        if caption ~= nil then
            element.Caption = tostring(caption)
        end
        element:Render()
        if isCallable(config.OnChange) then
            pcall(config.OnChange, element.Current, element.Total, element)
        end
        if isCallable(callback) then
            pcall(callback, element.Current, element.Total, element)
        end
        element:Fire(element.Current)
        return self
    end

    function element:Next(caption)
        return element:SetCurrent(element.Current + 1, caption)
    end

    function element:Prev(caption)
        return element:SetCurrent(element.Current - 1, caption)
    end

    function element:SetCaption(text)
        element.Caption = tostring(text or "")
        element:Render()
        return self
    end

    function element:Finish()
        return element:SetCurrent(element.Total + 1)
    end

    element:applyTheme(function()
        element:Render()
    end)
    element:Render()
    return element
end

-- A bordered summary card with a title row, a "..." menu button, divider rows of
-- label / value text and an optional meter. Used by the reference for
-- "Buildability" ("You own 0 of 1 required blocks", "1 blocks - 0 types").
function Section:StatCard(config)
    config = config or {}

    local element = Element.new(self, config)
    local rows = config.Rows or {}
    element.Value = config.Value
    element.Fields = {}

    local height = tonumber(config.Height) or (64 + #rows * 26)
    element.Row.Size = UDim2.new(1, 0, 0, height)
    element.Row.AutomaticSize = Enum.AutomaticSize.None
    element.Row.BackgroundColor3 = C("Surface")
    element.Row.BackgroundTransparency = 0.35
    UI.corner(UDim.new(0, 10)).Parent = element.Row
    element.Stroke = UI.stroke(C("Stroke"), 1, 0.25)
    element.Stroke.Parent = element.Row

    element.NameLabel = UI.label({
        Parent = element.Row,
        Position = UDim2.new(0, 12, 0, 12),
        Size = UDim2.new(1, -70, 0, 16),
        Text = tostring(config.Name or "Stat"),
        TextSize = Argon.Theme.TextSize,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("Text"),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    if config.Menu ~= false then
        element.MenuButton = UI.button({
            Parent = element.Row,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -8, 0, 8),
            Size = UDim2.new(0, 30, 0, 22),
            BackgroundColor3 = C("SurfaceHigh"),
            BackgroundTransparency = 0.25,
            Text = "⋯",
            TextSize = 12,
            TextColor3 = C("TextMuted"),
        })
        UI.corner(UDim.new(0, 6)).Parent = element.MenuButton
        Connect(element.MenuButton.MouseEnter, function()
            animate(element.MenuButton, { BackgroundColor3 = C("SurfaceActive"), BackgroundTransparency = 0 }, 0.1)
        end)
        Connect(element.MenuButton.MouseLeave, function()
            animate(element.MenuButton, { BackgroundColor3 = C("SurfaceHigh"), BackgroundTransparency = 0.25 }, 0.1)
        end)
        Connect(element.MenuButton.MouseButton1Click, function()
            if isCallable(config.OnMenu) then
                pcall(config.OnMenu, element)
            end
            element:Fire("menu", element)
        end)
    end

    local function addRow(index, row)
        local label = tostring(row.Label or row.Text or row[1] or "")
        local value = row.Value or row[2]
        local y = 38 + (index - 1) * 26
        local entry = {}

        entry.Label = UI.label({
            Parent = element.Row,
            Position = UDim2.new(0, 12, 0, y),
            Size = UDim2.new(1, -(value == nil and 24 or 80), 0, 14),
            Text = label,
            TextSize = Argon.Theme.TextSizeTiny,
            TextColor3 = C("TextDim"),
            TextTruncate = Enum.TextTruncate.AtEnd,
        })

        if value ~= nil then
            entry.Value = UI.label({
                Parent = element.Row,
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, y),
                Size = UDim2.new(0, 60, 0, 14),
                Text = tostring(value),
                TextSize = Argon.Theme.TextSizeTiny,
                Font = Argon.Theme.FontMedium,
                TextColor3 = C("Text"),
                TextXAlignment = Enum.TextXAlignment.Right,
            })
        end

        if row.Meter then
            entry.MeterTrack = UI.frame({
                Parent = element.Row,
                Position = UDim2.new(0, 12, 0, y + 16),
                Size = UDim2.new(1, -24, 0, 3),
                BackgroundColor3 = C("Stroke"),
                BackgroundTransparency = 0.4,
            })
            UI.corner(UDim.new(0, 2)).Parent = entry.MeterTrack
            entry.MeterFill = UI.frame({
                Parent = entry.MeterTrack,
                Size = UDim2.new(Math.clamp((tonumber(row.Percent) or 0) / 100, 0, 1), 0, 1, 0),
                BackgroundColor3 = C("Accent"),
            })
            UI.corner(UDim.new(0, 2)).Parent = entry.MeterFill
            entry.Percent = tonumber(row.Percent) or 0
        end

        table.insert(element.Fields, entry)
    end

    for index, row in ipairs(rows) do
        addRow(index, type(row) == "table" and row or { Text = tostring(row) })
    end

    function element:SetRow(index, value)
        local entry = element.Fields[index]
        if not entry then
            return self
        end
        if entry.Value then
            entry.Value.Text = tostring(value)
        elseif entry.Label then
            entry.Label.Text = tostring(value)
        end
        return self
    end

    function element:SetMeter(index, percent)
        local entry = element.Fields[index]
        if not entry or not entry.MeterFill then
            return self
        end
        entry.Percent = Math.clamp(tonumber(percent) or 0, 0, 100)
        animate(entry.MeterFill, { Size = UDim2.new(entry.Percent / 100, 0, 1, 0) }, 0.2)
        return self
    end

    Connect(element.Row.MouseEnter, function()
        animate(element.Stroke, { Color = C("StrokeLight"), Transparency = 0.05 }, 0.12)
    end)
    Connect(element.Row.MouseLeave, function()
        animate(element.Stroke, { Color = C("Stroke"), Transparency = 0.25 }, 0.12)
    end)

    element:applyTheme(function(theme)
        element.Row.BackgroundColor3 = theme.Surface
        element.Stroke.Color = theme.Stroke
        element.NameLabel.TextColor3 = theme.Text
        for _, entry in ipairs(element.Fields) do
            if entry.Label then
                entry.Label.TextColor3 = theme.TextDim
            end
            if entry.Value then
                entry.Value.TextColor3 = theme.Text
            end
            if entry.MeterTrack then
                entry.MeterTrack.BackgroundColor3 = theme.Stroke
                entry.MeterFill.BackgroundColor3 = theme.Accent
            end
        end
    end)
    return element
end

-- Label above a field with a placeholder, a trailing button and a hover stroke.
function Section:FileRow(config, callback)
    config = config or {}

    local element = Element.new(self, config)
    element.Value = config.Default
    local height = tonumber(config.Height) or 62

    element.Row.Size = UDim2.new(1, 0, 0, height)
    element.Row.AutomaticSize = Enum.AutomaticSize.None

    element.CaptionLabel = UI.label({
        Parent = element.Row,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 12),
        Text = string.upper(tostring(config.Name or "File")),
        TextSize = Argon.Theme.TextSizeTiny,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("TextDim"),
    })

    local field = UI.frame({
        Parent = element.Row,
        Position = UDim2.new(0, 0, 0, 18),
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = C("Input"),
        BackgroundTransparency = 0,
    })
    UI.corner(UDim.new(0, 8)).Parent = field
    element.Field = field
    element.FieldStroke = UI.stroke(C("Stroke"), 1, 0.2)
    element.FieldStroke.Parent = field

    element.ValueLabel = UI.label({
        Parent = field,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -110, 1, 0),
        Text = tostring(config.Value or config.Placeholder or "Choose a file"),
        TextSize = Argon.Theme.TextSizeSmall,
        TextColor3 = config.Value and C("Text") or C("TextDim"),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    element.Button = UI.button({
        Parent = field,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.new(0, 74, 0, 26),
        BackgroundColor3 = C("SurfaceHigh"),
        Text = tostring(config.Button or "Browse"),
        TextSize = Argon.Theme.TextSizeSmall,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("Text"),
    })
    UI.corner(UDim.new(0, 6)).Parent = element.Button

    function element:SetValue(value, silent)
        element.Value = value
        if element.ValueLabel then
            element.ValueLabel.Text = tostring(value or config.Placeholder or "Choose a file")
            element.ValueLabel.TextColor3 = value and C("Text") or C("TextDim")
        end
        if not silent then
            element:Fire(value)
        end
        return self
    end

    Connect(element.Button.MouseEnter, function()
        animate(element.Button, { BackgroundColor3 = C("SurfaceActive") }, 0.1)
    end)
    Connect(element.Button.MouseLeave, function()
        animate(element.Button, { BackgroundColor3 = C("SurfaceHigh") }, 0.1)
    end)
    Connect(element.Button.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        if isCallable(config.OnBrowse) then
            pcall(config.OnBrowse, element)
        end
        if isCallable(callback) then
            pcall(callback, element)
        end
    end)
    Connect(field.MouseEnter, function()
        animate(element.FieldStroke, { Color = C("StrokeLight"), Transparency = 0 }, 0.12)
    end)
    Connect(field.MouseLeave, function()
        animate(element.FieldStroke, { Color = C("Stroke"), Transparency = 0.2 }, 0.12)
    end)

    element:applyTheme(function(theme)
        field.BackgroundColor3 = theme.Input
        element.ValueLabel.TextColor3 = element.Value and theme.Text or theme.TextDim
        element.CaptionLabel.TextColor3 = theme.TextDim
        element.Button.BackgroundColor3 = theme.SurfaceHigh
        element.Button.TextColor3 = theme.Text
    end)
    return element
end

-- Boxed note with a leading glyph and an optional checkbox. `Kind` picks the
-- accent colour: "check" (toggle, bound to a flag), "info", "warn", "danger".
function Section:Callout(config, callback)
    config = config or {}

    local element = Element.new(self, config)
    local kind = tostring(config.Kind or "check")
    local isToggle = kind == "check" and (config.Flag ~= nil or isCallable(callback) or isCallable(config.Callback) or config.Default ~= nil)
    element.Value = config.Default and true or false
    if config.Default == nil and isToggle then
        element.Value = true
    end

    local height = tonumber(config.Height) or 74
    element.Row.Size = UDim2.new(1, 0, 0, height)
    element.Row.AutomaticSize = Enum.AutomaticSize.None

    local box = UI.frame({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = C("Surface"),
        BackgroundTransparency = 0.4,
        Active = true,
    })
    UI.corner(UDim.new(0, 10)).Parent = box
    element.Box = box
    element.BoxStroke = UI.stroke(C("Stroke"), 1, 0.3)
    element.BoxStroke.Parent = box

    local function kindColor()
        if kind == "danger" then
            return C("Danger")
        elseif kind == "warn" then
            return C("Warning")
        elseif kind == "info" then
            return C("Info")
        end
        return C("Accent")
    end

    if isToggle then
        element.Checkbox = UI.frame({
            Parent = box,
            Position = UDim2.new(0, 12, 0, 12),
            Size = UDim2.new(0, 18, 0, 18),
            BackgroundColor3 = kindColor(),
        })
        UI.corner(UDim.new(0, 5)).Parent = element.Checkbox
        element.CheckGlyph = UI.glyph("✓", 11, C("AccentText"), {
            Parent = element.Checkbox,
            Size = UDim2.new(1, 0, 1, 0),
        })
    else
        element.Icon = UI.glyph(kind == "danger" and "⚠" or "i", 12, kindColor(), {
            Parent = box,
            Position = UDim2.new(0, 12, 0, 12),
            Size = UDim2.new(0, 18, 0, 18),
        })
    end

    element.NameLabel = UI.label({
        Parent = box,
        Position = UDim2.new(0, 40, 0, 12),
        Size = UDim2.new(1, -52, 0, 16),
        Text = tostring(config.Name or config.Title or "Callout"),
        TextSize = Argon.Theme.TextSize,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("Text"),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    element.DescriptionLabel = UI.label({
        Parent = box,
        Position = UDim2.new(0, 40, 0, 30),
        Size = UDim2.new(1, -52, 0, height - 40),
        Text = tostring(config.Text or config.Description or ""),
        TextSize = Argon.Theme.TextSizeTiny,
        TextColor3 = C("TextDim"),
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
    })

    function element:Render()
        if element.Checkbox then
            local tint = kindColor()
            element.Checkbox.BackgroundColor3 = element.Value and tint or C("SurfaceActive")
            element.CheckGlyph.TextColor3 = element.Value and C("AccentText") or C("TextDim")
            element.CheckGlyph.Text = element.Value and "✓" or ""
        end
    end

    function element:SetValue(value, silent)
        element.Value = value and true or false
        if element.Flag then
            Argon.Flags[element.Flag] = element.Value
        end
        element:Render()
        if not silent then
            element:Fire(element.Value)
            if isCallable(callback) then
                pcall(callback, element.Value, element)
            end
        end
        return self
    end

    Connect(box.MouseButton1Click, function()
        if isToggle and not element.Disabled then
            element:SetValue(not element.Value)
        end
    end)
    Connect(box.MouseEnter, function()
        animate(element.BoxStroke, { Color = C("StrokeLight"), Transparency = 0.1 }, 0.12)
    end)
    Connect(box.MouseLeave, function()
        animate(element.BoxStroke, { Color = C("Stroke"), Transparency = 0.3 }, 0.12)
    end)

    element:applyTheme(function(theme)
        box.BackgroundColor3 = theme.Surface
        element.NameLabel.TextColor3 = theme.Text
        element.DescriptionLabel.TextColor3 = theme.TextDim
        element:Render()
    end)
    element:Render()
    return element
end

-- A vertical list of selectable cards. Items may omit `Image`, in which case a
-- placeholder tile is drawn so every row keeps the same height.
function Section:CardList(config, callback)
    config = config or {}

    local element = Element.new(self, config)
    element.Items = config.Items or {}
    element.Selected = nil
    element.Cards = {}

    element.Row.Size = UDim2.new(1, 0, 0, 0)
    element.Row.AutomaticSize = Enum.AutomaticSize.Y
    local layout = UI.listLayout(tonumber(config.Gap) or 8)
    layout.Parent = element.Row
    element.ListLayout = layout

    local function pick(card, item, index)
        if config.Select ~= false then
            for _, other in ipairs(element.Cards) do
                if other ~= card and other.Selected then
                    other:Select(false, true)
                end
            end
            element.Selected = card
            card:Select(true, true)
        end
        element:Fire(item, index)
        if isCallable(config.OnSelect) then
            pcall(config.OnSelect, item, index, element)
        end
        if isCallable(callback) then
            pcall(callback, item, index, element)
        end
        if isCallable(config.OnOpen) then
            pcall(config.OnOpen, item, index, element)
        end
    end

    local function makeCard(item, index)
        local card = element.Section:Card({
            Name = item.Name or item.Title or ("Item " .. tostring(index)),
            Description = item.Text or item.Description or item.Detail or "",
            Image = item.Image,
            Glyph = item.Glyph or config.PlaceholderGlyph or "▦",
            Tint = item.Tint,
            Badge = item.Badge,
            BadgeColor = item.BadgeColor,
            Tier = item.Tier,
            Height = tonumber(item.Height) or tonumber(config.RowHeight) or 72,
        })

        card.CardItem = item
        card.PickCallback = pick

        -- The click is wired here rather than through Card's own callback so the
        -- closure can see `card`: a local's scope begins after its initializer,
        -- so `local card = Section:Card(cfg, function() card end)` would read a
        -- *global* card and silently no-op inside pcall.
        Connect(card.Hitbox.MouseButton1Click, function()
            pick(card, item, index)
        end)

        return card
    end

    function element:SetItems(items)
        for _, card in ipairs(element.Cards) do
            card:Destroy()
        end
        element.Cards = {}
        element.Items = items or {}
        for index, item in ipairs(element.Items) do
            table.insert(element.Cards, makeCard(item, index))
        end
        element.Selected = nil
        return self
    end

    function element:GetSelected()
        if element.Selected then
            return element.Selected.CardItem
        end
        return nil
    end

    function element:SelectIndex(index)
        local card = element.Cards[math.floor(tonumber(index) or 0)]
        if card then
            for _, other in ipairs(element.Cards) do
                if other ~= card and other.Selected then
                    other:Select(false, true)
                end
            end
            element.Selected = card
            card:Select(true, true)
            element:Fire(card.CardItem, index)
            if isCallable(config.OnSelect) then
                pcall(config.OnSelect, card.CardItem, index, element)
            end
        end
        return self
    end

    function element:Filter(query)
        local needle = string.lower(tostring(query or ""))
        for _, card in ipairs(element.Cards) do
            local show = needle == "" or (card.SearchText and card:SearchText(needle))
            card:SetVisible(show ~= false)
        end
        return self
    end

    element:SetItems(element.Items)
    return element
end

-- ============================================================================
-- 34. COMPONENTS — TABLE
-- ============================================================================

function Section:Table(config)
    config = config or {}

    local element = Element.new(self, config)
    element.Row.Size = UDim2.new(1, 0, 0, 0)
    element.Row.AutomaticSize = Enum.AutomaticSize.Y
    element.Row.BackgroundColor3 = C("Surface")
    element.Row.BackgroundTransparency = 0.35
    UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = element.Row
    element.Stroke = UI.stroke(C("Stroke"), 1, 0.55)
    element.Stroke.Parent = element.Row
    UI.padding(8).Parent = element.Row
    UI.listLayout(2).Parent = element.Row

    local columns = config.Columns or { "Name", "Value" }
    local columnWidths = config.ColumnWidths or {}
    local rows = config.Rows or {}

    local header = UI.transparent({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 0, 22),
    })

    local function columnPosition(index)
        local offset = 0
        for i = 1, index - 1 do
            offset = offset + (columnWidths[i] or (1 / #columns))
        end
        return offset
    end

    for index, column in ipairs(columns) do
        UI.label({
            Parent = header,
            Position = UDim2.new(columnPosition(index), 0, 0, 0),
            Size = UDim2.new(columnWidths[index] or (1 / #columns), 0, 1, 0),
            Text = tostring(column):upper(),
            TextSize = 9,
            Font = Argon.Theme.FontBold,
            TextColor3 = C("TextDim"),
            TextXAlignment = index == #columns and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
        })
    end

    element.Body = UI.transparent({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    UI.listLayout(0).Parent = element.Body

    function element:SetRows(newRows)
        for _, child in ipairs(self.Body:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end
        for rowIndex, row in ipairs(newRows or {}) do
            local rowFrame = UI.transparent({
                Parent = self.Body,
                Size = UDim2.new(1, 0, 0, 24),
                LayoutOrder = rowIndex,
            })
            for columnIndex, value in ipairs(row) do
                UI.label({
                    Parent = rowFrame,
                    Position = UDim2.new(columnPosition(columnIndex), 0, 0, 0),
                    Size = UDim2.new(columnWidths[columnIndex] or (1 / #columns), 0, 1, 0),
                    Text = tostring(value),
                    TextSize = Argon.Theme.TextSizeTiny,
                    TextColor3 = columnIndex == 1 and C("Text") or C("TextMuted"),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextXAlignment = columnIndex == #columns and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
                })
            end
            if rowIndex < #newRows then
                local line = UI.frame({
                    Parent = rowFrame,
                    AnchorPoint = Vector2.new(0, 1),
                    Position = UDim2.new(0, 0, 1, 0),
                    Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = C("Stroke"),
                    BackgroundTransparency = 0.6,
                })
                line.Name = "Rule"
            end
        end
        return self
    end

    element:SetRows(rows)
    return element
end

-- ============================================================================
-- 35. TOOLBAR
-- ============================================================================
-- The floating pill row from the reference: circular icon buttons plus labelled
-- pill buttons, anchored to a screen corner, optionally draggable.

local Toolbar = {}
Toolbar.__index = Toolbar

function Toolbar.new(config)
    config = config or {}
    local self = setmetatable({}, Toolbar)

    self.Buttons = {}
    self.Destroyed = false
    self.Corner = config.Corner or "BottomLeft"
    self.Draggable = config.Draggable ~= false

    self.Gui = createScreenGui("ArgonToolbar" .. tostring(#Argon.Windows + 1), (config.DisplayOrder or 90))

    self.Holder = UI.transparent({
        Parent = self.Gui,
        Size = UDim2.new(0, 0, 0, 40),
        AutomaticSize = Enum.AutomaticSize.X,
    })

    self.Layout = UI.listLayout(8, true, Enum.HorizontalAlignment.Left)
    self.Layout.Parent = self.Holder

    self:ApplyAnchor()
    self:Build(config)

    if self.Draggable then
        makeDraggable(self.Holder, self.Holder, { bounds = true })
    end

    Argon.Toolbars = Argon.Toolbars or {}
    table.insert(Argon.Toolbars, self)
    table.insert(Argon.Instances, self.Gui)
    return self
end

function Toolbar:ApplyAnchor()
    local corner = self.Corner
    local position = UDim2.new(0, 16, 0, 16)
    local anchor = Vector2.new(0, 0)

    if corner == "TopRight" then
        position = UDim2.new(1, -16, 0, 16)
        anchor = Vector2.new(1, 0)
    elseif corner == "BottomLeft" then
        position = UDim2.new(0, 16, 1, -16)
        anchor = Vector2.new(0, 1)
    elseif corner == "BottomRight" then
        position = UDim2.new(1, -16, 1, -16)
        anchor = Vector2.new(1, 1)
    end

    self.Holder.AnchorPoint = anchor
    self.Holder.Position = position
end

function Toolbar:Build(config)
    local theme = Argon.Theme

    local function makeCircle(icon, tooltip, callback, active)
        local button = UI.button({
            Parent = self.Holder,
            Size = UDim2.new(0, 38, 0, 38),
            BackgroundColor3 = active and theme.Accent or theme.Surface,
            BackgroundTransparency = active and 0 or 0.05,
            Text = tostring(icon),
            TextSize = 15,
            TextColor3 = active and theme.AccentText or theme.Text,
            Font = theme.FontBold,
        })
        UI.corner(UDim.new(1, 0)).Parent = button
        UI.stroke(active and theme.Accent or theme.Stroke, 1, 0.2).Parent = button

        Connect(button.MouseEnter, function()
            animate(button, { BackgroundColor3 = active and theme.Accent or theme.SurfaceHover }, 0.1)
        end)
        Connect(button.MouseLeave, function()
            animate(button, { BackgroundColor3 = active and theme.Accent or theme.Surface }, 0.1)
        end)
        Connect(button.MouseButton1Click, function()
            if callback then
                pcall(callback)
            end
        end)
        if tooltip then
            attachTooltip(button, tooltip)
        end
        table.insert(self.Buttons, button)
        return button
    end

    local function makePill(text, icon, callback)
        local button = UI.button({
            Parent = self.Holder,
            Size = UDim2.new(0, 0, 0, 38),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = theme.Surface,
            BackgroundTransparency = 0.05,
            Text = "",
        })
        UI.corner(UDim.new(1, 0)).Parent = button
        UI.stroke(theme.Stroke, 1, 0.2).Parent = button
        UI.padding(0, 16, 0, 14).Parent = button

        local labelText = tostring(text or "")
        local offset = 0
        if icon then
            UI.glyph(tostring(icon), 13, theme.TextMuted, {
                Parent = button,
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(0, 16, 1, 0),
            })
            offset = 20
        end

        UI.label({
            Parent = button,
            Position = UDim2.new(0, offset, 0, 0),
            Size = UDim2.new(1, -offset, 1, 0),
            Text = labelText,
            TextSize = theme.TextSizeSmall,
            Font = theme.FontMedium,
            TextColor3 = theme.Text,
        })

        Connect(button.MouseEnter, function()
            animate(button, { BackgroundColor3 = theme.SurfaceHover }, 0.1)
        end)
        Connect(button.MouseLeave, function()
            animate(button, { BackgroundColor3 = theme.Surface }, 0.1)
        end)
        Connect(button.MouseButton1Click, function()
            if callback then
                pcall(callback)
            end
        end)
        table.insert(self.Buttons, button)
        return button
    end

    for _, item in ipairs(config.Buttons or {}) do
        if item.Style == "pill" then
            makePill(item.Text, item.Icon, item.Callback)
        else
            makeCircle(item.Icon or "•", item.Tooltip or item.Text, item.Callback, item.Active)
        end
    end

    registerThemed(function(palette)
        for _, button in ipairs(self.Buttons) do
            button.BackgroundColor3 = palette.Surface
        end
    end)

    return self
end

function Toolbar:SetVisible(visible)
    self.Gui.Enabled = visible ~= false
    return self
end

function Toolbar:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for index, existing in ipairs(Argon.Toolbars or {}) do
        if existing == self then
            table.remove(Argon.Toolbars, index)
            break
        end
    end
    DestroyInstance(self.Gui)
end

function Argon:Toolbar(config)
    return Toolbar.new(config)
end

-- ============================================================================
-- 36. WATERMARK
-- ============================================================================

function Argon:Watermark(text)
    local gui = createScreenGui("ArgonWatermark" .. tostring(#self.Windows + 1), 80)
    local holder = UI.frame({
        Parent = gui,
        Position = UDim2.new(0, 12, 0, 12),
        Size = UDim2.new(0, 0, 0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = C("Surface"),
        BackgroundTransparency = 0.15,
    })
    UI.corner(UDim.new(0, 6)).Parent = holder
    UI.padding(0, 8, 0, 8).Parent = holder

    local label = UI.label({
        Parent = holder,
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = tostring(text or ("Argon " .. self.Version)),
        TextSize = Argon.Theme.TextSizeTiny,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C("Text"),
    })

    local watermark = { Gui = gui, Label = label }

    function watermark:SetText(value)
        label.Text = tostring(value)
        return self
    end

    function watermark:Destroy()
        DestroyInstance(gui)
    end

    registerThemed(function(palette)
        holder.BackgroundColor3 = palette.Surface
        label.TextColor3 = palette.Text
    end)

    table.insert(self.Instances, gui)
    return watermark
end

-- ============================================================================
-- 37. CONFIG PAGE BUILDER
-- ============================================================================
-- Drops a complete "Settings" page into a window: config name, save/load/delete,
-- theme picker, motion toggle, notification test.

function Argon:BuildConfigPage(window, options)
    options = options or {}
    local page = window:GetPage(options.Name or "Settings")
    if page then
        return page
    end

    page = window:Page({
        Name = options.Name or "Settings",
        Icon = options.Icon or "⚙",
        Group = options.Group or "OTHER",
        Subtitle = options.Subtitle or "Preferences",
        Search = false,
    })

    local configSection = page:Section({ Name = "Configuration", Icon = "▤" })
    local nameInput = configSection:Input({
        Name = "Config name",
        Placeholder = "default",
        Default = Argon.Config.DefaultConfig,
        Flag = "argon.configName",
    })

    local configList = configSection:Dropdown({
        Name = "Saved configs",
        Placeholder = "None",
        Options = {},
        Flag = "argon.configSelected",
    })

    local function refreshList()
        local names = Argon:GetConfigs()
        local optionsList = {}
        for _, name in ipairs(names) do
            optionsList[#optionsList + 1] = name
        end
        configList:SetOptions(optionsList)
    end

    configSection:DualButton({
        Name = "Save",
        AlternateName = "Load",
    }, function()
        local name = nameInput:Get()
        if Argon:SaveConfig(name) then
            Argon:Notify({ Kind = "success", Title = "Config", Text = "Saved \"" .. tostring(name) .. "\"" })
            refreshList()
        else
            Argon:Notify({ Kind = "danger", Title = "Config", Text = "Could not write the config file" })
        end
    end, function()
        local name = configList:Get() or nameInput:Get()
        if Argon:LoadConfig(name) then
            Argon:Notify({ Kind = "success", Title = "Config", Text = "Loaded \"" .. tostring(name) .. "\"" })
        else
            Argon:Notify({ Kind = "warning", Title = "Config", Text = "No config named \"" .. tostring(name) .. "\"" })
        end
    end)

    configSection:DualButton({
        Name = "Delete",
        AlternateName = "Refresh",
    }, function()
        local name = configList:Get() or nameInput:Get()
        Argon:DeleteConfig(name)
        refreshList()
        Argon:Notify({ Kind = "info", Title = "Config", Text = "Deleted \"" .. tostring(name) .. "\"" })
    end, function()
        refreshList()
        Argon:Notify({ Kind = "info", Title = "Config", Text = "List refreshed" })
    end)

    local appearance = page:Section({ Name = "Appearance", Icon = "◐" })
    appearance:ThemePicker({ Name = "Theme" })

    appearance:Toggle({
        Name = "Reduce motion",
        Description = "Disable tweening and transitions",
        Flag = "argon.reduceMotion",
        Default = false,
    }, function(enabled)
        Argon.Config.ReduceMotion = enabled
    end)

    appearance:Slider({
        Name = "Animation speed",
        Flag = "argon.animationSpeed",
        Min = 0.5, Max = 3, Default = 1, Step = 0.1, Decimals = 1, Suffix = "x",
    }, function(speed)
        Argon.Config.AnimationSpeed = speed
    end)

    local about = page:Section({ Name = "About", Icon = "i", Collapsed = true })
    about:Paragraph({
        Title = "Argon " .. Argon.Version,
        Text = "Single-file component library for executor scripts. Flags, configs, themes and\n"
            .. "notifications are built in. Press the menu key to hide the UI at any time.",
    })
    about:UserRow({
        Name = window.User.Name or "user",
        Description = window.User.Tag or "User",
    })
    about:DualButton({ Name = "Unload UI", AlternateName = "Test toast" }, function()
        Argon:Unload()
    end, function()
        Argon:Notify({ Kind = "success", Title = "Argon", Text = "Notifications are working." })
    end)

    refreshList()
    return page
end

-- ============================================================================
-- 38. IRIS COMPATIBILITY LAYER
-- ============================================================================
-- Iris is an immediate-mode library. Argon is retained-mode, so this layer keeps
-- a cursor over the last opened section and creates real widgets on each call.
-- The constructor table shapes match the common Iris snippets, so migrating a
-- script usually means replacing `local Iris = require(...)` with this object.

local Iris = {}

function Iris:Init(config)
    config = config or {}
    self.Window = Argon:Window({
        Title = config.Title or config.Name or "Iris",
        Subtitle = config.Subtitle or ("Iris layer · Argon " .. Argon.Version),
        Width = config.Width or 520,
        Height = config.Height or 420,
        Theme = config.Theme,
    })
    self.Page = self.Window:Page({ Name = config.Page or "Main", Icon = "▤" })
    self.Section = self.Page:Section({ Name = config.Section or "Iris", Icon = nil })
    return self
end

local function irisEnsure(self)
    if not self.Window then
        self:Init()
    end
    return self
end

function Iris:Tab(config)
    irisEnsure(self)
    self.Page = self.Window:Page({
        Name = type(config) == "table" and (config.Text or config.Name) or tostring(config or "Tab"),
        Icon = type(config) == "table" and config.Icon or nil,
    })
    self.Section = self.Page:Section({ Name = "Content" })
    return self.Page
end

function Iris:Section_(config)
    irisEnsure(self)
    local name = type(config) == "table" and (config.Text or config.Name) or tostring(config or "Section")
    self.Section = self.Page:Section({ Name = name })
    return self.Section
end

function Iris:Tree(config)
    return self:Section_(config)
end

function Iris:TabBar()
    return self
end

function Iris:End()
    return self
end

function Iris:Toggle(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:Toggle({
        Name = config.Text or config.Name or "Toggle",
        Description = config.Tooltip,
        Flag = config.Flag or (config.Text and ("iris." .. tostring(config.Text)) or nil),
        Default = config.Default,
    }, config.Changed)
end

function Iris:Checkbox(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:Checkbox({
        Name = config.Text or "Checkbox",
        Flag = config.Flag or (config.Text and ("iris." .. tostring(config.Text)) or nil),
        Default = config.Default,
    }, config.Changed)
end

function Iris:Slider(config)
    irisEnsure(self)
    config = config or {}
    local minimum, maximum = 0, 100
    if type(config.Min) == "number" then
        minimum = config.Min
    end
    if type(config.Max) == "number" then
        maximum = config.Max
    end
    return self.Section:Slider({
        Name = config.Text or "Slider",
        Min = minimum,
        Max = maximum,
        Default = config.Default,
        Step = config.Increment or config.Step,
        Suffix = config.Suffix,
        Flag = config.Flag or (config.Text and ("iris." .. tostring(config.Text)) or nil),
    }, config.Changed)
end

function Iris:Input(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:Input({
        Name = config.Text or "Input",
        Placeholder = config.PlaceholderText,
        Default = config.Default,
        Flag = config.Flag or (config.Text and ("iris." .. tostring(config.Text)) or nil),
    }, config.Changed)
end

function Iris:InputText(config)
    return self:Input(config)
end

function Iris:Dropdown(config)
    irisEnsure(self)
    config = config or {}
    local values = {}
    for index, value in ipairs(config.Values or config.Options or {}) do
        values[index] = value
    end
    return self.Section:Dropdown({
        Name = config.Text or "Dropdown",
        Options = values,
        Multi = config.Multi,
        Default = config.Default,
        Flag = config.Flag or (config.Text and ("iris." .. tostring(config.Text)) or nil),
    }, config.Changed)
end

function Iris:Button(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:Button({
        Name = config.Text or "Button",
        Primary = config.Primary,
        Width = config.Width and "half" or "full",
    }, config.Callback)
end

function Iris:ColorPicker(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:ColorPicker({
        Name = config.Text or "Color",
        Default = config.Default,
        Flag = config.Flag or (config.Text and ("iris." .. tostring(config.Text)) or nil),
    }, config.Changed)
end

function Iris:Keybind(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:Keybind({
        Name = config.Text or "Keybind",
        Default = config.Default,
        Flag = config.Flag or (config.Text and ("iris." .. tostring(config.Text)) or nil),
    }, config.Changed)
end

function Iris:Text(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:Label({
        Text = config.Text or config.Content or "",
        Color = config.Color,
    })
end

function Iris:Separator()
    irisEnsure(self)
    return self.Section:Divider()
end

function Iris:ProgressBar(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:Progress({
        Name = config.Text or "Progress",
        Default = config.Value or 0,
    })
end

function Iris:Table(config)
    irisEnsure(self)
    config = config or {}
    return self.Section:Table({
        Columns = config.Columns,
        Rows = config.Rows,
    })
end

function Iris:Notify(config)
    return Argon:Notify(config)
end

function Iris:Unload()
    Argon:Unload()
end

Argon.Iris = Iris

-- ============================================================================
-- 38b. COMPONENTS — BANNER AND IMAGE
-- ============================================================================

function Section:Banner(config)
    config = config or {}
    local kind = tostring(config.Kind or "info")
    local colorKey = ({ info = "Info", success = "Success", warning = "Warning", danger = "Danger" })[kind]
        or "Info"

    local element = Element.new(self, config)
    element.Row.Size = UDim2.new(1, 0, 0, 0)
    element.Row.AutomaticSize = Enum.AutomaticSize.Y
    element.Row.BackgroundColor3 = C(colorKey)
    element.Row.BackgroundTransparency = 0.88
    element.Row.ClipsDescendants = true

    local corner = UI.corner(UDim.new(0, Argon.Theme.Corner))
    corner.Parent = element.Row

    local stroke = UI.stroke(C(colorKey), 1, 0.6)
    stroke.Parent = element.Row

    UI.padding(10, 12, 10, 12).Parent = element.Row
    UI.listLayout(3).Parent = element.Row

    local titleRow = UI.transparent({
        Parent = element.Row,
        Size = UDim2.new(1, 0, 0, 16),
        LayoutOrder = 1,
    })

    UI.glyph(
        ({ info = "i", success = "✓", warning = "!", danger = "×" })[kind] or "i",
        11,
        C(colorKey),
        {
            Parent = titleRow,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(0, 14, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
        }
    )

    element.NameLabel = UI.label({
        Parent = titleRow,
        Position = UDim2.new(0, 20, 0, 0),
        Size = UDim2.new(1, -28, 1, 0),
        Text = tostring(config.Name or config.Title or "Notice"),
        TextSize = Argon.Theme.TextSizeSmall,
        Font = Argon.Theme.FontMedium,
        TextColor3 = C(colorKey),
    })

    if config.Text then
        element.DescriptionLabel = UI.label({
            Parent = element.Row,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = tostring(config.Text),
            TextSize = Argon.Theme.TextSizeTiny,
            TextColor3 = C("TextMuted"),
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = 2,
        })
    end

    if config.Dismissible then
        local close = UI.button({
            Parent = titleRow,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 16, 0, 16),
            BackgroundTransparency = 1,
            Text = "×",
            TextSize = 12,
            TextColor3 = C("TextMuted"),
        })
        Connect(close.MouseButton1Click, function()
            element:Destroy()
        end)
    end

    element:applyTheme(function(theme)
        element.Row.BackgroundColor3 = theme[colorKey]
        stroke.Color = theme[colorKey]
        if element.DescriptionLabel then
            element.DescriptionLabel.TextColor3 = theme.TextMuted
        end
    end)

    return element
end

function Section:Image(config)
    config = config or {}

    local element = Element.new(self, config)
    local height = tonumber(config.Height) or 92

    element.Row.Size = UDim2.new(element.Width == "half" and 0.5 or 1, element.Width == "half" and -3 or 0, 0, height)
    element.Row.BackgroundColor3 = C("SurfaceHigh")
    element.Row.ClipsDescendants = true
    UI.corner(UDim.new(0, Argon.Theme.Corner)).Parent = element.Row

    if config.Image then
        UI.image({
            Parent = element.Row,
            Size = UDim2.new(1, 0, 1, 0),
            Image = tostring(config.Image),
            ImageTransparency = tonumber(config.Transparency) or 0,
        })
    end

    if config.Name then
        local overlay = UI.frame({
            Parent = element.Row,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, 0),
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundColor3 = C("Background"),
            BackgroundTransparency = 0.25,
        })
        UI.gradient(C("Background"), C("Background"), 90, 0.6, 0.1).Parent = overlay
        UI.label({
            Parent = overlay,
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -20, 1, 0),
            Text = tostring(config.Name),
            TextSize = Argon.Theme.TextSizeSmall,
            Font = Argon.Theme.FontMedium,
            TextColor3 = C("Text"),
        })
    end

    element:applyTheme(function(theme)
        element.Row.BackgroundColor3 = theme.SurfaceHigh
    end)

    return element
end

-- ============================================================================
-- 38c. UTILITIES EXPOSED TO SCRIPTS
-- ============================================================================

function Argon:GetUptime()
    return os.clock()
end

function Argon:IsMobile()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Argon:GetViewportSize()
    local camera = workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(1920, 1080)
end

function Argon:ShowLoading(text, duration)
    local gui = createScreenGui("ArgonLoading" .. tostring(#self.Instances), 8000)
    local holder = UI.frame({
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 220, 0, 54),
        BackgroundColor3 = C("BackgroundAlt"),
    })
    UI.corner(UDim.new(0, 10)).Parent = holder
    UI.stroke(C("Stroke"), 1, 0).Parent = holder

    UI.label({
        Parent = holder,
        Position = UDim2.new(0, 14, 0, 10),
        Size = UDim2.new(1, -28, 0, 16),
        Text = tostring(text or "Loading…"),
        TextSize = Argon.Theme.TextSizeSmall,
        TextColor3 = C("Text"),
    })

    local track = UI.frame({
        Parent = holder,
        Position = UDim2.new(0, 14, 1, -18),
        Size = UDim2.new(1, -28, 0, 3),
        BackgroundColor3 = C("SurfaceHigh"),
    })
    UI.corner(UDim.new(1, 0)).Parent = track

    local fill = UI.frame({
        Parent = track,
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = C("Accent"),
    })
    UI.corner(UDim.new(1, 0)).Parent = fill

    animate(fill, { Size = UDim2.new(1, 0, 1, 0) }, tonumber(duration) or 1.2, EasingStyle.Quad)
    task.delay((tonumber(duration) or 1.2) + 0.1, function()
        pcall(function()
            gui:Destroy()
        end)
    end)

    return gui
end

-- ============================================================================
-- 38d. GLOBAL KEYBIND REGISTRY
-- ============================================================================
-- Scripts can bind hotkeys without opening a window. Handlers receive the key
-- state (true on press, false on release) and are removed by Unload.

local KeyBindings = {}

function Argon:BindKey(keyCode, callback, options)
    options = options or {}
    if not isEnumItem(keyCode) or not isCallable(callback) then
        error("Argon:BindKey expects (Enum.KeyCode, function)", 2)
    end

    local binding = {
        KeyCode = keyCode,
        Callback = callback,
        IgnoreGameProcessed = options.IgnoreGameProcessed ~= false,
        Connection = nil,
    }

    KeyBindings[#KeyBindings + 1] = binding

    local function matches(input)
        return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == keyCode
    end

    Connect(UserInputService.InputBegan, function(input, processed)
        if options.IgnoreGameProcessed and processed then
            return
        end
        if matches(input) then
            pcall(callback, true, input)
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if matches(input) then
            pcall(callback, false, input)
        end
    end)

    return binding
end

function Argon:UnbindKey(binding)
    for index, existing in ipairs(KeyBindings) do
        if existing == binding then
            table.remove(KeyBindings, index)
            return true
        end
    end
    return false
end

function Argon:ClearKeys()
    KeyBindings = {}
    return self
end

-- ============================================================================
-- 39. PUBLIC ENTRY POINTS
-- ============================================================================

function Argon:CreateWindow(options)
    return Window.new(options)
end

function Argon:GetWindows()
    return self.Windows
end

function Argon:GetVersion()
    return self.Version
end

function Argon:SetDebug(enabled)
    self.Debug = enabled and true or false
    return self
end

function Argon:SetConfigFolder(path)
    self.Config.ConfigFolder = tostring(path)
    return self
end

function Argon:EnableAutoSave(name, delay)
    self.Config.AutoSave = true
    self.Config.AutoSaveDelay = tonumber(delay) or self.Config.AutoSaveDelay
    self._autoSaveName = name
    for flag in pairs(self.Flags) do
        self:OnFlagChanged(flag, function()
            ConfigStore.scheduleSave(name)
        end)
    end
    return self
end

function Argon:Unload()
    if self.Unloaded then
        return
    end
    self.Unloaded = true

    local connections = {}
    for index, connection in ipairs(self.Connections) do
        connections[index] = connection
    end
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    self.Connections = {}

    for _, window in ipairs(self.Windows) do
        if window.Destroy then
            pcall(window.Destroy, window)
        end
    end
    self.Windows = {}

    for _, toolbar in ipairs(self.Toolbars or {}) do
        pcall(toolbar.Destroy, toolbar)
    end
    self.Toolbars = {}

    for _, dialog in ipairs(self.Dialogs) do
        pcall(function()
            dialog:Close()
        end)
    end
    self.Dialogs = {}

    if NotificationUI.gui then
        pcall(function()
            NotificationUI.gui:Destroy()
        end)
        NotificationUI.gui = nil
    end
    NotificationUI.list = {}

    if TooltipUI.gui then
        pcall(function()
            TooltipUI.gui:Destroy()
        end)
        TooltipUI.gui = nil
    end

    for _, instance in ipairs(self.Instances) do
        pcall(function()
            if instance and instance.Parent then
                instance:Destroy()
            end
        end)
    end
    self.Instances = {}
    self.ThemeAppliers = {}
    self.Flags = {}

    if GENV.Argon == self then
        GENV.Argon = nil
    end
    if GENV.ArgonLib == self then
        GENV.ArgonLib = nil
    end
end

function Argon:IsLoaded()
    return not self.Unloaded
end

-- Publish to the executor's global environment so other scripts can reach the
-- UI, and keep the legacy aliases older Argon scripts look for.
GENV.Argon = Argon
GENV.ArgonLib = Argon
if GENV.Library == nil then
    GENV.Library = Argon
end

-- ============================================================================
-- 40. API INDEX (for quick grep)
-- ============================================================================
-- Argon:Window              Argon:Notify              Argon:Dialog
-- Argon:Toolbar             Argon:Watermark           Argon:SetTheme
-- Argon:GetTheme            Argon:GetThemeNames       Argon:SetAccent
-- Argon:RegisterTheme       Argon:ThemeTemplate       Argon:BuildConfigPage
-- Argon:GetFlag             Argon:SetFlag             Argon:GetFlags
-- Argon:OnFlagChanged       Argon:SaveConfig          Argon:LoadConfig
-- Argon:GetConfigs          Argon:DeleteConfig        Argon:EnableAutoSave
-- Argon:Unload              Argon:SetDebug            Argon:SetConfigFolder
-- Argon:BindKey             Argon:UnbindKey           Argon:ClearKeys
-- Argon:GetUptime           Argon:IsMobile            Argon:GetViewportSize
-- Argon:ShowLoading         Argon:GetWindows          Argon:GetVersion
--
-- Window:Page               Window:SelectPage         Window:GetPage
-- Window:SetTitle           Window:SetSubtitle        Window:SetUser
-- Window:SetTheme           Window:SetAccent          Window:SetMinimized
-- Window:SetVisible         Window:Toggle             Window:Refresh
-- Window:Notify             Window:Dialog             Window:Destroy
-- Window:OnFlagChanged      Window:BuildShell         Window:RebuildNav
--
-- Page:Section              Page:Pills                Page:Search
-- Page:Action               Page:SetActionEnabled     Page:SetPill
-- Page:ApplyFilter          Page:Refresh              Page:ScrollToTop
-- Page:SetSubtitle          Page:SetVisible           Page:Destroy
--
-- Section:Toggle            Section:Checkbox          Section:Slider
-- Section:Input             Section:Textarea          Section:Keybind
-- Section:Button            Section:DualButton        Section:ColorPicker
-- Section:ThemePicker       Section:Card              Section:Table
-- Section:Label             Section:Paragraph         Section:Divider
-- Section:Space             Section:Progress          Section:Tag
-- Section:UserRow           Section:Banner            Section:Image
-- Section:Collapse          Section:SetName
-- Section:SetVisible        Section:Refresh           Section:Clear
-- Section:UpdateOrder       Section:Destroy
--
-- Element:Set               Element:Get               Element:GetValue
-- Element:OnChanged         Element:Refresh           Element:SetVisible
-- Element:SetDisabled       Element:SetName           Element:SetDescription
-- Element:Destroy
-- ============================================================================

return Argon
