# Third-party notices

TopFit includes data that is generated from the third-party project below. This file carries the notices that
project's license requires.

## WoWSims Forever

- Project: <https://github.com/wowsims/forever>
- License: MIT
- Copyright (c) 2022 wowsims team

**What is derived from it.** Three data files are produced by the scripts in `tools/` from a clone of that project:

| TopFit file | What it holds | Where it comes from in the WoWSims Forever project |
| --- | --- | --- |
| `procdata.lua` | Proc chance, internal cooldown, trigger flags, duration and on-use cooldown of item effects | `assets/database/db.json`, `sim/core/spelldata/spells_auto_gen.go` |
| `setdata.lua` | Item set pieces and the flat-stat part of each set bonus | the item-set tables in the project's generated `wowsims.db`, and its spell data |
| `presets.lua` (the block marked "GENERATED SIM PRESETS") | Stat-weight presets, shown in the preset menu as "Sim: ..." | the EP-weight presets in `ui/specs/*/*/presets.ts`, and the rating conversions in `CombatRatings.txt` |

TopFit does not contain any WoWSims source code. The generated files only hold data (IDs, numbers and TopFit stat
keys), and each one starts with a header stating where it came from.

The project's authors also ask that anyone using it in their own project provide a user-visible link back to the
original project: <https://github.com/wowsims/forever>. TopFit does this in `readme.txt` and in the credits line
of the in-game About panel.

### License text

```
MIT License

Copyright (c) 2022 wowsims team

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

## Blizzard Entertainment

World of Warcraft and related names are trademarks of Blizzard Entertainment. The game data the files above
describe (items, spells, set bonuses) originates in the game client. TopFit is not affiliated with or endorsed by
Blizzard Entertainment or the WoWSims team.

## Embedded libraries

The libraries in `Libs/` (Ace3, LibStub, CallbackHandler, tekKonfig, ...) are distributed under their own licenses;
see the files in each library's folder.
