extends SceneTree
const Fixture = preload("res://tools/fixtures/profile_provider.gd")
var failures: Array[String] = []
var assertions := 0
var page: Node
var router: Node
var store: Node
var backend: Node
var captures := "res://outputs/profile-validation"

class Clipboard:
	extends RefCounted
	var result := true
	var value := ""
	func write_and_verify(text: String) -> bool:
		value = text
		return result

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count := 5) -> void:
	for i in count:
		await process_frame

func key(window: Window, code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		(root if window.is_embedded() else window).push_input(event)

func click(control: Control, fraction := Vector2(0.5, 0.5)) -> void:
	var rect := control.get_global_rect()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = rect.position + rect.size * fraction
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event, true)

func visit(scene: String) -> Node:
	router.go("res://scenes/" + scene + ".tscn")
	await scene_changed
	await frames()
	return current_scene

func capture(file: String, fixture := true) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	var label := Label.new()
	label.text = "实际运行 · 隔离测试资料" if fixture else "实际运行 · 未接入登录服务"
	label.position = Vector2(320, 8)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#092C87"))
	layer.add_child(label)
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(captures.path_join(file + ".png"))
	layer.queue_free()

func panel(mode: String, trigger: Control = null) -> Node:
	page.show_panel(mode, trigger)
	await frames()
	return page.dialog

func close_panel() -> void:
	if is_instance_valid(page.dialog):
		page.dialog.dismiss()
	await frames()

