local addon = require("spec.helpers.addon")

describe("FishingMastery Attempt classifier", function()
    local Attempt, classifier, finished

    before_each(function()
        Attempt = addon.load({ "Attempt.lua" }, nil, "FishingMastery").Attempt
        classifier = Attempt.NewClassifier()
        finished = {}
    end)

    local function feed(events)
        for _, event in ipairs(events) do
            for _, record in ipairs(classifier:Feed(event)) do
                finished[#finished + 1] = record
            end
        end
    end

    local function tick(now)
        for _, record in ipairs(classifier:Tick(now)) do
            finished[#finished + 1] = record
        end
    end

    local function start(t, spellID)
        feed({
            {
                t = t,
                name = "UNIT_SPELLCAST_CHANNEL_START",
                spellID = spellID or 7620,
                duration = 30,
            },
        })
    end

    local function stop(t, spellID)
        feed({ { t = t, name = "UNIT_SPELLCAST_CHANNEL_STOP", spellID = spellID or 7620 } })
    end

    local function message(t, msgName, name)
        feed({ { t = t, name = name or "UI_INFO_MESSAGE", msgName = msgName } })
    end

    local function outcomes()
        local list = {}
        for i, record in ipairs(finished) do
            list[i] = record.outcome
        end
        return list
    end

    describe("catch", function()
        it("ends at LOOT_CLOSED after the stop and keeps the bite time in tenths", function()
            start(100)
            stop(115.59)
            feed({
                { t = 115.706, name = "LOOT_READY", isFishingLoot = true, autoLoot = false },
                { t = 115.95, name = "LOOT_OPENED", isFishingLoot = true },
            })
            assert.are.same({}, finished)
            feed({ { t = 117, name = "LOOT_CLOSED" } })
            assert.are.same({ "catch" }, outcomes())
            assert.are.equal(157, finished[1].biteTenths)
            assert.is_false(finished[1].autoLoot)
            assert.is_false(classifier:Active())
        end)

        it("waits for the stop when the loot window closes first", function()
            start(100)
            feed({
                { t = 106.2, name = "LOOT_READY", isFishingLoot = true, autoLoot = true },
                { t = 106.3, name = "LOOT_CLOSED" },
            })
            assert.are.same({}, finished)
            stop(106.4)
            assert.are.same({ "catch" }, outcomes())
            assert.are.equal(62, finished[1].biteTenths)
            assert.is_true(finished[1].autoLoot)
        end)

        it("ignores loot that is not fishing loot", function()
            start(100)
            feed({ { t = 103, name = "LOOT_READY", isFishingLoot = false } })
            stop(103.1)
            feed({ { t = 103.2, name = "LOOT_CLOSED" } })
            tick(104.6)
            assert.are.same({ "cancel" }, outcomes())
            assert.is_nil(finished[1].biteTenths)
        end)
    end)

    describe("failures", function()
        it("counts a getaway with the message before or after the stop", function()
            start(100)
            message(112.77, "ERR_FISH_ESCAPED")
            stop(113.2)
            tick(114.7)
            start(200)
            stop(210)
            message(210.5, "ERR_FISH_ESCAPED")
            tick(211.5)
            assert.are.same({ "getaway", "getaway" }, outcomes())
            assert.is_nil(finished[1].biteTenths)
        end)

        it("counts an early click", function()
            start(100)
            stop(103.8)
            message(103.81, "ERR_FISH_NOT_HOOKED")
            tick(105.3)
            assert.are.same({ "early_click" }, outcomes())
        end)

        it("tells a timeout from a cancel by the channel length", function()
            start(100)
            stop(131.65) -- live timeouts stop after the nominal end
            tick(133.2)
            start(200)
            stop(229.6) -- within the 0.5 s tolerance
            tick(231.1)
            start(300)
            stop(305.07)
            tick(306.6)
            assert.are.same({ "timeout", "timeout", "cancel" }, outcomes())
        end)

        it("marks two signals as a conflict and keeps the strongest", function()
            start(100)
            message(110, "ERR_FISH_ESCAPED")
            feed({ { t = 110.1, name = "LOOT_READY", isFishingLoot = true } })
            stop(110.2)
            feed({ { t = 111, name = "LOOT_CLOSED" } })
            assert.are.equal("catch", finished[1].outcome)
            assert.are.equal("conflict", finished[1].note)
        end)

        it("ends as unknown without a channel length", function()
            feed({ { t = 100, name = "UNIT_SPELLCAST_CHANNEL_START", spellID = 7620 } })
            stop(101)
            tick(102.5)
            assert.are.equal("unknown", finished[1].outcome)
            assert.are.equal("no_duration", finished[1].note)
        end)
    end)

    describe("invalid target", function()
        local function fail(t, spellID)
            feed({ { t = t, name = "UNIT_SPELLCAST_FAILED", spellID = spellID or 7620 } })
        end

        it("pairs a fishing failure with a no-water or too-shallow message", function()
            fail(100)
            message(100.001, "SPELL_FAILED_NOT_FISHABLE", "UI_ERROR_MESSAGE")
            fail(105)
            message(105.001, "SPELL_FAILED_TOO_SHALLOW", "UI_ERROR_MESSAGE")
            assert.are.same({ "invalid_target", "invalid_target" }, outcomes())
            assert.are.equal(100.001, finished[1].start)
            assert.is_false(classifier:Active())
        end)

        it("needs a recent failure of the fishing spell", function()
            message(100, "SPELL_FAILED_NOT_FISHABLE", "UI_ERROR_MESSAGE")
            fail(101, 116)
            message(101.001, "SPELL_FAILED_NOT_FISHABLE", "UI_ERROR_MESSAGE")
            fail(102)
            message(103.5, "SPELL_FAILED_NOT_FISHABLE", "UI_ERROR_MESSAGE")
            assert.are.same({}, finished)
        end)

        it("counts one attempt per message when casts are spammed", function()
            for i = 1, 6 do
                fail(100 + i / 1000)
            end
            message(100.01, "SPELL_FAILED_NOT_FISHABLE", "UI_ERROR_MESSAGE")
            message(100.011, "SPELL_FAILED_TOO_SHALLOW", "UI_ERROR_MESSAGE")
            assert.are.same({ "invalid_target", "invalid_target" }, outcomes())
        end)

        it("ignores a failed recast inside a running channel", function()
            start(100)
            fail(100.27)
            message(100.27, "SPELL_FAILED_TOO_SHALLOW", "UI_ERROR_MESSAGE")
            feed({ { t = 100.3, name = "UNIT_SPELLCAST_FAILED_QUIET", spellID = 7620 } })
            assert.are.same({}, finished)
            feed({ { t = 106.2, name = "LOOT_READY", isFishingLoot = true } })
            stop(106.1)
            feed({ { t = 106.8, name = "LOOT_CLOSED" } })
            assert.are.same({ "catch" }, outcomes())
        end)

        it("ends a stopped attempt when a cast at bad water follows in the grace time", function()
            start(100)
            stop(102)
            fail(102.5)
            message(102.5, "SPELL_FAILED_NOT_FISHABLE", "UI_ERROR_MESSAGE")
            assert.are.same({ "cancel", "invalid_target" }, outcomes())
        end)
    end)

    describe("attempt end", function()
        it("waits 1.5 s after the stop", function()
            start(100)
            stop(105)
            assert.are.equal(106.5, classifier:Deadline())
            tick(106.4)
            assert.are.same({}, finished)
            tick(106.5)
            assert.are.same({ "cancel" }, outcomes())
            assert.is_nil(classifier:Deadline())
        end)

        it("ends at a new cast, which starts the next attempt", function()
            start(100)
            stop(100.23)
            start(100.23)
            assert.are.same({ "cancel" }, outcomes())
            assert.is_true(classifier:Active())
        end)

        it("marks an attempt without a stop as unknown when a new cast starts", function()
            start(100)
            start(110)
            assert.are.equal("unknown", finished[1].outcome)
            assert.are.equal("superseded", finished[1].note)
        end)

        it("ends a stuck attempt as unknown after 90 s", function()
            start(100)
            assert.are.equal(190, classifier:Deadline())
            tick(189)
            assert.are.same({}, finished)
            tick(190)
            assert.are.equal("unknown", finished[1].outcome)
            assert.are.equal("no_stop", finished[1].note)
        end)

        it("keeps a catch whose loot window stays open past 90 s", function()
            start(100)
            feed({ { t = 110, name = "LOOT_READY", isFishingLoot = true } })
            stop(110.1)
            tick(150)
            assert.are.same({}, finished)
            tick(190)
            assert.are.equal("catch", finished[1].outcome)
        end)
    end)

    describe("spell filter", function()
        it("ignores other channels and their stops", function()
            start(100, 1260270)
            stop(100.5, 1260270)
            tick(200)
            assert.is_false(classifier:Active())
            start(300)
            stop(301, 1260270)
            assert.is_nil(classifier.current.stop)
            assert.are.same({}, finished)
        end)

        it("uses the injected fishing check", function()
            classifier = Attempt.NewClassifier(function(spellID)
                return spellID == 99
            end)
            start(100, 99)
            assert.is_true(classifier:Active())
            start(101, 7620)
            assert.are.same({}, finished)
        end)

        it("ignores unknown events and non-table input", function()
            feed({ { t = 1, name = "ZONE_CHANGED" } })
            assert.are.same({}, classifier:Feed(nil))
            assert.are.same({}, finished)
        end)
    end)
end)
