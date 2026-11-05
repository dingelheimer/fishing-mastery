-- Pure logic: the statistics engine. Turns counts from the aggregates (Totals.lua) into displayable
-- numbers with 95% ranges and display rules, so every screen shows the same values
-- (Statistics Methods). No frame or API calls. Proportions and ranges are fractions (0-1).
local _, ns = ...

local type, sqrt, floor, ceil, huge, min, max, pairs, ipairs, sort =
    type, math.sqrt, math.floor, math.ceil, math.huge, math.min, math.max, pairs, ipairs, table.sort

local Stats = {}
ns.Stats = Stats

-- Every threshold in one table; the settings panel may override countBelow, greyBelow, and T
-- (defaults in Options.DEFAULTS.thresholds).
local SETTINGS = ns.Options.DEFAULTS.thresholds
Stats.DEFAULTS = {
    z = 1.96, -- 95% ranges
    countBelow = SETTINGS.countBelow, -- n below this: count only, no percentage
    greyBelow = SETTINGS.greyBelow, -- n below this: percentage greyed ("few casts")
    narrowWidth = 0.10, -- a range narrower than this is never greyed
    blendWeight = 20, -- m pseudo-catches of the reference share (module 3)
    activeCap = ns.Totals.ACTIVE_CAP, -- seconds, T
}

