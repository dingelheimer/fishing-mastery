-- Test window for the UI API check (/fm dev ui, dev flag only): a chart area with one line, one
-- bar, and an item icon, a list area with a 3-row scroll list, two tab buttons, and an "Open
-- settings" button. The Draw functions use the APIs under test and may raise; UiCheck runs each
-- one protected. Drawn parts are kept on the window and reused on the next run. Unnamed and
-- insecure frames only.
local _, ns = ...

local format, ipairs, pcall, concat, tostring = string.format, ipairs, pcall, table.concat, tostring
local L = ns.L
local Frames = ns.Frames

local UiTest = {}
ns.UiTest = UiTest

UiTest.WIDTH = 420
UiTest.HEIGHT = 250
UiTest.AREA_WIDTH = 180
UiTest.AREA_HEIGHT = 120
UiTest.ROW_HEIGHT = 20
UiTest.POSITION_KEY = "uiCheck"
UiTest.SCROLL_TEMPLATE = "WowScrollBoxList"
UiTest.SCROLLBAR_TEMPLATE = "MinimalScrollBar"
UiTest.TAB_TEMPLATES =
    { "PanelTabButtonTemplate", "PanelTopTabButtonTemplate", "CharacterFrameTabButtonTemplate" }

local function area(env, parent, label, x)
    local frame = env.CreateFrame("Frame", nil, parent)
    frame:SetSize(UiTest.AREA_WIDTH, UiTest.AREA_HEIGHT)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -54)
    local caption = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    caption:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4)
    caption:SetText(label)
    return frame
end

-- store: FishingMasteryCharDB.ui (the window position is saved there).
-- onSettings(): runs on the "Open settings" button.
function UiTest.Create(env, store, onSettings)
    local frame = Frames.Create(env, "Frame", env.UIParent, Frames.TEMPLATE)
    frame:SetSize(UiTest.WIDTH, UiTest.HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    Frames.RestorePosition(frame, env, store, UiTest.POSITION_KEY)
    Frames.MakeMovable(frame, store, UiTest.POSITION_KEY)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText(L.UI_TITLE)
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 44)
    hint:SetWidth(UiTest.WIDTH - 32)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.UI_HINT)

    local window = {
        env = env,
        frame = frame,
        chart = area(env, frame, L.UI_CHART, 16),
        list = area(env, frame, L.UI_LIST, UiTest.WIDTH - 16 - UiTest.AREA_WIDTH),
    }
    window.settingsButton = Frames.Button(env, frame, L.UI_OPEN_SETTINGS, 120, onSettings)
    window.settingsButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
    window.closeButton = Frames.Button(env, frame, L.BUTTON_CLOSE, 80, function()
        frame:Hide()
    end)
    window.closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    return window
end

-- Frame:CreateLine with start, end, and thickness.
function UiTest.DrawLine(window)
    local chart = window.chart
    local line = window.line or chart:CreateLine(nil, "ARTWORK")
    window.line = line
    line:SetColorTexture(1, 0.82, 0, 1)
    line:SetStartPoint("BOTTOMLEFT", chart, 50, 10)
    line:SetEndPoint("TOPRIGHT", chart, -10, -30)
    line:SetThickness(2)
    return "drawn"
end

-- One bar from a color texture.
function UiTest.DrawBar(window)
    local chart = window.chart
    local bar = window.bar or chart:CreateTexture(nil, "ARTWORK")
    window.bar = bar
    bar:SetColorTexture(0.2, 0.6, 1, 1)
    bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", 10, 0)
    bar:SetSize(24, 80)
    return "drawn"
end

-- An item icon (file ID from C_Item.GetItemIconByID) in the chart corner.
function UiTest.DrawIcon(window, icon)
    local chart = window.chart
    window.icon = window.icon or chart:CreateTexture(nil, "ARTWORK")
    window.icon:SetTexture(icon)
    window.icon:SetSize(24, 24)
    window.icon:SetPoint("TOPRIGHT", chart, "TOPRIGHT", 0, 0)
end

local function buildScrollBox(window)
    local env, list = window.env, window.list
    local box = env.CreateFrame("Frame", nil, list, UiTest.SCROLL_TEMPLATE)
    box:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    box:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -16, 0)
    local barType = "EventFrame"
    local ok, bar = pcall(env.CreateFrame, barType, nil, list, UiTest.SCROLLBAR_TEMPLATE)
    if not ok or not bar then
        barType = "Frame"
        bar = env.CreateFrame(barType, nil, list, UiTest.SCROLLBAR_TEMPLATE)
    end
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = env.CreateScrollBoxListLinearView()
    view:SetElementExtent(UiTest.ROW_HEIGHT)
    view:SetElementInitializer(
        "Frame",
        ns.Guard.Wrap("uicheck:row", function(row, data)
            if not row.label then
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
            end
            row.label:SetText(data.text)
        end)
    )
    env.ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    window.scrollBox, window.barType = box, barType
end

-- ScrollBox list with a linear view, a scroll bar, and a data provider of 3 rows.
function UiTest.DrawList(window)
    if not window.scrollBox then
        buildScrollBox(window)
    end
    local rows = {}
    for i = 1, 3 do
        rows[i] = { text = format(L.UI_ROW, i) }
    end
    local provider = window.env.CreateDataProvider(rows)
    window.scrollBox:SetDataProvider(provider)
    local size = provider.GetSize and provider:GetSize()
    return format("%s rows, scroll bar %s", tostring(size), window.barType)
end

local function buildTabs(window)
    local env, frame = window.env, window.frame
    for _, template in ipairs(UiTest.TAB_TEMPLATES) do
        local ok, first = pcall(env.CreateFrame, "Button", nil, frame, template)
        if ok and first then
            window.tabs = { first, env.CreateFrame("Button", nil, frame, template) }
            window.tabTemplate = template
            break
        end
    end
    if not window.tabs then
        error("no tab template of " .. concat(UiTest.TAB_TEMPLATES, ", "))
    end
    for i, tab in ipairs(window.tabs) do
        tab:SetID(i)
        tab:SetText(format(L.UI_TAB, i))
        tab:SetScript(
            "OnClick",
            ns.Guard.Wrap("uicheck:tab", function(self)
                env.PanelTemplates_SetTab(frame, self:GetID())
            end)
        )
    end
    window.tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    window.tabs[2]:SetPoint("LEFT", window.tabs[1], "RIGHT", 4, 0)
end

-- Two tab buttons from the first tab template that exists, run by PanelTemplates on frame.Tabs
-- (the frames are unnamed, so PanelTemplates cannot find "<name>Tab<n>" globals).
function UiTest.DrawTabs(window)
    if not window.tabs then
        buildTabs(window)
    end
    local env, frame = window.env, window.frame
    frame.Tabs = window.tabs
    env.PanelTemplates_SetNumTabs(frame, #window.tabs)
    env.PanelTemplates_SetTab(frame, 1)
    return window.tabTemplate
end
