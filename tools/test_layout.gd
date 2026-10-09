extends SceneTree

# ROZVRZENI NA RŮZNÝCH DISPLEJÍCH. Tohle je jadro zadani "nativne na sirku":
# hra se musi sama slozit na kazdem telefonu, ne jen na tom vyvojovem.
# Prochazi se realna rozliveni vcetne landscape telefonu, kde je POMER
# STRAN jiny nez u 960x600 - prave tam se rozvrzeni lame nejdriv.
#
# U kazdeho rozliseni se kontroluje:
#   * vsechny dotykove cile jsou CELE na obrazovce a neprekryvaji se
#   * tlacitko ma dotykovou velikost pro prst (>= 44 px)
#   * mista na bonusy jsou v herni plose, neprekryvaji se mezi pruhy
#     a nelezi v ovladacim pruhu
#   * HERNI DESKA NENESE ZADNY TEXT - vsechno vysvetleni je v menu
#   * NAVOD SE VEJDE CELY DO OBRAZOVKY MENU, i s tabulkou poskozeni
#   * hra na tom rozliseni PORAD FUNGUJE: klepnuti na usek vybere prave
#     ten usek a nepritel na protikladnem useku tam opravdu umre
#
# Vystup: LAYOUT_ALL_PASS=true / false

const REAL_SCREENS := [
	[2560, 1080, "21:9 velky"],
	[2160, 1080, "velky siroky telefon"],
	[1920, 1080, "FullHD"],
	[1366, 768, "notebook"],
	[1280, 720, "tablet 16:9"],
	[1024, 768, "iPad 4:3"],
	[960, 600, "zakladni navrh"],
	[932, 430, "iPhone 15 Pro Max na sirku"],
	[854, 480, "starsi telefon 16:9"],
	[844, 390, "iPhone 12/13/14 na sirku"],
	[800, 480, "maly tablet 5:3"],
	[780, 360, "maly telefon 19.5:9"],
	[740, 360, "velmi siroky telefon"],
	[640, 360, "nejmensi podporovany"],
]

const MIN_TOUCH := 44.0

var fails: Array = []
var checks: int = 0


func _init() -> void:
	print("--- rozvrzeni na %d rozlisenich ---" % REAL_SCREENS.size())
	var font: Font = ThemeDB.fallback_font
	_test_board_has_no_text(font)
	for spec in REAL_SCREENS:
		var w: float = float(spec[0])
		var h: float = float(spec[1])
		var name: String = str(spec[2])
		var info: String = _check_screen(w, h, name, font)
		print(info)
	print("checks=%d fails=%d" % [checks, fails.size()])
	for f in fails:
		print("FAIL: " + str(f))
	if fails.is_empty():
		print("LAYOUT_ALL_PASS=true")
	else:
		print("LAYOUT_ALL_PASS=false")
	quit()


func _ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails.append(what)


# STRAZCE BEZ TEXTU. Janovo zadani je, ze z herni desky zmizi VSECHEN text -
# popisek vyhybky, vystupu i kmene. Kdyby se nejaky vratil, poznalo by se to
# jen okem na telefonu; tenhle test to vi z kodu. Cte se ZDROJAK, protoze
# z hotove kresby se text zpetne neprecte.
func _test_board_has_no_text(font: Font) -> void:
	var path: String = "res://scripts/game_view.gd"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	_ok(f != null, "herni scena jde precist (%s)" % path)
	if f == null:
		return
	var src: String = f.get_as_text()
	f.close()
	# Vsechno od pozadi po HUD je DESKA. HUD je jedina cast, ktera smi
	# mit text - je mimo herni plochu.
	var a: int = src.find("func _draw_background")
	var b: int = src.find("func _draw_hud")
	_ok(a >= 0 and b > a, "v herni scene jde najit cast s deskou")
	if a < 0 or b <= a:
		return
	var board: String = src.substr(a, b - a)
	_ok(not board.contains("_label("), "herni deska neobsahuje zadny popisek (_label)")
	_ok(not board.contains("draw_string"), "herni deska nekresli zadny text")
	# A slova, ktera drive v desce byla, uz nikde ve hre nejsou.
	var scripts := ["res://scripts/game_view.gd", "res://scripts/network.gd"]
	for p in scripts:
		var sf: FileAccess = FileAccess.open(p, FileAccess.READ)
		if sf == null:
			continue
		var text: String = sf.get_as_text()
		sf.close()
		for gone in ["výhybka —", "neutrální kmen", "dmg × 1.0", "dmg × %.1f"]:
			_ok(not text.contains(gone),
				"%s: popisek \"%s\" se do desky vratil" % [p, gone])
	# Navod musi byt v menu - jinak by zmizel i s popisky.
	var mf: FileAccess = FileAccess.open("res://scripts/game_view.gd", FileAccess.READ)
	var view_src: String = mf.get_as_text() if mf != null else ""
	if mf != null:
		mf.close()
	_ok(view_src.contains("menu.open_guide()"), "menu otevira NAVOD")
	_ok(view_src.contains("_draw_guide"), "NAVOD se kresli")
	_ok(view_src.contains("_draw_pair_row"), "NAVOD kresli dvojice run (ne jen barvu)")


