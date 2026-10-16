extends VBoxContainer

signal category_selected(category: String)
signal entry_opened(entry: Dictionary)
signal filters_cleared

var result_entries: Array[Dictionary] = []
var category_names: Array[String] = []
var category_counts: Dictionary = {}
var active_category := ""
var is_dark := false
var font_scale := 1.0
var result_count: Label
var sort_select: OptionButton
var filter_column: VBoxContainer
var results_column: VBoxContainer
var results_scroll: ScrollContainer
var filter_buttons: Array[Button] = []
var expanded_entries: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 20)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 16)
	add_child(toolbar)
	result_count = _label("", 28, "text")
	result_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(result_count)
	toolbar.add_child(_label("排序", 22, "muted"))
	sort_select = OptionButton.new()
	sort_select.add_item("推荐顺序")
	sort_select.add_item("标题名称")
	sort_select.set_meta("result_font_size", 22)
	sort_select.set_meta("result_role", "sort")
	sort_select.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sort_select.item_selected.connect(func(_index: int) -> void: _render_results())
	toolbar.add_child(sort_select)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var filters_scroll := ScrollContainer.new()
	filters_scroll.custom_minimum_size.x = 250
	filters_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(filters_scroll)
	filter_column = VBoxContainer.new()
	filter_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_column.add_theme_constant_override("separation", 12)
	filters_scroll.add_child(filter_column)
	var separator := VSeparator.new()
	separator.set_meta("result_role", "divider")
	body.add_child(separator)
	results_scroll = ScrollContainer.new()
	results_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(results_scroll)
	results_column = VBoxContainer.new()
	results_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_column.add_theme_constant_override("separation", 0)
	results_scroll.add_child(results_column)


func configure_categories(all_entries: Array[Dictionary], names: Array[String]) -> void:
	category_names = names.duplicate()
	_update_category_counts(all_entries)
	_render_filters()


func _update_category_counts(matching_entries: Array[Dictionary]) -> void:
	category_counts.clear()
	category_counts[""] = matching_entries.size()
	for entry in matching_entries:
		var category := str(entry.get("category", ""))
		category_counts[category] = int(category_counts.get(category, 0)) + 1


func show_results(items: Array[Dictionary], category: String, matching_entries: Array[Dictionary]) -> void:
	result_entries = items.duplicate()
	active_category = category
	_update_category_counts(matching_entries)
	expanded_entries.clear()
	_render_filters()
	_render_results()


func set_appearance(dark: bool, scale_value: float) -> void:
	is_dark = dark
	font_scale = clampf(scale_value, 0.7, 1.17)
	_apply_appearance(self)


func _render_filters() -> void:
	_clear_children(filter_column)
	filter_buttons.clear()
	filter_column.add_child(_label("内容类型", 25, "text"))
	for category in [""] + category_names:
		var caption := "全部类型" if str(category).is_empty() else str(category)
		var button := Button.new()
		button.text = "%s  ·  %d" % [caption, int(category_counts.get(category, 0))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 52
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.set_meta("result_font_size", 23)
		button.set_meta("result_role", "filter")
		button.set_meta("selected", str(category) == active_category)
		button.pressed.connect(func() -> void: category_selected.emit(str(category)))
		filter_column.add_child(button)
		filter_buttons.append(button)
	var divider := HSeparator.new()
	divider.set_meta("result_role", "divider")
	filter_column.add_child(divider)
	var note := _label("按内容类型筛选\n也可输入关键词检索", 21, "muted")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	filter_column.add_child(note)
	var reset := _link_button("清除筛选", 22)
	reset.pressed.connect(func() -> void: filters_cleared.emit())
	filter_column.add_child(reset)
	_apply_appearance(filter_column)


func _render_results() -> void:
	_clear_children(results_column)
	var sorted_entries := result_entries.duplicate()
	if sort_select.selected == 1:
		sorted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0
		)
	result_count.text = "%d 条结果" % sorted_entries.size()
	if sorted_entries.is_empty():
		var empty := VBoxContainer.new()
		empty.add_theme_constant_override("separation", 20)
		results_column.add_child(empty)
		empty.add_child(_label("暂未找到相关内容", 30, "text"))
		var hint := _label("当前类型下暂无匹配内容，可以更换关键词或清除筛选查看全部内容。", 24, "muted")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_child(hint)
		var reset := _link_button("查看全部内容", 25)
		reset.pressed.connect(func() -> void: filters_cleared.emit())
		empty.add_child(reset)
	for index in sorted_entries.size():
		_add_result(sorted_entries[index], index)
	results_scroll.scroll_vertical = 0
	_apply_appearance(self)


