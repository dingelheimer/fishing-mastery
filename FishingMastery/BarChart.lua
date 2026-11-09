-- Bar chart widget for the stats window: a title, y axis labels with faint grid lines, one color
-- texture per bar, a range mark (95 % range from low to high, with caps) where the chart has
-- ranges, a reference mark (a line across the bar, e.g. the Classic model), value labels above
-- bars wide enough for them, x labels at a step, and an invisible hover frame per bar with its
-- tooltip. Textures, font strings, and hover frames are pooled and reused on every draw. Unnamed,
-- insecure frames only.
local _, ns = ...

local setmetatable, ipairs, max, floor = setmetatable, ipairs, math.max, math.floor
local ChartModel = ns.ChartModel

local BarChart = {}
BarChart.__index = BarChart
ns.BarChart = BarChart

BarChart.LEFT, BarChart.BOTTOM, BarChart.TOP = 40, 16, 30 -- plot margins (title + value labels)
BarChart.VALUE_MIN_SLOT = 18 -- value labels only for slots at least this wide
-- Colors of the style kit (Style.lua): the skill bar blue, grey small samples, gold ranges.
local Style = ns.Style
BarChart.BAR = { Style.SKILL[1], Style.SKILL[2], Style.SKILL[3], 1 }
BarChart.BAR_GREY = { Style.GREY[1], Style.GREY[2], Style.GREY[3], 1 }
BarChart.RANGE = { Style.GOLD[1], Style.GOLD[2], Style.GOLD[3], 1 }
BarChart.GRID = Style.GRID
BarChart.MARK = { 1, 1, 1, 0.9 }

-- parent: the frame the chart is drawn in, width × height in pixels.
function BarChart.Create(env, parent, width, height)
    local self = setmetatable({
        env = env,
        frame = env.CreateFrame("Frame", nil, parent),
        width = width,
        height = height,
        textures = { list = {}, used = 0 },
        labels = { list = {}, used = 0 },
        hovers = { list = {}, used = 0 },
    }, BarChart)
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
    item:ClearAllPoints()
    item:Show()
    return item
end

local function texture(self, color, x, y, w, h)
    local tex = acquire(self.textures, function()
        return self.frame:CreateTexture(nil, "ARTWORK")
    end)
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
    tex:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, y)
    tex:SetSize(max(1, w), max(1, h))
    return tex
end

local function label(self, text, point, x, y, width, justify)
    local fs = acquire(self.labels, function()
        return self.frame:CreateFontString(nil, "OVERLAY", ns.Style.FONTS.small)
    end)
    fs:SetPoint(point, self.frame, "BOTTOMLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "CENTER")
    fs:SetText(text)
    return fs
end

local function hover(self, bar, x, y, w, h)
    local frame = acquire(self.hovers, function()
        local f = self.env.CreateFrame("Frame", nil, self.frame)
        f:EnableMouse(true)
        f:SetScript(
            "OnEnter",
            ns.Guard.Wrap("chart:tooltip", function(owner)
                if owner.tip then
                    ns.Tip.Open(self.env, owner, owner.tip, "ANCHOR_TOP")
                end
            end)
        )
        f:SetScript("OnLeave", function(owner)
            ns.Tip.Close(self.env, owner)
        end)
        return f
    end)
    frame:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, y)
    frame:SetSize(max(1, w), max(1, h))
    frame.tip = bar.tip
end

local function reset(self)
    for _, pool in ipairs({ self.textures, self.labels, self.hovers }) do
        for _, item in ipairs(pool.list) do
            item:Hide()
        end
        pool.used = 0
    end
end

local function axis(self, chart, plotW, plotH)
    local left, bottom = BarChart.LEFT, BarChart.BOTTOM
    for _, value in ipairs(chart.axis.ticks) do
        local y = bottom + value / chart.axis.max * plotH
        texture(self, BarChart.GRID, left, y, plotW, 1)
        label(
            self,
            ChartModel.TickText(value, chart.percent),
            "RIGHT",
            left - 4,
            y,
            left - 4,
            "RIGHT"
        )
    end
end

local function bars(self, chart, plotW, plotH)
    local left, bottom = BarChart.LEFT, BarChart.BOTTOM
    local n = #chart.bars
    local layout = ChartModel.Layout(n, plotW)
    local every = ChartModel.LabelEvery(n)
    local scale = plotH / chart.axis.max
    for i, bar in ipairs(chart.bars) do
        local x = left + layout.x(i)
        local h = (bar.value or 0) * scale
        texture(self, bar.grey and BarChart.BAR_GREY or BarChart.BAR, x, bottom, layout.bar, h)
        local top = h
        if bar.low and bar.high then
            local mid = x + floor(layout.bar / 2)
            local low, high = bottom + bar.low * scale, bottom + bar.high * scale
            local cap = max(3, floor(layout.bar * 0.6))
            texture(self, BarChart.RANGE, mid - 1, low, 2, high - low)
            texture(self, BarChart.RANGE, mid - floor(cap / 2), low, cap, 1)
            texture(self, BarChart.RANGE, mid - floor(cap / 2), high, cap, 1)
            top = max(top, high - bottom)
        end
        if bar.mark then
            local y = bottom + bar.mark * scale
            texture(self, BarChart.MARK, x - 2, y - 1, layout.bar + 4, 2)
            top = max(top, y + 1 - bottom)
        end
        if layout.slot >= BarChart.VALUE_MIN_SLOT and bar.text then
            label(self, bar.text, "BOTTOM", x + layout.bar / 2, bottom + top + 2, layout.slot)
        end
        if (i - 1) % every == 0 then
            label(self, bar.label, "TOP", x + layout.bar / 2, bottom - 2, layout.slot * every)
        end
        hover(self, bar, left + (i - 1) * layout.slot, bottom, layout.slot, plotH)
    end
end

-- Draws a chart (ChartModel.Build) under a title; without a chart, the title and a message.
function BarChart:Draw(title, chart, message)
    reset(self)
    self.title:SetText(title)
    self.drawn = chart
    if not chart then
        label(self, message or "", "CENTER", self.width / 2, self.height / 2, self.width)
        return
    end
    local plotW = self.width - BarChart.LEFT - 4
    local plotH = self.height - BarChart.BOTTOM - BarChart.TOP
    axis(self, chart, plotW, plotH)
    bars(self, chart, plotW, plotH)
end
