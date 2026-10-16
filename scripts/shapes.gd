class_name Shapes
extends RefCounted

# GEOMETRIE TVARU POUTNIKU. Jsou tu jen BODY tvaru, kresleni je v `game_view` -
# diky tomu se da tvar OTESTOVAT bez prohlizece. Barvocit nestoji na tom, ze si
# hrac rozdilu vsimne az ve hre (cervena se zelenou je nejcastejsi porucha).
#
# TVAR MA "OBLICEJ": vsechno je nakreslene tak, ze NAHORU (0,-1) je vrchol /
# rameno / brisko. `toward` je smer, kterym ma tvar hledet - u poutniku je to
# smer k vezi (Jan, Oct 2026: "všichni nepřátelé by měli k věži směřovat
# 'obličejem'. Trojúhelník jedno z vrcholů, ne stěnou. Kapka bříškem, ne
# stranou.").
#
# CTVEREC A KRUH SE NEOTACI a vraceji PRAZDNE pole - kresli je obrazovka
# z geometrie (obdelnik, kruh). Ctverec otoceny o 45 stupnu vypada jako
# kosoctverec fialove, a to je jina barva, ne orientace.

static func pts(shape: String, c: Vector2, r: float,
		toward: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var raw: PackedVector2Array = _canonical(shape, r)
	if raw.is_empty():
		return PackedVector2Array()
	var face: Vector2 = _face_dir(shape, toward)
	var out := PackedVector2Array()
	for v in raw:
		out.append(c + _turn(v, face))
	return out


# KAM MA TVAR HLEDET. Kapka ma brisko DOLE, takze aby se brisko dotklo veze,
# otaci se OBRACENE nez ostatni tvary (vrchol/rameno maji nahoru).
static func _face_dir(shape: String, toward: Vector2) -> Vector2:
	if toward == Vector2.ZERO:
		return Vector2.ZERO
	if shape == "droplet":
		return -toward.normalized()
	return toward.normalized()


# OTOCENI BODU: (0,-1) tvaru se prevede na smer `face`, (1,0) na kolmici k nemu.
# Kdo otaci jinak nez tudy, otaci tvary kazdy jinam - proto je tu jedina cesta.
static func _turn(v: Vector2, face: Vector2) -> Vector2:
	if face == Vector2.ZERO:
		return v
	return Vector2(-face.y, face.x) * v.x - face * v.y


static func _canonical(shape: String, r: float) -> PackedVector2Array:
	match shape:
		"triangle":
			return PackedVector2Array([
				Vector2(0.0, -1.00 * r),
				Vector2(-0.95 * r, 0.70 * r),
				Vector2(0.95 * r, 0.70 * r)])
		"droplet":
			return PackedVector2Array([
				Vector2(0.0, -1.15 * r),
				Vector2(-0.68 * r, -0.20 * r),
				Vector2(-0.80 * r, 0.35 * r),
				Vector2(0.0, 0.95 * r),
				Vector2(0.80 * r, 0.35 * r),
				Vector2(0.68 * r, -0.20 * r)])
		"diamond":
			return PackedVector2Array([
				Vector2(0.0, -0.95 * r),
				Vector2(0.95 * r, 0.0),
				Vector2(0.0, 0.95 * r),
				Vector2(-0.95 * r, 0.0)])
		"cross":
			# 12 bodu: dve ramena jako JEDEN polygon. Driv se krize kreslila
			# dvema obdelniky a u ducha (obrysu) se jedno rameno vyplnovalo
			# podkladem - v obrysu po nem zustala dira.
			var a: float = 0.28 * r
			var b: float = 1.00 * r
			return PackedVector2Array([
				Vector2(-a, -b), Vector2(a, -b), Vector2(a, -a), Vector2(b, -a),
				Vector2(b, a), Vector2(a, a), Vector2(a, b), Vector2(-a, b),
				Vector2(-a, a), Vector2(-b, a), Vector2(-b, -a), Vector2(-a, -a)])
	return PackedVector2Array()


# KAM POUTNIK HLEDI - pro obrazovku i pro testy, aby se smer neopisoval zvlast.
# Poutnik jde porad PRIMO k vezi, takze jeho smer je i smer, kterym se otaci.
# PRERUSOVANA CARA (mrzivy paprsek). Vraci seznam usecek [od, do], ktere se maji
# nakreslit; to, ze mezi nimi jsou mezery, je z toho "chlad". Je to VYPOCET, ne
# kresleni - da se proto otestovat bez prohlizece.
static func dash(a: Vector2, b: Vector2, w: float) -> Array:
	var out: Array = []
	var d: float = (b - a).length()
	if d <= 0.001:
		return out
	var seg: float = maxf(6.0, w * 2.5)
	var n: int = maxi(1, int(round(d / seg)))
	for i in range(n):
		var t0: float = float(i) / float(n)
		out.append([a.lerp(b, t0), a.lerp(b, t0 + 0.6 / float(n))])
	return out


# SPOJENY TVAR SMESI. Jan: "Červená (čtverec) + žlutá (trojúhelník) = oranžová
# (čtverec se zobákem, jak kdybych přilepil rovnostranný trojúhelník na jednu
# stranu čtverce)". Vraci DVA polygony: prvni tvar v plne velikosti a druhy
# zmenseny, posunuty "na cumak" (poutnik jde k vezi oblicejem, takze cumak je
# smerem k vezi). Je to VYPOCET, ne kresleni - da se otestovat bez prohlizece.
static func pts_pair(a: String, b: String, c: Vector2, r: float, face: Vector2) -> Array:
	var dir: Vector2 = face.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var out: Array = [_poly(a, c, r, face)]
	out.append(_poly(b, c + dir * (r * 0.95), r * 0.62, face))
	return out


# TVAR JAKO POLYGON I PRO CTVEREC. Ctverec v `Shapes` schvalne neni (kresli se
# pres `draw_rect` a NEOTACI SE - otoceny je kosostverec, a to je jina barva),
# ale spojeny tvar smesi ho potrebuje taky. Sklada se proto tady a vzdy rovne.
static func _poly(shape: String, c: Vector2, r: float, face: Vector2) -> PackedVector2Array:
	if shape == "square":
		return PackedVector2Array([
			c + Vector2(-0.80 * r, -0.80 * r), c + Vector2(0.80 * r, -0.80 * r),
			c + Vector2(0.80 * r, 0.80 * r), c + Vector2(-0.80 * r, 0.80 * r)])
	return pts(shape, c, r, face)


static func facing(dir: Vector2) -> Vector2:
	return dir.normalized()
