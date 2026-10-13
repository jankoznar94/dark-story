extends SceneTree

# MERENI OBTIZNOSTI. Neni to test (nic nehlida), je to nastroj: zahraje
# zakladni desku za "slusneho hrace" (vsechny poutniky posila do jednoho
# useku, kde stoji veze, a nakupuje, dokud ma zlato) a vypise, co se deje
# vlnu po vlne.
#
# PROC TO TU JE: Jan (Oct 2026) popsal dve selhani balancu - "zvolis jednu
# spravnou kombinaci vezi a nikdo neprojde" a "zvolis spatne a nemas penize
# na dalsi veze, takze jsi odsouzen k zahube". Cisla, ktera to maji rozhodit,
# se nedaji odhadnout od stolu: zalezi na delce useku (cas v dostrelu), na
# kadence vezi a na tom, kolik vlna zaplati.
#
#   ~/tools/godot/godot4 --headless --path . --script res://tools/balance_sim.gd
#
# Vystup: radky po vlnach pro kazdou strategii ("co udelal hrac") a souhrn.

const DT := 1.0 / 30.0
const MAX_WAVES := 25
# Dve rozliseni: 960x600 je referencni, 932x430 je telefon. Useky jsou na
# nich ruzne dlouhe, takze se meni i cas, ktery poutnik stravi v dostrelu.
const ARENAS := [
	{"tag": "960x600", "r": Rect2(0.0, 0.0, 960.0, 600.0)},
	{"tag": "932x430", "r": Rect2(0.0, 0.0, 932.0, 430.0)},
]


# LADENI SE DĚLÁ VE SMYČCE, takže nastroj bere argumenty:
#   --only <text>  hraje jen strategie, jejichz jmeno obsahuje text
#   --waves <n>    kolik vlny nejdal
#   --one-arena    jen 960x600 (sweep cisel ma byt rychly)
func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var only: String = ""
	var max_waves: int = MAX_WAVES
	var one: bool = false
	var sweep: String = ""
	for i in range(args.size()):
		var a: String = str(args[i])
		if a == "--only" and i + 1 < args.size():
			only = str(args[i + 1])
		elif a == "--waves" and i + 1 < args.size():
			max_waves = int(str(args[i + 1]))
		elif a == "--sweep" and i + 1 < args.size():
			sweep = str(args[i + 1])
		elif a == "--one-arena":
			one = true
	if sweep != "":
		_sweep(sweep, max_waves)
		quit(0)
		return
	for a in ARENAS:
		if one and str(a["tag"]) != "960x600":
			continue
		var arena: Rect2 = a["r"]
		print("=== arena %s ===" % str(a["tag"]))
		for pol in _policies():
			if only != "" and not str(pol["name"]).contains(only):
				continue
			var res: Dictionary = _run(pol, arena, max_waves)
			_print_policy(pol, res["rows"])
	quit(0)


func _policies() -> Array:
	return [
		{"name": "nic (bez obrany)", "max_towers": 0, "neutral": true, "upgrade": true},
		{"name": "1 neutralni vez", "max_towers": 1, "neutral": true, "upgrade": true},
		{"name": "1 zivlova vez", "max_towers": 1, "neutral": false, "upgrade": true},
		{"name": "stavet (neutralni)", "max_towers": 99, "neutral": true, "upgrade": true},
		{"name": "stavet (zivlove)", "max_towers": 99, "neutral": false, "upgrade": true},
		# CHYTREJSI HRAC: nejdriv rozlozi nekolik vezi po ceste (kazda vez
		# prida cas v dostrelu), a teprve pak vylepsuje. Vylecovani prvni veze
		# je na zacatku hry horsi investice - jedna vez na 3. urovni stoji
		# 320 a za to jsou skoro ctyri veze na 1. urovni.
		{"name": "rozlozit (6 vezi, pak vylepsovat)", "max_towers": 99,
			"neutral": true, "upgrade": true, "build_first": 6},
		# STROPY POCTU VEZI: kolik toho hrac stihne postavit, nez ho vlny
		# dobehnou. "45" je plna deska koridoru (strop geometrie), 10 a 20 jsou
		# hraci, kteri maji na desce jen cast toho, co by se veslo.
		{"name": "strop 20 vezi", "max_towers": 20, "neutral": true,
			"upgrade": true, "build_first": 6},
		{"name": "strop 10 vezi", "max_towers": 10, "neutral": true,
			"upgrade": true, "build_first": 6},
	]


