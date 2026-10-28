extends Window
## Native exclusive window supplies focus confinement and Escape handling.
signal closed
var page: Control
var store: Node
var card_id := ""
var selected_friend: Dictionary = {}
var friend_rows: Array = []
var query_epoch := 0
var busy := false
var closing := false
var search: LineEdit
var friends_list: VBoxContainer
var friend_status: Label
var quantity: SpinBox
var confirm: Button
var recovery: Button
var review: Label
var remaining: Label
var error_label: Label
var stock: Label
var card_art: TextureRect
var panel: PanelContainer
var shade: ColorRect
var scroll_box: ScrollContainer
var column: VBoxContainer
var _account := ""

func _ready() -> void:
	title = "赠送好友"
	transient = true
	exclusive = true
	borderless = true
	visible = false
	theme = page.theme
	_account = store.account_id
	min_size = Vector2i(340, 280)
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", page._style(page.surface, 8, page.border))
	add_child(panel)
	scroll_box = ScrollContainer.new()
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll_box)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll_box.add_child(margin)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var heading_label := _text(heading, "赠送好友", 26)
	heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := _action(heading, "关闭", dismiss)
	close.accessibility_name = "关闭赠送好友窗口"
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 20)
	column.add_child(info)
	var card: Dictionary = store.card(card_id)
	var art: Control = page._picture(info, card, Rect2())
	card_art = art
	art.custom_minimum_size = Vector2(84, 84 * page._picture_ratio(art))
	var metadata := VBoxContainer.new()
	metadata.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(metadata)
	_text(metadata, str(card.name), 24)
	_text(metadata, page._season_title(store.season(card.season_id)), 18)
	stock = _text(metadata, page._count_text(card_id), 18)
	_text(column, "选择好友", 20)
	search = LineEdit.new()
	search.placeholder_text = "搜索昵称或账号 ID"
	search.accessibility_name = "搜索好友昵称或账号 ID"
	search.custom_minimum_size.y = 44
	search.add_theme_color_override("font_color", page.text_color)
	search.add_theme_color_override("font_placeholder_color", page.muted_color)
	var input_style: StyleBoxFlat = page._style(page.surface, 6, page.border)
	input_style.content_margin_left = 12
	input_style.content_margin_right = 12
	search.add_theme_stylebox_override("normal", input_style)
	search.add_theme_stylebox_override("focus", input_style)
	column.add_child(search)
	page._suppress_collection_focus(search)
	page._motion().bind_input(search)
	search.text_changed.connect(_search_friends)
	friend_status = _text(column, "正在读取好友…", 18)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size.y = 118
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(list_scroll)
	friends_list = VBoxContainer.new()
	friends_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(friends_list)
	var quantity_row := HBoxContainer.new()
	quantity_row.add_theme_constant_override("separation", 18)
	column.add_child(quantity_row)
	_text(quantity_row, "赠送数量", 20)
	quantity = SpinBox.new()
	quantity.min_value = 1
	quantity.max_value = maxi(1, int(store.gift_rule(card_id).max))
	quantity.step = 1
	quantity.rounded = true
	quantity.allow_greater = false
	quantity.allow_lesser = false
	quantity.value = 1
	quantity.custom_minimum_size = Vector2(120, 44)
	quantity.suffix = "张"
	quantity.get_line_edit().accessibility_name = "赠送数量，正整数"
	quantity_row.add_child(quantity)
	var quantity_edit := quantity.get_line_edit()
	quantity_edit.add_theme_color_override("font_color", page.text_color)
	quantity_edit.add_theme_stylebox_override("normal", input_style.duplicate())
	quantity_edit.add_theme_stylebox_override("focus", input_style.duplicate())
	page._suppress_collection_focus(quantity_edit)
	page._motion().bind_input(quantity_edit)
	quantity.value_changed.connect(_sync.unbind(1))
	review = _text(column, "", 20)
	remaining = _text(column, "", 20)
	error_label = _text(column, "", 18)
	error_label.add_theme_color_override("font_color", page.muted_color)
	recovery = _action(column, "查询上一笔赠送结果", _recover)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var cancel := _action(actions, "取消", dismiss)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm = Button.new()
	confirm.text = "确认赠送 1 张"
	confirm.custom_minimum_size.y = 44
	confirm.pressed.connect(_submit)
	actions.add_child(confirm)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page._style_button(confirm, page.BLUE, true)
	page._suppress_collection_focus(confirm)
	store.changed.connect(_sync)
	store.operation_changed.connect(_sync)
	store.gift_completed.connect(_finished)
	store.friends_loaded.connect(_friends_arrived)
	close_requested.connect(dismiss)
	window_input.connect(_on_input)
	_sync()
	_search_friends("")

func _text(parent: Node, caption: String, font_size: int) -> Label:
	var label: Label = page._label(parent, caption, font_size, page.text_color)
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = font_size + 6
	return label

func _action(parent: Node, caption: String, action: Callable) -> Button:
	var button: Button = page._button(parent, "Action", caption, action)
	button.custom_minimum_size = Vector2(84, 44)
	button.add_theme_font_size_override("font_size", 20)
	return button

func present() -> void:
	popup_centered_clamped(Vector2i(600, 780), 0.9)
	page._motion().enter(panel, page.Tokens.PANEL)
	search.grab_focus()

