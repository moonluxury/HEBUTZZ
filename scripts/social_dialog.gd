extends Window
const CardArtwork = preload("res://scripts/card_artwork.gd")
const Styles = preload("res://scripts/ui_styles.gd")
## All I/O lives in SocialStore; a closed window never owns an awaited request.
signal closed
var page: Control
var store: Node
var panel_mode := ""
var context: Dictionary = {}
var column: VBoxContainer
var content: VBoxContainer
var status: Label
var panel: PanelContainer
var scroll_box: ScrollContainer
var shade: ColorRect
var first_focus: Control
var heading_label: Label
var friend_tabs: Dictionary = {}
var _friend_query := ""
var query: LineEdit
var note: TextEdit
var give: OptionButton
var receive: OptionButton
var give_amount: SpinBox
var receive_amount: SpinBox
var confirmation: Button
var closing := false
var busy := false
var _epoch := 0
var _serial := 0
var _ticket := ""
var _handler := ""
var _operation: Dictionary = {}
var _action_name := ""
var _record_cursor := ""
var _record_rows: Array = []
var _selected_messages: Array = []
var _report_reason: OptionButton
var _read_timer := 0.0
var _request_rows: Array = []
var _request_read_seq := 0
var _requests_hash := ""
var _inventory_requested := false
var _waiting_inventory := false

func _ready() -> void:
	_epoch = store.epoch
	transient = true
	exclusive = true
	borderless = true
	visible = false
	theme = page.theme
	min_size = Vector2i(340, 260)
	title = {"add": "添加好友", "requests": "好友申请", "peer_menu": "会话操作", "recent_menu": "最近对话", "wishlist": "想要清单", "gift": "赠送卡牌", "exchange": "发起换卡", "trade_review": "核对换卡条款", "trade_detail": "换卡详情", "gift_detail": "赠送详情", "records": "换卡记录", "profile": "查看资料", "remark": "修改备注", "blacklist": "黑名单", "report": "举报", "request_friend": "添加好友", "remove": "删除好友", "block": "拉黑", "trade_cancel": "取消邀请", "trade_reject": "拒绝邀请"}.get(panel_mode, "提示")
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame: StyleBoxFlat = page._style(page.surface, 8, page.border)
	frame.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", frame)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll_box = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	heading_label = page._text(heading, title, 27, page.text_color, true)
	first_focus = action(heading, "关闭", dismiss)
	if panel_mode in ["add", "requests"]:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 12)
		column.add_child(tabs)
		for value in ["add", "requests"]:
			var button := action(tabs, "添加好友" if value == "add" else "好友申请", _set_friend_tab.bind(value))
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			friend_tabs[value] = button
		_sync_friend_tabs()
	status = text(column, "")
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	column.add_child(content)
	store.completed.connect(_response)
	store.changed.connect(_changed)
	if panel_mode in ["gift", "exchange"]:
		page.collection.changed.connect(_inventory_changed)
	close_requested.connect(dismiss)
	window_input.connect(_window_input)
	_build()

