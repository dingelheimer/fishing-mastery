-- Frames of the Statistics Overview (Draft 1, Story 9.3): the Fishing panel with the skill bar, the
-- four headline numbers, where casts end, and the most caught items. Build creates the frames
-- once on the Overview panel; Draw fills them from an OverviewModel result. Unnamed, insecure
-- frames only.
local _, ns = ...

local ipairs, type = ipairs, type
local L, Style, Controls = ns.L, ns.Style, ns.Controls

local OverviewPage = {}
ns.OverviewPage = OverviewPage

OverviewPage.ICON = "Interface\\Icons\\Trade_Fishing"
OverviewPage.SKILL_HEIGHT, OverviewPage.NUMBERS_HEIGHT, OverviewPage.GAP = 70, 78, 6
OverviewPage.BAR_X, OverviewPage.BAR_HEIGHT = 240, 18
OverviewPage.ROW_TOP, OverviewPage.ROW = -32, 22
OverviewPage.OUT_BAR, OverviewPage.TOP_BAR = 120, 80 -- bar lengths in the two lower panels

local function text(parent, font, point, x, y, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint(point, parent, point, x, y)
    if width then
        fs:SetWidth(width)
        fs:SetWordWrap(false)
    end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function color(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

local function tint(texture, c)
    texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

local function skillPanel(page, env, panel, width)
    local box = Controls.Box(env, panel, L.OV_FISHING)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    box:SetSize(width, OverviewPage.SKILL_HEIGHT)
    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(30, 30)
    icon:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -30)
    icon:SetTexture(OverviewPage.ICON)
    local name = text(box, Style.FONTS.label, "TOPLEFT", 46, -32)
    name:SetText(L.OV_FISHING)
    page.rankName = text(box, Style.FONTS.small, "TOPLEFT", 46, -48)
    local barWidth = width - OverviewPage.BAR_X - 12
    local bar = env.CreateFrame("StatusBar", nil, box)
    bar:SetSize(barWidth, OverviewPage.BAR_HEIGHT)
    bar:SetPoint("TOPLEFT", box, "TOPLEFT", OverviewPage.BAR_X, -28)
    bar:SetStatusBarTexture(Style.BAR)
    bar:SetStatusBarColor(Style.SKILL[1], Style.SKILL[2], Style.SKILL[3])
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    tint(track, Style.TRACK)
    bar.text = text(bar, Style.FONTS.small, "CENTER", 0, 0, nil, "CENTER")
    bar.mark = bar:CreateTexture(nil, "OVERLAY")
    bar.mark:SetSize(2, OverviewPage.BAR_HEIGHT + 6)
    tint(bar.mark, Style.WHITE)
    bar.width = barWidth
    page.skillBar = bar
    page.skillMod =
        text(box, Style.FONTS.secondary, "TOPLEFT", OverviewPage.BAR_X, -50, barWidth / 2)
    page.skillGained = text(box, Style.FONTS.small, "TOPRIGHT", -12, -50, barWidth / 2, "RIGHT")
    color(page.skillGained, Style.GREEN)
    page.skillNone = text(box, Style.FONTS.secondary, "TOPLEFT", OverviewPage.BAR_X, -30)
    page.skillNone:SetText(L.OV_SKILL_NONE)
end

local function numbersPanel(page, env, panel, width)
    local top = OverviewPage.SKILL_HEIGHT + OverviewPage.GAP
    local box = Controls.Box(env, panel)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -top)
    box:SetSize(width, OverviewPage.NUMBERS_HEIGHT)
    local column = width / 4
    page.numbers = {}
    for i = 1, 4 do
        local cell = env.CreateFrame("Frame", nil, box)
        cell:SetPoint("TOPLEFT", box, "TOPLEFT", (i - 1) * column, 0)
        cell:SetSize(column, OverviewPage.NUMBERS_HEIGHT)
        cell.value = text(cell, Style.FONTS.big, "TOP", 0, -10, nil, "CENTER")
        cell.unit = cell:CreateFontString(nil, "OVERLAY", Style.FONTS.secondary)
        cell.unit:SetPoint("BOTTOMLEFT", cell.value, "BOTTOMRIGHT", 4, 2)
        cell.label = text(cell, Style.FONTS.label, "TOP", 0, -42, column - 8, "CENTER")
        cell.sub = text(cell, Style.FONTS.secondary, "TOP", 0, -57, column - 8, "CENTER")
        page.numbers[i] = cell
    end
    -- The Catches number lists the characters in its tooltip (all characters).
    local catches = page.numbers[1]
    catches:EnableMouse(true)
    catches:SetScript("OnEnter", function(cell)
        local lines = page.characters
        if not lines then
            return
        end
        ns.Tip.Open(env, cell, function(tip)
            tip:Title(L.OV_CHARACTERS, Style.GOLD)
            for _, line in ipairs(lines) do
                tip:Pair(line.label, line.value)
            end
        end, "ANCHOR_BOTTOM")
    end)
    catches:SetScript("OnLeave", function(cell)
        ns.Tip.Close(env, cell)
    end)
end

-- One row of a lower panel: a stripe on even rows, then the cells the caller adds.
local function row(box, index)
    local frame = box:CreateTexture(nil, "BACKGROUND")
    local y = OverviewPage.ROW_TOP - (index - 1) * OverviewPage.ROW
    frame:SetPoint("TOPLEFT", box, "TOPLEFT", 6, y + 2)
    frame:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", -6, y + 2 - OverviewPage.ROW)
    tint(frame, Style.STRIPE)
    frame:SetShown(index % 2 == 0)
    return y
