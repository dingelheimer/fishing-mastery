-- Pure logic for the developer storage test. Everything lives in db.dev, never in db.chars:
--   dev.stress  a test character entry (casts, days, quarantine, totals) filled with synthetic
--               casts in steps, so the client writes and loads a large history
--   dev.lines   one chunk of about 4,000 and one of about 60,000 characters (line length check)
--   dev.loads   load time measurements (newest last, capped)
--   dev.logoutAt GetTimePreciseSec() at the last PLAYER_LOGOUT
local _, ns = ...

local type, ipairs, pairs, floor, tremove, tostring =
    type, ipairs, pairs, math.floor, table.remove, tostring

local Codec, History, Totals, Synthetic = ns.Codec, ns.History, ns.Totals, ns.Synthetic

local Stress = {}
ns.Stress = Stress

Stress.DEFAULT_CASTS = 200000
Stress.MAX_CASTS = 500000
Stress.SEED = 42 -- same seed as spec/fm/storage_stress_spec.lua
Stress.LINE_SEED = 7
Stress.LINE_LENGTHS = { 4000, 60000 }
Stress.MAX_LOADS = 10
Stress.MAX_RELOAD = 600 -- seconds; a longer gap is a logout and login, not a /reload

-- The dev table in the database, created on first use.
function Stress.Dev(db)
    if type(db.dev) ~= "table" then
        db.dev = {}
    end
    return db.dev
end

-- A new test character entry that will hold target casts.
function Stress.NewEntry(target)
    return {
        casts = {},
        days = {},
        quarantine = {},
        totals = Totals.New(),
        target = target,
        written = 0,
    }
end

-- The cast generator for a stress entry (kept outside the saved table: functions are not saved).
function Stress.Generator()
    return Synthetic.New(Synthetic.START, Stress.SEED)
end

-- Adds up to n more casts from nextCast() the way live casts are saved: pack on a day change,
-- count totals. Returns true when the entry holds its target.
function Stress.Fill(entry, nextCast, n)
    local stop = entry.written + n
    if stop > entry.target then
        stop = entry.target
    end
    while entry.written < stop do
        local cast = nextCast()
        History.PackIfNewDay(entry, cast.t)
        entry.casts[#entry.casts + 1] = cast
        Totals.Add(entry.totals, cast)
        entry.written = entry.written + 1
    end
    return entry.written >= entry.target
end

-- Packs the open casts. Returns chunk count and total characters in the chunks.
function Stress.Finish(entry)
    History.Pack(entry)
    return Stress.Size(entry.days)
end

-- Number of chunks and characters in a list of chunk strings.
function Stress.Size(days)
    local bytes = 0
    for _, chunk in ipairs(days or {}) do
        bytes = bytes + #chunk
    end
    return #(days or {}), bytes
end

-- One valid chunk per target length, each as long as the cap allows:
-- { { chunk, length, casts } }. The casts span several days; only the line length matters.
function Stress.Lines(lengths)
    local lines = {}
    for i, target in ipairs(lengths or Stress.LINE_LENGTHS) do
        local casts = Synthetic.Casts(floor(target / 4), Synthetic.START, Stress.LINE_SEED + i)
        local chunk = Codec.Encode(Codec.Day(casts[1].t), casts, target)[1]
        local _, decoded = Codec.Decode(chunk)
        lines[i] = { chunk = chunk, length = #chunk, casts = #decoded }
    end
    return lines
end

-- Checks the saved line test chunks: { { length, ok, error } }.
function Stress.CheckLines(lines)
    local results = {}
    for i, line in ipairs(lines or {}) do
        local result = { length = type(line.chunk) == "string" and #line.chunk or 0 }
        local day, casts = Codec.Decode(line.chunk)
        if not day then
            result.error = casts
        elseif result.length ~= line.length or #casts ~= line.casts then
            result.error = "length or cast count changed"
        else
            result.ok = true
        end
        results[i] = result
    end
    return results
end

-- Characters the client's SavedVariables writer needs for value: one value per line, array
-- items 1..#value bare (a hole inside #value is written as nil), other keys as `[key] = `, no
-- indentation, CRLF (strings counted without escapes). Same rules as spec/helpers/synthetic.lua.
function Stress.SavedSize(value)
    if type(value) == "string" then
        return #value + 2
    elseif type(value) ~= "table" then
        return #tostring(value)
    end
    local size, n = 4, #value -- "{", CRLF, "}"
    for i = 1, n do
        size = size + Stress.SavedSize(value[i]) + 3 -- ",", CRLF
    end
    for key, child in pairs(value) do
        if not (type(key) == "number" and key >= 1 and key <= n and key % 1 == 0) then
            -- "[", "] = ", ",", CRLF
            size = size + Stress.SavedSize(key) + Stress.SavedSize(child) + 8
        end
    end
    return size
end

-- Size of a totals table: { bytes, items, maps, hours, bands, bites (keys in all groups) }.
function Stress.TotalsSize(totals)
    local size = { bytes = Stress.SavedSize(totals), items = 0, maps = 0, hours = 0 }
    size.bands, size.bites = 0, 0
    for _ in pairs(totals.items or {}) do
        size.items = size.items + 1
    end
    for _ in pairs(totals.hours or {}) do
        size.hours = size.hours + 1
    end
    for _, bands in pairs(totals.skills or {}) do
        for _ in pairs(bands) do
            size.bands = size.bands + 1
        end
    end
    for _, groups in pairs(totals.zones or {}) do
        size.maps = size.maps + 1
        for _, group in pairs(groups) do
            for _ in pairs(group.bites or {}) do
                size.bites = size.bites + 1
            end
        end
    end
    return size
end

-- Seconds from the saved logout time to ADDON_LOADED, or nil when there is no usable pair.
function Stress.ReloadTime(dev, loadedAt)
    local logoutAt = dev.logoutAt
    if type(logoutAt) ~= "number" or type(loadedAt) ~= "number" then
        return nil
    end
    local seconds = loadedAt - logoutAt
    if seconds < 0 or seconds > Stress.MAX_RELOAD then
        return nil
    end
    return seconds
end

-- Appends a measurement to dev.loads, keeping the newest MAX_LOADS.
function Stress.AddLoad(dev, load)
    if type(dev.loads) ~= "table" then
        dev.loads = {}
    end
    local loads = dev.loads
    loads[#loads + 1] = load
    while #loads > Stress.MAX_LOADS do
        tremove(loads, 1)
    end
    return load
end
