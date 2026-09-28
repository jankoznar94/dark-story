extends SceneTree
## tools/probe_lock_icon.gd — what is actually IN the padlock texture, pixel by pixel.
##
## Jan's report ("every dot says 0") is fixed in the logic, but the capture of the road showed the
## stations that have NOT opened as a SOLID WHITE 18x18 square where the padlock should be. A
## solid square is not a scaled padlock, so either the imported texture is not what the .png holds
## or something draws over it. This reads the IMAGE the engine actually has, which is the half a
## screenshot cannot tell apart.
##
## Run: godot --headless --path . --script res://tools/probe_lock_icon.gd

const UIKit := preload("res://scripts/ui/ui_kit.gd")

const PATH := "assets/menu-icons/lock.png"


func _initialize() -> void:
	var tex := UIKit.load_texture(PATH)
	if tex == null:
		print("LOCK: the texture did not load at all")
		quit(0)
		return
	print("LOCK: %s size=%s class=%s path=%s" % [PATH, str(tex.get_size()),
		tex.get_class(), tex.resource_path])
	var img := tex.get_image()
	if img == null:
		print("LOCK: the texture has NO image (get_image() returned null)")
		quit(0)
		return
	print("LOCK: image %dx%d format=%d has_alpha=%s" % [img.get_width(), img.get_height(),
		img.get_format(), str(img.detect_alpha())])
	# Sample the middle (where the padlock's body is), a corner (black background) and the four
	# points an 18x18 downscale would average from.
	var w := img.get_width()
	var h := img.get_height()
	for label in ["corner", "middle", "top-middle", "bottom-middle"]:
		var at := Vector2i.ZERO
		match label:
			"corner": at = Vector2i(2, 2)
			"middle": at = Vector2i(w / 2, h / 2)
			"top-middle": at = Vector2i(w / 2, h / 8)
			"bottom-middle": at = Vector2i(w / 2, h - h / 8)
		print("LOCK: %s at %s = %s" % [label, str(at), str(img.get_pixelv(at))])
	# How much of the image is BRIGHT, i.e. would read as ink over the node's #141414 fill.
	var bright := 0
	var total := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			total += 1
			var c := img.get_pixelv(Vector2i(x, y))
			if (c.r + c.g + c.b) / 3.0 > 0.5 and c.a > 0.5:
				bright += 1
	print("LOCK: bright fraction = %.3f (%d of %d samples)" % [float(bright) / float(total),
		bright, total])
	quit(0)
