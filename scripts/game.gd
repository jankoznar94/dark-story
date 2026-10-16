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
#   * SPECIÁL (multishot, odraz, jed, led) je jen permanentni,
#   * VEZ STRIli LASEREM, ne projektily (Jan, Oct 2026: "Vrátíme se k laseru
#     místo projektilů... Poškození bude probíhat plynule"). Dostrel je konec
#     paprsku, poskozeni tece kazdy snimek (`laser_dps`) a odraz paprsek
#     rozvetvi na dalsi poutniky (`odraz`), kazdy dalsi za mene,
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
# pomalí." 15 / 1,5 = 10 s.
#
# Oct 2026 (Jan): "Všechny nepřátele o 15 % zpomalíme. Ať to vytvoří pocit ještě
# větší vzdálenosti a rozlohy." 10 / 0,85 = 11,8 s. POZOR: okno na reakci je
# `dostrel * TRAVEL_S`, takze s pomalejsi chuzi roste i okno na reakci - kdo
# hybe timhle cislem, hybe obtiznosti a musi to merit (`tools/balance_sim.gd`).
const TRAVEL_S := 11.8
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
# ZLATO ROSTE S OBTIZNOSTI. Zivoty poutniku rostou 1,40x za level; kdyby zlato
# stalo na miste, hrac by za stejne penize kupoval porad slabsi vez a hra by se
# zlomila - zmereno simulatorem (`tools/balance_sim.gd --order=damage`): hrac,
# ktery sype VSECHNO do poskozeni, padl na 6. levelu v prvni vlne, protoze
# permanentni zebricky uz mel vykoupené a zlato se mu na kazdem levelu vratilo
# na 150. Zlato za zabiti, za vlnu i na startu levelu proto roste stejnym
# krokem jako obtiznost.
const GOLD_LEVEL := 1.30
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

# LASER. Neni to strela, co leti - je to paprsek, ktery sviti, dokud je cil
# v dostrelu a vez ho vidi. Sirka je podil MERITKA a s kazdym odrazem se
# zužuje, aby hrac na prvni pohled videl, ktery cil je hlavni.
const BEAM_W_FRAC := 0.015
const BEAM_TAPER := 0.72
# PRSTENEC KOLEM POUTNIKA. Paprsek se na nem zastavi - konci na jeho PLASHTI,
# ne ve stredu tela (Jan, Oct 2026: "Laser končí ve středu nepřítele, s hranatým
# zakončením. Stejně tak začíná i odraz. Je to jak dva obdélníky vedle sebe.
# Možná by bylo dobré, kdyby každý nepřítel byl v malém kruhu (své barvy). Laser
# by mohl končit (a odraz začínat) na plášti toho kruhu."). Je to podil polomeru
# kresby poutnika; kruh je i VIDET (kresli ho obrazovka), aby hrac videl, kde
# paprsek konci, a aby to nebyla jen neviditelna hranice ve vzduchu.
#
# Oct 2026 (Jan): "Udělejme větší vnitřní padding. Ať kruh není nalepený přímo
# na tvář uvnitř." Pri 1,30 sel prstenec tesne kolem tvaru (spicka trojuhelniku
# je v 1,00 r, brisko kapky v 1,15 r) - na telefonu zbyla mezera 1-4 px a kruh
# vypadal, jako by obkresloval oblicej. Pri 1,70 je mezera 4-6 px podle tvaru:
# poutnik je v kruhu, ne v jeho obrysu. Paprsek tim konci o kousek dal od tela.
# Zmereno na snimku 390x844 (`zily2_ring_probe.py`): tvár 11 px, prstenec 22 px.
const RING_FRAC := 1.70
# VELIKOST POUTNIKA je NASOBEK ZAKLADNI velikosti kresby (`ScreenLayout.pilgrim_r`).
# Puvodne 0,85 (Jan: "Všechny nepřátele o 15 % zmenšíme"). Od Oct 2026 je poutnik
# PUNTIK S PISMENY a Jan k tomu rekl: "Všichni budou mít tvar puntíku. V něm budou
# mít iniciály barvy nebo kombinace barev. Zbytek zůstává. Takže musí být o něco
# větší, aby to bylo čitelné." Proto 1,05: do prumeru 16 px se vejdou dve pismena.
# Nese si ji poutnik (ne rozvrzeni), takze se zvetsi i jeho prstenec (= HP bar) -
# vetsi vnitrni padding z `RING_FRAC` zustava. Hlida to `test_layout`
# (`_test_pilgrim_stays_readable`).
const PILGRIM_SIZE := 1.05
# POSKOZENI LASERU (za sekundu) JE PARAMETR HRACE ("Ještě musíme přidat upgrade
# pro Attack damage", Jan Oct 2026) - hledej `laser_dps()` v sekci PARAMETRY.
# JED A LED: jak dlouho ucinek drzi. Podil (20/35/50 %) je v tabulce upgradu.
const POISON_S := 3.0
# JAK DLOUHO DRZI CHLAD. Jan (Oct 2026): "Chill effect by měl trvat třeba 3s po
# ukončení dmg." Je to i doba, po kterou je poutnik ZPOMALENY - stav je jeden
# (`ice_left`), takze se nerozejde to, co hrac vidi, od toho, co se deje.
const ICE_S := 3.0
# ODRAZ: jak daleko od sebe mohou byt dva poutnici, aby paprsek preskocil.
# Na kazdeho se v jednom paprsku dostane nejvyce jednou (Jan: "vždy jen jeden
# odraz za každého unikátního nepřítele").
const ODRAZ_RANGE_FRAC := 0.55
# DVOJTAP NA PALETE: dva tapy na stejnou barvu do teto doby = michani (druhy tap
# se primichava do barvy zvolene pred tim). Je to horni hranice pro "dva tapy za
# sebou" - delsi prodleva znamena dva obycejne tapy.
const DOUBLE_TAP_S := 0.30

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

