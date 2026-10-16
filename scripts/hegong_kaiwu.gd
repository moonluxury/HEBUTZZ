extends Control

const SearchResultsView = preload("res://scripts/hegong_search_results.gd")
const CONTENT_PATH := "res://data/hegong_kaiwu.json"
const DEMO_CONTENT_PATH := "res://data/hegong_kaiwu_demo.json"
const DETAIL_SCENE_PATH := "res://scenes/HegongKaiwuDetail.tscn"
const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
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
const DARK_ACCENT_SURFACE := Color("#21375B")
const DARK_PRIMARY := Color("#315CCB")
const ALL_CATEGORY_LABEL := "全部类型"
const CONTENT_CATEGORIES: Array[String] = ["复习资料", "校园故事", "优秀文章"]
const HEGONG_BASE_FONT_SIZE := 36
const HEGONG_MIN_FONT_SIZE := 25
const HEGONG_MAX_FONT_SIZE := 42
const ANNOUNCEMENT_BUTTON_FONT_SIZE := 30
const ANNOUNCEMENT_MORPH_DURATION := 0.40
const ANNOUNCEMENT_DOT_DURATION := 0.14
const MICRO_DURATION := 0.26
const INTRO_DURATION := 0.32


class AnnouncementMorphIcon:
	extends Control

	var morph_progress := 0.0:
		set(value):
			morph_progress = clampf(value, 0.0, 1.0)
			queue_redraw()
	var dot_progress := 0.0:
		set(value):
			dot_progress = clampf(value, 0.0, 1.0)
			queue_redraw()
	var stroke_color := Color("#092C87"):
		set(value):
			stroke_color = value
			queue_redraw()

	func _draw() -> void:
		var icon_size := minf(size.x, size.y) - 5.0
		var origin := (size - Vector2(icon_size, icon_size)) * 0.5
		var diamond := [
			Vector2(0.5, 0.0),
			Vector2(1.0, 0.5),
			Vector2(0.5, 1.0),
			Vector2(0.0, 0.5),
		]
		var square := [
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
			Vector2(1.0, 1.0),
			Vector2(0.0, 1.0),
		]
		var points := PackedVector2Array()
		for index in diamond.size():
			points.append(
				origin
				+ diamond[index].lerp(square[index], morph_progress)
				* icon_size,
			)
		points.append(points[0])
		draw_polyline(points, stroke_color, 3.0, true)
		if dot_progress > 0.0:
			draw_circle(
				size * 0.5,
				3.5 * dot_progress,
				Color(stroke_color, dot_progress),
				true,
				-1.0,
				true,
			)


var hebut_blue_hover := HEBUT_BLUE.lightened(0.12)
var categories: Array[String] = []
var entries: Array[Dictionary] = []
var visible_entries: Array[Dictionary] = []
var selected_category := ""
var current_entry: Dictionary = {}
var category_panel: PanelContainer
var category_column: VBoxContainer
var category_close_timer: Timer
var category_tween: Tween
var announcement_panel: PanelContainer
var announcement_title: Label
var announcement_content: Label
var announcement_divider: ColorRect
var announcement_close_timer: Timer
var announcement_tween: Tween
var active_announcement_button: Button
var announcement_button_tweens := {}
var announcement_button_icons := {}
var search_button_tween: Tween
var search_button_style: StyleBoxFlat
var card_tweens: Dictionary = {}
var card_base_y: Dictionary = {}
var card_hover_enabled := false
var returning_home := false

