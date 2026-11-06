-- Pure logic: the Classic reference of a water next to the player's own catches. The own group
-- of an area sums the subzone texts of its map that resolve to it (or to a subzone of it without
-- its own list); places without data sum the texts that resolve to nothing. The comparison rows
-- list the area's expected fish (Classic estimate, season or quest flag) with the own share and
-- range, then fish caught here that are not in the Classic data. Also the HUD zone line. No
-- frame or API calls.
local _, ns = ...

local format, pairs, ipairs, sort, floor, type =
    string.format, pairs, ipairs, table.sort, math.floor, type
local L, Stats, HudModel, StatsTables = ns.L, ns.Stats, ns.HudModel, ns.StatsTables

local ZoneRef = {}
ns.ZoneRef = ZoneRef

ZoneRef.SEASONS = { [322] = "winter", [323] = "summer" } -- condition IDs of the zone data

ZoneRef.COLUMNS = {
    { key = "fish", label = L.ZONE_COL_FISH, width = 260 },
    { key = "classic", label = L.ZONE_COL_CLASSIC, width = 130, right = true },
    { key = "flag", label = L.ZONE_COL_FLAG, width = 110 },
    { key = "own", label = L.ZONE_COL_OWN, width = 110, right = true },
    { key = "caught", label = L.ZONE_COL_CAUGHT, width = 80, right = true },
}

local function newGroup()
    return { casts = 0, outcomes = {}, items = {}, active = 0 }
end

local function addGroup(total, group)
    total.casts = total.casts + (group.casts or 0)
    total.active = total.active + (group.active or 0)
    for key, n in pairs(group.outcomes or {}) do
        total.outcomes[key] = (total.outcomes[key] or 0) + n
    end
    for id, n in pairs(group.items or {}) do
        total.items[id] = (total.items[id] or 0) + n
    end
end

-- The own group of an area in one map: view.subs[map] texts whose resolved area uses the area's
-- list; area nil sums the texts without data. areas: the Area resolver.
function ZoneRef.Own(view, areas, map, area)
    local total = newGroup()
    for text, group in pairs(view.subs and view.subs[map] or {}) do
        local resolved = areas and areas:Resolve(map, text ~= "" and text or nil) or nil
        local uses
        if area == nil then
            uses = resolved == nil
        else
            uses = areas:Uses(resolved, area)
        end
        if uses then
            addGroup(total, group)
        end
    end
    return total
end

-- Expected fish of a list (quest-only rows left out) and how many have no own catch:
-- missing, total.
function ZoneRef.Missing(rows, items)
    local seen, missing, total = {}, 0, 0
    for _, row in ipairs(rows or {}) do
        local id = row[1]
        if not row[5] and not seen[id] then
            seen[id] = true
            total = total + 1
            if (items[id] or 0) == 0 then
                missing = missing + 1
            end
        end
    end
    return missing, total
end

local function flagText(row)
    if row[5] then
        return L.ZONE_FLAG_QUEST
    end
    local season = ZoneRef.SEASONS[row[4] or 0]
    return season and L["ZONE_FLAG_" .. season] or ""
end

local function chanceText(chance)
    if chance == floor(chance) then
        return format("%d %%", chance)
    end
    return format("%s %%", (format("%.2f", chance):gsub("0+$", "")))
end

local function ownCells(share, n)
    return n > 0 and HudModel.Percent(share) or "-", format("%d", n)
end

