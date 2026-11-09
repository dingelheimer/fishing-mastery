-- Pure logic: the Bite times tab from a StatsView view: groups per zone and lure state (plus all
-- zones together first), each with median and quartiles from its bite histogram (Stats.Quartiles,
-- no range), one table row per group, and a 1-second histogram chart of a group. No frame or API
-- calls.
local _, ns = ...

local format, ipairs, pairs, sort = string.format, ipairs, pairs, table.sort
local L, Stats, ChartModel = ns.L, ns.Stats, ns.ChartModel

local Style = ns.Style
local BiteTable = {}
ns.BiteTable = BiteTable

BiteTable.BIN = 10 -- tenths: 1-second bins
BiteTable.LIMIT = 300 -- tenths: bites after 30 s go into the last bin

BiteTable.COLUMNS = {
    { key = "zone", label = L.STATS_COL_ZONE_ONLY, width = 250 },
    { key = "lure", label = L.STATS_COL_LURE, width = 110 },
    { key = "n", label = L.STATS_COL_BITES, width = 70, right = true },
    { key = "q1", label = L.STATS_COL_Q1, width = 90, right = true },
    { key = "median", label = L.STATS_COL_MEDIAN, width = 90, right = true },
    { key = "q3", label = L.STATS_COL_Q3, width = 90, right = true },
}

local function count(histogram)
    local n = 0
    for _, c in pairs(histogram) do
        n = n + c
    end
    return n
end

-- Groups with bites: { { map (nil = all zones), lure ("on", "off", nil = both), bites, n,
-- quartiles } }; all zones first, then most bites first.
function BiteTable.Groups(view)
    local all, groups = {}, {}
    for map, lures in pairs(view.zones) do
        for lure, group in pairs(lures) do
            local n = count(group.bites or {})
            if n > 0 then
                for tenths, c in pairs(group.bites) do
                    all[tenths] = (all[tenths] or 0) + c
                end
                groups[#groups + 1] = { map = map, lure = lure, bites = group.bites, n = n }
            end
        end
    end
    sort(groups, function(a, b)
        if a.n ~= b.n then
            return a.n > b.n
        end
        if a.map ~= b.map then
            return a.map < b.map
        end
        return a.lure > b.lure -- "on" before "off"
    end)
    if #groups == 0 then
        return {}
    end
    local result = { { bites = all, n = count(all) } }
    for _, group in ipairs(groups) do
        result[#result + 1] = group
    end
    for _, group in ipairs(result) do
        group.quartiles = Stats.Quartiles(group.bites)
    end
    return result
end

local function seconds(tenths)
    return format(L.STATS_SECONDS, tenths / 10)
end

-- Name of a group: "All zones" or "<zone>, with lure" / "<zone>, no lure".
function BiteTable.Name(group, mapName)
    if not group.map then
        return L.STATS_ALL_ZONES
    end
    local zone = mapName(group.map) or format(L.SUMMARY_ZONE_ID, group.map)
    return format("%s, %s", zone, L["STATS_LURE_" .. group.lure])
end

local function lureText(group)
    return group.lure and L["STATS_LURE_" .. group.lure] or L.STATS_LURE_BOTH
end

-- One row per group; selected (index) is marked.
function BiteTable.Rows(groups, mapName, selected)
    local rows = {}
    for i, group in ipairs(groups) do
        local q = group.quartiles
        local zone = group.map and (mapName(group.map) or format(L.SUMMARY_ZONE_ID, group.map))
            or L.STATS_ALL_ZONES
        rows[i] = {
            key = i,
            order = i,
            cells = {
                (i == selected and "> " or "") .. zone,
                lureText(group),
                Style.Number(group.n),
                seconds(q.q1),
                seconds(q.median),
                seconds(q.q3),
            },
            tip = function(tip)
                tip:Title(BiteTable.Name(group, mapName), Style.GOLD)
                tip:Pair(L.STATS_COL_BITES, Style.Number(group.n))
                tip:Pair(L.STATS_COL_MEDIAN, seconds(q.median))
                tip:Pair(L.BITE_TIP_HALF, format(L.BITE_TIP_RANGE, q.q1 / 10, q.q3 / 10))
                tip:Details({ L.BITE_D_QUARTILES })
            end,
        }
    end
    return rows
end

-- "Median 11.2 s; half your bites take 8.4-15.0 s (43 bites)".
function BiteTable.Summary(group)
    local q = group.quartiles
    return format(L.STATS_BITE_SUMMARY, q.median / 10, q.q1 / 10, q.q3 / 10, group.n)
end

-- Histogram of a group in 1-second bins.
function BiteTable.Chart(group)
    local bins = ChartModel.Bins(group.bites, BiteTable.BIN, BiteTable.LIMIT)
    local bars = {}
    for i, n in ipairs(bins) do
        local from = (i - 1) * BiteTable.BIN / 10
        bars[i] = {
            label = format("%d", from),
            value = n,
            text = format("%d", n),
            tip = function(tip)
                tip:Title(format(L.STATS_TIP_BITE_AT, from, from + 1))
                tip:Pair(
                    L.STATS_TIP_BITES,
                    format(L.TIP_OF, Style.Number(n), Style.Number(group.n))
                )
            end,
        }
    end
    return ChartModel.Build(bars, false)
end
