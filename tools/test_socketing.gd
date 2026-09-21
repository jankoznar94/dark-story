extends SceneTree
## tools/test_socketing.gd — putting gems and jewels into an item's sockets.
##
## Worth asserting because every rule here is INVISIBLE when it breaks: a gem that
## grants the wrong stat (armour's +HP on a weapon instead of fire damage) still
## inserts cleanly, still shows an icon, and only shows up as a balance problem
## twenty levels later. Same for an occupied socket that quietly accepts a second gem
## and doubles the stat.
##
## Run:  godot --headless --path . --script res://tools/test_socketing.gd
## Pass: prints SOCKETING_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Socketing := preload("res://scripts/items/socketing.gd")

var _data: Node
var _gen: ItemGen
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_gem_stat_depends_on_host_type()
	_test_elemental_roll_adds_as_a_range()
	_test_occupied_socket_refuses()
	_test_gapless_and_over_index_refused()
	_test_socket_consumes_the_gem_from_the_bag()
	_test_refused_insert_keeps_the_gem()
	_test_no_sockets_means_no_insert()
	_test_jewel_applies_its_affixes()
	_test_jewel_from_loot_registry()
	_test_socket_record_shape()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("SOCKETING_ALL_PASS=true")
	else:
		print("SOCKETING_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh(class_id: String = "barbarian"):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	return s


func _rng(seed_value: int = 12345) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


## A socketed host built by hand, so the test does not depend on a loot roll producing
## sockets. `sockets` is set explicitly.
func _host(base_id: String, sockets: int) -> Dictionary:
	var base: Dictionary = _data.item(base_id)
	var item := base.duplicate(true)
	item["id"] = "test_%s" % base_id
	item["baseId"] = base_id
	item["sockets"] = sockets
	item["socketedGems"] = []
	return item


# --- the host-type table ------------------------------------------------------

## The same ruby is fire damage in a weapon, +HP in armour and fire resist in a shield.
## That is the whole reason GEMS.json carries three sub-tables, and it is the rule most
## likely to be collapsed into one by accident.
func _test_gem_stat_depends_on_host_type() -> void:
	var weapon := _host("blade_shortSword", 1)
	Socketing.apply_gem_stats(weapon, "ruby", "chipped", _data)
	if not weapon.has("fireDmg"):
		_fail("a ruby in a WEAPON granted no fireDmg")
	elif int((weapon["fireDmg"] as Array)[0]) <= 0:
		_fail("a ruby in a weapon granted a zero fireDmg range")
	if int(weapon.get("bonusHp", 0)) != 0:
		_fail("a ruby in a weapon granted bonusHp - it read the ARMOR table")

	var armor := _host("armor_fullPlate", 1)
	Socketing.apply_gem_stats(armor, "ruby", "chipped", _data)
	if int(armor.get("bonusHp", 0)) <= 0:
		_fail("a ruby in ARMOR granted no bonusHp")
	if armor.has("fireDmg"):
		_fail("a ruby in armour granted fireDmg - it read the WEAPON table")

	var shield := _host("shield_buckler", 1)
	Socketing.apply_gem_stats(shield, "ruby", "chipped", _data)
	if int(shield.get("fireRes", 0)) <= 0:
		_fail("a ruby in a SHIELD granted no fireRes")


func _test_elemental_roll_adds_as_a_range() -> void:
	var weapon := _host("blade_shortSword", 2)
	Socketing.apply_gem_stats(weapon, "ruby", "chipped", _data)
	var first: Array = (weapon["fireDmg"] as Array).duplicate()
	Socketing.apply_gem_stats(weapon, "ruby", "chipped", _data)
	var second: Array = weapon["fireDmg"]
	if int(second[0]) != int(first[0]) * 2 or int(second[1]) != int(first[1]) * 2:
		_fail("two rubies did not add up as a range (%s -> %s)" % [str(first), str(second)])

	# A gem applied over an item that already has an elemental roll must ADD, not
	# replace: a cold-damage weapon keeps its cold damage.
	var cold_weapon := _host("blade_shortSword", 1)
	cold_weapon["coldDmg"] = [5, 9]
	Socketing.apply_gem_stats(cold_weapon, "ruby", "chipped", _data)
	if int(cold_weapon["coldDmg"][0]) != 5:
		_fail("socketing a ruby overwrote the weapon's existing cold damage")


# --- gates --------------------------------------------------------------------

func _test_occupied_socket_refuses() -> void:
	var state = _fresh()
	var host := _host("blade_shortSword", 2)
	state.add_item("ruby", _data.item("ruby"))
	var gem: Dictionary = _data.item("ruby")
	var first: Dictionary = Socketing.socket(state, host, "ruby", gem, 0, _data, _rng())
	if not first["ok"]:
		_fail("the first insert into an empty socket failed: %s" % str(first["message"]))
		return
	state.add_item("ruby", gem)
	var second: Dictionary = Socketing.socket(state, host, "ruby", gem, 0, _data, _rng())
	if second["ok"]:
		_fail("an OCCUPIED socket accepted a second gem")
	# The refused insert must not have added anything: compare against a host that got
	# exactly one gem. Reading the GEMS table directly here was wrong once already —
	# assert the invariant, not a transcribed number.
	var one := _host("blade_shortSword", 2)
	Socketing.apply_gem_stats(one, "ruby", "normal", _data)
	if host["fireDmg"] != one["fireDmg"]:
		_fail("the refused insert still added its stats (%s vs %s)" % [str(host["fireDmg"]), str(one["fireDmg"])])


func _test_gapless_and_over_index_refused() -> void:
	var state = _fresh()
	var gem: Dictionary = _data.item("ruby")
	var host := _host("blade_shortSword", 1)
	state.add_item("ruby", gem)
	if Socketing.socket(state, host, "ruby", gem, 5, _data, _rng())["ok"]:
		_fail("a socket index beyond the socket count was accepted")
	if Socketing.socket(state, host, "ruby", gem, -1, _data, _rng())["ok"]:
		_fail("a negative socket index was accepted")


func _test_no_sockets_means_no_insert() -> void:
	var state = _fresh()
	var gem: Dictionary = _data.item("ruby")
	var host := _host("blade_shortSword", 0)
	state.add_item("ruby", gem)
	if Socketing.socket(state, host, "ruby", gem, 0, _data, _rng())["ok"]:
		_fail("an item with no sockets accepted a gem")


func _test_socket_consumes_the_gem_from_the_bag() -> void:
	var state = _fresh()
	var gem: Dictionary = _data.item("ruby")
	state.add_item("ruby", gem)
	state.add_item("ruby", gem)
	var host := _host("blade_shortSword", 1)
	var before := ItemGen.stack_count(state.inventory(), "ruby")
	if not Socketing.socket(state, host, "ruby", gem, 0, _data, _rng())["ok"]:
		_fail("the insert failed")
		return
	var after := ItemGen.stack_count(state.inventory(), "ruby")
	if after != before - 1:
		_fail("the insert did not consume one gem from the stack (%d -> %d)" % [before, after])


## A refused socket must not eat the gem — the refund rule, from the other side.
func _test_refused_insert_keeps_the_gem() -> void:
	var state = _fresh()
	var gem: Dictionary = _data.item("ruby")
	state.add_item("ruby", gem)
	var host := _host("blade_shortSword", 1)
	host["socketedGems"] = [{"type": "ruby", "quality": "chipped", "name": "Chipped Ruby"}]
	var before := ItemGen.stack_count(state.inventory(), "ruby")
	var result: Dictionary = Socketing.socket(state, host, "ruby", gem, 0, _data, _rng())
	if result["ok"]:
		_fail("the occupied socket accepted the gem")
	if ItemGen.stack_count(state.inventory(), "ruby") != before:
		_fail("a REFUSED insert consumed the gem anyway")


# --- jewels -------------------------------------------------------------------

func _test_jewel_applies_its_affixes() -> void:
	var state = _fresh()
	var host := _host("blade_shortSword", 1)
	var jewel := {
		"id": "jewel_t1", "name": "Jewel", "type": "jewel",
		"affixes": [
			{"k": "test_dmg", "stats": {"enhancedDmg": [10, 20]}},
			{"k": "test_hp", "stats": {"bonusHp": 25}},
		],
	}
	state.register_loot_item(jewel)
	state.add_item("jewel_t1", jewel)
	var result: Dictionary = Socketing.socket(state, host, "jewel_t1", jewel, 0, _data, _rng())
	if not result["ok"]:
		_fail("a jewel failed to socket: %s" % str(result["message"]))
		return
	# bonusHp is a scalar affix line here (25, not a range), so it lands exactly.
	if int(host.get("bonusHp", 0)) != 25:
		_fail("the jewel's flat bonusHp did not reach the host (%d)" % int(host.get("bonusHp", 0)))
	# enhancedDmg is a RANGE [10, 20] and is rolled at insert, so assert the bounds.
	var ed := int(host.get("enhancedDmg", 0))
	if ed < 10 or ed > 20:
		_fail("the jewel's enhancedDmg roll %d is outside its [10, 20] range" % ed)
	if not host.has("socketedGems"):
		_fail("the jewel was not recorded in socketedGems")
	var entry: Dictionary = (host["socketedGems"] as Array)[0]
	if str(entry.get("type", "")) != "jewel":
		_fail("the socket record for a jewel is %s" % str(entry.get("type", "")))
	if str(entry.get("jewelId", "")) != "jewel_t1":
		_fail("the socket record lost the jewel's id")


## A jewel that came from LOOT stores its rolled stats on itself (fireRes, enhancedDmg,
## ...) rather than as an affix list. Both shapes must apply.
func _test_jewel_from_loot_registry() -> void:
	var state = _fresh()
	var host := _host("armor_fullPlate", 1)
	var jewel := {
		"id": "jewel_loot_1", "name": "Jewel", "type": "jewel",
		"fireRes": 12, "coldRes": 12, "enhancedDefense": 30, "bonusHp": 0,
	}
	state.register_loot_item(jewel)
	state.add_item("jewel_loot_1", jewel)
	var result: Dictionary = Socketing.socket(state, host, "jewel_loot_1", jewel, 0, _data, _rng())
	if not result["ok"]:
		_fail("a loot jewel failed to socket: %s" % str(result["message"]))
		return
	if int(host.get("fireRes", 0)) != 12:
		_fail("a loot jewel's fireRes did not reach the host")
	if int(host.get("enhancedDefense", 0)) != 30:
		_fail("a loot jewel's enhancedDefense did not reach the host")


func _test_socket_record_shape() -> void:
	var state = _fresh()
	var gem: Dictionary = _data.item("ruby_perfect")
	state.add_item("ruby_perfect", gem)
	var host := _host("blade_shortSword", 3)
	var result: Dictionary = Socketing.socket(state, host, "ruby_perfect", gem, 1, _data, _rng())
	if not result["ok"]:
		_fail("inserting at index 1 of 3 sockets failed: %s" % str(result["message"]))
		return
	var record: Array = host["socketedGems"]
	if record.size() != 3:
		_fail("the socket record is %d long, expected the socket count 3" % record.size())
	if record[0] != null:
		_fail("inserting at index 1 filled index 0")
	if record[1] == null:
		_fail("inserting at index 1 did not fill index 1")
	var entry: Dictionary = record[1]
	if str(entry.get("type", "")) != "ruby" or str(entry.get("quality", "")) != "perfect":
		_fail("the socket record reads %s, expected ruby/perfect" % str(entry))
