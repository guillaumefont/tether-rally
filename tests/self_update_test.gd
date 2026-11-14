# Test builds update themselves (Guillaume, 2026-11-14: "Can you build a version of the game
# that updates itself?"). An installed test APK reads update.json from its own Pages folder,
# downloads a newer build's game data (game.pck) and mounts it at the next launch; a build
# that changed the engine or project settings needs its APK instead. Only our own HTTPS
# Pages site, never on a build without the feature, and a broken download never sticks.
#   godot --headless --path . --script tests/self_update_test.gd
extends SceneTree

const SelfUpdate = preload("res://scripts/self_update.gd")
const Updater = preload("res://scripts/updater.gd")
const BuildInfo = preload("res://scripts/build_info.gd")
const Settings = preload("res://scripts/settings.gd")

const DIR := "user://self_update_test/"

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	Settings._load().set_value("options", "tutorial_done", true)
	_run.call_deferred()

func _info(build: int, shell := "abc", sha := "") -> Dictionary:
	return { "build": build, "engine": Updater.engine_version(), "shell": shell, "pck": "game.pck",
		"size": 1000, "sha256": sha if sha != "" else "0123456789abcdef".repeat(4), "apk": "tether-racing.apk" }

func _wipe() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			d.remove(f)
	DirAccess.make_dir_recursive_absolute(DIR)

# a real pack holding one file, as the CI's game.pck holds the whole game
func _make_pck(build: int, text: String) -> String:
	var path := SelfUpdate.pck_path(DIR, build)
	var tmp := DIR + "probe.txt"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var p := PCKPacker.new()
	p.pck_start(path)
	p.add_file("res://tests/self_update_probe.txt", tmp)
	p.flush()
	DirAccess.remove_absolute(tmp)
	return path

func _state(build: int, sha: String, shell := "abc", tries := 0) -> void:
	var st := ConfigFile.new()
	st.load(DIR + "state.cfg")
	st.set_value("pck", "build", build)
	st.set_value("pck", "sha256", sha)
	st.set_value("pck", "shell", shell)
	st.set_value("pck", "engine", Updater.engine_version())
	st.set_value("pck", "tries", tries)
	st.save(DIR + "state.cfg")

