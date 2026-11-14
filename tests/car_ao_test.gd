extends SceneTree
# Baked car AO (WorldView.apply_ao, art/car_ao.res): every vehicle's bake matches its current
# parts (rerun tools/bake_car_ao.gd after changing a vehicle), the shading is there but never
# blacks a car out, and a game car really wears it, livery or not.
const WorldView = preload("res://scripts/world_view.gd")
const Cosmetics = preload("res://scripts/cosmetics.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func _initialize() -> void:
	WorldView.detail = 1
	var view := WorldView.new()
	var data := WorldView.ao_data()
	for id in WorldView.BODIES:
		if not data.has(id):
			fail("%s: no baked AO, run tools/bake_car_ao.gd" % id)
			continue
		WorldView.ao_on = false
		var car: Node3D = view._make_car(Color.ORANGE, false, { "color": Color.ORANGE, "body": id, "livery": "none" })
		var n := WorldView.ao_parts(car).size()
		if (data[id] as Array).size() != n:
			fail("%s: bake has %d parts, the vehicle %d: rerun tools/bake_car_ao.gd" % [id, (data[id] as Array).size(), n])
		var got := WorldView.apply_ao(id, car)
		if got != n:
			fail("%s: AO fits %d of %d parts: rerun tools/bake_car_ao.gd" % [id, got, n])
		# the main top (roof, hull) is open sky: it must stay nearly unshaded, while
		# somewhere (wheel arches, the underside) the car gets clearly darker
		var lo := 255
		var hi := 0
		for vals: PackedByteArray in data[id]:
			for v in vals:
				lo = mini(lo, v)
				hi = maxi(hi, v)
		if lo > 160:
			fail("%s: no visible shading (darkest %d/255)" % [id, lo])
		if hi < 235:
			fail("%s: even the open top is shaded (brightest %d/255)" % [id, hi])
		car.free()
		# a game car with a livery: the body parts carry the AO colours, the decals stay plain
		WorldView.ao_on = true
		var look := Cosmetics.look("amber", "stripes")
		look["body"] = id
		var gc: Node3D = view._make_car(look["color"], false, look)
		var shaded := 0
		for pr in WorldView.ao_parts(gc):
			var mi: MeshInstance3D = pr[0]
			if mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR:
				var m: Material = mi.material_override if mi.material_override else mi.get_surface_override_material(0)
				if m is StandardMaterial3D and not (m as StandardMaterial3D).vertex_color_use_as_albedo:
					fail("%s: a part has AO colours its material ignores" % id)
				shaded += 1
		if shaded != n:
			fail("%s: %d of %d parts shaded on a game car" % [id, shaded, n])
		gc.free()
	view.free()
	print("car AO test: ", "OK" if bad == 0 else "%d failures" % bad)
	quit(1 if bad > 0 else 0)
