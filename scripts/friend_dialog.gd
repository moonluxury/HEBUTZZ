extends Window
const TimeDisplay = preload("res://scripts/time_display.gd")
## The add/request flow owns presentation only; authenticated I/O stays in SocialStore.
const Styles = preload("res://scripts/ui_styles.gd")
const UI = preload("res://scripts/account_dialog_ui.gd")
const Avatar = preload("res://scripts/profile_avatar.gd")
const BLUE := Color("#092C87")
const INK := Color("#1B1F28")
const MUTED := Color("#667085")
const BORDER := Color("#E4E7EC")
const BASE_SIZE := Vector2(504, 620)
const NOTE_LIMIT := 100
signal closed
var page: Control
var store: Node
var panel_mode := "add"
var context: Dictionary = {}
var panel: PanelContainer
var shade: ColorRect
var column: VBoxContainer
var content: VBoxContainer
var scroll_box: ScrollContainer
var status: Label
var query: LineEdit
var note: TextEdit
var counter: Label
var search_button: Button
var send_button: Button
var close_button: Button
var friend_tabs: Dictionary = {}
var tab_surfaces: Dictionary = {}
var tab_lines: Dictionary = {}
var result_slot: VBoxContainer
var empty_result: Label
var closing := false
var busy := false
var searching := false
var _epoch := 0
var _serial := 0
var _close_serial := 0
var _ticket := ""
var _friend_query := ""
var _friend_note := ""
var _lookup: Dictionary = {}
var _lookup_query := ""
var _writes: Dictionary = {}
var _pending: Dictionary = {}
var _row_feedback: Dictionary = {}
var _request_rows: Array = []
var _request_read_seq := 0
var _requests_hash := ""
var _read_timer := 0.0
var _login_pending := false
var _fit_queued := false
var _ui_scale := 1.0

func _ready() -> void:
	_epoch = store.epoch
	panel_mode = "requests" if panel_mode == "requests" else "add"
	title = "添加好友"
	transient = true
	exclusive = true
	visible = false
	theme = page.theme
	content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	shade = ColorRect.new()
	shade.name = "FriendModalShade"
	shade.color = Color(0.08, 0.10, 0.14, 0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(panel)
	var frame := Styles.dialog_panel(self, panel, Color.WHITE, 12)
	frame.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", frame)
	column = _vbox(panel, 12)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	_label(heading, "添加好友", 24, INK, true)
	close_button = _button(heading, "", dismiss)
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.icon = UI.glyph("close", MUTED)
	close_button.add_theme_constant_override("icon_max_width", 20)
	close_button.accessibility_name = "关闭添加好友"
	_build_tabs()
	scroll_box = ScrollContainer.new()
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.follow_focus = true
	column.add_child(scroll_box)
	content = _vbox(scroll_box, 0)
	store.completed.connect(_response)
	store.changed.connect(_changed)
	close_requested.connect(dismiss)
	window_input.connect(_window_input)
	page.get_window().size_changed.connect(_schedule_fit)
	page.resized.connect(_schedule_fit)
	get_node("/root/AppState").font_scale_changed.connect(_schedule_fit.unbind(1))
	_build()

func _motion() -> Node: return get_node("/root/UiMotion")

func _label(parent: Node, caption: String, font_size := 16, color := MUTED, strong := false) -> Label:
	return UI.label(parent, caption, font_size, color, strong)

func _vbox(parent: Node, gap: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	return box

func _spacer(parent: Node, height: int) -> void:
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.custom_minimum_size.y = height
	parent.add_child(space)

func _button(parent: Node, caption: String, callback: Callable, primary := false, outlined := false) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 40)
	parent.add_child(button)
	Styles.button(button, BLUE if primary else Color.WHITE if outlined else Color.TRANSPARENT, primary, false, 16)
	var box := Styles.box(BLUE if primary else Color.WHITE if outlined else Color.TRANSPARENT, 8, BLUE if outlined else Color.TRANSPARENT)
	box.content_margin_left = 16 if not caption.is_empty() else 0
	box.content_margin_right = box.content_margin_left
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, box.duplicate())
	button.add_theme_color_override("font_color", Color.WHITE if primary else BLUE if outlined else MUTED)
	_motion().bind_button(button, primary)
	button.pressed.connect(callback)
	return button