func _build() -> void:
	match panel_mode:
		"add":
			query = edit(content, "输入完整公开用户 ID", 128)
			query.text = _friend_query
			query.text_changed.connect(_query_edited)
			query.text_submitted.connect(_search.unbind(1))
			action(content, "查找用户", _search, true)
			text(content, "昵称用于核对；最终通过稳定用户 ID 确定对象。")
			first_focus = query
		"request_friend": _request_form(context.get("peer", {}))
		"requests":
			_requests()
		"recent_menu":
			action(content, "全部标为已读", _mutate.bind("mark_all_read", {}, "done"))
			action(content, "换卡记录", _navigate.bind("records", {}))
			action(content, "黑名单", _navigate.bind("blacklist", {}))
		"peer_menu": _peer_menu()
		"profile":
			var person: Dictionary = context.get("peer", {})
			text(content, "昵称：" + str(person.get("name", "")))
			text(content, "公开 ID：" + str(person.get("public_id", "")))
			text(content, "我的备注：" + str(person.get("remark", "未设置")))
		"remark":
			query = edit(content, "仅自己可见的备注", store.REMARK_LIMIT)
			query.text = str(context.get("peer", {}).get("remark", ""))
			action(content, "保存备注", _remark, true)
		"remove", "block":
			text(content, ("删除好友后保留聊天和已完成交易，待确认交换将失效。" if panel_mode == "remove" else "拉黑将阻止新消息、申请和转卡，并使待确认交换失效。解除拉黑不会恢复好友关系。"))
			text(content, "%s · %s" % [context.get("peer", {}).get("name", ""), context.get("peer", {}).get("public_id", "")])
			action(content, "确认删除" if panel_mode == "remove" else "确认拉黑", _mutate.bind("relationship", {"peer_id": context.peer.id, "operation": panel_mode}, "done"))
		"blacklist": _ask("blacklist", {}, "blacklist")
		"wishlist": _ask("wishlist", {"peer_id": context.peer.id}, "wishlist")
		"gift": _gift_cards()
		"exchange": _exchange()
		"trade_review", "trade_cancel", "trade_reject": _trade_review()
		"trade_detail", "gift_detail": _ask(panel_mode, {"record_id": context.get("record_id", "")}, "detail")
		"records": _records_load()
		"report": _report()
		_: text(content, str(context.get("message", "")))

func _sync_friend_tabs() -> void:
	for value in friend_tabs:
		var button: Button = friend_tabs[value]
		button.text = "添加好友" if value == "add" else "好友申请 %d" % store.pending_requests if store.pending_requests > 0 else "好友申请"
		button.disabled = busy
		page._tab(button, panel_mode == value)

func _set_friend_tab(value: String) -> void:
	if busy or closing or panel_mode == value:
		return
	if panel_mode == "add" and is_instance_valid(query):
		_friend_query = query.text
	_serial += 1
	_ticket = "" # A search reply must not populate the requests tab.
	query = null
	_request_rows.clear()
	page._clear(content)
	status.text = ""
	panel_mode = value
	title = "添加好友" if value == "add" else "好友申请"
	heading_label.text = title
	_build()
	_sync_friend_tabs()
	scroll_box.scroll_vertical = 0
	friend_tabs[value].grab_focus()

func text(parent: Node, caption: String, strong := false) -> Label:
	return page._text(parent, caption, 19, page.text_color if strong else page.muted_color, strong)

func action(parent: Node, caption: String, callback: Callable, primary := false) -> Button:
	return page._action(parent, caption, callback, primary)

func edit(parent: Node, placeholder: String, limit: int) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.accessibility_name = placeholder
	input.max_length = limit
	input.custom_minimum_size.y = 44
	input.add_theme_color_override("font_color", page.text_color)
	var frame: StyleBoxFlat = page._style(page.surface, 6, page.border)
	frame.set_content_margin_all(10)
	input.add_theme_stylebox_override("normal", frame)
	Styles.apply_focus(input, input.get_theme_stylebox("normal") as StyleBoxFlat)
	parent.add_child(input)
	return input

func multiline(parent: Node, placeholder: String) -> TextEdit:
	var input := TextEdit.new()
	input.placeholder_text = placeholder
	input.accessibility_name = placeholder
	input.custom_minimum_size.y = 82
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.add_theme_color_override("font_color", page.text_color)
	var frame: StyleBoxFlat = page._style(page.surface, 6, page.border)
	frame.set_content_margin_all(10)
	input.add_theme_stylebox_override("normal", frame)
	Styles.apply_focus(input, input.get_theme_stylebox("normal") as StyleBoxFlat)
	parent.add_child(input)
	return input

func _ask(action_name: String, payload: Dictionary, handler: String) -> void:
	_serial += 1
	_ticket = "%s:%s" % [get_instance_id(), _serial]
	_handler = handler
	status.text = "正在提交…关闭窗口不会撤回已提交操作。" if busy else "正在加载…"
	store.dispatch(action_name, payload, _ticket)

func _mutate(action_name: String, payload: Dictionary, handler := "done") -> void:
	if busy:
		return
	var operation_id: String = store.intent(action_name, payload)
	if operation_id.is_empty():
		status.text = "无法保存操作标识，请检查本机存储后重试；尚未提交。"
		return
	_operation = payload.duplicate(true)
	_action_name = action_name
	payload = payload.duplicate(true)
	payload.operation_id = operation_id
	busy = true
	_lock(true)
	_ask(action_name, payload, handler)

