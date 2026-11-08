-- Pure logic: the Statistics Overview page of Draft 1 (Story 9.3) from StatsModel.Overview of the
-- chosen scope: the Fishing skill bar, four headline numbers with their ranges as one grey line,
-- where casts end (outcome rows with count, bar, and share), and the five most caught items.
-- Grey rules follow Stats.Display (count only, or grey for few casts). No frame or API calls.
local _, ns = ...

local format, floor, ipairs, pairs, sort, type =
    string.format, math.floor, ipairs, pairs, table.sort, type
local L, Stats, Style = ns.L, ns.Stats, ns.Style

local OverviewModel = {}
ns.OverviewModel = OverviewModel

OverviewModel.TOP = 5
-- Rank names by the skill cap (the Classic trainer steps).
OverviewModel.RANKS =
    { [75] = "apprentice", [150] = "journeyman", [225] = "expert", [300] = "artisan" }
-- Outcome rows in order; fair outcomes have a share of the fair casts, the others are grey.
OverviewModel.OUTCOMES = {
    { key = "catch", color = Style.GREEN },
    { key = "getaway", color = Style.ORANGE },
    { key = "early_click", color = Style.GOLD },
    { key = "timeout", color = Style.GOLD },
    { key = "cancel", grey = true },
    { key = "invalid_target", grey = true },
}

local function percent(p)
    return floor(p * 100 + 0.5)
end

-- skill: { rank, max, modifier, gained } of the logged-in character, or nil.
local function skill(input)
    if type(input) ~= "table" or type(input.rank) ~= "number" then
        return nil
    end
    local modifier = type(input.modifier) == "number" and input.modifier or 0
    local max = type(input.max) == "number" and input.max >= input.rank and input.max or input.rank
    local rank = OverviewModel.RANKS[max]
    local result = {
        rank = input.rank,
        max = max,
        effective = input.rank + modifier,
        rankName = rank and L["OV_RANK_" .. rank] or nil,
        bar = format(L.OV_SKILL_BAR, input.rank, max),
        modifier = modifier ~= 0 and format(L.OV_SKILL_MOD, modifier, input.rank + modifier) or "",
        gained = "",
    }
    local gained = input.gained
    if type(gained) == "number" and gained > 0 then
        result.gained = format(L.OV_SKILL_GAINED, gained)
    end
    return result
end

local function successNumber(success)
    if success.n == 0 then
        return { value = "-", label = L.OV_SUCCESS, sub = L.OV_NO_CASTS }
    end
    if success.display == "count" then
        return {
            value = format("%d/%d", success.k, success.n),
            label = L.OV_SUCCESS,
            sub = L.OV_FEW,
            grey = true,
        }
    end
    return {
        value = format("%d", percent(success.p)),
        unit = "%",
        label = L.OV_SUCCESS,
        sub = format(L.OV_LIKELY_PERCENT, percent(success.low), percent(success.high)),
        grey = success.display == "few",
    }
end

local function rateNumber(perHour)
    if not perHour.rate or perHour.display == "count" then
        return { value = "-", label = L.OV_PER_HOUR, sub = L.OV_FEW, grey = true }
    end
    return {
        value = format("%d", floor(perHour.rate + 0.5)),
        unit = L.OV_PER_HOUR_UNIT,
        label = L.OV_PER_HOUR,
        sub = format(L.OV_LIKELY, floor(perHour.low + 0.5), floor(perHour.high + 0.5)),
        grey = perHour.display == "few",
    }
end

local function activeNumber(seconds, sessions)
    local minutes = floor((seconds or 0) / 60)
    return {
        value = format(L.OV_ACTIVE_VALUE, floor(minutes / 60), minutes % 60),
        label = L.OV_ACTIVE,
        sub = format(L.OV_SESSIONS, Style.Number(sessions or 0)),
    }
end

local function numbers(summary, sessions)
    return {
        {
            value = Style.Number(summary.catches),
            label = L.OV_CATCHES,
            sub = format(L.OV_OF_CASTS, Style.Number(summary.casts)),
        },
        successNumber(summary.success),
        rateNumber(summary.perHour),
        activeNumber(summary.active, sessions),
    }
end

local function outcomes(view)
    local fair = Stats.Fair(view.outcomes)
    local rows = {}
    for _, entry in ipairs(OverviewModel.OUTCOMES) do
        local count = view.outcomes[entry.key] or 0
        local share = not entry.grey and fair > 0 and count / fair or nil
        rows[#rows + 1] = {
            key = entry.key,
            label = L["OV_OUT_" .. entry.key],
            count = Style.Number(count),
            share = share,
            text = share and format("%d %%", percent(share)) or "-",
            color = entry.color,
            grey = entry.grey == true,
        }
    end
    return rows
end

-- info(id): { name, icon, hex } from the item cache.
local function top(view, info)
    local list = {}
    for id, item in pairs(view.items) do
        list[#list + 1] = { id = id, n = item.n or 0 }
    end
    sort(list, function(a, b)
        if a.n ~= b.n then
            return a.n > b.n
        end
        return a.id < b.id
    end)
    local rows, most = {}, list[1] and list[1].n or 0
    for i = 1, math.min(OverviewModel.TOP, #list) do
        local entry = list[i]
        local item = info(entry.id) or {}
        rows[i] = {
            id = entry.id,
            name = item.name or format(L.OV_ITEM, entry.id),
            icon = item.icon,
            hex = item.hex,
            n = Style.Number(entry.n),
            fill = most > 0 and entry.n / most or 0,
        }
    end
    return rows
end

-- Lines for the Catches tooltip: one per character with catches of casts (all characters only).
local function characters(model)
    if #model.characters < 2 then
        return nil
    end
    local lines = {}
    for _, char in ipairs(model.characters) do
        local s = char.summary
        local name = char.name or L.STATS_UNNAMED
        lines[#lines + 1] = {
            label = char.current and format(L.STATS_YOU, name) or name,
            value = format(L.OV_CHAR_LINE, Style.Number(s.catches), Style.Number(s.casts)),
        }
    end
    return lines
end

-- input: { model (StatsModel.Overview of the scope, with .view), sessions (count in the scope),
-- skill ({ rank, max, modifier, gained } of the logged-in character), info(id) }.
-- Returns { skill, numbers, outcomes, top, characters, empty }.
function OverviewModel.Build(input)
    local model = input.model
    return {
        skill = skill(input.skill),
        numbers = numbers(model.account, input.sessions),
        outcomes = outcomes(model.view),
        top = top(model.view, input.info),
        characters = characters(model),
        empty = model.account.casts == 0,
    }
end
