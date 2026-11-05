-- Developer storage test logic: filling the test entry in steps, line test chunks, and load
-- measurements (FishingMastery/Stress.lua).
local addon = require("spec.helpers.addon")

local FILES = { "Codec.lua", "History.lua", "Totals.lua", "Synthetic.lua", "Stress.lua" }

describe("FishingMastery Stress", function()
    local ns, Stress

    before_each(function()
        ns = addon.load(FILES, nil, "FishingMastery")
        Stress = ns.Stress
    end)

    describe("test entry", function()
        it("fills in steps exactly like packing the same casts at once", function()
            local entry = Stress.NewEntry(12000)
            local nextCast = Stress.Generator()
            local steps = 0
            while not Stress.Fill(entry, nextCast, 5000) do
                steps = steps + 1
            end
            assert.are.equal(2, steps)
            assert.are.equal(12000, entry.written)
            local chunks, bytes = Stress.Finish(entry)
            assert.are.same({}, entry.casts)

            local reference = {
                casts = ns.Synthetic.Casts(12000, ns.Synthetic.START, Stress.SEED),
                days = {},
                quarantine = {},
            }
            ns.History.Pack(reference)
            assert.are.same(reference.days, entry.days)
            assert.are.equal(#reference.days, chunks)
            local total = 0
            for _, chunk in ipairs(entry.days) do
                total = total + #chunk
            end
            assert.are.equal(total, bytes)
            assert.are.same(ns.Totals.Rebuild(entry), entry.totals)
        end)

        it("never writes more than the target and keeps no function in the entry", function()
            local entry = Stress.NewEntry(7)
            assert.is_true(Stress.Fill(entry, Stress.Generator(), 5000))
            assert.are.equal(7, entry.written)
            Stress.Finish(entry)
            for _, value in pairs(entry) do
                assert.are_not.equal("function", type(value))
            end
            assert.are.equal(7, ns.History.Check(entry, 0).casts)
        end)
    end)

    describe("line test chunks", function()
        it("builds valid chunks close to 4,000 and 60,000 characters", function()
            local lines = Stress.Lines()
            assert.are.equal(2, #lines)
            for i, target in ipairs(Stress.LINE_LENGTHS) do
                assert.is_true(lines[i].length <= target)
                assert.is_true(lines[i].length > target - 100)
                assert.are.equal(lines[i].length, #lines[i].chunk)
            end
            assert.is_true(lines[2].casts > 4000)
            local results = Stress.CheckLines(lines)
            assert.is_true(results[1].ok)
            assert.is_true(results[2].ok)
        end)

        it("reports a cut or damaged chunk", function()
            local lines = Stress.Lines()
            lines[1].chunk = lines[1].chunk:sub(1, 2000)
            lines[2].chunk = lines[2].chunk .. ";x"
            local results = Stress.CheckLines(lines)
            assert.is_nil(results[1].ok)
            assert.are.equal("length or cast count changed", results[1].error)
            assert.is_nil(results[2].ok)
            assert.truthy(results[2].error:find("bad number", 1, true))
        end)
    end)

    describe("load measurement", function()
        it("gives the time from logout to ADDON_LOADED within a reload", function()
            assert.are.equal(2.5, Stress.ReloadTime({ logoutAt = 100 }, 102.5))
            assert.is_nil(Stress.ReloadTime({}, 102.5))
            assert.is_nil(Stress.ReloadTime({ logoutAt = 100 }, nil))
            assert.is_nil(Stress.ReloadTime({ logoutAt = 100 }, 50))
            assert.is_nil(Stress.ReloadTime({ logoutAt = 100 }, 100 + Stress.MAX_RELOAD + 1))
        end)

        it("keeps the newest measurements", function()
            local dev = {}
            for i = 1, Stress.MAX_LOADS + 3 do
                Stress.AddLoad(dev, { reload = i })
            end
            assert.are.equal(Stress.MAX_LOADS, #dev.loads)
            assert.are.equal(4, dev.loads[1].reload)
            assert.are.equal(Stress.MAX_LOADS + 3, dev.loads[#dev.loads].reload)
        end)

        it("creates the dev table only in db.dev", function()
            local db = { chars = {}, settings = {} }
            local dev = Stress.Dev(db)
            assert.are.equal(db.dev, dev)
            assert.are.equal(dev, Stress.Dev(db))
            assert.are.same({}, db.chars)
        end)
    end)
end)