-- Outcomes that are not fair casts (the player's choice or no channel at all).
Stats.UNFAIR = ns.Totals.UNFAIR

-- DEFAULTS with the keys of overrides (e.g. db.settings.thresholds) that are numbers; activeCap
-- is always this login's T (Totals.cap), so open sessions and the totals use the same T.
function Stats.Thresholds(overrides)
    local result = {}
    for key, value in pairs(Stats.DEFAULTS) do
        local custom = type(overrides) == "table" and overrides[key]
        result[key] = type(custom) == "number" and custom or value
    end
    result.activeCap = ns.Totals.cap
    return result
end

local function thresholds(t)
    return t or Stats.DEFAULTS
end

local function clamp(x)
    return max(0, min(1, x))
end

-- Wilson score interval for k successes in n trials: low, high; nil for n <= 0.
function Stats.Wilson(k, n, z)
    if type(n) ~= "number" or n <= 0 or type(k) ~= "number" then
        return nil
    end
    z = z or Stats.DEFAULTS.z
    local p, z2 = k / n, z * z
    local denominator = 1 + z2 / n
    local center = (p + z2 / (2 * n)) / denominator
    local half = z * sqrt(p * (1 - p) / n + z2 / (4 * n * n)) / denominator
    local low, high = clamp(center - half), clamp(center + half)
    if k <= 0 then
        low = 0
    elseif k >= n then
        high = 1
    end
    return low, high
end

-- Byar's approximation of the Poisson range for a count c: low, high (counts).
function Stats.Byar(c, z)
    if type(c) ~= "number" or c < 0 then
        return nil
    end
    z = z or Stats.DEFAULTS.z
    local low = 0
    if c > 0 then
        low = c * (1 - 1 / (9 * c) - z / (3 * sqrt(c))) ^ 3
    end
    local c1 = c + 1
    local high = c1 * (1 - 1 / (9 * c1) + z / (3 * sqrt(c1))) ^ 3
    return max(0, low), high
end

-- Display rule for a sample of n: "count" (count only), "few" (greyed), or "full".
function Stats.Display(n, low, high, t)
    t = thresholds(t)
    if type(n) ~= "number" or n < t.countBelow then
        return "count"
    end
    if n < t.greyBelow and not (low and high and high - low < t.narrowWidth) then
        return "few"
    end
    return "full"
end

-- A proportion k of n: { k, n, p, low, high, display }; p, low, and high are nil for n = 0.
function Stats.Proportion(k, n, t)
    t = thresholds(t)
    k, n = k or 0, n or 0
    local result = { k = k, n = n }
    if n > 0 then
        result.p = k / n
        result.low, result.high = Stats.Wilson(k, n, t.z)
    end
    result.display = Stats.Display(n, result.low, result.high, t)
    return result
end

-- A count per hour of active time: { count, seconds, n, rate, low, high, display }; the display
-- follows the sample n (casts) behind the count. rate is nil without active time.
function Stats.PerHour(count, seconds, n, t)
    t = thresholds(t)
    count = count or 0
    local result = { count = count, seconds = seconds or 0, n = n or 0 }
    if result.seconds > 0 then
        local hours = result.seconds / 3600
        local low, high = Stats.Byar(count, t.z)
        result.rate, result.low, result.high = count / hours, low / hours, high / hours
    end
    result.display = Stats.Display(result.n, nil, nil, t)
    return result
end

-- Newcombe hybrid score range of p1 - p2 (method 10): { d, low, high, clear }; clear means the
-- range excludes 0. nil when a sample is empty.
function Stats.Difference(k1, n1, k2, n2, t)
    t = thresholds(t)
    local l1, u1 = Stats.Wilson(k1, n1, t.z)
    local l2, u2 = Stats.Wilson(k2, n2, t.z)
    if not (l1 and l2) then
        return nil
    end
    local p1, p2 = k1 / n1, k2 / n2
    local d = p1 - p2
    local low = d - sqrt((p1 - l1) ^ 2 + (u2 - p2) ^ 2)
    local high = d + sqrt((u1 - p1) ^ 2 + (p2 - l2) ^ 2)
    return { d = d, low = low, high = high, clear = low > 0 or high < 0 }
end

-- Expected casts until the next item from a proportion: { mean, low, high }; math.huge where the
-- rate (or its lower bound) is 0. The range comes from the inverted Wilson bounds.
function Stats.ExpectedCasts(proportion)
    if not (proportion and proportion.p) then
        return nil
    end
    local function inverse(x)
        return x > 0 and 1 / x or huge
    end
    return {
        mean = inverse(proportion.p),
        low = inverse(proportion.high),
        high = inverse(proportion.low),
    }
end

-- Chance of at least one item in the next casts: { p, low, high } from the proportion's bounds.
function Stats.AtLeastOne(proportion, casts)
    if not (proportion and proportion.p) or type(casts) ~= "number" or casts < 0 then
        return nil
    end
    local function chance(x)
        return 1 - (1 - x) ^ casts
    end
    local p, low, high = proportion.p, proportion.low, proportion.high
    return { p = chance(p), low = chance(low), high = chance(high) }
end

-- Value at quantile q (0-1) of a histogram { [value] = count }, linear between the two nearest
-- order statistics (the common "type 7" rule). nil for an empty histogram.
function Stats.Quantile(histogram, q)
    local keys, n = {}, 0
    for value, count in pairs(histogram or {}) do
        if type(value) == "number" and type(count) == "number" and count > 0 then
            keys[#keys + 1] = value
            n = n + count
        end
    end
    if n == 0 then
        return nil
    end
    sort(keys)
    local function at(rank) -- the rank-th smallest value, 1-based
        local seen = 0
        for _, value in ipairs(keys) do
            seen = seen + histogram[value]
            if seen >= rank then
                return value
            end
        end
        return keys[#keys]
    end
    local h = (n - 1) * q + 1
    local lowRank = floor(h)
    local lowValue, highValue = at(lowRank), at(ceil(h))
    return lowValue + (h - lowRank) * (highValue - lowValue)
end

-- Median and quartiles of a histogram: { n, q1, median, q3 }, or nil when empty.
function Stats.Quartiles(histogram)
    local median = Stats.Quantile(histogram, 0.5)
    if not median then
        return nil
    end
    local n = 0
    for _, count in pairs(histogram) do
        n = n + (type(count) == "number" and count or 0)
    end
    return {
        n = n,
        q1 = Stats.Quantile(histogram, 0.25),
        median = median,
        q3 = Stats.Quantile(histogram, 0.75),
    }
end

-- Active seconds of cast start times (oldest first): Σ min(gap, cap), plus cap for the last.
function Stats.ActiveTime(times, cap)
    cap = cap or Stats.DEFAULTS.activeCap
    local total = 0
    for i = 1, #times do
        local nextTime = times[i + 1]
        local gap = nextTime and nextTime - times[i]
        total = total + ((gap and gap >= 0 and gap < cap) and gap or cap)
    end
    return total
end

-- Blended share of own catches with a reference share worth m pseudo-catches (module 3):
-- (own + m · reference) / (n + m).
function Stats.Blend(ownK, ownN, reference, m)
    m = m or Stats.DEFAULTS.blendWeight
    if type(reference) ~= "number" or (ownN or 0) + m <= 0 then
        return nil
    end
    return ((ownK or 0) + m * reference) / ((ownN or 0) + m)
end

-- Rate builders with the fixed denominators. outcomes: { [outcome] = count }.

function Stats.Count(outcomes, name)
    return type(outcomes) == "table" and outcomes[name] or 0
end

-- Fair casts: every outcome except cancel, unknown, and invalid target.
function Stats.Fair(outcomes)
    local n = 0
    for name, count in pairs(type(outcomes) == "table" and outcomes or {}) do
        if not Stats.UNFAIR[name] then
            n = n + count
        end
    end
    return n
end

-- Hooked casts: catches and getaways.
function Stats.Hooked(outcomes)
    return Stats.Count(outcomes, "catch") + Stats.Count(outcomes, "getaway")
end

function Stats.SuccessRate(outcomes, t)
    return Stats.Proportion(Stats.Count(outcomes, "catch"), Stats.Fair(outcomes), t)
end

function Stats.GetawayRate(outcomes, t)
    return Stats.Proportion(Stats.Count(outcomes, "getaway"), Stats.Hooked(outcomes), t)
end

function Stats.MissRate(outcomes, t)
    local missed = Stats.Count(outcomes, "early_click") + Stats.Count(outcomes, "timeout")
    return Stats.Proportion(missed, Stats.Fair(outcomes), t)
end

-- Share of catches that held an item (itemCatches of catches).
function Stats.ItemShare(itemCatches, catches, t)
    return Stats.Proportion(itemCatches, catches, t)
end

-- Catches per active hour; the display follows the fair casts behind it.
function Stats.CatchesPerHour(outcomes, seconds, t)
    return Stats.PerHour(Stats.Count(outcomes, "catch"), seconds, Stats.Fair(outcomes), t)
end
