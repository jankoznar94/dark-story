extends RefCounted
class_name SurvivorRun
## SurvivorRun — the RULES half of the new fight: a run through a procedurally dressed
## arena where the hero MOVES CONTINUOUSLY, kills what he walks into, and picks up loot.
##
## This replaces `battle.gd` (the duel) as the port's combat. It is the same split that
## made the duel testable: this file owns every number and draws nothing, so a headless
## test can drive a whole run; `survivor_screen.gd` only reads it and paints.
##
## What it deliberately does NOT do (yet): spells, talents, monster spells, XP/levels,
## collision against props. Those are the next slices — see the report on the branch.
##
## Timing: the caller pumps `step(dt, move)` with a FIXED dt (1/60 s). A fixed step is
## what keeps the run reproducible from a seed, which is what makes the tests meaningful.

const ItemGen := preload("res://scripts/items/item_gen.gd")
const Progression := preload("res://scripts/combat/progression.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const RunSpells := preload("res://scripts/combat/run_spells.gd")
const PlayerSpells := preload("res://scripts/combat/player_spells.gd")
## The zone's look is a DATA table (`scripts/ui/zone_theme.gd`): which ground tile, which palette
## and — since Nov 2026 — which TERRAIN FEATURE (swamp boardwalk, river with a bridge) the area
## is built with. Reading the same table the screen paints from is what keeps "a bog" one idea.
const ZoneThemeData := preload("res://scripts/ui/zone_theme.gd")
## Print the terrain build's own numbers while it runs. Off in the game; `tools/probe_terrain.gd`
## is the proper instrument.
const DEBUG_TERRAIN := false
const Sfx := preload("res://scripts/audio/sfx.gd")

## --- the arena -------------------------------------------------------------
## The world is bigger than the phone's viewport (390x844), so the camera FOLLOWS the
## hero and the run reads as travel instead of a fixed stage. These are world pixels.
## The world is the GRID, so it moves with `COLS`/`ROWS`: a hand-written 1500x2100 stayed behind
## when the area tripled and culled every projectile and body below/above the old bounds.
const WORLD := Vector2(COLS * TILE, ROWS * TILE)
## The BASE walk. Deliberately slower than the 168 the first slice shipped: a boot affix that
## adds 20 % has to be FELT, and a bonus measured against an already-fast walk reads as noise.
## `moveSpeed` from gear multiplies this — see `hero_speed()`.
const HERO_BASE_SPEED := 140.0
## Everything in the game is additive percent, and a stacking cap keeps two lucky boots from
## turning the hero into a projectile.
const MAX_SPEED_PCT := 60
## The bodies are the PORTRAIT DISCS, so the collision radius is the disc's own radius. One
## number for both sides: a melee reach that is bigger than the gap between two bodies is a
## reach that hits from another postcode.
const BODY_RADIUS := 31.0
const HERO_RADIUS := BODY_RADIUS
const MON_RADIUS := BODY_RADIUS

## --- the fight ------------------------------------------------------------
## ONE reach per HAND, taken from the weapon that hand holds: a two-handed axe is a longer arm
## than a fist, and a fight where every weapon reaches exactly 76 px makes the whole gear table
## decorative. `ATTACK_RANGE` is the ONE-HANDED BLADE value and stays the fallback for an empty
## or unknown weapon.
##
## The rule is about BODIES, not centres: a target is hit when its own disc crosses the drawn
## circle. Jan's report ("the enemy has to be deep inside the radius before the hero swings")
## was this rule measured to the wrong point: with the check on centres, a 31 px body had to be
## half-way through the circle before it registered, which reads as point-blank. `HIT_REACH`
## adds the target's radius, so the blow lands the moment a portrait touches the drawn circle.
const ATTACK_RANGE := 76.0
const HIT_REACH := ATTACK_RANGE + MON_RADIUS
const WEAPON_REACH := {
	"fists": 58.0, "claws": 62.0, "blade": 76.0, "axe": 80.0, "blunt": 72.0,
}
const TWO_HAND_REACH_BONUS := 10.0
const CONTACT_PAD := 3.0
## The shortest beat a dual-wielded PAIR may take, in seconds. The pair's interval is the harmonic
## mean of the two hands (both rates summed), so two IAS-stacked daggers could otherwise push the
## alternation below the animation's readability.
const PAIR_FLOOR := 0.15

## --- facing ----------------------------------------------------------------
## Jan, Nov 2026: "hrdina může útočit na nepřítele jen když je nepřítel v dosahu zbraní a když je
## hrdina otočen k nepříteli čelem. Teď hrdina útočí i za sebe, když utíká a to je příliš velká
## výhoda."
##
## So a swing needs TWO things: the body inside the hand's drawn reach AND in FRONT of the hero.
## The front is the half-plane the hero faces — 90° each side of `facing`, i.e. `dot >= 0`.
##
## ⚠️  Jan, Nov 2026 CHANGED WHO TURNS THE HERO: "Hrdina neútočí automaticky. Jen když hráč drží
## tlačítko útoku … hra vybere target podle směru, kterým hráč kouká, hrdina k němu automaticky
## směřuje pohyb a útočí." So the facing is the PLAYER's walk direction until an attack is held;
## from then on the ASSIST owns it and points the hero at the chosen target (see `_pick_target`).
## Walking still outranks the assist's own step — the player may always spend movement.
const FACING_MIN_DOT := 0.0

## --- the held attack and the target assist ---------------------------------
## A swing happens ONLY while `attack_held` (or an offensive spell button held) is true. With no
## thumb free to pick a target on a phone, the game picks it: candidates are the bodies in FRONT
## of the hero within `TARGET_RANGE`, ranked by their distance PLUS their missing health — so a
## nearly-dead body a little further away wins over a healthy one in the face. `TARGET_HP_WEIGHT`
## is that trade in pixels: 160 means "a full-health body must be 160 px closer to be preferred
## over a corpse-to-be". The switch margin stops two equal candidates from stealing the target
## from each other every frame (which reads as the hero twitching).
const TARGET_RANGE := 280.0
const TARGET_HP_WEIGHT := 160.0
## How much a body being OFF the aim direction costs it, in pixels. 120 means a body 60° off the
## stick is penalised 60 px: pushing the stick at the enemy on the right beats a slightly nearer
## one straight ahead, which is exactly Jan's "přejeď zleva doprava a útok se přesměruje".
const TARGET_AIM_WEIGHT := 120.0
const TARGET_SWITCH_MARGIN := 0.12


## The reach of one weapon, in world pixels. Static so the screen can ask the same question the
## rules answer, and so a test can assert the table without building a run.
static func reach_for(weapon: Dictionary) -> float:
	if weapon.is_empty():
		return ATTACK_RANGE
	var r: float = float(WEAPON_REACH.get(str(weapon.get("weaponType", "fists")), ATTACK_RANGE))
	if bool(weapon.get("twoHand", false)):
		r += TWO_HAND_REACH_BONUS
	return r

## --- ranged units ----------------------------------------------------------
## The PWA had no notion of range: every monster walked into the hero and the damage was a
## contact tick. Ranged attacks are NEW in the port (Jan, Nov 2026), so this is where the
## distance between the two sides finally means something.
##
## A thrower stops at `KEEP_RANGE` and shoots; it walks BACKWARDS when the hero closes inside
## `RETREAT_RANGE`, which is the whole point — the player has to spend movement to get into
## reach instead of just waiting for the pack to arrive. The retreat is slower than the hero
## on purpose: a caster that can outrun a player makes a fight that never ends.
const KEEP_RANGE := 232.0
const RETREAT_RANGE := 168.0
const SHOOT_RANGE := 470.0
const PROJECTILE_SPEED := 268.0
## The HERO's bolt: faster than a thrown orb (it is magic, and the player is spending mana on it),
## small, and gone after 1.4 s so a miss cannot fly around the area forever.
const BOLT_SPEED := 620.0
const BOLT_RADIUS := 9.0
const BOLT_LIFETIME := 1.4
## 12 px on a 1077 px-wide canvas: the first pass was 9 and it read as a speck of dust on the
## grass rather than as a threat. The orb is a BODY, so it has to look like one.
const PROJECTILE_RADIUS := 12.0
const PROJECTILE_LIFETIME := 3.2
## Rarach's orb. Green because it is a poison bolt, and the fight has to be readable at a
## glance: a green ball crossing the arena is a different threat from a body walking at you.
const ORB_COLOUR := "#7ac74f"

## Which kinds keep their distance.
##
## Two inputs, in this order:
##   * a row that already says `caster` is a spell thrower in the PWA's own vocabulary;
##   * `RANGED_FACES` — the port's own list of kinds that throw rather than touch. Rarach was
##     the first: in the PWA he was a melee imp carrying a `poison_bolt` he never cast, which
##     is exactly why the fight had no distance in it.
##
## ⚠️  This table lives in the PORT and not in `data/MONSTER_DB.json`: `data/` is generated
## from the PWA by `tools/import/convert.mjs`, so a hand edit there disappears on the next
## conversion and the rule silently reverts.
const RANGED_FACES := ["assets/monsters/lesni_rarach.png"]

## --- the area ---------------------------------------------------------------
## The run happens in ONE FINITE AREA, not in an endless arena. The world is cut into a grid of
## cells; every cell except the hero's own clearing holds ONE PACK, and a pack only EXISTS once
## the hero walks close enough to its cell. That is the Diablo-2 shape Jan asked for: an enemy
## is a DISCOVERY, not a trickle that arrives from off screen, and walking into a new cell is
## the decision that starts a fight.
##
## The cells are laid out so the hero's spawn point is the EXACT middle of the middle cell: that
## is what gives him a clearing to start in, and it keeps every neighbouring pack at 436 px or
## more — outside ACTIVATE_RADIUS, so nothing wakes on the first frame.
## ⚠️  THE AREA IS A CORRIDOR NOW, NOT A RECTANGLE. It used to be the whole 1500x2100 world
## with a wall inset, i.e. one open field with nine packs scattered on a 3x3 grid — Jan: "Oblast
## by neměla být čtverec nebo obdélník. Spíš takový jakýsi koridor, který má různé zatáčky, atd.
## Teď je mapa strašně jednotvárná a nic neříkající."
##
## The walkable world is a GRID OF CELLS (`TILE` px), and only the cells the generator carved are
## floor: a wide start clearing, then a winding corridor that turns left and right on its way up
## the map, widening into the occasional room. Everything else is rock the hero cannot enter.
##
## The corridor is also what makes the FOG OF WAR read: `explored_cells` is one flag per cell, and
## a cell the hero has never been near is drawn black — Warcraft 2's shape, which is what Jan
## asked for ("tam, kde hráč ještě fyzicky nebyl, by to mělo být černé, nebo minimálně zašedlé").
const TILE := 60.0
## ⚠️  THE AREA'S SIZE. Jan: "Oblasti jsou stále hrozně krátké a na jedno brdo. Každá oblast by
## měla být minimálně 3x rozsáhlejší než teď." The old grid was 25x35 cells (1500x2100 px) and
## the corridor in it measured ~3 600 px from the entrance to the exit; this grid is 33x61
## (1980x3660 px) and the winding path inside it runs ~3x as long. The generator's legs and
## turns were widened with it (see `_build_corridor`), because a taller grid alone only makes
## a longer pipe.
const COLS := 41
const ROWS := 99
## Half-width of a corridor leg, in cells. 3 = a 7-cell leg (420 px): two hero discs pass a pack
## with room to spare. It was 2 (300 px) and Jan: "teď je příliš úzký s přímý" — a 5-cell tube
## reads as a pipe, not as a dungeon corridor. Legs VARY between `CORRIDOR_HALF_MIN` and
## `CORRIDOR_HALF_MAX` so the area does not read as one extruded profile.
const CORRIDOR_HALF := 3
const CORRIDOR_HALF_MIN := 2
const CORRIDOR_HALF_MAX := 4
## Half-width of the clearing the hero starts in, in cells (9x9 = 540 px).
const START_ROOM_HALF := 4
## Half-width of the occasional wider room along the corridor. 4 = 9x9 (540 px), enough for a
## pack to form up and for the player to circle it. Rooms vary from `ROOM_HALF_MIN` to
## `ROOM_HALF_MAX`, and the big end is a real cavern rather than a slightly wider corridor.
const ROOM_HALF := 4
const ROOM_HALF_MIN := 3
const ROOM_HALF_MAX := 7
## How far the hero sees, in world px. Also the radius that marks cells as explored.
const FOG_REVEAL := 300.0
const AREA_MARGIN := 96.0
## The largest group one cell can hold: an elite pack. A normal cell holds ONE body.
const PACK_MIN := 1
const PACK_MAX := 4
## How far a pack's members scatter from its cell centre, and the least gap between two of them.
## The gap is bigger than one disc (62) on purpose: a pack is a formation, not a pile.
const ZONE_JITTER := 104.0
const PACK_SPACING := 70.0
## How long the corridor should RUN, in world px, entrance to exit. This is the number Jan's
## "3x rozsáhlejší" turns into: `tools/probe_area_size.gd` measures it, and the old corridor
## measured 3 240-4 200 px on five seeds. See `_build_corridor` for why it is a target and not
## a by-product of the grid size.
const PATH_TARGET := 12800.0
## How far apart along the corridor one spawn cell sits. It was 330 when a cell held a pack of
## 2-4; the default is a SINGLE body now, so the cells are closer together to keep the same
## density of enemies per metre walked. 300 (was 220) is the DENSITY dial for the 3x area: the
## path is three times longer, and holding the old spacing would have tripled the bodies per
## area together with it — more kills, a longer run and the same "full bag" as before.
const CELL_SPACING := 380.0
const ACTIVATE_RADIUS := 330.0
## Two spawn cells must be at least this far apart in SPACE (not along the path), so that walking
## into one pack does not wake the next. `PACK_MIN_GAP > 2 * ACTIVATE_RADIUS` leaves a margin for
## the pack's own members walking outward.
const PACK_MIN_GAP := 460.0

## --- what a cell holds ------------------------------------------------------
## Jan, Nov 2026: "Nespawnoval bych je vždy jako skupiny. Spíš jako jednotlivce. Někdy blízko
## sebe, někdy dál, ale aby to ve výchozím stavu nebyly skupinky namačkané na sebe."
##
## So the DEFAULT cell is one wanderer. A second stray in the same cell is the minority, and it
## stands `STRAY_GAP` away from the first — two separate bodies, not the old 70 px formation.
##
## On top of that, two special kinds, the duel's own two:
##   CHAMPION  2-4 bodies of ONE kind, 1.6x HP / 1.3x damage, 400 % XP, better loot.
##   ELITE     one leader with a D2 affix (auras included) plus ELITE_MINIONS slaves that
##             inherit the aura's damage bonus. 500 % XP for the elite AND its minions, and
##             the best loot table in the game so far.
const STRAY_PAIR_CHANCE := 0.28
const STRAY_GAP_MIN := 170.0
const STRAY_GAP_MAX := 300.0
const CHAMPION_PACK_CHANCE := 0.22
const CHAMPION_MIN := 2
const CHAMPION_MAX := 4
const CHAMPION_HP_MULT := 1.6
const CHAMPION_DMG_MULT := 1.3
const CHAMPION_XP_MULT := 4.0
const ELITE_PACK_CHANCE := 0.5
const ELITE_MINIONS := 3
const ELITE_HP_MULT := 2.5
const ELITE_DMG_MULT := 1.5
const ELITE_XP_MULT := 5.0
## How far a minion stands from its elite: a ring tight enough to read as one pack.
const ELITE_RING := 86.0
## How far from the hero a woken pack is placed. The phone screen is 390x844, so half of it is
## 195 px across and 422 px down: a pack that appeared at 330 would POP into view in the middle of
## the field, which is exactly the seam Jan would notice. At 470 the bodies arrive from OFF the
## screen and walk in, which also gives the player the beat of hearing/seeing them come.
const WAKE_MIN_DIST := 470.0

## --- spawning -------------------------------------------------------------
## The density is the design dial. The Dark Story pacing rule banned hordes; the survivor
## loop needs a CROWD, so the number lives here, named, and the slice stays at 16 alive.
## Was 16 on the first pass and Jan's report was "there are too many enemies". Seven is a pack
## you can read and back away from; the arena's own pacing lesson is that a crowd on a phone
## screen is not difficulty, it is noise.
##
## A pack larger than the remaining room WAITS instead of spawning over the cap, so two
## neighbouring cells can never add up to a wall of bodies.
const MAX_ALIVE := 7
const SPAWN_RADIUS_MIN := 300.0
const SPAWN_RADIUS_MAX := 430.0
## How far the hero may walk from a portal he stepped out of before it closes.
const PORTAL_CLOSE_DIST := 150.0

## --- loot ------------------------------------------------------------------
const PICKUP_RADIUS := 30.0
const MAGNET_RADIUS := 96.0
const MAGNET_SPEED := 430.0

var _data: Node
var _state
var _find_item: Callable
var _prog
var _loot: LootSystem
var _gen: ItemGen
var rng := RandomNumberGenerator.new()

var act_id := 0
var player_pos := Vector2.ZERO
## Where the hero is pointing. The PLAYER owns it by walking, and the target assist takes it over
## while an attack is held (see `FACING_MIN_DOT`); RIGHT is the starting direction, which is also
## what a still hero who never walked is facing.
var facing := Vector2.RIGHT
## THE AIM — the half-plane the target assist looks into, and NOT the same thing as `facing`.
## Jan, Nov 2026: "když hráč drží útok a během toho mění směr, tak by se měl target změnit. Pokud
## stojí třeba tři nepřátelé vedle sebe a hráč přejez zleva doprava, tak by se měl útok přesměrovat
## na toho vpravo."
##
## So the aim is written ONLY by the player's stick (and by the assist's turn-around when he stands
## with nothing in front), while `facing` follows the target so the swing lands where it looks.
## Keeping one field for both was the bug: `facing` was overwritten by the target's direction every
## step, so the half-plane never moved and the assist never had a reason to re-pick.
var aim := Vector2.RIGHT
## Is the attack button (or an offensive spell) held RIGHT NOW? The screen owns the gesture and
## writes this every frame; the rules read it and nothing else. Default FALSE — a run that has
## not been told the player is holding anything does not attack, which is Jan's new rule.
var attack_held := false
## The spell whose button is being HELD, or "". A held offensive spell repeats on its own
## cooldowns (the GCD paces it) and uses the same target picker as the weapon.
var held_spell := ""
## The body the assist picked for the CURRENT frame, as a monster id (-1 = nothing in front).
## Kept as an ID because an index is invalid the moment a kill removes an entry.
var target_id := -1
var hp := 1
var max_hp := 1
var defense := 0
## MAIN hand's damage range and crit (the fields the HUD and the older tests read).
var dmg_min := 1
var dmg_max := 2
var crit_chance := 0.0

## --- the two hands ---------------------------------------------------------
## Each hand is a WEAPON with its own reach, its own interval and its own roll. `off_weapon`
## stays empty for a class that cannot dual-wield, for a two-hander, and for a shield.
var main_weapon: Dictionary = {}
var off_weapon: Dictionary = {}
## Seconds per swing, from `Progression.swing_time` — the weapon's own `swingMs`, shortened by
## DEX and by Increased Attack Speed on the weapon and the gloves, floored at 0.45 s. Two hands,
## two intervals: the second weapon never inherits the first one's pace.
var main_swing := 0.85
var off_swing := 0.0
var reach_main := ATTACK_RANGE
var reach_off := 0.0
var dmg_off_min := 0
var dmg_off_max := 0
var crit_off := 0.0
## Percent from `moveSpeed` gear (boots), capped at MAX_SPEED_PCT.
var speed_pct := 0

var monsters: Array = []
## The area's own map: one entry per cell that holds a pack. `members` are the ROWS and their
## standing positions, decided at setup from the seed, so the layout is reproducible and a pack
## that has not woken yet is still a known quantity for a test.
var zones: Array = []

## --- cell terrain ------------------------------------------------------------
## `floor_cells` (below) is the WALKABLE mask every rule reads. `cell_kind` adds what the cell
## LOOKS like, which is what a swamp or a river needs: impassable water you cannot walk on, and
## a plank deck you can. KIND_GROUND and KIND_DECK are walkable; KIND_ROCK and KIND_WATER are not.
const KIND_ROCK := 0
const KIND_GROUND := 1
const KIND_WATER := 2
const KIND_DECK := 3
var cell_kind := PackedByteArray()
## Which edge the hero arrives through and which one he leaves by (0 bottom, 1 top, 2 left,
## 3 right). Random per zone, and never the same edge twice — Jan: "Východ nemusí být vždy
## vpravo nahoře. A vchod nemusí být vždy vpravo dole."
var entry_side := 0
var exit_side := 1
## The zone's terrain feature ("", "boardwalk", "river", "chasm"), resolved from `ZoneTheme`.
var feature := ""
## The walkable grid, one byte per cell (1 = floor). `COLS` x `ROWS`, index `cy * COLS + cx`.
## Built by `_build_corridor()`, read by the walk (`walkable`), the spawns and the screen.
var floor_cells := PackedByteArray()
## Fog of war, one byte per cell: 1 once the hero has been within `FOG_REVEAL` of it. A cell
## that is still 0 is drawn BLACK — nothing about the map leaks before he walks there.
var explored_cells := PackedByteArray()
## Bumped every time a cell flips 0 -> 1. The screen bakes the fog veil into a texture and
## re-bakes it ONLY when this changes, so a frame with no discovery uploads nothing.
var explored_version := 0
## The corridor's centreline, in world px, from the start clearing to the far end. Packs are
## placed along it in order, so walking deeper is what raises the stakes.
var path_points: Array = []
## Where the hero starts: the middle of the start clearing.
var start_point := Vector2.ZERO
## Which zone of the act this map IS (`ActRun`). The layout is seeded from the act's seed and
## this index, so coming back to zone 3 shows the same dungeon.
var zone_index := 0
## The act's LAST zone is its boss zone (the PWA's `progress >= zones - 1`). The fight rules do
## not change; this is what the music and the HUD read.
var is_boss := false
## Where the waypoint stands: a few cells off the entrance, always on floor. Tap it to go to
## town; the act's record keeps this zone as the checkpoint.
var waypoint_point := Vector2.ZERO
## The exit to the NEXT zone — the far end of the corridor, guaranteed far from the entrance.
var exit_point := Vector2.ZERO
## The town PORTAL: where it opened (the spot the hero stood on when he used the scroll) and
## whether it is still open. Pure world state — the trip itself belongs to `Main`. Drawing it is
## what makes the return read as "I came out of that thing", and walking away from it closes it.
var portal_point := Vector2.ZERO
var portal_open := false
## Orbs in flight: {pos, vel, dmg, age, colour}. Simulated here, painted by the screen.
var projectiles: Array = []
## The HERO's own spells in the air (`thunderBolt`): {pos, vel, dmg, stun_ms, age, colour}.
## A targeted spell has to be SEEN travelling — an instant number over a portrait two hundred
## pixels away reads as a bug in the health bar, not as a bolt.
var bolts: Array = []
## Visual effects, aged on the run's own step and painted by the screen:
## {kind, pos, age, life, colour, data}. Kinds: "ring" (expanding shout waves), "flash"
## (the white blast of a Thunder Clap), "cracks" (its lightning), "shield" (the slam falling
## from above), "spiral" (a bolt's impact). Pure paint — no rule reads this list.
var effects: Array = []
var drops: Array = []
var numbers: Array = []
## Sound cues, drained by the screen every frame (battle.gd does the same with its log).
var events: Array = []

var kills := 0
## How many packs have WOKEN. It is the loot table's depth too (`_roll_drop` passes it), so a
## later pack pays better than the first one.
var wave := 0
var elapsed := 0.0
var gold := 0
var items_taken := 0
## Every item that reached the bag during the run, in the order it was picked up. Kept as the
## run's own record (`items_taken` alone can say how many but not which); the zone loop no
## longer prints a loot page for it.
var looted: Array = []
## XP this run paid into the save, and how many LEVELS that bought — the run levels the hero
## the way the arena's `apply_levels()` does.
var xp_gained := 0
var levels_gained := 0
## Every spawn cell has been emptied. It is a state the HUD may read; it does NOT end the run.
var area_cleared := false
## How long ago the last swing LANDED, in seconds (-1 = no swing yet). The renderer turns this
## into the lunge and the slash — the RULES never animate, they only say when and which way.
var swing_age := -1.0
var swing_dir := Vector2.RIGHT
## The OFF hand's own animation state. Two ages, not one: a 700 ms scimitar and a 1580 ms axe
## must not share a single arc, or the second weapon is drawn only as a mirror of the first.
var swing_age_off := -1.0
var swing_dir_off := Vector2.RIGHT

var finished := false
## "" | "dead". There is no "cleared": walking out of the exit is what advances the act, and
## the run does not crown the player for it.
var outcome := ""

# ============================================================================ spells
## The run's own spell session: mana, the global cooldown and the per-spell cooldowns live HERE
## (a session, like the duel's) and never on the save. The effects live in `run_spells.gd`; this
## side only owns the numbers a tick has to move.
var mana := 0.0
var max_mana := 0
var mana_regen_frac := 0.0
var spell_gcd_ms := 0
var spell_cooldowns: Dictionary = {}
## The two Shouts, as the numbers the swings and the damage taken actually read. A buff that
## writes a value nothing consumes is not a buff — see `_swing_hand` and `_take_damage`.
var buff_dmg_pct := 0.0
var buff_dmg_ms := 0
var buff_armor_pct := 0.0
var buff_armor_ms := 0
## Queued class spells, consumed by the next MAIN-HAND swing (the duel's rule).
var heroic_queued := false
var frenzy_queued := false
## Frenzy stacks: each landed main-hand hit inside the queue adds one (max 5), and each stack
## shortens BOTH hands by `lv + 1` % for FRENZY_MS.
var frenzy_stacks := 0
var frenzy_ms := 0

## Whirlwind — the flurry of PS presses. `ww_dirs` is the random sequence, `ww_deadline_ms` the
## time left to press the CURRENT one, counted on the run's own fixed step.
var ww_active := false
var ww_dirs: Array = []
var ww_index := 0
var ww_deadline_ms := 0
var ww_reaction_ms := 0
var ww_feedback := ""
var ww_landed := 0

var _main_clock := 0.0
## Kept at 0: there is no second clock any more (the hands alternate on `_main_clock`).
var _off_clock := 0.0
## Which hand takes the NEXT beat. False = main hand (the hero opens with it), and it flips on
## every landed swing while a second weapon is held.
var _next_hand_off := false
var _next_id := 0
## The hero's position at the START of the frame: the only honest place to send him back to
## when his own step would put him inside a body.
var _prev_pos := Vector2.ZERO


## `seed_value` is what makes a run reproducible: the tests drive one seed, the screen
## seeds from the clock. Passing 0 means "use entropy".
func setup(state, find_item: Callable, loot_system, act: int, seed_value: int = 0,
		zone: int = 0) -> void:
	_state = state
	_find_item = find_item
	_loot = loot_system
	_data = state.data_ref() if state.has_method("data_ref") else null
	act_id = act
	zone_index = zone
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	var hero: Dictionary = state.hero()
	_gen = ItemGen.new(_data)
	_prog = Progression.new(_data)
	max_hp = _gen.hero_max_hp(hero, state.equip(), find_item)
	hp = max_hp
	defense = int(_prog.total_defense(state.equip(), find_item))
	var roll: Dictionary = Progression.hero_dmg(hero, state.equip(), find_item)
	dmg_min = int(roll["min"])
	dmg_max = int(roll["max"])
	_read_hands()

	# The mana pool is the save's own (class base + INT + gear), and the run holds a FLOAT copy
	# so the regen can accumulate below 1 point — `_sync_mana()` writes the int back.
	max_mana = _gen.hero_max_mana(hero, state.equip(), str(state.data.get("heroClass", "")),
		find_item)
	mana = float(mini(int(hero.get("mana", max_mana)), max_mana))
	mana_regen_frac = 0.0
	spell_gcd_ms = 0
	spell_cooldowns.clear()
	buff_dmg_pct = 0.0
	buff_dmg_ms = 0
	buff_armor_pct = 0.0
	buff_armor_ms = 0
	heroic_queued = false
	frenzy_queued = false
	frenzy_stacks = 0
	frenzy_ms = 0
	ww_active = false
	ww_dirs.clear()
	ww_index = 0
	ww_deadline_ms = 0
	ww_reaction_ms = 0
	ww_feedback = ""
	ww_landed = 0
	facing = Vector2.RIGHT
	aim = Vector2.RIGHT
	# A new run starts with NOTHING held: the screen writes these from its own gesture state
	# every frame, but a stale `true` from the previous fight would make the hero swing on his own
	# for as long as it took the first frame to arrive.
	attack_held = false
	held_spell = ""
	target_id = -1

	monsters.clear()
	projectiles.clear()
	bolts.clear()
	effects.clear()
	drops.clear()
	numbers.clear()
	events.clear()
	_build_area()
	is_boss = zone_index >= _prog.total_zones(act_id) - 1
	# The hero starts in the middle of the start clearing, and the fog is lifted only around him.
	player_pos = start_point
	_reveal_around(player_pos)
	_prev_pos = player_pos
	kills = 0
	wave = 0
	elapsed = 0.0
	gold = 0
	items_taken = 0
	looted.clear()
	xp_gained = 0
	levels_gained = 0
	finished = false
	outcome = ""
	area_cleared = false
	portal_open = false
	portal_point = Vector2.ZERO
	_main_clock = 0.0
	_off_clock = 0.0
	_next_id = 0
	swing_age = -1.0
	swing_dir = Vector2.RIGHT
	swing_age_off = -1.0
	swing_dir_off = Vector2.RIGHT


## Snapshots the zone's WALKED state, so leaving it (waypoint to town, the leave button, walking
## through the exit) does not re-roll it on the way back. Jan: "zóny by se neresetovaly při
## každém odchodu do města. Při smrti ano, ale při použití waypointu a town scroll portálu ne."
##
## The layout is NOT copied: `setup()` rebuilds the identical corridor and pack positions from
## the act's seed and this zone's index. What is copied is everything the SEED cannot know —
## the packs that are awake, the ones already emptied, every living monster's position and hp,
## and the fog the player has lifted.
##
## The result goes to `ZoneMemory` (process memory, never the save), which is what makes the
## "sleep" reset — closing and re-opening the game — refresh every monster for free.
func snapshot() -> Dictionary:
	var zone_states: Array = []
	for z in zones:
		zone_states.append({
			"active": bool(z.get("active", false)),
			"cleared": bool(z.get("cleared", false)),
			"ids": (z.get("ids", []) as Array).duplicate(),
		})
	return {
		"hp": hp,
		"mana": mana,
		"monsters": monsters.duplicate(true),
		"drops": drops.duplicate(true),
		"zone_states": zone_states,
		"next_id": _next_id,
		"explored": explored_cells.duplicate(),
		"kills": kills,
		"wave": wave,
		"elapsed": elapsed,
	}


## Puts a `snapshot()` back over a freshly `setup()` run of the SAME act and zone. Returns false
## when there is nothing to restore, which is the normal case for a zone being entered first time.
##
## The hero arrives at the zone's ENTRANCE (`start_point`), never at the exact spot he left: a
## waypoint or a portal is a doorway at the start of the area, and restoring the exit-gate
## position would drop him at the far end of a corridor he is supposed to walk again.
##
## `hp` is clamped to the freshly computed `max_hp`: the hero may have bought or changed gear in
## town, and a restored 180 hp over a new max of 150 would be a free heal (or worse, a hero who
## cannot die). Mana is clamped the same way. Spell cooldowns, buffs and orbs in flight are NOT
## restored — they are a session, and a trip through town is a pause that ends them.
func restore(snap: Dictionary) -> bool:
	if snap.is_empty():
		return false
	player_pos = start_point
	hp = clampi(int(snap.get("hp", hp)), 1, maxi(max_hp, 1))
	mana = clampf(float(snap.get("mana", mana)), 0.0, float(max_mana))

	monsters.clear()
	var next_free := 1
	for m in (snap.get("monsters", []) as Array):
		if not (m is Dictionary):
			continue
		var rec: Dictionary = (m as Dictionary).duplicate(true)
		monsters.append(rec)
		next_free = maxi(next_free, int(rec.get("id", 0)) + 1)
	_next_id = maxi(int(snap.get("next_id", 0)), next_free)

	# Loot on the floor comes back too: a waypoint trip must never destroy an item the player
	# has already seen drop. A COLLECTED drop is gone from this list before the snapshot, so
	# restoring it cannot pay anything twice.
	drops.clear()
	for d in (snap.get("drops", []) as Array):
		if d is Dictionary:
			drops.append((d as Dictionary).duplicate(true))

	# Packs: awake, emptied and their ids line up with the monsters just restored, so
	# `_zone_clear_tick` keeps reporting the truth instead of waking a wiped pack again.
	var states: Array = snap.get("zone_states", [])
	for i in range(mini(zones.size(), states.size())):
		var st: Variant = states[i]
		if not (st is Dictionary):
			continue
		var z: Dictionary = zones[i]
		z["active"] = bool(st.get("active", false))
		z["cleared"] = bool(st.get("cleared", false))
		z["ids"] = (st.get("ids", []) as Array).duplicate()

	# Fog of war. A size mismatch means the grid changed under an old snapshot — keep the fresh
	# fog rather than index past the end of a PackedByteArray.
	var fog: Variant = snap.get("explored")
	if fog is PackedByteArray and (fog as PackedByteArray).size() == explored_cells.size():
		explored_cells = (fog as PackedByteArray).duplicate()
		explored_version += 1

	kills = int(snap.get("kills", kills))
	wave = int(snap.get("wave", wave))
	elapsed = float(snap.get("elapsed", elapsed))
	_reveal_around(player_pos)
	_prev_pos = player_pos
	return true


## Reads BOTH hands off the save: the weapon's own interval (`swingMs` + DEX + IAS), its own
## reach, and its own damage roll. The off hand is the `shield` slot holding something with a
## `weaponType` — that is how the PWA's equipment model stores a second weapon, and a real
## shield has no `weaponType`, so it is skipped instead of being swung.
func _read_hands() -> void:
	var hero: Dictionary = _state.hero()
	var equip: Dictionary = _state.equip()
	main_weapon = _find_item.call(equip.get("weapon", "fists"))
	if main_weapon.is_empty():
		main_weapon = _find_item.call("fists")
	var dex_total := int(hero.get("attrDex", 0)) \
		+ int(Progression._equip_attr(equip, _find_item, "dex"))
	var gloves: Dictionary = _find_item.call(equip.get("gloves"))
	var glove_ias := int(gloves.get("ias", 0)) if not gloves.is_empty() else 0
	main_swing = float(Progression.swing_time(rng, main_weapon, dex_total, glove_ias)) / 1000.0
	reach_main = reach_for(main_weapon)
	var cls: Dictionary = {}
	if _data != null:
		cls = _data.class_by_id(str(_state.data.get("heroClass", "")))
	off_weapon = {}
	if bool(cls.get("dualWield", false)):
		var cand: Dictionary = _find_item.call(equip.get("shield"))
		if not cand.is_empty() and cand.has("weaponType"):
			off_weapon = cand
	if off_weapon.is_empty():
		off_swing = 0.0
		reach_off = 0.0
		dmg_off_min = 0
		dmg_off_max = 0
		crit_off = 0.0
	else:
		# Each hand's OWN interval is kept: the off hand's number is what the HUD shows and what
		# the beat's reach test uses. The PAIR swings at the HARMONIC mean of the two, i.e. both
		# rates summed — an average would halve each hand's speed (see `_attack_tick`).
		var off_ms := float(Progression.swing_time(rng, off_weapon, dex_total, glove_ias)) / 1000.0
		off_swing = off_ms
		main_swing = maxf(PAIR_FLOOR, 1.0 / (1.0 / main_swing + 1.0 / off_ms))
		reach_off = reach_for(off_weapon)

	# Damage per hand: the weapon's own roll, times its specialisation, times D2's off-hand
	# penalty (50 %, raised by One-Hand Specialization in `Talents.weapon_spec`).
	var spec_main: Dictionary = Talents.weapon_spec(_state, main_weapon, false)
	var roll_main: Dictionary = Progression.hero_dmg(hero, equip, _find_item, 1.0, {},
		float(spec_main["dmgMult"]))
	dmg_min = int(roll_main["min"])
	dmg_max = int(roll_main["max"])
	crit_chance = float(main_weapon.get("critChance", 0)) + float(spec_main["critBonus"])
	if not off_weapon.is_empty():
		var spec_off: Dictionary = Talents.weapon_spec(_state, off_weapon, true)
		var mult := float(spec_off["dmgMult"]) * float(spec_off["offHandMult"])
		var roll_off: Dictionary = Progression.hero_dmg(hero, equip, _find_item, 1.0,
			off_weapon, mult)
		dmg_off_min = int(roll_off["min"])
		dmg_off_max = int(roll_off["max"])
		crit_off = float(off_weapon.get("critChance", 0)) + float(spec_off["critBonus"])

	speed_pct = clampi(int(Progression._equip_attr(equip, _find_item, "moveSpeed")),
		0, MAX_SPEED_PCT)


## The walk, in world pixels per second. One number for the rules and the camera, so a boot
## bonus cannot move the hero at one speed and the screen's follow at another.
func hero_speed() -> float:
	return HERO_BASE_SPEED * (1.0 + float(speed_pct) / 100.0)


# ============================================================================ step

func step(dt: float, move: Vector2) -> void:
	if finished:
		return
	elapsed += dt
	if swing_age >= 0.0:
		swing_age += dt
	if swing_age_off >= 0.0:
		swing_age_off += dt

	_prev_pos = player_pos
	# ...and the DIRECTION the player walks sets the AIM, and outranks the assist's facing while he
	# walks (see `_update_target` and `aim`). Set BEFORE the pick, so a thumb that changed sides
	# re-picks the target on the very same step.
	var walk := move.limit_length(1.0)
	var walking := walk.length_squared() > 0.0001
	if walking:
		aim = walk.normalized()
	_update_target(walking)
	_move_hero(dt, move, target_id >= 0)
	# FOG OF WAR: everything the hero can see from where he now stands is marked explored. Done
	# once per step, off the grid cells, so it costs nothing per frame.
	_reveal_around(player_pos)
	_zone_tick()
	_move_monsters(dt)
	_attack_tick(dt)
	_step_projectiles(dt)
	_step_bolts(dt)
	_age_effects(dt)
	_move_drops(dt)
	_age_numbers(dt)
	RunSpells.tick(self, dt)
	_zone_clear_tick(dt)
	# A portal left behind closes once the hero has walked away from it. It is not a second way
	# home — the scroll was spent on the trip it already carried him through — and an open mouth
	# standing in a cleared room for the rest of the run would read as a promise it cannot keep.
	if portal_open and player_pos.distance_to(portal_point) > PORTAL_CLOSE_DIST:
		portal_open = false


## One step of the walk. `keep_facing` is the TARGET ASSIST talking: while an attack is held the
## hero keeps looking at the body the game picked for him, even if the player walks him sideways,
## and with no stick input he closes the distance on his own (`_approach_step`).
##
## ⚠️  The player's own stick ALWAYS wins the movement. A hero the game walks for the player is a
## hero the player cannot back out of a fight with, and "unhittable while holding attack" is worse
## than no assist at all.
func _move_hero(dt: float, move: Vector2, keep_facing: bool = false) -> void:
	var dir := move.limit_length(1.0)
	var walking := dir.length_squared() > 0.0001
	if not keep_facing and walking:
		# Movement IS the aim while nothing is held: the hero faces where he walks, and a still
		# hero keeps the last direction (see `FACING_MIN_DOT`).
		facing = aim
	if not walking:
		if not keep_facing:
			return
		dir = _approach_step()
		if dir == Vector2.ZERO:
			return
	# THE CORRIDOR, not a rectangle: the step is taken through `_step_body`, so the hero slides
	# along the rock at a turn instead of stopping dead against it.
	player_pos = _step_body(player_pos, dir * hero_speed() * dt, HERO_RADIUS)


## Where the ASSIST would walk the hero this frame, or ZERO if he is already close enough. The
## stop is measured to BODIES like every reach in this fight (`reach + the target's radius`), so
## the hero halts exactly where a swing can land instead of walking into the portrait.
func _approach_step() -> Vector2:
	var idx := target_index()
	if idx < 0:
		return Vector2.ZERO
	var want := _approach_distance()
	if want <= 0.0:
		return Vector2.ZERO
	var off: Vector2 = (monsters[idx]["pos"] as Vector2) - player_pos
	if off.length() <= want or off.length() < 0.001:
		return Vector2.ZERO
	return off.normalized()


## How close the current ACTION needs the body: the weapon's arm for a swing or a melee spell, and
## nothing at all for an aimed spell — a bolt that reaches further than the picker's own range has
## no reason to walk the player into the pack.
func _approach_distance() -> float:
	if held_spell != "" and not RunSpells.needs_melee_reach(held_spell):
		return 0.0
	return reach_main + MON_RADIUS


# ============================================================================ area
#
# The map: a grid of `TILE` px cells, a start clearing, and a carved corridor that turns on its
# way up the world. The walk, the spawns and the fog all read this grid, so there is exactly one
# answer to "is this a place the hero can stand".

func cell_index(cx: int, cy: int) -> int:
	return cy * COLS + cx


func in_grid(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < COLS and cy < ROWS


## Is this cell floor? A cell OUTSIDE the grid is rock, which is what makes the corridor's ends
## and edges solid without any special case at the border.
func is_floor_cell(cx: int, cy: int) -> bool:
	if not in_grid(cx, cy) or floor_cells.size() != COLS * ROWS:
		return false
	return floor_cells[cell_index(cx, cy)] == 1


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


func cell_centre(cx: int, cy: int) -> Vector2:
	return Vector2((float(cx) + 0.5) * TILE, (float(cy) + 0.5) * TILE)


func is_explored_cell(cx: int, cy: int) -> bool:
	if not in_grid(cx, cy) or explored_cells.size() != COLS * ROWS:
		return false
	return explored_cells[cell_index(cx, cy)] == 1


func _carve_square(cx: int, cy: int, half: int) -> void:
	for y in range(cy - half, cy + half + 1):
		for x in range(cx - half, cx + half + 1):
			if in_grid(x, y):
				floor_cells[cell_index(x, y)] = 1


## A straight leg between two cell centres, carved at `half`. Axis-aligned in practice (the
## generator only ever makes vertical or horizontal legs), which is what gives the corridor its
## square-cut turns instead of a diagonal smear.
func _carve_leg(a: Vector2i, b: Vector2i, half: int) -> void:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for s in steps + 1:
		var t := float(s) / float(maxi(steps, 1))
		_carve_square(int(round(lerpf(float(a.x), float(b.x), t))),
			int(round(lerpf(float(a.y), float(b.y), t))), half)


## The four cell directions, in the order `_pick_walk_dir` scores them.
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Build the area.
##
## ⚠️  THE ENTRANCE IS A SIDE, NOT ALWAYS THE BOTTOM, AND THE EXIT IS NOT ALWAYS THE TOP
## (Jan, Nov 2026: "Východ nemusí být vždy vpravo nahoře. A vchod nemusí být vždy vpravo dole.
## Může to být libovolně"). So the journey is a 4-directional random walk with a bias toward the
## far edge, not a snake that always climbs: `entry_side` is drawn, the exit edge is a DIFFERENT
## edge, the walk turns in any direction and prefers straight legs only by a small penalty.
##
## ⚠️  "NA JEDNO BRDO" (all the same) was a property of the GENERATOR, not of the grid: one
## corridor profile drawn all the way up is the same area every time with a different wiggle.
## Four dials now vary independently per leg: LENGTH 3-8 cells, WIDTH 5-9 cells, a ROOM at 45 %
## of the leg ends (7-15 cells across), plus LOOPS and PILLARS below, which is what makes the
## player choose a lane instead of holding one direction.
##
## ⚠️  THE LENGTH IS A TARGET, NOT A CONSEQUENCE OF THE GRID (`PATH_TARGET`), and the walk is
## bounded by `guard` so a seed that keeps turning into its own trail cannot hang the build.
func _build_corridor() -> void:
	floor_cells.resize(COLS * ROWS)
	floor_cells.fill(0)
	explored_cells.resize(COLS * ROWS)
	explored_cells.fill(0)
	explored_version = 0
	path_points.clear()

	entry_side = rng.randi_range(0, 3)
	exit_side = (entry_side + rng.randi_range(1, 3)) % 4
	var start := _side_anchor(entry_side)
	# The gate drifts along its own edge — an entrance in the exact middle of every map is the
	# second half of "every area looks the same".
	var drift := rng.randi_range(-6, 6)
	if absi(DIRS[_side_dir_index(entry_side)].x) == 0:
		start.x = clampi(start.x + drift, 6, COLS - 7)
	else:
		start.y = clampi(start.y + drift, 6, ROWS - 7)
	_carve_square(start.x, start.y, START_ROOM_HALF)
	start_point = cell_centre(start.x, start.y)
	path_points.append(start_point)

	var target := _side_anchor(exit_side)
	var pos := start
	var dir_i := _side_dir_index(entry_side)
	var built := 0.0
	var last: Vector2 = start_point
	var guard := 0
	while built < PATH_TARGET and guard < 200:
		guard += 1
		dir_i = _pick_walk_dir(pos, dir_i)
		var dir: Vector2i = DIRS[dir_i]
		var nxt := pos + dir * rng.randi_range(3, 8)
		nxt.x = clampi(nxt.x, 2, COLS - 3)
		nxt.y = clampi(nxt.y, 2, ROWS - 3)
		if nxt == pos:
			continue
		_carve_leg(pos, nxt, rng.randi_range(CORRIDOR_HALF_MIN, CORRIDOR_HALF_MAX))
		pos = nxt
		var centre: Vector2 = cell_centre(pos.x, pos.y)
		path_points.append(centre)
		built += last.distance_to(centre)
		last = centre
		# A room every other leg gives the corridor places to breathe — and places for a pack to
		# stand in formation instead of in single file.
		if rng.randf() < 0.45:
			_carve_square(pos.x, pos.y, rng.randi_range(ROOM_HALF_MIN, ROOM_HALF_MAX))

	# The far end: the walk ended somewhere, so the exit is the NEAREST edge to that end (never the
	# entrance's own edge), reached by a short approach and closed with a room to fight the deepest
	# pack in. Aiming the whole walk at a pre-chosen exit anchor instead made it circle the anchor
	# for the last half of its length, which folded the corridor onto itself.
	exit_side = _closest_side(pos, entry_side)
	target = _side_anchor(exit_side)
	var mid := Vector2i(target.x, pos.y)
	if rng.randf() < 0.5:
		mid = Vector2i(pos.x, target.y)
	_carve_leg(pos, mid, rng.randi_range(2, 3))
	_carve_leg(mid, target, rng.randi_range(2, 3))
	_carve_square(target.x, target.y, ROOM_HALF)
	path_points.append(cell_centre(mid.x, mid.y))
	path_points.append(cell_centre(target.x, target.y))

	# The corridor as carved IS connected; the extra structure and the zone's terrain then get a
	# chance to break it, and the fallback puts the walk back. A map whose exit cannot be reached
	# is a zone the act stops dead at, so this is checked, not hoped for.
	var walk_snapshot: PackedByteArray = floor_cells.duplicate()
	_carve_loops()
	_carve_pillars()
	_sync_kind_from_floor()
	_apply_zone_feature()
	_sync_floor_from_kind()
	if not _all_floor_connected():
		floor_cells = walk_snapshot.duplicate()
		_sync_kind_from_floor()
		_apply_zone_feature(true)
		_sync_floor_from_kind()
	_repair_isolated_floor()


## The inward direction of a walk that ENTERS through `side` (0 bottom, 1 top, 2 left, 3 right).
func _side_forward(side: int) -> Vector2i:
	return DIRS[_side_dir_index(side)]


func _side_dir_index(side: int) -> int:
	match side:
		0:
			return 0   # bottom -> up
		1:
			return 2   # top -> down
		2:
			return 1   # left -> right
		_:
			return 3   # right -> left


## The mouth of a gate on `side`, inset far enough for the start room's half-width.
func _side_anchor(side: int) -> Vector2i:
	match side:
		0:
			return Vector2i(COLS / 2, ROWS - 6)
		1:
			return Vector2i(COLS / 2, 5)
		2:
			return Vector2i(5, ROWS / 2)
		_:
			return Vector2i(COLS - 6, ROWS / 2)


## The edge the walk ended nearest to, ignoring the one it came in through. The exit gate is
## therefore a property of where the journey ARRIVED, not a target the walk was aimed at.
func _closest_side(pos: Vector2i, avoid: int) -> int:
	var best := 0
	var best_d := 99999
	for side in 4:
		if side == avoid:
			continue
		var a := _side_anchor(side)
		var d := absi(pos.x - a.x) + absi(pos.y - a.y)
		if d < best_d:
			best_d = d
			best = side
	return best


## Which of the four directions the walk takes next: straight first, away from the rock border
## second, and OFF CELLS THE WALK ALREADY CARVED third. Never straight back. There is no bias
## toward a pre-chosen exit any more — the walk picks the edge it ends nearest to, and the retread
## penalty is what makes it spread across the map instead of circling one target.
func _pick_walk_dir(pos: Vector2i, dir_i: int) -> int:
	var best := dir_i
	var best_score := -INF
	for i in 4:
		if i == (dir_i + 2) % 4:
			continue
		var d: Vector2i = DIRS[i]
		var score := 0.0
		if i != dir_i:
			score -= 0.35
		var ahead := pos + d * 4
		if ahead.x < 2 or ahead.x > COLS - 3 or ahead.y < 2 or ahead.y > ROWS - 3:
			score -= 1.6
		# DON'T RETREAD. A leg that lands on cells the walk already carved turns a journey into a
		# blob: measured, a 224-cell walk lay on itself three times over (880 floor cells for what
		# should have been ~1 500) and only five packs could then be spaced far enough apart to be
		# met one at a time. This is what makes the corridor SPREAD across the map.
		var crowded := 0
		for step in [2, 5, 8]:
			var q: Vector2i = pos + d * step
			if is_floor_cell(q.x, q.y):
				crowded += 1
		score -= 0.55 * float(crowded)
		score += rng.randf() * 0.6
		if score > best_score:
			best_score = score
			best = i
	return best


## LOOPS: two stretches of the walk that ended up close in SPACE but far apart along the path get
## a short connecting corridor. That is what turns a tube into a place with two ways round, and
## it costs two `_carve_leg` calls.
func _carve_loops() -> void:
	var made := 0
	for i in range(1, path_points.size() - 4):
		if made >= 2:
			return
		var a: Vector2i = cell_of(path_points[i])
		var best := -1
		var best_d := 999
		for j in range(i + 5, mini(path_points.size(), i + 12)):
			var b: Vector2i = cell_of(path_points[j])
			var d := absi(a.x - b.x) + absi(a.y - b.y)
			if d < 4 or d > 13:
				continue
			if d < best_d:
				best_d = d
				best = j
		if best < 0:
			continue
		var target: Vector2i = cell_of(path_points[best])
		var half := rng.randi_range(1, 2)
		var corner := Vector2i(target.x, a.y)
		_carve_leg(a, corner, half)
		_carve_leg(corner, target, half)
		made += 1


## PILLARS: rock outcrops INSIDE a room, so a fight in the open has a shape to use. They are the
## one obstacle a player can circle, which is why they are worth the cells — but only where
## `_has_clearance` proves they cannot plug the corridor: a pillar that touches a wall divides
## the area and the exit becomes unreachable.
func _carve_pillars() -> void:
	for i in range(2, path_points.size() - 2, 2):
		if rng.randf() > 0.5:
			continue
		var ang := rng.randf() * TAU
		var p: Vector2 = (path_points[i] as Vector2) \
			+ Vector2(cos(ang), sin(ang)) * rng.randf_range(2.5, 5.0) * TILE
		var c: Vector2i = cell_of(p)
		if not _distance_to_path(p) > TILE * 2.2:
			continue
		var half := rng.randi_range(0, 1)
		if not _has_clearance(c.x, c.y, half + 2):
			continue
		for y in range(c.y - half, c.y + half + 1):
			for x in range(c.x - half, c.x + half + 1):
				if in_grid(x, y):
					floor_cells[cell_index(x, y)] = 0


## Are all cells within `margin` of (cx, cy) floor? A pillar needs that ring, or it stands against
## a wall and the walk has to go round the long way (or not at all).
func _has_clearance(cx: int, cy: int, margin: int) -> bool:
	for y in range(cy - margin, cy + margin + 1):
		for x in range(cx - margin, cx + margin + 1):
			if not is_floor_cell(x, y):
				return false
	return true


## Distance from a world point to the walked centreline. Used to keep obstacles OFF the path.
func _distance_to_path(p: Vector2) -> float:
	var best := INF
	var pts: Array = path_points
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0
		if len2 > 0.001:
			t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Is every floor cell reachable from the spawn? One flood fill, four neighbours — the same check
## `tools/test_corridor_fog.gd` runs, available here so a layout that failed can be discarded
## before the player ever sees it.
func _all_floor_connected() -> bool:
	if floor_cells.size() != COLS * ROWS:
		return false
	var start: Vector2i = cell_of(start_point)
	var seen := PackedByteArray()
	seen.resize(COLS * ROWS)
	seen.fill(0)
	var stack: Array[Vector2i] = [start]
	seen[cell_index(start.x, start.y)] = 1
	var reached := 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var n: Vector2i = c + d
			if not in_grid(n.x, n.y) or floor_cells[cell_index(n.x, n.y)] != 1:
				continue
			if seen[cell_index(n.x, n.y)] == 1:
				continue
			seen[cell_index(n.x, n.y)] = 1
			reached += 1
			stack.append(n)
	for i in floor_cells.size():
		if floor_cells[i] == 1 and seen[i] == 0:
			return false
	return true


## Anything the walk cannot reach is not floor any more: a visible pocket behind the rock reads
## as a bug, and a pack in it is a body the player can never fight.
func _repair_isolated_floor() -> void:
	if not _all_floor_connected():
		for i in cell_kind.size():
			if cell_kind[i] == KIND_GROUND or cell_kind[i] == KIND_DECK:
				floor_cells[i] = 1
			else:
				floor_cells[i] = 0
		var start: Vector2i = cell_of(start_point)
		var seen := PackedByteArray()
		seen.resize(COLS * ROWS)
		seen.fill(0)
		var stack: Array[Vector2i] = [start]
		seen[cell_index(start.x, start.y)] = 1
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in DIRS:
				var n: Vector2i = c + d
				if not in_grid(n.x, n.y) or floor_cells[cell_index(n.x, n.y)] != 1:
					continue
				if seen[cell_index(n.x, n.y)] == 1:
					continue
				seen[cell_index(n.x, n.y)] = 1
				stack.append(n)
		for i in cell_kind.size():
			if floor_cells[i] == 1 and seen[i] == 0:
				cell_kind[i] = KIND_ROCK
				floor_cells[i] = 0


# ============================================================================ terrain features
#
# Jan, Nov 2026: "Každá ta lokalita má sice nějak ztvárněné dominantní prvky, ale takhle
# jednoduše mi to nestačí. Močály nebudou mít jen jinou texturu na zemi, ale můžeme doslova
# napodobit dřevěné lávky uprostřed močálů… Valley se rozdělí řekou, přes kterou vede velký most."
#
# So a zone's GROUND now has a shape as well as a texture: `cell_kind` marks every cell as rock,
# ground, WATER (impassable) or DECK (a plank walkway or a bridge — walkable). `floor_cells` stays
# the walkable mask every rule in the run reads, so nothing downstream had to learn a new concept.

func cell_kind_at(cx: int, cy: int) -> int:
	if not in_grid(cx, cy) or cell_kind.size() != COLS * ROWS:
		return KIND_ROCK
	return cell_kind[cell_index(cx, cy)]


func is_water_cell(cx: int, cy: int) -> bool:
	return cell_kind_at(cx, cy) == KIND_WATER


func is_deck_cell(cx: int, cy: int) -> bool:
	return cell_kind_at(cx, cy) == KIND_DECK


func _set_kind(cx: int, cy: int, kind: int) -> void:
	if in_grid(cx, cy) and cell_kind.size() == COLS * ROWS:
		cell_kind[cell_index(cx, cy)] = kind


func _sync_kind_from_floor() -> void:
	cell_kind.resize(COLS * ROWS)
	for i in floor_cells.size():
		cell_kind[i] = KIND_GROUND if floor_cells[i] == 1 else KIND_ROCK


func _sync_floor_from_kind() -> void:
	floor_cells.resize(COLS * ROWS)
	for i in cell_kind.size():
		var k := cell_kind[i]
		floor_cells[i] = 1 if (k == KIND_GROUND or k == KIND_DECK) else 0


## The zone's own terrain. `safe` is the fallback pass, used when the first attempt left a walkable
## cell cut off: the same feature is applied again with an extra guarantee (`_bridge_over_path`)
## that the walked centreline is deck from end to end.
func _apply_zone_feature(safe: bool = false) -> void:
	var theme: Dictionary = ZoneThemeData.for_zone(act_id, zone_index)
	feature = str(theme.get("feature", ""))
	match feature:
		"boardwalk":
			_feature_boardwalk(safe)
		"river", "chasm":
			_feature_river(feature == "chasm")


## THE SWAMP. Every carved cell becomes impassable water and a plank walkway is laid along the
## walk — width 3 cells, wobbling 0-2 cells off the centreline with a turn every 2-5 cells, which
## is what makes the walkway run left, right and back again instead of straight up. A wobble is
## eased by ONE cell per step and snapped to the centreline on the leg's own endpoints, so no
## step can jump two cells and leave a gap: a hole in the walkway is a zone the player cannot
## cross.
func _feature_boardwalk(safe: bool = false) -> void:
	for i in cell_kind.size():
		if cell_kind[i] == KIND_GROUND:
			cell_kind[i] = KIND_WATER
	# A wooden landing at the gate, so the hero does not arrive on one plank.
	var gate: Vector2i = cell_of(start_point)
	_stamp_deck(gate.x, gate.y, 2)
	var prev: Vector2 = start_point
	for i in range(1, path_points.size()):
		var p: Vector2 = path_points[i]
		_deck_leg(cell_of(prev), cell_of(p))
		prev = p
	if safe:
		_bridge_over_path(1)


func _deck_leg(a: Vector2i, b: Vector2i) -> void:
	var vertical := a.x == b.x
	var length := maxi(absi(b.x - a.x), absi(b.y - a.y))
	if length <= 0:
		_stamp_deck(a.x, a.y, 1)
		return
	var wobble := 0
	var target := 0
	var hold := 0
	for s in length + 1:
		var t := float(s) / float(length)
		var cx := int(round(lerpf(float(a.x), float(b.x), t)))
		var cy := int(round(lerpf(float(a.y), float(b.y), t)))
		if s == 0 or s == length:
			wobble = 0
			target = 0
			hold = 0
		elif hold <= 0:
			target = rng.randi_range(-2, 2)
			hold = rng.randi_range(2, 5)
		else:
			hold -= 1
		if wobble < target:
			wobble += 1
		elif wobble > target:
			wobble -= 1
		var ox := wobble if vertical else 0
		var oy := 0 if vertical else wobble
		if not is_water_cell(cx + ox, cy + oy):
			ox = 0
			oy = 0
		_stamp_deck(cx + ox, cy + oy, 1)


func _stamp_deck(cx: int, cy: int, half: int) -> void:
	for y in range(cy - half, cy + half + 1):
		for x in range(cx - half, cx + half + 1):
			if is_water_cell(x, y):
				_set_kind(x, y, KIND_DECK)


## THE RIVER (and the canyon's chasm): a straight band cut ACROSS the corridor at a point along
## the walk, then a bridge over every place the path crosses it.
##
## ⚠️  THE BAND IS CUT THROUGH THE ROCK AS WELL — a river that stops dead at the same wall the
## corridor ends at reads as a puddle, and Jan asked for a location DIVIDED by a river. It is cut
## only `REACH` cells to each side of the crossing, so it runs off into the fog on both sides
## instead of sawing the whole map in half.
##
## ⚠️  AND IT IS VERIFIED, NOT HOPED FOR. The flood is undone and retried narrower if it broke the
## walk (a loop carved by `_carve_loops` can cross the same band away from the bridge, which is a
## pocket the player could see and never reach). A zone that still fails falls back to the plain
## corridor in `_build_corridor`.
func _feature_river(wide: bool) -> void:
	var n := path_points.size()
	if n < 8:
		return
	var backup: PackedByteArray = cell_kind.duplicate()
	for attempt in 3:
		cell_kind = backup.duplicate()
		var idx := rng.randi_range(int(float(n) * 0.4), int(float(n) * 0.72))
		var dir := _path_dir_at(idx)
		if dir == Vector2i.ZERO:
			continue
		var cross: Vector2 = path_points[idx]
		var scale := 1.0 - 0.26 * float(attempt)
		var half := (4.6 if wide else 4.2) * scale
		# ⚠️  THE REACH IS LONG ON PURPOSE (24 cells = 1 440 px each side). The band is cut through
		# the ROCK as well, and a band that only reaches the corridor's own edge reads as a pool in
		# a room instead of a river dividing the valley — measured at reach 10: 80 cells of water
		# and not one cell of rock, because the crossing usually lands in a room.
		_cut_band(cross, dir, half, 24.0 * scale)
		if DEBUG_TERRAIN:
			var w := 0
			for v in cell_kind:
				if int(v) == KIND_WATER:
					w += 1
			print("    [river] attempt %d idx=%d dir=%s half=%.1f water=%d"
				% [attempt, idx, str(dir), half, w])
		_stamp_bridge(cross, dir, half)
		# A second, narrower ford further along the walk on some seeds: two crossings read as a
		# river valley, one reads as a puddle.
		if rng.randf() < 0.45:
			var i2 := mini(int(float(n) * 0.8), n - 3)
			var d2 := _path_dir_at(i2)
			if d2 != Vector2i.ZERO:
				_cut_band(path_points[i2], d2, half * 0.6, 7.0 * scale)
				_stamp_bridge(path_points[i2], d2, half * 0.6)
		_sync_floor_from_kind()
		if _all_floor_connected():
			return
	cell_kind = backup.duplicate()
	_sync_floor_from_kind()


## The AXIS-ALIGNED direction of the walk at `idx`, taken from the segment itself. Averaging the
## two neighbouring points gives a 45 deg direction at every corner, and a diagonal band is both
## ugly (a river at 45 deg to a square-tiled world) and hard to bridge cleanly.
func _path_dir_at(idx: int) -> Vector2i:
	var pts: Array = path_points
	var a: Vector2i = cell_of(pts[clampi(idx - 1, 0, pts.size() - 1)] as Vector2)
	var b: Vector2i = cell_of(pts[clampi(idx + 1, 0, pts.size() - 1)] as Vector2)
	if a.x == b.x and a.y == b.y:
		return Vector2i.ZERO
	if absi(b.x - a.x) >= absi(b.y - a.y):
		return Vector2i(1 if b.x > a.x else -1, 0)
	return Vector2i(0, 1 if b.y > a.y else -1)


## A BRIDGE over the river at `cross`: `half + 2` cells along the path's own direction (it has to
## span the water and stand on both banks) and 5 cells across. Stamped only on WATER, so the
## bridge lands ON the banks instead of painting deck over the road.
func _stamp_bridge(cross: Vector2, dir: Vector2i, half: float) -> void:
	var perp := Vector2i(-dir.y, dir.x)
	var c: Vector2i = cell_of(cross)
	var length := int(ceil(half)) + 2
	for a in range(-length, length + 1):
		for b in range(-2, 3):
			var x: int = c.x + dir.x * a + perp.x * b
			var y: int = c.y + dir.y * a + perp.y * b
			if is_water_cell(x, y):
				_set_kind(x, y, KIND_DECK)


## One cut: every GROUND or ROCK cell inside the band `half` cells either side of the line
## through `cross` becomes water, but only within `reach` cells ALONG the band — the river's two
## ends fade into the rock instead of crossing the whole map.
func _cut_band(cross: Vector2, dir: Vector2i, half: float, reach: float) -> void:
	var normal := Vector2i(-dir.y, dir.x)
	var axis := Vector2(dir)
	var side := Vector2(normal)
	var r := reach * TILE
	for cy in ROWS:
		for cx in COLS:
			var k := cell_kind[cell_index(cx, cy)]
			if k != KIND_GROUND and k != KIND_ROCK:
				continue
			var v: Vector2 = cell_centre(cx, cy) - cross
			# THICKNESS is measured ALONG the path's direction (the path crosses the river), and
			# the river's LENGTH runs along the normal (across the corridor and into the rock).
			# Getting these two the wrong way round cut a 20-cell stretch of corridor and then
			# bridged all of it: 113 cells of deck over 13 cells of visible water.
			if absf(v.dot(axis)) > half * TILE:
				continue
			if absf(v.dot(side)) > r:
				continue
			cell_kind[cell_index(cx, cy)] = KIND_WATER


## Lay a deck over every water cell the walked centreline passes through, `half` cells to each
## side. This is the guarantee that a ford is crossable: the bridge follows the path, so it can
## never miss a crossing, and it is stamped in the path's own direction.
func _bridge_over_path(half: int) -> void:
	var prev: Vector2 = path_points[0]
	for i in range(1, path_points.size()):
		var p: Vector2 = path_points[i]
		var a: Vector2i = cell_of(prev)
		var b: Vector2i = cell_of(p)
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for s in steps + 1:
			var t := float(s) / float(maxi(steps, 1))
			var cx := int(round(lerpf(float(a.x), float(b.x), t)))
			var cy := int(round(lerpf(float(a.y), float(b.y), t)))
			if not is_water_cell(cx, cy):
				continue
			if a.x == b.x:
				_stamp_deck(cx, cy, 0)
				for k in range(-half, half + 1):
					if is_water_cell(cx + k, cy):
						_set_kind(cx + k, cy, KIND_DECK)
			else:
				for k in range(-half, half + 1):
					if is_water_cell(cx, cy + k):
						_set_kind(cx, cy + k, KIND_DECK)
			# A deck cell on the centreline always exists, even if the sideways stamp found no
			# water to replace (a 1-cell ford): the crossing has to be walkable.
			if cell_kind[cell_index(cx, cy)] == KIND_WATER:
				cell_kind[cell_index(cx, cy)] = KIND_DECK
		prev = p


## Can a body of radius `r` stand at `p`? The WHOLE disc has to be on floor, not just its centre:
## a hero whose centre is on the last floor cell would otherwise hang his shoulder over the rock,
## and the drawn wall would be inside him.
##
## Eight sample points on the rim (the four cardinals and the four diagonals) are enough for a
## 60 px grid and a ~31 px body: a corner of rock cannot slip between them.
func walkable(p: Vector2, r: float) -> bool:
	if not is_floor_cell(int(floor(p.x / TILE)), int(floor(p.y / TILE))):
		return false
	if is_floor_cell(int(floor((p.x - r) / TILE)), int(floor((p.y - r) / TILE))) \
			and is_floor_cell(int(floor((p.x + r) / TILE)), int(floor((p.y - r) / TILE))) \
			and is_floor_cell(int(floor((p.x - r) / TILE)), int(floor((p.y + r) / TILE))) \
			and is_floor_cell(int(floor((p.x + r) / TILE)), int(floor((p.y + r) / TILE))):
		return true
	for i in 8:
		var a := TAU * float(i) / 8.0
		if not is_floor_cell(int(floor((p.x + cos(a) * r) / TILE)),
				int(floor((p.y + sin(a) * r) / TILE))):
			return false
	return true


## Move a body from `from` by `delta`, sliding along the rock instead of stopping dead: a full
## move, else the x component only, else the y component only. Without the slide the corridor's
## turns would be sticky — the player pushes into a wall and the walk stops even though the thumb
## is aiming down the leg.
func _step_body(from: Vector2, delta: Vector2, r: float) -> Vector2:
	var target := from + delta
	if walkable(target, r):
		return target
	var slide_x := Vector2(target.x, from.y)
	if is_zero_approx(delta.x) == false and walkable(slide_x, r):
		return slide_x
	var slide_y := Vector2(from.x, target.y)
	if is_zero_approx(delta.y) == false and walkable(slide_y, r):
		return slide_y
	return from


## The nearest point a body of radius `r` can stand on, searched outward from `p` in cell steps.
## Used by the spawns, which used to clamp to a rectangle and now have to find floor.
func nearest_floor_point(p: Vector2, r: float = MON_RADIUS) -> Vector2:
	if walkable(p, r):
		return p
	var c := cell_of(p)
	for radius in range(1, 8):
		var best := Vector2.ZERO
		var best_d := INF
		for y in range(c.y - radius, c.y + radius + 1):
			for x in range(c.x - radius, c.x + radius + 1):
				if absi(x - c.x) != radius and absi(y - c.y) != radius:
					continue
				if not is_floor_cell(x, y):
					continue
				var q := cell_centre(x, y)
				var d: float = q.distance_squared_to(p)
				if d < best_d and walkable(q, r):
					best_d = d
					best = q
		if best_d < INF:
			return best
	return start_point


## Mark every cell the hero can see as explored. Called once per step; 5x5 to 7x7 cells is all
## the work a 60 px grid needs, so the fog costs nothing per frame.
func _reveal_around(p: Vector2) -> void:
	var c := cell_of(p)
	var reach := int(ceil(FOG_REVEAL / TILE))
	for y in range(c.y - reach, c.y + reach + 1):
		for x in range(c.x - reach, c.x + reach + 1):
			if not in_grid(x, y):
				continue
			if not is_floor_cell(x, y):
				# Rock next to the hero is explored too, so the wall he is standing against is
				# DRAWN instead of being a black tile he is pressed into.
				if cell_centre(x, y).distance_to(p) <= FOG_REVEAL + TILE:
					_mark_explored(x, y)
				continue
			if cell_centre(x, y).distance_to(p) <= FOG_REVEAL:
				_mark_explored(x, y)


## Set one explored flag, bumping `explored_version` only on a real change — the screen's
## fog texture keys off this counter.
func _mark_explored(x: int, y: int) -> void:
	var i := cell_index(x, y)
	if explored_cells[i] == 1:
		return
	explored_cells[i] = 1
	explored_version += 1


## One pack per STOP along the corridor, the hero's own clearing left EMPTY. `minArea` is honoured
## by DISTANCE from the start instead of elapsed time: the far end holds the heavy kinds, so
## walking deeper is what raises the stakes and the run cannot be farmed by standing still.
func _build_area() -> void:
	zones.clear()
	path_points.clear()
	_build_corridor()
	# The act's chain: the entrance is where the hero stands, the exit is the far END of the
	# centreline (always a cleared room), and the waypoint sits just off the entrance — INSIDE the
	# start room, i.e. opposite the edge the hero walked in through, now that the entrance can be
	# any of the four edges.
	exit_point = path_points[path_points.size() - 1]
	var inward: Vector2 = Vector2(_side_forward(entry_side))
	waypoint_point = nearest_floor_point(start_point + inward * TILE * 2.0)
	# How many packs the corridor holds: one per `CELL_SPACING` px of path, clamped to something a
	# phone run can finish. The ceiling moved from 20 to 34 with the 3x grid — 20 was already
	# binding on the OLD corridor, so leaving it would have made a bigger map with the same
	# number of fights spread thinner, i.e. longer walks and nothing to meet.
	var total := 0.0
	var prev: Vector2 = path_points[0]
	var lengths: Array = [0.0]
	for i in range(1, path_points.size()):
		var p: Vector2 = path_points[i]
		total += prev.distance_to(p)
		lengths.append(total)
		prev = p
	var count := clampi(int(round(total / CELL_SPACING)), 8, 34)
	var max_d := maxf(1.0, total)
	# The first pack must be OUTSIDE the activation radius of the spawn point, or it would be
	# standing on the hero before he takes a step — so the samples start past the clearing
	# instead of being dropped after the fact (dropping them left the corridor with five packs
	# and no far end).
	var d_min := minf(ACTIVATE_RADIUS + 120.0, max_d * 0.5)
	# The cells are placed FIRST and the roles are dealt among them afterwards: an elite pack
	# needs to know how many cells exist before one can be picked for it.
	var spots: Array = []
	for k in range(count):
		# Evenly spaced along the path, from past the clearing to the far end.
		var want := d_min + (max_d - d_min) * float(k + 1) / float(count + 1)
		var centre := _point_at_distance(lengths, want)
		if centre.distance_to(start_point) < ACTIVATE_RADIUS + 60.0:
			continue
		# ⚠️  TWO PACKS MUST NOT BE FIGHTABLE AT ONCE. Cells are spaced along the PATH, and since
		# the walk can double back (it has loops now) two cells three turns apart can stand 200 px
		# from each other — which is the banned horde arrived at by accident: the hero wakes both
		# and the choice of which lane to fight in is gone. A cell closer than `PACK_MIN_GAP` to one
		# already accepted is dropped, which thins the packs exactly where the corridor doubles back.
		var too_close := false
		for taken in spots:
			if (taken["centre"] as Vector2).distance_to(centre) < PACK_MIN_GAP:
				too_close = true
				break
		if too_close:
			continue
		spots.append({
			"centre": centre,
			"tier": 1 + int(round(3.0 * float(k) / float(maxi(count - 1, 1)))),
			"progress": clampi(int(round(9.0 * float(k) / float(maxi(count - 1, 1)))), 0, 9),
		})

	# At most ONE elite pack per zone, and it stands in the DEEPER half: walking further is
	# what raises the stakes, the same rule the tier of a pack already follows.
	var elite_at := -1
	if spots.size() >= 3 and rng.randf() < ELITE_PACK_CHANCE:
		elite_at = rng.randi_range(int(spots.size() / 2.0), spots.size() - 1)

	for i in range(spots.size()):
		var spot: Dictionary = spots[i]
		var kind := "normal"
		if i == elite_at:
			kind = "elite"
		elif rng.randf() < CHAMPION_PACK_CHANCE:
			kind = "champion"
		var members: Array = _make_pack(kind, spot["centre"] as Vector2, int(spot["tier"]))
		if members.is_empty():
			continue
		zones.append({
			"centre": spot["centre"],
			"progress": int(spot["progress"]),
			"kind": kind,
			"members": members,
			"active": false,
			"cleared": false,
			"ids": [],
		})


## The bodies of ONE cell. The default is a single wanderer (sometimes a pair that stands
## apart); a champion cell is 2-4 of the SAME kind; an elite cell is one leader with an affix
## and `ELITE_MINIONS` slaves that inherit its aura.
##
## Every member carries the multipliers THE WAKE reads — the row alone cannot say whether the
## body is a champion, so the pack has to.
func _make_pack(kind: String, centre: Vector2, tier: int) -> Array:
	var members: Array = []
	var row := _pick_row(tier)
	if row.is_empty():
		return members
	match kind:
		"champion":
			for _i in rng.randi_range(CHAMPION_MIN, CHAMPION_MAX):
				members.append({
					"row": row,
					"pos": _pack_slot(centre, members),
					"role": "champion",
					"hp_mult": CHAMPION_HP_MULT,
					"dmg_mult": CHAMPION_DMG_MULT,
					"xp_mult": CHAMPION_XP_MULT,
					"loot_grade": 1,
				})
		"elite":
			var affix := _roll_elite_affix()
			# An aura is the one affix that is not just a number on the leader: the slaves are
			# built with its damage bonus, which is what makes killing the elite FIRST pay.
			var aura := float(affix.get("auraDmgMult", 1.0)) if bool(affix.get("aura", false)) else 1.0
			members.append({
				"row": row,
				"pos": nearest_floor_point(centre, MON_RADIUS),
				"role": "elite",
				"hp_mult": ELITE_HP_MULT,
				"dmg_mult": ELITE_DMG_MULT,
				"xp_mult": ELITE_XP_MULT,
				"loot_grade": 2,
				"affix": affix,
				"elite_name": _elite_name(row),
			})
			for i in ELITE_MINIONS:
				var ang := TAU * float(i) / float(ELITE_MINIONS) + rng.randf_range(-0.35, 0.35)
				members.append({
					"row": row,
					"pos": nearest_floor_point(centre + Vector2(cos(ang), sin(ang)) * ELITE_RING,
						MON_RADIUS),
					"role": "minion",
					"hp_mult": 1.0,
					"dmg_mult": aura,
					"xp_mult": ELITE_XP_MULT,
					"loot_grade": 0,
				})
		_:
			members.append({
				"row": row,
				"pos": _pack_slot(centre, members),
				"role": "normal",
				"hp_mult": 1.0, "dmg_mult": 1.0, "xp_mult": 1.0, "loot_grade": 0,
			})
			if rng.randf() < STRAY_PAIR_CHANCE:
				var other := _pick_row(tier)
				if not other.is_empty():
					members.append({
						"row": other,
						"pos": _stray_slot(members[0]["pos"] as Vector2, centre),
						"role": "normal",
						"hp_mult": 1.0, "dmg_mult": 1.0, "xp_mult": 1.0, "loot_grade": 0,
					})
	return members


## A second wanderer's spot: `STRAY_GAP` away from the first body, ON floor. Bounded tries and
## then the nearest floor point in the chosen direction — a "find room" loop that can fail
## forever is a hang, which is worse than a stray that stands closer than it wanted to.
func _stray_slot(first: Vector2, centre: Vector2) -> Vector2:
	for _try in 12:
		var ang := rng.randf() * TAU
		var gap := rng.randf_range(STRAY_GAP_MIN, STRAY_GAP_MAX)
		var p := first + Vector2(cos(ang), sin(ang)) * gap
		if walkable(p, MON_RADIUS) and p.distance_to(centre) <= ZONE_JITTER * 2.2:
			return p
	var ang2 := rng.randf() * TAU
	return nearest_floor_point(first + Vector2(cos(ang2), sin(ang2)) * STRAY_GAP_MIN, MON_RADIUS)


## A D2 elite name: [Prefix] [Suffix] the [Appellation], from the PWA's own three tables. Purely
## cosmetic — the affix is what the fight reads — but a named body is what makes the pack
## readable as THE elite and not as another stray.
func _elite_name(row: Dictionary) -> String:
	var base := str(row.get("name", "Elita"))
	if _data == null:
		return "Elitni %s" % base
	var prefixes: Array = _data.table("ELITE_PREFIXES", [])
	var suffixes: Array = _data.table("ELITE_SUFFIXES", [])
	var appellations: Array = _data.table("ELITE_APPELATIONS", [])
	if prefixes.is_empty() or suffixes.is_empty() or appellations.is_empty():
		return "Elitni %s" % base
	return "%s %s %s" % [
		str(prefixes[rng.randi_range(0, prefixes.size() - 1)]),
		str(suffixes[rng.randi_range(0, suffixes.size() - 1)]),
		str(appellations[rng.randi_range(0, appellations.size() - 1)]),
	]


## The elite's D2 affix, from the table the DUEL already uses. `Aura Enchanted` is the reason
## the minions are built with a damage multiplier instead of the plain row stats.
func _roll_elite_affix() -> Dictionary:
	if _data == null:
		return {}
	var pool: Array = _data.table("ELITE_AFFIXES", [])
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]



## The world point at `distance` along the corridor's centreline.
func _point_at_distance(lengths: Array, distance: float) -> Vector2:
	for i in range(1, path_points.size()):
		if float(lengths[i]) >= distance:
			var a: Vector2 = path_points[i - 1]
			var b: Vector2 = path_points[i]
			var span := maxf(float(lengths[i]) - float(lengths[i - 1]), 0.001)
			var t := (distance - float(lengths[i - 1])) / span
			return a.lerp(b, clampf(t, 0.0, 1.0))
	return path_points[path_points.size() - 1]


## A free spot inside a pack, at least PACK_SPACING from every other member. Rejection for a
## BOUNDED number of tries and then a ring slot: two discs stacked on each other is a bad pack,
## but a "find room" loop that can fail forever is a hang, which is worse.
func _pack_slot(centre: Vector2, taken: Array) -> Vector2:
	for _try in 14:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(26.0, ZONE_JITTER)
		var p := centre + Vector2(cos(ang), sin(ang)) * dist
		if not walkable(p, MON_RADIUS):
			continue
		var free := true
		for m in taken:
			if p.distance_to(m["pos"] as Vector2) < PACK_SPACING:
				free = false
				break
		if free:
			return p
	var slot := TAU * float(taken.size()) / float(PACK_MAX) + rng.randf() * 0.4
	return nearest_floor_point(centre + Vector2(cos(slot), sin(slot)) * ZONE_JITTER)


## The kind pool for one tier of the area. Same `minArea` rule the temporal waves used, now fed
## by where the cell is instead of by how long the run has lasted.
func _pick_row(tier: int) -> Dictionary:
	var db: Array = []
	if _data != null:
		db = _data.monsters_for_theme(act_id)
	if db.is_empty():
		return {}
	var pool: Array = []
	for row in db:
		if int(row.get("minArea", 0)) <= tier:
			pool.append(row)
	if pool.is_empty():
		pool = db
	return pool[rng.randi_range(0, pool.size() - 1)]


## The discovery tick: a pack wakes when the hero is inside its cell's ACTIVATE_RADIUS, and it
## WAITS for room rather than spawning over the alive cap.
func _zone_tick() -> void:
	for z in zones:
		if bool(z["active"]):
			continue
		if player_pos.distance_to(z["centre"] as Vector2) > ACTIVATE_RADIUS:
			continue
		var members: Array = z["members"]
		if monsters.size() + members.size() > MAX_ALIVE:
			continue
		_wake_zone(z)


func _wake_zone(z: Dictionary) -> void:
	var ids: Array = []
	var lvl: int = _prog.monster_level(act_id, int(z.get("progress", 0)), 0) if _prog != null else 1
	for m in z["members"]:
		# A pack is never SEEN popping into being: each member is placed at least WAKE_MIN_DIST
		# away, on the side of its cell it would have come from, and walks in from the edge of
		# the screen.
		var opts := {
			"role": str(m.get("role", "normal")),
			"hp_mult": float(m.get("hp_mult", 1.0)),
			"dmg_mult": float(m.get("dmg_mult", 1.0)),
			"xp_mult": float(m.get("xp_mult", 1.0)),
			"loot_grade": int(m.get("loot_grade", 0)),
			"affix": m.get("affix", {}),
			"name": str(m.get("elite_name", "")),
		}
		var rec := _make_monster(m["row"], _spawn_away((m["pos"] as Vector2) - player_pos), lvl, opts)
		monsters.append(rec)
		ids.append(int(rec["id"]))
	z["ids"] = ids
	z["active"] = true
	wave += 1
	events.append("pack")
	if str(z.get("kind", "normal")) != "normal":
		# The screen plays a heavier cue for a champion/elite cell; the rules only say which.
		events.append("pack_%s" % str(z.get("kind")))


## A point `WAKE_MIN_DIST` from the hero in the direction of `prefer`, rotated in 30° steps until
## it lands INSIDE the area. Clamping to the wall is what this replaces: a clamp near an edge
## drags the spawn back toward the hero, which is the visible pop the rule exists to prevent. The
## sweep is bounded; a hero pinned in a corner takes the best direction it has.
func _spawn_away(prefer: Vector2) -> Vector2:
	var base := prefer.normalized() if prefer.length() > 0.001 else Vector2.RIGHT
	for i in 13:
		var k := int(ceil(float(i) / 2.0))
		var dir := base.rotated(deg_to_rad(30.0 * float(k) * (1.0 if i % 2 == 1 else -1.0)))
		var p := player_pos + dir * WAKE_MIN_DIST
		if walkable(p, MON_RADIUS):
			return p
	return nearest_floor_point(player_pos + base * WAKE_MIN_DIST)


## Is this a place a body of `MON_RADIUS` can stand? The old rectangle test is gone: the area is
## the carved corridor, and a point in the middle of the map can be solid rock.
func _inside_area(p: Vector2) -> bool:
	return walkable(p, MON_RADIUS)


func cleared_zones() -> int:
	var n := 0
	for z in zones:
		if bool(z["cleared"]):
			n += 1
	return n


## A pack is cleared when none of ITS ids is alive. The area ends only when every cell has been
## visited and emptied — an unvisited pack is not a cleared area, which is what makes this a map
## to walk rather than a timer to outlast.
func _zone_clear_tick(dt: float) -> void:
	var alive := {}
	for m in monsters:
		alive[int(m["id"])] = true
	for z in zones:
		if bool(z["cleared"]) or not bool(z["active"]):
			continue
		var left := false
		for id in z["ids"]:
			if alive.has(int(id)):
				left = true
				break
		if not left:
			z["cleared"] = true
			events.append("zone")
	if zones.is_empty():
		return
	if not area_cleared and cleared_zones() >= zones.size():
		area_cleared = true
		events.append("cleared")
	# ⚠️  AN EMPTIED ZONE DOES NOT END THE RUN. Jan, Nov 2026: "Musíme zrušit vítěznou
	# obrazovku s lootem. Teď už by vlastně nemělo být nic jako vítězství. Vítězství je, že
	# dojdu na konec lokace, projdu východem do další a tam si vezmu waypoint."
	#
	# So the only thing that ends a run is death (`_die`). Clearing every pack just means the
	# corridor is quiet — the player still has to WALK to the exit, and the loot he left on
	# the floor stays walkable-over for as long as he is down there.


# ============================================================================ spawn

## A STRAY spawn next to the hero — kept because every rules test seeds its actor with it. A real
## run does not trickle enemies any more: they arrive as packs, through `_zone_tick()`.
func _spawn_one() -> void:
	var row := _pick_row(1 + int(elapsed / 45.0))
	if row.is_empty():
		return
	var ang := rng.randf() * TAU
	var dist := rng.randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	var pos := nearest_floor_point(player_pos + Vector2(cos(ang), sin(ang)) * dist)
	var lvl: int = _prog.monster_level(act_id, 0, 0) if _prog != null else 1
	monsters.append(_make_monster(row, pos, lvl))


## Every monster is a WALKING PORTRAIT: the record is the data row's own `face`, so a new
## monster in MONSTER_DB needs no code.
##
## `opts` is what makes a champion/elite pack differ from the same row as a stray: the
## multipliers, the role the screen dresses the ring by, the XP rate and the loot grade. A
## plain wake (and every rules test) passes nothing, which is exactly a normal body.
func _make_monster(row: Dictionary, pos: Vector2, level: int = 1, opts: Dictionary = {}) -> Dictionary:
	# A kind's strength is the DB's own number, scaled by the act's difficulty so a run in a
	# later act is dangerous without a second table.
	var lvl_scale := 1.0 + float(act_id) * 0.35
	var hp_mult := float(opts.get("hp_mult", 1.0))
	var dmg_mult := float(opts.get("dmg_mult", 1.0))
	var role := str(opts.get("role", "normal"))
	var mon_hp := int(round(float(row.get("hp", 60)) * lvl_scale * hp_mult))
	var ranged := _is_ranged(row)
	var base_name := str(row.get("name", ""))
	var name := base_name
	match role:
		"champion":
			name = "%s Champion" % base_name
		"minion":
			name = "%s Slave" % base_name
		"elite":
			name = str(opts.get("name", "")) if str(opts.get("name", "")) != "" else base_name
	var rec := {
		"id": _next_id,
		"face": str(row.get("face", "")),
		"name": name,
		"role": role,
		"pos": pos,
		"hp": mon_hp,
		"max_hp": mon_hp,
		"speed": rng.randf_range(46.0, 68.0) + float(act_id) * 4.0,
		"dmg_min": int(round(float(row.get("dmgMin", 5)) * lvl_scale * dmg_mult)),
		"dmg_max": int(round(float(row.get("dmgMax", 9)) * lvl_scale * dmg_mult)),
		"atk_cd": float(row.get("attackSpeed", 1500)) / 1000.0,
		"atk_ready": 0.0,
		"hit_flash": 0.0,
		# THE MONSTER'S OWN SWING, for the screen to draw. Seconds since it STRUCK (contact
		# damage or a thrown orb), -1 when it has not struck yet, plus the direction it struck
		# in. Presentation only: nothing in this file reads either value back, exactly like
		# `hit_flash`. Without them a monster's attack was a number appearing over the hero and
		# nothing on screen moved — Jan: "u nepřátel musí mít animaci útoku".
		"atk_age": -1.0,
		"atk_dir": Vector2.ZERO,
		"bob": rng.randf() * TAU,
		# A thrower's DISTANCE is part of its record, not a global: the fight has to be able
		# to give two kinds different stand-off ranges without a second table.
		"ranged": ranged,
		"keep_range": KEEP_RANGE,
		"orb_colour": str(row.get("orbColor", ORB_COLOUR)),
		# The monster's own LEVEL VALUE, the same number `battle.gd` calls
		# `monster_level_value`: the XP a kill is worth is derived from it.
		"lvl": level,
		# 1x a stray, 4x a champion, 5x an elite AND its minions (Jan's numbers).
		"xp_mult": float(opts.get("xp_mult", 1.0)),
		# 0 = the normal table, 1 = champion, 2 = elite (`LootSystem.roll`'s grade).
		"loot_grade": int(opts.get("loot_grade", 0)),
		# The elite's D2 affix, as rolled. An `Aura Enchanted` leader has already paid its
		# bonus into the minions' `dmg_*`; the screen reads this to draw the aura.
		"affix": (opts.get("affix", {}) as Dictionary).duplicate(),
	}
	_next_id += 1
	return rec


## A row is a thrower when the PWA itself called it a caster, or when it is on the port's own
## `RANGED_FACES` list — see the constants block for why both inputs exist.
func _is_ranged(row: Dictionary) -> bool:
	if str(row.get("attackType", "")) == "caster":
		return true
	return RANGED_FACES.has(str(row.get("face", "")))


# ============================================================================ monsters

func _move_monsters(dt: float) -> void:
	var alive: Array = []
	for m in monsters:
		m["hit_flash"] = maxf(0.0, float(m["hit_flash"]) - dt)
		if float(m["atk_age"]) >= 0.0:
			m["atk_age"] = float(m["atk_age"]) + dt
		m["bob"] = float(m["bob"]) + dt * 7.0
		# A spell's status window, ticked here so the numbers on the record are the numbers the
		# fight reads. A stunned body does NOTHING (no walk, no hit) — `_take_damage` would
		# otherwise tick through the stun and make Thunder Bolt a slow.
		m["stun_ms"] = maxi(0, int(m.get("stun_ms", 0)) - int(round(dt * 1000.0)))
		m["slow_ms"] = maxi(0, int(m.get("slow_ms", 0)) - int(round(dt * 1000.0)))
		m["block_ms"] = maxi(0, int(m.get("block_ms", 0)) - int(round(dt * 1000.0)))
		if int(m.get("slow_ms", 0)) <= 0:
			m["slow_pct"] = 0.0
		if int(m["stun_ms"]) > 0:
			alive.append(m)
			continue
		var to_hero: Vector2 = player_pos - (m["pos"] as Vector2)
		var gap := to_hero.length()
		var dir := to_hero / gap if gap > 0.001 else Vector2.RIGHT
		var ranged := bool(m["ranged"])
		var walk_mult := 1.0 + float(m.get("slow_pct", 0.0)) / 100.0
		# A thrower stops OUT OF REACH and shoots; a melee kind stops when the two discs touch.
		var stop_at := float(m["keep_range"]) if ranged else BODY_RADIUS * 2.0
		if gap > stop_at:
			var step_len := minf(float(m["speed"]) / walk_mult * dt, gap - stop_at)
			m["pos"] = _step_body(m["pos"] as Vector2, dir * step_len, MON_RADIUS)
		elif ranged and gap < RETREAT_RANGE:
			# Backing off is SLOWER than walking in, and it can be cornered: the arena's
			# edge wins over the caster's comfort.
			var back := minf(float(m["speed"]) * 0.8 / walk_mult * dt, RETREAT_RANGE - gap)
			m["pos"] = _step_body(m["pos"] as Vector2, -dir * back, MON_RADIUS)

		# The gap AFTER the move: the attack must be judged on where the bodies really are,
		# or a caster fires from a distance it has already left.
		var after: float = player_pos.distance_to(m["pos"] as Vector2)
		m["atk_ready"] = maxf(0.0, float(m["atk_ready"]) - dt)
		if int(m.get("block_ms", 0)) > 0:
			# Pummel: the attacks are blocked, the body still walks. The clock is NOT spent
			# while blocked, so the first swing after the window is a real one.
			alive.append(m)
			continue
		if float(m["atk_ready"]) <= 0.0:
			if ranged:
				if after <= SHOOT_RANGE:
					m["atk_ready"] = float(m["atk_cd"]) * walk_mult
					_shoot(m, player_pos - (m["pos"] as Vector2))
			elif after <= stop_at + 1.0:
				# Contact damage. The cooldown is the KIND's own attack speed, so a Bear hits
				# like a bear and a Wolf like a wolf with no extra code.
				m["atk_ready"] = float(m["atk_cd"]) * walk_mult
				# The lunge the screen draws, aimed where the hero actually stands.
				m["atk_age"] = 0.0
				m["atk_dir"] = ((player_pos as Vector2) - (m["pos"] as Vector2)).normalized()
				_take_damage(rng.randi_range(int(m["dmg_min"]), maxi(int(m["dmg_max"]), int(m["dmg_min"]))))
		alive.append(m)
	monsters = alive
	_resolve_bodies()


## The corridor's edge, for anything that only has a TARGET point and no previous one: pull the
## point back onto the nearest floor. The walk itself uses `_step_body`, which slides along the
## rock instead of snapping, but a spawn or a knock-back correction has no previous position.
func _clamp_world(pos: Vector2) -> Vector2:
	return nearest_floor_point(pos, MON_RADIUS)


## One orb, aimed at where the hero IS at the moment of the throw. It is NOT homing: that is
## what makes the distance a skill instead of a formality — stepping out of the line is the
## answer, and a hero who only walks straight in eats every ball.
func _shoot(m: Dictionary, toward: Vector2) -> void:
	var dir := toward.normalized() if toward.length() > 0.001 else Vector2.RIGHT
	# A caster's attack has a body too: it rears back and throws, and that is what the screen
	# draws. Without it the only sign of a shot was the orb already in the air.
	m["atk_age"] = 0.0
	m["atk_dir"] = dir
	var dmg := rng.randi_range(int(m["dmg_min"]), maxi(int(m["dmg_max"]), int(m["dmg_min"])))
	projectiles.append({
		"pos": (m["pos"] as Vector2) + dir * (BODY_RADIUS + 6.0),
		"vel": dir * PROJECTILE_SPEED,
		"dmg": dmg,
		"age": 0.0,
		"colour": str(m["orb_colour"]),
		# WHO threw it. Spell Reflect has to throw the damage back at the thrower, and a
		# projectile with no owner can only be cancelled.
		"owner": int(m["id"]),
	})
	events.append("orb")


## An orb is a BODY with a radius, and it dies on the hero's disc, not on his centre — the same
## rule the hero's own reach uses. A projectile that only tests the centre passes through a
## shoulder, which is exactly the bug "the ball went through me" describes.
func _step_projectiles(dt: float) -> void:
	if projectiles.is_empty():
		return
	var keep: Array = []
	for p in projectiles:
		p["age"] = float(p["age"]) + dt
		var pos: Vector2 = (p["pos"] as Vector2) + (p["vel"] as Vector2) * dt
		p["pos"] = pos
		if float(p["age"]) > PROJECTILE_LIFETIME:
			continue
		if pos.x < -PROJECTILE_RADIUS or pos.y < -PROJECTILE_RADIUS \
				or pos.x > WORLD.x + PROJECTILE_RADIUS or pos.y > WORLD.y + PROJECTILE_RADIUS:
			continue
		if pos.distance_to(player_pos) <= HERO_RADIUS + PROJECTILE_RADIUS:
			events.append("orb_hit")
			_take_damage(int(p["dmg"]))
			continue
		keep.append(p)
	projectiles = keep


## Bodies are SOLID. Jan: "hrdina prochází nepřáteli jakoby to byli duchové. Portréty se nesmí
## překrývat." Two rules, both here so no screen can disagree with them:
##
##   * monster vs monster — pushed apart symmetrically, so a pack spreads instead of stacking;
##   * hero vs monster — the HERO yields, because a player who could shove monsters around would
##     be able to walk the whole arena while touching nothing.
##
## The pass runs AFTER both sides have moved and BEFORE the auto-attack reads distances, so what
## the swing sees is what the player sees.
func _resolve_bodies() -> void:
	var min_gap := BODY_RADIUS * 2.0
	# ORDER MATTERS, and getting it wrong is how "the portraits may not overlap" became "the hero
	# stands inside one". The bodies are settled FIRST and they may never be pushed toward the
	# hero; only then is the hero's own step judged, and a step that ends inside a body is simply
	# NOT TAKEN. That is also the feel Jan asked for: you walk into the pack and you stop.
	for _pass in 4:
		for i in monsters.size():
			for j in range(i + 1, monsters.size()):
				var a: Vector2 = monsters[i]["pos"]
				var b: Vector2 = monsters[j]["pos"]
				var d := a.distance_to(b)
				if d >= min_gap:
					continue
				var dir := (a - b)
				if d <= 0.001:
					dir = Vector2(cos(float(i) * 2.1 + float(_pass)), sin(float(i) * 2.1 + float(_pass)))
					d = 1.0
				var push: Vector2 = dir / d * (min_gap - d) * 0.5
				monsters[i]["pos"] = _keep_off_hero(a + push, min_gap)
				monsters[j]["pos"] = _keep_off_hero(b - push, min_gap)
	if _hero_is_free(min_gap):
		return
	# The hero's own step is refused whole: half a step would still be inside the body.
	player_pos = _prev_pos
	if not _hero_is_free(min_gap):
		# He was ALREADY overlapped when the frame began (a body slid onto him), so the bodies are
		# what yields — radially, away from him, never across him.
		for _pass in 4:
			for m in monsters:
				var off: Vector2 = (m["pos"] as Vector2) - player_pos
				var dist := off.length()
				if dist >= min_gap or dist <= 0.001:
					continue
				var shoved: Vector2 = player_pos + off / dist * min_gap
				if walkable(shoved, MON_RADIUS):
					m["pos"] = shoved


## A body pushed by its neighbour may not be pushed INTO the hero — and it may not be pushed into
## the rock either: a shove that would put it outside the corridor is simply refused, because the
## wall wins over the spacing rule.
func _keep_off_hero(pos: Vector2, min_gap: float) -> Vector2:
	var off: Vector2 = pos - player_pos
	var dist := off.length()
	if dist < min_gap and dist > 0.001:
		pos = player_pos + off / dist * min_gap
	if walkable(pos, MON_RADIUS):
		return pos
	return pos


func _hero_is_free(min_gap: float) -> bool:
	for m in monsters:
		if (m["pos"] as Vector2).distance_to(player_pos) < min_gap - 0.001:
			return false
	return true


func _take_damage(raw: int) -> void:
	# The hero's own defence is the only mitigation in the slice; gear therefore already
	# matters, which is the point of keeping the loot loop attached from day one.
	# Defensive Shout multiplies that armour — it writes `buff_armor_pct` and THIS is the one
	# place that reads it, so a buff cannot end up as a number nothing consumes.
	var eff_def := float(defense) * (1.0 + buff_armor_pct / 100.0)
	var taken := maxi(1, raw - int(eff_def * 0.35))
	hp -= taken
	_add_number(player_pos + Vector2(0, -34), "-%d" % taken, "hurt")
	events.append("hurt")
	if hp <= 0:
		hp = 0
		finished = true
		outcome = "dead"
		events.append("dead")


# ============================================================================ attack

## Pick the body the assist fights, and turn the hero to it. Called once per step, BEFORE the walk,
## so the turn and the closing step are the same frame's decision.
##
## ⚠️  This REPLACED the old per-hand "nearest body in reach" auto-attack. Jan, Nov 2026: the hero
## no longer attacks on his own at all — Diablo 2 Resurrected with a gamepad. Nothing held → no
## target, no swing, and the facing stays the player's.
func _update_target(walking: bool = false) -> void:
	var wants := attack_held or (held_spell != "" and RunSpells.is_offensive(held_spell))
	if not wants or ww_active:
		target_id = -1
		return
	var idx := _pick_target()
	if idx < 0 and not walking:
		# ⚠️  Standing still and holding the attack with everything BEHIND him used to be a dead
		# lock: the facing only changes by walking, and a player holding an attack has no thumb
		# free to walk with. So the assist turns him to the nearest body instead.
		#
		# It only does that while he STANDS. Walking away from a pack must still keep the pack
		# behind him — otherwise "hold attack and run" is the free-hits-while-fleeing exploit the
		# facing rule was written to close.
		idx = _nearest_body()
		# ...and it turns the AIM with him, or the next step would look the old way again and
		# drop the body it just committed to.
		if idx >= 0:
			var turn: Vector2 = (monsters[idx]["pos"] as Vector2) - player_pos
			if turn.length() > 0.001:
				aim = turn.normalized()
	if idx < 0:
		target_id = -1
		return
	target_id = int(monsters[idx]["id"])
	var off: Vector2 = (monsters[idx]["pos"] as Vector2) - player_pos
	if off.length() > 0.001:
		facing = off.normalized()


## The assist's choice. The phone has one thumb on the stick and one on the attack, so there is no
## second cursor: the game ranks what the player is AIMING at (`aim`, not `facing` — see the field's
## own note: `facing` follows the target and would make the choice self-fulfilling).
##
##   * only bodies in FRONT of the AIM (`dot(aim) >= FACING_MIN_DOT`), within `TARGET_RANGE`;
##   * score = distance + missing-health-weighted penalty + an ALIGNMENT penalty, so pushing the
##     stick at the enemy on the right picks that one even when a body straight ahead is nearer.
##     That is Jan's "přejeď zleva doprava a útok se přesměruje";
##   * a candidate must beat the one already chosen by `TARGET_SWITCH_MARGIN` to steal it —
##     without that, two similar bodies trade the target every frame and the hero twitches.
func _pick_target() -> int:
	if monsters.is_empty():
		return -1
	var best := -1
	var best_score := INF
	var cur := -1
	var cur_score := INF
	for i in monsters.size():
		var off: Vector2 = (monsters[i]["pos"] as Vector2) - player_pos
		if off.dot(aim) < FACING_MIN_DOT:
			continue
		var d := off.length()
		if d > TARGET_RANGE + MON_RADIUS:
			continue
		var frac := clampf(float(monsters[i]["hp"]) / maxf(1.0, float(monsters[i]["max_hp"])),
			0.0, 1.0)
		# `1 - dot` is 0 straight ahead and 1 at the edge of the half-plane; multiplied by a pixel
		# weight it puts the alignment on the SAME scale as distance.
		var align := 1.0 - off.normalized().dot(aim) if d > 0.001 else 0.0
		var score := d + frac * TARGET_HP_WEIGHT + align * TARGET_AIM_WEIGHT
		if int(monsters[i]["id"]) == target_id:
			cur = i
			cur_score = score
		if score < best_score:
			best_score = score
			best = i
	if best < 0:
		return -1
	if cur >= 0 and cur != best and best_score > cur_score * (1.0 - TARGET_SWITCH_MARGIN):
		return cur
	return best


## The nearest body in ANY direction, inside the picker's range. The turn-around case only: the
## aim rule is still "in front", and this is what lets a standing hero face a pack that surrounded
## him instead of freezing.
func _nearest_body() -> int:
	var limit := TARGET_RANGE + MON_RADIUS
	var best := limit * limit
	var found := -1
	for i in monsters.size():
		var d2: float = (monsters[i]["pos"] as Vector2).distance_squared_to(player_pos)
		if d2 <= best:
			best = d2
			found = i
	return found


## The chosen body's index in `monsters`, or -1 when it died / was never picked. The screen reads
## this to mark the target, so it must be cheap and safe to call anywhere.
func target_index() -> int:
	if target_id < 0:
		return -1
	return _index_of_monster(target_id)


## ONE clock for both hands, and the hands STRICTLY ALTERNATE. The pair's interval is the
## HARMONIC mean of the two hands (1/T = 1/T_main + 1/T_off), so each weapon keeps its own speed:
## an average halves both rates, which is exactly what Jan felt — "každá čeká na svůj plný swing
## … i když jsou to jednoruční zbraně, tak se chovají jako velmi pomalé zbraně."
##
## ⚠️  The port also ran two INDEPENDENT clocks here for one branch. The numbers were right and
## the FEEL was wrong: the arcs drifted apart and the hero struck with both weapons at the same
## instant. Jan: "obě zbraně sekají ve stejnou dobu … daleko uspokojivější je, když se zbraně
## plynule střídají."
##
## A HELD attack button swings as soon as the clock is ready — Jan's own rule ("hrdina neútočí
## automaticky"), and the clock always runs down, so a hero who lets go keeps his progress.
func _attack_tick(dt: float) -> void:
	_main_clock = maxf(0.0, _main_clock - dt)
	# `_off_clock` is kept only so a save/test that pokes it cannot break: there is no second
	# clock any more, and nothing reads it to decide a swing.
	_off_clock = 0.0
	# A HELD spell button repeats itself: the GCD and the spell's cooldown are the pacing, so
	# holding Thunder Clap is "cast it whenever it is ready", not a second, faster rule.
	if held_spell != "":
		_repeat_held_spell()
	if not attack_held:
		return
	# A spell on hold owns the attack button: swings would be a second action under one thumb.
	if ww_active or held_spell != "" or monsters.is_empty():
		return
	if _main_clock > 0.0:
		return
	# The hand that takes this beat. An off-hand beat needs a body inside the OFF weapon's own
	# reach; with nothing there, the main hand takes the beat rather than the swing being lost.
	var is_off := off_swing > 0.0 and _next_hand_off
	var reach := reach_off if is_off else reach_main
	var idx := target_index()
	if idx < 0 or not _in_reach(idx, reach):
		if is_off:
			# Fall back to the main hand — and keep the pair in alternation.
			is_off = false
			reach = reach_main
			idx = target_index()
		if idx < 0 or not _in_reach(idx, reach):
			return
	_main_clock = _main_interval()
	# ⚠️  Read the ID BEFORE the blow: this swing can KILL, and `_kill` removes the entry —
	# `monsters[idx]` after it is either the next body or an index error.
	_swing_hand(idx, is_off)
	if off_swing > 0.0:
		_next_hand_off = not is_off


## Cast the held spell again if it is ready. A refusal is NOT reported here: the button is held,
## so "Globalni cooldown" every half second would be a wall of text instead of a cast.
func _repeat_held_spell() -> void:
	if not RunSpells.is_offensive(held_spell):
		return
	if not RunSpells.can_cast(self, held_spell):
		return
	cast_spell(held_spell)


## Is a body's own rim inside a hand's drawn circle? Bodies, not centres — the same semantics the
## drawn reach ring promises (`HIT_REACH`).
func _in_reach(index: int, reach: float) -> bool:
	if index < 0 or index >= monsters.size():
		return false
	return (monsters[index]["pos"] as Vector2).distance_to(player_pos) <= reach + MON_RADIUS


## Seconds per beat. One clock for both hands (they alternate), so this is the PAIR's interval:
## the main hand's own when he holds one weapon, the harmonic mean of the two when he holds two.
## Frenzy is the only thing that changes it — each stack takes `lv + 1` % off the pair, and the
## 0.45 s floor is kept so a buffed hero cannot swing faster than the animation can be read.
func _main_interval() -> float:
	var pct := _frenzy_speed_pct()
	if pct <= 0.0:
		return main_swing
	return maxf(0.45, main_swing * (1.0 - pct / 100.0))


## The OFF hand's own interval, as INFORMATION (the screen and the tests read it). It is not a
## clock: the beat is `_main_clock` and the hand that takes it alternates.
func _off_interval() -> float:
	return off_swing


func _frenzy_speed_pct() -> float:
	if frenzy_stacks <= 0 or frenzy_ms <= 0:
		return 0.0
	var lv := 1
	if _state != null:
		var cid := str(_state.data.get("heroClass", ""))
		lv = maxi(PlayerSpells.spell_level(_state, cid, "frenzy"), 1)
	return float(frenzy_stacks * (lv + 1))


## The nearest body whose rim crosses `reach`'s circle AND that stands IN FRONT of the hero,
## skipping one id (so the two hands do not both land on the same portrait). `-1` skips nothing.
##
## The facing test is on the BODY's direction, not on the target's centre only: a body at
## point-blank behind him has a centre with a negative dot and is correctly refused, which is the
## whole point of the rule.
func _nearest_in_reach(reach: float, exclude_id: int) -> int:
	var limit := reach + MON_RADIUS
	var best := limit * limit
	var found := -1
	for i in monsters.size():
		if exclude_id >= 0 and int(monsters[i]["id"]) == exclude_id:
			continue
		var off: Vector2 = (monsters[i]["pos"] as Vector2) - player_pos
		if off.dot(facing) < FACING_MIN_DOT:
			continue
		var d2 := off.length_squared()
		if d2 <= best:
			best = d2
			found = i
	return found


## One hand's landing blow. `index` is valid at call time; a kill removes the monster and no
## later hand may use that index.
##
## The two queues and the one buff are consumed HERE, because this is where a blow is really
## dealt: Heroic Strike multiplies this swing (`100 + lv*100` %, so lv1 is 200 %), Frenzy adds a
## stack instead and Battle Shout's percentage applies to every swing while it lasts.
func _swing_hand(index: int, is_off: bool) -> void:
	var m: Dictionary = monsters[index]
	var lo := dmg_off_min if is_off else dmg_min
	var hi := dmg_off_max if is_off else dmg_max
	var hand_crit := crit_off if is_off else crit_chance
	var dmg := rng.randi_range(lo, maxi(hi, lo))
	var crit := hand_crit > 0.0 and rng.randf() * 100.0 < hand_crit
	if crit:
		dmg = int(round(float(dmg) * 2.0))
	if buff_dmg_pct > 0.0:
		dmg = int(round(float(dmg) * (1.0 + buff_dmg_pct / 100.0)))
	if not is_off and heroic_queued:
		heroic_queued = false
		var lv := maxi(PlayerSpells.spell_level(_state, str(_state.data.get("heroClass", "")),
			"heroicStrike"), 1)
		dmg = int(round(float(dmg) * (1.0 + float(100 * lv) / 100.0)))
		_add_number((m["pos"] as Vector2) + Vector2(0, -52), "HEROIC", "word")
	if not is_off and frenzy_queued:
		frenzy_queued = false
		_apply_frenzy_stack()
	m["hp"] = int(m["hp"]) - dmg
	m["hit_flash"] = 0.12
	var toward: Vector2 = (m["pos"] as Vector2) - player_pos
	var dir := toward.normalized() if toward.length() > 0.001 else Vector2.RIGHT
	if is_off:
		swing_dir_off = dir
		swing_age_off = 0.0
	else:
		swing_dir = dir
		swing_age = 0.0
	var kind := "hit"
	if crit:
		kind = "crit"
	elif is_off:
		kind = "hit_off"
	_add_number((m["pos"] as Vector2) + Vector2(0, -30), str(dmg), kind)
	events.append("crit" if crit else "hit")
	if int(m["hp"]) <= 0:
		_kill(index)


## XP and LEVEL-UPS — the same rule as `arena_screen.apply_levels()`: 40 XP buys level 2, then
## 80 per level, capped at 60; every level refills HP, pays 5 attribute points and 1 talent
## point. It runs DURING the run (a kill can level the hero mid-fight), which is why the run's
## own hp/max_hp are re-read here — the arena only ever levels between fights.
func _award_xp(amount: int) -> void:
	if amount <= 0:
		return
	var hero: Dictionary = _state.hero()
	hero["xp"] = int(hero.get("xp", 0)) + amount
	xp_gained += amount
	var safety := 0
	while safety < 100 and int(hero.get("level", 1)) < 60:
		safety += 1
		var lvl := int(hero["level"])
		var need := lvl * 40 if lvl <= 2 else lvl * 80
		if int(hero.get("xp", 0)) < need:
			break
		hero["xp"] = int(hero["xp"]) - need
		hero["level"] = lvl + 1
		hero["maxHp"] = _gen.hero_max_hp(hero, _state.equip(), _find_item)
		hero["hp"] = hero["maxHp"]
		hero["attrPoints"] = int(hero.get("attrPoints", 0)) + 5
		_state.data["talentPoints"] = int(_state.data.get("talentPoints", 0)) + 1
		# The RUN's own body: a level heals him where he stands, or the level-up would be a
		# number in a save the player cannot feel until the run is over.
		max_hp = int(hero["maxHp"])
		hp = max_hp
		levels_gained += 1
		events.append("levelup")


func _kill(index: int) -> void:
	var m: Dictionary = monsters[index]
	kills += 1
	# XP per kill, the arena's own rule (`Progression.kill_xp` with the monster's level value):
	# the survivor run is going to REPLACE the duel, so it has to pay the same currency. The
	# pack's OWN rate multiplies it: 4x for a champion, 5x for an elite and its minions.
	var xp_mult := float(m.get("xp_mult", 1.0))
	var xp := int(round(float(_prog.kill_xp(int(_state.hero().get("level", 1)),
		int(m.get("lvl", 1)), 1)) * xp_mult))
	_award_xp(xp)
	events.append("kill")
	_roll_drop(m["pos"] as Vector2, int(m.get("loot_grade", 0)), int(m.get("lvl", 1)))
	monsters.remove_at(index)


# ============================================================================ loot

## The drop table is the PWA's own: `LootSystem.roll()` decides gold vs an item
## vs a special, so the survivor loop and the duel pay out through the same code.
##
## `grade` is the kill's rank (0 normal, 1 champion, 2 elite) and it is the ONLY difference:
## the table itself stays one table, so a better body cannot invent a drop the game never had.
##
## ⚠️  THE DEPTH IS THE AREA, NOT THE PACK COUNT, and the ITEM LEVEL is the MONSTER'S. Both
## were wrong here and both are what Jan saw as "elitní věci padají v aktu 1":
##   * `wave` (how many packs have woken, 0-30) was passed as the floor, which the item table
##     turns into a global depth — so the last packs of act 1 dropped act-4 gear.
##   * the HERO's level was passed as `monster_level`, so an act-1 skeleton rolled level-20
##     affixes; `ItemGen.generate` takes `min(monster_level, hero_level)` as ilvl, which is
##     only meaningful if the first number really is the monster's.
func _roll_drop(pos: Vector2, grade: int = 0, monster_lvl: int = 1) -> void:
	var magic_find := int(Progression._equip_attr(_state.equip(), _find_item, "magicFind"))
	var gold_find := int(Progression._equip_attr(_state.equip(), _find_item, "goldFind"))
	var result: Dictionary = _loot.roll(_state, act_id, zone_index, false,
		maxi(1, monster_lvl), magic_find, gold_find, rng, grade)
	var kind := str(result.get("type", "gold"))
	if kind == "gold":
		drops.append({"pos": pos, "kind": "gold", "amount": int(result.get("gold", 1)), "age": 0.0})
		return
	var item: Dictionary = result.get("item", {})
	if item.is_empty():
		return
	if int(result.get("gold", 0)) > 0:
		drops.append({"pos": pos, "kind": "gold", "amount": int(result.get("gold", 0)), "age": 0.0})
	drops.append({"pos": pos + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12)),
		"kind": "item", "item": item, "age": 0.0,
		"color": _quality_color(str(item.get("quality", "normal")))})


