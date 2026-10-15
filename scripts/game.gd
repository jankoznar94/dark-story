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
#
# Oct 2026 - OPACNY SMER: "Rychlost pohybu všech nepřátel se zrychlí na rychlost
# 1.5x. Bude to nová výchozí hodnota. Nové 1.0x = staré 1.5x. Jsou teď příliš
# pomalí." 15 / 1,5 = 10 s. POZOR: okno na reakci je `dostrel * TRAVEL_S`, takze
# se zkratilo z 5,1 s na 3,4 s - kdo hybe timhle cislem, hybe obtiznosti a musi
# to merit (`tools/balance_sim.gd`).
const TRAVEL_S := 10.0
const BASE_HP := 20.0
# OBTIZNOST: kazdy dalsi LEVEL je o 22 % tuzsi (Jan schvalil 1,22; driv 1,15)
# a kazda dalsi vlna v levelu o 6 %. Driv to bylo 13 % za vlnu v nekonecne
# partii - s levelem a resetenym zlatem by to bylo nehratelne.
const LEVEL_HP := 1.40
# Vlna v ramci levelu uz zveda obtiznost jen NECITELNE (1,06 misto 1,15):
# deset vln po 1,06 da za level stejny rust jako pet vln po 1,15, takze delsi
# level neznamena tezsi hru, jen vic krokku. Kdo hybe poctem vln, musi
# premerit `tools/balance_sim.gd`.
const WAVE_HP := 1.06
const START_GOLD := 150
const BUILD_TIME := 5.0
# VELIKOST VLNY (Oct 2026). Jan: "Počet nepřátel v jednotlivých vlnách bude
# obecně vyšší. V prvních levelech bude začínat třeba na 15. Ve vyšších to budou
# klidně desítky až stovky. Samozřejmě musí chodit v takovém tempu a pořadí, aby
# bylo možné je zabít."
#
# JSOU TO DVE CISLA, NE JEDNO: tabulka je pocet poutniku v 1.-10. vlne PRVNIHO
# levelu a kazdy dalsi level ji NASOBI (`WAVE_SIZE_PER_LEVEL`). Driv se k tabulce
# pricitaval jeden poutnik za level, takze se stropu (24) dosahlo uz ve tretim
# levelu a "vyssi levely" se v poctech vubec neprojevily. Nasobenim se z desítek
# stanou stovky.
const WAVE_SIZES := [15, 17, 19, 22, 25, 29, 33, 38, 44, 51]
const WAVE_SIZE_PER_LEVEL := 1.20
# STROP VELIKOSTI VLNY: hra je nekonecna, takze pocet musi nekam dojit - na 20.
# levelu by jinak chodily tisice poutniku a hra by se zadrhla.
const WAVE_SIZES_MAX := 400
# ODMENA ZA VLNU. S DESETI VLNAMI NA LEVEL se zlato za level ZDVOJNASOBILO
# (vic vln = vic zabiti i vic bonusu) a hra se tim stala lehci, i kdyz se
# obtiznost nemenila - zmereno simulatorem. Proto je bonus za vlnu mensi:
# soucet za level zustava zhruba tam, kde byl u peti vln.
const WAVE_BONUS := 10
const WAVE_BONUS_PER_WAVE := 4
# ODMENA ZA VYHRANY LEVEL V BODECH (Jan schvalil): 25 + 5 * level.
const BODY_BASE := 25
const BODY_PER_LEVEL := 5
# KAZDY LEVEL MA DESET VLN. Jan (Oct 2026): "Kol v levelu by mělo být víc."
# Driv to bylo 3-5 vln podle poradi levelu; level tak byl kratky a barvy se
# musely odemykat uprostred neho. Deset vln je i Janovo starsi cislo ("Levely
# by měly mít jen 10 kol").
const WAVES_PER_LEVEL := 10
# KOLO SE POCITA VZDY PO DESETI VLNACH, takze "kolo" je proste poradi vlny pres
# cely pruchod hrou. Odtud se bere obtiznost (hp_for) i velikost vlny
# (wave_size) - jedno pocitadlo, ne dve.
const KOLO_PER_LEVEL := WAVES_PER_LEVEL

