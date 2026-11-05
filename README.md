# Fishing Mastery

Fishing expectations and statistics addon for World of Warcraft: Forever. Licensed under GPL-3.0.

Research, plans, and stories live in the KB repository `dingelheimer/gg-ai-development-system`,
under `projects/wow-fishing-addon`.

## Repository Layout

| Path                    | Contents                                                        |
|-------------------------|-----------------------------------------------------------------|
| `FishingMastery/`       | The published addon (core tracker in development)               |
| `FishingMasteryProbe/`  | Unpublished test addon that records Forever API facts into a log; frozen ([docs](docs/probe.md)) |
| `spec/`                 | busted tests for the probe: pure logic, fake-UI window tests, and a boot test of all TOC files |
| `spec/fm/`              | busted tests for `FishingMastery/`, including a boot test of all its TOC files |
| `spec/fixtures/`        | Redacted event sequences from the live probe run, replayed by the tracker specs |
| `tools/`                | Developer scripts (fixture extraction from a probe log)         |
| `docs/`                 | Longer docs (probe reference)                                    |
| `probe-results/`        | Local copies of probe logs; git-ignored, never committed         |

## FishingMastery

The published addon. It shares no code at runtime with the probe: proven probe modules are
copied and adapted, and the probe folder is never loaded or referenced.

