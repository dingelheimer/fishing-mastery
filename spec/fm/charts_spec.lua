-- Chart math (axis scales, bins, bar layout, label step) and the Failures, Bite times, and Sessions
-- table builders of the stats window.
local addon = require("spec.helpers.addon")

local DAY = 20763 * 86400

describe("FishingMastery charts and failure tables", function()
    local ns, ChartModel

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "Codec.lua",
            "History.lua",
            "Session.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "StatsView.lua",
            "StatsTables.lua",
            "ChartModel.lua",
            "FailureTable.lua",
            "BiteTable.lua",
            "SessionTable.lua",
        }, nil, "FishingMastery")
        ChartModel = ns.ChartModel
    end)

    local function near(expected, actual)
        assert.is_true(math.abs(expected - actual) < 1e-9, tostring(actual))
    end

    local function view(casts)
        local totals = ns.Totals.New()
        for i, cast in ipairs(casts) do
            cast.t = cast.t or DAY + i * 20
            cast.map = cast.map or 1411
            ns.Totals.Add(totals, cast)
        end
        return ns.StatsView.Build({ { totals = totals } })
    end

    local function mapName(map)
        return ({ [1411] = "Durotar", [1412] = "Mulgore" })[map]
    end

    describe("ChartModel", function()
        it("scales the axis to nice steps of 1, 2, 2.5, and 5", function()
            assert.are.same(
                { max = 40, step = 10, ticks = { 0, 10, 20, 30, 40 } },
                ChartModel.Scale(37, true)
            )
            assert.are.same(
                { max = 3, step = 1, ticks = { 0, 1, 2, 3 } },
                ChartModel.Scale(3, true)
            )
            -- Counts never get steps below 1.
            assert.are.same({ max = 1, step = 1, ticks = { 0, 1 } }, ChartModel.Scale(0.5, true))
            local rate = ChartModel.Scale(0.42)
            near(0.2, rate.step)
            near(0.6, rate.max)
            assert.are.equal(4, #rate.ticks)
            -- Nothing to show: a 0-1 axis in quarters.
            local empty = ChartModel.Scale(0)
            near(0.25, empty.step)
            near(1, empty.max)
        end)

        it("bins tenth-second histograms and clips late keys into the last bin", function()
            local bins =
                ChartModel.Bins({ [5] = 1, [15] = 2, [19] = 1, [310] = 4, [-1] = 9 }, 10, 300)
            assert.are.equal(30, #bins)
            assert.are.equal(1, bins[1])
            assert.are.equal(3, bins[2])
            assert.are.equal(4, bins[30])
        end)

        it("lays out bars, spaces the x labels, and writes tick texts", function()
            local layout = ChartModel.Layout(4, 100)
            assert.are.equal(25, layout.slot)
            assert.are.equal(17, layout.bar)
            assert.are.equal(4, layout.x(1))
            assert.are.equal(29, layout.x(2))
            assert.are.equal(1, ChartModel.Layout(500, 100).bar) -- never narrower than 1 pixel
            assert.are.equal(3, ChartModel.LabelEvery(30))
            assert.are.equal(1, ChartModel.LabelEvery(5))
            assert.are.equal("25 %", ChartModel.TickText(0.25, true))
            assert.are.equal("2.5", ChartModel.TickText(2.5))
            assert.are.equal("10", ChartModel.TickText(10))
            -- The axis covers the upper range bound, not only the bar.
            near(
                0.6,
                ChartModel.Build({ { value = 0.2, high = 0.5 }, { value = 0.1 } }, true).axis.max
            )
        end)
    end)

    -- 30 catches and 6 getaways at effective skill 50, 4 getaways at 72 + 25, 5 early clicks
    -- (3 at 4.2 s, 2 at 0.7 s), 5 timeouts, 2 cancels, 1 invalid target.
    local function failureView()
        local casts = {}
        local function add(n, cast)
            for _ = 1, n do
                local copy = {}
                for key, value in pairs(cast) do
                    copy[key] = value
                end
                casts[#casts + 1] = copy
            end
        end
        add(30, { out = "catch", rank = 50, loot = { { id = 6303 } } })
        add(6, { out = "getaway", rank = 50 })
        add(4, { out = "getaway", rank = 72, mod = 25 })
        add(3, { out = "early_click", click = 42 })
        add(2, { out = "early_click", click = 7 })
        add(5, { out = "timeout" })
        add(2, { out = "cancel" })
        add(1, { out = "invalid_target" })
        return view(casts)
    end

    it("lists every outcome with its rates of fair and hooked casts", function()
        local rows = ns.FailureTable.Rows(failureView())
        local cells = {}
        for i, row in ipairs(rows) do
            cells[i] = row.cells
        end
        assert.are.same({ "catch", "30", "60 %", "75 %" }, cells[1]) -- 50 fair, 40 hooked
        assert.are.same({ "fish got away", "10", "20 %", "25 %" }, cells[2])
        assert.are.same({ "clicked too early", "5", "10 %", "-" }, cells[3])
        assert.are.same({ "timeout (bobber not clicked)", "5", "10 %", "-" }, cells[4])
        assert.are.same({ "cancelled", "2", "-", "-" }, cells[5]) -- counts only
        assert.are.same({ "invalid target (no fishable water)", "1", "-", "-" }, cells[6])
        local tip = table.concat(rows[2].tooltip, "\n")
        assert.truthy(tip:find("Of fair casts: 20 % (95 % range", 1, true))
        assert.truthy(tip:find("Of hooked casts: 25 % (95 % range", 1, true))
        assert.truthy(table.concat(rows[5].tooltip, "\n"):find("Count only", 1, true))
    end)

    it("charts the getaway rate by skill band and early clicks by click time", function()
        local fv = failureView()
        local skill = ns.FailureTable.SkillChart(fv)
        assert.are.equal(2, #skill.bars)
        local low, high = ns.Stats.Wilson(6, 36)
        assert.are.equal("50", skill.bars[1].label)
        near(6 / 36, skill.bars[1].value)
        near(low, skill.bars[1].low)
        near(high, skill.bars[1].high)
        assert.are.equal("17 %", skill.bars[1].text)
        assert.is_false(skill.bars[1].grey)
        assert.are.equal("95", skill.bars[2].label) -- 72 + 25 = 97
        assert.are.equal("4/4", skill.bars[2].text) -- counts only below 10
        assert.is_true(skill.bars[2].grey)
        assert.truthy(skill.bars[2].tip[1]:find("Effective skill 95-99", 1, true))
        assert.is_true(skill.percent)

        local clicks = ns.FailureTable.ClickChart(fv)
        assert.are.equal(30, #clicks.bars)
        assert.are.equal(2, clicks.bars[1].value)
        assert.are.equal(3, clicks.bars[5].value)
        assert.are.equal(5, clicks.total)
        assert.are.equal(3, clicks.axis.max)
        assert.truthy(clicks.bars[5].tip[1]:find("Clicked at 4-5 s: 3 of 5", 1, true))

        local empty = view({ { out = "cancel" } })
        assert.is_nil(ns.FailureTable.SkillChart(empty))
        assert.is_nil(ns.FailureTable.ClickChart(empty))
    end)

    it("groups bite times by zone and lure with median and quartiles", function()
        local casts = {}
        for i = 1, 30 do -- bites at 1, 2, ..., 30 s; the first 10 with a lure
            casts[i] = {
                out = "catch",
                bite = i * 10,
                lure = i <= 10 and 263 or nil,
                loot = { { id = 6303 } },
            }
        end
        local groups = ns.BiteTable.Groups(view(casts))
        assert.are.equal(3, #groups)
        assert.is_nil(groups[1].map) -- all zones first
        assert.are.equal(30, groups[1].n)
        assert.are.equal("off", groups[2].lure) -- 20 bites before 10
        assert.are.equal("on", groups[3].lure)
        assert.are.equal(155, groups[1].quartiles.median)
        local q = groups[1].quartiles
        assert.are.equal(
            string.format(
                "Median %.1f s; half your bites take %.1f-%.1f s (30 bites)",
                15.5,
                q.q1 / 10,
                q.q3 / 10
            ),
            ns.BiteTable.Summary(groups[1])
        )
        assert.are.equal("Durotar, with lure", ns.BiteTable.Name(groups[3], mapName))
        local rows = ns.BiteTable.Rows(groups, mapName, 2)
        assert.are.equal("All zones", rows[1].cells[1])
        assert.are.equal("> Durotar", rows[2].cells[1]) -- the charted group
        assert.are.equal("no lure", rows[2].cells[2])
        assert.are.equal("15.5 s", rows[1].cells[5])
        local chart = ns.BiteTable.Chart(groups[1])
        assert.are.equal(30, #chart.bars)
        assert.are.equal(0, chart.bars[1].value)
        assert.are.equal(1, chart.bars[2].value)
        assert.are.equal(2, chart.bars[30].value) -- 29 s and 30 s
        assert.are.same({}, ns.BiteTable.Groups(view({ { out = "getaway" } })))
    end)

    it("lists sessions newest first and sorts by any column", function()
        local function session(start, casts, zones, skillStart, skill)
            return {
                start = start,
                last = start + 300,
                ended = start + 300,
                endReason = "idle",
                casts = casts,
                catches = casts - 1,
                counts = { catch = casts - 1, getaway = 1 },
                zones = zones,
                skillStart = skillStart,
                skill = skill,
                active = 300,
            }
        end
        local chars = {
            {
                name = "Alice",
                entry = {
                    sessions = {
                        session(1000, 12, { 1411 }, 50, 52),
                        session(9000, 3, { 1411, 1412 }),
                    },
                },
            },
            { name = "Bob", entry = { sessions = { session(5000, 20, { 1412 }, 10, 10) } } },
        }
        local input = {
            mapName = mapName,
            formatTime = function(t)
                return "T" .. t
            end,
            now = 20000,
        }
        local rows = ns.SessionTable.Rows(chars, input)
        assert.are.same({ "T9000", "Alice", "Durotar +1", "6 min", "3", "2", "-" }, rows[1].cells)
        assert.are.same(
            { "T5000", "Bob", "Mulgore", "6 min", "20", "19", "+0 (10 -> 10)" },
            rows[2].cells
        )
        assert.are.same(
            { "T1000", "Alice", "Durotar", "6 min", "12", "11", "+2 (50 -> 52)" },
            rows[3].cells
        )
        local tip = table.concat(rows[2].tooltip, "\n")
        assert.truthy(tip:find("Success rate 95 % (95 % range", 1, true))
        assert.truthy(tip:find("6 min active of 5 min", 1, true))
        assert.truthy(tip:find("Ended after 15 minutes without a cast", 1, true))
        input.sort = { key = "casts" }
        rows = ns.SessionTable.Rows(chars, input)
        assert.are.same({ 3, 12, 20 }, { rows[1].casts, rows[2].casts, rows[3].casts })
        input.sort = { key = "skill", descending = true }
        rows = ns.SessionTable.Rows(chars, input)
        assert.are.equal(1000, rows[1].start) -- +2 first
    end)
end)
