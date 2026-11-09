-- The HUD views of Draft 5 (Epic 9): the card (water name with a risk tag, the skill bar, three
-- headline numbers) in the tooltip look (TooltipBackdropTemplate, confirmed in Story 9.1) and the
-- compact line. Story 9.7 draws them as the Settings page preview from a sample model; Story 9.8
-- extends the card for the HUD itself. Draw takes a model:
-- { zone, risk = { text, kind = "safe" | "risk" | "unknown" }, bar = { value, max, text },
--   numbers = { { value, label, grey } x3 }, compact (one line with color escapes) }.
-- Unnamed, insecure frames only.
local _, ns = ...

local ipairs = ipairs
local L, Style, Frames, Controls = ns.L, ns.Style, ns.Frames, ns.Controls

local HudCard = {}
ns.HudCard = HudCard

HudCard.TEMPLATE = "TooltipBackdropTemplate"
HudCard.WIDTH, HudCard.HEIGHT = 260, 104
HudCard.COMPACT_HEIGHT = 24
HudCard.BACK = { 0.03, 0.03, 0.06, 0.92 } -- without the template
HudCard.RISK = {
    safe = { Style.GREEN, { 0.12, 1, 0, 0.15 } },
    risk = { Style.ORANGE, { 1, 0.5, 0, 0.18 } },
    unknown = { Style.GREY, { 1, 1, 1, 0.08 } },
}

local function frame(env, parent, width, height)
    local f, template = Frames.CreateFirst(env, "Frame", parent, { HudCard.TEMPLATE })
    f:SetSize(width, height)
    if not template then
        local back = f:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(f)
        back:SetColorTexture(HudCard.BACK[1], HudCard.BACK[2], HudCard.BACK[3], HudCard.BACK[4])
    end
    return f
end

local function text(parent, font, point, x, y, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint(point, parent, point, x, y)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Creates both views on parent; only one is shown at a time.
function HudCard.Create(env, parent)
    local card = { env = env }
    local f = frame(env, parent, HudCard.WIDTH, HudCard.HEIGHT)
    card.card = f
    card.zone = text(f, Style.FONTS.label, "TOPLEFT", 10, -10)
    card.tag = text(f, Style.FONTS.smallLabel, "TOPRIGHT", -12, -11, "RIGHT")
    card.tagBack = f:CreateTexture(nil, "BORDER")
    card.tagBack:SetPoint("TOPLEFT", card.tag, "TOPLEFT", -4, 2)
    card.tagBack:SetPoint("BOTTOMRIGHT", card.tag, "BOTTOMRIGHT", 4, -2)
    card.bar = Controls.Bar(env, f, HudCard.WIDTH - 20, 14)
    card.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
    card.numbers = {}
    local column = (HudCard.WIDTH - 20) / 3
    for i = 1, 3 do
        local x = 10 + (i - 0.5) * column - HudCard.WIDTH / 2
        local value = text(f, Style.FONTS.number, "TOP", x, -54, "CENTER")
        local label = text(f, Style.FONTS.smallLabel, "TOP", x, -78, "CENTER")
        card.numbers[i] = { value = value, label = label }
    end
    local line = frame(env, parent, HudCard.WIDTH, HudCard.COMPACT_HEIGHT)
    card.compact = line
    card.line = text(line, Style.FONTS.small, "LEFT", 10, 0)
    return card
end

-- Shows the card or the compact line (layout) drawn from model.
function HudCard.Draw(card, model, layout)
    local compact = layout == "compact"
    card.card:SetShown(not compact)
    card.compact:SetShown(compact)
    if compact then
        card.line:SetText(model.compact)
        card.compact:SetWidth(card.line:GetStringWidth() + 20)
        return
    end
    card.zone:SetText(model.zone)
    local risk = HudCard.RISK[model.risk.kind] or HudCard.RISK.unknown
    card.tag:SetText(model.risk.text)
    card.tag:SetTextColor(risk[1][1], risk[1][2], risk[1][3])
    card.tagBack:SetColorTexture(risk[2][1], risk[2][2], risk[2][3], risk[2][4])
    local bar = model.bar
    card.bar:SetMinMaxValues(0, bar.max)
    card.bar:SetValue(bar.value)
    card.bar.text:SetText(bar.text)
    for i, number in ipairs(model.numbers) do
        local cells = card.numbers[i]
        local color = number.grey and Style.GREY or Style.WHITE
        cells.value:SetText(number.value)
        cells.value:SetTextColor(color[1], color[2], color[3])
        cells.label:SetText(number.label)
    end
end

-- The frame of the shown view (for scale, opacity, and placement).
function HudCard.Shown(card, layout)
    return layout == "compact" and card.compact or card.card
end

-- The sample of Draft 5 (safe water) for the Settings page preview.
function HudCard.Sample()
    local gold, green, grey = Style.Hex(Style.GOLD), Style.Hex(Style.GREEN), Style.Hex(Style.GREY)
    return {
        zone = L.PREVIEW_ZONE,
        risk = { text = L.PREVIEW_SAFE, kind = "safe" },
        bar = { value = 154, max = 225, text = L.PREVIEW_BAR },
        numbers = {
            { value = "8", label = L.PREVIEW_CATCHES },
            { value = "8/9", label = L.PREVIEW_SUCCESS, grey = true },
            { value = "-", label = L.PREVIEW_PER_HOUR, grey = true },
        },
        compact = "|c"
            .. gold
            .. L.PREVIEW_ZONE
            .. "|r  |c"
            .. green
            .. L.PREVIEW_SAFE
            .. "|r  "
            .. L.PREVIEW_COMPACT_CATCHES
            .. "  |c"
            .. grey
            .. "8/9|r  "
            .. L.PREVIEW_COMPACT_SKILL,
    }
end
