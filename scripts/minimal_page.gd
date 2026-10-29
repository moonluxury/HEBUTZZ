extends Control
const Styles = preload("res://scripts/ui_styles.gd")
## Shared UI for the supplied 简约风 screens (1600 px design grid).
const Tokens = preload("res://scripts/ui_tokens.gd")
const MotionProgressBar = preload("res://scripts/ui_progress_bar.gd")
const BLUE := Tokens.PRIMARY
const IdentityEntry = preload("res://scripts/profile_identity.gd")
const WalletBadge = preload("res://scripts/wallet_badge.gd")
const NAV_SIZE := 22
const BODY_SIZE := 22
const BUTTON_SIZE := 22
const TITLE_SIZE := 36
const SECTION_SIZE := 28
const ICON_SIZE := 28
var canvas: Control
var sidebar: Panel
var scroll: ScrollContainer
var body: Control
var bold_font: SystemFont
var dark := false
var text_color := Color("#171B24")
var muted_color := Color("#657080")
var surface := Color.WHITE
var border := Color("#E5E8EE")
var active_nav := "HomeButton"
var content_height := 900.0
var detail_overlay: Control
var modal_focus: Array[Control] = []
var appearance_dirty := false
var wallet_badge: HBoxContainer

func _ready() -> void:
	var resources := get_node("/root/UiResources")
	bold_font = resources.bold
	theme = resources.page_theme
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_meta("route_key", get_node("/root/PageRouter").key_for(scene_file_path, _app().quiz_mode))
	_app().color_mode_changed.connect(_rebuild)
	_app().font_scale_changed.connect(_layout.unbind(1))
	resized.connect(_layout)
	_rebuild()
	_motion().enter(body)

func _motion() -> Node:
	return get_node("/root/UiMotion")

func _app() -> Node:
	return get_node("/root/AppState")

func _stats() -> Node:
	return get_node("/root/StudyStats")

func _texture(path: String) -> Texture2D:
	return get_node("/root/UiResources").texture(path)

func _accent() -> Color:
	return Tokens.DARK_ACCENT if dark else BLUE

func _rebuild(_unused: Variant = null) -> void:
	if not is_inside_tree():
		appearance_dirty = true
		return
	appearance_dirty = false
	var saved_scroll := scroll.scroll_vertical if is_instance_valid(scroll) else 0
	var focused := get_viewport().gui_get_focus_owner()
	var focus_path := canvas.get_path_to(focused) if is_instance_valid(canvas) and focused != null and canvas.is_ancestor_of(focused) else NodePath()
	if is_instance_valid(canvas):
		if is_instance_valid(sidebar) and sidebar.get_parent() == canvas:
			sidebar.reparent(get_node("/root/PageRouter"), false)
		remove_child(canvas)
		canvas.queue_free()
	detail_overlay = null
	dark = _app().dark_mode
	var colors := Styles.palette(dark)
	text_color = colors.text
	muted_color = colors.muted
	surface = colors.surface
	border = colors.border
	canvas = Control.new()
	canvas.name = "Canvas"
	add_child(canvas)
	var bg := _display_panel(canvas, "Background", surface)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_sidebar()
	scroll = ScrollContainer.new()
	scroll.name = "ContentScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	canvas.add_child(scroll)
	body = Control.new()
	body.name = "Content"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_build_content()
	wallet_badge = WalletBadge.new()
	wallet_badge.name = "WalletBadge"
	canvas.add_child(wallet_badge)
	wallet_badge.configure(self)
	wallet_badge.minimum_size_changed.connect(_layout_wallet_badge)
	_layout()
	scroll.set_deferred("scroll_vertical", saved_scroll)
	if not focus_path.is_empty() and canvas.has_node(focus_path):
		canvas.get_node(focus_path).grab_focus()

