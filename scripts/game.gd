class_name Game
extends RefCounted

# CELA herni logika. Zadne kresleni, zadne nody, zadny Input.
# Diky tomu se da hra testovat headless a simulovat zrychlene.
#
# POSKOZENI DELAJ VEZE. Jan (Oct 2026): "Trochu se přiblížíme TD žánru tím,
# že budeme reálně stavět věže kolem tras, které budou útočit na procházející
# nepřátele." Vez stoji v PASU kolem cesty (1 bunka na kazdou stranu) a sama
# utoci na poutniky, kteri prochazeji v jejim ctvercovem dosahu 2 bunky.
# CESTA SAMA NEDAVA ZADNE POSKOZENI - to je budouci upgrade, ne dnesni hra.
#
# DVE VEZE VYPOCTU, na kterych stoji cela hra:
#   * vez v SEDEM pasu (neutralni usek, kmen) bere vsem presne 100 %,
#   * vez elementu X da vlastnimu zivlu 0 %, jeho protikladu 200 %
#     a zbylym dvema 50 %. Poslat poutnika na jeho vlastni usek je tedy
#     ZTRATA - projde bez skrabnuti, i kdyz tam vez stoji.
# Hrac prepina vyhybku pro kazdeho poutnika zvlast a jeho investice je vez
# v pasu. Investice ma cenu jen tehdy, kdyz na nej dokaze poutniky poslat -
# to je cele napeti hry.

const START_GOLD := 260
const START_LIVES := 12
const BASE_HP := 70.0
# RUST ZIVOTU ZA VLNU. Zmereno simulator obstiznosti
# (`tools/balance_sim.gd`, zakladni deska, hrac s PLNOU deskou vezi
# v jednom koridoru a dokonalym prepinanim vyhybek):
#   0,06 -> 25. vlna bez prusmyku, 0,12 -> taky, 0,15 -> prulom ve 24. vlne,
#   0,20 -> prulom ve 14. vlne a konec v 16., 0,22 -> prulom v 5. (zlato uz
#   nestaci na obranu a hra se zamkne jeste nez se stihne rozjet).
# 0,20 je zvolene: drzi hrace v tahu asi do 15. vlny, ale prvni vlny
# nechava klidne (do 10. vlny se stavi, pak uz jen drzi, co muze).
const HP_GROWTH := 0.20
const ENEMY_SPEED := 52.0
# ODMENA ZA ZAKLADNIHO POUTNIKA. Dalsi druhy maji vlastni odmenu v `Enemy.TIERS`
# (lehky 8, tezky 25); tohle cislo plati pro zakladni druh a drzi se kvuli
# starym mistum, kde sel o jediny druh poutnika.
const REWARD := 12
# VLNA = POCET POUTNIKU, NE CASOVE OKNO. Jan (Oct 2026): "Musíme tedy vrátit
# princip vln místo kol. Že každá vlna bude mít pevně daný počet nepřátel
# určitého typu, kteří budou přicházet v náhodném pořadí. Každá vlna bude buď
# více nepřátel, nebo přibude nový typ."
#
# Tabulka je SLOZENI VLNY: kolik poutniku ktereho druhu vlna posle. Poradi
# druhu v ramci vlny se losuje (viz `wave_plan`), pocet kazdeho je dany -
# hrac tedy vi, KOLIK jich prijde, ale ne v jakem poradi.
#   * lehky (rychly, malo zivotu) se objevi ve 3. vlne,
#   * tezky (pomaly, hodne zivotu) v 5. vlne,
#   * dvojzivelny (bere nevyhody obou zivlu) v 7. vlne.
# Kazda dalsi vlna ma BUD vic poutniku, NEBO novy druh - nikdy mene. Hlida to
# test `_test_waves_get_harder` (součet zivotu vlny musi rust).
const WAVES := [
	{"basic": 6, "light": 0, "heavy": 0, "dual": 0},    # 1
	{"basic": 8, "light": 0, "heavy": 0, "dual": 0},    # 2
	{"basic": 8, "light": 2, "heavy": 0, "dual": 0},    # 3 - novy druh: lehky
	{"basic": 10, "light": 2, "heavy": 0, "dual": 0},   # 4
	{"basic": 10, "light": 3, "heavy": 1, "dual": 0},   # 5 - novy druh: tezky
	{"basic": 11, "light": 4, "heavy": 1, "dual": 0},   # 6
	{"basic": 12, "light": 4, "heavy": 2, "dual": 1},   # 7 - novy druh: dvojzivelny
	{"basic": 12, "light": 5, "heavy": 2, "dual": 1},   # 8
	{"basic": 13, "light": 5, "heavy": 3, "dual": 2},   # 9
	{"basic": 14, "light": 6, "heavy": 3, "dual": 2},   # 10
]
# NEJKRATSI A NEJDELSI MEZERA MEZI DVA POUTNIKY. Hrac musi stihnout
# prepnout vyhybku pro kazdeho zvlast, takze i ta nejkratsi mezera je
# hratelnostni vec: 1 s = 52 px na zakladni rychlosti.
const WAVE_GAP_MIN := 1.0
const WAVE_GAP_MAX := 5.0
# POCET POUTNIKU V PRVNI VLNE ZAKLADNIHO LEVELU. Odtud se nasobi cely
# `WAVES` radek, takze level muze byt tezsi i lehci (`Level.wave_count`).
const BASE_WAVE_ENEMIES := 6
const BUILD_TIME := 6.0
# ODMENA ZA ODRAZENOU VLNU. Vlna se pocita jako investice, ne jen jako
# vydelek z mrtvol: i hrac, ktery v predchozi vlne nezvladl vsechno, dostane
# na dalsi obranu - jinak je z jednoho spatneho rozhodnuti odsouzeny.
const WAVE_BONUS := 30
const WAVE_BONUS_PER_WAVE := 15
# "ELEMENT NEVOLIM" pro `try_build`. Je to cislo mimo vsechny hodnoty useku
# (0..3, Level.NEUTRAL = -1, Level.KMEN = -2), takze se nikdy nemuze plest
# s opravdovym elementem veze.
const ELEMENT_AUTO := -99

