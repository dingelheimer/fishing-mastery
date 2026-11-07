"""Download the pinned zone and journal data sources and keep the rows the builds use in
tools/data/.

Usage (repository root): python tools/fetch_zone_sources.py

Sources (fixed HTTPS URLs, pinned versions):
- CMaNGOS classic-db (GPL-3.0), Full_DB dump at commit CMANGOS_COMMIT: the tables
  fishing_loot_template, reference_loot_template, skill_fishing_base_level, conditions; for the
  journal (journal_sources.py) rows of item_template, spell_template, npc_vendor, npc_trainer(_
  template), quest_template rewards, the loot tables, game_event, game_event_time.
- AllTheThings Forever client exports (MIT), build CLIENT_BUILD at commit ATT_COMMIT: AreaTable,
  UiMap, UiMapAssignment; SkillLineAbility for the journal.

Downloaded files are parsed as data and never executed. The trimmed copies replace the files in
tools/data/; the script prints which areas changed compared with the committed copies, and how
many journal rows were added or removed per file.
Python 3 standard library only.
"""

import csv
import gzip
import io
import os
import sys
import urllib.request

import journal_sources as journal
from zone_sources import (
    ATT_COMMIT,
    CLIENT_BUILD,
    CMANGOS_COMMIT,
    DATA_DIR,
    FILES,
    area_signatures,
    read_sources,
)

CMANGOS_URL = (
    "https://raw.githubusercontent.com/cmangos/classic-db/"
    + CMANGOS_COMMIT
    + "/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
)
ATT_URL = (
    "https://raw.githubusercontent.com/ATTWoWAddon/AllTheThings/"
    + ATT_COMMIT
    + "/.contrib/.db/forever/.config/.wago/{table}."
    + CLIENT_BUILD
    + ".csv"
)

# Columns kept per table, in file order.
LOOT_COLUMNS = ["entry", "item", "chance", "group", "mincountOrRef", "maxcount", "condition"]
SKILL_COLUMNS = ["entry", "skill"]
CONDITION_COLUMNS = ["condition", "type", "value1", "value2", "value3", "value4", "flags"]
AREA_COLUMNS = ["ID", "AreaName_lang", "ContinentID", "ParentAreaID"]
UIMAP_COLUMNS = ["ID", "Name_lang", "Type", "ParentUiMapID"]
ASSIGNMENT_COLUMNS = ["UiMapID", "AreaID", "MapID"]

MAX_DOWNLOAD = 64 * 1024 * 1024


