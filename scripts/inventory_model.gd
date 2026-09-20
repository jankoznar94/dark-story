extends RefCounted
## The D2 "Tetris" inventory and the ten equipment slots, as PURE DATA.
##
## No Nodes, no Control, no drawing: the grid is a claim about where things are,
## and every rule the player feels ("a halberd is 2x4", "a two-hander blocks the
## off hand", "two rings, not one") is decided here and asserted in
## tools/test_inventory.gd. The window that draws it reads this and nothing else,
## so the UI can be redone without touching a single gameplay rule.
##
## Jan's brief: "the inventory is very similar to D2 LoD - a grid of squares,
## every item with its own shape, and the player plays Tetris. And there are
## equip slots like in D2: helm, amulet, two rings, main hand, off hand, chest,
## belt, boots, gloves."

const IB := preload("res://scripts/item_base.gd")

## The bag. D2's own inventory is 10x4. Kept at exactly that, because the whole
## point of the shape sizes is that the space is TIGHT.
const COLS := 10
const ROWS := 4

## The ten equipment slots, in D2's arrangement: a column of armour down the
## left, jewellery in the middle, the two hands on the right.
const SLOTS := [
	IB.Slot.HELM,
	IB.Slot.CHEST,
	IB.Slot.BELT,
	IB.Slot.BOOTS,
	IB.Slot.GLOVES,
	IB.Slot.AMULET,
	IB.Slot.RING,       ## ring 1
	IB.Slot.RING,       ## ring 2 - the SAME slot id, two distinct positions
	IB.Slot.MAIN_HAND,
	IB.Slot.OFF_HAND,
]

