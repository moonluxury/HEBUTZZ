extends "res://scripts/backend_provider.gd"
## Isolated authentication responses; no production network or credentials.
var login_calls := 0
var resume_calls := 0
var delay := 0.12
var resume_fails := false
var memory := {"username": "saved_user", "account_id": "account-saved_user", "can_resume": true}

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("workbench-check"))
	enable_login_requirement()
	attach.call_deferred()

func remembered_account() -> Dictionary: return memory.duplicate(true)
func _remember_session(_response: Dictionary) -> void: pass

func _response_delay() -> void:
	# A process-frame wait is owned by SceneTree and can be released immediately
	# when the real quit test stops, unlike a retained SceneTreeTimer fixture.
	var deadline := Time.get_ticks_msec() + int(delay * 1000)
	while Time.get_ticks_msec() < deadline: await get_tree().process_frame

func remembered_auth() -> Dictionary:
	resume_calls += 1
	await _response_delay()
	if resume_fails: return {"ok": false, "code": "network", "message": "连接失败，请重试。"}
	return {"ok": true, "account_id": "account-saved_user", "access_token": "isolated-startup-session", "_remembered_login": true}

func _request(path: String, body: Dictionary, _authenticated := true, _credential: Dictionary = {}) -> Dictionary:
	if path in ["/v1/auth/login", "/v1/auth/register"]:
		login_calls += 1
		await _response_delay()
		if body.get("password") != "fixture-password-123": return {"ok": false, "message": "账号或密码错误。"}
		return {"ok": true, "account_id": "account-" + str(body.username), "access_token": "isolated-startup-session"}
	if path == "/v1/rpc" and body.get("action") == "profile":
		return {"ok": true, "account_id": account_id, "profile": {"public_id": "STARTUP-QA", "display_name": "隔离登录账号"}, "editable_fields": {}}
	if path == "/v1/rpc" and body.get("action") == "snapshot":
		return {"ok": true, "account_id": account_id, "inventory_complete": true, "inventory": {}, "revision": 1}
	return {"ok": false, "account_id": account_id, "code": "unavailable"}
