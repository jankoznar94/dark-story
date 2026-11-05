extends RefCounted
class_name TownPortal
## TownPortal — ONE place that answers "does the player carry a town-portal scroll?".
##
## The scroll exists in TWO forms in this port, and every screen that offered a portal used to
## read only the first:
##
##   * `state.data.townPortalCount` — the BELT counter, raised by buying a scroll in the shop or
##     by "using" one from the bag (`EquipLogic.equip_consumable`);
##   * an actual `townPortalScroll` entry in the INVENTORY — which is how a scroll that DROPPED
##     arrives (`LootSystem._roll_special`) and how the shop shows it before it is used.
##
## Jan, reporting the missing portal button in a fight: "ani když mám scrolly" — the scrolls were
## in the bag, the counter was 0, and the button therefore never appeared. Reading both is the fix,
## and spending picks the belt first so the counter keeps its old meaning.

const SCROLL_ID := "townPortalScroll"


static func belt_count(state) -> int:
	if state == null:
		return 0
	return int(state.data.get("townPortalCount", 0))


## Is a scroll in the BAG? Entries are either a bare id string or `{id, count}` for a stack.
static func in_bag(state) -> bool:
	if state == null:
		return false
	for entry in state.inventory():
		var eid := str(entry.get("id", "")) if entry is Dictionary else str(entry)
		if eid == SCROLL_ID:
			return true
	return false


static func available(state) -> bool:
	return belt_count(state) > 0 or in_bag(state)


## Spends ONE scroll and says whether it could. The belt counter goes first (that is the number
## the shop and the map already read); only then is a bag entry removed. A refusal changes nothing,
## so a caller that could not pay must not open a portal.
static func spend(state) -> bool:
	if state == null:
		return false
	if belt_count(state) > 0:
		state.data["townPortalCount"] = belt_count(state) - 1
		return true
	if not in_bag(state):
		return false
	state.remove_item(SCROLL_ID)
	return true
