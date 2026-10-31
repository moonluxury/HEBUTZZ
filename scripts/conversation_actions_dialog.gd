extends CanvasLayer
## One in-scene modal surface. SocialStore owns all authenticated I/O and retries.
const Row = preload("res://scripts/conversation_action_row.gd")
const UI = preload("res://scripts/account_dialog_ui.gd")
const Styles = preload("res://scripts/ui_styles.gd")
const Avatar = preload("res://scripts/profile_avatar.gd")
const TimeDisplay = preload("res://scripts/time_display.gd")
const BASE := Vector2(455, 532)
const INK := Color("#151922")
const MUTED := Color("#707988")
const BLUE := Color("#092C87")
const ITEMS := [
	{"id": "profile", "title": "查看资料", "subtitle": "查看对方的公开资料"},
	{"id": "remark", "title": "修改备注", "subtitle": "设置备注名，方便识别"},
	{"id": "marks", "title": "标记卡牌", "subtitle": "为该好友设置卡牌标记"},
	{"id": "records", "title": "与此好友的记录", "subtitle": "查看赠送、交换等历史记录"},
	{"id": "block", "title": "屏蔽此好友", "subtitle": "不再接收对方的消息"},
	{"id": "remove", "title": "删除好友", "subtitle": "删除后将不再显示在好友列表中"}
]
signal closed
var page: Control
var store: Node
var context: Dictionary = {}
var panel_mode := "peer_menu"
var panel: Panel
var shade: ColorRect
var column: Control
var content: VBoxContainer
var status: Label
var query: LineEdit
var confirmation: Button
var close_button: Button
var rows: Dictionary = {}
var closing := false
var busy := false
var _switching := false
var _epoch := 0
var _peer_id := ""
var _conversation_id := ""
var _serial := 0
var _transition := 0
var _pending: Dictionary = {}
var _focusables: Array[Control] = []
var _scale := 1.0
var _record_tab := "gifts"
var _record_data := {"gifts": [], "trades": []}
var _cursors := {"gifts": "", "trades": ""}
var _loaded := {"gifts": false, "trades": false}
var _record_id := ""

func _ready() -> void:
	layer = 90
	_epoch = store.epoch
	_peer_id = str(context.get("peer", {}).get("id", ""))
	_conversation_id = str(context.get("conversation", {}).get("id", ""))
	shade = ColorRect.new()
	shade.name = "ConversationModalShade"
	shade.color = Color(0.12, 0.14, 0.18, 0.36)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.focus_mode = Control.FOCUS_ALL
	add_child(shade)
	shade.gui_input.connect(_outside)
	panel = Panel.new()
	panel.name = "ConversationActionsPanel"
	panel.theme = page.theme
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.size = BASE
	var box := Styles.box(Color.WHITE, 11, Color.TRANSPARENT)
	box.shadow_color = Color(0, 0, 0, 0.025)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	get_viewport().size_changed.connect(_fit)
	page.resized.connect(_fit)
	get_node("/root/AppState").font_scale_changed.connect(_fit.unbind(1))
	store.changed.connect(_changed)
	store.completed.connect(_response)
	_build()
	_fit()

func _motion() -> Node: return get_node("/root/UiMotion")

func _fit() -> void:
	if not is_instance_valid(panel): return
	var bounds := get_viewport().get_visible_rect().size
	_scale = minf(page.canvas.scale.x, minf((bounds.x - 32) / BASE.x, (bounds.y - 32) / BASE.y))
	_scale = maxf(0.1, _scale)
	panel.scale = Vector2.ONE * _scale
	panel.position = (bounds - BASE * _scale) * 0.5

func present() -> void:
	shade.modulate.a = 0.0
	panel.modulate.a = 0.0
	_motion().animate(shade, shade, ^"modulate:a", 1.0, 0.18)
	_motion().animate(panel, panel, ^"modulate:a", 1.0, 0.18)
	shade.grab_focus() # No row is selected in the P3 initial state.

