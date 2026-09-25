extends SceneTree
class_name CaptureScreen
## CaptureScreen — boot the game, optionally jump to one screen, save a PNG.
##
## Why this exists: the port is judged against the PWA screenshots, and "the arena looks
## wrong" is not something a headless test can tell you. This drives the real main.gd and
## writes a real frame, so a visual diff is possible without a desktop.
##
##   godot4 --path . --script res://tools/capture_screen.gd -- \
##       --screen arena --out /tmp/port_arena.png --frames 90
##
## `--screen` accepts a router key (town, inventory, arena, shop, chest, craft, gamble,
## hero). `--fight-ticks N` steps the arena N times before the shot so the fight is
## mid-swing rather than on frame zero.

var _main: Node = null
var _frames := 0
var _target := 60
var _out := "/tmp/port_shot.png"
var _screen := ""
var _fight_ticks := 0
## `--result lose` captures the DEFEAT page rather than the victory one.
var _result_lose := false
## `--tab sell` presses the screen's OWN tab button after entering (the shop's Buy/Sell
## strip). Driving the button rather than writing `_tab` follows the route a tap takes —
## a hand-written field would pass against broken wiring.
var _tab := ""
## `--bag a,b,c` seeds the hero's inventory before the capture, so a screen that renders the
## BAG (the shop's sell list) has something in it. Without it a fresh save shows an empty
## list, and an empty list is a frame that proves nothing about the card that overflows.
var _bag := ""
var _started := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				_out = args[i + 1]
			"--frames":
				_target = int(args[i + 1])
			"--screen":
				_screen = args[i + 1]
			"--fight-ticks":
				_fight_ticks = int(args[i + 1])
			"--result":
				_result_lose = args[i + 1] == "lose"
			"--tab":
				_tab = args[i + 1]
			"--bag":
				_bag = args[i + 1]
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


## Write the `--bag` list into the hero's inventory before entering. The shop's SELL tab
## renders the BAG, and a fresh save has none — so without this the capture is an empty list
## and proves nothing about the card Jan reported running off the screen.
func _seed_bag() -> void:
	if _bag == "":
		return
	var state = _main.state
	state.data["hero"]["inventory"] = []
	for id in _bag.split(","):
		var clean := id.strip_edges()
		if clean != "":
			state.data["hero"]["inventory"].append(clean)
	state.data["hero"]["gold"] = 5000


func _process(_delta: float) -> bool:
	# _ready() on a node added in _initialize() has NOT run yet — the SceneTree calls it
	# when the main loop starts, i.e. after this first _process. Waiting only "one frame"
	# was not enough: `show_screen("town")` in main's _ready() runs AFTER _entry() and
	# overwrites whatever the capture asked for, which is why every `--screen` other than
	# town came back as the town. Wait until the screens actually exist, then enter.
	if not _started:
		# Wait for main to be FULLY built, not merely started. `_screens["town"]` exists as
		# soon as its `_add_screen` runs, but `_build_screens()` continues and `_ready()`
		# then calls `show_screen("town")` — which resets every screen's visibility. Entering
		# between those two points let town overwrite whatever was asked for, so every
		# `--screen` came back as the town. `_nav_bar` is built after the screens and before
		# that call, so it is the last cheap marker of "main is done".
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		_seed_bag()
		_entry()
		return false

	_frames += 1
	if _frames < _target:
		return false
	# _capture() awaits frame_post_draw, so the tree MUST stay alive this frame or the
	# await never resumes and no PNG is written (the old `return true` here did exactly
	# that): quit() only inside _capture, after the image is saved.
	_capture()
	return false


## Resolve `--screen` to (router key, tab). `inventory`, `talents` and `hero` are the PWA's
## three tabs of ONE modal — in the port they are `character` plus a tab name. Both the
## reference set's own names and an explicit `<screen>@<tab>` resolve here, and this is the
## ONE place that knows the mapping.
##
## Why it is a function with a verdict rather than an `if` chain: `--screen inventory` used to
## fall through to `show_screen("inventory")`, which pushes an error and shows NOTHING — the
## town stayed up and `town.png` was written under the name `inventory.png`. The frame was
## real and the file name was a lie, which is exactly how four of the ten PWA reference frames
## went wrong in an earlier session. An unknown key now stops the capture instead.
## The PWA's nav keys and the modal's PANE keys are two different vocabularies:
## `main.gd`'s `MODAL_TABS` maps `talents -> skills` and `hero -> stats`, and the modal's own
## `TABS` are `inventory` / `skills` / `stats`. Passing a nav key straight to `set_tab()` hits
## `if not _panes.has(key): return` and leaves whatever tab was up — which is why all three
## captures came back as the Inventory pane. The map is spelled out here the same way, and
## an explicit `<screen>@<pane>` form stays available for an exact pane.
func _resolve(name: String) -> Dictionary:
	match name:
		"inventory":
			return {"key": "character", "tab": "inventory"}
		"talents":
			return {"key": "character", "tab": "skills"}
		"hero":
			return {"key": "character", "tab": "stats"}
		"character":
			return {"key": "character", "tab": "inventory"}
		_:
			if name.begins_with("character@"):
				return {"key": "character", "tab": name.split("@")[1]}
			return {"key": name, "tab": ""}


