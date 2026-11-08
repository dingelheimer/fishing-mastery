-- Pure logic: the record lines of the Sessions tab from StatsModel.Overview of the chosen scope
-- (Story 9.3 moved them from the Overview). Character names are the own account's characters
-- only. No frame or API calls.
local _, ns = ...

local format, floor = string.format, math.floor
local L, HudModel = ns.L, ns.HudModel

local OverviewTable = {}
ns.OverviewTable = OverviewTable

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

-- input: { mapName(map), formatDate(t) }. Lines of the records (most catches in a session, most
-- catches per hour, longest session), or an empty list without sessions.
function OverviewTable.Records(model, input)
    local records, lines = model.records, {}
    if not records.catches then
        return lines
    end
    lines[1] = recordLine(L.STATS_OV_MOST, records.catches, records.catches.value, input)
    if records.perHour then
        local rate = floor(records.perHour.value + 0.5)
        lines[#lines + 1] = recordLine(L.STATS_OV_FASTEST, records.perHour, rate, input)
    end
    local longest = HudModel.Duration(records.active.value)
    lines[#lines + 1] = recordLine(L.STATS_OV_LONGEST, records.active, longest, input)
    return lines
end
