extends SceneTree
const ProfileFixture = preload("res://tools/fixtures/profile_provider.gd")
const Backend = preload("res://scripts/backend_provider.gd")
var failures: Array[String] = []
var assertions := 0
var page: Node
var store: Node
var backend: Node
var output := "res://.godot_appdata/account-ui-validation"

class AccountFixture extends Backend:
	var memory := {"username": "design_user", "account_id": "account-design_user", "can_resume": false}
	var login_delay := 0.0
	var requests := 0
	var sent_password := ""
	func remembered_account() -> Dictionary: return memory.duplicate(true)
	func forget_remembered_account() -> bool:
		memory = {}
		remembered_changed.emit()
		return true
	func _remember_session(_response: Dictionary) -> void: pass
	func _request(path: String, body: Dictionary, _authenticated := true, _credential: Dictionary = {}) -> Dictionary:
		if path in ["/v1/auth/login", "/v1/auth/register"]:
			requests += 1
			sent_password = str(body.password)
			if login_delay > 0: await get_tree().create_timer(login_delay).timeout
			if str(body.password) != " valid password ": return {"ok": false, "message": "隔离测试：认证失败。"}
			return {"ok": true, "account_id": "account-" + str(body.username), "access_token": "isolated-account-session"}
		if body.get("action") == "profile":
			return {"ok": true, "account_id": account_id, "profile": {"public_id": "TEST-ACCOUNT", "display_name": "隔离登录账户", "avatar_card_id": "0001"}, "editable_fields": {}}
		if body.get("action") == "snapshot":
			return {"ok": true, "account_id": account_id, "inventory_complete": true, "inventory": {"0001": {"count": 2}}, "revision": 1}
		return {"ok": false, "code": "unavailable"}

func _init() -> void: _run.call_deferred()

func check(value: bool, text: String) -> void:
	assertions += 1
	if not value:
		failures.append(text)
		push_error(text)

func frames(count := 8) -> void:
	for index in count: await process_frame

func until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while not condition.call() and Time.get_ticks_msec() < deadline: await process_frame
	check(condition.call(), "The isolated asynchronous operation finishes within its deadline")

func editor() -> Node:
	page.show_panel("edit", page.edit_button)
	await frames()
	return page.dialog

