extends Node
const JsonStore = preload("res://scripts/local_json_store.gd")
## Collection-only state. No inventory mutations are performed by this client.
signal changed
signal operation_changed
signal gift_completed(result: Dictionary)
signal friends_loaded(ticket: String, response: Dictionary)
const CATALOG := "res://data/collection_catalog.json"
const SAVE_DIR := "user://collection_v1"
const KEEP_ONE_REASON := "每种卡片需至少保留 1 张，拥有 2 张及以上才可赠送。"
var provider: Node
var account_id := "local-profile"
var seasons: Array = []
var cards: Array = []
var inventory: Dictionary = {}
var inventory_known := false
var revision := -1
var wanted: Dictionary = {}
var operation: Dictionary = {}
var status := ""
var loading := false
var _epoch := 0
var _busy := false
var _save_error := ""

func _ready() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if catalog is Dictionary:
		seasons = catalog.get("seasons", [])
		cards = catalog.get("cards", [])
	_load_local()

func use_provider(value: Node, stable_account_id: String) -> void:
	# The host supplies a verified account ID; never infer it from a nickname.
	_epoch += 1
	provider = value
	account_id = stable_account_id
	inventory = {}
	inventory_known = false
	revision = -1
	_busy = false
	loading = false
	wanted = {}
	operation = {}
	_save_error = ""
	status = ""
	_load_local()
	changed.emit()

func card(id: String) -> Dictionary:
	for item in cards:
		if str(item.id) == id:
			return item
	return {}

func is_busy() -> bool:
	return _busy

func season(id: String) -> Dictionary:
	for item in seasons:
		if str(item.id) == id:
			return item
	return {}

func count(id: String) -> int:
	return int(inventory.get(id, {}).get("count", 0)) if inventory_known else -1

func is_wanted(id: String) -> bool:
	return bool(wanted.get(id, false))

func results(season_id: String, filter: String) -> Array:
	var found: Array = []
	for item in cards:
		if str(item.season_id) != season_id:
			continue
		if filter == "owned" and count(item.id) <= 0:
			continue
		if filter == "wanted" and not is_wanted(item.id):
			continue
		found.append(item)
	return found

func summary() -> Dictionary:
	var kinds := 0
	var total := 0
	# A complete authoritative inventory, never the currently displayed page.
	for value in inventory.values():
		var amount := int(value.get("count", 0))
		if amount > 0:
			kinds += 1
			total += amount
	return {"known": inventory_known, "kinds": kinds, "total": total}

func set_wanted(id: String, value: bool) -> Dictionary:
	if card(id).is_empty():
		return {"ok": false, "message": "这张卡已不在可见目录中。"}
	var previous := wanted.duplicate()
	if value:
		wanted[id] = true
	else:
		wanted.erase(id)
	# Synchronous atomic local commits serialize rapid intents, without stale replies.
	if not _save_local():
		wanted = previous
		return {"ok": false, "message": _save_error}
	changed.emit()
	return {"ok": true}

func gift_rule(id: String) -> Dictionary:
	if card(id).is_empty():
		return {"max": 0, "reason": "这张卡已不在可见目录中。"}
	if not is_instance_valid(provider):
		return {"max": 0, "reason": "赠送服务尚未接入，暂时无法赠送。"}
	if not inventory_known:
		return {"max": 0, "reason": "尚未取得当前库存，暂时无法赠送。"}
	if count(id) <= 0:
		return {"max": 0, "reason": "尚未拥有这张卡。"}
	if count(id) == 1:
		return {"max": 0, "reason": KEEP_ONE_REASON}
	var entry: Dictionary = inventory.get(id, {})
	if not entry.has("giftable_count"):
		return {"max": 0, "reason": "服务未返回可赠数量，暂时无法赠送。"}
	return {"max": mini(count(id) - 1, maxi(0, int(entry.giftable_count))),
		"reason": str(entry.get("gift_reason", "")), "consequence": str(entry.get("gift_consequence", ""))}

func refresh() -> void:
	if not is_instance_valid(provider):
		return
	_epoch += 1
	var ticket := _epoch
	var owner_id := account_id
	loading = true
	changed.emit()
	var response: Dictionary = await provider.request_snapshot(owner_id)
	if ticket != _epoch or owner_id != account_id:
		return
	loading = false
	if not response.get("ok", false) or not _apply_snapshot(response):
		status = str(response.get("message", "库存读取失败，请重试。"))
	else:
		status = ""
	changed.emit()

func _apply_snapshot(response: Dictionary) -> bool:
	# Reject partial inventories, old reads, wrong-account responses and invalid counts.
	if response.get("account_id", "") != account_id or not response.get("inventory_complete", false):
		return false
	var next_revision := int(response.get("revision", -1))
	if next_revision < 0 or not response.get("inventory") is Dictionary:
		return false
	if next_revision < revision:
		return true
	for entry in response.inventory.values():
		if not entry is Dictionary or not entry.has("count"):
			return false
		if not (entry.count is int or entry.count is float) or float(entry.count) < 0 or float(entry.count) != floor(float(entry.count)):
			return false
	inventory = response.inventory.duplicate(true)
	revision = next_revision
	inventory_known = true
	return true

