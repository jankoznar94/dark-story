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
# Rozestup poutniku. Hrac musi stihnout prepnout vyhybku PRO KAZDEHO
# zvlast, takze dve klepnuti se musi vejit do mezery mezi dvema poutniky.
# Test to hlida pres ENEMY_SPEED * SPAWN_INTERVAL.
const SPAWN_INTERVAL := 1.05
const BUILD_TIME := 6.0
const WAVE_BONUS := 40
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

var net: Network = Network.new()
var bonuses: Array = []
var enemies: Array = []
var gold: int = START_GOLD
var lives: int = START_LIVES
var wave: int = 0
var phase: String = "build"
var build_timer: float = BUILD_TIME
var spawn_left: int = 0
var spawn_timer: float = 0.0
var rng: int = 20261009
var log: Array = []
# Vypnuto v testech, ktere sleduji jednoho poutnika. V hre vzdy zapnuto.
var auto_wave: bool = true


func setup(r: Rect2, scale_hint: float = 1.0, bar_top: float = 1.0e9) -> void:
	rebuild_network(r, scale_hint, bar_top)
	bonuses = []
	enemies = []
	gold = START_GOLD
	lives = START_LIVES
	wave = 0
	phase = "build"
	build_timer = BUILD_TIME
	spawn_left = 0
	spawn_timer = 0.0
	log = []


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
	net = Network.new()
	net.build(r, sc, bt)


# ---------------------------------------------------------------- bonusy

func bonus_at(lane: int, slot: int) -> Bonus:
	for b in bonuses:
		var bo: Bonus = b
		if bo.lane == lane and bo.slot == slot:
			return bo
	return null


func try_build(lane: int, slot: int, element: int) -> bool:
	if lane < 0 or lane >= Network.LANES:
		_note("Neplatný úsek.")
		return false
	if bonus_at(lane, slot) != null:
		_note("Na tom místě už něco stojí.")
		return false
	# BONUS PATRI JEN NA USEK SVÉHO ZIVLU. Na neutralni usek nesmi nic -
	# nema co posilovat, uz poskozuje vsechny stejne. Pravidlo je tady,
	# volat ji s necim jinym nesmi projit.
	if not Network.lane_accepts(lane, element):
		if Network.lane_is_neutral(lane):
			_note("Neutrální úsek nemá element — nedá se na něm stavět.")
		else:
			_note("Na úsek %s patří jen bonus %s." % [
				Element.name_of(Network.lane_element(lane)),
				Element.name_of(Network.lane_element(lane))])
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
	var len_px: float = float(net.lane_len[lane])
	if len_px <= 0.001 or e.speed <= 0.0:
		return 0.0
	var traverse: float = len_px / e.speed
	var neutral: bool = Network.lane_is_neutral(lane)
	var total: float = ZONE_DMG * lane_mult(lane) * Element.lane_multiplier(
		e.element, Network.lane_element(lane), neutral)
	return total / traverse


# ---------------------------------------------------------------- vyhybka

func set_switch(lane: int) -> void:
	if lane < 0 or lane >= Network.LANES:
		return
	net.switch_lane = lane
	if Network.lane_is_neutral(lane):
		_note("Výhybka nastavena na neutrální úsek.")
	else:
		_note("Výhybka nastavena na %s." % Element.name_of(Network.lane_element(lane)))


func switch_lane() -> int:
	return net.switch_lane


# Ktery zivel se na ten usek stavi. NENI to volba hrace: usek nese svuj
# zivel a jen ten tam muze stat. UI to jen cte.
func build_element(lane: int) -> int:
	return Network.lane_element(lane)


# ---------------------------------------------------------------- vlny

func start_wave() -> void:
	wave += 1
	phase = "wave"
	spawn_left = 3 + wave
	spawn_timer = 0.0
	_note("Vlna %d zacina (%d poutniku)." % [wave, spawn_left])


func _spawn(enemy_el: int) -> void:
	var e := Enemy.new()
	e.element = enemy_el
	e.max_hp = BASE_HP * pow(1.0 + HP_GROWTH, float(wave - 1))
	e.hp = e.max_hp
	e.speed = ENEMY_SPEED
	e.lane = -1
	e.s = 0.0
	enemies.append(e)


# Verejny vstup pro nastroje (nahled, diagnostika). Hra sama spawnuje
# jen pres vlny, takze se tohle v hernim kode nikde nevola.
func debug_spawn(enemy_el: int) -> Enemy:
	_spawn(enemy_el)
	var e: Enemy = enemies[enemies.size() - 1]
	return e


func _next_int(limit: int) -> int:
	rng = (rng * 1103515245 + 12345) & 0x7fffffff
	return (rng / 65536) % limit


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
	else:
		if spawn_left > 0:
			spawn_timer -= delta
			if spawn_timer <= 0.0:
				spawn_timer = SPAWN_INTERVAL
				spawn_left -= 1
				_spawn(_next_int(Element.COUNT))

	_move_enemies(delta)
	_apply_damage(delta)

	if phase == "wave" and spawn_left == 0 and enemies.is_empty():
		wave_done()


func wave_done() -> void:
	var bonus: int = WAVE_BONUS + 10 * wave
	gold += bonus
	phase = "build"
	build_timer = BUILD_TIME
	_note("Vlna %d odrazena (+%d zlata)." % [wave, bonus])


func _move_enemies(delta: float) -> void:
	var still: Array = []
	for item in enemies:
		var e: Enemy = item
		if not e.alive:
			continue
		e.s += e.speed * delta
		if not e.on_lane():
			if e.s >= net.trunk_len:
				e.s -= net.trunk_len
				e.lane = net.switch_lane
		else:
			if e.s >= net.lane_len[e.lane]:
				e.leaked = true
				e.alive = false
				lives -= 1
				if Network.lane_is_neutral(e.lane):
					_note("Poutnik %s došel na neutrální výstup (-1 život)." %
						Element.name_of(e.element))
				else:
					_note("Poutnik %s došel na konec úseku (-1 život)." %
						Element.name_of(e.element))
				continue
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
