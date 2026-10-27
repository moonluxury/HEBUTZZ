extends SceneTree

# Run in an isolated project copy whose save paths point to res://test_saves/.
# This guard keeps the checks from changing a learner's real wrong-question list.
var failures: Array[String] = []
var state: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	state = root.get_node("AppState")
	state.set_process(false)
	for subject in state.SUBJECTS.values():
		if not str(subject["wrong_path"]).begins_with("res://test_saves/"):
			push_error("Run this check in an isolated project copy, not with real save paths.")
			quit(1)
			return
	state.subject_id = "matlab"
	state.quiz_mode = "all"
	state.start_index = 0
	var xi_path: String = state.SUBJECTS["xi"]["wrong_path"]
	var xi_file := FileAccess.open(xi_path, FileAccess.WRITE)
	xi_file.store_string("[1]\n")
	xi_file.close()

	var main = await _open_page("res://scenes/Workbench.tscn")
	_expect(not main.has_node("PageMargin/PageColumn/WrongStatusMargin"), "首页不再显示错题数量")
	main.find_child("AllButton", true, false).pressed.emit()
	await _settle()
	var selector = current_scene
	_expect(selector.matlab_button.get_parent().get_node("CourseTitle").text == "MATLAB", "总题库课程页应有 MATLAB 课程入口")
	_expect(selector.wrong_count_labels.is_empty(), "总题库课程页不显示错题数量")
	selector.matlab_button.pressed.emit()
	await _settle()
	var quiz = current_scene
	_expect(state.subject_id == "matlab" and state.quiz_mode == "all", "总题库入口应选择 MATLAB")
	_expect(quiz.questions.size() == 505, "MATLAB 总题库应加载全部 505 题")
	_expect(quiz.minimal_view.number_count == 505, "应显示 505 个跳题题号")
	_expect(quiz.minimal_view.heading.text == "MATLAB", "答题页应显示课程名称")
	_expect(quiz.minimal_view.active_nav == "AllButton", "总题库模式名称不正确")
	var counts := {"single": 0, "multiple": 0, "judge": 0}
	var sample_indices := {}
	for question_index in quiz.questions.size():
		var question: Dictionary = quiz.questions[question_index]
		var question_type: String = question["type"]
		counts[question_type] += 1
		if not sample_indices.has(question_type):
			sample_indices[question_type] = question_index
		var correct_count := 0
		for option in question["options"]:
			if option["correct"]:
				correct_count += 1
		_expect(correct_count > 0, "题目缺少正确选项：%d" % question["id"])
	_expect(counts == {"single": 225, "multiple": 98, "judge": 182}, "三种题型的数量应与原题库相同")
	quiz.jump_input.text = "505"
	quiz.jump_button.pressed.emit()
	_expect(quiz.current_index == 504, "应能跳转到最后一道题")

	var collected_ids: Array[int] = []
	for question_type in ["single", "multiple", "judge"]:
		quiz._jump_to(sample_indices[question_type])
		for index in quiz.shuffled_options.size():
			if quiz.shuffled_options[index]["correct"]:
				quiz.option_buttons[index].pressed.emit()
		if question_type == "multiple":
			_expect(not quiz.has_answered, "多选题应等待提交")
			quiz.submit_button.pressed.emit()
		_expect(quiz.has_answered and quiz.result_label.text == "回答正确", "%s 乱序选项判题失败" % question_type)
		quiz.wrong_toggle.pressed.emit()
		collected_ids.append(int(quiz.questions[quiz.current_index]["id"]))
		_expect("已加入错题库" in quiz.wrong_toggle.text, "收藏状态应及时更新")
	collected_ids.sort()
	var wrong_path: String = state.get_subject()["wrong_path"]
	_expect(_load_ids(wrong_path) == collected_ids, "三种题型的错题题号应保存到独立文件")
	_expect(FileAccess.get_file_as_string(xi_path) == "[1]\n", "MATLAB 收藏不能修改其他课程记录")

	# A wrong multiple-choice answer must not be accepted as a correct subset.
	quiz.question_states.clear()
	quiz._jump_to(sample_indices["multiple"])
	var incorrect_index := -1
	for index in quiz.shuffled_options.size():
		if not quiz.shuffled_options[index]["correct"]:
			incorrect_index = index
			break
	if incorrect_index >= 0:
		quiz.option_buttons[incorrect_index].pressed.emit()
	else:
		quiz.option_buttons[0].pressed.emit()
	quiz.submit_button.pressed.emit()
	_expect(quiz.result_label.text == "回答错误", "多选题的错误组合应判错")

	main = await _open_page("res://scenes/Workbench.tscn")
	main.find_child("WrongButton", true, false).pressed.emit()
	await _settle()
	_expect(current_scene.wrong_count_labels["matlab"].text == "3 道", "错题库课程按钮应刷新 MATLAB 错题数量")
	current_scene.matlab_button.pressed.emit()
	await _settle()
	quiz = current_scene
	_expect(quiz.questions.size() == 3, "错题入口应读取已保存的 MATLAB 题目")
	_expect(quiz.minimal_view.active_nav == "WrongButton", "错题模式名称不正确")
	_expect(int(quiz.questions[0]["id"]) == collected_ids[0], "错题记录应按原题号找到题目")
	quiz.wrong_toggle.pressed.emit()
	_expect(quiz.questions.size() == 2, "移出错题应立即更新当前列表")
	_expect(_load_ids(wrong_path).size() == 2, "移出错题应写入存档")
	quiz = await _open_page("res://scenes/Quiz.tscn")
	_expect(quiz.questions.size() == 2, "重新进入错题库应保留移出后的结果")
	quiz.wrong_toggle.pressed.emit()
	quiz.wrong_toggle.pressed.emit()
	await _settle()
	_expect(current_scene.scene_file_path == state.HOME_SCENE_PATH, "移出最后一道错题后应返回首页")
	_expect(_load_ids(wrong_path).is_empty(), "清空后错题文件应为空")
	current_scene.find_child("WrongButton", true, false).pressed.emit()
	await _settle()
	current_scene.matlab_button.pressed.emit()
	await _settle()
	_expect(current_scene.empty_label.is_visible_in_tree() and not current_scene.question_scroll.visible, "空错题库应显示空状态")
	_expect(current_scene.empty_label.text == "MATLAB错题库暂无题目", "空状态应显示正确课程名称")
	_expect(FileAccess.get_file_as_string(xi_path) == "[1]\n", "完整错题流程应保持其他课程存档不变")

	for subject_id in ["marxism", "mao", "xi"]:
		state.subject_id = subject_id
		state.quiz_mode = "all"
		state.start_index = 0
		quiz = await _open_page("res://scenes/Quiz.tscn")
		_expect(not quiz.questions.is_empty(), "原有课程仍应能加载：%s" % subject_id)
		print("EXISTING SUBJECT: ", subject_id, " questions=", quiz.questions.size())
	if failures.is_empty():
		print("MATLAB CHECK: PASS — 505 questions, navigation, grading, wrong-list persistence/removal, course isolation")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _open_page(path: String) -> Node:
	change_scene_to_file(path)
	await _settle()
	return current_scene


func _settle() -> void:
	await process_frame
	await process_frame


func _load_ids(path: String) -> Array:
	var ids: Array[int] = []
	for value in JSON.parse_string(FileAccess.get_file_as_string(path)):
		ids.append(int(value))
	return ids


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
