# The Tether Rally logo, "the medal" (picked by Guillaume 2026-11-14): a round chalk-cream
# medal, dark inside, with the amber car swinging round the tower seen from above, three speed
# trails behind it. For the app icon it sits in front of a snowy dusk scene with two light beams.
# Everything is SVG in a -50..50 box (medal radius 40, the loading ring at 48), so the icons
# (tools/gen_icons.gd), the web loading page and the game draw the same shapes. In the game the
# frame is a texture and the moving parts (trails, rope, tower hub, car) are drawn by
# menu_art.gd `draw_medal` from the numbers below, so the car can lap the tower.
extends RefCounted

const R_FRAME := 40.0      # outer edge of the cream frame
const R_DISC := 34.5       # the dark disc inside it
const R_LINE := 31.5       # thin cream line inside the disc
const R_RING := 48.0       # the loading ring round the medal
const ORBIT := 21.0        # the car's distance from the tower
const HUB := 7.5           # tower top radius
const CAR_K := 1.45        # car scale
const ANGLE := 40.0        # the car's angle in still pictures (degrees, clockwise from +x)
# speed trails: [radius offset, length (deg), width, alpha]; they end TRAIL_GAP degrees behind the car
const TRAILS := [[-5.5, 45.0, 2.0, 0.55], [0.0, 80.0, 3.0, 0.9], [5.5, 45.0, 2.0, 0.55]]
const TRAIL_GAP := 30.0
# the car seen from above, nose +x, before CAR_K: [x, y, w, h, colour]
const CAR := [
	[-8.6, -5.6, 3.4, 2.0, "#15191e"], [4.4, -5.6, 3.4, 2.0, "#15191e"],
	[-8.6, 3.6, 3.4, 2.0, "#15191e"], [4.4, 3.6, 3.4, 2.0, "#15191e"],
	[-9.0, -4.6, 18.0, 9.2, "#c98a1c"], [-8.6, -4.2, 17.0, 7.6, "#f2b134"],
	[-1.2, -3.6, 6.4, 7.2, "#f7c85a"],
	[4.6, -3.2, 2.0, 6.4, "#1a2330"], [-3.4, -3.0, 1.4, 6.0, "#1a2330"],
	[8.2, -3.6, 1.0, 1.6, "#fff4c8"], [8.2, 2.0, 1.0, 1.6, "#fff4c8"],
]
const CREAM := "#f3efe6"
const AMBER := "#f2b134"

# The medal logo at `c`, `k` pixels per logo unit (frame radius R_FRAME), car at angle
# `a` (radians, clockwise from +x). The frame is the SVG from logo_art.gd as a texture, made
# once per pixel size; trails, rope, tower top and car are drawn here so they can move.
static var _frames := {}
static func medal_frame(px: int) -> Texture2D:
	if not _frames.has(px):
		if _frames.size() > 8:
			_frames.clear()
		var img := Image.new()
		img.load_svg_from_string(frame_svg(px))
		_frames[px] = ImageTexture.create_from_image(img)
	return _frames[px]

static func draw_medal(ci: CanvasItem, c: Vector2, k: float, a: float) -> void:
	var px := maxi(8, int(ceil(100.0 * k)))
	var box := float(px)
	ci.draw_texture_rect(medal_frame(px), Rect2(c - Vector2(box, box) * 0.5, Vector2(box, box)), false)
	var cream := Color(CREAM)
	for tr in TRAILS:
		var a1: float = a - deg_to_rad(TRAIL_GAP)
		var a0: float = a1 - deg_to_rad(tr[1])
		ci.draw_arc(c, (ORBIT + tr[0]) * k, a0, a1, 24, Color(cream, tr[3]), maxf(1.0, tr[2] * k), true)
	var cp := c + Vector2.from_angle(a) * ORBIT * k
	ci.draw_line(c, cp, Color(AMBER), maxf(1.0, 2.4 * k), true)
	var hr := HUB * k
	ci.draw_circle(c + Vector2(0, hr * 0.18), hr, Color(0, 0, 0, 0.35))
	ci.draw_circle(c, hr, cream)
	ci.draw_circle(c, hr * 0.62, Color("#cfc8b8"))
	ci.draw_circle(c, hr * 0.3, Color("#2a2f36"))
	ci.draw_set_transform(cp, a + PI / 2, Vector2.ONE * k * CAR_K)
	for r in CAR:
		ci.draw_rect(Rect2(r[0], r[1], r[2], r[3]), Color(r[4]))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# the frame alone: shadow, cream bevelled ring, dark disc, thin line (no car)
static func frame_svg(size: int) -> String:
	return _svg(size, _frame())

static func _frame(mono := false) -> String:
	if mono:
		return "<circle r='%s' fill='none' stroke='#fff' stroke-width='%s'/>" % [(R_FRAME + R_DISC) * 0.5, R_FRAME - R_DISC]
	return """<defs><linearGradient id='fm' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#fbf8f1'/><stop offset='.5' stop-color='#e3dccb'/><stop offset='1' stop-color='#a39c8c'/></linearGradient>
<radialGradient id='fd' cx='.5' cy='.35' r='.75'><stop offset='0' stop-color='#1f3a45'/><stop offset='1' stop-color='#081822'/></radialGradient></defs>
<circle cy='2.5' r='%s' fill='#000' fill-opacity='.35'/><circle r='%s' fill='url(#fm)'/><circle r='%s' fill='url(#fd)'/>
<circle r='%s' fill='none' stroke='%s' stroke-opacity='.5' stroke-width='.8'/>""" % [R_FRAME, R_FRAME, R_DISC, R_LINE, CREAM]