func _build_tabs() -> void:
	var background := PanelContainer.new()
	background.custom_minimum_size.y = 44
	var box := Styles.box(Color("#EBEEF5"), 8)
	box.set_content_margin_all(3)
	background.add_theme_stylebox_override("panel", box)
	column.add_child(background)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	background.add_child(tabs)
	for value in ["add", "requests"]:
		var button := Button.new()
		button.custom_minimum_size.y = 38
		button.text = "添加好友" if value == "add" else "好友申请"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
		var surface := Styles.box(Color.TRANSPARENT, 6)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			button.add_theme_stylebox_override(state, surface)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		tabs.add_child(button)
		var line := ColorRect.new()
		line.color = BLUE
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(line)
		line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		line.offset_left = -32
		line.offset_right = 32
		line.offset_top = -2
		button.pressed.connect(_set_friend_tab.bind(value))
		friend_tabs[value] = button
		tab_surfaces[value] = surface
		tab_lines[value] = line
	_sync_friend_tabs(false)

func _sync_friend_tabs(animate := true) -> void:
	for value in friend_tabs:
		var selected: bool = panel_mode == value
		var button: Button = friend_tabs[value]
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, BLUE if selected else MUTED)
		button.add_theme_font_override("font", get_node("/root/UiResources").bold if selected else theme.default_font)
		button.accessibility_name = button.text + ("，已选中" if selected else "")
		_motion().animate(button, tab_surfaces[value], ^"bg_color", Color.WHITE if selected else Color.TRANSPARENT, 0.16 if animate else 0.0)
		_motion().animate(button, tab_lines[value], ^"modulate:a", 1.0 if selected else 0.0, 0.16 if animate else 0.0)

func _set_friend_tab(value: String) -> void:
	if closing or value == panel_mode: return
	_save_draft()
	_ticket = ""
	searching = false
	panel_mode = value
	_build()
	_sync_friend_tabs()
	scroll_box.scroll_vertical = 0
	_motion().enter(content, 0.13)
	friend_tabs[value].grab_focus()

func _save_draft() -> void:
	if panel_mode == "add":
		if is_instance_valid(query): _friend_query = query.text
		if is_instance_valid(note): _friend_note = note.text

