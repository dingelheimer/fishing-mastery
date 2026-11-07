-- Filled tabs of the journal window, one entry per tab name: build(window, panel) creates its
-- frames, draw(window, keepScroll) fills them; filters = true shows the fish filter row. This
-- file: Fish (the filtered list on the left, the selected fish's details on the right) and Waters
-- (every water colored for the effective skill, the selected water's fish below; a click on a fish
-- opens it in the Fish tab). Recipes and Gear follow in Stories 5.6-5.7.
local _, ns = ...

local concat, ipairs, tonumber = table.concat, ipairs, tonumber
local L, StatsFrame, JournalTable, WatersTable =
    ns.L, ns.StatsFrame, ns.JournalTable, ns.WatersTable

local JournalTabs = {}
ns.JournalTabs = JournalTabs

JournalTabs.LIST_WIDTH = 530 -- the fish list; the details fill the rest of the panel
JournalTabs.WATERS_LIST = 200 -- height of the waters list above the selected water's fish

local function findEntry(model, id)
    for _, entry in ipairs(model.entries) do
        if entry.id == id then
            return entry
        end
    end
end

JournalTabs.fish = {
    filters = true,
    build = function(self, panel)
        local list = StatsFrame.Area(self, panel, 0, 0)
        list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", JournalTabs.LIST_WIDTH, 0)
        self.fishList = ns.StatsList.Create(self.env, list, JournalTable.COLUMNS, nil, function(row)
            self.filters.selected = row.id
            self:Render(true)
        end)
        self.fishEmpty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        self.fishEmpty:SetPoint("TOP", list, "TOP", 0, -60)
        local detail = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detail:SetPoint("TOPLEFT", panel, "TOPLEFT", JournalTabs.LIST_WIDTH + 12, -2)
        detail:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
        detail:SetJustifyH("LEFT")
        detail:SetJustifyV("TOP")
        detail:SetWordWrap(true)
        self.fishDetail = detail
    end,
    draw = function(self, keepScroll)
        local model, view = self:Model()
        local input = self:Inputs(view)
        local filters = self.filters
        local rows = JournalTable.Rows(model, input, filters)
        self.fishList:SetRows(rows, keepScroll)
        self.fishEmpty:SetText(#rows == 0 and L.JOURNAL_EMPTY or "")
        local entry = filters.selected and findEntry(model, filters.selected)
        self.fishDetail:SetText(concat(JournalTable.Detail(entry, input), "\n"))
        self.progress:SetText(JournalTable.Progress(model))
        self.groupButton:SetText(L["JOURNAL_GROUP_" .. filters.group])
        self.showButton:SetText(L["JOURNAL_SHOW_" .. filters.show])
        self.model = model
    end,
}

-- Opens a fish in the Fish tab with every filter cleared.
local function openFish(self, id)
    local filters = self.filters
    filters.group, filters.show, filters.selected = "all", "all", id
    filters.search = ""
    self.searchBox:SetText("")
    self:Select(1)
end

JournalTabs.waters = {
    build = function(self, panel)
        local state = self.waters
        self.fishableButton = StatsFrame.Button(self, panel, 120, function()
            state.fishable = not state.fishable
        end)
        self.fishableButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        self.sortButton = StatsFrame.Button(self, panel, 120, function()
            state.sort = ns.JournalFrame.Next(WatersTable.SORTS, state.sort)
        end)
        self.sortButton:SetPoint("LEFT", self.fishableButton, "RIGHT", 6, 0)
        local list = StatsFrame.Area(self, panel, 0, 28, JournalTabs.WATERS_LIST)
        self.watersList = ns.StatsList.Create(
            self.env,
            list,
            WatersTable.COLUMNS,
            nil,
            function(row)
                state.selected = row.key
                self:Render(true)
            end
        )
        self.watersNote = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.watersNote:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -JournalTabs.WATERS_LIST - 34)
        self.watersNote:SetJustifyH("LEFT")
        local detail = StatsFrame.Area(self, panel, 0, JournalTabs.WATERS_LIST + 52)
        self.watersFish = ns.StatsList.Create(
            self.env,
            detail,
            ns.ZoneRef.COLUMNS,
            nil,
            function(row)
                openFish(self, tonumber(row.key))
            end
        )
    end,
    draw = function(self, keepScroll)
        local state = self.waters
        local view = self:View()
        local input = self:Inputs(view)
        input.zones, input.view, input.skill = self.zones, view, self:Skill()
        input.groupOf = self:Index().groupOf
        local rows = WatersTable.Rows(input, state)
        self.watersList:SetRows(rows, keepScroll)
        local selected
        for _, row in ipairs(rows) do
            if row.key == state.selected then
                selected = row
            end
        end
        if selected then
            local detail = ns.ZoneRef.Detail(view, selected, input)
            self.watersNote:SetText(detail.note .. "  " .. L.WATERS_HINT)
            self.watersFish:SetRows(detail.rows, keepScroll)
        else
            self.watersNote:SetText(L.WATERS_SELECT)
            self.watersFish:SetRows({}, keepScroll)
        end
        self.progress:SetText(WatersTable.Legend(input.skill))
        self.fishableButton:SetText(
            state.fishable and L.WATERS_FISHABLE_ON or L.WATERS_FISHABLE_OFF
        )
        self.sortButton:SetText(L["WATERS_SORT_" .. state.sort])
    end,
}
