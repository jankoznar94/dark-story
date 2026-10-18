extends SceneTree
# NAHLEDOVE OKNO PRO VARIANTY LASERU (jen pro vyvoj, do hry nezasahuje).
#
# Vyrenderuje JEDEN snimek bitvy (realna obrazovka hry - pozadi, vez, poutnici,
# HUD) a paprsek v tom miste nakresli zvolenou variantou. Varianty jsou psane
# stejnymi volanimi, jakymi by sly do `_draw_beams` v `game_view.gd`, takze co
# je videt tady, je presne to, co by hrac videl.
#
# Spusteni:
#   ~/tools/godot/godot4 --path . --rendering-driver opengl3 --resolution 960x600 \
#       --script res://tools/laser_variants.gd -- --variant=1 --out=/tmp/laser1.png

const NAMES := [
	"TEĎ (současný)",
	"1 · Vrstvené světlo",
	"2 · Neonové lišty",
	"3 · Pulzní tok",
	"4 · Tryska",
	"5 · Nit a jiskry",
]
const GLYPH := Color(0.09, 0.085, 0.09)
const PLATE := Color(0.10, 0.095, 0.105, 0.88)

var view: Node2D = null
var overlay: Node2D = null
var frame: int = 0
var variant: int = 0
var out_path: String = "user://laser.png"
var phase: float = 0.0
var beams: Array = []
var shots: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			variant = int(a.split("=")[1])
		elif a.begins_with("--out="):
			out_path = a.split("=")[1]


func _process(d: float) -> bool:
	frame += 1
	phase += d
	if frame == 1:
		view = load("res://main.tscn").instantiate()
		root.add_child(view)
		return false
	if frame == 2:
		_setup()
		return false
	if frame < 8:
		_pin()
		return false
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("NO_IMAGE")
		return true
	img.save_png(out_path)
	print("SAVED ", out_path, " ", img.get_width(), "x", img.get_height(),
		"  ", NAMES[clampi(variant, 0, NAMES.size() - 1)])
	return true


func _setup() -> void:
	view.menu.open_battle()
	view.game.start_level(1)
	view._sync_shop_shape()
	view._refield()
	var g: Game = view.game
	# ZADNA VLNA: hra zustava ve fazi pripravy, takze se nic nehybe a nic
	# neumira, ale obrazovka se kresli jako bitva (zadny PAUZA text).
	g.phase = "build"
	g.build_left = 99999.0
	# VEZ JE SMES (oranzova) - na teple barve je svetlo nejlip videt.
	g.tower.hues = [Hue.RED, Hue.YELLOW]
	g.pilgrims = []
	var c: Vector2 = g.center
	var fr: float = g.field_r
	var spots: Array = [
		[2.62, 0.72, Hue.RED],
		[3.14, 0.86, Hue.YELLOW],
		[3.66, 0.74, Hue.BLUE],
		[0.26, 0.80, Hue.GREEN],
	]
	shots = []
	for s in spots:
		var p: Pilgrim = g.spawn_at_angle(float(s[0]), int(s[2]), 0)
		p.pos = c + Vector2(cos(float(s[0])), sin(float(s[0]))) * (fr * float(s[1]))
		p.hp = p.max_hp * 0.72
		shots.append(p)
	beams = []
	for p in shots:
		var dir: Vector2 = (p.pos - c).normalized()
		beams.append({
			"from": c + dir * g.tower_edge_r(),
			"to": p.pos - dir * g.pilgrim_hit_r(p),
			"hop": 0,
			"target": p,
		})
	# JEDEN ODRAZ (hop 1) mezi dvema pravymi poutniky - aby bylo videt, jak
	# varianta vypada na uzsim paprsku.
	var a: Pilgrim = shots[3]
	var b: Pilgrim = shots[0]
	beams.append({
		"from": a.pos,
		"to": b.pos,
		"hop": 1,
		"target": b,
	})
	print("LAYOUT view=", view.layout.view, " arena=", view.layout.arena, " center=", g.center, " field_r=", g.field_r, " unit_r=", g.unit_r, " bar_h=", view.layout.bar_h)
	print("PILGRIMS ", shots.size(), " beams ", beams.size())
	overlay = Node2D.new()
	overlay.z_index = 100
	overlay.draw.connect(_paint)
	view.add_child(overlay)


func _pin() -> void:
	# Paprsek kresli JEN overlay (jinak by pod nim prosvital stary tenky).
	var g: Game = view.game
	g.beams = []
	g.phase = "build"
	g.build_left = 99999.0
	for s in shots:
		s.dir = Vector2.ZERO
	overlay.queue_redraw()


# ---------------------------------------------------------------- KRESLENI
func _paint() -> void:
	var g: Game = view.game
	var col: Color = g.tower.color()
	if variant == 0:
		col = Color(col.r, col.g, col.b, 1.0)
	for b in beams:
		var w: float = maxf(1.0, g.beam_w(int(b["hop"])))
		_one(b["from"], b["to"], col, w)
	_label()


