-- Scope helpers of the Statistics page (StatsWindow methods, Story 9.3): the characters of the
-- chosen scope by key, their StatsModel.Overview, the saved session count, and the logged-in
-- character's Fishing skill. Loaded after StatsWindow.lua.
local _, ns = ...

local type, ipairs = type, ipairs
local Context = ns.Context
local StatsWindow = ns.StatsWindow

-- Characters of the chosen scope by key (StatsModel.Overview input).
function StatsWindow:CharMap()
    local chars = type(self.db.chars) == "table" and self.db.chars or {}
    if self.scope == "char" then
        return { [self.charKey] = chars[self.charKey] }
    end
    return chars
end

-- StatsModel.Overview of the chosen scope (Overview numbers, records, calendar days).
function StatsWindow:OverviewModel()
    return ns.StatsModel.Overview({
        chars = self:CharMap(),
        current = self.charKey,
        now = self.serverTime(),
        thresholds = self.thresholds,
    })
end

-- Saved sessions of the chosen scope.
function StatsWindow:SessionCount()
    local count = 0
    for _, entry in ipairs(self:Chars()) do
        if type(entry.sessions) == "table" then
            count = count + #entry.sessions
        end
    end
    return count
end

-- Fishing skill of the logged-in character: { rank, max, modifier, gained }, live from the
-- client, else the saved rank and cap.
function StatsWindow:Skill()
    local char = self.castLog.char or {}
    local rank, modifier, max = Context.Fishing(self.env)
    rank = rank or char.fishingRank
    return {
        rank = rank,
        max = max or char.fishingMax,
        modifier = modifier,
        gained = ns.SkillModel.Gained(char.sessions, rank),
    }
end
