extends SceneTree
## Uses the production HTTPS adapter; credentials remain in process memory.
const API = preload("res://scripts/backend_provider.gd")
var checks := 0
var failures := 0
var bank := ""
var accounts: Array = []
var control_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures += 1; printerr("COMMENT CHECK FAILED: " + label)

func _write_ids() -> void:
	var file := FileAccess.open(control_dir.path_join("identities.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"bank":bank, "accounts":accounts})); file.close()

func _rpc(api: Node, action: String, fields: Dictionary = {}) -> Dictionary:
	var payload := fields.duplicate(true)
	payload.target_type = "bank"; payload.target_id = bank
	if action not in ["comment_list", "comment_replies"] and not payload.has("operation_id"):
		payload.operation_id = Crypto.new().generate_random_bytes(16).hex_encode()
	return await api.comment_request(action, payload)

func _run() -> void:
	control_dir = OS.get_environment("HEGONG_COMMENTS_LIVE_CONTROL")
	if OS.get_environment("HEGONG_BACKEND_LIVE_TEST") != "1" or not OS.get_user_data_dir().contains("comments-live-") or control_dir.is_empty():
		printerr("Live checks require explicit activation and isolated saves."); quit(2); return
	await process_frame; await process_frame
	var nonce := Crypto.new().generate_random_bytes(8).hex_encode()
	bank = "commentcheck_" + nonce
	var clients: Array = []
	for suffix in ["a", "b"]:
		var api := API.new(); root.add_child(api); clients.append(api)
		var username := "commentcheck_" + nonce + str(suffix)
		var registered: Dictionary = await api.password_auth(username, Crypto.new().generate_random_bytes(24).hex_encode(), true)
		check(registered.get("ok", false), "register disposable identity over verified HTTPS")
		if not registered.get("ok", false): _write_ids(); quit(1); return
		api.account_id = str(registered.account_id); api.access_token = str(registered.access_token)
		accounts.append({"id":api.account_id, "username":username}); _write_ids()
	for attempt in 300:
		if FileAccess.file_exists(control_dir.path_join("ready")): break
		await create_timer(0.1).timeout
	if not FileAccess.file_exists(control_dir.path_join("ready")): printerr("Private bank setup timed out"); quit(1); return
	var a: Node = clients[0]; var b: Node = clients[1]
	var guest := API.new(); root.add_child(guest)
	for subject in root.get_node("AppState").SUBJECTS:
		var response: Dictionary = await guest.comment_request("comment_list", {"target_type":"bank", "target_id":subject, "sort":"latest", "limit":20})
		check(response.get("ok", false) and response.get("items") is Array, "public bank readable: " + subject)
	var denied := await _rpc(guest, "comment_list")
	check(denied.get("http_status") == 403, "private fixture invisible to visitors")
	var operation := Crypto.new().generate_random_bytes(16).hex_encode()
	var created := await _rpc(a, "comment_create", {"body":"私有接口验收记录", "parent_id":"", "operation_id":operation})
	check(created.get("ok", false), "publish persisted")
	var id := str(created.get("comment", {}).get("id", ""))
	if id.is_empty(): quit(1); return
	var repeated := await _rpc(a, "comment_create", {"body":"私有接口验收记录", "parent_id":"", "operation_id":operation})
	check(repeated.get("comment", {}).get("id") == id, "duplicate request returns original comment")
	var conflict := await _rpc(a, "comment_create", {"body":"改变后的内容", "parent_id":"", "operation_id":operation})
	check(conflict.get("http_status") == 409, "operation identifier cannot change content")
	var reply := await _rpc(b, "comment_create", {"body":"私有回复验收", "parent_id":id})
	check(reply.get("ok", false), "reply persisted")
	var replies := await _rpc(a, "comment_replies", {"parent_id":id,"limit":20})
	check(replies.get("items", []).size() == 1, "reply fetched from server")
	var third_level := await _rpc(b, "comment_create", {"body":"不应创建第三层", "parent_id":reply.get("comment", {}).get("id", "")})
	check(third_level.get("http_status") == 409, "reply depth enforced")
	var liked := await _rpc(b, "comment_like", {"comment_id":id,"value":true})
	check(liked.get("comment", {}).get("like_count") == 1 and liked.get("comment", {}).get("liked", false), "like persisted")
	var hot := await _rpc(a, "comment_list", {"sort":"hot","limit":20})
	check(hot.get("items", []).size() == 1 and hot.items[0].id == id, "hot list uses database state")
	var unlike := await _rpc(b, "comment_like", {"comment_id":id,"value":false})
	check(unlike.get("comment", {}).get("like_count") == 0, "unlike persisted")
	var report := await _rpc(b, "comment_report", {"comment_id":id,"reason":"私有验收记录"})
	check(report.get("ok", false), "report recorded")
	var other_delete := await _rpc(b, "comment_delete", {"comment_id":id})
	check(other_delete.get("http_status") == 403, "another user cannot delete comment")
	var removed := await _rpc(a, "comment_delete", {"comment_id":id})
	check(removed.get("comment", {}).get("status") == "deleted" and removed.get("comment", {}).get("body") == "", "author deletion persisted")
	var final := await _rpc(b, "comment_list", {"sort":"latest", "limit":20})
	check(final.get("items", []).size() == 1 and final.items[0].status == "deleted", "deletion visible in fresh read")
	var forbidden_write := await _rpc(guest, "comment_create", {"body":"未登录不得发表"})
	check(not forbidden_write.get("ok", false), "anonymous writes rejected")
	var invalid := await guest.comment_request("comment_list", {"target_type":"bank","target_id":"marxism","sort":[]})
	check(invalid.get("http_status") == 400, "malformed input returns 400")
	for api in clients:
		var logout: Dictionary = await api._request("/v1/auth/logout", {})
		check(logout.get("ok", false), "temporary session revoked")
	print("COMMENTS LIVE: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
