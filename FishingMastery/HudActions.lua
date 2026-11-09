-- The two HUD buttons (owner request, Story 9.8): switch between the card and the compact line,
-- and stop the session now. Small template-free buttons at the top right of the card and at the
-- right end of the compact line: the layout button shows the arrow (up on the card: make it
-- compact; down on the line: open the card), the stop button a red square. Each has a tooltip.
-- The Settings preview has none. Unnamed, insecure frames only.
local _, ns = ...

local L, Style = ns.L, ns.Style

local HudActions = {}
ns.HudActions = HudActions

HudActions.SIZE, HudActions.GAP = 14, 4
HudActions.WIDTH = 2 * HudActions.SIZE + HudActions.GAP -- both buttons
HudActions.STOP = { 0.85, 0.15, 0.1 }

local function button(env, parent, title, text, onClick)
    local b = env.CreateFrame("Button", nil, parent)
    b:SetSize(HudActions.SIZE, HudActions.SIZE)
    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(b)
    back:SetColorTexture(0, 0, 0, 0.4)
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(b)
    highlight:SetColorTexture(Style.HOVER[1], Style.HOVER[2], Style.HOVER[3], 0.35)
    b:SetScript("OnClick", ns.Guard.Wrap("hud:button", onClick))
    b:SetScript("OnEnter", function(owner)
        ns.Tip.Open(env, owner, function(tip)
            tip:Title(owner.title or title)
            tip:Text(owner.text or text, Style.GREY)
        end)
    end)
    b:SetScript("OnLeave", function(owner)
        ns.Tip.Close(env, owner)
    end)
    return b
end

-- Adds both buttons to view (the card or the compact frame) at its top right (the line: right
-- end). actions: { layout(), stop() }. compact: the view is the compact line.
function HudActions.Attach(env, view, actions, compact)
    local set = {}
    set.stop = button(env, view, L.HACT_STOP, L.HACT_STOP_TEXT, actions.stop)
    local square = set.stop:CreateTexture(nil, "ARTWORK")
    square:SetSize(8, 8)
    square:SetPoint("CENTER", set.stop, "CENTER", 0, 0)
    square:SetColorTexture(HudActions.STOP[1], HudActions.STOP[2], HudActions.STOP[3], 1)
    local title = compact and L.HACT_CARD or L.HACT_COMPACT
    local text = compact and L.HACT_CARD_TEXT or L.HACT_COMPACT_TEXT
    set.layout = button(env, view, title, text, actions.layout)
    local arrow = set.layout:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(9, 8)
    arrow:SetPoint("CENTER", set.layout, "CENTER", 0, 0)
    arrow:SetTexture(Style.ARROW)
    local coords = compact and Style.ARROW_DOWN or Style.ARROW_UP
    arrow:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    if compact then
        set.stop:SetPoint("RIGHT", view, "RIGHT", -6, 0)
    else
        set.stop:SetPoint("TOPRIGHT", view, "TOPRIGHT", -6, -6)
    end
    set.layout:SetPoint("RIGHT", set.stop, "LEFT", -HudActions.GAP, 0)
    return set
end
