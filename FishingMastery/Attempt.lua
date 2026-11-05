-- Pure logic: turns normalized cast, message, and loot events into finished fishing attempts.
-- Events: { t, name, spellID, msgName, isFishingLoot, autoLoot, duration, ctx, loot }. name is
-- the WoW event name; msgName is the global string name of a UI message (resolved by
-- Tracker.lua); duration is the channel length in seconds from UnitChannelInfo. ctx (cast
-- context, at the channel start or the failure message) and loot (at the first fishing loot
-- event) are opaque and copied into the record. No frame or API calls.
local _, ns = ...

local setmetatable, floor, type, ipairs, tremove =
    setmetatable, math.floor, type, ipairs, table.remove

local Attempt = {}
Attempt.__index = Attempt
ns.Attempt = Attempt

Attempt.FISHING_SPELL_ID = 7620
Attempt.GRACE = 1.5 -- seconds after the channel stop to wait for loot or a message
Attempt.MAX_AGE = 90 -- an attempt that has not ended after this ends as unknown
-- A stop this close to the channel end, or later, is a timeout. Live timeouts stopped 1.6-2.2 s
-- after the nominal 30 s end, so there is no upper bound.
Attempt.TIMEOUT_TOLERANCE = 0.5
Attempt.FAIL_WINDOW = 1 -- a type-57 message pairs with a fishing cast failure this recent

Attempt.OUTCOMES = { "catch", "getaway", "early_click", "timeout", "cancel", "invalid_target" }

-- Info messages inside an attempt and the outcome they signal.
Attempt.SIGNALS = {
    ERR_FISH_ESCAPED = "getaway",
    ERR_FISH_NOT_HOOKED = "early_click",
}
-- Error message names (resolved from the text) that make a failed cast an invalid target.
Attempt.INVALID_TARGET = {
    SPELL_FAILED_NOT_FISHABLE = true,
    SPELL_FAILED_TOO_SHALLOW = true,
}

-- Signal outcomes, strongest first. Timeout and cancel come from timing.
local PRIORITY = { "catch", "getaway", "early_click" }
-- Outcomes whose message marks the moment of the player's click.
local CLICKED = { getaway = true, early_click = true }

-- isFishingSpell(spellID): true for the fishing spell; default compares with 7620.
function Attempt.NewClassifier(isFishingSpell)
    return setmetatable({
        current = nil,
        pendingFails = {},
        isFishingSpell = isFishingSpell or function(spellID)
            return spellID == Attempt.FISHING_SPELL_ID
        end,
    }, Attempt)
end

function Attempt:Active()
    return self.current ~= nil
end

-- Time at which Tick must run to end the current attempt, or nil when idle.
function Attempt:Deadline()
    local current = self.current
    if not current then
        return nil
    end
    local deadline = current.start + Attempt.MAX_AGE
    if current.stop and not current.looting then
        local graceEnd = current.stop + Attempt.GRACE
        if graceEnd < deadline then
            deadline = graceEnd
        end
    end
    return deadline
end

local function tenths(seconds)
    return floor(seconds * 10 + 0.5)
end

local function classify(attempt)
    local signals = attempt.signals
    local count, outcome = 0, nil
    for _, name in ipairs(PRIORITY) do
        if signals[name] then
            count = count + 1
            outcome = outcome or name
        end
    end
    if outcome then
        return outcome, count > 1 and "conflict" or nil
    end
    if attempt.reason then
        return "unknown", attempt.reason
    end
    if not attempt.duration then
        return "unknown", "no_duration"
    end
    if attempt.stop - attempt.start >= attempt.duration - Attempt.TIMEOUT_TOLERANCE then
        return "timeout"
    end
    return "cancel"
end

-- Message time of an early click or getaway in tenths after the channel start. The message
-- follows the click within a frame, so this is the click time (Story 3.4).
local function clickTenths(attempt, outcome)
    local t = CLICKED[outcome] and attempt.signalT[outcome]
    return t and tenths(t - attempt.start) or nil
end

