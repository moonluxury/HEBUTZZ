extends Button
## Local radio-style option. Artwork stays untouched; all decoration is a sibling overlay.
const Avatar = preload("res://scripts/profile_avatar.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
const Styles = preload("res://scripts/ui_styles.gd")
var picture: TextureRect
var decoration: Control
var accent := Tokens.PRIMARY
var surface := Color.WHITE
var selected := false
var hover_alpha := 0.0:
	set(value):
		hover_alpha = value
		if is_instance_valid(decoration): decoration.queue_redraw()

class SelectionOverlay extends Control:
	var choice: Button
	func _draw() -> void:
		var center := size * 0.5
		var color: Color = choice.accent
		if choice.selected:
			draw_arc(center, 73, 0, TAU, 128, color, 2, true)
			var badge := center + Vector2(52, 52)
			draw_circle(badge, 13, choice.surface, true, -1, true)
			draw_circle(badge, 10.5, color, true, -1, true)
			draw_polyline(PackedVector2Array([badge + Vector2(-5, 0), badge + Vector2(-1, 4), badge + Vector2(5, -4)]), Color.WHITE, 2, true)
		elif choice.hover_alpha > 0 or choice.has_focus():
			draw_arc(center, 73, 0, TAU, 128, Color(color, 0.55 if choice.has_focus() else choice.hover_alpha * 0.35), 2, true)
		if choice.has_focus() and Styles.focus_visible(choice):
			for index in 24:
				var angle := TAU * index / 24.0
				draw_arc(center, 78, angle, angle + 0.12, 4, color, 1.5, true)

func _init() -> void:
	custom_minimum_size = Vector2(148, 148)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_mode = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	picture = Avatar.new()
	add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	picture.position = Vector2(-68, -68)
	picture.size = Vector2(136, 136)
	decoration = SelectionOverlay.new()
	decoration.choice = self
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(decoration)
	decoration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(decoration.queue_redraw)
	focus_exited.connect(decoration.queue_redraw)

func _hover(inside: bool) -> void:
	var motion := get_node("/root/UiMotion")
	motion.animate(self, self, ^"hover_alpha", 1.0 if inside and not disabled and motion.hover_enabled else 0.0, Tokens.HOVER)

func configure(is_selected: bool, unavailable: bool, ink: Color, background: Color) -> void:
	selected = is_selected
	accent = ink
	surface = background
	set_pressed_no_signal(selected)
	picture.set_unavailable(unavailable)
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	decoration.queue_redraw()
