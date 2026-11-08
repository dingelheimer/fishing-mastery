-- DoubleClick.lua: the second press of a double-click into the world, with every case that is
-- no double-click (too slow, too fast, a held camera drag, units, frames, the bobber), and the
-- order of the reasons that block a cast.
local addon = require("spec.helpers.addon")

describe("FishingMastery double-click logic", function()
    local DoubleClick

    before_each(function()
        DoubleClick = addon.load({ "DoubleClick.lua" }, nil, "FishingMastery").DoubleClick
    end)

    it("takes the second world press within 0.4 s as a double-click", function()
        local c = DoubleClick.New()
        assert.are.same({ false, "first" }, { c:Down(10, "world") })
        c:Up(10.1)
        assert.are.same({ true, "double" }, { c:Down(10.3, "world") })
        -- The click after a double-click starts over.
        assert.are.same({ false, "first" }, { c:Down(10.5, "world") })
    end)

    it("is no double-click when too slow or too fast", function()
        local c = DoubleClick.New()
        c:Down(10, "world")
        assert.are.same({ false, "first" }, { c:Down(10.4, "world") }) -- 0.4 s is too slow
        assert.are.same({ false, "too-fast" }, { c:Down(10.43, "world") })
        assert.are.same({ true, "double" }, { c:Down(10.6, "world") })
    end)

    it("forgets a first press held for camera turning", function()
        local c = DoubleClick.New()
        c:Down(10, "world")
        assert.are.equal("hold", c:Up(10.35))
        assert.are.same({ false, "first" }, { c:Down(10.39, "world") })
        assert.is_nil(c:Up(10.45)) -- a short press
        assert.are.same({ true, "double" }, { c:Down(10.6, "world") })
        assert.is_nil(c:Up(11)) -- the second press may be held: the binding already took it
    end)

    it("ignores frames and units, and world clicks right after a unit", function()
        local c = DoubleClick.New()
        c:Down(10, "world")
        assert.are.same({ false, "ui" }, { c:Down(10.2, "ui") })
        assert.are.same({ false, "first" }, { c:Down(10.4, "world") })
        assert.are.same({ false, "unit" }, { c:Down(10.6, "unit") })
        assert.are.same({ false, "unit-quiet" }, { c:Down(10.8, "world") })
        assert.are.same({ false, "unit-quiet" }, { c:Down(11.5, "world") })
        assert.are.same({ false, "first" }, { c:Down(11.7, "world") })
        assert.are.same({ true, "double" }, { c:Down(11.9, "world") })
    end)

    it("does not cast again when the first click hooked the bobber", function()
        local c = DoubleClick.New()
        c:Down(10, "world")
        c:LineIn(10.05)
        assert.are.same({ false, "bobber" }, { c:Down(10.3, "world") })
        -- A line that came in before the first press does not count.
        c:Down(12, "world")
        assert.are.same({ true, "double" }, { c:Down(12.2, "world") })
    end)

    it("forgets every press at a loading screen", function()
        local c = DoubleClick.New()
        c:Down(10, "unit")
        c:Down(10.1, "world")
        c:Forget()
        assert.are.same({ false, "first" }, { c:Down(10.2, "world") })
        c:Forget()
        assert.are.same({ false, "first" }, { c:Down(10.3, "world") })
    end)

    it("names the first reason that blocks a cast", function()
        assert.is_nil(DoubleClick.Blocked({}))
        assert.are.equal("off", DoubleClick.Blocked({ off = true, combat = true }))
        assert.are.equal("combat", DoubleClick.Blocked({ combat = true, mounted = true }))
        local expected = {
            mounted = "mounted",
            swimming = "swimming",
            flying = "flying",
            taxi = "taxi",
            dead = "dead",
            noButton = "no-button",
            noFishing = "no-fishing",
            noPole = "no-pole",
            lineOut = "line-out",
        }
        for field, reason in pairs(expected) do
            assert.are.equal(reason, DoubleClick.Blocked({ [field] = true }))
        end
    end)
end)
