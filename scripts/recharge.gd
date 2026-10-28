extends "res://scripts/minimal_page.gd"
const Amount = preload("res://scripts/battery_amount.gd")
const Dialog = preload("res://scripts/recharge_dialog.gd")
var store: Node
var balance_amount: HBoxContainer
var balance_retry: Button
var record_links: HBoxContainer
var balance_line: ColorRect
var left: VBoxContainer
var right: VBoxContainer
var separator: ColorRect
var package_grid: GridContainer
var package_status: Label
var package_retry: Button
var channel_box: VBoxContainer
var account_value: Label
var quantity_value: Label
var estimate_value: Label
var total_value: Label
var pay_button: Button
var reason_label: Label
var footer: Label
var resume: Button
var bell: Button
var dialog: Window
var _focus_return: WeakRef
var _catalog_hash := ""
var _channel_hash := ""
var _generation := -1
var _queued := false

func _ready() -> void:
	active_nav = "RechargeButton"
	store = get_node("/root/PageRouter").wallet_store()
	store.changed.connect(_state_changed)
	store.order_ready.connect(_order_ready)
	get_node("/root/ProfileStore").changed.connect(_state_changed)
	super._ready()
	store.activate(true)

func _exit_tree() -> void:
	if is_instance_valid(store): store.activate(false)
	if is_instance_valid(dialog): dialog.dismiss()

func _build_content() -> void:
	_catalog_hash = ""
	_channel_hash = ""
	bell = _button(body, "Bell", "", get_node("/root/PageRouter").open_friends.bind(true))
	bell.icon = _texture("res://assets/profile/bell.svg")
	bell.accessibility_name = "查看未读消息与通知"
	balance_amount = Amount.new()
	balance_amount.name = "BalanceAmount"
	body.add_child(balance_amount)
	balance_amount.setup(self, "—")
	balance_retry = _button(body, "BalanceRetry", "", _retry_balance)
	balance_retry.alignment = HORIZONTAL_ALIGNMENT_LEFT
	balance_retry.add_theme_font_size_override("font_size", 15)
	record_links = HBoxContainer.new()
	record_links.add_theme_constant_override("separation", 18)
	body.add_child(record_links)
	_action(record_links, "电池明细 →", show_panel.bind("ledger"))
	var link_divider := ColorRect.new()
	link_divider.color = border
	link_divider.custom_minimum_size = Vector2(1, 18)
	link_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	link_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	record_links.add_child(link_divider)
	_action(record_links, "充值记录 →", show_panel.bind("orders"))
	balance_line = _line(body, Rect2())
	left = VBoxContainer.new()
	left.name = "PackagesAndRewards"
	left.add_theme_constant_override("separation", 20)
	body.add_child(left)
	_text(left, "选择充值金额", 25, text_color, true)
	package_status = _text(left, "", 18, muted_color)
	package_retry = _action(left, "重新获取套餐", store.refresh_catalog)
	package_grid = GridContainer.new()
	package_grid.name = "Packages"
	package_grid.columns = 2
	package_grid.add_theme_constant_override("h_separation", 18)
	package_grid.add_theme_constant_override("v_separation", 18)
	left.add_child(package_grid)
	_rule(left)
	_text(left, "也可以这样获得电池", 22, text_color, true)
	var rewards := HBoxContainer.new()
	rewards.name = "RewardEntries"
	rewards.add_theme_constant_override("separation", 22)
	left.add_child(rewards)
	_reward_row(rewards, "reward-quiz", "答题得电池", "答对题目，按规则获得", "去答题 →", _open_subjects.bind("all"))
	var reward_divider := ColorRect.new()
	reward_divider.color = border
	reward_divider.custom_minimum_size.x = 1
	reward_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rewards.add_child(reward_divider)
	_reward_row(rewards, "reward-publication", "投稿得电池", "审核通过并发表后获得", "去投稿 →", _publication)
	footer = _text(left, "", 14, muted_color)
	separator = _line(body, Rect2())
	right = VBoxContainer.new()
	right.name = "Confirmation"
	right.add_theme_constant_override("separation", 19)
	body.add_child(right)
	_text(right, "确认充值", 25, text_color, true)
	account_value = _field(right, "充值账户", "—")
	quantity_value = _field(right, "充值数量", "—")
	estimate_value = _field(right, "充值后预计余额", "—")
	_rule(right)
	_text(right, "支付方式", 18, text_color)
	channel_box = VBoxContainer.new()
	channel_box.add_theme_constant_override("separation", 10)
	right.add_child(channel_box)
	_rule(right)
	total_value = _field(right, "应付金额", "—", true)
	pay_button = _action(right, "确认充值", store.create_order, true)
	pay_button.name = "ConfirmRecharge"
	pay_button.custom_minimum_size.y = 52
	var tip := _text(right, "到账后自动更新余额", 15, muted_color)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var links := HBoxContainer.new()
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	links.add_theme_constant_override("separation", 22)
	right.add_child(links)
	_action(links, "充值说明", show_panel.bind("rules"))
	_action(links, "支付遇到问题", _help)
	reason_label = _text(right, "", 15, muted_color)
	resume = _action(right, "查询原订单 →", _resume)
	_render()

