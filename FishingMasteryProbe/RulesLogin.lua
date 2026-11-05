-- Data: report rules for the questions the login snapshot answers (Q01-Q05, Q20-Q22, Q29).
local _, ns = ...

local type, ipairs, pairs, tostring, tonumber = type, ipairs, pairs, tostring, tonumber
local format = string.format
local R = ns.ReportRules

R.Add({
    q = "Q01",
    match = R.Topic("build"),
    complete = function(list)
        return type(R.Last(list).interface) == "number"
    end,
    value = function(list)
        local d = R.Last(list)
        return format(
            "interface %s, build %s, version %s",
            tostring(d.interface),
            tostring(d.build),
            tostring(d.version)
        )
    end,
})

R.Add({
    q = "Q02",
    match = R.Topic("project"),
    value = function(list)
        local d = R.Last(list)
        return format("WOW_PROJECT_ID %s, %s constants", tostring(d.id), tostring(d.total))
    end,
})

R.Add({
    q = "Q03",
    match = R.Topic("game_rules"),
    complete = function(list)
        return type(R.Last(list).members) == "table"
    end,
    value = function(list)
        local d = R.Last(list)
        local preset = R.First(d.preset)
        if preset == nil then
            preset = R.First(d.globalPreset)
        end
        return format("preset %s, %d C_GameRules members", tostring(preset), R.CountKeys(d.members))
    end,
})

-- Q04 needs both the API and the event scan.
R.Add({
    q = "Q04",
    match = R.Topic("api_scan", "event_scan"),
    complete = function(list)
        local api = R.Any(list, function(d)
            return d.topic == "api_scan"
        end)
        local events = R.Any(list, function(d)
            return d.topic == "event_scan"
        end)
        return api and events
    end,
    value = function(list)
        local apis, apiTotal, events, eventTotal = 0, 0, 0, 0
        for _, entry in ipairs(list) do
            local d = R.Data(entry)
            if d.topic == "api_scan" then
                apiTotal = apiTotal + (tonumber(d.total) or 0)
                apis = apis + (tonumber(d.total) or 0) - (tonumber(d.missing) or 0)
            else
                for _, result in pairs(R.Table(d.result)) do
                    eventTotal = eventTotal + 1
                    events = events + (R.Table(result).registered and 1 or 0)
                end
            end
        end
        return format("APIs %d of %d, events %d of %d", apis, apiTotal, events, eventTotal)
    end,
})

R.Add({
    q = "Q05",
    match = R.Topic("global_strings"),
    value = function(list)
        return format("%s global strings", tostring(R.Last(list).total))
    end,
})

R.Add({
    q = "Q20",
    match = R.Topic("time"),
    value = function(list)
        local d = R.Last(list)
        return format(
            "game time %s, server time %s, calendar %s",
            R.YesNo(R.Table(d.gameTime).ok),
            R.YesNo(R.Table(d.serverTime).ok),
            R.YesNo(R.Table(d.calendarTime).ok)
        )
    end,
})

R.Add({
    q = "Q21",
    match = R.Topic("character_key"),
    value = function(list)
        local d = R.Last(list)
        local guid = R.Table(R.Table(d.guid).value)
        local realm = R.Table(R.Table(d.unitName).realm)
        return format(
            "GUID %s with %s segments, UnitName realm part %s",
            tostring(guid.type),
            tostring(guid.segments),
            R.YesNo(realm.present)
        )
    end,
})

-- Q22 is answered once a later session found the marker of an earlier one.
R.Add({
    q = "Q22",
    match = function(entry)
        return R.Topic("persistence")(entry) or entry.kind == "entering_world"
    end,
    complete = function(list)
        return R.Any(list, function(d)
            return R.Table(d.marker).found == true
        end)
    end,
    value = function(list)
        local sessions = R.Count(list, function(d)
            return type(d.marker) == "table"
        end)
        local found = R.Count(list, function(d)
            return R.Table(d.marker).found == true
        end)
        local reload = R.Any(list, function(d)
            return d.isReloadingUi == true
        end)
        return format(
            "marker kept in %d of %d sessions, reload seen %s",
            found,
            sessions,
            R.YesNo(reload)
        )
    end,
})

R.Add({
    q = "Q29",
    match = R.Topic("restricted_actions", "restricted_getter"),
    value = function(list)
        local members = 0
        for _, entry in ipairs(list) do
            if R.Data(entry).topic == "restricted_actions" then
                members = R.CountKeys(R.Data(entry).members)
            end
        end
        local getters = R.Count(list, function(d)
            return d.topic == "restricted_getter"
        end)
        return format("%d members, %d getter entries", members, getters)
    end,
})
