-- Pure logic: the HUD of Draft 5 (Story 9.8) from the session numbers (HudModel.Build) and the
-- water: the card (water name with a risk tag, the skill bar with the skill-ups and a mark at the
-- effective skill, the risk line, the lure row, three numbers, the last catch, the water's fish)
-- as a HudCard model, the compact line, and the HUD tooltip of Draft 6. Grey while a sample is
-- small (Stats display rule). No frame or API calls.
local _, ns = ...

local format, floor, ipairs, type, tostring, concat =
    string.format, math.floor, ipairs, type, tostring, table.concat
local L, Style, HudModel, RowTip = ns.L, ns.Style, ns.HudModel, ns.RowTip

local HudCardModel = {}
ns.HudCardModel = HudCardModel

HudCardModel.FISH = 8 -- fish icons at most
HudCardModel.LURE_ICON = 134335 -- the fishing lure icon for a running lure

local function pct(x)
    return floor(x * 100 + 0.5)
end

local function paint(text, color)
    return Style.Paint(text, color)
end

-- The getaway model of the water, or nil (no water read, no base, or no fishing rank).
local function model(zone)
    return zone and zone.risk and zone.risk.model or nil
end

local function risk(zone)
    local m = model(zone)
    if not m then
        return { text = L.HCARD_RISK_UNKNOWN, kind = "unknown" }
    end
    if m.getaway <= 0 then
        return { text = L.HCARD_SAFE, kind = "safe" }
    end
    return { text = format(L.HCARD_RISK, pct(m.getaway)), kind = "risk" }
end

local function bar(input)
    local m = input.model
    if type(m.rank) ~= "number" then
        return { value = 0, max = 1, text = L.HUD_SKILL_NONE }
    end
    local max = type(input.max) == "number" and input.max >= m.rank and input.max or m.rank
    local text = format(L.OV_SKILL_BAR, m.rank, max)
    if (m.skillUps or 0) > 0 then
        text = text .. " " .. paint(format("+%d", m.skillUps), Style.GREEN)
    end
    local mark
    if m.effective and m.effective ~= m.rank then
        mark = (m.effective > max and max or m.effective) / max
    end
    return { value = m.rank, max = max, text = text, mark = mark }
end

-- "with lure 176 / getaways stop at 225", only while fish still get away.
local function riskLine(input)
    local m = model(input.zone)
    local effective = input.model.effective or input.model.rank
    if not m or m.getaway <= 0 or type(effective) ~= "number" then
        return nil
    end
    local left = input.lure and L.HCARD_WITH_LURE or L.HCARD_SKILL
    return {
        left = format(left, effective),
        right = format(L.HCARD_STOP, paint(tostring(m.stopsAt), Style.GREEN)),
    }
end

local function timer(seconds)
    local s = floor(seconds + 0.5)
    return format("%d:%02d", floor(s / 60), s % 60)
end

local function lure(input)
    local running = input.lure
    if running and running.seconds then
        local text = running.bonus and format(L.HCARD_LURE, running.bonus) or L.HCARD_LURE_ON
        return { icon = HudCardModel.LURE_ICON, text = text, timer = timer(running.seconds) }
    end
    local m = model(input.zone)
    if m and m.getaway <= 0 then
        return { text = L.HCARD_NO_LURE_NEEDED, grey = true }
    end
    local suggestion = input.suggestion
    if suggestion then
        local text = suggestion.name .. " " .. paint(format("+%d", suggestion.bonus), Style.GREY)
        return { icon = suggestion.icon, text = text, dim = true }
    end
    return { text = L.HCARD_NO_LURE, grey = true }
end

local function numbers(m)
    local success, perHour = m.success, m.perHour
    local full = success.n > 0 and success.display ~= "count"
    local rate = HudModel.Rate(perHour)
    return {
        { value = Style.Number(m.catches or 0), label = L.PREVIEW_CATCHES },
        {
            -- A percent gets "%" as a small unit (Draft 5); counts ("4/5") and "-" have none.
            value = full and format("%d", pct(success.p)) or HudModel.Percent(success),
            unit = full and "%" or nil,
            label = L.PREVIEW_SUCCESS,
            grey = success.display ~= "full",
        },
        {
            value = rate == "-" and "-" or format("%d", floor(perHour.rate + 0.5)),
            label = L.PREVIEW_PER_HOUR,
            grey = perHour.display ~= "full",
        },
    }
end

local function last(input)
    local m = input.model
    if not m.lastItem then
        return nil
    end
    local info = input.last or {}
    return {
        icon = info.icon,
        text = info.name or format(L.HUD_ITEM_LOADING, m.lastItem),
        color = Style.FromHex(info.hex) or Style.WHITE,
        bite = type(m.lastBite) == "number" and format(L.STATS_SECONDS, m.lastBite / 10) or "",
    }
end

-- The water's fish (its Classic list without quest rows, in list order): icon bright when caught
-- here, dark when missing; and the "2 missing" text.
local function fish(input)
    local zone = input.zone
    if not (zone and zone.rows) then
        return nil, nil
    end
    local list, seen, missing = {}, {}, 0
    for _, row in ipairs(zone.rows) do
        local id = row[1]
        if not row[5] and not seen[id] then
            seen[id] = true
            local caught = ((zone.items or {})[id] or 0) > 0
            missing = missing + (caught and 0 or 1)
            if #list < HudCardModel.FISH then
                local info = input.info and input.info(id) or {}
                list[#list + 1] = { id = id, icon = info.icon, name = info.name, caught = caught }
            end
        end
    end
    local text = missing > 0 and format(L.HCARD_MISSING, missing) or L.HCARD_ALL_CAUGHT
    return list, text
end

local function compact(card, m)
    local riskColor = card.risk.kind == "safe" and Style.GREEN
        or card.risk.kind == "risk" and Style.ORANGE
        or Style.GREY
    local success = card.numbers[2]
    local rate = success.unit and success.value .. " " .. success.unit or success.value
    local skill = type(m.rank) == "number" and format(L.HCARD_COMPACT_SKILL, m.rank) or ""
    if (m.skillUps or 0) > 0 then
        skill = skill .. " " .. paint(format("+%d", m.skillUps), Style.GREEN)
    end
    local parts = {
        paint(card.zone, Style.GOLD),
        paint(card.risk.text, riskColor),
        format(L.HCARD_COMPACT_CATCHES, card.numbers[1].value),
        success.grey and paint(rate, Style.GREY) or rate,
        skill,
    }
    return concat(parts, paint("  |  ", Style.GREY))
end

-- input: { model (HudModel.Build), max (skill cap), zone (HudZone.Read or nil when the water
-- line is off), lure ({ bonus, seconds } of the running lure or nil), suggestion ({ name, bonus,
-- icon } of the smart lure's choice or nil), last ({ name, icon, hex } of the last catch),
-- info(id) -> { name, icon } }. Returns the HudCard model.
function HudCardModel.Build(input)
    local zone = input.zone
    local card = {
        zone = zone and zone.name or L.PREFIX,
        risk = zone and risk(zone) or { text = "", kind = "unknown" },
        bar = bar(input),
        riskLine = riskLine(input),
        lure = lure(input),
        numbers = numbers(input.model),
        last = last(input),
    }
    card.fish, card.missing = fish(input)
    card.compact = compact(card, input.model)
    -- The green tick where getaways stop, only in risky water and only on the bar.
    local m = model(zone)
    if card.riskLine and m.stopsAt <= card.bar.max then
        card.bar.safe = m.stopsAt / card.bar.max
    end
    return card
end

-- The sample of Draft 5 (safe water) for the Settings page preview.
function HudCardModel.Sample()
    local gold, green, grey = Style.Hex(Style.GOLD), Style.Hex(Style.GREEN), Style.Hex(Style.GREY)
    return {
        zone = L.PREVIEW_ZONE,
        risk = { text = L.PREVIEW_SAFE, kind = "safe" },
        bar = { value = 154, max = 225, text = L.PREVIEW_BAR },
        lure = { text = L.HCARD_NO_LURE_NEEDED, grey = true },
        numbers = {
            { value = "8", label = L.PREVIEW_CATCHES },
            { value = "8/9", label = L.PREVIEW_SUCCESS, grey = true },
            { value = "-", label = L.PREVIEW_PER_HOUR, grey = true },
        },
        compact = "|c"
            .. gold
            .. L.PREVIEW_ZONE
            .. "|r  |c"
            .. green
            .. L.PREVIEW_SAFE
            .. "|r  "
            .. L.PREVIEW_COMPACT_CATCHES
            .. "  |c"
            .. grey
            .. "8/9|r  "
            .. L.PREVIEW_COMPACT_SKILL,
    }
end

local function getaways(tip, zone)
    local r, m = zone.risk, model(zone)
    tip:Gap()
    tip:Header(L.HTIP_GETAWAYS)
    if not m then
        tip:Line(L.HTIP_NO_BASE, Style.GREY)
        return
    end
    tip:Pair(format(L.HTIP_CLASSIC, r.skill), m.below and L.HTIP_NO_CATCH or pct(m.getaway) .. " %")
    if r.shown then
        local own = r.own
        tip:Pair(
            format(L.HTIP_YOURS, r.band, r.band + ns.Totals.SKILL_BAND - 1),
            Style.Range(HudModel.Percent(own), pct(own.low), pct(own.high))
        )
    end
    tip:Pair(L.HTIP_NONE_FROM, m.stopsAt)
    if r.differs then
        tip:Line(L.STATS_TIP_DIFFERS, Style.ORANGE)
    end
end

-- The HUD tooltip of Draft 6 drawn into a Tip builder (same input as Build); extra(tip) adds
-- lines at the end (the dev area line).
function HudCardModel.Tip(input, extra)
    return function(tip)
        local m, zone = input.model, input.zone
        tip:Title(zone and zone.name or L.PREFIX, Style.GOLD)
        tip:Line(format(L.HTIP_SESSION, HudModel.Duration(m.active)), Style.GREY)
        tip:Pair(
            L.OV_CATCHES,
            format(L.OV_CHAR_LINE, Style.Number(m.catches), Style.Number(m.casts))
        )
        RowTip.Rates(tip, m.success, m.perHour)
        if zone and zone.risk then
            getaways(tip, zone)
        end
        local suggestion = input.suggestion
        if suggestion then
            tip:Gap()
            tip:Pair(
                L.HTIP_BEST_LURE,
                suggestion.name .. " " .. paint("+" .. suggestion.bonus, Style.GREY)
            )
        end
        RowTip.Details(tip, { "fair", "range", L.HTIP_D_CLASSIC })
        if extra then
            extra(tip)
        end
    end
end
