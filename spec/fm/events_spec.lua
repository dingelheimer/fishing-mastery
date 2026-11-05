local addon = require("spec.helpers.addon")

describe("FishingMastery Events and Guard", function()
    local ns, frame

    before_each(function()
        ns = addon.load({ "Guard.lua", "Events.lua" }, nil, "FishingMastery")
        frame = { registered = {} }
        function frame:RegisterEvent(event)
            if event == "BAD_EVENT" then
                error("Attempt to register unknown event")
            end
            self.registered[event] = true
        end
        function frame:UnregisterEvent(event)
            self.registered[event] = nil
        end
    end)

    it("registers once and calls every handler in order", function()
        local bus = ns.Events.New(frame)
        local calls = {}
        bus:On("LOOT_READY", function(event, arg)
            calls[#calls + 1] = "a:" .. event .. ":" .. tostring(arg)
        end)
        bus:On("LOOT_READY", function()
            calls[#calls + 1] = "b"
        end)
        bus:Dispatch("LOOT_READY", true)
        assert.are.same({ "a:LOOT_READY:true", "b" }, calls)
        assert.are.same({ "LOOT_READY" }, bus:Summary().subscribed)
    end)

    it("skips events the client cannot register", function()
        local bus = ns.Events.New(frame)
        assert.is_false(bus:On("BAD_EVENT", function() end))
        assert.truthy(bus:Summary().failed.BAD_EVENT:find("unknown event", 1, true))
        bus:Dispatch("BAD_EVENT")
        assert.are.equal(0, ns.Guard.errors)
    end)

    it("unregisters an event with Off", function()
        local bus = ns.Events.New(frame)
        local count = 0
        bus:On("ADDON_LOADED", function()
            count = count + 1
            bus:Off("ADDON_LOADED")
        end)
        bus:Dispatch("ADDON_LOADED")
        bus:Dispatch("ADDON_LOADED")
        assert.are.equal(1, count)
        assert.is_nil(frame.registered.ADDON_LOADED)
        bus:Off("NEVER_REGISTERED")
    end)

    it("filters unit events to the player", function()
        local bus = ns.Events.New(frame)
        local units = {}
        bus:On("UNIT_AURA", function(_, unit)
            units[#units + 1] = unit
        end, "player")
        bus:Dispatch("UNIT_AURA", "target")
        bus:Dispatch("UNIT_AURA", "player")
        assert.are.same({ "player" }, units)
    end)

    it("isolates handler errors and hands them to the sink", function()
        local bus = ns.Events.New(frame)
        local records, reached = {}, false
        ns.Guard.SetSink(function(record)
            records[#records + 1] = record
        end)
        bus:On("X", function()
            error("boom")
        end)
        bus:On("X", function()
            reached = true
        end)
        bus:Dispatch("X")
        assert.is_true(reached)
        assert.are.equal(1, ns.Guard.errors)
        assert.are.equal("event:X", records[1].where)
        assert.truthy(records[1].msg:find("boom", 1, true))
    end)
end)
