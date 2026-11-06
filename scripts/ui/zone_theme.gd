extends RefCounted
class_name ZoneTheme
## ZoneTheme — what a ZONE of an act looks like: its ground, its palette and its props.
##
## Jan, Nov 2026: "Musíme ještě trochu oživit generování oblastí. Teď vypadají všechny stejně.
## Stejná textura na zemi, stejné objekty, nic unikátního… pro každou oblast v aktu 1 vzít obrázek
## oblasti a podle toho obrázku nějak ikonicky upravit tu reálnou živou oblast."
##
## So every zone of ACT 1 is painted from its own stop painting (`assets/stops/stop_act0_<n>.webp`).
## The mapping is one entry per zone, in the map's own order, and each entry names the ONE thing
## that painting is about — the stone circle, the ruined tower, the bridge, the tree village —
## and carries it into the playable area as a LANDMARK plus the materials around it.
##
## Three things stay true of every entry, because they are Jan's rules and not a style choice:
##   * flat, desaturated colours — no glow, no gradients, no bloom. An "accent" colour is a FLAT
##     colour that happens to be cooler or warmer than the ground (a glyph, a torch flame, water),
##     never an additive halo;
##   * the props are ICONS, not scenery: a menhir is four straight edges, a pine is three
##     triangles. At the 0.82 zoom the phone runs at, anything finer is four grey pixels;
##   * the wall a zone is edged with is the zone's own material (pines, menhirs, masonry), so even
##     a player who never turns his head can tell two zones apart.
##
## Only THREE ground tiles are new (`needles`, `gravel`, `mud`) on top of the existing grass and
## dirt: the ten zones differ by TINT as well, and every extra 512 px tile is ~150 KB of the web
## build's first load.

## The palette keys every entry may override. `_expand()` turns every hex string into a Color,
## because a `const` dictionary cannot hold a `Color("…")` constructor call.
const COLOR_KEYS := [
	"tint", "rock", "rock_line", "patch_a", "patch_b",
	"stone", "stone_light", "wood", "wood_light",
	"foliage", "foliage_light", "accent",
	"water", "water_line",
]

