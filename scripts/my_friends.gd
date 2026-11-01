extends "res://scripts/minimal_page.gd"
const CardArtwork = preload("res://scripts/card_artwork.gd")
const Avatar = preload("res://scripts/profile_avatar.gd")
const Composer = preload("res://scripts/social_composer.gd")
const Dialog = preload("res://scripts/social_dialog.gd")
const ConversationActionsDialog = preload("res://scripts/conversation_actions_dialog.gd")
const GiftDialog = preload("res://scripts/collection_gift_dialog.gd")
const TradeDialog = preload("res://scripts/trade_dialog.gd")
const WishlistDialog = preload("res://scripts/wishlist_dialog.gd")
var store: Node
var collection: Node
var search: LineEdit
var contacts: Control
var contact_scroll: ScrollContainer
var contact_rows: VBoxContainer
var contact_status: Label
var friends_tab: Button
var recent_tab: Button
var recent_menu: Button
var chat: Control
var chat_head: Control
var chat_name: Label
var chat_id: Label
var chat_avatar: TextureRect
var wants_button: Button
var more_button: Button
var add_peer_button: Button
var back_list: Button
var transcript: ScrollContainer
var message_rows: VBoxContainer
var composer: TextEdit
var send_button: Button
var compose_hint: Label
var new_messages: Button
var connection: Label
var bell: Button
var add_button: Button
var separator: ColorRect
var dialog: Node
var gift_dialog: Window
var _dialog_focus: WeakRef
var _shown := ""
var _generation := -1
var _render_queued := false
var _restore_serial := 0
var _rendering := false
var _narrow_chat := false
var _row_hash := ""
var _contacts_hash := ""
var _history_anchor: Dictionary = {}
var _read_timer := 0.0
var _bubble_nodes: Array = []
var _last_message_seq := 0

func _ready() -> void:
	active_nav = "FriendsButton"
	store = get_node("/root/AppServices").social_store()
	collection = get_node("/root/AppServices").collection_store()
	store.active = true
	var navigation := get_node("/root/PageRouter")
	if navigation.friends_notifications_requested:
		store.bell_requested = true
		navigation.friends_notifications_requested = false
	store.changed.connect(_state_changed)
	store.messages_changed.connect(_messages_changed)
	store.completed.connect(_completed)
	super._ready()
	store.refresh()
	_handle_bell.call_deferred()

func _exit_tree() -> void:
	store.active = false
	_save_position()
	if is_instance_valid(dialog):
		dialog.dismiss()
		if is_instance_valid(dialog) and dialog.get_script() == ConversationActionsDialog: dialog._finish_close()
	if is_instance_valid(gift_dialog):
		gift_dialog.dismiss()

