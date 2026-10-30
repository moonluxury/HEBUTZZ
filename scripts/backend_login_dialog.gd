extends Window
const Styles = preload("res://scripts/ui_styles.gd")
const DialogUi = preload("res://scripts/account_dialog_ui.gd")
signal finished(result: Dictionary)
var provider: Node
var password_mode := false
var registering := false
var username: LineEdit
var password: LineEdit
var confirmation: LineEdit
var current_password: LineEdit
var submit: Button
var close_button: Button
var mode_switch: Button
var mode_hint: Label
var shade: ColorRect
var panel: PanelContainer
var shell: VBoxContainer
var body: VBoxContainer
var scroll_box: ScrollContainer
var footer: VBoxContainer
var heading_label: Label
var subtitle: Label
var status: Label
var password_hint: Label
var remembered_box: VBoxContainer
var remembered_label: Label
var quick_login: Button
var forget_account: Button
var field_boxes: Dictionary = {}
var visibility_buttons: Dictionary = {}
var action_buttons: Array[Button] = []
var rules: Array[ColorRect] = []
var colors: Dictionary
var source_page: Control
var busy := false
var done := false
var fit_queued := false
var username_touched := false

func _ready() -> void:
	title = "修改密码" if password_mode else "账号登录"
	transient = true
	exclusive = true
	visible = false
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_size = Vector2i.ZERO
	min_size = Vector2i(340, 300)
	theme = get_node("/root/UiResources").page_theme
	colors = Styles.palette(get_node("/root/AppState").dark_mode)
	source_page = get_tree().current_scene as Control
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.22)
	get_parent().add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Styles.dialog_panel(self, panel, colors.surface, 12))
	add_child(panel)
	var margin := DialogUi.margin(panel)
	shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 22)
	margin.add_child(shell)
	var heading := HBoxContainer.new()
	shell.add_child(heading)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 8)
	heading.add_child(titles)
	heading_label = _label(titles, title, 28, false, true)
	subtitle = _label(titles, "更新你的登录密码" if password_mode else "欢迎回来", 18, true)
	close_button = DialogUi.close(heading, _cancel, colors, "关闭" + title)
	scroll_box = ScrollContainer.new()
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.follow_focus = true
	shell.add_child(scroll_box)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	scroll_box.add_child(body)
	if password_mode:
		current_password = _field(body, "当前密码", "请输入当前密码", true)
	else:
		_build_remembered(body)
		username = _field(body, "账号", "请输入账号", false)
		username.max_length = 32
		username.text = str(provider.remembered_account().get("username", ""))
		username.text_changed.connect(func(_value: String): username_touched = true)
	password = _field(body, "新密码" if password_mode else "密码", "请输入新密码" if password_mode else "请输入密码", true)
	password_hint = _label(field_boxes[password], "", 14, true)
	confirmation = _field(body, "确认密码", "请再次输入密码", true)
	field_boxes[confirmation].visible = password_mode
	status = _label(shell, "", 15, true)
	status.visible = false
	footer = VBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	shell.add_child(footer)
	submit = _action(footer, "确认修改" if password_mode else "登录", _submit, true)
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not password_mode:
		var mode_row := HBoxContainer.new()
		mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
		mode_row.add_theme_constant_override("separation", 6)
		footer.add_child(mode_row)
		mode_hint = _label(mode_row, "还没有账号？", 15, true)
		mode_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
		mode_hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mode_switch = _action(mode_row, "注册账号", _switch_mode)
		mode_switch.custom_minimum_size = Vector2(0, 32)
		mode_switch.set_meta("account_link", true)
		provider.remembered_changed.connect(_refresh_remembered)
		_refresh_remembered()
	else:
		password_hint.text = "至少 6 位；修改后所有设备需重新登录"
	close_requested.connect(_cancel)
	window_input.connect(_window_input)
	get_tree().root.size_changed.connect(_schedule_fit)
	if is_instance_valid(source_page): source_page.resized.connect(_schedule_fit)
	get_node("/root/AppState").font_scale_changed.connect(_schedule_fit.unbind(1))
	get_node("/root/AppState").color_mode_changed.connect(_refresh_theme.unbind(1))
	_refresh_theme()

func _label(parent: Node, text: String, size: int, muted := false, strong := false) -> Label:
	var control := DialogUi.label(parent, text, size, colors.muted if muted else colors.text, strong)
	control.set_meta("account_muted", muted)
	return control

func _action(parent: Node, text: String, action: Callable, primary := false, outlined := false) -> Button:
	var control := DialogUi.button(parent, text, action, colors, primary, outlined)
	control.set_meta("account_primary", primary)
	control.set_meta("account_outlined", outlined)
	action_buttons.append(control)
	return control

