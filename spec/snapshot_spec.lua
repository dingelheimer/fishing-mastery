local addon = require("spec.helpers.addon")

local FILES = {
    "Serializer.lua",
    "Logger.lua",
    "Guard.lua",
    "Db.lua",
    "Scan.lua",
    "Calls.lua",
    "Redact.lua",
    "ApiList.lua",
    "Snapshot.lua",
}

local NAME, REALM, GUID = "Synthia Brook", "Testrealm", "Player-4321-0ABCDEF9"

-- A fake client environment with synthetic player data.
local function fakeEnv()
    local calls = {}
    local env = {
        GetBuildInfo = function()
            return "1.60.1", "70500", "Nov 1 2026", 16001
        end,
        WOW_PROJECT_ID = 18,
        WOW_PROJECT_CAMELOT = 18,
        WOW_PROJECT_MAINLINE = 1,
        C_GameRules = {
            GetForeverExperiencePreset = function()
                return 1
            end,
            IsGameRuleActive = function()
                error("must not be called")
            end,
        },
        GetGameTime = function()
            return 14, 30
        end,
        GetServerTime = function()
            return 1793800000
        end,
        C_DateAndTime = {
            GetCurrentCalendarTime = function()
                return { year = 2026, month = 11, monthDay = 4, hour = 14, minute = 30 }
            end,
        },
        Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1 } },
        C_RestrictedActions = {
            IsAddOnRestrictionActive = function(kind)
                calls[#calls + 1] = kind
                assert(type(kind) == "number", "needs a type")
                return kind == 1
            end,
            GetAddOnRestrictionState = function()
                return 0
            end,
            SetSomething = function()
                error("must not be called")
            end,
        },
        IsFishingLoot = function()
            error("must not be called")
        end,
        C_EventUtils = {
            IsEventValid = function(event)
                return event ~= "UNIT_SPELLCAST_FAILED_QUIET"
            end,
        },
        ERR_FISH_ESCAPED = "Your fish got away!",
        ERR_FISH_NOT_HOOKED = "No fish are hooked.",
        UnitName = function()
            return NAME, nil
        end,
        UnitFullName = function()
            return NAME, REALM
        end,
        GetRealmName = function()
            return REALM
        end,
        UnitGUID = function(unit)
            assert(unit == "player")
            return GUID
        end,
    }
    return env, calls
end

