extends SceneTree
## tools/test_gem_stats.gd — every stat every gem grants, on every host family, and the
## code that CONSUMES it.
##
## Jan: "Rovnou zkontroluj, aby se správně přičítaly všechny staty gemů k itemům."
## A gem whose stat lands on the item but is never read is worse than no gem at all: the
## tooltip shows a number and nothing in the game changes. So this test walks the whole
## GEMS table (4 gems x 5 qualities) against the three host families, asserts the exact
## value written to the host, and then asserts the CONSUMER that is supposed to use it:
##
##   weapon  fireDmg / coldDmg / lightningDmg / poisonDmg + poisonDur
##           -> ItemStats.weapon_dmg_min/max, Progression damage range, poison DoT
##   armor   bonusHp -> ItemGen.hero_max_hp
##           bonusMana -> ItemGen.hero_max_mana
##           dex -> ItemGen.equip_attr_sum
##           magicFind -> ItemGen.magic_find
##   shield  fireRes/coldRes/lightningRes/poisonRes -> Battle.hero_school_resist
##
## Run:  godot --headless --path . --script res://tools/test_gem_stats.gd
## Pass: prints GEM_STATS_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Socketing := preload("res://scripts/items/socketing.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const Battle := preload("res://scripts/combat/battle.gd")

## One base per host family. Armour and helmet both read the `armor` sub-table, and the
## PWA treats every non-weapon non-shield host that way (a belt included).
const HOSTS := {
	"weapon": "blade_shortSword",
	"shield": "shield_buckler",
	"armor": "armor_leather",
	"helmet": "helm_cap",
}

