-- Pure logic: the Fish table of the Statistics page from a StatsModel view (Draft 2: six columns,
-- item icon, quality color, season or night tag; hour and dates in the row tooltip), and the
-- item helpers the other tables share. Each row is { key, cells, grey = { [column] = true },
-- icons, colors, tags, tip(tip) } (StatsList); small samples are grey with "~" by the Stats
-- display rule and the 95 % ranges live in the tooltips. Item and zone names come in through
-- input functions. No frame or API calls.
local _, ns = ...

local format, floor, type, pairs, ipairs, sort, HUGE =
    string.format, math.floor, type, pairs, ipairs, table.sort, math.huge
local L, Stats, Style, RowTip = ns.L, ns.Stats, ns.Style, ns.RowTip

local StatsTables = {}
ns.StatsTables = StatsTables

StatsTables.QUALITIES = { 0, 1, 2, 3, 4 } -- quality filter steps after "all"
StatsTables.ICON = 14

-- Column keys, labels, widths, and alignment (the list widget draws them).
StatsTables.FISH_COLUMNS = {
    { key = "name", label = L.STATS_COL_FISH, width = 250, icon = true, tags = true },
    { key = "n", label = L.STATS_COL_CAUGHT, width = 70, right = true },
    { key = "share", label = L.STATS_COL_SHARE, width = 70, right = true },
    { key = "expected", label = L.STATS_COL_EVERY, width = 100, right = true },
    { key = "dry", label = L.STATS_COL_DRY, width = 80, right = true },
    { key = "best", label = L.STATS_COL_BEST_WATER, width = 200 },
}

-- Tag of a fish from the journal data: { text, kind } for a season (summer, winter) or a time of
-- day (night, day), or nil.
function StatsTables.Tag(season, time)
    if type(season) == "table" and season.season then
        return { text = L["TAG_" .. season.season], kind = "season" }
    end
    return time and { text = L["TAG_" .. time], kind = "night" } or nil
end

-- Item name with icon and quality color; "Item <id>" while the name is loading.
function StatsTables.ItemText(id, info)
    local name = info.name or format(L.HUD_ITEM_LOADING, id)
    if info.hex then
        name = format("|c%s%s|r", info.hex, name)
    end
    if info.icon then
        name = format("|T%d:%d:%d|t %s", info.icon, StatsTables.ICON, StatsTables.ICON, name)
    end
    return name
end

local function hourOf(hours, offset)
    local best, most = nil, 0
    for hour, n in pairs(hours or {}) do
        if n > most or (n == most and best and hour < best) then
            best, most = hour, n
        end
    end
    return best and (best + (offset or 0)) % 24 or nil
end

local function fishRow(id, item, view, input)
    local t = input.thresholds or Stats.DEFAULTS
    local info = input.info(id) or {}
    local catches = Stats.Count(view.outcomes, "catch")
    local perCast = Stats.Proportion(item.n, Stats.Fair(view.outcomes), t)
    local row = {
        key = id,
        id = id,
        order = id,
        info = info,
        name = info.name,
        quality = info.quality,
        n = item.n,
        qty = item.qty,
        share = Stats.ItemShare(item.n, catches, t),
        perCast = perCast,
        expected = Stats.ExpectedCasts(perCast),
        best = item.best,
        bestName = item.best and input.mapName(item.best) or nil,
        hour = hourOf(item.hours, input.hourOffset),
        first = item.first,
        last = item.last,
    }
    if view.fair and type(item.fair) == "number" then
        row.dry = view.fair - item.fair
    end
    return row
end

local function finite(x)
    return type(x) == "number" and x < HUGE
end

-- "7.9" below 10 casts, else a whole number with separators.
local function casts(x)
    if x < 10 then
        return format("%.1f", x)
    end
    return Style.Number(floor(x + 0.5))
end

-- A grey "~" value for small samples, "-" when only counts are shown.
local function approx(text, display)
    if display == "count" then
        return "-"
    end
    return display == "few" and Style.Approx(text) or text
end

local function everyText(row)
    local mean = row.expected and row.expected.mean
    if not finite(mean) then
        return "-"
    end
    return approx(format(L.FISH_CASTS, casts(mean)), row.perCast.display)
end

