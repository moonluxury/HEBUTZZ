extends SceneTree
const Transport = preload("res://scripts/wallet_http_transport.gd")
var failures := 0
var assertions := 0
var cancelled := false
var transport: Node
var actor := "wallet-test-a"
var token := "isolated-account-a"

func _init() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func _cancel_probe() -> void:
	var response: Dictionary = await transport.wallet_request("slow", {})
	cancelled = not response.ok and response.code == "unknown"

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check-") or OS.get_environment("WALLET_TEST_PORT").is_empty():
		quit(2)
		return
	transport = Transport.new()
	root.add_child(transport)
	transport.response_account = func(): return actor
	var result: Dictionary = await transport.wallet_request("balance", {})
	check(not result.ok and result.code == "unavailable", "Unconfigured transport remains unavailable")
	transport.endpoint = "http://127.0.0.1:" + OS.get_environment("WALLET_TEST_PORT")
	transport.authorization = func(): return PackedStringArray(["Authorization: Bearer " + token])
	result = await transport.wallet_request("balance", {})
	check(not result.ok, "Cleartext requires explicit isolated loopback opt-in")
	transport.allow_loopback_test = true
	result = await transport.wallet_request("balance", {})
	check(result.ok and result.account_id == actor and result.balance == 1280, "Actual HTTP JSON reads the fixture SQLite balance")
	result = await transport.wallet_request("catalog", {})
	check(result.ok and result.packages.size() == 4 and result.preview, "Catalog preserves explicit fixture isolation")
	var payload := {"request_id": "http-retry", "package_id": "preview-600", "package_version": "v1", "channel": "sandbox"}
	result = await transport.wallet_request("create_order", payload)
	check(result.ok and result.order.payment_status == "pending", "HTTP creates only an unpaid order")
	var id: String = result.order.id
	result = await transport.wallet_request("create_order", payload)
	check(result.ok and result.order.id == id, "HTTP retry preserves server idempotency")
	var changed := payload.duplicate(true)
	changed.package_id = "preview-300"
	result = await transport.wallet_request("create_order", changed)
	check(not result.ok and result.code == "conflict", "Same key with changed payload is rejected over HTTP")
	result = await transport.wallet_request("order", {"order_id": id})
	check(result.ok and result.order.credit_status == "none", "Query cannot credit the SQLite wallet")
	actor = "wallet-test-b"
	token = "isolated-account-b"
	result = await transport.wallet_request("order", {"order_id": id})
	check(not result.ok and result.code == "not_found", "Server enforces authenticated order ownership")
	result = await transport.wallet_request("balance", {"account_id": "wallet-test-a"})
	check(result.ok and result.balance == 17 and result.account_id == actor, "Payload cannot override the authenticated account")
	for action in ["denied", "malformed", "reject", "redirect", "disconnect"]:
		result = await transport.wallet_request(action, {})
		check(not result.ok, "Transport does not manufacture success for " + action)
		if action == "denied": check(result.code == "unauthenticated", "401 uses the existing authentication recovery")
	_cancel_probe()
	await create_timer(0.05).timeout
	transport.wallet_cancel_requests()
	await process_frame
	check(cancelled and transport.pending.is_empty(), "Cancellation wakes awaiting callers and releases requests")
	transport.authorization = func(): return PackedStringArray()
	result = await transport.wallet_request("balance", {})
	check(not result.ok and result.code == "unauthenticated", "Missing credentials do not dispatch")
	print("WALLET HTTP ASSERTIONS: %d; FAILURES: %d" % [assertions, failures])
	print("WORKBENCH CHECKS: PASS" if failures == 0 else "WORKBENCH CHECKS: FAIL")
	quit(0 if failures == 0 else 1)
