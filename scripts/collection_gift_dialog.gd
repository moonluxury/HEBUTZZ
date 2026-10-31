extends Window
const CardArtwork = preload("res://scripts/card_artwork.gd")
const CollectionStore = preload("res://scripts/collection_store.gd")
const Avatar = preload("res://scripts/profile_avatar.gd")
const TransferUi = preload("res://scripts/card_transfer_ui.gd")
const DialogUi = preload("res://scripts/account_dialog_ui.gd")
const BASE_SIZE := Vector2(500, 748)
## Native exclusive window supplies focus confinement and Escape handling.
signal closed
const Styles = preload("res://scripts/ui_styles.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
var host: Control
var colors: Dictionary
var dark := false
var store: CollectionStore
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
var footer: VBoxContainer
var friends_scroll: ScrollContainer
var close_button: Button
var search_timer: Timer
var searching := false
var _fit_queued := false
var _current_query := ""
var _friends_error := false
var choose_card := false
var card_choice: OptionButton
var card_summary: Dictionary = {}
var inventory_retry: Button
var _choice_signature := ""
var _art_card_id := ""
var _close_serial := 0

func configure(owner_control: Control, collection: CollectionStore, selected_card: String, friend: Dictionary = {}) -> void:
	host = owner_control
	store = collection
	card_id = selected_card
	choose_card = selected_card.is_empty()
	selected_friend = friend.duplicate(true)

func _motion() -> Node:
	return get_node("/root/UiMotion")

func _texture(path: String) -> Texture2D:
	return get_node("/root/UiResources").texture(path)

func _stock_text() -> String:
	var count: int = store.count(card_id)
	return "拥有数量未接入" if count < 0 else "未拥有" if count == 0 else "拥有 %d 张" % count

func _ready() -> void:
	title = "赠送好友"
	transient = true
	exclusive = true
	borderless = true
	visible = false
	theme = get_node("/root/UiResources").page_theme
	dark = get_node("/root/AppState").dark_mode
	colors = TransferUi.colors(dark)
	_account = store.account_id
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(shade)
	var shell := TransferUi.shell(self, title, dismiss, colors)
	panel = shell.panel
	column = shell.column
	scroll_box = shell.scroll
	footer = shell.footer
	close_button = shell.close
	var body: VBoxContainer = shell.body
	body.add_theme_constant_override("separation",14)
	footer.add_theme_constant_override("separation",10)
	var card: Dictionary = store.card(card_id)
	var summary := TransferUi.summary(body, card, store.season(str(card.get("season_id", ""))), _stock_text(), colors)
	card_summary = summary
	card_art = summary.art
	stock = summary.amount
	if choose_card:
		summary.name.hide()
		card_choice = OptionButton.new()
		card_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_choice.clip_text = true
		card_choice.accessibility_name = "选择赠送的卡牌"
		summary.metadata.add_child(card_choice)
		summary.metadata.move_child(card_choice, 0)
		_style_card_choice()
		card_choice.item_selected.connect(_choose_card)
		inventory_retry = TransferUi.button(summary.metadata, "重试读取库存", _request_inventory, colors)
		inventory_retry.set_meta("transfer_link", true)
		DialogUi.style_button(inventory_retry, colors, false, false, true)
		inventory_retry.hide()
	DialogUi.rule(body, colors.border)
	var friends := VBoxContainer.new()
	friends.add_theme_constant_override("separation", 8)
	body.add_child(friends)
	TransferUi.label(friends, "选择好友", 18, colors, false, true)
	search = LineEdit.new()
	search.placeholder_text = "搜索昵称或账号 ID"
	search.accessibility_name = search.placeholder_text
	search.custom_minimum_size.y = 44
	search.max_length = 120
	search.add_theme_font_size_override("font_size", 16)
	friends.add_child(search)
	_style_search()
	var icon := TextureRect.new()
	icon.name = "SearchIcon"
	icon.texture = TransferUi.glyph("search", colors.muted)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(14, 13)
	icon.size = Vector2(18, 18)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	search.add_child(icon)
	search.text_changed.connect(_search_edited)
	search.text_submitted.connect(func(query): search_timer.stop(); _search_friends(query))
	search_timer = Timer.new()
	search_timer.one_shot = true
	search_timer.wait_time = 0.25
	search_timer.timeout.connect(func(): _search_friends(search.text))
	add_child(search_timer)
	friends_scroll = ScrollContainer.new()
	friends_scroll.custom_minimum_size.y = 224
	friends_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	friends_scroll.follow_focus = true
	friends.add_child(friends_scroll)
	var list_body := VBoxContainer.new()
	list_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_scroll.add_child(list_body)
	friend_status = TransferUi.label(list_body, "正在读取好友…", 16, colors, true)
	friends_list = VBoxContainer.new()
	friends_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_list.add_theme_constant_override("separation", 2)
	list_body.add_child(friends_list)
	DialogUi.rule(footer, colors.border)
	var quantity_row := HBoxContainer.new()
	footer.add_child(quantity_row)
	var caption := TransferUi.label(quantity_row, "赠送数量", 18, colors, false, true)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quantity = TransferUi.stepper(quantity_row, colors, "赠送数量", int(store.gift_rule(card_id).max))
	quantity.value_changed.connect(_sync.unbind(1))
	review = _text(footer, "", 16)
	review.hide()
	remaining = TransferUi.label(footer, "", 16, colors, true)
	error_label = TransferUi.label(footer, "", 14, colors, true)
	recovery = _action(footer, "查询上一笔赠送结果", _recover)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	footer.add_child(actions)
	var cancel := TransferUi.button(actions, "取消", dismiss, colors, false, true)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm = TransferUi.button(actions, "确认赠送 1 张", _submit, colors, true)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	store.changed.connect(_sync)
	store.operation_changed.connect(_sync)
	store.gift_completed.connect(_finished)
	store.friends_loaded.connect(_friends_arrived)
	close_requested.connect(dismiss)
	window_input.connect(_on_input)
	RenderingServer.frame_pre_draw.connect(_before_draw)
	get_tree().root.size_changed.connect(_schedule_fit)
	host.resized.connect(_schedule_fit)
	get_node("/root/AppState").font_scale_changed.connect(_schedule_fit.unbind(1))
	get_node("/root/AppState").color_mode_changed.connect(_theme_changed.unbind(1))
	_sync()
	_search_friends("")
	if choose_card and not store.inventory_known and not store.loading:
		_request_inventory.call_deferred()

func _before_draw() -> void:
	if not closing: TransferUi.render_density(self)

func _style_search() -> void:
	var style := Styles.box(colors.summary, 8)
	style.content_margin_left = 42
	style.content_margin_right = 12
	search.add_theme_stylebox_override("normal", style)
	search.add_theme_stylebox_override("read_only", style)
	search.add_theme_color_override("font_color", colors.text)
	search.add_theme_color_override("font_placeholder_color", colors.muted)
	Styles.apply_focus(search, style)
	_motion().bind_input(search)

func _theme_changed() -> void:
	if closing: return
	dark = get_node("/root/AppState").dark_mode
	colors = TransferUi.colors(dark)
	panel.add_theme_stylebox_override("panel", Styles.dialog_panel(self, panel, colors.surface, 14))
	for label in panel.find_children("*", "Label", true, false):
		label.add_theme_color_override("font_color", colors.muted if label.get_meta("transfer_muted", false) else colors.text)
	for control in panel.find_children("*", "PanelContainer", true, false):
		if control.get_meta("transfer_summary", false):
			var frame := Styles.box(colors.summary, 10)
			frame.set_content_margin_all(12)
			control.add_theme_stylebox_override("panel", frame)
		elif control.get_meta("transfer_stepper", false): control.add_theme_stylebox_override("panel", Styles.box(colors.surface, 8, colors.border))
	for button in panel.find_children("*", "Button", true, false):
		if not button.has_meta("friend_id"):
			DialogUi.style_button(button, colors, button.get_meta("transfer_primary", false), button.get_meta("transfer_outlined", false), button.get_meta("transfer_link",false))
	for line in panel.find_children("*", "ColorRect", true, false): line.color = colors.border
	quantity.get_line_edit().add_theme_color_override("font_color", colors.text)
	quantity.get_line_edit().add_theme_color_override("font_uneditable_color",colors.muted)
	quantity.get_line_edit().add_theme_color_override("font_readonly_color",colors.muted)
	close_button.add_theme_font_size_override("font_size", 16)
	search.get_node("SearchIcon").texture = TransferUi.glyph("search", colors.muted)
	_style_search()
	if choose_card: _style_card_choice()
	_sync()
	_schedule_fit()

func _schedule_fit() -> void:
	if closing or not visible or _fit_queued: return
	_fit_queued = true
	_refit.call_deferred()

func _refit() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_queued = false
	if not closing and visible: TransferUi.fit(self, BASE_SIZE, host, panel)


func _text(parent: Node, caption: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colors.text)
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = font_size + 6
	parent.add_child(label)
	return label

func _action(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = "Action"
	button.text = caption
	button.clip_text = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(84, 44)
	Styles.button(button, Color.TRANSPARENT, false, dark, 20)
	button.pressed.connect(action)
	parent.add_child(button)
	_motion().bind_button.call_deferred(button)
	return button

func present() -> void:
	TransferUi.fit(self, BASE_SIZE, host, panel, true)
	_schedule_fit()
	_motion().enter(shade, Tokens.PANEL)
	_motion().enter(panel, Tokens.PANEL)
	if choose_card and not card_choice.disabled: card_choice.grab_focus()
	else: search.grab_focus()

func _style_card_choice() -> void:
	Styles.button(card_choice, colors.surface, false, dark, 18)
	Styles.choice(card_choice, dark)
	card_choice.custom_minimum_size.y = 40
	_motion().bind_button(card_choice)

func _request_inventory() -> void:
	if not closing and not store.loading: store.refresh()

func _sync_card_choice() -> void:
	var choices: Array = []
	var eligible := 0
	if store.inventory_known:
		for card in store.cards:
			var maximum := int(store.gift_rule(str(card.id)).max)
			if maximum > 0 or str(card.id) == card_id:
				choices.append({"id":str(card.id), "name":str(card.name), "max":maximum})
			if maximum > 0: eligible += 1
	if card_id.is_empty() and not choices.is_empty(): card_id = str(choices[0].id)
	var signature := str([choices, card_id, store.inventory_known, store.loading])
	if signature != _choice_signature:
		_choice_signature = signature
		card_choice.clear()
		for entry in choices:
			card_choice.add_item("%s · 可赠 %d 张" % [entry.name, entry.max])
			var index := card_choice.item_count - 1
			card_choice.set_item_metadata(index, entry.id)
			card_choice.set_item_disabled(index, int(entry.max) <= 0)
			if entry.id == card_id: card_choice.select(index)
		if choices.is_empty():
			card_choice.add_item("暂无可赠卡牌" if store.inventory_known else "正在读取库存…" if store.loading else "库存暂不可用")
			card_choice.set_item_metadata(0, "")
		elif not choices.any(func(entry): return entry.id == card_id):
			# Never silently switch an already reviewed card after it disappears.
			card_choice.add_item("当前卡牌已不可用")
			card_choice.set_item_metadata(card_choice.item_count - 1, card_id)
			card_choice.select(card_choice.item_count - 1)
	card_choice.disabled = busy or store.pending() or store.loading or not store.inventory_known or eligible == 0
	inventory_retry.visible = not store.inventory_known and not store.loading
	inventory_retry.disabled = busy or store.pending()
	var card: Dictionary = store.card(card_id)
	card_art.visible = not card.is_empty()
	card_summary.season.visible = not card.is_empty()
	if not card.is_empty() and _art_card_id != card_id:
		_art_card_id = card_id
		card_art.texture = _texture(str(card.get("artwork", "")))
		card_art.custom_minimum_size.y = 80 * CardArtwork.ratio(card_art)
		card_summary.season.text = CardArtwork.season_title(store.season(str(card.get("season_id", ""))))

func _choose_card(index: int) -> void:
	if closing or busy or store.pending() or card_choice.disabled: return
	var id := str(card_choice.get_item_metadata(index))
	if id.is_empty() or id == card_id or int(store.gift_rule(id).max) <= 0: return
	card_id = id
	quantity.value = 1
	quantity.get_line_edit().text = "1 张"
	quantity.set_meta("manual_edit", false)
	error_label.text = ""
	_sync()

func _search_edited(_query: String) -> void:
	query_epoch += 1
	selected_friend = {}
	searching = true
	friend_status.text = "正在查找好友…"
	friend_status.show()
	_sync()
	search_timer.start()

func _search_friends(query: String) -> void:
	if closing: return
	search_timer.stop()
	query_epoch += 1
	_current_query = query
	searching = true
	_friends_error = false
	friend_status.text = "正在读取好友…"
	friend_status.show()
	for child in friends_list.get_children():
		friends_list.remove_child(child)
		child.queue_free()
	friend_rows.clear()
	_sync()
	store.search_friends(query, "%s:%s" % [get_instance_id(), query_epoch])

func _friends_arrived(ticket: String, response: Dictionary) -> void:
	if not is_inside_tree() or closing or ticket != "%s:%s" % [get_instance_id(), query_epoch] or _account != store.account_id:
		return
	searching = false
	if not response.get("ok", false):
		_friends_error = true
		friend_status.text = str(response.get("message", "好友读取失败，请重试。"))
		_action(friends_list, "重试", _search_friends.bind(search.text))
		_sync()
		return
	var friends: Array = response.get("friends", [])
	for friend in friends:
		if str(friend.get("id", "")).is_empty() or str(friend.id) == _account or friend.get("official", false) or friend.get("blocked", false) or not friend.get("is_friend", true):
			continue
		var row := Button.new()
		row.toggle_mode = true
		row.custom_minimum_size.y = 54
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.accessibility_name = "%s，ID %s" % [friend.get("name", "好友"), friend.get("public_id", friend.id)]
		friends_list.add_child(row)
		row.pressed.connect(_choose_friend.bind(friend))
		var margin := DialogUi.margin(row, 12)
		margin.add_theme_constant_override("margin_top", 5)
		margin.add_theme_constant_override("margin_bottom", 5)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_meta("person_controls", TransferUi.person(margin, friend, colors, true))
		row.set_meta("friend_id", friend.id)
		row.set_meta("friend", friend.duplicate(true))
		row.set_meta("eligible", friend.get("eligible", true))
		row.disabled = busy or not friend.get("eligible", true)
		row.gui_input.connect(_friend_input.bind(row))
		friend_rows.append(row)
		if selected_friend.get("id", "") == friend.id: selected_friend = friend.duplicate(true)
	friend_status.text = "暂无可赠送的好友" if _current_query.is_empty() else "没有找到匹配的好友"
	friend_status.visible = friend_rows.is_empty()
	if not friend_rows.any(func(row): return row.get_meta("friend_id") == selected_friend.get("id","")):
		selected_friend = {}
	_sync()

func _choose_friend(friend: Dictionary) -> void:
	if closing or busy or store.pending() or not friend.get("eligible", true): return
	selected_friend = friend.duplicate(true)
	_sync()

func _friend_input(event: InputEvent, row: Button) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode not in [KEY_UP, KEY_DOWN]: return
	row.accept_event()
	var index := friend_rows.find(row) + (1 if event.keycode == KEY_DOWN else -1)
	while index >= 0 and index < friend_rows.size():
		var next: Button = friend_rows[index]
		if not next.disabled:
			next.grab_focus()
			_choose_friend(next.get_meta("friend"))
			friends_scroll.ensure_control_visible(next)
			return
		index += 1 if event.keycode == KEY_DOWN else -1

func _style_friend(row: Button) -> void:
	var chosen: bool = row.get_meta("friend_id") == selected_friend.get("id", "")
	var signature := str([chosen, row.disabled, dark])
	if row.get_meta("painted", "") == signature: return
	row.set_meta("painted", signature)
	row.set_pressed_no_signal(chosen)
	Styles.button(row, colors.selection if chosen else colors.surface, false, dark, 16)
	_motion().bind_button(row, false, true)
	var controls: Dictionary = row.get_meta("person_controls")
	controls.radio.texture = TransferUi.glyph("circle-dot" if chosen else "circle", colors.accent if chosen else colors.muted)
	controls.name.add_theme_color_override("font_color", colors.muted if row.disabled else colors.text)
	controls.id.add_theme_color_override("font_color", colors.muted)
	controls.avatar.modulate.a = 0.6 if row.disabled else 1.0
	row.accessibility_description = "已选中" if chosen else "未选中"

func _sync() -> void:
	if not is_instance_valid(confirm) or closing:
		return
	if _account != store.account_id:
		set_meta("skip_transfer_exit",true)
		dismiss()
		return
	if choose_card: _sync_card_choice()
	var rule: Dictionary = store.gift_rule(card_id) if not card_id.is_empty() else {"max":0,"reason":"当前没有可赠卡牌，每种卡片需至少保留 1 张。" if store.inventory_known else "正在读取库存…" if store.loading else "库存暂不可用，请重试。"}
	stock.text = _stock_text()
	if choose_card and card_id.is_empty(): stock.text = str(rule.reason)
	# Preserve a now-invalid quantity after a service failure so the user sees why.
	var n := int(quantity.value)
	quantity.max_value = maxi(n, maxi(1, int(rule.max)))
	var name := str(store.card(card_id).get("name", ""))
	review.text = "请选择赠送对象。" if selected_friend.is_empty() else "将 %d 张「%s」赠送给 %s。" % [n, name, selected_friend.name]
	if n >= 1 and n <= int(rule.max):
		remaining.text = "送出后你将剩余 %d 张（至少保留 1 张）。\n每种卡片需至少保留 1 张。" % (store.count(card_id) - n)
	else:
		remaining.text = "每种卡片至少保留 1 张，当前最多可赠送 %d 张。" % int(rule.max)
	confirm.text = "正在提交…" if busy else "确认赠送 %d 张" % n
	confirm.disabled = busy or store.pending() or searching or _friends_error or selected_friend.is_empty() or n < 1 or n > int(rule.max) or not selected_friend.get("eligible", true)
	if choose_card and (store.loading or not store.inventory_known): confirm.disabled = true
	# Refresh this local button before its draw: changing a shared StyleBox from
	# inside the draw callback can otherwise leave an embedded window one draw behind.
	var feedback := confirm.get_node_or_null("UIFeedback")
	if feedback != null:
		feedback._check_disabled()
	confirm.queue_redraw()
	TransferUi.sync_stepper(quantity, not busy and not store.pending() and int(rule.max) > 0, int(rule.max))
	search.editable = not busy and not store.pending()
	recovery.visible = store.pending()
	recovery.disabled = busy or store.is_busy()
	for row in friend_rows:
		row.disabled = busy or store.pending() or searching or not row.get_meta("eligible", true)
		_style_friend(row)
	if store.pending():
		error_label.text = "上一笔赠送正在核实。关闭窗口不会取消已经提交的赠送。"
	elif not str(rule.get("reason", "")).is_empty():
		error_label.text = str(rule.reason)
	elif n > int(rule.max):
		error_label.text = "当前可赠数量已变化，请调整数量。"
	elif not str(rule.get("consequence", "")).is_empty():
		error_label.text = "" if str(rule.consequence) == store.KEEP_ONE_REASON else str(rule.consequence)
	elif error_label.text == store.KEEP_ONE_REASON:
		error_label.text = ""
	error_label.visible = not error_label.text.is_empty()
	confirm.accessibility_description = review.text

func _submit() -> void:
	if closing or busy: return
	TransferUi.commit_quantity(quantity)
	_sync()
	if confirm.disabled or busy:
		return
	busy = true
	error_label.text = ""
	_sync()
	# Store outlives this window. Closing cannot cancel or repeat an operation.
	store.submit_gift(card_id, str(selected_friend.id), int(quantity.value))

func _recover() -> void:
	if busy or closing:
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
	error_label.visible = not error_label.text.is_empty()
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
	_close_serial += 1
	set_meta("transfer_retiring",true)
	if is_instance_valid(shade): shade.set_meta("transfer_retiring",true)
	if not is_inside_tree() or not is_instance_valid(host) or not host.is_inside_tree():
		_finish_close()
		return
	if _motion().reduced() or DisplayServer.get_name() == "headless" or get_meta("skip_transfer_exit",false):
		_finish_close()
		return
	_motion().animate(self,panel,^"modulate:a",0.0,Tokens.EXIT,true)
	_motion().animate(self,shade,^"modulate:a",0.0,Tokens.EXIT,true)
	get_tree().create_timer(Tokens.EXIT).timeout.connect(_finish_close.bind(_close_serial))

func _finish_close(serial := -1) -> void:
	if is_queued_for_deletion() or (serial >= 0 and serial != _close_serial): return
	_close_serial += 1
	hide()
	if is_instance_valid(shade):
		shade.queue_free()
		shade = null
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	query_epoch += 1
	if is_instance_valid(shade) and not shade.is_queued_for_deletion():
		shade.queue_free()
