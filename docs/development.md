# Fishing Mastery - Development Reference

The full reference for developers: repository layout, every module, the saved data format,
commands in detail, the data builds, tests, and developer tools. Players start with the
[README](../README.md). Licensed under GPL-3.0.

Research, plans, and stories live in the KB repository `dingelheimer/gg-ai-development-system`,
under `projects/wow-fishing-addon`.

## Repository Layout

| Path                    | Contents                                                        |
|-------------------------|-----------------------------------------------------------------|
| `FishingMastery/`       | The published addon (core tracker in development)               |
| `FishingMasteryProbe/`  | Unpublished test addon that records Forever API facts into a log; frozen ([docs](probe.md)) |
| `spec/`                 | busted tests for the probe: pure logic, fake-UI window tests, and a boot test of all TOC files |
| `spec/fm/`              | busted tests for `FishingMastery/`, including a boot test of all its TOC files |
| `spec/fixtures/`        | Redacted event sequences from the live probe run, replayed by the tracker specs |
| `tools/`                | Developer scripts: fixture extraction from a probe log, zone and journal data fetch and build, privacy scan, contribution checker |
| `tools/data/`           | Trimmed, pinned copies of the zone and journal data sources (input of both builds) |
| `docs/`                 | This development reference, the probe reference, the CurseForge page text, the logo (`images/`, drawn by `tools/draw_logo.py`, needs Pillow) |
| `.github/workflows/`    | `check.yml`: the quality gates on every push and pull request; `package.yml`: a dry run of the release zip (started by hand); `release.yml`: upload on a version tag |
| `.pkgmeta`, `CHANGELOG.md` | Packager configuration (only `FishingMastery/`, `LICENSE`, and the changelog go into the zip) and the release notes |
| `probe-results/`        | Local copies of probe logs; git-ignored, never committed         |

## FishingMastery

The published addon. It shares no code at runtime with the probe: proven probe modules are
copied and adapted, and the probe folder is never loaded or referenced.

