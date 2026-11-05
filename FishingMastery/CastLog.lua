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

-- Runs the load check of char in steps of History.CHECK_CHUNKS, one step per after(0, fn) call
-- (all at once without after). onDone(check) runs at the end; with clock() (GetTimePreciseSec)
-- the check also sums the step times (seconds) and keeps the longest step (longest).
-- Returns the check state.
function CastLog.RunCheck(char, now, after, clock, onDone)
    local check = History.NewCheck(char, now)
    check.seconds, check.longest, check.steps = 0, 0, 0
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
-- another 2 hours. With after, the load check runs in steps after login.
function CastLog.Start(deps)
    local env, char = deps.env, deps.char
    local self = setmetatable({
        env = env,
        char = char and CastLog.Prepare(char) or nil,
        serverTime = deps.serverTime,
        items = ns.Items.New(env),
        settings = deps.settings or {},
        remind = deps.remind,
    }, CastLog)
    if self.char then
        local rank = Context.Fishing(env)
        if type(rank) == "number" then
            self.char.fishingRank = rank
        end
        local owner = self.char
        self.check = CastLog.RunCheck(owner, self.serverTime(), deps.after, nil, function()
            local unreported = History.TakeUnreported(owner)
            if #unreported > 0 and deps.report then
                deps.report(unreported)
            end
        end)
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
    local session = Session.Add(char, cast)
    Totals.Add(char.totals, cast)
    if self.remind and ns.Backup.ShouldRemind(self.settings, session) then
        self.remind()
    end
    return cast
end

function CastLog:OnSkillLines()
    if not self.char then
        return
    end
    local rank = Context.Fishing(self.env)
    if type(rank) == "number" then
        Session.SkillChanged(self.char, rank, self.serverTime())
    end
end

-- Replaces the totals with a count from the history. Returns the totals, or nil.
function CastLog:Rebuild()
    if not self.char then
        return nil
    end
    self.char.totals = Totals.Rebuild(self.char)
    return self.char.totals
end

-- The open session (after the idle check), or nil.
function CastLog:Session()
    if not self.char then
        return nil
    end
    return Session.Expire(self.char, self.serverTime())
end
