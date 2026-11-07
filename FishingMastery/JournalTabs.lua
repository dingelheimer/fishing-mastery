-- Filled tabs of the journal window, one entry per tab name: build(window, panel) creates its
-- frames, draw(window, keepScroll) fills them; filters = true shows the fish filter row. This
-- file: Fish (the filtered list on the left, the selected fish's details on the right) and Waters
-- (every water colored for the effective skill, the selected water's fish below; a click on a fish
-- opens it in the Fish tab), and Recipes (bundled and read-in-game recipes, filtered by known or
-- by one fish from the Fish tab). Gear follows in Story 5.7.
local _, ns = ...

local concat, ipairs, tonumber = table.concat, ipairs, tonumber
local L, StatsFrame, JournalTable, WatersTable, RecipeTable =
    ns.L, ns.StatsFrame, ns.JournalTable, ns.WatersTable, ns.RecipeTable

local JournalTabs = {}
ns.JournalTabs = JournalTabs

JournalTabs.LIST_WIDTH = 530 -- the fish list; the details fill the rest of the panel
JournalTabs.WATERS_LIST = 200 -- height of the waters list above the selected water's fish
JournalTabs.RECIPES_TAB = 3

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
        detail:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 30)
        detail:SetJustifyH("LEFT")
        detail:SetJustifyV("TOP")
        detail:SetWordWrap(true)
        self.fishDetail = detail
        -- Link to the Recipes tab, filtered to the selected fish.
        self.fishRecipes = ns.Frames.Button(
            self.env,
            panel,
            L.JOURNAL_RECIPES_BUTTON,
            140,
            function()
                local recipes = self.recipeFilters
                recipes.fish, recipes.show = self.filters.selected, "all"
                self:Select(JournalTabs.RECIPES_TAB)
            end
        )
        self.fishRecipes:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", JournalTabs.LIST_WIDTH + 12, 2)
    end,
    draw = function(self, keepScroll)
        local model, view, recipes = self:Model()
        local input = self:Inputs(view, recipes)
        local filters = self.filters
        local rows = JournalTable.Rows(model, input, filters)
        self.fishList:SetRows(rows, keepScroll)
        self.fishEmpty:SetText(#rows == 0 and L.JOURNAL_EMPTY or "")
        local entry = filters.selected and findEntry(model, filters.selected)
        self.fishDetail:SetText(concat(JournalTable.Detail(entry, input), "\n"))
        self.fishRecipes:SetShown(entry ~= nil and #entry.recipes > 0)
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

JournalTabs.recipes = {
    build = function(self, panel)
        local filters = self.recipeFilters
        self.recipeShowButton = StatsFrame.Button(self, panel, 120, function()
            filters.show = ns.JournalFrame.Next(RecipeTable.SHOWS, filters.show)
        end)
        self.recipeShowButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        self.recipeAllButton = StatsFrame.Button(self, panel, 120, function()
            filters.fish = nil
        end)
        self.recipeAllButton:SetPoint("LEFT", self.recipeShowButton, "RIGHT", 6, 0)
        self.recipeAllButton:SetText(L.RECIPES_ALL)
        local list = StatsFrame.Area(self, panel, 0, 28)
        list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 20)
        self.recipeList = ns.StatsList.Create(self.env, list, RecipeTable.COLUMNS)
        local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 2)
        hint:SetJustifyH("LEFT")
        hint:SetText(L.RECIPES_HINT)
    end,
    draw = function(self, keepScroll)
        local filters = self.recipeFilters
        local recipes = self:Recipes()
        local input = self:Inputs(self:View(), recipes)
        self.recipeList:SetRows(RecipeTable.Rows(recipes, input, filters), keepScroll)
        self.progress:SetText(RecipeTable.Progress(recipes, input, filters))
        self.recipeShowButton:SetText(L["RECIPES_SHOW_" .. filters.show])
        self.recipeAllButton:SetShown(filters.fish ~= nil)
    end,
}