func _build() -> void:
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	_pending.clear()
	_focusables.clear()
	rows.clear()
	query = null
	confirmation = null
	column = Control.new()
	column.size = BASE
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var heading := UI.label(column, _title(), 20, INK, true)
	heading.position = Vector2(28, 22)
	heading.size = Vector2(350, 32)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close_button = _button(column, "", dismiss)
	close_button.icon = Row.glyph("close", INK)
	close_button.add_theme_constant_override("icon_max_width", 20)
	close_button.position = Vector2(403, 20)
	close_button.size = Vector2(32, 32)
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.accessibility_name = "关闭会话操作"
	close_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	if panel_mode == "peer_menu":
		_build_menu()
		_focusables.erase(close_button)
		_focusables.append(close_button)
		return
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(28, 74)
	scroll.size = Vector2(399, 370)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	status = _text("", 14)
	var back := _button(column, "返回会话操作", _switch.bind("peer_menu"))
	back.position = Vector2(28, 464)
	back.size = Vector2(399, 40)
	match panel_mode:
		"profile": _profile()
		"remark": _remark_form()
		"marks":
			_text("为「%s」设置卡牌标记" % store.display_name(context.peer), 17, true)
			_text("好友卡牌标记尚未接入，当前无法读取或保存标记。")
			_text("此操作需要好友与卡牌的标记接口，不会更改想要清单、卡牌数量或电池余额。")
			confirmation = _button(content, "保存标记", func(): pass, true)
			confirmation.disabled = true
		"records": _records_view()
		"record_detail": _ask("gift_detail" if _record_tab == "gifts" else "trade_detail", {"record_id": _record_id}, "detail")
		"block", "unblock", "remove": _relationship_form()
		"notice": _text(str(context.get("notice", "当前操作不可用。")))
	if panel_mode == "remark" and is_instance_valid(query): query.grab_focus()
	else: shade.grab_focus()

func _title() -> String:
	if panel_mode == "peer_menu": return "会话操作"
	if panel_mode == "unblock": return "解除屏蔽"
	if panel_mode == "record_detail": return "赠送详情" if _record_tab == "gifts" else "换卡详情"
	for item in ITEMS:
		if item.id == panel_mode: return item.title
	return "提示"

func _build_menu() -> void:
	for index in ITEMS.size():
		var item: Dictionary = ITEMS[index].duplicate()
		if item.id == "block" and context.conversation.get("blocked_by_me", false):
			item.title = "解除屏蔽"
			item.subtitle = "允许对方再次发送消息"
		var row := Row.new()
		column.add_child(row)
		row.configure(item, _activate.bind(str(item.id)))
		row.position = Vector2(28, 68 + index * 70 if index < 5 else 438)
		row.size = Vector2(399, 60 if index < 5 else 66)
		rows[item.id] = row
		_focusables.append(row)
	var rule := ColorRect.new()
	rule.color = Color("#E4E7EC")
	rule.position = Vector2(28, 423)
	rule.size = Vector2(399, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

func _text(value: String, font_size := 15, strong := false) -> Label:
	return UI.label(content, value, font_size, INK if strong else MUTED, strong)

func _button(parent: Node, caption: String, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 16)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE if primary else INK)
	button.add_theme_stylebox_override("normal", Styles.box(BLUE if primary else Color.WHITE, 7, BLUE if primary else Color("#E4E7EC")))
	button.add_theme_stylebox_override("hover", Styles.box(Color("#143C96") if primary else Color("#EBEEF5"), 7))
	button.add_theme_stylebox_override("pressed", Styles.box(Color("#092467") if primary else Color("#DFE5F0"), 7))
	button.add_theme_stylebox_override("disabled", Styles.box(Color("#F0F2F5"), 7))
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("focus", Styles.box(Color.TRANSPARENT, 7, BLUE))
	parent.add_child(button)
	button.pressed.connect(callback)
	_focusables.append(button)
	return button

func _activate(id: String) -> void:
	if busy or closing or _switching: return
	var reason := _permission(id)
	if not reason.is_empty():
		context.notice = reason
		_switch("notice")
		return
	_switch("unblock" if id == "block" and context.conversation.get("blocked_by_me", false) else id)

