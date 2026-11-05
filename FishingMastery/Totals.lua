-- Pure logic: aggregates for the fast UI, updated with every cast and rebuildable from the
-- history (Statistics Methods: live aggregates first). char.totals = {
--   version  = Totals.VERSION; another value makes CastLog rebuild the totals after login
--   outcomes = { [outcome] = count },
--   days     = { [day] = { casts, catches } },
--   maps     = { [map] = { casts, catches, items = { [itemID] = quantity } } },
--   zones    = { [map] = { [lure] = group } }, lure "on" or "off",
--              group = { casts, outcomes = { [outcome] = n }, items = { [itemID] = quantity },
--                        bites = { [tenths] = catches }, clicks = { [tenths] = early clicks } },
--   hours    = { [UTC hour 0-23] = { casts, outcomes = { [outcome] = n } } },
--   skills   = { [map] = { [band] = { hooked, getaways } } }, band = lower bound of a
--              SKILL_BAND-point band of effective skill (rank + modifier),
--   items    = { [itemID] = { n (catches with it), qty, first, last (server time), best (map),
--                hours = { [UTC hour] = catches with it }, fair (fair casts counted at its last
--                catch, for the dry streak) } },
--   active   = { [map] = seconds }: Σ min(gap to the next cast, ACTIVE_CAP), and ACTIVE_CAP
--              for the latest cast,
--   subs     = { [map] = { [sub] = { casts, outcomes, items = { [itemID] = catches with it },
--                active } } }, sub = index into char.subzones or 0 (no subzone text),
--   last     = { t, map, sub } of the latest cast (for the active time),
--   cap      = the idle cap T (seconds) the active times were counted with; nil = ACTIVE_CAP,
-- }
-- map is the uiMapID or 0. Every key is an ID or a number; no names.
local _, ns = ...

local type, ipairs, pairs, floor = type, ipairs, pairs, math.floor

local Codec, History = ns.Codec, ns.History

local Totals = {}
ns.Totals = Totals

Totals.VERSION = 4 -- 3: early-click times (Story 3.4); 4: subzones, item hours (Story 3.7)
Totals.ACTIVE_CAP = ns.Options.DEFAULTS.thresholds.activeCap -- seconds; default T
-- T of this login (settings.thresholds.activeCap, set by Core before the cast log starts). Totals
-- counted with another T are not current, so the next login counts them again.
Totals.cap = Totals.ACTIVE_CAP
Totals.MIN_CAP, Totals.MAX_CAP = 30, 120

-- Sets T for this login; values outside MIN_CAP-MAX_CAP give ACTIVE_CAP. Returns T.
function Totals.SetCap(cap)
    if type(cap) ~= "number" or cap < Totals.MIN_CAP or cap > Totals.MAX_CAP then
        cap = Totals.ACTIVE_CAP
    end
    Totals.cap = cap
    return cap
end
Totals.SKILL_BAND = 5
Totals.TABLES =
    { "outcomes", "days", "maps", "zones", "hours", "skills", "items", "active", "subs" }
