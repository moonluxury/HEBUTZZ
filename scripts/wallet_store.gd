extends Node
const JsonStore = preload("res://scripts/local_json_store.gd")
## Account-scoped client state. No client path can credit a wallet.
signal changed
signal completed(ticket: String, response: Dictionary)
signal order_ready(order_id: String)
const Amount = preload("res://scripts/battery_amount.gd")
const SAVE_DIR := "user://wallet_requests_v1"
const PAYMENT_STATES := ["pending", "processing", "unknown", "paid", "closed", "failed"]
const CREDIT_STATES := ["none", "pending", "credited", "failed"]
var provider: Node
var account_id := ""
var epoch := 0
var session_epoch := -1
var balance: Variant = null
var balance_revision := -1
var balance_loading := false
var balance_error := ""
var packages: Array = []
var channels: Array = []
var rules: Dictionary = {}
var catalog_loading := false
var catalog_error := ""
var configured := false
var preview := false
var selected := ""
var channel := ""
var orders: Dictionary = {}
var current_order := ""
var intent: Dictionary = {}
var intent_snapshot: Dictionary = {}
var creating := false
var error := ""
var active := false
var _balance_busy := false
var _query_busy: Dictionary = {}
var _balance_again := false
var _wait := 3.0
var _polls := 0
var _last_focus := true
var _default_used := false
var _storage_error := false
var _recovering := false
var _watched_order := ""
var _payment_window: WeakRef

func _ready() -> void:
	get_node("/root/ProfileStore").changed.connect(_session_changed)
	_session_changed()

func _session_changed() -> void:
	var profile := get_node("/root/ProfileStore")
	if session_epoch == profile.epoch: return
	epoch += 1
	if is_instance_valid(provider) and provider.has_method("wallet_cancel_requests"): provider.wallet_cancel_requests()
	session_epoch = profile.epoch
	provider = profile.provider if profile.authenticated() else null
	account_id = profile.account_id
	balance = null
	balance_revision = -1
	balance_loading = false
	_balance_busy = false
	_balance_again = false
	balance_error = ""
	packages = []
	channels = []
	rules = {}
	catalog_loading = false
	catalog_error = ""
	configured = false
	preview = false
	selected = ""
	channel = ""
	orders = {}
	current_order = ""
	intent = {}
	intent_snapshot = {}
	creating = false
	error = ""
	_query_busy.clear()
	_default_used = false
	_storage_error = false
	_recovering = false
	_watched_order = ""
	_payment_window = null
	_polls = 0
	_load_intent()
	changed.emit()
	if available():
		refresh()
		if active:
			recover()
			if not current_order.is_empty(): query_order(current_order)

func available() -> bool:
	return not account_id.is_empty() and is_instance_valid(provider) and provider.has_method("wallet_request")

func unavailable() -> String:
	var profile := get_node("/root/ProfileStore")
	if profile.session_state == "loading": return "正在确认登录状态…"
	if account_id.is_empty(): return "登录后查看电池余额与记录"
	return "电池服务尚未接入，请稍后重试。" if not available() else ""

func message(response: Dictionary) -> String:
	# Do not render server diagnostics, tokens or raw payment payloads.
	return {"unavailable": "相关服务尚未开放。", "unauthenticated": "登录已失效，请重新登录。", "forbidden": "无法查看这条记录。", "not_found": "未找到记录，请查询原订单。", "price_changed": "套餐已更新，请重新选择并核对价格。", "conflict": "原请求与本次选择不一致，请恢复原订单。", "disabled": "该套餐或支付渠道当前不可用。", "invalid_response": "获取失败，服务返回的内容无法确认，请重试。", "stale": "账号已切换。", "unknown": "网络中断或结果未知，请查询或重试原请求。"}.get(str(response.get("code", "unknown")), "请求未完成，请重试或查询原订单。")

func request(action: String, payload: Dictionary = {}) -> Dictionary:
	if not available(): return {"ok": false, "code": "unavailable"}
	var generation := epoch
	var response: Variant = await provider.wallet_request(action, payload.duplicate(true))
	if generation != epoch: return {"ok": false, "code": "stale"}
	if not response is Dictionary or response.get("account_id", "") != account_id:
		return {"ok": false, "code": "invalid_response"}
	if not response.get("ok") is bool: return {"ok": false, "code": "invalid_response"}
	if response.get("code") == "unauthenticated":
		get_node("/root/ProfileStore").use_provider(provider, {"state": "signed_out"})
		return {"ok": false, "code": "stale"}
	return response

