extends SceneTree

var failures: Array[String] = []
var app: Node
var stats: Node
const ORDER := ["single", "multiple", "judge", "fill", "output", "program"]

func _init() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in 4:
		await process_frame

func _open(scene: String) -> Node:
	change_scene_to_file("res://scenes/" + scene + ".tscn")
	await scene_changed
	await _frames()
	return current_scene

func _ids(questions: Array) -> Array:
	return questions.map(func(question: Dictionary): return str(question.id))

func _check_display(quiz: Node) -> void:
	var index: int = quiz.current_index
	_expect(quiz.question_label.text == "%d. %s" % [index + 1, quiz.questions[index].stem], "Question text uses the displayed practice number")
	_expect(quiz.minimal_view.question_meta.text.ends_with("%d / %d" % [index + 1, quiz.questions.size()]), "Question heading uses the same practice number")

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	app = root.get_node("AppState")
	stats = root.get_node("StudyStats")
	root.get_node("UiMotion").set_enabled(false)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 984)
	root.content_scale_size = root.size
	for subject in app.SUBJECTS:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(app.SUBJECTS[subject].question_path))
		var raw: Array = parsed if parsed is Array else parsed.questions
		var bank: Array = stats.banks[subject]
		var source_by_id: Dictionary = {}
		var source_by_type: Dictionary = {}
		for question in raw:
			source_by_id[str(question.id)] = question
			if not source_by_type.has(question.type):
				source_by_type[question.type] = []
			source_by_type[question.type].append(str(question.id))
		var expected_types: Array = ORDER.filter(func(kind: String): return source_by_type.has(kind))
		var first_indices: Array[int] = []
		var actual_types: Array = []
		var actual_by_type: Dictionary = {}
		var previous := ""
		for index in bank.size():
			var question: Dictionary = bank[index]
			_expect(question == source_by_id.get(str(question.id)), subject + ": question content and source ID are unchanged")
			if question.type != previous:
				actual_types.append(question.type)
				first_indices.append(index)
				previous = question.type
			if not actual_by_type.has(question.type):
				actual_by_type[question.type] = []
			actual_by_type[question.type].append(str(question.id))
		_expect(bank.size() == raw.size() and _ids(bank).size() == source_by_id.size(), subject + ": all original questions are retained")
		_expect(actual_types == expected_types, subject + ": each type appears once in the intended order")
		for kind in expected_types:
			_expect(actual_by_type[kind] == source_by_type[kind], subject + ": original order within " + kind + " is preserved")
		var unchanged_bank := JSON.stringify(bank)
		for index in first_indices:
			stats.last_question = {"subject": subject, "id": int(bank[index].id)}
			_expect(stats.resume_target() == {"subject": subject, "index": index}, subject + ": saved question IDs resolve after grouping")
			stats.learned["%s:%s" % [subject, bank[index].id]] = true
		_expect(stats.subject_learned(subject) == first_indices.size(), subject + ": existing learned IDs retain their progress")

		# Resume an original-source question through the course selector.
		var old_id := int(raw[0].id)
		stats.last_question = {"subject": subject, "id": old_id}
		var resume: Dictionary = stats.resume_target()
		app.quiz_mode = "all"
		app.subject_id = subject
		app.start_index = resume.index
		var selector: Node = await _open("SubjectSelect")
		_expect(selector._matching_index(subject) == resume.index, subject + ": continue-learning uses the reordered index")
		selector.query = str(raw[0].stem)
		var match_index: int = selector._matching_index(subject)
		_expect(match_index >= 0 and bank[match_index].stem == raw[0].stem, subject + ": search opens the matching question")
		var quiz: Node = await _open("Quiz")
		_expect(int(quiz.questions[quiz.current_index].id) == old_id, subject + ": resume opens the original question")
		_expect(_ids(quiz.questions) == _ids(bank), subject + ": practice follows the grouped bank")
		_check_display(quiz)
		var headings: Array = []
		for row in quiz.minimal_view.number_rows:
			if row.has("title"):
				headings.append(row.title)
		var expected_headings: Array = []
		for index in first_indices:
			expected_headings.append(bank[index].type_label)
		_expect(headings == expected_headings, subject + ": question rail has one heading per type")
		for index in first_indices:
			quiz.jump_input.text = str(index + 1)
			quiz.jump_button.pressed.emit()
			_expect(quiz.current_index == index, subject + ": number search reaches each type boundary")
			_check_display(quiz)
			if index > 0:
				quiz.prev_button.pressed.emit()
				_expect(quiz.current_index == index - 1, "Previous reaches the last question in the previous type")
				quiz.next_button.pressed.emit()
				_expect(quiz.current_index == index, "Next reaches the first question in the next type")
			if bank[index].type in ["single", "multiple", "judge"]:
				for option_index in quiz.shuffled_options.size():
					if quiz.shuffled_options[option_index].correct:
						quiz.option_buttons[option_index].pressed.emit()
				if bank[index].type == "multiple":
					quiz.submit_button.pressed.emit()
				_expect(quiz.has_answered and quiz.result_label.text == "回答正确", subject + ": grading stays attached to the correct question")
			if bank[index].type == "program":
				app.program_drafts[str(bank[index].source_id)] = "print('saved draft')"
				quiz._jump_to(index)
				_expect(quiz.program_editor.editor.text == "print('saved draft')", "Reordered programming questions restore drafts by source ID")

		# Existing wrong IDs can be in any order; review must use grouped order.
		var saved_ids: Array = []
		for kind in source_by_type:
			saved_ids.append(int(source_by_type[kind][0]))
			saved_ids.append(int(source_by_type[kind][-1]))
		saved_ids.reverse()
		var file := FileAccess.open(app.SUBJECTS[subject].wrong_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(saved_ids))
		file.close()
		var expected_wrong: Array = bank.filter(func(question: Dictionary): return int(question.id) in saved_ids)
		app.quiz_mode = "wrong"
		selector = await _open("SubjectSelect")
		_expect(_ids(selector.wrongs[subject]) == _ids(expected_wrong), subject + ": wrong selector preserves grouped order and saved IDs")
		selector._open_wrong(subject, old_id)
		await scene_changed
		await _frames()
		quiz = current_scene
		_expect(_ids(quiz.questions) == _ids(expected_wrong), subject + ": wrong practice is grouped without mixing types")
		_expect(int(quiz.questions[quiz.current_index].id) == old_id, subject + ": wrong-course action opens its requested ID")
		_check_display(quiz)
		quiz.wrong_toggle.pressed.emit()
		_expect(not quiz.wrong_ids.has(str(old_id)) and quiz.questions.size() == expected_wrong.size() - 1, subject + ": removal targets the original wrong ID")
		_check_display(quiz)
		_expect(JSON.stringify(bank) == unchanged_bank, subject + ": answering and review do not mutate the shared bank")
		print(subject, ": ", bank.size(), " questions; ", actual_types, "; grouping, resume, numbering and wrong review OK")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