## Act 1 — Enchanted Forest, one entry per stop, in the map's order.
##
## `wall`   kinds that edge the corridor (cycled along it — a run of the SAME kind is a hedge,
##          and the cycle is what stops it reading as a pattern);
## `cover`  interior props as [kind, weight] — sparse cover to run past, never a maze;
## `marks`  the zone's LANDMARK kinds, placed in the rock beyond the path at fixed depths;
## `feature` what the GROUND does beyond its texture: "" = dry ground, "boardwalk" = impassable
##          swamp crossed by a plank walkway, "river" = a river with a bridge, "chasm" = a gap
##          with a stone span. `shore` is the prop list that grows along a water edge.
const ACT1 := [
	{   # 0 — the stone circle in a misty glade
		"name": "Kamenný kruh",
		"ground": "grass",
		"tint": "#b9c9a8",
		"rock": "#1d2018", "rock_line": "#2a2e20",
		"patch_a": "#43523a", "patch_b": "#4c5a40",
		"stone": "#6b6a5c", "stone_light": "#8a8975",
		"wood": "#4a3a28", "wood_light": "#5f4b34",
		"foliage": "#2f3a26", "foliage_light": "#3c4930",
		"accent": "#5f8f7a",
		"wall": ["bush", "menhir", "bush"],
		"cover": [["menhir", 3], ["fern", 3], ["rock", 2]],
		"marks": ["lm_circle"],
	},
	{   # 1 — the thick dark conifer wood
		"name": "Hustý hvozd",
		"ground": "needles",
		"tint": "#c4c2a6",
		"rock": "#1a1a12", "rock_line": "#262619",
		"patch_a": "#3a3226", "patch_b": "#443a2b",
		"stone": "#5e5a4c", "stone_light": "#7a7565",
		"wood": "#3c2e20", "wood_light": "#4e3c29",
		"foliage": "#2b3421", "foliage_light": "#39442c",
		"accent": "#6b7a4e",
		"wall": ["pine", "pine", "bush"],
		"cover": [["pine", 3], ["stump", 2], ["bush", 3], ["fern", 2]],
		"marks": ["lm_grove"],
	},
	{   # 2 — the ruined tower under a full moon
		"name": "Věž pod měsícem",
		"ground": "gravel",
		"tint": "#a9b8d2",
		"rock": "#191b1f", "rock_line": "#252830",
		"patch_a": "#4a4d52", "patch_b": "#565a60",
		"stone": "#767a80", "stone_light": "#93979d",
		"wood": "#3e3a33", "wood_light": "#4f4a41",
		"foliage": "#2c352c", "foliage_light": "#394435",
		"accent": "#8fb3c8",
		"wall": ["rubble", "rubble", "column"],
		"cover": [["column", 3], ["rubble", 4], ["dead_tree", 2]],
		"marks": ["lm_tower"],
	},
	{   # 3 — the bog with a broken boardwalk
		"name": "Bažina",
		"ground": "mud",
		"tint": "#d6dcc6",
		"rock": "#161a16", "rock_line": "#20261f",
		"patch_a": "#2a3430", "patch_b": "#33403a",
		"stone": "#585c52", "stone_light": "#6f7367",
		"wood": "#4a3b28", "wood_light": "#6a563a",
		"foliage": "#2c3a2c", "foliage_light": "#3a4a37",
		"accent": "#4e7a63",
		"water": "#2b3a34", "water_line": "#44584e",
		"wall": ["dead_tree", "reed", "dead_tree"],
		"cover": [["reed", 5], ["plank", 3], ["mushroom", 2]],
		"marks": ["lm_fallen_log"],
		# Jan, Nov 2026: "Močály nebudou mít jen jinou texturu na zemi… do močálů se vstoupit
		# nedá a chodit se dá jen po lávkách. Ty mohou směřovat různě."
		"feature": "boardwalk",
		"shore": [["reed", 6], ["dead_tree", 2], ["stump", 2]],
	},
	{   # 4 — the mountain valley road
		"name": "Horské údolí",
		"ground": "dirt",
		"tint": "#d2c8b6",
		"rock": "#201c17", "rock_line": "#2e2820",
		"patch_a": "#5a5245", "patch_b": "#6a6152",
		"stone": "#79705f", "stone_light": "#968c78",
		"wood": "#463522", "wood_light": "#5c4730",
		"foliage": "#303a26", "foliage_light": "#3e4a31",
		"accent": "#8a8064",
		"water": "#33454c", "water_line": "#4e6a72",
		"wall": ["rock", "rock", "rock"],
		"cover": [["rock", 4], ["cairn", 3]],
		"marks": ["lm_cairn_field"],
		# "Valley úplně vybízí k tomu, že by měla být lokace rozdělena řekou, přes kterou vede
		# velký most."
		"feature": "river",
		"shore": [["reed", 5], ["rock", 3]],
	},
	{   # 5 — the canyon and its stone bridge
		"name": "Kaňon",
		"ground": "gravel",
		"tint": "#c2c0bb",
		"rock": "#17181a", "rock_line": "#22252a",
		"patch_a": "#454a4d", "patch_b": "#515759",
		"stone": "#6d7375", "stone_light": "#8a9092",
		"wood": "#3b332a", "wood_light": "#4c4237",
		"foliage": "#2a352e", "foliage_light": "#374439",
		"accent": "#77939c",
		"water": "#1f252a", "water_line": "#39434a",
		"wall": ["rock", "rubble", "rock"],
		"cover": [["rubble", 4], ["cairn", 3]],
		"marks": ["lm_bridge"],
		"feature": "chasm",
		"shore": [["rubble", 4], ["rock", 3], ["cairn", 2]],
	},
	{   # 6 — the village in the trees
		"name": "Stromová vesnice",
		"ground": "dirt",
		"tint": "#d8c49c",
		"rock": "#1b1610", "rock_line": "#292117",
		"patch_a": "#5e5040", "patch_b": "#6d5c47",
		"stone": "#6a6152", "stone_light": "#857a66",
		"wood": "#4d3a26", "wood_light": "#634c33",
		"foliage": "#33402a", "foliage_light": "#465538",
		"accent": "#b8763a",
		"wall": ["pine", "fence", "pine"],
		"cover": [["hut", 2], ["barrel", 3], ["torch", 2], ["fence", 3]],
		"marks": ["lm_village"],
	},
	{   # 7 — the glowing spring in the clearing
		"name": "Světélkující pramen",
		"ground": "grass",
		"tint": "#9fbfae",
		"rock": "#161d1a", "rock_line": "#232c26",
		"patch_a": "#3d5246", "patch_b": "#48604f",
		"stone": "#6a7268", "stone_light": "#868e80",
		"wood": "#42362a", "wood_light": "#534435",
		"foliage": "#2e3f34", "foliage_light": "#3b4e40",
		"accent": "#6fb3a0",
		"wall": ["fern", "bush", "fern"],
		"cover": [["fern", 5], ["mushroom", 3], ["rock", 1]],
		"marks": ["lm_fountain"],
	},
	{   # 8 — the river valley under the distant fortress
		"name": "Řeka a pevnost",
		"ground": "gravel",
		"tint": "#a2b39c",
		"rock": "#171a18", "rock_line": "#232724",
		"patch_a": "#3f4a44", "patch_b": "#4b574f",
		"stone": "#6e726b", "stone_light": "#8b8f86",
		"wood": "#3d332a", "wood_light": "#52463a",
		"foliage": "#2b3830", "foliage_light": "#39493e",
		"accent": "#5d7f86",
		"water": "#2e4148", "water_line": "#48636b",
		"wall": ["wall_block", "wall_block", "reed"],
		"cover": [["reed", 4], ["rubble", 3], ["fence", 2]],
		"marks": ["lm_watchtower"],
		"feature": "river",
		"shore": [["reed", 4], ["rubble", 3]],
	},
	{   # 9 — the ruined gate overgrown with roots
		"name": "Zřícená brána",
		"ground": "dirt",
		"tint": "#c6b9a0",
		"rock": "#1c1811", "rock_line": "#2a2418",
		"patch_a": "#544a3a", "patch_b": "#615543",
		"stone": "#736a58", "stone_light": "#8f8570",
		"wood": "#463424", "wood_light": "#5a4530",
		"foliage": "#2f3a26", "foliage_light": "#3d4a31",
		"accent": "#6d7f56",
		"wall": ["wall_block", "root", "wall_block"],
		"cover": [["rubble", 4], ["root", 3], ["dead_tree", 2]],
		"marks": ["lm_gate"],
	},
]

