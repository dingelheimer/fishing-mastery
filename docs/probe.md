# FishingMasteryProbe

Unpublished, frozen test addon from Epic 1 that recorded Forever API facts into a log.
Back to the [README](../README.md).

The probe never changes gameplay. It records facts into the SavedVariables table
`FishingMasteryProbeDB`, which the client writes on `/reload` or logout.

| File             | Responsibility                                                      |
|------------------|---------------------------------------------------------------------|
| `Locale.lua`     | User-facing strings (`ns.L`)                                        |
| `Serializer.lua` | Converts any value to plain data; secret values become `<secret:type>` |
| `Logger.lua`     | Append-only log entries `{ t, step, q, kind, data }` with a hard cap |
| `Guard.lua`      | Runs handlers through `xpcall`; errors are logged as `lua_error`    |
| `Db.lua`         | SavedVariables schema (`schemaVersion`), migrations, persistence marker |
| `Scan.lua`       | Existence checks and global scans; reads values, never calls them   |
| `Calls.lua`      | Protected calls of named APIs; missing functions and errors become results |
| `Redact.lua`     | Reduces names and GUIDs to shape facts (presence, length, type)     |
| `ApiList.lua`    | Data: APIs, namespaces, and events checked on login                 |
| `Snapshot.lua`   | Login snapshot (step `S0`)                                          |
| `Attempt.lua`    | Attempt classifier: groups cast events into attempts with an outcome |
| `Context.lua`    | Cast context: professions, pole, lure, auras, location, time         |
| `Loot.lua`       | Loot slot data and item info                                        |
| `Events.lua`     | Event bus for the recorders; skips events the snapshot could not register |
| `Tracer.lua`     | Event tracer: redacted payloads and secret flags                    |
| `Recorders.lua`  | Cast, loot, item info, attempt, and tooltip recorders               |
| `SecureKey.lua`  | Step S14a: secure Fishing button on a temporary test key            |
| `AddonMessage.lua` | Step S14b: addon message self-whisper with prefix `FMProbe`       |
| `Helpers.lua`    | Step S14: helper environment entry, combat check, test key removal  |
| `Steps.lua`      | Data: guided test run steps S0-S15 (texts, targets, optional flag, question IDs) |
| `Progress.lua`   | Guided run state: start, done, skip, back, counting, auto-advance    |
| `View.lua`       | Texts and button states the window shows for the current step       |
| `Window.lua`     | Guided test run window (movable, position saved)                    |
| `Checklist.lua`  | Checklist overview of all steps with open/done/skipped              |
| `ReportRules.lua` | Report rule building blocks (entry matchers, counters, key value helpers) |
| `RulesLogin.lua` | Data: report rules for the login snapshot questions (Q01-Q05, Q20-Q22, Q29) |
| `RulesCasts.lua` | Data: report rules for the guided fishing steps (Q06-Q17)            |
| `RulesPassive.lua` | Data: report rules for passive recorders and S10-S14 (Q18, Q19, Q23-Q28, Q30-Q32) |
| `Report.lua`     | Per-question summary of the log (answered / partial / skipped / missing) |
| `Export.lua`     | The log as compact text: one JSON line per entry, split into pages   |
| `TextWindow.lua` | Scrollable, read-only text window to select and copy report or export |
| `Confirm.lua`    | Confirmation dialog (used by `/fmp reset`)                           |
| `Commands.lua`   | `/fmp` command registry and dispatch                                |
| `Handover.lua`   | `/fmp report`, `/fmp export`, `/fmp reset`                          |
| `Core.lua`       | Event frame, setup on `ADDON_LOADED`, snapshot, recorder and helper start, and first-login window on `PLAYER_LOGIN`, test key removal on `PLAYER_LOGOUT`, slash command |

## Log Format

- `FishingMasteryProbeDB.log.entries` holds entries `{ t, step, q, kind, data }`. `t` is
  `GetTimePreciseSec()`, `step` the guided step ID, `q` the question ID when known.
- The log keeps at most `log.cap` entries (default 20,000); the oldest are dropped and counted in
  `log.dropped`.
- `log.sessionId` and `log.probeVersion` describe the current session; every session also starts
  with a `session_start` entry. Session IDs combine server time and a random number.
- Serializer limits: depth 6, strings 500 characters, 200 keys per table.
- The log never contains the account folder name, character name, or realm.

