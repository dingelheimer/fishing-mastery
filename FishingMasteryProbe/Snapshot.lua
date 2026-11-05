-- Login snapshot (step S0): records the client environment without player actions.
-- Answers Q01-Q05, Q20-Q22, and Q29. Reads from an injected environment (_G in game) so the
-- whole run is testable; every collector runs through Guard so one failure skips one topic.
local _, ns = ...

local type, pairs, ipairs = type, pairs, ipairs
local sort, sub = table.sort, string.sub
local isSecret = issecretvalue or function()
    return false
end

local Scan, Redact = ns.Scan, ns.Redact
local invoke, call = ns.Calls.Invoke, ns.Calls.Call

local Snapshot = {}
ns.Snapshot = Snapshot

Snapshot.KIND = "snapshot"
Snapshot.GLOBAL_STRING_CAP = 500
Snapshot.CHUNK_SIZE = 100
Snapshot.MAX_ENUM_VALUES = 16 -- argument values tried per C_RestrictedActions getter
Snapshot.GETTER_PREFIXES = { "Is", "Get", "Has" }

local function itemsToMap(items)
    local map = {}
    for i = 1, #items do
        map[items[i].name] = items[i].value
    end
    return map
end

local function isGetter(name)
    for _, prefix in ipairs(Snapshot.GETTER_PREFIXES) do
        if sub(name, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local collectors = {}

-- Q01: version, build, date, interface number.
function collectors.build(env, ctx)
    local result = call(env, "GetBuildInfo")
    local values = result.ok and result.values or {}
    ctx.log({
        topic = "build",
        call = result,
        version = values[1],
        build = values[2],
        date = values[3],
        interface = values[4],
    }, "Q01")
end

-- Q02: WOW_PROJECT_ID and every WOW_PROJECT_* global.
function collectors.project(env, ctx)
    local constants = Scan.Collect(env, Scan.NameStartsWith("WOW_PROJECT_"))
    ctx.log({
        topic = "project",
        id = Scan.Resolve(env, "WOW_PROJECT_ID"),
        constants = itemsToMap(constants.items),
        total = constants.total,
    }, "Q02")
end

-- Q03: C_GameRules members and the experience preset.
function collectors.game_rules(env, ctx)
    ctx.log({
        topic = "game_rules",
        members = Scan.Members(Scan.Resolve(env, "C_GameRules")),
        preset = call(env, "C_GameRules.GetForeverExperiencePreset"),
        globalPreset = call(env, "GetForeverExperiencePreset"),
        enumGameRule = Scan.Members(Scan.Resolve(env, "Enum.GameRule")),
    }, "Q03")
end

-- Q20: game time, server time, calendar time.
function collectors.time(env, ctx)
    ctx.log({
        topic = "time",
        gameTime = call(env, "GetGameTime"),
        serverTime = call(env, "GetServerTime"),
        calendarTime = call(env, "C_DateAndTime.GetCurrentCalendarTime"),
    }, "Q20")
end

-- Numeric values of every Enum table whose name contains "Restriction", sorted and capped.
local function restrictionEnumValues(env)
    local enums =
        Scan.Collect(Scan.Resolve(env, "Enum"), Scan.NameContains({ "Restriction" }, "table"))
    local seen, values = {}, {}
    for i = 1, #enums.items do
        for _, value in pairs(enums.items[i].value) do
            if not isSecret(value) and type(value) == "number" and not seen[value] then
                seen[value] = true
                values[#values + 1] = value
            end
        end
    end
    sort(values)
    while #values > Snapshot.MAX_ENUM_VALUES do
        values[#values] = nil
    end
    local tables = {}
    for i = 1, #enums.items do
        tables[enums.items[i].name] = enums.items[i].value
    end
    return values, tables
end

-- Q29: C_RestrictedActions members, related enums, and getter results. Only functions named
-- Is*, Get*, or Has* are called: once without arguments, and with each enum value if that fails.
function collectors.restricted_actions(env, ctx)
    local namespace = Scan.Resolve(env, "C_RestrictedActions")
    local members = Scan.Members(namespace)
    local enumValues, enumTables = restrictionEnumValues(env)
    ctx.log({
        topic = "restricted_actions",
        members = members,
        enums = enumTables,
    }, "Q29")
    local names = {}
    for name, kind in pairs(members or {}) do
        if kind == "function" and isGetter(name) then
            names[#names + 1] = name
        end
    end
    sort(names)
    for _, name in ipairs(names) do
        local path = "C_RestrictedActions." .. name
        local entry = { topic = "restricted_getter", name = name, noArgs = call(env, path) }
        if not entry.noArgs.ok and #enumValues > 0 then
            entry.byValue = {}
            for _, value in ipairs(enumValues) do
                entry.byValue[value] = call(env, path, value)
            end
        end
        ctx.log(entry, "Q29")
    end
end

-- Q04: existence of every API and namespace in ApiList, one entry per group.
function collectors.api_scan(env, ctx)
    for _, group in ipairs(ns.ApiList.GROUPS) do
        local result = Scan.Existence(env, group.names)
        local missing = 0
        for _, kind in pairs(result) do
            if kind == "nil" then
                missing = missing + 1
            end
        end
        ctx.log({
            topic = "api_scan",
            group = group.name,
            result = result,
            total = #group.names,
            missing = missing,
        }, "Q04")
    end
end

-- Q04: whether each planned event can be registered; results are kept for the recorders.
function collectors.event_scan(env, ctx)
    local events = ns.ApiList.EVENTS
    for _, chunk in ipairs(Scan.Chunk(events, Snapshot.CHUNK_SIZE)) do
        local result = {}
        for _, event in ipairs(chunk) do
            local ok, err = ctx.registerEvent(event)
            ctx.events[event] = ok and true or false
            result[event] = { registered = ok and true or false, err = err }
            local valid = call(env, "C_EventUtils.IsEventValid", event)
            if valid.exists then
                result[event].valid = valid.values[1]
            end
        end
        ctx.log({ topic = "event_scan", result = result, total = #events }, "Q04")
    end
end

-- Q05: string globals whose name contains FISH or LURE, in chunks.
function collectors.global_strings(env, ctx)
    local found = Scan.Collect(
        env,
        Scan.NameContains({ "FISH", "LURE" }, "string"),
        Snapshot.GLOBAL_STRING_CAP
    )
    local chunks = Scan.Chunk(found.items, Snapshot.CHUNK_SIZE)
    if #chunks == 0 then
        chunks[1] = {}
    end
    for index, chunk in ipairs(chunks) do
        local items = {}
        for i = 1, #chunk do
            items[i] = { name = chunk[i].name, text = chunk[i].value }
        end
        ctx.log({
            topic = "global_strings",
            chunk = index,
            chunks = #chunks,
            total = found.total,
            cut = found.cut,
            items = items,
        }, "Q05")
    end
end

-- Redacted name/realm pair from UnitName or UnitFullName.
local function redactPair(env, path)
    local exists, ok, name, realm = invoke(env, path, "player")
    if not exists then
        return { exists = false }
    end
    if not ok then
        return { exists = true, ok = false }
    end
    return { exists = true, ok = true, name = Redact.Text(name), realm = Redact.Text(realm) }
end

local function redactSingle(env, path, redact, ...)
    local exists, ok, value = invoke(env, path, ...)
    if not exists then
        return { exists = false }
    end
    if not ok then
        return { exists = true, ok = false }
    end
    return { exists = true, ok = true, value = redact(value) }
end

-- Q21: character key format, reduced to shape facts.
function collectors.character_key(env, ctx)
    ctx.log({
        topic = "character_key",
        unitName = redactPair(env, "UnitName"),
        unitFullName = redactPair(env, "UnitFullName"),
        realmName = redactSingle(env, "GetRealmName", Redact.Text),
        normalizedRealmName = redactSingle(env, "GetNormalizedRealmName", Redact.Text),
        guid = redactSingle(env, "UnitGUID", Redact.Guid, "player"),
    }, "Q21")
end

-- Q22: whether the previous session's marker survived.
function collectors.persistence(_, ctx)
    ctx.log({ topic = "persistence", marker = ctx.persistence }, "Q22")
end

Snapshot.ORDER = {
    "build",
    "project",
    "game_rules",
    "time",
    "restricted_actions",
    "api_scan",
    "event_scan",
    "global_strings",
    "character_key",
    "persistence",
}

-- deps.log(kind, data, q) writes one entry; deps.registerEvent(event) returns ok, err;
-- deps.persistence is the Db.Mark result. Returns { count, events = { [event] = bool } }.
function Snapshot.Run(env, deps)
    local result = { count = 0, events = {} }
    local ctx = {
        events = result.events,
        persistence = deps.persistence,
        registerEvent = deps.registerEvent,
    }
    function ctx.log(data, q)
        result.count = result.count + 1
        return deps.log(Snapshot.KIND, data, q)
    end
    for _, topic in ipairs(Snapshot.ORDER) do
        ns.Guard.Call("snapshot:" .. topic, collectors[topic], env, ctx)
    end
    local supported = 0
    for _, ok in pairs(result.events) do
        if ok then
            supported = supported + 1
        end
    end
    result.supported = supported
    ctx.log({ topic = "done", entries = result.count, eventsSupported = supported })
    return result
end