-- Flattens a value into one string so tests can search the whole log for leaks.
local function dump(value, out)
    out = out or {}
    if type(value) == "table" then
        for key, child in pairs(value) do
            dump(key, out)
            dump(child, out)
        end
    else
        out[#out + 1] = tostring(value)
    end
    return table.concat(out, "|")
end

describe("Snapshot", function()
    local ns, store, logger, result, env, restrictedCalls

    local function run(customEnv, registerEvent)
        ns = addon.load(FILES)
        store = {}
        logger = ns.Logger.New(store, {
            now = function()
                return 0
            end,
            sanitize = ns.Serializer.Sanitize,
        })
        logger:SetStep("S5")
        ns.Guard.SetSink(function(record)
            logger:Log("lua_error", record)
        end)
        result = ns.Snapshot.Run(customEnv, {
            log = function(kind, data, q)
                return logger:Log(kind, data, q, "S0")
            end,
            registerEvent = registerEvent or function(event)
                if event == "UNIT_SPELLCAST_FAILED_QUIET" then
                    return false, "Attempt to register unknown event"
                end
                return true
            end,
            persistence = { found = true, previousSessionId = "abc", sessions = 2 },
        })
    end

    local function topic(name)
        local found = {}
        for _, entry in ipairs(store.entries) do
            if entry.kind == "snapshot" and entry.data.topic == name then
                found[#found + 1] = entry
            end
        end
        return found
    end

    before_each(function()
        env, restrictedCalls = fakeEnv()
        run(env)
    end)

    it("logs every topic as step S0 with its question ID and no errors", function()
        local expected = {
            build = "Q01",
            project = "Q02",
            game_rules = "Q03",
            time = "Q20",
            restricted_actions = "Q29",
            api_scan = "Q04",
            event_scan = "Q04",
            global_strings = "Q05",
            character_key = "Q21",
            persistence = "Q22",
        }
        for name, q in pairs(expected) do
            local entries = topic(name)
            assert(#entries > 0, name)
            assert.are.equal(q, entries[1].q)
            assert.are.equal("S0", entries[1].step)
        end
        assert.are.equal(0, ns.Guard.errors)
        assert.are.equal(#store.entries, result.count)
        assert.are.equal(1, #topic("done"))
    end)

    it("records build info, project constants, and the preset", function()
        local build = topic("build")[1].data
        assert.are.equal(16001, build.interface)
        assert.are.equal("70500", build.build)
        local project = topic("project")[1].data
        assert.are.equal(18, project.id)
        assert.are.same(
            { WOW_PROJECT_CAMELOT = 18, WOW_PROJECT_ID = 18, WOW_PROJECT_MAINLINE = 1 },
            project.constants
        )
        local rules = topic("game_rules")[1].data
        assert.are.equal(1, rules.preset.values[1])
        assert.are.equal("function", rules.members.IsGameRuleActive)
        assert.is_false(rules.globalPreset.exists)
    end)

    it("records time APIs", function()
        local time = topic("time")[1].data
        assert.are.same({ n = 2, 14, 30 }, time.gameTime.values)
        assert.are.equal(1793800000, time.serverTime.values[1])
        assert.are.equal(2026, time.calendarTime.values[1].year)
    end)

    it("calls only restricted-action getters, retrying with enum values", function()
        local getters = topic("restricted_getter")
        assert.are.equal(2, #getters)
        local active = getters[2].data
        assert.are.equal("IsAddOnRestrictionActive", active.name)
        assert.is_false(active.noArgs.ok)
        assert.is_false(active.byValue[0].values[1])
        assert.is_true(active.byValue[1].values[1])
        assert.are.same({ 0, 1 }, restrictedCalls)
        assert.are.equal(0, getters[1].data.noArgs.values[1])
        assert.are.equal("function", topic("restricted_actions")[1].data.members.SetSomething)
    end)

    it("scans every API group without calling functions", function()
        local scans = topic("api_scan")
        assert.are.equal(#ns.ApiList.GROUPS, #scans)
        for _, entry in ipairs(scans) do
            if entry.data.group == "loot" then
                assert.are.equal("function", entry.data.result.IsFishingLoot)
                assert.are.equal("nil", entry.data.result.GetLootSourceInfo)
            end
        end
    end)

    it("keeps every API group and the event list under the serializer key cap", function()
        for _, group in ipairs(ns.ApiList.GROUPS) do
            assert(#group.names < ns.Serializer.DEFAULTS.maxKeys, group.name)
        end
        assert(#ns.ApiList.EVENTS <= ns.Snapshot.CHUNK_SIZE)
    end)

    it("records event registration and keeps the support table", function()
        local scan = topic("event_scan")[1].data.result
        assert.is_true(scan.LOOT_READY.registered)
        assert.is_true(scan.LOOT_READY.valid)
        assert.is_false(scan.UNIT_SPELLCAST_FAILED_QUIET.registered)
        assert.are.equal("Attempt to register unknown event", scan.UNIT_SPELLCAST_FAILED_QUIET.err)
        assert.is_false(result.events.UNIT_SPELLCAST_FAILED_QUIET)
        assert.is_true(result.events.UNIT_AURA)
        assert.are.equal(#ns.ApiList.EVENTS - 1, result.supported)
    end)

    it("records FISH and LURE global strings with their text", function()
        local strings = topic("global_strings")[1].data
        assert.are.equal(2, strings.total)
        assert.are.same(
            { name = "ERR_FISH_ESCAPED", text = "Your fish got away!" },
            strings.items[1]
        )
    end)

    it("chunks and caps a large global string scan at 500", function()
        local big = fakeEnv()
        for i = 1, 650 do
            big[string.format("FISH_%04d", i)] = "text"
        end
        run(big)
        local chunks = topic("global_strings")
        assert.are.equal(5, #chunks)
        assert.are.equal(652, chunks[1].data.total)
        assert.are.equal(152, chunks[1].data.cut)
        assert.are.equal(100, #chunks[1].data.items)
    end)

    it("reduces the character key to shape facts", function()
        local key = topic("character_key")[1].data
        assert.are.same(
            { present = true, length = 13, hasSpace = true, hasHyphen = false },
            key.unitName.name
        )
        assert.are.same({ present = false, type = "nil" }, key.unitName.realm)
        assert.is_true(key.unitFullName.realm.present)
        assert.are.equal(9, key.realmName.value.length)
        assert.are.same({ present = true, type = "Player", segments = 3 }, key.guid.value)
        assert.is_false(key.normalizedRealmName.exists)
    end)

    it("never writes names, realm, or GUID into the log", function()
        local text = dump(store)
        assert.is_nil(text:find("Synthia", 1, true))
        assert.is_nil(text:find(REALM, 1, true))
        assert.is_nil(text:find("4321", 1, true))
        assert.is_nil(text:find("0ABCDEF9", 1, true))
        assert.is_nil(text:find("<depth>", 1, true), "a record exceeds the serializer depth cap")
    end)

    it("records the persistence marker", function()
        assert.are.same(
            { found = true, previousSessionId = "abc", sessions = 2 },
            topic("persistence")[1].data.marker
        )
    end)

    it("continues after a failing topic and logs the error", function()
        run(fakeEnv(), function()
            error("register failed")
        end)
        assert.are.equal(1, ns.Guard.errors)
        assert.are.equal(1, #topic("done"))
        assert.are.equal(1, #topic("character_key"))
        local errors = 0
        for _, entry in ipairs(store.entries) do
            if entry.kind == "lua_error" then
                errors = errors + 1
                assert.are.equal("snapshot:event_scan", entry.data.where)
            end
        end
        assert.are.equal(1, errors)
    end)

    it("handles an empty client without errors", function()
        run({})
        assert.are.equal(0, ns.Guard.errors)
        assert.is_false(topic("build")[1].data.call.exists)
        assert.are.equal(0, topic("global_strings")[1].data.total)
    end)
end)
