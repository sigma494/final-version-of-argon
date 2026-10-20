--[[
    Argon — a UI library for Roblox executors.
    Single file. No dependencies. No loadstring chain. Everything you need and nothing else.

    Load:
        local Argon = loadstring(game:HttpGet("https://raw.githubusercontent.com/sigma494/final-version-of-argon/main/Argon.lua"))()

    Use:
        local Window = Argon:Window({
            Title = "Argon",
            Subtitle = "final build",
            ToggleKey = Enum.KeyCode.RightShift,
            Accent = Color3.fromRGB(88, 166, 255),
        })

        local Tab = Window:Tab({ Name = "Main" })
        local Section = Tab:Section({ Name = "Combat" })

        Section:Toggle({ Name = "Aimbot", Flag = "aimbot", Default = false }, function(on)
            print("aimbot", on)
        end)

        Section:Slider({ Name = "FOV", Flag = "fov", Min = 10, Max = 360, Default = 90, Suffix = "°" }, function(v)
            print("fov", v)
        end)

        Window:Notify({ Title = "Argon", Text = "Loaded in " .. tostring(math.floor(os.clock() * 1000)) .. "ms" })

    Every element returns a handle with :Set(value), :Get(), :SetVisible(bool), :Destroy().
    Every element can carry a Flag; flags are readable with Argon:GetFlag("fov") and
    persist through configs (Window:SaveConfig / Window:LoadConfig).

    Tested against the API surface available in Synapse X, Wave, Fluxus, Delta, Krnl and AWP.
    Nothing here touches the game's DataModel; it only builds GUI.
]]

-- ============================================================================
-- singleton guard: reloading the script replaces the previous UI instead of
-- stacking two of them on top of each other
-- ============================================================================
local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
if GENV.Argon and typeof(GENV.Argon.Unload) == "function" then
    pcall(function()
        GENV.Argon:Unload()
    end)
end

-- ============================================================================
-- services
-- ============================================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ============================================================================
-- library state
-- ============================================================================
local Argon = {
    Version = "1.0.0",
    Name = "Argon",
    Flags = {},          -- flag -> current value
    Connections = {},    -- every RBXScriptConnection we own, for Unload
    Instances = {},      -- every Instance we own, for Unload
    Windows = {},
    Notifications = {},
    Unloaded = false,
}

Argon.Theme = {
    Background = Color3.fromRGB(17, 18, 23),
    Surface = Color3.fromRGB(23, 25, 32),
    SurfaceHigh = Color3.fromRGB(31, 34, 43),
    SurfaceActive = Color3.fromRGB(38, 42, 53),
    Stroke = Color3.fromRGB(45, 49, 61),
    StrokeLight = Color3.fromRGB(60, 66, 82),
    Text = Color3.fromRGB(235, 239, 246),
    TextMuted = Color3.fromRGB(139, 147, 165),
    Accent = Color3.fromRGB(88, 166, 255),
    Danger = Color3.fromRGB(248, 113, 113),
    Success = Color3.fromRGB(74, 222, 128),
    Warning = Color3.fromRGB(251, 191, 36),
    Font = Enum.Font.Gotham,
    FontMedium = Enum.Font.GothamMedium,
    FontBold = Enum.Font.GothamBold,
    FontMono = Enum.Font.Code,
}

-- ============================================================================
-- tiny utilities
-- ============================================================================
local unpack = unpack or table.unpack  -- Luau and Lua 5.1 have unpack; 5.2+ moved it

local function pack(...)
    return { n = select("#", ...), ... }
end

local function Try(fn, ...)
    local results = pack(pcall(fn, ...))
    if not results[1] then
        warn("[Argon] " .. tostring(results[2]))
        return false, results[2]
    end
    if results.n > 2 then
        return true, unpack(results, 2, results.n)
    end
    return true, results[2]
end

local function Connect(signal, fn)
    local connection = signal:Connect(function(...)
        if Argon.Unloaded then
            return
        end
        Try(fn, ...)
    end)
    table.insert(Argon.Connections, connection)
    return connection
end

local function New(class, props, children)
    local instance = Instance.new(class)
    for key, value in pairs(props or {}) do
        if key ~= "Parent" then
            instance[key] = value
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = instance
    end
    if props and props.Parent then
        instance.Parent = props.Parent
    end
    table.insert(Argon.Instances, instance)
    return instance
end

local function Tween(instance, properties, duration, style, direction)
    local info = TweenInfo.new(
        duration or 0.16,
        style or Enum.EasingStyle.Quad,
        direction or Enum.EasingDirection.Out
    )
    local tween = TweenService:Create(instance, info, properties)
    tween:Play()
    return tween
end

local function Round(value, step)
    step = step or 1
    if step <= 0 then
        return value
    end
    return math.floor(value / step + 0.5) * step
end

local function Clamp(value, min, max)
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function IsColor(value)
    return typeof(value) == "Color3"
end

local function IsEnumItem(value)
    return typeof(value) == "EnumItem"
end

-- HSV -> Color3 without relying on Color3.fromHSV (some executors shadow it)
local function HSVtoRGB(h, s, v)
    h = h % 1
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    local r, g, b
    if i == 0 then
        r, g, b = v, t, p
    elseif i == 1 then
        r, g, b = q, v, p
    elseif i == 2 then
        r, g, b = p, v, t
    elseif i == 3 then
        r, g, b = p, q, v
    elseif i == 4 then
        r, g, b = t, p, v
    else
        r, g, b = v, p, q
    end
    return Color3.new(r, g, b)
end

local function RGBtoHSV(color)
    local r, g, b = color.R, color.G, color.B
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local delta = max - min
    local h, s, v

    v = max
    if max == 0 then
        s = 0
    else
        s = delta / max
    end

    if delta == 0 then
        h = 0
    elseif max == r then
        h = ((g - b) / delta) % 6
    elseif max == g then
        h = (b - r) / delta + 2
    else
        h = (r - g) / delta + 4
    end
    h = h / 6

    return h, s, v
end

local function FormatNumber(value, decimals)
    if decimals and decimals > 0 then
        return string.format("%." .. tostring(decimals) .. "f", value)
    end
    if value % 1 == 0 then
        return tostring(math.floor(value))
    end
    return string.format("%.2f", value)
end

local function GuiParent()
    local ok, hui = pcall(function()
        if gethui then
            return gethui()
        end
        return nil
    end)
    if ok and hui then
        return hui
    end

    local okCore, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if okCore and coreGui then
        return coreGui
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local function CreateScreenGui(name, displayOrder)
    local gui = New("ScreenGui", {
        Name = name,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = displayOrder or 999,
    })
    gui.Parent = GuiParent()

    if syn and syn.protect_gui then
        pcall(syn.protect_gui, gui)
    end
    if protectgui then
        pcall(protectgui, gui)
    end
    return gui
end

local function Corner(radius)
    return New("UICorner", { CornerRadius = radius or UDim.new(0, 8) })
end