func capture(dialog: Window, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	dialog.get_texture().get_image().save_png(output.path_join(name + ".png"))
	root.get_texture().get_image().save_png(output.path_join(name + "-page.png"))

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(output)
	store = root.get_node("ProfileStore")
	backend = ProfileFixture.new()
	root.add_child(backend)
	backend.permissions.school = {}
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-a"})
	root.get_node("PageRouter").go("res://scenes/PersonalCenter.tscn")
	await scene_changed
	await frames()
	page = current_scene
	var dialog := await editor()
	check(dialog.fields.size() == 6 and dialog.confirm.disabled and dialog.confirm.text == "保存修改", "Six real fields appear and an unchanged draft cannot be submitted")
	check(dialog.editor_grid.columns == 2 and dialog.fields.school.get_global_rect().position.y == dialog.fields.college.get_global_rect().position.y, "School and college share the first two-column row")
	check(dialog.fields.major.get_global_rect().position.y == dialog.fields.grade.get_global_rect().position.y and dialog.fields.bio.get_global_rect().position.y > dialog.fields.grade.get_global_rect().position.y, "Major and grade share the second row; biography comes last")
	check(dialog.fields.display_name.size.x > dialog.fields.school.size.x * 1.8 and dialog.fields.bio.size.x == dialog.fields.display_name.size.x, "Name and biography occupy the full form width")
	var public_id: String = store.profile.public_id
	var owner: String = store.account_id
	dialog.fields.display_name.text = "未保存的草稿"
	dialog.fields.bio.text = "第一行\n第二行"
	dialog._draft_changed()
	check(not dialog.confirm.disabled and store.profile.display_name == "测试同学" and backend.saves == 0, "Typing and biography newlines change only the local draft")
	await capture(dialog, "01-edit-draft")
	dialog.dismiss()
	await frames()
	check(store.profile.display_name == "测试同学" and backend.saves == 0, "Cancelling the draft does not persist any fields")
	dialog = await editor()
	backend.save_fail = true
	dialog.fields.display_name.text = "新的显示名称"
	dialog._save()
	await until(func(): return not store.saving)
	check(page.dialog == dialog and dialog.fields.display_name.text == "新的显示名称" and store.profile.display_name == "测试同学", "Rejected saves preserve the draft and previously committed profile")
	backend.save_fail = false
	backend.save_delay = 0.12
	var saves: int = backend.saves
	dialog._save()
	dialog._save()
	dialog.dismiss()
	await frames()
	var replacement := await editor()
	await until(func(): return not store.saving)
	check(backend.saves == saves + 1 and page.dialog == replacement and replacement.fields.display_name.text == "新的显示名称", "One immutable write survives closing; its reply cannot close a later editor")
	check(store.account_id == owner and store.profile.public_id == public_id, "Changing a display name keeps the authenticated account and public ID")
	replacement.dismiss()
	await frames()
	backend.save_delay = 0
	backend.profile_unknown_after = true
	dialog = await editor()
	dialog.fields.bio.text = "已保存但回包丢失"
	dialog._save()
	await until(func(): return not store.saving)
	check(page.dialog == null and store.profile.bio == "已保存但回包丢失" and store.profile_pending.is_empty(), "A lost success response is confirmed by reading the authoritative profile")
	backend.profile_unknown_after = false
	backend.profile_unknown_before = true
	dialog = await editor()
	dialog.fields.grade.text = "研0"
	dialog._save()
	await until(func(): return not store.saving)
	var request: String = store.profile_pending.request_id
	check(dialog.confirm.text == "核实保存结果" and not dialog.fields.grade.editable, "An unconfirmed write stays distinct from a definite failure")
	backend.profile_unknown_before = false
	dialog._save()
	await until(func(): return not store.saving)
	check(store.profile.grade == "研0" and backend.profile_requests[-1].request_id == request and page.dialog == null, "Recovery reuses the immutable request and existing grade rules")
	store.profile_timeout_seconds = 0.03
	backend.save_delay = 0.12
	dialog = await editor()
	dialog.fields.major.text = "延迟确认的专业"
	saves = backend.saves
	dialog._save()
	await until(func(): return not store.saving)
	check(not store.profile_pending.is_empty() and store.profile.major != "延迟确认的专业", "A real local timeout never claims the delayed write failed or succeeded")
	request = str(store.profile_pending.request_id)
	await create_timer(0.15).timeout
	dialog._save()
	await until(func(): return not store.saving)
	check(store.profile.major == "延迟确认的专业" and backend.saves == saves + 1 and backend.profile_requests[-1].request_id == request, "A timeout retry confirms the original idempotent operation without a second write")
	store.profile_timeout_seconds = 20.0
	backend.save_delay = 0
	dialog = await editor()
	dialog.size = Vector2i(400, 460)
	await frames(16)
	check(dialog.editor_grid.columns == 1 and dialog.confirm.get_global_rect().end.y <= dialog.get_visible_rect().size.y, "Narrow editor stacks fields and keeps its footer visible")
	await capture(dialog, "02-edit-narrow")
	dialog.dismiss()
	await frames()
	var api := AccountFixture.new()
	api.base_url = "https://account-ui.test"
	root.add_child(api)
	store.use_provider(api, {"state": "signed_out"})
	page.show_panel("login", page.edit_button)
	await frames()
	dialog = api.active_dialog
	check(page.dialog == null and is_instance_valid(dialog), "Personal center opens the actual login form directly, with no second white panel")
	check(dialog.remembered_box.visible and dialog.username.text == "design_user" and dialog.password.text.is_empty() and not dialog.quick_login.visible, "A username-only record prefills the account without presenting invalid one-click login")
	check(dialog.password_hint.text.contains("请输入密码") and dialog.submit.text == "登录", "The remembered-account hint and primary action match the actual credential state")
	await capture(dialog, "03-login-remembered")
	dialog.password.text = "  密码 AbC !  "
	dialog.password.caret_column = 4
	dialog.password.select(2, 6)
	dialog._toggle_password(dialog.password)
	check(not dialog.password.secret and dialog.password.text == "  密码 AbC !  " and dialog.password.caret_column == 4 and dialog.password.get_selected_text() == "密码 A", "Password visibility preserves spaces, case, caret and selection")
	dialog._toggle_password(dialog.password)
	check(dialog.password.secret, "Password can be hidden again")
	dialog.username.clear()
	dialog._submit()
	check(api.requests == 0 and dialog.username.has_focus(), "Missing account focuses its field without sending an authentication request")
	dialog.username.text = "manual_other"
	dialog._forget_account()
	check(dialog.username.text == "manual_other" and not dialog.remembered_box.visible and not dialog.password_hint.visible, "Removing a local record preserves a manually entered different account and closes the empty row")
	dialog.mode_switch.pressed.emit()
	check(dialog.registering and dialog.field_boxes[dialog.confirmation].visible and dialog.password.text.is_empty(), "The text registration entry retains the original registration flow")
	dialog.mode_switch.pressed.emit()
	check(not dialog.registering and not dialog.field_boxes[dialog.confirmation].visible, "Returning to login removes the confirmation field and its label")
	dialog.username.text = "design_user"
	dialog.password.text = " valid password "
	api.login_delay = 0.14
	dialog._submit()
	dialog._submit()
	check(api.requests == 1 and dialog.submit.disabled and dialog.submit.text == "登录中…", "An in-flight login blocks duplicate requests and shows its submitting state")
	dialog.close_button.pressed.emit()
	check(api.active_dialog == null and not dialog.visible and dialog.password.text.is_empty(), "Closing an in-flight login hides the dialog and immediately clears sensitive input")
	page.show_panel("login", page.edit_button)
	await frames()
	var new_login: Window = api.active_dialog
	await create_timer(0.20).timeout
	check(not store.authenticated() and api.active_dialog == new_login, "A late cancelled authentication cannot log in or replace a later dialog")
	new_login._cancel()
	await frames()
	page.show_panel("login", page.edit_button)
	await frames()
	dialog = api.active_dialog
	dialog.username.text = "design_user"
	dialog.password.text = " valid password "
	dialog._submit()
	store.use_provider(backend, {"state": "authenticated", "account_id": "test-account-b"})
	await create_timer(0.20).timeout
	check(store.account_id == "test-account-b" and api.active_dialog == null and api.account_id.is_empty(), "An unrelated account switch cancels and invalidates the old login response")
	store.use_provider(api, {"state": "signed_out"})
	await frames()
	page.show_panel("avatar", page.avatar_button)
	await frames()
	var avatar: Window = page.dialog
	avatar._select_card_avatar("0002")
	avatar._confirm()
	await frames()
	dialog = api.active_dialog
	check(not avatar.visible and not avatar.shade.visible and dialog.visible and dialog.shade.visible, "Login from avatar settings shows one modal and one shade while retaining the draft")
	await capture(dialog, "04-login-from-avatar")
	dialog._cancel()
	await frames()
	check(avatar.visible and avatar.shade.visible and avatar.selected_avatar == "0002", "Cancelling login restores the source avatar draft without saving it")
	avatar._confirm()
	await frames()
	dialog = api.active_dialog
	dialog.username.text = "design_user"
	dialog.password.text = " valid password "
	dialog.password.text_submitted.emit(dialog.password.text)
	await until(func(): return store.authenticated())
	await frames()
	check(api.sent_password == " valid password " and store.account_id == "account-design_user", "Authentication receives the password unchanged and applies only the server-verified account")
	check(avatar.visible and avatar.selected_avatar == "0002" and store.profile.avatar_card_id == "0001", "Successful login restores the candidate but never automatically saves the avatar")
	avatar.dismiss()
	await frames()
	print("ACCOUNT UI ASSERTIONS: ", assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
