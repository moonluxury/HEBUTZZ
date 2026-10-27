extends "res://scripts/minimal_page.gd"

const Chart = preload("res://scripts/workbench_chart.gd")
const SHORT_TITLES := {"marxism": "马克思主义原理", "mao": "毛泽东思想和\n中国特色社会主义", "xi": "习近平新时代\n中国特色社会主义思想概论", "matlab": "MATLAB", "python": "Python", "cpp": "C++"}
const COURSE_LABELS := {"marxism": "马克思主义原理", "mao": "毛泽东思想概论", "xi": "习近平新时代思想概论", "matlab": "MATLAB", "python": "Python", "cpp": "C++"}
const COURSE_ICONS := {"marxism": "book-text", "mao": "book-open", "xi": "notebook-pen", "matlab": "chart-no-axes-column-increasing", "python": "brand-python", "cpp": "cpu"}
var marxism_button: Button
var mao_button: Button
var xi_button: Button
var matlab_button: Button
var python_button: Button
var cpp_button: Button
var back_button: Button
var title_label: Label
var wrong_count_labels: Dictionary = {}
var cards: Array[Control] = []
var search_edit: LineEdit
var category := "全部课程"
var query := ""
var cards_root: Control
var tabs_root: Control
var summary_label: Label
var wrongs: Dictionary = {}
var wrong_subject := "全部科目"
var wrong_filter := "全部错题"
var progress_filter := 0
var filter_button: MenuButton
var review_section: Control
var review_button: Button
var wrong_chart: Control
var distribution: Control
var stats_row: Control
var page_mode := "all"
var data_dirty := false
var shown_date := ""

func _ready() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	page_mode = _app().quiz_mode
	active_nav = "WrongButton" if page_mode == "wrong" else "AllButton"
	super._ready()
	_stats().changed.connect(func(): data_dirty = true)

func _refresh_cached_content() -> void:
	if not data_dirty and shown_date == Time.get_date_string_from_system():
		return
	data_dirty = false
	shown_date = Time.get_date_string_from_system()
	if page_mode == "wrong":
		_load_wrongs()
		_refresh_wrong_region(true)
	else:
		_refresh_courses()

func _build_content() -> void:
	data_dirty = false
	shown_date = Time.get_date_string_from_system()
	cards.clear()
	wrong_count_labels.clear()
	back_button = sidebar.get_node("HomeButton")
	title_label = _label(body, "错题库" if page_mode == "wrong" else "总题库", TITLE_SIZE, text_color, Rect2(0, 0, 500, 55), true)
	if page_mode == "wrong":
		_build_wrong()
	else:
		_build_bank()

func _build_bank() -> void:
	_label(body, "共 6 门课程 · %s 道题" % _number(_stats().summary().total), BODY_SIZE, muted_color, Rect2(0, 62, 800, 40))
	search_edit = _search(body, "搜索课程、知识点或题目", _search_changed, Rect2(0, 129, 1050, 60))
	search_edit.text = query
	filter_button = MenuButton.new()
	filter_button.flat = false
	filter_button.text = "筛选"
	filter_button.icon = _texture("res://assets/minimal/icons/sliders-horizontal.png")
	_style_choice(filter_button)
	body.add_child(filter_button)
	for caption in ["全部进度", "尚未开始", "学习中", "已完成"]:
		filter_button.get_popup().add_item(caption)
	# Measure the menu with its final font and padding during page layout.
	_motion().bind_popup(filter_button.get_popup(), filter_button)
	filter_button.get_popup().visibility_changed.connect(_align_filter_popup)
	filter_button.get_popup().id_pressed.connect(func(id: int):
		progress_filter = id
		_refresh_courses()
	)
	_line(body, Rect2(0, 279, 1300, 1))
	tabs_root = Control.new()
	body.add_child(tabs_root)
	for index in 3:
		var value: String = ["全部课程", "公共基础", "计算机类"][index]
		var tab := _button(tabs_root, "Category%d" % index, value, _select_category.bind(value))
		_rect(tab, Rect2(index * 148, 0, 120, 54))
		_tab(tab, category == value, 120, 52)
	cards_root = Control.new()
	body.add_child(cards_root)
	summary_label = _label(body, "", 20, muted_color)
	_populate_courses()

