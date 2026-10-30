extends Node
## A presentation adapter, not an authentication backend. Only the host supplies sessions.
signal changed
signal saved(ticket: String, result: Dictionary)
signal action_finished(ticket: String, result: Dictionary)
signal avatar_login_finished(flow: String, result: Dictionary)
const FIELDS := ["display_name", "bio", "school", "college", "major", "grade"]
var provider: Node
var account_id := ""
var session_state := "signed_out"
var profile: Dictionary = {}
var editable_fields: Dictionary = {}
var loading := false
var saving := false
var action_busy := false
var error := ""
var epoch := 0
var _read := 0
var avatar_pending: Dictionary = {}
var profile_pending: Dictionary = {}
var profile_timeout_seconds := 20.0
var avatar_timeout_seconds := 20.0

class BoundedResult extends RefCounted:
	signal finished(response: Dictionary)
	var done := false
	func resolve(response: Dictionary) -> void:
		if done: return
		done = true
		finished.emit(response)

func authenticated() -> bool:
	return session_state == "authenticated" and not account_id.is_empty()

func use_provider(value: Node, session: Dictionary, collection_provider: Node = null) -> void:
	# Session changes clear identity synchronously, before any asynchronous read.
	epoch += 1
	_read += 1
	provider = value
	session_state = str(session.get("state", "signed_out"))
	account_id = str(session.get("account_id", "")) if session_state == "authenticated" else ""
	if session_state == "authenticated" and account_id.is_empty():
		session_state = "loading"
	profile = {}
	editable_fields = {}
	loading = false
	saving = false
	avatar_pending = {}
	profile_pending = {}
	action_busy = false
	error = ""
	var collection: Node = get_node("/root/AppServices").collection_store()
	var adapter: Node = collection_provider
	if adapter == null and is_instance_valid(value) and value.has_method("request_snapshot") and value.has_method("request_friends"):
		adapter = value
	collection.use_provider(adapter if authenticated() else null, account_id if authenticated() else "local-profile")
	changed.emit()
	if authenticated():
		refresh()

func refresh() -> void:
	if not authenticated() or saving:
		return
	if not is_instance_valid(provider) or not provider.has_method("request_profile"):
		error = "个人资料服务尚未接入。"
		changed.emit()
		return
	_read += 1
	var read_id := _read
	var session_epoch := epoch
	loading = true
	error = ""
	changed.emit()
	var response: Dictionary = await provider.request_profile(account_id)
	if session_epoch != epoch or read_id != _read:
		return
	loading = false
	if not response.get("ok", false) or not _apply_profile(response):
		error = str(response.get("message", "资料读取失败，请重试。"))
	changed.emit()

func _apply_profile(response: Dictionary) -> bool:
	if response.get("account_id") != account_id or not response.get("profile") is Dictionary:
		return false
	var data: Dictionary = response.profile
	# Only the existing public identifier is exposed; internal account IDs are not substituted.
	if not str(profile.get("public_id", "")).is_empty() and data.get("public_id", "") != profile.public_id:
		return false
	var next: Dictionary = {}
	for field in FIELDS + ["public_id", "avatar_card_id"]:
		next[field] = str(data.get(field, ""))
	profile = next
	editable_fields = {}
	var permissions: Variant = response.get("editable_fields", {})
	if permissions is Dictionary:
		for field in FIELDS + ["avatar_card_id"]:
			if permissions.get(field) is Dictionary:
				editable_fields[field] = permissions[field].duplicate(true)
	return true

func avatar_editable() -> bool:
	return authenticated() and is_instance_valid(provider) and provider.has_method("save_profile") and editable_fields.has("avatar_card_id")

func validate_card_avatar(card_id: String) -> String:
	if not avatar_editable():
		return "头像设置暂不可用，请登录或稍后重试。"
	if card_id.is_empty():
		return "" if editable_fields.get("avatar_card_id", {}).get("reset_supported", false) else "当前服务尚不支持重置默认头像，请等待服务更新。"
	var collection: Node = get_node("/root/AppServices").collection_store()
	if collection.card(card_id).is_empty():
		return "只能选择卡牌目录中的头像。"
	if collection.account_id != account_id or not collection.inventory_known or collection.loading:
		return "正在确认卡牌拥有情况，请稍后重试。"
	if collection.count(card_id) <= 0:
		return "尚未拥有这张卡，暂时不能用作头像。"
	return ""

