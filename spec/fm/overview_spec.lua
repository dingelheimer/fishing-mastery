-- The Statistics Overview model of Draft 1 (Story 9.3): headline numbers with ranges and grey
-- rules, where casts end, the five most caught items, the skill bar, the characters of the
-- Catches tooltip, empty data, and the skill points gained since tracking started.
local addon = require("spec.helpers.addon")

local DAY = 20763 * 86400
local HOUR5 = DAY + 5 * 3600

describe("FishingMastery overview model", function()
    local ns, Totals

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleUI.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "History.lua",
            "Session.lua",
            "Options.lua",
            "OptionsControls.lua",
            "Totals.lua",
            "Stats.lua",
            "Style.lua",
            "StatsView.lua",
            "StatsModel.lua",
            "SkillModel.lua",
            "OverviewModel.lua",
        }, nil, "FishingMastery")
        Totals = ns.Totals
    end)

    local ITEMS = {
        [6303] = { name = "Raw Slitherskin Mackerel", icon = 133910, hex = "ffffffff" },
        [6358] = { name = "Oily Blackmouth", icon = 133891, hex = "ff1eff00" },
    }

    local function info(id)
        return ITEMS[id]
    end

    -- A character with the casts { out, item } 20 s apart from HOUR5.
    local function char(name, casts)
        local totals = Totals.New()
        for i, cast in ipairs(casts) do
            Totals.Add(totals, {
                t = HOUR5 + i * 20,
                map = 1411,
                out = cast[1],
                loot = cast[2] and { { id = cast[2] } } or nil,
            })
        end
        return { name = name, totals = totals, subzones = {}, sessions = {} }
    end

    local function casts(spec)
        local list = {}
        for _, entry in ipairs(spec) do
            for _ = 1, entry[1] do
                list[#list + 1] = { entry[2], entry[3] }
            end
        end
        return list
    end

    local function build(chars, extra)
        local input = extra or {}
        input.model = ns.StatsModel.Overview({ chars = chars, current = "Player-1", now = HOUR5 })
        input.info = info
        return ns.OverviewModel.Build(input)
    end

    it("writes the headline numbers with their ranges and where casts end", function()
        local one = char(
            "Brannoc",
            casts({
                { 38, "catch", 6303 },
                { 2, "catch", 6358 },
                { 8, "getaway" },
                { 2, "cancel" },
                { 1, "invalid_target" },
            })
        )
        local model = build({ ["Player-1"] = one }, { sessions = 3 })
        local catches, success, rate, active = unpack(model.numbers)
        assert.are.same({ value = "40", label = "Catches", sub = "of 51 casts" }, catches)
        assert.are.equal("83", success.value)
        assert.are.equal("%", success.unit)
        assert.truthy(success.sub:find("^likely %d+ %- %d+ %%$"))
        assert.is_false(success.grey)
        assert.truthy(rate.sub:find("^likely %d+ %- %d+$"))
        assert.are.equal("/ h", rate.unit)
        assert.are.equal("in 3 sessions", active.sub)
        assert.truthy(active.value:find("^0 h %d%d min$"))
        assert.is_false(model.empty)

        local rows = {}
        for i, row in ipairs(model.outcomes) do
            rows[i] = { row.label, row.count, row.text, row.grey }
        end
        assert.are.same({
            { "Catch", "40", "83 %", false },
            { "Got away", "8", "17 %", false },
            { "Clicked too early", "0", "0 %", false },
            { "Not clicked (timeout)", "0", "0 %", false },
            { "Cancelled", "2", "-", true },
            { "Invalid target", "1", "-", true },
        }, rows)
        assert.is_nil(model.outcomes[5].share)
        assert.are.same(ns.Style.BAR_GREEN, model.outcomes[1].color)

        assert.are.equal(2, #model.top)
        assert.are.same({
            id = 6303,
            name = "Raw Slitherskin Mackerel",
            icon = 133910,
            hex = "ffffffff",
            n = "38",
            fill = 1,
        }, model.top[1])
        assert.are.equal(2 / 38, model.top[2].fill)
        assert.is_nil(model.characters) -- one character: no tooltip list
    end)

    it("greys small samples and keeps the top five", function()
        local one = char("Brannoc", {
            { "catch", 1 },
            { "catch", 2 },
            { "getaway" },
            { "catch", 3 },
            { "catch", 4 },
            { "catch", 5 },
            { "catch", 6 },
            { "catch", 6 },
        })
        local model = build({ ["Player-1"] = one })
        local success, rate = model.numbers[2], model.numbers[3]
        assert.are.same(
            { value = "7/8", label = "Success rate", sub = "few casts yet", grey = true },
            success
        )
        assert.are.equal("-", rate.value)
        assert.is_true(rate.grey)
        assert.are.equal(5, #model.top)
        assert.are.equal(6, model.top[1].id) -- caught twice
        assert.are.equal("Item 6", model.top[1].name) -- not in the item cache yet
        assert.are.equal(0.5, model.top[2].fill)
    end)

    it("lists every character for the Catches tooltip", function()
        local model = build({
            ["Player-1"] = char("Brannoc", casts({ { 5, "catch", 6303 } })),
            ["Player-2"] = char("Ysolde", casts({ { 3, "catch", 6303 }, { 1, "getaway" } })),
        })
        assert.are.same({
            { label = "Brannoc (you)", value = "5 of 5 casts" },
            { label = "Ysolde", value = "3 of 4 casts" },
        }, model.characters)
        assert.are.equal("8", model.numbers[1].value)
    end)

    it("handles a scope without casts", function()
        local model = build({})
        assert.is_true(model.empty)
        assert.are.equal("0", model.numbers[1].value)
        assert.are.same(
            { value = "-", label = "Success rate", sub = "no casts yet" },
            model.numbers[2]
        )
        assert.are.same({}, model.top)
        assert.are.equal("-", model.outcomes[1].text)
        assert.is_nil(model.skill)
    end)

    it(
        "writes the skill bar with the rank name, the effective skill, and the points gained",
        function()
            local skill =
                build({}, { skill = { rank = 154, max = 225, modifier = 25, gained = 12 } }).skill
            assert.are.same({
                rank = 154,
                max = 225,
                effective = 179,
                rankName = "Expert",
                bar = "Fishing 154 / 225",
                modifier = "+25 from lure and gear, effective 179 (white mark)",
                gained = "+12 skill points since you started tracking",
            }, skill)
            skill = build({}, { skill = { rank = 80, max = 0 } }).skill
            assert.are.equal(80, skill.max) -- an unknown cap is the rank
            assert.is_nil(skill.rankName)
            assert.are.equal("", skill.modifier)
            assert.are.equal("", skill.gained)

            local Gained = ns.SkillModel.Gained
            assert.are.equal(12, Gained({ { skillStart = 150 }, { skillStart = 142 }, {} }, 154))
            assert.are.equal(0, Gained({ { skillStart = 160 } }, 154))
            assert.is_nil(Gained({}, 154))
            assert.is_nil(Gained(nil, 154))
        end
    )
end)
