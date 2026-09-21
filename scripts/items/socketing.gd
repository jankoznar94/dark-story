extends RefCounted
class_name Socketing
## Socketing — putting a gem or a jewel into an item's socket, and what that does to
## the item's stats. Ported from the PWA's `applyGemStats` / `applyJewelStats` and the
## gem-select click handler.
##
## The rules, and why they are here rather than in the screen:
##
##   1. Which stat a gem grants depends on HOST TYPE, not on the gem: a ruby is fire
##      damage in a weapon, +HP in armour and fire resist in a shield. One table, three
##      readings — that is why GEMS.json has `weapon` / `armor` / `shield` sub-tables.
##   2. A socket holds one gem and never gets a second one. An occupied socket refuses;
##      it does not overwrite.
##   3. A JEWEL applies every affix it carries to the host, like a gem that can hold
##      four rolls of anything.
##
## The host item's stats are MUTATED — a socketed item's stats are part of the item, so
## a save/load has to keep them, and the PWA mutated in place for the same reason. The
## caller owns the save().
##
## Everything is a pure function of (item, gem, tables), so a headless test can pin it.

const ITEM_SLOT_KEY := "socketedGems"

const ItemGen := preload("res://scripts/items/item_gen.gd")

## Every stat a gem or jewel can write, so an item always has the keys and the UI does
## not have to guess whether a missing key means 0 or "not computed".
const ELEMENTAL := ["fireDmg", "coldDmg", "lightningDmg", "poisonDmg"]


## Can this gem go into this socket? Returns "" when it can, else the reason.
static func can_socket(host: Dictionary, gem: Dictionary, socket_index: int) -> String:
	if host.is_empty():
		return "Zadny predmet"
	if str(gem.get("type", "")) not in ["gem", "jewel"]:
		return "Toto neni gem ani jewel"
	var sockets := int(host.get("sockets", 0))
	if sockets <= 0:
		return "Predmet nema socket"
	if socket_index < 0 or socket_index >= sockets:
		return "Neplatny socket"
	var filled: Array = host.get(ITEM_SLOT_KEY, [])
	if socket_index < filled.size() and filled[socket_index] != null:
		return "Socket je obsazeny"
	return ""


## Insert a gem or jewel into a socket: consume it from the bag, record it on the host
## and apply its stats. Returns {ok, message}.
##
## `gem_id` is removed from the bag only once the insert is certain — a refused socket
## must not eat the gem.
static func socket(state, host: Dictionary, gem_id: String, gem: Dictionary,
		socket_index: int, data: Node, rng: RandomNumberGenerator) -> Dictionary:
	var reason := can_socket(host, gem, socket_index)
	if reason != "":
		return {"ok": false, "message": reason}
	if ItemGen.stack_count(state.inventory(), gem_id) <= 0:
		return {"ok": false, "message": "Gem nemas v inventari"}

	# Grow the record to the socket count so index positions are stable.
	var filled: Array = host.get(ITEM_SLOT_KEY, [])
	while filled.size() < int(host.get("sockets", 0)):
		filled.append(null)

	var is_jewel := str(gem.get("type", "")) == "jewel"
	if is_jewel:
		filled[socket_index] = {"type": "jewel", "jewelId": gem_id, "name": str(gem.get("name", "Jewel"))}
		apply_jewel_stats(host, gem, rng)
	else:
		filled[socket_index] = {
			"type": str(gem.get("gemType", "")),
			"quality": str(gem.get("gemQuality", "")),
			"name": str(gem.get("name", "")),
		}
		apply_gem_stats(host, str(gem.get("gemType", "")), str(gem.get("gemQuality", "")), data)

	host[ITEM_SLOT_KEY] = filled
	state.remove_item(gem_id)
	return {"ok": true, "message": "%s vlozen do socketu" % str(gem.get("name", gem_id))}


## The stat a gem grants its host. Which of the three sub-tables is read depends on the
## host's TYPE — a ruby is fire damage in a weapon, +HP in armour, fire resist in a
## shield. Elemental damage is a [min, max] pair and ADDS onto any existing range.
static func apply_gem_stats(host: Dictionary, gem_type: String, gem_quality: String,
		data: Node) -> void:
	var gems: Dictionary = data.gems()
	var gem: Dictionary = gems.get(gem_type, {})
	if gem.is_empty():
		return
	var q_data: Dictionary = gem.get("qualities", {}).get(gem_quality, {})
	if q_data.is_empty():
		return
	var host_type := str(host.get("type", ""))
	var stats: Dictionary = {}
	if host_type == "weapon":
		stats = q_data.get("weapon", {})
	elif host_type == "shield":
		stats = q_data.get("shield", {})
	else:
		stats = q_data.get("armor", {})
	_apply_stats(host, stats)


