class_name Game
extends RefCounted

# CELA HRA. Zadny uzel, zadny Input, zadne _draw - proto ji jde hrat a merit
# headless a proto se da overit, ze se chova stejne na kazde obrazovce.
#
# MODEL (rozhodnuty s Janem, Oct 2026 - "jako ve hře Tower"):
#   * hra je delena na LEVELY; level ma 3-5 VLN a bonus je az za vyhrany level,
#   * v bitve se za ZLATO kupuji docasne kroky upgradu a na kazdem levelu se
#     kupuji ZNOVU (zlato zacina na kazdem levelu znovu),
#   * v menu se za BODY (za vyhrany level) kupuji PERMANENTNI stupne, ktere
#     posouvaji START kazdeho parametru,
#   * SPECIÁL (multishot, ricochet, jed, led) je jen permanentni,
#   * vez ma ZIVOTY: poutnik, ktery dojde, ubere tolik, kolik mu zbylo zivotu,
#     zbroj to zredukuje a regenerace doléčí,
#   * prohra vraci hrace do menu; zlato z rozehraneho levelu propada, upgrady
#     i body zustavaji.
#
# Kdo chce zmenit cisla, meni `Upgrades.STATS` (upgrady) nebo konstanty tady
# (obtiznost). Obrazovka ani testy si NIKDY nepocitaji hodnotu samy.

# ---------------------------------------------------------------- KONSTANTY

