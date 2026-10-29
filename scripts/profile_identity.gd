extends Button
## Persistent sidebar control: callbacks never capture a cached/destroyed page.
const Avatar = preload("res://scripts/profile_avatar.gd")
var avatar: TextureRect
var username: Label
var caption: Label
var arrow: TextureRect

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	avatar = Avatar.new()
	avatar.name = "Avatar"
	add_child(avatar)
	avatar.position = Vector2(10, 12)
	avatar.size = Vector2(46, 46)
	username = Label.new()
	username.name = "Username"
	username.position = Vector2(68, 7)
	username.size = Vector2(126, 32)
	username.clip_text = true
	username.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	username.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(username)
	caption = Label.new()
	caption.text = "个人中心"
	caption.position = Vector2(68, 39)
	caption.size = Vector2(126, 27)
	caption.add_theme_font_size_override("font_size", 17)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	arrow = TextureRect.new()
	arrow.texture = load("res://assets/minimal/icons/chevron-right.png")
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.position = Vector2(200, 27)
	arrow.size = Vector2(18, 18)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arrow)
	pressed.connect(get_node("/root/PageRouter").open_identity)
	get_node("/root/ProfileStore").changed.connect(refresh)
	refresh()

func configure(page: Control, selected: bool) -> void:
	page._style_button(self)
	# A collection page may create the shell first; this entry always retains focus.
	remove_meta("suppress_focus_feedback")
	add_theme_stylebox_override("normal", page._style((page.Tokens.DARK_SOFT if page.dark else page.Tokens.SOFT) if selected else Color.TRANSPARENT, 8))
	username.add_theme_font_override("font", page.bold_font)
	username.add_theme_font_size_override("font_size", 22)
	username.add_theme_color_override("font_color", page._accent() if selected else page.text_color)
	caption.add_theme_color_override("font_color", page.muted_color)
	arrow.self_modulate = page._accent() if selected else page.muted_color
	set_meta("motion_snap", true)
	page._motion().bind_button(self)
	refresh()

func refresh() -> void:
	var store := get_node("/root/ProfileStore")
	username.text = store.display_name()
	tooltip_text = username.text if username.text.length() > 7 else ""
	accessibility_name = username.text + "，个人中心" if store.authenticated() else username.text
	avatar.show_profile(store.profile)
