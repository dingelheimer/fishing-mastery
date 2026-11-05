-- Session summary builder (pure): times, rates with ranges, failures, skill, best and new fish,
-- vendor value, and the zone comparison shown only when its Newcombe range excludes 0.
local addon = require("spec.helpers.addon")

describe("FishingMastery session summary model", function()
    local ns, SummaryModel

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "Session.lua",
            "Stats.lua",
            "HudModel.lua",
            "SummaryModel.lua",
        }, nil, "FishingMastery")
        SummaryModel = ns.SummaryModel
    end)

    -- A session in map 1411 from 1000 to 2380 server time that ended idle.
    local function session(counts, fields)
        local s = {
            start = 1000,
            last = 2380,
            ended = 2380,
            endReason = "idle",
            casts = 0,
            catches = counts.catch or 0,
            counts = counts,
            zones = { 1411 },
            skillStart = 48,
            skill = 51,
            active = 1340,
            items = {},
        }
        for _, n in pairs(counts) do
            s.casts = s.casts + n
        end
        for key, value in pairs(fields or {}) do
            s[key] = value
        end
        return s
    end

    local ITEMS = {
        [6303] = { name = "Raw Slitherskin Mackerel", icon = 133910, quality = 1, sellPrice = 1 },
        [6358] = { name = "Oily Blackmouth", icon = 134300, quality = 1, sellPrice = 4 },
        [6289] = { name = "Raw Longjaw Mud Snapper", icon = 133890, quality = 1, sellPrice = 1 },
        [21071] = { name = "Raw Sagefish", icon = 133892, quality = 2, sellPrice = 2 },
    }

    local function totals(items, zone)
        return { items = items or {}, zones = { [1411] = zone or {} } }
    end

    it("adds the full cap for the last cast of an idle session and counts total time", function()
        local model =
            SummaryModel.Build({ session = session({ catch = 30, getaway = 3, early_click = 2 }) })
        assert.are.equal(1400, model.active)
        assert.are.equal(1380, model.total)
        assert.is_false(model.open)
        local lines = SummaryModel.Lines(model)
        assert.are.equal("23 min active of 23 min", lines[1])
        assert.are.equal("35 casts, 30 catches", lines[2])
        local low, high = ns.Stats.Wilson(30, 35)
        assert.are.equal(
            string.format(
                "Success rate 86 %% (95 %% range %d-%d %%, 35 fair casts)",
                math.floor(low * 100 + 0.5),
                math.floor(high * 100 + 0.5)
            ),
            lines[3]
        )
        assert.truthy(lines[4]:find("^Catches per hour 77 %(95 %% range %d+%-%d+%)$"))
        assert.are.equal("Failures: fish got away 3, clicked too early 2", lines[5])
        assert.are.equal("Fishing skill 48 -> 51 (+3)", lines[6])
        assert.are.equal(6, #lines) -- no items: no best fish, new fish, or value lines
    end)

    it("counts an open session up to now and a logout at its end", function()
        local open = session({ catch = 2 }, { ended = false, endReason = false })
        open.ended, open.endReason = nil, nil
        local model = SummaryModel.Build({ session = open, now = 2400 })
        assert.is_true(model.open)
        assert.are.equal(1360, model.active)
        assert.are.equal(1400, model.total)
        local logout = session({ catch = 2 }, { ended = 2390, endReason = "logout" })
        assert.are.equal(1350, SummaryModel.Build({ session = logout }).active)
        local lines = SummaryModel.Lines(SummaryModel.Build({ session = logout }))
        assert.are.equal("Success: 2 of 2 fair casts (too few for a rate)", lines[3])
        assert.are.equal("Catches per hour: too few casts", lines[4])
        assert.are.equal("Failures: none", lines[5])
    end)

    it("picks the best fish, lists new fish, and sums the vendor value", function()
        local s = session({ catch = 6 }, {
            items = { [6303] = 3, [6358] = 2, [6289] = 1, [21071] = 1 },
        })
        local model = SummaryModel.Build({
            session = s,
            items = ITEMS,
            totals = totals({
                [6303] = { n = 400, first = 10 },
                [6358] = { n = 9, first = 1200 }, -- first caught in this session
                [6289] = { n = 3, first = 500 },
                [21071] = { n = 1, first = 2000 },
            }),
        })
        assert.are.equal(21071, model.best.id) -- highest quality
        assert.are.same({ 6358, 21071 }, { model.newFish[1].id, model.newFish[2].id })
        assert.are.equal(3 * 1 + 2 * 4 + 1 + 2, model.value)
        local lines = SummaryModel.Lines(model)
        assert.are.equal("Best fish: |T133892:14:14|t Raw Sagefish x1", lines[7])
        local new = "New for this character: |T134300:14:14|t Oily Blackmouth, "
            .. "|T133892:14:14|t Raw Sagefish"
        assert.are.equal(new, lines[8])
        assert.are.equal("Vendor value 14c (36c per hour)", lines[9])

        -- Same quality: the rarest for this character wins.
        s.items = { [6303] = 3, [6289] = 1 }
        model = SummaryModel.Build({
            session = s,
            items = ITEMS,
            totals = totals({ [6303] = { n = 400, first = 10 }, [6289] = { n = 3, first = 500 } }),
        })
        assert.are.equal(6289, model.best.id)
        assert.are.equal(0, #model.newFish)
    end)

    it("shows item IDs and a partial value while item data is loading", function()
        local s = session({ catch = 2 }, { items = { [6303] = 1, [6358] = 1 } })
        local model = SummaryModel.Build({
            session = s,
            items = { [6303] = ITEMS[6303], [6358] = {} },
            totals = totals({}),
        })
        assert.is_true(model.missingPrice)
        local lines = SummaryModel.Lines(model)
        assert.truthy(lines[#lines]:find("some prices are still loading", 1, true))
        assert.truthy(table.concat(lines, "\n"):find("Item 6358", 1, true) == nil)
        assert.are.equal("Best fish: |T133910:14:14|t Raw Slitherskin Mackerel x1", lines[7])
        -- Without quality, the rarest unknown item can still be the best one.
        s.items = { [6358] = 1 }
        lines =
            SummaryModel.Lines(SummaryModel.Build({ session = s, items = {}, totals = totals() }))
        assert.are.equal("Best fish: Item 6358 x1", lines[7])
    end)

    it("formats money", function()
        assert.are.equal("7c", SummaryModel.Money(7))
        assert.are.equal("35s 07c", SummaryModel.Money(3507))
        assert.are.equal("1g 05s 20c", SummaryModel.Money(10520))
        assert.are.equal("0c", SummaryModel.Money(nil))
    end)

    it("compares with the rest of the zone only when the range excludes 0", function()
        local s = session({ catch = 38, timeout = 2 })
        -- Zone totals include the session: 38 + 40 catches of 40 + 80 fair casts.
        local zone = {
            off = { outcomes = { catch = 78, timeout = 42 } },
        }
        local model = SummaryModel.Build({ session = s, totals = totals({}, zone) })
        assert.is_table(model.compare)
        local diff = ns.Stats.Difference(38, 40, 40, 80)
        assert.are.equal(diff.low, model.compare.diff.low)
        local lines = SummaryModel.Lines(model, "Durotar")
        assert.are.equal(
            string.format(
                "Success rate 95 %% vs your 50 %% in Durotar: clearly higher (%+d to %+d points)",
                math.floor(diff.low * 100 + 0.5),
                math.floor(diff.high * 100 + 0.5)
            ),
            lines[#lines]
        )
        assert.truthy(SummaryModel.Lines(model)[#lines]:find("in zone 1411", 1, true))

        -- A small difference: no line.
        zone.off.outcomes = { catch = 38 + 70, timeout = 2 + 10 }
        assert.is_nil(SummaryModel.Build({ session = s, totals = totals({}, zone) }).compare)
        -- More than one zone in the session, or no other casts there: no line.
        zone.off.outcomes = { catch = 78, timeout = 42 }
        s.zones = { 1411, 1454 }
        assert.is_nil(SummaryModel.Build({ session = s, totals = totals({}, zone) }).compare)
        s.zones = { 1411 }
        zone.off.outcomes = { catch = 38, timeout = 2 }
        assert.is_nil(SummaryModel.Build({ session = s, totals = totals({}, zone) }).compare)
    end)
end)
