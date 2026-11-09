-- Pure logic: every user setting with its default in one table, the controls of the settings
-- panel (kind, range, getter, setter), and a proxy table the Settings API reads and writes, so a
-- change is validated and reported at once. Account settings live in FishingMasteryDB.settings,
-- positions in FishingMasteryCharDB.ui. No frame or API calls.
local _, ns = ...

local type, ipairs, pairs, floor, min, max, setmetatable =
    type, ipairs, pairs, math.floor, math.min, math.max, setmetatable

local Options = {}
ns.Options = Options

Options.DEFAULTS = {
    hud = { enabled = true, locked = false, scale = 1, style = "full", zoneLine = true },
    summary = { style = "window" },
    minimap = { shown = true },
    tooltip = { shown = true }, -- item tooltip line
    reloadReminder = true,
    thresholds = { countBelow = 10, greyBelow = 30, activeCap = 60 },
    helpers = { doubleClick = false, autoLure = false, loudSplash = false, hideUI = false },
    ui = { minimapAngle = 220 }, -- per character (FishingMasteryCharDB.ui.minimap)
}

local function section(settings, name)
    local value = settings[name]
    if type(value) ~= "table" then
        value = {}
        settings[name] = value
    end
    return value
end

local function threshold(settings, key)
    local value = section(settings, "thresholds")[key]
    return type(value) == "number" and value or Options.DEFAULTS.thresholds[key]
end

local function setThreshold(key)
    return function(settings, value)
        section(settings, "thresholds")[key] = value
    end
end

-- Panel controls in order. checkbox: get/set booleans; slider: numbers from min to max in steps;
-- page: shown on that page of the main window instead of the settings panel.
Options.CONTROLS = {
    {
        key = "hudEnabled",
        kind = "checkbox",
        get = function(s)
            return section(s, "hud").enabled ~= false
        end,
        set = function(s, v)
            section(s, "hud").enabled = v
        end,
    },
    {
        key = "hudLocked",
        kind = "checkbox",
        get = function(s)
            return section(s, "hud").locked == true
        end,
        set = function(s, v)
            section(s, "hud").locked = v
        end,
    },
    {
        key = "hudText",
        kind = "checkbox",
        get = function(s)
            return section(s, "hud").style == "text"
        end,
        set = function(s, v)
            section(s, "hud").style = v and "text" or "full"
        end,
    },
    {
        key = "hudZone",
        kind = "checkbox",
        get = function(s)
            return section(s, "hud").zoneLine ~= false
        end,
        set = function(s, v)
            section(s, "hud").zoneLine = v
        end,
    },
    {
        key = "hudScale",
        kind = "slider",
        min = 0.5,
        max = 2,
        step = 0.05,
        get = function(s)
            local scale = section(s, "hud").scale
            return type(scale) == "number" and scale or Options.DEFAULTS.hud.scale
        end,
        set = function(s, v)
            section(s, "hud").scale = v
        end,
    },
    {
        key = "summaryChat",
        kind = "checkbox",
        get = function(s)
            return section(s, "summary").style == "chat"
        end,
        set = function(s, v)
            section(s, "summary").style = v and "chat" or "window"
        end,
    },
    {
        key = "minimapShown",
        kind = "checkbox",
        get = function(s)
            return section(s, "minimap").shown ~= false
        end,
        set = function(s, v)
            section(s, "minimap").shown = v
        end,
    },
    {
        key = "tooltipLine",
        kind = "checkbox",
        get = function(s)
            return section(s, "tooltip").shown ~= false
        end,
        set = function(s, v)
            section(s, "tooltip").shown = v
        end,
    },
    {
        key = "reloadReminder",
        kind = "checkbox",
        get = function(s)
            return s.reloadReminder ~= false
        end,
        set = function(s, v)
            s.reloadReminder = v
        end,
    },
    {
        key = "countBelow",
        kind = "slider",
        min = 5,
        max = 30,
        step = 1,
        get = function(s)
            return threshold(s, "countBelow")
        end,
        set = setThreshold("countBelow"),
    },
    {
        key = "greyBelow",
        kind = "slider",
        min = 10,
        max = 100,
        step = 5,
        get = function(s)
            return threshold(s, "greyBelow")
        end,
        set = setThreshold("greyBelow"),
    },
    {
        key = "activeCap",
        kind = "slider",
        min = 30,
        max = 120,
        step = 5,
        get = function(s)
            return threshold(s, "activeCap")
        end,
        set = setThreshold("activeCap"),
    },
    -- Helpers (module 5): shown on the Helpers page of the main window (page = "helpers"), not
    -- in the game's settings panel (Story 9.6); the keys stay.
    {
        key = "doubleClick",
        kind = "checkbox",
        page = "helpers",
        get = function(s)
            return section(s, "helpers").doubleClick == true
        end,
        set = function(s, v)
            section(s, "helpers").doubleClick = v
        end,
    },
    {
        key = "autoLure",
        kind = "checkbox",
        page = "helpers",
        get = function(s)
            return section(s, "helpers").autoLure == true
        end,
        set = function(s, v)
            section(s, "helpers").autoLure = v
        end,
    },
    {
        key = "loudSplash",
        kind = "checkbox",
        page = "helpers",
        get = function(s)
            return section(s, "helpers").loudSplash == true
        end,
        set = function(s, v)
            section(s, "helpers").loudSplash = v
        end,
    },
    {
        key = "hideUI",
        kind = "checkbox",
        page = "helpers",
        get = function(s)
            return section(s, "helpers").hideUI == true
        end,
        set = function(s, v)
            section(s, "helpers").hideUI = v
        end,
    },
}

-- Value controls by key (section headings hold no value).
Options.BY_KEY = {}
for _, control in ipairs(Options.CONTROLS) do
    if control.kind ~= "header" then
        Options.BY_KEY[control.key] = control
    end
end

-- The default value of a control.
function Options.Default(key)
    local defaults = {}
    for name, value in pairs(Options.DEFAULTS) do
        defaults[name] = type(value) == "table" and setmetatable({}, { __index = value }) or value
    end
    return Options.BY_KEY[key].get(defaults)
end

function Options.Get(settings, key)
    return Options.BY_KEY[key].get(settings)
end

-- A slider value inside its range, on its step.
function Options.Clamp(control, value)
    value = min(control.max, max(control.min, value))
    local steps = floor((value - control.min) / control.step + 0.5)
    return min(control.max, control.min + steps * control.step)
end

-- Sets a control's value; a value of the wrong type is ignored. Returns true when it changed.
function Options.Set(settings, key, value)
    local control = Options.BY_KEY[key]
    if not control then
        return false
    end
    if control.kind == "checkbox" then
        if type(value) ~= "boolean" then
            return false
        end
    elseif type(value) ~= "number" then
        return false
    else
        value = Options.Clamp(control, value)
    end
    if control.get(settings) == value then
        return false
    end
    control.set(settings, value)
    return true
end

-- A table whose fields are the control keys: reads give the current values, writes go through
-- Options.Set and call onChange(key) when the value changed.
function Options.Proxy(settings, onChange)
    return setmetatable({}, {
        __index = function(_, key)
            if Options.BY_KEY[key] then
                return Options.Get(settings, key)
            end
            return nil
        end,
        __newindex = function(_, key, value)
            if Options.Set(settings, key, value) and onChange then
                onChange(key)
            end
        end,
    })
end
