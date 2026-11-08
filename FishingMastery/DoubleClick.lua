-- Pure logic of double right-click casting (module 5, Story 8.2): which right-button press is the
-- second click of a double-click into the world, and why casting is blocked right now. Times are
-- seconds (GetTimePreciseSec). No frame or API calls.
local _, ns = ...

local setmetatable, ipairs = setmetatable, ipairs

local DoubleClick = {}
DoubleClick.__index = DoubleClick
ns.DoubleClick = DoubleClick

DoubleClick.MAX = 0.4 -- the second press must follow the first within this time
DoubleClick.MIN = 0.05 -- a faster second press is a bounce, not a click
DoubleClick.HOLD = 0.3 -- a press held longer turned the camera; it starts no double-click
DoubleClick.UNIT_QUIET = 1 -- after a click on a unit, world clicks this soon count for nothing
DoubleClick.ARM_TIMEOUT = 2 -- the right button stays bound to the cast button at most this long

function DoubleClick.New()
    return setmetatable({ last = nil, downAt = nil, unitAt = nil, lineInAt = nil }, DoubleClick)
end

-- A right-button press at time t. place: "world", "unit" (a unit under the mouse), or "ui" (a
-- frame). Returns true when this press completes a double-click into the world, else false and
-- the reason.
function DoubleClick:Down(t, place)
    self.downAt = t
    local last = self.last
    if place ~= "world" then
        if place == "unit" then
            self.unitAt = t
        end
        self.last = nil
        return false, place
    end
    if self.unitAt and t - self.unitAt < DoubleClick.UNIT_QUIET then
        self.last = nil
        return false, "unit-quiet"
    end
    local gap = last and t - last
    if not gap or gap >= DoubleClick.MAX then
        self.last = t
        return false, "first"
    end
    if gap <= DoubleClick.MIN then
        self.last = t
        return false, "too-fast"
    end
    self.last = nil
    -- The first click hooked the bobber: the line came in between both presses.
    if self.lineInAt and self.lineInAt > last then
        return false, "bobber"
    end
    return true, "double"
end

-- The right button came up at time t: a long hold was camera turning, not a first click.
function DoubleClick:Up(t)
    local downAt = self.downAt
    self.downAt = nil
    if downAt and self.last and t - downAt > DoubleClick.HOLD then
        self.last = nil
        return "hold"
    end
    return nil
end

-- The fishing line came in (bobber clicked, getaway, timeout, cancel) at time t.
function DoubleClick:LineIn(t)
    self.lineInAt = t
end

-- A loading screen: a press before it and one after it are no double-click.
function DoubleClick:Forget()
    self.last, self.downAt, self.unitAt = nil, nil, nil
end

-- Conditions that block a cast, in order; each maps to the state field that must be false.
DoubleClick.BLOCKS = {
    { "off", "off" },
    { "combat", "combat" },
    { "mounted", "mounted" },
    { "swimming", "swimming" },
    { "flying", "flying" },
    { "taxi", "taxi" },
    { "dead", "dead" },
    { "no-button", "noButton" },
    { "no-fishing", "noFishing" },
    { "no-pole", "noPole" },
    { "lure-wait", "lureWait" },
    { "line-out", "lineOut" },
}

-- Why a double-click would not cast now (nil: it would). state: booleans named in BLOCKS.
function DoubleClick.Blocked(state)
    for _, block in ipairs(DoubleClick.BLOCKS) do
        if state[block[2]] then
            return block[1]
        end
    end
    return nil
end