func _build_content() -> void:
	bell = _button(body, "Bell", "", _bell)
	bell.icon = _texture("res://assets/profile/bell.svg")
	bell.accessibility_name = "查看未读消息与通知"
	add_button = _button(body, "AddFriend", "", show_panel.bind("add", {}))
	add_button.icon = _texture("res://assets/profile/user-plus.svg")
	add_button.accessibility_name = "添加好友与好友申请"
	connection = _label(body, "", 16, muted_color)
	connection.name = "ConnectionStatus"
	connection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contacts = Control.new()
	contacts.name = "Contacts"
	body.add_child(contacts)
	search = _search(contacts, "搜索好友或对话", _filter_changed, Rect2())
	search.add_theme_font_size_override("font_size", 18)
	friends_tab = _button(contacts, "FriendsTab", "好友", store.set_tab.bind("friends"))
	recent_tab = _button(contacts, "RecentTab", "最近对话", store.set_tab.bind("recent"))
	recent_menu = _button(contacts, "RecentMenu", "⋯", show_panel.bind("recent_menu", {}))
	recent_menu.accessibility_name = "最近对话更多操作"
	contact_status = _label(contacts, "", 17, muted_color)
	contact_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contact_scroll = ScrollContainer.new()
	contact_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	contacts.add_child(contact_scroll)
	contact_rows = VBoxContainer.new()
	contact_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contact_rows.add_theme_constant_override("separation", 4)
	contact_scroll.add_child(contact_rows)
	separator = _line(body, Rect2())
	chat = Control.new()
	chat.name = "Chat"
	body.add_child(chat)
	chat_head = Control.new()
	chat.add_child(chat_head)
	chat_avatar = Avatar.new()
	chat_head.add_child(chat_avatar)
	chat_name = _label(chat_head, "", 24, text_color, Rect2(), true)
	chat_id = _label(chat_head, "", 16, muted_color)
	chat_id.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	wants_button = _button(chat_head, "Wishlist", "想要清单", _peer_panel.bind("wishlist"))
	more_button = _button(chat_head, "More", "⋯", _peer_panel.bind("peer_menu"))
	more_button.accessibility_name = "会话更多操作"
	add_peer_button = _button(chat_head, "RequestFriend", "添加好友", _peer_panel.bind("request_friend"))
	back_list = _button(chat_head, "BackToList", "← 列表", _show_list)
	transcript = ScrollContainer.new()
	transcript.name = "Transcript"
	transcript.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat.add_child(transcript)
	message_rows = VBoxContainer.new()
	message_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_rows.add_theme_constant_override("separation", 18)
	transcript.add_child(message_rows)
	composer = Composer.new()
	composer.name = "Composer"
	composer.placeholder_text = "输入消息…"
	composer.accessibility_name = "输入消息，Enter 发送，Shift Enter 换行"
	composer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	composer.add_theme_color_override("font_color", text_color)
	composer.add_theme_color_override("font_placeholder_color", muted_color)
	composer.add_theme_font_size_override("font_size", 20)
	var frame := _style(surface, 8, border)
	frame.set_content_margin_all(14)
	composer.add_theme_stylebox_override("normal", frame)
	Styles.apply_focus(composer, composer.get_theme_stylebox("normal") as StyleBoxFlat)
	chat.add_child(composer)
	composer.text_changed.connect(_draft_changed)
	composer.submit.connect(_send)
	send_button = _primary(chat, "发送", _send, Rect2())
	compose_hint = _label(chat, "", 16, muted_color)
	new_messages = _button(chat, "NewMessages", "有新消息 ↓", _to_bottom)
	new_messages.hide()
	_shown = ""
	_row_hash = ""
	_contacts_hash = ""
	_state_changed()

