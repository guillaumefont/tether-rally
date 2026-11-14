extends SceneTree
# Writes the app icons from the medal logo (scripts/logo_art.gd): icon.svg (the project and
# editor icon), the Android launcher icons in icons/ and the store icon store/icon-512.png.
# No display needed: godot --headless --path . --script tools/gen_icons.gd
# The boot splash (icons/splash.png, tools/gen_splash.gd) and the web page logo
# (tools/gen_web_shell.gd) come from the same drawing.
const Logo = preload("res://scripts/logo_art.gd")

func _png(kind: String, size: int, path: String) -> void:
	var img := Image.new()
	var err := img.load_svg_from_string(Logo.icon_svg(kind, size))
	if err != OK:
		printerr("cannot draw ", kind, ": ", err)
		return
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(path)
	print("saved ", path, " ", img.get_size())

func _initialize() -> void:
	var f := FileAccess.open("res://icon.svg", FileAccess.WRITE)
	f.store_string(Logo.icon_svg("icon", 128))
	f.close()
	_png("icon", 192, "res://icons/icon-192.png")
	_png("background", 432, "res://icons/adaptive-background-432.png")
	_png("foreground", 432, "res://icons/adaptive-foreground-432.png")
	_png("monochrome", 432, "res://icons/adaptive-monochrome-432.png")
	_png("square", 512, "res://store/icon-512.png")
	quit()
