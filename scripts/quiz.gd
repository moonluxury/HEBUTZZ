extends Control

const FillAnswer = preload("res://scripts/fill_answer.gd")
const OutputAnswer = preload("res://scripts/output_answer.gd")
const ProgramEditor = preload("res://scripts/program_editor.gd")
const CODE_FONT = preload("res://themes/code_font.tres")
const DISPLAY_LETTERS := ["A", "B", "C", "D", "E", "F"]
const CORRECT_COLOR := Color(0.05, 0.55, 0.22)
const WRONG_COLOR := Color(0.86, 0.15, 0.15)
const Tokens = preload("res://scripts/ui_tokens.gd")
const HEBUT_BLUE := Tokens.PRIMARY
const OPTION_SELECTED_BG := Tokens.SOFT
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
const DARK_ACCENT := Tokens.DARK_ACCENT
const DARK_ACCENT_SURFACE := Tokens.DARK_SOFT
const DARK_CORRECT := Color("#63D68A")
const DARK_CORRECT_SURFACE := Color("#173827")
const DARK_WRONG := Color("#FF858C")
const DARK_WRONG_SURFACE := Color("#41242B")

var minimal_view: Control

var all_questions: Array = []
var questions: Array = []
var wrong_ids := {}
var question_states := {}
var current_index := 0
var shuffled_options: Array = []
var selected_indices: Array = []
var entered_answers: Array[String] = []
var fill_inputs: Array[LineEdit] = []
var output_input: TextEdit
var program_editor: VBoxContainer
var question_images: VBoxContainer
var reference_revealed := false
var has_answered := false

@onready var empty_label: Label = $EmptyLabel
@onready var jump_input: LineEdit = $JumpInput
@onready var jump_button: Button = $JumpButton
@onready var question_scroll: ScrollContainer = $QuestionScroll
@onready var question_label: RichTextLabel = $QuestionScroll/Content/QuestionLabel
@onready var submit_button: Button = $QuestionScroll/Content/SubmitRow/SubmitButton
@onready var answer_margin: MarginContainer = $QuestionScroll/Content/AnswerMargin
@onready var fill_answers_box: VBoxContainer = $QuestionScroll/Content/AnswerMargin/FillAnswers
@onready var result_label: Label = $QuestionScroll/Content/SubmitRow/ResultLabel
@onready var answer_label: Label = $QuestionScroll/Content/AnswerLabel
@onready var prev_button: Button = $PrevButton
@onready var next_button: Button = $NextButton
@onready var wrong_toggle: Button = $WrongToggle
@onready var home_button: Button = $HomeButton
@onready var option_buttons: Array[Button] = [
	$QuestionScroll/Content/Option1,
	$QuestionScroll/Content/Option2,
	$QuestionScroll/Content/Option3,
	$QuestionScroll/Content/Option4,
	$QuestionScroll/Content/Option5,
	$QuestionScroll/Content/Option6,
]


func _ready() -> void:
	theme = get_node("/root/UiResources").page_theme
	_load_data()
	question_images = VBoxContainer.new()
	question_images.name = "QuestionImages"
	question_label.get_parent().add_child(question_images)
	question_label.get_parent().move_child(question_images, question_label.get_index() + 1)
	_connect_controls()
	current_index = clampi(_app_state().start_index, 0, maxi(0, questions.size() - 1))
	empty_label.text = "%s%s" % [_subject().title, "错题库暂无题目" if _app_state().quiz_mode == "wrong" else "题库暂无题目"]
	minimal_view = preload("res://scripts/minimal_quiz_view.gd").new()
	minimal_view.quiz = self
	minimal_view.size = size
	add_child(minimal_view)
	minimal_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not questions.is_empty():
		_show_question()


func _connect_controls() -> void:
	for index in option_buttons.size():
		option_buttons[index].pressed.connect(_on_option_pressed.bind(index))
	submit_button.pressed.connect(_submit_multiple_answer)
	prev_button.pressed.connect(func(): _jump_to(current_index - 1))
	next_button.pressed.connect(func(): _jump_to(current_index + 1))
	wrong_toggle.pressed.connect(_toggle_wrong_current)
	home_button.pressed.connect(get_node("/root/PageRouter").back)
	jump_button.pressed.connect(_jump_from_search)
	jump_input.text_submitted.connect(func(_text: String): _jump_from_search())


func _populate_question_numbers() -> void:
	if is_instance_valid(minimal_view):
		minimal_view.build_numbers()


