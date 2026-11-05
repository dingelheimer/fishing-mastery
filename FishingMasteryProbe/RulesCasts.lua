-- Data: report rules for the questions guided fishing steps answer (Q06-Q17).
local _, ns = ...

local type, ipairs, tostring, format = type, ipairs, tostring, string.format
local min, max = math.min, math.max
local R = ns.ReportRules

R.Add({
    q = "Q06",
    match = R.Kind("cast"),
    value = function(list)
        return format(
            "%d casts, %s",
            #list,
            R.Tally(list, function(d)
                return "spell " .. tostring(d.spellID)
            end)
        )
    end,
})

-- Q07 needs the S1 (no pole) and S2 (pole) snapshots; S9 adds the lure.
R.Add({
    q = "Q07",
    match = R.Kind("context"),
    complete = function(list)
        local function phaseIn(step)
            return R.Any(list, function(d, entry)
                return entry.step == step and d.phase ~= nil
            end)
        end
        return phaseIn("S1") and phaseIn("S2")
    end,
    value = function(list)
        local skill = {}
        for _, entry in ipairs(list) do
            local step = entry.step
            if step == "S1" or step == "S2" or step == "S9" then
                skill[step] = R.FishingSkill(R.Data(entry)) or "?"
            end
        end
        return format(
            "fishing skill S1 %s, S2 %s, S9 %s",
            skill.S1 or "-",
            skill.S2 or "-",
            skill.S9 or "-"
        )
    end,
})

R.Add({
    q = "Q08",
    min = 5,
    match = function(entry)
        return entry.kind == "attempt" and R.Data(entry).outcome == "catch"
    end,
    value = function(list)
        local low, high
        for _, entry in ipairs(list) do
            local bite = R.Data(entry).biteTime
            if type(bite) == "number" then
                low, high = min(low or bite, bite), max(high or bite, bite)
            end
        end
        if not low then
            return format("%d catches", #list)
        end
        return format("%d catches, bite time %.1f-%.1f s", #list, low, high)
    end,
})

R.Add({
    q = "Q09",
    min = 5,
    match = R.FishingLoot,
    value = function(list)
        local slots = 0
        for _, entry in ipairs(list) do
            slots = slots + R.CountKeys(R.Data(entry).slots)
        end
        return format("%d fishing loots, %d slots", #list, slots)
    end,
})

-- Q10 needs a school or wreckage source with its object ID.
local function sourceIds(list)
    local ids = {}
    for _, entry in ipairs(list) do
        R.EachSource(R.Data(entry), function(source)
            if source.id then
                ids[#ids + 1] =
                    { name = format("%s %s", tostring(source.type), tostring(source.id)) }
            end
        end)
    end
    return ids
end

R.Add({
    q = "Q10",
    match = R.Kind("loot", "S11"),
    complete = function(list)
        return #sourceIds(list) > 0
    end,
    value = function(list)
        local sources = R.Tally(sourceIds(list), function(_, item)
            return item.name
        end)
        return format("%d loots, sources: %s", #list, sources ~= "" and sources or "-")
    end,
})

R.Add(R.AttemptRule("Q11", "S5", "early_click", 2))
R.Add(R.AttemptRule("Q12", "S6", "timeout", 2))
R.Add(R.AttemptRule("Q13", "S7", "cancel", 2))
R.Add(R.AttemptRule("Q14", "S12", "getaway", 1))
R.Add(R.AttemptRule("Q15", "S8", "invalid_target", 1))

R.Add({
    q = "Q16",
    match = R.Kind("context", "S9"),
    value = function(list)
        local values = R.Table(R.Table(R.Last(list).weaponEnchant).values)
        return format("main-hand enchant %s, ID %s", tostring(values[1]), tostring(values[4]))
    end,
})

R.Add({
    q = "Q17",
    match = R.Kind("context", "S2"),
    complete = function(list)
        return type(R.First(R.Last(list).mainHand)) == "number"
    end,
    value = function(list)
        local d = R.Last(list)
        return format(
            "pole item %s, fishing skill %s",
            tostring(R.First(d.mainHand)),
            R.FishingSkill(d) or "-"
        )
    end,
})
