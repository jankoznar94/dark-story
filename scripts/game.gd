class_name Game
extends RefCounted

# CELA herni logika. Zadne kresleni, zadne nody, zadny Input.
# Diky tomu se da hra testovat headless a simulovat zrychlene.
#
# POSKOZENI DELA CELEK USEKU, ne vez. Usek je dmg zona: cim dele poutnik
# po elementarnim useku jde, tim vic ran dostane. Bonusy na useku
# posiluji CELOU dmg zonu, ale samy neutoci.
#
# DVE VEZE VYPOCTU, na kterych stoji cela hra:
#   * neutralni usek poskozuje vsechny presne 100 % - spolehlivy zaklad,
#   * elementarni usek da vlastnimu zivlu 0 %, jeho protikladu 200 %
#     a zbylym dvema 50 %. Poslat poutnika na jeho vlastni usek je tedy
#     ZTRATA - projde bez skrabnuti.
# Hrac prepina vyhybku pro kazdeho poutnika zvlast a jeho jedina investice
# je bonus do useku. Investice ma cenu jen tehdy, kdyz na usek dokaze
# poutniky poslat - to je cele napeti hry.

const START_GOLD := 260
const START_LIVES := 12
const BASE_HP := 70.0
const HP_GROWTH := 0.10
const ENEMY_SPEED := 52.0
const REWARD := 12
# KOLO NENI VLNA Z TD. Jan: "Asi nebudeme dělat jednotlivé vlny jako u TD
# žánru. ... Kolo bude mít časový limit. Třeba 2 minuty. Během této doby
# budou v náhodném pořadí a intervalech (min 1s, max 5s) chodit nepřátelé
# z náhodných vstupů. Po uplynutí časového limitu hra čeká na zabití všech
# nepřátel nebo porážku hráče."
#
# Takze kolo = CASOVE OKNO, ve kterem vstupy jen TECOU: nahodny zivel,
# nahodny vstup, nahodna mezera 1-5 s. Pocet poutniku v kole NENI dane
# cislo (driv `3 + vlna`) - je to dusledek okna a prumerne mezery, na
# zakladni desce ~40 za 2 minuty. Kolo konci teprve tehdy, kdyz je deska
# PRAZDNA, takze hrac nikdy neprijde o cas na dobiti zbytku.
const ROUND_TIME := 120.0
# NEJKRATSI A NEJDELSI MEZERA MEZI DVA POUTNIKY. Hrac musi stihnout
# prepnout vyhybku pro kazdeho zvlast, takze i ta nejkratsi mezera je
# hratelnostni vec: 1 s = 52 px na zakladni rychlosti.
const ROUND_GAP_MIN := 1.0
const ROUND_GAP_MAX := 5.0
const BUILD_TIME := 6.0
const ROUND_BONUS := 40
# Poskozeni, ktere da usek poutnikovi za CELE PROJETI sve delky pri
# jednotkovem nasobku. NENI to poskozeni za sekundu - to by záviselo na
# tom, jak je displej velky (na malem telefonu je usek kratsi v pixelech,
# takze by poutnik dostal min ran a hra by se rozbila podle zarizeni).
# Takto je "usek da X" vlastnost useku, ne obrazovky ani rychlosti.
#
# Cisla: neutralni usek 30 (43 % z 70 HP), elementarni na protiklad 60
# (poutnika ZRANI, ale nezabije - k zabiti je potreba investice), s jedním
# bonusem x3 = 180 (zabije). Presne to je jadro hry.
const ZONE_DMG := 30.0

var level: Level = null
var net: Network = Network.new()
var bonuses: Array = []
var enemies: Array = []
var gold: int = START_GOLD
var lives: int = START_LIVES
var round: int = 0
var phase: String = "build"
var build_timer: float = BUILD_TIME
# KOLIK SEKUND ZBYVA DO KONCE VSTUPU V TOMHLE KOLE. Nula znamena "vstupy
# skoncity" - hra pak jeste ceka, nez desku dobehnou zabit nebo dojit.
var round_left: float = 0.0
# DO KDY VSTOUPI DALSÍ POUTNIK (v sekundach). Neni to perioda: po kazdem
# vstupu se losuje nova mezera 1-5 s, takze hrac vi, ze jich prijde hodne,
# ale ne kdy presne.
var spawn_wait: float = 0.0
# Kolik poutniku uz do TOHOTO kola vstoupilo. Kolo nema naplanovany pocet;
# tenhle pocitac je jedina odpoved na "kolik jich bylo" (HUD, souhrn kola).
var spawned: int = 0
var rng: int = 20261009
var log: Array = []
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
var auto_round: bool = true
# VYHYBKY. Kazda si drzi svou volbu - index useku, ktery z ni vede. Je to stav
# ROZEHRANE PARTIE, ne level: proto to neni v Levelu a proto se to pri zmene
# velikosti okna neztrati (sit se prelozi, volba hrace zustava).
var switch_sel: Array = []


