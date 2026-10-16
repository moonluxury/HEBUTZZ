extends Control

const DISPLAY_LETTERS := ["A", "B", "C", "D", "E", "F"]
const CORRECT_COLOR := Color(0.05, 0.55, 0.22)
const WRONG_COLOR := Color(0.86, 0.15, 0.15)
const QUESTION_NUMBER_COLUMNS := 5
const HEBUT_BLUE := Color("#092C87")
const OPTION_SELECTED_BG := Color("#EEF3FF")
const OPTION_CORRECT_BG := Color("#EDF9F1")
const OPTION_WRONG_BG := Color("#FFF1F1")
const OPTION_BORDER := Color("#E3EAF5")
const LIGHT_BACKGROUND := Color("#F6F9FE")
const LIGHT_TEXT := Color("#0F1E37")
const LIGHT_MUTED := Color("#68758A")
const DARK_BACKGROUND := Color("#0B1220")
const DARK_HEADER := Color("#111A2A")
const DARK_CARD := Color("#151F32")
const DARK_OPTION := Color("#19263A")
const DARK_OPTION_HOVER := Color("#20314B")
const DARK_BORDER := Color("#2C3D59")
const DARK_TEXT := Color("#E8EEF8")
const DARK_MUTED := Color("#9EADC3")
const DARK_ACCENT := Color("#6D92FF")
const DARK_ACCENT_SURFACE := Color("#21375B")
const DARK_CORRECT := Color("#63D68A")
const DARK_CORRECT_SURFACE := Color("#173827")
const DARK_WRONG := Color("#FF858C")
const DARK_WRONG_SURFACE := Color("#41242B")
const INTERACTION_DURATION := 0.12
const INTRO_DURATION := 0.28
const HEADER_HIDE_DELAY := 0.16
const HEADER_FADE_DURATION := 0.16
const HEADER_COLLAPSED_HEIGHT := 28.0
const HEADER_EXPANDED_HEIGHT := 156.0
const OPTION_PRESS_SCALE := 0.996
const NUMBER_UNDERLINE_HEIGHT := 4.0
const NUMBER_UNDERLINE_DURATION := 0.42

var all_questions: Array = []
var questions: Array = []
var wrong_ids := {}
var question_states := {}
var current_index := 0
var shuffled_options: Array = []
var selected_indices: Array = []
var has_answered := false
var button_tweens := {}
var header_hover_timer: Timer
var header_tween: Tween
var header_is_expanded := false
var number_underline: ColorRect
var number_underline_tween: Tween

@onready var empty_state: Control = $EmptyState
@onready var page_margin: MarginContainer = $PageMargin
@onready var empty_label: Label = $EmptyState/EmptyColumn/EmptyLabel
@onready var empty_back_button: Button = $EmptyState/EmptyColumn/BackButton
@onready var background: ColorRect = $Background
@onready var header_panel: PanelContainer = $PageMargin/PageColumn/Header
@onready var header_margin: MarginContainer = $PageMargin/PageColumn/Header/HeaderMargin
@onready var university_logo: TextureRect = $PageMargin/PageColumn/Header/HeaderMargin/HeaderRow/BrandRow/UniversityLogo
@onready var left_card: PanelContainer = $PageMargin/PageColumn/ContentMargin/Body/LeftCard
@onready var right_card: PanelContainer = $PageMargin/PageColumn/ContentMargin/Body/RightCard
@onready var title_label: Label = $PageMargin/PageColumn/Header/HeaderMargin/HeaderRow/BrandRow/TitleColumn/Title
@onready var mode_label: Label = $PageMargin/PageColumn/Header/HeaderMargin/HeaderRow/BrandRow/TitleColumn/ModeLabel
@onready var clock_icon: Label = $PageMargin/PageColumn/Header/HeaderMargin/HeaderRow/TimeRow/ClockIcon
@onready var time_label: Label = $PageMargin/PageColumn/Header/HeaderMargin/HeaderRow/TimeRow/TimeColumn/TimeLabel
@onready var date_label: Label = $PageMargin/PageColumn/Header/HeaderMargin/HeaderRow/TimeRow/TimeColumn/DateLabel
@onready var brand_divider: ColorRect = $PageMargin/PageColumn/Header/HeaderMargin/HeaderRow/BrandRow/BrandDivider
@onready var progress_label: Label = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/TopBar/ProgressLabel
@onready var type_label: Label = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/TopBar/TypeLabel
@onready var jump_input: LineEdit = $PageMargin/PageColumn/ContentMargin/Body/RightCard/RightMargin/RightColumn/HeaderRow/JumpRowContainer/JumpRow/JumpInput
@onready var jump_button: Button = $PageMargin/PageColumn/ContentMargin/Body/RightCard/RightMargin/RightColumn/HeaderRow/JumpRowContainer/JumpRow/JumpButton
@onready var question_number_list: ItemList = $PageMargin/PageColumn/ContentMargin/Body/RightCard/RightMargin/RightColumn/QuestionNumberList
@onready var question_scroll: ScrollContainer = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll
@onready var question_label: RichTextLabel = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/QuestionLabel
@onready var option_buttons: Array[Button] = [
	$PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/Option1,
	$PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/Option2,
	$PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/Option3,
	$PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/Option4,
	$PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/Option5,
	$PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/Option6,
]
@onready var submit_button: Button = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/SubmitRow/SubmitButton
@onready var result_label: Label = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/SubmitRow/ResultLabel
@onready var answer_label: Label = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/QuestionMargin/QuestionArea/QuestionScroll/Content/AnswerLabel
@onready var footer_divider: ColorRect = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/FooterDivider
@onready var prev_button: Button = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/BottomNavContainer/BottomNav/PrevPositionKeeper/PrevButton
@onready var next_button: Button = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/BottomNavContainer/BottomNav/NextButton
@onready var wrong_toggle: Button = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/BottomNavContainer/BottomNav/WrongToggle
@onready var home_button: Button = $PageMargin/PageColumn/ContentMargin/Body/LeftCard/LeftColumn/BottomNavContainer/BottomNav/HomeButton
@onready var question_numbers_title: Label = $PageMargin/PageColumn/ContentMargin/Body/RightCard/RightMargin/RightColumn/HeaderRow/HeaderTitleColumn/QuestionNumbersTitle
@onready var title_underline: ColorRect = $PageMargin/PageColumn/ContentMargin/Body/RightCard/RightMargin/RightColumn/HeaderRow/HeaderTitleColumn/TitleUnderline


