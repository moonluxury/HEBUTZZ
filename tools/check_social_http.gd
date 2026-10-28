extends SceneTree
const Transport = preload("res://scripts/social_http_transport.gd")
var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check") or OS.get_environment("SOCIAL_TEST_PORT").is_empty():
		quit(2)
		return
	var transport := Transport.new()
	root.add_child(transport)
	transport.response_account = func(): return "http-test-account"
	var result: Dictionary = await transport.social_request("sync", {})
	check(not result.ok and result.code == "unavailable", "Missing transport configuration is unavailable")
	transport.endpoint = "http://127.0.0.1:" + OS.get_environment("SOCIAL_TEST_PORT")
	transport.authorization = func(): return PackedStringArray(["Authorization: Bearer isolated-not-a-real-key"])
	result = await transport.social_request("sync", {})
	check(not result.ok, "Cleartext transport is disabled unless explicitly in loopback test mode")
	transport.allow_loopback_test = true
	result = await transport.social_request("sync", {"cursor": "known-cursor"})
	check(result.ok and result.account_id == "http-test-account" and result.get("cursor") == "known-cursor", "Real HTTP request and JSON envelope reach loopback service")
	result = await transport.social_request("denied", {})
	check(not result.ok and result.code == "unauthenticated", "HTTP 401 enters existing login recovery")
	result = await transport.social_request("malformed", {})
	check(not result.ok and result.code == "unknown", "Malformed response never becomes local success")
	result = await transport.social_request("reject", {})
	check(not result.ok and result.code == "forbidden", "Structured HTTP rejection retains actual business failure")
	result = await transport.social_request("redirect", {})
	check(not result.ok, "Credential-bearing requests never follow redirects")
	transport.authorization = func(): return PackedStringArray()
	result = await transport.social_request("sync", {})
	check(not result.ok and result.code == "unauthenticated", "Missing credentials cannot dispatch")
	print("HTTP TRANSPORT ASSERTIONS: 8 (isolated loopback server)")
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
