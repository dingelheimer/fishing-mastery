-- The journal window (/fm journal, Shift-click on the minimap button or the addon compartment):
-- an own movable window (owner decision 1, 2026-11-06) with the tabs Fish, Waters, Recipes, Gear.
-- Position and last tab are saved per character. The Fish tab lists the JournalModel entries of
-- the chosen scope (account-wide by default) with filters and a detail pane; Waters and Recipes
-- follow (JournalTabs.lua), Gear is a placeholder until its story. Built on first open
-- (JournalFrame.lua); item names that load later redraw once per frame. Unnamed, insecure frames
-- only.
local _, ns = ...

local setmetatable, type, pairs, ipairs, select, tostring =
    setmetatable, type, pairs, ipairs, select, tostring
local L, Context = ns.L, ns.Context

local JournalWindow = {}
JournalWindow.__index = JournalWindow
ns.JournalWindow = JournalWindow

JournalWindow.TABS = { "fish", "waters", "recipes", "gear" }
JournalWindow.TAB_KEY = "journalTab" -- FishingMasteryCharDB.ui key of the last tab
JournalWindow.QUALITY_HEX = 4 -- C_Item.GetItemQualityColor: hex color
-- Days before each month in a year without 29 February (1970, the epoch year).
JournalWindow.DAYS_BEFORE = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }

-- deps: { env, castLog, db (FishingMasteryDB), charKey, store (FishingMasteryCharDB.ui), areas
-- (the Area resolver), zones, journal, after(seconds, fn) }.
function JournalWindow.Start(deps)
    local tab = deps.store[JournalWindow.TAB_KEY]
    return setmetatable({
        env = deps.env,
        castLog = deps.castLog,
        db = deps.db,
        charKey = deps.charKey,
        store = deps.store,
        areas = deps.areas,
        zones = deps.zones,
        journal = deps.journal,
        after = deps.after,
        tab = type(tab) == "number" and JournalWindow.TABS[tab] and tab or 1,
        scope = "account", -- owner decision 5
        filters = { group = "all", show = "all", search = "" },
        waters = { fishable = false, sort = "name" },
        recipeFilters = { show = "all" },
        waiting = {},
    }, JournalWindow)
end

-- Static index of the bundled data, built on first use.
function JournalWindow:Index()
    if not self.index then
        self.index = ns.JournalModel.Index(self.journal, self.zones, self.areas)
        local areaMap = {}
        for map, area in pairs(self.zones.mapToArea or {}) do
            areaMap[area] = map
        end
        self.areaMap = areaMap
    end
    return self.index
end

local function itemInfo(self, id)
    local onLoad = nil
    if not self.waiting[id] then
        onLoad = function()
            self.waiting[id] = nil
            self:Redraw()
        end
    end
    local info = self.castLog.items:Info(id, onLoad)
    if not info.name and onLoad then
        self.waiting[id] = true
    end
    if info.quality then
        info.hex = select(
            JournalWindow.QUALITY_HEX,
            Context.Call(self.env, "C_Item.GetItemQualityColor", info.quality)
        )
    end
    return info
end

-- Forever item class and subclass of an item (nil while not loaded).
local function classOf(self, id)
    local info = { Context.Call(self.env, "C_Item.GetItemInfoInstant", id) }
    local class, subclass = info[6], info[7]
    if type(class) == "number" and type(subclass) == "number" then
        return class, subclass
    end
    return nil
end

-- Journal item test for the recipe read: a bundled journal item or a Forever fish or container.
function JournalWindow:IsJournal(id)
    return ns.JournalModel.GroupOf(self:Index(), function(item)
        return classOf(self, item)
    end, id) ~= nil
end

-- The recipe list: bundled recipes merged with the ones read in game (FishingMasteryDB.recipes).
function JournalWindow:Recipes()
    return ns.RecipeModel.Build(self.journal, self.db.recipes)
end

-- StatsView view of the chosen scope.
function JournalWindow:View()
    return ns.StatsView.Build(ns.JournalModel.Chars(self.db.chars, self.scope, self.charKey))
end

-- Effective fishing skill (rank + modifier, as the HUD uses), or nil without Fishing.
function JournalWindow:Skill()
    local rank, modifier = Context.Fishing(self.env)
    if type(rank) ~= "number" then
        return nil
    end
    return rank + (type(modifier) == "number" and modifier or 0)
end

