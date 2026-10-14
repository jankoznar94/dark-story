class_name Game
extends RefCounted

# CELA HRA. Zadny uzel, zadny Input, zadne _draw — proto ji jde hrat a merit
# headless (`tools/test_core.gd`) a proto se da overit, ze se chova stejne
# na kazde obrazovce.
#
# MODEL (rozhodnuty s Janem, Oct 2026):
#   * jedna vez ve stredu KRUHOVE plochy, kolem prazdno,
#   * vez vidi jen svoji barvu (na ostatni dava nulu a nestrili na ne),
#   * svazek drzi jeden cil, dokud neumre,
#   * poutnici vstupuji na okraji plochy NASLEPO a jdou rovne k vezi,
#   * cesta od okraje k vezi trva TRAVEL_S sekund,
#   * levely vypadaji vsechny stejne — lisi se jen slozenim vln.

const TRAVEL_S := 8.0
const BASE_HP := 40.0
const HP_GROWTH := 0.12
const REWARD := 12
const START_GOLD := 100
const START_LIVES := 12
const BUILD_TIME := 5.0
const WAVE_MAX := 10
const WAVE_SIZES := [4, 5, 6, 7, 8, 9, 10, 11, 12, 14]
const SPAWN_GAP := 2.4
const WAVE_BONUS := 30
const WAVE_BONUS_PER_WAVE := 10

# VENEC BAREV KOLEM VEZE. Klepnuti na vysek prepne barvu jednim klepnutim;
# cisla jsou nasobky polomeru veze a pouziva je HRA (dotyk) i KRESLENI, aby
# se klikaci plocha nemohla rozejit s tim, co hrac vidi.
const NOTCH_IN := 1.15
const NOTCH_OUT := 1.95

# ROZVRZENI PLOCHY jde do hry jednim mistem (`set_field`). Rychlost poutnika
# je z nej ODVOZENA (`field_r / TRAVEL_S`), takze "cesta trva 8 s" plati na
# telefonu i na velkem displeji. Pevne pixely za sekundu by na male obrazovce
# znamenaly kratsi dobu v ohne — a tim jinou hru.
var field_r: float = 300.0
var tower_r: float = 30.0
var center: Vector2 = Vector2.ZERO

var tower: Tower = Tower.new()
var pilgrims: Array = []
var locks: Array = []
var phase: String = "build"
var wave: int = 1
var lives: int = START_LIVES
var gold: int = START_GOLD
var build_left: float = BUILD_TIME
var spawn_left: float = 0.0
var plan: Array = []
var spawned: int = 0
var log: Array = []
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 20261014


func set_field(r: float, t: float, c: Vector2) -> void:
	field_r = maxf(r, 1.0)
	tower_r = maxf(t, 1.0)
	center = c


# RYCHLOST JE ODVOZENA Z ROZVRZENI, ne z pevnych pixelu: cestu od okraje
# k okraji veze (tam uz poutnik stoji zivot) musi vzdy ujit presne za
# TRAVEL_S sekund. Kdyby se pocitala z celeho polomeru, prisel by k vezi
# drive, protoze se zastavuje na jejim obvodu, ne ve stredu.
func pilgrim_speed() -> float:
	return maxf(0.001, (field_r - tower_r) / TRAVEL_S)


func is_over() -> bool:
	return phase == "won" or phase == "lost"


# ---------------------------------------------------------------- KROK HRY

func step(dt: float) -> void:
	if is_over():
		return
	_phase_step(dt)
	_move(dt)
	_beam(dt)
	_prune()


func _phase_step(dt: float) -> void:
	if phase == "build":
		build_left -= dt
		if build_left <= 0.0:
			_start_wave()
		return
	if phase != "wave":
		return
	if spawned < plan.size():
		spawn_left -= dt
		if spawn_left <= 0.0:
			_spawn_next()
			spawn_left = SPAWN_GAP
	elif pilgrims.is_empty():
		gold += WAVE_BONUS + WAVE_BONUS_PER_WAVE * wave
		if wave >= WAVE_MAX:
			phase = "won"
			_note("Vyhráno — všech %d vln odraženo." % WAVE_MAX)
		else:
			_note("Vlna %d odražena." % wave)
			wave += 1
			phase = "build"
			build_left = BUILD_TIME


func _start_wave() -> void:
	plan = wave_plan(wave)
	spawned = 0
	spawn_left = 0.0
	phase = "wave"
	_note("Vlna %d — %d poutníků." % [wave, plan.size()])


