extends RefCounted
class_name ItemDetail
## ItemDetail — an item rendered as plain text, for tooltips and shop lists.
##
## Ported from the PWA's `buildItemStatsHtml`. The HTML becomes lines, and the two
## colour classes it used ("fixed" stats vs "rolled" affix mods) survive as the
## MOD_PREFIX marker, which a Label with BBCode colouring can style differently.
##
## Everything here is presentation: it reads an item dictionary and returns a string.
## No node, no theme, so a test can assert on the text.

const ItemStats := preload("res://scripts/items/item_stats.gd")

## Prepended to a rolled affix line so the caller can colour it differently from the
## item's fixed stats. The PWA showed these in blue.
const MOD_PREFIX := "~"

## affix stat name -> label. Only the ones the PWA had a label for; anything else
## falls back to the raw key so nothing silently disappears.
const STAT_LABELS := {
	"fireDmg": "Fire Dmg",
	"coldDmg": "Cold Dmg",
	"lightningDmg": "Lightning Dmg",
	"poisonDmg": "Poison Dmg",
	"lifesteal": "Life Steal",
	"manaSteal": "Mana Steal",
	"attackRating": "Attack Rating",
	"skillDmg": "Skill Dmg",
	"critChance": "Crit Chance",
	"castSpeed": "Cast Speed",
	"manaRegen": "Mana Regen",
	"bonusMana": "+Mana",
	"bonusHp": "+HP",
	"ias": "Increased Attack Speed",
	"enhancedDefense": "Enhanced Defense",
	"enhancedDmg": "Enhanced Damage",
	"str": "Strength",
	"vit": "Vitality",
	"int": "Intellect",
	"dex": "Dexterity",
	"magicFind": "Magic Find",
	"goldFind": "Gold Find",
	"fireRes": "Fire Resist",
	"coldRes": "Cold Resist",
	"lightningRes": "Lightning Resist",
	"poisonRes": "Poison Resist",
	"allRes": "All Resists",
	"allSkills": "All Skills",
	"thorns": "Thorns",
	"dmgReduction": "Damage Reduction",
	"lifeRegen": "Life Regen",
	"knockback": "Knockback",
	"preventHeal": "Prevent Monster Heal",
}


