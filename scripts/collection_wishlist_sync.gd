extends Node
## Durable per-card intent queue. Remote reads never replace newer local edits.
var collection: Node
var pending: Dictionary = {}
var inflight: Dictionary = {}
var revision := 0
var migrated := false
var loaded := false
var initialized := false
var busy := false
var error := ""
var generation := 0
var _backoff := 3.0
var _refresh_again := false
var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(refresh)
	add_child(_timer)

func available() -> bool:
	return is_instance_valid(collection.provider) and collection.provider.has_method("wishlist_request") and collection.account_id != "local-profile"

func export_state() -> Dictionary:
	return {"revision":revision,"migrated":migrated,"pending":pending.duplicate(true),"inflight":inflight.duplicate(true)}

func restore(state: Dictionary) -> void:
	revision = int(state.get("revision",0))
	migrated = bool(state.get("migrated",false))
	pending = state.get("pending",{}).duplicate(true)
	inflight = state.get("inflight",{}).duplicate(true)

func reset() -> void:
	generation += 1
	_timer.stop()
	restore({})
	loaded = false
	initialized = false
	busy = false
	error = ""
	_refresh_again = false
	_backoff = 3.0

func queue_change(id: String, value: bool) -> void:
	# Keep offline edits even while signed out of this account; no anonymous import.
	if collection.account_id != "local-profile": pending[id] = value

func schedule(delay := 0.35) -> void:
	if available(): _timer.start(delay)

func caption() -> String:
	if not available(): return "想要清单保存在本机，登录后可使用云端清单。"
	if not error.is_empty(): return "想要清单待同步：" + error
	if busy or not loaded or not pending.is_empty() or not inflight.is_empty(): return "正在同步想要清单…"
	return "想要清单已同步至云端 · 好友可见"

func _valid(response: Dictionary) -> bool:
	if not response.get("ok",false) or response.get("account_id","") != collection.account_id: return false
	if not response.get("card_ids") is Array or not response.get("initialized") is bool: return false
	var value: Variant = response.get("wishlist_revision")
	return (value is int or value is float) and value >= 0 and value == floor(value) and response.card_ids.all(func(id): return id is String)

func _adopt(response: Dictionary) -> void:
	if not migrated and not response.initialized:
		# The first cloud initializer imports this account's legacy local marks.
		# A later device uses the existing cloud list, never resurrecting old caches.
		for id in collection.wanted:
			if not pending.has(id) and not collection.card(id).is_empty(): pending[id] = true
	migrated = true
	initialized = response.initialized
	revision = int(response.wishlist_revision)
	loaded = true
	var desired := {}
	for id in response.card_ids:
		if not collection.card(id).is_empty(): desired[id] = true
	for id in pending:
		if pending[id]: desired[id] = true
		else: desired.erase(id)
	collection.wanted = desired

func _save_or_restore(old_wanted: Dictionary, old_state: Dictionary) -> bool:
	if collection._save_local(): return true
	collection.wanted = old_wanted
	restore(old_state)
	error = "本机保存失败，请检查存储后重试。"
	return false

func refresh() -> void:
	if not available(): return
	if busy:
		_refresh_again = true
		return
	_timer.stop()
	busy = true
	error = ""
	var ticket := generation
	var owner_id: String = collection.account_id
	collection.changed.emit()
	# Replay a saved operation before reading: a lost successful reply must not
	# become a new write that resurrects a card another device has since removed.
	if inflight.is_empty() and (not loaded or pending.is_empty()):
		var read: Dictionary = await collection.provider.wishlist_request("wishlist_load",{})
		if ticket != generation or owner_id != collection.account_id: return
		if not _valid(read):
			_failed(str(read.get("message","读取失败，请重试。")))
			return
		var old_wanted: Dictionary = collection.wanted.duplicate(true)
		var old_state := export_state()
		_adopt(read)
		if not _save_or_restore(old_wanted,old_state):
			_failed(error)
			return
	if inflight.is_empty() and (not pending.is_empty() or not initialized):
		inflight = {"operation_id":Crypto.new().generate_random_bytes(24).hex_encode(),"expected_revision":revision,"changes":pending.duplicate(true)}
		if not collection._save_local():
			inflight = {}
			_failed("本机保存失败，尚未提交，请重试。")
			return
	if not inflight.is_empty():
		var sent := inflight.duplicate(true)
		var result: Dictionary = await collection.provider.wishlist_request("wishlist_update",sent)
		if ticket != generation or owner_id != collection.account_id: return
		if result.get("code") == "wishlist_conflict":
			inflight = {}
			loaded = false
			if not collection._save_local(): inflight = sent
			busy = false
			schedule(0.1)
			collection.changed.emit()
			return
		if not _valid(result):
			_failed(str(result.get("message","连接失败，修改已保存在本机。")))
			return
		var old_wanted: Dictionary = collection.wanted.duplicate(true)
		var old_state := export_state()
		for id in sent.changes:
			if pending.has(id) and pending[id] == sent.changes[id]: pending.erase(id)
		inflight = {}
		_adopt(result)
		if not _save_or_restore(old_wanted,old_state):
			_failed(error)
			return
		# Refresh after an old receipt or concurrent device write; one read after
		# a mutation also verifies the published source used by friend views.
		_refresh_again = true
	busy = false
	_backoff = 3.0
	collection.changed.emit()
	if not pending.is_empty() or _refresh_again:
		_refresh_again = false
		schedule(0.35)

func _failed(message: String) -> void:
	busy = false
	error = message
	collection.changed.emit()
	schedule(_backoff)
	_backoff = minf(60.0,_backoff*2.0)
