# Rewarded-ad offers on the results screen (docs/monetization.md):
# - Gold ghost: one per track for Standard/Reverse/Obstacles (not Collect) lapping at the Gold
#   time; offered after a run without Gold, unlocked for good by the video, not after a Gold run
# - Daily Detour: an attempt is used at GO, given back by a first-lap quit, only from the banner;
#   with none left the banner starts practice (no coins); a video adds one
# - full-screen ads when leaving the results: none in the first session, before 6 races, after
#   the tutorial, Off the Map or with No ads; then one every 4 races, a test card meanwhile
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

# the countdown runs out: GO
func go() -> void:
	main.countdown = 0.1
	for i in 3:
		await process_frame

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

	# ---- the Gold ghost: every lap variant has one that laps at the Gold time
	var GoldGhosts = load("res://scripts/gold_ghosts.gd")
	var n := 0
	for d in Defs.TRACKS:
		for v in ["standard", "reverse", "obstacles", "collect"]:
			var has: bool = GoldGhosts.has(d["name"], v)
			if v == "collect":
				if has:
					check(false, "no Gold ghost on Collect (%s)" % d["name"])
				continue
			if not has:
				check(false, "Gold ghost for %s %s" % [d["name"], v])
				continue
			n += 1
			var g: float = Medals.targets(d["name"], v)[2]
			var lt: float = GoldGhosts.lap_time(d["name"], v)
			if absf(lt - g) > 0.05:
				check(false, "%s %s Gold ghost laps in %.3f, Gold is %.2f" % [d["name"], v, lt, g])
			if GoldGhosts.trace(d["name"], v).size() != GoldGhosts.hooked(d["name"], v).size():
				check(false, "%s %s hook marks match the samples" % [d["name"], v])
	check(n == Defs.TRACKS.size() * 3, "a Gold ghost per track for Standard, Reverse and Obstacles (%d)" % n)

	# ---- offered after a run without Gold, unlocked for good by the video
	Store._cfg = ConfigFile.new()   # no "No ads" any more
	Wallet.reset()
	Records.reset()
	await start(ev)
	check(main.view.gold_node == null, "no Gold ghost before it is unlocked")
	var silver: float = Medals.targets(name, "standard")[1]
	await finish_trial(silver - 0.05)   # Silver, not Gold
	check(offers().has("gold_ghost"), "Gold ghost offered after a run without Gold (%s)" % str(offers()))
	offer_btn("gold_ghost").pressed.emit()
	await frames(2)
	check(GoldGhosts.unlocked(name, "standard"), "the video unlocks it")
	check(not offers().has("gold_ghost"), "the offer goes once taken")
	await start(ev)
	check(main.view.gold_node != null and not main.gold_ghost.is_empty(), "the next run brings the Gold ghost")
	check(not GoldGhosts.unlocked(name, "reverse"), "only on that track + variant")
	await finish_trial(silver - 0.05)
	check(not offers().has("gold_ghost"), "not offered again once open")
	# a Gold run never offers it
	await start({ "track": 1, "variant": "standard", "mode": "trial", "humans": 1, "kind": "attack", "idx": 0, "theme": "" })
	await finish_trial(Medals.targets(Defs.TRACKS[1]["name"], "standard")[2] - 0.1)
	check(not offers().has("gold_ghost"), "no Gold ghost offer after a Gold run")
	# Reset progress closes it again
	Wallet.reset()
	check(not GoldGhosts.unlocked(name, "standard"), "Reset progress closes unlocked Gold ghosts")

	# ---- Daily Detour: scored attempts from the banner only
	Wallet.reset()
	Records.reset()
	var dday := Daily.day_of(2026, 11, 20)
	Daily.fake_day = dday
	var p: Dictionary = Daily.current()
	var dev := { "track": p["track"], "variant": p["variant"], "mode": "trial", "humans": 1, "kind": "daily", "idx": 0, "theme": "" }
	var dname: String = Defs.TRACKS[p["track"]]["name"]
	var dgold: float = Medals.targets(dname, p["variant"])[2]
	# the same track from Special Stages uses no attempt and pays no Daily Detour coins
	await start({ "track": p["track"], "variant": p["variant"], "mode": "trial", "humans": 1, "kind": "attack", "idx": 0, "theme": "" })
	await go()
	await finish_trial(dgold + 5.0)
	check(Daily.attempts_left() == 3 and Daily.paid_tier() < 0, "Special Stages on the daily track uses nothing")
	# a quit in the first lap gives the attempt back
	await start(dev)
	check(main.daily_scored, "a banner run is scored")
	await go()
	check(Daily.attempts_left() == 2, "the attempt is used at GO")
	main._pause_action("restart")
	await frames(2)
	check(Daily.attempts_left() == 3, "a restart in the first lap gives it back")
	# a quit later on uses it
	await go()
	main.race.cars[0].lap = 2
	main._to_menu()
	check(Daily.attempts_left() == 2, "a quit after the first lap uses it")
	# two finished attempts pay; the best counts
	for k in 2:
		await start(dev)
		await go()
		await finish_trial(dgold + 1.0 - k)
	check(Daily.attempts_left() == 0, "three attempts used")
	check(Daily.paid_tier() >= 0 and Daily.best_today() > 0.0, "scored runs pay and set today's best")
	check(offers().has("daily_extra"), "+1 scored attempt offered with none left (%s)" % str(offers()))
	# a 4th run is practice: no coins
	var c4 := Wallet.coins()
	var best4 := Daily.best_today()
	await start(dev)
	check(not main.daily_scored, "with none left the banner starts practice")
	await go()
	await finish_trial(dgold - 0.5)
	check(Wallet.coins() == c4 and main.pay_total == 0, "practice pays nothing (%d)" % (Wallet.coins() - c4))
	check(Daily.best_today() == best4, "practice sets no daily best")
	# the ad gives one more scored attempt
	offer_btn("daily_extra").pressed.emit()
	await frames(2)
	check(Daily.attempts_left() == 1, "+1 scored attempt after the video")
	Daily.fake_day = dday + 1
	check(Daily.attempts_left() == 3, "three again the next day")

	# ---- full-screen ads: none in the first session or before 6 races, then one every 4
	Daily.fake_day = Daily.day_of(2030, 1, 1)
	Store._cfg = ConfigFile.new()
	Wallet.reset()
	Monetization.fake_now = 5_000_000
	Ads._last_ad_ms = -1
	var Settings = load("res://scripts/settings.gd")
	var launches_was: int = Monetization.launches()
	Settings.set_opt("launches", 1)
	var ads_seen := [0]
	var leave := func():
		var went := [false]
		main._leave_results(func(): went[0] = true)
		var shown: bool = main._ad_showing
		if shown:
			ads_seen[0] += 1
			check(main.ui.ad_card.visible, "the test ad card covers the screen")
			await create_timer(Ads.stub_delay + 0.3).timeout
			check(not main.ui.ad_card.visible, "the card goes after the ad")
		check(went[0], "the player goes on after leaving the results")
	Ads.stub_delay = 0.2
	for k in 8:
		await start(ev)
		await finish_trial(gold + 3.0)
		Monetization.fake_now += 600
		await leave.call()
	check(ads_seen[0] == 0, "no full-screen ad in the first session (%d)" % ads_seen[0])
	Settings.set_opt("launches", 2)
	Wallet.set_v("ads", "races", 0)
	Wallet.set_v("ads", "since_ad", 0)
	for k in 5:
		await start(ev)
		await finish_trial(gold + 3.0)
		Monetization.fake_now += 600
		await leave.call()
	check(ads_seen[0] == 0, "none before 6 races")
	for k in 9:
		await start(ev)
		await finish_trial(gold + 3.0)
		Monetization.fake_now += 600
		Ads._last_ad_ms = -1
		await leave.call()
	check(ads_seen[0] == 3, "then one every 4 races (%d after 14)" % ads_seen[0])
	# the tutorial's end screen never leads to one
	Wallet.set_v("ads", "since_ad", 10)
	Monetization.fake_now += 600
	main.tutorial = true
	await leave.call()
	main.tutorial = false
	check(ads_seen[0] == 3, "never after the tutorial")
	# nor Off the Map
	await start({ "track": 0, "variant": "standard", "mode": "trial", "humans": 1, "kind": "custom", "idx": 0, "theme": "", "laps": 1 })
	await finish_trial(gold + 3.0)
	await leave.call()
	check(ads_seen[0] == 3, "never after Off the Map")
	# No ads: none
	Store.buy("remove_ads")
	await start(ev)
	await finish_trial(gold + 3.0)
	await leave.call()
	check(ads_seen[0] == 3, "never with No ads")
	Settings.set_opt("launches", launches_was)
	Monetization.fake_now = -1
	Ads.stub_delay = 0.0

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
