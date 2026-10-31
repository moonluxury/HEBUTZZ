extends "res://scripts/social_dialog.gd"
## Exchange presentation shares the gift window's typography and original card art.
const TransferUi = preload("res://scripts/card_transfer_ui.gd")
const DialogUi = preload("res://scripts/account_dialog_ui.gd")
const BASE_SIZE := Vector2(560, 820)
var colors: Dictionary
var footer: VBoxContainer
var actions: HBoxContainer
var close_button: Button
var give_preview: Dictionary = {}
var receive_preview: Dictionary = {}
var _form_active := false
var _create_review_active := false
var _result_mode := false
var _result_message := ""
var _unknown_operation := false
var _fit_queued := false
var _editing_terms: Button
var _close_serial := 0

func _ready() -> void:
	_epoch = store.epoch
	transient = true
	exclusive = true
	borderless = true
	visible = false
	theme = page.theme
	colors = TransferUi.colors(page.dark)
	title = {"exchange":"发起换卡","trade_review":"确认换卡","trade_detail":"换卡详情","trade_cancel":"取消换卡邀请","trade_reject":"拒绝换卡邀请"}.get(panel_mode,"换卡")
	shade = ColorRect.new()
	shade.color = Color(0.02,0.04,0.09,0.22)
	page.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell := TransferUi.shell(self,title,dismiss,colors)
	panel = shell.panel
	column = shell.column
	content = shell.body
	scroll_box = shell.scroll
	footer = shell.footer
	heading_label = shell.heading
	close_button = shell.close
	first_focus = close_button
	DialogUi.rule(footer,colors.border)
	status = TransferUi.label(footer,"",15,colors,true)
	status.hide()
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation",14)
	footer.add_child(actions)
	store.completed.connect(_response)
	store.changed.connect(_changed)
	if panel_mode == "exchange": page.collection.changed.connect(_inventory_changed)
	close_requested.connect(dismiss)
	window_input.connect(_window_input)
	RenderingServer.frame_pre_draw.connect(_before_draw)
	get_tree().root.size_changed.connect(_schedule_fit)
	page.resized.connect(_schedule_fit)
	get_node("/root/AppState").font_scale_changed.connect(_schedule_fit.unbind(1))
	get_node("/root/AppState").color_mode_changed.connect(_theme_changed.unbind(1))
	_build()

func _before_draw() -> void:
	if not closing: TransferUi.render_density(self)

func text(parent: Node, caption: String, strong := false) -> Label:
	return TransferUi.label(parent,caption,18 if strong else 16,colors,not strong,strong)

func action(parent: Node, caption: String, callback: Callable, primary := false) -> Button:
	return TransferUi.button(parent,caption,callback,colors,primary,not primary)

func _clear_transfer() -> void:
	_form_active = false
	_create_review_active = false
	page._clear(content)
	page._clear(actions)
	status.text = ""
	status.hide()
	_editing_terms = null

func _footer_action(caption: String, callback: Callable, primary := false) -> Button:
	var button := action(actions,caption,callback,primary)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button

func _peer(person: Dictionary) -> void:
	TransferUi.person(content,person,colors)
	DialogUi.rule(content,colors.border)

