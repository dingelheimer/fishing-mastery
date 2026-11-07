-- Pure logic: the Waters tab of the journal window. One row per area of the zone data (each zone
-- with its subzones indented below, then the dungeons), plus places the player fished that have no
-- reference data. Each row has the base and no-getaway skill, the number of fish in its list, the
-- own casts and catches there, and a color band for the player's effective skill: red below the
-- base (no catch), orange from the base to base + 94 (getaways), green from base + 95. No frame or
-- API calls.
local _, ns = ...

local format, ipairs, pairs, sort, type, tostring =
    string.format, ipairs, pairs, table.sort, type, tostring
local L = ns.L

local WatersTable = {}
ns.WatersTable = WatersTable

WatersTable.SAFE = 95 -- getaways stop at base + SAFE (Zone Data research)
WatersTable.INDENT = "    "
WatersTable.SORTS = { "name", "base" }
WatersTable.COLORS = {
    red = { 1, 0.25, 0.25 },
    orange = { 1, 0.6, 0.1 },
    green = { 0.3, 0.9, 0.3 },
}
WatersTable.COLUMNS = {
    { key = "water", label = L.WATERS_COL_WATER, width = 290 },
    { key = "base", label = L.WATERS_COL_BASE, width = 80, right = true },
    { key = "safe", label = L.WATERS_COL_SAFE, width = 100, right = true },
    { key = "fish", label = L.WATERS_COL_FISH, width = 60, right = true },
    { key = "casts", label = L.WATERS_COL_CASTS, width = 70, right = true },
    { key = "catches", label = L.WATERS_COL_CATCHES, width = 70, right = true },
}

-- Color band of a water for an effective skill: "red", "orange", "green", or nil (no base or no
-- skill known).
function WatersTable.Band(skill, base)
    if type(skill) ~= "number" or type(base) ~= "number" then
        return nil
    end
    if skill < base then
        return "red"
    end
    if skill < base + WatersTable.SAFE then
        return "orange"
    end
    return "green"
end

-- Own casts and catches per resolved area and per map: { [area] = { casts, catches } }, and the
-- map totals. Subzone texts resolve through the Area resolver; casts that resolve to nothing are
-- left out of the areas (their map row counts them).
local function ownCounts(view, areas)
    local byArea = {}
    for map, subs in pairs(view.subs or {}) do
        for text, group in pairs(subs) do
            local area = areas:Resolve(map, text ~= "" and text or nil)
            if area then
                local entry = byArea[area] or { casts = 0, catches = 0 }
                byArea[area] = entry
                entry.casts = entry.casts + (group.casts or 0)
                entry.catches = entry.catches + ((group.outcomes or {}).catch or 0)
            end
        end
    end
    return byArea
end

-- Fish of the journal fish group in the list that applies to an area (quest rows left out).
local function fishCount(areas, groupOf, area)
    local rows = areas:List(area)
    local seen, n = {}, 0
    for _, row in ipairs(rows or {}) do
        if not row[5] and groupOf[row[1]] == "fish" and not seen[row[1]] then
            seen[row[1]] = true
            n = n + 1
        end
    end
    return n
end

local function newRow(input, area, map, own, kind)
    local base = input.areas:Base(area)
    local band = WatersTable.Band(input.skill, base)
    local name = input.areaName(area) or tostring(area)
    return {
        key = tostring(area),
        area = area,
        map = map,
        kind = kind,
        name = name,
        base = base,
        band = band,
        color = band and WatersTable.COLORS[band] or nil,
        own = own or { casts = 0, catches = 0 },
        fish = fishCount(input.areas, input.groupOf, area),
    }
end

local function cells(row)
    local label = row.name
    if row.kind == "subzone" then
        label = WatersTable.INDENT .. label
    elseif row.kind == "dungeon" then
        label = format(L.WATERS_DUNGEON, label)
    elseif row.kind == "none" then
        label = format(L.WATERS_NO_REFERENCE, label)
    end
    local base = row.base and tostring(row.base < 1 and 1 or row.base) or "-"
    local safe = row.base and tostring(row.base + WatersTable.SAFE) or "-"
    return {
        label,
        base,
        safe,
        row.kind == "none" and "-" or tostring(row.fish),
        tostring(row.own.casts),
        tostring(row.own.catches),
    }
end

local function before(sortKey)
    return function(a, b)
        if sortKey == "base" and a.base ~= b.base then
            if a.base == nil or b.base == nil then
                return b.base == nil
            end
            return a.base < b.base
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.area < b.area
    end
end

local function fishable(row)
    return row.band == "orange" or row.band == "green"
end

-- input: { zones, areas, view, skill (effective, or nil), groupOf (item -> journal group),
-- areaName(area), mapName(map) }. filters: { fishable (bool), sort ("name" or "base"),
-- selected (row key) }. Returns the list rows.
function WatersTable.Rows(input, filters)
    local zones, view = input.zones, input.view
    local own = ownCounts(view, input.areas)
    local mapOf = {}
    for map, area in pairs(zones.mapToArea or {}) do
        mapOf[area] = map
    end
    local tops, kids = {}, {}
    for area, info in pairs(zones.areas or {}) do
        if info.zone then
            local list = kids[info.zone] or {}
            kids[info.zone] = list
            list[#list + 1] = newRow(input, area, mapOf[info.zone], own[area], "subzone")
        else
            local map = mapOf[area]
            local counts = map and (view.maps or {})[map] or nil
            local row = newRow(input, area, map, counts, info.instance and "dungeon" or "zone")
            tops[#tops + 1] = row
        end
    end
    for map, counts in pairs(view.maps or {}) do
        if map ~= 0 and not (zones.mapToArea or {})[map] then
            tops[#tops + 1] = {
                key = "map" .. map,
                map = map,
                area = 0,
                kind = "none",
                name = input.mapName(map) or tostring(map),
                own = counts,
            }
        end
    end
    local order = before(filters.sort or "name")
    sort(tops, function(a, b)
        if (a.kind == "dungeon") ~= (b.kind == "dungeon") then
            return b.kind == "dungeon"
        end
        return order(a, b)
    end)
    local rows = {}
    local function add(row)
        row.cells = cells(row)
        row.selected = filters.selected == row.key
        rows[#rows + 1] = row
    end
    for _, top in ipairs(tops) do
        local children = kids[top.area] or {}
        sort(children, order)
        local shown = {}
        for _, child in ipairs(children) do
            if not filters.fishable or fishable(child) then
                shown[#shown + 1] = child
            end
        end
        if not filters.fishable or fishable(top) or #shown > 0 then
            add(top)
            for _, child in ipairs(shown) do
                add(child)
            end
        end
    end
    return rows
end

-- The line above the list: the skill the colors use, or that it is unknown.
function WatersTable.Legend(skill)
    if type(skill) ~= "number" then
        return L.WATERS_LEGEND_UNKNOWN
    end
    return format(L.WATERS_LEGEND, skill)
end