func refresh() -> void:
	refresh_balance()
	refresh_catalog()

func refresh_balance() -> void:
	if _balance_busy:
		_balance_again = true
		return
	if not available():
		balance = null
		balance_error = unavailable()
		changed.emit()
		return
	_balance_busy = true
	balance_loading = true
	var generation := epoch
	changed.emit()
	var response := await request("balance")
	if generation != epoch: return
	_balance_busy = false
	balance_loading = false
	if response.get("ok", false) and Amount.integer(response.get("balance")) and Amount.integer(response.get("revision")):
		if int(response.revision) >= balance_revision:
			balance = int(response.balance)
			balance_revision = int(response.revision)
		balance_error = ""
	else:
		balance = null
		balance_error = message(response)
	changed.emit()
	if _balance_again:
		_balance_again = false
		refresh_balance.call_deferred()

func refresh_catalog() -> void:
	if catalog_loading or not available(): return
	catalog_loading = true
	var generation := epoch
	changed.emit()
	var response := await request("catalog")
	if generation != epoch: return
	catalog_loading = false
	if not response.get("ok", false) or not _catalog(response):
		configured = false
		packages = []
		channels = []
		selected = ""
		channel = ""
		rules = {}
		preview = false
		catalog_error = message(response)
	else: catalog_error = ""
	changed.emit()

func _catalog(response: Dictionary) -> bool:
	if not response.get("packages") is Array or not response.get("channels") is Array or not response.get("rules", {}) is Dictionary: return false
	if not response.get("preview", false) is bool or not response.get("recharge_enabled", false) is bool: return false
	for name in ["quiz", "publication"]:
		if not response.get("rules", {}).get(name, {}) is Dictionary: return false
	var quiz_rule: Dictionary = response.get("rules", {}).get("quiz", {})
	if not quiz_rule.get("types", []) is Array or not quiz_rule.get("bank_versions", {}) is Dictionary: return false
	# Reject preview responses before adopting any rule or payment capability.
	var is_preview: bool = response.get("preview", false) == true
	if is_preview and not (OS.get_user_data_dir().contains("workbench-check-") and OS.has_feature("editor")): return false
	var next: Array = []
	var ids: Array = []
	for item in response.packages:
		if not item is Dictionary or not valid_package(item) or item.id in ids: return false
		ids.append(item.id)
		if item.get("enabled", false): next.append(item.duplicate(true))
	var next_channels: Array = []
	ids.clear()
	for item in response.channels:
		if not item is Dictionary or not item.get("id") is String or str(item.id).is_empty() or not item.get("label") is String or str(item.label).is_empty() or not item.get("enabled") is bool or item.id in ids: return false
		ids.append(item.id)
		if item.get("enabled", false): next_channels.append(item.duplicate(true))
	var old := package()
	packages = next
	channels = next_channels
	rules = response.get("rules", {}).duplicate(true)
	# A server flag alone cannot enable a design preview in a production account.
	preview = is_preview
	configured = response.get("recharge_enabled", false) == true
	var current := package()
	if not old.is_empty() and (current.is_empty() or old.version != current.version or old.price_cents != current.price_cents or old.batteries != current.batteries):
		selected = ""
		error = "套餐已更新，请重新选择并核对价格。"
	if not intent.is_empty():
		selected = str(intent.package_id)
		channel = str(intent.channel)
		_default_used = true
	elif not _default_used:
		_default_used = true
		var default_id := str(response.get("default_package_id", ""))
		if packages.any(func(p): return p.id == default_id): selected = default_id
	if intent.is_empty() and not channels.any(func(c): return c.id == channel): channel = str(channels[0].id) if not channels.is_empty() else ""
	return true

static func valid_package(item: Dictionary) -> bool:
	return item.get("id") is String and not item.id.is_empty() and item.get("version") is String and not item.version.is_empty() and item.get("enabled") is bool and Amount.integer(item.get("price_cents"), 1) and Amount.integer(item.get("batteries"), 1) and item.get("currency") == "CNY"