-- The model of the chosen scope, the view it was built from, and the recipe list.
function JournalWindow:Model()
    local view, recipes = self:View(), self:Recipes()
    local model = ns.JournalModel.Build({
        index = self:Index(),
        view = view,
        classOf = function(id)
            return classOf(self, id)
        end,
        recipesOf = ns.RecipeModel.ByReagent(recipes),
    })
    return model, view, recipes
end

-- Own catches of an item and all catches in an area's water (ZoneRef.Own over its zone's map).
local function ownShare(self, view, area, id)
    local info = self.areas:Info(area)
    local zone = info and (info.zone or area)
    local map = zone and self.areaMap[zone]
    if not map then
        return nil
    end
    local group = ns.ZoneRef.Own(view, self.areas, map, area)
    local catches = group.outcomes.catch or 0
    return group.items[id] or 0, catches
end

-- Inputs of the table builders (JournalTable, RecipeTable). recipes: the recipe list (built when
-- not given).
function JournalWindow:Inputs(view, recipes)
    local env, names, spells, known, stock = self.env, {}, {}, {}, {}
    recipes = recipes or self:Recipes()
    return {
        info = function(id)
            return itemInfo(self, id)
        end,
        areas = self.areas,
        thresholds = ns.Stats.Thresholds(self.db.settings.thresholds),
        mapName = function(map)
            if names[map] == nil then
                names[map] = Context.MapName(env, map) or false
            end
            return names[map] or nil
        end,
        areaName = function(area)
            return Context.AreaName(env, area)
        end,
        spellName = function(spell)
            if spells[spell] == nil then
                local data = Context.Call(env, "C_Spell.GetSpellInfo", spell)
                spells[spell] = type(data) == "table" and type(data.name) == "string" and data.name
                    or false
            end
            return spells[spell] or nil
        end,
        recipe = function(spell)
            return ns.RecipeModel.Find(recipes, spell)
        end,
        known = function(spell)
            if known[spell] == nil then
                -- Story 5.1: IsSpellKnown is false for known recipes on Forever.
                local value = Context.Call(env, "IsPlayerSpell", spell)
                known[spell] = type(value) == "boolean" and { value } or {}
            end
            return known[spell][1]
        end,
        stock = function(id)
            if stock[id] == nil then
                local value = Context.Call(env, "C_Item.GetItemCount", id, true)
                stock[id] = type(value) == "number" and value or false
            end
            return stock[id] or nil
        end,
        ownShare = function(area, id)
            return ownShare(self, view, area, id)
        end,
        formatDate = function(t)
            local date = env.date
            return type(date) == "function" and date("%Y-%m-%d", t) or tostring(t)
        end,
        formatMonthDay = function(month, day)
            local date = env.date
            if type(date) ~= "function" then
                return month .. "/" .. day
            end
            local days = JournalWindow.DAYS_BEFORE[month] + day - 1
            return date("!%d %b", days * 86400)
        end,
    }
end

-- Draws the shown tab.
function JournalWindow:Render(keepScroll)
    for i, frame in ipairs(self.panels) do
        frame:SetShown(i == self.tab)
    end
    Context.Call(self.env, "PanelTemplates_SetTab", self.frame, self.tab)
    self.scopeButton:SetText(L["JOURNAL_SCOPE_" .. self.scope])
    local name = JournalWindow.TABS[self.tab]
    local tab = ns.JournalTabs[name]
    local filters = tab and tab.filters == true
    self.groupButton:SetShown(filters)
    self.showButton:SetShown(filters)
    self.searchBox:SetShown(filters)
    self.searchLabel:SetShown(filters)
    if tab then
        tab.draw(self, keepScroll)
    else
        self.progress:SetText("")
    end
end

-- Redraws once per frame after item data arrived, keeping the scroll position.
function JournalWindow:Redraw()
    if self.redrawing or not (self.frame and self.frame:IsShown()) then
        return
    end
    if not self.after then
        self:Render(true)
        return
    end
    self.redrawing = true
    self.after(0, function()
        self.redrawing = false
        if self.frame:IsShown() then
            self:Render(true)
        end
    end)
end

function JournalWindow:Select(index)
    self.tab = index
    self.store[JournalWindow.TAB_KEY] = index
    self:Render()
end

function JournalWindow:Open()
    if not self.frame then
        ns.JournalFrame.Build(self)
    end
    self.frame:Show()
    self:Render()
end

function JournalWindow:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Open()
    end
end

ns.Commands.Register("journal", L.CMD_JOURNAL, function()
    if not (ns.journalWindow and ns.castLog and ns.castLog.char) then
        ns.Print(L.STATUS_NOT_READY)
        return
    end
    ns.journalWindow:Open()
end)
