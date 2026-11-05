-- Pure logic: append-only log with a hard entry cap. Clock and sanitizer are injected.
local _, ns = ...

local setmetatable, format, tremove = setmetatable, string.format, table.remove

local Logger = {}
Logger.__index = Logger
ns.Logger = Logger

Logger.DEFAULT_CAP = 20000

-- Builds a session ID from server time and a random number; contains no player data.
function Logger.MakeSessionId(serverTime, randomValue)
    return format("%08x-%04x", serverTime, randomValue)
end

-- store: the persisted log table ({ entries, dropped, cap, sessionId, probeVersion }).
-- deps.now: returns the entry time (GetTimePreciseSec in game).
-- deps.sanitize: turns entry data into plain data (Serializer.Sanitize in game).
function Logger.New(store, deps)
    store.entries = store.entries or {}
    store.dropped = store.dropped or 0
    store.cap = store.cap or Logger.DEFAULT_CAP
    return setmetatable({
        store = store,
        now = deps.now,
        sanitize = deps.sanitize,
        step = "S0",
    }, Logger)
end

function Logger:SetStep(step)
    self.step = step
end

-- Appends { t, step, q, kind, data } and drops the oldest entries above the cap.
-- step overrides the current step for this entry (the login snapshot always logs as S0).
function Logger:Log(kind, data, q, step)
    local store = self.store
    local entries = store.entries
    local entry = {
        t = self.now(),
        step = step or self.step,
        q = q,
        kind = kind,
        data = self.sanitize(data),
    }
    entries[#entries + 1] = entry
    while #entries > store.cap do
        tremove(entries, 1)
        store.dropped = store.dropped + 1
    end
    return entry
end

-- Records the current session in the header and as a "session_start" entry.
function Logger:StartSession(sessionId, probeVersion)
    self.store.sessionId = sessionId
    self.store.probeVersion = probeVersion
    return self:Log("session_start", { sessionId = sessionId, probeVersion = probeVersion })
end

function Logger:Count()
    return #self.store.entries
end

function Logger:Dropped()
    return self.store.dropped
end
