extends Window
const Styles = preload("res://scripts/ui_styles.gd")
const DialogUi = preload("res://scripts/account_dialog_ui.gd")
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
var editor_shell: VBoxContainer
var editor_grid: GridContainer
var editor_footer: VBoxContainer
var displayed_fields: Dictionary = {}
var editor_rules: Array[ColorRect] = []
var fit_queued := false
var syncing_fields := false
var request_id := ""
var account_values: Dictionary = {}
var account_actions: Array[Button] = []
var refresh_button: Button
var manage_button: Button

func _ready() -> void:
	store = get_node("/root/ProfileStore")
	session_epoch = store.epoch
	ticket = Crypto.new().generate_random_bytes(16).hex_encode()
	transient = true
	exclusive = true
	borderless = true
	visible = false
	theme = page.theme
	title = {"edit": "编辑资料", "account": "账号与安全", "login": "登录", "logout": "退出登录"}.get(panel_mode, "个人中心")
	min_size = Vector2i(340, 260)
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.09, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", Styles.dialog_panel(self, panel, page.surface, 12 if panel_mode in ["edit", "account"] else 8))
	add_child(panel)
	if panel_mode in ["edit", "account"]:
		_build_editor_shell()
	else:
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
	panel.add_theme_stylebox_override("panel", Styles.dialog_panel(self, panel, page.surface, 12 if panel_mode in ["edit", "account"] else 8))
	for label in panel.find_children("*", "Label", true, false):
		label.add_theme_color_override("font_color", page.muted_color if label.get_meta("account_muted", false) else page.text_color)
	message.add_theme_color_override("font_color", page.muted_color)
	for button in column.find_children("*", "Button", true, false):
		var primary: bool = button.get_meta("profile_primary", false)
		page._style_button(button, page.BLUE if primary else Color.TRANSPARENT, primary)
	for edit in displayed_fields.values() if panel_mode == "edit" else fields.values():
		_field_style(edit)
	if panel_mode in ["edit", "account"]:
		close_button.icon = DialogUi.glyph("close", page.text_color)
		DialogUi.style_button(close_button, Styles.palette(page.dark))
		if is_instance_valid(cancel_button): DialogUi.style_button(cancel_button, Styles.palette(page.dark), false, true)
		DialogUi.style_button(confirm, Styles.palette(page.dark), true)
		for button in account_actions: DialogUi.style_button(button, Styles.palette(page.dark), false, true)
		for line in editor_rules: line.color = page.border
		_update_edit_state()
		_schedule_fit()

func _field_style(edit: Control) -> void:
	var style: StyleBoxFlat = page._style(page.surface, 6, page.border)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("read_only", style)
	Styles.apply_focus(edit, edit.get_theme_stylebox("normal") as StyleBoxFlat)
	edit.add_theme_color_override("font_color", page.text_color)
	edit.add_theme_color_override("font_uneditable_color", page.muted_color)
	edit.add_theme_color_override("font_readonly_color", page.muted_color)
	edit.add_theme_color_override("font_placeholder_color", page.muted_color)
	edit.custom_minimum_size.y = 46
	page._motion().bind_input(edit)

func _build_editor_shell() -> void:
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_size = Vector2i.ZERO
	var margin := DialogUi.margin(panel)
	editor_shell = VBoxContainer.new()
	editor_shell.add_theme_constant_override("separation", 20)
	margin.add_child(editor_shell)
	var heading := HBoxContainer.new()
	editor_shell.add_child(heading)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 8)
	heading.add_child(titles)
	DialogUi.label(titles, title, 28, page.text_color, true)
	var subtitle := DialogUi.label(titles, "完善你的个人信息" if panel_mode == "edit" else "管理登录与绑定信息", 18, page.muted_color)
	subtitle.set_meta("account_muted", true)
	close_button = DialogUi.close(heading, dismiss, Styles.palette(page.dark), "关闭" + title)
	scroll_box = ScrollContainer.new()
	scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_box.follow_focus = true
	editor_shell.add_child(scroll_box)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 20)
	scroll_box.add_child(column)
	message = DialogUi.label(editor_shell, "", 16, page.muted_color)
	message.set_meta("account_muted", true)
	message.visible = false
	editor_footer = VBoxContainer.new()
	editor_footer.add_theme_constant_override("separation", 18)
	editor_shell.add_child(editor_footer)
	editor_rules.append(DialogUi.rule(editor_footer, page.border))
	size_changed.connect(_editor_layout)
	get_tree().root.size_changed.connect(_schedule_fit)
	page.resized.connect(_schedule_fit)
	get_node("/root/AppState").font_scale_changed.connect(_schedule_fit.unbind(1))

func _build_edit() -> void:
	_add_edit_field(column, "display_name")
	editor_grid = GridContainer.new()
	editor_grid.columns = 2
	editor_grid.add_theme_constant_override("h_separation", 20)
	editor_grid.add_theme_constant_override("v_separation", 20)
	column.add_child(editor_grid)
	for field in ["school", "college", "major", "grade"]:
		_add_edit_field(editor_grid, field)
	_add_edit_field(column, "bio")
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	editor_footer.add_child(actions)
	cancel_button = DialogUi.button(actions, "取消", dismiss, Styles.palette(page.dark), false, true)
	confirm = DialogUi.button(actions, "保存修改", _save, Styles.palette(page.dark), true)
	confirm.custom_minimum_size.x = 132
	_update_edit_state()

