extends SceneTree
## tools/test_zone_memory.gd — a zone must survive a waypoint trip and a town portal, and must
## NOT survive a death or a restart of the game.
##
## Jan: "zóny by se neresetovaly při každém odchodu do města. Při smrti ano, ale při použití
## waypointu a town scroll portálu ne. Tzn., že se musí uložit pozice a stav všech monster v dané
## lokaci a i samotná vygenerovaná lokace. Reset by proběhl jen u smrti a když by šel hráč 'spát',
## což by byla obdoba vypnutí a zapnutí hry v diablu."
##
## The failure this file exists to catch is invisible in a screenshot: re-entering a zone always
## LOOKS right — the corridor is rebuilt identically from the seed — and only the monsters give
## it away. So every case below compares the STATE that the seed cannot produce: which packs woke,
## which are emptied, where each living monster stands, how hurt it is, and the fog.
##
## Run:  godot --headless --path . --script res://tools/test_zone_memory.gd
## Pass: prints ZONE_MEMORY_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
const ZoneMemory := preload("res://scripts/combat/zone_memory.gd")

## A value that only the snapshot can carry — used to prove the store never reached the SAVE.
const SENTINEL := 987654

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")

	_test_a_fresh_zone_has_nothing_to_restore()
	_test_the_woken_pack_and_its_wounds_come_back()
	_test_a_wiped_pack_stays_wiped()
	_test_the_seed_still_rebuilds_the_layout()
	_test_death_clears_the_acts_world_only()
	_test_the_store_never_reaches_the_save()
	_test_hp_is_clamped_to_the_new_maximum()
	_test_loot_on_the_floor_is_not_destroyed_by_a_trip()

	for f in _failures:
		print("  FAIL: %s" % f)
	print("ZONE_MEMORY_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh(seed_value: int, zone: int) -> SurvivorRun:
	var run := SurvivorRun.new()
	run.setup(_state, _resolve, _loot, 0, seed_value, zone)
	return run


func _resolve(id) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var loot: Dictionary = _state.loot_item(item_id)
	if not loot.is_empty():
		return loot
	return _data.item(item_id)


## Puts the hero on a pack's cell and runs the discovery tick — the same two rules the game uses
## (`_zone_tick` wakes on proximity). Returns the index of the pack that woke.
func _wake_pack(run: SurvivorRun, pack: int = 1) -> int:
	if pack >= run.zones.size():
		return -1
	run.player_pos = run.zones[pack]["centre"] as Vector2
	run._zone_tick()
	run._reveal_around(run.player_pos)
	return pack


func _test_a_fresh_zone_has_nothing_to_restore() -> void:
	ZoneMemory.reset()
	var run := _fresh(4242, 2)
	if run.restore(ZoneMemory.peek(0, 2)):
		_fail("a zone never visited reported a restore")
	if not run.monsters.is_empty():
		_fail("a fresh zone starts with %d monsters — packs must wake on approach"
			% run.monsters.size())
	if ZoneMemory.has(0, 2):
		_fail("an untouched zone left a snapshot behind")


func _test_the_woken_pack_and_its_wounds_come_back() -> void:
	ZoneMemory.reset()
	var run := _fresh(4242, 2)
	var pack := _wake_pack(run)
	if pack < 0 or run.monsters.is_empty():
		_fail("the pack never woke — the case below would compare two empty lists")
		return
	var n := run.monsters.size()
	# Wound one monster and move it, so the restore must carry BOTH numbers, not just the count.
	run.monsters[0]["hp"] = 5
	run.monsters[0]["pos"] = (run.monsters[0]["pos"] as Vector2) + Vector2(37.0, -11.0)
	run.hp = 33
	var moved: Vector2 = run.monsters[0]["pos"]
	var first_id := int(run.monsters[0]["id"])
	run._zone_tick()
	ZoneMemory.store(0, 2, run.snapshot())

	var back := _fresh(4242, 2)
	if not back.restore(ZoneMemory.peek(0, 2)):
		_fail("the stored zone was not restored")
		return
	print("  restore: %d/%d monsters, pack awake=%s, hero hp=%d, fog cells=%d"
		% [back.monsters.size(), n, str(back.zones[pack]["active"]), back.hp,
			back.explored_cells.size() - back.explored_cells.count(0)])
	if back.monsters.size() != n:
		_fail("restored %d monsters, %d were left standing" % [back.monsters.size(), n])
	if not bool(back.zones[pack]["active"]):
		_fail("the restored pack is not awake — it would spawn a SECOND copy on approach")
	var found := false
	for m in back.monsters:
		if int(m["id"]) == first_id:
			found = true
			if int(m["hp"]) != 5:
				_fail("the wounded monster came back at %d hp, it was hit down to 5" % int(m["hp"]))
			if (m["pos"] as Vector2).distance_to(moved) > 0.01:
				_fail("the monster moved %.1f px between the snapshot and the restore"
					% (m["pos"] as Vector2).distance_to(moved))
	if not found:
		_fail("monster id %d disappeared in the restore" % first_id)
	if back.hp != 33:
		_fail("the hero came back at %d hp, he left at 33 — a waypoint healed him" % back.hp)
	if back.player_pos.distance_to(back.start_point) > 0.01:
		_fail("the hero did not arrive at the zone entrance")
	# The fog: a restored zone remembers the map the player revealed.
	var fresh_fog := _fresh(4242, 2)
	var restored_fog: int = back.explored_cells.size() - back.explored_cells.count(0)
	var fresh_fog_n: int = fresh_fog.explored_cells.size() - fresh_fog.explored_cells.count(0)
	if restored_fog <= fresh_fog_n:
		_fail("the restored fog (%d cells) is no wider than a fresh zone's (%d)"
			% [restored_fog, fresh_fog_n])
	# The counterfactual: without the snapshot the same seed holds no monsters at all.
	var unrestored := _fresh(4242, 2)
	if not unrestored.monsters.is_empty():
		_fail("the counterfactual zone already had monsters — the case proves nothing")


func _test_a_wiped_pack_stays_wiped() -> void:
	ZoneMemory.reset()
	var run := _fresh(777, 4)
	var pack := _wake_pack(run)
	if pack < 0 or run.monsters.is_empty():
		_fail("the pack never woke (wiped-pack case)")
		return
	run.monsters.clear()
	run._zone_clear_tick(0.0)
	if not bool(run.zones[pack]["cleared"]):
		_fail("the emptied pack was not marked cleared before the snapshot")
	ZoneMemory.store(0, 4, run.snapshot())

	var back := _fresh(777, 4)
	back.restore(ZoneMemory.peek(0, 4))
	if not back.monsters.is_empty():
		_fail("a wiped pack came back with %d monsters" % back.monsters.size())
	if not bool(back.zones[pack]["cleared"]):
		_fail("a wiped pack came back UNCLEARED — the area would never finish")
	# Walking onto it again must not wake it a second time.
	back.player_pos = back.zones[pack]["centre"] as Vector2
	var ids: Array = (back.zones[pack]["ids"] as Array).duplicate()
	back._zone_tick()
	# A NEIGHBOURING pack may legitimately wake when the hero teleports onto this cell — what
	# must not happen is one of the EMPTIED pack's own members coming back.
	for m in back.monsters:
		if ids.has(int(m["id"])):
			_fail("an emptied pack re-spawned on approach (monster id %d)" % int(m["id"]))
			break


func _test_the_seed_still_rebuilds_the_layout() -> void:
	ZoneMemory.reset()
	var a := _fresh(31337, 5)
	var b := _fresh(31337, 5)
	if a.exit_point.distance_to(b.exit_point) > 0.01:
		_fail("the same seed produced two different exits (%.1f px apart)"
			% a.exit_point.distance_to(b.exit_point))
	if a.zones.size() != b.zones.size():
		_fail("the same seed produced %d and %d packs" % [a.zones.size(), b.zones.size()])
	var c := _fresh(31338, 5)
	if c.exit_point.distance_to(a.exit_point) < 1.0:
		_fail("two different seeds produced the same exit — the layout is not seeded")
	# The snapshot therefore does NOT need to carry the geometry, and must not pretend to:
	# it is the walked state only. A restore over the same seed must land on the same corridor.
	if not a.zones.is_empty() and a.zones.size() == b.zones.size():
		if (a.zones[0]["centre"] as Vector2).distance_to(b.zones[0]["centre"] as Vector2) > 0.01:
			_fail("pack 0 sits at a different place for the same seed")


func _test_death_clears_the_acts_world_only() -> void:
	ZoneMemory.reset()
	var run := _fresh(90210, 1)
	_wake_pack(run)
	ZoneMemory.store(0, 1, run.snapshot())
	ZoneMemory.store(1, 1, run.snapshot())
	if ZoneMemory.count() != 2:
		_fail("two stores produced %d entries" % ZoneMemory.count())
	# Death in act 1 rolls act 1's world again; act 2 was never entered.
	ZoneMemory.clear_act(1)
	if ZoneMemory.has(1, 1):
		_fail("a death in act 1 did not clear act 1's zone")
	if not ZoneMemory.has(0, 1):
		_fail("a death in act 1 also cleared act 0 — other acts are untouched")
	ZoneMemory.clear_all()
	if ZoneMemory.count() != 0:
		_fail("clear_all left %d snapshots" % ZoneMemory.count())


func _test_the_store_never_reaches_the_save() -> void:
	ZoneMemory.reset()
	var run := _fresh(1234, 0)
	_wake_pack(run)
	var snap := run.snapshot()
	snap["zone_state_marker"] = SENTINEL
	ZoneMemory.store(0, 0, snap)
	# "Sleep" = the process ends. The proof that closing the game refreshes every monster is that
	# the snapshot is NOT in the save: a save written now must not carry a single monster.
	# ⚠️  Do not grep for the word "monsters" — `state.data` legitimately keeps a monster COUNT
	# under that key, so a blanket word check fails on a healthy save. The sentinel key is the
	# only thing that can exist in the snapshot alone.
	var text := JSON.stringify(_state.data)
	if text.contains(str(SENTINEL)) or text.contains("zone_state_marker"):
		_fail("the zone snapshot reached the save — a restart would keep the old monsters")
	ZoneMemory.reset()


func _test_hp_is_clamped_to_the_new_maximum() -> void:
	ZoneMemory.reset()
	var run := _fresh(55, 3)
	var snap := run.snapshot()
	snap["hp"] = 99999
	ZoneMemory.store(0, 3, snap)
	var back := _fresh(55, 3)
	back.restore(ZoneMemory.peek(0, 3))
	if back.hp > back.max_hp:
		_fail("restore gave the hero %d hp over a %d maximum" % [back.hp, back.max_hp])
	if back.hp < 1:
		_fail("restore left the hero at %d hp" % back.hp)


## A waypoint trip must not destroy loot the player has already SEEN drop. The drop list is part
## of the snapshot for exactly that reason, and the pickup itself is what empties it.
func _test_loot_on_the_floor_is_not_destroyed_by_a_trip() -> void:
	ZoneMemory.reset()
	var run := _fresh(808, 1)
	run.drops.append({"pos": run.start_point + Vector2(40, 0), "kind": "gold", "amount": 17,
		"age": 0.4})
	run.drops.append({"pos": run.start_point + Vector2(-30, 10), "kind": "item",
		"item": {"id": "sword_test", "name": "Kratky mec", "quality": "magic"},
		"age": 0.9, "color": "#4a7fd4"})
	ZoneMemory.store(0, 1, run.snapshot())

	var back := _fresh(808, 1)
	back.restore(ZoneMemory.peek(0, 1))
	if back.drops.size() != 2:
		_fail("a waypoint trip left %d of 2 drops on the floor" % back.drops.size())
		return
	var gold: Dictionary = back.drops[0]
	if str(gold.get("kind", "")) != "gold" or int(gold.get("amount", 0)) != 17:
		_fail("the gold drop came back as %s/%s" % [str(gold.get("kind")), str(gold.get("amount"))])
	var item: Dictionary = back.drops[1]
	var item_data: Dictionary = item.get("item", {})
	if str(item_data.get("id", "")) != "sword_test":
		_fail("the item on the floor came back as %s" % str(item_data.get("id", "nothing")))
