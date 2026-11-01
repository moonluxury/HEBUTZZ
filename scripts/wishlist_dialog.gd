extends "res://scripts/trade_dialog.gd"
## Friend projection of CollectionStore's cloud source; no local duplicate list.
var response_data: Dictionary = {}
var fetching := false
var card_rows: Array = []
var _next_action := ""
var _next_card := ""

func _ready() -> void:
	super._ready()
	page.collection.changed.connect(_inventory_changed)
	if not page.collection.inventory_known: _request_inventory.call_deferred()

func _build() -> void:
	_load_wishlist()

func _load_wishlist() -> void:
	if closing or fetching: return
	fetching = true
	response_data = {}
	_render_wishlist()
	_ask("wishlist",{"peer_id":context.peer.id},"wishlist")

func _response(ticket: String, response: Dictionary) -> void:
	if closing or ticket != _ticket or store.epoch != _epoch: return
	fetching = false
	response_data = response.duplicate(true)
	_render_wishlist()

func _render_wishlist() -> void:
	var position := scroll_box.scroll_vertical
	_clear_transfer()
	card_rows.clear()
	title = "想要清单"
	heading_label.text = title
	_peer(context.get("peer",{}))
	if fetching:
		text(content,"正在读取云端想要清单…")
	elif not response_data.get("ok",false):
		text(content,"暂时无法读取想要清单",true)
		text(content,str(response_data.get("message","连接失败，请稍后重试。")))
	elif response_data.get("visibility","inaccessible") != "accessible":
		text(content,"对方的想要清单为私密。" if response_data.get("visibility") == "private" else "当前无权访问对方的想要清单。")
	else:
		var ids: Array = response_data.get("card_ids",[])
		if ids.is_empty():
			text(content,"还没有想要的卡牌",true)
			text(content,"好友在「我的收藏」中标记想要后，会显示在这里。")
		else:
			text(content,"想要 %d 款卡牌" % ids.size(),true)
			text(content,"这份清单表示好友的心愿，不代表对方已拥有。")
			for id in ids:
				var card: Dictionary = page.collection.card(str(id))
				if card.is_empty():
					text(content,"有一张卡牌需要更新客户端目录后查看。")
					continue
				var rule: Dictionary = page.collection.gift_rule(str(id))
				var detail := "你可赠送 %d 张" % int(rule.max) if int(rule.max)>0 else "你尚未拥有这张卡" if page.collection.count(str(id))==0 else "赠送需至少保留 1 张" if page.collection.inventory_known else "正在确认你的库存…"
				var row := TransferUi.summary(content,card,page.collection.season(str(card.get("season_id",""))),detail,colors)
				var buttons := HBoxContainer.new()
				buttons.add_theme_constant_override("separation",12)
				row.metadata.add_child(buttons)
				var gift := action(buttons,"赠送",_open_transfer.bind("gift",str(id)),true)
				gift.disabled = int(rule.max)<=0 or page.collection.pending()
				var exchange := action(buttons,"换卡",_open_transfer.bind("exchange",str(id)))
				exchange.disabled = not store.capabilities.get("exchange",false) or int(page.collection.inventory.get(str(id),{}).get("exchangeable_count",0))<=0
				row["gift"] = gift
				row["exchange"] = exchange
				card_rows.append(row)
	var refresh := _footer_action("刷新清单",_load_wishlist)
	refresh.disabled = fetching
	_footer_action("关闭",dismiss,true)
	_sync_action_feedback()
	scroll_box.set_deferred("scroll_vertical",position)
	_schedule_fit()

func _inventory_changed() -> void:
	if not closing: _render_wishlist()

func _theme_changed() -> void:
	if closing: return
	colors = TransferUi.colors(get_node("/root/AppState").dark_mode)
	panel.add_theme_stylebox_override("panel",Styles.dialog_panel(self,panel,colors.surface,14))
	heading_label.add_theme_color_override("font_color",colors.text)
	DialogUi.style_button(close_button,colors,false,false,true)
	for line in footer.find_children("*","ColorRect",true,false): line.color = colors.border
	_render_wishlist()

func _open_transfer(mode: String, id: String) -> void:
	if closing or store.epoch != _epoch: return
	_next_action = mode
	_next_card = id
	dismiss()

func _finish_close(serial := -1) -> void:
	if is_queued_for_deletion() or (serial >= 0 and serial != _close_serial): return
	var target_page := page
	var target := context.duplicate(true)
	var next := _next_action
	var id := _next_card
	var epoch := _epoch
	super._finish_close(serial)
	if next.is_empty(): return
	if not is_instance_valid(target_page) or not target_page.is_inside_tree() or store.epoch != epoch: return
	if next == "gift": target_page.open_gift.call_deferred(id,target.peer)
	else:
		target.give_card_id = id
		target_page.show_panel.call_deferred("exchange",target)
