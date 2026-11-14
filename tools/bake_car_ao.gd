extends SceneTree
# Bakes the vehicles' ambient occlusion into art/car_ao.res (see WorldView.apply_ao):
# for every vertex of every game-model part, a fan of hemisphere rays measures how much of
# the sky the vehicle's other parts and the road under it hide. Rerun after changing a vehicle:
#   godot --headless --path . --script tools/bake_car_ao.gd     (~15 s)
# Optional env: AO_STRENGTH (1.4), AO_REACH (ray length, m, 0.45), AO_RAYS (48).
const WorldView = preload("res://scripts/world_view.gd")
const Themes = preload("res://scripts/themes.gd")

func _env(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return d if v == "" else float(v)

func _initialize() -> void:
	WorldView.detail = 1
	WorldView.ao_on = false
	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	view.th = Themes.get_theme("snow")
	var out := {}
	for id in WorldView.BODIES:
		var t0 := Time.get_ticks_msec()
		var car := view._make_car(Color("#e0a030"), false, { "color": Color("#e0a030"), "body": id, "livery": "none" })
		root.add_child(car)
		out[id] = await _bake(car)
		print(id, ": ", out[id].size(), " parts in ", Time.get_ticks_msec() - t0, " ms")
		car.queue_free()
		await process_frame
	var r := Resource.new()
	r.set_meta("ao", out)
	var err := ResourceSaver.save(r, WorldView.AO_PATH, ResourceSaver.FLAG_COMPRESS)
	print("saved ", WorldView.AO_PATH, " ", error_string(err))
	quit()

func _bake(car: Node3D) -> Array:
	var strength := _env("AO_STRENGTH", 1.4)
	var reach := _env("AO_REACH", 0.45)
	var n_dirs := int(_env("AO_RAYS", 48))
	var parts := WorldView.ao_parts(car)
	# occluders: every part except the tiny ones (lamps, badges), which would only blotch
	# the panel they sit on, plus the road under the wheels
	var faces := PackedVector3Array()
	for pr in parts:
		var mi: MeshInstance3D = pr[0]
		if mi.mesh.get_aabb().size.length() < 0.13:
			continue
		var xf: Transform3D = pr[1]
		for v in mi.mesh.get_faces():
			faces.append(xf * v)
	var gs := 3.0
	for v in [Vector3(-gs, 0, -gs), Vector3(gs, 0, -gs), Vector3(gs, 0, gs), Vector3(-gs, 0, -gs), Vector3(gs, 0, gs), Vector3(-gs, 0, gs)]:
		faces.append(v + Vector3(0, -0.002, 0))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	root.add_child(sb)
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.hit_back_faces = true
	var dirs: Array[Vector3] = []
	for k in n_dirs:   # cosine-weighted hemisphere, z up
		var u := (k + 0.5) / n_dirs
		var phi := k * 2.39996
		var r := sqrt(u)
		dirs.append(Vector3(cos(phi) * r, sin(phi) * r, sqrt(1.0 - u)))
	var data: Array = []
	for pr in parts:
		var mi: MeshInstance3D = pr[0]
		var xf: Transform3D = pr[1]
		var nb := xf.basis.inverse().transposed()
		var vals := PackedByteArray()
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var row := PackedFloat32Array()
			row.resize(vs.size())
			var buried: Array[int] = []
			var sum := 0.0
			var cnt := 0
			for i in vs.size():
				var p := xf * vs[i]
				var nrm := (nb * ns[i]).normalized()
				var tng := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
				var btg := nrm.cross(tng)
				var start := p + nrm * 0.004
				var occ := 0.0
				var back := 0
				for d in dirs:
					var w := tng * d.x + btg * d.y + nrm * d.z
					q.from = start
					q.to = start + w * reach
					var h := space.intersect_ray(q)
					if not h.is_empty():
						if (h["normal"] as Vector3).dot(w) > 0.0:
							back += 1
						occ += 1.0 - start.distance_to(h["position"]) / reach * 0.5
				if back > n_dirs / 3:   # inside another part: never seen, take the part's average
					buried.append(i)
					continue
				row[i] = clampf(1.0 - strength * occ / n_dirs, 0.0, 1.0)
				sum += row[i]
				cnt += 1
			for i in buried:
				row[i] = sum / cnt if cnt > 0 else 1.0
			for i in vs.size():
				vals.append(int(round(row[i] * 255.0)))
		data.append(vals)
	sb.queue_free()
	return data