func setup(r: Rect2, scale_hint: float = 1.0, bar_top: float = 1.0e9,
		level_data: Level = null) -> void:
	level = level_data if level_data != null else Level.base()
	switch_sel = []
	rebuild_network(r, scale_hint, bar_top)
	bonuses = []
	enemies = []
	gold = level.gold
	lives = level.lives
	lives_max = level.lives
	round = 0
	phase = "build"
	build_timer = BUILD_TIME
	round_left = 0.0
	spawn_wait = 0.0
	spawned = 0
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


# ---------------------------------------------------------------- bonusy

func bonus_at(lane: int, slot: int) -> Bonus:
	for b in bonuses:
		var bo: Bonus = b
		if bo.lane == lane and bo.slot == slot:
			return bo
	return null


func try_build(lane: int, slot: int, element: int) -> bool:
	if lane < 0 or lane >= net.lane_count():
		_note("Neplatný úsek.")
		return false
	if slot < 0 or slot >= net.slot_count(lane):
		_note("Neplatné místo.")
		return false
	if bonus_at(lane, slot) != null:
		_note("Na tom místě už něco stojí.")
		return false
	# BONUS PATRI JEN NA USEK SVÉHO ZIVLU. Na neutralni usek nesmi nic -
	# nema co posilovat, uz poskozuje vsechny stejne. Pravidlo je tady,
	# volat ji s necim jinym nesmi projit.
	if not net.lane_accepts(lane, element):
		if net.lane_is_neutral(lane):
			_note("Neutrální úsek nemá element — nedá se na něm stavět.")
		elif net.lane_is_kmen(lane) or net.lane_is_entry(lane):
			_note("Tenhle úsek neposkozuje — bonus na něm nemá co posílit.")
		else:
			_note("Na úsek %s patří jen bonus %s." % [
				net.level.lane_type_name(lane),
				net.level.lane_type_name(lane)])
		return false
	if gold < Bonus.COST:
		_note("Málo zlata na bonus (%d)." % Bonus.COST)
		return false
	gold -= Bonus.COST
	var b := Bonus.new()
	b.lane = lane
	b.slot = slot
	b.element = element
	bonuses.append(b)
	_note("Bonus %s postaven — posiluje celý úsek." % Element.name_of(element))
	return true


func try_upgrade(lane: int, slot: int) -> bool:
	var b := bonus_at(lane, slot)
	if b == null:
		_note("Prazdne misto.")
		return false
	if not b.can_upgrade():
		_note("Bonus je na maximu.")
		return false
	if gold < Bonus.UPGRADE_COST:
		_note("Malo zlata na vylepseni (%d)." % Bonus.UPGRADE_COST)
		return false
	gold -= Bonus.UPGRADE_COST
	b.level += 1
	_note("Bonus vylepsen na uroven %d." % b.level)
	return true


# Jak silna je dmg zona na tomhle useku. Nasobi se VSEMI bonusy, ktere
# na nem stoji - bonus posiluje CELOU dmg zonu, ne jen sve misto.
func lane_mult(lane: int) -> float:
	var m := 1.0
	for item in bonuses:
		var bo: Bonus = item
		if bo.lane == lane:
			m *= bo.mult()
	return m


# Kolik poskozeni tenhle poutnik dostane ZA SEKUNDU na svem useku.
# Prepocitava se z ZONE_DMG pres dobu projeti useku, takze CELE PROJETI
# da vzdy stejne poskozeni bez ohledu na velikost displeje.
func dps_on(e: Enemy) -> float:
	if not e.on_lane():
		return 0.0
	var lane: int = e.lane
	# VSTUPNI USEK A KMEN NEPOSKOZUJI. Poutnik po vstupnim useku teprve
	# prichazi - hrac jeste nemel jakkoli sanci neco udelat, takze by to
	# bylo poskozeni "zdarma". Kmen je tataz vec, jen si ho hrac kresli sam.
	if not net.lane_deals_damage(lane):
		return 0.0
	var len_px: float = float(net.lane_len[lane])
	if len_px <= 0.001 or e.speed <= 0.0:
		return 0.0
	var traverse: float = len_px / e.speed
	var neutral: bool = net.lane_is_neutral(lane)
	var dmg: float = level.zone_dmg if level != null else ZONE_DMG
	var total: float = dmg * lane_mult(lane) * Element.lane_multiplier(
		e.element, net.lane_element(lane), neutral)
	return total / traverse


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