func _align_filter_popup() -> void:
	var popup := filter_button.get_popup()
	if not popup.visible:
		return
	# PopupMenu finalizes its scale before becoming visible. Match both edges
	# in its screen coordinates, including canvas/window scale and pixel rounding.
	var transform := filter_button.get_screen_transform()
	var left := roundi(transform.origin.x)
	var right := roundi((transform * Vector2(filter_button.size.x, 0)).x)
	popup.size.x = right - left
	popup.position.x = left

func _search_changed(value: String) -> void:
	query = value
	_refresh_courses()

func _select_category(value: String) -> void:
	category = value
	for tab in tabs_root.get_children():
		_tab(tab, tab.text == value, 120, 52, true)
	_refresh_courses()

func _refresh_courses() -> void:
	_populate_courses()
	_layout()
	_motion().enter(cards_root, Tokens.HOVER)

func _matching_index(subject: String) -> int:
	if query.strip_edges().is_empty():
		var target: Dictionary = _stats().resume_target()
		if target.get("subject", "") == subject:
			return int(target.index)
		var questions: Array = _stats().banks[subject]
		for index in questions.size():
			if not _stats().learned.has("%s:%s" % [subject, questions[index].id]):
				return index
		return 0
	if str(_app().SUBJECTS[subject].title).to_lower().contains(query.to_lower()):
		return 0
	var bank: Array = _stats().banks[subject]
	for index in bank.size():
		if str(bank[index].get("stem", "")).to_lower().contains(query.to_lower()):
			return index
	return -1

func _populate_courses() -> void:
	for child in cards_root.get_children():
		cards_root.remove_child(child)
		child.queue_free()
	cards.clear()
	for subject in _app().SUBJECTS:
		var computer: bool = subject in ["matlab", "python", "cpp"]
		if category == "计算机类" and not computer or category == "公共基础" and computer:
			continue
		var subject_total: int = _stats().banks[subject].size()
		var subject_learned: int = _stats().subject_learned(subject)
		if progress_filter == 1 and subject_learned > 0 or progress_filter == 2 and (subject_learned == 0 or subject_learned >= subject_total) or progress_filter == 3 and subject_learned < subject_total:
			continue
		var match_index := _matching_index(subject)
		if match_index < 0:
			continue
		_course_card(subject, subject_total, subject_learned, _select_subject.bind(subject, match_index))
	summary_label.text = "已显示 %d 门课程" % cards.size() if cards.size() else "没有找到相关课程或题目"

func _course_card(subject: String, total: int, learned: int, action: Callable, wrong := false) -> void:
	# Both banks use the same card composition, spacing and interaction styles.
	var card := _display_panel(cards_root, subject, surface)
	card.add_theme_stylebox_override("panel", _style(surface, 12, border))
	_icon(card, COURSE_ICONS[subject], Rect2(24, 27, 38, 38), BLUE if subject == "marxism" else muted_color)
	_label(card, SHORT_TITLES[subject], 24, text_color, Rect2(82, 16, 280, 82), true).name = "CourseTitle"
	_label(card, ("共 %s 道错题" if wrong else "共 %s 道题") % _number(total), 20, muted_color, Rect2(24, 111, 280, 36)).name = "QuestionCount"
	var ratio := 100.0 * learned / maxi(1, total)
	_bar(card, ratio, Rect2(24, 160, 250, 6)).name = "Progress"
	_label(card, _percent(ratio) + "%", 20, muted_color).name = "Percent"
	var caption := ("继续复习" if learned else "开始复习") if wrong else ("继续学习" if learned else "开始学习")
	var b := _button(card, "CourseAction", caption, action)
	b.accessibility_name = "%s，%s，共 %d 道%s，已练习 %d 道" % [caption, COURSE_LABELS[subject], total, "错题" if wrong else "题", learned]
	b.icon = _texture("res://assets/minimal/icons/arrow-right.png")
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_theme_color_override("font_color", _accent())
	b.add_theme_color_override("icon_normal_color", _accent())
	set(subject + "_button", b)
	cards.append(card)
	_motion().bind_panel.call_deferred(card)

