-- Layout of the Journal page of the main window (MainWindow.lua): the scope dropdown at the top
-- right, the progress line at the top of the body, the filter row (group, caught or not, search
-- box), one panel per tab (built by its JournalTabs entry), and the bottom tab buttons run by
-- PanelTemplates on frame.Tabs (the frames are unnamed). Unnamed, insecure frames only.
local _, ns = ...

local ipairs = ipairs
local L, Frames, Context, StatsFrame = ns.L, ns.Frames, ns.Context, ns.StatsFrame
local MainWindow = ns.MainWindow

local JournalFrame = {}
ns.JournalFrame = JournalFrame

JournalFrame.WIDTH, JournalFrame.HEIGHT = MainWindow.WIDTH, MainWindow.HEIGHT
JournalFrame.SEARCH_TEMPLATE = "InputBoxTemplate"
JournalFrame.SEARCH_MAX = 40 -- letters in the search box
JournalFrame.PANEL_TOP = 108
JournalFrame.FILTER_Y = -82 -- the filter row
JournalFrame.BAR_X, JournalFrame.BAR_WIDTH = 150, 200 -- the progress bar in the page header

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
        ns.JournalTabs[name].build(self, frame)
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
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 270, JournalFrame.FILTER_Y - 4)
    label:SetText(L.JOURNAL_SEARCH)
    local box = Frames.Create(self.env, "EditBox", frame, JournalFrame.SEARCH_TEMPLATE)
    box:SetSize(160, 20)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 324, JournalFrame.FILTER_Y)
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

-- A dropdown-styled button that changes the window state, then redraws the page.
function JournalFrame.Dropdown(self, parent, width, onClick)
    return ns.Controls.Dropdown(self.env, parent, width, function()
        onClick()
        self:Render()
    end)
end

local function buildFilters(self, frame)
    local Table = ns.JournalTable
    self.groupButton = JournalFrame.Dropdown(self, frame, 120, function()
        self.filters.group = JournalFrame.Next(Table.FILTERS, self.filters.group)
    end)
    self.groupButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, JournalFrame.FILTER_Y)
    self.showButton = JournalFrame.Dropdown(self, frame, 120, function()
        self.filters.show = JournalFrame.Next(Table.SHOWS, self.filters.show)
    end)
    self.showButton:SetPoint("LEFT", self.groupButton, "RIGHT", 6, 0)
    buildSearch(self, frame)
    self.scopeButton = ns.Controls.Dropdown(self.env, frame, 130, function()
        self.scope = self.scope == "account" and "character" or "account"
        self:Render()
    end)
    self.scopeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, MainWindow.CONTROLS_Y)
end

-- The progress bar in the page header; its tooltip lists every group.
local function buildBar(self, page)
    local bar = ns.Controls.Bar(self.env, page, JournalFrame.BAR_WIDTH, 16)
    bar:SetPoint("TOPLEFT", page, "TOPLEFT", JournalFrame.BAR_X, MainWindow.NAME_Y + 2)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(owner)
        local data = owner.data
        if not data then
            return
        end
        ns.Tip.Open(self.env, owner, function(tip)
            tip:Title(L.JOURNAL_BAR_TITLE, ns.Style.GOLD)
            for _, line in ipairs(data.lines) do
                tip:Pair(line.label, line.value)
            end
            if data.pending then
                tip:Line(data.pending, ns.Style.GREY)
            end
        end, "ANCHOR_BOTTOM")
    end)
    bar:SetScript("OnLeave", function(owner)
        ns.Tip.Close(self.env, owner)
    end)
    self.progressBar = bar
end

-- Fills the header bar from JournalTable.Bar.
function JournalFrame.DrawBar(self, data)
    local bar = self.progressBar
    bar.data = data
    bar:SetMinMaxValues(0, data.total > 0 and data.total or 1)
    bar:SetValue(data.caught)
    bar.text:SetText(data.text)
end

-- Builds the page of a JournalWindow on page (the panel of the main window): window.frame,
-- progress, filters, panels, tabs.
function JournalFrame.Build(self, page)
    self.frame = page
    self.progress = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.progress:SetPoint("TOPLEFT", page, "TOPLEFT", 16, MainWindow.BODY_Y)
    self.progress:SetWidth(JournalFrame.WIDTH - 32)
    self.progress:SetJustifyH("LEFT")
    buildBar(self, page)
    buildFilters(self, page)
    buildPanels(self)
    buildTabs(self)
end
