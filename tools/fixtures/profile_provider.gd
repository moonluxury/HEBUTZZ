extends "res://tools/fixtures/collection_provider.gd"
## Never loaded by production. All data and persistence belong to an isolated runner.
var profile_delay := 0.0
var save_delay := 0.0
var action_delay := 0.0
var profile_fail := false
var save_fail := false
var logout_fail := false
var malformed_save := false
var wrong_avatar_response := false
var last_avatar_id := ""
var avatar_operations: Dictionary = {}
var unknown_after_save := false
var unknown_before_save := false
var login_delay := 0.0
var login_result := "cancel"
var login_account := "test-account-a"
var saves := 0
var logouts := 0
var accounts: Dictionary = {}
var permissions := {"display_name": {"max_length": 80}, "bio": {"max_length": 600}, "college": {}, "major": {}, "grade": {}, "avatar_card_id": {"reset_supported": true}}

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("workbench-check"))
	accounts = {
		"test-account-a": {"public_id": "TEST-2026-000001", "display_name": "测试同学", "school": "测试大学", "college": "测试学院", "major": "测试专业", "grade": "测试年级", "bio": "喜欢探索，也在认真记录每一天的学习。", "avatar_card_id": ""},
		"test-account-b": {"public_id": "TEST-2026-000002", "display_name": "另一位测试同学"},
	}

func profile_response(account: String) -> Dictionary:
	return {"ok": true, "account_id": account, "profile": accounts.get(account, {}).duplicate(true), "editable_fields": permissions.duplicate(true)}

func request_profile(account: String) -> Dictionary:
	var response := profile_response(account)
	if profile_delay > 0:
		await get_tree().create_timer(profile_delay).timeout
	return {"ok": false, "account_id": account, "message": "隔离测试：资料读取失败。"} if profile_fail else response

func save_profile(account: String, patch: Dictionary, avatar_card_id: String, reset_avatar := false) -> Dictionary:
	saves += 1
	last_avatar_id = avatar_card_id
	if save_delay > 0:
		await get_tree().create_timer(save_delay).timeout
	if save_fail:
		return {"ok": false, "account_id": account, "message": "隔离测试：服务器拒绝保存。"}
	var next: Dictionary = accounts[account].duplicate(true)
	next.merge(patch, true)
	if not avatar_card_id.is_empty() or reset_avatar:
		if not permissions.has("avatar_card_id") or (not avatar_card_id.is_empty() and (not inventory.has(avatar_card_id) or int(inventory[avatar_card_id].count) <= 0)):
			return {"ok": false, "account_id": account, "message": "隔离测试：尚未拥有这张卡，不能用作头像。"}
		next.avatar_card_id = avatar_card_id
	var file := FileAccess.open("user://profile-test-" + account + ".json", FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "隔离测试：资料持久化失败。"}
	file.store_string(JSON.stringify(next))
	file.close()
	accounts[account] = next
	var response := profile_response(account)
	response.persisted = not malformed_save
	if wrong_avatar_response:
		response.profile.avatar_card_id = "0007"
	return response

func save_avatar(account: String, card_id: String, operation_id: String) -> Dictionary:
	var key := account + ":" + operation_id
	if avatar_operations.has(key):
		return avatar_operations[key].duplicate(true)
	if unknown_before_save:
		return {"ok": false, "account_id": account, "code": "unknown"}
	var response: Dictionary = await save_profile(account, {}, card_id, card_id.is_empty())
	if response.get("ok", false) and response.get("persisted", false):
		avatar_operations[key] = response.duplicate(true)
	if unknown_after_save: return {"ok": false, "account_id": account, "code": "unknown"}
	return response

func begin_avatar_login(flow: String) -> Dictionary:
	var profile := get_node("/root/ProfileStore")
	var generation: int = profile.epoch
	if login_delay > 0: await get_tree().create_timer(login_delay).timeout
	if generation != profile.epoch:
		return {"ok": false, "message": "账号已改变。"}
	if login_result != "success":
		return {"ok": false, "message": "已取消登录。" if login_result == "cancel" else "登录失败，请重试。"}
	profile.use_provider(self, {"state": "authenticated", "account_id": login_account}, self)
	return {"ok": true, "account_id": login_account, "avatar_login_context": flow, "session_epoch": profile.epoch}

func request_account(account: String) -> Dictionary:
	return {"ok": true, "account_id": account, "login_method": "测试统一身份认证", "masked_email": "t***@example.invalid", "masked_phone": "13800138000", "password": "must-never-render", "token": "must-never-render"}

func logout(account: String) -> Dictionary:
	logouts += 1
	if action_delay > 0:
		await get_tree().create_timer(action_delay).timeout
	return {"ok": not logout_fail, "account_id": account, "message": "隔离测试：退出失败。" if logout_fail else ""}
