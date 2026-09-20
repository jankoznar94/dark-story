extends RefCounted
## The ITEM CATALOGUE - data only, no logic.
##
## Jan's brief: "we hold to the principles of Diablo 2 LoD". So an item is a BASE
## TYPE (a short sword, a cap) that carries its own grid footprint, its own
## requirements and its own base numbers, plus - depending on rarity - a few
## AFFIXES rolled on top. `item.gd` is one instance, `item_gen.gd` rolls one,
## `item_affix.gd` is the affix list.
##
## GRID FOOTPRINT is the whole reason this is data: Jan wants D2's "Tetris"
## inventory, where a ring is 1 cell and a halberd is 2x4. Sizes below are D2's
## own, shrunk to the range Jan named (smallest 1 cell, mid 2x2, largest 2x4).
##
## SLOT and SIZE are separate: a belt is a real equipment slot and only 2x1 of
## grid, while a halberd is 2x4 and blocks the off hand.

enum Slot { NONE, HELM, AMULET, RING, MAIN_HAND, OFF_HAND, CHEST, BELT, BOOTS, GLOVES }
enum Rarity { NORMAL, MAGIC, RARE }

## Czech UI labels - the HUD is Czech (see hud.gd) and the game ships to Jan.
const SLOT_NAMES := {
	Slot.HELM: "Přilba",
	Slot.AMULET: "Amulet",
	Slot.RING: "Prsten",
	Slot.MAIN_HAND: "Pravá ruka",
	Slot.OFF_HAND: "Levá ruka",
	Slot.CHEST: "Zbroj",
	Slot.BELT: "Pás",
	Slot.BOOTS: "Boty",
	Slot.GLOVES: "Rukavice",
}

const RARITY_NAMES := {
	Rarity.NORMAL: "Běžný",
	Rarity.MAGIC: "Magický",
	Rarity.RARE: "Vzácný",
}

## D2's own label colours: white, magic blue, rare yellow. No glow, no outline -
## the colour alone carries the rarity (art rule: flat toning).
const RARITY_COLORS := {
	Rarity.NORMAL: Color(0.86, 0.84, 0.78),
	Rarity.MAGIC: Color(0.42, 0.56, 0.95),
	Rarity.RARE: Color(0.95, 0.84, 0.32),
}

## How many affixes each rarity rolls. Normal items get none (D2), magic 1-2,
## rare 3-4.
const AFFIX_COUNT := {
	Rarity.NORMAL: Vector2i(0, 0),
	Rarity.MAGIC: Vector2i(1, 2),
	Rarity.RARE: Vector2i(3, 4),
}

## Drop chance of each rarity, by the item level of the drop. Read as
## [normal, magic, rare]; D2 is overwhelmingly normal, which is what keeps the
## arena from becoming a "shower of loot" (banned pattern).
const RARITY_WEIGHTS := [
	Vector3(88.0, 10.0, 2.0),    ## ilvl 1-4
	Vector3(80.0, 16.0, 4.0),    ## ilvl 5-9
	Vector3(72.0, 22.0, 6.0),    ## ilvl 10-14
	Vector3(64.0, 27.0, 9.0),    ## ilvl 15+
]


static func rarity_weights(ilvl: int) -> Vector3:
	if ilvl <= 4:
		return RARITY_WEIGHTS[0]
	if ilvl <= 9:
		return RARITY_WEIGHTS[1]
	if ilvl <= 14:
		return RARITY_WEIGHTS[2]
	return RARITY_WEIGHTS[3]


