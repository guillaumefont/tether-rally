# Test builds update themselves (Guillaume, 2026-11-14): checking for, downloading and offering
# new builds. scripts/self_update.gd (the autoload) mounts downloaded game data at launch and then
# starts this node as /root/SelfUpdate/Updater. This file loads from the running game data, so
# changes here reach phones through the update itself. The parts frozen into the APK live in
# self_update.gd.
#
# Each CI build publishes its game data (game.pck) and update.json next to its APK on GitHub
# Pages. A few seconds after launch, when back on the menu (at most every 10 minutes), and when
# "Check for update" is tapped in Settings, this reads update.json from the app's own Pages
# folder: main, or pr/N for a PR's APK. A PR's APK falls back to main once its PR is closed and
# its folder is gone. A newer build's data is downloaded in the background and checked against
# its SHA-256. The home page then shows "restart", or the update applies on the next launch.
# A build that changed what data alone can't change (the SHELL fingerprint in build_info.gd)
# offers its APK instead, because Android always asks before installing an app.
# It only fetches over HTTPS from the github.io folder baked into the app at build time, and it
# never gets in the way of playing when offline.
extends Node

const BuildInfo = preload("res://scripts/build_info.gd")
const Shell = preload("res://scripts/self_update.gd")

const PART := Shell.DIR + "download.part"
const MAX_BYTES := 128 * 1024 * 1024
const RECHECK_MS := 10 * 60 * 1000
const FIRST_CHECK_S := 4.0       # after launch: leave the loading screen and menu alone first
const APK := "tether-racing.apk"

signal changed

# off: not a self-updating build | idle | checking | current | downloading | ready (restart to
# apply) | apk (the new build needs the new app) | error (offline, server down: tried again later)
var status := "off"
var latest := 0         # newest build seen on the server
var source := ""        # the Pages folder the last update.json came from
var _checked_ms := -1
var _http: HTTPRequest
var _want := {}         # the build being downloaded

func _ready() -> void:
	if not enabled():
		return
	status = "idle"
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 20.0
	add_child(_http)
	get_tree().create_timer(FIRST_CHECK_S).timeout.connect(check)

static func enabled() -> bool:
	return Shell.enabled() and channel_ok(BuildInfo.CHANNEL)

# the build of the game data running now
func running() -> int:
	var p := get_parent()
	return int(p.running) if p and "running" in p else BuildInfo.BUILD

# only our own Pages site, over HTTPS
static func channel_ok(url: String) -> bool:
	if not url.begins_with("https://") or not url.ends_with("/") or url.contains("..") or url.contains("?") or url.contains("@"):
		return false
	var host := url.trim_prefix("https://").get_slice("/", 0)
	return host.ends_with(".github.io") and host.count(".") == 2

# where to look, in order: the app's own folder, then for a PR's APK the main build (its PR
# folder disappears once the PR is merged or closed, and main carries on from there)
static func channels(own: String) -> Array:
	var out := [own]
	var i := own.find("/pr/")
	if i > 0 and own.substr(i).count("/") == 3:
		out.append(own.substr(0, i + 1))
	return out.filter(func(u): return channel_ok(u))

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

# back on the menu: look again if the last look was a while ago
# (the first look is FIRST_CHECK_S after launch, not before)
func poke() -> void:
	if status in ["current", "error"] and _checked_ms >= 0 and Time.get_ticks_msec() - _checked_ms > RECHECK_MS:
		check()

# the game reached its menu: the running build works
func confirm() -> void:
	if status != "off":
		Shell.confirm_in(Shell.DIR)

func check() -> void:
	if status in ["off", "checking", "downloading", "ready", "apk"] or _http == null:
		return
	_checked_ms = Time.get_ticks_msec()
	_set_status("checking")
	var info = null
	for ch in channels(BuildInfo.CHANNEL):
		var got: Array = await _fetch_json(ch + "update.json?t=%d" % Time.get_unix_time_from_system())
		if got[0] == 200 and got[1] is Dictionary:
			info = got[1]
			source = ch
			break
		if got[0] != 404:   # offline, server trouble: don't guess, try again later
			break
	if not info is Dictionary:
		_set_status("error")
		return
	latest = maxi(latest, int(info.get("build", 0)))
	var st := ConfigFile.new()
	st.load(Shell.STATE)
	var have := maxi(running(), int(st.get_value("pck", "build", 0)))
	match plan(Shell.app_info(), have, info, int(st.get_value("boot", "bad", 0))):
		"apk":
			_set_status("apk")
		"pck":
			_download(info)
		_:
			# a newer build is already downloaded but not running yet
			_set_status("ready" if have > running() else "current")

