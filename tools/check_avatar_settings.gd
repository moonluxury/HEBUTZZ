extends SceneTree
const Fixture = preload("res://tools/fixtures/profile_provider.gd")
const Avatar = preload("res://scripts/profile_avatar.gd")
var failures: Array[String] = []
var assertions := 0
var page: Node
var store: Node
var services: Node
var backend: Node
var collection: Node
var captures := "res://outputs/avatar-settings-validation"

class LoginAdapter extends "res://scripts/backend_provider.gd":
	var canonical := {"avatar_card_id": "0001", "public_id": "ISOLATED-LOGIN", "display_name": "登录联调测试"}
	var sent: Dictionary = {}
	func _remember_session(_response: Dictionary) -> void:
		# Avatar tests exercise the login handoff, not platform credential encryption.
		pass
	func _request(path: String, body: Dictionary, _authenticated := true, _session: Dictionary = {}) -> Dictionary:
		if path == "/v1/auth/login":
			return {"ok": true, "account_id": "login-adapter-test", "access_token": "isolated-memory-token"}
		var action: String = body.get("action", "")
		if action == "snapshot":
			return {"ok": true, "account_id": account_id, "revision": 1, "inventory_complete": true, "inventory": {"0001": {"count": 1}, "0002": {"count": 1}}}
		if action == "save_profile":
			sent = body.payload.duplicate(true)
			if sent.get("avatar_change", false): canonical.avatar_card_id = sent.avatar_card_id
		if action in ["profile", "save_profile"]:
			return {"ok": true, "account_id": account_id, "profile": canonical.duplicate(true), "persisted": true, "editable_fields": {"avatar_card_id": {"reset_supported": true}}}
		return {"ok": false, "account_id": account_id, "code": "unavailable"}

func _init() -> void:
	OS.set_environment("HEGONG_BACKEND_DISABLED", "1")
	_run.call_deferred()

func check(value: bool, caption: String) -> void:
	assertions += 1
	if not value:
		failures.append(caption)
		push_error(caption)

func frames(count := 8) -> void:
	for index in count: await process_frame

func open_panel() -> Node:
	page.avatar_button.pressed.emit()
	await frames()
	return page.dialog

func close_panel() -> void:
	if is_instance_valid(page.dialog): page.dialog.dismiss()
	await frames()

func key(window: Window, code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		(root if window.is_embedded() else window).push_input(event)
	await frames()

func capture(name: String) -> void:
	await frames()
	if DisplayServer.get_name() == "headless": return
	var dialog: Window = page.dialog
	var mark := Label.new()
	mark.text = "实际运行 · 隔离测试账户"
	mark.add_theme_font_size_override("font_size", 11)
	mark.add_theme_color_override("font_color", page.muted_color)
	dialog.add_child(mark)
	mark.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mark.offset_left = 30
	mark.offset_top = -17
	mark.offset_bottom = -2
	await frames()
	await RenderingServer.frame_post_draw
	dialog.get_texture().get_image().save_png(captures.path_join(name + ".png"))
	root.get_texture().get_image().save_png(captures.path_join(name + "-page.png"))
	mark.queue_free()

func capture_double_scale() -> void:
	if DisplayServer.get_name() == "headless": return
	var dialog: Window = page.dialog
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1680, 1800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var old_theme: Theme = dialog.panel.theme
	dialog.panel.theme = dialog.theme
	dialog.panel.reparent(viewport, false)
	dialog.panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	dialog.panel.size = Vector2(840, 900)
	viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(2, 2))
	await frames(12)
	check(dialog.avatar_preview.get_global_transform_with_canvas().get_scale().is_equal_approx(Vector2(2, 2)), "The actual preview renders at a measured 200 percent canvas scale")
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(captures.path_join("05-preview-200-percent.png"))
	dialog.panel.reparent(dialog, false)
	dialog.panel.theme = old_theme
	dialog.panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.queue_free()
	await frames()