func _permission(id: String) -> String:
	if not store.available(): return store.unavailable()
	var conv: Dictionary = store.conversation(_conversation_id)
	if conv.is_empty() or conv.get("kind") == "system" or str(conv.get("peer", {}).get("id", "")) != _peer_id:
		return "当前联系人不可执行此操作。"
	if id in ["remark", "marks", "remove"] and not conv.get("is_friend", false): return "此操作仅适用于当前好友。"
	return ""

func _switch(mode: String) -> void:
	if closing or busy or _switching: return
	_switching = true
	_transition += 1
	var transition := _transition
	_pending.clear()
	_motion().animate(panel, panel, ^"modulate:a", 0.0, 0.12, true)
	if _motion().reduced(): _finish_switch(mode, transition)
	else: get_tree().create_timer(0.12).timeout.connect(_finish_switch.bind(mode, transition))

func _finish_switch(mode: String, transition: int) -> void:
	if closing or transition != _transition: return
	panel_mode = mode
	_build()
	_switching = false
	_motion().animate(panel, panel, ^"modulate:a", 1.0, 0.18)

func _profile() -> void:
	_ask("find_user", {"public_id": context.peer.get("public_id", "")}, "profile")

func _remark_form() -> void:
	_text("为「%s」设置备注，仅自己可见。" % str(context.peer.get("name", "")))
	query = LineEdit.new()
	query.text = str(context.peer.get("remark", ""))
	query.placeholder_text = "备注名（最多 %d 字）" % store.REMARK_LIMIT
	query.accessibility_name = "好友备注"
	query.max_length = store.REMARK_LIMIT
	query.custom_minimum_size.y = 44
	query.add_theme_font_size_override("font_size", 17)
	query.add_theme_color_override("font_color", INK)
	var frame := Styles.box(Color.WHITE, 7, Color("#D0D5DD"))
	frame.set_content_margin_all(10)
	query.add_theme_stylebox_override("normal", frame)
	query.add_theme_stylebox_override("focus", Styles.box(Color.TRANSPARENT, 7, BLUE))
	content.add_child(query)
	_focusables.append(query)
	confirmation = _button(content, "保存备注", _save_remark, true)
	_button(content, "取消", _switch.bind("peer_menu"))
	query.text_submitted.connect(_save_remark.unbind(1))
	query.grab_focus()

func _save_remark() -> void:
	if is_instance_valid(query): _mutate("preferences", {"peer_id": _peer_id, "remark": query.text}, "remark")

func _relationship_form() -> void:
	_text(store.display_name(context.peer), 18, true)
	_text("公开 ID：" + str(context.peer.get("public_id", "")), 14)
	_text({"remove": "删除后，对方将不再显示在好友列表中。聊天和已完成的赠送、换卡记录会保留，待确认的交换将失效。", "block": "屏蔽后，将阻止对方的新消息、好友申请和转卡。按现有服务规则，同时解除好友关系，待确认的交换将失效；聊天和已完成记录保留。", "unblock": "解除后允许重新联系，但不会自动恢复好友关系或失效的交换。"}[panel_mode])
	confirmation = _button(content, {"remove": "确认删除", "block": "确认屏蔽", "unblock": "解除屏蔽"}[panel_mode], _confirm_relationship, true)
	_button(content, "取消", _switch.bind("peer_menu"))

func _confirm_relationship() -> void:
	_mutate("relationship", {"peer_id": _peer_id, "operation": panel_mode}, "block" if panel_mode == "unblock" else panel_mode)

func _mutate(action: String, payload: Dictionary, permission: String) -> void:
	if busy or closing or _switching: return
	var reason := _permission(permission)
	if not reason.is_empty(): status.text = reason; return
	var operation_id: String = store.intent(action, payload)
	if operation_id.is_empty(): status.text = "无法保存操作标识，尚未提交，请重试。"; return
	payload = payload.duplicate(true)
	payload.operation_id = operation_id
	busy = true
	_lock()
	_ask(action, payload, "saved")