local function finalize(attempt, reason)
    attempt.reason = attempt.reason or reason
    local outcome, note = classify(attempt)
    return {
        outcome = outcome,
        note = note,
        start = attempt.start,
        stop = attempt.stop,
        duration = attempt.duration,
        biteTenths = outcome == "catch" and attempt.lootT and tenths(attempt.lootT - attempt.start)
            or nil,
        clickTenths = clickTenths(attempt, outcome),
        autoLoot = attempt.autoLoot,
        ctx = attempt.ctx,
        loot = outcome == "catch" and attempt.loot or nil,
    }
end

local function invalidTarget(event)
    return { outcome = "invalid_target", start = event.t, stop = event.t, ctx = event.ctx }
end

-- Ends the current attempt (if any) into finished; reason marks an unclear end.
local function closeCurrent(self, finished, reason)
    local current = self.current
    if current then
        self.current = nil
        finished[#finished + 1] = finalize(current, not current.stop and reason or nil)
    end
end

-- Drops failures older than FAIL_WINDOW; returns true and consumes one when one is left.
local function takeFail(self, t)
    local fails = self.pendingFails
    while fails[1] and t - fails[1] > Attempt.FAIL_WINDOW do
        tremove(fails, 1)
    end
    if fails[1] then
        tremove(fails, 1)
        return true
    end
    return false
end

local handlers = {}

handlers.UNIT_SPELLCAST_CHANNEL_START = function(self, event, finished)
    if not self.isFishingSpell(event.spellID) then
        return
    end
    closeCurrent(self, finished, "superseded")
    self.pendingFails = {}
    self.current = {
        start = event.t,
        duration = event.duration,
        signals = {},
        signalT = {},
        ctx = event.ctx,
    }
end

handlers.UNIT_SPELLCAST_CHANNEL_STOP = function(self, event, finished)
    local current = self.current
    if not current or current.stop or not self.isFishingSpell(event.spellID) then
        return
    end
    current.stop = event.t
    if current.signals.catch and not current.looting then
        closeCurrent(self, finished)
    end
end

-- A failure of the fishing spell; the message that names the reason follows. Failures of a
-- recast inside a running channel (and UNIT_SPELLCAST_FAILED_QUIET) are not attempts.
handlers.UNIT_SPELLCAST_FAILED = function(self, event)
    local current = self.current
    if self.isFishingSpell(event.spellID) and not (current and not current.stop) then
        local fails = self.pendingFails
        fails[#fails + 1] = event.t
    end
end

local function onMessage(self, event, finished)
    local name = event.msgName
    local current = self.current
    if Attempt.INVALID_TARGET[name] then
        -- A recast at bad water inside a running channel leaves the channel running.
        if current and not current.stop then
            return
        end
        if takeFail(self, event.t) then
            closeCurrent(self, finished, "superseded")
            finished[#finished + 1] = invalidTarget(event)
        end
        return
    end
    local signal = Attempt.SIGNALS[name]
    if signal and current then
        current.signals[signal] = true
        current.signalT[signal] = current.signalT[signal] or event.t
    end
end
handlers.UI_INFO_MESSAGE = onMessage
handlers.UI_ERROR_MESSAGE = onMessage

local function onLootStart(self, event)
    local current = self.current
    if not current or event.isFishingLoot ~= true then
        return
    end
    current.signals.catch = true
    current.looting = true
    current.lootT = current.lootT or event.t
    current.loot = current.loot or event.loot
    if event.autoLoot ~= nil and current.autoLoot == nil then
        current.autoLoot = event.autoLoot
    end
end
handlers.LOOT_READY = onLootStart
handlers.LOOT_OPENED = onLootStart

handlers.LOOT_CLOSED = function(self, _, finished)
    local current = self.current
    if not current or not current.looting then
        return
    end
    current.looting = false
    if current.stop then
        closeCurrent(self, finished)
    end
end

-- Feeds one event; returns the list of finished attempt records (usually empty).
function Attempt:Feed(event)
    local finished = {}
    local handler = type(event) == "table" and handlers[event.name]
    if handler then
        handler(self, event, finished)
    end
    return finished
end

-- Ends the current attempt when its grace time or maximum age has passed.
function Attempt:Tick(now)
    local deadline = self:Deadline()
    if not deadline or now < deadline then
        return {}
    end
    local current = self.current
    self.current = nil
    local reason = nil
    if not current.stop or current.looting then
        reason = current.looting and "loot_not_closed" or "no_stop"
    end
    return { finalize(current, reason) }
end