# HERNI HODINY: bezi, kdykoli bezi krok hry (`step`). Meri se jimi dvojtap na
# palete - kdyby se meril hodinami systemu, testy by nebyly deterministicke.
var clock: float = 0.0
# DVOJTAP NA PALETE: dva tapy na stejnou barvu do `DOUBLE_TAP_S` = michani.
var last_tap_hue: int = -1
var last_tap_t: float = -10.0
# BARVA ZVOLENA PRED POSLEDNIM TAPEM. Do ni se druhy tap primichava.
var before_hue: int = -1

var pilgrims: Array = []
# ZAMERENE CILE (multishot): vez jich drzi tolik, kolik ma koupeno.
var locks: Array = []
# PAPRSKY PRO OBRAZOVKU: [{from, target, hop}]. Hra je pocita kazdy snimek
# znovu (cile se hybou), obrazovka z nich jen kresli - nic si nepocita sama.
var beams: Array = []
# KOLIK PAPRSKU SE ZA CELOU BITVU ROZSVITILO. Neni to kosmetika: je to jedine
# merko toho, ze vez opravdu "vystrelila" (kadence uz neexistuje).
var beams_lit: int = 0
# KRITICKY ZASAH JAKO ZABLESK. U spojiteho paprsku se neda losovat kazdy
# snimek - hrac by videl skakat cisla, ktera nikde nejsou. Sance se proto
# prevede na PODIL CASU: paprsek blika ostrym svetlem kratce po sobe
# (`CRIT_FLASH_S`) a behem zabliknuti bere `crit_dmg()` nasobek. Stredni
# poskozeni je presne stejne jako driv (`laser_dps()`), ale hrac ho VIDI -
# a kdyz si koupi vetsi sanci, blika to casteji, ne "vic do prazdna".
const CRIT_FLASH_S := 0.22
# Kolik jeste bude zablesk svitit / kolik se ma cekat na dalsi.
var crit_left: float = 0.0
var crit_wait: float = 0.0
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


func range_frac() -> float:
	return val("ar")


