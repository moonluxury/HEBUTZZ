extends "res://scripts/minimal_page.gd"
## Presentation adapter. The existing quiz controller still owns answers, saves and drafts.
const QUESTION_FONT_SIZE := 26
const OPTION_FONT_SIZE := 24
const FOCUS_QUESTION_FONT_SIZE := 28
const FOCUS_OPTION_FONT_SIZE := 24
var quiz: Node
var header: Control
var rail: Control
var number_scroll: ScrollContainer
var number_column: Control
var pane: Control
var question_meta: Label
var heading: Label
var timer_label: Label
var finish: Button
var hide_numbers: Button
var rail_visible := true
var compact_rail_open := false
var distraction_free := false
var hidden_focus_path := NodePath()
# Only visible indices have controls. The pool survives scrolling.
var number_buttons: Dictionary = {}
var number_pool: Array[Button] = []
var title_pool: Array[Label] = []
var number_rows: Array[Dictionary] = []
var number_positions: Array[Vector2] = []
var number_count := 0
var numbers_queued := false
var last_number := -1
var start_msec := Time.get_ticks_msec()
var footer_line: Control
var clock_timer: Timer

func _ready() -> void:
	active_nav = "WrongButton" if _app().quiz_mode == "wrong" else "AllButton"
	super._ready()
	clock_timer = Timer.new()
	clock_timer.wait_time = 1.0
	clock_timer.autostart = true
	clock_timer.timeout.connect(_update_timer)
	add_child(clock_timer)
	_motion().preference_changed.connect(_sync_clock)
	_sync_clock()
	question_changed()

func _build_content() -> void:
	number_pool.clear()
	title_pool.clear()
	number_buttons.clear()
	scroll.hide()
	header = _display_panel(canvas, "QuizHeader")
	_move(quiz.home_button, header)
	quiz.home_button.text = "返回"
	quiz.home_button.icon = _texture("res://assets/minimal/icons/arrow-left.png")
	_rect(quiz.home_button, Rect2(30, 39, 112, 54))
	_line(header, Rect2(164, 45, 1, 42))
	heading = _label(header, str(quiz._subject().title), 28, text_color, Rect2(194, 32, 680, 64), true)
	_icon(header, "clock", Rect2(986, 53, 24, 24), muted_color).name = "Clock"
	timer_label = _label(header, "00:00:00", BODY_SIZE, muted_color)
	var clock_font := FontVariation.new()
	clock_font.base_font = theme.default_font
	clock_font.opentype_features = {"tnum": 1}
	timer_label.add_theme_font_override("font", clock_font)
	finish = _button(header, "FinishPractice", "结束练习", _finish_session)
	finish.add_theme_stylebox_override("normal", _style(surface, 8, BLUE))
	finish.add_theme_color_override("font_color", _accent())
	_line(header, Rect2(0, 124, 1600, 1))
	rail = _display_panel(canvas, "QuestionRail", surface)
	rail.z_index = 2
	_label(rail, "题号列表", SECTION_SIZE, text_color, Rect2(32, 25, 220, 48), true)
	hide_numbers = _button(rail, "HideNumbers", "隐藏", _toggle_rail)
	_rect(hide_numbers, Rect2(265, 29, 64, 42))
	number_scroll = ScrollContainer.new()
	number_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail.add_child(number_scroll)
	number_column = Control.new()
	number_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	number_scroll.add_child(number_column)
	number_scroll.get_v_scroll_bar().value_changed.connect(_queue_visible_numbers.unbind(1))
	number_scroll.resized.connect(_queue_visible_numbers)
	var legend := _display_panel(rail, "Legend")
	for index in 3:
		var point := Vector2((index % 2) * 154, (index / 2) * 36)
		var box := _display_panel(legend, "State%d" % index)
		var fill := BLUE if index == 0 else Tokens.SOFT if index == 1 else surface
		box.add_theme_stylebox_override("panel", _style(fill, 4, border if index == 2 else Color.TRANSPARENT))
		_rect(box, Rect2(point + Vector2(0, 7), Vector2(20, 20)))
		if index == 1:
			_icon(box, "check", Rect2(2, 2, 16, 16), BLUE)
		_label(legend, ["当前题", "已答", "未答"][index], 18, muted_color, Rect2(point + Vector2(30, 0), Vector2(110, 34)))
	_line(rail, Rect2(0, 0, 1, 2000))
	pane = _display_panel(canvas, "QuestionPane")
	_line(pane, Rect2(0, 64, 1300, 1)).name = "MetaDivider"
	question_meta = _label(pane, "", BODY_SIZE, text_color, Rect2(0, 10, 600, 44), true)
	_move(quiz.question_scroll, pane)
	quiz.question_scroll.get_child(0).custom_minimum_size.x = 0
	_move(quiz.prev_button, pane)
	_move(quiz.next_button, pane)
	_move(quiz.wrong_toggle, pane)
	quiz.wrong_toggle.set_meta("state_only_feedback", true)
	footer_line = _line(pane, Rect2())
	_move(quiz.jump_input, rail)
	_move(quiz.jump_button, rail)
	quiz.jump_input.placeholder_text = "输入题号"
	quiz.jump_button.text = "跳转"
	quiz.jump_button.icon = null
	quiz.prev_button.text = "上一题"
	quiz.next_button.text = "下一题"
	quiz.prev_button.icon = _texture("res://assets/minimal/icons/arrow-left.png")
	quiz.next_button.icon = _texture("res://assets/minimal/icons/arrow-right.png")
	quiz.next_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quiz.empty_label.hide()
	if quiz.questions.is_empty():
		_move(quiz.empty_label, pane)
		_rect(quiz.empty_label, Rect2(0, 160, 800, 200))
		quiz.empty_label.add_theme_font_size_override("font_size", SECTION_SIZE)
		quiz.empty_label.add_theme_color_override("font_color", muted_color)
		quiz.empty_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		quiz.empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quiz.question_scroll.hide()
		for control in [quiz.prev_button, quiz.next_button, quiz.wrong_toggle, finish]:
			control.hide()
	build_numbers()
	refresh()

