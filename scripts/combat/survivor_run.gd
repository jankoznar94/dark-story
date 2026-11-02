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

## --- the arena -------------------------------------------------------------
## The world is bigger than the phone's viewport (390x844), so the camera FOLLOWS the
## hero and the run reads as travel instead of a fixed stage. These are world pixels.
const WORLD := Vector2(1500.0, 2100.0)
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
const AREA_MARGIN := 96.0
const ZONE_COLS := 3
const ZONE_ROWS := 3
const PACK_MIN := 2
const PACK_MAX := 4
## How far a pack's members scatter from its cell centre, and the least gap between two of them.
## The gap is bigger than one disc (62) on purpose: a pack is a formation, not a pile.
const ZONE_JITTER := 104.0
const PACK_SPACING := 70.0
const ACTIVATE_RADIUS := 330.0
## How far from the hero a woken pack is placed. The phone screen is 390x844, so half of it is
## 195 px across and 422 px down: a pack that appeared at 330 would POP into view in the middle of
## the field, which is exactly the seam Jan would notice. At 470 the bodies arrive from OFF the
## screen and walk in, which also gives the player the beat of hearing/seeing them come.
const WAKE_MIN_DIST := 470.0
## After the LAST pack dies the run keeps running this long: the final kill's loot has to be
## walkable-over, or the payout of the winning blow is the one drop the player never gets.
const CLEAR_DELAY := 2.0

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

## --- loot ------------------------------------------------------------------
const PICKUP_RADIUS := 30.0
const MAGNET_RADIUS := 96.0
const MAGNET_SPEED := 430.0

var _data: Node
var _state
var _find_item: Callable
var _loot: LootSystem
var _gen: ItemGen
var rng := RandomNumberGenerator.new()

var act_id := 0
var player_pos := Vector2.ZERO
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
## Orbs in flight: {pos, vel, dmg, age, colour}. Simulated here, painted by the screen.
var projectiles: Array = []
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
## Set the moment the last pack dies; `finished` follows after CLEAR_DELAY.
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
## "" | "dead"
var outcome := ""

var _clear_clock := 0.0
var _main_clock := 0.0
var _off_clock := 0.0
## The monster the MAIN hand just hit, so the off hand prefers a different body. -1 = no
## preference (the main hand has not swung at anything).
var _off_prefer_id := -1
var _next_id := 0
## The hero's position at the START of the frame: the only honest place to send him back to
## when his own step would put him inside a body.
var _prev_pos := Vector2.ZERO


## `seed_value` is what makes a run reproducible: the tests drive one seed, the screen
## seeds from the clock. Passing 0 means "use entropy".
func setup(state, find_item: Callable, loot_system, act: int, seed_value: int = 0) -> void:
	_state = state
	_find_item = find_item
	_loot = loot_system
	_data = state.data_ref() if state.has_method("data_ref") else null
	act_id = act
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	var hero: Dictionary = state.hero()
	_gen = ItemGen.new(_data)
	var _prog := Progression.new(_data)
	max_hp = _gen.hero_max_hp(hero, state.equip(), find_item)
	hp = max_hp
	defense = int(_prog.total_defense(state.equip(), find_item))
	var roll: Dictionary = Progression.hero_dmg(hero, state.equip(), find_item)
	dmg_min = int(roll["min"])
	dmg_max = int(roll["max"])
	_read_hands()

	player_pos = WORLD * 0.5
	monsters.clear()
	projectiles.clear()
	drops.clear()
	numbers.clear()
	events.clear()
	_build_area()
	kills = 0
	wave = 0
	elapsed = 0.0
	gold = 0
	items_taken = 0
	finished = false
	outcome = ""
	area_cleared = false
	_clear_clock = 0.0
	_main_clock = 0.0
	_off_clock = 0.0
	_next_id = 0
	swing_age = -1.0
	swing_dir = Vector2.RIGHT
	swing_age_off = -1.0
	swing_dir_off = Vector2.RIGHT


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
		# Each hand swings at its OWN pace. Averaging the two is what made an off-hand dagger
		# obey the main hand's axe, and it also hid the whole point of a fast weapon.
		off_swing = float(Progression.swing_time(rng, off_weapon, dex_total, glove_ias)) / 1000.0
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
	_move_hero(dt, move)
	_zone_tick()
	_move_monsters(dt)
	_auto_attack(dt)
	_step_projectiles(dt)
	_move_drops(dt)
	_age_numbers(dt)
	_zone_clear_tick(dt)


