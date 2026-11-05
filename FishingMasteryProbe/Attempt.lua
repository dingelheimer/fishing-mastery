-- Pure logic: groups normalized events between a channel start and the next idle state into one
-- fishing attempt with a provisional outcome. Events are { t, name, spellID, castGUID, msgName,
-- isFishingLoot, duration }; msgName is the global string name of a UI message when known.
local _, ns = ...

local setmetatable, ipairs = setmetatable, ipairs

local Attempt = {}
Attempt.__index = Attempt
ns.Attempt = Attempt

Attempt.GRACE = 1.5 -- seconds after the channel stop to wait for loot or a message
Attempt.MAX_AGE = 90 -- an attempt without a channel stop ends as unknown after this
Attempt.MAX_LOOT_AGE = 180 -- an open loot window ends the attempt after this at the latest
Attempt.TIMEOUT_TOLERANCE = 0.5 -- a stop this close to the channel end counts as a timeout
Attempt.MAX_EVENTS = 50 -- event names (and raw events) kept per attempt

-- UI message global strings and the outcome they signal. Unknown names are kept as messages.
Attempt.MESSAGE_OUTCOMES = {
    ERR_FISH_ESCAPED = "getaway",
    ERR_FISH_NOT_HOOKED = "early_click",
    SPELL_FAILED_NOT_FISHABLE = "invalid_target",
    SPELL_FAILED_TOO_SHALLOW = "invalid_target",
    SPELL_FAILED_FISHING_TOO_LOW = "invalid_target",
    ERR_CANT_FISH_HERE = "invalid_target",
}

-- Signal outcomes, strongest first. Timeout and cancel are derived from timing.
Attempt.PRIORITY = { "catch", "getaway", "early_click", "invalid_target" }

-- Log question ID per outcome.
Attempt.QUESTIONS = {
    catch = "Q08",
    early_click = "Q11",
    timeout = "Q12",
    cancel = "Q13",
    getaway = "Q14",
    invalid_target = "Q15",
}

local STOP_EVENTS = {
    UNIT_SPELLCAST_CHANNEL_STOP = true,
}
local LOOT_START_EVENTS = { LOOT_READY = true, LOOT_OPENED = true }

function Attempt.NewClassifier()
    return setmetatable({ current = nil, nextId = 1 }, Attempt)
end

function Attempt:Active()
    return self.current ~= nil
end

local function remember(attempt, event)
    local names = attempt.events
    if #names < Attempt.MAX_EVENTS then
        names[#names + 1] = event.name
        attempt.raw[#attempt.raw + 1] = event
    else
        attempt.eventsCut = attempt.eventsCut + 1
    end
end

local function newAttempt(self, event)
    local attempt = {
        id = self.nextId,
        start = event.t,
        spellID = event.spellID,
        castGUID = event.castGUID,
        duration = event.duration,
        messages = {},
        events = {},
        raw = {},
        eventsCut = 0,
    }
    self.nextId = self.nextId + 1
    remember(attempt, event)
    return attempt
end

-- Decides the outcome from the collected signals and timing.
local function classify(attempt)
    local signals = {}
    if attempt.loot then
        signals.catch = true
    end
    for _, msgName in ipairs(attempt.messages) do
        local outcome = Attempt.MESSAGE_OUTCOMES[msgName]
        if outcome then
            signals[outcome] = true
        end
    end
    local count, outcome = 0, nil
    for _, name in ipairs(Attempt.PRIORITY) do
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
    if attempt.interrupted then
        return "cancel"
    end
    local duration = attempt.duration
    if not duration then
        return "unknown", "no_duration"
    end
    if attempt.stop - attempt.start >= duration - Attempt.TIMEOUT_TOLERANCE then
        return "timeout"
    end
    return "cancel"
end

local function finalize(attempt, now, reason)
    attempt.reason = attempt.reason or reason
    local outcome, note = classify(attempt)
    local record = {
        id = attempt.id,
        outcome = outcome,
        note = note,
        spellID = attempt.spellID,
        castGUID = attempt.castGUID,
        start = attempt.start,
        stop = attempt.stop,
        finished = now,
        duration = attempt.duration,
        elapsed = attempt.stop and attempt.stop - attempt.start or nil,
        biteTime = attempt.lootT and attempt.lootT - attempt.start or nil,
        interrupted = attempt.interrupted,
        nonFishingLoot = attempt.nonFishingLoot,
        messages = attempt.messages,
        events = attempt.events,
        eventsCut = attempt.eventsCut > 0 and attempt.eventsCut or nil,
    }
    -- Unclear attempts keep the raw events for analysis.
    if outcome == "unknown" or note == "conflict" then
        record.raw = attempt.raw
    end
    return record
end

-- Feeds one event; returns a list of finished attempt records (usually empty).
function Attempt:Feed(event)
    local finished = {}
    local current = self.current
    if event.name == "UNIT_SPELLCAST_CHANNEL_START" then
        if current then
            finished[1] = finalize(current, event.t, not current.stop and "superseded" or nil)
        end
        self.current = newAttempt(self, event)
        return finished
    end
    if not current then
        -- A cast that fails before channeling (e.g. no fishable water) is an attempt of its own.
        if Attempt.MESSAGE_OUTCOMES[event.msgName] == "invalid_target" then
            local attempt = newAttempt(self, event)
            attempt.stop = event.t
            attempt.messages[1] = event.msgName
            finished[1] = finalize(attempt, event.t)
        end
        return finished
    end
    remember(current, event)
    if event.msgName then
        current.messages[#current.messages + 1] = event.msgName
    end
    local name = event.name
    if STOP_EVENTS[name] then
        current.stop = current.stop or event.t
        if current.loot and not current.looting then
            finished[1] = finalize(current, event.t)
            self.current = nil
        end
    elseif name == "UNIT_SPELLCAST_INTERRUPTED" then
        current.interrupted = true
    elseif LOOT_START_EVENTS[name] then
        if event.isFishingLoot == false then
            current.nonFishingLoot = true
        else
            current.loot = true
            current.looting = true
            current.lootT = current.lootT or event.t
        end
    elseif name == "LOOT_CLOSED" and current.looting then
        current.looting = false
        if current.stop then
            finished[1] = finalize(current, event.t)
            self.current = nil
        end
    end
    return finished
end

-- Ends the current attempt when it reached an idle state; returns finished records.
function Attempt:Tick(now)
    local current = self.current
    if not current then
        return {}
    end
    local age = now - current.start
    local done, reason = false, nil
    if current.looting then
        done = age >= Attempt.MAX_LOOT_AGE
        reason = done and "loot_not_closed" or nil
    elseif current.stop then
        done = now >= current.stop + Attempt.GRACE
    elseif age >= Attempt.MAX_AGE then
        done, reason = true, "no_stop"
    end
    if not done then
        return {}
    end
    self.current = nil
    return { finalize(current, now, reason) }
end

-- Counts outcomes of finished records into stats = { total, last, byOutcome }.
function Attempt.Count(stats, records)
    for _, record in ipairs(records) do
        stats.total = stats.total + 1
        stats.last = record.outcome
        stats.byOutcome[record.outcome] = (stats.byOutcome[record.outcome] or 0) + 1
    end
    return stats
end