func _build() -> void:
	page._clear(content)
	query = null
	note = null
	send_button = null
	_request_rows.clear()
	if panel_mode == "requests":
		_requests()
		return
	var search_form := _vbox(content, 8)
	_label(search_form, "通过用户 ID 添加", 16, MUTED, true)
	query = LineEdit.new()
	query.placeholder_text = "请输入完整用户 ID"
	query.accessibility_name = "完整用户 ID"
	query.custom_minimum_size.y = 44
	query.max_length = 128
	query.text = _friend_query
	search_form.add_child(query)
	_input_style(query, 52)
	var icon := TextureRect.new()
	icon.texture = preload("res://assets/minimal/icons/user-round.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = MUTED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	query.add_child(icon)
	icon.position = Vector2(14, 12)
	icon.size = Vector2(20, 20)
	query.text_changed.connect(_query_edited)
	query.text_submitted.connect(_search.unbind(1))
	search_button = _button(search_form, "查找用户", _search, true)
	status = _label(search_form, "", 14)
	status.hide()
	_spacer(content, 18)
	UI.rule(content, BORDER)
	_spacer(content, 16)
	_label(content, "搜索结果", 16, MUTED, true)
	_spacer(content, 12)
	result_slot = _vbox(content, 0)
	result_slot.custom_minimum_size.y = 86
	empty_result = _label(result_slot, "输入完整用户 ID，查找后核对身份。", 15)
	empty_result.custom_minimum_size.y = 86
	empty_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_spacer(content, 22)
	_label(content, "申请附言（选填）", 16, MUTED, true)
	_spacer(content, 8)
	note = TextEdit.new()
	note.placeholder_text = "例如：你好，我们是同一门课程的同学"
	note.accessibility_name = "申请附言，最多 100 字"
	note.custom_minimum_size.y = 92
	note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	note.text = _friend_note
	content.add_child(note)
	_input_style(note)
	var note_box: StyleBoxFlat = note.get_theme_stylebox("normal")
	note_box.content_margin_bottom = 28
	counter = _label(note, "", 13)
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	counter.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	counter.offset_left = -68
	counter.offset_right = -12
	counter.offset_top = -26
	counter.offset_bottom = -8
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.text_changed.connect(_note_edited)
	_note_edited()
	_spacer(content, 14)
	_label(content, "昵称用于核对，最终请通过用户 ID 确认对象。", 14)
	_render_result()
	if not store.available(): _show_status(store.unavailable())

func _input_style(input: Control, left := 16) -> void:
	var box := Styles.box(Color.WHITE, 8, BORDER)
	box.set_content_margin_all(12)
	box.content_margin_left = left
	input.add_theme_stylebox_override("normal", box)
	input.add_theme_stylebox_override("read_only", box)
	input.add_theme_font_size_override("font_size", 16)
	input.add_theme_color_override("font_color", INK)
	input.add_theme_color_override("font_placeholder_color", Color("#98A2B3"))
	input.add_theme_color_override("caret_color", BLUE)
	_motion().bind_input(input)
	# Animate a single fine border, without an additional opaque focus layer.
	input.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _note_edited() -> void:
	var breaks := TextServerManager.get_primary_interface().string_get_character_breaks(note.text)
	if breaks.size() > NOTE_LIMIT:
		var line := note.get_caret_line()
		var col := note.get_caret_column()
		note.text = note.text.left(breaks[NOTE_LIMIT - 1])
		note.set_caret_line(mini(line, note.get_line_count() - 1))
		note.set_caret_column(mini(col, note.get_line(note.get_caret_line()).length()))
	_friend_note = note.text
	counter.text = "%d/100" % mini(breaks.size(), NOTE_LIMIT)

func _show_status(message: String) -> void:
	if not is_instance_valid(status): return
	status.text = message
	status.visible = not message.is_empty()

func _query_edited(value: String) -> void:
	_friend_query = value
	_ticket = ""
	searching = false
	_lookup = {}
	_lookup_query = ""
	search_button.disabled = false
	search_button.text = "查找用户"
	_show_status("")
	_render_result()

func _search() -> void:
	if closing or not is_instance_valid(query): return
	var value := query.text.strip_edges()
	if value.is_empty():
		_show_status("请输入完整用户 ID")
		query.grab_focus()
		return
	if value.length() > 32 or value.contains("\n") or value.contains("\t"):
		_show_status("请输入有效的完整用户 ID（不超过 32 个字符）")
		return
	if not store.available():
		if store.account_id.is_empty(): _login()
		else: _show_status(store.unavailable())
		return
	if searching and value == _lookup_query: return
	_save_draft()
	_lookup = {}
	_lookup_query = value
	_render_result()
	searching = true
	search_button.text = "查找中…"
	search_button.disabled = true
	_show_status("")
	_serial += 1
	_ticket = "%d:search:%d" % [get_instance_id(), _serial]
	store.dispatch("find_user", {"public_id": value}, _ticket)

func _render_result() -> void:
	if panel_mode != "add" or not is_instance_valid(result_slot): return
	if is_instance_valid(note): note.editable = true
	for child in result_slot.get_children():
		if child != empty_result:
			result_slot.remove_child(child)
			child.queue_free()
	send_button = null
	empty_result.visible = _lookup.is_empty() or _lookup.get("user", {}).is_empty()
	var state := str(_lookup.get("state", ""))
	empty_result.text = {"": "输入完整用户 ID，查找后核对身份。", "not_found": "未找到用户，请检查 ID", "inaccessible": "当前无法添加该用户。"}.get(state, "无法确认用户状态，请重试。")
	var person: Dictionary = _lookup.get("user", {})
	if person.is_empty(): return
	var card := PanelContainer.new()
	card.name = "SearchResult"
	card.custom_minimum_size.y = 86
	var frame := Styles.box(Color.WHITE, 8, BORDER)
	frame.set_content_margin_all(12)
	frame.content_margin_left = 16
	card.add_theme_stylebox_override("panel", frame)
	result_slot.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)
	_identity(row, person, 58)
	var captions := {"available": "发送申请", "friend": "已是好友", "self": "不能添加自己", "outgoing": "申请已发送", "incoming": "查看申请"}
	send_button = _button(row, captions.get(state, "暂不可添加"), _result_action, false, true)
	send_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	send_button.custom_minimum_size.x = 100
	send_button.disabled = state not in ["available", "friend", "incoming"] or _pending.has("send:" + str(person.get("id", "")))
	if _pending.has("send:" + str(person.get("id", ""))):
		send_button.text = "发送中…"
		if is_instance_valid(note): note.editable = false
	if state == "incoming": _show_status("对方已申请添加你，请在好友申请中处理。")
	if state == "friend": send_button.accessibility_name = "已是好友，打开会话"
	_motion().enter(card, 0.15)

