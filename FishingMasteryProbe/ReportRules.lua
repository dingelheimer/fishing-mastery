-- Pure logic: building blocks for the per-question report rules (RulesLogin.lua,
-- RulesCasts.lua, RulesPassive.lua). A rule is { q, match(entry), min, complete(list),
-- value(list) }: match picks the log entries that answer the question, min is the number needed
-- (default 1), complete tells whether they really answer it, value is the key value text.
local _, ns = ...

local type, ipairs, pairs, tostring, format = type, ipairs, pairs, tostring, string.format
local concat, sort, sub = table.concat, table.sort, string.sub

local R = { list = {}, byQ = {} }
ns.ReportRules = R

R.FISHING_INDEX = 4 -- GetProfessions(): prof1, prof2, archaeology, fishing, cooking
R.MAX_DEPTH = 6

function R.Add(rule)
    R.list[#R.list + 1] = rule
    R.byQ[rule.q] = rule
end

function R.Data(entry)
    return type(entry) == "table" and type(entry.data) == "table" and entry.data or {}
end

function R.Last(list)
    return R.Data(list[#list])
end

function R.YesNo(value)
    return value and "yes" or "no"
end

function R.Table(value)
    return type(value) == "table" and value or {}
end

-- Logged snapshot entry with the given data.topic.
function R.Topic(...)
    local names = {}
    for _, name in ipairs({ ... }) do
        names[name] = true
    end
    return function(entry)
        return entry.kind == "snapshot" and names[R.Data(entry).topic] == true
    end
end

-- Entries of a kind, optionally only those logged during one step.
function R.Kind(kind, step)
    return function(entry)
        return entry.kind == kind and (step == nil or entry.step == step)
    end
end

-- First returned value of a logged Calls.Call result ({ exists, ok, n, values }), or nil.
function R.First(call)
    if type(call) == "table" and call.ok and type(call.values) == "table" then
        return call.values[1]
    end
    return nil
end

function R.CountKeys(value)
    local n = 0
    for _ in pairs(R.Table(value)) do
        n = n + 1
    end
    return n
end

-- Number of entries in the list for which test(data, entry) is true.
function R.Count(list, test)
    local n = 0
    for _, entry in ipairs(list) do
        if test(R.Data(entry), entry) then
            n = n + 1
        end
    end
    return n
end

function R.Any(list, test)
    return R.Count(list, test) > 0
end

-- "a 3, b 1" from the values key(data, entry) returns, sorted by value.
function R.Tally(list, key)
    local counts, names = {}, {}
    for _, entry in ipairs(list) do
        local name = key(R.Data(entry), entry)
        if name ~= nil then
            name = tostring(name)
            if not counts[name] then
                names[#names + 1] = name
            end
            counts[name] = (counts[name] or 0) + 1
        end
    end
    sort(names)
    for i, name in ipairs(names) do
        names[i] = format("%s %d", name, counts[name])
    end
    return concat(names, ", ")
end

-- True when a logged value holds a secret marker anywhere (depth-limited).
function R.HasSecret(value, depth)
    depth = depth or 0
    if type(value) == "string" then
        return sub(value, 1, 8) == "<secret:"
    end
    if type(value) ~= "table" or depth > R.MAX_DEPTH then
        return false
    end
    for key, child in pairs(value) do
        if (key == "secret" and child) or R.HasSecret(child, depth + 1) then
            return true
        end
    end
    return false
end

-- Fishing skill from a context entry as "rank/max +modifier", or nil.
function R.FishingSkill(context)
    local info = R.Table(R.Table(context.professions).info)[R.FISHING_INDEX]
    if type(info) ~= "table" or not info.ok or type(info.values) ~= "table" then
        return nil
    end
    local v = info.values
    return format("%s/%s +%s", tostring(v[3]), tostring(v[4]), tostring(v[8] or 0))
end

-- Calls fn(source) for every reduced loot source in a loot entry's data.
function R.EachSource(lootData, fn)
    for _, slot in pairs(R.Table(lootData.slots)) do
        for _, source in ipairs(R.Table(R.Table(slot).sources)) do
            fn(R.Table(R.Table(source).source))
        end
    end
end

function R.FishingLoot(entry)
    return entry.kind == "loot" and R.First(R.Data(entry).isFishingLoot) == true
end

-- Attempts logged during the step made for the question, or with the expected outcome anywhere.
-- Answered when at least one has the expected outcome; otherwise the raw events need analysis.
function R.AttemptRule(q, step, outcome, min)
    return {
        q = q,
        min = min,
        match = function(entry)
            return entry.kind == "attempt"
                and (entry.step == step or R.Data(entry).outcome == outcome)
        end,
        complete = function(list)
            return R.Any(list, function(d)
                return d.outcome == outcome
            end)
        end,
        value = function(list)
            return R.Tally(list, function(d)
                return d.outcome
            end)
        end,
    }
end

-- S14 helper test result (probe_check entries of one test).
function R.CheckRule(q, test, field, label)
    return {
        q = q,
        match = function(entry)
            return entry.kind == "probe_check" and R.Data(entry).test == test
        end,
        value = function(list)
            return format("%s: %s", label, R.YesNo(R.Last(list)[field]))
        end,
    }
end
