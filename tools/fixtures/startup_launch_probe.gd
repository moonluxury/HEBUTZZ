extends Node
## Injected only into a temporary test project; never registered in the application.
func _ready() -> void: _run.call_deferred()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		get_tree().quit(2)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var api := get_node("/root/BackendProvider")
	var profile := get_node("/root/ProfileStore")
	var dialog: Window = api.active_dialog
	if not api.login_required or profile.authenticated() or not is_instance_valid(dialog) or not dialog.visible:
		push_error("The actual main-scene launch did not require login")
		get_tree().quit(1)
		return
	if get_tree().current_scene.scene_file_path != "res://scenes/Workbench.tscn":
		push_error("The real initial scene was replaced unexpectedly")
		get_tree().quit(1)
		return
	print("NORMAL STARTUP LOGIN: PASS")
	get_tree().create_timer(0.5).timeout.connect(func():
		push_error("X did not exit the real main-scene process")
		get_tree().quit(1))
	dialog.close_button.pressed.emit()