# SLOZENI VLNY JE MIX BAREV. Kazda vlna posle VSECHNY ctyri barvy: kdyby
# chodila jedna barva, hrac prepne jednou a zírá. Poradi je nahodne, pocet
# dany — hrac vi, KOLIK jich prijde, ale ne v jakem poradi a odkud.
func wave_plan(n: int) -> Array:
	var total: int = int(WAVE_SIZES[clampi(n - 1, 0, WAVE_SIZES.size() - 1)])
	var out: Array = []
	for i in range(total):
		out.append(i % Element.COUNT)
	# Fisher-Yates vlastnim rng, aby hra zustala deterministicka
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Variant = out[i]
		out[i] = out[j]
		out[j] = t
	return out


func hp_for(n: int) -> float:
	return BASE_HP * pow(1.0 + HP_GROWTH, float(n - 1))


# VSTUP POUTNIKA. Pouziva to hra i testy: `a` je uhel na okraji plochy,
# `el` barva (-1 = losovat).
func spawn_at_angle(a: float, el: int = -1) -> Pilgrim:
	var p := Pilgrim.new()
	p.element = el if Element.is_valid(el) else rng.randi_range(0, Element.COUNT - 1)
	p.pos = center + Vector2(cos(a), sin(a)) * field_r
	p.dir = (center - p.pos).normalized()
	p.max_hp = hp_for(wave)
	p.hp = p.max_hp
	p.speed = pilgrim_speed()
	pilgrims.append(p)
	return p


func _spawn_next() -> void:
	spawn_at_angle(rng.randf() * TAU, int(plan[clampi(spawned, 0, plan.size() - 1)]))
	spawned += 1


func _move(dt: float) -> void:
	for p in pilgrims:
		if not p.alive:
			continue
		p.pos += p.dir * p.speed * dt
		if p.pos.distance_to(center) <= tower_r:
			p.alive = false
			lives -= 1
			_note("%s došel k věži." % Element.name_of(p.element))
			if lives <= 0:
				lives = 0
				phase = "lost"
				_note("Konec — srdce podlehlo.")


func in_range(p: Pilgrim, r: float) -> bool:
	return p.pos.distance_to(center) <= r


# SVAZEK. Drzi cil, dokud neumre — a zámek se uvolni jen tehdy, kdyz je cil
# mrtvy, mimo dostrel, nebo kdyz hrac prepnul barvu (pak uz ho vez nevidi).
# Poskozeni jde KAZDY SNIMEK: zadny skryty cooldown, zadny prebytek rany.
func _beam(dt: float) -> void:
	var r: float = tower.range_px(field_r)
	var keep: Array = []
	for p in locks:
		if tower.sees(p) and in_range(p, r):
			keep.append(p)
	locks = keep
	if locks.size() < tower.targets():
		var pool: Array = []
		for p in pilgrims:
			if tower.sees(p) and in_range(p, r) and not locks.has(p):
				pool.append(p)
		pool.sort_custom(_closer)
		while locks.size() < tower.targets() and not pool.is_empty():
			locks.append(pool.pop_front())
	for p in locks:
		p.hp -= tower.dps() * dt
		if p.hp <= 0.0:
			p.alive = false
			gold += REWARD


func _closer(a: Pilgrim, b: Pilgrim) -> bool:
	return a.pos.distance_squared_to(center) < b.pos.distance_squared_to(center)


func _prune() -> void:
	var keep: Array = []
	for p in pilgrims:
		if p.alive:
			keep.append(p)
	pilgrims = keep


# ------------------------------------------------------------------ VSTUP

# KLEPNUTI NA VEZ. Presny vysek vence prepne barvu jednim klepnutim (pod
# casovym tlakem je kolecko kolem dokola pozde); klepnuti primo na telo veze
# otoci barvu na dalsi, aby klepnuti "na vez" nikdy neskoncilo bez odpovedi.
func tap_at(pos: Vector2) -> void:
	var d: float = pos.distance_to(center)
	if d <= tower_r:
		tower.set_element((tower.element + 1) % Element.COUNT)
		return
	var i: int = notch_of(pos)
	if i >= 0:
		tower.set_element(i)


func notch_of(pos: Vector2) -> int:
	var d: float = pos.distance_to(center)
	if d < tower_r * NOTCH_IN or d > tower_r * NOTCH_OUT:
		return -1
	var a: float = (pos - center).angle() + PI
	var i: int = int(a / (TAU / float(Element.COUNT)))
	return clampi(i, 0, Element.COUNT - 1)


func buy_upgrade() -> bool:
	if not tower.can_upgrade() or gold < tower.upgrade_cost():
		return false
	gold -= tower.upgrade_cost()
	tower.upgrade()
	_note("Věž na %d. stupni (dostřel %d %%, %d cíl)."
		% [tower.level, int(round(tower.range_frac() * 100.0)), tower.targets()])
	return true


# ------------------------------------------------------------------ HLASKY

func _note(s: String) -> void:
	log.append(s)
	if log.size() > 40:
		log.pop_front()


func last_note() -> String:
	if log.is_empty():
		return ""
	return String(log[log.size() - 1])
