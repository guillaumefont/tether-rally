# Every number of the free-to-play rules in one place, and the counters they need
# (docs/monetization.md). The values are first guesses, to tune after the soft launch.
# Counters live in user://wallet.cfg (section "ads"), so "Reset progress" clears them;
# what was paid for lives in Store and is never reset.
extends RefCounted

const Wallet = preload("res://scripts/wallet.gd")
const Daily = preload("res://scripts/daily.gd")
const Settings = preload("res://scripts/settings.gd")

# rewarded ads
const DOUBLE_COINS_PER_DAY := 10    # "x2 coins" on the results
const DAILY_ATTEMPTS := 3           # scored Daily Detour runs a day (a quit in the first lap gives it back)
const DAILY_EXTRA_PER_DAY := 1      # extra scored Daily Detour runs for an ad (2 at most)
# a rewarded placement capped per day -> its cap (others have none)
const PER_DAY := { "double_coins": DOUBLE_COINS_PER_DAY, "daily_extra": DAILY_EXTRA_PER_DAY }

# full-screen ads, shown only when leaving a results screen
const INTERSTITIAL_EVERY := 4       # finished races between two of them
const INTERSTITIAL_MIN_RACES := 6   # finished races before the first one ever
const INTERSTITIAL_COOLDOWN_S := 120  # none this soon after a rewarded ad
const INTERSTITIAL_MIN_GAP_S := 420   # and never two closer than this (races last 30-60 s)

# later phases
const STREAK_BONUS := { 3: 50, 7: 150 }   # then +150 every 7 days
const STREAK_SAVE_EVERY_DAYS := 7
const STARTER_AFTER_RACES := 5

# ---------------------------------------------------------------- per-day counters
# how many times `key` was used today (the device's day, Daily.today())
static func used_today(key: String) -> int:
	if int(Wallet.get_v("ads", key + "_day", -999999)) != Daily.today():
		return 0
	return int(Wallet.get_v("ads", key, 0))

static func use(key: String) -> void:
	var n := used_today(key) + 1
	Wallet.set_v("ads", key + "_day", Daily.today())
	Wallet.set_v("ads", key, n)

# uses of a capped placement left today (a large number when it has no cap)
static func left_today(key: String) -> int:
	if not PER_DAY.has(key):
		return 1 << 30
	return maxi(0, int(PER_DAY[key]) - used_today(key))

# ---------------------------------------------------------------- full-screen ad pacing
# app launches, counted at boot: the first session never sees a full-screen ad
static func launches() -> int:
	return int(Settings.get_opt("launches", 0))

static func note_launch() -> void:
	Settings.set_opt("launches", launches() + 1)

# a finished race that may lead to a full-screen ad (not the tutorial, Off the Map,
# Daily Detour practice or a 2-player race: the caller leaves those out)
static func note_race() -> void:
	Wallet.set_v("ads", "races", int(Wallet.get_v("ads", "races", 0)) + 1)
	Wallet.set_v("ads", "since_ad", int(Wallet.get_v("ads", "since_ad", 0)) + 1)

# the clock for the gap between full-screen ads (a test sets fake_now)
static var fake_now := -1
static func now() -> int:
	return fake_now if fake_now >= 0 else int(Time.get_unix_time_from_system())

# is a full-screen ad due, `since_last_ad_s` seconds after the last ad of any kind (-1: none yet)
static func interstitial_due(since_last_ad_s: float) -> bool:
	if launches() <= 1:
		return false
	if int(Wallet.get_v("ads", "races", 0)) < INTERSTITIAL_MIN_RACES:
		return false
	if since_last_ad_s >= 0.0 and since_last_ad_s < INTERSTITIAL_COOLDOWN_S:
		return false
	var last := int(Wallet.get_v("ads", "last_full", -1))
	if last >= 0 and now() - last < INTERSTITIAL_MIN_GAP_S:
		return false
	return int(Wallet.get_v("ads", "since_ad", 0)) >= INTERSTITIAL_EVERY

static func interstitial_shown() -> void:
	Wallet.set_v("ads", "since_ad", 0)
	Wallet.set_v("ads", "last_full", now())
