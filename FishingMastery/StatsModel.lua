-- Pure logic: the data behind the stats window. A view holds the totals of one character or of
-- several characters merged (in memory only; subzones keyed by their text, since every character
-- numbers its own). The Overview model adds lifetime numbers per character and for the account,
-- the favorite zone, and records from the session lists. Reads aggregates and session records
-- only, never the history. No frame or API calls.
local _, ns = ...

local type, pairs, ipairs, next, sort = type, pairs, ipairs, next, table.sort
local Stats, Session, Totals = ns.Stats, ns.Session, ns.Totals

local StatsModel = {}
ns.StatsModel = StatsModel

StatsModel.NO_SUBZONE = "" -- subzone key of casts without a subzone text

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

local function mergeItem(view, id, entry)
    local item = view.items[id]
    if not item then
        item = { n = 0, qty = 0, hours = {} }
        view.items[id] = item
    end
    item.n, item.qty = item.n + (entry.n or 0), item.qty + (entry.qty or 0)
    if type(entry.first) == "number" and (not item.first or entry.first < item.first) then
        item.first = entry.first
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
            local key = type(name) == "string" and name or StatsModel.NO_SUBZONE
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

local function mergeChar(view, char)
    local totals = tbl(char.totals)
    if not Totals.Current(totals) then
        view.stale = view.stale + 1
    end
    addCounts(view.outcomes, totals.outcomes)
    addCounts(view.activeByMap, totals.active)
    for day in pairs(tbl(totals.days)) do
        view.days[day] = true
    end
    for map, entry in pairs(tbl(totals.maps)) do
        local into = child(view.maps, map)
        add(into, "casts", entry.casts)
        add(into, "catches", entry.catches)
        addCounts(child(into, "items"), entry.items)
    end
    for id, entry in pairs(tbl(totals.items)) do
        mergeItem(view, id, entry)
    end
    mergeSubs(view, totals, tbl(char.subzones))
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

-- View of the characters in list (char entries): { outcomes, active, activeByMap, days, dayCount,
-- maps, items, subs, stale (characters counted by an older Totals version), fair (fair casts
-- now; single character only, for dry streaks) }.
function StatsModel.View(list)
    local view = {
        outcomes = {},
        activeByMap = {},
        days = {},
        maps = {},
        items = {},
        subs = {},
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
-- (most casts first), records }.
function StatsModel.Overview(input)
    local t = input.thresholds or Stats.DEFAULTS
    local entries, list = {}, {}
    for key, entry in pairs(tbl(input.chars)) do
        if type(entry) == "table" and next(tbl(tbl(entry.totals).outcomes)) then
            entries[#entries + 1] = { key = key, entry = entry }
            list[#list + 1] = entry
        end
    end
    local model = {
        account = StatsModel.Summary(StatsModel.View(list), t),
        characters = {},
        records = records(entries, input.now, t),
    }
    for _, char in ipairs(entries) do
        model.characters[#model.characters + 1] = {
            key = char.key,
            name = char.entry.name,
            current = char.key == input.current,
            summary = StatsModel.Summary(StatsModel.View({ char.entry }), t),
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
