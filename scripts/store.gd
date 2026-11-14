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
	"starter_pack": { "name": "Starter pack", "price": "€4.99", "desc": "No ads, the Neon pack and 1000 coins.",
		"includes": ["remove_ads", "neon_pack"], "coins": 1000 },
	# consumables: bought again and again, they only add coins
	"coins_s": { "name": "1500 coins", "price": "€0.99", "desc": "A pouch of 1500 coins for the Garage.", "coins": 1500, "consumable": true },
	"coins_m": { "name": "5000 coins", "price": "€2.99", "desc": "A chest of 5000 coins for the Garage.", "coins": 5000, "consumable": true },
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

# owned, bought on its own or as part of a bundle (the Starter pack holds No ads and Neon)
static func owns(id: String) -> bool:
	if bool(_load().get_value("owned", id, false)):
		return true
	for b in PRODUCTS:
		if PRODUCTS[b].get("includes", []).has(id) and bool(_load().get_value("owned", b, false)):
			return true
	return false

static func consumable(id: String) -> bool:
	return bool(product(id).get("consumable", false))

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
	elif owns(id) and not consumable(id):
		res = "owned"
	elif not available():
		res = "unavailable"
	else:
		_grant(id)
	if done.is_valid():
		done.call(res)

# a purchase the platform confirmed (a real backend acknowledges it here, or Play refunds it)
static func _grant(id: String) -> void:
	# coins come once per purchase (a restore never pays them again); a consumable is then
	# consumed (a real backend calls consume() after this)
	var coins := int(product(id).get("coins", 0))
	if coins > 0:
		load("res://scripts/wallet.gd").add(coins)
	if not consumable(id):
		_load().set_value("owned", id, true)
		_cfg.save(PATH)
	_changed()

# read the purchases back from the platform (nothing to do for the stub)
static func restore(done := Callable()) -> void:
	if done.is_valid():
		done.call("ok")
