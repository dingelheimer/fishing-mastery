local addon = require("spec.helpers.addon")

describe("Attempt classifier", function()
    local Attempt, classifier

    before_each(function()
        Attempt = addon.load({ "Attempt.lua" }).Attempt
        classifier = Attempt.NewClassifier()
    end)

    local function start(t, duration)
        return classifier:Feed({
            t = t,
            name = "UNIT_SPELLCAST_CHANNEL_START",
            spellID = 7620,
            duration = duration == nil and 30 or duration or nil,
        })
    end

    -- Feeds { t, name, ... } events in order and returns all finished records.
    local function feed(events)
        local finished = {}
        for _, event in ipairs(events) do
            for _, record in ipairs(classifier:Feed(event)) do
                finished[#finished + 1] = record
            end
        end
        return finished
    end

    local function tick(now)
        return classifier:Tick(now)
    end

    it("classifies a catch with stop before loot", function()
        start(100)
        local finished = feed({
            { t = 104, name = "UNIT_SPELLCAST_CHANNEL_STOP" },
            { t = 104.1, name = "LOOT_READY", isFishingLoot = true },
            { t = 104.2, name = "LOOT_OPENED", isFishingLoot = true },
            { t = 106, name = "LOOT_CLOSED" },
        })
        assert.are.equal(1, #finished)
        local record = finished[1]
        assert.are.equal("catch", record.outcome)
        assert.are.equal(4, record.elapsed)
        assert.is_true(math.abs(record.biteTime - 4.1) < 1e-9)
        assert.are.equal(7620, record.spellID)
        assert.is_nil(record.raw)
        assert.are.same({
            "UNIT_SPELLCAST_CHANNEL_START",
            "UNIT_SPELLCAST_CHANNEL_STOP",
            "LOOT_READY",
            "LOOT_OPENED",
            "LOOT_CLOSED",
        }, record.events)
        assert.is_false(classifier:Active())
    end)

    it("classifies a catch with auto loot where loot closes before the stop", function()
        start(100)
        local finished = feed({
            { t = 105, name = "LOOT_READY", isFishingLoot = true },
            { t = 105.1, name = "LOOT_CLOSED" },
        })
        assert.are.equal(0, #finished)
        finished = feed({ { t = 105.2, name = "UNIT_SPELLCAST_CHANNEL_STOP" } })
        assert.are.equal("catch", finished[1].outcome)
    end)

    it("classifies a timeout at the full channel duration", function()
        start(100)
        feed({ { t = 129.8, name = "UNIT_SPELLCAST_CHANNEL_STOP" } })
        assert.are.same({}, tick(130))
        local finished = tick(129.8 + Attempt.GRACE)
        assert.are.equal("timeout", finished[1].outcome)
        assert.are.equal("Q12", Attempt.QUESTIONS.timeout)
    end)

    it("classifies an early stop as cancel and an interrupt as cancel", function()
        start(100)
        feed({ { t = 101, name = "UNIT_SPELLCAST_CHANNEL_STOP" } })
        assert.are.equal("cancel", tick(110)[1].outcome)
        start(200, false)
        feed({
            { t = 201, name = "UNIT_SPELLCAST_INTERRUPTED" },
            { t = 201, name = "UNIT_SPELLCAST_CHANNEL_STOP" },
        })
        local record = tick(210)[1]
        assert.are.equal("cancel", record.outcome)
        assert.is_true(record.interrupted)
    end)

    it("classifies getaway and early click from message names", function()
        start(100)
        feed({
            { t = 110, name = "UI_ERROR_MESSAGE", msgName = "ERR_FISH_ESCAPED" },
            { t = 110.1, name = "UNIT_SPELLCAST_CHANNEL_STOP" },
        })
        local record = tick(115)[1]
        assert.are.equal("getaway", record.outcome)
        assert.are.same({ "ERR_FISH_ESCAPED" }, record.messages)
        start(200)
        feed({
            { t = 202, name = "UNIT_SPELLCAST_CHANNEL_STOP" },
            { t = 202.5, name = "UI_ERROR_MESSAGE", msgName = "ERR_FISH_NOT_HOOKED" },
        })
        assert.are.equal("early_click", tick(210)[1].outcome)
    end)

    it("records an invalid target cast that never channels", function()
        local finished = feed({
            { t = 50, name = "UNIT_SPELLCAST_FAILED", spellID = 7620 },
            { t = 50, name = "UI_ERROR_MESSAGE", msgName = "SPELL_FAILED_NOT_FISHABLE" },
        })
        assert.are.equal(1, #finished)
        assert.are.equal("invalid_target", finished[1].outcome)
        assert.is_false(classifier:Active())
    end)

    it("ignores unrelated messages while idle", function()
        assert.are.same({}, feed({ { t = 1, name = "UI_ERROR_MESSAGE", msgName = "ERR_OTHER" } }))
    end)

    it("keeps raw events for unknown outcomes", function()
        start(100, false)
        feed({ { t = 105, name = "UNIT_SPELLCAST_CHANNEL_STOP" } })
        local record = tick(110)[1]
        assert.are.equal("unknown", record.outcome)
        assert.are.equal("no_duration", record.note)
        assert.are.equal(2, #record.raw)
    end)

    it("ends a superseded attempt as unknown", function()
        start(100)
        local finished = start(105)
        assert.are.equal("unknown", finished[1].outcome)
        assert.are.equal("superseded", finished[1].note)
        assert.is_true(classifier:Active())
        assert.are.equal(2, classifier.current.id)
    end)

    it("ends an attempt without a stop after the maximum age", function()
        start(100)
        assert.are.same({}, tick(100 + Attempt.MAX_AGE - 1))
        local record = tick(100 + Attempt.MAX_AGE)[1]
        assert.are.equal("unknown", record.outcome)
        assert.are.equal("no_stop", record.note)
    end)

    it("waits for an open loot window", function()
        start(100)
        feed({
            { t = 104, name = "UNIT_SPELLCAST_CHANNEL_STOP" },
            { t = 104.1, name = "LOOT_READY", isFishingLoot = true },
        })
        assert.are.same({}, tick(120))
        assert.are.equal("catch", tick(100 + Attempt.MAX_LOOT_AGE)[1].outcome)
    end)

    it("does not count non-fishing loot as a catch", function()
        start(100)
        feed({
            { t = 101, name = "LOOT_READY", isFishingLoot = false },
            { t = 102, name = "UNIT_SPELLCAST_CHANNEL_STOP" },
        })
        local record = tick(110)[1]
        assert.are.equal("cancel", record.outcome)
        assert.is_true(record.nonFishingLoot)
    end)

    it("marks conflicting signals and keeps raw events", function()
        start(100)
        local finished = feed({
            { t = 103, name = "UI_ERROR_MESSAGE", msgName = "ERR_FISH_ESCAPED" },
            { t = 104, name = "LOOT_READY", isFishingLoot = true },
            { t = 104.1, name = "LOOT_CLOSED" },
            { t = 104.2, name = "UNIT_SPELLCAST_CHANNEL_STOP" },
        })
        assert.are.equal("catch", finished[1].outcome)
        assert.are.equal("conflict", finished[1].note)
        assert.is_not_nil(finished[1].raw)
    end)

    it("caps the event list", function()
        start(100)
        for i = 1, Attempt.MAX_EVENTS + 5 do
            classifier:Feed({ t = 100 + i / 100, name = "UNIT_SPELLCAST_CHANNEL_UPDATE" })
        end
        feed({ { t = 101, name = "UNIT_SPELLCAST_CHANNEL_STOP" } })
        local record = tick(110)[1]
        assert.are.equal(Attempt.MAX_EVENTS, #record.events)
        assert.are.equal(7, record.eventsCut) -- start + 55 updates + stop = 57
    end)

    it("counts outcomes", function()
        local stats = { total = 0, byOutcome = {} }
        Attempt.Count(
            stats,
            { { outcome = "catch" }, { outcome = "timeout" }, { outcome = "catch" } }
        )
        assert.are.same(
            { total = 3, last = "catch", byOutcome = { catch = 2, timeout = 1 } },
            stats
        )
    end)
end)