func _refresh_question_number_states() -> void:
	if is_instance_valid(minimal_view):
		minimal_view.refresh_numbers()


func _load_data() -> void:
	all_questions = get_node("/root/StudyStats").banks.get(_app_state().subject_id, [])
	wrong_ids = _load_wrong_ids()
	questions.clear()
	if _app_state().quiz_mode == "wrong":
		for question in all_questions:
			if wrong_ids.has(str(question["id"])):
				questions.append(question)
	else:
		# The bank dictionaries are read-only; only this session's list is mutable.
		questions = all_questions.duplicate()


func _show_question() -> void:
	# Reused option controls must never interpolate from the previous question's result.
	for button in option_buttons:
		button.set_meta("motion_snap", true)
	var question: Dictionary = questions[current_index]
	get_node("/root/StudyStats").remember_question(_app_state().subject_id, question)
	shuffled_options = question.get("options", []).duplicate()
	if not question.get("preserve_option_order", false):
		shuffled_options.shuffle()
	_restore_current_question_state()
	question_label.text = "%d. %s" % [question["id"], question["stem"]]
	_build_fill_inputs()
	_build_question_images(question.get("images", []))
	submit_button.visible = question["type"] in ["multiple", "fill", "output"]
	submit_button.disabled = has_answered
	question_label.scroll_to_line(0)
	question_scroll.set_deferred("scroll_vertical", 0)

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
	_refresh_question_number_states()
	prev_button.disabled = current_index == 0
	next_button.disabled = current_index == questions.size() - 1
	_update_wrong_button()
	if is_instance_valid(minimal_view):
		minimal_view.question_changed()


func _restore_current_question_state() -> void:
	selected_indices.clear()
	entered_answers.clear()
	has_answered = false
	reference_revealed = false
	if _is_program_question():
		entered_answers.append(str(_app_state().program_drafts.get(str(questions[current_index].get("source_id", "")), "")))
	var state_key := _question_state_key(current_index)
	if not question_states.has(state_key):
		return

	var state: Dictionary = question_states[state_key]
	# A completed attempt remains in the number list, but revisiting starts a new
	# attempt. Unsubmitted drafts (including a retry draft) still restore below.
	if bool(state.get("submitted", state.get("answered", false))) and not _is_program_question():
		return
	reference_revealed = bool(state.get("reference_revealed", false))
	entered_answers.clear()
	for answer in state.get("fill_answers", []):
		entered_answers.append(str(answer))
	var selected_keys: Array = state.get("selected_keys", [])
	for index in shuffled_options.size():
		if selected_keys.has(str(shuffled_options[index].get("key", ""))):
			selected_indices.append(index)


func _save_current_question_state() -> void:
	var previous: Dictionary = question_states.get(_question_state_key(current_index), {})
	var selected_keys: Array[String] = []
	for index in selected_indices:
		selected_keys.append(str(shuffled_options[index].get("key", "")))
	question_states[_question_state_key(current_index)] = {
		"selected_keys": selected_keys,
		"fill_answers": entered_answers.duplicate(),
		"answered": has_answered or bool(previous.get("answered", false)),
		"submitted": has_answered,
		"reference_revealed": reference_revealed,
		"correct": _is_selection_correct() if has_answered else bool(previous.get("correct", false)),
	}


func _question_state_key(index: int) -> String:
	if index < 0 or index >= questions.size():
		return ""
	return str(questions[index].get("id", index + 1))


func _on_option_pressed(index: int) -> void:
	if _is_text_question() or has_answered or index >= shuffled_options.size():
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
	if _is_output_question():
		if entered_answers[0].strip_edges().is_empty():
			result_label.add_theme_color_override("font_color", _wrong_feedback_color())
			result_label.text = "请输入程序输出"
			output_input.grab_focus()
			return
	elif _is_fill_question():
		for index in fill_inputs.size():
			if entered_answers[index].strip_edges().is_empty():
				result_label.add_theme_color_override("font_color", _wrong_feedback_color())
				result_label.text = "请填写第 %d 空" % (index + 1)
				fill_inputs[index].grab_focus()
				return
	elif selected_indices.is_empty():
		result_label.add_theme_color_override("font_color", _wrong_feedback_color())
		result_label.text = "请至少选择一个选项"
		return
	_reveal_answer()