func _quality_color(quality: String) -> String:
	if _data == null:
		return "#888888"
	var table = _data.table("QUALITY_COLORS", {})
	if typeof(table) != TYPE_DICTIONARY:
		return "#888888"
	return str((table as Dictionary).get(quality, "#888888"))


## Drops are MAGNETISED inside 96 px and picked up at 30 px. The pull is what makes walking
## over a kill feel like collecting instead of aiming at coins, and it is why the phone's
## thumb never has to be precise about loot.
func _move_drops(dt: float) -> void:
	var keep: Array = []
	for d in drops:
		d["age"] = float(d["age"]) + dt
		var pos: Vector2 = d["pos"]
		var gap := pos.distance_to(player_pos)
		if gap <= PICKUP_RADIUS:
			# ⚠️  `_collect` must NOT append back into `drops` while this loop runs: a refused
			# item is still inside the pickup radius, so appending it made the array grow
			# under the `for` and the collect ran forever. It returns whether it consumed the
			# drop instead, and a refusal is kept exactly where it was.
			if _collect(d):
				continue
			keep.append(d)
			continue
		if gap <= MAGNET_RADIUS:
			d["pos"] = pos + (player_pos - pos).normalized() * minf(MAGNET_SPEED * dt, gap)
		keep.append(d)
	drops = keep