# POSKOZENI LASERU ZA SEKUNDU. Zaklad 10 je v `Upgrades.STATS` pod id "ad" -
# zadna druha konstanta, ktera by o upgradu nevedela.
#
# JSOU TO TRI OSY, KAZDA Z TABULKY UPGRADU:
#   * "ad" - pevne poskozeni (start + krok za kazdou koupenou uroven),
#   * "ap" - SÍLA PAPRSKU, nasobici osa (1,0x - a v bitve za zlato dal),
#   * kritika - nasobic prumeru.
#
# KRITIKA SE ROZPOCITAVA DO PRUMERU: u plynuleho paprsku nema smysl losovat
# kazdy snimek (a hrac by videl skakat cisla, ktera nikde nejsou). Stredni
# hodnota je stejna, jako kdyby se losovalo: dps * (1 + sance * (nasobek - 1)).
# TO CISLO JE "CO HRAC DOSTANE V PRUMERU" - okamzity vykon behem zablesku je
# `laser_now_dps()` a obrazovka ho kresli svetlejsim paprskem.
func laser_base() -> float:
	return maxf(1.0, val("ad")) * maxf(0.05, val("ap"))


func laser_dps() -> float:
	return laser_base() * (1.0 + crit_chance() * (crit_dmg() - 1.0))


# SVITI PRAVE TED ZABLESK KRITIKY?
func crit_active() -> bool:
	return crit_left > 0.0


# OKAMZITY VYKON PAPRSKU (behem zablesku nasobek kritiky). Hra ubira TOHLE,
# obrazovka to i tak kresli - kdyby hra brala prumer a obrazek ukazoval
# zablesk, hrac by videl neco jineho, nez co se deje.
func laser_now_dps() -> float:
	return laser_base() * (crit_dmg() if crit_active() else 1.0)


# ZABLESK KRITIKY. Sance na krit = podil casu, kdy paprsek sviti ostře:
# zablesk trva `CRIT_FLASH_S` a pauza mezi zablesky je `CRIT_FLASH_S * (1-sance)/sance`.
# Soucet je porad presne 1 - proto se stredni poskozeni nezmeni, jen je videt.
# Sance >= 1 znamena, ze paprsek sviti ostře porad (a dalsi kroky uz nic nepridaji).
func _tick_crit(dt: float) -> void:
	var cc: float = clampf(crit_chance(), 0.0, 1.0)
	if cc <= 0.0:
		crit_left = 0.0
		crit_wait = 0.0
		return
	if crit_left > 0.0:
		crit_left = maxf(0.0, crit_left - dt)
		if crit_left <= 0.0:
			crit_wait = CRIT_FLASH_S * (1.0 - cc) / cc
		return
	crit_wait = maxf(0.0, crit_wait - dt)
	if crit_wait <= 0.0:
		crit_left = CRIT_FLASH_S


# ODRAZ: kolik skoku paprsek udela a kolik si kazdy jeste odnese. Obe cisla
# jsou v JEDNE polozce tabulky (`Upgrades.chain_of`), aby se nedala koupit
# polovina upgradu.
func odraz() -> int:
	return int(round(_chain_pair().x))


func odraz_strength() -> float:
	return clampf(_chain_pair().y, 0.0, 1.0)


func _chain_pair() -> Vector2:
	return Upgrades.chain_of("rc", profile.perm_level("rc"), int(temp.get("rc", 0)))


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
	beams = []
	beams_lit = 0
	crit_left = 0.0
	crit_wait = 0.0
	# TEMPO ZACINA VZDY NA 1,0x (Jan, Oct 2026: "Výchozí vždy 1.0x."). Upgrade
	# jen otevira moznost si ho v bitve prepnout - hrac si ma kazdou partii
	# zvolit, jak rychle ji chce hrat.
	speed_step = 0
	max_hp = val("hp")
	hp = max_hp
	gold = int(round(float(START_GOLD) * gold_mult())) + int(round(val("gl")))
	plan = []
	spawned = 0
	refresh_palette()
	_note("Level %d — %d vln." % [level, waves_in_level()])


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
	# HERNI HODINY. Bezi JEN v kroku hry (ne kdyz je pauza nebo konec), takze se
	# dvojtap meri hernim casem - testy pak zustavaji deterministicke.
	clock += dt
	# ZRYCHLENI HRY: nasobi se CELY krok, takze se zrychli vsechno, co je na
	# case (pohyb, kadence, let strely, jed, led, regenerace, casy vln).
	dt *= time_scale()
	_phase_step(dt)
	_regen(dt)
	_move(dt)
	_aim()
	_tick_crit(dt)
	_laser(dt)
	_advance_effects(dt)
	_prune()


