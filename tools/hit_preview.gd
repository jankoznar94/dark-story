extends SceneTree
# NAHLED: efekt zasahu + prstence urovni (jen pro vyvoj).
#
# Vykresli realnou obrazovku hry (vez, poutnici, HUD) a pres ni efekt zasahu,
# ktery hra zatim nema. Poutnici maji vsechny ctyri urovne (0..3), takze je
# videt i nove prerusovani HP prstence.
#
#   --fx=0  zadny efekt (srovnani)
#   --fx=1  jiskra v miste dopadu
#   --fx=2  zhave jadro v tele poutnika
#   --fx=3  sleh (curlici paprsky z místa dopadu)

const GLYPH := Color(0.09, 0.085, 0.09)
const PLATE := Color(0.10, 0.095, 0.105, 0.88)
const FX_NAMES := [
	"B · Žhavé jádro (hotovo)",
	"A · Jiskra v místě dopadu",
	"B · Žhavé jádro (jen telo)",
	"C · Šleh",
]

var view: Node2D = null
var overlay: Node2D = null
var frame: int = 0
var fx: int = 1
var clock: float = 0.30
var out_path: String = "user://fx.png"
var phase: float = 0.0
var beams: Array = []
var shots: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clock="):
			clock = float(a.split("=")[1])
		elif a.begins_with("--fx="):
			fx = int(a.split("=")[1])
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
	print("SAVED ", out_path, " ", img.get_width(), "x", img.get_height(), "  ", FX_NAMES[fx])
	return true


func _setup() -> void:
	view.menu.open_battle()
	view.game.start_level(1)
	view._sync_shop_shape()
	view._refield()
	var g: Game = view.game
	g.phase = "build"
	g.build_left = 99999.0
	g.tower.hues = [Hue.RED, Hue.YELLOW]
	g.pilgrims = []
	var c: Vector2 = g.center
	var fr: float = g.field_r
	# CTYRI UROVNE VEDLE SEBE: 0 = plna cara, 1 = carkovana, 2 = teckovana,
	# 3 = carky + tecky.
	var spots: Array = [
		[2.62, 0.70, Hue.RED, 0],
		[3.14, 0.86, Hue.YELLOW, 1],
		[3.66, 0.72, Hue.BLUE, 2],
		[0.26, 0.82, Hue.GREEN, 3],
	]
	shots = []
	for s in spots:
		var p: Pilgrim = g.spawn_at_angle(float(s[0]), int(s[2]), int(s[3]))
		p.pos = c + Vector2(cos(float(s[0])), sin(float(s[0]))) * (fr * float(s[1]))
		p.dir = Vector2.ZERO
		p.hp = p.max_hp * 0.68
		# ZASAH: hra nastavuje `burning_now` kazdy snimek, dokud paprsek sviti.
		# V nahledu je hra zastavena, takze si ho nastavime sami - kresli se
		# REALNY efekt z `_draw_pilgrim`.
		p.burning_now = true
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
	overlay = Node2D.new()
	overlay.z_index = 100
	overlay.draw.connect(_paint)
	view.add_child(overlay)
	# HRA SE ZASTAVI: `step()` kazdy snimek maze `beams` (pocita je z zamku),
	# takze by nahled prisel o paprsky. Vypnuty `_process` obrazovky nechá stav
	# presne tak, jak ho tu postavime - a kresleni funguje dal.
	view.game.beams = beams
	view.game.clock = clock  # faze pulsu (0..2,2 = jeden pruchod vlny)
	view.set_process(false)


func _pin() -> void:
	# Kresli se i RODIC: vypnuty `_process` uz sam `queue_redraw` nevola, takze
	# by na platne zustal snimek z doby pred `_setup` (menu).
	view.queue_redraw()
	overlay.queue_redraw()


func _paint() -> void:
	var g: Game = view.game
	if fx > 0:
		var col: Color = g.tower.color()
		for p in shots:
			if fx == 1:
				_spark(p, col, g)
			elif fx == 2:
				_heat(p, col, g)
			elif fx == 3:
				_splash(p, col, g)
	_label()


