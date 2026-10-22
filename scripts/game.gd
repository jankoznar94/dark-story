class_name Game
extends RefCounted

# THROWER - CELA HERNI LOGIKA. Bez uzlu, bez kresleni, bez vstupu: diky tomu
# je hra deterministicka a da se ridit testy headless.
#
# PRINCIP (Jan, Oct 2026): "věž střílela automaticky projektily opačným směrem,
# než kterým hráč ukazuje prstem ... Hráč položí prst na displej a bojovník
# střílí přesně opačným směrem. Jak když napínám prstem luk a opačný směr je
# směr šípů." Barvy NEEXISTUJI: cilem je ten, kdo stoji v draze oštěpu.

const WAVES_PER_LEVEL := 10
const BASE_HP := 12.0
# RUST OBTIZNOSTI: kazda vlna o 16 % vic zivotu. Kolo = vlna pres cely pruchod.
const HP_GROWTH := 1.16
# CESTA NEPRITELE od okraje do stredu. Je to cas, ne rychlost - na jinem
# displeji musi prijit za stejnou dobu.
const TRAVEL_S := 9.0
const SPAWN_GAP := 0.75
const BUILD_S := 3.0
const BODY_PER_WAVE := 1
const BODY_LEVEL_BASE := 6
const BODY_PER_LEVEL := 2
# ODRAZ: jak daleko muze byt dalsi cil a kolik si odnese.
const RICO_RANGE_FRAC := 0.55
const RICO_FALLOFF := 0.6
# ROZESTUP VIC OSTREPU (celkem, v radiánech).
const SPREAD := 0.10

var profile: Profile = Profile.new()
var field_r: float = 300.0
var center: Vector2 = Vector2(500.0, 500.0)
var level: int = 1
var wave: int = 1
var phase: String = "build"
var build_left: float = BUILD_S
var hp: float = 100.0
var max_hp: float = 100.0
var gold: int = 0          # nepouziva se, zustava kvuli kompatibilite UI
var body_earned: int = 0
var enemies: Array = []
var spears: Array = []
var aiming: bool = false
var aim: Vector2 = Vector2.RIGHT
var fire_left: float = 0.0
var spawn_left: float = 0.0
var spawned: int = 0
var plan: int = 0
var clock: float = 0.0
var paused: bool = false
var log: Array = []
var hits: int = 0
var kills: int = 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 20261022


func set_field(r: float, c: Vector2) -> void:
	field_r = maxf(40.0, r)
	center = c


# ------------------------------------------------------------------ PARAMETRY

func val(id: String) -> float:
	return Upgrades.value_of(id, profile.perm_level(id))


func fire_interval() -> float:
	return maxf(0.12, val("rate"))


func shots() -> int:
	return maxi(1, int(round(val("shots"))))


func ricochet() -> int:
	return maxi(0, int(round(val("ric"))))


func spear_speed() -> float:
	return field_r * maxf(0.2, val("spd"))


func damage() -> float:
	return maxf(1.0, val("dmg"))


func regen() -> float:
	return maxf(0.0, val("rg"))


# ---------------------------------------------------------------- ROZMERY
# Jednotky se pocitaji z polomeru plochy, ne z pixelu: na kazdem displeji musi
# bojovnik i nepratele zabirat stejny podil plochy.

func warrior_r() -> float:
	return field_r * 0.055


func enemy_r() -> float:
	return field_r * 0.030


func spear_r() -> float:
	return field_r * 0.010


func enemy_hp(w: int) -> float:
	var kolo: int = (level - 1) * WAVES_PER_LEVEL + w
	return BASE_HP * pow(HP_GROWTH, float(maxi(0, kolo - 1)))


func enemy_dmg(w: int) -> float:
	var kolo: int = (level - 1) * WAVES_PER_LEVEL + w
	return 5.0 + 0.7 * float(kolo)


func wave_size(w: int) -> int:
	return 4 + 2 * w


# ------------------------------------------------------------------ ZIVOT HRY

