extends RefCounted
## Rolls items. The ONE place that decides what falls out of a monster, so a
## balance change is an edit here rather than a hunt through the AI.
##
## Distribution rules, all from D2 LoD:
##   * a rarity is rolled first (mostly normal), then affixes are rolled ON TOP
##     of the base type - the base type is never chosen by rarity;
##   * affixes never repeat a GROUP (no two strength rolls on one rare);
##   * a magic item gets 1-2 affixes, a rare 3-4, a normal none;
##   * the base type is filtered by item level, so early drops are daggers and
##     caps and later ones are halberds and plate.

const IB := preload("res://scripts/item_base.gd")
const IA := preload("res://scripts/item_affix.gd")
const Item := preload("res://scripts/item.gd")

## A monster drops at most this many items. Deliberately small: the banned
## pattern for this game is "showers of loot" (see the pacing rules), so a pack
## of six should give the player a handful of things to look at, not a carpet.
const MAX_DROPS := 2

## Jan's setting for the loot-testing pass (Sept 2026): "for testing, make the
## drop chance 100 %". A monster that died always leaves a body with something in
## it, so the open-a-body loop can be judged without rolling for it. It is one
## CONSTANT on purpose - the D2 rate (55 %) comes back by putting it to 0.55, and
## `tools/test_inventory.gd` checks the shape of the distribution against this
## value rather than against a stored histogram.
const DROP_CHANCE := 1.0


## One item for an area / monster of level `ilvl`. `slot_filter` of
## Slot.NONE means "anything".
static func roll(ilvl: int, slot_filter: int = IB.Slot.NONE, rng: RandomNumberGenerator = null) -> RefCounted:
	var r: RandomNumberGenerator = rng if rng != null else _rng()

	var pool := IB.droppable(ilvl, slot_filter)
	if pool.is_empty():
		pool = IB.droppable(99, slot_filter)
	var base_id: String = pool[r.randi() % pool.size()]

	var rarity := _roll_rarity(ilvl, r)
	var it: RefCounted = Item.new(base_id, rarity, ilvl)
	it.affixes = _roll_affixes(it, rarity, r)
	return it


## What a monster leaves behind. Returns an Array of items (possibly empty) - the
## caller puts them inside a body.
static func roll_drop(ilvl: int, rng: RandomNumberGenerator = null) -> Array:
	var r: RandomNumberGenerator = rng if rng != null else _rng()
	var out: Array = []
	# DROP_CHANCE is 1.0 for the testing pass, so every corpse has something to
	# open. At the D2 setting (0.55) the rest of the monsters leave nothing, which
	# is what keeps an item feeling like an event rather than furniture.
	if r.randf() > DROP_CHANCE:
		return out
	var n := 1
	if r.randf() < 0.18:
		n = 2
	for i in n:
		# gold is not a currency yet, so every drop is a real object
		out.append(roll(ilvl, IB.Slot.NONE, r))
	return out


static func _roll_rarity(ilvl: int, r: RandomNumberGenerator) -> int:
	var w := IB.rarity_weights(ilvl)
	var total := w.x + w.y + w.z
	var t := r.randf() * total
	if t < w.x:
		return IB.Rarity.NORMAL
	if t < w.x + w.y:
		return IB.Rarity.MAGIC
	return IB.Rarity.RARE


## Rolls the affixes for an item, honouring the group rule and the item level.
static func _roll_affixes(it: RefCounted, rarity: int, r: RandomNumberGenerator) -> Array:
	var band: Vector2i = IB.AFFIX_COUNT.get(rarity, Vector2i(0, 0))
	if band.y <= 0:
		return []
	var want := band.x + r.randi() % (band.y - band.x + 1)
	var out: Array = []
	var groups: Array = []
	var used: Array = []
	for i in want:
		var cands := IA.candidates(it.slot(), it.ilvl, groups, used)
		if cands.is_empty():
			break
		var id: String = cands[r.randi() % cands.size()]
		var d: Dictionary = IA.affix(id)
		var lo: float = float(d["val"][0])
		var hi: float = float(d["val"][1])
		# scale the roll with the item level: a level-1 rare is not a level-20 one
		var boost := 1.0 + float(maxi(0, it.ilvl - 1)) * 0.06
		var roll: Variant = Vector2(roundf(lo * boost), roundf(hi * boost)) \
			if bool(d.get("range", false)) else float(roundf(r.randf_range(lo, hi) * boost))
		out.append({"id": id, "roll": roll})
		groups.append(str(d["group"]))
		used.append(id)
	return out


## A generator seeded per call unless a caller passes one. Tests pass a seeded
## RNG so a distribution claim is reproducible.
static func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r


## The hero's starting gear: exactly one hand-made weapon, no affixes, the same
## numbers the game had before items existed.
static func starter_loadout() -> Array:
	var w: RefCounted = Item.new(IB.starter_weapon_id(), IB.Rarity.NORMAL, 1)
	return [w]


## Build a specific item, used by tests and by the developer spawner. `affix_ids`
## is a list of ids; pass [] for a plain base item.
static func make(base_id: String, rarity: int = IB.Rarity.NORMAL, ilvl: int = 1,
		affix_ids: Array = []) -> RefCounted:
	var it: RefCounted = Item.new(base_id, rarity, ilvl)
	for id in affix_ids:
		var d: Dictionary = IA.affix(str(id))
		if d.is_empty():
			continue
		var v: Array = d["val"]
		var roll: Variant = Vector2(v[0], v[1]) if bool(d.get("range", false)) else float(v[1])
		it.affixes.append({"id": str(id), "roll": roll})
	return it
