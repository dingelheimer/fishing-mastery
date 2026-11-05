-- Optional raw capture for follow-ups F1 (buff food, camp buffs) and F2 (schools): a capped ring
-- buffer of player aura spell IDs at a fishing cast start and loot source types and object IDs
-- at fishing loot. Off by default. Keeps IDs and GUID types only: no names, no aura casters,
-- and no player GUIDs. Readers take an injected environment (_G in game).
local _, ns = ...

local type, ipairs, pairs, sort, match, tostring =
    type, ipairs, pairs, table.sort, string.match, tostring
local isSecret = issecretvalue or function()
    return false
end

local Call = ns.Context.Call

local Capture = {}
ns.Capture = Capture

Capture.CAP = 2000 -- entries kept; the oldest is overwritten
Capture.MAX_AURAS = 40
Capture.MAX_SLOTS = 10
Capture.MAX_SOURCES = 5 -- loot sources read per slot

local function plain(value)
    if isSecret(value) then
        return nil
    end
    return value
end

-- A valid ring buffer { entries, nextIndex, total }; a broken one is replaced.
function Capture.Repair(buffer)
    if type(buffer) ~= "table" or type(buffer.entries) ~= "table" then
        return { entries = {}, nextIndex = 1, total = 0 }
    end
    if type(buffer.nextIndex) ~= "number" or buffer.nextIndex < 1 then
        buffer.nextIndex = 1
    end
    buffer.total = type(buffer.total) == "number" and buffer.total or #buffer.entries
    return buffer
end

-- Stores an entry, overwriting the oldest once cap entries are kept.
function Capture.Add(buffer, entry, cap)
    cap = cap or Capture.CAP
    local index = buffer.nextIndex
    if index > cap then
        index = 1
    end
    buffer.entries[index] = entry
    buffer.nextIndex = index + 1
    buffer.total = buffer.total + 1
end

-- Entries oldest first.
function Capture.List(buffer, cap)
    cap = cap or Capture.CAP
    local entries, list = buffer.entries, {}
    local n = #entries
    local start = n >= cap and buffer.nextIndex or 1
    for i = 0, n - 1 do
        local index = (start - 1 + i) % n + 1
        list[#list + 1] = entries[index]
    end
    return list
end

-- Helpful aura spell IDs on the player; secret or missing values are skipped.
function Capture.Auras(env)
    local ids = {}
    for i = 1, Capture.MAX_AURAS do
        local aura = plain((Call(env, "C_UnitAuras.GetAuraDataByIndex", "player", i, "HELPFUL")))
        if type(aura) ~= "table" then
            break
        end
        local id = plain(aura.spellId)
        if type(id) == "number" then
            ids[#ids + 1] = id
        end
    end
    return ids
end

-- "Type:objectID" for a unit or object GUID, "Type" when the GUID has no object ID, nil for
-- players (never stored) and anything that is not a GUID.
function Capture.Source(guid)
    guid = plain(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local kind = match(guid, "^(%a+)%-")
    if not kind or kind == "Player" then
        return nil
    end
    local id = match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return id and (kind .. ":" .. id) or kind
end

-- Loot source per slot of the open loot window: { "GameObject:35591", ... } (empty slots and
-- player sources skipped; a slot with several sources adds each one).
function Capture.Sources(env)
    local count = plain((Call(env, "GetNumLootItems")))
    count = type(count) == "number" and count or 0
    if count > Capture.MAX_SLOTS then
        count = Capture.MAX_SLOTS
    end
    local sources = {}
    for slot = 1, count do
        local info = { Call(env, "GetLootSourceInfo", slot) }
        for i = 1, Capture.MAX_SOURCES * 2, 2 do
            local source = Capture.Source(info[i])
            if source then
                sources[#sources + 1] = source
            end
        end
    end
    return sources
end

-- Counts per aura spell ID and per loot source: { casts, loots, auras = { { key, count } },
-- sources = { { key, count } } }, most frequent first.
function Capture.Summary(buffer)
    local auras, sources, casts, loots = {}, {}, 0, 0
    for _, entry in pairs(buffer.entries) do
        if entry.k == "cast" then
            casts = casts + 1
            for _, id in ipairs(entry.auras or {}) do
                auras[id] = (auras[id] or 0) + 1
            end
        elseif entry.k == "loot" then
            loots = loots + 1
            for _, source in ipairs(entry.src or {}) do
                sources[source] = (sources[source] or 0) + 1
            end
        end
    end
    local function sorted(counts)
        local list = {}
        for key, count in pairs(counts) do
            list[#list + 1] = { key = tostring(key), count = count }
        end
        sort(list, function(a, b)
            if a.count ~= b.count then
                return a.count > b.count
            end
            return a.key < b.key
        end)
        return list
    end
    return { casts = casts, loots = loots, auras = sorted(auras), sources = sorted(sources) }
end