var level: Level = null
var net: Network = Network.new()
var towers: Array = []
# VYBRANA VEZ (bunka), nebo -1. Panel s vylepsenim a prodejem se kresli jen
# pro ni, takze "co je vybrane" je stav HRY, ne obrazovky - testy se na to
# ptaji tady a obrazovka si to jen cte.
var sel_tower: Vector2i = Vector2i(-1, -1)
# OZNACENE STAVEBNI MISTO (bunka), nebo -1. Je to stav PRED stavbou: dokud
# tu neco je, obrazovka kresli obchod s vezemi a deska je jen oznacena.
# Teprve "Postavit" z toho udela vez (viz `confirm_build`).
var build_cell: Vector2i = Vector2i(-1, -1)
# VYBRANY DRUH VEZI v obchode (index do Tower.KINDS). Voli se klepnutim na
# druh, ne klepnutim na desku.
var build_kind: int = Tower.DEFAULT_KIND
# VYBRANY ZIVEL VEZE pro oznacene misto. Je to volba HRACE, ne vlastnost
# mista: na elementarnim pasu si hrac vybira mezi vezi sveho elementu
# a neutralni (Jan, Oct 2026: "Na neutrální cestě může být pouze neutrální
# věž. Na elementární cestě může být jak věž daného elementu, tak i neutrální
# věž."). Na neutralnim pasu je nabidka jednoclenná, takze se nic nevoli.
var build_element: int = Tower.NEUTRAL
var enemies: Array = []
# STRELY, KTERE PRÁVĚ LETÍ. Rana neni hotova ve chvili vystrelu - je to
# predmet na ceste k poutnikovi a poskozeni ubira teprve pri DOPADU
# (viz `_move_shots`). Hrac tak vidi, ze rana neprichazi okamzite.
var shots: Array = []
# SLOVNIK BUNKA -> POUTNICI, postaveny jednou za snimek. Vez, ktera nema
# v dosahu nikoho, zustava NABITA (cd = 0) a hleda cil znovu kazdy snimek;
# prohledavat kvuli tomu vsechny poutniky by bylo O(veze x poutnici).
# Takhle si vez precte jen sve ctvercove okoli (2 bunky na kazdou stranu).
var cell_enemies: Dictionary = {}
var gold: int = START_GOLD
var lives: int = START_LIVES
# KOLIKATA VLNA PRAVE BEZI (1, 2, 3 ...). Je to zaroven skore hrace: hra je
# nekonecna, prohra je konec a "vydrzels N vln" je vysledek.
var wave: int = 0
var phase: String = "build"
var build_timer: float = BUILD_TIME
# SLOZENI BEZICI VLNY: jeden radek na kazdeho poutnika ({tier, dual}), v
# poradi, ktere vylosoval `wave_plan`. Pocet je dany tabulkou, poradi nahodne.
var plan: Array = []
# KOLIKATY POUTNIK Z `plan` JE NA RADE. Vlna skonci, kdyz se rovna velikosti
# planu - od te doby uz nikdo nevstoupi a hra jen cisti desku.
var spawn_index: int = 0
# DO KDY VSTOUPI DALSÍ POUTNIK (v sekundach). Neni to perioda: po kazdem
# vstupu se losuje nova mezera 1-5 s, takze hrac vi, KOLIK jich prijde,
# ale ne kdy presne.
var spawn_wait: float = 0.0
# Kolik poutniku uz do TOHOTO VLNY vstoupilo (HUD, souhrn vlny).
var spawned: int = 0
var rng: int = 20261009
# RYCHLOST RUSTU ZIVOTU ZA BEH. Vychozi hodnota je `HP_GROWTH`, takze hra se
# chova presne podle konstanty; nastroj na ladeni obtiznosti
# (`tools/balance_sim.gd`) si ji muze prepnout a projit nekolik hodnot
# v jednom behu, aniz by se sahalo do konstant.
var hp_growth: float = HP_GROWTH
var log: Array = []
# VZPLANUTI VYHYBKY PRI PRUCHODU. Kazdy pruchod poutnika vyhybkou se na chvili
# oznaci a obrazovka z toho kresli krouzek, ktery zhasina. Jan (Oct 2026):
# "Když projde nepřítel výhybkou a dojde k 'rozřazení' na kolej, tak to mělo
# udělat nějaký drobný vizuální efekt. Aby hráč věděl, že už výhybkou prošel.
# Někdy jsou totiž nepřátelé velmi blízko sebe a hráč potřebuje bleskově
# přepnout výhybku. Teď si ale není 100% jistý jestli už nepřítel prošel
# bodem zlomu nebo ne."
#
# Je to stav HRY (ne obrazovky): cas efektu odcita `step`, takze se v testu da
# zmerit, kdy efekt vznikne a kdy zmizi.
var junction_flash: Array = []
const FLASH_TIME := 0.55
# OKNO SHLUKU NA VYHYBCE. Kdyz do jednoho uzlu dojdou dva (a vic) poutniku
# v tomhle case, vyhybka je rozdeli sama - hrac nema jak stihnout dve
# rozhodnuti a nema jak zjistit, ktery je prvni (viz `_cluster_at`).
#
# Merene (zakladni deska, partie po 20 vlnach, ctyri ruzne rychlosti poutniku):
# geometrickych shluku je pri 0,2 s ~2,5 % vsech pruchodu vyhybkami a pri
# 0,5 s uz ~5,5 %. V hre, kde hrac posila vsechno na jednu kolej, rozhodne
# vyhybka v ~4 % pruchodu. Uzsi okno = vzacnejsi jev, ale porad dost casty
# na to, aby hrac neveril, ze o neco prisel.
const CLUSTER_WINDOW := 0.2
# ZIVLY, KTERE SE V TOMHLE LEVELU POSILAJI. Neni to vzdycky vsechny ctyri:
# mapa, ktera ma jen vodu a ohen, posila jen vodni a ohnive poutniky - na
# ostatni by v mape nebyl protiklad a hrac by je nemel jak zabit.
# Pocita se pri stavbe site (rebuild_network), takze hra i zmena velikosti
# okna ji maji vzdy stejnou jako level.
var spawn_pool: Array = []
# ZIVOTY NA ZACATKU PARTIE. HUD potrebuje vedet, z kolika hrac zacinal -
# `Level.lives` si level muze prepsat, konstanta by v HUDu lhala.
var lives_max: int = START_LIVES
# Vypnuto v testech, ktere sleduji jednoho poutnika. V hre vzdy zapnuto.
var auto_wave: bool = true
# VYHYBKY. Kazda si drzi svou volbu - index useku, ktery z ni vede. Je to stav
# ROZEHRANE PARTIE, ne level: proto to neni v Levelu a proto se to pri zmene
# velikosti okna neztrati (sit se prelozi, volba hrace zustava).
var switch_sel: Array = []


func setup(r: Rect2, scale_hint: float = 1.0, bar_top: float = 1.0e9,
		level_data: Level = null) -> void:
	level = level_data if level_data != null else Level.base()
	switch_sel = []
	rebuild_network(r, scale_hint, bar_top)
	towers = []
	sel_tower = Vector2i(-1, -1)
	build_cell = Vector2i(-1, -1)
	build_kind = Tower.DEFAULT_KIND
	build_element = Tower.NEUTRAL
	enemies = []
	shots = []
	cell_enemies = {}
	gold = level.gold
	lives = level.lives
	lives_max = level.lives
	wave = 0
	phase = "build"
	build_timer = BUILD_TIME
	plan = []
	spawn_index = 0
	spawn_wait = 0.0
	spawned = 0
	junction_flash = []
	log = []


# Vymena levelu za behu - pouziva ji editor, ktery si hru nechava postavenou
# a jen do ni posila upravenou desku.
func set_level(level_data: Level, r: Rect2, scale_hint: float = -1.0,
		bar_top: float = -1.0) -> void:
	setup(r, scale_hint, bar_top, level_data)


# Prestaveni site pri zmene velikosti okna. Stav hry zustava - meni se
# jen souradnice, protoze sit je cista geometrie z rectu.
func rebuild_network(r: Rect2, scale_hint: float = -1.0, bar_top: float = -1.0) -> void:
	# Zavorky u defaultu jsou potreba: vyraz s = by se jinak cetl jako
	# prirazeni do promenne "r".
	var sc: float = scale_hint
	if sc < 0.0:
		sc = net.scale
	var bt: float = bar_top
	if bt < 0.0:
		bt = net.bar_top
	var lv: Level = level
	if lv == null:
		# Hra si musi level drzet, ne jen pouzit. Kdyby si ho jen pujcila
		# do lokalni promenne, zustal by `level` prazdny a kazdy, kdo se ho
		# zepta (trefa do vyhybky, poskozeni, jmeno v HUD), by spadl.
		lv = Level.base()
		level = lv
	net = Network.new()
	net.build(r, sc, bt, lv)
	# Zivly, ktere level posila. Bere se z LEVELU, ne z konstanty: hra se
	# nikdy nesmi chovat jinak, nez jak vypada mapa.
	spawn_pool = lv.spawn_elements()
	_sync_switch()


# Volby vyhybek musi mit hra svuj vlastni seznam: sit se pri zmene velikosti
# okna stavi ZNOVU, takze by se volba hrace ztratila. Prepocita se jen tolik
# voleb, kolik ma sit vyhybek - kdyz se pocet zmeni (jiny level), zacinaji
# vsechny na prvni vetvi.
func _sync_switch() -> void:
	var n: int = net.junction_count()
	for j in range(n):
		if j < switch_sel.size():
			var lanes_in_j: int = maxi(net.junction_lanes[j].size(), 1)
			switch_sel[j] = clampi(int(switch_sel[j]), 0, lanes_in_j - 1)
		else:
			switch_sel.append(0)
	while switch_sel.size() > n:
		switch_sel.remove_at(switch_sel.size() - 1)


# ---------------------------------------------------------------- veze

func tower_at(cell: Vector2i) -> Tower:
	for item in towers:
		var t: Tower = item
		if t.cell == cell:
			return t
	return null


