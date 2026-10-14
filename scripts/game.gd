class_name Game
extends RefCounted

# CELA HRA. Zadny uzel, zadny Input, zadne _draw - proto ji jde hrat a merit
# headless (`tools/test_core.gd`, `tools/balance_sim.gd`) a proto se da
# overit, ze se chova stejne na kazde obrazovce.
#
# MODEL (rozhodnuty s Janem, Oct 2026):
#   * jedna vez ve stredu KRUHOVE plochy, kolem prazdno,
#   * vez vidi jen svoji barvu (na ostatni dava nulu a nestrili na ne),
#   * svazek drzi jeden cil, dokud neumre,
#   * poutnici vstupuji na okraji plochy NASLEPO a jdou rovne k vezi,
#   * cesta od okraje k vezi trva TRAVEL_S (12 s, u zakladni barvy),
#   * PAPRSEK JE JEN ZAMEROVANI (ukazuje, na koho vez miri) - poskozeni
#     neubira on, ale DOPAD strely: od veze leti velmi rychla tecka a teprve
#     jeji dopad ubere zivoty,
#   * rychlost strelby je upgrade (vic ran za sekundu = vic tecek v paprsku),
#   * barvy se vybiraji z palety DOLE, do pole se neklepe,
#   * kazda barva ma sve chovani (rozpad, regenerace, mizeni, zmena barvy),
#   * barvy pribyvaji s obtiznosti (odemykaji se vlnami, dokud nejsou levely).

# CESTA OD OKRAJE K VEZI. Je to CAS, ne rychlost v pixelech: na kazdem displeji
# ma poutnik na cestu stejne dlouho, takze "jde pomalu" je vlastnost hry, ne
# rozliseni. Jan (Oct 2026): "Rychlost všech nepřátel se musí snížit, aby to
# vzbudilo dojem ještě větší vzdálenosti" - 8 s -> 12 s. S pomalejsim poutnikem
# se dostrel muze vratit na mensi usek a okno na reakci zustava (~4,5 s).
const TRAVEL_S := 12.0
const BASE_HP := 34.0
const HP_GROWTH := 0.13
const START_GOLD := 100
const START_LIVES := 12
const BUILD_TIME := 5.0
const WAVE_MAX := 10
const WAVE_SIZES := [4, 5, 6, 7, 8, 9, 10, 11, 12, 14]
const WAVE_BONUS := 30
const WAVE_BONUS_PER_WAVE := 10

# MEZERA MEZI POUTNIKY SE ZKRACUJE. Tlak hry nejde z rychlosti (tu drzi
# "cesta trva 8 s"), ale z toho, kolik jich jde naraz: kdyz je mezera delsi
# nez cas na zabiti, vez ma vzdycky cas a hrac jen zírá.
const SPAWN_GAP_START := 2.5
const SPAWN_GAP_MIN := 1.2
const SPAWN_GAP_PER_WAVE := 0.13

# STRELA JE TECKA, KTERA MA BYT VIDET. Rychlost je podil POLOMERU PLOCHY, ne
# pevne pixely za sekundu: pres ZAKLADNI DOSTREL (Tower.RANGE_FRACS[0] = 0,42
# polomeru) leti tecka vzdy ~0,33 s, na telefonu i na velkem displeji. Jan
# (Oct 2026): "Rychlost projektilu musíme snížit" - bylo to 0,15 s a byl to
# jen blik; 0,33 s uz je videt jako letici tecka a pri kadenci 3 ran/s je
# v paprsku videt skoro porad.
const SHOT_SPEED_FRAC := 1.36
# POLOMER TECKY. Mala - je to tecka, ne koule; v paprsku jich ma byt videt vic.
const SHOT_R_FRAC := 0.022

