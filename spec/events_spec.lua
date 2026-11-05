local addon = require("spec.helpers.addon")

describe("Events", function()
    local ns, frame

    before_each(function()
        ns = addon.load({ "Guard.lua", "Events.lua" })
        frame = { registered = {} }
        function frame:RegisterEvent(event)
            if event == "BAD_EVENT" then
                error("Attempt to register unknown event")
            end
            self.registered[event] = true
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
        assert.is_true(frame.registered.LOOT_READY)
    end)

    it("skips unsupported events and reports failed registrations", function()
        local bus = ns.Events.New(frame, { UNSUPPORTED = false })
        assert.is_false(bus:On("UNSUPPORTED", function() end))
        assert.is_false(bus:On("BAD_EVENT", function() end))
        local summary = bus:Summary()
        assert.are.same({ "UNSUPPORTED" }, summary.skipped)
        assert.truthy(summary.failed.BAD_EVENT:find("unknown event", 1, true))
    end)

    it("filters unit events without RegisterUnitEvent", function()
        local bus = ns.Events.New(frame)
        local units = {}
        bus:On("UNIT_AURA", function(_, unit)
            units[#units + 1] = unit
        end, "player")
        bus:Dispatch("UNIT_AURA", "target")
        bus:Dispatch("UNIT_AURA", "player")
        assert.are.same({ "player" }, units)
    end)

    it("isolates handler errors", function()
        local bus = ns.Events.New(frame)
        local reached = false
        bus:On("X", function()
            error("boom")
        end)
        bus:On("X", function()
            reached = true
        end)
        bus:Dispatch("X")
        assert.is_true(reached)
        assert.are.equal(1, ns.Guard.errors)
    end)
end)