@onready var category_button: Button = $PageMargin/PageColumn/SearchBarBackground/SearchBarMargin/SearchCard/SearchRow/CategoryButton
@onready var search_edit: LineEdit = $PageMargin/PageColumn/SearchBarBackground/SearchBarMargin/SearchCard/SearchRow/SearchEdit
@onready var search_button: Button = $PageMargin/PageColumn/SearchBarBackground/SearchBarMargin/SearchCard/SearchRow/SearchButton
@onready var submission_button: Button = $PageMargin/PageColumn/ContentMargin/ContentRow/AnnouncementCard/AnnouncementColumn/SubmissionButton
@onready var report_button: Button = $PageMargin/PageColumn/ContentMargin/ContentRow/AnnouncementCard/AnnouncementColumn/ReportButton
@onready var header: VBoxContainer = $PageMargin/PageColumn/Header
@onready var title_label: Label = $PageMargin/PageColumn/Header/Title
@onready var subtitle_label: Label = $PageMargin/PageColumn/Header/Subtitle
@onready var background: ColorRect = $Background
@onready var campus_background: TextureRect = $PageMargin/PageColumn/SearchBarBackground/CampusBackground
@onready var search_card: PanelContainer = $PageMargin/PageColumn/SearchBarBackground/SearchBarMargin/SearchCard
@onready var announcement_card: PanelContainer = $PageMargin/PageColumn/ContentMargin/ContentRow/AnnouncementCard
@onready var article_card: PanelContainer = $PageMargin/PageColumn/ContentMargin/ContentRow/ArticleCard
@onready var tips_card: PanelContainer = $PageMargin/PageColumn/ContentMargin/ContentRow/TipsCard
@onready var article_icon: PanelContainer = $PageMargin/PageColumn/ContentMargin/ContentRow/ArticleCard/ArticleColumn/ArticleHeader/ArticleIcon
@onready var article_icon_label: Label = $PageMargin/PageColumn/ContentMargin/ContentRow/ArticleCard/ArticleColumn/ArticleHeader/ArticleIcon/IconLabel
@onready var tips_title: Label = $PageMargin/PageColumn/ContentMargin/ContentRow/TipsCard/TipsColumn/TipsTitle
@onready var article_divider: ColorRect = $PageMargin/PageColumn/ContentMargin/ContentRow/ArticleCard/ArticleColumn/ArticleDivider
@onready var footer_divider: ColorRect = $PageMargin/PageColumn/FooterMargin/FooterColumn/FooterDivider
@onready var article_title: Label = $PageMargin/PageColumn/ContentMargin/ContentRow/ArticleCard/ArticleColumn/ArticleHeader/ArticleTitle
@onready var content_label: RichTextLabel = $PageMargin/PageColumn/ContentMargin/ContentRow/ArticleCard/ArticleColumn/ContentLabel
@onready var search_results: SearchResultsView = $PageMargin/PageColumn/ContentMargin/ContentRow/ArticleCard/ArticleColumn/SearchResults
@onready var status_label: Label = $PageMargin/PageColumn/FooterMargin/FooterColumn/StatusRow/StatusLabel
@onready var back_button: Button = $PageMargin/PageColumn/FooterMargin/FooterColumn/StatusRow/BackButton


func _ready() -> void:
	_load_content()
	search_results.configure_categories(entries, CONTENT_CATEGORIES)
	search_results.category_selected.connect(_on_result_category_selected)
	search_results.filters_cleared.connect(_clear_search_filters)
	search_results.entry_opened.connect(_open_result_entry)
	_build_category_panel()
	_build_announcement_panel()
	_setup_announcement_button_icon(submission_button, "征稿公告")
	_setup_announcement_button_icon(report_button, "举报公告")
	category_button.mouse_entered.connect(_open_category_panel)
	category_button.mouse_exited.connect(_schedule_category_panel_close)
	submission_button.mouse_entered.connect(
		_animate_announcement_button.bind(submission_button, true),
	)
	submission_button.mouse_entered.connect(
		_open_announcement_panel.bind(
			submission_button,
			"征稿公告",
			"优秀的平台，离不开每一位工大人的共同建设与用心守护！\n"
			+ "现面向全体工大人长期征集优质稿件，期待你的校园故事、青春感悟、学习经验与精彩创意在这里被更多人看见！\n"
			+ "投稿邮箱：hebutxjkt@163.com。投稿时，请将邮件主题标注为“投稿名称—稿件类型”，并附上Word可修改版稿件，同时留下作者姓名及联系方式，便于后续沟通。\n"
			+ "稿件一经采用，可获得39—69元稿费；同一作者累计中稿超过3次后，此后每次中稿还将额外获得30元“优质作者赏金”！\n"
			+ "用文字记录工大故事，用热爱传递青春力量。期待每一份真诚表达，也期待与你一起，让这个属于工大人的平台更加精彩！",
		),
	)
	submission_button.mouse_exited.connect(
		_animate_announcement_button.bind(submission_button, false),
	)
	submission_button.mouse_exited.connect(_schedule_announcement_panel_close)
	report_button.mouse_entered.connect(
		_animate_announcement_button.bind(report_button, true),
	)
	report_button.mouse_entered.connect(
		_open_announcement_panel.bind(
			report_button,
			"举报公告",
			"本平台对违规、劣质内容始终坚持零容忍态度！\n"
			+ "为及时发现并处理违规内容、劣质内容，现面向全体用户开放举报通道。若你在使用过程中发现违反平台规定、内容质量低下、恶意灌水或影响正常浏览体验的信息，欢迎及时向我们反馈。\n"
			+ "举报时，请尽量提供相关内容截图、发布者信息及具体问题说明，并发送至举报渠道：732414720@qq.com。我们将认真核实每一条线索，并依据平台规则及时处理，同时严格保护举报人的个人信息。\n"
			+ "每一次勇敢发声，都是对优质内容的支持；每一次认真监督，都在让平台变得更加清朗、更有温度。让我们一起拒绝违规与敷衍，共同守护属于大家的优质交流空间！",
		),
	)
	report_button.mouse_exited.connect(
		_animate_announcement_button.bind(report_button, false),
	)
	report_button.mouse_exited.connect(_schedule_announcement_panel_close)
	search_button.pressed.connect(_run_search)
	search_button.mouse_entered.connect(_animate_search_button.bind(true))
	search_button.mouse_exited.connect(_animate_search_button.bind(false))
	search_edit.text_submitted.connect(_on_search_submitted)
	article_title.gui_input.connect(_on_article_gui_input)
	content_label.gui_input.connect(_on_article_gui_input)
	back_button.pressed.connect(_return_to_main)
	resized.connect(_position_category_panel)
	resized.connect(_position_announcement_panel)
	category_button.resized.connect(_position_category_panel)
	_prepare_search_button_animation()
	_connect_card_hover(announcement_card)
	_connect_card_hover(article_card)
	_connect_card_hover(tips_card)
	_apply_filters()
	_app_state().font_scale_changed.connect(_on_font_scale_changed)
	_app_state().color_mode_changed.connect(_on_color_mode_changed)
	_apply_responsive_font_size(self)
	_app_state().apply_color_mode(self)
	_apply_page_palette()
	_play_intro_animation.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if (
		category_panel == null
		or not category_panel.visible
		or not event is InputEventMouseButton
		or not event.pressed
	):
		return
	var mouse_position := get_global_mouse_position()
	if (
		not category_button.get_global_rect().has_point(mouse_position)
		and not category_panel.get_global_rect().has_point(mouse_position)
	):
		_close_category_panel()


