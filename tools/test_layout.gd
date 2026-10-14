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
	_test_leave_route()
	if fails.is_empty():
		print("LAYOUT_ALL_PASS=true (%d kontrol)" % checks)
		quit(0)
	else:
		for f in fails:
			print("  FAIL: " + str(f))
		print("LAYOUT_ALL_PASS=false (%d kontrol)" % checks)
		quit(1)


# =========================================================================
# CESTA Z BITVE: KLEPNUTI NA MENU, DOTAZ A ODPOVED
#
# Jan (Oct 2026): "Ještě musíme přidat tlačítko 'menu' do boje. Aby se hráč
# mohl vrátit z boje předčasně. Musí se hra samozřejmě zeptat jestli chce
# opravdu ukončit level."
#
# Tohle se neda overit ctenim zdroje - proto se postavi SKUTECNA obrazovka
# (`main.tscn`) a klepe se do ni jako prstem. Kontroluje se hlavne to, ze
# pod dotazem hra STOJI (jinak by se hrac rozhodoval, zatimco mu umiraji
# poutnici) a ze se hrac vrati TAM, ODKUD PRISEL.
#
# POZOR NA SUM V LOGU: v tomhle rezimu (bez okna) hlasi kazde klepnuti
# "Playback can only happen when a node is inside the scene tree" - zvuk v
# testu nehraje. Neni to chyba hry: `_setup_audio` hrace do stromu pridava a
# v realnem behu hraje (viz `test_audio`).
# =========================================================================
func _test_leave_route() -> void:
	var packed: PackedScene = load("res://main.tscn")
	_check(packed != null, "main.tscn se neda nacist")
	if packed == null:
		return
	var v: Node = packed.instantiate()
	get_root().add_child(v)
	# POZOR: v testovacim behu (`--script`) se `_ready` obrazovky jeste
	# nezavolalo - strom se inicializuje az po `_init`. Zavolame ho sami,
	# at se testuje SKUTECNA obrazovka a ne prazdny objekt.
	if v.game == null:
		v._ready()
	# A ROZVRZENI SE MUSI DODAT: v testu ma okno 0x0, takze by vsechna
	# tlacitka vysla mimo displej a klepnuti by nikam netrefilo. Bereme
	# rozliseni telefonu na sirku - na tom hraji Janovi lidi.
	v.layout.compute(Vector2(932.0, 430.0))
	# Z KAMPANE: hraju prvni level z vyberu levelu.
	v._play_campaign(0)
	_check(v.menu.is_battle(), "level z kampane se nespustil")
	_check(v.level_index == 0, "hra nevi, ktery level hraje")
	v._handle_tap(v.layout.hud_menu.get_center())
	_check(v.leave_ask, "klepnuti na MENU se nezeptalo, jestli level ukoncit")
	_check(v.game.is_paused(), "pod dotazem hra bezi dal")
	# Klepnuti mimo odpoved nesmi nic udelat (ani zavrit dotaz, ani stavel).
	v._handle_tap(Vector2(4.0, v.layout.view.y * 0.5))
	_check(v.leave_ask, "klepnuti mimo odpoved dotaz zavrelo")
	_check(v.game.is_paused(), "klepnuti mimo odpoved hru rozjelo")
	# ZPET DO HRY: dotaz zmizi a hra jede dal.
	v._handle_tap(v.layout.leave_no.get_center())
	_check(not v.leave_ask, "ZPET DO HRY nezavrelo dotaz")
	_check(not v.game.is_paused(), "po ZPET DO HRY hra stoji")
	# UKONCIT: hrac se vrati do vyberu levelu.
	v._handle_tap(v.layout.hud_menu.get_center())
	v._handle_tap(v.layout.leave_yes.get_center())
	_check(not v.leave_ask, "po UKONCIT zustal dotaz otevreny")
	_check(v.menu.is_levels(), "po UKONCIT se hrac nevratil do vyberu levelu")
	# Z VOLNE HRY: hrac se vraci do menu (vyber levelu nema smysl).
	v._start_battle()
	_check(v.menu.is_battle(), "volna hra se nespustila")
	v._handle_tap(v.layout.hud_menu.get_center())
	v._handle_tap(v.layout.leave_yes.get_center())
	_check(v.menu.is_menu(), "z volne hry se hrac nevratil do menu")
	# PAUZA A MENU SE NESMI PLEST: klepnuti na pauzu hru zastavi, ale dotaz
	# se neotevre.
	v._start_battle()
	v._handle_tap(v.layout.hud_pause.get_center())
	_check(v.game.is_paused() and not v.leave_ask,
		"pauza se plete s dotazem na ukonceni")
	v.queue_free()


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
	# SHLUK NA VYHYBCE: kdyz se u vyhybky rozdeli dva poutnici, musi hrac
	# videt DVA krouzky. Kdyby kresleni bralo jen nejsilnejsi efekt
	# (`junction_flash_at`), druhy poutnik by z desky zmizel - a to je presne
	# ten pripad, kdy hrac potrebuje videt, co se stalo.
	_check(src.contains("for item in game.junction_flashes_at(n):"),
		"kresleni vyhybky bere jen jeden efekt - shluk by nebyl videt")
	# ODCHOD Z BOJE: tlacitko MENU se musi zeptat a odpovedi musi neco delat.
	_check(src.contains("func ask_leave()"), "v bitve neni cim se zeptat na ukonceni")
	_check(src.contains("if leave_ask:\n		_handle_leave_tap(pos)"),
		"dotaz na ukonceni neni nad ostatnim vstupem - sel by stavel pod nim")
	_check(src.contains("leave_yes.has_point(pos)") and src.contains("leave_no.has_point(pos)"),
		"odpovedi na dotaz se nedaji zmacknout")
	_check(src.contains("func _draw_leave()") and src.contains("_draw_leave()"),
		"dotaz na ukonceni se nekresli")
	# PAUZA: tlacitko je jen tehdy funkci, kdyz se na nej da klepnout a kdyz
	# hra pod pauzou opravdu stoji.
	_check(src.contains("if layout.hud_pause.has_point(pos):"),
		"tlacitko pauzy se nedá zmacknout")
	_check(src.contains("game.toggle_pause()"), "klepnuti na pauzu hru nezastavi")
	_check(src.contains("not game.is_paused()"),
		"obrazovka kroku hrou i pod pauzou - pauza by nic nedelala")
	_check(src.contains("\"PAUZA\""), "tlacitko pauzy nema popisek")
	# VYHRA: level se musi zapsat a hrac se musi vratit do vyberu levelu.
	_check(src.contains("campaign.mark_cleared(level_index)"),
		"vyhra se neoznaci (level by zustal zamceny)")
	_check(src.contains("func _open_levels()") and src.contains("_open_levels()"),
		"po vyhre se hrac nevrátí do vyberu levelu")
	_check(src.contains("campaign.is_unlocked(i)"),
		"vyber levelu necte, co je odemcene")
	# PREJMENOVANI A SMAZANI v seznamu editoru: tlacitka musi neco delat.
	_check(src.contains("editor.begin_rename(key)"), "tlacitko nazvu nic nedela")
	_check(src.contains("editor.ask_delete(key)"), "tlacitko smazani nic nedela")
	_check(src.contains("editor.commit_name()") and src.contains("editor.close_name()"),
		"obrazovka prejmenovani nema cim ulozit nebo zrusit nazev")
	# KLAVESNICI DAVA SYSTEM, NE HRA (Jan: "Chci používat úplně klasickou
	# mobilní klávesnici. A klasický input."). Hlida se MISTO POUZITI:
	# existence funkce by prosla i s vstupem, ktery nikdo nezobrazi.
	_check(src.contains("LineEdit.new()"), "vstup pro nazev neni opravdovy LineEdit")
	_check(src.contains("_sync_name_input()"), "vstup pro nazev se nikde neaktualizuje")
	_check(src.contains("virtual_keyboard_show"), "hra si nerekne o klavesnici systemu")
	_check(src.contains("_name_input.has_focus()"),
		"text z nativni klavesnice se nikam neprebira (web neemituje text_changed)")
	_check(not src.contains("editor.name_grid()"), "hra stale kresli vlastni klavesnici")
	var edsrc: String = FileAccess.get_file_as_string("res://scripts/editor.gd")
	_check(not edsrc.contains("func name_grid()"), "editor stale nabizi nakreslenou klavesnici")
	_check(edsrc.contains("func set_name_text("), "editor nema cim prijmout text z pole")
	# VIRTUALNI KLAVESNICE NA WEBU JE VOLBA EXPORTU. Bez ni `DisplayServer`
	# zadnou klavesnici nema a na mobilu by se neukazala - ticha chyba, ktera
	# se projevi jen na telefonu.
	var preset: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	_check(preset.contains("html/experimental_virtual_keyboard=true"),
		"export nezapina virtualni klavesnici na webu")
	_check(edsrc.contains("Level.delete_key("), "editor neumi level smazat")
	_check(edsrc.contains("Level.rename_key("), "editor neumi level prejmenovat")
	# PO SMAZANI SE ZUSTAVA V SEZNAMU. `reset` prepina rezim do kresleni, takze
	# bez navratu vyhodi potvrzujici klepnuti hrace na desku ("po smazání se
	# otevře následující level", Jan).
	_check(edsrc.contains("mode = MODE_LIST"), "smazani levelu necha hrace v kresleni")


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
	g.auto_wave = false
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
	g2.auto_wave = false
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

	# --- PAUZA A NAVRAT DO EDITORU v hornim panelu. Obe tlacitka jsou MIMO
	# herni desku (deska zustava bez ovladani) a nad dotykovym minimem -
	# jinak by si hrac nemel kde hru zastavit.
	for pr in [layout.hud_pause, layout.hud_back]:
		var prr: Rect2 = pr
		_check(prr.position.x >= -0.6 and prr.end.x <= float(w) + 0.6,
			"%s: tlacitko panelu utika vodorovne (%.1f..%.1f)" % [tag, prr.position.x, prr.end.x])
		_check(prr.position.y >= -0.6 and prr.end.y <= layout.hud_h + 0.6,
			"%s: tlacitko panelu leze z horniho pruhu (%.1f..%.1f)" % [tag, prr.position.y, prr.end.y])
		_check(prr.size.y >= ScreenLayout.MIN_TOUCH * 0.8 - 0.6,
			"%s: tlacitko panelu je nizke %.1f px" % [tag, prr.size.y])
	_check(not layout.hud_pause.intersects(layout.hud_back),
		"%s: pauza a navrat do editoru se prekryvaji" % tag)
	_check(layout.hud_pause.end.y <= layout.arena.position.y + 0.6,
		"%s: pauza leze na herni desku" % tag)
	# ODCHOD Z BOJE: treti tlacitko v panelu, vlevo od ostatnich.
	_check(layout.hud_menu.position.x >= -0.6 and layout.hud_menu.end.x <= float(w) + 0.6,
		"%s: tlacitko MENU utika vodorovne (%.1f..%.1f)" % [tag,
			layout.hud_menu.position.x, layout.hud_menu.end.x])
	_check(layout.hud_menu.end.y <= layout.hud_h + 0.6 and layout.hud_menu.position.y >= -0.6,
		"%s: tlacitko MENU leze z horniho pruhu" % tag)
	_check(layout.hud_menu.size.x >= ScreenLayout.MIN_TOUCH - 0.6
			and layout.hud_menu.size.y >= ScreenLayout.MIN_TOUCH * 0.8 - 0.6,
		"%s: tlacitko MENU je male (%.1f x %.1f)" % [tag, layout.hud_menu.size.x,
			layout.hud_menu.size.y])
	_check(not layout.hud_menu.intersects(layout.hud_pause)
			and not layout.hud_menu.intersects(layout.hud_back),
		"%s: tlacitko MENU se prekryva s pauzou nebo navratem" % tag)
	# DOTAZ NA UKONCENI: stoji uprostred displeje a obe odpovedi jsou
	# dotykove a uvnitr dotazu.
	_check(layout.leave_box.size.x > 0.0
			and layout.leave_box.position.x >= -0.6
			and layout.leave_box.end.x <= float(w) + 0.6
			and layout.leave_box.position.y >= -0.6
			and layout.leave_box.end.y <= float(h) + 0.6,
		"%s: dotaz na ukonceni utika z displeje" % tag)
	var lb2: Array = layout.all_leave_buttons()
	_check(lb2.size() == 2, "%s: dotaz nema dve odpovedi (%d)" % [tag, lb2.size()])
	for ai in range(lb2.size()):
		var ar: Rect2 = lb2[ai]
		_check(layout.leave_box.encloses(ar), "%s: odpoved %d leze z dotazu" % [tag, ai])
		_check(ar.size.x >= ScreenLayout.MIN_TOUCH - 0.6
				and ar.size.y >= ScreenLayout.MIN_TOUCH - 0.6,
			"%s: odpoved %d je mala (%.1f x %.1f)" % [tag, ai, ar.size.x, ar.size.y])
	_check(not layout.leave_yes.intersects(layout.leave_no),
		"%s: odpovedi dotazu se prekryvaji" % tag)

	# --- VYBER LEVELU: kazdy radek musi byt na displeji, nad dotykovym
	# minimem a bez prekryvu se ZPET. Klepnuti na radek hraje level, takze
	# spatne rozvrzeni znamena, ze se hrac netrefi.
	layout.levels_panel(Campaign.level_count())
	_check(layout.levels_rows.size() == layout.levels_fit + 1,
		"%s: vyber levelu ma %d radku, ceka se %d" % [tag, layout.levels_rows.size(),
			layout.levels_fit + 1])
	var lb: Array = layout.all_level_buttons()
	_check(lb.size() >= 2, "%s: vyber levelu nema ani radek a ZPET" % tag)
	for li in range(lb.size()):
		var lr: Rect2 = lb[li]
		_check(lr.position.x >= -0.6 and lr.end.x <= float(w) + 0.6,
			"%s: cíl vyberu levelu %d utika vodorovne" % [tag, li])
		_check(lr.position.y >= -0.6 and lr.end.y <= float(h) + 0.6,
			"%s: cíl vyberu levelu %d utika svisle (%.1f..%.1f)" % [tag, li,
				lr.position.y, lr.end.y])
		_check(lr.size.y >= ScreenLayout.MIN_TOUCH - 0.6,
			"%s: cíl vyberu levelu %d je nizky %.1f px" % [tag, li, lr.size.y])
		for lj in range(li + 1, lb.size()):
			var lr2: Rect2 = lb[lj]
			_check(not lr.intersects(lr2),
				"%s: cile vyberu levelu %d a %d se prekryvaji" % [tag, li, lj])

	# --- PREJMENOVANI LEVELU: pole a dve tlacitka. Vsechno musi byt na
	# displeji, dotykove velke a NEPREKRYVAT se - a hlavne CELÉ NAD PRVNÍM
	# RADKEM: klavesnici system vysune ZDOLA a prekryla by, co by stalo niz.
	var targets: Array = layout.all_name_targets()
	_check(targets.size() == 3, "%s: obrazovka prejmenovani ma %d cilu" % [tag, targets.size()])
	for ti in range(targets.size()):
		var tr: Rect2 = targets[ti]
		_check(tr.position.x >= -0.6 and tr.end.x <= float(w) + 0.6,
			"%s: cil prejmenovani %d utika vodorovne" % [tag, ti])
		_check(tr.position.y >= -0.6 and tr.end.y <= float(h) + 0.6,
			"%s: cil prejmenovani %d utika svisle" % [tag, ti])
		_check(tr.size.y >= ScreenLayout.MIN_TOUCH - 0.6,
			"%s: cil prejmenovani %d je nizky %.1f px" % [tag, ti, tr.size.y])
		for tj in range(ti + 1, targets.size()):
			var tr2: Rect2 = targets[tj]
			_check(not tr.intersects(tr2),
				"%s: cile prejmenovani %d a %d se prekryvaji" % [tag, ti, tj])
	# POLE I TLACITKA MUSI BYT V HORNIM PASU. Klavesnice zabira spodni
	# polovinu displeje - cokoli pod ni by hrac nevidel, kdyz pise.
	var name_bottom: float = maxf(layout.name_field.end.y,
		maxf(layout.name_ok.end.y, layout.name_cancel.end.y))
	_check(name_bottom <= float(h) * 0.45,
		"%s: vstup pro nazev konci na %.1f px z %d - klavesnice by ho prekryla" % [
			tag, name_bottom, h])
