class_name Shapes
extends RefCounted

# GEOMETRIE, KTERA NENI POUTNIKUV TVAR. Poutnik ma od Oct 2026 tvar PUNTIKU
# s inicialami barvy (Jan: "Všichni budou mít tvar puntíku. V něm budou mít
# iniciály barvy nebo kombinace barev.") - tvary (ctverec, trojuhelnik, kapka,
# kriz, kosostverec) se tim ZRUSILY i s otacenim "oblicejem" k vezi: hrac z nich
# u smesi nepoznal, na kterou kombinaci ma mirrit.
#
# Zustava jen to, co se pocita a da se proto otestovat bez prohlizece:
#   * LEDOVY KRYSTAL (namrazovy prstenec kolem HP baru).
#
# PRERUSOVANA CARA (`Shapes.dash`, mrzivy paprsek) se ZRUSILA - Jan (Oct 2026):
# "Laser je teď čárkovaný... Nevím proč jsi to změnila. Starý laser byl lepší."


# LEDOVY KRYSTAL (namrazovy prstenec kolem poutnika). Jan (Oct 2026): "Zmrazení
# musíme znázornit jinak. Ten vnější kruh ještě kolem HP baru byl možná skutečně
# nejlepší řešení. Jen bych ho udělal tak, aby více evokoval zmrazení. Předtím
# spíš evokoval silové pole." a "Zkusme ledový krystal."
#
# PROC MNOHOUHELNIK A NE KRUH: silove pole je HLADKY kruh - stejne silny vsude,
# takze vypada jako hranice, ne jako stav. Krystal ma ROVNE STRANY a rohy, takze
# se cte jako krystal.
#
# PRAVIDELNY, NE ZUBATY. Jan (Oct 2026): "To vypadá blbě. Měl by to být normálně
# pravidelný hexagon nebo Oktagon." Nepravidelny obrys (kazdy vrchol jinde
# daleko) vypadal jako rozbita kresba, ne jako krystal.
#
# DEVITIHRAN. Jan vybiral z nahledu sesty/osmi/deviti/desetiuhelnik:
# "Devitihran je nejlepší" (Oct 2026). Mene stran = moc hrotu, vic stran = obrys
# je skoro kruh a vraci se to silove pole, ktere mel krystal nahradit.
#
# VZDALENOSTI JSOU TU, NE V OBRAZOVCE: krystal se nesmi dotknout prstence
# (= HP bar na 1,0) ani jedoveho krouzku (2,35 tela = 1,382 prstence), a to se
# tak da OTESTOVAT bez prohlizece.
#
# Je to VYPOCET, ne kresleni (a zadne losovani za behu).
const CRYSTAL_SIDES := 9            # devitihran (Jan, Oct 2026)
const CRYSTAL_RADIUS := 1.25        # vsechny vrcholy stejne daleko (opsana kruznice)


# PRSTENEC POUTNIKA (= HP bar) SE PRERUSUJE PODLE UROVNE BARVY (Jan, Oct 2026:
# "Plná čára lvl1, čárkovaná lvl2, tečkovaná lvl3, kombinace čárek a teček
# lvl4"). Velikost sama o sobe uroven necte - rozdil mezi sousednimi urovnemi
# je 12 %, coz hrac na telefonu nepozna. Prerusovani je druha, nezavisla cesta
# k informaci (cte se i bez barev).
#
# Je to VYPOCET, ne kresleni: vraci seznam oblouku (dvojice uhlu od 0), ktere
# obrazovka vykresli. `sweep` = kolik z kruhu odpovida zbyvajicim zivotum.
const RING_CELLS := 48
const RING_DASH := [1, 1, 1, 1, 1, 0, 0, 0]     # lvl2: cara (5 Policek, 3 mezera)
const RING_DOT := [1, 0, 0, 0]                  # lvl3: tecka (1 policko, 3 mezera)
const RING_DASH_DOT := [1, 1, 1, 0, 1, 0]       # lvl4: carka, mezera, tecka, mezera


static func hp_ring_marks(tier: int, sweep: float) -> Array:
	var end: float = clampf(sweep, 0.0, TAU)
	if end <= 0.0:
		return []
	var lvl: int = clampi(tier, 0, 3)
	if lvl == 0:
		return [Vector2(0.0, end)]
	var pattern: Array = RING_DASH if lvl == 1 else (RING_DOT if lvl == 2 else RING_DASH_DOT)
	var cells: float = end / TAU * float(RING_CELLS)
	var out: Array = []
	var i: int = 0
	while float(i) < cells:
		if int(pattern[i % pattern.size()]) == 0:
			i += 1
			continue
		var start: int = i
		while float(i) < cells and int(pattern[i % pattern.size()]) == 1:
			i += 1
		var a0: float = TAU * float(start) / float(RING_CELLS)
		var a1: float = TAU * float(i) / float(RING_CELLS)
		# TECKA je jedno policko - jako oblouk by nemela skoro zadnou delku,
		# takze dostane minimum, aby ji hrac vubec videl.
		if i - start <= 1:
			a1 = a0 + TAU * 1.6 / float(RING_CELLS)
		# PRSTENEC JE HP BAR: ani tecka, ani cara nesmi prelezt za zbyvajici
		# zivoty (jinak by hrac videl zivoty, ktere uz nepoutnik nema).
		out.append(Vector2(a0, minf(a1, end)))
	return out


# NEJBLIZSI BOD STRANY. U pravidelneho mnohouhelniku se STRED STRANY dostane
# k poutnikovi bliz nez vrchol - a ten se nesmi dotknout prstence (= HP bar).
static func crystal_inner() -> float:
	return CRYSTAL_RADIUS * cos(PI / float(CRYSTAL_SIDES))


# VRCHOL NAHORU (ne strana): krystal je tim soumerny a hrac ho cte stejne jako
# prstenec zivotu, ktery taky zacina nahore.
static func crystal_ring(c: Vector2, ring_r: float,
		sides: int = CRYSTAL_SIDES) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = maxi(3, sides)
	for i in range(n):
		var a: float = -PI * 0.5 + TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * ring_r * CRYSTAL_RADIUS)
	return out
