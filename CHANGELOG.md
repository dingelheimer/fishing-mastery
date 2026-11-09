# Changelog

## Unreleased

- Changed: every tooltip of the addon uses short labels and values in the game's style. The item
  tooltip shows "Fishing Mastery" with "caught N" and your best water; the minimap button shows
  the session, your Fishing skill, and the click hints; chart bars and calendar days list their
  numbers as pairs. Longer explanations (settings, helpers, comparisons) appear while Shift is
  held. The fish details in the Journal are label and value pairs with the places and recipes as
  small tables instead of a block of sentences.
- Fixed: in places the game reports as the continent, such as the cave outside Wailing Caverns,
  the HUD named "Kalimdor" and knew no risk or fish; new casts there were saved under Kalimdor.
  Both now use the zone shown on screen (The Barrens). Casts saved before stay as they are.
- Changed: statistics and journal are pages of one Fishing Mastery window with side tabs on its
  right edge, like the Professions window. It opens on the last page, moves by the title, and
  closes with Escape. Window positions saved before this version are reset once.
- Changed: the HUD is a card in the tooltip look: the water with a risk tag, the skill bar with a
  mark at your skill with lure and gear, the lure with a timer or the one that would help, three
  headline numbers, the last catch, and the water's fish as icons. Its tooltip lists short labels
  and values with the explanations behind Shift. The compact layout is one line. Two buttons on
  the HUD switch between card and compact and stop the session now.
- New: a Settings page in the window with every setting grouped, a live HUD preview, the data
  buttons, and Defaults. New HUD settings: layout (card or compact; your old style carries over)
  and opacity. The game's Options entry now opens this page. `/fm hud style` is now
  `/fm hud layout card|compact`.
- New: a Helpers page in the window. Turn each helper on or off, see whether it is ready or
  what blocks it, bind the casting key in place, see what the smart lure would do in this water,
  and this login's counts. The helpers left the game's settings panel; your settings are kept.
- Changed: the Journal tabs show item icons and quality colors, season and night tags, a
  progress bar in the page header (every group in its tooltip), dropdown-styled filters, and
  recipe and gear tooltips as short labels and values.
- Changed: the Fish tab has six columns with item icons, quality colors, and season or night
  tags; the hour and dates moved into the row tooltip. Every table's row tooltip lists short
  labels and values with the range in grey brackets; explanations appear while Shift is held.
- Changed: the Statistics Overview shows your Fishing skill bar, four headline numbers with their
  likely range, where your casts end, and your five most caught items, for this character or all
  characters. The records and the fishing days calendar moved to the Sessions tab.
- Changed: tables have a gold header bar with a sort arrow on the sorted column, striped rows,
  and a highlight on the row under the mouse (first step of the interface overhaul).
- New: `/fm contribute` shows your catch counts per area and skill band to share, with a random
  token and no names, IDs, or times.

## 1.0.0

First stable release: the tracker, statistics, zones, and journal of the beta, plus the helpers.
Every helper is off by default, and the casting key has no key until you set one.

- New: casting key. Bind a key to "Cast Fishing" (Key Bindings, AddOns, Fishing Mastery); the
  settings panel has a Helpers section that says where.
- New: double right-click casting (setting "Double right-click casts Fishing", off by default).
  With a fishing pole in hand, a double right-click into the world casts Fishing; right-clicks on
  units and windows, camera turning, and combat stay as they are. The setting's tooltip warns when
  Luredon or Classic Fishing Companion is loaded.
- New: smart lure (setting "Apply a lure first", off by default). The casting key and the double
  right-click put on the cheapest lure in your bags that stops getaways in this water (your best
  one if none does), and none when your skill is enough or a lure is running. The HUD tooltip names
  the lure that would help, with the setting on or off.
- New: louder splash (setting, off by default): sound effects at full volume, music and ambience
  off while a fishing pole is equipped; your own volumes are restored afterwards and at logout.
- New: hide the interface while fishing (setting, off by default), like Alt+Z when the line goes
  out; it comes back on movement, combat, death, a target change, a whisper, a dialog, a loot
  window without auto loot, or when the pole leaves your hand. Catches show at the top of the
  screen while it is hidden.
- New: `/fm helpers` shows what the helpers did since login and their settings.
- Changed: the version in `/fm` no longer shows the tag's leading "v" ("1.0.0").
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
