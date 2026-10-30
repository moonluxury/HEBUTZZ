extends Window
const Styles = preload("res://scripts/ui_styles.gd")
## Exclusive window contains keyboard focus and leaves the selected package intact.
signal closed
var page: Control
var store: Node
var panel_mode := ""
var order_id := ""
var panel: PanelContainer
var content: VBoxContainer
var status_label: Label
var close_button: Button
var shade: ColorRect
var closing := false
var _epoch := -1
var _ticket := ""
var _cursor := ""
var _filter := "all"
var _rows: Array = []
var _busy := false
var _loaded := false
var _order_hash := ""

func _ready() -> void:
	_epoch = store.epoch
	transient = true
	exclusive = true
	borderless = true
	visible = false
	theme = page.theme
	title = {"ledger": "电池明细", "orders": "充值记录", "order": "充值订单", "rules": "充值说明", "help": "支付遇到问题", "publication": "投稿得电池"}.get(panel_mode, "充值")
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := Styles.dialog_panel(self, panel, page.surface)
	frame.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", frame)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	page._text(heading, title, 27, page.text_color, true)
	close_button = page._action(heading, "关闭", dismiss)
	status_label = page._text(column, "", 16, page.muted_color)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	column.add_child(content)
	store.changed.connect(_changed)
	store.completed.connect(_response)
	close_requested.connect(dismiss)
	window_input.connect(_input_window)
	match panel_mode:
		"ledger", "orders": _load_records()
		"order": _order()
		"rules":
			_text(str(store.rules.get("description", "正式充值规则尚未配置，当前不提供真实收款。")))
			if store.preview: _text("充值档位与兑换比例仅作设计示意。当前为隔离预览，不产生真实支付。")
			_text("电池可通过答题、投稿和充值获得。投稿奖励须审核通过并发表。未到账数量不计入可用余额。")
		"publication":
			_text("应用内投稿入口尚未开放。现有投稿说明可在河工开物的征稿公告查看。")
			_text("稿件须审核通过并发表后，按正式规则获得电池。当前尚未接入发表状态与电池奖励服务。")
			_action("查看现有征稿说明 →", _publication_notice)
		"help":
			_text("已付款或结果未知时，请从充值记录查询原订单。关闭支付窗口不代表订单已取消；请勿重复支付来尝试恢复。")
			_action("查看充值记录 →", _navigate.bind("orders", ""))
			_text("当前未配置在线支付支持渠道。")

func _text(value: String, strong := false) -> Label:
	return page._text(content, value, 19, page.text_color if strong else page.muted_color, strong)

func _action(caption: String, callback: Callable, primary := false) -> Button:
	return page._action(content, caption, callback, primary)

func _load_records() -> void:
	if _busy: return
	_busy = true
	status_label.text = "正在加载…"
	_ticket = str(get_instance_id()) + ":" + str(Time.get_ticks_usec())
	store.read_records(panel_mode, _cursor, _filter, _ticket)

func _response(ticket: String, response: Dictionary) -> void:
	if closing or _epoch != store.epoch or ticket != _ticket: return
	_busy = false
	status_label.text = "" if response.get("ok", false) else store.message(response)
	if panel_mode == "order":
		_order()
		return
	if response.get("ok", false):
		_loaded = true
		for row in response.items:
			var index := _rows.find_custom(func(old): return old.id == row.id)
			if index < 0: _rows.append(row)
			else: _rows[index] = row
		_cursor = str(response.get("next_cursor", ""))
	_records()

