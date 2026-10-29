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
const HERO_SPEED := 168.0
## The bodies are the PORTRAIT DISCS, so the collision radius is the disc's own radius. One
## number for both sides: a melee reach that is bigger than the gap between two bodies is a
## reach that hits from another postcode.
const BODY_RADIUS := 31.0
const HERO_RADIUS := BODY_RADIUS
const MON_RADIUS := BODY_RADIUS

## --- the fight ------------------------------------------------------------
## ONE range and ONE cadence for the auto-attack: a survivor hero must never have to
## aim, and a swing timer the player cannot see must not vary per monster type.
## Reach is CONTACT plus ~14 px. With two 31 px discs, touching is 62 px, so the hero has to be
## pressed against a body to swing — the "logicky musí být blízko" Jan asked for.
const ATTACK_RANGE := 76.0
const ATTACK_COOLDOWN := 0.85
const CONTACT_PAD := 3.0

## --- spawning -------------------------------------------------------------
## The density is the design dial. The Dark Story pacing rule banned hordes; the survivor
## loop needs a CROWD, so the number lives here, named, and the slice stays at 16 alive.
## Was 16 on the first pass and Jan's report was "there are too many enemies". Seven is a pack
## you can read and back away from; the arena's own pacing lesson is that a crowd on a phone
## screen is not difficulty, it is noise.
const MAX_ALIVE := 7
const WAVE_SECONDS := 26.0
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
var dmg_min := 1
var dmg_max := 2
var crit_chance := 0.0

var monsters: Array = []
var drops: Array = []
var numbers: Array = []
## Sound cues, drained by the screen every frame (battle.gd does the same with its log).
var events: Array = []

var kills := 0
var wave := 1
var elapsed := 0.0
var gold := 0
var items_taken := 0
## How long ago the last swing LANDED, in seconds (-1 = no swing yet). The renderer turns this
## into the lunge and the slash — the RULES never animate, they only say when and which way.
var swing_age := -1.0
var swing_dir := Vector2.RIGHT

var finished := false
## "" | "dead"
var outcome := ""

var _wave_clock := 0.0
var _spawn_accum := 0.0
var _attack_clock := 0.0
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
	var weapon: Dictionary = find_item.call(state.equip().get("weapon", "fists"))
	if weapon.is_empty():
		weapon = find_item.call("fists")
	crit_chance = float(weapon.get("critChance", 0))

	player_pos = WORLD * 0.5
	monsters.clear()
	drops.clear()
	numbers.clear()
	events.clear()
	kills = 0
	wave = 1
	elapsed = 0.0
	gold = 0
	items_taken = 0
	finished = false
	outcome = ""
	_wave_clock = 0.0
	_spawn_accum = 0.0
	_attack_clock = 0.0
	_next_id = 0
	swing_age = -1.0
	swing_dir = Vector2.RIGHT
	_spawn_wave(2)


# ============================================================================ step

func step(dt: float, move: Vector2) -> void:
	if finished:
		return
	elapsed += dt
	if swing_age >= 0.0:
		swing_age += dt
	_wave_clock += dt
	if _wave_clock >= WAVE_SECONDS:
		_wave_clock -= WAVE_SECONDS
		wave += 1

	_prev_pos = player_pos
	_move_hero(dt, move)
	_spawn_tick(dt)
	_move_monsters(dt)
	_auto_attack(dt)
	_move_drops(dt)
	_age_numbers(dt)


func _move_hero(dt: float, move: Vector2) -> void:
	var dir := move.limit_length(1.0)
	if dir.length_squared() <= 0.0001:
		return
	player_pos += dir * HERO_SPEED * dt
	player_pos.x = clampf(player_pos.x, HERO_RADIUS, WORLD.x - HERO_RADIUS)
	player_pos.y = clampf(player_pos.y, HERO_RADIUS, WORLD.y - HERO_RADIUS)


# ============================================================================ spawn

func _spawn_tick(dt: float) -> void:
	_spawn_accum += dt
	# The cadence tightens with the wave and stops at 0.55 s: a floor exists so the run
	# cannot turn into a wall of bodies that the 16-alive cap then starves anyway.
	var interval := maxf(1.10, 2.30 - float(wave - 1) * 0.12)
	if _spawn_accum < interval:
		return
	_spawn_accum -= interval
	if monsters.size() >= MAX_ALIVE:
		return
	_spawn_one()