# CESTA OD OKRAJE K VEZI. Je to CAS, ne rychlost v pixelech: na kazdem displeji
# ma poutnik na cestu stejne dlouho, takze "jde pomalu" je vlastnost hry, ne
# rozliseni. Jan dvakrat: "Rychlost všech nepřátel se musí snížit" (8 -> 12 s)
# a "Celkově ještě zpomalíme pohyb nepřátel" (12 -> 15 s).
const TRAVEL_S := 15.0
const BASE_HP := 20.0
# OBTIZNOST: kazdy dalsi LEVEL je o 15 % tuzsi (Jan schvalil 1,15) a kazda
# dalsi vlna v levelu o 5 %. Driv to bylo 13 % za vlnu v nekonecne partii -
# s levelem a resetenym zlatem by to bylo nehratelne.
const LEVEL_HP := 1.22
const WAVE_HP := 1.15
const START_GOLD := 150
const BUILD_TIME := 5.0
# VELIKOST VLNY PODLE PORADI KOLA (kolo = pocitadlo vln pres cely pruchod hrou).
# Prvnich deset je rucne, dal uz jen roste - levelu je nekonecne.
const WAVE_SIZES := [5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
const WAVE_SIZES_MAX := 24
const WAVE_BONUS := 30
const WAVE_BONUS_PER_WAVE := 10
# ODMENA ZA VYHRANY LEVEL V BODECH (Jan schvalil): 25 + 5 * level.
const BODY_BASE := 25
const BODY_PER_LEVEL := 5
# LEVEL MA 3-5 VLN: prvni dva levely tri, treti a ctvrty ctyri, od peteho pet.
const WAVES_EASY := 3
const WAVES_MID := 4
const WAVES_FULL := 5
# KOLO SE POCITA VZDY PO PETI VLNACH, i kdyz level ma tri - jinak by se barvy
# odemykaly podle toho, jak dlouhy level zrovna je, a hrac by je vidal nahodne.
const KOLO_PER_LEVEL := 5

# DOCASNE UCPINKY: mezera mezi poutniky se v ramci levelu zkracuje.
const SPAWN_GAP_START := 2.5
const SPAWN_GAP_MIN := 1.2
const SPAWN_GAP_PER_WAVE := 0.13

# STRELA. Rychlost je podil POLOMERU PLOCHY, polomer tecky podil MERITKA.
const SHOT_SPEED_FRAC := 0.80
const SHOT_R_FRAC := 0.032
const SHOT_RIM_FRAC := 1.55
# POSKOZENI JEDNE RANY. Kadenci a kritiku resi upgrady - tohle je zaklad,
# ze ktereho se vsechno nasobi.
const SHOT_DMG := 10.0
# JED A LED: jak dlouho ucinek drzi. Podil (20/35/50 %) je v tabulce upgradu.
const POISON_S := 3.0
const ICE_S := 2.0
# RICOCHET: na kazdeho poutnika se v jednom odrazu dostane nejvyse jednou
# (Jan: "vždy jen jeden odraz za každého unikátního nepřítele").
const RICOCHET_RANGE_FRAC := 0.55

# ------------------------------------------------------------------ ROZVRZENI

var field_r: float = 300.0
var unit_r: float = 300.0
var tower_r: float = 30.0
var center: Vector2 = Vector2.ZERO

# ------------------------------------------------------------------- STAV HRY

var profile: Profile = Profile.new()
var tower: Tower = Tower.new()
# PALETA HRACE = barvy, ktere hrac muze zvolit. Je to vlastnost HRY (ne veze),
# protoze z ni obrazovka kresli tlacitka dole; vez si ji jen prevzima
# (`tower.palette = palette` v `refresh_palette`).
# POZOR: `game_view` ji cte na peti mistech. Kdyz tu chybi, GDScript to ohlasí
# jen do logu ("Invalid get index 'palette'"), tlacitka se nedokresli a hrac
# nemuze prenastavit barvu - cela mechanika hry zmizi a testy pritom projdou.
var palette: Array = []

# LEVEL = sada vln; WAVE = kolikata vlna v tomto levelu.
var level: int = 1
var wave: int = 1
# DOCASNE KROKY TOHOTO LEVELU: id -> kolik kroku hrac koupil. Na kazdem levelu
# se zacina s prazdnym slovnikem - presne to je "kupuje se znovu od nuly".
var temp: Dictionary = {}
var gold: int = 0
var hp: float = 100.0
var max_hp: float = 100.0
# KOLIK BODU DAL POSLEDNI VYHRANY LEVEL (kresli se v dialogu).
var body_earned: int = 0
# "build" (priprava) / "wave" (vstupy) / "won" (level vyhran) / "lost" (konec)
var phase: String = "build"
var build_left: float = BUILD_TIME
var spawn_left: float = 0.0
var plan: Array = []
var spawned: int = 0
var log: Array = []
# PAUZA HRY. Drzi ji obrazovka (panel upgradu, dotaz pri odchodu) - hra sama
# jen vi, ze stoji, a `step` opravdu nekrokuje.
var paused: bool = false

var pilgrims: Array = []
var locks: Array = []
# STRELY: {pos, target, dmg, bounce, hit} - viz `_advance_shots`.
var shots: Array = []
var shots_fired: int = 0
var fire_left: float = 0.0
var fire_i: int = 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 20261014
	refresh_palette()


func set_field(r: float, u: float, c: Vector2) -> void:
	field_r = maxf(r, 1.0)
	unit_r = maxf(u, 1.0)
	tower_r = unit_r * 0.12
	center = c


# --------------------------------------------------------------- PARAMETRY

# HODNOTA PARAMETRU. Hra, obrazovka i testy se ptaji TOHOHLE - nikdo si ji
# nepocita sam, jinak by ukazoval neco jineho, nez co hra opravdu pouziva.
func val(id: String) -> float:
	return Upgrades.value_of(id, profile.perm_level(id), int(temp.get(id, 0)))


func temp_level(id: String) -> int:
	return int(temp.get(id, 0))


# KADENCE VEZE (rany za sekundu). Parametr je INTERVAL, takze se prepocitava.
func rate() -> float:
	return 1.0 / maxf(0.05, val("as"))


func range_frac() -> float:
	return val("ar")


func range_px() -> float:
	return range_frac() * field_r


func targets() -> int:
	return int(round(val("ms")))


func crit_chance() -> float:
	return val("cc")


func crit_dmg() -> float:
	return val("cd")


func armor() -> float:
	return clampf(val("am"), 0.0, 0.9)


func regen() -> float:
	return val("rg")


func ricochet() -> int:
	return int(round(val("rc")))


func poison_frac() -> float:
	return val("ps")


func ice_frac() -> float:
	return val("ic")


func pilgrim_speed() -> float:
	return maxf(0.001, (field_r - tower_r) / TRAVEL_S)


# ------------------------------------------------------------------ LEVELY

# KOLO = poradi vlny pres cely pruchod hrou (pocita se po peti vlnach na level).
func kolo() -> int:
	return KOLO_PER_LEVEL * (level - 1) + wave


func waves_in_level() -> int:
	if level <= 2:
		return WAVES_EASY
	if level <= 4:
		return WAVES_MID
	return WAVES_FULL


func wave_size(k: int) -> int:
	if k <= WAVE_SIZES.size():
		return int(WAVE_SIZES[k - 1])
	return mini(WAVE_SIZES_MAX, int(WAVE_SIZES[WAVE_SIZES.size() - 1]) + (k - WAVE_SIZES.size()) / 2)


func is_over() -> bool:
	return phase == "won" or phase == "lost"


# NOVY LEVEL. Zlato zacina znovu (jen se zakladnim bonusem), docasne kroky se
# smazou - presne to je smysl "v kazdem kole se kupuje od znovu".
func start_level(n: int) -> void:
	level = maxi(1, n)
	wave = 1
	temp = {}
	phase = "build"
	build_left = BUILD_TIME
	body_earned = 0
	pilgrims = []
	locks = []
	shots = []
	fired_reset()
	max_hp = val("hp")
	hp = max_hp
	gold = START_GOLD + int(round(val("gl")))
	plan = []
	spawned = 0
	refresh_palette()
	_note("Level %d — %d vln." % [level, waves_in_level()])


func fired_reset() -> void:
	shots_fired = 0
	fire_left = 0.0
	fire_i = 0


# VYHRANY LEVEL: body za level, odemkne se dalsi. Hra dal nekrokuje, dokud se
# hrac nerozhodne (`next_level` / obrazovka do menu).
func _level_won() -> void:
	phase = "won"
	body_earned = BODY_BASE + BODY_PER_LEVEL * level
	profile.add_body(body_earned)
	profile.clear_level(level)
	_note("Level %d vyhrán — %d bodů do menu." % [level, body_earned])


func next_level() -> void:
	if phase != "won":
		return
	start_level(level + 1)


func _lose() -> void:
	phase = "lost"
	hp = 0.0
	_note("Konec — věž padla na levelu %d." % level)


# ---------------------------------------------------------------- UPGRADY

# DOCASNY KROK ZA ZLATO (kupuje se kazdy level znovu). Vraci true, kdyz se
# opravdu koupil - obrazovka se na to ptá, ne na to, "co se asi stalo".
func buy_temp(id: String) -> bool:
	var have: int = temp_level(id)
	if have >= Upgrades.temp_max(id):
		return false
	var cost: int = Upgrades.temp_cost(id, have)
	if gold < cost:
		return false
	gold -= cost
	temp[id] = have + 1
	_after_hp_change()
	_note("%s %s (dočasně %d) za %d zlata."
		% [Upgrades.label_of(id), Upgrades.value_text(id, profile.perm_level(id), have + 1),
			have + 1, cost])
	return true


# PERMANENTNI STUPEN ZA BODY (kupuje se v menu, plati se z profilu).
func buy_perm(id: String) -> bool:
	if not profile.buy_perm(id):
		return false
	_after_hp_change()
	_note("%s na %d. permanentním stupni."
		% [Upgrades.label_of(id), profile.perm_level(id)])
	return true


# ZIVOTY SE MUSI PREPOCITAT HNAD: kdyz hrac koupi zivoty, ma je dostat i ted
# (a ne az v dalsim levelu) - jinak by tlacitko "zaplat a nic se nestalo"
# vypadalo rozbite.
func _after_hp_change() -> void:
	var new_max: float = val("hp")
	if new_max > max_hp:
		hp += new_max - max_hp
	max_hp = new_max
	hp = clampf(hp, 0.0, max_hp)


# ------------------------------------------------------------------ KROK HRY

func step(dt: float) -> void:
	if is_over() or paused:
		return
	_phase_step(dt)
	_regen(dt)
	_move(dt)
	_aim()
	_fire(dt)
	_advance_shots(dt)
	_advance_effects(dt)
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
		_wave_clear()


func spawn_gap() -> float:
	return maxf(SPAWN_GAP_MIN, SPAWN_GAP_START - SPAWN_GAP_PER_WAVE * float(wave))


func _start_wave() -> void:
	plan = wave_plan(wave)
	spawned = 0
	spawn_left = 0.0
	phase = "wave"
	_note("Level %d · vlna %d/%d — %d poutníků."
		% [level, wave, waves_in_level(), plan.size()])
	_announce_new_enemies()


# KONEC VLNY. Kdyz to byla posledni vlna levelu, level je vyhrany - a to je
# jedine misto, kde hrac dostane body.
func _wave_clear() -> void:
	gold += WAVE_BONUS + WAVE_BONUS_PER_WAVE * wave + int(round(val("gw")))
	_note("Vlna %d odražena." % wave)
	if wave >= waves_in_level():
		_level_won()
		return
	wave += 1
	phase = "build"
	build_left = BUILD_TIME
	refresh_palette()


# BARVY, KTERE NEJSOU V PALETE, SE OHLASTI ZVLAST: hrac je nemuze zvolit, takze
# by jen videl, ze "neco" jde po plose a neslo to zabit.
func _announce_new_enemies() -> void:
	var prev: Array = Hue.active_at(kolo() - 1)
	for h in Hue.active_at(kolo()):
		if prev.has(h) or Hue.in_palette(h):
			continue
		_note("Na ploše se objeví %s. %s" % [Hue.name_of(h), _behaviour_hint(h)])


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


# PALETA HRACE. Cte se z toho, co je v tomto kole ve hre - barvy pribyvaji
# s obtiznosti. Kdyz se paleta rozsiri, hra to rekne: nova barva znamena nove
# pravidlo a ticha zmena by nechala hrace hledat, proc se neco deje jinak.
func refresh_palette() -> void:
	var before: int = palette.size()
	palette = Hue.palette_at(kolo())
	# VEZ SI PALETU BER Z HRY, ne naopak: tlacitka dole kresli `game_view` z
	# `game.palette`, takze kdyby si vez drzela vlastni kopii, hrac by videl
	# jednu paletu a `Tower.set_hue` by se rozhodoval podle druhe.
	tower.palette = palette
	if not palette.has(tower.hue) and not palette.is_empty():
		tower.hue = int(palette[0])
	if before > 0 and palette.size() > before:
		for h in palette:
			if not Hue.palette_at(kolo() - 1).has(h):
				_note("Přibyla barva: %s. %s" % [Hue.name_of(h), _behaviour_hint(h)])


func spawn_pool() -> Array:
	return Hue.active_at(kolo())


func select_hue(h: int) -> bool:
	return tower.set_hue(h)


# --------------------------------------------------------------- VSTUP POUTNIKU

func wave_plan(n: int) -> Array:
	var total: int = wave_size(kolo())
	var pool: Array = spawn_pool()
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


# ZIVOTY POUTNIKA. Obtiznost roste s levelem (a malo i s vlnou v levelu).
func hp_for(k: int, wave_n: int, h: int) -> float:
	var lv: int = 1 + (k - 1) / KOLO_PER_LEVEL
	var lvl_mult: float = pow(LEVEL_HP, float(lv - 1))
	var wave_mult: float = pow(WAVE_HP, float(maxi(0, wave_n - 1)))
	return BASE_HP * lvl_mult * wave_mult * Hue.hp_mult(h)


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
	p.max_hp = hp_for(kolo(), wave, hue)
	p.hp = p.max_hp
	p.speed = pilgrim_speed() * Hue.speed_mult(hue)
	if p.behaviour == Hue.B_SHIFT:
		p.shift_left = Hue.SHIFT_S
	pilgrims.append(p)
	return p


func _spawn_next() -> void:
	spawn_at_angle(rng.randf() * TAU, int(plan[clampi(spawned, 0, plan.size() - 1)]))
	spawned += 1


# ------------------------------------------------------------------- POHYB

func _move(dt: float) -> void:
	for p in pilgrims:
		if not p.alive:
			continue
		_advance_behaviour(p, dt)
		p.pos += p.dir * p.speed * p.slow_mult() * dt
		if p.pos.distance_to(center) <= tower_r:
			_arrive(p)


# POUTNIK DOSEL K VEZI. Ubere tolik, kolik mu zbylo zivotu, zbroj to zkrati.
# Tohle je jedine misto, kde hrac prichazi o zivoty veze.
func _arrive(p: Pilgrim) -> void:
	p.alive = false
	var dmg: float = maxf(1.0, p.hp) * (1.0 - armor())
	hp -= dmg
	_note("%s došel k věži — %d poškození." % [Hue.name_of(p.hue), int(round(dmg))])
	if hp <= 0.0:
		_lose()


func _regen(dt: float) -> void:
	var r: float = regen()
	if r > 0.0 and hp > 0.0:
		hp = minf(max_hp, hp + r * dt)


func _advance_behaviour(p: Pilgrim, dt: float) -> void:
	if p.behaviour == Hue.B_REGEN:
		p.hp = minf(p.max_hp, p.hp + p.max_hp * Hue.REGEN_FRAC * dt)
	if p.ghost_left > 0.0:
		p.ghost_left = maxf(0.0, p.ghost_left - dt)
	if p.behaviour == Hue.B_SHIFT:
		p.shift_left -= dt
		if p.shift_left <= 0.0:
			p.shift_left = Hue.SHIFT_S
			p.hue = _random_other_hue(p.hue)


# JED A LED SE ODPOCITAVAJI ZVLAST: plati i na poutnika, ktery uz je z dosahu
# (jed je jed) - jinak by upgrady "po zasahu" nic nedelaly.
func _advance_effects(dt: float) -> void:
	for p in pilgrims:
		if not p.alive:
			continue
		if p.ice_left > 0.0:
			p.ice_left = maxf(0.0, p.ice_left - dt)
		if p.poison_left > 0.0:
			p.poison_left = maxf(0.0, p.poison_left - dt)
			_hurt(p, p.poison_dps * dt)


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


# --------------------------------------------------------------- ZAMEROVANI

# SVAZEK DRZI CIL, DOKUD NEUMRE. SAM POSKOZENI NEDAVA: paprsek je jen ukazatel,
# na koho vez miri. Pocet cilu zaraz je upgradovatelny parametr (multishot).
func _aim() -> void:
	var r: float = range_px()
	var keep: Array = []
	for p in locks:
		if tower.sees(p) and in_range(p, r):
			keep.append(p)
	locks = keep
	if locks.size() < targets():
		var pool: Array = []
		for p in pilgrims:
			if tower.sees(p) and in_range(p, r) and not locks.has(p):
				pool.append(p)
		pool.sort_custom(_closer)
		while locks.size() < targets() and not pool.is_empty():
			locks.append(pool.pop_front())


func _fire(dt: float) -> void:
	if locks.is_empty():
		fire_left = 0.0
		return
	fire_left -= dt
	var guard: int = 0
	while fire_left <= 0.0 and guard < 8:
		guard += 1
		_fire_at(locks[fire_i % locks.size()])
		fire_i += 1
		fire_left += 1.0 / rate()


# RANA. Kriticka sance i kriticke poskozeni jsou upgradovatelne parametry,
# takze se losuje PRES RNG HRY - hra zustava deterministicka.
func _fire_at(p: Pilgrim) -> void:
	var dmg: float = SHOT_DMG
	if rng.randf() < crit_chance():
		dmg *= crit_dmg()
	_fire_shot(p, dmg, ricochet(), [])


# STRELA VYCHAZI Z OKRAJE VEZE. `bounce` = kolik odrazu jeste zbyva, `hit` =
# na koho uz se v tomto odrazu dostalo (kazdy poutnik nejvyse jednou).
func _fire_shot(p: Pilgrim, dmg: float, bounce: int, hit: Array) -> void:
	var from: Vector2 = center
	if not hit.is_empty():
		from = p.pos
	else:
		from = center + (p.pos - center).normalized() * tower_r
	var already: Array = hit.duplicate()
	already.append(p)
	shots.append({"pos": from, "target": p, "dmg": dmg, "bounce": bounce, "hit": already})
	shots_fired += 1


# LET STRELY A DOPAD. Poskozeni udeli az ve chvili, kdy do cile doleti. Kdyz
# cil mezitim zmizi (umrel, hrac prepnul barvu, fialova se zneviditelnila),
# strela zanikne - nikoho jineho nezasahne.
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
			_ricochet_from(p, s)
			continue
		s["pos"] = pos + d.normalized() * step_len
		keep.append(s)
	shots = keep


# ODRAZ (RICOCHET). Strela se odrazi na dalsiho poutnika STEJNE BARVY, na
# ktereho se v tomto odrazu jeste nedostalo - a to i kdyz uz je mimo dostrel
# (je to odraz, ne zamereni). Kazdy poutnik dostane nejvyse jednu ranu.
func _ricochet_from(p: Pilgrim, s: Dictionary) -> void:
	var bounce: int = int(s["bounce"])
	if bounce <= 0:
		return
	var hit: Array = s["hit"]
	var best: Pilgrim = null
	var best_d: float = RICOCHET_RANGE_FRAC * field_r
	for q in pilgrims:
		if not q.alive or q.hue != p.hue or hit.has(q):
			continue
		var d: float = q.pos.distance_to(p.pos)
		if d <= best_d:
			best_d = d
			best = q
	if best == null:
		return
	_fire_shot(best, float(s["dmg"]), bounce - 1, hit)


# ------------------------------------------------------------------ POSKOZENI

# POSKOZENI POUTNIKA DOPADEM STRELY. Tady se take aplikuje jed a led - a proto
# to musi byt ODDELENE od "ubrat zivoty" (`_hurt`): kdyby jed skodil pres tuhle
# funkci, OBNAVOVAL by si sam sebe na kazdem snimku a nikdy by nevyprsel.
func _damage(p: Pilgrim, amount: float) -> void:
	if not p.alive:
		return
	# JED A LED SE APLIKUJI PRI KAZDEM ZASAHU (obnovi se cas, ne poskozeni).
	if poison_frac() > 0.0:
		p.poison_left = POISON_S
		p.poison_dps = SHOT_DMG * poison_frac()
	if ice_frac() > 0.0:
		p.ice_left = ICE_S
		p.ice_frac = ice_frac()
	_hurt(p, amount)


# UBRAT ZIVOTY. Jedno misto pro kazdy zdroj poskozeni (dopad strely, jed) -
# hra se nikdy nesmi dostat pod nulu a smrt je taky jen tady.
func _hurt(p: Pilgrim, amount: float) -> void:
	if not p.alive or amount <= 0.0:
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
	gold += Hue.gold_of(p.hue) + int(round(val("gk")))
	# MODRA: rozpadne se na dva mensi kusy. Hra se tim zhusti presne tam, kde
	# ma vez nejmene casu. Kusy se dal nedeli a jdou porad ROVNE k vezi.
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


func _closer(a: Pilgrim, b: Pilgrim) -> bool:
	return a.pos.distance_squared_to(center) < b.pos.distance_squared_to(center)


func _prune() -> void:
	var keep: Array = []
	for p in pilgrims:
		if p.alive:
			keep.append(p)
	pilgrims = keep


func pilgrim_r() -> float:
	return unit_r * 0.05


func shot_speed() -> float:
	return field_r * SHOT_SPEED_FRAC


func shot_r() -> float:
	return unit_r * SHOT_R_FRAC


func shot_rim_r() -> float:
	return shot_r() * SHOT_RIM_FRAC


# ------------------------------------------------------------------ HLASKY

func _note(s: String) -> void:
	log.append(s)
	if log.size() > 40:
		log.pop_front()


func last_note() -> String:
	if log.is_empty():
		return ""
	return String(log[log.size() - 1])
