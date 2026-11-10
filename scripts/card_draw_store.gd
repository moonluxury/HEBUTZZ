extends Node
## Persistent, account-scoped intent. Windows never own a wallet/inventory write.
const JsonStore = preload("res://scripts/local_json_store.gd")
const PRICE := 200
const SAVE_DIR := "user://card_draw_v1"
signal changed
var wallet: Node
var collection: Node
var profile: Node
var save_dir := SAVE_DIR
var endpoint_key := ""
var account_id := ""
var epoch := -1
var options: Dictionary = {}
var operation: Dictionary = {}
var busy := false
var loading := false
var verified := false
var error := ""
var _corrupt := false

func _ready() -> void:
	if wallet == null or collection == null:
		var services := get_node("/root/AppServices")
		if wallet == null: wallet = services.wallet_store()
		if collection == null: collection = services.collection_store()
	if profile == null: profile = get_node("/root/ProfileStore")
	profile.changed.connect(_session_changed)
	_session_changed()

func _session_changed() -> void:
	if epoch == profile.epoch: return
	epoch = profile.epoch
	account_id = profile.account_id if profile.authenticated() else ""
	options = {}
	operation = {}
	busy = false
	loading = false
	verified = false
	_corrupt = false
	error = ""
	if not account_id.is_empty() and FileAccess.file_exists(_path()):
		var saved: Variant = JsonStore.read(_path())
		if saved is Dictionary and saved.get("account_id") == account_id and saved.get("operation") is Dictionary:
			operation = saved.operation
			if not operation.is_empty() and (operation.get("account_id") != account_id or not operation.get("id") is String or str(operation.get("id", "")).is_empty() or not operation.get("pool_id") is String or not operation.get("rule_version") is String or operation.get("expected_price") != PRICE or operation.get("state") not in ["pending", "unknown", "succeeded", "failed"]):
				_corrupt = true
				operation = {}
				error = "本机获取记录无法读取，原文件已保留。"
		else:
			_corrupt = true
			error = "本机获取记录无法读取，原文件已保留。"
	changed.emit()

func available() -> bool:
	return not account_id.is_empty() and wallet.available() and wallet.account_id == account_id

func unresolved() -> bool:
	return not operation.is_empty() and operation.get("state") in ["pending", "unknown", "succeeded"]

func ready_result() -> bool:
	return verified and operation.get("state") == "succeeded"

func open() -> void:
	if _corrupt: changed.emit(); return
	if unresolved() and not verified: recover()
	elif options.is_empty(): load_options()

func load_options() -> void:
	if loading or not available():
		if not available(): error = "请先登录后获取卡牌。"; changed.emit()
		return
	loading = true
	var generation := epoch
	changed.emit()
	var response: Dictionary = await wallet.request("card_draw_options")
	if generation != epoch: return
	loading = false
	if response.get("ok", false) and response.get("price") == PRICE and response.get("odds") is Array and not str(response.get("pool_id", "")).is_empty() and response.get("rule_version") is String and not str(response.rule_version).is_empty():
		options = response.duplicate(true)
		error = ""
	else:
		options = {}
		error = "卡牌获取暂不可用，请稍后重试。"
	changed.emit()

func acquire() -> void:
	if busy or ready_result() or _corrupt or not available(): return
	if not unresolved():
		if options.is_empty(): load_options(); return
		var next := {"id": Crypto.new().generate_random_bytes(24).hex_encode(), "account_id": account_id,
			"pool_id": options.pool_id, "rule_version": options.rule_version, "expected_price": PRICE, "state": "pending"}
		if not _persist(next): changed.emit(); return
		operation = next
	var payload := {"operation_id": operation.id, "pool_id": operation.pool_id,
		"rule_version": operation.rule_version, "expected_price": int(operation.expected_price)}
	_run_request("card_draw", payload)

func recover() -> void:
	if busy or not unresolved() or not available(): return
	_run_request("card_draw_status", {"operation_id": operation.id})

func _run_request(action: String, payload: Dictionary) -> void:
	busy = true
	error = ""
	var generation := epoch
	var id: String = operation.id
	changed.emit()
	var response: Dictionary = await wallet.request(action, payload)
	if generation != epoch or operation.get("id") != id: return
	busy = false
	verified = false
	var receipt: Dictionary = response.get("draw", {}) if response.get("draw") is Dictionary else {}
	var valid: bool = response.get("ok", false) and response.get("state") == "succeeded" and receipt.get("operation_id") == id and receipt.get("price") == PRICE and receipt.get("quantity") == 1
	valid = valid and receipt.get("pool_id") == operation.get("pool_id") and receipt.get("rule_version") == operation.get("rule_version")
	valid = valid and not collection.card(str(receipt.get("card_id", ""))).is_empty() and response.get("collection") is Dictionary
	valid = valid and wallet.Amount.integer(response.get("balance")) and wallet.Amount.integer(response.get("revision"))
	if valid and collection._apply_snapshot(response.collection):
		operation.state = "succeeded"
		operation.receipt = receipt.duplicate(true)
		verified = true
		wallet.adopt_balance(response)
		collection.changed.emit()
	elif not response.get("ok", false) and response.get("state") == "failed" and response.get("operation_id") == id and response.get("definitive", false):
		operation.state = "failed"
		error = {"insufficient_balance": "电池不足，本次需要 200 电池。", "pool_changed": "卡牌获取规则已更新，请重新打开。", "price_changed": "获取价格已更新，请重新打开。", "inventory_limit": "该卡牌数量已达上限。"}.get(str(response.get("code", "")), "获取未完成，请重试。")
		if response.get("code") in ["pool_changed", "price_changed"]: options = {}
		wallet.refresh_balance()
	else:
		operation.state = "unknown"
		error = "结果尚未确认，请重试。"
	_persist(operation)
	changed.emit()

func acknowledge() -> void:
	if not ready_result(): return
	if _persist({}):
		operation = {}
		verified = false
		error = ""
	changed.emit()

func _path() -> String:
	var key := account_id if endpoint_key.is_empty() else endpoint_key + ":" + account_id
	return save_dir.path_join(key.sha256_text() + ".json")

func _persist(value: Dictionary) -> bool:
	if _corrupt: return false
	if JsonStore.write(_path(), {"version": 1, "account_id": account_id, "operation": value}) != OK:
		error = "本机记录保存失败，请检查存储空间后重试。"
		return false
	return true