func _spawn_wave(count: int) -> void:
	for _i in count:
		_spawn_one()


## Every monster is a WALKING PORTRAIT: the record is the data row's own `face`, so a new
## monster in MONSTER_DB needs no code. `minArea` is honoured — the act's low-tier kinds
## arrive first and the heavy ones only later in the run, which is what makes the waves
## read as escalating rather than random.
func _spawn_one() -> void:
	var db: Array = []
	if _data != null:
		db = _data.monsters_for_theme(act_id)
	if db.is_empty():
		return
	var tier := 1 + int(elapsed / 45.0)
	var pool: Array = []
	for row in db:
		if int(row.get("minArea", 0)) <= tier:
			pool.append(row)
	if pool.is_empty():
		pool = db
	var row: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]

	var ang := rng.randf() * TAU
	var dist := rng.randf_range(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
	var pos := player_pos + Vector2(cos(ang), sin(ang)) * dist
	pos.x = clampf(pos.x, MON_RADIUS, WORLD.x - MON_RADIUS)
	pos.y = clampf(pos.y, MON_RADIUS, WORLD.y - MON_RADIUS)

	# A kind's strength is the DB's own number, scaled by the act's difficulty so a run in
	# a later act is dangerous without a second table.
	var lvl_scale := 1.0 + float(act_id) * 0.35
	var mon_hp := int(round(float(row.get("hp", 60)) * lvl_scale))
	monsters.append({
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
	})
	_next_id += 1


# ============================================================================ monsters

func _move_monsters(dt: float) -> void:
	var alive: Array = []
	for m in monsters:
		m["hit_flash"] = maxf(0.0, float(m["hit_flash"]) - dt)
		m["bob"] = float(m["bob"]) + dt * 7.0
		var to_hero: Vector2 = player_pos - (m["pos"] as Vector2)
		var gap := to_hero.length()
		var stop_at := BODY_RADIUS * 2.0
		if gap > stop_at:
			var step_len := minf(float(m["speed"]) * dt, gap - stop_at)
			m["pos"] = (m["pos"] as Vector2) + to_hero.normalized() * step_len

		# Contact damage. The cooldown is the KIND's own attack speed, so a Bear hits like
		# a bear and a Wolf like a wolf with no extra code.
		m["atk_ready"] = maxf(0.0, float(m["atk_ready"]) - dt)
		if gap <= stop_at + 1.0 and float(m["atk_ready"]) <= 0.0:
			m["atk_ready"] = float(m["atk_cd"])
			_take_damage(rng.randi_range(int(m["dmg_min"]), maxi(int(m["dmg_max"]), int(m["dmg_min"]))))
		alive.append(m)
	monsters = alive
	_resolve_bodies()


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

## The auto-attack picks the NEAREST monster inside the range and nothing else. No cone,
## no aiming, no target assist: in a survivor fight the player steers the hero, and the
## hero spends what the timer gives him. Everything the swing lands on is a real roll
## from the equipped weapon through `Progression`, so the loot loop stays honest.
func _auto_attack(dt: float) -> void:
	_attack_clock = maxf(0.0, _attack_clock - dt)
	if _attack_clock > 0.0 or monsters.is_empty():
		return
	var nearest := -1
	var best := ATTACK_RANGE * ATTACK_RANGE
	for i in monsters.size():
		var d2: float = (monsters[i]["pos"] as Vector2).distance_squared_to(player_pos)
		if d2 <= best:
			best = d2
			nearest = i
	if nearest < 0:
		return
	_attack_clock = ATTACK_COOLDOWN
	var m: Dictionary = monsters[nearest]
	var dmg := rng.randi_range(dmg_min, maxi(dmg_max, dmg_min))
	var crit := crit_chance > 0.0 and rng.randf() * 100.0 < crit_chance
	if crit:
		dmg = int(round(float(dmg) * 2.0))
	m["hp"] = int(m["hp"]) - dmg
	m["hit_flash"] = 0.12
	var toward: Vector2 = (m["pos"] as Vector2) - player_pos
	swing_dir = toward.normalized() if toward.length() > 0.001 else Vector2.RIGHT
	swing_age = 0.0
	_add_number((m["pos"] as Vector2) + Vector2(0, -30), str(dmg), "crit" if crit else "hit")
	events.append("crit" if crit else "hit")
	if int(m["hp"]) <= 0:
		_kill(nearest)


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
