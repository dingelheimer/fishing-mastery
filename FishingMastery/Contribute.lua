-- Pure logic: the contribution export (module 7, Story 7.1), counts only, for sharing Forever
-- catch data. Built from the totals of every character on the account (StatsView merges them;
-- subzone texts resolve to AreaTable IDs with Area:Resolve and are summed per area):
--   FMC!<format>!<token>!<addon version>!<client build>!<checksum>
--   A!<area>!<casts>!<item>:<catches>,...       per resolved area
--   M!<map>!<casts>!<item>:<catches>,...        places without a resolved area
--   S!<area or m<map>>!<band>!<hooked>!<getaways> per 5-point band of effective skill
--   L!<map>!<casts with lure>!<catches with lure> per map
-- catches: casts that caught the item. No times, days, subzone texts, names, keys, or realms;
-- only "!", ":", "," separators, never "|". Lines are sorted; the checksum (Export.Checksum)
-- covers every line after the header, joined with "\n". No frame or API calls.
local _, ns = ...

local type, pairs, ipairs, tostring, concat, sort, format, gsub, floor =
    type, pairs, ipairs, tostring, table.concat, table.sort, string.format, string.gsub, math.floor

local StatsView, Export = ns.StatsView, ns.Export

local Contribute = {}
ns.Contribute = Contribute

Contribute.FORMAT = 1
Contribute.TOKEN_DIGITS = 8

-- A new account token: TOKEN_DIGITS random hex digits. random(lo, hi) is math.random.
function Contribute.NewToken(random)
    local digits = {}
    for i = 1, Contribute.TOKEN_DIGITS do
        digits[i] = format("%x", random(0, 15))
    end
    return concat(digits)
end

-- A token as saved, or nil when it is not TOKEN_DIGITS hex digits.
function Contribute.ValidToken(token)
    return type(token) == "string"
            and #token == Contribute.TOKEN_DIGITS
            and token:match("^%x+$") ~= nil
            and token:lower()
        or nil
end

-- A header field without separators or spaces ("1.0.0", "70790", "dev").
local function field(value)
    local text = gsub(tostring(value or ""), "[^%w%.%-]", "")
    return text ~= "" and text or "-"
end

local function child(list, key)
    local value = list[key]
    if not value then
        value = { casts = 0, items = {} }
        list[key] = value
    end
    return value
end

local function add(into, group)
    into.casts = into.casts + (group.casts or 0)
    for id, n in pairs(group.items or {}) do
        into.items[id] = (into.items[id] or 0) + n
    end
end

local function keys(list)
    local out = {}
    for key in pairs(list) do
        out[#out + 1] = key
    end
    sort(out, function(a, b)
        if type(a) == type(b) then
            return a < b
        end
        return type(a) == "number"
    end)
    return out
end

local function items(list)
    local out = {}
    for _, id in ipairs(keys(list)) do
        if list[id] > 0 then
            out[#out + 1] = id .. ":" .. list[id]
        end
    end
    return concat(out, ",")
end

-- Places and bands of a merged view: { areas = { [area] = group }, maps = { [map] = group },
-- bands = { [key] = { [band] = { hooked, getaways } } } }, key an area ID or "m<map>".
function Contribute.Collect(view, areas)
    local placed = { areas = {}, maps = {}, bands = {} }
    local function resolve(map, text)
        return areas and areas:Resolve(map, text ~= StatsView.NO_SUBZONE and text or nil) or nil
    end
    for map, subs in pairs(view.subs or {}) do
        for text, group in pairs(subs) do
            local area = resolve(map, text)
            add(area and child(placed.areas, area) or child(placed.maps, map), group)
        end
    end
    for map, subs in pairs(view.subskills or {}) do
        for text, bands in pairs(subs) do
            local area = resolve(map, text)
            local key = area or ("m" .. map)
            local into = placed.bands[key] or {}
            placed.bands[key] = into
            for band, entry in pairs(bands) do
                local b = into[band] or { hooked = 0, getaways = 0 }
                into[band] = b
                b.hooked = b.hooked + (entry.hooked or 0)
                b.getaways = b.getaways + (entry.getaways or 0)
            end
        end
    end
    return placed
end

-- The body lines (without the header), sorted.
function Contribute.Lines(view, areas)
    local placed = Contribute.Collect(view, areas)
    local lines = {}
    for _, area in ipairs(keys(placed.areas)) do
        local g = placed.areas[area]
        lines[#lines + 1] = format("A!%d!%d!%s", area, g.casts, items(g.items))
    end
    for _, map in ipairs(keys(placed.maps)) do
        local g = placed.maps[map]
        lines[#lines + 1] = format("M!%d!%d!%s", map, g.casts, items(g.items))
    end
    for _, key in ipairs(keys(placed.bands)) do
        local bands = placed.bands[key]
        for _, band in ipairs(keys(bands)) do
            local b = bands[band]
            if b.hooked > 0 then
                lines[#lines + 1] =
                    format("S!%s!%d!%d!%d", tostring(key), floor(band), b.hooked, b.getaways)
            end
        end
    end
    for _, map in ipairs(keys(view.zones or {})) do
        local on = view.zones[map].on
        if on and (on.casts or 0) > 0 then
            lines[#lines + 1] = format("L!%d!%d!%d", map, on.casts, (on.outcomes or {}).catch or 0)
        end
    end
    return lines
end

-- The contribution text. chars: the account's character entries (FishingMasteryDB.chars);
-- info: { token, version, build }.
function Contribute.Build(chars, areas, info)
    local list = {}
    for _, key in ipairs(keys(chars or {})) do
        list[#list + 1] = chars[key]
    end
    local lines = Contribute.Lines(StatsView.Build(list), areas)
    local body = concat(lines, "\n")
    local header = format(
        "FMC!%d!%s!%s!%s!%s",
        Contribute.FORMAT,
        field(info.token),
        field(info.version),
        field(info.build),
        Export.Checksum(body)
    )
    if body == "" then
        return header, 0
    end
    return header .. "\n" .. body, #lines
end
