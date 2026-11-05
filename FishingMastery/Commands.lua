-- Slash command registry and dispatch for /fm (alias /fishingmastery). Later stories register
-- more commands with Commands.Register.
local _, ns = ...

local format, lower, match, ipairs, pairs, max, floor, tostring =
    string.format, string.lower, string.match, ipairs, pairs, math.max, math.floor, tostring
local L = ns.L

local Commands = { list = {}, byName = {} }
ns.Commands = Commands

Commands.ERRORS_SHOWN = 3

-- visible(): optional; when it returns false the command is left out of the help and treated as
-- unknown (used for the developer commands).
function Commands.Register(name, description, fn, visible)
    local command = { name = name, description = description, fn = fn, visible = visible }
    Commands.list[#Commands.list + 1] = command
    Commands.byName[name] = command
end

-- Runs "/fm <name> <rest>". An empty or unknown name shows the help.
function Commands.Dispatch(message)
    local name, rest = match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    name = lower(name)
    local command = Commands.byName[name]
    if command and command.visible and not command.visible() then
        command = nil
    end
    if not command then
        if name ~= "" then
            ns.Print(format(L.UNKNOWN_COMMAND, name))
        end
        command = Commands.byName.help
    end
    command.fn(rest)
end

local function printErrors()
    local recent = ns.recentErrors or {}
    local count = ns.Guard.errors
    if count == 0 then
        ns.Print(L.ERRORS_NONE)
        return
    end
    local first = max(1, #recent - Commands.ERRORS_SHOWN + 1)
    ns.Print(format(L.ERRORS, count, #recent - first + 1))
    for i = first, #recent do
        ns.Print(format(L.ERROR_LINE, recent[i].where, recent[i].msg))
    end
end

Commands.Register("help", L.CMD_HELP, function()
    ns.Print(format(L.HELP_HEADER, ns.VERSION))
    for _, command in ipairs(Commands.list) do
        if not command.visible or command.visible() then
            ns.Print(format(L.HELP_LINE, command.name, command.description))
        end
    end
    ns.Print(format(L.CHARACTERS, ns.Character.Count(ns.db)))
    printErrors()
end)

Commands.Register("status", L.CMD_STATUS, function()
    local castLog = ns.castLog
    if castLog and castLog:Counting() then
        ns.Print(L.STATUS_COUNTING)
    end
    local session = castLog and castLog:Session()
    if not session then
        ns.Print(castLog and L.STATUS_NONE or L.STATUS_NOT_READY)
        return
    end
    local counts = session.counts
    local minutes = floor((session.last - session.start) / 60)
    ns.Print(format(L.STATUS_HEADER, minutes, session.casts, session.catches))
    ns.Print(
        format(
            L.STATUS_COUNTS,
            counts.getaway or 0,
            counts.early_click or 0,
            counts.timeout or 0,
            counts.cancel or 0,
            counts.invalid_target or 0,
            counts.unknown or 0
        )
    )
    ns.Print(
        format(
            L.STATUS_SKILL,
            tostring(session.skillStart or "-"),
            tostring(session.skill or "-"),
            ns.Session.SkillUps(session)
        )
    )
    local last = ns.tracker and ns.tracker.last
    if last then
        local outcome = L["OUTCOME_" .. last.outcome]
        if last.biteTenths then
            ns.Print(format(L.STATUS_LAST_BITE, outcome, last.biteTenths / 10))
        else
            ns.Print(format(L.STATUS_LAST, outcome))
        end
    end
end)

Commands.Register("rebuild", L.CMD_REBUILD, function()
    local totals, same = nil, false
    if ns.castLog then
        totals, same = ns.castLog:Rebuild()
    end
    if not totals then
        ns.Print(L.STATUS_NOT_READY)
        return
    end
    local casts, catches, days = 0, 0, 0
    for _, day in pairs(totals.days) do
        casts, catches, days = casts + day.casts, catches + day.catches, days + 1
    end
    ns.Print(format(L.REBUILD_DONE, casts, catches, days))
    ns.Print(same and L.REBUILD_SAME or L.REBUILD_CHANGED)
end)
