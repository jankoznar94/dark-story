class_name Guide
extends RefCounted

# Text NAVODU. Jedine misto ve hre, kde se vysvetluji pravidla - z herni
# desky zmizel kazdy popisek, protoze kazdy radek textu v desce je misto,
# ktere chybi poutnikum.
#
# Text je ZDROJ, ne hotove radky: na malem telefonu se musi zalomit podle
# skutecne sirky pisma. Kresleni i testy pouzivaji STEJNE `lay_out()`, takze
# test overi to, co hrac opravdu uvidi - a hlavne ze se na malem displeji
# neztrati ani slovo.
#
# Radek druhu "e" neni text, ale DVOJICE RUN (kdo je silny proti komu).
# Barva nesmi byt nikdy jediny nosic informace, proto je u kazde dvojice
# i jmeno zivlu.
#
# POZOR, dva chytáky, na kterych uz beh spadl:
#   1. Funkce se NESMI jmenovat `wrap` - to je vestavena funkce Godotu
#      (wrap(hodnota, min, max)) a prebije ji i uvnitr teto tridy.
#   2. Velikost pisma navodu se NESMI nasobit meritkem `ui`. Meri se
#      a kresli se ve SKUTECNYCH pixelech; kdyby se pri kresleni jeste
#      zmensila, hrac by videl jiny text, nez jaky test zmeril.

const TITLE := "NÁVOD"
const BACK := "ZPĚT"
# O kolik px je nadpis vetsi nez telo textu.
const TITLE_EXTRA := 7

const SOURCE := [
	["h", "Co je cílem"],
	["p", "Poutníci putují po žilách many. Každý, kdo dojde na výstup, stojí jeden život."],
	["p", "Cílem je zabít poutníka dřív, než tam dojde. Když se jich nahromadí víc, než stíháš odklízet, síť padne."],
	["h", "Přepínání výhybky"],
	["p", "Klepni na úsek a výhybka pošle příští poutníky na něj. Tlačítka žádná nejsou."],
	["p", "Vybraný úsek je světlejší, barvu ani runu ale nemění."],
	["h", "Poškození dělá celý úsek"],
	["e", ""],
	["p", "Čím déle jde poutník po úseku, tím víc ran dostane. Nezáleží na tom, kde přesně na něm stojí."],
	["p", "Neutrální úsek: všichni 100 %."],
	["p", "Elementární úsek: vlastní živel 0 %, jiný 50 %, protiklad 200 %."],
	["p", "Poslat poutníka na jeho vlastní úsek je ztráta — projde bez škrábnutí."],
	["h", "Bonusy"],
	["p", "Klepni na prázdné místo na úseku a postaví se bonus. Patří jen na úsek svého živlu."],
	["p", "Bonus posiluje celý úsek. Klepnutím na hotový bonus ho vylepšíš."],
	["p", "Na neutrálním úseku stavět nelze, už teď působí na všechny stejně."],
	["h", "Zlato a životy"],
	["p", "Zlato dostaneš za zabitého poutníka a za odraženou vlnu. Životy jsou společné pro celou síť."],
]

# Vyska radku v nasobcich velikosti pisma. Cim tesnejsi, tim vic textu se
# vejde na maly displej - a na malem displeji jde kazdy pixel.
const ROW_P := 1.38
const ROW_H := 1.70
const ROW_T := 2.40
const PAIR_ROW := 3.10
const MIN_PX := 9
const MAX_PX := 15


# Zalomi zdrojovy text na radky, ktere se vejdou do `max_w` pixelu pri
# velikosti pisma `px`. Nadpisy a radek s runami zustavaji jako vlastni radek.
static func lay_out(font: Font, px: int, max_w: float) -> Array:
	var out: Array = []
	for item in SOURCE:
		var kind: String = item[0]
		var text: String = item[1]
		if kind != "p":
			out.append([kind, text])
			continue
		var line: String = ""
		for word in text.split(" ", false):
			var cand: String = word if line.is_empty() else line + " " + word
			if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= max_w:
				line = cand
			else:
				if not line.is_empty():
					out.append(["p", line])
				line = word
		if not line.is_empty():
			out.append(["p", line])
	return out


# Vyska hotoveho bloku pri velikosti pisma `px`. Pocita se z TYCH SAMYCH
# radku, ktere se kresli - proto se do displeje vejde presne to, co se
# do nej vejit ma.
static func block_height(lines: Array, px: float) -> float:
	var h := px * ROW_T
	var head_gap := false
	for item in lines:
		match item[0]:
			"h":
				h += px * (ROW_H * (0.55 if head_gap else 1.0))
				head_gap = true
			"e":
				h += px * PAIR_ROW
			_:
				h += px * ROW_P
	return h


# Nejmensi velikost pisma, pri ktere se cely navod vejde do `max_h`.
# Vraci -1, kdyz se nevejde ani pri nejmensi - to je chyba rozvrzeni,
# proto to testy kontroluji.
static func fit_px(font: Font, max_w: float, max_h: float) -> int:
	var px: int = MAX_PX
	while px >= MIN_PX:
		if block_height(lay_out(font, px, max_w), float(px)) <= max_h:
			return px
		px -= 1
	return -1


# Kolik slov navod obsahuje. Test overuje, ze se pri zalamovani na malem
# displeji neztratilo ani jedno - ticha ztrata textu je presne ta chyba,
# ktera by se jinak poznala az na telefonu.
static func word_count(lines: Array) -> int:
	var n := 0
	for item in lines:
		if item[0] == "p" or item[0] == "h":
			n += str(item[1]).split(" ", false).size()
	return n


static func source_word_count() -> int:
	var n := 0
	for item in SOURCE:
		n += str(item[1]).split(" ", false).size()
	return n