func _lock() -> void:
	for button in column.find_children("*", "Button", true, false):
		button.disabled = busy and button != close_button
	if is_instance_valid(query): query.editable = not busy

func _ask(action: String, payload: Dictionary, handler: String) -> void:
	_serial += 1
	var ticket := "conversation:%s:%s" % [get_instance_id(), _serial]
	_pending[ticket] = handler
	status.text = "正在保存…" if busy else "正在加载…"
	store.dispatch(action, payload, ticket)

func _response(ticket: String, response: Dictionary) -> void:
	if closing or _epoch != store.epoch or not _pending.has(ticket): return
	var handler: String = _pending[ticket]
	_pending.erase(ticket)
	if handler == "saved": busy = false; _lock()
	if not response.get("ok", false):
		status.text = str(response.get("message", "请求失败，请重试。"))
		if handler != "saved": _button(content, "重试", _retry.bind(handler))
		return
	status.text = ""
	match handler:
		"saved":
			status.text = "备注已保存。" if panel_mode == "remark" else "已删除好友，历史记录已保留。" if panel_mode == "remove" else "已解除屏蔽，好友关系未自动恢复。" if panel_mode == "unblock" else "已屏蔽，好友关系已解除。"
			if panel_mode != "remark": confirmation.disabled = true
		"profile":
			var person: Dictionary = response.get("user", {})
			if str(person.get("id", "")) != _peer_id:
				status.text = "对方的公开资料当前不可访问。"
				return
			var avatar := Avatar.new()
			avatar.custom_minimum_size = Vector2(80, 80)
			avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			content.add_child(avatar)
			avatar.show_profile(person)
			_text(str(person.get("name", "")), 20, true)
			_text("公开 ID：" + str(person.get("public_id", "")))
			# The public-user API currently exposes no school/contact/account fields.
			_text("我的备注：" + str(person.get("remark", "未设置")))
		"gifts", "trades": _accept_records(handler, response)
		"detail": _detail(response)

func _retry(handler: String) -> void:
	if handler in ["gifts", "trades"]: _load_records()
	else: _build()

func _records_view() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	content.add_child(tabs)
	_button(tabs, "赠送记录", _choose_records.bind("gifts"), _record_tab == "gifts")
	_button(tabs, "换卡记录", _choose_records.bind("trades"), _record_tab == "trades")
	for record in _record_data[_record_tab]:
		_text(("卡牌赠送" if _record_tab == "gifts" else "换卡 · " + page.trade_status(str(record.get("status", "")))) + " · " + TimeDisplay.datetime(str(record.get("time_label", ""))), 15, true)
		_text("记录 ID：" + str(record.get("record_id", record.get("id", ""))), 13)
		if _record_tab == "gifts": _text(str(record.get("summary", record.get("title", ""))), 14)
		_button(content, "查看详情", _open_record.bind(str(record.get("record_id", record.get("id", "")))))
	if not _loaded[_record_tab]: _load_records()
	elif not str(_cursors[_record_tab]).is_empty():
		_text("尚有更早记录，可继续加载。", 13)
		_button(content, "继续查找更早赠送" if _record_tab == "gifts" else "加载更多换卡", _load_records)
	elif _record_data[_record_tab].is_empty(): _text("暂无赠送记录。" if _record_tab == "gifts" else "暂无换卡记录。")

func _choose_records(kind: String) -> void:
	if closing or _switching or _record_tab == kind: return
	_record_tab = kind
	_build()

func _load_records() -> void:
	if closing: return
	if _record_tab in _pending.values(): return
	if _record_tab == "gifts":
		_ask("history", {"conversation_id": _conversation_id, "before": _cursors.gifts, "limit": store.PAGE_SIZE}, "gifts")
	else:
		_ask("trade_records", {"peer_id": _peer_id, "before": _cursors.trades, "limit": store.PAGE_SIZE}, "trades")

