# Dungeon Recall (Godot)

Portrait auto-combat ARPG — the same game as the PWA `jeniczek-pwa-rpg`, rebuilt in
Godot 4.7 so the combat can be replaced and the mobile build can run natively.

## What this repository is

`jankoznar94/dark-story` used to hold **Dark Story**, an isometric 3D ARPG prototype.
That project is finished and archived — see the tags below. The repository is now
reused for the Dungeon Recall port, on branch `dr-godot`.

| | |
|---|---|
| **Archived project** | `dark-story-final`, `dark-story-archive-2026-09` (tags, on `main`) |
| **This port** | branch `dr-godot`, worktree `~/dr-godot` |
| **Playable (web)** | <https://jankoznar94.github.io/dark-story/> — the same URL Dark Story used |
| **Original game** | `jankoznar94/jeniczek-pwa-rpg`, branch `test/auto-combat-redesign` — unchanged |
| **Engine** | Godot 4.7.2, mobile renderer, landscape |
| **CI** | `.github/workflows/build.yml` — data verify, script load, data test, export Web/Windows/Android, publish to GitHub Pages |

## The one rule this port is built on

**Numbers are cheap to move; a DOM renderer is not.** So the game's data tables are
ported mechanically and everything that drew pixels is rewritten.

`src/data/*.ts` in the PWA → `data/*.json` here, one file per table, produced by
`tools/import/convert.mjs`. Nothing in this project may hardcode a monster, an item
or an affix again: read it from `scripts/data/game_data.gd`.

| Table | Count |
|---|---|
| ITEMS / UNIQUE_ITEMS | 205 / 199 |
| AFFIXES | 186 |
| MONSTER_DB | 40 monsters in 5 themes |
| CLASSES / CLASS_SKILLS | 3 (Barbarian, Assassin, Mage) |
| ENEMY_SPELLS | 11 |
| ACTS | 5, each with a boss |
| GEMS / DIFFICULTIES | 4 / 3 |

## Regenerating the data

```bash
node tools/import/convert.mjs \
  --src "/mnt/c/Users/Martin Fabian/Desktop/Zod-Files/pwa-game-auto-combat/src/data" \
  --out data
node tools/import/verify.mjs --data data      # asserts counts + spot checks
```

`convert.mjs` concatenates the TS files in dependency order and evaluates them as
one script — they are pure object literals that reference only each other, so this
is a faithful 1:1 port with no hand-transcription. Verify with `--check` first if
you only want the counts printed.

## Tests (all run in CI, all headless)

```bash
GODOT=~/tools/godot/godot4
$GODOT --headless --path . --import                              # generate .import cache
$GODOT --headless --path . --script res://tools/test_scripts_load.gd   # every .gd parses
$GODOT --headless --path . --script res://tools/test_data.gd           # tables loaded, counts
```

Each prints `*_ALL_PASS=true` on success. `test_data.gd` asserts counts rather than
just absence of errors on purpose: a converter that writes nothing produces a game
that boots fine and is empty.

### Verifying the DEPLOYED build

CI being green says the pipeline ran, not that the published bytes work. To check what
a player actually downloads, run the served pack directly — it prints the data report,
so an empty deploy is obvious:

```bash
curl -sL -o /tmp/live.pck https://jankoznar94.github.io/dark-story/index.pck
~/tools/godot/godot4 --headless --main-pack /tmp/live.pck --quit-after 120
# expect: tables=36 items=205 unique_items=199 affixes=186 classes=3 monsters=40
#         acts=5 enemy_spells=11 gems=4
```

## Layout

```
data/              36 JSON tables (generated — never hand-edit)
scripts/data/      game_data.gd — the single reader for every table
tools/import/      convert.mjs (PWA -> JSON), verify.mjs (CI gate)
tools/             headless tests
assets/            portraits, item/spell/gem icons, stops, sfx, music
.github/workflows/ build.yml — the whole pipeline
```

## Status

Steps 1-5 of the port are done: the data foundation, the portrait arena, the
progression loop, the whole itemisation loop and save/load.

| | |
|---|---|
| Data | 36 JSON tables (generated from the PWA), one reader, counts asserted |
| Itemisation | generator, affixes, Magic Find, loot priority chain, stacking, socketing |
| Inventory + town | character sheet, belt, equip slots, town hub, save/load |
| Town services | shop (progress-gated), gamble (level-gated), chest, craft, talent trees |
| Combat | one fight as pure logic, ticked at 100 ms; arena screen renders it |
| Class spells | the barbarian's ten, cast from the arena bar: talent-gated, mana-paid, cooldowned |
| Progression | 5 acts x 10 zones, bosses, 3 difficulties, D2 XP curve, attack table |
| Tests | 9 headless suites, all gates in CI |

**Not in this port yet:** the assassin's and the mage's class spells (their mechanics
need combo points, a spell school and enemy DoTs, which this port has no home for yet —
they are refused with a reason rather than faked); Whirlwind, deliberately not ported
(its PWA mechanic is a tap-the-shown-button flurry, an interaction model for a DOM page);
the balance pass across 40 monsters x 3 difficulties; the reaction mechanics.

**Every class runs on mana**, the barbarian included — `CLASSES.json` says
`resource: 'mana'` for all three, and his warcries are paid out of the same pool the
mage's firebolts are. A port note once claimed otherwise and hid his mana bar in the
arena; if you see that claim again, it is wrong.

The combat split is deliberate and worth keeping: `scripts/combat/battle.gd` owns
every rule and `scripts/ui/arena_screen.gd` owns none. That is what lets
`tools/test_combat.gd` drive 15 real fights headlessly and assert they terminate.
