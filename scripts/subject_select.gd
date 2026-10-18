extends Control

const HEBUT_BLUE := Color("#092C87")
const LIGHT_BACKGROUND := Color("#F7F9FD")
const LIGHT_SURFACE := Color("#FFFFFF")
const LIGHT_BORDER := Color("#DDE5F1")
const LIGHT_TEXT := Color("#11203A")
const DARK_BACKGROUND := Color("#0B1220")
const DARK_SURFACE := Color("#151F32")
const DARK_SURFACE_HOVER := Color("#1C2A42")
const DARK_BORDER := Color("#2C3D59")
const DARK_TEXT := Color("#E8EEF8")
const DARK_ACCENT := Color("#6D92FF")
const LIGHT_COUNT := Color("#7D8BA1")
const DARK_COUNT := Color("#93A1B8")

var wrong_count_labels: Dictionary = {}

@onready var marxism_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/MarxismButton
@onready var mao_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/MaoButton
@onready var xi_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/XiButton
@onready var matlab_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/MatlabButton
@onready var python_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/PythonButton
@onready var cpp_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/CppButton
@onready var back_button: Button = $PageMargin/PageColumn/BackButtonContainer/BackButton
@onready var background: ColorRect = $Background
@onready var title_label: Label = $PageMargin/PageColumn/Title


func _ready() -> void:
	marxism_button.pressed.connect(_select_subject.bind("marxism"))
	mao_button.pressed.connect(_select_subject.bind("mao"))
	xi_button.pressed.connect(_select_subject.bind("xi"))
	matlab_button.pressed.connect(_select_subject.bind("matlab"))
	python_button.pressed.connect(_select_subject.bind("python"))
	cpp_button.pressed.connect(_select_subject.bind("cpp"))
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"))
	_setup_wrong_counts()
	_app_state().font_scale_changed.connect(_on_font_scale_changed)
	_app_state().color_mode_changed.connect(_on_color_mode_changed)
	_app_state().apply_font_scale(self)
	_app_state().apply_color_mode(self)
	_apply_page_palette()


func _setup_wrong_counts() -> void:
	if _app_state().quiz_mode != "wrong":
		return
	title_label.text = "错题库"
	var buttons := {
		"marxism": marxism_button, "mao": mao_button, "xi": xi_button,
		"matlab": matlab_button, "python": python_button, "cpp": cpp_button,
	}
	for subject_id in buttons:
		var button: Button = buttons[subject_id]
		var count := Label.new()
		count.name = "WrongCount"
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 36)
		button.add_child(count)
		count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wrong_count_labels[subject_id] = count
	_refresh_wrong_counts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and not wrong_count_labels.is_empty():
		_refresh_wrong_counts()


func _refresh_wrong_counts() -> void:
	for subject_id in wrong_count_labels:
		var path: String = _app_state().SUBJECTS[subject_id]["wrong_path"]
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		var count: int = parsed.size() if parsed is Array else 0
		wrong_count_labels[subject_id].text = "%d 道" % count
	_layout_wrong_counts()


func _layout_wrong_counts() -> void:
	var scale: float = _app_state().font_scale
	var count_width := 0.0
	for count: Label in wrong_count_labels.values():
		count.offset_left = 48.0 * scale
		count.offset_right = -48.0 * scale
		var font := count.get_theme_font("font")
		var font_size := count.get_theme_font_size("font_size")
		count_width = maxf(count_width, font.get_string_size(count.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	# Reserve equal space on both sides to keep course names centered at larger font sizes.
	var padding := count_width + 72.0 * scale
	for count: Label in wrong_count_labels.values():
		var button: Button = count.get_parent()
		for style_name in ["normal", "hover", "pressed", "focus"]:
			var style := button.get_theme_stylebox(style_name).duplicate() as StyleBox
			style.content_margin_left = padding
			style.content_margin_right = padding
			button.add_theme_stylebox_override(style_name, style)


func _select_subject(subject_id: String) -> void:
	var app_state := _app_state()
	app_state.subject_id = subject_id
	app_state.start_index = 0
	get_tree().change_scene_to_file("res://scenes/Quiz.tscn")


func _app_state() -> Node:
	return get_node("/root/AppState")


func _on_font_scale_changed(_scale: float) -> void:
	_app_state().apply_font_scale(self)
	_layout_wrong_counts()


func _on_color_mode_changed(_is_dark: bool) -> void:
	_app_state().apply_color_mode(self)
	_apply_page_palette()


func _apply_page_palette() -> void:
	var is_dark: bool = _app_state().dark_mode
	background.color = DARK_BACKGROUND if is_dark else LIGHT_BACKGROUND
	title_label.add_theme_color_override(
		"font_color",
		DARK_TEXT if is_dark else LIGHT_TEXT,
	)
	for button in [marxism_button, mao_button, xi_button, matlab_button, python_button, cpp_button]:
		_apply_button_palette(button, false, is_dark)
	_apply_button_palette(back_button, true, is_dark)
	for count: Label in wrong_count_labels.values():
		count.add_theme_color_override("font_color", DARK_COUNT if is_dark else LIGHT_COUNT)
	_layout_wrong_counts()


func _apply_button_palette(
	button: Button,
	is_primary: bool,
	is_dark: bool,
) -> void:
	var background_color := (
		(DARK_ACCENT if is_dark else HEBUT_BLUE)
		if is_primary
		else (DARK_SURFACE if is_dark else LIGHT_SURFACE)
	)
	var hover_color := (
		background_color.lightened(0.10)
		if is_primary
		else (DARK_SURFACE_HOVER if is_dark else Color("#F0F4FC"))
	)
	var border_color := (
		background_color
		if is_primary
		else (DARK_BORDER if is_dark else LIGHT_BORDER)
	)
	var font_color := (
		Color.WHITE
		if is_primary
		else (DARK_TEXT if is_dark else LIGHT_TEXT)
	)
	_set_button_colors(button, font_color)
	button.add_theme_stylebox_override(
		"normal",
		_subject_button_style(background_color, border_color, is_dark),
	)
	button.add_theme_stylebox_override(
		"hover",
		_subject_button_style(hover_color, border_color.lightened(0.12), is_dark),
	)
	button.add_theme_stylebox_override(
		"pressed",
		_subject_button_style(hover_color.darkened(0.04), border_color, is_dark),
	)
	button.add_theme_stylebox_override(
		"focus",
		_subject_button_style(background_color, border_color, is_dark),
	)


func _subject_button_style(
	background_color: Color,
	border_color: Color,
	is_dark: bool,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0, 0, 0, 0.20 if is_dark else 0.06)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 3)
	return style


func _set_button_colors(button: Button, color: Color) -> void:
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color",
	]:
		button.add_theme_color_override(color_name, color)
