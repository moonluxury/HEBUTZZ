extends Window
const Styles = preload("res://scripts/ui_styles.gd")
signal finished(result: Dictionary)
var provider: Node
var password_mode := false
var auth_mode: OptionButton
var username: LineEdit
var password: LineEdit
var confirmation: LineEdit
var current_password: LineEdit
var submit: Button
var status: Label
var remembered_box: VBoxContainer
var remembered_label: Label
var quick_login: Button
var forget_account: Button
var colors: Dictionary
var busy := false
var done := false

func _ready() -> void:
	title = "修改密码" if password_mode else "账号登录"
	transient = true
	exclusive = true
	visible = false
	min_size = Vector2i(360, 420)
	theme = get_node("/root/UiResources").page_theme
	colors = Styles.palette(get_node("/root/AppState").dark_mode)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Styles.box(colors.surface, 8, colors.border))
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	if password_mode:
		current_password = _field(column, "当前密码", true)
	else:
		auth_mode = OptionButton.new()
		auth_mode.add_item("登录")
		auth_mode.add_item("注册账号")
		auth_mode.item_selected.connect(_mode_changed)
		Styles.button(auth_mode, colors.surface, false, get_node("/root/AppState").dark_mode)
		Styles.choice(auth_mode, get_node("/root/AppState").dark_mode)
		column.add_child(auth_mode)
		_build_remembered(column)
		username = _field(column, "用户名：4–32 位字母、数字或下划线", false)
		username.max_length = 32
		username.text = str(provider.remembered_account().get("username", ""))
	password = _field(column, "新密码：至少 6 位" if password_mode else "密码：至少 6 位", true)
	confirmation = _field(column, "再次输入密码", true)
	confirmation.visible = password_mode
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", colors.muted)
	status.text = "修改后所有设备需重新登录。" if password_mode else "登录后可使用个人资料和好友。"
	status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(status)
	submit = Button.new()
	submit.text = "确认修改" if password_mode else "登录"
	submit.custom_minimum_size.y = 44
	Styles.button(submit, colors.surface, true, get_node("/root/AppState").dark_mode)
	submit.pressed.connect(_submit)
	column.add_child(submit)
	get_node("/root/UiMotion").bind_button.call_deferred(submit, true)
	close_requested.connect(_cancel)
	window_input.connect(_window_input)
	if not password_mode:
		provider.remembered_changed.connect(_refresh_remembered)
		_refresh_remembered()
		if remembered_box.visible and quick_login.disabled:
			status.text = "已记住账号，请输入密码登录。"