local function everyPair(tip, row)
    local expected = row.expected
    if not finite(expected.mean) or row.perCast.display == "count" then
        return
    end
    local high = finite(expected.high) and casts(expected.high) or "-"
    local value = format(L.FISH_CASTS, casts(expected.mean))
    value = Style.Range(value, casts(expected.low), high)
    tip:Pair(L.FISH_TIP_EVERY, value, row.perCast.display == "few" and Style.GREY or nil)
end

local function fishTip(row, input)
    return function(tip)
        RowTip.Item(tip, row.id, row.info)
        local caught = Style.Number(row.n)
        if row.qty and row.qty ~= row.n then
            caught = format(L.FISH_TIP_QTY, caught, Style.Number(row.qty))
        end
        tip:Pair(L.FISH_TIP_CAUGHT, caught)
        RowTip.Rate(tip, L.FISH_TIP_SHARE, row.share)
        everyPair(tip, row)
        if row.dry then
            tip:Pair(L.FISH_TIP_DRY, format(L.FISH_CASTS, Style.Number(row.dry)))
        end
        if row.hour then
            tip:Pair(L.FISH_TIP_HOUR, format(L.FISH_HOUR_VALUE, row.hour))
        end
        if row.first then
            local dates = input.formatDate(row.first) .. " / " .. input.formatDate(row.last)
            tip:Pair(L.FISH_TIP_DATES, dates)
        end
        RowTip.Details(tip, { "range", L.FISH_D_EVERY, row.share.display ~= "full" and "grey" })
    end
end

local function fishCells(row, input)
    local info = row.info
    row.cells = {
        info.name or format(L.HUD_ITEM_LOADING, row.id),
        Style.Number(row.n),
        approx(RowTip.Percent(row.share), row.share.display),
        everyText(row),
        row.dry and Style.Number(row.dry) or "-",
        row.bestName or (row.best and format(L.SUMMARY_ZONE_ID, row.best)) or "-",
    }
    row.icons = { info.icon }
    row.colors = { Style.FromHex(info.hex) }
    row.tags = { input.tag and input.tag(row.id) or nil }
    row.grey = { [3] = row.share.display ~= "full", [4] = row.perCast.display ~= "full" }
    row.tip = fishTip(row, input)
    return row
end

-- Sort values per Fish column; nil sorts last.
local SORT_VALUE = {
    name = function(row)
        return row.name
    end,
    share = function(row)
        return row.share.p
    end,
    best = function(row)
        return row.bestName
    end,
    expected = function(row)
        return row.expected and row.expected.mean
    end,
}

-- Sorts rows by value(row) (nil last in both orders); ties keep row.order (a number).
function StatsTables.Sort(rows, value, descending)
    sort(rows, function(a, b)
        local va, vb = value(a), value(b)
        if va == nil or vb == nil or va == vb then
            if (va == nil) ~= (vb == nil) then
                return vb == nil
            end
            return a.order < b.order
        end
        if descending then
            return va > vb
        end
        return va < vb
    end)
    return rows
end

-- Sorts Fish rows by a column key; ties by item ID.
function StatsTables.SortFish(rows, key, descending)
    local value = SORT_VALUE[key] or function(row)
        return row[key]
    end
    return StatsTables.Sort(rows, value, descending)
end

-- input: { info(id) -> { name, icon, quality, hex }, mapName(map), formatDate(t), hourOffset
-- (realm hour minus UTC hour), thresholds, quality (filter; nil = all), tag(id) -> { text, kind }
-- or nil (season and night fish), sort = { key, descending } }. Returns the rows of the Fish
-- table.
function StatsTables.Fish(view, input)
    local rows = {}
    for id, item in pairs(view.items) do
        local row = fishRow(id, item, view, input)
        if input.quality == nil or row.quality == input.quality then
            rows[#rows + 1] = fishCells(row, input)
        end
    end
    local order = input.sort or { key = "n", descending = true }
    return StatsTables.SortFish(rows, order.key, order.descending)
end

-- Kinds and catches of Fish rows (the line next to the quality filter).
function StatsTables.Kinds(rows)
    local n = 0
    for _, row in ipairs(rows) do
        n = n + (row.n or 0)
    end
    return format(L.FISH_KINDS, Style.Number(#rows), Style.Number(n))
end