func start_level(n: int) -> void:
	level = maxi(1, n)
	wave = 1
	phase = "build"
	build_left = BUILD_S
	body_earned = 0
	enemies = []
	spears = []
	aiming = false
	fire_left = 0.0
	spawned = 0
	spawn_left = 0.0
	plan = 0
	hits = 0
	kills = 0
	max_hp = val("hp")
	hp = max_hp
	_note("Level %d — %d vln." % [level, WAVES_PER_LEVEL])


func next_level() -> void:
	if phase == "won":
		start_level(level + 1)


func is_over() -> bool:
	return phase == "won" or phase == "lost"


func _lose() -> void:
	phase = "lost"
	hp = 0.0
	_note("Konec — bojovník padl na levelu %d." % level)


func _level_won() -> void:
	phase = "won"
	var first: bool = level > profile.best
	if first:
		var bonus: int = BODY_LEVEL_BASE + BODY_PER_LEVEL * level
		body_earned += bonus
		profile.add_body(bonus)
	profile.clear_level(level)


# ------------------------------------------------------------------ VSTUP

# PRST NA DISPLEJI = NAPNUTY LUK. Smer strelby je PRESNE OPAČNY nez smer
# k prstu, proto `center - pos` (a ne `pos - center`).
func aim_at(pos: Vector2) -> void:
	var d: Vector2 = center - pos
	if d.length() <= 0.001:
		aiming = true
		return
	aim = d.normalized()
	aiming = true


func release() -> void:
	aiming = false


# ------------------------------------------------------------------ KROK

func step(dt: float) -> void:
	if is_over() or paused:
		return
	clock += dt
	_regen(dt)
	_phase(dt)
	_fire(dt)
	_move_enemies(dt)
	_move_spears(dt)
	_prune()
	if hp <= 0.0:
		_lose()


func _regen(dt: float) -> void:
	if regen() <= 0.0 or hp <= 0.0:
		return
	hp = minf(max_hp, hp + regen() * dt)


func _phase(dt: float) -> void:
	if phase == "build":
		build_left -= dt
		if build_left <= 0.0:
			_start_wave()
		return
	if phase != "wave":
		return
	if spawned < plan:
		spawn_left -= dt
		if spawn_left <= 0.0:
			_spawn()
			spawn_left = SPAWN_GAP
	# VLNA KONCI AZ KDYBY NA PLOSE NIKDO NEZBYL - jinak by dalsi vlna zacala
	# driv, nez hrac dodela tu predchozi.
	if spawned >= plan and enemies.is_empty():
		_next_wave()


func _start_wave() -> void:
	phase = "wave"
	plan = wave_size(wave)
	spawned = 0
	spawn_left = 0.0
	_note("Vlna %d — %d nepřátel." % [wave, plan])


func _next_wave() -> void:
	# KAZDA ODRAZENA VLNA PLATI BODY: hracovi se nikdy nesmi stat, ze hraje
	# deset minut a nema na zadny upgrade.
	profile.add_body(BODY_PER_WAVE)
	body_earned += BODY_PER_WAVE
	wave += 1
	if wave > WAVES_PER_LEVEL:
		_level_won()
		return
	phase = "build"
	build_left = BUILD_S


func _spawn() -> void:
	var a: float = rng.randf_range(0.0, TAU)
	var p := {
		"pos": center + Vector2(cos(a), sin(a)) * field_r * 1.05,
		"hp": enemy_hp(wave), "max_hp": enemy_hp(wave),
		"speed": field_r / TRAVEL_S, "dmg": enemy_dmg(wave),
		"alive": true,
	}
	enemies.append(p)
	spawned += 1


