-- Raw capture: ring buffer, aura and loot source readers, and the summary
-- (FishingMastery/Capture.lua).
local addon = require("spec.helpers.addon")

describe("FishingMastery Capture", function()
    local ns, Capture

    before_each(function()
        ns = addon.load({ "Context.lua", "Capture.lua" }, nil, "FishingMastery")
        Capture = ns.Capture
    end)

    describe("ring buffer", function()
        it("keeps the newest entries up to the cap, oldest first", function()
            local buffer = Capture.Repair(nil)
            for i = 1, 7 do
                Capture.Add(buffer, { t = i }, 5)
            end
            assert.are.equal(5, #buffer.entries)
            assert.are.equal(7, buffer.total)
            local times = {}
            for i, entry in ipairs(Capture.List(buffer, 5)) do
                times[i] = entry.t
            end
            assert.are.same({ 3, 4, 5, 6, 7 }, times)
        end)

        it("lists a buffer that is not full in order", function()
            local buffer = Capture.Repair(nil)
            Capture.Add(buffer, { t = 1 }, 5)
            Capture.Add(buffer, { t = 2 }, 5)
            assert.are.same({ { t = 1 }, { t = 2 } }, Capture.List(buffer, 5))
        end)

        it("caps at 2,000 entries by default", function()
            local buffer = Capture.Repair(nil)
            for i = 1, 2100 do
                Capture.Add(buffer, { t = i })
            end
            assert.are.equal(2000, #buffer.entries)
            assert.are.equal(101, Capture.List(buffer)[1].t)
        end)

        it("repairs a broken buffer", function()
            assert.are.same({ entries = {}, nextIndex = 1, total = 0 }, Capture.Repair("x"))
            local fixed = Capture.Repair({ entries = { { t = 1 } }, nextIndex = "a" })
            assert.are.equal(1, fixed.nextIndex)
            assert.are.equal(1, fixed.total)
        end)
    end)

    describe("readers", function()
        it("reads helpful aura spell IDs only", function()
            local secret = {}
            local env = {
                C_UnitAuras = {
                    GetAuraDataByIndex = function(unit, index, filter)
                        assert.are.equal("player", unit)
                        assert.are.equal("HELPFUL", filter)
                        local auras = {
                            { spellId = 1234, name = "Well Fed", sourceUnit = "party1" },
                            { spellId = secret },
                            { spellId = 5678 },
                        }
                        return auras[index]
                    end,
                },
            }
            _G.issecretvalue = function(value)
                return value == secret
            end
            ns = addon.load({ "Context.lua", "Capture.lua" }, nil, "FishingMastery")
            _G.issecretvalue = nil
            assert.are.same({ 1234, 5678 }, ns.Capture.Auras(env))
            assert.are.same({}, ns.Capture.Auras({}))
        end)

        it("keeps type and object ID, never players", function()
            assert.are.equal("GameObject:35591", Capture.Source("GameObject-0-1-2-3-35591-0000AB"))
            assert.are.equal("Creature:1234", Capture.Source("Creature-0-5827-0-12-1234-00001"))
            assert.are.equal("Item", Capture.Source("Item-5827-0-4000000ABCDEF"))
            assert.is_nil(Capture.Source("Player-5827-0ABCDEF0"))
            assert.is_nil(Capture.Source("not a guid"))
            assert.is_nil(Capture.Source(nil))
        end)

        it("reads every source of every loot slot", function()
            local env = {
                GetNumLootItems = function()
                    return 3
                end,
                GetLootSourceInfo = function(slot)
                    if slot == 1 then
                        return "GameObject-0-1-2-3-180582-0000AB", 1
                    elseif slot == 2 then
                        return "GameObject-0-1-2-3-35591-0000AB",
                            1,
                            "Player-5827-0ABCDEF0",
                            1,
                            "Creature-0-1-2-3-99-0001",
                            2
                    end
                    return nil
                end,
            }
            assert.are.same(
                { "GameObject:180582", "GameObject:35591", "Creature:99" },
                Capture.Sources(env)
            )
        end)
    end)

    it("summarizes auras and sources, most frequent first", function()
        local buffer = Capture.Repair(nil)
        Capture.Add(buffer, { k = "cast", t = 1, auras = { 10, 20 } })
        Capture.Add(buffer, { k = "cast", t = 2, auras = { 20 } })
        Capture.Add(buffer, { k = "loot", t = 3, src = { "GameObject:35591" } })
        local summary = Capture.Summary(buffer)
        assert.are.equal(2, summary.casts)
        assert.are.equal(1, summary.loots)
        assert.are.same({ { key = "20", count = 2 }, { key = "10", count = 1 } }, summary.auras)
        assert.are.same({ { key = "GameObject:35591", count = 1 } }, summary.sources)
    end)
end)
