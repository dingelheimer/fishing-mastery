-- Pure logic: SavedVariables schema setup and migrations for FishingMasteryProbeDB.
local _, ns = ...

local type, tonumber = type, tonumber

local Db = {}
ns.Db = Db

Db.SCHEMA_VERSION = 1

-- MIGRATIONS[v] upgrades a table from schema v to v + 1.
local MIGRATIONS = {}

local function ensureDefaults(db)
    db.log = type(db.log) == "table" and db.log or {}
    db.log.entries = type(db.log.entries) == "table" and db.log.entries or {}
    db.log.dropped = db.log.dropped or 0
    db.progress = type(db.progress) == "table" and db.progress or {}
    db.progress.step = db.progress.step or "S0"
end

-- Returns a valid database table, reusing saved data when present.
function Db.Init(saved)
    local db = type(saved) == "table" and saved or {}
    local version = db.schemaVersion or Db.SCHEMA_VERSION
    while version < Db.SCHEMA_VERSION do
        MIGRATIONS[version](db)
        version = version + 1
    end
    db.schemaVersion = version
    ensureDefaults(db)
    return db
end

-- Q22 persistence marker: reads the previous session's marker, then writes a new one with an
-- increased session counter. Returns { found, previousSessionId, sessions }.
function Db.Mark(db, sessionId)
    local previous = type(db.marker) == "table" and db.marker or {}
    local sessions = (tonumber(previous.sessions) or 0) + 1
    db.marker = { sessions = sessions, lastSessionId = sessionId }
    return {
        found = previous.lastSessionId ~= nil,
        previousSessionId = previous.lastSessionId,
        sessions = sessions,
    }
end
