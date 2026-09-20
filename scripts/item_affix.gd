extends RefCounted
## The AFFIX LIST - D2 LoD's prefixes and suffixes as data.
##
## An affix is a named modifier rolled onto an item. D2's rule that makes it feel
## like D2 and not like a spreadsheet: an affix has a NAME that turns into the
## item's name ("Silový krátký meč"), a LEVEL it needs, and a group it belongs to
## (weapon-only, armour-only, jewellery-only). Two affixes from the same group can
## never land on one item, so a rare never rolls "+3 strength" twice.
##
## Every stat key below is consumed by scripts/hero_stats.gd - there are no
## decorative affixes. A modifier that nothing reads is worse than no affix at
## all, because it looks like a system while doing nothing.

const Slot := preload("res://scripts/item_base.gd").Slot

## group keys
const G_ATTR := "attr"
const G_VITAL := "vital"
const G_DAMAGE := "damage"
const G_ELEM := "elem"
const G_DEFENSE := "defense"
const G_RESIST := "resist"

## Affix definitions. `val` is [min, max]; `range` marks an affix whose roll is a
## pair (D2's "adds 3-10 fire damage") rather than a single number.
static func all() -> Dictionary:
	return {
		# ------------------------------------------------------- attributes
		"of_strength": {"name": "Silový", "kind": "prefix", "group": G_ATTR,
			"ilvl": 1, "slots": [], "stat": "strength", "val": [3, 8]},
		"of_dexterity": {"name": "Hbitý", "kind": "prefix", "group": G_ATTR,
			"ilvl": 1, "slots": [], "stat": "dexterity", "val": [3, 8]},
		"of_vitality": {"name": "Houževnatý", "kind": "prefix", "group": G_ATTR,
			"ilvl": 1, "slots": [], "stat": "vitality", "val": [3, 8]},
		"of_energy": {"name": "Moudrý", "kind": "prefix", "group": G_ATTR,
			"ilvl": 1, "slots": [], "stat": "energy", "val": [3, 8]},
		# ---------------------------------------------------------- vitals
		"of_life": {"name": "Životodárný", "kind": "prefix", "group": G_VITAL,
			"ilvl": 1, "slots": [], "stat": "life", "val": [15, 40]},
		"of_mana": {"name": "Zářící", "kind": "prefix", "group": G_VITAL,
			"ilvl": 1, "slots": [], "stat": "mana", "val": [10, 25]},
		# ----------------------------------------------------------- damage
		## D2's core weapon prefix: +% enhanced damage.
		"of_craft": {"name": "Ostřící", "kind": "prefix", "group": G_DAMAGE,
			"ilvl": 2, "slots": [Slot.MAIN_HAND], "stat": "enhanced_damage_pct",
			"val": [20, 60]},
		# ------------------------------------------------------- elemental
		"of_flame": {"name": "Plamenný", "kind": "prefix", "group": G_ELEM,
			"ilvl": 2, "slots": [Slot.MAIN_HAND], "stat": "fire_damage",
			"val": [3, 10], "range": true},
		"of_frost": {"name": "Mrazivý", "kind": "prefix", "group": G_ELEM,
			"ilvl": 2, "slots": [Slot.MAIN_HAND], "stat": "cold_damage",
			"val": [3, 10], "range": true},
		"of_storm": {"name": "Bouřný", "kind": "prefix", "group": G_ELEM,
			"ilvl": 2, "slots": [Slot.MAIN_HAND], "stat": "lightning_damage",
			"val": [3, 10], "range": true},
		# ---------------------------------------------------------- defense
		"of_hardiness": {"name": "Tuhý", "kind": "prefix", "group": G_DEFENSE,
			"ilvl": 1, "slots": [Slot.HELM, Slot.CHEST, Slot.OFF_HAND, Slot.GLOVES,
				Slot.BOOTS, Slot.BELT],
			"stat": "defense", "val": [10, 30]},
		# --------------------------------------------------------- resistance
		"suffix_fire": {"name": "ohně", "kind": "suffix", "group": G_RESIST,
			"ilvl": 3, "slots": [], "stat": "resist_fire", "val": [10, 25]},
		"suffix_cold": {"name": "chladu", "kind": "suffix", "group": G_RESIST,
			"ilvl": 3, "slots": [], "stat": "resist_cold", "val": [10, 25]},
		"suffix_light": {"name": "blesku", "kind": "suffix", "group": G_RESIST,
			"ilvl": 3, "slots": [], "stat": "resist_lightning", "val": [10, 25]},
		"suffix_poison": {"name": "jedu", "kind": "suffix", "group": G_RESIST,
			"ilvl": 3, "slots": [], "stat": "resist_poison", "val": [10, 25]},
	}


static func affix(id: String) -> Dictionary:
	var all := all()
	if not all.has(id):
		return {}
	return (all[id] as Dictionary).duplicate(true)


## Prefixes and suffixes the item's SLOT can carry at this item level, minus the
## groups already present (one affix per group, D2's rule).
static func candidates(slot: int, ilvl: int, taken_groups: Array, taken_ids: Array) -> Array:
	var out: Array = []
	for id in all():
		var a: Dictionary = all()[id]
		if int(a["ilvl"]) > ilvl:
			continue
		if taken_ids.has(id):
			continue
		if taken_groups.has(str(a["group"])):
			continue
		var slots: Array = a["slots"]
		if not slots.is_empty() and not slots.has(slot):
			continue
		out.append(id)
	return out


## How an affix reads on the item: "+5 k síle", "+12 k životům". Czech because
## the rest of the UI is Czech; a tooltip that mixes languages reads as a bug.
static func describe(a: Dictionary, roll) -> String:
	var stat := str(a.get("stat", ""))
	var v: float = 0.0
	if roll is Vector2:
		v = (roll as Vector2).y
	else:
		v = float(roll)
	match stat:
		"strength": return "+%d k síle" % int(v)
		"dexterity": return "+%d k obratnosti" % int(v)
		"vitality": return "+%d k vitalitě" % int(v)
		"energy": return "+%d k energii" % int(v)
		"life": return "+%d k životům" % int(v)
		"mana": return "+%d k maně" % int(v)
		"enhanced_damage_pct": return "+%d %% k poškození" % int(v)
		"defense": return "+%d k obraně" % int(v)
		"resist_fire": return "+%d %% odolnost proti ohni" % int(v)
		"resist_cold": return "+%d %% odolnost proti chladu" % int(v)
		"resist_lightning": return "+%d %% odolnost proti blesku" % int(v)
		"resist_poison": return "+%d %% odolnost proti jedu" % int(v)
	return stat


## Elemental rolls read as a pair, D2 style: "přidává 3-10 poškození ohněm".
static func describe_range(stat: String, roll: Vector2) -> String:
	match stat:
		"fire_damage": return "přidává %d-%d poškození ohněm" % [int(roll.x), int(roll.y)]
		"cold_damage": return "přidává %d-%d poškození chladem" % [int(roll.x), int(roll.y)]
		"lightning_damage": return "přidává %d-%d poškození bleskem" % [int(roll.x), int(roll.y)]
	return stat