func _field(parent: Node, caption: String, placeholder: String, secret: bool) -> LineEdit:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 8)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)
	_label(holder, caption, 18)
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.accessibility_name = caption
	field.secret = secret
	field.max_length = 0
	field.custom_minimum_size.y = 48
	field.add_theme_font_size_override("font_size", 18)
	holder.add_child(field)
	field_boxes[field] = holder
	if secret:
		var toggle := Button.new()
		toggle.text = ""
		toggle.custom_minimum_size = Vector2(44, 44)
		field.add_child(toggle)
		toggle.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		toggle.offset_left = -46
		toggle.offset_right = -2
		toggle.offset_top = 2
		toggle.offset_bottom = -2
		toggle.pressed.connect(_toggle_password.bind(field))
		visibility_buttons[field] = toggle
	_style_field(field)
	field.text_submitted.connect(_submit_from.bind(field))
	return field

func _style_field(field: LineEdit) -> void:
	Styles.input(field, colors, 7)
	if visibility_buttons.has(field):
		for style_name in ["normal", "read_only", "focus"]:
			var box := field.get_theme_stylebox(style_name) as StyleBoxFlat
			if box != null: box.content_margin_right = 52
		var toggle: Button = visibility_buttons[field]
		DialogUi.style_button(toggle, colors)
		toggle.icon = DialogUi.glyph("eye" if field.secret else "eye_hidden", colors.muted)
		toggle.add_theme_constant_override("icon_max_width", 20)
		toggle.accessibility_name = ("显示" if field.secret else "隐藏") + field.accessibility_name
	get_node("/root/UiMotion").bind_input(field)

func _toggle_password(field: LineEdit) -> void:
	if busy or done: return
	var caret := field.caret_column
	var selection_start := field.get_selection_from_column()
	var selection_end := field.get_selection_to_column()
	var selected := field.has_selection()
	field.secret = not field.secret
	_style_field(field)
	field.grab_focus()
	field.caret_column = caret
	if selected: field.select(selection_start, selection_end)

func _submit_from(_text: String, field: LineEdit) -> void:
	if field.has_method("has_ime_text") and field.call("has_ime_text"): return
	if DisplayServer.has_feature(DisplayServer.FEATURE_IME) and not DisplayServer.ime_get_text().is_empty(): return
	_submit()

