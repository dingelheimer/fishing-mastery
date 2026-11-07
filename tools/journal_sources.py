"""Shared part of the journal data tools: the trimmed journal source files in tools/data/, how the
fetch script trims them from the CMaNGOS dump and the Forever SkillLineAbility export, and the
rules that turn them into journal groups, recipes, gear, and season rules (Journal research doc).

Python 3 standard library only. Every value used in the output is converted to int here; item and
spell names are only read for sanitized comments.
"""

import csv
import os
import re
from collections import defaultdict

from zone_sources import DATA_DIR, SEASON_CONDITIONS, DataError

FILES = {
    "items": "cmangos_item_template.csv",
    "spells": "cmangos_spell_template.csv",
    "vendors": "cmangos_npc_vendor.csv",
    "trainers": "cmangos_npc_trainer.csv",
    "quests": "cmangos_quest_rewards.csv",
    "drops": "cmangos_item_drops.csv",
    "events": "cmangos_game_event.csv",
    "abilities": "forever_SkillLineAbility.csv",
}

ITEM_COLUMNS = ["entry", "class", "subclass", "name", "Quality", "RequiredSkill",
                "RequiredSkillRank", "RequiredLevel", "AllowableRace", "FoodType", "openable",
                "spellid_1", "spellid_2", "spellid_3", "spellid_4", "spellid_5"]
SPELL_COLUMNS = (["Id", "SpellName"] + ["Reagent%d" % i for i in range(1, 9)]
                 + ["ReagentCount%d" % i for i in range(1, 9)]
                 + [f % i for f in ("Effect%d", "EffectItemType%d", "EffectApplyAuraName%d",
                                    "EffectMiscValue%d", "EffectBasePoints%d", "EffectTriggerSpell%d")
                    for i in range(1, 4)])
VENDOR_COLUMNS = ["entry", "item"]
TRAINER_COLUMNS = ["spell", "reqskillvalue"]
QUEST_COLUMNS = ["quest", "item", "races"]  # races = quest_template.RequiredRaces
DROP_COLUMNS = ["source", "item"]
EVENT_COLUMNS = ["entry", "start_time", "occurence", "length"]
ABILITY_COLUMNS = ["SkillLine", "Spell", "MinSkillLineRank", "TrivialSkillLineRankLow",
                   "TrivialSkillLineRankHigh"]

PROFESSIONS = {185: "Cooking", 171: "Alchemy", 356: "Fishing"}  # Forever skill lines kept
FISHING_SKILL = 356
SKILL_AURAS = {30, 98}  # SPELL_AURA_MOD_SKILL, MOD_SKILL_TALENT
EFFECT_CREATE_ITEM = 24
EFFECT_LEARN_SPELL = 36
ITEM_CLASS_RECIPE = 9
DROP_TABLES = ("creature_loot_template", "gameobject_loot_template", "item_loot_template",
               "fishing_loot_template", "reference_loot_template")

# Group rules (Journal research doc, "Items From Fishing"). Classes alone cannot split trophy fish
# from junk (both class 15) or fish from potions (both class 0/3), so these ID lists complete them.
TROPHY = frozenset([6292, 6294, 6295, 6309, 6310, 6311, 6363, 6364, 13876, 13877, 13878, 13879,
                    13880, 13882, 13883, 13884, 13885, 13886, 13887, 13901, 13902, 13903, 13904,
                    13905, 13907, 13908, 13909, 13910, 13911, 13912, 13913, 13914, 13915, 13916,
                    13917])
FISH_EXTRA = frozenset([6299, 6360, 6522])  # Sickly Looking Fish, Steelscale Crushfish, Deviate Fish
JUNK_EXTRA = frozenset([6651])  # Broken Wine Bottle (a weapon by class)
OTHER_CLASSES = frozenset([2, 4, 7])  # weapons, armor, trade goods not caught by a rule above
FOOD_FISH = 2  # item_template.FoodType of fish
GROUPS = ("fish", "trophy", "container", "quest", "potion", "junk", "other")
JOURNAL_GROUPS = ("fish", "trophy", "container", "quest")  # owner decision 3 (2026-11-06)
SEASON_EVENTS = {35: "winter", 36: "summer"}


