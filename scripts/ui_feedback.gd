extends Node
## One live StyleBox per control; native hover cannot override semantic/disabled state.
const T = preload("res://scripts/ui_tokens.gd")
var control: Control
var motion: Node
var live: StyleBoxFlat
var base: StyleBoxFlat
var disabled_style: StyleBoxFlat
var primary := false
var semantic := false
var foreground_only := false
var state_only := false
var hovered := false
var pressing := false
var last_disabled := false
var is_input := false
var is_panel := false
var hover_duration := T.HOVER
var ink := Color.WHITE
var icon_ink := Color.WHITE
var disabled_ink := Color("#657080")
var foreground_color := Color.WHITE:
	set(value):
		foreground_color = value
		if is_instance_valid(control) and control is Button:
			_apply_foreground(value, value)

func _ready() -> void:
	control = get_parent()
	motion = get_node("/root/UiMotion")
	control.mouse_entered.connect(func(): hovered = true; update_state(hover_duration))
	control.mouse_exited.connect(func(): hovered = false; update_state(hover_duration))
	control.focus_entered.connect(func(): update_state(T.STATE))
	control.focus_exited.connect(func(): pressing = false; update_state(T.STATE))
	control.visibility_changed.connect(func():
		if not control.is_visible_in_tree():
			hovered = false
			pressing = false
			update_state(0.0)
	)
	motion.pointer_changed.connect(func(): update_state(T.STATE))
	motion.preference_changed.connect(func(): pressing = false; update_state(0.0))
	if control is BaseButton:
		control.button_down.connect(func(): pressing = true; update_state(T.PRESS))
		control.button_up.connect(func(): pressing = false; update_state(T.STATE))
		control.draw.connect(_check_disabled)

func configure(is_primary: bool, keep_semantics: bool) -> void:
	primary = is_primary
	semantic = keep_semantics
	state_only = control.get_meta("state_only_feedback", false)
	foreground_only = state_only or control.get_meta("foreground_only_feedback", false)
	var source := control.get_theme_stylebox("normal") as StyleBoxFlat
	if source == null:
		return
	if source == live:
		update_state(T.STATE)
		return
	base = source.duplicate()
	disabled_style = control.get_theme_stylebox("disabled").duplicate() if semantic else base.duplicate()
	ink = control.get_theme_color("font_color")
	icon_ink = control.get_theme_color("icon_normal_color")
	disabled_ink = control.get_theme_color("font_disabled_color") if semantic else Color("#A2ADBE") if base.bg_color.get_luminance() < 0.15 and not primary else Color("#657080")
	if not semantic:
		disabled_style.bg_color = Color("#2F3A4D") if base.bg_color.get_luminance() < 0.15 and not primary else Color("#E5E8EE") if primary else base.bg_color
	var old := live
	live = base.duplicate()
	if old != null and not control.get_meta("motion_snap", false):
		live.bg_color = old.bg_color
		live.border_color = old.border_color
	motion.cancel(self)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		control.add_theme_stylebox_override(state, live)
	_install_focus()
	var snap: bool = control.get_meta("motion_snap", false) or old == null
	control.remove_meta("motion_snap")
	last_disabled = control.disabled
	update_state(0.0 if snap else T.STATE)

func configure_input() -> void:
	is_input = true
	base = control.get_theme_stylebox("normal").duplicate()
	motion.cancel(self)
	live = base.duplicate()
	control.add_theme_stylebox_override("normal", live)
	control.add_theme_stylebox_override("read_only", live)
	_install_focus()
	update_state(0.0)

func configure_panel(duration: float) -> void:
	is_panel = true
	hover_duration = duration
	base = control.get_theme_stylebox("panel").duplicate()
	live = base.duplicate()
	control.add_theme_stylebox_override("panel", live)
	# A hoverable surface is not a button; retain arrow cursor and no focus/action.
	control.mouse_filter = Control.MOUSE_FILTER_PASS

func _install_focus() -> void:
	if foreground_only or control.get_meta("suppress_focus_feedback", false):
		control.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		return
	var focus := base.duplicate()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = T.PRIMARY
	focus.set_border_width_all(2)
	# A shadow behind a transparent focus box also tints the control's interior.
	# Keep the light button fill and mark keyboard focus with the border alone.
	focus.shadow_color = Color.TRANSPARENT
	focus.shadow_size = 0
	control.add_theme_stylebox_override("focus", focus)

func _check_disabled() -> void:
	if control.disabled != last_disabled:
		last_disabled = control.disabled
		pressing = false
		update_state(0.0)

func update_state(duration: float) -> void:
	if base == null or live == null:
		return
	var disabled: bool = control is BaseButton and control.disabled
	var bg := disabled_style.bg_color if disabled else base.bg_color
	var border := disabled_style.border_color if disabled else base.border_color
	var over: bool = hovered and motion.hover_enabled and not motion.suspended and control.is_visible_in_tree()
	if not disabled and not foreground_only:
		if is_input and control.has_focus() and not control.get_meta("suppress_focus_feedback", false):
			border = T.PRIMARY
		elif pressing and not is_input and not is_panel:
			bg = T.PRESSED_COLOR if primary else _shade(bg, 0.07)
		elif over:
			bg = T.HOVER_COLOR if primary else base.bg_color if is_input else _shade(bg, 0.04)
			if border.a > 0 and not primary:
				border = border.lerp(T.PRIMARY, 0.18)
	motion.animate(self, live, ^"bg_color", bg, duration)
	motion.animate(self, live, ^"border_color", border, duration)
	if control is Button:
		control.mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
		var foreground := disabled_ink if disabled else ink
		var icon_color := control.get_theme_color("icon_disabled_color") if disabled and semantic else disabled_ink if disabled else icon_ink
		if foreground_only:
			if not disabled and not state_only and (over or (control.has_focus() and not control.get_meta("suppress_focus_feedback", false)) or pressing):
				foreground = T.DARK_ACCENT if get_node("/root/AppState").dark_mode else T.PRIMARY
			motion.animate(self, self, ^"foreground_color", foreground, duration)
		else:
			_apply_foreground(foreground, icon_color)

func _apply_foreground(foreground: Color, icon_color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		control.add_theme_color_override(state, foreground)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color", "icon_disabled_color"]:
		control.add_theme_color_override(state, icon_color)

func _shade(color: Color, amount: float) -> Color:
	if color.a < 0.01:
		return Color(T.PRIMARY, amount)
	return color.lightened(amount) if color.get_luminance() < 0.15 else color.darkened(amount)
