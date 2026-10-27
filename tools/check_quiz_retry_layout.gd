extends "res://tools/check_minimal_design.gd"
## Regression coverage for clipped short questions and repeat attempts.

func _frames() -> void:
	for frame in 8:
		await process_frame

func _attempts() -> int:
	return int(stats.history.get(Time.get_date_string_from_system(), {}).get("attempts", 0))

func _correct_answer(quiz: Node) -> void:
	var question: Dictionary = quiz.questions[quiz.current_index]
	match str(question.type):
		"fill":
			for index in quiz.fill_inputs.size():
				var field: LineEdit = quiz.fill_inputs[index]
				field.text = str(question.blanks[index].answers[0])
				field.text_changed.emit(field.text)
		"output":
			quiz.output_input.text = str(question.answers[0])
			quiz.output_input.text_changed.emit()
		_:
			for index in quiz.shuffled_options.size():
				if quiz.shuffled_options[index].correct:
					quiz.option_buttons[index].pressed.emit()
	if quiz.submit_button.visible:
		quiz.submit_button.pressed.emit()

func _short_question_fits(quiz: Node, name: String) -> void:
	await _frames()
	var area: Rect2 = quiz.question_scroll.get_global_rect()
	for control in [quiz.question_label, quiz.submit_button] + quiz.option_buttons:
		if control.is_visible_in_tree():
			var bounds: Rect2 = control.get_global_rect()
			_expect(bounds.position.y >= area.position.y - 1 and bounds.end.y <= area.end.y + 1, name + ": full stem, choices and submit button fit without scrolling: " + str(control.name))
	_expect(quiz.question_scroll.get_child(0).get_combined_minimum_size().y <= quiz.question_scroll.size.y + 1, name + ": short question does not require a scrollbar")
	for action in [quiz.prev_button, quiz.next_button, quiz.wrong_toggle]:
		_expect(action.get_global_rect().position.y > area.end.y, name + ": footer does not cover question controls")

