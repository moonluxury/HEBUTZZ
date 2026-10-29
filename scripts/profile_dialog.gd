extends Window
const Styles = preload("res://scripts/ui_styles.gd")
## Exclusive, scrollable local panel. All async work belongs to the persistent store.
signal closed
const FIELD_LABELS := {"display_name": "显示名称", "bio": "个人简介", "school": "学校", "college": "学院", "major": "专业", "grade": "年级"}
var page: Control
var panel_mode := ""
var store: Node
var column: VBoxContainer
var panel: PanelContainer
var scroll_box: ScrollContainer
var shade: ColorRect
var message: Label
var confirm: Button
var close_button: Button
var cancel_button: Button
var fields: Dictionary = {}
var original_fields: Dictionary = {}
var session_epoch := 0
var ticket := ""
var busy := false
var closing := false

func _ready() -> void:
	store = get_node("/root/ProfileStore")
	session_epoch = store.epoch
	ticket = str(get_instance_id())
	transient = true
	exclusive = true
	borderless = true
	visible = false
	theme = page.theme
	title = {"edit": "编辑资料", "account": "账号与安全", "version": "版本信息", "login": "登录", "logout": "退出登录"}.get(panel_mode, "个人中心")
	min_size = Vector2i(340, 260)
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", page._style(page.surface, 8, page.border))
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll_box = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	scroll.add_child(margin)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	page._text(heading, title, 28, page.text_color, true)
	close_button = _action(heading, "关闭", dismiss)
	message = page._text(column, "", 18, page.muted_color)
	store.changed.connect(_session_changed)
	store.saved.connect(_saved)
	store.action_finished.connect(_action_finished)
	close_requested.connect(dismiss)
	window_input.connect(_input_window)
	match panel_mode:
		"edit": _build_edit()
		"account": _build_account()
		"version":
			page._text(column, str(ProjectSettings.get_setting("application/config/name", "")), 24, page.text_color, true)
			var version := str(ProjectSettings.get_setting("application/config/version", ""))
			message.text = "版本 " + version if not version.is_empty() else "当前构建未提供版本号。"
		"login":
			message.text = "登录后可管理你的个人资料。" if is_instance_valid(store.provider) and store.provider.has_method("begin_login") else "当前版本尚未接入登录服务。接入后可使用个人资料与账号管理。"
			if is_instance_valid(store.provider) and store.provider.has_method("begin_login"):
				confirm = _action(column, "前往登录", _run_action.bind("begin_login"), true)
		"logout":
			message.text = "退出当前账号？本地题库、学习记录和收藏存档会保留。"
			confirm = _action(column, "退出登录", _run_action.bind("logout"))

func _action(parent: Node, caption: String, action: Callable, primary := false) -> Button:
	var button: Button = page._button(parent, "Action", caption, action)
	page._style_button(button, page.BLUE if primary else Color.TRANSPARENT, primary)
	button.custom_minimum_size = Vector2(88, 46)
	button.set_meta("profile_primary", primary)
	return button

func refresh_theme() -> void:
	panel.add_theme_stylebox_override("panel", page._style(page.surface, 8, page.border))
	for label in column.find_children("*", "Label", true, false):
		label.add_theme_color_override("font_color", page.text_color)
	message.add_theme_color_override("font_color", page.muted_color)
	for button in column.find_children("*", "Button", true, false):
		var primary: bool = button.get_meta("profile_primary", false)
		page._style_button(button, page.BLUE if primary else Color.TRANSPARENT, primary)
	for edit in fields.values():
		_field_style(edit)

func _field_style(edit: Control) -> void:
	var style: StyleBoxFlat = page._style(page.surface, 6, page.border)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", style)
	Styles.apply_focus(edit, edit.get_theme_stylebox("normal") as StyleBoxFlat)
	edit.add_theme_color_override("font_color", page.text_color)
	edit.add_theme_color_override("font_placeholder_color", page.muted_color)
	edit.custom_minimum_size.y = 46
	page._motion().bind_input(edit)

