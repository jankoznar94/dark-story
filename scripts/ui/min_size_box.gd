extends Container
class_name MinSizeBox
## A wrapper that reports its children's minimum size AND stretches them to its own box.
##
## `StatsPanel`, `SkillsPanel` and `InventoryScreen` all hold their content column as a
## CHILD. Two things were wrong with that:
##
## 1. A plain `Control` reports a minimum of ZERO for its children — measured
##    `plain Control combined=(0.0, 0.0)` against `(30.0, 50.0)` for the same content inside
##    a Container. So the modal's pane reported `min=(0.0, 0.0)`, the dialog's content height
##    (which drives `min-height:85vh`) was computed from nothing, and the whole modal laid
##    out inside a zero-height box. Measured: the pane's rect came out `size=(374, 0)` with
##    1931px of content inside it, for all three panes.
## 2. A bare `Container` reports the minimum but does no layout of its own, so the child
##    column stayed at its MINIMUM width (measured 250px in a 374px pane) instead of
##    filling — a narrow strip with dead space beside it.
##
## `Container._get_minimum_size()` and `Container._notification(NOTIFICATION_SORT_CHILDREN)`
## are both real script virtuals (unlike `Label`'s, which C++ shadows and never calls), so a
## Container subclass is the one shape that can do both. Together they are what the browser's
## `height:auto` + block layout does for free.
##
## Use it as a panel's ROOT when the panel is embedded in the character modal. Only one
## child is expected (the content column); several children would each get the full rect.
func _get_minimum_size() -> Vector2:
	var box := Vector2.ZERO
	for child in get_children():
		if child is Control:
			box = box.max((child as Control).get_combined_minimum_size())
	return box


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for child in get_children():
			if child is Control:
				fit_child_in_rect(child, Rect2(Vector2.ZERO, size))
