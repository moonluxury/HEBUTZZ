extends SceneTree
const Fixture = preload("res://tools/fixtures/social_provider.gd")
const Actions = preload("res://scripts/conversation_actions_dialog.gd")
var assertions := 0
var failures: Array[String] = []
var page: Node
var social: Node
var backend: Node
var profile: Node
var motion: Node
var cid := ""
var output := "res://outputs/conversation-actions-validation"

func _init() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); push_error(message)

func pause(seconds := 0.24) -> void: await create_timer(seconds).timeout

func key(code: Key, shift := false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		event.shift_pressed = shift
		root.push_input(event)

func click(point: Vector2) -> void:
	var movement := InputEventMouseMotion.new()
	movement.position = point
	root.push_input(movement, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func open() -> Node:
	page.more_button.grab_focus()
	page.more_button.pressed.emit()
	await pause()
	return page.dialog

func labels(node: Node) -> String:
	var result := ""
	for label in node.find_children("*", "Label", true, false): result += label.text + "\n"
	return result

func capture(dialog: Node, name: String, corners := false) -> void:
	if DisplayServer.get_name() == "headless": return
	await pause()
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png(output.path_join(name + ".png"))
	if dialog == null: return
	var rect := Rect2i(root.get_stretch_transform() * dialog.panel.get_global_rect())
	picture.get_region(rect.grow(12).intersection(Rect2i(Vector2i.ZERO, picture.get_size()))).save_png(output.path_join(name + "-dialog.png"))
	if not corners: return
	dialog.panel.hide()
	await RenderingServer.frame_post_draw
	var background := root.get_texture().get_image()
	dialog.panel.show()
	for corner in [rect.position, rect.position + Vector2i(rect.size.x - 1, 0), rect.end - Vector2i.ONE, rect.position + Vector2i(0, rect.size.y - 1)]:
		var actual := picture.get_pixelv(corner)
		var expected := background.get_pixelv(corner)
		check(absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b) < 0.06, "Actual composited corner exposes the same shaded background: " + str(corner))

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await pause()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(2560, 1680)
	root.size = Vector2i(1624, 946) # The reference's client area below the native title bar.
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	DirAccess.make_dir_recursive_absolute(output)
	motion = root.get_node("UiMotion")
	motion.set_enabled(false)
	profile = root.get_node("ProfileStore")
	root.get_node("PageRouter").go("res://scenes/MyFriends.tscn")
	await scene_changed
	page = current_scene
	social = root.get_node("AppServices").social_store()
	backend = Fixture.new()
	root.add_child(backend)
	profile.use_provider(backend, {"state": "authenticated", "account_id": Fixture.A})
	await pause()
	cid = backend.pair(Fixture.A, Fixture.B)
	page._select(cid)
	await pause()
	var baseline_stock: Dictionary = backend.stocks.duplicate(true)
	var dialog := await open()
	check(dialog.get_script() == Actions and not dialog is Window, "The real ellipsis opens an in-scene modal, never a native window")
	check(dialog.rows.size() == 6, "Exactly six P3 rows")
	for item in Actions.ITEMS:
		check(dialog.rows[item.id].caption.text == item.title and dialog.rows[item.id].description.text == item.subtitle, "Exact P3 copy: " + item.id)
		check(dialog.rows[item.id].frame.bg_color == Color.WHITE, "Initial row has no selected highlight: " + item.id)
	check(root.gui_get_focus_owner() == dialog.shade, "Initial focus does not select any row")
	check(dialog.panel.size == Actions.BASE and dialog.panel.scale.x > 1, "Reference proportions follow the production viewport scale")
	check(not labels(dialog).contains("免打扰") and not labels(dialog).contains("举报"), "No replaced or additional menu rows")
	await capture(dialog, "01-p3-default", true)
	key(KEY_TAB)
	check(root.gui_get_focus_owner() == dialog.rows.profile, "Tab reaches the first row")
	for index in 6: key(KEY_TAB)
	check(root.gui_get_focus_owner() == dialog.close_button, "Tab includes close after six actions")
	key(KEY_TAB)
	check(root.gui_get_focus_owner() == dialog.rows.profile, "Keyboard focus is trapped within the modal")
	key(KEY_ENTER)
	await pause()
	check(dialog.panel_mode == "profile" and labels(dialog).contains("QA-000002"), "Enter opens the correct contact's public profile")
	check(not labels(dialog).contains("test-account-b"), "Profile never renders the private account key")
	dialog._switch("peer_menu")
	await pause()
	var pointer := InputEventMouseMotion.new()
	pointer.position = dialog.rows.remark.get_global_rect().get_center()
	root.push_input(pointer, true)
	await pause()
	check(dialog.rows.remark.is_hovered(), "Pointer enters the entire remark row")
	await capture(dialog, "02-p3-hover")
	click(dialog.rows.remark.get_global_rect().position + Vector2(4, 4))
	await pause()
	check(dialog.panel_mode == "remark", "The entire row, not only the arrow, activates")
	check(page.find_children("ConversationModalShade", "ColorRect", true, false).size() == 1, "Secondary forms reuse exactly one mask")
	dialog.query.text = "我的备注"
	backend.fail_action = "preferences"
	dialog._save_remark()
	await pause()
	check(dialog.query.text == "我的备注" and not dialog.busy and not dialog.status.text.is_empty(), "Failed saving preserves input and enables retry")
	check(social.peer(Fixture.B).get("remark", "") == "", "Failed saving does not optimistically alter the contact")
	backend.fail_action = ""
	backend.delay = 0.12
	dialog._save_remark()
	dialog._save_remark()
	check(dialog.busy and not dialog.query.editable, "Duplicate submission is locked while waiting for the service")
	await pause()
	backend.delay = 0
	check(social.peer(Fixture.B).remark == "我的备注" and page.chat_name.text == "我的备注", "Successful service response updates the list and conversation name")
	check(backend.users[Fixture.B].name == "隔离账号乙", "Remark does not change the peer's actual name")
	dialog._switch("marks")
	await pause()
	check(dialog.confirmation.disabled and labels(dialog).contains("尚未接入"), "Missing card-mark API is explicit and cannot submit")
	check(backend.stocks == baseline_stock and backend.wanted[Fixture.A] == ["0002"], "Viewing card marks never changes inventory or wishes")
	await capture(dialog, "03-card-mark-unavailable")
	# Real gift/trade data generated only by the isolated service contract fixture.
	await backend.send_gift({"account_id": Fixture.A, "id": "p3-gift", "card_id": "0001", "friend_id": Fixture.B, "quantity": 1})
	for index in 42: backend.append(cid, Fixture.A, "text", {"text": "分页测试 %d" % index})
	var trade_result: Dictionary = backend.execute(Fixture.A, "create_trade", {"operation_id": "p3-trade", "peer_id": Fixture.B, "give": [{"card_id": "0001", "season_id": "season-001", "quantity": 1}], "receive": [{"card_id": "0002", "season_id": "season-001", "quantity": 1}], "terms_version": 1})
	check(trade_result.get("ok", false), "Transfer history fixture satisfies the existing service contract")
	dialog._switch("records")
	await pause()
	check(dialog._record_data.gifts.is_empty() and not str(dialog._cursors.gifts).is_empty() and not labels(dialog).contains("暂无赠送"), "First history page does not pretend older gifts are absent")
	dialog._load_records()
	await pause()
	check(dialog._record_data.gifts.size() == 1 and labels(dialog).contains("p3-gift"), "Gift records paginate the authorized conversation's business events")
	check(not labels(dialog).contains("分页测试"), "Ordinary messages are not shown as transfer records")
	await capture(dialog, "04-gift-records")
	dialog._open_record("p3-gift")
	await pause()
	check(labels(dialog).contains("赠送 0001 ×1"), "Gift detail reuses the actual authenticated gift endpoint")
	dialog._switch("records")
	await pause()
	dialog._choose_records("trades")
	await pause()
	check(dialog._record_data.trades.size() == 1, "Trade history is scoped to the same peer")
	dialog._open_record(str(dialog._record_data.trades[0].id))
	await pause()
	check(dialog.panel_mode == "record_detail" and not labels(dialog).contains("确认交换"), "Record detail is read-only even for a pending exchange")
	dialog._switch("remove")
	await pause()
	check(backend.friend(Fixture.A, Fixture.B), "Opening delete confirmation does not delete the friend")
	await capture(dialog, "05-remove-confirmation")
	backend.fail_action = "relationship"
	dialog._confirm_relationship()
	await pause()
	check(backend.friend(Fixture.A, Fixture.B) and not dialog.confirmation.disabled, "Delete failure retains the relationship and allows retry")
	backend.fail_action = ""
	var stocks_before: Dictionary = backend.stocks.duplicate(true)
	var log_count: int = backend.logs.size()
	dialog._switch("block")
	await pause()
	check(labels(dialog).contains("解除好友关系"), "Blocking explicitly discloses the existing server's relationship rule")
	dialog._confirm_relationship()
	await pause()
	check(backend.blocked(Fixture.A, Fixture.B) and not backend.friend(Fixture.A, Fixture.B), "Blocking invokes the real relationship contract, not notification preferences")
	check(not backend.may_send(Fixture.B, Fixture.A, cid), "A blocked sender cannot send a new message")
	check(backend.stocks == stocks_before and backend.logs.size() == log_count, "Blocking preserves inventory and message history")
	dialog._switch("peer_menu")
	await pause()
	check(dialog.rows.block.caption.text == "解除屏蔽", "Blocked state offers the actual unblock action")
	dialog._activate("block")
	await pause()
	dialog._confirm_relationship()
	await pause()
	check(not backend.blocked(Fixture.A, Fixture.B) and not backend.friend(Fixture.A, Fixture.B), "Unblock does not fabricate a restored friendship")
	backend.relationships[cid] = true
	backend.revision += 1
	social.refresh()
	await pause()
	dialog._switch("remove")
	await pause()
	dialog._confirm_relationship()
	await pause()
	check(not backend.friend(Fixture.A, Fixture.B) and backend.logs.size() == log_count and backend.stocks == stocks_before, "Confirmed deletion removes only the relationship and preserves history/assets")
	key(KEY_ESCAPE)
	await pause()
	check(not is_instance_valid(page.dialog) and root.gui_get_focus_owner() == page.more_button, "Escape frees the overlay and restores ellipsis focus")
	await capture(null, "06-closed-chat")
	# Reopen with animation and close mid-entry; the previous timer must not
	# dismiss a new instance or leave an invisible input shield.
	backend.relationships[cid] = true
	backend.revision += 1
	social.refresh()
	motion.set_enabled(true)
	motion.suspended = false
	motion.system_reduced = 0 # Exercise animation even in the offscreen renderer.
	page._peer_panel("peer_menu")
	# Offscreen rendering may deliver one frame >180 ms. Step the real Tween
	# deterministically so an idle-window frame cap cannot skip the sample.
	var panel_track := "%s:modulate:a" % page.dialog.panel.get_instance_id()
	check(motion.tracks.has(panel_track) and page.dialog.panel.modulate.a == 0, "Opening registers a real opacity track starting at zero")
	motion.tracks[panel_track].tween.custom_step(0.045)
	check(page.dialog.panel.modulate.a > 0 and page.dialog.panel.modulate.a < 1, "Opening renders intermediate alpha during the 180 ms transition")
	await pause()
	page.dialog.dismiss()
	motion.tracks[panel_track].tween.custom_step(0.035)
	check(is_instance_valid(page.dialog) and page.dialog.panel.modulate.a > 0 and page.dialog.panel.modulate.a < 1, "Closing renders intermediate alpha during the 120 ms transition")
	await pause()
	for index in 4:
		page._peer_panel("peer_menu")
		await pause(0.035)
		page.dialog.dismiss()
		page._peer_panel("peer_menu")
		await pause(0.2)
		check(is_instance_valid(page.dialog) and not page.dialog.closing, "Rapid reopen cancels the previous close lifetime")
		page.dialog.dismiss()
		await pause()
	check(page.find_children("ConversationModalShade", "ColorRect", true, false).is_empty(), "Rapid close leaves no shade or pointer interceptor")
	dialog = await open()
	check(is_equal_approx(dialog.panel.modulate.a, 1) and is_equal_approx(dialog.shade.modulate.a, 1), "Open animation settles panel and shade opacity")
	click(Vector2(8, 8))
	await pause()
	check(not is_instance_valid(page.dialog), "Clicking outside dismisses the modal")
	dialog = await open()
	root.size = Vector2i(900, 620)
	await pause()
	check(root.get_visible_rect().encloses(dialog.panel.get_global_rect()), "Small window keeps all six rows inside the viewport")
	await capture(dialog, "07-small-window", true)
	root.get_node("AppState")._set_font_scale(1.6)
	await pause()
	check(root.get_visible_rect().encloses(dialog.panel.get_global_rect()), "Increased font scaling fits the viewport without clipping the panel")
	await capture(dialog, "08-large-font", true)
	root.get_node("AppState")._set_font_scale(1.0)
	root.size = Vector2i(1624, 946)
	root.get_node("AppState").dark_mode = true
	root.get_node("AppState").color_mode_changed.emit(true)
	await pause()
	check(is_instance_valid(page.dialog) and dialog.panel.get_theme_stylebox("panel").bg_color == Color.WHITE, "P3 remains white when the surrounding page changes theme")
	await capture(dialog, "09-dark-background", true)
	dialog.dismiss()
	await pause()
	check(root.gui_get_focus_owner() == page.more_button, "Theme rebuild restores focus to the new ellipsis instance")
	page._select("system:" + Fixture.A)
	await pause()
	page._peer_panel("peer_menu")
	check(not is_instance_valid(page.dialog), "Official read-only channel cannot open ordinary friend actions")
	page._select(cid)
	await pause()
	dialog = await open()
	page._select("system:" + Fixture.A)
	await pause()
	check(not is_instance_valid(page.dialog), "Switching target immediately discards the previous modal context")
	page._select(cid)
	await pause()
	dialog = await open()
	dialog._switch("remark")
	await pause()
	dialog.query.text = "旧账号请求"
	backend.delay = 0.15
	dialog._save_remark()
	backend.actor = Fixture.C
	profile.use_provider(backend, {"state": "authenticated", "account_id": Fixture.C})
	await pause(0.3)
	check(not is_instance_valid(page.dialog) and social.account_id == Fixture.C and not page.chat_name.text.contains("旧账号请求"), "Account switch discards stale UI responses and releases the overlay")
	backend.delay = 0
	backend.actor = Fixture.A
	profile.use_provider(backend, {"state": "authenticated", "account_id": Fixture.A})
	await pause()
	page._select(cid)
	await pause()
	dialog = await open()
	motion.set_enabled(false)
	dialog.dismiss()
	check(not is_instance_valid(page.dialog), "Reduced motion closes immediately without a blocking layer")
	motion.set_enabled(true)
	motion.suspended = false
	dialog = await open()
	dialog._switch("profile")
	root.get_node("PageRouter").go("res://scenes/Workbench.tscn")
	await scene_changed
	await pause()
	check(root.find_children("ConversationModalShade", "ColorRect", true, false).is_empty(), "Leaving during a secondary transition frees the entire modal")
	print("CONVERSATION ACTION ASSERTIONS: %d (isolated contract; no production writes)" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
