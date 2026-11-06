"""Shared part of the zone data tools: pinned versions, the trimmed source files in tools/data/,
loot list resolution the way the CMaNGOS server rolls fishing loot, and area placement.

Python 3 standard library only. Every value read from the sources is converted to int or float
here; text (area names) is only used for sanitized comments.
"""

import csv
import os
from collections import defaultdict

CMANGOS_COMMIT = "37eeeeb1d4c12f00ded1b542e758f71d6135d391"
ATT_COMMIT = "e15f5d9ceebc32a683a09ce2b6609e838a2fab94"
CLIENT_BUILD = "1.60.1.70790"

DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
FILES = {
    "fishing": "cmangos_fishing_loot_template.csv",
    "reference": "cmangos_reference_loot_template.csv",
    "skill": "cmangos_skill_fishing_base_level.csv",
    "conditions": "cmangos_conditions.csv",
    "areas": "forever_AreaTable.csv",
    "uimaps": "forever_UiMap.csv",
    "assignments": "forever_UiMapAssignment.csv",
}

SEASON_CONDITIONS = {322: 35, 323: 36}  # condition ID -> game event ID (winter, summer)
CONDITION_GAME_EVENT = 12  # CMaNGOS condition type "game event active"
UIMAP_ZONE = 3  # UiMap.Type of a zone map
WORLD_CONTINENTS = {0, 1}  # Eastern Kingdoms, Kalimdor; other map IDs are instances


class DataError(Exception):
    """The sources cannot be turned into zone data; the build stops."""


def _read(name):
    path = os.path.join(DATA_DIR, FILES[name])
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def read_sources():
    return {name: _read(name) for name in FILES}


def _loot(row):
    return {
        "entry": int(row["entry"]),
        "item": int(row["item"]),
        "chance": float(row["chance"]),
        "group": int(row["group"]),
        "ref": -int(row["mincountOrRef"]) if int(row["mincountOrRef"]) < 0 else 0,
        "maxcount": int(row["maxcount"]),
        "condition": int(row["condition"]),
    }


def _template(rows):
    """Item rows of one loot template with server chances: a zero chance in a group gets an equal
    share of what the group's explicit chances leave; a negative chance is a quest drop."""
    items = []
    for row in rows:
        if row["ref"]:
            raise DataError("nested reference %d in reference template" % row["ref"])
        chance = abs(row["chance"])
        if chance == 0 and row["group"] == 0:
            raise DataError("ungrouped zero chance: entry %d item %d" % (row["entry"], row["item"]))
        items.append([row["item"], chance, row["group"], row["condition"], row["chance"] < 0])
    for group in {item[2] for item in items if item[2] > 0}:
        members = [item for item in items if item[2] == group]
        explicit = sum(item[1] for item in members)
        zero = [item for item in members if item[1] == 0]
        for item in zero:
            item[1] = max(0.0, 100.0 - explicit) / len(zero)
    return items


def resolve_lists(sources):
    """Area ID -> tuple of (itemID, chance, group, condition, quest) with chances in percent."""
    fishing = defaultdict(list)
    for row in sources["fishing"]:
        fishing[int(row["entry"])].append(_loot(row))
    reference = defaultdict(list)
    for row in sources["reference"]:
        reference[int(row["entry"])].append(_loot(row))
    conditions = {int(r["condition"]): r for r in sources["conditions"]}

    lists = {}
    for area, rows in fishing.items():
        own = [row for row in rows if not row["ref"]]
        items = _template(own)
        own_groups = {item[2] for item in items if item[2] > 0}
        for row in rows:
            if not row["ref"]:
                continue
            if row["ref"] not in reference:
                raise DataError("area %d references missing template %d" % (area, row["ref"]))
            if row["maxcount"] != 1:
                raise DataError("area %d rolls reference %d more than once" % (area, row["ref"]))
            scale = row["chance"] / 100.0
            for item in _template(reference[row["ref"]]):
                if item[2] > 0 and item[2] in own_groups:
                    raise DataError("area %d: group %d in two templates" % (area, item[2]))
                item[1] *= scale
                items.append(item)
        for item in items:
            condition = item[3]
            if condition == 0:
                continue
            if condition not in SEASON_CONDITIONS:
                raise DataError("area %d: unknown condition %d" % (area, condition))
            row = conditions.get(condition)
            if (
                row is None
                or int(row["type"]) != CONDITION_GAME_EVENT
                or int(row["value1"]) != SEASON_CONDITIONS[condition]
            ):
                raise DataError("condition %d is not the expected season event" % condition)
        lists[area] = tuple(
            sorted((item, round(chance, 4), group, cond, quest) for item, chance, group, cond, quest in items)
        )
    return lists