# ROZVRZENI PLOCHY jde do hry jednim mistem (`set_field`). Rychlost poutnika
# je z nej ODVOZENA, takze "cesta trva 8 s" plati na telefonu i na velkem
# displeji; pevne pixely za sekundu by na male obrazovce znamenaly kratsi
# dobu v ohne - a tim jinou hru.
#
# PLOCHA A MERITKO JSOU DVE RUZNA CISLA (Jan, Oct 2026: "Zoom měl zůstat
# stejný. Jen se měly změnit rozměry jednotlivých zón."). Spawnovaci kruh je
# vetsi nez displej, ale vez, poutnici a tahy zustavaji stejne velke:
#   * `field_r` = SPAWNOVACI KRUH (odkud poutnici vstupuji, muze vest mimo obraz)
#   * `unit_r`  = MERITKO KRESLENI (polomer stareho vepsaneho kruhu)
# `tower_r` je z meritka ODVOZENY (`unit_r * TOWER_R_FRAC`) - nikdy se
# nenastavuje zvlast, aby se dve cisla nemohla rozejit.
var field_r: float = 300.0
var unit_r: float = 300.0
var tower_r: float = 30.0
var center: Vector2 = Vector2.ZERO

var tower: Tower = Tower.new()
var pilgrims: Array = []
var locks: Array = []
# STRELY. Kazda je slovnik `{pos, target, dmg}`: tecka leti od veze k cili a
# poskozeni udeli az v okamziku dopadu. `shots_fired` je pocitadlo vsech ran
# (HUD i testy se ho ptaji, kolik jich vez za cas vystrelila).
var shots: Array = []
var shots_fired: int = 0
# RYTMUS STRELBY: cas do dalsi rany a ktery z zamerenych cilu je na rade.
var fire_left: float = 0.0
var fire_i: int = 0
var palette: Array = []
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
	refresh_palette()


# MERITKO KRESLENI VEZE. Je to podil MERITKA (`unit_r`), ne polomeru plochy -
# plocha muze byt vetsi nez displej, ale vez ma porad stejnou velikost.
const TOWER_R_FRAC := 0.12


func set_field(r: float, u: float, c: Vector2) -> void:
	field_r = maxf(r, 1.0)
	unit_r = maxf(u, 1.0)
	tower_r = unit_r * TOWER_R_FRAC
	center = c


# RYCHLOST ZAKLADNI BARVY (nasobek barvy se pripocte zvlast). Cesta od okraje
# k okraji veze musi trvat presne TRAVEL_S - proto se nepocita z celeho
# polomeru, ale k obvodu veze.
func pilgrim_speed() -> float:
	return maxf(0.001, (field_r - tower_r) / TRAVEL_S)


func is_over() -> bool:
	return phase == "won" or phase == "lost"


# ---------------------------------------------------------------- BARVY

# PALETA JE JEDINY ZDROJ PRAVDY O TOM, CO HRAc MUZE ZVOLIT. Kresli se z ni
# i tlacitka dole, takze se nemuze stat, ze by hrac videl barvu, kterou
# zvolit nejde (nebo naopak).
#
# Kdyz paleta povyroste, hra to REKNE: nova barva znamena nove pravidlo
# (rozpad, regenerace, mizeni) a ticha zmena by nechala hrace hledat, proc
# se neco deje jinak.
func refresh_palette() -> void:
	var before: int = palette.size()
	palette = Hue.palette_at(wave)
	tower.palette = palette
	if not palette.has(tower.hue) and not palette.is_empty():
		tower.hue = int(palette[0])
	if before > 0 and palette.size() > before:
		for h in palette:
			if not Hue.palette_at(wave - 1).has(h):
				_note("Přibyla barva: %s. %s" % [Hue.name_of(h), _behaviour_hint(h)])


# BARVY, KTERE V TETO VLNE VSTUPUJI (vcetne stribrne, ktera v palete neni).
func spawn_pool() -> Array:
	return Hue.active_at(wave)


func select_hue(h: int) -> bool:
	if not palette.has(h):
		return false
	tower.hue = h
	return true


# ---------------------------------------------------------------- KROK HRY

func step(dt: float) -> void:
	if is_over():
		return
	_phase_step(dt)
	_move(dt)
	_aim()
	_fire(dt)
	_advance_shots(dt)
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
			spawn_left = spawn_gap()
	elif pilgrims.is_empty():
		gold += WAVE_BONUS + WAVE_BONUS_PER_WAVE * wave
		if wave >= WAVE_MAX:
			phase = "won"
			_note("Vyhráno — všech %d vln odraženo." % WAVE_MAX)
		else:
			_note("Vlna %d odražena." % wave)
			wave += 1
			refresh_palette()
			phase = "build"
			build_left = BUILD_TIME


