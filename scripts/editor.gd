class_name Editor
extends RefCounted

# LEVEL EDITOR. Jan si v nem macka levely rucne - na telefonu, bez souboru,
# bez klavesnice.
#
# Stav editoru je ZAMERNE mimo hru: hra ma svuj Game a editor si do nej jen
# posila hotovy level pres set_level(). Kdyby editor sahal do rozjete hry,
# musel by se resit, co je rozdeleny poutnik, kdo ma bonus a co zlato.
#
# INTERAKCE: klepnutim na usek se vybere, tlacitka dole meni VYBRANY usek.
# Zadne tazeni - Jan hraje na telefonu a tazeni prstem pres cely displej
# je na male obrazovce nepresne. Tlacitka jsou jednoznacna a vidi se u nich,
# co delaji.
#
# UKLADANI JE LOKALNI. Nikam se nic neposila - zadna Firestore. Kdo chce
# level prenest do hry natrvalo, zmackne EXPORT a posle mi jednoradkovy KOD
# (vejde se do Telegramu i z telefonu). Ja ho vlozim do BuiltinLevels a level
# se veze s hrou na vsech platformach.
#
# Kazda zmena se rovnou uklada lokalne (localStorage / user://), aby hrac
# neprisel o praci, kdyz mu prohlizec zavre panel. Proto tu neni tlacitko
# "ulozit" - bylo by to tlacitko, ktere nic neresi.

# Tlacitka editoru. Poradi je poradi ve spodnim pruhu.
const BTN_ADD := 0
const BTN_DEL := 1
const BTN_ELEMENT := 2
const BTN_EXIT := 3
const BTN_BEND_LEFT := 4
const BTN_BEND_RIGHT := 5
const BTN_EXPORT := 6
const BTN_PLAY := 7
const BTN_LABELS := [
	"úsek +", "úsek −", "živel", "výstup", "odbočení −", "odbočení +", "export", "hrát",
]

var level: Level = Level.base()
# Ktery usek je vybrany. Meni se klepnutim na usek.
var sel: int = 0
# Hlaska pro hrace: co se prave stalo. Kresli se nad pruhem.
var status: String = ""
# Kod levelu pro predani. Po exportu se ukaze - hrac ho muze zkopirovat
# a poslat. Je to nejkratsi cesta z telefonu: soubor se z telefonu posila
# slozite, jedna rada textu ne.
var code: String = ""
# Jmeno, pod kterym se level uklada lokalne. Generuje se jednou za otevreni
# editoru, aby se kazda zmena neukladala pod jinym jmenem.
var local_name: String = ""


func reset() -> void:
	level = Level.base()
	sel = 0
	status = ""
	code = ""
	local_name = "level-%d" % (int(Time.get_unix_time_from_system()) % 100000)


# Nacte level - bud zakotveny ve hre, nebo lokalne ulozeny. Jeden vstup pro
# obe cesty: hrac nemusi vedet, odkud level prisel.
func load_named(n: String) -> void:
	var lv: Level = Level.builtin(n)
	if lv == null:
		lv = Level.load_named(n)
	level = lv
	sel = 0
	code = ""
	local_name = level.name
	status = "načteno: " + level.name


func _clamp_sel() -> void:
	if level.lane_count() <= 0:
		sel = 0
		return
	sel = clampi(sel, 0, level.lane_count() - 1)


# Jedno tlacitko editoru. Vsechno, co editor umi, je tady - kdyby se
# operace rozdelila mezi tlačítka a klávesové zkratky, nešlo by to na
# telefonu vubec pouzit.
func press(button: int) -> int:
	# VYBER SE SROVNA PRVNI. Hrac mohl klepnout na usek a pak level zmenit
	# (odebrat usek, nacist jiny) - bez toho by zivel nebo vystup sahal
	# mimo level a hra by spadla az za behu.
	_clamp_sel()
	match button:
		BTN_ADD:
			if level.add_lane():
				sel = level.lane_count() - 1
				status = "přidán úsek %d" % level.lane_count()
			else:
				status = "víc než %d úseků nejde" % Level.MAX_LANES
			_after_change()
		BTN_DEL:
			if level.lane_count() <= Level.MIN_LANES:
				status = "méně než %d úseky nejdou" % Level.MIN_LANES
			elif level.remove_lane(sel):
				_clamp_sel()
				status = "odebrán úsek"
				_after_change()
			else:
				status = "úsek nejde odebrat"
		BTN_ELEMENT:
			_cycle_element()
		BTN_EXIT:
			_cycle_exit()
		BTN_BEND_LEFT:
			_bend(-Level.SPREAD_STEP * 5.0)
		BTN_BEND_RIGHT:
			_bend(Level.SPREAD_STEP * 5.0)
		BTN_EXPORT:
			_export()
		BTN_PLAY:
			status = "spouštím hru s tímto levelem"
	return button


