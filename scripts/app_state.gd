extends Node

signal font_scale_changed(scale: float)
signal color_mode_changed(is_dark: bool)
signal spirit_progress_changed

var quiz_mode := "all"
var subject_id := "xi"
var start_index := 0
var font_scale := 1.0
var dark_mode := false
var hegong_kaiwu_article: Dictionary = {}
var spirit_progress := {
	"online_seconds": 0.0,
	"xp": 0,
	"level": 1,
	"correct_answers": 0,
	"wrong_answers": 0,
	"interactions": 0,
}
var _spirit_save_elapsed := 0.0
var _last_interaction_msec := -10000
var program_drafts: Dictionary = {}
var _draft_save_timer: Timer
const PROGRAM_DRAFTS_PATH := "user://python_code_drafts_v2.json"

const MIN_FONT_SCALE := 0.7
const MAX_FONT_SCALE := 1.8
const FONT_SCALE_STEP := 0.1
const SPIRIT_PROGRESS_PATH := "user://spirit_progress.json"
const SPIRIT_XP_PER_LEVEL := 100
const SPIRIT_XP_CORRECT := 10
const SPIRIT_XP_WRONG := 3
const SPIRIT_XP_INTERACTION := 2
const SPIRIT_XP_PER_ONLINE_MINUTE := 1
const SPIRIT_INTERACTION_COOLDOWN_MSEC := 3000
const LIGHT_BACKGROUND := Color("#F7F8FC")
const DARK_BACKGROUND := Color("#0B1220")
const LIGHT_FOREGROUND := Color(0.0, 0.0, 0.0)
const DARK_FOREGROUND := Color("#E8EEF8")
const LIGHT_DISABLED_FOREGROUND := Color(0.45, 0.45, 0.45)
const DARK_DISABLED_FOREGROUND := Color("#77869E")
const HOME_SCENE_PATH := "res://scenes/Main.tscn"
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
	_load_spirit_progress()
	if FileAccess.file_exists(PROGRAM_DRAFTS_PATH):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(PROGRAM_DRAFTS_PATH))
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
	if program_drafts.is_empty():
		return
	var file := FileAccess.open(PROGRAM_DRAFTS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(program_drafts))


func _migrate_legacy_user_data() -> void:
	# Desktop save folders follow the application name; keep existing learning records.
	# Android keeps its package identifier, so its private save folder is unchanged.
	if not OS.has_feature("pc"):
		return
	var user_dir := OS.get_user_data_dir()
	var legacy_dir := user_dir.get_base_dir().path_join("答题系统")
	var save_paths: Array[String] = [SPIRIT_PROGRESS_PATH]
	for subject in SUBJECTS.values():
		save_paths.append(str(subject["wrong_path"]))
	for save_path in save_paths:
		if FileAccess.file_exists(save_path):
			continue
		var legacy_path := legacy_dir.path_join(save_path.get_file())
		if not FileAccess.file_exists(legacy_path):
			continue
		var copy_error := DirAccess.copy_absolute(
			legacy_path, ProjectSettings.globalize_path(save_path),
		)
		if copy_error != OK:
			push_warning("学习记录迁移失败：%s（%s）" % [save_path.get_file(), error_string(copy_error)])


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


func _process(delta: float) -> void:
	var previous_minutes := int(float(spirit_progress["online_seconds"]) / 60.0)
	spirit_progress["online_seconds"] = float(spirit_progress["online_seconds"]) + delta
	var current_minutes := int(float(spirit_progress["online_seconds"]) / 60.0)
	if current_minutes > previous_minutes:
		_grant_spirit_xp(
			(current_minutes - previous_minutes) * SPIRIT_XP_PER_ONLINE_MINUTE,
		)

	_spirit_save_elapsed += delta
	if _spirit_save_elapsed >= 30.0:
		_spirit_save_elapsed = 0.0
		_save_spirit_progress()


func _exit_tree() -> void:
	_save_program_drafts()
	_save_spirit_progress()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_return_to_home()
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


func _return_to_home() -> void:
	var scene_tree := get_tree()
	if scene_tree == null or scene_tree.current_scene == null:
		return
	if scene_tree.current_scene.scene_file_path == HOME_SCENE_PATH:
		return
	_mark_input_handled()
	scene_tree.change_scene_to_file(HOME_SCENE_PATH)


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


func apply_font_scale(root: Node) -> void:
	_apply_font_scale_to_node(root)


func apply_color_mode(root: Node) -> void:
	_apply_color_mode_to_node(root)


func get_foreground_color() -> Color:
	return DARK_FOREGROUND if dark_mode else LIGHT_FOREGROUND


func get_background_color() -> Color:
	return DARK_BACKGROUND if dark_mode else LIGHT_BACKGROUND


