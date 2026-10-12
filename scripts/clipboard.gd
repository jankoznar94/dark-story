class_name Clipboard
extends RefCounted

# KOPIROVANI DO SCHRANKY. Level se z editoru predava jako KOD - a na telefonu
# se neda opsat: vypsany radek se neda oznacit a zkopirovat. Hrac tedy zmackne
# "export" a kod ma rovnou ve schrance; zbytek je vlozeni do zpravy.
#
# Dve cesty, protoze web a desktop se chovaji jinak:
#   * WEB: JavaScriptBridge. `navigator.clipboard` umi zapisovat jen v
#     uzivatelskem gestu (a jen na https) - nas tisk tlacitka gesto je, takze
#     to projde. Kdyz prohlizec clipboard API nema, zkusi se jeste stara cesta
#     pres skryty textarea a `document.execCommand("copy")`.
#   * DESKTOP: DisplayServer.clipboard_set a hned se cte zpet - jedina
#     kontrola, ktera ma smysl (a je duvod, proc funkce vraci bool).


# Zkopiruje text do schranky. Vraci true, kdyz to podle vseho vyslo.
static func copy(text: String) -> bool:
	if text.is_empty():
		return false
	if OS.has_feature("web"):
		return _copy_web(text)
	# Kdyz platforma schranku vubec neumi (headless testy), nesahame na ni -
	# `clipboard_get` by do logu vypsal chybu a hrac by videl hlasku o selhani.
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		return false
	DisplayServer.clipboard_set(text)
	# WINDOWS VRACI TEXT SE SVYMI KONCI RADKU (\r\n). Kdyby se porovnavalo
	# presne, vypsalo by se "nepodařilo se zkopírovat", i kdyz kod ve schrance
	# opravdu je - a hrac by ho zbytecne hledal jinde. Porovnava se proto
	# NORMALIZOVANE.
	return _same(DisplayServer.clipboard_get(), text)


# Jsou to ty same texty? Rozdily ve koncich radku a mezerach na okraji se
# ignoruji - to jsou rozdily formatu, ne obsahu.
static func _same(a: String, b: String) -> bool:
	return _norm(a) == _norm(b)


static func _norm(s: String) -> String:
	return s.replace("\r\n", "\n").replace("\r", "\n").strip_edges()


# Na webu NELZE zjistit vysledek: navigator.clipboard.writeText vraci Promise,
# ktery JavaScriptBridge.eval nevidi. Vracime tedy jen to, ze zapis probehl -
# a hrac ma druhou sanci (kod je porad vypsany nad pruhem).
static func _copy_web(text: String) -> bool:
	var js := Engine.get_singleton("JavaScriptBridge")
	if js == null:
		return false
	var lit: String = JSON.stringify(text)
	var script: String = "(function(t){try{" \
		+ "if(navigator.clipboard&&navigator.clipboard.writeText){" \
		+ "navigator.clipboard.writeText(t);return 'ok';}" \
		+ "var a=document.createElement('textarea');a.value=t;" \
		+ "a.setAttribute('readonly','');a.style.position='fixed';" \
		+ "a.style.left='-9999px';document.body.appendChild(a);a.select();" \
		+ "var r=document.execCommand('copy');document.body.removeChild(a);" \
		+ "return r?'ok':'fail';}catch(e){return 'fail';}})(" + lit + ")"
	var res: Variant = js.eval(script)
	return str(res) == "ok"