## Returns TRUE when the drop was consumed (gold banked, item bagged) and FALSE when it has to
## stay on the ground.
func _collect(d: Dictionary) -> bool:
	if str(d["kind"]) == "gold":
		gold += int(d["amount"])
		_state.hero()["gold"] = int(_state.hero().get("gold", 0)) + int(d["amount"])
		_add_number(player_pos + Vector2(rng.randf_range(-14, 14), -44), "+%d" % int(d["amount"]), "gold")
		events.append("gold")
		return true
	var item: Dictionary = d["item"]
	if _state.bag_full():
		# ⚠️  A full bag LEAVES the item on the ground, exactly as the loot panel does.
		# Destroying a visible drop because the bag is full is the worst bug a loot game can
		# have, and here it would also be invisible: no panel, no refusal message.
		events.append("bagfull")
		return false
	_state.register_loot_item(item)
	_state.add_item(str(item.get("id", "")), item)
	items_taken += 1
	# Kept for the RESULT PAGE, which lists what the run actually paid out. The bag is the
	# truth for the save; this is the receipt.
	looted.append(item)
	_add_number(player_pos + Vector2(0, -48), str(item.get("name", "Predmet")), "item")
	return true


func _add_number(pos: Vector2, text: String, kind: String) -> void:
	numbers.append({"pos": pos, "text": text, "kind": kind, "age": 0.0})


