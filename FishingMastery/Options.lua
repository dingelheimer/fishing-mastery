-- Pure logic: every user setting with its default in one table, the HUD layout reader, and the
-- access to the controls (OptionsControls.lua: kind, range, getter, setter, page): defaults,
-- reads, and validated writes. Account settings
-- live in FishingMasteryDB.settings, positions in FishingMasteryCharDB.ui. No frame or API calls.
local _, ns = ...

local type, ipairs, pairs, floor, min, max, setmetatable, tonumber, format =
    type, ipairs, pairs, math.floor, math.min, math.max, setmetatable, tonumber, string.format

local Options = {}
ns.Options = Options

Options.DEFAULTS = {
    hud = {
        enabled = true,
        locked = false,
        scale = 1,
        layout = "card",
        opacity = 1,
        zoneLine = true,
    },
    summary = { style = "window" },
    minimap = { shown = true },
    tooltip = { shown = true }, -- item tooltip line
    reloadReminder = true,
    thresholds = { countBelow = 10, greyBelow = 30, activeCap = 60 },
    helpers = { doubleClick = false, autoLure = false, loudSplash = false, hideUI = false },
    ui = { minimapAngle = 220 }, -- per character (FishingMasteryCharDB.ui.minimap)
}

-- HUD layouts (Epic 9): the card of Draft 5 and the one compact line.
Options.LAYOUTS = { "card", "compact" }
local LAYOUT = { card = true, compact = true }
-- Layouts of the HUD style before Epic 9 (full: the HUD of lines, text: one line).
Options.OLD_STYLES = { full = "card", text = "compact" }

-- The HUD layout of settings.hud; a layout saved before Epic 9 (style) is read as its new name.
function Options.Layout(hud)
    if LAYOUT[hud.layout] then
        return hud.layout
    end
    return Options.OLD_STYLES[hud.style] or Options.DEFAULTS.hud.layout
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
    -- Four decimals: steps like 0.05 add up to values such as 0.6000000000000001.
    return tonumber(format("%.4f", min(control.max, control.min + steps * control.step)))
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
    elseif control.kind == "choice" then
        local known = false
        for _, choice in ipairs(control.values) do
            known = known or choice == value
        end
        if not known then
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
