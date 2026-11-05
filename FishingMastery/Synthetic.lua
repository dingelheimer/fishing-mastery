-- Pure logic: synthetic cast records (Records.Build format) for the developer stress test and the
-- storage specs, shaped like the saved data benchmark: casts every 18-58 s in sessions of 150,
-- 8 maps, 12 items, a realistic outcome mix, and a lure on part of the sessions. Deterministic
-- for a given seed. Never written into a real character entry.
local _, ns = ...

local ipairs = ipairs

local Synthetic = {}
ns.Synthetic = Synthetic

Synthetic.START = 1793836800 -- default server time of the first cast
Synthetic.MAPS = { 1411, 1412, 1413, 1417, 1426, 1429, 1437, 1454 }
Synthetic.ITEMS = { 6303, 6291, 6358, 6359, 6361, 6362, 6289, 6308, 6309, 6317, 21071, 4592 }
Synthetic.OUTCOMES = {
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
    for _, entry in ipairs(Synthetic.OUTCOMES) do
        if value < entry[2] then
            return entry[1]
        end
        value = value - entry[2]
    end
    return "catch"
end

-- Returns next(), which gives one cast per call, oldest first, starting at server time start.
function Synthetic.New(start, seed)
    local roll = generator(seed)
    local t, i = start or Synthetic.START, 0
    local map, sub, rank, lure = Synthetic.MAPS[1], 1, 1, nil
    local maps, items = Synthetic.MAPS, Synthetic.ITEMS
    return function()
        i = i + 1
        if i % 150 == 1 then
            -- A new session: a pause of 2-20 hours, maybe a new map, lure on or off.
            t = t + 7200 + roll(64800)
            map = maps[roll(#maps) + 1]
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
            cast.loot = { { id = items[roll(#items) + 1], qty = 1, q = 1 } }
            if roll(25) == 0 then
                cast.loot[2] = { id = items[roll(#items) + 1], qty = 1 + roll(3), q = 2 }
            end
            cast.srcType, cast.srcId = "GameObject", 35591
        end
        return cast
    end
end

-- Returns count casts starting at server time start (oldest first).
function Synthetic.Casts(count, start, seed)
    local nextCast, list = Synthetic.New(start, seed), {}
    for i = 1, count do
        list[i] = nextCast()
    end
    return list
end