func get_spirit_progress() -> Dictionary:
	return spirit_progress.duplicate(true)


func get_spirit_level_progress() -> int:
	return int(spirit_progress["xp"]) % SPIRIT_XP_PER_LEVEL


func register_quiz_answer(is_correct: bool) -> void:
	if is_correct:
		spirit_progress["correct_answers"] = int(spirit_progress["correct_answers"]) + 1
		_grant_spirit_xp(SPIRIT_XP_CORRECT)
	else:
		spirit_progress["wrong_answers"] = int(spirit_progress["wrong_answers"]) + 1
		_grant_spirit_xp(SPIRIT_XP_WRONG)
	_save_spirit_progress()


func register_spirit_interaction() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_interaction_msec < SPIRIT_INTERACTION_COOLDOWN_MSEC:
		return false
	_last_interaction_msec = now
	spirit_progress["interactions"] = int(spirit_progress["interactions"]) + 1
	_grant_spirit_xp(SPIRIT_XP_INTERACTION)
	_save_spirit_progress()
	return true


func _apply_font_scale_to_node(node: Node) -> void:
	if node is Control:
		_apply_font_size(node, "font_size")
		if node is RichTextLabel:
			_apply_font_size(node, "normal_font_size")
	for child in node.get_children(true):
		_apply_font_scale_to_node(child)


func _apply_font_size(control: Control, theme_name: String) -> void:
	var meta_name := "base_" + theme_name
	if not control.has_meta(meta_name):
		control.set_meta(meta_name, control.get_theme_font_size(theme_name))
	var base_size := int(control.get_meta(meta_name))
	control.add_theme_font_size_override(theme_name, max(1, roundi(base_size * font_scale)))


func _apply_color_mode_to_node(node: Node) -> void:
	var foreground := get_foreground_color()
	var disabled_foreground := (
		DARK_DISABLED_FOREGROUND if dark_mode else LIGHT_DISABLED_FOREGROUND
	)

	if node is ColorRect and node.name == "Background":
		node.color = get_background_color()
	elif node is Button:
		_apply_button_colors(node, foreground, disabled_foreground)
	elif node is RichTextLabel:
		node.add_theme_color_override("default_color", foreground)
		node.add_theme_color_override(
			"font_selected_color",
			get_background_color(),
		)
		node.add_theme_color_override(
			"selection_color",
			Color(1.0, 1.0, 1.0, 0.28)
			if dark_mode
			else Color(0.0, 0.0, 0.0, 0.22),
		)
	elif node is Label:
		node.add_theme_color_override("font_color", foreground)
	elif node is ItemList:
		for color_name in [
			"font_color",
			"font_hovered_color",
			"font_hovered_selected_color",
			"font_outline_color",
			"font_selected_color",
			"font_selected_outline_color",
		]:
			node.add_theme_color_override(color_name, foreground)
	elif node is LineEdit:
		node.add_theme_color_override("font_color", foreground)
		node.add_theme_color_override("font_selected_color", get_background_color())
		node.add_theme_color_override("caret_color", foreground)
		node.add_theme_color_override(
			"selection_color",
			Color(1.0, 1.0, 1.0, 0.28)
			if dark_mode
			else Color(0.0, 0.0, 0.0, 0.22),
		)

	for child in node.get_children(true):
		_apply_color_mode_to_node(child)


func _apply_button_colors(
	button: Button,
	foreground: Color,
	disabled_foreground: Color,
) -> void:
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color",
	]:
		button.add_theme_color_override(color_name, foreground)
	button.add_theme_color_override("font_disabled_color", disabled_foreground)


func _grant_spirit_xp(amount: int) -> void:
	if amount <= 0:
		return
	spirit_progress["xp"] = int(spirit_progress["xp"]) + amount
	spirit_progress["level"] = 1 + int(
		floor(float(spirit_progress["xp"]) / float(SPIRIT_XP_PER_LEVEL))
	)
	spirit_progress_changed.emit()


func _load_spirit_progress() -> void:
	if not FileAccess.file_exists(SPIRIT_PROGRESS_PATH):
		return
	var file := FileAccess.open(SPIRIT_PROGRESS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for key in spirit_progress.keys():
		if parsed.has(key):
			spirit_progress[key] = parsed[key]
	spirit_progress["online_seconds"] = maxf(
		0.0,
		float(spirit_progress["online_seconds"]),
	)
	for key in ["xp", "correct_answers", "wrong_answers", "interactions"]:
		spirit_progress[key] = maxi(0, int(spirit_progress[key]))
	spirit_progress["level"] = 1 + int(
		floor(float(spirit_progress["xp"]) / float(SPIRIT_XP_PER_LEVEL))
	)


func _save_spirit_progress() -> void:
	var file := FileAccess.open(SPIRIT_PROGRESS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(spirit_progress, "  "))
