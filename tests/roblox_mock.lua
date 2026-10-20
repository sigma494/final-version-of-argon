--[[ tests/roblox_mock.lua
     A small, honest fake of the Roblox API surface that Argon touches.
     Purpose: run Argon.lua outside Roblox so layout/callback logic is exercised
     in CI instead of "it loads, trust me".

     It is never shipped to users and never loaded by Argon itself.
]]

-- ---------------------------------------------------------------- basic types
local M = {}

local unpack = table.unpack or unpack  -- Lua 5.1 vs 5.2+

local function class(name, extra)
    local c = { __class = name }
    for key, value in pairs(extra or {}) do
        c[key] = value
    end
    c.__index = c
    return c
end

-- Vector2 -----------------------------------------------------------
local Vector2 = {}
Vector2.__index = Vector2
function Vector2.new(x, y)
    return setmetatable({ X = x or 0, Y = y or 0 }, Vector2)
end
Vector2.__sub = function(a, b)
    return Vector2.new(a.X - b.X, a.Y - b.Y)
end
Vector2.__add = function(a, b)
    return Vector2.new(a.X + b.X, a.Y + b.Y)
end
function Vector2.__tostring(v)
    return string.format("Vector2(%s, %s)", v.X, v.Y)
end
M.Vector2 = Vector2

-- Vector3 -----------------------------------------------------------
local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end
M.Vector3 = Vector3

-- UDim / UDim2 ------------------------------------------------------
local UDim = {}
UDim.__index = UDim
function UDim.new(scale, offset)
    return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDim)
end
M.UDim = UDim

local UDim2 = {}
UDim2.__index = UDim2
function UDim2.new(xs, xo, ys, yo)
    return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UDim2)
end
UDim2.__add = function(a, b)
    return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
function UDim2.__tostring(v)
    return string.format("UDim2(%s,%s,%s,%s)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
end
M.UDim2 = UDim2

-- Color3 ------------------------------------------------------------
local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b)
    return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end
function Color3.fromRGB(r, g, b)
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
M.Color3 = Color3

-- sequences ---------------------------------------------------------
local function SequenceKeypoint_new(t, v)
    return { Time = t, Value = v }
end
M.ColorSequence = {
    new = function(a, b)
        local points = {}
        if type(a) == "table" then
            points = a
        else
            points = { SequenceKeypoint_new(0, a), SequenceKeypoint_new(1, b) }
        end
        return { Keypoints = points }
    end,
}
M.NumberSequence = M.ColorSequence
M.NumberSequenceKeypoint = { new = SequenceKeypoint_new }
M.ColorSequenceKeypoint = { new = SequenceKeypoint_new }
M.NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
M.ColorSequenceKeypoint = M.ColorSequenceKeypoint
M.NumberSequenceKeypoint = M.NumberSequenceKeypoint

-- TweenInfo ---------------------------------------------------------
M.TweenInfo = { new = function(time, style, direction) return { Time = time, Style = style, Direction = direction } end }

-- Enum --------------------------------------------------------------
local EnumItem = {}
EnumItem.__index = EnumItem
function EnumItem.__tostring(self)
    return "Enum." .. tostring(self.EnumType) .. "." .. tostring(self.Name)
end
local enumCache = {}
local Enum = setmetatable({}, {
    __index = function(self, enumType)
        local existing = rawget(enumCache, enumType)
        if existing then
            return existing
        end
        local created = setmetatable({}, {
            __index = function(tbl, name)
                local item = setmetatable({ Name = name, EnumType = enumType, Value = 0 }, EnumItem)
                rawset(tbl, name, item)
                return item
            end,
        })
        enumCache[enumType] = created
        return created
    end,
})
-- a couple of enum members whose numeric ordering the library relies on
Enum.ZIndexBehavior.Sibling = setmetatable({ Name = "Sibling", EnumType = "ZIndexBehavior", Value = 1 }, EnumItem)
M.Enum = Enum

-- typeof ------------------------------------------------------------
local types = {
    [Vector2] = "Vector2",
    [Vector3] = "Vector3",
    [UDim2] = "UDim2",
    [UDim] = "UDim",
    [Color3] = "Color3",
    [EnumItem] = "EnumItem",
}
function M.typeof(value)
    local mt = type(value) == "table" and getmetatable(value) or nil
    if mt and types[mt] then
        return types[mt]
    end
    if type(value) == "table" and value.__class then
        return "Instance"
    end
    return type(value)
end

-- ---------------------------------------------------------------- signals
local Signal = {}
Signal.__index = Signal
function Signal.new(name)
    return setmetatable({ Name = name, Handlers = {}, FireCount = 0 }, Signal)
