-- Pure logic: bar chart math for the stats window. Nice axis scales (steps of 1, 2, 2.5, 5 × 10^k),
-- histogram bins from tenth-second keys, bar positions in a plot width, and the label step that
-- keeps the x labels apart. A chart is { bars = { { label, value, low, high, text, grey, tip } },
-- axis = Scale, percent }; a line chart (Line) holds points with an x range. No frame or API calls.
local _, ns = ...

local floor, ceil, max, log10, format, ipairs, pairs, type =
    math.floor, math.ceil, math.max, math.log10, string.format, ipairs, pairs, type

local ChartModel = {}
ns.ChartModel = ChartModel

ChartModel.NICE = { 1, 2, 2.5, 5, 10 }
ChartModel.STEPS = 4 -- axis steps above 0 at most
ChartModel.BAR_SHARE = 0.7 -- bar width of its slot
ChartModel.MAX_LABELS = 10 -- x labels at most

-- Axis from 0 to at least top: { max, step, ticks = { 0, step, ... } }. integer: counts
-- (steps of at least 1). top <= 0 gives a 0-1 axis.
function ChartModel.Scale(top, integer, steps)
    steps = steps or ChartModel.STEPS
    if type(top) ~= "number" or top <= 0 then
        top = 1
    end
    local raw = top / steps
    local magnitude = 10 ^ floor(log10(raw))
    local step = magnitude * 10
    for _, nice in ipairs(ChartModel.NICE) do
        if nice * magnitude * steps >= top then
            step = nice * magnitude
            break
        end
    end
    if integer and step < 1 then
        step = 1
    end
    local count = ceil(top / step - 1e-9)
    local ticks = {}
    for i = 0, count do
        ticks[#ticks + 1] = i * step
    end
    return { max = count * step, step = step, ticks = ticks }
end

-- Counts per bin of size tenths from a { [tenths] = count } histogram: bins 1..ceil(limit/size);
-- keys at or above limit go into the last bin, negative keys are skipped.
function ChartModel.Bins(histogram, size, limit)
    local n = ceil(limit / size)
    local bins = {}
    for i = 1, n do
        bins[i] = 0
    end
    for key, count in pairs(histogram or {}) do
        if type(key) == "number" and key >= 0 and type(count) == "number" then
            local index = floor(key / size) + 1
            if index > n then
                index = n
            end
            bins[index] = bins[index] + count
        end
    end
    return bins
end

-- Slot and bar width for n bars in width, and the left edge of bar i: { slot, bar, x(i) }.
function ChartModel.Layout(n, width)
    local slot = width / max(n, 1)
    local bar = max(1, floor(slot * ChartModel.BAR_SHARE))
    return {
        slot = slot,
        bar = bar,
        x = function(i)
            return (i - 1) * slot + (slot - bar) / 2
        end,
    }
end

-- Every how many bars an x label is drawn.
function ChartModel.LabelEvery(n, maxLabels)
    return max(1, ceil(n / (maxLabels or ChartModel.MAX_LABELS)))
end

-- Text of an axis value: "25 %" on a percent axis (values 0-1), else the number.
function ChartModel.TickText(value, percent)
    if percent then
        return format("%d %%", floor(value * 100 + 0.5))
    end
    if value == floor(value) then
        return format("%d", value)
    end
    return format("%.1f", value)
end

-- A chart of bars with its axis: the axis covers the highest value or upper range bound.
function ChartModel.Build(bars, percent)
    local top = 0
    for _, bar in ipairs(bars) do
        top = max(top, bar.high or 0, bar.value or 0)
    end
    if percent and top > 1 then
        top = 1
    end
    return { bars = bars, axis = ChartModel.Scale(top, not percent), percent = percent }
end

ChartModel.LINE_LABELS = 4 -- x labels of a line chart

-- A line chart of points { x, y, tip } (x ascending): a y axis from 0 (counts), the x range of
-- the points, and up to labels evenly spaced x values for labels: { points, axis, xmin, xmax,
-- xticks }. A single point gets a range of 1 around it.
function ChartModel.Line(points, labels)
    local top = 0
    for _, point in ipairs(points) do
        top = max(top, point.y or 0)
    end
    local xmin, xmax = points[1].x, points[#points].x
    if xmax <= xmin then
        xmin, xmax = xmin - 0.5, xmin + 0.5
    end
    local n = labels or ChartModel.LINE_LABELS
    local xticks = {}
    for i = 0, n - 1 do
        xticks[#xticks + 1] = xmin + (xmax - xmin) * i / max(n - 1, 1)
    end
    return {
        points = points,
        axis = ChartModel.Scale(top, true),
        xmin = xmin,
        xmax = xmax,
        xticks = xticks,
    }
end

-- Position of (x, y) in a plot of width × height (from its bottom left corner).
function ChartModel.Place(chart, x, y, width, height)
    return (x - chart.xmin) / (chart.xmax - chart.xmin) * width, y / chart.axis.max * height
end
