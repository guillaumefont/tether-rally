# Ads, behind one small interface like Store, so the menus never know the ad network
# (AdMob on Android later). For now this is a stub: debug and preview builds "play" a
# rewarded video by waiting `stub_delay` seconds and then granting the reward, so every
# placement can be tried without an ad account; release builds have no ads at all yet.
#
# Rules (docs/monetization.md): a rewarded ad is always a button the player taps, and its
# reward is granted only when the ad network says it was earned (never just because the
# ad closed). With "No ads" bought, nothing is ever shown and every reward is granted at
# once. Full-screen ads are rare, only when leaving a results screen, paced by Monetization.
extends RefCounted

const Store = preload("res://scripts/store.gd")
const Monetization = preload("res://scripts/monetization.gd")

# the rewarded placements (one ad unit each once AdMob is in)
const PLACEMENTS := ["double_coins", "gold_ghost", "ideal_line", "daily_extra", "streak_save"]
# products that end the ads
const REMOVERS := ["remove_ads"]

static var stub_delay := 1.0         # seconds a stub video "plays"
static var _last_ad_ms := -1         # when the last ad of any kind ended (cooldown)
static var _busy := false            # an ad is on screen

static func ads_removed() -> bool:
	for id in REMOVERS:
		if Store.owns(id):
			return true
	return false

# the stub plays only where Store's stub sells: debug and preview builds
static func _stub() -> bool:
	return Store.available()

# can the placement's button be offered now (else it is greyed: "No video right now")
static func rewarded_ready(placement: String) -> bool:
	if not PLACEMENTS.has(placement) or Monetization.left_today(placement) <= 0:
		return false
	if ads_removed():
		return true
	return _stub() and not _busy

# play a rewarded ad for `placement`; `on_reward` is called only if it was earned.
# Returns false (and calls nothing) when no ad can be shown.
static func show_rewarded(placement: String, on_reward: Callable) -> bool:
	if not rewarded_ready(placement):
		return false
	if ads_removed():
		_earned(placement, on_reward, false)
		return true
	_busy = true
	if stub_delay <= 0.0:
		_earned(placement, on_reward, true)
	else:
		var tree := Engine.get_main_loop() as SceneTree
		tree.create_timer(stub_delay, true).timeout.connect(func(): _earned(placement, on_reward, true))
	return true

static func _earned(placement: String, on_reward: Callable, watched: bool) -> void:
	_busy = false
	if watched:
		_last_ad_ms = Time.get_ticks_msec()
	Monetization.use(placement)
	if on_reward.is_valid():
		on_reward.call()

static func since_last_ad() -> float:
	return -1.0 if _last_ad_ms < 0 else (Time.get_ticks_msec() - _last_ad_ms) / 1000.0

# leaving a results screen: show a full-screen ad if one is due. `done` is called when the
# player is free to go on (at once when no ad shows). Returns whether an ad showed.
# The stub only counts it for now; the results screen wiring and a test card come later.
static func maybe_interstitial(trigger: String, done := Callable()) -> bool:
	var show := trigger == "after_results" and not ads_removed() and _stub() and not _busy \
		and Monetization.interstitial_due(since_last_ad())
	if show:
		Monetization.interstitial_shown()
		_last_ad_ms = Time.get_ticks_msec()
	if done.is_valid():
		done.call()
	return show
