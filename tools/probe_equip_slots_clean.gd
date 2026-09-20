extends SceneTree
## DIAGNOSTIC: equip EVERY base into the slot that suits it, each one with a FRESH
## EMPTY bag, and print the outcome. A shared bag made the earlier run of this
## probe a lie: a refused item stays in the bag, and those leftovers then filled
## the grid for every later case - "V inventáři není místo pro sundanný předmět."
## while the bag was, at that point, full of earlier failures.
## Run: godot --headless --path . --script res://tools/probe_equip_slots_clean.gd

const IB := preload("res://scripts/item_base.gd")
const Inv := preload("res://scripts/inventory_model.gd")
const Item := preload("res://scripts/item.gd")

var bad := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("== equip each base into its own slot, FRESH bag each time ==")
	for id in IB.bases():
		var it = Item.new(id, IB.Rarity.NORMAL, 5)
		var want: int = it.slot()
		var idx := -1
		for i in Inv.SLOTS.size():
			if Inv.SLOTS[i] == want:
				idx = i
				break
		var sz: Vector2i = it.size()
		# (a) into the exact slot
		var inv = Inv.new()
		inv.add(it)
		var placed: int = inv.placements.size()
		var res: Dictionary = inv.equip(it, idx)
		var on: bool = inv.equipped_at(idx) == it
		var line := "%s %dx%d -> slot %-2d  ok=%s on_it=%s bag_before=%d  %s" % [
			id.rpad(16), sz.x, sz.y, idx, str(res.get("ok", false)), str(on), placed,
			str(res.get("reason", ""))]
		if not bool(res.get("ok", false)) or not on:
			bad += 1
			print("  FAIL ", line)
		else:
			print("  OK   ", line)
		# (b) the auto path (a double tap), fresh bag again
		var inv2 = Inv.new()
		inv2.add(it)
		var res2: Dictionary = inv2.equip(it)
		if not bool(res2.get("ok", false)) or inv2.equipped_items().size() != 1:
			bad += 1
			print("        auto-slot path FAILED: ", res2.get("reason", ""))
	print("EQUIP_SLOTS_CLEAN failures=%d" % bad)
	quit()