func labels(node: Node) -> String:
	var text := ""
	for child in node.find_children("*", "Label", true, false):
		text += child.text + "\n"
	return text

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
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
	store = root.get_node("ProfileStore")
	root.get_node("UiMotion").set_enabled(false)
	page = await visit("Workbench")
	var sidebar: Panel = page.sidebar
	var identity: Button = sidebar.get_node("IdentityButton")
	check(identity.username.text == "登录", "Signed-out shell uses the default avatar and login label")
	check(identity.avatar.texture == identity.avatar.DEFAULT, "Default avatar is available before any service")
	check(sidebar.get_node("KaiwuButton").get_child(1).text == "河工开物", "Resource navigation remains in its original location")
	check(sidebar.get_node("KaiwuButton").position.y == 360, "Original navigation geometry is preserved")
	identity.grab_focus()
	key(root, KEY_ENTER)
	await scene_changed
	await frames()
	page = current_scene
	check(page.name == "PersonalCenter" and is_instance_valid(page.dialog), "Anonymous identity opens a real login-availability panel")
	check("尚未接入登录服务" in page.dialog.message.text, "Missing authentication is explicit")
	await close_panel()
	check(page.copy_button.disabled and page.logout_button.disabled, "No invented ID or logout operation for anonymous users")
	check(page.values.school.text == "未填写" and page.values.bio.text == "暂无简介", "Missing profile fields have truthful defaults")
	await capture("01-current-no-service", false)
	backend = Fixture.new()
	root.add_child(backend)
	backend.profile_delay = 0.10
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-a"})
	check(store.profile.is_empty() and identity.username.text == "正在加载…", "Verified session loads without flashing invented or previous identity")
	await create_timer(0.16).timeout
	await frames()
	check(identity.username.text == "测试同学" and page.username.text == "测试同学", "Shell and profile read one authoritative profile")
	check(not page.edit_button.disabled, "Edit action is enabled after authenticated profile loading")
	check(page.public_id.text.ends_with(store.profile.public_id), "Displayed ID comes from the provider public field")
	check("帮助与反馈" not in labels(page.body) and "使用偏好" not in labels(page.body), "Removed settings do not reappear")
	check(page.settings.get_node("CollectionShortcut").get_child(0).texture == sidebar.get_node("CollectionButton").get_child(0).texture, "Both collection entries use the same card icon")
	check("查看卡牌收藏与想要清单" in labels(page.settings), "Collection shortcut has the confirmed description")
	for name in ["HomeButton", "AllButton", "WrongButton", "KaiwuButton", "CollectionButton"]:
		check(sidebar.get_node(name).get_theme_stylebox("normal").bg_color.a == 0, "Only identity is selected: " + name)
	check(identity.get_theme_stylebox("normal").bg_color == page.Tokens.SOFT, "Personal center selects the identity entry")
	await capture("02-profile-fixture")
	var clipboard := Clipboard.new()
	check(store.copy_public_id(clipboard).ok and clipboard.value == "TEST-2026-000001", "Clipboard copies complete canonical ID")
	clipboard.result = false
	check(not store.copy_public_id(clipboard).ok, "Clipboard failure never reports success")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		var original := DisplayServer.clipboard_get()
		check(store.copy_public_id().ok and DisplayServer.clipboard_get() == "TEST-2026-000001", "System clipboard write and readback work")
		DisplayServer.clipboard_set(original)
	backend.profile_fail = true
	store.refresh()
	await create_timer(0.16).timeout
	check(store.authenticated() and identity.username.text == "测试同学" and page.status.visible and not page.status.text.is_empty(), "Profile failures preserve real authentication and last committed identity")
	backend.profile_fail = false
	backend.profile_delay = 0.0
	store.refresh()
	var editor: Node = await panel("edit", page.edit_button)
	check(not editor.fields.has("school") and not editor.fields.has("public_id"), "Service field permissions preserve school and public ID")
	editor.fields.display_name.text = "取消的草稿"
	key(editor, KEY_ESCAPE)
	await frames()
	check(store.profile.display_name == "测试同学" and backend.saves == 0, "Cancel does not commit any draft")
	check(page.edit_button.has_focus(), "Closing a panel restores trigger focus")
	editor = await panel("edit", page.edit_button)
	editor.fields.display_name.text = "切换主题保留草稿"
	root.get_node("AppState").dark_mode = true
	root.get_node("AppState").color_mode_changed.emit(true)
	await frames()
	check(page.dialog == editor and editor.fields.display_name.text == "切换主题保留草稿", "Theme changes preserve the edit draft")
	root.get_node("AppState").dark_mode = false
	root.get_node("AppState").color_mode_changed.emit(false)
	await close_panel()
	editor = await panel("edit", page.edit_button)
	editor.fields.display_name.text = "已保存的测试昵称"
	editor.fields.bio.text = "新的测试简介"
	await capture("05-edit-fixture")
	backend.save_fail = true
	editor._save()
	await frames()
	check(is_instance_valid(page.dialog) and editor.fields.display_name.text == "已保存的测试昵称" and not editor.confirm.disabled, "Failed save retains the editable draft")
	check(store.profile.display_name == "测试同学" and "服务器拒绝" in editor.message.text, "Failed save leaves committed identity unchanged with specific feedback")
	backend.save_fail = false
	backend.save_delay = 0.15
	var before_saves: int = backend.saves
	editor._save()
	editor._save()
	check(editor.confirm.disabled and store.profile.display_name == "测试同学", "Saving locks submission and keeps committed data until success")
	await create_timer(0.22).timeout
	await frames()
	check(backend.saves == before_saves + 1 and not is_instance_valid(page.dialog), "Repeated submission commits once")
	check(identity.username.text == "已保存的测试昵称" and page.username.text == identity.username.text, "Successful save updates shared shell and profile")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://profile-test-test-account-a.json"))
	check(saved.display_name == store.profile.display_name, "Success is backed by fixture persistence")
	backend.save_delay = 0
	store.refresh()
	check(store.profile.display_name == saved.display_name, "Profile reload keeps persisted changes")
	var result: Dictionary = {}
	var callback := func(_ticket: String, response: Dictionary): result.merge(response, true)
	store.saved.connect(callback)
	store.save_profile({"public_id": "tampered"}, "", "forbidden")
	check(not result.get("ok", true) and store.profile.public_id == "TEST-2026-000001", "Protected fields cannot be saved through the adapter")
	backend.malformed_save = true
	store.save_profile({"display_name": "未确认的昵称"}, "", "unconfirmed")
	check(not result.get("ok", true) and store.profile.display_name == saved.display_name, "Unconfirmed persistence never updates displayed identity")
	backend.malformed_save = false
	backend.accounts["test-account-a"].display_name = saved.display_name
	store.saved.disconnect(callback)
	editor = await panel("edit", page.edit_button)
	backend.accounts["test-account-a"].college = "服务更新的测试学院"
	store.refresh()
	editor.fields.bio.text = "只修改简介"
	editor._save()
	await frames()
	check(store.profile.college == "服务更新的测试学院" and store.profile.bio == "只修改简介", "Saving a draft does not overwrite untouched fields refreshed by the service")
	check(not store.validate_card_avatar("user://selected-test-avatar.png").is_empty(), "Local image files cannot be used as avatars")
	editor = await panel("avatar", page.avatar_button)
	check(editor.avatar_choices.size() == 8 and editor.find_children("*", "FileDialog", true, false).is_empty(), "Avatar settings offer the default and seven catalog cards without file upload")
	check(editor.avatar_choices["0003"].button.disabled and not editor.avatar_choices["0001"].button.disabled, "Only owned cards can be selected")
	editor._select_card_avatar("0001")
	editor._confirm()
	await frames()
	check(store.profile.avatar_card_id == "0001" and identity.avatar.texture != identity.avatar.DEFAULT and page.avatar.source_path == identity.avatar.source_path, "Saved card avatar updates both profile and shared sidebar")
	await close_panel()
	backend.accounts["test-account-a"].avatar_card_id = "unknown-card"
	store.refresh()
	check(identity.avatar.texture == identity.avatar.DEFAULT and page.avatar.texture == page.avatar.DEFAULT, "Missing avatar falls back in both places")
	page.show_panel("friends")
	await scene_changed
	await frames()
	check(current_scene.scene_file_path.ends_with("MyFriends.tscn"), "Personal center friend entry uses the shared social module")
	check(current_scene.active_nav == "FriendsButton", "Shared friends navigation is selected")
	page = await visit("PersonalCenter")
	var account: Node = await panel("account")
	check("t***@example.invalid" in account.message.text and "13800138000" not in labels(account) and "must-never-render" not in labels(account), "Account panel displays only masked contact fields and no credentials")
	await close_panel()
	var version: Node = await panel("version")
	check("未提供版本号" in version.message.text, "Missing build metadata does not become an invented version")
	await close_panel()
	click(page.settings.get_node("CollectionShortcut"), Vector2(0.8, 0.8))
	await scene_changed
	await frames()
	var collection: Node = current_scene
	check(collection.name == "MyCollection" and collection.store == get_root().get_node("AppServices").collection_store(), "Profile shortcut enters the existing collection and state source")
	collection._set_filter("wanted")
	var season: String = collection.selected_season
	var expanded: Dictionary = collection.expanded.duplicate(true)
	var collection_id: int = collection.get_instance_id()
	page = await visit("PersonalCenter")
	sidebar.get_node("CollectionButton").pressed.emit()
	await scene_changed
	await frames()
	check(current_scene.get_instance_id() == collection_id and current_scene.filter == "wanted" and current_scene.selected_season == season and current_scene.expanded == expanded, "Sidebar entry retains exactly the same cached collection state")
	check(identity.get_theme_stylebox("normal").bg_color.a == 0, "Collection selection clears profile highlight")
	page = await visit("PersonalCenter")
	page.settings.get_node("CollectionShortcut").pressed.emit()
	await scene_changed
	await frames()
	check(current_scene.filter == "wanted" and current_scene.get_instance_id() == collection_id, "Profile entry does not reset collection filters or recreate its page")
	page = await visit("PersonalCenter")
	backend.accounts["test-account-a"].display_name = "很长的测试昵称，用来验证完整资料会自然换行而不会遮挡操作按钮"
	backend.accounts["test-account-a"].major = "很长的专业名称".repeat(8)
	backend.accounts["test-account-a"].bio = "这是一段用于验证换行和滚动的测试简介。".repeat(14)
	store.refresh()
	await frames()
	check(identity.size.x == 224 and identity.username.size.x == 126, "Long names cannot expand the sidebar")
	check(page.username.text == store.profile.display_name and not page.username.clip_text and page.username.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING, "Profile keeps the complete display name")
	root.content_scale_size = Vector2i(900, 700)
	root.size = Vector2i(900, 700)
	await frames(10)
	check(page.columns.vertical and page.content_height > page.scroll.size.y, "Narrow windows stack columns and scroll long text")
	check(page.username.size.y > 40, "Long display names wrap in narrow windows")
	check(page.edit_button.get_global_rect().end.x <= page.scroll.get_global_rect().end.x, "Long identity does not cover the edit action")
	await capture("03-narrow-long-text")
	root.get_node("AppState").dark_mode = true
	root.get_node("AppState").color_mode_changed.emit(true)
	await frames()
	check(page.dark and page.sidebar.get_node("IdentityButton") == identity, "Theme changes retain the shared identity entry")
	await capture("04-dark-narrow")
	root.get_node("AppState").dark_mode = false
	root.get_node("AppState").color_mode_changed.emit(false)
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	await frames()
	backend.profile_delay = 0.18
	store.refresh()
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-b"})
	check(store.profile.is_empty() and "很长" not in page.username.text, "Account switching clears previous identity immediately")
	await create_timer(0.24).timeout
	await frames()
	check(store.profile.public_id == "TEST-2026-000002" and page.username.text == "另一位测试同学", "Late previous-account reads are discarded")
	backend.profile_delay = 0
	backend.save_delay = 0.18
	editor = await panel("edit")
	editor.fields.display_name.text = "旧请求不能写回"
	editor._save()
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-a"})
	await create_timer(0.24).timeout
	check(store.profile.public_id == "TEST-2026-000001" and store.profile.display_name != "旧请求不能写回" and not is_instance_valid(page.dialog), "Switching accounts invalidates pending saves and closes drafts")
	backend.save_delay = 0
	backend.logout_fail = true
	var logout: Node = await panel("logout")
	logout._run_action("logout")
	await frames()
	check(store.authenticated() and "退出失败" in logout.message.text, "Failed logout preserves the session")
	backend.logout_fail = false
	backend.action_delay = 0.14
	var collection_store: Node = get_root().get_node("AppServices").collection_store()
	collection_store.set_wanted(str(collection_store.cards[0].id), true)
	var wanted_path: String = collection_store._path()
	var wanted_before := FileAccess.get_file_as_string(wanted_path)
	logout._run_action("logout")
	logout._run_action("logout")
	await create_timer(0.20).timeout
	await frames()
	check(not store.authenticated() and store.profile.is_empty() and identity.username.text == "登录", "Successful logout clears all displayed identity")
	check(backend.logouts == 2, "Repeated logout click sends only one request per attempt")
	check(FileAccess.get_file_as_string(wanted_path) == wanted_before, "Logout preserves the account collection save")
	check(collection_store.account_id == "local-profile" and not is_instance_valid(collection_store.provider), "Logout releases authenticated collection context without deleting data")
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-a"})
	editor = await panel("edit")
	editor.fields.display_name.text = "离页后的已提交资料"
	backend.save_delay = 0.14
	editor._save()
	var old_page: WeakRef = weakref(page)
	page = await visit("Workbench")
	await create_timer(0.20).timeout
	await frames()
	check(old_page.get_ref() == null and identity.username.text == "离页后的已提交资料", "Submitted work survives page disposal without retaining old UI")
	check(root.get_node("UiMotion").tracks.is_empty(), "Reduced-motion navigation leaves no orphaned tweens")
	page = await visit("PersonalCenter")
	backend.action_delay = 0.16
	store.run_action("logout", "late-logout")
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-b"})
	await create_timer(0.22).timeout
	check(store.authenticated() and store.account_id == "test-account-b", "Late logout cannot end a newly switched session")
	store.use_provider(null, {"state": "signed_out"})
	page = await visit("Workbench")
	check(page.sidebar == sidebar, "Shell is retained across profile navigation")
	print("PROFILE ASSERTIONS: %d" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
