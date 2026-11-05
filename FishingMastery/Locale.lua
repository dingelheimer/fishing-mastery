-- User-facing strings. English is the only locale; missing keys fall back to the key itself.
local _, ns = ...

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
ns.L = L

L.PREFIX = "Fishing Mastery"
L.HELP_HEADER = "Version %s. Commands:"
L.HELP_LINE = "  /fm %s - %s"
L.CMD_HELP = "Show this help"
L.UNKNOWN_COMMAND = "Unknown command: %s"
L.CHARACTERS = "Characters with saved data: %d"
L.ERRORS_NONE = "Lua errors this session: 0"
L.ERRORS = "Lua errors this session: %d (last %d shown)"
L.ERROR_LINE = "  %s: %s"
L.DB_NEWER = "Saved data is from a newer version (schema %d, this version reads %d). "
    .. "Update the addon; nothing is migrated."
L.MIGRATED = "Saved data upgraded from schema %d to %d; a copy of the old data is kept until "
    .. "the next login."
L.CMD_STATUS = "Show the current fishing session"
L.STATUS_NONE = "No open fishing session; the next cast starts one."
L.STATUS_HEADER = "Session: %d min, %d casts, %d catches"
L.STATUS_COUNTS = "  Getaways %d, early clicks %d, timeouts %d, cancels %d, invalid targets %d, "
    .. "unknown %d"
L.STATUS_SKILL = "  Fishing skill %s -> %s (%+d)"
L.STATUS_LAST = "  Last: %s"
L.STATUS_LAST_BITE = "  Last: %s, bite time %.1f s"
L.STATUS_NOT_READY = "Tracking starts after login."
L.OUTCOME_catch = "catch"
L.OUTCOME_getaway = "fish got away"
L.OUTCOME_early_click = "clicked too early"
L.OUTCOME_timeout = "timeout (bobber not clicked)"
L.OUTCOME_cancel = "cancelled"
L.OUTCOME_invalid_target = "invalid target (no fishable water)"
L.OUTCOME_unknown = "unknown"
L.QUARANTINE = "%d damaged history chunk(s) were set aside in quarantine and kept unchanged; "
    .. "the rest of your history loaded."
L.CMD_REBUILD = "Count the totals again from the whole history"
L.REBUILD_DONE = "Totals rebuilt from %d casts (%d catches) on %d days."
L.NO_CHARACTER = "Character not recognized yet; data for this character is not saved."
