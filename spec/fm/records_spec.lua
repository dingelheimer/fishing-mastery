local addon = require("spec.helpers.addon")

local FILES = { "Context.lua", "Loot.lua", "Items.lua", "Records.lua" }

describe("FishingMastery cast records", function()
    local ns

    before_each(function()
        ns = addon.load(FILES, nil, "FishingMastery")
    end)

    after_each(function()
        _G.issecretvalue = nil
    end)

    describe("Context", function()
        local function env(opts)
            opts = opts or {}
            return {
                GetServerTime = function()
                    return 1793836800
                end,
                C_Map = {
                    GetBestMapForUnit = function(unit)
                        assert.are.equal("player", unit)
                        return 1411
                    end,
                },
                GetSubZoneText = function()
                    return opts.subzone == nil and "Darkspear Strand" or opts.subzone
                end,
                GetProfessions = function()
                    if opts.noFishing then
                        return 5, nil, nil, nil, 6
                    end
                    return 5, nil, nil, 7, 6
                end,
                GetProfessionInfo = function(index)
                    assert.are.equal(7, index)
                    return "Fishing", 1, 11, 75, 2, 19, 356, opts.modifier or 0, -1, 0
                end,
                GetWeaponEnchantInfo = function()
                    if opts.lure then
                        return true, 584149, 0, opts.lure, false
                    end
                    return false, nil, nil, nil
                end,
            }
        end

        it("reads time, map, subzone, fishing rank and modifier, and the lure", function()
            assert.are.same({
                time = 1793836800,
                map = 1411,
                subzone = "Darkspear Strand",
                rank = 11,
                modifier = 25,
                lure = 263,
            }, ns.Context.Read(env({ lure = 263, modifier = 25 })))
        end)

        it("leaves fields empty without a lure, a subzone, or Fishing", function()
            local ctx = ns.Context.Read(env({ subzone = "", noFishing = true }))
            assert.is_nil(ctx.lure)
            assert.is_nil(ctx.subzone)
            assert.is_nil(ctx.rank)
            assert.is_nil(ctx.modifier)
            assert.are.equal(1411, ctx.map)
        end)

        it("survives missing and failing APIs", function()
            local ctx = ns.Context.Read({
                GetServerTime = function()
                    error("broken")
                end,
            })
            assert.are.same({}, ctx)
        end)
    end)

    describe("Loot", function()
        local function lootEnv(slots)
            return {
                GetNumLootItems = function()
                    return #slots
                end,
                GetLootSlotLink = function(slot)
                    return slots[slot].link
                end,
                GetLootSlotInfo = function(slot)
                    local s = slots[slot]
                    return 1, "name", s.qty, nil, s.q, false
                end,
                GetLootSourceInfo = function(slot)
                    return slots[slot].source, 1
                end,
            }
        end

        it("reads every item slot and the first source; coins are skipped", function()
            local loot = ns.Loot.Read(lootEnv({
                { link = nil, qty = 5, q = 0, source = "GameObject-0-1-2-3-35591-0000ABCD" },
                {
                    link = "|cnIQ1:|Hitem:6303::::::::5:1482|h[Mackerel]|h|r",
                    qty = 2,
                    q = 1,
                    source = "GameObject-0-1-2-3-35591-0000ABCD",
                },
                { link = "|Hitem:6358::|h[Oily Blackmouth]|h", qty = 1, q = nil },
            }))
            assert.are.same({
                items = { { id = 6303, qty = 2, q = 1 }, { id = 6358, qty = 1 } },
                srcType = "GameObject",
                srcId = 35591,
            }, loot)
        end)

        it("parses source GUIDs and never keeps a player GUID", function()
            assert.are.same(
                { "GameObject", 180582 },
                { ns.Loot.Source("GameObject-0-4170-0-12-180582-00002A1B3C") }
            )
            assert.are.same({}, { ns.Loot.Source("Player-5827-0ABCDEF0") })
            assert.are.same({}, { ns.Loot.Source(nil) })
            _G.issecretvalue = function()
                return true
            end
            ns = addon.load(FILES, nil, "FishingMastery")
            assert.are.same({}, { ns.Loot.Source("GameObject-0-1-2-3-35591-0000ABCD") })
        end)

        it("caps the slot count and handles a missing loot API", function()
            local slots = {}
            for i = 1, 15 do
                slots[i] = { link = "|Hitem:" .. i .. ":|h", qty = 1, q = 1 }
            end
            assert.are.equal(ns.Loot.MAX_SLOTS, #ns.Loot.Read(lootEnv(slots)).items)
            assert.are.same({ items = {} }, ns.Loot.Read({}))
        end)
    end)

    describe("Items", function()
        local cached, requested, env

        before_each(function()
            cached, requested = {}, {}
            env = {
                C_Item = {
                    GetItemInfo = function(id)
                        if cached[id] then
                            return "name", "link", cached[id]
                        end
                    end,
                    RequestLoadItemDataByID = function(id)
                        requested[#requested + 1] = id
                    end,
                },
            }
        end)

        it("fills quality at once when the item is cached", function()
            cached[6303] = 1
            local entry = { id = 6303 }
            ns.Items.New(env):Fill(entry)
            assert.are.equal(1, entry.q)
            assert.are.same({}, requested)
        end)

        it("requests an uncached item once and fills every waiting entry on load", function()
            local items = ns.Items.New(env)
            local a, b = { id = 13755 }, { id = 13755 }
            items:Fill(a)
            items:Fill(b)
            assert.are.same({ 13755 }, requested)
            assert.is_nil(a.q)
            cached[13755] = 2
            items:OnLoaded(999, true)
            items:OnLoaded(13755, true)
            assert.are.equal(2, a.q)
            assert.are.equal(2, b.q)
            assert.are.equal(0, items.count)
        end)

        it("keeps quality empty when loading fails and caps waiting entries", function()
            local items = ns.Items.New(env)
            local entry = { id = 1 }
            items:Fill(entry)
            items:OnLoaded(1, false)
            assert.is_nil(entry.q)
            for i = 1, ns.Items.MAX_PENDING + 5 do
                items:Fill({ id = 100 + i })
            end
            assert.are.equal(ns.Items.MAX_PENDING, items.count)
        end)
    end)

    describe("Records", function()
        local char

        before_each(function()
            char = { subzones = {} }
        end)

        local function ctx(fields)
            local base = { time = 100, map = 1411, subzone = "Darkspear Strand", rank = 11 }
            for key, value in pairs(fields or {}) do
                base[key] = value
            end
            return base
        end

        it("builds a catch with lure, multi-slot loot, and source", function()
            local cast = ns.Records.Build(char, {
                outcome = "catch",
                biteTenths = 157,
                autoLoot = true,
                ctx = ctx({ modifier = 25, lure = 263 }),
                loot = {
                    items = { { id = 6303, qty = 1, q = 1 }, { id = 6358, qty = 2 } },
                    srcType = "GameObject",
                    srcId = 35591,
                },
            }, 999)
            assert.are.same({
                t = 100,
                map = 1411,
                sub = 1,
                rank = 11,
                mod = 25,
                lure = 263,
                out = "catch",
                bite = 157,
                auto = true,
                loot = { { id = 6303, qty = 1, q = 1 }, { id = 6358, qty = 2 } },
                srcType = "GameObject",
                srcId = 35591,
            }, cast)
        end)

        it("builds a failure without lure or loot", function()
            local cast = ns.Records.Build(char, {
                outcome = "getaway",
                ctx = ctx({ subzone = "Sen'jin Village" }),
                loot = { items = { { id = 1 } } },
            }, 999)
            assert.are.equal("getaway", cast.out)
            assert.is_nil(cast.lure)
            assert.is_nil(cast.loot)
            assert.is_nil(cast.bite)
        end)

        it("uses the fallback time without a context", function()
            local cast = ns.Records.Build(char, { outcome = "unknown" }, 999)
            assert.are.equal(999, cast.t)
            assert.is_nil(cast.sub)
        end)

        it("indexes subzone texts per character and reuses saved ones", function()
            assert.are.equal(1, ns.Records.SubzoneIndex(char, "A"))
            assert.are.equal(2, ns.Records.SubzoneIndex(char, "B"))
            assert.are.equal(1, ns.Records.SubzoneIndex(char, "A"))
            assert.is_nil(ns.Records.SubzoneIndex(char, ""))
            local loaded = { subzones = { "X", "Y" } }
            assert.are.equal(2, ns.Records.SubzoneIndex(loaded, "Y"))
            assert.are.equal(3, ns.Records.SubzoneIndex(loaded, "Z"))
            assert.are.same({ "X", "Y", "Z" }, loaded.subzones)
            -- The lookup lives in memory only; the saved table holds the list and nothing else.
            for key in pairs(loaded) do
                assert.are.equal("subzones", key)
            end
        end)

        it("stops indexing at the subzone cap", function()
            for i = 1, ns.Records.MAX_SUBZONES do
                char.subzones[i] = "S" .. i
            end
            assert.is_nil(ns.Records.SubzoneIndex(char, "new"))
            assert.are.equal(5, ns.Records.SubzoneIndex(char, "S5"))
        end)
    end)
end)