func _age_numbers(dt: float) -> void:
	var keep: Array = []
	for n in numbers:
		n["age"] = float(n["age"]) + dt
		if float(n["age"]) < 0.85:
			keep.append(n)
	numbers = keep


# ============================================================================ helpers

func alive_count() -> int:
	return monsters.size()


# ============================================================================ spells

## The bar the screen draws. The rule lives in `run_spells.gd` — this only forwards.
func spell_bar() -> Array:
	return RunSpells.bar(self)


## Cast one class spell. The rule lives in `run_spells.gd`; this forwards and keeps the run's
## own bookkeeping (the mana copy in the save) in one place.
func cast_spell(spell_id: String) -> Dictionary:
	var result: Dictionary = RunSpells.cast(self, spell_id)
	if bool(result.get("ok", false)):
		events.append("cast")
		_sync_mana()
	return result


## The float copy of the mana pool is the truth DURING the run; the save gets the integer,
## because every other screen (and the duel) reads `hero.mana` as an int.
func _sync_mana() -> void:
	if _state == null:
		return
	_state.hero()["mana"] = clampi(int(floor(mana)), 0, maxi(max_mana, 1))


## One damage roll of the hand's own weapon, through the same `dmg_min/dmg_max` the swings use,
## so a spell's damage is in the same currency as a blow and the loot loop stays honest.
func _roll_damage(is_off: bool) -> int:
	var lo := dmg_off_min if is_off else dmg_min
	var hi := dmg_off_max if is_off else dmg_max
	return rng.randi_range(lo, maxi(hi, lo))