func _field(parent: Node, caption: String, value: String, strong := false) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	var label := _text(row, caption, 18, muted_color)
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.custom_minimum_size.x = 145
	var result := _text(row, value, 28 if strong else 18, text_color, strong)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return result

func _reward_row(parent: Node, icon_name: String, caption: String, description: String, action_text: String, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.texture = _texture("res://assets/recharge/" + icon_name + ".svg")
	icon.self_modulate = muted_color
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	row.add_child(column)
	_text(column, caption, 20, text_color, true)
	_text(column, description, 15, muted_color)
	var action := _action(column, action_text, callback)
	action.alignment = HORIZONTAL_ALIGNMENT_LEFT

func _rule(parent: Node) -> void:
	var line := _line(parent, Rect2())
	line.custom_minimum_size.y = 1

func _text(parent: Node, caption: String, font_size: int, color: Color, strong := false) -> Label:
	var label := _label(parent, caption, font_size, color, Rect2(), strong)
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _action(parent: Node, caption: String, callback: Callable, primary := false) -> Button:
	var button := _button(parent, "Action", caption, callback)
	_style_button(button, BLUE if primary else Color.TRANSPARENT, primary)
	button.add_theme_font_size_override("font_size", 18)
	button.clip_text = false
	button.custom_minimum_size.y = 38
	if not primary: button.add_theme_color_override("font_color", _accent())
	return button

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _state_changed() -> void:
	if not is_instance_valid(body) or _queued: return
	_queued = true
	_render.call_deferred()

func _render() -> void:
	_queued = false
	if not is_inside_tree() or not is_instance_valid(balance_amount): return
	if _generation != store.epoch:
		_generation = store.epoch
		if is_instance_valid(dialog): dialog.dismiss()
	balance_amount.set_value(Amount.grouped(int(store.balance)) if store.balance != null else "—")
	# Fit the full safe-integer range without hiding either the amount or its unit.
	balance_amount.number.add_theme_font_size_override("font_size", 46 if balance_amount.number.text.length() <= 10 else 29)
	balance_retry.text = "正在获取余额…" if store.balance_loading else (store.unavailable() if not store.available() else ("获取失败 · 点击重试" if not store.balance_error.is_empty() else ""))
	balance_retry.disabled = store.balance_loading
	balance_retry.visible = not balance_retry.text.is_empty()
	var hash_value := JSON.stringify(store.packages)
	if hash_value != _catalog_hash:
		_catalog_hash = hash_value
		_build_packages()
	package_status.visible = store.packages.is_empty()
	package_status.text = "正在获取充值套餐…" if store.catalog_loading else ("正式充值尚未开放\n套餐配置完成后将在这里展示。" if store.catalog_error.is_empty() else store.catalog_error)
	package_status.custom_minimum_size.y = 112 if store.packages.is_empty() else 0
	package_retry.visible = not store.catalog_error.is_empty() and not store.catalog_loading
	for button in package_grid.get_children():
		var chosen: bool = button.get_meta("package_id") == store.selected
		button.disabled = store.locked()
		button.set_pressed_no_signal(chosen)
		button.get_node("Selected").visible = chosen
		button.add_theme_stylebox_override("normal", _style((Tokens.DARK_SOFT if dark else Tokens.SOFT) if chosen else surface, 9, BLUE if chosen else border))
		_motion().bind_button(button)
	var channel_hash: String = JSON.stringify(store.channels) + store.confirmation_channel() + store.confirmation_channel_label() + str(store.locked())
	if channel_hash != _channel_hash:
		_channel_hash = channel_hash
		_build_channels()
	var profile := get_node("/root/ProfileStore")
	account_value.text = profile.display_name() if profile.authenticated() else "未登录"
	var public_id := str(profile.profile.get("public_id", ""))
	if not public_id.is_empty(): account_value.text += "\n" + public_id
	var item: Dictionary = store.confirmation_package()
	quantity_value.text = Amount.grouped(int(item.batteries)) + " 电池" if not item.is_empty() else "—"
	total_value.text = Amount.money(int(item.price_cents)) if not item.is_empty() else "—"
	total_value.add_theme_font_size_override("font_size", 28 if total_value.text.length() < 16 else 20)
	estimate_value.text = "—"
	if store.balance != null and not item.is_empty() and int(store.balance) <= Amount.MAX_INTEGER - int(item.batteries):
		estimate_value.text = Amount.grouped(int(store.balance) + int(item.batteries)) + " 电池（预计）"
	var unresolved: bool = not store.intent.is_empty()
	var pending_order: bool = not store.current_order.is_empty() and not store.terminal(store.orders.get(store.current_order, {}))
	pay_button.text = "创建订单…" if store.creating else "恢复原充值请求" if unresolved else "查看当前订单" if pending_order else "确认充值" + (" " + total_value.text if not item.is_empty() else "")
	pay_button.disabled = store.creating or (not unresolved and not pending_order and not store.checkout_reason().is_empty())
	_style_button(pay_button, BLUE, true)
	reason_label.text = store.error if not store.error.is_empty() else ("原订单处理中，套餐与渠道已锁定；请先查询该订单。" if pending_order or unresolved else store.checkout_reason())
	reason_label.visible = not reason_label.text.is_empty()
	resume.visible = not store.current_order.is_empty()
	footer.text = "充值档位与兑换比例仅作设计示意" if store.preview else str(store.rules.get("summary", "答题与投稿的电池奖励以正式开放的规则为准。"))
	_layout()

func _build_packages() -> void:
	_clear(package_grid)
	var group := ButtonGroup.new()
	for item in store.packages:
		var button := _button(package_grid, "Package_" + str(item.id).validate_node_name(), "", store.select_package.bind(str(item.id)))
		button.set_meta("package_id", str(item.id))
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 124)
		button.accessibility_name = "%s 电池，%s" % [Amount.grouped(int(item.batteries)), Amount.money(int(item.price_cents))]
		var amount := Amount.new()
		amount.name = "Amount"
		button.add_child(amount)
		amount.setup(self, Amount.grouped(int(item.batteries)), 36.0, 27, 17)
		if amount.number.text.length() >= 9: amount.number.add_theme_font_size_override("font_size", 18)
		amount.position = Vector2(22, 23)
		var price := _label(button, Amount.money(int(item.price_cents)), 23, text_color, Rect2(70, 74, 180, 34))
		price.name = "Price"
		if price.text.length() >= 13: price.add_theme_font_size_override("font_size", 17)
		button.custom_minimum_size.x = maxf(amount.get_combined_minimum_size().x + 44, price.get_combined_minimum_size().x + 88)
		var mark := TextureRect.new()
		mark.name = "Selected"
		mark.texture = _texture("res://assets/recharge/selected-check.svg")
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(mark)
		button.resized.connect(func():
			_rect(mark, Rect2(button.size.x - 31, 9, 22, 22))
			price.size.x = button.size.x - 88
			var digits: int = amount.number.text.length()
			amount.number.add_theme_font_size_override("font_size", 27 if digits < 9 else 18)
			price.add_theme_font_size_override("font_size", 23 if price.text.length() < 13 else 17))

