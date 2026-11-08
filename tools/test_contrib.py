"""Tests for the contribution checker (standard library unittest).

Usage (repository root): python -m unittest discover -s tools -p "test_*.py"
"""

from __future__ import annotations

import contextlib
import io
import os
import tempfile
import unittest

import contrib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FIXTURE = os.path.join(ROOT, "spec", "fixtures", "contribution.txt")
HEADER = "FMC!1!0a1b2c3d!1.0.0!70790!"


def read_fixture() -> str:
    """The export written by the addon's contribute spec (Story 7.1)."""
    with open(FIXTURE, encoding="utf-8") as handle:
        return handle.read()


def signed(*body: str, header: str = HEADER) -> str:
    """A contribution with a correct checksum over the body lines."""
    text = "\n".join(body)
    return header + contrib.checksum(text) + ("\n" + text if body else "")


class ContribTest(unittest.TestCase):
    zones: contrib.Zones

    @classmethod
    def setUpClass(cls) -> None:
        cls.zones = contrib.load_zones()

    def rejects(self, text: str, rule: str) -> None:
        with self.assertRaises(contrib.Rejected) as caught:
            contrib.parse(text, self.zones)
        self.assertIn(rule, str(caught.exception))

    # ---- accepted ------------------------------------------------------------------------------

    def test_fixture_is_valid(self) -> None:
        result = contrib.parse(read_fixture(), self.zones)
        self.assertEqual(("0a1b2c3d", "1.0.0", "70790"),
                         (result.token, result.version, result.build))
        self.assertEqual({"A": 2, "M": 1, "S": 3, "L": 1}, result.counts())
        self.assertEqual(contrib.Place(15, {6303: 9}), result.areas[2979])
        self.assertEqual(contrib.Place(5, {6303: 2, 6358: 1}), result.areas[14])
        self.assertEqual((12, 3), result.bands[("2979", 10)])
        self.assertEqual((2, 1), result.bands[("m9999", 0)])
        self.assertEqual((5, 3), result.lure[1411])

    def test_checksum_matches_the_addon(self) -> None:
        # Export.Checksum("") and of the fixture body, as the Lua spec computed them.
        self.assertEqual("00001505", contrib.checksum(""))
        header, body = read_fixture().rstrip("\n").split("\n", 1)
        self.assertEqual(header.rsplit("!", 1)[1], contrib.checksum(body))

    def test_empty_contribution_is_valid(self) -> None:
        self.assertEqual({"A": 0, "M": 0, "S": 0, "L": 0},
                         contrib.parse(signed(), self.zones).counts())

    def test_pasted_text_is_cleaned(self) -> None:
        fixture = read_fixture()
        fenced = "```text\r\n" + fixture.replace("\n", "\r\n") + "```\r\n"
        self.assertEqual(2, len(contrib.parse(fenced, self.zones).areas))
        doubled = "  " + fixture.replace("!", "||") + "\n\n"
        self.assertEqual(2, len(contrib.parse(doubled, self.zones).areas))

    def test_an_area_without_items_and_an_item_line_kind_mix(self) -> None:
        result = contrib.parse(signed("A!14!3!", "M!1234!1!6291:1"), self.zones)
        self.assertEqual({}, result.areas[14].items)
        self.assertEqual(1, result.maps[1234].casts)

    # ---- rejected, one test per rule -----------------------------------------------------------

    def test_bad_header(self) -> None:
        self.rejects("FMX!1!0a1b2c3d!1.0.0!70790!00001505", "bad header")
        self.rejects("FMC!1!NOTATOKN!1.0.0!70790!00001505", "bad header")
        self.rejects("", "bad header")

    def test_unknown_format_version(self) -> None:
        self.rejects(signed(header="FMC!2!0a1b2c3d!1.0.0!70790!"), "unknown format version")

    def test_checksum_mismatch(self) -> None:
        self.rejects(read_fixture().replace("6303:9", "6303:10"), "checksum mismatch")
        self.rejects(read_fixture().rsplit("\n", 2)[0], "checksum mismatch")  # incomplete

    def test_unknown_line_kind(self) -> None:
        self.rejects(signed("A!14!5!", "T!1!2"), "line 3: unknown line kind")

    def test_wrong_field_count(self) -> None:
        self.rejects(signed("A!14!5"), "A line needs 4 fields")
        self.rejects(signed("S!14!10!3"), "S line needs 5 fields")
        self.rejects(signed("L!1411!1"), "L line needs 4 fields")
        self.rejects(signed("A!14!5!6303"), "item entry is not")

    def test_non_integer_or_negative_counts(self) -> None:
        self.rejects(signed("A!14!five!"), "casts is not a non-negative integer")
        self.rejects(signed("A!14!-5!"), "casts is not a non-negative integer")
        self.rejects(signed("A!14!5!6303:1.5"), "catches is not a non-negative integer")
        self.rejects(signed("S!14!10!3!-1"), "getaways is not a non-negative integer")
        self.rejects(signed("A!14!12345678901!"), "casts is not a non-negative integer")

    def test_ids_out_of_range(self) -> None:
        self.rejects(signed("A!362!5!"), "area ID out of range")  # not in the bundled data
        self.rejects(signed("A!14!5!0:1"), "item ID out of range")
        self.rejects(signed("A!14!5!1000000:1"), "item ID out of range")
        self.rejects(signed("M!0!5!"), "map ID out of range")
        self.rejects(signed("S!m0!10!3!1"), "map ID out of range")
        self.rejects(signed("S!362!10!3!1"), "area ID out of range")
        self.rejects(signed("S!14!12!3!1"), "band out of range")
        self.rejects(signed("L!0!1!1"), "map ID out of range")

    def test_catches_above_casts(self) -> None:
        self.rejects(signed("A!14!5!6303:6"), "catches above casts")
        self.rejects(signed("A!14!5!", "L!1411!2!3"), "catches above casts")

    def test_getaways_above_hooked(self) -> None:
        self.rejects(signed("S!14!10!3!4"), "getaways above hooked")

    def test_lure_above_the_maps_casts(self) -> None:
        # Map 1411 is Durotar: areas 14 and its subzones (2979) count, Barrens areas do not.
        self.assertEqual(1, len(contrib.parse(signed("A!14!2!", "A!2979!3!", "L!1411!5!1"),
                                              self.zones).lure))
        self.rejects(signed("A!14!2!", "A!2979!3!", "L!1411!6!1"), "lure casts above")
        self.rejects(signed("L!1234!1!0"), "lure casts above")
        self.assertEqual(1, len(contrib.parse(signed("M!1234!1!", "L!1234!1!0"),
                                              self.zones).lure))

    def test_duplicate_keys(self) -> None:
        self.rejects(signed("A!14!5!", "A!14!1!"), "duplicate A line")
        self.rejects(signed("M!1234!5!", "M!1234!1!"), "duplicate M line")
        self.rejects(signed("S!14!10!3!1", "S!14!10!1!0"), "duplicate S line")
        self.rejects(signed("A!14!5!", "L!1411!1!0", "L!1411!1!0"), "duplicate L line")
        self.rejects(signed("A!14!5!6303:1,6303:2"), "duplicate item")

    def test_size_limit(self) -> None:
        self.rejects(read_fixture() + " " * contrib.MAX_CHARS, "longer than 65536 characters")

    def test_messages_never_echo_the_content(self) -> None:
        secret = "Brannoc"
        for text in (secret, signed("A!14!" + secret + "!"), signed("A!14!5!", secret)):
            with self.assertRaises(contrib.Rejected) as caught:
                contrib.parse(text, self.zones)
            self.assertNotIn(secret, str(caught.exception))

    # ---- command line --------------------------------------------------------------------------

    def run_main(self, path: str) -> tuple[int, str]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = contrib.main(["contrib.py", path])
        return code, out.getvalue().strip()

    def test_command_line(self) -> None:
        self.assertEqual((0, "valid: A 2, M 1, S 3, L 1"), self.run_main(FIXTURE))
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "broken.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(read_fixture().replace("6303:9", "6303:10"))
            code, text = self.run_main(path)
            self.assertEqual(1, code)
            self.assertEqual("rejected: checksum mismatch (text changed or incomplete)", text)
            self.assertEqual((2, "cannot read the file"),
                             self.run_main(os.path.join(folder, "missing.txt")))


if __name__ == "__main__":
    unittest.main()
