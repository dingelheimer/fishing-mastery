-- Stress test for the saved data budget: 200,000 synthetic casts packed into day chunks, written
-- in the Forever client's SavedVariables format, and loaded back. LuaJIT's constant limit
-- (65,536) is lower than the client's (262,143), so a load here also passes in the client.
local addon = require("spec.helpers.addon")
local synthetic = require("spec.helpers.synthetic")

local CASTS = 200000

describe("FishingMastery storage stress", function()
    local ns, char, casts

    setup(function()
        ns = addon.load({ "Codec.lua", "History.lua", "Totals.lua" }, nil, "FishingMastery")
        casts = synthetic.casts(CASTS, 1793836800, 42)
        char = { casts = casts, days = {}, quarantine = {} }
        ns.History.Pack(char)
    end)

    it("packs 200,000 casts below 26 bytes per cast on average", function()
        local bytes = 0
        for _, chunk in ipairs(char.days) do
            assert.is_true(#chunk <= ns.Codec.CHUNK_CAP)
            bytes = bytes + #chunk
        end
        local perCast = bytes / CASTS
        print(
            string.format("\n  storage: %d chunks, %.2f bytes/cast in chunks", #char.days, perCast)
        )
        assert.is_true(perCast < 26)
    end)

    it("loads in the client writer format without a constant overflow", function()
        local text = synthetic.write("FishingMasteryDB", {
            schemaVersion = 1,
            chars = {
                ["Player-5827-0ABCDEF0"] = { days = char.days, totals = ns.Totals.Rebuild(char) },
            },
        })
        print(
            string.format(
                "  storage: file %.2f MB, %.2f bytes/cast",
                #text / 1048576,
                #text / CASTS
            )
        )
        local chunk = assert(loadstring(text, "=FishingMasteryDB"))
        local env = {}
        setfenv(chunk, env)
        chunk()
        local loaded =
            { casts = {}, days = env.FishingMasteryDB.chars["Player-5827-0ABCDEF0"].days }
        loaded.quarantine = {}
        local result = ns.History.Check(loaded, 0)
        assert.are.equal(CASTS, result.casts)
        assert.are.equal(0, result.quarantined)
    end)

    it("decodes the whole history back to the same casts", function()
        local i = 0
        for cast in ns.History.Iterate(char) do
            i = i + 1
            if i % 997 == 0 then
                assert.are.same(casts[i], cast)
            end
        end
        assert.are.equal(CASTS, i)
    end)
end)
