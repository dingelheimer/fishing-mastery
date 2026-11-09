-- Saves every finished attempt as a cast record with its context and loot, keeps sessions and
-- totals, detects skill-ups, packs the open day into chunks, and runs the load check in steps
-- after login. Connects
-- Tracker (attempts), Context, Loot, Items, Records, Session, History, and Totals.
local _, ns = ...

local type, setmetatable, ipairs, HUGE = type, setmetatable, ipairs, math.huge
local isSecret = issecretvalue or function()
    return false
end

local Context, Loot, Records, Session = ns.Context, ns.Loot, ns.Records, ns.Session
local History, Totals = ns.History, ns.Totals

local CastLog = {}
CastLog.__index = CastLog
ns.CastLog = CastLog

-- Adds the history tables to a character entry: casts (open day), days (packed chunks),
-- quarantine, subzones, sessions, and totals.
function CastLog.Prepare(char)
    for _, name in ipairs({ "casts", "days", "quarantine", "subzones", "sessions" }) do
        if type(char[name]) ~= "table" then
            char[name] = {}
        end
    end
    char.totals = Totals.Repair(char.totals)
    return char
end

-- Counts the totals from the chunks the check decodes; at the end the open casts are added and
-- the new totals replace char.totals. Live casts during the check land in the open casts (or in
-- a chunk packed later and still checked), so none is lost or counted twice.
local function addRebuild(char, check)
    local totals = Totals.New()
    check.onCasts = function(casts)
        for _, cast in ipairs(casts) do
            Totals.Add(totals, cast)
        end
    end
    check.onRestart = function()
        totals = Totals.New()
    end
    return function()
        for _, cast in ipairs(char.casts) do
            Totals.Add(totals, cast)
        end
        char.totals = totals
    end
end

-- Runs the load check of char in steps of History.CHECK_CHUNKS, one step per after(0, fn) call
-- (all at once without after). With rebuild, the same steps count the totals again (one decode
-- for both). onDone(check) runs at the end; with clock() (GetTimePreciseSec) the check also
-- sums the step times (seconds) and keeps the longest step (longest). Returns the check state.
function CastLog.RunCheck(char, now, after, clock, onDone, rebuild)
    local check = History.NewCheck(char, now)
    check.seconds, check.longest, check.steps = 0, 0, 0
    local finishRebuild = rebuild and addRebuild(char, check)
    local function step()
        local started = clock and clock()
        local done = History.CheckStep(char, check, not after and HUGE or nil)
        check.steps = check.steps + 1
        if started then
            local spent = clock() - started
            check.seconds = check.seconds + spent
            check.longest = spent > check.longest and spent or check.longest
        end
        if not done then
            after(0, step)
            return
        end
        check.done = true
        if finishRebuild then
            finishRebuild()
        end
        if onDone then
            onDone(check)
        end
    end
    step()
    return check
end

-- deps: { env, bus, char (nil when the character is unknown), serverTime(), report(entries),
-- settings (db.settings), remind(), after(seconds, fn) }. report gets the quarantine entries
-- the load check found that were not reported before; remind runs when a session reaches
-- another 2 hours. With after, the load check runs in steps after login and a timer ends an idle
-- session on time (listeners from OnSessionEnd).
function CastLog.Start(deps)
    local env, char = deps.env, deps.char
    local self = setmetatable({
        env = env,
        char = char and CastLog.Prepare(char) or nil,
        serverTime = deps.serverTime,
        items = ns.Items.New(env),
        settings = deps.settings or {},
        remind = deps.remind,
        after = deps.after,
        endListeners = {},
        idleFor = nil, -- the session table the idle timer watches
        idleLast = nil, -- its last cast when the timer was set
    }, CastLog)
    if self.char then
        local rank, _, cap = Context.Fishing(env)
        if type(rank) == "number" then
            self.char.fishingRank = rank
        end
        self.char.fishingMax = cap or self.char.fishingMax
        local owner = self.char
        self.counting = not Totals.Current(owner.totals)
        self.check = CastLog.RunCheck(owner, self.serverTime(), deps.after, nil, function()
            self.counting = false
            local unreported = History.TakeUnreported(owner)
            if #unreported > 0 and deps.report then
                deps.report(unreported)
            end
        end, self.counting)
    end

    local bus = deps.bus
    bus:On("SKILL_LINES_CHANGED", function()
        self:OnSkillLines()
    end)
    bus:On("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
        self.items:OnLoaded(itemID, success)
    end)
    bus:On("PLAYER_ENTERING_WORLD", function(_, _, isReloadingUi)
        if self.char then
            Session.Login(
                self.char,
                self.serverTime(),
                not isSecret(isReloadingUi) and isReloadingUi
            )
            self:WatchIdle()
        end
    end)
    bus:On("PLAYER_LOGOUT", function()
        if self.char then
            Session.Logout(self.char, self.serverTime())
            History.Pack(self.char)
        end
    end)
    return self
