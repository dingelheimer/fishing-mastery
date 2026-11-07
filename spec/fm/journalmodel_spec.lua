-- Journal model (JournalModel.lua) on the generated journal and zone data: the static index
-- (places, base skills, recipes per reagent), two characters merged account-wide and the
-- character scope, the first catch place through StatsView, a not-caught entry with full
-- information, new-in-Forever items by Forever item class, excluded potions, pending classes,
-- quest-only fish, progress counts, and the gear that closes a skill gap.
local addon = require("spec.helpers.addon")

local DAY = 20763 * 86400
local NAMES = { [367] = "Sen'jin Village" }

describe("FishingMastery journal model", function()
    local ns, JournalModel, index

    before_each(function()
        ns = addon.load({
            "Data\\Zones.lua",
            "Data\\Journal.lua",
            "Codec.lua",
            "History.lua",
            "Options.lua",
            "Totals.lua",
            "Stats.lua",
            "StatsView.lua",
            "Area.lua",
            "JournalModel.lua",
        }, nil, "FishingMastery")
        JournalModel = ns.JournalModel
        local areas = ns.Area.New(ns.Zones, function(id)
            return NAMES[id]
        end)
        index = JournalModel.Index(ns.Journal, ns.Zones, areas)
    end)

    local function char(name, subzones, casts)
        local totals = ns.Totals.New()
        for _, cast in ipairs(casts) do
            cast.out = cast.out or "catch"
            ns.Totals.Add(totals, cast)
        end
        return { name = name, subzones = subzones, totals = totals }
    end

    local function catch(t, map, sub, id)
        return { t = DAY + t, map = map, sub = sub, rank = 50, loot = { { id = id } } }
    end

    -- A: two Smallfish in Sen'jin Village (Durotar 1411, subzone 1) on day 2.
    -- B: a Smallfish on day 1 in Mulgore (1412, no subzone), Raw Sagefish (new in Forever), a
    -- potion, an item whose class is not loaded yet, and an item of an unknown Forever class.
    local function chars()
        return {
            a = char("A", { "Sen'jin Village" }, {
                catch(86400, 1411, 1, 6291),
                catch(86460, 1411, 1, 6291),
            }),
            b = char("B", {}, {
                catch(100, 1412, 0, 6291),
                catch(200, 1412, 0, 21071),
                catch(300, 1412, 0, 118),
                catch(400, 1412, 0, 99001),
                catch(500, 1412, 0, 99002),
            }),
        }
    end

    local CLASSES = { [21071] = { 7, 8 }, [99002] = { 15, 0 } }
    local function classOf(id)
        local c = CLASSES[id]
        if c then
            return c[1], c[2]
        end
    end

    local function build(scope, current)
        local list = JournalModel.Chars(chars(), scope, current or "a")
        local view = ns.StatsView.Build(list)
        return JournalModel.Build({ index = index, view = view, classOf = classOf })
    end

    local function find(model, id)
        for _, entry in ipairs(model.entries) do
            if entry.id == id then
                return entry
            end
        end
    end

    it("indexes places, base skills, and recipes per reagent", function()
        local places = index.places[6291] -- Raw Brilliant Smallfish
        assert.is_true(#places > 5)
        for i = 2, #places do
            assert.is_true(places[i - 1].chance >= places[i].chance)
        end
        assert.are.same({ 7751 }, index.recipes[6291])
        assert.are.same({ 8238, 8240 }, index.recipes[6522]) -- Deviate Fish: Cooking and Alchemy
        assert.are.equal("trophy", index.groupOf[6292])
    end)

    it("merges every character by default with the earliest first catch place", function()
        local model = build()
        local fish = find(model, 6291)
        assert.is_true(fish.caught)
        assert.are.equal(3, fish.n)
        assert.are.equal(DAY + 100, fish.first)
        assert.are.equal(1412, fish.firstMap)
        assert.are.equal("", fish.firstSub)
        assert.are.equal(-70, fish.base)
        assert.are.equal(25, fish.safe)
        assert.are.equal(JournalModel.PLACES, #fish.places)
        assert.is_true(fish.placeCount > JournalModel.PLACES)
        assert.are.same({ 7751 }, fish.recipes)
    end)

    it("limits the character scope to the current character", function()
        local model = build("character", "a")
        local fish = find(model, 6291)
        assert.are.equal(2, fish.n)
        assert.are.equal(DAY + 86400, fish.first)
        assert.are.equal(1411, fish.firstMap)
        assert.are.equal("Sen'jin Village", fish.firstSub)
        assert.is_nil(find(model, 21071))
        assert.are.equal(1, model.progress.fish.caught)
        assert.are.equal(0, model.progress.fish.new)
    end)

    it("gives a not-caught fish all its information", function()
        local squid = find(build(), 13755) -- Winter Squid
        assert.is_false(squid.caught)
        assert.is_nil(squid.n)
        assert.is_true(#squid.places > 0)
        assert.are.equal(205, squid.base)
        assert.are.equal(300, squid.safe)
        assert.are.same({ 18240 }, squid.recipes)
        assert.are.equal("winter", squid.season.season)
        assert.is_nil(squid.questOnly)
    end)

    it("adds new-in-Forever items by class and leaves out potions and unknown classes", function()
        local model = build()
        local sagefish = find(model, 21071)
        assert.are.same({ "fish", true, true, 1 }, {
            sagefish.group,
            sagefish.new,
            sagefish.caught,
            sagefish.n,
        })
        assert.are.same({}, sagefish.places)
        assert.is_nil(sagefish.base)
        assert.is_nil(find(model, 118)) -- potion: not a journal group
        assert.is_nil(find(model, 99002)) -- 15/0 cannot be told apart
        assert.is_nil(find(model, 99001))
        assert.are.equal(1, model.pending) -- 99001: class not loaded yet
        assert.are.same({ caught = 1, total = 28, new = 1 }, model.progress.fish)
        assert.are.same({ caught = 0, total = 35, new = 0 }, model.progress.trophy)
        assert.are.equal(18, model.progress.container.total)
        assert.are.equal(7, model.progress.quest.total)
        assert.are.equal(28 + 35 + 18 + 7 + 1, #model.entries)
    end)

    it("marks quest fish and orders entries by group, caught, and ID", function()
        local model = build()
        assert.is_true(find(model, 16967).questOnly) -- Feralas Ahi
        assert.are.same({ 6291, "fish" }, { model.entries[1].id, model.entries[1].group })
        assert.are.equal(21071, model.entries[2].id) -- caught entries first
        local last = model.entries[#model.entries]
        assert.are.equal("quest", last.group)
        local without = JournalModel.Build({ index = index, view = { items = {} } })
        assert.are.equal(0, without.pending)
        assert.are.equal(88, #without.entries)
    end)

    it("finds the gear that closes a skill gap", function()
        local J = ns.Journal
        -- Skill 100, gap 20: Big Iron (+20), FC-5000 (+25, Horde only); usable at 100 and below.
        assert.are.same({ 6367, 19022 }, JournalModel.GearFor(J, 20, 100, nil))
        assert.are.same({ 6367 }, JournalModel.GearFor(J, 20, 100, 1)) -- race bit 1: Human
        assert.are.same({ 6367, 19022 }, JournalModel.GearFor(J, 20, 100, 2)) -- 2: Orc
        -- Skill 10: nothing reaches +20, so every usable +5 item (pole, boots, hat).
        assert.are.same({ 6365, 19969, 19972 }, JournalModel.GearFor(J, 20, 10, 2))
        assert.are.same({}, JournalModel.GearFor({ gear = {} }, 5, 300))
    end)
end)
