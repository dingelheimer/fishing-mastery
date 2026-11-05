-- Pure logic: the session summary from a session, the character's totals, and item data (name,
-- icon, quality, sell price). Rates and ranges come from Stats; the zone comparison is shown
-- only when its Newcombe range excludes 0. No frame or API calls.
local _, ns = ...

local format, floor, type, pairs, ipairs, sort, concat, HUGE =
    string.format, math.floor, type, pairs, ipairs, table.sort, table.concat, math.huge
local L, Stats, Session = ns.L, ns.Stats, ns.Session

local SummaryModel = {}
ns.SummaryModel = SummaryModel

-- Failure outcomes in the order they are listed.
SummaryModel.FAILURES =
    { "getaway", "early_click", "timeout", "cancel", "invalid_target", "unknown" }
SummaryModel.ICON_SIZE = 14

-- Item entries of the session: { id, qty, name, icon, quality, sellPrice, total, new }.
local function itemEntries(session, totals, items)
    local list = {}
    for id, qty in pairs(type(session.items) == "table" and session.items or {}) do
        local info = items[id] or {}
        local lifetime = totals.items and totals.items[id]
        list[#list + 1] = {
            id = id,
            qty = qty,
            name = info.name,
            icon = info.icon,
            quality = info.quality,
            sellPrice = info.sellPrice,
            total = lifetime and lifetime.n or nil,
            -- First caught by this character in this session.
            new = lifetime ~= nil
                and type(lifetime.first) == "number"
                and lifetime.first >= session.start,
        }
    end
    sort(list, function(a, b)
        return a.id < b.id
    end)
    return list
end

-- Best fish: highest quality, then the rarest for this character (fewest catches), then the ID.
local function better(a, b)
    local qa, qb = a.quality or -1, b.quality or -1
    if qa ~= qb then
        return qa > qb
    end
    local ta, tb = a.total or HUGE, b.total or HUGE
    if ta ~= tb then
        return ta < tb
    end
    return a.id < b.id
end

local function zoneOutcomes(totals, map)
    local merged = {}
    local zone = totals.zones and totals.zones[map]
    for _, group in pairs(type(zone) == "table" and zone or {}) do
        for outcome, n in pairs(group.outcomes or {}) do
            merged[outcome] = (merged[outcome] or 0) + n
        end
    end
    return merged
end

-- Session success rate against the rest of the character's casts in the session's only zone.
local function compare(session, totals, t)
    local zones = session.zones
    if type(zones) ~= "table" or #zones ~= 1 then
        return nil
    end
    local rest = zoneOutcomes(totals, zones[1])
    for outcome, n in pairs(session.counts) do
        local left = (rest[outcome] or 0) - n
        rest[outcome] = left > 0 and left or nil
    end
    local own, other = Stats.SuccessRate(session.counts, t), Stats.SuccessRate(rest, t)
    local diff = Stats.Difference(own.k, own.n, other.k, other.n, t)
    if not diff or not diff.clear then
        return nil
    end
    return { map = zones[1], own = own, other = other, diff = diff }
end