func _move(control: Control, parent: Node) -> void:
	control.reparent(parent, false)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.custom_minimum_size = Vector2.ZERO
	if control is Button:
		# Set this before assigning a 384 px icon, otherwise Button expands its
		# minimum size and keeps an oversized hit area after later restyling.
		control.expand_icon = true
	control.show()

func build_numbers() -> void:
	number_rows.clear()
	number_positions.clear()
	number_count = quiz.questions.size()
	var y := 0.0
	var index := 0
	while index < number_count:
		var kind := str(quiz.questions[index].get("type_label", "题目"))
		var end := index + 1
		while end < number_count and str(quiz.questions[end].get("type_label", "题目")) == kind:
			end += 1
		number_rows.append({"y": y, "title": kind})
		y += 56
		while index < end:
			var count := mini(5, end - index)
			number_rows.append({"y": y, "start": index, "count": count})
			for column in count:
				number_positions.append(Vector2(column * 62, y))
			index += count
			y += 62
		y += 4
	number_column.custom_minimum_size = Vector2(298, y)
	last_number = -1
	for button in number_pool:
		button.set_meta("number_state", "")
	_queue_visible_numbers()
	_ensure_current_visible.call_deferred()

func _queue_visible_numbers() -> void:
	if not numbers_queued:
		numbers_queued = true
		_render_visible_numbers.call_deferred()

