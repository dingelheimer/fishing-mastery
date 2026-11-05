-- Pure logic: the Compare tab. Two groups of casts side by side (lure on/off, day/night, zone A/B,
-- character A/B) from the live aggregates: casts, success, getaway, early-click, and timeout
-- rates with Wilson ranges, their difference with the Newcombe range ("clear difference" only
-- when the range excludes 0; no p-values), and the median bite time (no range: Statistics
-- Methods). No frame or API calls.
local _, ns = ...

local type, ipairs, pairs, sort, format, floor =
    type, ipairs, pairs, table.sort, string.format, math.floor
local L, Stats, HudModel, FailureTable = ns.L, ns.Stats, ns.HudModel, ns.FailureTable

local CompareTable = {}
ns.CompareTable = CompareTable

CompareTable.KINDS = { "lure", "daynight", "zone", "char" }
CompareTable.DAY_FROM, CompareTable.DAY_TO = 6, 18 -- realm hours of "day": 06:00-17:59
-- Rates compared: outcome of base ("fair" or "hooked") casts.
CompareTable.MEASURES = {
    { key = "success", outcome = "catch", base = "fair" },
    { key = "getaway", outcome = "getaway", base = "hooked" },
    { key = "early", outcome = "early_click", base = "fair" },
    { key = "timeout", outcome = "timeout", base = "fair" },
}

CompareTable.COLUMNS = {
    { key = "measure", label = L.CMP_COL_MEASURE, width = 170 },
    { key = "a", label = "A", width = 130, right = true },
    { key = "b", label = "B", width = 130, right = true },
    { key = "diff", label = L.CMP_COL_DIFF, width = 130, right = true },
    { key = "result", label = L.CMP_COL_RESULT, width = 160 },
}

local function newGroup(key)
    return { key = key, casts = 0, outcomes = {}, bites = {} }
end

local function addCounts(into, from)
    for key, n in pairs(type(from) == "table" and from or {}) do
        if type(n) == "number" then
            into[key] = (into[key] or 0) + n
        end
    end
end

local function addGroup(into, from)
    if type(from) == "table" then
        into.casts = into.casts + (from.casts or 0)
        addCounts(into.outcomes, from.outcomes)
        addCounts(into.bites, from.bites)
    end
end

-- Most casts first, then the lower key.
local function byCasts(list)
    sort(list, function(a, b)
        if a.casts ~= b.casts then
            return a.casts > b.casts
        end
        return a.key < b.key
    end)
    return list
end

-- With lure (A) and without (B), all zones of the view.
function CompareTable.Lure(view)
    local a, b = newGroup("on"), newGroup("off")
    for _, lures in pairs(view.zones) do
        addGroup(a, lures.on)
        addGroup(b, lures.off)
    end
    return { a, b }
end

-- Day (A) and night (B) by realm hour; offset: realm hour minus UTC hour of the server time.
function CompareTable.DayNight(view, offset)
    local a, b = newGroup("day"), newGroup("night")
    for hour, entry in pairs(view.hours) do
        local realm = (hour + (offset or 0)) % 24
        local into = (realm >= CompareTable.DAY_FROM and realm < CompareTable.DAY_TO) and a or b
        into.casts = into.casts + (entry.casts or 0)
        addCounts(into.outcomes, entry.outcomes)
    end
    return { a, b }
end

-- One group per zone of the view (both lure states), most casts first.
function CompareTable.Zones(view)
    local list = {}
    for map, lures in pairs(view.zones) do
        local group = newGroup(map)
        addGroup(group, lures.on)
        addGroup(group, lures.off)
        list[#list + 1] = group
    end
    return byCasts(list)
end

-- One group per character; chars: { { key, name, view } }. Most casts first.
function CompareTable.Chars(chars)
    local list = {}
    for _, char in ipairs(chars) do
        local group = newGroup(char.key)
        group.name = char.name
        for _, lures in pairs(char.view.zones) do
            addGroup(group, lures.on)
            addGroup(group, lures.off)
        end
        list[#list + 1] = group
    end
    return byCasts(list)
end

local function base(outcomes, name)
    return name == "hooked" and Stats.Hooked(outcomes) or Stats.Fair(outcomes)
end

local function points(x)
    return floor(x * 100 + 0.5)
end

-- Row of one rate: both rates, the difference A - B in percentage points, and the verdict.
local function rateRow(measure, a, b, t)
    local label = L["CMP_" .. measure.key]
    local pa = Stats.Proportion(
        Stats.Count(a.outcomes, measure.outcome),
        base(a.outcomes, measure.base),
        t
    )
    local pb = Stats.Proportion(
        Stats.Count(b.outcomes, measure.outcome),
        base(b.outcomes, measure.base),
        t
    )
    local row = {
        key = measure.key,
        grey = { [2] = pa.display ~= "full", [3] = pb.display ~= "full" },
        tooltip = {
            label,
            FailureTable.RateLine("A", pa),
            FailureTable.RateLine("B", pb),
        },
    }
    local diff, cells = nil, { label, HudModel.Percent(pa), HudModel.Percent(pb), "-", L.CMP_FEW }
    if pa.display ~= "count" and pb.display ~= "count" then
        diff = Stats.Difference(pa.k, pa.n, pb.k, pb.n, t)
    end
    if diff then
        cells[4] = format(L.CMP_POINTS, points(diff.d))
        cells[5] = diff.clear and L.CMP_CLEAR or L.CMP_UNCLEAR
        row.tooltip[#row.tooltip + 1] =
            format(L.CMP_TIP_DIFF, points(diff.d), points(diff.low), points(diff.high))
        row.clear = diff.clear
    else
        row.tooltip[#row.tooltip + 1] = L.CMP_TIP_FEW
    end
    row.tooltip[#row.tooltip + 1] = L.CMP_TIP_RULE
    row.cells = cells
    return row
end

local function median(group)
    local value = Stats.Quantile(group.bites, 0.5)
    return value and value / 10 or nil
end

-- Rows for groups a and b: casts, the rates of MEASURES, and the median bite time when both
-- groups have bites.
function CompareTable.Rows(a, b, t)
    local rows = {
        {
            key = "casts",
            cells = { L.CMP_casts, format("%d", a.casts), format("%d", b.casts), "", "" },
            tooltip = { L.CMP_casts, L.CMP_TIP_CASTS },
        },
    }
    for _, measure in ipairs(CompareTable.MEASURES) do
        rows[#rows + 1] = rateRow(measure, a, b, t)
    end
    local ma, mb = median(a), median(b)
    if ma and mb then
        rows[#rows + 1] = {
            key = "bite",
            cells = {
                L.CMP_bite,
                format(L.STATS_SECONDS, ma),
                format(L.STATS_SECONDS, mb),
                format(L.CMP_SECONDS, ma - mb),
                L.CMP_NO_RANGE,
            },
            tooltip = { L.CMP_bite, L.CMP_TIP_BITE },
        }
    end
    return rows
end

-- Name of a group of a kind; input: { mapName(map) }.
function CompareTable.Name(kind, group, input)
    if kind == "zone" then
        return input.mapName(group.key) or format(L.SUMMARY_ZONE_ID, group.key)
    end
    if kind == "char" then
        return group.name or L.STATS_UNNAMED
    end
    return L["CMP_GROUP_" .. group.key]
end
