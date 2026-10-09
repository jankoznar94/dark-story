class_name Guide
extends RefCounted

# NAVOD. Strucne, obrazkove a hlavne mimo herni desku - na desku se zadny
# text nevejde, kazdy radek by ubral misto poutnikum.
#
# Neni to souvisly text. Je to pet BLOKU a kazdy blok je OBRAZEK s jednou
# kratkou vetou:
#
#   [ nakreslene schema ]   Výhybka
#                           Klepni na úsek.
#
# Obrazky kresli hra sama (_guide_switch, _guide_damage, ...) stejnymi
# znackami zivlu jako deska, proto jsou v game_view. Tady je jen to, co se
# da merit: texty bloku. Test diky tomu overi, ze je navod opravdu STRUCNY
# (kazdy popisek ma nejvyce MAX_WORDS slov) a ze pro kazdy blok existuje
# obrazek. Obe veci se snadno rozbijou a nikdo si toho na velkem monitoru
# nevsimne.

const TITLE := "NÁVOD"
const BACK := "ZPĚT"
# Strucnost je pozadavek, ne styl. Delsi vetu navod nema - delsi veta se
# na telefonu neprecte a navod se rozpadne na odstavec.
const MAX_WORDS := 8
const MIN_PX := 9
const MAX_PX := 16

# Bloky navodu. "art" je jmeno funkce v game_view, ktera ten obrazek kresli.
const BLOCKS := [
	{
		"art": "_guide_switch",
		"title": "Výhybka",
		"text": "Klepni na úsek. Poutníci půjdou tam.",
	},
	{
		"art": "_guide_damage",
		"title": "Poškození",
		"text": "Bere celý úsek. Protiklad ×2, vlastní nic.",
	},
	{
		"art": "_guide_bonus",
		"title": "Bonus",
		"text": "Klepni na místo s runou. Další klepnutí vylepší.",
	},
	{
		"art": "_guide_exit",
		"title": "Výstup",
		"text": "Kdo dojde, stojí život.",
	},
	{
		"art": "_guide_lane",
		"title": "Úseky",
		"text": "Šedý bere všem stejně, 100 %.",
	},
]


# Zalomi kratky popisek na radky, ktere se vejdou do `max_w` pri velikosti
# pisma `px`. Nadpis bloku se nezalamuje - je kratky.
static func caption(font: Font, px: int, max_w: float, text: String) -> Array:
	var out: Array = []
	var line: String = ""
	for word in text.split(" ", false):
		var cand: String = word if line.is_empty() else line + " " + word
		if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= max_w:
			line = cand
		else:
			if not line.is_empty():
				out.append(line)
			line = word
	if not line.is_empty():
		out.append(line)
	return out


# Sirka obrazku v bloku. Obrazek je vzdy vlevo, text vpravo.
static func art_width(avail_w: float, block_h: float, wide: bool) -> float:
	return minf(avail_w * 0.42, block_h * 1.9)


# Nejmensi velikost pisma, pri ktere se vsechny popisky vejdou do svych bloku
# a obrazkum zustane rozumne misto. Vraci -1, kdyz se nevejdou ani pri MIN_PX.
static func fit_px(font: Font, avail_w: float, avail_h: float, wide: bool) -> int:
	var count: int = BLOCKS.size()
	if count == 0:
		return MAX_PX
	var px: int = MAX_PX
	while px >= MIN_PX:
		var cols: int = 2 if wide else 1
		var rows: int = int(ceil(float(count) / float(cols)))
		var cell_w: float = avail_w / float(cols)
		var block_h: float = (avail_h - float(px) * 1.9) / float(rows)
		if block_h < float(px) * 2.6:
			px -= 1
			continue
		var aw: float = art_width(cell_w, block_h, wide)
		var tw: float = cell_w - aw - float(px) * 1.6
		if tw < float(px) * 4.0:
			px -= 1
			continue
		var max_lines := 1
		for b in BLOCKS:
			max_lines = maxi(max_lines, caption(font, px, tw, str(b["text"])).size() + 1)
		if block_h >= float(px) * 1.45 * float(max_lines) + float(px) * 0.6:
			return px
		px -= 1
	return -1


# Kolik slov ma nejdelsi popisek. Test hlida strucnost.
static func longest_caption_words() -> int:
	var n := 0
	for b in BLOCKS:
		n = maxi(n, str(b["text"]).split(" ", false).size())
	return n
