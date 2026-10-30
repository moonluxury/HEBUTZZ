extends RefCounted
## Local UI primitives shared only by the profile editor and account form.
const Styles = preload("res://scripts/ui_styles.gd")

static func glyph(kind: String, color: Color) -> Texture2D:
	var shape := '<path d="m6 6 12 12M18 6 6 18"/>'
	if kind == "eye":
		shape = '<path d="M2 12s3.5-6.5 10-6.5S22 12 22 12s-3.5 6.5-10 6.5S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>'
	elif kind == "eye_hidden":
		shape = '<path d="m3 3 18 18M8.5 5.9A12.7 12.7 0 0 1 12 5.5c6.5 0 10 6.5 10 6.5a20 20 0 0 1-3 3.8M15.5 18.1a12.7 12.7 0 0 1-3.5.4C5.5 18.5 2 12 2 12a20 20 0 0 1 3-3.8"/>'
	return DPITexture.create_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [color.to_html(false), shape])

static func label(parent: Node, text: String, size: int, color: Color, strong := false) -> Label:
	var control := Label.new()
	control.text = text
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
	if strong: control.add_theme_font_override("font", parent.get_node("/root/UiResources").bold)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(control)
	return control

static func button(parent: Node, text: String, action: Callable, colors: Dictionary, primary := false, outlined := false) -> Button:
	var control := Button.new()
	control.text = text
	control.custom_minimum_size = Vector2(92, 48)
	parent.add_child(control)
	style_button(control, colors, primary, outlined)
	control.pressed.connect(action)
	return control

static func style_button(control: Button, colors: Dictionary, primary := false, outlined := false, link := false) -> void:
	var dark: bool = control.get_node("/root/AppState").dark_mode
	Styles.button(control, colors.surface if outlined else Color.TRANSPARENT, primary, dark, 18)
	if outlined:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := Styles.box(colors.surface, 7, colors.border)
			box.set_content_margin_all(12)
			control.add_theme_stylebox_override(state, box)
	if link:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			control.add_theme_color_override(state, colors.accent)
	control.get_node("/root/UiMotion").bind_button(control, primary)

static func close(parent: Node, action: Callable, colors: Dictionary, description: String) -> Button:
	var control := button(parent, "", action, colors)
	control.custom_minimum_size = Vector2(44, 44)
	control.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	control.icon = glyph("close", colors.text)
	control.add_theme_constant_override("icon_max_width", 22)
	control.accessibility_name = description
	return control

static func margin(parent: Node, inset := 30) -> MarginContainer:
	var control := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		control.add_theme_constant_override("margin_" + side, inset)
	parent.add_child(control)
	return control

static func rule(parent: Node, color: Color) -> ColorRect:
	var control := ColorRect.new()
	control.color = color
	control.custom_minimum_size.y = 1
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	return control

static func fit(window: Window, desired: Vector2, source: Control, opening := false) -> void:
	var owner := window.get_tree().root
	var bounds := owner.get_visible_rect()
	var ui_scale := 1.0
	if is_instance_valid(source) and source.get("canvas") is Control:
		ui_scale = source.canvas.get_global_transform_with_canvas().get_scale().x
	if not window.is_embedded():
		bounds = Rect2(Vector2(owner.position), Vector2(owner.size))
		ui_scale *= owner.get_stretch_transform().get_scale().x
	ui_scale = maxf(0.85, minf(ui_scale, bounds.size.y / (desired.y + 48.0)))
	window.content_scale_factor = ui_scale
	var safe := bounds.grow(-24.0 * ui_scale)
	var target := Vector2i((desired * ui_scale).min(safe.size))
	window.min_size = Vector2i(Vector2(340, 300) * ui_scale).min(target)
	var origin := Vector2i(bounds.position + (bounds.size - Vector2(target)) * 0.5)
	if opening: window.popup(Rect2i(origin, target))
	window.size = target
	window.position = origin
