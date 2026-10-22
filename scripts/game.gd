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
const TRAVEL_S := 20.0
# ZACATEK JE POMALEJSI A ZRYCHLUJE S LEVELY (Jan, Oct 2026: "Nepřátelé budou
# chodit ze začátku pomaleji", pak "stále chodí příliš rychle"): na prvnim
# levelu jdou 20 s, kazdy dalsi o 1 s min, ale nikdy pod 12 s.
const TRAVEL_MIN := 12.0
const TRAVEL_STEP := 1.0
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
# HERNI PLOCHA nad bojovnikem (bez horniho pruhu). Nepratele se rodi u horniho
# okraje a jdou dolu na bojovnika; ostepy leti opacne a mimo plochu zanikaji.
var arena: Rect2 = Rect2()
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
var aim: Vector2 = Vector2.UP
var fire_left: float = 0.0
var spawn_left: float = 0.0
var spawned: int = 0
var plan: int = 0
var clock: float = 0.0
var paused: bool = false
# ZASAH: jak dlouho (s) blika bojovnik po zasahu a kolik mu to ubralo. Obrazovka
# z toho kresli cerveny obrys a "-X" nad hlavou - hrac musi VIDET, ze dostal
# rano, ne jen ze mu nekde ubylo cislo.
var hit_flash: float = 0.0
var hit_amount: float = 0.0
var log: Array = []
var hits: int = 0
var kills: int = 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 20261022


func set_field(r: float, c: Vector2, a: Rect2 = Rect2()) -> void:
	field_r = maxf(40.0, r)
	center = c
	if a.size.x > 0.0 and a.size.y > 0.0:
		arena = a
	else:
		arena = Rect2(c.x - r * 2.0, c.y - r * 2.2, r * 4.0, r * 2.2)


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
	# BARBAR JE VELKY (Jan, Oct 2026: "Barbar musí být větší") - je to hlavni
	# objekt na obrazovce a musi byt videt, kam se otoci.
	return field_r * 0.085


func travel_time() -> float:
	return clampf(TRAVEL_S - float(level - 1) * TRAVEL_STEP, TRAVEL_MIN, TRAVEL_S)


func enemy_r() -> float:
	# NEPRATELE JSOU VELCI (Jan, Oct 2026: "nepřátelé musí být podstatně větší,
	# aby bylo snadnější je trefit"). Sirka displeje, ne vyska - na vysku by
	# byli na dlouhem telefonu mensi nez na sirokem.
	return field_r * 0.065


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

# MIREni PRIMO PRSTEM PRED BOJOVNIKEM: smer je presne ten, kterym prst lezi
# od barbara (Jan, Oct 2026: "bude střílet tam, kam ukazuje prst. Přímo").
# Uhel se orizne na 180° dopredu, takze se nikdy neotoci zpet k sobe.
func aim_at(pos: Vector2) -> void:
	var d: Vector2 = pos - center
	if d.length() <= 0.001:
		aiming = true
		return
	var rel: float = wrapf(d.angle() + PI * 0.5, -PI, PI)
	rel = clampf(rel, -PI * 0.5, PI * 0.5)
	aim = Vector2.from_angle(-PI * 0.5 + rel)
	aiming = true


func release() -> void:
	aiming = false


# ------------------------------------------------------------------ KROK

func step(dt: float) -> void:
	if is_over() or paused:
		return
	clock += dt
	hit_flash = maxf(0.0, hit_flash - dt)
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
	# NEPRATELE JDOU SHORA: rodi se u horniho okraje plochy, ne kolem dokola.
	# Sireni po cele sirce, aby se hrac nemohl jen schovat do jednoho rohu.
	var span: float = minf(arena.size.x * 0.42, field_r * 0.95)
	var x: float = center.x + rng.randf_range(-span, span)
	var p0 := Vector2(clampf(x, 8.0, arena.end.x - 8.0), arena.position.y + field_r * 0.06)
	var dist: float = p0.distance_to(center)
	var p := {
		"pos": p0,
		"hp": enemy_hp(wave), "max_hp": enemy_hp(wave),
		"speed": dist / travel_time(), "dmg": enemy_dmg(wave),
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
		# JEDEN OSTEP LETI PRESNE TAM, KAM HRAC MIRI. Rozestup se pridava jen
		# u vicenasobne strelby - jinak by se jednoducha rana vzdy ukradla
		# o pulku rozestupu do strany.
		var a: float = aim.angle()
		if n > 1:
			a += -SPREAD * 0.5 + step * float(i)
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
			hit_amount = float(e["dmg"])
			hit_flash = 0.45
			e["alive"] = false
			continue
		e["pos"] = pos + d / dd * float(e["speed"]) * dt


func _move_spears(dt: float) -> void:
	for s in spears:
		if not bool(s.get("alive", true)):
			continue
		var pos: Vector2 = s["pos"] + (s["dir"] as Vector2) * spear_speed() * dt
		s["pos"] = pos
		# OSTEP ZANIKA, KDYZ VYJDE Z PLOCHY. Plati pro kazdou strelu, i pro
		# odrazenou - jinak by "odraz" do strany litel donekonecna. Plocha je
		# o kousek vetsi nez obrazovka, aby ostep do strany doletel az za okraj.
		if not arena.grow(field_r * 0.15).has_point(pos):
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
