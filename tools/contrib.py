"""Strict checker for contribution exports (`/fm contribute`, Story 7.1 format).

Usage (repository root):
    python tools/contrib.py <file>

Prints "valid" with the number of lines per kind, or "rejected: <rule>" (exit code 1); 2 on a
missing file. A contribution is untrusted text: it is size-limited before parsing, parsed as data
only, and rejected as a whole on the first broken rule. Messages name the rule and a line number,
never the content. Format:

    FMC!<format>!<token>!<addon version>!<client build>!<checksum>
    A!<area>!<casts>!<item>:<catches>,...       per resolved area
    M!<map>!<casts>!<item>:<catches>,...        places without a resolved area
    S!<area or m<map>>!<band>!<hooked>!<getaways> per 5-point band of effective skill
    L!<map>!<casts with lure>!<catches with lure> per map

The checksum (the addon's Export.Checksum) covers every line after the header joined with "\\n".
Area IDs must be ones the addon can resolve (FishingMastery/Data/Zones.lua). Python 3 standard
library only.
"""

from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass, field

FORMAT = 1
MAX_CHARS = 65536  # the GitHub issue body limit
MAX_ITEM = 999999  # item IDs are positive and below this
MAX_MAP = 99999  # uiMapIDs are positive and below this
MAX_BAND = 1000  # effective skill bands start at 0
ZONES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "FishingMastery", "Data",
                     "Zones.lua")

HEADER = re.compile(r"FMC!(\d+)!([0-9a-f]{8})!([A-Za-z0-9.\-]+)!([A-Za-z0-9.\-]+)!([0-9a-f]{8})")
NUMBER = re.compile(r"\d{1,9}")
FENCE = re.compile(r"^```[A-Za-z]*$")


class Rejected(Exception):
    """A contribution broke a rule; the message names the rule, never the content."""


@dataclass
class Place:
    """Casts and catches per item of one area or map."""

    casts: int
    items: dict[int, int]


@dataclass
class Contribution:
    """A checked contribution."""

    token: str
    version: str
    build: str
    areas: dict[int, Place] = field(default_factory=dict)
    maps: dict[int, Place] = field(default_factory=dict)
    bands: dict[tuple[str, int], tuple[int, int]] = field(default_factory=dict)
    lure: dict[int, tuple[int, int]] = field(default_factory=dict)

    def counts(self) -> dict[str, int]:
        """Lines per kind."""
        return {"A": len(self.areas), "M": len(self.maps), "S": len(self.bands),
                "L": len(self.lure)}


@dataclass(frozen=True)
class Zones:
    """What the bundled zone data allows: resolvable areas and the areas of each map."""

    areas: frozenset[int]
    map_areas: dict[int, frozenset[int]]


# ---- bundled data ------------------------------------------------------------------------------

def _block(text: str, name: str) -> str:
    """The body of a top-level table `    name = { ... }` of the generated data file."""
    match = re.search(r"\n    " + name + r" = \{\n(.*?)\n    \},", text, re.S)
    if not match:
        raise ValueError(f"zone data has no {name} table")
    return match.group(1)


def load_zones(path: str = ZONES) -> Zones:
    """Reads the resolvable area IDs and each map's areas from the generated Zones.lua.

    Args:
        path: The data file.

    Returns:
        The allowed IDs.
    """
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    areas: set[int] = {int(k) for k in re.findall(r"^        \[(\d+)\] = \{", _block(text, "areas"),
                                                   re.M)}
    children: dict[int, set[int]] = {}
    for zone, ids in re.findall(r"^        \[(\d+)\] = \{ ([\d, ]+) \}", _block(text, "children"),
                                re.M):
        children[int(zone)] = {int(i) for i in ids.split(",")}
        areas.update(children[int(zone)])
    map_areas: dict[int, frozenset[int]] = {}
    for map_id, zone in re.findall(r"^        \[(\d+)\] = (\d+),", _block(text, "mapToArea"), re.M):
        zone_id = int(zone)
        areas.add(zone_id)
        map_areas[int(map_id)] = frozenset({zone_id} | children.get(zone_id, set()))
    for area in re.findall(r"^        \[\d+\] = (\d+),", _block(text, "instanceToArea"), re.M):
        areas.add(int(area))
    return Zones(frozenset(areas), map_areas)


# ---- text --------------------------------------------------------------------------------------

def checksum(text: str) -> str:
    """The addon's Export.Checksum: a 32-bit polynomial hash (33) from 5381 as 8 hex digits."""
    value = 5381
    for byte in text.encode("utf-8"):
        value = (value * 33 + byte) % 4294967296
    return f"{value:08x}"


