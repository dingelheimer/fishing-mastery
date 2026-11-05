-- Failures, Bite times, and Sessions tabs of the stats window (entries as in StatsTabs.lua):
-- the outcome table with two bar charts (getaway rate by skill band with ranges, early clicks by
-- click time), the bite histogram of a chosen group with median and quartiles over the table of
-- groups, and the sortable session list.
local _, ns = ...

local type, pairs, format = type, pairs, string.format
local L, StatsFrame, StatsTabs, StatsView = ns.L, ns.StatsFrame, ns.StatsTabs, ns.StatsView
local FailureTable, BiteTable, SessionTable = ns.FailureTable, ns.BiteTable, ns.SessionTable

local FailureTabs = {}
ns.FailureTabs = FailureTabs

FailureTabs.TABLE_HEIGHT = 150 -- outcome table on the Failures tab
FailureTabs.CHART_GAP = 12
FailureTabs.BITE_CHART = 190

local function chart(self, panel, x, top, width, height)
    local widget = ns.BarChart.Create(self.env, panel, width, height)
    widget.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -top)
    return widget
end

StatsTabs.failures = {
    scoped = true,
    build = function(self, panel)
        local area = StatsFrame.Area(self, panel, 0, 0, FailureTabs.TABLE_HEIGHT)
        self.failures = ns.StatsList.Create(self.env, area, FailureTable.COLUMNS)
        local top = FailureTabs.TABLE_HEIGHT + 8
        local width = (StatsFrame.PANEL_WIDTH - FailureTabs.CHART_GAP) / 2
        local height = StatsFrame.HEIGHT - 72 - top
        self.skillChart = chart(self, panel, 0, top, width, height)
        self.clickChart = chart(self, panel, width + FailureTabs.CHART_GAP, top, width, height)
    end,
    draw = function(self, input, keepScroll)
        local view = StatsView.Build(self:Chars())
        local t = input.thresholds
        self.failures:SetRows(FailureTable.Rows(view, t), keepScroll)
        self.skillChart:Draw(
            L.STATS_CHART_SKILL,
            FailureTable.SkillChart(view, t),
            L.STATS_CHART_NO_HOOKED
        )
        self.clickChart:Draw(
            L.STATS_CHART_CLICKS,
            FailureTable.ClickChart(view),
            L.STATS_CHART_NO_CLICKS
        )
        return view
    end,
}

StatsTabs.bites = {
    scoped = true,
    build = function(self, panel)
        self.biteButton = StatsFrame.Button(self, panel, 300, function()
            self.biteGroup = self.biteGroup % (self.biteCount or 1) + 1
        end)
        self.biteButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        self.biteText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.biteText:SetPoint("TOPLEFT", panel, "TOPLEFT", 312, -5)
        self.biteText:SetWidth(StatsFrame.PANEL_WIDTH - 312)
        self.biteText:SetJustifyH("LEFT")
        self.biteChart = chart(self, panel, 0, 30, StatsFrame.PANEL_WIDTH, FailureTabs.BITE_CHART)
        local area = StatsFrame.Area(self, panel, 0, 30 + FailureTabs.BITE_CHART + 6)
        self.biteList = ns.StatsList.Create(self.env, area, BiteTable.COLUMNS)
    end,
    draw = function(self, input, keepScroll)
        local view = StatsView.Build(self:Chars())
        local groups = BiteTable.Groups(view)
        self.biteCount = #groups
        if self.biteGroup > #groups then
            self.biteGroup = 1
        end
        local group = groups[self.biteGroup]
        self.biteList:SetRows(BiteTable.Rows(groups, input.mapName, self.biteGroup), keepScroll)
        self.biteButton:SetShown(group ~= nil)
        if not group then
            self.biteText:SetText("")
            self.biteChart:Draw("", nil, L.STATS_CHART_NO_BITES)
            return view
        end
        local name = BiteTable.Name(group, input.mapName)
        self.biteButton:SetText(format(L.STATS_BITE_SHOWING, name))
        self.biteText:SetText(BiteTable.Summary(group))
        self.biteChart:Draw(name, BiteTable.Chart(group))
        return view
    end,
}

-- Characters of the chosen scope with their names, for the session list.
local function namedChars(self)
    local chars = type(self.db.chars) == "table" and self.db.chars or {}
    if self.scope == "char" then
        local entry = chars[self.charKey]
        return entry and { { entry = entry, name = entry.name } } or {}
    end
    local list = {}
    for _, entry in pairs(chars) do
        if type(entry) == "table" then
            list[#list + 1] = { entry = entry, name = entry.name }
        end
    end
    return list
end

StatsTabs.sessions = {
    scoped = true,
    build = function(self, panel)
        local area = StatsFrame.Area(self, panel)
        self.sessions = ns.StatsList.Create(self.env, area, SessionTable.COLUMNS, function(key)
            self:SortBy("sessions", key)
        end)
    end,
    draw = function(self, input, keepScroll)
        input.sort = self.sorts.sessions
        input.now = self.serverTime()
        local rows = SessionTable.Rows(namedChars(self), input)
        self.sessions:SetRows(rows, keepScroll)
        self.sessionCount = #rows
        return nil
    end,
}