func spawn_gap() -> float:
	return maxf(SPAWN_GAP_MIN, SPAWN_GAP_START - SPAWN_GAP_PER_WAVE * float(wave))


func _start_wave() -> void:
	plan = wave_plan(wave)
	spawned = 0
	spawn_left = 0.0
	phase = "wave"
	_note("Vlna %d — %d poutníků." % [wave, plan.size()])
	_announce_new_enemies()


# BARVY, KTERE NEJSOU V PALETE, SE OHLASTI ZVLAST: hrac je nemuze zvolit, takze
# by jen videl, ze "neco" jde po plose a neslo to zabit. Stribrna je prvni
# takova barva.
func _announce_new_enemies() -> void:
	if wave <= 1:
		return
	var prev: Array = Hue.active_at(wave - 1)
	for h in Hue.active_at(wave):
		if prev.has(h) or Hue.in_palette(h):
			continue
		_note("Na ploše se objeví %s. %s" % [Hue.name_of(h), _behaviour_hint(h)])


# CO HRAc POTREBUJE VEDET O BARVE. Bez toho by mu prislo, ze se neco deje
# "samo" - rozpad modre, regenerace zelene, mizeni fialove.
func _behaviour_hint(h: int) -> String:
	match Hue.behaviour_of(h):
		Hue.B_SPLIT:
			return "Po zabití se rozpadne na dva menší kusy."
		Hue.B_REGEN:
			return "Obnovuje si životy — musíš ho stihnout dřív."
		Hue.B_VANISH:
			return "Po prvním zásahu na tři vteřiny zmizí a putuje dál."
		Hue.B_SHIFT:
			return "Mění každé tři vteřiny barvu a na stříbrnou se už nevrátí."
	return ""


# SLOZENI VLNY JE MIX BAREV: kazda vlna posle vsechny barvy, ktere uz do hry
# vstoupily. Kdyby chodila jedna barva, hrac prepne jednou a zírá - to je past,
# kterou hledame celou dobu. Poradi je nahodne, pocet dany.
func wave_plan(n: int) -> Array:
	var total: int = int(WAVE_SIZES[clampi(n - 1, 0, WAVE_SIZES.size() - 1)])
	var pool: Array = Hue.active_at(n)
	var out: Array = []
	if pool.is_empty():
		return out
	for i in range(total):
		out.append(int(pool[i % pool.size()]))
	# Fisher-Yates vlastnim rng, aby hra zustala deterministicka
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Variant = out[i]
		out[i] = out[j]
		out[j] = t
	return out


func hp_for(n: int, h: int) -> float:
	return BASE_HP * pow(1.0 + HP_GROWTH, float(n - 1)) * Hue.hp_mult(h)


# VSTUP POUTNIKA. Pouziva to hra i testy: `a` je uhel na okraji plochy,
# `h` barva (-1 = losovat z toho, co je ve hre).
func spawn_at_angle(a: float, h: int = -1) -> Pilgrim:
	var pool: Array = spawn_pool()
	var hue: int = h
	if not Hue.is_valid(hue):
		hue = int(pool[rng.randi_range(0, maxi(0, pool.size() - 1))])
	var p := Pilgrim.new()
	p.hue = hue
	p.behaviour = Hue.behaviour_of(hue)
	p.pos = center + Vector2(cos(a), sin(a)) * field_r
	p.dir = (center - p.pos).normalized()
	p.max_hp = hp_for(wave, hue)
	p.hp = p.max_hp
	p.speed = pilgrim_speed() * Hue.speed_mult(hue)
	# STRIBRNA: prvni zmena barvy po SHIFT_S a pak porad dal, na stribrnou
	# se uz nikdy nevrati.
	if p.behaviour == Hue.B_SHIFT:
		p.shift_left = Hue.SHIFT_S
	pilgrims.append(p)
	return p


func _spawn_next() -> void:
	spawn_at_angle(rng.randf() * TAU, int(plan[clampi(spawned, 0, plan.size() - 1)]))
	spawned += 1


func _move(dt: float) -> void:
	for p in pilgrims:
		if not p.alive:
			continue
		_advance_behaviour(p, dt)
		p.pos += p.dir * p.speed * dt
		if p.pos.distance_to(center) <= tower_r:
			p.alive = false
			lives -= 1
			_note("%s došel k věži." % Hue.name_of(p.hue))
			if lives <= 0:
				lives = 0
				phase = "lost"
				_note("Konec — srdce podlehlo.")