def clean(text: str) -> str:
    """Undoes what pasting can do: Markdown code fences, Windows line ends, spaces around lines,
    and the addon's internal "|" form (doubled "||" from an edit box, "|" for "!")."""
    lines = [line.strip() for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    lines = [line for line in lines if line and not FENCE.match(line)]
    return "\n".join(lines).replace("||", "|").replace("|", "!")


def _count(value: str, rule: str, line: int) -> int:
    if not NUMBER.fullmatch(value):
        raise Rejected(f"line {line}: {rule} is not a non-negative integer")
    return int(value)


def _id(value: str, highest: int, what: str, line: int) -> int:
    number = _count(value, what, line)
    if number < 1 or number > highest:
        raise Rejected(f"line {line}: {what} out of range")
    return number


def _items(value: str, casts: int, line: int) -> dict[int, int]:
    items: dict[int, int] = {}
    if value == "":
        return items
    for part in value.split(","):
        pieces = part.split(":")
        if len(pieces) != 2:
            raise Rejected(f"line {line}: item entry is not <item>:<catches>")
        item = _id(pieces[0], MAX_ITEM, "item ID", line)
        catches = _count(pieces[1], "catches", line)
        if item in items:
            raise Rejected(f"line {line}: duplicate item")
        if catches > casts:
            raise Rejected(f"line {line}: catches above casts")
        items[item] = catches
    return items


def _place(fields: list[str], line: int, zones: Zones, kind: str) -> tuple[int, Place]:
    if len(fields) != 4:
        raise Rejected(f"line {line}: {kind} line needs 4 fields")
    if kind == "A":
        key = _count(fields[1], "area ID", line)
        if key not in zones.areas:
            raise Rejected(f"line {line}: area ID out of range")
    else:
        key = _id(fields[1], MAX_MAP, "map ID", line)
    casts = _count(fields[2], "casts", line)
    return key, Place(casts, _items(fields[3], casts, line))


def _band(fields: list[str], line: int, zones: Zones) -> tuple[tuple[str, int], tuple[int, int]]:
    if len(fields) != 5:
        raise Rejected(f"line {line}: S line needs 5 fields")
    key = fields[1]
    if key.startswith("m"):
        _id(key[1:], MAX_MAP, "map ID", line)
    elif _count(key, "area ID", line) not in zones.areas:
        raise Rejected(f"line {line}: area ID out of range")
    band = _count(fields[2], "band", line)
    if band > MAX_BAND or band % 5:
        raise Rejected(f"line {line}: band out of range")
    hooked, getaways = _count(fields[3], "hooked", line), _count(fields[4], "getaways", line)
    if getaways > hooked:
        raise Rejected(f"line {line}: getaways above hooked")
    return (key, band), (hooked, getaways)


def _map_casts(result: Contribution, zones: Zones, map_id: int) -> int:
    areas = zones.map_areas.get(map_id, frozenset())
    placed = sum(p.casts for a, p in result.areas.items() if a in areas)
    return placed + (result.maps[map_id].casts if map_id in result.maps else 0)


def parse(text: str, zones: Zones | None = None) -> Contribution:
    """Checks a contribution text completely.

    Args:
        text: The pasted text (cleaned first: fences, line ends, pipes).
        zones: The allowed IDs; read from the bundled data when None.

    Returns:
        The checked contribution.

    Raises:
        Rejected: On the first broken rule.
    """
    if len(text) > MAX_CHARS:
        raise Rejected(f"longer than {MAX_CHARS} characters")
    zones = zones or load_zones()
    lines = clean(text).split("\n")
    header = HEADER.fullmatch(lines[0])
    if not header:
        raise Rejected("line 1: bad header")
    if int(header.group(1)) != FORMAT:
        raise Rejected("line 1: unknown format version")
    body = lines[1:]
    if checksum("\n".join(body)) != header.group(5):
        raise Rejected("checksum mismatch (text changed or incomplete)")
    result = Contribution(header.group(2), header.group(3), header.group(4))
    lures: list[tuple[int, int, int, int]] = []
    for number, line in enumerate(body, start=2):
        fields = line.split("!")
        kind = fields[0]
        if kind in ("A", "M"):
            key, place = _place(fields, number, zones, kind)
            target = result.areas if kind == "A" else result.maps
            if key in target:
                raise Rejected(f"line {number}: duplicate {kind} line")
            target[key] = place
        elif kind == "S":
            key_band, counts = _band(fields, number, zones)
            if key_band in result.bands:
                raise Rejected(f"line {number}: duplicate S line")
            result.bands[key_band] = counts
        elif kind == "L":
            if len(fields) != 4:
                raise Rejected(f"line {number}: L line needs 4 fields")
            map_id = _id(fields[1], MAX_MAP, "map ID", number)
            casts = _count(fields[2], "casts", number)
            catches = _count(fields[3], "catches", number)
            if map_id in result.lure:
                raise Rejected(f"line {number}: duplicate L line")
            if catches > casts:
                raise Rejected(f"line {number}: catches above casts")
            result.lure[map_id] = (casts, catches)
            lures.append((number, map_id, casts, catches))
        else:
            raise Rejected(f"line {number}: unknown line kind")
    for number, map_id, casts, _ in lures:
        if casts > _map_casts(result, zones, map_id):
            raise Rejected(f"line {number}: lure casts above the map's casts")
    return result


def main(argv: list[str]) -> int:
    """Command line: checks one file and prints the result."""
    if len(argv) != 2:
        print(__doc__.strip().split("\n\n")[1])
        return 2
    try:
        with open(argv[1], encoding="utf-8", errors="replace") as handle:
            text = handle.read(MAX_CHARS + 1)
    except OSError:
        print("cannot read the file")
        return 2
    try:
        result = parse(text)
    except Rejected as error:
        print(f"rejected: {error}")
        return 1
    counts = ", ".join(f"{kind} {n}" for kind, n in result.counts().items())
    print(f"valid: {counts}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
