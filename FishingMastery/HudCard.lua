-- The HUD views of Draft 5 (Epic 9): the card in the tooltip look (TooltipBackdropTemplate,
-- confirmed in Story 9.1) and the compact line. The HUD (Story 9.8) and the Settings page preview
-- (Story 9.7) draw them. Draw takes a model (HudCardModel.Build):
-- { zone, risk = { text, kind = "safe" | "risk" | "unknown" }, bar = { value, max, text, mark },
--   riskLine = { left, right } or nil, lure = { icon, text, timer, grey, dim },
--   numbers = { { value, label, grey } x3 }, last = { icon, text, color, bite } or nil,
--   fish = { { id, icon, name, caught } } or nil, missing, compact }.
-- Rows stack from the top; the card is as tall as what it shows. Unnamed, insecure frames only.
local _, ns = ...

local ipairs = ipairs
local L, Style, Frames, Controls = ns.L, ns.Style, ns.Frames, ns.Controls

local HudCard = {}
ns.HudCard = HudCard

HudCard.TEMPLATE = "TooltipBackdropTemplate"
HudCard.WIDTH, HudCard.PAD = 260, 10
HudCard.COMPACT_HEIGHT = 24
HudCard.ICON, HudCard.FISH_ICONS = 16, 8
HudCard.TAG_GAP = 14 -- between the water name and the risk tag
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
    if not template then
        local back = f:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(f)
        back:SetColorTexture(HudCard.BACK[1], HudCard.BACK[2], HudCard.BACK[3], HudCard.BACK[4])
    end
    return f
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

-- One fish icon with its name in a tooltip.
local function fishIcon(card, f)
    local slot = card.env.CreateFrame("Frame", nil, f)
    slot:SetSize(HudCard.ICON, HudCard.ICON)
    slot.texture = icon(slot)
    slot.texture:SetAllPoints(slot)
    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(owner)
        local data = owner.data
        if data then
            ns.Tip.Open(card.env, owner, function(tip)
                tip:Title(data.name or "?")
                tip:Line(data.caught and L.HCARD_FISH_CAUGHT or L.HCARD_FISH_MISSING, Style.GREY)
            end)
        end
    end)
    slot:SetScript("OnLeave", function(owner)
        ns.Tip.Close(card.env, owner)
    end)
    return slot
end

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
    card.riskLeft = text(f, Style.FONTS.secondary)
    card.riskRight = text(f, Style.FONTS.secondary, "RIGHT")
    card.lureIcon, card.lureText = icon(f), text(f, Style.FONTS.small)
    card.lureTimer = text(f, Style.FONTS.small, "RIGHT")
    card.divider = f:CreateTexture(nil, "ARTWORK")
    card.divider:SetSize(HudCard.WIDTH - 2 * HudCard.PAD, 1)
    card.divider:SetColorTexture(1, 1, 1, 0.12)
    card.numbers = {}
    for i = 1, 3 do
        card.numbers[i] = {
            value = text(f, Style.FONTS.number, "CENTER"),
            label = text(f, Style.FONTS.smallLabel, "CENTER"),
        }
    end
    card.lastIcon, card.lastText = icon(f), text(f, Style.FONTS.small)
    card.lastBite = text(f, Style.FONTS.secondary, "RIGHT")
    card.fishSlots = {}
    for i = 1, HudCard.FISH_ICONS do
        card.fishSlots[i] = fishIcon(card, f)
    end
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

local function color(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
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
    place(card.divider, card, "TOPLEFT", pad, y)
    local column = (HudCard.WIDTH - 2 * pad) / 3
    for i, number in ipairs(numbers) do
        local cells = card.numbers[i]
        local x = pad + (i - 0.5) * column - HudCard.WIDTH / 2
        place(cells.value, card, "TOP", x, y - 6)
        place(cells.label, card, "TOP", x, y - 28)
        cells.value:SetText(number.value)
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

local function drawFish(card, fish, missing, y)
    local pad = HudCard.PAD
    for i, slot in ipairs(card.fishSlots) do
        local data = fish and fish[i]
        slot:SetShown(data ~= nil)
        slot.data = data
        if data then
            place(slot, card, "TOPLEFT", pad + (i - 1) * (HudCard.ICON + 4), y - 2)
            slot.texture:SetTexture(data.icon)
            local light = data.caught and 1 or HudCard.DARK
            slot.texture:SetVertexColor(light, light, light)
        end
    end
    card.missing:SetShown(fish ~= nil)
    if not fish then
        return y
    end
    place(card.missing, card, "TOPRIGHT", -pad, y - 4)
    card.missing:SetText(missing or "")
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
    y = drawLast(card, model.last, y)
    y = drawFish(card, model.fish, model.missing, y)
    card.card:SetHeight(-y + HudCard.PAD - 4)
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
        lure = { text = L.HCARD_NO_LURE_NEEDED, grey = true },
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