func _entry() -> void:
	if _screen == "":
		return
	var resolved := _resolve(_screen)
	var key := str(resolved["key"])
	if key == "character":
		var tab := str(resolved["tab"])
		_main.open_modal(tab)
		# `CharacterModal.set_tab()` returns silently for a key it has no pane for, so a
		# capture with a wrong key would write a REAL frame of whatever pane was already up
		# under the name it asked for. All three of these came back byte-identical once.
		var modal = _main._screens["character"]
		if str(modal._active) != tab:
			push_error("capture_screen: asked for pane '%s', the modal is on '%s'"
				% [tab, str(modal._active)])
			print("capture: FAIL pane '%s' is not in the modal (asked '%s', got '%s')"
				% [tab, _screen, str(modal._active)])
			quit(2)
			return
		return
	if key == "arena":
		# Entering through the REAL route: a stop on the map winds progress forward and
		# starts the fight. `_on_wilderness()` used to exist and was deleted with the
		# map rebuild, which silently broke every arena capture after that.
		_main._on_stop_selected(0, 0)
	elif key == "result":
		# The result PAGE, which only exists at the end of a fight — so the fight has to
		# actually end. `--result lose` kills the hero instead of the enemy.
		_main._on_stop_selected(0, 0)
		var arena = _main._screens["arena"]
		if arena.battle != null:
			if _result_lose:
				arena.battle.hero_max_hp = 1.0
				arena.battle.hero_hp = 1.0
				arena.battle.gap = 0.0
			else:
				arena.battle.enemy_hp = 0.0
				arena.battle.gap = 0.0
			var guard := 0
			while (not arena.battle.ended or not arena._result_built) and guard < 300:
				arena.step()
				guard += 1
	elif not _main._screens.has(key):
		# A name the router does not have used to be a silent no-op: the capture then wrote
		# whatever WAS up under the asked-for name.
		push_error("capture_screen: no screen named '%s' (asked for '%s')" % [key, _screen])
		print("capture: FAIL no screen named '%s'" % key)
		quit(2)
		return
	else:
		_main.show_screen(key)

	if _fight_ticks > 0 and key == "arena":
		var arena = _main._screens["arena"]
		var t := 0
		while t < _fight_ticks and arena.battle != null and not arena.battle.ended:
			arena.step()
			t += 1
	_apply_tab()


## Press the screen's OWN tab button (`--tab sell`). The shop's Buy/Sell strip is the only
## one today. Driving the button is what makes this follow the route a tap takes: a helper
## that wrote `_tab` directly would pass against broken wiring, and the failure being hunted
## here (the sell card running off the canvas) is a layout consequence of that branch.
##
## It STOPS when the tab did not move, for the same reason `--screen` does: a capture that
## writes a real frame of the Buy tab under the name `shop_sell.png` is a file name lying
## about its contents.
func _apply_tab() -> void:
	if _tab == "":
		return
	var screen = _main._screens.get(_screen, null)
	if screen == null:
		return
	if not ("_tab_buttons" in screen):
		print("capture: WARN screen '%s' has no tabs, --tab ignored" % _screen)
		return
	var buttons: Array = screen._tab_buttons
	if buttons.is_empty():
		print("capture: WARN screen '%s' built no tab buttons" % _screen)
		return
	var index := 0 if _tab == "buy" else 1
	if index >= buttons.size():
		print("capture: FAIL no tab '%s' on '%s'" % [_tab, _screen])
		quit(2)
		return
	# Emit the signal the button is wired to, exactly as a press does.
	buttons[index].emit_signal("pressed")
	if str(screen._tab) != _tab:
		print("capture: FAIL asked for tab '%s' on '%s', the screen is on '%s'"
			% [_tab, _screen, str(screen._tab)])
		quit(2)
		return
	print("capture: tab=%s" % str(screen._tab))


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out)
	# `current` is the screen the port says is up — a file name is not evidence of its own
	# contents, and these are diffs against the PWA.
	print("capture: %s %dx%d asked=%s current=%s" % [_out, img.get_width(), img.get_height(),
		_screen, str(_main._current)])
	quit()
