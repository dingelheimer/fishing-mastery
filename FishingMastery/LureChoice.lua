-- Pure logic of the smart lure (module 5, Story 8.3): which owned lure, if any, the casting key
-- puts on before it casts. Getaways stop at the water's base skill + 95 (Getaway.lua); the choice
-- is no lure when the skill without a lure reaches that, else the cheapest owned lure that does,
-- else the strongest usable one. No frame or API calls.
local _, ns = ...

local type, ipairs, pairs = type, ipairs, pairs
local Getaway = ns.Getaway

local LureChoice = {}
ns.LureChoice = LureChoice

LureChoice.KEEP = 30 -- a running lure with more seconds left than this is left alone

local function usable(lure, rank)
    return (lure.need or 0) <= (rank or 0)
end

-- The cheapest usable lure that reaches goal from skill, else the strongest usable one.
local function pick(lures, skill, rank, goal)
    local cheapest, strongest
    for _, lure in ipairs(lures) do
        if usable(lure, rank) then
            if
                goal
                and skill + lure.bonus >= goal
                and (not cheapest or lure.bonus < cheapest.bonus)
            then
                cheapest = lure
            end
            if not strongest or lure.bonus > strongest.bonus then
                strongest = lure
            end
        end
    end
    if cheapest then
        return cheapest, "reaches"
    end
    return strongest, strongest and "strongest" or "no-lures"
end

-- input: { base (water base skill, nil: unknown), skill (effective skill without a lure, nil:
-- unknown), rank (Fishing rank, for a lure's skill to use), lures ({ { id, bonus, need } } owned
-- in the bags), active ({ bonus (nil: unknown lure), seconds } or nil), applying (a lure click is
-- still being applied) }. Returns { action = "lure" | "none" | "wait", lure, reason, goal }.
-- Reasons: applying, unknown-skill, active, enough, reaches, strongest, no-lures, unknown-base
-- (the strongest lure: no water data), other-running (the lure to renew is of another kind, the
-- client would ask to replace the running one).
function LureChoice.Choose(input)
    local base, skill = input.base, input.skill
    local goal = type(base) == "number" and base + Getaway.SPAN or nil
    local function result(action, reason, lure)
        return { action = action, reason = reason, lure = lure, goal = goal }
    end
    if input.applying then
        return result("wait", "applying")
    end
    local active = input.active
    if active and (active.seconds == nil or active.seconds > LureChoice.KEEP) then
        return result("none", "active")
    end
    if type(skill) ~= "number" then
        return result("none", "unknown-skill")
    end
    if goal and skill >= goal then
        return result("none", "enough")
    end
    local lure, reason = pick(input.lures or {}, skill, input.rank, goal)
    if not lure then
        return result("none", reason)
    end
    if not goal then
        reason = "unknown-base"
    end
    if active and active.bonus ~= lure.bonus then
        return result("none", "other-running", lure)
    end
    return result("lure", reason, lure)
end

-- The item of a running lure from its bonus (the client reports only the lure enchant, which the
-- journal maps to a bonus; Story 10.3): a lure of that bonus in the bags (several kinds: the
-- lowest item ID, as Choose picks among equal bonuses), else the only lure of the journal with
-- that bonus, else nil (two lures share it). owned: { { id, bonus } } or nil; lures: the
-- journal's lures ({ [id] = { bonus, ... } }).
function LureChoice.Running(bonus, owned, lures)
    if type(bonus) ~= "number" then
        return nil
    end
    local best
    for _, lure in ipairs(owned or {}) do
        if lure.bonus == bonus and (not best or lure.id < best) then
            best = lure.id
        end
    end
    if best then
        return best
    end
    local only, count = nil, 0
    for id, lure in pairs(lures or {}) do
        if lure[1] == bonus then
            only, count = id, count + 1
        end
    end
    return count == 1 and only or nil
end
