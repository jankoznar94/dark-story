class_name Campaign
extends RefCounted

# POSTUP HROU. Kolik levelu ma hrac dohrano a ktery level si muze zahrat.
#
# Jan (Oct 2026): "Po výhře levelu se musí hráč vrátit zpět do výběru levelů,
# musí se odemknout následující level a vyhraný se musí označit jako vyhraný."
#
# Je to JEDNO misto, kde o postupu neco vime:
#   * `is_unlocked` - prvni level je odemceny vzdy, dalsi az po vyhre
#     predchoziho. Nic se neuklada zvlast ("odemceno") - odemyka se tim, ze
#     je predchozi vyhrany, takze se stav nemuze rozejit.
#   * `is_cleared` - vyhrany level. V seznamu se oznaci a nikdy se nezamyka
#     zpatky.
#   * `mark_cleared` - zapise vyhru a ULOZI ji. Hrac si postup nesmi ztratit
#     zavrenim prohlizece.
#
# Uklada se lokalne (`user://progress.cfg`), jako vsechno ostatni v teto hre:
# na server se neposila nic.

const PATH := "user://progress.cfg"
const SECTION := "campaign"

# Indexy vyhranych levelu kamennym seznamem (ConfigFile umi jen zakladni
# typy). Poradi neni dulezite - rozhoduje `has`.
var cleared: Array = []


func load_from_disk() -> void:
	cleared = []
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var raw: String = str(cfg.get_value(SECTION, "cleared", ""))
	for part in raw.split(",", false):
		var n: int = int(part)
		if n >= 0 and not cleared.has(n):
			cleared.append(n)


func save() -> void:
	var cfg := ConfigFile.new()
	# Nacteme, co v souboru je, aby se neprepsaly jine sekce (kdyby nejake
	# casem pribyly) - zapisujeme jen sve klice.
	cfg.load(PATH)
	var parts: Array = []
	for n in cleared:
		parts.append(str(int(n)))
	cfg.set_value(SECTION, "cleared", ",".join(parts))
	cfg.save(PATH)


func reset() -> void:
	cleared = []
	save()


# KOLIK LEVELU KAMPAN MA. Bere se primo z zakotvenych levelu, aby se pocet
# nemusel psat dvakrat.
static func level_count() -> int:
	return BuiltinLevels.LEVELS.size()


static func level_name(i: int) -> String:
	if i < 0 or i >= level_count():
		return "?"
	return str(BuiltinLevels.LEVELS[i]["name"])


# NACTENY LEVEL K HRANI. Level dostava JMENO ZE SEZNAMU (hrac tak v HUDu vidi
# "Level 1", ne jmeno, ktere si level nese uvnitr sveho kodu) - sam kod se
# ale nemeni, takze se porad da precist a zapsat znak po znaku.
static func make_level(i: int) -> Level:
	if i < 0 or i >= level_count():
		return null
	var code: String = str(BuiltinLevels.LEVELS[i]["code"])
	var lv := Level.from_code(code)
	if lv == null:
		return null
	lv.name = level_name(i)
	return lv


func is_cleared(i: int) -> bool:
	return cleared.has(i)


func is_unlocked(i: int) -> bool:
	if i <= 0:
		return level_count() > 0
	return is_cleared(i - 1)


# ZAPIS VYHRY. Vraci true, kdyz se neco zmenilo (a ulozilo) - obrazovka se
# tak nemusi ptat, jestli ma neco delat.
func mark_cleared(i: int) -> bool:
	if i < 0 or i >= level_count() or is_cleared(i):
		return false
	cleared.append(i)
	save()
	return true