func _reveal_answer() -> void:
	has_answered = true
	for field in fill_inputs:
		field.editable = false
	if output_input != null:
		output_input.editable = false
	var correct := _is_selection_correct()
	_app_state().register_quiz_answer(correct)
	get_node("/root/StudyStats").record_answer(_app_state().subject_id, questions[current_index], correct)
	_save_current_question_state()
	_refresh_option_text()
	_refresh_all_option_visuals()
	_refresh_answer_feedback()
	_refresh_question_number_states()
	submit_button.disabled = true


func _refresh_answer_feedback() -> void:
	answer_label.visible = has_answered and not _is_program_question()
	if not has_answered or _is_program_question():
		result_label.text = ""
		answer_label.text = ""
		return
	var correct := _is_selection_correct()
	result_label.text = "回答正确" if correct else "回答错误"
	result_label.add_theme_color_override(
		"font_color",
		_correct_feedback_color() if correct else _wrong_feedback_color(),
	)
	if _is_output_question():
		answer_label.text = "%s：\n%s\n\n%s" % [
			str(questions[current_index].get("answer_title", "参考输出（原资料）")),
			"\n或\n".join(questions[current_index]["answers"]),
			str(questions[current_index].get("explanation", "")),
		]
	elif _is_fill_question():
		var lines: Array[String] = ["参考答案（原资料）：" if questions[current_index].get("language", "") == "cpp" else "参考答案："]
		var blanks: Array = questions[current_index]["blanks"]
		for index in blanks.size():
			lines.append("（%d）%s" % [index + 1, " 或 ".join(blanks[index]["answers"])])
		var explanation := str(questions[current_index].get("explanation", ""))
		if not explanation.is_empty():
			lines.append(explanation)
		answer_label.text = "\n".join(lines)
	else:
		var answer_title := "参考答案（原资料）" if questions[current_index].get("language", "") in ["cpp", "python"] else "正确答案"
		answer_label.text = "%s：%s" % [answer_title, _correct_display_text()]
		var explanation := str(questions[current_index].get("explanation", ""))
		if not explanation.is_empty():
			answer_label.text += "\n\n" + explanation


func _is_fill_question() -> bool:
	return (
		current_index >= 0 and current_index < questions.size()
		and questions[current_index].get("type", "") == "fill"
	)


func _is_output_question() -> bool:
	return (
		current_index >= 0 and current_index < questions.size()
		and questions[current_index].get("type", "") == "output"
	)


func _is_text_question() -> bool:
	return _is_fill_question() or _is_output_question() or _is_program_question()


func _is_program_question() -> bool:
	return current_index >= 0 and current_index < questions.size() and questions[current_index].get("type", "") == "program"


func _build_question_images(paths: Array) -> void:
	for child in question_images.get_children():
		question_images.remove_child(child)
		child.queue_free()
	question_images.visible = not paths.is_empty()
	for path in paths:
		var picture := TextureRect.new()
		picture.texture = load(str(path))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picture.resized.connect(_fit_question_image.bind(picture))
		question_images.add_child(picture)
		_fit_question_image.call_deferred(picture)


func _fit_question_image(picture: TextureRect) -> void:
	if is_instance_valid(picture) and picture.texture != null and picture.size.x > 0:
		var display_width := minf(picture.size.x, picture.texture.get_width() * 3.0)
		picture.custom_minimum_size.y = ceilf(display_width * picture.texture.get_height() / picture.texture.get_width())


func _build_fill_inputs() -> void:
	for child in fill_answers_box.get_children():
		fill_answers_box.remove_child(child)
		child.queue_free()
	fill_inputs.clear()
	output_input = null
	program_editor = null
	answer_margin.visible = _is_text_question()
	fill_answers_box.visible = _is_text_question()
	if not _is_text_question():
		return
	if _is_program_question():
		program_editor = ProgramEditor.new()
		fill_answers_box.add_child(program_editor)
		program_editor.configure(questions[current_index], entered_answers[0], reference_revealed)
		program_editor.draft_changed.connect(_on_program_draft_changed.bind(str(questions[current_index]["source_id"])))
		program_editor.reference_toggled.connect(_on_program_reference_toggled)
		_apply_quiz_font_scale(program_editor)
		_app_state().apply_color_mode(program_editor)
		program_editor.apply_palette(_is_dark_mode())
		return
	if _is_output_question():
		_build_output_input()
		return
	var blanks: Array = questions[current_index]["blanks"]
	while entered_answers.size() < blanks.size():
		entered_answers.append("")
	for index in blanks.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		fill_answers_box.add_child(row)
		var label := Label.new()
		label.text = "（%d）" % (index + 1)
		label.add_theme_font_size_override("font_size", 40)
		row.add_child(label)
		var field := LineEdit.new()
		field.custom_minimum_size = Vector2(0, 80)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.placeholder_text = "填写第 %d 空" % (index + 1)
		field.text = entered_answers[index]
		field.editable = not has_answered
		field.add_theme_font_override("font", CODE_FONT)
		field.add_theme_font_size_override("font_size", 40)
		field.text_changed.connect(_on_fill_text_changed.bind(index))
		field.text_submitted.connect(_on_fill_enter.bind(index))
		row.add_child(field)
		fill_inputs.append(field)
	_apply_quiz_font_scale(fill_answers_box)
	_app_state().apply_color_mode(fill_answers_box)
	_style_fill_inputs()


