-- The stats window (/fm stats): a movable window (position saved per character) with 8 tabs.
-- Each filled tab (StatsTabs.lua, FailureTabs.lua) reads the live aggregates and session records
-- only; Skill and Compare follow in a later story. Built on first open (StatsFrame.lua); only the
-- shown tab is drawn. Item names that load later redraw the tab once per frame. Unnamed, insecure
-- frames only.
local _, ns = ...

local setmetatable, type, ipairs, pairs, floor, select, format, tostring =
    setmetatable, type, ipairs, pairs, math.floor, select, string.format, tostring
local L, Context = ns.L, ns.Context
local StatsTables = ns.StatsTables

local StatsWindow = {}
StatsWindow.__index = StatsWindow
ns.StatsWindow = StatsWindow

StatsWindow.TABS =
    { "overview", "fish", "zones", "failures", "bites", "sessions", "skill", "compare" }
-- Columns sorted A-Z on their first click, per sortable list; others start with the largest.
StatsWindow.TEXT_KEYS =
    { fish = { name = true, best = true }, sessions = { name = true, zone = true } }
StatsWindow.RECHECK = 1 -- seconds between checks while the history is counted
StatsWindow.QUALITY_HEX = 4 -- C_Item.GetItemQualityColor: hex color

-- deps: { env, castLog, db (FishingMasteryDB), charKey, store (FishingMasteryCharDB.ui),
-- serverTime(), after(seconds, fn) }.
function StatsWindow.Start(deps)
    return setmetatable({
        env = deps.env,
        castLog = deps.castLog,
        db = deps.db,
        charKey = deps.charKey,
        store = deps.store,
        serverTime = deps.serverTime,
        after = deps.after,
        thresholds = ns.Stats.Thresholds(deps.db.settings.thresholds),
        tab = 1,
        scope = "char",
        quality = 0, -- index into StatsTables.QUALITIES; 0 = all
        sorts = {
            fish = { key = "n", descending = true },
            sessions = { key = "start", descending = true },
        },
        biteGroup = 1, -- index into the Bite times groups (1 = all zones)
        waiting = {}, -- item IDs with a load callback
    }, StatsWindow)
end

-- Item data for the tables; an uncached item is requested once and redraws the tab on load.
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
            StatsWindow.QUALITY_HEX,
            Context.Call(self.env, "C_Item.GetItemQualityColor", info.quality)
        )
    end
    return info
end

local function inputs(self)
    local env, names = self.env, {}
    local gameHour = Context.Call(env, "GetGameTime")
    local offset = 0
    if type(gameHour) == "number" then
        offset = (gameHour - floor((self.serverTime() % 86400) / 3600)) % 24
    end
    return {
        info = function(id)
            return itemInfo(self, id)
        end,
        mapName = function(map)
            if names[map] == nil then
                names[map] = Context.MapName(env, map) or false
            end
            return names[map] or nil
        end,
        formatDate = function(t)
            local date = env.date
            return type(date) == "function" and date("%Y-%m-%d", t) or tostring(t)
        end,
        formatTime = function(t)
            local date = env.date
            return type(date) == "function" and date("%Y-%m-%d %H:%M", t) or tostring(t)
        end,
        hourOffset = offset,
        thresholds = self.thresholds,
        quality = StatsTables.QUALITIES[self.quality],
    }
end

-- Character entries of the chosen scope.
function StatsWindow:Chars()
    local chars = type(self.db.chars) == "table" and self.db.chars or {}
    if self.scope == "char" then
        return { chars[self.charKey] }
    end
    local list = {}
    for _, entry in pairs(chars) do
        if type(entry) == "table" then
            list[#list + 1] = entry
        end
    end
    return list
end

local function statusText(self, name, view)
    if self.castLog:Counting() then
        return L.STATS_COUNTING
    end
    if name ~= "overview" and view and view.stale > 0 then
        return format(L.STATS_STALE, view.stale)
    end
    if view and ns.Stats.Count(view.outcomes, "catch") == 0 then
        return L.STATS_EMPTY
    end
    if name == "sessions" and self.sessionCount == 0 then
        return L.STATS_NO_SESSIONS
    end
    return ""
end

local function draw(self, keepScroll)
    local name = StatsWindow.TABS[self.tab]
    local tab = ns.StatsTabs[name]
    local view = tab and tab.draw(self, inputs(self), keepScroll)
    self.status:SetText(statusText(self, name, view))
    self.scopeButton:SetText(L["STATS_SCOPE_" .. self.scope])
    self.scopeButton:SetShown(tab ~= nil and tab.scoped == true)
end

local function recheck(self)
    if not self.after or self.rechecking or not self.castLog:Counting() then
        return
    end
    self.rechecking = true
    self.after(StatsWindow.RECHECK, function()
        self.rechecking = false
        if self.frame:IsShown() then
            self:Render()
        end
    end)
end

-- Draws the shown tab from the current aggregates.
function StatsWindow:Render(keepScroll)
    for i, frame in ipairs(self.panels) do
        frame:SetShown(i == self.tab)
    end
    Context.Call(self.env, "PanelTemplates_SetTab", self.frame, self.tab)
    draw(self, keepScroll)
    recheck(self)
end

-- Redraws once per frame after item data arrived, keeping the scroll position.
function StatsWindow:Redraw()
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

function StatsWindow:Select(index)
    self.tab = index
    self:Render()
end

-- Header click on a sortable list ("fish", "sessions"): the same column flips the order; a new
-- one starts with the largest values first (text columns A-Z).
function StatsWindow:SortBy(list, key)
    local sort = self.sorts[list]
    if sort.key == key then
        sort.descending = not sort.descending
    else
        sort.key, sort.descending = key, not StatsWindow.TEXT_KEYS[list][key]
    end
    self:Render()
end

function StatsWindow:Open()
    if not self.frame then
        ns.StatsFrame.Build(self)
    end
    self.frame:Show()
    self:Render()
end

ns.Commands.Register("stats", L.CMD_STATS, function()
    if not (ns.stats and ns.castLog and ns.castLog.char) then
        ns.Print(L.STATUS_NOT_READY)
        return
    end
    ns.stats:Open()
end)
