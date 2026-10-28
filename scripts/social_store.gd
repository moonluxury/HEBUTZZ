extends Node
## Session-scoped social state. Only a trusted provider can return official/business events.
signal changed
signal messages_changed(conversation_id: String)
signal completed(ticket: String, response: Dictionary)
const Policy = preload("res://scripts/social_policy.gd")
const TEXT_LIMIT := Policy.TEXT_LIMIT
const NOTE_LIMIT := Policy.NOTE_LIMIT
const REMARK_LIMIT := Policy.REMARK_LIMIT
const REPORT_LIMIT := Policy.REPORT_LIMIT
const PAGE_SIZE := Policy.PAGE_SIZE
const POLL_SECONDS := Policy.POLL_SECONDS
const SAVE_DIR := "user://social_v1"
var provider: Node
var account_id := ""
var epoch := 0
var session_epoch := -1
var revision := -1
var cursor := ""
var friends: Array = []
var conversations: Array = []
var requests: Array = []
var trades: Dictionary = {}
var messages: Dictionary = {}
var history_before: Dictionary = {}
var history_loaded: Dictionary = {}
var history_busy: Dictionary = {}
var history_errors: Dictionary = {}
var drafts: Dictionary = {}
var positions: Dictionary = {}
var selected := ""
var tab := "friends"
var error := ""
var loading := false
var connected := false
var pending_requests := 0
var request_unread := 0
var capabilities: Dictionary = {}
var active := false
var bell_requested := false
var _refreshing := false
var _wait := 0.0
var _backoff := POLL_SECONDS
var _busy: Dictionary = {}
var _read_inflight: Dictionary = {}
var _intents: Dictionary = {}

func _ready() -> void:
	get_node("/root/ProfileStore").changed.connect(_session_changed)
	get_node("/root/PageRouter").collection_store().gift_completed.connect(_gift_finished)
	_session_changed()

func _session_changed() -> void:
	var profile := get_node("/root/ProfileStore")
	if session_epoch == profile.epoch:
		return
	session_epoch = profile.epoch
	epoch += 1
	provider = profile.provider if profile.authenticated() else null
	account_id = profile.account_id
	for value in [trades, messages, history_before, history_loaded, history_busy, history_errors, drafts, positions, _busy, _read_inflight, _intents]:
		value.clear()
	friends = []
	conversations = []
	requests = []
	capabilities = {}
	pending_requests = 0
	request_unread = 0
	revision = -1
	cursor = ""
	selected = ""
	tab = "friends"
	_refreshing = false
	loading = false
	connected = false
	_load_preferences()
	error = unavailable()
	changed.emit()
	if not account_id.is_empty():
		refresh()

func available() -> bool:
	return not account_id.is_empty() and is_instance_valid(provider) and provider.has_method("social_request")

func unavailable() -> String:
	if account_id.is_empty():
		return "当前未登录。请从个人中心使用现有登录方式；此版本尚未接入正式登录服务。" if not is_instance_valid(get_node("/root/ProfileStore").provider) else "当前未登录，请从个人中心登录。"
	return "好友与聊天服务尚未接入，无法读取联系人或发送消息。" if not available() else ""

func _process(delta: float) -> void:
	if not available():
		return
	_wait -= delta
	if _wait <= 0:
		_wait = _backoff if active and get_tree().root.has_focus() else maxf(30.0, _backoff)
		refresh()

func request(action: String, payload: Dictionary = {}) -> Dictionary:
	if not available():
		return {"ok": false, "code": "unavailable", "message": unavailable()}
	var generation := epoch
	var response: Variant = await provider.social_request(action, payload.duplicate(true))
	if generation != epoch:
		return {"ok": false, "code": "stale", "message": "账号已切换，旧请求已忽略。"}
	if not response is Dictionary or response.get("account_id", "") != account_id:
		return {"ok": false, "code": "invalid_response", "message": "服务响应身份不匹配，请重新连接。"}
	if response.get("code") == "unauthenticated":
		# Existing host owns reauthentication. Clear private views immediately.
		get_node("/root/ProfileStore").use_provider(provider, {"state": "signed_out"})
		return {"ok": false, "code": "stale", "message": "登录已失效，请从个人中心重新登录。"}
	return response