# PROHLEDANI JEDNOHO CISLA. Ladi se podle dvou cisel: kdy poprve neco projde
# ("prvni prulom") a kdy hrac umre ("konec"). Cil je, aby PLNÁ deska vezi
# (nejlepsi hrac, jakeho si dovedu predstavit) prorazila kolem 12.-15. vlny -
# do te doby ma hrac stavet a ucit se, potom uz jen drzi, co muze.
func _sweep(text: String, max_waves: int) -> void:
	var pol: Dictionary = {
		"name": "rozlozit (6 vezi, pak vylepsovat)", "max_towers": 99,
		"neutral": true, "upgrade": true, "build_first": 6,
	}
	print("  rust   prulom  konec  proslo  zivoty   zlato  vezi")
	for part in text.split(","):
		var gr: float = float(str(part).strip_edges())
		var res: Dictionary = _run(pol, Rect2(0.0, 0.0, 960.0, 600.0), max_waves, gr)
		var rows: Array = res["rows"]
		var last: Dictionary = rows[rows.size() - 1]
		print("  %.3f %7d %6d %7d %7d %7d %5d" % [
			gr, _first_leak(rows),
			int(last["wave"]) if int(last["lives"]) <= 0 else 0,
			_total_leak(rows), int(last["lives"]), int(last["gold"]),
			int(last["towers"])])


func _run(policy: Dictionary, arena: Rect2, max_waves: int = MAX_WAVES,
		growth: float = -1.0) -> Dictionary:
	var g := Game.new()
	g.auto_wave = false
	g.setup(arena, 1.0, 1.0e9, Level.base())
	g.hp_growth = growth if growth >= 0.0 else Game.HP_GROWTH
	var corridor: int = _longest_lane(g)
	var st := {
		"g": g, "policy": policy, "corridor": corridor,
		"cells": _ordered_cells(g, corridor),
	}
	var rows: Array = []
	for n in range(1, max_waves + 1):
		var lives_before: int = g.lives
		var size: int = g.wave_size(n)
		var hp: float = _wave_hp(g, n)
		_spend(st)
		_align(g, st)
		g.start_wave()
		var guard: int = 0
		while g.phase != "build" and g.phase != "lost" and guard < 400000:
			_align(g, st)
			g.step(DT)
			guard += 1
			_spend(st)
		rows.append({
			"wave": n, "size": size, "hp": hp, "leak": lives_before - g.lives,
			"lives": g.lives, "gold": g.gold, "towers": g.towers.size(),
			"tower_gold": _spent_in_towers(g), "phase": g.phase,
		})
		if g.phase == "lost":
			break
	return {"rows": rows}


func _print_policy(pol: Dictionary, rows: Array) -> void:
	print("--- %s ---" % str(pol["name"]))
	print("  vlna  poutniku   zivoty vlny   proslo  zivoty  zlato  veze")
	for row in rows:
		var r: Dictionary = row
		print("  %4d %9d %12.0f %8d %7d %6d %5d" % [
			int(r["wave"]), int(r["size"]), float(r["hp"]), int(r["leak"]),
			int(r["lives"]), int(r["gold"]), int(r["towers"])])
	var last: Dictionary = rows[rows.size() - 1]
	print("  ...vydrzel %d vln, prosel(o) %d poutniku, zbyva %d zivotu, zlato %d, vezi %d"
		% [int(last["wave"]), _total_leak(rows), int(last["lives"]),
			int(last["gold"]), int(last["towers"])])
	# PRVNI PRULOM A KONEC: dve cisla, podle kterych se ladi obtiznost.
	print("  ...prvni prulom: vlna %d, konec: vlna %d"
		% [int(_first_leak(rows)), int(last["wave"]) if int(last["lives"]) <= 0 else 0])


func _first_leak(rows: Array) -> int:
	for row in rows:
		if int(row["leak"]) > 0:
			return int(row["wave"])
	return 0


func _total_leak(rows: Array) -> int:
	var s: int = 0
	for row in rows:
		s += int(row["leak"])
	return s


func _spent_in_towers(g: Game) -> int:
	var s: int = 0
	for item in g.towers:
		var t: Tower = item
		s += t.spent
	return s


# ---------------------------------------------------------------- hrac

# NEJDELSI USEK JE KORIDOR: poutnik v nem stravi nejvic casu, takze se v nem
# vyplati mit veze.
func _longest_lane(g: Game) -> int:
	var best: int = 0
	for i in range(g.net.lane_count()):
		if float(g.net.lane_len[i]) > float(g.net.lane_len[best]):
			best = i
	return best


