extends Node
## GameData — the ONE place every table from the old src/data/*.ts is read from.
##
## The port's whole premise: porting numbers is cheap, porting a DOM renderer is
## not. So the JSON under res://data/ is the single source of truth and nothing
## in this project is allowed to hardcode a monster, an item or an affix again.
##
## Usage:
##   var item := GameData.item("blade_shortSword")
##   var pool: Array = GameData.monsters_for_theme(0)
##
## Everything is loaded once in _ready() and handed out by reference — callers
## must not mutate the returned dictionaries. If a system needs a per-instance
## copy, duplicate() it.

const DATA_DIR := "res://data/"

## name -> parsed contents of data/<name>.json
var _tables: Dictionary = {}

## Lookup indexes built on top of the raw tables, so callers do not each write
## their own linear search (the JS version had four of them, all subtly different).
var _items_by_id: Dictionary = {}
var _monsters_by_name: Dictionary = {}

## Set once the tables are in memory.
##
## Loading is LAZY rather than done in _ready() on purpose: a `--script` tool
## (SceneTree) never gets _ready() called for a node it instantiates, so a
## _ready()-only load made every tool see an empty GameData and report the whole
## port as broken. Every public accessor funnels through _ensure_loaded() instead,
## which is correct in a scene, in a tool, and as an autoload alike.
var _loaded := false


func _ready() -> void:
	_ensure_loaded()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true   # set before loading so a re-entrant call cannot loop
	_load_tables()


func _load_tables() -> void:
	for file_name in _list_json_files():
		var table_name := file_name.get_basename()
		var parsed: Variant = _read_json(DATA_DIR + file_name)
		if parsed == null:
			push_error("GameData: %s is not valid JSON — rerun tools/import/convert.mjs" % file_name)
			continue
		_tables[table_name] = parsed
	_build_indexes()


func _list_json_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("GameData: cannot open %s — did the JSON get copied in?" % DATA_DIR)
		return out
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			out.append(file_name)
	return out


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _build_indexes() -> void:
	for item in table("ITEMS", []):
		if item is Dictionary and item.has("id"):
			_items_by_id[item["id"]] = item
	_build_gem_items()


## Gems are NOT in ITEMS: the PWA builds them at runtime in initGemItems() from the
## GEMS table (4 types x 5 qualities), and the loot system then refers to them by id
## ("ruby", "ruby_perfect", ...). The same construction happens here so a gem id
## resolves wherever an item id is expected. Without this, gem drops resolved to
## nothing and the 5% gem branch of rollLoot silently produced no item.
func _build_gem_items() -> void:
	var qualities: Array = table("GEM_QUALITIES", [])
	var costs := {"chipped": 10, "flawed": 15, "normal": 20, "flawless": 50, "perfect": 100}
	var tiers := {"chipped": 1, "flawed": 2, "normal": 3, "flawless": 4, "perfect": 5}
	for gem_type in table("GEMS", {}):
		var gem: Dictionary = table("GEMS", {})[gem_type]
		var idx := 0
		for q in qualities:
			var q_data: Dictionary = gem.get("qualities", {}).get(q, {})
			if q_data.is_empty():
				idx += 1
				continue
			var id: String = gem_type if q == "normal" else "%s_%s" % [gem_type, q]
			_items_by_id[id] = {
				"id": id,
				"name": q_data.get("name", id),
				"type": "gem",
				"gemType": gem_type,
				"gemQuality": q,
				# The asset names use the QUALITY NAME, not the 0-based index this used to
				# emit: the files are `emerald_chipped.png` / `emerald.png` and the code asked
				# for `emerald0.png` / `emerald2.png`, so `_load` returned null for all 20
				# gems and every gem drew as an empty 32px slot — on the victory page, in the
				# bag, in the shop and in socketing. `normal` is the bare `<type>.png`, which
				# is the same "no suffix" rule the id above already uses.
				"iconImg": "assets/gems/%s%s.png" % [gem_type,
					"" if q == "normal" else "_" + str(q)],
				"cost": costs.get(q, 20),
				"tier": tiers.get(q, 1),
				"quality": "magic",
			}
			idx += 1
	for theme_bucket in table("MONSTER_DB", []):
		for monster in theme_bucket:
			if monster is Dictionary and monster.has("name"):
				_monsters_by_name[monster["name"]] = monster


