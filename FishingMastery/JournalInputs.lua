-- Inputs of the Journal table builders (JournalWindow methods, Story 9.5 moved them here from
-- JournalWindow.lua): item and place names, season and month helpers, recipes, known spells,
-- stock in bags and bank, the own share of a fish in an area, and date formats. Loaded after
-- JournalWindow.lua.
local _, ns = ...

local type, tostring = type, tostring
local Context = ns.Context
local JournalWindow = ns.JournalWindow

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
    local now = Context.Call(env, "GetServerTime")
    local offset = ns.Season.Offset(Context.Call(env, "GetGameTime"), now)
    return {
        hourOffset = offset,
        inSeason = function(season)
            if type(now) ~= "number" then
                return nil -- no server time
            end
            return ns.Season.InSeason(season, now, offset)
        end,
        monthName = function(month)
            local date = env.date
            local days = JournalWindow.DAYS_BEFORE[month]
            return type(date) == "function" and date("!%b", days * 86400) or tostring(month)
        end,
        info = function(id)
            return self:ItemInfo(id)
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