func _load_content() -> void:
	categories.clear()
	entries.clear()
	for content_path in [CONTENT_PATH, DEMO_CONTENT_PATH]:
		if not FileAccess.file_exists(content_path):
			continue
		var file := FileAccess.open(content_path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		var raw_entries: Array = []
		if typeof(parsed) == TYPE_ARRAY:
			raw_entries = parsed
		elif typeof(parsed) == TYPE_DICTIONARY:
			if parsed.has("articles") and typeof(parsed["articles"]) == TYPE_ARRAY:
				raw_entries = parsed["articles"]
			elif parsed.has("items") and typeof(parsed["items"]) == TYPE_ARRAY:
				raw_entries = parsed["items"]
			elif parsed.has("title"):
				raw_entries = [parsed]
		for raw_entry in raw_entries:
			if typeof(raw_entry) == TYPE_DICTIONARY:
				entries.append(raw_entry)

	_build_categories()


func _build_categories() -> void:
	categories = [ALL_CATEGORY_LABEL]
	categories.append_array(CONTENT_CATEGORIES)
	selected_category = ALL_CATEGORY_LABEL
	category_button.text = "%s  ﹀" % selected_category


func _build_category_panel() -> void:
	category_panel = PanelContainer.new()
	category_panel.name = "CategoryPanel"
	category_panel.z_index = 100
	category_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	category_panel.add_theme_stylebox_override("panel", _category_panel_style())
	category_panel.hide()
	add_child(category_panel)
	category_panel.mouse_entered.connect(_cancel_category_panel_close)
	category_panel.mouse_exited.connect(_schedule_category_panel_close)

	category_close_timer = Timer.new()
	category_close_timer.name = "CategoryCloseTimer"
	category_close_timer.one_shot = true
	category_close_timer.wait_time = 0.14
	category_close_timer.timeout.connect(_close_category_panel)
	add_child(category_close_timer)

	category_column = VBoxContainer.new()
	category_column.name = "CategoryColumn"
	category_column.add_theme_constant_override("separation", 0)
	category_panel.add_child(category_column)

	for category_name in categories:
		var option_button := Button.new()
		option_button.text = category_name
		option_button.custom_minimum_size = Vector2(0, 72)
		option_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		option_button.add_theme_font_size_override("font_size", 42)
		option_button.add_theme_color_override("font_color", Color("#1C263D"))
		option_button.add_theme_color_override("font_hover_color", HEBUT_BLUE)
		option_button.add_theme_color_override("font_pressed_color", HEBUT_BLUE)
		option_button.add_theme_stylebox_override("normal", _category_option_style(false))
		option_button.add_theme_stylebox_override("hover", _category_option_style(true))
		option_button.add_theme_stylebox_override("pressed", _category_option_style(true))
		option_button.add_theme_stylebox_override("focus", _category_option_style(false))
		option_button.pressed.connect(_select_category.bind(category_name))
		category_column.add_child(option_button)

	_position_category_panel.call_deferred()


func _build_announcement_panel() -> void:
	announcement_panel = PanelContainer.new()
	announcement_panel.name = "AnnouncementHoverPanel"
	announcement_panel.z_index = 110
	announcement_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	announcement_panel.custom_minimum_size = Vector2(720, 300)
	announcement_panel.add_theme_stylebox_override("panel", _category_panel_style())
	announcement_panel.hide()
	add_child(announcement_panel)
	announcement_panel.mouse_entered.connect(_cancel_announcement_panel_close)
	announcement_panel.mouse_exited.connect(_schedule_announcement_panel_close)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 24)
	panel_margin.add_theme_constant_override("margin_top", 20)
	panel_margin.add_theme_constant_override("margin_right", 24)
	panel_margin.add_theme_constant_override("margin_bottom", 20)
	announcement_panel.add_child(panel_margin)

	var panel_column := VBoxContainer.new()
	panel_column.add_theme_constant_override("separation", 14)
	panel_margin.add_child(panel_column)

	announcement_title = Label.new()
	announcement_title.add_theme_font_size_override("font_size", 42)
	announcement_title.add_theme_color_override("font_color", HEBUT_BLUE)
	panel_column.add_child(announcement_title)

	announcement_divider = ColorRect.new()
	announcement_divider.custom_minimum_size = Vector2(0, 1)
	announcement_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announcement_divider.color = Color("#E0E6F0")
	panel_column.add_child(announcement_divider)

	announcement_content = Label.new()
	announcement_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	announcement_content.add_theme_font_size_override("font_size", 42)
	announcement_content.add_theme_color_override("font_color", Color("#303A51"))
	announcement_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_column.add_child(announcement_content)

	announcement_close_timer = Timer.new()
	announcement_close_timer.name = "AnnouncementCloseTimer"
	announcement_close_timer.one_shot = true
	announcement_close_timer.wait_time = 0.14
	announcement_close_timer.timeout.connect(_close_announcement_panel)
	add_child(announcement_close_timer)