func _build_remembered(parent: Node) -> void:
	remembered_box = VBoxContainer.new()
	remembered_box.add_theme_constant_override("separation", 12)
	parent.add_child(remembered_box)
	remembered_label = Label.new()
	remembered_label.add_theme_color_override("font_color", colors.text)
	remembered_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	remembered_box.add_child(remembered_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	remembered_box.add_child(actions)
	quick_login = Button.new()
	quick_login.text = "一键登录"
	quick_login.custom_minimum_size = Vector2(150, 46)
	quick_login.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Styles.button(quick_login, colors.accent, true, get_node("/root/AppState").dark_mode)
	quick_login.pressed.connect(_quick_login)
	actions.add_child(quick_login)
	get_node("/root/UiMotion").bind_button.call_deferred(quick_login, true)
	forget_account = Button.new()
	forget_account.text = "移除记录"
	forget_account.custom_minimum_size = Vector2(120, 46)
	Styles.button(forget_account, colors.surface, false, get_node("/root/AppState").dark_mode)
	forget_account.pressed.connect(_forget_account)
	actions.add_child(forget_account)
	get_node("/root/UiMotion").bind_button.call_deferred(forget_account)

func _refresh_remembered() -> void:
	if password_mode or done: return
	var saved: Dictionary = provider.remembered_account()
	remembered_box.visible = auth_mode.selected == 0 and not saved.is_empty()
	remembered_label.text = "上次登录：" + str(saved.get("username", ""))
	quick_login.disabled = busy or not saved.get("can_resume", false)
	forget_account.disabled = busy
	var primary: bool = auth_mode.selected == 1 or not saved.get("can_resume", false)
	Styles.button(submit, colors.surface, primary, get_node("/root/AppState").dark_mode)
	if not primary: Styles.choice(submit, get_node("/root/AppState").dark_mode)
	get_node("/root/UiMotion").bind_button.call_deferred(submit, primary)
	if auth_mode.selected == 0:
		submit.text = "密码登录" if not saved.is_empty() else "登录"

func _quick_login() -> void:
	if busy or done or password_mode or auth_mode.selected != 0: return
	_set_busy(true)
	status.text = "正在验证上次登录…"
	var response: Dictionary = await provider.remembered_auth()
	if done: return
	_set_busy(false)
	if response.get("ok", false):
		password.clear()
		_finish(response)
	else:
		status.text = str(response.get("message", "快捷登录暂未完成，请重试或使用密码登录。"))
		_refresh_remembered()
		if quick_login.disabled: password.grab_focus()

func _forget_account() -> void:
	if busy or done: return
	var old_username := str(provider.remembered_account().get("username", ""))
	if provider.forget_remembered_account():
		if username.text == old_username: username.clear()
		_refresh_remembered()
		status.text = "已移除本机登录记录。"
		username.grab_focus()
	else:
		status.text = "本机记录移除失败，请重试。"

func _set_busy(value: bool) -> void:
	busy = value
	submit.disabled = value
	password.editable = not value
	confirmation.editable = not value
	if current_password != null: current_password.editable = not value
	if auth_mode != null:
		auth_mode.disabled = value
		username.editable = not value
		_refresh_remembered()

func _field(parent: Node, placeholder: String, secret: bool) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.secret = secret
	field.max_length = 0
	field.custom_minimum_size.y = 44
	Styles.input(field, colors)
	field.text_submitted.connect(func(_text: String): _submit())
	parent.add_child(field)
	return field

func present() -> void:
	popup_centered_clamped(Vector2i(560, 570 if not password_mode and remembered_box.visible else 430), 0.9)
	if password_mode:
		current_password.grab_focus()
	else:
		if remembered_box.visible and not quick_login.disabled:
			quick_login.grab_focus()
		elif not username.text.is_empty():
			password.grab_focus()
		else:
			username.grab_focus()

func _mode_changed(index: int) -> void:
	confirmation.visible = index == 1
	submit.text = "注册并登录" if index == 1 else "登录"
	status.text = "用户名创建后保持不变；显示名称可在个人资料中修改。" if index == 1 else "登录后可使用个人资料和好友。"
	if index == 1 and username.text == str(provider.remembered_account().get("username", "")):
		username.clear()
	elif index == 0 and username.text.is_empty():
		username.text = str(provider.remembered_account().get("username", ""))
	_refresh_remembered()

func _submit() -> void:
	if busy or done:
		return
	var registering: bool = not password_mode and auth_mode.selected == 1
	if password.text.length() < 6:
		status.text = "密码至少需要 6 位。"
		return
	if (registering or password_mode) and password.text != confirmation.text:
		status.text = "两次输入的密码不一致。"
		return
	if not password_mode:
		var pattern := RegEx.new()
		pattern.compile("^[A-Za-z0-9_]{4,32}$")
		if pattern.search(username.text.strip_edges()) == null:
			status.text = "用户名需要 4–32 位英文字母、数字或下划线。"
			return
	_set_busy(true)
	status.text = "正在处理…"
	var response: Dictionary
	if password_mode:
		response = await provider.change_password(current_password.text, password.text)
	else:
		response = await provider.password_auth(username.text.strip_edges(), password.text, registering)
	if done:
		return
	_set_busy(false)
	if response.get("ok", false):
		password.clear()
		confirmation.clear()
		if current_password != null:
			current_password.clear()
		_finish(response)
	else:
		status.text = str(response.get("message", "操作失败，请重试。"))

func _window_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		_cancel()

func _cancel() -> void:
	if busy:
		return
	_finish({"ok": false, "account_id": provider.account_id, "message": "已取消。"})

func _finish(result: Dictionary) -> void:
	if done:
		return
	done = true
	hide()
	finished.emit(result)
	queue_free()

func _exit_tree() -> void:
	if not done:
		done = true
		finished.emit({"ok": false, "account_id": "", "message": "账号窗口已关闭。"})
