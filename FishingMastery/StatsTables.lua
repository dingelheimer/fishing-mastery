-- Pure logic: the Fish table of the stats window from a StatsModel view, and the item helpers the
-- other tables share. Each row is
-- { key, cells = { text per column }, grey = { [column] = true }, tooltip = { lines } }; small
-- samples are greyed by the Stats display rule and the 95 % ranges live in the tooltips. Item
-- and zone names come in through input functions. No frame or API calls.
local _, ns = ...

local format, floor, type, pairs, sort, HUGE =
    string.format, math.floor, type, pairs, table.sort, math.huge
local L, Stats, HudModel = ns.L, ns.Stats, ns.HudModel

local StatsTables = {}
ns.StatsTables = StatsTables

StatsTables.RARE_QUALITY = 2 -- uncommon and better get a dry streak and expected casts
StatsTables.QUALITIES = { 0, 1, 2, 3, 4 } -- quality filter steps after "all"
StatsTables.ICON = 14

-- Column keys, labels, widths, and alignment (the list widget draws them).
StatsTables.FISH_COLUMNS = {
    { key = "name", label = L.STATS_COL_FISH, width = 170 },
    { key = "n", label = L.STATS_COL_CAUGHT, width = 50, right = true },
    { key = "share", label = L.STATS_COL_SHARE, width = 55, right = true },
    { key = "best", label = L.STATS_COL_BEST_ZONE, width = 110 },
    { key = "hour", label = L.STATS_COL_HOUR, width = 45, right = true },
    { key = "first", label = L.STATS_COL_FIRST, width = 75, right = true },
    { key = "last", label = L.STATS_COL_LAST, width = 75, right = true },
    { key = "dry", label = L.STATS_COL_DRY, width = 65, right = true },
    { key = "expected", label = L.STATS_COL_EXPECTED, width = 70, right = true },
}
local function pct(x)
    return floor(x * 100 + 0.5)
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

-- Tooltip line of an item share: the range, or the counts while the sample is small.
function StatsTables.ShareLine(share)
    if share.display == "count" or not share.low then
        return format(L.STATS_TIP_SHARE_FEW, share.k, share.n)
    end
    return format(
        L.STATS_TIP_SHARE,
        HudModel.Percent(share),
        pct(share.low),
        pct(share.high),
        share.k,
        share.n
    )
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
    local row = {
        key = id,
        id = id,
        order = id,
        name = info.name,
        quality = info.quality,
        n = item.n,
        qty = item.qty,
        share = Stats.ItemShare(item.n, catches, t),
        best = item.best,
        bestName = item.best and input.mapName(item.best) or nil,
        hour = hourOf(item.hours, input.hourOffset),
        first = item.first,
        last = item.last,
    }
    if (info.quality or -1) >= StatsTables.RARE_QUALITY then
        local perCast = Stats.Proportion(item.n, Stats.Fair(view.outcomes), t)
        row.perCast = perCast
        row.expected = Stats.ExpectedCasts(perCast)
        if view.fair and type(item.fair) == "number" then
            row.dry = view.fair - item.fair
        end
    end
    row.text = StatsTables.ItemText(id, info)
    return row
end

local function count(value)
    return type(value) == "number" and format("%d", value) or "-"
end

local function finite(x)
    return type(x) == "number" and x < HUGE
end

local function fishCells(row, input)
    local date = input.formatDate
    local expected = row.expected
            and finite(row.expected.mean)
            and format("%d", floor(row.expected.mean + 0.5))
        or "-"
    row.cells = {
        row.text,
        count(row.n),
        HudModel.Percent(row.share),
        row.bestName or (row.best and format(L.SUMMARY_ZONE_ID, row.best)) or "-",
        row.hour and format(L.STATS_HOUR, row.hour) or "-",
        row.first and date(row.first) or "-",
        row.last and date(row.last) or "-",
        count(row.dry),
        expected,
    }
    row.grey = { [3] = row.share.display ~= "full" }
    row.grey[9] = row.perCast ~= nil and row.perCast.display ~= "full"
    local tip =
        { row.text, format(L.STATS_TIP_CAUGHT, row.n, row.qty), StatsTables.ShareLine(row.share) }
    if row.hour then
        tip[#tip + 1] = format(L.STATS_TIP_HOUR, row.hour)
    end
    if row.expected and finite(row.expected.mean) then
        local high = finite(row.expected.high) and format("%d", floor(row.expected.high + 0.5))
            or "-"
        tip[#tip + 1] = format(
            L.STATS_TIP_EXPECTED,
            floor(row.expected.mean + 0.5),
            floor(row.expected.low + 0.5),
            high,
            row.perCast.n
        )
    end
    if row.dry then
        tip[#tip + 1] = format(L.STATS_TIP_DRY, row.dry)
    end
    if row.grey[3] then
        tip[#tip + 1] = L.STATS_TIP_GREY
    end
    row.tooltip = tip
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
-- (realm hour minus UTC hour), thresholds, quality (filter; nil = all), sort = { key,
-- descending } }. Returns the rows of the Fish table.
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