func _layout_content(width: float) -> void:
	if not is_instance_valid(chat):
		return
	var h := maxf(400, scroll.size.y)
	content_height = h
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_rect(bell, Rect2(width - 54, 0, 50, 46))
	_rect(add_button, Rect2(width - 116, 0, 50, 46))
	_rect(connection, Rect2(0, 0, width - 140, 46))
	var content_top := 64.0
	var narrow := width < 930
	var left := clampf(width * 0.29, 270, 350)
	contacts.visible = not narrow or not _narrow_chat
	chat.visible = not narrow or _narrow_chat
	separator.visible = not narrow
	if narrow:
		left = width
	_rect(contacts, Rect2(0, content_top, left, h - content_top))
	_rect(search, Rect2(0, 0, left - (42 if store.tab == "recent" else 0), 54))
	_rect(recent_menu, Rect2(left - 38, 4, 36, 42))
	_rect(friends_tab, Rect2(0, 68, 80, 44))
	_rect(recent_tab, Rect2(104, 68, 122, 44))
	_tab(friends_tab, store.tab == "friends", 44, 41)
	_tab(recent_tab, store.tab == "recent", 70, 41)
	_rect(contact_status, Rect2(0, 125, left, 66))
	_rect(contact_scroll, Rect2(0, 122, left, maxf(80, contacts.size.y - 130)))
	_rect(separator, Rect2(left + 22, content_top, 1, h - content_top))
	var x := 0.0 if narrow else left + 46
	_rect(chat, Rect2(x, content_top, width - x, h - content_top))
	var w := chat.size.x
	var ch := chat.size.y
	_rect(chat_head, Rect2(0, 0, w, 104))
	back_list.visible = narrow
	_rect(back_list, Rect2(0, 0, 100, 40))
	var offset := 44.0 if narrow else 0.0
	_rect(chat_avatar, Rect2(offset, 8, 48, 48))
	chat_avatar.visible = not narrow and not store.conversation(store.selected).is_empty()
	var name_x := 62.0 if not narrow else 110.0
	var actions_width := 192.0 if wants_button.visible or add_peer_button.visible else 58.0 if more_button.visible else 0.0
	_rect(chat_name, Rect2(name_x, 0, w - name_x - actions_width, 40))
	_rect(chat_id, Rect2(62 if not narrow else 0, 43, w - 70, 28))
	_rect(wants_button, Rect2(w - 176, 4, 124, 44))
	_rect(more_button, Rect2(w - 42, 4, 40, 44))
	_rect(add_peer_button, Rect2(w - 190, 4, 140, 44))
	var input_height := 140.0 if composer.visible else 44.0
	_rect(transcript, Rect2(0, 96, w, maxf(70, ch - 108 - input_height)))
	_rect(composer, Rect2(0, ch - 132, w - 108, 92))
	_rect(send_button, Rect2(w - 96, ch - 132, 96, 92))
	_rect(compose_hint, Rect2(0, ch - 34, w, 30))
	_rect(new_messages, Rect2(w - 160, ch - input_height - 48, 156, 40))
	for child in message_rows.get_children():
		if child is HBoxContainer:
			for bubble in child.get_children():
				if bubble is PanelContainer:
					bubble.custom_minimum_size.x = minf(w - 18, 520 if bubble.get_meta("business", false) else w * 0.74)

func _state_changed() -> void:
	if not is_inside_tree() or not is_instance_valid(search):
		return
	if _generation != store.epoch:
		_generation = store.epoch
		_shown = ""
		_narrow_chat = false
		search.text = ""
		if is_instance_valid(dialog):
			dialog.dismiss()
		if is_instance_valid(gift_dialog):
			gift_dialog.dismiss()
	connection.text = "正在连接…" if store.loading else store.error
	bell.text = str(store.unread_total()) if store.unread_total() > 0 else ""
	bell.accessibility_name = "消息与通知，%d 条未读" % store.unread_total()
	recent_menu.visible = store.tab == "recent"
	add_button.accessibility_name = "添加好友与好友申请，%d 条待处理" % store.pending_requests if store.pending_requests > 0 else "添加好友与好友申请"
	_render_contacts()
	if _shown != store.selected:
		_save_position()
		_shown = store.selected
		composer.text = str(store.drafts.get(_shown, ""))
		_history_anchor = {}
		_row_hash = ""
		_last_message_seq = 0
		new_messages.hide()
		if not _shown.is_empty() and not store.history_loaded.has(_shown) and not store.history_busy.has(_shown):
			store.load_history.call_deferred(_shown)
	_sync_header()
	_queue_messages()
	_layout()
	_handle_bell()

func _filter_changed(_query: String) -> void:
	_render_contacts()