func _add_edit_field(parent: Node, field: String) -> void:
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 8)
	parent.add_child(holder)
	DialogUi.label(holder, FIELD_LABELS[field], 18, page.text_color)
	var edit: Control = TextEdit.new() if field == "bio" else LineEdit.new()
	edit.name = field
	edit.text = str(store.profile.get(field, ""))
	edit.editable = store.editable_fields.has(field)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.accessibility_name = FIELD_LABELS[field]
	holder.add_child(edit)
	_field_style(edit)
	edit.add_theme_font_size_override("font_size", 18)
	if edit is TextEdit:
		edit.custom_minimum_size.y = 112
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text_changed.connect(_draft_changed)
	else:
		edit.max_length = int(store.editable_fields.get(field, {}).get("max_length", 0))
		edit.text_changed.connect(_draft_changed.unbind(1))
	displayed_fields[field] = edit
	if edit.editable:
		original_fields[field] = edit.text
		fields[field] = edit
	else:
		edit.accessibility_description = "此字段由账号服务管理，不可编辑"

func _draft_patch() -> Dictionary:
	var patch: Dictionary = {}
	for field in fields:
		if fields[field].text != str(original_fields.get(field, "")):
			patch[field] = fields[field].text
	return patch

func _draft_changed() -> void:
	if syncing_fields or closing or busy: return
	request_id = ""
	message.text = ""
	message.visible = false
	_update_edit_state()

func _update_edit_state() -> void:
	if panel_mode != "edit" or not is_instance_valid(confirm): return
	var pending: bool = not store.profile_pending.is_empty()
	var locked: bool = busy or store.saving or pending
	for field in fields.values(): field.editable = not locked
	var issue := ""
	for field in fields:
		var limit: int = store.editable_fields.get(field, {}).get("max_length", 0)
		if limit > 0 and fields[field].text.length() > limit:
			issue = FIELD_LABELS[field] + "超出允许长度"
	confirm.text = "保存中…" if busy or store.saving else "核实保存结果" if pending else "保存修改"
	confirm.disabled = busy or store.saving or (not pending and (_draft_patch().is_empty() or not issue.is_empty()))
	confirm.accessibility_description = issue if not issue.is_empty() else "当前没有修改" if _draft_patch().is_empty() and not pending else ""
	if not issue.is_empty(): message.text = issue
	elif pending and not busy and not store.saving: message.text = "上次保存结果待确认，请先核实。"
	message.visible = not message.text.is_empty()
	page.sync_button_state(confirm)

func _editor_layout() -> void:
	if not is_instance_valid(editor_grid): return
	var columns := 2 if get_visible_rect().size.x >= 560 else 1
	if editor_grid.columns != columns:
		editor_grid.columns = columns

func _schedule_fit() -> void:
	if panel_mode not in ["edit", "account"] or closing or not visible or fit_queued: return
	fit_queued = true
	_refit.call_deferred()

func _refit() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	fit_queued = false
	if closing or not visible: return
	DialogUi.fit(self, Vector2(680, _editor_height()), page)
	_editor_layout()

func _editor_height() -> float:
	return clampf(editor_shell.get_combined_minimum_size().y + column.get_combined_minimum_size().y + 60, 560, 920)

func _save() -> void:
	if closing or busy or store.saving: return
	_update_edit_state()
	if confirm.disabled: return
	var patch := _draft_patch()
	if not store.profile_pending.is_empty():
		patch = store.profile_pending.patch.duplicate(true)
		request_id = str(store.profile_pending.request_id)
	if patch.is_empty(): return
	if request_id.is_empty(): request_id = Crypto.new().generate_random_bytes(24).hex_encode()
	_set_busy(true)
	message.text = "正在保存…"
	message.visible = true
	store.save_profile(patch, "", ticket, request_id)

func _saved(id: String, response: Dictionary) -> void:
	if closing or id != ticket or session_epoch != store.epoch:
		return
	_set_busy(false)
	message.text = str(response.get("message", ""))
	message.visible = not message.text.is_empty()
	if scroll_box.is_ancestor_of(message): scroll_box.ensure_control_visible.call_deferred(message)
	if response.get("ok", false):
		page.feedback.text = message.text
		dismiss()

func _set_busy(value: bool) -> void:
	busy = value
	if panel_mode == "edit":
		_update_edit_state()
		return
	if panel_mode == "account":
		refresh_button.text = "读取中…" if value else "刷新信息"
		for button in account_actions:
			button.disabled = value
			page.sync_button_state(button)
		return
	if is_instance_valid(confirm):
		confirm.disabled = value
		confirm.text = "处理中…" if value else "重试"
		page.sync_button_state(confirm)

