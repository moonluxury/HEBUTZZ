extends SceneTree
const Fixture = preload("res://tools/fixtures/social_provider.gd")
var failures: Array[String] = []
var assertions := 0
var page: Node
var backend: Node
var profile: Node
var social: Node
var motion: Node
var output := "res://outputs/friend-dialog-validation"

class LoginFixture extends Fixture:
	var login_started := false
	var accept_login := false
	func begin_login() -> Dictionary:
		login_started = true
		await get_tree().create_timer(0.12).timeout
		if not accept_login: return {"ok": false, "message": "已取消登录"}
		actor = A
		get_node("/root/ProfileStore").use_provider(self, {"state": "authenticated", "account_id": A})
		return {"ok": true}

func _init() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(n := 8) -> void:
	for i in n: await process_frame

func pause(seconds := 0.22) -> void: await create_timer(seconds).timeout

func open_dialog() -> Node:
	page.add_button.grab_focus()
	page.show_panel("add")
	await pause()
	return page.dialog

func search(dialog: Node, value: String) -> void:
	dialog.query.text = value
	dialog.query.text_changed.emit(value)
	dialog._search()
	await pause()

func login(account: String) -> void:
	backend.actor = account
	profile.use_provider(backend, {"state": "authenticated", "account_id": account})
	await frames()

