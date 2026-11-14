extends SceneTree
# The Play store build (docs/monetization.md): a separate export preset, "Android Play", an AAB
# built with Gradle (needed by the Billing and AdMob plugins). It must never carry "preview"
# (the Store/Ads stubs would give purchases away) nor "self_update" (Play forbids self-updating
# code), and CI must never add them to it. The ad id permission is declared.
#   godot --headless --path . --script tests/store_build_test.gd
const Store = preload("res://scripts/store.gd")

var bad := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		bad += 1

func _init() -> void:
	var cfg := ConfigFile.new()
	check(cfg.load("res://export_presets.cfg") == OK, "export presets load")
	var play := ""
	var test_apk := ""
	for sec in cfg.get_sections():
		if sec.ends_with(".options") or not sec.begins_with("preset."):
			continue
		var nm := String(cfg.get_value(sec, "name", ""))
		if nm == "Android Play":
			play = sec
		elif nm == "Android":
			test_apk = sec
	check(play != "", "an Android Play preset exists")
	check(test_apk != "", "the test APK preset is still there")
	if play != "":
		var feats := String(cfg.get_value(play, "custom_features", ""))
		check(not feats.contains("preview"), "the Play build has no preview feature (stubs would give purchases away)")
		check(not feats.contains("self_update"), "the Play build never updates itself")
		var o := play + ".options"
		check(bool(cfg.get_value(o, "gradle_build/use_gradle_build", false)), "the Play build uses Gradle (Billing and AdMob plugins)")
		check(int(cfg.get_value(o, "gradle_build/export_format", 0)) == 1, "the Play build is an AAB")
		var perms: PackedStringArray = cfg.get_value(o, "permissions/custom_permissions", PackedStringArray())
		check(perms.has("com.google.android.gms.permission.AD_ID"), "the ad id permission is declared")
		check(cfg.get_value(o, "package/unique_name") == cfg.get_value(test_apk + ".options", "package/unique_name"), "same app id as the test APKs (it will change: reconfirm before the first Play upload)")
	# CI turns test features on for the test presets only
	var wf := FileAccess.get_file_as_string("res://.github/workflows/build.yml")
	check(wf != "", "build workflow readable")
	for line in wf.split("\n"):
		if line.contains("custom_features=") and (line.contains("preset.3") or line.contains("Android Play")):
			check(false, "CI never edits the Play preset's features: " + line.strip_edges())
	printerr("STORE BUILD BAD: %d" % bad)
	quit(1 if bad > 0 else 0)