func _load_wrongs() -> void:
	wrongs.clear()
	for subject in _app().SUBJECTS:
		var path: String = _app().SUBJECTS[subject].wrong_path
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else []
		var ids: Array = parsed if parsed is Array else []
		wrongs[subject] = []
		for question in _stats().banks[subject]:
			if question.id in ids or str(question.id) in ids:
				wrongs[subject].append(question)

func _build_wrong() -> void:
	_load_wrongs()
	_label(body, "复习薄弱知识，巩固每一次进步。", BODY_SIZE, muted_color, Rect2(0, 62, 800, 40))
	review_button = _primary(body, "开始复习", _start_review, Rect2(1030, 60, 200, 54))
	review_button.icon = _texture("res://assets/minimal/icons/arrow-right.png")
	review_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs_root = Control.new()
	body.add_child(tabs_root)
	for index in 3:
		var value: String = ["全部错题", "未练习", "已练习"][index]
		var tab := _button(tabs_root, "Filter%d" % index, value, _select_wrong_filter.bind(value))
		_tab(tab, value == wrong_filter, 116, 47)
		_rect(tab, Rect2(index * 128, 0, 116, 50))
	var select := OptionButton.new()
	select.name = "SubjectFilter"
	for value in ["全部科目", "马克思主义原理", "毛泽东思想概论", "习近平新时代思想概论", "MATLAB", "Python", "C++"]:
		select.add_item(value)
	select.selected = 0 if wrong_subject == "全部科目" else _app().SUBJECTS.keys().find(wrong_subject) + 1
	# Keep OptionButton selection behavior without the menu's radio-circle column.
	for index in select.item_count:
		select.get_popup().set_item_as_radio_checkable(index, false)
	_style_choice(select)
	select.item_selected.connect(func(index: int):
		wrong_subject = "全部科目" if index == 0 else _app().SUBJECTS.keys()[index - 1]
		_refresh_wrong_region(true)
	)
	body.add_child(select)
	_build_wrong_regions()

