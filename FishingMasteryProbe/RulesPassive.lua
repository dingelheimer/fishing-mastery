-- Data: report rules for questions the passive recorders and the S10-S14 steps answer
-- (Q18, Q19, Q23-Q28, Q30-Q32).
local _, ns = ...

local type, ipairs, tostring, format = type, ipairs, tostring, string.format
local R = ns.ReportRules

R.Add({
    q = "Q18",
    match = R.Kind("context"),
    value = function(list)
        local auras, secret = 0, 0
        for _, entry in ipairs(list) do
            for _, aura in ipairs(R.Table(R.Data(entry).buffs)) do
                auras = auras + 1
                secret = secret + (R.HasSecret(aura) and 1 or 0)
            end
        end
        return format("%d buff records, %d secret", auras, secret)
    end,
})

R.Add({
    q = "Q19",
    match = function(entry)
        return entry.kind == "context" and type(R.Data(entry).location) == "table"
    end,
    complete = function(list)
        return type(R.Last(list).location.mapID) == "number"
    end,
    value = function(list)
        return format("uiMapID %s", tostring(R.Last(list).location.mapID))
    end,
})

R.Add({
    q = "Q23",
    match = function(entry)
        return entry.kind == "event" or entry.kind == "cast" or entry.kind == "loot"
    end,
    value = function(list)
        local secret = R.Count(list, function(d)
            return R.HasSecret(d)
        end)
        return format("secret values in %d of %d entries", secret, #list)
    end,
})

R.Add({
    q = "Q24",
    match = R.Kind("item_info"),
    complete = function(list)
        return R.Any(list, function(d)
            return type(d.sellPrice) == "number"
        end)
    end,
    value = function(list)
        local cached = R.Count(list, function(d)
            return d.cached == true and d.wait == nil
        end)
        local loaded = R.Count(list, function(d)
            return d.wait ~= nil
        end)
        return format("%d item entries, %d cached at once, %d after load", #list, cached, loaded)
    end,
})

-- Q25 is answered by the skill-up chat message; other skill events alone are partial.
R.Add({
    q = "Q25",
    match = function(entry)
        return entry.kind == "event" and entry.q == "Q25"
    end,
    complete = function(list)
        return R.Any(list, function(d)
            return d.name == "CHAT_MSG_SKILL"
        end)
    end,
    value = function(list)
        return R.Tally(list, function(d)
            return d.name
        end)
    end,
})

R.Add({
    q = "Q26",
    match = R.Kind("tooltip"),
    value = function(list)
        return format("%d tooltips, line 1: %s", #list, tostring(R.Last(list).line1))
    end,
})

R.Add(R.CheckRule("Q27", "S14b", "received", "message arrived"))
R.Add(R.CheckRule("Q28", "S14a", "channelStarted", "cast started"))

local function multiItem(d)
    local n = R.First(d.numItems)
    return type(n) == "number" and n > 1
end

-- Q30 needs at least one fishing loot with more than one item.
R.Add({
    q = "Q30",
    match = R.FishingLoot,
    complete = function(list)
        return R.Any(list, multiItem)
    end,
    value = function(list)
        return format("multi-item loots: %d of %d", R.Count(list, multiItem), #list)
    end,
})

R.Add({
    q = "Q31",
    match = R.Kind("context", "S13"),
    value = function(list)
        return format("%d buffs during S13", #R.Table(R.Last(list).buffs))
    end,
})

-- Q32 compares loots with auto loot on and off.
R.Add({
    q = "Q32",
    match = R.FishingLoot,
    complete = function(list)
        local on = R.Any(list, function(d)
            return d.autoLoot == true
        end)
        local off = R.Any(list, function(d)
            return d.autoLoot == false
        end)
        return on and off
    end,
    value = function(list)
        local on = R.Count(list, function(d)
            return d.autoLoot == true
        end)
        local off = R.Count(list, function(d)
            return d.autoLoot == false
        end)
        return format("auto loot on: %d loots, off: %d loots", on, off)
    end,
})