func _move_hero(dt: float, move: Vector2) -> void:
	var dir := move.limit_length(1.0)
	if dir.length_squared() <= 0.0001:
		return
	player_pos += dir * hero_speed() * dt
	player_pos.x = clampf(player_pos.x, AREA_MARGIN + HERO_RADIUS, WORLD.x - AREA_MARGIN - HERO_RADIUS)
	player_pos.y = clampf(player_pos.y, AREA_MARGIN + HERO_RADIUS, WORLD.y - AREA_MARGIN - HERO_RADIUS)


# ============================================================================ area

## The cell grid, in world pixels. Every centre sits in the middle of its own cell, and the hero
## spawns in the exact middle of the middle one.
static func zone_centres() -> Array:
	var out: Array = []
	var w := WORLD.x - AREA_MARGIN * 2.0
	var h := WORLD.y - AREA_MARGIN * 2.0
	for r in ZONE_ROWS:
		for c in ZONE_COLS:
			out.append(Vector2(
				AREA_MARGIN + w * (float(c) + 0.5) / float(ZONE_COLS),
				AREA_MARGIN + h * (float(r) + 0.5) / float(ZONE_ROWS)))
	return out


## One pack per cell, the hero's own cell left EMPTY. `minArea` is honoured by DISTANCE from the
## start instead of elapsed time: the far corners hold the heavy kinds, so walking deeper is what
## raises the stakes and the run cannot be farmed by standing still.
func _build_area() -> void:
	zones.clear()
	var centre_start := WORLD * 0.5
	var centres := zone_centres()
	var max_d := 1.0
	for c in centres:
		max_d = maxf(max_d, (c as Vector2).distance_to(centre_start))
	for c in centres:
		var centre: Vector2 = c
		if centre.distance_to(centre_start) < 1.0:
			continue
		var tier := 1 + int(round(3.0 * centre.distance_to(centre_start) / max_d))
		var members: Array = []
		for _i in rng.randi_range(PACK_MIN, PACK_MAX):
			var row := _pick_row(tier)
			if row.is_empty():
				continue
			members.append({"row": row, "pos": _pack_slot(centre, members)})
		if members.is_empty():
			continue
		zones.append({
			"centre": centre,
			"members": members,
			"active": false,
			"cleared": false,
			"ids": [],
		})


## A free spot inside a pack, at least PACK_SPACING from every other member. Rejection for a
## BOUNDED number of tries and then a ring slot: two discs stacked on each other is a bad pack,
## but a "find room" loop that can fail forever is a hang, which is worse.
func _pack_slot(centre: Vector2, taken: Array) -> Vector2:
	for _try in 14:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(26.0, ZONE_JITTER)
		var p := _clamp_world(centre + Vector2(cos(ang), sin(ang)) * dist)
		var free := true
		for m in taken:
			if p.distance_to(m["pos"] as Vector2) < PACK_SPACING:
				free = false
				break
		if free:
			return p
	var slot := TAU * float(taken.size()) / float(PACK_MAX) + rng.randf() * 0.4
	return _clamp_world(centre + Vector2(cos(slot), sin(slot)) * ZONE_JITTER)


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
	for m in z["members"]:
		# A pack is never SEEN popping into being: each member is placed at least WAKE_MIN_DIST
		# away, on the side of its cell it would have come from, and walks in from the edge of
		# the screen.
		var rec := _make_monster(m["row"], _spawn_away((m["pos"] as Vector2) - player_pos))
		monsters.append(rec)
		ids.append(int(rec["id"]))
	z["ids"] = ids
	z["active"] = true
	wave += 1
	events.append("pack")


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
		if _inside_area(p):
			return p
	return _clamp_world(player_pos + base * WAKE_MIN_DIST)


func _inside_area(p: Vector2) -> bool:
	return p.x >= AREA_MARGIN + MON_RADIUS and p.x <= WORLD.x - AREA_MARGIN - MON_RADIUS \
		and p.y >= AREA_MARGIN + MON_RADIUS and p.y <= WORLD.y - AREA_MARGIN - MON_RADIUS


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
		_clear_clock = CLEAR_DELAY
		events.append("cleared")
	if area_cleared and not finished:
		_clear_clock -= dt
		if _clear_clock <= 0.0:
			finished = true
			outcome = "cleared"


# ============================================================================ spawn

## A STRAY spawn next to the hero — kept because every rules test seeds its actor with it. A real
## run does not trickle enemies any more: they arrive as packs, through `_zone_tick()`.
func _spawn_one() -> void:
	var row := _pick_row(1 + int(elapsed / 45.0))
	if row.is_empty():
		return
	var ang := rng.randf() * TAU
	var dist := rng.randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	var pos := _clamp_world(player_pos + Vector2(cos(ang), sin(ang)) * dist)
	monsters.append(_make_monster(row, pos))


