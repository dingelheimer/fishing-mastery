-- Pure logic: shared pieces of the row tooltips of the Statistics tables (Story 9.4, Draft 2),
-- written into a Tip builder: an item title in its quality color, rates and rates per hour as
-- gold label and value with the range in a grey bracket (counts only for small samples), and the
-- Shift explanations. No frame or API calls; the builder comes in from Tip.Open.
local _, ns = ...

local format, floor, ipairs = string.format, math.floor, ipairs
local L, Style, HudModel = ns.L, ns.Style, ns.HudModel

local RowTip = {}
ns.RowTip = RowTip

local function pct(x)
    return floor(x * 100 + 0.5)
end

-- A proportion as a percent; "<1 %" for a share above 0 that rounds to 0 (owner check, Story
-- 9.4: one catch in hundreds read as "0 %").
function RowTip.Percent(rate)
    if rate.display ~= "count" and rate.p and rate.p > 0 and pct(rate.p) == 0 then
        return L.TIP_UNDER_ONE
    end
    return HudModel.Percent(rate)
end

-- The item as the title: its name in the quality color; "Item <id>" while loading.
function RowTip.Item(tip, id, info)
    info = info or {}
    tip:Title(info.name or format(L.HUD_ITEM_LOADING, id), Style.FromHex(info.hex) or Style.WHITE)
end

-- A proportion: "12 % (8 - 17)", "5 of 40" in grey for small samples, "-" without any.
function RowTip.Rate(tip, label, rate)
    if rate.n == 0 then
        tip:Pair(label, "-", Style.GREY)
    elseif rate.display == "count" or not rate.low then
        tip:Pair(label, format(L.TIP_OF, Style.Number(rate.k), Style.Number(rate.n)), Style.GREY)
    else
        local value = Style.Range(RowTip.Percent(rate), pct(rate.low), pct(rate.high))
        tip:Pair(label, value, rate.display == "few" and Style.GREY or nil)
    end
end

-- A count per hour: "122 / h (110 - 135)", or grey "too few casts".
function RowTip.PerHour(tip, label, perHour)
    if not perHour.rate or perHour.display == "count" then
        tip:Pair(label, L.TIP_FEW, Style.GREY)
        return
    end
    local value = format(L.TIP_PER_HOUR, floor(perHour.rate + 0.5))
    value = Style.Range(value, floor(perHour.low + 0.5), floor(perHour.high + 0.5))
    tip:Pair(label, value, perHour.display == "few" and Style.GREY or nil)
end

-- Success rate and catches per hour of a group of casts.
function RowTip.Rates(tip, success, perHour)
    RowTip.Rate(tip, L.TIP_SUCCESS, success)
    RowTip.PerHour(tip, L.TIP_PER_HOUR_LABEL, perHour)
end

-- The Shift lines: keys of RowTip.DETAILS (range, fair, hooked, grey, ...) or own lines.
RowTip.DETAILS = {
    range = "TIP_D_RANGE",
    fair = "TIP_D_FAIR",
    hooked = "TIP_D_HOOKED",
    grey = "TIP_D_GREY",
}
function RowTip.Details(tip, keys)
    local lines = {}
    for _, key in ipairs(keys) do
        if key then
            local name = RowTip.DETAILS[key]
            lines[#lines + 1] = name and L[name] or key
        end
    end
    tip:Details(lines)
end
