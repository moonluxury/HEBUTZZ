extends "res://scripts/minimal_page.gd"

const CONTENT_CATEGORIES := ["复习资料", "校园故事", "优秀文章"]
var entries: Array = []
var visible_entries: Array = []
var selected_category := "全部资源"
var query := ""
var search_edit: LineEdit
var back_button: Button
var list_root: Control
var tools_root: Control
var stats_root: Control
var divider: Control
var active_preview := ""
var results_height := 500.0
var submissions: Node

func _ready() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	active_nav = "KaiwuButton"
	for path in ["res://data/hegong_kaiwu.json", "res://data/hegong_kaiwu_demo.json"]:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			entries.append_array(parsed)
		elif parsed is Dictionary:
			entries.append_array(parsed.get("articles", parsed.get("items", [parsed] if parsed.has("title") else [])))
	super._ready()
	submissions = get_node("/root/AppServices").submission_store()
	submissions.changed.connect(_publication_changed)
	submissions.refresh_public()

func _publication_changed(reason: String) -> void:
	if reason != "public" or not is_inside_tree(): return
	entries = entries.filter(func(item: Dictionary): return not item.has("article_id"))
	for item in submissions.public_items:
		entries.append({"id":"article_" + str(item.id),"article_id":item.id,"title":item.data.title,"category":"优秀文章","type":"已发表文章","summary":item.data.get("course", ""),"keywords":item.data.get("tags", [])})
	for index in 4:
		var category: String = (["全部资源"] + CONTENT_CATEGORIES)[index]
		var count: int = entries.size() if index == 0 else entries.filter(func(entry: Dictionary): return entry.get("category", "") == category).size()
		stats_root.get_node("Stat%d" % index).get_child(1).text = str(count)
	_update_results()
	_layout()

func _refresh_cached_content() -> void:
	if is_instance_valid(submissions):
		_publication_changed("public")
		submissions.refresh_public()

func _build_content() -> void:
	back_button = sidebar.get_node("HomeButton")
	_label(body, "河工开物", TITLE_SIZE, text_color, Rect2(0, 25, 800, 55), true)
	_label(body, "优质学习资源，助力高效备考", BODY_SIZE, muted_color, Rect2(0, 89, 900, 42))
	search_edit = _search(body, "搜索课程、资料、知识点……", _search_changed, Rect2(0, 165, 1200, 62))
	search_edit.text = query
	for index in 4:
		var category: String = (["全部资源"] + CONTENT_CATEGORIES)[index]
		var tab := _button(body, "Category%d" % index, category, _select_category.bind(category))
		_rect(tab, Rect2(index * 160, 255, 138, 65))
		_tab(tab, category == selected_category, 138, 61)
	stats_root = _display_panel(body, "ResourceStats")
	for index in 4:
		var category: String = (["全部资源"] + CONTENT_CATEGORIES)[index]
		var count := entries.size() if index == 0 else entries.filter(func(entry: Dictionary): return entry.get("category", "") == category).size()
		var card := _display_panel(stats_root, "Stat%d" % index)
		_label(card, category, BODY_SIZE, muted_color, Rect2(0, 0, 220, 40))
		_label(card, str(count), 42, text_color, Rect2(0, 48, 180, 60), true)
		_label(card, "份", BODY_SIZE, text_color, Rect2(36 + str(count).length() * 20, 64, 50, 40))
		if index:
			_line(card, Rect2(-28, 5, 1, 94))
	_line(body, Rect2(0, 320, 1300, 1))
	divider = _line(body, Rect2())
	list_root = _display_panel(body, "ResourceList")
	tools_root = _display_panel(body, "LearningTools")
	_line(tools_root, Rect2(-36, 0, 1, 480))
	_label(tools_root, "资源分类", SECTION_SIZE, text_color, Rect2(0, 0, 400, 50), true)
	for index in 3:
		var b := _button(tools_root, "Tool%d" % index, CONTENT_CATEGORIES[index], _select_category.bind(CONTENT_CATEGORIES[index]))
		b.icon = _texture("res://assets/minimal/icons/%s.png" % ["book-open", "network", "file-text"][index])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rect(b, Rect2(0, 72 + index * 80, 270, 50))
	var announcements: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/hegong_announcements.json"))
	for index in announcements.size():
		var entry: Dictionary = announcements[index]
		var b := _button(tools_root, "Announcement%d" % index, entry.title, _open_article.bind(entry))
		b.icon = _texture("res://assets/minimal/icons/megaphone.png")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rect(b, Rect2(0, 340 + index * 60, 270, 50))
	_update_results()

func _search_changed(value: String) -> void:
	query = value
	_update_results()
	_layout()
	_motion().enter(list_root, Tokens.HOVER)

func _select_category(category: String) -> void:
	selected_category = category
	for index in 4:
		var tab: Button = body.get_node("Category%d" % index)
		_tab(tab, tab.text == category, 138, 61, true)
	_update_results()
	_layout()
	_motion().enter(list_root, Tokens.HOVER)

