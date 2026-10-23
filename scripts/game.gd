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
# ROZESTUP VIC OSTREPU (celkem, v radiánech) pri zakladnim nastaveni.
const SPREAD := 0.10
# ROZPTYL JE OVLADATELNY (Jan, Oct 2026: "levá zóna bude ovládat rozptyl
# střel u multishotu"). Hrac nastavuje nasobek zakladniho rozestupu: 0 = co
# nejužší ("dopředu"), 1 = co nejširší ("dozadu").
const SPREAD_SCALE_MIN := 0.30
const SPREAD_SCALE_MAX := 3.60
# MINIMALNI POLOMER NEPRITELE v pixelech (prumer 25 px). Jan: "Nejmensi z nich
# musi mit minimalne prumer kruhu 25 px." Podil field_r na malem displeji pada
# pod to, takze se velikost dorovnava nahoru.
const MIN_ENEMY_R := 12.5

# HRADBA (Jan, Oct 2026): "Před Barbara postavíme hradbu. Nepřátelé budou ničit
# ji, místo Barbara. Nepřátelé tedy budou chodit striktně rovně. Žádné směřování
# do středu. Žádné kličkování."
#
# Hradba stoji vodorovne pres celou plochu kus nad Barbarem. Nepratel jde rovne
# dolu SVYM sloupcem (x se nikdy nemeni), zastavi se o hradbu a mlati do ni.
# Dokud stoji, jde vsechno poskozeni do ni; kdyz padne, jde to do Barbara.
# Hradba se stavi znovu na zacatku kazde vlny (proto existuje priprava).
const WALL_ABOVE := 0.45       # vyska hradby nad bojovnikem (podil field_r)
const WALL_HP_FRAC := 1.0      # kolik zivotu bojovnika hradba vydrzi
const WALL_ATTACK_CD := 1.0    # sekundy mezi ranami do hradby

# DRUHY NEPRATEL (Jan, Oct 2026: "Různé velikosti, různá rychlost, různá výdrž.
# Někteří budou střílet ... většina bude na blízko.")
#
#   r      - polomer v podilu field_r (velikost je videt na prvni pohled)
#   travel - nasobek doby chuze; <1 = rychlejsi, >1 = pomalejsi
#   hp     - nasobek zivotu vlny
#   dmg    - nasobek poskozeni pri dorazu
#   ranged - stoji v `stop` (podil field_r od stredu) a strili
#   shot_cd / shot_dmg / shot_spd - kadence, poskozeni a rychlost strel (podil field_r/s)
#
# Vetsina je na blizko; strelci jsou vzacni a stoji daleko, takze je hrac musi
# dobehnout ostepem, ne je nechat dojit.
const ENEMY_TYPES := [
	{"id": "cobra", "name": "Kobra", "img": "desert_cobra", "r": 0.065,
		"travel": 0.60, "hp": 0.55, "dmg": 0.55, "ranged": false},
	{"id": "nomad", "name": "Poutník", "img": "desert_nomad", "r": 0.072,
		"travel": 1.00, "hp": 1.00, "dmg": 1.00, "ranged": false},
	{"id": "treant", "name": "Stromák", "img": "ent", "r": 0.090,
		"travel": 1.35, "hp": 1.90, "dmg": 1.45, "ranged": false},
	{"id": "kolos", "name": "Kolos", "img": "desert_beetle", "r": 0.105,
		"travel": 1.70, "hp": 2.40, "dmg": 1.90, "ranged": false},
	{"id": "ghost", "name": "Přízrak", "img": "ghost", "r": 0.066,
		"travel": 1.15, "hp": 0.85, "dmg": 0.50, "ranged": true,
		"stop": 0.68, "shot_cd": 2.6, "shot_dmg": 0.55, "shot_spd": 0.50},
	{"id": "pyro", "name": "Ohnivec", "img": "fire_ghost", "r": 0.076,
		"travel": 1.30, "hp": 1.15, "dmg": 0.60, "ranged": true,
		"stop": 0.52, "shot_cd": 3.2, "shot_dmg": 0.90, "shot_spd": 0.60},
]

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
# STRELY NEPRATEL (strelci): leti od nepritele k bojovnikovi.
var enemy_shots: Array = []
var aiming: bool = false
var aim: Vector2 = Vector2.UP
# VSTUP ZE ZON: smer otaceni (-1 vlevo, +1 vpravo) a nasobek rozptylu.
# Obrazovka je jen nastavuje, otaceni se pocita tady v kroku - diky tomu je
# pohyb plynuly a nezavisly na poctu snimku.
var spread_scale: float = 1.0
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
# HRADBA: zivoty a bliknuti pri zasahu. Vyska se pocita z `center` a `field_r`
# (`wall_top()`), takze po zmene rozmeru nikdy nezustane na starem miste.
var wall_hp: float = 0.0
var wall_max_hp: float = 0.0
var wall_flash: float = 0.0
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


