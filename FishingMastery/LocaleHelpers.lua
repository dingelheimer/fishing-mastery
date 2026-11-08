-- User-facing strings of the helpers (module 5, Epic 8: casting key, double right-click, smart
-- lure); loaded after Locale.lua, which creates ns.L.
local _, ns = ...

local L = ns.L

-- Casting key (Story 8.1)
L.BINDING_CAST = "Cast Fishing"
L.CASTKEY_NO_FISHING = "Cast Fishing: this character has not learned Fishing yet."

-- Settings: the Helpers section (Stories 8.1-8.3)
L.OPT_helpers = "Helpers"
L.OPT_TIP_helpers = 'Bind a key to "Cast Fishing" in the game\'s Key Bindings, under AddOns, '
    .. "Fishing Mastery. Helpers act only on your key press or click."
L.OPT_doubleClick = "Double right-click casts Fishing"
L.OPT_TIP_doubleClick = "With a fishing pole in hand, a double right-click into the world casts "
    .. "Fishing. Right-clicks on units and windows, camera turning, and combat stay as they are."
L.HELPER_CONFLICT = "%s is loaded and has its own casting; both may react to the same click."
L.OPT_autoLure = "Apply a lure first"
L.OPT_TIP_autoLure = "With a fishing pole in hand, the casting key and the double right-click "
    .. "first put on the cheapest lure in your bags that stops getaways in this water, or your "
    .. "best one if none does. Nothing is used when your skill is enough or a lure is running."

L.OPT_loudSplash = "Louder splash while a pole is equipped"
L.OPT_TIP_loudSplash = "With a fishing pole in hand: sound effects at full volume, music and "
    .. "ambience off. Your own volumes come back when the pole leaves your hand or you log out."
L.OPT_hideUI = "Hide the interface while fishing"
L.OPT_TIP_hideUI = "Hides the interface when your line goes out, like Alt+Z. It comes back when "
    .. "you move, fight, die, change your target, get a whisper or a dialog, open a loot window "
    .. "(auto loot off), or put the pole away. Your catches show at the top of the screen."

-- Catch line while the interface is hidden (Story 8.4)
L.HIDEUI_CATCH = "+%d %s"

-- Smart lure lines in the HUD tooltip (Story 8.3)
L.LURE_REACHES = "Lure: %s (+%d) would stop getaways here"
L.LURE_STRONGEST = "Lure: %s (+%d) is your best; getaways stop at %d"
L.LURE_ENOUGH = "No lure needed at your skill"
L.LURE_NONE_OWNED = "No usable lure in your bags; getaways stop at %d"
L.LURE_ITEM = "item %d"
