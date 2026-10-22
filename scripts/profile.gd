class_name Profile
extends RefCounted

# PROFIL HRACE. Prezije partii: BODY, permanentni upgrady, nejvyssi odemceny
# a nejlepsi vyhrany level. Thrower nema zadnou bitevni menu (zlato) - jedina
# mena jsou BODY za odrazene vlny a vyhrane levely.

const PATH := "user://thrower_progress.cfg"
const SECTION := "profil"

# Testy a simulace nesmi prepsat hracuv postup.
static var allow_save: bool = true

var body: int = 0
var perm: Dictionary = {}
var level: int = 1
var best: int = 0


func perm_level(id: String) -> int:
	return clampi(int(perm.get(id, 0)), 0, Upgrades.perm_max(id))


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


func add_body(n: int) -> void:
	if n <= 0:
		return
	body += n
	save()


func clear_level(n: int) -> void:
	best = maxi(best, n)
	level = maxi(level, n + 1)
	save()


func reset() -> void:
	body = 0
	perm = {}
	level = 1
	best = 0
	save()


func save() -> void:
	if not allow_save:
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "body", body)
	cfg.set_value(SECTION, "level", level)
	cfg.set_value(SECTION, "best", best)
	cfg.set_value(SECTION, "perm", perm)
	cfg.save(PATH)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	body = maxi(0, int(cfg.get_value(SECTION, "body", 0)))
	level = maxi(1, int(cfg.get_value(SECTION, "level", 1)))
	best = maxi(0, int(cfg.get_value(SECTION, "best", 0)))
	var p: Variant = cfg.get_value(SECTION, "perm", {})
	perm = {}
	if typeof(p) == TYPE_DICTIONARY:
		for k in p:
			var id: String = String(k)
			if Upgrades.perm_max(id) > 0:
				perm[id] = clampi(int(p[k]), 0, Upgrades.perm_max(id))


func menu_note() -> String:
	if best <= 0:
		return "Body %d" % body
	return "Body %d · nejlepší level %d" % [body, best]