## A spell's landing blow on one body. The word is the spell's name, drawn over the portrait the
## way the duel floats its own note ("DOUBLE SWING 45") — the same receipt, on a crowd.
func _hurt_monster(index: int, dmg: int, word: String) -> void:
	if index < 0 or index >= monsters.size():
		return
	var m: Dictionary = monsters[index]
	m["hp"] = int(m["hp"]) - dmg
	m["hit_flash"] = 0.14
	var toward: Vector2 = (m["pos"] as Vector2) - player_pos
	if toward.length() > 0.001:
		swing_dir = toward.normalized()
		swing_age = 0.0
	_add_number((m["pos"] as Vector2) + Vector2(0, -30), str(dmg), "spell")
	if word != "":
		_add_number((m["pos"] as Vector2) + Vector2(0, -54), word, "word")
	events.append("hit")
	if int(m["hp"]) <= 0:
		_kill(index)


## A slow window on one body: `pct` % off its walk AND its attack clock, for `ms`.
func _slow_monster(index: int, pct: float, ms: int) -> void:
	if index < 0 or index >= monsters.size():
		return
	var m: Dictionary = monsters[index]
	m["slow_pct"] = maxf(float(m.get("slow_pct", 0.0)), pct)
	m["slow_ms"] = maxi(int(m.get("slow_ms", 0)), ms)
	_add_number((m["pos"] as Vector2) + Vector2(0, -46), "SLOW", "word")


