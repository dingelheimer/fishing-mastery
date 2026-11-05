-- Pure logic: the Overview model of the stats window from StatsView views: lifetime numbers per
-- character and for the account, the favorite zone, and records from the session lists. Reads
-- aggregates and session records only, never the history. No frame or API calls.
local _, ns = ...

local type, pairs, ipairs, next, sort = type, pairs, ipairs, next, table.sort
local Stats, Session, StatsView = ns.Stats, ns.Session, ns.StatsView

local StatsModel = {}
ns.StatsModel = StatsModel

local function tbl(value)
    return type(value) == "table" and value or {}
end

-- True when map is a better favorite than best: a known map before map 0 (unknown), then more
-- catches, more casts, and the lower map ID.
local function ahead(map, entry, best, bestEntry)
    if not best then
        return true
    end
    if (best == 0) ~= (map == 0) then
        return best == 0
    end
    local a, b = entry.catches or 0, bestEntry.catches or 0
    if a ~= b then
        return a > b
    end
    a, b = entry.casts or 0, bestEntry.casts or 0
    if a ~= b then
        return a > b
    end
    return map < best
end

-- Favorite zone of a view (see ahead), or nil without casts.
function StatsModel.Favorite(view)
    local best, bestEntry = nil, nil
    for map, entry in pairs(view.maps) do
        if ahead(map, entry, best, bestEntry) then
            best, bestEntry = map, entry
        end
    end
    return best
end

-- Lifetime numbers of a view: { casts, catches, success, perHour, active, days, species,
-- favorite, stale }.
function StatsModel.Summary(view, t)
    local casts = 0
    for _, n in pairs(view.outcomes) do
        casts = casts + n
    end
    return {
        casts = casts,
        catches = Stats.Count(view.outcomes, "catch"),
        success = Stats.SuccessRate(view.outcomes, t),
        perHour = Stats.CatchesPerHour(view.outcomes, view.active, t),
        active = view.active,
        days = view.dayCount,
        species = view.species,
        favorite = StatsModel.Favorite(view),
        stale = view.stale,
    }
end

-- A record candidate replaces the current one when its value is higher (ties: the earlier one).
local function offer(records, name, value, entry)
    local current = records[name]
    if value and value > 0 and (not current or value > current.value) then
        entry.value = value
        records[name] = entry
    end
end

-- Records over the sessions of every character: most catches, most catches per hour (sessions
-- with at least greyBelow fair casts), and the longest active time. Each: { value, name,
-- session, map (first zone) }.
local function records(chars, now, t)
    local result = {}
    for _, char in ipairs(chars) do
        for _, session in ipairs(tbl(char.entry.sessions)) do
            local function entry()
                return { name = char.entry.name, session = session, map = tbl(session.zones)[1] }
            end
            local active = Session.Counted(session, now, t.activeCap)
            offer(result, "catches", session.catches, entry())
            offer(result, "active", active, entry())
            local counts = tbl(session.counts)
            if Stats.Fair(counts) >= t.greyBelow then
                offer(result, "perHour", Stats.CatchesPerHour(counts, active, t).rate, entry())
            end
        end
    end
    return result
end

-- input: { chars (db.chars), current (key of the logged-in character), now (server time),
-- thresholds }. Returns { account = Summary, characters = { { key, name, current, summary } }
-- (most casts first), records, days (the account's { [day] = { casts, catches } }) }.
function StatsModel.Overview(input)
    local t = input.thresholds or Stats.DEFAULTS
    local entries, list = {}, {}
    for key, entry in pairs(tbl(input.chars)) do
        if type(entry) == "table" and next(tbl(tbl(entry.totals).outcomes)) then
            entries[#entries + 1] = { key = key, entry = entry }
            list[#list + 1] = entry
        end
    end
    local accountView = StatsView.Build(list)
    local model = {
        account = StatsModel.Summary(accountView, t),
        days = accountView.days,
        characters = {},
        records = records(entries, input.now, t),
    }
    for _, char in ipairs(entries) do
        model.characters[#model.characters + 1] = {
            key = char.key,
            name = char.entry.name,
            current = char.key == input.current,
            summary = StatsModel.Summary(StatsView.Build({ char.entry }), t),
        }
    end
    sort(model.characters, function(a, b)
        if a.summary.casts ~= b.summary.casts then
            return a.summary.casts > b.summary.casts
        end
        return a.key < b.key
    end)
    return model
end
