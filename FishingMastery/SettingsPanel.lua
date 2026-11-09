-- The settings panel (Settings API, vertical layout, confirmed on live in Story 3.1): one control
-- per Options.CONTROLS entry, bound through RegisterAddOnSetting to an Options proxy, so every
-- change is validated and applied at once; a "header" entry is a section heading (listed as
-- missing without CreateSettingsListSectionHeaderInitializer). Checkboxes are confirmed on live; a
-- slider is added only when CreateSlider and CreateSliderOptions exist, else the control is listed
-- as missing
-- (/fm settings prints it). Each control is created protected; one failing control does not stop
-- the others. Also /fm settings and /fm minimap.
local _, ns = ...

local setmetatable, type, ipairs, pcall, format, tostring, floor =
    setmetatable, type, ipairs, pcall, string.format, tostring, math.floor
local L, Options = ns.L, ns.Options

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel
ns.SettingsPanel = SettingsPanel

SettingsPanel.VARIABLE = "FishingMastery_%s" -- setting IDs (strings, not globals)

-- Slider label texts per control.
local FORMATS = {
    hudScale = function(value)
        return format("%d %%", floor(value * 100 + 0.5))
    end,
    activeCap = function(value)
        return format(L.OPT_SECONDS, value)
    end,
}

local function sliderOptions(env, S, control)
    local options = S.CreateSliderOptions(control.min, control.max, control.step)
    local mixin = env.MinimalSliderWithSteppersMixin
    local labels = type(mixin) == "table" and type(mixin.Label) == "table" and mixin.Label
    if type(options.SetLabelFormatter) == "function" and labels and labels.Right then
        options:SetLabelFormatter(labels.Right, FORMATS[control.key] or tostring)
    end
    return options
end

-- A section heading with its note as tooltip (CreateSettingsListSectionHeaderInitializer).
local function addHeader(self, control)
    local make = self.env.CreateSettingsListSectionHeaderInitializer
    local layout = self.layout
    if
        type(make) ~= "function"
        or type(layout) ~= "table"
        or type(layout.AddInitializer) ~= "function"
    then
        return "missing"
    end
    layout:AddInitializer(make(L["OPT_" .. control.key], L["OPT_TIP_" .. control.key]))
    return "ok"
end

local function addControl(self, S, control)
    if control.kind == "header" then
        return addHeader(self, control)
    end
    if control.kind == "slider" then
        if type(S.CreateSlider) ~= "function" or type(S.CreateSliderOptions) ~= "function" then
            return "missing"
        end
    elseif type(S.CreateCheckbox) ~= "function" then
        return "missing"
    end
    local varTypes = type(S.VarType) == "table" and S.VarType or {}
    local isBox = control.kind == "checkbox"
    local setting = S.RegisterAddOnSetting(
        self.category,
        format(SettingsPanel.VARIABLE, control.key),
        control.key,
        self.proxy,
        isBox and (varTypes.Boolean or "boolean") or (varTypes.Number or "number"),
        L["OPT_" .. control.key],
        Options.Default(control.key)
    )
    local tooltip = L["OPT_TIP_" .. control.key]
    if isBox then
        S.CreateCheckbox(self.category, setting, tooltip)
    else
        S.CreateSlider(self.category, setting, sliderOptions(self.env, S, control), tooltip)
    end
    return "ok"
end

-- deps: { env, settings (db.settings), onChange(key) }. Registers the category once; results per
-- control key ("ok", "missing", or "error ..."); controls of a main window page (control.page) are
-- left out. Without the Settings API, panel.category is nil.
function SettingsPanel.Start(deps)
    local self = setmetatable({
        env = deps.env,
        settings = deps.settings,
        results = {},
        proxy = Options.Proxy(deps.settings, deps.onChange),
    }, SettingsPanel)
    local S = deps.env.Settings
    if
        type(S) ~= "table"
        or type(S.RegisterVerticalLayoutCategory) ~= "function"
        or type(S.RegisterAddOnSetting) ~= "function"
    then
        return self
    end
    self.category, self.layout = S.RegisterVerticalLayoutCategory(L.PREFIX)
    for _, control in ipairs(Options.CONTROLS) do
        if not control.page then
            local ok, result = pcall(addControl, self, S, control)
            self.results[control.key] = ok and result or ("error " .. tostring(result))
        end
    end
    S.RegisterAddOnCategory(self.category)
    return self
end

-- Controls that could not be created: { "key: status" }.
function SettingsPanel:Problems()
    local list = {}
    for _, control in ipairs(Options.CONTROLS) do
        local result = self.results[control.key]
        if result and result ~= "ok" then
            list[#list + 1] = control.key .. ": " .. result
        end
    end
    return list
end

-- Opens the panel. Returns false without a category or when opening failed.
function SettingsPanel:Open()
    local category = self.category
    if not category then
        return false
    end
    local id = type(category.GetID) == "function" and category:GetID() or category
    return (pcall(self.env.Settings.OpenToCategory, id))
end

ns.Commands.Register("settings", L.CMD_SETTINGS, function()
    local panel = ns.settingsPanel
    if not (panel and panel:Open()) then
        ns.Print(L.OPT_UNAVAILABLE)
        return
    end
    for _, problem in ipairs(panel:Problems()) do
        ns.Print(format(L.OPT_PROBLEM, problem))
    end
end)

ns.Commands.Register("minimap", L.CMD_MINIMAP, function(rest)
    local value = (rest or ""):lower()
    if not (ns.db and (value == "show" or value == "hide")) then
        ns.Print(L.MINIMAP_USAGE)
        return
    end
    Options.Set(ns.db.settings, "minimapShown", value == "show")
    if ns.minimap then
        ns.minimap:Update()
    end
    ns.Print(value == "show" and L.MINIMAP_SHOWN or L.MINIMAP_HIDDEN)
end)
