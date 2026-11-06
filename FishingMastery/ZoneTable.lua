-- Pure logic: the Zones table of the stats window from a StatsModel view: every zone (most casts
-- first) with its subzones below, casts, catches per hour, species, and the top items with their
-- shares; ranges in the tooltips. Subzone texts that resolve to a subzone of the zone data form
-- one row per area; other texts keep their own row. Rows as in StatsTables.lua and carry the
-- resolved area ID (nil without data). No frame or API calls.
local _, ns = ...

local format, pairs, ipairs, sort, concat = string.format, pairs, ipairs, table.sort, table.concat
local L, Stats, HudModel, StatsTables = ns.L, ns.Stats, ns.HudModel, ns.StatsTables

local ZoneTable = {}
ns.ZoneTable = ZoneTable

ZoneTable.TOP_ITEMS = 3 -- items in the row
ZoneTable.TIP_ITEMS = 10 -- items in the tooltip

ZoneTable.COLUMNS = {
    { key = "name", label = L.STATS_COL_ZONE, width = 230 },
    { key = "casts", label = L.STATS_COL_CASTS, width = 60, right = true },
    { key = "perHour", label = L.STATS_COL_PER_HOUR, width = 80, right = true },
    { key = "species", label = L.STATS_COL_SPECIES, width = 60, right = true },
    { key = "top", label = L.STATS_COL_TOP, width = 280 },
}

-- Items of a group, most caught first: { { id, share } }.
local function topItems(group, catches, t)
    local list = {}
    for id, n in pairs(group.items) do
        list[#list + 1] = { id = id, n = n, share = Stats.ItemShare(n, catches, t) }
    end
    sort(list, function(a, b)
        if a.n ~= b.n then
            return a.n > b.n
        end
        return a.id < b.id
    end)
    return list
end

local function zoneRow(key, name, group, input, indent)
    local t = input.thresholds or Stats.DEFAULTS
    local catches = Stats.Count(group.outcomes, "catch")
    local items = topItems(group, catches, t)
    local perHour = Stats.CatchesPerHour(group.outcomes, group.active, t)
    local success = Stats.SuccessRate(group.outcomes, t)
    local top, tip = {}, { name }
    for _, line in ipairs(HudModel.Tooltip({ success = success, perHour = perHour })) do
        tip[#tip + 1] = line
    end
    for i, entry in ipairs(items) do
        local info = input.info(entry.id) or {}
        if i <= ZoneTable.TOP_ITEMS then
            local label = info.icon
                    and format("|T%d:%d:%d|t", info.icon, StatsTables.ICON, StatsTables.ICON)
                or info.name
                or format(L.HUD_ITEM_LOADING, entry.id)
            top[#top + 1] = format("%s %s", label, HudModel.Percent(entry.share))
        end
        if i <= ZoneTable.TIP_ITEMS then
            tip[#tip + 1] = format(
                "%s: %s",
                StatsTables.ItemText(entry.id, info),
                StatsTables.ShareLine(entry.share)
            )
        end
    end
    return {
        key = key,
        casts = group.casts,
        cells = {
            (indent and "    " or "") .. name,
            format("%d", group.casts),
            HudModel.Rate(perHour),
            format("%d", #items),
            concat(top, "  "),
        },
        grey = { [3] = perHour.display ~= "full" },
        tooltip = tip,
    }
end

local function byCasts(a, b)
    if a.casts ~= b.casts then
        return a.casts > b.casts
    end
    return a.key < b.key
end

-- Sum of groups (a zone from its subzones, or the texts of one area; every cast belongs to
-- exactly one subzone group).
local function zoneTotal(subs)
    local total = { casts = 0, outcomes = {}, items = {}, active = 0 }
    for _, group in pairs(subs) do
        total.casts, total.active = total.casts + group.casts, total.active + group.active
        for key, n in pairs(group.outcomes) do
            total.outcomes[key] = (total.outcomes[key] or 0) + n
        end
        for id, n in pairs(group.items) do
            total.items[id] = (total.items[id] or 0) + n
        end
    end
    return total
end

-- Subzone groups of one map keyed for rows: texts resolving to a subzone area share a key.
-- Returns { { key, name, unnamed, area, groups } }.
local function subGroups(map, subs, areas)
    local byKey, list = {}, {}
    for name, group in pairs(subs) do
        local unnamed = name == ns.StatsView.NO_SUBZONE
        local area = areas and areas:Resolve(map, not unnamed and name or nil) or nil
        local key = name
        if areas and areas:IsSubzone(area) then
            key = format("#%d", area)
        end
        local entry = byKey[key]
        if not entry then
            entry = { key = key, name = name, unnamed = unnamed, area = area, groups = {} }
            byKey[key] = entry
            list[#list + 1] = entry
        elseif name < entry.name then
            entry.name = name
        end
        entry.groups[#entry.groups + 1] = group
    end
    return list
end

-- input: { info(id), mapName(map), thresholds, areas (Area resolver, optional) }. Returns the
-- Zones rows: each zone (most casts first) followed by its subzones; a zone fished only without a
-- subzone text has none. Each row has .area: the resolved area ID or nil.
function ZoneTable.Rows(view, input)
    local zones, areas = {}, input.areas
    for map, subs in pairs(view.subs) do
        local zone = zoneRow(
            format("%09d", map),
            input.mapName(map) or format(L.SUMMARY_ZONE_ID, map),
            zoneTotal(subs),
            input
        )
        zone.area = areas and areas:Resolve(map, nil) or nil
        zone.subs = {}
        for _, entry in ipairs(subGroups(map, subs, areas)) do
            local sub = zoneRow(
                zone.key .. "/" .. entry.key,
                entry.unnamed and L.STATS_NO_SUBZONE or entry.name,
                #entry.groups == 1 and entry.groups[1] or zoneTotal(entry.groups),
                input,
                true
            )
            sub.unnamed, sub.area = entry.unnamed, entry.area
            zone.subs[#zone.subs + 1] = sub
        end
        zones[#zones + 1] = zone
    end
    sort(zones, byCasts)
    local rows = {}
    for _, zone in ipairs(zones) do
        rows[#rows + 1] = zone
        sort(zone.subs, byCasts)
        local onlyUnnamed = #zone.subs == 1 and zone.subs[1].unnamed
        for _, sub in ipairs(onlyUnnamed and {} or zone.subs) do
            rows[#rows + 1] = sub
        end
        zone.subs = nil
    end
    return rows
end