local function Stroke(color, thickness, transparency)
    return New("UIStroke", {
        Color = color or Argon.Theme.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function Padding(top, right, bottom, left)
    return New("UIPadding", {
        PaddingTop = UDim.new(0, top or 0),
        PaddingRight = UDim.new(0, right or top or 0),
        PaddingBottom = UDim.new(0, bottom or top or 0),
        PaddingLeft = UDim.new(0, left or right or top or 0),
    })
end

local function TextLabel(props)
    props = props or {}
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.BorderSizePixel = props.BorderSizePixel or 0
    props.Font = props.Font or Argon.Theme.Font
    props.TextColor3 = props.TextColor3 or Argon.Theme.Text
    props.TextSize = props.TextSize or 13
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
    if props.RichText == nil then
        props.RichText = false
    end
    return New("TextLabel", props)
end

local function TextButton(props)
    props = props or {}
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.BorderSizePixel = props.BorderSizePixel or 0
    props.AutoButtonColor = false
    props.Font = props.Font or Argon.Theme.Font
    props.TextColor3 = props.TextColor3 or Argon.Theme.Text
    props.TextSize = props.TextSize or 13
    props.Text = props.Text or ""
    return New("TextButton", props)
end

local function ScrollingFrame(props)
    props = props or {}
    props.BackgroundTransparency = props.BackgroundTransparency or 1
    props.BorderSizePixel = 0
    props.ScrollBarThickness = props.ScrollBarThickness or 3
    props.ScrollBarImageColor3 = props.ScrollBarImageColor3 or Argon.Theme.StrokeLight
    props.ScrollBarImageTransparency = props.ScrollBarImageTransparency or 0.4
    props.CanvasSize = props.CanvasSize or UDim2.new(0, 0, 0, 0)
    props.ScrollingDirection = props.ScrollingDirection or Enum.ScrollingDirection.Y
    props.ElasticBehavior = Enum.ElasticBehavior.Never
    return New("ScrollingFrame", props)
end

local function MakeDraggable(frame, handle)
    handle = handle or frame
    local dragging = false
    local dragStart, startPos

    Connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    Connect(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function SetCanvasBounds(scroller, layout, paddingBottom)
    local function update()
        local content = layout.AbsoluteContentSize
        scroller.CanvasSize = UDim2.new(0, 0, 0, content.Y + (paddingBottom or 12))
    end
    Connect(scroller:GetPropertyChangedSignal("AbsoluteSize"), update)
    Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), update)
    update()
end

-- ============================================================================
-- element base
--
-- Every element is a row inside a section. Subclasses build their own controls
-- inside `self.Row` and register themselves in the section's layout.
-- ============================================================================
local Window, Tab, Section  -- forward declarations: defined further down

local Element = {}
Element.__index = Element

function Element.new(section, config)
    local self = setmetatable({}, Element)
    self.Section = section
    self.Window = section.Window
    self.Config = config or {}
    self.Flag = self.Config.Flag
    self.Value = self.Config.Default
    self.Destroyed = false
    self.Callbacks = {}

    self.Row = New("Frame", {
        Name = (self.Config.Name or "Element") .. "Row",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = true,
        Parent = section.Content,
    }, {
        New("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 0),
        }),
    })
    table.insert(section.Elements, self)

    if self.Flag then
        if Argon.Flags[self.Flag] == nil then
            Argon.Flags[self.Flag] = self.Value
        else
            self.Value = Argon.Flags[self.Flag]
        end
    end

    section:UpdateOrder()
    return self
end

function Element:AddCallback(fn)
    if typeof(fn) == "function" then
        table.insert(self.Callbacks, fn)
    end
    return self
end

function Element:Fire(...)
    if self.Destroyed then
        return
    end
    for _, callback in ipairs(self.Callbacks) do
        Try(callback, ...)
    end
    if self.Window then
        self.Window:FireFlagChanged(self.Flag, ...)
    end
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

function Element:GetValue()
    return self.Value
end

-- base implementation; controls with side effects (slider, input, picker) override it
function Element:Set(value, silent)
    return self:SetValue(value, silent)
end

function Element:Get()
    return self.Value
end

function Element:SetVisible(visible)
    self.Row.Visible = visible ~= false
    self.Section:UpdateOrder()
    return self
end

function Element:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self.Row.Active = not self.Disabled
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
    end
    return self
end

function Element:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for index, element in ipairs(self.Section.Elements) do
        if element == self then
            table.remove(self.Section.Elements, index)
            break
        end
    end
    if self.Row and self.Row.Parent then
        pcall(function()
            self.Row:Destroy()
        end)
    end
    self.Section:UpdateOrder()
end

-- Builds the standard "name + description on the left" block shared by most rows
function Element:BuildTextBlock(row, options)
    options = options or {}
    local height = options.Height or 44

    row.Size = UDim2.new(1, 0, 0, height)
    row.AutomaticSize = Enum.AutomaticSize.None
    row.BackgroundColor3 = Argon.Theme.Surface
    row.BackgroundTransparency = 0
    row.ClipsDescendants = false
    Corner(UDim.new(0, 6)).Parent = row

    New("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, options.PaddingTop or 0),
        PaddingBottom = UDim.new(0, options.PaddingBottom or 0),
    }, {}).Parent = row

    local textHolder = New("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, options.ReservedWidth or -120, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        Parent = row,
    }, {
        New("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 1),
        }),
    })

    self.NameLabel = TextLabel({
        Name = "Name",
        Text = tostring(self.Config.Name or ""),
        Size = UDim2.new(1, 0, 0, options.NameHeight or 18),
        TextSize = options.NameSize or 13,
        Font = Argon.Theme.FontMedium,
        LayoutOrder = 1,
        Parent = textHolder,
    })

    if options.Description ~= false and self.Config.Description and self.Config.Description ~= "" then
        self.DescriptionLabel = TextLabel({
            Name = "Description",
            Text = tostring(self.Config.Description),
            Size = UDim2.new(1, 0, 0, 15),
            TextSize = 11,
            TextColor3 = Argon.Theme.TextMuted,
            TextTruncate = Enum.TextTruncate.AtEnd,
            LayoutOrder = 2,
            Parent = textHolder,
        })
    end

    return textHolder
end

-- ============================================================================
-- Window
-- ============================================================================
Window = {}
Window.__index = Window

function Window:FireFlagChanged(flag, value)
    if not flag then
        return
    end
    local listeners = self.FlagListeners[flag]
    if not listeners then
        return
    end
    for _, fn in ipairs(listeners) do
        Try(fn, value)
    end
end

function Window:OnFlagChanged(flag, fn)
    self.FlagListeners[flag] = self.FlagListeners[flag] or {}
    table.insert(self.FlagListeners[flag], fn)
    return self
end

function Window:SetAccent(color)
    self.Options.Accent = color
    Argon.Theme.Accent = color
    if self.AccentFill then
        self.AccentFill.BackgroundColor3 = color
    end
    for _, tab in ipairs(self.Tabs) do
        tab:Refresh()
    end
    return self
end

function Window:Notify(config)
    return Argon:Notify(config)
end

function Window:Tab(config)
    config = config or {}
    local tab = setmetatable({
        Window = self,
        Name = config.Name or "Tab",
        Index = #self.Tabs + 1,
        Sections = {},
        Gui = nil,
        Button = nil,
        Destroyed = false,
    }, Tab)
    table.insert(self.Tabs, tab)
    tab:Build()
    if #self.Tabs == 1 then
        self:SelectTab(tab)
    end
    return tab
end

function Window:SelectTab(tab)
    if self.ActiveTab == tab then
        return self
    end
    self.ActiveTab = tab
    for _, candidate in ipairs(self.Tabs) do
        local active = candidate == tab
        candidate.Content.Visible = active
        if candidate.Button then
            candidate.Button.BackgroundColor3 = active and Argon.Theme.SurfaceActive or Argon.Theme.Surface
            candidate.Indicator.Visible = active
            candidate.Label.TextColor3 = active and Argon.Theme.Text or Argon.Theme.TextMuted
        end
    end
    return self
end

function Window:SetTitle(title)
    self.TitleLabel.Text = tostring(title or "")
    return self
end

function Window:SetSubtitle(subtitle)
    self.SubtitleLabel.Text = tostring(subtitle or "")
    return self
end

function Window:SetVisible(visible)
    self.Gui.Enabled = visible ~= false
    self.Visible = visible ~= false
    return self
end

function Window:Toggle()
    self:SetVisible(not self.Visible)
    return self
end

-- ---------------------------------------------------------------- configs
function Window:ConfigPath(name)
    return "Argon/configs/" .. tostring(name) .. ".json"
end

function Window:SerializeFlags()
    local data = {}
    for flag, value in pairs(Argon.Flags) do
        if typeof(value) == "Color3" then
            data[flag] = { __type = "Color3", R = value.R, G = value.G, B = value.B }
        elseif IsEnumItem(value) then
            data[flag] = { __type = "EnumItem", Value = value.Name, EnumType = tostring(value.EnumType) }
        elseif typeof(value) == "boolean" or typeof(value) == "number" or typeof(value) == "string" then
            data[flag] = value
        elseif typeof(value) == "table" then
            local copy = {}
            for index, item in ipairs(value) do
                copy[index] = item
            end
            data[flag] = { __type = "Array", Items = copy }
        end
    end
    return data