# Zmena levelu se rovnou uklada lokalne. Neni to "ukladani pro hrace" - je to
# jen to, aby o praci neprisel. Nic se nikam neposila.
func _after_change() -> void:
	code = ""
	level.name = local_name
	level.save()


# Zivel vybraneho useku. Cykli se pres vsechny ctyri a neutralni - hrac tak
# muze postavit treba dve kolejе stejneho zivlu, nebo naopak udelat mapu bez
# neutralniho useku (coz je tezsi, ale hratelne).
func _cycle_element() -> void:
	if level.lane_count() == 0:
		return
	var l: Dictionary = level.lanes[sel]
	var el: int = int(l["el"]) + 1
	if el > Element.COUNT - 1:
		el = Level.NEUTRAL
	l["el"] = el
	level.lanes[sel] = l
	level.relayout()
	if el == Level.NEUTRAL:
		status = "úsek %d: neutrální" % (sel + 1)
	else:
		status = "úsek %d: %s" % [sel + 1, Element.name_of(el)]
	_after_change()


# Vystup, kam usek usti. Vystup je dira v mape - nema element a nikdo ho
# "nevlastni". Kdyz jich je vic nez kolejí, zustanou nepouzite: to je
# v poradku, maji proste jen vic der.
func _cycle_exit() -> void:
	if level.lane_count() == 0:
		return
	var l: Dictionary = level.lanes[sel]
	var ex: int = (int(l["exit"]) + 1) % maxi(level.exits.size(), 1)
	l["exit"] = ex
	level.lanes[sel] = l
	level.relayout()
	status = "úsek %d ústí do výstupu %d" % [sel + 1, ex + 1]
	_after_change()


# Kde se usek ohne k vystupu. Mensi hodnota = ohne driv (bliz k vyhybce),
# vetsi = jde dele rovne. Diky tomu se daji dve koleje sbihat do jednoho
# vystupu, nebo se naopak rozejit hned na zacatku.
func _bend(d: float) -> void:
	if level.lane_count() == 0:
		return
	var l: Dictionary = level.lanes[sel]
	var v: float = clampf(float(l.get("divert", Level.BASE_DIVERT)) + d, 0.0, 0.98)
	l["divert"] = v
	level.lanes[sel] = l
	level.relayout()
	status = "úsek %d: odbočení %.2f" % [sel + 1, v]
	_after_change()


# EXPORT. Vysledek je jednoradkovy KOD, ktery se vejde do Telegramu, a
# k tomu soubor (ve webu se stahne, na desktopu se zapise do user://export).
# Kod je to, co mi Jan posle; soubor je pro pripad, ze si level chce nechat.
func _export() -> void:
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = "nevyexportováno: " + str(errs[0])
		return
	if level.name.is_empty() or level.name == Level.DEFAULT_NAME:
		level.name = local_name
	code = level.to_code()
	var where: String = level.export_to_file()
	if where.is_empty():
		status = "kód je níže, soubor se nepodařilo uložit"
	else:
		status = "export: " + where


# Popis vybraneho useku. Kresli se do HUDu editoru - deska sama zustava bez
# textu jako ve hre.
func sel_text() -> String:
	if level.lane_count() == 0:
		return "žádný úsek"
	_clamp_sel()
	var el: int = level.el_of(sel)
	var el_name: String = "neutrální" if el == Level.NEUTRAL else Element.name_of(el)
	return "úsek %d/%d · %s · výstup %d · odbočení %.2f" % [
		sel + 1, level.lane_count(), el_name, level.exit_of(sel) + 1, level.divert_of(sel)]


# Co je k dispozici k nacteni: zakotvene levely ve hre + lokalne ulozene.
# Jmena se needuplikuji - zakotveny level ma prednost, protoze ten se
# neztrati smazanim cache.
func available_levels() -> Array:
	var out: Array = []
	var seen := {}
	for item in BuiltinLevels.LEVELS:
		var d: Dictionary = item
		var n: String = str(d.get("name", ""))
		if n.is_empty() or seen.has(n):
			continue
		seen[n] = true
		out.append(n)
	for n2 in Level.saved_names():
		if not seen.has(str(n2)):
			seen[n2] = true
			out.append(str(n2))
	return out
