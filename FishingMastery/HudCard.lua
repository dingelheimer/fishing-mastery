-- The HUD views of Draft 5 (Epic 9): the card in the tooltip look (TooltipBackdropTemplate,
-- confirmed in Story 9.1) and the compact line. The HUD (Story 9.8) and the Settings page preview
-- (Story 9.7) draw them. Draw takes a model (HudCardModel.Build):
-- { zone, risk = { text, kind = "safe" | "risk" | "unknown" }, bar = { value, max, text, mark,
--   safe }, riskLine = { left, right } or nil, lure = { icon, text, timer, grey, dim },
--   numbers = { { value, unit, label, grey } x3 }, session = { time, value, grey } (Story 10.6),
--   last = { icon, text, color, bite } or nil,
--   fish = { { id, icon, name, caught } } or nil, missing, compact }.
-- Rows stack from the top with thin dividers around the numbers (Story 10.2); the card is as tall
-- as what it shows. Unnamed, insecure frames only.
local _, ns = ...

local ipairs = ipairs
local Style, Frames, Controls = ns.Style, ns.Frames, ns.Controls

local HudCard = {}
ns.HudCard = HudCard

HudCard.TEMPLATE = "TooltipBackdropTemplate"
HudCard.WIDTH, HudCard.PAD = 260, 10
HudCard.COMPACT_HEIGHT = 24
HudCard.ICON, HudCard.FISH_ICONS = 16, 8
HudCard.TAG_GAP = 14 -- between the water name and the risk tag
HudCard.UNIT_GAP = 3 -- between a number and its small unit
HudCard.SESSION_ROW = 22 -- the session time and value row under the numbers
HudCard.DARK = 0.3 -- brightness of a fish icon not caught here yet
HudCard.BACK = { 0.03, 0.03, 0.06, 0.92 } -- without the template
HudCard.RISK = {
    safe = { Style.GREEN, { 0.12, 1, 0, 0.15 } },
    risk = { Style.ORANGE, { 1, 0.5, 0, 0.18 } },
    unknown = { Style.GREY, { 1, 1, 1, 0.08 } },
}

local function frame(env, parent, height)
    local f, template = Frames.CreateFirst(env, "Frame", parent, { HudCard.TEMPLATE })
    f:SetSize(HudCard.WIDTH, height)
    ns.Look.Backing(f) -- the solid background setting (Story 10.4)
    if not template then
        local back = f:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(f)
        back:SetColorTexture(HudCard.BACK[1], HudCard.BACK[2], HudCard.BACK[3], HudCard.BACK[4])
    end
    return f
end

