-- Connects game events to the attempt classifier: normalizes payloads (fishing spell check,
-- message names, channel length, fishing loot), runs the end-of-attempt timer, and counts the
-- outcomes of this login. Only reads events and query APIs; never calls protected functions.
local _, ns = ...

local type, ipairs, setmetatable = type, ipairs, setmetatable
local isSecret = issecretvalue or function()
    return false
end

local Attempt = ns.Attempt
local Tracker = {}
Tracker.__index = Tracker
ns.Tracker = Tracker

Tracker.TIMER_SLACK = 0.05 -- seconds added to the deadline so Tick runs after it
Tracker.GENERIC_SPELL_FAILED = "ERR_SPELL_FAILED_S"
Tracker.GENERIC_SPELL_FAILED_TYPE = 57 -- live message type of ERR_SPELL_FAILED_S

-- Global strings whose text identifies a message when the message name is missing or generic.
Tracker.TEXT_NAMES = {
    "ERR_FISH_ESCAPED",
    "ERR_FISH_NOT_HOOKED",
    "SPELL_FAILED_NOT_FISHABLE",
    "SPELL_FAILED_TOO_SHALLOW",
}

local function plain(value)
    if isSecret(value) then
        return nil
    end
    return value
end

local call = ns.Context.Call

local function spellName(env, spellID)
    local info = call(env, "C_Spell.GetSpellInfo", spellID)
    local name = type(info) == "table" and plain(info.name) or nil
    return type(name) == "string" and name or nil
end

-- Fishing spell check: 7620, or a spell with the same name as 7620 (in case ranks change the ID).
function Tracker.FishingSpellCheck(env)
    local cache = {}
    return function(spellID)
        spellID = plain(spellID)
        if type(spellID) ~= "number" then
            return false
        end
        if spellID == Attempt.FISHING_SPELL_ID then
            return true
        end
        if cache[spellID] == nil then
            local fishing = spellName(env, Attempt.FISHING_SPELL_ID)
            cache[spellID] = fishing ~= nil and spellName(env, spellID) == fishing
        end
        return cache[spellID]
    end
end

-- Global string name of a UI message: GetGameMessageInfo first; a missing or generic name
-- (ERR_SPELL_FAILED_S) is replaced by the global string whose text equals the message text.
-- Invalid-target names are only taken from generic spell failures.
function Tracker.MessageName(env, messageType, text)
    messageType, text = plain(messageType), plain(text)
    local name = plain((call(env, "GetGameMessageInfo", messageType)))
    if type(name) ~= "string" then
        name = nil
    end
    if name and name ~= Tracker.GENERIC_SPELL_FAILED then
        return name
    end
    if type(text) ~= "string" then
        return name
    end
    local generic = name == Tracker.GENERIC_SPELL_FAILED
        or (name == nil and messageType == Tracker.GENERIC_SPELL_FAILED_TYPE)
    for _, candidate in ipairs(Tracker.TEXT_NAMES) do
        local value = plain(env[candidate])
        if value == text and (generic or not Attempt.INVALID_TARGET[candidate]) then
            return candidate
        end
    end
    return name
end

local function channelDuration(env)
    local _, _, _, startMs, endMs = call(env, "UnitChannelInfo", "player")
    startMs, endMs = plain(startMs), plain(endMs)
    if type(startMs) == "number" and type(endMs) == "number" and endMs > startMs then
        return (endMs - startMs) / 1000
    end
    return nil
end

-- deps: { env, bus, now(), after(seconds, fn), onAttempt(record), context(), loot() }; the last
-- three are optional. context() is read at a fishing channel start and at an invalid-target
-- message, loot() at fishing loot during an attempt; both results go into the record.
function Tracker.Start(deps)
    local env, now = deps.env, deps.now
    local isFishingSpell = Tracker.FishingSpellCheck(env)
    local context = deps.context or function() end
    local readLoot = deps.loot or function() end
    local self = setmetatable({
        classifier = Attempt.NewClassifier(isFishingSpell),
        counts = {},
        total = 0,
        last = nil,
        timerAt = nil,
    }, Tracker)

    local tick

    local function emit(records)
        for _, record in ipairs(records) do
            self.total = self.total + 1
            self.counts[record.outcome] = (self.counts[record.outcome] or 0) + 1
            self.last = record
            if deps.onAttempt then
                deps.onAttempt(record)
            end
        end
    end

    local function schedule()
        local deadline = self.classifier:Deadline()
        if not deadline or (self.timerAt and self.timerAt <= deadline) then
            return
        end
        self.timerAt = deadline
        deps.after(deadline - now() + Tracker.TIMER_SLACK, tick)
    end

    tick = function()
        self.timerAt = nil
        emit(self.classifier:Tick(now()))
        schedule()
    end

    local function feed(event)
        event.t = now()
        emit(self.classifier:Feed(event))
        schedule()
    end

    local bus = deps.bus
    bus:On("UNIT_SPELLCAST_CHANNEL_START", function(name, _, _, spellID)
        spellID = plain(spellID)
        if not isFishingSpell(spellID) then
            return
        end
        feed({ name = name, spellID = spellID, duration = channelDuration(env), ctx = context() })
    end, "player")
    for _, name in ipairs({ "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED" }) do
        bus:On(name, function(event, _, _, spellID)
            feed({ name = event, spellID = plain(spellID) })
        end, "player")
    end
    for _, name in ipairs({ "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }) do
        bus:On(name, function(event, messageType, text)
            local msgName = Tracker.MessageName(env, messageType, text)
            local ctx = Attempt.INVALID_TARGET[msgName] and context() or nil
            feed({ name = event, msgName = msgName, ctx = ctx })
        end)
    end
    local function onLoot(event, autoLoot)
        local flag = plain(autoLoot)
        if event ~= "LOOT_READY" or type(flag) ~= "boolean" then
            flag = nil
        end
        local fishing = plain((call(env, "IsFishingLoot"))) == true
        feed({
            name = event,
            isFishingLoot = fishing,
            autoLoot = flag,
            loot = fishing and self.classifier:Active() and readLoot() or nil,
        })
    end
    bus:On("LOOT_READY", onLoot)
    bus:On("LOOT_OPENED", onLoot)
    bus:On("LOOT_CLOSED", function(event)
        feed({ name = event })
    end)
    return self
end