func refresh() -> void:
	if _refreshing:
		return
	if not available():
		_refresh_legacy_friends()
		return
	_refreshing = true
	loading = revision < 0
	var generation := epoch
	if loading:
		changed.emit()
	var response := await request("sync", {"cursor": cursor})
	if generation != epoch:
		return
	_refreshing = false
	loading = false
	if response.get("code") == "cursor_expired" and not cursor.is_empty():
		cursor = ""
		history_loaded.clear()
		refresh.call_deferred()
		return
	connected = bool(response.get("ok", false))
	if connected and _apply_sync(response):
		error = ""
		_backoff = POLL_SECONDS
	else:
		error = str(response.get("message", "连接失败，草稿已保留。可点击重新连接。"))
		_backoff = minf(60.0, _backoff * 2)
	changed.emit()

func _refresh_legacy_friends() -> void:
	# A host may already expose the older friend lookup without a chat service.
	var collection: Node = get_node("/root/PageRouter").collection_store()
	if account_id.is_empty() or not is_instance_valid(collection.provider) or not collection.provider.has_method("request_friends"):
		return
	_refreshing = true
	loading = true
	var generation := epoch
	var response: Dictionary = await collection.friends("")
	if generation != epoch:
		return
	_refreshing = false
	loading = false
	if response.get("ok", false):
		friends = response.get("friends", []).duplicate(true)
	else:
		error = str(response.get("message", "好友读取失败，请重试。"))
	changed.emit()

func _apply_sync(response: Dictionary) -> bool:
	var next := int(response.get("revision", -1))
	if next < 0 or not response.get("conversations") is Array or not response.get("friends") is Array:
		return false
	if next < revision:
		return true
	revision = next
	cursor = str(response.get("cursor", cursor))
	friends = response.friends.duplicate(true)
	conversations = response.conversations.duplicate(true)
	requests = response.get("requests", []).duplicate(true)
	pending_requests = int(response.get("pending_requests", 0))
	request_unread = int(response.get("request_unread", 0))
	capabilities = response.get("capabilities", {})
	for trade in response.get("trades", []):
		_merge_trade(trade)
	for message in response.get("messages", []):
		merge_message(message)
	return true

func _merge_trade(trade: Dictionary) -> void:
	var id := str(trade.get("id", ""))
	if id.is_empty() or int(trade.get("revision", 0)) < int(trades.get(id, {}).get("revision", -1)):
		return
	var newly_completed: bool = trade.get("status") == "completed" and trades.get(id, {}).get("status") != "completed"
	trades[id] = trade.duplicate(true)
	if newly_completed:
		get_node("/root/PageRouter").collection_store().refresh()

func conversation(id: String) -> Dictionary:
	for item in conversations:
		if str(item.id) == id:
			return item
	return {}

func peer(id: String) -> Dictionary:
	for item in friends:
		if str(item.id) == id:
			return item
	return {}

func display_name(item: Dictionary) -> String:
	return str(item.get("remark", "")) if not str(item.get("remark", "")).is_empty() else str(item.get("name", ""))

func list_items(query: String) -> Array:
	var found: Array = []
	for item in friends if tab == "friends" else conversations:
		var person: Dictionary = item.get("peer", {}) if tab != "friends" else item
		var haystack := "%s %s %s" % [person.get("remark", ""), person.get("name", item.get("name", "")), person.get("public_id", "")]
		if query.strip_edges().is_empty() or query.to_lower() in haystack.to_lower():
			found.append(item)
	if tab != "friends":
		found.sort_custom(func(a, b):
			if (a.get("kind") == "system") != (b.get("kind") == "system"):
				return a.get("kind") == "system"
			if bool(a.get("pinned", false)) != bool(b.get("pinned", false)):
				return bool(a.get("pinned", false))
			return int(a.get("activity_seq", 0)) > int(b.get("activity_seq", 0)))
	return found

