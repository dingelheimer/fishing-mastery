# Fishing Mastery - Notices

Fishing Mastery is free software under the GNU General Public License version 3 (see
`LICENSE.txt` in the package, `LICENSE` in the repository). The bundled data in `Data/` is
generated from the sources below; item, spell, quest, and zone names come from the game client at
runtime.

## CMaNGOS classic-db

https://github.com/cmangos/classic-db, GPL-3.0, commit
`37eeeeb1d4c12f00ded1b542e758f71d6135d391`.

Used for `Data/Zones.lua` (fishing loot, reference loot, base skill, season conditions) and
`Data/Journal.lua` (items, spells, vendors, trainers, quest rewards, loot sources, game events).
The rates are reconstructions of Classic, shown as "Classic estimate".

## AllTheThings Forever client exports

https://github.com/ATTWoWAddon/AllTheThings, commit `e15f5d9ceebc32a683a09ce2b6609e838a2fab94`,
World of Warcraft: Forever client build `1.60.1.70790`. Used for the `AreaTable`, `UiMap`,
`UiMapAssignment`, and `SkillLineAbility` rows in `Data/Zones.lua` and `Data/Journal.lua`.

```text
MIT License

Copyright (c) 2026 AllTheThings WoW Addon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

World of Warcraft is a trademark of Blizzard Entertainment, Inc. Fishing Mastery is not made or
endorsed by Blizzard.