func _exchange() -> void:
	_clear_transfer()
	_result_mode = false
	heading_label.text = "发起换卡"
	_peer(context.get("peer",{}))
	if not store.capabilities.get("exchange",false):
		text(content,str(store.capabilities.get("exchange_reason","换卡服务暂不可用。")))
		_footer_action("关闭",dismiss)
		return
	_waiting_inventory = not page.collection.inventory_known
	if _waiting_inventory:
		text(content,"正在读取库存…" if page.collection.loading else "暂未取得库存，请稍后重新打开。")
		_footer_action("关闭",dismiss)
		_request_inventory.call_deferred()
		return
	for is_give in [true,false]:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation",10)
		content.add_child(section)
		text(section,"我送出" if is_give else "我想换取",true)
		var preview := TransferUi.summary(section,{}, {}, "",colors)
		preview.name.hide()
		var choice := OptionButton.new()
		choice.custom_minimum_size.y = 40
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.clip_text = true
		choice.accessibility_name = "选择送出的卡牌" if is_give else "选择想换取的卡牌"
		preview.metadata.add_child(choice)
		preview.metadata.move_child(choice,0)
		Styles.button(choice,colors.surface,false,page.dark,18)
		choice.get_popup().add_theme_font_size_override("font_size",18)
		for card in page.collection.cards:
			var count := int(page.collection.inventory.get(card.id,{}).get("exchangeable_count",0))
			if is_give and count <= 0: continue
			choice.add_item(str(card.name))
			choice.set_item_metadata(choice.item_count-1,card.id)
			if str(context.get("give_card_id" if is_give else "receive_card_id","")) == str(card.id): choice.select(choice.item_count-1)
		choice.disabled = choice.item_count == 0
		var quantity_row := HBoxContainer.new()
		section.add_child(quantity_row)
		var caption := text(quantity_row,"数量")
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var quantity := TransferUi.stepper(quantity_row,colors,"送出数量" if is_give else "换取数量",store.Policy.QUANTITY_LIMIT)
		quantity.value = int(context.get("give_quantity" if is_give else "receive_quantity",1))
		if is_give:
			give = choice; give_amount = quantity; give_preview = preview
		else:
			receive = choice; receive_amount = quantity; receive_preview = preview
		choice.item_selected.connect(_selection_changed.unbind(1))
		quantity.value_changed.connect(_selection_changed.unbind(1))
	text(content,"想换取的卡牌来自公开目录，是否可用由对方确认时核验。发起邀请不会立即转移卡牌。")
	_footer_action("取消",dismiss)
	confirmation = _footer_action("核对换卡内容",_review_create,true)
	_form_active = true
	_selection_changed()
	_schedule_fit()

func _selection_changed() -> void:
	if not _form_active or closing: return
	for is_give in [true,false]:
		var choice: OptionButton = give if is_give else receive
		var number: SpinBox = give_amount if is_give else receive_amount
		var preview: Dictionary = give_preview if is_give else receive_preview
		if choice.item_count == 0:
			preview.season.text = "当前没有可交换的卡牌"
			preview.amount.text = ""
			TransferUi.sync_stepper(number,false,0)
			continue
		var id := str(choice.get_selected_metadata())
		var card: Dictionary = page.collection.card(id)
		var maximum: int = int(page.collection.inventory.get(id,{}).get("exchangeable_count",0)) if is_give else store.Policy.QUANTITY_LIMIT
		preview.art.texture = page._texture(str(card.get("artwork","")))
		preview.art.custom_minimum_size.y = 80 * CardArtwork.ratio(preview.art)
		preview.season.text = CardArtwork.season_title(page.collection.season(str(card.get("season_id",""))))
		preview.amount.text = "可交换 %d 张" % maximum if is_give else "以对方确认时的库存为准"
		TransferUi.sync_stepper(number,not busy and maximum > 0,maximum)
		context["give_card_id" if is_give else "receive_card_id"] = id
		context["give_quantity" if is_give else "receive_quantity"] = int(number.value)
	var allowed: int = page.collection.inventory.get(str(give.get_selected_metadata()),{}).get("exchangeable_count",0) if give.item_count else 0
	confirmation.disabled = busy or give.item_count == 0 or receive.item_count == 0 or give_amount.value > allowed
	if not busy and give.item_count > 0 and give_amount.value > allowed:
		status.text = "送出数量超出当前可交换库存，请调整数量。"
	elif not busy:
		status.text = ""
	_status_changed()