## Everything that is not act 1 (acts 2-4) keeps the ONE look the port shipped with: warm dark
## ground, boulders and bushes. A zone without its own painting must not invent a theme, and an
## act that has not been themed yet must not look broken.
const DEFAULT := {
	"name": "",
	"ground": "grass",
	"tint": "#ffffff",
	"rock": "#191510", "rock_line": "#241d15",
	"patch_a": "#5a503e", "patch_b": "#645945",
	"stone": "#6a614f", "stone_light": "#857a63",
	"wood": "#4a3a28", "wood_light": "#5f4b34",
	"foliage": "#373c26", "foliage_light": "#454b2f",
	"accent": "#7d6e56",
	"water": "#2b3a37", "water_line": "#435a54",
	"wall": ["rock", "rock", "bush"],
	"cover": [["rock", 3], ["bush", 3]],
	"marks": [],
	"feature": "",
	"shore": [["rock", 2], ["reed", 2]],
}


## The theme for one zone. `zone` is the zone INDEX within the act, i.e. the same number the map
## sends the player to and the same one the stop paintings are numbered by.
static func for_zone(act_id: int, zone: int) -> Dictionary:
	var src: Dictionary = DEFAULT
	if act_id == 0 and zone >= 0 and zone < ACT1.size():
		src = ACT1[zone]
	return expand(src)


## Hex strings -> Colors, plus the resolved texture path. Public so a test can expand a raw
## entry and check it without building a screen.
static func expand(src: Dictionary) -> Dictionary:
	var out: Dictionary = src.duplicate(true)
	for key in COLOR_KEYS:
		out[key] = Color(str(src.get(key, DEFAULT[key])))
	out["ground_path"] = "res://assets/ground/%s.png" % str(src.get("ground", "grass"))
	return out


## One kind out of a [kind, weight] list, seeded by the caller's RNG. Weights are relative, so a
## zone can say "mostly reeds, a few planks" without listing the kind four times.
static func pick_cover(theme: Dictionary, rng: RandomNumberGenerator) -> String:
	return pick_weighted(theme.get("cover", []), rng, "rock")


## The props that grow where the ground meets WATER: reeds in a bog, boulders on a river bank.
## Same weighted pick, different list, so a shore never borrows the zone's dry-land cover.
static func pick_shore(theme: Dictionary, rng: RandomNumberGenerator) -> String:
	return pick_weighted(theme.get("shore", []), rng, "reed")


static func pick_weighted(list: Array, rng: RandomNumberGenerator, fallback: String) -> String:
	var total := 0.0
	for entry in list:
		total += float(entry[1])
	if total <= 0.0:
		return fallback
	var roll := rng.randf() * total
	for entry in list:
		roll -= float(entry[1])
		if roll <= 0.0:
			return str(entry[0])
	return str(list[list.size() - 1][0])


## The material a zone's WALL is made of at position `index` along the corridor. Cycled rather
## than random: a run of one kind is a hedge, and a random pick produces exactly the "all the
## same" wall this is meant to fix.
static func wall_kind(theme: Dictionary, index: int) -> String:
	var wall: Array = theme.get("wall", ["rock"])
	return str(wall[index % wall.size()])


## How big a piece of a given kind is, in the same units `_draw_props` uses (a rock's `size` is
## its width). Landmarks are deliberately far larger than cover: they are the thing a player
## recognises the zone by, seen from across the map.
static func base_size(kind: String, rng: RandomNumberGenerator, wall: bool) -> float:
	match kind:
		"pine", "dead_tree":
			return rng.randf_range(54, 78) if wall else rng.randf_range(38, 54)
		"menhir":
			return rng.randf_range(46, 62) if wall else rng.randf_range(30, 42)
		"wall_block":
			return rng.randf_range(50, 64) if wall else rng.randf_range(34, 44)
		"reed":
			return rng.randf_range(26, 40)
		"root":
			return rng.randf_range(40, 58)
	if wall:
		return rng.randf_range(42, 66)
	return rng.randf_range(22, 44)