def download(url):
    if not url.startswith("https://"):
        raise SystemExit("refusing a non-HTTPS URL: " + url)
    request = urllib.request.Request(url, headers={"User-Agent": "fishing-mastery-data-fetch"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read(MAX_DOWNLOAD + 1)
    if len(data) > MAX_DOWNLOAD:
        raise SystemExit("download too large: " + url)
    return data


def sql_rows(text, table):
    """Yields the value tuples of every `INSERT INTO table VALUES (...),(...);` statement."""
    marker = "INSERT INTO `" + table + "` VALUES "
    start = text.find(marker)
    if start < 0:
        raise SystemExit("table not found in the dump: " + table)
    while start >= 0:
        i = start + len(marker)
        while True:
            if text[i] != "(":
                raise SystemExit("unexpected SQL near " + table + " at offset " + str(i))
            i += 1
            row, value, quoted = [], [], False
            while True:
                c = text[i]
                if c == "'":
                    i += 1
                    while text[i] != "'":
                        if text[i] == "\\":
                            i += 1
                        value.append(text[i])
                        i += 1
                    quoted = True
                    i += 1
                elif c in ",)":
                    row.append("".join(value) if quoted or value else "")
                    value, quoted = [], False
                    i += 1
                    if c == ")":
                        break
                else:
                    value.append(c)
                    i += 1
            yield row
            if text[i] == ",":
                i += 1
                continue
            if text[i] == ";":
                break
            raise SystemExit("unexpected SQL end near " + table)
        start = text.find(marker, i)


def loot_rows(rows):
    # The dump's last column (comments) is free text and is dropped.
    return [row[:7] for row in rows]


def trim_cmangos(text):
    fishing = loot_rows(sql_rows(text, "fishing_loot_template"))
    refs = {-int(row[4]) for row in fishing if int(row[4]) < 0}
    reference = [r for r in loot_rows(sql_rows(text, "reference_loot_template")) if int(r[0]) in refs]
    skill = [row[:2] for row in sql_rows(text, "skill_fishing_base_level")]
    used = {row[6] for row in fishing + reference if row[6] != "0"}
    conditions = [row[:7] for row in sql_rows(text, "conditions") if row[0] in used]
    return fishing, reference, skill, conditions


def csv_table(data, columns):
    reader = csv.DictReader(io.StringIO(data.decode("utf-8")))
    missing = [c for c in columns if c not in (reader.fieldnames or [])]
    if missing:
        raise SystemExit("client export misses columns: " + ", ".join(missing))
    return [[row[c] for c in columns] for row in reader]


def trim_client(areas, uimaps, assignments, cmangos_areas):
    by_id = {int(row[0]): row for row in areas}
    keep = set()
    for area in cmangos_areas:
        if area not in by_id:
            raise SystemExit("CMaNGOS area %d is missing in the client AreaTable" % area)
        keep.add(area)
        parent = int(by_id[area][3])
        if parent:
            keep.add(parent)
    kept_assignments = [row for row in assignments if int(row[1]) in keep]
    maps = {int(row[0]) for row in kept_assignments}
    kept_maps = [row for row in uimaps if int(row[0]) in maps]
    kept_areas = [row for row in areas if int(row[0]) in keep]
    return kept_areas, kept_maps, kept_assignments


def sort_key(row):
    key = []
    for value in row:
        try:
            key.append((0, float(value), ""))
        except ValueError:
            key.append((1, 0.0, value))
    return key


def sort_rows(rows):
    return sorted(rows, key=sort_key)


def write_csv(path, columns, rows):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(columns)
        writer.writerows(sort_rows(rows))


def old_rows(path):
    """Rows of a written CSV as a set of tuples (empty when the file does not exist yet)."""
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8", newline="") as handle:
        return {tuple(row) for row in list(csv.reader(handle))[1:]}


def main():
    old = area_signatures(read_sources()) if all(
        os.path.exists(os.path.join(DATA_DIR, name)) for name in FILES.values()
    ) else {}

    print("Downloading CMaNGOS classic-db " + CMANGOS_COMMIT[:10] + " ...")
    text = gzip.decompress(download(CMANGOS_URL)).decode("utf-8", errors="replace")
    fishing, reference, skill, conditions = trim_cmangos(text)
    cmangos_areas = {int(r[0]) for r in fishing} | {int(r[0]) for r in skill}

    print("Downloading Forever client exports " + CLIENT_BUILD + " ...")
    exports = {
        table: download(ATT_URL.format(table=table))
        for table in ("AreaTable", "UiMap", "UiMapAssignment", "SkillLineAbility")
    }
    areas, uimaps, assignments = trim_client(
        csv_table(exports["AreaTable"], AREA_COLUMNS),
        csv_table(exports["UiMap"], UIMAP_COLUMNS),
        csv_table(exports["UiMapAssignment"], ASSIGNMENT_COLUMNS),
        cmangos_areas,
    )

    os.makedirs(DATA_DIR, exist_ok=True)
    out = {
        "fishing": (LOOT_COLUMNS, fishing),
        "reference": (LOOT_COLUMNS, reference),
        "skill": (SKILL_COLUMNS, skill),
        "conditions": (CONDITION_COLUMNS, conditions),
        "areas": (AREA_COLUMNS, areas),
        "uimaps": (UIMAP_COLUMNS, uimaps),
        "assignments": (ASSIGNMENT_COLUMNS, assignments),
    }
    for key, (columns, rows) in out.items():
        write_csv(os.path.join(DATA_DIR, FILES[key]), columns, rows)

    abilities = list(csv.DictReader(io.StringIO(exports["SkillLineAbility"].decode("utf-8"))))
    journal_out = journal.trim_journal(
        text, sql_rows, abilities, journal.fishing_item_ids(fishing, reference)
    )
    for key, (columns, rows) in journal_out.items():
        path = os.path.join(DATA_DIR, journal.FILES[key])
        before = old_rows(path)
        write_csv(path, columns, rows)
        after = old_rows(path)
        print("Journal %s: %d rows (%d added, %d removed)"
              % (journal.FILES[key], len(after), len(after - before), len(before - after)))

    new = area_signatures(read_sources())
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = sorted(a for a in set(new) & set(old) if new[a] != old[a])
    print("Kept: %d fishing, %d reference, %d skill, %d condition rows; %d areas, %d UI maps, "
          "%d map assignments" % (len(fishing), len(reference), len(skill), len(conditions),
                                  len(areas), len(uimaps), len(assignments)))
    if not old:
        print("No committed copies to compare with: %d areas written." % len(new))
        return 0
    for label, ids in (("added", added), ("removed", removed), ("changed", changed)):
        print("Areas %s: %s" % (label, ", ".join(str(a) for a in ids) if ids else "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