func package() -> Dictionary:
	for item in packages:
		if str(item.id) == selected: return item
	return {}

func confirmation_package() -> Dictionary:
	# An in-flight operation always displays the immutable price the user confirmed.
	if not intent.is_empty(): return intent_snapshot
	var order: Dictionary = orders.get(current_order, {})
	if not current_order.is_empty() and not terminal(order): return order
	return package()

func confirmation_channel() -> String:
	var order: Dictionary = orders.get(current_order, {})
	if not intent.is_empty(): return str(intent.get("channel", ""))
	if not order.is_empty() and not terminal(order): return str(order.channel)
	return channel

func confirmation_channel_label() -> String:
	var order: Dictionary = orders.get(current_order, {})
	if not order.is_empty() and not terminal(order): return str(order.get("channel_label", "原订单支付渠道"))
	if not intent.is_empty(): return str(intent_snapshot.get("payment_channel_label", "原请求支付渠道"))
	for item in channels:
		if item.id == channel: return str(item.label)
	return "支付渠道待确认"

func select_package(id: String) -> void:
	if locked(): return
	selected = id
	error = ""
	changed.emit()

func select_channel(id: String) -> void:
	if locked(): return
	channel = id
	changed.emit()

func locked() -> bool:
	return creating or not intent.is_empty() or (not current_order.is_empty() and not terminal(orders.get(current_order, {})))

func checkout_reason() -> String:
	if not available(): return unavailable()
	if _storage_error: return "无法保存原请求标识，请检查本机存储后重试。"
	if catalog_loading: return "正在获取充值规则…"
	if not configured: return "正式充值尚未开放，价格与支付渠道待配置。"
	if packages.is_empty(): return "暂无可用充值套餐。"
	if channels.is_empty(): return "暂无已开通的支付渠道。"
	if package().is_empty(): return "请先选择充值金额。"
	if channel.is_empty(): return "请选择支付方式。"
	if balance == null: return "请先重试获取电池余额，核对后再充值。"
	if int(balance) > Amount.MAX_INTEGER - int(package().batteries): return "预计余额超出可显示范围，请联系已有支持渠道。"
	return ""

func create_order() -> void:
	if creating: return
	if intent.is_empty() and not current_order.is_empty() and not terminal(orders.get(current_order, {})):
		order_ready.emit(current_order)
		return
	if intent.is_empty():
		var reason := checkout_reason()
		if not reason.is_empty():
			error = reason
			changed.emit()
			return
		intent = {"request_id": Crypto.new().generate_random_bytes(24).hex_encode(), "package_id": selected, "package_version": str(package().version), "channel": channel}
		intent_snapshot = package().duplicate(true)
		for item in channels:
			if item.id == channel: intent_snapshot.payment_channel_label = str(item.label)
		if not _save_intent():
			intent = {}
			intent_snapshot = {}
			_storage_error = true
			error = "未能保存请求标识，尚未提交订单。"
			changed.emit()
			return
	creating = true
	error = ""
	var generation := epoch
	changed.emit()
	var response := await request("create_order", intent)
	if generation != epoch: return
	creating = false
	var value: Variant = response.get("order", {})
	if response.get("ok", false) == true and value is Dictionary and _matches_intent(value) and merge_order(value):
		current_order = str(value.id)
		intent = {}
		intent_snapshot = {}
		_save_intent()
		_wait = 3.0
		_polls = 0
		order_ready.emit(current_order)
	else:
		error = message(response)
		if response.get("code") in ["price_changed", "disabled"] and response.get("definitive", false):
			intent = {}
			intent_snapshot = {}
			_save_intent()
			selected = ""
			_default_used = true
			refresh_catalog()
	changed.emit()

func _matches_intent(value: Dictionary) -> bool:
	for field in ["request_id", "package_id", "package_version", "channel"]:
		if value.get(field) != intent.get(field): return false
	if not intent_snapshot.is_empty():
		for field in ["price_cents", "batteries", "currency"]:
			if value.get(field) != intent_snapshot.get(field): return false
	return true

