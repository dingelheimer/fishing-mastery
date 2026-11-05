-- Calendar heatmap widget for the Overview: a title and a grid of WEEKS × 7 day cells (one color
-- texture on a mouse-enabled frame each, created once), colored by CalendarModel levels, with the
-- day's date and numbers in the tooltip (color is never the only carrier). Weekday labels on the
-- left. Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, ipairs, pairs, floor, format =
    setmetatable, ipairs, pairs, math.floor, string.format
local L, CalendarModel = ns.L, ns.CalendarModel

local Heatmap = {}
Heatmap.__index = Heatmap
ns.Heatmap = Heatmap

Heatmap.CELL, Heatmap.GAP = 10, 2
Heatmap.LEFT, Heatmap.TOP = 30, 16 -- weekday labels, title
Heatmap.HEIGHT = Heatmap.TOP + 7 * (Heatmap.CELL + Heatmap.GAP)
Heatmap.DAY_LABELS = { [1] = "HEAT_MON", [4] = "HEAT_THU", [7] = "HEAT_SUN" }

local function onEnter(owner)
    local tip = owner.env.GameTooltip
    if tip and owner.tip then
        tip:SetOwner(owner, "ANCHOR_TOP")
        tip:SetText(owner.tip[1] or "")
        for i = 2, #owner.tip do
            tip:AddLine(owner.tip[i], 1, 1, 1, true)
        end
        tip:Show()
    end
end

local function onLeave(owner)
    local tip = owner.env.GameTooltip
    if tip then
        tip:Hide()
    end
end

local function cell(self, index)
    local step = Heatmap.CELL + Heatmap.GAP
    local col, row = (index - 1) % CalendarModel.WEEKS, floor((index - 1) / CalendarModel.WEEKS)
    local frame = self.env.CreateFrame("Frame", nil, self.frame)
    frame:SetSize(Heatmap.CELL, Heatmap.CELL)
    frame:SetPoint(
        "TOPLEFT",
        self.frame,
        "TOPLEFT",
        Heatmap.LEFT + col * step,
        -(Heatmap.TOP + row * step)
    )
    frame:EnableMouse(true)
    frame.env = self.env
    frame:SetScript("OnEnter", ns.Guard.Wrap("heatmap:tooltip", onEnter))
    frame:SetScript("OnLeave", onLeave)
    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetAllPoints(frame)
    return frame
end

-- parent: the frame the heatmap is drawn in; width in pixels.
function Heatmap.Create(env, parent, width)
    local self = setmetatable({ env = env, cells = {} }, Heatmap)
    self.frame = env.CreateFrame("Frame", nil, parent)
    self.frame:SetSize(width, Heatmap.HEIGHT)
    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.title:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    self.title:SetWidth(width)
    self.title:SetJustifyH("LEFT")
    local step = Heatmap.CELL + Heatmap.GAP
    for row, key in pairs(Heatmap.DAY_LABELS) do
        local text = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -(Heatmap.TOP + (row - 1) * step))
        text:SetText(L[key])
    end
    for i = 1, CalendarModel.WEEKS * 7 do
        self.cells[i] = cell(self, i)
    end
    return self
end

-- Draws CalendarModel.Build(days, today); input: { formatDay(day) }. Cells after today are
-- hidden.
function Heatmap:Draw(model, input)
    self.title:SetText(format(L.HEAT_TITLE, CalendarModel.WEEKS, model.fishing))
    for _, frame in ipairs(self.cells) do
        frame:Hide()
    end
    for _, entry in ipairs(model.cells) do
        local frame = self.cells[(entry.row - 1) * CalendarModel.WEEKS + entry.col]
        local color = CalendarModel.COLORS[entry.level]
        frame.texture:SetColorTexture(color[1], color[2], color[3], color[4])
        local numbers = entry.casts > 0 and format(L.HEAT_TIP, entry.casts, entry.catches)
            or L.HEAT_TIP_NONE
        frame.tip = { input.formatDay(entry.day), numbers }
        frame:Show()
    end
    self.drawn = model
end