## A stun window on one body: it neither walks nor hits, and the arc of its next attack is not
## spent while it is out.
func _stun_monster(index: int, ms: int) -> void:
	if index < 0 or index >= monsters.size():
		return
	var m: Dictionary = monsters[index]
	m["stun_ms"] = maxi(int(m.get("stun_ms", 0)), ms)


## Pummel's window: the body's attacks are blocked for `ms`, the body itself keeps walking.
func _block_monster(index: int, ms: int) -> void:
	if index < 0 or index >= monsters.size():
		return
	monsters[index]["block_ms"] = maxi(int(monsters[index].get("block_ms", 0)), ms)


## One Frenzy stack, and it is the MAIN hand's landed hit that earns it — the same rule the duel
## has ("a missed Frenzy costs the mana and gives no stack").
func _apply_frenzy_stack() -> void:
	frenzy_stacks = mini(5, frenzy_stacks + 1)
	frenzy_ms = RunSpells.FRENZY_MS
	_add_number(player_pos + Vector2(0, -56), "FRENZY %d/5" % frenzy_stacks, "word")


func _say_word(text: String) -> void:
	_add_number(player_pos + Vector2(0, -62), text, "word")


# ============================================================================ bolts & effects

## Fire the hero's own spell projectile at a point. The direction is FIXED at cast time (not
## homing) — the same rule the enemy's orbs obey, so stepping aside is still the answer to a
## thrown thing and the aimed spell never curves into a body the hero did not face.
func cast_bolt(at: Vector2, dmg: int, stun_ms: int, colour: String) -> void:
	var toward: Vector2 = at - player_pos
	var dir := toward.normalized() if toward.length() > 0.001 else facing
	bolts.append({
		"pos": player_pos + dir * (HERO_RADIUS + 4.0),
		"vel": dir * BOLT_SPEED,
		"dmg": dmg,
		"stun_ms": stun_ms,
		"age": 0.0,
		"colour": colour,
	})
	# The cast itself is drawn as a small burst at the hand, so a bolt that has already left is
	# still explained by something happening where the hero stands.
	add_effect("ring", player_pos, {"life": 0.30, "colour": colour,
		"data": {"count": 2, "r0": 8.0, "r1": 34.0, "delay": 0.10, "width": 3.0}})


