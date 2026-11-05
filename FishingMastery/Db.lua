-- Pure logic: schema setup, migrations, repair, and the migration snapshot for FishingMasteryDB
-- (account-wide) and FishingMasteryCharDB (per character, UI layout only).
local _, ns = ...

local type, pairs, ipairs, pcall, tonumber, tostring =
    type, pairs, ipairs, pcall, tonumber, tostring

local Db = {}
ns.Db = Db

Db.SCHEMA_VERSION = 2
Db.CHAR_SCHEMA_VERSION = 1

-- MIGRATIONS[v] upgrades the database from schema v to v + 1:
-- { tables = { "chars", ... }, run = function(db) end }. `tables` names the top-level tables
-- the step changes; they are copied into the migration snapshot before the first step runs.
Db.MIGRATIONS = {
    -- Schema 2 (Story 3.2): the totals gain zone, hour, skill, item, bite, and active time
    -- aggregates. The step only marks every character's totals as stale; CastLog counts them
    -- again in steps after login (with the load check), so loading stays fast.
    [1] = {
        tables = { "chars" },
        run = function(db)
            for _, char in pairs(type(db.chars) == "table" and db.chars or {}) do
                if type(char) == "table" and type(char.totals) == "table" then
                    char.totals.version = nil
                end
            end
        end,
    },
}

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(child, seen)
    end
    return copy
end
Db.DeepCopy = deepCopy

local function isTable(value)
    return type(value) == "table"
end

-- Adds missing top-level tables and drops character entries that are not tables.
-- Returns the number of repaired fields.
local function repair(db)
    local repaired = 0
    for _, name in ipairs({ "chars", "settings" }) do
        if not isTable(db[name]) then
            db[name] = {}
            repaired = repaired + 1
        end
    end
    for key, entry in pairs(db.chars) do
        if type(key) ~= "string" or not isTable(entry) then
            db.chars[key] = nil
            repaired = repaired + 1
        end
    end
    if db.migrationSnapshot ~= nil and not isTable(db.migrationSnapshot) then
        db.migrationSnapshot = nil
        repaired = repaired + 1
    end
    return repaired
end

-- Copies every table the pending steps touch, so a failed or buggy migration can be undone.
local function takeSnapshot(db, from, to, migrations, now)
    local names, tables = {}, {}
    for version = from, to - 1 do
        for _, name in ipairs(migrations[version].tables or {}) do
            if not names[name] then
                names[name] = true
                tables[name] = deepCopy(db[name])
            end
        end
    end
    return { fromVersion = from, toVersion = to, createdAt = now, tables = tables }
end

local function restore(db, snapshot)
    for name, copy in pairs(snapshot.tables) do
        db[name] = deepCopy(copy)
    end
    db.schemaVersion = snapshot.fromVersion
end

-- Returns a valid database plus load info, reusing saved data when present.
-- opts.migrations, opts.schemaVersion: overrides for tests. opts.now: server time.
-- info: { fresh, migratedFrom, migrationError, newer, snapshotCreated, repaired }.
function Db.Init(saved, opts)
    opts = opts or {}
    local migrations = opts.migrations or Db.MIGRATIONS
    local target = opts.schemaVersion or Db.SCHEMA_VERSION
    local info = { fresh = not isTable(saved) }
    local db = isTable(saved) and saved or {}
    local version = tonumber(db.schemaVersion) or target

    if version > target then
        info.newer = version
    elseif version < target then
        for step = version, target - 1 do
            if not isTable(migrations[step]) or type(migrations[step].run) ~= "function" then
                info.migrationError = "missing migration " .. step
                break
            end
        end
        if not info.migrationError then
            local snapshot = takeSnapshot(db, version, target, migrations, opts.now)
            db.migrationSnapshot = snapshot
            info.snapshotCreated = true
            for step = version, target - 1 do
                local ok, err = pcall(migrations[step].run, db)
                if not ok then
                    info.migrationError = tostring(err)
                    restore(db, snapshot)
                    break
                end
                db.schemaVersion = step + 1
            end
            if not info.migrationError then
                info.migratedFrom = version
            end
        end
    end

    if not info.migrationError and not info.newer then
        db.schemaVersion = target
    end
    info.repaired = repair(db)
    return db, info
end

-- Called at PLAYER_LOGIN: a snapshot from an earlier load is dropped once a later login has
-- loaded without Lua errors. Returns true when the snapshot was removed.
function Db.ConfirmLogin(db, info, errors)
    if db.migrationSnapshot and not info.snapshotCreated and errors == 0 then
        db.migrationSnapshot = nil
        return true
    end
    return false
end

-- Per-character variable: UI layout only.
function Db.InitChar(saved)
    local db = isTable(saved) and saved or {}
    db.schemaVersion = tonumber(db.schemaVersion) or Db.CHAR_SCHEMA_VERSION
    if not isTable(db.ui) then
        db.ui = {}
    end
    return db
end