func select(id: String) -> void:
	selected = id
	_save_preferences()
	changed.emit()
	if not id.is_empty() and not history_loaded.has(id):
		load_history(id)

func set_tab(value: String) -> void:
	tab = value if value in ["friends", "recent"] else "friends"
	_save_preferences()
	changed.emit()

func open_peer(id: String) -> void:
	for item in conversations:
		if str(item.get("peer", {}).get("id", "")) == id:
			select(str(item.id))
			return
	dispatch("open_conversation", {"peer_id": id}, "open_peer")

func dispatch(action: String, payload: Dictionary, ticket: String) -> void:
	var key := action + ":" + ticket
	if _busy.has(key):
		return
	_busy[key] = true
	var generation := epoch
	var response := await request(action, payload)
	if generation != epoch:
		return
	_busy.erase(key)
	if (response.get("ok", false) or response.get("definitive", false)) and payload.has("operation_id"):
		for fingerprint in _intents.keys():
			if _intents[fingerprint] == payload.operation_id:
				_intents.erase(fingerprint)
		_save_preferences()
	if response.get("ok", false):
		if response.has("sync"):
			_apply_sync(response.sync)
		if response.has("trade"):
			_merge_trade(response.trade)
		if response.has("conversation"):
			var value: Dictionary = response.conversation
			if conversation(str(value.id)).is_empty():
				conversations.append(value)
			select(str(value.id))
		if action in ["request_friend", "respond_request", "relationship", "preferences", "mark_all_read", "mark_requests_read", "create_trade", "trade_action"]:
			refresh()
	changed.emit()
	completed.emit(ticket, response)

func send_reason(id: String, text: String) -> String:
	if not available():
		return unavailable()
	var item := conversation(id)
	if item.is_empty():
		return "请先选择会话。"
	if item.get("kind") == "system":
		return "系统通知无需回复"
	if not item.get("can_send", false):
		return str(item.get("send_reason", "当前无法发送，请等待对方回复或检查关系状态。"))
	if not connected:
		return "连接已中断，草稿已保留。请重新连接后发送。"
	if text.strip_edges().is_empty():
		return "请输入消息。"
	if text.length() > TEXT_LIMIT:
		return "消息最多 %d 字。" % TEXT_LIMIT
	return ""

func send_text(id: String, text: String) -> String:
	if not send_reason(id, text).is_empty():
		return ""
	var client_id := new_id()
	var message := {"client_id": client_id, "conversation_id": id, "sender_id": account_id, "type": "text", "text": text, "state": "sending", "seq": 0}
	if not messages.has(id):
		messages[id] = []
	messages[id].append(message)
	# Clear only the exact submitted draft, before dispatch. Later input is never cleared.
	if drafts.get(id, "") == text:
		drafts[id] = ""
	messages_changed.emit(id)
	_send(message)
	return client_id

func retry_text(id: String, client_id: String) -> void:
	for message in messages.get(id, []):
		if message.get("client_id") == client_id and message.get("state") == "failed":
			message.state = "sending"
			messages_changed.emit(id)
			_send(message)
			return

func _send(message: Dictionary) -> void:
	var generation := epoch
	var id := str(message.conversation_id)
	var response := await request("send_text", {"conversation_id": id, "client_id": message.client_id, "text": message.text})
	if generation != epoch:
		return
	if response.get("ok", false) and response.get("message_record") is Dictionary:
		merge_message(response.message_record)
		refresh()
	elif message.get("state") != "sent":
		message.state = "failed"
		message.error = str(response.get("message", "结果未确认，请使用原消息重试。"))
	messages_changed.emit(id)

