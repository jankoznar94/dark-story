class_name Game
extends RefCounted

# CELA herni logika. Zadne kresleni, zadne nody, zadny Input.
# Diky tomu se da hra testovat headless a simulovat zrychlene.

const START_GOLD := 260
const START_LIVES := 12
const BASE_HP := 70.0
const HP_GROWTH := 0.10
const ENEMY_SPEED := 52.0
const REWARD := 12
# Rozestup poutniku. Hrac musi stihnout prepnout vyhybku PRO KAZDEHO
# zvlast, takze dvě vyhybky (dva stisky) se musi vejit do mezery mezi
# dvema poutniky. Pri 0.62 s to neslo - druhy uz byl na vyhybce, nez
# hrac doklikal prvni. Test to hlida pres ENEMY_SPEED * SPAWN_INTERVAL.
const SPAWN_INTERVAL := 1.05
const BUILD_TIME := 6.0
const WAVE_BONUS := 40

var net: Network = Network.new()
var towers: Array = []
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
	towers = []
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


# ---------------------------------------------------------------- ekonomika

func tower_at(lane: int, slot: int) -> Tower:
	for t in towers:
		var tw: Tower = t
		if tw.lane == lane and tw.slot == slot:
			return tw
	return null


func try_build(lane: int, slot: int, element: int) -> bool:
	if lane < 0 or lane >= Network.LANES:
		_note("Neplatná kolej.")
		return false
	if tower_at(lane, slot) != null:
		_note("Kolej už má věž.")
		return false
	# VEZ PATRI JEN NA KOLEJ SVÉHO ZIVLU. Toto je jedine pravidlo staveni
	# a je vynucene tady - volat ji s jinym zivlem nesmi projit.
	if not Network.lane_accepts(lane, element):
		_note("Na kolej %s patří jen věže %s." % [
			Element.name_of(Network.lane_element(lane)), Element.name_of(Network.lane_element(lane))])
		return false
	if gold < Tower.COST:
		_note("Málo zlata na věž (%d)." % Tower.COST)
		return false
	gold -= Tower.COST
	var t := Tower.new()
	t.lane = lane
	t.slot = slot
	t.element = element
	towers.append(t)
	_note("Věž %s postavena." % Element.name_of(element))
	return true


func try_upgrade(lane: int, slot: int) -> bool:
	var t := tower_at(lane, slot)
	if t == null:
		_note("Prazdne misto.")
		return false
	if not t.can_upgrade():
		_note("Vez je na maximu.")
		return false
	if gold < Tower.UPGRADE_COST:
		_note("Malo zlata na vylepseni (%d)." % Tower.UPGRADE_COST)
		return false
	gold -= Tower.UPGRADE_COST
	t.level += 1
	_note("Vez vylepsena na uroven %d." % t.level)
	return true


# ---------------------------------------------------------------- vyhybka

func set_switch(lane: int) -> void:
	if lane < 0 or lane >= Network.LANES:
		return
	net.switch_lane = lane
	_note("Výhybka nastavena na %s." % Element.name_of(Network.lane_element(lane)))


func switch_lane() -> int:
	return net.switch_lane


# Ktery zivel se na te kolej stavi. NENI to volba hrace: kolej nese svuj
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
				_note("Poutnik %s dosel do svatyne (-1 zivot)." % Element.name_of(e.element))
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
			var dps := 0.0
			for item2 in towers:
				var t: Tower = item2
				if t.lane != e.lane:
					continue
				dps += t.dps() * Element.multiplier(e.element, t.element)
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
	for item in towers:
		var t: Tower = item
		seen[t.lane] = true
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
