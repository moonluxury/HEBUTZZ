extends Node
## Owns only the existing Label's fill and title opacity. No business callbacks.
const TitleShader = preload("res://shaders/card_title.gdshader")
const FADE := 0.20
const SWEEP := 0.50
const INTERVAL := 7.0
const STOP := 0.08
const STRENGTH := 0.26
var label: Label
var dark := false
var material: ShaderMaterial
var waiting := false
var opening_started := false
var _presented := false
var _closed := false
var _intro_done := false
var _generation := 0
var _fade: Tween
var _sweep: Tween
var _idle: Timer
var _motion: Node
var _bounds := Rect2()

static func bind(target: Label, dark_background := false) -> Node:
	var existing := target.get_node_or_null("CardTitleEffect")
	if existing != null: return existing
	var effect := new()
	effect.name = "CardTitleEffect"
	effect.label = target
	effect.dark = dark_background
	target.add_child(effect)
	return effect

func _ready() -> void:
	_motion = get_node("/root/UiMotion")
	# Readable native fallback; no fonts, metrics, alignment or layout are changed.
	label.add_theme_color_override("font_color", Color("#81A8F3") if dark else Color("#164AB9"))
	if ProjectSettings.get_setting("rendering/card_title/use_shader", true):
		material = ShaderMaterial.new()
		material.shader = TitleShader
		_set_alpha(1.0)
		_set_strength(0.0)
		_set_position(-0.18)
		if dark:
			material.set_shader_parameter("deep_blue", Color("#6D91E0"))
			material.set_shader_parameter("campus_blue", Color("#81A8F3"))
			material.set_shader_parameter("bright_blue", Color("#A6C3FF"))
		label.material = material
	_idle = Timer.new()
	_idle.one_shot = true
	add_child(_idle)
	_idle.timeout.connect(_idle_timeout)
	label.resized.connect(_update_bounds)
	label.theme_changed.connect(_update_bounds)
	label.draw.connect(_update_bounds)
	label.visibility_changed.connect(_visibility_changed)
	_motion.preference_changed.connect(_preference_changed)
	_update_bounds()

func _update_bounds() -> void:
	if material == null or not label.is_inside_tree(): return
	var bounds := Rect2()
	for index in label.text.length():
		var character := label.get_character_bounds(index)
		if character.has_area(): bounds = character if not bounds.has_area() else bounds.merge(character)
	if not bounds.has_area() or bounds == _bounds: return
	_bounds = bounds
	material.set_shader_parameter("text_bounds", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))

func present() -> void:
	if _presented or _closed: return
	_presented = true
	if material == null or _motion.reduced() or not label.is_visible_in_tree():
		_intro_done = true
		_set_alpha(1.0)
		return
	_set_alpha(0.0)
	var ticket := _generation
	_fade = create_tween()
	_fade.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fade.tween_method(_set_alpha, 0.0, 1.0, FADE)
	_fade.tween_callback(func():
		_fade = null
		if ticket != _generation or _closed: return
		_intro_done = true
		if not opening_started: _start_sweep())

func set_waiting(value: bool) -> void:
	value = value and not opening_started and not _closed
	if waiting == value: return
	waiting = value
	if not waiting: _stop_sweep(true)
	elif _intro_done and _sweep == null: _schedule(INTERVAL)

func begin_opening() -> void:
	if opening_started or _closed: return
	opening_started = true
	waiting = false
	_stop_sweep(true)

func _can_animate() -> bool:
	return _presented and not _closed and material != null and label.is_visible_in_tree() and not _motion.reduced() and not opening_started

func _start_sweep() -> void:
	if not _can_animate(): return
	_idle.stop()
	_set_strength(STRENGTH)
	_set_position(-0.18)
	var ticket := _generation
	_sweep = create_tween()
	_sweep.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sweep.tween_method(_set_position, -0.18, 1.18, SWEEP)
	_sweep.tween_callback(func():
		_sweep = null
		_set_strength(0.0)
		if ticket == _generation: _schedule(INTERVAL - SWEEP))

func _schedule(delay: float) -> void:
	if waiting and _can_animate(): _idle.start(delay)

func _idle_timeout() -> void:
	if waiting and _can_animate(): _start_sweep()

func _stop_sweep(smooth: bool) -> void:
	_idle.stop()
	_kill(_sweep)
	_sweep = null
	if material == null: return
	var strength: float = material.get_shader_parameter("sweep_strength")
	if smooth and strength > 0.0 and label.is_visible_in_tree() and not _motion.reduced():
		_sweep = create_tween()
		_sweep.tween_method(_set_strength, strength, 0.0, STOP)
		_sweep.tween_callback(func(): _sweep = null)
	else: _set_strength(0.0)

func _set_alpha(value: float) -> void:
	if material != null: material.set_shader_parameter("title_alpha", value)

func _set_position(value: float) -> void:
	if material != null: material.set_shader_parameter("sweep_position", value)

func _set_strength(value: float) -> void:
	if material != null: material.set_shader_parameter("sweep_strength", value)

func _cancel_work() -> void:
	_generation += 1
	_kill(_fade)
	_fade = null
	_stop_sweep(false)

func close() -> void:
	if _closed: return
	_closed = true
	waiting = false
	_cancel_work()

func _visibility_changed() -> void:
	if not label.is_visible_in_tree():
		_cancel_work()
		_set_alpha(1.0)
		_intro_done = true
	elif not _closed and _intro_done: _schedule(INTERVAL)

func _preference_changed() -> void:
	if _closed: return
	if _motion.reduced():
		_cancel_work()
		_set_alpha(1.0)
		_intro_done = true
	elif _intro_done: _schedule(INTERVAL)

func _kill(tween: Tween) -> void:
	if tween != null:
		if is_instance_valid(_motion): tween.bind_node(_motion)
		tween.kill()

func _exit_tree() -> void:
	if is_instance_valid(_idle): close()