# Kolik vezi stoji. HUD z toho cte, kolik hrac vubec postavil.
func tower_count() -> int:
	return towers.size()


# KOLIK VEZI STOJI V PASU TOHOHLE USEKU. Hrac to vidi v hornim panelu
# u vybraneho useku: vyhybkou kupuje "kam je poslu" a cislo rika, kolik
# obrany ho tam ceka.
func towers_of_lane(lane: int) -> int:
	var c: int = 0
	for item in towers:
		var t: Tower = item
		if net.strip_lane_of(t.cell) == lane:
			c += 1
	return c


# POSTAVENI VEZE. Mimo pas se stavet neda vubec a element veze musi byt
# z nabidky toho mista (`build_elements`): u neutralni cesty je to jedina
# neutralni vez, u elementarni cesty vez sveho elementu nebo neutralni.
#
# TAHLE FUNKCE UZ SE Z DESKY NEVOLA. Deska umi jen OZNACIT misto
# (`select_build_cell`) a stavba je az `confirm_build` - vez se nesmi postavit
# omylem pri prvnim klepnuti (Jan, Oct 2026).
func try_build(cell: Vector2i, kind: int = Tower.DEFAULT_KIND,
		element: int = ELEMENT_AUTO) -> bool:
	var why: String = _build_block_reason(cell)
	if not why.is_empty():
		_note(why)
		return false
	# Kdo element nevoli (stare mapy, testy), dostane element pasu - presne to,
	# co umela hra driv. Nabidka mista ho vzdycky obsahuje.
	if element == ELEMENT_AUTO:
		element = net.strip_element(cell)
	var ewhy: String = _build_element_reason(cell, element)
	if not ewhy.is_empty():
		_note(ewhy)
		return false
	var cost: int = Tower.kind_cost(kind, 1)
	if gold < cost:
		_note("Málo zlata na věž (%d)." % cost)
		return false
	gold -= cost
	var t := Tower.new()
	t.cell = cell
	t.kind = kind
	t.element = element
	# Kolik do ni hrac dal - z toho se pocita cena pri prodeji.
	t.spent = cost
	towers.append(t)
	sel_tower = cell
	# Obchod se zavira: misto je zadane. Nechat ho oznacene by hrace mátlo
	# ("a staví se jeste neco?").
	build_cell = Vector2i(-1, -1)
	_note("Věž %s postavena." % Level.value_name(t.element))
	return true


# PROC SE NA TUHLE BUNKU NEDA STAVET. Prazdny retezec = stavebni misto je
# v poradku. Dve ruzne veci se musi rict ruzne, jinak hrac hleda chybu v siti:
# bud je to cesta sama/uzel (tam se proste nestavi), nebo je to misto mimo pas.
# Pouziva ji oznaceni mista i stavba - jedna pravda pro obe.
func _build_block_reason(cell: Vector2i) -> String:
	if not net.strip_has(cell):
		if net.level.node_at_cell(cell) >= 0:
			return "Na uzlu se nestaví."
		if _is_lane_cell(cell):
			return "Na cestě se nestaví — věže patří do pásu vedle ní."
		return "Tady pás není — věže stojí jen u cesty."
	if tower_at(cell) != null:
		return "Tady už věž stojí."
	return ""


# MUZE NA TOM MISTE STAT VEZE TOHOHLE ELEMENTU? Pravidlo je Janovo (Oct
# 2026): na neutralni ceste jen neutralni vez, na elementarni ceste vez sveho
# elementu nebo neutralni. Hlaska musi rict, co je tu vubec mozne - tiche
# odmitnuti by hrace nechalo hadat, proc tlacitko neudelalo nic.
func _build_element_reason(cell: Vector2i, element: int) -> String:
	var allowed: Array = build_elements(cell)
	if allowed.has(element):
		return ""
	var lane_el: int = net.strip_element(cell)
	if lane_el == Level.NEUTRAL:
		return "U neutrální cesty může stát jen neutrální věž."
	var names: Array = []
	for e in allowed:
		names.append(Level.value_name(int(e)))
	return "Tady může stát jen věž %s." % " nebo ".join(names)


# ZIVLY, KTERE NA TOM MISTE SMI VEZ MÍT. Zdrojem pravdy je typ pasu - viz
# `Tower.allowed_elements`.
func build_elements(cell: Vector2i) -> Array:
	if not net.strip_has(cell):
		return []
	return Tower.allowed_elements(net.strip_element(cell))


# NABIDKA PRO OZNACENE MISTO. Neni to seznam druhu, ale seznam VOLEB, ktere
# hrac na tom miste ma: kazdy povoleny zivel (a casem i kazdy druh). Obrazovka,
# klepnuti i testy se ptaji tohohle jednoho seznamu, takze tlacitko nemuze
# nabizet neco jineho, nez co `try_build` prijme.
func build_choices() -> Array:
	var out: Array = []
	if not build_selected():
		return out
	for e in build_elements(build_cell):
		for k in range(Tower.KIND_COUNT):
			out.append({"kind": k, "element": int(e),
				"label": Tower.choice_label(k, int(e)),
				"cost": Tower.kind_cost(k, 1)})
	return out


# KTERA VOLBA JE PRAVE VYBRANA (-1 = zadna). Obrazovka z toho dela zvyrazneny
# ramecek, takze se nikdy nemuze stat, ze by svitilo neco jineho, nez co se
# opravdu postavi.
func build_choice_index() -> int:
	var ch: Array = build_choices()
	for i in range(ch.size()):
		var row: Dictionary = ch[i]
		if int(row["kind"]) == build_kind and int(row["element"]) == build_element:
			return i
	return -1


# ------------------------------------------------- stavba ve dvou krocich

# OZNACENI STAVEBNIHO MISTA. Klepnuti na prazdnou bunku pasu uz vez NESTAVI:
# jen misto oznaci a otevre obchod s vezemi. Jan (Oct 2026): "Věž by se
# neměla postavit hned při prvním kliknutí na stavební půdu. Zaprvé bude na
# výběr více druhů věží a za druhé se takhle snadno postaví věž omylem.
# Musíme označit půdu, dostat na výběr věže, vybrat věž a kliknout na
# 'postavit'."
func select_build_cell(cell: Vector2i) -> bool:
	var why: String = _build_block_reason(cell)
	if not why.is_empty():
		_note(why)
		return false
	if build_cell == cell:
		# Druhe klepnuti na to same misto obchod ZAVRE - presne jako druhe
		# klepnuti na vybranou vez zrusi vyber. Klepnuti na uz oznacene
		# misto musi neco znamenat, ne jen zopakovat to prvni.
		build_cell = Vector2i(-1, -1)
		_note("Stavba zrušena.")
		return false
	build_cell = cell
	build_kind = Tower.DEFAULT_KIND
	# Vychozi volba je vez sveho elementu: kdo nic nevybere, dostane to, co
	# misto nabizi jako prvni (`build_choices`).
	build_element = net.strip_element(cell)
	# Vybrana vez a oznacene misto se vzajemne vylucuji: na obrazovce je pro
	# ne jen jeden pruh a hrac by nevedel, ktera tlacitka plati.
	sel_tower = Vector2i(-1, -1)
	_note("Stavební místo vybráno — zvol věž a klepni na Postavit.")
	return true


# VOLBA V OBCHODE. Jen vybira, nestavi - stavba je az `confirm_build`.
func pick_choice(index: int) -> bool:
	var ch: Array = build_choices()
	if index < 0 or index >= ch.size():
		return false
	var row: Dictionary = ch[index]
	build_kind = int(row["kind"])
	build_element = int(row["element"])
	_note("Vybraná věž: %s (%d)." % [Tower.choice_label(build_kind, build_element),
		Tower.kind_cost(build_kind, 1)])
	return true


func cancel_build() -> void:
	if build_cell.x >= 0:
		_note("Stavba zrušena.")
	build_cell = Vector2i(-1, -1)


# Je otevreny obchod s vezemi? Obrazovka se na to ptá, aby vedela, co kreslit.
func build_selected() -> bool:
	return build_cell.x >= 0


