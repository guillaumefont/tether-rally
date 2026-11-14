# Test builds update themselves (Guillaume, 2026-11-14: "Can you build a version of the game
# that updates itself?"). Only APKs that CI exports for testing carry the "self_update"
# feature; a store build must never have it (Google Play forbids apps that update their own
# code outside the store), and the web build is always the latest anyway.
#
# Each build publishes, next to its APK on GitHub Pages, its game data (game.pck: every
# script, scene, picture and sound) and a small update.json describing it. The installed app:
#   1. at launch, before anything else loads, mounts the newest game data it downloaded
#      earlier over its own (this file is an autoload, the first thing the engine runs), so
#      main.tscn and every script after it come from that build;
#   2. a few seconds after launch, and when back on the menu at most every 10 minutes, reads
#      update.json from its own Pages folder (main, or pr/N for a PR's APK). A newer build is
#      downloaded in the background (a few MB), checked against its SHA-256, and kept next to
#      the current one; the home page then offers "restart" (or it applies on the next launch).
#   3. If the new build changed what game data alone can't (engine version, project.godot,
#      export presets, this file: the SHELL fingerprint in build_info.gd), the home page
#      offers the new APK instead: Android always asks the player to confirm an install.
# Safety: it only fetches over HTTPS from the github.io folder baked into the app at build
# time, never runs when offline or on a build without the feature, and a downloaded build
# that fails to reach the menu twice in a row is dropped (the app's own data runs again).
#   godot --headless --path . --script tests/self_update_test.gd
extends Node

const BuildInfo = preload("res://scripts/build_info.gd")

const DIR := "user://update/"
const STATE := DIR + "state.cfg"
const PART := DIR + "download.part"
const MAX_BYTES := 128 * 1024 * 1024
const RECHECK_MS := 10 * 60 * 1000
const FIRST_CHECK_S := 4.0       # after launch: leave the loading screen and menu alone first
const MAX_TRIES := 2             # launches a downloaded build may fail to reach the menu
const APK := "tether-racing.apk"

signal changed

# off: not a self-updating build | idle | checking | current | downloading | ready (restart to
# apply) | apk (the new build needs the new app) | error (offline, server down: tried again later)
var status := "off"
var running := 0        # build of the game data running now (the app's own, or a downloaded one)
var latest := 0         # newest build seen on the server
var _checked_ms := -1
var _http: HTTPRequest
var _want := {}         # the build being downloaded

func _init() -> void:
	running = BuildInfo.BUILD
	if not enabled():
		return
	status = "idle"
	var pick := pick_saved(DIR, app_info())
	if pick.is_empty():
		return
	if ProjectSettings.load_resource_pack(pick["path"], true):
		running = pick["build"]
		print("self update: running game data of build %d" % running)
	else:
		_forget(DIR)

func _ready() -> void:
	if status == "off":
		return
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 20.0
	add_child(_http)
	get_tree().create_timer(FIRST_CHECK_S).timeout.connect(check)

static func enabled() -> bool:
	return OS.has_feature("self_update") and BuildInfo.BUILD > 0 and channel_ok(BuildInfo.CHANNEL)

static func app_info() -> Dictionary:
	return { "build": BuildInfo.BUILD, "shell": BuildInfo.SHELL, "engine": BuildInfo.ENGINE }

# only our own Pages site, over HTTPS
static func channel_ok(url: String) -> bool:
	if not url.begins_with("https://") or not url.ends_with("/") or url.contains("..") or url.contains("?") or url.contains("@"):
		return false
	var host := url.trim_prefix("https://").get_slice("/", 0)
	return host.ends_with(".github.io") and host.count(".") == 2

static func engine_version() -> String:
	var v := Engine.get_version_info()
	return "%d.%d.%d" % [v["major"], v["minor"], v["patch"]]

# What to do about the build described by `info` (update.json): "none", "pck" (download its
# game data, no install needed) or "apk" (it needs the new app). `have` is the newest build
# already here (running or downloaded), `bad` one that failed to start.
static func plan(app: Dictionary, have: int, info: Dictionary, bad := 0) -> String:
	var b := int(info.get("build", 0))
	if b <= maxi(have, int(app["build"])) or b == bad:
		return "none"
	if str(info.get("shell", "")) != str(app["shell"]) or str(info.get("engine", "")) != str(app["engine"]) \
			or str(app["engine"]) != engine_version():
		return "apk"
	var sha := str(info.get("sha256", ""))
	var size := int(info.get("size", 0))
	var name := str(info.get("pck", ""))
	if sha.length() != 64 or not sha.is_valid_hex_number() or size <= 0 or size > MAX_BYTES \
			or not name.is_valid_filename() or not name.ends_with(".pck"):
		return "none"
	return "pck"

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

