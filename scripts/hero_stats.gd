extends RefCounted
## The hero's STAT SHEET: everything the player sees on the stat page, derived
## from ONE place, so gear can never disagree with the numbers the game runs on.
##
## The rule that keeps this honest: player.gd does not know what an affix is.
## It asks this object for `max_hp()`, `damage_range()`, `defense()`,
## `resist(...)` and the two speeds. The item system changes the INPUT; this
## turns it into the numbers the game already used.
##
## The locked numbers survive exactly. At level 1 with the starting weapon and
## nothing else equipped:
##   max_hp      105 + 25 * 3 = 180        (player.gd's old max_hp was 180)
##   damage      16-25                     (the sword's own roll)
##   walk / run  1.8 / 3.05                (the pacing lock, unchanged by gear)
## tools/test_stats.gd asserts those three lines, so a future "improvement" that
## quietly moves them fails a test instead of being noticed on Jan's phone.

const IB := preload("res://scripts/item_base.gd")

## ---------------------------------------------------------------- base numbers
## A level-1 melee hero. Attributes are D2-shaped (base 20-30, gear pushes them
## up) and are what the Strength requirements on items are measured against.
const BASE_STRENGTH := 30
const BASE_DEXTERITY := 25
const BASE_VITALITY := 25
const BASE_ENERGY := 20

## Vitals formulas. `base_life + vitality * VIT_TO_LIFE` is the D2 shape, with
## the constants chosen so the level-1 total lands exactly on the old max_hp.
const BASE_LIFE := 105.0
const VIT_TO_LIFE := 3.0
const BASE_MANA := 40.0
const ENERGY_TO_MANA := 4.0

## Per-level gains, defined now so the stat page and a future level-up share the
## same formula. At level 1 none of these apply, which is why the locked numbers
## above hold today.
const LIFE_PER_LEVEL := 12.0
const MANA_PER_LEVEL := 6.0
const ATTR_PER_LEVEL := 5

## D2's resistance cap. A resistance above 75 % is useless, and the sheet says so.
const RESIST_CAP := 75.0

## The pacing lock (see player.gd and the SKILL notes). Gear does NOT move these:
## D2 does not slow the character for wearing plate either, and "run speed" here
## is the design, not a derived number.
const WALK_SPEED := 1.8
const RUN_SPEED := 3.05

## Every resistance the sheet lists, in the order it draws them.
const RESISTS := ["resist_fire", "resist_cold", "resist_lightning", "resist_poison"]

var level: int = 1
## Points the player has spent on attributes, added to the bases above.
var alloc: Dictionary = {"strength": 0, "dexterity": 0, "vitality": 0, "energy": 0}
## Unspent attribute points. A level-up grants ATTR_PER_LEVEL.
var unspent_points: int = 0
## Cached derivations - rebuilt on `recompute()`.
var _cache: Dictionary = {}
var _equipped_items: Array = []


func _init(p_level: int = 1) -> void:
	level = maxi(1, p_level)
	recompute([])


## Called whenever the equipment changes. `items` is inventory.equipped_items().
func recompute(items: Array) -> void:
	_equipped_items = items
	_cache = {}
	_cache["strength"] = _attr("strength")
	_cache["dexterity"] = _attr("dexterity")
	_cache["vitality"] = _attr("vitality")
	_cache["energy"] = _attr("energy")
	_cache["life"] = _vital("life", BASE_LIFE, VIT_TO_LIFE * _attr("vitality"))
	_cache["mana"] = _vital("mana", BASE_MANA, ENERGY_TO_MANA * _attr("energy"))


func _attr(name: String) -> int:
	var base := BASE_STRENGTH
	match name:
		"dexterity": base = BASE_DEXTERITY
		"vitality": base = BASE_VITALITY
		"energy": base = BASE_ENERGY
	return int(base + int(alloc.get(name, 0)) + _affix_total(name))


## A flat pool (life / mana): base + per-point bonus + level gains + affixes.
func _vital(key: String, base: float, per_point: float) -> float:
	var level_gain: float = (LIFE_PER_LEVEL if key == "life" else MANA_PER_LEVEL) \
		* float(level - 1)
	return base + per_point + level_gain + _affix_total(key)


func _affix_total(key: String) -> float:
	var total := 0.0
	for it in _equipped_items:
		total += float(it.stat_value(key))
	return total