# POSTAVIT. Jedina cesta, jak dostat vez na desku z ruky hrace - klepnuti na
# desku umi jen oznacit misto. Hraje se tedy na dve klepnuti a omylem
# postavena vez prestava existovat.
func confirm_build() -> bool:
	if build_cell.x < 0:
		_note("Nejdřív vyber stavební místo.")
		return false
	return try_build(build_cell, build_kind, build_element)


# VYLEPSENI VEZE. Kazdy dalsi level je drazsi a o neco rychlejsi a silnejsi.
func try_upgrade(cell: Vector2i) -> bool:
	var t: Tower = tower_at(cell)
	if t == null:
		_note("Tady žádná věž nestojí.")
		return false
	if not t.can_upgrade():
		_note("Věž je na maximu.")
		return false
	var cost: int = t.upgrade_cost()
	if gold < cost:
		_note("Málo zlata na vylepšení (%d)." % cost)
		return false
	gold -= cost
	t.spent += cost
	t.level += 1
	_note("Věž vylepšena na úroveň %d." % t.level)
	return true


# PRODEJ VEZE. Vez je samostatny objekt, takze ji hrac musi umet i zbavit se -
# jinak by mu spatne postavena vez blokovala bunku do konce hry.
func try_sell(cell: Vector2i) -> bool:
	var t: Tower = tower_at(cell)
	if t == null:
		_note("Tady žádná věž nestojí.")
		return false
	var back: int = t.sell_back()
	gold += back
	towers.erase(t)
	if sel_tower == cell:
		sel_tower = Vector2i(-1, -1)
	_note("Věž prodána za %d." % back)
	return true


# ---------------------------------------------------------------- vyber veze

func selected_tower() -> Tower:
	if sel_tower.x < 0:
		return null
	return tower_at(sel_tower)


# VYBER VEZE. Klepnuti na hotovou vez ji VYBRE (ne vylepsi): hrac musi nejdriv
# videt, co ta vez umi a co stoji dalsi level, a teprve pak se rozhodnout.
# Klepnuti na uz vybranou vez vyber ZRUSI - druhe klepnuti na to same misto
# musi neco znamenat, ne jen zopakovat prvni.
func select_tower(cell: Vector2i) -> bool:
	if tower_at(cell) == null:
		sel_tower = Vector2i(-1, -1)
		return false
	# Obchod s vezemi se zavre: hrac si prave rekl o INFORMACE o vezi, ktera
	# uz stoji, ne o stavbu nove.
	build_cell = Vector2i(-1, -1)
	if sel_tower == cell:
		sel_tower = Vector2i(-1, -1)
		_note("Výběr zrušen.")
		return false
	sel_tower = cell
	var t: Tower = tower_at(cell)
	if t.can_upgrade():
		_note("Věž %s, úroveň %d — vylepšení %d." % [
			Level.value_name(t.element), t.level, t.upgrade_cost()])
	else:
		_note("Věž %s, úroveň %d — maximum." % [Level.value_name(t.element), t.level])
	return true


# Klepnuti na bunku pasu: prazdna = OZNAC misto (obchod s vezemi), obsazena =
# vyber ji. Jedno misto pro tohle rozhodnuti - obrazovka se ho jen ptá.
# Vylepseni a prodej uz nejsou "druhe klepnuti na vez", ale tlacitka u vybrane
# veze: prodavat ve dve klepnuti omylem by hrac prisel o vez, kterou chtel
# vylepsit. Stavba je ze STEJNEHO duvodu na dve klepnuti (misto, pak Postavit).
func tap_build_cell(cell: Vector2i) -> bool:
	if tower_at(cell) != null:
		return select_tower(cell)
	return select_build_cell(cell)


# ZRUSENI VSECH VYBERU. Klepnuti mimo desku (nebo mimo pruh s tlacitky)
# nesmi nechat viset ani panel vybrane veze, ani obchod s vezemi - jinak by
# panel prekryval desku a hrac by nevedel, proc.
func clear_selection() -> void:
	sel_tower = Vector2i(-1, -1)
	build_cell = Vector2i(-1, -1)


func _is_lane_cell(cell: Vector2i) -> bool:
	for i in range(net.lane_count()):
		for cellv in net.level.lane_cells(i):
			if cellv == cell:
				return true
	return false


# ---------------------------------------------------------------- vyhybka

# KLEPNUTI NA USEK PREPNE VYHYBKU, ZE KTERE TEN USEK VEDE. Vyhybek muze byt
# vic a kazda ma svou volbu - hrac tim rozhoduje, kam pujde dalsi poutnik.
func set_switch(lane: int) -> void:
	if lane < 0 or lane >= net.lane_count():
		return
	var j: int = net.lane_junction(lane)
	if j < 0:
		return
	switch_sel[j] = int(net.lane_sel_index[lane])
	_note("Výhybka %d nastavena na %s." % [j + 1, net.level.lane_type_name(lane)])


# Který usek vyhybka posila. Hra to potrebuje pri kazdem pruchodu poutnika.
func selected_lane(j: int) -> int:
	if j < 0 or j >= net.junction_count():
		return -1
	if switch_sel.size() != net.junction_count():
		_sync_switch()
	return net.junction_lane(j, int(switch_sel[j]))


# POSUN VYHYBKOU NA DALSÍ VETEV. Pouziva ji klepnuti na uzel vyhybky -
# klepnuti na usek vybere presne ten usek, klepnuti na kruh jde na dalsi.
# Dve ruzna gesta na dve ruzne veci: hrac na malem displeji nemusi trefovat
# konkretni caru, kdyz chce jen "posli je jinam".
func cycle_switch(j: int) -> void:
	if j < 0 or j >= net.junction_count():
		return
	var lanes: Array = net.junction_lanes[j]
	if lanes.is_empty():
		return
	if switch_sel.size() != net.junction_count():
		_sync_switch()
	var cur: int = int(switch_sel[j])
	switch_sel[j] = (cur + 1) % lanes.size()
	var lane: int = net.junction_lane(j, int(switch_sel[j]))
	_note("Výhybka %d: %s." % [j + 1, net.level.lane_type_name(lane)])


# Usek vybrany na PRVNI vyhybce. HUD v nem ukazuje nasobek poskozeni.
func switch_lane() -> int:
	return selected_lane(0)


# Je tenhle usek prave vybrany na sve vyhybce? Kresli se podle toho jas.
func lane_selected(lane: int) -> bool:
	return selected_lane(net.lane_junction(lane)) == lane


# ---------------------------------------------------------------- vlny

# START VLNY. Slozeni se vezme z tabulky (`wave_plan`): pocet kazdeho druhu je
# dany, poradi se losuje. Prvni poutnik vstupuje HNED - kdyby se losovalo i
# prvni cekani, hrac by na zacatku vlny koukal do prazdne mapy a nevedel, ze
# vlna bezi.
func start_wave() -> void:
	wave += 1
	phase = "wave"
	plan = wave_plan(wave)
	spawn_index = 0
	spawn_wait = 0.0
	spawned = 0
	var msg: String = "Vlna %d: %s." % [wave, wave_summary(wave)]
	# DVOJZIVELNY JE IMUNNI NA OBA SVOJE ZIVLY (viz `Enemy.mult_against`),
	# takze na nej plati jen neutralni vez. Pravidlo se rekne JEDNOU, v prvni
	# vlne, kde se dvojzivelni objevi - hrac jinak vidi, jak rany nic nedelaji,
	# a nema se to jak dozvedet.
	if level != null and int(wave_counts(wave)["dual"]) > 0 \
			and int(wave_counts(maxi(wave - 1, 1))["dual"]) == 0:
		msg += " Dvojzivelný je imunní na oba své živly — platí na něj neutrální věž."
	# PRAZDNY SEZNAM JE TA NEJHORSI ODPOVED. Hrac vidi, ze vlna bezi, deska
	# zustava prazdna - a nema jak zjistit, ze chyba neni v siti, ale v mape.
	# Jan (Oct 2026): "Po spuštění levelu v editoru teď nepřátelé vůbec
	# nechodí. Nebo je to nějakým nastavením?" Proto se kazdy duvod rekne
	# slovy; ticha funkce je neexistujici funkce.
	if level != null:
		if net.entry_lanes.is_empty() or spawn_pool.is_empty():
			msg += " " + _empty_pool_reason()
		else:
			var bad: Array = level.unkillable_elements()
			if not bad.is_empty():
				var names: String = ""
				for e in bad:
					var el: int = e
					names += ("" if names.is_empty() else ", ") + Element.name_of(el)
				msg += " %s nemá v mapě protiklad — neposílá se." % names
	_note(msg)