def _read(name):
    path = os.path.join(DATA_DIR, FILES[name])
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def read_sources():
    return {name: _read(name) for name in FILES}


def _int(row, key):
    return int(float(row[key] or 0))


# ---- trimming (fetch time) -------------------------------------------------------------------

def sql_columns(text, table):
    """Column names of `CREATE TABLE table`, in order."""
    start = text.find("CREATE TABLE `" + table + "`")
    if start < 0:
        raise SystemExit("table not found in the dump: " + table)
    end = text.find("\n)", start)
    return re.findall(r"^\s*`(\w+)`", text[start:end], re.M)[0:]


def named_rows(text, table, sql_rows):
    columns = sql_columns(text, table)
    for row in sql_rows(text, table):
        if len(row) != len(columns):
            raise SystemExit("column count mismatch in " + table)
        yield dict(zip(columns, row))


def fishing_item_ids(fishing, reference):
    """Item IDs a fishing roll can give (trimmed loot rows: entry, item, chance, group, ref...)."""
    return {int(r[1]) for r in fishing + reference if int(r[4]) >= 0}


def trim_journal(text, sql_rows, abilities, fishing_items):
    """Returns {name: (columns, rows)} for every journal file. `abilities` are the Forever
    SkillLineAbility rows as dicts; `fishing_items` the IDs from fishing_item_ids."""
    def rows(table):
        return named_rows(text, table, sql_rows)

    spells_all = {int(s["Id"]): s for s in rows("spell_template")}
    create = {sid for sid, s in spells_all.items()
              if any(int(s["Effect%d" % e]) == EFFECT_CREATE_ITEM for e in (1, 2, 3))
              and any(int(s["Reagent%d" % i]) in fishing_items for i in range(1, 9))}
    auras = {sid for sid, s in spells_all.items()
             if any(int(s["EffectApplyAuraName%d" % e]) in SKILL_AURAS
                    and int(s["EffectMiscValue%d" % e]) == FISHING_SKILL for e in (1, 2, 3))}
    learn = {sid for sid, s in spells_all.items()
             if any(int(s["Effect%d" % e]) == EFFECT_LEARN_SPELL
                    and int(s["EffectTriggerSpell%d" % e]) in create for e in (1, 2, 3))}

    items_all = {int(i["entry"]): i for i in rows("item_template")}
    openable = {int(r["entry"]) for r in rows("item_loot_template")}

    def spells_of(item):
        return {int(item["spellid_%d" % k]) for k in range(1, 6)}

    gear = {i for i, it in items_all.items() if spells_of(it) & auras}
    recipe_items = {i for i, it in items_all.items()
                    if int(it["class"]) == ITEM_CLASS_RECIPE and spells_of(it) & (create | learn)}
    keep_items = fishing_items | gear | recipe_items
    missing = sorted(fishing_items - set(items_all))
    if missing:
        raise SystemExit("fishing items missing in item_template: %s" % missing)
    items = [[items_all[i][c] if c != "openable" else ("1" if i in openable else "0")
              for c in ITEM_COLUMNS] for i in sorted(keep_items)]
    spells = [[spells_all[s][c] for c in SPELL_COLUMNS] for s in sorted(create | auras | learn)]

    sourced = gear | recipe_items
    vendors = sorted({(r["entry"], r["item"]) for r in rows("npc_vendor") if int(r["item"]) in sourced})
    trainers = sorted({(r["spell"], r["reqskillvalue"])
                       for t in ("npc_trainer", "npc_trainer_template") for r in rows(t)
                       if int(r["spell"]) in create | learn})
    quests = set()
    for q in rows("quest_template"):
        for col in ["RewChoiceItemId%d" % n for n in range(1, 7)] + ["RewItemId%d" % n for n in range(1, 5)]:
            if int(q[col] or 0) in sourced:
                quests.add((q["entry"], q[col], q["RequiredRaces"]))
    drops = set()
    for table in DROP_TABLES:
        for r in rows(table):
            if int(r["item"]) in sourced and int(r["mincountOrRef"]) >= 0:
                drops.add((table.replace("_loot_template", ""), r["item"]))
    events = {r["entry"]: r for r in rows("game_event")}
    times = {r["entry"]: r for r in rows("game_event_time")}
    season_rows = []
    for entry in sorted(SEASON_EVENTS):
        key = str(entry)
        if key not in events or key not in times:
            raise SystemExit("season event %d missing in the dump" % entry)
        season_rows.append([key, times[key]["start_time"], events[key]["occurence"],
                            events[key]["length"]])
    ability_rows = [[a[c] for c in ABILITY_COLUMNS] for a in abilities
                    if int(a["SkillLine"]) in PROFESSIONS]
    return {
        "items": (ITEM_COLUMNS, items),
        "spells": (SPELL_COLUMNS, spells),
        "vendors": (VENDOR_COLUMNS, [list(v) for v in vendors]),
        "trainers": (TRAINER_COLUMNS, [list(t) for t in trainers]),
        "quests": (QUEST_COLUMNS, [list(q) for q in sorted(quests)]),
        "drops": (DROP_COLUMNS, [list(d) for d in sorted(drops)]),
        "events": (EVENT_COLUMNS, season_rows),
        "abilities": (ABILITY_COLUMNS, ability_rows),
    }