func _build_account() -> void:
	DialogUi.label(column, "账号信息", 20, page.text_color, true)
	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 16)
	column.add_child(identity)
	_account_row(identity, "username", "登录账号")
	_account_row(identity, "public_id", "用户 ID")
	_account_row(identity, "login_method", "登录方式")
	editor_rules.append(DialogUi.rule(column, page.border))
	DialogUi.label(column, "绑定信息", 20, page.text_color, true)
	var contacts := VBoxContainer.new()
	contacts.add_theme_constant_override("separation", 16)
	column.add_child(contacts)
	_account_row(contacts, "masked_email", "邮箱")
	_account_row(contacts, "masked_phone", "手机")
	editor_rules.append(DialogUi.rule(column, page.border))
	var security := HBoxContainer.new()
	security.add_theme_constant_override("separation", 16)
	column.add_child(security)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_constant_override("separation", 8)
	security.add_child(description)
	DialogUi.label(description, "登录密码", 20, page.text_color, true)
	var can_manage: bool = store.authenticated() and is_instance_valid(store.provider) and store.provider.has_method("open_account_settings")
	var can_change_password: bool = can_manage and store.provider.has_method("change_password")
	var hint := DialogUi.label(description, "修改后需要重新登录" if can_change_password else "通过账号服务管理登录安全" if can_manage else "暂未提供密码管理", 16, page.muted_color)
	hint.set_meta("account_muted", true)
	if can_manage:
		var manage := DialogUi.button(security, "修改密码" if can_change_password else "管理账号", _run_action.bind("open_account_settings"), Styles.palette(page.dark), false, true)
		manage_button = manage
		manage.name = "ManageAccount"
		manage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		account_actions.append(manage)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	editor_footer.add_child(actions)
	refresh_button = DialogUi.button(actions, "刷新信息", _run_action.bind("request_account"), Styles.palette(page.dark), false, true)
	account_actions.append(refresh_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	confirm = DialogUi.button(actions, "完成", dismiss, Styles.palette(page.dark), true)
	if not store.authenticated():
		for value in account_values.values(): value.text = "未登录"
		message.text = "登录后可查看账号与绑定信息。"
		message.visible = true
		refresh_button.hide()
	else:
		_run_action("request_account")

func _account_row(parent: Node, field: String, caption: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	var label := DialogUi.label(row, caption, 18, page.muted_color)
	label.set_meta("account_muted", true)
	label.custom_minimum_size.x = 90
	label.size_flags_horizontal = Control.SIZE_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var value := DialogUi.label(row, "读取中…", 18, page.text_color)
	value.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	value.accessibility_name = caption
	account_values[field] = value

func _show_account(response: Dictionary) -> void:
	account_values.public_id.text = str(store.profile.get("public_id", "")) if store.authenticated() else ""
	for field in ["username", "login_method"]:
		account_values[field].text = str(response.get(field, ""))
	# Contact details are displayed only when the service explicitly masks them.
	for field in ["masked_email", "masked_phone"]:
		var value := str(response.get(field, ""))
		account_values[field].text = value if "*" in value or "•" in value else ""
	for value in account_values.values():
		if value.text.is_empty(): value.text = "暂未提供" if response.get("ok", false) else "暂不可用"
	_schedule_fit()

func _run_action(action: String) -> void:
	if busy:
		return
	_set_busy(true)
	message.text = "正在读取账号信息…" if action == "request_account" else "正在处理…"
	message.visible = true
	_schedule_fit()
	store.run_action(action, ticket + ":" + action)

func _action_finished(id: String, response: Dictionary) -> void:
	if closing or not id.begins_with(ticket + ":") or session_epoch != store.epoch:
		return
	_set_busy(false)
	message.text = str(response.get("message", "操作未完成，请重试。"))
	message.visible = not message.text.is_empty()
	if id.ends_with(":open_account_settings") and is_instance_valid(manage_button) and visible:
		manage_button.grab_focus()
	if id.ends_with(":request_account"):
		_show_account(response)
		if response.get("ok", false):
			message.text = ""
			message.hide()
		_schedule_fit()
		return
	if not response.get("ok", false):
		_schedule_fit()
		return
	if id.ends_with(":begin_login") or id.ends_with(":open_account_settings"):
		message.text = str(response.get("message", "请在已打开的账号流程中继续。"))
		message.visible = not message.text.is_empty()
	_schedule_fit()

func _session_changed() -> void:
	if store.epoch != session_epoch:
		dismiss()
		return
	if panel_mode == "edit" and not closing:
		if not busy and not store.saving and _draft_patch().is_empty():
			syncing_fields = true
			for field in displayed_fields:
				displayed_fields[field].text = str(store.profile.get(field, ""))
				if fields.has(field): original_fields[field] = displayed_fields[field].text
			syncing_fields = false
		_update_edit_state()

func present() -> void:
	if panel_mode in ["edit", "account"]:
		DialogUi.fit(self, Vector2(680, 720), page, true)
		_editor_layout()
		_schedule_fit()
	else:
		popup_centered_clamped(Vector2i(640, 330), 0.88)
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