# SLOZENI VLNY. Radek tabulky pro vlny 1..10; dal se pocita vzorcem - kazda
# dalsi vlna prida zakladniho poutnika a ob vlnu i jednoho z kazdeho dalsiho
# druhu. Hra tim nema strop a obtiznost roste porad (viz `WAVES`).
func wave_mix(n: int) -> Dictionary:
	var idx: int = clampi(n, 1, WAVES.size()) - 1
	var row: Dictionary = WAVES[idx]
	var extra: int = maxi(n - WAVES.size(), 0)
	return {
		"basic": int(row["basic"]) + extra,
		"light": int(row["light"]) + (extra + 1) / 2,
		"heavy": int(row["heavy"]) + (extra + 1) / 2,
		"dual": int(row["dual"]) + extra / 2,
	}


# POCET POUTNIKU KAZDEHO DRUHU PRO TENHLE LEVEL. Nasobi se pomerem
# `Level.wave_count` k zakladnimu poctu (6), takze level s dvanacti posila na
# kazdou vlnu dvojnasobek a level se tremi polovinu. Nula zustava nulou (druh
# se v te vlne jeste neobjevil); co vyjde aspon na jednoho, je aspon jeden.
func wave_counts(n: int) -> Dictionary:
	var mix: Dictionary = wave_mix(n)
	var base: int = BASE_WAVE_ENEMIES
	if level != null:
		base = maxi(level.wave_count, 1)
	var k: float = float(base) / float(BASE_WAVE_ENEMIES)
	var out: Dictionary = {}
	for key in mix.keys():
		var c: int = int(mix[key])
		out[key] = 0 if c <= 0 else maxi(1, int(round(float(c) * k)))
	return out


func _plan_push(out: Array, tier: int, count: int, dual: bool) -> void:
	for i in range(count):
		out.append({"tier": tier, "dual": dual})


# PLAN VLNY: jeden radek na kazdeho poutnika, v NAHODNEM poradi. Poradi se
# losuje tady, ne az pri vstupech - vsechny nahody vlny tak jdou jednim rng
# na jednom miste a hra zustava deterministicka (test na to ma kontrolu).
func wave_plan(n: int) -> Array:
	var c: Dictionary = wave_counts(n)
	var out: Array = []
	_plan_push(out, Enemy.TIER_BASIC, int(c["basic"]), false)
	_plan_push(out, Enemy.TIER_LIGHT, int(c["light"]), false)
	_plan_push(out, Enemy.TIER_HEAVY, int(c["heavy"]), false)
	_plan_push(out, Enemy.TIER_BASIC, int(c["dual"]), true)
	for i in range(out.size() - 1, 0, -1):
		var j: int = _next_int(i + 1)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


# JMENA DRUHU VE SLOZENI VLNY. Hrac se z buildu musi dozvedet, na co se
# chysta - "vic poutniku" bez druhu je jen cislo.
const WAVE_WORD := {
	"basic": "základních", "light": "lehkých", "heavy": "těžkých",
	"dual": "dvojživelných",
}


# KOLIK POUTNIKU TAHLE VLNA POSLE (soucet vsech druhu).
func wave_size(n: int) -> int:
	var c: Dictionary = wave_counts(n)
	return int(c["basic"]) + int(c["light"]) + int(c["heavy"]) + int(c["dual"])


# SLOZENI VLNY SLOVY, treba "12 základních · 5 lehkých · 2 těžkých".
func wave_summary(n: int) -> String:
	var c: Dictionary = wave_counts(n)
	var parts: Array = []
	for key in ["basic", "light", "heavy", "dual"]:
		var cnt: int = int(c[key])
		if cnt > 0:
			parts.append("%d %s" % [cnt, WAVE_WORD[key]])
	if parts.is_empty():
		return "—"
	return " · ".join(parts)


# PROC NIKDO NECHODI. Tri ruzne priciny vypadaji na obrazovce stejne (vlna
# bezi, deska je prazdna), takze se musi rozeznat SLOVY. Jedno misto pro
# vsechny tri - kdyby si kazda vetev vymyslela vlastni vetu, rozejdou se.
func _empty_pool_reason() -> String:
	if net.entry_lanes.is_empty():
		return "Mapa nemá start — poutníci nemají kudy vejít."
	if level == null or level.present_elements().is_empty():
		return "V mapě není ani jeden úsek s živlem — poutníci nechodí. " \
			+ "Nakresli dva protikladné živly (oheň a vodu, zemi a vzduch)."
	return "Ani jeden živl v mapě nemá svůj protiklad — není čím je zabít, " \
		+ "proto se z nich neposílá."


# MEZERA DO DALSÍHO VSTUPU. Losuje se pro kazdou mezeru zvlast z rozpeti
# 1-5 s, takze vstupy nejsou perioda (hrac nesmi videt "kazde 3 s"). Nahodne
# cislo je z TEHOZ rng jako slozeni vlny, takze hra zustava deterministicka -
# test na to ma kontrolu.
func _next_gap() -> float:
	var t: float = float(_next_int(1001)) / 1000.0
	return WAVE_GAP_MIN + (WAVE_GAP_MAX - WAVE_GAP_MIN) * t


# Bezi jeste vstupy? Jedine misto, kde se to rozhoduje - HUD, step i testy
# se musi ptat tady, jinak by se "vlna skoncila" pocitalo na trech mistech.
func spawning() -> bool:
	return phase == "wave" and spawn_index < plan.size()


func _speed() -> float:
	var sp: float = level.speed if level != null else ENEMY_SPEED
	return maxf(sp, 1.0)


func _spawn(kind_el: int, tier: int = Enemy.TIER_BASIC, pair: Array = []) -> void:
	var e := Enemy.new()
	e.element = kind_el
	# DRUHY ZIVEL: kdyz hra vylosovala dvojici (ohen+voda), dostane poutnik
	# ten druhy z dvojice - nezalezi na tom, ktery z nich prisel jako prvni.
	if pair.size() == 2:
		e.element2 = int(pair[1]) if int(pair[0]) == kind_el else int(pair[0])
	e.tier = tier
	e.max_hp = BASE_HP * pow(1.0 + hp_growth, float(wave - 1)) * Enemy.tier_hp(tier)
	e.hp = e.max_hp
	e.speed = (level.speed if level != null else ENEMY_SPEED) * Enemy.tier_speed(tier)
	# POUTNIK VSTUPUJE NA VSTUPNI USEK. Vstup do mapy je v mrizce normalni
	# usek ze startu (od vychoziho stavu kmen, takze neposkozuje). Vstupu
	# muze byt vic a VSTUP SE LOSUJE - driv se kmeny stridaly po poradi
	# ("kazdy druhy zleva"), coz hrac odhalil jako vzor.
	# Kdyby mapa zadny start nemela, poutnik se neobjevi vubec.
	if net.entry_lanes.is_empty():
		return
	e.lane = int(net.entry_lanes[_next_int(net.entry_lanes.size())])
	e.s = 0.0
	e.pos = net.point_at(e.lane, 0.0)
	spawned += 1
	enemies.append(e)


# VSTUP JEDNOHO POUTNIKA Z PLANU VLNY. Zivel se losuje (jen z toho, co mapa
# posila), dvojzivelny si k tomu losuje dvojici protikladu. Kdyz mapa zadnou
# dvojici nema, prijde jednozivelny - vlna se kvuli tomu nesmi zaseknout.
func _spawn_from_plan(row: Dictionary) -> void:
	var el: int = _next_element()
	if el < 0:
		return
	var pair: Array = []
	if bool(row.get("dual", false)):
		pair = _next_dual_pair()
	_spawn(el, int(row.get("tier", Enemy.TIER_BASIC)), pair)