| File            | Responsibility                                                         |
|-----------------|------------------------------------------------------------------------|
| `Locale.lua`    | User-facing strings (`ns.L`), English fallback                         |
| `Options.lua`   | Every setting's default in one table, the HUD layout reader (an old `style` read as its layout), reads, defaults, and validated writes (pure) |
| `OptionsControls.lua` | The controls in page order: checkbox, slider, or choice, range, getter and setter, and the page that shows them (pure) |
| `LocaleStats.lua` | User-facing strings of the Statistics page                           |
| `LocaleJournal.lua` | User-facing strings of the Journal page |
| `LocaleHelpers.lua` | User-facing strings of the helpers (casting key, the helpers' long explanations, smart lure, catch line) |
| `LocaleUI.lua` | User-facing strings of the UI overhaul (style kit; later the main window and its pages) |
| `Data/Zones.lua` | Generated zone data `ns.Zones`: Classic loot lists, base skills, area placement (see Zone Data) |
| `Data/Journal.lua` | Generated journal data `ns.Journal`: item groups, Classic recipes that use fish, fishing gear, lures, buff food, fishing ranks, the glove enchant, season rules (see Journal Data) |
| `Guard.lua`     | Runs every handler and slash command through `xpcall`; counts errors   |
| `Events.lua`    | Event bus: one frame, dispatch table, player-only unit events; events the client cannot register are skipped and listed |
| `Db.lua`        | Schema version, migration walk, repair of missing fields, migration snapshot (pure) |
| `Character.lua` | Character key `UnitGUID("player")` and the character entry           |
| `Attempt.lua`   | Attempt classifier: cast, message, and loot events to one outcome per attempt (pure) |
| `Context.lua`   | Cast context: server time, map (the zone map: where the client reports a map the zone data does not know, such as the continent in the cave outside Wailing Caverns, the zone map with the name of the zone shown on screen), subzone text, fishing rank and modifier, lure enchant; area name, instance ID, current area; the client name of Fishing; a fishing pole in the main hand |
| `Area.lua`      | Area lookup: instance ID, UI map, and subzone text to an area of the zone data; subzone names from `C_Map.GetAreaInfo`, cached per zone (pure) |
| `Loot.lua`      | Loot slots (item ID, quantity, quality) and loot source type and object ID |
| `Items.lua`     | Item cache: quality the loot window did not give, and name, icon, quality, sell price for the UI; uncached items requested once and filled in after `ITEM_DATA_LOAD_RESULT` |
| `Tracker.lua`   | Game events to classifier input (fishing spell, message names, channel length, fishing loot), end-of-attempt timer, outcome counts |
| `Records.lua`   | Saved cast record from an attempt; per-character subzone table (pure) |
| `Session.lua`   | Sessions: start, 15-minute idle end, logout, the stop button, `/reload` resume, skill before and after, active time, last catch (pure) |
| `Codec.lua`     | Day chunk format: packs casts into `<day>\|<cast>;<cast>;…` strings (pure) |
| `CodecDecode.lua` | Parses a day chunk back into casts, field by field, without `loadstring` (pure) |
| `History.lua`   | Packing the open day, load check with quarantine, on-demand history iterator (pure) |
| `Season.lua`    | Classic season windows (in season now, realm time), the realm hour offset, catches per realm hour; date helpers (pure) |
| `Totals.lua`    | Aggregates per outcome, day, map, map × lure, map × subzone, UTC hour, skill band, item (with hours, months, and the dry-streak counter), bite time, and active time; rebuild from the history (pure) |
| `SummaryModel.lua` | Session summary: times, rates with ranges, failures, skill, best and new fish, vendor value, zone comparison; the text lines of the chat style (pure) |
| `SummaryCardModel.lua` | The summary card (Story 10.5): water and active time, skill line, three numbers between dividers, pairs (casts, outcomes, vendor value), the Caught table (at most 5 rows), the clear zone comparison, drawn into a `DetailPane` (pure) |
| `Getaway.lua`   | Getaway risk: Classic model at an effective skill and base, own rate per resolved area and skill band with its range, and the comparison (pure) |
| `HudModel.lua`  | HUD numbers from the session, rank, lure, and item; short formats; count/grey rules (pure) |
| `HudCardModel.lua` | The HUD card of Draft 5 (water and risk tag, skill bar with skill-ups and the effective-skill mark, risk line, lure row with timer or suggestion, three numbers with "%" as a unit, last catch, the water's fish, the green getaway-free tick), the compact line, the HUD tooltip of Draft 6, and the Settings preview sample (pure) |
| `StatsView.lua` | Stats window data: one character's totals or all characters merged (days, hours, subzones by text, lure groups, skill bands) (pure) |
| `StatsModel.lua` | Scope model: per-character and merged numbers, favorite zone, session records, calendar days, the merged view (pure) |
| `JournalModel.lua` | Journal model: entries of the four journal groups with own catches (account-wide or one character), places, base and no-getaway skill, recipes, season, quest-only flag, new-in-Forever items by Forever class, progress per group, gear for a skill gap (pure) |
| `GearModel.lua` | Gear tab model: poles, other gear, lures, buff food, fishing ranks, enchants with bundled and tooltip bonus, needs, source, and where the player has them; the equipped bonus against the skill modifier; the best setup per slot plus the best lure in the bags; the tooltip number parser (pure) |
| `RecipeModel.lua` | Journal recipes: the bundled recipes merged with the ones read in game, the account store of read recipes (journal items only, capped), buff food, recipes per fish (pure) |
| `RowTip.lua` | Row tooltip pieces for the tables: item title in its quality color, rates and rates per hour with grey ranges, Shift explanations (pure) |
| `StatsTables.lua` | Fish table (Draft 2): name with icon, quality color, and season or night tag; caught, share, about every, dry streak, best water; hour and dates in the row tooltip; sorting, quality filter, kinds line; item text helpers (pure) |
| `ZoneRef.lua`   | Classic reference next to own catches: own group per area, comparison rows (Classic estimate, season or quest flag, own share, fish not in the Classic data), note, the count of the list's fish still missing (pure) |
| `ZoneTable.lua` | Zones table: zones with their subzones (one row per resolved subzone area, else per text), casts, catches per hour, species, top items with shares; rows carry the area ID (pure) |
| `OverviewTable.lua` | Record lines of the Sessions tab (pure) |
| `OverviewModel.lua` | Overview page: skill bar, four headline numbers with ranges and grey rules, outcome rows, the five most caught items, the characters of the Catches tooltip (pure) |
| `ChartModel.lua` | Chart math: nice axis scales, histogram bins, bar layout, x label step, line chart range and placement (pure) |
| `FailureTable.lua` | Failures tab: outcome rows with rates of fair and hooked casts, getaway rate by skill band or by skill above the water's base with the Classic model, early clicks by click time (pure) |
| `BiteTable.lua` | Bite times tab: groups per zone and lure state with median and quartiles, histogram chart (pure) |
| `SessionTable.lua` | Sessions tab: sortable session rows with rates in the tooltip (pure) |
| `SkillScan.lua` | Skill tab history scan in steps: first cast and catches per fishing rank; open casts added per result (pure) |
| `SkillModel.lua` | Skill numbers: rank over time, catches per skill point with range, forecast to the next rank cap and to 300 (pure) |
| `SkillTable.lua` | Skill tab texts, rank line chart, catches-per-point bars by rank band (pure) |
| `CompareTable.lua` | Compare tab: groups (lure, day/night, zone, character), rates with the Newcombe difference, median bite time (pure) |
| `MinimapModel.lua` | Minimap button position for an angle (round minimap or `GetMinimapShape` shapes), drag angle, saved angle; the button's tooltip (session, skill, click hints) (pure) |
| `TooltipModel.lua` | Item tooltip lines of Draft 6 ("Fishing Mastery" with "caught N", "Best water") from one item total (pure) |
| `Style.lua` | Text colors, the softer bar colors of Draft 1 (`BAR_GREEN`, `BAR_GOLD`, `BAR_ORANGE`, `BAR_GREY`), fonts by role, thousands separators, grey ranges "66 % (52 - 78)", "~" estimates (pure) |
| `CalendarModel.lua` | Calendar heatmap: 53 weeks of days, rows Monday to Sunday, color levels by catches (pure) |
| `Stats.lua`     | Statistics engine: Wilson, Byar, Newcombe ranges, expected casts, chance of at least one, bite quartiles, active time, blending; rate builders with fair and hooked casts and the display thresholds (pure) |
| `Export.lua`    | Export text: versioned pages with a checksum, per character (sharing) or all (backup) (pure) |
| `Contribute.lua` | Contribution export (module 7, `/fm contribute`): counts only, all characters merged (`StatsView`), subzone texts resolved per area: `FMC!<format>!<token>!<version>!<build>!<checksum>`, then sorted `A!<area>!<casts>!<item>:<catches>,...`, `M!<map>!...` (no area), `S!<area or m<map>>!<band>!<hooked>!<getaways>`, `L!<map>!<lure casts>!<lure catches>`; the checksum (`Export.Checksum`) covers the lines after the header joined with newlines; fixture `spec/fixtures/contribution.txt` |
| `Import.lua`    | Import: full validation, then merge of missing days (pure) |
| `Backup.lua`    | Rolling snapshots of totals and settings; reload reminder rule (pure) |
| `Synthetic.lua` | Deterministic synthetic casts for the stress test and the storage specs (pure) |
| `Stress.lua`    | Developer storage test: test entry filled in steps, line test chunks, load measurements (pure) |
| `Capture.lua`   | Raw capture ring buffer; aura spell IDs and loot source readers |
| `CastLog.lua`   | Saves each attempt as a cast record, counts sessions and totals, detects skill-ups, packs at logout and day change, runs the load check, ends idle sessions on time and a session on the HUD's stop button (session-end listeners) |
| `Frames.lua`    | Frame helpers: template fallback (one template or the first of a list), saved position, movable (optionally by a handle), guarded buttons |
| `TextWindow.lua` | Export (read-only pages, Select all) and import (paste box, Import button) window |
| `Confirm.lua`   | Confirmation dialog (backup restore) |
| `UiTest.lua`    | UI check test window: one line, one bar, an item icon, a 3-row scroll list, two tabs, "Open settings" (dev flag only) |
| `UiCheck.lua`   | UI API check: each statistics UI API missing, ok, or error; results in `dev.ui` (dev flag only) |
| `LureCheck.lua` | Lure check: the enchant ID of the running lure, the bonus the data gives it, and the time left; one entry per ID in `dev.lures` (dev flag only) |
| `AreaCheck.lua` | Area API check: map, zone and subzone texts, instance, area IDs at the position, test area names with byte-exact match flags; runs in `dev.area` (dev flag only) |
| `JournalCheck.lua` | Journal API check: recipe spells known, new Forever spell names, gear tooltips and counts, item classes, fishing modifier and main-hand tooltip; runs in `dev.journal` (dev flag only) |
| `JournalTrade.lua` | Trade skill read on `TRADE_SKILL_SHOW` for the journal check, repeated 1 s later: Classic API part (line, recipe count, first 3 recipes with spell, product, and reagent IDs) plus the `C_TradeSkillUI` part (dev flag only) |
| `JournalTradeUI.lua` | `C_TradeSkillUI` part of the trade read: function names, base profession, recipe IDs with learned flag, learned recipes with product and reagents (dev flag only); its one-recipe reader is shared with `RecipeRead.lua` |
| `RecipeRead.lua` | Recipe read for every player: on `TRADE_SKILL_SHOW`, once `C_TradeSkillUI` reports the list ready, stores the learned recipes that use a journal item in `FishingMasteryDB.recipes` |
| `GearInputs.lua` | Gear tab reads: item counts with and without the bank, the equipped slots, the fishing bonus on item tooltips and on the equipped gloves, race, level, rank, cap, skill modifier, active lure, quest names (all protected; missing APIs give "?") |
| `Commands.lua`  | `/fm` command registry and help                                        |
| `DataCommands.lua` | `/fm backup`, `/fm export`, `/fm import`, `/fm reminder` |
| `HudZone.lua`   | The HUD's water at the current spot: resolved area and name, getaway risk at the effective skill, the Classic list and own catches where it applies; dev area readout |
| `Hud.lua`       | HUD: the card or the compact line in a movable frame, shown from the first cast to the session end; gathers the cap, the running and suggested lure, and the items; lure tick; Draft 6 tooltip (dev flag: resolved area line); scale and opacity; the layout and stop buttons |
| `HudCommands.lua` | `/fm hud`: show, hide, lock, unlock, reset, scale, layout |
| `HudActions.lua` | The two HUD buttons at the top right (the line: right end): card or compact, and stop the session; tooltips |
| `Summary.lua`   | Session summary at the idle end and on `/fm summary`: the card in the HUD card's look (`TooltipBackdropTemplate`, the HUD background setting applies, movable, grows with its rows) or the chat block |
| `Tip.lua` | Tooltip builder: title, label and value pairs (gold label unless a color is given), gaps, headers, short lines, green hints, explanations only while Shift is held (redraws on `MODIFIER_STATE_CHANGED`; the only wrapped lines); `Tip.Into` writes below a shown tooltip (item post-call). The only file that writes tooltip lines (a spec checks it) |
| `StatsListHeader.lua` | Table header: gold bar with sort buttons and arrow, or labels |
| `StatsList.lua` | Table widget: header (`StatsListHeader`) over a ScrollBox list; striped rows, hover highlight, number cells with separators, item icons, cell colors, season and night tags, grey cells, legend line, `Tip` tooltips |
| `BarFill.lua` | Bar fills: a slight vertical gradient (`SetGradient` with `CreateColor`, checked by `/fm dev ui`), flat fill as the fallback; clears an old gradient on reused textures |
| `BarChart.lua`  | Bar chart widget: pooled bars (gold; orange for getaway charts; grey small samples), soft white range marks, grid and axis labels, value and x labels, hover tooltip per bar (`Tip` draw from the chart model) |
| `LineChart.lua` | Line chart widget: pooled `CreateLine` segments (squares without it), grid and axis labels, hover tooltip per point |
| `Heatmap.lua`   | Calendar heatmap widget: 53 × 7 day cells with weekday labels and a tooltip per day |
| `DetailPane.lua` | Detail pane widget in the tooltip and table style: title, lines, gold label and right-aligned value pairs, gaps, three-column tables; nothing wraps, rows past the height are hidden |
| `Look.lua` | Look settings: warm tints (Draft 1's brown) inside the main window's inset and every framed box, a solid backing (Draft 5's dark) behind the HUD views; created once, shown or hidden as a whole (`Look.Apply` at login and on a change) |
| `Controls.lua` | Shared controls of the pages: dropdown-styled button, the same look without the arrow for actions, framed box, small status bar, check box |
| `MainWindow.lua` | The Fishing Mastery window: page registry (`MainWindow.Register`), portrait frame (template fallbacks), side tabs on the right edge, page name, last page and position per character, Escape |
| `StatsWindow.lua` | Statistics page `/fm stats`: tab, scope, sort, filter, and bite group state; draws only the shown tab; redraws when item names load and while the history is counted |
| `StatsScope.lua` | Statistics page helpers: characters of the scope, their overview model, session count, the Fishing skill |
| `StatsFrame.lua` | Statistics page layout: scope dropdown, status line, one panel per tab, 8 bottom tabs |
| `OverviewPage.lua` | Overview frames: Fishing panel with the skill bar, headline numbers, where casts end, most caught |
| `StatsTabs.lua` | Build and draw of the Overview, Fish, and Zones tabs (with the click hint) |
| `JournalTable.lua` | Fish tab of the journal: filtered rows (group, caught or not, plain-text search) with icon, quality color, season or night tag, dimmed icon and grey row when not caught; the header bar (fish caught of total, every group in its tooltip); the place names shared with the detail pane (pure) |
| `JournalDetail.lua` | The Fish tab's detail pane: the fish as title, gold label and value pairs (caught, first catch, skill, season, time of day, own catches by hour and month), the places table (Classic and own share) and the recipes table (pure) |
| `JournalWindow.lua` | Journal page `/fm journal`: tab (saved per character), scope (account-wide by default), filters, selection; builds the model once per draw |
| `JournalInputs.lua` | Inputs of the Journal table builders: names, seasons, recipes, known spells, stock, own share per area, dates |
| `JournalFrame.lua` | Journal page layout: progress bar in the page header, scope dropdown, info line, filter row (dropdowns and the search box), panels, bottom tabs |
| `WatersTable.lua` | Waters tab of the journal: one row per area (subzones under their zone, dungeons last, places without reference data), base and no-getaway skill, fish count, own casts and catches, color band for the effective skill, fishable filter, sort (pure) |
| `RecipeTable.lua` | Recipes tab of the journal: rows (product, profession, reagents with own stock, color ranks, learn skill and source, fishing buff, known), product icon and quality color, `Tip` tooltip, known and per-fish filters, progress line (pure) |
| `GearTable.lua` | Gear tab of the journal: a heading row per section, rows (item, bonus with tooltip and game value, needs, source with the quest name, what you have), item icon and quality color, `Tip` tooltip, the best setup line, the equipped-bonus line (pure) |
| `JournalTabs.lua` | Build and draw of the journal tabs: Fish (list, detail pane, link to its recipes), Waters (waters list, the selected water's fish, colors for the skill now or the best setup), Recipes, and Gear |
| `FailureTabs.lua` | Build and draw of the Failures, Bite times, and Sessions tabs |
| `SkillTabs.lua` | Build and draw of the Skill tab (history scan with a progress line) and the Compare tab |
| `Dev.lua`       | `/fm dev` developer tools, load time measurement, raw capture events (dev flag only) |
| `MinimapButton.lua` | Own minimap button: drag around the edge (angle per character), left click main window, Shift + left click its Journal page, right click settings, tooltip of Draft 6, hide setting |
| `SettingsPanel.lua` | The game's Options entry as a launcher: one button that opens the Settings page (canvas category, else a button initializer); `/fm settings`, `/fm minimap` |
| `HudCard.lua` | HUD views of Draft 5 in the tooltip look: the card with stacked rows and two dividers around the numbers (small grey units; fish icons with names on hover; a long water name cut before the tag) and the compact line |
| `SettingsPage.lua` | Settings page of the main window: HUD (with the live preview), Information, Advanced statistics with the data buttons; "Panels: game / warm" and Defaults with a confirmation in the page header |
| `CastKey.lua`, `Bindings.xml` | Casting key (module 5): the named secure button `FishingMasteryCastButton` casts Fishing (name, else the highest known rank) on the key bound to "Cast Fishing" (Key Bindings, AddOns; no default key), on release only; attributes change only out of combat, a /reload in combat builds it after the fight; a note once without Fishing; a chooser (the smart lure) may make the next press a lure use or nothing, asked again in `PreClick`; `OnRelease` listeners (double-click, smart lure) |
| `DoubleClick.lua`, `DoubleCast.lua` | Double right-click casting (module 5, setting `doubleClick`, off): pure `DoubleClick` takes the second right press within 0.4 s into the world (not a unit, a frame, a held camera drag, a click right after a unit, or the bobber) and names what blocks a cast (combat, mounted, swimming, flying, taxi, dead, no button, no Fishing, no pole, a lure being applied, line out); `DoubleCast` binds `BUTTON2` to the cast button for that one press and clears it on the release, `PLAYER_REGEN_DISABLED`, a loading screen, or after 2 s; `Conflict` names a loaded Luredon or CFC for the settings note |
| `LureChoice.lua`, `SmartLure.lua` | Smart lure (module 5, setting `autoLure`, off): pure `LureChoice` picks no lure when the skill without a lure reaches base + 95, else the cheapest usable lure in the bags that does, else the strongest (also in water without data); nothing while a lure with more than 30 s runs, only a same-kind renewal at 30 s or less, a wait while a lure is applied. `SmartLure` reads the inputs, is the casting key's chooser (`type=item`, `target-slot` 16, decided in `PreClick` out of combat), waits after a lure click until the enchant shows up (at most 10 s, or a failed cast), and gives the Helpers page and the HUD the choice for this water (`SmartLure.Now`); `LureChoice.Running` names the running lure from its bonus, `SmartLure.Owned` lists the lures in the bags |
| `SoundBoost.lua` | Louder splash (module 5, setting `loudSplash`, off): with a pole in hand `Sound_EnableSFX` 1, `Sound_SFXVolume` 1, `Sound_MusicVolume` 0, `Sound_AmbienceVolume` 0; the old values in `FishingMasteryCharDB.sounds`, restored when the pole leaves the hand, the setting goes off, at `PLAYER_LOGOUT`, and at the next login without a pole (a copy is never saved over) |
| `HideUI.lua` | Hidden interface (module 5, setting `hideUI`, off): `SetUIVisibility(false)` at the fishing channel start (not in combat, dead, or when the player hid it); back on moving, combat, death, target, whispers, dialogs, mount, a loot window without auto loot, the pole leaving the hand, loading screens, logout, the setting off; the player's own Alt+Z is left alone; catch lines on `WorldFrame` for 5 s |
| `HelperStatus.lua` | `/fm helpers`: this login's casting key presses by mode (cast, lure, wait), double-click presses, casts the tracker saved, and each helper setting (memory only); opens the Helpers page |
| `HelperModel.lua` | Helpers page: helper rows with their state (off, ready, on, active, blocked with the reason), the smart lure's "Right now" texts, the "This login" rows (pure) |
| `KeyButton.lua` | Key-binding button: binds the next key (with modifiers) to "Cast Fishing", Escape cancels, right-click clears; disabled in combat |
| `HelpersPage.lua` | Helpers page of the main window: helper rows with check boxes and state tags, the casting key, "Right now", "This login", the other-addon warning; redraws every second while shown |
| `Helpers.lua` | Starts the helpers at login in order (casting key, smart lure, louder splash, hidden interface, double-click, status) and passes each saved cast to the catch line and the status |
| `ItemTooltip.lua` | Item tooltip post-call: adds the lines for items this character caught through `Tip.Into`, one lookup per tooltip, tooltip setting |
| `Compartment.lua` | Addon compartment handler `FishingMastery_OnAddonCompartmentClick` (TOC `AddonCompartmentFunc`), run through the guard; opens or closes the main window, with Shift its Journal page |
| `Core.lua`      | Event frame, setup on `ADDON_LOADED`, character entry on `PLAYER_LOGIN`, slash command |

### Saved Data

- `FishingMasteryDB` (account-wide): `schemaVersion`, `chars[UnitGUID("player")]` with
  `name` and `part` (the two name parts, display only), `firstSeen`, `lastSeen` (server time),
  and `settings`. `GetRealmName()` is never part of the key. `contributeToken`: 8 random hex
  digits for `/fm contribute`, made on its first use (never derived from a name, GUID, or realm).
- `FishingMasteryDB.recipes` (account-wide): recipes read from profession windows that use a
  journal item, `[spellID] = { s = skill line (0: unknown), p = product item (0: none), r =
  { { itemID, count } } }`; at most 300 recipes and 8 reagents each. IDs and counts only.
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
- Session: `start`, `last` (last cast), `ended` and `endReason` (`idle`, `logout`, or `stopped`:
  the HUD's stop button), `casts`,
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
  | `items`    | `[itemID] = { n (catches with it), qty, first, last (server time), best (map with the most), fm, fs (map and subzone index of the first catch), hours = { [UTC hour] = catches }, months = { [UTC month] = catches }, fair (fair casts counted at its last catch) }` |
  | `active`   | `[map] = seconds`: Σ min(gap to the next cast, 60 s), 60 s for the latest cast |
  | `subs`     | `[map][sub] = { casts, outcomes, items = { [itemID] = catches with it }, active }`, sub = subzone index or 0 (none); the same active time split per subzone |
  | `subskills` | `[map][sub][band] = { hooked, getaways }`: the `skills` bands per subzone, so the getaway rate can be split by resolved area |
  | `last`     | `{ t, map, sub }` of the latest cast (for the active time) |

  Hooked = catch + getaway. `/fm rebuild` counts everything again and says whether the result
  equals the live totals. Totals of another version (after the schema 2 update, a new totals
  version such as 3 for the early-click times, 4 for subzones and item hours, 5 for the
  skill bands per subzone, 6 for the first catch place, or 7 for the item months, or a restored
  old snapshot) are counted again after login, in the same steps as the load check (one decode for
  both); `/fm status` says "Counting your history" until it is done, and casts during the count
  are counted once. 200,000 synthetic casts give about 86 KB of totals in the saved file (8 maps, 12 items;
  version 4 adds about 20 % for subzones and item hours: the spec estimate goes from 76,076 to 91,269
  characters);
  on live the load check with the rebuild took 2.3 s in 80 steps (longest 48 ms).
- `FishingMasteryCharDB` (per character): `schemaVersion` and `ui` (UI layout only: window and
  HUD positions; `ui.main` is the main window, `ui.page` its last page, `ui.minimap.angle` the minimap button, degrees,
  default 220).
- `FishingMasteryDB.settings` (account; every default in `Options.DEFAULTS`): `hud` = `enabled`
  (default on), `locked`, `scale` (0.5-2, default 1), `layout` (`card` or `compact`; a `style` saved
  before 1.1.0 becomes its layout: full card, text compact), `opacity` (0.3-1, default 1), `zoneLine`
  (default on), `background` (`tooltip`, default, or `solid`); `ui.panels` (`warm`, default, or
  `game`); `summary.style` = `window` (default) or `chat`; `minimap.shown` (default on);
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
| `/fm hud layout card\|compact` | The card, or one compact line                          |
| `/fm summary`              | Summary of the open session, or of the last one (also shown when a session ends after 15 minutes without a cast) |
| `/fm summary window\|chat` | Where summaries appear: the summary card (default) or your chat frame |
| `/fm stats`                | Statistics page of the main window, see below (the minimap button's left click and the addon compartment entry open the window on its last page) |
| `/fm journal`              | Journal page of the main window, see below (also Shift + left click on the minimap button or the compartment entry) |
| `/fm settings`             | Settings page of the main window (also the minimap button's right click and the game's Options entry) |
| `/fm minimap show\|hide`   | Shows or hides the minimap button |
| `/fm rebuild`              | Counts the totals again from the whole history, prints casts, catches, and days, and says whether they equal the live totals |
| `/fm status`               | "Counting your history" while the totals are counted after login; current session: length, casts, catches, count per failure outcome, fishing skill before and after, and the last outcome (with bite time for a catch, click time for an early click or getaway) |

### HUD Card

The HUD card names the water you stand in (resolved area, else the map name) with a risk tag at
your effective skill from the Classic model (green "no getaways", orange "18 % get away", grey "?"
without a base level). The skill bar shows "Fishing 154 / 225" with the skill-ups and a white mark
at the effective skill with lure and gear; while fish still get away a green tick marks where
getaways stop (when that is on the bar) and a line shows "with lure 176" and "getaways stop at
225". The lure row shows the running lure with a mm:ss timer (named with its icon: the lure of
that bonus in the bags, else the only lure with that bonus; "Lure +50" when two share it and
none is owned), "No lure needed
here", or the smart lure's suggestion. Then, between two thin dividers, catches, success (with a
small grey "%"), and catches per hour (grey while the sample is small), the last catch with
icon, quality color, and bite time, and the water's fish as
icons (bright when caught here, dark when missing, names on hover) with "N missing". The compact
layout is one line: water, risk, catches, success, skill. A long water name ends in "..." before
the tag. The water is read again on `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA`,
skill changes, and attempt ends (the lure tick keeps it). The tooltip (Draft 6): the session, its
casts and rates with ranges, getaways here (Classic at your skill, yours in the skill band, none
from skill), in risky water the best lure in the bags ("on the pole" when it runs), and the
explanations with Shift. The setting "Water line" leaves the
water out. Two small buttons at the top right (at the right end of the compact line) switch
between the card and the compact line (saved like the Settings page) and stop the session now
(the summary shows as after an idle end; the next cast starts a new session).

### Main Window

One window "Fishing Mastery" holds every module as a page, with a side tab per page on its right
edge (Statistics, Journal). It is movable by the title, closes with Escape, and opens on the last
page; position and page are saved per character. Each page has its name under the title, its
controls on the right (the scope dropdown), and its bottom tabs.

### Stats Window

`/fm stats` opens the Statistics page with 8 tabs. It reads the
totals and the session records; only the Skill tab reads the history, in steps. It draws only the
shown tab. Ranges are in the row tooltips; values from small samples are grey (counts only below
10).

- **Overview** (of the scope): the Fishing panel (rank name, the skill bar "Fishing 154 / 225"
  with a white mark at the effective skill with lure and gear, the skill points gained since the
  first saved session); four numbers: catches of casts, success rate, catches per hour (each
  with "likely low - high", grey or counts only for few casts), active fishing time in sessions
  ("4 h 44 min", "12 min" under an hour; units small and grey, each number centered with its unit);
  where casts end (catch, got away, clicked too early, not clicked: count, bar, share of fair
  casts; cancelled and invalid target grey, counted only); the five most caught items with a bar;
  each panel's note line right under its rows.
  With all characters the Catches number lists every character in its tooltip.
- **Fish:** every item with catches (icon, quality color, a season or night tag), share of
  catches, about every (fair casts per catch), dry streak (fair casts since the last one, one
  character), best water. The row tooltip adds the ranges, the hour with the most catches (realm
  time), and the first and last catch. Small samples are grey with "~" (legend under the list).
  Click a header to sort, again to flip the order; the quality dropdown filters, the line next to
  it counts kinds and catches.
- Every tooltip (table rows, chart bars, calendar days, the HUD, the item tooltip, the minimap
  button, settings, helpers) is a title with gold labels and white values; ranges in a grey
  bracket "66 % (52 - 78)"; explanations only while Shift is held; click hints in green. Charts
  use the same fonts and colors.
- **Zones:** every zone (most casts first) and its subzones: casts, catches per hour, species,
  the top 3 items with their shares; all items with ranges in the tooltip. Subzones with their
  own zone data get one row per area; other subzone texts keep their own row. A click on a row
  selects it (gold name; the first row by default; a hint line says so) and fills the
  comparison below: the
  water's expected fish with their "Classic estimate" chance, season (winter, summer) or quest
  flag, and your share with its range, then fish caught there that are "not in Classic data".
  A subzone without its own list shows its zone's list and the zone's catches where that list
  applies. The note names the list and the part of a catch it does not cover (partial lists);
  places without data show "No reference data (new in Forever)" and your catches only.
- **Failures:** every outcome with its count and rates (of fair casts; catches and getaways also
  of hooked casts; cancels, invalid targets, and unknown attempts are counts only); bar charts of
  the getaway rate with 95 % range marks, and of early clicks by click time (1-second bands).
  The getaway chart groups by 5-point band of effective skill minus the water's base level
  (resolved area, a subzone's own base or its zone's) with the Classic model as a white line and
  in the tooltip ("Differs from Classic" when the own range excludes it); hooked casts in waters
  without a base are left out and counted next to the button. The button switches to bands of
  effective skill (rank + modifier, all zones together); without any water with a base only that
  chart is shown.
- **Bite times:** histogram (1-second bins up to 30 s) of all zones or of one zone and lure state
  (the button steps through them), median and quartiles; a table of every group.
- **Sessions** (of the scope): the records above the list (most catches in a session, most
  catches per hour in a session with at least 30 fair casts, longest session); every session
  (newest first) with date, character, zone, active time, casts, catches, and skill change; click
  a header to sort, rates with ranges in the tooltip; a calendar heatmap of the last 53 weeks
  below (UTC days of the server time, brighter = more catches; date, casts, and catches in each
  day's tooltip).
- Charts: bar values above the bars when they fit, the numbers of every bar in its tooltip, grey
  bars for small samples. Bars use the softer colors of Draft 1 with a slight gradient (gold;
  orange for the getaway charts); the 95 % range is a soft white whisker.
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

- **Settings page** (`/fm settings`, a right click on the minimap button, or the button of the
  game's Options > AddOns > Fishing Mastery entry): HUD on/off, lock, water line, layout (card or
  compact), background (game tooltip or solid), scale, opacity, with a live preview; item tooltip
  line, summary in the chat, minimap button, reload reminder; the count-only and grey sample sizes
  and the idle cap T; export, backups, contribute; in the page header "Panels: game / warm" (a dark
  warm tint over the window's panels) and Defaults (asks first; the helpers and positions stay).
  Changes apply at once (T at the next login). The helpers are on the Helpers page.
- **Minimap button** (own, no libraries): drag it around the minimap edge (square minimaps
  follow their corners); the angle is saved per character. Left click opens or closes the main
  window, Shift + left click its Journal page, right click opens the settings. The tooltip
  (Draft 6) shows the open session (catches and active time), the Fishing skill, and the click
  hints. Hide it in the settings or with `/fm minimap hide`.
- **Addon compartment:** the Fishing Mastery entry opens or closes the main window (with Shift
  held: its Journal page).
- **Journal page** (`/fm journal`): a page of the main window with the tabs Fish, Waters,
  Recipes, Gear; the last tab is saved per character. The
  Fish tab lists every fish, trophy fish, container, and quest fish of the Classic data plus
  caught items new in Forever, for all characters (scope button: this character). Not-caught
  fish are marked (dimmed icon, grey row, "not caught") but show all their information. Filters:
  group, caught or not, and a search box (plain text in the item name). A click on a row shows
  the details on the right as label and value pairs and two small tables (no sentences): count,
  first catch date and place, most caught zone, the skill to catch it and
  to stop getaways (Classic model), the top 5 places by Classic share with the own share there
  (grey counts below 10 casts), up to 4 recipes that use it, and the Classic season with "in season now" or not (Classic
  window in server time). Caught fish list your catches by month (UTC). Raw Nightfin Snapper
  and Raw Sunscale Salmon carry the guides' day or night claim, "unconfirmed" below 30 catches,
  with your busiest server hours. A bar in the page header shows the fish caught of all fish;
  its tooltip lists every group. Filters and buttons have the dropdown look.
  The **Waters** tab lists every water of the Classic data (subzones under their zone, dungeons
  last) and places you fished that have no reference data, with the skill to catch there and to
  stop getaways, the number of fish, and your casts and catches. Rows are colored for your
  effective skill (rank and bonuses): red = no catch, orange = some fish get away, green = no
  getaways. "Fishable now" keeps orange and green waters; the sort button switches between
  name and skill; "Colors: best setup" colors for the best setup of the Gear tab instead. A
  click on a water lists its fish (Classic estimate and own share, as on the
  stats window's Zones tab); a click on a fish opens it in the Fish tab.
  The **Recipes** tab lists the 23 Classic recipes that use fish (Cooking and Alchemy) and the
  recipes read in game: product, profession, reagents with counts and how many you have (bags
  and bank), the yellow and green skill ranks, the learn skill and source, the fishing buff of
  buff food (guide values), and whether this character knows it (`IsPlayerSpell`; grey when
  not). Hover a row for the details. Opening any profession window stores every learned recipe
  that uses a journal item once per account (about 1 s after the window opens, once the list
  has loaded); recipes not in the Classic data show as "read in game". The filter button picks
  known or not known; "Show its recipes" in the Fish tab detail opens the tab filtered to that
  fish ("All recipes" clears it).
  The **Gear** tab lists fishing poles, other gear, lures, buff food, the four fishing ranks,
  and Enchant Gloves - Fishing: the bonus, what it needs (Fishing skill, level, Alliance or
  Horde only), the source (vendor, quest with its client name, derby, drop, trainer, book,
  formula), and where you have it (equipped, bags, bank; ranks learned or not; the enchant on
  your gloves). Grey rows are items you do not have or cannot use. For gear the bonus is read
  from the item tooltip ("+20 (tooltip)"); a tooltip that differs from the data shows both. With
  one bonus item equipped, the bonus the game applies (skill modifier minus the active lure) is
  shown next to it when it differs; the line below the list compares all equipped items with
  it. The line on top is the best setup: your rank plus the highest bonus you have per slot
  (pole, line, head, feet, hands, glove enchant) and the best lure in your bags, each usable at
  your skill, level, and race. Lure, food, and enchant values are guide values.
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
| `/fm dev ui`                 | UI API check: opens the test window, prints one line per API (ok, missing, error with the text), and keeps the results in `dev.ui`; "Bar gradient" says whether bars get the gradient or the flat fallback |
| `/fm dev lure`               | Lure check: prints the running lure's enchant ID with the data's bonus and time left, keeps one entry per ID in `dev.lures` |
| `/fm dev area [clear]`       | Area API check at the current spot: prints the readings and the area the lookup resolves, appends them to `dev.area.runs` (30 kept); `clear` removes the runs |
| `/fm dev journal [clear]`    | Journal API check: prints and appends a run to `dev.journal.runs` (10 kept); while the dev flag is on, every opened trade skill window adds a read to `dev.journal.trades` (10 kept); `clear` removes both |

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
- **Area API check** (`dev.area.runs`, at most 30, oldest dropped): each run is `{ at, map,
  mapName, mapType, zone, realZone, subzone, minimap, instanceType, instanceID, here = { x, y,
  areas = { { id, name, subzone, zone } } }, tests = { { id, name, subzone, zone, english } },
  missing }`. `map` is `C_Map.GetBestMapForUnit`; the texts come from `GetZoneText`,
  `GetRealZoneText`, `GetSubZoneText`, and `GetMinimapZoneText`; the instance from
  `GetInstanceInfo` (type, 8th return); `here.areas` from
  `C_MapExplorationInfo.GetExploredAreaIDsAtPosition` at `C_Map.GetPlayerMapPosition`. Names
  come from `C_Map.GetAreaInfo`; `subzone`/`zone` mean the same bytes as the subzone or zone
  text, `english` the English name in the client export. The 26 test areas are listed in
  `AreaCheck.TEST_AREAS`. No player names or GUIDs are stored.
- **Journal API check** (`dev.journal`, `runs` and `trades`, at most 10 each, oldest dropped):
  a run is `{ at, recipes = { { id, name, known, player } }, newSpells = { { id, name } },
  gear = { { id, tip, bags, bank } }, groups = { { id, class, subclass } }, fishing = { rank,
  modifier, pole, tip }, missing }`. `known`/`player` come from `IsSpellKnown`/`IsPlayerSpell`,
  names from `C_Spell.GetSpellInfo` (else `GetSpellInfo`), `tip` is up to 12 left lines of
  `C_TooltipInfo.GetItemByID` (nil until the item is loaded), `bags`/`bank` are
  `C_Item.GetItemCount` without and with the bank, `class`/`subclass` from
  `C_Item.GetItemInfoInstant`, and `pole` is `GetInventoryItemID("player", 16)`. The ID lists
  are `JournalCheck.RECIPES`, `NEW_SPELLS`, `GEAR`, and `GROUP_ITEMS`. A trade read is `{ at,
  fired, line, num, recipes = { { index, spell, product, reagents = { { id, count } } } } }`
  from `GetTradeSkillLine`, `GetNumTradeSkills`, `GetTradeSkillInfo` (headers skipped),
  `GetTradeSkillRecipeLink`, `GetTradeSkillItemLink`, `GetTradeSkillNumReagents`,
  `GetTradeSkillReagentInfo`, and `GetTradeSkillReagentItemLink` (all missing on Forever), plus
  `phase` (`show`, or `later` for the read 1 s after the event) and `modern = { api, profession,
  professionName, skill, maxSkill, total, learned, recipes = { { id, via, product, reagents } } }`
  from `C_TradeSkillUI`: `api` lists its function names (150 kept), `recipes` the learned ones (60
  kept), read with `GetRecipeSchematic` (`via = "schematic"`) or `GetRecipeNumReagents`,
  `GetRecipeItemLink`, `GetRecipeReagentInfo`, `GetRecipeReagentItemLink` (`"reagentInfo"`).
  Recipe names are printed, not saved. No player names or GUIDs are stored.
- **HUD dev line:** while the dev flag is set, the HUD tooltip ends with the resolved area
  ("Dev: area 367 Sen'jin Village (subzone)", "(zone)", "(dungeon)", or "no area data here").

## FishingMasteryProbe

The frozen Epic 1 API probe (files, log format, guided run, commands, export) is documented in
[docs/probe.md](probe.md).

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

**On GitHub:** `.github/workflows/check.yml` runs the same gates on every push and pull request:
`luacheck .`, `busted`, `stylua --check .` (job `lua`), and
`python -m unittest discover -s tools -p "test_*.py"` (job `tools`). It uses Lua 5.1.5, the
game's language version, so code that only LuaJIT accepts fails there. Versions are pinned:
luacheck 1.2.0, busted 2.3.0, StyLua 2.6.0, Python 3.14, each action at a release tag. Raise them
together with the local tools.

**Package dry run:** Actions → Package → Run workflow builds the release zip with the BigWigs
packager (v2.7.0, `.pkgmeta`) without uploading, lists its files in the log, and keeps the zip
as the workflow artifact `package` for 7 days.

**Cutting a release:**
1. `CHANGELOG.md`: a new top entry `## <version>` with the changes since the last release.
2. Run the package dry run (above) and the privacy scan (below); `main` must be green.
3. Tag and push: `git tag v<version>` and `git push origin v<version>`. Tags with `-beta` or
   `-alpha` (for example `v0.9.0-beta`) upload as beta or alpha files.
4. `release.yml` builds the zip with the packager, writes the version from the tag into the TOC,
   and uploads it to CurseForge ("Fishing Mastery Forever", project 1789368 from
   `## X-Curse-Project-ID`) and to GitHub Releases. It needs the repository secret `CF_API_KEY`
   (CurseForge author API token, https://www.curseforge.com/account/api-tokens).
5. Check the file on CurseForge and the GitHub release, then install it with the CurseForge app.

**Privacy scan:** before the repository is made public, and before each release,
`python tools/privacy_scan.py <WTF/Account/<account>/SavedVariables/FishingMastery.lua> . ../kb`
searches the full history and the current files of each given repository for the account,
realm, and character folder names and the character keys and name parts in
`FishingMasteryDB.chars`, as whole words. It prints counts per kind only, never a term or the
path, and exits with 1 on any hit. Terms shorter than 3 letters are not searched.

**Contribution checker:** `python tools/contrib.py <file>` checks one `/fm contribute` text
(module 7) and prints "valid" with the lines per kind, or "rejected: <rule>". It cleans what
pasting does (Markdown code fences, Windows line ends, the "|" form), limits the size to 65,536
characters before parsing, and rejects the whole text on: a bad header or format version, a
checksum mismatch, an unknown line kind or field count, counts that are not non-negative integers,
area IDs the addon cannot resolve (`Data/Zones.lua`: areas, subzones, zones of maps, instances),
item IDs outside 1-999999, map IDs outside 1-99999, bands not on a 5-point step, catches above
casts, getaways above hooked, lure casts above the map's casts (its zone's areas and its `M`
line), and duplicate keys. Messages name the rule and a line number, never the content. Tests:
`tools/test_contrib.py` with the addon's fixture `spec/fixtures/contribution.txt`.

`.luacheckrc` turns the LuaJIT JIT compiler off for luacheck: with it on, full-tree runs crashed
with a segfault in most attempts, while the interpreter is stable.

### Zone Data

`FishingMastery/Data/Zones.lua` is generated; never edit it by hand. It holds the Classic
fishing loot lists, base skills, and area placement as `ns.Zones` (`lists`, `areas`,
`mapToArea`, `children`, `instanceToArea`; format in the file header). Chances are Classic
estimates (CMaNGOS reconstructions), not Blizzard values; Forever-only zones have no entry.

- An area's list replaces its zone's list (server rule); an area without `list` uses the zone's.
- A subzone list with only seasonal or quest rows is merged with its zone's list
  (`merged = true`), because those rows add to the zone's fish rather than replace them.
- `partial` is the percent of a roll the Classic data does not cover (e.g. Silverpine 45.4);
  the rest is shown as not in the Classic data, never spread over the known fish.

**Area lookup** (`Area.lua`): a dungeon by its instance ID, else the zone of the UI map
(`mapToArea`), and inside it the subzone whose `C_Map.GetAreaInfo` name equals the subzone text
byte for byte; no match or no text gives the zone, a place without data `nil`. Past cast records
resolve the same way from their map and subzone text (no schema change); texts saved under
another client language fall back to the zone, and past dungeon casts (no instance ID saved)
have no area.

```powershell
python tools/fetch_zone_sources.py   # download the pinned sources, rewrite tools/data/, list changed areas
python tools/build_zone_data.py      # write Data/Zones.lua from tools/data/ (fails if an area cannot be placed)
python -m unittest discover -s tools -p "test_*.py"
```

Both scripts need only Python 3 (standard library). The fetch uses fixed HTTPS URLs; to move to a
newer source, change the pinned commits and client build in `tools/zone_sources.py`, run both
scripts, review the changed areas, and commit `tools/data/` with the new `Zones.lua`.
`spec/fm/zones_spec.lua` checks the counts; update them only after reviewing a source change.

### Journal Data

`FishingMastery/Data/Journal.lua` is generated by `tools/build_journal_data.py` (shared rules in
`tools/journal_sources.py`); never edit it by hand. `ns.Journal` holds (row formats in the file
header):

- `groups`: every item of the zone data's loot lists (108) by group: `fish`, `trophy`,
  `container`, `quest` (the journal shows these four), `potion`, `junk`, `other`. Containers are
  the openable items; trophy fish are an ID list; fish have the fish food type, are reagent class,
  or are one of three listed IDs. The build fails when an item fits no rule. Forever re-classed
  these items, so the addon must not group them by `C_Item.GetItemInfoInstant`.
- `recipes`: Classic recipes with a journal item as reagent that are on a Forever skill line
  (Cooking 185, Alchemy 171): product, reagents, color ranks from the Forever `SkillLineAbility`,
  learn skill, source (`vendor`, `drop`, `quest` with the recipe item, or `trainer`). Spells on no
  Forever line are left out (Copy of Nightfin Soup).
- `gear`: obtainable items with a fishing skill aura and every fishing pole (the plain Fishing
  Pole at +0) (bonus, required skill and level, race mask
  from the item or its reward quest, source), plus two Forever items confirmed on live: High Test
  Eternium Fishing Line (+5, guide value) and the Wide-Brimmed Fishing Hat (`lure`, +25 on use).
  Copies without any source are left out. Each item has its slot (`pole`, `line`, `head`,
  `feet`, `hands`; from `InventoryType`).
- `lures`: obtainable items whose use spell puts a lure enchant on the pole (bonus per enchant,
  guide values; required skill, race mask, source). `lureEnchants`: lure enchant ID → bonus,
  for the active lure.
- `ranks`: the four fishing ranks with their rank cap, the skill and level to learn them, and
  the source (trainer, or the Expert and Artisan books; the Artisan book's quest is not in the
  dump). `enchants`: Enchant Gloves - Fishing (+2, guide value) with the formula's Enchanting
  skill and source.
- `food`: fishing buff food made by a bundled recipe (Loch Frenzy Delight, Bristle Whisker
  Catfish, Rockscale Cod, Filet of Redgill): bonus and character level, guide values. The build
  fails when a listed food is no bundled recipe's product.
- `times`: Raw Nightfin Snapper (night) and Raw Sunscale Salmon (day), the window the guides
  claim; CMaNGOS has no condition for them, so the addon shows it as unconfirmed.
- `seasons`: Winter Squid and Summer Bass with their Classic game event window (start month, day,
  hour in server time, length in days).

`python tools/fetch_zone_sources.py` also refreshes the journal inputs (and lists added and
removed rows per file); then run `python tools/build_journal_data.py`.
`spec/fm/journal_data_spec.lua` and `tools/test_journal_tools.py` check the counts.

**Getaway model** (`Getaway.lua`, CMaNGOS server rule): catch chance of a hooked fish =
clamp(effective skill − base + 5, 0, 100) %; below the base no fish is caught (every hooked fish
gets away), and getaways stop at base + 95. A subzone without its own base uses its zone's. The
own getaway rate (getaways / hooked) per resolved area and 5-point skill band is compared with
the model's mean over the band only when it is shown (at least the count threshold of hooked
casts); places without a base level show "unknown" and the own rate only.

### Data Sources and Credits

- **CMaNGOS classic-db** (https://github.com/cmangos/classic-db, GPL-3.0), commit
  `37eeeeb1d4`: fishing loot, reference loot, base skill, and season condition rows; for the
  journal, item, spell, vendor, trainer, quest reward, loot source, and game event rows.
- **AllTheThings** Forever client exports (https://github.com/ATTWoWAddon/AllTheThings, MIT,
  copyright (c) 2026 AllTheThings WoW Addon), commit `e15f5d9cee`, client build `1.60.1.70790`:
  `AreaTable`, `UiMap`, `UiMapAssignment`, and `SkillLineAbility` rows. The MIT notice is in
  `tools/data/LICENSE-AllTheThings.txt`.

Item names, icons, and zone names are read from the game client at runtime. The package carries
these notices, with the MIT text, in `FishingMastery/NOTICE.md`.

### Install for In-Game Testing

Link each addon folder into the game client with a junction (no admin rights needed):

```bash
cmd //c mklink /J "<WoW>\_forever_\Interface\AddOns\FishingMastery" "<repo>\FishingMastery"
cmd //c mklink /J "<WoW>\_forever_\Interface\AddOns\FishingMasteryProbe" "<repo>\FishingMasteryProbe"
```

The probe is only needed for API tests; Fishing Mastery runs without it.

In game, `/console scriptErrors 1` shows Lua errors and `/reload` loads code changes.
