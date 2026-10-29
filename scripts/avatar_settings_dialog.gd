extends Window
const Styles = preload("res://scripts/ui_styles.gd")
## Draft-only selection; ProfileStore owns submitted requests after this window closes.
signal closed
const Avatar = preload("res://scripts/profile_avatar.gd")
const Choice = preload("res://scripts/avatar_choice.gd")
const BASE_SIZE := Vector2(840, 900)
const GRID_GAP := 24
const MIN_CELL := 148
var page: Control
var panel_mode := "avatar"
var store: Node
var collection: Node
var panel: PanelContainer
var shade: ColorRect
var column: VBoxContainer
var scroll_box: ScrollContainer
var avatar_grid: GridContainer
var avatar_preview: TextureRect
var avatar_choices: Dictionary = {}
var message: Label
var confirm: Button
var cancel_button: Button
var close_button: Button
var close_glyph: Control
var login_hint: Label
var footer: BoxContainer
var lines: Array[ColorRect] = []
var secondary: Array[Label] = []
var session_epoch := 0
var ticket := ""
var saved_avatar := ""
var selected_avatar := ""
var saved_known := false
var dirty := false
var busy := false
var closing := false
var login_flow := ""
var login_provider: Node
var focused_avatar := ""
var request_id := ""
var context_message := ""
var fit_queued := false

class CloseGlyph extends Control:
	var ink := Color.BLACK:
		set(value):
			ink = value
			queue_redraw()
	func _draw() -> void:
		var center := size * 0.5
		draw_line(center + Vector2(-7, -7), center + Vector2(7, 7), ink, 1.8, true)
		draw_line(center + Vector2(-7, 7), center + Vector2(7, -7), ink, 1.8, true)

class ActionFocusCue extends Control:
	var button: Button
	var ink := Color.WHITE
	func _draw() -> void:
		if button.has_focus():
			draw_line(Vector2(size.x * 0.5 - 9, size.y - 5), Vector2(size.x * 0.5 + 9, size.y - 5), ink, 2, true)

func _ready() -> void:
	store = get_node("/root/ProfileStore")
	collection = get_node("/root/AppServices").collection_store()
	session_epoch = store.epoch
	ticket = Crypto.new().generate_random_bytes(16).hex_encode()
	transient = true
	exclusive = true
	borderless = true
	visible = false
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_size = Vector2i.ZERO
	title = "头像设置"
	min_size = Vector2i(340, 340)
	theme = page.theme
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := _margin(panel, 32)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 8)
	heading.add_child(titles)
	_text(titles, "头像设置", 32, true)
	_text(titles, "选择一个喜欢的头像", 20, false, true)
	close_button = _action(heading, "", dismiss)
	close_button.accessibility_name = "关闭头像设置"
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_glyph = CloseGlyph.new()
	close_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close_button.add_child(close_glyph)
	close_glyph.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	close_glyph.position = Vector2(-12, -12)
	close_glyph.size = Vector2(24, 24)
	scroll_box = ScrollContainer.new()
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll_box)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	scroll_box.add_child(body)
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 28)
	body.add_child(preview_row)
	avatar_preview = Avatar.new()
	avatar_preview.custom_minimum_size = Vector2(144, 144)
	avatar_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_row.add_child(avatar_preview)
	var preview_text := VBoxContainer.new()
	preview_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_text.add_theme_constant_override("separation", 10)
	preview_row.add_child(preview_text)
	_text(preview_text, "头像预览", 24, true)
	_text(preview_text, "选择头像，保存后生效", 20, false, true)
	_rule(body)
	_text(body, "选择头像", 24, true)
	avatar_grid = GridContainer.new()
	avatar_grid.columns = 4
	avatar_grid.add_theme_constant_override("h_separation", GRID_GAP)
	avatar_grid.add_theme_constant_override("v_separation", GRID_GAP)
	body.add_child(avatar_grid)
	var group := ButtonGroup.new()
	_add_choice("", "默认头像", group)
	for card in collection.cards:
		_add_choice(str(card.id), str(card.get("name", "头像 " + str(avatar_choices.size()))), group)
	message = _text(body, "", 16, false, true)
	message.visible = false
	_rule(column)
	footer = BoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	login_hint = _text(footer, "登录后可保存头像", 15, false, true)
	login_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	footer.add_child(actions)
	cancel_button = _action(actions, "取消", dismiss)
	confirm = _action(actions, "保存头像", _confirm, true)
	confirm.custom_minimum_size.x = 136
	store.changed.connect(_session_changed)
	store.saved.connect(_saved)
	store.avatar_login_finished.connect(_login_finished)
	collection.changed.connect(_sync)
	close_requested.connect(dismiss)
	window_input.connect(_window_input)
	size_changed.connect(_layout)
	panel.resized.connect(_layout)
	scroll_box.resized.connect(_layout)
	page.get_window().size_changed.connect(_schedule_fit)
	page.resized.connect(_schedule_fit)
	get_node("/root/AppState").font_scale_changed.connect(_schedule_fit.unbind(1))
	refresh_theme()
	_sync()
	if store.authenticated():
		store.refresh()
		collection.refresh()