# Ktery zivel se na ten usek stavi. NENI to volba hrace: usek nese svuj
# zivel a jen ten tam muze stat. UI to jen cte.
func build_element(lane: int) -> int:
	return net.lane_element(lane)


# ---------------------------------------------------------------- kola

func start_round() -> void:
	round += 1
	phase = "round"
	round_left = ROUND_TIME
	if level != null:
		round_left = level.round_time
	round_left = maxf(round_left, 1.0)
	# PRVNI POUTNIK VSTUPUJE HNED: kdyby se losovalo i prvni cekani, hrac by
	# na zacatku kola koukal do prazdne mapy a nevedel, ze kolo bezi.
	spawn_wait = 0.0
	spawned = 0
	var msg: String = "Kolo %d začíná (%.0f s)." % [round, round_left]
	# POUTNIK BEZ PROTIKLADU SE NEPOSILA (viz Level.spawn_elements). Hlaska to
	# musi rict: kdyz by hrac videl, ze nechodi Zeme, hledal by chybu v siti -
	# pritom staci do mapy pridat protikladny usek.
	if level != null:
		var bad: Array = level.unkillable_elements()
		if not bad.is_empty():
			var names: String = ""
			for e in bad:
				names += ("" if names.is_empty() else ", ") + Element.name_of(e)
			msg += " %s nemá v mapě protiklad — neposílá se." % names
	_note(msg)


# MEZERA DO DALSÍHO VSTUPU. Losuje se pro kazdou mezeru zvlast z rozpeti
# 1-5 s, takze vstupy nejsou perioda (hrac nesmi videt "kazde 3 s"). Nahodne
# cislo je z TEHOZ rng jako zivly poutniku, takze hra zustava
# deterministicka - test na to ma kontrolu.
func _next_gap() -> float:
	var t: float = float(_next_int(1001)) / 1000.0
	return ROUND_GAP_MIN + (ROUND_GAP_MAX - ROUND_GAP_MIN) * t


# Bezi jeste vstupy? Jedine misto, kde se to rozhoduje - HUD, step i testy
# se musi ptat tady, jinak by se "kolo skoncilo" pocitalo na trech mistech.
func spawning() -> bool:
	return phase == "round" and round_left > 0.0


# Jak dlouho poutnik mapou jde: vstupni usek + nejdelsi usek, v sekundach.
# Je to HORNÍ odhad trasy (hrac muze poslat poutnika i kratkou vetvi),
# takze kolo z nej vychazi o chlup delsi, nez jak doopravdy skonci.
func walk_time() -> float:
	var sp: float = _speed()
	var entry: float = 0.0
	if net.entry_lane >= 0 and net.entry_lane < net.lane_len.size():
		entry = float(net.lane_len[net.entry_lane])
	var longest: float = 0.0
	for i in range(net.lane_count()):
		longest = maxf(longest, float(net.lane_len[i]))
	return maxf((entry + longest) / sp, 0.5)


func _speed() -> float:
	var sp: float = level.speed if level != null else ENEMY_SPEED
	return maxf(sp, 1.0)


func _spawn(enemy_el: int) -> void:
	var e := Enemy.new()
	e.element = enemy_el
	e.max_hp = BASE_HP * pow(1.0 + HP_GROWTH, float(round - 1))
	e.hp = e.max_hp
	e.speed = level.speed if level != null else ENEMY_SPEED
	# POUTNIK VSTUPUJE NA VSTUPNI USEK. Vstup do mapy je v mrizce normalni
	# usek ze startu (od vychoziho stavu kmen, takze neposkozuje). Vstupu
	# muze byt vic a VSTUP SE LOSUJE - driv se kmeny stridaly po poradi
	# ("kazdy druhy zleva"), coz hrac odhalil jako vzor.
	# Kdyby mapa zadny start nemela, poutnik se neobjevi vubec.
	if net.entry_lanes.is_empty():
		return
	e.lane = int(net.entry_lanes[_next_int(net.entry_lanes.size())])
	e.s = 0.0
	spawned += 1
	enemies.append(e)


# Verejny vstup pro nastroje (nahled, diagnostika). Hra sama spawnuje
# jen pres vlny, takze se tohle v hernim kode nikde nevola.
func debug_spawn(enemy_el: int) -> Enemy:
	_spawn(enemy_el)
	if enemies.is_empty():
		return null
	var e: Enemy = enemies[enemies.size() - 1]
	return e

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