# POSUNOUT JEN HODINY. Pro testy dvojtapu: hrac v pauze (nebo v testu) potrebuje
# nechat cas bezet, aby druhy tap uz nebyl dvojtap.
func tick(dt: float) -> void:
	clock += dt


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
	gold += int(round(float(WAVE_BONUS + WAVE_BONUS_PER_WAVE * wave) * gold_mult())) + int(round(val("gw")))
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
			return "Mění každých pět vteřin podobu — bere si schopnost, rychlost i životy té barvy. Na stříbrnou se už nevrátí."
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
	# SMES: kdyby nekterá z obou barev z palety vypadla (nemeni se to, ale kdo
	# bude menit pravidla odemykani, at to nerozbije), vez zustane na te, ktera
	# v palete je - nikdy nesmi mirrit barvou, kterou hrac nema.
	if tower.hues.size() > 1:
		for h in tower.hues:
			if not palette.has(h):
				tower.hue = int(palette[0]) if not palette.is_empty() else Hue.RED
				break
	if before > 0 and palette.size() > before:
		for h in palette:
			if not Hue.palette_at(level - 1).has(h):
				_note("Přibyla barva: %s. %s" % [Hue.name_of(h), _behaviour_hint(h)])


func spawn_pool() -> Array:
	return Hue.active_at(level)


func select_hue(h: int) -> bool:
	return tower.set_hue(h)


# --------------------------------------------------------------- MICHANI BAREV
#
# Jan (Oct 2026): "Jeden obyčejný tap = výběr jednoduché barvy. Dva tapy za
# sebou na stejnou barvu = promíchání barvy do již zvolené. Jakmile je navolena
# kombinace, tak pro změnu musí hráč vždy udělat prvně jeden tap na jinou barvu
# a tím výběr resetuje. Pak dvojtapem vytvoří další kombinaci."
#
# Je to STAVOVY AUTOMAT HRY (ne obrazovky) a meri se HERNIM casem (`clock`), aby
# se dalo testovat bez prohlizece. Prvni tap se projevi OKAMZITE (vez na chvili
# prebije jednoduchou barvu) - cekat 0,3 s, nez se paleta ozve, by pusobilo mrtve.
#
# Vraci "mix" (promichano), "single" (obycejny tap) nebo "none" (barva neni
# v palete) - obrazovka si podle toho hraje zvuk.
func tap_hue(h: int) -> String:
	if not palette.has(h):
		return "none"
	var dbl: bool = (h == last_tap_hue) and (clock - last_tap_t) <= DOUBLE_TAP_S
	var was: int = before_hue
	before_hue = tower.hue
	last_tap_hue = h
	last_tap_t = clock
	if dbl and was >= 0 and was != h and Hue.mix_unlocked(level) and tower.set_pair(was, h):
		_note("Barvy se míchají: %s (%s)." % [Hue.name_of(tower.mix()), Hue.letter_of(tower.mix())])
		return "mix"
	tower.set_hue(h)
	return "single"


# --------------------------------------------------------------- VSTUP POUTNIKU