| File            | Responsibility                                                         |
|-----------------|------------------------------------------------------------------------|
| `Locale.lua`    | User-facing strings (`ns.L`), English fallback                         |
| `Options.lua`   | Every setting's default in one table; settings panel controls with ranges; the proxy the panel writes through (pure) |
| `LocaleStats.lua` | User-facing strings of the stats window                              |
| `Guard.lua`     | Runs every handler and slash command through `xpcall`; counts errors   |
| `Events.lua`    | Event bus: one frame, dispatch table, player-only unit events; events the client cannot register are skipped and listed |
| `Db.lua`        | Schema version, migration walk, repair of missing fields, migration snapshot (pure) |
| `Character.lua` | Character key `UnitGUID("player")` and the character entry           |
| `Attempt.lua`   | Attempt classifier: cast, message, and loot events to one outcome per attempt (pure) |
| `Context.lua`   | Cast context: server time, map, subzone text, fishing rank and modifier, lure enchant |
| `Loot.lua`      | Loot slots (item ID, quantity, quality) and loot source type and object ID |
| `Items.lua`     | Item cache: quality the loot window did not give, and name, icon, quality, sell price for the UI; uncached items requested once and filled in after `ITEM_DATA_LOAD_RESULT` |
| `Tracker.lua`   | Game events to classifier input (fishing spell, message names, channel length, fishing loot), end-of-attempt timer, outcome counts |
| `Records.lua`   | Saved cast record from an attempt; per-character subzone table (pure) |
| `Session.lua`   | Sessions: start, 15-minute idle end, logout, `/reload` resume, skill before and after, active time, last catch (pure) |
| `Codec.lua`     | Day chunk format: packs casts into `<day>\|<cast>;<cast>;…` strings and parses them back (pure) |
| `History.lua`   | Packing the open day, load check with quarantine, on-demand history iterator (pure) |
| `Totals.lua`    | Aggregates per outcome, day, map, map × lure, map × subzone, UTC hour, skill band, item (with hours and the dry-streak counter), bite time, and active time; rebuild from the history (pure) |
| `SummaryModel.lua` | Session summary: times, rates with ranges, failures, skill, best and new fish, vendor value, zone comparison (pure) |
| `HudModel.lua`  | HUD numbers and texts from the session, rank, lure, and item; count/grey rules and tooltip ranges (pure) |
| `StatsView.lua` | Stats window data: one character's totals or all characters merged (days, hours, subzones by text, lure groups, skill bands) (pure) |
| `StatsModel.lua` | Overview model: per-character and account numbers, favorite zone, session records (pure) |
| `StatsTables.lua` | Fish table: count, share with range, best zone and hour, first and last catch, dry streak and expected casts for uncommon and better items, sorting, quality filter; item text helpers (pure) |
| `ZoneTable.lua` | Zones table: zones with their subzones, casts, catches per hour, species, top items with shares (pure) |
| `OverviewTable.lua` | Overview lines (account totals, rates with ranges, favorite zone, records) and the character rows (pure) |
| `ChartModel.lua` | Chart math: nice axis scales, histogram bins, bar layout, x label step, line chart range and placement (pure) |
| `FailureTable.lua` | Failures tab: outcome rows with rates of fair and hooked casts, getaway rate by skill band, early clicks by click time (pure) |
| `BiteTable.lua` | Bite times tab: groups per zone and lure state with median and quartiles, histogram chart (pure) |
| `SessionTable.lua` | Sessions tab: sortable session rows with rates in the tooltip (pure) |
| `SkillScan.lua` | Skill tab history scan in steps: first cast and catches per fishing rank; open casts added per result (pure) |
| `SkillModel.lua` | Skill numbers: rank over time, catches per skill point with range, forecast to the next rank cap and to 300 (pure) |
| `SkillTable.lua` | Skill tab texts, rank line chart, catches-per-point bars by rank band (pure) |
| `CompareTable.lua` | Compare tab: groups (lure, day/night, zone, character), rates with the Newcombe difference, median bite time (pure) |
| `MinimapModel.lua` | Minimap button position for an angle (round minimap or `GetMinimapShape` shapes), drag angle, saved angle (pure) |
| `TooltipModel.lua` | Item tooltip line "caught Nx (best: zone)" from one item total (pure) |
| `CalendarModel.lua` | Calendar heatmap: 53 weeks of days, rows Monday to Sunday, color levels by catches (pure) |
| `Stats.lua`     | Statistics engine: Wilson, Byar, Newcombe ranges, expected casts, chance of at least one, bite quartiles, active time, blending; rate builders with fair and hooked casts and the display thresholds (pure) |
| `Export.lua`    | Export text: versioned pages with a checksum, per character (sharing) or all (backup) (pure) |
| `Import.lua`    | Import: full validation, then merge of missing days (pure) |
| `Backup.lua`    | Rolling snapshots of totals and settings; reload reminder rule (pure) |
| `Synthetic.lua` | Deterministic synthetic casts for the stress test and the storage specs (pure) |
| `Stress.lua`    | Developer storage test: test entry filled in steps, line test chunks, load measurements (pure) |
| `Capture.lua`   | Raw capture ring buffer; aura spell IDs and loot source readers |
| `CastLog.lua`   | Saves each attempt as a cast record, counts sessions and totals, detects skill-ups, packs at logout and day change, runs the load check, ends idle sessions on time (session-end listeners) |
| `Frames.lua`    | Frame helpers: template fallback, saved position, movable, guarded buttons |
| `TextWindow.lua` | Export (read-only pages, Select all) and import (paste box, Import button) window |
| `Confirm.lua`   | Confirmation dialog (backup restore) |
| `UiTest.lua`    | UI check test window: one line, one bar, an item icon, a 3-row scroll list, two tabs, "Open settings" (dev flag only) |
| `UiCheck.lua`   | UI API check: each statistics UI API missing, ok, or error; results in `dev.ui` (dev flag only) |
| `Commands.lua`  | `/fm` command registry and help                                        |
| `DataCommands.lua` | `/fm backup`, `/fm export`, `/fm import`, `/fm reminder` |
| `Hud.lua`       | HUD frame: shown from the first cast to the session end, lure tick, tooltip, `/fm hud` |
| `Summary.lua`   | Session summary window or chat block at the idle end, `/fm summary` |
| `StatsList.lua` | Table widget of the stats window: sort buttons or header labels over a ScrollBox list, grey cells, row tooltips |
| `BarChart.lua`  | Bar chart widget: pooled bars, range marks, grid and axis labels, value and x labels, hover tooltip per bar |
| `LineChart.lua` | Line chart widget: pooled `CreateLine` segments (squares without it), grid and axis labels, hover tooltip per point |
| `Heatmap.lua`   | Calendar heatmap widget: 53 × 7 day cells with weekday labels and a tooltip per day |
| `StatsWindow.lua` | Stats window `/fm stats`: tab, scope, sort, filter, and bite group state; draws only the shown tab; redraws when item names load and while the history is counted |
| `StatsFrame.lua` | Stats window layout: movable frame, status line, scope button, one panel per tab, 8 tab buttons |
| `StatsTabs.lua` | Build and draw of the Overview, Fish, and Zones tabs |
| `FailureTabs.lua` | Build and draw of the Failures, Bite times, and Sessions tabs |
| `SkillTabs.lua` | Build and draw of the Skill tab (history scan with a progress line) and the Compare tab |
| `Dev.lua`       | `/fm dev` developer tools, load time measurement, raw capture events (dev flag only) |
| `MinimapButton.lua` | Own minimap button: drag around the edge (angle per character), left click stats window, right click settings, session tooltip, hide setting |
| `SettingsPanel.lua` | Settings panel (Settings API): one checkbox or slider per setting, `/fm settings`, `/fm minimap` |
| `ItemTooltip.lua` | Item tooltip post-call: adds the line for items this character caught, one lookup per tooltip, tooltip setting |
| `Compartment.lua` | Addon compartment handler `FishingMastery_OnAddonCompartmentClick` (TOC `AddonCompartmentFunc`), run through the guard; opens or closes the stats window |
| `Core.lua`      | Event frame, setup on `ADDON_LOADED`, character entry on `PLAYER_LOGIN`, slash command |