## Login Snapshot (Step S0)

On `PLAYER_LOGIN` the probe logs `kind = "snapshot"` entries with step `S0`; `data.topic` names
the content:

| Topic                | Q   | Content                                                          |
|----------------------|-----|------------------------------------------------------------------|
| `build`              | Q01 | `GetBuildInfo()`: version, build, date, interface                |
| `project`            | Q02 | `WOW_PROJECT_ID` and every `WOW_PROJECT_*` global                |
| `game_rules`         | Q03 | `C_GameRules` members, experience preset, `Enum.GameRule`        |
| `time`               | Q20 | `GetGameTime`, `GetServerTime`, calendar time                    |
| `restricted_actions` | Q29 | `C_RestrictedActions` members and `Enum` tables named `*Restriction*` |
| `restricted_getter`  | Q29 | One per `Is*`/`Get*`/`Has*` function: result without arguments, then per enum value (max 16) if that fails |
| `api_scan`           | Q04 | One per `ApiList.GROUPS` group: `function` / `table` / `nil` per name |
| `event_scan`         | Q04 | Per `ApiList.EVENTS` event: registration result, error, `C_EventUtils.IsEventValid` |
| `global_strings`     | Q05 | String globals whose name contains `FISH` or `LURE` (case-sensitive), max 500, chunks of 100 |
| `character_key`      | Q21 | `UnitName`, `UnitFullName`, realm, GUID reduced to presence, byte length, separators, GUID type and segment count |
| `persistence`        | Q22 | Whether the previous session marker survived, previous session ID, session counter |
| `done`               | -   | Entry count and number of registrable events                     |

- Each topic runs separately protected; a failing topic is logged as `lua_error` with
  `where = "snapshot:<topic>"` and the others continue.
- The event scan registers each event on a separate handler-less frame and unregisters it at
  once. Its result (`ns.eventSupport`) decides which events the recorders register.
- The existence scan resolves dotted names field by field and never calls a function. The only
  calls are the named APIs above and the `C_RestrictedActions` getters.
- A `entering_world` entry (Q22) records `isInitialLogin` and `isReloadingUi` of the first
  `PLAYER_ENTERING_WORLD`.
- `FishingMasteryProbeDB.marker` holds `{ sessions, lastSessionId }` for the persistence check.

## Recorders

Started after the login snapshot on their own event frame. Log kinds:

| Kind               | Q        | Content                                                         |
|--------------------|----------|-----------------------------------------------------------------|
| `recorders_started`| -        | Subscribed, skipped (unsupported), and failed events            |
| `tooltip_hook`     | Q26      | Hook mode: `post_call` (TooltipDataProcessor), `on_show`, or none |
| `event`            | Q08 etc. | Traced event: `name`, `n`, redacted `args`, `secret` positions; UI messages add `msgName`; `UNIT_AURA` at most once per second with a `suppressed` count |
| `cast`             | Q06      | Channel start: spell ID, cast GUID (type, spell ID, cast ID), `C_Spell.GetSpellInfo`, `UnitChannelInfo`, duration |
| `context`          | Q07      | Follows each `cast`: professions, main-hand item ID, weapon enchant, buff/debuff spell IDs and timing, map chain, position, zone texts, server time, swimming/mounted/indoors, auto loot CVar |
| `loot`             | Q09      | `LOOT_READY`: `IsFishingLoot`, slot count, per slot info, type, link, item ID, sources |
| `item_info`        | Q24      | `C_Item.GetItemInfo` per new item ID; `cached = false` entries are followed by one after `ITEM_DATA_LOAD_RESULT` with `wait` |
| `attempt`          | Q08-Q15  | One fishing attempt: `outcome`, timing, bite time, messages, event names; `raw` events for `unknown` and conflicts |
| `tooltip`          | Q26      | World-object tooltip during a cast: line 1 text, line 2 shape only (max 3 per attempt) |

**Attempt outcomes:** `catch` (fishing loot), `getaway`, `early_click`, `invalid_target` (from UI
message global string names in `Attempt.MESSAGE_OUTCOMES`), `timeout` (stop within 0.5 s of the
channel end), `cancel` (interrupt or early stop), `unknown` (no duration, no stop after 90 s, or a
new cast before the stop). An attempt ends 1.5 s after the channel stop, or when the loot window
closes. Message names come from `GetGameMessageInfo` or, without it, from comparing the text with
the candidate global strings.