func _setup_announcement_button_icon(button: Button, caption: String) -> void:
	button.text = "      %s" % caption
	var icon := AnnouncementMorphIcon.new()
	icon.name = "MorphIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	icon.offset_left = 24.0
	icon.offset_top = -14.0
	icon.offset_right = 52.0
	icon.offset_bottom = 14.0
	button.add_child(icon)
	announcement_button_icons[button.get_instance_id()] = icon


func _animate_announcement_button(button: Button, is_hovered: bool) -> void:
	var tween_key := button.get_instance_id()
	if announcement_button_tweens.has(tween_key):
		var previous_tween: Tween = announcement_button_tweens[tween_key]
		if previous_tween != null and previous_tween.is_valid():
			previous_tween.kill()
	if not announcement_button_icons.has(tween_key):
		return
	var icon: AnnouncementMorphIcon = announcement_button_icons[tween_key]
	var tween := create_tween()
	announcement_button_tweens[tween_key] = tween
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_hovered:
		icon.stroke_color = Color.WHITE
		tween.tween_property(
			icon,
			"morph_progress",
			1.0,
			ANNOUNCEMENT_MORPH_DURATION,
		)
		tween.tween_property(
			icon,
			"dot_progress",
			1.0,
			ANNOUNCEMENT_DOT_DURATION,
		)
	else:
		icon.stroke_color = DARK_ACCENT if _is_dark_mode() else HEBUT_BLUE
		tween.tween_property(
			icon,
			"dot_progress",
			0.0,
			ANNOUNCEMENT_DOT_DURATION,
		)
		tween.tween_property(
			icon,
			"morph_progress",
			0.0,
			ANNOUNCEMENT_MORPH_DURATION,
		)


func _open_announcement_panel(
	button: Button,
	title_text: String,
	content_text: String,
) -> void:
	_cancel_announcement_panel_close()
	active_announcement_button = button
	announcement_title.text = title_text
	announcement_content.text = content_text
	_position_announcement_panel()

	if announcement_tween != null and announcement_tween.is_valid():
		announcement_tween.kill()
	var target_position := announcement_panel.global_position
	if announcement_panel.visible:
		announcement_panel.modulate.a = 1.0
		return

	announcement_panel.modulate.a = 0.0
	announcement_panel.global_position = target_position + Vector2(-5, 0)
	announcement_panel.show()
	announcement_tween = create_tween()
	announcement_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	announcement_tween.tween_property(
		announcement_panel,
		"global_position",
		target_position,
		MICRO_DURATION,
	)
	announcement_tween.parallel().tween_property(
		announcement_panel,
		"modulate:a",
		1.0,
		MICRO_DURATION,
	)


func _position_announcement_panel() -> void:
	if (
		announcement_panel == null
		or active_announcement_button == null
		or not is_instance_valid(active_announcement_button)
	):
		return
	var button_rect := active_announcement_button.get_global_rect()
	announcement_panel.global_position = Vector2(
		button_rect.end.x + 12.0,
		button_rect.position.y,
	)
	announcement_panel.size = Vector2(
		720.0,
		maxf(300.0, announcement_panel.get_combined_minimum_size().y),
	)