func _check_screen(w: float, h: float, name: String, font: Font) -> String:
	var lay := ScreenLayout.new()
	lay.compute(Vector2(w, h))

	var min_touch: float = 9999.0
	var min_cross: float = 9999.0
	var guide_px: int = -1
	var guide_lines := 0
	var guide_words := 0

	# --- dotykove cile ---
	var btns: Array = lay.all_buttons()
	for i in range(btns.size()):
		var r: Rect2 = btns[i]
		_ok(r.position.x >= -0.5 and r.position.y >= -0.5,
			"%s: prvek %d nezacina mimo obrazovku (%s)" % [name, i, r])
		_ok(r.end.x <= w + 0.5 and r.end.y <= h + 0.5,
			"%s: prvek %d nekonci mimo obrazovku (%s)" % [name, i, r])
		min_touch = minf(min_touch, minf(r.size.x, r.size.y))
		for j in range(i + 1, btns.size()):
			var r2: Rect2 = btns[j]
			_ok(not r.intersects(r2), "%s: prvky %d a %d se prekryvaji" % [name, i, j])
	_ok(min_touch >= MIN_TOUCH - 0.01,
		"%s: nejmensi dotykovy cil ma %.1f px (min %d)" % [name, min_touch, int(MIN_TOUCH)])
	# a SKIP musi byt nad pruhem, ne v nem utopeny
	_ok(lay.skip_rect.position.y >= lay.bar_y,
		"%s: SKIP zacina v pruhu (%.0f vs %.0f)" % [name, lay.skip_rect.position.y, lay.bar_y])

	# --- NAVOD SE MUSI VEJIT CELY ---
	# Navod je jedina informace o pravidlech hry. Drive bydlel v pruhu
	# a musel se do nej vejit vodorovne; ted je v obrazovce MENU, takze se
	# kontroluje, ze se cely vejde do VYSKY obrazovky a neztrati slovo.
	var guide_left: float = 22.0 * lay.ui
	var guide_w: float = w - guide_left * 2.0
	var guide_top: float = 30.0 * lay.ui
	var guide_h: float = lay.bar_y - guide_top - 6.0 * lay.ui
	guide_px = Guide.fit_px(font, guide_w, guide_h)
	_ok(guide_px > 0,
		"%s: navod se nevejde do obrazovky ani pri 9 px (k dispozici %.0f px)" % [name, guide_h])
	var lines: Array = Guide.lay_out(font, maxi(guide_px, Guide.MIN_PX), guide_w)
	guide_lines = lines.size()
	guide_words = Guide.word_count(lines)
	_ok(guide_words == Guide.source_word_count(),
		"%s: zalamovani navodu ztratilo slova (%d z %d)" % [name, guide_words, Guide.source_word_count()])

	# --- MENU A NASTAVENI ---
	# Menu je prvni obrazovka, takze jeho tlacitka musi byt stisknutelna
	# prstem na kazdem displeji - jinak se hrac ke hre vubec nedostane.
	# A NAVOD je mezi nimi, takze musi byt v seznamu taky.
	_ok(lay.all_menu_buttons().size() == 4, "%s: menu ma ctyři tlacitka (vcetne navodu)" % name)
	for k in range(2):
		var mb: Array = lay.all_menu_buttons() if k == 0 else lay.all_settings_buttons()
		var tag: String = "menu" if k == 0 else "nastaveni"
		for i in range(mb.size()):
			var r: Rect2 = mb[i]
			_ok(r.position.x >= -0.5 and r.position.y >= -0.5,
				"%s: %s prvek %d nezacina mimo obrazovku (%s)" % [name, tag, i, r])
			_ok(r.end.x <= w + 0.5 and r.end.y <= h + 0.5,
				"%s: %s prvek %d nekonci mimo obrazovku (%s)" % [name, tag, i, r])
			_ok(minf(r.size.x, r.size.y) >= MIN_TOUCH - 0.01,
				"%s: %s prvek %d je moc maly (%.1f)" % [name, tag, i, minf(r.size.x, r.size.y)])
			for j in range(i + 1, mb.size()):
				var r2: Rect2 = mb[j]
				_ok(not r.intersects(r2),
					"%s: %s prvky %d a %d se prekryvaji" % [name, tag, i, j])

	# ZPET v navodu musi byt nad pruhem a mimo text.
	_ok(lay.guide_back.position.y >= lay.bar_y,
		"%s: ZPET v navodu zacina v pruhu (%.0f vs %.0f)" % [name, lay.guide_back.position.y, lay.bar_y])
	_ok(lay.guide_back.position.y - (guide_top + 52.0 * lay.ui) >= guide_h * 0.6,
		"%s: navod si nebere cely prostor nad ZPET" % name)

	# --- herni plocha a sit ---
	var g := Game.new()
	g.setup(lay.arena, lay.s, lay.bar_y)
	g.rebuild_network(lay.arena, lay.s, lay.bar_y)

	_ok(lay.arena.size.x > 200.0 and lay.arena.size.y > 80.0,
		"%s: herni plocha neni degenerovana (%s)" % [name, lay.arena])
	_ok(lay.arena.size.x > lay.arena.size.y,
		"%s: hra je na sirku, plocha je sirsi nez vyssi (%.0fx%.0f)" % [name,
			lay.arena.size.x, lay.arena.size.y])

	for lane in range(Network.LANES):
		for slot in range(g.net.slot_count()):
			var p: Vector2 = g.net.slot_world(lane, slot)
			_ok(lay.arena.grow(g.net.bonus_r).has_point(p),
				"%s: misto %d/%d lezi v plose (%s)" % [name, lane, slot, p])
			var slot_rect := Rect2(p - Vector2(g.net.bonus_r, g.net.bonus_r),
				Vector2(g.net.bonus_r * 2.0, g.net.bonus_r * 2.0))
			_ok(not lay.overlaps_with(slot_rect),
				"%s: misto %d/%d se dotyka tlacitka" % [name, lane, slot])
		var path: PackedVector2Array = g.net.lane_path[lane]
		for k in range(path.size()):
			_ok(path[k].y < lay.bar_y, "%s: bod useku %d je v ovladacim pruhu" % [name, lane])
		var last: Vector2 = g.net.point_at(lane, g.net.lane_len[lane])
		_ok(last.distance_to(g.net.exit_pos[g.net.lane_exit[lane]]) < 1.0,
			"%s: usek %d nekonci ve svem vystupu" % [name, lane])
		# DMG ZONA musi zustat nad pruhem - jinak by kreslila do ovladani
		_ok(g.net.rows[lane] < lay.bar_y - 20.0 * lay.s,
			"%s: dmg zona %d leze k pruhu (y=%.0f)" % [name, lane, g.net.rows[lane]])

	# VSECHNY prvky desky musi zustat nad pruhem. Deska je bez textu, takze
	# se kontroluje geometrie: useky, vystupy, mista na bonusy i rucky.
	for lane in range(Network.LANES):
		var ex: int = g.net.lane_exit[lane]
		var ep: Vector2 = g.net.exit_pos[ex]
		_ok(ep.y + g.net.exit_r <= lay.bar_y,
			"%s: vystup %d leze do pruhu (%.0f + %.0f)" % [name, ex, ep.y, g.net.exit_r])
	_ok(g.net.exit_pos[0].x + g.net.exit_r <= w + 0.5,
		"%s: vystupy nekonci mimo obrazovku" % name)

	min_cross = g.net.min_cross_lane_slot_distance()
	_ok(min_cross > g.net.bonus_r * 2.0,
		"%s: bonusy na sousednich pruzich se prekryvaji (mezera %.1f, potreba %.1f)" % [
			name, min_cross, g.net.bonus_r * 2.0])

	# --- a hra na tom rozliseni musi porad fungovat ---
	# Klepnuti na usek je jedina interakce, kterou hrac prepina vyhybku.
	for lane in range(Network.LANES):
		var tap: Vector2 = g.net.point_at(lane, g.net.lane_len[lane] * 0.7)
		var hit: int = g.net.lane_tap_at(tap, maxf(10.0, 16.0 * lay.s))
		_ok(hit == lane, "%s: klepnuti na usek %d ho vybere (hit=%d)" % [name, lane, hit])
	# Kazdy zivel umre na sve protikladne useku, kdyz je usek vystrojen -
	# a to i na tomhle rozliseni. Geometrie nesmi prestat davat smysl jen
	# proto, ze se zmenil pomer stran. (Samotna cesta poutnika jen ZRANI;
	# zabiti je odmena za investici, proto se jeden bonus staví.)
	var target_el: int = Element.opposite_of(Element.FIRE)
	var kill_lane: int = -1
	for lane in range(Network.LANES):
		if Network.lane_element(lane) == target_el:
			kill_lane = lane
	_ok(kill_lane >= 0, "%s: usek pro %s existuje" % [name, Element.name_of(target_el)])
	g.auto_wave = false
	g.gold = 999
	g.try_build(kill_lane, 0, Network.lane_element(kill_lane))
	g.set_switch(kill_lane)
	var e: Enemy = g.debug_spawn(Element.FIRE)
	var lives0: int = g.lives
	g.run_for(60.0)
	_ok(e.hp <= 0.0, "%s: nepritel na protikladnem useku nezahynul (hp=%.1f)" % [name, e.hp])
	_ok(g.lives == lives0, "%s: zivy se dostal na vystup (zivoty %d)" % [name, g.lives])

	return "%-30s %4.0fx%-4.0f  meritko %.2f  ovladani %.2f  dotyk %.0f  deska %.0fx%.0f  navod %d px / %d radku / %d slov  krizeni %.0f" % [
		name, w, h, lay.s, lay.ui, min_touch, lay.arena.size.x, lay.arena.size.y,
		guide_px, guide_lines, guide_words, min_cross]