func _build_remembered(parent: Node) -> void:
	remembered_box = VBoxContainer.new()
	remembered_box.add_theme_constant_override("separation", 12)
	parent.add_child(remembered_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	remembered_box.add_child(row)
	remembered_label = _label(row, "", 16, true)
	remembered_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	forget_account = _action(row, "移除记录", _forget_account)
	forget_account.custom_minimum_size = Vector2(0, 32)
	forget_account.set_meta("account_link", true)
	quick_login = _action(remembered_box, "一键登录", _quick_login, false, true)
	rules.append(DialogUi.rule(remembered_box, colors.border))

func _refresh_remembered() -> void:
	if password_mode or done: return
	var saved: Dictionary = provider.remembered_account()
	remembered_box.visible = not registering and not saved.is_empty()
	remembered_label.text = "上次登录：" + str(saved.get("username", ""))
	quick_login.visible = not registering and bool(saved.get("can_resume", false))
	quick_login.disabled = busy or not saved.get("can_resume", false)
	forget_account.disabled = busy
	password_hint.text = "至少 6 位" if registering else "已记住账号，请输入密码登录" if not saved.is_empty() and not saved.get("can_resume", false) else ""
	password_hint.visible = not password_hint.text.is_empty()
	_schedule_fit()

func _refresh_theme() -> void:
	if done: return
	colors = Styles.palette(get_node("/root/AppState").dark_mode)
	panel.add_theme_stylebox_override("panel", Styles.dialog_panel(self, panel, colors.surface, 12))
	for label in panel.find_children("*", "Label", true, false):
		label.add_theme_color_override("font_color", colors.muted if label.get_meta("account_muted", false) else colors.text)
	for button in action_buttons:
		DialogUi.style_button(button, colors, button.get_meta("account_primary", false), button.get_meta("account_outlined", false), button.get_meta("account_link", false))
	close_button.icon = DialogUi.glyph("close", colors.text)
	DialogUi.style_button(close_button, colors)
	for field in field_boxes: _style_field(field)
	for line in rules: line.color = colors.border

func _notice(text: String, focus: Control = null) -> void:
	status.text = text
	status.visible = not text.is_empty()
	if is_instance_valid(focus):
		focus.grab_focus()
		scroll_box.ensure_control_visible.call_deferred(focus)
	_schedule_fit()

func _set_busy(value: bool) -> void:
	busy = value
	submit.disabled = value
	submit.text = "修改中…" if value and password_mode else "注册中…" if value and registering else "登录中…" if value else "确认修改" if password_mode else "注册并登录" if registering else "登录"
	for field in field_boxes: field.editable = not value
	for button in visibility_buttons.values(): button.disabled = value
	if not password_mode:
		mode_switch.disabled = value
		_refresh_remembered()

func _quick_login() -> void:
	if busy or done or password_mode or registering or quick_login.disabled: return
	_set_busy(true)
	_notice("正在验证上次登录…")
	var response: Dictionary = await provider.remembered_auth()
	if done:
		queue_free()
		return
	_set_busy(false)
	if response.get("ok", false):
		_finish(response)
	else:
		_refresh_remembered()
		_notice(str(response.get("message", "快捷登录暂未完成，请重试或使用密码登录。")), password if quick_login.disabled else null)

func _forget_account() -> void:
	if busy or done: return
	var old_username := str(provider.remembered_account().get("username", ""))
	if provider.forget_remembered_account():
		if username.text == old_username: username.clear()
		_refresh_remembered()
		_notice("已移除本机登录记录。", username)
	else:
		_notice("本机记录移除失败，请重试。")

func _switch_mode() -> void:
	_mode_changed(0 if registering else 1)

func _mode_changed(index: int) -> void:
	if busy or done or password_mode: return
	registering = index == 1
	field_boxes[confirmation].visible = registering
	heading_label.text = "注册账号" if registering else "账号登录"
	subtitle.text = "创建你的账号" if registering else "欢迎回来"
	mode_hint.text = "已有账号？" if registering else "还没有账号？"
	mode_switch.text = "返回登录" if registering else "注册账号"
	if registering and not username_touched and username.text == str(provider.remembered_account().get("username", "")): username.clear()
	elif not registering and username.text.is_empty(): username.text = str(provider.remembered_account().get("username", ""))
	password.clear()
	confirmation.clear()
	for field in visibility_buttons: field.secret = true; _style_field(field)
	_set_busy(false)
	_notice("")
	_refresh_remembered()
	username.grab_focus()

func _submit() -> void:
	if busy or done: return
	if not password_mode:
		if username.text.strip_edges().is_empty(): _notice("请输入账号。", username); return
		var pattern := RegEx.new()
		pattern.compile("^[A-Za-z0-9_]{4,32}$")
		if pattern.search(username.text.strip_edges()) == null: _notice("账号需要 4–32 位英文字母、数字或下划线。", username); return
	if password_mode and current_password.text.is_empty(): _notice("请输入当前密码。", current_password); return
	if password.text.is_empty(): _notice("请输入密码。", password); return
	if password.text.length() < 6: _notice("密码至少需要 6 位。", password); return
	if (registering or password_mode) and password.text != confirmation.text: _notice("两次输入的密码不一致。", confirmation); return
	_set_busy(true)
	_notice("正在修改密码…" if password_mode else "正在注册…" if registering else "正在登录…")
	var response: Dictionary
	if password_mode:
		response = await provider.change_password(current_password.text, password.text)
	else:
		response = await provider.password_auth(username.text.strip_edges(), password.text, registering)
	if done:
		queue_free()
		return
	_set_busy(false)
	if response.get("ok", false): _finish(response)
	else: _notice(str(response.get("message", "操作失败，请重试。")))

func _desired_size() -> Vector2:
	return Vector2(540, clampf(shell.get_combined_minimum_size().y + body.get_combined_minimum_size().y + 60, 380, 900))

func _schedule_fit() -> void:
	if done or not visible or fit_queued: return
	fit_queued = true
	_refit.call_deferred()

func _refit() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	fit_queued = false
	if not done and visible: DialogUi.fit(self, _desired_size(), source_page)

func present() -> void:
	DialogUi.fit(self, Vector2(540, 560 if password_mode or remembered_box.visible else 460), source_page, true)
	get_node("/root/UiMotion").enter(panel)
	_schedule_fit()
	if password_mode: current_password.grab_focus()
	elif quick_login.visible and not quick_login.disabled: quick_login.grab_focus()
	elif not username.text.is_empty(): password.grab_focus()
	else: username.grab_focus()

func _window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		_cancel()

func _cancel() -> void:
	_finish({"ok": false, "account_id": provider.account_id, "message": "已取消。"})

func _finish(result: Dictionary) -> void:
	if done: return
	done = true
	for field in visibility_buttons:
		field.clear()
		field.secret = true
	hide()
	if is_instance_valid(shade): shade.hide(); shade.queue_free(); shade = null
	finished.emit(result)
	# Keep an in-flight callback alive but invisible until it can discard its result.
	if not busy: queue_free()

func _exit_tree() -> void:
	if is_instance_valid(shade): shade.queue_free()
	if not done:
		done = true
		finished.emit({"ok": false, "account_id": "", "message": "账号窗口已关闭。"})