end

function Window:DeserializeFlags(data)
    local flags = {}
    for flag, value in pairs(data or {}) do
        if typeof(value) == "table" and value.__type == "Color3" then
            flags[flag] = Color3.new(value.R, value.G, value.B)
        elseif typeof(value) == "table" and value.__type == "Array" then
            flags[flag] = value.Items
        else
            flags[flag] = value
        end
    end
    return flags
end

function Window:SaveConfig(name)
    if typeof(writefile) ~= "function" then
        warn("[Argon] writefile is not available in this executor; config not saved")
        return false
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(self:SerializeFlags())
    end)
    if not ok then
        warn("[Argon] could not encode config: " .. tostring(encoded))
        return false
    end
    local okWrite = pcall(function()
        if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder("Argon") then
            makefolder("Argon")
        end
        if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder("Argon/configs") then
            makefolder("Argon/configs")
        end
        writefile(self:ConfigPath(name), encoded)
    end)
    if not okWrite then
        warn("[Argon] could not write config (missing folder permissions?)")
        return false
    end
    return true
end

function Window:LoadConfig(name)
    if typeof(isfile) ~= "function" or typeof(readfile) ~= "function" then
        warn("[Argon] readfile/isfile are not available in this executor")
        return false
    end
    local path = self:ConfigPath(name)
    if not isfile(path) then
        warn("[Argon] no config named " .. tostring(name))
        return false
    end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(path))
    end)
    if not ok then
        warn("[Argon] config is corrupt: " .. tostring(decoded))
        return false
    end

    local flags = self:DeserializeFlags(decoded)
    for flag, value in pairs(flags) do
        Argon.Flags[flag] = value
        local listener = self.FlagListeners[flag]
        if listener then
            for _, fn in ipairs(listener) do
                Try(fn, value)
            end
        end
    end

    for _, tab in ipairs(self.Tabs) do
        for _, section in ipairs(tab.Sections) do
            for _, element in ipairs(section.Elements) do
                if element.Refresh then
                    element:Refresh()
                end
            end
        end
    end
    return true
end

function Window:DeleteConfig(name)
    if typeof(delfile) == "function" and typeof(isfile) == "function" then
        local path = self:ConfigPath(name)
        if isfile(path) then
            pcall(delfile, path)
            return true
        end
    end
    return false
end

function Window:GetConfigs()
    local list = {}
    if typeof(listfiles) ~= "function" then
        return list
    end
    local ok, files = pcall(listfiles, "Argon/configs")
    if not ok or not files then
        return list
    end
    for _, file in ipairs(files) do
        local name = string.match(file, "([^/\\]+)%.json$")
        if name then
            table.insert(list, name)
        end
    end
    return list
end

function Window:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for index, candidate in ipairs(Argon.Windows) do
        if candidate == self then
            table.remove(Argon.Windows, index)
            break
        end
    end
    pcall(function()
        self.Gui:Destroy()
    end)
    for _, tab in ipairs(self.Tabs) do
        tab.Destroyed = true
    end
end

function Window.new(options)
    local self = setmetatable({
        Options = options or {},
        Tabs = {},
        FlagListeners = {},
        ActiveTab = nil,
        Destroyed = false,
        Visible = true,
    }, Window)

    local theme = Argon.Theme
    local accent = self.Options.Accent or theme.Accent
    theme.Accent = accent

    local width = self.Options.Width or 580
    local height = self.Options.Height or 460
    local title = self.Options.Title or "Argon"
    local subtitle = self.Options.Subtitle or ("v" .. Argon.Version)

    self.Gui = CreateScreenGui("Argon", self.Options.DisplayOrder)

    local shadow = New("Frame", {
        Name = "Shadow",
        Parent = self.Gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, width + 2, 0, height + 2),
        BackgroundColor3 = accent,
        BackgroundTransparency = 0.86,
        BorderSizePixel = 0,
        ZIndex = 1,
    })
    Corner(UDim.new(0, 14)).Parent = shadow

    local main = New("Frame", {
        Name = "Main",
        Parent = self.Gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, width, 0, height),
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = false,
        ZIndex = 2,
    })
    Corner(UDim.new(0, 12)).Parent = main
    Stroke(theme.Stroke, 1).Parent = main
    self.Main = main

    -- header ---------------------------------------------------------------
    local header = New("Frame", {
        Name = "Header",
        Parent = main,
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundTransparency = 1,
        ZIndex = 3,
    })
    self.Header = header

    self.AccentFill = New("Frame", {
        Name = "Accent",
        Parent = header,
        Position = UDim2.new(0, 16, 0, 12),
        Size = UDim2.new(0, 4, 0, 24),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        ZIndex = 3,
    })
    Corner(UDim.new(1, 0)).Parent = self.AccentFill

    self.TitleLabel = TextLabel({
        Name = "Title",
        Parent = header,
        Position = UDim2.new(0, 30, 0, 8),
        Size = UDim2.new(1, -140, 0, 20),
        Text = title,
        TextSize = 15,
        Font = theme.FontBold,
        ZIndex = 3,
    })

    self.SubtitleLabel = TextLabel({
        Name = "Subtitle",
        Parent = header,
        Position = UDim2.new(0, 30, 0, 26),
        Size = UDim2.new(1, -140, 0, 14),
        Text = subtitle,
        TextSize = 11,
        TextColor3 = theme.TextMuted,
        ZIndex = 3,
    })

    local closeButton = TextButton({
        Name = "Close",
        Parent = header,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 12),
        Size = UDim2.new(0, 24, 0, 24),
        Text = "×",
        TextSize = 18,
        TextColor3 = theme.TextMuted,
        ZIndex = 4,
    })
    Corner(UDim.new(0, 6)).Parent = closeButton
    closeButton.MouseEnter:Connect(function()
        Tween(closeButton, { BackgroundTransparency = 0, BackgroundColor3 = theme.Danger, TextColor3 = theme.Text }, 0.1)
    end)
    closeButton.MouseLeave:Connect(function()
        Tween(closeButton, { BackgroundTransparency = 1, TextColor3 = theme.TextMuted }, 0.1)
    end)
    Connect(closeButton.MouseButton1Click, function()
        self:SetVisible(false)
    end)

    local minimizeButton = TextButton({
        Name = "Minimize",
        Parent = header,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -42, 0, 12),
        Size = UDim2.new(0, 24, 0, 24),
        Text = "–",
        TextSize = 16,
        TextColor3 = theme.TextMuted,
        ZIndex = 4,
    })
    Corner(UDim.new(0, 6)).Parent = minimizeButton
    self.Minimized = false
    Connect(minimizeButton.MouseButton1Click, function()
        self.Minimized = not self.Minimized
        if self.Minimized then
            self.Body.Visible = false
            main.Size = UDim2.new(0, width, 0, 48)
        else
            self.Body.Visible = true
            main.Size = UDim2.new(0, width, 0, height)
        end
    end)

    MakeDraggable(main, header)

    -- body ----------------------------------------------------------------
    local body = New("Frame", {
        Name = "Body",
        Parent = main,
        Position = UDim2.new(0, 10, 0, 48),
        Size = UDim2.new(1, -20, 1, -58),
        BackgroundTransparency = 1,
        ZIndex = 3,
    })
    self.Body = body

    local sidebar = New("Frame", {
        Name = "Sidebar",
        Parent = body,
        Size = UDim2.new(0, 150, 1, 0),
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        ZIndex = 3,
    })
    Corner(UDim.new(0, 8)).Parent = sidebar
    self.Sidebar = sidebar

    self.TabList = New("Frame", {
        Name = "Tabs",
        Parent = sidebar,
        Position = UDim2.new(0, 6, 0, 6),
        Size = UDim2.new(1, -12, 1, -12),
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, {
        New("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 4),
        }),
    })

    local footer = TextLabel({
        Name = "Footer",
        Parent = body,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, 0),
        Size = UDim2.new(0, 160, 0, 14),
        Text = "Argon " .. Argon.Version,
        TextSize = 10,
        TextColor3 = theme.TextMuted,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
    })
    self.Footer = footer

    local contentHolder = New("Frame", {
        Name = "ContentHolder",
        Parent = body,
        Position = UDim2.new(0, 160, 0, 0),
        Size = UDim2.new(1, -160, 1, -18),
        BackgroundTransparency = 1,
        ZIndex = 4,
    })
    self.ContentHolder = contentHolder

    table.insert(Argon.Windows, self)
    table.insert(Argon.Instances, self.Gui)

    -- global toggle key ----------------------------------------------------
    self.ToggleKey = self.Options.ToggleKey or Enum.KeyCode.RightShift
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

    if self.Options.AutoLoad and typeof(self.LoadConfig) == "function" then
        self:LoadConfig(self.Options.AutoLoad)
    end

    if self.Options.AutoSaveTo and typeof(self.SaveConfig) == "function" then
        self:BindAutoSave(self.Options.AutoSaveTo)
    end

    return self