local function color(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

local function text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Places region at x, y from the same point of the card (TOPLEFT, TOP, TOPRIGHT).
local function place(region, card, point, x, y)
    region:ClearAllPoints()
    region:SetPoint(point, card.card, point, x, y)
end

local function icon(parent)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(HudCard.ICON, HudCard.ICON)
    return tex
end
HudCard.Place, HudCard.Icon = place, icon -- shared with the fish row (HudCardFish.lua)

-- Creates both views on parent; only one is shown at a time. actions ({ layout(), stop() }, the
-- HUD only) adds the two buttons (HudActions.lua) to both views.
function HudCard.Create(env, parent, actions)
    local card = { env = env, right = 0 }
    local f = frame(env, parent, 120)
    card.card = f
    card.zone = text(f, Style.FONTS.label)
    card.tag = text(f, Style.FONTS.smallLabel, "RIGHT")
    card.tagBack = f:CreateTexture(nil, "BORDER")
    card.tagBack:SetPoint("TOPLEFT", card.tag, "TOPLEFT", -4, 2)
    card.tagBack:SetPoint("BOTTOMRIGHT", card.tag, "BOTTOMRIGHT", 4, -2)
    card.bar = Controls.Bar(env, f, HudCard.WIDTH - 2 * HudCard.PAD, 14)
    card.mark = card.bar:CreateTexture(nil, "OVERLAY")
    card.mark:SetSize(2, 18)
    card.mark:SetColorTexture(1, 1, 1, 1)
    card.safe = card.bar:CreateTexture(nil, "OVERLAY") -- where getaways stop (green)
    card.safe:SetSize(2, 18)
    card.safe:SetColorTexture(Style.GREEN[1], Style.GREEN[2], Style.GREEN[3], 1)
    card.riskLeft = text(f, Style.FONTS.secondary)
    card.riskRight = text(f, Style.FONTS.secondary, "RIGHT")
    card.lureIcon, card.lureText = icon(f), text(f, Style.FONTS.small)
    card.lureTimer = text(f, Style.FONTS.small, "RIGHT")
    card.dividers = {}
    for i = 1, 2 do
        local line = f:CreateTexture(nil, "ARTWORK")
        line:SetSize(HudCard.WIDTH - 2 * HudCard.PAD, 1)
        line:SetColorTexture(1, 1, 1, 0.12)
        card.dividers[i] = line
    end
    card.numbers = {}
    for i = 1, 3 do
        local unit = text(f, Style.FONTS.secondary)
        color(unit, Style.GREY)
        card.numbers[i] = {
            value = text(f, Style.FONTS.number, "CENTER"),
            unit = unit,
            label = text(f, Style.FONTS.smallLabel, "CENTER"),
        }
    end
    card.sessionTime = text(f, Style.FONTS.small)
    card.sessionValue = text(f, Style.FONTS.small, "RIGHT")
    card.lastIcon, card.lastText = icon(f), text(f, Style.FONTS.small)
    card.lastBite = text(f, Style.FONTS.secondary, "RIGHT")
    ns.HudCardFish.Create(card, f)
    card.missing = text(f, Style.FONTS.secondary, "RIGHT")
    local line = frame(env, parent, HudCard.COMPACT_HEIGHT)
    card.compact = line
    card.line = text(line, Style.FONTS.small)
    card.line:SetPoint("LEFT", line, "LEFT", 10, 0)
    if actions then
        card.cardButtons = ns.HudActions.Attach(env, f, actions, false)
        card.lineButtons = ns.HudActions.Attach(env, line, actions, true)
        card.right = ns.HudActions.WIDTH + 6 -- room the buttons take at the right
    end
    return card
end

local function drawTop(card, model)
    local pad = HudCard.PAD
    place(card.zone, card, "TOPLEFT", pad, -pad)
    card.zone:SetText(model.zone)
    local risk = HudCard.RISK[model.risk.kind] or HudCard.RISK.unknown
    place(card.tag, card, "TOPRIGHT", -pad - 2 - card.right, -pad - 1)
    card.tag:SetText(model.risk.text)
    color(card.tag, risk[1])
    card.tagBack:SetColorTexture(risk[2][1], risk[2][2], risk[2][3], risk[2][4])
    card.tagBack:SetShown(model.risk.text ~= "")
    -- A long water name ends in "..." before the tag.
    local tag = model.risk.text ~= "" and card.tag:GetStringWidth() + HudCard.TAG_GAP or 0
    card.zone:SetWidth(HudCard.WIDTH - 2 * pad - tag - card.right)
    local bar = model.bar
    place(card.bar, card, "TOPLEFT", pad, -30)
    card.bar:SetMinMaxValues(0, bar.max)
    card.bar:SetValue(bar.value)
    card.bar.text:SetText(bar.text)
    card.mark:SetShown(bar.mark ~= nil)
    if bar.mark then
        card.mark:ClearAllPoints()
        card.mark:SetPoint("CENTER", card.bar, "LEFT", bar.mark * (HudCard.WIDTH - 2 * pad), 0)
    end
    card.safe:SetShown(bar.safe ~= nil)
    if bar.safe then
        card.safe:ClearAllPoints()
        card.safe:SetPoint("CENTER", card.bar, "LEFT", bar.safe * (HudCard.WIDTH - 2 * pad) - 1, 0)
    end
    local y = -48
    local risky = model.riskLine
    card.riskLeft:SetShown(risky ~= nil)
    card.riskRight:SetShown(risky ~= nil)
    if risky then
        place(card.riskLeft, card, "TOPLEFT", pad, y)
        place(card.riskRight, card, "TOPRIGHT", -pad, y)
        card.riskLeft:SetText(risky.left)
        card.riskRight:SetText(risky.right)
        y = y - 14
    end
    return y
end

local function drawLure(card, lure, y)
    local pad = HudCard.PAD
    card.lureIcon:SetShown(lure.icon ~= nil)
    place(card.lureIcon, card, "TOPLEFT", pad, y - 2)
    card.lureIcon:SetTexture(lure.icon)
    local dim = lure.dim and HudCard.DARK + 0.3 or 1
    card.lureIcon:SetVertexColor(dim, dim, dim)
    place(card.lureText, card, "TOPLEFT", pad + (lure.icon and HudCard.ICON + 6 or 0), y - 4)
    card.lureText:SetText(lure.text)
    color(card.lureText, lure.grey and Style.GREY or Style.WHITE)
    place(card.lureTimer, card, "TOPRIGHT", -pad, y - 4)
    card.lureTimer:SetText(lure.timer or "")
    return y - 22
end

local function drawNumbers(card, numbers, y)
    local pad = HudCard.PAD
    place(card.dividers[1], card, "TOPLEFT", pad, y)
    local column = (HudCard.WIDTH - 2 * pad) / 3
    for i, number in ipairs(numbers) do
        local cells = card.numbers[i]
        local x = pad + (i - 0.5) * column - HudCard.WIDTH / 2
        cells.value:SetText(number.value)
        cells.unit:SetText(number.unit or "")
        -- The number and its unit are centered as one group.
        local width = cells.value:GetStringWidth()
        local unit = number.unit and cells.unit:GetStringWidth() + HudCard.UNIT_GAP or 0
        place(cells.value, card, "TOP", x - unit / 2, y - 6)
        cells.unit:ClearAllPoints()
        cells.unit:SetPoint("BOTTOMLEFT", cells.value, "BOTTOM", width / 2 + HudCard.UNIT_GAP, 2)
        place(cells.label, card, "TOP", x, y - 28)
        color(cells.value, number.grey and Style.GREY or Style.WHITE)
        cells.label:SetText(number.label)
    end
    return y - 44
end

local function drawLast(card, last, y)
    local pad = HudCard.PAD
    local shown = last ~= nil
    card.lastIcon:SetShown(shown and last.icon ~= nil)
    card.lastText:SetShown(shown)
    card.lastBite:SetShown(shown)
    if not shown then
        return y
    end
    place(card.lastIcon, card, "TOPLEFT", pad, y - 2)
    card.lastIcon:SetTexture(last.icon)
    place(card.lastText, card, "TOPLEFT", pad + HudCard.ICON + 6, y - 4)
    card.lastText:SetText(last.text)
    color(card.lastText, last.color)
    place(card.lastBite, card, "TOPRIGHT", -pad, y - 4)
    card.lastBite:SetText(last.bite)
    return y - 22
end

-- Shows the card or the compact line (layout) drawn from model.
function HudCard.Draw(card, model, layout)
    local compact = layout == "compact"
    card.card:SetShown(not compact)
    card.compact:SetShown(compact)
    if compact then
        card.line:SetText(model.compact)
        card.compact:SetWidth(card.line:GetStringWidth() + 20 + card.right)
        return
    end
    local y = drawTop(card, model)
    y = drawLure(card, model.lure or { text = "" }, y)
    y = drawNumbers(card, model.numbers, y)
    -- The session row: the time since the first cast and the catch's vendor value (Story 10.6).
    local row = model.session or { time = "", value = "" }
    place(card.dividers[2], card, "TOPLEFT", HudCard.PAD, y + 2)
    place(card.sessionTime, card, "TOPLEFT", HudCard.PAD, y - 4)
    place(card.sessionValue, card, "TOPRIGHT", -HudCard.PAD, y - 4)
    card.sessionTime:SetText(row.time)
    card.sessionValue:SetText(row.value)
    color(card.sessionValue, row.grey and Style.GREY or Style.WHITE)
    y = y - HudCard.SESSION_ROW
    y = drawLast(card, model.last, y)
    y = ns.HudCardFish.Draw(card, model.fish, model.missing, y)
    card.card:SetHeight(-y + HudCard.PAD - 4)
end

-- The frame of the shown view (for scale, opacity, and placement).
function HudCard.Shown(card, layout)
    return layout == "compact" and card.compact or card.card
end