func _render_visible_numbers() -> void:
	numbers_queued = false
	if not is_inside_tree() or not is_instance_valid(number_column):
		return
	var top := float(number_scroll.scroll_vertical) - 62.0
	var bottom := top + number_scroll.size.y + 124.0
	var indices: Array[int] = []
	var titles: Array[Dictionary] = []
	for row in number_rows:
		if row.y + 50 < top:
			continue
		if row.y > bottom:
			break
		if row.has("title"):
			titles.append(row)
		else:
			for offset in row.count:
				indices.append(row.start + offset)
	while number_pool.size() < indices.size():
		var button := _button(number_column, "NumberSlot%d" % number_pool.size(), "", Callable())
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(func(): quiz._jump_to(int(button.get_meta("number_index"))))
		button.gui_input.connect(_number_key.bind(button))
		number_pool.append(button)
	number_buttons.clear()
	for slot in number_pool.size():
		var button := number_pool[slot]
		button.visible = slot < indices.size()
		if not button.visible:
			continue
		var index := indices[slot]
		if int(button.get_meta("number_index", -1)) != index:
			if button.has_focus():
				button.release_focus()
			button.set_meta("number_index", index)
			button.set_meta("number_state", "")
			button.set_meta("motion_snap", true)
			button.text = str(index + 1)
		_rect(button, Rect2(number_positions[index], Vector2(50, 50)))
		number_buttons[index] = button
		_style_number(index)
	while title_pool.size() < titles.size():
		title_pool.append(_label(number_column, "", BODY_SIZE, muted_color))
	for slot in title_pool.size():
		title_pool[slot].visible = slot < titles.size()
		if slot < titles.size():
			title_pool[slot].text = titles[slot].title
			_rect(title_pool[slot], Rect2(0, titles[slot].y, 298, 40))

func _style_number(index: int) -> void:
	if not number_buttons.has(index):
		return
	var b: Button = number_buttons[index]
	var answered := bool(quiz.question_states.get(quiz._question_state_key(index), {}).get("answered", false))
	var selected: bool = index == quiz.current_index
	var state_key := "%s:%s:%s" % [answered, selected, dark]
	if b.get_meta("number_state", "") == state_key:
		return
	b.set_meta("number_state", state_key)
	var color := BLUE if selected else Tokens.DARK_SOFT if dark and answered else Tokens.SOFT if answered else surface
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, _style(color, 6, BLUE if selected else border))
		b.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), Color.WHITE if selected else _accent() if answered else text_color)
	b.icon = null
	b.accessibility_name = "第 %d 题，%s%s" % [index + 1, "当前题，" if selected else "", "已答" if answered else "未答"]
	_motion().bind_button(b)

func refresh_numbers() -> void:
	if not is_instance_valid(number_column):
		return
	if number_count != quiz.questions.size():
		build_numbers()
	_style_number(last_number)
	_style_number(quiz.current_index)
	if last_number != quiz.current_index:
		_ensure_current_visible.call_deferred()
	last_number = quiz.current_index

func _ensure_current_visible() -> void:
	if not is_inside_tree() or not is_instance_valid(quiz) or quiz.current_index >= number_positions.size():
		return
	_ensure_number_visible(quiz.current_index)

func _ensure_number_visible(index: int) -> void:
	var y := number_positions[index].y
	if y < number_scroll.scroll_vertical:
		number_scroll.scroll_vertical = int(y)
	elif y + 50 > number_scroll.scroll_vertical + number_scroll.size.y:
		number_scroll.scroll_vertical = int(y + 50 - number_scroll.size.y)
	_render_visible_numbers()

func _number_key(event: InputEvent, button: Button) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var index := int(button.get_meta("number_index"))
	var target := index
	match event.keycode:
		KEY_LEFT: target -= 1
		KEY_RIGHT: target += 1
		KEY_UP: target -= 5
		KEY_DOWN: target += 5
		KEY_HOME: target = 0
		KEY_END: target = number_count - 1
		KEY_PAGEUP: target -= maxi(5, int(number_scroll.size.y / 62) * 5)
		KEY_PAGEDOWN: target += maxi(5, int(number_scroll.size.y / 62) * 5)
		_: return
	button.accept_event()
	target = clampi(target, 0, number_count - 1)
	_ensure_number_visible(target)
	number_buttons[target].grab_focus()