end

local function barTexture(box, x, y)
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", x, y - 5)
    return fill
end

local function outcomePanel(page, env, panel, x, top, width, height)
    local box = Controls.Box(env, panel, L.OV_WHERE)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -top)
    box:SetSize(width, height)
    page.outcomeRows = {}
    for i = 1, #ns.OverviewModel.OUTCOMES do
        local y = row(box, i)
        page.outcomeRows[i] = {
            label = text(box, Style.FONTS.small, "TOPLEFT", 12, y - 3, 150),
            count = text(box, Style.FONTS.small, "TOPLEFT", 162, y - 3, 60, "RIGHT"),
            bar = barTexture(box, 234, y),
            share = text(box, Style.FONTS.small, "TOPRIGHT", -12, y - 3, 50, "RIGHT"),
        }
    end
    local legend = text(box, Style.FONTS.secondary, "BOTTOMLEFT", 12, 8, width - 24)
    legend:SetText(L.OV_GREY_ROWS)
end

local function topPanel(page, env, panel, x, top, width, height)
    local box = Controls.Box(env, panel, L.OV_MOST)
    box:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -top)
    box:SetSize(width, height)
    page.topRows = {}
    for i = 1, ns.OverviewModel.TOP do
        local y = row(box, i)
        local icon = box:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y - 1)
        page.topRows[i] = {
            icon = icon,
            name = text(box, Style.FONTS.small, "TOPLEFT", 34, y - 3, 200),
            count = text(box, Style.FONTS.small, "TOPLEFT", 236, y - 3, 50, "RIGHT"),
            bar = barTexture(box, 296, y),
        }
    end
    page.topEmpty = text(box, Style.FONTS.secondary, "TOPLEFT", 12, OverviewPage.ROW_TOP - 3)
    page.topEmpty:SetText(L.OV_NONE_CAUGHT)
    local hint = text(box, Style.FONTS.secondary, "BOTTOMLEFT", 12, 8, width - 24)
    hint:SetText(L.OV_ALL_FISH)
end

-- Creates the Overview frames on panel (width x height pixels); page holds them.
function OverviewPage.Build(page, env, panel, width, height)
    page.env = env
    skillPanel(page, env, panel, width)
    numbersPanel(page, env, panel, width)
    local top = OverviewPage.SKILL_HEIGHT + OverviewPage.NUMBERS_HEIGHT + 2 * OverviewPage.GAP
    local half = (width - OverviewPage.GAP) / 2
    outcomePanel(page, env, panel, 0, top, half, height - top)
    topPanel(page, env, panel, half + OverviewPage.GAP, top, half, height - top)
end

local function drawSkill(page, skill)
    local bar = page.skillBar
    bar:SetShown(skill ~= nil)
    page.skillNone:SetShown(skill == nil)
    page.rankName:SetText(skill and skill.rankName or "")
    page.skillMod:SetText(skill and skill.modifier or "")
    page.skillGained:SetText(skill and skill.gained or "")
    if not skill then
        return
    end
    bar:SetMinMaxValues(0, skill.max)
    bar:SetValue(skill.rank)
    bar.text:SetText(skill.bar)
    local at = skill.effective > skill.max and skill.max or skill.effective
    bar.mark:ClearAllPoints()
    bar.mark:SetPoint("CENTER", bar, "LEFT", bar.width * at / skill.max, 0)
    bar.mark:SetShown(skill.effective ~= skill.rank)
end

local function drawNumbers(page, numbers)
    for i, number in ipairs(numbers) do
        local cell = page.numbers[i]
        cell.value:SetText(number.value)
        color(cell.value, number.grey and Style.GREY or Style.WHITE)
        cell.unit:SetText(number.unit or "")
        cell.label:SetText(number.label)
        cell.sub:SetText(number.sub or "")
    end
end

local function drawBar(page, fill, share, length, c)
    local width = type(share) == "number" and share * length or 0
    fill:SetShown(width >= 1)
    if width >= 1 then
        fill:SetSize(width, 10)
        ns.BarFill.Paint(page.env, fill, c)
    end
end

local function drawOutcomes(page, rows)
    for i, data in ipairs(rows) do
        local cells = page.outcomeRows[i]
        local c = data.grey and Style.GREY or Style.WHITE
        cells.label:SetText(data.label)
        cells.count:SetText(data.count)
        cells.share:SetText(data.text)
        color(cells.label, c)
        color(cells.count, c)
        color(cells.share, c)
        drawBar(page, cells.bar, data.share, OverviewPage.OUT_BAR, data.color or Style.BAR_GREY)
    end
end

local function drawTop(page, rows)
    for i, cells in ipairs(page.topRows) do
        local data = rows[i]
        cells.icon:SetShown(data ~= nil and data.icon ~= nil)
        cells.name:SetShown(data ~= nil)
        cells.count:SetShown(data ~= nil)
        if data then
            cells.icon:SetTexture(data.icon)
            cells.name:SetText(data.hex and ("|c" .. data.hex .. data.name .. "|r") or data.name)
            cells.count:SetText(data.n)
        end
        drawBar(page, cells.bar, data and data.fill, OverviewPage.TOP_BAR, Style.BAR_GOLD)
    end
    page.topEmpty:SetShown(#rows == 0)
end

-- Fills the frames from an OverviewModel result.
function OverviewPage.Draw(page, model)
    drawSkill(page, model.skill)
    drawNumbers(page, model.numbers)
    drawOutcomes(page, model.outcomes)
    drawTop(page, model.top)
    page.characters = model.characters
end