# DOCASNE UCPINKY: mezera mezi poutniky se v ramci levelu zkracuje - a u VELKE
# vlny se zkrati jeste vic, aby se cely zastup vysypal do `SPAWN_WAVE_S`. Bez
# toho by vlna o stovkach poutniku trvala desitky minut.
const SPAWN_GAP_START := 2.5
const SPAWN_GAP_MIN := 0.45
const SPAWN_GAP_PER_WAVE := 0.13
# CELKOVA DOBA VYSYPANI VLNY. Neni to kosmetika: pocet poutniku je ted v destikach
# az stovkach, takze pevna mezera by jednu vlnu natahla pres deset minut. Je to
# ZAROVEN HRANICE OBTIZNOSTI: cim kratsi vysypani, tim vic poutniku je na plose
# naraz a tim vic prace pro vez - hra se pak da dohrat jen s nakoupenymi upgrady.
const SPAWN_WAVE_S := 55.0

# STRELA. Rychlost je podil POLOMERU PLOCHY, polomer tecky podil MERITKA.
const SHOT_SPEED_FRAC := 0.80
# Oct 2026 (Jan: "Projektily uděláme o trošku menší."): 0,032 -> 0,026 meritka.
# Na telefonu je tecka ~4 px (driv 5) a porad ji drzi tmavy obrys pod sebou,
# proto se zmenseni netyka `SHOT_RIM_FRAC`. Test hlida, ze neklesne pod 3 px.
const SHOT_R_FRAC := 0.026
const SHOT_RIM_FRAC := 1.55
# POSKOZENI JEDNE RANY JE PARAMETR HRACE ("Ještě musíme přidat upgrade pro
# Attack damage", Jan Oct 2026) - hledej `shot_dmg()` v sekci PARAMETRY.
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


# ZRYCHLENI HRY (specialni permanentni upgrade "gs"). Upgrade je KLIC, ne
# hodnota: hra zacina VZDY na 1,0x a hrac si tempo prepina v bitve tlacitkem v
# pruhu (Jan, Oct 2026: "Výchozí vždy 1.0x. Upgrade jen otevírá možnost to
# přepínat."). Kdo si special nekoupil, nema co prepinat - tlacitko v pruhu
# vubec neni (`speed_options() == 1`).
var speed_step: int = 0


# KOLIK POLOH TEMPA MA HRAC ODEMCENYCH (1 = jen zakladni 1,0x).
func speed_options() -> int:
	return 1 + profile.perm_level("gs")


# PRAVE ZVOLENE TEMPO. Nikdy neni vyssi, nez co ma hrac koupene.
func time_scale() -> float:
	return Upgrades.speed_at(mini(speed_step, speed_options() - 1))


# PREPNUTI TEMPA (tlacitko v pruhu). Vraci true, kdyz se neco zmenilo -
# obrazovka se na to ptá, ne na to, "co se asi stalo".
func cycle_speed() -> bool:
	var n: int = speed_options()
	if n <= 1:
		return false
	speed_step = (speed_step + 1) % n
	# HLASKA: hrac ma videt, co si prave zapnul. Cislo je i na tlacitku, ale
	# hlaska rekne, ze se zmenil CAS CELE HRY (pohyb, kadence, vsechno).
	_note("Tempo hry: %s." % Upgrades.value_text("gs", speed_step, 0))
	return true


# KADENCE VEZE (rany za sekundu). Parametr je INTERVAL, takze se prepocitava.
# Podlaha je stejna jako v tabulce (`Upgrades.MIN_INTERVAL`) - kadence je cas
# a nula by delila nulou.
func rate() -> float:
	return 1.0 / maxf(Upgrades.MIN_INTERVAL, val("as"))


func range_frac() -> float:
	return val("ar")


# POSKOZENI JEDNE RANY ("Attack damage"). Zaklad 10 je v `Upgrades.STATS` pod
# id "ad" - zadna druha konstanta, ktera by o upgradu nevedela.
func shot_dmg() -> float:
	return maxf(1.0, val("ad"))


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
	return WAVES_PER_LEVEL


