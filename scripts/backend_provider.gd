extends Node
## HTTPS adapter. Remembered sessions use OS-protected storage and server validation.
signal remembered_changed
const DEFAULT_URL := "https://39.107.44.18"
const DialogScript = preload("res://scripts/backend_login_dialog.gd")
const LoginStore = preload("res://scripts/local_login_store.gd")
var base_url := DEFAULT_URL
var access_token := ""
var account_id := ""
var auth_generation := 0
var active_dialog: Window
var login_store: Node
var remember_error := ""
var login_required := false
var _enforce_desktop_login := false
var _required_login_opening := false
var _quitting := false
var _locked_page: WeakRef
var _locked_process_mode := Node.PROCESS_MODE_INHERIT

func _ready() -> void:
	var configured := OS.get_environment("HEGONG_API_URL").strip_edges().trim_suffix("/")
	if not configured.is_empty():
		base_url = configured
	if OS.get_environment("HEGONG_BACKEND_DISABLED") == "1":
		return
	# Existing headless suites use isolated providers and must not touch live accounts.
	if DisplayServer.get_name() == "headless" and OS.get_environment("HEGONG_BACKEND_LIVE_TEST") != "1":
		return
	# Tool-driven checks supply their own isolated providers. Ordinary PC launches
	# always present the existing login form, including when an account is saved.
	if OS.has_feature("pc") and not OS.get_cmdline_args().has("--script"):
		enable_login_requirement()
	attach.call_deferred()

func enable_login_requirement() -> void:
	if _enforce_desktop_login: return
	_enforce_desktop_login = true
	login_required = true
	get_node("/root/PageRouter").login_guard = self
	get_node("/root/ProfileStore").changed.connect(_check_required_login)
	get_tree().scene_changed.connect(_lock_current_page)

func _check_required_login() -> void:
	if not _enforce_desktop_login or _quitting: return
	var profile_store := get_node("/root/ProfileStore")
	if profile_store.authenticated() and profile_store.provider == self:
		login_required = false
		_unlock_current_page()
		get_node("/root/PageRouter").resume_after_login()
		return
	login_required = true
	_lock_current_page()
	if not _required_login_opening:
		_required_login_opening = true
		_open_required_login.call_deferred()

func _lock_current_page() -> void:
	if not login_required or _quitting: return
	var page := get_tree().current_scene
	if not is_instance_valid(page): return
	if _locked_page != null and _locked_page.get_ref() == page: return
	_unlock_current_page()
	_locked_page = weakref(page)
	_locked_process_mode = page.process_mode
	page.process_mode = Node.PROCESS_MODE_DISABLED

func _unlock_current_page() -> void:
	var page: Node = _locked_page.get_ref() if _locked_page != null else null
	if is_instance_valid(page): page.process_mode = _locked_process_mode
	_locked_page = null

func _open_required_login() -> void:
	if _quitting or not login_required:
		_required_login_opening = false
		return
	_lock_current_page()
	var result: Dictionary
	if is_instance_valid(active_dialog):
		result = await active_dialog.finished
		await get_tree().process_frame # The existing auth caller attaches the session.
	else:
		result = await begin_login()
	_required_login_opening = false
	if _quitting: return
	if result.get("code") == "cancelled":
		_quitting = true
		auth_generation += 1
		_quit_application()
	else:
		_check_required_login()

func _quit_application() -> void:
	get_tree().quit()

func attach() -> void:
	get_node("/root/ProfileStore").use_provider(self, {"state": "signed_out"})

func _endpoint_allowed() -> bool:
	return base_url.begins_with("https://")

