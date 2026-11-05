-- HUD model (pure): numbers, texts, small-sample rules, and tooltip ranges.
local addon = require("spec.helpers.addon")

describe("FishingMastery HUD model", function()
    local ns, HudModel

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "Session.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
        }, nil, "FishingMastery")
        HudModel = ns.HudModel
    end)

    -- A session with the given outcome counts that started at server time 1000.
    local function session(counts, fields)
        local s = { start = 1000, last = 1000, casts = 0, catches = 0, counts = counts, active = 0 }
        for _, n in pairs(counts) do
            s.casts = s.casts + n
        end
        s.catches = counts.catch or 0
        for key, value in pairs(fields or {}) do
            s[key] = value
        end
        return s
    end

    local function build(s, input)
        input = input or {}
        input.session = s
        input.now = input.now or s.last
        return HudModel.Build(input)
    end

    it("shows counts only below 10 fair casts", function()
        local model = build(session({ catch = 4, getaway = 1, cancel = 2 }), { rank = 50 })
        local lines = HudModel.Lines(model)
        assert.are.equal("0 min active, 7 casts, 4 catches", lines.session)
        assert.are.equal("Success 4/5, -", lines.rates)
        assert.is_true(lines.grey)
        assert.are.same({
            "Success: 4 of 5 fair casts (too few for a rate)",
            "Catches per hour: too few casts yet",
        }, HudModel.Tooltip(model))
    end)

    it("greys the rates below 30 fair casts and shows them in full above", function()
        local few = build(session({ catch = 15, timeout = 5 }, { active = 600 }))
        local lines = HudModel.Lines(few)
        assert.are.equal("Success 75 %, 90/h", lines.rates)
        assert.is_true(lines.grey)
        assert.are.equal(
            "Grey: fewer than 30 fair casts, the range is still wide.",
            HudModel.Tooltip(few)[3]
        )

        local s = session({ catch = 34, getaway = 2, early_click = 4, cancel = 3 }, {
            active = 1380,
        })
        local model = build(s, { now = s.last + 20 }) -- 1,400 s active
        lines = HudModel.Lines(model)
        assert.are.equal("23 min active, 43 casts, 34 catches", lines.session)
        assert.are.equal("Success 85 %, 87/h", lines.rates)
        assert.is_false(lines.grey)
        local low, high = ns.Stats.Wilson(34, 40)
        local byLow, byHigh = ns.Stats.Byar(34)
        local hours = 1400 / 3600
        assert.are.same({
            string.format(
                "Success rate 85 %% (95 %% range %d-%d %%), 34 of 40 fair casts",
                math.floor(low * 100 + 0.5),
                math.floor(high * 100 + 0.5)
            ),
            string.format(
                "Catches per hour 87 (95 %% range %d-%d), 34 catches in 23 min",
                math.floor(byLow / hours + 0.5),
                math.floor(byHigh / hours + 0.5)
            ),
        }, HudModel.Tooltip(model))
    end)

    it("shows rank, skill-ups, and the effective skill with a lure", function()
        local s = session({ catch = 1 }, { skillStart = 48, skill = 51 })
        assert.are.equal(
            "Fishing 51 (+3)",
            HudModel.Lines(build(s, { rank = 51, modifier = 0 })).skill
        )
        local model = build(s, { rank = 51, modifier = 25, lureSeconds = 481 })
        local lines = HudModel.Lines(model)
        assert.are.equal("Fishing 51 (+3), effective 76", lines.skill)
        assert.are.equal("Lure: 9 min left", lines.lure)
        -- Without Fishing data the session's rank is used; without any rank a dash.
        assert.are.equal("Fishing 51 (+3)", HudModel.Lines(build(s)).skill)
        assert.are.equal("Fishing -", HudModel.Lines(build(session({}))).skill)
        assert.are.equal("No lure", HudModel.Lines(build(s)).lure)
    end)

    it("shows the last catch with icon, name, and bite time", function()
        local s = session({ catch = 2 }, { lastItem = 6303, lastBite = 123 })
        local lines =
            HudModel.Lines(build(s, { itemName = "Raw Slitherskin Mackerel", itemIcon = 133910 }))
        assert.are.equal("Raw Slitherskin Mackerel, bite 12.3 s", lines.last)
        assert.are.equal(133910, lines.icon)
        -- Item data not loaded yet: the ID stands in until the name arrives.
        assert.are.equal("Item 6303, bite 12.3 s", HudModel.Lines(build(s)).last)
        s.lastBite = nil
        assert.are.equal("Item 6303", HudModel.Lines(build(s)).last)
        local none = HudModel.Lines(build(session({ timeout = 1 }), { itemIcon = 1 }))
        assert.are.equal("No catch yet", none.last)
        assert.is_nil(none.icon)
    end)

    it("formats durations and the text style", function()
        assert.are.equal("0 min", HudModel.Duration(59))
        assert.are.equal("59 min", HudModel.Duration(3599))
        assert.are.equal("1 h 05 min", HudModel.Duration(3900))
        local s = session({ catch = 34, getaway = 2, early_click = 4 }, { active = 1400 })
        local model = build(s, { rank = 51, modifier = 25, lureSeconds = 60 })
        assert.are.equal(
            "23 min, 34/40, 85 %, 87/h, Fishing 51 (+0), effective 76, Lure: 1 min left",
            HudModel.Short(model)
        )
    end)

    it("uses the active cap from the thresholds", function()
        local s = session({ catch = 1 }, { active = 100 })
        local t = ns.Stats.Thresholds({ activeCap = 30 })
        assert.are.equal(130, build(s, { now = s.last + 500, thresholds = t }).active)
        assert.are.equal(160, build(s, { now = s.last + 500 }).active)
    end)
end)
