extends SceneTree
var failures: Array[String] = []
var app: Node
var stats: Node
const OUT := "res://outputs/minimal-design/"
const MotionTokens = preload("res://scripts/ui_tokens.gd")

func _init() -> void:
	_prepare_test_window.call_deferred()
	_run.call_deferred()

func _prepare_test_window() -> void:
	# Render a real window without intercepting the learner's desktop input.
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _settle(frames: int = 6) -> void:
	for frame in frames:
		await process_frame
	await create_timer(maxf(MotionTokens.DATA, MotionTokens.TAB_UNDERLINE) + 0.08).timeout

func _open(path: String) -> Node:
	change_scene_to_file("res://scenes/" + path + ".tscn")
	await _settle()
	return current_scene

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")

func _click(button: Control) -> void:
	var point := button.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		# get_global_rect() is in viewport coordinates, independent of window stretch.
		root.push_input(event, true)
		await process_frame
	await _settle()

func _common(page: Node) -> void:
	for name in ["HomeButton", "AllButton", "WrongButton", "KaiwuButton", "CollectionButton"]:
		var button: Button = page.find_child(name, true, false)
		_expect(button != null, "Shared sidebar: " + name)
		if button:
			_expect(button.size == Vector2(224, 58), "Consistent navigation button size")
			_expect(button.get_child(1).get_theme_font_size("font_size") == 22, "Consistent navigation text size")
	_expect(get_processed_tweens().is_empty(), "No continuing UI motion after settling")
	for control in page.find_children("*", "Control", true, false):
		_expect(control.tooltip_text.is_empty(), "No hover descriptions")
		if control is Button and control.is_visible_in_tree() and not control.text.is_empty() and control.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var label_width: float = control.get_theme_font("font").get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x
			if control.icon != null:
				label_width += control.get_theme_constant("icon_max_width") + control.get_theme_constant("h_separation")
			label_width += control.get_theme_stylebox("normal").get_minimum_size().x
			_expect(control.size.x + 1 >= label_width, "Button text should not be clipped: " + control.text)