## A jewel carries its own rolled affixes and applies every one of them, exactly like a
## gem — but with no host-type table in between.
##
## The affix lines are RANGES to roll, and the PWA rolled them at INSERT time, so the
## same jewel socketed twice is not the same item. `rng` is passed in rather than held
## here so a test can pin the result.
static func apply_jewel_stats(host: Dictionary, jewel: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var affixes: Array = jewel.get("affixes", [])
	if not affixes.is_empty():
		for affix in affixes:
			var stats: Dictionary = (affix as Dictionary).get("stats", {})
			for stat in stats:
				_apply_rolled(host, stat, stats[stat], jewel, rng)
		return
	# A jewel with no affix list carries its rolled stats directly (that is how the
	# port's own generate_jewel stores one), so those are read as-is.
	for stat in jewel:
		if stat in ["id", "name", "type", "affixes", "quality", "rarity", "ilvl",
				"jewelColor", "iconImg", "cost", "tier", "_classSkillsClass"]:
			continue
		var value: Variant = jewel[stat]
		if value is int and int(value) != 0:
			_apply_stats(host, {stat: value})


## Add a table of stat -> value|range onto the host. Elemental rolls add as a range.
static func _apply_stats(host: Dictionary, stats: Dictionary) -> void:
	for stat in stats:
		var value: Variant = stats[stat]
		if value is Array:
			# An elemental roll is a [min, max] pair in the GEMS table. Anything else
			# stored as a pair (a classSkills triple, say) is not a range — take the max.
			if stat in ELEMENTAL:
				var lo := int((value as Array)[0]) if (value as Array).size() > 0 else 0
				var hi := int((value as Array)[1]) if (value as Array).size() > 1 else lo
				host[stat] = _add_range(host.get(stat), lo, hi)
			else:
				# Not a range: take the upper bound of the pair, as the PWA did.
				var pair: Array = value
				host[stat] = int(host.get(stat, 0)) + (int(pair[1]) if pair.size() > 1 else int(pair[0]))
		else:
			host[stat] = int(host.get(stat, 0)) + int(value)


## An affix's stat line is a RANGE, rolled at insert time — that is what the PWA did, so
## the same jewel socketed into two items does not give an identical number.
static func _apply_rolled(host: Dictionary, stat: String, value: Variant, jewel: Dictionary,
		rng: RandomNumberGenerator) -> void:
	if stat == "allRes":
		var v := _roll(rng, value)
		for res in ["fireRes", "coldRes", "lightningRes", "poisonRes"]:
			host[res] = int(host.get(res, 0)) + v
		return
	if stat == "classSkills":
		# classSkills is [className, min, max] — a three-element array whose first
		# entry is a string, so it must never go through _roll.
		var rolled := _roll(rng, [value[1], value[2]])
		host["classSkills"] = int(host.get("classSkills", 0)) + rolled
		host["_classSkillsClass"] = value[0]
		return
	if stat == "swingMs":
		host[stat] = int(host.get(stat, 0)) + _roll(rng, value)
		return
	if stat in ELEMENTAL:
		var lo := int(jewel.get(stat, 0))
		host[stat] = _add_range(host.get(stat), lo, lo)
		return
	host[stat] = int(host.get(stat, 0)) + _roll(rng, value)


## Roll a value that is either a scalar or a [min, max] pair.
static func _roll(rng: RandomNumberGenerator, value: Variant) -> int:
	if value is Array:
		var arr: Array = value
		var lo := int(arr[0]) if arr.size() > 0 else 0
		var hi := int(arr[1]) if arr.size() > 1 else lo
		return lo + rng.randi_range(0, maxi(hi - lo, 0))
	return int(value)


static func _rolled_from(jewel: Dictionary, key: String) -> int:
	return int(jewel.get(key, 0))


static func _add_range(existing: Variant, lo: int, hi: int) -> Array:
	if existing is Array:
		var arr: Array = existing
		var e_lo := int(arr[0]) if arr.size() > 0 else 0
		var e_hi := int(arr[1]) if arr.size() > 1 else e_lo
		return [e_lo + lo, e_hi + hi]
	var base := int(existing) if existing != null else 0
	return [base + lo, base + hi]
