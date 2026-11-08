-- Getaway model (Getaway.lua) on the generated zone data: the base-level rows of the research
-- table, the subzone override (Jaguero Isle 205 in Stranglethorn Vale 130), clamping and no
-- catch below the base, unknown areas, the Epic 2 Durotar sample (9 catches, 5 getaways), own
-- rates per resolved area and band, the comparison with the model, and the relative chart.
local addon = require("spec.helpers.addon")

local NAMES = { [297] = "Jaguero Isle", [367] = "Sen'jin Village", [814] = "Southfury River" }

describe("FishingMastery getaway model", function()
    local ns, Getaway, Area

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "Data\\Zones.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "History.lua",
            "Options.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "Getaway.lua",
            "StatsView.lua",
            "ChartModel.lua",
            "FailureTable.lua",
            "Area.lua",
        }, nil, "FishingMastery")
        Getaway = ns.Getaway
        Area = ns.Area.New(ns.Zones, function(id)
            return NAMES[id]
        end)
    end)

    local function near(expected, actual)
        assert.is_true(math.abs(expected - actual) < 1e-9, tostring(actual))
    end

    it("matches the base-level table of the research", function()
        -- base, getaways stop at, 50 % catch at
        local rows = {
            { -70, 25, nil },
            { -20, 75, 25 },
            { 55, 150, 100 },
            { 130, 225, 175 },
            { 205, 300, 250 },
            { 330, 425, 375 },
        }
        for _, row in ipairs(rows) do
            local base, stops, half = row[1], row[2], row[3]
            assert.are.equal(stops, Getaway.Model(stops, base).stopsAt)
            near(0, Getaway.Model(stops, base).getaway)
            near(0.01, Getaway.Model(stops - 1, base).getaway)
            if half then
                near(0.5, Getaway.Model(half, base).catch)
            end
        end
        -- Starting zones: at least 75 % from skill 1 on.
        near(0.76, Getaway.Model(1, -70).catch)
    end)

    it("clamps, and gives no catch below the base", function()
        near(0.05, Getaway.Model(55, 55).catch)
        local below = Getaway.Model(54, 55)
        assert.is_true(below.below)
        near(0, below.catch)
        near(1, below.getaway)
        near(1, Getaway.Model(400, 55).catch)
        assert.is_false(Getaway.Model(400, 55).below)
        -- Band means: skills 0-4 above the base catch 5-9 %.
        near(0.93, Getaway.BandModel(55, 5, 55))
        near(1, Getaway.BandModel(-10, 5, 0))
    end)

    it("uses the subzone's own base and the zone's where a subzone has none", function()
        assert.are.equal(130, Area:Base(33)) -- Stranglethorn Vale
        assert.are.equal(205, Area:Base(Area:Resolve(1434, "Jaguero Isle")))
        assert.are.equal(-70, Area:Base(Area:Resolve(1411, "Sen'jin Village"))) -- zone's base
        near(0.5, Getaway.Model(175, 130).getaway)
        assert.is_true(Getaway.Model(175, 205).below)
    end)

    it("shows unknown and the own rate only without a base level", function()
        assert.is_nil(Area:Base(Area:Resolve(9999, "Somewhere")))
        assert.is_nil(Getaway.Model(100, nil))
        local risk = Getaway.Risk({ [100] = { hooked = 12, getaways = 3 } }, 102, nil)
        assert.is_nil(risk.model)
        assert.is_true(risk.shown)
        assert.is_false(risk.differs)
        local lines = Getaway.Lines(risk)
        assert.truthy(lines[1]:find("unknown", 1, true))
        assert.truthy(lines[2]:find("here: 25 %", 1, true))
        assert.are.equal(2, #lines)
    end)

    it("agrees with the Epic 2 Durotar sample (9 catches, 5 getaways at skill 1-10)", function()
        local bands = { [5] = { hooked = 14, getaways = 5 } } -- shown as one band
        local risk = Getaway.Risk(bands, 7, Area:Base(14))
        near(0.18, risk.bandModel) -- catch 80-84 %
        near(0.18, risk.model.getaway) -- skill 7: catch 82 %
        assert.is_true(risk.shown)
        assert.is_false(risk.differs) -- own 36 %, range about 16-61 %
        assert.is_true(risk.own.low < 0.18 and risk.own.high > 0.18)
        local lines = Getaway.Lines(risk)
        assert.are.equal(
            "Getaway risk at skill 7: 18 % (Classic model; none from skill 25)",
            lines[1]
        )
        assert.are.equal(2, #lines)
    end)

    it("notes when the own range excludes the model, and hides small samples", function()
        -- 0 of 40 hooked where the model expects half to get away: differs.
        local risk = Getaway.Risk({ [100] = { hooked = 40, getaways = 0 } }, 102, 55)
        assert.is_true(risk.differs)
        local lines = Getaway.Lines(risk)
        assert.truthy(lines[3]:find("Differs from Classic (model 48 %", 1, true))
        -- Below the count threshold: count only, never "differs".
        risk = Getaway.Risk({ [100] = { hooked = 5, getaways = 0 } }, 102, 55)
        assert.is_false(risk.shown)
        assert.is_false(risk.differs)
        assert.truthy(Getaway.Lines(risk)[2]:find("0 of 5 hooked", 1, true))
        -- No hooked casts in the band: the model only.
        risk = Getaway.Risk({}, 50, 55)
        assert.is_nil(risk.own)
        assert.truthy(Getaway.Lines(risk)[1]:find("no catches below skill 55", 1, true))
    end)

    local function view()
        return {
            subskills = {
                [1411] = { -- Durotar, base -70
                    [""] = { [5] = { hooked = 10, getaways = 2 } },
                    ["Razor Hill"] = { [5] = { hooked = 4, getaways = 3 } }, -- no own data
                    ["Southfury River"] = { [10] = { hooked = 2, getaways = 0 } },
                },
                [1434] = { -- Jaguero Isle, base 205 in Stranglethorn Vale (130)
                    ["Jaguero Isle"] = { [200] = { hooked = 6, getaways = 6 } },
                    [""] = { [200] = { hooked = 3, getaways = 1 } },
                },
                [9999] = { [""] = { [100] = { hooked = 7, getaways = 1 } } },
            },
        }
    end

    it("splits own rates by resolved area and groups them by skill above the base", function()
        local byArea, unknown = Getaway.ByArea(view(), Area)
        assert.are.equal(7, unknown)
        assert.are.same({ [5] = { hooked = 14, getaways = 5 } }, byArea[14])
        assert.are.same({ [10] = { hooked = 2, getaways = 0 } }, byArea[814])
        assert.are.same({ [200] = { hooked = 6, getaways = 6 } }, byArea[297])
        assert.are.same({ [200] = { hooked = 3, getaways = 1 } }, byArea[33])
        local relative, noBase = Getaway.Relative(byArea, Area)
        assert.are.equal(0, noBase)
        assert.are.same({
            [75] = { hooked = 14, getaways = 5 },
            [80] = { hooked = 2, getaways = 0 },
            [-5] = { hooked = 6, getaways = 6 }, -- 200 at base 205: below
            [70] = { hooked = 3, getaways = 1 },
        }, relative)
    end)

    it("builds the relative Failures chart with the model as a mark", function()
        local chart, left = ns.FailureTable.RelativeChart(view(), Area)
        assert.are.equal(7, left)
        local labels = {}
        for i, bar in ipairs(chart.bars) do
            labels[i] = bar.label
        end
        assert.are.same({ "-5", "+70", "+75", "+80" }, labels)
        near(1, chart.bars[1].mark)
        local tip = table.concat(chart.bars[1].tip, " / ")
        assert.truthy(tip:find("Below the base level", 1, true))
        assert.truthy(tip:find("Classic model: 100 %", 1, true))
        near(0.18, chart.bars[3].mark) -- +75 to +79: catch 80-84 %
        -- Without zone data nothing is grouped.
        assert.is_nil((ns.FailureTable.RelativeChart(view(), nil)))
    end)
end)