**Privacy:** chat events keep only the player's own text (sender GUID compared in memory) with
the own name replaced by `<player>`; other chat keeps `own = false` only. Player GUIDs become type
and segment count; game object, creature, pet, and vehicle GUIDs keep their object ID. The
`UNIT_SPELLCAST_SENT` target name is reduced to its shape. Positions are rounded to 0.1 % of the
map. Tooltip line 2 can name another player and is reduced to its shape plus `hasOwnName`.

## Guided Test Run Window

`/fmp` shows or hides the window; it also opens by itself on the very first login. It shows the
current step ID, title, instructions, a live counter (e.g. "Catches: 3 / 5"), prerequisites, why
the step matters, and the linked question IDs. S0 adds the login snapshot result and the log file
path; S15 explains `/reload`, logout, and the hand-over. The window never triggers game actions.

| Button        | Effect                                                                  |
|---------------|-------------------------------------------------------------------------|
| **Start**     | Only on steps with a target; logs `step_start` and resets the step's counters |
| **Done**      | Logs `step_done` (count, target, outcome summary, `auto`) and moves on   |
| **Skip**      | Asks for a reason (no item / no location / other) and logs `step_skip`; optional steps skip at once with reason `optional` |
| **Back**      | Goes back one step to redo it; logs `step_back`                          |
| **Checklist** | Shows all steps with open, done, or skipped                              |

- Counting runs only while the step is started. `attempt` log entries count as `attempt` and as
  their outcome (`catch`, `timeout`, `cancel`, `getaway`); `tooltip` entries count as `hover`;
  `probe_check` entries count as `check`. Reaching the target logs `step_done` with
  `auto = true`, moves to the next step, and plays the ready-check sound.
- S1 and S2 log a `context` entry (phase `done`) when Done is pressed; S9 logs one on Start.
- Every log entry carries the current step ID; the step changes on Done, Skip, and Back.
- `FishingMasteryProbeDB.progress` keeps `step`, `started`, `status`, `counts`, `outcomes`,
  `reasons`, `window` (position), and `autoOpened`, so the run resumes after `/reload`.

## Helper Tests (Step S14)

Two opt-in tests, run with buttons that S14 shows after **Start**. Both are skipped in combat
(`InCombatLockdown`): the press logs `probe_skip` with `reason = "combat"` and the window says why.

- **Enable test key (S14a, Q28):** creates a `SecureActionButtonTemplate` button
  (`type = "spell"`, spell from the last recorded catch, else the fishing profession name from
  `GetProfessions` / `GetProfessionInfo`) and binds `CTRL-SHIFT-F` to it with
  `SetOverrideBindingClick`. The player presses the key once; the probe logs the press and whether
  a fishing channel started within 2 seconds. The binding is removed after the result, when S14 is
  left or finished, and on `PLAYER_LOGOUT`; during combat the removal waits for
  `PLAYER_REGEN_ENABLED`. The probe never casts without the key press.
- **Send self-whisper (S14b, Q27):** registers the prefix `FMProbe`, sends the fixed text
  `FMProbe self-test 1` via `WHISPER` to the player's own character, and waits 5 seconds for
  `CHAT_MSG_ADDON`. Messages with other prefixes are ignored and never logged.
- The button is the probe's only named frame (`FishingMasteryProbeTestButton`), because
  `SetOverrideBindingClick` takes a frame name.

| Kind            | Q        | Content                                                          |
|-----------------|----------|------------------------------------------------------------------|
| `helpers_env`   | Q28      | At login: existence of `loadstring_untainted` (secure snippets) and the binding and addon message APIs, `C_XMLUtil.GetTemplateInfo`, combat state |
| `probe_key`     | Q28      | Test key actions: `enable` (bound, spell source, `ActionButtonUseKeyDown`), `press` (`down`), `disable` (reason), `clear_deferred` |
| `probe_message` | Q27      | `sent` (send result) and `late` (receipt after the timeout)      |
| `probe_skip`    | Q27, Q28 | Test skipped in combat                                           |
| `probe_check`   | Q27, Q28 | One result per test run; counts toward the S14 target. S14a: template, bound, presses, `channelStarted`, delay, spell ID, `matchesSpell`. S14b: register and send results, `received`, `fromSelf`, `sameText`, channel, delay |

The own name is used only as the whisper target and for the `fromSelf` comparison; send errors
have it replaced by `<player>`.