## Which of the two ring positions a slot index is: -1 for everything else.
static func ring_index_of(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= SLOTS.size():
		return -1
	if SLOTS[slot_index] != IB.Slot.RING:
		return -1
	var n := 0
	for i in slot_index:
		if SLOTS[i] == IB.Slot.RING:
			n += 1
	return n


## True when the slot at `i` is the SECOND ring. Used only for labelling.
static func is_second_ring(i: int) -> bool:
	return ring_index_of(i) == 1


## The bag: a list of placements, one per item.
##   {"item": Item, "pos": Vector2i, "size": Vector2i}
var placements: Array = []

## Equipped items, indexed by SLOT index (see SLOTS). null = empty.
var equipped: Array = []

## Signals, so the UI can refresh without polling. RefCounted supports them.
signal changed()


func _init() -> void:
	equipped.resize(SLOTS.size())
	for i in equipped.size():
		equipped[i] = null


# ------------------------------------------------------------------ occupancy
## Cells covered by a placement, as "x,y" keys. Used for overlap and for drawing.
static func cells_of(pos: Vector2i, size: Vector2i) -> Array:
	var out: Array = []
	for y in size.y:
		for x in size.x:
			out.append(Vector2i(pos.x + x, pos.y + y))
	return out


## Is `size` at `pos` fully inside the bag?
func fits_in_bounds(pos: Vector2i, size: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x + size.x <= COLS and pos.y + size.y <= ROWS


## May an item of `size` be placed at `pos`? `ignore` is a placement index to
## skip (used when moving an item that is already in the bag, so it does not
## collide with itself).
func can_place(pos: Vector2i, size: Vector2i, ignore: int = -1) -> bool:
	if not fits_in_bounds(pos, size):
		return false
	for i in placements.size():
		if i == ignore:
			continue
		var p: Dictionary = placements[i]
		if _overlaps(pos, size, p["pos"], p["size"]):
			return false
	return true


static func _overlaps(a_pos: Vector2i, a_size: Vector2i, b_pos: Vector2i, b_size: Vector2i) -> bool:
	return a_pos.x < b_pos.x + b_size.x and b_pos.x < a_pos.x + a_size.x \
		and a_pos.y < b_pos.y + b_size.y and b_pos.y < a_pos.y + a_size.y


## The first free spot big enough for `size`, scanning row by row like D2's own
## auto-placement. Returns Vector2i(-1, -1) when the bag is full.
func find_free(size: Vector2i, ignore: int = -1) -> Vector2i:
	for y in ROWS:
		for x in COLS:
			var p := Vector2i(x, y)
			if can_place(p, size, ignore):
				return p
	return Vector2i(-1, -1)


func placement_index_of(item) -> int:
	for i in placements.size():
		if placements[i]["item"] == item:
			return i
	return -1


## Adds an item to the first free spot. Returns true when it fit. The caller is
## expected to say something when it does not - a silently swallowed drop is the
## worst possible outcome for a loot game.
func add(item) -> bool:
	var sz: Vector2i = item.size()
	var pos := find_free(sz)
	if pos.x < 0:
		return false
	placements.append({"item": item, "pos": pos, "size": sz})
	changed.emit()
	return true


## Places (or moves) an item at an exact cell. Used by drag & drop.
func place_at(item, pos: Vector2i, ignore: int = -1) -> bool:
	var sz: Vector2i = item.size()
	var idx := placement_index_of(item)
	var ig := idx if ignore < 0 else ignore
	if not can_place(pos, sz, ig):
		return false
	if idx >= 0:
		placements[idx]["pos"] = pos
		placements[idx]["size"] = sz
	else:
		placements.append({"item": item, "pos": pos, "size": sz})
	changed.emit()
	return true


func remove(item) -> bool:
	var idx := placement_index_of(item)
	if idx < 0:
		return false
	placements.remove_at(idx)
	changed.emit()
	return true


func clear() -> void:
	placements.clear()
	for i in equipped.size():
		equipped[i] = null
	changed.emit()


# ------------------------------------------------------------------ equipment
## Equip `item` from the bag into the slot that suits it. Handles D2's awkward
## cases in one place, so no caller has to know them:
##   * the second ring goes to the free ring position;
##   * a two-handed weapon empties the off hand (and cannot be equipped while an
##     off-hand item is worn);
##   * whatever was already in the slot goes back to the bag.
## Returns {"ok": bool, "moved_to_bag": Item|Array|null, "reason": String}.
##
## `only_slot` pins the target slot, which is what a DRAG & DROP into a specific
## box means: dropping a helm onto the boots box must be refused, not quietly
## equipped as a helm. -1 = "find the right box yourself" (a double click).
func equip(item, only_slot: int = -1) -> Dictionary:
	var slot: int = item.slot()
	if slot == IB.Slot.NONE:
		return _deny("Tento předmět nelze nasadit.")
	if only_slot >= 0:
		if only_slot >= SLOTS.size() or SLOTS[only_slot] != slot:
			return _deny("Sem tento předmět nepatří.")

	# --- two-handed rules (D2) -------------------------------------------------
	if item.is_two_handed() and _slot_index(IB.Slot.OFF_HAND) >= 0 \
			and equipped[_slot_index(IB.Slot.OFF_HAND)] != null:
		return _deny("Obouruční zbraň - nejdřív sundej předmět z levé ruky.")
	# a shield / off-hand item cannot go on while a two-hander is worn
	if slot == IB.Slot.OFF_HAND and _main_hand_is_two_handed():
		return _deny("V pravé ruce držíš obouruční zbraň.")

	var target := (only_slot if only_slot >= 0 else _slot_for(slot))
	if target < 0:
		return _deny("Nemáš volné místo pro tento předmět.")

	var prev: Variant = equipped[target]
	equipped[target] = item
	remove(item)
	var out: Variant = null
	if prev != null:
		# whatever came off has to go back to the bag, unless it came off because
		# of the two-hander rule (handled below)
		if not add(prev):
			# no room: put it back and refuse, so an item is never destroyed
			equipped[target] = prev
			add(item)
			return _deny("V inventáři není místo pro sundanný předmět.")
		out = prev

	if item.is_two_handed():
		var off := _slot_index(IB.Slot.OFF_HAND)
		if off >= 0 and equipped[off] != null:
			if not add(equipped[off]):
				return _deny("V inventáři není místo pro předmět z levé ruky.")
			equipped[off] = null

	changed.emit()
	return {"ok": true, "moved_to_bag": out, "reason": ""}


## Takes an equipped item off and returns it to the bag. Returns the item, or
## null when it did not fit (in which case nothing changed).
func unequip(slot_index: int):
	if slot_index < 0 or slot_index >= equipped.size():
		return null
	var it: Variant = equipped[slot_index]
	if it == null:
		return null
	if not add(it):
		return null
	equipped[slot_index] = null
	changed.emit()
	return it


## Which equipped item, if any, makes the off hand illegal.
func _main_hand_is_two_handed() -> bool:
	var mh := _slot_index(IB.Slot.MAIN_HAND)
	if mh < 0 or equipped[mh] == null:
		return false
	return equipped[mh].is_two_handed()


## The slot index an item of `slot` should go into: the first free one, falling
## back to the first (so equipping over an existing item REPLACES it, D2 style).
func _slot_for(slot: int) -> int:
	var first := -1
	for i in SLOTS.size():
		if SLOTS[i] != slot:
			continue
		if first < 0:
			first = i
		if equipped[i] == null:
			return i
	return first


func _slot_index(slot: int) -> int:
	for i in SLOTS.size():
		if SLOTS[i] == slot:
			return i
	return -1


func _deny(reason: String) -> Dictionary:
	return {"ok": false, "moved_to_bag": null, "reason": reason}


## Equips an item only if the hero actually meets its Strength requirement - the
## D2 gate that makes an attribute worth spending points on. `stats` is a
## hero_stats.gd. Kept here rather than in the UI so the rule is one function.
func equip_with_requirement(item, stats) -> Dictionary:
	if stats != null and not can_carry(int(stats.strength()), item):
		return _deny("Potřebuješ sílu %d." % int(item.strength_requirement()))
	return equip(item)


# ------------------------------------------------------------------ queries
func equipped_at(i: int):
	if i < 0 or i >= equipped.size():
		return null
	return equipped[i]


## The main-hand weapon, or null. Everything the combat code needs goes through
## this so "unarmed" is a state and not a crash.
func main_hand():
	return equipped_at(_slot_index(IB.Slot.MAIN_HAND))


func off_hand():
	return equipped_at(_slot_index(IB.Slot.OFF_HAND))


## Every item the hero wears, in slot order. Affix totals and requirements are
## summed over this.
func equipped_items() -> Array:
	var out: Array = []
	for it in equipped:
		if it != null:
			out.append(it)
	return out


func bag_items() -> Array:
	var out: Array = []
	for p in placements:
		out.append(p["item"])
	return out


func used_cells() -> int:
	var n := 0
	for p in placements:
		n += int(p["size"].x) * int(p["size"].y)
	return n


func total_cells() -> int:
	return COLS * ROWS


## The hero's Strength has to cover every item worn and carried - the D2 rule
## that makes a plate mail a decision rather than a free upgrade.
static func can_carry(strength: int, item) -> bool:
	return strength >= int(item.strength_requirement())


# ------------------------------------------------------------------ dev helpers
## Drops a whole pre-made kit into the bag, packing it tightly. Used by the dev
## spawner and by tests; never by gameplay.
func fill(items: Array) -> Array:
	var refused: Array = []
	for it in items:
		if not add(it):
			refused.append(it)
	changed.emit()
	return refused
