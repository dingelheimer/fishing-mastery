-- Pure logic: the HUD's numbers from the open session and the live game values (rank, skill
-- modifier, lure time, item name), their short formats, and the rate tooltip lines (minimap
-- button); the HUD card is HudCardModel.lua. Rates come from Stats with the session's
-- outcome counts; small samples show counts or are greyed by the Stats display rule. No frame
-- or API calls.
local _, ns = ...

local format, floor, type = string.format, math.floor, type
local L, Stats, Session = ns.L, ns.Stats, ns.Session

local HudModel = {}
ns.HudModel = HudModel

-- input: { session, now (server time), rank, modifier, lureSeconds (nil without a lure),
-- itemName, itemIcon, thresholds (Stats.Thresholds) }. Returns the model the texts are made of.
function HudModel.Build(input)
    local session, t = input.session, input.thresholds or Stats.DEFAULTS
    local active = Session.Active(session, input.now, t.activeCap)
    local rank, modifier = input.rank, input.modifier
    return {
        active = active,
        casts = session.casts,
        catches = session.catches,
        success = Stats.SuccessRate(session.counts, t),
        perHour = Stats.CatchesPerHour(session.counts, active, t),
        rank = type(rank) == "number" and rank or session.skill,
        skillUps = Session.SkillUps(session),
        effective = type(rank) == "number"
                and rank + (type(modifier) == "number" and modifier or 0)
            or nil,
        lureSeconds = input.lureSeconds,
        lastItem = session.lastItem,
        lastBite = session.lastBite,
        itemName = input.itemName,
        itemIcon = input.itemIcon,
    }
end

-- "12 min" or "1 h 05 min".
function HudModel.Duration(seconds)
    local minutes = floor((seconds or 0) / 60)
    if minutes < 60 then
        return format(L.HUD_MINUTES, minutes)
    end
    return format(L.HUD_HOURS, floor(minutes / 60), minutes % 60)
end

-- Success rate: "4/5" below the count threshold, "85 %" above, "-" without fair casts.
function HudModel.Percent(result)
    if result.n == 0 then
        return "-"
    end
    if result.display == "count" then
        return format("%d/%d", result.k, result.n)
    end
    return format("%d %%", floor(result.p * 100 + 0.5))
end

-- Catches per hour: "91/h", or "-" without enough casts or active time.
function HudModel.Rate(result)
    if not result.rate or result.display == "count" then
        return "-"
    end
    return format(L.HUD_PER_HOUR, floor(result.rate + 0.5))
end

local function percentRange(result)
    return floor(result.low * 100 + 0.5), floor(result.high * 100 + 0.5)
end

-- Tooltip lines with the 95 % ranges of both rates (or why there is none yet).
function HudModel.Tooltip(model)
    local lines = {}
    local success, perHour = model.success, model.perHour
    if success.display == "count" or not success.low then
        lines[1] = format(L.HUD_TIP_SUCCESS_FEW, success.k, success.n)
    else
        local low, high = percentRange(success)
        lines[1] =
            format(L.HUD_TIP_SUCCESS, HudModel.Percent(success), low, high, success.k, success.n)
    end
    if perHour.display == "count" or not perHour.rate then
        lines[2] = L.HUD_TIP_RATE_FEW
    else
        lines[2] = format(
            L.HUD_TIP_RATE,
            floor(perHour.rate + 0.5),
            floor(perHour.low + 0.5),
            floor(perHour.high + 0.5),
            perHour.count,
            HudModel.Duration(perHour.seconds)
        )
    end
    if success.display == "few" then
        lines[3] = L.HUD_TIP_GREY
    end
    return lines
end