## A bolt is a BODY with a radius, exactly like an orb: it dies on the first body whose disc it
## touches, and it hits THAT body — not the one it was aimed at, which is what makes a line of
## enemies worth thinking about.
func _step_bolts(dt: float) -> void:
	if bolts.is_empty():
		return
	var keep: Array = []
	for b in bolts:
		b["age"] = float(b["age"]) + dt
		if float(b["age"]) > BOLT_LIFETIME:
			continue
		var pos: Vector2 = (b["pos"] as Vector2) + (b["vel"] as Vector2) * dt
		b["pos"] = pos
		var hit := -1
		for i in monsters.size():
			if pos.distance_to(monsters[i]["pos"] as Vector2) <= MON_RADIUS + BOLT_RADIUS:
				hit = i
				break
		if hit >= 0:
			var m: Dictionary = monsters[hit]
			# The impact is a spiral on the body, the PWA's own shape for a bolt landing.
			add_effect("spiral", m["pos"] as Vector2, {"life": 0.50, "colour": str(b["colour"])})
			if int(b["stun_ms"]) > 0:
				m["stun_ms"] = maxi(int(m.get("stun_ms", 0)), int(b["stun_ms"]))
			_hurt_monster(hit, int(b["dmg"]), "")
			continue
		keep.append(b)
	bolts = keep


