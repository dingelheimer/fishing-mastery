"""Tests for the privacy scan (standard library unittest; needs git on the PATH).

Usage (repository root): python -m unittest discover -s tools -p "test_*.py"
"""

from __future__ import annotations

import contextlib
import io
import os
import subprocess
import tempfile
import unittest

import privacy_scan as ps

ACCOUNT, REALM, FOLDER = "TESTACCT1", "Testrealm", "Brannoc"
KEY, NAME, PART = "Player-1-0ABCDEF0", "Brannoc Ironfin", "Fenwick"
SAVED = """
FishingMasteryDB = {
["chars"] = {
["%s"] = {
["name"] = "%s",
["part"] = "%s",
["subzones"] = {
"Sen'jin Village",
},
["firstSeen"] = 1793865676,
},
},
["settings"] = {
["dev"] = true,
["hud"] = { ["scale"] = 1.5, ["style"] = "full" },
},
["schemaVersion"] = 1,
}
FishingMasteryCharDB = nil
""" % (KEY, NAME, PART)


def make_wtf(root: str) -> str:
    """A fake WTF account folder with one realm and character; returns the saved file path."""
    account = os.path.join(root, "WTF", "Account", ACCOUNT)
    os.makedirs(os.path.join(account, ps.SAVED_DIR))
    os.makedirs(os.path.join(account, REALM, FOLDER))
    path = os.path.join(account, ps.SAVED_DIR, "FishingMastery.lua")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(SAVED)
    return path


def git(repo: str, *args: str) -> None:
    subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid",
                    *args], check=True, capture_output=True)


def commit(repo: str, files: dict[str, str | None], message: str) -> None:
    for name, text in files.items():
        path = os.path.join(repo, name)
        if text is None:
            os.remove(path)
        else:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", message)


class Terms(unittest.TestCase):
    def test_terms_from_folders_and_character_entries(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            terms = ps.collect_terms(make_wtf(root))
        self.assertEqual(terms[ACCOUNT], "account")
        self.assertEqual(terms[REALM], "realm")
        self.assertEqual(terms[FOLDER], "character folder")  # the folder wins over the name part
        self.assertEqual(terms[KEY], "character key")
        self.assertEqual(terms[NAME], "character name")
        self.assertEqual(terms["Ironfin"], "character name")
        self.assertEqual(terms[PART], "character name")
        self.assertNotIn("Sen'jin Village", terms)  # only name fields count

    def test_parser_reads_the_saved_format_and_rejects_others(self) -> None:
        data = ps.parse_saved(SAVED)
        db = data["FishingMasteryDB"]
        assert isinstance(db, dict)
        self.assertEqual(db["settings"]["hud"]["style"], "full")  # type: ignore[index]
        self.assertIsNone(data["FishingMasteryCharDB"])
        with self.assertRaises(ValueError):
            ps.parse_saved("x = y")

    def test_file_outside_saved_variables_is_bad_input(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            path = os.path.join(root, "FishingMastery.lua")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(SAVED)
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                self.assertEqual(ps.main([path]), 2)
        self.assertNotIn(root, err.getvalue())

    def test_word_pattern_escapes(self) -> None:
        self.assertEqual(ps.word_pattern("a.b"), "(^|[^A-Za-z0-9_])a\\.b([^A-Za-z0-9_]|$)")


class Scan(unittest.TestCase):
    def test_history_and_files_counted_by_kind_without_printing_terms(self) -> None:
        with tempfile.TemporaryDirectory() as root:
            saved = make_wtf(root)
            repo = os.path.join(root, "repo")
            os.makedirs(repo)
            git(repo, "init", "-q")
            commit(repo, {"a.md": "fished with %s today\n" % PART}, "one")
            commit(repo, {"a.md": None, "b.md": "%sfish is a word, not a name\n" % FOLDER}, "two")
            commit(repo, {"c.md": "realm: %s\n" % REALM}, "three")

            hits = ps.scan(repo, ps.collect_terms(saved))
            self.assertEqual(hits["character name"], ps.Hits(terms=1, commits=2, files=0))
            self.assertEqual(hits["character folder"], ps.Hits(0, 0, 0))  # inside a longer word
            self.assertEqual(hits["realm"], ps.Hits(terms=1, commits=1, files=1))
            self.assertEqual(hits["account"], ps.Hits(0, 0, 0))

            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(ps.main([saved, repo]), 1)
            text = out.getvalue()
            for secret in (ACCOUNT, REALM, FOLDER, KEY, PART, "Ironfin", root):
                self.assertNotIn(secret, text)
            self.assertIn("result: HITS FOUND", text)

            commit(repo, {"c.md": "no names here\n"}, "four")
            git(repo, "checkout", "-q", "--orphan", "clean")
            git(repo, "commit", "-q", "-m", "fresh history")
            for ref in ("master", "main"):
                subprocess.run(["git", "-C", repo, "branch", "-D", ref], capture_output=True,
                               check=False)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(ps.main([saved, repo]), 0)
            self.assertIn("result: clean", out.getvalue())


if __name__ == "__main__":
    unittest.main()