func _request(path: String, body: Dictionary, authenticated := true, credential: Dictionary = {}) -> Dictionary:
	var owner := str(credential.get("account_id", account_id))
	var request_token := str(credential.get("access_token", access_token))
	if not _endpoint_allowed():
		return {"ok": false, "account_id": owner, "code": "unavailable", "message": "后端必须使用 HTTPS 地址。"}
	if authenticated and request_token.is_empty():
		return {"ok": false, "account_id": owner, "code": "unauthenticated", "message": "请先登录。"}
	var headers := PackedStringArray(["Content-Type: application/json"])
	if authenticated:
		headers.append("Authorization: Bearer " + request_token)
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.max_redirects = 0
	http.body_size_limit = 4194304
	add_child(http)
	var error := http.request(base_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		http.queue_free()
		return {"ok": false, "account_id": owner, "code": "network", "message": "无法发起连接，请检查网络。"}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "account_id": owner, "code": "unknown", "message": "连接中断或超时，操作结果尚未确认。"}
	var status := int(result[1])
	if status == 401 and authenticated:
		if credential.is_empty() and account_id == owner and access_token == request_token:
			_login_store().invalidate(owner)
			access_token = ""
			account_id = ""
			auth_generation += 1
			get_node("/root/ProfileStore").use_provider(self, {"state": "signed_out"})
		return {"ok": false, "account_id": owner, "code": "unauthenticated", "message": "登录已失效，请重新登录。"}
	var parser := JSON.new()
	if parser.parse(result[3].get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok": false, "account_id": owner, "code": "unknown", "message": "服务响应异常，请稍后重试。"}
	var response: Dictionary = parser.data
	if status < 200 or status >= 300:
		response.ok = false
	response["http_status"] = status
	return response

func _normalize_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = value.duplicate(true)
		for key in result:
			if key in ["quantity", "terms_version", "through_seq", "limit", "expected_version", "expected_revision", "level", "start", "colspan", "rowspan", "width", "height", "price_batteries", "expected_price"] and result[key] is float and result[key] == floor(result[key]):
				result[key] = int(result[key])
			else:
				result[key] = _normalize_numbers(result[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_normalize_numbers(item))
		return result
	return value

func social_request(action: String, payload: Dictionary) -> Dictionary:
	return await _request("/v1/rpc", {"version": 1, "action": action, "payload": _normalize_numbers(payload)})

func comment_request(action: String, payload: Dictionary) -> Dictionary:
	if action in ["comment_list", "comment_replies"]:
		return await _request("/v1/comments/query", {"version": 1, "action": action, "payload": _normalize_numbers(payload)}, not access_token.is_empty())
	return await social_request(action, payload)

func submission_upload(asset: Dictionary) -> Dictionary:
	return await _request("/v1/submission-assets", asset)

func submission_get(path: String, binary := false) -> Dictionary:
	if not _endpoint_allowed():
		return {"ok": false, "message": "后端必须使用 HTTPS。"}
	if not path.begins_with("/v1/articles") and not path.begins_with("/v1/submission-assets/"):
		return {"ok": false, "message": "不支持的资源路径。"}
	var http := HTTPRequest.new()
	http.timeout = 15
	http.max_redirects = 0
	http.body_size_limit = 8388608
	add_child(http)
	var headers := PackedStringArray()
	if not access_token.is_empty(): headers.append("Authorization: Bearer " + access_token)
	if http.request(base_url + path, headers) != OK:
		http.queue_free()
		return {"ok": false, "message": "无法连接文章服务。"}
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		return {"ok": false, "message": "资源不存在、尚未公开或暂时无法访问。"}
	if binary:
		var mime := ""
		for header in response[2]:
			if str(header).to_lower().begins_with("content-type:"): mime = str(header).split(":", true, 1)[1].strip_edges().split(";")[0]
		return {"ok": true, "data": response[3], "mime": mime}
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	return parsed if parsed is Dictionary else {"ok": false, "message": "服务响应异常。"}

func request_profile(_owner: String) -> Dictionary:
	return await social_request("profile", {})

func save_profile(_owner: String, patch: Dictionary, avatar_card_id: String) -> Dictionary:
	if _owner != account_id: return {"ok": false, "account_id": _owner, "code": "stale"}
	return await social_request("save_profile", {"patch": patch, "avatar_card_id": avatar_card_id})

func save_profile_request(owner: String, patch: Dictionary, avatar_card_id: String, request_id: String) -> Dictionary:
	if owner != account_id: return {"ok": false, "account_id": owner, "code": "stale"}
	return await social_request("save_profile", {"patch": patch, "avatar_card_id": avatar_card_id, "operation_id": request_id})

func save_avatar(owner: String, avatar_card_id: String, request_id: String) -> Dictionary:
	if owner != account_id: return {"ok": false, "account_id": owner, "code": "stale"}
	return await social_request("save_profile", {"patch": {}, "avatar_card_id": avatar_card_id, "avatar_change": true, "operation_id": request_id})

func request_account(_owner: String) -> Dictionary:
	return await social_request("account", {})

func wallet_request(action: String, payload: Dictionary) -> Dictionary:
	return await _request("/v1/wallet", {"version": 1, "action": action, "payload": _normalize_numbers(payload)})

func open_publication() -> void:
	get_node("/root/PageRouter").go("res://scenes/Submissions.tscn")

func request_snapshot(_owner: String) -> Dictionary:
	return await social_request("snapshot", {})

func wishlist_request(action: String, payload: Dictionary) -> Dictionary:
	return await social_request(action,payload)

func request_friends(_owner: String, query: String) -> Dictionary:
	return await social_request("friends", {"query": query, "eligible_for_gift": true})

func send_gift(operation: Dictionary) -> Dictionary:
	return await social_request("send_gift", {"operation_id": str(operation.get("id", "")),
		"card_id": str(operation.get("card_id", "")), "friend_id": str(operation.get("friend_id", "")),
		"quantity": int(operation.get("quantity", 0))})

func gift_status(_owner: String, operation_id: String) -> Dictionary:
	return await social_request("gift_status", {"operation_id": operation_id})

func password_auth(username: String, password: String, register := false) -> Dictionary:
	var server := base_url
	var response: Dictionary = await _request("/v1/auth/register" if register else "/v1/auth/login",
		{"username": username, "password": password}, false)
	if server != base_url: return {"ok": false, "code": "stale", "message": "登录服务已改变，请重试。"}
	if response.get("ok", false): response.username = username.strip_edges().to_lower()
	return response

func _login_store() -> Node:
	if not is_instance_valid(login_store):
		login_store = LoginStore.new()
		login_store.name = "LocalLoginStore"
		add_child(login_store)
		login_store.configure(base_url)
		login_store.changed.connect(remembered_changed.emit)
	elif login_store.endpoint != base_url.trim_suffix("/"):
		login_store.configure(base_url)
	return login_store

func remembered_account() -> Dictionary:
	var memory := _login_store()
	return memory.account() if memory.endpoint == base_url.trim_suffix("/") else {}

func forget_remembered_account() -> bool:
	return _login_store().forget()

func remembered_auth() -> Dictionary:
	var memory := _login_store()
	var saved: Dictionary = remembered_account()
	if saved.is_empty() or not saved.can_resume:
		return {"ok": false, "code": "unavailable", "message": "请使用密码登录该账号。"}
	var generation := auth_generation
	var ticket: int = memory.revision
	var server := base_url
	var credential: Dictionary = await memory.credential()
	if generation != auth_generation or ticket != memory.revision or server != base_url:
		return {"ok": false, "code": "stale", "message": "本机登录记录已改变，请重新选择。"}
	if credential.is_empty():
		memory.invalidate(str(saved.account_id))
		return {"ok": false, "code": "invalid_local_session", "message": "本机登录凭证无法使用，请输入密码重新登录。"}
	# Validate the stored bearer with the server before changing any application session.
	var response: Dictionary = await _request("/v1/rpc", {"version": 1, "action": "profile", "payload": {}}, true, credential)
	if generation != auth_generation or ticket != memory.revision or server != base_url:
		return {"ok": false, "code": "stale", "message": "账号状态已改变，请重新打开登录窗口。"}
	if not response.get("ok", false):
		if response.get("code") == "unauthenticated" or int(response.get("http_status", 0)) == 401:
			memory.invalidate(str(saved.account_id))
			response.message = "上次登录已过期，请输入密码重新登录。"
		return response
	if response.get("account_id") != credential.account_id or not response.get("profile") is Dictionary:
		memory.invalidate(str(saved.account_id))
		return {"ok": false, "code": "invalid_response", "message": "登录信息无法确认，请使用密码登录。"}
	response.access_token = credential.access_token
	response.username = credential.username
	response["_remembered_login"] = true
	return response

func _remember_session(response: Dictionary) -> void:
	if response.get("_remembered_login", false) or not LoginStore.valid_username(str(response.get("username", ""))): return
	var generation := auth_generation
	var success: bool = await _login_store().remember(str(response.username), account_id, access_token, str(response.get("expires_at", "")))
	if generation == auth_generation:
		remember_error = "" if success else "已登录，但本机快捷登录凭证未能保存。"

func accept_session(response: Dictionary) -> bool:
	if not response.get("ok", false) or str(response.get("access_token", "")).is_empty() or str(response.get("account_id", "")).is_empty():
		return false
	access_token = str(response.access_token)
	account_id = str(response.account_id)
	auth_generation += 1
	remember_error = ""
	_remember_session(response)
	get_node("/root/ProfileStore").use_provider(self, {"state": "authenticated", "account_id": account_id}, self)
	get_node("/root/AppServices").collection_store().refresh()
	return true

func logout(_owner: String) -> Dictionary:
	var generation := auth_generation
	var response: Dictionary = await _request("/v1/auth/logout", {})
	if generation != auth_generation:
		return {"ok": false, "code": "stale", "account_id": _owner, "message": "账号状态已改变。"}
	if response.get("ok", false):
		_login_store().invalidate(_owner)
		access_token = ""
		account_id = ""
		auth_generation += 1
	return response

func change_password(current: String, replacement: String) -> Dictionary:
	var owner := account_id
	var response: Dictionary = await _request("/v1/auth/password", {"current_password": current, "new_password": replacement})
	if response.get("ok", false): _login_store().invalidate(owner)
	return response

func begin_login() -> Dictionary:
	return await _show_auth(false)

func begin_avatar_login(flow: String) -> Dictionary:
	var response := await _show_auth(false)
	if response.get("ok", false):
		response.avatar_login_context = flow
		response.session_epoch = get_node("/root/ProfileStore").epoch
	return response

func open_account_settings(_owner: String) -> Dictionary:
	return await _show_auth(true)

func _show_auth(password_mode: bool) -> Dictionary:
	if is_instance_valid(active_dialog):
		active_dialog.grab_focus()
		return {"ok": false, "account_id": account_id, "message": "请先完成已打开的账号窗口。"}
	var profile_store: Node = get_node("/root/ProfileStore")
	var session_epoch: int = profile_store.epoch
	var origin: Window
	var origin_focus: Control
	var origin_shade: CanvasItem
	# Keep the source draft alive, but show only the account modal and one shade.
	for candidate in get_tree().root.find_children("*", "Window", true, false):
		if candidate is Window and candidate.visible and candidate.get_script() != null and candidate.get_script().resource_path in ["res://scripts/profile_dialog.gd", "res://scripts/avatar_settings_dialog.gd"]:
			origin = candidate
			origin_focus = origin.gui_get_focus_owner()
			origin_shade = origin.get("shade") as CanvasItem
			if is_instance_valid(origin_shade): origin_shade.hide()
			origin.hide()
			break
	var dialog: Window = DialogScript.new()
	active_dialog = dialog
	dialog.provider = self
	dialog.password_mode = password_mode
	get_tree().root.add_child(dialog)
	var invalidate := func():
		if is_instance_valid(dialog) and not dialog.done and profile_store.epoch != session_epoch:
			dialog._cancel()
	profile_store.changed.connect(invalidate)
	var origin_closed := func():
		if is_instance_valid(dialog) and not dialog.done: dialog._cancel()
	if is_instance_valid(origin): origin.closed.connect(origin_closed, CONNECT_ONE_SHOT)
	dialog.present()
	var result: Dictionary = await dialog.finished
	if profile_store.changed.is_connected(invalidate): profile_store.changed.disconnect(invalidate)
	if is_instance_valid(origin) and origin.closed.is_connected(origin_closed): origin.closed.disconnect(origin_closed)
	active_dialog = null
	if session_epoch != profile_store.epoch:
		result = {"ok": false, "account_id": account_id, "message": "登录期间账号状态已改变，请重新打开设置。"}
	elif result.get("ok", false):
		if password_mode:
			access_token = ""
			account_id = ""
			auth_generation += 1
			profile_store.use_provider(self, {"state": "signed_out"})
		elif not accept_session(result):
			result = {"ok": false, "message": "登录信息无法确认，请重试。"}
	if is_instance_valid(origin) and not origin.is_queued_for_deletion() and not origin.closing:
		if is_instance_valid(origin_shade): origin_shade.show()
		origin.present()
		if is_instance_valid(origin_focus) and origin_focus.is_inside_tree() and origin_focus.is_visible_in_tree(): origin_focus.grab_focus()
	# Never propagate a token to UI status panels or diagnostics.
	result.erase("access_token")
	result.erase("_remembered_login")
	return result
