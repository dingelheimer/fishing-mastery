-- Pure logic: the Fish tab of the journal window from a JournalModel model: the filtered list rows
-- (group, caught or not, plain-text search on the item name), the progress line, and the place
-- names the detail pane shares (JournalDetail.lua). Not-caught rows are marked (dimmed icon, grey
-- cells, "not caught") but keep every column filled (owner decision 2, 2026-11-06). No frame or
-- API calls.
local _, ns = ...

local format, ipairs, find, lower, type, tostring =
    string.format, ipairs, string.find, string.lower, type, tostring
local L, StatsTables = ns.L, ns.StatsTables

local Style = ns.Style
local JournalTable = {}
ns.JournalTable = JournalTable

JournalTable.ICON = 14
JournalTable.DIM = 110 -- icon vertex color (0-255) of not-caught fish
JournalTable.FILTERS = { "all", "fish", "trophy", "container", "quest" }
JournalTable.SHOWS = { "all", "caught", "missing" }
JournalTable.COLUMNS = {
    { key = "fish", label = L.JOURNAL_COL_FISH, width = 196, icon = true, tags = true },
    { key = "group", label = L.JOURNAL_COL_GROUP, width = 76 },
    { key = "caught", label = L.JOURNAL_COL_CAUGHT, width = 64, right = true },
    { key = "where", label = L.JOURNAL_COL_WHERE, width = 118 },
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

-- Place name of an area: "Subzone, Zone" for a subzone (only the subzone when short), the zone
-- name otherwise.
function JournalTable.AreaName(input, area, short)
    local name = input.areaName(area) or tostring(area)
    if short then
        return name
    end
    local info = input.areas and input.areas:Info(area)
    local zone = info and info.zone and input.areaName(info.zone)
    return zone and format(L.JOURNAL_SUBZONE, name, zone) or name
end

-- Place of a first catch: "Subzone, Zone" when the subzone text is known, else the zone.
function JournalTable.PlaceName(input, map, sub)
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
                where = JournalTable.AreaName(input, entry.places[1].area)
            end
            rows[#rows + 1] = {
                id = entry.id,
                selected = filters.selected == entry.id,
                grey = not entry.caught and GREY_ALL or nil,
                cells = {
                    info.name or format(L.HUD_ITEM_LOADING, entry.id),
                    L["JOURNAL_GROUP_" .. entry.group],
                    entry.caught and Style.Number(entry.n) or L.JOURNAL_NOT_CAUGHT,
                    where or L.JOURNAL_NO_PLACE,
                    skillText(entry),
                },
                icons = { info.icon },
                colors = { entry.caught and Style.FromHex(info.hex) or nil },
                dim = { not entry.caught },
                tags = { StatsTables.Tag(entry.season, entry.time) },
            }
        end
    end
    return rows
end

-- The header bar: the fish group caught of total ("Fish 17 / 28"), and one tooltip line per
-- group with the new items and the items still waiting for data.
function JournalTable.Bar(model)
    local fish = model.progress.fish or { caught = 0, total = 0, new = 0 }
    local lines = {}
    for _, group in ipairs(ns.JournalModel.GROUPS) do
        local p = model.progress[group]
        local value = format(L.JOURNAL_BAR_VALUE, p.caught, p.total)
        if p.new > 0 then
            value = value .. format(L.JOURNAL_PROGRESS_NEW, p.new)
        end
        lines[#lines + 1] = { label = L["JOURNAL_GROUP_" .. group], value = value }
    end
    return {
        caught = fish.caught,
        total = fish.total,
        text = format(L.JOURNAL_PROGRESS_GROUP, L.JOURNAL_GROUP_fish, fish.caught, fish.total),
        lines = lines,
        pending = model.pending > 0 and format(L.JOURNAL_PENDING, model.pending) or nil,
    }
end
