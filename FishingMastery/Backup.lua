-- Pure logic: rolling snapshots of the small, changing parts (settings and every character's
-- totals) in db.backups, newest first, one per day for the last 3 days. History chunks are
-- immutable and never copied.
local _, ns = ...

local type, pairs, ipairs, tremove, tinsert = type, pairs, ipairs, table.remove, table.insert

local DeepCopy = ns.Db.DeepCopy

local Backup = {}
ns.Backup = Backup

Backup.KEEP = 3

local function list(db)
    if type(db.backups) ~= "table" then
        db.backups = {}
    end
    return db.backups
end

-- Takes today's snapshot unless one exists. Returns true when a snapshot was taken.
function Backup.Take(db, day, now)
    local backups = list(db)
    if backups[1] and backups[1].day == day then
        return false
    end
    local totals = {}
    for guid, entry in pairs(db.chars) do
        if type(entry.totals) == "table" then
            totals[guid] = DeepCopy(entry.totals)
        end
    end
    tinsert(backups, 1, { day = day, at = now, settings = DeepCopy(db.settings), totals = totals })
    while #backups > Backup.KEEP do
        tremove(backups)
    end
    return true
end

-- Snapshots newest first: { day, at, chars } per entry.
function Backup.List(db)
    local result = {}
    for i, snapshot in ipairs(list(db)) do
        local chars = 0
        for _ in pairs(snapshot.totals or {}) do
            chars = chars + 1
        end
        result[i] = { day = snapshot.day, at = snapshot.at, chars = chars }
    end
    return result
end

-- Puts snapshot n (1 = newest) back: settings and the totals of characters that still exist.
-- Returns true, or false when there is no such snapshot.
function Backup.Restore(db, n)
    local snapshot = list(db)[n]
    if type(snapshot) ~= "table" then
        return false
    end
    db.settings = DeepCopy(snapshot.settings or {})
    for guid, totals in pairs(snapshot.totals or {}) do
        local entry = db.chars[guid]
        if entry then
            entry.totals = DeepCopy(totals)
        end
    end
    return true
end

-- Reload reminder: true once per full 2 hours of fishing in a session, unless switched off in
-- settings (reloadReminder = false). Counts the reminders in session.reminders.
Backup.REMINDER_EVERY = 7200

function Backup.ShouldRemind(settings, session)
    if settings.reloadReminder == false or not session then
        return false
    end
    local blocks = (session.last - session.start) / Backup.REMINDER_EVERY
    if blocks >= (session.reminders or 0) + 1 then
        session.reminders = (session.reminders or 0) + 1
        return true
    end
    return false
end
