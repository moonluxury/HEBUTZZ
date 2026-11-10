extends Node
## Presentation-only press feedback; never delays or invokes the button's action.
var button: BaseButton
var visual: Control
var motion: Node
var rest_scale := Vector2.ONE
var rest_tint := Color.WHITE
var frozen := false

static func bind(source: BaseButton, target: Control = null) -> Node:
	var existing := source.get_node_or_null("CardPressFeedback")
	if existing != null: return existing
	var feedback := new()
	feedback.name = "CardPressFeedback"
	feedback.button = source
	feedback.visual = source if target == null else target
	source.add_child(feedback)
	return feedback

func _ready() -> void:
	motion = get_node("/root/UiMotion")
	rest_scale = visual.scale
	rest_tint = visual.self_modulate
	_center()
	visual.resized.connect(_center)
	button.button_down.connect(_press.bind(true))
	button.button_up.connect(_press.bind(false))
	button.pressed.connect(_press.bind(false))
	button.mouse_exited.connect(_press.bind(false))
	button.focus_exited.connect(_press.bind(false))
	button.visibility_changed.connect(_visibility_changed)
	if visual != button: visual.visibility_changed.connect(_visibility_changed)
	motion.preference_changed.connect(_reset)

func _center() -> void:
	visual.pivot_offset = visual.size * 0.5

func _press(down: bool) -> void:
	if frozen or (down and button.disabled): return
	var duration := 0.08 if down else 0.10
	var zoom := 0.98 if down and not motion.reduced() else 1.0
	var tint := rest_tint.darkened(0.035) if down else rest_tint
	motion.animate(self, visual, ^"scale", rest_scale * zoom, duration)
	motion.animate(self, visual, ^"self_modulate", tint, duration)

func _visibility_changed() -> void:
	if not button.is_visible_in_tree() or not visual.is_visible_in_tree(): _reset()

func _reset() -> void:
	if frozen: return
	motion.cancel(self, false)
	if is_instance_valid(visual):
		visual.scale = rest_scale
		visual.self_modulate = rest_tint

func freeze() -> void:
	# A modal exit keeps the current press pose instead of snapping it back.
	frozen = true
	motion.cancel(self, false)

func _exit_tree() -> void:
	if is_instance_valid(motion):
		frozen = false
		_reset()