func _run() -> void:
	# only test builds made by CI update themselves; a hand-made (or store) build never does
	check(not SelfUpdate.enabled(), "a build without the self_update feature never updates itself")
	check(root.get_node_or_null("SelfUpdate") != null, "the launch part is loaded first (autoload)")
	await process_frame
	var su := root.get_node_or_null("SelfUpdate/Updater")
	check(su != null and su.status == "off", "it starts the updater from the game data, which stays off here")
	check(ProjectSettings.get_setting("autoload/SelfUpdate", "") == "*res://scripts/self_update.gd", "the updater is the app's autoload, so it runs before main.tscn loads")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.contains("permissions/internet=true"), "the Android app may reach the network")
	check(presets.contains('custom_features=""'), "the committed presets carry no self_update feature (CI adds it to test APKs only)")
	var ci := FileAccess.get_file_as_string("res://.github/workflows/build.yml")
	check(ci.contains('custom_features="preview,self_update"') and ci.contains("--export-pack Android") and ci.contains("update.json"),
		"CI exports test APKs with the feature, and publishes game.pck + update.json beside them")

	# where it may look: our own Pages site over HTTPS, nothing else
	for u in ["https://guillaumefont.github.io/tether-rally/", "https://guillaumefont.github.io/tether-rally/pr/91/"]:
		check(Updater.channel_ok(u), "allowed: " + u)
	for u in ["http://guillaumefont.github.io/tether-rally/", "https://guillaumefont.github.io.evil.com/x/",
			"https://evil.com/tether-rally/", "https://guillaumefont.github.io/tether-rally", "https://a.b.github.io/x/",
			"https://guillaumefont.github.io/tether-rally/../x/", "https://x@guillaumefont.github.io/t/", ""]:
		check(not Updater.channel_ok(u), "refused: '%s'" % u)

	# a PR's APK: its own folder, then main once the PR is gone
	check(Updater.channels("https://guillaumefont.github.io/tether-rally/pr/91/") == ["https://guillaumefont.github.io/tether-rally/pr/91/", "https://guillaumefont.github.io/tether-rally/"],
		"a PR's APK falls back to main once its PR folder is gone")
	check(Updater.channels("https://guillaumefont.github.io/tether-rally/") == ["https://guillaumefont.github.io/tether-rally/"], "main's APK looks at main only")
	check(Updater.channels("http://evil.com/pr/1/").is_empty(), "nothing outside our site")
	var shell_src := FileAccess.get_file_as_string("res://scripts/self_update.gd")
	check(not shell_src.contains("HTTPRequest") and shell_src.contains('load("res://scripts/updater.gd")'),
		"the frozen launch part only mounts; checking and downloading live in the updatable updater.gd")

	# what to do with a published build
	var app := { "build": 240, "shell": "abc", "engine": Updater.engine_version() }
	check(Updater.plan(app, 240, _info(245)) == "pck", "newer build, same app: download its game data")
	check(Updater.plan(app, 240, _info(240)) == "none", "same build: nothing")
	check(Updater.plan(app, 240, _info(238)) == "none", "older build: never go back")
	check(Updater.plan(app, 246, _info(245)) == "none", "already have a newer download: nothing")
	check(Updater.plan(app, 240, _info(245, "xyz")) == "apk", "new engine/settings/updater: offer the new APK")
	var other_engine := _info(245)
	other_engine["engine"] = "9.9.9"
	check(Updater.plan(app, 240, other_engine) == "apk", "another engine version: offer the new APK")
	check(Updater.plan(app, 240, _info(245), 245) == "none", "a build that failed to start here is not fetched again")
	check(Updater.plan(app, 240, _info(245, "abc", "nothex")) == "none", "no valid checksum: nothing")
	var big := _info(245)
	big["size"] = Updater.MAX_BYTES + 1
	check(Updater.plan(app, 240, big) == "none", "absurd size: nothing")
	var sneaky := _info(245)
	sneaky["pck"] = "../../game.pck"
	check(Updater.plan(app, 240, sneaky) == "none", "a file name with a path: nothing")
	check(Updater.plan(app, 240, {}) == "none" and Updater.plan(app, 240, { "build": "x" }) == "none", "garbage update.json: nothing")

	# at launch: which downloaded game data to mount
	_wipe()
	check(SelfUpdate.pick_saved(DIR, app).is_empty(), "nothing downloaded: the app's own data")
	var path := _make_pck(245, "build 245")
	var sha := FileAccess.get_sha256(path)
	_make_pck(243, "old")   # an older download left behind
	_state(245, sha)
	var pick := SelfUpdate.pick_saved(DIR, app)
	check(pick.get("build", 0) == 245 and pick.get("path", "") == path, "a good download newer than the app is mounted")
	check(not FileAccess.file_exists(SelfUpdate.pck_path(DIR, 243)), "older downloads are deleted")
	check(ProjectSettings.load_resource_pack(pick["path"], true), "the downloaded pack mounts")
	check(FileAccess.get_file_as_string("res://tests/self_update_probe.txt") == "build 245", "files come from the downloaded build after mounting")

	# a downloaded build that never reaches the menu is dropped after MAX_TRIES launches
	SelfUpdate.confirm_in(DIR)
	for i in SelfUpdate.MAX_TRIES:
		check(not SelfUpdate.pick_saved(DIR, app).is_empty(), "launch %d without reaching the menu: still tried" % (i + 1))
	check(SelfUpdate.pick_saved(DIR, app).is_empty(), "then it is dropped: the app's own data runs again")
	var st := ConfigFile.new()
	st.load(DIR + "state.cfg")
	check(int(st.get_value("boot", "bad", 0)) == 245, "and remembered as bad, so it is not downloaded again")
	check(not FileAccess.file_exists(path), "its file is deleted")
	# reaching the menu clears the count
	path = _make_pck(247, "build 247")
	_state(247, FileAccess.get_sha256(path))
	var kept := true
	for i in 5:
		kept = kept and not SelfUpdate.pick_saved(DIR, app).is_empty()
		SelfUpdate.confirm_in(DIR)
	check(kept, "launches that reach the menu keep it, however many")

	# damaged, stale or foreign downloads are never mounted
	_state(247, "0".repeat(64))
	check(SelfUpdate.pick_saved(DIR, app).is_empty() and not FileAccess.file_exists(path), "a damaged download (checksum) is dropped")
	path = _make_pck(247, "x")
	_state(247, FileAccess.get_sha256(path))
	var newer_app := app.duplicate()
	newer_app["build"] = 250
	check(SelfUpdate.pick_saved(DIR, newer_app).is_empty() and not FileAccess.file_exists(path), "a newer APK installed since: the older download is dropped")
	path = _make_pck(247, "x")
	_state(247, FileAccess.get_sha256(path), "xyz")
	check(SelfUpdate.pick_saved(DIR, app).is_empty(), "a download made for another app shell is dropped")
	_wipe()

	# the home page's slip and the Settings line
	check(su.version_line().begins_with("Development build" if BuildInfo.BUILD == 0 else "Build"), "Settings names the build: " + su.version_line())
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var ui = main.ui
	var menu = ui.menu
	ui.loading.visible = false
	for sz in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		root.size = sz
		await frames(3)
		su.status = "current"
		menu.show_home()
		await create_timer(1.0).timeout
		var tag := "%dx%d" % [sz.x, sz.y]
		check(_slips(menu).is_empty(), "%s: up to date: no slip on the home page" % tag)
		su._set_status("ready")   # a download finishes while the home page is up
		await frames(3)
		var s := _slips(menu)
		check(s.size() == 1, "%s: update ready: one slip appears on the home page right away" % tag)
		if s.size() == 1:
			check(root.get_visible_rect().encloses(s[0].get_global_rect()), "%s: the slip is on screen" % tag)
			check(s[0].size.y >= 36.0, "%s: big enough to tap" % tag)
			var tabs: Array = menu.body.find_children("*", "Button", true, false).filter(func(b): return b != s[0] and b.is_visible_in_tree() and not b.has_meta("update_slip"))
			check(not tabs.any(func(b): return b.get_global_rect().intersects(s[0].get_global_rect())), "%s: it covers no other button" % tag)
			check(s[0].get_child(0).text.contains("restart"), "%s: it says restart" % tag)
		su._set_status("apk")
		await frames(3)
		s = _slips(menu)
		check(s.size() == 1 and s[0].get_child(0).text.contains("install"), "%s: a build needing the new app offers the install" % tag)
		su._set_status("current")
		await frames(3)
		check(_slips(menu).is_empty(), "%s: gone when there is nothing to offer" % tag)
	# Settings: the game version, and a button to check for an update (Guillaume, 2026-11-14)
	su.status = "off"
	ui.show_settings(main._options(true))
	await frames(2)
	check(ui._ver_box.is_visible_in_tree(), "Settings shows a GAME VERSION box")
	check(ui._ver_title.text == su.version_title() and ui._ver_title.text != "", "it names the build: " + ui._ver_title.text)
	check(not ui._ver_btn.visible, "a build that never updates itself has no check button: " + ui._ver_status.text)
	var cases := { "idle": ["CHECK FOR UPDATE", true], "current": ["CHECK FOR UPDATE", true], "error": ["CHECK FOR UPDATE", true],
		"checking": ["CHECK FOR UPDATE", false], "downloading": ["CHECK FOR UPDATE", false],
		"ready": ["RESTART TO UPDATE", true], "apk": ["INSTALL NEW VERSION", true] }
	for stt in cases:
		su._set_status(stt)   # the box follows the updater while it is open
		await frames(1)
		var lbl: Label = ui._ver_btn.get_meta("label")
		check(ui._ver_btn.visible and lbl.text == cases[stt][0] and ui._ver_btn.disabled != cases[stt][1],
			"%s: button '%s'%s, says '%s'" % [stt, lbl.text, "" if cases[stt][1] else " (greyed)", ui._ver_status.text])
		check(ui._ver_status.text == su.status_text() and ui._ver_status.text != "", "%s: the status is spelled out" % stt)
	ui._uh = 450   # a phone
	for sz in [Vector2i(1280, 720), Vector2i(720, 1280), Vector2i(2400, 1080), Vector2i(1080, 2400)]:
		root.size = sz
		ui._apply_scale()
		await frames(3)
		var r: Rect2 = ui._ver_btn.get_global_rect()
		check(root.get_visible_rect().encloses(r) and r.size.y >= 40.0, "%dx%d: the button is on screen and tappable" % [sz.x, sz.y])
		var panel: Rect2 = ui.settings_panel.get_global_rect()
		check(root.get_visible_rect().grow(1.0).encloses(panel), "%dx%d: the whole Settings page still fits on screen (DONE included)" % [sz.x, sz.y])
	su.status = "off"
	ui.hide_settings()

	print("self update test: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)

func _slips(menu) -> Array:
	return menu.body.get_children().filter(func(c): return c.has_meta("update_slip") and not c.is_queued_for_deletion())
