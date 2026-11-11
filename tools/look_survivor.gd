extends SceneTree
class_name LookSurvivor
## LookSurvivor — boot the game, enter the SURVIVOR RUN, play a couple of seconds and write a PNG.
##
## Why this exists: the survivor screen is drawn entirely in `_draw()`, so a headless run proves
## the rules and NOTHING about what the player sees. This is the only way to answer "how does it
## actually look on the phone" without asking Jan to look at a mockup.
##
##   godot4 --path . --rendering-driver opengl3 --resolution 390x844 \
##       --script res://tools/look_survivor.gd -- --out /tmp/survivor.png [--frames 300] [--walk 1]
##
## The hero is driven through the screen's OWN gesture path (`_on_press` + `_on_drag`), so the
## floating stick that a real thumb produces is in the frame — a hand-set `_stick_vec` would
## photograph a control state that cannot happen.

var _main: Node = null
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
var _out := "/tmp/survivor.png"
var _frames_to_run := 300
var _walk := true
## How long the thumb holds the stick. The rest of the frames are STOOD STILL, so the monsters
## close in and the auto-attack actually fires — a shot taken while running away from everything
## shows an empty arena and no fight.
var _walk_frames := 130
## Keep the thumb DOWN at capture time, so the floating stick is in the frame. The control is
## half of what this slice is; a shot without it photographs a game with no controls.
var _stick := "1"
## Wait for a blow to be LANDING before the shot. A screenshot of a swing that is not happening
## photographs the game as if it had no attack animation at all.
var _wait_swing := true
## Hold the frame until a body is COMMITTED to a blow, so the telegraph ring is in the shot.
## A look-frame of a fight has to show the thing being judged: an idle pack photographs the
## absence of the feature as convincingly as its presence.
var _wait_telegraph := false
## Place N bodies in the hero's reach before the shot. A look-frame needs a fight IN it; waiting
## for the spawner to walk one over costs the timeout and photographs an empty field.
var _pack := 5
## Where to stand for the shot: "" = the start clearing, "zone" = inside the next cell (whose
## pack wakes and walks in), "wall" = against the boundary props. A capture of the AREA has to
## show the thing being judged — the wall line and the discovery beat — not the middle of a field.
var _spot := ""
## Grant talent points to a handful of the barbarian's spells so the spell column is POPULATED in
## the frame. Nothing is saved — this is a look-probe, and a screenshot of a class that invested
## in nothing would photograph an empty column and prove nothing.
var _spells := false
## Open a Whirlwind flurry a few frames before the shot, so the PS row (and its countdown ring) is
## in the frame. The row is the one part of the spell work that cannot be judged from a still of
## anything else.
var _flurry := false
## Cast ONE spell a few frames before the shot, so its effect is mid-animation in the frame.
## The effects are the whole point of `--cast`: a still of a finished spell proves nothing.
var _cast_id := ""
## Put a TOWN PORTAL in the frame: a scroll in the belt (so the HUD's `Portal` button exists and
## is drawn) and the portal's mouth on the floor beside the hero. Nothing else about the frame
## changes, so it is the same picture with and without the portal.
var _portal := false
## How many frames before the shot the spell is cast. A shout's wave needs ~20 frames to leave the
## portrait (at 8 it is still INSIDE the hero's own disc and reads as a rim); a bolt crosses 105 px
## of body in ~10, so it is caught with 5.
var _cast_at := 20
## Which ZONE of act 1 to photograph. Each zone has its own ground, palette and props
## (`scripts/ui/zone_theme.gd`), so a look pass has to be able to walk to any of them.
var _zone := 0
## Stage N ITEM drops beside the hero, so the frame judges what an item on the ground LOOKS
## like. Without it the only way to photograph the drop marker is to wait for a kill, which
## makes the capture depend on the fight (and on a save that may already own every item).
var _drop := 0
## Open the ZONE MAP overlay for the shot, so the explored sheet and the hero's dot can be judged
## from a frame instead of from a description.
var _map := false
## Close the map again through the REAL press path before the shot, so the frame shows the HUD AFTER
## a map round trip. That is the state where the button used to be a screen-sized plate in the middle
## of the screen (Jan, Nov 2026) — a frame of the open map could never show it.
var _map_close := false
## Reveal the fog along the whole ROUTE before the shot, so a map frame shows what a player who
## walked the zone would see. The reveal goes through `run._reveal_around()` — the same call the
## step loop makes — so the bytes are the ones a walk produces, only without the fifteen minutes.
var _explore := false

