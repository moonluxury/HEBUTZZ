extends Control

const CONTENT_PATH := "res://data/hegong_kaiwu.json"
const HOME_SCENE_PATH := "res://scenes/HegongKaiwu.tscn"
const HEGONG_BASE_FONT_SIZE := 36
const HEGONG_MIN_FONT_SIZE := 25
const HEGONG_MAX_FONT_SIZE := 42
const MICRO_DURATION := 0.26
const INTRO_DURATION := 0.32
const HEBUT_BLUE := Color("#092C87")
const LIGHT_BACKGROUND := Color("#F7F9FD")
const LIGHT_SURFACE := Color("#FFFFFF")
const LIGHT_BORDER := Color("#DDE5F1")
const LIGHT_TEXT := Color("#11203A")
const LIGHT_MUTED := Color("#66738A")
const DARK_BACKGROUND := Color("#0B1220")
const DARK_SURFACE := Color("#151F32")
const DARK_SURFACE_ALT := Color("#19263A")
const DARK_SURFACE_HOVER := Color("#20314B")
const DARK_BORDER := Color("#2C3D59")
const DARK_TEXT := Color("#E8EEF8")
const DARK_MUTED := Color("#9EADC3")
const DARK_ACCENT := Color("#6D92FF")

var article_card_base_y := 0.0
var article_card_tween: Tween
var card_hover_enabled := false
var returning_home := false

@onready var header: VBoxContainer = $PageColumn/Header
@onready var background: ColorRect = $Background
@onready var title_label: Label = $PageColumn/Header/Title
@onready var header_divider: ColorRect = $PageColumn/HeaderDivider
@onready var article_card: PanelContainer = $PageColumn/BodyMargin/ArticleCard
@onready var article_title: Label = $PageColumn/BodyMargin/ArticleCard/ArticleColumn/ArticleTitle
@onready var category_label: Label = $PageColumn/BodyMargin/ArticleCard/ArticleColumn/CategoryLabel
@onready var content_label: RichTextLabel = $PageColumn/BodyMargin/ArticleCard/ArticleColumn/ContentLabel
@onready var article_divider: ColorRect = $PageColumn/BodyMargin/ArticleCard/ArticleColumn/ArticleDivider
@onready var back_button: Button = $PageColumn/BodyMargin/ArticleCard/ArticleColumn/FooterRow/BackButton


func _ready() -> void:
	back_button.pressed.connect(_return_home)
	article_card.mouse_entered.connect(_animate_article_card.bind(true))
	article_card.mouse_exited.connect(_animate_article_card.bind(false))
	var article: Dictionary = get_node("/root/AppState").hegong_kaiwu_article
	if article.is_empty():
		article = _load_default_article()
	_show_article(article)
	_app_state().font_scale_changed.connect(_on_font_scale_changed)
	_app_state().color_mode_changed.connect(_on_color_mode_changed)
	_apply_responsive_font_size(self)
	_app_state().apply_color_mode(self)
	_apply_page_palette()
	_play_intro_animation.call_deferred()


func _load_default_article() -> Dictionary:
	if not FileAccess.file_exists(CONTENT_PATH):
		return {}
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_ARRAY and not parsed.is_empty():
		return parsed[0] if typeof(parsed[0]) == TYPE_DICTIONARY else {}
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if parsed.has("articles") and typeof(parsed["articles"]) == TYPE_ARRAY:
		var articles: Array = parsed["articles"]
		if not articles.is_empty() and typeof(articles[0]) == TYPE_DICTIONARY:
			return articles[0]
	if parsed.has("items") and typeof(parsed["items"]) == TYPE_ARRAY:
		var items: Array = parsed["items"]
		if not items.is_empty() and typeof(items[0]) == TYPE_DICTIONARY:
			return items[0]
	return parsed if parsed.has("title") else {}


func _show_article(article: Dictionary) -> void:
	if article.is_empty():
		article_title.text = "暂无内容"
		category_label.text = ""
		content_label.text = "请返回首页后重新选择内容。"
		return

	article_title.text = str(article.get("title", "未命名内容"))
	var category := str(article.get("category", "未分类"))
	var content_type := str(article.get("type", "")).strip_edges()
	category_label.text = (
		"◇  分类：%s" % category
		if content_type.is_empty()
		else "◇  分类：%s  ·  类型：%s" % [category, content_type]
	)
	content_label.text = str(article.get("content", ""))
	content_label.scroll_to_line(0)


func _return_home() -> void:
	if returning_home:
		return
	returning_home = true
	await _play_button_click(back_button)
	get_tree().change_scene_to_file(HOME_SCENE_PATH)


