-- Small controls in the Forever look, shared by the pages of the main window (Epic 9): a
-- dropdown-styled button (an inset box with the value and a down arrow, as in Draft 2; a click
-- runs onClick, the pages cycle the value, no menu), the same look without the arrow for actions,
-- a framed box with a gold title (Draft 1), a small status bar, a check box, and a slider.
-- Unnamed, insecure frames only.
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

-- A framed panel (the inset look of the Professions window) with an optional gold title.
function Controls.Box(env, parent, title)
    local box = Frames.Create(env, "Frame", parent, Controls.BOX_TEMPLATE)
    ns.Look.Tint(box, ns.Look.WARM_PANEL)
    if title then
        box.title = box:CreateFontString(nil, "OVERLAY", Style.FONTS.label)
        box.title:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
        box.title:SetText(title)
    end
    return box
end

-- A button in the dropdown look without the arrow (actions next to dropdowns).
function Controls.Button(env, parent, width, onClick)
    local button = Controls.Dropdown(env, parent, width, onClick)
    button.arrow:Hide()
    return button
end

-- A small status bar with centered text (the Journal progress in the page header).
function Controls.Bar(env, parent, width, height)
    local bar = env.CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetStatusBarTexture(Style.BAR)
    bar:SetStatusBarColor(Style.SKILL[1], Style.SKILL[2], Style.SKILL[3])
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    tint(track, Style.TRACK)
    bar.text = bar:CreateFontString(nil, "OVERLAY", Style.FONTS.small)
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    return bar
end

-- A check box: the client's UICheckButtonTemplate, else the Classic check box textures. A click
-- calls onClick(checked).
Controls.CHECK_TEMPLATE = "UICheckButtonTemplate"
Controls.CHECK = {
    normal = "InterfaceButtonsUI-CheckBox-Up",
    pushed = "InterfaceButtonsUI-CheckBox-Down",
    highlight = "InterfaceButtonsUI-CheckBox-Highlight",
    checked = "InterfaceButtonsUI-CheckBox-Check",
}
function Controls.Check(env, parent, onClick)
    local box, template =
        Frames.CreateFirst(env, "CheckButton", parent, { Controls.CHECK_TEMPLATE })
    box:SetSize(24, 24)
    if not template then
        box:SetNormalTexture(Controls.CHECK.normal)
        box:SetPushedTexture(Controls.CHECK.pushed)
        box:SetHighlightTexture(Controls.CHECK.highlight)
        box:SetCheckedTexture(Controls.CHECK.checked)
    end
    box:SetScript(
        "OnClick",
        ns.Guard.Wrap("check:click", function(button)
            onClick(button:GetChecked() and true or false)
        end)
    )
    return box
end

-- A horizontal slider from Classic art (no template): a dark track and the slider thumb. Moving it
-- calls onChange(value); the value is on its step (SetObeyStepOnDrag).
Controls.THUMB = "InterfaceButtonsUI-SliderBar-Button-Horizontal"
function Controls.Slider(env, parent, width, low, high, step, onChange)
    local slider = env.CreateFrame("Slider", nil, parent)
    slider:SetSize(width, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouse(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, -5)
    track:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, 5)
    tint(track, Style.TRACK)
    slider:SetThumbTexture(Controls.THUMB)
    slider:SetScript(
        "OnValueChanged",
        ns.Guard.Wrap("slider:change", function(_, value)
            onChange(value)
        end)
    )
    return slider
end
