extends SceneTree

# ROZVRZENI NA RŮZNÝCH DISPLEJÍCH. Tohle je jadro zadani "nativne na sirku":
# hra se musi sama slozit na kazdem telefonu, ne jen na tom vyvojovem.
# Prochazi se realna rozliseni vcetne landscape telefonu, kde je POMER
# STRAN jiny nez u 960x600 - prave tam se rozvrzeni lame nejdriv.
#
# U kazdeho rozliseni se kontroluje:
#   * tlacitka jsou CELE na obrazovce a neprekryvaji se
#   * HERNI DESKA NEMA ZADNE OVLADANI ANI TEXT - pruh i SKIP jsou pryc
#   * deska saha az k spodnimu okraji displeje
#   * NAVOD se vejde CELY, ma obrazky a je STRUCNY
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
	_test_menu_buttons_are_wired()
	_test_board_has_no_furniture()
	_test_guide_shape()
	_test_editor_screens_are_wired()
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


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


# STRAZCE BEZ NABYTKU NA DESCE. Zadani je, ze z herni desky zmizi VSECHEN
# text I CELE OVLADANI - pruh a SKIP. Kdyby se neco vratilo, poznalo by se to
# jen okem na telefonu; tenhle test to vi z kodu. Cte se ZDROJAK, protoze
# z hotove kresby se text zpetne neprecte.
# KAZDE TLACITKO MENU MUSI BYT NAPOJENE NA SVOU AKCI. Klepnuti na "EDITOR"
# musi otevrit editor - ne navod. Driv se akce vybirala podle PORADI tlacitka
# a stacilo pridat tlacitko doprostred, aby se vsechno posunulo: Jan klepl na
# EDITOR a otevrel se navod. Test cte ZDROJ a hlida, ze se akce vybira pres
# Menu.MENU_ACTIONS a ze pro kazdou akci existuje vetev.
func _test_menu_buttons_are_wired() -> void:
	var src: String = _read("res://scripts/game_view.gd")
	_ok(src.contains("Menu.MENU_ACTIONS"), "menu vybira akci pres Menu.MENU_ACTIONS")
	_ok(not src.contains("match i:"), "a NIKOLI podle poradi tlacitka (match i)")
	# kazda akce musi mit vetev a kazda vetev musi byt v seznamu
	for a in Menu.MENU_ACTIONS:
		_ok(src.contains('"%s":' % a), "akce \"%s\" ma vetev v obsluze klepnuti" % a)
	# a seznamy musi byt stejne dlouhe - jinak by posledni tlacitko nemelo akci
	_ok(Menu.MENU_ITEMS.size() == Menu.MENU_ACTIONS.size(),
		"jmen je stejne jako akci (%d vs %d)" % [Menu.MENU_ITEMS.size(), Menu.MENU_ACTIONS.size()])
	_ok(Menu.MENU_SUBS.size() == Menu.MENU_ACTIONS.size(),
		"podtitulku je stejne jako akci (%d vs %d)" % [Menu.MENU_SUBS.size(), Menu.MENU_ACTIONS.size()])
	_ok(Menu.MENU_ITEMS.size() == ScreenLayout.MENU_COUNT,
		"tlacitek v rozvrzeni je stejne jako polozek menu (%d vs %d)" % [
			ScreenLayout.MENU_COUNT, Menu.MENU_ITEMS.size()])
	# a kazda akce musi nekam vest: kazda vetev musi mit aspon jeden prikaz
	var act: int = src.find("Menu.MENU_ACTIONS[i]:")
	_ok(act >= 0, "vetveni podle akce je v kodu")
	if act >= 0:
		var block: String = src.substr(act, 900)
		for a in Menu.MENU_ACTIONS:
			var at: int = block.find('"%s":' % a)
			_ok(at >= 0, "vetev pro \"%s\" existuje" % a)
			if at >= 0:
				var rest: String = block.substr(at)
				var lines: Array = rest.split("\n")
				var body: String = ""
				for k in range(1, mini(lines.size(), 4)):
					body += String(lines[k])
				_ok(body.strip_edges().length() > 0, "vetev \"%s\" neco dela" % a)


