extends SceneTree
class_name CaptureScreen
const ToolHelpers := preload("res://tools/tool_helpers.gd")
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
## `--nodes N` sets the road's `areaFightProgress` before the shot, so a capture can show a stop
## that is part way through (some dots ticked, the current one live, the rest locked) instead of
## only the fresh-stop case Jan kept seeing as "every dot says 0".
var _node_states := ""
## `--tab sell` presses the screen's OWN tab button after entering (the shop's Buy/Sell
## strip). Driving the button rather than writing `_tab` follows the route a tap takes —
## a hand-written field would pass against broken wiring.
var _tab := ""
## `--bag a,b,c` seeds the hero's inventory before the capture, so a screen that renders the
## BAG (the shop's sell list) has something in it. Without it a fresh save shows an empty
## list, and an empty list is a frame that proves nothing about the card that overflows.
var _bag := ""
## `--opp dodge|block|counter` forces an OPEN reaction window on the arena before the shot.
## The window itself is a roll (12-40 % per enemy swing), so a capture that waits for one
## writes a different state every run — and a frame of the reaction row is exactly what a
## "the Dodge button is broken" report needs to be judged against.
var _opp := ""
## `--opp-fail` answers the window with a WRONG button first, so the frame shows the cross.
var _opp_fail := false
## `--opp-hit` answers it CORRECTLY, so the frame shows the tick. Separate from `--opp-fail`
## because they are the two halves of the PWA's `showOpportunitySuccess` /
## `showOpportunityFail` pair and a capture has to be able to ask for either.
var _opp_hit := false
## `--shield` equips a real shield before the fight, which is the only way `--opp-fail` has a
## wrong button to press: `updateDefBtnsVisibility` hides Block from a hero without one, and a
## window whose wrong answer is hidden cannot be answered wrongly at all.
var _shield := false
var _started := false
## `--web` forces the web-only sections on so a desktop capture can show them.
var _force_web := false
## `--scroll max` shows the BOTTOM of the page (the town's update section lives there).
var _scroll := ""
## The stop the `world` capture enters. Act 0, stop 0 — the first one a player sees.
const STOP_FOR_CAPTURE := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		# ⚠️  A FLAG consumes ONE token, an option consumes TWO. Every token used to be read as
		# a pair, so `--opp-fail --shield` swallowed `--shield` as `--opp-fail`'s value and the
		# shield was never equipped — which read as "the wrong button is not visible" rather
		# than as a parse bug.
		var step := 2
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
			"--nodes":
				_node_states = args[i + 1]
			"--opp":
				_opp = args[i + 1]
			"--opp-fail":
				_opp_fail = true
				step = 1
			"--opp-hit":
				_opp_hit = true
				step = 1
			"--shield":
				_shield = true
				step = 1
			"--scroll":
				_scroll = args[i + 1]
			"--web":
				# Draws the web-only parts a desktop run cannot have — today the town's
				# AKTUALIZOVAT HRU section. A phone-only feature that is previewed only on
				# the phone is a feature nobody can look at before shipping it.
				_force_web = true
				step = 1
		i += step
	# ⚠️  BEFORE main is built: the town decides whether to create the section in _build().
	if _force_web:
		var check := preload("res://scripts/ui/update_check.gd")
		check.force_web = true
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


## `--shield` — a REAL shield from the item table, because `battle.hero_has_shield` reads the
## item's own `type` and a made-up id would have none. Equipping one is what makes Block
## visible, and Block is the wrong button `--opp-fail` presses.
##
## ⚠️  It runs AFTER `_seed_bag()`, not with it. `enter_arena` calls `main._on_stop_selected`,
## which winds the act forward and STARTS THE FIGHT — and starting a fight re-applies the
## class kit, wiping `equip["shield"]`. Seeding before `_entry()` therefore had no effect at
## all: measured, `--shield --opp-fail` still failed with "no usable wrong button".
func _seed_shield() -> void:
	if not _shield:
		return
	_main.state.equip()["shield"] = "shield_buckler"
	_main.state.save()


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
	# `--scroll max` BEFORE the shot: the town's update section sits below the fold, and a
	# capture that only ever shows the top of a page cannot judge it.
	if _scroll == "max":
		# A SceneTree script IS the tree — there is no `get_tree()`, `root` is the window.
		var sc := _find_scroll(_main)
		if sc != null:
			sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
	# _capture() awaits frame_post_draw, so the tree MUST stay alive this frame or the
	# await never resumes and no PNG is written (the old `return true` here did exactly
	# that): quit() only inside _capture, after the image is saved.
	_capture()
	return false


