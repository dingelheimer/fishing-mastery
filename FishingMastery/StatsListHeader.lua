-- The header of a StatsList table (Epic 9, Draft 2): a gold bar with the column labels, as
-- template-free sort buttons with a hover tint and the sort arrow (flipped for ascending) when
-- the list sorts, else as plain labels. Unnamed, insecure frames only.
local _, ns = ...

local ipairs = ipairs
local Style = ns.Style

local Header = {}
ns.StatsListHeader = Header

Header.HEIGHT = 20
Header.ARROW, Header.ARROW_DOWN, Header.ARROW_UP = Style.ARROW, Style.ARROW_DOWN, Style.ARROW_UP

local function tint(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
end
Header.Tint = tint

local function sortButton(list, parent, column)
    local key = column.key
    local button = list.env.CreateFrame("Button", nil, parent)
    button:SetSize(column.width - 2, Header.HEIGHT)
    local label = button:CreateFontString(nil, "OVERLAY", Style.FONTS.smallLabel)
    label:SetPoint("LEFT", button, "LEFT", 3, 0)
    label:SetWidth(column.width - (column.right and 18 or 8))
    label:SetJustifyH(column.right and "RIGHT" or "LEFT")
    button:SetFontString(label)
    button:SetText(column.label)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    tint(highlight, Style.HOVER)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(9, 8)
    arrow:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    arrow:SetTexture(Header.ARROW)
    arrow:Hide()
    button.arrow, button.key = arrow, key
    button:SetScript(
        "OnClick",
        ns.Guard.Wrap("list:sort", function()
            list.onSort(key)
        end)
    )
    return button
end

-- Builds the bar and one cell per column of list.columns on parent; sets list.headers.
function Header.Build(list, parent)
    local bar = parent:CreateTexture(nil, "BACKGROUND")
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, -Header.HEIGHT)
    tint(bar, Style.HEADER)
    local x = 0
    list.headers = {}
    for _, column in ipairs(list.columns) do
        local cell
        if list.onSort then
            cell = sortButton(list, parent, column)
        else
            cell = parent:CreateFontString(nil, "OVERLAY", Style.FONTS.smallLabel)
            cell:SetWidth(column.width - 6)
            cell:SetJustifyH(column.right and "RIGHT" or "LEFT")
            cell:SetText(column.label)
        end
        cell:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (list.onSort and 0 or 3), -3)
        list.headers[#list.headers + 1] = cell
        x = x + column.width
    end
end

-- Puts the arrow on the sorted column (sort = { key, descending }) of a sorting list.
function Header.DrawSort(list, sort)
    if not list.onSort then
        return
    end
    for _, button in ipairs(list.headers) do
        local sorted = sort ~= nil and button.key == sort.key
        button.arrow:SetShown(sorted)
        if sorted then
            local coords = sort.descending and Header.ARROW_DOWN or Header.ARROW_UP
            button.arrow:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
    end
end