func _identity(parent: Node, person: Dictionary, diameter := 42) -> void:
	var avatar := Avatar.new()
	avatar.custom_minimum_size = Vector2(diameter, diameter)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(avatar)
	avatar.show_profile(person)
	var metadata := _vbox(parent, 4)
	metadata.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := _label(metadata, str(person.get("name", "")), 18, INK, true)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	_label(metadata, "用户 ID：" + str(person.get("public_id", "")), 14)

func _result_action() -> void:
	if closing: return
	if _lookup.get("state") == "friend":
		store.set_tab("recent")
		page._narrow_chat = true
		store.open_peer(str(_lookup.user.id))
		dismiss()
	elif _lookup.get("state") == "incoming": _set_friend_tab("requests")
	else: _request_friend()

func _request_friend() -> void:
	if closing or _lookup.get("state") != "available" or not is_instance_valid(query) or query.text.strip_edges() != _lookup_query: return
	var person: Dictionary = _lookup.get("user", {})
	if str(person.get("id", "")).is_empty(): return
	_note_edited()
	_write("request_friend", {"peer_id": person.id, "note": note.text}, "send:" + str(person.id))
	_render_result()

func _write(action: String, payload: Dictionary, key: String) -> void:
	if closing or _pending.has(key): return
	var operation: String = store.intent(action, payload)
	if operation.is_empty():
		_show_status("无法保存操作标识，尚未提交。请稍后重试。")
		return
	_serial += 1
	var ticket := "%d:write:%d" % [get_instance_id(), _serial]
	_writes[ticket] = {"key": key, "action": action, "payload": payload.duplicate(true)}
	_pending[key] = true
	busy = true
	payload = payload.duplicate(true)
	payload.operation_id = operation
	store.dispatch(action, payload, ticket)

func _response(ticket: String, response: Dictionary) -> void:
	# Keep write bookkeeping during the exit fade: the same window may be reopened.
	if is_queued_for_deletion() or store.epoch != _epoch: return
	if ticket == "%d:read" % get_instance_id():
		if not response.get("ok", false): _request_read_seq = 0
		return
	if ticket == _ticket and not _ticket.is_empty():
		_ticket = ""
		searching = false
		if panel_mode != "add" or query.text.strip_edges() != _lookup_query: return
		search_button.text = "查找用户"
		search_button.disabled = false
		if not response.get("ok", false):
			_show_status(str(response.get("message", "查找失败，请重试。")))
			return
		_lookup = response.duplicate(true)
		_render_result()
		return
	if not _writes.has(ticket): return
	var write: Dictionary = _writes[ticket]
	_writes.erase(ticket)
	_pending.erase(write.key)
	busy = not _writes.is_empty()
	var succeeded: bool = response.get("ok", false)
	if succeeded or response.get("definitive", false): store.forget_intent(write.action, write.payload)
	if write.action == "request_friend":
		if str(_lookup.get("user", {}).get("id", "")) == str(write.payload.peer_id):
			if succeeded:
				var request: Dictionary = response.get("request", {})
				# Older servers return only a message for an already-friend race.
				if request.get("status") == "pending":
					_lookup.state = "incoming" if request.get("direction") == "received" else "outgoing"
				elif request.get("status") == "accepted" or response.get("state") == "friend": _lookup.state = "friend"
				else: _lookup = {}
			_render_result()
			_show_status(str(response.get("message", "申请已发送")) if succeeded else str(response.get("message", "发送失败，请重试。")))
	else:
		_row_feedback[write.key] = str(response.get("message", "已处理" if succeeded else "处理失败，请重试。"))
		if panel_mode == "requests": _requests()

