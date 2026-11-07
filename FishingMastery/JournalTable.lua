-- Pure logic: the Fish tab of the journal window from a JournalModel model: the filtered list rows
-- (group, caught or not, plain-text search on the item name), the progress line, and the detail
-- lines of the selected fish. Not-caught rows are marked (dimmed icon, grey cells, "not caught")
-- but keep every column filled (owner decision 2, 2026-11-06). No frame or API calls.
local _, ns = ...

local format, ipairs, find, lower, min, concat, type, tostring =
    string.format, ipairs, string.find, string.lower, math.min, table.concat, type, tostring
local L, StatsTables = ns.L, ns.StatsTables

local JournalTable = {}
ns.JournalTable = JournalTable

JournalTable.ICON = 14
JournalTable.DIM = 110 -- icon vertex color (0-255) of not-caught fish
JournalTable.FILTERS = { "all", "fish", "trophy", "container", "quest" }
JournalTable.SHOWS = { "all", "caught", "missing" }
JournalTable.COLUMNS = {
    { key = "fish", label = L.JOURNAL_COL_FISH, width = 190 },
    { key = "group", label = L.JOURNAL_COL_GROUP, width = 80 },
    { key = "caught", label = L.JOURNAL_COL_CAUGHT, width = 64, right = true },
    { key = "where", label = L.JOURNAL_COL_WHERE, width = 120 },
    { key = "skill", label = L.JOURNAL_COL_SKILL, width = 56, right = true },
}
local GREY_ALL = { true, true, true, true, true }

-- Item text with a dimmed icon (texture escape with a vertex color) for a not-caught fish.
function JournalTable.ItemText(id, info, caught)
    if caught or not info.icon then
        return StatsTables.ItemText(id, info)
    end
    local name = info.name or format(L.HUD_ITEM_LOADING, id)
    local d, size = JournalTable.DIM, JournalTable.ICON
    return format(
        "|T%d:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t %s",
        info.icon,
        size,
        size,
        d,
        d,
        d,
        name
    )
end

-- Place name of an area: "Subzone, Zone" for a subzone, the zone name otherwise.
local function areaName(input, area)
    local info = input.areas and input.areas:Info(area)
    local name = input.areaName(area) or tostring(area)
    local zone = info and info.zone and input.areaName(info.zone)
    return zone and format(L.JOURNAL_SUBZONE, name, zone) or name
end

local function placeName(input, map, sub)
    local zone = input.mapName(map) or L.JOURNAL_NO_PLACE
    if type(sub) == "string" and sub ~= "" then
        return format(L.JOURNAL_SUBZONE, sub, zone)
    end
    return zone
end

local function matches(entry, filters, name)
    if filters.group and filters.group ~= "all" and entry.group ~= filters.group then
        return false
    end
    if filters.show == "caught" and not entry.caught then
        return false
    end
    if filters.show == "missing" and entry.caught then
        return false
    end
    local search = filters.search
    if type(search) == "string" and search ~= "" then
        return find(lower(name or ""), lower(search), 1, true) ~= nil
    end
    return true
end

local function skillText(entry)
    if not entry.base then
        return L.JOURNAL_NO_PLACE
    end
    return format(L.JOURNAL_SKILL_RANGE, entry.base < 1 and 1 or entry.base, entry.safe)
end

-- input: { info(id) -> { name, icon, quality, hex }, mapName(map), areaName(area), areas }.
-- filters: { group ("all" or a journal group), show ("all", "caught", "missing"), search,
-- selected (item ID) }. Returns the list rows (data.id = item ID).
function JournalTable.Rows(model, input, filters)
    local rows = {}
    for _, entry in ipairs(model.entries) do
        local info = input.info(entry.id)
        if matches(entry, filters, info.name) then
            local where
            if entry.caught and entry.best then
                where = input.mapName(entry.best)
            elseif entry.places[1] then
                where = areaName(input, entry.places[1].area)
            end
            rows[#rows + 1] = {
                id = entry.id,
                selected = filters.selected == entry.id,
                grey = not entry.caught and GREY_ALL or nil,
                cells = {
                    JournalTable.ItemText(entry.id, info, entry.caught),
                    L["JOURNAL_GROUP_" .. entry.group],
                    entry.caught and tostring(entry.n) or L.JOURNAL_NOT_CAUGHT,
                    where or L.JOURNAL_NO_PLACE,
                    skillText(entry),
                },
            }
        end
    end
    return rows