func _build_wrong_regions() -> void:
	var total := 0
	var reviewed := 0
	for subject in wrongs:
		if wrong_subject != "全部科目" and subject != wrong_subject:
			continue
		total += wrongs[subject].size()
		for question in wrongs[subject]:
			if _stats().learned.has("%s:%s" % [subject, question.id]):
				reviewed += 1
	stats_row = _display_panel(body, "WrongStats")
	var stats := [["错题总数", str(total), "题"], ["未练习", str(total - reviewed), "题"], ["已练习", str(reviewed), "题"], ["复习进度", _percent(100.0 * reviewed / maxi(1, total)), "%"]]
	for index in 4:
		var item := _display_panel(stats_row, "Stat%d" % index)
		_label(item, stats[index][0], BODY_SIZE, muted_color, Rect2(0, 0, 180, 40))
		_label(item, stats[index][1], 42, text_color, Rect2(0, 44, 240, 56), true)
		var extent := bold_font.get_string_size(stats[index][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
		_label(item, stats[index][2], BODY_SIZE, muted_color, Rect2(extent + 8, 58, 40, 38))
		if index:
			_line(item, Rect2(-28, 8, 1, 86))
	if not body.has_node("StatsDivider"):
		_line(body, Rect2(0, 340, 1300, 1)).name = "StatsDivider"
	if not is_instance_valid(wrong_chart) or not wrong_chart.is_inside_tree():
		wrong_chart = _display_panel(body, "WrongTrend")
		_label(wrong_chart, "错题趋势", SECTION_SIZE, text_color, Rect2(0, 0, 300, 48), true)
		_label(wrong_chart, "近 7 天答错次数", 20, muted_color, Rect2(350, 7, 300, 36)).name = "Period"
		var chart := Chart.new()
		chart.name = "Chart"
		chart.empty_message = "暂无答错记录"
		chart.dark = dark
		chart.days = _stats().recent_wrong_days("" if wrong_subject == "全部科目" else wrong_subject)
		wrong_chart.add_child(chart)
	else:
		var chart: Control = wrong_chart.get_node("Chart")
		var days: Array = _stats().recent_wrong_days("" if wrong_subject == "全部科目" else wrong_subject)
		if chart.days == days:
			chart.reveal.restart()
		else:
			chart.days = days
	wrong_chart.get_node("Period").text = "近 7 天 · 已归属科目记录" if wrong_subject != "全部科目" and _stats().has_unattributed_wrongs() else "近 7 天答错次数"
	distribution = _display_panel(body, "CourseDistribution")
	_line(distribution, Rect2(-30, 0, 1, 270))
	_label(distribution, "课程分布", SECTION_SIZE, text_color, Rect2(0, 0, 300, 48), true)
	var index := 0
	for subject in wrongs:
		if wrong_subject != "全部科目" and subject != wrong_subject:
			continue
		var row := _button(distribution, subject, "", _select_subject.bind(subject))
		_label(row, COURSE_LABELS[subject], 20, muted_color, Rect2(0, 0, 210, 36))
		var count := _label(row, "%d 道" % wrongs[subject].size(), 20, BLUE)
		count.name = "Count"
		wrong_count_labels[subject] = count
		_bar(row, 100.0 * wrongs[subject].size() / maxi(1, total), Rect2(200, 15, 180, 8)).name = "Bar"
		set(subject + "_button", row)
		_rect(row, Rect2(0, 52 + index * 36, 420, 36))
		index += 1
	_build_wrong_courses()

func _build_wrong_courses() -> void:
	review_section = _display_panel(body, "WrongCourses")
	_label(review_section, "待复习错题", SECTION_SIZE, text_color, Rect2(0, 0, 400, 48), true)
	cards_root = Control.new()
	cards_root.name = "CourseCards"
	review_section.add_child(cards_root)
	cards.clear()
	var rows := _filtered_wrong_rows()
	review_button.disabled = rows.is_empty()
	var first_matches: Dictionary = {}
	for entry in rows:
		if not first_matches.has(entry.subject):
			first_matches[entry.subject] = int(entry.question.id)
	for subject in first_matches:
		var reviewed := 0
		for question in wrongs[subject]:
			if _stats().learned.has("%s:%s" % [subject, question.id]):
				reviewed += 1
		_course_card(subject, wrongs[subject].size(), reviewed, _open_wrong.bind(subject, first_matches[subject]), true)
	if rows.is_empty():
		_label(cards_root, "暂无符合条件的错题科目", BODY_SIZE, muted_color, Rect2(0, 24, 600, 56)).name = "EmptyState"

func _filtered_wrong_rows() -> Array:
	var rows: Array = []
	for subject in wrongs:
		if wrong_subject != "全部科目" and subject != wrong_subject:
			continue
		for question in wrongs[subject]:
			var learned: bool = _stats().learned.has("%s:%s" % [subject, question.id])
			if wrong_filter == "未练习" and learned or wrong_filter == "已练习" and not learned:
				continue
			rows.append({"subject": subject, "question": question})
	return rows

func _select_wrong_filter(value: String) -> void:
	wrong_filter = value
	for tab in tabs_root.get_children():
		_tab(tab, tab.text == value, 116, 47, true)
	_refresh_wrong_region()

func _refresh_wrong_region(subject_changed := false) -> void:
	var saved_scroll := scroll.scroll_vertical
	var focused := get_viewport().gui_get_focus_owner()
	var focus_path := review_section.get_path_to(focused) if focused != null and review_section.is_ancestor_of(focused) else NodePath()
	for region in [stats_row, distribution, review_section] if subject_changed else [review_section]:
		body.remove_child(region)
		region.queue_free()
	if subject_changed:
		wrong_count_labels.clear()
		_build_wrong_regions()
	else:
		_build_wrong_courses()
	_layout()
	scroll.set_deferred("scroll_vertical", saved_scroll)
	_motion().enter(cards_root, Tokens.HOVER)
	if not focus_path.is_empty() and review_section.has_node(focus_path):
		review_section.get_node(focus_path).grab_focus()

func _open_wrong(subject: String, id: int) -> void:
	for index in wrongs[subject].size():
		if int(wrongs[subject][index].id) == id:
			_select_subject(subject, index)
			return

func _start_review() -> void:
	var rows := _filtered_wrong_rows()
	if not rows.is_empty():
		_open_wrong(rows[0].subject, int(rows[0].question.id))

func _select_subject(subject_id: String, index: int = 0) -> void:
	_app().quiz_mode = page_mode
	_app().subject_id = subject_id
	_app().start_index = index
	_go("res://scenes/Quiz.tscn")

func _layout_content(width: float) -> void:
	if page_mode == "all":
		# Keep the trigger and menu equally wide without clipping menu text.
		var filter_width := maxf(142.0, filter_button.get_popup().get_contents_minimum_size().x)
		_rect(search_edit, Rect2(0, 129, width - filter_width - 24, 60))
		_rect(filter_button, Rect2(width - filter_width, 129, filter_width, 60))
		_rect(tabs_root, Rect2(0, 223, width, 58))
		var grid_height := _layout_course_cards(width)
		_rect(cards_root, Rect2(0, 316, width, grid_height))
		content_height = 350 + grid_height
		_rect(summary_label, Rect2(0, content_height - 10, width, 50))
		content_height += 50
	else:
		_rect(review_button, Rect2(width - 200, 60, 200, 54))
		_rect(tabs_root, Rect2(0, 152, 450, 50))
		_rect(body.get_node("SubjectFilter"), Rect2(width - 320, 152, 320, 50))
		_rect(stats_row, Rect2(0, 228, width, 110))
		for index in 4:
			_rect(stats_row.get_node("Stat%d" % index), Rect2(index * width / 4, 0, width / 4 - 28, 110))
		var compact := width < 1000
		var chart_width := width if compact else width * 0.57
		_rect(wrong_chart, Rect2(0, 365, chart_width, 290))
		_rect(wrong_chart.get_node("Chart"), Rect2(0, 60, chart_width, 220))
		_rect(distribution, Rect2(0 if compact else chart_width + 55, 680 if compact else 365, width if compact else width - chart_width - 55, 290))
		for subject in wrongs:
			var row: Control = distribution.get_node_or_null(subject)
			if row == null:
				continue
			row.size.x = distribution.size.x
			_rect(row.get_node("Count"), Rect2(row.size.x - 74, 0, 74, 36))
			_rect(row.get_node("Bar"), Rect2(220, 15, maxf(50, row.size.x - 305), 8))
		var section_y := 1010.0 if compact else 658.0
		var grid_height := maxf(120, _layout_course_cards(width))
		_rect(review_section, Rect2(0, section_y, width, 74 + grid_height))
		_rect(cards_root, Rect2(0, 74, width, grid_height))
		content_height = section_y + 74 + grid_height + 32

func _layout_course_cards(width: float) -> float:
	var columns := 2 if width < 1050 else 3
	var card_width := (width - (columns - 1) * 24) / columns
	var tall := card_width < 370
	var stride := 292 if tall else 258
	for index in cards.size():
		var card: Control = cards[index]
		_rect(card, Rect2((index % columns) * (card_width + 24), (index / columns) * stride, card_width, 268 if tall else 234))
		card.get_node("CourseTitle").size.x = card_width - 96
		card.get_node("CourseTitle").size.y = 112 if tall else 82
		card.get_node("CourseTitle").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.get_node("QuestionCount").position.y = 141 if tall else 111
		_rect(card.get_node("Progress"), Rect2(24, 194 if tall else 160, card_width - 110, 6))
		_rect(card.get_node("Percent"), Rect2(card_width - 70, 178 if tall else 144, 60, 36))
		_rect(card.get_node("CourseAction"), Rect2(card_width - 176, 218 if tall else 184, 152, 42))
	return ceili(float(cards.size()) / columns) * stride
