-- Starts the helpers of module 5 (Epic 8) at login, in order: the casting key, the smart lure
-- (its chooser), the louder splash, the hidden interface, double right-click casting (uses the
-- key), and the /fm helpers counts. Each is kept in ns for the settings and the tracker hook.
local _, ns = ...

local Helpers = {}
ns.Helpers = Helpers

-- deps: { env, bus, settings (db.settings), store (FishingMasteryCharDB), areas, print, now,
-- timer(where) -> after(seconds, fn) or nil }.
function Helpers.Start(deps)
    local env, bus, settings = deps.env, deps.bus, deps.settings
    local isFishingSpell = ns.Tracker.FishingSpellCheck(env)
    ns.castKey = ns.CastKey.Start({ env = env, bus = bus, print = deps.print })
    ns.smartLure = ns.SmartLure.Start({
        env = env,
        bus = bus,
        castKey = ns.castKey,
        settings = settings,
        areas = deps.areas,
        journal = ns.Journal,
        now = deps.now,
    })
    ns.soundBoost = ns.SoundBoost.Start({
        env = env,
        bus = bus,
        settings = settings,
        store = deps.store,
    })
    ns.hideUI = ns.HideUI.Start({
        env = env,
        bus = bus,
        settings = settings,
        isFishingSpell = isFishingSpell,
        after = deps.timer("timer:hideui"),
    })
    ns.doubleCast = ns.DoubleCast.Start({
        env = env,
        bus = bus,
        castKey = ns.castKey,
        settings = settings,
        now = deps.now,
        after = deps.timer("timer:double"),
        isFishingSpell = isFishingSpell,
    })
    ns.helperStatus = ns.HelperStatus.Start({
        settings = settings,
        castKey = ns.castKey,
        doubleCast = ns.doubleCast,
        hideUI = ns.hideUI,
        soundBoost = ns.soundBoost,
    })
end

-- A cast the tracker saved: the catch line of the hidden interface and the /fm helpers count.
function Helpers.OnCast(cast)
    if ns.helperStatus then
        ns.hideUI:OnCast(cast)
        ns.helperStatus:OnCast(cast)
    end
end
