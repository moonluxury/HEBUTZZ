extends "res://scripts/minimal_page.gd"
const Avatar = preload("res://scripts/profile_avatar.gd")
const ProfileDialog = preload("res://scripts/profile_dialog.gd")
const PROFILE_LABELS := {"school": "学校", "college": "学院", "major": "专业", "grade": "年级", "bio": "个人简介"}
var profile_store: Node
var column: VBoxContainer
var columns: BoxContainer
var settings: VBoxContainer
var avatar: TextureRect
var username: Label
var public_id: Label
var status: Label
var feedback: Label
var values: Dictionary = {}
var edit_button: Button
var copy_button: Button
var logout_button: Button
var retry_button: Button
var dialog: Window
var dialog_return: WeakRef

func _ready() -> void:
	profile_store = get_node("/root/ProfileStore")
	active_nav = "IdentityButton"
	super._ready()
	profile_store.changed.connect(_refresh_profile)
	var router := get_node("/root/PageRouter")
	if router.identity_login_requested:
		router.identity_login_requested = false
		show_panel.call_deferred("login", edit_button)

func _rebuild(unused: Variant = null) -> void:
	super._rebuild(unused)
	if is_instance_valid(dialog) and dialog.is_node_ready():
		dialog.refresh_theme()

func _text(parent: Node, caption: String, font_size: int, color: Color, strong := false) -> Label:
	var label := _label(parent, caption, font_size, color, Rect2(), strong)
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.y = font_size + 10
	return label

func _space(parent: Node, height: float) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = height
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(space)

func _rule(parent: Node) -> void:
	var line := _line(parent, Rect2())
	line.custom_minimum_size.y = 1

func _build_content() -> void:
	values.clear()
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	body.add_child(column)
	_text(column, "个人中心", TITLE_SIZE, text_color, true)
	_space(column, 10)
	_text(column, "管理你的资料与账号", BODY_SIZE, muted_color)
	_space(column, 42)
	var header := HBoxContainer.new()
	header.name = "IdentitySummary"
	header.add_theme_constant_override("separation", 26)
	column.add_child(header)
	avatar = Avatar.new()
	avatar.custom_minimum_size = Vector2(94, 94)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.add_child(avatar)
	var identity := VBoxContainer.new()
	identity.add_theme_constant_override("separation", 8)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(identity)
	username = _text(identity, "", 30, text_color, true)
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 10)
	identity.add_child(id_row)
	public_id = _text(id_row, "", 18, muted_color)
	public_id.size_flags_horizontal = Control.SIZE_FILL
	public_id.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	copy_button = _button(id_row, "CopyID", "", _copy_id)
	copy_button.icon = _texture("res://assets/profile/copy.svg")
	copy_button.accessibility_name = "复制完整用户 ID"
	copy_button.custom_minimum_size = Vector2(38, 38)
	copy_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var friends := _button(identity, "Friends", "我的好友 →", Callable())
	friends.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	friends.custom_minimum_size = Vector2(145, 42)
	friends.add_theme_color_override("font_color", _accent())
	friends.pressed.connect(get_node("/root/PageRouter").open_friends)
	edit_button = _button(header, "EditProfile", "编辑资料", _edit)
	_style_button(edit_button, BLUE, true)
	edit_button.custom_minimum_size = Vector2(154, 52)
	edit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_space(column, 30)
	_rule(column)
	_space(column, 34)
	status = _text(column, "", 18, muted_color)
	retry_button = _button(column, "RetryProfile", "重新加载资料", profile_store.refresh)
	retry_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	retry_button.custom_minimum_size = Vector2(180, 40)
	columns = BoxContainer.new()
	columns.name = "ProfileColumns"
	columns.add_theme_constant_override("separation", 60)
	column.add_child(columns)
	var details := VBoxContainer.new()
	details.name = "ProfileDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 26)
	columns.add_child(details)
	_text(details, "个人资料", SECTION_SIZE, text_color, true)
	for field in PROFILE_LABELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		details.add_child(row)
		var label := _text(row, PROFILE_LABELS[field], BODY_SIZE, muted_color)
		label.custom_minimum_size.x = 100
		label.size_flags_horizontal = Control.SIZE_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		values[field] = _text(row, "", BODY_SIZE, text_color)
	settings = VBoxContainer.new()
	settings.name = "AccountSettings"
	settings.add_theme_constant_override("separation", 0)
	columns.add_child(settings)
	_text(settings, "账号与设置", SECTION_SIZE, text_color, true)
	_space(settings, 18)
	var account := _setting("AccountSecurity", "账号与安全", "管理登录与绑定信息", "shield")
	account.pressed.connect(show_panel.bind("account", account))
	_rule(settings)
	var collection := _setting("CollectionShortcut", "我的收藏", "查看卡牌收藏与想要清单", "cards")
	collection.pressed.connect(get_node("/root/PageRouter").go.bind("res://scenes/MyCollection.tscn"))
	_space(settings, 16)
	var version := _button(settings, "Version", "版本信息", Callable())
	version.custom_minimum_size = Vector2(104, 44)
	version.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	version.add_theme_color_override("font_color", muted_color)
	version.pressed.connect(show_panel.bind("version", version))
	_space(column, 54)
	_rule(column)
	_space(column, 22)
	logout_button = _button(column, "Logout", "退出登录", Callable())
	logout_button.icon = _texture("res://assets/profile/log-out.svg")
	logout_button.custom_minimum_size = Vector2(150, 46)
	logout_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	logout_button.pressed.connect(show_panel.bind("logout", logout_button))
	feedback = _text(column, "", 18, muted_color)
	column.minimum_size_changed.connect(_queue_layout)
	_refresh_profile()

