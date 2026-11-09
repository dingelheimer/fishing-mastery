-- UI API check (/fm dev ui, dev flag only): confirms that every UI API the statistics screens need
-- exists in the client and works, by drawing into the test window (UiTest.lua). Each check is
-- missing (with the missing names), ok (with a detail), or error (with the error text); nothing
-- raises. Results are printed and kept in FishingMasteryDB.dev.ui for the saved file.
local _, ns = ...

local pcall, type, format, concat, ipairs, tostring, gmatch =
    pcall, type, string.format, table.concat, ipairs, tostring, string.gmatch
local L = ns.L
local UiTest = ns.UiTest
local isSecret = issecretvalue or function()
    return false
end

local UiCheck = {}
ns.UiCheck = UiCheck

UiCheck.TEST_ITEM = 6303 -- Raw Slitherskin Mackerel
UiCheck.TEST_QUALITY = 3 -- rare (blue)
UiCheck.SETTING_VARIABLE = "FishingMastery_UiCheck"

-- Resolves "A.B.C" field by field in env; nil when a part is missing or not a table.
local function resolve(env, path)
    local value = env
    for key in gmatch(path, "[^%.]+") do
        if type(value) ~= "table" then
            return nil
        end
        value = value[key]
    end
    return value
end

local function errorText(err)
    return isSecret(err) and "<secret error>" or tostring(err)
end

-- A test checkbox in the test category; its value lives in FishingMasteryDB.dev.uiSetting.
local function checkbox(ctx, category)
    local S = ctx.env.Settings
    if type(S.RegisterAddOnSetting) ~= "function" or type(S.CreateCheckbox) ~= "function" then
        return "missing RegisterAddOnSetting or CreateCheckbox"
    end
    ctx.dev.uiSetting = type(ctx.dev.uiSetting) == "table" and ctx.dev.uiSetting or {}
    local ok, err = pcall(function()
        local varType = S.VarType and S.VarType.Boolean or "boolean"
        local setting = S.RegisterAddOnSetting(
            category,
            UiCheck.SETTING_VARIABLE,
            "flag",
            ctx.dev.uiSetting,
            varType,
            L.UI_SETTING_LABEL,
            false
        )
        S.CreateCheckbox(category, setting, L.UI_SETTING_TOOLTIP)
    end)
    return ok and "ok" or ("error " .. errorText(err))
end

-- Registers the test category once per session: vertical layout, checkbox, add-on category.
local function trySettings(ctx)
    local S, state = ctx.env.Settings, ctx.state
    if not state.category then
        local category = S.RegisterVerticalLayoutCategory(L.UI_SETTINGS_NAME)
        state.checkbox = checkbox(ctx, category)
        S.RegisterAddOnCategory(category)
        state.category = category
    end
    local category = state.category
    local id = type(category.GetID) == "function" and category:GetID() or nil
    return format("category %s, checkbox %s", tostring(id), state.checkbox)
end

local function tryIcon(ctx)
    local icon = ctx.env.C_Item.GetItemIconByID(UiCheck.TEST_ITEM)
    if icon and type(ctx.window.chart.CreateTexture) == "function" then
        UiTest.DrawIcon(ctx.window, icon)
    end
    return "icon " .. tostring(icon)
end

local function tryQuality(ctx)
    local r, g, b, hex = ctx.env.C_Item.GetItemQualityColor(UiCheck.TEST_QUALITY)
    return format("%s %s %s %s", tostring(r), tostring(g), tostring(b), tostring(hex))
end

-- Adds a test line to item tooltips while a check result exists and the dev flag is set.
function UiCheck.OnTooltip(tooltip, data)
    local result = UiCheck.result
    if not result or not ns.Dev.Enabled(ns.db) or type(data) ~= "table" then
        return
    end
    local id = data.id
    if type(id) ~= "number" or isSecret(id) then
        return
    end
    ns.Tip.Into(tooltip):Line(format(L.UI_TOOLTIP_LINE, id))
    result.tooltipSeen = (result.tooltipSeen or 0) + 1
end

-- Registers the item post-call once per session (post-calls cannot be removed).
local function tryTooltip(ctx)
    local env, state = ctx.env, ctx.state
    if not state.tooltipHooked then
        env.TooltipDataProcessor.AddTooltipPostCall(
            env.Enum.TooltipDataType.Item,
            ns.Guard.Wrap("uicheck:tooltip", UiCheck.OnTooltip)
        )
        state.tooltipHooked = true
    end
    return "registered, hover an item"
end

local function draw(fn)
    return function(ctx)
        return fn(ctx.window)
    end
end

