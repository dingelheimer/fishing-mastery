-- Boot tests for the schema 2 update: saved data of schema 1 is migrated, the totals are counted
-- again in steps after login (together with the load check), a cast during the count is counted
-- once, and /fm status says so until the count is done.
local addon = require("spec.helpers.addon")
local fmboot = require("spec.helpers.fmboot")
local synthetic = require("spec.helpers.synthetic")

local GUID = fmboot.GUID

describe("FishingMastery totals rebuild boot", function()
    local w, pure

    before_each(function()
        pure = addon.load(
            { "Codec.lua", "History.lua", "Options.lua", "Totals.lua" },
            nil,
            "FishingMastery"
        )
        w = fmboot.new()
    end)

    after_each(function()
        w.cleanup()
    end)

    -- Schema 1 data: a packed history of 12,000 casts (about 50 chunks, 5 steps) and old totals
    -- without a version.
    local function schema1()
        local char = { casts = synthetic.casts(12000, 1793836800, 5), days = {}, quarantine = {} }
        pure.History.Pack(char)
        return {
            schemaVersion = 1,
            chars = {
                [GUID] = {
                    name = "Dingel",
                    part = "Brightwater",
                    firstSeen = 1,
                    lastSeen = 2,
                    days = char.days,
                    totals = { outcomes = { catch = 1 }, days = {}, maps = {} },
                },
            },
            settings = {},
        }
    end

    it("migrates, counts the history in steps, and counts a live cast once", function()
        w.boot(schema1(), nil)
        local db = _G.FishingMasteryDB
        assert.are.equal(2, db.schemaVersion)
        assert.truthy(w.output():find("upgraded from schema 1 to 2", 1, true))
        assert.is_table(db.migrationSnapshot)
        local castLog = w.ns.castLog
        assert.is_true(castLog:Counting())
        _G.SlashCmdList.FM("status")
        assert.truthy(w.output():find("Counting your history", 1, true))

        w.fire("PLAYER_ENTERING_WORLD", true, false)
        w.catch(5000, 8)
        local steps = 0
        while castLog:Counting() do
            w.runTimers(w.clock + 0.01)
            steps = steps + 1
            assert.is_true(steps < 100)
        end
        assert.is_true(steps >= 4)
        local char = db.chars[GUID]
        assert.is_true(w.ns.Totals.Current(char.totals))
        assert.are.same(pure.Totals.Rebuild(char), char.totals)
        local catches = 0
        for cast in pure.History.Iterate(char) do
            catches = catches + (cast.out == "catch" and 1 or 0)
        end
        assert.are.equal(catches, char.totals.outcomes.catch)
        assert.are.equal(1, #char.casts)

        w.printed = {}
        _G.SlashCmdList.FM("status")
        assert.is_nil(w.output():find("Counting your history", 1, true))
        assert.are.equal(0, w.ns.Guard.errors)

        -- The next clean login drops the snapshot and does not count again.
        w.fire("PLAYER_LOGOUT")
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)
        assert.is_nil(_G.FishingMasteryDB.migrationSnapshot)
        assert.is_false(w.ns.castLog:Counting())
    end)

    it("counts restored stale totals again at the next login", function()
        w.boot(nil, nil)
        w.catch(5000, 8)
        local char = _G.FishingMasteryDB.chars[GUID]
        char.totals = { outcomes = {}, days = {}, maps = {} } -- e.g. a restored old snapshot
        w.fire("PLAYER_LOGOUT")
        w.boot(_G.FishingMasteryDB, _G.FishingMasteryCharDB)
        -- One step is enough for one chunk; the count ends at login.
        assert.is_false(w.ns.castLog:Counting())
        char = _G.FishingMasteryDB.chars[GUID]
        assert.are.equal(1, char.totals.outcomes.catch)
        assert.are.equal(w.ns.Totals.VERSION, char.totals.version)
    end)
end)