func _update_results() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var focus_path := list_root.get_path_to(focused) if focused != null and list_root.is_ancestor_of(focused) else NodePath()
	for child in list_root.get_children():
		list_root.remove_child(child)
		child.queue_free()
	_label(list_root, "推荐资源" if query.is_empty() else "搜索结果", SECTION_SIZE, text_color, Rect2(0, 0, 320, 50), true)
	visible_entries.clear()
	for entry in entries:
		if selected_category != "全部资源" and entry.get("category", "") != selected_category:
			continue
		var searchable := " ".join([str(entry.get("title", "")), str(entry.get("category", "")), str(entry.get("summary", "")), str(entry.get("content", "")), str(entry.get("keywords", [])), str(entry.get("preview", ""))]).to_lower()
		if not query.strip_edges().is_empty() and not searchable.contains(query.strip_edges().to_lower()):
			continue
		visible_entries.append(entry)
	var y := 74.0
	for index in visible_entries.size():
		var entry: Dictionary = visible_entries[index]
		var row := _display_panel(list_root, "Result_%s" % str(entry.get("id", entry.get("title", index))).validate_node_name())
		_rect(row, Rect2(0, y, 800, 104))
		_icon(row, "file-text", Rect2(0, 16, 36, 40), muted_color)
		var open := _button(row, "Title", str(entry.get("title", "未命名内容")), _open_entry.bind(entry))
		open.focus_mode = Control.FOCUS_NONE
		open.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open.add_theme_font_override("font", bold_font)
		_rect(open, Rect2(60, 6, 550, 44))
		_label(row, "%s · %s%s" % [entry.get("category", ""), entry.get("type", "资料"), " · 示例" if entry.get("demo", false) else ""], 20, muted_color, Rect2(60, 56, 600, 36)).name = "Meta"
		var action := _button(row, "Open", "查看", _open_entry.bind(entry))
		action.focus_mode = Control.FOCUS_NONE
		action.icon = _texture("res://assets/minimal/icons/arrow-right.png")
		action.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		action.add_theme_color_override("font_color", _accent())
		action.add_theme_color_override("icon_normal_color", _accent())
		var expanded: bool = entry.get("demo", false) and active_preview == str(entry.get("id", ""))
		if expanded:
			var preview := _label(row, str(entry.get("summary", "")) + "\n" + str(entry.get("preview", "")), 20, muted_color, Rect2(60, 105, 600, 125))
			preview.name = "Preview"
			preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.size.y = 254
		_line(row, Rect2(0, row.size.y - 1, 800, 1)).name = "Line"
		_motion().bind_panel.call_deferred(row)
		y += row.size.y
	if visible_entries.is_empty():
		_label(list_root, "暂无相关资源", BODY_SIZE, muted_color, Rect2(0, 100, 600, 56))
		var clear := _button(list_root, "ClearFilters", "查看全部资源", _clear_filters)
		_rect(clear, Rect2(0, 170, 200, 50))
	results_height = maxf(250, y)
	content_height = maxf(930, 600 + results_height)
	if not focus_path.is_empty() and list_root.has_node(focus_path):
		list_root.get_node(focus_path).grab_focus()

func _clear_filters() -> void:
	query = ""
	search_edit.text = ""
	_select_category("全部资源")

func _open_entry(entry: Dictionary) -> void:
	if entry.has("article_id"):
		var response: Dictionary = await submissions.open_article(str(entry.article_id))
		if response.get("ok", false): _go("res://scenes/SubmissionArticle.tscn")
	elif entry.get("demo", false):
		active_preview = "" if active_preview == str(entry.get("id", "")) else str(entry.get("id", ""))
		_update_results()
		_layout()
		for row in list_root.find_children("Result*", "Panel", false, false):
			if row.has_node("Preview"):
				_motion().enter(row.get_node("Preview"), Tokens.PANEL)
	else:
		_open_article(entry)

func _open_article(entry: Dictionary) -> void:
	_app().hegong_kaiwu_article = entry
	_go("res://scenes/HegongKaiwuDetail.tscn")

func consume_back_action() -> bool:
	if active_preview.is_empty() or list_root.find_child("Preview", true, false) == null:
		return false
	active_preview = ""
	_update_results()
	_layout()
	return true

func _layout_content(width: float) -> void:
	_rect(search_edit, Rect2(0, 165, width, 62))
	_rect(stats_root, Rect2(0, 355, width, 120))
	for index in 4:
		_rect(stats_root.get_node("Stat%d" % index), Rect2(index * width / 4, 0, width / 4 - 28, 120))
	_rect(divider, Rect2(0, 495, width, 1))
	var compact := width < 1000
	var left_width := width if compact else width - 390
	_rect(list_root, Rect2(0, 530, left_width, results_height))
	_rect(tools_root, Rect2(0 if compact else left_width + 76, 580 + results_height if compact else 530, 265, 480))
	content_height = 1100 + results_height if compact else maxf(930, 600 + results_height)
	for row in list_root.find_children("Result*", "Panel", false, false):
		row.size.x = left_width
		row.get_node("Title").size.x = left_width - 180
		row.get_node("Meta").size.x = left_width - 70
		_rect(row.get_node("Open"), Rect2(left_width - 100, 14, 100, 45))
		row.get_node("Line").size.x = left_width
		if row.has_node("Preview"):
			row.get_node("Preview").size.x = left_width - 70
