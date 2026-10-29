extends "res://scripts/backend_provider.gd"
## No network: exercise the real login/store/UI against deterministic auth responses.
var login_calls := 0
var resume_calls := 0
var resume_error := ""
var mismatched_owner := false
var response_delay := 0.04

func _request(path: String, body: Dictionary, authenticated := true, credential: Dictionary = {}) -> Dictionary:
	var owner := str(credential.get("account_id", account_id))
	if path in ["/v1/auth/login", "/v1/auth/register"]:
		login_calls += 1
		if body.password != "fixture-password-123": return {"ok": false, "code": "invalid_credentials", "message": "用户名或密码不正确。"}
		var user := str(body.username).to_lower()
		return {"ok": true, "account_id": "account-" + user, "access_token": "fixture-session-" + user, "expires_at": "2099-01-01T00:00:00+00:00"}
	if path in ["/v1/auth/logout", "/v1/auth/password"]:
		return {"ok": true, "account_id": owner}
	if path == "/v1/rpc":
		if not credential.is_empty():
			resume_calls += 1
			await get_tree().create_timer(response_delay).timeout
			if not resume_error.is_empty():
				return {"ok": false, "account_id": owner, "code": resume_error,
					"http_status": 401 if resume_error == "unauthenticated" else 0, "message": "网络暂不可用，请重试。"}
			if credential.access_token != "fixture-session-" + owner.trim_prefix("account-"):
				return {"ok": false, "account_id": owner, "code": "unauthenticated", "http_status": 401}
			if mismatched_owner: owner = "account-unexpected"
		match str(body.get("action", "")):
			"profile": return {"ok": true, "account_id": owner, "profile": {"public_id": "id-" + owner, "display_name": owner}, "editable_fields": {}}
			"snapshot": return {"ok": true, "account_id": owner, "inventory_complete": true, "inventory": {}, "revision": 1}
	return {"ok": false, "account_id": owner, "code": "unavailable"}
