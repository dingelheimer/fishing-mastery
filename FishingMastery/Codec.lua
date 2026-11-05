-- Pure logic: packs one day's casts into chunk strings "<day>|<cast>;<cast>;..." and back.
-- A cast is comma-separated integer fields in the fixed order of Codec.FIELDS; new fields are
-- only ever appended, so old chunks decode with the new fields empty. Decoding parses the text
-- field by field and never runs loadstring.
--
-- Field rules (an empty field costs one comma; trailing empty fields are dropped):
--   dt     seconds since the previous cast in the chunk (the first: seconds into the day)
--   out    outcome code (Codec.OUTCOMES)
--   time   catches: bite time in tenths after the channel start; early clicks and getaways:
--          click time in tenths (Story 3.4; older chunks have none); empty = none
--   item, qty, q, srcType, srcId, auto: first loot slot, loot source, auto loot (catches);
--          empty = same as the previous catch in the chunk, "-" = none
--   map, sub, rank, mod, lure: cast context; empty = same as the previous cast, "-" = none
--   extra  further loot slots "id:qty:q/id:qty:q" (catches); empty = none
local _, ns = ...

local type, tostring, tonumber, floor, concat = type, tostring, tonumber, math.floor, table.concat
local find, match, gmatch, format = string.find, string.match, string.gmatch, string.format
local ipairs, pairs, pcall, error = ipairs, pairs, pcall, error

local Codec = {}
ns.Codec = Codec

Codec.CHUNK_CAP = 4000 -- characters per chunk string
Codec.DAY = 86400

Codec.FIELDS = {
    "dt",
    "out",
    "time",
    "item",
    "qty",
    "q",
    "map",
    "sub",
    "rank",
    "mod",
    "lure",
    "srcType",
    "srcId",
    "auto",
    "extra",
}

Codec.OUTCOMES = {
    unknown = 0,
    catch = 1,
    getaway = 2,
    early_click = 3,
    timeout = 4,
    cancel = 5,
    invalid_target = 6,
}
Codec.SOURCE_TYPES = { GameObject = 1, Creature = 2, Item = 3, Other = 9 }

local OUTCOME_NAMES, SOURCE_NAMES = {}, {}
for name, code in pairs(Codec.OUTCOMES) do
    OUTCOME_NAMES[code] = name
end
for name, code in pairs(Codec.SOURCE_TYPES) do
    SOURCE_NAMES[code] = name
end

-- Position of every field in a cast.
local POSITION = {}
for index, name in ipairs(Codec.FIELDS) do
    POSITION[name] = index
end

local CONTEXT = { "map", "sub", "rank", "mod", "lure" }
local CATCH = { "item", "qty", "q", "srcType", "srcId", "auto" }
-- Outcomes whose time field holds the click time.
local CLICKED = { [Codec.OUTCOMES.getaway] = true, [Codec.OUTCOMES.early_click] = true }

function Codec.Day(t)
    return floor(t / Codec.DAY)
end

local function int(value)
    if type(value) ~= "number" then
        return nil
    end
    return floor(value + 0.5)
end

-- Flat, integer-only view of a cast record (Records.Build format).
local function flatten(cast)
    local flat = {
        t = int(cast.t) or 0,
        out = Codec.OUTCOMES[cast.out] or Codec.OUTCOMES.unknown,
        map = int(cast.map),
        sub = int(cast.sub),
        rank = int(cast.rank),
        mod = int(cast.mod),
        lure = int(cast.lure),
    }
    if CLICKED[flat.out] then
        flat.click = int(cast.click)
    end
    if flat.out == Codec.OUTCOMES.catch then
        local loot = type(cast.loot) == "table" and cast.loot or {}
        local first = loot[1] or {}
        flat.bite = int(cast.bite)
        flat.item, flat.qty, flat.q = int(first.id), int(first.qty), int(first.q)
        flat.srcType = cast.srcType and (Codec.SOURCE_TYPES[cast.srcType] or 9) or nil
        flat.srcId = int(cast.srcId)
        if cast.auto ~= nil then
            flat.auto = cast.auto and 1 or 0
        end
        local extra = {}
        for i = 2, #loot do
            local slot = loot[i]
            extra[i - 1] =
                format("%s:%s:%s", int(slot.id) or "", int(slot.qty) or "", int(slot.q) or "")
        end
        flat.extra = #extra > 0 and concat(extra, "/") or nil
    end
    return flat
end

local function repeatField(value, previous)
    if value == previous then
        return ""
    end
    if value == nil then
        return "-"
    end
    return tostring(value)
end

-- Text of one cast against the chunk state (previous time, context, and catch values).
local function encodeCast(flat, state)
    local fields = {
        dt = tostring(flat.t - state.t),
        out = tostring(flat.out),
        time = tostring(flat.bite or flat.click or ""),
        extra = flat.extra or "",
    }
    for _, name in ipairs(CONTEXT) do
        fields[name] = repeatField(flat[name], state.ctx[name])
    end
    if flat.out == Codec.OUTCOMES.catch then
        for _, name in ipairs(CATCH) do
            fields[name] = repeatField(flat[name], state.catch[name])
        end
    end
    local parts, last = {}, 0
    for i, name in ipairs(Codec.FIELDS) do
        local value = fields[name] or ""
        parts[i] = value
        if value ~= "" then
            last = i
        end
    end
    return concat(parts, ",", 1, last)