end

function Window:BindAutoSave(name)
    local pending = false
    for flag in pairs(Argon.Flags) do
        self:OnFlagChanged(flag, function()
            if pending then
                return
            end
            pending = true
            task.delay(1, function()
                pending = false
                self:SaveConfig(name)
            end)
        end)
    end
    return self
end

-- ============================================================================
-- Tab
-- ============================================================================
Tab = {}
Tab.__index = Tab

function Tab:Build()
    local theme = Argon.Theme

    local button = New("TextButton", {
        Name = "Tab_" .. tostring(self.Index),
        Parent = self.Window.TabList,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = self.Index,
        ZIndex = 3,
    })
    Corner(UDim.new(0, 7)).Parent = button
    self.Button = button

    self.Indicator = New("Frame", {
        Name = "Indicator",
        Parent = button,
        Position = UDim2.new(0, 6, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 3, 0, 16),
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 4,
    })
    Corner(UDim.new(1, 0)).Parent = self.Indicator

    self.Label = TextLabel({
        Name = "Label",
        Parent = button,
        Position = UDim2.new(0, 16, 0, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = self.Name,
        TextSize = 13,
        Font = theme.FontMedium,
        TextColor3 = theme.TextMuted,
        ZIndex = 4,
    })

    Connect(button.MouseEnter, function()
        if self.Window.ActiveTab ~= self then
            Tween(button, { BackgroundColor3 = theme.SurfaceHigh }, 0.12)
        end
    end)
    Connect(button.MouseLeave, function()
        if self.Window.ActiveTab ~= self then
            Tween(button, { BackgroundColor3 = theme.Surface }, 0.12)
        end
    end)
    Connect(button.MouseButton1Click, function()
        self.Window:SelectTab(self)
    end)

    local content = ScrollingFrame({
        Name = "Content_" .. tostring(self.Index),
        Parent = self.Window.ContentHolder,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Visible = false,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = 4,
    })
    Padding(2, 2, 8, 2).Parent = content
    local layout = New("UIListLayout", {
        Parent = content,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
    })
    self.Content = content
    self.Layout = layout
    SetCanvasBounds(content, layout, 12)
    self.Content.Parent = self.Window.ContentHolder
end

function Tab:Section(config)
    config = config or {}
    local section = setmetatable({
        Tab = self,
        Window = self.Window,
        Name = config.Name or "Section",
        Index = #self.Sections + 1,
        Elements = {},
    }, Section)
    table.insert(self.Sections, section)
    section:Build(config)
    return section
end

function Tab:Refresh()
    for _, section in ipairs(self.Sections) do
        section:Refresh()
    end
end

function Tab:Destroy()
    for _, section in ipairs(self.Sections) do
        for _, element in ipairs(section.Elements) do
            element:Destroy()
        end
    end
    if self.Button then
        self.Button:Destroy()
    end
    if self.Content then
        self.Content:Destroy()
    end
    for index, candidate in ipairs(self.Window.Tabs) do
        if candidate == self then
            table.remove(self.Window.Tabs, index)
            break
        end
    end
end

-- ============================================================================
-- Section
-- ============================================================================
Section = {}
Section.__index = Section

function Section:Build(config)
    local theme = Argon.Theme
    config = config or {}

    local frame = New("Frame", {
        Name = "Section_" .. tostring(self.Index),
        Parent = self.Tab.Content,
        Size = UDim2.new(1, 0, 0, config.Height or 30),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        LayoutOrder = self.Index,
        ZIndex = 4,
    })
    Corner(UDim.new(0, 9)).Parent = frame
    Stroke(theme.Stroke, 1, 0.5).Parent = frame
    self.Frame = frame

    local header = New("Frame", {
        Name = "Header",
        Parent = frame,
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        ZIndex = 4,
    })
    self.Header = header

    self.Title = TextLabel({
        Name = "Title",
        Parent = header,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = self.Name,
        TextSize = 12,
        Font = theme.FontBold,
        TextColor3 = theme.TextMuted,
        ZIndex = 5,
    })

    local content = New("Frame", {
        Name = "Content",
        Parent = frame,
        Position = UDim2.new(0, 0, 0, 32),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 4,
    })
    Padding(0, 8, 8, 8).Parent = content
    New("UIListLayout", {
        Parent = content,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    })
    self.Content = content
end

function Section:UpdateOrder()
    local visibleIndex = 0
    for _, element in ipairs(self.Elements) do
        if element.Row and element.Row.Visible then
            visibleIndex = visibleIndex + 1
            element.Row.LayoutOrder = visibleIndex
        end
    end
    if self.Content then
        self.Content.LayoutOrder = 1
    end
end

function Section:Refresh()
    for _, element in ipairs(self.Elements) do
        if element.Refresh then
            element:Refresh()
        end
    end
end

function Section:SetName(name)
    self.Name = tostring(name)
    self.Title.Text = self.Name
    return self
end

function Section:Collapse(collapsed)
    self.Collapsed = collapsed and true or false
    self.Content.Visible = not self.Collapsed
    self.Frame.Size = UDim2.new(1, 0, 0, self.Collapsed and 32 or 30)
    return self
end

function Section:SetVisible(visible)
    self.Frame.Visible = visible ~= false
    return self
end

-- ============================================================================
-- elements
-- ============================================================================

-- ---------------------------------------------------------------- Toggle
function Section:Toggle(config, callback)
    config = config or {}
    local element = Element.new(self, config)
    local theme = Argon.Theme
    local row = element.Row

    element:AddCallback(callback)
    element:BuildTextBlock(row, { Height = 44, ReservedWidth = -62 })

    local switch = New("Frame", {
        Name = "Switch",
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 40, 0, 22),
        BackgroundColor3 = theme.SurfaceHigh,
        BorderSizePixel = 0,
        ZIndex = 5,
    })
    Corner(UDim.new(1, 0)).Parent = switch
    local switchStroke = Stroke(theme.StrokeLight, 1, 0.3)
    switchStroke.Parent = switch

    local knob = New("Frame", {
        Name = "Knob",
        Parent = switch,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 2, 0.5, 0),
        Size = UDim2.new(0, 18, 0, 18),
        BackgroundColor3 = theme.TextMuted,
        BorderSizePixel = 0,
        ZIndex = 6,
    })
    Corner(UDim.new(1, 0)).Parent = knob

    local clickArea = TextButton({
        Name = "Click",
        Parent = switch,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        ZIndex = 7,
    })

    local function render(animate)
        local on = element.Value and true or false
        local targetColor = on and theme.Accent or theme.SurfaceHigh
        local knobColor = on and Color3.new(1, 1, 1) or theme.TextMuted
        local knobPos = UDim2.new(0, on and 20 or 2, 0.5, 0)

        if animate then
            Tween(switch, { BackgroundColor3 = targetColor }, 0.16)
            Tween(knob, { Position = knobPos, BackgroundColor3 = knobColor }, 0.16)
        else
            switch.BackgroundColor3 = targetColor
            knob.Position = knobPos
            knob.BackgroundColor3 = knobColor
        end
        switchStroke.Transparency = on and 1 or 0.3
    end

    element.Refresh = function()
        render(false)
    end

    Connect(clickArea.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element:SetValue(not element.Value)
        render(true)
    end)

    render(false)
    return element