## The full detail text: name (with socket count), the type-specific block, then
## every rolled affix with its rolled range.
##
## `show_name` is false for the shop rows, which draw the name themselves in the
## item's quality colour.
static func build_text(item: Dictionary, data: Node, show_name: bool = true) -> String:
	if item.is_empty():
		return ""
	var lines: Array[String] = []

	if show_name:
		var sockets := int(item.get("sockets", 0))
		var suffix := "" if sockets <= 0 else "  Sockets: %d" % sockets
		lines.append(ItemStats.socket_name(item) + suffix)
		if int(item.get("lvlReq", 0)) > 0:
			lines.append("Required Level: %d" % int(item["lvlReq"]))

	var ranges := _affix_ranges(item)

	# --- type-specific block -------------------------------------------------
	var item_type := str(item.get("type", ""))
	if item_type == "weapon":
		var hand := "2H" if item.get("twoHand", false) else "1H"
		var dmg_min := ItemStats.weapon_dmg_min(item)
		var dmg_max := ItemStats.weapon_dmg_max(item)
		var swing_ms := int(item.get("swingMs", 2200))
		var swing_sec := float(swing_ms) / 1000.0
		var dps := 0.0
		if swing_sec > 0.0:
			dps = round(((float(dmg_min) + float(dmg_max)) / 2.0) / swing_sec * 10.0) / 10.0
		lines.append("Damage: %d-%d (%s)  [%s DPS]" % [dmg_min, dmg_max, hand, str(dps)])
		lines.append("Speed: %.2fs per attack (%.2f/s)" % [swing_sec, 1.0 / swing_sec])
		if int(item.get("critChance", 0)) > 0:
			lines.append("Crit: %d%% (x2.0)" % int(item["critChance"]))
	elif item_type == "shield":
		if int(item.get("blockChance", 0)) > 0:
			lines.append("Block: %d%%" % int(item["blockChance"]))
		if int(item.get("baseDmgMin", 0)) > 0 or int(item.get("baseDmgMax", 0)) > 0:
			lines.append("Shield Slam: %d-%d dmg" % [int(item.get("baseDmgMin", 0)), int(item.get("baseDmgMax", 0))])
		if int(item.get("defense", 0)) > 0:
			lines.append("Defense: %d" % int(item["defense"]))
	elif item_type == "belt":
		var rows := int(item.get("beltRows", 0))
		lines.append("Potion Slots: %d rows (%d slots)" % [rows, rows * 4] if rows > 0 else "Potion Slots: 0")
	elif item_type == "consumable":
		var verb := "Heals" if str(item.get("subtype", "")) == "heal" else "Restores"
		var unit := "HP" if str(item.get("subtype", "")) == "heal" else "Mana"
		lines.append("%s: %d %s" % [verb, int(item.get("effectValue", 0)), unit])
	elif item_type == "gem":
		for line in _gem_lines(item, data):
			lines.append(line)
	else:
		if int(item.get("defense", 0)) > 0:
			lines.append("Defense: %d" % int(item["defense"]))

	# --- rolled mods ---------------------------------------------------------
	for stat in _mod_stat_order():
		# A stat the TYPE BLOCK already printed must not be printed twice. `critChance`
		# lands on the item's own base stat, so a weapon with a crit affix prints it under
		# Damage AND as a mod row — which is what the PWA does (`buildItemStatsHtml` gates
		# the blue row on `item.critChance` as well). The port shows it once: grey on a
		# weapon, where the type block reads it, and blue everywhere else.
		if stat == "critChance" and str(item.get("type", "")) == "weapon":
			continue
		# `poisonDur` is carried by the poison line ("Poison Dmg +10-10 (3s)") and has no
		# row of its own.
		if stat == "poisonDur":
			continue
		var value: Variant = item.get(stat, 0)
		if not _has_value(value):
			continue
		lines.append(MOD_PREFIX + _mod_line(stat, item, ranges))

	if int(item.get("sockets", 0)) > 0:
		lines.append("Sockets: %d" % int(item["sockets"]))

	return "\n".join(lines)


## The order the PWA printed rolled mods in. Kept because reading the same item in
## two screens must not reorder its stats.
##
## ⚠️  A stat that is NOT in this list is INVISIBLE on every item that carries it —
## `build_text` walks this array and nothing else, so the affix is rolled, stored,
## equipped and silently never printed. Measured in the data: `critChance` (`crit_sharp`,
## `ofCritical`), `castSpeed` (`ofCasting`) and `poisonDur` were all missing. The first two
## are the WHOLE payload of their affixes, so those three items showed a name and no stats
## at all — Jan's "I looted an amulet with no stats, just a name". `poisonDur` is never
## printed on its own (the `poisonDmg` line carries it) but it is listed so the array is
## the honest answer to "which keys render".
##
## Adding a stat to the game means adding it here too: `tools/test_items.gd` asserts that
## every stat key present in the affix table appears in this list.
static func _mod_stat_order() -> Array:
	return [
		"fireDmg", "coldDmg", "poisonDmg", "poisonDur", "lightningDmg", "lifesteal", "manaSteal",
		"attackRating", "skillDmg", "critChance", "castSpeed", "manaRegen", "bonusMana",
		"bonusHp", "ias",
		"enhancedDefense", "enhancedDmg", "str", "vit", "int", "dex",
		"magicFind", "goldFind", "fireRes", "coldRes", "lightningRes", "poisonRes",
		"allRes", "allSkills", "classSkills", "thorns", "dmgReduction", "lifeRegen",
		"knockback", "preventHeal",
	]


