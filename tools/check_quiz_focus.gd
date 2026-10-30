extends "res://tools/check_minimal_design.gd"

func _key(code: Key, echo := false) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		event.echo = echo and down
		# Native Window input also reaches the editor's debugger shortcut listener.
		root.window_input.emit(event)
		root.push_input(event)
		await process_frame

func _right_rail(view: Control, overlay := false) -> void:
	_expect(view.rail.is_visible_in_tree(), "Question list remains available on the right")
	_expect(is_equal_approx(view.right_panes.position.x + view.right_panes.size.x, view.canvas.size.x), "Question list is anchored to the right edge")
	if not overlay:
		_expect(view.pane.position.x + view.pane.size.x < view.right_panes.position.x, "Question content does not overlap the right list")

func _wrong_button_pixel(button: Button) -> Color:
	if DisplayServer.get_name() == "headless":
		return button.get_theme_stylebox("normal").bg_color
	await RenderingServer.frame_post_draw
	var point := button.get_global_rect().position + Vector2(button.get_global_rect().size.x * 0.5, 6)
	return root.get_texture().get_image().get_pixelv(Vector2i(root.get_final_transform() * point))

func _wrong_action_feedback(quiz: Node, name: String) -> void:
	var button: Button = quiz.wrong_toggle
	var view: Control = quiz.minimal_view
	button.release_focus()
	button.mouse_exited.emit()
	await _settle()
	var background := await _wrong_button_pixel(button)
	button.mouse_entered.emit()
	await _settle()
	_expect((await _wrong_button_pixel(button)).is_equal_approx(background), name + ": hover keeps the rendered background")
	_expect(button.get_theme_color("font_color").is_equal_approx(view.text_color) and button.get_theme_color("icon_normal_color").is_equal_approx(view.text_color), name + ": hover keeps unsaved text and icon in their normal color")
	button.mouse_exited.emit()
	button.grab_focus()
	await _settle()
	_expect((await _wrong_button_pixel(button)).is_equal_approx(background), name + ": keyboard focus keeps the rendered background")
	_expect(button.get_theme_color("font_color").is_equal_approx(view.text_color) and button.get_theme_color("icon_normal_color").is_equal_approx(view.text_color), name + ": keyboard focus keeps unsaved text and icon in their normal color")
	await _capture("wrong-button-" + name)
	button.button_down.emit()
	await _settle()
	_expect((await _wrong_button_pixel(button)).is_equal_approx(background), name + ": pressing keeps the rendered background")
	_expect(button.get_theme_color("font_color").is_equal_approx(view.text_color) and button.get_theme_color("icon_normal_color").is_equal_approx(view.text_color), name + ": pressing does not imply the question has been saved")
	button.button_up.emit()
	button.pressed.emit()
	await _settle()
	_expect(quiz.wrong_ids.has(str(quiz.questions[quiz.current_index].id)), name + ": adding a wrong question still saves it")
	_expect((await _wrong_button_pixel(button)).is_equal_approx(background), name + ": saved state keeps the background")
	button.release_focus()
	await _settle()
	_expect(button.get_theme_color("font_color").is_equal_approx(view._accent()) and button.get_theme_color("icon_normal_color").is_equal_approx(view._accent()), name + ": saved text and icon stay blue without focus or hover")
	await _capture("wrong-button-saved-" + name)
	button.grab_focus()
	button.mouse_entered.emit()
	button.pressed.emit()
	await _settle()
	_expect(not quiz.wrong_ids.has(str(quiz.questions[quiz.current_index].id)), name + ": removing a wrong question still works")
	_expect(button.get_theme_color("font_color").is_equal_approx(view.text_color) and button.get_theme_color("icon_normal_color").is_equal_approx(view.text_color), name + ": removing restores the normal color even while focused and hovered")
	button.release_focus()
	button.mouse_exited.emit()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	app = root.get_node("AppState")
	stats = root.get_node("StudyStats")
	# Let AppState finish its one-time native window fit before choosing test size.
	await process_frame
	await process_frame
	_prepare_test_window()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1600, 984)
	root.size = Vector2i(1600, 984)
	app.quiz_mode = "all"
	app.subject_id = "mao"
	app.start_index = 0
	var quiz: Node = await _open("Quiz")
	var view: Control = quiz.minimal_view
	_right_rail(view)
	_expect(view.header.get_global_rect().encloses(quiz.home_button.get_global_rect()), "Return button and its hit area stay inside the header")
	await _capture("quiz-right-list")
	await _wrong_action_feedback(quiz, "light")
	await _click(view.number_buttons[2])
	_expect(quiz.current_index == 2, "Mouse selects a question in the relocated number grid")
	quiz._on_option_pressed(0)
	var states: Dictionary = quiz.question_states.duplicate(true)
	var history: Dictionary = stats.history.duplicate(true)
	var original_rect: Rect2 = view.pane.get_rect()
	var start: int = view.start_msec
	view.finish.grab_focus()
	await _key(KEY_F6)
	_expect(view.distraction_free and not view.sidebar.visible and not view.header.visible, "F6 hides the left navigation and top header")
	_expect(view.pane.position == Vector2(36, 0) and view.pane.size.x > original_rect.size.x and view.pane.size.y > original_rect.size.y, "Focus mode reclaims the hidden regions")
	_expect(root.gui_get_focus_owner() != view.finish, "Hidden header no longer owns keyboard focus")
	_right_rail(view)
	await _capture("quiz-focus")
	for action in [quiz.prev_button, quiz.next_button, quiz.wrong_toggle]:
		_expect(action.is_visible_in_tree() and action.modulate.a == 1.0 and action.self_modulate.a == 1.0, "Focus mode keeps footer actions visible")
		_expect(Rect2(Vector2.ZERO, view.pane.size).encloses(action.get_rect()), "Focus mode keeps footer actions within the answer pane")
	await _key(KEY_F6, true)
	_expect(view.distraction_free, "Holding F6 ignores repeat events")
	await _key(KEY_F6)
	_expect(not view.distraction_free and view.sidebar.visible and view.header.visible and view.pane.get_rect() == original_rect, "F6 restores the original layout")
	_expect(root.gui_get_focus_owner() == view.finish, "Restoring the header restores its prior focus when no other control took focus")
	_expect(quiz.current_index == 2 and quiz.question_states == states and stats.history == history and view.start_msec == start, "Toggling does not change answers, statistics, current question or timer baseline")
	quiz.jump_input.text = "8"
	quiz.jump_input.grab_focus()
	await _key(KEY_F6)
	_expect(view.distraction_free and root.gui_get_focus_owner() == quiz.jump_input and quiz.jump_input.text == "8", "F6 works while a text input is focused without changing its contents")
	quiz.jump_button.pressed.emit()
	_expect(quiz.current_index == 7, "Number jump works in focus mode")
	await _key(KEY_F9)
	await _settle()
	_expect(view.distraction_free and not view.sidebar.visible and not view.header.visible, "Theme rebuild preserves focus mode")
	_right_rail(view)
	await _capture("quiz-focus-dark")
	await _wrong_action_feedback(quiz, "dark")
	await _key(KEY_F6)
	await _key(KEY_F9)
	await _settle()
	view.hide_numbers.pressed.emit()
	await _key(KEY_F6)
	await _key(KEY_F6)
	_expect(not view.rail.is_visible_in_tree() and view.pane.get_node("ShowNumbers").visible, "F6 preserves a manually hidden number list")
	view.pane.get_node("ShowNumbers").pressed.emit()
	_right_rail(view)
	root.content_scale_size = Vector2i(1100, 820)
	root.size = Vector2i(1100, 820)
	await _settle()
	_right_rail(view)
	await _capture("quiz-right-list-narrow")
	await _key(KEY_F6)
	_right_rail(view)
	view.hide_numbers.pressed.emit()
	app._set_font_scale(1.4)
	await _capture("quiz-focus-large-text")
	_expect(view.distraction_free and not view.sidebar.visible and not view.header.visible, "Resize and font scaling preserve focus mode")
	app._set_font_scale(1.0)
	app.subject_id = "python"
	app.start_index = 0
	quiz = await _open("Quiz")
	view = quiz.minimal_view
	_expect(not view.distraction_free and view.sidebar.visible and view.header.visible, "A new quiz starts with its normal navigation")
	for kind in ["fill", "program"]:
		for index in quiz.questions.size():
			if quiz.questions[index].type == kind:
				quiz._jump_to(index)
				break
		await _settle()
		var field: Control = quiz.fill_inputs[0] if kind == "fill" else quiz.program_editor.editor
		field.text = "focus draft"
		field.grab_focus()
		await _key(KEY_F6)
		_expect(view.distraction_free and root.gui_get_focus_owner() == field and field.text == "focus draft", "F6 preserves focused " + kind + " input and draft")
		await _key(KEY_F6)
		_expect(not view.distraction_free and field.text == "focus draft", "Restoring preserves " + kind + " input")
	app.subject_id = "marxism"
	app.start_index = 167
	root.content_scale_size = Vector2i(1600, 984)
	root.size = Vector2i(1600, 984)
	quiz = await _open("Quiz")
	await _capture("quiz-normal-long-question")
	await _key(KEY_F6)
	await _capture("quiz-focus-long-question")
	await _open("Workbench")
	await _key(KEY_F6)
	_expect(current_scene.sidebar.visible, "Quiz shortcut does not hide navigation on other pages")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