func _ready() -> void:
	randomize()
	page_margin.modulate.a = 0.0
	_update_clock()
	var clock_timer := Timer.new()
	clock_timer.wait_time = 1.0
	clock_timer.autostart = true
	clock_timer.timeout.connect(_update_clock)
	add_child(clock_timer)
	_load_data()
	title_label.text = "%s题库" % str(_subject()["title"])
	_connect_controls()
	_setup_header_hover()
	_setup_question_number_underline()
	if questions.is_empty():
		_set_quiz_ui_visible(false)
		empty_state.visible = true
		empty_label.text = "%s%s" % [
			_subject()["title"],
			"错题库暂无题目" if _app_state().quiz_mode == "wrong" else "题库暂无题目",
		]
	else:
		_set_quiz_ui_visible(true)
		empty_state.visible = false
		current_index = clamp(_app_state().start_index, 0, questions.size() - 1)
		_update_jump_search_hint()
		_populate_question_numbers()
		_show_question()
	_app_state().font_scale_changed.connect(_on_font_scale_changed)
	_app_state().color_mode_changed.connect(_on_color_mode_changed)
	_app_state().apply_font_scale(self)
	_app_state().apply_color_mode(self)
	_apply_quiz_palette()
	_setup_button_interactions()
	_play_intro_fade.call_deferred()


func _setup_header_hover() -> void:
	header_panel.custom_minimum_size = Vector2(0, HEADER_COLLAPSED_HEIGHT)
	header_panel.clip_contents = true
	header_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	header_panel.tooltip_text = "悬停显示题库信息"
	header_margin.modulate.a = 0.0
	header_margin.hide()
	header_panel.mouse_entered.connect(_expand_header)
	header_panel.mouse_exited.connect(_schedule_header_collapse)

	header_hover_timer = Timer.new()
	header_hover_timer.name = "HeaderHoverTimer"
	header_hover_timer.one_shot = true
	header_hover_timer.wait_time = HEADER_HIDE_DELAY
	header_hover_timer.timeout.connect(_collapse_header)
	add_child(header_hover_timer)


func _setup_question_number_underline() -> void:
	number_underline = ColorRect.new()
	number_underline.name = "CurrentNumberUnderline"
	number_underline.z_index = 5
	number_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number_underline.color = HEBUT_BLUE
	number_underline.hide()
	question_number_list.add_child(number_underline)
	question_number_list.clip_contents = true

	var scroll_bar := question_number_list.get_v_scroll_bar()
	if scroll_bar != null:
		scroll_bar.value_changed.connect(_on_question_number_scroll_changed)


func _animate_current_number_underline() -> void:
	if not _position_current_number_underline():
		return
	if number_underline_tween != null and number_underline_tween.is_valid():
		number_underline_tween.kill()
	number_underline.pivot_offset = Vector2(
		number_underline.size.x * 0.5,
		NUMBER_UNDERLINE_HEIGHT * 0.5,
	)
	number_underline.scale = Vector2(0.0, 1.0)
	number_underline.show()
	number_underline_tween = create_tween()
	number_underline_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	number_underline_tween.tween_property(
		number_underline,
		"scale:x",
		1.0,
		NUMBER_UNDERLINE_DURATION,
	)