-- name: shown in the report. apis: global paths. methods: frame methods on the chart area.
-- try(ctx): returns a detail; raising makes the check an error. note: shown when missing.
UiCheck.CHECKS = {
    { name = "Frame:CreateLine", methods = { "CreateLine" }, try = draw(UiTest.DrawLine) },
    { name = "Texture bar", methods = { "CreateTexture" }, try = draw(UiTest.DrawBar) },
    {
        name = "Settings API",
        apis = {
            "Settings.RegisterVerticalLayoutCategory",
            "Settings.RegisterAddOnCategory",
            "Settings.OpenToCategory",
        },
        try = trySettings,
    },
    {
        name = "ScrollBox list",
        apis = {
            "ScrollUtil.InitScrollBoxListWithScrollBar",
            "CreateScrollBoxListLinearView",
            "CreateDataProvider",
        },
        try = draw(UiTest.DrawList),
    },
    { name = "C_Item.GetItemIconByID", apis = { "C_Item.GetItemIconByID" }, try = tryIcon },
    {
        name = "C_Item.GetItemQualityColor",
        apis = { "C_Item.GetItemQualityColor" },
        try = tryQuality,
    },
    { name = "ITEM_QUALITY_COLORS", apis = { "ITEM_QUALITY_COLORS" } },
    {
        name = "Item tooltip post-call",
        apis = { "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType.Item" },
        try = tryTooltip,
    },
    {
        name = "Tab templates",
        apis = { "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab" },
        try = draw(UiTest.DrawTabs),
    },
    {
        name = "GetMinimapShape",
        apis = { "GetMinimapShape" },
        try = function(ctx)
            return tostring(ctx.env.GetMinimapShape())
        end,
        note = L.UI_NOTE_MINIMAP_SHAPE,
    },
    {
        name = "Addon compartment",
        apis = { "AddonCompartmentFrame" },
        try = function()
            return L.UI_COMPARTMENT_HINT
        end,
    },
}

function UiCheck.RunOne(check, ctx)
    local missing = {}
    for _, path in ipairs(check.apis or {}) do
        if resolve(ctx.env, path) == nil then
            missing[#missing + 1] = path
        end
    end
    local target = ctx.window.chart
    for _, method in ipairs(check.methods or {}) do
        if type(target[method]) ~= "function" then
            missing[#missing + 1] = "Frame:" .. method
        end
    end
    local entry = { name = check.name }
    if #missing > 0 then
        entry.status, entry.detail, entry.note = "missing", concat(missing, ", "), check.note
        return entry
    end
    if not check.try then
        entry.status, entry.detail = "ok", "exists"
        return entry
    end
    local ok, detail = pcall(check.try, ctx)
    entry.status = ok and "ok" or "error"
    entry.detail = ok and tostring(detail) or errorText(detail)
    return entry
end

-- "Open settings" button: opens the test category and records the outcome.
function UiCheck.OpenSettings(env)
    local category = UiCheck.state and UiCheck.state.category
    local outcome = "no category"
    if category then
        local id = type(category.GetID) == "function" and category:GetID() or category
        local ok, err = pcall(env.Settings.OpenToCategory, id)
        outcome = ok and "ok" or ("error " .. errorText(err))
    end
    if UiCheck.result then
        UiCheck.result.openSettings = outcome
    end
    ns.Print(format(L.UI_OPEN_RESULT, outcome))
end

-- deps: { env, db, charDb, serverTime }. Shows the test window, runs every check, prints the
-- report, and keeps the result in db.dev.ui (replacing the previous run).
function UiCheck.Run(deps)
    local env = deps.env
    local state = UiCheck.state or {}
    UiCheck.state = state
    state.window = state.window
        or UiTest.Create(env, deps.charDb.ui, function()
            UiCheck.OpenSettings(env)
        end)
    state.window.frame:Show()
    local dev = ns.Stress.Dev(deps.db)
    local result = { at = deps.serverTime(), results = {} }
    dev.ui, UiCheck.result = result, result
    local ctx = { env = env, window = state.window, state = state, dev = dev }
    local counts = { ok = 0, missing = 0, error = 0 }
    for _, check in ipairs(UiCheck.CHECKS) do
        local entry = UiCheck.RunOne(check, ctx)
        result.results[#result.results + 1] = entry
        counts[entry.status] = counts[entry.status] + 1
        local line = format(L.UI_LINE, entry.name, L["UI_" .. entry.status], entry.detail)
        ns.Print(entry.note and (line .. " (" .. entry.note .. ")") or line)
    end
    ns.Print(format(L.UI_SUMMARY, counts.ok, counts.missing, counts.error))
    return result
end
