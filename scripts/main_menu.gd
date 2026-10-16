extends Control

const HEBUT_BLUE := Color("#092C87")
const LIGHT_BACKGROUND := Color("#F7F9FD")
const LIGHT_SURFACE := Color("#FFFFFF")
const LIGHT_BORDER := Color("#DDE5F1")
const LIGHT_TEXT := Color("#11203A")
const LIGHT_MUTED := Color("#66738A")
const DARK_BACKGROUND := Color("#0B1220")
const DARK_SURFACE := Color("#151F32")
const DARK_SURFACE_HOVER := Color("#1C2A42")
const DARK_BORDER := Color("#2C3D59")
const DARK_TEXT := Color("#E8EEF8")
const DARK_MUTED := Color("#9EADC3")
const DARK_ACCENT := Color("#416ED8")

@onready var all_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonRow/AllButton
@onready var wrong_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonRow/WrongButton
@onready var kaiwu_button: Button = $PageMargin/PageColumn/FeatureCenter/FeatureRow/KaiwuButton
@onready var spirit_button: Button = $PageMargin/PageColumn/FeatureCenter/FeatureRow/SpiritButton
@onready var wrong_status: Label = $PageMargin/PageColumn/WrongStatusMargin/WrongStatus
@onready var background: ColorRect = $Background
@onready var title_label: Label = $PageMargin/PageColumn/Title
@onready var welcome_label: Label = $PageMargin/PageColumn/SubtitleRow/WelcomeLabel
@onready var brand_label: Label = $PageMargin/PageColumn/SubtitleRow/BrandLabel


func _ready() -> void:
	all_button.pressed.connect(_open_subject_selector.bind("all"))
	wrong_button.pressed.connect(_open_subject_selector.bind("wrong"))
	kaiwu_button.pressed.connect(
		func(): get_tree().change_scene_to_file("res://scenes/HegongKaiwu.tscn")
	)
	spirit_button.pressed.connect(
		func(): get_tree().change_scene_to_file("res://scenes/MySpirit.tscn")
	)
	_refresh_wrong_counts()
	_app_state().font_scale_changed.connect(_on_font_scale_changed)
	_app_state().color_mode_changed.connect(_on_color_mode_changed)
	_app_state().apply_font_scale(self)
	_app_state().apply_color_mode(self)
	_apply_page_palette()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_instance_valid(wrong_status):
		_refresh_wrong_counts()


func _refresh_wrong_counts() -> void:
	var subjects: Dictionary = _app_state().SUBJECTS
	var marxism_count := _load_json_array(subjects["marxism"]["wrong_path"]).size()
	var mao_count := _load_json_array(subjects["mao"]["wrong_path"]).size()
	var xi_count := _load_json_array(subjects["xi"]["wrong_path"]).size()
	wrong_status.text = "马克思主义原理错题：%d 道\n毛泽东思想和中国特色社会主义错题：%d 道\n习近平新时代中国特色社会主义思想概论错题：%d 道" % [
		marxism_count,
		mao_count,
		xi_count,
	]


func _open_subject_selector(mode: String) -> void:
	var app_state := _app_state()
	app_state.quiz_mode = mode
	app_state.start_index = 0
	get_tree().change_scene_to_file("res://scenes/SubjectSelect.tscn")


func _app_state() -> Node:
	return get_node("/root/AppState")


func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func _on_font_scale_changed(_scale: float) -> void:
	_app_state().apply_font_scale(self)


func _on_color_mode_changed(_is_dark: bool) -> void:
	_app_state().apply_color_mode(self)
	_apply_page_palette()


func _apply_page_palette() -> void:
	var is_dark: bool = _app_state().dark_mode
	var page_background := DARK_BACKGROUND if is_dark else LIGHT_BACKGROUND
	var text_color := DARK_TEXT if is_dark else LIGHT_TEXT
	var muted_color := DARK_MUTED if is_dark else LIGHT_MUTED
	background.color = page_background
	title_label.add_theme_color_override("font_color", text_color)
	welcome_label.add_theme_color_override("font_color", muted_color)
	brand_label.add_theme_color_override(
		"font_color",
		Color("#8EACFF") if is_dark else HEBUT_BLUE,
	)
	wrong_status.add_theme_color_override("font_color", muted_color)

	_apply_button_palette(all_button, true, is_dark)
	for button in [wrong_button, kaiwu_button, spirit_button]:
		_apply_button_palette(button, false, is_dark)


func _apply_button_palette(
	button: Button,
	is_primary: bool,
	is_dark: bool,
) -> void:
	var normal_background: Color
	var hover_background: Color
	var border_color: Color
	var font_color: Color
	if is_primary:
		normal_background = DARK_ACCENT if is_dark else HEBUT_BLUE
		hover_background = normal_background.lightened(0.10)
		border_color = normal_background
		font_color = Color.WHITE
	else:
		normal_background = DARK_SURFACE if is_dark else LIGHT_SURFACE
		hover_background = DARK_SURFACE_HOVER if is_dark else Color("#F0F4FC")
		border_color = DARK_BORDER if is_dark else LIGHT_BORDER
		font_color = DARK_TEXT if is_dark else LIGHT_TEXT

	_set_button_colors(button, font_color)
	button.add_theme_stylebox_override(
		"normal",
		_menu_button_style(normal_background, border_color, is_dark),
	)
	button.add_theme_stylebox_override(
		"hover",
		_menu_button_style(hover_background, border_color.lightened(0.12), is_dark),
	)
	button.add_theme_stylebox_override(
		"pressed",
		_menu_button_style(hover_background.darkened(0.04), border_color, is_dark),
	)
	button.add_theme_stylebox_override(
		"focus",
		_menu_button_style(normal_background, border_color, is_dark),
	)


func _menu_button_style(
	background_color: Color,
	border_color: Color,
	is_dark: bool,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0, 0, 0, 0.22 if is_dark else 0.07)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
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
