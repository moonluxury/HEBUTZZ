extends SceneTree
const Fixture = preload("res://tools/fixtures/startup_login_provider.gd")
var assertions := 0
var failures: Array[String] = []
var api: Node
var profile: Node
var router: Node

class ObservedExit extends Fixture:
	var quit_calls := 0
	func _quit_application() -> void: quit_calls += 1

func _init() -> void: _run.call_deferred()
func pause(seconds := 0.25) -> void: await create_timer(seconds).timeout
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); push_error(message)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var output := "res://outputs/startup-login-validation"
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func sign_out() -> void:
	api.access_token = ""
	api.account_id = ""
	profile.use_provider(api, {"state": "signed_out"})
	await pause()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await pause()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(2560, 1680)
	root.size = Vector2i(1624, 946)
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	root.get_node("UiMotion").set_enabled(false)
	profile = root.get_node("ProfileStore")
	router = root.get_node("PageRouter")
	router.go("res://scenes/Workbench.tscn")
	await scene_changed
	api = ObservedExit.new()
	root.add_child(api) # The same startup enable/attach path opens the form.
	check(api.login_required, "Startup locks navigation before the deferred login opens")
	await pause()
	var home := current_scene
	var dialog: Window = api.active_dialog
	check(is_instance_valid(dialog) and dialog.visible and dialog.exclusive, "Opening the desktop app automatically shows the exclusive login form")
	check(not profile.authenticated() and current_scene.process_mode == Node.PROCESS_MODE_DISABLED, "The underlying page cannot process input before authentication")
	check(dialog.heading_label.text == "账号登录" and dialog.close_button.text.is_empty(), "Reuse the original login title and X without extra explanatory copy")
	check(dialog.quick_login.visible and api.resume_calls == 0 and api.login_calls == 0, "Saved credentials still require an explicit login action on every launch")
	var click := InputEventMouseButton.new()
	click.position = Vector2(20, 300)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)
	click.pressed = false
	root.push_input(click, true)
	await pause()
	check(api.active_dialog == dialog and dialog.visible and current_scene == home, "Outside clicks cannot dismiss or bypass startup login")
	router.go("res://scenes/SubjectSelect.tscn")
	router.back()
	await pause()
	check(current_scene == home and not router.switch_queued, "Direct entry routes wait for authentication")
	await capture("01-required-login")
	api.resume_fails = true
	dialog.quick_login.pressed.emit()
	await pause()
	check(not profile.authenticated() and api.login_required and api.active_dialog == dialog and not dialog.busy, "Failed cached-session verification keeps the form open and the application locked")
	dialog.password.text = "wrong-password"
	dialog.submit.pressed.emit()
	await pause()
	check(not profile.authenticated() and api.active_dialog == dialog and dialog.status.visible, "Incorrect passwords cannot unlock or dismiss startup login")
	dialog.mode_switch.pressed.emit()
	check(dialog.registering and api.login_required, "Registration remains available inside the same required login flow")
	dialog.mode_switch.pressed.emit()
	dialog.username.text = "startup_user"
	dialog.password.text = "fixture-password-123"
	var before: int = api.login_calls
	dialog.submit.pressed.emit()
	dialog.submit.pressed.emit()
	await pause()
	check(api.login_calls == before + 1 and profile.authenticated(), "Successful authentication is submitted only once")
	check(not api.login_required and not is_instance_valid(api.active_dialog), "A verified session releases the login gate")
	check(current_scene.scene_file_path == "res://scenes/SubjectSelect.tscn" and current_scene.process_mode != Node.PROCESS_MODE_DISABLED, "The waiting route resumes only after successful login")
	await capture("02-authenticated-entry")
	await sign_out()
	dialog = api.active_dialog
	check(is_instance_valid(dialog) and dialog.visible and api.login_required, "Signing out or losing the session returns to required login")
	api.resume_fails = false
	dialog.quick_login.pressed.emit()
	await pause()
	check(profile.authenticated() and profile.account_id == "account-saved_user" and not api.login_required, "Existing one-click login unlocks only after verification")
	check(current_scene.process_mode != Node.PROCESS_MODE_DISABLED, "Reauthentication restores the existing page's input")
	await sign_out()
	dialog = api.active_dialog
	dialog.password.text = "fixture-password-123"
	dialog.submit.pressed.emit()
	dialog.close_button.pressed.emit()
	check(api.quit_calls == 1 and not dialog.visible and dialog.password.text.is_empty(), "X requests application exit immediately, including during an outstanding login")
	await pause()
	check(not profile.authenticated() and api.access_token.is_empty() and api.quit_calls == 1, "A late authentication reply cannot revive a closed startup session")
	print("STARTUP LOGIN ASSERTIONS: %d" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
