-- Layout of the journal window: the movable frame (position saved per character), title,
-- progress line, the filter row (group, caught or not, search box, scope), one panel per tab
-- (built by its JournalTabs entry, else "coming in a later story"), and the tab buttons run by
-- PanelTemplates on frame.Tabs (the frames are unnamed). Unnamed, insecure frames only.
local _, ns = ...

local ipairs = ipairs
local L, Frames, Context, StatsFrame = ns.L, ns.Frames, ns.Context, ns.StatsFrame

local JournalFrame = {}
ns.JournalFrame = JournalFrame

JournalFrame.WIDTH, JournalFrame.HEIGHT = 860, 480
JournalFrame.POSITION_KEY = "journal"
JournalFrame.SEARCH_TEMPLATE = "InputBoxTemplate"
JournalFrame.SEARCH_MAX = 40 -- letters in the search box
JournalFrame.PANEL_TOP = 86

-- The next value of list after current (wraps around).
function JournalFrame.Next(list, current)
    for i, value in ipairs(list) do
        if value == current then
            return list[i % #list + 1]
        end
    end
    return list[1]
end

local function panel(self)
    local frame = self.env.CreateFrame("Frame", nil, self.frame)
    frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -JournalFrame.PANEL_TOP)
    frame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -14, 14)
    return frame
end

local function buildPanels(self)
    self.panels = {}
    for i, name in ipairs(ns.JournalWindow.TABS) do
        local frame = panel(self)
        self.panels[i] = frame
        local tab = ns.JournalTabs[name]
        if tab then
            tab.build(self, frame)
        else
            local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("TOP", frame, "TOP", 0, -60)
            text:SetText(L.JOURNAL_SOON)
        end
    end
end

local function buildTabs(self)
    local env, frame = self.env, self.frame
    frame.Tabs = {}
    for i, name in ipairs(ns.JournalWindow.TABS) do
        local tab = Frames.Create(env, "Button", frame, StatsFrame.TAB_TEMPLATE)
        tab:SetID(i)
        tab:SetText(L["JOURNAL_TAB_" .. name])
        tab:SetScript(
            "OnClick",
            ns.Guard.Wrap("journal:tab", function(clicked)
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

local function buildSearch(self, frame)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 270, -60)
    label:SetText(L.JOURNAL_SEARCH)
    local box = Frames.Create(self.env, "EditBox", frame, JournalFrame.SEARCH_TEMPLATE)
    box:SetSize(160, 20)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 324, -56)
    box:SetAutoFocus(false)
    box:SetMaxLetters(JournalFrame.SEARCH_MAX)
    box:SetScript(
        "OnTextChanged",
        ns.Guard.Wrap("journal:search", function(edit)
            local text = edit:GetText() or ""
            if text ~= self.filters.search then
                self.filters.search = text
                self:Render()
            end
        end)
    )
    box:SetScript("OnEscapePressed", function(edit)
        edit:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(edit)
        edit:ClearFocus()
    end)
    self.searchBox, self.searchLabel = box, label
end

local function buildFilters(self, frame)
    local Table = ns.JournalTable
    self.groupButton = StatsFrame.Button(self, frame, 120, function()
        self.filters.group = JournalFrame.Next(Table.FILTERS, self.filters.group)
    end)
    self.groupButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -56)
    self.showButton = StatsFrame.Button(self, frame, 120, function()
        self.filters.show = JournalFrame.Next(Table.SHOWS, self.filters.show)
    end)
    self.showButton:SetPoint("LEFT", self.groupButton, "RIGHT", 6, 0)
    buildSearch(self, frame)
    self.scopeButton = StatsFrame.Button(self, frame, 130, function()
        self.scope = self.scope == "account" and "character" or "account"
    end)
    self.scopeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -56)
end

-- Creates the window of a JournalWindow (window.frame, progress, filters, panels, tabs).
function JournalFrame.Build(self)
    local env = self.env
    local frame = Frames.Create(env, "Frame", env.UIParent, Frames.TEMPLATE)
    self.frame = frame
    frame:SetSize(JournalFrame.WIDTH, JournalFrame.HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    Frames.RestorePosition(frame, env, self.store, JournalFrame.POSITION_KEY)
    Frames.MakeMovable(frame, self.store, JournalFrame.POSITION_KEY)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText(L.JOURNAL_TITLE)
    self.progress = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.progress:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    self.progress:SetWidth(JournalFrame.WIDTH - 32)
    self.progress:SetJustifyH("LEFT")
    buildFilters(self, frame)
    buildPanels(self)
    buildTabs(self)
end