func _margin(parent: Node, inset: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, inset)
	parent.add_child(margin)
	return margin

func _text(parent: Node, value: String, font_size: int, strong := false, muted := false) -> Label:
	var label: Label = page._text(parent, value, font_size, page.muted_color if muted else page.text_color, strong)
	label.custom_minimum_size.y = font_size + 4
	if muted: secondary.append(label)
	return label

func _rule(parent: Node) -> void:
	var line := ColorRect.new()
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	lines.append(line)

func _action(parent: Node, caption: String, callback: Callable, primary := false) -> Button:
	var button: Button = page._button(parent, "AvatarAction", caption, callback)
	button.set_meta("avatar_primary", primary)
	button.custom_minimum_size = Vector2(88, 46)
	button.focus_entered.connect(_action_focus.bind(button))
	if not caption.is_empty():
		var cue := ActionFocusCue.new()
		cue.name = "AvatarKeyboardFocus"
		cue.button = button
		cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(cue)
		cue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.focus_entered.connect(cue.queue_redraw)
		button.focus_exited.connect(cue.queue_redraw)
	return button

func _action_focus(button: Button) -> void:
	Styles.apply_focus(button)

func _add_choice(id: String, caption: String, group: ButtonGroup) -> void:
	var button := Choice.new()
	button.button_group = group
	button.accessibility_name = caption
	avatar_grid.add_child(button)
	button.picture.show_card(id)
	button.pressed.connect(_select_card_avatar.bind(id))
	button.gui_input.connect(_choice_input.bind(id))
	button.focus_entered.connect(_choice_focus.bind(id))
	avatar_choices[id] = {"button": button, "picture": button.picture, "name": caption}

func refresh_theme() -> void:
	panel.add_theme_stylebox_override("panel", page._style(page.surface, 12, page.border))
	for label in column.find_children("*", "Label", true, false):
		label.add_theme_color_override("font_color", page.muted_color if label in secondary else page.text_color)
	for line in lines: line.color = page.border
	for button in [close_button, cancel_button, confirm]:
		var primary: bool = button.get_meta("avatar_primary", false)
		page._style_button(button, page.BLUE if primary else Color.TRANSPARENT, primary)
		button.add_theme_font_size_override("font_size", 18)
		var cue: Control = button.get_node_or_null("AvatarKeyboardFocus")
		if cue != null:
			cue.ink = Color.WHITE if primary else page._accent()
			cue.queue_redraw()
		if button.has_focus(): _action_focus.call_deferred(button)
		if button == cancel_button:
			for state in ["normal", "hover", "pressed", "disabled"]:
				button.add_theme_stylebox_override(state, page._style(Color.TRANSPARENT, 7, page.border))
	close_glyph.ink = page.text_color
	_sync()

func _layout() -> void:
	if not is_instance_valid(avatar_grid) or not is_instance_valid(footer): return
	var bar := scroll_box.get_v_scroll_bar()
	# Use the viewport, not a container still held wide by the previous column count.
	var logical_width := get_visible_rect().size.x
	var width := logical_width - 66.0 - (bar.size.x if bar.visible else 0.0)
	if width > 0:
		avatar_grid.columns = clampi(int((width + GRID_GAP) / float(MIN_CELL + GRID_GAP)), 1, 4)
		var side := maxf(MIN_CELL, floorf((width - GRID_GAP * (avatar_grid.columns - 1)) / avatar_grid.columns))
		for item in avatar_choices.values():
			item.button.custom_minimum_size = Vector2(MIN_CELL, side)
	footer.vertical = logical_width < 520