func _build_edit() -> void:
	for field in FIELD_LABELS:
		page._text(column, FIELD_LABELS[field], 20, page.text_color)
		if not store.editable_fields.has(field):
			var value := str(store.profile.get(field, ""))
			page._text(column, (value if not value.is_empty() else "未填写") + "（不可编辑）", 18, page.muted_color)
			continue
		var edit: Control = TextEdit.new() if field == "bio" else LineEdit.new()
		edit.name = field
		edit.text = str(store.profile.get(field, ""))
		original_fields[field] = edit.text
		edit.accessibility_name = FIELD_LABELS[field]
		column.add_child(edit)
		_field_style(edit)
		if edit is TextEdit:
			edit.custom_minimum_size.y = 110
			edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		else:
			edit.max_length = int(store.editable_fields[field].get("max_length", 0))
		fields[field] = edit
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	cancel_button = _action(actions, "取消", dismiss)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm = _action(actions, "保存", _save, true)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.disabled = fields.is_empty()
	if confirm.disabled:
		message.text = "当前账号未提供可编辑字段，资料保存服务尚未接入或没有编辑权限。"

func _save() -> void:
	if busy or store.saving or confirm.disabled:
		return
	var patch: Dictionary = {}
	for field in fields:
		if fields[field].text != str(original_fields.get(field, "")):
			patch[field] = fields[field].text
	if patch.is_empty():
		dismiss()
		return
	_set_busy(true)
	message.text = "正在保存…"
	store.save_profile(patch, "", ticket)

func _saved(id: String, response: Dictionary) -> void:
	if closing or id != ticket or session_epoch != store.epoch:
		return
	_set_busy(false)
	message.text = str(response.get("message", ""))
	scroll_box.ensure_control_visible.call_deferred(message)
	if response.get("ok", false):
		page.feedback.text = message.text
		dismiss()

func _set_busy(value: bool) -> void:
	busy = value
	if is_instance_valid(confirm):
		confirm.disabled = value
		confirm.text = "保存中…" if value and panel_mode == "edit" else "保存" if panel_mode == "edit" else "处理中…" if value else "重试"
		page.sync_button_state(confirm)
	for field in fields.values():
		field.editable = not value
	if is_instance_valid(cancel_button):
		cancel_button.disabled = value
		page.sync_button_state(cancel_button)

func _build_account() -> void:
	message.text = "正在读取账号信息…"
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	if store.authenticated() and is_instance_valid(store.provider) and store.provider.has_method("open_account_settings"):
		_action(column, "管理登录与绑定信息", _run_action.bind("open_account_settings"))
	_run_action("request_account")

func _run_action(action: String) -> void:
	if busy:
		return
	_set_busy(true)
	message.text = "正在处理…"
	store.run_action(action, ticket + ":" + action)

func _action_finished(id: String, response: Dictionary) -> void:
	if closing or not id.begins_with(ticket + ":") or session_epoch != store.epoch:
		return
	_set_busy(false)
	message.text = str(response.get("message", "操作未完成，请重试。"))
	if not response.get("ok", false):
		return
	if id.ends_with(":request_account"):
		var lines: Array[String] = []
		if not str(response.get("login_method", "")).is_empty():
			lines.append("登录方式：" + str(response.login_method))
		# Only explicitly masked contact fields are allowed in this view.
		for field in {"masked_email": "邮箱", "masked_phone": "手机"}:
			var value := str(response.get(field, ""))
			if "*" in value or "•" in value:
				lines.append(("邮箱：" if field == "masked_email" else "手机：") + value)
		message.text = "\n".join(lines) if not lines.is_empty() else "服务未提供可展示的登录与绑定信息。"
	elif id.ends_with(":begin_login") or id.ends_with(":open_account_settings"):
		message.text = str(response.get("message", "请在已打开的账号流程中继续。"))

func _session_changed() -> void:
	if store.epoch != session_epoch:
		dismiss()

func present() -> void:
	popup_centered_clamped(Vector2i(640, 820 if panel_mode == "edit" else 330), 0.88)
	page._motion().enter(panel, page.Tokens.PANEL)
	if not fields.is_empty():
		fields.values()[0].grab_focus()
	else:
		close_button.grab_focus()

func _input_window(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		consume_back_action()

func consume_back_action() -> void:
	dismiss()

func dismiss() -> void:
	if closing:
		return
	closing = true
	fields.clear()
	original_fields.clear()
	hide()
	if is_instance_valid(shade):
		page._motion().retire(shade)
		shade = null
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(shade) and not shade.is_queued_for_deletion():
		shade.queue_free()