end

-- ---------------------------------------------------------------- Slider
function Section:Slider(config, callback)
    config = config or {}
    local theme = Argon.Theme
    local min = tonumber(config.Min) or 0
    local max = tonumber(config.Max) or 100
    if max <= min then
        max = min + 1
    end
    config.Min, config.Max = min, max
    config.Default = tonumber(config.Default) or min

    local element = Element.new(self, config)
    element.Step = tonumber(config.Step) or 1
    element.Decimals = config.Decimals or 0
    element.Suffix = config.Suffix or ""
    element:AddCallback(callback)

    local row = element.Row
    element:BuildTextBlock(row, { Height = 56, ReservedWidth = -80 })

    local valueLabel = TextLabel({
        Name = "Value",
        Parent = row,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 2, 0, 10),
        Size = UDim2.new(0, 80, 0, 18),
        Text = tostring(element.Value) .. element.Suffix,
        TextSize = 12,
        Font = theme.FontMedium,
        TextColor3 = theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 6,
    })

    local track = New("Frame", {
        Name = "Track",
        Parent = row,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -12),
        Size = UDim2.new(1, 0, 0, 4),
        BackgroundColor3 = theme.SurfaceHigh,
        BorderSizePixel = 0,
        ZIndex = 5,
    })
    Corner(UDim.new(1, 0)).Parent = track

    local fill = New("Frame", {
        Name = "Fill",
        Parent = track,
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 6,
    })
    Corner(UDim.new(1, 0)).Parent = fill

    local knob = New("Frame", {
        Name = "Knob",
        Parent = track,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 12),
        BackgroundColor3 = theme.Text,
        BorderSizePixel = 0,
        ZIndex = 7,
    })
    Corner(UDim.new(1, 0)).Parent = knob

    local trackHitbox = TextButton({
        Name = "Hitbox",
        Parent = row,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -2),
        Size = UDim2.new(1, 0, 0, 20),
        Text = "",
        ZIndex = 8,
    })

    local function ratio()
        return Clamp((element.Value - min) / (max - min), 0, 1)
    end

    local function render()
        local x = ratio()
        fill.Size = UDim2.new(x, 0, 1, 0)
        knob.Position = UDim2.new(x, 0, 0.5, 0)
        valueLabel.Text = FormatNumber(element.Value, element.Decimals) .. element.Suffix
    end

    element.Refresh = render

    local function setFromX(absoluteX)
        local width = math.max(trackHitbox.AbsoluteSize.X, 1)
        local rel = Clamp((absoluteX - trackHitbox.AbsolutePosition.X) / width, 0, 1)
        local raw = min + (max - min) * rel
        local value = Round(raw, element.Step)
        value = Clamp(value, min, max)
        if element.Decimals > 0 then
            local mult = 10 ^ element.Decimals
            value = math.floor(value * mult + 0.5) / mult
        end
        if value ~= element.Value then
            element:SetValue(value)
        end
        render()
    end

    local dragging = false

    Connect(trackHitbox.InputBegan, function(input)
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

    element.Set = function(_, value, silent)
        local nextValue = Clamp(tonumber(value) or element.Value, min, max)
        if nextValue ~= element.Value then
            element:SetValue(nextValue, silent)
        end
        render()
        return element
    end

    render()
    return element
end

-- ---------------------------------------------------------------- Dropdown
function Section:Dropdown(config, callback)
    config = config or {}
    local theme = Argon.Theme
    local multi = config.Multi and true or false

    if multi then
        config.Default = config.Default or {}
    end

    local element = Element.new(self, config)
    element.Multi = multi
    element.Options = config.Options or {}
    element:AddCallback(callback)

    local row = element.Row
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.Size = UDim2.new(1, 0, 0, 44)
    row.BackgroundColor3 = theme.Surface
    row.ClipsDescendants = false
    Corner(UDim.new(0, 6)).Parent = row

    local header = TextButton({
        Name = "Header",
        Parent = row,
        Size = UDim2.new(1, 0, 0, 44),
        Text = "",
        ZIndex = 5,
    })

    local nameLabel = TextLabel({
        Name = "Name",
        Parent = header,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(1, -110, 0, 28),
        Text = tostring(config.Name or ""),
        TextSize = 13,
        Font = theme.FontMedium,
        ZIndex = 6,
    })

    local valueLabel = TextLabel({
        Name = "Selected",
        Parent = header,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -30, 0, 8),
        Size = UDim2.new(0, 120, 0, 28),
        Text = "",
        TextSize = 12,
        TextColor3 = theme.TextMuted,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 6,
    })

    local chevron = TextLabel({
        Name = "Chevron",
        Parent = header,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 8),
        Size = UDim2.new(0, 16, 0, 28),
        Text = "▾",
        TextSize = 13,
        TextColor3 = theme.TextMuted,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 6,
    })

    local listHolder = New("Frame", {
        Name = "List",
        Parent = row,
        Position = UDim2.new(0, 0, 0, 44),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.SurfaceHigh,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 7,
    })
    New("UICorner", { CornerRadius = UDim.new(0, 6) }).Parent = listHolder
    Padding(4, 4, 4, 4).Parent = listHolder
    New("UIListLayout", {
        Parent = listHolder,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
    })

    local optionButtons = {}
    local opened = false

    local function isSelected(option)
        if multi then
            for _, value in ipairs(element.Value or {}) do
                if value == option then
                    return true
                end
            end
            return false
        end
        return element.Value == option
    end

    local function summary()
        if multi then
            local selected = element.Value or {}
            if #selected == 0 then
                return "None"
            end
            if #selected <= 2 then
                return table.concat(selected, ", ")
            end
            return tostring(#selected) .. " selected"
        end
        return element.Value ~= nil and tostring(element.Value) or "None"
    end

    element.Refresh = function()
        valueLabel.Text = summary()
        for option, button in pairs(optionButtons) do
            local selected = isSelected(option)
            button.BackgroundColor3 = selected and theme.SurfaceActive or theme.SurfaceHigh
            button.TextColor3 = selected and theme.Accent or theme.Text
            local tick = button:FindFirstChild("Tick")
            if tick then
                tick.Visible = selected
            end
        end
    end

    local function buildOptions()
        for _, child in ipairs(listHolder:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        optionButtons = {}

        for index, option in ipairs(element.Options) do
            local button = TextButton({
                Name = "Option_" .. tostring(index),
                Parent = listHolder,
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundColor3 = theme.SurfaceHigh,
                Text = "  " .. tostring(option),
                TextColor3 = theme.Text,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = index,
                ZIndex = 8,
            })
            Corner(UDim.new(0, 5)).Parent = button
            New("UIPadding", { PaddingLeft = UDim.new(0, 8) }).Parent = button

            local tick = TextLabel({
                Name = "Tick",
                Parent = button,
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.new(0, 14, 0, 14),
                Text = "✓",
                TextSize = 12,
                TextColor3 = theme.Accent,
                TextXAlignment = Enum.TextXAlignment.Right,
                Visible = false,
                ZIndex = 9,
            })

            Connect(button.MouseEnter, function()
                if not isSelected(option) then
                    button.BackgroundColor3 = theme.SurfaceActive
                end
            end)
            Connect(button.MouseLeave, function()
                if not isSelected(option) then
                    button.BackgroundColor3 = theme.SurfaceHigh
                end
            end)

            Connect(button.MouseButton1Click, function()
                if multi then
                    local selected = {}
                    local found = false
                    for _, value in ipairs(element.Value or {}) do
                        if value == option then
                            found = true
                        else
                            table.insert(selected, value)
                        end
                    end
                    if not found then
                        table.insert(selected, option)
                    end
                    element:SetValue(selected)
                else
                    element:SetValue(option)
                    element:Close()
                end
                element:Refresh()
            end)

            optionButtons[option] = button
        end
        element:Refresh()
    end

    function element:Open()
        opened = true
        listHolder.Visible = true
        Tween(chevron, { Rotation = 180 }, 0.12)
    end

    function element:Close()
        opened = false
        listHolder.Visible = false
        Tween(chevron, { Rotation = 0 }, 0.12)
    end

    function element:ToggleOpen()
        if opened then
            self:Close()
        else
            self:Open()
        end
    end

    function element:SetOptions(options)
        if typeof(options) ~= "table" then
            return self
        end
        self.Options = options
        buildOptions()
        return self
    end

    function element:GetOptions()
        return self.Options
    end

    Connect(header.MouseButton1Click, function()
        element:ToggleOpen()
    end)

    Connect(UserInputService.InputBegan, function(input)
        if not opened then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            local pos = input.Position
            local insideList = pos.X >= listHolder.AbsolutePosition.X
                and pos.X <= listHolder.AbsolutePosition.X + listHolder.AbsoluteSize.X
                and pos.Y >= row.AbsolutePosition.Y
                and pos.Y <= listHolder.AbsolutePosition.Y + listHolder.AbsoluteSize.Y
            if not insideList then
                element:Close()
            end
        end
    end)

    buildOptions()
    return element
end

-- ---------------------------------------------------------------- Input
function Section:Input(config, callback)
    config = config or {}
    local theme = Argon.Theme
    config.Default = config.Default or ""

    local element = Element.new(self, config)
    element:AddCallback(callback)

    local row = element.Row
    element:BuildTextBlock(row, { Height = 44, ReservedWidth = -180 })

    local box = New("TextBox", {
        Name = "Box",
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 170, 0, 30),
        BackgroundColor3 = theme.SurfaceHigh,
        BorderSizePixel = 0,
        Font = theme.Font,
        TextSize = 12,
        TextColor3 = theme.Text,
        Text = tostring(element.Value or ""),
        PlaceholderText = config.Placeholder or "Type here...",
        PlaceholderColor3 = theme.TextMuted,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ClipsDescendants = true,
        ZIndex = 6,
    })
    Corner(UDim.new(0, 6)).Parent = box
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }).Parent = box

    local boxStroke = Stroke(theme.Stroke, 1, 0)
    boxStroke.Parent = box

    element.Refresh = function()
        if box.Text ~= tostring(element.Value or "") then
            box.Text = tostring(element.Value or "")
        end
    end

    Connect(box.Focused, function()
        Tween(boxStroke, { Color = theme.Accent, Transparency = 0 }, 0.12)
    end)

    Connect(box.FocusLost, function(enterPressed)
        Tween(boxStroke, { Color = theme.Stroke, Transparency = 0 }, 0.12)
        local value = box.Text
        if config.Numeric then
            value = tonumber(value) or element.Value
        end
        if value ~= element.Value then
            element:SetValue(value)
        end
        if enterPressed then
            element:Fire(value, true)
        end
    end)

    element.Set = function(_, value, silent)
        element:SetValue(value, silent)
        box.Text = tostring(value or "")
        return element
    end

    return element