func save_profile(patch: Dictionary, avatar_card_id: String, ticket: String, request_id := "") -> void:
	if saving:
		return
	if not authenticated() or not is_instance_valid(provider) or not provider.has_method("save_profile"):
		saved.emit(ticket, {"ok": false, "message": "资料保存服务尚未接入。"})
		return
	for field in patch:
		if field not in FIELDS or not editable_fields.has(field):
			saved.emit(ticket, {"ok": false, "message": "该字段不允许修改。"})
			return
		var limit := int(editable_fields[field].get("max_length", 0))
		if limit > 0 and str(patch[field]).length() > limit:
			saved.emit(ticket, {"ok": false, "message": "输入超出服务允许的长度，请缩短后重试。"})
			return
	if not avatar_card_id.is_empty():
		var issue := validate_card_avatar(avatar_card_id)
		if not issue.is_empty():
			saved.emit(ticket, {"ok": false, "message": issue})
			return
	var snapshot := patch.duplicate(true)
	if not profile_pending.is_empty():
		if snapshot != profile_pending.patch or avatar_card_id != profile_pending.avatar_card_id:
			saved.emit(ticket, {"ok": false, "unknown": true, "message": "上一项资料保存结果待确认，请先核实原请求。"})
			return
		request_id = str(profile_pending.request_id)
	elif request_id.is_empty():
		request_id = Crypto.new().generate_random_bytes(24).hex_encode()
	var owner := account_id
	var generation := epoch
	var adapter := provider
	profile_pending = {"account_id": owner, "patch": snapshot, "avatar_card_id": avatar_card_id, "request_id": request_id}
	saving = true
	loading = false
	_read += 1
	error = ""
	changed.emit()
	# Capture the account, patch and idempotency key before any await.
	var submit: Callable = adapter.save_profile_request.bind(owner, snapshot, avatar_card_id, request_id) if adapter.has_method("save_profile_request") else adapter.save_profile.bind(owner, snapshot, avatar_card_id)
	var response := await _bounded(submit, profile_timeout_seconds)
	if generation != epoch or provider != adapter or account_id != owner: return
	var committed: bool = response.get("ok", false) and response.get("persisted", false)
	if committed and not avatar_card_id.is_empty():
		committed = response.get("profile") is Dictionary and response.profile.get("avatar_card_id") == avatar_card_id
	if committed: committed = _apply_profile(response)
	var unknown: bool = str(response.get("code", "")) in ["unknown", "network", "invalid_response"]
	if not committed and unknown:
		# A lost response does not prove that the server rejected the write.
		var current := await _bounded(adapter.request_profile.bind(owner), profile_timeout_seconds)
		if generation != epoch or provider != adapter or account_id != owner: return
		if current.get("ok", false) and current.get("account_id") == owner and current.get("profile") is Dictionary:
			var matches := true
			for field in snapshot:
				if str(current.profile.get(field, "")) != str(snapshot[field]): matches = false
			if not avatar_card_id.is_empty() and current.profile.get("avatar_card_id") != avatar_card_id: matches = false
			committed = matches and _apply_profile(current)
	if committed or not unknown: profile_pending = {}
	saving = false
	error = "" if committed else "保存结果尚未确认，请核实原请求后再继续。" if unknown else str(response.get("message", "未能确认资料已保存，请重试。"))
	changed.emit()
	saved.emit(ticket, {"ok": committed, "unknown": unknown and not committed, "message": "资料已更新" if committed else error})

func _invoke_bounded(callback: Callable, result: BoundedResult) -> void:
	if not callback.is_valid():
		result.resolve({"ok": false, "code": "unavailable"})
		return
	var response: Variant = await callback.call()
	result.resolve(response if response is Dictionary else {"ok": false, "code": "unknown"})

func _bounded(callback: Callable, seconds: float) -> Dictionary:
	var result := BoundedResult.new()
	var timer := get_tree().create_timer(seconds)
	var timeout := result.resolve.bind({"ok": false, "code": "unknown"})
	timer.timeout.connect(timeout, CONNECT_ONE_SHOT)
	_invoke_bounded.call_deferred(callback, result)
	var response: Dictionary = await result.finished
	if timer.timeout.is_connected(timeout): timer.timeout.disconnect(timeout)
	return response

