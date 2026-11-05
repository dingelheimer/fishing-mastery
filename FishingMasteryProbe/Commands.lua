-- Slash command registry and dispatch for /fmp. Later stories register more commands.
local _, ns = ...

local format, lower, match, ipairs = string.format, string.lower, string.match, ipairs
local L = ns.L

-- onEmpty: called for a bare "/fmp" before the help (Core sets it to toggle the window).
local Commands = { list = {}, byName = {}, onEmpty = nil }
ns.Commands = Commands

function Commands.Register(name, description, fn)
    local command = { name = name, description = description, fn = fn }
    Commands.list[#Commands.list + 1] = command
    Commands.byName[name] = command
end

-- Runs "/fmp <name> <rest>". An empty name calls onEmpty and shows the help; an unknown name
-- is reported and shows the help.
function Commands.Dispatch(message)
    local name, rest = match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    name = lower(name)
    local command = Commands.byName[name]
    if not command then
        if name ~= "" then
            ns.Print(format(L.UNKNOWN_COMMAND, name))
        elseif Commands.onEmpty then
            Commands.onEmpty()
        end
        command = Commands.byName.help
    end
    command.fn(rest)
end

Commands.Register("help", L.CMD_HELP, function()
    ns.Print(L.HELP_HEADER)
    for _, command in ipairs(Commands.list) do
        ns.Print(format(L.HELP_LINE, command.name, command.description))
    end
    ns.Print(format(L.CURRENT_STEP, ns.logger and ns.logger.step or "-"))
    ns.Print(L.LOG_PATH)
    ns.Print("  " .. L.LOG_PATH_VALUE)
    ns.Print(L.HELP_WINDOW)
end)

Commands.Register("status", L.CMD_STATUS, function()
    local logger = ns.logger
    if not logger then
        ns.Print(L.NOT_READY)
        return
    end
    local store = logger.store
    ns.Print(
        format(
            L.STATUS,
            store.sessionId or "-",
            store.probeVersion or "-",
            logger:Count(),
            store.cap,
            logger:Dropped(),
            ns.Guard.errors
        )
    )
    local snapshot = ns.snapshot
    if snapshot then
        ns.Print(format(L.SNAPSHOT, snapshot.count, snapshot.supported, #ns.ApiList.EVENTS))
    else
        ns.Print(L.SNAPSHOT_PENDING)
    end
    local stats = ns.recorders and ns.recorders.stats
    if stats and stats.total > 0 then
        ns.Print(format(L.ATTEMPTS, stats.total, stats.last))
    else
        ns.Print(L.ATTEMPTS_NONE)
    end
    local progress = ns.progress
    if progress then
        local counter = ns.View.Counter(progress)
        ns.Print(
            format(
                L.STATUS_STEP,
                progress:Current().id,
                progress:Started() and L.STARTED or L.NOT_STARTED,
                counter and ", " .. counter or ""
            )
        )
    end
end)