func _schedule_announcement_panel_close() -> void:
	if announcement_close_timer != null:
		announcement_close_timer.start()


func _cancel_announcement_panel_close() -> void:
	if announcement_close_timer != null:
		announcement_close_timer.stop()


func _close_announcement_panel() -> void:
	if announcement_panel == null or not announcement_panel.visible:
		return
	if announcement_tween != null and announcement_tween.is_valid():
		announcement_tween.kill()
	var target_position := announcement_panel.global_position + Vector2(-5, 0)
	announcement_tween = create_tween()
	announcement_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	announcement_tween.tween_property(
		announcement_panel,
		"global_position",
		target_position,
		0.20,
	)
	announcement_tween.parallel().tween_property(
		announcement_panel,
		"modulate:a",
		0.0,
		0.20,
	)
	announcement_tween.tween_callback(announcement_panel.hide)


func _category_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = DARK_SURFACE if _is_dark_mode() else Color.WHITE
	style.border_color = DARK_BORDER if _is_dark_mode() else Color("#D7DFED")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	style.shadow_color = (
		Color(0, 0, 0, 0.24)
		if _is_dark_mode()
		else Color(HEBUT_BLUE, 0.08)
	)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


func _category_option_style(is_hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		(DARK_SURFACE_HOVER if _is_dark_mode() else Color("#EEF3FF"))
		if is_hovered
		else Color.TRANSPARENT
	)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	return style


func _toggle_category_panel() -> void:
	if category_panel.visible:
		_close_category_panel()
		return
	_open_category_panel()


func _open_category_panel() -> void:
	_cancel_category_panel_close()
	if category_panel.visible:
		return
	_position_category_panel()
	if category_tween != null and category_tween.is_valid():
		category_tween.kill()
	var target_position := category_panel.global_position
	category_panel.modulate.a = 0.0
	category_panel.global_position = target_position + Vector2(0, -5)
	category_panel.show()
	category_tween = create_tween()
	category_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	category_tween.tween_property(
		category_panel,
		"global_position",
		target_position,
		MICRO_DURATION,
	)
	category_tween.parallel().tween_property(
		category_panel,
		"modulate:a",
		1.0,
		MICRO_DURATION,
	)


func _schedule_category_panel_close() -> void:
	if category_close_timer != null:
		category_close_timer.start()


func _cancel_category_panel_close() -> void:
	if category_close_timer != null:
		category_close_timer.stop()


func _close_category_panel() -> void:
	if category_panel == null or not category_panel.visible:
		return
	if category_tween != null and category_tween.is_valid():
		category_tween.kill()
	var target_position := category_panel.global_position - Vector2(0, 5)
	category_tween = create_tween()
	category_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	category_tween.tween_property(
		category_panel,
		"global_position",
		target_position,
		0.20,
	)
	category_tween.parallel().tween_property(
		category_panel,
		"modulate:a",
		0.0,
		0.20,
	)
	category_tween.tween_callback(category_panel.hide)


func _position_category_panel() -> void:
	if category_panel == null:
		return
	var button_rect := category_button.get_global_rect()
	category_panel.global_position = Vector2(
		button_rect.position.x,
		button_rect.end.y + 8.0,
	)
	category_panel.size = Vector2(
		button_rect.size.x,
		category_panel.get_combined_minimum_size().y,
	)


func _select_category(category_name: String) -> void:
	selected_category = category_name
	category_button.text = "%s  ﹀" % selected_category
	_close_category_panel()
	_apply_filters()


func _run_search() -> void:
	if category_panel != null:
		_close_category_panel()
	_apply_filters()


func _on_search_submitted(_query: String) -> void:
	_run_search()


func _on_result_category_selected(category: String) -> void:
	_select_category(ALL_CATEGORY_LABEL if category.is_empty() else category)


func _clear_search_filters() -> void:
	search_edit.clear()
	_select_category(ALL_CATEGORY_LABEL)


func _open_result_entry(entry: Dictionary) -> void:
	if bool(entry.get("demo", false)):
		return
	current_entry = entry
	_open_current_article()


func _apply_filters() -> void:
	visible_entries.clear()
	var query := search_edit.text.strip_edges().to_lower()
	var all_category := categories[0] if not categories.is_empty() else ""

	if query.is_empty() and selected_category == all_category:
		_show_search_welcome()
		return

	var matching_entries: Array[Dictionary] = []
	for entry in entries:
		if not query.is_empty() and not _entry_matches(entry, query):
			continue
		matching_entries.append(entry)
		if (
			not selected_category.is_empty()
			and selected_category != all_category
			and str(entry.get("category", "")) != selected_category
		):
			continue
		visible_entries.append(entry)

	status_label.text = "共找到 %d 条内容" % visible_entries.size()
	current_entry.clear()
	article_title.text = "河工开物智能检索"
	_set_article_interactive(false)
	search_results.show_results(visible_entries, "" if selected_category == all_category else selected_category, matching_entries)