## Every monster is a WALKING PORTRAIT: the record is the data row's own `face`, so a new
## monster in MONSTER_DB needs no code.
func _make_monster(row: Dictionary, pos: Vector2) -> Dictionary:
	# A kind's strength is the DB's own number, scaled by the act's difficulty so a run in a
	# later act is dangerous without a second table.
	var lvl_scale := 1.0 + float(act_id) * 0.35
	var mon_hp := int(round(float(row.get("hp", 60)) * lvl_scale))
	var ranged := _is_ranged(row)
	var rec := {
		"id": _next_id,
		"face": str(row.get("face", "")),
		"name": str(row.get("name", "")),
		"pos": pos,
		"hp": mon_hp,
		"max_hp": mon_hp,
		"speed": rng.randf_range(46.0, 68.0) + float(act_id) * 4.0,
		"dmg_min": int(round(float(row.get("dmgMin", 5)) * lvl_scale)),
		"dmg_max": int(round(float(row.get("dmgMax", 9)) * lvl_scale)),
		"atk_cd": float(row.get("attackSpeed", 1500)) / 1000.0,
		"atk_ready": 0.0,
		"hit_flash": 0.0,
		"bob": rng.randf() * TAU,
		# A thrower's DISTANCE is part of its record, not a global: the fight has to be able
		# to give two kinds different stand-off ranges without a second table.
		"ranged": ranged,
		"keep_range": KEEP_RANGE,
		"orb_colour": str(row.get("orbColor", ORB_COLOUR)),
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
		m["bob"] = float(m["bob"]) + dt * 7.0
		var to_hero: Vector2 = player_pos - (m["pos"] as Vector2)
		var gap := to_hero.length()
		var dir := to_hero / gap if gap > 0.001 else Vector2.RIGHT
		var ranged := bool(m["ranged"])
		# A thrower stops OUT OF REACH and shoots; a melee kind stops when the two discs touch.
		var stop_at := float(m["keep_range"]) if ranged else BODY_RADIUS * 2.0
		if gap > stop_at:
			var step_len := minf(float(m["speed"]) * dt, gap - stop_at)
			m["pos"] = _clamp_world((m["pos"] as Vector2) + dir * step_len)
		elif ranged and gap < RETREAT_RANGE:
			# Backing off is SLOWER than walking in, and it can be cornered: the arena's
			# edge wins over the caster's comfort.
			var back := minf(float(m["speed"]) * 0.8 * dt, RETREAT_RANGE - gap)
			m["pos"] = _clamp_world((m["pos"] as Vector2) - dir * back)

		# The gap AFTER the move: the attack must be judged on where the bodies really are,
		# or a caster fires from a distance it has already left.
		var after: float = player_pos.distance_to(m["pos"] as Vector2)
		m["atk_ready"] = maxf(0.0, float(m["atk_ready"]) - dt)
		if float(m["atk_ready"]) <= 0.0:
			if ranged:
				if after <= SHOOT_RANGE:
					m["atk_ready"] = float(m["atk_cd"])
					_shoot(m, player_pos - (m["pos"] as Vector2))
			elif after <= stop_at + 1.0:
				# Contact damage. The cooldown is the KIND's own attack speed, so a Bear hits
				# like a bear and a Wolf like a wolf with no extra code.
				m["atk_ready"] = float(m["atk_cd"])
				_take_damage(rng.randi_range(int(m["dmg_min"]), maxi(int(m["dmg_max"]), int(m["dmg_min"]))))
		alive.append(m)
	monsters = alive
	_resolve_bodies()


## The WALL of the area. It is the same inset the decoration stands on, so the rocks the player
## runs into are the line the rules stop him at — a boundary drawn anywhere else is a lie.
func _clamp_world(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, AREA_MARGIN + MON_RADIUS, WORLD.x - AREA_MARGIN - MON_RADIUS),
		clampf(pos.y, AREA_MARGIN + MON_RADIUS, WORLD.y - AREA_MARGIN - MON_RADIUS))