static func _mod_line(stat: String, item: Dictionary, ranges: Dictionary) -> String:
	var value: Variant = item.get(stat, 0)
	var range_text := ""
	if ranges.has(stat):
		var r: Array = ranges[stat]
		range_text = "  [%d - %d]" % [int(r[0]), int(r[1])]
	match stat:
		"classSkills":
			var cls := str(item.get("_classSkillsClass", "unknown"))
			return "%s Skills +%d%s" % [cls.capitalize(), int(value), range_text]
		"poisonDmg":
			return "Poison Dmg +%s (%ss)%s" % [ItemStats.fmt_dmg(value), str(item.get("poisonDur", 2)), range_text]
		"allRes", "fireRes", "coldRes", "lightningRes", "poisonRes", "enhancedDmg", "enhancedDefense", "lifesteal", "manaSteal", "skillDmg", "ias", "magicFind", "goldFind", "allSkills", "critChance", "castSpeed":
			return "%s +%s%%%s" % [_label(stat), str(int(value)), range_text]
		"manaRegen":
			return "Mana Regen +%d/tick%s" % [int(value), range_text]
		"lifeRegen":
			return "Life Regen +%d/s%s" % [int(value), range_text]
		"knockback", "preventHeal":
			return _label(stat)
		_:
			return "%s +%s%s" % [_label(stat), ItemStats.fmt_dmg(value), range_text]


static func _label(stat: String) -> String:
	return str(STAT_LABELS.get(stat, stat))


static func _has_value(value: Variant) -> bool:
	if value is Array:
		return _max_of_array(value) > 0
	return int(value) != 0


static func _max_of_array(value: Array) -> int:
	return int(value[1]) if value.size() > 1 else (int(value[0]) if value.size() == 1 else 0)


## stat name -> [min, max], summed over every affix that carries it, so a tooltip can
## show the roll's range next to the value.
static func _affix_ranges(item: Dictionary) -> Dictionary:
	var out := {}
	var affixes: Array = item.get("affixes", [])
	for a in affixes:
		if not (a is Dictionary):
			continue
		var stats: Dictionary = a.get("stats", {})
		for stat in stats:
			var r: Variant = stats[stat]
			var lo := int(r[0]) if r is Array and r.size() > 0 else int(r)
			var hi := int(r[1]) if r is Array and r.size() > 1 else lo
			if out.has(stat):
				var prev: Array = out[stat]
				out[stat] = [int(prev[0]) + lo, int(prev[1]) + hi]
			else:
				out[stat] = [lo, hi]
	return out


## What a gem does in each of the three socket families. Ported from the PWA's gem
## branch of buildItemStatsHtml, which reads the GEMS table for the description.
static func _gem_lines(item: Dictionary, data: Node) -> Array[String]:
	var lines: Array[String] = []
	var gems: Dictionary = data.gems()
	var gem: Dictionary = gems.get(str(item.get("gemType", "")), {})
	if gem.is_empty():
		return lines
	var quality: Dictionary = gem.get("qualities", {}).get(str(item.get("gemQuality", "")), {})
	if quality.is_empty():
		return lines
	var families := [
		{"key": "weapon", "label": "Weapon"},
		{"key": "armor", "label": "Armor/Helm"},
		{"key": "shield", "label": "Shield"},
	]
	for family in families:
		var entries: Dictionary = quality.get(str(family["key"]), {})
		if entries.is_empty():
			continue
		lines.append("%s:" % str(family["label"]))
		for key in entries:
			var value: Variant = entries[key]
			var label := str(STAT_LABELS.get(key, key))
			if key == "poisonDur":
				label = "Duration"
			var text: String = ItemStats.fmt_dmg(value)
			if str(key).ends_with("Res") or key == "allRes":
				text = "+%s%%" % text
			elif key == "bonusHp":
				text = "+%s" % text
			elif key == "attackRating":
				text = "+%s" % text
			lines.append("  %s: %s" % [label, text])
	return lines
