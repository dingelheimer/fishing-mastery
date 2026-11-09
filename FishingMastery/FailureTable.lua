-- Pure logic: the Failures tab from a StatsView view: one row per outcome with its count and rates
-- (of fair casts; getaways and catches also of hooked casts), the getaway rate by band of
-- effective skill with Wilson ranges (all zones together), or by band of skill above the water's
-- base level with the Classic model as a mark (waters with zone data only), and early clicks by
-- time band (click times saved since Story 3.4). Cancels, invalid targets, and unknown attempts
-- are counts only. No frame or API calls.
local _, ns = ...

local format, ipairs, pairs, sort, floor = string.format, ipairs, pairs, table.sort, math.floor
local L, Stats, HudModel, ChartModel, Getaway =
    ns.L, ns.Stats, ns.HudModel, ns.ChartModel, ns.Getaway

local Style, RowTip = ns.Style, ns.RowTip
local FailureTable = {}
ns.FailureTable = FailureTable

FailureTable.OUTCOMES =
    { "catch", "getaway", "early_click", "timeout", "cancel", "invalid_target", "unknown" }
FailureTable.CLICK_BIN = 10 -- tenths: 1-second bands
FailureTable.CLICK_LIMIT = 300 -- tenths: a fishing channel lasts at most ~30 s

FailureTable.COLUMNS = {
    { key = "outcome", label = L.STATS_COL_OUTCOME, width = 260 },
    { key = "count", label = L.STATS_COL_COUNT, width = 80, right = true },
    { key = "fair", label = L.STATS_COL_OF_FAIR, width = 120, right = true },
    { key = "hooked", label = L.STATS_COL_OF_HOOKED, width = 120, right = true },
}

local function pct(x)
    return floor(x * 100 + 0.5)
end

-- The tooltip of a getaway band as draw(tip): the band, the getaway rate with its range, the
-- hooked casts; with a model the Classic value, below-base and differs lines, and the relative
-- band explanation behind Shift.
local function bandTip(title, rate, model, from)
    return function(tip)
        tip:Title(title)
        RowTip.Rate(tip, L.STATS_GETAWAYS, rate)
        tip:Pair(L.STATS_TIP_HOOKED, Style.Number(rate.n))
        if not model then
            RowTip.Details(tip, { "range" })
            return
        end
        tip:Pair(L.STATS_TIP_MODEL, format("%d %%", pct(model)))
        if from < 0 then
            tip:Line(L.STATS_TIP_BELOW_BASE, Style.GREY)
        end
        if Getaway.Compare(rate, model).differs then
            tip:Line(L.STATS_TIP_DIFFERS, Style.ORANGE)
        end
        RowTip.Details(tip, { "range", L.STATS_D_REL_BAND, L.HTIP_D_CLASSIC })
    end
end