func _build_output_input() -> void:
	if entered_answers.is_empty():
		entered_answers.append("")
	var hint := Label.new()
	hint.text = str(questions[current_index].get("answer_prompt", "填写程序输出（Enter 换行，点击下方按钮提交）"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 34)
	fill_answers_box.add_child(hint)
	output_input = TextEdit.new()
	output_input.name = "OutputInput"
	output_input.custom_minimum_size = Vector2(0, 280)
	output_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	output_input.placeholder_text = "在这里填写输出结果，可输入多行"
	output_input.text = entered_answers[0]
	output_input.editable = not has_answered
	output_input.add_theme_font_override("font", CODE_FONT)
	output_input.add_theme_font_size_override("font_size", 40)
	output_input.text_changed.connect(_on_output_text_changed)
	fill_answers_box.add_child(output_input)
	_apply_quiz_font_scale(fill_answers_box)
	_app_state().apply_color_mode(fill_answers_box)
	_style_fill_inputs()


func _on_output_text_changed() -> void:
	if has_answered or output_input == null:
		return
	entered_answers[0] = output_input.text
	_save_current_question_state()
	result_label.text = ""


func _on_program_draft_changed(code: String, source_id: String) -> void:
	_app_state().set_program_draft(source_id, code)
	if not _is_program_question() or questions[current_index]["source_id"] != source_id:
		return
	entered_answers[0] = code
	_save_current_question_state()


func _on_program_reference_toggled(revealed: bool) -> void:
	reference_revealed = revealed
	if revealed:
		get_node("/root/StudyStats").record_review(_app_state().subject_id, questions[current_index])
	_save_current_question_state()


func _on_fill_text_changed(text: String, index: int) -> void:
	if has_answered:
		return
	entered_answers[index] = text
	_save_current_question_state()
	result_label.text = ""


func _on_fill_enter(_text: String, index: int) -> void:
	if index + 1 < fill_inputs.size():
		fill_inputs[index + 1].grab_focus()
	else:
		_submit_multiple_answer()


func _style_fill_inputs() -> void:
	if program_editor != null:
		program_editor.apply_palette(_is_dark_mode())
	var accent := DARK_ACCENT if _is_dark_mode() else HEBUT_BLUE
	var border := DARK_BORDER if _is_dark_mode() else OPTION_BORDER
	var background_color := DARK_OPTION if _is_dark_mode() else Color.WHITE
	for field in fill_inputs:
		field.add_theme_color_override("font_color", _ink_color())
		field.add_theme_color_override("font_uneditable_color", _ink_color())
		field.add_theme_color_override("caret_color", _ink_color())
		field.add_theme_color_override("font_placeholder_color", DARK_MUTED if _is_dark_mode() else LIGHT_MUTED)
		field.add_theme_stylebox_override("normal", _jump_input_style(background_color, border, 2))
		field.add_theme_stylebox_override("read_only", _jump_input_style(background_color, border, 2))
		field.add_theme_stylebox_override("focus", _jump_input_style(background_color, accent, 2))
		get_node("/root/UiMotion").bind_input.call_deferred(field)
	if output_input != null:
		output_input.add_theme_color_override("font_color", _ink_color())
		output_input.add_theme_color_override("font_readonly_color", _ink_color())
		output_input.add_theme_color_override("caret_color", _ink_color())
		output_input.add_theme_color_override("font_placeholder_color", DARK_MUTED if _is_dark_mode() else LIGHT_MUTED)
		output_input.add_theme_color_override("selection_color", Color(accent, 0.26))
		output_input.add_theme_stylebox_override("normal", _jump_input_style(background_color, border, 2))
		output_input.add_theme_stylebox_override("read_only", _jump_input_style(background_color, border, 2))
		output_input.add_theme_stylebox_override("focus", _jump_input_style(background_color, accent, 2))


func _refresh_all_option_visuals() -> void:
	for index in shuffled_options.size():
		_refresh_option_visual(index)


func _refresh_option_visual(index: int) -> void:
	var button := option_buttons[index]
	button.disabled = has_answered
	var icon_name := "circle-dot" if selected_indices.has(index) else "circle"
	if has_answered and bool(shuffled_options[index].get("correct", false)):
		icon_name = "check"
	elif has_answered and selected_indices.has(index):
		icon_name = "x"
	button.icon = load("res://assets/minimal/icons/%s.png" % icon_name)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 26)
	button.add_theme_constant_override("h_separation", 18)
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
	if not is_selected and not has_answered:
		for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
			button.add_theme_color_override(state, DARK_MUTED if is_dark else Color("#AEB6C2"))
	get_node("/root/UiMotion").bind_button(button, false, true)


