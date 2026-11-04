extends RefCounted
class_name ActRun
## ActRun — one act as a CHAIN of real zones, with waypoints as checkpoints.
##
## Replaces the old "one stop = one run, back to the road between fights" model (Jan: "Každá
## oblast v mapě v rámci aktu by měla mít svoji reálnou zónu ve hře. Úplně tím nahradíme
## mapový systém. Jednotlivé oblasti aktu budou použity jako waypointy").
##
## The state lives on the save under `actRuns[act_id]`, so a death or a walk to town resumes
## at the last unlocked waypoint instead of restarting the act:
##
##   { "seed": 918273, "zone": 3, "waypoints": [0,1,2,3], "cleared": [0,1,2] }
##
## `seed` is ONE per act: every zone's layout is `zone_seed(zone)` off it, so an act is
## reproducible and a reloaded save walks the same dungeon.

const KEY := "actRuns"


static func _runs(state) -> Dictionary:
	var data: Dictionary = state.data
	if not data.has(KEY) or not (data[KEY] is Dictionary):
		data[KEY] = {}
	return data[KEY]


## The act's record, created on first entry. `total` comes from the act table so a new act
## with a different zone count needs no migration.
static func get_run(state, act_id: int, total: int) -> Dictionary:
	var runs := _runs(state)
	var key := str(act_id)
	if not runs.has(key) or not (runs[key] is Dictionary):
		var fresh := {
			"seed": randi(),
			"zone": 0,
			"waypoints": [0],
			"cleared": [],
			"total": total,
		}
		runs[key] = fresh
		state.data[KEY] = runs
		return fresh
	var entry: Dictionary = runs[key]
	# A save written before this feature has no fields; fill them in place.
	if not entry.has("seed"):
		entry["seed"] = randi()
	if not entry.has("zone"):
		entry["zone"] = 0
	if not entry.has("waypoints"):
		entry["waypoints"] = [int(entry.get("zone", 0))]
	if not entry.has("cleared"):
		entry["cleared"] = []
	entry["total"] = total
	# ⚠️  THE SAVE IS JSON: every int comes back as a FLOAT, and `Array.has(2)` does not see
	# `2.0` — so entering a zone twice appended a second copy of the same waypoint and
	# `last_waypoint()` then returned the highest STALE entry (measured: last=9 while the act
	# really stood in zone 3). Normalise and de-duplicate on every read: ints only, one entry
	# per zone, order preserved.
	entry["zone"] = int(entry.get("zone", 0))
	entry["waypoints"] = _int_set(entry.get("waypoints", []))
	entry["cleared"] = _int_set(entry.get("cleared", []))
	return entry


## A de-duplicated, int-typed copy of a zone list. Godot does not coerce 2 and 2.0 inside
## `Array.has`, which is what produced duplicate waypoints after a JSON round trip.
static func _int_set(values: Variant) -> Array:
	var out: Array = []
	var seen := {}
	if values is Array:
		for v in values:
			var z := int(v)
			if seen.has(z):
				continue
			seen[z] = true
			out.append(z)
	return out


static func zone_seed(entry: Dictionary, zone: int) -> int:
	return int(entry.get("seed", 1)) * 131 + int(zone)


static func current_zone(state, act_id: int, total: int) -> int:
	return clampi(int(get_run(state, act_id, total).get("zone", 0)), 0, maxi(total - 1, 0))


## Entering a zone (from the map, a waypoint, or an exit) always unlocks its waypoint — the
## checkpoint is where you ARRIVED, not something you have to find.
static func enter_zone(state, act_id: int, zone: int, total: int) -> Dictionary:
	var entry := get_run(state, act_id, total)
	entry["zone"] = clampi(zone, 0, maxi(total - 1, 0))
	var wps: Array = entry["waypoints"]
	if not wps.has(int(entry["zone"])):
		wps.append(int(entry["zone"]))
	entry["waypoints"] = _int_set(wps)
	return entry


## Walking out of a zone's exit: mark it cleared and step one deeper. Returns the NEXT zone,
## or -1 when this was the act's last zone (the boss zone), which ends the act.
static func clear_zone(state, act_id: int, zone: int, total: int) -> int:
	var entry := get_run(state, act_id, total)
	var cleared: Array = entry["cleared"]
	if not cleared.has(int(zone)):
		cleared.append(int(zone))
	entry["cleared"] = _int_set(cleared)
	var nxt := int(zone) + 1
	if nxt >= total:
		return -1
	enter_zone(state, act_id, nxt, total)
	return nxt


static func waypoints(state, act_id: int, total: int) -> Array:
	return (get_run(state, act_id, total).get("waypoints", []) as Array).duplicate()


static func is_unlocked(state, act_id: int, zone: int, total: int) -> bool:
	return waypoints(state, act_id, total).has(int(zone))


## The checkpoint a death or a town trip resumes at: the zone the player was IN. It is NOT
## `max(waypoints)` — the map lets him step into a far unlocked area, and the highest waypoint
## he ever touched is then not where he wants to continue (measured: entering zone 9 once made
## every later death resume at 9).
static func last_waypoint(state, act_id: int, total: int) -> int:
	return current_zone(state, act_id, total)
