-- Skill scan, skill pace, forecasts, and the Skill tab texts of the stats window.
local addon = require("spec.helpers.addon")
local tiplines = require("spec.helpers.tiplines")

local DAY = 20763

describe("FishingMastery skill tab", function()
    local ns

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleUI.lua",
            "Style.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "History.lua",
            "Session.lua",
            "Options.lua",
            "OptionsControls.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "ChartModel.lua",
            "SkillScan.lua",
            "SkillModel.lua",
            "SkillTable.lua",
        }, nil, "FishingMastery")
    end)

    local function near(expected, actual, tolerance)
        assert.is_true(math.abs(expected - actual) < (tolerance or 1e-9), tostring(actual))
    end

    -- A character with one chunk per day: day i has catches at rank first + i - 1.
    local function char(days, first, catchesPerDay)
        local entry = { days = {}, casts = {} }
        for i = 1, days do
            local day, casts = DAY + i, {}
            for j = 1, catchesPerDay do
                casts[j] = {
                    t = day * 86400 + j * 20,
                    out = "catch",
                    rank = first + i - 1,
                    map = 1411,
                    loot = { { id = 6303, qty = 1 } },
                }
            end
            for _, chunk in ipairs(ns.Codec.Encode(day, casts)) do
                entry.days[#entry.days + 1] = chunk
            end
        end
        return entry
    end

    describe("SkillScan", function()
        it("reads the chunks in steps and adds the open casts on every result", function()
            local entry = char(25, 20, 4)
            local scan = ns.SkillScan.New()
            assert.is_false(ns.SkillScan.Step(scan, entry))
            assert.are.same({ 10, 25 }, { ns.SkillScan.Progress(scan) })
            assert.is_false(ns.SkillScan.Step(scan, entry))
            assert.is_true(ns.SkillScan.Step(scan, entry))
            local result = ns.SkillScan.Result(scan, entry)
            assert.are.equal(4, result.ranks[20].catches)
            assert.are.equal((DAY + 1) * 86400 + 20, result.ranks[20].first)
            assert.are.same({ t = (DAY + 25) * 86400 + 80, rank = 44 }, result.latest)

            entry.casts[1] = { t = (DAY + 26) * 86400, out = "catch", rank = 45 }
            entry.casts[2] = { t = (DAY + 26) * 86400 + 30, out = "timeout", rank = 45 }
            result = ns.SkillScan.Result(scan, entry)
            assert.are.same({ first = (DAY + 26) * 86400, catches = 1 }, result.ranks[45])
            assert.is_nil(scan.ranks[45]) -- open casts never enter the scan itself
        end)

        it("continues after a new chunk and starts over for a replaced list", function()
            local entry = char(3, 20, 2)
            local scan = ns.SkillScan.New()
            assert.is_true(ns.SkillScan.Step(scan, entry))
            entry.days[4] =
                ns.Codec.Encode(DAY + 9, { { t = (DAY + 9) * 86400, out = "catch", rank = 23 } })[1]
            assert.is_true(ns.SkillScan.Step(scan, entry, 1))
            assert.are.equal(1, scan.ranks[23].catches)
            assert.are.equal(2, scan.ranks[20].catches) -- not counted twice

            local imported = char(2, 50, 1)
            entry.days = imported.days
            assert.is_true(ns.SkillScan.Step(scan, entry))
            assert.is_nil(scan.ranks[20])
            assert.are.equal(1, scan.ranks[51].catches)

            -- A chunk removed from the middle (quarantine) also starts over.
            local three = char(3, 60, 1)
            assert.is_true(ns.SkillScan.Step(scan, three))
            table.remove(three.days, 2)
            assert.is_true(ns.SkillScan.Step(scan, three))
            assert.is_nil(scan.ranks[61])
            assert.are.equal(2, scan.index)
        end)

        it("skips broken chunks and casts without a rank", function()
            local entry = char(2, 30, 1)
            table.insert(entry.days, 2, "broken")
            entry.casts[1] = { t = (DAY + 5) * 86400, out = "catch" }
            local scan = ns.SkillScan.New()
            assert.is_true(ns.SkillScan.Step(scan, entry))
            local result = ns.SkillScan.Result(scan, entry)
            assert.are.equal(1, result.ranks[30].catches)
            assert.are.equal(1, result.ranks[31].catches)
            assert.are.equal(31, result.latest.rank)
        end)
    end)

    describe("SkillModel", function()
        local function ranks(list)
            local result = { ranks = {} }
            for rank, catches in pairs(list) do
                result.ranks[rank] = { first = rank * 100, catches = catches }
            end
            return result
        end

        it(
            "paces the last 10 completed points, leaving out first, current, and cap ranks",
            function()
                -- Ranks 60-90: rank 60 is the first tracked one, 90 the current one, 75 a cap.
                local list = {}
                for rank = 60, 90 do
                    list[rank] = rank >= 80 and 5 or 2
                end
                list[75] = 400
                local result = ranks(list)
                result.latest = { t = 9000, rank = 90 }
                local model = ns.SkillModel.Build({
                    result = result,
                    rank = 90,
                    max = 150,
                    perHour = { rate = 100, display = "full" },
                })
                assert.are.equal(60, model.first)
                assert.are.equal(5, model.since)
                -- Ranks 89-80: 10 points in 50 catches.
                assert.are.same({ 10, 50 }, { model.pace.k, model.pace.c })
                near(5, model.pace.mean)
                local low, high = ns.Stats.Wilson(10, 50)
                near(1 / high, model.pace.low)
                near(1 / low, model.pace.high)
                assert.are.equal(150, model.toCap.cap)
                assert.are.equal(60, model.toCap.points)
                near(300, model.toCap.mean)
                near(300 / 100 * 3600, model.toCap.seconds)
                assert.are.equal(210, model.toTop.points)
                -- Bands of 25 ranks: 61-74 (2 per point); 76-79 (2) and 80-89 (5).
                assert.are.equal(2, #model.bands)
                assert.are.same({ 50, 74 }, { model.bands[1].from, model.bands[1].to })
                assert.are.same({ 14, 28 }, { model.bands[1].pace.k, model.bands[1].pace.c })
                assert.are.same({ 14, 58 }, { model.bands[2].pace.k, model.bands[2].pace.c })
                -- Timeline: the first cast at every rank, oldest first.
                assert.are.same({ t = 6000, rank = 60 }, model.timeline[1])
                assert.are.same({ t = 9000, rank = 90 }, model.timeline[#model.timeline])
            end
        )

        it("adds a point for a skill-up after the last cast and knows the caps", function()
            local result = ranks({ [10] = 1, [11] = 1 })
            result.latest = { t = 1100, rank = 11 }
            local model = ns.SkillModel.Build({ result = result, rank = 12 })
            assert.are.same({ t = 1100, rank = 12 }, model.timeline[3])
            assert.are.same({ 1, 1 }, { model.pace.k, model.pace.c }) -- rank 11 only
            assert.are.equal("count", model.pace.display)
            assert.are.equal(75, model.toCap.cap) -- no saved cap: the next step of 75
            assert.is_nil(model.toCap.seconds)

            model = ns.SkillModel.Build({ result = result, rank = 75, max = 75 })
            assert.is_true(model.atCap)
            assert.is_nil(model.toCap)
            assert.are.equal(225, model.toTop.points)
            model = ns.SkillModel.Build({ result = result, rank = 300, max = 300 })
            assert.is_nil(model.toTop)
            assert.is_nil(ns.SkillModel.Build({ result = { ranks = {} } }))

            assert.are.equal(150, ns.SkillModel.NextCap(75, nil))
            assert.are.equal(150, ns.SkillModel.NextCap(101, 150))
            assert.are.equal(300, ns.SkillModel.NextCap(299, nil))
        end)

        it("writes the pace, forecast, and chart texts", function()
            local list = {}
            for rank = 20, 45 do
                list[rank] = 4
            end
            local result = ranks(list)
            result.latest = { t = 4500, rank = 45 }
            result.start = { t = 2000, rank = 20 }
            local model = ns.SkillModel.Build({
                result = result,
                rank = 45,
                max = 75,
                perHour = { rate = 120, display = "full" },
            })
            local input = {
                formatDate = function(t)
                    return "d" .. t
                end,
            }
            local text = table.concat(ns.SkillTable.Lines(model, input), "\n")
            assert.truthy(text:find("Fishing rank 45 of 75", 1, true))
            assert.truthy(text:find("First tracked rank: 20 on d2000", 1, true))
            assert.truthy(text:find("4.0 catches per point (95 % range", 1, true))
            assert.truthy(text:find("10 points in 40 catches", 1, true))
            assert.truthy(text:find("To the rank cap 75: 30 points, about 120 catches", 1, true))
            assert.truthy(text:find("about 1 h 00 min of active fishing", 1, true), text)
            local chart = ns.SkillTable.RankChart(model, input)
            assert.are.equal(26, #chart.points)
            assert.are.same({ "Rank 20", "d2000" }, tiplines.lines(chart.points[1].tip))
            assert.are.equal("d2000", chart.labels[1])
            local bars = ns.SkillTable.BandChart(model)
            assert.are.equal(2, #bars.bars) -- ranks 21-24 and 25-44
            assert.are.equal("4.0", bars.bars[1].text)
        end)
    end)
end)
