-- Pure logic: the session summary card (Story 10.5, the owner's pick of a card like the HUD card)
-- drawn into a DetailPane builder from a SummaryModel model: the water and the active time, the
-- skill line, three big numbers between dividers, pairs (casts with the session time, the
-- outcomes that were not a catch, the vendor value), the "Caught" table (most caught first, at
-- most MAX_ITEMS rows), and the zone comparison when it is clear. No frame or API calls.
local _, ns = ...

local format, ipairs, sort, type, min = string.format, ipairs, table.sort, type, math.min
local L, Style = ns.L, ns.Style

local SummaryCardModel = {}
ns.SummaryCardModel = SummaryCardModel

SummaryCardModel.MAX_ITEMS = 5
SummaryCardModel.GREY_OUTCOMES = { cancel = true, invalid_target = true, unknown = true }

local function paint(text, color)
    return Style.Paint(text, color)
end

local function pct(x)
    return math.floor(x * 100 + 0.5)
end

local function skillLine(model)
    local from, to = model.skillStart, model.skill
    if type(from) ~= "number" or type(to) ~= "number" then
        return nil
    end
    local text = format(L.SCARD_SKILL, from, to)
    if (model.skillUps or 0) > 0 then
        text = text .. "  " .. paint(format("+%d", model.skillUps), Style.GREEN)
    end
    return text
end

local function caught(b, model)
    local items = {}
    for i, entry in ipairs(model.items) do
        items[i] = entry
    end
    sort(items, function(a, c)
        if a.qty ~= c.qty then
            return a.qty > c.qty
        end
        return a.id < c.id
    end)
    b:Gap()
    b:Header({ L.SCARD_CAUGHT, L.SCARD_COUNT, "" })
    for i = 1, min(#items, SummaryCardModel.MAX_ITEMS) do
        local e = items[i]
        local name = e.name or format(L.HUD_ITEM_LOADING, e.id)
        if e.icon then
            name = format("|T%d:14:14|t %s", e.icon, name)
        end
        b:Row({ name, Style.Number(e.qty), e.new and L.SCARD_NEW or "" }, {
            Style.FromHex(e.hex),
            nil,
            Style.GREEN,
        })
    end
    if #items > SummaryCardModel.MAX_ITEMS then
        b:Line(format(L.SCARD_MORE, #items - SummaryCardModel.MAX_ITEMS), Style.GREY)
    end
end

local function comparison(b, model)
    local c = model.compare
    if not c then
        return
    end
    local higher = c.diff.d > 0
    b:Gap()
    b:Line(higher and L.SCARD_ABOVE or L.SCARD_BELOW, higher and Style.GREEN or Style.ORANGE)
    local value = format(L.SCARD_VS, pct(c.own.p), pct(c.other.p))
    b:Line(
        Style.Range(value, format("%+d", pct(c.diff.low)), format(L.SCARD_PTS, pct(c.diff.high)))
    )
end

-- draw(builder) of the card. input: { session, mapName(map) -> name or nil }.
function SummaryCardModel.Draw(model, input)
    local Hud = ns.HudModel
    return function(b)
        b:Title(model.open and L.SUMMARY_TITLE_OPEN or L.SUMMARY_TITLE, Style.GREY)
        local zone = ns.SessionTable.ZoneText(input.session, input.mapName) or L.PREFIX
        b:Heading(zone, Hud.Duration(model.active))
        local skill = skillLine(model)
        if skill then
            b:Line(skill)
        end
        b:Divider()
        b:Numbers(ns.HudCardModel.Numbers(model))
        b:Divider()
        b:Pair(
            L.SCARD_CASTS,
            Style.Number(model.casts)
                .. " "
                .. paint("(" .. Hud.Duration(model.total) .. ")", Style.GREY)
        )
        for _, entry in ipairs(model.failures) do
            local grey = SummaryCardModel.GREY_OUTCOMES[entry.outcome]
            b:Pair(
                L["OV_OUT_" .. entry.outcome] or L["OUTCOME_" .. entry.outcome],
                Style.Number(entry.count),
                grey and Style.GREY or nil
            )
        end
        if #model.items > 0 then
            local perHour = model.valuePerHour and ns.SummaryModel.Money(model.valuePerHour) or "-"
            local value = ns.SummaryModel.Money(model.value)
                .. " "
                .. paint(format(L.SCARD_PER_HOUR, perHour), Style.GREY)
            if model.missingPrice then -- a sell price is still loading
                value = value .. " " .. paint(L.SCARD_LOADING, Style.GREY)
            end
            b:Pair(L.SCARD_VALUE, value)
            caught(b, model)
        end
        comparison(b, model)
    end
end
