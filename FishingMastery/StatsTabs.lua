-- Filled tabs of the stats window, one entry per tab name: build(window, panel) creates its frames
-- once, draw(window, input, keepScroll) fills them from the aggregates and returns the view it
-- used (for the status line); scoped tabs show the scope button. This file: Overview, Fish, and
-- Zones (a click on a zone row shows its Classic comparison below); FailureTabs.lua adds Failures,
-- Bite times, and Sessions; SkillTabs.lua Skill and Compare.
local _, ns = ...

local concat, format, ipairs = table.concat, string.format, ipairs
local L, StatsFrame = ns.L, ns.StatsFrame
local StatsModel, StatsView, StatsTables, ZoneTable, OverviewTable =
    ns.StatsModel, ns.StatsView, ns.StatsTables, ns.ZoneTable, ns.OverviewTable

local StatsTabs = {}
ns.StatsTabs = StatsTabs

StatsTabs.OVERVIEW_TEXT = 150 -- height of the Overview text block
StatsTabs.ZONE_LIST = 190 -- height of the zone list above the comparison

StatsTabs.overview = {
    build = function(self, panel)
        self.overviewText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.overviewText:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, 0)
        self.overviewText:SetWidth(StatsFrame.PANEL_WIDTH - 4)
        self.overviewText:SetJustifyH("LEFT")
        local heatTop = StatsFrame.HEIGHT - 72 - ns.Heatmap.HEIGHT
        local area = StatsFrame.Area(
            self,
            panel,
            0,
            StatsTabs.OVERVIEW_TEXT,
            heatTop - 8 - StatsTabs.OVERVIEW_TEXT
        )
        self.characters = ns.StatsList.Create(self.env, area, OverviewTable.COLUMNS)
        self.heatmap = ns.Heatmap.Create(self.env, panel, StatsFrame.PANEL_WIDTH)
        self.heatmap.frame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -heatTop)
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
        local today = ns.Codec.Day(self.serverTime())
        self.heatmap:Draw(ns.CalendarModel.Build(model.days, today), input)
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
        local list = StatsFrame.Area(self, panel, 0, 0, StatsTabs.ZONE_LIST)
        self.zones = ns.StatsList.Create(self.env, list, ZoneTable.COLUMNS, nil, function(row)
            self.zoneKey = row.key
            self:Render(true)
        end)
        self.zoneNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.zoneNote:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -StatsTabs.ZONE_LIST - 6)
        self.zoneNote:SetWidth(StatsFrame.PANEL_WIDTH - 4)
        self.zoneNote:SetJustifyH("LEFT")
        -- Hovering does not select a row (Epic 4 review): say that a click does.
        self.zoneHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        self.zoneHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -StatsTabs.ZONE_LIST - 20)
        self.zoneHint:SetJustifyH("LEFT")
        self.zoneHint:SetText(L.ZONE_HINT)
        local detail = StatsFrame.Area(self, panel, 0, StatsTabs.ZONE_LIST + 40)
        self.zoneDetail = ns.StatsList.Create(self.env, detail, ns.ZoneRef.COLUMNS)
    end,
    draw = function(self, input, keepScroll)
        local view = StatsView.Build(self:Chars())
        local rows = ZoneTable.Rows(view, input)
        local selected = nil
        for _, row in ipairs(rows) do
            if row.key == self.zoneKey then
                selected = row
            end
        end
        selected = selected or rows[1]
        if selected then
            selected.selected = true
            self.zoneKey = selected.key
        end
        self.zones:SetRows(rows, keepScroll)
        local detail = ns.ZoneRef.Detail(view, selected, input)
        self.zoneNote:SetText(detail.note)
        self.zoneDetail:SetRows(detail.rows, keepScroll)
        return view
    end,
}
