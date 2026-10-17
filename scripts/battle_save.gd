class_name BattleSave
extends RefCounted

# UKLADANI ROZEHRANE PARTIE. Jan (Oct 2026): "Když mám hru rozehranou a odejdu
# z appky (nechám zapnutou na pozadí), tak se po návratu znovu načítá Godot
# a progress v levelu se mi ztratí. ... Chtělo by to přidat možnost pokračovat
# tam, kde jsem skončil."
#
# PROC TO NESTACI RESIT V PROHLIZECI: na telefonu prohlizec zalozku na pozadi
# ZAHODI (ne jen uspi), takze se stranka znovu nacte a cela pamet hry je pryc.
# Jedina cesta je mit stav na disku - a to je presne to, co dela `Profile`
# s postupem. `user://` na webu drzi Godot v IndexedDB, takze prezije reload.
#
# CO SE UKLADA: cely stav BITVY (`Game.to_state()`), ne jen "kde jsem byl" -
# hrac se ma vratit do rozjete vlny, ne na zacatek levelu (level ma 50 vln a
# trva desitky minut).
#
# KDO UKLADA: obrazovka (`game_view`) kazde `SAVE_EVERY` sekundy, dokud bitva
# bezi. Neni to "uklid pri odchodu" - kdyz prohlizec zalozku zahodi, zadny
# odchod se nekoná. Zapis je maly (desitky kB) a v IndexedDB rychly.
#
# CO S UKLADANOU PARTII DELA KONEC HRY: vyhra i prohra ukladanou partii MAZOU
# (`clear()`), protoze dohrana bitva se neobnovuje - hrac ma hrat novou.

# CESTA JE PROMENNA (ne konstanta), aby si ji test mohl presmerovat do
# vlastniho souboru a neprepsal hracuv rozehrany level.
static var path: String = "user://zily2_battle.cfg"
const SECTION := "bitva"
# ZAPIS SE DA VYPNOUT stejne jako u profilu (`Profile.allow_save`): testy
# a simulátor hrají desítky partii a nesmi prepsat hracuv stav.
static var allow_save: bool = true


# ULOZIT STAV BITVY. Vraci true, kdyz se opravdu zapsal - hrac i testy se
# ptaji na navratovou hodnotu, ne na to, "co se asi stalo".
static func save(g: Game) -> bool:
	if not allow_save or g == null:
		return false
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "state", g.to_state())
	return cf.save(path) == OK


# JE CO OBNOVIT? Ptá se na to menu (nabidka "pokracovat").
static func has() -> bool:
	return not state().is_empty()


# ULOZENY STAV (prazdny slovnik, kdyz nic neni nebo je soubor poskozeny).
static func state() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return {}
	var d: Variant = cf.get_value(SECTION, "state", {})
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	return d


# CO JE V ULOZENE PARTII (pro text dotazu: "level 3, vlna 12"). Nikdy necte
# stav hry - jen to, co je na disku.
static func info() -> Dictionary:
	var d: Dictionary = state()
	if d.is_empty():
		return {}
	return {
		"level": int(d.get("level", 1)),
		"wave": int(d.get("wave", 1)),
		"pilgrims": (d.get("pilgrims", []) as Array).size(),
	}


static func load_into(g: Game) -> bool:
	var d: Dictionary = state()
	if d.is_empty():
		return false
	return g.from_state(d)


static func clear() -> void:
	if not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(path)
