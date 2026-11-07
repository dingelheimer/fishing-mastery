-- Pure logic: a view of the totals for the stats window: one character, or several characters
-- merged in memory (subzones keyed by their text, since every character numbers its own; items by
-- first and last catch, the first catch place (map and subzone text), and summed hours, the best
-- zone recomputed from the merged maps). No frame or API calls.
local _, ns = ...

local type, pairs, ipairs = type, pairs, ipairs
local Stats, Totals = ns.Stats, ns.Totals

local StatsView = {}
ns.StatsView = StatsView

StatsView.NO_SUBZONE = "" -- subzone key of casts without a subzone text

local function tbl(value)
    return type(value) == "table" and value or {}
end

local function add(list, key, n)
    list[key] = (list[key] or 0) + (type(n) == "number" and n or 0)
end

local function child(list, key)
    local value = list[key]
    if not value then
        value = {}
        list[key] = value
    end
    return value
end

local function addCounts(into, from)
    for key, n in pairs(tbl(from)) do
        add(into, key, n)
    end
end

local function mergeItem(view, id, entry, subzones)
    local item = view.items[id]
    if not item then
        item = { n = 0, qty = 0, hours = {} }
        view.items[id] = item
    end
    item.n, item.qty = item.n + (entry.n or 0), item.qty + (entry.qty or 0)
    if type(entry.first) == "number" and (not item.first or entry.first < item.first) then
        item.first = entry.first
        -- First catch place: map and subzone text (indices differ per character).
        local name = type(entry.fs) == "number" and entry.fs ~= 0 and subzones[entry.fs] or nil
        item.firstMap = type(entry.fm) == "number" and entry.fm or nil
        item.firstSub = item.firstMap and (type(name) == "string" and name or StatsView.NO_SUBZONE)
            or nil
    end
    if type(entry.last) == "number" and (not item.last or entry.last > item.last) then
        item.last = entry.last
    end
    addCounts(item.hours, entry.hours)
    item.fair = entry.fair -- used only for a single character
end

local function mergeSubs(view, totals, subzones)
    for map, subs in pairs(tbl(totals.subs)) do
        local zone = child(view.subs, map)
        for index, group in pairs(tbl(subs)) do
            local name = index ~= 0 and subzones[index] or nil
            local key = type(name) == "string" and name or StatsView.NO_SUBZONE
            local into = zone[key]
            if not into then
                into = { casts = 0, outcomes = {}, items = {}, active = 0 }
                zone[key] = into
            end
            into.casts = into.casts + (group.casts or 0)
            into.active = into.active + (group.active or 0)
            addCounts(into.outcomes, group.outcomes)
            addCounts(into.items, group.items)
        end
    end
end

-- Hooked casts and getaways per map, subzone text, and skill band.
local function mergeSubSkills(view, totals, subzones)
    for map, subs in pairs(tbl(totals.subskills)) do
        local zone = child(view.subskills, map)
        for index, bands in pairs(tbl(subs)) do
            local name = index ~= 0 and subzones[index] or nil
            local into = child(zone, type(name) == "string" and name or StatsView.NO_SUBZONE)
            for band, entry in pairs(tbl(bands)) do
                local sum = child(into, band)
                add(sum, "hooked", entry.hooked)
                add(sum, "getaways", entry.getaways)
            end
        end
    end
end

-- Lure groups per map: casts, outcomes, bite and early-click histograms.
local function mergeZones(view, totals)
    for map, lures in pairs(tbl(totals.zones)) do
        local zone = child(view.zones, map)
        for lure, group in pairs(tbl(lures)) do
            local into = zone[lure]
            if not into then
                into = { casts = 0, outcomes = {}, bites = {}, clicks = {} }
                zone[lure] = into
            end
            into.casts = into.casts + (group.casts or 0)
            addCounts(into.outcomes, group.outcomes)
            addCounts(into.bites, group.bites)
            addCounts(into.clicks, group.clicks)
        end
    end
end

local function mergeChar(view, char)
    local totals = tbl(char.totals)
    if not Totals.Current(totals) then
        view.stale = view.stale + 1
    end
    addCounts(view.outcomes, totals.outcomes)
    addCounts(view.activeByMap, totals.active)
    for day, entry in pairs(tbl(totals.days)) do
        local into = child(view.days, day)
        add(into, "casts", entry.casts)
        add(into, "catches", entry.catches)
    end
    for hour, entry in pairs(tbl(totals.hours)) do
        local into = child(view.hours, hour)
        add(into, "casts", entry.casts)
        addCounts(child(into, "outcomes"), entry.outcomes)
    end
    for map, entry in pairs(tbl(totals.maps)) do
        local into = child(view.maps, map)
        add(into, "casts", entry.casts)
        add(into, "catches", entry.catches)
        addCounts(child(into, "items"), entry.items)
    end
    for id, entry in pairs(tbl(totals.items)) do
        mergeItem(view, id, entry, tbl(char.subzones))
    end
    mergeSubs(view, totals, tbl(char.subzones))
    mergeSubSkills(view, totals, tbl(char.subzones))
    mergeZones(view, totals)
    for _, bands in pairs(tbl(totals.skills)) do
        for band, entry in pairs(tbl(bands)) do
            local into = child(view.skills, band)
            add(into, "hooked", entry.hooked)
            add(into, "getaways", entry.getaways)
        end
    end
end

-- The map with the most of an item (quantity); ties go to the lower map ID.
local function bestMap(maps, id)
    local best, most = nil, 0
    for map, entry in pairs(maps) do
        local qty = tbl(entry.items)[id] or 0
        if qty > most or (qty == most and qty > 0 and map < best) then
            best, most = map, qty
        end
    end
    return best
end

-- View of the characters in list (char entries): { outcomes, active, activeByMap, days ([day] =
-- { casts, catches }), dayCount, hours ([UTC hour] = { casts, outcomes }), maps, items, subs,
-- zones ([map][lure] with bites and clicks), skills ([band] = { hooked,
-- getaways }, all maps together), subskills ([map][subzone text][band] = { hooked, getaways }),
-- stale (characters counted by an older Totals version), fair
-- (fair casts now; single character only, for dry streaks) }.
function StatsView.Build(list)
    local view = {
        outcomes = {},
        activeByMap = {},
        days = {},
        hours = {},
        maps = {},
        items = {},
        subs = {},
        zones = {},
        skills = {},
        subskills = {},
        stale = 0,
        chars = #list,
    }
    for _, char in ipairs(list) do
        mergeChar(view, char)
    end
    view.active, view.dayCount, view.species = 0, 0, 0
    for _, seconds in pairs(view.activeByMap) do
        view.active = view.active + seconds
    end
    for _ in pairs(view.days) do
        view.dayCount = view.dayCount + 1
    end
    for id, item in pairs(view.items) do
        item.best = bestMap(view.maps, id)
        view.species = view.species + 1
    end
    if #list == 1 then
        view.fair = Stats.Fair(view.outcomes)
    else
        for _, item in pairs(view.items) do
            item.fair = nil
        end
    end
    return view
end
