extends SceneTree

# ROZVRZENI PRO SONDU. Vypise presna streda tlacitek, ktera hra opravdu kresli,
# jako JSON. Sonda v prohlizeci, ktera si vzorce prepisuje sama, se rozejde
# s hrou pri kazde zmene rozvrzeni - a pak "meri neco jineho" (presne to se
# stalo u panelu s upgrady: klepnuti minulo a snimek ukazoval menu).
#
# Pouziti:
#   godot4 --headless --path . --script res://tools/layout_dump.gd -- 390 844 4
#                                        sirka vyska [pocet barev v palete]
#
# Vystup: jeden radek `LAYOUT_JSON={...}`.

const DEF_W := 390.0
const DEF_H := 844.0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var w: float = DEF_W
	var h: float = DEF_H
	var pal: int = 4
	if args.size() > 0:
		w = float(args[0])
	if args.size() > 1:
		h = float(args[1])
	if args.size() > 2:
		pal = int(args[2])

	var lay := ScreenLayout.new()
	lay.update(Vector2(w, h))

	# Pocet bunek v panelu v bitve odpovida kategorii "utok" (prvni tab).
	var shop_cells: int = Upgrades.stats_in(Upgrades.CAT_OFF).size()
	lay.set_shop_shape(3, maxi(1, shop_cells))
	lay.set_upg_shape(maxi(1, shop_cells))
	lay.layout_palette(pal)

	var out: Dictionary = {
		"view": [w, h],
		"bar_h": lay.bar_h,
		"pal_h": lay.pal_h,
		"center": _p(lay.center),
		"unit_r": lay.unit_r,
		"field_r": lay.field_r,
		"tower_r": lay.tower_r,
		"menu": _centers(lay.menu_rects),
		"menu_rects": _rects(lay.menu_rects),
		"pal": _centers(lay.pal_rects),
		"pal_rects": _rects(lay.pal_rects),
		"pal_top": lay.pal_top,
		"hud_menu": _p(lay.hud_menu.get_center()),
		"upg_panel": _r(lay.upg_panel),
		"upg_tabs": _centers(lay.upg_tabs),
		"upg_tab_rects": _rects(lay.upg_tabs),
		"upg_tab_icons": _rects(lay.upg_tab_icons),
		"upg_cells": _rects(lay.upg_cells),
		"upg_back": _p(lay.upg_back.get_center()),
		"upg_title_y": lay.upg_note_y,
		"shop_panel": _r(lay.shop_panel),
		"shop_tabs": _centers(lay.shop_tabs),
		"shop_tab_rects": _rects(lay.shop_tabs),
		"shop_tab_icons": _rects(lay.shop_tab_icons),
		"shop_cells": _rects(lay.shop_cells),
		"shop_cats": Upgrades.CATEGORIES,
		"shop_row_labels": _labels(Upgrades.stats_in(Upgrades.CAT_OFF)),
		"perm_labels": _labels(Upgrades.stats_in(Upgrades.CAT_OFF)),
	}
	print("LAYOUT_JSON=" + JSON.stringify(out))
	quit()


func _labels(stats: Array) -> Array:
	var out: Array = []
	for s in stats:
		out.append(String(s["label"]))
	return out


func _p(v: Vector2) -> Array:
	return [v.x, v.y]


func _r(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _rects(list: Array) -> Array:
	var out: Array = []
	for r in list:
		out.append(_r(r))
	return out


func _centers(list: Array) -> Array:
	var out: Array = []
	for r in list:
		out.append(_p(r.get_center()))
	return out