func _requests() -> void:
	page._clear(content)
	_request_rows.clear()
	_requests_hash = JSON.stringify(store.requests).sha256_text()
	status = _label(content, "", 14)
	status.hide()
	if not store.available():
		_show_status(store.unavailable())
		if store.account_id.is_empty(): _button(content, "登录", _login, true)
		return
	for direction in ["received", "sent"]:
		_label(content, "收到的申请" if direction == "received" else "发出的申请", 17, INK, true)
		_spacer(content, 12)
		var count := 0
		for item in store.requests:
			if item.get("direction") != direction: continue
			count += 1
			var card := PanelContainer.new()
			var frame := Styles.box(Color.WHITE, 8, BORDER)
			frame.set_content_margin_all(14)
			card.add_theme_stylebox_override("panel", frame)
			content.add_child(card)
			var stack := _vbox(card, 10)
			var identity := HBoxContainer.new()
			identity.add_theme_constant_override("separation", 12)
			stack.add_child(identity)
			_identity(identity, item.get("peer", {}))
			var message: String = str(item.get("note", ""))
			if not message.is_empty(): _label(stack, message, 14)
			var state := str(item.get("status", ""))
			var time := TimeDisplay.datetime(str(item.get("time_label", "")))
			_label(stack, (time + " · " if not time.is_empty() else "") + {"pending": "待处理" if direction == "received" else "等待对方处理", "accepted": "已接受", "ignored": "已忽略", "invalidated": "已失效"}.get(state, state), 13)
			var key := "request:" + str(item.id)
			if direction == "received":
				card.set_meta("request_seq", item.get("seq", 0))
				_request_rows.append(card)
				if state == "pending":
					var actions := HBoxContainer.new()
					actions.add_theme_constant_override("separation", 10)
					stack.add_child(actions)
					for decision in ["accept", "ignore"]:
						var button := _button(actions, "处理中…" if _pending.has(key) else "接受" if decision == "accept" else "忽略", _respond.bind(str(item.id), decision), false, true)
						button.disabled = _pending.has(key)
			if _row_feedback.has(key): _label(stack, _row_feedback[key], 14, BLUE)
			_spacer(content, 12)
		if count == 0: _label(content, "暂无好友申请", 15)
		_spacer(content, 24)
	if not store.error.is_empty():
		_show_status(store.error)
		_button(content, "重新连接", store.refresh)

func _respond(id: String, decision: String) -> void:
	_write("respond_request", {"request_id": id, "decision": decision}, "request:" + id)
	if panel_mode == "requests": _requests()

func _changed() -> void:
	if store.epoch != _epoch:
		if _login_pending: return
		_finish_close()
		return
	if closing: return
	if panel_mode == "requests" and JSON.stringify(store.requests).sha256_text() != _requests_hash:
		var offset := scroll_box.scroll_vertical
		_requests()
		scroll_box.set_deferred("scroll_vertical", offset)
	if not _lookup.is_empty():
		var peer_id := str(_lookup.get("user", {}).get("id", ""))
		for person in store.friends:
			if str(person.get("id", "")) == peer_id and _lookup.get("state") != "friend":
				_lookup.state = "friend"
				_render_result()

func _login() -> void:
	if closing or _login_pending: return
	var profile := get_node("/root/ProfileStore")
	var provider: Node = profile.provider
	if not is_instance_valid(provider) or not provider.has_method("begin_login"):
		_show_status(store.unavailable())
		return
	_save_draft()
	_login_pending = true
	hide()
	shade.hide()
	var response: Dictionary = await provider.begin_login()
	if closing or not is_inside_tree(): return
	_login_pending = false
	_epoch = store.epoch
	_lookup = {}
	_lookup_query = ""
	_ticket = ""
	_writes.clear()
	_pending.clear()
	busy = false
	_build()
	shade.show()
	present()
	if not response.get("ok", false): _show_status(str(response.get("message", "登录未完成，输入已保留。")))