func save_avatar(card_id: String, ticket: String, request_id: String) -> void:
	if saving: return
	if not authenticated() or not is_instance_valid(provider) or not provider.has_method("save_avatar"):
		saved.emit(ticket, {"ok": false, "message": "头像保存服务暂不可用，请稍后重试。"})
		return
	if not avatar_pending.is_empty():
		if card_id != avatar_pending.card_id:
			saved.emit(ticket, {"ok": false, "message": "上一项保存结果待核实，请先核实原请求。"})
			return
		request_id = str(avatar_pending.request_id)
	else:
		var issue := validate_card_avatar(card_id)
		if not issue.is_empty():
			saved.emit(ticket, {"ok": false, "message": issue})
			return
		avatar_pending = {"card_id": card_id, "request_id": request_id, "account_id": account_id}
	var owner := account_id
	var generation := epoch
	var adapter: Node = provider
	saving = true
	loading = false
	_read += 1
	error = ""
	changed.emit()
	var response := await _bounded(adapter.save_avatar.bind(owner, card_id, request_id), avatar_timeout_seconds)
	if generation != epoch: return
	var committed: bool = response.get("ok", false) and response.get("persisted", false) and response.get("account_id") == owner and response.get("profile") is Dictionary and response.profile.get("avatar_card_id") == card_id
	var unknown: bool = response.get("ok", false) or str(response.get("code", "")) in ["unknown", "network", "invalid_response"]
	if committed:
		committed = _apply_profile(response)
	elif unknown:
		# A timeout is not proof of failure. Read the authoritative value before allowing retry.
		var current := await _bounded(adapter.request_profile.bind(owner), avatar_timeout_seconds)
		if generation != epoch: return
		if current.get("ok", false) and current.get("account_id") == owner and current.get("profile") is Dictionary:
			committed = current.profile.get("avatar_card_id") == card_id and _apply_profile(current)
	if committed or not unknown: avatar_pending = {}
	saving = false
	error = "" if committed else "保存结果尚未确认，请核实原请求后再继续。" if unknown else str(response.get("message", "保存失败，请重试。"))
	changed.emit()
	saved.emit(ticket, {"ok": committed, "unknown": unknown and not committed, "message": "头像已更新" if committed else error})

func begin_avatar_login(flow: String) -> void:
	if not is_instance_valid(provider) or not provider.has_method("begin_avatar_login"):
		avatar_login_finished.emit(flow, {"ok": false, "message": "当前登录服务暂不可用，请稍后重试。"})
		return
	var response: Dictionary = await provider.begin_avatar_login(flow)
	avatar_login_finished.emit(flow, response)

func run_action(action: String, ticket: String) -> void:
	if action_busy:
		action_finished.emit(ticket, {"ok": false, "message": "上一项账号操作仍在进行，请稍后重试。"})
		return
	var missing := {"begin_login": "当前版本尚未接入登录服务。", "request_account": "账号与安全服务尚未接入。", "open_account_settings": "账号管理服务尚未接入。", "logout": "退出登录服务尚未接入。"}
	if not missing.has(action):
		return
	if action != "begin_login" and not authenticated():
		action_finished.emit(ticket, {"ok": false, "message": "当前未登录。"})
		return
	if not is_instance_valid(provider) or not provider.has_method(action):
		action_finished.emit(ticket, {"ok": false, "message": missing[action]})
		return
	action_busy = true
	var session_epoch := epoch
	var response: Dictionary = await provider.call(action) if action == "begin_login" else await provider.call(action, account_id)
	if session_epoch != epoch:
		return
	action_busy = false
	if action != "begin_login" and response.get("account_id") != account_id:
		response = {"ok": false, "message": "账号响应不匹配，请重试。"}
	if action == "logout" and response.get("ok", false):
		use_provider(provider, {"state": "signed_out"})
	action_finished.emit(ticket, response)

func display_name() -> String:
	if session_state == "loading":
		return "正在加载…"
	if not authenticated():
		return "登录"
	var value := str(profile.get("display_name", ""))
	return value if not value.is_empty() else "正在加载…" if loading else "已登录用户"

func copy_public_id(clipboard: Object = null) -> Dictionary:
	var value := str(profile.get("public_id", ""))
	if not authenticated() or value.is_empty():
		return {"ok": false, "message": "暂无可复制的用户 ID。"}
	var copied := false
	if clipboard != null:
		copied = clipboard.write_and_verify(value)
	elif DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(value)
		copied = DisplayServer.clipboard_get() == value
	return {"ok": copied, "message": "已复制" if copied else "复制失败，请重试或手动复制用户 ID。"}
