extends RefCounted
## ONE item on the ground or in a bag. Pure data + the handful of derived
## questions the UI and the stats code ask about it.
##
## Deliberately NOT a Node: an item exists in three places at once (a ground
## label, an inventory cell, an equip slot) and a Node would have to be moved
## between parents, which is how an item gets duplicated by a save/load or lost
## by a `queue_free`. The item is DATA; the nodes that draw it come and go.

const IB := preload("res://scripts/item_base.gd")
const IA := preload("res://scripts/item_affix.gd")

var base_id: String = ""
## Rolled rarity. A normal item has no affixes at all (D2 rule).
var rarity: int = IB.Rarity.NORMAL
## The item level the drop was rolled at. A "Krátký meč" that fell in a level-12
## area is worth more than one from the start, so this is kept even though the
## base type is the same.
var ilvl: int = 1

## Rolled affixes: [{"id": String, "roll": float | Vector2}, ...]
var affixes: Array = []

## Stable id of this instance, so a UI callback can name it without holding a
## reference that a re-sort could invalidate.
var uid: int = 0
static var _next_uid: int = 1


func _init(p_base_id: String = "", p_rarity: int = IB.Rarity.NORMAL, p_ilvl: int = 1) -> void:
	base_id = p_base_id
	rarity = p_rarity
	ilvl = p_ilvl
	uid = _next_uid
	_next_uid += 1


func base() -> Dictionary:
	return IB.base(base_id)


## The slot this item occupies when equipped.
func slot() -> int:
	return int(base().get("slot", IB.Slot.NONE))


## Grid footprint, `Vector2i(w, h)` in cells. Jan's Tetris rule: a ring is 1x1,
## a halberd 2x4.
func size() -> Vector2i:
	return base().get("size", Vector2i(1, 1))


func is_two_handed() -> bool:
	return bool(base().get("two_handed", false))


## D2 naming: "Silový krátký meč obrany". Prefix in front, suffix behind, base
## name in the middle, lower-cased the way Czech item names are written.
func display_name() -> String:
	var b := base()
	var nm := str(b.get("name", base_id)).to_lower()
	var pre := ""
	var suf := ""
	for a in affixes:
		var d: Dictionary = IA.affix(str(a["id"]))
		if d.is_empty():
			continue
		if str(d.get("kind", "prefix")) == "prefix":
			pre = str(d.get("name", "")) + " "
		else:
			suf = " " + str(d.get("name", ""))
	return pre + nm + suf


func rarity_color() -> Color:
	return IB.RARITY_COLORS.get(rarity, Color.WHITE)


func rarity_name() -> String:
	return str(IB.RARITY_NAMES.get(rarity, "?"))


# ------------------------------------------------------------------ stat maths
## Base weapon damage, and the elemental add-on, both rolled from the base type.
## `enhanced_damage_pct` is applied by hero_stats.gd over the summed base.
func base_damage() -> Vector2:
	return base().get("damage", Vector2.ZERO)


## Affixed defence, on top of the base type's own.
func base_defense() -> Vector2:
	return base().get("defense", Vector2.ZERO)


## Requirement to wear it. A hero below this cannot equip it - the D2 rule that
## makes attributes mean something long before any damage formula does.
func strength_requirement() -> int:
	return int(base().get("str_req", 0))


## Sum of every affix for one stat key. Range affixes (elemental damage) add
## their own two numbers, so this returns the MAX, and `stat_range()` returns the
## pair for a tooltip.
func stat_value(key: String) -> float:
	var total := 0.0
	for a in affixes:
		var d: Dictionary = IA.affix(str(a["id"]))
		if str(d.get("stat", "")) != key:
			continue
		var r: Variant = a["roll"]
		if r is Vector2:
			total += (r as Vector2).y
		else:
			total += float(r)
	return total


func has_stat(key: String) -> bool:
	for a in affixes:
		var d: Dictionary = IA.affix(str(a["id"]))
		if str(d.get("stat", "")) == key:
			return true
	return false


## Tooltip lines: the base line ("Poškození 16-25") plus one line per affix.
func tooltip_lines() -> Array:
	var out: Array = []
	var b := base()
	out.append("%s  (%s)" % [display_name(), rarity_name()])
	var dmg := base_damage()
	if dmg != Vector2.ZERO:
		out.append("Poškození: %d-%d" % [int(dmg.x), int(dmg.y)])
	var def := base_defense()
	if def != Vector2.ZERO:
		out.append("Obrana: %d-%d" % [int(def.x), int(def.y)])
	if strength_requirement() > 0:
		out.append("Síla %d" % strength_requirement())
	for a in affixes:
		var d: Dictionary = IA.affix(str(a["id"]))
		if d.is_empty():
			continue
		if bool(d.get("range", false)):
			out.append(IA.describe_range(str(d["stat"]), a["roll"] as Vector2))
		else:
			out.append(IA.describe(d, a["roll"]))
	return out


# ------------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	var rolls: Array = []
	for a in affixes:
		var r: Variant = a["roll"]
		rolls.append({"id": a["id"],
			"roll": ([r.x, r.y] if r is Vector2 else float(r))})
	return {"base": base_id, "rarity": rarity, "ilvl": ilvl, "rolls": rolls}


static func from_dict(d: Dictionary) -> RefCounted:
	var script: GDScript = load("res://scripts/item.gd")
	var it: RefCounted = script.new(
		str(d.get("base", "short_sword")), int(d.get("rarity", 0)), int(d.get("ilvl", 1)))
	for r in d.get("rolls", []):
		var v: Variant = r["roll"]
		var roll: Variant
		if v is Array:
			var arr: Array = v
			roll = Vector2(float(arr[0]), float(arr[1]))
		else:
			roll = float(v)
		it.affixes.append({"id": str(r["id"]), "roll": roll})
	return it