# ------------------------------------------------------------ runtime (self-updating builds)
func confirm() -> void:
	if status != "off":
		confirm_in(DIR)

# back on the menu: look again if the last look was a while ago
func poke() -> void:
	# (the first look is FIRST_CHECK_S after launch, not before)
	if status in ["current", "error"] and _checked_ms >= 0 and Time.get_ticks_msec() - _checked_ms > RECHECK_MS:
		check()

func check() -> void:
	if status in ["off", "checking", "downloading", "ready", "apk"] or _http == null:
		return
	_checked_ms = Time.get_ticks_msec()
	_set_status("checking")
	_http.download_file = ""
	_http.body_size_limit = 64 * 1024
	# a fresh copy, not one the phone or GitHub's cache kept from earlier
	var url := BuildInfo.CHANNEL + "update.json?t=%d" % Time.get_unix_time_from_system()
	if _http.request(url, ["Cache-Control: no-cache"]) != OK:
		_set_status("error")
		return
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_set_status("error")
		return
	var info = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not info is Dictionary:
		_set_status("error")
		return
	latest = maxi(latest, int(info.get("build", 0)))
	var st := ConfigFile.new()
	st.load(STATE)
	var have := maxi(running, int(st.get_value("pck", "build", 0)))
	match plan(app_info(), have, info, int(st.get_value("boot", "bad", 0))):
		"apk":
			_set_status("apk")
		"pck":
			_download(info)
		_:
			# a newer build is already downloaded but not running yet
			_set_status("ready" if have > running else "current")

func _download(info: Dictionary) -> void:
	_want = info
	_set_status("downloading")
	DirAccess.make_dir_recursive_absolute(DIR)
	_http.download_file = PART
	_http.body_size_limit = MAX_BYTES
	_http.timeout = 600.0
	var err := _http.request(BuildInfo.CHANNEL + str(info["pck"]) + "?b=%d" % int(info["build"]))
	var res: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0] if err != OK else await _http.request_completed
	_http.download_file = ""
	_http.timeout = 20.0
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200 or not _verify(PART, info):
		DirAccess.remove_absolute(PART)
		_set_status("error")
		return
	var b := int(info["build"])
	DirAccess.rename_absolute(PART, pck_path(DIR, b))
	var st := ConfigFile.new()
	st.load(STATE)
	st.set_value("pck", "build", b)
	st.set_value("pck", "sha256", str(info["sha256"]))
	st.set_value("pck", "shell", BuildInfo.SHELL)
	st.set_value("pck", "engine", BuildInfo.ENGINE)
	st.set_value("pck", "tries", 0)
	st.save(STATE)
	# an older download that never ran is no longer needed (never the one running now)
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		if f.begins_with("game-") and f.ends_with(".pck") and f != pck_path("", b) and f != pck_path("", running):
			d.remove(f)
	_set_status("ready")

static func _verify(path: String, info: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() != int(info["size"]):
		return false
	f.close()
	return FileAccess.get_sha256(path) == str(info["sha256"]).to_lower()

func _set_status(s: String) -> void:
	status = s
	changed.emit()

# the home page's slip: what it says, or "" when there is nothing to offer
func offer() -> String:
	match status:
		"ready": return "new build ready  ·  restart  ›"
		"apk": return "new version  ·  install  ›"
	return ""

# the slip was tapped
func act() -> void:
	if status == "ready":
		# Android (and desktop) start the game again; the new data mounts at launch
		OS.set_restart_on_exit(true)
		get_tree().quit()
	elif status == "apk":
		OS.shell_open(BuildInfo.CHANNEL + APK)

# one line for the Settings screen
func version_line() -> String:
	if BuildInfo.BUILD == 0:
		return "Development build"
	var s := "Build %d" % running
	if running != BuildInfo.BUILD:
		s += " (app %d)" % BuildInfo.BUILD
	match status:
		"current": s += "  ·  up to date"
		"checking": s += "  ·  checking for updates"
		"downloading": s += "  ·  downloading build %d" % int(_want.get("build", 0))
		"ready": s += "  ·  update ready, restart to apply"
		"apk": s += "  ·  build %d needs the new app" % latest
	return s