func _schedule_fit() -> void:
	if closing or not visible or fit_queued: return
	fit_queued = true
	_refit.call_deferred()

func _refit() -> void:
	fit_queued = false
	if not closing and visible: _fit_to_page(false)

func _fit_to_page(opening: bool) -> void:
	var owner_window: Window = page.get_window()
	var bounds: Rect2 = owner_window.get_visible_rect()
	var ui_scale: float = page.canvas.get_global_transform_with_canvas().get_scale().x
	if not is_embedded():
		bounds = Rect2(Vector2(owner_window.position), Vector2(owner_window.size))
		ui_scale *= owner_window.get_stretch_transform().get_scale().x
	# Match the page's UI scale, with a legible floor for short/narrow windows.
	ui_scale = maxf(0.85, minf(ui_scale, bounds.size.y / (BASE_SIZE.y + 48.0)))
	content_scale_factor = ui_scale
	var safe := bounds.grow(-24.0 * ui_scale)
	var target := Vector2i((BASE_SIZE * ui_scale).min(safe.size))
	min_size = Vector2i(Vector2(340, 340) * ui_scale).min(target)
	var origin := Vector2i(bounds.position + (bounds.size - Vector2(target)) * 0.5)
	if opening: popup(Rect2i(origin, target))
	# Embedded popup() may clamp virtual coordinates to the host monitor's pixels.
	# The target has already been bounded against the actual owner viewport.
	size = target
	position = origin
	_layout.call_deferred()

func present() -> void:
	_fit_to_page(true)
	_layout()
	page._motion().enter(panel, page.Tokens.PANEL)
	var initial: String = selected_avatar if avatar_choices.has(selected_avatar) else ""
	if not avatar_choices[initial].button.disabled:
		avatar_choices[initial].button.focus_mode = Control.FOCUS_ALL
		avatar_choices[initial].button.grab_focus()
	else: close_button.grab_focus()

func _sync() -> void:
	if closing or not is_instance_valid(confirm): return
	if not context_message.is_empty() and message.text == context_message: message.text = ""
	context_message = ""
	var authenticated: bool = store.authenticated()
	if authenticated and not store.profile.is_empty() and store.profile.has("avatar_card_id"):
		saved_avatar = str(store.profile.avatar_card_id)
		saved_known = true
		if not dirty: selected_avatar = saved_avatar
	elif not authenticated:
		saved_known = false
		if not dirty: selected_avatar = ""
	var unresolved: bool = not store.avatar_pending.is_empty()
	if unresolved and not dirty:
		selected_avatar = str(store.avatar_pending.card_id)
		dirty = true
	avatar_preview.show_card(selected_avatar)
	var known: bool = collection.account_id == store.account_id and collection.inventory_known
	for id in avatar_choices:
		var item: Dictionary = avatar_choices[id]
		var allowed: bool = not authenticated or id.is_empty() or (known and collection.count(id) > 0)
		var disabled: bool = busy or store.saving or not login_flow.is_empty() or unresolved or (authenticated and (not allowed or collection.loading or not store.avatar_editable()))
		item.button.disabled = disabled
		item.button.configure(id == selected_avatar and (saved_known or dirty or not authenticated), authenticated and not id.is_empty() and not allowed, page._accent(), page.surface)
		item.button.accessibility_name = str(item.name) + ("，已选中" if item.button.selected else "") + ("，不可用" if not allowed else "")
	if not avatar_choices.has(focused_avatar) or avatar_choices[focused_avatar].button.disabled:
		for id in avatar_choices:
			if not avatar_choices[id].button.disabled:
				focused_avatar = id
				break
	for id in avatar_choices:
		avatar_choices[id].button.focus_mode = Control.FOCUS_ALL if id == focused_avatar else Control.FOCUS_NONE
	if not avatar_choices.has(selected_avatar) and message.text.is_empty():
		_notice("当前头像素材暂不可用，可以选择其他头像。")
	login_hint.visible = not authenticated
	confirm.text = "保存中…" if busy or store.saving else "正在登录…" if not login_flow.is_empty() else "核实保存结果" if unresolved else "保存头像" if authenticated else "登录后保存"
	var issue: String = store.validate_card_avatar(selected_avatar) if authenticated else ""
	if dirty and authenticated and not issue.is_empty(): _notice(issue)
	var missing := not selected_avatar.is_empty() and avatar_preview.texture == Avatar.DEFAULT
	confirm.disabled = busy or store.saving or not login_flow.is_empty() or (authenticated and (not saved_known or store.loading or (not unresolved and (selected_avatar == saved_avatar or not issue.is_empty()))))
	if missing and authenticated: confirm.disabled = true
	if missing: _notice("头像图片暂时无法加载，可关闭后重试。")
	page.sync_button_state(confirm)
	message.visible = not message.text.is_empty()
	if authenticated and not saved_known and not busy and message.text.is_empty():
		_notice("正在读取当前头像…" if store.loading else "当前头像读取失败，请关闭后重试。")
		message.visible = true

