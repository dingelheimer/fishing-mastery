-- Pure logic: the HUD tooltip of Draft 6 (Story 9.8, moved out of HudCardModel.lua in Story
-- 10.6): the water, the session with its casts and rates, the getaways here, the best lure in
-- risky water, the Shift details. Drawn into a Tip builder from the HudCardModel input. No frame
-- or API calls.
local _, ns = ...

local format, floor = string.format, math.floor
local L, Style, HudModel, RowTip, HudCardModel =
    ns.L, ns.Style, ns.HudModel, ns.RowTip, ns.HudCardModel

local model = HudCardModel.Water

local function pct(x)
    return floor(x * 100 + 0.5)
end

local function paint(text, color)
    return Style.Paint(text, color)
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
        RowTip.Rate(tip, L.HTIP_SUCCESS, m.success)
        RowTip.PerHour(tip, L.HTIP_PER_HOUR, m.perHour)
        if zone and zone.risk then
            getaways(tip, zone)
        end
        -- The best owned lure, only while fish still get away; "on the pole" when it runs.
        local suggestion, water = input.suggestion, model(zone)
        if suggestion and water and water.getaway > 0 then
            local value = suggestion.name .. " " .. paint("+" .. suggestion.bonus, Style.GREY)
            if input.lure and input.lure.bonus == suggestion.bonus then
                value = value .. " " .. paint(L.HTIP_ON_POLE, Style.GREY)
            end
            tip:Gap()
            tip:Pair(L.HTIP_BEST_LURE, value)
        end
        RowTip.Details(tip, { "fair", "range", L.HTIP_D_CLASSIC })
        if extra then
            extra(tip)
        end
    end
end