## Commands

| Command       | Effect                                                     |
|---------------|------------------------------------------------------------|
| `/fmp`        | Shows or hides the guided run window, then the help: commands, current step, expected log file path |
| `/fmp help`   | Help only                                                  |
| `/fmp status` | Session ID, version, entry count, dropped entries, errors, login snapshot size, attempt count and last outcome, guided run step and counter |
| `/fmp report` | Builds the per-question summary (Q01-Q32), stores it as a `report` log entry, and shows it in a scrollable window |
| `/fmp export` | Shows the whole log as copyable text (pages of at most 200,000 characters) |
| `/fmp reset`  | Asks for confirmation, then clears the log and the guided run (back to S0) and records the login snapshot again |

## Report

One row per question: status, number of matching log entries, and a key value (e.g. Q01
"interface 16001, build ..., version ..."). The rules are data in `Rules*.lua`.

| Status     | Meaning                                                                  |
|------------|--------------------------------------------------------------------------|
| `answered` | Enough matching entries (rule `min`, e.g. 5 catches for Q08) and the rule's completeness test passes |
| `partial`  | Some entries, but too few, incomplete (e.g. Q11 attempts that the classifier did not mark `early_click`), or the rule failed |
| `skipped`  | No entries and every step linked to the question was skipped              |
| `missing`  | No entries                                                                |

Earlier `report` entries are ignored. The report is a quick check during the run; the agent
evaluates the full log.

## Export Format

Each page starts with a header line
`{"cap":…,"dropped":…,"entries":…,"format":"fmp-export-1","page":1,"pages":N,"session":…,"version":…}`,
followed by one line per entry: `[t, step, q, kind, data]` as JSON with sorted keys. `|` is
written as `|` so the client edit box shows no color codes. The export holds the same
redacted content as the log.

## Reset

`log_reset` is the first entry afterwards (`removed` entry count, session ID, probe version),
followed by a new login snapshot (step `S0`). The guided run returns to S0 with all steps open;
the window positions and the first-login flag are kept. The S14 test key is removed if active.

## Running the Probe

Prerequisites: a Forever character with Fishing learned, a fishing pole, fishable water nearby.
Optional: a lure, a school or wreckage, a zone above your skill, buff food. About 30-45 minutes.

1. **Install:** create the junction (see [Install for In-Game Testing](../README.md#install-for-in-game-testing)),
   start the client, and enable **Fishing Mastery Probe** in the AddOns list.
2. **Start:** log in; the guided run window opens on the first login (otherwise type `/fmp`).
   `/console scriptErrors 1` shows Lua errors. If an earlier test left entries, run `/fmp reset`.
3. **Follow the steps** in the window; Start, Done, and Skip are explained there. `/fmp status`
   shows progress at any time.

   | Step | Do                                               | Step | Do                                   |
   |------|--------------------------------------------------|------|--------------------------------------|
   | S0   | Read the login snapshot, press Done              | S8   | Cast at land or shallow water once   |
   | S1   | Unequip the pole, press Done                     | S9   | Apply a lure, Start, catch 2 fish    |
   | S2   | Equip the pole (no lure), press Done             | S10  | Hover the bobber for 2 seconds       |
   | S3   | Auto loot off: catch 5 fish                      | S11  | School or wreckage: 2 catches (optional) |
   | S4   | Auto loot on: catch 3 fish                       | S12  | Zone above your skill: 1 get-away (optional) |
   | S5   | Click the bobber before the splash, twice        | S13  | Buff food or camp buff: 1 catch (optional) |
   | S6   | Let the bobber time out, twice                   | S14  | Test key and self-whisper            |
   | S7   | Cast and move or jump, twice                     | S15  | `/reload`, then log out              |

4. **Report:** before S15, type `/fmp report` and check the summary for `missing` questions you
   can still cover.
5. **File:** the client writes the log on `/reload` or logout to
   `World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\FishingMasteryProbe.lua`
   (client folder name to be confirmed in the run).
6. **Copy:** after logging out completely, copy that file to `probe-results/` in this repository
   (git-ignored, never committed). If the file cannot be found, use `/fmp export`, copy each page
   with **Select all** and Ctrl+C, and save the pages as `probe-results/export-<page>.txt`.
7. **Hand over:** tell the agent the file is in `probe-results/` and add the run date and any
   failures or surprises you noticed.