end

-- Context and loot readers handed to Tracker.
function CastLog:Context()
    return Context.Read(self.env)
end

function CastLog:Loot()
    return Loot.Read(self.env)
end

-- Tracker's onAttempt: builds, saves, and counts one cast. Returns the saved cast.
function CastLog:OnAttempt(record)
    local char = self.char
    if not char then
        return nil
    end
    local cast = Records.Build(char, record, self.serverTime())
    for _, item in ipairs(cast.loot or {}) do
        self.items:Fill(item)
    end
    History.PackIfNewDay(char, cast.t)
    char.casts[#char.casts + 1] = cast
    local session = Session.Add(char, cast, Totals.cap)
    Totals.Add(char.totals, cast)
    if self.remind and ns.Backup.ShouldRemind(self.settings, session) then
        self.remind()
    end
    self:WatchIdle()
    return cast
end

-- fn(session) runs when an open session ends after IDLE seconds without a cast or by the HUD's
-- stop button (not at logout).
function CastLog:OnSessionEnd(fn)
    self.endListeners[#self.endListeners + 1] = fn
end

-- One timer per new last cast: IDLE seconds after it, the session ends and the listeners run.
-- A cast in between moves the watch to the new last cast.
function CastLog:WatchIdle()
    local session = self.char and Session.Current(self.char)
    if not self.after or not session then
        return
    end
    if self.idleFor == session and self.idleLast == session.last then
        return
    end
    self.idleFor, self.idleLast = session, session.last
    local wait = Session.IDLE - (self.serverTime() - session.last) + 1
    self.after(wait > 0 and wait or 1, function()
        if self.idleFor ~= session or self.idleLast ~= session.last then
            return -- a newer timer watches this session
        end
        self.idleFor, self.idleLast = nil, nil
        Session.Expire(self.char, self.serverTime())
        if session.ended and session.endReason == "idle" then
            for _, fn in ipairs(self.endListeners) do
                fn(session)
            end
        else
            self:WatchIdle()
        end
    end)
end

function CastLog:OnSkillLines()
    if not self.char then
        return
    end
    local rank, _, cap = Context.Fishing(self.env)
    if type(rank) == "number" then
        Session.SkillChanged(self.char, rank, self.serverTime())
    end
    self.char.fishingMax = cap or self.char.fishingMax
end

-- Replaces the totals with a count from the history. Returns the totals and whether they equal
-- the live totals they replace (always false while the count after login is still running), or
-- nil.
function CastLog:Rebuild()
    if not self.char then
        return nil
    end
    local live = self.char.totals
    local totals = Totals.Rebuild(self.char)
    self.char.totals = totals
    return totals, Totals.Equal(live, totals)
end

-- True while the totals are being counted from the history after login (schema 2 update).
function CastLog:Counting()
    return self.counting == true
end

-- Ends the open session now (the HUD's stop button) and runs the end listeners. Returns true when
-- a session was open; the next cast starts a new one.
function CastLog:StopSession()
    if not self.char then
        return false
    end
    local session = Session.Stop(self.char, self.serverTime())
    if not session then
        return false
    end
    self.idleFor, self.idleLast = nil, nil
    for _, fn in ipairs(self.endListeners) do
        fn(session)
    end
    return true
end

-- The open session (after the idle check), or nil.
function CastLog:Session()
    if not self.char then
        return nil
    end
    return Session.Expire(self.char, self.serverTime())
end
