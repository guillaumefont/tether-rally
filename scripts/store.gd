# In-app purchases, behind one small interface so each platform can plug in its own
# billing (Google Play Billing on Android, StoreKit on iOS, Steam) without the menus
# changing. For now this is a stub: there is no real billing yet. Debug builds (the editor)
# and preview builds (CI APKs, exported with the "preview" feature) grant a purchase at once
# so paid items can be tried; release builds report the store as unavailable. Owned products
# are kept in user://store.cfg; with a real backend that file is only a cache and restore()
# reads the platform's purchases back as the truth.
#
# Buying is asynchronous: buy(id, done) answers through `done` (a real store answers after
# its own purchase sheet closes), so a caller shows a "buying" state and never waits on it.
# Results: "ok", "owned", "unavailable", "cancelled", "error". Purchases never touch race
# times: they buy looks and the end of forced ads, nothing else (docs/monetization.md).
extends RefCounted

const PATH := "user://store.cfg"
static var _cfg: ConfigFile
static var _listeners: Array[Callable] = []

# the ids are the Play Console product ids; prices here are only shown until the platform
# gives its own (local currency, see price())
const PRODUCTS := {
	"remove_ads": { "name": "No ads", "price": "€3.49", "desc": "No more full-screen ads, and every video reward without watching." },
	"chrome_pack": { "name": "Chrome pack", "price": "€1.99", "desc": "Three mirror-finish paints: Chrome, Rose gold and Black chrome." },
	"neon_pack": { "name": "Neon pack", "price": "€1.99", "desc": "Three glowing paints, the Neon trim livery and a neon rope." },
}

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg

static func product(id: String) -> Dictionary:
	return PRODUCTS.get(id, { "name": id, "price": "", "desc": "" })

# the price to show: the platform's localised price once a backend has read it
static func price(id: String) -> String:
	return String(_load().get_value("prices", id, product(id)["price"]))

static func owns(id: String) -> bool:
	return bool(_load().get_value("owned", id, false))

# can a purchase be made on this build at all
static func available() -> bool:
	return OS.is_debug_build() or OS.has_feature("preview")

# be told when what the player owns changes (a purchase, a restore)
static func on_changed(cb: Callable) -> void:
	if not _listeners.has(cb):
		_listeners.append(cb)

static func _changed() -> void:
	for cb in _listeners.duplicate():
		if cb.is_valid():
			cb.call()
		else:
			_listeners.erase(cb)

# buy a product; `done` gets the result. The stub answers at once, a real backend later.
static func buy(id: String, done := Callable()) -> void:
	var res := "ok"
	if not PRODUCTS.has(id):
		res = "error"
	elif owns(id):
		res = "owned"
	elif not available():
		res = "unavailable"
	else:
		_grant(id)
	if done.is_valid():
		done.call(res)

# a purchase the platform confirmed (a real backend acknowledges it here, or Play refunds it)
static func _grant(id: String) -> void:
	_load().set_value("owned", id, true)
	_cfg.save(PATH)
	_changed()

# read the purchases back from the platform (nothing to do for the stub)
static func restore(done := Callable()) -> void:
	if done.is_valid():
		done.call("ok")