end

-- ---------------------------------------------------------------- Button
function Section:Button(config, callback)
    config = config or {}
    local theme = Argon.Theme

    local element = Element.new(self, config)
    element:AddCallback(callback)

    local row = element.Row
    row.Size = UDim2.new(1, 0, 0, 34)

    local button = TextButton({
        Name = "Button",
        Parent = row,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = theme.SurfaceHigh,
        Text = tostring(config.Name or "Button"),
        TextSize = 13,
        Font = theme.FontMedium,
        TextColor3 = theme.Text,
        ZIndex = 5,
    })
    Corner(UDim.new(0, 6)).Parent = button
    local buttonStroke = Stroke(theme.Stroke, 1, 0)
    buttonStroke.Parent = button

    Connect(button.MouseEnter, function()
        Tween(button, { BackgroundColor3 = theme.SurfaceActive }, 0.12)
        Tween(buttonStroke, { Color = theme.Accent }, 0.12)
    end)
    Connect(button.MouseLeave, function()
        Tween(button, { BackgroundColor3 = theme.SurfaceHigh }, 0.12)
        Tween(buttonStroke, { Color = theme.Stroke }, 0.12)
    end)
    Connect(button.MouseButton1Click, function()
        if element.Disabled then
            return
        end
        element:Fire()
    end)

    element.SetText = function(_, text)
        button.Text = tostring(text)
        return element
    end

    element.SetName = function(_, text)
        button.Text = tostring(text)
        return element
    end

    element.SetDisabled = function(_, disabled)
        element.Disabled = disabled and true or false
        button.TextTransparency = disabled and 0.5 or 0
        return element
    end

    return element
end

-- ---------------------------------------------------------------- Label / Paragraph / Divider
function Section:Label(config)
    config = config or {}
    if typeof(config) == "string" then
        config = { Text = config }
    end
    local theme = Argon.Theme
    local element = Element.new(self, config)

    local row = element.Row
    row.Size = UDim2.new(1, 0, 0, 24)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundTransparency = 1
    Padding(2, 2, 2, 2).Parent = row

    element.NameLabel = TextLabel({
        Name = "Text",
        Parent = row,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(config.Text or ""),
        TextSize = config.TextSize or 12,
        TextColor3 = config.Color or theme.Text,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 5,
    })

    return element
end

