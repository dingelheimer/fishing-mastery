-- Pure logic: the Skill tab's texts and charts from SkillModel.Build: the rank and pace lines, the
-- forecasts to the next rank cap and to 300, the rank-over-time line chart, and the catches per
-- skill point by rank band (bars with the 95 % range). No frame or API calls.
local _, ns = ...

local format, floor, ipairs, huge = string.format, math.floor, ipairs, math.huge
local L, HudModel, ChartModel, Style = ns.L, ns.HudModel, ns.ChartModel, ns.Style

local SkillTable = {}
ns.SkillTable = SkillTable

local function round(x)
    return floor(x + 0.5)
end

local function oneDecimal(x)
    return floor(x * 10 + 0.5) / 10
end

local function upper(x)
    return x == huge and "?" or format("%d", round(x))
end

-- "4.3 catches per point (95 % range 3.1-6.0), 10 points in 43 catches" or the count form.
function SkillTable.PaceText(pace)
    if not pace.mean or pace.display == "count" then
        return format(L.SKILL_PACE_FEW, pace.k, pace.c)
    end
    return format(
        L.SKILL_PACE,
        oneDecimal(pace.mean),
        oneDecimal(pace.low),
        pace.high == huge and "?" or format("%.1f", oneDecimal(pace.high)),
        pace.k,
        pace.c
    )
end

local function forecastLine(text, target, forecast)
    if not forecast.mean then
        return format(L.SKILL_TO_UNKNOWN, text, target, forecast.points)
    end
    local line = format(
        L.SKILL_TO,
        text,
        target,
        forecast.points,
        round(forecast.mean),
        round(forecast.low),
        upper(forecast.high)
    )
    if forecast.seconds then
        line = line .. format(L.SKILL_TO_TIME, HudModel.Duration(forecast.seconds))
    end
    return line
end

-- input: { formatDate(t) }. Text lines of the Skill tab.
function SkillTable.Lines(model, input)
    local lines = {}
    if model.max then
        lines[1] = format(L.SKILL_RANK_MAX, model.rank, model.max)
    else
        lines[1] = format(L.SKILL_RANK, model.rank)
    end
    if model.firstTime then
        lines[#lines + 1] = format(L.SKILL_FIRST, model.first, input.formatDate(model.firstTime))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L.SKILL_PACE_HEADER
    lines[#lines + 1] = SkillTable.PaceText(model.pace)
    lines[#lines + 1] = format(L.SKILL_SINCE, model.since)
    lines[#lines + 1] = ""
    if model.rank >= ns.SkillModel.TOP then
        lines[#lines + 1] = L.SKILL_DONE
        return lines
    end
    if model.atCap then
        lines[#lines + 1] = format(L.SKILL_AT_CAP, model.max)
    else
        lines[#lines + 1] = forecastLine(L.SKILL_TO_CAP, model.toCap.cap, model.toCap)
    end
    lines[#lines + 1] = forecastLine(L.SKILL_TO_TOP, ns.SkillModel.TOP, model.toTop)
    lines[#lines + 1] = ""
    lines[#lines + 1] = L.SKILL_NOTE
    return lines
end

-- The tooltip of a rank point as draw(tip): "Rank 20" and the date in grey.
function SkillTable.RankTip(rank, date)
    return function(tip)
        tip:Title(format(L.SKILL_TIP_RANK, rank))
        tip:Line(date, Style.GREY)
    end
end

-- The tooltip of a band of ranks as draw(tip): catches per point with its range (grey "too few"
-- below the count rule), the points, and the catches.
function SkillTable.PaceTip(title, pace)
    return function(tip)
        tip:Title(title)
        if not pace.mean or pace.display == "count" then
            tip:Pair(L.SKILL_TIP_PACE, L.TIP_FEW, Style.GREY)
        else
            local high = pace.high == huge and "?" or format("%.1f", oneDecimal(pace.high))
            local value = Style.Range(
                format("%.1f", oneDecimal(pace.mean)),
                format("%.1f", oneDecimal(pace.low)),
                high
            )
            tip:Pair(L.SKILL_TIP_PACE, value, pace.display == "few" and Style.GREY or nil)
        end
        tip:Pair(L.SKILL_TIP_POINTS, Style.Number(pace.k))
        tip:Pair(L.SKILL_TIP_CATCHES, Style.Number(pace.c))
    end
end

-- Line chart of the rank over time; input: { formatDate(t) }.
function SkillTable.RankChart(model, input)
    local points = {}
    for i, entry in ipairs(model.timeline) do
        points[i] = {
            x = entry.t,
            y = entry.rank,
            tip = SkillTable.RankTip(entry.rank, input.formatDate(entry.t)),
        }
    end
    local chart = ChartModel.Line(points)
    chart.labels = {}
    for i, x in ipairs(chart.xticks) do
        chart.labels[i] = input.formatDate(x)
    end
    return chart
end

-- Bars of catches per skill point by band of ranks, or nil without a completed point.
function SkillTable.BandChart(model)
    local bars = {}
    for _, band in ipairs(model.bands) do
        local pace = band.pace
        if pace.mean then
            local range = format("%d-%d", band.from, band.to)
            local high = pace.high ~= huge and pace.high or nil
            bars[#bars + 1] = {
                label = range,
                value = pace.mean,
                low = high and pace.low or nil,
                high = high,
                text = format("%.1f", oneDecimal(pace.mean)),
                grey = pace.display ~= "full",
                tip = SkillTable.PaceTip(format(L.SKILL_TIP_BAND, range), pace),
            }
        end
    end
    if #bars == 0 then
        return nil
    end
    return ChartModel.Build(bars)
end
