extends SceneTree
const Fixture = preload("res://tools/fixtures/wallet_provider.gd")
const Amount = preload("res://scripts/battery_amount.gd")
var failures: Array[String] = []
var assertions := 0
var router: Node
var profile: Node
var store: Node
var backend: Node
var page: Node
var captures := "res://outputs/recharge-validation"

func _init() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(n := 8) -> void:
	for i in n: await process_frame

func visit(name: String) -> Node:
	router.go("res://scenes/" + name + ".tscn")
	await scene_changed
	await frames()
	return current_scene

func capture(name: String, preview := true) -> void:
	await create_timer(0.18).timeout
	if DisplayServer.get_name() == "headless": return
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	var label := Label.new()
	label.text = "实际 Godot 运行 · 隔离预览 / 非正式账号、定价与支付" if preview else "实际 Godot 运行 · 正式服务尚未接入"
	label.position = Vector2(322, 6)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("#092C87"))
	layer.add_child(label)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(captures.path_join(name + ".png"))
	var active_dialog: Window = page.get("dialog")
	if is_instance_valid(active_dialog):
		await RenderingServer.frame_post_draw
		active_dialog.get_texture().get_image().save_png(captures.path_join(name + "-panel.png"))
	layer.queue_free()

func login(account := "wallet-test-a") -> void:
	backend.actor = account
	profile.use_provider(backend, {"state": "authenticated", "account_id": account})
	await frames()

