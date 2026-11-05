-- The stats window (/fm stats): a movable window (position saved per character) with 8 tabs.
-- Overview, Fish, and Zones read the live aggregates only (StatsModel views, table builders);
-- the other tabs follow in later stories. Built on first open (StatsFrame.lua); only the shown
-- tab is drawn.
-- Item names that load later redraw the tab once per frame. Unnamed, insecure frames only.
local _, ns = ...

local setmetatable, type, ipairs, pairs, floor, concat, select, format, tostring =
    setmetatable, type, ipairs, pairs, math.floor, table.concat, select, string.format, tostring
local L, Context = ns.L, ns.Context
local StatsModel, StatsTables, ZoneTable, OverviewTable =
    ns.StatsModel, ns.StatsTables, ns.ZoneTable, ns.OverviewTable

local StatsWindow = {}
StatsWindow.__index = StatsWindow
ns.StatsWindow = StatsWindow

StatsWindow.TABS =
    { "overview", "fish", "zones", "failures", "bites", "sessions", "skill", "compare" }
StatsWindow.FILLED = { overview = true, fish = true, zones = true }
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
        sort = { key = "n", descending = true },
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
        hourOffset = offset,
        thresholds = self.thresholds,
        quality = StatsTables.QUALITIES[self.quality],
        sort = self.sort,
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
    return ""
end

local function draw(self, keepScroll)
    local name = StatsWindow.TABS[self.tab]
    local input = inputs(self)
    local view = nil
    if name == "overview" then
        local model = StatsModel.Overview({
            chars = self.db.chars,
            current = self.charKey,
            now = self.serverTime(),
            thresholds = self.thresholds,
        })
        self.overviewText:SetText(concat(OverviewTable.Lines(model, input), "\n"))
        self.characters:SetRows(OverviewTable.Rows(model, input), keepScroll)
    elseif name == "fish" or name == "zones" then
        view = StatsModel.View(self:Chars())
        if name == "fish" then
            self.fish:SetRows(StatsTables.Fish(view, input), keepScroll)
        else
            self.zones:SetRows(ZoneTable.Rows(view, input), keepScroll)
        end
    end
    self.status:SetText(statusText(self, name, view))
    self.scopeButton:SetText(L["STATS_SCOPE_" .. self.scope])
    self.scopeButton:SetShown(name == "fish" or name == "zones")
    local quality = input.quality
    self.qualityButton:SetText(
        quality and format(L.STATS_QUALITY, L["STATS_QUALITY_" .. quality]) or L.STATS_QUALITY_ALL
    )
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

-- Fish header click: the same column flips the order; a new one starts with the largest values
-- first (names and zones A-Z).
function StatsWindow:SortBy(key)
    local sort = self.sort
    if sort.key == key then
        sort.descending = not sort.descending
    else
        sort.key, sort.descending = key, key ~= "name" and key ~= "best"
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