# ---- rules (build time) ----------------------------------------------------------------------

def group_of(item):
    """Journal group of one trimmed item row; raises DataError when no rule fits."""
    entry, cls, sub = _int(item, "entry"), _int(item, "class"), _int(item, "subclass")
    if item["openable"] == "1":
        return "container"
    if entry in TROPHY:
        return "trophy"
    if cls == 12:
        return "quest"
    if entry in JUNK_EXTRA:
        return "junk"
    if _int(item, "FoodType") == FOOD_FISH or cls == 5 or entry in FISH_EXTRA:
        return "fish"
    if cls == 0 and sub == 3:
        return "potion"
    if cls == 15:
        return "junk"
    if cls in OTHER_CLASSES:
        return "other"
    raise DataError("item %d (class %d/%d) fits no journal group" % (entry, cls, sub))


def groups(sources, fishing_items):
    items = {_int(i, "entry"): i for i in sources["items"]}
    out = {}
    for entry in sorted(fishing_items):
        if entry not in items:
            raise DataError("fishing item %d missing in the trimmed item table" % entry)
        out[entry] = group_of(items[entry])
    return out


def _spells(sources):
    return {_int(s, "Id"): s for s in sources["spells"]}


def recipes(sources, journal_items):
    """Recipe spell -> dict for every Classic recipe with a journal item as reagent that is on a
    kept Forever skill line. Spells not on a Forever skill line (e.g. "Copy of" spells) are left
    out and returned as the second value."""
    spells = _spells(sources)
    abilities = {_int(a, "Spell"): a for a in sources["abilities"]}
    items = {_int(i, "entry"): i for i in sources["items"]}
    trainers = {_int(t, "spell"): _int(t, "reqskillvalue") for t in sources["trainers"]}
    vendors = {_int(v, "item") for v in sources["vendors"]}
    quests = defaultdict(list)
    for q in sources["quests"]:
        quests[_int(q, "item")].append(_int(q, "quest"))
    drops = {_int(d, "item") for d in sources["drops"]}
    learn = {}  # learn spell -> recipe spell
    for sid, s in spells.items():
        for e in (1, 2, 3):
            if _int(s, "Effect%d" % e) == EFFECT_LEARN_SPELL:
                learn[sid] = _int(s, "EffectTriggerSpell%d" % e)
    teaching = defaultdict(list)  # recipe spell -> recipe items
    for entry, item in items.items():
        if _int(item, "class") != ITEM_CLASS_RECIPE:
            continue
        for k in range(1, 6):
            sid = _int(item, "spellid_%d" % k)
            target = learn.get(sid, sid)
            if target in spells:
                teaching[target].append(entry)

    out, dropped = {}, []
    for sid, s in sorted(spells.items()):
        products = [_int(s, "EffectItemType%d" % e) for e in (1, 2, 3)
                    if _int(s, "Effect%d" % e) == EFFECT_CREATE_ITEM]
        reagents = [(_int(s, "Reagent%d" % i), _int(s, "ReagentCount%d" % i)) for i in range(1, 9)
                    if _int(s, "Reagent%d" % i)]
        if not products or not any(r in journal_items for r, _ in reagents):
            continue
        ability = abilities.get(sid)
        if ability is None:
            dropped.append(sid)
            continue
        recipe = {
            "skill": _int(ability, "SkillLine"),
            "product": products[0],
            "reagents": reagents,
            "low": _int(ability, "TrivialSkillLineRankLow"),
            "high": _int(ability, "TrivialSkillLineRankHigh"),
            "name": s["SpellName"],
        }
        taught = sorted(teaching.get(sid, []))
        if sid in trainers or any(l for l, t in learn.items() if t == sid and l in trainers):
            recipe["source"] = "trainer"
            recipe["learn"] = trainers.get(sid) or min(
                trainers[l] for l, t in learn.items() if t == sid and l in trainers)
        elif taught:
            item = taught[0]
            recipe["item"] = item
            recipe["learn"] = _int(items[item], "RequiredSkillRank")
            if item in vendors:
                recipe["source"] = "vendor"
            elif item in quests:
                recipe["source"], recipe["quest"] = "quest", min(quests[item])
            elif item in drops:
                recipe["source"] = "drop"
            else:
                raise DataError("recipe item %d has no source" % item)
        else:
            raise DataError("recipe %d is neither trained nor taught by an item" % sid)
        out[sid] = recipe
    return out, dropped


