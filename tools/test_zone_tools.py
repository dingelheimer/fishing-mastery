"""Tests for the zone data tools (standard library unittest).

Usage (repository root): python -m unittest discover -s tools -p "test_*.py"
"""

import unittest

import build_zone_data as build
import fetch_zone_sources as fetch
import zone_sources as zs


def loot(entry, item, chance, group=1, ref=0, maxcount=1, condition=0):
    return {
        "entry": str(entry),
        "item": str(item),
        "chance": str(chance),
        "group": str(group),
        "mincountOrRef": str(-ref if ref else 1),
        "maxcount": str(maxcount),
        "condition": str(condition),
    }


def sources(fishing, reference=(), conditions=()):
    return {"fishing": list(fishing), "reference": list(reference), "conditions": list(conditions)}


class SqlRows(unittest.TestCase):
    def test_quotes_escapes_and_statements(self):
        text = (
            "INSERT INTO `t` VALUES (1,2.5,'It\\'s, (fine)'),(3,-4,'');\n"
            "INSERT INTO `other` VALUES (9);\n"
            "INSERT INTO `t` VALUES (5,6,'x');\n"
        )
        self.assertEqual(
            list(fetch.sql_rows(text, "t")),
            [["1", "2.5", "It's, (fine)"], ["3", "-4", ""], ["5", "6", "x"]],
        )

    def test_missing_table_fails(self):
        with self.assertRaises(SystemExit):
            list(fetch.sql_rows("", "t"))

    def test_only_https(self):
        with self.assertRaises(SystemExit):
            fetch.download("http://example.com/data")


class Resolve(unittest.TestCase):
    def test_zero_chance_share_and_reference_scale(self):
        lists = zs.resolve_lists(
            sources(
                [loot(14, 11000, 100, ref=11000), loot(16, 13755, 10, group=0, ref=13755)],
                [
                    loot(11000, 6289, 40),
                    loot(11000, 6291, 0),
                    loot(11000, 6292, 0),
                    loot(13755, 13755, 100, group=0, condition=322),
                ],
                [{"condition": "322", "type": "12", "value1": "35"}],
            )
        )
        self.assertEqual(lists[14], ((6289, 40.0, 1, 0, False), (6291, 30.0, 1, 0, False), (6292, 30.0, 1, 0, False)))
        self.assertEqual(lists[16], ((13755, 10.0, 0, 322, False),))

    def test_quest_rows(self):
        lists = zs.resolve_lists(sources([loot(44, 1467, -100, group=0)]))
        self.assertEqual(lists[44], ((1467, 100.0, 0, 0, True),))

    def test_unknown_condition_fails(self):
        with self.assertRaises(zs.DataError):
            zs.resolve_lists(sources([loot(1, 2, 5, group=0, condition=7)]))

    def test_missing_reference_fails(self):
        with self.assertRaises(zs.DataError):
            zs.resolve_lists(sources([loot(1, 9, 100, ref=9)]))


class Place(unittest.TestCase):
    def data(self, areas):
        return {
            "areas": [
                {"ID": str(a), "AreaName_lang": n, "ParentAreaID": str(p), "ContinentID": str(c)}
                for a, n, p, c in areas
            ],
            "uimaps": [{"ID": "1411", "Type": "3"}],
            "assignments": [{"UiMapID": "1411", "AreaID": "14"}],
        }

    def test_zone_subzone_dungeon(self):
        placed = zs.place_areas(
            self.data([(14, "Durotar", 0, 1), (367, "Sen'jin", 14, 1), (1581, "Deadmines", 0, 36)]),
            {14, 367, 1581},
        )
        self.assertEqual(placed[14]["map"], 1411)
        self.assertEqual(placed[367]["zone"], 14)
        self.assertEqual(placed[1581]["instance"], 36)

    def test_unplaceable_area_fails(self):
        with self.assertRaises(zs.DataError):
            zs.place_areas(self.data([(14, "Durotar", 0, 1), (99, "Nowhere", 0, 1)]), {14, 99})

    def test_parent_outside_data_fails(self):
        with self.assertRaises(zs.DataError):
            zs.place_areas(self.data([(14, "Durotar", 0, 1), (5, "Lost", 77, 1)]), {14, 5})


class Complete(unittest.TestCase):
    placed = {
        33: {"kind": "zone"},
        297: {"kind": "subzone", "zone": 33},
        130: {"kind": "zone"},
        5: {"kind": "subzone", "zone": 99},
    }

    def test_merge_and_partial(self):
        lists, flags = zs.complete_lists(
            {
                33: ((1, 60.0, 1, 0, False), (2, 40.0, 1, 0, False)),
                297: ((13755, 10.0, 0, 322, False),),
                130: ((3, 54.6, 1, 0, False),),
                5: ((4, 20.0, 0, 0, True),),
            },
            self.placed,
        )
        self.assertEqual(
            lists[297], ((1, 60.0, 1, 0, False), (2, 40.0, 1, 0, False), (13755, 10.0, 0, 322, False))
        )
        self.assertEqual(flags[297], {"merged": True, "partial": None})
        self.assertEqual(flags[33], {"merged": False, "partial": None})
        self.assertEqual(flags[130], {"merged": False, "partial": 45.4})
        # A subzone whose zone has no list cannot be merged: all of the roll is missing.
        self.assertEqual(flags[5], {"merged": False, "partial": 100.0})

    def test_unknown_group_fails(self):
        with self.assertRaises(zs.DataError):
            zs.complete_lists({33: ((1, 50.0, 2, 0, False),)}, self.placed)

    def test_item_in_both_lists_fails(self):
        with self.assertRaises(zs.DataError):
            zs.complete_lists(
                {33: ((7, 100.0, 1, 0, False), (8, 5.0, 0, 0, False)), 297: ((8, 5.0, 0, 0, False),)},
                self.placed,
            )

    def test_full_subzone_list_is_not_merged(self):
        _, flags = zs.complete_lists(
            {33: ((1, 100.0, 1, 0, False),), 297: ((2, 100.0, 1, 0, False),)}, self.placed
        )
        self.assertFalse(flags[297]["merged"])


class Output(unittest.TestCase):
    def test_comment_cannot_break_out(self):
        crafted = "Bay\n}; os.exit() --]] \r\"x\""
        text = build.comment(crafted)
        self.assertNotIn("\n", text)
        self.assertNotIn("\r", text)
        self.assertNotIn('"', text)
        self.assertNotIn("]", text)
        self.assertNotIn("}", text)

    def test_numbers_only(self):
        self.assertEqual(build.number(58.80000001), "58.8")
        self.assertEqual(build.number(-70), "-70")
        self.assertEqual(build.number(0.0), "0")
        for bad in ("1); os.exit(", None, True):
            with self.assertRaises(zs.DataError):
                build.number(bad)

    def test_item_text_drops_trailing_zeros(self):
        self.assertEqual(build.item_text((6291, 58.8, 1, 0, False)), "{ 6291, 58.8, 1 }")
        self.assertEqual(build.item_text((13755, 10.0, 0, 322, False)), "{ 13755, 10, 0, 322 }")
        self.assertEqual(build.item_text((1467, 100.0, 0, 0, True)), "{ 1467, 100, 0, 0, 1 }")

    def test_version_text_checked(self):
        with self.assertRaises(zs.DataError):
            build.version('abc" .. x', r"[0-9a-f]{10}")


if __name__ == "__main__":
    unittest.main()