function Section:Paragraph(config)
    config = config or {}
    local theme = Argon.Theme
    local element = Element.new(self, config)

    local row = element.Row
    row.Size = UDim2.new(1, 0, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundTransparency = 1

    New("UIListLayout", {
        Parent = row,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
    })

    if config.Title and config.Title ~= "" then
        TextLabel({
            Name = "Title",
            Parent = row,
            Size = UDim2.new(1, 0, 0, 16),
            Text = tostring(config.Title),
            TextSize = 12,
            Font = theme.FontMedium,
            LayoutOrder = 1,
            ZIndex = 5,
        })
    end

    TextLabel({
        Name = "Body",
        Parent = row,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(config.Text or config.Content or ""),
        TextSize = 11,
        TextColor3 = theme.TextMuted,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 2,
        ZIndex = 5,
    })

    return element
end

function Section:Divider()
    local theme = Argon.Theme
    local element = Element.new(self, { Name = "Divider" })
    local row = element.Row
    row.Size = UDim2.new(1, 0, 0, 9)
    row.BackgroundTransparency = 1

    New("Frame", {
        Name = "Line",
        Parent = row,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = theme.Stroke,
        BorderSizePixel = 0,
        ZIndex = 5,
    })

    return element
end

function Section:Space(height)
    local element = Element.new(self, { Name = "Space" })
    element.Row.Size = UDim2.new(1, 0, 0, tonumber(height) or 8)
    element.Row.BackgroundTransparency = 1
    return element
end

-- ---------------------------------------------------------------- ColorPicker
function Section:ColorPicker(config, callback)
    config = config or {}
    local theme = Argon.Theme
    config.Default = config.Default or Color3.fromRGB(255, 255, 255)

    local element = Element.new(self, config)
    element:AddCallback(callback)

    local row = element.Row
    element:BuildTextBlock(row, { Height = 44, ReservedWidth = -56 })

    local swatch = New("Frame", {
        Name = "Swatch",
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 34, 0, 24),
        BackgroundColor3 = element.Value,
        BorderSizePixel = 0,
        ZIndex = 6,
    })
    Corner(UDim.new(0, 6)).Parent = swatch
    Stroke(theme.StrokeLight, 1, 0.2).Parent = swatch

    local swatchButton = TextButton({
        Name = "SwatchButton",
        Parent = swatch,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        ZIndex = 7,
    })

    local chevron = TextLabel({
        Name = "Chevron",
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -42, 0.5, 0),
        Size = UDim2.new(0, 12, 0, 16),
        Text = "▾",
        TextSize = 11,
        TextColor3 = theme.TextMuted,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 6,
    })

    local picker = New("Frame", {
        Name = "Picker",
        Parent = row,
        Position = UDim2.new(0, 0, 0, 44),
        Size = UDim2.new(1, 0, 0, 158),
        BackgroundColor3 = theme.SurfaceHigh,
        BorderSizePixel = 0,
        Visible = false,
        ClipsDescendants = true,
        ZIndex = 8,
    })
    Corner(UDim.new(0, 6)).Parent = picker
    Padding(8, 8, 8, 8).Parent = picker

    -- saturation / value square
    local satVal = New("Frame", {
        Name = "SatVal",
        Parent = picker,
        Size = UDim2.new(1, -18, 0, 110),
        BackgroundColor3 = Color3.new(1, 0, 0),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 9,
    })
    Corner(UDim.new(0, 4)).Parent = satVal

    New("Frame", {
        Name = "White",
        Parent = satVal,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 10,
    }).BackgroundTransparency = 0

    local satValOverlay = New("Frame", {
        Name = "Gradient",
        Parent = satVal,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 11,
    })
    local whiteGradient = New("UIGradient", { Parent = satValOverlay })
    whiteGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
    whiteGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    whiteGradient.Rotation = 0

    local blackOverlay = New("Frame", {
        Name = "BlackOverlay",
        Parent = satVal,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        ZIndex = 12,
    })
    local blackGradient = New("UIGradient", { Parent = blackOverlay })
    blackGradient.Rotation = 90
    blackGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })

    local marker = New("Frame", {
        Name = "Marker",
        Parent = satVal,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.new(0, 10, 0, 10),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 14,
    })
    Corner(UDim.new(1, 0)).Parent = marker
    Stroke(Color3.new(1, 1, 1), 2, 0).Parent = marker

    local satValHitbox = TextButton({
        Name = "Hitbox",
        Parent = satVal,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        ZIndex = 15,
    })

    -- hue slider
    local hueBar = New("Frame", {
        Name = "Hue",
        Parent = picker,
        Position = UDim2.new(0, 0, 0, 118),
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundColor3 = Color3.new(1, 0, 0),
        BorderSizePixel = 0,
        ZIndex = 9,
    })
    Corner(UDim.new(1, 0)).Parent = hueBar
    local hueGradient = New("UIGradient", { Parent = hueBar })
    hueGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
    })

    local hueMarker = New("Frame", {
        Name = "HueMarker",
        Parent = hueBar,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 6, 0, 16),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 10,
    })
    Corner(UDim.new(1, 0)).Parent = hueMarker

    local hueHitbox = TextButton({
        Name = "HueHitbox",
        Parent = hueBar,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        ZIndex = 11,
    })

    local hexBox = New("TextBox", {
        Name = "Hex",
        Parent = picker,
        Position = UDim2.new(0, 0, 0, 136),
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        Font = theme.FontMono,
        TextSize = 11,
        TextColor3 = theme.Text,
        Text = "",
        ClearTextOnFocus = false,
        ZIndex = 9,
    })
    Corner(UDim.new(0, 4)).Parent = hexBox
    Padding(6, 6, 0, 6).Parent = hexBox

    element.Hue = 0
    element.Saturation = 1
    element.Brightness = 1
    element.Opened = false

    local function colorToHex(color)
        return string.format(
            "%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5)
        )
    end

    local function syncHsv(fromColor)
        if fromColor then
            element.Hue, element.Saturation, element.Brightness = RGBtoHSV(element.Value)
        end
        local hueColor = HSVtoRGB(element.Hue, 1, 1)
        satVal.BackgroundColor3 = hueColor
        marker.Position = UDim2.new(element.Saturation, 0, 1 - element.Brightness, 0)
        hueMarker.Position = UDim2.new(element.Hue, 0, 0.5, 0)
        swatch.BackgroundColor3 = element.Value
        local hex = colorToHex(element.Value)
        if hexBox.Text ~= hex then
            hexBox.Text = hex
        end
    end

    element.Refresh = function()
        syncHsv(true)
    end

    local function applyColor(color)
        element:SetValue(color)
        syncHsv(false)
    end

    local function updateFromSatVal(x, y)
        local size = satVal.AbsoluteSize
        element.Saturation = Clamp((x - satVal.AbsolutePosition.X) / math.max(size.X, 1), 0, 1)
        element.Brightness = 1 - Clamp((y - satVal.AbsolutePosition.Y) / math.max(size.Y, 1), 0, 1)
        local color = HSVtoRGB(element.Hue, element.Saturation, element.Brightness)
        applyColor(color)
    end

    local function updateFromHue(x)
        local size = hueBar.AbsoluteSize
        element.Hue = Clamp((x - hueBar.AbsolutePosition.X) / math.max(size.X, 1), 0, 1)
        local color = HSVtoRGB(element.Hue, element.Saturation, element.Brightness)
        applyColor(color)
    end

    local draggingSV, draggingHue = false, false

    Connect(satValHitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV = true
            updateFromSatVal(input.Position.X, input.Position.Y)
        end
    end)

    Connect(hueHitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingHue = true
            updateFromHue(input.Position.X)
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV, draggingHue = false, false
        end
    end)

    Connect(UserInputService.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            if draggingSV then
                updateFromSatVal(input.Position.X, input.Position.Y)
            elseif draggingHue then
                updateFromHue(input.Position.X)
            end
        end
    end)

    Connect(hexBox.FocusLost, function()
        local hex = hexBox.Text:gsub("#", ""):gsub("%s", "")
        if #hex == 6 and hex:match("^%x+$") then
            local r = tonumber(hex:sub(1, 2), 16) / 255
            local g = tonumber(hex:sub(3, 4), 16) / 255
            local b = tonumber(hex:sub(5, 6), 16) / 255
            element:SetValue(Color3.new(r, g, b))
            syncHsv(true)
        else
            syncHsv(false)
        end
    end)

    Connect(swatchButton.MouseButton1Click, function()
        element.Opened = not element.Opened
        picker.Visible = element.Opened
        row.Size = UDim2.new(1, 0, 0, element.Opened and 202 or 44)
        Tween(chevron, { Rotation = element.Opened and 180 or 0 }, 0.12)
    end)

    element.Set = function(_, value, silent)
        if IsColor(value) then
            element:SetValue(value, silent)
            syncHsv(true)
        end
        return element
    end

    syncHsv(true)
    return element
end

-- ---------------------------------------------------------------- Keybind
function Section:Keybind(config, callback)
    config = config or {}
    local theme = Argon.Theme
    config.Default = config.Default or nil

    local element = Element.new(self, config)
    element:AddCallback(callback)
    element.Listening = false

    local row = element.Row
    element:BuildTextBlock(row, { Height = 44, ReservedWidth = -110 })

    local button = TextButton({
        Name = "KeyButton",
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 100, 0, 28),
        BackgroundColor3 = theme.SurfaceHigh,
        Text = element.Value and element.Value.Name or "None",
        TextSize = 12,
        TextColor3 = theme.Text,
        Font = theme.Font,
        ZIndex = 6,
    })
    Corner(UDim.new(0, 6)).Parent = button
    Stroke(theme.Stroke, 1, 0).Parent = button

    element.Refresh = function()
        button.Text = element.Value and tostring(element.Value.Name) or "None"
    end

    Connect(button.MouseButton1Click, function()
        element.Listening = true
        button.Text = "Press a key..."
        button.TextColor3 = theme.Accent
    end)

    Connect(UserInputService.InputBegan, function(input, processed)
        if not element.Listening then
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            element.Listening = false
            button.TextColor3 = theme.Text
            local key = input.KeyCode
            if key == Enum.KeyCode.Backspace or key == Enum.KeyCode.Delete then
                element:SetValue(nil)
            elseif not processed then
                element:SetValue(key)
            end
            element:Refresh()
        end
    end)

    element.Set = function(_, value, silent)
        if IsEnumItem(value) or value == nil then
            element:SetValue(value, silent)
            element:Refresh()
        end
        return element
    end

    Connect(UserInputService.InputBegan, function(input, processed)
        if processed or element.Listening or element.Disabled then
            return
        end
        if element.Value and input.KeyCode == element.Value then
            element:Fire(true)
        end
    end)

    Connect(UserInputService.InputEnded, function(input)
        if element.Value and input.KeyCode == element.Value then
            element:Fire(false)
        end
    end)

    return element
