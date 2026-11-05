-- Pure logic: aggregates for the fast UI, updated with every cast and rebuildable from the
-- history. char.totals = {
--   outcomes = { [outcome] = count },
--   days = { [day] = { casts, catches } },
--   maps = { [uiMapID or 0] = { casts, catches, items = { [itemID] = quantity } } },
-- }
local _, ns = ...

local type, ipairs = type, ipairs

local Codec, History = ns.Codec, ns.History

local Totals = {}
ns.Totals = Totals

function Totals.New()
    return { outcomes = {}, days = {}, maps = {} }
end

-- Missing or invalid parts are recreated.
function Totals.Repair(totals)
    if type(totals) ~= "table" then
        return Totals.New()
    end
    for _, name in ipairs({ "outcomes", "days", "maps" }) do
        if type(totals[name]) ~= "table" then
            totals[name] = {}
        end
    end
    return totals
end

local function entry(list, key)
    local value = list[key]
    if not value then
        value = { casts = 0, catches = 0 }
        list[key] = value
    end
    return value
end

-- Counts one cast (live or decoded).
function Totals.Add(totals, cast)
    local out = cast.out or "unknown"
    totals.outcomes[out] = (totals.outcomes[out] or 0) + 1
    local catch = out == "catch" and 1 or 0
    local day = entry(totals.days, Codec.Day(cast.t or 0))
    day.casts, day.catches = day.casts + 1, day.catches + catch
    local map = entry(totals.maps, type(cast.map) == "number" and cast.map or 0)
    map.casts, map.catches = map.casts + 1, map.catches + catch
    if catch == 1 then
        map.items = map.items or {}
        for _, item in ipairs(cast.loot or {}) do
            if type(item.id) == "number" then
                map.items[item.id] = (map.items[item.id] or 0) + (item.qty or 1)
            end
        end
    end
end

-- Totals counted again from every cast in the history.
function Totals.Rebuild(char)
    local totals = Totals.New()
    for cast in History.Iterate(char) do
        Totals.Add(totals, cast)
    end
    return totals
end
