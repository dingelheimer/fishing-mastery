-- Pure logic: the Overview tab's texts from StatsModel.Overview: the account's lifetime lines,
-- the records, and one list row per character (rows as in StatsTables.lua). Character names
-- are the own account's characters only. No frame or API calls.
local _, ns = ...

local format, floor, ipairs = string.format, math.floor, ipairs
local L, HudModel, SummaryModel = ns.L, ns.HudModel, ns.SummaryModel

local OverviewTable = {}
ns.OverviewTable = OverviewTable

OverviewTable.COLUMNS = {
    { key = "name", label = L.STATS_COL_CHARACTER, width = 170 },
    { key = "casts", label = L.STATS_COL_CASTS, width = 70, right = true },
    { key = "catches", label = L.STATS_COL_CATCHES, width = 70, right = true },
    { key = "success", label = L.STATS_COL_SUCCESS, width = 70, right = true },
    { key = "perHour", label = L.STATS_COL_PER_HOUR, width = 80, right = true },
    { key = "favorite", label = L.STATS_COL_FAVORITE, width = 240 },
}

local function zone(map, input)
    if map == nil then
        return "-"
    end
    return input.mapName(map) or format(L.SUMMARY_ZONE_ID, map)
end

local function name(value)
    return value or L.STATS_UNNAMED
end

local function recordLine(text, record, value, input)
    return format(
        text,
        value,
        name(record.name),
        input.formatDate(record.session.start),
        zone(record.map, input)
    )
end

-- input: { mapName(map), formatDate(t) }. Lines of the account block and the records.
function OverviewTable.Lines(model, input)
    local account = model.account
    local lines = {
        format(L.STATS_OV_ACCOUNT, account.casts, account.catches, account.days),
    }
    for _, line in ipairs(SummaryModel.RateLines(account)) do
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = format(
        L.STATS_OV_MORE,
        HudModel.Duration(account.active),
        account.species,
        zone(account.favorite, input)
    )
    local records = model.records
    if records.catches then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.STATS_OV_RECORDS
        lines[#lines + 1] =
            recordLine(L.STATS_OV_MOST, records.catches, records.catches.value, input)
        if records.perHour then
            local rate = floor(records.perHour.value + 0.5)
            lines[#lines + 1] = recordLine(L.STATS_OV_FASTEST, records.perHour, rate, input)
        end
        local longest = HudModel.Duration(records.active.value)
        lines[#lines + 1] = recordLine(L.STATS_OV_LONGEST, records.active, longest, input)
    end
    if account.stale > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = format(L.STATS_STALE, account.stale)
    end
    return lines
end

-- One row per character (most casts first); the logged-in character is marked.
function OverviewTable.Rows(model, input)
    local rows = {}
    for _, char in ipairs(model.characters) do
        local s = char.summary
        local label = char.current and format(L.STATS_YOU, name(char.name)) or name(char.name)
        local tip = { label }
        for _, line in ipairs(HudModel.Tooltip(s)) do
            tip[#tip + 1] = line
        end
        tip[#tip + 1] =
            format(L.STATS_OV_MORE, HudModel.Duration(s.active), s.species, zone(s.favorite, input))
        if s.stale > 0 then
            tip[#tip + 1] = format(L.STATS_STALE, 1)
        end
        rows[#rows + 1] = {
            key = char.key,
            cells = {
                label,
                format("%d", s.casts),
                format("%d", s.catches),
                HudModel.Percent(s.success),
                HudModel.Rate(s.perHour),
                zone(s.favorite, input),
            },
            grey = { [4] = s.success.display ~= "full", [5] = s.perHour.display ~= "full" },
            tooltip = tip,
        }
    end
    return rows
end
