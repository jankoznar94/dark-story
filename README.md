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

Step 1 (data foundation) is done: tables ported, JSON committed, reader in place,
CI green-able. Combat, inventory UI, town and progression screens are **not** in
this port yet — they are written against these tables next.
