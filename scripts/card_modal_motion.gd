extends Node
## Modal transforms are independent of the card's shader and reveal feedback.
signal entered
signal exited
const ENTER := 0.32
const EXIT := 0.20
const REDUCED := 0.14
var background: Control
var content: Control
var state := "closed"
var base_position := Vector2.ZERO
var base_scale := Vector2.ONE
var offset := Vector2.ZERO
var zoom := 1.0
var _tween: Tween
var _reduced := false

static func curve(value: float, a: Vector2, b: Vector2) -> float:
	var x := clampf(value, 0.0, 1.0)
	if x == 0.0 or x == 1.0: return x
	var low := 0.0
	var high := 1.0
	for i in 12:
		var t := (low + high) * 0.5
		var sample := 3.0 * (1.0 - t) * (1.0 - t) * t * a.x + 3.0 * (1.0 - t) * t * t * b.x + t * t * t
		if sample < x: low = t
		else: high = t
	var t := (low + high) * 0.5
	return 3.0 * (1.0 - t) * (1.0 - t) * t * a.y + 3.0 * (1.0 - t) * t * t * b.y + t * t * t

static func out(value: float) -> float:
	return curve(value, Vector2(0.22, 1), Vector2(0.36, 1))

func configure(backdrop: Control, group: Control) -> void:
	background = backdrop
	content = group
	if ProjectSettings.get_setting("rendering/card_modal/use_blur", true):
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/card_modal_backdrop.gdshader")
		background.material = material
		background.color = Color.WHITE
	get_node("/root/UiMotion").preference_changed.connect(_preference_changed)

func layout(position: Vector2, scale_value := Vector2.ONE) -> void:
	base_position = position
	base_scale = scale_value
	_apply_transform()

func _apply_transform() -> void:
	content.pivot_offset = content.size * 0.5
	content.position = base_position + offset * base_scale
	content.scale = base_scale * zoom

func present() -> void:
	_kill()
	_reduced = get_node("/root/UiMotion").reduced()
	state = "entering"
	_enter_frame(0.0)
	var duration := REDUCED if _reduced else ENTER
	_tween = create_tween()
	_tween.tween_method(_enter_frame, 0.0, duration, duration)
	_tween.tween_callback(func():
		state = "ready"
		entered.emit())

func _enter_frame(time: float) -> void:
	var p := out(time / (REDUCED if _reduced else ENTER))
	zoom = 1.0 if _reduced else lerpf(0.96, 1.0, p)
	offset = Vector2.ZERO if _reduced else Vector2(0, 16 * (1.0 - p))
	content.modulate.a = out(time / 0.14)
	background.modulate.a = out(time / (REDUCED if _reduced else 0.18))
	_apply_transform()

func dismiss() -> void:
	if state in ["closed", "exiting"]: return
	_kill()
	state = "exiting"
	_reduced = get_node("/root/UiMotion").reduced()
	var start_zoom := zoom
	var start_offset := offset
	var start_alpha := content.modulate.a
	var shade_alpha := background.modulate.a
	_tween = create_tween()
	_tween.tween_method(func(value: float):
		var p := curve(value, Vector2(0.4, 0), Vector2(1, 1))
		zoom = 1.0 if _reduced else lerpf(start_zoom, 0.985, p)
		offset = Vector2.ZERO if _reduced else start_offset.lerp(Vector2(0, 8), p)
		content.modulate.a = start_alpha * (1.0 - p)
		background.modulate.a = shade_alpha * (1.0 - p)
		_apply_transform(), 0.0, 1.0, REDUCED if _reduced else EXIT)
	_tween.tween_callback(func():
		state = "closed"
		exited.emit())

func _preference_changed() -> void:
	if not get_node("/root/UiMotion").reduced(): return
	_reduced = true
	zoom = 1.0
	offset = Vector2.ZERO
	_apply_transform()

func _kill() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null

func _exit_tree() -> void:
	_kill()