-- Rows of the outcome table.
function FailureTable.Rows(view, t)
    local outcomes, rows = view.outcomes, {}
    local fair, hooked = Stats.Fair(outcomes), Stats.Hooked(outcomes)
    for i, outcome in ipairs(FailureTable.OUTCOMES) do
        local count = Stats.Count(outcomes, outcome)
        local row = { key = outcome, order = i, grey = {} }
        local cells = { L["OUTCOME_" .. outcome], Style.Number(count), "-", "-" }
        local ofFair, ofHooked
        if not Stats.UNFAIR[outcome] then
            ofFair = Stats.Proportion(count, fair, t)
            cells[3], row.grey[3] = HudModel.Percent(ofFair), ofFair.display ~= "full"
        end
        if outcome == "catch" or outcome == "getaway" then
            ofHooked = Stats.Proportion(count, hooked, t)
            cells[4], row.grey[4] = HudModel.Percent(ofHooked), ofHooked.display ~= "full"
        end
        row.cells = cells
        row.tip = function(tip)
            tip:Title(L["OUTCOME_" .. outcome])
            tip:Pair(L.STATS_COL_COUNT, Style.Number(count))
            if ofFair then
                RowTip.Rate(tip, L.STATS_OF_FAIR, ofFair)
            else
                tip:Line(L.STATS_TIP_COUNT_ONLY, Style.GREY)
            end
            if ofHooked then
                RowTip.Rate(tip, L.STATS_OF_HOOKED, ofHooked)
            end
            RowTip.Details(tip, { "range", "fair", ofHooked and "hooked" })
        end
        rows[#rows + 1] = row
    end
    return rows
end

-- Getaway rate per band of effective skill (rank + modifier), or nil without hooked casts.
function FailureTable.SkillChart(view, t)
    local bands = {}
    for band, entry in pairs(view.skills) do
        if (entry.hooked or 0) > 0 then
            bands[#bands + 1] = band
        end
    end
    if #bands == 0 then
        return nil
    end
    sort(bands)
    local size = ns.Totals.SKILL_BAND
    local bars = {}
    for i, band in ipairs(bands) do
        local entry = view.skills[band]
        local rate = Stats.Proportion(entry.getaways or 0, entry.hooked, t)
        local label = format("%d-%d", band, band + size - 1)
        bars[i] = {
            label = format("%d", band),
            value = rate.p,
            low = rate.low,
            high = rate.high,
            text = HudModel.Percent(rate),
            grey = rate.display ~= "full",
            tip = bandTip(format(L.STATS_TIP_BAND, label), rate),
        }
    end
    return ChartModel.Build(bars, true)
end

-- Getaway rate per band of effective skill minus the water's base, with the Classic model of
-- the band as a mark: chart (or nil without hooked casts in waters with a base), and the hooked
-- casts left out (no zone data or no base). areas: the Area resolver.
function FailureTable.RelativeChart(view, areas, t)
    local byArea, unknown = Getaway.ByArea(view, areas)
    local relative, noBase = Getaway.Relative(byArea, areas)
    local bands = {}
    for band, entry in pairs(relative) do
        if entry.hooked > 0 then
            bands[#bands + 1] = band
        end
    end
    local left = unknown + noBase
    if #bands == 0 then
        return nil, left
    end
    sort(bands)
    local size = ns.Totals.SKILL_BAND
    local bars = {}
    for i, band in ipairs(bands) do
        local entry = relative[band]
        local rate = Stats.Proportion(entry.getaways, entry.hooked, t)
        local model = Getaway.BandModel(band, size, 0)
        local title = format(L.STATS_TIP_REL_BAND, format("%+d to %+d", band, band + size - 1))
        bars[i] = {
            label = format("%+d", band),
            value = rate.p,
            low = rate.low,
            high = rate.high,
            mark = model,
            text = HudModel.Percent(rate),
            grey = rate.display ~= "full",
            tip = bandTip(title, rate, model, band),
        }
    end
    return ChartModel.Build(bars, true), left
end

-- Early clicks per 1-second band of the click time, or nil when no early click has a time.
function FailureTable.ClickChart(view)
    local clicks, total = {}, 0
    for _, lures in pairs(view.zones) do
        for _, group in pairs(lures) do
            for tenths, n in pairs(group.clicks or {}) do
                clicks[tenths] = (clicks[tenths] or 0) + n
                total = total + n
            end
        end
    end
    if total == 0 then
        return nil
    end
    local bins = ChartModel.Bins(clicks, FailureTable.CLICK_BIN, FailureTable.CLICK_LIMIT)
    local bars = {}
    for i, n in ipairs(bins) do
        local from = (i - 1) * FailureTable.CLICK_BIN / 10
        bars[i] = {
            label = format("%d", from),
            value = n,
            text = format("%d", n),
            tip = function(tip)
                tip:Title(format(L.STATS_TIP_CLICKS_AT, from, from + 1))
                tip:Pair(L.STATS_TIP_CLICKS, format(L.TIP_OF, Style.Number(n), Style.Number(total)))
            end,
        }
    end
    local chart = ChartModel.Build(bars, false)
    chart.total = total
    return chart
end
