-- Filled tabs of the journal window, one entry per tab name: build(window, panel) creates its
-- frames, draw(window, keepScroll) fills them; filters = true shows the fish filter row. This
-- file: Fish (the filtered list on the left, the selected fish's details on the right) and Waters
-- (every water colored for the effective skill, the selected water's fish below; a click on a fish
-- opens it in the Fish tab; colors for the skill now or the best setup), Recipes (bundled and
-- read-in-game recipes, filtered by known or by one fish from the Fish tab), and Gear (every
-- fishing item, rank, and enchant with what the player has, and the best setup).
local _, ns = ...

local concat, ipairs, tonumber = table.concat, ipairs, tonumber
local L, StatsFrame, JournalTable, WatersTable, RecipeTable, GearTable =
    ns.L, ns.StatsFrame, ns.JournalTable, ns.WatersTable, ns.RecipeTable, ns.GearTable

local function Dropdown(...)
    return ns.JournalFrame.Dropdown(...)
end

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
        self.fishRecipes = ns.Controls.Button(self.env, panel, 160, function()
            local recipes = self.recipeFilters
            recipes.fish, recipes.show = self.filters.selected, "all"
            self:Select(JournalTabs.RECIPES_TAB)
        end)
        self.fishRecipes:SetText(L.JOURNAL_RECIPES_BUTTON)
        self.fishRecipes:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", JournalTabs.LIST_WIDTH + 12, 2)
    end,
    draw = function(self, keepScroll)
        local current = self.current
        local model = current.model
        local input = self:Inputs(current.view, current.recipes)
        local filters = self.filters
        local rows = JournalTable.Rows(model, input, filters)
        self.fishList:SetRows(rows, keepScroll)
        self.fishEmpty:SetText(#rows == 0 and L.JOURNAL_EMPTY or "")
        local entry = filters.selected and findEntry(model, filters.selected)
        self.fishDetail:SetText(concat(JournalTable.Detail(entry, input), "\n"))
        self.fishRecipes:SetShown(entry ~= nil and #entry.recipes > 0)
        local bar = JournalTable.Bar(model)
        self.progress:SetText(bar.pending or "")
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
        self.fishableButton = Dropdown(self, panel, 120, function()
            state.fishable = not state.fishable
        end)
        self.fishableButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        self.sortButton = Dropdown(self, panel, 120, function()
            state.sort = ns.JournalFrame.Next(WatersTable.SORTS, state.sort)
        end)
        self.sortButton:SetPoint("LEFT", self.fishableButton, "RIGHT", 6, 0)
        self.bestButton = Dropdown(self, panel, 140, function()
            state.best = not state.best
        end)
        self.bestButton:SetPoint("LEFT", self.sortButton, "RIGHT", 6, 0)
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
        if state.best then
            local best = ns.GearInputs.Model(self).best
            input.skill = best and best.total or nil
        end
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
        self.progress:SetText(WatersTable.Legend(input.skill, state.best))
        self.fishableButton:SetText(
            state.fishable and L.WATERS_FISHABLE_ON or L.WATERS_FISHABLE_OFF
        )
        self.sortButton:SetText(L["WATERS_SORT_" .. state.sort])
        self.bestButton:SetText(state.best and L.WATERS_BEST_ON or L.WATERS_BEST_OFF)
    end,
}

JournalTabs.recipes = {
    build = function(self, panel)
        local filters = self.recipeFilters
        self.recipeShowButton = Dropdown(self, panel, 120, function()
            filters.show = ns.JournalFrame.Next(RecipeTable.SHOWS, filters.show)
        end)
        self.recipeShowButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        self.recipeAllButton = ns.Controls.Button(self.env, panel, 120, function()
            filters.fish = nil
            self:Render()
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

JournalTabs.gear = {
    build = function(self, panel)
        local list = StatsFrame.Area(self, panel, 0, 0)
        list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 20)
        self.gearList = ns.StatsList.Create(self.env, list, GearTable.COLUMNS)
        self.gearMeasure = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        self.gearMeasure:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2, 2)
        self.gearMeasure:SetJustifyH("LEFT")
    end,
    draw = function(self, keepScroll)
        local model, input = ns.GearInputs.Model(self)
        self.gearList:SetRows(GearTable.Rows(model, input), keepScroll)
        self.gearMeasure:SetText(GearTable.Measure(model))
        self.progress:SetText(GearTable.Best(model, self:Skill()))
    end,
}