func refresh() -> void:
	if not is_instance_valid(pane):
		return
	quiz.theme = theme
	quiz._style_fill_inputs()
	_font_controls(quiz.question_scroll.get_child(0))
	quiz.question_label.add_theme_font_override("normal_font", theme.default_font)
	quiz.question_label.add_theme_color_override("default_color", text_color)
	_apply_question_typography()
	for b in quiz.option_buttons:
		b.add_theme_constant_override("h_separation", 18)
		b.expand_icon = true
	_style_button(quiz.submit_button, BLUE, true)
	for b in [quiz.prev_button, quiz.next_button, quiz.wrong_toggle, quiz.home_button, quiz.jump_button]:
		_style_button(b, surface, b == quiz.next_button)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		if b == quiz.prev_button:
			b.add_theme_stylebox_override("normal", _style(surface, 8, border))
	quiz.jump_input.add_theme_font_size_override("font_size", BUTTON_SIZE)
	quiz.jump_input.add_theme_color_override("font_color", text_color)
	quiz.jump_input.add_theme_color_override("font_placeholder_color", muted_color)
	var input_style := _style(surface, 8, border)
	input_style.content_margin_left = 12
	for state in ["normal", "focus"]:
		quiz.jump_input.add_theme_stylebox_override(state, input_style)
	_motion().bind_input.call_deferred(quiz.jump_input)
	quiz.answer_label.add_theme_color_override("font_color", text_color)
	if quiz.has_answered:
		quiz.result_label.add_theme_color_override("font_color", quiz._correct_feedback_color() if quiz._is_selection_correct() else quiz._wrong_feedback_color())
	if quiz.questions.is_empty():
		return
	var question: Dictionary = quiz.questions[quiz.current_index]
	question_meta.text = "%s · %d / %d" % [question.get("type_label", "题目"), quiz.current_index + 1, quiz.questions.size()]
	quiz.wrong_toggle.icon = _texture("res://assets/minimal/icons/clipboard-x.png")
	var in_wrongs: bool = quiz.wrong_ids.has(str(question.id))
	quiz.wrong_toggle.add_theme_stylebox_override("normal", _style(surface, 8))
	quiz.wrong_toggle.add_theme_color_override("font_color", _accent() if in_wrongs else text_color)
	quiz.wrong_toggle.add_theme_color_override("icon_normal_color", _accent() if in_wrongs else text_color)
	# Capture the saved/unsaved colors before a same-frame focus change can repaint them.
	_motion().bind_button(quiz.wrong_toggle)
	quiz._refresh_all_option_visuals()
	refresh_numbers()
	_update_timer()

func _apply_question_typography() -> void:
	var compact_height := canvas.size.y - (0.0 if distraction_free else 125.0) < 650.0
	quiz.question_label.add_theme_font_size_override("normal_font_size", FOCUS_QUESTION_FONT_SIZE if distraction_free else QUESTION_FONT_SIZE)
	quiz.question_label.add_theme_constant_override("line_separation", 8)
	# fit_content grows with wrapped text; short stems do not reserve empty lines.
	quiz.question_label.custom_minimum_size.y = 0
	quiz.question_scroll.get_child(0).add_theme_constant_override("separation", 16 if compact_height else 24)
	quiz.submit_button.custom_minimum_size = Vector2(170, 44 if compact_height else 48)
	for button in quiz.option_buttons:
		button.custom_minimum_size.y = 48 if compact_height else 56
		button.add_theme_font_size_override("font_size", FOCUS_OPTION_FONT_SIZE if distraction_free else OPTION_FONT_SIZE)
		button.add_theme_constant_override("line_spacing", 6)

func _font_controls(node: Node) -> void:
	if node is Control:
		node.add_theme_font_size_override("font_size", BODY_SIZE)
		if node is Label or node is Button or node is LineEdit:
			node.add_theme_font_override("font", theme.default_font)
		if node is Button:
			_style_button(node, surface)
		if node is LineEdit:
			node.custom_minimum_size.y = 58
		if node is CodeEdit:
			node.custom_minimum_size.y = minf(node.custom_minimum_size.y, 380)
	for child in node.get_children():
		_font_controls(child)

