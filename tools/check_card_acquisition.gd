extends SceneTree
const Fixture = preload("res://tools/fixtures/card_draw_provider.gd")
const DrawStore = preload("res://scripts/card_draw_store.gd")
const Reveal = preload("res://scripts/card_reveal.gd")
var failures: Array[String] = []
var assertions := 0
var page: Node
var api: Node
var profile: Node
var draws: Node
var wallet: Node
var motion: Node
var output := "res://outputs/card-acquisition-validation"

class StorageFailure extends DrawStore:
	func _persist(_value: Dictionary) -> bool: return false

func _init() -> void: _run.call_deferred()
func pause(seconds := 0.25) -> void: await create_timer(seconds).timeout
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures.append(message); push_error(message)

func key(code: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	root.push_input(event, true)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func open() -> Node:
	page.acquire_button.pressed.emit()
	await pause()
	return page.acquisition

func result_ready(dialog: Node) -> void:
	for i in 300:
		if dialog.state == "result": return
		if dialog.state == "revealing" and dialog.preview.state in ["ready", "revealing"]:
			key(KEY_SPACE, true)
			key(KEY_SPACE, false)
		await process_frame
	check(false, "Acquisition result finishes loading")

func login(owner: String) -> void:
	api.actor = owner
	profile.use_provider(api, {"state": "authenticated", "account_id": owner})
	await pause()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await pause()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(2560, 1680)
	root.size = Vector2i(1624, 946)
	if DisplayServer.get_name() != "headless": root.unfocusable = true; root.position = Vector2i(-10000, -10000)
	DirAccess.make_dir_recursive_absolute(output)
	profile = root.get_node("ProfileStore")
	motion = root.get_node("UiMotion")
	api = Fixture.new()
	root.add_child(api)
	await login(Fixture.A)
	root.get_node("PageRouter").go("res://scenes/MyCollection.tscn")
	await scene_changed
	page = current_scene
	draws = page.draw_store
	wallet = root.get_node("AppServices").wallet_store()
	await pause()
	check(page.acquire_button.text == "获取卡牌" and page.acquire_price.text == "200 电池/次", "Collection has the requested action and visible price")
	check(page.acquire_price.get_theme_color("font_color") == page.muted_color, "Price annotation uses the existing muted text color")
	await capture("01-collection-entry")
	var dialog := await open()
	check(dialog.state == "ready" and api.draw_calls.is_empty() and api.balances[Fixture.A] == 1000, "Opening P2 does not spend batteries")
	check(dialog.back.texture.resource_path == page.store.seasons[0].back_image and not dialog.preview.visible, "Waiting screen uses the current complete card back")
	check(not dialog.details.visible, "Card identity and result controls stay hidden before opening")
	await capture("02-waiting-card-back")
	key(KEY_SPACE, true)
	key(KEY_SPACE, false)
	check(api.draw_calls.is_empty(), "Space before opening cannot trigger a paid action")
	dialog.dismiss()
	await pause()
	check(api.draw_calls.is_empty() and page.acquire_button.has_focus(), "Cancelling the waiting screen is free and restores collection focus")
	dialog = await open()
	motion.suspended = false
	motion.system_reduced = 0
	motion.set_enabled(true)
	dialog.hit.pressed.emit()
	dialog.hit.pressed.emit()
	check(api.draw_calls.size() == 1 and draws.busy, "Double clicking a card dispatches one saved operation")
	await pause(0.18)
	check(draws.ready_result() and api.grants == 1 and api.balances[Fixture.A] == 800, "A confirmed draw spends exactly 200 and grants one card")
	check(wallet.balance == 800 and page.store.count("0004") == 1, "Wallet badge and collection adopt the same authoritative response")
	check(dialog.preview.get_script() == Reveal and not dialog.return_button.is_visible_in_tree(), "The existing reveal timeline owns the result presentation")
	for i in 200:
		if dialog.preview.state != "loading": break
		await process_frame
	dialog.preview._kill_tween()
	dialog.preview._set_elapsed(Reveal.ENTRY + 0.79)
	await capture("03-existing-opening-animation")
	key(KEY_SPACE, true)
	check(dialog.state == "result" and dialog.details.visible and not dialog.return_button.disabled, "Space skips to the revealed card, text and return button")
	key(KEY_SPACE, true, true)
	key(KEY_SPACE, false)
	check(is_instance_valid(page.acquisition) and api.grants == 1, "Held Space and release cannot return early or draw again")
	check(dialog.name_label.text == page.store.card("0004").name, "The revealed name comes from the actual returned card ID")
	await capture("04-card-result")
	dialog.hit.pressed.emit()
	await pause()
	check(not is_instance_valid(page.acquisition) and not page.in_detail and draws.operation.is_empty(), "Clicking the revealed card returns to collection and acknowledges the result")
	await capture("05-returned-collection")
	api.lose_draw_response = true
	dialog = await open()
	dialog.hit.pressed.emit()
	await pause()
	var original: String = draws.operation.id
	check(draws.operation.state == "unknown" and api.grants == 2 and not dialog.preview.visible, "A lost response is not presented as success or replaced with a new draw")
	dialog.dismiss()
	await pause()
	draws.queue_free()
	await pause()
	draws = root.get_node("AppServices").card_draw_store()
	page.draw_store = draws
	api.miss_status = true
	dialog = await open()
	check(draws.operation.id == original and draws.operation.state == "unknown", "Restart restores the same request even if status has not arrived")
	api.miss_status = false
	dialog.hit.pressed.emit()
	await pause()
	await result_ready(dialog)
	check(api.draw_calls[-1].operation_id == original and api.grants == 2 and wallet.balance == 600, "Retry uses the original operation and does not charge twice")
	dialog.return_button.pressed.emit()
	await pause()
	api.invalid_receipt = true
	dialog = await open()
	dialog.hit.pressed.emit()
	await pause()
	check(draws.operation.state == "unknown" and not dialog.preview.visible, "Unknown card IDs cannot become a fabricated successful result")
	api.invalid_receipt = false
	draws.recover()
	await pause()
	await result_ready(dialog)
	dialog.dismiss()
	await pause()
	var saved_calls: int = api.draw_calls.size()
	var failure := StorageFailure.new()
	root.add_child(failure)
	failure.options = draws.options.duplicate(true)
	failure.acquire()
	check(api.draw_calls.size() == saved_calls, "Storage failure prevents an unrecorded paid request")
	failure.queue_free()
	dialog = await open()
	dialog.hit.pressed.emit()
	await login(Fixture.B)
	check(not is_instance_valid(page.acquisition) and wallet.account_id == Fixture.B and wallet.balance == 600, "Switching accounts closes the old screen and rejects its late wallet response")
	await login(Fixture.A)
	dialog = await open()
	await result_ready(dialog)
	check(api.grants == 4 and wallet.balance == 200, "Returning to the original account recovers its already-paid card")
	dialog.dismiss()
	await pause()
	api.balances[Fixture.A] = 199
	api.wallet_revisions[Fixture.A] += 1
	wallet.refresh_balance()
	dialog = await open()
	dialog.hit.pressed.emit()
	await pause()
	check(draws.operation.state == "failed" and api.grants == 4 and wallet.balance == 199 and dialog.hint.text.contains("电池不足"), "Insufficient balance keeps the back visible and never grants a card")
	await capture("06-insufficient-batteries")
	root.size = Vector2i(900, 620)
	await pause()
	check(root.get_visible_rect().encloses(dialog.stage.get_global_rect()), "Opening and result controls remain within a small window")
	await capture("07-small-window")
	dialog.dismiss()
	await pause()
	check(page.find_children("*", "CanvasLayer", true, false).is_empty(), "Returning leaves no modal input layer")
	var saved_path: String = draws._path()
	var original_save := FileAccess.get_file_as_bytes(saved_path)
	var broken := FileAccess.open(saved_path, FileAccess.WRITE)
	broken.store_string("{broken card draw record")
	broken.close()
	draws.queue_free()
	await pause()
	draws = root.get_node("AppServices").card_draw_store()
	page.draw_store = draws
	var calls_before_corruption: int = api.draw_calls.size()
	dialog = await open()
	check(dialog.hit.disabled and dialog.hint.text.contains("原文件已保留"), "A damaged intent file visibly disables spending")
	dialog.hit.pressed.emit()
	check(api.draw_calls.size() == calls_before_corruption and FileAccess.get_file_as_string(saved_path).begins_with("{broken"), "Damaged intent data is never overwritten or charged")
	dialog.dismiss()
	await pause()
	var restore := FileAccess.open(saved_path, FileAccess.WRITE)
	restore.store_buffer(original_save)
	restore.close()
	print("CARD ACQUISITION ASSERTIONS: %d (isolated wallet/inventory only)" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