func _lock(value: bool) -> void:
	for button in friend_tabs.values():
		button.disabled = value
	for button in content.find_children("*", "Button", true, false):
		button.disabled = value
	for input in content.find_children("*", "LineEdit", true, false):
		input.editable = not value
	for input in content.find_children("*", "TextEdit", true, false):
		input.editable = not value

func _response(ticket: String, response: Dictionary) -> void:
	if ticket == "request_panel_read" and _epoch == store.epoch:
		if not response.get("ok", false):
			_request_read_seq = 0
		return
	if closing or not is_inside_tree() or ticket != _ticket or _epoch != store.epoch:
		return
	var was_mutation := busy
	busy = false
	_lock(false)
	if not response.get("ok", false):
		status.text = str(response.get("message", "请求失败，可重试。"))
		if was_mutation and response.get("definitive", false):
			store.forget_intent(_action_name, _operation)
		return
	status.text = ""
	if was_mutation:
		store.forget_intent(_action_name, _operation)
	match _handler:
		"search": _search_result(response)
		"requests": _requests()
		"wishlist": _wishlist(response)
		"blacklist": _blacklist(response)
		"detail": _detail(response)
		"records": _records(response)
		"created":
			page._clear(content)
			text(content, "换卡邀请已提交，等待对方确认。确认时将核验双方卡牌数量。", true)
			if response.has("trade"):
				context.trade = response.trade
				page._trade_terms(content, response.trade)
		"trade_result":
			context.trade = response.get("trade", context.get("trade", {}))
			page._clear(content)
			text(content, page.trade_status(str(context.trade.get("status", ""))), true)
			page._trade_terms(content, context.trade)
			text(content, str(response.get("message", "状态已由服务确认。")))
		"done":
			page._clear(content)
			text(content, str(response.get("message", "操作已由服务确认。")), true)

func _search() -> void:
	if busy or query.text.strip_edges().is_empty():
		status.text = "请输入完整公开用户 ID。"
		return
	_ask("find_user", {"public_id": query.text.strip_edges()}, "search")

func _query_edited(_value: String) -> void:
	_serial += 1
	_ticket = ""
	status.text = "请输入完整公开用户 ID 并查找。"
	var result := content.get_node_or_null("SearchResult")
	if result != null:
		content.remove_child(result)
		result.queue_free()

func _search_result(response: Dictionary) -> void:
	var old := content.get_node_or_null("SearchResult")
	if old != null:
		content.remove_child(old)
		old.queue_free()
	var result := VBoxContainer.new()
	result.name = "SearchResult"
	result.add_theme_constant_override("separation", 12)
	content.add_child(result)
	var state := str(response.get("state", "not_found"))
	var captions := {"not_found": "未找到该公开 ID，请核对后重试。", "self": "这是你自己的账号。", "inaccessible": "该用户当前不可访问。", "friend": "你们已经是好友。", "outgoing": "好友申请已发送，等待对方处理。", "incoming": "已收到对方申请，请在好友申请中处理。", "available": "核对昵称和完整 ID 后再添加。"}
	text(result, captions.get(state, "无法确认此账号状态。"))
	var person: Dictionary = response.get("user", {})
	if not person.is_empty():
		var avatar: TextureRect = page.Avatar.new()
		avatar.custom_minimum_size = Vector2(56, 56)
		avatar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		result.add_child(avatar)
		avatar.show_profile(person)
		text(result, str(person.get("name", "")), true)
		text(result, "ID：" + str(person.get("public_id", "")))
	if state == "available":
		action(result, "添加好友", _navigate.bind("request_friend", {"peer": person}), true)
		action(result, "打个招呼", _greet.bind(str(person.id)))
	elif state == "incoming":
		action(result, "查看收到的申请", _navigate.bind("requests", {}))
	elif state == "friend":
		action(result, "打开会话", _greet.bind(str(person.id)))

func _request_form(person: Dictionary) -> void:
	text(content, "%s · %s" % [person.get("name", ""), person.get("public_id", "")], true)
	note = multiline(content, "简短申请说明（最多 %d 字，可选）" % store.NOTE_LIMIT)
	action(content, "发送申请", _request_friend, true)

