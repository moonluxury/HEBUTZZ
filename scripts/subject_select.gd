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

@onready var marxism_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/MarxismButton
@onready var mao_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/MaoButton
@onready var xi_button: Button = $PageMargin/PageColumn/ButtonCenter/ButtonColumn/XiButton
@onready var back_button: Button = $PageMargin/PageColumn/BackButtonContainer/BackButton
@onready var background: ColorRect = $Background
@onready var title_label: Label = $PageMargin/PageColumn/Title


func _ready() -> void:
	marxism_button.pressed.connect(_select_subject.bind("marxism"))
	mao_button.pressed.connect(_select_subject.bind("mao"))
	xi_button.pressed.connect(_select_subject.bind("xi"))
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"))
	_app_state().font_scale_changed.connect(_on_font_scale_changed)
	_app_state().color_mode_changed.connect(_on_color_mode_changed)
	_app_state().apply_font_scale(self)
	_app_state().apply_color_mode(self)
	_apply_page_palette()


func _select_subject(subject_id: String) -> void:
	var app_state := _app_state()
	app_state.subject_id = subject_id
	app_state.start_index = 0
	get_tree().change_scene_to_file("res://scenes/Quiz.tscn")


func _app_state() -> Node:
	return get_node("/root/AppState")


func _on_font_scale_changed(_scale: float) -> void:
	_app_state().apply_font_scale(self)


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
	for button in [marxism_button, mao_button, xi_button]:
		_apply_button_palette(button, false, is_dark)
	_apply_button_palette(back_button, true, is_dark)


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
