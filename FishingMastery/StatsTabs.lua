-- Filled tabs of the Statistics page, one entry per tab name: build(window, panel) creates its
-- frames once, draw(window, input, keepScroll) fills them from the aggregates and returns the view
-- it used (for the status line); scoped tabs show the scope button. This file: Overview
-- (OverviewPage.lua), Fish, and Zones (a click on a zone row shows its Classic comparison
-- below); FailureTabs.lua adds Failures, Bite times, and Sessions; SkillTabs.lua Skill and
-- Compare.
local _, ns = ...

local format, ipairs = string.format, ipairs
local L, StatsFrame = ns.L, ns.StatsFrame
local StatsView, StatsTables, ZoneTable = ns.StatsView, ns.StatsTables, ns.ZoneTable

local StatsTabs = {}
ns.StatsTabs = StatsTabs

StatsTabs.ZONE_LIST = 190 -- height of the zone list above the comparison

StatsTabs.overview = {
    scoped = true,
    build = function(self, panel)
        self.overview = {}
        local width, height = StatsFrame.PANEL_WIDTH, StatsFrame.PANEL_HEIGHT
        ns.OverviewPage.Build(self.overview, self.env, panel, width, height)
    end,
    draw = function(self, input)
        local model = self:OverviewModel()
        ns.OverviewPage.Draw(
            self.overview,
            ns.OverviewModel.Build({
                model = model,
                sessions = self:SessionCount(),
                skill = self:Skill(),
                info = input.info,
            })
        )
        return model.view
    end,
}

StatsTabs.fish = {
    scoped = true,
    build = function(self, panel)
        self.qualityButton = ns.Controls.Dropdown(self.env, panel, 140, function()
            self.quality = (self.quality + 1) % (#StatsTables.QUALITIES + 1)
            self:Render()
        end)
        self.qualityButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        self.fishKinds = panel:CreateFontString(nil, "OVERLAY", ns.Style.FONTS.secondary)
        self.fishKinds:SetPoint("LEFT", self.qualityButton, "RIGHT", 10, 0)
        local area = StatsFrame.Area(self, panel, 0, 28)
        self.fish = ns.StatsList.Create(self.env, area, StatsTables.FISH_COLUMNS, function(key)
            self:SortBy("fish", key)
        end)
        self.fish:SetLegend(L.LIST_GREY)
    end,
    draw = function(self, input, keepScroll)
        local view = StatsView.Build(self:Chars())
        input.sort = self.sorts.fish
        local rows = StatsTables.Fish(view, input)
        self.fish:SetRows(rows, keepScroll, input.sort)
        self.fishKinds:SetText(StatsTables.Kinds(rows))
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
