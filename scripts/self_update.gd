# Test builds update themselves (Guillaume, 2026-11-14). This file is the part that must run
# before anything else loads, so it is frozen into the installed app: the engine runs it from
# the APK, never from downloaded game data. Keep it small. A change here changes the build's
# SHELL fingerprint (CI hashes this file), and installed apps then need the new APK.
#
# It is an autoload, the first thing the engine runs. At launch it mounts the newest game data
# downloaded earlier (user://update/game-N.pck) over the app's own, so main.tscn and every
# script after it come from that build. Then it starts scripts/updater.gd, which comes from the
# mounted data (so it updates itself too). updater.gd checks for, downloads and offers new
# builds. Only APKs that CI exports for testing carry the "self_update" feature. The committed
# export presets don't, so a store build never updates itself: Google Play forbids that.
# A downloaded build that fails to reach the menu MAX_TRIES launches in a row is dropped.
#   godot --headless --path . --script tests/self_update_test.gd
extends Node

const BuildInfo = preload("res://scripts/build_info.gd")

const DIR := "user://update/"
const STATE := DIR + "state.cfg"
const MAX_TRIES := 2             # launches a downloaded build may fail to reach the menu

var running := 0        # build of the game data running now (the app's own, or a downloaded one)

func _init() -> void:
	running = BuildInfo.BUILD
	if not enabled():
		return
	var pick := pick_saved(DIR, app_info())
	if pick.is_empty():
		return
	if ProjectSettings.load_resource_pack(pick["path"], true):
		running = pick["build"]
		print("self update: running game data of build %d" % running)
	else:
		_forget(DIR)

# the updater (checks, downloads, the home page slip, the Settings line) comes from the game
# data now mounted, so its fixes reach phones without a new APK
func _ready() -> void:
	var u: Node = load("res://scripts/updater.gd").new()
	u.name = "Updater"
	add_child(u)

static func enabled() -> bool:
	return OS.has_feature("self_update") and BuildInfo.BUILD > 0

static func app_info() -> Dictionary:
	return { "build": BuildInfo.BUILD, "shell": BuildInfo.SHELL, "engine": BuildInfo.ENGINE }

static func pck_path(dir: String, build: int) -> String:
	return dir + "game-%d.pck" % build

# The downloaded game data to mount at launch: { path, build }, or {} for the app's own.
# Drops what can't run on this app (older than the app, made for another shell, damaged, or
# failed to reach the menu MAX_TRIES times) and deletes stale files. Counts this launch as a
# try; confirm() (the menu came up) clears it.
static func pick_saved(dir: String, app: Dictionary) -> Dictionary:
	var st := ConfigFile.new()
	if st.load(dir + "state.cfg") != OK:
		return {}
	var b := int(st.get_value("pck", "build", 0))
	var path := pck_path(dir, b)
	var ok: bool = b > int(app["build"]) and st.get_value("pck", "shell", "") == app["shell"] \
		and st.get_value("pck", "engine", "") == app["engine"] and FileAccess.file_exists(path)
	if ok and int(st.get_value("pck", "tries", 0)) >= MAX_TRIES:
		st.set_value("boot", "bad", b)
		ok = false
	if ok and FileAccess.get_sha256(path) != str(st.get_value("pck", "sha256", "")):
		ok = false
	_clean(dir, b if ok else 0)
	if not ok:
		st.erase_section("pck")
		st.save(dir + "state.cfg")
		return {}
	st.set_value("pck", "tries", int(st.get_value("pck", "tries", 0)) + 1)
	st.save(dir + "state.cfg")
	return { "path": path, "build": b }

# the game reached its menu: the running build works
static func confirm_in(dir: String) -> void:
	var st := ConfigFile.new()
	if st.load(dir + "state.cfg") == OK and int(st.get_value("pck", "tries", 0)) != 0:
		st.set_value("pck", "tries", 0)
		st.save(dir + "state.cfg")

# delete every game-N.pck but `keep` (a mounted pack must never be overwritten or deleted
# while the game runs: the engine reads it again at the offsets it saw at launch)
static func _clean(dir: String, keep: int) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("game-") and f.ends_with(".pck") and f != pck_path("", keep):
			d.remove(f)

static func _forget(dir: String) -> void:
	var st := ConfigFile.new()
	st.load(dir + "state.cfg")
	st.erase_section("pck")
	st.save(dir + "state.cfg")