func _play_intro_animation() -> void:
	header.modulate.a = 0.0
	article_card_base_y = article_card.position.y
	article_card.position.y = article_card_base_y + 10.0
	article_card.modulate.a = 0.0

	var header_tween := create_tween()
	header_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	header_tween.tween_property(header, "modulate:a", 1.0, INTRO_DURATION)

	var card_tween := create_tween()
	card_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	card_tween.tween_interval(0.10)
	card_tween.tween_property(
		article_card,
		"position:y",
		article_card_base_y,
		INTRO_DURATION,
	)
	card_tween.parallel().tween_property(
		article_card,
		"modulate:a",
		1.0,
		INTRO_DURATION,
	)

	await get_tree().create_timer(0.46).timeout
	card_hover_enabled = true


func _animate_article_card(is_hovered: bool) -> void:
	if not card_hover_enabled:
		return
	if article_card_tween != null and article_card_tween.is_valid():
		article_card_tween.kill()
	article_card_tween = create_tween()
	article_card_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	article_card_tween.tween_property(
		article_card,
		"position:y",
		article_card_base_y - 3.0 if is_hovered else article_card_base_y,
		MICRO_DURATION,
	)


func _apply_page_palette() -> void:
	var is_dark := bool(_app_state().dark_mode)
	var surface_color := DARK_SURFACE if is_dark else LIGHT_SURFACE
	var border_color := DARK_BORDER if is_dark else LIGHT_BORDER
	var text_color := DARK_TEXT if is_dark else LIGHT_TEXT
	var muted_color := DARK_MUTED if is_dark else LIGHT_MUTED
	var accent_color := DARK_ACCENT if is_dark else HEBUT_BLUE
	background.color = DARK_BACKGROUND if is_dark else LIGHT_BACKGROUND
	title_label.add_theme_color_override("font_color", accent_color)
	header_divider.color = border_color
	article_divider.color = border_color
	article_card.add_theme_stylebox_override(
		"panel",
		_article_surface_style(surface_color, border_color, is_dark),
	)
	article_title.add_theme_color_override("font_color", text_color)
	category_label.add_theme_color_override("font_color", muted_color)
	content_label.add_theme_color_override("default_color", text_color)
	_apply_back_button_palette(is_dark)


func _article_surface_style(
	background_color: Color,
	border_color: Color,
	is_dark: bool,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 32.0
	style.content_margin_top = 32.0
	style.content_margin_right = 32.0
	style.content_margin_bottom = 32.0
	style.shadow_color = Color(0, 0, 0, 0.24 if is_dark else 0.08)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


func _apply_back_button_palette(is_dark: bool) -> void:
	var background_color := DARK_SURFACE_ALT if is_dark else Color.WHITE
	var hover_color := DARK_SURFACE_HOVER if is_dark else Color("#EEF3FF")
	var border_color := DARK_BORDER if is_dark else LIGHT_BORDER
	var text_color := DARK_TEXT if is_dark else HEBUT_BLUE
	var hover_text := DARK_ACCENT if is_dark else HEBUT_BLUE
	_set_button_colors(back_button, text_color, hover_text)
	for state_name in ["normal", "focus"]:
		back_button.add_theme_stylebox_override(
			state_name,
			_back_button_style(background_color, border_color, is_dark),
		)
	for state_name in ["hover", "pressed"]:
		back_button.add_theme_stylebox_override(
			state_name,
			_back_button_style(hover_color, hover_text, is_dark),
		)


func _back_button_style(
	background_color: Color,
	border_color: Color,
	is_dark: bool,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.shadow_color = Color(0, 0, 0, 0.16 if is_dark else 0.0)
	style.shadow_size = 5 if is_dark else 0
	style.shadow_offset = Vector2(0, 2)
	return style


func _set_button_colors(
	button: Button,
	normal_color: Color,
	hover_color: Color,
) -> void:
	button.add_theme_color_override("font_color", normal_color)
	button.add_theme_color_override("font_focus_color", normal_color)
	button.add_theme_color_override("font_disabled_color", normal_color.darkened(0.20))
	button.add_theme_color_override("font_hover_color", hover_color)
	button.add_theme_color_override("font_pressed_color", hover_color)
	button.add_theme_color_override("font_hover_pressed_color", hover_color)


func _apply_responsive_font_size(node: Node) -> void:
	var font_size := clampi(
		roundi(HEGONG_BASE_FONT_SIZE * float(_app_state().font_scale)),
		HEGONG_MIN_FONT_SIZE,
		HEGONG_MAX_FONT_SIZE,
	)
	if node is Control:
		var control := node as Control
		control.add_theme_font_size_override("font_size", font_size)
		if control is RichTextLabel:
			control.add_theme_font_size_override(
				"normal_font_size",
				font_size,
			)
	for child in node.get_children(true):
		_apply_responsive_font_size(child)


func _on_font_scale_changed(_scale: float) -> void:
	_apply_responsive_font_size(self)


func _on_color_mode_changed(_is_dark: bool) -> void:
	_app_state().apply_color_mode(self)
	_apply_page_palette()


func _app_state() -> Node:
	return get_node("/root/AppState")


func _play_button_click(button: Control) -> void:
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(0.96, 0.96), 0.10)
	tween.tween_property(button, "scale", Vector2.ONE, 0.14)
	await tween.finished
