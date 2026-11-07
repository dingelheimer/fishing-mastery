"""Tests for the journal data tools (standard library unittest).

Usage (repository root): python -m unittest discover -s tools -p "test_*.py"
"""

import unittest

import build_journal_data as build
import journal_sources as js
import zone_sources as zs


def item(entry, cls, sub=0, food=0, openable=False, spell=0, skill=0, level=0, races=-1, name="x",
         slot=17):
    row = {c: "0" for c in js.ITEM_COLUMNS}
    row.update({
        "entry": str(entry), "class": str(cls), "subclass": str(sub), "FoodType": str(food),
        "openable": "1" if openable else "0", "spellid_1": str(spell),
        "RequiredSkillRank": str(skill), "RequiredLevel": str(level), "AllowableRace": str(races),
        "name": name, "InventoryType": str(slot),
    })
    return row


def spell(sid, name="s", reagents=(), create=0, aura=None, learn=0, lure=0):
    row = {c: "0" for c in js.SPELL_COLUMNS}
    row.update({"Id": str(sid), "SpellName": name})
    for i, (reagent, count) in enumerate(reagents, 1):
        row["Reagent%d" % i], row["ReagentCount%d" % i] = str(reagent), str(count)
    if create:
        row["Effect1"], row["EffectItemType1"] = str(js.EFFECT_CREATE_ITEM), str(create)
    if aura is not None:
        row["EffectApplyAuraName1"], row["EffectMiscValue1"] = "30", str(js.FISHING_SKILL)
        row["EffectBasePoints1"] = str(aura - 1)
    if learn:
        row["Effect1"], row["EffectTriggerSpell1"] = str(js.EFFECT_LEARN_SPELL), str(learn)
    if lure:
        row["Effect1"], row["EffectMiscValue1"] = str(js.EFFECT_ENCHANT_TEMPORARY), str(lure)
    return row


def sources(items=(), spells=(), vendors=(), trainers=(), quests=(), drops=(), abilities=()):
    return {
        "items": list(items),
        "spells": list(spells),
        "vendors": [{"entry": "1", "item": str(i)} for i in vendors],
        "trainers": [{"spell": str(s), "reqskillvalue": str(v)} for s, v in trainers],
        "quests": [{"quest": str(q), "item": str(i), "races": str(r)} for q, i, r in quests],
        "drops": [{"source": s, "item": str(i)} for s, i in drops],
        "events": [],
        "abilities": [
            {"SkillLine": str(line), "Spell": str(s), "MinSkillLineRank": "1",
             "TrivialSkillLineRankLow": str(low), "TrivialSkillLineRankHigh": str(high)}
            for line, s, low, high in abilities
        ],
    }


class Groups(unittest.TestCase):
    def test_rules(self):
        cases = [
            (item(6643, 0, food=0, openable=True), "container"),
            (item(6292, 15), "trophy"),
            (item(16967, 12), "quest"),
            (item(6651, 2, 4), "junk"),
            (item(6291, 0, food=js.FOOD_FISH), "fish"),
            (item(6358, 5), "fish"),
            (item(6522, 7), "fish"),
            (item(118, 0, 3), "potion"),
            (item(6297, 15), "junk"),
            (item(3857, 7), "other"),
        ]
        for row, group in cases:
            self.assertEqual(js.group_of(row), group, row["entry"])

    def test_unknown_class_fails(self):
        with self.assertRaises(zs.DataError):
            js.group_of(item(9999, 9))

    def test_missing_item_fails(self):
        with self.assertRaises(zs.DataError):
            js.groups(sources(items=[item(6291, 0, food=2)]), {6291, 6292})


