-- User-facing strings of the UI overhaul (Epic 9: style kit, main window, pages); loaded after
-- Locale.lua, which creates ns.L.
local _, ns = ...

local L = ns.L

-- Style kit (Story 9.1)
L.THOUSANDS = ","
L.RANGE = "(%s - %s)"
L.TIP_SHIFT = "Hold Shift for how this is counted"
L.LIST_GREY = "~ grey: few casts, the value can still move a lot"

-- Main window (Story 9.2)
L.MAIN_TITLE = "Fishing Mastery"
L.PAGE_STATS = "Statistics"
L.PAGE_JOURNAL = "Journal"

-- Statistics Overview (Story 9.3)
L.OV_FISHING = "Fishing"
L.OV_RANK_apprentice = "Apprentice"
L.OV_RANK_journeyman = "Journeyman"
L.OV_RANK_expert = "Expert"
L.OV_RANK_artisan = "Artisan"
L.OV_SKILL_BAR = "Fishing %d / %d"
L.OV_SKILL_MOD = "+%d from lure and gear, effective %d (white mark)"
L.OV_SKILL_GAINED = "+%d skill points since you started tracking"
L.OV_SKILL_NONE = "Fishing skill not known yet"
L.OV_CATCHES = "Catches"
L.OV_OF_CASTS = "of %s casts"
L.OV_SUCCESS = "Success rate"
L.OV_PER_HOUR = "Catches per hour"
L.OV_PER_HOUR_UNIT = "/ h"
L.OV_ACTIVE = "Active fishing"
L.OV_ACTIVE_VALUE = "%d h %02d min"
L.OV_SESSIONS = "in %s sessions"
L.OV_LIKELY = "likely %d - %d"
L.OV_LIKELY_PERCENT = "likely %d - %d %%"
L.OV_FEW = "few casts yet"
L.OV_NO_CASTS = "no casts yet"
L.OV_WHERE = "Where casts end"
L.OV_OUT_catch = "Catch"
L.OV_OUT_getaway = "Got away"
L.OV_OUT_early_click = "Clicked too early"
L.OV_OUT_timeout = "Not clicked (timeout)"
L.OV_OUT_cancel = "Cancelled"
L.OV_OUT_invalid_target = "Invalid target"
L.OV_GREY_ROWS = "Grey rows are counted but not part of any rate."
L.OV_MOST = "Most caught"
L.OV_ITEM = "Item %d"
L.OV_ALL_FISH = "All fish: the Fish tab below."
L.OV_NONE_CAUGHT = "Nothing caught yet."
L.OV_CHARACTERS = "Characters"
L.OV_CHAR_LINE = "%s of %s casts"