end

-- ---------------------------------------------------------------- Search / filter
function Section:Search(config)
    config = config or {}
    local theme = Argon.Theme
    local element = Element.new(self, config)

    local row = element.Row
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = theme.SurfaceHigh
    row.ClipsDescendants = true
    Corner(UDim.new(0, 6)).Parent = row
    Padding(0, 8, 0, 8).Parent = row

    local icon = TextLabel({
        Name = "Icon",
        Parent = row,
        Position = UDim2.new(0, 2, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 16, 0, 16),
        Text = "⌕",
        TextSize = 14,
        TextColor3 = theme.TextMuted,
        ZIndex = 6,
    })

    local box = New("TextBox", {
        Name = "Box",
        Parent = row,
        Position = UDim2.new(0, 22, 0, 0),
        Size = UDim2.new(1, -22, 1, 0),
        BackgroundTransparency = 1,
        Font = theme.Font,
        TextSize = 12,
        TextColor3 = theme.Text,
        Text = "",
        PlaceholderText = config.Placeholder or "Search...",
        PlaceholderColor3 = theme.TextMuted,
        ClearTextOnFocus = false,
        ZIndex = 6,
    })

    Connect(box:GetPropertyChangedSignal("Text"), function()
        element:SetValue(box.Text)
    end)

    element.Set = function(_, value, silent)
        element:SetValue(value, silent)
        box.Text = tostring(value or "")
        return element
    end

    return element
end

-- ============================================================================
-- notifications
-- ============================================================================
function Argon:Notify(config)
    config = config or {}
    if typeof(config) == "string" then
        config = { Text = config }
    end

    local theme = Argon.Theme
    local accent = config.Color or theme.Accent
    local duration = tonumber(config.Duration) or 4

    if not self.NotificationGui or not self.NotificationGui.Parent then
        self.NotificationGui = CreateScreenGui("ArgonNotifications", 1000)
    end

    local holder = New("Frame", {
        Name = "Toast",
        Parent = self.NotificationGui,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -18, 1, -18 - (#self.Notifications * 84)),
        Size = UDim2.new(0, 280, 0, 76),
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 50,
    })
    Corner(UDim.new(0, 9)).Parent = holder
    Stroke(theme.Stroke, 1, 1).Parent = holder

    local bar = New("Frame", {
        Name = "Accent",
        Parent = holder,
        Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        ZIndex = 51,
    })

    TextLabel({
        Name = "Title",
        Parent = holder,
        Position = UDim2.new(0, 14, 0, 10),
        Size = UDim2.new(1, -24, 0, 18),
        Text = tostring(config.Title or "Argon"),
        TextSize = 13,
        Font = theme.FontBold,
        TextColor3 = theme.Text,
        ZIndex = 51,
    })

    TextLabel({
        Name = "Body",
        Parent = holder,
        Position = UDim2.new(0, 14, 0, 30),
        Size = UDim2.new(1, -24, 0, 34),
        Text = tostring(config.Text or ""),
        TextSize = 11,
        TextColor3 = theme.TextMuted,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 51,
    })

    table.insert(self.Notifications, holder)
    local index = #self.Notifications

    Tween(holder, { BackgroundTransparency = 0 }, 0.18)
    holder.Position = UDim2.new(1, -18, 1, -18 - (index - 1) * 84)

    task.delay(duration, function()
        if holder.Parent then
            Tween(holder, { BackgroundTransparency = 1, Position = holder.Position + UDim2.new(0, 40, 0, 0) }, 0.18)
            task.wait(0.2)
            for i, notification in ipairs(self.Notifications) do
                if notification == holder then
                    table.remove(self.Notifications, i)
                    break
                end
            end
            pcall(function()
                holder:Destroy()
            end)
            for i, notification in ipairs(self.Notifications) do
                Tween(notification, { Position = UDim2.new(1, -18, 1, -18 - (i - 1) * 84) }, 0.16)
            end
        end
    end)

    return holder
end

-- ============================================================================
-- flags / lifecycle
-- ============================================================================
function Argon:GetFlag(flag)
    return self.Flags[flag]
end

function Argon:SetFlag(flag, value)
    self.Flags[flag] = value
    for _, window in ipairs(self.Windows) do
        for _, tab in ipairs(window.Tabs) do
            for _, section in ipairs(tab.Sections) do
                for _, element in ipairs(section.Elements) do
                    if element.Flag == flag then
                        element.Value = value
                        if element.Refresh then
                            element:Refresh()
                        end
                    end
                end
            end
        end
        window:FireFlagChanged(flag, value)
    end
    return self
end

function Argon:GetFlags()
    local copy = {}
    for flag, value in pairs(self.Flags) do
        copy[flag] = value
    end
    return copy
end

function Argon:Window(options)
    return Window.new(options)
end

function Argon:SetAccent(color)
    if IsColor(color) then
        self.Theme.Accent = color
        for _, window in ipairs(self.Windows) do
            window:SetAccent(color)
        end
    end
    return self
end

function Argon:GetWindows()
    return self.Windows
end

function Argon:Destroy()
    for _, window in ipairs(self.Windows) do
        window:Destroy()
    end
    self.Windows = {}
    if self.NotificationGui then
        pcall(function()
            self.NotificationGui:Destroy()
        end)
        self.NotificationGui = nil
    end
    return self
end

function Argon:Unload()
    if self.Unloaded then
        return
    end
    self.Unloaded = true

    for _, connection in ipairs(self.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    self.Connections = {}

    pcall(function()
        self:Destroy()
    end)

    for _, instance in ipairs(self.Instances) do
        pcall(function()
            if instance and instance.Parent then
                instance:Destroy()
            end
        end)
    end
    self.Instances = {}
    self.Flags = {}

    if GENV.Argon == self then
        GENV.Argon = nil
    end
end

function Argon:IsLoaded()
    return not self.Unloaded
end

-- ============================================================================
-- scheduler
--
-- A deliberately small sequential task runner for scripts whose setup has
-- ordered, yielding steps (wait for character, load assets, then build UI).
-- Argon never depends on it; it is here because every script re-implements it.
-- ============================================================================
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(options)
    return setmetatable({
        Options = options or {},
        Tasks = {},
        Running = false,
    }, Scheduler)
end

-- fn receives a `nextTask` callback. Call it when the step is done; if you never
-- call it the runner moves on after Options.Timeout seconds (default 10).
function Scheduler:Add(name, fn, immediate)
    if typeof(fn) ~= "function" then
        error("Scheduler:Add expects a function", 2)
    end
    table.insert(self.Tasks, { Name = tostring(name or #self.Tasks + 1), fn = fn })
    if immediate then
        self:Run()
    end
    return self
end

function Scheduler:Clear()
    self.Tasks = {}
    return self
end

function Scheduler:Run()
    if self.Running or #self.Tasks == 0 then
        return self
    end
    self.Running = true
    local timeout = tonumber(self.Options.Timeout) or 10

    task.spawn(function()
        while #self.Tasks > 0 and not Argon.Unloaded do
            local job = table.remove(self.Tasks, 1)
            local finished = false
            local function nextTask()
                finished = true
            end
            local ok, err = pcall(job.fn, nextTask)
            if not ok then
                warn("[Argon] task '" .. job.Name .. "' failed: " .. tostring(err))
                finished = true
            end
            local waited = 0
            while not finished and waited < timeout and not Argon.Unloaded do
                task.wait(0.05)
                waited = waited + 0.05
            end
        end
        self.Running = false
    end)

    return self
end

Argon.Scheduler = {
    Create = function(_, options)
        return Scheduler.new(options)
    end,
}

-- expose to the executor's global environment
GENV.Argon = Argon

-- legacy alias: plenty of pasted scripts check for `ArgonLib` or `Library`
GENV.ArgonLib = Argon
if GENV.Library == nil then
    GENV.Library = Argon
end

return Argon