# VELIKOST VLNY. Bere se z VLNY V LEVELU (patnact az padesat poutniku v prvnim
# levelu) a kazdy dalsi LEVEL ji NASOBI - viz `WAVE_SIZE_PER_LEVEL`. Strop drzi
# nekonecnou partii hratelnou.
func wave_size(w: int, lv: int) -> int:
	var base: int = int(WAVE_SIZES[clampi(w, 1, WAVE_SIZES.size()) - 1])
	var grown: float = float(base) * pow(WAVE_SIZE_PER_LEVEL, float(maxi(0, lv - 1)))
	return clampi(int(round(grown)), 1, WAVE_SIZES_MAX)


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
	# TEMPO ZACINA VZDY NA 1,0x (Jan, Oct 2026: "Výchozí vždy 1.0x."). Upgrade
	# jen otevira moznost si ho v bitve prepnout - hrac si ma kazdou partii
	# zvolit, jak rychle ji chce hrat.
	speed_step = 0
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
#
# BODY SE DAVAJI JEN ZA NOVY LEVEL (Jan, Oct 2026: "Abych se mohl vrátit i k
# hotovým."). Kdo si vyhrany level zahraje znovu, nedostane nic - jinak by
# stacilo opakovat prvni level a body by se jen sypaly.
func _level_won() -> void:
	phase = "won"
	var first: bool = level > profile.best
	body_earned = 0
	if first:
		body_earned = BODY_BASE + BODY_PER_LEVEL * level
		profile.add_body(body_earned)
	profile.clear_level(level)
	if first:
		_note("Level %d vyhrán — %d bodů do menu." % [level, body_earned])
	else:
		_note("Level %d vyhrán znovu — body se dávají jen za nový level." % level)


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
# DOCASNE KROKY NEJSOU SHORA OMEZENE (Jan, Oct 2026): jedinym stropem je zlato
# hrace, proto se ptáme na cenu, ne na "kolik jich jeste zbývá".
func buy_temp(id: String) -> bool:
	var have: int = temp_level(id)
	if Upgrades.temp_is_maxed(id, have):
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


# ------------------------------------------------------------------ PAUZA

# Pauza je stav HRY, ne obrazovky: krok se ji ptá (`step`), takze ji nemuze
# obejit nikdo, kdo hru rozjede. Obrazovka ji jen prepina a pod pauzou
# nenecha desku reagovat.
func toggle_pause() -> void:
	paused = not paused


func is_paused() -> bool:
	return paused


# ------------------------------------------------------------------ KROK HRY

func step(dt: float) -> void:
	if is_over() or paused:
		return
	# ZRYCHLENI HRY: nasobi se CELY krok, takze se zrychli vsechno, co je na
	# case (pohyb, kadence, let strely, jed, led, regenerace, casy vln).
	dt *= time_scale()
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


# MEZERA MEZI POUTNIKY. Dve hranice: klesajici zaklad podle vlny a strop na
# CELKOVOU dobu vysypani - velka vlna se musi vysypat do `SPAWN_WAVE_S`, i kdyz
# by ji zaklad nechal pomalejsi.
func spawn_gap() -> float:
	var base: float = maxf(SPAWN_GAP_MIN, SPAWN_GAP_START - SPAWN_GAP_PER_WAVE * float(wave))
	var n: int = plan.size()
	if n > 1:
		base = minf(base, SPAWN_WAVE_S / float(n - 1))
	return maxf(SPAWN_GAP_MIN, base)


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
	var prev: Array = Hue.active_at(level - 1)
	for h in Hue.active_at(level):
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


# PALETA HRACE. Bere se z LEVELU, ne z kola: "Co level, to nová barva" (Jan,
# Oct 2026). Kdyz se paleta rozsiri, hra to rekne: nova barva znamena nove
# pravidlo a ticha zmena by nechala hrace hledat, proc se neco deje jinak.
func refresh_palette() -> void:
	var before: int = palette.size()
	palette = Hue.palette_at(level)
	# VEZ SI PALETU BER Z HRY, ne naopak: tlacitka dole kresli `game_view` z
	# `game.palette`, takze kdyby si vez drzela vlastni kopii, hrac by videl
	# jednu paletu a `Tower.set_hue` by se rozhodoval podle druhe.
	tower.palette = palette
	if not palette.has(tower.hue) and not palette.is_empty():
		tower.hue = int(palette[0])
	if before > 0 and palette.size() > before:
		for h in palette:
			if not Hue.palette_at(level - 1).has(h):
				_note("Přibyla barva: %s. %s" % [Hue.name_of(h), _behaviour_hint(h)])


func spawn_pool() -> Array:
	return Hue.active_at(level)


