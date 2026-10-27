extends SceneTree
var failures: Array[String] = []
var app: Node
var router: Node
var stats: Node

func _init() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _frames() -> void:
	for index in 4:
		await process_frame

func _visit(page: String, mode := "all") -> Node:
	app.quiz_mode = mode
	router.go("res://scenes/%s.tscn" % page)
	await scene_changed
	await _frames()
	return current_scene

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	app = root.get_node("AppState")
	router = root.get_node("PageRouter")
	stats = root.get_node("StudyStats")
	root.get_node("UiMotion").set_enabled(false)
	root.content_scale_size = Vector2i(1600, 984)
	root.size = Vector2i(1600, 984)
	var home: Node = await _visit("Workbench")
	var sidebar_id: int = home.sidebar.get_instance_id()
	var bank: Node = await _visit("SubjectSelect")
	var bank_id: int = bank.get_instance_id()
	var bank_canvas: Control = bank.canvas
	bank.search_edit.text = "Python"
	bank.search_edit.text_changed.emit("Python")
	var wrong: Node = await _visit("SubjectSelect", "wrong")
	var wrong_id: int = wrong.get_instance_id()
	_expect(wrong_id != bank_id, "All/wrong pages have independent cache keys")
	_expect(not bank.is_inside_tree(), "Cached pages are detached and cannot handle input")
	await _visit("Workbench")
	_expect(current_scene == home, "Workbench is reused")
	await _visit("SubjectSelect")
	_expect(current_scene.get_instance_id() == bank_id and bank.canvas == bank_canvas, "Unchanged bank reuses its controls")
	_expect(bank.search_edit.text == "Python" and bank.cards.size() == 1, "Cached page retains search and filtering")
	app.subject_id = "python"
	app.start_index = 0
	var original_bank := JSON.stringify(stats.banks.python)
	var quiz: Node = await _visit("Quiz")
	var view: Control = quiz.minimal_view
	_expect(quiz.home_button.get_parent() == view.header and view.header.get_global_rect().encloses(quiz.home_button.get_global_rect()), "Return button remains inside the quiz header: %s" % quiz.home_button.get_global_rect())
	_expect(is_same(quiz.all_questions, stats.banks.python), "Quiz uses the shared parsed bank")
	_expect(is_same(quiz.questions[0], stats.banks.python[0]), "Question dictionaries are shared without a deep copy")
	_expect(view.sidebar.get_instance_id() == sidebar_id, "Sidebar survives every routed page change")
	_expect(view.theme == home.theme and view.bold_font == home.bold_font, "Fonts/theme are shared")
	_expect(not quiz.has_node("PageMargin"), "Hidden legacy UI is absent")
	for target in [889, 405, 0, 170, 888]:
		quiz._jump_to(target)
		await _frames()
		_expect(view.number_buttons.has(target), "Distant question appears in the virtual viewport: %d" % target)
		_expect(view.number_pool.size() < 150, "Question controls stay bounded")
		var button: Button = view.number_buttons[target]
		_expect(button.text == str(target + 1), "Reused button has correct number")
		button.pressed.emit()
		_expect(quiz.current_index == target, "Reused button jumps to its current binding")
	view.number_scroll.scroll_vertical = 0
	await _frames()
	_expect(view.number_buttons.has(0), "Manual scrolling materializes the first row")
	view.number_buttons[0].pressed.emit()
	await _frames()
	_expect(quiz.current_index == 0, "Click after recycling keeps correct question mapping")
	view.number_buttons[0].grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_END
	key.pressed = true
	root.push_input(key)
	await _frames()
	_expect(view.number_buttons.has(889) and view.number_buttons[889].has_focus(), "Keyboard focus reaches numbers beyond the visible pool")
	_expect(quiz.current_index == 0, "Moving keyboard focus does not submit or change the question")
	quiz._toggle_wrong_current()
	_expect(quiz.wrong_ids.has(str(quiz.questions[0].id)), "Wrong toggle persists with the lean controller")
	stats.record_answer("python", quiz.questions[0], false)
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await _frames()
	_expect(bank.appearance_dirty and wrong.appearance_dirty, "Hidden pages defer theme rebuilds")
	_expect(JSON.stringify(stats.banks.python) == original_bank, "Answer/shuffle/wrong actions do not mutate cached bank")
	wrong = await _visit("SubjectSelect", "wrong")
	_expect(wrong.get_instance_id() == wrong_id and wrong.dark, "Cached wrong page adopts current theme")
	_expect(wrong.wrongs.python.size() == 1 and wrong.cards.size() == 1, "Wrong page refreshes saved changes")
	await _visit("Workbench")
	_expect(current_scene.data.learned == 1, "Cached workbench refreshes study statistics")
	for page in ["HegongKaiwu", "MyCollection", "SubjectSelect", "Workbench"]:
		await _visit(page)
		_expect(router.pages.size() <= router.CACHE_LIMIT, "Inactive page cache is bounded")
		_expect(router.sidebar.get_instance_id() == sidebar_id, "Cache eviction preserves shared sidebar")
	var resources: Node = await _visit("HegongKaiwu")
	resources.tools_root.get_node("Announcement0").pressed.emit()
	await scene_changed
	await _frames()
	_expect(current_scene.article_title.text == "征稿公告", "Routed resource detail shows the selected announcement")
	current_scene.back_button.pressed.emit()
	await scene_changed
	await _frames()
	_expect(current_scene == resources, "Returning from detail reuses the resource page")
	app.dark_mode = false
	app.color_mode_changed.emit(false)
	await _frames()
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
