class_name Menu
extends RefCounted

# KTERA OBRAZOVKA JE OTEVRENA. Hra sama o sobe nic nekresli ani necte vstup -
# tady je jen stav, aby se podle nej dalo kreslit i klepat.

enum View { MENU, BATTLE, UPGRADES }

# Polozky menu. Akce se vyhodnocuji PRES JMENO, ne podle poradi.
const ITEMS := ["HRÁT", "VYLEPŠENÍ"]
const SUBS := ["hraj od nejvyššího levelu", "permanentní upgrady za body"]
const ACTIONS := ["battle", "upgrades"]

var view: int = View.MENU
var build_id: String = "dev"


func open_menu() -> void:
	view = View.MENU


func open_battle() -> void:
	view = View.BATTLE


func open_upgrades() -> void:
	view = View.UPGRADES


func is_menu() -> bool:
	return view == View.MENU


func is_battle() -> bool:
	return view == View.BATTLE


func is_upgrades() -> bool:
	return view == View.UPGRADES
