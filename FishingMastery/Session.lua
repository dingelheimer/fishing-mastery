-- Pure logic: fishing sessions per character in char.sessions. A session starts with the first
-- cast, ends 15 minutes after the last cast or at logout, and survives a /reload. Times are
-- server times (seconds). skillStart is the fishing rank at the first cast, skill the latest
-- known rank; skill - skillStart is the number of skill-ups. active is the sum of the gaps
-- between casts, each capped at the active cap (Statistics Methods); Session.Active adds the
-- time since the last cast. lastItem and lastBite describe the latest catch.
local _, ns = ...

local type, ipairs = type, ipairs

local Session = {}
ns.Session = Session

Session.IDLE = 900 -- seconds without a cast that end a session
Session.ACTIVE_CAP = 60 -- default cap; CastLog passes Totals.ACTIVE_CAP

-- The open session (the last one, when it has no end), or nil.
function Session.Current(char)
    local sessions = char.sessions
    local last = sessions[#sessions]
    if last and not last.ended then
        return last
    end
    return nil
end

-- Ends the open session at its last cast when it has been idle for IDLE seconds.
function Session.Expire(char, now)
    local current = Session.Current(char)
    if current and now - current.last >= Session.IDLE then
        current.ended = current.last
        current.endReason = "idle"
    end
    return Session.Current(char)
end

local function higher(a, b)
    if type(a) ~= "number" then
        return b
    end
    if type(b) ~= "number" or a >= b then
        return a
    end
    return b
end

local function addZone(session, map)
    if type(map) ~= "number" then
        return
    end
    for _, known in ipairs(session.zones) do
        if known == map then
            return
        end
    end
    session.zones[#session.zones + 1] = map
end

local function min(a, b)
    return a < b and a or b
end

-- Counts a saved cast into the open session, starting a new one when needed. cap: active cap in
-- seconds (default ACTIVE_CAP).
function Session.Add(char, cast, cap)
    local t = cast.t or 0
    local current = Session.Expire(char, t)
    if not current then
        current = {
            start = t,
            last = t,
            casts = 0,
            catches = 0,
            counts = {},
            zones = {},
            skillStart = cast.rank,
            active = 0,
        }
        char.sessions[#char.sessions + 1] = current
    elseif t > current.last then
        -- Sessions from before Story 3.5 start their active time at the next cast.
        current.active = (current.active or 0) + min(t - current.last, cap or Session.ACTIVE_CAP)
    end
    current.casts = current.casts + 1
    if cast.out == "catch" then
        current.catches = current.catches + 1
        local first = type(cast.loot) == "table" and cast.loot[1]
        current.lastItem = first and first.id or nil
        current.lastBite = cast.bite
    end
    current.counts[cast.out] = (current.counts[cast.out] or 0) + 1
    if t > current.last then
        current.last = t
    end
    addZone(current, cast.map)
    current.skillStart = current.skillStart or cast.rank
    -- A skill-up fires before the catch is saved, so the known rank can be above the cast's.
    current.skill = higher(higher(current.skill, cast.rank), char.fishingRank)
    return current
end

-- The fishing rank read on SKILL_LINES_CHANGED. Returns true when it went up.
function Session.SkillChanged(char, rank, now)
    local previous = char.fishingRank
    char.fishingRank = rank
    local current = Session.Expire(char, now)
    if current then
        current.skill = higher(current.skill, rank)
    end
    return type(previous) == "number" and rank > previous
end

-- Active seconds of a session at server time now: the capped gaps plus the time since the last
-- cast (capped; the session is only open within IDLE of it).
function Session.Active(session, now, cap)
    local since = (now or session.last) - session.last
    if since < 0 then
        since = 0
    end
    return (session.active or 0) + min(since, cap or Session.ACTIVE_CAP)
end

-- Skill-ups in a session.
function Session.SkillUps(session)
    if type(session.skillStart) ~= "number" or type(session.skill) ~= "number" then
        return 0
    end
    return session.skill - session.skillStart
end

-- PLAYER_LOGOUT (also fired by /reload): ends the open session now.
function Session.Logout(char, now)
    local current = Session.Current(char)
    if current then
        current.ended = now
        current.endReason = "logout"
    end
end

-- PLAYER_ENTERING_WORLD: after a /reload, reopens the session the reload's logout ended. A
-- session left open by a crash is ended at its last cast once it is idle.
function Session.Login(char, now, isReload)
    local sessions = char.sessions
    local last = sessions[#sessions]
    if isReload and last and last.endReason == "logout" and now - last.last < Session.IDLE then
        last.ended = nil
        last.endReason = nil
    end
    Session.Expire(char, now)
end
