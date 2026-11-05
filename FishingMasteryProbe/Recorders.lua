-- Recorders (Story 1.3): cast context, loot, item info, attempts, and the bobber tooltip.
-- Everything reads from an injected environment and bus so a full sequence runs in tests.
local _, ns = ...

local type, pcall, ipairs, pairs, find = type, pcall, ipairs, pairs, string.find
local isSecret = issecretvalue or function()
    return false
end

local Calls, Redact, Attempt, Loot = ns.Calls, ns.Redact, ns.Attempt, ns.Loot

local Recorders = {}
ns.Recorders = Recorders

Recorders.MAX_TOOLTIPS_PER_ATTEMPT = 3
Recorders.TIMER_SLACK = 0.1

-- Cast and UI events the attempt classifier needs besides channel start and loot.
Recorders.ATTEMPT_EVENTS = {
    { "UNIT_SPELLCAST_CHANNEL_STOP", true },
    { "UNIT_SPELLCAST_CHANNEL_UPDATE", true },
    { "UNIT_SPELLCAST_STOP", true },
    { "UNIT_SPELLCAST_INTERRUPTED", true },
    { "UNIT_SPELLCAST_FAILED", true },
    { "UNIT_SPELLCAST_FAILED_QUIET", true },
    { "LOOT_CLOSED" },
}

local function plain(value)
    return not isSecret(value) and value
end