FISH_GROUP = 1  # the one group per list that gives the fish (one item per roll)


def fish_share(items):
    """Percent of a roll the fish group covers."""
    return sum(chance for _, chance, group, _, _ in items if group == FISH_GROUP)


def complete_lists(lists, placed):
    """Owner decision 2026-11-06 (Story 4.3): a subzone list without fish group rows (only
    seasonal or quest rows) is merged with its zone's list, the subzone rows on top. Lists whose
    fish group still covers less than 100 % keep their rows and get the missing percent.

    Returns (area -> list, area -> {"merged": bool, "partial": percent or None})."""
    for area, items in lists.items():
        groups = {group for _, _, group, _, _ in items}
        if groups - {0, FISH_GROUP}:
            raise DataError("area %d has groups %s; only 0 and 1 are known" % (area, sorted(groups)))
    done, flags = {}, {}
    for area, items in lists.items():
        merged = False
        place = placed[area]
        if place["kind"] == "subzone" and fish_share(items) == 0 and place["zone"] in lists:
            zone_items = lists[place["zone"]]
            keys = {(item, group) for item, _, group, _, _ in zone_items}
            for item, _, group, _, _ in items:
                if (item, group) in keys:
                    raise DataError("area %d: item %d already in the zone list" % (area, item))
            items = tuple(sorted(zone_items + items))
            merged = True
        missing = round(100.0 - fish_share(items), 2)
        done[area] = items
        flags[area] = {"merged": merged, "partial": missing if missing > 0.01 else None}
    return done, flags


def base_skills(sources):
    return {int(row["entry"]): int(row["skill"]) for row in sources["skill"]}


def place_areas(sources, area_ids):
    """Places every area as a zone (with its UI map), a subzone (parent zone in the data), or a
    dungeon (instance map). Raises DataError for an area that fits none of them."""
    table = {int(r["ID"]): r for r in sources["areas"]}
    uimap_type = {int(r["ID"]): int(r["Type"]) for r in sources["uimaps"]}
    zone_maps = defaultdict(set)
    for row in sources["assignments"]:
        area, uimap = int(row["AreaID"]), int(row["UiMapID"])
        if area and uimap_type.get(uimap) == UIMAP_ZONE:
            zone_maps[area].add(uimap)

    placed = {}
    for area in sorted(area_ids):
        row = table.get(area)
        if row is None:
            raise DataError("area %d is not in the client AreaTable" % area)
        parent, continent = int(row["ParentAreaID"]), int(row["ContinentID"])
        if parent == 0 and zone_maps.get(area):
            if len(zone_maps[area]) != 1:
                raise DataError("area %d has several zone maps" % area)
            placed[area] = {"kind": "zone", "map": min(zone_maps[area])}
        elif parent == 0 and continent not in WORLD_CONTINENTS:
            placed[area] = {"kind": "dungeon", "instance": continent}
        elif parent:
            placed[area] = {"kind": "subzone", "zone": parent}
        else:
            raise DataError("area %d (%s) cannot be placed" % (area, row["AreaName_lang"]))
    for area, place in placed.items():
        if place["kind"] == "subzone":
            zone = placed.get(place["zone"]) or {}
            if zone.get("kind") != "zone":
                raise DataError("subzone %d: parent %d is not a zone in the data" % (area, place["zone"]))
    instances = defaultdict(list)
    for area, place in placed.items():
        if place["kind"] == "dungeon":
            instances[place["instance"]].append(area)
    for instance, areas in instances.items():
        if len(areas) > 1:
            raise DataError("instance %d holds several areas %s" % (instance, areas))
    for area in placed:
        placed[area]["name"] = table[area]["AreaName_lang"]
    return placed


def area_signatures(sources):
    """Area ID -> comparable tuple of everything the build writes for it (change report)."""
    lists = resolve_lists(sources)
    skills = base_skills(sources)
    areas = set(lists) | set(skills)
    table = {int(r["ID"]): r for r in sources["areas"]}
    maps = defaultdict(set)
    for row in sources["assignments"]:
        maps[int(row["AreaID"])].add(int(row["UiMapID"]))
    signatures = {}
    for area in areas:
        row = table.get(area) or {}
        signatures[area] = (
            skills.get(area),
            lists.get(area),
            row.get("AreaName_lang"),
            row.get("ParentAreaID"),
            row.get("ContinentID"),
            tuple(sorted(maps.get(area, ()))),
        )
    return signatures
