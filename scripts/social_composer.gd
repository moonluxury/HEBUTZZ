extends TextEdit
signal submit
## IME composition is tracked through the editor and platform notification.
var composing := false
var ime_guard_until := 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_IME_UPDATE:
		composing = not DisplayServer.ime_get_text().is_empty()
		ime_guard_until = Time.get_ticks_msec() + 80

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if composing or has_ime_text() or Time.get_ticks_msec() < ime_guard_until:
			return
		accept_event()
		if event.echo:
			return
		if event.shift_pressed:
			insert_text_at_caret("\n")
		else:
			submit.emit()