# --- generic access ----------------------------------------------------------

## Raw table by name ("ITEMS", "AFFIXES", "CLASSES", ...). `default` is returned
## when the table is missing so a half-finished port does not crash on boot.
func table(table_name: String, default: Variant = null) -> Variant:
	_ensure_loaded()
	if _tables.has(table_name):
		return _tables[table_name]
	push_warning("GameData: no table named %s" % table_name)
	return default


func has_table(table_name: String) -> bool:
	_ensure_loaded()
	return _tables.has(table_name)


# --- typed accessors for the tables the port actually consumes ---------------

func items() -> Array:
	return table("ITEMS", [])


## A single item by id. Goes through _ensure_loaded() like every other accessor: this
## was the one lookup that did NOT, so the FIRST call in a process returned {} (the
## index was still empty) and only later calls worked. A caller that resolved one item
## before touching any table saw "no such item".
func item(id: String) -> Dictionary:
	_ensure_loaded()
	return _items_by_id.get(id, {})


## EVERY item the game can hand out, keyed by id — the static ITEMS table PLUS the gems
## `_build_gem_items()` synthesises from GEMS.json.
##
## `items()` above returns the RAW table and therefore does NOT contain a single gem: the
## 20 gem entries live only in `_items_by_id`. A test that walked `items()` to check icon
## paths was blind to exactly the entries that were broken (all 20 gems pointed at files
## that do not exist, and the check still reported "0 missing").
func item_ids() -> Array:
	_ensure_loaded()
	var ids: Array = _items_by_id.keys()
	ids.sort()
	return ids


## All items by id, as an Array of dictionaries. The counterpart to `item_ids()`.
func all_items() -> Array:
	_ensure_loaded()
	var out: Array = []
	for id in item_ids():
		out.append(_items_by_id[id])
	return out


func unique_items() -> Array:
	return table("UNIQUE_ITEMS", [])


func affixes() -> Array:
	return table("AFFIXES", [])


func classes() -> Dictionary:
	return table("CLASSES", {})


func class_by_id(id: String) -> Dictionary:
	return classes().get(id, {})


func class_skills() -> Dictionary:
	return table("CLASS_SKILLS", {})


func monsters_for_theme(theme: int) -> Array:
	var db: Array = table("MONSTER_DB", [])
	if theme < 0 or theme >= db.size():
		return []
	return db[theme]


func monster_by_name(name: String) -> Dictionary:
	_ensure_loaded()
	return _monsters_by_name.get(name, {})


func monster_count() -> int:
	var total := 0
	for theme_bucket in table("MONSTER_DB", []):
		total += theme_bucket.size()
	return total


func enemy_spells() -> Dictionary:
	return table("ENEMY_SPELLS", {})


func acts() -> Array:
	return table("ACTS", [])


func act_by_id(id: int) -> Dictionary:
	for act in acts():
		if act.get("id", -1) == id:
			return act
	return {}


func difficulties() -> Array:
	return table("DIFFICULTIES", [])


func gems() -> Dictionary:
	return table("GEMS", {})


func gem_qualities() -> Array:
	return table("GEM_QUALITIES", [])


func hero_faces() -> Array:
	return table("HERO_FACES", [])


## Small self-check used by tools/test_data.gd and the CI run. Returns a
## dictionary of "what loaded" so a broken converter fails loudly instead of
## silently shipping an empty game.
func integrity_report() -> Dictionary:
	_ensure_loaded()
	return {
		"tables": _tables.size(),
		"items": items().size(),
		"unique_items": unique_items().size(),
		"affixes": affixes().size(),
		"classes": classes().size(),
		"monsters": monster_count(),
		"acts": acts().size(),
		"enemy_spells": enemy_spells().size(),
		"gems": gems().size(),
	}
