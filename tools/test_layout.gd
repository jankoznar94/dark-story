extends SceneTree

# Test ROZLOZENI: hra musi byt hratelna na kazdem telefone, ne jen vypadat
# dobre. Vystup: LAYOUT_ALL_PASS=true / false
#
# Mrizka ma pevny pocet bunek, takze se do areny VZDY vejde - to je dana
# vec. Co se ale overit da a co se opravdu kazi, je:
#   * ze cesty zustanou v arene a nad hornim panelem,
#   * ze PAS kolem cest (jedina stavebni plocha) je cely v arene a v kazde
#     bunce se da opravdu postavit vez,
#   * ze klepnuti na stred vyhybky opravdu prepne TU vyhybku a ne jinou,
#   * ze klepnuti na stred bunky pasu stavi PRAVE tam.
# Posledni dve jsou meritka HRATELNOSTI: klepnuti se hleda podle vzdalenosti
# k trase a ta zavisi na rozliseni, takze se to na malem displeji muze
# rozbit, i kdyz obrazek vypada stejne.

const RESOLUTIONS := [
	[640, 360],   # nejmensi podporovany
	[800, 360],
	[854, 384],
	[932, 430],   # typicky telefon na sirku
	[960, 540],
	[960, 600],
	[1024, 600],
	[1080, 480],
	[1280, 600],
	[1280, 720],
	[1366, 768],
	[1440, 600],
	[1600, 720],
	[1920, 1080],
]

var fails: Array = []
var checks: int = 0


func _init() -> void:
	for r in RESOLUTIONS:
		_one(r[0], r[1])
	_strokes_scale()
	if fails.is_empty():
		print("LAYOUT_ALL_PASS=true (%d kontrol)" % checks)
		quit(0)
	else:
		for f in fails:
			print("  FAIL: " + str(f))
		print("LAYOUT_ALL_PASS=false (%d kontrol)" % checks)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)


