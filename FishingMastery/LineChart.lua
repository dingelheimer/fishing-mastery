-- Line chart widget for the stats window: a title, y axis labels with faint grid lines, one line
-- segment between neighbouring points (Frame:CreateLine, confirmed on live in Story 3.1), x labels,
-- and an invisible hover frame per point with its tooltip. Without CreateLine (the Story 3.1
-- fallback) and for a single point, each point is a small square. Lines, textures, font strings,
-- and hover frames are pooled and reused on every draw. Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, ipairs, max, min = setmetatable, ipairs, math.max, math.min
local ChartModel = ns.ChartModel

local LineChart = {}
LineChart.__index = LineChart
ns.LineChart = LineChart

LineChart.LEFT, LineChart.BOTTOM, LineChart.TOP, LineChart.RIGHT = 40, 16, 22, 30
LineChart.THICKNESS = 2
-- Colors of the style kit (Style.lua): the skill bar blue and the grid.
LineChart.LINE = { ns.Style.SKILL[1], ns.Style.SKILL[2], ns.Style.SKILL[3], 1 }
LineChart.GRID = ns.Style.GRID
LineChart.DOT = 3 -- fallback square size
LineChart.HOVER = 12 -- hover frame width around a point (at most)

-- parent: the frame the chart is drawn in, width × height in pixels.
function LineChart.Create(env, parent, width, height)
    local self = setmetatable({
        env = env,
        frame = env.CreateFrame("Frame", nil, parent),
        width = width,
        height = height,
        lines = { list = {}, used = 0 },
        textures = { list = {}, used = 0 },
        labels = { list = {}, used = 0 },
        hovers = { list = {}, used = 0 },
    }, LineChart)
    self.frame:SetSize(width, height)
    self.title = self.frame:CreateFontString(nil, "OVERLAY", ns.Style.FONTS.smallLabel)
    self.title:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    self.title:SetWidth(width)
    self.title:SetJustifyH("LEFT")
    return self
end

local function acquire(pool, make)
    pool.used = pool.used + 1
    local item = pool.list[pool.used]
    if not item then
        item = make()
        pool.list[pool.used] = item
    end
    item:Show()
    return item
end

local function texture(self, color, x, y, w, h)
    local tex = acquire(self.textures, function()
        return self.frame:CreateTexture(nil, "ARTWORK")
    end)
    tex:ClearAllPoints()
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
    tex:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, y)
    tex:SetSize(max(1, w), max(1, h))
end

local function label(self, text, point, x, y, width, justify)
    local fs = acquire(self.labels, function()
        return self.frame:CreateFontString(nil, "OVERLAY", ns.Style.FONTS.small)
    end)
    fs:ClearAllPoints()
    fs:SetPoint(point, self.frame, "BOTTOMLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "CENTER")
    fs:SetText(text)
end

local function segment(self, x1, y1, x2, y2)
    local line = acquire(self.lines, function()
        local made = self.frame:CreateLine(nil, "ARTWORK")
        made:SetThickness(LineChart.THICKNESS)
        made:SetColorTexture(
            LineChart.LINE[1],
            LineChart.LINE[2],
            LineChart.LINE[3],
            LineChart.LINE[4]
        )
        return made
    end)
    line:SetStartPoint("BOTTOMLEFT", self.frame, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", self.frame, x2, y2)
end

local function hover(self, point, x, width, plotH)
    local frame = acquire(self.hovers, function()
        local f = self.env.CreateFrame("Frame", nil, self.frame)
        f:EnableMouse(true)
        f:SetScript(
            "OnEnter",
            ns.Guard.Wrap("chart:tooltip", function(owner)
                if owner.tip then
                    ns.Tip.Lines(self.env, owner, owner.tip, "ANCHOR_TOP")
                end
            end)
        )
        f:SetScript("OnLeave", function(owner)
            ns.Tip.Close(self.env, owner)
        end)
        return f
    end)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x - width / 2, LineChart.BOTTOM)
    frame:SetSize(max(1, width), max(1, plotH))
    frame.tip = point.tip
end

local function reset(self)
    for _, pool in ipairs({ self.lines, self.textures, self.labels, self.hovers }) do
        for _, item in ipairs(pool.list) do
            item:Hide()
        end
        pool.used = 0
    end
end

local function axes(self, chart, plotW, plotH)
    local left, bottom = LineChart.LEFT, LineChart.BOTTOM
    for _, value in ipairs(chart.axis.ticks) do
        local y = bottom + value / chart.axis.max * plotH
        texture(self, LineChart.GRID, left, y, plotW, 1)
        label(self, ChartModel.TickText(value), "RIGHT", left - 4, y, left - 4, "RIGHT")
    end
    local width = plotW / max(#chart.xticks - 1, 1)
    for i, x in ipairs(chart.xticks) do
        local px = left + ChartModel.Place(chart, x, 0, plotW, plotH)
        label(self, chart.labels and chart.labels[i] or "", "TOP", px, bottom - 2, width)
    end
end

-- Draws a chart (ChartModel.Line, optional labels per x tick) under a title; without a chart, the
-- title and a message.
function LineChart:Draw(title, chart, message)
    reset(self)
    self.title:SetText(title)
    self.drawn = chart
    if not chart then
        label(self, message or "", "CENTER", self.width / 2, self.height / 2, self.width)
        return
    end
    local plotW = self.width - LineChart.LEFT - LineChart.RIGHT
    local plotH = self.height - LineChart.BOTTOM - LineChart.TOP
    axes(self, chart, plotW, plotH)
    local useLines = self.frame.CreateLine ~= nil and #chart.points > 1
    local hoverW = min(LineChart.HOVER, plotW / max(#chart.points, 1))
    local px, py
    for _, point in ipairs(chart.points) do
        local x, y = ChartModel.Place(chart, point.x, point.y, plotW, plotH)
        x, y = LineChart.LEFT + x, LineChart.BOTTOM + y
        if not useLines then
            local half = LineChart.DOT / 2
            texture(self, LineChart.LINE, x - half, y - half, LineChart.DOT, LineChart.DOT)
        elseif px then
            segment(self, px, py, x, y)
        end
        hover(self, point, x, hoverW, plotH)
        px, py = x, y
    end
end