func _review_create() -> void:
	if closing or not _form_active or busy or give.item_count == 0 or receive.item_count == 0: return
	TransferUi.commit_quantity(give_amount); TransferUi.commit_quantity(receive_amount)
	_selection_changed()
	if confirmation.disabled: return
	var give_id := str(give.get_selected_metadata())
	var receive_id := str(receive.get_selected_metadata())
	context.terms = {"peer_id":context.peer.id,"give":[{"card_id":give_id,"season_id":page.collection.card(give_id).season_id,"quantity":int(give_amount.value)}],"receive":[{"card_id":receive_id,"season_id":page.collection.card(receive_id).season_id,"quantity":int(receive_amount.value)}],"terms_version":1}
	_render_create_review()

func _render_create_review() -> void:
	_clear_transfer()
	_create_review_active = true
	heading_label.text = "核对换卡内容"
	_peer(context.get("peer",{}))
	var preview: Dictionary = context.terms.duplicate(true)
	preview.initiator_id = store.account_id
	_trade_cards(preview)
	text(content,"发送邀请即同意以上固定条款。邀请不冻结库存；对方确认时会再次核验双方的卡牌数量。")
	_editing_terms = _footer_action("返回修改",_edit_terms)
	confirmation = _footer_action("发送邀请",_mutate.bind("create_trade",context.terms,"created"),true)
	_schedule_fit()

func _edit_terms() -> void:
	if busy or _unknown_operation: return
	_exchange()

func _trade_cards(trade: Dictionary) -> void:
	var outgoing: Array = trade.get("give",[]) if trade.get("initiator_id") == store.account_id else trade.get("receive",[])
	var incoming: Array = trade.get("receive",[]) if trade.get("initiator_id") == store.account_id else trade.get("give",[])
	for part in [["我送出",outgoing],["我获得",incoming]]:
		text(content,part[0],true)
		for line in part[1]:
			var card: Dictionary = page.collection.card(str(line.get("card_id","")))
			TransferUi.summary(content,card,page.collection.season(str(card.get("season_id",""))),"数量：%d 张" % int(line.get("quantity",0)),colors)

func _trade_review() -> void:
	if _result_mode:
		_render_result()
		return
	_clear_transfer()
	var trade: Dictionary = context.get("trade",{})
	if trade.is_empty():
		text(content,"交易详情暂不可用。")
		_footer_action("关闭",dismiss)
		return
	var peer: Dictionary = trade.get("recipient" if trade.get("initiator_id") == store.account_id else "initiator",context.get("peer",{}))
	_peer(peer)
	_trade_cards(trade)
	text(content,"状态：" + page.trade_status(str(trade.get("status",""))))
	_footer_action("关闭",dismiss)
	if trade.get("status") == "pending":
		var decision := "confirm" if panel_mode == "trade_review" else "cancel" if panel_mode == "trade_cancel" else "reject"
		var permitted: bool = trade.get("initiator_id") == store.account_id if decision == "cancel" else trade.get("recipient_id") == store.account_id
		if permitted:
			text(content,"确认后将按以上内容交换卡牌。" if decision == "confirm" else "此操作只结束邀请，不会交换卡牌。")
			confirmation = _footer_action({"confirm":"确认交换","cancel":"取消邀请","reject":"拒绝邀请"}[decision],_mutate.bind("trade_action",{"trade_id":trade.id,"terms_version":trade.terms_version,"decision":decision},"trade_result"),decision == "confirm")
	_schedule_fit()

func _render_result() -> void:
	_clear_transfer()
	heading_label.text = "换卡邀请已发送" if _handler == "created" else "换卡结果"
	var trade: Dictionary = context.get("trade",{})
	if not trade.is_empty():
		_peer(trade.get("recipient" if trade.get("initiator_id") == store.account_id else "initiator",context.get("peer",{})))
		_trade_cards(trade)
		text(content,page.trade_status(str(trade.get("status",""))),true)
	text(content,_result_message)
	_footer_action("完成",dismiss,true)
	_schedule_fit()

