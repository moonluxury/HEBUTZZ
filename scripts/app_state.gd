extends Node
const JsonStore = preload("res://scripts/local_json_store.gd")
const LegacyMigration = preload("res://scripts/legacy_save_migration.gd")

signal font_scale_changed(scale: float)
signal color_mode_changed(is_dark: bool)

var quiz_mode := "all"
var subject_id := "xi"
var start_index := 0
var font_scale := 1.0
var dark_mode := false
var hegong_kaiwu_article: Dictionary = {}
var program_drafts: Dictionary = {}
var _draft_save_timer: Timer
const PROGRAM_DRAFTS_PATH := "user://python_code_drafts_v2.json"

const MIN_FONT_SCALE := 0.7
const MAX_FONT_SCALE := 1.8
const FONT_SCALE_STEP := 0.1
const HOME_SCENE_PATH := "res://scenes/Workbench.tscn"
const WINDOW_SAFE_FILL := 0.92

const SUBJECTS := {
	"marxism": {
		"title": "马克思主义原理",
		"question_path": "res://data/questions_marxism.json",
		"wrong_path": "user://wrong_questions_marxism.json",
	},
	"mao": {
		"title": "毛泽东思想和中国特色社会主义",
		"question_path": "res://data/questions_mao.json",
		"wrong_path": "user://wrong_questions_mao.json",
	},
	"xi": {
		"title": "习近平新时代中国特色社会主义思想概论",
		"question_path": "res://data/questions.json",
		"wrong_path": "user://wrong_questions.json",
	},
	"matlab": {
		"title": "MATLAB",
		"question_path": "res://data/questions_matlab.json",
		"wrong_path": "user://wrong_questions_matlab.json",
	},
	"python": {
		"title": "Python",
		"question_path": "res://data/questions_python.json",
		"wrong_path": "user://wrong_questions_python_v2.json",
	},
	"cpp": {
		"title": "C++",
		"question_path": "res://data/questions_cpp.json",
		"wrong_path": "user://wrong_questions_cpp.json",
	},
}


func get_subject() -> Dictionary:
	return SUBJECTS.get(subject_id, SUBJECTS["xi"])


func _ready() -> void:
	_migrate_legacy_user_data()
	if FileAccess.file_exists(PROGRAM_DRAFTS_PATH):
		var saved = JsonStore.read(PROGRAM_DRAFTS_PATH)
		if typeof(saved) == TYPE_DICTIONARY:
			program_drafts = saved
	_draft_save_timer = Timer.new()
	_draft_save_timer.one_shot = true
	_draft_save_timer.wait_time = 0.6
	_draft_save_timer.timeout.connect(_save_program_drafts)
	add_child(_draft_save_timer)
	_fit_window_to_current_screen.call_deferred()


func set_program_draft(key: String, code: String) -> void:
	program_drafts[key] = code
	_draft_save_timer.start()


func _save_program_drafts() -> void:
	if not program_drafts.is_empty() and JsonStore.write(PROGRAM_DRAFTS_PATH, program_drafts) != OK:
		push_warning("编程草稿保存失败，原文件已保留。")

func _migrate_legacy_user_data() -> void:
	LegacyMigration.migrate(SUBJECTS)

func _fit_window_to_current_screen() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0 or screen >= DisplayServer.get_screen_count():
		return
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		return

	var current_size := DisplayServer.window_get_size()
	var safe_bounds := Vector2i(
		maxi(1, floori(usable_rect.size.x * WINDOW_SAFE_FILL)),
		maxi(1, floori(usable_rect.size.y * WINDOW_SAFE_FILL)),
	)
	var target_size := _fit_size_inside(current_size, safe_bounds)
	var current_rect := Rect2i(
		DisplayServer.window_get_position(),
		current_size,
	)
	var needs_reposition := (
		target_size != current_size
		or not usable_rect.encloses(current_rect)
	)
	if target_size != current_size:
		DisplayServer.window_set_size(target_size)
	if needs_reposition:
		DisplayServer.window_set_position(
			usable_rect.position + (usable_rect.size - target_size) / 2,
		)


func _fit_size_inside(size: Vector2i, bounds: Vector2i) -> Vector2i:
	if size.x <= 0 or size.y <= 0 or bounds.x <= 0 or bounds.y <= 0:
		return size
	if size.x <= bounds.x and size.y <= bounds.y:
		return size
	var fit_scale := minf(
		float(bounds.x) / float(size.x),
		float(bounds.y) / float(size.y),
	)
	return Vector2i(
		maxi(1, floori(size.x * fit_scale)),
		maxi(1, floori(size.y * fit_scale)),
	)


func _exit_tree() -> void:
	_save_program_drafts()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			# A real popup owns Escape; an ordinary focused text field
			# must not swallow the page's back action just to release its focus.
			if _escape_owned_by_popup():
				return
			_mark_input_handled()
			if not event.echo:
				get_node("/root/PageRouter").back()
			return
		if event.pressed and not event.echo and event.keycode == KEY_F9:
			dark_mode = not dark_mode
			color_mode_changed.emit(dark_mode)
			_mark_input_handled()
			return

	if not event is InputEventMouseButton or not event.ctrl_pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_font_scale(font_scale + FONT_SCALE_STEP)
		_mark_input_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_font_scale(font_scale - FONT_SCALE_STEP)
		_mark_input_handled()


func _escape_owned_by_popup() -> bool:
	for window in get_tree().root.find_children("*", "Window", true, false):
		if window.visible and not window.is_queued_for_deletion():
			return true
	return false


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _set_font_scale(value: float) -> void:
	var next_scale := clampf(value, MIN_FONT_SCALE, MAX_FONT_SCALE)
	if is_equal_approx(font_scale, next_scale):
		return
	font_scale = next_scale
	font_scale_changed.emit(font_scale)
