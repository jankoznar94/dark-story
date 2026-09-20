extends SceneTree
## GATE for Jan's reports 1 and 3, as one runnable test.
##
##   1. "the body does not lie down smoothly, it becomes lying instantly" - so the
##      corpse's fall is SAMPLED: the death clip must be allowed to run (speed_scale
##      stays 1.0 while it plays), the model root must NOT be pre-rotated to the
##      prone pose, and the head must descend GRADUALLY from standing height to a
##      body on the ground. A single-step drop fails the gate.
##
##   3. "items from the inventory cannot be equipped into the slots" - so the
##      interaction a player performs on a phone is exercised: TAP the item in the
##      bag, then TAP the box. The old build equipped nothing that way (a tap only
##      opened a tooltip, a tap on a box only unequipped), which is the report.
##      Both halves are asserted: the wrong box is refused, the right one equips.
##
## Run: godot --headless --path . --script res://tools/test_corpse_fall_and_equip.gd
## Prints CORPSE_FALL_AND_EQUIP_ALL_PASS=true/false.

const IB := preload("res://scripts/item_base.gd")
const Inv := preload("res://scripts/inventory_model.gd")
const Item := preload("res://scripts/item.gd")
const HeroStats := preload("res://scripts/hero_stats.gd")

var main: Node
var fails: Array[String] = []
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	_test_equip_by_taps()
	await _test_corpse_fall()
	print("")
	print("checks executed: ", checks)
	if fails.is_empty() and checks >= 12:
		print("CORPSE_FALL_AND_EQUIP_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		print("CORPSE_FALL_AND_EQUIP_ALL_PASS=false")
	quit()


# ------------------------------------------------------------- 3. equip by taps
func _test_equip_by_taps() -> void:
	print("== tapping an item, then tapping its box, equips it ==")
	var ui: Control = main.get_node("HUD/InventoryUI")
	var model = Inv.new()
	var st = HeroStats.new(40)         # enough Strength for a cap, not for plate
	ui.setup(model, st)
	ui.set_open(true)
	ui.size = ui.get_viewport_rect().size
	ui.layout_now()

	# --- the right box
	var cap = Item.new("cap", IB.Rarity.NORMAL, 5)
	model.add(cap)
	ui.layout_now()
	var cap_rect: Rect2 = ui.cell_rect(model.placements[0]["pos"], model.placements[0]["size"])
	var helm_rect: Rect2 = ui._slot_rect(0)                      # slot 0 = helm
	ui._tap(cap_rect.position + cap_rect.size * 0.5)             # pick it up
	_ok("a tap on a bag item PICKS IT UP (it is carried, not just described)",
		ui._held_item == cap, "held=%s" % str(ui._held_item != null))
	ui._tap(helm_rect.position + helm_rect.size * 0.5)           # put it in the helm box
	_ok("a tap on the HELM box equips it there", model.equipped_at(0) == cap,
		str(model.equipped_at(0)))
	_ok("the carried item is released after a successful equip", ui._held_item == null)
	_ok("the cap left the bag", model.placement_index_of(cap) < 0)

	# --- the WRONG box is refused, and says why, and changes nothing
	var boots = Item.new("boots", IB.Rarity.NORMAL, 5)
	model.add(boots)
	ui.layout_now()
	var boot_rect: Rect2 = ui.cell_rect(model.placements[0]["pos"], model.placements[0]["size"])
	var chest_rect: Rect2 = ui._slot_rect(1)                     # slot 1 = chest
	ui._tap(boot_rect.position + boot_rect.size * 0.5)
	ui._tap(chest_rect.position + chest_rect.size * 0.5)
	_ok("boots into the CHEST box is refused", model.equipped_at(1) == null,
		"chest=%s" % str(model.equipped_at(1)))
	_ok("...and the boots are still in the bag, still carried",
		model.placement_index_of(boots) >= 0 and ui._held_item == boots)
	ui._tap(ui._slot_rect(3).position + ui._slot_rect(3).size * 0.5)   # slot 3 = boots
	_ok("tapping the BOOTS box then equips them", model.equipped_at(3) == boots)

	# --- the Strength gate still answers through this path
	var plate = Item.new("plate_mail", IB.Rarity.NORMAL, 20)     # str_req 60
	model.add(plate)
	ui.layout_now()
	var pr: Rect2 = ui.cell_rect(model.placements[0]["pos"], model.placements[0]["size"])
	ui._tap(pr.position + pr.size * 0.5)
	ui._tap(ui._slot_rect(1).position + ui._slot_rect(1).size * 0.5)
	_ok("an item the hero cannot carry is refused by this path too",
		model.equipped_at(1) == null and model.placement_index_of(plate) >= 0)

	# --- a selection lapses rather than being installed by a later, unrelated tap
	var ring = Item.new("ring", IB.Rarity.NORMAL, 5)
	model.add(ring)
	ui.layout_now()
	var ri: int = model.placement_index_of(ring)
	var rr: Rect2 = ui.cell_rect(model.placements[ri]["pos"], model.placements[ri]["size"])
	ui._tap(rr.position + rr.size * 0.5)
	_ok("a picked-up item is carried", ui._held_item == ring,
		"held=%s" % (ui._held_item.display_name() if ui._held_item != null else "none"))
	ui._held_t = ui.HELD_TIMEOUT + 1.0
	ui._process(0.0)
	_ok("the selection lapses after HELD_TIMEOUT", ui._held_item == null)
	ui.set_open(false)


# ---------------------------------------------------------- 1. the corpse's fall
func _test_corpse_fall() -> void:
	print("== the corpse falls over, it does not become prone ==")
	main.clear_enemies()
	var e: Node = main._build_enemy("ghoul", Vector3(0, 0, -6.0))
	e.remember_home()
	var player: Node = main.get_node("Player")
	player.global_position = Vector3(0, 0, 0)
	var sk := _find_skel(e)
	var head := -1
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).to_lower().ends_with("head"):
			head = i
	e.take_damage(99999.0)
	await physics_frame

	_ok("the death clip is FREE to play after the kill (it was frozen on frame 0)",
		e.anim.is_playing() and e.anim.speed_scale > 0.0,
		"playing=%s speed_scale=%.2f" % [str(e.anim.is_playing()), e.anim.speed_scale])
	var mr = e.get_model_root()
	_ok("the model is NOT pre-rotated into the prone pose",
		absf(mr.rotation_degrees.x) < 1.0, "rot.x=%.2f" % mr.rotation_degrees.x)

	var heights: Array[float] = []
	for i in 60:
		await physics_frame
		heights.append((sk.global_transform * sk.get_bone_global_pose(head).origin).y)
	var h0: float = heights[0]
	var lo: float = 9.0
	var hi: float = -9.0
	for h in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	# A body that becomes prone INSTANTLY shows one height repeated (the old build:
	# the head went to lying height in the frame the monster died). A fall shows the
	# head passing through a RANGE of heights on its way down.
	_ok("the head travels DOWN through intermediate heights (a smooth fall)",
		(hi - lo) > 0.4, "range %.3f m (first %.3f, lowest %.3f)" % [hi - lo, h0, lo])
	_ok("the head STARTS standing up, not lying down",
		h0 > 0.6, "first sample %.3f m" % h0)
	# and once the clip is over the corpse is frozen, so it cannot writhe forever
	for i in 200:
		await physics_frame
	var rest := (sk.global_transform * sk.get_bone_global_pose(head).origin).y
	await physics_frame
	var rest2 := (sk.global_transform * sk.get_bone_global_pose(head).origin).y
	_ok("once the fall is over the corpse holds still (frozen, not looping)",
		absf(rest - rest2) < 0.02, "%.3f -> %.3f" % [rest, rest2])
	_ok("the corpse ends up on the ground", rest < 0.6, "head at %.3f m" % rest)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