# VYSKA HRADBY: vodorovna cara, za kterou uz nepratele neprojdou. Pocita se
# z rozmeru, neuklada se - pri zmene displeje nemuze zustat na starem miste.
func wall_top() -> float:
	return center.y - field_r * WALL_ABOVE


func wall_max() -> float:
	return maxf(1.0, max_hp * WALL_HP_FRAC)


func wall_frac() -> float:
	return clampf(wall_hp / maxf(1.0, wall_max_hp), 0.0, 1.0)


func wall_alive() -> bool:
	return wall_hp > 0.0


# NOVA HRADBA. Stavi se na zacatku levelu a na zacatku kazde vlny.
func build_wall() -> void:
	wall_max_hp = wall_max()
	wall_hp = wall_max_hp
	wall_flash = 0.0


# RANA DO HRADBY. Dokud stoji, bere vsechno poskozeni ona; hracuv zivot se
# ani nehne, dokud nezustane 0.
func _damage_wall(amount: float) -> void:
	if wall_hp <= 0.0:
		return
	wall_hp = maxf(0.0, wall_hp - amount)
	wall_flash = 0.30
	if wall_hp <= 0.0:
		_note("Hradba padla.")


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


# VZHLED A VLASTNOSTI DRUHU. Hleda se podle id, aby se dala mit v jedne tabulce
# i logika i kresleni (obrazek).
static func enemy_type(id: String) -> Dictionary:
	for t in ENEMY_TYPES:
		if String(t["id"]) == id:
			return t
	return ENEMY_TYPES[1]


# POLOMER KONKRETNIHO NEPRITELE. Testy a starsi data nemaji "kind", takze padaji
# na zakladni velikost.
func radius_of(e: Dictionary) -> float:
	if e.has("r"):
		return maxf(MIN_ENEMY_R, float(e["r"]))
	return maxf(MIN_ENEMY_R, enemy_r())


# SLOZENI VLNY: do zacatku jen pesaci, od 3. vlny prvni strelci, od 5. vlny
# tezsi kusy. Vahy jsou nasobene, aby "vetsina na blizko" opravdu platilo.
func type_weights(w: int) -> Array:
	var out: Array = [["cobra", 2.2], ["nomad", 5.0]]
	if w >= 3:
		out.append(["ghost", 1.5])
	if w >= 4:
		out.append(["treant", 1.6])
	if w >= 6:
		out.append(["pyro", 1.3])
	if w >= 7:
		out.append(["kolos", 0.9])
	return out


func _pick_type(w: int) -> Dictionary:
	var list: Array = type_weights(w)
	var total: float = 0.0
	for it in list:
		total += float(it[1])
	var roll: float = rng.randf() * total
	for it in list:
		roll -= float(it[1])
		if roll <= 0.0:
			return enemy_type(String(it[0]))
	return enemy_type("nomad")


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
	enemy_shots = []
	aiming = false
	aim = Vector2.UP
	spread_scale = 1.0
	fire_left = 0.0
	spawned = 0
	spawn_left = 0.0
	plan = 0
	hits = 0
	kills = 0
	max_hp = val("hp")
	hp = max_hp
	build_wall()
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

# MIREni PRIMO PRSTEM: smer je presne ten, kterym prst lezi od barbara, a
# VZDALENOST PRSTU URCI ROZPTYL (Jan, Oct 2026: "vzdalenost prstu od barbara
# bude urcovat rozptyl projektilu. Cim dal od barbara, tim primnejsi").
# Uhel se orizne na 180° dopredu, takze se nikdy neotoci zpet k sobe.
func aim_at(pos: Vector2) -> void:
	var d: Vector2 = pos - center
	var dist: float = d.length()
	_spread_from_distance(dist)
	if dist <= 0.001:
		aiming = true
		return
	var rel: float = wrapf(d.angle() + PI * 0.5, -PI, PI)
	rel = clampf(rel, -PI * 0.5, PI * 0.5)
	aim = Vector2.from_angle(-PI * 0.5 + rel)
	aiming = true