func merge_message(message: Dictionary) -> void:
	var id := str(message.get("conversation_id", ""))
	if id.is_empty() or conversation(id).is_empty() or str(message.get("id", "")).is_empty() or int(message.get("seq", 0)) < 1:
		return
	if not messages.has(id):
		messages[id] = []
	var items: Array = messages[id]
	for i in items.size():
		var old: Dictionary = items[i]
		var same_client: bool = not str(message.get("client_id", "")).is_empty() and old.get("client_id") == message.get("client_id") and old.get("sender_id") == message.get("sender_id")
		if old.get("id") == message.id or same_client:
			# Do not let a mismatched receipt silently replace the original text/target.
			if same_client and (old.get("text", "") != message.get("text", "") or old.get("conversation_id") != id):
				return
			old.merge(message, true)
			old.state = "sent"
			_sort_messages(id)
			messages_changed.emit(id)
			return
	var accepted := message.duplicate(true)
	accepted.state = "sent"
	items.append(accepted)
	_sort_messages(id)
	messages_changed.emit(id)

func _sort_messages(id: String) -> void:
	messages[id].sort_custom(func(a, b): return int(a.get("seq", 9223372036854775807)) < int(b.get("seq", 9223372036854775807)) if int(a.get("seq", 0)) > 0 and int(b.get("seq", 0)) > 0 else int(a.get("seq", 0)) > int(b.get("seq", 0)))

func load_history(id: String, older := false) -> void:
	if history_busy.get(id, false):
		return
	history_busy[id] = true
	history_errors.erase(id)
	messages_changed.emit(id)
	var generation := epoch
	var response := await request("history", {"conversation_id": id, "before": history_before.get(id, "") if older else "", "limit": PAGE_SIZE})
	if generation != epoch:
		return
	history_busy.erase(id)
	if response.get("ok", false):
		for message in response.get("messages", []):
			merge_message(message)
		history_before[id] = str(response.get("next_before", ""))
		history_loaded[id] = true
	else:
		history_errors[id] = str(response.get("message", "历史消息加载失败，请重试。"))
	messages_changed.emit(id)

func mark_read(id: String, seq: int) -> void:
	if not active or seq <= int(conversation(id).get("read_seq", 0)) or _read_inflight.has(id):
		return
	_read_inflight[id] = true
	var generation := epoch
	var response := await request("mark_read", {"conversation_id": id, "through_seq": seq})
	if generation != epoch:
		return
	_read_inflight.erase(id)
	if response.get("ok", false):
		if response.has("sync"):
			_apply_sync(response.sync)
		changed.emit()

func unread_total(quiet := false) -> int:
	var count := request_unread
	for item in conversations:
		if quiet or not item.get("muted", false):
			count += int(item.get("unread", 0))
	return count

func bell_target() -> String:
	var fallback := ""
	for item in conversations:
		if int(item.get("unread", 0)) > 0 and not item.get("muted", false):
			if item.get("kind") == "system":
				return str(item.id)
			if fallback.is_empty():
				fallback = str(item.id)
	return fallback

func new_id() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()

func intent(action: String, payload: Dictionary) -> String:
	# Persist trade/action keys before dispatch; unknown outcomes survive window/app closure.
	var fingerprint := (action + JSON.stringify(payload, "", true)).sha256_text()
	if not _intents.has(fingerprint):
		_intents[fingerprint] = new_id()
	if not _save_preferences():
		return ""
	return str(_intents[fingerprint])

func forget_intent(action: String, payload: Dictionary) -> void:
	_intents.erase((action + JSON.stringify(payload, "", true)).sha256_text())
	_save_preferences()

func _save_preferences() -> bool:
	if account_id.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR.path_join(account_id.sha256_text() + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"account_id": account_id, "tab": tab, "selected": selected, "intents": _intents}))
	file.flush()
	var result := file.get_error()
	file.close()
	return result == OK and DirAccess.rename_absolute(path + ".tmp", path) == OK

func _load_preferences() -> void:
	if account_id.is_empty():
		return
	var path := SAVE_DIR.path_join(account_id.sha256_text() + ".json")
	if not FileAccess.file_exists(path):
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary and value.get("account_id") == account_id:
		tab = str(value.get("tab", "friends"))
		selected = str(value.get("selected", ""))
		_intents = value.get("intents", {})

func _gift_finished(response: Dictionary) -> void:
	if response.get("ok", false):
		refresh()