func _request_friend() -> void:
	if note.text.length() > store.NOTE_LIMIT:
		status.text = "申请说明最多 %d 字。" % store.NOTE_LIMIT
		return
	_mutate("request_friend", {"peer_id": context.peer.id, "note": note.text}, "done")

func _requests() -> void:
	_requests_hash = JSON.stringify(store.requests).sha256_text()
	page._clear(content)
	_request_rows.clear()
	if not store.available():
		status.text = store.unavailable()
		return
	for direction in ["received", "sent"]:
		text(content, "收到的申请" if direction == "received" else "发出的申请", true)
		var count := 0
		for item in store.requests:
			if item.get("direction") != direction:
				continue
			count += 1
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			content.add_child(row)
			if direction == "received":
				row.set_meta("request_seq", item.get("seq", 0))
				_request_rows.append(row)
			var person: Dictionary = item.get("peer", {})
			var avatar: TextureRect = page.Avatar.new()
			avatar.custom_minimum_size = Vector2(42, 42)
			avatar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			row.add_child(avatar)
			avatar.show_profile(person)
			text(row, "%s · %s" % [person.get("name", ""), person.get("public_id", "")], true)
			text(row, str(item.get("note", "未附说明")))
			var state := str(item.get("status", ""))
			text(row, str(item.get("time_label", "")) + " · " + {"pending": "待处理", "accepted": "已接受", "ignored": "已忽略", "invalidated": "已失效"}.get(state, state))
			if direction == "received" and state == "pending":
				var actions := HBoxContainer.new()
				row.add_child(actions)
				action(actions, "接受", _mutate.bind("respond_request", {"request_id": item.id, "decision": "accept"}, "requests"), true)
				action(actions, "忽略", _mutate.bind("respond_request", {"request_id": item.id, "decision": "ignore"}, "requests"))
		if count == 0:
			text(content, "暂无收到的申请" if direction == "received" else "暂无发出的申请")
	if not store.error.is_empty():
		status.text = store.error
		action(content, "重新连接", store.refresh)

func _peer_menu() -> void:
	var conv: Dictionary = context.get("conversation", {})
	var friendly: bool = conv.get("is_friend", false)
	action(content, "查看资料", _navigate.bind("profile", context))
	action(content, "修改备注", _navigate.bind("remark", context))
	if friendly:
		action(content, "赠送卡牌", _navigate.bind("gift", context))
		action(content, "与此好友的记录", _navigate.bind("records", context))
	action(content, "取消免打扰" if conv.get("muted", false) else "消息免打扰", _mutate.bind("preferences", {"peer_id": context.peer.id, "muted": not conv.get("muted", false)}, "done"))
	text(content, "关系与安全")
	if friendly:
		action(content, "删除好友", _navigate.bind("remove", context))
	if conv.get("blocked_by_me", false):
		action(content, "解除拉黑", _mutate.bind("relationship", {"peer_id": context.peer.id, "operation": "unblock"}, "done"))
	else:
		action(content, "拉黑", _navigate.bind("block", context))
	action(content, "举报", _navigate.bind("report", context))

func _remark() -> void:
	_mutate("preferences", {"peer_id": context.peer.id, "remark": query.text}, "done")

func _blacklist(response: Dictionary) -> void:
	page._clear(content)
	var people: Array = response.get("users", [])
	if people.is_empty():
		text(content, "黑名单为空。")
	for person in people:
		text(content, "%s · %s" % [person.get("name", ""), person.get("public_id", "")])
		action(content, "解除拉黑", _mutate.bind("relationship", {"peer_id": person.id, "operation": "unblock"}, "done"))

func _wishlist(response: Dictionary) -> void:
	page._clear(content)
	var state := str(response.get("visibility", "accessible"))
	if state != "accessible":
		text(content, "对方的想要清单为私密。" if state == "private" else "当前无权访问对方的想要清单。")
		return
	var cards: Array = response.get("card_ids", [])
	if cards.is_empty():
		text(content, "对方还没有想要的卡牌。")
	for id in cards:
		page.card_summary(content, str(id), 1)
		text(content, "想要不代表拥有。")
		var actions := HBoxContainer.new()
		content.add_child(actions)
		action(actions, "赠送这张卡", _gift.bind(str(id)))
		var next := context.duplicate(true)
		next.give_card_id = str(id)
		action(actions, "发起换卡", _navigate.bind("exchange", next))

