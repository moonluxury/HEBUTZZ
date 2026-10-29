extends SceneTree
const Fixture = preload("res://tools/fixtures/wallet_provider.gd")
var failures := 0
var assertions := 0
var store: Node
var backend: Node
var profile: Node

func _init() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)

func calls(action: String) -> int:
	return backend.calls.filter(func(row): return row.action == action).size()

func frames() -> void:
	for i in 5: await process_frame

func login(account := "wallet-test-a") -> void:
	backend.actor = account
	profile.use_provider(backend, {"state": "authenticated", "account_id": account})
	await frames()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check-"):
		quit(2)
		return
	await frames()
	profile = root.get_node("ProfileStore")
	backend = Fixture.new()
	root.add_child(backend)
	store = root.get_node("AppServices").wallet_store()
	store.set_process(false) # Exercise explicit focus/time transitions deterministically.
	store.activate(true)
	await login()
	store.select_package("preview-3000")
	backend.lose_create = true
	store.create_order()
	check(not store.intent.is_empty() and backend.orders.size() == 1, "Unknown submission retains its original operation")
	var intent: Dictionary = store.intent.duplicate(true)
	backend.package_rows[3].version = "v2"
	backend.package_rows[3].price_cents = 4000
	backend.package_rows[3].batteries = 3500
	store.refresh_catalog()
	check(store.confirmation_package().price_cents == 3000 and store.confirmation_package().batteries == 3000, "Unknown operation keeps its original review snapshot despite a new catalog")
	profile.use_provider(backend, {"state": "signed_out"})
	check(store.intent_snapshot.is_empty() and store.balance == null, "Logout clears the private review snapshot")
	await login()
	check(store.intent.is_empty() and not store.current_order.is_empty(), "Login on an active page automatically recovers an unfinished operation")
	var id: String = store.current_order
	check(store.orders[id].request_id == intent.request_id and store.confirmation_package().price_cents == 3000, "Recovered operation shows the original order, not the default package")
	var before := calls("order")
	store._last_focus = true
	store._tick_poll(4.0, true)
	check(calls("order") == before + 1, "Focused payment state queries at a bounded interval")
	before = calls("order")
	store._tick_poll(200.0, false)
	check(calls("order") == before, "Background application does not poll")
	backend.settle(id, false)
	store._tick_poll(0.01, true)
	check(store.orders[id].credit_status == "pending" and store.balance == 1280, "Returning from payment queries the same paid-but-uncredited order")
	backend.settle(id)
	store._tick_poll(60.0, true)
	check(store.balance == 4280 and store.orders[id].credit_status == "credited", "Authoritative credit refreshes the current balance")
	before = calls("order")
	store._tick_poll(500.0, true)
	check(calls("order") == before, "Completed orders stop routine polling")
	store.select_package("preview-300")
	store.create_order()
	id = store.current_order
	backend.orders[id].payment_status = "closed"
	backend.orders[id].revision += 1
	store.query_order(id)
	backend.settle(id)
	store._last_focus = false
	store._tick_poll(0.01, true)
	check(store.orders[id].credit_status == "credited" and store.balance == 4580, "A late authoritative payment replaces a closed hint on return")
	store.select_package("preview-600")
	backend.corrupt_created_price = true
	store.create_order()
	check(not store.intent.is_empty() and backend.orders.size() == 3, "Unexpected response price never opens a changed payment target")
	backend.corrupt_created_price = false
	store.create_order()
	check(store.intent.is_empty() and backend.orders.size() == 3, "Retry after an invalid receipt reuses the same operation")
	id = store.current_order
	var other: Dictionary = backend.execute(backend.actor, "create_order", {"request_id": "other-device", "package_id": "preview-300", "package_version": "v1", "channel": "test-wechat"}).order
	store.merge_order(other)
	store.watch_order(other.id)
	before = calls("order")
	store._tick_poll(4.0, true)
	check(calls("order") == before + 1 and backend.calls[-1].payload.order_id == other.id, "Viewing a history order follows that order, not another current order")
	store.watch_order("")
	check(store.poll_target() == id, "Closing detail restores the original pending order target")
	store._polls = 12
	before = calls("order")
	store._tick_poll(1000.0, true)
	check(calls("order") == before, "Polling stops after the bounded attempt budget")
	store.activate(false)
	store._polls = 0
	store._tick_poll(1000.0, true)
	check(calls("order") == before, "Leaving the page stops all UI polling")
	store.activate(true)
	backend.delay = 0.06
	store.query_order(id)
	await login("wallet-test-b")
	await create_timer(0.12).timeout
	backend.delay = 0
	check(store.orders.is_empty() and store.balance == 17, "Delayed order and catalog responses cannot cross account boundaries")
	await login()
	var config: Dictionary = backend.execute(backend.actor, "catalog", {})
	config.preview = "true"
	check(not store._catalog(config), "A non-boolean preview flag cannot enable a catalog")
	config = backend.execute(backend.actor, "catalog", {})
	config.rules.quiz = "invalid"
	check(not store._catalog(config), "Malformed reward rules cannot become client capabilities")
	store.activate(false)
	print("WALLET RECOVERY ASSERTIONS: %d; FAILURES: %d" % [assertions, failures])
	print("WORKBENCH CHECKS: PASS" if failures == 0 else "WORKBENCH CHECKS: FAIL")
	quit(0 if failures == 0 else 1)
