# The Gold medal ghost (docs/monetization.md): for each track and lap variant (Standard,
# Reverse, Obstacles; Collect has none, its medal is a whole-run score) a lap of the AI,
# slowed to finish exactly at the Gold time, made by tools/gen_gold_ghosts.gd into
# res://ghosts/gold.res (rerun it after changing a layout, like tools/gen_medals.gd).
# Samples are 30 a second, like the player's own ghost (Records): x, y, heading, and
# whether the rope is hooked (for the ideal line).
# A player unlocks the Gold ghost of a track + variant for good with a rewarded ad, offered
# on the results after a run without Gold; "No ads" opens every one. Unlocks live in
# user://wallet.cfg (section "ghosts"), so Reset progress clears them.
extends RefCounted

const Wallet = preload("res://scripts/wallet.gd")
const Ads = preload("res://scripts/ads.gd")
const Medals = preload("res://scripts/medals.gd")

const PATH := "res://ghosts/gold.res"
const VARIANTS := ["standard", "reverse", "obstacles"]
const RATE := 30.0

static var _data: Dictionary   # key -> PackedFloat32Array (x, y, h, hooked) * samples

static func key(track_name: String, variant: String) -> String:
	return "%s|%s" % [track_name, variant]

static func _all() -> Dictionary:
	if _data.is_empty() and ResourceLoader.exists(PATH):
		var r: Resource = load(PATH)
		if r and r.has_meta("traces"):
			_data = r.get_meta("traces")
	return _data

static func has(track_name: String, variant: String) -> bool:
	return VARIANTS.has(variant) and _all().has(key(track_name, variant))

static func _flat(track_name: String, variant: String) -> PackedFloat32Array:
	return _all().get(key(track_name, variant), PackedFloat32Array())

# the lap as Records ghosts are: Vector3(x, y, heading) at 30 a second
static func trace(track_name: String, variant: String) -> Array:
	var f := _flat(track_name, variant)
	var out: Array = []
	for i in range(0, f.size() - 3, 4):
		out.append(Vector3(f[i], f[i + 1], f[i + 2]))
	return out

# is the rope hooked at each sample
static func hooked(track_name: String, variant: String) -> Array:
	var f := _flat(track_name, variant)
	var out: Array = []
	for i in range(3, f.size(), 4):
		out.append(f[i] > 0.5)
	return out

static func lap_time(track_name: String, variant: String) -> float:
	return _flat(track_name, variant).size() / 4.0 / RATE

# ---------------------------------------------------------------- unlocks
static func unlocked(track_name: String, variant: String) -> bool:
	if not has(track_name, variant):
		return false
	return Ads.ads_removed() or bool(Wallet.get_v("ghosts", key(track_name, variant), false))

static func unlock(track_name: String, variant: String) -> void:
	Wallet.set_v("ghosts", key(track_name, variant), true)

# offer it on these results: a Time trial run that finished without Gold, where the player
# has no Gold yet and the ghost isn't open already
static func offer(track_name: String, variant: String, finished: bool, run_tier: int, held_tier: int) -> bool:
	return finished and run_tier < 3 and held_tier < 3 and has(track_name, variant) and not unlocked(track_name, variant)
