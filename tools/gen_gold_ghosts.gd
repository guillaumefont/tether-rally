extends SceneTree
# Regenerates res://ghosts/gold.res: the Gold medal ghost of every track for the Standard,
# Reverse and Obstacles variants (scripts/gold_ghosts.gd). The AI drives a Time Trial the way
# tools/gen_medals.gd does (fixed seeds, best of 3 runs); its best lap is resampled at 30 a
# second and slowed to last exactly the Gold time (Medals.targets()[2]).
# Usage: godot --headless --path . --script tools/gen_gold_ghosts.gd   (rerun after gen_medals)
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Medals = preload("res://scripts/medals.gd")
const Gold = preload("res://scripts/gold_ghosts.gd")

func _init() -> void:
	var traces := {}
	for d in Defs.TRACKS:
		for v in Gold.VARIANTS:
			var best := {}
			for run in 3:
				seed(1000 + run)
				var lap := _best_lap(TrackData.new(d, v))
				if not lap.is_empty() and (best.is_empty() or lap["lt"] < best["lt"]):
					best = lap
			var gold: float = Medals.targets(d["name"], v)[2]
			if best.is_empty() or gold <= 0.0:
				printerr("no Gold ghost for %s %s" % [d["name"], v])
				continue
			traces[Gold.key(d["name"], v)] = _resample(best, gold)
			printerr("%s %s: AI lap %.2f -> Gold %.2f" % [d["name"], v, best["lt"], gold])
	var r := Resource.new()
	r.set_meta("traces", traces)
	DirAccess.make_dir_recursive_absolute("res://ghosts")
	var err := ResourceSaver.save(r, Gold.PATH, ResourceSaver.FLAG_COMPRESS)
	printerr("saved %d ghosts (%s)" % [traces.size(), error_string(err)])
	quit(0 if err == OK else 1)

# the AI's fastest clean lap: { lt, raw (clock time), samples [[t, x, y, h, hooked]...] }
func _best_lap(tr) -> Dictionary:
	var race := Race.new(tr, "trial", 1)
	var c = race.cars[0]
	var dt := 1.0 / 60.0
	var best := {}
	var cur: Array = []
	var cur_lap := -1
	while race.clock < 400.0 and not c.finished:
		race.ai_think(c)
		race.inputs[0]["held"] = c.hook >= 0
		var lap_before: int = c.lap
		var hits_before: int = c.lap_hits
		race.update(dt)
		race.events.clear()
		if c.lap != lap_before:
			# a lap just ended: keep it if it is the fastest without a post hit
			if lap_before >= 1 and cur.size() > 10 and hits_before == 0:
				var lt: float = c.laps[c.laps.size() - 1]
				var raw: float = cur[cur.size() - 1][0] + dt
				if best.is_empty() or lt < best["lt"]:
					best = { "lt": lt, "raw": raw, "samples": cur }
			cur = []
			cur_lap = c.lap
		if c.lap >= 1:
			cur.append([race.clock - c.lap_start, c.pos.x, c.pos.y, c.h, 1.0 if c.hook >= 0 else 0.0])
	return best

# 30 samples a second over `gold` seconds, each read from the lap at the same fraction of it
func _resample(lap: Dictionary, gold: float) -> PackedFloat32Array:
	var s: Array = lap["samples"]
	var raw: float = lap["raw"]
	var n := int(round(gold * Gold.RATE))
	var out := PackedFloat32Array()
	var j := 0
	for i in n:
		var t := (i / Gold.RATE) * raw / gold
		while j < s.size() - 2 and s[j + 1][0] <= t:
			j += 1
		var a: Array = s[j]
		var b: Array = s[mini(j + 1, s.size() - 1)]
		var span: float = maxf(0.0001, b[0] - a[0])
		var k := clampf((t - a[0]) / span, 0.0, 1.0)
		out.append(roundf(lerpf(a[1], b[1], k)))
		out.append(roundf(lerpf(a[2], b[2], k)))
		out.append(snappedf(lerp_angle(a[3], b[3], k), 0.01))
		out.append(a[4] if k < 0.5 else b[4])
	return out
