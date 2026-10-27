extends "res://tools/fixtures/collection_provider.gd"
## Never loaded by production. All data and persistence belong to an isolated runner.
var profile_delay := 0.0
var save_delay := 0.0
var action_delay := 0.0
var profile_fail := false
var save_fail := false
var logout_fail := false
var malformed_save := false
var saves := 0
var logouts := 0
var accounts: Dictionary = {}
var permissions := {"display_name": {"max_length": 80}, "bio": {"max_length": 600}, "college": {}, "major": {}, "grade": {}, "avatar": {"extensions": ["png", "jpg"], "max_bytes": 1048576}}

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("workbench-check"))
	accounts = {
		"test-account-a": {"public_id": "TEST-2026-000001", "display_name": "测试同学", "school": "测试大学", "college": "测试学院", "major": "测试专业", "grade": "测试年级", "bio": "喜欢探索，也在认真记录每一天的学习。", "avatar": ""},
		"test-account-b": {"public_id": "TEST-2026-000002", "display_name": "另一位测试同学"},
	}

func profile_response(account: String) -> Dictionary:
	return {"ok": true, "account_id": account, "profile": accounts.get(account, {}).duplicate(true), "editable_fields": permissions.duplicate(true)}

func request_profile(account: String) -> Dictionary:
	var response := profile_response(account)
	if profile_delay > 0:
		await get_tree().create_timer(profile_delay).timeout
	return {"ok": false, "account_id": account, "message": "隔离测试：资料读取失败。"} if profile_fail else response

func save_profile(account: String, patch: Dictionary, avatar_file: String) -> Dictionary:
	saves += 1
	if save_delay > 0:
		await get_tree().create_timer(save_delay).timeout
	if save_fail:
		return {"ok": false, "account_id": account, "message": "隔离测试：服务器拒绝保存。"}
	var next: Dictionary = accounts[account].duplicate(true)
	next.merge(patch, true)
	if not avatar_file.is_empty():
		var persisted := "user://profile-avatar-" + str(saves) + ".png"
		if Image.load_from_file(avatar_file).save_png(persisted) != OK:
			return {"ok": false, "message": "隔离测试：头像持久化失败。"}
		next.avatar = persisted
	var file := FileAccess.open("user://profile-test-" + account + ".json", FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "隔离测试：资料持久化失败。"}
	file.store_string(JSON.stringify(next))
	file.close()
	accounts[account] = next
	var response := profile_response(account)
	response.persisted = not malformed_save
	return response

func request_account(account: String) -> Dictionary:
	return {"ok": true, "account_id": account, "login_method": "测试统一身份认证", "masked_email": "t***@example.invalid", "masked_phone": "13800138000", "password": "must-never-render", "token": "must-never-render"}

func logout(account: String) -> Dictionary:
	logouts += 1
	if action_delay > 0:
		await get_tree().create_timer(action_delay).timeout
	return {"ok": not logout_fail, "account_id": account, "message": "隔离测试：退出失败。" if logout_fail else ""}