func _add_result(entry: Dictionary, index: int) -> void:
	var row := MarginContainer.new()
	row.name = "Result%d" % index
	row.add_theme_constant_override("margin_top", 12)
	row.add_theme_constant_override("margin_bottom", 16)
	row.add_theme_constant_override("margin_right", 16)
	results_column.add_child(row)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	row.add_child(column)
	var demo := bool(entry.get("demo", false))
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 14)
	column.add_child(heading)
	heading.add_child(_label("%02d" % [index + 1], 22, "muted"))
	var meta := str(entry.get("category", "校园内容"))
	var title := _link_button(str(entry.get("title", "未命名内容")), 33)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(title)
	heading.add_child(_label(meta, 21, "muted"))
	var author_name := str(entry.get("author", "匿名")).strip_edges()
	var author := _label("作者：%s" % ("匿名" if author_name.is_empty() else author_name), 24, "text")
	author.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(author)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	var keywords: Array = entry.get("keywords", [])
	if not keywords.is_empty():
		var tags := _label("关键词：" + "  /  ".join(keywords), 21, "muted")
		tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tags.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		actions.add_child(tags)
	var action := _link_button("展开预览" if demo else "阅读全文", 22)
	action.size_flags_horizontal = Control.SIZE_SHRINK_END
	actions.add_child(action)
	if demo:
		var preview := PanelContainer.new()
		preview.name = "Preview"
		preview.set_meta("result_role", "preview")
		preview.visible = expanded_entries.has(str(entry.get("id", title.text)))
		column.add_child(preview)
		var preview_text := _label(str(entry.get("preview", "")) + "\n仅作检索界面展示，暂无课程资料。", 23, "text")
		preview_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.add_child(preview_text)
		action.text = "收起预览" if preview.visible else "展开预览"
		var toggle_preview := func() -> void:
			preview.visible = not preview.visible
			action.text = "收起预览" if preview.visible else "展开预览"
			var entry_id := str(entry.get("id", title.text))
			if preview.visible:
				expanded_entries[entry_id] = true
			else:
				expanded_entries.erase(entry_id)
		title.pressed.connect(toggle_preview)
		action.pressed.connect(toggle_preview)
	else:
		title.pressed.connect(func() -> void: entry_opened.emit(entry))
		action.pressed.connect(func() -> void: entry_opened.emit(entry))
	var divider := HSeparator.new()
	divider.set_meta("result_role", "divider")
	results_column.add_child(divider)


func _label(caption: String, point_size: int, role: String) -> Label:
	var label := Label.new()
	label.text = caption
	label.set_meta("result_font_size", point_size)
	label.set_meta("result_role", role)
	return label


func _link_button(caption: String, point_size: int) -> Button:
	var button := Button.new()
	button.text = caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("result_font_size", point_size)
	button.set_meta("result_role", "link")
	return button


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _apply_appearance(node: Node) -> void:
	var accent := Color("#8FAEFF") if is_dark else Color("#092C87")
	var ink := Color("#E8EEF8") if is_dark else Color("#11203A")
	var muted := Color("#A6B4CA") if is_dark else Color("#66738A")
	var border := Color("#2C3D59") if is_dark else Color("#DDE5F1")
	var tint := Color("#21375B") if is_dark else Color("#EEF3FF")
	if node is Control:
		var control := node as Control
		if control.has_meta("result_font_size"):
			control.add_theme_font_size_override("font_size", roundi(float(control.get_meta("result_font_size")) * font_scale))
		var role := str(control.get_meta("result_role", ""))
		if control is Label:
			control.add_theme_color_override("font_color", muted if role == "muted" else ink)
		elif control is Button:
			var selected := bool(control.get_meta("selected", false))
			var color := accent if role == "link" or selected else ink
			for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				control.add_theme_color_override(state, color)
			control.add_theme_stylebox_override("normal", _style(tint if selected else Color.TRANSPARENT, Color.TRANSPARENT, role != "link"))
			control.add_theme_stylebox_override("hover", _style(tint, Color.TRANSPARENT, role != "link"))
			control.add_theme_stylebox_override("pressed", _style(tint, accent, role != "link"))
			control.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, accent, role != "link"))
			if control is OptionButton:
				control.add_theme_color_override("font_color", accent)
				control.get_popup().add_theme_font_size_override("font_size", roundi(22 * font_scale))
		elif role == "divider":
			var line := StyleBoxLine.new()
			line.color = border
			line.thickness = 1
			line.vertical = control is VSeparator
			control.add_theme_stylebox_override("separator", line)
		elif role == "preview":
			control.add_theme_stylebox_override("panel", _style(tint, border, true))
	for child in node.get_children():
		_apply_appearance(child)


func _style(background: Color, border: Color, padded: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12 if padded else 0
	style.content_margin_right = 24 if padded else 0
	style.content_margin_top = 8 if padded else 2
	style.content_margin_bottom = 8 if padded else 2
	return style
