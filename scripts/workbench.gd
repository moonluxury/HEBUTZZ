extends "res://scripts/minimal_page.gd"

const Chart = preload("res://scripts/workbench_chart.gd")
var data: Dictionary
var hero: Panel
var stat_cards: Array[Panel] = []
var trend: Button
var distribution: Panel
var trend_chart: Control
var separator: Control
var divider: Control
var detail_return_focus: WeakRef
var reward_store: Node
var reward_notice: Label

func _ready() -> void:
	reward_store = get_node("/root/AppServices").practice_rewards()
	super._ready()
	_stats().changed.connect(_refresh_data)
	reward_store.changed.connect(_refresh_rewards)

func _build_content() -> void:
	data = _stats().summary()
	stat_cards.clear()
	_label(body, "工作台", TITLE_SIZE, text_color, Rect2(0, 0, 300, 55), true)
	hero = _display_panel(body, "StudyHero")
	_label(hero, "让每一次练习，都有收获", 42, text_color, Rect2(0, 0, 1000, 68), true)
	reward_notice = _label(hero, "坚持学习，遇见更好的自己", 24, muted_color, Rect2(0, 77, 950, 44))
	_refresh_rewards()
	var items := [
		["TodayCard", "今日学习", str(data.today), "题"],
		["ProgressCard", "学习进度", _percent(float(data.percent)), "%"],
		["DaysCard", "累计学习", str(data.days), "天"],
		["TotalCard", "题库总数", _number(data.total), "题"],
	]
	for index in items.size():
		var item: Array = items[index]
		var card := _display_panel(body, item[0])
		_label(card, item[1], BODY_SIZE, muted_color, Rect2(0, 0, 210, 36))
		var value := _label(card, item[2], 42, text_color, Rect2(0, 43, 240, 60), true)
		value.name = "Value"
		var extent := bold_font.get_string_size(item[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
		_label(card, item[3], 22, text_color, Rect2(extent + 8, 57, 36, 38))
		card.get_child(-1).name = "Unit"
		if index == 1:
			_bar(card, data.percent, Rect2(0, 111, 200, 6)).name = "Progress"
		if index > 0:
			_line(card, Rect2(-32, 6, 1, 92))
		stat_cards.append(card)
	separator = _line(body, Rect2())
	trend = _button(body, "TrendCard", "", _show_history)
	trend.focus_mode = Control.FOCUS_NONE
	_label(trend, "学习趋势", SECTION_SIZE, text_color, Rect2(0, 0, 240, 48), true)
	var period := _label(trend, "近 7 天", BODY_SIZE, muted_color)
	period.name = "Period"
	trend_chart = Chart.new()
	trend_chart.days = _stats().recent_days()
	trend_chart.dark = dark
	trend.add_child(trend_chart)
	divider = _line(body, Rect2())
	distribution = _display_panel(body, "DistributionCard")
	_label(distribution, "题型分布", SECTION_SIZE, text_color, Rect2(0, 0, 300, 48), true)
	_label(distribution, "已练习 %s 题" % _number(data.learned), BODY_SIZE, muted_color, Rect2(0, 54, 360, 36))
	distribution.get_child(-1).name = "Learned"
	for index in Chart.TYPES.size():
		var kind: String = Chart.TYPES[index]
		var row := _display_panel(distribution, kind)
		_label(row, _stats().TYPE_NAMES[kind], BODY_SIZE, muted_color, Rect2(0, 0, 100, 38))
		var ratio: float = 100.0 * data.types.get(kind, 0) / maxi(1, data.total)
		_bar(row, ratio, Rect2(106, 16, 220, 8)).name = "Bar"
		_label(row, "%.1f%%" % ratio, BODY_SIZE, BLUE).name = "Percent"

func _refresh_data() -> void:
	if not is_inside_tree():
		return
	data = _stats().summary()
	var values := [str(data.today), _percent(float(data.percent)), str(data.days), _number(data.total)]
	for index in stat_cards.size():
		stat_cards[index].get_node("Value").text = values[index]
		stat_cards[index].get_node("Unit").position.x = bold_font.get_string_size(values[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x + 8
	var progress: ProgressBar = stat_cards[1].get_node("Progress")
	progress.value = float(data.percent)
	trend_chart.days = _stats().recent_days()
	distribution.get_node("Learned").text = "已练习 %s 题" % _number(data.learned)

func _refresh_cached_content() -> void:
	_refresh_data()
	_refresh_rewards()

func _refresh_rewards() -> void:
	if not is_instance_valid(reward_notice) or not is_instance_valid(reward_store): return
	reward_notice.text = reward_store.last_message if not reward_store.last_message.is_empty() else "坚持学习，遇见更好的自己"

func _layout_content(width: float) -> void:
	_rect(hero, Rect2(0, 114, width, 140))
	var compact := width < 1000
	var columns := 2 if compact else 4
	var card_width := width / columns
	for index in stat_cards.size():
		_rect(stat_cards[index], Rect2((index % columns) * card_width + (32 if index % columns else 0), 280 + (index / columns) * 150, card_width - 32, 126))
	var chart_y := 472.0 + (150 if compact else 0)
	_rect(separator, Rect2(0, chart_y - 48, width, 1))
	var trend_width := width if compact else width * 0.59
	_rect(trend, Rect2(0, chart_y, trend_width, 370))
	_rect(trend.get_node("Period"), Rect2(trend_width - 95, 4, 90, 40))
	_rect(trend_chart, Rect2(0, 70, trend_width - 10, 290))
	divider.visible = not compact
	_rect(divider, Rect2(trend_width + 20, chart_y, 1, 350))
	var distribution_width := width if compact else width - trend_width - 55
	_rect(distribution, Rect2(0 if compact else trend_width + 55, chart_y + 405 if compact else chart_y, distribution_width, 400))
	for index in Chart.TYPES.size():
		var row: Control = distribution.get_node(Chart.TYPES[index])
		_rect(row, Rect2(0, 108 + index * 48, distribution_width, 40))
		_rect(row.get_node("Bar"), Rect2(106, 16, maxf(50, distribution_width - 200), 8))
		_rect(row.get_node("Percent"), Rect2(distribution_width - 82, 0, 82, 38))
	content_height = chart_y + (820 if compact else 420)

func _details(title: String, subtitle: String) -> VBoxContainer:
	_close_details(false)
	var previous := get_viewport().gui_get_focus_owner()
	detail_return_focus = weakref(previous) if previous != null else null
	for control in canvas.find_children("*", "Button", true, false):
		if control.focus_mode != Control.FOCUS_NONE:
			modal_focus.append(control)
			control.focus_mode = Control.FOCUS_NONE
	detail_overlay = Control.new()
	detail_overlay.name = "DetailsOverlay"
	canvas.add_child(detail_overlay)
	detail_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := _button(detail_overlay, "Backdrop", "", _close_details, Color(0.02, 0.06, 0.17, 0.48))
	backdrop.set_meta("motion_fixed", true)
	backdrop.focus_mode = Control.FOCUS_NONE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A fixed backdrop for every state, with click-to-close instead of hover UI.
	for state in ["normal", "hover", "pressed", "focus"]:
		backdrop.add_theme_stylebox_override(state, _style(Color(0.02, 0.06, 0.17, 0.48), 0))
	var panel := Panel.new()
	panel.name = "DetailPanel"
	panel.add_theme_stylebox_override("panel", _style(surface, 26))
	detail_overlay.add_child(panel)
	var heading := _label(panel, title, 36, text_color, Rect2(32, 23, 540, 55))
	heading.name = "Heading"
	var subtitle_label := _label(panel, subtitle, 20, muted_color, Rect2(32, 86, 640, 70))
	subtitle_label.name = "Subtitle"
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close_button := _button(panel, "CloseButton", "关闭", _close_details, Color.TRANSPARENT)
	_rect(close_button, Rect2(610, 28, 90, 46))
	close_button.grab_focus()
	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "DetailScroll"
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(detail_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	detail_scroll.add_child(column)
	_layout_details()
	_motion().enter(panel, Tokens.PANEL)
	return column


func _layout_details() -> void:
	var panel: Control = detail_overlay.get_node("DetailPanel")
	var panel_size := Vector2(minf(740, canvas.size.x - 48), minf(780, canvas.size.y - 48))
	_rect(panel, Rect2((canvas.size - panel_size) * 0.5, panel_size))
	_rect(panel.get_node("DetailScroll"), Rect2(32, 170, panel_size.x - 64, panel_size.y - 202))
	_rect(panel.get_node("CloseButton"), Rect2(panel_size.x - 130, 28, 90, 46))
	_rect(panel.get_node("Heading"), Rect2(32, 23, panel_size.x - 180, 55))
	_rect(panel.get_node("Subtitle"), Rect2(32, 86, panel_size.x - 64, 70))


func _close_details(animate := true) -> void:
	for control in modal_focus:
		if is_instance_valid(control):
			control.focus_mode = Control.FOCUS_ALL
	modal_focus.clear()
	if is_instance_valid(detail_overlay):
		if animate:
			_motion().retire(detail_overlay)
		else:
			canvas.remove_child(detail_overlay)
			detail_overlay.queue_free()
		detail_overlay = null
	if detail_return_focus != null:
		var previous: Control = detail_return_focus.get_ref()
		if is_instance_valid(previous) and previous.is_inside_tree():
			previous.grab_focus()
	detail_return_focus = null


func _history_row(column: VBoxContainer, text: String) -> void:
	var row := PanelContainer.new()
	row.name = "HistoryRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, 68)
	row.add_theme_stylebox_override("panel", _style(Tokens.DARK_SOFT if dark else Tokens.SOFT, 8))
	column.add_child(row)
	var label := _label(row, text, BODY_SIZE, text_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _show_history() -> void:
	var column := _details("学习记录", "累计学习 %d 天 · 最近 14 天\n每天完成一道题即可记为学习一天。" % data.days)
	var days: Array = _stats().recent_days(14)
	days.reverse()
	for day in days:
		_history_row(column, "%s     %d 题" % [day.date, day.count])


func consume_back_action() -> bool:
	if not is_instance_valid(detail_overlay):
		return false
	_close_details()
	return true