## One orb, aimed at where the hero IS at the moment of the throw. It is NOT homing: that is
## what makes the distance a skill instead of a formality — stepping out of the line is the
## answer, and a hero who only walks straight in eats every ball.
func _shoot(m: Dictionary, toward: Vector2) -> void:
	var dir := toward.normalized() if toward.length() > 0.001 else Vector2.RIGHT
	var dmg := rng.randi_range(int(m["dmg_min"]), maxi(int(m["dmg_max"]), int(m["dmg_min"])))
	projectiles.append({
		"pos": (m["pos"] as Vector2) + dir * (BODY_RADIUS + 6.0),
		"vel": dir * PROJECTILE_SPEED,
		"dmg": dmg,
		"age": 0.0,
		"colour": str(m["orb_colour"]),
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
				m["pos"] = player_pos + off / dist * min_gap


## A body pushed by its neighbour may not be pushed INTO the hero.
func _keep_off_hero(pos: Vector2, min_gap: float) -> Vector2:
	var off: Vector2 = pos - player_pos
	var dist := off.length()
	if dist >= min_gap or dist <= 0.001:
		return pos
	return player_pos + off / dist * min_gap


func _hero_is_free(min_gap: float) -> bool:
	for m in monsters:
		if (m["pos"] as Vector2).distance_to(player_pos) < min_gap - 0.001:
			return false
	return true


func _take_damage(raw: int) -> void:
	# The hero's own defence is the only mitigation in the slice; gear therefore already
	# matters, which is the point of keeping the loot loop attached from day one.
	var taken := maxi(1, raw - int(float(defense) * 0.35))
	hp -= taken
	_add_number(player_pos + Vector2(0, -34), "-%d" % taken, "hurt")
	events.append("hurt")
	if hp <= 0:
		hp = 0
		finished = true
		outcome = "dead"
		events.append("dead")


# ============================================================================ attack

## The auto-attack picks, PER HAND, the NEAREST monster whose BODY reaches inside that hand's
## drawn reach and nothing else. No cone, no aiming, no target assist: in a survivor fight the
## player steers the hero, and each hand spends what its own timer gives it.
##
## Everything a swing lands on is a real roll from the weapon that hand holds through
## `Progression`, so the loot loop stays honest and a fast 1H is not the same weapon as a slow
## 2H. The two hands are INDEPENDENT: a 700 ms scimitar in the off hand swings on its own clock
## while a 1580 ms axe keeps its own pace in the main hand.
func _auto_attack(dt: float) -> void:
	_main_clock = maxf(0.0, _main_clock - dt)
	if off_swing > 0.0:
		_off_clock = maxf(0.0, _off_clock - dt)
	if monsters.is_empty():
		return
	if _main_clock <= 0.0:
		var idx := _nearest_in_reach(reach_main, -1)
		if idx >= 0:
			_main_clock = main_swing
			var hit_id := int(monsters[idx]["id"])
			_swing_hand(idx, false)
			# The off hand AIMS SOMEWHERE ELSE when there is something else: two arcs on one
			# portrait read as one weapon swinging twice, which is the exact thing the second
			# weapon must not look like.
			_off_prefer_id = hit_id
	if off_swing > 0.0 and _off_clock <= 0.0:
		var idx_off := _nearest_in_reach(reach_off, _off_prefer_id)
		if idx_off < 0:
			idx_off = _nearest_in_reach(reach_off, -1)
		if idx_off >= 0:
			_off_clock = off_swing
			_swing_hand(idx_off, true)


## The nearest body whose rim crosses `reach`'s circle, skipping one id (so the two hands do not
## both land on the same portrait). `-1` skips nothing.
func _nearest_in_reach(reach: float, exclude_id: int) -> int:
	var limit := reach + MON_RADIUS
	var best := limit * limit
	var found := -1
	for i in monsters.size():
		if exclude_id >= 0 and int(monsters[i]["id"]) == exclude_id:
			continue
		var d2: float = (monsters[i]["pos"] as Vector2).distance_squared_to(player_pos)
		if d2 <= best:
			best = d2
			found = i
	return found


## One hand's landing blow. `index` is valid at call time; a kill removes the monster and no
## later hand may use that index.
func _swing_hand(index: int, is_off: bool) -> void:
	var m: Dictionary = monsters[index]
	var lo := dmg_off_min if is_off else dmg_min
	var hi := dmg_off_max if is_off else dmg_max
	var hand_crit := crit_off if is_off else crit_chance
	var dmg := rng.randi_range(lo, maxi(hi, lo))
	var crit := hand_crit > 0.0 and rng.randf() * 100.0 < hand_crit
	if crit:
		dmg = int(round(float(dmg) * 2.0))
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


func _kill(index: int) -> void:
	var m: Dictionary = monsters[index]
	kills += 1
	events.append("kill")
	_roll_drop(m["pos"] as Vector2)
	monsters.remove_at(index)


# ============================================================================ loot

## The drop table is the PWA's own, unchanged: `LootSystem.roll()` decides gold vs an item
## vs a special, so the survivor loop and the duel pay out through the same code.
func _roll_drop(pos: Vector2) -> void:
	var hero: Dictionary = _state.hero()
	var level := int(hero.get("level", 1))
	var magic_find := int(Progression._equip_attr(_state.equip(), _find_item, "magicFind"))
	var gold_find := int(Progression._equip_attr(_state.equip(), _find_item, "goldFind"))
	var result: Dictionary = _loot.roll(_state, act_id, wave, false, level, magic_find, gold_find, rng)
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


func drain_events() -> Array:
	var out := events.duplicate()
	events.clear()
	return out