var _screen = null
var _started := false
var _frames := 0
## How many extra frames the swing wait has spent looking for a blow. A run that ENDS (the hero
## dies to the pack the frame was staged around) freezes `swing_age`, so an unbounded wait here
## hangs the tool instead of producing a frame — measured on a 320-frame shot that never wrote a
## PNG. Give up after a stretch and capture what there is.
var _stall := 0


## Stand where the frame's question is. The fake pack below is a RENDERING probe (a fight in the
## frame); the area itself is judged from real state — the wall line, and a pack that arrived by
## walking in from off screen.
func _place_hero() -> void:
	if _spot == "" or _screen.run == null:
		return
	var run = _screen.run
	match _spot:
		"wall":
			run.player_pos = Vector2(SurvivorRun.WORLD.x * 0.5,
				SurvivorRun.WORLD.y - SurvivorRun.AREA_MARGIN - 40.0)
		"zone":
			# Inside the next cell, ~250 px off its centre: the pack wakes OFF SCREEN and walks in.
			var z: Dictionary = run.zones[0]
			run.player_pos = (z["centre"] as Vector2) + Vector2(0, 250.0)
		"feature":
			# Stand on the DECK at the middle of a crossing — the place with water on BOTH sides,
			# which is the bridge over the river / the walkway over the bog. A look pass at the
			# hero's own spawn photographs the entrance, and the terrain feature is a hundred steps
			# away from it.
			#
			# ⚠️  "most water in the neighbourhood" picks an EDGE cell (water wraps three sides),
			# and the first capture was taken from the very lip of the bridge: water on the left,
			# planks on the right, and the bridge itself out of frame. The middle is the cell with
			# water on two OPPOSITE sides and the SMALLEST distance to both.
			var best := Vector2i(-1, -1)
			var best_score := INF
			for cy in SurvivorRun.ROWS:
				for cx in SurvivorRun.COLS:
					if not run.is_deck_cell(cx, cy):
						continue
					var span := _water_span(run, cx, cy)
					if span < 0.0 or span >= best_score:
						continue
					best_score = span
					best = Vector2i(cx, cy)
			if best.x >= 0:
				run.player_pos = run.cell_centre(best.x, best.y)


