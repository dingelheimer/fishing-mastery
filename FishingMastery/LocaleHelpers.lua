-- User-facing strings of the helpers (module 5, Epic 8: casting key, double right-click, smart
-- lure); loaded after Locale.lua, which creates ns.L.
local _, ns = ...

local L = ns.L

-- Casting key (Story 8.1)
L.BINDING_CAST = "Cast Fishing"
L.CASTKEY_NO_FISHING = "Cast Fishing: this character has not learned Fishing yet."

-- The long explanation of each helper (Stories 8.1-8.4; the row tooltips of the Helpers page).
L.OPT_TIP_doubleClick = "With a fishing pole in hand, a double right-click into the world casts "
    .. "Fishing. Right-clicks on units and windows, camera turning, and combat stay as they are."
L.HELPER_CONFLICT = "%s is loaded and has its own casting; both may react to the same click."
L.OPT_TIP_autoLure = "With a fishing pole in hand, the casting key and the double right-click "
    .. "first put on the cheapest lure in your bags that stops getaways in this water, or your "
    .. "best one if none does. Nothing is used when your skill is enough or a lure is running."

L.OPT_TIP_loudSplash = "With a fishing pole in hand: sound effects at full volume, music and "
    .. "ambience off. Your own volumes come back when the pole leaves your hand or you log out."
L.OPT_TIP_hideUI = "Hides the interface when your line goes out, like Alt+Z. It comes back when "
    .. "you move, fight, die, change your target, get a whisper or a dialog, open a loot window "
    .. "(auto loot off), or put the pole away. Your catches show at the top of the screen."

-- /fm helpers (Story 8.5)
L.CMD_HELPERS = "Show what the helpers did this login"
L.HELPERS_COUNTS = "Helpers this login: the casting key cast Fishing %d times, put on a lure %d "
    .. "times, waited for a lure %d times; %d presses came from a double right-click. Casts "
    .. "tracked: %d."
L.HELPERS_STATE = "Double right-click %s, smart lure %s, louder splash %s (%s), hide the "
    .. "interface %s (hidden %d times)."
L.HELPERS_ON = "on"
L.HELPERS_OFF = "off"
L.HELPERS_ACTIVE = "active"
L.HELPERS_IDLE = "idle"

-- Catch line while the interface is hidden (Story 8.4)
L.HIDEUI_CATCH = "+%d %s"

-- Smart lure lines in the HUD tooltip (Story 8.3)
L.LURE_REACHES = "Lure: %s (+%d) would stop getaways here"
L.LURE_STRONGEST = "Lure: %s (+%d) is your best; getaways stop at %d"
L.LURE_ENOUGH = "No lure needed at your skill"
L.LURE_NONE_OWNED = "No usable lure in your bags; getaways stop at %d"
L.LURE_ITEM = "item %d"
