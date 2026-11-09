# CurseForge Project Page

Text for the CurseForge project "Fishing Mastery Forever" (owner decision 2026-11-07: the name
says the addon is for WoW: Forever; in game it stays "Fishing Mastery", and the folder and saved
data names stay `FishingMastery`). Paste the summary into the project's summary field and the
description into the description editor (Markdown). Keep it in step with the
[README](../README.md).

**Project settings:** game World of Warcraft, flavor Forever, category Professions, license
GPL-3.0, source `https://github.com/dingelheimer/fishing-mastery`, issues on the same repository.
**Logo:** `docs/images/logo-400.png` (400 × 400; `logo-1024.png` if a larger one is asked for),
drawn by `tools/draw_logo.py`.
**Images tab:** `docs/images/stats-overview.png`, `hud-card.png`, `journal-fish.png` (the README
screenshots of 1.1.0), `zones.png`, `bite-times.png`, `skill.png`, `sessions.png` (1.1.0;
`sessions.png` shows the owner's character name, accepted by the owner on 2026-11-09).

## Summary

Fishing statistics, getaway risk, and a fish journal for WoW: Forever: every cast counted, every
rate with a confidence range, Classic estimates next to your own catches.

## Description

**Fishing Mastery Forever** records every fishing cast you make in World of Warcraft: Forever and
turns it into numbers you can trust.

### What you get

- **One window** with side tabs like the Professions window: Statistics, Journal, Helpers, and
  Settings.
- **HUD card:** the water with its getaway risk, your skill bar, the lure with its time left or the
  one that would help, catches, success rate, catches per hour, the last catch, and the water's
  fish you have not caught there yet. Or one compact line.
- **Statistics** with eight tabs: Overview, Fish, Zones, Failures, Bite times, Sessions, Skill,
  Compare. Every rate has a 95 % range; small samples show counts only.
- **Journal:** every fish (caught or not) with where it bites and the skill it needs; every water
  colored for your skill; recipes that use fish and which ones you know; fishing gear, lures,
  buff food, and ranks with what you own and your best possible skill.
- **Helpers** (all off by default): a casting key, double right-click casting, a smart lure that
  puts on the cheapest lure that stops getaways, a louder splash, and hiding the interface while
  your line is out. They act only on your key press or click.
- **Tooltips** in the game's style, with the explanations behind Shift; item tooltip counts,
  the session summary, daily snapshots, and text export and import.

### Where the numbers come from

Your own casts, plus a Classic estimate from the CMaNGOS classic-db for fish lists, chances, and
base skill. Forever changed some waters, so the Classic estimate is always shown next to your own
numbers, never instead of them.

### Privacy

All data stays in your saved files. The addon sends nothing: no chat or addon messages. Exports
are text you copy yourself; `/fm export` leaves out character names and IDs.

### Commands

`/fm` (help), `/fm stats`, `/fm journal`, `/fm helpers`, `/fm settings`, `/fm summary`,
`/fm hud`, `/fm export`, `/fm import`. Left click on the minimap button opens the window.

### Credits

Data: CMaNGOS classic-db (GPL-3.0), AllTheThings Forever client exports (MIT). Full notices in
`NOTICE.md` inside the addon folder.

Bug reports with the Lua error text are very welcome on GitHub.
