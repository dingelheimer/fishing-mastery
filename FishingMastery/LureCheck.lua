-- Lure check (/fm dev lure, dev flag only; Story 10.3): prints the lure enchant ID the client
-- reports for the running lure (GetWeaponEnchantInfo), the bonus the journal data gives it, and
-- the time left, and keeps one entry per enchant ID in FishingMasteryDB.dev.lures for the saved
-- file. Answers whether lures with the same bonus (Nightcrawlers and Aquadynamic Fish Lens,
-- Bright Baubles and Flesh Eating Worm) have their own enchant IDs on Forever.
local _, ns = ...

local type, format, floor = type, string.format, math.floor
local L, Context = ns.L, ns.Context

local LureCheck = {}
ns.LureCheck = LureCheck

-- deps: { env, db, serverTime() }. Returns the saved entry, or nil without a lure.
function LureCheck.Run(deps)
    local enchant, seconds = Context.LureTime(deps.env)
    if type(enchant) ~= "number" then
        ns.Print(L.DEV_LURE_NONE)
        return nil
    end
    local bonus = ((ns.Journal or {}).lureEnchants or {})[enchant]
    local dev = ns.Stress.Dev(deps.db)
    dev.lures = type(dev.lures) == "table" and dev.lures or {}
    local entry =
        { bonus = bonus, seconds = seconds and floor(seconds) or nil, at = deps.serverTime() }
    dev.lures[enchant] = entry
    ns.Print(
        format(
            L.DEV_LURE,
            enchant,
            bonus and format("+%d", bonus) or L.DEV_LURE_UNKNOWN,
            seconds and format("%d:%02d", floor(seconds / 60), floor(seconds) % 60) or "?"
        )
    )
    return entry
end
