-- Compare groups and rows, the calendar heatmap model, and the line chart math of the stats
-- window.
local addon = require("spec.helpers.addon")
local tiplines = require("spec.helpers.tiplines")

local DAY = 20763

describe("FishingMastery compare, calendar, and line chart", function()
    local ns

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleUI.lua",
            "Style.lua",
            "LocaleStats.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "Options.lua",
            "OptionsControls.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "RowTip.lua",
            "StatsView.lua",
            "ChartModel.lua",
            "FailureTable.lua",
            "CompareTable.lua",
            "CalendarModel.lua",
        }, nil, "FishingMastery")
    end)

    describe("CompareTable", function()
        local function view(casts)
            local totals = ns.Totals.New()
            for i, cast in ipairs(casts) do
                cast.t = cast.t or DAY * 86400 + i * 20
                cast.map = cast.map or 1411
                ns.Totals.Add(totals, cast)
            end
            return ns.StatsView.Build({ { totals = totals } })
        end

        local function casts(n, out, fields)
            local list = {}
            for i = 1, n do
                local cast = { out = out, loot = out == "catch" and { { id = 6303 } } or nil }
                for key, value in pairs(fields or {}) do
                    cast[key] = value
                end
                list[i] = cast
            end
            return list
        end

        local function join(...)
            local all = {}
            for _, list in ipairs({ ... }) do
                for _, cast in ipairs(list) do
                    all[#all + 1] = cast
                end
            end
            return all
        end

        it("groups by lure, realm day and night, and zone", function()
            local v = view(
                join(
                    casts(3, "catch", { lure = 7, bite = 100 }),
                    casts(2, "timeout"),
                    casts(1, "catch", { map = 1412, t = DAY * 86400 + 20 * 3600 })
                )
            )
            local lure = ns.CompareTable.Lure(v)
            assert.are.same({ "on", 3, 3 }, { lure[1].key, lure[1].casts, lure[1].outcomes.catch })
            assert.are.same({ "off", 3 }, { lure[2].key, lure[2].casts })
            assert.are.equal(3, lure[1].bites[100])
            -- Offset 2: UTC hours 0 and 20 are realm hours 2 and 22 (night).
            local day = ns.CompareTable.DayNight(v, 2)
            assert.are.same({ 0, 6 }, { day[1].casts, day[2].casts })
            day = ns.CompareTable.DayNight(v, 10) -- realm hours 10 and 6: day
            assert.are.same({ 6, 0 }, { day[1].casts, day[2].casts })
            local zones = ns.CompareTable.Zones(v)
            assert.are.same({ 1411, 1412 }, { zones[1].key, zones[2].key })
            local names = {
                mapName = function(map)
                    return map == 1411 and "Durotar" or nil
                end,
            }
            assert.are.equal("Durotar", ns.CompareTable.Name("zone", zones[1], names))
            assert.are.equal("zone 1412", ns.CompareTable.Name("zone", zones[2], names))
            assert.are.equal("With lure", ns.CompareTable.Name("lure", lure[1], names))
        end)

        it("calls a difference clear only when its Newcombe range excludes 0", function()
            local function group(catches, timeouts)
                return {
                    casts = catches + timeouts,
                    outcomes = { catch = catches, timeout = timeouts },
                    bites = { [150] = catches },
                }
            end
            local rows = ns.CompareTable.Rows(group(60, 40), group(30, 70))
            assert.are.same({ "Casts", "100", "100", "", "" }, rows[1].cells)
            local success = rows[2]
            assert.are.same(
                { "Success rate", "60 %", "30 %", "+30 pts", "clear difference" },
                success.cells
            )
            local diff = ns.Stats.Difference(60, 100, 30, 100)
            assert.truthy(
                tiplines.text(success.tip):find(
                    string.format(
                        "A - B = +30 pts (%+d - %+d)",
                        math.floor(diff.low * 100 + 0.5),
                        math.floor(diff.high * 100 + 0.5)
                    ),
                    1,
                    true
                )
            )
            assert.are.same(
                { "Getaway rate", "0 %", "0 %", "+0 pts", "no clear difference" },
                rows[3].cells
            )
            rows = ns.CompareTable.Rows(group(50, 50), group(45, 55))
            assert.are.equal("no clear difference", rows[2].cells[5])
            assert.are.equal("Median bite time", rows[6].cells[1])
            assert.are.same({ "15.0 s", "15.0 s", "+0.0 s", "no range" }, {
                rows[6].cells[2],
                rows[6].cells[3],
                rows[6].cells[4],
                rows[6].cells[5],
            })
            rows = ns.CompareTable.Rows(group(3, 2), group(30, 70))
            assert.are.same({ "3/5", "-", "too few casts" }, {
                rows[2].cells[2],
                rows[2].cells[4],
                rows[2].cells[5],
            })
        end)
    end)

    describe("CalendarModel", function()
        it("lays out the last 53 weeks from Monday to Sunday with levels by catches", function()
            assert.are.equal(3, ns.CalendarModel.Row(0)) -- 1970-01-01 was a Thursday
            local monday = 20759 -- 2026-11-02
            assert.are.equal(0, ns.CalendarModel.Row(monday))
            local days = {
                [monday] = { casts = 10, catches = 8 },
                [monday - 1] = { casts = 4, catches = 0 },
                [monday - 7] = { casts = 3, catches = 2 },
                [monday - 400] = { casts = 9, catches = 9 }, -- out of range
            }
            local model = ns.CalendarModel.Build(days, monday + 2)
            assert.are.equal(52 * 7 + 3, #model.cells)
            assert.are.same({ 3, 8 }, { model.fishing, model.most })
            local last = model.cells[#model.cells]
            assert.are.same({ monday + 2, 53, 3, 0 }, { last.day, last.col, last.row, last.level })
            local today = model.cells[#model.cells - 2]
            assert.are.same({ monday, 53, 1, 4 }, { today.day, today.col, today.row, today.level })
            assert.are.equal(1, model.cells[#model.cells - 3].level) -- casts, no catches
            assert.are.equal(1, model.cells[#model.cells - 9].level) -- 2 of 8 -> 1
            assert.are.equal(1, model.cells[1].row)
            assert.are.equal(2, ns.CalendarModel.Level(3, 8))
        end)
    end)

    describe("ChartModel.Line", function()
        it("spans the points and places them in the plot", function()
            local chart = ns.ChartModel.Line({ { x = 100, y = 20 }, { x = 400, y = 37 } })
            assert.are.same({ 100, 400, 40 }, { chart.xmin, chart.xmax, chart.axis.max })
            assert.are.same({ 100, 200, 300, 400 }, chart.xticks)
            assert.are.same({ 150, 50 }, { ns.ChartModel.Place(chart, 250, 20, 300, 100) })
            local single = ns.ChartModel.Line({ { x = 5, y = 1 } })
            assert.are.same({ 4.5, 5.5 }, { single.xmin, single.xmax })
        end)
    end)
end)
