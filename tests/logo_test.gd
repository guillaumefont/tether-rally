extends SceneTree
# The medal logo (Guillaume, 2026-11-14): one drawing in scripts/logo_art.gd feeds the app
# icons, the web loading page, the menu header and the loading screen's emblem and ring.
const Logo = preload("res://scripts/logo_art.gd")
const Art = preload("res://scripts/menu_art.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func _img(svg: String) -> Image:
	var img := Image.new()
	if img.load_svg_from_string(svg) != OK:
		return null
	return img

func _init() -> void:
	# every icon kind draws
	for kind in ["icon", "square", "background", "foreground", "monochrome"]:
		var img := _img(Logo.icon_svg(kind, 128))
		if img == null or img.get_size() != Vector2i(128, 128):
			fail("icon kind %s does not draw" % kind)
		elif img.is_invisible():
			fail("icon kind %s is empty" % kind)
	# the project icon and the launcher icons come from the medal, not an old hand edit
	if FileAccess.get_file_as_string("res://icon.svg").strip_edges() != Logo.icon_svg("icon", 128):
		fail("icon.svg is out of date: run tools/gen_icons.gd")
	var fg := Image.load_from_file("res://icons/adaptive-foreground-432.png")
	if fg == null or fg.get_size() != Vector2i(432, 432):
		fail("launcher foreground missing")
	else:
		# medal inside Android's safe zone (66 of 108): the corners stay clear
		if fg.get_pixel(40, 40).a > 0.01 or fg.get_pixel(392, 392).a > 0.01:
			fail("launcher foreground spills outside the safe zone")
		# the medal's frame is cream at its edge, its disc dark inside
		var frame := fg.get_pixel(216, 216 - int(37 * 0.72 * 4.32))
		if frame.get_luminance() < 0.6:
			fail("launcher foreground: the frame is not cream (%s)" % frame.to_html())
	# the frame texture the game draws is the right size, dark in the middle, cream at the rim
	var tex := Logo.medal_frame(200)
	var fi := tex.get_image()
	if fi.get_size() != Vector2i(200, 200):
		fail("medal frame texture size %s" % fi.get_size())
	elif fi.get_pixel(100, 100).get_luminance() > 0.25 or fi.get_pixel(100, 100 - 74).get_luminance() < 0.6:
		fail("medal frame: disc not dark or rim not cream")
	# the web loading page draws the same medal, its car on the orbit
	var shell := FileAccess.get_file_as_string("res://web/shell_template.html")
	for want in ["the medal logo", "id=\"orbit\"", "id=\"ring\"", "r=\"34.5\""]:
		if not shell.contains(want):
			fail("web/shell_template.html lacks %s" % want)
	var built := FileAccess.get_file_as_string("res://web/shell.html")
	if not built.contains("the medal logo"):
		fail("web/shell.html is out of date: run tools/gen_web_shell.gd")
	if bad == 0:
		print("logo_test: OK")
	quit(1 if bad > 0 else 0)
