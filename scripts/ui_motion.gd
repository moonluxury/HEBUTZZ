extends Node
const Styles = preload("res://scripts/ui_styles.gd")
## Interruptible presentation only. No answer/save/request depends on a Tween callback.
const Tokens = preload("res://scripts/ui_tokens.gd")
const Feedback = preload("res://scripts/ui_feedback.gd")
signal preference_changed
signal pointer_changed
var enabled := true
var system_reduced := -1
var hover_enabled := true
var suspended := false
var tracks: Dictionary = {}

func _ready() -> void:
	refresh_system_preference()
	enabled = not OS.get_environment("HEGONG_REDUCED_MOTION").to_lower() in ["1", "true"]
	get_window().visibility_changed.connect(func():
		if not get_window().visible:
			_suspend()
		else:
			_resume()
	)

func _notification(what: int) -> void:
	if not is_node_ready():
		return
	# Application focus, not the main Window: opening a child popup isn't app blur.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_suspend()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_resume()

func refresh_system_preference() -> void:
	system_reduced = DisplayServer.accessibility_should_reduce_animation()
	if reduced():
		finish_all()
	preference_changed.emit()

func set_enabled(value: bool) -> void:
	enabled = value
	if reduced():
		finish_all()
	preference_changed.emit()

func reduced() -> bool:
	return not enabled or system_reduced == 1 or suspended

func _suspend() -> void:
	suspended = true
	finish_all()
	preference_changed.emit()

func _resume() -> void:
	suspended = false
	refresh_system_preference()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		set_hover_enabled(false)
	elif event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		set_hover_enabled(true)

func set_hover_enabled(value: bool) -> void:
	if hover_enabled == value:
		return
	hover_enabled = value
	pointer_changed.emit()

func animate(owner: Node, target: Object, property: NodePath, value: Variant, duration: float, exiting := false) -> void:
	var key := "%s:%s" % [target.get_instance_id(), property]
	if tracks.has(key):
		var previous: Dictionary = tracks[key]
		if previous.value == value and duration > 0 and not reduced():
			return
		_dispose_tween(previous.tween)
		tracks.erase(key)
	if reduced() or duration <= 0 or target.get_indexed(property) == value or not owner.is_inside_tree():
		target.set_indexed(property, value)
		return
	var tween := owner.create_tween()
	# Godot equivalent: non-overshooting cubic ease out/in; never bounce or spring.
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if exiting else Tween.EASE_OUT)
	tween.tween_property(target, property, value, duration)
	tracks[key] = {"tween": tween, "target": weakref(target), "owner": weakref(owner), "property": property, "value": value}
	tween.finished.connect(_track_finished.bind(key, tween.get_instance_id()))
	if not owner.tree_exiting.is_connected(_owner_exiting.bind(owner.get_instance_id())):
		owner.tree_exiting.connect(_owner_exiting.bind(owner.get_instance_id()))

func _track_finished(key: String, tween_id: int) -> void:
	# Completion can trigger layout/visibility callbacks that replace this track.
	if tracks.has(key) and tracks[key].tween.get_instance_id() == tween_id:
		tracks.erase(key)

func _dispose_tween(tween: Tween) -> void:
	# A killed Tween bound to a detached cached page can remain in SceneTree's
	# queue. Rebind it to this persistent manager so Godot can retire it next frame.
	tween.bind_node(self)
	tween.kill()

func settle_subtree(root: Node) -> void:
	for key in tracks.keys():
		if not tracks.has(key):
			continue
		var owner: Node = tracks[key].owner.get_ref()
		if owner == root or (is_instance_valid(owner) and root.is_ancestor_of(owner)):
			cancel(owner)

func _owner_exiting(id: int) -> void:
	for key in tracks.keys():
		if not tracks.has(key):
			continue
		var owner: Object = tracks[key].owner.get_ref()
		if owner == null or owner.get_instance_id() == id:
			var track: Dictionary = tracks[key]
			tracks.erase(key)
			_dispose_tween(track.tween)
			# A control may be reparented by theme rebuild, not destroyed. Settle first.
			var target: Object = track.target.get_ref()
			if is_instance_valid(target):
				target.set_indexed(track.property, track.value)

func finish_all() -> void:
	var finishing := tracks.values()
	tracks.clear()
	for track in finishing:
		_dispose_tween(track.tween)
		var target: Object = track.target.get_ref()
		if is_instance_valid(target):
			target.set_indexed(track.property, track.value)

