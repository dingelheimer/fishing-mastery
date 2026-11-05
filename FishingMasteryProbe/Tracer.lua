-- Event tracer: logs name, redacted payload, and secret flags of every traced event (Q08, Q23).
-- Chat events keep only the player's own loot and skill messages. Format is pure logic.
local _, ns = ...

local select, ipairs = select, ipairs
local isSecret = issecretvalue or function()
    return false
end

local Redact = ns.Redact

local Tracer = {}
ns.Tracer = Tracer

Tracer.AURA_THROTTLE = 1 -- seconds between logged UNIT_AURA events
Tracer.MAX_ARGS = 20

-- Traced events; true marks unit events limited to the player.
Tracer.EVENTS = {
    { "UNIT_SPELLCAST_SENT", true },
    { "UNIT_SPELLCAST_START", true },
    { "UNIT_SPELLCAST_CHANNEL_START", true },
    { "UNIT_SPELLCAST_CHANNEL_STOP", true },
    { "UNIT_SPELLCAST_CHANNEL_UPDATE", true },
    { "UNIT_SPELLCAST_STOP", true },
    { "UNIT_SPELLCAST_SUCCEEDED", true },
    { "UNIT_SPELLCAST_INTERRUPTED", true },
    { "UNIT_SPELLCAST_FAILED", true },
    { "UNIT_SPELLCAST_FAILED_QUIET", true },
    { "LOOT_READY" },
    { "LOOT_OPENED" },
    { "LOOT_SLOT_CLEARED" },
    { "LOOT_CLOSED" },
    { "UI_ERROR_MESSAGE" },
    { "UI_INFO_MESSAGE" },
    { "CHAT_MSG_LOOT" },
    { "CHAT_MSG_SKILL" },
    { "SKILL_LINES_CHANGED" },
    { "TRADE_SKILL_LIST_UPDATE" },
    { "UNIT_INVENTORY_CHANGED", true },
    { "PLAYER_EQUIPMENT_CHANGED" },
    { "BAG_UPDATE_DELAYED" },
    { "UNIT_AURA", true },
    { "ZONE_CHANGED" },
    { "ZONE_CHANGED_INDOORS" },
    { "ZONE_CHANGED_NEW_AREA" },
    { "ITEM_DATA_LOAD_RESULT" },
    { "SPELL_DATA_LOAD_RESULT" },
}

-- Question ID per traced event family.
Tracer.QUESTIONS = {
    CHAT_MSG_SKILL = "Q25",
    SKILL_LINES_CHANGED = "Q25",
    TRADE_SKILL_LIST_UPDATE = "Q25",
    UNIT_AURA = "Q18",
    ITEM_DATA_LOAD_RESULT = "Q24",
}

-- Payload positions that hold a unit or target name; they are reduced to shape facts.
Tracer.NAME_ARGS = { UNIT_SPELLCAST_SENT = { [2] = true } }

local CHAT_EVENTS = { CHAT_MSG_LOOT = true, CHAT_MSG_SKILL = true }
local MESSAGE_EVENTS = { UI_ERROR_MESSAGE = true, UI_INFO_MESSAGE = true }
Tracer.CHAT_GUID_ARG = 12 -- sender GUID position in CHAT_MSG_* payloads

-- Positions of secret payload values.
local function secretPositions(...)
    local positions
    for i = 1, select("#", ...) do
        if isSecret((select(i, ...))) then
            positions = positions or {}
            positions[#positions + 1] = i
        end
    end
    return positions
end

-- Builds the log data for one event. ctx: { ownName, isOwnGuid(guid), messageName(type, text) }.
function Tracer.Format(ctx, event, ...)
    local count = select("#", ...)
    local data = { name = event, n = count, secret = secretPositions(...) }
    if CHAT_EVENTS[event] then
        local text, guid = ..., select(Tracer.CHAT_GUID_ARG, ...)
        data.own = ctx.isOwnGuid(guid)
        data.n = nil
        if data.own then
            data.text = Redact.OwnName(text, ctx.ownName)
        end
        return data
    end
    local args, nameArgs = {}, Tracer.NAME_ARGS[event]
    for i = 1, count < Tracer.MAX_ARGS and count or Tracer.MAX_ARGS do
        local value = select(i, ...)
        if nameArgs and nameArgs[i] then
            args[i] = Redact.Text(value)
        else
            args[i] = Redact.Value(value, ctx.ownName)
        end
    end
    data.args = args
    if MESSAGE_EVENTS[event] then
        local messageType, text = ...
        data.msgName = ctx.messageName(messageType, text)
    end
    return data
end

-- Throttle state for UNIT_AURA: returns true when the event may be logged now, plus the number
-- of events suppressed since the last logged one.
function Tracer.NewThrottle(interval)
    local last, suppressed = nil, 0
    return function(now)
        if last and now - last < interval then
            suppressed = suppressed + 1
            return false
        end
        local count = suppressed
        last, suppressed = now, 0
        return true, count
    end
end

-- Subscribes the tracer on the bus. deps: { log(kind, data, q), now(), ctx }.
function Tracer.Start(bus, deps)
    local auraThrottle = Tracer.NewThrottle(Tracer.AURA_THROTTLE)
    local function trace(event, ...)
        local suppressed
        if event == "UNIT_AURA" then
            local allowed, count = auraThrottle(deps.now())
            if not allowed then
                return
            end
            suppressed = count > 0 and count or nil
        end
        local data = Tracer.Format(deps.ctx, event, ...)
        data.suppressed = suppressed
        deps.log("event", data, Tracer.QUESTIONS[event])
    end
    for _, spec in ipairs(Tracer.EVENTS) do
        bus:On(spec[1], trace, spec[2] and "player" or nil)
    end
end
