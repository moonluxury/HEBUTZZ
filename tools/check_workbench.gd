extends SceneTree

var failures: Array[String] = []
var app: Node
var stats: Node
var screenshot_dir := "res://outputs/minimal-design"


func _init() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _open(path: String) -> Node:
	change_scene_to_file(path)
	await process_frame
	await process_frame
	return current_scene


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(screenshot_dir + "/" + name + ".png")


func _run() -> void:
	app = root.get_node("AppState")
	stats = root.get_node("StudyStats")
	# Refuse to run against the learner's normal save directory.
	if not OS.get_user_data_dir().contains("workbench-check"):
		push_error("Run through tools/run_workbench_checks.py to isolate learner saves.")
		quit(2)
		return
	root.content_scale_size = Vector2i(1600, 984)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 984)
	_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/Workbench.tscn", "F5 should launch Workbench")
	_expect(stats.summary().total == 2981, "All six banks must total 2,981")
	_expect(stats.summary().today == 0 and stats.summary().days == 0, "Fresh state should not fabricate study data")
	var home: Node = await _open("res://scenes/Workbench.tscn")
	_check_no_tooltips(home)
	_expect(home.find_child("OriginalHomeButton", true, false) == null, "Legacy home entry must be removed")
	_expect(not FileAccess.file_exists("res://scenes/Main.tscn"), "Legacy home scene must be removed")
	_expect(not FileAccess.file_exists("res://scripts/main_menu.gd"), "Legacy home script must be removed")
	_expect(home.find_child("ThemeButton", true, false) == null, "Removed top toolbar must not return")
	_expect(home.theme.default_font.oversampling >= 4.0, "Scaled button text should use high-resolution glyph sampling")
	await _capture("workbench-light")
	root.content_scale_size = Vector2i(1920, 1008)
	root.size = Vector2i(1920, 1008)
	await process_frame
	await process_frame
	await _capture("workbench-wide")
	root.content_scale_size = Vector2i(1600, 984)
	root.size = Vector2i(1600, 984)
	await process_frame
	await process_frame
	# The content area now has exactly one action: the learning trend.
	for node_name in ["StudyHero", "TodayCard", "ProgressCard", "DaysCard", "TotalCard", "DistributionCard"]:
		var display: Control = home.find_child(node_name, true, false)
		_expect(not display is BaseButton and display.find_children("*", "BaseButton", true, false).is_empty(), node_name + " should be display-only")
		_expect(display.focus_mode == Control.FOCUS_NONE and display.mouse_filter == Control.MOUSE_FILTER_IGNORE, node_name + " must not receive clicks or keyboard focus")
	_expect(home.body.find_children("*", "Button", true, false).size() == 1, "Only the trend remains interactive in the content area")
	home.find_child("TrendCard", true, false).pressed.emit()
	await process_frame
	_expect(is_instance_valid(home.detail_overlay), "Trend should still open learning history")
	var history: VBoxContainer = home.detail_overlay.find_child("DetailScroll", true, false).get_child(0)
	_expect(history.get_child_count() == 14 and history.find_children("*", "BaseButton", true, false).is_empty(), "History keeps 14 display-only dates without action buttons")
	for row in history.get_children():
		_expect(row.focus_mode == Control.FOCUS_NONE and row.mouse_filter == Control.MOUSE_FILTER_IGNORE, "History dates must not receive clicks or keyboard focus")
	_expect(not "点击日期" in home.detail_overlay.find_child("Subtitle", true, false).text, "History must not advertise removed date actions")
	home.detail_overlay.find_child("CloseButton", true, false).pressed.emit()
	_expect(home.detail_overlay == null, "History close button should remain usable")
	home.find_child("AllButton", true, false).pressed.emit()
	await process_frame
	await process_frame
	_expect(current_scene.scene_file_path.ends_with("SubjectSelect.tscn"), "Sidebar total bank should select a course")
	current_scene.back_button.pressed.emit()
	await process_frame
	await process_frame
	_expect(current_scene.scene_file_path.ends_with("Workbench.tscn"), "Course selector should return to Workbench")
	home = current_scene
	home.find_child("WrongButton", true, false).pressed.emit()
	await process_frame
	await process_frame
	_expect(app.quiz_mode == "wrong" and current_scene.title_label.text == "错题库", "Wrong bank should keep its mode")
	var quiz: Node
	for subject in app.SUBJECTS:
		app.subject_id = subject
		app.quiz_mode = "all"
		app.start_index = 0
		quiz = await _open("res://scenes/Quiz.tscn")
		_expect(quiz.questions.size() == stats.banks[subject].size(), subject + " bank should load")
		quiz._go_home()
		await process_frame
		await process_frame
		_expect(current_scene.scene_file_path.ends_with("Workbench.tscn"), "Quiz home should return to Workbench")
	# Answer via actual quiz behavior, then repeat the same item on a fresh scene.
	app.subject_id = "python"
	app.quiz_mode = "all"
	app.start_index = 0
	quiz = await _open("res://scenes/Quiz.tscn")
	for index in quiz.shuffled_options.size():
		if quiz.shuffled_options[index].get("correct", false):
			quiz._on_option_pressed(index)
			break
	_expect(stats.summary().today == 1 and stats.summary().learned == 1 and stats.summary().days == 1, "Answer should update daily, unique and day counts")
	quiz = await _open("res://scenes/Quiz.tscn")
	quiz._on_option_pressed(0)
	_expect(stats.summary().today == 1 and stats.summary().learned == 1, "Repeated answers should not inflate unique count")
	var today: String = Time.get_date_string_from_system()
	_expect(int(stats.history[today].attempts) == 2, "Repeated answers should still count attempts")
	# Resume a question selected from the wrong bank by ID in the full bank.
	var question: Dictionary = stats.banks.python[5]
	stats.remember_question("python", question)
	home = await _open("res://scenes/Workbench.tscn")
	home.find_child("AllButton", true, false).pressed.emit()
	await process_frame
	await process_frame
	current_scene.cards_root.get_node("python/CourseAction").pressed.emit()
	await process_frame
	await process_frame
	_expect(app.subject_id == "python" and current_scene.current_index == 5, "Course action should restore the question by ID")
	# Program review is counted as learning, never as a correct answer.
	var correct_before: int = stats.answer_count(true)
	quiz = current_scene
	for index in quiz.questions.size():
		if quiz.questions[index].type == "program":
			quiz._jump_to(index)
			quiz._on_program_reference_toggled(true)
			break
	_expect(stats.summary().learned == 2, "Program reference review should update progress")
	_expect(stats.answer_count(true) == correct_before, "Program review must not grant correctness")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(stats.SAVE_PATH))
	_expect(saved is Dictionary and saved.learned.size() == 2, "Learning records should persist")
	home = await _open("res://scenes/Workbench.tscn")
	await _capture("workbench-with-records")
	home.find_child("TrendCard", true, false).pressed.emit()
	await _capture("workbench-history")
	home._close_details()
	home._toggle_theme()
	await process_frame
	await _capture("workbench-dark")
	home._toggle_theme()
	app._set_font_scale(1.8)
	await process_frame
	await _capture("workbench-large-text")
	app._set_font_scale(1.0)
	root.size = Vector2i(1000, 850)
	root.content_scale_size = Vector2i(1000, 850)
	await process_frame
	await process_frame
	await _capture("workbench-narrow")
	root.size = Vector2i(1600, 984)
	root.content_scale_size = Vector2i(1600, 984)
	await process_frame
	await process_frame
	home.find_child("CollectionButton", true, false).pressed.emit()
	await process_frame
	await process_frame
	_expect(current_scene.scene_file_path.ends_with("MyCollection.tscn"), "Collection entry should open the new collection page")
	_expect(current_scene.find_child("Title", true, false).text == "我的收藏", "Collection page should use the requested title")
	_expect(current_scene.find_child("EmptyTitle", true, false).text == "暂无收藏", "Collection page should begin empty")
	_check_no_tooltips(current_scene)
	await _capture("my-collection")
	current_scene.back_button.pressed.emit()
	await process_frame
	await process_frame
	_expect(current_scene.scene_file_path.ends_with("Workbench.tscn"), "Collection back button should return to the only home")
	current_scene.find_child("CollectionButton", true, false).pressed.emit()
	await process_frame
	await process_frame
	root.get_node("PageRouter").back()
	await process_frame
	await process_frame
	_expect(current_scene.scene_file_path.ends_with("Workbench.tscn"), "Escape from collection returns to Workbench")
	for entry in [["KaiwuButton", "HegongKaiwu.tscn"]]:
		current_scene.find_child(entry[0], true, false).pressed.emit()
		await process_frame
		await process_frame
		_expect(current_scene.scene_file_path.ends_with(entry[1]), entry[0] + " should open existing feature")
		root.get_node("PageRouter").back()
		await process_frame
		await process_frame
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_no_tooltips(node: Node) -> void:
	if node is Control:
		_expect(node.tooltip_text.is_empty(), "Workbench must not have hover explanations")
	for child in node.get_children():
		_check_no_tooltips(child)
