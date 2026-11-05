local addon = require("spec.helpers.addon")
local replay = require("spec.helpers.replay")
local fixtures = dofile("spec/fixtures/live_attempts.lua")

local FILES = { "Guard.lua", "Events.lua", "Attempt.lua", "Context.lua", "Tracker.lua" }

-- Finds a fixture by its exact label, else by the first label that contains the text.
local function scenario(label)
    for _, entry in ipairs(fixtures) do
        if entry.label == label then
            return entry.events
        end
    end
    for _, entry in ipairs(fixtures) do
        if entry.label:find(label, 1, true) then
            return entry.events
        end
    end
    error("no fixture " .. label)
end

describe("FishingMastery Tracker", function()
    local ns

    before_each(function()
        ns = addon.load(FILES, nil, "FishingMastery")
    end)

    after_each(function()
        _G.issecretvalue = nil
    end)

    describe("message names", function()
        local env

        before_each(function()
            env = replay.new(ns).env
        end)

        it("takes the name from GetGameMessageInfo", function()
            assert.are.equal(
                "ERR_FISH_ESCAPED",
                ns.Tracker.MessageName(env, 418, "Your fish got away!")
            )
            assert.are.equal("ERR_ZONE_EXPLORED", ns.Tracker.MessageName(env, 412, "Discovered"))
        end)

        it("resolves a generic spell failure by its text", function()
            assert.are.equal(
                "SPELL_FAILED_NOT_FISHABLE",
                ns.Tracker.MessageName(env, 57, "Your cast didn't land in fishable water")
            )
            assert.are.equal(
                "SPELL_FAILED_TOO_SHALLOW",
                ns.Tracker.MessageName(env, 57, "Water too shallow")
            )
            assert.are.equal(
                "ERR_SPELL_FAILED_S",
                ns.Tracker.MessageName(env, 57, "Can't do that while moving")
            )
        end)

        it("compares texts when GetGameMessageInfo is missing", function()
            env.GetGameMessageInfo = nil
            assert.are.equal(
                "ERR_FISH_NOT_HOOKED",
                ns.Tracker.MessageName(env, 417, "No fish are hooked.")
            )
            assert.are.equal(
                "SPELL_FAILED_TOO_SHALLOW",
                ns.Tracker.MessageName(env, 57, "Water too shallow")
            )
            -- Invalid-target texts count only for the generic spell failure type.
            assert.is_nil(ns.Tracker.MessageName(env, 999, "Water too shallow"))
        end)

        it("follows the client's global strings, not English literals", function()
            env.SPELL_FAILED_NOT_FISHABLE = "Dein Wurf landete nicht in fischbarem Wasser"
            assert.are.equal(
                "SPELL_FAILED_NOT_FISHABLE",
                ns.Tracker.MessageName(env, 57, "Dein Wurf landete nicht in fischbarem Wasser")
            )
            assert.are.equal(
                "ERR_SPELL_FAILED_S",
                ns.Tracker.MessageName(env, 57, "Your cast didn't land in fishable water")
            )
        end)

        it("skips a missing global and secret values", function()
            env.SPELL_FAILED_TOO_SHALLOW = nil
            assert.are.equal(
                "ERR_SPELL_FAILED_S",
                ns.Tracker.MessageName(env, 57, "Water too shallow")
            )
            _G.issecretvalue = function(value)
                return value == "Your fish got away!"
            end
            ns = addon.load(FILES, nil, "FishingMastery")
            env.GetGameMessageInfo = nil
            assert.is_nil(ns.Tracker.MessageName(env, 418, "Your fish got away!"))
        end)
    end)

    describe("fishing spell check", function()
        it("accepts 7620 and a spell with the fishing name", function()
            local env = replay.new(ns).env
            replay.SPELL_NAMES[7621] = "Fishing"
            local check = ns.Tracker.FishingSpellCheck(env)
            assert.is_true(check(7620))
            assert.is_true(check(7621))
            assert.is_false(check(1260270))
            assert.is_false(check(nil))
            assert.is_false(check("7620"))
            replay.SPELL_NAMES[7621] = nil
            assert.is_true(check(7621)) -- cached
        end)

        it("rejects other spells when C_Spell is missing", function()
            local check = ns.Tracker.FishingSpellCheck({})
            assert.is_true(check(7620))
            assert.is_false(check(7621))
        end)
    end)

    describe("live log replay", function()
        local function run(label, opts)
            local runner = replay.new(ns, opts)
            runner.Run(scenario(label), 1000)
            runner.Finish()
            assert.are.equal(0, ns.Guard.errors)
            return runner
        end

        it("auto loot off: getaways before the stop, recast cancels, and catches", function()
            local runner = run("auto loot off")
            assert.are.same({
                "cancel",
                "getaway",
                "cancel",
                "catch",
                "cancel",
                "getaway",
                "catch",
                "catch",
                "catch",
                "catch",
                "getaway",
                "catch",
                "catch",
            }, runner.Outcomes())
            -- Bite times match the probe's live classification (15.71 s, 8.28 s, ...).
            assert.are.equal(157, runner.records[4].biteTenths)
            assert.are.equal(83, runner.records[7].biteTenths)
            assert.is_false(runner.records[4].autoLoot)
            assert.is_true(runner.records[13].autoLoot)
        end)

        it("auto loot on", function()
            local runner = run("auto loot on")
            assert.are.same({ "getaway", "catch", "cancel", "getaway", "catch" }, runner.Outcomes())
            assert.are.equal(147, runner.records[2].biteTenths)
            assert.is_true(runner.records[2].autoLoot)
        end)

        it("early clicks with the message before and after the stop", function()
            assert.are.same({ "early_click", "early_click" }, run("early clicks").Outcomes())
        end)

        it("cancel, timeouts, and cancels by moving or jumping", function()
            assert.are.same(
                { "cancel", "timeout", "timeout", "cancel", "cancel", "cancel" },
                run("two timeouts").Outcomes()
            )
        end)

        it("invalid targets, including cast spam", function()
            local outcomes = run("invalid target").Outcomes()
            assert.are.equal(8, #outcomes)
            for _, outcome in ipairs(outcomes) do
                assert.are.equal("invalid_target", outcome)
            end
        end)

        it("invalid targets without GetGameMessageInfo", function()
            assert.are.equal(8, #run("invalid target", { messageNames = false }).Outcomes())
        end)

        it("lure catch with a too-shallow recast inside the channel", function()
            local runner = run("lure catch")
            assert.are.same({ "catch" }, runner.Outcomes())
            assert.are.equal(62, runner.records[1].biteTenths)
        end)

        it("ignores non-fishing channels and herb loot", function()
            assert.are.same({}, run("herb loot").Outcomes())
            assert.are.same({}, run("non-fishing channel").Outcomes())
        end)

        it("counts outcomes and the last attempt", function()
            local tracker = run("early clicks").tracker
            assert.are.equal(2, tracker.total)
            assert.are.equal(2, tracker.counts.early_click)
            assert.are.equal("early_click", tracker.last.outcome)
        end)
    end)
end)