func _show_search_welcome() -> void:
	current_entry.clear()
	visible_entries.assign(entries)
	article_title.text = "河工开物智能检索"
	status_label.text = "%d 条内容 · 输入标题、课程或关键词开始检索" % entries.size()
	_set_article_interactive(false)
	search_results.show_results(visible_entries, "", entries)


func _entry_matches(entry: Dictionary, query: String) -> bool:
	var searchable_parts: Array[String] = [
		str(entry.get("title", "")),
		str(entry.get("category", "")),
		str(entry.get("content", "")),
		str(entry.get("type", "")),
		str(entry.get("subtitle", "")),
		str(entry.get("summary", "")),
		str(entry.get("keywords", "")),
		str(entry.get("preview", "")),
	]
	return query in "\n".join(searchable_parts).to_lower()


func _show_entry(entry: Dictionary) -> void:
	current_entry = entry
	article_title.text = str(entry.get("title", "未命名内容"))
	content_label.text = str(entry.get("content", ""))
	content_label.scroll_to_line(0)
	_set_article_interactive(true)


func _set_article_interactive(is_interactive: bool) -> void:
	var cursor_shape := (
		Control.CURSOR_POINTING_HAND
		if is_interactive
		else Control.CURSOR_ARROW
	)
	var tooltip := "点击阅读完整内容" if is_interactive else ""
	article_title.mouse_default_cursor_shape = cursor_shape
	content_label.mouse_default_cursor_shape = cursor_shape
	article_title.tooltip_text = tooltip
	content_label.tooltip_text = tooltip


func _on_article_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_open_current_article()


func _open_current_article() -> void:
	if current_entry.is_empty():
		return
	var app_state := get_node("/root/AppState")
	app_state.hegong_kaiwu_article = current_entry.duplicate(true)
	get_tree().change_scene_to_file(DETAIL_SCENE_PATH)


func _prepare_search_button_animation() -> void:
	var normal_style := search_button.get_theme_stylebox("normal")
	if not normal_style is StyleBoxFlat:
		return
	search_button_style = normal_style.duplicate() as StyleBoxFlat
	search_button_style.shadow_size = 8
	search_button_style.shadow_offset = Vector2(0, 4)
	search_button_style.shadow_color = Color(HEBUT_BLUE, 0.0)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		search_button.add_theme_stylebox_override(state_name, search_button_style)


func _animate_search_button(is_hovered: bool) -> void:
	if search_button_style == null:
		return
	if search_button_tween != null and search_button_tween.is_valid():
		search_button_tween.kill()
	search_button_tween = create_tween()
	search_button_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var base_color := DARK_PRIMARY if _is_dark_mode() else HEBUT_BLUE
	search_button_tween.tween_property(
		search_button_style,
		"bg_color",
		base_color.lightened(0.12) if is_hovered else base_color,
		MICRO_DURATION,
	)
	search_button_tween.parallel().tween_property(
		search_button_style,
		"shadow_color",
		Color(base_color, 0.20) if is_hovered
		else Color(base_color, 0.0),
		MICRO_DURATION,
	)


func _connect_card_hover(card: Control) -> void:
	card.mouse_entered.connect(_animate_card_hover.bind(card, true))
	card.mouse_exited.connect(_animate_card_hover.bind(card, false))


func _animate_card_hover(card: Control, is_hovered: bool) -> void:
	if not card_hover_enabled or not card_base_y.has(card):
		return
	if card_tweens.has(card):
		var old_tween: Tween = card_tweens[card]
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()
	var tween := create_tween()
	card_tweens[card] = tween
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		card,
		"position:y",
		float(card_base_y[card]) - 3.0 if is_hovered else float(card_base_y[card]),
		MICRO_DURATION,
	)