# CHOVANI BAREV. Cte se z POUTNIKA (`p.behaviour`), ne z jeho barvy: stribrna
# po prvni zmene barvu zmeni, ale sve chovani si nese dal.
func _advance_behaviour(p: Pilgrim, dt: float) -> void:
	if p.behaviour == Hue.B_REGEN:
		# ZELENA: obnovuje si zivoty, ale nikdy nad sve maximum.
		p.hp = minf(p.max_hp, p.hp + p.max_hp * Hue.REGEN_FRAC * dt)
	if p.ghost_left > 0.0:
		# FIALOVA: cas, po ktery ji vez nevidi.
		p.ghost_left = maxf(0.0, p.ghost_left - dt)
	if p.behaviour == Hue.B_SHIFT:
		p.shift_left -= dt
		if p.shift_left <= 0.0:
			p.shift_left = Hue.SHIFT_S
			p.hue = _random_other_hue(p.hue)


# NA STRIBKNOU SE UZ NIKDY NEVRACI a losuje se jen z barev, ktere jsou ve hre -
# kdyby si stribrna vybrala barvu, ktera do hry jeste nevstoupila, byla by
# nepolapitelna a hrac by nemel jak zasahnout.
func _random_other_hue(cur: int) -> int:
	var pool: Array = []
	for h in spawn_pool():
		if h != cur and h != Hue.SILVER:
			pool.append(h)
	if pool.is_empty():
		return Hue.RED
	return int(pool[rng.randi_range(0, pool.size() - 1)])


func in_range(p: Pilgrim, r: float) -> bool:
	return p.pos.distance_to(center) <= r


# SVAZEK (ZAMEROVANI). Drzi cil, dokud neumre - a zámek se uvolni jen tehdy,
# kdyz je cil mrtvy, mimo dostrel, nebo kdyz hrac zmenil barvu (pak uz ho vez
# nevidi). SAM POSKOZENI NEDAVA: paprsek je od Oct 2026 jen ukazatel, na koho
# vez miri ("Bude to ukazatel na koho věž míří. Jako zaměřování.").
func _aim() -> void:
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


# RYTMUS STRELBY. Vez strili na zamrene cile; kadence je z tabulky veze
# (`Tower.rate`), takze upgrade je videt jako hustsi proud tecek. Kdyz nema
# vez na co mirrit, hlaven se "nabije" hned (dalsi rana pri zamereni).
func _fire(dt: float) -> void:
	if locks.is_empty():
		fire_left = 0.0
		return
	fire_left -= dt
	# STRAZCE: kdyby dt prislo obrovske (teleport ve hre), nema se vystrelit
	# sto ran v jednom snimku.
	var guard: int = 0
	while fire_left <= 0.0 and guard < 8:
		guard += 1
		_spawn_shot(locks[fire_i % locks.size()])
		fire_i += 1
		fire_left += 1.0 / tower.rate()


# STRELA VYCHAZI Z OKRAJE VEZE, ne z jejiho stredu - tecka ma byt videt jako
# neco, co z veze opravdu vyletelo.
func _spawn_shot(p: Pilgrim) -> void:
	var dir: Vector2 = (p.pos - center).normalized()
	shots.append({"pos": center + dir * tower_r, "target": p, "dmg": tower.shot_damage()})
	shots_fired += 1


# LET STRELY A DOPAD. Strela leti VELMI RYCHLE (v paprsku jich je proto videt
# nekolik naraz a vypada to jako stabilni paprsek, kterym rytmicky proudi
# strely) a poskozeni udeli az ve chvili, kdy do cile doleti. Kdyz cil mezitim
# zmizi (umrel, hrac prepnul barvu, fialova se zneviditelnila), strela zanikne -
# nikoho jineho nezasahne.
func _advance_shots(dt: float) -> void:
	var keep: Array = []
	for s in shots:
		var p: Pilgrim = s["target"]
		if not p.alive or not tower.sees(p):
			continue
		var pos: Vector2 = s["pos"]
		var d: Vector2 = p.pos - pos
		var step_len: float = shot_speed() * dt
		if d.length() <= step_len + shot_r():
			_damage(p, float(s["dmg"]))
			continue
		s["pos"] = pos + d.normalized() * step_len
		keep.append(s)
	shots = keep