func _accept_records(kind: String, response: Dictionary) -> void:
	for record in response.get("messages" if kind == "gifts" else "trades", []):
		if kind == "gifts" and (record.get("type") != "gift" or str(record.get("conversation_id", "")) != _conversation_id): continue
		if kind == "trades" and str(record.get("conversation_id", "")) != _conversation_id: continue
		var id := str(record.get("record_id", "") if kind == "gifts" else record.get("id", ""))
		if id.is_empty(): continue
		var duplicate := false
		for old in _record_data[kind]:
			if str(old.get("record_id", old.get("id", ""))) == id: duplicate = true
		if not duplicate: _record_data[kind].append(record.duplicate(true))
	if kind == "gifts": _record_data[kind].sort_custom(func(a, b): return int(a.get("seq", 0)) > int(b.get("seq", 0)))
	_cursors[kind] = str(response.get("next_before", ""))
	_loaded[kind] = true
	_build()

func _open_record(id: String) -> void:
	_record_id = id
	_switch("record_detail")

func _detail(response: Dictionary) -> void:
	var record: Dictionary = response.get("gift", response.get("trade", {}))
	if record.is_empty() or (record.has("id") and str(record.id) != _record_id) or (record.has("conversation_id") and str(record.conversation_id) != _conversation_id):
		status.text = "服务未返回匹配的记录。"
		return
	_text("记录 ID：" + _record_id, 14)
	if record.has("status"): _text("状态：" + page.trade_status(str(record.status)), 17, true)
	_text(TimeDisplay.datetime(str(record.get("time_label", ""))))
	if record.has("summary"): _text(str(record.summary))
	for direction in ["give", "receive"]:
		for line in record.get(direction, []):
			var card: Dictionary = page.collection.card(str(line.get("card_id", "")))
			_text(("发起方给出：" if direction == "give" else "接收方给出：") + str(card.get("name", line.get("card_id", ""))) + " ×" + str(line.get("quantity", "")))
	_button(content, "返回记录", _switch.bind("records"))

func _changed() -> void:
	if _epoch != store.epoch or store.selected != _conversation_id or not page.is_inside_tree():
		_finish_close()
		return
	if closing: return
	var conv: Dictionary = store.conversation(_conversation_id)
	if conv.get("kind") == "system" or str(conv.get("peer", {}).get("id", "")) != _peer_id:
		_finish_close()
		return
	context.conversation = conv.duplicate(true)
	context.peer = conv.get("peer", {}).duplicate(true)
	if panel_mode == "peer_menu" and rows.has("block"):
		var blocked: bool = conv.get("blocked_by_me", false)
		rows.block.caption.text = "解除屏蔽" if blocked else ITEMS[4].title
		rows.block.description.text = "允许对方再次发送消息" if blocked else ITEMS[4].subtitle
		rows.block.accessibility_name = rows.block.caption.text + "，" + rows.block.description.text

func _outside(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		shade.accept_event()
		dismiss()

func _input(event: InputEvent) -> void:
	if closing: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			dismiss()
		elif event.keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
			var available := _focusables.filter(func(c): return is_instance_valid(c) and c.is_visible_in_tree() and not (c is BaseButton and c.disabled))
			if available.is_empty(): return
			var index := available.find(get_viewport().gui_get_focus_owner())
			available[posmod(index + (-1 if event.shift_pressed else 1), available.size())].grab_focus()

func dismiss() -> void:
	if not is_inside_tree(): _finish_close(); return
	if closing: return
	closing = true
	_transition += 1
	_pending.clear()
	_motion().animate(panel, panel, ^"modulate:a", 0.0, 0.12, true)
	_motion().animate(shade, shade, ^"modulate:a", 0.0, 0.12, true)
	if _motion().reduced(): _finish_close()
	else: get_tree().create_timer(0.12).timeout.connect(_finish_close)

func _finish_close() -> void:
	if is_queued_for_deletion(): return
	closing = true
	_transition += 1
	_pending.clear()
	hide()
	closed.emit()
	queue_free()
