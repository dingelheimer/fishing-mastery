-- Stubs for the Blizzard templates the UI overhaul chose (Story 9.1, owner check 2026-11-08:
-- PortraitFrameTemplate, ButtonFrameTemplate, InsetFrameTemplate, LargeSideTabButtonTemplate,
-- TooltipBackdropTemplate, PanelTabButtonTemplate exist; SpellBookSkillLineTabTemplate does
-- not) and for the StatusBar frame type. Child keys follow the Mainline UI code the Forever
-- client runs; Story 9.2 confirms them with /fstack and fixes this file if they differ.
local M = {}

-- Adds a child region or frame the way a template's parentKey does.
local function texture(frame, key)
    frame[key] = frame:CreateTexture(nil, "ARTWORK")
    return frame[key]
end

local function nineSlice(env, frame)
    local slice = env.CreateFrame("Frame", nil, frame)
    function slice.SetCenterColor(s, r, g, b, a)
        s.center = { r, g, b, a }
    end
    function slice.SetBorderColor(s, r, g, b, a)
        s.border = { r, g, b, a }
    end
    frame.NineSlice = slice
end

local function portrait(env, frame)
    nineSlice(env, frame)
    texture(frame, "Bg")
    frame.PortraitContainer = env.CreateFrame("Frame", nil, frame)
    texture(frame.PortraitContainer, "portrait")
    frame.TitleContainer = env.CreateFrame("Frame", nil, frame)
    frame.TitleContainer.TitleText = frame.TitleContainer:CreateFontString(nil, "OVERLAY")
    frame.CloseButton = env.CreateFrame("Button", nil, frame)
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    function frame.SetTitle(f, title)
        f.TitleContainer.TitleText:SetText(title)
    end
    function frame.SetPortraitToAsset(f, asset)
        f.PortraitContainer.portrait:SetTexture(asset)
    end
end

local BUILD = {
    PortraitFrameTemplate = portrait,
    ButtonFrameTemplate = function(env, frame)
        portrait(env, frame)
        frame.Inset = env.CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    end,
    InsetFrameTemplate = function(env, frame)
        nineSlice(env, frame)
        texture(frame, "Bg")
    end,
    -- Keys as /fstack showed on ProfessionsFrame.ProfessionsOverviewTab (2026-11-08).
    LargeSideTabButtonTemplate = function(_, frame)
        texture(frame, "Background")
        texture(frame, "Icon")
        texture(frame, "Mask")
        texture(frame, "HighlightTexture")
        texture(frame, "TabGlow"):Hide()
        texture(frame, "SelectedTexture"):Hide()
        function frame.SetChecked(f, checked)
            f.checked = checked and true or false
            f.SelectedTexture:SetShown(f.checked)
        end
        function frame.GetChecked(f)
            return f.checked or false
        end
    end,
    TooltipBackdropTemplate = nineSlice,
}

-- StatusBar methods: value, range, texture, and color.
local STATUS_BAR = {
    SetMinMaxValues = function(bar, low, high)
        bar.min, bar.max = low, high
    end,
    GetMinMaxValues = function(bar)
        return bar.min or 0, bar.max or 1
    end,
    SetValue = function(bar, value)
        bar.value = value
    end,
    GetValue = function(bar)
        return bar.value or 0
    end,
    SetStatusBarTexture = function(bar, asset)
        bar.barTexture = asset
    end,
    SetStatusBarColor = function(bar, r, g, b, a)
        bar.barColor = { r, g, b, a }
    end,
}

-- Called by fakeui's CreateFrame for every new frame.
function M.apply(env, frame, frameType, template)
    if frameType == "StatusBar" then
        for name, fn in pairs(STATUS_BAR) do
            frame[name] = fn
        end
    end
    for name in (template or ""):gmatch("[^,%s]+") do
        if BUILD[name] then
            BUILD[name](env, frame)
        end
    end
end

M.TEMPLATES = BUILD

return M