def gear(sources, fishing_items):
    """Item -> dict for every obtainable item with a fishing skill aura; items without any source
    are unused copies and returned as the second value. `races` is the item's race mask, or the
    reward quest's when the item allows every race (0 = all)."""
    spells = _spells(sources)
    bonus = {}
    for sid, s in spells.items():
        for e in (1, 2, 3):
            if (_int(s, "EffectApplyAuraName%d" % e) in SKILL_AURAS
                    and _int(s, "EffectMiscValue%d" % e) == FISHING_SKILL):
                bonus[sid] = _int(s, "EffectBasePoints%d" % e) + 1
    vendors = {_int(v, "item") for v in sources["vendors"]}
    quests = defaultdict(list)
    quest_races = {}
    for q in sources["quests"]:
        quests[_int(q, "item")].append(_int(q, "quest"))
        quest_races[_int(q, "quest")] = _int(q, "races")
    drops = defaultdict(set)
    for d in sources["drops"]:
        drops[_int(d, "item")].add(d["source"])
    out, unused = {}, []
    for item in sources["items"]:
        entry = _int(item, "entry")
        found = [bonus[_int(item, "spellid_%d" % k)] for k in range(1, 6)
                 if _int(item, "spellid_%d" % k) in bonus]
        if not found:
            continue
        races = _int(item, "AllowableRace")
        g = {"bonus": max(found), "skill": _int(item, "RequiredSkillRank"),
             "level": _int(item, "RequiredLevel"), "races": 0 if races == -1 else races,
             "name": item["name"]}
        if entry in quests:
            g["source"], g["quest"] = "quest", min(quests[entry])
            if not g["races"]:
                g["races"] = quest_races[g["quest"]]
        elif entry in vendors:
            g["source"] = "vendor"
        elif entry in fishing_items:
            g["source"] = "fishing"
        elif drops[entry]:
            g["source"] = "drop"
        else:
            unused.append(entry)
            continue
        out[entry] = g
    return out, unused


def seasons(sources, lists):
    """Item -> season rule from the fishing loot conditions and the game events."""
    events = {}
    for row in sources["events"]:
        start = re.fullmatch(r"(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)", row["start_time"])
        if not start:
            raise DataError("unexpected event start %r" % row["start_time"])
        events[_int(row, "entry")] = {
            "month": int(start.group(2)), "day": int(start.group(3)), "hour": int(start.group(4)),
            "every": _int(row, "occurence"), "length": _int(row, "length"),
        }
    out = {}
    for items in lists.values():
        for item, _, _, condition, _ in items:
            if not condition:
                continue
            event = SEASON_CONDITIONS[condition]
            if event not in events:
                raise DataError("season event %d missing" % event)
            rule = dict(events[event], event=event, season=SEASON_EVENTS[event])
            if out.get(item, rule) != rule:
                raise DataError("item %d has two season rules" % item)
            out[item] = rule
    return out