### Saved Data

- `FishingMasteryDB` (account-wide): `schemaVersion`, `chars[UnitGUID("player")]` with
  `name` and `part` (the two name parts, display only), `firstSeen`, `lastSeen` (server time),
  and `settings`. `GetRealmName()` is never part of the key.
- Per character entry, history: `days` (packed day chunks, oldest first, append-only), `casts`
  (the open day's records, packed at logout and when a cast of a later day arrives),
  `quarantine` (chunks that failed the load check, kept unchanged), `totals`, `subzones`
  (subzone texts; records store the index), `sessions`, `fishingRank` (last known rank), and
  `fishingMax` (last known rank cap).
- Cast record: `t` (server time at the cast), `map` (`uiMapID`), `sub` (subzone index), `rank`,
  `mod` (`skillModifier`), `lure` (enchant ID), `out` (outcome), `bite` (tenths of a second,
  catches), `click` (tenths of a second after the channel start, early clicks and getaways),
  `auto` (auto loot), `loot` (`{ id, qty, q }` per item slot), `srcType` and `srcId`
  (loot source, e.g. `GameObject` 35591 = the bobber). Empty fields are left out.
- Session: `start`, `last` (last cast), `ended` and `endReason` (`idle` or `logout`), `casts`,
  `catches`, `counts` per outcome, `zones` (map IDs), `skillStart` and `skill` (rank at the first
  cast and the latest rank), `active` (seconds: gaps between casts, each at most 60 s; the time
  since the last cast is added when shown), `lastItem` and `lastBite` (latest catch), `items`
  (`[itemID] = quantity` caught in the session). A session ends 15 minutes after its last cast or at logout; a
  `/reload` within 15 minutes continues it.
- **Day chunk:** `<day>|<cast>;<cast>;…`, day = `floor(serverTime / 86400)`, at most 4,000
  characters (a busy day gets several chunks). A cast is comma-separated integers in a fixed
  order; new fields are only appended (or use a field that was always empty for that outcome),
  and trailing empty fields are dropped:

  | # | Field   | Meaning                                               | Empty means |
  |---|---------|-------------------------------------------------------|-------------|
  | 1 | dt      | Seconds since the previous cast in the chunk (first: seconds into the day) | — |
  | 2 | out     | 0 unknown, 1 catch, 2 getaway, 3 early click, 4 timeout, 5 cancel, 6 invalid target | — |
  | 3 | time    | Catches: bite time in tenths; early clicks and getaways: click time in tenths (saved since Story 3.4) | none |
  | 4-6 | item, qty, q | First loot slot (catches)                     | same as the previous catch |
  | 7-11 | map, sub, rank, mod, lure | Cast context                    | same as the previous cast |
  | 12-14 | srcType, srcId, auto | Loot source (1 GameObject, 2 Creature, 3 Item, 9 other), auto loot 1/0 (catches) | same as the previous catch |
  | 15 | extra  | Further loot slots `id:qty:q/id:qty:q` (catches)       | none |

  `-` stores "none" in a repeating field. Decoding parses the text field by field and never
  runs `loadstring`. 200,000 synthetic casts take 12.1 bytes per cast (real casts ~15).
- **Load check:** after login every chunk is decoded once, 10 chunks per frame (decoding all at
  login took 1.4 s for 200,000 casts on live); a broken chunk moves to `quarantine` (reported once
  in chat when the check ends) and the rest loads. Tracking works while the check runs.
  Statistics read the history through `History.Iterate`, which decodes one chunk at a time.
- **Totals** (`version = 4`), updated with every cast; `map` is the `uiMapID` or 0:

  | Table      | Shape |
  |------------|-------|
  | `outcomes` | `[outcome] = count` |
  | `days`     | `[day] = { casts, catches }` |
  | `maps`     | `[map] = { casts, catches, items = { [itemID] = quantity } }` |
  | `zones`    | `[map].on / .off` (lure or not) `= { casts, outcomes, items = { [itemID] = quantity }, bites = { [tenths] = catches }, clicks = { [tenths] = early clicks } }` |
  | `hours`    | `[UTC hour 0-23] = { casts, outcomes }` (shifted to the realm or local hour when shown) |
  | `skills`   | `[map][band] = { hooked, getaways }`, band = lower bound of 5 points of rank + modifier |
  | `items`    | `[itemID] = { n (catches with it), qty, first, last (server time), best (map with the most), hours = { [UTC hour] = catches }, fair (fair casts counted at its last catch) }` |
  | `active`   | `[map] = seconds`: Σ min(gap to the next cast, 60 s), 60 s for the latest cast |
  | `subs`     | `[map][sub] = { casts, outcomes, items = { [itemID] = catches with it }, active }`, sub = subzone index or 0 (none); the same active time split per subzone |
  | `last`     | `{ t, map, sub }` of the latest cast (for the active time) |

  Hooked = catch + getaway. `/fm rebuild` counts everything again and says whether the result
  equals the live totals. Totals of another version (after the schema 2 update, a new totals
  version such as 3 for the early-click times or 4 for subzones and item hours, or a restored old snapshot) are counted again after login, in the same steps as the load check (one decode for
  both); `/fm status` says "Counting your history" until it is done, and casts during the count
  are counted once. 200,000 synthetic casts give about 86 KB of totals in the saved file (8 maps, 12 items;
  version 4 adds about 20 % for subzones and item hours: the spec estimate goes from 76,076 to 91,269
  characters);
  on live the load check with the rebuild took 2.3 s in 80 steps (longest 48 ms).
- `FishingMasteryCharDB` (per character): `schemaVersion` and `ui` (UI layout only: window and
  HUD positions; `ui.stats` is the stats window, `ui.minimap.angle` the minimap button, degrees,
  default 220).
- `FishingMasteryDB.settings` (account; every default in `Options.DEFAULTS`): `hud` = `enabled`
  (default on), `locked`, `scale` (0.5-2, default 1), `style` (`full` or `text`);
  `summary.style` = `window` (default) or `chat`; `minimap.shown` (default on);
  `tooltip.shown` (item tooltip line, default on);
  `reloadReminder` (default on); `thresholds` = `countBelow` (5-30, default 10), `greyBelow`
  (10-100, default 30), `activeCap` (the idle cap T, 30-120 s, default 60).
- **Idle cap T:** totals keep the T they were counted with (`totals.cap`, left out for 60 s). A
  new T applies at the next login: totals of another T are counted again in steps (as after an
  update); past sessions keep the active time they were counted with.
- **Migrations:** on `ADDON_LOADED`, `Db.MIGRATIONS[v]` upgrades schema `v` to `v + 1`. Before
  the first step, the tables a step names are copied into `migrationSnapshot`; a failing step
  restores them and keeps the old version. The snapshot is removed at the first later login
  that loads without Lua errors. A schema newer than the addon is left unmigrated, with a warning.
  Schema 2 marks every character's totals stale (the snapshot holds `chars`, so the saved file is
  about twice as large until the next clean login).