# trails, rope, tower top and car at angle `a` (degrees)
static func _parts(a: float, mono := false) -> String:
	var s := ""
	var cream := "#fff" if mono else CREAM
	for tr in TRAILS:
		var r: float = ORBIT + tr[0]
		var a1: float = a - TRAIL_GAP
		var a0: float = a1 - tr[1]
		var p0 := Vector2.from_angle(deg_to_rad(a0)) * r
		var p1 := Vector2.from_angle(deg_to_rad(a1)) * r
		s += "<path d='M %.2f %.2f A %.2f %.2f 0 0 1 %.2f %.2f' fill='none' stroke='%s' stroke-opacity='%s' stroke-width='%s' stroke-linecap='round'/>" % [p0.x, p0.y, r, r, p1.x, p1.y, cream, 1.0 if mono else tr[3], tr[2]]
	var cp := Vector2.from_angle(deg_to_rad(a)) * ORBIT
	s += "<line x1='0' y1='0' x2='%.2f' y2='%.2f' stroke='%s' stroke-width='2.4' stroke-linecap='round'/>" % [cp.x, cp.y, "#fff" if mono else AMBER]
	if mono:
		s += "<circle r='%s' fill='none' stroke='#fff' stroke-width='%s'/>" % [HUB * 0.65, HUB * 0.7]
	else:
		s += "<circle cy='%s' r='%s' fill='#000' fill-opacity='.35'/><circle r='%s' fill='%s'/><circle r='%s' fill='#cfc8b8'/><circle r='%s' fill='#2a2f36'/>" % [HUB * 0.18, HUB, HUB, CREAM, HUB * 0.62, HUB * 0.3]
	s += "<g transform='translate(%.2f %.2f) rotate(%.2f) scale(%s)'>" % [cp.x, cp.y, a + 90.0, CAR_K]
	for r in CAR:
		s += "<rect x='%s' y='%s' width='%s' height='%s' fill='%s'/>" % [r[0], r[1], r[2], r[3], "#fff" if mono else r[4]]
	return s + "</g>"

# the snowy dusk scene behind the medal on the app icon
static func _scene() -> String:
	var s := """<defs><linearGradient id='sk' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#0d2233'/><stop offset='.45' stop-color='#4c4062'/><stop offset='.72' stop-color='#e9b7aa'/><stop offset='1' stop-color='#f3d2b8'/></linearGradient>
<linearGradient id='bm' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#fff' stop-opacity='.22'/><stop offset='1' stop-color='#fff' stop-opacity='0'/></linearGradient></defs>
<rect x='-50' y='-50' width='100' height='100' fill='url(#sk)'/>
<polygon points='-6,-52 6,-52 30,40 -30,40' fill='url(#bm)' transform='rotate(-24 0 -52)'/>
<polygon points='-5,-52 5,-52 26,40 -26,40' fill='url(#bm)' transform='rotate(28 0 -52)'/>
<path d='M -50 22 Q -30 12 -10 20 T 30 16 T 50 20 V 50 H -50 Z' fill='#8fa3b5'/>"""
	for p in [[-42, 24, 9], [-36, 27, 7], [-28, 26, 6], [33, 25, 8], [40, 27, 10], [46, 24, 6]]:
		var x: float = p[0]; var y: float = p[1]; var h: float = p[2]
		s += "<polygon points='%s,%s %s,%s %s,%s' fill='#1f4438'/>" % [x - h * 0.38, y, x + h * 0.38, y, x, y - h]
		s += "<polygon points='%s,%s %s,%s %s,%s' fill='#e6eef4'/>" % [x - h * 0.2, y - h * 0.5, x + h * 0.2, y - h * 0.5, x, y - h]
	s += "<path d='M -50 32 Q -20 22 10 30 T 50 28 V 50 H -50 Z' fill='#c9d6e0'/><path d='M -50 42 Q -10 34 30 41 T 50 40 V 50 H -50 Z' fill='#e8eef3'/>"
	for f in [[-40, -8, 1], [-34, 10, .8], [38, -14, 1.1], [44, 4, .7], [-44, 26, .9], [30, 30, 1], [40, 40, .8], [-30, 40, .7], [-20, -38, .6], [26, -40, .7], [-46, -30, .6], [46, -34, .8]]:
		s += "<circle cx='%s' cy='%s' r='%s' fill='#fff' fill-opacity='.75'/>" % f
	return s

# kind: "icon" (rounded square, scene + medal), "square" (full bleed, store), "background"
# (scene only), "foreground" (medal only, inside Android's safe zone), "monochrome" (white mask)
static func icon_svg(kind: String, size: int) -> String:
	var medal := "<g transform='translate(0 -2) scale(.9)'>%s%s</g>" % [_frame(), _parts(ANGLE)]
	match kind:
		"icon":
			return _svg(size, "<defs><clipPath id='ic'><rect x='-50' y='-50' width='100' height='100' rx='19'/></clipPath></defs><g clip-path='url(#ic)'>%s</g>%s" % [_scene(), medal])
		"square":
			return _svg(size, _scene() + medal)
		"background":
			return _svg(size, _scene())
		"foreground":
			return _svg(size, "<g transform='scale(.72)'>%s%s</g>" % [_frame(), _parts(ANGLE)])
		"monochrome":
			return _svg(size, "<g transform='scale(.72)'>%s%s</g>" % [_frame(true), _parts(ANGLE, true)])
	return ""

static func _svg(size: int, body: String) -> String:
	return "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='-50 -50 100 100'>%s</svg>" % [size, size, body]