func friends(query: String) -> Dictionary:
	var social := get_node_or_null("/root/AppServices/SocialStore")
	if social != null and social.account_id == account_id and social.available():
		return await social.request("friends", {"query": query, "eligible_for_gift": true})
	if not is_instance_valid(provider):
		return {"ok": false, "message": "好友服务尚未接入。", "friends": []}
	var owner_id := account_id
	var response: Dictionary = await provider.request_friends(owner_id, query)
	if owner_id != account_id:
		return {"ok": false, "message": "账户已切换。", "friends": []}
	return response

func search_friends(query: String, ticket: String) -> void:
	# The store outlives a dismissed dialog; no suspended coroutine retains UI.
	var response: Dictionary = await friends(query)
	friends_loaded.emit(ticket, response)

func pending() -> bool:
	return operation.get("state", "") in ["pending", "unknown"]

func submit_gift(card_id: String, friend_id: String, amount: int) -> Dictionary:
	if _busy or pending():
		return _gift_result({"ok": false, "message": "上一笔赠送正在核实，请查询结果。"})
	var rule := gift_rule(card_id)
	if amount < 1 or amount > int(rule.max) or friend_id.is_empty():
		var reason := str(rule.reason)
		if reason.is_empty() and count(card_id) > 0 and amount >= count(card_id):
			reason = KEEP_ONE_REASON
		return _gift_result({"ok": false, "message": reason if not reason.is_empty() else "请核对好友和可赠数量。"})
	var previous := operation.duplicate(true)
	operation = {"id": Crypto.new().generate_random_bytes(24).hex_encode(), "account_id": account_id,
		"card_id": card_id, "friend_id": friend_id, "quantity": amount, "state": "pending"}
	# Persist intent BEFORE dispatch. Reopening/restarting only queries this same ID.
	if not _save_local():
		operation = previous
		return _gift_result({"ok": false, "message": _save_error})
	_busy = true
	operation_changed.emit()
	var owner_id := account_id
	var operation_id: String = operation.id
	var response: Dictionary = await provider.send_gift(operation.duplicate(true))
	if owner_id != account_id or operation.get("id") != operation_id:
		return {"ok": false, "message": "账户已切换；返回原账户后查询赠送结果。"}
	_busy = false
	return _finish_operation(response)

func recover_gift() -> Dictionary:
	if _busy or not pending() or not is_instance_valid(provider):
		return {"ok": false, "message": "请等待当前查询完成，或接通赠送服务。"}
	_busy = true
	var owner_id := account_id
	var operation_id: String = operation.id
	operation_changed.emit()
	var response: Dictionary = await provider.gift_status(owner_id, operation_id)
	if owner_id != account_id or operation.get("id") != operation_id:
		return {"ok": false, "message": "账户已切换。"}
	_busy = false
	return _finish_operation(response)

func _finish_operation(response: Dictionary) -> Dictionary:
	var state := str(response.get("state", "unknown"))
	# Success requires an authoritative complete inventory in the same response.
	var valid: bool = response.get("operation_id", "") == operation.id and response.get("account_id", "") == account_id
	if valid and state == "succeeded" and _apply_snapshot(response):
		operation.state = "succeeded"
		status = "赠送成功，库存已更新。"
	elif valid and state == "failed":
		if not _apply_snapshot(response):
			inventory_known = false
		operation.state = "failed"
		status = str(response.get("message", "赠送未完成，请检查库存和赠送资格。"))
	else:
		operation.state = "unknown"
		status = "赠送结果尚未确认，请查询结果；不会重复扣卡。"
	if not _save_local():
		status += " 结果保存失败；重启后将查询原操作。"
	changed.emit()
	operation_changed.emit()
	return _gift_result({"ok": operation.state == "succeeded", "message": status, "state": operation.state})

func _gift_result(result: Dictionary) -> Dictionary:
	gift_completed.emit(result)
	return result

func _path() -> String:
	return SAVE_DIR.path_join(account_id.sha256_text() + ".json")

func _load_local() -> void:
	var path := _path()
	if not FileAccess.file_exists(path):
		return
	var parsed = JsonStore.read(path)
	if not parsed is Dictionary or parsed.get("account_id") != account_id or not parsed.get("wanted") is Dictionary:
		status = "本机收藏存档无法读取，已保留原文件；请检查存档。"
		_save_error = status
		return
	wanted = parsed.wanted
	operation = parsed.get("operation", {})
	_save_error = ""

func _save_local() -> bool:
	if not _save_error.is_empty() and _save_error.contains("原文件"):
		return false
	if JsonStore.write(_path(), {"version": 1, "account_id": account_id, "wanted": wanted, "operation": operation}) != OK:
		_save_error = "保存失败，原状态已保留，请检查本机存储空间和写入权限后重试。"
		return false
	_save_error = ""
	return true
