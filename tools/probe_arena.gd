extends SceneTree

const ToolHelpers := preload("res://tools/tool_helpers.gd")
## Probe the PORT's arena the way `tools/import/probe_arena.py` probes the PWA.
##
## The two output the same columns on purpose: "the hero has the wrong HP / no mana /
## the swing timers do not run" is a claim about the MECHANICS, and the only way to
## settle it is to read the same numbers off both builds. Headless, so it can run in CI:
## it asserts nothing, it prints.
##
##   godot4 --headless --path . --script res://tools/probe_arena.gd -- --steps 120

var _main: Node = null
var _steps := 60
var _started := false
var _t := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--steps":
			_steps = int(args[i + 1])
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		ToolHelpers.enter_arena(_main, 0, 0)
		var arena = _main._screens["arena"]
		# The screen's own _process() pumps step() as well, so without this the probe
		# advances the fight TWICE per row and every printed millisecond is really two.
		# The probe is the only clock here, which is what makes its columns comparable
		# with probe_arena.py's (both are a true 100 ms tick).
		arena.set_process(false)
		print("swing_ms=%d offhand_ms=%d enemy_ms=%d hero_max_hp=%d hero_hp=%d arena=%dx%d"
			% [arena.battle.player_swing_ms, arena.battle.offhand_swing_ms,
				arena.battle.enemy_swing_ms, arena.battle.hero_max_hp, arena.battle.hero_hp,
				int(arena._arena.size.x), int(arena._arena.size.y)])
		# The placement is normally refreshed by the screen's own _process -> _animate();
		# the probe switched that off (it would advance the fight twice), so it has to
		# drive the renderer's placement itself. Without this the hero reads as size 0
		# and the walk-in is invisible to the probe — which proved nothing about _gap.
		arena._place_hero(0.0)
		return false

	if _t >= _steps:
		return false
	var arena = _main._screens["arena"]
	arena.step()
	arena._place_hero(0.0)
	_t += 1
	var b = arena.battle
	if b == null:
		return false
	var hero: Dictionary = _main.state.hero()
	var sprite = arena._hero_sprite
	var arena_h: float = arena._arena.size.y
	print("t=%-5d hp=%-6d/%-6d mana=%-4d/%-4d enemy=%-7.0f/%-7.0f gap=%.2f cPl=%.2f cEn=%.2f heroY=%.2f heroSize=%.0f arenaH=%.0f ended=%s"
		% [_t * 100, int(b.hero_hp), int(b.hero_max_hp), int(hero.get("mana", 0)),
			int(hero.get("maxMana", 0)), b.enemy_hp, b.enemy_max_hp, b.gap,
			b.player_swing_elapsed / maxf(float(b.player_swing_ms), 1.0),
			b.enemy_swing_elapsed / maxf(float(b.enemy_swing_ms), 1.0),
			sprite.position.y / maxf(arena_h, 1.0), sprite.size.x, arena_h, str(b.ended)])
	if _t >= _steps or b.ended:
		quit(0)
	return false
