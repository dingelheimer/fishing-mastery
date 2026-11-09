-- HUD model (pure): the session numbers, small-sample rules, durations, and the rate tooltip
-- lines of the minimap button (the card is tested in hudcardmodel_spec.lua).
local addon = require("spec.helpers.addon")

describe("FishingMastery HUD model", function()
    local ns, HudModel

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "Session.lua",
            "Options.lua",
            "OptionsControls.lua",
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
        assert.are.same({ 7, 4 }, { model.casts, model.catches })
        assert.are.equal("4/5", HudModel.Percent(model.success))
        assert.are.equal("-", HudModel.Rate(model.perHour))
        assert.are.same({
            "Success: 4 of 5 fair casts (too few for a rate)",
            "Catches per hour: too few casts yet",
        }, HudModel.Tooltip(model))
    end)

    it("greys the rates below 30 fair casts and shows them in full above", function()
        local few = build(session({ catch = 15, timeout = 5 }, { active = 600 }))
        assert.are.equal("few", few.success.display)
        assert.are.equal("75 %", HudModel.Percent(few.success))
        assert.are.equal("90/h", HudModel.Rate(few.perHour))
        assert.are.equal(
            "Grey: fewer than 30 fair casts, the range is still wide.",
            HudModel.Tooltip(few)[3]
        )

        local s = session({ catch = 34, getaway = 2, early_click = 4, cancel = 3 }, {
            active = 1380,
        })
        local model = build(s, { now = s.last + 20 }) -- 1,400 s active
        assert.are.equal(1400, model.active)
        assert.are.equal("full", model.success.display)
        assert.are.equal("87/h", HudModel.Rate(model.perHour))
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

    it("keeps rank, skill-ups, the effective skill, the lure, and the last catch", function()
        local s = session({ catch = 1 }, { skillStart = 48, skill = 51, lastItem = 6303 })
        s.lastBite = 123
        local model = build(s, {
            rank = 51,
            modifier = 25,
            lureSeconds = 481,
            itemName = "Raw Slitherskin Mackerel",
            itemIcon = 133910,
        })
        assert.are.same({ 51, 3, 76, 481, 6303, 123, "Raw Slitherskin Mackerel", 133910 }, {
            model.rank,
            model.skillUps,
            model.effective,
            model.lureSeconds,
            model.lastItem,
            model.lastBite,
            model.itemName,
            model.itemIcon,
        })
        -- Without Fishing data the session's rank is used and there is no effective skill.
        assert.are.equal(51, build(s).rank)
        assert.is_nil(build(s).effective)
        assert.is_nil(build(session({})).rank)
    end)

    it("formats durations", function()
        assert.are.equal("0 min", HudModel.Duration(59))
        assert.are.equal("59 min", HudModel.Duration(3599))
        assert.are.equal("1 h 05 min", HudModel.Duration(3900))
    end)

    it("uses this login's active cap T, not a changed setting", function()
        local s = session({ catch = 1 }, { active = 100 })
        ns.Totals.SetCap(30)
        local t = ns.Stats.Thresholds({ activeCap = 90 })
        ns.Totals.SetCap(60)
        assert.are.equal(30, t.activeCap)
        assert.are.equal(130, build(s, { now = s.last + 500, thresholds = t }).active)
        assert.are.equal(160, build(s, { now = s.last + 500 }).active)
    end)
end)
