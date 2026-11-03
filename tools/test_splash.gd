extends SceneTree
## tools/test_splash.gd — the PWA's `#splashScreen` on the port's launch.
##
## The failure this guards is not "the splash looks wrong on a screenshot": it is that the
## splash never goes away, or goes away at the wrong moment, or that the black card does not
## swallow the first tap of a launch. None of those is visible in a still frame, and all
## three make the game feel broken on a phone.
##
## Numbers asserted are the PWA's own, read off `public/style.css` and `src/game.ts`:
## content fade-in 800 ms starting at 300 ms, held to 2500 ms, then a 600 ms fade-out.
##
## Run:  godot --headless --path . --script res://tools/test_splash.gd
## Pass: prints SPLASH_ALL_PASS=true

const SplashScreen := preload("res://scripts/ui/splash_screen.gd")

var _failures: Array[String] = []
var _finished := 0


func _initialize() -> void:
	_test_assets()
	_test_fade_in()
	_test_hold_and_fade_out()
	_test_it_swallows_taps()
	_test_stops_ticking()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("SPLASH_ALL_PASS=true")
	else:
		print("SPLASH_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


## A splash built by hand: this runs inside `_initialize()`, before the tree propagates
## readiness, so `_ready()` is called explicitly (a node added here never gets it).
func _make():
	var splash = SplashScreen.new()
	splash._ready()
	splash.finished.connect(func() -> void: _finished += 1)
	return splash


func _advance(splash, _from_ms: float, _to_ms: float, step_ms: float = 16.0) -> void:
	var t: float = _from_ms
	while t < _to_ms:
		splash._tick(step_ms)
		t += step_ms


func _test_assets() -> void:
	var tex := load(SplashScreen.ICON_PATH) as Texture2D
	if tex == null:
		_fail("splash icon %s does not load" % SplashScreen.ICON_PATH)
		return
	var size := tex.get_size()
	if size != Vector2(512, 512):
		_fail("splash icon is %s, expected 512x512" % str(size))
	var image := tex.get_image()
	if image == null:
		return
	# The rounded corners are the port's `border-radius:24px`; without alpha the corners
	# would be a square block on the black backdrop's edge on a lighter screen.
	var corner := image.get_pixel(0, 0)
	if corner.a > 0.01:
		_fail("splash icon corner is opaque (a=%.2f) — the rounded mask is missing" % corner.a)
	if image.get_pixel(image.get_width() / 2, image.get_height() / 2).a < 0.9:
		_fail("splash icon centre is transparent — the mask ate the art")


func _test_fade_in() -> void:
	var splash = _make()
	if absf(splash.content_alpha()) > 0.01:
		_fail("content is visible at t=0 (alpha %.2f)" % splash.content_alpha())
	splash._tick(300.0)
	if splash.content_alpha() > 0.02:
		_fail("content is visible during the 300 ms delay (alpha %.2f)" % splash.content_alpha())
	splash._tick(400.0)
	var mid: float = splash.content_alpha()
	if mid < 0.3 or mid > 0.8:
		_fail("content alpha at 700 ms is %.2f, expected a partial fade-in" % mid)
	splash._tick(400.0)
	if absf(splash.content_alpha() - 1.0) > 0.02:
		_fail("content is not fully visible at 1100 ms (alpha %.2f)" % splash.content_alpha())
	if splash.modulate.a < 0.99:
		_fail("the overlay itself dimmed during the hold (alpha %.2f)" % splash.modulate.a)


func _test_hold_and_fade_out() -> void:
	var splash = _make()
	_advance(splash, 0.0, SplashScreen.HOLD_MS - 100.0)
	if splash.is_done():
		_fail("the splash finished before its %d ms hold" % int(SplashScreen.HOLD_MS))
	if splash.visible == false:
		_fail("the splash hid itself before the hold ended")
	# Half way through the fade-out: still there, but dimmed and NOT done.
	_advance(splash, SplashScreen.HOLD_MS - 100.0, SplashScreen.HOLD_MS + 300.0)
	if splash.is_done():
		_fail("the splash finished 300 ms into a 600 ms fade-out")
	var a: float = splash.modulate.a
	if a <= 0.05 or a >= 0.95:
		_fail("overlay alpha 300 ms into the fade-out is %.2f, expected partial" % a)
	_advance(splash, SplashScreen.HOLD_MS + 300.0, SplashScreen.HOLD_MS + SplashScreen.FADE_OUT_MS + 100.0)
	if not splash.is_done():
		_fail("the splash never finished after the fade-out")
	if splash.visible:
		_fail("the splash is still visible after finishing")
	if _finished != 1:
		_fail("`finished` was emitted %d times, expected exactly 1" % _finished)
	# Ticking a finished splash must not restart it.
	splash._tick(5000.0)
	if splash.visible:
		_fail("a finished splash became visible again")


func _test_it_swallows_taps() -> void:
	var splash = _make()
	if splash.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("the splash lets taps through to the screen hidden behind it")
	if splash.get_child_count() < 2:
		_fail("the splash has no backdrop/content children")
	var backdrop := splash.get_node_or_null("Backdrop") as ColorRect
	if backdrop == null:
		_fail("the splash has no black backdrop")
	elif backdrop.color != Color.BLACK:
		_fail("the splash backdrop is %s, expected black" % str(backdrop.color))
	var title := splash.get_node_or_null("Centre/Content/Title") as Label
	if title == null:
		_fail("the splash has no title label")
	elif title.text != "DUNGEON RECALL":
		_fail("the title reads '%s', expected 'DUNGEON RECALL' (uppercase, as CSS paints it)" % title.text)
	var icon := splash.get_node_or_null("Centre/Content/Icon") as TextureRect
	if icon == null:
		_fail("the splash has no icon")
	elif icon.custom_minimum_size != Vector2(SplashScreen.ICON_SIZE, SplashScreen.ICON_SIZE):
		_fail("the icon box is %s, expected 200x200" % str(icon.custom_minimum_size))


func _test_stops_ticking() -> void:
	var splash = _make()
	_advance(splash, 0.0, SplashScreen.HOLD_MS + SplashScreen.FADE_OUT_MS + 50.0)
	if splash.is_processing():
		_fail("a finished splash still ticks every frame")