end

-- "Fish 17 / 28 + 2 new in Forever;  Trophy fish 0 / 35;  ...".
function JournalTable.Progress(model)
    local parts = {}
    for i, group in ipairs(ns.JournalModel.GROUPS) do
        local p = model.progress[group]
        local text =
            format(L.JOURNAL_PROGRESS_GROUP, L["JOURNAL_GROUP_" .. group], p.caught, p.total)
        if p.new > 0 then
            text = text .. format(L.JOURNAL_PROGRESS_NEW, p.new)
        end
        parts[i] = text
    end
    local line = concat(parts, ";  ")
    if model.pending > 0 then
        line = line .. "  " .. format(L.JOURNAL_PENDING, model.pending)
    end
    return line
end

local function pct(x)
    local value = x * 100
    if value < 1 then
        return format("%.1f %%", value)
    end
    return format("%d %%", value + 0.5)
end

-- Detail lines of one entry. input as for Rows plus formatDate(t), spellName(id),
-- ownShare(area, id) -> k, n (own catches of the item and all catches in that area) or nil,
-- recipe(spell) -> the journal recipe row, formatMonthDay(month, day).
function JournalTable.Detail(entry, input)
    if not entry then
        return { L.JOURNAL_SELECT }
    end
    local info = input.info(entry.id)
    local lines = { JournalTable.ItemText(entry.id, info, entry.caught) }
    local function add(...)
        lines[#lines + 1] = format(...)
    end
    add("%s", L["JOURNAL_GROUP_" .. entry.group])
    if entry.new then
        add("%s", L.JOURNAL_D_NEW)
    end
    if entry.questOnly then
        add("%s", L.JOURNAL_D_QUEST)
    end
    if entry.caught then
        add(L.JOURNAL_D_CAUGHT, entry.n, entry.qty or entry.n)
        if entry.first then
            add(
                L.JOURNAL_D_FIRST,
                input.formatDate(entry.first),
                placeName(input, entry.firstMap, entry.firstSub)
            )
        end
        if entry.best then
            add(L.JOURNAL_D_BEST, input.mapName(entry.best) or L.JOURNAL_NO_PLACE)
        end
    else
        add("%s", L.JOURNAL_D_NOT_CAUGHT)
    end
    if entry.base and entry.base < 1 then
        add("%s", L.JOURNAL_D_SKILL_LOW)
    elseif entry.base then
        add(L.JOURNAL_D_SKILL, entry.base, entry.safe)
    else
        add("%s", L.JOURNAL_D_NO_SKILL)
    end
    if #entry.places > 0 then
        add("%s", L.JOURNAL_D_WHERE)
        for _, place in ipairs(entry.places) do
            local k, n = input.ownShare(place.area, entry.id)
            local name = areaName(input, place.area)
            if n and n > 0 then
                add(L.JOURNAL_D_PLACE_OWN, name, pct(place.chance / 100), pct(k / n), k, n)
            else
                add(L.JOURNAL_D_PLACE, name, pct(place.chance / 100))
            end
        end
        if entry.placeCount > #entry.places then
            add(L.JOURNAL_D_MORE, entry.placeCount - #entry.places)
        end
    else
        add("%s", L.JOURNAL_D_NO_WHERE)
    end
    if #entry.recipes > 0 then
        add("%s", L.JOURNAL_D_RECIPES)
        for i = 1, min(#entry.recipes, 6) do
            local spell = entry.recipes[i]
            local recipe = input.recipe(spell)
            add(
                L.JOURNAL_D_RECIPE,
                input.spellName(spell) or format(L.JOURNAL_SPELL_LOADING, spell),
                L["JOURNAL_SKILL_" .. recipe[1]] or ""
            )
        end
    end
    local season = entry.season
    if season then
        local start = input.formatMonthDay(season.month, season.day)
        add(L.JOURNAL_D_SEASON, L["JOURNAL_SEASON_" .. season.season], start, season.days)
    end
    return lines
end