func _retry(quiz: Node, kind: String) -> void:
	var target := -1
	for index in quiz.questions.size():
		if quiz.questions[index].type == kind:
			target = index
			break
	_expect(target >= 0, "Real bank contains " + kind)
	if target < 0:
		return
	quiz._jump_to(target)
	var key: String = quiz._question_state_key(target)
	var attempts := _attempts()
	_correct_answer(quiz)
	_expect(quiz.has_answered and quiz.result_label.text == "回答正确" and _attempts() == attempts + 1, kind + ": first submission is graded once")
	quiz._submit_multiple_answer()
	_expect(_attempts() == attempts + 1, kind + ": duplicate submit does not record another attempt")
	quiz._jump_to((target + 1) % quiz.questions.size())
	quiz._jump_to(target)
	await _frames()
	_expect(not quiz.has_answered and quiz.selected_indices.is_empty() and quiz.answer_label.text.is_empty() and not quiz.answer_label.visible, kind + ": revisit starts without selections or reference answers")
	_expect(_attempts() == attempts + 1 and quiz.question_states[key].answered, kind + ": reopening preserves completion and does not count as an answer")
	_expect(quiz.minimal_view.number_buttons[target].accessibility_name.contains("已答"), kind + ": number list retains answered status")
	for button in quiz.option_buttons:
		if button.visible:
			_expect(not button.disabled, kind + ": choices accept input on retry")
	for field in quiz.fill_inputs:
		_expect(field.editable and field.text.is_empty(), kind + ": fill fields are editable and cleared")
	if quiz.output_input != null:
		_expect(quiz.output_input.editable and quiz.output_input.text.is_empty(), kind + ": output field is editable and cleared")
	if kind in ["multiple", "fill", "output"]:
		_expect(not quiz.submit_button.disabled, kind + ": submit is re-enabled")
		# A partially edited retry is a draft, even though this number is already answered.
		if kind == "multiple":
			quiz.option_buttons[0].pressed.emit()
		elif kind == "fill":
			quiz.fill_inputs[0].text = "retry draft"
			quiz.fill_inputs[0].text_changed.emit("retry draft")
		else:
			quiz.output_input.text = "retry draft"
			quiz.output_input.text_changed.emit()
		var draft: Dictionary = quiz.question_states[key].duplicate(true)
		quiz._jump_to((target + 1) % quiz.questions.size())
		quiz._jump_to(target)
		_expect(not quiz.has_answered and quiz.question_states[key] == draft and draft.answered, kind + ": incomplete retry preserves its draft and completed status")
		if kind == "multiple":
			_expect(quiz.selected_indices.size() == 1, "Multiple retry restores one selected option")
			quiz.option_buttons[quiz.selected_indices[0]].pressed.emit()
		elif kind == "fill":
			_expect(quiz.fill_inputs[0].text == "retry draft", "Fill retry restores draft text")
		else:
			_expect(quiz.output_input.text == "retry draft", "Output retry restores draft text")
	_correct_answer(quiz)
	_expect(quiz.has_answered and quiz.result_label.text == "回答正确" and _attempts() == attempts + 2, kind + ": second attempt can be submitted and counted once")
	quiz._submit_multiple_answer()
	_expect(_attempts() == attempts + 2, kind + ": repeated retry submission is ignored")
	var snapshot: Dictionary = quiz.question_states.duplicate(true)
	quiz.minimal_view._toggle_distraction_free()
	quiz.minimal_view._toggle_distraction_free()
	_expect(quiz.has_answered and quiz.question_states == snapshot and _attempts() == attempts + 2, kind + ": F6 changes layout without resetting the current answer")

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	app = root.get_node("AppState")
	stats = root.get_node("StudyStats")
	root.mode = Window.MODE_WINDOWED
	app.quiz_mode = "all"
	app.subject_id = "marxism"
	app.start_index = 38
	# Match the screenshot's usable 1920 x 1008 window, then a shorter window.
	root.content_scale_size = Vector2i(1600, 840)
	root.size = Vector2i(1920, 1008)
	var quiz: Node = await _open("Quiz")
	for height in [840, 750]:
		root.content_scale_size = Vector2i(1600, height)
		root.size = Vector2i(1600, height)
		for focus in [false, true]:
			if quiz.minimal_view.distraction_free != focus:
				quiz.minimal_view._toggle_distraction_free()
			await _short_question_fits(quiz, "height=%d focus=%s" % [height, focus])
			await _capture("quiz-compact-%d-%s" % [height, "focus" if focus else "normal"])
	# Long content must still wrap and scroll instead of clipping or shrinking text.
	var longest := 0
	for index in quiz.questions.size():
		if quiz.questions[index].stem.length() > quiz.questions[longest].stem.length():
			longest = index
	quiz._jump_to(longest)
	await _frames()
	_expect(quiz.question_label.size.y >= quiz.question_label.get_content_height(), "Long stems grow to their full wrapped height")
	root.content_scale_size = Vector2i(1600, 840)
	root.size = Vector2i(1600, 840)
	app.subject_id = "matlab"
	app.start_index = 0
	quiz = await _open("Quiz")
	for kind in ["single", "multiple", "judge"]:
		await _retry(quiz, kind)
	app.subject_id = "cpp"
	quiz = await _open("Quiz")
	for kind in ["fill", "output"]:
		await _retry(quiz, kind)
	# Wrong-bank sessions use the same retry behavior with IDs unrelated to list indices.
	app.subject_id = "matlab"
	var ids: Array = [stats.banks.matlab[0].id, stats.banks.matlab[225].id]
	var file := FileAccess.open(app.get_subject().wrong_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(ids))
	file.close()
	app.quiz_mode = "wrong"
	app.start_index = 0
	quiz = await _open("Quiz")
	await _retry(quiz, "multiple")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