func _position_current_number_underline() -> bool:
	if (
		number_underline == null
		or current_index < 0
		or current_index >= question_number_list.item_count
	):
		if number_underline != null:
			number_underline.hide()
		return false

	var item_rect := question_number_list.get_item_rect(current_index, false)
	var font := question_number_list.get_theme_font("font")
	var font_size := question_number_list.get_theme_font_size("font_size")
	var item_text := question_number_list.get_item_text(current_index)
	var text_size := font.get_string_size(
		item_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
	)
	var underline_width := maxf(8.0, ceilf(text_size.x))
	var text_height := font.get_height(font_size)
	var underline_x := (
		item_rect.position.x
		+ (item_rect.size.x - underline_width) * 0.5
	)
	var underline_y := (
		item_rect.position.y
		+ (item_rect.size.y + text_height) * 0.5
		+ 1.0
	)
	underline_y = minf(
		underline_y,
		item_rect.end.y - NUMBER_UNDERLINE_HEIGHT,
	)
	var scroll_bar := question_number_list.get_v_scroll_bar()
	if scroll_bar != null:
		underline_y -= scroll_bar.value
	number_underline.position = Vector2(underline_x, underline_y)
	number_underline.size = Vector2(underline_width, NUMBER_UNDERLINE_HEIGHT)
	number_underline.pivot_offset = Vector2(
		underline_width * 0.5,
		NUMBER_UNDERLINE_HEIGHT * 0.5,
	)
	return true


func _on_question_number_scroll_changed(_value: float) -> void:
	_position_current_number_underline.call_deferred()


func _expand_header() -> void:
	if header_hover_timer != null:
		header_hover_timer.stop()
	if header_is_expanded:
		return
	header_is_expanded = true
	if header_tween != null and header_tween.is_valid():
		header_tween.kill()
	header_panel.custom_minimum_size = Vector2(0, HEADER_EXPANDED_HEIGHT)
	header_margin.show()
	header_margin.modulate.a = 0.0
	_apply_quiz_palette()
	header_tween = create_tween()
	header_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	header_tween.tween_property(
		header_margin,
		"modulate:a",
		1.0,
		HEADER_FADE_DURATION,
	)


func _schedule_header_collapse() -> void:
	if header_hover_timer != null:
		header_hover_timer.start()


func _collapse_header() -> void:
	if not header_is_expanded:
		return
	header_is_expanded = false
	if header_tween != null and header_tween.is_valid():
		header_tween.kill()
	header_tween = create_tween()
	header_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	header_tween.tween_property(
		header_margin,
		"modulate:a",
		0.0,
		HEADER_FADE_DURATION,
	)
	header_tween.tween_callback(_finish_header_collapse)


func _finish_header_collapse() -> void:
	if header_is_expanded:
		return
	header_margin.hide()
	header_panel.custom_minimum_size = Vector2(0, HEADER_COLLAPSED_HEIGHT)
	_apply_quiz_palette()


func _update_clock() -> void:
	var now := Time.get_datetime_dict_from_system()
	var weekdays := ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
	time_label.text = "%02d:%02d:%02d" % [now.hour, now.minute, now.second]
	date_label.text = "%04d年%02d月%02d日  %s" % [
		now.year,
		now.month,
		now.day,
		weekdays[now.weekday],
	]


func _setup_button_interactions() -> void:
	var buttons: Array[Button] = []
	buttons.append_array(option_buttons)
	buttons.append_array([
		submit_button,
		prev_button,
		next_button,
		wrong_toggle,
		home_button,
		jump_button,
		empty_back_button,
	])
	for button in buttons:
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.button_down.connect(_animate_button_press.bind(button, true))
		button.button_up.connect(_animate_button_press.bind(button, false))


func _animate_button_press(button: Button, is_pressed: bool) -> void:
	var tween_key := button.get_instance_id()
	if button_tweens.has(tween_key):
		var previous_tween: Tween = button_tweens[tween_key]
		if previous_tween != null and previous_tween.is_valid():
			previous_tween.kill()
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	button_tweens[tween_key] = tween
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		button,
		"scale",
		(
			Vector2(OPTION_PRESS_SCALE, OPTION_PRESS_SCALE)
			if is_pressed and option_buttons.has(button)
			else Vector2(0.98, 0.98) if is_pressed else Vector2.ONE
		),
		0.07 if is_pressed else INTERACTION_DURATION,
	)


func _play_intro_fade() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(page_margin, "modulate:a", 1.0, INTRO_DURATION)


