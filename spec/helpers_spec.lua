local addon = require("spec.helpers.addon")
local fakeui = require("spec.helpers.fakeui")

-- Synthetic own character; neither part may appear in the log.
local NAME, REALM = "Testchar", "Otherrealm"

describe("Helpers (S14)", function()
    local ns, env, bus, helpers, logged, timers, clock, combat, bindings, sent, changes

    local function setup(opts)
        opts = opts or {}
        env = fakeui.new(opts.ui)
        ns = addon.load({
            "Locale.lua",
            "Serializer.lua",
            "Guard.lua",
            "Scan.lua",
            "Calls.lua",
            "Redact.lua",
            "Events.lua",
            "SecureKey.lua",
            "AddonMessage.lua",
            "Helpers.lua",
            "Steps.lua",
            "Progress.lua",
            "View.lua",
        })
        logged, timers, clock, combat, bindings, sent, changes = {}, {}, 100, false, {}, {}, 0
        env.InCombatLockdown = function()
            return combat
        end
        env.SetOverrideBindingClick = function(owner, priority, key, name, mouseButton)
            bindings[key] = { owner = owner, priority = priority, name = name, mouse = mouseButton }
        end
        env.ClearOverrideBindings = function(owner)
            for key, binding in pairs(bindings) do
                if binding.owner == owner then
                    bindings[key] = nil
                end
            end
        end
        env.GetProfessions = function()
            return 1, 2, nil, 4, 5
        end
        env.GetProfessionInfo = function(index)
            if index == 4 then
                return "Fishing", 136245, 75, 300
            end
        end
        env.C_Spell = {
            GetSpellInfo = function(id)
                if id == 7620 then
                    return { name = "Fishing", spellID = 7620 }
                end
                return { name = "Other", spellID = id }
            end,
        }
        env.GetCVar = function()
            return "1"
        end
        env.UnitName = function()
            if opts.noRealm then
                return NAME
            end
            return NAME, REALM
        end
        env.C_ChatInfo = {
            RegisterAddonMessagePrefix = function()
                return 0
            end,
            IsAddonMessagePrefixRegistered = function()
                return true
            end,
            SendAddonMessage = function(prefix, text, channel, target)
                sent[#sent + 1] = { prefix, text, channel, target }
                if opts.sendError then
                    error("cannot whisper " .. target)
                end
                return 0
            end,
        }
        for key, value in pairs(opts.env or {}) do
            env[key] = value ~= false and value or nil
        end
        bus = ns.Events.New({
            RegisterEvent = function()
                return true
            end,
        })
        helpers = ns.Helpers.New({
            env = env,
            bus = bus,
            log = function(kind, data, q)
                logged[#logged + 1] = { kind = kind, data = ns.Serializer.Sanitize(data), q = q }
            end,
            now = function()
                return clock
            end,
            after = function(seconds, fn)
                timers[#timers + 1] = { at = clock + seconds, fn = fn }
            end,
            fishingSpellID = function()
                return opts.spellID
            end,
            onChange = function()
                changes = changes + 1
            end,
        })
    end

    local function wait(seconds)
        clock = clock + seconds
        local due = timers
        timers = {}
        for _, timer in ipairs(due) do
            if timer.at <= clock then
                timer.fn()
            else
                timers[#timers + 1] = timer
            end
        end
    end

    local function entries(kind)
        local list = {}
        for _, entry in ipairs(logged) do
            if entry.kind == kind then
                list[#list + 1] = entry
            end
        end
        return list
    end

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
        return out
    end

    local function assertNoNames()
        local text = table.concat(dump(logged), "\n")
        assert.is_nil(text:find(NAME, 1, true))
        assert.is_nil(text:find(REALM, 1, true))
    end

    local function button()
        return env[ns.SecureKey.BUTTON_NAME]
    end

    it("logs the helper environment once, incl. loadstring_untainted", function()
        setup()
        local entry = entries("helpers_env")[1]
        assert.are.equal("Q28", entry.q)
        assert.are.equal("nil", entry.data.apis.loadstring_untainted)
        assert.are.equal("function", entry.data.apis.SetOverrideBindingClick)
        assert.are.equal("CTRL-SHIFT-F", entry.data.key)
        assert.is_false(entry.data.inCombat)

        setup({ env = { loadstring_untainted = function() end } })
        assert.are.equal("function", entries("helpers_env")[1].data.apis.loadstring_untainted)
    end)

    describe("S14a test key", function()
        it("binds a secure Fishing button, logs a cast after the press, and unbinds", function()
            setup()
            assert.is_nil(button())
            assert.is_true(helpers:EnableKey())
            local b = button()
            assert.are.equal("SecureActionButtonTemplate", b.template)
            assert.are.equal("spell", b:GetAttribute("type"))
            assert.are.equal("Fishing", b:GetAttribute("spell"))
            assert.are.same({ "AnyUp", "AnyDown" }, b.clicks)
            local binding = bindings["CTRL-SHIFT-F"]
            assert.are.equal(b, binding.owner)
            assert.is_true(binding.priority)
            assert.are.equal("FishingMasteryProbeTestButton", binding.name)
            local enable = entries("probe_key")[1]
            assert.are.equal("enable", enable.data.action)
            assert.is_true(enable.data.bound)
            assert.are.equal("profession", enable.data.spellSource)
            assert.are.equal("active", helpers:Status().key)

            b:PressKey(true)
            assert.are.equal("waiting", helpers:Status().key)
            wait(0.5)
            bus:Dispatch("UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 7620)
            assert.are.equal(0, #entries("probe_check"))
            bus:Dispatch("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)

            local result = entries("probe_check")[1]
            assert.are.equal("Q28", result.q)
            assert.are.equal("S14a", result.data.test)
            assert.is_true(result.data.channelStarted)
            assert.is_true(result.data.matchesSpell)
            assert.are.equal(0.5, result.data.delay)
            assert.are.equal(1, result.data.presses)
            assert.is_nil(bindings["CTRL-SHIFT-F"])
            assert.are.equal("checked", entries("probe_key")[3].data.reason)
            assert.are.equal("done", helpers:Status().key)
            assert.is_true(helpers:Status().keyResult)

            -- A second channel or a timer after the result logs nothing more.
            wait(3)
            bus:Dispatch("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
            assert.are.equal(1, #entries("probe_check"))
            assert.are.equal(0, ns.Guard.errors)
        end)

        it("prefers the spell of a recorded catch and compares by spell ID", function()
            setup({ spellID = 7620 })
            helpers:EnableKey()
            assert.are.equal("Fishing", button():GetAttribute("spell"))
            assert.are.equal("catch_name", entries("probe_key")[1].data.spellSource)
            button():PressKey(false)
            bus:Dispatch("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 1234)
            assert.is_false(entries("probe_check")[1].data.matchesSpell)
        end)

        it("logs no cast when nothing starts within 2 seconds", function()
            setup()
            helpers:EnableKey()
            button():PressKey(true)
            wait(2.05)
            bus:Dispatch("UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 7620)
            assert.are.equal(0, #entries("probe_check"))
            wait(0.1)
            local result = entries("probe_check")[1]
            assert.is_false(result.data.channelStarted)
            assert.is_nil(bindings["CTRL-SHIFT-F"])
            assert.is_false(helpers:Status().keyResult)
        end)

        it("is skipped in combat and shows why", function()
            setup()
            combat = true
            assert.is_false(helpers:EnableKey())
            assert.is_nil(button())
            assert.is_nil(next(bindings))
            assert.are.same({ test = "S14a", reason = "combat" }, entries("probe_skip")[1].data)
            assert.are.equal(0, #entries("probe_check"))
            local lines = ns.View.Helpers(helpers:Status())
            assert.truthy(lines[1]:find("in combat", 1, true))

            combat = false
            assert.is_true(helpers:EnableKey())
            assert.is_table(bindings["CTRL-SHIFT-F"])
        end)

        it("removes the key when S14 ends, deferred while in combat", function()
            setup()
            local store = { step = "S14" }
            local progress = ns.Progress.New(store, ns.Steps, { log = function() end })
            progress:Start()
            helpers:EnableKey()
            helpers:Sync(progress)
            assert.is_table(bindings["CTRL-SHIFT-F"])

            combat = true
            progress:Back()
            helpers:Sync(progress)
            assert.is_table(bindings["CTRL-SHIFT-F"])
            assert.are.equal("clear_deferred", entries("probe_key")[2].data.action)
            bus:Dispatch("PLAYER_REGEN_ENABLED")
            assert.is_table(bindings["CTRL-SHIFT-F"])
            combat = false
            bus:Dispatch("PLAYER_REGEN_ENABLED")
            assert.is_nil(bindings["CTRL-SHIFT-F"])
            assert.are.equal("step_end", entries("probe_key")[3].data.reason)
            -- Unbound keys ignore presses.
            button():PressKey(true)
            assert.are.equal(3, #entries("probe_key"))
        end)

        it("removes the key on logout", function()
            setup()
            helpers:EnableKey()
            helpers:Shutdown()
            assert.is_nil(bindings["CTRL-SHIFT-F"])
            assert.are.equal("logout", entries("probe_key")[2].data.reason)
            assert.are.equal("off", helpers:Status().key)
        end)

        it("logs a result when the template, the spell, or the binding API is missing", function()
            setup({ ui = { missingTemplates = { SecureActionButtonTemplate = true } } })
            assert.is_false(helpers:EnableKey())
            local result = entries("probe_check")[1]
            assert.is_false(result.data.template)
            assert.truthy(result.data.error:find("Couldn't find", 1, true))
            assert.are.equal("failed", helpers:Status().key)

            setup({ env = { GetProfessions = false } })
            assert.is_false(helpers:EnableKey())
            assert.are.equal("no_spell", entries("probe_check")[1].data.reason)
            assert.is_nil(next(bindings))

            setup({ env = { SetOverrideBindingClick = false } })
            assert.is_false(helpers:EnableKey())
            assert.is_false(entries("probe_check")[1].data.bound)
            assert.is_false(entries("probe_key")[1].data.bindExists)
            assert.are.equal(0, ns.Guard.errors)
        end)
    end)

    describe("S14b self-whisper", function()
        it("whispers the fixed text to the own character and logs the receipt", function()
            setup()
            assert.is_true(helpers:SendWhisper())
            assert.are.same(
                { { "FMProbe", "FMProbe self-test 1", "WHISPER", NAME .. "-" .. REALM } },
                sent
            )
            assert.are.equal("waiting", helpers:Status().whisper)

            local before = #logged
            bus:Dispatch("CHAT_MSG_ADDON", "OtherAddon", "secret plans", "GUILD", "Someone")
            assert.are.equal(before, #logged)
            wait(0.25)
            bus:Dispatch("CHAT_MSG_ADDON", "FMProbe", "FMProbe self-test 1", "WHISPER", NAME)

            local result = entries("probe_check")[1]
            assert.are.equal("Q27", result.q)
            assert.are.equal("S14b", result.data.test)
            assert.is_true(result.data.received)
            assert.is_true(result.data.fromSelf)
            assert.is_true(result.data.sameText)
            assert.is_false(result.data.senderHasRealm)
            assert.are.equal("WHISPER", result.data.channel)
            assert.are.equal(0.25, result.data.delay)
            assert.are.equal(0, result.data.register.values[1])
            assert.is_true(result.data.send.realmPart)
            assert.is_true(helpers:Status().whisperResult)
            -- The timeout of the finished round logs nothing more.
            wait(6)
            assert.are.equal(1, #entries("probe_check"))
            assertNoNames()
            assert.is_nil(table.concat(dump(logged), "\n"):find("secret plans", 1, true))
        end)

        it("logs a missing receipt after the timeout and a late one separately", function()
            setup({ noRealm = true })
            helpers:SendWhisper()
            assert.are.equal(NAME, sent[1][4])
            wait(5.2)
            local result = entries("probe_check")[1]
            assert.is_false(result.data.received)
            assert.is_false(helpers:Status().whisperResult)
            bus:Dispatch("CHAT_MSG_ADDON", "FMProbe", "FMProbe self-test 1", "WHISPER", NAME)
            assert.are.equal("late", entries("probe_message")[2].data.action)
            assert.are.equal(1, #entries("probe_check"))
            assertNoNames()
        end)

        it("is skipped in combat", function()
            setup()
            combat = true
            assert.is_false(helpers:SendWhisper())
            assert.are.equal(0, #sent)
            assert.are.same({ test = "S14b", reason = "combat" }, entries("probe_skip")[1].data)
            assert.truthy(ns.View.Helpers(helpers:Status())[2]:find("in combat", 1, true))
        end)

        it("redacts the own name from a send error", function()
            setup({ sendError = true })
            assert.is_false(helpers:SendWhisper())
            local result = entries("probe_check")[1]
            assert.is_false(result.data.send.ok)
            assert.truthy(result.data.send.result:find("<player>", 1, true))
            assertNoNames()
            assert.are.equal(0, ns.Guard.errors)
        end)

        it("logs a result when the client has no own name or no addon messages", function()
            setup({ env = { UnitName = false } })
            assert.is_false(helpers:SendWhisper())
            assert.are.equal("no_name", entries("probe_check")[1].data.reason)

            setup({ env = { C_ChatInfo = false } })
            assert.is_false(helpers:SendWhisper())
            local result = entries("probe_check")[1]
            assert.is_false(result.data.register.exists)
            assert.is_false(result.data.send.exists)
            assert.are.equal("failed", helpers:Status().whisper)
        end)
    end)

    it("renders a line per test for the window", function()
        setup()
        assert.are.same({
            "Test key (CTRL-SHIFT-F): off. Press Enable test key.",
            "Self-whisper: not sent yet.",
        }, ns.View.Helpers(helpers:Status()))
        assert.are.same({ ns.L.HELPERS_PENDING }, ns.View.Helpers(nil))
    end)
end)