## Every base type. Keys are stable ids (stored on a generated item), so a save
## file only ever needs the id plus the rolls.
##
## `shape` is the drawing key shared by the 3D ground model and the inventory
## icon, so both render the same object from one label.
## `str_req` is real: a hero with less Strength cannot equip it (D2 rule).
static func bases() -> Dictionary:
	return {
		# ------------------------------------------------------------ weapons
		"dagger": {"name": "Dýka", "slot": Slot.MAIN_HAND, "size": Vector2i(1, 2),
			"shape": "dagger", "ilvl": 1, "str_req": 0, "damage": Vector2(9, 16)},
		## The hero's STARTING weapon. Its 16-25 IS the number monster_kind.gd
		## mirrors as HERO_HIT_MIN/MAX, so the balance claim in tools/test_fight.gd
		## keeps meaning exactly what it meant before items existed.
		"short_sword": {"name": "Krátký meč", "slot": Slot.MAIN_HAND, "size": Vector2i(1, 3),
			"shape": "sword", "ilvl": 1, "str_req": 0, "damage": Vector2(16, 25),
			"starter": true},
		"long_sword": {"name": "Dlouhý meč", "slot": Slot.MAIN_HAND, "size": Vector2i(1, 3),
			"shape": "sword", "ilvl": 6, "str_req": 28, "damage": Vector2(22, 34)},
		"broad_sword": {"name": "Široký meč", "slot": Slot.MAIN_HAND, "size": Vector2i(2, 3),
			"shape": "sword", "ilvl": 12, "str_req": 45, "damage": Vector2(30, 46)},
		"hand_axe": {"name": "Ruční sekera", "slot": Slot.MAIN_HAND, "size": Vector2i(2, 2),
			"shape": "axe", "ilvl": 8, "str_req": 32, "damage": Vector2(24, 38)},
		"mace": {"name": "Palcát", "slot": Slot.MAIN_HAND, "size": Vector2i(1, 3),
			"shape": "mace", "ilvl": 10, "str_req": 40, "damage": Vector2(28, 42)},
		"war_hammer": {"name": "Válečné kladivo", "slot": Slot.MAIN_HAND, "size": Vector2i(2, 3),
			"shape": "hammer", "ilvl": 16, "str_req": 55, "damage": Vector2(36, 58)},
		## Two-handed: D2's rule, it blocks the off hand while equipped.
		"halberd": {"name": "Halapartna", "slot": Slot.MAIN_HAND, "size": Vector2i(2, 4),
			"shape": "polearm", "ilvl": 20, "str_req": 60, "damage": Vector2(44, 70),
			"two_handed": true},
		# -------------------------------------------------------------- shields
		"buckler": {"name": "Puklíř", "slot": Slot.OFF_HAND, "size": Vector2i(2, 2),
			"shape": "shield", "ilvl": 1, "str_req": 12, "defense": Vector2(8, 14)},
		"kite_shield": {"name": "Štít", "slot": Slot.OFF_HAND, "size": Vector2i(2, 3),
			"shape": "shield", "ilvl": 10, "str_req": 34, "defense": Vector2(18, 28)},
		# ---------------------------------------------------------------- body
		"quilted_armor": {"name": "Prošívaná zbroj", "slot": Slot.CHEST, "size": Vector2i(2, 3),
			"shape": "armor", "ilvl": 1, "str_req": 0, "defense": Vector2(14, 22)},
		"leather_armor": {"name": "Kožená zbroj", "slot": Slot.CHEST, "size": Vector2i(2, 3),
			"shape": "armor", "ilvl": 6, "str_req": 22, "defense": Vector2(22, 34)},
		"ring_mail": {"name": "Kroužková zbroj", "slot": Slot.CHEST, "size": Vector2i(2, 3),
			"shape": "armor", "ilvl": 12, "str_req": 40, "defense": Vector2(34, 50)},
		"plate_mail": {"name": "Plátová zbroj", "slot": Slot.CHEST, "size": Vector2i(2, 3),
			"shape": "armor", "ilvl": 20, "str_req": 60, "defense": Vector2(50, 72)},
		# --------------------------------------------------------------- head
		"cap": {"name": "Čapka", "slot": Slot.HELM, "size": Vector2i(2, 2),
			"shape": "helm", "ilvl": 1, "str_req": 0, "defense": Vector2(8, 14)},
		"helm": {"name": "Přilba", "slot": Slot.HELM, "size": Vector2i(2, 2),
			"shape": "helm", "ilvl": 8, "str_req": 30, "defense": Vector2(16, 26)},
		"great_helm": {"name": "Velká přilba", "slot": Slot.HELM, "size": Vector2i(2, 2),
			"shape": "helm", "ilvl": 16, "str_req": 45, "defense": Vector2(26, 40)},
		# ------------------------------------------------------- hands / feet
		"leather_gloves": {"name": "Kožené rukavice", "slot": Slot.GLOVES, "size": Vector2i(2, 2),
			"shape": "gloves", "ilvl": 1, "str_req": 0, "defense": Vector2(3, 7)},
		"gauntlets": {"name": "Rukavice z plechu", "slot": Slot.GLOVES, "size": Vector2i(2, 2),
			"shape": "gloves", "ilvl": 10, "str_req": 30, "defense": Vector2(10, 16)},
		"boots": {"name": "Kožené boty", "slot": Slot.BOOTS, "size": Vector2i(2, 2),
			"shape": "boots", "ilvl": 1, "str_req": 0, "defense": Vector2(3, 7)},
		"greaves": {"name": "Těžké boty", "slot": Slot.BOOTS, "size": Vector2i(2, 2),
			"shape": "boots", "ilvl": 12, "str_req": 30, "defense": Vector2(12, 18)},
		# --------------------------------------------------------------- waist
		"sash": {"name": "Pás", "slot": Slot.BELT, "size": Vector2i(2, 1),
			"shape": "belt", "ilvl": 1, "str_req": 0, "defense": Vector2(2, 5)},
		"war_belt": {"name": "Válečný pás", "slot": Slot.BELT, "size": Vector2i(2, 1),
			"shape": "belt", "ilvl": 8, "str_req": 25, "defense": Vector2(6, 10)},
		# ------------------------------------------------------------- jewellery
		"ring": {"name": "Prsten", "slot": Slot.RING, "size": Vector2i(1, 1),
			"shape": "ring", "ilvl": 1, "str_req": 0},
		"amulet": {"name": "Amulet", "slot": Slot.AMULET, "size": Vector2i(1, 1),
			"shape": "amulet", "ilvl": 1, "str_req": 0},
	}


static func base(id: String) -> Dictionary:
	var all := bases()
	if not all.has(id):
		push_error("item_base: unknown base '%s'" % id)
		return {}
	return (all[id] as Dictionary).duplicate(true)


## Every base that can drop at or below `ilvl`. Higher item levels push better
## base types onto the ground - that is the whole progression of the loot.
static func droppable(ilvl: int, slot_filter: int = Slot.NONE) -> Array:
	var out: Array = []
	for id in bases():
		var b: Dictionary = bases()[id]
		if int(b.get("ilvl", 1)) > ilvl:
			continue
		if slot_filter != Slot.NONE and int(b["slot"]) != slot_filter:
			continue
		out.append(id)
	return out


static func starter_weapon_id() -> String:
	for id in bases():
		if bool((bases()[id] as Dictionary).get("starter", false)):
			return id
	return "short_sword"