func _play_intro_animation() -> void:
	var cards: Array[Control] = [announcement_card, article_card, tips_card]
	header.modulate.a = 0.0
	var search_base_y := search_card.position.y
	search_card.position.y = search_base_y + 12.0
	search_card.modulate.a = 0.0

	for card in cards:
		card_base_y[card] = card.position.y
		card.position.y += 8.0
		card.modulate.a = 0.0

	var header_tween := create_tween()
	header_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	header_tween.tween_property(header, "modulate:a", 1.0, INTRO_DURATION)

	var search_tween := create_tween()
	search_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	search_tween.tween_interval(0.06)
	search_tween.tween_property(
		search_card,
		"position:y",
		search_base_y,
		INTRO_DURATION,
	)
	search_tween.parallel().tween_property(
		search_card,
		"modulate:a",
		1.0,
		INTRO_DURATION,
	)

	for index in cards.size():
		var card := cards[index]
		var card_tween := create_tween()
		card_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		card_tween.tween_interval(0.16 + index * 0.07)
		card_tween.tween_property(
			card,
			"position:y",
			float(card_base_y[card]),
			INTRO_DURATION,
		)
		card_tween.parallel().tween_property(
			card,
			"modulate:a",
			1.0,
			INTRO_DURATION,
		)

	await get_tree().create_timer(0.62).timeout
	card_hover_enabled = true


func _apply_page_palette() -> void:
	var is_dark := _is_dark_mode()
	var page_background := DARK_BACKGROUND if is_dark else LIGHT_BACKGROUND
	var surface_color := DARK_SURFACE if is_dark else LIGHT_SURFACE
	var input_color := DARK_SURFACE_ALT if is_dark else LIGHT_SURFACE
	var border_color := DARK_BORDER if is_dark else LIGHT_BORDER
	var text_color := DARK_TEXT if is_dark else LIGHT_TEXT
	var muted_color := DARK_MUTED if is_dark else LIGHT_MUTED
	var accent_color := DARK_ACCENT if is_dark else HEBUT_BLUE
	var primary_color := DARK_PRIMARY if is_dark else HEBUT_BLUE

	background.color = page_background
	campus_background.modulate = (
		Color("#34435C")
		if is_dark
		else Color.WHITE
	)
	title_label.add_theme_color_override("font_color", accent_color)
	subtitle_label.add_theme_color_override(
		"font_color",
		DARK_MUTED if is_dark else Color("#526FAE"),
	)

	search_card.add_theme_stylebox_override(
		"panel",
		_surface_style(surface_color, border_color, 16, 24, is_dark),
	)
	for card in [announcement_card, article_card, tips_card]:
		card.add_theme_stylebox_override(
			"panel",
			_surface_style(surface_color, border_color, 16, 32, is_dark),
		)
	article_icon.add_theme_stylebox_override(
		"panel",
		_simple_surface_style(
			DARK_ACCENT_SURFACE if is_dark else Color("#E6EFFF"),
			Color.TRANSPARENT,
			32,
		),
	)

	category_button.add_theme_stylebox_override(
		"normal",
		_input_style(input_color, border_color, 2),
	)
	category_button.add_theme_stylebox_override(
		"hover",
		_input_style(input_color, accent_color, 3),
	)
	category_button.add_theme_stylebox_override(
		"pressed",
		_input_style(input_color, accent_color, 3),
	)
	category_button.add_theme_stylebox_override(
		"focus",
		_input_style(input_color, accent_color, 3),
	)
	_set_button_colors(category_button, text_color, accent_color)

	search_edit.add_theme_stylebox_override(
		"normal",
		_input_style(input_color, border_color, 2),
	)
	search_edit.add_theme_stylebox_override(
		"focus",
		_input_style(input_color, accent_color, 3),
	)
	search_edit.add_theme_color_override("font_color", text_color)
	search_edit.add_theme_color_override("font_placeholder_color", muted_color)
	search_edit.add_theme_color_override("caret_color", accent_color)

	_apply_primary_button(search_button, primary_color, is_dark)
	_apply_announcement_button(submission_button, primary_color, is_dark)
	_apply_announcement_button(report_button, primary_color, is_dark)
	_apply_secondary_button(back_button, is_dark)

	article_title.add_theme_color_override("font_color", text_color)
	content_label.add_theme_color_override("default_color", text_color)
	article_icon_label.add_theme_color_override("font_color", accent_color)
	tips_title.add_theme_color_override("font_color", accent_color)
	status_label.add_theme_color_override("font_color", muted_color)
	article_divider.color = border_color
	footer_divider.color = border_color

	for child in tips_card.find_children("*", "Label", true, false):
		var label := child as Label
		if label != tips_title:
			label.add_theme_color_override("font_color", muted_color)
	for child in tips_card.find_children("*", "ColorRect", true, false):
		var divider := child as ColorRect
		divider.color = border_color

	if category_panel != null:
		category_panel.add_theme_stylebox_override("panel", _category_panel_style())
	if category_column != null:
		for child in category_column.get_children():
			if child is Button:
				var option_button := child as Button
				option_button.add_theme_color_override("font_color", text_color)
				option_button.add_theme_color_override("font_hover_color", accent_color)
				option_button.add_theme_color_override("font_pressed_color", accent_color)
				option_button.add_theme_stylebox_override(
					"normal",
					_category_option_style(false),
				)
				option_button.add_theme_stylebox_override(
					"hover",
					_category_option_style(true),
				)
				option_button.add_theme_stylebox_override(
					"pressed",
					_category_option_style(true),
				)
				option_button.add_theme_stylebox_override(
					"focus",
					_category_option_style(false),
				)

	if announcement_panel != null:
		announcement_panel.add_theme_stylebox_override(
			"panel",
			_category_panel_style(),
		)
	if announcement_title != null:
		announcement_title.add_theme_color_override("font_color", accent_color)
	if announcement_content != null:
		announcement_content.add_theme_color_override("font_color", text_color)
	if announcement_divider != null:
		announcement_divider.color = border_color

	_prepare_search_button_animation()
	search_results.set_appearance(is_dark, float(_app_state().font_scale))