func _one(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	match variant:
		0:
			# PRESNE DNE SNI: obrys + jedna cara (co je ve hre ted).
			_line(a, b, GLYPH, w + 1.7)
			_line(a, b, c, w)
		1:
			# TRI VRSTVY SVETLA: siroky pruhledny obal, uzsi jasnejsi obal,
			# barevne telo a svetle jadro. Vsechno PLOCHA (zadny blur) - kazda
			# dalsi vrstva je jen svetlejsi a uzsi, oko si z toho slozi zareni.
			_line(a, b, GLYPH, w + 9.0)
			_line(a, b, Color(c.r, c.g, c.b, 0.10), w * 4.6)
			_line(a, b, Color(c.r, c.g, c.b, 0.22), w * 3.0)
			_line(a, b, Color(c.r, c.g, c.b, 0.50), w * 1.9)
			_line(a, b, c.lightened(0.18), w * 1.15)
			_line(a, b, c.lerp(Color(1, 1, 1), 0.62), w * 0.55)
		2:
			# NEONOVE LISTY: bile jadro a po jeho stranach dve barevne linky.
			# Paprsek je tim "trubice", ktera sviti - a zustava ostry.
			_line(a, b, GLYPH, w + 10.0)
			var n: Vector2 = (b - a).orthogonal().normalized()
			_line(a, b, Color(c.r, c.g, c.b, 0.30), w * 1.6)
			_line(a + n * w * 1.05, b + n * w * 1.05, c, w * 0.90)
			_line(a - n * w * 1.05, b - n * w * 1.05, c, w * 0.90)
			_line(a, b, c.lerp(Color(1, 1, 1), 0.85), maxf(1.0, w * 0.55))
		3:
			# PULZNI TOK: paprsek je slozeny z useku a jas v nich plyne od veze
			# k poutnikovi. Animovane to tece, ve snimku je videt smer.
			_line(a, b, GLYPH, w + 8.0)
			_line(a, b, Color(c.r, c.g, c.b, 0.20), w * 3.0)
			var n: int = 18
			for i in n:
				var t0: float = float(i) / float(n)
				var t1: float = float(i + 1) / float(n)
				var s: float = 0.5 + 0.5 * sin((t0 * 1.7 - phase * 1.6) * TAU)
				var f: float = pow(s, 3.0)
				var seg: Color = c.lerp(Color(1, 1, 1), 0.12 + 0.80 * f)
				_line(a.lerp(b, t0), a.lerp(b, t1), seg, w * (0.75 + 0.85 * f))
		4:
			# TRYSKA: od veze siroky, k poutnikovi uzky kuzel (plocha), uvnitr
			# barevne telo a bile jadro. Vypada jako projektor, ne jako nit.
			var n2: Vector2 = (b - a).orthogonal().normalized()
			var w0: float = w * 3.2
			var w1: float = w * 0.55
			var outer: PackedVector2Array = PackedVector2Array([
				a + n2 * w0, b + n2 * w1, b - n2 * w1, a - n2 * w0])
			overlay.draw_colored_polygon(outer, Color(c.r, c.g, c.b, 0.16))
			var mid0: float = w * 1.9
			var mid1: float = w * 0.38
			var mid: PackedVector2Array = PackedVector2Array([
				a + n2 * mid0, b + n2 * mid1, b - n2 * mid1, a - n2 * mid0])
			overlay.draw_colored_polygon(mid, Color(c.r, c.g, c.b, 0.40))
			_line(a, b, c.lightened(0.12), w * 0.85)
			_line(a, b, c.lerp(Color(1, 1, 1), 0.70), maxf(1.0, w * 0.38))
		5:
			# NIT A JISKRY: tenka bila nit, kolem barevna zar, a po paprsku
			# drobne castic - u veze huste, k poutnikovi ridnou.
			_line(a, b, GLYPH, w + 9.0)
			_line(a, b, Color(c.r, c.g, c.b, 0.14), w * 5.0)
			_line(a, b, Color(c.r, c.g, c.b, 0.34), w * 2.2)
			_line(a, b, c.lightened(0.10), w * 0.95)
			_line(a, b, Color(1, 1, 1, 0.94), maxf(1.0, w * 0.34))
			var n3: Vector2 = (b - a).orthogonal().normalized()
			for i in 11:
				var t: float = float(i) / 10.0
				var off: float = sin(float(i) * 2.4) * w * 2.1 * (1.0 - 0.4 * t)
				var pt: Vector2 = a.lerp(b, t) + n3 * off
				overlay.draw_circle(pt, maxf(1.0, w * (0.70 - 0.40 * t)),
					c.lerp(Color(1, 1, 1), 0.62))


# CARA S KULATYMI KONCI (stejne jako `_beam_line` ve hre).
func _line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	overlay.draw_line(a, b, c, w)
	overlay.draw_circle(a, w * 0.5, c)
	overlay.draw_circle(b, w * 0.5, c)


func _label() -> void:
	var font: Font = ThemeDB.fallback_font
	var text: String = NAMES[clampi(variant, 0, NAMES.size() - 1)]
	var size: int = 22
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var box: Rect2 = Rect2((view.layout.view.x - tw) * 0.5 - 18.0, view.layout.bar_h + 10.0,
		tw + 36.0, float(size) + 20.0)
	overlay.draw_rect(box, PLATE)
	overlay.draw_rect(box, Color(0.55, 0.53, 0.50, 0.55), false, 2.0)
	overlay.draw_string(font, Vector2(box.position.x + 18.0, box.position.y + 13.0 + float(size) * 0.62),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.92, 0.90, 0.84))