func _test_board_has_no_furniture() -> void:
	var src: String = _read("res://scripts/game_view.gd")
	_ok(not src.is_empty(), "herni scena jde precist")
	if src.is_empty():
		return
	# Vsechno od pozadi po HUD je DESKA. HUD je jedina cast, ktera smi mit
	# text - je mimo herni plochu.
	var a: int = src.find("func _draw_background")
	var b: int = src.find("func _draw_hud")
	_ok(a >= 0 and b > a, "v herni scene jde najit cast s deskou")
	if a >= 0 and b > a:
		var board: String = src.substr(a, b - a)
		_ok(not board.contains("_label("), "herni deska neobsahuje zadny popisek (_label)")
		_ok(not board.contains("draw_string"), "herni deska nekresli zadny text")
	# Pruh ani SKIP uz nesmi existovat NIKDE.
	_ok(not src.contains("skip_rect"), "SKIP je pryc z herni sceny")
	_ok(not src.contains("_draw_control_bar"), "ovladaci pruh je pryc")
	# KMEN SE MUSI KRESLIT. Kdyz se z vykreslovaci cesty vytratil, hrac vidi,
	# jak poutnici jdou do vyhybky odnikud - a v nabidce buildu to nikdo
	# nepozna. Presne to se stalo a nasel to az Jan na telefonu.
	_ok(src.contains("_draw_trunk()"), "kmen se kresli na herni desce")
	for p in ["res://scripts/game_view.gd", "res://scripts/screen_layout.gd",
			"res://scripts/network.gd"]:
		var s: String = _read(p)
		_ok(not s.contains("bar_y") and not s.contains("bar_h"),
			"%s: zbytky pruhu (bar_y/bar_h)" % p)
		for gone in ["výhybka —", "neutrální kmen", "dmg × 1.0", "dmg × %.1f"]:
			_ok(not s.contains(gone), "%s: popisek \"%s\" se do desky vratil" % [p, gone])
	# Rozvrzeni nesmi mit zadne tlacitko na desce.
	var lay_src: String = _read("res://scripts/screen_layout.gd")
	_ok(lay_src.contains("func all_buttons() -> Array:\n\treturn []"),
		"herni deska vraci prazdny seznam tlacitek")


# NAVOD JE OBRAZKOVY A STRUCNY. Kontroluje se tvar navodu, ne jeho vzhled:
#   * kazdy blok ma vlastni obrazek, ktery hra opravdu umi nakreslit
#   * popisky jsou kratke (MAX_WORDS slov)
func _test_guide_shape() -> void:
	_ok(Guide.BLOCKS.size() >= 3, "navod ma aspon tri obrazkove bloky (%d)" % Guide.BLOCKS.size())
	_ok(Guide.longest_caption_words() <= Guide.MAX_WORDS,
		"nejdelsi popisek ma %d slov (max %d)" % [Guide.longest_caption_words(), Guide.MAX_WORDS])
	var src: String = _read("res://scripts/game_view.gd")
	for b in Guide.BLOCKS:
		var art: String = str(b["art"])
		_ok(src.contains("func " + art), "obrazek navodu %s existuje" % art)
		# A HLAVNE: musi se opravdu VOLAT. Kdyz se blok prida do seznamu,
		# ale zapomene se vetev v match, obrazek se nikdy nenakresli -
		# pritom "funkce existuje" test projde. Presne to se stalo.
		_ok(src.contains('"' + art + '":\n			' + art + "("),
			"obrazek navodu %s se opravdu kresli (vetev v match)" % art)
		_ok(not str(b["title"]).is_empty(), "blok %s ma nadpis" % art)
		_ok(not str(b["text"]).is_empty(), "blok %s ma popisek" % art)


