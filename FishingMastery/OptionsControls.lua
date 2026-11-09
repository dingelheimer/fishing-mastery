-- Pure logic: the controls of the settings in page order (Options.lua reads and writes through
-- them): kind (checkbox, slider, choice), range, getter and setter on the saved shapes, and the
-- main window page that shows them. Loaded after Options.lua.
local _, ns = ...

local type, ipairs = type, ipairs
local Options = ns.Options

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

-- Controls in order. checkbox: get/set booleans; slider: numbers from min to max in steps;
-- choice: one of values; page: the main window page that shows it (settings or helpers).
Options.CONTROLS = {
    {
        key = "hudEnabled",
        page = "settings",
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
        page = "settings",
        kind = "checkbox",
        get = function(s)
            return section(s, "hud").locked == true
        end,
        set = function(s, v)
            section(s, "hud").locked = v
        end,
    },
    {
        key = "hudLayout",
        page = "settings",
        kind = "choice",
        values = Options.LAYOUTS,
        get = function(s)
            return Options.Layout(section(s, "hud"))
        end,
        set = function(s, v)
            local hud = section(s, "hud")
            hud.layout, hud.style = v, nil
        end,
    },
    {
        key = "hudZone",
        page = "settings",
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
        page = "settings",
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
        key = "hudOpacity",
        page = "settings",
        kind = "slider",
        min = 0.3,
        max = 1,
        step = 0.05,
        get = function(s)
            local opacity = section(s, "hud").opacity
            return type(opacity) == "number" and opacity or Options.DEFAULTS.hud.opacity
        end,
        set = function(s, v)
            section(s, "hud").opacity = v
        end,
    },
    {
        key = "summaryChat",
        page = "settings",
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
        page = "settings",
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
        page = "settings",
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
        page = "settings",
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
        page = "settings",
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
        page = "settings",
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
        page = "settings",
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