class Recipes(unittest.TestCase):
    def test_sources_learn_skill_and_dropped_copy(self):
        data = sources(
            items=[item(6325, 9, spell=483), item(6661, 9, spell=8238, skill=85)],
            spells=[
                spell(7751, "Brilliant Smallfish", [(6291, 1)], create=6290),
                spell(483, learn=7751),
                spell(8238, "Savory Deviate Delight", [(6522, 1), (2678, 1)], create=6657),
                spell(7836, "Blackmouth Oil", [(6358, 2), (3371, 1)], create=6370),
                spell(7838, learn=7836),
                spell(25662, "Copy of Nightfin Soup", [(13759, 1)], create=13931),
                spell(9999, "Not fish", [(2678, 1)], create=1),
            ],
            vendors=[6325],
            trainers=[(7838, 80)],
            drops=[("creature", 6661)],
            abilities=[(185, 7751, 45, 85), (185, 8238, 125, 165), (171, 7836, 80, 100),
                       (185, 9999, 1, 2)],
        )
        data["items"][0]["RequiredSkillRank"] = "1"
        recipes, dropped = js.recipes(data, {6291, 6522, 6358, 13759})
        self.assertEqual(sorted(recipes), [7751, 7836, 8238])
        self.assertEqual(dropped, [25662])
        self.assertEqual(recipes[7751]["source"], "vendor")
        self.assertEqual((recipes[7751]["item"], recipes[7751]["learn"]), (6325, 1))
        self.assertEqual((recipes[8238]["source"], recipes[8238]["learn"]), ("drop", 85))
        self.assertEqual((recipes[7836]["source"], recipes[7836]["learn"]), ("trainer", 80))
        self.assertEqual(recipes[7836]["reagents"], [(6358, 2), (3371, 1)])
        self.assertEqual((recipes[7836]["skill"], recipes[7836]["low"]), (171, 80))

    def test_recipe_without_source_fails(self):
        data = sources(
            items=[item(6325, 9, spell=7751)],
            spells=[spell(7751, reagents=[(6291, 1)], create=6290)],
            abilities=[(185, 7751, 45, 85)],
        )
        with self.assertRaises(zs.DataError):
            js.recipes(data, {6291})


class Gear(unittest.TestCase):
    def test_sources_races_and_unused(self):
        data = sources(
            items=[
                item(6365, 2, 20, spell=1, skill=10, level=5),
                item(6366, 2, 20, spell=2, skill=50),
                item(6367, 2, 20, spell=3),
                item(19022, 2, 20, spell=4, skill=100),
                item(7996, 4, 1, spell=1, races=511),
            ],
            spells=[spell(1, aura=5), spell(2, aura=15), spell(3, aura=20), spell(4, aura=25)],
            vendors=[6365],
            quests=[(7815, 19022, 178)],
            drops=[("reference", 6366), ("gameobject", 6367)],
        )
        gear, unused = js.gear(data, {6366})
        self.assertEqual(unused, [7996])
        self.assertEqual((gear[6365]["source"], gear[6365]["bonus"], gear[6365]["level"]),
                         ("vendor", 5, 5))
        self.assertEqual(gear[6366]["source"], "fishing")
        self.assertEqual(gear[6367]["source"], "drop")
        self.assertEqual((gear[19022]["quest"], gear[19022]["races"]), (7815, 178))
        self.assertEqual(gear[6365]["slot"], "pole")

    def test_unknown_slot_fails(self):
        data = sources(items=[item(19969, 4, 1, spell=1, slot=5)], spells=[spell(1, aura=5)],
                       vendors=[19969])
        with self.assertRaises(zs.DataError):
            js.gear(data, set())

    def test_lures_ranks_and_enchants(self):
        data = sources(
            items=[
                item(6529, 0, spell=8087),
                item(6811, 0, spell=8532, races=255),
                item(7307, 0, spell=9092, skill=100),
                item(16083, 9, 9, skill=125, level=20),
                item(16082, 9, 9, skill=200, level=35),
                item(11152, 9, 8, skill=145),
            ],
            spells=[spell(8087, lure=263), spell(8532, lure=264), spell(9092, lure=265)],
            vendors=[6529, 16083],
            trainers=[(7733, 0), (7734, 50), (7734, 75)],
            quests=[(1580, 6811, 77)],
            drops=[("creature", 7307), ("creature", 11152)],
        )
        lures = js.lures(data)
        self.assertEqual((lures[6529]["bonus"], lures[6529]["skill"], lures[6529]["source"]),
                         (25, 1, "vendor"))
        self.assertEqual((lures[6811]["races"], lures[6811]["quest"]), (77, 1580))
        self.assertEqual((lures[7307]["bonus"], lures[7307]["source"]), (75, "drop"))
        ranks = js.ranks(data)
        self.assertEqual([(r["key"], r["skill"], r["source"]) for r in ranks],
                         [("apprentice", 1, "trainer"), ("journeyman", 50, "trainer"),
                          ("expert", 125, "vendor"), ("artisan", 200, "quest")])
        self.assertEqual(ranks[3]["level"], 35)
        self.assertEqual(js.enchants(data)[13620],
                         {"bonus": 2, "formula": 11152, "name": "Enchant Gloves - Fishing",
                          "skill": 145, "source": "drop"})
        data["vendors"] = []
        with self.assertRaises(zs.DataError):
            js.lures(data)


