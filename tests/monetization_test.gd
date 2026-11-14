extends SceneTree
# Ads, Store and Monetization stubs (docs/monetization.md, phase 1 step 1):
# - the stub plays a rewarded video and grants the reward only when it ends, once
# - a capped placement stops at its daily cap and comes back the next day
# - full-screen ads: none in the first session or before INTERSTITIAL_MIN_RACES races,
#   then one every INTERSTITIAL_EVERY races, never inside the cooldown after another ad
# - buying "No ads" ends full-screen ads and grants every reward without a video
# - buying answers through a callback; "Reset progress" never takes a purchase back
const Ads = preload("res://scripts/ads.gd")
const Store = preload("res://scripts/store.gd")
const Monetization = preload("res://scripts/monetization.gd")
const Wallet = preload("res://scripts/wallet.gd")
const Daily = preload("res://scripts/daily.gd")
const Settings = preload("res://scripts/settings.gd")
const M = Monetization

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func expect(got, want, what: String) -> void:
	if got != want:
		fail("%s: got %s, want %s" % [what, str(got), str(want)])

func _initialize() -> void:
	_run()

func _run() -> void:
	# keep the player's own files as they were
	var store_was := FileAccess.get_file_as_string(Store.PATH)
	var launches_was := M.launches()
	Store._cfg = ConfigFile.new()   # a store with nothing bought
	Wallet.reset()
	var day := Daily.day_of(2026, 11, 14)
	Daily.fake_day = day
	Ads._last_ad_ms = -1
	M.fake_now = 1_000_000
	Settings.set_opt("launches", 0)

	# ---- the stub video: reward only once it has played
	expect(Store.available(), true, "stub store open in a debug run")
	expect(Ads.ads_removed(), false, "ads on without the purchase")
	expect(Ads.rewarded_ready("double_coins"), true, "x2 coins ready")
	expect(Ads.rewarded_ready("no_such_placement"), false, "unknown placement never ready")
	var got := [0]
	Ads.stub_delay = 0.1
	expect(Ads.show_rewarded("double_coins", func(): got[0] += 1), true, "video starts")
	expect(got[0], 0, "no reward while the video plays")
	expect(Ads.rewarded_ready("gold_ghost"), false, "one video at a time")
	await create_timer(0.4).timeout
	expect(got[0], 1, "reward once the video ended")
	expect(M.used_today("double_coins"), 1, "x2 coins counted")
	expect(Ads.since_last_ad() >= 0.0, true, "the video starts the ad cooldown")

	# ---- the daily cap
	Ads.stub_delay = 0.0
	for k in M.DOUBLE_COINS_PER_DAY - 1:
		Ads.show_rewarded("double_coins", func(): got[0] += 1)
	expect(got[0], M.DOUBLE_COINS_PER_DAY, "rewards up to the cap")
	expect(Ads.rewarded_ready("double_coins"), false, "x2 coins capped for today")
	expect(Ads.show_rewarded("double_coins", func(): got[0] += 1), false, "capped video refused")
	expect(got[0], M.DOUBLE_COINS_PER_DAY, "no reward past the cap")
	expect(Ads.rewarded_ready("gold_ghost"), true, "an uncapped placement stays ready")
	Daily.fake_day = day + 1
	expect(M.used_today("double_coins"), 0, "counter starts again the next day")
	expect(Ads.rewarded_ready("double_coins"), true, "x2 coins back the next day")
	Daily.fake_day = day

	# ---- full-screen ad pacing
	Ads._last_ad_ms = -1
	M.note_launch()   # first session
	for k in 10:
		M.note_race()
	expect(Ads.maybe_interstitial("after_results"), false, "never in the first session")
	M.note_launch()
	Wallet.set_v("ads", "races", 0)
	Wallet.set_v("ads", "since_ad", 0)
	for k in M.INTERSTITIAL_MIN_RACES - 1:
		M.note_race()
		expect(Ads.maybe_interstitial("after_results"), false, "none before %d races (race %d)" % [M.INTERSTITIAL_MIN_RACES, k + 1])
	M.note_race()
	expect(Ads.maybe_interstitial("during_race"), false, "only when leaving the results")
	var called := [false]
	expect(Ads.maybe_interstitial("after_results", func(): called[0] = true), true, "first full-screen ad after %d races" % M.INTERSTITIAL_MIN_RACES)
	expect(called[0], true, "the player goes on after it")
	var shown := 0
	for k in M.INTERSTITIAL_EVERY * 3:
		M.note_race()
		Ads._last_ad_ms = -1   # past the cooldown
		M.fake_now += M.INTERSTITIAL_MIN_GAP_S / M.INTERSTITIAL_EVERY + 1   # races of ~2 min
		if Ads.maybe_interstitial("after_results"):
			shown += 1
	expect(shown, 3, "one every %d races" % M.INTERSTITIAL_EVERY)
	# short races: the time gap holds them back
	shown = 0
	for k in M.INTERSTITIAL_EVERY * 3:
		M.note_race()
		Ads._last_ad_ms = -1
		M.fake_now += 40   # a 40 s race
		if Ads.maybe_interstitial("after_results"):
			shown += 1
	expect(shown <= int(ceil(12 * 40.0 / M.INTERSTITIAL_MIN_GAP_S)), true, "at most one per %d s with 40 s races (%d shown)" % [M.INTERSTITIAL_MIN_GAP_S, shown])
	M.fake_now += M.INTERSTITIAL_MIN_GAP_S
	for k in M.INTERSTITIAL_EVERY:
		M.note_race()
	Ads.show_rewarded("gold_ghost", func(): pass)   # a video just played
	expect(Ads.maybe_interstitial("after_results"), false, "none in the cooldown after a video")
	expect(M.interstitial_due(M.INTERSTITIAL_COOLDOWN_S + 1.0), true, "due again after the cooldown")

	# ---- buying is answered through the callback
	var changes := [0]
	var listen := func(): changes[0] += 1
	Store.on_changed(listen)
	expect(Store.price("remove_ads"), "€3.49", "stub price")
	var res := [""]
	Store.buy("nothing_like_this", func(r): res[0] = r)
	expect(res[0], "error", "unknown product")
	Store.buy("remove_ads", func(r): res[0] = r)
	expect(res[0], "ok", "No ads bought")
	expect(Store.owns("remove_ads"), true, "No ads owned")
	expect(changes[0], 1, "listeners told of the purchase")
	Store.buy("remove_ads", func(r): res[0] = r)
	expect(res[0], "owned", "No ads bought twice")

	# ---- with No ads: no full-screen ads, rewards at once
	expect(Ads.ads_removed(), true, "No ads removes ads")
	Ads._last_ad_ms = -1
	expect(M.interstitial_due(-1.0), true, "a full-screen ad would be due")
	expect(Ads.maybe_interstitial("after_results"), false, "but No ads shows none")
	Ads.stub_delay = 5.0
	got[0] = 0
	expect(Ads.show_rewarded("gold_ghost", func(): got[0] += 1), true, "reward without a video")
	expect(got[0], 1, "granted at once with No ads")
	expect(Ads.since_last_ad(), -1.0, "no video, no cooldown")
	expect(Ads.rewarded_ready("double_coins"), false, "the daily cap still holds with No ads")

	# ---- Reset progress keeps purchases, clears the ad counters
	Wallet.reset()
	expect(Store.owns("remove_ads"), true, "No ads kept after Reset progress")
	expect(M.used_today("double_coins"), 0, "ad counters cleared by Reset progress")

	# ---- the Starter pack: No ads + Neon pack + 1000 coins; coin packs can be bought again
	Store._cfg = ConfigFile.new()
	Wallet.reset()
	expect(M.starter_for_sale(), true, "Starter pack for sale on a fresh save")
	expect(M.starter_card_due(false), false, "no Starter card before %d races" % M.STARTER_AFTER_RACES)
	Wallet.set_v("ads", "races", M.STARTER_AFTER_RACES)
	expect(M.starter_card_due(true), false, "never over a medal or award moment")
	expect(M.starter_card_due(false), true, "Starter card after %d races" % M.STARTER_AFTER_RACES)
	M.starter_card_shown()
	expect(M.starter_card_due(false), false, "the card shows once")
	Store.buy("starter_pack", func(r): res[0] = r)
	expect([res[0], Store.owns("remove_ads"), Store.owns("neon_pack"), Wallet.coins()], ["ok", true, true, 1000], "Starter pack holds No ads, Neon and 1000 coins")
	expect(Ads.ads_removed(), true, "Starter pack removes ads")
	expect(M.starter_for_sale(), false, "Starter pack no longer for sale")
	Store._cfg = ConfigFile.new()
	Store.buy("neon_pack")
	expect(M.starter_for_sale(), false, "not sold to someone with the Neon pack")
	Wallet.reset()
	Store.buy("coins_s", func(r): res[0] = r)
	Store.buy("coins_s", func(r): res[0] = r)
	expect([res[0], Wallet.coins(), Store.owns("coins_s")], ["ok", 3000, false], "coin packs add coins each time")
	Store._cfg = ConfigFile.new()
	Wallet.reset()

	# ---- every product the Garage sells is a real Store product with a price
	for id in Store.PRODUCTS:
		if Store.price(id) == "" or Store.product(id)["name"] == "":
			fail("product %s has no name or price" % id)

	Store._listeners.clear()
	# put the player's files back
	Daily.fake_day = -1
	M.fake_now = -1
	Settings.set_opt("launches", launches_was)
	if store_was == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Store.PATH))
	else:
		var f := FileAccess.open(Store.PATH, FileAccess.WRITE)
		f.store_string(store_was)
		f.close()
	Store._cfg = null
	Wallet.reset()
	printerr("MONETIZATION BAD: %d" % bad)
	quit(1 if bad > 0 else 0)