func _render_contacts() -> void:
	var rows: Array = store.list_items(search.text)
	var fingerprint := JSON.stringify([rows, store.conversations, store.selected, store.tab, search.text, store.loading, store.error, dark]).sha256_text()
	if fingerprint == _contacts_hash:
		return
	_contacts_hash = fingerprint
	var focused_peer := ""
	var focus := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and focus.get_parent() == contact_rows:
		focused_peer = str(focus.get_meta("peer_id", ""))
	var old_scroll := contact_scroll.scroll_vertical
	_clear(contact_rows)
	contact_status.visible = rows.is_empty()
	contact_status.text = "正在读取联系人…" if store.loading else store.unavailable() if not store.available() else "连接暂时失败，正在等待重新连接。" if not store.error.is_empty() else "没有匹配的好友或对话。" if not search.text.is_empty() else "还没有好友。点击添加好友，通过用户 ID 查找。" if store.tab == "friends" else "尚无会话，连接后将自动获取通知通道。"
	for item in rows:
		var is_friend: bool = store.tab == "friends"
		var person: Dictionary = item if is_friend else item.get("peer", {})
		var official: bool = not is_friend and item.get("kind") == "system"
		var cid := str(item.get("conversation_id", "")) if is_friend else str(item.id)
		var conversation_data: Dictionary = store.conversation(cid) if is_friend else item
		var name_text: String = "系统通知" if official else store.display_name(person)
		var button := _button(contact_rows, "Contact", "", store.open_peer.bind(str(item.id)) if is_friend else _select.bind(cid))
		button.custom_minimum_size.y = 88
		button.accessibility_name = name_text + ("，官方通知" if official else "")
		button.set_meta("peer_id", person.get("id", ""))
		if is_friend:
			button.pressed.connect(func(): _narrow_chat = true)
		button.add_theme_stylebox_override("normal", _style((Tokens.DARK_SOFT if dark else Tokens.SOFT) if cid == store.selected and not cid.is_empty() else Color.TRANSPARENT, 8))
		if not focused_peer.is_empty() and focused_peer == str(person.get("id", "")):
			button.grab_focus.call_deferred()
		var avatar := Avatar.new()
		button.add_child(avatar)
		avatar.show_profile(person)
		_rect(avatar, Rect2(12, 18, 46, 46))
		var title_label := _label(button, name_text + ("  官方" if official else ""), 20, text_color, Rect2(70, 8, maxf(80, contacts.size.x - 148), 32), true)
		title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		title_label.offset_right = -70
		var summary := str(conversation_data.get("summary", "尚无消息，打个招呼吧" if is_friend else "暂无通知" if official else "尚无消息"))
		var sub := _label(button, ("免打扰 · " if conversation_data.get("muted", false) else "") + summary, 16, muted_color, Rect2(70, 44, 200, 30))
		sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
		sub.offset_right = -24
		var stamp := _label(button, str(conversation_data.get("time_label", "")), 13, muted_color, Rect2())
		stamp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_rect(stamp, Rect2(-66, 9, 62, 26))
		if int(conversation_data.get("unread", 0)) > 0:
			var badge := _label(button, str(conversation_data.unread), 14, _accent(), Rect2())
			badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			_rect(badge, Rect2(-30, 48, 28, 24))
	contact_scroll.set_deferred("scroll_vertical", old_scroll)

func _select(id: String) -> void:
	_narrow_chat = true
	store.select(id)

func _sync_header() -> void:
	var item: Dictionary = store.conversation(_shown)
	var official: bool = item.get("kind") == "system"
	var person: Dictionary = item.get("peer", {})
	var friendly: bool = item.get("is_friend", false)
	chat_name.text = "系统通知 · 官方" if official else store.display_name(person) if not person.is_empty() else ""
	chat_id.text = "来自服务端的官方通知，只读通道" if official else (str(person.get("public_id", "")) + (" · 已拉黑" if item.get("blocked_by_me", false) else " · 未添加好友" if not friendly else ""))
	if item.is_empty():
		chat_id.text = ""
	chat_avatar.show_profile(person)
	wants_button.visible = friendly and not official
	more_button.visible = not item.is_empty() and not official
	add_peer_button.visible = not item.is_empty() and not friendly and not official and not item.get("blocked_by_me", false)
	composer.visible = not item.is_empty() and not official
	send_button.visible = composer.visible
	_draft_changed()
	if official:
		compose_hint.text = "系统通知无需回复"
	elif item.is_empty():
		compose_hint.text = ""

