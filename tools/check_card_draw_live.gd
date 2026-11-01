extends SceneTree
var assertions := 0
var failures: Array[String] = []

func _init() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); push_error(label)

func until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	check(condition.call(), "Real HTTPS operation completes within its deadline")

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check") or OS.get_environment("HEGONG_DRAW_LIVE_TEST") != "1" or not OS.get_environment("HEGONG_DRAW_TEST_USERNAME").begins_with("drawcheck_"):
		quit(2); return
	await process_frame
	var api := root.get_node("BackendProvider")
	api.base_url = "https://39.107.44.18"
	check(api.accept_session({"ok": true, "account_id": OS.get_environment("HEGONG_DRAW_TEST_ACCOUNT"), "access_token": OS.get_environment("HEGONG_DRAW_TEST_TOKEN")}), "Attach only the temporary HTTPS-created account")
	for name in ["HEGONG_DRAW_TEST_TOKEN", "HEGONG_DRAW_TEST_ACCOUNT", "HEGONG_DRAW_TEST_USERNAME"]: OS.unset_environment(name)
	root.get_node("PageRouter").go("res://scenes/MyCollection.tscn")
	await scene_changed
	var page: Node = current_scene
	var store: Node = page.draw_store
	var wallet: Node = root.get_node("AppServices").wallet_store()
	await until(func(): return wallet.balance != null and page.store.inventory_known)
	check(wallet.balance == 400 and page.store.summary().total == 0, "The test account starts with isolated funds and no cards")
	page.acquire_button.pressed.emit()
	await until(func(): return not store.options.is_empty())
	check(store.options.price == 200 and store.options.odds.size() == 7, "Godot receives the deployed price and seven-card pool")
	var dialog: Node = page.acquisition
	dialog.hit.pressed.emit()
	await until(func(): return store.ready_result() or not store.busy)
	check(store.ready_result(), "The real draw receipt is accepted by the client")
	if not store.ready_result(): quit(1); return
	var card_id: String = store.operation.receipt.card_id
	check(wallet.balance == 200 and page.store.count(card_id) == 1 and page.store.summary().total == 1, "Real balance and inventory update together in the PC client")
	await until(func(): return dialog.preview.state != "loading")
	dialog.preview.skip()
	check(dialog.state == "result" and dialog.name_label.text == page.store.card(card_id).name and dialog.return_button.is_visible_in_tree(), "The actual card uses the existing reveal and visible result controls")
	dialog.return_button.pressed.emit()
	await process_frame
	check(not is_instance_valid(page.acquisition) and store.operation.is_empty(), "Returning to collection finishes the paid operation")
	print("LIVE CARD DRAW ASSERTIONS: %d (temporary account only)" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