end

-- Makes the cast the "previous cast" of the chunk state.
local function commit(flat, state)
    state.t = flat.t
    for _, name in ipairs(CONTEXT) do
        state.ctx[name] = flat[name]
    end
    if flat.out == Codec.OUTCOMES.catch then
        for _, name in ipairs(CATCH) do
            state.catch[name] = flat[name]
        end
    end
end

local function newChunk(day)
    return { t = day * Codec.DAY, ctx = {}, catch = {}, parts = {}, length = #tostring(day) + 1 }
end

-- Packs casts of one day (in time order) into chunk strings of at most cap characters.
function Codec.Encode(day, casts, cap)
    cap = cap or Codec.CHUNK_CAP
    local chunks = {}
    local state = newChunk(day)
    for _, cast in ipairs(casts) do
        local flat = flatten(cast)
        local text = encodeCast(flat, state)
        local added = #text + (#state.parts > 0 and 1 or 0)
        if state.length + added > cap and #state.parts > 0 then
            chunks[#chunks + 1] = day .. "|" .. concat(state.parts, ";")
            state = newChunk(day)
            text = encodeCast(flat, state)
            added = #text
        end
        commit(flat, state)
        state.parts[#state.parts + 1] = text
        state.length = state.length + added
    end
    if #state.parts > 0 then
        chunks[#chunks + 1] = day .. "|" .. concat(state.parts, ";")
    end
    return chunks
end

-- Integer field; raises for anything else (caught by Codec.Decode).
local function parseInt(text)
    if type(text) ~= "string" or not find(text, "^%-?%d+$") then
        error("bad number '" .. tostring(text) .. "'", 0)
    end
    return tonumber(text)
end

-- Splits a cast into its fields; missing trailing fields are empty.
local function splitFields(text)
    local fields, index = {}, 1
    for value in gmatch(text .. ",", "([^,]*),") do
        fields[index] = value
        index = index + 1
    end
    return fields
end

local function decodeRepeat(text, previous)
    if text == "" or text == nil then
        return previous
    end
    if text == "-" then
        return nil
    end
    return parseInt(text)
end

local function decodeExtra(text, loot)
    for slot in gmatch(text, "[^/]+") do
        local id, qty, q = match(slot, "^(%d*):(%d*):(%d*)$")
        if not id then
            error("bad loot slot '" .. slot .. "'", 0)
        end
        loot[#loot + 1] = { id = tonumber(id), qty = tonumber(qty), q = tonumber(q) }
    end
end

local function decodeChunk(chunk)
    if type(chunk) ~= "string" then
        error("chunk is not a string", 0)
    end
    local dayText, body = match(chunk, "^(%d+)|(.*)$")
    if not dayText then
        error("missing day header", 0)
    end
    local day = tonumber(dayText)
    local casts = {}
    local t, ctx, catch = day * Codec.DAY, {}, {}
    for text in gmatch(body .. ";", "([^;]*);") do
        if text == "" then
            error("empty cast", 0)
        end
        local f = splitFields(text)
        if #f > #Codec.FIELDS then
            error("too many fields", 0)
        end
        local dt = parseInt(f[POSITION.dt])
        local code = decodeRepeat(f[POSITION.out], nil)
        local out = OUTCOME_NAMES[code]
        if not out then
            error("bad outcome '" .. tostring(f[POSITION.out]) .. "'", 0)
        end
        t = t + dt
        local cast = { t = t, out = out }
        for _, name in ipairs(CONTEXT) do
            ctx[name] = decodeRepeat(f[POSITION[name]], ctx[name])
            cast[name] = ctx[name]
        end
        if CLICKED[code] then
            cast.click = decodeRepeat(f[POSITION.time], nil)
        end
        if out == "catch" then
            cast.bite = decodeRepeat(f[POSITION.time], nil)
            for _, name in ipairs(CATCH) do
                catch[name] = decodeRepeat(f[POSITION[name]], catch[name])
            end
            local loot = {}
            if catch.item then
                loot[1] = { id = catch.item, qty = catch.qty, q = catch.q }
            end
            local extra = f[POSITION.extra]
            if extra and extra ~= "" then
                decodeExtra(extra, loot)
            end
            cast.loot = loot
            cast.srcType = catch.srcType and SOURCE_NAMES[catch.srcType] or nil
            cast.srcId = catch.srcId
            if catch.auto ~= nil then
                cast.auto = catch.auto == 1
            end
        end
        casts[#casts + 1] = cast
    end
    return day, casts
end

-- Returns day, casts for a chunk, or nil and an error message for a broken chunk.
function Codec.Decode(chunk)
    local ok, day, casts = pcall(decodeChunk, chunk)
    if not ok then
        return nil, tostring(day)
    end
    return day, casts
end