func merge_order(value: Dictionary) -> bool:
	for field in ["request_id", "package_id", "package_version", "channel"]:
		if not value.get(field) is String or str(value[field]).is_empty(): return false
	if str(value.get("id", "")).is_empty() or value.get("account_id") != account_id or not Amount.integer(value.get("revision")) or not Amount.integer(value.get("price_cents"), 1) or not Amount.integer(value.get("batteries"), 1) or value.get("currency") != "CNY" or value.get("payment_status") not in PAYMENT_STATES or value.get("credit_status") not in CREDIT_STATES: return false
	if value.credit_status == "credited" and (value.payment_status != "paid" or str(value.get("ledger_id", "")).is_empty()): return false
	var old: Dictionary = orders.get(str(value.id), {})
	if not old.is_empty():
		for field in ["account_id", "request_id", "package_id", "package_version", "price_cents", "currency", "batteries", "channel"]:
			if old.get(field) != value.get(field): return false
		if int(value.revision) <= int(old.revision): return true
		if old.credit_status == "credited" and value.credit_status != "credited": return true
		if old.payment_status == "paid" and value.payment_status != "paid": return true
	orders[str(value.id)] = value.duplicate(true)
	if value.credit_status == "credited" and old.get("credit_status") != "credited": refresh_balance()
	return true

static func terminal(value: Dictionary) -> bool:
	return value.get("credit_status") == "credited" or value.get("payment_status") in ["closed", "failed"]

static func status(value: Dictionary) -> String:
	if value.is_empty(): return "正在查询订单…"
	if value.get("credit_status") == "credited": return "已到账"
	if value.get("payment_status") == "paid": return "已支付，电池到账中" if value.get("credit_status") != "failed" else "已支付，到账异常，可查询恢复"
	return {"pending": "待支付", "processing": "支付处理中", "unknown": "支付结果未知，请查询原订单", "closed": "已关闭", "failed": "支付失败"}.get(str(value.get("payment_status", "")), "状态待确认")

func query_order(id: String, ticket := "") -> void:
	if _query_busy.has(id):
		if not ticket.is_empty(): completed.emit(ticket, {"ok": false, "code": "busy"})
		return
	_query_busy[id] = true
	var generation := epoch
	var response := await request("order", {"order_id": id})
	if generation != epoch: return
	_query_busy.erase(id)
	if response.get("ok", false):
		if not response.get("order") is Dictionary or str(response.order.get("id", "")) != id or not merge_order(response.order): response = {"ok": false, "code": "invalid_response"}
	error = "" if response.get("ok", false) else message(response)
	changed.emit()
	completed.emit(ticket, response)

func recover() -> void:
	if not available() or _recovering: return
	_recovering = true
	var generation := epoch
	var response := await request("orders", {"scope": "unfinished", "cursor": "", "limit": 20})
	if generation != epoch: return
	_recovering = false
	if response.get("ok", false) and response.get("items") is Array:
		for value in response.items:
			if value is Dictionary and merge_order(value):
				if (current_order.is_empty() or terminal(orders.get(current_order, {}))) and not terminal(value): current_order = str(value.id)
				if not intent.is_empty() and _matches_intent(value):
					current_order = str(value.id)
					intent = {}
					intent_snapshot = {}
		_save_intent()
	else: error = "未能恢复充值记录，可重试查询原订单。"
	changed.emit()

func read_records(kind: String, cursor: String, filter: String, ticket: String) -> void:
	var generation := epoch
	var response := await request(kind, {"cursor": cursor, "filter": filter, "limit": 20})
	if generation != epoch: return
	if response.get("ok", false):
		if not response.get("items") is Array or not response.get("next_cursor", "") is String:
			response = {"ok": false, "code": "invalid_response"}
		else:
			for row in response.items:
				var valid: bool = row is Dictionary
				if valid and kind == "orders": valid = merge_order(row)
				elif valid:
					valid = row.get("account_id") == account_id and not str(row.get("id", "")).is_empty() and (row.get("delta") is int or row.get("delta") is float) and Amount.integer(absf(float(row.get("delta", INF))), 1) and str(row.get("reference", "")) != ""
				if not valid:
					response = {"ok": false, "code": "invalid_response"}
					break
	completed.emit(ticket, response)

func activate(value: bool) -> void:
	active = value
	_polls = 0
	_wait = 3.0
	if value:
		refresh()
		recover()
		if not current_order.is_empty(): query_order(current_order)
	else:
		_watched_order = ""
		_payment_window = null