-- Outcomes that are not fair casts (the player's choice or no channel at all); Stats uses them.
Totals.UNFAIR = { cancel = true, unknown = true, invalid_target = true }

-- Empty totals for this login's T (the default T is not stored, so older totals stay current).
function Totals.New()
    local totals = { version = Totals.VERSION }
    if Totals.cap ~= Totals.ACTIVE_CAP then
        totals.cap = Totals.cap
    end
    for _, name in ipairs(Totals.TABLES) do
        totals[name] = {}
    end
    return totals
end

-- Missing or invalid parts are recreated; the version is kept, so stale totals stay stale.
function Totals.Repair(totals)
    if type(totals) ~= "table" then
        return Totals.New()
    end
    for _, name in ipairs(Totals.TABLES) do
        if type(totals[name]) ~= "table" then
            totals[name] = {}
        end
    end
    return totals
end

-- True when the totals were counted by this version's rules and this login's T.
function Totals.Current(totals)
    return type(totals) == "table"
        and totals.version == Totals.VERSION
        and (totals.cap or Totals.ACTIVE_CAP) == Totals.cap
end

-- list[key], created by make() when missing.
local function get(list, key, make)
    local value = list[key]
    if not value then
        value = make()
        list[key] = value
    end
    return value
end

local function newTable()
    return {}
end
local function newCounter()
    return { casts = 0, catches = 0 }
end
local function newOutcomes()
    return { casts = 0, outcomes = {} }
end
local function newGroup()
    return { casts = 0, outcomes = {}, items = {}, bites = {}, clicks = {} }
end
local function newBand()
    return { hooked = 0, getaways = 0 }
end
local function newSub()
    return { casts = 0, outcomes = {}, items = {}, active = 0 }
end

local function bump(list, key, n)
    list[key] = (list[key] or 0) + (n or 1)
end

-- Fair casts counted so far (every outcome except the UNFAIR ones).
local function fairCasts(outcomes)
    local n = 0
    for name, count in pairs(outcomes) do
        if not Totals.UNFAIR[name] then
            n = n + count
        end
    end
    return n
end

local function addItems(totals, cast, map, group, sub, hour)
    local mapItems = get(totals.maps[map], "items", newTable)
    local fair = fairCasts(totals.outcomes)
    for _, item in ipairs(cast.loot or {}) do
        local id = item.id
        if type(id) == "number" then
            local qty = item.qty or 1
            bump(mapItems, id, qty)
            bump(group.items, id, qty)
            bump(sub.items, id)
            local entry = totals.items[id]
            if not entry then
                entry = { n = 0, qty = 0, first = cast.t, best = map }
                totals.items[id] = entry
            end
            entry.n, entry.qty, entry.last = entry.n + 1, entry.qty + qty, cast.t
            entry.fair = fair
            bump(get(entry, "hours", newTable), hour)
            local best = totals.maps[entry.best]
            if (best.items[id] or 0) < mapItems[id] then
                entry.best = map
            end
        end
    end
end

local function subGroup(totals, map, sub)
    return get(get(totals.subs, map, newTable), sub, newSub)
end

-- The previous cast's active time shrinks from ACTIVE_CAP to the gap when the gap is shorter.
-- The same time is kept per subzone.
local function addActive(totals, t, map, sub)
    if type(t) ~= "number" then
        return
    end
    local last, cap = totals.last, totals.cap or Totals.ACTIVE_CAP
    if type(last) == "table" and type(last.t) == "number" then
        local gap = t - last.t
        if gap >= 0 and gap < cap then
            bump(totals.active, last.map, gap - cap)
            if type(last.map) == "number" and type(last.sub) == "number" then
                local previous = subGroup(totals, last.map, last.sub)
                previous.active = previous.active + gap - cap
            end
        end
    end
    bump(totals.active, map, cap)
    local group = subGroup(totals, map, sub)
    group.active = group.active + cap
    totals.last = { t = t, map = map, sub = sub }
end

local function addSkill(totals, cast, map, out)
    if (out ~= "catch" and out ~= "getaway") or type(cast.rank) ~= "number" then
        return
    end
    local skill = cast.rank + (type(cast.mod) == "number" and cast.mod or 0)
    local band = floor(skill / Totals.SKILL_BAND) * Totals.SKILL_BAND
    local entry = get(get(totals.skills, map, newTable), band, newBand)
    entry.hooked = entry.hooked + 1
    if out == "getaway" then
        entry.getaways = entry.getaways + 1
    end
end

-- Counts one cast (live or decoded). Casts must arrive oldest first (active time).
function Totals.Add(totals, cast)
    local out = cast.out or "unknown"
    local t = cast.t or 0
    local catch = out == "catch" and 1 or 0
    bump(totals.outcomes, out)
    local day = get(totals.days, Codec.Day(t), newCounter)
    day.casts, day.catches = day.casts + 1, day.catches + catch
    local map = type(cast.map) == "number" and cast.map or 0
    local mapEntry = get(totals.maps, map, newCounter)
    mapEntry.casts, mapEntry.catches = mapEntry.casts + 1, mapEntry.catches + catch

    local lure = type(cast.lure) == "number" and "on" or "off"
    local group = get(get(totals.zones, map, newTable), lure, newGroup)
    group.casts = group.casts + 1
    bump(group.outcomes, out)
    local hourKey = floor((t % 86400) / 3600)
    local hour = get(totals.hours, hourKey, newOutcomes)
    hour.casts = hour.casts + 1
    bump(hour.outcomes, out)
    local subKey = type(cast.sub) == "number" and cast.sub or 0
    local sub = subGroup(totals, map, subKey)
    sub.casts = sub.casts + 1
    bump(sub.outcomes, out)

    if catch == 1 then
        addItems(totals, cast, map, group, sub, hourKey)
        if type(cast.bite) == "number" then
            bump(group.bites, cast.bite)
        end
    end
    if out == "early_click" and type(cast.click) == "number" then
        bump(group.clicks, cast.click)
    end
    addSkill(totals, cast, map, out)
    addActive(totals, cast.t, map, subKey)
end

-- True when a and b hold the same values (deep comparison of the totals tables).
function Totals.Equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not Totals.Equal(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Totals counted again from every cast in the history (all at once).
function Totals.Rebuild(char)
    local totals = Totals.New()
    for cast in History.Iterate(char) do
        Totals.Add(totals, cast)
    end
    return totals
end
