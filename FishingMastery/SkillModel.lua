-- Pure logic: the Skill tab's numbers from a SkillScan result. Rank over time (the first cast at
-- every rank), catches per skill point (skill-ups per catch as a proportion with its Wilson range,
-- inverted like Stats.ExpectedCasts), and the forecast to the next rank cap and to 300 at the
-- recent pace. A point counts only when its whole rank was tracked: the first tracked rank, the
-- current one, and ranks at a trainer cap (catches there may have been made at the cap) are left
-- out. No frame or API calls.
local _, ns = ...

local type, pairs, ipairs, sort, floor, min, max, huge =
    type, pairs, ipairs, table.sort, math.floor, math.min, math.max, math.huge
local Stats = ns.Stats

local SkillModel = {}
ns.SkillModel = SkillModel

SkillModel.TOP = 300
SkillModel.CAP_STEP = 75 -- trainer caps 75, 150, 225, 300
SkillModel.CAPS = { [75] = true, [150] = true, [225] = true }
SkillModel.RECENT = 10 -- skill points of the recent pace
SkillModel.BAND = 25 -- ranks per bar of the catches-per-point chart

-- Catches per point of k points in c catches: { k, c, mean, low, high, display }.
function SkillModel.Pace(k, c, t)
    c = max(c, k) -- every point needs a catch; casts without a rank can hide some
    local proportion = Stats.Proportion(k, c, t)
    local result = { k = k, c = c, display = proportion.display }
    local expected = Stats.ExpectedCasts(proportion)
    if k > 0 and expected then
        result.mean, result.low, result.high = expected.mean, expected.low, expected.high
    end
    return result
end

-- The ranks whose whole span was tracked, highest first.
local function completed(first, rank)
    local list = {}
    for r = rank - 1, first + 1, -1 do
        if not SkillModel.CAPS[r] then
            list[#list + 1] = r
        end
    end
    return list
end

local function catchesAt(ranks, r)
    return ranks[r] and ranks[r].catches or 0
end

-- Pace of the last RECENT completed points.
local function recent(ranks, list, t)
    local k, c = 0, 0
    for i = 1, min(#list, SkillModel.RECENT) do
        k, c = k + 1, c + catchesAt(ranks, list[i])
    end
    return SkillModel.Pace(k, c, t)
end

-- One pace per BAND of ranks, lowest band first: { { from, to, pace } }.
local function bands(ranks, list, t)
    local sums, keys = {}, {}
    for _, r in ipairs(list) do
        local band = floor(r / SkillModel.BAND) * SkillModel.BAND
        local sum = sums[band]
        if not sum then
            sum = { k = 0, c = 0 }
            sums[band] = sum
            keys[#keys + 1] = band
        end
        sum.k, sum.c = sum.k + 1, sum.c + catchesAt(ranks, r)
    end
    sort(keys)
    local result = {}
    for i, band in ipairs(keys) do
        local sum = sums[band]
        result[i] = {
            from = band,
            to = band + SkillModel.BAND - 1,
            pace = SkillModel.Pace(sum.k, sum.c, t),
        }
    end
    return result
end

-- Catches and active seconds for points at a pace: { points, mean, low, high, seconds }.
local function forecast(points, pace, perHour)
    local result = { points = points }
    if pace.mean then
        result.mean, result.low, result.high =
            points * pace.mean, points * pace.low, points * pace.high
        if perHour and perHour.rate and perHour.rate > 0 and perHour.display ~= "count" then
            result.seconds = result.mean / perHour.rate * 3600
        end
    end
    return result
end

-- The next rank cap above rank: the saved cap when it is higher, else the next step of 75.
function SkillModel.NextCap(rank, cap)
    if type(cap) == "number" and cap > rank then
        return cap
    end
    return min(SkillModel.TOP, (floor(rank / SkillModel.CAP_STEP) + 1) * SkillModel.CAP_STEP)
end

-- input: { result (SkillScan.Result), rank (char.fishingRank), max (char.fishingMax), perHour
-- (Stats.CatchesPerHour of the character), thresholds }. Returns nil without a cast with a rank,
-- else { rank, max, first, since, timeline = { { t, rank } }, pace, bands, toCap, toTop, atCap }.
function SkillModel.Build(input)
    local result, t = input.result, input.thresholds or Stats.DEFAULTS
    local first, highest = huge, nil
    for r in pairs(result.ranks) do
        first, highest = min(first, r), max(highest or r, r)
    end
    if not highest then
        return nil
    end
    local rank = max(highest, type(input.rank) == "number" and input.rank or highest)
    local timeline = {}
    for r, entry in pairs(result.ranks) do
        timeline[#timeline + 1] = { t = entry.first, rank = r }
    end
    sort(timeline, function(a, b)
        return a.t < b.t or (a.t == b.t and a.rank < b.rank)
    end)
    local latest = result.latest
    if latest and (latest.t > timeline[#timeline].t or rank > highest) then
        timeline[#timeline + 1] = { t = latest.t, rank = rank }
    end
    local list = completed(first, rank)
    local pace = recent(result.ranks, list, t)
    local model = {
        rank = rank,
        max = input.max,
        first = first,
        firstTime = result.start and result.start.t,
        since = catchesAt(result.ranks, rank),
        timeline = timeline,
        pace = pace,
        bands = bands(result.ranks, list, t),
    }
    if rank >= SkillModel.TOP then
        return model
    end
    if type(input.max) == "number" and rank >= input.max then
        model.atCap = true
    else
        local cap = SkillModel.NextCap(rank, input.max)
        model.toCap = forecast(cap - rank, pace, input.perHour)
        model.toCap.cap = cap
    end
    model.toTop = forecast(SkillModel.TOP - rank, pace, input.perHour)
    return model
end