# TLOUSTKA TAHU SE MUSI MENIT S ROZLISENIM. Jan (Oct 2026): "Ať to vypadá
# stejně nehledě na rozlišení."
#
# Displej s dvojnasobnou hustotou dostane dvojnasobne platno, takze PEVNY pocet
# pixelu na tahu je na nem relativne polovicni - hra pak vypadala na velkem
# displeji jinak (hrany, mrizka a obrysy byly tenci, nebot se kreslily porad
# stejnym poctem pixelu). Vsechny tahy se proto berou z `layout.bl()` (deska)
# a `layout.ul()` (pruh, panel, HUD).
func _strokes_scale() -> void:
	var small := ScreenLayout.new()
	small.compute(Vector2(960.0, 600.0))
	var big := ScreenLayout.new()
	big.compute(Vector2(1440.0, 900.0))
	# Dvojnasobny displej = dvojnasobny tah (v pixelech), tedy STEJNA relativni
	# tloušťka. Presna shoda se neda cekat (krok meritka je spojity), ale
	# pomer musi odpovidat pomeru meritka - a ten se bere z rozvrzeni, aby
	# test nezavisle neuhadal, jak jsou meritka definovana.
	var r_s: float = big.bl(2.0) / maxf(small.bl(2.0), 0.001)
	var want_s: float = big.s / small.s
	_check(absf(r_s - want_s) < 0.05,
		"tah desky se meni jinak nez s meritkem (pomer %.2f, ceka se %.2f)" % [r_s, want_s])
	var r_u: float = big.ul(2.0) / maxf(small.ul(2.0), 0.001)
	var want_u: float = big.ui / small.ui
	_check(absf(r_u - want_u) < 0.05,
		"tah UI se meni jinak nez s meritkem (pomer %.2f, ceka se %.2f)" % [r_u, want_u])
	# Male rozliseni nesmi tah ztloustnout na nulu.
	var tiny := ScreenLayout.new()
	tiny.compute(Vector2(640.0, 360.0))
	_check(tiny.bl(2.0) >= 1.0 and tiny.ul(2.0) >= 1.0,
		"tah na malem displeji zmizel (%.2f / %.2f)" % [tiny.bl(2.0), tiny.ul(2.0)])

	# A KRESLENI JE MUSI OPRAVDU POUZIT: kdyby si nekdo napsal do kresleni
	# pevne "2.0", test to shodi - hodnota by se na velkem displeji neměnila.
	# (Hledaji se jen tvary, ktere v kresleni desky a UI opravdu jsou.)
	var src: String = FileAccess.get_file_as_string("res://scripts/game_view.gd")
	_check(src.contains("func bl(") == false, "hlavicka testu se plete s kodem")
	var lay: String = FileAccess.get_file_as_string("res://scripts/screen_layout.gd")
	_check(lay.contains("func bl(") and lay.contains("func ul("),
		"rozvrzeni nema meritko tahu (bl/ul)")
	for bad in ["Level.GRID_MAJOR if major else Level.GRID_LINE, 2.0",
			"Color(0.42, 0.39, 0.33, 0.9), false, 2.0",
			"Color(accent.r, accent.g, accent.b, 0.55), false, 2.0",
			"Color(accent.r, accent.g, accent.b, 0.7), false, 2.0",
			"Color(0.38, 0.35, 0.30), false, 2.0",
			"Color(0.28, 0.25, 0.21), 2.0",
			"Color(0.46, 0.42, 0.35), 2.0",
			"Color(0.62, 0.74, 0.86, 0.80), false, 2.0",
			"Color(0.90, 0.87, 0.80, 0.55), false, 2.0",
			"Color(0.90, 0.87, 0.80, 0.9), 2.0",
			"Color(0.78, 0.62, 0.30), false, 2.0",
			"Color(0.55, 0.25, 0.22), false, 3.0"]:
		_check(not src.contains(bad),
			"v kresleni zustala pevna tloušťka tahu (%s)" % bad)
	_check(src.contains("layout.bl(2.0) if major else layout.bl(1.5)"),
		"mrizka nekresli tahy pres meritko")
	# UROVEN VEZE = TECKY UVNITR VEZE. Hlida se MISTO VOLANI, ne existence
	# funkce: kdyby `_draw_towers` tecky nevolal, vez by uroven nemela vubec
	# a test na existenci funkce by pritom prosel.
	_check(src.contains("_draw_level_dots(p, r, t.level)"),
		"kresleni vezi nevola tecky urovne")
	_check(not src.contains("_teeth_text") and not src.contains("zub"),
		"uroven veze se porad kresli zuby nad vezi")
	# OBCHOD KRESLI TO, CO HRA OPRAVDU POSTAVI: nabidka se bere z mista
	# (`Game.build_choices`), ne z druhu veze. Kdyby si obrazovka skladala
	# popisky sama, mohl by svitit jiny element, nez ktery se postavi.
	_check(src.contains("var choices: Array = game.build_choices()"),
		"obchod si nabidku nebere ze hry")
	_check(not src.contains("Tower.kind_label"),
		"obchod kresli popisky druhu, ne voleb mista")
	# ODCHOD Z EDITORU: klepnuti na "menu" musi opravdu prepnout obrazovku.
	# Hlida se MISTO VOLANI (`is_menu` -> `menu.open_menu()`), ne existence
	# funkce - tlacitko, ktere se nakresli a nic nedela, je presne ta chyba,
	# kterou hrac vidi jako "z editoru se neda vratit do menu".
	_check(src.contains("if editor.is_menu(act):"),
		"pruh editoru nepozná tlacitko menu")
	_check(src.contains("if editor.is_menu(act):\n			menu.open_menu()"),
		"klepnuti na menu v editoru neotevre menu")


# Lezi bod na okraji displeje (areny)? Pouziva se na vstup a cile: poutnici
# maji prichazet z okraje a v cili z nej zase zmizet.
func _on_border(p: Vector2, a: Rect2) -> bool:
	return absf(p.x - a.position.x) < 1.0 or absf(p.x - a.end.x) < 1.0 \
		or absf(p.y - a.position.y) < 1.0 or absf(p.y - a.end.y) < 1.0


