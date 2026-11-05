-- Pure logic: the Skill tab's history scan (Statistics Methods: other filters scan in steps). It
-- decodes the packed day chunks a few per step, as the load check does, and keeps per fishing rank
-- the time of its first cast and the catches made at it. The open casts are added on every
-- Result, so new casts show without a new scan; chunks packed later continue the scan. A replaced
-- or shortened chunk list (import, quarantine) starts it over. Never changes the history. No
-- frame or API calls.
local _, ns = ...

local type, ipairs, pairs = type, ipairs, pairs
local Codec = ns.Codec

local SkillScan = {}
ns.SkillScan = SkillScan

SkillScan.CHUNKS = 10 -- chunks per step (History.CHECK_CHUNKS)

local function reset(scan, days)
    scan.days, scan.index, scan.last = days, 0, nil
    scan.ranks, scan.start, scan.latest = {}, nil, nil
end

-- An empty scan; the first Step binds it to a character's chunk list.
function SkillScan.New()
    local scan = {}
    reset(scan, nil)
    return scan
end

-- Counts one cast into acc { ranks = { [rank] = { first, catches } }, start, latest }; casts
-- without a rank or time are skipped. Casts arrive oldest first.
local function addCast(acc, cast)
    local rank, t = cast.rank, cast.t
    if type(rank) ~= "number" or type(t) ~= "number" then
        return
    end
    local entry = acc.ranks[rank]
    if not entry then
        entry = { first = t, catches = 0 }
        acc.ranks[rank] = entry
    end
    if cast.out == "catch" then
        entry.catches = entry.catches + 1
    end
    acc.latest = { t = t, rank = rank }
    acc.start = acc.start or acc.latest
end

-- True when the chunk list is not the one the scan has read so far.
local function changed(scan, days)
    if scan.days ~= days or scan.index > #days then
        return true
    end
    return scan.index > 0 and days[scan.index] ~= scan.last
end

-- Reads up to maxChunks more chunks of char.days (broken chunks are skipped; the load check
-- quarantines them). Returns true when every chunk has been read.
function SkillScan.Step(scan, char, maxChunks)
    local days = type(char.days) == "table" and char.days or {}
    if changed(scan, days) then
        reset(scan, days)
    end
    local budget = maxChunks or SkillScan.CHUNKS
    while scan.index < #days and budget > 0 do
        budget = budget - 1
        local i = scan.index + 1
        local day, casts = Codec.Decode(days[i])
        if day then
            for _, cast in ipairs(casts) do
                addCast(scan, cast)
            end
        end
        scan.index, scan.last = i, days[i]
    end
    return scan.index >= #days
end

-- Chunks read and chunks in total.
function SkillScan.Progress(scan)
    return scan.index, scan.days and #scan.days or 0
end

-- The scan's counts with the open casts added: { ranks, start, latest } (start and latest are
-- { t, rank } of the first and last cast with a rank).
function SkillScan.Result(scan, char)
    local acc = { ranks = {}, start = scan.start, latest = scan.latest }
    for rank, entry in pairs(scan.ranks) do
        acc.ranks[rank] = { first = entry.first, catches = entry.catches }
    end
    for _, cast in ipairs(type(char.casts) == "table" and char.casts or {}) do
        addCast(acc, cast)
    end
    return acc
end