# DVE NOVE OBRAZOVKY EDITORU A NAVRAT ZE HRY. Kontroluje se, ze jsou opravdu
# NAPOJENE - ze se seznam levelu kresli i obsluhuje a ze se z rozehraneho
# levelu da vratit do editoru. Kdyby zustala jen funkce bez volani, hrac by
# na obrazovce videl neco jineho, nez co se da zmacknout.
func _test_editor_screens_are_wired() -> void:
	var src: String = _read("res://scripts/game_view.gd")
	# seznam levelu
	_ok(src.contains("_draw_editor_list()"), "seznam levelu se kresli")
	_ok(src.contains("editor.is_list()"), "obsluha klepnuti vi o seznamu")
	_ok(src.contains("editor.list_items("), "radky seznamu jdou z editoru")
	_ok(src.contains("layout.editor_list_fit()"), "a rozvrzeni rika, kolik jich je videt")
	_ok(src.contains("editor.pick("), "klepnuti na radek level nacte")
	_ok(src.contains("_open_editor"), "editor se z menu otevira")
	_ok(src.contains("editor.open_last()"),
		"a otevira se tam, kde hrac skoncil (ne od nuly)")
	# navrat do editoru z rozehrane hry
	_ok(src.contains("layout.hud_back"), "navrat do editoru je v hornim panelu")
	_ok(src.contains("_back_to_editor()"), "a klepnuti na nej neco dela")
	_ok(src.contains("_from_editor = true"), "hrac vi, ze hraje level z editoru")
	_ok(src.contains("menu.open_editor()\n	editor.close_list()"),
		"navrat zpet otevre editor a ne jeho seznam")
	# tlacitka editoru: popisky se berou z editoru (tlacitko vyhybky se meni)
	_ok(src.contains("editor.button_labels()"), "popisky tlacitek editoru jdou z editoru")
	_ok(not src.contains("Editor.BTN_LABELS"), "a nikdo je nebere z konstanty")
	_ok(Editor.BTN_LABELS.size() == ScreenLayout.ED_COUNT,
		"tlacitek editoru je tolik, kolik jich rozvrzeni pocita (%d vs %d)" % [
			Editor.BTN_LABELS.size(), ScreenLayout.ED_COUNT])