# KOMBINOVANI POUTNICI. Jan: "Jejich výskyt nesmí být vysoký, jinak by to hráč
# nemohl zvládnout." Do vlny jich jde nejvyce MIX_MAX a jen kdyz uz je michani
# odemcene (a existuje smes, kterou hrac dokaze zasahnout - potrebuje na ni obe
# barvy ve vezi).
const MIX_SHARE := 0.10
const MIX_MAX := 2


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
	# SMES MISTO JEDNODUCHE BARVY. Az PO zamichani, aby se michalo do cele vlny
	# (a aby se smes neobjevila vzdy na stejnem miste poradi).
	var mixes: Array = Hue.mix_pool_at(level)
	var used: int = 0
	for i in range(out.size()):
		if mixes.is_empty() or used >= MIX_MAX:
			break
		if rng.randf() < MIX_SHARE:
			out[i] = int(mixes[rng.randi_range(0, mixes.size() - 1)])
			used += 1
	return out


# NASOBEK ZLATA PRO TENTO LEVEL. Jedno misto, odkud se bere - kdyby si to
# kazde misto pocitalo samo, jedna cast hry by rostla a druha ne.
func gold_mult() -> float:
	return pow(GOLD_LEVEL, float(maxi(0, level - 1)))


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
	p.behaviours = Hue.behaviours_of(hue)
	# VELIKOST KRESBY (Jan: o 15 % mensi nez driv) - viz `PILGRIM_SIZE`.
	# Rozpadly kus modre ji dale zmensi pres `Hue.SPLIT_SIZE`.
	p.size = PILGRIM_SIZE
	p.pos = center + Vector2(cos(a), sin(a)) * field_r
	p.dir = (center - p.pos).normalized()
	p.max_hp = hp_for(kolo(), wave, hue)
	p.hp = p.max_hp
	p.speed = pilgrim_speed() * Hue.speed_mult(hue)
	if p.behaviour == Hue.B_SHIFT:
		p.shift_left = Hue.SHIFT_S
	# MENICI PODSTATA JE ZVLAST (viz `Pilgrim.shifting`): `behaviour` se pri
	# zmene podoby prepisuje schopnosti nove barvy, takze "je to menic" se z nej
	# neda precist.
	p.shifting = (p.behaviour == Hue.B_SHIFT)
	# KOMBINOVANY POUTNIK: hrac musi vedet, PROC ho nedokaze zasahnout. Bez
	# poznamky by to vypadalo jako chyba hry (plan, ukol 6 krok 3).
	if Hue.is_mix(hue):
		_note("%s - potřebuješ obě barvy!" % Hue.name_of(hue))
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
	if p.has_behaviour(Hue.B_REGEN):
		p.hp = minf(p.max_hp, p.hp + p.max_hp * Hue.REGEN_FRAC * dt)
	if p.ghost_left > 0.0:
		p.ghost_left = maxf(0.0, p.ghost_left - dt)
	if p.shifting:
		p.shift_left -= dt
		if p.shift_left <= 0.0:
			p.shift_left = Hue.SHIFT_S
			_shift(p)


# STRIBRNA MENI PODOBU (Jan, Oct 2026): "Nově budou měnit po 5s. A se změnou
# podoby budou přebírat i výhody jednotlivých barev. Zelená = léčení, žlutá =
# rychlost, modrá = při smrti se rozdělí, fialová = po první ráně zmizí, červená
# = vysoká odolnost. Měly by se měnit i životy. Hra by měla přepočítávat podle
# procentuální hodnoty."
#
# Forma se bere CELA: nova barva da poutnikovi svou schopnost, svou rychlost
# i SVUJ ZIVOTNI POOL. Zivoty se NEPRICITAJI ani neprepisuji - prenasi se
# PROCENTO: `hp_frac()` pred zmenou se nasadi na pool nove barvy. Proto ma
# stribrna v kazde podobe jinak zivotu a cervena je vzdycky ta tlustsi (2,2x).
func _shift(p: Pilgrim) -> void:
	var frac: float = p.hp_frac()
	p.hue = _random_other_hue(p.hue)
	p.behaviour = Hue.behaviour_of(p.hue)
	p.behaviours = Hue.behaviours_of(p.hue)
	p.max_hp = hp_for(kolo(), wave, p.hue)
	p.hp = maxf(1.0, p.max_hp * frac)
	# RYCHLOST JE VYHODA ZLUTE, takze nova podoba znamena i novou chuzi.
	p.speed = pilgrim_speed() * Hue.speed_mult(p.hue)
	# NEVIDITELNOST KONCI SE ZMENOU PODOBY (Jan: "pokud bude neviditelný v době,
	# kdy má změnit podobu, tak o neviditelnost v rámci změny přijde"). Nove
	# podoby se take netyka zasah z podoby predchozi - fialova zmizi az po SVEM
	# prvnim zasahu, ne po tom, ktery dostala jako neco jineho.
	p.ghost_left = 0.0
	p.was_hit = false


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