func _setting(node_name: String, title: String, description: String, icon_name: String) -> Button:
	var row := _button(settings, node_name, "", Callable())
	row.accessibility_name = title + "，" + description
	row.custom_minimum_size.y = 102
	var icon := _icon(row, "user-round", Rect2(10, 34, 30, 30), muted_color)
	icon.texture = _texture("res://assets/profile/%s.svg" % icon_name)
	var heading := _label(row, title, 23, text_color, Rect2(60, 17, 280, 34))
	var detail := _label(row, description, 18, muted_color, Rect2(60, 55, 300, 28))
	var arrow := _icon(row, "chevron-right", Rect2(), muted_color)
	row.resized.connect(func():
		heading.size.x = row.size.x - 100
		detail.size.x = row.size.x - 100
		_rect(arrow, Rect2(row.size.x - 28, 39, 22, 22))
	)
	return row

func _queue_layout() -> void:
	_layout.call_deferred()

func _layout_content(width: float) -> void:
	var id_width := public_id.get_theme_font("font").get_string_size(public_id.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 2
	public_id.custom_minimum_size.x = minf(id_width, maxf(80, width - 348))
	columns.vertical = width < 940
	columns.add_theme_constant_override("separation", 38 if columns.vertical else 60)
	settings.custom_minimum_size.x = 0 if columns.vertical else 410
	column.position = Vector2.ZERO
	column.size.x = width
	column.size.y = column.get_combined_minimum_size().y
	content_height = column.size.y + 24

func _refresh_profile() -> void:
	if not is_instance_valid(username):
		return
	var data: Dictionary = profile_store.profile
	username.text = profile_store.display_name() if profile_store.authenticated() or profile_store.session_state == "loading" else "尚未登录"
	avatar.show_avatar(str(data.get("avatar", "")))
	var identifier := str(data.get("public_id", ""))
	public_id.text = "用户 ID：" + (identifier if not identifier.is_empty() else "暂不可用" if profile_store.authenticated() else "未登录")
	copy_button.disabled = identifier.is_empty() or not profile_store.authenticated()
	for field in values:
		var value := str(data.get(field, ""))
		values[field].text = value if not value.is_empty() else "暂无简介" if field == "bio" else "未填写"
	status.text = "正在加载资料…" if profile_store.loading or profile_store.session_state == "loading" else profile_store.error if not profile_store.error.is_empty() else "登录后可管理你的资料与账号。" if not profile_store.authenticated() else ""
	status.visible = not status.text.is_empty()
	retry_button.visible = profile_store.authenticated() and not profile_store.error.is_empty() and not profile_store.saving
	edit_button.text = "保存中…" if profile_store.saving else "编辑资料" if profile_store.authenticated() else "登录"
	edit_button.disabled = profile_store.saving or profile_store.loading or profile_store.session_state == "loading"
	logout_button.disabled = not profile_store.authenticated()
	for button in [edit_button, copy_button, logout_button]:
		sync_button_state(button)
	_queue_layout()

func sync_button_state(button: Button) -> void:
	# Update before drawing; changing font overrides inside draw can leave stale ink.
	var state := button.get_node_or_null("UIFeedback")
	if state != null:
		state._check_disabled()
	button.queue_redraw()

func _edit() -> void:
	show_panel("edit" if profile_store.authenticated() else "login", edit_button)

func _copy_id() -> void:
	feedback.text = profile_store.copy_public_id().message

func show_panel(mode: String, trigger: Control = null) -> void:
	if mode == "friends":
		get_node("/root/PageRouter").open_friends()
		return
	if is_instance_valid(dialog):
		return
	dialog_return = weakref(trigger) if trigger != null else null
	dialog = ProfileDialog.new()
	dialog.page = self
	dialog.panel_mode = mode
	dialog.closed.connect(_dialog_closed)
	add_child(dialog)
	dialog.present()

func _dialog_closed() -> void:
	dialog = null
	var trigger: Control = dialog_return.get_ref() if dialog_return != null else null
	if is_instance_valid(trigger) and trigger.is_inside_tree() and trigger.is_visible_in_tree():
		trigger.grab_focus()
	elif is_inside_tree() and is_instance_valid(edit_button) and not edit_button.disabled:
		edit_button.grab_focus()

func _exit_tree() -> void:
	if is_instance_valid(dialog):
		dialog.dismiss()

func consume_back_action() -> bool:
	if not is_instance_valid(dialog):
		return false
	dialog.consume_back_action()
	return true