func _affix_total_int(key: String) -> int:
	return int(round(_affix_total(key)))


# ------------------------------------------------------------------ accessors
func strength() -> int:
	return int(_cache.get("strength", BASE_STRENGTH))


func dexterity() -> int:
	return int(_cache.get("dexterity", BASE_DEXTERITY))


func vitality() -> int:
	return int(_cache.get("vitality", BASE_VITALITY))


func energy() -> int:
	return int(_cache.get("energy", BASE_ENERGY))


func max_hp() -> float:
	return float(_cache.get("life", BASE_LIFE))


func max_mana() -> float:
	return float(_cache.get("mana", BASE_MANA))


## Physical damage the main hand deals, with the D2 shape:
##   base damage (rolled on the weapon type)
##   + elemental affix damage (a flat add)
##   then enhanced_damage_pct multiplies the PHYSICAL part only.
## Unarmed: a small flat range, so the hero is never a zero-damage object.
const UNARMED := Vector2(3.0, 6.0)


func damage_range() -> Vector2:
	var lo := 0.0
	var hi := 0.0
	for it in _equipped_items:
		var d: Vector2 = it.base_damage()
		lo += d.x
		hi += d.y
	if lo <= 0.0 and hi <= 0.0:
		return UNARMED
	for it in _equipped_items:
		lo += it.stat_value("fire_damage")
		hi += it.stat_value("fire_damage")
		lo += it.stat_value("cold_damage")
		hi += it.stat_value("cold_damage")
		lo += it.stat_value("lightning_damage")
		hi += it.stat_value("lightning_damage")
	var pct := 1.0 + _affix_total("enhanced_damage_pct") / 100.0
	lo *= pct
	hi *= pct
	return Vector2(lo, hi)


## Total defence: the rolled range on worn armour, plus flat affix defence.
func defense() -> Vector2:
	var lo := 0.0
	var hi := 0.0
	for it in _equipped_items:
		var d: Vector2 = it.base_defense()
		lo += d.x
		hi += d.y
	var flat := _affix_total("defense")
	lo += flat
	hi += flat
	return Vector2(lo, hi)


## One resistance, capped the way D2 caps it.
func resist(key: String) -> float:
	return clampf(_affix_total(key), -100.0, RESIST_CAP)


func resists() -> Dictionary:
	var out := {}
	for k in RESISTS:
		out[k] = resist(k)
	return out


func walk_speed() -> float:
	return WALK_SPEED


func run_speed() -> float:
	return RUN_SPEED


## The stat page, as rows of [label, value]. One source for the UI, so a number
## can never be shown that the game does not use.
func sheet() -> Array:
	var dmg := damage_range()
	var def := defense()
	var rows: Array = [
		["Úroveň", str(level)],
		["Síla", str(strength())],
		["Obratnost", str(dexterity())],
		["Vitalita", str(vitality())],
		["Energie", str(energy())],
		["Životy", "%d / %d" % [int(max_hp()), int(max_hp())]],
		["Mana", "%d / %d" % [int(max_mana()), int(max_mana())]],
		["Útok", "%d-%d" % [int(dmg.x), int(dmg.y)]],
		["Obrana", "%d-%d" % [int(def.x), int(def.y)]],
		["Rychlost chůze", "%.2f m/s" % walk_speed()],
		["Rychlost běhu", "%.2f m/s" % run_speed()],
	]
	for k in RESISTS:
		rows.append([_resist_label(k), "%d %%" % int(resist(k))])
	if unspent_points > 0:
		rows.append(["Nerozdané body", str(unspent_points)])
	return rows


static func _resist_label(key: String) -> String:
	match key:
		"resist_fire": return "Odolnost oheň"
		"resist_cold": return "Odolnost chlad"
		"resist_lightning": return "Odolnost blesk"
		"resist_poison": return "Odolnost jed"
	return key


## Spends a point on an attribute, D2 style. Returns false when there is nothing
## to spend.
func spend_point(attr: String) -> bool:
	if unspent_points <= 0 or not alloc.has(attr):
		return false
	alloc[attr] = int(alloc.get(attr, 0)) + 1
	unspent_points -= 1
	recompute(_equipped_items)
	return true


func grant_level(points: int = ATTR_PER_LEVEL) -> void:
	level += 1
	unspent_points += points
	recompute(_equipped_items)