func _draft_changed() -> void:
	if _shown.is_empty():
		return
	store.drafts[_shown] = composer.text
	var reason: String = store.send_reason(_shown, composer.text)
	send_button.disabled = not reason.is_empty()
	var feedback := send_button.get_node_or_null("UIFeedback")
	if feedback != null:
		feedback._check_disabled()
	send_button.queue_redraw()
	compose_hint.text = reason if not reason.is_empty() and reason != "请输入消息。" else "Enter 发送，Shift+Enter 换行  ·  %d/%d" % [composer.text.length(), store.TEXT_LIMIT]

func _send() -> void:
	if composer.composing or composer.has_ime_text():
		return
	var submitted := composer.text
	if not store.send_reason(_shown, submitted).is_empty():
		return
	# A provider may complete synchronously. Clear this submission before dispatch
	# so a synchronous state refresh cannot restore it as a fresh draft.
	composer.text = ""
	var id: String = store.send_text(_shown, submitted)
	if id.is_empty() and composer.text.is_empty():
		composer.text = submitted
	_draft_changed()

func _messages_changed(id: String) -> void:
	if id == _shown:
		_queue_messages()

func _queue_messages() -> void:
	if not _render_queued:
		_render_queued = true
		_render_messages.call_deferred()

func _render_messages() -> void:
	_render_queued = false
	if not is_inside_tree():
		return
	if store.conversation(_shown).is_empty():
		_clear(message_rows)
		_bubble_nodes.clear()
		_row_hash = ""
		_rendering = false
		new_messages.hide()
		return
	var rows: Array = store.messages.get(_shown, [])
	var fingerprint := JSON.stringify([_shown, rows, store.trades, store.history_errors.get(_shown), store.history_busy.get(_shown), store.history_before.get(_shown)]).sha256_text()
	if fingerprint == _row_hash:
		return
	var first := _row_hash.is_empty()
	var newest_seq := 0
	for message in rows:
		newest_seq = maxi(newest_seq, int(message.get("seq", 0)))
	var received_new := newest_seq > _last_message_seq
	_last_message_seq = newest_seq
	_row_hash = fingerprint
	var bottom := _at_bottom()
	var anchor: Dictionary = _anchor() if not first else store.positions.get(_shown, {})
	_rendering = true
	_clear(message_rows)
	_bubble_nodes.clear()
	if store.history_busy.get(_shown, false):
		_text(message_rows, "正在加载消息…", 16, muted_color)
	elif store.history_errors.has(_shown):
		_text(message_rows, str(store.history_errors[_shown]), 18, muted_color)
		_action(message_rows, "重试加载", store.load_history.bind(_shown))
	elif not str(store.history_before.get(_shown, "")).is_empty():
		_action(message_rows, "加载更早消息", _older)
	if rows.is_empty() and not store.history_busy.get(_shown, false):
		_text(message_rows, "暂无系统通知" if store.conversation(_shown).get("kind") == "system" else "还没有聊天记录", 20, muted_color)
	var last_date := ""
	for message in rows:
		var date := str(message.get("date_label", ""))
		if date != last_date and not date.is_empty():
			var date_label := _text(message_rows, date, 15, muted_color)
			date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			last_date = date
		_message(message)
	_layout()
	_restore_serial += 1
	_restore_view.call_deferred(_restore_serial, _shown, anchor, (bottom and not first) or (first and anchor.is_empty()))
	if received_new and not bottom and not first and _history_anchor.is_empty():
		new_messages.show()
	_history_anchor = {}

