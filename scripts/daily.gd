# Track of the day: one track + variant in Time trial, picked from the local date alone
# (no server, works offline: everyone on the same day gets the same track). Tracks come in
# a shuffled order that covers all of them before any comes back, never the same track two
# days running; each pass round the tracks moves every track on to its next variant, so
# every track + variant shows up once every 17 x 4 days.
# Finishing it pays coins once a day, plus more per medal tier (an improvement later the
# same day pays the difference).
extends RefCounted

const Defs = preload("res://scripts/track_defs.gd")
const Wallet = preload("res://scripts/wallet.gd")

const BASE := 40       # coins for finishing it
const PER_TIER := 30   # and for each medal tier of the run

# a test sets this to pretend it is another day (-1: the real date)
static var fake_day := -1

# days since 1970-01-01 in the player's own time zone
static func today() -> int:
	if fake_day >= 0:
		return fake_day
	var d := Time.get_date_dict_from_system()
	return day_of(int(d["year"]), int(d["month"]), int(d["day"]))

static func day_of(y: int, m: int, d: int) -> int:
	var t := Time.get_unix_time_from_datetime_dict({ "year": y, "month": m, "day": d, "hour": 12, "minute": 0, "second": 0 })
	return int(floor(t / 86400.0))

# a small deterministic generator (same numbers on every device and build)
static func _next(s: int) -> int:
	return (s * 1103515245 + 12345) % 2147483648

static func _order(cycle: int) -> Array:
	var n := Defs.TRACKS.size()
	var o: Array = range(n)
	var s := posmod(cycle * 7919 + 104729, 2147483648)
	for i in range(n - 1, 0, -1):
		s = _next(s)
		var j := (s >> 16) % (i + 1)
		var tmp = o[i]; o[i] = o[j]; o[j] = tmp
	return o

# { track, name, variant } for a day
static func pick(day: int) -> Dictionary:
	var n := Defs.TRACKS.size()
	var cycle := int(floor(float(day) / n))
	var pos := day - cycle * n
	var o := _order(cycle)
	# the first day of a pass never repeats the last day of the one before
	if o[0] == _order(cycle - 1)[n - 1]:
		var tmp = o[0]; o[0] = o[1]; o[1] = tmp
	var t: int = o[pos]
	var v: String = Defs.VARIANTS[posmod(cycle + t, Defs.VARIANTS.size())][0]
	return { "track": t, "name": Defs.TRACKS[t]["name"], "variant": v }

static func current() -> Dictionary:
	return pick(today())

static func is_today(track_i: int, variant: String) -> bool:
	var p := current()
	return p["track"] == track_i and p["variant"] == variant

# the best medal tier already paid today (-1: not finished today)
static func paid_tier() -> int:
	if int(Wallet.get_v("daily", "day", -999999)) != today():
		return -1
	return int(Wallet.get_v("daily", "tier", -1))

# coins a finished run on today's track pays, given what today already paid
static func coins_for(paid: int, run_tier: int) -> int:
	if paid < 0:
		return BASE + PER_TIER * run_tier
	return PER_TIER * maxi(0, run_tier - paid)

# a finished run on today's track: pay it and remember it; returns the coins paid
static func claim(run_tier: int) -> int:
	var paid := paid_tier()
	var n := coins_for(paid, run_tier)
	if paid < 0:
		Wallet.bump("dailies")
	if paid < 0 or run_tier > paid:
		Wallet.set_v("daily", "day", today())
		Wallet.set_v("daily", "tier", maxi(run_tier, paid))
	Wallet.add(n)
	return n

# ---------------------------------------------------------------- scored attempts
# (docs/monetization.md) A day has DAILY_ATTEMPTS scored runs, started from the Daily Detour
# banner; the best counts (claim() already pays only an improvement). An attempt is used when
# the countdown ends; a quit or restart during the first lap gives it back. With none left the
# banner starts free practice (no coins, no daily best). A rewarded ad adds one more.
static func _att(k: String, default = 0):
	if int(Wallet.get_v("daily", "att_day", -999999)) != today():
		return default
	return Wallet.get_v("daily", k, default)

static func _set_att(k: String, v) -> void:
	if int(Wallet.get_v("daily", "att_day", -999999)) != today():
		Wallet.set_v("daily", "att_day", today())
		Wallet.set_v("daily", "used", 0)
		Wallet.set_v("daily", "extra", 0)
		Wallet.set_v("daily", "best", -1.0)
	Wallet.set_v("daily", k, v)

static func attempts_total() -> int:
	return int(load("res://scripts/monetization.gd").DAILY_ATTEMPTS) + int(_att("extra"))

static func attempts_left() -> int:
	return maxi(0, attempts_total() - int(_att("used")))

static func use_attempt() -> void:
	if attempts_left() > 0:
		_set_att("used", int(_att("used")) + 1)

static func give_back_attempt() -> void:
	_set_att("used", maxi(0, int(_att("used")) - 1))

static func add_extra() -> void:
	_set_att("extra", int(_att("extra")) + 1)

# today's best scored time (lap, or run score on Collect); -1: none yet
static func best_today() -> float:
	return float(_att("best", -1.0))

static func note_time(t: float) -> void:
	if t > 0.0 and (best_today() < 0.0 or t < best_today()):
		_set_att("best", t)