func _build_sidebar() -> void:
	var router := get_node("/root/PageRouter")
	if is_instance_valid(router.sidebar):
		sidebar = router.sidebar
		if sidebar.get_parent() != canvas:
			sidebar.reparent(canvas, false)
		_refresh_sidebar()
		return
	sidebar = _display_panel(canvas, "Sidebar", Color("#101724") if dark else Color("#F6F7F9"))
	router.sidebar = sidebar
	var identity := IdentityEntry.new()
	identity.name = "IdentityButton"
	sidebar.add_child(identity)
	_rect(identity, Rect2(24, 36, 224, 72))
	var items := [
		["HomeButton", "工作台", "house", router.go.bind("res://scenes/Workbench.tscn")],
		["AllButton", "总题库", "book-text", router.open_subjects.bind("all")],
		["WrongButton", "错题库", "clipboard-x", router.open_subjects.bind("wrong")],
		["KaiwuButton", "河工开物", "book-open", router.go.bind("res://scenes/HegongKaiwu.tscn")],
		["CollectionButton", "我的收藏", "user-round", router.go.bind("res://scenes/MyCollection.tscn")],
		["FriendsButton", "我的好友", "user-round", router.open_friends],
		["RechargeButton", "我要充值", "user-round", router.go.bind("res://scenes/Recharge.tscn")],
	]
	for index in items.size():
		var item: Array = items[index]
		var selected: bool = item[0] == active_nav
		var button := _button(sidebar, item[0], "", item[3])
		button.accessibility_name = item[1]
		_rect(button, Rect2(24, 144 + index * 72, 224, 58))
		if selected:
			button.add_theme_stylebox_override("normal", _style(Tokens.DARK_SOFT if dark else Tokens.SOFT, 8))
		var nav_icon := _icon(button, item[2], Rect2(20, 15, ICON_SIZE, ICON_SIZE), BLUE if selected else muted_color)
		if item[0] == "CollectionButton":
			nav_icon.texture = _texture("res://assets/profile/cards.svg")
		if item[0] == "FriendsButton":
			nav_icon.texture = _texture("res://assets/profile/friends.svg")
		if item[0] == "RechargeButton":
			nav_icon.texture = _texture("res://assets/recharge/battery-two.svg")
		if selected and item[0] == "HomeButton":
			nav_icon.texture = load("res://assets/workbench/art/original/nav_home.png")
		_label(button, item[1], NAV_SIZE, BLUE if selected else muted_color, Rect2(78, 9, 138, 40), selected)
	_line(sidebar, Rect2(263, 0, 1, 2000))
	_refresh_sidebar()

func _refresh_sidebar() -> void:
	sidebar.show()
	sidebar.add_theme_stylebox_override("panel", _style(Color("#101724") if dark else Color("#F6F7F9"), 0))
	sidebar.get_node("IdentityButton").configure(self, active_nav == "IdentityButton")
	for name in ["HomeButton", "AllButton", "WrongButton", "KaiwuButton", "CollectionButton", "FriendsButton", "RechargeButton"]:
		var button: Button = sidebar.get_node(name)
		var selected: bool = name == active_nav
		_style_button(button)
		button.add_theme_stylebox_override("normal", _style((Tokens.DARK_SOFT if dark else Tokens.SOFT) if selected else Color.TRANSPARENT, 8))
		button.get_child(0).self_modulate = _accent() if selected else muted_color
		if name == "HomeButton":
			button.get_child(0).texture = _texture("res://assets/workbench/art/original/nav_home.png" if selected else "res://assets/minimal/icons/house.png")
		button.get_child(1).add_theme_color_override("font_color", _accent() if selected else muted_color)
		button.get_child(1).add_theme_font_override("font", bold_font if selected else theme.default_font)
		button.set_meta("motion_snap", true)
		_motion().bind_button(button)
	sidebar.get_child(-1).color = border

func page_activated() -> void:
	if appearance_dirty or dark != _app().dark_mode:
		_rebuild()
	else:
		_build_sidebar()
		_refresh_cached_content()
		_layout()
	for reveal in find_children("DataReveal", "Node", true, false):
		reveal.restart()
	_motion().enter(body)

func _refresh_cached_content() -> void:
	pass

func _build_content() -> void:
	pass

func _layout_content(_width: float) -> void:
	pass

func _layout() -> void:
	if not is_inside_tree() or size.x < 1 or size.y < 1 or not is_instance_valid(body):
		return
	var base_width := 1200.0 if size.x / maxf(1, size.y) < 1.5 else 1600.0
	var factor := minf(size.x / base_width * clampf(_app().font_scale, 0.7, 1.8), size.x / 1100.0)
	canvas.scale = Vector2.ONE * factor
	canvas.size = size / factor
	_rect(sidebar, Rect2(0, 0, 264, canvas.size.y))
	_rect(scroll, Rect2(322, 48, canvas.size.x - 358, canvas.size.y - 64))
	_layout_content(scroll.size.x - 12)
	body.custom_minimum_size = Vector2(0, content_height)
	_layout_wallet_badge()
	if is_instance_valid(detail_overlay) and has_method("_layout_details"):
		call("_layout_details")

func _layout_wallet_badge() -> void:
	if not is_inside_tree() or not is_instance_valid(wallet_badge): return
	var extent := wallet_badge.get_combined_minimum_size()
	_rect(wallet_badge, Rect2(canvas.size.x - 48 - extent.x, 8, extent.x, maxf(30, extent.y)))

func _label(parent: Node, caption: String, font_size: int, color: Color, rect: Rect2 = Rect2(), bold: bool = false) -> Label:
	var label := Label.new()
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	if bold:
		label.add_theme_font_override("font", bold_font)
	label.add_theme_color_override("font_color", _accent() if color == BLUE else color)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	_rect(label, rect)
	return label