# HAZENI. Dokud hrac drzi prst, bojovnik haze v pravidelnych odstupech;
# `fire_left` je odpočet do dalsiho hodu (ne "kadence", ktera by se dala
# preskocit mackanim).
func _fire(dt: float) -> void:
	fire_left = maxf(0.0, fire_left - dt)
	if not aiming or fire_left > 0.0:
		return
	fire_left = fire_interval()
	var n: int = shots()
	var step: float = 0.0
	if n > 1:
		step = SPREAD / float(n - 1)
	for i in range(n):
		var a: float = aim.angle() - SPREAD * 0.5 + step * float(i)
		spears.append({
			"pos": center + Vector2(cos(a), sin(a)) * (warrior_r() + spear_r()),
			"dir": Vector2(cos(a), sin(a)),
			"dmg": damage(), "ric": ricochet(), "hit": [],
		})


func _move_enemies(dt: float) -> void:
	for e in enemies:
		if not bool(e["alive"]):
			continue
		var pos: Vector2 = e["pos"]
		var d: Vector2 = center - pos
		var dd: float = d.length()
		if dd <= warrior_r() + enemy_r():
			# DORAZIL: ubere zivoty a zmizi. Zbroj ani barvy tu nejsou - jedina
			# obrana je zabit ho driv.
			hp -= float(e["dmg"])
			e["alive"] = false
			continue
		e["pos"] = pos + d / dd * float(e["speed"]) * dt


func _move_spears(dt: float) -> void:
	for s in spears:
		if not bool(s.get("alive", true)):
			continue
		var pos: Vector2 = s["pos"] + (s["dir"] as Vector2) * spear_speed() * dt
		s["pos"] = pos
		if pos.distance_to(center) > field_r * 1.25:
			s["alive"] = false
			continue
		var hit: Dictionary = _first_hit(pos, s["hit"])
		if hit.is_empty():
			continue
		hits += 1
		# KAZDY NEPRITEL DOSTANE OD JEDNOHO OSTEPU JEN JEDNU RANU. Bez toho by
		# se odraz vracel na stejny cil, ktery stoji na miste, kde ostep
		# zrovna je - a "odraz" by byl jen dalsi zasah do téhož.
		(s["hit"] as Array).append(hit)
		_hurt(hit, float(s["dmg"]))
		# ODRAZ: preskoci na nejblizsiho dalsiho ziveho nepritele a odnese si
		# jen cast poskozeni. Kazdy cil muze dostat jen jednu ranu.
		if int(s["ric"]) > 0:
			var nxt: Dictionary = _nearest(hit, RICO_RANGE_FRAC * field_r, s["hit"])
			if not nxt.is_empty():
				s["dir"] = ((nxt["pos"] as Vector2) - (hit["pos"] as Vector2)).normalized()
				s["pos"] = hit["pos"]
				s["dmg"] = float(s["dmg"]) * RICO_FALLOFF
				s["ric"] = int(s["ric"]) - 1
				continue
		s["alive"] = false


func _first_hit(pos: Vector2, skip: Array = []) -> Dictionary:
	for e in enemies:
		if not bool(e["alive"]) or skip.has(e):
			continue
		if (e["pos"] as Vector2).distance_to(pos) <= enemy_r() + spear_r():
			return e
	return {}


func _nearest(from: Dictionary, reach: float, skip: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = reach
	for e in enemies:
		if not bool(e["alive"]) or e == from or skip.has(e):
			continue
		var d: float = (e["pos"] as Vector2).distance_to(from["pos"])
		if d <= best_d:
			best_d = d
			best = e
	return best


func _hurt(e: Dictionary, amount: float) -> void:
	e["hp"] = float(e["hp"]) - amount
	if float(e["hp"]) <= 0.0:
		e["alive"] = false
		kills += 1


func _prune() -> void:
	var keep_e: Array = []
	for e in enemies:
		if bool(e["alive"]):
			keep_e.append(e)
	enemies = keep_e
	var keep_s: Array = []
	for s in spears:
		if bool(s.get("alive", true)):
			keep_s.append(s)
	spears = keep_s


# ------------------------------------------------------------------ HLASKY

func _note(s: String) -> void:
	log.append(s)
	if log.size() > 30:
		log.pop_front()


func last_note() -> String:
	if log.is_empty():
		return ""
	return String(log[log.size() - 1])
