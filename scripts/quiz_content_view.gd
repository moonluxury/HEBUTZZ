extends Control
## Rendering and input widgets. Sends user intent through signals, never calls the controller.
const Session = preload("res://scripts/quiz_session.gd")
const Styles = preload("res://scripts/ui_styles.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const ProgramEditor = preload("res://scripts/program_editor.gd")
const CODE_FONT = preload("res://themes/code_font.tres")
const DISPLAY_LETTERS := ["A", "B", "C", "D", "E", "F"]
signal option_chosen(index: int)
signal submit_requested
signal jump_requested(index: int)
signal wrong_toggle_requested
signal back_requested
signal finish_requested
signal answer_edited(index: int, value: String)
signal program_draft_edited(code: String, source_id: String)
signal reference_changed(revealed: bool)
var session: Session
var minimal_view: Control
var reward_feedback := ""
const CORRECT_COLOR = Styles.CORRECT_COLOR
const WRONG_COLOR = Styles.WRONG_COLOR
const HEBUT_BLUE = Styles.HEBUT_BLUE
const OPTION_SELECTED_BG = Styles.OPTION_SELECTED_BG
const OPTION_CORRECT_BG = Styles.OPTION_CORRECT_BG
const OPTION_WRONG_BG = Styles.OPTION_WRONG_BG
const OPTION_BORDER = Styles.OPTION_BORDER
const LIGHT_BACKGROUND = Styles.LIGHT_BACKGROUND
const LIGHT_TEXT = Styles.LIGHT_TEXT
const LIGHT_MUTED = Styles.LIGHT_MUTED
const DARK_BACKGROUND = Styles.DARK_BACKGROUND
const DARK_HEADER = Styles.DARK_HEADER
const DARK_CARD = Styles.DARK_CARD
const DARK_OPTION = Styles.DARK_OPTION
const DARK_OPTION_HOVER = Styles.DARK_OPTION_HOVER
const DARK_BORDER = Styles.DARK_BORDER
const DARK_TEXT = Styles.DARK_TEXT
const DARK_MUTED = Styles.DARK_MUTED
const DARK_ACCENT = Styles.DARK_ACCENT
const DARK_ACCENT_SURFACE = Styles.DARK_ACCENT_SURFACE
const DARK_CORRECT = Styles.DARK_CORRECT
const DARK_CORRECT_SURFACE = Styles.DARK_CORRECT_SURFACE
const DARK_WRONG = Styles.DARK_WRONG
const DARK_WRONG_SURFACE = Styles.DARK_WRONG_SURFACE
var all_questions: Array:
	get: return session.all_questions
var questions: Array:
	get: return session.questions
var wrong_ids: Dictionary:
	get: return session.wrong_ids
var question_states: Dictionary:
	get: return session.question_states
var current_index: int:
	get: return session.current_index
var shuffled_options: Array:
	get: return session.shuffled_options
var selected_indices: Array:
	get: return session.selected_indices
var entered_answers: Array[String]:
	get: return session.entered_answers
var reference_revealed: bool:
	get: return session.reference_revealed
var has_answered: bool:
	get: return session.has_answered
var empty_label: Label
var jump_input: LineEdit
var jump_button: Button
var question_scroll: ScrollContainer
var question_label: RichTextLabel
var submit_button: Button
var answer_margin: MarginContainer
var fill_answers_box: VBoxContainer
var result_label: Label
var answer_label: Label
var prev_button: Button
var next_button: Button
var wrong_toggle: Button
var home_button: Button
var option_buttons: Array[Button] = []
var fill_inputs: Array[LineEdit] = []
var output_input: TextEdit
var program_editor: VBoxContainer
var question_images: VBoxContainer

func bind(owner_control: Control, practice: Session) -> void:
	session = practice
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = get_node("/root/UiResources").page_theme
	empty_label = owner_control.get_node("EmptyLabel")
	jump_input = owner_control.get_node("JumpInput")
	jump_button = owner_control.get_node("JumpButton")
	question_scroll = owner_control.get_node("QuestionScroll")
	question_label = owner_control.get_node("QuestionScroll/Content/QuestionLabel")
	submit_button = owner_control.get_node("QuestionScroll/Content/SubmitRow/SubmitButton")
	answer_margin = owner_control.get_node("QuestionScroll/Content/AnswerMargin")
	fill_answers_box = owner_control.get_node("QuestionScroll/Content/AnswerMargin/FillAnswers")
	result_label = owner_control.get_node("QuestionScroll/Content/SubmitRow/ResultLabel")
	answer_label = owner_control.get_node("QuestionScroll/Content/AnswerLabel")
	prev_button = owner_control.get_node("PrevButton")
	next_button = owner_control.get_node("NextButton")
	wrong_toggle = owner_control.get_node("WrongToggle")
	home_button = owner_control.get_node("HomeButton")
	for index in 6:
		option_buttons.append(owner_control.get_node("QuestionScroll/Content/Option%d" % (index + 1)))
	question_images = VBoxContainer.new()
	question_images.name = "QuestionImages"
	question_label.get_parent().add_child(question_images)
	question_label.get_parent().move_child(question_images, question_label.get_index() + 1)
	_connect_controls()

func _connect_controls() -> void:
	for index in option_buttons.size(): option_buttons[index].pressed.connect(option_chosen.emit.bind(index))
	submit_button.pressed.connect(submit_requested.emit)
	prev_button.pressed.connect(func(): jump_requested.emit(current_index - 1))
	next_button.pressed.connect(func(): jump_requested.emit(current_index + 1))
	wrong_toggle.pressed.connect(wrong_toggle_requested.emit)
	home_button.pressed.connect(back_requested.emit)
	jump_button.pressed.connect(_jump_from_search)
	jump_input.text_submitted.connect(_jump_from_search.unbind(1))

func request_jump(index: int) -> void:
	jump_requested.emit(index)

func request_finish() -> void:
	finish_requested.emit()

func _question_state_key(index: int) -> String:
	return session.state_key(index)

func _is_selection_correct() -> bool:
	return session.is_correct()

func render_selection() -> void:
	_refresh_option_text()
	_refresh_all_option_visuals()
	result_label.add_theme_color_override("font_color", _ink_color())
	result_label.text = "已选：%s" % _selected_display_text()

func render_answer() -> void:
	for field in fill_inputs: field.editable = false
	if output_input != null: output_input.editable = false
	_refresh_option_text()
	_refresh_all_option_visuals()
	_refresh_answer_feedback()
	_refresh_question_number_states()
	submit_button.disabled = true

func show_submission_issue(issue: Dictionary) -> void:
	result_label.add_theme_color_override("font_color", _wrong_feedback_color())
	result_label.text = issue.message
	if _is_output_question(): output_input.grab_focus()
	elif _is_fill_question() and issue.field >= 0: fill_inputs[issue.field].grab_focus()

func show_save_error() -> void:
	_update_wrong_button()
	result_label.text = "错题库保存失败，请重试。"
	result_label.add_theme_color_override("font_color", _wrong_feedback_color())
	get_node("/root/UiMotion").enter(result_label, Tokens.STATE)

func _populate_question_numbers() -> void:
	if is_instance_valid(minimal_view):
		minimal_view.build_numbers()

func _refresh_question_number_states() -> void:
	if is_instance_valid(minimal_view):
		minimal_view.refresh_numbers()

func render_question() -> void:
	# Reused option controls must never interpolate from the previous question's result.
	for button in option_buttons:
		button.set_meta("motion_snap", true)
	var question: Dictionary = questions[current_index]
	# Display the practice position; stable source IDs remain the save keys.
	question_label.text = "%d. %s" % [current_index + 1, question["stem"]]
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
	if not reward_feedback.is_empty(): result_label.text += " · " + reward_feedback

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
		program_editor.draft_changed.connect(program_draft_edited.emit.bind(str(questions[current_index]["source_id"])))
		program_editor.reference_toggled.connect(reference_changed.emit)
		_apply_quiz_font_scale(program_editor)
		Styles.apply_text_palette(program_editor, _is_dark_mode())
		program_editor.apply_palette(_is_dark_mode())
		return
	if _is_output_question():
		_build_output_input()
		return
	var blanks: Array = questions[current_index]["blanks"]
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
		field.text_changed.connect(func(value: String): answer_edited.emit(index, value))
		field.text_submitted.connect(_on_fill_enter.bind(index))
		row.add_child(field)
		fill_inputs.append(field)
	_apply_quiz_font_scale(fill_answers_box)
	Styles.apply_text_palette(fill_answers_box, _is_dark_mode())
	_style_fill_inputs()

func _build_output_input() -> void:
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
	output_input.text_changed.connect(func(): answer_edited.emit(0, output_input.text))
	fill_answers_box.add_child(output_input)
	_apply_quiz_font_scale(fill_answers_box)
	Styles.apply_text_palette(fill_answers_box, _is_dark_mode())
	_style_fill_inputs()

func _on_fill_enter(_text: String, index: int) -> void:
	if index + 1 < fill_inputs.size():
		fill_inputs[index + 1].grab_focus()
	else:
		submit_requested.emit()

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
		Styles.apply_focus(field, field.get_theme_stylebox("normal") as StyleBoxFlat)
		get_node("/root/UiMotion").bind_input.call_deferred(field)
	if output_input != null:
		output_input.add_theme_color_override("font_color", _ink_color())
		output_input.add_theme_color_override("font_readonly_color", _ink_color())
		output_input.add_theme_color_override("caret_color", _ink_color())
		output_input.add_theme_color_override("font_placeholder_color", DARK_MUTED if _is_dark_mode() else LIGHT_MUTED)
		output_input.add_theme_color_override("selection_color", Color(accent, 0.26))
		output_input.add_theme_stylebox_override("normal", _jump_input_style(background_color, border, 2))
		output_input.add_theme_stylebox_override("read_only", _jump_input_style(background_color, border, 2))
		Styles.apply_focus(output_input, output_input.get_theme_stylebox("normal") as StyleBoxFlat)

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
	Styles.apply_focus(button)
	button.add_theme_stylebox_override("disabled", _option_style(background, border))
	_set_option_color(button, text_color)
	if not is_selected and not has_answered:
		for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
			button.add_theme_color_override(state, DARK_MUTED if is_dark else Color("#AEB6C2"))
	get_node("/root/UiMotion").bind_button(button, false, true)

func _option_style(background: Color, border: Color) -> StyleBoxFlat:
	return Styles.option(background, border)

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

func _update_wrong_button() -> void:
	var is_collected := wrong_ids.has(str(questions[current_index]["id"]))
	wrong_toggle.text = "已加入错题库" if is_collected else "加入错题库"
	if is_instance_valid(minimal_view):
		minimal_view.refresh()

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
	jump_requested.emit(target_index)
	jump_input.clear()
	jump_input.placeholder_text = "跳转到题号"
	jump_input.release_focus()

func _update_jump_search_hint() -> void:
	jump_input.placeholder_text = "跳转到题号"

func _app_state() -> Node:
	return get_node("/root/AppState")

func _subject() -> Dictionary:
	return _app_state().get_subject()

func _apply_quiz_font_scale(root: Node) -> void:
	if is_instance_valid(minimal_view):
		minimal_view._font_controls(root)

func _ink_color() -> Color:
	return Styles.text_ink(_is_dark_mode())

func _refresh_interaction_colors() -> void:
	if is_instance_valid(minimal_view):
		minimal_view.refresh()

func _jump_input_style(background_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	return Styles.answer_input(background_color, border_color, border_width)

func _correct_feedback_color() -> Color:
	return DARK_CORRECT if _is_dark_mode() else CORRECT_COLOR

func _wrong_feedback_color() -> Color:
	return DARK_WRONG if _is_dark_mode() else WRONG_COLOR

func _is_dark_mode() -> bool:
	return bool(_app_state().dark_mode)
