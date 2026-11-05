local addon = require("spec.helpers.addon")
local synthetic = require("spec.helpers.synthetic")

local FILES = { "Codec.lua", "History.lua", "Totals.lua" }

describe("FishingMastery history", function()
    local ns, char

    before_each(function()
        ns = addon.load(FILES, nil, "FishingMastery")
        char = { casts = {}, days = {}, quarantine = {} }
    end)

    local function all()
        local list = {}
        for cast in ns.History.Iterate(char) do
            list[#list + 1] = cast
        end
        return list
    end

    describe("packing", function()
        it("packs the open casts per day, appends, and empties the open list", function()
            local casts = synthetic.casts(400, 1793836800, 7)
            for i, cast in ipairs(casts) do
                char.casts[i] = cast
            end
            local added = ns.History.Pack(char)
            assert.is_true(added >= 2)
            assert.are.same({}, char.casts)
            assert.are.same(casts, all())
            local days = {}
            for _, chunk in ipairs(char.days) do
                days[#days + 1] = tonumber(chunk:match("^(%d+)|"))
            end
            for i = 2, #days do
                assert.is_true(days[i] >= days[i - 1])
            end
        end)

        it("never rewrites older chunks", function()
            char.casts = synthetic.casts(50, 1793836800, 1)
            ns.History.Pack(char)
            local before = { unpack(char.days) }
            char.casts = synthetic.casts(50, 1793836800, 2)
            ns.History.Pack(char)
            for i, chunk in ipairs(before) do
                assert.are.equal(chunk, char.days[i])
            end
            assert.is_true(#char.days > #before)
            assert.are.equal(0, ns.History.Pack(char))
        end)

        it("packs the open day when a cast of a later day arrives", function()
            local day = 20763 * 86400
            char.casts = { { t = day + 100, out = "cancel" } }
            assert.are.equal(0, ns.History.PackIfNewDay(char, day + 80000))
            assert.are.equal(1, #char.casts)
            assert.are.equal(1, ns.History.PackIfNewDay(char, day + 86400 + 5))
            assert.are.same({}, char.casts)
            assert.are.equal("20763|100,5", char.days[1])
            assert.are.equal(0, ns.History.PackIfNewDay(char, day + 90000))
        end)
    end)

    describe("load check", function()
        it("moves a broken chunk to quarantine, reports it once, and keeps the rest", function()
            char.casts = synthetic.casts(300, 1793836800, 3)
            ns.History.Pack(char)
            local good = #char.days
            table.insert(char.days, 2, "20763|10,1,broken")
            local result = ns.History.Check(char, 555)
            assert.are.same({ chunks = good, casts = 300, quarantined = 1 }, result)
            assert.are.equal(good, #char.days)
            assert.are.equal("20763|10,1,broken", char.quarantine[1].chunk)
            assert.truthy(char.quarantine[1].error:find("bad number", 1, true))
            assert.are.equal(555, char.quarantine[1].found)
            assert.are.equal(1, #ns.History.TakeUnreported(char))
            assert.are.equal(0, #ns.History.TakeUnreported(char))
            assert.are.equal(300, #all())
        end)
    end)

    describe("iterator", function()
        it("returns chunks oldest first, then the open casts, decoding on demand", function()
            char.casts = synthetic.casts(500, 1793836800, 4)
            ns.History.Pack(char)
            char.casts = { { t = 1893836800, out = "cancel" } }
            local decodes = 0
            local decode = ns.Codec.Decode
            ns.Codec.Decode = function(chunk)
                decodes = decodes + 1
                return decode(chunk)
            end
            local iterator = ns.History.Iterate(char)
            assert.are.equal(0, decodes)
            iterator()
            assert.are.equal(1, decodes)
            local count = 1
            local last
            for cast in iterator do
                count = count + 1
                last = cast
            end
            assert.are.equal(501, count)
            assert.are.equal(1893836800, last.t)
            assert.are.equal(#char.days, decodes)
        end)

        it("skips broken chunks", function()
            char.days = { "broken", "20763|100,5" }
            assert.are.equal(1, #all())
        end)
    end)

    describe("totals", function()
        it("counts outcomes, days, and items per map", function()
            local totals = ns.Totals.New()
            ns.Totals.Add(totals, {
                t = 20763 * 86400 + 5,
                out = "catch",
                map = 1411,
                loot = { { id = 6303, qty = 1 }, { id = 6358, qty = 2 } },
            })
            ns.Totals.Add(totals, { t = 20763 * 86400 + 50, out = "getaway", map = 1411 })
            ns.Totals.Add(totals, { t = 20764 * 86400, out = "cancel" })
            assert.are.same({ catch = 1, getaway = 1, cancel = 1 }, totals.outcomes)
            assert.are.same(
                { [20763] = { casts = 2, catches = 1 }, [20764] = { casts = 1, catches = 0 } },
                totals.days
            )
            assert.are.same({
                casts = 2,
                catches = 1,
                items = { [6303] = 1, [6358] = 2 },
            }, totals.maps[1411])
            assert.are.same({ casts = 1, catches = 0 }, totals.maps[0])
        end)

        it("rebuild from the chunks equals live counting", function()
            local live = ns.Totals.New()
            for i, cast in ipairs(synthetic.casts(5000, 1793836800, 9)) do
                ns.History.PackIfNewDay(char, cast.t)
                char.casts[#char.casts + 1] = cast
                ns.Totals.Add(live, cast)
                if i % 700 == 0 then
                    ns.History.Pack(char) -- a logout in the middle of a day
                end
            end
            assert.are.same(live, ns.Totals.Rebuild(char))
            ns.History.Pack(char)
            assert.are.same(live, ns.Totals.Rebuild(char))
        end)

        it("repairs broken totals", function()
            assert.are.same(ns.Totals.New(), ns.Totals.Repair(nil))
            assert.are.same(ns.Totals.New(), ns.Totals.Repair({ outcomes = 5 }))
        end)
    end)
end)
