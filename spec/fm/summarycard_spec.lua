-- Session summary card (Story 10.5): SummaryCardModel draws a SummaryModel model as the card the
-- owner picked (title, water and active time, skill, three numbers between dividers, pairs, the
-- "Caught" table with at most 5 rows, the clear zone comparison); the chat lines stay the
-- sentences of SummaryModel.Lines.
local addon = require("spec.helpers.addon")
local tiplines = require("spec.helpers.tiplines")

describe("FishingMastery session summary card", function()
    local ns

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleUI.lua",
            "Session.lua",
            "Options.lua",
            "OptionsControls.lua",
            "Totals.lua",
            "Stats.lua",
            "Style.lua",
            "HudModel.lua",
            "RowTip.lua",
            "HudCardModel.lua",
            "SummaryModel.lua",
            "SessionTable.lua",
            "SummaryCardModel.lua",
        }, nil, "FishingMastery")
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

    local function mapName(map)
        return ({ [1411] = "Durotar", [1454] = "Orgrimmar" })[map]
    end

    local function lines(s, input)
        input = input or {}
        input.session = s
        input.totals = input.totals or { items = {}, zones = {} }
        local model = ns.SummaryModel.Build(input)
        return tiplines.lines(ns.SummaryCardModel.Draw(model, { session = s, mapName = mapName })),
            model
    end

    it("draws the card of an ended session with the numbers between dividers", function()
        local s = session({ catch = 34, getaway = 2, early_click = 4, cancel = 3 })
        local out = lines(s)
        assert.are.same({
            "Fishing session summary",
            "Durotar | 23 min",
            "Fishing 48 -> 51  +3",
            "---",
        }, { out[1], out[2], out[3], out[4] })
        assert.truthy(out[5]:find("^34 catches | %d+ %% success | %d+ per hour$"))
        assert.are.equal("---", out[6])
        assert.are.same({
            "Casts = 43 (23 min)",
            "Got away = 2",
            "Clicked too early = 4",
            "Cancelled = 3",
        }, { out[7], out[8], out[9], out[10] })
        assert.is_nil(table.concat(out, "\n"):find("Caught", 1, true)) -- no items, no table
        assert.is_nil(table.concat(out, "\n"):find("Vendor value", 1, true))
    end)

    it("shows small samples as counts and an open session as 'so far'", function()
        local s = session({ catch = 2, timeout = 1 }, { ended = false, zones = { 1411, 1454 } })
        s.ended = nil
        local out = lines(s, { now = 1100 })
        assert.are.equal("Fishing session so far", out[1])
        assert.truthy(out[2]:find("^Durotar %+1 | "))
        assert.are.equal("2 catches | 2/3 success | - per hour", out[5])
        local skillless = session({ catch = 1 }, { skillStart = "?" })
        assert.are.equal("---", lines(skillless)[3]) -- no skill line without a known skill
    end)

    it("lists the most caught first, at most five, with new fish and the value", function()
        local s = session({ catch = 21 })
        local items = {}
        for i = 1, 7 do
            s.items[1000 + i] = i
            items[1000 + i] = { name = "Fish " .. i, icon = 7, quality = 1, sellPrice = 10 }
        end
        local totals = { items = { [1007] = { n = 7, first = 1500 } }, zones = {} }
        local out = lines(s, { items = items, totals = totals })
        local text = table.concat(out, "\n")
        assert.truthy(text:find("Vendor value = 2s 80c (", 1, true))
        assert.truthy(text:find("\nCaught | Count | \n|T7:14:14|t Fish 7 | 7 | new\n", 1, true))
        assert.truthy(text:find("\n|T7:14:14|t Fish 3 | 3 | \n+2 more", 1, true))
        assert.is_nil(text:find("Fish 2 |", 1, true))
    end)

    it("says above or below the zone average only when it is clear", function()
        local s = session({ catch = 38, timeout = 2 })
        local zone = { off = { outcomes = { catch = 78, timeout = 42 } } }
        local out = lines(s, { totals = { items = {}, zones = { [1411] = zone } } })
        local text = table.concat(out, "\n")
        assert.truthy(text:find("\nAbove your average here\n95 % vs 50 % (+", 1, true))
        assert.truthy(text:find("pts%)$"))
        local low = session({ catch = 10, timeout = 30 })
        zone.off.outcomes = { catch = 10 + 70, timeout = 30 + 10 }
        text =
            table.concat(lines(low, { totals = { items = {}, zones = { [1411] = zone } } }), "\n")
        assert.truthy(text:find("Below your average here", 1, true))
    end)

    it("keeps the sentences for the chat style", function()
        local _, model = lines(session({ catch = 34, getaway = 2 }))
        local chat = ns.SummaryModel.Lines(model, "Durotar")
        assert.are.equal("23 min active of 23 min", chat[1])
        assert.are.equal("36 casts, 34 catches", chat[2])
    end)
end)