# ---------------------------------------------------------------- krok

func step(delta: float) -> void:
	if phase == "lost" or phase == "won":
		return

	if phase == "build":
		build_timer -= delta
		if build_timer <= 0.0:
			build_timer = 0.0
			if auto_round:
				start_round()
	elif phase == "round":
		# VSTUPY TECOU PO CELOU DOBU KOLA. Po kazdem poutnikovi se losuje
		# nova mezera 1-5 s (viz _next_gap), takze nikdo nevi, kolik jich
		# prijde - vi jen, dokdy. `while` tu je kvuli velkemu kroku (testy
		# umi skocit o par sekund), ale mezera >= 1 s ho necha bezet jednou.
		round_left -= delta
		spawn_wait -= delta
		var guard: int = 0
		while round_left > 0.0 and spawn_wait <= 0.0 and guard < 60:
			guard += 1
			var el: int = _next_element()
			if el >= 0:
				_spawn(el)
			spawn_wait += _next_gap()
		if round_left <= 0.0:
			round_left = 0.0
			phase = "clear"
			_note("Kolo %d: vstupy skončily, dočisti desku." % round)

	_move_enemies(delta)
	_apply_damage(delta)

	# KOLO KONCI AZ PRAZDNOU DESKOU. Kdyz vstupy skoncily a na desce uz nic
	# neni, kolo je odrazene. Dokud se poutnici dobíjejí, hra ceka - hrac
	# tak nikdy neprijde o kolo s poutniky na ceste.
	if phase == "clear" and enemies.is_empty():
		round_done()


func round_done() -> void:
	var bonus: int = ROUND_BONUS + 10 * round
	gold += bonus
	phase = "build"
	build_timer = BUILD_TIME
	_note("Kolo %d odraženo (+%d zlata)." % [round, bonus])


func _move_enemies(delta: float) -> void:
	var still: Array = []
	for item in enemies:
		var e: Enemy = item
		if not e.alive:
			continue
		# Poutnik mimo trasu znamena, ze mapa nema start. Nema kam jit.
		if not e.on_lane():
			e.leaked = true
			e.alive = false
			lives -= 1
			continue
		e.s += e.speed * delta
		if e.s < float(net.lane_len[e.lane]):
			still.append(e)
			continue
		# KONEC USEKU = POUTNIK JE V UZLU. Tam se rozhodne:
		#   vyhybka             - hrac svou volbou posle poutnika na jeden
		#                         ze svych vystupu (rozhoduje se az ted,
		#                         v okamziku pruchodu),
		#   spojka / uzel / start - jediny vystup, zadne rozhodovani,
		#   cil                - konec cesty, stoji zivot.
		var nd: int = net.lane_end_node(e.lane)
		var nxt: int = -1
		if nd >= 0:
			var j: int = net.junction_index_of_node(nd)
			var sel: int = 0
			if j >= 0:
				if switch_sel.size() != net.junction_count():
					_sync_switch()
				sel = int(switch_sel[j])
			nxt = level.next_lane(nd, sel)
		if nxt < 0 or nxt >= net.lane_count():
			e.leaked = true
			e.alive = false
			lives -= 1
			if nd >= 0 and int(net.node_kind[nd]) == Level.CIL:
				_note("Poutnik %s došel do cíle (-1 život)." % Element.name_of(e.element))
			else:
				_note("Poutnik %s zabloudil (-1 život)." % Element.name_of(e.element))
			continue
		e.lane = nxt
		e.s = 0.0
		still.append(e)
	enemies = still


func _apply_damage(delta: float) -> void:
	var keep: Array = []
	for item in enemies:
		var e: Enemy = item
		if not e.alive:
			continue
		if e.on_lane():
			# DMG ZONA CELEHO USEKU. Neutralni usek dava vzdy 100 %,
			# elementarni 0 / 50 / 200 podle toho, kdo po nem jde.
			var dps: float = dps_on(e)
			e.hp -= dps * delta
			if e.hp <= 0.0:
				e.alive = false
				gold += REWARD
				_note("Poutnik %s znicen (+%d)." % [Element.name_of(e.element), REWARD])
				continue
		keep.append(e)
	enemies = keep
	if lives <= 0:
		phase = "lost"
		_note("PROHRA.")


# ---------------------------------------------------------------- pomocne

func lanes_used() -> Array:
	var seen := {}
	for item in bonuses:
		var b: Bonus = item
		seen[b.lane] = true
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