# Verejny vstup pro nastroje (nahled, diagnostika). Hra sama spawnuje
# jen pres vlny, takze se tohle v hernim kode nikde nevola. Druh a dvojici
# zivlu si muze zavolany rict - jinak prijde zakladni jednozivelny.
func debug_spawn(enemy_el: int, tier: int = Enemy.TIER_BASIC, pair: Array = []) -> Enemy:
	_spawn(enemy_el, tier, pair)
	if enemies.is_empty():
		return null
	var e: Enemy = enemies[enemies.size() - 1]
	return e


# VYSTREL PRO NAHLED (snimek vzhledu). Strela leti 0,25 s, takze ji zadny
# snimek nechyta - nahled si ji proto vyrobi rucne a `aim_at` mu dovoli
# postavit ji tam, kam se na snimek vejde. `e` muze byt i null: strela
# v nahledu nikam nedoleti, takze cil nepotrebuje. V hernim kode se nevola.
func debug_fire(t: Tower, e: Enemy, aim_at: Vector2) -> Shot:
	if t == null:
		return null
	t.cd = t.cooldown()
	var s: Shot = Shot.launch(t, e, net.cell_center(t.cell), aim_at, t.damage())
	shots.append(s)
	return s


func _next_int(limit: int) -> int:
	rng = (rng * 1103515245 + 12345) & 0x7fffffff
	return (rng / 65536) % limit


# Ktery zivel poutnika posleme. VYHradNE z zivlu, ktere v mape opravdu jsou:
# kdyz mapa nema vzduch, neposle se vzduch (hrac by na nej nemel protiklad).
# Poradi zustava dane (deterministicke) - hra se nikde nesmi zacit chovat
# jinak podle toho, jak vypada mapa.
func _next_element() -> int:
	if spawn_pool.is_empty():
		return -1
	return int(spawn_pool[_next_int(spawn_pool.size())])


# DVOJICE PROTIKLADNYCH ZIVLU pro dvojzivelneho poutnika. Vyberaji se JEN
# zivly, ktere mapa posila, a druhy z dvojice musi byt taky v mape - jinak by
# hrac na jednu pul poutnika nemel protiklad a nemel by ho cim zabit.
# Dvojice se bere jednou (`el < op`), aby ohen+voda nebyla i voda+ohen.
func _next_dual_pair() -> Array:
	var pairs: Array = []
	for x in spawn_pool:
		var el: int = x
		var op: int = Element.opposite_of(el)
		if el < op and spawn_pool.has(op):
			pairs.append([el, op])
	if pairs.is_empty():
		return []
	return pairs[_next_int(pairs.size())]


# ---------------------------------------------------------------- krok

func step(delta: float) -> void:
	if phase == "lost" or phase == "won":
		return

	if phase == "build":
		build_timer -= delta
		if build_timer <= 0.0:
			build_timer = 0.0
			if auto_wave:
				start_wave()
	elif phase == "wave":
		# POUTNICI VCHAZEJI V PORADI, KTERE VYLOSOVAL PLAN VLNY, s nahodnou
		# mezerou 1-5 s. Pocet je dany tabulkou, takze hrac vi, KOLIK jich
		# prijde - nevi jen, kdy presne a v jakem poradi druhu. `while` tu je
		# kvuli velkemu kroku (testy umi skocit o par sekund), ale mezera
		# >= 1 s ho necha bezet jednou.
		spawn_wait -= delta
		var guard: int = 0
		while spawn_index < plan.size() and spawn_wait <= 0.0 and guard < 60:
			guard += 1
			_spawn_from_plan(plan[spawn_index])
			spawn_index += 1
			spawn_wait += _next_gap()
		if spawn_index >= plan.size():
			phase = "clear"
			_note("Vlna %d: všichni vešli, dočisti desku." % wave)

	_move_enemies(delta)
	_fire(delta)
	_move_shots(delta)
	# Uklid na jednom miste: kdo umrel (dopadem strely) nebo dosel do cile,
	# je z desky pryc jeste pred vyhodnocenim kola.
	_prune()
	_fade_flash(delta)
	if lives <= 0:
		phase = "lost"
		_note("PROHRA.")

	# VLNA KONCI AZ PRAZDNOU DESKOU. Kdyz vstupy skoncily a na desce uz nic
	# neni, vlna je odrazena. Dokud se poutnici dobíjejí, hra ceka - hrac
	# tak nikdy neprijde o vlnu s poutniky na ceste.
	if phase == "clear" and enemies.is_empty():
		wave_done()


# ODRAZENA VLNA. Odmena roste s vlnou: cim tezsi vlna, tim vic zlata na
# dalsi obranu - jinak by se hrac dostal do stavu, kdy uz nema z ceho stavet
# a jen ceka na konec (Jan: "nemáš peníze na další věže a jsi odsouzen k
# záhubě"). Bonus dostava i hrac, ktery vsechno nezvladl.
func wave_done() -> void:
	var bonus: int = WAVE_BONUS + WAVE_BONUS_PER_WAVE * wave
	gold += bonus
	phase = "build"
	build_timer = BUILD_TIME
	_note("Vlna %d odražena (+%d zlata)." % [wave, bonus])


func _move_enemies(delta: float) -> void:
	# POSUN. Vsechno se nejdriv posune, teprve pak se rozhoduje - kdyz dva
	# poutnici dojdou do uzlu ve stejnem snimku, musi se o nich rozhodnout
	# NAJEDNOU (viz `_cluster_at`).
	for item in enemies:
		var e: Enemy = item
		if not e.alive:
			# Mrtve vyhazuje `_prune` na konci kroku - tady se jen preskakuji.
			continue
		# Poutnik mimo trasu znamena, ze mapa nema start. Nema kam jit.
		if not e.on_lane():
			e.leaked = true
			e.alive = false
			lives -= 1
			continue
		e.s += e.speed * delta
		e.pos = net.point_at(e.lane, e.s)

	# SHLUK NA VYHYBCE. Kdyz se do jednoho uzlu hrne vic poutniku v okne
	# `CLUSTER_WINDOW`, hrac nema sanci: nestihne dve klepnuti a hlavne nema
	# jak zjistit, ktery z nich je prvni (je to hod minci). Vyhybka je proto
	# rozdeli sama. Detekuje se to DOPREDU - z pozice a rychlosti kazdeho
	# poutnika se spocita, za jak dlouho do uzlu dojde, takze nikdo nemusi
	# cekat (poutnici plynou jako dosud).
	for item in enemies:
		var e: Enemy = item
		if not e.alive or e.route_node >= 0 or not e.on_lane():
			continue
		if e.s < float(net.lane_len[e.lane]):
			continue
		var nd: int = net.lane_end_node(e.lane)
		if net.junction_index_of_node(nd) < 0:
			continue
		var group: Array = _cluster_at(nd, e)
		if group.size() > 1:
			_route_cluster(nd, group)

	for item in enemies:
		var e: Enemy = item
		if not e.alive:
			continue
		if not e.on_lane():
			continue
		if e.s < float(net.lane_len[e.lane]):
			continue
		# KONEC USEKU = POUTNIK JE V UZLU. Tam se rozhodne:
		#   vyhybka             - hrac svou volbou posle poutnika na jeden
		#                         ze svych vystupu (rozhoduje se az ted,
		#                         v okamziku pruchodu); kdyz je poutnik ve
		#                         shluku, rozhodla uz za nej hra,
		#   spojka / uzel / start - jediny vystup, zadne rozhodovani,
		#   cil                - konec cesty, stoji zivot.
		var nd: int = net.lane_end_node(e.lane)
		var nxt: int = -1
		# INDEX VYHYBKY se musi drzet i po prechodu (efekt prusmyku se kresli
		# nad ni), takze se nedeklaruje uvnitr vetve.
		var j: int = -1
		if nd >= 0:
			j = net.junction_index_of_node(nd)
			var sel: int = 0
			if j >= 0:
				if e.route_node == nd:
					# SHLUK: takhle rozhodla vyhybka sama, hrac na to nemel
					# jak zareagovat. Prirazeni je pro tenhle pruchod.
					sel = e.route_sel
				else:
					if switch_sel.size() != net.junction_count():
						_sync_switch()
					sel = int(switch_sel[j])
			nxt = level.next_lane(nd, sel)
		e.route_node = -1
		e.route_sel = -1
		if nxt < 0 or nxt >= net.lane_count():
			e.leaked = true
			e.alive = false
			lives -= 1
			if nd >= 0 and int(net.node_kind[nd]) == Level.CIL:
				_note("Poutnik %s došel do cíle (-1 život)." % e.title())
			else:
				_note("Poutnik %s zabloudil (-1 život)." % Element.name_of(e.element))
			continue
		# ROZRAZENI JE HOTOVE - a hrac to musi videt. Teprve ted totiz plati,
		# ze dalsi prepnuti vyhybky posle uz NASLEDUJICIHO poutnika; u dvou
		# poutniku tesne za sebou je to jedina jistota, kterou hrac ma.
		if j >= 0:
			_flash_junction(nd, nxt)
		e.lane = nxt
		e.s = 0.0
		e.pos = net.point_at(nxt, 0.0)


