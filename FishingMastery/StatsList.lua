-- A table for the windows: a gold header bar (StatsListHeader) over a
-- ScrollBox list with a scroll bar (APIs confirmed on live in Story 3.1), in the table style of
-- Epic 9 (Draft 2): striped rows, a gold hover highlight, numbers right-aligned with thousands
-- separators, optional item icons, per-cell colors (quality), small tags (season, night), grey
-- cells for small samples, and an optional legend line. Rows come from the table builders:
-- cells per column, .grey[i], .colors[i] ({ r, g, b }), .icons[i] (texture), .tags[i]
-- ({ text, kind }), .color for every cell, .selected (first cell gold), and the tooltip as
-- .tip(tip) (Tip builder) or .tooltip (lines). With onSelect a click on a row selects it.
-- Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, ipairs, pcall, type = setmetatable, ipairs, pcall, type
local Style = ns.Style
local Header = ns.StatsListHeader

local StatsList = {}
StatsList.__index = StatsList
ns.StatsList = StatsList

StatsList.ROW_HEIGHT = 18
StatsList.HEADER_HEIGHT = Header.HEIGHT
StatsList.LEGEND_HEIGHT = 16
StatsList.ICON = 16
StatsList.SCROLLBAR_WIDTH = 16
StatsList.SCROLL_TEMPLATE = "WowScrollBoxList"
StatsList.SCROLLBAR_TEMPLATE = "MinimalScrollBar"
StatsList.ARROW_DOWN, StatsList.ARROW_UP = Header.ARROW_DOWN, Header.ARROW_UP
StatsList.TAGS =
    { season = { Style.SEASON, Style.TAG_SEASON }, night = { Style.NIGHT, Style.TAG_NIGHT } }
StatsList.GREY, StatsList.WHITE, StatsList.GOLD = Style.GREY, Style.WHITE, Style.GOLD

local tint = Header.Tint

local function showTooltip(self, row)
    local data = row.data
    if not data then
        return
    end
    if type(data.tip) == "function" then
        ns.Tip.Open(self.env, row, data.tip)
        return
    end
    if data.tooltip then
        ns.Tip.Lines(self.env, row, data.tooltip)
    end
end

local function buildCell(row, i, column, x)
    local cell = row:CreateFontString(nil, "OVERLAY", Style.FONTS.small)
    local inset = column.icon and StatsList.ICON + 5 or 3
    cell:SetPoint("LEFT", row, "LEFT", x + inset, 0)
    cell:SetWidth(column.width - inset - 3)
    cell:SetJustifyH(column.right and "RIGHT" or "LEFT")
    cell:SetWordWrap(false)
    row.cells[i] = cell
    if column.icon then
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(StatsList.ICON, StatsList.ICON)
        icon:SetPoint("LEFT", row, "LEFT", x + 2, 0)
        row.icons[i] = icon
    end
    if column.tags then
        local tag = row:CreateFontString(nil, "OVERLAY", Style.FONTS.smallLabel)
        local back = row:CreateTexture(nil, "BORDER")
        back:SetPoint("TOPLEFT", tag, "TOPLEFT", -3, 1)
        back:SetPoint("BOTTOMRIGHT", tag, "BOTTOMRIGHT", 3, -1)
        row.tags[i] = { text = tag, back = back }
    end
end

local function buildRow(self, row)
    row.cells, row.icons, row.tags = {}, {}, {}
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints(row)
    tint(row.stripe, Style.STRIPE)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints(row)
    tint(row.hover, Style.HOVER)
    row.hover:Hide()
    local x = 0
    for i, column in ipairs(self.columns) do
        buildCell(row, i, column, x)
        x = x + column.width
    end
    row:EnableMouse(true)
    row:SetScript(
        "OnEnter",
        ns.Guard.Wrap("stats:tooltip", function(frame)
            frame.hover:Show()
            showTooltip(self, frame)
        end)
    )
    row:SetScript("OnLeave", function(frame)
        frame.hover:Hide()
        ns.Tip.Close(self.env, frame)
    end)
    if self.onSelect then
        row:SetScript(
            "OnMouseUp",
            ns.Guard.Wrap("stats:select", function(frame)
                if frame.data then
                    self.onSelect(frame.data)
                end
            end)
        )
    end
end

