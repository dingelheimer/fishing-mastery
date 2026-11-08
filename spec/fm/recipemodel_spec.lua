-- Recipe model and Recipes tab builders (RecipeModel.lua, RecipeTable.lua) on the generated
-- data: the bundled list with buff food, a stored runtime recipe merged with a bundled one, a
-- Forever-only recipe, what the store keeps (journal items only, valid IDs, the cap), the
-- per-fish index, and the rows, filters, hover lines, and progress line.
local addon = require("spec.helpers.addon")

local ITEMS = { [6291] = "Raw Brilliant Smallfish", [21071] = "Raw Sagefish", [6290] = "Fish" }
local JOURNAL_ITEMS = { [6291] = true, [6308] = true, [21071] = true }

describe("FishingMastery recipe model", function()
    local ns, RecipeModel, RecipeTable

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
            "RecipeModel.lua",
            "RecipeTable.lua",
        }, nil, "FishingMastery")
        RecipeModel, RecipeTable = ns.RecipeModel, ns.RecipeTable
    end)

    local function isJournal(id)
        return JOURNAL_ITEMS[id] == true
    end

    local function input(known, stock)
        return {
            info = function(id)
                return { name = ITEMS[id] }
            end,
            spellName = function(spell)
                return "Spell " .. spell
            end,
            known = function(spell)
                return (known or {})[spell]
            end,
            stock = function(id)
                return (stock or {})[id]
            end,
        }
    end

    it("lists the 23 bundled recipes by profession and learn skill, with buff food", function()
        local list = RecipeModel.Build(ns.Journal, nil)
        assert.are.equal(23, #list)
        assert.are.same({ 7751, 185, 1, "vendor", 6325 }, {
            list[1].spell,
            list[1].profession,
            list[1].learn,
            list[1].source,
            list[1].item,
        })
        assert.are.equal(171, list[20].profession) -- 19 Cooking, then 4 Alchemy
        assert.are.equal(17551, list[23].spell)
        local catfish = RecipeModel.Find(list, 7755)
        assert.are.same({ bonus = 8, level = 15, source = "guide" }, catfish.food)
        assert.is_nil(RecipeModel.Find(list, 7751).food)
        assert.is_false(catfish.read)
        assert.is_nil(catfish.forever)
        assert.are.same(
            { 7751, 1229745 },
            RecipeModel.ByReagent({
                list[1],
                { spell = 1229745, reagents = { { 6291, 1 }, { 3371, 1 } } },
            })[6291]
        )
    end)

    it("stores learned recipes that use a journal item, once, with valid IDs only", function()
        local store = RecipeModel.Store({ recipes = "broken" })
        assert.are.same({}, store)
        local read = {
            {
                id = 7751,
                profession = 185,
                product = 6290,
                reagents = { { id = 6291, count = 1 } },
            },
            {
                id = 2538,
                profession = 185,
                product = 2679,
                reagents = { { id = 2672, count = 1 } },
            },
            {
                id = 25704,
                product = 21072,
                reagents = { { id = 21071, count = 1 }, { count = 1 } },
            },
            { id = "x", reagents = { { id = 6291, count = 1 } } },
            { id = 1, reagents = { { id = 6291, count = 0 } } },
        }
        assert.are.same({ 2, 0 }, { RecipeModel.Merge(store, read, isJournal) })
        assert.are.same({ s = 185, p = 6290, r = { { 6291, 1 } } }, store[7751])
        assert.are.same({ s = 0, p = 21072, r = { { 21071, 1 } } }, store[25704])
        assert.is_nil(store[2538]) -- no journal item
        assert.are.same({ 0, 0 }, { RecipeModel.Merge(store, read, isJournal) })
        read[1].product = 6291
        assert.are.same({ 0, 1 }, { RecipeModel.Merge(store, read, isJournal) })

        local full, many = {}, {}
        for i = 1, RecipeModel.CAP + 5 do
            many[i] = { id = 100 + i, reagents = { { id = 6291, count = 1 } } }
        end
        assert.are.equal(RecipeModel.CAP, (RecipeModel.Merge(full, many, isJournal)))
    end)

    it("merges a stored bundled recipe and adds a Forever-only one", function()
        local store = {
            [7755] = { s = 185, p = 4593, r = { { 6308, 2 } } },
            [25704] = { s = 185, p = 21072, r = { { 21071, 1 }, { 2678, 1 } } },
            [99] = { s = 185, p = 0, r = {} }, -- no reagents: ignored
        }
        local list = RecipeModel.Build(ns.Journal, store)
        assert.are.equal(24, #list)
        local catfish = RecipeModel.Find(list, 7755)
        assert.are.same({ { 6308, 2 } }, catfish.reagents)
        assert.are.same({ true, 140, "vendor" }, { catfish.read, catfish.low, catfish.source })
        local sage = RecipeModel.Find(list, 25704)
        assert.are.same({ true, true, 185, 21072 }, {
            sage.read,
            sage.forever,
            sage.profession,
            sage.product,
        })
        assert.is_nil(sage.learn)
        assert.are.equal(25704, list[20].spell) -- after the bundled Cooking recipes
        assert.are.same({ 25704 }, RecipeModel.ByReagent(list)[21071])

        -- A recipe stored before the stricter read (meat, Story 5.9) is left out with a test.
        store[2538] = { s = 185, p = 2679, r = { { 2672, 1 } } }
        assert.are.equal(25, #RecipeModel.Build(ns.Journal, store))
        local strict = RecipeModel.Build(ns.Journal, store, isJournal)
        assert.are.equal(24, #strict)
        assert.is_nil(RecipeModel.Find(strict, 2538))
        assert.is_not_nil(RecipeModel.Find(strict, 25704))
        assert.is_not_nil(RecipeModel.Find(strict, 7755)) -- bundled recipes always stay
    end)

    it("builds rows with stock, known, and buff, and filters by fish and known", function()
        local store = { [25704] = { s = 185, p = 21072, r = { { 21071, 1 } } } }
        local list = RecipeModel.Build(ns.Journal, store)
        local inp = input({ [7751] = true, [25704] = true, [7755] = false }, { [6291] = 3 })
        local rows = RecipeTable.Rows(list, inp, { show = "all" })
        assert.are.equal(24, #rows)
        local first = rows[1]
        assert.are.same({
            "Fish",
            "Cooking",
            "Raw Brilliant Smallfish x1 (3)",
            "45 / 85",
            "1, vendor",
            "",
            "yes",
        }, first.cells)
        assert.is_nil(first.grey)
        assert.are.equal(
            "  Raw Brilliant Smallfish x1 - you have 3 (bags and bank)",
            first.tooltip[4]
        )
        local catfish
        for _, row in ipairs(rows) do
            if row.spell == 7755 then
                catfish = row
            end
        end
        assert.are.same({ "+8 (guide)", "no" }, { catfish.cells[6], catfish.cells[7] })
        assert.is_true(catfish.grey[1])
        local tip = table.concat(catfish.tooltip, "\n")
        assert.truthy(
            tip:find("Fishing buff: +8 Fishing, character level 15 (guide value", 1, true)
        )
        assert.truthy(tip:find("Learn at Cooking 100 from a vendor", 1, true))

        local sage = RecipeTable.Rows(list, inp, { show = "all", fish = 21071 })
        assert.are.equal(1, #sage)
        assert.are.same({ "Raw Sagefish x1 (?)", "-", "read in game" }, {
            sage[1].cells[3],
            sage[1].cells[4],
            sage[1].cells[5],
        })
        assert.truthy(table.concat(sage[1].tooltip, "\n"):find("New in Forever", 1, true))
        assert.are.equal(2, #RecipeTable.Rows(list, inp, { show = "known" }))
        assert.are.equal(1, #RecipeTable.Rows(list, inp, { show = "unknown" }))
        assert.are.equal("?", RecipeTable.Rows(list, input(), { show = "all" })[1].cells[7])

        assert.are.equal(
            "23 recipes (19 Cooking, 4 Alchemy) + 1 read in game; this character knows 2.",
            RecipeTable.Progress(list, inp, { show = "all" })
        )
        assert.truthy(
            RecipeTable.Progress(list, inp, { fish = 6291 })
                :find("^Recipes with Raw Brilliant Smallfish: 1%.  23 recipes")
        )
    end)
end)
