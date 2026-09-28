"""Drive the REAL main.gd and read which pane the modal actually shows, per entry route.

Jan: "u modal okna ... budeme vždy jako výchozí kartu otevírat inventář. Teď se otevírají staty."

A `--headless` test can assert `_active` until the cows come home; this asks the GAME, through the
routes a finger takes, and prints the pane that came up. Run it when the report is about which tab
a player lands on, because the answer is in the routes and not in the modal.

    ~/tools/godot/godot4 --headless --path . --script res://tools/probe_modal_default.gd
"""
extends SceneTree

const Main := preload("res://scripts/main.gd")

var _main: Node = null
var _started := false


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null or _main.state == null:
			return false
		_started = true
		_run()
		return false
	return false


func _run() -> void:
	var modal = _main._screens["character"]
	var routes := [
		["nav: inventory (Predmety)", func(): _main._on_nav_selected("inventory")],
		["nav: talents (Dovednosti)", func(): _main._on_nav_selected("talents")],
		["nav: hero (Hrdina)", func(): _main._on_nav_selected("hero")],
		["arena: Hrdina button", func(): _main.open_modal("stats")],
	]
	# Every route, from a clean town. `show_screen` is what a fresh entry does.
	for route in routes:
		_main.show_screen("town")
		(route[1] as Callable).call()
		print("ROUTE %-26s -> pane='%s'" % [str(route[0]), str(modal._active)])

	# THE SEQUENCE THAT MATTERS: visit Stats first (the arena's Hrdina button asks for it), then
	# enter through the nav's Predmety, which asks for Inventory.
	_main.show_screen("town")
	_main._on_nav_selected("hero")
	print("SEQUENCE after Hrdina      -> pane='%s'" % str(modal._active))
	_main._on_nav_selected("inventory")
	print("SEQUENCE Predmety next     -> pane='%s'  (expected 'inventory')" % str(modal._active))

	# And opening the dialog with no tab named at all.
	_main.show_screen("town")
	modal.open_default_tab()
	print("FRESH open (no tab named)  -> pane='%s'  (expected 'inventory')" % str(modal._active))
	quit(0)
