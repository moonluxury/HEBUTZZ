extends Button
## A local P3 row. Feedback never changes geometry or the global button theme.
const BLUE := Color("#092C87")
const MUTED := Color("#707988")
static var glyphs: Dictionary = {}
var frame: StyleBoxFlat
var caption: Label
var description: Label

static func glyph(kind: String, color: Color) -> Texture2D:
	var key := kind + color.to_html()
	if glyphs.has(key): return glyphs[key]
	var paths := {
		"profile": '<circle cx="10" cy="6" r="4"/><path d="M16 21H2v-3a6 6 0 0 1 12-1M21 5v16"/>',
		"remark": '<path d="m12 2 3 6.5 7 1-5 5 1.2 7-6.2-3.3L5.8 21l1.2-6.5-5-5 7-1Z"/>',
		"marks": '<path d="M13 2h8a1 1 0 0 1 1 1v8L11 22 1 12Z"/><circle cx="17.5" cy="6.5" r="1"/>',
		"records": '<rect x="3" y="1.5" width="18" height="21" rx="2"/><path d="M7 7h10M7 12h10M7 17h5"/>',
		"block": '<path d="m2 2 20 20M9 3a6 6 0 0 1 9 5c0 3 0 5 3 9M6 7c0 5 0 7-3 11h13M10 21a2 2 0 0 0 4 0M11 1h2"/>',
		"remove": '<path d="M3 5h18M9 5V2h6v3M5 5l1 17h12l1-17M10 9v9M14 9v9"/>',
		"arrow": '<path d="m9 5 7 7-7 7"/>',
		"close": '<path d="m5 5 14 14M19 5 5 19"/>'
	}
	glyphs[key] = DPITexture.create_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 24 24"><g fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [color.to_html(false), paths.get(kind, paths.close)])
	return glyphs[key]

func configure(item: Dictionary, callback: Callable) -> void:
	name = str(item.id)
	custom_minimum_size = Vector2(399, 60)
	set_meta("motion_fixed", true)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame = StyleBoxFlat.new()
	frame.bg_color = Color.WHITE
	frame.border_color = Color("#E4E7EC")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(9)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(state, frame)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = BLUE
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(9)
	add_theme_stylebox_override("focus", focus)
	var ink := Color("#E53943") if item.id == "remove" else Color("#151922")
	_picture(glyph(str(item.id), ink if item.id == "remove" else BLUE), Rect2(23, 18, 24, 24))
	caption = _label(str(item.title), 18, ink, Rect2(76, 7, 286, 25))
	description = _label(str(item.subtitle), 15, MUTED, Rect2(76, 33, 286, 21))
	_picture(glyph("arrow", MUTED), Rect2(365, 22, 16, 16))
	accessibility_name = str(item.title) + "，" + str(item.subtitle)
	pressed.connect(callback)
	mouse_entered.connect(_feedback.bind(0.14))
	mouse_exited.connect(_feedback.bind(0.14))
	button_down.connect(_feedback.bind(0.08))
	button_up.connect(_feedback.bind(0.08))

func _label(value: String, font_size: int, color: Color, rect: Rect2, strong := false) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if strong: label.add_theme_font_override("font", get_node("/root/UiResources").bold)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _picture(texture: Texture2D, rect: Rect2) -> void:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.position = rect.position
	picture.size = rect.size
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(picture)

func _feedback(duration: float) -> void:
	var motion := get_node("/root/UiMotion")
	var over: bool = is_hovered() and motion.hover_enabled and not disabled
	motion.animate(self, frame, ^"bg_color", Color("#DFE5F0") if is_pressed() else Color("#EBEEF5") if over else Color.WHITE, duration)
	motion.animate(self, frame, ^"border_color", Color("#CBD3E2") if over else Color("#E4E7EC"), duration)