func _notice(value: String) -> void:
	if message.text.is_empty():
		context_message = value
		message.text = value

func _select_card_avatar(id: String) -> void:
	if closing or not avatar_choices.has(id) or avatar_choices[id].button.disabled: return
	selected_avatar = id
	dirty = true
	request_id = ""
	message.text = ""
	_sync()

func _choice_focus(id: String) -> void:
	focused_avatar = id
	for key in avatar_choices:
		avatar_choices[key].button.focus_mode = Control.FOCUS_ALL if key == id else Control.FOCUS_NONE
	scroll_box.ensure_control_visible(avatar_choices[id].button)

func _choice_input(event: InputEvent, id: String) -> void:
	if not event is InputEventKey or not event.pressed: return
	var step: int = {KEY_LEFT: -1, KEY_RIGHT: 1, KEY_UP: -avatar_grid.columns, KEY_DOWN: avatar_grid.columns}.get(event.keycode, 0)
	if step == 0: return
	avatar_choices[id].button.accept_event()
	var keys: Array = avatar_choices.keys()
	var next := keys.find(id) + step
	while next >= 0 and next < keys.size():
		var candidate: Button = avatar_choices[keys[next]].button
		if not candidate.disabled:
			candidate.focus_mode = Control.FOCUS_ALL
			candidate.grab_focus()
			return
		next += step

func _confirm() -> void:
	if confirm.disabled or closing: return
	if not store.authenticated():
		login_provider = store.provider
		login_flow = ticket + ":" + Crypto.new().generate_random_bytes(8).hex_encode()
		message.text = ""
		_sync()
		store.begin_avatar_login(login_flow)
		return
	busy = true
	if request_id.is_empty(): request_id = Crypto.new().generate_random_bytes(24).hex_encode()
	message.text = ""
	_sync()
	store.save_avatar(selected_avatar, ticket, request_id)

func _saved(id: String, response: Dictionary) -> void:
	if closing or id != ticket or session_epoch != store.epoch: return
	busy = false
	if response.get("ok", false):
		page.feedback.text = "头像已更新"
		dismiss()
		return
	message.text = str(response.get("message", "保存失败，请重试。"))
	_sync()
	scroll_box.ensure_control_visible.call_deferred(message)

func _session_changed() -> void:
	if closing: return
	if store.epoch != session_epoch:
		if not login_flow.is_empty(): return
		dismiss()
		return
	_sync()

func _login_finished(flow: String, response: Dictionary) -> void:
	if closing or flow != login_flow: return
	login_flow = ""
	var matched: bool = response.get("ok", false) and response.get("avatar_login_context") == flow and response.get("session_epoch") == store.epoch and response.get("account_id") == store.account_id and store.provider == login_provider
	if matched:
		session_epoch = store.epoch
		saved_known = false
		# Login only restores this draft; the user must still click Save.
		dirty = true
		message.text = ""
		collection.refresh()
	elif store.epoch != session_epoch:
		dismiss()
		return
	else:
		message.text = str(response.get("message", "登录未完成，请重试。"))
	_sync()
	if not confirm.disabled: confirm.grab_focus()
	else: close_button.grab_focus()

func _window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		dismiss()

func consume_back_action() -> void: dismiss()

func dismiss() -> void:
	if closing: return
	closing = true
	login_flow = ""
	selected_avatar = ""
	hide()
	if is_instance_valid(shade):
		page._motion().retire(shade)
		shade = null
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(shade) and not shade.is_queued_for_deletion(): shade.queue_free()