func _gift_cards() -> void:
	text(content, "沿用收藏页的赠送额度、确认与至少保留一张规则。")
	_waiting_inventory = not page.collection.inventory_known
	if not page.collection.inventory_known:
		text(content, "正在读取库存…" if page.collection.loading else "库存暂不可用，当前无法选择赠送卡牌。")
		_request_inventory.call_deferred()
		return
	var count := 0
	for card in page.collection.cards:
		var rule: Dictionary = page.collection.gift_rule(str(card.id))
		if int(rule.max) <= 0:
			continue
		count += 1
		text(content, "%s · %s · 拥有 %d · 可赠 %d" % [card.name, CardArtwork.season_title(page.collection.season(card.season_id)), page.collection.count(card.id), rule.max])
		action(content, "选择并核对赠送", _gift.bind(str(card.id)))
	if count == 0:
		text(content, "当前没有可赠卡牌。至少保留一张及服务端额度仍然适用。")

func _gift(id: String) -> void:
	page.open_gift(id, context.peer)

func _exchange() -> void:
	text(content, "%s · %s" % [context.peer.get("name", ""), context.peer.get("public_id", "")], true)
	if not store.capabilities.get("exchange", false):
		text(content, str(store.capabilities.get("exchange_reason", "换卡服务尚未接入，无法创建或交割真实邀请。")))
		return
	_waiting_inventory = not page.collection.inventory_known
	if not page.collection.inventory_known:
		text(content, "正在读取库存…" if page.collection.loading else "尚未取得真实库存，当前无法选择换卡内容。")
		_request_inventory.call_deferred()
		return
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 24)
	content.add_child(sides)
	for is_give in [true, false]:
		var side := VBoxContainer.new()
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sides.add_child(side)
		text(side, "我送出" if is_give else "我获得", true)
		var choice := OptionButton.new()
		choice.custom_minimum_size = Vector2(210, 48)
		page._style_choice(choice)
		side.add_child(choice)
		for card in page.collection.cards:
			var count := int(page.collection.inventory.get(card.id, {}).get("exchangeable_count", 0))
			if is_give and count <= 0:
				continue
			choice.add_item("%s · %s%s" % [card.name, page.collection.season(card.season_id).get("label", ""), " · 可用 %d" % count if is_give else ""])
			choice.set_item_metadata(choice.item_count - 1, card.id)
			if str(context.get("give_card_id" if is_give else "receive_card_id", "")) == str(card.id):
				choice.select(choice.item_count - 1)
		var quantity := SpinBox.new()
		quantity.min_value = 1
		quantity.max_value = store.Policy.QUANTITY_LIMIT
		quantity.step = 1
		quantity.rounded = true
		quantity.custom_minimum_size.y = 46
		quantity.get_line_edit().accessibility_name = "送出数量" if is_give else "获得数量"
		side.add_child(quantity)
		if is_give:
			give = choice
			give_amount = quantity
		else:
			receive = choice
			receive_amount = quantity
	text(content, "希望获得的卡牌来自公开目录，不代表对方拥有。邀请不冻结库存，确认时将核验双方卡牌数量。")
	confirmation = action(content, "核对条款", _review_create, true)
	confirmation.disabled = give.item_count == 0 or receive.item_count == 0
	if give.item_count == 0:
		text(content, "当前没有服务允许转出的卡牌。")