func _build_channels() -> void:
	_clear(channel_box)
	if store.locked():
		_text(channel_box, store.confirmation_channel_label(), 18, text_color)
		return
	if store.channels.is_empty():
		_text(channel_box, "暂无已开通的支付渠道", 17, muted_color)
		return
	var group := ButtonGroup.new()
	for item in store.channels:
		var button := CheckBox.new()
		button.text = str(item.label)
		button.button_group = group
		button.set_pressed_no_signal(str(item.id) == store.channel)
		button.disabled = store.locked()
		button.add_theme_font_size_override("font_size", 18)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, text_color)
		button.add_theme_color_override("font_disabled_color", muted_color)
		button.custom_minimum_size.y = 38
		var brand := str(item.get("brand", ""))
		if brand in ["wechat-pay", "alipay"]:
			button.icon = _texture("res://assets/recharge/%s.svg" % brand)
			button.add_theme_constant_override("icon_max_width", 26)
			button.expand_icon = true
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(store.select_channel.bind(str(item.id)))
		channel_box.add_child(button)

func _layout_content(width: float) -> void:
	if not is_instance_valid(left): return
	_rect(bell, Rect2(width - 48, 6, 44, 44))
	_rect(balance_amount, Rect2(0, 0, 330, 62))
	var narrow := width < 1000
	var link_width := maxf(355, record_links.get_combined_minimum_size().x)
	_rect(record_links, Rect2(0 if narrow else width - link_width - 76, 76 if narrow else 12, link_width, 40))
	_rect(balance_retry, Rect2(0, 120 if narrow else 70, width, 28))
	var main_y := (182.0 if narrow else 132.0) if balance_retry.visible else (150.0 if narrow else 106.0)
	_rect(balance_line, Rect2(0, main_y - 25, width, 1))
	var left_width := width if narrow else (width - 68) * 0.58
	var card_width := 0.0
	for card in package_grid.get_children(): card_width = maxf(card_width, card.custom_minimum_size.x)
	package_grid.columns = 2 if left_width >= card_width * 2 + 18 else 1
	left.size.x = left_width
	left.position = Vector2(0, main_y)
	left.size.y = left.get_combined_minimum_size().y
	var right_width := width if narrow else width - left_width - 68
	right.size.x = right_width
	right.size.y = right.get_combined_minimum_size().y
	right.position = Vector2(0, main_y + left.size.y + 44) if narrow else Vector2(left_width + 68, main_y)
	_rect(separator, Rect2(0, right.position.y - 22, width, 1) if narrow else Rect2(left_width + 34, main_y, 1, maxf(left.size.y, right.size.y)))
	content_height = maxf(left.position.y + left.size.y, right.position.y + right.size.y) + 35
	# Container minimum sizes settle after text wrapping; defer one layout pass.
	if not left.minimum_size_changed.is_connected(_layout): left.minimum_size_changed.connect(_layout)
	if not right.minimum_size_changed.is_connected(_layout): right.minimum_size_changed.connect(_layout)