func _process(delta: float) -> void:
	_read_timer += delta
	if _read_timer < 0.5 or panel_mode != "requests" or not visible or not has_focus() or closing: return
	_read_timer = 0
	var viewport := scroll_box.get_global_rect()
	var reached := _request_read_seq
	for row in _request_rows:
		if is_instance_valid(row) and viewport.encloses(row.get_global_rect()): reached = maxi(reached, int(row.get_meta("request_seq", 0)))
	if reached > _request_read_seq:
		_request_read_seq = reached
		store.dispatch("mark_requests_read", {"through_seq": reached}, "%d:read" % get_instance_id())

func _schedule_fit() -> void:
	if _fit_queued or closing: return
	_fit_queued = true
	_fit.call_deferred()

func _fit() -> void:
	_fit_queued = false
	if closing or not is_inside_tree(): return
	_fit_window()

func _fit_window(opening := false) -> void:
	_motion().cancel(self, false)
	var owner := get_tree().root
	var bounds := owner.get_visible_rect()
	var pixels_per_unit := owner.get_stretch_transform().get_scale().x if is_embedded() else 1.0
	_ui_scale = page.canvas.get_global_transform_with_canvas().get_scale().x
	if not is_embedded():
		bounds = Rect2(Vector2(owner.position), Vector2(owner.size))
		_ui_scale *= owner.get_stretch_transform().get_scale().x
	# Retain readable text on small screens; excess form height scrolls internally.
	_ui_scale = maxf(0.85 / pixels_per_unit, minf(_ui_scale, bounds.size.y / (BASE_SIZE.y + 48)))
	var safe := bounds.grow(-20.0 / pixels_per_unit)
	var target := Vector2i((BASE_SIZE * _ui_scale).min(safe.size))
	min_size = Vector2i(Vector2(300, 240) * _ui_scale).min(target)
	var origin := Vector2i(bounds.position + (bounds.size - Vector2(target)) * 0.5)
	if opening: popup(Rect2i(origin, target))
	size = target
	position = origin
	# Keep the Window viewport 1:1. Godot draws an opaque letterbox rectangle when
	# fractional viewport scaling makes its transformed bounds differ from size.
	# Scale the transparent Control content instead, preserving exact window bounds.
	content_scale_factor = 1.0
	panel.scale = Vector2.ONE * _ui_scale
	panel.size = Vector2(size) / _ui_scale

func present() -> void:
	_fit_window(true)
	_motion().enter(shade, 0.17)
	_motion().enter(panel, 0.18)
	var destination := position
	if not _motion().reduced(): position.y += maxi(1, roundi(4 * _ui_scale))
	_motion().animate(self, self, ^"position", destination, 0.18)
	(query if panel_mode == "add" else friend_tabs.requests).grab_focus()

func reopen() -> void:
	if not closing: return
	_close_serial += 1
	closing = false
	searching = false
	if panel_mode == "add":
		search_button.disabled = false
		search_button.text = "查找用户"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	present()

func _window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			set_input_as_handled()
			dismiss()
		elif event.keycode == KEY_TAB and is_instance_valid(note) and gui_get_focus_owner() == note:
			set_input_as_handled()
			if event.shift_pressed and is_instance_valid(send_button) and not send_button.disabled: send_button.grab_focus()
			elif event.shift_pressed: search_button.grab_focus()
			else: close_button.grab_focus()

func dismiss() -> void:
	if closing: return
	closing = true
	_ticket = ""
	_close_serial += 1
	var generation := _close_serial
	_motion().animate(self, panel, ^"modulate:a", 0.0, 0.12, true)
	_motion().animate(self, shade, ^"modulate:a", 0.0, 0.12, true)
	if not _motion().reduced(): await get_tree().create_timer(0.12).timeout
	if generation == _close_serial: _finish_close()

func _finish_close() -> void:
	if is_queued_for_deletion(): return
	closing = true
	_close_serial += 1
	hide()
	if is_instance_valid(shade):
		shade.queue_free()
		shade = null
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(shade): shade.queue_free()
