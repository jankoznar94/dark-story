extends RefCounted
class_name ItemStats
## ItemStats — the small pure helpers every item UI needs: quality colour, socket
## name, weapon damage totals and an icon path.
##
## These were previously duplicated between the inventory screen and would have been
## duplicated again in the chest / shop / gamble / craft screens. They are one-line
## functions, but each one encodes a display rule (unique and crafted override the
## quality colour; sockets append " (n)" to the name) that must read the same in
## every screen.
##
## Ported from the PWA's `getQualityColor`, `getItemSocketName` and
## `src/core/weapon.ts`.

## Quality colours. `unique` and `crafted` are not quality strings but flags, so they
## are checked separately in quality_color().
const QUALITY_COLORS := {
	"normal": "#c8c8c8",
	"magic": "#4a7dff",
	"rare": "#f1c40f",
	"unique": "#b8860b",
	"crafted": "#ff8c00",
}


## getQualityColor — a crafted item is orange and a unique is gold-brown, regardless
## of its own `quality` string.
static func quality_color(item: Dictionary) -> Color:
	if item.get("unique", false):
		return Color("#b8860b")
	if item.get("crafted", false):
		return Color("#ff8c00")
	var q: String = str(item.get("quality", item.get("rarity", "normal")))
	return Color(QUALITY_COLORS.get(q, QUALITY_COLORS["normal"]))


## getItemSocketName — "Short Sword (2)". Used as the item's label everywhere.
static func socket_name(item: Dictionary) -> String:
	var name_text: String = str(item.get("name", "?"))
	var sockets := int(item.get("sockets", 0))
	if sockets <= 0:
		return name_text
	return "%s (%d)" % [name_text, sockets]


## Icon path for an item. Generated items inherit `iconImg` from their base, and the
## unique table carries its own, so this is a plain lookup with a guard.
static func icon_path(item: Dictionary) -> String:
	return str(item.get("iconImg", ""))


## A stat value may be a rolled int (our generator) or a [min, max] range (a raw
## affix definition). Both must render.
static func fmt_dmg(value: Variant) -> String:
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return "%s-%s" % [str(arr[0]), str(arr[1])]
		return str(arr[0]) if arr.size() == 1 else "0"
	return str(int(value))


static func _min_of(value: Variant) -> int:
	if value is Array:
		var arr: Array = value
		return int(arr[0]) if arr.size() > 0 else 0
	return int(value)


static func _max_of(value: Variant) -> int:
	if value is Array:
		var arr: Array = value
		return int(arr[1]) if arr.size() > 1 else 0
	return int(value)


## getWeaponTotalDmgMin — base plus every elemental damage channel. Poison is NOT
## included: it is a damage-over-time and the PWA leaves it out of the swing range.
static func weapon_dmg_min(weapon: Dictionary) -> int:
	return int(weapon.get("baseDmgMin", 0)) + _min_of(weapon.get("fireDmg", 0)) \
		+ _min_of(weapon.get("coldDmg", 0)) + _min_of(weapon.get("lightningDmg", 0))


static func weapon_dmg_max(weapon: Dictionary) -> int:
	return int(weapon.get("baseDmgMax", 0)) + _max_of(weapon.get("fireDmg", 0)) \
		+ _max_of(weapon.get("coldDmg", 0)) + _max_of(weapon.get("lightningDmg", 0))


## getWeaponElementColor — the weapon's damage is tinted by its element, first match
## wins (fire, cold, poison, lightning), exactly as the PWA ordered them.
## Returns null when the weapon is purely physical.
static func weapon_element_color(weapon: Dictionary) -> Variant:
	var checks := [
		["fireDmg", "#e67e22"],
		["coldDmg", "#4a7dff"],
		["poisonDmg", "#2ecc71"],
		["lightningDmg", "#8b5cf6"],
	]
	for check in checks:
		var value: Variant = weapon.get(check[0], 0)
		if _max_of(value) > 0:
			return Color(str(check[1]))
	return null


## Version of a base item, from its id suffix: 1 = normal, 2 = nightmare, 3 = hell.
## A generated loot item carries a `loot_...` id, so the version is read from
## `baseId` — this is the bug the PWA comments on and it matters for crafting.
static func item_version(item: Dictionary) -> int:
	var ref := str(item.get("baseId", item.get("id", "")))
	if ref.ends_with("_hell"):
		return 3
	if ref.ends_with("_nm"):
		return 2
	return 1
