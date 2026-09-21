# Port notes — Dungeon Recall, PWA → Godot

Written when the port was decided (2026-09-21), before any gameplay code existed.
These are the measurements the estimate was made from, so a later reader can see
whether the assumptions held instead of re-deriving them.

## The decision

Dungeon Recall (`jeniczek-pwa-rpg`, branch `test/auto-combat-redesign`) stays exactly
as it is — it is finished and playable. The port to Godot is what gets the combat
replaced, the mobile build fixed, and eventually a new coat of paint. Dark Story was
archived for it (`dark-story-final`, `dark-story-archive-2026-09`).

Why Godot and not a from-scratch web rewrite: performance. The PWA is a DOM renderer
with a PixiJS layer for combat — 142 `innerHTML` writes, 323 direct `style` writes and
208 `classList` toggles inside the game closure. None of that batches.

## What was measured, not guessed

**Data — ports mechanically.** 10 files in `src/data/*.ts` are pure object literals
referencing only each other. Concatenated in dependency order and evaluated as one
script they yield 36 tables: 205 items, 199 uniques, 186 affixes, 40 monsters in 5
themes, 3 classes with 11 enemy spells, 5 acts with bosses, 4 gem types, 3
difficulties, 12 elite affixes plus 81 prefixes and 124 suffixes. 226 KB of JSON.
The converter (`tools/import/convert.mjs`) does this in one run and is verified by
both `verify.mjs` (CI) and `tools/test_data.gd` (in-engine).

**Assets — ports unchanged.** 388 files, 38 MB. Monsters are square portraits
(52× 512², 8× 256², 3× 320²), item icons 256², 61 spell icons, 24 stop images,
22 music tracks. A portrait combat scene wants square images and these already are.

**The rewrite is the presentation and the combat.** `src/game.ts` is 12 910 lines:

| Area | Lines | Verdict |
|---|---|---|
| Combat (Whirlwind 1916, projectiles 921, sockets 805, opportunity dodge 794, arena 736, pack 243, act entry 473, hold-to-repeat 490, spells 656+243+73) | 6 808 | rewrite — most of it is DOM timing code |
| UI screens (inventory 842, craft 449, gamble 309, shop 284, town 281, map 160, hero 274, talents 204, items ref 270, chest 112) | 3 195 | rewrite as Godot Control scenes |
| Logic (state, progression, loot) | 2 184 | port/adapt — already partly modular |
| Audio + FX | 369 | port — same MP3s, `AudioStreamPlayer` |

Plus 3 094 lines of CSS across `index.html` (693, with 213 DOM ids) and
`public/style.css` (2 401). None of it survives.

**Deliberately dropped, not ported:** Whirlwind's tap-the-shown-button flurry,
Opportunity Dodge's reaction windows, the rapid-tap minigames. Together roughly
2 700 lines. They are interaction models for a DOM page that is watched while
tapped; in a portrait auto-combat arena they have nothing to attach to. If the new
combat wants reaction mechanics, they get designed fresh rather than transplanted.

## Port order

1. **Data foundation** — done. Tables in `data/`, reader in `scripts/data/game_data.gd`,
   CI gates, headless tests.
2. **Portrait arena** — done. `scripts/combat/battle.gd` is the fight as pure logic;
   `scripts/ui/arena_screen.gd` renders it. The screen owns no rules on purpose.
3. **Progression loop** — done. `scripts/combat/progression.gd`: 5 acts x 10 zones,
   bosses, 3 difficulties, the `getZoneMult` scaling table (Normal 1.0/+0.50,
   Nightmare 5.5/+0.72, Hell 12.0/+0.89 per zone), the D2 XP curve and attack table.
4. **Itemisation UI** — done. Inventory grid, belt, equip slots, the town and the
   five town services (shop, gamble, chest, craft, talent trees), plus gem and jewel
   socketing. **Still to do: class spells in the arena.** The spell tables are loaded
   and the talent levels are read, but only the auto-attack swing is wired up, so all
   three classes fight the same way.
5. **Save/load** — done. `user://` JSON. Note the PWA's key is `dungeonRecallV7` with a
   flat→2D `bossesDefeated` migration; a fresh port starts clean instead.
6. **Balance pass** — 40 monsters across 5 themes × 3 difficulties is the longest
   tail and cannot be shortened by tooling.

## Two things about the combat worth knowing before changing it

**Rules live in `battle.gd`, never in the screen.** The reason is testability: a
RefCounted that ticks in fixed 100 ms steps can be driven end to end headlessly, which
is how `tools/test_combat.gd` asserts 15 real fights terminate. The PWA's equivalent
was a 900-line `requestAnimationFrame` loop that also wrote DOM, so nothing about it
could be asserted at all. If a rule only exists inside `_process`, no test can reach it.

**`mb.baseDmg` is set nowhere in the PWA**, so the fallback in `dealPlayerDamage` is
the live damage path: `2 + level * 0.8 + weapon dmg + STR * 0.3`, with no crit and no
skill multipliers on a plain swing. Two consequences that surprised this port: a
level-60 hero with bare fists genuinely loses to the act 1 boss (fists are 1-2 damage),
and a hero with 0 STR hits like a level-1 one no matter their level, because damage
scales with attributes. Tests pin both directions so a later change to this is visible.

## The public URL

<https://jankoznar94.github.io/dark-story/> — reused as-is, because the web export is
published from this repository's `gh-pages` branch by the same CI step Dark Story used.
Nothing had to be reconfigured. Two consequences worth knowing:

- **Dark Story no longer answers on that URL.** Its web build was overwritten by the
  first successful deploy of this branch. It is still fully recoverable: check out
  `main` (or the `dark-story-final` tag), rebuild, and the old export comes back.
- The URL keeps the name `dark-story` because the repository does. Renaming the repo
  would change the URL to `/dungeon-recall/`; that is Jan's call, not a technical need.

## What to watch

- **Lazy data loading is load-bearing.** `game_data.gd` loads on first access, not in
  `_ready()`, because a `--script` tool never gets `_ready()` on a node it
  instantiates — a `_ready()`-only load made every tool report the port as empty.
- **Counts are asserted, not eyeballed.** An empty data set produces a game that boots
  perfectly and has no content, which is the failure mode here. Both data tests assert
  minimum counts and spot-check real values.
- **`data/*.json` is generated.** Edit `convert.mjs`, never the JSON.