# POSILA TENHLE USEK POUTNIKY AZ DO KORIDORU? (BFS po grafu.) Hrac to vi z
# mapy; hra to nikde nepocita, takze si to simulator musi umet sam.
func _leads_to(lv: Level, lane: int, target: int) -> bool:
	if lane == target:
		return true
	var seen := {}
	var stack: Array = [lane]
	while not stack.is_empty():
		var l: int = stack.pop_back()
		if seen.has(l):
			continue
		seen[l] = true
		var n: int = lv.lane_end_node(l)
		if n < 0:
			continue
		for item in lv.lanes_from(n):
			var nl: int = item
			if nl == target:
				return true
			if not seen.has(nl):
				stack.append(nl)
	return false


# VOLBA VYHYBEK: kamkoli muze hrac poslat poutnika, posle ho do koridoru.
func _align(g: Game, st: Dictionary) -> void:
	var target: int = int(st["corridor"])
	for j in range(g.net.junction_count()):
		var lanes: Array = g.net.junction_lanes[j]
		for k in range(lanes.size()):
			if _leads_to(g.level, int(lanes[k]), target):
				g.switch_sel[j] = k
				break


# BUNKY PASU KORIDORU, SERAZENE PODEL CESTY. Hrac je stavi v tomto poradi,
# takze se veze rozlozi po cele delce useku (a poutnik jich mine vic).
func _ordered_cells(g: Game, lane: int) -> Array:
	var lane_cells: Array = g.level.lane_cells(lane)
	var out: Array = []
	for item in g.net.strip_cells:
		var c: Vector2i = item
		if g.net.strip_lane_of(c) != lane:
			continue
		var best_i: int = 0
		var best_d: float = 1.0e12
		for i in range(lane_cells.size()):
			var lc: Vector2i = lane_cells[i]
			var d: float = absf(float(lc.x - c.x)) + absf(float(lc.y - c.y))
			if d < best_d:
				best_d = d
				best_i = i
		out.append({"cell": c, "along": best_i})
	out.sort_custom(func(a, b): return int(a["along"]) < int(b["along"]))
	var cells: Array = []
	for row in out:
		cells.append(row["cell"])
	return cells


# NAKUPOVANI. Hrac nejdriv vylepsi, co ma (je to levnejsi nez novy vez na
# stejny ucinek), a teprve pak stavi novou - tak to dela clovek, ktery vi, ze
# kazda vez stoji jen u sveho useku.
func _spend(st: Dictionary) -> void:
	var g: Game = st["g"]
	var pol: Dictionary = st["policy"]
	var guard: int = 0
	while guard < 200:
		guard += 1
		# VYLEPSOVAT SE ZACINA AZ PO `build_first` VEZI: do te doby je lepsi
		# pokryt cestu (kazda vez prida cas v dostrelu), ne posilovat jednu.
		if g.towers.size() >= int(pol.get("build_first", 0)) and _try_upgrade(g, pol):
			continue
		if g.towers.size() < int(pol["max_towers"]) and _try_build(st):
			continue
		# Kdyz uz se stavit neda (misto nebo zlato), zkus vylepseni i driv.
		if _try_upgrade(g, pol):
			continue
		break


func _try_upgrade(g: Game, pol: Dictionary) -> bool:
	if not bool(pol["upgrade"]):
		return false
	var best: Tower = null
	for item in g.towers:
		var t: Tower = item
		if not t.can_upgrade():
			continue
		if best == null or t.level < best.level:
			best = t
	if best == null:
		return false
	if g.gold < best.upgrade_cost():
		return false
	return g.try_upgrade(best.cell)


func _try_build(st: Dictionary) -> bool:
	var g: Game = st["g"]
	var pol: Dictionary = st["policy"]
	var cells: Array = st["cells"]
	for item in cells:
		var c: Vector2i = item
		if g.tower_at(c) != null:
			continue
		var el: int = Tower.NEUTRAL if bool(pol["neutral"]) else g.net.strip_element(c)
		return g.try_build(c, Tower.DEFAULT_KIND, el)
	return false


# ---------------------------------------------------------------- pomocne

func _wave_hp(g: Game, n: int) -> float:
	var c: Dictionary = g.wave_counts(n)
	var base: float = Game.BASE_HP * pow(1.0 + Game.HP_GROWTH, float(n - 1))
	return base * (float(c["basic"]) * 1.0
		+ float(c["light"]) * Enemy.tier_hp(Enemy.TIER_LIGHT)
		+ float(c["heavy"]) * Enemy.tier_hp(Enemy.TIER_HEAVY)
		+ float(c["dual"]) * Enemy.tier_hp(Enemy.TIER_BASIC))
