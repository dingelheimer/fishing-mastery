"""Privacy scan before a repository goes public: searches the full git history and the current
files for the account, realm, and character names of a local game installation.

Usage (repository root):
    python tools/privacy_scan.py <path to FishingMastery.lua in WTF/.../SavedVariables> [repo ...]

The terms come from the saved file's folder names (account, realm, character folders) and from
`FishingMasteryDB.chars` (character keys, name parts). A term counts only as a whole word, so a
name inside a longer word ("Angel" in "Angelfish") is no hit. The output gives counts per term
kind only; it never prints a term, the account folder, or the input path. Exit code 1 on any hit,
2 on bad input. Python 3 standard library only.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from dataclasses import dataclass

MIN_LENGTH = 3  # shorter terms match too much ordinary text
KINDS = ("account", "realm", "character folder", "character key", "character name")
NAME_FIELDS = ("name", "part")  # FishingMasteryDB.chars[key] fields with the name parts
SAVED_DIR = "SavedVariables"


@dataclass(frozen=True)
class Hits:
    """Hits of one term kind: terms found, commits and current files that contain them."""

    terms: int
    commits: int
    files: int


# ---- terms -------------------------------------------------------------------------------------

def folder_terms(saved_file: str) -> dict[str, str]:
    """Account, realm, and character folder names around a saved variables file.

    Args:
        saved_file: Path to `WTF/Account/<account>/SavedVariables/FishingMastery.lua`.

    Returns:
        Term to kind.

    Raises:
        ValueError: The file does not sit in an account's SavedVariables folder.
    """
    saved_dir = os.path.dirname(os.path.abspath(saved_file))
    if os.path.basename(saved_dir) != SAVED_DIR:
        raise ValueError("the file is not in a SavedVariables folder")
    account_dir = os.path.dirname(saved_dir)
    terms = {os.path.basename(account_dir): "account"}
    for realm in sorted(os.listdir(account_dir)):
        realm_dir = os.path.join(account_dir, realm)
        if realm == SAVED_DIR or not os.path.isdir(realm_dir):
            continue
        terms.setdefault(realm, "realm")
        for char in sorted(os.listdir(realm_dir)):
            if os.path.isdir(os.path.join(realm_dir, char)):
                terms.setdefault(char, "character folder")
    return terms


_TOKEN = re.compile(r'\s*(?:"((?:[^"\\]|\\.)*)"|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|'
                    r"([A-Za-z_]\w*)|(\S))", re.S)


def _tokens(text: str) -> list[tuple[str, str]]:
    out = []
    for m in _TOKEN.finditer(text):
        if m.group(1) is not None:
            out.append(("str", re.sub(r"\\(.)", r"\1", m.group(1))))
        elif m.group(2) is not None:
            out.append(("num", m.group(2)))
        elif m.group(3) is not None:
            out.append(("name", m.group(3)))
        else:
            out.append(("sym", m.group(4)))
    return out


def parse_saved(text: str) -> dict[str, object]:
    """Parses the subset of Lua that the game writes to saved variables files.

    Args:
        text: File content: `Name = <value>` assignments of strings, numbers, booleans, nil,
            and tables with `["key"] = value`, `[1] = value`, or list items.

    Returns:
        Global name to value; tables become dicts.

    Raises:
        ValueError: The text is not in that format.
    """
    tokens, pos = _tokens(text), 0

    def take() -> tuple[str, str]:
        nonlocal pos
        if pos >= len(tokens):
            raise ValueError("unexpected end of the saved file")
        pos += 1
        return tokens[pos - 1]

    def value() -> object:
        kind, tok = take()
        if kind in ("str", "num"):
            return tok
        if kind == "name" and tok in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[tok]
        if (kind, tok) != ("sym", "{"):
            raise ValueError("unexpected token in the saved file")
        table: dict[object, object] = {}
        index = 1
        while tokens[pos] != ("sym", "}"):
            if tokens[pos] == ("sym", "["):
                take()
                key = value()
                if take() != ("sym", "]") or take() != ("sym", "="):
                    raise ValueError("bad table key in the saved file")
                table[key] = value()
            else:
                table[str(index)] = value()
                index += 1
            if tokens[pos] == ("sym", ","):
                take()
        take()
        return table

    result: dict[str, object] = {}
    while pos < len(tokens):
        kind, name = take()
        if kind != "name" or take() != ("sym", "="):
            raise ValueError("expected an assignment in the saved file")
        result[name] = value()
    return result


def char_terms(text: str) -> dict[str, str]:
    """Character keys and name parts from `FishingMasteryDB.chars` of a saved file's text."""
    db = parse_saved(text).get("FishingMasteryDB")
    chars = db.get("chars") if isinstance(db, dict) else None
    terms: dict[str, str] = {}
    for key, char in (chars.items() if isinstance(chars, dict) else ()):
        if isinstance(key, str):
            terms[key] = "character key"
        if isinstance(char, dict):
            for field in NAME_FIELDS:
                value = char.get(field)
                if isinstance(value, str):
                    for part in [value, *value.split()]:
                        terms.setdefault(part, "character name")
    return terms


