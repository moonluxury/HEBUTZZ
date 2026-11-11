extends RefCounted
## Widget appearance policy. Pages provide layout; UiFeedback only animates it.
const Tokens = preload("res://scripts/ui_tokens.gd")
const DialogSurface = preload("res://scripts/dialog_surface.gd")

static func palette(dark: bool) -> Dictionary:
	return {"text": Color("#E8ECF4") if dark else Color("#171B24"),
		"muted": Color("#A2ADBE") if dark else Color("#657080"),
		"surface": Color("#141C2A") if dark else Color.WHITE,
		"border": Color("#2F3A4D") if dark else Color("#E5E8EE"),
		"accent": Tokens.DARK_ACCENT if dark else Tokens.PRIMARY,
		"soft": Tokens.DARK_SOFT if dark else Tokens.SOFT}

static func box(color: Color, radius: int, outline: Color = Color.TRANSPARENT, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	if outline.a > 0:
		style.border_color = outline
		style.set_border_width_all(width)
	return style

static func dialog_panel(window: Window, panel: PanelContainer, color: Color, radius := 8) -> StyleBoxFlat:
	# Rounded modal surfaces must not expose an opaque viewport or outer outline.
	window.borderless = true
	window.transparent_bg = true
	window.transparent = true
	var surface := window.get_node_or_null("DialogSurface")
	if surface == null:
		surface = DialogSurface.new()
		window.add_child(surface)
	surface.configure(panel, color)
	return box(color, radius)

static func install_theme(theme: Theme) -> void:
	var empty := StyleBoxEmpty.new()
	for kind in ["Button", "CheckBox", "CheckButton", "MenuButton", "OptionButton", "LinkButton"]:
		theme.set_stylebox("focus", kind, empty)

static func focus_visible(control: Control) -> bool:
	return not control is BaseButton and not control.get_meta("suppress_focus_feedback", false)

static func apply_focus(control: Control, base: StyleBoxFlat = null) -> void:
	if not focus_visible(control) or base == null:
		control.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		return
	var focus := base.duplicate() as StyleBoxFlat
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Tokens.PRIMARY
	focus.set_border_width_all(2)
	focus.shadow_color = Color.TRANSPARENT
	focus.shadow_size = 0
	control.add_theme_stylebox_override("focus", focus)

static func white_button_text(control: Control, style: StyleBoxFlat, primary := false, semantic := false) -> bool:
	if primary: return true
	if semantic or control.get_meta("state_only_feedback", false) or control.get_meta("foreground_only_feedback", false): return false
	return style != null and style.draw_center and style.bg_color.a >= 0.95 and style.bg_color.srgb_to_linear().get_luminance() <= 0.18

static func button(control: Button, color := Color.TRANSPARENT, primary := false, dark := false, font_size := 22) -> void:
	var colors := palette(dark)
	control.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := box(Tokens.PRIMARY if primary else color, 8)
		style.content_margin_left = 16 if primary else 0
		style.content_margin_right = 16 if primary else 0
		control.add_theme_stylebox_override(state, style)
	apply_focus(control)
	# Enabled colors must not depend on the current disabled flag. Otherwise a
	# deferred feedback binding can accidentally cache disabled gray as normal.
	var foreground: Color = Tokens.ON_PRIMARY if white_button_text(control, control.get_theme_stylebox("normal") as StyleBoxFlat, primary) else colors.text
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		control.add_theme_color_override(state, foreground)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		control.add_theme_color_override(state, Tokens.ON_PRIMARY if primary else colors.text)
	control.add_theme_color_override("font_disabled_color", Color("#657080") if primary else colors.muted)
	control.add_theme_color_override("icon_disabled_color", Color("#657080") if primary else colors.muted)
	control.add_theme_constant_override("icon_max_width", 28)
	control.add_theme_constant_override("h_separation", 12)
	control.expand_icon = true
	control.tooltip_text = ""

static func input(control: Control, colors: Dictionary, radius := 8, padding := 12) -> void:
	var style := box(colors.surface, radius, colors.border)
	style.content_margin_left = padding
	style.content_margin_right = padding
	control.add_theme_stylebox_override("normal", style)
	control.add_theme_stylebox_override("read_only", style)
	control.add_theme_color_override("font_color", colors.text)
	control.add_theme_color_override("font_placeholder_color", colors.muted)
	apply_focus(control, style)

static func choice(control: Button, dark: bool) -> void:
	var colors := palette(dark)
	var style := box(colors.surface, 8, colors.border)
	style.content_margin_left = 16
	style.content_margin_right = 16
	control.add_theme_stylebox_override("normal", style)
	control.custom_minimum_size.y = 50

static func tab(control: Button, selected: bool, dark: bool) -> void:
	var colors := palette(dark)
	control.add_theme_color_override("font_color", colors.accent if selected else colors.muted)
	control.add_theme_stylebox_override("normal", box(colors.soft if selected else Color.TRANSPARENT, 8))
	apply_focus(control)

static func option(background: Color, border: Color) -> StyleBoxFlat:
	var style := box(background, 12, border, 2)
	style.content_margin_left = 24
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func code_palette(dark: bool) -> Dictionary:
	return {"ink": Color("#E8EEF8") if dark else Color("#172235"),
		"surface": Color("#19263A") if dark else Color("#F8FAFE"),
		"border": Color("#455878") if dark else Color("#CBD5E5"),
		"placeholder": Color("#8795AB") if dark else Color("#69788F"),
		"accent": Tokens.DARK_ACCENT if dark else Tokens.PRIMARY}

static func code_editor(field: Control, dark: bool) -> void:
	var colors := code_palette(dark)
	var style := box(colors.surface, 0, colors.border, 2)
	style.set_content_margin_all(18)
	field.add_theme_stylebox_override("normal", style)
	field.add_theme_stylebox_override("read_only", style)
	apply_focus(field, style)
	for name in ["font_color", "font_readonly_color", "caret_color", "line_number_color"]:
		field.add_theme_color_override(name, colors.ink)
	field.add_theme_color_override("font_placeholder_color", colors.placeholder)
	field.add_theme_color_override("selection_color", Color(colors.accent, 0.25))

static func code_button(control: Button, dark: bool) -> void:
	var colors := code_palette(dark)
	var normal := box(Tokens.DARK_SOFT if dark else Tokens.SOFT, 8, colors.border, 2)
	normal.set_content_margin_all(16)
	for state in ["normal", "disabled", "hover", "pressed"]:
		control.add_theme_stylebox_override(state, normal)
	apply_focus(control)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		control.add_theme_color_override(state, colors.ink)
	control.add_theme_color_override("font_disabled_color", Color("#8795AB") if dark else Color("#69788F"))

# Answer-state palette used by every quiz presentation.
const CORRECT_COLOR := Color(0.05, 0.55, 0.22)
const WRONG_COLOR := Color(0.86, 0.15, 0.15)
const HEBUT_BLUE := Tokens.PRIMARY
const OPTION_SELECTED_BG := Tokens.SOFT
const OPTION_CORRECT_BG := Color("#EDF9F1")
const OPTION_WRONG_BG := Color("#FFF1F1")
const OPTION_BORDER := Color("#E3EAF5")
const LIGHT_BACKGROUND := Color("#F6F9FE")
const LIGHT_TEXT := Color("#0F1E37")
const LIGHT_MUTED := Color("#68758A")
const DARK_BACKGROUND := Color("#0B1220")
const DARK_HEADER := Color("#111A2A")
const DARK_CARD := Color("#151F32")
const DARK_OPTION := Color("#19263A")
const DARK_OPTION_HOVER := Color("#20314B")
const DARK_BORDER := Color("#2C3D59")
const DARK_TEXT := Color("#E8EEF8")
const DARK_MUTED := Color("#9EADC3")
const DARK_ACCENT := Tokens.DARK_ACCENT
const DARK_ACCENT_SURFACE := Tokens.DARK_SOFT
const DARK_CORRECT := Color("#63D68A")
const DARK_CORRECT_SURFACE := Color("#173827")
const DARK_WRONG := Color("#FF858C")
const DARK_WRONG_SURFACE := Color("#41242B")

static func answer_input(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := box(background, 10, border, width)
	style.content_margin_left = 12
	style.content_margin_right = 12
	return style

static func text_ink(dark: bool) -> Color:
	return Color("#E8EEF8") if dark else Color.BLACK

static func text_background(dark: bool) -> Color:
	return Color("#0B1220") if dark else Color("#F7F8FC")

static func apply_text_palette(node: Node, dark_mode: bool) -> void:
	var foreground := text_ink(dark_mode)
	var disabled_foreground := (
		Color("#77869E") if dark_mode else Color(0.45, 0.45, 0.45)
	)

	if node is ColorRect and node.name == "Background":
		node.color = text_background(dark_mode)
	elif node is Button:
		_apply_button_colors(node, foreground, disabled_foreground)
	elif node is RichTextLabel:
		node.add_theme_color_override("default_color", foreground)
		node.add_theme_color_override(
			"font_selected_color",
			text_background(dark_mode),
		)
		node.add_theme_color_override(
			"selection_color",
			Color(1.0, 1.0, 1.0, 0.28)
			if dark_mode
			else Color(0.0, 0.0, 0.0, 0.22),
		)
	elif node is Label:
		node.add_theme_color_override("font_color", foreground)
	elif node is ItemList:
		for color_name in [
			"font_color",
			"font_hovered_color",
			"font_hovered_selected_color",
			"font_outline_color",
			"font_selected_color",
			"font_selected_outline_color",
		]:
			node.add_theme_color_override(color_name, foreground)
	elif node is LineEdit:
		node.add_theme_color_override("font_color", foreground)
		node.add_theme_color_override("font_selected_color", text_background(dark_mode))
		node.add_theme_color_override("caret_color", foreground)
		node.add_theme_color_override(
			"selection_color",
			Color(1.0, 1.0, 1.0, 0.28)
			if dark_mode
			else Color(0.0, 0.0, 0.0, 0.22),
		)

	for child in node.get_children(true):
		apply_text_palette(child, dark_mode)

static func _apply_button_colors(
	button: Button,
	foreground: Color,
	disabled_foreground: Color,
) -> void:
	for color_name in [
		"font_color",
		"font_hover_color",
		"font_pressed_color",
		"font_focus_color",
		"font_hover_pressed_color",
	]:
		button.add_theme_color_override(color_name, foreground)
	button.add_theme_color_override("font_disabled_color", disabled_foreground)

static func popup(popup: PopupMenu, source: Button, dark: bool, choice_icon: Callable) -> void:
	# PopupMenu is its own Window; install the page's high-resolution font and
	# complete palette explicitly instead of falling back to the engine theme.
	popup.add_theme_font_override("font", source.get_theme_font("font"))
	popup.add_theme_font_size_override("font_size", source.get_theme_font_size("font_size"))
	popup.add_theme_color_override("font_color", Color("#E8ECF4") if dark else Color("#171B24"))
	popup.add_theme_color_override("font_disabled_color", Color("#A2ADBE") if dark else Color("#657080"))
	var accent := Tokens.DARK_ACCENT if dark else Tokens.PRIMARY
	var muted := Color("#A2ADBE") if dark else Color("#657080")
	popup.add_theme_icon_override("radio_checked", choice_icon.call("checked", accent))
	popup.add_theme_icon_override("radio_unchecked", choice_icon.call("circle", muted))
	popup.add_theme_icon_override("radio_checked_disabled", choice_icon.call("checked", muted))
	popup.add_theme_icon_override("radio_unchecked_disabled", choice_icon.call("circle", muted))
	popup.add_theme_constant_override("h_separation", 12)
	popup.add_theme_constant_override("v_separation", 14)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#141C2A") if dark else Color.WHITE
	panel.border_color = Color("#2F3A4D") if dark else Color("#E5E8EE")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	popup.add_theme_stylebox_override("panel", panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Tokens.DARK_SOFT if dark else Tokens.SOFT
	hover.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("hover", hover)
	popup.add_theme_color_override("font_hover_color", Tokens.DARK_ACCENT if dark else Tokens.PRIMARY)
