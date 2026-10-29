extends SceneTree
const Fixture = preload("res://tools/fixtures/remembered_login_provider.gd")
const JsonStore = preload("res://scripts/local_json_store.gd")
var failures: Array[String] = []
var assertions := 0
var api: Node
var profile: Node
var saved: Dictionary
var save_path := ""

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count := 3) -> void:
	for index in count: await process_frame

func until(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(condition.call(), "Asynchronous login/storage operation completes within its deadline")

func restart(restore_saved := false, server := "https://remembered-login.test") -> void:
	if is_instance_valid(api):
		if is_instance_valid(api.active_dialog): api.active_dialog._cancel()
		profile.use_provider(null, {"state": "signed_out"})
		api.queue_free()
		await frames()
	if restore_saved: check(JsonStore.write(save_path, saved) == OK, "Restore only isolated test state")
	api = Fixture.new()
	api.base_url = server
	root.add_child(api)
	api.attach()
	await frames()

func open_login() -> Window:
	api.begin_login()
	await frames()
	return api.active_dialog

func snapshot(dialog: Window) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var dir := "res://.godot_appdata/remembered-login-visual"
	DirAccess.make_dir_recursive_absolute(dir)
	dialog.get_texture().get_image().save_png(dir + "/last-account.png")

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1200, 900)
	root.content_scale_size = root.size
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	profile = root.get_node("ProfileStore")
	await restart()
	var dialog := await open_login()
	check(not dialog.remembered_box.visible and dialog.username.text.is_empty(), "First run offers ordinary login without fabricated account history")
	dialog.username.text = "saved_user"
	dialog.password.text = "fixture-password-123"
	dialog.submit.pressed.emit()
	await until(func(): return profile.authenticated() and api.remembered_account().get("can_resume", false))
	check(api.account_id == "account-saved_user", "Password login attaches the verified account")
	check(api.remembered_account().username == "saved_user", "Successful login remembers the username")
	save_path = api._login_store().path()
	saved = JsonStore.read(save_path)
	var on_disk := FileAccess.get_file_as_string(save_path)
	check(not str(saved.get("protected_session", "")).is_empty(), "Session is protected by the real Windows DPAPI helper")
	check(not on_disk.contains("fixture-session-saved_user") and not on_disk.contains("fixture-password-123") and not on_disk.contains("access_token"), "Plaintext token and password are absent from the save")
	check(not api.remembered_account().has("protected_session"), "UI metadata does not expose the stored credential")

	await restart()
	dialog = await open_login()
	check(dialog.remembered_box.visible and dialog.username.text == "saved_user" and dialog.password.text.is_empty(), "Restart restores the last account without filling a password")
	check(not dialog.quick_login.disabled, "A protected cached session enables one-click login")
	await snapshot(dialog)
	dialog.quick_login.pressed.emit()
	dialog.quick_login.pressed.emit()
	await until(func(): return profile.authenticated())
	check(api.resume_calls == 1 and api.login_calls == 0, "One click validates the old session once, without submitting a password")
	check(profile.account_id == "account-saved_user", "Server-validated quick login attaches the expected account")
	await api.logout(api.account_id)
	check(not api.remembered_account().can_resume and api.remembered_account().username == "saved_user", "Explicit logout clears the shortcut credential while retaining the username")

	await restart(true)
	api.resume_error = "unauthenticated"
	dialog = await open_login()
	dialog.quick_login.pressed.emit()
	await until(func(): return not dialog.busy)
	check(not profile.authenticated() and dialog.quick_login.disabled, "Expired/revoked sessions never authenticate locally")
	check(dialog.username.text == "saved_user" and dialog.status.text.contains("密码"), "Expired login keeps the account and requests its password")
	check(str(JsonStore.read(save_path).get("protected_session", "")).is_empty(), "Rejected credentials are removed from disk")

	await restart(true)
	api.resume_error = "network"
	dialog = await open_login()
	dialog.quick_login.pressed.emit()
	await until(func(): return not dialog.busy)
	check(not profile.authenticated() and api.remembered_account().can_resume, "Network failure preserves a retryable cached session")
	dialog.username.text = "different_user"
	dialog.password.text = "wrong-password"
	dialog.submit.pressed.emit()
	await frames()
	check(api.remembered_account().username == "saved_user", "Failed password login never overwrites the last successful account")
	dialog.forget_account.pressed.emit()
	check(api.remembered_account().is_empty() and JsonStore.read(save_path).is_empty(), "Remove-record action erases local account and credential data")

	await restart(true, "https://another-login.test")
	check(api.remembered_account().is_empty(), "Remembered credentials never cross server endpoints")
	var response: Dictionary = await api.remembered_auth()
	check(not response.ok and api.resume_calls == 0, "No credential is sent to a different server")

	await restart(true)
	api.mismatched_owner = true
	response = await api.remembered_auth()
	check(not response.ok and not profile.authenticated() and not api.remembered_account().can_resume, "Mismatched server identity cannot switch the cached account silently")

	var corrupt := saved.duplicate(true)
	corrupt.protected_session = "AAAA"
	check(JsonStore.write(save_path, corrupt) == OK, "Prepare an isolated corrupted credential")
	await restart()
	response = await api.remembered_auth()
	check(not response.ok and api.resume_calls == 0 and not api.remembered_account().can_resume, "Corrupted credentials fail locally without a network login")

	await restart(true)
	response = await api.remembered_auth()
	check(api.accept_session(response), "Restore authenticated context before changing a password")
	await api.change_password("fixture-password-123", "replacement-123")
	check(not api.remembered_account().can_resume, "Password changes remove the local shortcut credential")

	await restart(true)
	dialog = await open_login()
	dialog.quick_login.pressed.emit()
	api.forget_remembered_account()
	await until(func(): return not dialog.busy)
	check(not profile.authenticated() and api.remembered_account().is_empty(), "Removing a record invalidates an in-flight quick login")
	dialog._cancel()
	print("REMEMBERED LOGIN ASSERTIONS: ", assertions)
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
