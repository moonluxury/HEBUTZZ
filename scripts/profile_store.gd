extends Node
## A presentation adapter, not an authentication backend. Only the host supplies sessions.
signal changed
signal saved(ticket: String, result: Dictionary)
signal action_finished(ticket: String, result: Dictionary)
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
	action_busy = false
	error = ""
	var collection: Node = get_node("/root/PageRouter").collection_store()
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
	for field in FIELDS + ["public_id", "avatar"]:
		next[field] = str(data.get(field, ""))
	profile = next
	editable_fields = {}
	var permissions: Variant = response.get("editable_fields", {})
	if permissions is Dictionary:
		for field in FIELDS + ["avatar"]:
			if permissions.get(field) is Dictionary:
				editable_fields[field] = permissions[field].duplicate(true)
	return true

func avatar_rules() -> Dictionary:
	var rules: Dictionary = editable_fields.get("avatar", {})
	# Do not invent upload restrictions where the backend has not defined them.
	if not rules.get("extensions") is Array or rules.get("extensions", []).is_empty() or int(rules.get("max_bytes", 0)) <= 0:
		return {}
	return rules

func validate_avatar(path: String) -> String:
	var rules := avatar_rules()
	if rules.is_empty():
		return "头像上传能力尚未接入。"
	if path.get_extension().to_lower() not in rules.extensions:
		return "请选择支持的头像格式：" + ", ".join(rules.extensions)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "无法读取所选头像，请重新选择。"
	if file.get_length() > int(rules.max_bytes):
		return "头像超过服务允许的大小（%s 字节）。" % rules.max_bytes
	if Image.load_from_file(path) == null:
		return "无法识别这张图片，请重新选择。"
	return ""

func save_profile(patch: Dictionary, avatar_file: String, ticket: String) -> void:
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
	if not avatar_file.is_empty():
		var issue := validate_avatar(avatar_file)
		if not issue.is_empty():
			saved.emit(ticket, {"ok": false, "message": issue})
			return
	saving = true
	loading = false
	_read += 1
	var session_epoch := epoch
	changed.emit()
	# Adapter must authorize, upload and persist before returning a canonical profile.
	var response: Dictionary = await provider.save_profile(account_id, patch.duplicate(true), avatar_file)
	if session_epoch != epoch:
		return
	saving = false
	var committed := bool(response.get("ok", false)) and bool(response.get("persisted", false))
	if committed and not avatar_file.is_empty():
		committed = response.get("profile") is Dictionary and not str(response.profile.get("avatar", "")).is_empty() and response.profile.get("avatar") != avatar_file
	if committed:
		committed = _apply_profile(response)
	error = "" if committed else str(response.get("message", "未能确认资料已保存，请重试。"))
	changed.emit()
	saved.emit(ticket, {"ok": committed, "message": "资料已保存" if committed else error})

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