## How BALANCED the water is on both sides of a deck cell: 0 is dead centre, larger is lopsided,
## -1 is a cell with water on one side only. Used to stand the camera in the middle of a bridge
## (the first version returned the raw gap and ties went to whichever cell the scan met first,
## which put the hero on the bridge's lip).
func _water_span(run, cx: int, cy: int) -> float:
	var left := -1
	var right := -1
	var up := -1
	var down := -1
	for i in range(1, 6):
		if left < 0 and run.is_water_cell(cx - i, cy):
			left = i
		if right < 0 and run.is_water_cell(cx + i, cy):
			right = i
		if up < 0 and run.is_water_cell(cx, cy - i):
			up = i
		if down < 0 and run.is_water_cell(cx, cy + i):
			down = i
	var best := -1.0
	if left > 0 and right > 0:
		best = float(absi(left - right)) + float(6 - mini(left + right, 6)) * 0.1
	if up > 0 and down > 0:
		var v := float(absi(up - down)) + float(6 - mini(up + down, 6)) * 0.1
		if best < 0.0 or v < best:
			best = v
	return best


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				_out = args[i + 1]
			"--frames":
				_frames_to_run = int(args[i + 1])
			"--walk":
				_walk = args[i + 1] != "0"
			"--stick":
				_stick = args[i + 1]
			"--swing":
				_wait_swing = args[i + 1] != "0"
			"--telegraph":
				_wait_telegraph = args[i + 1] != "0"
			"--pack":
				_pack = int(args[i + 1])
			"--spot":
				_spot = args[i + 1]
			"--spells":
				_spells = args[i + 1] != "0"
			"--flurry":
				_flurry = args[i + 1] != "0"
			"--cast":
				_cast_id = args[i + 1]
			"--cast-at":
				_cast_at = int(args[i + 1])
			"--portal":
				_portal = args[i + 1] != "0"
			"--zone":
				_zone = int(args[i + 1])
			"--drop":
				_drop = int(args[i + 1])
			"--map":
				_map = args[i + 1] != "0"
			"--mapclose":
				_map_close = args[i + 1] != "0"
			"--explore":
				_explore = args[i + 1] != "0"
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		# `_nav_bar` is the last cheap marker of "main is fully built" — the same gate
		# capture_screen.gd uses, because entering a screen before that gets overwritten.
		#
		# ⚠️  AND WAIT OUT THE SPLASH. It is a `CanvasLayer` at layer 40 that sits over EVERY
		# screen for ~3.9 s (`HOLD_MS + FADE_OUT_MS`), so a capture taken before it finishes is a
		# photograph of the logo with the fight invisible behind it — measured: an 80-frame run
		# returned the splash card, and the file looked like "the game has no HUD at all".
		if not _main._screens.has("survivor") or _main._nav_bar == null:
			return false
		if _main._splash != null and _main._splash.visible:
			_main._splash._tick(60000.0)
			return false
		_started = true
		_main._enter_survivor(0, _zone)
		_screen = _main._screens["survivor"]
		# A look-probe is not a play session: it must not overwrite the local save.
		_main.state.save_enabled = false
		_place_hero()
		if _explore and _screen.run != null:
			_explore_route()
		if _drop > 0 and _screen.run != null:
			_stage_drops()
		if _portal:
			# ⚠️  A scroll IN THE BAG, not the belt counter: that is the case Jan reported ("ani
			# když mám scrolly") and the one the old check missed. If this frame shows the button,
			# the fix is in the build he is looking at.
			_main.state.data["townPortalCount"] = 0
			_main.state.add_item("townPortalScroll", _main.data.item("townPortalScroll"), 1)
			if _screen.run != null:
				_screen.run.portal_point = _screen.run.player_pos + Vector2(0.0, 58.0)
				_screen.run.portal_open = true
		if _spells or _flurry:
			_grant_spells()
		if _pack > 0 and _screen.run != null:
			var run = _screen.run
			run.monsters.clear()
			for i in _pack:
				run._spawn_one()
				var ang := TAU * float(i) / float(_pack) + 0.4
				# ⚠️  CLAMPED TO FLOOR. A raw ring of 105 px around the hero lands in the jungle on a
				# village walkway, so the frame showed three bodies hanging off the planks and read as
				# a spawn bug. The look-probe must photograph the game, not its own geometry.
				run.monsters[i]["pos"] = run.nearest_floor_point(
					run.player_pos + Vector2(cos(ang), sin(ang)) * 105.0)
		return false

	if _screen == null:
		return false
	# ⚠️  TWO WHEELS, TWO HALVES: the stick is planted on the RIGHT, the action wheel on the LEFT
	# (Jan, Nov 2026). A press on the wrong side starts the other control.
	if _frames == 4 and _walk:
		_screen._on_press(Vector2(250, 660))
		_screen._on_drag(Vector2(290, 610))
	# THE ATTACK WEDGE IS HELD, or the hero never swings and `--wait_swing` waits forever: since
	# Jan's D2R rule a thumb that is not on an action means a hero who stands and looks. The wheel
	# is FIXED in the bottom-left now, so the thumb goes to ITS centre and pushes up past the
	# resting disc; the frame also shows the wheel in its active state (which it always has now).
	if _frames == 6:
		var wc: Vector2 = _screen.wheel_centre()
		_screen._on_press(wc, 7)
		_screen._on_drag(wc + Vector2(0, -(_screen.wheel_inner() + 14.0)), 7)
	# ⚠️  THE WALK STOPS. A shot taken while still running shows a hero who outran his pack and is
	# now surrounded from BEHIND — which the facing rule correctly refuses to swing at, so
	# `--wait_swing` never finds a blow. Standing still is also the beat worth judging: the assist
	# turns him and the fight happens under the wheel.
	if _frames == 4 + _walk_frames and _walk:
		_screen._on_release()
	# A flurry has to be OPEN at capture time: its row only exists while the flurry runs, and the
	# run's own clock burns the deadline in 1.5 s, so it is opened a handful of frames before.
	if _cast_id != "" and _frames == _frames_to_run - _cast_at and _screen.run != null:
		_screen._cast_spell(_cast_id)
	if _flurry and _frames == _frames_to_run - 12 and _screen.run != null:
		_screen._layout_spells()
		_screen._cast_spell("whirlwind")
	_frames += 1
	if _frames < _frames_to_run:
		return false
	if _wait_swing and _screen.run != null:
		var age: float = _screen.run.swing_age
		if age < 0.0 or age > 0.07:
			_stall += 1
			if _stall < 180:
				_frames -= 1
				return false
			print("look_survivor: no swing window (held=%s screen_held=%s held_spell='%s' slots=%s idx=%d slot=%d target=%d pick=%d facing=%s closest=%.0f)"
				% [str(_screen.run.attack_held), str(_screen._attack_held), str(_screen._held_spell),
					str(_screen._wheel_slots), _screen._wheel_index,
					_screen._wheel_slot, int(_screen.run.target_id),
					_screen.run._pick_target(), str(_screen.run.facing),
					(_screen.run.monsters[0]["pos"] as Vector2).distance_to(_screen.run.player_pos)
						if not _screen.run.monsters.is_empty() else -1.0])
	if _wait_telegraph and _screen.run != null:
		var committed := false
		for m in _screen.run.monsters:
			if float(m.get("atk_t", -1.0)) >= 0.0:
				committed = true
				break
		if not committed:
			_stall += 1
			if _stall < 180:
				_frames -= 1
				return false
			print("look_survivor: no committed body in the window (alive=%d)" % _screen.run.monsters.size())
	if _map and _screen != null:
		# Through the REAL press path, so the frame also proves the button is hittable where it is
		# drawn — a private `_open_map()` would photograph a map nobody can open.
		_screen._on_press(_screen._map_rect.get_center())
		if not _screen._map_open:
			print("look_survivor: the Mapa button did not take a press at %s" % str(_screen._map_rect))
			_screen._open_map()
	if _map_close and _screen != null and _screen._map_open:
		_screen._on_press(Vector2(6, 6), 0)
		if _screen._map_open:
			print("look_survivor: a tap outside the sheet did NOT close the map")
		print("look_survivor: after the map round trip the button is %s (was a 38x38 plate in the bar)"
			% str(_screen._map_rect))
	_capture()
	return false