local function drawTag(row, i, cell, tag)
    local slot = row.tags[i]
    if not slot then
        return
    end
    local style = tag and StatsList.TAGS[tag.kind]
    slot.text:SetShown(style ~= nil)
    slot.back:SetShown(style ~= nil)
    if not style then
        return
    end
    slot.text:ClearAllPoints()
    slot.text:SetPoint("LEFT", cell, "LEFT", cell:GetStringWidth() + 8, 0)
    slot.text:SetText(tag.text)
    slot.text:SetTextColor(style[1][1], style[1][2], style[1][3])
    tint(slot.back, style[2])
end

local function initRow(self, row, data)
    if not row.cells then
        buildRow(self, row)
    end
    row.data = data
    row.stripe:SetShown((self.index[data] or 1) % 2 == 0)
    for i, cell in ipairs(row.cells) do
        local value = data.cells[i]
        cell:SetText(type(value) == "number" and Style.Number(value) or value or "")
        local color = data.grey and data.grey[i] and StatsList.GREY
            or data.colors and data.colors[i]
            or data.color
            or StatsList.WHITE
        if data.selected and i == 1 then
            color = StatsList.GOLD
        end
        cell:SetTextColor(color[1], color[2], color[3])
        local icon = row.icons[i]
        if icon then
            local texture = data.icons and data.icons[i]
            icon:SetTexture(texture)
            icon:SetShown(texture ~= nil)
        end
        drawTag(row, i, cell, data.tags and data.tags[i])
    end
end

local function placeBox(self)
    local box, parent = self.box, self.parent
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -StatsList.HEADER_HEIGHT - 4)
    local bottom = self.legend and StatsList.LEGEND_HEIGHT or 0
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -StatsList.SCROLLBAR_WIDTH - 4, bottom)
end

local function scrollBox(self, parent)
    local env = self.env
    local box = env.CreateFrame("Frame", nil, parent, StatsList.SCROLL_TEMPLATE)
    self.box = box
    placeBox(self)
    local ok, bar = pcall(env.CreateFrame, "EventFrame", nil, parent, StatsList.SCROLLBAR_TEMPLATE)
    if not ok or not bar then
        bar = env.CreateFrame("Frame", nil, parent, StatsList.SCROLLBAR_TEMPLATE)
    end
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = env.CreateScrollBoxListLinearView()
    view:SetElementExtent(StatsList.ROW_HEIGHT)
    view:SetElementInitializer(
        "Frame",
        ns.Guard.Wrap("stats:row", function(row, data)
            initRow(self, row, data)
        end)
    )
    env.ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
end

-- parent: the frame the list fills. columns: { { key, label, width, right, icon, tags } }.
-- onSort(key): optional; makes the header cells buttons. onSelect(rowData): optional; makes
-- rows clickable.
function StatsList.Create(env, parent, columns, onSort, onSelect)
    local self = setmetatable({
        env = env,
        parent = parent,
        columns = columns,
        onSort = onSort,
        onSelect = onSelect,
        index = {},
    }, StatsList)
    Header.Build(self, parent)
    scrollBox(self, parent)
    return self
end

-- A grey line under the list (what grey or "~" values mean); nil removes it.
function StatsList:SetLegend(text)
    if text and not self.legendText then
        self.legendText = self.parent:CreateFontString(nil, "OVERLAY", Style.FONTS.secondary)
        self.legendText:SetPoint("BOTTOMLEFT", self.parent, "BOTTOMLEFT", 4, 2)
        self.legendText:SetJustifyH("LEFT")
    end
    if self.legendText then
        self.legendText:SetText(text or "")
        self.legendText:SetShown(text ~= nil)
    end
    self.legend = text ~= nil
    placeBox(self)
end

-- Shows the rows; keepScroll keeps the scroll position (item names that loaded later); sort
-- ({ key, descending }) puts the arrow on the sorted column.
function StatsList:SetRows(rows, keepScroll, sort)
    local env = self.env
    self.index = {}
    for i, data in ipairs(rows) do
        self.index[data] = i
    end
    Header.DrawSort(self, sort)
    local provider = env.CreateDataProvider(rows)
    local constants = env.ScrollBoxConstants
    if keepScroll and constants and constants.RetainScrollPosition then
        self.box:SetDataProvider(provider, constants.RetainScrollPosition)
    else
        self.box:SetDataProvider(provider)
    end
    self.rows = rows
end