func _surface_style(
	background_color: Color,
	border_color: Color,
	radius: int,
	content_margin: float,
	is_dark: bool,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	style.shadow_color = Color(0, 0, 0, 0.24 if is_dark else 0.08)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


func _simple_surface_style(
	background_color: Color,
	border_color: Color,
	radius: int,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_corner_radius_all(radius)
	return style


func _input_style(
	background_color: Color,
	border_color: Color,
	border_width: int,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	return style


func _apply_primary_button(
	button: Button,
	background_color: Color,
	is_dark: bool,
) -> void:
	_set_button_colors(button, Color.WHITE, Color.WHITE)
	for state_name in ["normal", "focus"]:
		button.add_theme_stylebox_override(
			state_name,
			_button_style(background_color, background_color, is_dark),
		)
	for state_name in ["hover", "pressed"]:
		button.add_theme_stylebox_override(
			state_name,
			_button_style(
				background_color.lightened(0.10),
				background_color.lightened(0.10),
				is_dark,
			),
		)


func _apply_secondary_button(button: Button, is_dark: bool) -> void:
	var background_color := DARK_SURFACE_ALT if is_dark else Color.WHITE
	var hover_color := DARK_SURFACE_HOVER if is_dark else Color("#EEF3FF")
	var border_color := DARK_BORDER if is_dark else LIGHT_BORDER
	var text_color := DARK_TEXT if is_dark else HEBUT_BLUE
	var hover_text := DARK_ACCENT if is_dark else HEBUT_BLUE
	_set_button_colors(button, text_color, hover_text)
	for state_name in ["normal", "focus"]:
		button.add_theme_stylebox_override(
			state_name,
			_button_style(background_color, border_color, is_dark),
		)
	for state_name in ["hover", "pressed"]:
		button.add_theme_stylebox_override(
			state_name,
			_button_style(hover_color, hover_text, is_dark),
		)


func _apply_announcement_button(
	button: Button,
	primary_color: Color,
	is_dark: bool,
) -> void:
	var background_color := DARK_SURFACE_ALT if is_dark else Color.WHITE
	var border_color := DARK_BORDER if is_dark else LIGHT_BORDER
	var normal_text := DARK_ACCENT if is_dark else HEBUT_BLUE
	_set_button_colors(button, normal_text, Color.WHITE)
	for state_name in ["normal", "focus"]:
		button.add_theme_stylebox_override(
			state_name,
			_button_style(background_color, border_color, is_dark),
		)
	for state_name in ["hover", "pressed"]:
		button.add_theme_stylebox_override(
			state_name,
			_button_style(primary_color, primary_color, is_dark),
		)


func _button_style(
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
	if node == search_results:
		search_results.set_appearance(_is_dark_mode(), float(_app_state().font_scale))
		return
	var font_size := clampi(
		roundi(HEGONG_BASE_FONT_SIZE * float(_app_state().font_scale)),
		HEGONG_MIN_FONT_SIZE,
		HEGONG_MAX_FONT_SIZE,
	)
	if node is Control:
		var control := node as Control
		if control == submission_button or control == report_button:
			font_size = roundi(
				font_size * float(ANNOUNCEMENT_BUTTON_FONT_SIZE) / HEGONG_BASE_FONT_SIZE,
			)
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
	_position_category_panel.call_deferred()
	_position_announcement_panel.call_deferred()


func _on_color_mode_changed(_is_dark: bool) -> void:
	_app_state().apply_color_mode(self)
	_apply_page_palette()


func _app_state() -> Node:
	return get_node("/root/AppState")


func _is_dark_mode() -> bool:
	return bool(_app_state().dark_mode)


func _return_to_main() -> void:
	if returning_home:
		return
	returning_home = true
	await _play_button_click(back_button)
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _play_button_click(button: Control) -> void:
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(0.96, 0.96), 0.10)
	tween.tween_property(button, "scale", Vector2.ONE, 0.14)
	await tween.finished