func _review_create() -> void:
	give_amount.apply()
	receive_amount.apply()
	var give_id := str(give.get_selected_metadata())
	var receive_id := str(receive.get_selected_metadata())
	var amount := int(give_amount.value)
	if amount < 1 or amount > int(page.collection.inventory.get(give_id, {}).get("exchangeable_count", 0)):
		status.text = "送出数量超出当前可转出库存。"
		return
	context.terms = {"peer_id": context.peer.id, "give": [{"card_id": give_id, "season_id": page.collection.card(give_id).season_id, "quantity": amount}], "receive": [{"card_id": receive_id, "season_id": page.collection.card(receive_id).season_id, "quantity": int(receive_amount.value)}], "terms_version": 1}
	page._clear(content)
	var profile: Dictionary = get_node("/root/ProfileStore").profile
	text(content, "我：%s · %s" % [profile.get("display_name", ""), profile.get("public_id", "")], true)
	text(content, "对方：%s · %s" % [context.peer.get("name", ""), context.peer.get("public_id", "")], true)
	var preview: Dictionary = context.terms.duplicate(true)
	preview.initiator_id = store.account_id
	page._trade_terms(content, preview)
	text(content, "发送邀请即同意以上固定条款。邀请不冻结库存；确认时将核验双方卡牌数量。")
	action(content, "修改条款", _edit_terms)
	action(content, "发送邀请", _mutate.bind("create_trade", context.terms, "created"), true)

func _edit_terms() -> void:
	page._clear(content)
	_exchange()

func _trade_review() -> void:
	var trade: Dictionary = context.get("trade", {})
	if trade.is_empty():
		text(content, "交易详情暂不可用。")
		return
	text(content, "双方：%s · %s ↔ %s · %s" % [trade.get("initiator", {}).get("name", ""), trade.get("initiator", {}).get("public_id", ""), trade.get("recipient", {}).get("name", ""), trade.get("recipient", {}).get("public_id", "")], true)
	text(content, "状态：%s · 条款版本 %s" % [page.trade_status(str(trade.get("status", ""))), trade.get("terms_version", "")])
	page._trade_terms(content, trade)
	if trade.get("status") != "pending":
		return
	if panel_mode == "trade_review":
		text(content, "确认时将核验双方卡牌数量。只有点击确认交换才会提交交割。")
	var decision := "confirm" if panel_mode == "trade_review" else "cancel" if panel_mode == "trade_cancel" else "reject"
	if (decision == "cancel" and trade.get("initiator_id") != store.account_id) or (decision != "cancel" and trade.get("recipient_id") != store.account_id):
		text(content, "当前账号无权执行此操作。")
		return
	action(content, {"confirm": "确认交换", "cancel": "确认取消邀请", "reject": "确认拒绝"}[decision], _mutate.bind("trade_action", {"trade_id": trade.id, "terms_version": trade.terms_version, "decision": decision}, "trade_result"), decision == "confirm")

func _detail(response: Dictionary) -> void:
	page._clear(content)
	if response.has("trade"):
		context.trade = response.trade
		panel_mode = "trade_review" if response.trade.get("recipient_id") == store.account_id else "trade_cancel"
		_trade_review()
	elif response.has("gift"):
		text(content, str(response.gift.get("summary", "")), true)
		text(content, str(response.gift.get("time_label", "")))
	else:
		text(content, "服务未返回可查看的业务记录。")

func _records_load() -> void:
	_ask("trade_records", {"peer_id": context.get("peer", {}).get("id", ""), "before": _record_cursor, "limit": store.PAGE_SIZE}, "records")

func _records(response: Dictionary) -> void:
	_record_rows.append_array(response.get("trades", []))
	_record_cursor = str(response.get("next_before", ""))
	page._clear(content)
	if _record_rows.is_empty():
		text(content, "暂无换卡记录。")
	for trade in _record_rows:
		text(content, "%s ↔ %s · %s · %s" % [trade.get("initiator", {}).get("name", ""), trade.get("recipient", {}).get("name", ""), page.trade_status(str(trade.status)), trade.get("time_label", "")], true)
		page._trade_terms(content, trade)
		action(content, "查看记录", _navigate.bind("trade_detail", {"record_id": trade.id}))
		action(content, "返回原会话", _return_conversation.bind(str(trade.get("conversation_id", ""))))
	if not _record_cursor.is_empty():
		action(content, "加载更多记录", _records_load)