func _button(parent: Node, node_name: String, caption: String, action: Callable, color: Color = Color.TRANSPARENT) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.clip_text = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(button, color)
	if action.is_valid():
		button.pressed.connect(action)
	parent.add_child(button)
	return button

func _style_button(button: Button, color: Color = Color.TRANSPARENT, primary: bool = false) -> void:
	Styles.button(button, color, primary, dark, BUTTON_SIZE)
	_motion().bind_button.call_deferred(button, primary)

func _primary(parent: Node, caption: String, action: Callable, rect: Rect2) -> Button:
	var b := _button(parent, "PrimaryAction", caption, action)
	_style_button(b, BLUE, true)
	_rect(b, rect)
	return b

func _style_choice(button: Button) -> void:
	_style_button(button, surface)
	Styles.choice(button, dark)
	if button is OptionButton:
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_icon_override("arrow", _motion().choice_icon("arrow", muted_color))
		button.add_theme_constant_override("arrow_margin", 16)
		button.add_theme_constant_override("modulate_arrow", 0)

func _display_panel(parent: Node, node_name: String, color: Color = Color.TRANSPARENT) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(color, 0))
	parent.add_child(panel)
	return panel

func _style(color: Color, radius: int, outline: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	return Styles.box(color, radius, outline)

func _icon(parent: Node, icon_name: String, rect: Rect2, color: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _texture("res://assets/minimal/icons/%s.png" % icon_name)
	icon.self_modulate = _accent() if color == BLUE else color
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	_rect(icon, rect)
	return icon

func _line(parent: Node, rect: Rect2) -> ColorRect:
	var line := ColorRect.new()
	line.color = border
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	_rect(line, rect)
	return line

func _bar(parent: Node, ratio: float, rect: Rect2) -> ProgressBar:
	var bar := MotionProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.step = 0.0
	bar.value = clampf(ratio, 0, 100)
	bar.add_theme_stylebox_override("background", _style(border, 3))
	bar.add_theme_stylebox_override("fill", _style(_accent(), 3))
	parent.add_child(bar)
	_rect(bar, rect)
	return bar

func _search(parent: Node, placeholder: String, changed: Callable, rect: Rect2) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.add_theme_font_size_override("font_size", BODY_SIZE)
	edit.add_theme_color_override("font_color", text_color)
	edit.add_theme_color_override("font_placeholder_color", muted_color)
	var style := _style(surface, 8, border)
	style.content_margin_left = 76
	style.content_margin_right = 20
	edit.add_theme_stylebox_override("normal", style)
	Styles.apply_focus(edit, edit.get_theme_stylebox("normal") as StyleBoxFlat)
	edit.accessibility_name = placeholder
	edit.text_changed.connect(changed)
	parent.add_child(edit)
	_rect(edit, rect)
	_icon(edit, "search", Rect2(22, 14, 32, 32), muted_color)
	_motion().bind_input.call_deferred(edit)
	return edit

func _tab(button: Button, selected: bool, underline_width := 0.0, underline_y := 0.0, animate_selection := false) -> void:
	button.add_theme_color_override("font_color", _accent() if selected else muted_color)
	var line := button.get_node_or_null("SelectionLine") as ColorRect
	if underline_width > 0:
		# Refresh the feedback base so it also picks up the newly selected text color.
		button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, 8))
		if line == null:
			line = _line(button, Rect2(0, underline_y, underline_width, 3))
			line.name = "SelectionLine"
		# Only the line scales. Its center, text and button hit area stay fixed.
		_motion().cancel(line)
		_rect(line, Rect2(0, underline_y, underline_width, 3))
		line.pivot_offset = Vector2(underline_width * 0.5, 1.5)
		line.color = _accent()
		line.visible = selected
		line.scale.x = 0.0 if selected and animate_selection else 1.0
		if selected and animate_selection:
			_motion().animate(line, line, ^"scale:x", 1.0, Tokens.TAB_UNDERLINE)
	else:
		button.add_theme_stylebox_override("normal", _style((Tokens.DARK_SOFT if dark else Tokens.SOFT) if selected else Color.TRANSPARENT, 8))
	_motion().bind_button.call_deferred(button)

func _rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

func _number(value: int) -> String:
	var raw := str(value)
	var result := ""
	for index in raw.length():
		if index > 0 and (raw.length() - index) % 3 == 0:
			result += ","
		result += raw[index]
	return result

func _percent(value: float) -> String:
	return "%.1f" % value if value > 0 and value < 1 else str(roundi(value))

func _go(path: String) -> void:
	get_node("/root/PageRouter").go(path)

func _open_subjects(mode: String) -> void:
	_app().quiz_mode = mode
	_app().start_index = 0
	_go("res://scenes/SubjectSelect.tscn")

func _toggle_theme() -> void:
	_app().dark_mode = not _app().dark_mode
	_app().color_mode_changed.emit(_app().dark_mode)
