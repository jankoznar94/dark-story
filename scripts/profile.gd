class_name Profile
extends RefCounted

# PROFIL HRACE. To, co prezije partii: nasbirane BODY, permanentni upgrady,
# nejvyssi odemceny level a nejlepsi vyhrany level. Zlato tady NENI - to je
# bitevni mena a na kazdem levelu zacina znovu (rozhodnuto s Janem, Oct 2026).
#
# UKLADA SE PO KAZDE ZMENE (`save()`), ne az pri odchodu: hrac muze kdykoli
# zavrit zalozku a prijit o level, ktery uz vyhral. Na webu jde zapis do
# `user://` (Godot si ho drzi v IndexedDB), na desktopu do `~/.local/share`.
#
# VSE, CO SE UKLADA, JE JEDNO MISTO TADY. Kdo prida dalsi parametr, prida ho
# sem - jinak by se stav hry a stav na disku mohly rozejit.

const PATH := "user://zily2_progress.cfg"
const SECTION := "profil"

# ZAPIS NA DISK SE DA VYPNOUT. Testy a simulátor hrají desítky partii - kdyby
# ukládaly, prepsaly by hracuv skutecny postup (a hrac by prisel o levely).
# Vypina se JEDNOU na zacatku (`Profile.allow_save = false`).
static var allow_save: bool = true

var body: int = 0
# PERMANENTNI STUPNE: id upgradu -> kolik stupnu hrac koupil.
var perm: Dictionary = {}
# NEJVYSsi ODEMCENY LEVEL (od jedne) a nejlepsi VYHRANY level (nula = zadny).
var level: int = 1
var best: int = 0
# SATELITY: uroven kazdeho ze tri slotu (0 = jeste nestoji, 1-3 = stupen).
# Ktery slot je vubec odemceny, se NEPLATE - pocita se z `level`
# (`Upgrades.guard_slots`), takze se stav nemuze rozejit s pravidlem.
var guards: Array = [0, 0, 0]


func perm_level(id: String) -> int:
	return clampi(int(perm.get(id, 0)), 0, Upgrades.perm_max(id))


# KOUPE PERMANENTNIHO STUPNVE ZA BODY. Vraci true, kdyz se opravdu koupil -
# obrazovka i testy se ptaji na navratovou hodnotu, ne na to, "co se asi stalo".
func buy_perm(id: String) -> bool:
	var have: int = perm_level(id)
	if have >= Upgrades.perm_max(id):
		return false
	var cost: int = Upgrades.perm_cost(id, have)
	if body < cost:
		return false
	body -= cost
	perm[id] = have + 1
	save()
	return true


func guard_level(i: int) -> int:
	if i < 0 or i >= guards.size():
		return 0
	return clampi(int(guards[i]), 0, Upgrades.GUARD_MAX)


# KOUPE STUPNE STRAZCE ZA BODY. Vraci true, kdyz se opravdu koupil. Odemceny
# slot je podminka - bez ni by sel koupit strazce do slotu, ktery hrac jeste
# nema (a UI by ukazovalo neco jineho, nez co plati).
func buy_guard(i: int) -> bool:
	if i < 0 or i >= guards.size():
		return false
	if Upgrades.guard_slots(level) <= i:
		return false
	var have: int = guard_level(i)
	if have >= Upgrades.GUARD_MAX:
		return false
	var cost: int = Upgrades.guard_cost(have)
	if cost <= 0 or body < cost:
		return false
	body -= cost
	guards[i] = have + 1
	save()
	return true


func add_body(n: int) -> void:
	if n <= 0:
		return
	body += n
	save()


# VYHRANY LEVEL: odemkne dalsi a posune nejlepsi vysledek. Odemceny level se
# neuklada zvlast - je to proste "nejvyssi, kam se hrac dostal".
func clear_level(n: int) -> void:
	best = maxi(best, n)
	level = maxi(level, n + 1)
	save()


func reset() -> void:
	body = 0
	perm = {}
	level = 1
	best = 0
	guards = [0, 0, 0]
	save()


func save() -> void:
	if not allow_save:
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "body", body)
	cfg.set_value(SECTION, "level", level)
	cfg.set_value(SECTION, "best", best)
	cfg.set_value(SECTION, "perm", perm)
	cfg.set_value(SECTION, "guards", guards)
	cfg.save(PATH)


# NACTENI JE TICHE A BEZPECNE: kdyz soubor neni (nebo je poskozeny), hra zacina
# od nuly. Hrac nikdy nesmi videt chybu loadu - jen novy profil.
func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	body = maxi(0, int(cfg.get_value(SECTION, "body", 0)))
	level = maxi(1, int(cfg.get_value(SECTION, "level", 1)))
	best = maxi(0, int(cfg.get_value(SECTION, "best", 0)))
	var g: Variant = cfg.get_value(SECTION, "guards", [0, 0, 0])
	guards = [0, 0, 0]
	if typeof(g) == TYPE_ARRAY:
		for i in range(mini(3, (g as Array).size())):
			guards[i] = clampi(int(g[i]), 0, Upgrades.GUARD_MAX)
	var p: Variant = cfg.get_value(SECTION, "perm", {})
	perm = {}
	if typeof(p) == TYPE_DICTIONARY:
		for k in p:
			var id: String = String(k)
			if Upgrades.perm_max(id) > 0:
				perm[id] = clampi(int(p[k]), 0, Upgrades.perm_max(id))


# TEXT PRO MENU: "Level 4 · body 120 · nejlepší 3".
func menu_note() -> String:
	if best <= 0:
		return "Level 1 · body %d" % body
	return "Level %d · body %d · nejlepší %d" % [level, body, best]