func _run() -> void:
	app = root.get_node("AppState")
	stats = root.get_node("StudyStats")
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	await _settle(10)
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.content_scale_size = Vector2i(1600, 984)
	root.size = Vector2i(1600, 984)
	await _settle()
	var page: Node = await _open("Workbench")
	_common(page)
	await _capture("01-home")
	await _click(page.find_child("AllButton", true, false))
	_expect(current_scene.scene_file_path.ends_with("SubjectSelect.tscn"), "Mouse click routes through the native sidebar")
	page = current_scene
	_common(page)
	_expect(page.cards.size() == 6, "All six real courses")
	await _capture("02-bank")
	page.search_edit.text = "python"
	page.search_edit.text_changed.emit("python")
	_expect(page.cards.size() == 1, "Course search")
	page._select_category("公共基础")
	_expect(page.cards.is_empty(), "Combined category/search filters")
	page.query = ""
	page._select_category("计算机类")
	_expect(page.cards.size() == 3, "Computing category")
	page.filter_button.get_popup().id_pressed.emit(3)
	_expect(page.cards.is_empty(), "Completed-course progress filter")
	for subject in app.SUBJECTS:
		var file := FileAccess.open(app.SUBJECTS[subject].wrong_path, FileAccess.WRITE)
		var ids: Array = []
		for index in {"marxism": 2, "xi": 3, "python": 1}.get(subject, 0):
			ids.append(stats.banks[subject][index].id)
		file.store_string(JSON.stringify(ids))
	stats.record_review("marxism", stats.banks.marxism[0])
	stats.record_review("xi", stats.banks.xi[0])
	app.quiz_mode = "wrong"
	page = await _open("SubjectSelect")
	_common(page)
	_expect(page._filtered_wrong_rows().size() == 6, "Wrong bank uses actual saved IDs")
	_expect(page.cards.size() == 3, "Only subjects with saved wrong questions receive cards")
	_expect(not page.body.has_node("WrongTable") and page.find_child("ShowAll", true, false) == null, "Individual question table and show-all action removed")
	_expect(page.cards_root.get_node("marxism/QuestionCount").text == "共 2 道错题", "Card count uses wrong questions, not the full bank")
	_expect(is_equal_approx(page.cards_root.get_node("marxism/Progress").value, 50), "Card progress uses reviewed wrong questions")
	_expect(page.cards_root.get_node("python/CourseAction").text == "开始复习", "Unreviewed course action")
	_expect(page.cards_root.get_node("xi/CourseAction").text == "继续复习", "Reviewed course action")
	await _capture("03-wrong")
	page.scroll.scroll_vertical = 520
	await _capture("03-wrong-courses")
	page._select_wrong_filter("已练习")
	_expect(page.cards.size() == 2 and not page.cards_root.has_node("python"), "Review status filters courses without matches")
	page.body.get_node("SubjectFilter").item_selected.emit(5)
	_expect(page.cards.is_empty() and page.cards_root.has_node("EmptyState") and page.review_button.disabled, "Combined filters expose a useful empty state")
	page._select_wrong_filter("全部错题")
	_expect(page.cards.size() == 1 and page.cards[0].name == "python", "Subject filter shows only the selected wrong course")
	page.cards[0].get_node("CourseAction").pressed.emit()
	await _settle()
	_expect(app.subject_id == "python" and current_scene.questions.size() == 1, "Course card opens actual saved wrong questions")
	page = await _open("SubjectSelect")
	page._select_wrong_filter("未练习")
	page.cards_root.get_node("marxism/CourseAction").pressed.emit()
	await _settle()
	_expect(app.subject_id == "marxism" and current_scene.questions.size() == 2 and current_scene.current_index == 1, "Filtered course action starts at its first matching wrong question")
	page = await _open("SubjectSelect")
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await _settle()
	page.scroll.scroll_vertical = 520
	await _capture("03-wrong-dark")
	_common(page)
	app.dark_mode = false
	app.color_mode_changed.emit(false)
	app.quiz_mode = "all"
	app.subject_id = "python"
	app.start_index = 0
	var quiz: Node = await _open("Quiz")
	_common(quiz.minimal_view)
	await _capture("05-quiz")
	quiz.minimal_view.number_buttons[2].pressed.emit()
	_expect(quiz.current_index == 2, "Number grid navigation")
	quiz._on_option_pressed(0)
	_expect(quiz.has_answered, "Existing single answer submission")
	await _capture("05-quiz-answered")
	quiz.next_button.pressed.emit()
	_expect(quiz.current_index == 3, "Next question")
	quiz.prev_button.pressed.emit()
	_expect(quiz.current_index == 2 and not quiz.has_answered and quiz.question_states[quiz._question_state_key(2)].answered, "Revisiting permits another attempt and preserves the answered number state")
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await _capture("05-quiz-dark")
	app.dark_mode = false
	app.color_mode_changed.emit(false)
	for kind in ["fill", "output", "program"]:
		for index in quiz.questions.size():
			if quiz.questions[index].type == kind:
				quiz._jump_to(index)
				await _capture("05-quiz-" + kind)
				break
	page = await _open("HegongKaiwu")
	_common(page)
	_expect(page.visible_entries.size() == 4, "Existing four resource examples")
	_expect(not page.list_root.has_node("Sorts"), "Resource sorting controls removed")
	await _capture("04-resources")
	page.search_edit.text = "热泵"
	page.search_edit.text_changed.emit("热泵")
	_expect(page.visible_entries.size() == 1 and page.visible_entries[0].title == "建筑冷热源", "Resource keyword search")
	page._open_entry(page.visible_entries[0])
	_expect(page.list_root.find_child("Preview", true, false) != null, "Demo stays as inline preview")
	await _capture("04-resource-preview")
	page._select_category("校园故事")
	_expect(page.visible_entries.is_empty(), "Category filtering")
	page._clear_filters()
	_expect(page.visible_entries.size() == 4, "Clear resource filters")
	page.tools_root.get_node("Announcement0").pressed.emit()
	await _settle()
	_expect(current_scene.article_title.text == "征稿公告", "Announcement content preserved")
	await _capture("04-announcement")
	page = await _open("MyCollection")
	_common(page)
	_expect(page.find_child("EmptyTitle", true, false).text == "暂无收藏", "Empty collection")
	await _capture("06-collection")
	# Check constrained layout and large text in the same native renderer.
	root.content_scale_size = Vector2i(1100, 820)
	root.size = Vector2i(1100, 820)
	app.quiz_mode = "all"
	page = await _open("SubjectSelect")
	await _capture("02-bank-narrow")
	app._set_font_scale(1.4)
	await _capture("02-bank-large-text")
	app._set_font_scale(1.0)
	app.quiz_mode = "wrong"
	page = await _open("SubjectSelect")
	page.scroll.scroll_vertical = 10000
	await _capture("03-wrong-narrow")
	_common(page)
	_expect(page.cards[0].position.y == page.cards[1].position.y and page.cards[2].position.y > page.cards[0].position.y, "Narrow wrong bank uses two card columns")
	app._set_font_scale(1.4)
	await _settle()
	page.scroll.scroll_vertical = 10000
	await _capture("03-wrong-large-text")
	_common(page)
	app._set_font_scale(1.0)
	for subject in app.SUBJECTS:
		var file := FileAccess.open(app.SUBJECTS[subject].wrong_path, FileAccess.WRITE)
		file.store_string("[]")
	page = await _open("SubjectSelect")
	_expect(page.cards.is_empty() and page.review_button.disabled and page.cards_root.has_node("EmptyState"), "No wrong questions produces no placeholder course cards")
	app.quiz_mode = "all"
	app.subject_id = "python"
	app.start_index = 0
	page = await _open("Quiz")
	await _capture("05-quiz-narrow")
	page.minimal_view.pane.get_node("ShowNumbers").pressed.emit()
	_expect(page.minimal_view.rail.visible, "Compact question list opens on demand")
	page.minimal_view.number_buttons[20].pressed.emit()
	_expect(page.current_index == 20, "Compact number list works")
	page.minimal_view.hide_numbers.pressed.emit()
	_expect(not page.minimal_view.rail.visible, "Compact list closes without animation")
	await _settle()
	_common(page.minimal_view)
	_expect(get_processed_tweens().is_empty(), "No animations after all flows")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
