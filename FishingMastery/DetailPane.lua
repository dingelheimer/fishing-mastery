-- A detail pane in the tooltip and table style (the journal's Fish tab): draws a builder function
-- top-down into pooled font strings: a title, short grey or colored lines, gold label and value
-- pairs (the value right-aligned), gaps, and small three-column tables (a gold header row, then
-- rows: the first cell left, the others right). Nothing wraps; long texts are cut by the font
-- string. Rows that do not fit the height are hidden. Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, ipairs, pairs = setmetatable, ipairs, pairs
local Style = ns.Style

local DetailPane = {}
DetailPane.__index = DetailPane
ns.DetailPane = DetailPane

DetailPane.TITLE, DetailPane.LINE, DetailPane.GAP = 20, 15, 8 -- row heights
DetailPane.LABEL = 100 -- width of a pair's label
DetailPane.NUMBER = 46 -- width of the second and third table columns
DetailPane.SPACE = 6

-- parent: the frame the pane sits in; x, y: its top left in parent; width, height in pixels.
function DetailPane.Create(env, parent, x, y, width, height)
    local self = setmetatable({ env = env, width = width, height = height }, DetailPane)
    local frame = env.CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, height)
    self.frame = frame
    self.pools = {}
    return self
end

local function text(self, font)
    local pool = self.pools[font]
    if not pool then
        pool = { list = {}, used = 0 }
        self.pools[font] = pool
    end
    pool.used = pool.used + 1
    local fs = pool.list[pool.used]
    if not fs then
        fs = self.frame:CreateFontString(nil, "OVERLAY", font)
        fs:SetWordWrap(false)
        pool.list[pool.used] = fs
    end
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

-- One font string at x in the current row, width w, justified, colored.
local function cell(self, font, value, x, w, justify, color)
    local fs = text(self, font)
    fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -self.y)
    fs:SetWidth(w)
    fs:SetJustifyH(justify)
    color = color or Style.WHITE
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetText(value)
    if self.y + DetailPane.LINE > self.height then
        fs:Hide()
    end
    self.cells[#self.cells + 1] = fs
    return fs
end

-- Builder methods (the same names as Tip where they mean the same).
function DetailPane:Title(value, color)
    cell(self, Style.FONTS.label, value, 0, self.width, "LEFT", color)
    self.y = self.y + DetailPane.TITLE
    return self
end

function DetailPane:Line(value, color)
    cell(self, Style.FONTS.small, value, 0, self.width, "LEFT", color)
    self.y = self.y + DetailPane.LINE
    return self
end

function DetailPane:Pair(label, value, color)
    local right = self.width - DetailPane.LABEL
    cell(self, Style.FONTS.smallLabel, label, 0, DetailPane.LABEL, "LEFT", Style.GOLD)
    cell(self, Style.FONTS.small, value, DetailPane.LABEL, right, "RIGHT", color)
    self.y = self.y + DetailPane.LINE
    return self
end

function DetailPane:Gap()
    if self.y > 0 then
        self.y = self.y + DetailPane.GAP
    end
    return self
end

local function columns(self, font, values, colors, base)
    local n, space = DetailPane.NUMBER, DetailPane.SPACE
    local first = self.width - 2 * (n + space)
    cell(self, font, values[1], 0, first, "LEFT", colors[1] or base)
    cell(self, font, values[2] or "", first + space, n, "RIGHT", colors[2] or base)
    cell(self, font, values[3] or "", first + 2 * space + n, n, "RIGHT", colors[3] or base)
    self.y = self.y + DetailPane.LINE
    return self
end

-- A gold header row of a small table.
function DetailPane:Header(values)
    return columns(self, Style.FONTS.smallLabel, values, {}, Style.GOLD)
end

-- A table row; colors[i] per cell (white when nil).
function DetailPane:Row(values, colors)
    return columns(self, Style.FONTS.small, values, colors or {}, Style.WHITE)
end

-- Clears the pane and draws draw(builder) into it.
function DetailPane:Draw(draw)
    for _, pool in pairs(self.pools) do
        for _, fs in ipairs(pool.list) do
            fs:Hide()
        end
        pool.used = 0
    end
    self.y, self.cells = 0, {}
    draw(self)
end

-- The shown texts in order (for specs and the dev view).
function DetailPane:Texts()
    local out = {}
    for _, fs in ipairs(self.cells or {}) do
        if fs:IsShown() then
            out[#out + 1] = fs:GetText()
        end
    end
    return out
end