class Seasons(unittest.TestCase):
    def test_rule_from_condition(self):
        data = sources()
        data["events"] = [{"entry": "35", "start_time": "2010-09-23 01:00:00",
                           "occurence": "525600", "length": "256320"}]
        rules = js.seasons(data, {16: ((13755, 10.0, 0, 322, False), (6291, 50.0, 1, 0, False))})
        self.assertEqual(rules, {13755: {"month": 9, "day": 23, "hour": 1, "every": 525600,
                                         "length": 256320, "event": 35, "season": "winter"}})

    def test_bad_start_fails(self):
        data = sources()
        data["events"] = [{"entry": "35", "start_time": "soon", "occurence": "1", "length": "1"}]
        with self.assertRaises(zs.DataError):
            js.seasons(data, {})


class Output(unittest.TestCase):
    def test_words_from_fixed_sets_only(self):
        self.assertEqual(build.word("vendor", build.SOURCES), '"vendor"')
        with self.assertRaises(zs.DataError):
            build.word('x" } os.exit() --', build.SOURCES)

    def test_long_rows_are_expanded(self):
        short = build.entry(7751, ["185", "6290"], "Brilliant Smallfish")
        self.assertEqual(short, ["        -- Brilliant Smallfish", "        [7751] = { 185, 6290 },"])
        long = build.entry(8240, ["1234567890"] * 9, "Elixir of Giant Growth\n--]] x")
        self.assertEqual(long[0], "        -- Elixir of Giant Growth?--?? x")
        self.assertEqual(long[1], "        [8240] = {")
        self.assertEqual(long[-1], "        },")
        self.assertTrue(all(len(line) <= build.MAX_COLUMNS for line in long))


class Pinned(unittest.TestCase):
    def test_build_matches_the_research_numbers(self):
        text, summary = build.build(zs.read_sources(), js.read_sources())
        self.assertEqual(summary["items"], 108)
        self.assertEqual(summary["groups"], {"fish": 28, "trophy": 35, "container": 18, "quest": 7,
                                             "potion": 11, "junk": 6, "other": 3})
        self.assertEqual((summary["recipes"], summary["bySkill"]), (23, {185: 19, 171: 4}))
        self.assertEqual(summary["dropped"], [25662])
        self.assertEqual((summary["gear"], sorted(summary["unused"])), (9, [7996, 12221, 12222]))
        self.assertEqual(summary["seasons"], 2)
        self.assertEqual(summary["times"], 2)
        self.assertIn('    times = { [13759] = "night", [13760] = "day" },', text.splitlines())
        self.assertEqual(summary["food"], 4)
        self.assertEqual((summary["lures"], summary["ranks"], summary["enchants"]), (6, 4, 1))
        self.assertIn("        [4593] = { 8, 15, \"guide\" },", text.splitlines())
        self.assertLess(len(text.encode("utf-8")), build.MAX_BYTES)
        self.assertTrue(all(len(line) <= build.MAX_COLUMNS for line in text.splitlines()))


if __name__ == "__main__":
    unittest.main()