func watch_order(id: String, window: Window = null) -> void:
	_watched_order = id
	_payment_window = weakref(window) if window != null else null
	_polls = 0
	_wait = 3.0

func poll_target() -> String:
	return _watched_order if not _watched_order.is_empty() else current_order

func _process(delta: float) -> void:
	var window: Window = _payment_window.get_ref() if _payment_window != null else null
	var focused := get_tree().root.has_focus() or (is_instance_valid(window) and window.has_focus())
	_tick_poll(delta, focused)

func _tick_poll(delta: float, focused: bool) -> void:
	if not active or not available(): return
	if not focused:
		_last_focus = false
		return
	if not _last_focus:
		_last_focus = true
		_polls = 0
		_wait = 3.0
		# Even a previously closed order may have a late authoritative payment.
		if not poll_target().is_empty(): query_order(poll_target())
	var target := poll_target()
	if target.is_empty() or terminal(orders.get(target, {})) or _polls >= 12: return
	_wait -= delta
	if _wait <= 0:
		_polls += 1
		_wait = minf(60.0, 3.0 * pow(1.6, _polls))
		query_order(target)

func payment_url(id: String) -> String:
	var value: Dictionary = orders.get(id, {})
	if value.get("payment_status") != "pending" or value.get("credit_status") == "credited": return ""
	var payment: Dictionary = value.get("payment", {}) if value.get("payment") is Dictionary else {}
	if payment.get("kind") != "redirect" or not payment.get("verified", false): return ""
	var url := str(payment.get("url", ""))
	if not url.begins_with("https://") or "@" in url.get_slice("/", 2): return ""
	var host := url.get_slice("/", 2).to_lower()
	# The authenticated host configures an explicit allowlist; the response cannot expand it.
	if not provider.has_method("wallet_payment_hosts") or host not in provider.wallet_payment_hosts(): return ""
	if int(payment.get("expires_at", 0)) <= int(Time.get_unix_time_from_system()): return ""
	return url

func submit_quiz(attempt_id: String, answer: Dictionary) -> Dictionary:
	var generation := epoch
	var payload := {"attempt_id": attempt_id, "answer": answer.duplicate(true)}
	var response := await request("quiz_submit", payload)
	if generation != epoch: return {"ok": false, "code": "stale"}
	# A single retry keeps the server-issued event identity, including a lost receipt.
	if not response.get("ok", false) and response.get("code") == "unknown":
		response = await request("quiz_submit", payload)
	if generation != epoch: return {"ok": false, "code": "stale"}
	if response.get("ok", false):
		var reward: Variant = response.get("reward")
		if not reward is Dictionary or reward.get("status") not in ["credited", "pending", "ineligible"]: return {"ok": false, "code": "invalid_response"}
		if reward.status == "credited":
			if not Amount.integer(reward.get("amount"), 1) or str(reward.get("ledger_id", "")).is_empty(): return {"ok": false, "code": "invalid_response"}
			refresh_balance()
	return response

func _intent_path() -> String:
	return SAVE_DIR.path_join(account_id.sha256_text() + ".json")

func _load_intent() -> void:
	if account_id.is_empty() or not FileAccess.file_exists(_intent_path()): return
	var data: Variant = JsonStore.read(_intent_path())
	if data is Dictionary and data.get("account_hash") == account_id.sha256_text() and data.get("intent") is Dictionary:
		var value: Dictionary = data.intent
		if value.is_empty() or (["request_id", "package_id", "package_version", "channel"].all(func(k): return value.get(k) is String and not value[k].is_empty())):
			intent = value
			var snapshot: Variant = data.get("snapshot", {})
			if snapshot is Dictionary and valid_package(snapshot) and snapshot.id == intent.get("package_id") and snapshot.version == intent.get("package_version"):
				intent_snapshot = snapshot
			current_order = str(data.get("order_id", ""))
			return
	_storage_error = true

func _save_intent() -> bool:
	if account_id.is_empty(): return false
	return JsonStore.write(_intent_path(), {"account_hash": account_id.sha256_text(), "intent": intent, "snapshot": intent_snapshot, "order_id": current_order}) == OK