# SVAZEK DRZI CIL, DOKUD JEJ VEZ VIDI A JE V DOSTRELU. Pocet cilu zaraz je
# upgradovatelny parametr (multishot) a KAZDY cil ma svuj paprsek (a svuj
# retez odrazu) - "vic cilu" tedy od teď znamena vic paprsku naraz.
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


# ------------------------------------------------------------------- LASER
#
# Jan (Oct 2026): "Vrátíme se k laseru místo projektilů. Tím pádem zrušíme
# úplně Attack speed upgrady. Poškození bude probíhat plynule a čím vyšší bude
# mít věž dmg, tím rychleji to logicky bude nepřítele zabíjet. Barva laseru
# bude podle barvy věže. RICOHET přejmenujeme na Odraz a bude se takhle laser
# šířit na další nepřátele, podobně jako ricochet, ale bez projektilů. A každý
# odraz bude dávat menší poškození. S levelem upgradu se bude zvyšovat počet
# odrazů a bude snižovat penalizace za odraz."
#
# Z TOHO PLYNE CELY MODEL - a je to zamerne JEDNA funkce, proto:
#   * zadny projektil, zadna kadence a zadny "swing timer": dokud vez na
#     neco vidi, paprsek sviti a `laser_dps()` tece kazdy snimek,
#   * barva paprsku je BARVA VEZE (kresli ji obrazovka z `beams`),
#   * odraz je druhy, treti... cil paprsku se snizujicim se poskozenim,
#   * "vystreleno = doleti" uz neexistuje - neni co doletovat. Paprsek proste
#     prestane svitit ve chvili, kdy cil zmizi z dostrelu nebo zustane sam
#     (`tower.sees`), a to same plati pro fialovou v duchovem stavu.
func _laser(dt: float) -> void:
	beams = []
	for p in pilgrims:
		p.burning_now = false
	var r: float = range_px()
	var dps: float = laser_now_dps()
	var strength: float = odraz_strength()
	var crit: bool = crit_active()
	for p in locks:
		if not p.alive or not tower.sees(p) or not in_range(p, r):
			continue
		var chain: Array = _chain(p)
		# PAPRSEK ZACINA NA PLASHTI VEZE a konci na prstenci cile - ne na
		# stredu tela. Kdyz paprsek sviti pres poutnika (odraz na dalsi),
		# projde skrz nej: vstoupi na blizsi strane prstence a vystoupi na
		# te, ktera je bliz k dalsimu cili. Diky tomu na sebe segmenty
		# Presne navazuji a nikde neni "svar" (Jan: "Je to jak dva obdelniky
		# vedle sebe.").
		var from_pt: Vector2 = center + (chain[0].pos - center).normalized() * tower_r
		for i in range(chain.size()):
			var q: Pilgrim = chain[i]
			var rr: float = pilgrim_ring_r(q)
			var entry: Vector2 = q.pos - (q.pos - from_pt).normalized() * rr
			beams.append({"from": from_pt, "to": entry, "target": q, "hop": i,
				"crit": crit})
			_burn(q, dps * pow(strength, float(i)) * dt)
			if i + 1 < chain.size():
				var nxt: Pilgrim = chain[i + 1]
				var exit: Vector2 = q.pos + (nxt.pos - q.pos).normalized() * rr
				beams.append({"from": entry, "to": exit, "target": q, "hop": i,
					"crit": crit})
				from_pt = exit
	# `burning` = svitil paprsek na tohle poutnika i v PREDCHOZIM snimku.
	# Prelozi se az tady, kdyz je hotove cely paprsek - kdyby se to delalo za
	# pochodu, zvuk zazehnuti by se ozval u kazdeho odrazu zvlast.
	for p in pilgrims:
		p.burning = p.burning_now


