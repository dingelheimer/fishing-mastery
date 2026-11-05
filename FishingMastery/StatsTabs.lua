-- Filled tabs of the stats window, one entry per tab name: build(window, panel) creates its frames
-- once, draw(window, input, keepScroll) fills them from the aggregates and returns the view it
-- used (for the status line); scoped tabs show the scope button. This file: Overview, Fish, and
-- Zones; FailureTabs.lua adds Failures, Bite times, and Sessions.
local _, ns = ...

local concat, format = table.concat, string.format
local L, StatsFrame = ns.L, ns.StatsFrame
local StatsModel, StatsView, StatsTables, ZoneTable, OverviewTable =
    ns.StatsModel, ns.StatsView, ns.StatsTables, ns.ZoneTable, ns.OverviewTable

local StatsTabs = {}
ns.StatsTabs = StatsTabs

StatsTabs.OVERVIEW_TEXT = 190 -- height of the Overview text block

StatsTabs.overview = {
    build = function(self, panel)
        self.overviewText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.overviewText:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, 0)
        self.overviewText:SetWidth(StatsFrame.PANEL_WIDTH - 4)
        self.overviewText:SetJustifyH("LEFT")
        local area = StatsFrame.Area(self, panel, 0, StatsTabs.OVERVIEW_TEXT)
        self.characters = ns.StatsList.Create(self.env, area, OverviewTable.COLUMNS)
    end,
    draw = function(self, input, keepScroll)
        local model = StatsModel.Overview({
            chars = self.db.chars,
            current = self.charKey,
            now = self.serverTime(),
            thresholds = self.thresholds,
        })
        self.overviewText:SetText(concat(OverviewTable.Lines(model, input), "\n"))
        self.characters:SetRows(OverviewTable.Rows(model, input), keepScroll)
        return nil
    end,
}

StatsTabs.fish = {
    scoped = true,
    build = function(self, panel)
        self.qualityButton = StatsFrame.Button(self, panel, 140, function()
            self.quality = (self.quality + 1) % (#StatsTables.QUALITIES + 1)
        end)
        self.qualityButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        local area = StatsFrame.Area(self, panel, 0, 28)
        self.fish = ns.StatsList.Create(self.env, area, StatsTables.FISH_COLUMNS, function(key)
            self:SortBy("fish", key)
        end)
    end,
    draw = function(self, input, keepScroll)
        local view = StatsView.Build(self:Chars())
        input.sort = self.sorts.fish
        self.fish:SetRows(StatsTables.Fish(view, input), keepScroll)
        local quality = input.quality
        self.qualityButton:SetText(
            quality and format(L.STATS_QUALITY, L["STATS_QUALITY_" .. quality])
                or L.STATS_QUALITY_ALL
        )
        return view
    end,
}

StatsTabs.zones = {
    scoped = true,
    build = function(self, panel)
        self.zones = ns.StatsList.Create(self.env, StatsFrame.Area(self, panel), ZoneTable.COLUMNS)
    end,
    draw = function(self, input, keepScroll)
        local view = StatsView.Build(self:Chars())
        self.zones:SetRows(ZoneTable.Rows(view, input), keepScroll)
        return view
    end,
}
