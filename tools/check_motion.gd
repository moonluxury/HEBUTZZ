extends SceneTree
## Behavioral risks, using real controls and isolated saves. No animation completion gates.
const T = preload("res://scripts/ui_tokens.gd")
var failures: Array[String] = []
var motion: Node
var app: Node
var stats: Node

func _init() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _settle() -> void:
	await create_timer(0.34).timeout

func _open(scene: String) -> Node:
	change_scene_to_file("res://scenes/" + scene + ".tscn")
	await process_frame
	await process_frame
	await _settle()
	return current_scene

func _key(key: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = down
		root.push_input(event)
		await process_frame

func _check_tab_underlines(buttons: Array, name: String) -> void:
	var initial: ColorRect = buttons[0].get_node("SelectionLine")
	var line: ColorRect = buttons[1].get_node("SelectionLine")
	var button_rect: Rect2 = buttons[1].get_rect()
	var center: Vector2 = line.get_global_transform() * (line.size * 0.5)
	_expect(initial.visible and initial.scale == Vector2.ONE, name + ": initial selection is fully drawn")
	buttons[1].pressed.emit()
	# Godot clamps a Control's zero scale to about 0.00001.
	_expect(line.visible and line.scale.x < 0.0001 and not initial.visible, name + ": click starts at the center and removes the old underline")
	await create_timer(T.TAB_UNDERLINE * 0.2).timeout
	_expect(line.scale.x > 0.0 and line.scale.x < 1.0, name + ": underline expands over time")
	_expect(buttons[1].get_theme_color("font_color") == T.PRIMARY and buttons[0].get_theme_color("font_color") != T.PRIMARY, name + ": selected text follows the new underline")
	_expect((line.get_global_transform() * (line.size * 0.5)).is_equal_approx(center), name + ": expansion keeps the center fixed")
	_expect(buttons[1].get_rect() == button_rect and buttons[1].scale == Vector2.ONE and line.scale.y == 1.0, name + ": hit area, text and line thickness remain fixed")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/minimal-design/underline-" + name + "-expanding.png")
	await create_timer(T.TAB_UNDERLINE + 0.05).timeout
	_expect(line.scale == Vector2.ONE, name + ": underline reaches full width")
	buttons[1].pressed.emit()
	_expect(line.scale.x < 0.0001, name + ": repeated click restarts from the center")
	for button in buttons:
		button.pressed.emit()
	buttons[0].pressed.emit()
	await create_timer(T.TAB_UNDERLINE + 0.05).timeout
	for index in buttons.size():
		var underline: ColorRect = buttons[index].get_node("SelectionLine")
		_expect(underline.visible == (index == 0) and underline.scale == Vector2.ONE, name + ": rapid switching leaves only the latest complete underline")
	buttons[1].pressed.emit()
	motion.set_enabled(false)
	_expect(line.scale == Vector2.ONE and motion.tracks.is_empty(), name + ": reduced motion finishes an active underline")
	buttons[0].pressed.emit()
	_expect(initial.visible and initial.scale == Vector2.ONE and motion.tracks.is_empty(), name + ": reduced motion selects immediately")
	motion.set_enabled(true)
	await _settle()

func _check_search_focus(page: Node, name: String) -> void:
	# Keep the real test window's cursor out of search fields in both layouts.
	var pointer := InputEventMouseMotion.new()
	pointer.position = Vector2(1590, 20)
	pointer.global_position = pointer.position
	root.push_input(pointer)
	await process_frame
	for dark_mode in [false, true]:
		app.dark_mode = dark_mode
		app.color_mode_changed.emit(dark_mode)
		await _settle()
		var search: LineEdit = page.search_edit
		search.release_focus()
		search.mouse_exited.emit()
		await _settle()
		var normal: StyleBoxFlat = search.get_theme_stylebox("normal")
		var background := normal.bg_color
		var outline := normal.border_color
		var sample_point: Vector2i = Vector2i(search.get_global_transform() * Vector2(search.size.x - 36, search.size.y * 0.5))
		var before_pixel := Color.TRANSPARENT
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			before_pixel = root.get_texture().get_image().get_pixelv(sample_point)
		search.grab_focus()
		await create_timer(T.STATE * 0.4).timeout
		_expect(normal.bg_color == background, name + ": input fill stays unchanged during focus transition")
		await _settle()
		var focus: StyleBoxFlat = search.get_theme_stylebox("focus")
		_expect(search.has_focus() and normal.border_color.is_equal_approx(T.PRIMARY) and not normal.border_color.is_equal_approx(outline), "%s dark=%s: focus retains border feedback (focused=%s, border=%s, old=%s)" % [name, dark_mode, search.has_focus(), normal.border_color, outline])
		_expect(normal.bg_color == background and focus.bg_color.a == 0.0 and focus.shadow_size == 0, name + ": focus has no interior overlay")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			_expect(frame.get_pixelv(sample_point).is_equal_approx(before_pixel), name + ": rendered input interior is identical before and after focus")
			frame.save_png("res://outputs/minimal-design/search-focus-" + name + ("-dark" if dark_mode else "-light") + ".png")
		search.release_focus()
		await _settle()
		_expect(normal.bg_color == background and normal.border_color.is_equal_approx(outline), "%s dark=%s: blur restores the border without changing fill (border=%s, old=%s)" % [name, dark_mode, normal.border_color, outline])
	app.dark_mode = false
	app.color_mode_changed.emit(false)
	await _settle()

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	motion = root.get_node("UiMotion")
	app = root.get_node("AppState")
	stats = root.get_node("StudyStats")
	root.content_scale_size = Vector2i(1600, 984)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 984)
	# Exercise animated paths regardless of this test machine's accessibility setting.
	print("System reduce-animation capability: ", motion.system_reduced)
	motion.system_reduced = 0
	motion.suspended = false
	motion.set_enabled(true)
	var page: Node = await _open("SubjectSelect")
	await _check_tab_underlines(page.tabs_root.get_children(), "bank")
	await _check_search_focus(page, "bank")
	var canvas: Control = page.canvas
	var search: LineEdit = page.search_edit
	search.grab_focus()
	page._search_changed("p")
	page._search_changed("python")
	page._select_category("计算机类")
	page.filter_button.get_popup().id_pressed.emit(1)
	_expect(page.canvas == canvas and page.search_edit == search, "Filtering preserves sidebar, search instance and input focus")
	_expect(search.has_focus() and page.cards.size() == 1 and page.cards[0].name == "python", "Latest combined query wins without an animation lock")
	await _settle()
	var popup: PopupMenu = page.filter_button.get_popup()
	popup.popup(Rect2i(800, 240, 260, 220))
	await create_timer(0.05).timeout
	_expect(not motion.suspended, "An application-owned popup does not suspend the app")
	var tint: CanvasModulate = popup.find_children("*", "CanvasModulate", false, false)[0]
	_expect(tint.color.a > 0.0 and tint.color.a < 1.0, "Menu fades during actual opening without delaying interaction")
	await _settle()
	_expect(popup.visible, "Existing menu opens during normal input")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		popup.get_texture().get_image().save_png("res://outputs/minimal-design/motion-filter-menu.png")
	popup.hide()
	_expect(not popup.visible, "Menu closes immediately without a lingering input shield")
	search.grab_focus()
	var card: Panel = page.cards[0]
	var card_rect := card.get_rect()
	card.mouse_entered.emit()
	card.mouse_exited.emit()
	card.mouse_entered.emit()
	await _settle()
	_expect(card.get_rect() == card_rect and card.scale == Vector2.ONE, "Card hover never moves or scales layout")
	_expect(card.mouse_default_cursor_shape == Control.CURSOR_ARROW and card.focus_mode == Control.FOCUS_NONE, "Course surface remains non-clickable")
	var link: Button = card.get_node("CourseAction")
	link.grab_focus()
	await _key(KEY_ENTER)
	await _settle()
	_expect(current_scene.scene_file_path.ends_with("Quiz.tscn"), "Keyboard Enter opens a course")
	if not current_scene.scene_file_path.ends_with("Quiz.tscn"):
		quit(1)
		return
	var quiz: Node = current_scene
	var view: Node = quiz.minimal_view
	var primary: Button = quiz.next_button
	var initial_rect := primary.get_rect()
	primary.mouse_entered.emit()
	await _settle()
	_expect(primary.get_theme_stylebox("normal").bg_color.is_equal_approx(T.HOVER_COLOR), "Primary hover uses brand hover color")
	primary.button_down.emit()
	await create_timer(0.1).timeout
	_expect(primary.get_theme_stylebox("normal").bg_color.is_equal_approx(T.PRESSED_COLOR), "Primary press uses brand pressed color")
	primary.button_up.emit()
	primary.disabled = true
	primary.queue_redraw()
	await _settle()
	_expect(primary.get_theme_stylebox("normal").bg_color != T.HOVER_COLOR, "Disabled cancels hover/press")
	_expect(primary.get_rect() == initial_rect and primary.scale == Vector2.ONE, "Primary label and hit box remain stable")
	primary.disabled = false
	motion.set_hover_enabled(false)
	primary.mouse_entered.emit()
	await _settle()
	_expect(primary.get_theme_stylebox("normal").bg_color.is_equal_approx(T.PRIMARY), "Touch mode cannot retain hover")
	motion.set_hover_enabled(true)
	primary.mouse_exited.emit()
	var clock_started: int = view.start_msec
	# Verify answer colors independently of the desktop cursor's hover position.
	motion.set_hover_enabled(false)
	quiz._jump_to(0)
	quiz._on_option_pressed(0)
	var saved: Dictionary = quiz.question_states[quiz._question_state_key(0)].duplicate(true)
	for index in range(1, 30):
		quiz._jump_to(index)
		_expect(quiz.question_label.text == "%d. %s" % [quiz.questions[index].id, quiz.questions[index].stem], "Stem matches the latest ID")
		_expect(not quiz.has_answered and quiz.selected_indices.is_empty() and quiz.answer_label.text.is_empty(), "New question has no previous answer or analysis")
		_expect(quiz.option_buttons[0].get_theme_stylebox("normal").bg_color.is_equal_approx(Color.WHITE), "No previous green/red background leaks across questions")
	motion.set_hover_enabled(true)
	quiz._jump_to(0)
	_expect(not quiz.has_answered and quiz.selected_indices.is_empty() and quiz.question_states[quiz._question_state_key(0)] == saved, "Revisiting permits a fresh attempt while preserving the completed record")
	_expect(view.start_msec == clock_started, "Question changes never reset the timer")
	quiz._jump_to(1)
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await _settle()
	_expect(quiz.question_scroll.modulate.a == 1.0 and quiz.question_scroll.is_visible_in_tree(), "Theme rebuild during a question fade cannot leave reused content transparent")
	app.dark_mode = false
	app.color_mode_changed.emit(false)
	app.subject_id = "matlab"
	app.start_index = 0
	quiz = await _open("Quiz")
	view = quiz.minimal_view
	var multiple := -1
	for index in quiz.questions.size():
		if quiz.questions[index].type == "multiple" and multiple == -1:
			multiple = index
	quiz._jump_to(multiple)
	quiz._on_option_pressed(0)
	_expect(not quiz.has_answered and not quiz.question_states[quiz._question_state_key(multiple)].answered, "Multiple choice selection is saved immediately without judgement")
	await _settle()
	_expect(quiz.option_buttons[0].get_theme_stylebox("normal").bg_color.is_equal_approx(T.SOFT), "Unsubmitted selection stays brand blue/soft rather than green")
	quiz._jump_to(multiple + 1)
	quiz._jump_to(multiple)
	_expect(quiz.selected_indices.size() == 1, "Unsubmitted selection survives navigation")
	quiz._submit_multiple_answer()
	var attempts: int = stats.history[Time.get_date_string_from_system()].attempts
	quiz._submit_multiple_answer()
	_expect(stats.history[Time.get_date_string_from_system()].attempts == attempts, "Repeated submission does not record another attempt")
	# Force an actual file-open failure in the isolated save directory.
	var wrong_path: String = app.get_subject().wrong_path
	DirAccess.remove_absolute(wrong_path)
	DirAccess.make_dir_absolute(wrong_path)
	var before_wrongs: Dictionary = quiz.wrong_ids.duplicate()
	quiz._toggle_wrong_current()
	_expect(quiz.wrong_ids == before_wrongs and quiz.result_label.text.contains("保存失败"), "Failed persistence restores state and shows local error")
	DirAccess.remove_absolute(wrong_path)
	quiz._toggle_wrong_current()
	_expect(FileAccess.file_exists(wrong_path), "Retry persists the real state")
	view.finish.pressed.emit()
	view.finish.pressed.emit()
	await process_frame
	await process_frame
	_expect(current_scene.scene_file_path == "res://scenes/Workbench.tscn", "Finish returns directly to the workbench, including rapid repeated clicks")
	_expect(stats.history[Time.get_date_string_from_system()].attempts == attempts, "Finishing preserves recorded attempts without duplicate submission")
	app.subject_id = "python"
	app.start_index = 0
	quiz = await _open("Quiz")
	view = quiz.minimal_view
	clock_started = view.start_msec
	for index in quiz.questions.size():
		if quiz.questions[index].type == "program":
			quiz._jump_to(index)
			break
	var editor: Node = quiz.program_editor
	editor.editor.text = "import time\ntime.sleep(0.6)\nprint('motion-check')"
	editor._run_code()
	var pid: int = editor.runner.pid
	editor._run_code()
	_expect(pid > 0 and editor.runner.pid == pid and editor.run_button.disabled, "Real pending execution rejects duplicate run")
	while editor.runner.is_running():
		await create_timer(0.1).timeout
	_expect(editor.output_editor.text.contains("motion-check") and not editor.run_button.disabled, "Real execution completes and re-enables action")
	editor.editor.text = "raise ValueError('expected-check-error')"
	editor._run_code()
	while editor.runner.is_running():
		await create_timer(0.1).timeout
	_expect(editor.run_status.text.contains("出错") and not editor.run_button.disabled and editor.editor.text.contains("ValueError"), "Execution failure preserves draft and permits retry")
	editor._toggle_reference()
	motion.set_enabled(false)
	_expect(motion.tracks.is_empty() and editor.reference_box.modulate.a == 1.0, "Reduced motion settles all active tracks immediately")
	quiz._jump_to(2)
	_expect(quiz.current_index == 2 and quiz.question_scroll.modulate.a == 1.0, "Reduced motion keeps question navigation functional")
	motion._suspend()
	_expect(view.clock_timer.is_stopped(), "Window focus loss stops display timer")
	motion._resume()
	_expect(not view.clock_timer.is_stopped() and view.start_msec == clock_started, "Focus return resumes clock without reset")
	motion.system_reduced = 0
	motion.set_enabled(true)
	# A desktop focus notification can arrive after removal but before deletion.
	quiz.remove_child(view)
	motion.preference_changed.emit()
	quiz.add_child(view)
	page = await _open("Workbench")
	var old_body: Control = page.body
	var old_chart: Control = page.trend_chart
	stats.record_answer("python", stats.banks.python[35], true)
	_expect(page.body == old_body and page.trend_chart == old_chart, "Real stats update keeps content and chart instances")
	await _settle()
	_expect(is_equal_approx(page.stat_cards[1].get_node("Progress").value, stats.summary().percent), "Progress ends at the real latest value")
	var focused := root.gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	_expect(page.trend.focus_mode == Control.FOCUS_NONE, "Learning trend does not take focus on click")
	page._show_history()
	page._close_details()
	_expect(page.detail_overlay == null and root.gui_get_focus_owner() == null, "Closing a panel releases focus without focusing the trend")
	page = await _open("HegongKaiwu")
	await _check_tab_underlines([page.body.get_node("Category0"), page.body.get_node("Category1"), page.body.get_node("Category2"), page.body.get_node("Category3")], "resources")
	await _check_search_focus(page, "resources")
	page.body.get_node("Category1").pressed.emit()
	app.dark_mode = true
	app.color_mode_changed.emit(true)
	await _settle()
	var themed_line: ColorRect = page.body.get_node("Category1/SelectionLine")
	_expect(themed_line.visible and themed_line.scale == Vector2.ONE and themed_line.color == T.DARK_ACCENT, "Theme rebuild settles the current underline with the dark accent")
	app.dark_mode = false
	app.color_mode_changed.emit(false)
	await _settle()
	canvas = page.canvas
	page._search_changed("热泵")
	page._select_category("复习资料")
	_expect(page.canvas == canvas and page.visible_entries.size() == 1, "Resource filters update locally with latest results")
	page._open_entry(page.visible_entries[0])
	page._open_entry(page.visible_entries[0])
	page._open_entry(page.visible_entries[0])
	await _settle()
	_expect(page.list_root.find_child("Preview", true, false) != null, "Rapid preview toggles settle to latest state")
	app.quiz_mode = "wrong"
	page = await _open("SubjectSelect")
	await _check_tab_underlines(page.tabs_root.get_children(), "wrong")
	_expect(page.tabs_root.get_node("Filter0").get_theme_stylebox("normal").bg_color.a == 0.0, "Wrong filters use underlines instead of a filled selected pill")
	old_chart = page.wrong_chart
	canvas = page.canvas
	page._select_wrong_filter("已练习")
	page._select_wrong_filter("全部错题")
	_expect(page.canvas == canvas and page.wrong_chart == old_chart, "Wrong filters retain the chart and stable navigation")
	page = await _open("MyCollection")
	await _settle()
	_expect(motion.tracks.is_empty() and get_processed_tweens().is_empty(), "Navigation and idle leave no queued/looping animations")
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