func _one(w: int, h: int) -> void:
	var tag: String = "%dx%d" % [w, h]
	var layout := ScreenLayout.new()
	layout.compute(Vector2(float(w), float(h)))
	_check(layout.arena.size.x > 0.0 and layout.arena.size.y > 0.0,
		"%s: arena je prazdna" % tag)
	var g := Game.new()
	g.auto_round = false
	g.setup(layout.arena, layout.s, layout.board_bottom, Level.base())

	# --- mrizka a cesty zustanou v arene. POLE VYPLNUJE ARENU CELOU:
	# zadny okraj po stranach, jinak by hrac prisel o kus displeje a
	# poutnici by se objevovali uprostred, ne na okraji.
	var o: Vector2 = g.net.origin
	var gw: float = g.net.cell_w * float(g.net.level.cols)
	var gh: float = g.net.cell_h * float(g.net.level.rows)
	_check(absf(o.x - layout.arena.position.x) < 1.0,
		"%s: pole nezacina na levem okraji (%.1f vs %.1f)" % [tag, o.x, layout.arena.position.x])
	_check(absf(gw - layout.arena.size.x) < 1.5,
		"%s: pole nevyplnuje sirku displeje (%.1f z %.1f)" % [tag, gw, layout.arena.size.x])
	_check(o.y >= layout.arena.position.y - 1.0, "%s: mrizka zacina nad areny" % tag)
	_check(o.y + gh <= layout.arena.end.y + 1.5, "%s: mrizka pretekla dolu" % tag)
	_check(minf(g.net.cell_w, g.net.cell_h) > 8.0,
		"%s: bunka je jen %.1f x %.1f px" % [tag, g.net.cell_w, g.net.cell_h])
	for lane in range(g.net.lane_count()):
		var path: PackedVector2Array = g.net.lane_path[lane]
		for p in path:
			var v: Vector2 = p
			_check(v.x >= layout.arena.position.x - 1.0 and v.x <= layout.arena.end.x + 1.0,
				"%s: usek %d utíká z areny vodorovne" % [tag, lane])
			_check(v.y >= layout.arena.position.y - 1.0 and v.y <= layout.arena.end.y + 1.0,
				"%s: usek %d utíká z areny svisle" % [tag, lane])

	# --- poutnici PRICHAZEJI Z OKRAJE DISPLEJE a v cili z nej zmizi.
	# Je to videt: prvni bod vstupniho useku lezi na okraji a posledni bod
	# useku, ktery konci v cili, take.
	if g.net.entry_lane >= 0:
		var ep: PackedVector2Array = g.net.lane_path[g.net.entry_lane]
		_check(_on_border(ep[0], layout.arena),
			"%s: poutnici nevstupuji z okraje displeje (%s)" % [tag, str(ep[0])])
	var border_exits: int = 0
	for lane in range(g.net.lane_count()):
		var end_node: int = g.net.lane_end_node(lane)
		if end_node < 0 or g.net.node_kind[end_node] != Level.CIL:
			continue
		var pth: PackedVector2Array = g.net.lane_path[lane]
		_check(_on_border(pth[pth.size() - 1], layout.arena),
			"%s: usek %d do cile nekonci na okraji displeje" % [tag, lane])
		border_exits += 1
	_check(border_exits > 0, "%s: v mape neni zadny cil" % tag)

	# --- PAS KOLEM CEST: jedina stavebni plocha hry. Musi byt cely v arene
	# a v kazde jeho bunce se musi dat postavit vez - jinak by u nekterych
	# cest nebylo kde stavet a hrac by to poznal az v bitve.
	for i in range(g.net.lane_count()):
		if g.level.lane_is_kmen(i):
			continue
		_check(g.net.strip_cells_of_lane(i) > 0,
			"%s: usek %d nema ani jednu bunku pasu" % [tag, i])
	g.gold = 100000
	var built_here: int = 0
	for cellv in g.net.strip_cells:
		var c: Vector2i = cellv
		var p: Vector2 = g.net.cell_center(c)
		_check(p.x >= layout.arena.position.x - 1.0 and p.x <= layout.arena.end.x + 1.0,
			"%s: bunka pasu %s utika z areny vodorovne" % [tag, str(c)])
		_check(p.y >= layout.arena.position.y - 1.0 and p.y <= layout.arena.end.y + 1.0,
			"%s: bunka pasu %s utika z areny svisle" % [tag, str(c)])
		# BUNKA POD STREDEM PASU JE PRESNE TA BUNKA. Kdyby se rozslo
		# pocitani stredu a prevod bodu na bunku, hrac by klepal na vez
		# a stavěl by o bunku vedle.
		_check(g.net.cell_at(p) == c, "%s: stred bunky pasu %s padl do %s" % [
			tag, str(c), str(g.net.cell_at(p))])
		# KLEPNUTI NA STAVEBNI BUNKU NESMI UKRAST UZEL: u vyhybky musi byt
		# jedno policko volne, aby se hrac na prepnuti vyhybky vzdy trefil.
		var j: int = g.net.junction_tap_at(p, maxf(16.0, 34.0 * layout.s))
		_check(j < 0, "%s: klepnuti na bunku pasu %s chyti vyhybku %d" % [tag, str(c), j])
		if g.try_build(c):
			built_here += 1
	_check(built_here > 0, "%s: v pasu se nepostavila ani jedna vez" % tag)

	# --- hratelnost: klepnuti na uzel vyhybky prepne TU vyhybku
	for j in range(g.net.junction_count()):
		var node: int = int(g.net.junction_nodes[j])
		var p: Vector2 = g.net.node_world(node)
		var hit: int = g.net.junction_tap_at(p, maxf(16.0, 34.0 * layout.s))
		_check(hit == j, "%s: klepnuti na vyhybku %d vybralo vyhybku %d" % [tag, j, hit])
		if hit == j:
			# a posun na dalsi vetev opravdu zmeni, kam vyhybka posila
			var before: int = g.selected_lane(j)
			g.cycle_switch(j)
			var after: int = g.selected_lane(j)
			_check(before != after, "%s: posun vyhybkou %d nezmenil vetev" % [tag, j])

	# --- hratelnost: klepnuti na STAVEBBNI BUNKU stavi vez. Hra hleda nejdriv
	# uzel, pak bunku pasu, takze stred kazde bunky pasu musi opravdu byt
	# ta bunka (a ne treba cesta vedle).
	var g2 := Game.new()
	g2.auto_round = false
	g2.setup(layout.arena, layout.s, layout.board_bottom, Level.base())
	g2.gold = 100000
	for cellv in g2.net.strip_cells:
		var c: Vector2i = cellv
		var hit: Vector2i = g2.net.cell_at(g2.net.cell_center(c))
		_check(hit == c and g2.net.strip_has(hit),
			"%s: klepnuti na bunku pasu %s vybralo %s" % [tag, str(c), str(hit)])
		_check(g2.try_build(hit), "%s: v bunce pasu %s nejde postavit vez" % [tag, str(c)])
	# a klepnuti na CESTU stavi? Ne - prepina vyhybku. Stred useku, ktery vede
	# z vyhybky, proto nesmi lezet v pasu (jinak by se na nej stavělo).
	for j in range(g2.net.junction_count()):
		for k in range(g2.net.junction_lanes[j].size()):
			var lane: int = g2.net.junction_lane(j, k)
			var mid: Vector2 = g2.net.point_at(lane, float(g2.net.lane_len[lane]) * 0.5)
			_check(not g2.net.strip_has(g2.net.cell_at(mid)),
				"%s: stred useku %d lezi v pasu - klepnuti by stavělo místo prepnuti" % [tag, lane])

	# --- PANEL VYBRANE VEZE: tlacitka musi byt na displeji, nad dotykovym
	# minimem a NESMI zakryt vez, kterou hrac vybral - jinak by nevidel, co
	# vlastne vylepsuje. Zkousi se OBE strany: vez v horni i v dolni polovine,
	# protoze panel se kresli na protilehlou stranu.
	for want_top in [true, false]:
		var tcell := Vector2i(-1, -1)
		for cellv in g2.net.strip_cells:
			var cc: Vector2i = cellv
			if (cc.y < g2.net.level.rows / 2) == want_top and g2.tower_at(cc) != null:
				tcell = cc
				break
		if tcell.x < 0:
			continue
		var ctr: Vector2 = g2.net.cell_center(tcell)
		layout.tower_panel(ctr)
		for r in [layout.tower_bar, layout.tower_up, layout.tower_sell]:
			_check(r.position.x >= -0.6 and r.end.x <= float(w) + 0.6,
				"%s: panel veze utika vodorovne (%.1f..%.1f)" % [tag, r.position.x, r.end.x])
			_check(r.position.y >= -0.6 and r.end.y <= float(h) + 0.6,
				"%s: panel veze utika svisle (%.1f..%.1f)" % [tag, r.position.y, r.end.y])
		var touch: float = ScreenLayout.MIN_TOUCH * layout.ui
		_check(layout.tower_up.size.y >= touch - 0.6,
			"%s: tlacitko vylepseni je nizke %.1f px (min %.1f)" % [
				tag, layout.tower_up.size.y, touch])
		_check(layout.tower_sell.size.x >= touch - 0.6,
			"%s: tlacitko prodeje je uzke %.1f px (min %.1f)" % [
				tag, layout.tower_sell.size.x, touch])
		_check(not layout.tower_up.intersects(layout.tower_sell),
			"%s: tlacitka vylepseni a prodeje se prekryvaji" % tag)
		# PANEL NESMI ZAKRYT VYBRANOU VEZ
		var crect := Rect2(ctr - Vector2(g2.net.cell_w, g2.net.cell_h) * 0.5,
			Vector2(g2.net.cell_w, g2.net.cell_h))
		_check(not layout.tower_bar.intersects(crect),
			"%s: panel zakryva vybranou vez na %s" % [tag, str(tcell)])
		# a lezi opravdu na protilehle strane, nez vez stoji
		var panel_below: bool = layout.tower_bar.position.y > float(h) * 0.5
		_check(panel_below == want_top,
			"%s: panel je na stejne strane jako vez (nahore=%s, vez nahore=%s)" % [
				tag, not panel_below, want_top])

	# --- OBCHOD S VEZEMI: dokud stoji jen v nabidce, musi byt kazde tlacitko
	# na displeji, nad dotykovym minimem a nesmi se prekryvat s "Postavit".
	# Zkousi se prvni DRUH, ktery se do obchodu vejde, protoze sirka tlacitek
	# druhu se deli jejich poctem - s vice druhy je to horsi pripad.
	for want_top2 in [true, false]:
		var bcell := Vector2i(-1, -1)
		for cellv in g2.net.strip_cells:
			var bc: Vector2i = cellv
			if (bc.y < g2.net.level.rows / 2) == want_top2:
				bcell = bc
				break
		if bcell.x < 0:
			continue
		var bctr: Vector2 = g2.net.cell_center(bcell)
		# NEJHORSI PRIPAD: elementarni cesta nabizi dve volby (zivel cesty
		# a neutralni vez), takze se deli sirka mezi dve tlacitka.
		layout.build_panel(bctr, 2)
		var touch2: float = ScreenLayout.MIN_TOUCH * layout.ui
		_check(layout.build_choices.size() == 2,
			"%s: obchod rozvrhl %d tlacitek volby, ma mit 2" % [tag, layout.build_choices.size()])
		for r2 in [layout.build_bar, layout.build_ok, layout.build_cancel]:
			_check(r2.position.x >= -0.6 and r2.end.x <= float(w) + 0.6,
				"%s: obchod utika vodorovne (%.1f..%.1f)" % [tag, r2.position.x, r2.end.x])
			_check(r2.position.y >= -0.6 and r2.end.y <= float(h) + 0.6,
				"%s: obchod utika svisle (%.1f..%.1f)" % [tag, r2.position.y, r2.end.y])
		_check(layout.build_ok.size.y >= touch2 - 0.6,
			"%s: tlacitko Postavit je nizke %.1f px (min %.1f)" % [
				tag, layout.build_ok.size.y, touch2])
		_check(not layout.build_ok.intersects(layout.build_cancel),
			"%s: tlacitka Postavit a Zrusit se prekryvaji" % tag)
		for kr in layout.build_choices:
			var krr: Rect2 = kr
			_check(krr.size.y >= touch2 - 0.6 and krr.size.x >= touch2 - 0.6,
				"%s: tlacitko volby veze je male (%.1f x %.1f, min %.1f)" % [
					tag, krr.size.x, krr.size.y, touch2])
			_check(krr.end.x <= layout.build_cancel.position.x + 0.6,
				"%s: tlacitka volby lezou do tlacitek Postavit/Zrusit" % tag)
		# OBCHOD NESMI ZAKRYT OZNACENE MISTO - hrac musi videt, kam stavi
		var brect := Rect2(bctr - Vector2(g2.net.cell_w, g2.net.cell_h) * 0.5,
			Vector2(g2.net.cell_w, g2.net.cell_h))
		_check(not layout.build_bar.intersects(brect),
			"%s: obchod zakryva oznacene stavebni misto na %s" % [tag, str(bcell)])
		var bar_below: bool = layout.build_bar.position.y > float(h) * 0.5
		_check(bar_below == want_top2,
			"%s: obchod je na stejne strane jako misto (nahore=%s, misto nahore=%s)" % [
				tag, not bar_below, want_top2])

	# --- NASTAVENI: obrazovka se rozsirila o radek ROZLIŠENÍ, takze se na
	# malem displeji musi vejit tri prepinace + ZPET, kazdy nad dotykovym
	# minimem a bez prekryvu. Klepnuti na radek musi sedet na obrazek.
	var sbtns: Array = layout.all_settings_buttons()
	_check(sbtns.size() == ScreenLayout.SETTINGS_ROWS + 1,
		"%s: nastaveni ma %d dotykovych cilu, ceka se %d" % [
			tag, sbtns.size(), ScreenLayout.SETTINGS_ROWS + 1])
	for si in range(sbtns.size()):
		var sr: Rect2 = sbtns[si]
		_check(sr.position.x >= -0.6 and sr.end.x <= float(w) + 0.6,
			"%s: cíl nastaveni %d utika vodorovne (%.1f..%.1f)" % [tag, si, sr.position.x, sr.end.x])
		_check(sr.position.y >= -0.6 and sr.end.y <= float(h) + 0.6,
			"%s: cíl nastaveni %d utika svisle (%.1f..%.1f)" % [tag, si, sr.position.y, sr.end.y])
		_check(sr.size.y >= ScreenLayout.MIN_TOUCH * layout.ui - 0.6,
			"%s: cíl nastaveni %d je nizky %.1f px" % [tag, si, sr.size.y])
		for sj in range(si + 1, sbtns.size()):
			var sr2: Rect2 = sbtns[sj]
			_check(not sr.intersects(sr2),
				"%s: cile nastaveni %d a %d se prekryvaji" % [tag, si, sj])

	# --- OBSAH RADKU NASTAVENI: popisek, hodnota a zaskrtravatko musi byt
	# UVNITR radku a hodnota se NESMI dotykat zaskrtravatka. Presne tady se
	# to rozbilo: hodnota se zarovnavala k pravemu okraji radku a text se
	# lepil na ramecek zaskrtavatka. Test se pta rozvrzeni, ne kresleni.
	for si in range(ScreenLayout.SETTINGS_ROWS):
		var rowr: Rect2 = layout.settings_row(si)
		var chk: Rect2 = layout.settings_check(si)
		var valb: Rect2 = layout.settings_value_box(si)
		var labb: Rect2 = layout.settings_label_box(si)
		_check(rowr.encloses(chk), "%s: zaskrtravatko radku %d leze z radku" % [tag, si])
		_check(rowr.encloses(labb), "%s: popisek radku %d leze z radku" % [tag, si])
		_check(valb.position.x >= labb.end.x - 0.6,
			"%s: hodnota radku %d zacina pred koncem popisku" % [tag, si])
		var gap_px: float = chk.position.x - valb.end.x
		_check(gap_px >= ScreenLayout.SET_GAP * layout.ui - 0.6,
			"%s: hodnota radku %d se dotyka zaskrtravatka (mezera %.1f px, ma byt %.1f)" % [
				tag, si, gap_px, ScreenLayout.SET_GAP * layout.ui])
		_check(chk.end.x <= rowr.end.x - ScreenLayout.SET_PAD * layout.ui + 0.6,
			"%s: zaskrtravatko radku %d je nalepene na okraji radku" % [tag, si])