func capture(dialog: Window, name: String, settle := true) -> void:
	if DisplayServer.get_name() == "headless": return
	if settle: await pause()
	await RenderingServer.frame_post_draw
	var composite := root.get_texture().get_image()
	composite.save_png(output.path_join(name + ".png"))
	var picture := dialog.get_texture().get_image()
	picture.save_png(output.path_join(name + "-dialog.png"))
	for point in [Vector2i(0, 0), Vector2i(picture.get_width()-1, 0), Vector2i(0, picture.get_height()-1), picture.get_size()-Vector2i.ONE]:
		check(picture.get_pixelv(point).a < 0.02, "Rounded outer corner is transparent: " + name + str(point))
	# Texture alpha alone misses Godot's opaque letterbox drawn behind the window.
	# The backing texture may be supersampled; composite coordinates come from
	# the Window's displayed rectangle, not from that texture's pixel dimensions.
	var transform := root.get_stretch_transform()
	var origin := Vector2i((transform * Vector2(dialog.position)).round())
	var end := Vector2i((transform * Vector2(dialog.position + dialog.size)).round()) - Vector2i.ONE
	for direction in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var corner := Vector2i(end.x if direction.x > 0 else origin.x, end.y if direction.y > 0 else origin.y)
		var bounds := Rect2i(Vector2i.ZERO, composite.get_size())
		var on_screen := bounds.has_point(corner) and bounds.has_point(corner + direction * 3)
		check(on_screen, "Composited corner lies within the actual screen: " + name + str(direction))
		if not on_screen: continue
		var actual := composite.get_pixelv(corner)
		var outside := composite.get_pixelv(corner + direction * 3)
		check(absf(actual.r - outside.r) + absf(actual.g - outside.g) + absf(actual.b - outside.b) < 0.1, "Composited corner matches the surrounding shade: " + name + str(direction))

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED
	# Keep the production logical viewport, including fractional DPI/stretch composition.
	root.content_scale_size = Vector2i(2560, 1680)
	root.size = Vector2i(1672, 918)
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	DirAccess.make_dir_recursive_absolute(output)
	motion = root.get_node("UiMotion")
	profile = root.get_node("ProfileStore")
	root.get_node("PageRouter").go("res://scenes/MyFriends.tscn")
	await scene_changed
	await frames()
	page = current_scene
	social = page.store
	var dialog := await open_dialog()
	check(dialog.query.text.is_empty() and dialog._lookup.is_empty(), "Signed-out opening has no fabricated result")
	check(dialog.title == "添加好友" and dialog.close_button.text.is_empty(), "One fixed title and an icon-only close button")
	dialog._search()
	check(dialog.status.text.contains("请输入"), "Blank lookup fails locally")
	await capture(dialog, "00-signed-out")
	dialog.dismiss()
	await pause()
	backend = Fixture.new()
	root.add_child(backend)
	backend.users[Fixture.C].name = "隔离测试同学"
	backend.users[Fixture.C].avatar_card_id = "0001"
	await login(Fixture.A)
	social.set_tab("recent")
	social.select("system:" + Fixture.A)
	var badge := Label.new()
	badge.text = "实际 Godot 渲染 · 隔离测试账号与服务，不代表线上数据"
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", Color("#092C87"))
	badge.position = Vector2(520, 8)
	page.add_child(badge)
	dialog = await open_dialog()
	check(dialog.transparent_bg and dialog.get_node_or_null("DialogSurface") != null, "Single transparent viewport uses the existing rounded compositor")
	check(dialog.query.get_global_rect().position.y < dialog.search_button.get_global_rect().position.y and dialog.note.get_global_rect().position.y > dialog.result_slot.get_global_rect().end.y, "Search, result and note follow the reference order")
	await capture(dialog, "01-empty")
	await search(dialog, "QA-000003")
	check(dialog._lookup.state == "available" and dialog.send_button.text == "发送申请", "Exact lookup displays the returned user with inline outlined send action")
	check(dialog._lookup.user.id == Fixture.C and dialog._lookup.user.avatar_card_id == "0001", "Stable identity and existing avatar are supplied by the provider")
	await capture(dialog, "02-found")
	check(dialog.content.get_global_rect().end.y <= dialog.scroll_box.get_global_rect().end.y + 1, "All form content and final help fit the standard viewport")
	dialog.note.text = "é".repeat(100) + "末"
	dialog._note_edited()
	check(dialog.note.text == "é".repeat(100) and dialog.counter.text == "100/100", "100 visible characters preserve combining marks")
	dialog.note.text = "👩🏽‍💻".repeat(101)
	dialog._note_edited()
	check(dialog.note.text == "👩🏽‍💻".repeat(100), "Emoji sequences are counted as visible characters")
	dialog.note.text = "  你好，我们是同一门课程的同学。\n一起学习  "
	dialog._note_edited()
	var draft: String = dialog.note.text
	dialog._set_friend_tab("requests")
	await pause()
	dialog._set_friend_tab("add")
	await pause()
	check(dialog.note.text == draft and dialog._lookup.user.id == Fixture.C, "Switching tabs preserves draft and searched identity")
	backend.fail_action = "request_friend"
	dialog._request_friend()
	await pause()
	check(backend.requests.is_empty() and dialog.note.text == draft and not dialog.send_button.disabled, "Failed submission preserves identity and note, permits retry")
	if not motion.reduced():
		backend.delay = 0.04
		dialog._request_friend()
		dialog.dismiss()
		await pause(0.07)
		page.show_panel("add")
		await pause()
		dialog = page.dialog
		check(dialog._pending.is_empty() and not dialog.send_button.disabled and dialog.note.text == draft, "A response during the exit fade cannot leave a reopened form stuck submitting")
	backend.fail_action = ""
	backend.delay = 0.1
	for i in 5: dialog._request_friend()
	check(dialog.send_button.disabled and dialog.send_button.text == "发送中…", "Submission disables only the current target")
	dialog._set_friend_tab("requests")
	await pause()
	check(backend.requests.size() == 1 and backend.requests[0].note == draft, "Five clicks create one request and preserve note whitespace")
	check(social.requests.size() == 1, "Send response refreshes the existing shared request list")
	dialog._set_friend_tab("add")
	await pause()
	check(dialog.send_button.text == "申请已发送" and dialog.send_button.disabled, "Submission finishing on another tab updates the correct result")
	backend.delay = 0
	await capture(dialog, "03-sent")
	await search(dialog, "QA-000001")
	check(dialog._lookup.state == "self" and dialog.send_button.disabled, "Self-add is disabled")
	await search(dialog, "QA-000002")
	check(dialog._lookup.state == "friend" and dialog.send_button.text == "已是好友", "Existing friends use the conversation action")
	await search(dialog, "does-not-exist")
	check(dialog._lookup.state == "not_found" and dialog.empty_result.text == "未找到用户，请检查 ID", "Not-found is a real empty result")
	backend.fail_action = "find_user"
	await search(dialog, "QA-000004")
	check(dialog._lookup.is_empty() and dialog.status.text.contains("网络"), "Network failure is distinct from not-found")
	backend.fail_action = ""
	backend.blocks[Fixture.A + ":" + Fixture.D] = true
	await search(dialog, "QA-000004")
	check(dialog._lookup.state == "inaccessible" and dialog._lookup.get("user", {}).is_empty(), "Blocked lookup shows a generic status without private identity")
	backend.blocks.erase(Fixture.A + ":" + Fixture.D)
	backend.search_delay = true
	await search(dialog, "QA-000004")
	dialog.query.text = "QA-000002"
	dialog._search()
	dialog._query_edited("changed")
	await pause()
	check(dialog._lookup.is_empty(), "Edited query invalidates delayed identity")
	backend.search_delay = false
	dialog.dismiss()
	await pause()
	await login(Fixture.C)
	dialog = await open_dialog()
	await search(dialog, "QA-000001")
	check(dialog._lookup.state == "incoming" and dialog.status.text.contains("对方已申请"), "Incoming application directs to requests without a duplicate send")
	dialog._set_friend_tab("requests")
	await pause()
	await capture(dialog, "04-requests")
	check(social.requests[0].note == draft, "Recipient sees the exact transmitted note")
	dialog._respond(str(backend.requests[0].id), "accept")
	await pause()
	check(backend.friend(Fixture.A, Fixture.C) and social.friends.size() == 1, "Accept updates the shared friend list and both relationship sides")
	backend.execute(Fixture.D, "request_friend", {"peer_id": Fixture.C, "note": "忽略测试", "operation_id": "ignore-fixture"})
	social.refresh()
	await pause()
	dialog._respond(str(backend.requests[1].id), "ignore")
	await pause()
	check(backend.requests[1].status == "ignored" and not backend.friend(Fixture.D, Fixture.C), "Ignore updates status without creating a relationship")
	dialog.dismiss()
	await pause()
	for i in 10:
		dialog = await open_dialog()
		dialog.dismiss()
		if i % 2 == 0:
			var interrupted: bool = is_instance_valid(dialog) and not dialog.is_queued_for_deletion()
			page.show_panel("add")
			await pause()
			check(is_instance_valid(page.dialog) and (not interrupted or page.dialog == dialog) and not page.dialog.closing, "Quick reopen interrupts close without a second modal")
			dialog = page.dialog
			dialog.dismiss()
		await pause()
		check(page.dialog == null and page.find_children("FriendModalShade*", "ColorRect", true, false).is_empty(), "Open/close cycle cleans all modal surfaces")
		check(page.add_button.has_focus(), "Close restores the trigger focus")
	dialog = await open_dialog()
	root.size = Vector2i(800, 580)
	await pause()
	check(dialog.position.x >= 0 and dialog.position.y >= 0 and dialog.size.y < root.get_visible_rect().size.y, "Small viewport contains the modal")
	check(dialog.close_button.get_global_rect().end.y < dialog.get_visible_rect().size.y, "Close button stays outside scrolling content")
	await capture(dialog, "05-small")
	root.size = Vector2i(620, 420)
	await pause()
	check(dialog.scroll_box.get_v_scroll_bar().max_value > dialog.scroll_box.size.y, "Short window scrolls the form while keeping the header fixed")
	dialog.scroll_box.scroll_vertical = 10000
	await capture(dialog, "07-short-scrolled")
	root.size = Vector2i(1672, 918)
	await pause()
	root.get_node("AppState").font_scale = 1.4
	root.get_node("AppState").font_scale_changed.emit(1.4)
	await pause()
	check(dialog.position.y >= 0 and dialog.position.y + dialog.size.y <= root.get_visible_rect().size.y, "Large type scale stays bounded")
	await capture(dialog, "06-scaled")
	root.get_node("AppState").font_scale = 1.0
	root.get_node("AppState").font_scale_changed.emit(1.0)
	dialog.dismiss()
	await pause()
	page.show_panel("add")
	dialog = page.dialog
	await frames(1)
	await capture(dialog, "08-opening", false)
	await pause()
	dialog.dismiss()
	await pause(0.05)
	if is_instance_valid(dialog) and not dialog.is_queued_for_deletion(): await capture(dialog, "09-closing", false)
	await pause()
	dialog = await open_dialog()
	motion.set_enabled(false)
	dialog._set_friend_tab("requests")
	check(dialog.content.modulate.a == 1, "Reduced motion applies the final tab state immediately")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	dialog._window_input(event)
	await frames()
	check(page.dialog == null and page.add_button.has_focus(), "Escape closes and restores focus with reduced motion")
	dialog = await open_dialog()
	await search(dialog, "QA-000001")
	await login(Fixture.D)
	check(page.dialog == null, "Account switch disposes the previous user's private result")
	var login_provider := LoginFixture.new()
	root.add_child(login_provider)
	profile.use_provider(login_provider, {"state": "signed_out"})
	await frames()
	dialog = await open_dialog()
	dialog.query.text = "QA-000003"
	dialog.note.text = "登录后继续"
	dialog._login()
	check(login_provider.login_started and not dialog.visible and not dialog.shade.visible, "Existing login flow hides the origin window and its shade")
	await pause()
	check(dialog.visible and dialog.note.text == "登录后继续" and dialog.query.text == "QA-000003", "Cancelled login restores both drafts")
	login_provider.accept_login = true
	dialog._login()
	await pause()
	check(dialog.visible and social.account_id == Fixture.A and dialog._lookup.is_empty() and dialog.note.text == "登录后继续", "Successful login restores drafts but never an old account's result cache")
	dialog.dismiss()
	await frames()
	print("FRIEND DIALOG ASSERTIONS: %d (isolated provider, real rendering when enabled)" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
