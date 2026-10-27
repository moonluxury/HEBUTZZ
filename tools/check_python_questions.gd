extends SceneTree

var failures: Array[String] = []
var state: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	state = root.get_node("AppState")
	state.set_process(false)
	for subject in state.SUBJECTS.values():
		if not str(subject["wrong_path"]).begins_with("res://test_saves/"):
			push_error("Run in an isolated test fixture.")
			quit(1)
			return
	_expect(state.PROGRAM_DRAFTS_PATH.begins_with("res://test_saves/"), "Isolated editor drafts")
	var old_path := "res://test_saves/wrong_questions_python.json"
	_write(old_path, "[1,2,3]\n")
	var cpp_path: String = state.SUBJECTS["cpp"]["wrong_path"]
	_write(cpp_path, "[1]\n")
	state.subject_id = "python"
	state.quiz_mode = "all"
	state.start_index = 0
	var main = await _page("res://scenes/Workbench.tscn")
	_expect(not main.has_node("PageMargin/PageColumn/WrongStatusMargin"), "Home does not show wrong counts")
	main.find_child("WrongButton", true, false).pressed.emit()
	await _settle()
	_expect(current_scene.wrong_count_labels["python"].text == "0 道", "Old bank wrong IDs must not enter replacement bank")
	state.quiz_mode = "all"
	var quiz = await _page("res://scenes/Quiz.tscn")
	_expect(quiz.questions.size() == 890, "Complete replacement count")
	_expect(quiz.question_images.get_child_count() == 0, "Python questions use text instead of screenshots")
	await _settle()
	for index in 4:
		_expect(quiz.shuffled_options[index]["key"] == ["A","B","C","D"][index], "Keep screenshot option letters in source order")
	var counts := {"single": 0, "fill": 0, "output": 0, "program": 0}
	var seen := {}
	var sample := {}
	for index in quiz.questions.size():
		var q: Dictionary = quiz.questions[index]
		var source_id: String = q["source_id"]
		_expect(source_id.begins_with("py-v2-"), "Only replacement questions are active")
		_expect(not seen.has(source_id), "Unique provenance ID")
		seen[source_id] = true
		counts[q["type"]] += 1
		if not sample.has(q["type"]):
			sample[q["type"]] = index
		_expect(q["source"] in ["编程2.docx", "编程大题1.docx"], "Only the two requested sources")
		_expect(root.get_node("StudyStats")._is_valid_question(q), "Valid imported schema")
		_expect(q.get("images", []).is_empty() and q.get("reference_images", []).is_empty(), "All Python material is text: " + source_id)
		for path in q.get("images", []) + q.get("reference_images", []):
			_expect(ResourceLoader.exists(path), "Packaged image exists: " + path)
		for option in q["options"]:
			_expect(option["text"] != "见题干选项", "Every option has its actual text")
		if q["type"] == "single":
			var correct := 0
			for option in q["options"]:
				correct += int(option["correct"])
				_expect(not str(option["text"]).strip_edges().is_empty(), "Each choice has textual content")
			_expect(correct == 1, "One reference option per single-choice question")
			continue
		if q["type"] == "program":
			_expect(not q["reference_code"].is_empty(), "Every program keeps its source reference or missing-reference note")
			continue
		quiz._jump_to(index)
		if q["type"] == "output":
			_expect(quiz.output_input is TextEdit, "Output and irregular text choices use text input")
			quiz.output_input.text = q["answers"][0]
			quiz.output_input.text_changed.emit()
		else:
			for n in q["blanks"].size():
				quiz.fill_inputs[n].text = q["blanks"][n]["answers"][0]
				quiz.fill_inputs[n].text_changed.emit(quiz.fill_inputs[n].text)
		quiz.submit_button.pressed.emit()
		_expect(quiz.result_label.text == "回答正确", "Reference answer grades correctly: " + source_id)
		if index % 20 == 0:
			await _settle()
	_expect(counts == {"single":714,"fill":25,"output":35,"program":116}, "Imported type totals")
	quiz.question_states.clear()
	quiz._jump_to(sample["program"])
	await _settle()
	var code_editor = quiz.program_editor.editor
	_expect(code_editor is CodeEdit, "Embedded editor is a CodeEdit")
	_expect(code_editor.gutters_draw_line_numbers and code_editor.indent_use_spaces and code_editor.indent_size == 4, "Line numbers and four-space indentation")
	_expect(code_editor.syntax_highlighter is CodeHighlighter, "Python syntax highlighting")
	_expect(not quiz.program_editor.reference_box.visible, "Reference is hidden before reveal")
	_expect(not quiz.submit_button.visible and not quiz.option_buttons[0].visible, "Programming questions use editor controls")
	var before_running: int = state.spirit_progress["correct_answers"] + state.spirit_progress["wrong_answers"]
	await _check_execution(quiz.program_editor)
	_expect(not quiz.has_answered and state.spirit_progress["correct_answers"] + state.spirit_progress["wrong_answers"] == before_running, "Running code does not grade or award XP")
	code_editor.text = "if True:"
	code_editor.grab_focus()
	code_editor.set_caret_column(8)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	await _settle()
	_expect(code_editor.text == "if True:\n    ", "Enter inserts a newline and automatic Python indentation")
	enter.pressed = false
	Input.parse_input_event(enter)
	code_editor.text = "def solve():\n    return 42\n"
	code_editor.text_changed.emit()
	quiz._jump_to(0)
	quiz._jump_to(sample["program"])
	_expect(quiz.program_editor.editor.text == "def solve():\n    return 42\n", "Keep code draft across navigation")
	state._save_program_drafts()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(state.PROGRAM_DRAFTS_PATH))
	_expect(saved["py-v2-program-1"] == "def solve():\n    return 42\n", "Code draft saved to disk")
	var answers_before: int = state.spirit_progress["correct_answers"] + state.spirit_progress["wrong_answers"]
	quiz.program_editor.reveal_button.pressed.emit()
	_expect(quiz.program_editor.reference_box.visible and not quiz.has_answered, "Viewing reference does not count as a graded answer")
	_expect(state.spirit_progress["correct_answers"] + state.spirit_progress["wrong_answers"] == answers_before, "Reveal awards no XP")
	quiz.program_editor.reveal_button.pressed.emit()
	_expect(not quiz.program_editor.reference_box.visible, "Second click collapses reference")
	quiz._jump_to(0)
	quiz._jump_to(sample["program"])
	_expect(not quiz.program_editor.reference_box.visible, "Collapsed reference stays collapsed after navigation")
	_expect(quiz.program_editor.editor.text == "def solve():\n    return 42\n", "Reference toggling preserves the draft")
	quiz.program_editor.reveal_button.pressed.emit()
	quiz._jump_to(0)
	quiz._jump_to(sample["program"])
	_expect(quiz.program_editor.reference_box.visible and not quiz.program_editor.reveal_button.disabled, "Expanded reference is restored and remains collapsible")
	quiz.wrong_toggle.pressed.emit()
	_expect(quiz.wrong_ids.has(str(quiz.questions[quiz.current_index]["id"])), "Program can be manually added to wrong bank")
	_expect(not quiz.has_answered and state.spirit_progress["correct_answers"] + state.spirit_progress["wrong_answers"] == answers_before, "Reference toggling and collecting do not grade or award XP")
	for kind in ["single","fill","output"]:
		quiz._jump_to(sample[kind])
		_expect(quiz.program_editor == null, "Editor removed when switching to other question types")
		quiz.wrong_toggle.pressed.emit()
	var wrong_path: String = state.get_subject()["wrong_path"]
	_expect(JSON.parse_string(FileAccess.get_file_as_string(wrong_path)).size() == 4, "Four kinds persisted in replacement wrong bank")
	state.quiz_mode = "wrong"
	state.start_index = 0
	quiz = await _page("res://scenes/Quiz.tscn")
	_expect(quiz.questions.size() == 4, "Reload replacement wrong bank")
	for ignored in 3:
		quiz.wrong_toggle.pressed.emit()
	_expect(quiz.questions.size() == 1 and quiz.program_editor != null, "Program remains after removing other kinds")
	quiz.program_editor.reveal_button.pressed.emit()
	quiz.program_editor.reveal_button.pressed.emit()
	_expect(not quiz.program_editor.reference_box.visible and quiz.result_label.text.is_empty(), "Reference toggles in wrong bank without an assessment")
	quiz.wrong_toggle.pressed.emit()
	await _settle()
	_expect(current_scene.scene_file_path == state.HOME_SCENE_PATH, "Return home after removing final wrong item")
	_expect(FileAccess.get_file_as_string(old_path) == "[1,2,3]\n", "Original bank saves preserved without reusing IDs")
	_expect(FileAccess.get_file_as_string(cpp_path) == "[1]\n", "C++ wrong list unchanged")
	for subject in ["marxism","mao","xi","matlab","cpp"]:
		state.subject_id = subject
		state.quiz_mode = "all"
		state.start_index = 0
		quiz = await _page("res://scenes/Quiz.tscn")
		_expect(not quiz.questions.is_empty(), "Other course still loads: " + subject)
		_expect(not quiz.fill_answers_box.visible and not quiz.question_images.visible, "No Python editor or images in other course choice UI")
		for i in quiz.shuffled_options.size():
			if quiz.shuffled_options[i]["correct"]:
				quiz.option_buttons[i].pressed.emit()
		if quiz.questions[0]["type"] == "multiple":quiz.submit_button.pressed.emit()
		_expect(quiz.result_label.text == "回答正确", "Other course grades correctly: " + subject)
	if failures.is_empty():
		print("PYTHON V2 CHECK: PASS — 890 source entries; editor, drafts, grading, old-save isolation, wrong bank and five-course regression")
		quit()
	else:
		for failure in failures:push_error(failure)
		quit(1)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check_execution(panel: Node) -> void:
	panel.editor.text = "import math\nprint('中文输出', math.isqrt(81))\nprint(int(input()) + int(input()))"
	panel.stdin_editor.text = "3\n5"
	panel.run_button.pressed.emit()
	_expect(panel.runner.is_running(), "Real Python process starts")
	await _wait_run(panel)
	_expect(panel.output_editor.text == "中文输出 9\n8\n", "Unicode, standard library and multiple input calls")
	_expect(panel.run_status.text.begins_with("运行完成"), "Successful run status")
	_expect(not panel.reference_box.visible, "Running does not reveal the answer")
	for code in ["print(1/0)", "if True print(1)"]:
		panel.editor.text = code
		panel.run_button.pressed.emit()
		await _wait_run(panel)
		_expect(panel.run_status.text.begins_with("程序出错"), "Runtime and syntax errors displayed")
		_expect("main.py" in panel.output_editor.text, "Traceback points to learner code")
	panel.editor.text = "print(input())"
	panel.stdin_editor.text = ""
	panel.run_button.pressed.emit()
	await _wait_run(panel)
	_expect("EOFError" in panel.output_editor.text, "Missing input fails without hanging")
	panel.editor.text = "while True: pass"
	panel.run_button.pressed.emit()
	panel.stop_button.pressed.emit()
	_expect(not panel.runner.is_running() and panel.run_status.text == "已停止运行。", "Stop interrupts an infinite loop")
	panel.runner.time_limit_seconds = 0.5
	panel.run_button.pressed.emit()
	await _wait_run(panel)
	_expect("超过" in panel.run_status.text, "Time limit interrupts an infinite loop")
	panel.runner.time_limit_seconds = 10.0
	panel.editor.text = "while True: print('中文' * 1000)"
	panel.run_button.pressed.emit()
	await _wait_run(panel)
	_expect("256 KB" in panel.run_status.text, "Unbounded output is stopped")
	panel.editor.text = "print('再次运行')"
	panel.run_button.pressed.emit()
	await _wait_run(panel)
	_expect(panel.output_editor.text == "再次运行\n", "Rerun resets prior output")


func _wait_run(panel: Node) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while panel.runner.is_running() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	_expect(not panel.runner.is_running(), "Execution completes within test deadline")


func _page(path: String) -> Node:
	change_scene_to_file(path)
	await _settle()
	return current_scene


func _settle() -> void:
	await process_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:failures.append(message)