func check_project_resolution() -> void:
	var dialog: Window = page.dialog
	var old_base := root.content_scale_size
	var old_size := root.size
	root.content_scale_size = Vector2i(2560, 1680)
	root.size = Vector2i(2560, 1500)
	await frames(18)
	var parent_scale: float = page.canvas.get_global_transform_with_canvas().get_scale().x
	var popup_scale: float = dialog.avatar_preview.get_screen_transform().get_scale().x
	check(popup_scale >= parent_scale * 0.9, "Popup typography follows the actual project/page scale rather than remaining at 1x")
	check(dialog.size.x >= root.get_visible_rect().size.x * 0.45, "Popup remains legible at the user's 2560px window size")
	var first: Rect2 = dialog.avatar_choices[""].picture.get_global_rect()
	var next: Rect2 = dialog.avatar_choices["0001"].picture.get_global_rect()
	var below: Rect2 = dialog.avatar_choices["0004"].picture.get_global_rect()
	check(absf((next.get_center().x - first.get_center().x) - (below.get_center().y - first.get_center().y)) < 1.1, "Horizontal and vertical avatar center spacing is equal")
	check(dialog.close_glyph.get_global_rect().get_center().distance_to(dialog.close_button.get_global_rect().get_center()) < 0.5 and dialog.close_button.get_node_or_null("AvatarKeyboardFocus") == null, "Close glyph is centered and has no stray underline")
	check(dialog.avatar_choices["0007"].button.get_global_rect().end.y <= dialog.scroll_box.get_global_rect().end.y + 1, "All eight candidates fit in the actual large-window layout")
	print("PROJECT SCALE CHECK: root=", root.size, " base=", root.content_scale_size, " popup=", dialog.size, " ui=", dialog.content_scale_factor, " backing=", dialog.get_texture().get_size())
	await capture("06-project-resolution-2560")
	root.content_scale_size = old_base
	root.size = old_size
	await frames(18)

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check-"):
		quit(2)
		return
	await frames()
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(captures)
	store = root.get_node("ProfileStore")
	services = root.get_node("AppServices")
	collection = services.collection_store()
	backend = Fixture.new()
	root.add_child(backend)
	store.use_provider(backend, {"state": "signed_out"})
	root.get_node("PageRouter").go("res://scenes/PersonalCenter.tscn")
	await scene_changed
	await frames()
	page = current_scene
	var dialog: Node = await open_panel()
	check(page.settings.get_node_or_null("AvatarSettings") == null, "Only the large profile avatar opens settings")
	check(dialog.avatar_choices.keys() == ["", "0001", "0002", "0003", "0004", "0005", "0006", "0007"], "The existing default is first and seven stable IDs retain their order")
	check(dialog.avatar_choices[""].picture.texture == Avatar.DEFAULT and dialog.avatar_preview.texture == Avatar.DEFAULT, "Preview and default candidate reuse the original blue silhouette")
	for id in dialog.avatar_choices:
		var item: Dictionary = dialog.avatar_choices[id]
		check(not item.button.disabled and item.picture.self_modulate == Color.WHITE, "Signed-out users can preview the original candidate: " + str(id))
		if not str(id).is_empty(): check(item.picture.texture.get_size() == Vector2(1145, 1374), "Original high-resolution resource retained: " + str(id))
	check(dialog.confirm.text == "登录后保存" and dialog.login_hint.visible, "Signed-out footer shows the login action")
	check(dialog.avatar_grid.find_children("*", "Label", true, false).is_empty(), "Candidate grid has no visible names or availability captions")
	dialog._select_card_avatar("0002")
	check(dialog.avatar_preview.texture == dialog.avatar_choices["0002"].picture.texture and store.profile.is_empty() and backend.saves == 0, "Selecting only updates the draft preview")
	await capture("01-signed-out-preview")
	dialog._confirm()
	await frames()
	check(page.dialog == dialog and dialog.selected_avatar == "0002" and backend.saves == 0 and "取消" in dialog.message.text, "Cancelled login preserves the draft and never saves")
	backend.login_result = "failure"
	dialog._confirm()
	await frames()
	check(dialog.selected_avatar == "0002" and "失败" in dialog.message.text and backend.saves == 0, "Failed login preserves the candidate")
	backend.login_result = "success"
	dialog._confirm()
	await frames()
	check(store.authenticated() and page.dialog == dialog and dialog.selected_avatar == "0002" and store.profile.avatar_card_id == "" and backend.saves == 0, "Only this login flow restores the draft, without applying it")
	check(dialog.confirm.text == "保存头像" and not dialog.login_hint.visible and not dialog.confirm.disabled, "Authenticated footer requires explicit save")
	await capture("02-authenticated-preview")
	await check_project_resolution()
	await capture_double_scale()
	dialog._confirm()
	await frames()
	check(page.dialog == null and store.profile.avatar_card_id == "0002" and backend.saves == 1, "Explicit save commits once and closes the picker")
	check(page.avatar.source_path == Avatar.path_for_card("0002") and page.sidebar.get_node("IdentityButton").avatar.source_path == page.avatar.source_path, "Own profile and sidebar refresh from canonical state")
	var own_cached := Avatar.new()
	var other_cached := Avatar.new()
	root.add_child(own_cached)
	root.add_child(other_cached)
	own_cached.show_profile({"id": "test-account-a", "avatar_card_id": "0001"})
	other_cached.show_profile({"id": "test-account-b", "avatar_card_id": "0004"})
	check(own_cached.source_path == Avatar.path_for_card("0002") and other_cached.source_path == Avatar.path_for_card("0004"), "Shared avatar controls refresh only the current user's cached identity")
	var persisted: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profile-test-test-account-a.json"))
	check(persisted.avatar_card_id == "0002", "Success is backed by an isolated persisted record")
	dialog = await open_panel()
	check(dialog.selected_avatar == "0002" and dialog.confirm.disabled, "Opening reflects the actual saved avatar and disables no-op saves")
	dialog._select_card_avatar("0001")
	await key(dialog, KEY_ESCAPE)
	check(page.dialog == null and store.profile.avatar_card_id == "0002" and page.avatar_button.has_focus(), "Escape discards unsaved choice and restores trigger focus")
	dialog = await open_panel()
	check(dialog.selected_avatar == "0002", "Cancelled choices do not survive reopening")
	backend.permissions.avatar_card_id.reset_supported = false
	store.refresh()
	dialog._select_card_avatar("")
	check(dialog.confirm.disabled and "服务更新" in dialog.message.text, "A server without reset support cannot falsely report a default reset")
	backend.permissions.avatar_card_id.reset_supported = true
	store.refresh()
	await frames()
	check(not dialog.confirm.disabled and dialog.message.text.is_empty(), "Capability refresh clears the obsolete unavailable notice")
	dialog._select_card_avatar("")
	check(not dialog.confirm.disabled and dialog.avatar_preview.texture == Avatar.DEFAULT, "Default reset has an explicit preview and save action")
	dialog._confirm()
	await frames()
	check(store.profile.avatar_card_id == "" and backend.accounts["test-account-a"].avatar_card_id == "", "Default reset persists the existing empty ID")
	check(own_cached.texture == Avatar.DEFAULT and other_cached.source_path == Avatar.path_for_card("0004"), "Reset propagates to own cached avatar without changing another user")
	own_cached.queue_free()
	other_cached.queue_free()
	dialog = await open_panel()
	check(dialog.avatar_choices["0003"].button.disabled and not dialog.avatar_choices["0002"].button.disabled, "Actual ownership rules remain unchanged; one copy is enough")
	var previous: int = backend.saves
	dialog._select_card_avatar("0003")
	check(dialog.selected_avatar == "" and backend.saves == previous, "Unowned choices cannot become save candidates")
	dialog.avatar_choices[""].button.grab_focus()
	await key(dialog, KEY_RIGHT)
	check(dialog.avatar_choices["0001"].button.has_focus() and dialog.selected_avatar == "", "Arrow keys move focus without selecting or saving")
	await key(dialog, KEY_SPACE)
	check(dialog.selected_avatar == "0001" and backend.saves == previous, "Space selects the focused candidate without saving")
	backend.save_fail = true
	dialog._confirm()
	await frames()
	check(page.dialog == dialog and dialog.selected_avatar == "0001" and store.profile.avatar_card_id == "" and not dialog.confirm.disabled, "Failure keeps both the draft and previous committed value")
	backend.save_fail = false
	backend.save_delay = 0.12
	dialog._confirm()
	dialog._confirm()
	dialog._select_card_avatar("0002")
	check(dialog.confirm.disabled and dialog.confirm.text == "保存中…" and dialog.selected_avatar == "0001", "In-flight save locks duplicate submissions and other candidates")
	await create_timer(0.18).timeout
	await frames()
	check(store.profile.avatar_card_id == "0001" and backend.saves == previous + 2, "Failed attempt and one successful retry are the only writes")
	dialog = await open_panel()
	dialog._select_card_avatar("0002")
	dialog._confirm()
	backend.inventory["0002"].count = 0
	await create_timer(0.18).timeout
	await frames()
	check(page.dialog == dialog and store.profile.avatar_card_id == "0001" and dialog.selected_avatar == "0002", "Ownership is revalidated at commit without losing the draft")
	backend.inventory["0002"].count = 1
	backend.revision += 1
	collection.refresh()
	await close_panel()
	backend.save_delay = 0
	dialog = await open_panel()
	dialog._select_card_avatar("0002")
	backend.unknown_after_save = true
	dialog._confirm()
	await frames(12)
	check(page.dialog == null and store.profile.avatar_card_id == "0002" and store.avatar_pending.is_empty(), "A lost success response is reconciled by reading the persisted avatar")
	backend.unknown_after_save = false
	dialog = await open_panel()
	dialog._select_card_avatar("0001")
	backend.unknown_before_save = true
	dialog._confirm()
	await frames(12)
	var original_request: String = store.avatar_pending.request_id
	check(not store.avatar_pending.is_empty() and dialog.confirm.text == "核实保存结果" and dialog.avatar_choices["0002"].button.disabled, "Unknown outcome retains one pending operation instead of inventing failure")
	backend.unknown_before_save = false
	dialog._confirm()
	await frames(12)
	check(store.profile.avatar_card_id == "0001" and backend.avatar_operations.has("test-account-a:" + original_request), "Retry uses the original stable operation ID")
	store.avatar_timeout_seconds = 0.03
	backend.save_delay = 0.12
	dialog = await open_panel()
	dialog._select_card_avatar("0002")
	dialog._confirm()
	await create_timer(0.08).timeout
	check(not store.saving and not store.avatar_pending.is_empty() and store.profile.avatar_card_id == "0001", "A slow adapter cannot hold the UI indefinitely")
	await close_panel()
	await create_timer(0.12).timeout
	store.avatar_timeout_seconds = 20.0
	backend.save_delay = 0
	dialog = await open_panel()
	dialog._confirm()
	await frames(12)
	check(store.profile.avatar_card_id == "0002" and store.avatar_pending.is_empty(), "Reopening verifies a late commit without applying a second write")
	dialog = await open_panel()
	dialog._select_card_avatar("0001")
	backend.save_delay = 0.12
	dialog._confirm()
	await close_panel()
	await create_timer(0.18).timeout
	check(store.profile.avatar_card_id == "0001", "Closing after submit leaves persistence under the shared store")
	dialog = await open_panel()
	dialog._select_card_avatar("0002")
	dialog._confirm()
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-b"})
	await create_timer(0.18).timeout
	await frames()
	check(page.dialog == null and store.account_id == "test-account-b" and store.profile.get("avatar_card_id", "").is_empty(), "Late account A save does not change account B")
	backend.save_delay = 0
	backend.accounts["test-account-b"].avatar_card_id = "unlisted-original-id"
	store.refresh()
	dialog = await open_panel()
	var selected_count := 0
	for item in dialog.avatar_choices.values():
		if item.button.selected: selected_count += 1
	check(dialog.selected_avatar == "unlisted-original-id" and selected_count == 0, "An unknown current ID is preserved without selecting the default")
	await close_panel()
	backend.accounts["test-account-b"].avatar_card_id = ""
	store.refresh()
	dialog = await open_panel()
	var source_path: String = Avatar.card_paths["0001"]
	Avatar.card_paths["0001"] = "res://missing-avatar-artwork.png"
	dialog._select_card_avatar("0001")
	check(dialog.selected_avatar == "0001" and dialog.avatar_preview.texture == Avatar.DEFAULT and dialog.confirm.disabled, "Missing artwork is a display fallback only and retains its ID")
	Avatar.card_paths["0001"] = source_path
	await close_panel()
	dialog = await open_panel()
	dialog._select_card_avatar("0004")
	root.get_node("AppState").dark_mode = true
	root.get_node("AppState").color_mode_changed.emit(true)
	await frames()
	check(page.dialog == dialog and dialog.selected_avatar == "0004", "Theme changes keep the draft and original image")
	await capture("03-dark-preview")
	dialog.size = Vector2i(400, 440)
	await frames(12)
	print("NARROW LAYOUT: window=", dialog.size, " factor=", dialog.content_scale_factor, " panel=", dialog.panel.size, " scroll=", dialog.scroll_box.size, " bar=", dialog.scroll_box.get_v_scroll_bar().size, " grid=", dialog.avatar_grid.size, " columns=", dialog.avatar_grid.columns)
	check(dialog.avatar_grid.columns == 2 and dialog.column.size.y > 0, "Narrow settings retain two columns")
	check(dialog.confirm.get_global_rect().end.y <= float(dialog.size.y) and dialog.cancel_button.get_global_rect().end.y <= float(dialog.size.y), "Save and cancel stay visible while the body scrolls")
	dialog.scroll_box.ensure_control_visible(dialog.avatar_choices["0007"].button)
	await frames()
	check(dialog.avatar_choices["0007"].button.get_global_rect().end.y <= dialog.scroll_box.get_global_rect().end.y + 1, "Last candidate stays reachable without shrinking images")
	await capture("04-narrow-footer")
	await close_panel()
	root.get_node("AppState").dark_mode = false
	root.get_node("AppState").color_mode_changed.emit(false)
	store.use_provider(backend, {"state": "signed_out"})
	dialog = await open_panel()
	dialog._select_card_avatar("0002")
	backend.login_delay = 0.12
	dialog._confirm()
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-b"})
	await create_timer(0.18).timeout
	check(page.dialog == null and store.account_id == "test-account-b", "Unrelated login during the scoped flow discards the old draft")
	# Exercise the actual login-window/adapter integration with local responses only.
	var adapter := LoginAdapter.new()
	root.add_child(adapter)
	store.use_provider(adapter, {"state": "signed_out"})
	dialog = await open_panel()
	dialog._select_card_avatar("0002")
	dialog._confirm()
	await frames()
	check(is_instance_valid(adapter.active_dialog) and adapter.active_dialog.get_parent() == dialog, "Existing account login opens inside the avatar modal")
	adapter.active_dialog.username.text = "avatar_test"
	adapter.active_dialog.password.text = "123456"
	adapter.active_dialog._submit()
	await frames(12)
	check(store.account_id == "login-adapter-test" and dialog.selected_avatar == "0002" and dialog.saved_avatar == "0001" and adapter.sent.is_empty(), "Real adapter login returns to the same draft without auto-saving")
	dialog._select_card_avatar("")
	dialog._confirm()
	await frames(12)
	check(adapter.sent.get("avatar_change", false) and adapter.sent.get("avatar_card_id") == "" and not str(adapter.sent.get("operation_id", "")).is_empty(), "Adapter sends explicit reset with the original empty ID and stable request key")
	check(store.profile.avatar_card_id == "" and page.dialog == null, "Reset result flows back through the real client adapter")
	store.use_provider(null, {"state": "signed_out"})
	await frames()
	print("AVATAR SETTINGS ASSERTIONS: %d" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