func select_hue(h: int) -> bool:
	return tower.set_hue(h)


# --------------------------------------------------------------- VSTUP POUTNIKU

func wave_plan(n: int) -> Array:
	var total: int = wave_size(wave, level)
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
#
# NEVIDITELNA FIALOVA JE VSAK IMUNNI VUCI VSEMU (Jan, Oct 2026: "Fialoví
# nepřátelé teď po prvním zásahu sice zmizí, ale po objevení automaticky samo
# zemřou. Aniž by do nich věž znovu střílela."). Kdyz je poutnik pro vez
# neviditelny, nesmi ho zabít ani jed: byl to prave jed, ktery tise (bez
# projektilu) dokoncil prvni zásah presne ve chvili, kdy se poutnik znovu
# objevil - hrac videl "umrela sama". Zmizeni je TIM ZA NEPRITELNY, co ma
# znamenat: dokud je duch, neda se mu ublizit.
func _advance_effects(dt: float) -> void:
	for p in pilgrims:
		if not p.alive:
			continue
		if p.ice_left > 0.0:
			p.ice_left = maxf(0.0, p.ice_left - dt)
		if p.poison_left > 0.0:
			p.poison_left = maxf(0.0, p.poison_left - dt)
			if p.targetable():
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

# ------------------------------------------------------------------ ZVUKOVE UDALOSTI
#
# HRA NEREKNE "prehraj zvuk" (nevi, jestli je vubec nejaky prehravac, a v
# testech by nic nehrala): zapisuje, CO se stalo. Obrazovka si z toho zvuky
# udela (`Game.take_events`) - a je to zaroven jedine misto, kde se da overit,
# ze vystrel opravdu vystrelil a dopad opravdu ubral.
#
# STROP: zvuk je doplnek, ne zaznam. Kdo hru kroka bez obrazovky (simulátor),
# by si jinak pamatoval tisice udalosti.
const MAX_EVENTS := 24
var events: Array = []


func _event(kind: String) -> void:
	if events.size() >= MAX_EVENTS:
		events.remove_at(0)
	events.append(kind)


# VYBRANI UDALOSTI = JEJICH SMAZANI. Kdo je precte bez vybrani, prehraje je
# znovu (a zvuk by se opakoval).
func take_events() -> Array:
	var out: Array = events
	events = []
	return out


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
	var dmg: float = shot_dmg()
	if rng.randf() < crit_chance():
		dmg *= crit_dmg()
	shots.append(_make_shot(p, dmg, ricochet(), [], muzzle(p)))
	_event("shot")


# USTI HLAVNE. Strela vychazi z OKRAJE veze, ne ze stredu - hrac vidi, kterym
# smerem leti.
func muzzle(p: Pilgrim) -> Vector2:
	return center + (p.pos - center).normalized() * tower_r


# STRELA. `bounce` = kolik odrazu jeste zbyva, `hit` = na koho uz se v tomto
# odrazu dostalo (kazdy poutnik nejvyse jednou), `from` = ODKUD leti.
#
# `from` JE PARAMETR, ne pocitana hodnota: hlavni strela vychazi z veze, ale
# ODRAZ vychazi z TELA predchozi obeti. Kdyz si odraz spocital "odkud" sam
# (`from = p.pos`, kde `p` je NOVY cil), strela vznikla uz VE svem cili -
# v tom samem snimku doletela, ubrala zivoty a nebylo ji videt. Presne to Jan
# nasel: "Ricochet ... teď uděluje poškození, ale není nic vidět."
#
# BARVA SE DRZI PRI STRELE, ne u veze: hrac muze behem letu prebit vez na
# jinou barvu a tecka ve vzduchu nesmi zmenit barvu - leti porad ta, ktera
# vystrelila (a proto i po prepnuti doleti, viz `_advance_shots`).
func _make_shot(p: Pilgrim, dmg: float, bounce: int, hit: Array, from: Vector2) -> Dictionary:
	var already: Array = hit.duplicate()
	already.append(p)
	shots_fired += 1
	return {"pos": from, "target": p, "dmg": dmg, "bounce": bounce,
		"hit": already, "hue": tower.hue}