# =========================================================================
# SHLUK NA VYHYBCE
#
# Jan (Oct 2026): "Když nastane scénář, kdy dorazí na výhybku dva nepřátelé
# příliš blízko u sebe, tak je výhybka rozdělí automaticky, korektně. Takže
# to bude ve výsledku příjemný incident."
#
# PROC TO TU JE: poutnici maji ruzne rychlosti (2,7x rozdil mezi lehkym a
# tezkym), takze se pred vyhybkou dohaneji a nekdy do ni vejdou v jednom
# okamziku. Hrac ma na klepnuti ~0,2 s a hlavne NEMA JAK ZJISTIT, ktery
# z nich je prvni - oba vypadaji stejne blizko. Dve rozhodnuti v jednom
# okamziku tedy nejsou o sikovnosti, ale o hode minci.
#
# Reseni: hra to vi PRESNE (cas do uzlu je z pozice a rychlosti dany), takze
# se na to podiva DOPREDU a rozhodne za hrace. Nikdo neceka a nikdo se
# neřadí - poutnici plynou po svych kolejich jako dosud.
# =========================================================================

# Kdo vsechno do uzlu dojde v jednom okne. Zacne se tim, kdo tam je prave ted,
# a prida se kazdy, kdo se vejde do okna za POSLEDNIM pridanym clenem. Tak se
# posklada i retez (tri poutnici v rozestupu 0,4 s a okno 0,5 s jsou jeden
# shluk), ktery by se po dvojicich rozpadl.
func _cluster_at(node: int, first: Enemy) -> Array:
	var group: Array = [first]
	var t: float = 0.0
	var guard: int = 0
	while guard < 32:
		guard += 1
		var added: bool = false
		for item in enemies:
			var e: Enemy = item
			if not e.alive or e.route_node >= 0 or group.has(e):
				continue
			var ta: float = _arrival_in(e, node)
			if ta < 0.0 or ta > t + CLUSTER_WINDOW:
				continue
			group.append(e)
			t = maxf(t, ta)
			added = true
		if not added:
			break
	return group


# ZA JAK DLOUHO POUTNIK DOJDE DO UZLU `node`. Cesta se pocita jen pres uzly
# bez rozhodovani (start, spojka, uzel) - pres vyhybku nebo cil se predpovidat
# NEDA (nevime, kam hrac klepne), takze takovy poutnik do shluku nepatri.
# -1 = nedozvime se.
func _arrival_in(e: Enemy, node: int) -> float:
	var lane: int = e.lane
	var s: float = e.s
	var sp: float = maxf(e.speed, 0.001)
	var t: float = 0.0
	for step_i in range(4):
		if lane < 0 or lane >= net.lane_count():
			return -1.0
		var ln: float = float(net.lane_len[lane])
		if s < ln:
			t += (ln - s) / sp
			s = ln
		var nd: int = net.lane_end_node(lane)
		if nd == node:
			return t
		if nd < 0:
			return -1.0
		var kind: int = int(net.node_kind[nd])
		if kind == Level.VYHYBKA or kind == Level.CIL:
			return -1.0
		lane = level.next_lane(nd, 0)
	return -1.0


# ROZDĚLENÍ SHLUKU. Kazdy clen dostane usek, kde bere nejvetsi poskozeni;
# kdyz je to nerozhodne (typicky dvojzivelny poutnik, ktery ma na obou svych
# zivlech nulu), losuje se.
func _route_cluster(node: int, group: Array) -> void:
	var j: int = net.junction_index_of_node(node)
	if j < 0:
		return
	for item in group:
		var e: Enemy = item
		e.route_node = node
		e.route_sel = _auto_sel(e, j)
	var names: Array = []
	for item in group:
		names.append((item as Enemy).title())
	_note("Shluk na výhybce - výhybka ho rozdělila sama: %s." % ", ".join(names))


# VYSTUP S NEJVETSiM POSKOZENIM PRO TOHOHLE POUTNIKA. Pocita se z ELEMENTU
# vystupniho useku, ne z vezi, ktere na nem stoji - Jan (Oct 2026): "To, že
# na správné koleji nic nestojí už je hráčův problém." Pri shode se losuje.
func _auto_sel(e: Enemy, j: int) -> int:
	var lanes: Array = net.junction_lanes[j]
	if lanes.is_empty():
		return 0
	var best: float = -1.0
	var picks: Array = []
	for k in range(lanes.size()):
		var m: float = _lane_hurt(e, int(lanes[k]))
		if m > best + 0.0001:
			best = m
			picks = [k]
		elif absf(m - best) <= 0.0001:
			picks.append(k)
	if picks.is_empty():
		return 0
	if picks.size() == 1:
		return int(picks[0])
	return int(picks[_next_int(picks.size())])


# KOLIK POUTNIK NA TOMHLE USEKU DOSTANE. Jedine misto, kde se to pro potreby
# automatickeho rozřazení pocita: kmen neposkozuje vubec, neutralni usek bere
# vsem stejne (a je tedy "bezpecna volba", kdyz poutnik nema svuj protiklad)
# a elementarni usek dava nasobek z tabulky `Element`.
func _lane_hurt(e: Enemy, lane: int) -> float:
	var el: int = level.lane_element(lane)
	if el == Level.KMEN:
		return 0.0
	if el < 0 or el >= Element.COUNT:
		return Element.NEUTRAL
	return e.mult_against(el)


# ZAZNAMENEJ PRUCHOD VYHYBKOU. Efekt se prida k te, ktera ho opravdu pustila
# (kazda vyhybka ma svuj krouzek), a nese BARVU zvolene koleje - hrac z nej
# pozna, kam poutnik odesel, ne jen ze nekam odesel.
func _flash_junction(node: int, lane: int) -> void:
	junction_flash.append({"node": node, "lane": lane, "t": FLASH_TIME})


# KROUZEK PO PRUCHODU ZHASINA. Jedno misto, kde se cas efektu odcita - kdyby
# si ho obrazovka vedla sama, efekt by se s hrou rozešel.
func _fade_flash(delta: float) -> void:
	if junction_flash.is_empty():
		return
	var keep: Array = []
	for item in junction_flash:
		var f: Dictionary = item
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) > 0.0:
			keep.append(f)
	junction_flash = keep


# POLOMER KROUZKU EFEKTU pro silu `k` (0..1). Jedno misto, kde se geometrie
# efektu pocita - kresleni i snimek pro kontrolu se musi ptat tady.
#
# Krouzek zacina VEDLE znacky uzlu (ta ma polomer 0,34 r), ne na ni: kdyby
# efekt lezl po znacce, hrac by v nem videl jen "neco jako drive" a nic by mu
# to nereklo. Rozpina se ven, takze ho od znacky pozna na prvni pohled.
static func flash_radius(k: float, r0: float) -> float:
	return r0 * (0.95 + 0.75 * (1.0 - clampf(k, 0.0, 1.0)))


