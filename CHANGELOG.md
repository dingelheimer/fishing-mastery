# Changelog

## Unreleased

- New: casting key. Bind a key to "Cast Fishing" (Key Bindings, AddOns, Fishing Mastery); the
  settings panel has a Helpers section that says where.
- Fixed: the Recipes tab listed cooking recipes with raw meat or eggs as recipes that use fish.
  A Forever item now counts as a fish only once it was caught while fishing.

## 0.9.0-beta

First public test release for World of Warcraft: Forever.

### Tracking

- Records every fishing cast and its outcome: catch, getaway, early click, timeout, cancel,
  invalid target. Catches keep the bite time, the loot, and the place (zone and subzone).
- History is stored per character in compact day chunks, with daily snapshots of the totals,
  `/fm rebuild`, and a quarantine for damaged parts instead of deleting them.
- `/fm export` (no names or IDs) and `/fm export all` (full backup) as copyable text pages;
  `/fm import` adds missing days.

### Statistics

- HUD with session casts, catches, success rate, catches per hour, skill, lure time, the last
  catch, and two zone lines (getaway risk at your skill and fish not caught there yet).
- Session summary in the chat.
- Stats window with eight tabs: Overview, Fish, Zones, Failures, Bite times, Sessions, Skill,
  Compare. Every rate has a 95 % range; small samples show counts only.
- Item tooltip line "caught 37x" for items you caught; settings panel; minimap button and addon
  compartment entry.

### Zones and journal

- Bundled Classic fish lists and base skill for 136 areas (CMaNGOS classic-db), shown as "Classic
  estimate" next to your own catches, and the Classic getaway model next to your getaway rate.
- Journal window (`/fm journal`, Shift-click on the minimap button):
  - **Fish:** every fish, trophy fish, container, and quest fish with your catches, places, skill
    range, recipes, Classic season, and catches by month; day/night tags with catches by server
    hour.
  - **Waters:** every water colored for your skill (or your best setup), with its fish.
  - **Recipes:** the 23 Classic recipes that use fish plus the ones read from your profession
    windows, with your stock and whether you know them.
  - **Gear:** poles, gear, lures, buff food, fishing ranks, and the glove enchant with tooltip
    bonuses, what you own (bags, bank, equipped), and your best setup.