# LET STRELY A DOPAD. Poskozeni udeli az ve chvili, kdy do cile doleti.
#
# JEDNOU VYSTRELENA STRELA DOZENE SVUJ CIL (Jan, Oct 2026: "Když už věž
# vystřelí, tak musí projektil doletět do cíle a udělit poškození."). Driv
# strela zanikla, jakmile hrac prepl barvu veze - hrac videl, jak projektil
# zmizi a neubral nic. Strela proto zanikne JEN s MRTVYM cilem; zmena barvy
# veze ji nezastavi.
#
# VYJIMKA JE FIALOVA PO ZNEVIDITELNENI (Jan, Oct 2026): "Když zmizí, projektil
# zkrátka mine. Doletí na místo impaktu, zmizí a neudělí poškození." Neni to
# tedy "zanikne ve vzduchu" - doleti az na misto dopadu a tam zmizi bez rany
# (a bez odrazu). Kdo hleda pravidlo "co se stane s rozletlou strelou", najde
# tady obe vetve: `p.alive` (cil umrel) a `p.targetable()` (fialova zmizela).
#
# ODRAZ VZNIKA UVNITR TOHOTO PRUCHODU, takze se nove strely sbiraji vedle
# (`born`) a pripoji se az na konci. Kdyby se spolehlo na to, ze je smycka jeste
# stihne projit, prisly by o ne `shots = keep` a odraz by nebylo videt.
func _advance_shots(dt: float) -> void:
	var keep: Array = []
	var born: Array = []
	for s in shots:
		var p: Pilgrim = s["target"]
		if not p.alive:
			continue
		var pos: Vector2 = s["pos"]
		var d: Vector2 = p.pos - pos
		var step_len: float = shot_speed() * dt
		if d.length() <= step_len + shot_r():
			if p.targetable():
				_damage(p, float(s["dmg"]))
				var next: Dictionary = _ricochet_from(p, s)
				if not next.is_empty():
					born.append(next)
			# NETREFENO (fialova je v duchovem stavu): strela tady KONCI -
			# nema poskozeni, nema odraz a nikam dal neleti.
			continue
		s["pos"] = pos + d.normalized() * step_len
		keep.append(s)
	for s in born:
		keep.append(s)
	shots = keep


# ODRAZ (RICOCHET). Strela se odrazi na dalsiho poutnika STEJNE BARVY, na
# ktereho se v tomto odrazu jeste nedostalo - a to i kdyz uz je mimo dostrel
# (je to odraz, ne zamereni). Kazdy poutnik dostane nejvyce jednu ranu.
#
# NEVIDITELNA FIALOVA SE NESMI VYBRAT: duch dostane od odrazu strelu, kterou
# hrac nikdy nevidel vystrelit (a kdyby se stihl objevit, dostal by ránu "od
# nikud"). Plati stejne pravidlo jako u vseho ostatniho: dokud je duch, neda se
# mu ublizit.
#
# Vraci NOVOU strelu (nebo prazdny slovnik), aby si ji `_advance_shots` mohl
# pridat do sveho seznamu - do `shots` se sahat nesmi, prave se pres ni jde.
func _ricochet_from(p: Pilgrim, s: Dictionary) -> Dictionary:
	var bounce: int = int(s["bounce"])
	if bounce <= 0:
		return {}
	var hit: Array = s["hit"]
	var best: Pilgrim = null
	var best_d: float = RICOCHET_RANGE_FRAC * field_r
	for q in pilgrims:
		if not q.alive or not q.targetable() or q.hue != p.hue or hit.has(q):
			continue
		var d: float = q.pos.distance_to(p.pos)
		if d <= best_d:
			best_d = d
			best = q
	if best == null:
		return {}
	return _make_shot(best, float(s["dmg"]), bounce - 1, hit, p.pos)


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
		# JED SE POCITA Z AKTUALNIHO POSKOZENI RANY, ne z mrtve zakladni
		# konstanty: upgrade poskozeni tak posili i jed a zustava to "20 % z
		# rany", jak to hrac v panelu vidi.
		p.poison_dps = shot_dmg() * poison_frac()
	if ice_frac() > 0.0:
		p.ice_left = ICE_S
		p.ice_frac = ice_frac()
	# ZVUK ZASahu patri SEM (dopad strely), ne do `_hurt`: jed skodi pres
	# `_hurt` kazdy snimek a hrac by poslouchal tikani jedu misto ran.
	_event("hit")
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
	_event("kill")
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
