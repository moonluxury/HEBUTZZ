extends SceneTree

const FillAnswer = preload("res://scripts/fill_answer.gd")
const OutputAnswer = preload("res://scripts/output_answer.gd")
var failures: Array[String] = []
var state: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	state = root.get_node("AppState")
	state.set_process(false)
	for subject in state.SUBJECTS.values():
		if not str(subject["wrong_path"]).begins_with("res://test_saves/"):
			push_error("Use an isolated project copy with test save paths.")
			quit(1)
			return
	_expect(FillAnswer.normalize("'a'", "cpp") != FillAnswer.normalize('"a"', "cpp"), "C++ character and string literals differ")
	_expect(FillAnswer.normalize("p++", "cpp") != FillAnswer.normalize("p + +", "cpp"), "Keep compound operator boundaries")
	_expect(FillAnswer.normalize("const CRect &", "cpp") == FillAnswer.normalize("const CRect&", "cpp"), "Allow C++ token spacing")
	_expect(FillAnswer.normalize("' '", "cpp") != FillAnswer.normalize("''", "cpp"), "Keep literal whitespace")
	_expect(FillAnswer.normalize("'a'", "python") == FillAnswer.normalize('"a"', "python"), "Preserve Python quote equivalence")
	_expect(FillAnswer.normalize("CPoint", "cpp") != FillAnswer.normalize("cpoint", "cpp"), "C++ is case-sensitive")
	_expect(OutputAnswer.is_correct(["6 2\n3 4"], " 6\t 2 \r\n3  4\n"), "Accept output spacing and platform line endings")
	_expect(not OutputAnswer.is_correct(["62"], "6 2"), "Do not merge output tokens")
	_expect(not OutputAnswer.is_correct(["6\n2"], "6 2"), "Preserve output line breaks")
	_expect(not OutputAnswer.is_correct(["CA:10"], "ca:10"), "Preserve output case")
	_expect(not OutputAnswer.is_correct(["4,6"], "4 6"), "Preserve output punctuation")
	_expect(not OutputAnswer.is_correct(["0"], ""), "Reject blank output")
	_expect(not OutputAnswer.is_valid({"answers": []}), "Reject missing reference output")
	var python_path: String = state.SUBJECTS["python"]["wrong_path"]
	var file := FileAccess.open(python_path, FileAccess.WRITE)
	file.store_string("[1]\n")
	file.close()
	state.quiz_mode = "all"
	state.start_index = 0
	var main = await _page("res://scenes/Workbench.tscn")
	_expect(not main.has_node("PageMargin/PageColumn/WrongStatusMargin"), "Home does not show wrong counts")
	main.find_child("AllButton", true, false).pressed.emit()
	await _settle()
	_expect(current_scene.cpp_button.get_parent().get_node("CourseTitle").text == "C++", "C++ course entry exists")
	_expect(current_scene.wrong_count_labels.is_empty(), "Total bank does not show wrong counts")
	current_scene.cpp_button.pressed.emit()
	await _settle()
	var quiz = current_scene
	_expect(quiz.questions.size() == 402, "Load all C++ questions")
	var singles := 0
	var fills := 0
	var outputs := 0
	var multi_blank_index := -1
	var multiline_output_index := -1
	var long_output_index := -1
	for index in quiz.questions.size():
		var question: Dictionary = quiz.questions[index]
		quiz._jump_to(index)
		if question["type"] == "single":
			singles += 1
			_expect(not quiz.fill_answers_box.visible, "Choice UI at question %d" % question["id"])
			for option_index in quiz.shuffled_options.size():
				if quiz.shuffled_options[option_index]["correct"]:
					quiz.option_buttons[option_index].pressed.emit()
			_expect(quiz.result_label.text == "回答正确", "Choice grading at question %d" % question["id"])
		elif question["type"] == "output":
			outputs += 1
			_expect(quiz.output_input is TextEdit and quiz.fill_inputs.is_empty(), "Output uses a multiline editor")
			_expect(not quiz.option_buttons[0].visible, "Output hides choice options")
			if int(question["source_id"]) == 30024:
				multiline_output_index = index
			if int(question["source_id"]) == 40574:
				long_output_index = index
			_enter_output(quiz, question["answers"][0])
			quiz.submit_button.pressed.emit()
			_expect(quiz.result_label.text == "回答正确", "Output grading at question %d" % question["id"])
			_expect(not quiz.output_input.editable, "Lock submitted output")
		else:
			fills += 1
			var blanks: Array = question["blanks"]
			if blanks.size() > 1 and multi_blank_index < 0:
				multi_blank_index = index
			_expect(quiz.fill_inputs.size() == blanks.size(), "Fill field count at question %d" % question["id"])
			for blank_index in blanks.size():
				for accepted in blanks[blank_index]["answers"]:
					quiz.question_states.clear()
					quiz._jump_to(index)
					for answer_index in blanks.size():
						_enter(quiz, answer_index, str(accepted) if answer_index == blank_index else str(blanks[answer_index]["answers"][0]))
					quiz.submit_button.pressed.emit()
					_expect(quiz.result_label.text == "回答正确", "Accepted fill answer at question %d blank %d" % [question["id"], blank_index + 1])
	_expect(singles == 262 and fills == 69 and outputs == 71, "C++ type counts")
	quiz._jump_to(long_output_index)
	await _settle()
	quiz.question_scroll.scroll_vertical = 100000
	await _settle()
	_expect(quiz.question_scroll.scroll_vertical > 0, "Long output question can scroll")
	quiz.question_states.clear()
	quiz._jump_to(multi_blank_index)
	await _settle()
	_expect(quiz.question_scroll.scroll_vertical == 0, "Navigation starts at the question heading")
	quiz.submit_button.pressed.emit()
	_expect(not quiz.has_answered, "Reject empty fill submission")
	_enter(quiz, 0, "i >= 20")
	quiz._jump_to(0)
	quiz._jump_to(multi_blank_index)
	_expect(quiz.fill_inputs[0].text == "i >= 20", "Restore fill draft after navigation")
	_enter(quiz, 1, "i += 20")
	quiz.submit_button.pressed.emit()
	_expect(quiz.result_label.text == "回答错误", "Wrong arithmetic operation rejected")
	_expect(not quiz.fill_inputs[0].editable, "Submitted inputs locked")
	_expect("参考答案（原资料）" in quiz.answer_label.text, "Identify source answer")
	quiz.wrong_toggle.pressed.emit()
	quiz._jump_to(0)
	quiz.wrong_toggle.pressed.emit()
	quiz._jump_to(multiline_output_index)
	var answer_count: int = root.get_node("StudyStats").answer_count()
	quiz.submit_button.pressed.emit()
	_expect(not quiz.has_answered, "Reject empty output without recording an answer")
	_expect(root.get_node("StudyStats").answer_count() == answer_count, "Empty output should not count an answer")
	_enter_output(quiz, "1 5 9\n2 6 10")
	quiz._jump_to(multi_blank_index)
	_expect(quiz.output_input == null and not quiz.fill_inputs.is_empty(), "Clear output editor when switching to fill")
	quiz._jump_to(multiline_output_index)
	_expect(quiz.output_input.text == "1 5 9\n2 6 10", "Restore multiline draft")
	_enter_output(quiz, "1\t 5 9\r\n2 6 10\r\n3 7 11\r\n4 8 12\n")
	quiz.submit_button.pressed.emit()
	_expect(quiz.result_label.text == "回答正确", "Accept multiline output with tabs and CRLF")
	quiz.submit_button.pressed.emit()
	_expect(root.get_node("StudyStats").answer_count() == answer_count + 1, "Repeated submission should not duplicate an answer")
	quiz._jump_to(0)
	quiz._jump_to(multiline_output_index)
	_expect(not quiz.has_answered and quiz.output_input.editable and quiz.output_input.text.is_empty(), "Revisiting a submitted output starts a new editable attempt")
	_expect(quiz.answer_label.text.is_empty() and quiz.question_states[quiz._question_state_key(multiline_output_index)].answered, "Retry hides the reference and preserves the completed record")
	quiz.wrong_toggle.pressed.emit()
	var wrong_path: String = state.get_subject()["wrong_path"]
	_expect(_ids(wrong_path).size() == 3, "Persist choice, fill and output wrong items")
	main = await _page("res://scenes/Workbench.tscn")
	main.find_child("WrongButton", true, false).pressed.emit()
	await _settle()
	_expect(current_scene.wrong_count_labels["cpp"].text == "3 道", "Wrong bank shows updated C++ count")
	current_scene.cpp_button.pressed.emit()
	await _settle()
	quiz = current_scene
	_expect(quiz.questions.size() == 3, "Reload C++ wrong bank")
	quiz.wrong_toggle.pressed.emit()
	_expect(quiz.fill_answers_box.visible, "Switch from choice to fill after removal")
	quiz = await _page("res://scenes/Quiz.tscn")
	_expect(quiz.questions.size() == 2, "Persist wrong removal")
	quiz.wrong_toggle.pressed.emit()
	_expect(quiz.questions.size() == 1 and quiz.output_input is TextEdit, "Reload output from wrong bank")
	_enter_output(quiz, "wrong output")
	quiz.submit_button.pressed.emit()
	_expect(quiz.result_label.text == "回答错误", "Reject incorrect output in wrong bank")
	quiz.wrong_toggle.pressed.emit()
	await _settle()
	_expect(current_scene.scene_file_path == state.HOME_SCENE_PATH, "Return home after removing last wrong item")
	_expect(_ids(wrong_path).is_empty(), "Save empty wrong list")
	_expect(FileAccess.get_file_as_string(python_path) == "[1]\n", "Python wrong list remains unchanged")
	state.quiz_mode = "wrong"
	quiz = await _page("res://scenes/Quiz.tscn")
	_expect(quiz.empty_label.text == "C++错题库暂无题目", "C++ empty state")
	if failures.is_empty():
		print("CPP CHECK: PASS — 402 questions, 71 program outputs, literal multiline grading, drafts, XP and isolated wrong-list persistence")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _enter(quiz: Node, index: int, value: String) -> void:
	quiz.fill_inputs[index].text = value
	quiz.fill_inputs[index].text_changed.emit(value)


func _enter_output(quiz: Node, value: String) -> void:
	quiz.output_input.text = value
	quiz.output_input.text_changed.emit()


func _page(path: String) -> Node:
	change_scene_to_file(path)
	await _settle()
	return current_scene


func _settle() -> void:
	await process_frame
	await process_frame


func _ids(path: String) -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