func _connect_controls() -> void:
	for index in option_buttons.size():
		option_buttons[index].pressed.connect(_on_option_pressed.bind(index))
	submit_button.pressed.connect(_submit_multiple_answer)
	prev_button.pressed.connect(func(): _jump_to(current_index - 1))
	next_button.pressed.connect(func(): _jump_to(current_index + 1))
	wrong_toggle.pressed.connect(_toggle_wrong_current)
	home_button.pressed.connect(_go_home)
	empty_back_button.pressed.connect(_go_home)
	jump_button.pressed.connect(_jump_from_search)
	jump_input.text_submitted.connect(func(_text: String): _jump_from_search())
	question_number_list.item_selected.connect(_on_question_number_selected)
	question_number_list.resized.connect(_fit_question_number_columns)
	call_deferred("_fit_question_number_columns")


func _set_quiz_ui_visible(is_visible: bool) -> void:
	page_margin.visible = is_visible


func _populate_question_numbers() -> void:
	question_number_list.clear()
	for index in questions.size():
		question_number_list.add_item(str(index + 1))
	_refresh_question_number_states()
	call_deferred("_fit_question_number_columns")


func _refresh_question_number_states() -> void:
	for index in mini(questions.size(), question_number_list.item_count):
		var item_color := DARK_TEXT if _is_dark_mode() else Color("#17233A")
		var state_key := _question_state_key(index)
		var is_answered := false
		if question_states.has(state_key):
			var state: Dictionary = question_states[state_key]
			is_answered = bool(state.get("answered", false))
		if is_answered:
			item_color = DARK_ACCENT if _is_dark_mode() else HEBUT_BLUE
			question_number_list.set_item_tooltip(index, "第 %d 题 · 已答题" % (index + 1))
		else:
			question_number_list.set_item_tooltip(index, "第 %d 题" % (index + 1))
		if index == current_index:
			item_color = DARK_ACCENT if _is_dark_mode() else HEBUT_BLUE
		question_number_list.set_item_custom_fg_color(index, item_color)


func _fit_question_number_columns() -> void:
	var usable_width: int = max(1, int(question_number_list.size.x) - 36)
	question_number_list.fixed_column_width = max(80, int(floor(float(usable_width) / QUESTION_NUMBER_COLUMNS)))


func _load_data() -> void:
	all_questions = _load_questions_from_json(str(_subject()["question_path"]))
	wrong_ids = _load_wrong_ids()
	questions.clear()
	if _app_state().quiz_mode == "wrong":
		for question in all_questions:
			if wrong_ids.has(str(question["id"])):
				questions.append(question)
	else:
		questions = all_questions.duplicate(true)