# [HTTP code (0 = no answer), parsed JSON or null]; a fresh copy, not a cached one
func _fetch_json(url: String) -> Array:
	_http.download_file = ""
	_http.body_size_limit = 64 * 1024
	if _http.request(url, ["Cache-Control: no-cache"]) != OK:
		return [0, null]
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return [0, null]
	if res[1] != 200:
		return [res[1], null]
	return [200, JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())]

func _download(info: Dictionary) -> void:
	_want = info
	_set_status("downloading")
	DirAccess.make_dir_recursive_absolute(Shell.DIR)
	_http.download_file = PART
	_http.body_size_limit = MAX_BYTES
	_http.timeout = 600.0
	var err := _http.request(source + str(info["pck"]) + "?b=%d" % int(info["build"]))
	var res: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0] if err != OK else await _http.request_completed
	_http.download_file = ""
	_http.timeout = 20.0
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200 or not _verify(PART, info):
		DirAccess.remove_absolute(PART)
		_set_status("error")
		return
	var b := int(info["build"])
	DirAccess.rename_absolute(PART, Shell.pck_path(Shell.DIR, b))
	var st := ConfigFile.new()
	st.load(Shell.STATE)
	st.set_value("pck", "build", b)
	st.set_value("pck", "sha256", str(info["sha256"]))
	st.set_value("pck", "shell", BuildInfo.SHELL)
	st.set_value("pck", "engine", BuildInfo.ENGINE)
	st.set_value("pck", "tries", 0)
	st.save(Shell.STATE)
	# an older download that never ran is no longer needed (never the one running now: the
	# engine reads a mounted pack again at the offsets it saw at launch)
	var d := DirAccess.open(Shell.DIR)
	for f in d.get_files():
		if f.begins_with("game-") and f.ends_with(".pck") and f != Shell.pck_path("", b) and f != Shell.pck_path("", running()):
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

# The home page's pencilled version note (Guillaume, 2026-11-14: the version and a way to check
# for an update, "in the home screen if it's more discreet"): [text, loud]. Loud = an update to
# take (red, on a taped slip); otherwise a quiet pencil line. "" = no note (a build that never
# updates itself). Tapping it calls press().
func home_note() -> Array:
	if status == "off":
		return ["", false]
	var b := "build %d" % running()
	match status:
		"ready": return ["build %d ready  ·  restart  ›" % maxi(latest, int(_want.get("build", 0))), true]
		"apk": return ["new version  ·  install  ›", true]
		"checking": return [b + "  ·  checking…", false]
		"downloading": return ["downloading build %d…" % int(_want.get("build", 0)), false]
		"current": return [b + "  ·  up to date  ›", false]
		"error": return [b + "  ·  offline, tap to retry  ›", false]
	return [b + "  ·  check for update  ›", false]

# take the update
func act() -> void:
	if status == "ready":
		# Android (and desktop) start the game again; the new data mounts at launch
		OS.set_restart_on_exit(true)
		get_tree().quit()
	elif status == "apk":
		OS.shell_open((source if source != "" else BuildInfo.CHANNEL) + APK)

# ------------------------------------------------------------ the version in words
# "Build 328", or what kind of build this is
func version_title() -> String:
	if BuildInfo.BUILD == 0:
		return "Development build"
	var s := "Build %d" % running()
	if running() != BuildInfo.BUILD:
		s += "  (app %d)" % BuildInfo.BUILD
	return s

# what the updater is doing, in words
func status_text() -> String:
	if status == "off":
		if BuildInfo.BUILD == 0:
			return "Made by hand: no updates"
		return "The browser always runs the latest build" if OS.has_feature("web") else "Updates come from the store"
	match status:
		"checking": return "Checking for updates…"
		"current": return "Up to date"
		"downloading": return "Downloading build %d…" % int(_want.get("build", 0))
		"ready": return "Build %d is ready: restart to play it" % maxi(latest, int(_want.get("build", 0)))
		"apk": return "Build %d needs the new app: install it" % latest
		"error": return "Couldn't reach the update server (offline?)"
	return "Not checked yet"

# the version note was tapped: take the update, or look for one now
func press() -> void:
	if status in ["ready", "apk"]:
		act()
	else:
		_checked_ms = -1
		check()

# one line (kept for logs and tests)
func version_line() -> String:
	return version_title() + "  ·  " + status_text()