# A · JISKRA V MISTE DOPADU: kratky zary krizek na tele poutnika, presne tam,
# kde konci paprsek. Sirka i delka dychaji s pulsem paprsku.
func _spark(p: Pilgrim, col: Color, g: Game) -> void:
	var dir: Vector2 = (p.pos - g.center).normalized()
	var at: Vector2 = p.pos - dir * g.pilgrim_hit_r(p)
	var r: float = g.pilgrim_r() * p.size
	var k: float = 0.65 + 0.35 * sin(phase * 9.0)
	var arm: float = r * 0.85 * k
	var col2: Color = col.lerp(Color(1, 1, 1), 0.65)
	var n: Vector2 = dir.orthogonal()
	overlay.draw_line(at - dir * arm, at + dir * arm, GLYPH, r * 0.34)
	overlay.draw_line(at - n * arm, at + n * arm, GLYPH, r * 0.34)
	overlay.draw_line(at - dir * arm, at + dir * arm, col2, r * 0.20)
	overlay.draw_line(at - n * arm, at + n * arm, col2, r * 0.20)
	overlay.draw_circle(at, r * 0.30 * k, Color(1, 1, 1, 0.85))
	overlay.draw_circle(at, r * 0.30 * k, GLYPH, false, r * 0.08)


# B · ZHAVE JADRO: telo poutnika dostane svetlejsi jadro (stejny odstin, jen
# svetlejsi) - barva zustava barvou poutnika, takze hrac porad vi, na co miri.
func _heat(p: Pilgrim, col: Color, g: Game) -> void:
	var r: float = g.pilgrim_r() * p.size
	var body: Color = Hue.color_of(p.hue)
	var k: float = 0.60 + 0.40 * sin(phase * 7.0)
	overlay.draw_circle(p.pos, Game.PILGRIM_HIT_FRAC * r * 0.62 * k,
		body.lerp(Color(1, 1, 1), 0.55))
	overlay.draw_circle(p.pos, Game.PILGRIM_HIT_FRAC * r * 0.30 * k,
		body.lerp(Color(1, 1, 1), 0.85))


# C · SLEH: z místa dopadu vyleti nekolik kratkych carek (plochy, bez blur).
func _splash(p: Pilgrim, col: Color, g: Game) -> void:
	var dir: Vector2 = (p.pos - g.center).normalized()
	var at: Vector2 = p.pos - dir * g.pilgrim_hit_r(p)
	var r: float = g.pilgrim_r() * p.size
	for i in 7:
		var a: float = dir.angle() + PI + (float(i) - 3.0) * 0.34
		var k: float = 0.55 + 0.45 * sin(phase * 8.0 + float(i) * 0.7)
		var d: Vector2 = Vector2(cos(a), sin(a))
		var l0: float = r * 0.18
		var l1: float = r * (0.55 + 0.35 * k)
		overlay.draw_line(at + d * l0, at + d * l1, GLYPH, r * 0.24)
		overlay.draw_line(at + d * l0, at + d * l1, col.lerp(Color(1, 1, 1), 0.5), r * 0.13)


func _label() -> void:
	var font: Font = ThemeDB.fallback_font
	var text: String = FX_NAMES[clampi(fx, 0, FX_NAMES.size() - 1)]
	var size: int = 22
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var box: Rect2 = Rect2((view.layout.view.x - tw) * 0.5 - 18.0, view.layout.bar_h + 10.0,
		tw + 36.0, float(size) + 20.0)
	overlay.draw_rect(box, PLATE)
	overlay.draw_rect(box, Color(0.55, 0.53, 0.50, 0.55), false, 2.0)
	overlay.draw_string(font, Vector2(box.position.x + 18.0, box.position.y + 13.0 + float(size) * 0.62),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.92, 0.90, 0.84))
