-- A table for the stats window: a header (sort buttons or labels) over a ScrollBox list with a
-- scroll bar (APIs confirmed on live in Story 3.1). Rows come from the table builders
-- (StatsTables, ZoneTable, OverviewTable): cells per column, grey cells for small samples, and
-- tooltip lines shown on hover; with onSelect a click on a row selects it (row data .selected
-- draws its first cell in gold). Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, ipairs, pcall = setmetatable, ipairs, pcall
local Frames = ns.Frames

local StatsList = {}
StatsList.__index = StatsList
ns.StatsList = StatsList

StatsList.ROW_HEIGHT = 18
StatsList.HEADER_HEIGHT = 20
StatsList.SCROLLBAR_WIDTH = 16
StatsList.SCROLL_TEMPLATE = "WowScrollBoxList"
StatsList.SCROLLBAR_TEMPLATE = "MinimalScrollBar"
StatsList.GREY, StatsList.WHITE = { 0.55, 0.55, 0.55 }, { 1, 1, 1 }
StatsList.GOLD = { 1, 0.82, 0 }

local function header(self, parent)
    local x = 0
    self.headers = {}
    for _, column in ipairs(self.columns) do
        local cell
        if self.onSort then
            local key = column.key
            cell = Frames.Button(self.env, parent, column.label, column.width - 2, function()
                self.onSort(key)
            end)
            cell:SetSize(column.width - 2, StatsList.HEADER_HEIGHT)
        else
            cell = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            cell:SetWidth(column.width - 6)
            cell:SetJustifyH(column.right and "RIGHT" or "LEFT")
            cell:SetText(column.label)
        end
        cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (self.onSort and 0 or 3), 0)
        self.headers[#self.headers + 1] = cell
        x = x + column.width
    end
end

local function showTooltip(self, row)
    local tip, data = self.env.GameTooltip, row.data
    if not tip or not data or not data.tooltip then
        return
    end
    tip:SetOwner(row, "ANCHOR_RIGHT")
    tip:SetText(data.tooltip[1] or "")
    for i = 2, #data.tooltip do
        tip:AddLine(data.tooltip[i], 1, 1, 1, true)
    end
    tip:Show()
end

local function buildRow(self, row)
    row.cells = {}
    local x = 0
    for i, column in ipairs(self.columns) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell:SetPoint("LEFT", row, "LEFT", x + 3, 0)
        cell:SetWidth(column.width - 6)
        cell:SetJustifyH(column.right and "RIGHT" or "LEFT")
        cell:SetWordWrap(false)
        row.cells[i] = cell
        x = x + column.width
    end
    row:EnableMouse(true)
    row:SetScript(
        "OnEnter",
        ns.Guard.Wrap("stats:tooltip", function(frame)
            showTooltip(self, frame)
        end)
    )
    row:SetScript("OnLeave", function()
        local tip = self.env.GameTooltip
        if tip then
            tip:Hide()
        end
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

local function initRow(self, row, data)
    if not row.cells then
        buildRow(self, row)
    end
    row.data = data
    for i, cell in ipairs(row.cells) do
        cell:SetText(data.cells[i] or "")
        local color = data.grey and data.grey[i] and StatsList.GREY or StatsList.WHITE
        if data.selected and i == 1 then
            color = StatsList.GOLD
        end
        cell:SetTextColor(color[1], color[2], color[3])
    end
end

local function scrollBox(self, parent)
    local env = self.env
    local box = env.CreateFrame("Frame", nil, parent, StatsList.SCROLL_TEMPLATE)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -StatsList.HEADER_HEIGHT - 4)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -StatsList.SCROLLBAR_WIDTH - 4, 0)
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
    self.box = box
end

-- parent: the frame the list fills. columns: { { key, label, width, right } }. onSort(key):
-- optional; makes the header cells buttons. onSelect(rowData): optional; makes rows clickable.
function StatsList.Create(env, parent, columns, onSort, onSelect)
    local self = setmetatable(
        { env = env, columns = columns, onSort = onSort, onSelect = onSelect },
        StatsList
    )
    header(self, parent)
    scrollBox(self, parent)
    return self
end

-- Shows the rows; keepScroll keeps the scroll position (item names that loaded later).
function StatsList:SetRows(rows, keepScroll)
    local env = self.env
    local provider = env.CreateDataProvider(rows)
    local constants = env.ScrollBoxConstants
    if keepScroll and constants and constants.RetainScrollPosition then
        self.box:SetDataProvider(provider, constants.RetainScrollPosition)
    else
        self.box:SetDataProvider(provider)
    end
    self.rows = rows
end