## Item drops of three qualities, laid out in an arc in front of the hero. The item DATA is a
## copy of a real base with only the fields the marker reads (`quality`, `name`), because a
## marker is drawn from the colour, not from the item: this frame is about the marker.
func _stage_drops() -> void:
	var run = _screen.run
	var quals := ["normal", "magic", "rare", "unique"]
	var cols := {"normal": "#888888", "magic": "#4a7dff", "rare": "#ffd700", "unique": "#b8860b"}
	for i in _drop:
		var q: String = quals[i % quals.size()]
		var ang := -PI * 0.5 + (float(i) - float(_drop - 1) * 0.5) * 0.42
		run.drops.append({
			"pos": run.player_pos + Vector2(cos(ang), sin(ang)) * 96.0,
			"kind": "item",
			"item": {"id": "probe_%d" % i, "name": "probe", "quality": q},
			"age": 0.0,
			"color": str(cols.get(q, "#888888")),
		})


## A handful of the barbarian's spells bought, so the column has buttons in it. The SAVE is not
## written; the run reads the talent levels live through `PlayerSpells`.
func _grant_spells() -> void:
	var st = _screen._state
	var levels: Dictionary = st.data.get("talentLevels", {})
	for id in ["heroicStrike", "thunderClap", "thunderBolt", "doubleSwing", "battleShout",
			"defensiveShout", "pummel", "whirlwind", "frenzy"]:
		levels["barbarian_%s" % id] = 2
	st.data["talentLevels"] = levels
	# The wheel's defaults are DERIVED from the bar, so a freshly granted spell has to re-resolve
	# them or the frame shows a wheel with the old (shorter) bar.
	_screen._wheel_slots = _screen._resolve_wheel()


## Walk the ROUTE through the fog, one reveal per ~120 px, then put the hero back where the probe
## staged him. Used by `--explore` so a map frame is judged on "what a player who walked here
## sees" instead of on the 6 cells around the spawn.
func _explore_route() -> void:
	var run = _screen.run
	if run.path_points.size() < 2:
		return
	var keep: Vector2 = run.player_pos
	var prev: Vector2 = run.path_points[0]
	run.player_pos = run.nearest_floor_point(prev)
	run._reveal_around(run.player_pos)
	for i in range(1, run.path_points.size()):
		var p: Vector2 = run.path_points[i]
		var steps := maxi(1, int(ceil(prev.distance_to(p) / 120.0)))
		for s in range(1, steps + 1):
			var q := prev.lerp(p, float(s) / float(steps))
			run.player_pos = run.nearest_floor_point(q)
			run._reveal_around(run.player_pos)
		prev = p
	run.player_pos = keep
	run._reveal_around(keep)


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out)
	var run = _screen.run
	var kinds: Array = []
	for e in run.effects:
		kinds.append(str(e["kind"]))
	print("look_survivor: %s %dx%d kills=%d drops=%d alive=%d hp=%d/%d wave=%d t=%.1f effects=%s bolts=%d"
		% [_out, img.get_width(), img.get_height(), run.kills, run.drops.size(),
			run.monsters.size(), run.hp, run.max_hp, run.wave, run.elapsed, str(kinds),
			run.bolts.size()])
	quit(0)