-- Tracer context: own name and GUID stay in memory only and are used for comparisons.
function Recorders.BuildContext(env)
    local _, nameOk, ownName = Calls.Invoke(env, "UnitName", "player")
    local _, guidOk, ownGuid = Calls.Invoke(env, "UnitGUID", "player")
    ownName = nameOk and type(plain(ownName)) == "string" and ownName or nil
    ownGuid = guidOk and type(plain(ownGuid)) == "string" and ownGuid or nil
    local candidates = {}
    for name in pairs(Attempt.MESSAGE_OUTCOMES) do
        candidates[#candidates + 1] = name
    end
    local found = ns.Scan.Collect(env, ns.Scan.NameContains({ "FISH", "LURE" }, "string"))
    for _, item in ipairs(found.items) do
        candidates[#candidates + 1] = item.name
    end
    local ctx = { ownName = ownName }
    function ctx.isOwnGuid(guid)
        return ownGuid ~= nil and not isSecret(guid) and guid == ownGuid
    end
    -- Global string name of a UI message: GetGameMessageInfo first, then a text lookup.
    function ctx.messageName(messageType, text)
        local _, ok, errorName = Calls.Invoke(env, "GetGameMessageInfo", messageType)
        if ok and type(plain(errorName)) == "string" then
            return errorName
        end
        if isSecret(text) or type(text) ~= "string" then
            return nil
        end
        for _, name in ipairs(candidates) do
            local value = ns.Scan.Resolve(env, name)
            if not isSecret(value) and value == text then
                return name
            end
        end
        return nil
    end
    return ctx
end

-- Q26: first two lines of a world-object tooltip. Line 1 keeps its text (own name replaced);
-- line 2 is reduced to its shape, since it may name another player.
function Recorders.TooltipLines(env, tooltip, ownName)
    local okUnit, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not okUnit or unit ~= nil then
        return nil
    end
    local okOwner, owner = pcall(tooltip.GetOwner, tooltip)
    if not okOwner or owner ~= env.UIParent then
        return nil
    end
    local okName, name = pcall(tooltip.GetName, tooltip)
    if not okName or type(name) ~= "string" then
        return nil
    end
    local texts = {}
    for i = 1, 2 do
        local line = env[name .. "TextLeft" .. i]
        local okText, text = false, nil
        if type(line) == "table" and line.GetText then
            okText, text = pcall(line.GetText, line)
        end
        texts[i] = okText and text or nil
    end
    if texts[1] == nil then
        return nil
    end
    local second = Redact.Text(texts[2])
    if type(ownName) == "string" and not isSecret(texts[2]) and type(texts[2]) == "string" then
        second.hasOwnName = find(texts[2], ownName, 1, true) ~= nil
    end
    return { line1 = Redact.OwnName(texts[1], ownName), line2 = second }
end

-- deps: { env, bus, log(kind, data, q), now(), after(seconds, fn) }. Returns the recorder state.
function Recorders.Start(deps)
    local env, bus, log, now = deps.env, deps.bus, deps.log, deps.now
    local ctx = Recorders.BuildContext(env)
    local classifier = Attempt.NewClassifier()
    local state = { stats = { total = 0, byOutcome = {} }, classifier = classifier, items = {} }
    local tooltipsSeen = {}

    local function emit(records)
        for _, record in ipairs(records) do
            -- The spell of a catch is the fishing spell; the S14a test key casts it.
            if record.outcome == "catch" and type(record.spellID) == "number" then
                state.fishingSpellID = record.spellID
            end
            log("attempt", record, Attempt.QUESTIONS[record.outcome])
        end
        Attempt.Count(state.stats, records)
    end
    local function tick()
        emit(classifier:Tick(now()))
    end
    local function feed(event, wait)
        emit(classifier:Feed(event))
        if classifier:Active() then
            deps.after((wait or Attempt.GRACE) + Recorders.TIMER_SLACK, tick)
        end
    end
    state.tick = tick

    ns.Tracer.Start(bus, { log = log, now = now, ctx = ctx })

    bus:On("UNIT_SPELLCAST_CHANNEL_START", function(event, _, castGUID, spellID)
        local t = now()
        local channel = Calls.Call(env, "UnitChannelInfo", "player")
        local startMs, endMs = channel.ok and channel.values[4], channel.ok and channel.values[5]
        local duration
        if type(startMs) == "number" and type(endMs) == "number" then
            duration = (endMs - startMs) / 1000
        end
        local guid = Redact.Value(castGUID)
        log("cast", {
            spellID = spellID,
            castGUID = guid,
            spellInfo = Calls.Call(env, "C_Spell.GetSpellInfo", spellID),
            channel = channel,
            duration = duration,
        }, "Q06")
        log("context", ns.Context.Collect(env), "Q07")
        feed(
            { t = t, name = event, spellID = spellID, castGUID = guid, duration = duration },
            Attempt.MAX_AGE
        )
    end, "player")

    for _, spec in ipairs(Recorders.ATTEMPT_EVENTS) do
        bus:On(spec[1], function(event, _, _, spellID)
            feed({ t = now(), name = event, spellID = spec[2] and spellID or nil })
        end, spec[2] and "player" or nil)
    end

    local function onMessage(event, messageType, text)
        feed({ t = now(), name = event, msgName = ctx.messageName(messageType, text) })
    end
    bus:On("UI_ERROR_MESSAGE", onMessage)
    bus:On("UI_INFO_MESSAGE", onMessage)

    local function itemInfo(itemID)
        if state.items[itemID] then
            return
        end
        local info = Loot.ItemInfo(env, itemID)
        if info.cached then
            state.items[itemID] = { done = true }
            log("item_info", info, "Q24")
            return
        end
        state.items[itemID] = { requested = now() }
        info.request = Calls.Call(env, "C_Item.RequestLoadItemDataByID", itemID)
        log("item_info", info, "Q24")
    end

    local function onLoot(event, autoLoot)
        local record, itemIDs = Loot.Collect(env)
        record.event = event
        record.autoLoot = autoLoot
        log("loot", record, "Q09")
        for _, itemID in ipairs(itemIDs) do
            itemInfo(itemID)
        end
        feed(
            { t = now(), name = event, isFishingLoot = Loot.IsFishing(record) },
            Attempt.MAX_LOOT_AGE
        )
    end
    bus:On("LOOT_READY", onLoot)
    bus:On("LOOT_OPENED", function(event)
        local call = Calls.Call(env, "IsFishingLoot")
        feed({ t = now(), name = event, isFishingLoot = Loot.IsFishing({ isFishingLoot = call }) })
    end)

    bus:On("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
        local pending = not isSecret(itemID) and state.items[itemID]
        if not pending or pending.done then
            return
        end
        pending.done = true
        local info = Loot.ItemInfo(env, itemID)
        info.loadSuccess = success
        info.wait = now() - pending.requested
        log("item_info", info, "Q24")
    end)

    function state.onTooltip(tooltip)
        local current = classifier.current
        if not current then
            return
        end
        local lines = Recorders.TooltipLines(env, tooltip, ctx.ownName)
        if not lines then
            return
        end
        local seen = tooltipsSeen[current.id] or { count = 0 }
        tooltipsSeen[current.id] = seen
        local key = isSecret(lines.line1) and "<secret>" or lines.line1
        if seen[key] or seen.count >= Recorders.MAX_TOOLTIPS_PER_ATTEMPT then
            return
        end
        seen[key], seen.count = true, seen.count + 1
        lines.attempt = current.id
        log("tooltip", lines, "Q26")
    end

    log("recorders_started", bus:Summary())
    return state
end

-- Hooks the game tooltip (TooltipDataProcessor when present, else OnShow). Game only.
function Recorders.HookTooltip(env, state)
    local tooltip = env.GameTooltip
    if type(tooltip) ~= "table" then
        return "no_tooltip"
    end
    local handler = ns.Guard.Wrap("tooltip", function(tip)
        if tip == tooltip then
            state.onTooltip(tip)
        end
    end)
    local processor = env.TooltipDataProcessor
    if type(processor) == "table" and processor.AddTooltipPostCall and processor.AllTypes then
        processor.AddTooltipPostCall(processor.AllTypes, handler)
        return "post_call"
    end
    if tooltip.HookScript then
        tooltip:HookScript("OnShow", handler)
        return "on_show"
    end
    return "none"
end
