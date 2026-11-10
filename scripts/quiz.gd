extends Control
## Coordinates one session, domain services and view signals. No widget styling or grading.
const Collection = preload("res://scripts/manual_question_collection.gd")
const Session = preload("res://scripts/quiz_session.gd")
const ContentView = preload("res://scripts/quiz_content_view.gd")
const LayoutView = preload("res://scripts/minimal_quiz_view.gd")
const WalletBridge = preload("res://scripts/quiz_wallet_bridge.gd")
var session := Session.new()
var content: ContentView
var minimal_view: Control
var wallet_bridge: Node
var subject_id := ""
var wrong_mode := false

# Compatibility accessors for integration clients; views bind directly to the session.
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
var empty_label: Label:
	get: return content.empty_label
var jump_input: LineEdit:
	get: return content.jump_input
var jump_button: Button:
	get: return content.jump_button
var question_scroll: ScrollContainer:
	get: return content.question_scroll
var question_label: RichTextLabel:
	get: return content.question_label
var submit_button: Button:
	get: return content.submit_button
var answer_margin: MarginContainer:
	get: return content.answer_margin
var fill_answers_box: VBoxContainer:
	get: return content.fill_answers_box
var result_label: Label:
	get: return content.result_label
var answer_label: Label:
	get: return content.answer_label
var prev_button: Button:
	get: return content.prev_button
var next_button: Button:
	get: return content.next_button
var wrong_toggle: Button:
	get: return content.wrong_toggle
var home_button: Button:
	get: return content.home_button
var option_buttons: Array[Button]:
	get: return content.option_buttons
var fill_inputs: Array[LineEdit]:
	get: return content.fill_inputs
var output_input: TextEdit:
	get: return content.output_input
var program_editor: VBoxContainer:
	get: return content.program_editor
var question_images: VBoxContainer:
	get: return content.question_images

func _ready() -> void:
	var app := get_node("/root/AppState")
	subject_id = app.subject_id
	wrong_mode = app.quiz_mode == "wrong"
	session.configure(get_node("/root/StudyStats").banks.get(subject_id, []), _wrongs().ids(subject_id), wrong_mode, app.start_index)
	content = ContentView.new()
	content.name = "QuestionContentView"
	add_child(content)
	content.bind(self, session)
	content.option_chosen.connect(_on_option_pressed)
	content.submit_requested.connect(_submit_multiple_answer)
	content.jump_requested.connect(_jump_to)
	content.wrong_toggle_requested.connect(_toggle_wrong_current)
	content.back_requested.connect(get_node("/root/PageRouter").back)
	content.finish_requested.connect(_finish_practice)
	content.answer_edited.connect(_answer_edited)
	content.program_draft_edited.connect(_on_program_draft_changed)
	content.reference_changed.connect(_on_program_reference_toggled)
	content.empty_label.text = "%s%s" % [app.get_subject().title, "错题库暂无题目" if wrong_mode else "题库暂无题目"]
	minimal_view = LayoutView.new()
	minimal_view.content = content
	content.minimal_view = minimal_view
	minimal_view.size = size
	add_child(minimal_view)
	minimal_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wallet_bridge = WalletBridge.new()
	wallet_bridge.session = session
	add_child(wallet_bridge)
	wallet_bridge.feedback_changed.connect(_reward_feedback_changed)
	if not questions.is_empty(): _show_question()

func _wrongs() -> Node:
	return get_node("/root/AppServices").wrong_questions()

func _show_question() -> void:
	var question := session.current()
	var draft := str(get_node("/root/AppState").program_drafts.get(str(question.get("source_id", "")), ""))
	session.open_question(current_index, draft)
	get_node("/root/StudyStats").remember_question(subject_id, question)
	content.reward_feedback = ""
	content.render_question()
	wallet_bridge.prepare(subject_id, question)

func _on_option_pressed(index: int) -> void:
	match session.select_option(index):
		"selection": content.render_selection()
		"submit": _reveal_answer()

func _submit_multiple_answer() -> void:
	if has_answered: return
	var issue := session.submission_issue()
	if not issue.is_empty():
		content.show_submission_issue(issue)
		return
	_reveal_answer()

func _reveal_answer() -> void:
	if not session.submit(): return
	get_node("/root/StudyStats").record_answer(subject_id, session.current(), session.is_correct())
	content.render_answer()
	wallet_bridge.submit()

func _answer_edited(index: int, value: String) -> void:
	if has_answered: return
	session.set_answer(index, value)
	content.result_label.text = ""

func _on_program_draft_changed(code: String, source_id: String) -> void:
	get_node("/root/AppState").set_program_draft(source_id, code)
	if session.is_kind("program") and str(session.current().get("source_id", "")) == source_id:
		session.set_answer(0, code)

func _on_program_reference_toggled(revealed: bool) -> void:
	session.set_reference(revealed)
	if revealed: get_node("/root/StudyStats").record_review(subject_id, session.current())

func _refresh_answer_feedback() -> void:
	content.reward_feedback = str(wallet_bridge.feedback)
	content._refresh_answer_feedback()

func _reward_feedback_changed() -> void:
	_refresh_answer_feedback()
	get_node("/root/UiMotion").enter(content.result_label)

func _question_state_key(index: int) -> String:
	return session.state_key(index)

func _toggle_wrong_current() -> void:
	var id := str(session.current().id)
	var removing := wrong_ids.has(id)
	var next := Collection.toggled(wrong_ids, id)
	if not _wrongs().save_ids(subject_id, next):
		content.show_save_error()
		return
	session.wrong_ids = next
	if wrong_mode and removing:
		session.questions.remove_at(current_index)
		if questions.is_empty():
			_go_home()
			return
		session.current_index = mini(current_index, questions.size() - 1)
		content._update_jump_search_hint()
		minimal_view.build_numbers()
		_show_question()
	else:
		content._update_wrong_button()

func _jump_to(index: int) -> void:
	if index < 0 or index >= questions.size(): return
	session.current_index = index
	get_node("/root/AppState").start_index = index
	_show_question()

func consume_back_action() -> bool:
	if is_instance_valid(minimal_view) and minimal_view.right_mode != "numbers":
		minimal_view.show_right_pane("numbers")
		return true
	if is_instance_valid(minimal_view) and minimal_view.canvas.size.x < 1400 and minimal_view.compact_rail_open:
		minimal_view._toggle_rail()
		return true
	return false

func _go_home() -> void:
	get_node("/root/PageRouter").go("res://scenes/Workbench.tscn")

func _finish_practice() -> void:
	if minimal_view.finish.disabled: return
	minimal_view.finish.disabled = true
	minimal_view.finish.text = "结算中…"
	await wallet_bridge.finish()
	if is_inside_tree(): _go_home()