func _option_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24.0
	style.content_margin_right = 20.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _set_option_color(button: Button, color: Color) -> void:
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color",
		"font_disabled_color",
		"icon_normal_color",
		"icon_hover_color",
		"icon_pressed_color",
		"icon_focus_color",
		"icon_hover_pressed_color",
		"icon_disabled_color",
	]:
		button.add_theme_color_override(color_name, color)


func _is_selection_correct() -> bool:
	if _is_program_question():
		return false
	if _is_output_question():
		return OutputAnswer.is_correct(questions[current_index]["answers"], entered_answers[0], str(questions[current_index].get("answer_mode", "literal")))
	if _is_fill_question():
		return FillAnswer.is_correct(questions[current_index]["blanks"], entered_answers, str(questions[current_index].get("language", "python")))
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
	var option_text := str(shuffled_options[index]["text"])
	return "%s. %s" % [DISPLAY_LETTERS[index], option_text]


func _refresh_option_text() -> void:
	for index in shuffled_options.size():
		option_buttons[index].text = _option_display_text(index)


func _toggle_wrong_current() -> void:
	var id := str(questions[current_index]["id"])
	var previous := wrong_ids.duplicate()
	if wrong_ids.has(id):
		wrong_ids.erase(id)
		if not _save_wrong_ids():
			_wrong_save_failed(previous)
			return
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
		if not _save_wrong_ids():
			_wrong_save_failed(previous)
			return
	_update_wrong_button()

func _wrong_save_failed(previous: Dictionary) -> void:
	wrong_ids = previous
	_update_wrong_button()
	result_label.text = "错题库保存失败，请重试。"
	result_label.add_theme_color_override("font_color", _wrong_feedback_color())
	get_node("/root/UiMotion").enter(result_label, Tokens.STATE)


func _update_wrong_button() -> void:
	var is_collected := wrong_ids.has(str(questions[current_index]["id"]))
	wrong_toggle.text = "已加入错题库" if is_collected else "加入错题库"
	if is_instance_valid(minimal_view):
		minimal_view.refresh()


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


func consume_back_action() -> bool:
	if is_instance_valid(minimal_view) and minimal_view.canvas.size.x < 1400 and minimal_view.compact_rail_open:
		minimal_view._toggle_rail()
		return true
	return false


func _go_home() -> void:
	get_node("/root/PageRouter").go("res://scenes/Workbench.tscn")


func _load_wrong_ids() -> Dictionary:
	var ids := {}
	for id in _load_json_array(_subject()["wrong_path"]):
		ids[str(id)] = true
	return ids


func _save_wrong_ids() -> bool:
	var ids := []
	for id in wrong_ids.keys():
		ids.append(int(id))
	ids.sort()
	var file := FileAccess.open(_subject()["wrong_path"], FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(ids, "  "))
		file.flush()
		var saved := file.get_error() == OK
		if saved:
			get_node("/root/StudyStats").changed.emit()
		return saved
	return false


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


func _apply_quiz_font_scale(root: Node) -> void:
	if is_instance_valid(minimal_view):
		minimal_view._font_controls(root)


func _ink_color() -> Color:
	return _app_state().get_foreground_color()


func _refresh_interaction_colors() -> void:
	if is_instance_valid(minimal_view):
		minimal_view.refresh()


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


func _correct_feedback_color() -> Color:
	return DARK_CORRECT if _is_dark_mode() else CORRECT_COLOR


func _wrong_feedback_color() -> Color:
	return DARK_WRONG if _is_dark_mode() else WRONG_COLOR


func _is_dark_mode() -> bool:
	return bool(_app_state().dark_mode)