func _search_friends(query: String) -> void:
	query_epoch += 1
	friend_status.text = "正在读取好友…"
	for child in friends_list.get_children():
		friends_list.remove_child(child)
		child.queue_free()
	friend_rows.clear()
	store.search_friends(query, "%s:%s" % [get_instance_id(), query_epoch])

func _friends_arrived(ticket: String, response: Dictionary) -> void:
	if not is_inside_tree() or closing or ticket != "%s:%s" % [get_instance_id(), query_epoch] or _account != store.account_id:
		return
	if not response.get("ok", false):
		friend_status.text = str(response.get("message", "好友读取失败，请重试。"))
		_action(friends_list, "重试", _search_friends.bind(search.text))
		return
	var friends: Array = response.get("friends", [])
	friend_status.text = "没有可选好友" if friends.is_empty() and search.text.is_empty() else "没有匹配的好友" if friends.is_empty() else "已选：%s（%s）" % [selected_friend.name, selected_friend.id] if not selected_friend.is_empty() else "请选择一位好友"
	for friend in friends:
		if str(friend.get("id", "")).is_empty():
			continue
		var row := _action(friends_list, "%s  ·  %s" % [friend.get("name", ""), friend.id], _choose_friend.bind(friend))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.icon = page._texture("res://assets/minimal/icons/user-round.png")
		var avatar := str(friend.get("avatar", ""))
		if not avatar.is_empty() and ResourceLoader.exists(avatar):
			row.icon = page._texture(avatar)
		row.set_meta("friend_id", friend.id)
		row.set_meta("eligible", friend.get("eligible", true))
		row.disabled = busy or not friend.get("eligible", true)
		friend_rows.append(row)
	_sync()

func _choose_friend(friend: Dictionary) -> void:
	selected_friend = friend.duplicate(true)
	friend_status.text = "已选：%s（%s）" % [friend.name, friend.id]
	_sync()

func _sync() -> void:
	if not is_instance_valid(confirm) or closing:
		return
	if _account != store.account_id:
		dismiss()
		return
	var rule: Dictionary = store.gift_rule(card_id)
	stock.text = page._count_text(card_id)
	page._set_card_art_state(card_art, card_id)
	# Preserve a now-invalid quantity after a service failure so the user sees why.
	var n := int(quantity.value)
	quantity.max_value = maxi(n, maxi(1, int(rule.max)))
	var name := str(store.card(card_id).get("name", ""))
	review.text = "请选择赠送对象。" if selected_friend.is_empty() else "将 %d 张「%s」赠送给 %s。" % [n, name, selected_friend.name]
	if n >= 1 and n <= int(rule.max):
		remaining.text = "送出后你将剩余 %d 张（至少保留 1 张）。" % (store.count(card_id) - n)
	else:
		remaining.text = "每种卡片至少保留 1 张，当前最多可赠送 %d 张。" % int(rule.max)
	confirm.text = "正在提交…" if busy else "确认赠送 %d 张" % n
	confirm.disabled = busy or store.pending() or selected_friend.is_empty() or n < 1 or n > int(rule.max) or not selected_friend.get("eligible", true)
	# Refresh this local button before its draw: changing a shared StyleBox from
	# inside the draw callback can otherwise leave an embedded window one draw behind.
	var feedback := confirm.get_node_or_null("UIFeedback")
	if feedback != null:
		feedback._check_disabled()
	confirm.queue_redraw()
	quantity.editable = not busy and not store.pending() and int(rule.max) > 0
	search.editable = not busy and not store.pending()
	recovery.visible = store.pending()
	recovery.disabled = busy or store._busy
	for row in friend_rows:
		row.disabled = busy or store.pending() or not row.get_meta("eligible", true)
		page._tab(row, row.get_meta("friend_id") == selected_friend.get("id", ""))
	if store.pending():
		error_label.text = "上一笔赠送正在核实。关闭窗口不会取消已经提交的赠送。"
	elif not str(rule.get("reason", "")).is_empty():
		error_label.text = str(rule.reason)
	elif n > int(rule.max):
		error_label.text = "当前可赠数量已变化，请调整数量。"
	elif not str(rule.get("consequence", "")).is_empty():
		error_label.text = str(rule.consequence)
	elif error_label.text == store.KEEP_ONE_REASON:
		error_label.text = ""

func _submit() -> void:
	quantity.apply()
	_sync()
	if confirm.disabled or busy:
		return
	busy = true
	error_label.text = ""
	_sync()
	# Store outlives this window. Closing cannot cancel or repeat an operation.
	store.submit_gift(card_id, str(selected_friend.id), int(quantity.value))

func _recover() -> void:
	if busy:
		return
	busy = true
	_sync()
	store.recover_gift()

func _finished(response: Dictionary) -> void:
	if not is_inside_tree() or closing:
		return
	busy = false
	_sync()
	error_label.text = response.get("message", "")
	if response.get("ok", false):
		dismiss()

func _on_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		dismiss()

func dismiss() -> void:
	if closing:
		return
	closing = true
	query_epoch += 1
	page._retire_window(self)
	hide()
	if is_instance_valid(shade):
		page._motion().retire(shade)
		shade = null
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	query_epoch += 1
	if is_instance_valid(shade) and not shade.is_queued_for_deletion():
		shade.queue_free()