func _check_screen(w: float, h: float, name: String, font: Font) -> String:
	var lay := ScreenLayout.new()
	lay.compute(Vector2(w, h))

	var min_touch: float = 9999.0
	var min_cross: float = 9999.0
	var guide_px: int = -1
	var guide_art: int = 0

	# --- HERNI DESKA JE BEZ OVLADANI ---
	_ok(lay.all_buttons().is_empty(), "%s: na herni desce je nejake tlacitko" % name)
	# Deska musi sahat az k spodnimu okraji displeje - pruh je pryc, jeho
	# vyska patri hraci plose.
	_ok(lay.board_bottom >= h - 8.0 * lay.s,
		"%s: deska nekonci u okraje displeje (%.0f vs %.0f)" % [name, lay.board_bottom, h])
	_ok(lay.arena.end.y + 0.5 >= lay.board_bottom - 6.0 * lay.s,
		"%s: herni plocha nedosahuje k okraji desky" % name)

	# --- NAVRAT DO EDITORU v hornim panelu ---
	# Je to JEDINE tlacitko, ktere se v hre muze objevit (a jen kdyz hrac
	# hraje level z editoru). Musi byt cele v panelu a vpravo, kde nic
	# neprekazi - a musi byt dost velke na prst.
	var hb: Rect2 = lay.hud_back
	_ok(hb.position.x >= 0.0 and hb.end.x <= w + 0.5 and hb.end.y <= lay.hud_h + 0.5,
		"%s: navrat do editoru leze mimo horni panel (%s)" % [name, hb])
	_ok(hb.position.x >= w * 0.70,
		"%s: navrat do editoru prekazi cislum v panelu (x=%.0f)" % [name, hb.position.x])
	_ok(hb.size.x >= 80.0 * lay.ui and hb.size.y >= lay.hud_h - 6.0 * lay.ui - 0.01,
		"%s: navrat do editoru je moc maly (%s)" % [name, hb])

	# --- SEZNAM ULOZENYCH LEVELU v editoru ---
	var fit: int = lay.editor_list_fit()
	_ok(fit >= 3, "%s: do seznamu levelu se vejdou aspon tri radky (%d)" % [name, fit])
	var lrows: Array = lay.editor_list_rows(fit)
	_ok(lrows.size() == fit, "%s: radku seznamu je tolik, kolik se jich vejde" % name)
	for i in range(lrows.size()):
		var lr: Rect2 = lrows[i]
		_ok(lr.position.x >= -0.5 and lr.end.y <= h + 0.5,
			"%s: radek seznamu %d leze mimo obrazovku (%s)" % [name, i, lr])
		_ok(minf(lr.size.x, lr.size.y) >= MIN_TOUCH - 0.01,
			"%s: radek seznamu %d je moc maly (%.1f)" % [name, i, minf(lr.size.x, lr.size.y)])
		for j in range(i + 1, lrows.size()):
			var lr2: Rect2 = lrows[j]
			_ok(not lr.intersects(lr2), "%s: radky seznamu %d a %d se prekryvaji" % [name, i, j])

	# --- NAVOD SE MUSI VEJIT CELY ---
	# Navod je jedina informace o pravidlech hry. Je obrazkovy, takze se
	# kontroluje, ze se vejdou vsechny bloky i s obrazky.
	var guide_left: float = 22.0 * lay.ui
	var guide_w: float = w - guide_left * 2.0
	var guide_top: float = 10.0 * lay.ui
	var guide_h: float = lay.guide_back.position.y - guide_top - 8.0 * lay.ui
	var wide: bool = w >= 700.0
	guide_px = Guide.fit_px(font, guide_w, guide_h, wide)
	_ok(guide_px > 0,
		"%s: navod se nevejde do obrazovky ani pri %d px (k dispozici %.0f px)" % [
			name, Guide.MIN_PX, guide_h])
	# a obrazek musi mit v blocich rozumnou velikost, ne jen par pixelu
	var fs: int = maxi(guide_px, Guide.MIN_PX)
	var cols: int = 2 if wide else 1
	var rows: int = int(ceil(float(Guide.BLOCKS.size()) / float(cols)))
	var cell_h: float = (guide_h - float(fs) * 1.9) / float(rows)
	var art_w: float = Guide.art_width(guide_w / float(cols), cell_h, wide)
	guide_art = int(art_w)
	_ok(art_w >= float(fs) * 2.0,
		"%s: obrazky v navodu jsou moc male (%.0f px)" % [name, art_w])
	# a text vedle obrazku musi mit misto aspon na par znaku
	var txt_w: float = guide_w / float(cols) - art_w - float(fs) * 1.6
	_ok(txt_w >= float(fs) * 4.0, "%s: vedle obrazku nezustava misto na text (%.0f px)" % [name, txt_w])

	# --- PRUH EDITORU NESMI PREKRYVAT PLOCHU ---
	# Pruh se kresli od `editor_bar_top()` dolu (popisky vybraneho useku jsou
	# nad tlacitky) a arena editoru musi koncit NAD nim. Kdyz si to oboji
	# pocitalo samo, prekryl pruh spodni cast mrizky - a hrac nemel kam klapat.
	_ok(lay.editor_arena.end.y <= lay.editor_bar_top() - 1.0,
		"%s: arena editoru leze do pruhu tlacitek (%.0f vs %.0f)" % [
			name, lay.editor_arena.end.y, lay.editor_bar_top()])
	_ok(lay.editor_arena.size.y > 60.0,
		"%s: v editoru nezustava misto na mrizku (%.0f px)" % [name, lay.editor_arena.size.y])

	# --- POPISKY TLACITEK EDITORU SE MUSI VEJIT ---
	# Tlacitek je jedenact a pruh je nizky. Kdyby popisek pretekal, hrac by
	# nevidel, co tlacitko dela - a to je presne to, co u editoru nesmi nastat.
	var ed_probe := Editor.new()
	ed_probe.reset()
	var lbls: Array = ed_probe.button_labels()
	_ok(lbls.size() == lay.ed_buttons.size(),
		"%s: popisku je tolik, kolik je tlacitek editoru" % name)
	var efs: int = lay.font(13.0)
	for i in range(mini(lbls.size(), lay.ed_buttons.size())):
		var br: Rect2 = lay.ed_buttons[i]
		var tw: float = font.get_string_size(str(lbls[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, efs).x
		_ok(tw <= br.size.x - 4.0,
			"%s: popisek \"%s\" se do tlacitka nevejde (%.0f px do %.0f)" % [
				name, str(lbls[i]), tw, br.size.x])

	# --- CO NEJVIC MISTA NAD DESKOU ---
	# Nad prvni drazkou nesmi zustat prazdny pruh: kazdy pixel tam chybi
	# hraci plose. Meritkem je horni hrana bonusu na prvni draze.
	var g_top := Game.new()
	g_top.setup(lay.arena, lay.s, lay.board_bottom)
	var head: float = float(g_top.net.rows[0]) - g_top.net.bonus_r
	_ok(head <= lay.hud_h + 4.0 * lay.s,
		"%s: nad prvni drazkou zustava prazdny pruh (%.0f px pod panelem do %.0f)" % [
			name, head - lay.hud_h, head])
	_ok(head >= lay.hud_h - 6.0 * lay.s,
		"%s: prvni drazka se schovava pod panel (%.0f vs %.0f)" % [name, head, lay.hud_h])

	# --- a LEVEL SE DVEMA VSTUPY musi na tom rozliseni taky fungovat ---
	# Dva kmeny = dva stromy radku. Musi se vejit do plochy, bonusy se nesmi
	# prekryvat a hra se z toho musi dat vubec postavit.
	var lv2 := Level.base()
	var jt: int = lv2.add_tree()
	_ok(jt >= 0, "%s: level se dvema vstupy jde sestavit" % name)
	_ok(lv2.validate().is_empty(),
		"%s: a je platny: %s" % [name, str(lv2.validate())])
	var g2 := Game.new()
	g2.setup(lay.arena, lay.s, lay.board_bottom, lv2)
	_ok(g2.net.trunk_paths.size() == 2, "%s: sit postavi oba kmeny" % name)
	for lane in range(g2.net.lane_count()):
		_ok(g2.net.rows[lane] < lay.board_bottom - 12.0 * lay.s,
			"%s: drazka %d v levelu se dvema vstupy leze pod desku (%.0f)" % [
				name, lane, g2.net.rows[lane]])
		for slot in range(g2.net.slot_count()):
			var p2: Vector2 = g2.net.slot_world(lane, slot)
			_ok(lay.arena.grow(g2.net.bonus_r).has_point(p2),
				"%s: misto %d/%d v levelu se dvema vstupy lezi v plose (%s)" % [
					name, lane, slot, p2])
	var gap2: float = g2.net.min_cross_lane_slot_distance()
	_ok(gap2 > g2.net.bonus_r * 1.8,
		"%s: bonusy se ve dvou vetvich prekryvaji (mezera %.0f, potreba %.0f)" % [
			name, gap2, g2.net.bonus_r * 1.8])

	# --- PLNA DESKA ---
	# Strop levelu neni pocet useku ani vyhybek, ale MISTO NA DESCE: radky se
	# zmensuji jen do MIN_ROW_GAP. Presne tenhle strop se musi na kazdem
	# rozliseni vejit - jinak by si hrac postavil level, na kterem se bonusy
	# prekryvaji (a videl by to az ve hre).
	var lv3: Level = Level.base()
	while lv3.lane_count() < Level.MAX_LANES:
		var keep3: Level = lv3.clone()
		if not lv3.add_lane(0) or not lv3.rows_fit():
			lv3 = keep3
			break
	_ok(lv3.rows_fit(),
		"%s: plna deska ma vic radku, nez se vejde (%.3f)" % [name, lv3.row_gap()])
	_ok(lv3.rows_total() >= 9,
		"%s: na desku se vejde aspon 9 radku (%d)" % [name, lv3.rows_total()])
	_ok(lv3.validate().is_empty(),
		"%s: plna deska je platna: %s" % [name, str(lv3.validate())])
	var g3 := Game.new()
	g3.setup(lay.arena, lay.s, lay.board_bottom, lv3)
	var gap3: float = g3.net.min_cross_lane_slot_distance()
	_ok(gap3 > g3.net.bonus_r * 1.8,
		"%s: na plne desce (%d drah) se bonusy prekryvaji (mezera %.0f, potreba %.0f)" % [
			name, lv3.lane_count(), gap3, g3.net.bonus_r * 1.8])
	for lane in range(g3.net.lane_count()):
		_ok(g3.net.rows[lane] < lay.board_bottom - 6.0 * lay.s,
			"%s: draha %d plne desky leze pod desku (%.0f)" % [name, lane, g3.net.rows[lane]])

	# --- tlacitka ZPET, MENU, EDITOR ---
	for k in range(4):
		var mb: Array = lay.all_menu_buttons() if k == 0 else (
			lay.all_settings_buttons() if k == 1 else (
			lay.all_editor_buttons() if k == 2 else [lay.guide_back]))
		var tag: String = ["menu", "nastaveni", "editor", "navod"][k]
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
		if k == 0 or k == 2:
			for r in mb:
				var rr: Rect2 = r
				min_touch = minf(min_touch, minf(rr.size.x, rr.size.y))

	# --- herni plocha a sit ---
	var g := Game.new()
	g.setup(lay.arena, lay.s, lay.board_bottom)
	g.rebuild_network(lay.arena, lay.s, lay.board_bottom)

	_ok(lay.arena.size.x > 200.0 and lay.arena.size.y > 80.0,
		"%s: herni plocha neni degenerovana (%s)" % [name, lay.arena])
	_ok(lay.arena.size.x > lay.arena.size.y,
		"%s: hra je na sirku, plocha je sirsi nez vyssi (%.0fx%.0f)" % [name,
			lay.arena.size.x, lay.arena.size.y])

	for lane in range(g.net.lane_count()):
		for slot in range(g.net.slot_count()):
			var p: Vector2 = g.net.slot_world(lane, slot)
			_ok(lay.arena.grow(g.net.bonus_r).has_point(p),
				"%s: misto %d/%d lezi v plose (%s)" % [name, lane, slot, p])
		var path: PackedVector2Array = g.net.lane_path[lane]
		for k in range(path.size()):
			_ok(path[k].y < lay.board_bottom,
				"%s: bod useku %d je pod deskou" % [name, lane])
		var last: Vector2 = g.net.point_at(lane, g.net.lane_len[lane])
		_ok(last.distance_to(g.net.exit_pos[g.net.lane_exit[lane]]) < 1.0,
			"%s: usek %d nekonci ve svem vystupu" % [name, lane])
		# VSECHNY prvky desky musi zustat nad spodnim okrajem.
		_ok(g.net.rows[lane] < lay.board_bottom - 20.0 * lay.s,
			"%s: dmg zona %d leze pod desku (y=%.0f)" % [name, lane, g.net.rows[lane]])
		var ep: Vector2 = g.net.exit_pos[g.net.lane_exit[lane]]
		_ok(ep.y + g.net.exit_r <= lay.board_bottom,
			"%s: vystup %d leze pod desku (%.0f + %.0f)" % [name, lane, ep.y, g.net.exit_r])

	min_cross = g.net.min_cross_lane_slot_distance()
	_ok(min_cross > g.net.bonus_r * 2.0,
		"%s: bonusy na sousednich pruzich se prekryvaji (mezera %.1f, potreba %.1f)" % [
			name, min_cross, g.net.bonus_r * 2.0])

	# --- a hra na tom rozliseni musi porad fungovat ---
	# Klepnuti na usek je jedina interakce, kterou hrac prepina vyhybku.
	for lane in range(g.net.lane_count()):
		var tap: Vector2 = g.net.point_at(lane, g.net.lane_len[lane] * 0.7)
		var hit: int = g.net.lane_tap_at(tap, maxf(10.0, 16.0 * lay.s))
		_ok(hit == lane, "%s: klepnuti na usek %d ho vybere (hit=%d)" % [name, lane, hit])
	# Kazdy zivel umre na sve protikladne useku, kdyz je usek vystrojen.
	var target_el: int = Element.opposite_of(Element.FIRE)
	var kill_lane: int = -1
	for lane in range(g.net.lane_count()):
		if g.net.lane_element(lane) == target_el:
			kill_lane = lane
	_ok(kill_lane >= 0, "%s: usek pro %s existuje" % [name, Element.name_of(target_el)])
	g.auto_wave = false
	g.gold = 999
	g.try_build(kill_lane, 0, g.net.lane_element(kill_lane))
	g.set_switch(kill_lane)
	var e: Enemy = g.debug_spawn(Element.FIRE)
	var lives0: int = g.lives
	g.run_for(60.0)
	_ok(e.hp <= 0.0, "%s: nepritel na protikladnem useku nezahynul (hp=%.1f)" % [name, e.hp])
	_ok(g.lives == lives0, "%s: zivy se dostal na vystup (zivoty %d)" % [name, g.lives])

	return "%-30s %4.0fx%-4.0f  meritko %.2f  ovladani %.2f  deska %.0fx%.0f (do %.0f)  nad deskou %.0f px  navod %d px / obrazky %d px  krizeni %.0f" % [
		name, w, h, lay.s, lay.ui, lay.arena.size.x, lay.arena.size.y, lay.board_bottom,
		head - lay.hud_h, guide_px, guide_art, min_cross]
