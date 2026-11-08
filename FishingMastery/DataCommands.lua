-- Data commands: /fm backup, /fm export, /fm import, /fm contribute, and /fm reminder. The
-- windows are created on first use.
local _, ns = ...

local format, match, lower, tonumber, tostring, ipairs, type, select, _G =
    string.format, string.match, string.lower, tonumber, tostring, ipairs, type, select, _G
local L = ns.L

local DataCommands = {}
ns.DataCommands = DataCommands

local function textWindow()
    ns.textWindow = ns.textWindow or ns.TextWindow.Create(_G, ns.charDb.ui)
    return ns.textWindow
end

local function confirm()
    ns.confirm = ns.confirm or ns.Confirm.Create(_G)
    return ns.confirm
end

-- A day number as a date (the client's date function), or the number itself.
function DataCommands.FormatDay(day)
    local date = _G.date
    if type(date) == "function" then
        return date("!%Y-%m-%d", day * 86400)
    end
    return tostring(day)
end

local function ready()
    if not ns.db or not ns.charDb then
        ns.Print(L.STATUS_NOT_READY)
        return false
    end
    return true
end

local function backup(rest)
    local action, number = match(rest, "^(%S*)%s*(%S*)")
    action = lower(action or "")
    if action == "" or action == "list" then
        local list = ns.Backup.List(ns.db)
        if #list == 0 then
            ns.Print(L.BACKUP_NONE)
        end
        for i, item in ipairs(list) do
            ns.Print(format(L.BACKUP_LINE, i, DataCommands.FormatDay(item.day), item.chars))
        end
        return
    end
    local n = tonumber(number)
    if action ~= "restore" or not n or not ns.db.backups or not ns.db.backups[n] then
        ns.Print(L.BACKUP_USAGE)
        return
    end
    local day = DataCommands.FormatDay(ns.db.backups[n].day)
    confirm():Ask(format(L.BACKUP_QUESTION, n, day), L.BUTTON_RESTORE, function()
        ns.Backup.Restore(ns.db, n)
        ns.Print(format(L.BACKUP_RESTORED, n, day))
    end)
end

local function export(rest)
    local scope = lower(rest or "") == "all" and "all" or "char"
    if scope == "char" and not ns.charKey then
        ns.Print(L.NO_CHARACTER)
        return
    end
    local pages = ns.Export.Build(ns.db, scope, ns.charKey)
    local hint = scope == "all" and L.EXPORT_HINT_ALL or L.EXPORT_HINT_CHAR
    textWindow():Open(L.EXPORT_TITLE, hint, pages)
    ns.Print(format(L.EXPORT_PRINT, #pages))
end

-- Validates and merges one pasted export page. Returns the summary, or nil and the reason.
function DataCommands.Import(text)
    local staged, err = ns.Import.Parse(text)
    if not staged then
        return nil, err
    end
    if staged.scope == "char" and not ns.charKey then
        return nil, L.NO_CHARACTER
    end
    return ns.Import.Merge(ns.db, staged, ns.charKey, ns.CastLog.Prepare)
end

local function import()
    textWindow():OpenInput(L.IMPORT_TITLE, L.IMPORT_HINT, function(text)
        local summary, err = DataCommands.Import(text)
        if summary then
            ns.Print(format(L.IMPORT_DONE, summary.days, summary.casts, summary.skipped))
        else
            ns.Print(format(L.IMPORT_FAILED, err))
        end
    end)
end

-- The account token of the contribution export: made on first use, replaced with "new-token".
function DataCommands.Token(db, renew, random)
    local token = ns.Contribute.ValidToken(db.contributeToken)
    if renew or not token then
        token = ns.Contribute.NewToken(random)
        db.contributeToken = token
    end
    return token
end

local function contribute(rest)
    local renew = lower(rest or "") == "new-token"
    local token = DataCommands.Token(ns.db, renew, math.random)
    local build = _G.GetBuildInfo and select(2, _G.GetBuildInfo()) or nil
    local version = ns.VERSION == L.VERSION_DEV and "dev" or ns.VERSION
    local text, lines = ns.Contribute.Build(ns.db.chars, ns.area, {
        token = token,
        version = version,
        build = build,
    })
    textWindow():Open(L.CONTRIBUTE_TITLE, L.CONTRIBUTE_HINT, { text })
    ns.Print(format(renew and L.CONTRIBUTE_NEW_TOKEN or L.CONTRIBUTE_PRINT, lines))
end

local function reminder(rest)
    local value = lower(rest or "")
    if value == "on" or value == "off" then
        ns.db.settings.reloadReminder = value == "on"
    end
    ns.Print(ns.db.settings.reloadReminder == false and L.REMINDER_OFF or L.REMINDER_ON)
end

local function guarded(fn)
    return function(rest)
        if ready() then
            fn(rest or "")
        end
    end
end

ns.Commands.Register("backup", L.CMD_BACKUP, guarded(backup))
ns.Commands.Register("export", L.CMD_EXPORT, guarded(export))
ns.Commands.Register("import", L.CMD_IMPORT, guarded(import))
ns.Commands.Register("contribute", L.CMD_CONTRIBUTE, guarded(contribute))
ns.Commands.Register("reminder", L.CMD_REMINDER, guarded(reminder))