# ODRAZ. Paprsek preskoci na nejblizsiho dalsiho poutnika, na ktereho se v tom
# samem paprsku jeste nedostalo - a to i mimo dostrel (je to odraz, ne
# zamereni). "Stejna barva" neni zvlast podminka: vez jinou barvu nevidi
# (`tower.sees`), takze by ji ani nezamirila.
func _chain(p: Pilgrim) -> Array:
	var out: Array = [p]
	var reach: float = ODRAZ_RANGE_FRAC * field_r
	var cur: Pilgrim = p
	for i in range(odraz()):
		var best: Pilgrim = null
		var best_d: float = reach
		for q in pilgrims:
			if not q.alive or not tower.sees(q) or out.has(q):
				continue
			var d: float = q.pos.distance_to(cur.pos)
			if d <= best_d:
				best_d = d
				best = q
		if best == null:
			break
		out.append(best)
		cur = best
	return out


# HORI CIL PAPRSKEM - vcetne jedn a ledu, ktere plati, dokud paprsek sviti.
# Odraz je porad zasah tou samou zbrani, takze si veze i jed (jen slabsi, proto
# `laser_dps` v sile, ne v poskozeni - jed se pocita z plne rany veze).
#
# ZVUK ZAZEHNUTI ("shot") PATRI SEM: paprsek, ktery sviti na cil pet sekund,
# nesmi pet sekund tikat. Hra si drzi `burning` a ozve se jen prechod
# "nesvitil -> sviti" (`beams_lit` je toho pocitadlo, testy si ho ctou).
func _burn(p: Pilgrim, amount: float) -> void:
	if not p.alive or amount <= 0.0:
		return
	p.burning_now = true
	if not p.burning:
		beams_lit += 1
		_event("shot")
	if poison_frac() > 0.0:
		p.poison_left = POISON_S
		p.poison_dps = laser_dps() * poison_frac()
	if ice_frac() > 0.0:
		p.ice_left = ICE_S
		p.ice_frac = ice_frac()
	_hurt(p, amount)


# ------------------------------------------------------------------ POSKOZENI

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
		if p.has_behaviour(Hue.B_VANISH):
			p.ghost_left = Hue.VANISH_S
	if p.hp <= 0.0:
		_kill(p)


func _kill(p: Pilgrim) -> void:
	p.alive = false
	_event("kill")
	gold += int(round(float(Hue.gold_of(p.hue)) * gold_mult())) + int(round(val("gk")))
	# MODRA: rozpadne se na dva mensi kusy. Hra se tim zhusti presne tam, kde
	# ma vez nejmene casu. Kusy se dal nedeli a jdou porad ROVNE k vezi.
	if p.has_behaviour(Hue.B_SPLIT) and p.can_split:
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


# POLOMER PRSTENCE, NA KTEREM PAPRSEK KONCI. Je to ta VIDITELNA kruzna hranice
# kolem poutnika (kresli ji obrazovka). Vetsi poutnik (rozpadly kus modre) ma
# vetsi i prstenec - jinak by mu paprsek koncil uvnitr tela.
func pilgrim_ring_r(p: Pilgrim) -> float:
	return pilgrim_r() * maxf(0.1, p.size) * RING_FRAC


# SIRKA PAPRSKU. S kazdym odrazem se zuzi, ale nikdy nezmizi - hrac musi
# videt i to, kam az odraz dosahl. Kresli to obrazovka, proto to hra jen
# pocita (a obrazovka si to nepocita sama).
func beam_w(hop: int) -> float:
	return unit_r * BEAM_W_FRAC * pow(BEAM_TAPER, float(maxi(0, hop)))


# ------------------------------------------------------------------ HLASKY

func _note(s: String) -> void:
	log.append(s)
	if log.size() > 40:
		log.pop_front()


func last_note() -> String:
	if log.is_empty():
		return ""
	return String(log[log.size() - 1])
