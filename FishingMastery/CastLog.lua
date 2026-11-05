-- Saves every finished attempt as a cast record with its context and loot, keeps sessions and
-- totals, detects skill-ups, packs the open day into chunks, and runs the load check. Connects
-- Tracker (attempts), Context, Loot, Items, Records, Session, History, and Totals.
local _, ns = ...

local type, setmetatable, ipairs = type, setmetatable, ipairs
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

-- deps: { env, bus, char (nil when the character is unknown), serverTime(), report(entries),
-- settings (db.settings), remind() }. report gets the quarantine entries found by the load check
-- that were not reported before; remind runs when a session reaches another 2 hours.
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
        self.check = History.Check(self.char, self.serverTime())
        local unreported = History.TakeUnreported(self.char)
        if #unreported > 0 and deps.report then
            deps.report(unreported)
        end
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
