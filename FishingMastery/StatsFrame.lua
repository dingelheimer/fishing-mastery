-- Layout of the Statistics page of the main window (MainWindow.lua): the scope dropdown at the
-- top right, the status line at the top of the body, one panel per tab (built by its StatsTabs
-- entry, else "coming soon"), and the bottom tab buttons run by PanelTemplates on frame.Tabs (the
-- frames are unnamed). Unnamed, insecure frames only.
local _, ns = ...

local ipairs = ipairs
local L, Frames, Context, MainWindow = ns.L, ns.Frames, ns.Context, ns.MainWindow

local StatsFrame = {}
ns.StatsFrame = StatsFrame

StatsFrame.WIDTH, StatsFrame.HEIGHT = MainWindow.WIDTH, MainWindow.HEIGHT
StatsFrame.TAB_TEMPLATE = "PanelTabButtonTemplate"
StatsFrame.PANEL_TOP = 82
StatsFrame.PANEL_WIDTH = StatsFrame.WIDTH - 28
StatsFrame.PANEL_HEIGHT = StatsFrame.HEIGHT - StatsFrame.PANEL_TOP - 14

local function panel(self)
    local frame = self.env.CreateFrame("Frame", nil, self.frame)
    frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -StatsFrame.PANEL_TOP)
    frame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -14, 14)
    return frame
end

-- A frame in parent from top (pixels below its top) to its bottom, or of height when given.
function StatsFrame.Area(self, parent, x, top, height)
    local frame = self.env.CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, -(top or 0))
    if height then
        frame:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", 0, -(top or 0) - height)
    else
        frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    end
    return frame
end

-- A button whose click changes the window state, then redraws the window.
function StatsFrame.Button(self, parent, width, onClick)
    return Frames.Button(self.env, parent, "", width, function()
        onClick()
        self:Render()
    end)
end

-- One panel per tab, built by its StatsTabs entry, or "coming soon".
local function buildPanels(self)
    self.panels = {}
    for i, name in ipairs(ns.StatsWindow.TABS) do
        local frame = panel(self)
        self.panels[i] = frame
        local tab = ns.StatsTabs[name]
        if tab then
            tab.build(self, frame)
        else
            local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("TOP", frame, "TOP", 0, -60)
            text:SetText(L.STATS_SOON)
        end
    end
end

local function buildTabs(self)
    local env, frame = self.env, self.frame
    frame.Tabs = {}
    for i, name in ipairs(ns.StatsWindow.TABS) do
        local tab = Frames.Create(env, "Button", frame, StatsFrame.TAB_TEMPLATE)
        tab:SetID(i)
        tab:SetText(L["STATS_TAB_" .. name])
        tab:SetScript(
            "OnClick",
            ns.Guard.Wrap("stats:tab", function(clicked)
                self:Select(clicked:GetID())
            end)
        )
        if i == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
        else
            tab:SetPoint("LEFT", frame.Tabs[i - 1], "RIGHT", 4, 0)
        end
        frame.Tabs[i] = tab
    end
    Context.Call(env, "PanelTemplates_SetNumTabs", frame, #frame.Tabs)
end

-- Builds the page of a StatsWindow on page (the panel of the main window): window.frame,
-- status, scope dropdown, panels, lists, tabs.
function StatsFrame.Build(self, page)
    self.frame = page
    self.status = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.status:SetPoint("TOPLEFT", page, "TOPLEFT", 16, MainWindow.BODY_Y)
    self.status:SetWidth(StatsFrame.WIDTH - 32)
    self.status:SetJustifyH("LEFT")
    self.scopeButton = ns.Controls.Dropdown(self.env, page, 130, function()
        self.scope = self.scope == "char" and "all" or "char"
        self:Render()
    end)
    self.scopeButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, MainWindow.CONTROLS_Y)
    buildPanels(self)
    buildTabs(self)
end