func cancel(owner: Node, settle := true) -> void:
	for key in tracks.keys():
		if not tracks.has(key):
			continue
		if tracks[key].owner.get_ref() == owner:
			var track: Dictionary = tracks[key]
			tracks.erase(key)
			_dispose_tween(track.tween)
			var target: Object = track.target.get_ref()
			if settle and is_instance_valid(target):
				target.set_indexed(track.property, track.value)

func enter(control: Control, duration := Tokens.PAGE) -> void:
	if not is_instance_valid(control):
		return
	if not control.has_meta("motion_visibility"):
		control.set_meta("motion_visibility", true)
		control.visibility_changed.connect(_control_visibility_changed.bind(weakref(control)))
	if not control.is_visible_in_tree():
		cancel(control)
		control.modulate.a = 1.0
		return
	# Retarget an in-flight fade from its current value instead of restarting it.
	var key := "%s:modulate:a" % control.get_instance_id()
	if not tracks.has(key):
		control.modulate.a = 0.0 if not reduced() else 1.0
	animate(control, control, ^"modulate:a", 1.0, duration)

func _control_visibility_changed(reference: WeakRef) -> void:
	var control: Control = reference.get_ref()
	if is_instance_valid(control) and not control.is_visible_in_tree():
		cancel(control)
		control.modulate.a = 1.0

func reveal(control: Control, visible: bool) -> void:
	cancel(control)
	if visible:
		control.show()
		enter(control, Tokens.PANEL)
	else:
		# Preserve Container/formula layout and release focus immediately on close.
		control.hide()
		control.modulate.a = 1.0

func retire(control: Control) -> void:
	# Retiring visuals never retain a click shield or keyboard focus.
	for item in [control] + control.find_children("*", "Control", true, false):
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.focus_mode = Control.FOCUS_NONE
	if reduced():
		control.queue_free()
		return
	animate(control, control, ^"modulate:a", 0.0, Tokens.EXIT, true)
	get_tree().create_timer(Tokens.EXIT).timeout.connect(control.queue_free)

func bind_button(button: Variant, primary := false, semantic := false) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree() or button.is_queued_for_deletion() or button.get_meta("motion_fixed", false):
		return
	var feedback = button.get_node_or_null("UIFeedback")
	if feedback == null:
		feedback = Feedback.new()
		feedback.name = "UIFeedback"
		button.add_child(feedback)
	feedback.configure(primary, semantic)
	if button is MenuButton or button is OptionButton:
		bind_popup(button.get_popup(), button)

func bind_popup(popup: PopupMenu, source: Button) -> void:
	if popup.has_meta("motion_bound"):
		return
	popup.set_meta("motion_bound", true)
	var dark: bool = get_node("/root/AppState").dark_mode
	Styles.popup(popup, source, dark, choice_icon)
	# PopupMenu owns a viewport: tint that canvas instead of rebuilding menu controls.
	popup.transparent_bg = true
	popup.transparent = true
	var tint := CanvasModulate.new()
	popup.add_child(tint)
	popup.about_to_popup.connect(func():
		cancel(popup)
		tint.color.a = 1.0 if reduced() else 0.0
		animate(popup, tint, ^"color:a", 1.0, Tokens.PANEL)
	)
	popup.popup_hide.connect(func(): cancel(popup); tint.color.a = 1.0)

func choice_icon(kind: String, color: Color) -> Texture2D:
	var shape := '<path d="m4 7 5 5 5-5"/>'
	if kind != "arrow":
		shape = '<circle cx="9" cy="9" r="6.3"/>'
		if kind == "checked":
			shape += '<circle cx="9" cy="9" r="3" fill="#%s" stroke="none"/>' % color.to_html(false)
	# DPITexture rasterizes the vector at each Window's actual display scale.
	return DPITexture.create_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18"><g fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [color.to_html(false), shape])

func bind_input(control: Variant) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree() or control.is_queued_for_deletion():
		return
	var feedback = control.get_node_or_null("UIFeedback")
	if feedback == null:
		feedback = Feedback.new()
		feedback.name = "UIFeedback"
		control.add_child(feedback)
	feedback.configure_input()

func bind_panel(panel: Variant, duration := Tokens.HOVER) -> void:
	if not is_instance_valid(panel) or panel.is_queued_for_deletion() or not panel.is_inside_tree():
		return
	var feedback = Feedback.new()
	feedback.name = "UIFeedback"
	panel.add_child(feedback)
	feedback.configure_panel(duration)
