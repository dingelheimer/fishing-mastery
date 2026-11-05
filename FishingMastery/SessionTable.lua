-- Pure logic: the Sessions tab: one row per session of the chosen characters with date, character,
-- zone, active time, casts, catches, and skill change; sortable by every column (newest first by
-- default); rates with ranges in the tooltip. No frame or API calls.
local _, ns = ...

local format, ipairs, type = string.format, ipairs, type
local L, Stats, Session, HudModel, StatsTables =
    ns.L, ns.Stats, ns.Session, ns.HudModel, ns.StatsTables

local SessionTable = {}
ns.SessionTable = SessionTable

SessionTable.COLUMNS = {
    { key = "start", label = L.STATS_COL_DATE, width = 120 },
    { key = "name", label = L.STATS_COL_CHARACTER, width = 110 },
    { key = "zone", label = L.STATS_COL_ZONE_ONLY, width = 170 },
    { key = "active", label = L.STATS_COL_ACTIVE, width = 70, right = true },
    { key = "casts", label = L.STATS_COL_CASTS, width = 60, right = true },
    { key = "catches", label = L.STATS_COL_CATCHES, width = 60, right = true },
    { key = "skill", label = L.STATS_COL_SKILL, width = 110, right = true },
}
-- Columns sorted A-Z on their first click; the others start with the largest value.
SessionTable.TEXT_KEYS = { name = true, zone = true }

local function zoneText(session, mapName)
    local zones = type(session.zones) == "table" and session.zones or {}
    if #zones == 0 then
        return nil
    end
    local name = mapName(zones[1]) or format(L.SUMMARY_ZONE_ID, zones[1])
    if #zones > 1 then
        name = format(L.STATS_MORE_ZONES, name, #zones - 1)
    end
    return name
end

local function skillText(session)
    if type(session.skillStart) ~= "number" or type(session.skill) ~= "number" then
        return "-"
    end
    return format(
        L.STATS_SKILL_CHANGE,
        Session.SkillUps(session),
        session.skillStart,
        session.skill
    )
end

local function endText(session)
    if not session.ended then
        return L.STATS_SESSION_OPEN
    end
    return L["STATS_SESSION_" .. (session.endReason or "logout")] or L.STATS_SESSION_logout
end

local function row(session, name, index, input)
    local t = input.thresholds or Stats.DEFAULTS
    local counts = type(session.counts) == "table" and session.counts or {}
    local active = Session.Counted(session, input.now, t.activeCap)
    local zone = zoneText(session, input.mapName)
    local tip = { input.formatTime(session.start) }
    for _, line in
        ipairs(HudModel.Tooltip({
            success = Stats.SuccessRate(counts, t),
            perHour = Stats.CatchesPerHour(counts, active, t),
        }))
    do
        tip[#tip + 1] = line
    end
    local total = (session.ended or input.now or session.last) - session.start
    tip[#tip + 1] =
        format(L.STATS_SESSION_TIME, HudModel.Duration(active), HudModel.Duration(total))
    tip[#tip + 1] = endText(session)
    return {
        key = index,
        order = index,
        start = session.start,
        name = name,
        zone = zone,
        active = active,
        casts = session.casts,
        catches = session.catches,
        skill = Session.SkillUps(session),
        cells = {
            input.formatTime(session.start),
            name or L.STATS_UNNAMED,
            zone or "-",
            HudModel.Duration(active),
            format("%d", session.casts or 0),
            format("%d", session.catches or 0),
            skillText(session),
        },
        tooltip = tip,
    }
end

-- chars: { { entry (character), name } }. input: { mapName(map), formatTime(t), now,
-- thresholds, sort = { key, descending } }. Returns the sorted rows.
function SessionTable.Rows(chars, input)
    local rows = {}
    for _, char in ipairs(chars) do
        local sessions = type(char.entry.sessions) == "table" and char.entry.sessions or {}
        for _, session in ipairs(sessions) do
            if type(session) == "table" and type(session.start) == "number" then
                rows[#rows + 1] = row(session, char.name, #rows + 1, input)
            end
        end
    end
    local order = input.sort or { key = "start", descending = true }
    return StatsTables.Sort(rows, function(r)
        return r[order.key]
    end, order.descending)
end