- **Repair:** missing or invalid top-level tables are recreated; character entries that are not
  tables are dropped.

### Commands

| Command                    | Effect                                                       |
|----------------------------|--------------------------------------------------------------|
| `/fm` or `/fishingmastery` | Help: version, commands, characters with saved data, Lua error count and the last 3 errors |
| `/fm help`                 | Same as `/fm`                                                |
| `/fm backup list`          | Snapshots of the last 3 days (newest first) |
| `/fm backup restore <n>`   | Asks first, then puts snapshot n back (totals and settings; the cast history is not changed) |
| `/fm export`               | This character's history as copyable text, without character ID or names (for sharing) |
| `/fm export all`           | Full backup of every character, including character IDs and names (keep it private) |
| `/fm import`               | Paste one export page and press Import; days you already have are skipped |
| `/fm reminder on\|off`     | Reload reminder after every 2 hours of fishing in one session (on by default) |
| `/fm hud show\|hide`       | Turns the HUD on (shown now, so it can be placed) or off |
| `/fm hud lock\|unlock\|reset` | Locks or unlocks dragging; reset puts it back at the top center with scale 1 |
| `/fm hud scale <0.5-2>`    | HUD size                                                     |
| `/fm hud style full\|text` | Five lines, or one line of text                              |
| `/fm summary`              | Summary of the open session, or of the last one (also shown when a session ends after 15 minutes without a cast) |
| `/fm summary window\|chat` | Where summaries appear: a small window (default) or your chat frame |
| `/fm stats`                | Statistics window, see below (also the minimap button's left click and the addon compartment entry) |
| `/fm settings`             | Settings panel (also the minimap button's right click); lists any control the client could not show |
| `/fm minimap show\|hide`   | Shows or hides the minimap button |
| `/fm rebuild`              | Counts the totals again from the whole history, prints casts, catches, and days, and says whether they equal the live totals |
| `/fm status`               | "Counting your history" while the totals are counted after login; current session: length, casts, catches, count per failure outcome, fishing skill before and after, and the last outcome (with bite time for a catch, click time for an early click or getaway) |

### Stats Window

`/fm stats` opens a movable window (position saved per character) with 8 tabs. It reads the
totals and the session records; only the Skill tab reads the history, in steps. It draws only the
shown tab. Ranges are in the row tooltips; values from small samples are grey (counts only below
10).

- **Overview:** all characters' casts, catches, fishing days, success rate and catches per hour
  with ranges, active time, species, favorite zone (most catches); records (most catches in a
  session, most catches per hour in a session with at least 30 fair casts, longest session);
  one row per character of this account; a calendar heatmap of the last 53 weeks (UTC days of
  the server time, brighter = more catches; date, casts, and catches in each day's tooltip).
- **Fish:** every item with catches, share of catches, best zone, best hour (realm time), first
  and last catch; for uncommon and better items the dry streak (fair casts since the last one)
  and the expected casts per item. Click a header to sort, again to flip the order; the quality
  button filters.
- **Zones:** every zone (most casts first) and its subzones: casts, catches per hour, species,
  the top 3 items with their shares; all items with ranges in the tooltip.
- **Failures:** every outcome with its count and rates (of fair casts; catches and getaways also
  of hooked casts; cancels, invalid targets, and unknown attempts are counts only); bar charts of
  the getaway rate by 5-point band of effective skill (rank + modifier, all zones together) with
  95 % range marks, and of early clicks by click time (1-second bands).
- **Bite times:** histogram (1-second bins up to 30 s) of all zones or of one zone and lure state
  (the button steps through them), median and quartiles; a table of every group.
- **Sessions:** every session (newest first) with date, character, zone, active time, casts,
  catches, and skill change; click a header to sort. Rates with ranges in the tooltip.
- Charts: bar values above the bars when they fit, the numbers of every bar in its tooltip, grey
  bars for small samples.
- **Skill** (this character): reads the history 10 chunks per frame with "Reading your history"
  and a percentage in the status line, then later only the new chunks. Line chart of the rank
  over time (the first cast at each rank); catches per skill point over the last 10 points with
  the 95 % range (skill-ups per catch, Wilson, inverted); catches since the last skill-up; the
  forecast to the next rank cap (the saved cap, else the next step of 75) and to 300 in catches
  and active time at that pace; bars of catches per point by 25 ranks. Left out of the pace: the
  first tracked rank, the current one, and ranks 75, 150, and 225 (catches there may have been
  made at the cap).
- **Compare:** two groups side by side: lure on vs off, day (06:00-17:59 realm time) vs night,
  zone A vs B, or character A vs B (the buttons pick A and B). Casts; success, getaway,
  early-click, and timeout rates; the difference A - B in percentage points with its Newcombe
  range in the tooltip, "clear difference" only when the range excludes 0 (no p-values); the
  median bite time without a range.
- The scope button switches Fish, Zones, Failures, Bite times, Sessions, and Compare (except
  characters) between this character and all characters (dry streaks only for one character). The status line counts the characters whose totals are from
  an older version until they log in once.

### Settings and Minimap Button

- **Settings panel** (game menu Options > AddOns > Fishing Mastery, `/fm settings`, or a right
  click on the minimap button): HUD on/off, lock, one text line, scale; summary in the chat;
  minimap button; item tooltip line; reload reminder; the count-only and grey sample sizes; the idle cap T. Changes
  apply at once (T at the next login). Checkboxes use the Settings API confirmed on live; sliders
  appear only when the client has `Settings.CreateSlider`, else `/fm settings` names them.
- **Minimap button** (own, no libraries): drag it around the minimap edge (square minimaps
  follow their corners); the angle is saved per character. Left click opens or closes the stats
  window, right click opens the settings; the tooltip shows the open session's rates. Hide it in
  the settings or with `/fm minimap hide`.
- **Addon compartment:** the Fishing Mastery entry opens or closes the stats window.
- **Item tooltip line:** items this character caught show "Fishing Mastery: caught 37x (best:
  Darkspear Strand)" on every item tooltip (bags, vendor, links); one lookup in the item totals,
  never a history scan. Other lines are never changed. Off with the setting "Item tooltip line".

### Attempt Detection

Only channels of the fishing spell (7620, or a spell with the same name) start an attempt.

| Outcome          | Signal                                                                  |
|------------------|-------------------------------------------------------------------------|
| `catch`          | Fishing loot (`IsFishingLoot()`) at `LOOT_READY` / `LOOT_OPENED`        |
| `getaway`        | `UI_INFO_MESSAGE` named `ERR_FISH_ESCAPED`, before or after the stop     |
| `early_click`    | `UI_INFO_MESSAGE` named `ERR_FISH_NOT_HOOKED`                            |
| `timeout`        | Channel stop no earlier than 0.5 s before the channel end, no loot or message |
| `cancel`         | Earlier stop, no loot or message (moving, jumping, recasting)            |
| `invalid_target` | Fishing `UNIT_SPELLCAST_FAILED` and, within 1 s, a generic spell failure (`ERR_SPELL_FAILED_S`, type 57) whose text equals `SPELL_FAILED_NOT_FISHABLE` or `SPELL_FAILED_TOO_SHALLOW`; no channel |
| `unknown`        | No stop within 90 s, a new cast before the stop, or no channel length   |

- Message names come from `GetGameMessageInfo`; a missing or generic name is replaced by the
  global string whose text equals the message text. No English text is compared.
- An attempt ends 1.5 s after the stop, at `LOOT_CLOSED` after the stop, or when a new cast
  starts. A failed recast or `UNIT_SPELLCAST_FAILED_QUIET` inside a running channel is ignored.
- Bite time = first fishing loot event − channel start, in tenths of a second.
- Click time (early click, getaway) = first `ERR_FISH_NOT_HOOKED` or `ERR_FISH_ESCAPED` message −
  channel start, in tenths of a second. A click right after the splash also gives "No fish are
  hooked"; the times let a later story tell such late clicks from clicks before the bite.
- Each finished attempt is saved as a cast record (see Saved Data); the context is read at the
  cast start (or at the failure message), the loot at the first fishing loot event.
- Fixtures: `luajit tools/extract_live_attempts.lua probe-results/<log>.lua
  spec/fixtures/live_attempts.lua`, then `stylua .`.

### Your Data

- **Where it is:** the client writes everything on `/reload`, logout, or quit to
  `World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\FishingMastery.lua`
  (all characters) and `...\<realm>\<character>\SavedVariables\FishingMastery.lua` (window
  positions only). A crash loses the casts since the last save, so `/reload` now and then on long
  sessions; the addon reminds you after every 2 hours of fishing (`/fm reminder off` stops it).
- **Client backup:** the client keeps the previous save next to it as `FishingMastery.lua.bak`.
  To use it, quit the game and rename it to `FishingMastery.lua`.
- **Snapshots:** at the first login of each day the addon keeps a copy of the totals and settings
  (last 3 days, `/fm backup list`, `/fm backup restore <n>`). The cast history itself is stored
  append-only and is never rewritten, so it needs no copy; `/fm rebuild` recounts the totals from
  it. Damaged history parts are set aside in a quarantine instead of being deleted.
- **Export:** `/fm export all` shows the whole history as text pages (each at most 200,000
  characters, never splitting a day). Copy every page into a text file you keep outside the game.
  `/fm import` adds the days of a page that you do not have yet; pages can be imported in any
  order and twice without harm, and an invalid page changes nothing. Format: `FMX!1!<scope>!<page>!
  <pages>!<checksum>`, then `C!<character ID>!<name>!<second part>!<subzones>` and one
  `D!<day chunk>` per chunk; a sharing export (`/fm export`) writes `-` for ID and names. The
  text uses `!` where the saved data uses `|`, because the game's edit boxes treat `|` as an
  escape character (and double it on paste); the import accepts both.
- **New PC or reinstall:** copy the whole `WTF` folder (it also holds your game settings), or
  import your export pages.

### Developer Tools

Only active while the dev flag is set: `/run FishingMasteryDB.settings.dev = true` (and `= nil`
to turn it off). Without the flag `/fm dev` is an unknown command and nothing below runs. All test
data lives in `FishingMasteryDB.dev`, never in a character entry, so exports, backups, and totals
do not see it.

| Command                      | Effect                                                       |
|------------------------------|--------------------------------------------------------------|
| `/fm dev stress [n]`         | Writes n synthetic casts (default 200,000, at most 500,000) into `dev.stress` in steps of 5,000 per frame, packed into day chunks like live casts |
| `/fm dev lines`              | Writes one chunk of about 4,000 and one of about 60,000 characters into `dev.lines` |
| `/fm dev load`               | Lists the last 10 load measurements                          |
| `/fm dev clear`              | Removes `dev.stress` and `dev.lines`                         |
| `/fm dev capture [on\|off\|clear]` | Raw capture switch; without an argument, a summary of the captured aura IDs and loot sources |
| `/fm dev ui`                 | UI API check: opens the test window, prints one line per API (ok, missing, error with the text), and keeps the results in `dev.ui` |

- **Load measurement:** `PLAYER_LOGOUT` (also on `/reload`) saves `GetTimePreciseSec()` in
  `dev.logoutAt`; after the reload the addon prints the time from it to its `ADDON_LOADED`, the
  tracker start, and the stepped load check of `dev.stress` (total time, steps, longest step,
  size; the check also rebuilds the test totals), and stores them in `dev.loads`. A second line
  gives the size of the rebuilt totals in the saved file and their key counts. The line test chunks are decoded and compared after each
  reload.
- **Raw capture** (`dev.capture`, ring buffer of 2,000 entries): at a fishing cast start
  `{ k = "cast", t, mod, auras = { spell IDs } }`, at fishing loot `{ k = "loot", t, src =
  { "GameObject:35591", ... } }`. Only spell IDs, GUID types, and object IDs are kept: no names,
  no aura casters, no player GUIDs.

- **UI API check** (`dev.ui = { at, results = { { name, status, detail, note } }, openSettings,
  tooltipSeen, compartmentClicks }`): checks `Frame:CreateLine`, color texture bars, the Settings
  API (vertical layout category, test checkbox, add-on category, open), the ScrollBox list
  utilities, `C_Item.GetItemIconByID`, `C_Item.GetItemQualityColor`, `ITEM_QUALITY_COLORS`, the
  item tooltip post-call, tab templates with `PanelTemplates`, `GetMinimapShape`, and the addon
  compartment. The test settings category "Fishing Mastery (UI check)" (checkbox value in
  `dev.uiSetting`) and the tooltip post-call stay registered until `/reload`; the tooltip line
  shows only while the dev flag is set.

## FishingMasteryProbe

The frozen Epic 1 API probe (files, log format, guided run, commands, export) is documented in
[docs/probe.md](docs/probe.md).

## Development

Tools: LuaJIT or Lua 5.1, [busted](https://lunarmodules.github.io/busted/),
[luacheck](https://github.com/lunarmodules/luacheck), [StyLua](https://github.com/JohnnyMorganz/StyLua).

```powershell
stylua .      # format
luacheck .    # zero warnings required
busted        # run all specs in spec/
```

On Windows the tools install without admin rights:
`scoop install luajit stylua luarocks`, then
`luarocks --lua-version=5.1 --lua-dir=<luajit dir> install busted` and `... install luacheck`
(run from PowerShell).

`.luacheckrc` turns the LuaJIT JIT compiler off for luacheck: with it on, full-tree runs crashed
with a segfault in most attempts, while the interpreter is stable.

### Install for In-Game Testing

Link each addon folder into the game client with a junction (no admin rights needed):

```bash
cmd //c mklink /J "<WoW>\_forever_\Interface\AddOns\FishingMastery" "<repo>\FishingMastery"
cmd //c mklink /J "<WoW>\_forever_\Interface\AddOns\FishingMasteryProbe" "<repo>\FishingMasteryProbe"
```

The probe is only needed for API tests; Fishing Mastery runs without it.

In game, `/console scriptErrors 1` shows Lua errors and `/reload` loads code changes.
