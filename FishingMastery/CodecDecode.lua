-- Pure logic: decodes a chunk string of Codec (Codec.lua) back into casts. Parses field by
-- field and never runs loadstring; a broken chunk returns nil and an error message.
local _, ns = ...

local type, tostring, tonumber = type, tostring, tonumber
local find, match, gmatch = string.find, string.match, string.gmatch
local ipairs, pcall, error = ipairs, pcall, error

local Codec = ns.Codec
local POSITION, CONTEXT, CATCH, CLICKED = Codec.POSITION, Codec.CONTEXT, Codec.CATCH, Codec.CLICKED
local OUTCOME_NAMES, SOURCE_NAMES = Codec.OUTCOME_NAMES, Codec.SOURCE_NAMES

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
