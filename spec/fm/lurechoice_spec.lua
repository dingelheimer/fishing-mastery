-- LureChoice.lua: every branch of the smart lure choice (no lure needed, the cheapest that
-- stops getaways, the strongest, none owned or usable, unknown base and skill, a running lure,
-- a lure being applied, a running lure of another kind).
local addon = require("spec.helpers.addon")

describe("FishingMastery lure choice", function()
    local Choose
    local BAUBLE = { id = 6529, bonus = 25, need = 1 }
    local CRAWLERS = { id = 6530, bonus = 50, need = 50 }
    local BRIGHT = { id = 6532, bonus = 75, need = 100 }
    local ATTRACTOR = { id = 6533, bonus = 100, need = 100 }
    local ALL = { ATTRACTOR, BAUBLE, BRIGHT, CRAWLERS }

    before_each(function()
        local ns = addon.load({ "Getaway.lua", "LureChoice.lua" }, { L = {} }, "FishingMastery")
        Choose = ns.LureChoice.Choose
    end)

    local function choose(input)
        local c = Choose(input)
        return c.action, c.reason, c.lure and c.lure.id, c.goal
    end

    it("uses no lure when the skill already stops getaways", function()
        -- Base 55: getaways stop at 150.
        assert.are.same(
            { "none", "enough", nil, 150 },
            { choose({ base = 55, skill = 150, rank = 150, lures = ALL }) }
        )
    end)

    it("uses the cheapest owned lure that stops getaways", function()
        local input = { base = 55, skill = 110, rank = 110, lures = ALL }
        assert.are.same({ "lure", "reaches", 6530, 150 }, { choose(input) })
        input.skill = 126
        assert.are.same({ "lure", "reaches", 6529, 150 }, { choose(input) })
        input.skill = 76 -- +75 reaches 151
        assert.are.same({ "lure", "reaches", 6532, 150 }, { choose(input) })
    end)

    it("uses the strongest usable lure when none stops getaways", function()
        local input = { base = 130, skill = 110, rank = 110, lures = ALL }
        assert.are.same({ "lure", "strongest", 6533, 225 }, { choose(input) })
        -- Below 100 the strong lures cannot be used yet.
        input.rank, input.skill = 60, 60
        assert.are.same({ "lure", "strongest", 6530, 225 }, { choose(input) })
        input.rank, input.skill = 20, 20
        assert.are.same({ "lure", "strongest", 6529, 225 }, { choose(input) })
    end)

    it("uses nothing without a usable lure", function()
        assert.are.same(
            { "none", "no-lures", nil, 150 },
            { choose({ base = 55, skill = 110, rank = 110, lures = {} }) }
        )
        assert.are.same(
            { "none", "no-lures", nil, 150 },
            { choose({ base = 55, skill = 40, rank = 40, lures = { BRIGHT } }) }
        )
        assert.are.equal("no-lures", Choose({ base = 55, skill = 40, rank = 40 }).reason)
    end)

    it("uses the strongest lure in water without data, nothing without a skill", function()
        assert.are.same(
            { "lure", "unknown-base", 6533, nil },
            { choose({ skill = 110, rank = 110, lures = ALL }) }
        )
        assert.are.same({ "none", "unknown-skill", nil, 150 }, {
            choose({ base = 55, rank = 110, lures = ALL }),
        })
    end)

    it("leaves a running lure alone and waits while one is applied", function()
        local input = {
            base = 130,
            skill = 110,
            rank = 110,
            lures = ALL,
            active = { bonus = 100, seconds = 31 },
        }
        assert.are.same({ "none", "active", nil, 225 }, { choose(input) })
        input.active.seconds = nil -- time unknown: left alone too
        assert.are.equal("active", Choose(input).reason)
        -- 30 s or less: renewed with the same kind only.
        input.active.seconds = 30
        assert.are.same({ "lure", "strongest", 6533, 225 }, { choose(input) })
        input.active.bonus = 50
        assert.are.same({ "none", "other-running", 6533, 225 }, { choose(input) })
        input.active.bonus = nil -- an unknown running lure
        assert.are.equal("other-running", Choose(input).reason)
        input.applying = true
        assert.are.same({ "wait", "applying", nil, 225 }, { choose(input) })
        input.active = nil
        assert.are.equal("wait", Choose(input).action)
    end)
end)
