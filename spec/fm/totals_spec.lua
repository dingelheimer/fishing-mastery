-- Totals aggregates (schema 2): exact values for a small hand-made session, and rebuild from the
-- packed history equal to live counting for every aggregate.
local addon = require("spec.helpers.addon")
local synthetic = require("spec.helpers.synthetic")

local DAY = 20763 * 86400

describe("FishingMastery Totals", function()
    local ns, Totals

    before_each(function()
        ns = addon.load({ "Codec.lua", "History.lua", "Totals.lua" }, nil, "FishingMastery")
        Totals = ns.Totals
    end)

    -- 3 casts in map 1411 (one with a lure) at UTC hour 5, then 3 catches in 1412 and an invalid
    -- target without a map an hour later.
    local function session()
        local t1 = DAY + 5 * 3600
        local t4 = t1 + 50 + 3600
        return {
            {
                t = t1,
                map = 1411,
                lure = 263,
                rank = 50,
                mod = 25,
                out = "catch",
                bite = 120,
                loot = { { id = 6303, qty = 1 }, { id = 6358, qty = 2 } },
            },
            { t = t1 + 20, map = 1411, rank = 50, mod = 0, out = "getaway", click = 95 },
            {
                t = t1 + 50,
                map = 1411,
                rank = 52,
                out = "catch",
                bite = 80,
                loot = { { id = 6303, qty = 1 } },
            },
            { t = t4, map = 1412, rank = 52, out = "catch", bite = 100, loot = { { id = 6303 } } },
            {
                t = t4 + 10,
                map = 1412,
                rank = 52,
                out = "catch",
                bite = 100,
                loot = { { id = 6303 } },
            },
            {
                t = t4 + 50,
                map = 1412,
                rank = 52,
                out = "catch",
                bite = 100,
                loot = { { id = 6303 } },
            },
            { t = t4 + 55, out = "invalid_target" },
        }
    end

    it("counts every aggregate of a session", function()
        local totals = Totals.New()
        local casts = session()
        for i, cast in ipairs(casts) do
            Totals.Add(totals, cast)
            if i == 5 then
                -- A tie keeps the map that reached the count first.
                assert.are.equal(1411, totals.items[6303].best)
            end
        end
        assert.are.equal(3, totals.version)
        assert.are.same({
            [1411] = {
                on = {
                    casts = 1,
                    outcomes = { catch = 1 },
                    items = { [6303] = 1, [6358] = 2 },
                    bites = { [120] = 1 },
                    clicks = {},
                },
                off = {
                    casts = 2,
                    outcomes = { catch = 1, getaway = 1 },
                    items = { [6303] = 1 },
                    bites = { [80] = 1 },
                    clicks = {}, -- getaway click times are kept in the history only
                },
            },
            [1412] = {
                off = {
                    casts = 3,
                    outcomes = { catch = 3 },
                    items = { [6303] = 3 },
                    bites = { [100] = 3 },
                    clicks = {},
                },
            },
            [0] = {
                off = {
                    casts = 1,
                    outcomes = { invalid_target = 1 },
                    items = {},
                    bites = {},
                    clicks = {},
                },
            },
        }, totals.zones)
        assert.are.same({
            [5] = { casts = 3, outcomes = { catch = 2, getaway = 1 } },
            [6] = { casts = 4, outcomes = { catch = 3, invalid_target = 1 } },
        }, totals.hours)
        assert.are.same({
            [1411] = {
                [75] = { hooked = 1, getaways = 0 },
                [50] = { hooked = 2, getaways = 1 },
            },
            [1412] = { [50] = { hooked = 3, getaways = 0 } },
        }, totals.skills)
        assert.are.same({
            [6303] = { n = 5, qty = 5, first = casts[1].t, last = casts[6].t, best = 1412 },
            [6358] = { n = 1, qty = 2, first = casts[1].t, last = casts[1].t, best = 1411 },
        }, totals.items)
        -- 1411: gaps 20 + 30, then a break capped at 60; 1412: 10 + 40 + 5; the last cast 60.
        assert.are.same({ [1411] = 110, [1412] = 55, [0] = 60 }, totals.active)
        assert.are.same({ t = casts[7].t, map = 0 }, totals.last)
        assert.are.same(
            { casts = 3, catches = 2, items = { [6303] = 2, [6358] = 2 } },
            totals.maps[1411]
        )
    end)

    it("counts early-click times per zone and lure state", function()
        local totals = Totals.New()
        Totals.Add(totals, { t = DAY, map = 1411, out = "early_click", click = 42 })
        Totals.Add(totals, { t = DAY + 30, map = 1411, out = "early_click", click = 42 })
        Totals.Add(totals, { t = DAY + 60, map = 1411, lure = 263, out = "early_click", click = 7 })
        -- Saved before Story 3.4: counted as an early click, but without a time.
        Totals.Add(totals, { t = DAY + 90, map = 1411, out = "early_click" })
        Totals.Add(totals, { t = DAY + 120, map = 1411, out = "getaway", click = 95 })
        assert.are.same({ [42] = 2 }, totals.zones[1411].off.clicks)
        assert.are.same({ [7] = 1 }, totals.zones[1411].on.clicks)
        assert.are.equal(3, totals.zones[1411].off.outcomes.early_click)
    end)

    it("compares totals deeply", function()
        local a, b = Totals.New(), Totals.New()
        Totals.Add(a, { t = DAY, map = 1, out = "catch", loot = { { id = 5 } } })
        assert.is_false(Totals.Equal(a, b))
        Totals.Add(b, { t = DAY, map = 1, out = "catch", loot = { { id = 5 } } })
        assert.is_true(Totals.Equal(a, b))
        b.items[5].qty = 2
        assert.is_false(Totals.Equal(a, b))
    end)

    it("ignores a gap that goes back in time", function()
        local totals = Totals.New()
        Totals.Add(totals, { t = DAY + 100, map = 1, out = "cancel" })
        Totals.Add(totals, { t = DAY + 90, map = 1, out = "cancel" })
        assert.are.equal(120, totals.active[1])
    end)

    it("rebuild from the packed history equals live counting in every aggregate", function()
        local char = { casts = {}, days = {}, quarantine = {} }
        local live = Totals.New()
        for i, cast in ipairs(synthetic.casts(6000, 1793836800, 11)) do
            ns.History.PackIfNewDay(char, cast.t)
            char.casts[#char.casts + 1] = cast
            Totals.Add(live, cast)
            if i % 900 == 0 then
                ns.History.Pack(char)
            end
        end
        for _, name in ipairs(Totals.TABLES) do
            assert.is_not_nil(next(live[name]), name .. " is empty")
            assert.are.same(live[name], Totals.Rebuild(char)[name], name)
        end
        assert.are.same(live, Totals.Rebuild(char))
        local lured = 0
        for _, groups in pairs(live.zones) do
            lured = lured + (groups.on and groups.on.casts or 0)
        end
        assert.is_true(lured > 0)
    end)
end)