func _retry_balance() -> void:
	if store.account_id.is_empty(): get_node("/root/PageRouter").open_identity()
	else: store.refresh_balance()

func _publication() -> void:
	# Reuse a host's existing entry, never invent an editor or publish from this client.
	if store.available() and store.rules.get("publication", {}).get("entry_enabled", false) and store.provider.has_method("open_publication"):
		store.provider.open_publication()
	else: show_panel("publication")

func _help() -> void:
	if not store.current_order.is_empty(): _resume()
	else: show_panel("help")

func _resume() -> void:
	if store.current_order.is_empty(): return
	show_panel("order", store.current_order)
	store.query_order(store.current_order)

func _order_ready(id: String) -> void:
	if not is_inside_tree(): return
	if is_instance_valid(dialog): dialog.dismiss()
	show_panel("order", id)

func show_panel(mode: String, order_id := "") -> void:
	if is_instance_valid(dialog): return
	var focus := get_viewport().gui_get_focus_owner()
	_focus_return = weakref(focus) if focus != null else null
	dialog = Dialog.new()
	dialog.page = self
	dialog.store = store
	dialog.panel_mode = mode
	dialog.order_id = order_id
	dialog.closed.connect(_dialog_closed)
	add_child(dialog)
	dialog.present()

func _dialog_closed() -> void:
	dialog = null
	var focus: Control = _focus_return.get_ref() if _focus_return != null else null
	if is_instance_valid(focus) and focus.is_inside_tree(): focus.grab_focus()
	elif is_inside_tree() and is_instance_valid(pay_button): pay_button.grab_focus()

func consume_back_action() -> bool:
	if is_instance_valid(dialog):
		dialog.dismiss()
		return true
	return false