func _response(ticket: String, response: Dictionary) -> void:
	if closing or ticket != _ticket or store.epoch != _epoch: return
	var mutation := busy
	super._response(ticket,response)
	_unknown_operation = mutation and not response.get("ok",false) and not response.get("definitive",false)
	if response.get("ok",false) and _handler in ["created","trade_result"]:
		_result_mode = true
		_result_message = str(response.get("message","邀请已发送，等待对方确认。" if _handler == "created" else "交换状态已更新。"))
		_render_result()
	if is_instance_valid(_editing_terms): _editing_terms.disabled = busy or _unknown_operation
	_sync_action_feedback()
	_status_changed()

func _ask(action_name: String, payload: Dictionary, handler: String) -> void:
	super._ask(action_name,payload,handler)
	_status_changed()

func _mutate(action_name: String, payload: Dictionary, handler := "done") -> void:
	if closing or store.epoch != _epoch: return
	super._mutate(action_name,payload,handler)

func _lock(value: bool) -> void:
	super._lock(value)
	for button in actions.get_children():
		if button is Button: button.disabled = value
	if _form_active: _selection_changed()
	_sync_action_feedback()

func _sync_action_feedback() -> void:
	for button in panel.find_children("*","Button",true,false):
		var feedback := button.get_node_or_null("UIFeedback")
		if feedback != null: feedback._check_disabled()
		button.queue_redraw()

func _inventory_changed() -> void:
	if closing or busy: return
	if _waiting_inventory: _exchange()
	elif _form_active: _selection_changed()

func _status_changed() -> void:
	status.visible = not status.text.is_empty()
	_schedule_fit()

func _theme_changed() -> void:
	if closing: return
	var notice := status.text
	colors = TransferUi.colors(get_node("/root/AppState").dark_mode)
	panel.add_theme_stylebox_override("panel",Styles.dialog_panel(self,panel,colors.surface,14))
	heading_label.add_theme_color_override("font_color",colors.text)
	status.add_theme_color_override("font_color",colors.muted)
	DialogUi.style_button(close_button,colors,false,false,true)
	close_button.add_theme_font_size_override("font_size",16)
	for line in footer.find_children("*","ColorRect",true,false): line.color = colors.border
	if _form_active: _exchange()
	elif _create_review_active: _render_create_review()
	else: _trade_review()
	status.text = notice
	_lock(busy)
	if is_instance_valid(_editing_terms): _editing_terms.disabled = busy or _unknown_operation
	_sync_action_feedback()
	_status_changed()

func _schedule_fit() -> void:
	if closing or not visible or _fit_queued: return
	_fit_queued = true
	_refit.call_deferred()

func _refit() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_queued = false
	if not closing and visible: TransferUi.fit(self,BASE_SIZE if _form_active else Vector2(560,720),page,panel)

func present() -> void:
	TransferUi.fit(self,BASE_SIZE if _form_active else Vector2(560,720),page,panel,true)
	page._motion().enter(shade,page.Tokens.PANEL)
	page._motion().enter(panel,page.Tokens.PANEL)
	close_button.grab_focus()
	_schedule_fit()

func dismiss() -> void:
	if closing: return
	closing = true
	_serial += 1
	_close_serial += 1
	set_meta("transfer_retiring",true)
	if is_instance_valid(shade): shade.set_meta("transfer_retiring",true)
	if not is_inside_tree() or not is_instance_valid(page) or not page.is_inside_tree():
		_finish_close()
		return
	if page._motion().reduced() or DisplayServer.get_name() == "headless" or store.epoch != _epoch:
		_finish_close()
		return
	page._motion().animate(self,panel,^"modulate:a",0.0,page.Tokens.EXIT,true)
	page._motion().animate(self,shade,^"modulate:a",0.0,page.Tokens.EXIT,true)
	get_tree().create_timer(page.Tokens.EXIT).timeout.connect(_finish_close.bind(_close_serial))

func _finish_close(serial := -1) -> void:
	if is_queued_for_deletion() or (serial >= 0 and serial != _close_serial): return
	_close_serial += 1
	hide()
	if is_instance_valid(shade):
		shade.queue_free()
		shade = null
	closed.emit()
	queue_free()
