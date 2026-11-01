extends SceneTree
const Fixture = preload("res://tools/fixtures/startup_login_provider.gd")

func _init() -> void: _run.call_deferred()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await process_frame
	root.get_node("PageRouter").go("res://scenes/Workbench.tscn")
	await scene_changed
	var api := Fixture.new()
	root.add_child(api)
	await create_timer(0.2).timeout
	var dialog: Window = api.active_dialog
	if not is_instance_valid(dialog) or not dialog.visible:
		push_error("Startup login did not open")
		quit(1)
		return
	var scenario := OS.get_environment("STARTUP_LOGIN_EXIT_CASE")
	if scenario == "busy":
		dialog.password.text = "fixture-password-123"
		dialog.submit.pressed.emit()
	print("STARTUP EXIT SCENARIO: " + scenario)
	print("WORKBENCH CHECKS: PASS (real process exit is required)")
	create_timer(0.5).timeout.connect(func():
		push_error("The application remained open after cancelling required login")
		quit(1))
	if scenario == "escape":
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = true
		(root if dialog.is_embedded() else dialog).push_input(event)
	else:
		dialog.close_button.pressed.emit()
