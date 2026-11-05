extends RefCounted
class_name ZoneMemory
## ZoneMemory — the walked state of a zone, kept so a waypoint trip or a town portal does NOT
## re-roll the dungeon (Jan: "zóny by se neresetovaly při každém odchodu do města. Při smrti
## ano, ale při použití waypointu a town scroll portálu ne").
##
## ⚠️  THIS LIVES IN MEMORY ONLY, AND THAT IS THE FEATURE. `state.data` is written to the save
## (localStorage / the APK's file), so a snapshot put there would survive a restart. Jan's rule
## is the opposite: the "sleep" (quitting and re-opening the game, Diablo's new game) refreshes
## EVERY monster, and the only other reset is DEATH. A process-local store gives both for free —
## closing the game drops it — so do not "fix" this by moving it onto the save.
##
## The layout itself needs no copy: `ActRun.zone_seed()` already rebuilds the same corridor and
## the same pack positions for an act+zone. What cannot be recomputed is what the PLAYER did to
## it: which packs are awake, which are dead, where each living monster stands and how hurt it
## is, and how much of the fog he has lifted.
##
## Keyed by `act:zone`, so two acts (or two zones of one act) never share a snapshot.

static var _zones: Dictionary = {}


static func key(act_id: int, zone: int) -> String:
	return "%d:%d" % [int(act_id), int(zone)]


static func has(act_id: int, zone: int) -> bool:
	return _zones.has(key(act_id, zone))


## The stored snapshot, or `{}`. Never removes it: entering the same zone twice (a second town
## trip) must restore the same world again, not the one from before the first trip.
static func peek(act_id: int, zone: int) -> Dictionary:
	var snap: Variant = _zones.get(key(act_id, zone))
	if snap is Dictionary:
		return snap
	return {}


static func store(act_id: int, zone: int, snap: Dictionary) -> void:
	if snap.is_empty():
		return
	_zones[key(act_id, zone)] = snap


## The player DIED in `act_id`: Diablo's rule is that the whole act's world is rolled again, so
## every zone of that act forgets what it looked like. Zones of other acts are untouched.
static func clear_act(act_id: int) -> void:
	var prefix := "%d:" % int(act_id)
	for k in _zones.keys():
		if str(k).begins_with(prefix):
			_zones.erase(k)


## Death resets the world the player was in. Kept as one call so the caller does not have to
## know whether that means one act or all of them.
static func clear_all() -> void:
	_zones.clear()


static func count() -> int:
	return _zones.size()


## Test hook: a SceneTree suite runs several scenarios in one process, and a leftover snapshot
## from the previous case would make the next one pass for the wrong reason.
static func reset() -> void:
	_zones.clear()