# BLIZKO = SIROKY, DALEKO = PRIMY. U barbara se ostepy rozleti, na konci
# dostrelu leti presne. Mezi tim linearni prechod, aby to bylo odhadnutelne.
# `near` je tesne nad telem barbara, `far` je polovina dostrelu - dal uz nema
# smysl hledat, protoze prst dojede na kraj displeje.
func _spread_from_distance(dist: float) -> void:
	var near: float = warrior_r() * 2.5
	var far: float = field_r * 1.5
	var t: float = clampf((dist - near) / maxf(1.0, far - near), 0.0, 1.0)
	spread_scale = lerpf(SPREAD_SCALE_MAX, SPREAD_SCALE_MIN, t)


func release() -> void:
	aiming = false


# ROZPTYL: nasobek rozestupu vic ostrepu. 1.0 = zaklad (SPREAD).
func set_spread_scale(s: float) -> void:
	spread_scale = clampf(s, SPREAD_SCALE_MIN, SPREAD_SCALE_MAX)


# ------------------------------------------------------------------ KROK

func step(dt: float) -> void:
	if is_over() or paused:
		return
	clock += dt
	hit_flash = maxf(0.0, hit_flash - dt)
	wall_flash = maxf(0.0, wall_flash - dt)
	_regen(dt)
	_phase(dt)
	_fire(dt)
	_move_enemies(dt)
	_move_spears(dt)
	_move_shots(dt)
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
	# HRADBA SE STAVI ZNOVU: priprava pred vlnou je cas, kdy ji hrac "spravi".
	build_wall()
	phase = "build"
	build_left = BUILD_S


func _spawn() -> void:
	# NEPRATELE JDOU SHORA: rodi se u horniho okraje plochy, ne kolem dokola.
	# Sireni po cele sirce, aby se hrac nemohl jen schovat do jednoho rohu.
	var t: Dictionary = _pick_type(wave)
	var er: float = maxf(MIN_ENEMY_R, field_r * float(t["r"]))
	var span: float = minf(arena.size.x * 0.42, field_r * 0.95)
	var x: float = center.x + rng.randf_range(-span, span)
	var p0 := Vector2(clampf(x, er + 4.0, arena.end.x - er - 4.0), arena.position.y + er * 1.05)
	# CESTA JE ROVNE DOLU: merit se k mistu, kde se nepratel zastavi (hradba,
	# u strelcu jejich odstup), ne k bojovnikovi.
	var line_y: float = wall_top() - er
	if bool(t["ranged"]):
		line_y = center.y - float(t["stop"]) * field_r
	var dist: float = maxf(1.0, line_y - p0.y)
	var p := {
		"pos": p0,
		"kind": String(t["id"]),
		"r": er,
		"ranged": bool(t["ranged"]),
		"hp": enemy_hp(wave) * float(t["hp"]),
		"max_hp": enemy_hp(wave) * float(t["hp"]),
		# KAZDY DRUH MA SVOU DOBU CHUZE - je to doba, ne rychlost, aby to na
		# kazdem displeji vyslo stejne.
		"speed": dist / (travel_time() * float(t["travel"])),
		"dmg": enemy_dmg(wave) * float(t["dmg"]),
		"atk_left": WALL_ATTACK_CD * rng.randf_range(0.55, 1.0),
		"alive": true,
	}
	if bool(t["ranged"]):
		p["stop"] = float(t["stop"])
		p["shot_left"] = float(t["shot_cd"]) * rng.randf_range(0.35, 0.9)
		p["shot_cd"] = float(t["shot_cd"])
		p["shot_dmg"] = float(t["shot_dmg"])
		p["shot_spd"] = float(t["shot_spd"])
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
	var total: float = SPREAD * spread_scale
	var step: float = 0.0
	if n > 1:
		step = total / float(n - 1)
	for i in range(n):
		# JEDEN OSTEP LETI PRESNE TAM, KAM HRAC MIRI. Rozestup se pridava jen
		# u vicenasobne strelby - jinak by se jednoducha rana vzdy ukradla
		# o pulku rozestupu do strany.
		var a: float = aim.angle()
		if n > 1:
			a += -total * 0.5 + step * float(i)
		spears.append({
			"pos": center + Vector2(cos(a), sin(a)) * (warrior_r() + spear_r()),
			"dir": Vector2(cos(a), sin(a)),
			"dmg": damage(), "ric": ricochet(), "hit": [],
		})