-- input: { session, now (server time), totals (char.totals), items = { [id] = Items:Info },
-- thresholds }. Returns the model behind the summary lines.
function SummaryModel.Build(input)
    local session, t = input.session, input.thresholds or Stats.DEFAULTS
    local totals = input.totals or {}
    local active = Session.Counted(session, input.now, t.activeCap)
    local entries = itemEntries(session, totals, input.items or {})
    local model = {
        open = session.ended == nil,
        active = active,
        total = (session.ended or input.now or session.last) - session.start,
        casts = session.casts,
        catches = session.catches,
        success = Stats.SuccessRate(session.counts, t),
        perHour = Stats.CatchesPerHour(session.counts, active, t),
        failures = {},
        skillStart = session.skillStart,
        skill = session.skill,
        skillUps = Session.SkillUps(session),
        items = entries,
        newFish = {},
        value = 0,
        missingPrice = false,
        compare = compare(session, totals, t),
    }
    for _, outcome in ipairs(SummaryModel.FAILURES) do
        local n = session.counts[outcome]
        if n and n > 0 then
            model.failures[#model.failures + 1] = { outcome = outcome, count = n }
        end
    end
    for _, entry in ipairs(entries) do
        if not model.best or better(entry, model.best) then
            model.best = entry
        end
        if entry.new then
            model.newFish[#model.newFish + 1] = entry
        end
        if entry.sellPrice then
            model.value = model.value + entry.sellPrice * entry.qty
        else
            model.missingPrice = true
        end
    end
    if active > 0 then
        model.valuePerHour = model.value / (active / 3600)
    end
    return model
end

-- "1g 05s 20c", "35s 10c", "7c".
function SummaryModel.Money(copper)
    copper = floor((copper or 0) + 0.5)
    local gold, silver, rest = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if gold > 0 then
        return format(L.MONEY_GOLD, gold, silver, rest)
    end
    if silver > 0 then
        return format(L.MONEY_SILVER, silver, rest)
    end
    return format(L.MONEY_COPPER, rest)
end

local function itemText(entry)
    local name = entry.name or format(L.HUD_ITEM_LOADING, entry.id)
    if entry.icon then
        name = format(
            "|T%d:%d:%d|t %s",
            entry.icon,
            SummaryModel.ICON_SIZE,
            SummaryModel.ICON_SIZE,
            name
        )
    end
    return name
end

local function percent(p)
    return floor(p * 100 + 0.5)
end

-- The success rate and catches per hour lines (with ranges, or counts for small samples) of a
-- model with success and perHour; the stats window uses them too.
function SummaryModel.RateLines(model)
    local success, perHour = model.success, model.perHour
    local lines = {}
    if success.display == "count" or not success.low then
        lines[1] = format(L.SUMMARY_SUCCESS_FEW, success.k, success.n)
    else
        lines[1] = format(
            L.SUMMARY_SUCCESS,
            percent(success.p),
            percent(success.low),
            percent(success.high),
            success.n
        )
    end
    if perHour.display == "count" or not perHour.rate then
        lines[2] = L.SUMMARY_RATE_FEW
    else
        lines[2] = format(
            L.SUMMARY_RATE,
            floor(perHour.rate + 0.5),
            floor(perHour.low + 0.5),
            floor(perHour.high + 0.5)
        )
    end
    return lines
end

-- Text lines of the summary (window body or chat block). zoneName names compare.map.
function SummaryModel.Lines(model, zoneName)
    local Hud = ns.HudModel
    local lines = {
        format(L.SUMMARY_TIME, Hud.Duration(model.active), Hud.Duration(model.total)),
        format(L.SUMMARY_COUNTS, model.casts, model.catches),
    }
    for _, line in ipairs(SummaryModel.RateLines(model)) do
        lines[#lines + 1] = line
    end
    local failures = {}
    for i, entry in ipairs(model.failures) do
        failures[i] = format("%s %d", L["OUTCOME_" .. entry.outcome], entry.count)
    end
    lines[#lines + 1] = #failures > 0 and format(L.SUMMARY_FAILURES, concat(failures, ", "))
        or L.SUMMARY_NO_FAILURES
    lines[#lines + 1] = format(
        L.SUMMARY_SKILL,
        type(model.skillStart) == "number" and model.skillStart or "-",
        type(model.skill) == "number" and model.skill or "-",
        model.skillUps
    )
    if model.best then
        lines[#lines + 1] = format(L.SUMMARY_BEST, itemText(model.best), model.best.qty)
    end
    if #model.newFish > 0 then
        local names = {}
        for i, entry in ipairs(model.newFish) do
            names[i] = itemText(entry)
        end
        lines[#lines + 1] = format(L.SUMMARY_NEW, concat(names, ", "))
    end
    if #model.items > 0 then
        local value = SummaryModel.Money(model.value)
        local perHour = model.valuePerHour and SummaryModel.Money(model.valuePerHour) or "-"
        lines[#lines + 1] = format(
            model.missingPrice and L.SUMMARY_VALUE_PARTIAL or L.SUMMARY_VALUE,
            value,
            perHour
        )
    end
    local c = model.compare
    if c then
        lines[#lines + 1] = format(
            c.diff.d > 0 and L.SUMMARY_COMPARE_HIGHER or L.SUMMARY_COMPARE_LOWER,
            percent(c.own.p),
            percent(c.other.p),
            zoneName or format(L.SUMMARY_ZONE_ID, c.map),
            percent(c.diff.low),
            percent(c.diff.high)
        )
    end
    return lines
end