func _layout() -> void:
	if size.x < 1 or size.y < 1:
		return
	super._layout()
	if not is_instance_valid(pane):
		return
	_apply_question_typography()
	var sidebar_width := 0.0 if distraction_free else 264.0
	var header_height := 0.0 if distraction_free else 125.0
	sidebar.visible = not distraction_free
	header.visible = not distraction_free
	if is_instance_valid(wallet_badge): wallet_badge.visible = not distraction_free
	var available := canvas.size.x - sidebar_width
	_rect(header, Rect2(sidebar_width, 0, available, 125))
	_rect(quiz.home_button, Rect2(30, 39, 112, 54))
	heading.size.x = available - 510
	_rect(header.get_node("Clock"), Rect2(available - 320, 53, 24, 24))
	_rect(timer_label, Rect2(available - 280, 43, 120, 44))
	_rect(finish, Rect2(available - 142, 39, 126, 54))
	var compact := canvas.size.x < 1400
	var rail_width := 365.0 if (compact_rail_open if compact else rail_visible) else 0.0
	_rect(rail, Rect2(canvas.size.x - rail_width, header_height, rail_width, canvas.size.y - header_height))
	rail.visible = rail_width > 0
	_rect(number_scroll, Rect2(32, 88, 318, maxf(150, rail.size.y - 244)))
	_rect(quiz.jump_input, Rect2(32, rail.size.y - 144, 205, 48))
	_rect(quiz.jump_button, Rect2(245, rail.size.y - 144, 84, 48))
	_rect(rail.get_node("Legend"), Rect2(32, rail.size.y - 88, 310, 72))
	var left := sidebar_width + 36.0
	var right := canvas.size.x - (0.0 if compact else rail_width) - 36.0
	_rect(pane, Rect2(left, header_height, right - left, canvas.size.y - header_height))
	var show_numbers := pane.get_node_or_null("ShowNumbers")
	if show_numbers == null:
		show_numbers = _button(pane, "ShowNumbers", "题号列表", _toggle_rail)
	show_numbers.visible = rail_width == 0
	_rect(show_numbers, Rect2(pane.size.x - 130, 10, 130, 44))
	pane.get_node("MetaDivider").size.x = pane.size.x
	var footer_y := pane.size.y - 76
	_rect(quiz.question_scroll, Rect2(0, 82, pane.size.x, maxf(100, footer_y - 32 - 82)))
	_rect(footer_line, Rect2(0, footer_y - 16, pane.size.x, 1))
	_rect(quiz.prev_button, Rect2(0, footer_y, 166, 52))
	_rect(quiz.next_button, Rect2(184, footer_y, 176, 52))
	_rect(quiz.wrong_toggle, Rect2(pane.size.x - 198, footer_y, 198, 52))
	if pane.size.x < 700:
		_rect(quiz.prev_button, Rect2(0, footer_y, 140, 52))
		_rect(quiz.next_button, Rect2(154, footer_y, 140, 52))
	for picture in quiz.question_images.get_children():
		quiz._fit_question_image.call_deferred(picture)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F6 and event.pressed:
		# Handle before text fields, and ignore key repeat so holding F6 toggles once.
		get_viewport().set_input_as_handled()
		if not event.echo:
			_toggle_distraction_free()

func _toggle_distraction_free() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if not distraction_free:
		hidden_focus_path = NodePath()
		if focused != null and (sidebar.is_ancestor_of(focused) or header.is_ancestor_of(focused)):
			hidden_focus_path = canvas.get_path_to(focused)
			focused.release_focus()
	distraction_free = not distraction_free
	# Relayout existing controls; answers, drafts, timer and number-list state stay intact.
	_layout()
	if not distraction_free and not hidden_focus_path.is_empty():
		var previous := canvas.get_node_or_null(hidden_focus_path) as Control
		if previous != null and previous.is_visible_in_tree() and get_viewport().gui_get_focus_owner() == null:
			previous.grab_focus()
		hidden_focus_path = NodePath()

func _toggle_rail() -> void:
	if canvas.size.x < 1400:
		compact_rail_open = not compact_rail_open
	else:
		rail_visible = not rail_visible
	_layout()
	if rail.visible:
		_motion().enter(rail, Tokens.STATE)

func question_changed() -> void:
	# No fade of header, timer, rail, footer, or sidebar; answers are already installed.
	_motion().cancel(quiz.answer_label)
	quiz.answer_label.modulate.a = 1.0
	_motion().enter(quiz.question_scroll, Tokens.STATE)

func _sync_clock() -> void:
	if not is_inside_tree() or not is_instance_valid(clock_timer):
		return
	if _motion().suspended:
		clock_timer.stop()
	else:
		_update_timer()
		clock_timer.start()

func _update_timer() -> void:
	var seconds := (Time.get_ticks_msec() - start_msec) / 1000
	timer_label.text = "%02d:%02d:%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60]

func _finish_session() -> void:
	quiz._go_home()