# POSKOZENI POUTNIKA. Jedno misto pro dopad strely (a pro kohokoli dalsiho,
# kdo bude v budoucnu ublizovat): prvni zasah je pro fialovou znameni, ze ma
# zmizet, a nula zivotu znamena smrt.
func _damage(p: Pilgrim, amount: float) -> void:
	if not p.alive:
		return
	var before: float = p.hp
	p.hp -= amount
	if p.hp < before and not p.was_hit:
		p.was_hit = true
		# FIALOVA: po PRVNIM zasahu zmizi na 3 s (putuje dal, ale vez ji
		# nevidi, i kdyz ma hrac jeji barvu).
		if p.behaviour == Hue.B_VANISH:
			p.ghost_left = Hue.VANISH_S
	if p.hp <= 0.0:
		_kill(p)


func _kill(p: Pilgrim) -> void:
	p.alive = false
	gold += _gold_for(p)
	# MODRA: rozpadne se na dva mensi kusy. Hra se tim zhusti presne tam, kde
	# ma vez nejmene casu. Kusy se dal nedeli (z jednoho poutnika by bylo
	# nekonecno) a jdou porad ROVNE k vezi - jen stoji vedle sebe.
	if p.behaviour == Hue.B_SPLIT and p.can_split:
		var side: Vector2 = p.dir.rotated(PI * 0.5)
		for i in range(Hue.SPLIT_PIECES):
			var q := Pilgrim.new()
			q.hue = p.hue
			q.behaviour = Hue.B_NONE
			q.can_split = false
			q.size = p.size * Hue.SPLIT_SIZE
			q.max_hp = maxf(1.0, p.max_hp * Hue.SPLIT_HP_FRAC)
			q.hp = q.max_hp
			q.speed = p.speed
			q.pos = p.pos + side * (pilgrim_r() * 1.6 * (float(i) * 2.0 - 1.0))
			q.dir = (center - q.pos).normalized()
			pilgrims.append(q)


func _gold_for(p: Pilgrim) -> int:
	if not p.can_split:
		return Hue.SPLIT_GOLD
	return Hue.gold_of(p.hue)


func _closer(a: Pilgrim, b: Pilgrim) -> bool:
	return a.pos.distance_squared_to(center) < b.pos.distance_squared_to(center)


func _prune() -> void:
	var keep: Array = []
	for p in pilgrims:
		if p.alive:
			keep.append(p)
	pilgrims = keep


# POLOMER POUTNIKA VE HRE. Obrazovka si bere svoje meritko, ale rozpad modre
# potrebuje vedet, jak daleko od sebe kusy stat - proto je to tady jednim
# mistem (`pilgrim_r_frac`).
const PILGRIM_R_FRAC := 0.05

func pilgrim_r() -> float:
	return unit_r * PILGRIM_R_FRAC


# RYCHLOST LETU STRELY A POLOMER TECKY. Rychlost je podil POLOMERU PLOCHY
# (let pres dostrel trva porad stejne dlouho), polomer tecky podil MERITKA
# (tecka je stejne velka, i kdyz je plocha vetsi nez displej).
func shot_speed() -> float:
	return field_r * SHOT_SPEED_FRAC


func shot_r() -> float:
	return unit_r * SHOT_R_FRAC


# ---------------------------------------------------------------- VSTUP

# POPIS UPGRADU SE TYKA TOHO, CO HRAc OPRAVDU POZNA: kadence (pocet ran za
# sekundu) je ta vec, ktera je videt, a cisla se pisi s ceskou desetinnou
# carkou.
func _rate_text() -> String:
	return ("%.1f" % tower.rate()).replace(".", ",") + " ran/s"


func buy_upgrade() -> bool:
	if not tower.can_upgrade() or gold < tower.upgrade_cost():
		return false
	gold -= tower.upgrade_cost()
	tower.upgrade()
	_note("Věž na %d. stupni (dostřel %d %%, %s, %d cíl)."
		% [tower.level, int(round(tower.range_frac() * 100.0)), _rate_text(), tower.targets()])
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
