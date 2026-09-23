extends SceneTree
## tools/probe_loot.gd — why does nothing drop?
##
## Prints, step by step, what the loot chain actually produces:
##   1. the LOOT SYSTEM alone (1000 rolls, one per act),
##   2. `battle.roll_loot` for a finished fight,
##   3. the arena screen's `award_loot` on a real won fight,
##   4. whether the bag and the result page see it.
##
## Run: godot --headless --path . --script res://tools/probe_loot.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	_probe_rolls()
	_probe_screen()
	quit(0)


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _probe_rolls() -> void:
	print("--- 1. LootSystem.roll, 300 rolls per act ---")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	for act in range(5):
		var kinds := {"gold": 0, "item": 0, "boss": 0, "empty": 0}
		var names := {}
		for _i in 300:
			var d: Dictionary = _loot.roll(s, act, 0, false, 1 + act * 10, 0, 0, rng)
			var t := str(d.get("type", ""))
			if t == "":
				kinds["empty"] += 1
			else:
				kinds[t] += 1
			if d.has("item"):
				var it: Dictionary = d["item"]
				var iid := str(it.get("id", "?"))
				names[iid] = int(names.get(iid, 0)) + 1
		print("  act %d: %s  sample ids: %s" % [act, str(kinds), str(names.keys().slice(0, 6))])


func _probe_screen() -> void:
	print("--- 2. a real fight driven to a win ---")
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	s.hero()["level"] = 20
	s.hero()["attrStr"] = 40
	var screen: ArenaScreen = ArenaScreen.new(_data, _gen, _loot, s, _resolve(s))
	root.add_child(screen)
	if screen._mana_track == null:
		screen._build()
	if not screen.start(s, _resolve(s)):
		print("  start() FAILED")
		return
	screen.battle.enemy_hp = 1.0
	screen.battle.enemy_max_hp = 1.0
	screen.battle.hero_hp = 100000.0
	screen.battle.hero_max_hp = 100000.0
	var inv_before: int = s.inventory().size()
	var gold_before: int = int(s.hero().get("gold", 0))
	var ticks := 0
	while not screen.battle.ended and ticks < 6000:
		screen.step()
		ticks += 1
	print("  ended=%s won=%s after %d ticks" % [screen.battle.ended, screen.battle.won, ticks])
	print("  _result_loot_rows=%d  pending=%d  bag %d -> %d  gold %d -> %d" % [
		screen._result_loot_rows.size(), screen._pending_loot.size(),
		inv_before, s.inventory().size(), gold_before, int(s.hero().get("gold", 0))])
	for item in screen._result_loot_rows:
		print("    row: id=%s name=%s" % [str(item.get("id", "?")), str(item.get("name", "?"))])
	print("  bag contents: %s" % str(s.inventory().slice(0, 12)))

	print("--- 3. the result page's loot list ---")
	print("  _loot_list=%s visible=%s" % [
		str(screen._loot_list), str(screen._loot_list.visible if screen._loot_list != null else "null")])
	if screen._loot_list != null:
		print("  rows on screen: %d" % screen._loot_list.get_child_count())
	print("--- 4. reward summary from roll_loot ---")
	var res: Dictionary = screen.battle.roll_loot(_loot, s, _resolve(s),
		_gen.magic_find(s.equip(), _resolve(s)), _gen.gold_find(s.equip(), _resolve(s)))
	print("  items=%d gold=%d portals=%d" % [
		(res["items"] as Array).size(), int(res["gold"]), int(res["portals"])])

	print("--- 5. direct single roll through battle.roll_loot's inputs ---")
	var d: Dictionary = _loot.roll(s, 0, 0, false, 20, 0, 0, screen.battle.rng)
	print("  raw drop = %s" % str(d))