## Register one visual effect. `data` carries the shape's own numbers so the screen draws it
## without a second table; `life` is seconds on the run's fixed clock, never wall time.
func add_effect(kind: String, pos: Vector2, opts: Dictionary = {}) -> void:
	effects.append({
		"kind": kind,
		"pos": pos,
		"age": 0.0,
		"life": float(opts.get("life", 0.8)),
		"colour": str(opts.get("colour", "#e74c3c")),
		"data": opts.get("data", {}),
	})


## The duel's shout wave: five rings leaving the figure, 800 ms, the later ones delayed. The
## delays and the radii are the PWA's own (`10 + p * 250`), scaled down to the run's world so a
## wave does not cover the whole phone screen.
func add_shout_rings(colour: String) -> void:
	add_effect("ring", player_pos, {"life": 0.80, "colour": colour,
		"data": {"count": 5, "r0": 10.0, "r1": 148.0, "delay": 0.10, "width": 4.0}})


func _age_effects(dt: float) -> void:
	if effects.is_empty():
		return
	var keep: Array = []
	for e in effects:
		e["age"] = float(e["age"]) + dt
		if float(e["age"]) <= float(e["life"]):
			keep.append(e)
	effects = keep


func _index_of_monster(id: int) -> int:
	for i in monsters.size():
		if int(monsters[i]["id"]) == id:
			return i
	return -1


# ============================================================================ whirlwind

## Arm the flurry. Its strikes are dealt by `answer_whirlwind`, one press at a time, so nothing
## here applies damage — a flurry that ran to completion inside one call would be a damage spell
## with extra steps, and the whole point is that it stops when the player gets one wrong.
func start_whirlwind(dirs: Array, reaction_ms: int) -> void:
	ww_dirs = dirs.duplicate()
	ww_index = 0
	ww_landed = 0
	ww_active = not ww_dirs.is_empty()
	ww_reaction_ms = reaction_ms
	ww_deadline_ms = reaction_ms if ww_active else 0
	ww_feedback = ""
	# The flurry REPLACES the hero's swings rather than adding to them: BOTH hands start over,
	# which is the deliberate exception to the independent clocks.
	_main_clock = main_swing
	_next_hand_off = false


func whirlwind_open() -> bool:
	return ww_active


func whirlwind_prompt() -> String:
	if not ww_active or ww_index >= ww_dirs.size():
		return ""
	return str(ww_dirs[ww_index])


## The press, from the screen. A correct key lands one strike; a wrong one ends the flurry with
## what was already landed.
func answer_whirlwind(key: String) -> Dictionary:
	if not ww_active:
		return {"ok": false, "result": "none", "prompt": ""}
	if key != whirlwind_prompt():
		ww_active = false
		ww_deadline_ms = 0
		ww_feedback = "fail"
		_main_clock = main_swing
		_next_hand_off = false
		return {"ok": false, "result": "fail", "prompt": ""}
	ww_index += 1
	_whirlwind_strike()
	if ww_index >= ww_dirs.size():
		ww_active = false
		ww_deadline_ms = 0
		ww_feedback = "complete"
		_main_clock = main_swing
		_next_hand_off = false
		events.append("strong_strike")
	else:
		ww_deadline_ms = ww_reaction_ms
	return {"ok": true, "result": "strike", "landed": ww_landed, "prompt": whirlwind_prompt()}


## The deadline ran out on the current key: the flurry ends, landed strikes kept.
func whirlwind_timeout() -> void:
	if not ww_active:
		return
	ww_active = false
	ww_deadline_ms = 0
	ww_feedback = "fail"
	_main_clock = main_swing
	_next_hand_off = false


## The flurry's own word, drained by the screen ("complete" / "fail"), plus the strikes landed.
func take_whirlwind_result() -> Dictionary:
	var out := {"feedback": ww_feedback, "landed": ww_landed}
	ww_feedback = ""
	return out


## One strike of the flurry. In the duel Whirlwind hit the one enemy; here it is a SPIN, so it
## lands on every body inside the main hand's reach — that is what makes a flurry a crowd spell
## instead of a slower swing. The damage spread is the duel's own ±25 % (`0.75 + rand*0.5`), not
## the weapon's range, and Battle Shout applies on top.
##
## The list is walked BACKWARDS: a kill removes an entry, and an index taken before the removal
## is the next body or an index error — the same trap the drop loop documents.
func _whirlwind_strike() -> void:
	var limit := reach_main + MON_RADIUS
	var victims: Array = []
	for i in monsters.size():
		var off: Vector2 = (monsters[i]["pos"] as Vector2) - player_pos
		if off.dot(facing) < FACING_MIN_DOT:
			continue
		if off.length_squared() <= limit * limit:
			victims.append(i)
	for k in range(victims.size() - 1, -1, -1):
		var i: int = victims[k]
		var dmg := float(_roll_damage(false)) * (0.75 + rng.randf() * 0.5)
		if buff_dmg_pct > 0.0:
			dmg *= 1.0 + buff_dmg_pct / 100.0
		ww_landed += 1
		_hurt_monster(i, maxi(1, int(round(dmg))), "")
		events.append(Sfx.cue_for_weapon(main_weapon, false))


func drain_events() -> Array:
	var out := events.duplicate()
	events.clear()
	return out