# POHYB NEPRATEL: STRIKTNE ROVNE DOLU (Jan, Oct 2026: "Žádné směřování do
# středu. Žádné kličkování."). Kazdy si drzi svuj sloupec - meni se jen y.
# U hradby se zastavi a mlati do ni; strelci stoji v odstupu a strili.
func _move_enemies(dt: float) -> void:
	for e in enemies:
		if not bool(e["alive"]):
			continue
		var pos: Vector2 = e["pos"]
		var line: float = _line_y(e)
		if pos.y < line:
			e["pos"] = Vector2(pos.x, minf(line, pos.y + float(e["speed"]) * dt))
			continue
		# STRELEC: stoji a strili. Jeho strela narazi do hradby, dokud stoji.
		if bool(e.get("ranged", false)):
			e["shot_left"] = float(e["shot_left"]) - dt
			if float(e["shot_left"]) <= 0.0:
				_shoot(e)
				e["shot_left"] = float(e["shot_cd"])
			continue
		# NA HRADBE: rana do ni. Kdyz uz stoji jen zbytky, jde rana do Barbara.
		e["atk_left"] = float(e.get("atk_left", WALL_ATTACK_CD)) - dt
		if float(e["atk_left"]) <= 0.0:
			e["atk_left"] = WALL_ATTACK_CD
			_strike(e)


# KDE SE NEPRATEL ZASTAVI. Pesak se dotkne hradby okrajem tela, strelec stoji
# v odstupu `stop` od Barbara (hradba je pro nej jen prekazka mezi nim a cilem).
func _line_y(e: Dictionary) -> float:
	var stop_px: float = float(e.get("stop", 0.0)) * field_r
	if bool(e.get("ranged", false)) and stop_px > 0.0:
		return center.y - stop_px
	return wall_top() - radius_of(e)


# RANA NA BLIZKO: nejdriv hradba, teprve kdyz padne, Barbara.
func _strike(e: Dictionary) -> void:
	if wall_hp > 0.0:
		_damage_wall(float(e["dmg"]))
		return
	_hurt_warrior(float(e["dmg"]))


# STRELA NEPRITELE: leti presne na bojovnika v okamziku vystrelu. Hrac ji vidi
# prichazet, ale neda se od ni usknout - musi strelce zabit.
func _shoot(e: Dictionary) -> void:
	var from: Vector2 = e["pos"]
	var aim_vec: Vector2 = (center - from).normalized()
	var dmg: float = enemy_dmg(wave) * float(e.get("shot_dmg", 0.6))
	enemy_shots.append({
		"pos": from + aim_vec * (radius_of(e) + field_r * 0.02),
		"dir": aim_vec,
		"dmg": dmg,
		"spd": field_r * float(e.get("shot_spd", 0.5)),
		"r": field_r * 0.013,
		"kind": String(e.get("kind", "ghost")),
		"alive": true,
	})


func _hurt_warrior(amount: float) -> void:
	hp -= amount
	hit_amount = amount
	hit_flash = 0.45


func _move_shots(dt: float) -> void:
	for s in enemy_shots:
		if not bool(s.get("alive", true)):
			continue
		var prev: Vector2 = s["pos"]
		var pos: Vector2 = prev + (s["dir"] as Vector2) * float(s["spd"]) * dt
		s["pos"] = pos
		# HRADBA STRELU ZACHYTI: dokud stoji, nedoleti k Barbarovi. Je to
		# stejna cara jako pro pesaky, aby se hrac mohl spolehnout na jedno.
		if wall_hp > 0.0 and prev.y < wall_top() and pos.y >= wall_top():
			_damage_wall(float(s["dmg"]))
			s["alive"] = false
			continue
		if pos.distance_to(center) <= warrior_r() + float(s["r"]):
			_hurt_warrior(float(s["dmg"]))
			s["alive"] = false
			continue
		if not arena.grow(field_r * 0.20).has_point(pos):
			s["alive"] = false


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
		if (e["pos"] as Vector2).distance_to(pos) <= radius_of(e) + spear_r():
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
	var keep_o: Array = []
	for s in enemy_shots:
		if bool(s.get("alive", true)):
			keep_o.append(s)
	enemy_shots = keep_o


# ------------------------------------------------------------------ HLASKY

func _note(s: String) -> void:
	log.append(s)
	if log.size() > 30:
		log.pop_front()


func last_note() -> String:
	if log.is_empty():
		return ""
	return String(log[log.size() - 1])