## The first ScrollContainer under `node` — the page a screen is built on.
func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found := _find_scroll(child)
		if found != null:
			return found
	return null


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
	if key == "world":
		# Through the REAL route: a stop on the map winds the act's progress and opens the road,
		# which is also what writes `_currentAct` (`_on_stop_selected` -> the stop's transition
		# -> `show_world`). One step past the hold runs that callback, exactly as 1.8 s of
		# frames would — the same driving `ToolHelpers.enter_arena` does.
		_main._on_stop_selected(0, STOP_FOR_CAPTURE)
		var tr = _main._transition
		if tr != null and tr.is_transitioning():
			tr._process(tr.HOLD_MS / 1000.0 + 0.01)
		# A fresh stop unless `--nodes` asked for a road with fights already won. This is the
		# case Jan reported as "every dot says 0": on a fresh stop that IS what the road shows
		# (dot 1 live, the other nine behind padlocks), so the capture has to be able to ask
		# for a stop that is part way through.
		if _node_states != "":
			_main.state.data["areaFightProgress"][0] = int(_node_states)
			_main.show_world(0)
	elif key == "arena":
		# Entering through the REAL route: a stop on the map winds progress forward and
		# starts the fight. `_on_wilderness()` used to exist and was deleted with the
		# map rebuild, which silently broke every arena capture after that.
		ToolHelpers.enter_arena(_main, 0, 0)
	elif key == "result":
		# The result PAGE, which only exists at the end of a fight — so the fight has to
		# actually end. `--result lose` kills the hero instead of the enemy.
		ToolHelpers.enter_arena(_main, 0, 0)
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
	_arm_opportunity(key)
	_apply_tab()


## `--opp <kind>` — open a reaction window of a KNOWN kind and (with `--opp-fail`) answer it
## wrongly, so a capture can show the row, the middle icon, or the cross on purpose.
##
## ⚠️  It writes `battle.opp_type` rather than waiting for `arm_opportunity` to roll one. The
## roll is the RULES' business (`test_reactions` covers it); what a frame is needed for is the
## LAYOUT of a window, and a capture that waits for the roll writes a different state every run
## — once produced four frames of a plain fight under reaction-related names.
func _arm_opportunity(key: String) -> void:
	if _opp == "" or key != "arena":
		return
	var arena = _main._screens.get("arena", null)
	if arena == null or arena.battle == null:
		print("capture: FAIL --opp %s but the arena has no fight" % _opp)
		quit(2)
		return
	# ⚠️  AFTER the fight exists, never before: `enter_arena` starts the fight, and starting
	# one re-applies the class kit, which wipes the shield `--shield` just equipped.
	if _shield:
		_main.state.equip()["shield"] = "shield_buckler"
		print("capture: shield=", _main.state.equip().get("shield", "?"),
			" has_shield=", arena.battle.hero_has_shield(_main.state, arena._find_item))
	var battle = arena.battle
	battle.opp_type = _opp
	battle.opp_resolved = false
	battle.opp_failed = false
	if _opp_hit:
		# The PWA's `onPsDefButton` correct branch. Through the BUTTON's own signal, and the
		# button for the OPEN kind, so the tick is raised the way a real tap raises it.
		arena._refresh_reaction_layer(0.016)
		var correct: Button = arena._reaction_buttons[_opp]
		if correct == null or not correct.visible:
			print("capture: FAIL --opp-hit has no visible button for '%s'" % _opp)
			quit(2)
			return
		correct.pressed.emit()
		arena._refresh_reaction_layer(0.016)
		if not battle.opp_resolved:
			print("capture: FAIL --opp-hit did not answer the window")
			quit(2)
			return
	if _opp_fail:
		# Through the BUTTON's own signal, exactly as a tap does. A window that went wrong
		# has to have gone wrong through the real path or the frame proves nothing.
		#
		# ⚠️  The wrong button is whichever OTHER reaction is VISIBLE: Block is hidden from a
		# hero with no shield and Counter from one without the talent, and pressing a hidden
		# button would close the window through a route no player has. Pass `--shield` to
		# guarantee one exists.
		arena._refresh_reaction_layer(0.016)
		var button: Button = null
		for other in ["block", "counter"]:
			if other == _opp:
				continue
			var candidate: Button = arena._reaction_buttons[other]
			if candidate != null and candidate.visible:
				button = candidate
				break
		if button == null:
			print("capture: FAIL --opp-fail has no usable wrong button against '%s' "
				% _opp + "(add --shield, or invest the counter talent)")
			quit(2)
			return
		button.pressed.emit()
		arena._refresh_reaction_layer(0.016)
		if not battle.opp_failed:
			print("capture: FAIL --opp-fail did not close the window")
			quit(2)
			return
	arena._refresh_reaction_layer(0.016)
	print("capture: opp=%s open=%s failed=%s" % [_opp, str(battle.opportunity_open()),
		str(battle.opp_failed)])


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