func _report() -> void:
	if not store.capabilities.get("reports", false):
		text(content, "举报接收渠道尚未接通，当前无法提交。不会将私聊发送给普通联系人。")
		return
	_report_reason = OptionButton.new()
	for reason in ["骚扰", "欺诈", "不当内容", "其他"]:
		_report_reason.add_item(reason)
	page._style_choice(_report_reason)
	content.add_child(_report_reason)
	note = multiline(content, "可选说明，最多 %d 字" % store.REPORT_LIMIT)
	text(content, "仅提交你主动勾选的相关消息：")
	for message in store.messages.get(context.get("conversation", {}).get("id", ""), []):
		if message.get("type") != "text" or str(message.get("id", "")).is_empty():
			continue
		var choice := CheckBox.new()
		choice.text = str(message.get("text", "")).left(80)
		choice.clip_text = true
		choice.add_theme_color_override("font_color", page.text_color)
		content.add_child(choice)
		choice.toggled.connect(func(on):
			if on: _selected_messages.append(message.id)
			else: _selected_messages.erase(message.id))
	action(content, "提交举报", _submit_report, true)

func _submit_report() -> void:
	if note.text.length() > store.REPORT_LIMIT:
		status.text = "说明最多 %d 字。" % store.REPORT_LIMIT
		return
	_mutate("report", {"peer_id": context.peer.id, "reason": ["harassment", "fraud", "content", "other"][_report_reason.selected], "note": note.text, "message_ids": _selected_messages.duplicate()}, "done")

func _greet(id: String) -> void:
	store.set_tab("recent")
	page._narrow_chat = true
	store.open_peer(id)
	dismiss()

func _return_conversation(id: String) -> void:
	store.set_tab("recent")
	page._select(id)
	dismiss()

func _navigate(next_mode: String, next_context: Dictionary) -> void:
	dismiss()
	page.show_panel.call_deferred(next_mode, next_context)

func _request_inventory() -> void:
	if closing or _inventory_requested or page.collection.inventory_known or page.collection.loading:
		return
	_inventory_requested = true
	page.collection.refresh()

func _inventory_changed() -> void:
	if closing or busy or not is_instance_valid(content): return
	# Preserve exchange selections once its form is ready; only fill an empty form.
	if panel_mode == "gift" or (panel_mode == "exchange" and _waiting_inventory):
		page._clear(content)
		_build()

func _changed() -> void:
	if store.epoch != _epoch:
		dismiss()
		return
	_sync_friend_tabs()
	if closing or busy or not is_instance_valid(content):
		return
	if panel_mode == "requests" and JSON.stringify(store.requests).sha256_text() != _requests_hash:
		var position := scroll_box.scroll_vertical
		_requests()
		scroll_box.set_deferred("scroll_vertical", position)
	if context.has("trade"):
		var latest: Dictionary = store.trades.get(str(context.trade.get("id", "")), {})
		if int(latest.get("revision", 0)) > int(context.trade.get("revision", 0)):
			context.trade = latest.duplicate(true)
			page._clear(content)
			_trade_review()

func _process(delta: float) -> void:
	_read_timer += delta
	if _read_timer < 0.5 or panel_mode != "requests" or not visible or not has_focus() or closing:
		return
	_read_timer = 0
	var visible_rect := scroll_box.get_global_rect()
	var reached := _request_read_seq
	for row in _request_rows:
		if is_instance_valid(row):
			var rect: Rect2 = row.get_global_rect()
			if rect.end.y <= visible_rect.end.y and rect.end.y >= visible_rect.position.y:
				reached = maxi(reached, int(row.get_meta("request_seq", 0)))
	if reached > _request_read_seq:
		_request_read_seq = reached
		store.dispatch("mark_requests_read", {"through_seq": reached}, "request_panel_read")

func present() -> void:
	popup_centered_clamped(Vector2i(700 if panel_mode in ["exchange", "trade_review", "records", "trade_detail"] else 590, 730 if panel_mode in ["add", "requests", "exchange", "trade_review", "records", "report", "wishlist"] else 540), 0.9)
	page._motion().enter(panel, page.Tokens.PANEL)
	first_focus.grab_focus()

func _window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		dismiss()

func dismiss() -> void:
	if closing:
		return
	closing = true
	_serial += 1
	hide()
	if is_instance_valid(shade):
		shade.queue_free()
		shade = null
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(shade):
		shade.queue_free()