-- Comparison rows: input = { info(id), thresholds }, rows = the area's list rows (nil: no
-- reference data), group = ZoneRef.Own. Rows as in StatsTables.lua, most likely fish first.
function ZoneRef.Rows(rows, group, input)
    local t = input.thresholds or Stats.DEFAULTS
    local catches = Stats.Count(group.outcomes, "catch")
    local result, listed = {}, {}
    for _, row in ipairs(rows or {}) do
        local id, chance = row[1], row[2]
        if not listed[id] then
            listed[id] = true
            local info = input.info(id) or {}
            local n = group.items[id] or 0
            local share = Stats.ItemShare(n, catches, t)
            local own, caught = ownCells(share, n)
            local tip =
                { StatsTables.ItemText(id, info), format(L.ZONE_TIP_CLASSIC, chanceText(chance)) }
            if row[3] == 0 then
                tip[#tip + 1] = L.ZONE_TIP_EXTRA
            end
            if flagText(row) ~= "" then
                tip[#tip + 1] = flagText(row)
            end
            tip[#tip + 1] = StatsTables.ShareLine(share)
            local p = chance / 100
            if share.display ~= "count" and share.low and (p < share.low or p > share.high) then
                tip[#tip + 1] = L.ZONE_TIP_UNUSUAL
            end
            result[#result + 1] = {
                key = format("%d", id),
                chance = chance,
                n = n,
                cells = {
                    StatsTables.ItemText(id, info),
                    chanceText(chance),
                    flagText(row),
                    own,
                    caught,
                },
                grey = { [4] = share.display ~= "full" },
                tooltip = tip,
            }
        end
    end
    sort(result, function(a, b)
        if a.chance ~= b.chance then
            return a.chance > b.chance
        end
        return a.key < b.key
    end)
    local extra = {}
    for id, n in pairs(group.items) do
        if not listed[id] then
            local info = input.info(id) or {}
            local share = Stats.ItemShare(n, catches, t)
            local own, caught = ownCells(share, n)
            extra[#extra + 1] = {
                key = format("%d", id),
                n = n,
                cells = {
                    StatsTables.ItemText(id, info),
                    rows and L.ZONE_NOT_IN_CLASSIC or "-",
                    "",
                    own,
                    caught,
                },
                grey = { [2] = true, [4] = share.display ~= "full" },
                tooltip = { StatsTables.ItemText(id, info), StatsTables.ShareLine(share) },
            }
        end
    end
    sort(extra, function(a, b)
        if a.n ~= b.n then
            return a.n > b.n
        end
        return a.key < b.key
    end)
    for _, row in ipairs(extra) do
        result[#result + 1] = row
    end
    return result
end

-- The line above the comparison: the place, the source, the own catches, and the part of a
-- catch the Classic data does not cover.
function ZoneRef.Note(name, rows, info, group)
    local catches = Stats.Count(group.outcomes, "catch")
    if not rows then
        return format(L.ZONE_NO_REFERENCE, name, catches)
    end
    local note = format(L.ZONE_REFERENCE, name, catches)
    if info and type(info.partial) == "number" then
        note = note .. " " .. format(L.ZONE_PARTIAL, floor(100 - info.partial + 0.5))
    end
    return note
end

-- The comparison for a selected Zones row (ZoneTable.Rows; nil: none selected): { note, rows }.
-- input as for ZoneTable.Rows. The list of the row's area applies (a subzone without a list uses
-- its zone's); the note names the row when the list is its own, else the zone.
function ZoneRef.Detail(view, row, input)
    if not row then
        return { note = L.ZONE_SELECT, rows = {} }
    end
    local areas = input.areas
    local rows, info, listArea
    if areas then
        rows, info, listArea = areas:List(row.area)
    end
    rows = rows or nil
    local group = ZoneRef.Own(view, areas, row.map, rows and listArea or nil)
    -- A subzone row names itself only when the list is its own; else the zone's list applies.
    local name = row.name
    local subRow = row.unnamed ~= nil
    if rows and subRow and not (listArea == row.area and areas:IsSubzone(listArea)) then
        name = input.mapName(row.map) or row.name
    end
    return { note = ZoneRef.Note(name, rows, info, group), rows = ZoneRef.Rows(rows, group, input) }
end

local function pct(x)
    return floor(x * 100 + 0.5)
end

-- The HUD zone line: input = { name, risk (Getaway.Risk), rows (list or nil), items (own items
-- here) }. The risk details ("differs from Classic") go to the tooltip (Getaway.Lines).
function ZoneRef.HudLine(input)
    local risk, model = input.risk, input.risk and input.risk.model
    local getaway
    if not model then
        getaway = L.HUD_ZONE_RISK_UNKNOWN
    elseif model.below then
        getaway = format(L.HUD_ZONE_RISK_BELOW, model.stopsAt - ns.Getaway.SPAN)
    else
        getaway = format(L.HUD_ZONE_RISK, pct(model.getaway))
    end
    if risk and risk.shown then
        getaway = getaway .. " " .. format(L.HUD_ZONE_RISK_OWN, HudModel.Percent(risk.own))
    end
    local fish
    if not input.rows then
        fish = L.HUD_ZONE_NO_DATA
    else
        local missing, total = ZoneRef.Missing(input.rows, input.items or {})
        fish = missing > 0 and format(L.HUD_ZONE_MISSING, missing, total)
            or format(L.HUD_ZONE_ALL, total)
    end
    return format(L.HUD_ZONE, input.name or L.HUD_ZONE_UNNAMED, getaway, fish)
end