func _message(message: Dictionary) -> void:
	var row := HBoxContainer.new()
	message_rows.add_child(row)
	row.set_meta("message_id", message.get("id", message.get("client_id", "")))
	row.set_meta("seq", message.get("seq", 0))
	_bubble_nodes.append(row)
	var mine: bool = message.get("sender_id") == store.account_id
	var business: bool = message.get("type") != "text"
	if mine and not business:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	var panel := PanelContainer.new()
	panel.set_meta("business", business)
	var bubble_color: Color = surface if business else (Tokens.DARK_SOFT if mine else Color("#202C3C")) if dark else Tokens.SOFT if mine else Color("#F5F6F8")
	var frame := _style(bubble_color, 8, border if business else Color.TRANSPARENT)
	frame.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", frame)
	row.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	match str(message.get("type", "text")):
		"text":
			_text(column, str(message.get("text", "")), 20, text_color)
		"trade":
			var trade: Dictionary = store.trades.get(str(message.get("record_id", "")), {})
			_text(column, "换卡邀请  ·  " + trade_status(str(trade.get("status", ""))), 21, text_color, true)
			if not trade.is_empty():
				_trade_terms(column, trade)
				if trade.get("status") == "pending":
					if trade.get("recipient_id") == store.account_id:
						var actions := HBoxContainer.new()
						column.add_child(actions)
						_action(actions, "拒绝", show_panel.bind("trade_reject", {"trade": trade}))
						_action(actions, "查看并确认", show_panel.bind("trade_review", {"trade": trade}), true)
					else:
						_text(column, "等待对方确认", 17, muted_color)
						_action(column, "取消邀请", show_panel.bind("trade_cancel", {"trade": trade}))
				else:
					_text(column, str(trade.get("result_label", "")), 17, muted_color)
			else:
				_action(column, "读取交易详情", show_panel.bind("trade_detail", {"record_id": message.get("record_id", "")}))
		"gift":
			_text(column, str(message.get("title", "赠送记录")), 21, text_color, true)
			_text(column, str(message.get("summary", "")), 18, muted_color)
			_action(column, "查看赠送详情", show_panel.bind("gift_detail", {"record_id": message.get("record_id", "")}))
		"notification":
			_text(column, str(message.get("title", "系统通知")), 21, text_color, true)
			_text(column, str(message.get("body", "")), 19, text_color)
			var event := str(message.get("event", ""))
			if event in ["friend_request", "trade", "gift"]:
				_action(column, "查看详情", _notification_detail.bind(event, str(message.get("record_id", ""))))
		_:
			_text(column, "当前版本无法显示此消息，请更新客户端。", 18, muted_color)
	var state := str(message.get("state", "sent"))
	_text(column, str(message.get("time_label", "")) + (" · 发送中…" if state == "sending" else " · 发送失败" if state == "failed" else " · 已发送" if mine and not business else ""), 14, muted_color)
	if state == "failed":
		_text(column, str(message.get("error", "")), 16, muted_color)
		_action(column, "重试发送", store.retry_text.bind(_shown, str(message.client_id)))
	if not mine or business:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

