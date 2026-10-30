extends Control
## Fixed clipping boundary. Layout never animates the answer pane or the header.
signal mode_changed(mode: String)
const DURATION := 0.22
const DISTANCE := 24.0
var mode := "numbers"
var views: Dictionary = {}
var focus_memory: Dictionary = {}
var transition: Tween

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_node("/root/UiMotion").preference_changed.connect(_preference_changed)

func install(key: String, view: Control) -> void:
	views[key] = view
	add_child(view)
	view.visible = key == mode
	view.modulate.a = 1.0 if key == mode else 0.0
	_input_enabled(view, key == mode)

func switch_to(next: String, animate := true) -> void:
	if not views.has(next) or next == mode: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and views[mode].is_ancestor_of(focused):
		focus_memory[mode] = weakref(focused)
		focused.release_focus()
	var direction := -1.0 if next == "numbers" else 1.0
	mode = next
	if transition != null: transition.kill()
	mode_changed.emit(mode)
	var motion := get_node("/root/UiMotion")
	if not animate or motion.reduced(): _finish(); return
	transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for key in views:
		var view: Control = views[key]
		_input_enabled(view, key == mode)
		if key == mode and not view.visible:
			view.position.x = direction * DISTANCE; view.modulate.a = 0.0; view.show()
		if not view.visible: continue
		transition.tween_property(view, "position:x", 0.0 if key == mode else -direction * DISTANCE, DURATION)
		transition.tween_property(view, "modulate:a", 1.0 if key == mode else 0.0, DURATION)
	transition.finished.connect(_finish)

func _finish() -> void:
	if transition != null: transition.kill(); transition = null
	for key in views:
		var view: Control = views[key]
		view.visible = key == mode; view.position.x = 0.0; view.modulate.a = 1.0 if key == mode else 0.0
		_input_enabled(view, key == mode)
	if focus_memory.has(mode):
		var previous: Control = focus_memory[mode].get_ref()
		var focused := get_viewport().gui_get_focus_owner()
		var may_restore := focused == null or is_ancestor_of(focused) or str(focused.name) in ["OpenDiscussion", "CloseDiscussion"]
		if may_restore and is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()

func _input_enabled(view: Control, enabled: bool) -> void:
	# Godot 4.6 disables both mouse and keyboard traversal for the whole subtree.
	view.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED if enabled else Control.MOUSE_BEHAVIOR_DISABLED
	view.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED if enabled else Control.FOCUS_BEHAVIOR_DISABLED

func _preference_changed() -> void:
	if not is_inside_tree(): return
	if get_node("/root/UiMotion").reduced(): _finish()

func _exit_tree() -> void:
	if transition != null: transition.kill()
