extends SceneTree
## tools/test_loot_rates.gd — the item table's TWO rules after Jan's report:
##
##   1. "Padá teď příliš mnoho lootu. Po každé oblasti mám plný batoh."  -> the drop rates
##   2. "Teď padá mix všech možných úrovní itemů… jsme stále jen v Actu 1 obtížnosti normal,
##       tak by neměly padat tak silné itemy."  -> the AREA LEVEL gate
##
## Both are measured here instead of eyeballed: the rate by rolling thousands of kills through
## the real `LootSystem.roll`, the gate by asking which BASE each of those drops came from and
## comparing its `dropFloor` with the area's own depth.
##
## Run:  godot --headless --path . --script res://tools/test_loot_rates.gd
## Pass: prints LOOT_RATES_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")

## Enough rolls that a 1 % band is meaningful, few enough to stay under a second or two.
const ROLLS := 4000

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")
	# A hero above the monsters' level, so `ilvl = min(monster, hero)` is decided by the monster
	# and a hero-level leak into the roll shows up as wrong affixes instead of being masked.
	_state.data["hero"]["level"] = 30


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_test_area_gate()
	_test_rates()
	_test_item_level()
	for f in _failures:
		print("  FAIL: %s" % f)
	print("LOOT_RATES_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)
	return false


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)


# --- 1. the area-level gate --------------------------------------------------


## The PWA's own scale: difficulty * 50 + act * 10 + area. Act 1 normal therefore reaches depth
## 9 and nothing deeper, whatever the hero has outgrown and however many packs he has killed.
func _test_area_gate() -> void:
	var expect := {
		"act1 normal area 0": [0, 0, 0, 0],
		"act1 normal area 9": [0, 0, 9, 9],
		"act3 normal area 4": [0, 2, 4, 24],
		"act1 nightmare area 0": [1, 0, 0, 50],
		"act5 hell area 9": [2, 4, 9, 149],
	}
	for label in expect:
		var row: Array = expect[label]
		var got: int = LootSystem.area_depth(int(row[0]), int(row[1]), int(row[2]))
		_check(got == int(row[3]), "area_depth(%s) = %d, expected %d" % [label, got, int(row[3])])

	var rng := RandomNumberGenerator.new()
	# Act 1 normal, every area of it: the deepest base is `dropFloor` 9, and an Ataghan (106) is
	# an ELITE tier-5 blade that must not exist in this act at all.
	for area in 10:
		var depth: int = LootSystem.area_depth(0, 0, area)
		for _i in 300:
			var item: Dictionary = _loot.generate_item(_state, 0, area, false, 3, 0, rng)
			if item.is_empty():
				continue
			var base: Dictionary = _data.item(str(item.get("baseId", "")))
			if base.is_empty():
				continue
			var floor_needed := int(base.get("dropFloor", 0))
			_check(floor_needed <= depth,
				"act 1 normal area %d (depth %d) dropped %s (dropFloor %d)"
					% [area, depth, str(base.get("name", "?")), floor_needed])
			_check(str(base.get("name", "")) != "Ataghan",
				"act 1 normal area %d dropped an Ataghan" % area)
	# The other end: hell act 5 really does reach the elite band, or the gate is just "nothing".
	# The difficulty is GLOBAL state (the save's own setting), not a parameter of the roll — the
	# act is not allowed to be deeper than the difficulty the player is actually in.
	_state.data["difficulty"] = 2
	var deep := 0
	for _i in 400:
		var item: Dictionary = _loot.generate_item(_state, 4, 9, false, 60, 0, rng)
		if not item.is_empty() and int(_data.item(str(item.get("baseId", ""))).get("dropFloor", 0)) > 100:
			deep += 1
	_state.data["difficulty"] = 0
	_check(deep > 0, "hell act 5 never dropped anything past dropFloor 100 — the gate is too tight")


# --- 2. the drop rate --------------------------------------------------------


## Jan's "plný batoh" complaint, as a number. One body used to leave gear on ~30 % of kills and
## some kind of item on ~51 %. The bands below are the new contract: GEAR between 6 % and 13 %,
## everything item-shaped (specials included) under 28 %.
func _test_rates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var gear := 0
	var any_item := 0
	var boss_items := 0
	for _i in ROLLS:
		var drop: Dictionary = _loot.roll(_state, 0, 3, false, 3, 0, 0, rng, 0)
		if str(drop.get("type", "")) == "gold":
			continue
		var item: Dictionary = drop.get("item", {})
		if item.is_empty():
			continue
		any_item += 1
		var t := str(item.get("type", ""))
		if LootSystem.GEAR_TYPES.has(t):
			gear += 1
	var gear_share := float(gear) / float(ROLLS)
	var item_share := float(any_item) / float(ROLLS)
	print("  rates: gear %.3f, any item %.3f over %d kills" % [gear_share, item_share, ROLLS])
	_check(gear_share >= 0.06 and gear_share <= 0.13,
		"gear drops on %.1f %% of kills, expected 6-13 %%" % (gear_share * 100.0))
	_check(item_share <= 0.28,
		"some item drops on %.1f %% of kills, expected at most 28 %%" % (item_share * 100.0))
	# A champion and an elite must still pay better than a stray — the rate cut must not have
	# flattened the grades into each other.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 77
	for _i in 1500:
		if not _loot.roll(_state, 0, 3, true, 3, 0, 0, rng2, 0).get("item", {}).is_empty():
			boss_items += 1
	_check(boss_items == 1500, "a boss roll must ALWAYS pay an item, got %d of 1500" % boss_items)


# --- 3. the item level -------------------------------------------------------


## `ilvl` is `min(monster_level, hero_level)`: an act-1 skeleton may not roll level-20 affixes
## just because the player is level 20. The hero is level 30 in this test, so a leak shows.
func _test_item_level() -> void:
	var rng := RandomNumberGenerator.new()
	var seen := 0
	for _i in 400:
		var item: Dictionary = _loot.generate_item(_state, 0, 3, false, 3, 0, rng)
		if item.is_empty():
			continue
		seen += 1
		_check(int(item.get("ilvl", 999)) <= 3,
			"a level-3 monster rolled ilvl %d" % int(item.get("ilvl", 999)))
		for a in item.get("affixes", []):
			_check(int(a.get("minIlvl", 0)) <= 3,
				"a level-3 monster rolled affix %s (minIlvl %d)"
					% [str(a.get("name", "?")), int(a.get("minIlvl", 0))])
	_check(seen > 50, "the level check only produced %d items" % seen)