def collect_terms(saved_file: str) -> dict[str, str]:
    """Every term of a saved file: folder names first, then the character entries."""
    terms = folder_terms(saved_file)
    with open(saved_file, encoding="utf-8", errors="replace") as handle:
        for term, kind in char_terms(handle.read()).items():
            terms.setdefault(term, kind)
    return {t: k for t, k in terms.items() if len(t) >= MIN_LENGTH}


# ---- search ------------------------------------------------------------------------------------

def _git(repo: str, *args: str) -> str:
    # Fixed arguments, no shell; the terms go in as one argument each.
    result = subprocess.run(  # noqa: S603
        ["git", "-C", repo, *args],  # noqa: S607
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError("git failed in a scanned repository")
    return result.stdout


def word_pattern(term: str) -> str:
    """POSIX extended regex that finds the term as a whole word (git -G and git grep -E)."""
    escaped = re.sub(r"([.^$*+?()\[\]{}|\\])", r"\\\1", term)
    return "(^|[^A-Za-z0-9_])" + escaped + "([^A-Za-z0-9_]|$)"


def scan(repo: str, terms: dict[str, str]) -> dict[str, Hits]:
    """Counts per kind: the terms found, and the commits and current files that hold them."""
    found: dict[str, list[int]] = {kind: [0, 0, 0] for kind in KINDS}
    for term, kind in terms.items():
        pattern = word_pattern(term)
        commits = _git(repo, "log", "--all", "-G", pattern, "--format=%H").split()
        files = _git(repo, "grep", "-l", "-E", "-e", pattern).split("\n")
        files = [f for f in files if f]
        if commits or files:
            counts = found[kind]
            counts[0] += 1
            counts[1] += len(commits)
            counts[2] += len(files)
    return {kind: Hits(*counts) for kind, counts in found.items()}


def report(name: str, hits: dict[str, Hits]) -> list[str]:
    """Output lines for one repository: counts only."""
    lines = []
    for kind in KINDS:
        h = hits[kind]
        lines.append("%s: %s: %d terms found, %d commits, %d current files"
                     % (name, kind, h.terms, h.commits, h.files))
    return lines


def main(argv: list[str]) -> int:
    """Runs the scan; returns the exit code (0 clean, 1 hits, 2 bad input)."""
    if not argv:
        print("usage: privacy_scan.py <saved variables file> [repository ...]", file=sys.stderr)
        return 2
    saved_file, repos = argv[0], argv[1:] or ["."]
    try:
        terms = collect_terms(saved_file)
    except (OSError, ValueError, IndexError) as err:
        # The message never holds the path or a term.
        print("cannot read the saved file: %s" % type(err).__name__, file=sys.stderr)
        return 2
    print("terms: " + ", ".join("%s %d" % (k, sum(1 for v in terms.values() if v == k))
                                for k in KINDS))
    dirty = False
    for repo in repos:
        hits = scan(repo, terms)
        for line in report(os.path.basename(os.path.abspath(repo)), hits):
            print(line)
        dirty = dirty or any(h.terms for h in hits.values())
    print("result: " + ("HITS FOUND" if dirty else "clean"))
    return 1 if dirty else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