func close_dialog() -> void:
	if is_instance_valid(page.dialog): page.dialog.dismiss()
	await frames()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check-"):
		quit(2)
		return
	await frames()
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	DirAccess.make_dir_recursive_absolute(captures)
	router = root.get_node("PageRouter")
	profile = root.get_node("ProfileStore")
	root.get_node("UiMotion").set_enabled(false)
	page = await visit("Recharge")
	store = get_root().get_node("AppServices").wallet_store()
	check(store.balance == null and store.packages.is_empty() and page.pay_button.disabled, "Production does not seed a balance, identity, package or payment channel")
	check(page.active_nav == "RechargeButton" and page.sidebar.get_node("RechargeButton").position.y > page.sidebar.get_node("FriendsButton").position.y, "Recharge follows Friends without rearranging existing navigation")
	check(page.balance_amount.number.text == "—" and page.estimate_value.text == "—" and page.wallet_badge.number.text == "—", "Unknown balance, shared header and estimate are never zero")
	await capture("00-unconfigured", false)
	backend = Fixture.new()
	root.add_child(backend)
	await login()
	check(store.preview and store.selected == "preview-600" and store.balance == 1280, "Isolated preview has explicit default and example identity/balance")
	check(page.package_grid.get_child_count() == 4 and page.estimate_value.text == "1,880 电池（预计）" and page.total_value.text == "¥6.00", "Two by two packages and confirmation agree")
	var icon: Texture2D = page.balance_amount.picture.texture
	check(page.sidebar.get_node("RechargeButton").get_child(0).texture == icon, "Navigation and balance reuse the same independent battery asset")
	for card in page.package_grid.get_children(): check(card.get_node("Amount").picture.texture == icon, "Each package uses the same two-cell asset")
	check(FileAccess.get_file_as_string(Amount.ICON_PATH).count("height=\"14\"") == 2, "Battery source has exactly two fixed short cells")
	check(not page.pay_button.disabled and page.account_value.text.contains("禹浩"), "Preview can create only isolated test orders")
	await capture("01-main-preview")
	store.select_package("preview-1200")
	await frames()
	check(page.total_value.text == "¥12.00" and page.estimate_value.text == "2,480 电池（预计）", "Package selection updates exact cents and expected quantity")
	backend.wallet[backend.actor] = 0
	backend.revisions[backend.actor] += 1
	store.refresh_balance()
	await frames()
	check(page.balance_amount.picture.texture == icon and page.balance_amount.number.text == "0", "Zero balance still has two cells")
	backend.fail_balance = true
	store.refresh_balance()
	await frames()
	check(store.balance == null and page.estimate_value.text == "—" and page.wallet_badge.number.text == "—" and page.pay_button.disabled, "Read failure clears the shared header and never calculates an estimate from zero")
	backend.fail_balance = false
	backend.wallet[backend.actor] = 1280
	backend.revisions[backend.actor] += 1
	store.refresh_balance()
	store.select_package("preview-600")
	await frames()
	backend.delay = 0.06
	backend.lose_create = true
	store.create_order()
	store.create_order()
	check(store.creating, "Submitting locks repeated clicks")
	await create_timer(0.1).timeout
	check(backend.orders.size() == 1 and not store.intent.is_empty(), "Lost create response retains original persisted request")
	var old_intent: Dictionary = store.intent.duplicate(true)
	store.select_package("preview-3000")
	check(store.selected == "preview-600", "Uncertain submission locks the original selection")
	store.intent = {}
	store._load_intent()
	check(store.intent == old_intent, "Restart recovery loads original account-scoped request ID")
	check(store.intent_snapshot.price_cents == 600 and store.confirmation_package().batteries == 600, "Persisted confirmation retains the original price and quantity")
	store.create_order()
	await create_timer(0.1).timeout
	backend.delay = 0
	check(backend.orders.size() == 1 and store.intent.is_empty() and not store.current_order.is_empty(), "Retry returns the original order exactly once")
	var id: String = store.current_order
	var wrong_payload := old_intent.duplicate(true)
	wrong_payload.package_id = "preview-3000"
	check(backend.execute(backend.actor, "create_order", wrong_payload).code == "conflict", "Test provider rejects same request ID with a different payload")
	check(is_instance_valid(page.dialog), "Order confirmation opens only after submission")
	check(store.poll_target() == id and store._payment_window.get_ref() == page.dialog, "The visible native payment window participates in polling focus")
	await capture("02-order-pending")
	await close_dialog()
	check(backend.orders[id].payment_status == "pending", "Closing window does not close the order")
	store.query_order(id)
	check(store.balance == 1280, "I have paid / query alone cannot credit batteries")
	backend.package_rows[1].batteries = 900
	backend.package_rows[1].price_cents = 700
	backend.package_rows[1].version = "v2"
	store.refresh_catalog()
	check(store.orders[id].batteries == 600 and store.orders[id].price_cents == 600, "Existing order keeps its snapshot after repricing")
	check(store.selected.is_empty(), "Repricing clears selection and requires review")
	await frames()
	check(page.quantity_value.text == "600 电池" and page.total_value.text == "¥6.00", "In-flight confirmation keeps the original snapshot after catalog repricing")
	backend.settle(id, false)
	store.query_order(id)
	check(store.status(store.orders[id]).contains("到账中") and store.balance == 1280, "Paid but not credited does not change available balance")
	page.show_panel("order", id)
	await capture("03-paid-pending")
	backend.settle(id)
	store.query_order(id)
	await frames()
	check(store.balance == 1880 and store.orders[id].credit_status == "credited", "Credit response rereads authoritative balance")
	var stale: Dictionary = store.orders[id].duplicate(true)
	stale.revision += 1
	stale.payment_status = "pending"
	stale.credit_status = "none"
	store.merge_order(stale)
	check(store.orders[id].credit_status == "credited", "Late pending responses cannot regress a credited order")
	await capture("04-credited")
	await close_dialog()
	for route in [["Workbench", "all"], ["SubjectSelect", "all"], ["SubjectSelect", "wrong"], ["HegongKaiwu", "all"], ["HegongKaiwuDetail", "all"], ["MyCollection", "all"], ["PersonalCenter", "all"], ["MyFriends", "all"]]:
		root.get_node("AppState").quiz_mode = route[1]
		page = await visit(route[0])
		check(page.wallet_badge.number.text == "1,880", "Shared authoritative balance is present on " + route[0] + "/" + route[1])
		if route[0] in ["Workbench", "PersonalCenter", "MyFriends"]: await capture("11-header-" + route[0])
	page = await visit("Recharge")
	page.show_panel("ledger")
	await frames()
	check(page.dialog._rows.size() == 1 and page.dialog._rows[0].order_id == id, "Ledger links to the credited order only")
	await capture("05-ledger")
	await close_dialog()
	page.show_panel("orders")
	await capture("06-orders")
	await close_dialog()
	var forbidden: Dictionary = backend.execute("wallet-test-b", "order", {"order_id": id})
	check(not forbidden.ok, "Isolated provider enforces order ownership")
	backend.delay = 0.08
	store.refresh_balance()
	backend.actor = "wallet-test-b"
	profile.use_provider(backend, {"state": "authenticated", "account_id": "wallet-test-b"})
	await create_timer(0.14).timeout
	backend.delay = 0
	check(store.account_id == "wallet-test-b" and store.balance == 17 and store.orders.is_empty(), "Late account A response cannot populate account B")
	page = await visit("Workbench")
	check(page.wallet_badge.number.text == "17", "A cached page shows the new account balance when reattached")
	page = await visit("Recharge")
	await login()
	backend.corrupt_owner = true
	store.refresh_balance()
	check(store.balance == null, "Mismatched response identity is rejected")
	backend.corrupt_owner = false
	store.refresh_balance()
	backend.channel_rows = []
	store.refresh_catalog()
	await frames()
	check(page.pay_button.disabled and store.checkout_reason().contains("渠道"), "Missing channels disable collection but not history")
	backend.channel_rows = [{"id": "test-alipay", "label": "支付宝 · 测试", "brand": "alipay", "enabled": true}]
	store.refresh_catalog()
	store.select_package("preview-300")
	backend.package_rows[0].version = "v2"
	store.create_order()
	await frames()
	check(store.selected.is_empty() and store.intent.is_empty() and store.error.contains("重新选择"), "Stale price is definitive and requires a new explicit selection")
	backend.wallet[backend.actor] = 9007199254700000
	backend.revisions[backend.actor] += 1
	backend.nickname = "这是一个需要完整换行显示的很长的中文用户名称用于核对充值账户"
	profile.refresh()
	store.refresh_balance()
	await frames()
	await capture("07-large-balance-name")
	check(page.balance_amount.number.text == "9,007,199,254,700,000", "Large balance is grouped without floating-point loss")
	root.size = Vector2i(900, 740)
	await frames(16)
	check(page.right.position.y > page.left.position.y + page.left.size.y, "Narrow viewport stacks confirmation below packages")
	await capture("08-narrow")
	page.scroll.scroll_vertical = int(page.content_height)
	await frames()
	await capture("08b-narrow-confirmation")
	root.get_node("AppState").dark_mode = true
	root.get_node("AppState").color_mode_changed.emit(true)
	await frames()
	await capture("09-dark")
	root.get_node("AppState").dark_mode = false
	root.get_node("AppState").color_mode_changed.emit(false)
	root.size = Vector2i(1600, 1000)
	await frames()
	page.pay_button.grab_focus()
	page.show_panel("rules")
	await frames()
	check(page.dialog.exclusive and page.dialog.close_button.has_focus(), "Modal has exclusive keyboard focus")
	await close_dialog()
	check(page.pay_button.has_focus(), "Closing modal restores trigger focus")
	check(not Amount.integer(1.5) and not Amount.integer(-1) and not Amount.integer("600") and not Amount.integer(INF), "Fractional, negative, string and infinite monetary quantities are rejected")
	check(Amount.money(123456) == "¥1,234.56", "Integer cents format without floating-point arithmetic")
	var original_package: Dictionary = backend.package_rows[0].duplicate(true)
	backend.package_rows[0].batteries = Amount.MAX_INTEGER
	backend.package_rows[0].price_cents = Amount.MAX_INTEGER
	backend.package_rows[0].version = "huge-test"
	store.refresh_catalog()
	store.select_package("preview-300")
	await frames()
	page.scroll.scroll_vertical = 0
	await capture("10-large-package")
	var huge_card: Button = page.package_grid.get_child(0)
	check(page.package_grid.columns == 1 and huge_card.get_node("Amount").size.x + 44 <= huge_card.size.x, "Large package quantities use one column without overflowing the card")
	check(page.pay_button.disabled and page.estimate_value.text == "—", "An overflowing expected balance cannot create an order")
	backend.package_rows[0] = original_package
	store.refresh_catalog()
	backend.quiz_enabled = true
	backend.wallet[backend.actor] = 1280
	backend.revisions[backend.actor] += 1
	# Enter Quiz before the authenticated catalog has returned, then answer early.
	backend.delay = 0.25
	profile.use_provider(backend, {"state": "authenticated", "account_id": backend.actor})
	root.get_node("AppState").subject_id = "marxism"
	root.get_node("AppState").quiz_mode = "all"
	root.get_node("AppState").start_index = 0
	page = await visit("Quiz")
	check(not store.active, "Leaving recharge stops its polling")
	var q: Dictionary = page.questions[page.current_index]
	for index in page.shuffled_options.size():
		if page.shuffled_options[index].get("correct", false): page.selected_indices.append(index)
	page._reveal_answer()
	await create_timer(0.85).timeout
	backend.delay = 0
	check(page.result_label.text.contains("获得 5 电池") and store.balance == 1285, "Actual quiz sends selected keys to an issued attempt and displays confirmed reward")
	check(page.minimal_view.wallet_badge.number.text == "1,285", "Quiz reward also updates the shared header balance")
	await capture("11-header-Quiz")
	page._refresh_answer_feedback()
	check(page.result_label.text.count("获得 5 电池") == 1, "Repainting the answer retains one confirmed reward message")
	var aid: String = page.wallet_bridge.attempt_id
	var answer: Dictionary = page.wallet_bridge.pending_answer
	await store.submit_quiz(aid, answer)
	check(store.balance == 1285, "Retrying the same server-issued attempt does not repeat the reward")
	var forged: Dictionary = await store.request("quiz_submit", {"attempt_id": "fabricated", "correct": true, "amount": 999})
	check(not forged.ok and store.balance == 1285, "Client-reported correctness is not a reward path")
	page = await visit("Recharge")
	profile.use_provider(backend, {"state": "signed_out"})
	await frames()
	check(store.balance == null and store.orders.is_empty() and store.intent.is_empty(), "Logout clears private client state")
	print("RECHARGE ASSERTIONS: %d; FAILURES: %d" % [assertions, failures.size()])
	print("WORKBENCH CHECKS: PASS" if failures.is_empty() else "WORKBENCH CHECKS: FAIL")
	quit(0 if failures.is_empty() else 1)