func _trade_terms(parent: Node, trade: Dictionary) -> void:
	var outgoing: Array = trade.get("give", []) if trade.get("initiator_id") == store.account_id else trade.get("receive", [])
	var incoming: Array = trade.get("receive", []) if trade.get("initiator_id") == store.account_id else trade.get("give", [])
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	parent.add_child(split)
	for part in [["我送出", outgoing], ["我获得", incoming]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		split.add_child(column)
		_text(column, part[0], 16, muted_color)
		for line in part[1]:
			card_summary(column, str(line.get("card_id", "")), int(line.get("quantity", 0)))

func card_summary(parent: Node, id: String, amount: int) -> void:
	var card: Dictionary = collection.card(id)
	var row := HBoxContainer.new()
	row.name = "CardSummary"
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var art := CardArtwork.create(row, card, Rect2())
	art.custom_minimum_size = Vector2(64, 77)
	art.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var metadata := VBoxContainer.new()
	metadata.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metadata.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	metadata.custom_minimum_size.x = 110
	metadata.add_theme_constant_override("separation", 6)
	row.add_child(metadata)
	_text(metadata, "%s ×%d" % [card.get("name", id), amount], 18, text_color)
	_text(metadata, CardArtwork.season_title(collection.season(str(card.get("season_id", "")))), 15, muted_color)

func trade_status(value: String) -> String:
	return {"pending": "待确认", "completed": "已完成", "rejected": "已拒绝", "cancelled": "已取消", "invalidated": "已失效", "expired": "已过期"}.get(value, "待加载")

func _notification_detail(event: String, id: String) -> void:
	show_panel("requests" if event == "friend_request" else "trade_detail" if event == "trade" else "gift_detail", {"record_id": id})

func _anchor() -> Dictionary:
	for row in _bubble_nodes:
		if is_instance_valid(row) and row.position.y + row.size.y >= transcript.scroll_vertical:
			return {"id": row.get_meta("message_id"), "offset": row.position.y - transcript.scroll_vertical, "bottom": _at_bottom()}
	return {}

func _save_position() -> void:
	if not _shown.is_empty() and is_instance_valid(transcript):
		store.positions[_shown] = _anchor()

func _restore_view(serial: int, id: String, anchor: Dictionary, bottom: bool) -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	if not is_inside_tree() or serial != _restore_serial or id != _shown:
		return
	if bottom or anchor.get("bottom", false):
		transcript.scroll_vertical = int(transcript.get_v_scroll_bar().max_value)
	else:
		for row in _bubble_nodes:
			if row.get_meta("message_id") == anchor.get("id"):
				transcript.scroll_vertical = int(row.position.y - float(anchor.get("offset", 0)))
	_rendering = false

func _older() -> void:
	_history_anchor = _anchor()
	store.load_history(_shown, true)

func _at_bottom() -> bool:
	return transcript.scroll_vertical >= transcript.get_v_scroll_bar().max_value - transcript.size.y - 24

func _to_bottom() -> void:
	transcript.scroll_vertical = int(transcript.get_v_scroll_bar().max_value)
	new_messages.hide()

func _process(delta: float) -> void:
	_read_timer += delta
	if _read_timer < 0.5 or not is_instance_valid(transcript):
		return
	_read_timer = 0
	if _rendering or not chat.is_visible_in_tree() or not get_tree().root.has_focus() or is_instance_valid(dialog) or is_instance_valid(gift_dialog):
		return
	var seq := 0
	for row in _bubble_nodes:
		if row.position.y + row.size.y <= transcript.scroll_vertical + transcript.size.y and row.position.y + row.size.y >= transcript.scroll_vertical:
			seq = maxi(seq, int(row.get_meta("seq", 0)))
	if _at_bottom():
		new_messages.hide()
	store.mark_read(_shown, seq)

func _show_list() -> void:
	_narrow_chat = false
	_layout()

func consume_back_action() -> bool:
	if is_instance_valid(dialog):
		dialog.dismiss()
		return true
	if is_instance_valid(gift_dialog):
		gift_dialog.dismiss()
		return true
	if _narrow_chat and scroll.size.x < 930:
		_show_list()
		return true
	return false

func _bell() -> void:
	store.bell_requested = true
	_handle_bell()

func _handle_bell() -> void:
	if not store.bell_requested or store.loading:
		return
	store.bell_requested = false
	store.set_tab("recent")
	var id: String = store.bell_target()
	if not id.is_empty():
		_select(id)
	elif store.request_unread > 0:
		show_panel("requests", {})

func _peer_panel(mode: String) -> void:
	var item: Dictionary = store.conversation(_shown)
	show_panel(mode, {"peer": item.get("peer", {}), "conversation": item})

func show_panel(mode: String, context: Dictionary = {}) -> void:
	if mode == "peer_menu":
		var current: Dictionary = store.conversation(str(context.get("conversation", {}).get("id", "")))
		if current.is_empty() or current.get("kind") == "system" or str(current.get("peer", {}).get("id", "")).is_empty(): return
		context = {"peer": current.peer.duplicate(true), "conversation": current.duplicate(true)}
	if is_instance_valid(dialog) and dialog.get_script() == ConversationActionsDialog and dialog.closing: dialog._finish_close()
	if is_instance_valid(dialog) and dialog.get_script() == TradeDialog and dialog.closing: dialog._finish_close()
	if is_instance_valid(gift_dialog) and gift_dialog.closing: gift_dialog._finish_close()
	if is_instance_valid(dialog) or is_instance_valid(gift_dialog):
		return
	var focus := get_viewport().gui_get_focus_owner()
	_dialog_focus = weakref(more_button) if mode == "peer_menu" else weakref(focus) if focus != null else null
	if mode == "gift":
		open_gift("", context.get("peer", {}))
		return
	dialog = WishlistDialog.new() if mode == "wishlist" else ConversationActionsDialog.new() if mode == "peer_menu" else TradeDialog.new() if mode in ["exchange", "trade_review", "trade_detail", "trade_cancel", "trade_reject"] else Dialog.new()
	dialog.page = self
	dialog.store = store
	dialog.panel_mode = mode
	dialog.context = context.duplicate(true)
	dialog.closed.connect(_dialog_closed)
	add_child(dialog)
	dialog.present()

func open_conversation_transfer(action: String, conversation_id: String, peer_id: String, epoch: int) -> void:
	# Recheck the target after the old menu's exit animation and deferred cleanup.
	if not is_inside_tree() or get_tree().current_scene != self or store.epoch != epoch or store.selected != conversation_id: return
	if action not in ["gift", "exchange"] or not store.available(): return
	var current: Dictionary = store.conversation(conversation_id)
	if current.get("kind") == "system" or not current.get("is_friend", false) or current.get("blocked_by_me", false): return
	if str(current.get("peer", {}).get("id", "")) != peer_id or is_instance_valid(dialog) or is_instance_valid(gift_dialog): return
	more_button.grab_focus()
	_dialog_focus = weakref(more_button)
	if action == "gift": open_gift("", current.peer)
	else: show_panel("exchange", {"peer": current.peer, "conversation": current})

func _dialog_closed() -> void:
	var from_conversation: bool = is_instance_valid(dialog) and dialog.get_script() == ConversationActionsDialog
	dialog = null
	var focus: Control = more_button if from_conversation else _dialog_focus.get_ref() if _dialog_focus != null else null
	if is_instance_valid(focus) and focus.is_inside_tree() and focus.is_visible_in_tree():
		focus.grab_focus()
	elif is_instance_valid(add_button) and add_button.is_inside_tree():
		add_button.grab_focus()

func open_gift(id: String, person: Dictionary) -> void:
	if is_instance_valid(dialog):
		dialog.dismiss()
		if is_instance_valid(dialog) and dialog.get_script() == TradeDialog: dialog._finish_close()
	if is_instance_valid(gift_dialog) and gift_dialog.closing: gift_dialog._finish_close()
	if is_instance_valid(gift_dialog):
		return
	if not id.is_empty():
		var rule: Dictionary = collection.gift_rule(id)
		if int(rule.max) <= 0:
			show_panel("notice", {"message": rule.reason})
			return
	gift_dialog = GiftDialog.new()
	gift_dialog.configure(self, collection, id, person)
	gift_dialog.closed.connect(func(): gift_dialog = null; _dialog_closed())
	add_child(gift_dialog)
	gift_dialog.present()

func _completed(ticket: String, response: Dictionary) -> void:
	if ticket == "open_peer" and not response.get("ok", false):
		show_panel("notice", {"message": response.get("message", "无法打开会话。")})

func _text(parent: Node, caption: String, font_size: int, color: Color, strong := false) -> Label:
	var label := _label(parent, caption, font_size, color, Rect2(), strong)
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _action(parent: Node, caption: String, action: Callable, primary := false) -> Button:
	var button := _button(parent, "Action", caption, action)
	_style_button(button, BLUE if primary else Color.TRANSPARENT, primary)
	button.custom_minimum_size = Vector2(88, 42)
	button.add_theme_font_size_override("font_size", 18)
	return button

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
