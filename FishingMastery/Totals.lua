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
--   items    = { [itemID] = { n (catches with it), qty, first, last (server time), best (map) } },
--   active   = { [map] = seconds }: Σ min(gap to the next cast, ACTIVE_CAP), and ACTIVE_CAP
--              for the latest cast,
--   last     = { t, map } of the latest cast (for the active time),
-- }
-- map is the uiMapID or 0. Every key is an ID or a number; no names.
local _, ns = ...

local type, ipairs, pairs, floor = type, ipairs, pairs, math.floor

local Codec, History = ns.Codec, ns.History

local Totals = {}
ns.Totals = Totals

Totals.VERSION = 3 -- 3: early-click times (Story 3.4)
Totals.ACTIVE_CAP = 60 -- seconds; T in Statistics Methods
Totals.SKILL_BAND = 5
Totals.TABLES = { "outcomes", "days", "maps", "zones", "hours", "skills", "items", "active" }

function Totals.New()
    local totals = { version = Totals.VERSION }
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

-- True when the totals were counted by this version's rules.
function Totals.Current(totals)
    return type(totals) == "table" and totals.version == Totals.VERSION
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

local function bump(list, key, n)
    list[key] = (list[key] or 0) + (n or 1)
end

local function addItems(totals, cast, map, group)
    local mapItems = get(totals.maps[map], "items", newTable)
    for _, item in ipairs(cast.loot or {}) do
        local id = item.id
        if type(id) == "number" then
            local qty = item.qty or 1
            bump(mapItems, id, qty)
            bump(group.items, id, qty)
            local entry = totals.items[id]
            if not entry then
                entry = { n = 0, qty = 0, first = cast.t, best = map }
                totals.items[id] = entry
            end
            entry.n, entry.qty, entry.last = entry.n + 1, entry.qty + qty, cast.t
            local best = totals.maps[entry.best]
            if (best.items[id] or 0) < mapItems[id] then
                entry.best = map
            end
        end
    end
end

-- The previous cast's active time shrinks from ACTIVE_CAP to the gap when the gap is shorter.
local function addActive(totals, t, map)
    if type(t) ~= "number" then
        return
    end
    local last, cap = totals.last, Totals.ACTIVE_CAP
    if type(last) == "table" and type(last.t) == "number" then
        local gap = t - last.t
        if gap >= 0 and gap < cap then
            bump(totals.active, last.map, gap - cap)
        end
    end
    bump(totals.active, map, cap)
    totals.last = { t = t, map = map }
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
    local hour = get(totals.hours, floor((t % 86400) / 3600), newOutcomes)
    hour.casts = hour.casts + 1
    bump(hour.outcomes, out)

    if catch == 1 then
        addItems(totals, cast, map, group)
        if type(cast.bite) == "number" then
            bump(group.bites, cast.bite)
        end
    end
    if out == "early_click" and type(cast.click) == "number" then
        bump(group.clicks, cast.click)
    end
    addSkill(totals, cast, map, out)
    addActive(totals, cast.t, map)
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