# JAK SILNY EFEKT NA TOMHLE UZLU PRAVE JE. Vraci {} nebo {"k": 0..1,
# "lane": int}. Obrazovka, klepnuti i testy se ptaji tady, takze se kresba
# nemuze rozejit s casem hry.
func junction_flash_at(node: int) -> Dictionary:
	var best: Dictionary = {}
	for item in junction_flash:
		var f: Dictionary = item
		if int(f["node"]) != node:
			continue
		var k: float = float(f["t"]) / FLASH_TIME
		if best.is_empty() or k > float(best["k"]):
			best = {"k": k, "lane": int(f["lane"])}
	return best


# VSECHNY EFEKTY NA TOMHLE UZLU. Pri shluku na vyhybce jich je vic - kazdy
# poutnik ma svuj krouzek v barve sve koleje. `junction_flash_at` vraci jen
# ten nejsilnejsi, coz staci klepnuti i testum; kresleni potrebuje vsechny,
# jinak by hrac videl, ze jeden poutnik odesel a druhy nekam zmizel.
func junction_flashes_at(node: int) -> Array:
	var out: Array = []
	for item in junction_flash:
		var f: Dictionary = item
		if int(f["node"]) != node:
			continue
		out.append({"k": float(f["t"]) / FLASH_TIME, "lane": int(f["lane"])})
	return out


# ---------------------------------------------------------------- strelba

# VEZE STRILEJI. Kazda vez ma svuj nabijeci cas; kdyz je nabita a ma v dosahu
# poutnika, vystreli. Vez, ktera ceka na cil, zustava NABITA (cd = 0) - kdyz
# poutnik vstoupi do dosahu, dostane zásah hned, ne az za nabijeci dobu.
#
# CIL: poutnik, kteremu do cile zbyva NEJMENE. Hrac tak neztraci rany na tom,
# kdo stejne jeste daleko; vez pomaha tam, kde to nejvic hrozi. Pri shode
# rozhoduje poradi v seznamu (determinismus).
func _fire(delta: float) -> void:
	_index_enemies()
	for titem in towers:
		var t: Tower = titem
		t.cd -= delta
		if t.cd > 0.0:
			continue
		var target: Enemy = _target_for(t)
		if target == null:
			# Nabita vez zustava nabita: az poutnik vstoupi do dosahu,
			# dostane zásah HNED, ne az za nabijeci dobu.
			t.cd = 0.0
			continue
		_shot(t, target)


# BUNKA -> POUTNICI. Jednou za snimek, protoze veze se na cil ptaji kazdy
# snimek znovu (nabita vez zustava nabita).
func _index_enemies() -> void:
	cell_enemies = {}
	if enemies.is_empty():
		return
	for item in enemies:
		var e: Enemy = item
		if not e.alive or not e.on_lane():
			continue
		if e.lane < 0 or e.lane >= net.lane_len.size():
			continue
		var c: Vector2i = net.cell_at(e.pos)
		if cell_enemies.has(c):
			var arr: Array = cell_enemies[c]
			arr.append(e)
		else:
			cell_enemies[c] = [e]


# Kdo to schytá. Poutnik, kteremu do cile zbyva NEJMENE - vez pomaha tam,
# kde to nejvic hrozi. Hleda se v bunce veze a jejim okoli (ctverec 2 bunky
# na kazdou stranu, stejne jako `Tower.in_range`), ne ve vsech poutnicich:
# vez se na cil ptá i tehdy, kdyz v dosahu nikdo neni, a prohledavat kvuli
# tomu celou desku by hru zpomalovalo s kazdou vezi a kazdym poutnikem.
func _target_for(t: Tower) -> Enemy:
	var best: Enemy = null
	var best_left: float = 1.0e12
	var r: int = t.reach()
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := Vector2i(t.cell.x + dx, t.cell.y + dy)
			if not cell_enemies.has(c):
				continue
			var arr: Array = cell_enemies[c]
			for item in arr:
				var e: Enemy = item
				# NA SVEHO SE NEUTOCI. Vez, ktera by poutnikovi stejneho
				# elementu neublizila, na nej nesmi ani vystrelit - prisla
				# by o ranu pro nekoho, komu opravdu ublizi (Jan, Oct 2026).
				if not e.can_hurt(t.element):
					continue
				var left: float = float(net.lane_len[e.lane]) - e.s
				if left < best_left:
					best_left = left
					best = e
	return best


# VYSTREL. Tady se poutnikovi jeste NEBERE nic - jen vznikne strela, ktera
# k nemu leti (viz `Shot`). Poskozeni ubira az jeji dopad.
func _shot(t: Tower, e: Enemy) -> void:
	t.cd = t.cooldown()
	shots.append(Shot.launch(t, e, net.cell_center(t.cell), e.pos,
		t.damage() * e.mult_against(t.element)))


# LET STREL. Strela leti za svym poutnikem (je to strela, ne past polozena
# na ceste), a kdyz doleti, teprve ubere zivoty. Poutnik, ktery cestou umre,
# strelu "nechá doletet" na posledni misto - strela pak vyhasi a nikoho
# jineho nezrani; rana patri tomu, na koho vez vystrelila.
func _move_shots(delta: float) -> void:
	if shots.is_empty():
		return
	var still: Array = []
	for item in shots:
		var s: Shot = item
		var live: bool = s.target != null and s.target.alive and s.target.on_lane()
		if live:
			# NAVADENA STRELA: miri na skutecnou pozici poutnika, takze
			# leti za nim a neda se "utect" - jen se neda zasahnout
			# nekdo, kdo uz umrel.
			s.aim = s.target.pos
		var step: float = s.speed * delta
		var d: float = s.pos.distance_to(s.aim)
		if d <= step:
			s.pos = s.aim
			if live:
				_impact(s.target, s.dmg)
			continue
		s.pos += (s.aim - s.pos) / d * step
		still.append(s)
	shots = still


# DOPAD. Jedine misto, kde poutnik dostava poskozeni od veze.
func _impact(e: Enemy, dmg: float) -> void:
	_damage(e, dmg)


# UBERTE ZIVOTY. Jedno misto, kde se ubira, aby se nikde nezapomnelo na
# odmenu, na hlasku ani na smrt poutnika.
func _damage(e: Enemy, dmg: float) -> void:
	e.hp -= dmg
	if e.hp <= 0.0:
		e.alive = false
		# ODMENA JE PODLE DRUHU: lehky poutnik je jen na odskok, tezky se
		# vyplati (Jan: "Rychlejší s menšími životy. Pomalejší s vyššími").
		var r: int = e.reward()
		gold += r
		_note("Poutník %s %s zničen (+%d)." % [
			Enemy.tier_name(e.tier).to_lower(), e.title(), r])


# MRTVÍ POUTNÍCI SE VYHAZUJÍ NA JEDNOM MISTE. Driv si kazda faze (pohyb,
# strelba) vedla vlastni seznam "kdo zustava" - a jakmile pribyl dopad
# strely, musela by si ho vest i strelba. Jedno misto znamena, ze "kdo je
# na desce" ma jen jednu pravdu.
func _prune() -> void:
	if enemies.is_empty():
		return
	var keep: Array = []
	for item in enemies:
		var e: Enemy = item
		if e.alive:
			keep.append(e)
	if keep.size() != enemies.size():
		enemies = keep


# ---------------------------------------------------------------- pomocne

# Ktere useky maji u sebe vez. HUD a testy se ptaji tady.
func lanes_used() -> Array:
	var seen := {}
	for item in towers:
		var t: Tower = item
		var lane: int = net.strip_lane_of(t.cell)
		if lane >= 0:
			seen[lane] = true
	return seen.keys()


func _note(msg: String) -> void:
	log.append(msg)
	if log.size() > 40:
		log.pop_front()


# Zrychlena simulace pro testy i pro "preskocit" tlacitko v UI.
func run_for(seconds: float, dt: float = 1.0 / 60.0) -> void:
	var steps: int = int(seconds / dt)
	for i in range(steps):
		step(dt)
		if phase == "lost" or phase == "won":
			return