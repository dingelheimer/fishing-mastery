# Fishing Mastery

A fishing companion for **World of Warcraft: Forever**. It records every cast you make and turns
it into numbers you can trust: how often you catch, how fast, what gets away and why, and what
each water should give you at your skill. A journal lists every fish, water, recipe, and piece of
fishing gear, with what you have already caught and owned.

Published on CurseForge as **Fishing Mastery Forever**; in game it is called Fishing Mastery. Free
and open source (GPL-3.0). Developers: see the [development reference](docs/development.md).

## Features

- **Tracking:** every cast and its outcome (catch, getaway, early click, timeout, cancel, invalid
  target), with bite time, loot, zone and subzone, skill, and lure. Your history is kept per
  character. The game writes it at logout or `/reload`, so a crash loses the casts since then; a
  reload reminder after two hours of fishing helps (`/fm reminder on|off`).
- **HUD card:** the water with its getaway risk, your skill bar, the lure with its time left or
  the one that would help, catches, success rate, catches per hour, the last catch, and the
  water's fish you have not caught there yet. Movable, scalable, see-through, or one compact line.
- **Session summary** after a session ends, in a small window or the chat.
- **One window** (left click on the minimap button) with a side tab per module, like the
  Professions window.
- **Statistics** (`/fm stats`) with eight tabs: Overview, Fish,
  Zones, Failures, Bite times, Sessions, Skill, Compare. Every rate shows a 95 % range, and small
  samples show counts only, so a lucky streak is not mistaken for a rule.
- **Journal** (`/fm journal`, Shift + left click on the minimap button):
  - **Fish:** every fish, trophy fish, container, and quest fish, caught or not, with where it
    bites, the skill it needs, the recipes that use it, its season, and your catches by month.
  - **Waters:** every water colored for your skill (or your best gear setup): red = no catch,
    orange = some fish get away, green = no getaways.
  - **Recipes:** recipes that use fish, which ones you know, and how many reagents you have. Open
    a profession window once to add the Forever recipes you know.
  - **Gear:** poles, gear, lures, buff food, fishing ranks, and the glove enchant, with what you
    own (bags, bank, equipped) and your best possible skill.
- **Helpers page** (`/fm helpers`): every helper with a check box and what it does right now.
- **Casting key:** bind a key to "Cast Fishing" on the Helpers page (or in Key Bindings, AddOns,
  Fishing Mastery) and cast without an action bar slot. It acts only when you press it.
- **Double right-click casting** (off by default): with a fishing pole in hand, a double
  right-click into the world casts Fishing.
- **Smart lure** (off by default): the casting key and the double right-click first put on the
  cheapest lure in your bags that stops getaways in this water, or your best one if none does, and
  nothing when your skill is enough. The HUD tooltip says which lure would help.
- **Louder splash** (off by default): with a pole in hand, sound effects at full volume and music
  and ambience off; your own volumes come back when you put the pole away or log out.
- **Hide the interface while fishing** (off by default): like Alt+Z when your line goes out; it
  comes back when you move, fight, get a whisper, and more. Your catches show at the top.
- **Item tooltips** show "Fishing Mastery: caught 37" and your best water for items you caught.
- **Backups:** daily snapshots, `/fm export` and `/fm import` as copyable text.

## Install

Install with the CurseForge app, or download the zip from the releases and unpack the
`FishingMastery` folder into `World of Warcraft\_forever_\Interface\AddOns`. Restart the game.
Your data stays when you update.

## Commands

| Command | What it does |
|---------|--------------|
| `/fm` | Help: version and all commands |
| `/fm stats` | Statistics page |
| `/fm journal` | Journal page |
| `/fm summary` | Summary of the open or last session |
| `/fm status` | The current session in the chat |
| `/fm hud show`, `hide`, `lock`, `unlock`, `reset` | Show, hide, lock, or reset the HUD |
| `/fm hud scale <0.5-2>`, `/fm hud layout card` or `compact` | HUD size and layout |
| `/fm settings` | Settings page (also right click on the minimap button) |
| `/fm contribute` | Your catch counts as text to share (no names, IDs, or times) |
| `/fm helpers` | Helpers page; also prints what the helpers did since login |
| `/fm minimap show` or `hide` | The minimap button |
| `/fm export`, `/fm export all`, `/fm import` | Copy your history out, or back in |
| `/fm backup list`, `/fm backup restore <n>` | Daily snapshots of your totals and settings |
| `/fm rebuild` | Count all totals again from your history |

## Where the Numbers Come From

- **Your own catches.** Everything you see as "you" or "own" is counted from your casts.
- **Classic estimate.** The fish lists, drop chances, and base skill per water come from the
  CMaNGOS classic-db, a reconstruction of 1.12 Classic. Forever changed some waters and added new
  fish, so the addon always shows the Classic estimate next to your own numbers and marks fish
  "not in the Classic data". Seasons and day/night windows are Classic rules, marked
  "unconfirmed" until your catches show them.
- **The game client.** Item, zone, spell, and quest names, gear tooltips, and your recipes are read
  from the client, so every language works.

Full credits and licenses: [NOTICE.md](FishingMastery/NOTICE.md).

## Privacy

- **All data stays on your PC**, in the addon's saved files in your `WTF` folder. The addon never
  sends anything: no chat messages, no addon messages, no network.
- The saved file holds your casts (time, place, skill, loot), your settings, and for each of your
  characters its name and character ID, so the addon can tell them apart. No other player's name,
  no chat text, no account name.
- `/fm export` shows one character's history as text **without** its name or ID; it still holds
  the time and place of every cast. `/fm export all` is a full backup **with** names and IDs:
  keep it private.
- `/fm contribute` shows your catch counts to share: per area and skill band, summed over your
  characters, with a random token (`/fm contribute new-token` makes a new one). No names,
  realms, character IDs, subzone texts, or times.
- Nothing leaves the game unless you copy it out yourself.

## Problems and Ideas

Open an issue on the project's GitHub page. Please add your client language, what you did, and
any Lua error text (`/console scriptErrors 1` shows Lua errors). `/fm` lists the last addon errors.

## License

GPL-3.0, see [LICENSE](LICENSE). Bundled data: CMaNGOS classic-db (GPL-3.0) and the AllTheThings
Forever client exports (MIT), see [NOTICE.md](FishingMastery/NOTICE.md). World of Warcraft is a
trademark of Blizzard Entertainment, Inc.; this addon is not made or endorsed by Blizzard.