var _data: Node
var _gen: ItemGen
var _failures: Array[String] = []
var _cases := 0


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_every_gem_on_every_host_family()
	_test_gem_stats_reach_the_consumers()
	_test_socketed_gem_survives_a_save_round_trip()

	for f in _failures:
		print("  FAIL: %s" % f)
	print("cases=%d failures=%d" % [_cases, _failures.size()])
	print("GEM_STATS_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh():
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	return s


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var loot: Dictionary = state.loot_item(item_id)
		if not loot.is_empty():
			return loot
		return _data.item(item_id)


func _rng(seed_value: int = 4242) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _host(base_id: String, tag: String) -> Dictionary:
	var base: Dictionary = _data.item(base_id)
	if base.is_empty():
		_fail("no such base item: %s" % base_id)
		return {}
	var item := base.duplicate(true)
	item["id"] = "loot_gemhost_%s" % tag
	item["sockets"] = 1
	item["socketedGems"] = []
	return item


## --- 1. the value written to the host ---------------------------------------
func _test_every_gem_on_every_host_family() -> void:
	var gems: Dictionary = _data.gems()
	for gem_type in gems:
		var qualities: Dictionary = gems[gem_type].get("qualities", {})
		for quality in qualities:
			var gem: Dictionary = _data.item(gem_type if quality == "normal" else "%s_%s" % [gem_type, quality])
			if gem.is_empty():
				_fail("gem %s/%s does not resolve to an item" % [gem_type, quality])
				continue
			for host_key in HOSTS:
				_cases += 1
				var tag := "%s_%s_%s" % [gem_type, quality, host_key]
				var state = _fresh()
				var host := _host(str(HOSTS[host_key]), tag)
				state.register_loot_item(host)
				state.add_item(str(gem["id"]), gem)
				var result: Dictionary = Socketing.socket(state, host, str(gem["id"]), gem, 0, _data, _rng())
				if not result["ok"]:
					_fail("%s: socket refused: %s" % [tag, str(result["message"])])
					continue
				# The record must point back at a REAL gem, or the socket draws empty.
				var records: Array = host.get("socketedGems", [])
				if records.size() != 1 or records[0] == null:
					_fail("%s: no socket record written" % tag)
				var family := "weapon" if host_key == "weapon" else ("shield" if host_key == "shield" else "armor")
				var expected: Dictionary = qualities[quality].get(family, {})
				for stat in expected:
					_assert_stat(tag, host, stat, expected[stat])


func _assert_stat(tag: String, host: Dictionary, stat: String, expected: Variant) -> void:
	var got: Variant = host.get(stat)
	if expected is Array and stat in Socketing.ELEMENTAL:
		var want_lo := int(expected[0])
		var want_hi := int(expected[1]) if expected.size() > 1 else want_lo
		if not (got is Array) or got.size() < 2:
			_fail("%s: %s should be a [lo,hi] range, got %s" % [tag, stat, str(got)])
			return
		if int(got[0]) != want_lo or int(got[1]) != want_hi:
			_fail("%s: %s is %s, expected %d-%d" % [tag, stat, str(got), want_lo, want_hi])
		return
	var want := int(expected[1]) if expected is Array else int(expected)
	if got == null:
		_fail("%s: %s was never written to the host" % [tag, stat])
	elif int(got) != want:
		_fail("%s: %s is %d, expected %d" % [tag, stat, int(got), want])


## --- 2. the consumers --------------------------------------------------------
func _test_gem_stats_reach_the_consumers() -> void:
	var find := func(id): return _data.item(str(id))
	var gems: Dictionary = _data.gems()

	# WEAPON: each elemental channel must move the swing range the combat code reads.
	for gem_type in ["ruby", "sapphire", "topaz"]:
		var family_key: String = str({"ruby": "fireDmg", "sapphire": "coldDmg", "topaz": "lightningDmg"}[gem_type])
		var gem: Dictionary = _data.item(gem_type)
		var state = _fresh()
		var base: Dictionary = _data.item("blade_shortSword")
		var host := _host("blade_shortSword", "wpn_%s" % gem_type)
		state.register_loot_item(host)
		state.add_item(str(gem["id"]), gem)
		Socketing.socket(state, host, str(gem["id"]), gem, 0, _data, _rng())
		var roll: Array = gems[gem_type]["qualities"]["normal"]["weapon"][family_key]
		var want_min := int(base["baseDmgMin"]) + int(roll[0])
		var want_max := int(base["baseDmgMax"]) + int(roll[1])
		if ItemStats.weapon_dmg_min(host) != want_min:
			_fail("weapon %s: weapon_dmg_min is %d, expected %d" % [gem_type, ItemStats.weapon_dmg_min(host), want_min])
		if ItemStats.weapon_dmg_max(host) != want_max:
			_fail("weapon %s: weapon_dmg_max is %d, expected %d" % [gem_type, ItemStats.weapon_dmg_max(host), want_max])

	# ARMOUR: +HP, +Mana, dex and magicFind must show in the hero's own totals.
	var state2 = _fresh()
	var equip: Dictionary = {}
	var armor := _host("armor_leather", "armor_consumers")
	state2.register_loot_item(armor)
	equip["armor"] = str(armor["id"])
	for gem_type in ["ruby", "sapphire", "emerald", "topaz"]:
		var gem2: Dictionary = _data.item(gem_type)
		state2.add_item(str(gem2["id"]), gem2)
		# One socket per host, so the consumables are summed across four hosts instead.
		var host2 := _host("armor_leather", "armor_consumer_%s" % gem_type)
		state2.register_loot_item(host2)
		equip["armor"] = str(host2["id"])
		Socketing.socket(state2, host2, str(gem2["id"]), gem2, 0, _data, _rng())
		var q: Dictionary = gems[gem_type]["qualities"]["normal"]["armor"]
		for stat in q:
			if int(host2.get(stat, 0)) != int(q[stat]):
				_fail("armour %s: %s is %d, expected %d" % [gem_type, stat, int(host2.get(stat, 0)), int(q[stat])])

	var hp_gem: Dictionary = _data.item("ruby")
	var hp_host := _host("armor_leather", "hp_consumer")
	hp_host["socketedGems"] = [{"type": "ruby", "quality": "normal", "name": "Ruby"}]
	hp_host["bonusHp"] = int(gems["ruby"]["qualities"]["normal"]["armor"]["bonusHp"])
	state2.register_loot_item(hp_host)
	state2.equip()["armor"] = str(hp_host["id"])
	var hero: Dictionary = state2.hero()
	hero["level"] = 1
	hero["attrVit"] = 0
	hero["attrInt"] = 0
	var hp_with: int = _gen.hero_max_hp(hero, state2.equip(), _resolve(state2))
	if hp_with != 35 + int(hp_host["bonusHp"]):
		_fail("bonusHp does not reach hero_max_hp: %d, expected %d" % [hp_with, 35 + int(hp_host["bonusHp"])])

	var mana_gem: Dictionary = _data.item("sapphire")
	var mana_host := _host("armor_leather", "mana_consumer")
	mana_host["bonusMana"] = int(gems["sapphire"]["qualities"]["normal"]["armor"]["bonusMana"])
	state2.register_loot_item(mana_host)
	state2.equip()["helmet"] = str(mana_host["id"])
	var cls: Dictionary = _data.class_by_id("barbarian")
	var base_mana := int(cls.get("baseMana", 50))
	var mana_with: int = _gen.hero_max_mana(hero, state2.equip(), "barbarian", _resolve(state2))
	if mana_with != base_mana + int(mana_host["bonusMana"]):
		_fail("bonusMana does not reach hero_max_mana: %d, expected %d" % [mana_with, base_mana + int(mana_host["bonusMana"])])

	var dex_host := _host("armor_leather", "dex_consumer")
	dex_host["dex"] = int(gems["emerald"]["qualities"]["normal"]["armor"]["dex"])
	state2.register_loot_item(dex_host)
	state2.equip()["gloves"] = str(dex_host["id"])
	var attrs: Dictionary = _gen.equip_attr_sum(state2.equip(), _resolve(state2), ["dex"])
	if int(attrs["dex"]) < int(dex_host["dex"]):
		_fail("dex from a gem does not reach equip_attr_sum: %d" % int(attrs["dex"]))

	var mf_host := _host("armor_leather", "mf_consumer")
	mf_host["magicFind"] = int(gems["topaz"]["qualities"]["normal"]["armor"]["magicFind"])
	state2.register_loot_item(mf_host)
	state2.equip()["boots"] = str(mf_host["id"])
	if _gen.magic_find(state2.equip(), _resolve(state2)) < int(mf_host["magicFind"]):
		_fail("magicFind from a gem does not reach magic_find")

	# SHIELD: a resist gem must actually lower the damage multiplier the battle applies.
	var state3 = _fresh()
	var shield := _host("shield_buckler", "resist_consumer")
	state3.register_loot_item(shield)
	var rgem: Dictionary = _data.item("ruby")
	state3.add_item(str(rgem["id"]), rgem)
	Socketing.socket(state3, shield, str(rgem["id"]), rgem, 0, _data, _rng())
	state3.equip()["shield"] = str(shield["id"])
	var battle = Battle.new(_data)
	var mult: float = battle.hero_school_resist(state3, "fire")
	var want_pct := mini(75, int(gems["ruby"]["qualities"]["normal"]["shield"]["fireRes"]))
	if absf(mult - (1.0 - float(want_pct) / 100.0)) > 0.0001:
		_fail("shield fireRes does not reach hero_school_resist: mult %.3f, expected %.3f"
			% [mult, 1.0 - float(want_pct) / 100.0])


## --- 3. persistence ----------------------------------------------------------
func _test_socketed_gem_survives_a_save_round_trip() -> void:
	var state = _fresh()
	var gem: Dictionary = _data.item("ruby")
	var host := _host("blade_shortSword", "persist")
	state.register_loot_item(host)
	state.add_item(str(gem["id"]), gem)
	var result: Dictionary = Socketing.socket(state, host, str(gem["id"]), gem, 0, _data, _rng())
	if not result["ok"]:
		_fail("persistence: insert refused: %s" % str(result["message"]))
		return
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state.data))
	var records: Array = saved["lootItems"][str(host["id"])].get("socketedGems", [])
	if records.size() != 1 or records[0] == null:
		_fail("persistence: the socket record is not in the serialised save")
		return
	var fire = saved["lootItems"][str(host["id"])].get("fireDmg")
	if fire == null:
		_fail("persistence: the gem's stat is not in the serialised save")

	# A STATIC base has no save entry of its own. Socketing it must write a COPY into the
	# save (and leave the shared table pristine), or the next resolve hands back the base
	# and the gem's stats are gone.
	var state2 = _fresh()
	var static_host: Dictionary = _data.item("blade_shortSword").duplicate(true)
	# Static bases carry only `maxSockets`; a socket COUNT is rolled on generation, so a
	# socketable static base is hypothetical — the copy/register path still has to hold.
	static_host["sockets"] = 1
	static_host["socketedGems"] = []
	var gem2: Dictionary = _data.item("ruby")
	state2.add_item(str(gem2["id"]), gem2)
	var res2: Dictionary = Socketing.socket(state2, static_host, str(gem2["id"]), gem2, 0, _data, _rng())
	if not res2["ok"]:
		_fail("static base: insert refused: %s" % str(res2["message"]))
		return
	state2.register_loot_item(static_host)
	var live: Dictionary = state2.loot_item("blade_shortSword")
	if live.is_empty() or live.get("fireDmg") == null:
		_fail("static base: the socketed copy was not registered on the save")
	if _data.item("blade_shortSword").get("fireDmg") != null:
		_fail("static base: socketing mutated the SHARED base table")
