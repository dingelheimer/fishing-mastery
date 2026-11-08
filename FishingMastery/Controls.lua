-- Small controls in the Forever look, shared by the pages of the main window (Epic 9): a
-- dropdown-styled button (an inset box with the value and a down arrow, as in Draft 2). A click
-- runs onClick (the pages cycle the value; no menu). Unnamed, insecure frames only.
local _, ns = ...

local Frames, Style = ns.Frames, ns.Style

local Controls = {}
ns.Controls = Controls

Controls.BOX_TEMPLATE = "InsetFrameTemplate" -- confirmed in game, Story 9.1
Controls.HEIGHT = 22
Controls.BACK = { 0, 0, 0, 0.35 }

local function tint(texture, color)
    texture:SetColorTexture(color[1], color[2], color[3], color[4])
end

-- A button that looks like a dropdown; SetText sets the shown value.
function Controls.Dropdown(env, parent, width, onClick)
    local button = Frames.Create(env, "Button", parent, Controls.BOX_TEMPLATE)
    button:SetSize(width, Controls.HEIGHT)
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(button)
    tint(back, Controls.BACK)
    local label = button:CreateFontString(nil, "OVERLAY", Style.FONTS.small)
    label:SetPoint("LEFT", button, "LEFT", 8, 0)
    label:SetWidth(width - 26)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    button:SetFontString(label)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(9, 8)
    arrow:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    arrow:SetTexture(Style.ARROW)
    local down = Style.ARROW_DOWN
    arrow:SetTexCoord(down[1], down[2], down[3], down[4])
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    tint(highlight, Style.HOVER)
    button.arrow = arrow
    button:SetScript("OnClick", ns.Guard.Wrap("dropdown:click", onClick))
    return button
end
