-- Gear model, Gear tab builders, and the game reads (GearModel.lua, GearTable.lua,
-- GearInputs.lua) on the generated data: the sections, owned and not owned, a tooltip bonus that
-- differs from the bundled value, no tooltip line, a Horde-only item for an Alliance character,
-- the equipped bonus against the skill modifier, the best setup, and the reads from a fake client
-- (counts without the equipped item, tooltip lines, race bit, missing APIs).
local addon = require("spec.helpers.addon")

local HUMAN, ORC = 1, 2 -- race bits

describe("FishingMastery gear model", function()
    local ns, GearModel, GearTable

    before_each(function()
        ns = addon.load({
            "Locale.lua",
            "LocaleStats.lua",
            "LocaleJournal.lua",
            "Data\\Journal.lua",
            "Codec.lua",
            "CodecDecode.lua",
            "History.lua",
            "Options.lua",
            "Totals.lua",
            "Stats.lua",
            "HudModel.lua",
            "StatsTables.lua",
            "Context.lua",
            "GearModel.lua",
            "GearTable.lua",
            "GearInputs.lua",
        }, nil, "FishingMastery")
        GearModel, GearTable = ns.GearModel, ns.GearTable
    end)

    -- own: id -> { bags, bank, equipped }; tips: id -> number or false.
    local function input(o)
        o = o or {}
        return {
            own = function(id)
                if o.noApi then
                    return nil
                end
                return (o.own or {})[id] or { bags = 0, bank = 0, equipped = false }
            end,
            tip = function(id)
                return (o.tips or {})[id]
            end,
            raceBit = o.raceBit,
            level = o.level,
            rank = o.rank,
            cap = o.cap,
            modifier = o.modifier,
            lure = o.lure,
            gloves = o.gloves,
        }
    end

    local function find(list, id)
        for _, e in ipairs(list) do
            if e.id == id then
                return e
            end
        end
    end

    local tableInput = {
        info = function(id)
            return { name = "Item " .. id }
        end,
        spellName = function()
            return nil
        end,
        questName = function(quest)
            return quest == 8193 and "Master Angler" or nil
        end,
    }

    it("reads the fishing bonus from tooltip lines as data", function()
        local lines = {
            "Big Iron Fishing Pole",
            "Requires Fishing (100)",
            "Equip: Increased Fishing +20.",
        }
        assert.are.equal(20, GearModel.TipBonus(lines, "Fishing", "Equip:"))
        assert.are.equal(20, GearModel.TipBonus(lines, "Fishing", nil))
        assert.is_false(GearModel.TipBonus({ "Requires Fishing (150)" }, "Fishing", "Equip:"))
        assert.is_false(GearModel.TipBonus({ "Use: +25 Fishing" }, "Fishing", "Equip:"))
        assert.is_nil(GearModel.TipBonus(nil, "Fishing"))
        assert.is_nil(GearModel.TipBonus(lines, nil))
        assert.are.equal(42, GearModel.TipBonus({ "Equip: Increased %a+ +42." }, "%a+", "Equip:"))
    end)

    it("builds every section with owned and not owned items", function()
        local model = GearModel.Build(
            ns.Journal,
            input({
                own = {
                    [6365] = { bags = 1, bank = 0, equipped = false },
                    [6367] = { bags = 0, bank = 0, equipped = true },
                    [6530] = { bags = 5, bank = 2, equipped = false },
                },
                raceBit = HUMAN,
                rank = 150,
                cap = 225,
                modifier = 20,
                gloves = false,
            })
        )
        assert.are.same({ 7, 3, 7, 4, 4, 1 }, {
            #model.pole,
            #model.gear,
            #model.lure,
            #model.food,
            #model.rank,
            #model.enchant,
        })
        assert.are.same({ 6256, 12225, 6365, 6366, 6367, 19022, 19970 }, {
            model.pole[1].id,
            model.pole[2].id,
            model.pole[3].id,
            model.pole[4].id,
            model.pole[5].id,
            model.pole[6].id,
            model.pole[7].id,
        })
        assert.is_true(find(model.pole, 6367).has)
        assert.is_false(find(model.pole, 19970).has)
        assert.are.same({ true, true, true, false }, {
            model.rank[1].reached,
            model.rank[2].reached,
            model.rank[3].reached,
            model.rank[4].reached,
        })
        assert.are.same({ items = 20, count = 1, game = 20 }, model.measure)

        local rows = GearTable.Rows(model, tableInput)
        assert.are.equal(6 + 26, #rows)
        assert.are.same({ "pole", { "Fishing poles" } }, { rows[1].heading, rows[1].cells })
        local big
        for _, row in ipairs(rows) do
            if row.id == 6367 then
                big = row
            end
        end
        assert.are.same({ "+20", "Fishing 100, level 25", "drop", "equipped" }, {
            big.cells[2],
            big.cells[3],
            big.cells[4],
            big.cells[5],
        })
        assert.is_nil(big.grey)
        local function rowOf(id)
            for _, row in ipairs(rows) do
                if row.id == id then
                    return row
                end
            end
        end
        assert.are.equal("bags 5, bank 2", rowOf(6530).cells[5])
        assert.are.equal("+50 (guide)", rowOf(6530).cells[2])
        assert.are.equal("derby: Master Angler", rowOf(19970).cells[4])
        assert.are.equal("no", rowOf(19970).cells[5])
        assert.is_true(rowOf(19970).grey[1])
        assert.are.equal("Item 16083 (vendor)", rowOf(16083).cells[4])
        assert.are.equal("+8 (guide)", rowOf(4593).cells[2])
        assert.are.equal("Cooking (Recipes tab)", rowOf(4593).cells[4])
        local enchant = rows[#rows]
        assert.are.same(
            { "Spell 13620", "+2 (guide)", "Enchanting 145", "formula (drop)", "no" },
            enchant.cells
        )
    end)

    it("shows a tooltip bonus that differs, no tooltip line, and the game's bonus", function()
        local model = GearModel.Build(
            ns.Journal,
            input({
                own = { [6367] = { bags = 0, bank = 0, equipped = true } },
                tips = { [6367] = 42, [19971] = false, [6365] = 5 },
                rank = 150,
                modifier = 45, -- 20 pole + 25 lure
                lure = 263,
            })
        )
        local big = find(model.pole, 6367)
        assert.are.same({ 42, 42, 20 }, { big.tip, big.value, big.game })
        assert.are.same({ items = 42, count = 1, game = 20 }, model.measure)
        local rows = GearTable.Rows(model, tableInput)
        local cells = {}
        for _, row in ipairs(rows) do
            if row.id then
                cells[row.id] = row.cells
            end
        end
        assert.are.equal("+42 tooltip, data +20, game +20", cells[6367][2])
        assert.are.equal("+5 (tooltip)", cells[6365][2])
        assert.are.equal("+5 (no tooltip number)", cells[19971][2])
        local tip = table.concat(GearTable.Tooltip(big, tableInput), "\n")
        assert.truthy(tip:find("Tooltip: +42 Fishing", 1, true))
        assert.truthy(tip:find("The game applies +20", 1, true))
        assert.are.equal(
            "Equipped items +42, but the game applies +20 (skill modifier without the lure; a buff "
                .. "food also counts).",
            GearTable.Measure(model)
        )
        -- An unknown lure enchant: the game's bonus is not known.
        model = GearModel.Build(ns.Journal, input({ rank = 150, modifier = 45, lure = 999 }))
        assert.is_nil(model.measure.game)
        assert.truthy(GearTable.Measure(model):find("not known", 1, true))
    end)

    it("lists the plain Fishing Pole at +0 and keeps it out of the best setup", function()
        local model = GearModel.Build(
            ns.Journal,
            input({
                own = {
                    [6256] = { bags = 0, bank = 0, equipped = true },
                    [6529] = { bags = 2, bank = 0, equipped = false },
                },
                tips = { [6256] = false },
                raceBit = 128, -- Troll
                rank = 150,
                level = 20,
                modifier = 0,
            })
        )
        local rows = GearTable.Rows(model, tableInput)
        assert.are.same({ "Item 6256", "+0", "-", "vendor", "equipped" }, rows[2].cells)
        assert.is_nil(rows[2].grey)
        assert.are.same({ items = 0, count = 1, game = 0 }, model.measure)
        assert.are.equal(
            "Best setup: Fishing 150 + lure 25 = 175 (now 150).",
            GearTable.Best(model, 150)
        )
    end)

    it(
        "marks a Horde-only item for an Alliance character and leaves it out of the best setup",
        function()
            local own = {
                [19022] = { bags = 1, bank = 0, equipped = false }, -- FC-5000, Horde, +25
                [6367] = { bags = 0, bank = 1, equipped = false }, -- Big Iron, +20
                [19972] = { bags = 0, bank = 0, equipped = true }, -- Lucky Fishing Hat, +5
                [6532] = { bags = 2, bank = 0, equipped = false }, -- Bright Baubles, +75, skill 100
                [6533] = { bags = 0, bank = 3, equipped = false }, -- Attractor in the bank only
            }
            local human = GearModel.Build(
                ns.Journal,
                input({
                    own = own,
                    raceBit = HUMAN,
                    rank = 150,
                    level = 30,
                    gloves = 2,
                })
            )
            local fc = find(human.pole, 19022)
            assert.is_false(fc.usable)
            local rows = GearTable.Rows(human, tableInput)
            for _, row in ipairs(rows) do
                if row.id == 19022 then
                    assert.are.same({ "Fishing 100, Horde only", "Horde only" }, {
                        row.cells[3],
                        row.cells[5],
                    })
                    assert.is_true(row.grey[1])
                end
            end
            local best = human.best
            assert.are.equal(150 + 20 + 5 + 2 + 75, best.total)
            assert.are.equal(6367, best.parts[1].entry.id)
            assert.are.equal(6532, best.lure.id)
            assert.are.equal(
                "Best setup: Fishing 150 + pole 20 + head 5 + enchant 2 + lure 75 = 252 (now 155).",
                GearTable.Best(human, 155)
            )
            assert.are.equal("Spell 13620", GearTable.Rows(human, tableInput)[#rows].cells[1])
            assert.are.equal("on your gloves", rows[#rows].cells[5])

            local orc = GearModel.Build(ns.Journal, input({ own = own, raceBit = ORC, rank = 150 }))
            assert.are.equal(19022, orc.best.parts[1].entry.id)
            -- Skill too low for the pole and the lure.
            local low = GearModel.Build(ns.Journal, input({ own = own, raceBit = ORC, rank = 60 }))
            assert.are.same({ 60 + 5, nil }, { low.best.total, low.best.lure })
            assert.is_nil(GearModel.Build(ns.Journal, input({})).best)
            assert.are.equal(
                ns.L.GEAR_BEST_UNKNOWN,
                GearTable.Best(GearModel.Build(ns.Journal, input({})))
            )
        end
    )

    it(
        "reads counts, tooltips, race, and the gloves from the client, and degrades without APIs",
        function()
            local equipped = { [16] = 6367, [10] = 1234 }
            local env = {
                ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:",
                GetProfessions = function()
                    return nil, nil, nil, 7
                end,
                GetProfessionInfo = function()
                    return "Fishing", 1, 150, 225, 0, 0, 356, 45
                end,
                GetWeaponEnchantInfo = function()
                    return true, 600000, 1, 263
                end,
                GetInventoryItemID = function(_, slot)
                    return equipped[slot]
                end,
                UnitRace = function()
                    return "Orc", "Orc", 2
                end,
                UnitLevel = function()
                    return 30
                end,
                C_Item = {
                    GetItemCount = function(id, bank)
                        local bags = id == 6367 and 1 or id == 6530 and 4 or 0
                        return bags + ((bank and id == 6530) and 3 or 0)
                    end,
                },
                C_TooltipInfo = {
                    GetItemByID = function(id)
                        return {
                            lines = {
                                { leftText = "Item " .. id },
                                { leftText = "Equip: Increased Fishing +20." },
                            },
                        }
                    end,
                    GetInventoryItem = function()
                        return { lines = { { leftText = "Gloves" }, { leftText = "Fishing +2" } } }
                    end,
                },
                C_QuestLog = {
                    GetTitleForQuestID = function(quest)
                        return quest == 8193 and "Master Angler" or nil
                    end,
                },
            }
            local cache, loaded = { tips = {} }, { [6367] = true }
            local read = ns.GearInputs.Read(env, cache, function(id)
                return loaded[id] == true
            end)
            assert.are.same({ equipped = true, bags = 0, bank = 0 }, read.own(6367))
            assert.are.same({ equipped = false, bags = 4, bank = 3 }, read.own(6530))
            assert.are.equal(20, read.tip(6367))
            assert.is_nil(read.tip(6365)) -- not loaded yet: asked again on the next draw
            assert.are.same({ 2, 30, 150, 225, 45, 263, 2 }, {
                read.raceBit,
                read.level,
                read.rank,
                read.cap,
                read.modifier,
                read.lure,
                read.gloves,
            })
            assert.are.equal("Master Angler", ns.GearInputs.QuestName(env, 8193))
            local model = GearModel.Build(ns.Journal, read)
            assert.are.same({ items = 22, count = 2, game = 20 }, model.measure)

            local bare = ns.GearInputs.Read({}, { tips = {} }, function()
                return true
            end)
            assert.are.same(
                { nil, nil, nil, nil },
                { bare.own(6367), bare.tip(6367), bare.raceBit, bare.gloves }
            )
            assert.is_nil(ns.GearInputs.QuestName({}, 8193))
            local rows = GearTable.Rows(GearModel.Build(ns.Journal, bare), tableInput)
            assert.are.equal("?", rows[2].cells[5])
        end
    )
end)