func _records() -> void:
	page._clear(content)
	if panel_mode == "ledger":
		var filters := HBoxContainer.new()
		content.add_child(filters)
		for value in [["all", "全部"], ["income", "收入"], ["expense", "支出"]]:
			var button: Button = page._action(filters, value[1], _set_filter.bind(value[0]))
			button.disabled = _busy
			page._tab(button, _filter == value[0])
	if _rows.is_empty() and _loaded: _text("暂无电池明细" if panel_mode == "ledger" else "暂无充值记录")
	for row in _rows:
		if panel_mode == "ledger":
			var source: String = {"recharge": "充值", "quiz": "答题奖励", "publication": "稿件发表奖励", "spend": "消费", "opening": "期初余额", "adjustment": "余额调整"}.get(str(row.get("source", "")), str(row.get("description", "电池变动")))
			_text("%s    %s%s 电池" % [source, "+" if int(row.delta) > 0 else "", page.Amount.grouped(int(row.delta))], true)
			_text("%s\n业务引用：%s" % [row.get("created_at", ""), row.reference])
			if not str(row.get("order_id", "")).is_empty(): _action("查看关联订单 →", _navigate.bind("order", str(row.order_id)))
		else:
			var canonical: Dictionary = store.orders.get(str(row.id), row)
			_text("%s    %s 电池" % [page.Amount.money(int(canonical.price_cents)), page.Amount.grouped(int(canonical.batteries))], true)
			_text("订单 %s\n%s · %s\n%s" % [canonical.id, canonical.get("created_at", ""), canonical.get("channel_label", canonical.channel), store.status(canonical)])
			_action("查看订单 →", _navigate.bind("order", str(row.id)))
		page._rule(content)
	if not _cursor.is_empty() or not _loaded or not status_label.text.is_empty():
		var button := _action("重试" if not status_label.text.is_empty() else "加载更多", _load_records)
		button.disabled = _busy

func _set_filter(value: String) -> void:
	if _busy: return
	_filter = value
	_cursor = ""
	_rows = []
	_loaded = false
	_load_records()

func _order() -> void:
	var value: Dictionary = store.orders.get(order_id, {})
	_order_hash = JSON.stringify(value)
	status_label.text = "正在查询原订单…" if _busy else store.error
	page._clear(content)
	if value.is_empty():
		_text("订单信息尚未加载。")
		_action("查询原订单", _query)
		return
	_text(store.status(value), true)
	if value.get("credit_status") == "credited":
		var amount: HBoxContainer = page.Amount.new()
		content.add_child(amount)
		amount.setup(page, "+" + page.Amount.grouped(int(value.batteries)), 36.0, 30, 18)
		page._motion().enter(amount, page.Tokens.PANEL)
	else: _text("到账数量：%s 电池" % page.Amount.grouped(int(value.batteries)))
	_text("充值账户：%s\n应付金额：%s\n支付渠道：%s\n订单号：%s\n创建时间：%s" % [value.get("account_label", "当前登录账户"), page.Amount.money(int(value.price_cents)), value.get("channel_label", value.channel), value.id, value.get("created_at", "")])
	if value.payment_status == "pending":
		var url: String = store.payment_url(order_id)
		if not url.is_empty(): _action("前往支付", _open_payment, true)
		else:
			_text("支付入口暂不可用或已过期，请先查询原订单。" if not store.preview else "隔离测试订单，不提供真实二维码或支付跳转。")
		_text("关闭此窗口不会取消订单。支付页面返回后请查询原订单。")
	if value.payment_status == "pending":
		var query := _action("我已支付 · 查询状态", _query)
		query.disabled = _busy
	_action("查看充值记录 →", _navigate.bind("orders", ""))
	if value.get("credit_status") == "credited": _action("查看电池明细 →", _navigate.bind("ledger", ""))
	if not store.error.is_empty(): status_label.text = store.error

func _query() -> void:
	if _busy: return
	_busy = true
	_ticket = str(get_instance_id()) + ":query"
	_order()
	store.query_order(order_id, _ticket)

func _open_payment() -> void:
	var url: String = store.payment_url(order_id)
	if url.is_empty():
		status_label.text = "支付入口已过期，请先查询原订单。"
		_query()
		return
	if OS.shell_open(url) != OK: status_label.text = "无法打开支付页面，请查询订单后重试。"

func _changed() -> void:
	if _epoch != store.epoch:
		dismiss()
		return
	if not closing and panel_mode == "order" and _order_hash != JSON.stringify(store.orders.get(order_id, {})): _order()

func _navigate(mode: String, id: String) -> void:
	dismiss()
	page.show_panel.call_deferred(mode, id)
	if mode == "order": store.query_order(id)

func _publication_notice() -> void:
	dismiss()
	page._go("res://scenes/HegongKaiwu.tscn")

func present() -> void:
	popup_centered_clamped(Vector2i(660, 680), 0.9)
	if panel_mode == "order": store.watch_order(order_id, self)
	page._motion().enter(panel, page.Tokens.PANEL)
	close_button.grab_focus()

func _input_window(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		dismiss()

func dismiss() -> void:
	if closing: return
	closing = true
	if panel_mode == "order" and is_instance_valid(store): store.watch_order("")
	hide()
	if is_instance_valid(shade): shade.queue_free()
	shade = null
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(shade): shade.queue_free()