func _load_questions_from_json(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("题库文件不存在：%s" % path)
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("题库文件无法打开：%s" % path)
		return []

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		push_warning(
			"题库 JSON 解析失败（第 %d 行）：%s"
			% [json.get_error_line(), json.get_error_message()],
		)
		return []

	var parsed = json.data
	var raw_questions: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		raw_questions = parsed
	elif (
		typeof(parsed) == TYPE_DICTIONARY
		and parsed.has("questions")
		and typeof(parsed["questions"]) == TYPE_ARRAY
	):
		raw_questions = parsed["questions"]
	else:
		push_warning("题库 JSON 根节点必须是数组或包含 questions 数组")
		return []

	var valid_questions: Array = []
	for raw_question in raw_questions:
		if _is_valid_question(raw_question):
			valid_questions.append(raw_question)
		else:
			push_warning("已跳过一条格式不完整的题目数据")
	return valid_questions


func _is_valid_question(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var question: Dictionary = value
	return (
		question.has("stem")
		and question.has("options")
		and typeof(question["options"]) == TYPE_ARRAY
		and not question["options"].is_empty()
	)


func _show_question() -> void:
	var question: Dictionary = questions[current_index]
	shuffled_options = question["options"].duplicate(true)
	shuffled_options.shuffle()
	_restore_current_question_state()
	progress_label.text = str(current_index + 1)
	title_label.text = "%s题库" % str(_subject()["title"])
	mode_label.text = "错题库答题" if _app_state().quiz_mode == "wrong" else "总题库答题"
	type_label.text = question["type_label"]
	question_label.text = "%d. %s" % [question["id"], question["stem"]]
	submit_button.visible = question["type"] == "multiple"
	submit_button.disabled = has_answered
	question_label.scroll_to_line(0)

	for index in option_buttons.size():
		var button := option_buttons[index]
		if index < shuffled_options.size():
			button.visible = true
			button.disabled = has_answered
			button.toggle_mode = question["type"] == "multiple"
			button.button_pressed = selected_indices.has(index)
			button.text = _option_display_text(index)
			_refresh_option_visual(index)
		else:
			button.visible = false

	_refresh_answer_feedback()
	question_number_list.select(current_index)
	_refresh_question_number_states()
	question_number_list.ensure_current_is_visible()
	_animate_current_number_underline.call_deferred()
	prev_button.disabled = current_index == 0
	next_button.disabled = current_index == questions.size() - 1
	_update_wrong_button()
	_refresh_interaction_colors()


func _restore_current_question_state() -> void:
	selected_indices.clear()
	has_answered = false
	var state_key := _question_state_key(current_index)
	if not question_states.has(state_key):
		return

	var state: Dictionary = question_states[state_key]
	has_answered = bool(state.get("answered", false))
	var selected_keys: Array = state.get("selected_keys", [])
	for index in shuffled_options.size():
		if selected_keys.has(str(shuffled_options[index].get("key", ""))):
			selected_indices.append(index)


func _save_current_question_state() -> void:
	var selected_keys: Array[String] = []
	for index in selected_indices:
		selected_keys.append(str(shuffled_options[index].get("key", "")))
	question_states[_question_state_key(current_index)] = {
		"selected_keys": selected_keys,
		"answered": has_answered,
		"correct": _is_selection_correct() if has_answered else false,
	}


func _question_state_key(index: int) -> String:
	if index < 0 or index >= questions.size():
		return ""
	return str(questions[index].get("id", index + 1))


func _on_option_pressed(index: int) -> void:
	if has_answered or index >= shuffled_options.size():
		return
	if questions[current_index]["type"] == "multiple":
		if selected_indices.has(index):
			selected_indices.erase(index)
		else:
			selected_indices.append(index)
		_refresh_option_text()
		_refresh_all_option_visuals()
		_save_current_question_state()
		result_label.add_theme_color_override("font_color", _ink_color())
		result_label.text = "已选：%s" % _selected_display_text()
	else:
		selected_indices = [index]
		_refresh_option_text()
		_refresh_all_option_visuals()
		_reveal_answer()


func _submit_multiple_answer() -> void:
	if has_answered:
		return
	if selected_indices.is_empty():
		result_label.add_theme_color_override("font_color", _wrong_feedback_color())
		result_label.text = "请至少选择一个选项"
		return
	_reveal_answer()


func _reveal_answer() -> void:
	has_answered = true
	var correct := _is_selection_correct()
	_app_state().register_quiz_answer(correct)
	_save_current_question_state()
	_refresh_option_text()
	_refresh_all_option_visuals()
	_refresh_answer_feedback()
	_refresh_question_number_states()
	submit_button.disabled = true


func _refresh_answer_feedback() -> void:
	if not has_answered:
		result_label.text = ""
		answer_label.text = ""
		return
	var correct := _is_selection_correct()
	result_label.text = "回答正确" if correct else "回答错误"
	result_label.add_theme_color_override(
		"font_color",
		_correct_feedback_color() if correct else _wrong_feedback_color(),
	)
	answer_label.text = "正确答案：%s" % _correct_display_text()


func _refresh_all_option_visuals() -> void:
	for index in shuffled_options.size():
		_refresh_option_visual(index)


func _refresh_option_visual(index: int) -> void:
	var button := option_buttons[index]
	var is_selected := selected_indices.has(index)
	var is_correct_option := bool(shuffled_options[index].get("correct", false))
	var is_dark := _is_dark_mode()
	var background := DARK_OPTION if is_dark else Color.WHITE
	var border := DARK_BORDER if is_dark else OPTION_BORDER
	var text_color := DARK_TEXT if is_dark else _ink_color()

	if has_answered and is_correct_option:
		background = DARK_CORRECT_SURFACE if is_dark else OPTION_CORRECT_BG
		border = DARK_CORRECT.darkened(0.20) if is_dark else CORRECT_COLOR.lightened(0.34)
		text_color = _correct_feedback_color()
	elif has_answered and is_selected:
		background = DARK_WRONG_SURFACE if is_dark else OPTION_WRONG_BG
		border = DARK_WRONG.darkened(0.20) if is_dark else WRONG_COLOR.lightened(0.28)
		text_color = _wrong_feedback_color()
	elif is_selected:
		background = DARK_ACCENT_SURFACE if is_dark else OPTION_SELECTED_BG
		border = DARK_ACCENT if is_dark else HEBUT_BLUE
		text_color = DARK_ACCENT if is_dark else HEBUT_BLUE

	var hover_background := (
		background
		if is_selected
		else background.darkened(0.015)
	)
	var pressed_background := (
		background
		if is_selected
		else background.darkened(0.025)
	)
	button.add_theme_stylebox_override("normal", _option_style(background, border))
	button.add_theme_stylebox_override(
		"hover",
		_option_style(hover_background, border),
	)
	button.add_theme_stylebox_override(
		"pressed",
		_option_style(pressed_background, border),
	)
	button.add_theme_stylebox_override(
		"hover_pressed",
		_option_style(background, border),
	)
	button.add_theme_stylebox_override("focus", _option_style(background, border))
	button.add_theme_stylebox_override("disabled", _option_style(background, border))
	_set_option_color(button, text_color)


func _option_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 32.0
	style.content_margin_right = 24.0
	return style


func _set_option_color(button: Button, color: Color) -> void:
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color",
		"font_disabled_color",
	]:
		button.add_theme_color_override(color_name, color)


func _is_selection_correct() -> bool:
	var selected_keys := []
	for index in selected_indices:
		selected_keys.append(str(shuffled_options[index]["key"]))
	selected_keys.sort()
	var correct_keys := []
	for option in shuffled_options:
		if bool(option["correct"]):
			correct_keys.append(str(option["key"]))
	correct_keys.sort()
	return selected_keys == correct_keys


func _selected_display_text() -> String:
	var labels := []
	var sorted_indices := selected_indices.duplicate()
	sorted_indices.sort()
	for index in sorted_indices:
		labels.append(DISPLAY_LETTERS[index])
	return "、".join(labels)


func _correct_display_text() -> String:
	var labels := []
	for index in shuffled_options.size():
		if bool(shuffled_options[index]["correct"]):
			labels.append(DISPLAY_LETTERS[index])
	return "、".join(labels)


func _option_display_text(index: int) -> String:
	var marker := "●" if selected_indices.has(index) else "○"
	if has_answered and bool(shuffled_options[index].get("correct", false)):
		marker = "✓"
	elif has_answered and selected_indices.has(index):
		marker = "×"
	return "%s    %s. %s" % [marker, DISPLAY_LETTERS[index], shuffled_options[index]["text"]]


func _refresh_option_text() -> void:
	for index in shuffled_options.size():
		option_buttons[index].text = _option_display_text(index)


func _toggle_wrong_current() -> void:
	var id := str(questions[current_index]["id"])
	if wrong_ids.has(id):
		wrong_ids.erase(id)
		_save_wrong_ids()
		if _app_state().quiz_mode == "wrong":
			questions.remove_at(current_index)
			if questions.is_empty():
				_go_home()
				return
			current_index = min(current_index, questions.size() - 1)
			_update_jump_search_hint()
			_populate_question_numbers()
			_show_question()
			return
	else:
		wrong_ids[id] = true
		_save_wrong_ids()
	_update_wrong_button()


func _update_wrong_button() -> void:
	var is_collected := wrong_ids.has(str(questions[current_index]["id"]))
	wrong_toggle.text = "♥   已加入错题库" if is_collected else "♡   加入错题库"
	var is_dark := _is_dark_mode()
	var background := DARK_OPTION if is_dark else Color.WHITE
	var border := (
		(DARK_ACCENT if is_dark else HEBUT_BLUE)
		if is_collected
		else (DARK_BORDER if is_dark else OPTION_BORDER)
	)
	var text_color := (
		(DARK_ACCENT if is_dark else HEBUT_BLUE)
		if is_collected
		else (DARK_TEXT if is_dark else LIGHT_TEXT)
	)
	for state_name in ["normal", "focus"]:
		wrong_toggle.add_theme_stylebox_override(
			state_name,
			_action_button_style(background, border),
		)
	for state_name in ["hover", "pressed"]:
		wrong_toggle.add_theme_stylebox_override(
			state_name,
			_action_button_style(
				DARK_OPTION_HOVER if is_dark else Color("#F1F5FC"),
				DARK_ACCENT if is_collected and is_dark else (
					HEBUT_BLUE if is_collected else border
				),
			),
		)
	_set_button_state_colors(
		wrong_toggle,
		text_color,
		DARK_ACCENT if is_dark else HEBUT_BLUE,
	)


func _action_button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	return style


func _jump_to(index: int) -> void:
	if index < 0 or index >= questions.size():
		return
	current_index = index
	_app_state().start_index = current_index
	_show_question()


func _jump_from_search() -> void:
	var input_text := jump_input.text.strip_edges()
	if not input_text.is_valid_int():
		jump_input.clear()
		jump_input.placeholder_text = "请输入 1-%d" % questions.size()
		return
	var target_index := int(input_text) - 1
	if target_index < 0 or target_index >= questions.size():
		jump_input.clear()
		jump_input.placeholder_text = "请输入 1-%d" % questions.size()
		return
	_jump_to(target_index)
	jump_input.clear()
	jump_input.placeholder_text = "跳转到题号"
	jump_input.release_focus()


func _update_jump_search_hint() -> void:
	jump_input.placeholder_text = "跳转到题号"
	jump_input.tooltip_text = "请输入 1 至 %d 之间的题号" % questions.size()


func _on_question_number_selected(index: int) -> void:
	_jump_to(index)


func _go_home() -> void:
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _load_wrong_ids() -> Dictionary:
	var ids := {}
	for id in _load_json_array(_subject()["wrong_path"]):
		ids[str(id)] = true
	return ids


func _save_wrong_ids() -> void:
	var ids := []
	for id in wrong_ids.keys():
		ids.append(int(id))
	ids.sort()
	var file := FileAccess.open(_subject()["wrong_path"], FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(ids, "  "))


func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func _app_state() -> Node:
	return get_node("/root/AppState")


func _subject() -> Dictionary:
	return _app_state().get_subject()


func _on_font_scale_changed(_scale: float) -> void:
	_app_state().apply_font_scale(self)
	_position_current_number_underline.call_deferred()


func _on_color_mode_changed(_is_dark: bool) -> void:
	_app_state().apply_color_mode(self)
	_refresh_quiz_colors()


func _refresh_quiz_colors() -> void:
	_apply_quiz_palette()
	if questions.is_empty():
		return

	_refresh_all_option_visuals()
	_refresh_question_number_states()

	if has_answered:
		var correct := _is_selection_correct()
		result_label.add_theme_color_override(
			"font_color",
			_correct_feedback_color() if correct else _wrong_feedback_color(),
		)
	elif result_label.text.begins_with("请"):
		result_label.add_theme_color_override("font_color", _wrong_feedback_color())
	else:
		result_label.add_theme_color_override("font_color", _ink_color())


func _ink_color() -> Color:
	return _app_state().get_foreground_color()


func _refresh_interaction_colors() -> void:
	_set_option_color(submit_button, Color.WHITE)
	_apply_primary_button_style(jump_button, _is_dark_mode())
	_apply_footer_button_style(prev_button, _is_dark_mode())
	_apply_footer_button_style(next_button, _is_dark_mode())
	_apply_outline_button_style(home_button, _is_dark_mode())
	if not questions.is_empty():
		_update_wrong_button()


func _apply_quiz_palette() -> void:
	var is_dark := _is_dark_mode()
	var page_background := DARK_BACKGROUND if is_dark else LIGHT_BACKGROUND
	var header_background := DARK_HEADER if is_dark else Color.WHITE
	var card_background := DARK_CARD if is_dark else Color.WHITE
	var border_color := DARK_BORDER if is_dark else Color("#E5EAF2")
	var text_color := DARK_TEXT if is_dark else LIGHT_TEXT
	var muted_color := DARK_MUTED if is_dark else LIGHT_MUTED
	var accent_color := DARK_ACCENT if is_dark else HEBUT_BLUE

	background.color = page_background
	header_panel.add_theme_stylebox_override(
		"panel",
		_header_style(
			header_background,
			border_color,
			1,
		),
	)
	for card in [left_card, right_card]:
		card.add_theme_stylebox_override(
			"panel",
			_card_style(card_background, border_color, is_dark),
		)

	title_label.add_theme_color_override("font_color", accent_color)
	university_logo.self_modulate = accent_color
	mode_label.add_theme_color_override("font_color", muted_color)
	clock_icon.add_theme_color_override("font_color", accent_color)
	time_label.add_theme_color_override("font_color", text_color)
	date_label.add_theme_color_override("font_color", muted_color)
	type_label.add_theme_color_override("font_color", muted_color)
	question_label.add_theme_color_override("default_color", text_color)
	answer_label.add_theme_color_override("font_color", text_color)
	question_numbers_title.add_theme_color_override("font_color", text_color)
	brand_divider.color = DARK_BORDER if is_dark else Color("#A3B1C9")
	footer_divider.color = border_color
	title_underline.color = accent_color
	if number_underline != null:
		number_underline.color = accent_color
	jump_input.add_theme_color_override("font_color", text_color)
	jump_input.add_theme_color_override("font_placeholder_color", muted_color)
	jump_input.add_theme_color_override("caret_color", accent_color)
	jump_input.add_theme_color_override(
		"selection_color",
		Color(accent_color, 0.26),
	)
	jump_input.add_theme_stylebox_override(
		"normal",
		_jump_input_style(
			DARK_OPTION if is_dark else Color.WHITE,
			border_color,
			2,
		),
	)
	jump_input.add_theme_stylebox_override(
		"focus",
		_jump_input_style(
			DARK_OPTION_HOVER if is_dark else Color.WHITE,
			accent_color,
			2,
		),
	)

	progress_label.add_theme_color_override("font_color", Color.WHITE)
	progress_label.add_theme_stylebox_override(
		"normal",
		_badge_style(DARK_ACCENT.darkened(0.16) if is_dark else HEBUT_BLUE),
	)
	question_number_list.add_theme_color_override("font_color", text_color)
	question_number_list.add_theme_color_override("font_hovered_color", accent_color)
	question_number_list.add_theme_color_override("font_selected_color", accent_color)
	question_number_list.add_theme_color_override("font_hovered_selected_color", accent_color)
	question_number_list.add_theme_stylebox_override(
		"panel",
		_list_style(card_background),
	)
	question_number_list.add_theme_stylebox_override(
		"selected",
		_selection_style(Color.TRANSPARENT),
	)
	question_number_list.add_theme_stylebox_override(
		"selected_focus",
		_selection_style(Color.TRANSPARENT),
	)

	_apply_primary_button_style(submit_button, is_dark)
	_apply_primary_button_style(empty_back_button, is_dark)
	_apply_primary_button_style(jump_button, is_dark)
	_apply_footer_button_style(prev_button, is_dark)
	_apply_footer_button_style(next_button, is_dark)
	_apply_outline_button_style(home_button, is_dark)
	empty_label.add_theme_color_override("font_color", text_color)
	empty_label.add_theme_stylebox_override(
		"normal",
		_card_style(card_background, border_color, is_dark),
	)

	if not questions.is_empty():
		_refresh_all_option_visuals()
		_refresh_question_number_states()
	_refresh_interaction_colors()


func _header_style(
	background_color: Color,
	border_color: Color,
	border_width: int,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_bottom = border_width
	return style


func _card_style(
	background_color: Color,
	border_color: Color,
	is_dark: bool,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0, 0, 0, 0.24 if is_dark else 0.07)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 5)
	return style


func _badge_style(background_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.set_corner_radius_all(8)
	style.shadow_color = Color(background_color, 0.22)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


func _list_style(background_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	return style


func _selection_style(background_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.set_corner_radius_all(8)
	return style


func _jump_input_style(
	background_color: Color,
	border_color: Color,
	border_width: int,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style


func _apply_primary_button_style(button: Button, is_dark: bool) -> void:
	var normal_color := DARK_ACCENT.darkened(0.20) if is_dark else HEBUT_BLUE
	var hover_color := normal_color.lightened(0.10)
	_set_option_color(button, Color.WHITE)
	for state_name in ["normal", "focus"]:
		button.add_theme_stylebox_override(
			state_name,
			_primary_button_style(normal_color, is_dark),
		)
	for state_name in ["hover", "pressed"]:
		button.add_theme_stylebox_override(
			state_name,
			_primary_button_style(hover_color, is_dark),
		)


func _primary_button_style(background_color: Color, is_dark: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.22 if is_dark else 0.10)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 3)
	return style


func _apply_outline_button_style(button: Button, is_dark: bool) -> void:
	var normal_background := DARK_OPTION if is_dark else Color.WHITE
	var hover_background := DARK_OPTION_HOVER if is_dark else Color("#F1F5FC")
	var border_color := DARK_BORDER if is_dark else OPTION_BORDER
	var text_color := DARK_TEXT if is_dark else LIGHT_TEXT
	_set_option_color(button, text_color)
	for state_name in ["normal", "focus"]:
		button.add_theme_stylebox_override(
			state_name,
			_action_button_style(normal_background, border_color),
		)
	for state_name in ["hover", "pressed"]:
		button.add_theme_stylebox_override(
			state_name,
			_action_button_style(hover_background, border_color.lightened(0.12)),
		)


func _apply_footer_button_style(button: Button, is_dark: bool) -> void:
	var normal_background := DARK_OPTION if is_dark else Color.WHITE
	var normal_border := DARK_BORDER if is_dark else OPTION_BORDER
	var normal_text := DARK_TEXT if is_dark else LIGHT_TEXT
	var hover_background := DARK_ACCENT.darkened(0.20) if is_dark else HEBUT_BLUE
	for state_name in ["normal", "focus"]:
		button.add_theme_stylebox_override(
			state_name,
			_action_button_style(normal_background, normal_border),
		)
	for state_name in ["hover", "pressed"]:
		button.add_theme_stylebox_override(
			state_name,
			_action_button_style(hover_background, hover_background),
		)
	_set_button_state_colors(button, normal_text, Color.WHITE)


func _set_button_state_colors(
	button: Button,
	normal_color: Color,
	hover_color: Color,
) -> void:
	button.add_theme_color_override("font_color", normal_color)
	button.add_theme_color_override("font_focus_color", normal_color)
	button.add_theme_color_override(
		"font_disabled_color",
		normal_color.darkened(0.20),
	)
	button.add_theme_color_override("font_hover_color", hover_color)
	button.add_theme_color_override("font_pressed_color", hover_color)
	button.add_theme_color_override("font_hover_pressed_color", hover_color)


func _correct_feedback_color() -> Color:
	return DARK_CORRECT if _is_dark_mode() else CORRECT_COLOR


func _wrong_feedback_color() -> Color:
	return DARK_WRONG if _is_dark_mode() else WRONG_COLOR


func _is_dark_mode() -> bool:
	return bool(_app_state().dark_mode)
