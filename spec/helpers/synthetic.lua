-- Synthetic cast records (Records.Build format) for storage tests, shaped like the saved data
-- benchmark: casts every 18-58 s in sessions, 8 maps, 12 items, a realistic outcome mix, and a
-- lure on part of the casts. Deterministic for a given seed.
local M = {}

M.MAPS = { 1411, 1412, 1413, 1417, 1426, 1429, 1437, 1454 }
M.ITEMS = { 6303, 6291, 6358, 6359, 6361, 6362, 6289, 6308, 6309, 6317, 21071, 4592 }
M.OUTCOMES = {
    { "catch", 70 },
    { "getaway", 8 },
    { "early_click", 4 },
    { "timeout", 6 },
    { "cancel", 10 },
    { "invalid_target", 2 },
}

-- Small linear congruential generator so results do not depend on math.random.
local function generator(seed)
    local state = seed or 1
    return function(n)
        state = (state * 1103515245 + 12345) % 2147483648
        return state % n
    end
end

local function outcome(roll)
    local value = roll(100)
    for _, entry in ipairs(M.OUTCOMES) do
        if value < entry[2] then
            return entry[1]
        end
        value = value - entry[2]
    end
    return "catch"
end

-- Returns count casts starting at server time start (oldest first).
function M.casts(count, start, seed)
    local roll = generator(seed)
    local list, t = {}, start or 1793836800
    local map, sub, rank, lure = M.MAPS[1], 1, 1, nil
    for i = 1, count do
        if i % 150 == 1 then
            -- A new session: a pause of 2-20 hours, maybe a new map, lure on or off.
            t = t + 7200 + roll(64800)
            map = M.MAPS[roll(#M.MAPS) + 1]
            sub = roll(4) + 1
            lure = roll(3) == 0 and 263 or nil
        else
            t = t + 18 + roll(41)
        end
        if rank < 300 and roll(5) == 0 then
            rank = rank + 1
        end
        local cast = {
            t = t,
            map = map,
            sub = sub,
            rank = rank,
            mod = lure and 25 or 0,
            lure = lure,
            out = outcome(roll),
        }
        if cast.out == "catch" then
            cast.bite = 30 + roll(240)
            cast.auto = true
            cast.loot = { { id = M.ITEMS[roll(#M.ITEMS) + 1], qty = 1, q = 1 } }
            if roll(25) == 0 then
                cast.loot[2] = { id = M.ITEMS[roll(#M.ITEMS) + 1], qty = 1 + roll(3), q = 2 }
            end
            cast.srcType, cast.srcId = "GameObject", 35591
        end
        list[i] = cast
    end
    return list
end

-- Writes a table the way the Forever client writes SavedVariables: one value per line, hash keys
-- as ["key"] = value, array items bare, no indentation, CRLF line endings.
function M.write(name, value)
    local out = {}
    local function emit(v)
        local kind = type(v)
        if kind == "table" then
            out[#out + 1] = "{\r\n"
            local n = #v
            for i = 1, n do
                emit(v[i])
                out[#out + 1] = ",\r\n"
            end
            for key, child in pairs(v) do
                if not (type(key) == "number" and key >= 1 and key <= n and key % 1 == 0) then
                    out[#out + 1] = "["
                    out[#out + 1] = type(key) == "string" and string.format("%q", key)
                        or tostring(key)
                    out[#out + 1] = "] = "
                    emit(child)
                    out[#out + 1] = ",\r\n"
                end
            end
            out[#out + 1] = "}"
        elseif kind == "string" then
            out[#out + 1] = string.format("%q", v)
        else
            out[#out + 1] = tostring(v)
        end
    end
    out[#out + 1] = name .. " = "
    emit(value)
    out[#out + 1] = "\r\n"
    return table.concat(out)
end

return M
