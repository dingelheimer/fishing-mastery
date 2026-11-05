-- Statistics engine: reference values from Statistics Methods (Byar, Wilson, the Story 2.7
-- session), Newcombe's published example, edge cases (n = 0, p = 0, p = 1), and the display
-- thresholds.
local addon = require("spec.helpers.addon")

local function near(expected, actual, tolerance)
    assert.is_number(actual)
    assert.is_true(
        math.abs(expected - actual) <= (tolerance or 0.0005),
        ("expected %s, got %s"):format(expected, actual)
    )
end

describe("FishingMastery Stats", function()
    local Stats

    before_each(function()
        Stats = addon.load({ "Totals.lua", "Stats.lua" }, nil, "FishingMastery").Stats
    end)

    describe("ranges", function()
        it("Byar for c = 12 gives 6.19-20.96 and for c = 0 starts at 0", function()
            local low, high = Stats.Byar(12)
            near(6.19, low, 0.005)
            near(20.96, high, 0.005)
            low, high = Stats.Byar(0)
            assert.are.equal(0, low)
            near(3.668, high, 0.001)
            assert.is_nil(Stats.Byar(-1))
        end)

        it("Wilson for 0 of 44 gives 0-8.0 %, for 44 of 44 ends at 1, and nil for n = 0", function()
            local low, high = Stats.Wilson(0, 44)
            assert.are.equal(0, low)
            near(0.0803, high)
            low, high = Stats.Wilson(44, 44)
            near(1 - 0.0803, low)
            assert.are.equal(1, high)
            assert.is_nil(Stats.Wilson(0, 0))
            assert.is_nil(Stats.Wilson(nil, 10))
        end)

        it("Newcombe reproduces the published example and marks a clear difference", function()
            -- Newcombe (1998), example (a): 56/70 vs 48/80 → 0.0524 to 0.3339.
            local diff = Stats.Difference(56, 70, 48, 80)
            near(0.2, diff.d)
            near(0.0524, diff.low)
            near(0.3339, diff.high)
            assert.is_true(diff.clear)
            assert.is_false(Stats.Difference(10, 20, 11, 20).clear)
            assert.is_nil(Stats.Difference(1, 0, 1, 5))
        end)
    end)

    describe("the Story 2.7 session (40 catches, 44 fair casts, 13 minutes)", function()
        local outcomes =
            { catch = 40, early_click = 2, timeout = 2, cancel = 2, invalid_target = 2 }

        it("success rate 90.9 % with 78.8-96.4 %", function()
            assert.are.equal(44, Stats.Fair(outcomes))
            local rate = Stats.SuccessRate(outcomes)
            near(0.909, rate.p)
            near(0.788, rate.low)
            near(0.964, rate.high)
            assert.are.equal("full", rate.display)
        end)

        it("getaway rate 0 of 40 hooked casts with 0-8.8 %", function()
            assert.are.equal(40, Stats.Hooked(outcomes))
            local rate = Stats.GetawayRate(outcomes)
            assert.are.equal(0, rate.p)
            assert.are.equal(0, rate.low)
            near(0.0876, rate.high)
        end)

        it("miss rate 4 of 44 fair casts", function()
            local rate = Stats.MissRate(outcomes)
            assert.are.equal(4, rate.k)
            assert.are.equal(44, rate.n)
        end)

        it("catches per hour 185 with 132-251", function()
            local rate = Stats.CatchesPerHour(outcomes, 13 * 60)
            near(184.6, rate.rate, 0.05)
            near(132, rate.low, 0.5)
            near(251, rate.high, 0.5)
            assert.are.equal("full", rate.display)
        end)

        it("one rare in 200 casts: 0.09-2.8 %, expected every 36-1,132 casts", function()
            local share = Stats.ItemShare(1, 200)
            near(0.0009, share.low, 0.00005)
            near(0.028, share.high, 0.0005)
            local expected = Stats.ExpectedCasts(share)
            assert.are.equal(200, expected.mean)
            near(36, expected.low, 0.5)
            near(1132, expected.high, 0.5)
            local chance = Stats.AtLeastOne(share, 200)
            near(1 - 0.995 ^ 200, chance.p)
            assert.is_true(chance.low < chance.p and chance.p < chance.high)
        end)
    end)

    describe("edge cases", function()
        it("handles empty samples without numbers", function()
            local rate = Stats.Proportion(0, 0)
            assert.is_nil(rate.p)
            assert.are.equal("count", rate.display)
            assert.is_nil(Stats.ExpectedCasts(rate))
            assert.is_nil(Stats.AtLeastOne(rate, 10))
            assert.are.same({ k = 0, n = 0, display = "count" }, Stats.SuccessRate(nil))
            local perHour = Stats.PerHour(5, 0, 50)
            assert.is_nil(perHour.rate)
        end)

        it("gives infinite expected casts for an item never caught", function()
            local expected = Stats.ExpectedCasts(Stats.Proportion(0, 50))
            assert.are.equal(math.huge, expected.mean)
            assert.are.equal(math.huge, expected.high)
            near(1 / 0.0714, expected.low, 0.05)
        end)

        it("gives p = 1 a range ending at 1", function()
            local rate = Stats.Proportion(30, 30)
            assert.are.equal(1, rate.p)
            assert.are.equal(1, rate.high)
            assert.is_true(rate.low < 1)
        end)
    end)

    describe("display thresholds", function()
        it("shows counts below 10, greys below 30, and full from 30", function()
            assert.are.equal("count", Stats.Proportion(3, 9).display)
            assert.are.equal("few", Stats.Proportion(5, 10).display)
            assert.are.equal("few", Stats.Proportion(15, 29).display)
            assert.are.equal("full", Stats.Proportion(15, 30).display)
        end)

        it("does not grey a range narrower than 10 points", function()
            assert.are.equal("full", Stats.Display(20, 0.50, 0.58))
            assert.are.equal("few", Stats.Display(20, 0.50, 0.61))
        end)

        it("keeps every threshold in one table that settings may override", function()
            local t = Stats.Thresholds({ greyBelow = 50, countBelow = "x", other = 1 })
            assert.are.equal(50, t.greyBelow)
            assert.are.equal(10, t.countBelow)
            assert.is_nil(t.other)
            assert.are.equal(60, t.activeCap)
            assert.are.equal("few", Stats.Proportion(20, 40, t).display)
            assert.are.equal("full", Stats.Proportion(20, 40).display)
            assert.are.same(Stats.DEFAULTS, Stats.Thresholds(nil))
        end)
    end)

    describe("bite times", function()
        it("gives median and quartiles from a histogram", function()
            local q = Stats.Quartiles({ [10] = 1, [20] = 1, [30] = 1, [40] = 1 })
            assert.are.same({ n = 4, q1 = 17.5, median = 25, q3 = 32.5 }, q)
            assert.are.same({ n = 5, q1 = 80, median = 80, q3 = 80 }, Stats.Quartiles({ [80] = 5 }))
            -- Counts weigh the values: 3 bites at 100, 1 at 200.
            assert.are.equal(100, Stats.Quantile({ [100] = 3, [200] = 1 }, 0.5))
            assert.are.equal(200, Stats.Quantile({ [100] = 3, [200] = 1 }, 1))
            assert.is_nil(Stats.Quartiles({}))
            assert.is_nil(Stats.Quartiles(nil))
        end)
    end)

    describe("active time", function()
        it("caps every gap at 60 s and counts 60 s for the last cast", function()
            assert.are.equal(20 + 30 + 60 + 60, Stats.ActiveTime({ 0, 20, 50, 550 }))
            assert.are.equal(0, Stats.ActiveTime({}))
            assert.are.equal(60 + 60, Stats.ActiveTime({ 100, 90 }))
            assert.are.equal(10 + 30, Stats.ActiveTime({ 0, 10 }, 30))
        end)
    end)

    describe("blending", function()
        it("uses the reference alone without own catches and weighs it ~9 % at 200", function()
            assert.are.equal(0.3, Stats.Blend(0, 0, 0.3))
            near((100 + 20 * 0.3) / 220, Stats.Blend(100, 200, 0.3))
            assert.are.equal(20, Stats.DEFAULTS.blendWeight)
            assert.is_nil(Stats.Blend(1, 2, nil))
        end)
    end)

    it("needs no frame or WoW API: it runs with the Lua standard library only", function()
        local env = { math = math, table = table, string = string, type = type, pairs = pairs }
        env.ipairs, env.tostring, env.tonumber = ipairs, tostring, tonumber
        local ns = {}
        for _, file in ipairs({ "Totals.lua", "Stats.lua" }) do -- Stats takes UNFAIR from Totals
            local chunk = assert(loadfile("FishingMastery/" .. file))
            setfenv(chunk, env)
            chunk("FishingMastery", ns)
        end
        local pure = ns.Stats
        local outcomes = { catch = 30, getaway = 3, cancel = 1 }
        assert.are.equal("full", pure.SuccessRate(outcomes).display)
        assert.is_table(pure.GetawayRate(outcomes))
        assert.is_table(pure.CatchesPerHour(outcomes, 1800))
        assert.is_table(pure.Difference(1, 10, 2, 10))
        assert.is_table(pure.Quartiles({ [5] = 2 }))
        assert.are.equal(120, pure.ActiveTime({ 0, 100 }))
    end)
end)
