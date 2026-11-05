-- Layout of the stats window: the movable frame (position saved per character), title, status
-- line, scope button, one panel per tab (built by its StatsTabs entry, else "coming soon"), and
-- the tab buttons run by PanelTemplates on frame.Tabs (the frames are unnamed). Unnamed, insecure
-- frames only.
local _, ns = ...

local ipairs = ipairs
local L, Frames, Context = ns.L, ns.Frames, ns.Context

local StatsFrame = {}
ns.StatsFrame = StatsFrame

StatsFrame.WIDTH, StatsFrame.HEIGHT = 760, 470
StatsFrame.POSITION_KEY = "stats"
StatsFrame.TAB_TEMPLATE = "PanelTabButtonTemplate"
StatsFrame.PANEL_WIDTH = StatsFrame.WIDTH - 28

local function panel(self)
    local frame = self.env.CreateFrame("Frame", nil, self.frame)
    frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -58)
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

-- Creates the window of a StatsWindow (window.frame, status, buttons, panels, lists, tabs).
function StatsFrame.Build(self)
    local env = self.env
    local frame = Frames.Create(env, "Frame", env.UIParent, Frames.TEMPLATE)
    self.frame = frame
    frame:SetSize(StatsFrame.WIDTH, StatsFrame.HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    Frames.RestorePosition(frame, env, self.store, StatsFrame.POSITION_KEY)
    Frames.MakeMovable(frame, self.store, StatsFrame.POSITION_KEY)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText(L.STATS_TITLE)
    self.status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -36)
    self.status:SetWidth(StatsFrame.WIDTH - 180)
    self.status:SetJustifyH("LEFT")
    self.scopeButton = StatsFrame.Button(self, frame, 130, function()
        self.scope = self.scope == "char" and "all" or "char"
    end)
    self.scopeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -30)
    buildPanels(self)
    buildTabs(self)
end