end
function Signal:Connect(fn)
    local connection = { Connected = true }
    table.insert(self.Handlers, { fn = fn, connection = connection })
    function connection:Disconnect()
        self.Connected = false
    end
    function connection:disconnect()
        self:Disconnect()
    end
    return connection
end
function Signal:Fire(...)
    self.FireCount = self.FireCount + 1
    local snapshot = {}
    for i, entry in ipairs(self.Handlers) do
        snapshot[i] = entry
    end
    for _, entry in ipairs(snapshot) do
        if entry.connection.Connected then
            local ok, err = pcall(entry.fn, ...)
            if not ok then
                M.errors[#M.errors + 1] = tostring(err)
            end
        end
    end
end
M.Signal = Signal

-- ---------------------------------------------------------------- instances
M.errors = {}
M.instances = {}
M.createdCount = 0

-- read-only values Roblox always provides; the mock has to invent them
local INSTANCE_DEFAULTS = {
    AbsoluteSize = Vector2.new(0, 0),
    AbsolutePosition = Vector2.new(0, 0),
    AbsoluteContentSize = Vector2.new(0, 0),
    AbsoluteRotation = 0,
    AbsoluteCanvasSize = Vector2.new(0, 0),
    CanvasPosition = Vector3.new(0, 0, 0),
    TextBounds = Vector2.new(0, 0),
    Resolution = Vector2.new(1920, 1080),
    ViewportSize = Vector2.new(1920, 1080),
}

local InstanceClass = {}
InstanceClass.__index = function(self, key)
    local raw = rawget(self, "_props")
    if raw[key] ~= nil then
        return raw[key]
    end
    local signals = rawget(self, "_signals")
    if signals[key] then
        return signals[key]
    end
    local method = InstanceClass[key]
    if method then
        return method
    end
    if INSTANCE_DEFAULTS[key] ~= nil then
        return INSTANCE_DEFAULTS[key]
    end
    -- auto-create a signal on first access so any event name works
    local signal = Signal.new(key)
    signals[key] = signal
    return signal
end

InstanceClass.__newindex = function(self, key, value)
    local props = rawget(self, "_props")
    if key == "Parent" then
        local previous = props.Parent
        if previous and previous._children then
            for i, child in ipairs(previous._children) do
                if child == self then
                    table.remove(previous._children, i)
                    break
                end
            end
        end
        props.Parent = value
        if value and value._children then
            table.insert(value._children, self)
        end
        local signal = rawget(self, "_signals").ChildAdded
        if signal then
            signal:Fire(self)
        end
        return
    end
    local changed = props[key]
    props[key] = value
    local signal = rawget(self, "_signals")[key .. "Changed"]
    if signal and changed ~= value then
        signal:Fire(value, changed)
    end
    local propertyChanged = rawget(self, "_signals")["__property_" .. key]
    if propertyChanged then
        propertyChanged:Fire()
    end
end

local function newInstance(instanceClass, parent)
    local self = setmetatable({
        _props = { Name = instanceClass, ClassName = instanceClass, Visible = true, Parent = nil },
        _children = {},
        _signals = {},
        _destroyed = false,
    }, InstanceClass)
    table.insert(M.instances, self)
    M.createdCount = M.createdCount + 1
    if parent then
        self.Parent = parent
    end
    return self
end

function InstanceClass:GetChildren()
    local copy = {}
    for i, child in ipairs(self._children) do
        copy[i] = child
    end
    return copy
end

function InstanceClass:GetDescendants()
    local out = {}
    local function walk(node)
        for _, child in ipairs(node._children) do
            table.insert(out, child)
            walk(child)
        end
    end
    walk(self)
    return out
end

function InstanceClass:FindFirstChild(name)
    for _, child in ipairs(self._children) do
        if child._props.Name == name then
            return child
        end
    end
    return nil
end

function InstanceClass:FindFirstChildOfClass(className)
    for _, child in ipairs(self._children) do
        if child._props.ClassName == className then
            return child
        end
    end
    return nil
end

function InstanceClass:WaitForChild(name)
    return self:FindFirstChild(name) or newInstance(name, self)
end

function InstanceClass:IsFocused()
    return self._focused == true
end

function InstanceClass:IsA(className)
    return self._props.ClassName == className or className == "Instance"
end

function InstanceClass:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    for _, child in ipairs(self:GetChildren()) do
        child:Destroy()
    end
    self.Parent = nil
    for _, instance in ipairs(M.instances) do
        if instance == self then
            instance._destroyed = true
        end
    end
end

function InstanceClass:GetPropertyChangedSignal(property)
    local key = "__property_" .. property
    local signal = rawget(self, "_signals")[key]
    if not signal then
        signal = Signal.new(property .. "Changed")
        rawget(self, "_signals")[key] = signal
    end
    return signal
end

function InstanceClass:Clone()
    local copy = newInstance(self._props.ClassName)
    for key, value in pairs(self._props) do
        if key ~= "Parent" then
            copy[key] = value
        end
    end
    return copy
end

M.Instance = { new = function(className, parent) return newInstance(className, parent) end }

-- ---------------------------------------------------------------- services
local services = {}
local function service(name, table_)
    local svc = setmetatable(table_ or {}, {
        __index = function(tbl, key)
            local signal = Signal.new(key)
            rawset(tbl, key, signal)
            return signal
        end,
    })
    svc._props = { Name = name, ClassName = name }
    svc._children = {}
    services[name] = svc
    return svc
end

M.services = services
M.UserInputService = service("UserInputService", {
    TouchEnabled = false,
    KeyboardEnabled = true,
    MouseEnabled = true,
    GetMouseLocation = function(self)
        return M.mouseLocation or Vector2.new(400, 300)
    end,
    GetFocusedTextBox = function() return nil end,
})
M.TweenService = service("TweenService", {
    Create = function(self, instance, info, properties)
        return {
            Play = function()
                for key, value in pairs(properties) do
                    instance[key] = value
                end
            end,
        }
    end,
})
M.RunService = service("RunService", {
    Heartbeat = Signal.new("Heartbeat"),
    RenderStepped = Signal.new("RenderStepped"),
})
M.HttpService = service("HttpService", {
    JSONEncode = function(self, value) return M.json.encode(value) end,
    JSONDecode = function(self, value) return M.json.decode(value) end,
})
M.CoreGui = service("CoreGui")
M.Players = service("Players")
M.Workspace = service("Workspace")
M.Workspace.CurrentCamera = setmetatable({
    ClassName = "Camera",
    ViewportSize = Vector2.new(1280, 720),
    _props = {},
    _children = {},
    _signals = {},
}, InstanceClass)

local localPlayer = newInstance("Player")
localPlayer.Name = "LocalPlayer"
localPlayer.DisplayName = "LocalPlayer"
M.Players.LocalPlayer = localPlayer
M.Players.GetPlayers = function() return { localPlayer } end
M.Players.PlayerAdded = Signal.new("PlayerAdded")

M.game = setmetatable({}, {
    __index = function(self, key)
        if key == "GetService" then
            return function(_, name)
                local svc = services[name]
                if not svc then
                    svc = service(name)
                end
                return svc
            end
        end
        if key == "Players" then
            return M.Players
        end
        if key == "PlaceId" then
            return 123456
        end
        if key == "JobId" then
            return "mock-job-id"
        end
        if key == "HttpGet" then
            return function(_, url)
                return "-- fetched " .. tostring(url)
            end
        end
        return nil
    end,
})

-- ---------------------------------------------------------------- task scheduler
local scheduler = { queue = {}, clock = 0 }
M.scheduler = scheduler

local taskLib = {
    delay = function(seconds, fn, ...)
        table.insert(scheduler.queue, { at = scheduler.clock + (seconds or 0), fn = fn, args = { ... } })
    end,
    spawn = function(fn, ...)
        table.insert(scheduler.queue, { at = scheduler.clock, fn = fn, args = { ... } })
    end,
    wait = function(seconds)
        scheduler.clock = scheduler.clock + (seconds or 0)
    end,
    defer = function(fn, ...)
        table.insert(scheduler.queue, { at = scheduler.clock, fn = fn, args = { ... } })
    end,
    cancel = function() end,
}
M.task = taskLib

function M.runScheduler(limit)
    local ran = 0
    while #scheduler.queue > 0 and (not limit or ran < limit) do
        local job = table.remove(scheduler.queue, 1)
        scheduler.clock = math.max(scheduler.clock, job.at)
        local ok, err = pcall(job.fn, unpack(job.args))
        if not ok then
            M.errors[#M.errors + 1] = tostring(err)
        end
        ran = ran + 1
    end
    return ran
end

-- ---------------------------------------------------------------- filesystem
M.files = {}
M.folders = { Argon = true }

function M.readfile(path)
    local content = M.files[path]
    if not content then
        error("file not found: " .. tostring(path), 2)
    end
    return content
end

function M.writefile(path, content)
    M.files[path] = content
end

function M.isfile(path)
    return M.files[path] ~= nil
end

function M.isfolder(path)
    return M.folders[path] == true
end

function M.makefolder(path)
    M.folders[path] = true
end

function M.listfiles(path)
    local out = {}
    for file in pairs(M.files) do
        if string.sub(file, 1, #path) == path then
            table.insert(out, file)
        end
    end
    return out
end

function M.delfile(path)
    M.files[path] = nil
end

-- ---------------------------------------------------------------- json
-- minimal encoder/decoder: enough for configs (string/number/boolean/table)
local json = {}
M.json = json

local function escape(str)
    return '"' .. str:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

function json.encode(value)
    local t = type(value)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "number" then
        return string.format("%.14g", value)
    elseif t == "string" then
        return escape(value)
    elseif t == "table" then
        local isArray = true
        local count = 0
        for key in pairs(value) do
            count = count + 1
            if type(key) ~= "number" then
                isArray = false
            end
        end
        if isArray and count > 0 then
            local parts = {}
            for _, item in ipairs(value) do
                parts[#parts + 1] = json.encode(item)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        elseif count == 0 then
            return "[]"
        end
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = escape(tostring(key)) .. ":" .. json.encode(item)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("cannot encode " .. t)
end

function json.decode(text)
    local position = 1
    local function skip()
        while position <= #text and text:sub(position, position):match("%s") do
            position = position + 1
        end
    end
    local parseValue
    local function parseString()
        position = position + 1
        local out = {}
        while position <= #text do
            local char = text:sub(position, position)
            if char == '"' then
                position = position + 1
                return table.concat(out)
            elseif char == "\\" then
                local nextChar = text:sub(position + 1, position + 1)
                local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if map[nextChar] then
                    out[#out + 1] = map[nextChar]
                    position = position + 2
                elseif nextChar == "u" then
                    local hex = text:sub(position + 2, position + 5)
                    out[#out + 1] = string.char(tonumber(hex, 16) % 256)
                    position = position + 6
                else
                    error("bad escape")
                end
            else
                out[#out + 1] = char
                position = position + 1
            end
        end
        error("unterminated string")
    end

    parseValue = function()
        skip()
        local char = text:sub(position, position)
        if char == "{" then
            position = position + 1
            local object = {}
            skip()
            if text:sub(position, position) == "}" then
                position = position + 1
                return object
            end
            while true do
                skip()
                local key = parseString()
                skip()
                assert(text:sub(position, position) == ":", "expected :")
                position = position + 1
                object[key] = parseValue()
                skip()
                local sep = text:sub(position, position)
                position = position + 1
                if sep == "}" then
                    return object
                end
                assert(sep == ",", "expected , or }")
            end
        elseif char == "[" then
            position = position + 1
            local array = {}
            skip()
            if text:sub(position, position) == "]" then
                position = position + 1
                return array
            end
            while true do
                table.insert(array, parseValue())
                skip()
                local sep = text:sub(position, position)
                position = position + 1
                if sep == "]" then
                    return array
                end
                assert(sep == ",", "expected , or ]")
            end
        elseif char == '"' then
            return parseString()
        elseif text:sub(position, position + 3) == "true" then
            position = position + 4
            return true
        elseif text:sub(position, position + 4) == "false" then
            position = position + 5
            return false
        elseif text:sub(position, position + 3) == "null" then
            position = position + 4
            return nil
        else
            local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
            if not number then
                error("unexpected character at " .. position)
            end
            position = position + #number
            return tonumber(number)
        end
    end

    return parseValue()
end

-- ---------------------------------------------------------------- helpers for tests
function M.find(name)
    for _, instance in ipairs(M.instances) do
        if not instance._destroyed and instance._props.Name == name then
            return instance
        end
    end
    return nil
end

function M.findAll(name)
    local out = {}
    for _, instance in ipairs(M.instances) do
        if not instance._destroyed and instance._props.Name == name then
            table.insert(out, instance)
        end
    end
    return out
end

function M.countLive()
    local n = 0
    for _, instance in ipairs(M.instances) do
        if not instance._destroyed then
            n = n + 1
        end
    end
    return n
end

function M.countClass(className)
    local n = 0
    for _, instance in ipairs(M.instances) do
        if not instance._destroyed and instance._props.ClassName == className then
            n = n + 1
        end
    end
    return n
end

-- a fake UserInputService event payload
function M.input(userInputType, x, y, keyCode)
    return {
        UserInputType = userInputType,
        Position = Vector2.new(x or 0, y or 0),
        KeyCode = keyCode or Enum.KeyCode.Unknown,
    }
end

function M.click(instance)
    instance.MouseButton1Click:Fire()
end

M.Enum = Enum
M.unpack = unpack or table.unpack

return M
