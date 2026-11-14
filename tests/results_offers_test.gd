# Rewarded-ad offers on the results screen (docs/monetization.md):
# - "x2 coins": the wallet gets the run's coins a second time, once per results screen; the
#   badge says so; the daily cap holds; never after Off the Map, the tutorial or a 2-player race
#   godot --headless --path . --script tests/results_offers_test.gd
extends SceneTree

const Records = preload("res://scripts/records.gd")
const Wallet = preload("res://scripts/wallet.gd")
const Store = preload("res://scripts/store.gd")
const Ads = preload("res://scripts/ads.gd")
const Monetization = preload("res://scripts/monetization.gd")
const Medals = preload("res://scripts/medals.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Daily = preload("res://scripts/daily.gd")

var fails := 0
var main: Node

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func offers() -> Array:
	return main.ui.res_offers.get_children().filter(func(b): return b.has_meta("offer") and not b.is_queued_for_deletion()).map(func(b): return b.get_meta("offer"))

func offer_btn(id: String) -> Button:
	for b in main.ui.res_offers.get_children():
		if b.has_meta("offer") and b.get_meta("offer") == id and not b.is_queued_for_deletion():
			return b
	return null

func start(ev: Dictionary) -> void:
	main.race = null
	main.phase = "menu"
	main._start_event(ev)
	for i in 300:
		await process_frame
		if main.race != null and not main.building:
			break

# a finished Time trial run with lap time `lap`
func finish_trial(lap: float) -> void:
	var me = main.race.cars[0]
	main._trial_lap(me, lap, [])
	me.finished = true
	me.finish_time = lap
	me.best_lap = lap
	main._trial_run(me)
	main._show_results()
	await frames(2)

func _initialize() -> void:
	_run()

func _run() -> void:
	var store_was := FileAccess.get_file_as_string(Store.PATH)
	Store._cfg = ConfigFile.new()
	Records.reset()
	Wallet.reset()
	Daily.fake_day = Daily.day_of(2030, 1, 1)   # no Daily Detour on track 0 in the way
	Ads.stub_delay = 0.0
	Ads._last_ad_ms = -1
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	main.ui.loading.visible = false
	var name: String = Defs.TRACKS[0]["name"]
	var gold: float = Medals.targets(name, "standard")[2]
	var ev := { "track": 0, "variant": "standard", "mode": "trial", "humans": 1, "kind": "attack", "idx": 0, "theme": "" }

	# a Gold run pays coins: x2 is offered, and pays the same again once
	await start(ev)
	await finish_trial(gold - 0.2)
	var paid: int = main.pay_total
	check(paid > 0, "a first Gold pays coins (%d)" % paid)
	check(offers() == ["double_coins"], "x2 coins offered (%s)" % str(offers()))
	check(main.ui.res_noads.visible and main.ui.res_noads.text.begins_with("No ads?"), "the No ads link sits under it")
	var before := Wallet.coins()
	var b := offer_btn("double_coins")
	b.pressed.emit()
	await frames(2)
	check(Wallet.coins() - before == paid, "x2 paid the run's coins again (%d, want %d)" % [Wallet.coins() - before, paid])
	check(offers().is_empty(), "x2 gone once taken")
	var badge: Label = main.ui.res_rewards.get_child(0).get_meta("label")
	check(badge.text == "+%d x2 COINS" % paid, "the coin badge says x2 (%s)" % badge.text)
	main._offer_pressed("double_coins")
	await frames(2)
	check(Wallet.coins() - before == paid, "only once per results screen")
	check(Monetization.used_today("double_coins") == 1, "counted for the daily cap")

	# a run that pays nothing offers nothing
	await start(ev)
	await finish_trial(gold * 3.0)
	check(main.pay_total == 0 and offers().is_empty(), "no coins, no x2")

	# the daily cap
	await start(ev)
	Wallet.set_v("ads", "double_coins", Monetization.DOUBLE_COINS_PER_DAY)
	Wallet.set_v("ads", "double_coins_day", Daily.today())
	await finish_trial(gold - 0.1)   # repeat Gold: still pays
	check(main.pay_total > 0 and offers().is_empty(), "no x2 past the daily cap")
	Wallet.set_v("ads", "double_coins", 0)

	# with No ads, x2 is granted without a video and the link goes
	Store.buy("remove_ads")
	Ads.stub_delay = 5.0
	await start(ev)
	await finish_trial(gold - 0.1)
	check(offers() == ["double_coins"] and not main.ui.res_noads.visible, "No ads: x2 offered, no link")
	before = Wallet.coins()
	offer_btn("double_coins").pressed.emit()
	await frames(2)
	check(Wallet.coins() - before == main.pay_total, "No ads: x2 at once")
	Ads.stub_delay = 0.0

	# Off the Map never offers
	await start({ "track": 0, "variant": "standard", "mode": "trial", "humans": 1, "kind": "custom", "idx": 0, "theme": "", "laps": 1 })
	await finish_trial(gold - 0.3)
	check(offers().is_empty(), "nothing after Off the Map")
	# nor a 2-player race
	check(Monetization.results_offers({ "total": 50, "humans": 2 }).is_empty(), "nothing after a 2-player race")
	check(Monetization.results_offers({ "total": 50, "tutorial": true }).is_empty(), "nothing after the tutorial")
	# the tutorial's end screen clears any offers
	main.ui.set_offers([{ "id": "double_coins", "text": "x2 coins" }])
	main.ui.show_results("TUTORIAL DONE", [], "", false, 2)
	await frames(1)
	check(offers().is_empty(), "the tutorial's end screen has no offers")

	# put things back
	Daily.fake_day = -1
	Store._listeners.clear()
	if store_was == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.PATH))
	else:
		var f := FileAccess.open(Store.PATH, FileAccess.WRITE)
		f.store_string(store_was)
		f.close()
	Store._cfg = null
	Records.reset()
	Wallet.reset()
	print("results offers test: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails else 0)
