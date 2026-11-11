extends Node2D
## One presentation-only selection effect. No timers, purchases or card identities.
signal changed
const T = preload("res://scripts/ui_tokens.gd")
const Motion = preload("res://scripts/card_modal_motion.gd")
const Outline = preload("res://shaders/card_selection_outline.gdshader")
const BLUE := Color("#416CD7")
const ICE := Color("#D6EAFF")
const GOLD := Color("#D8C38A")
const PADDING := 24.0
var active_index := -1
var committed := false
var elapsed := 0.0
var reduced := false
var card_size := Vector2(184, 276)
var yaw := 0.0
var _start_scale := 1.0
var _opacity := 1.0
var _handoff := 1.0
var _ending := false
var _end_scale := 1.0
var _fade_start := 1.0
var _frozen := false
var _timeline: Tween
var _fade: Tween
var _motion: Node
var _rear: Node2D
var _front: Node2D
var _glow: TextureRect

func _ready() -> void:
	_motion = get_node("/root/UiMotion")
	_motion.preference_changed.connect(_preference_changed)
	_rear = Node2D.new()
	_rear.z_index = -1
	add_child(_rear)
	_rear.draw.connect(_draw_effect.bind(_rear, false))
	_glow = TextureRect.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var material := ShaderMaterial.new()
	material.shader = Outline
	_glow.material = material
	_rear.add_child(_glow)
	_front = Node2D.new()
	_front.z_index = 1
	add_child(_front)
	_front.draw.connect(_draw_effect.bind(_front, true))
	hide()
	set_process(false)

func preview(index: int) -> void:
	reset()
	active_index = index
	reduced = _motion.reduced()
	show()
	_refresh()

func activate(index: int, start_scale := 1.0) -> void:
	reset()
	active_index = index
	committed = true
	reduced = _motion.reduced()
	_start_scale = start_scale
	show()
	_refresh() # Immediate edge response, before the next rendered frame.
	_timeline = create_tween()
	_timeline.tween_method(_set_elapsed, 0.0, T.CARD_PICK_REDUCED if reduced else T.CARD_PICK_DURATION, T.CARD_PICK_REDUCED if reduced else T.CARD_PICK_DURATION)
	_timeline.tween_callback(func():
		_timeline = null)

func cancel_preview() -> void:
	if not committed: fade_out()

func fade_out() -> void:
	if active_index < 0: return
	_end_scale = card_scale()
	_ending = true
	_fade_start = maxf(_opacity, 0.001)
	_kill(_timeline); _timeline = null
	_kill(_fade)
	_fade = create_tween()
	_fade.tween_method(_set_opacity, _opacity, 0.0, T.CARD_PICK_RELEASE)
	_fade.tween_callback(func(): _fade = null; reset())

func card_scale() -> float:
	if not committed or reduced or active_index < 0: return 1.0
	if _ending: return lerpf(_end_scale, 1.0, 1.0 - _opacity / _fade_start)
	var t := _design_time()
	if t < 0.06: return lerpf(_start_scale, 0.97, Motion.out(t / 0.06))
	if t < 0.18: return lerpf(0.97, 1.03, Motion.out((t - 0.06) / 0.12))
	if t < 0.32: return lerpf(1.03, 1.0, Motion.out((t - 0.18) / 0.14))
	return 1.0

func back_light(extraction: float) -> float:
	if active_index < 0: return 0.0
	var level := T.CARD_PICK_BACK_LIGHT * (1.0 if committed else 0.55)
	return level * _opacity * (1.0 - smoothstep(0.62, 1.0, extraction))

func _design_time() -> float:
	# All four stages scale together when the one duration token is adjusted.
	return 0.45 if T.CARD_PICK_DURATION <= 0.0 else 0.45 * clampf(elapsed / T.CARD_PICK_DURATION, 0.0, 1.0)

func sync_from(slot: TextureRect, extraction: float) -> void:
	# Same center, rotation, scale, drawing depth and edge fade as the real card.
	position = slot.position + slot.pivot_offset
	scale = slot.scale
	rotation = slot.rotation
	modulate = slot.modulate
	z_index = slot.z_index
	card_size = slot.size
	yaw = float(slot.material.get_shader_parameter("yaw"))
	_handoff = 1.0 - smoothstep(0.62, 1.0, extraction)
	_glow.texture = slot.texture
	_glow.position = -card_size * 0.5 - Vector2.ONE * PADDING
	_glow.size = card_size + Vector2.ONE * PADDING * 2.0
	_glow.material.set_shader_parameter("card_size", card_size)
	_glow.material.set_shader_parameter("padding", PADDING)
	_glow.material.set_shader_parameter("yaw", yaw)
	_update_drawing()

func _set_elapsed(value: float) -> void:
	elapsed = value
	_refresh()

func _set_opacity(value: float) -> void:
	_opacity = value
	_refresh()

func _refresh() -> void:
	_update_drawing()
	changed.emit()

func _update_drawing() -> void:
	if not is_instance_valid(_glow): return
	var edge := 0.75 if not committed else lerpf(1.15, 0.32, smoothstep(0.18, 0.45, _design_time()))
	if reduced: edge = 0.65 * (1.0 - smoothstep(0.04, T.CARD_PICK_REDUCED, elapsed))
	_glow.material.set_shader_parameter("strength", edge * _opacity * _handoff)
	_rear.queue_redraw()
	_front.queue_redraw()

func _project(point: Vector2) -> Vector2:
	var normalized := point / card_size.x
	return Vector2(normalized.x * cos(yaw), normalized.y) * 5.0 / (5.0 + normalized.x * sin(yaw)) * card_size.x

func _draw_effect(layer: Node2D, front: bool) -> void:
	if active_index < 0 or not committed or reduced: return
	var t := _design_time()
	var amount := smoothstep(0.055, 0.16, t) * (1.0 - smoothstep(0.24, 0.45, t)) * _opacity * _handoff
	if amount > 0.001:
		_draw_orbit(layer, front, 0, amount)
		_draw_orbit(layer, front, 1, amount * 0.72)
	if front: _draw_particles(layer)

func _draw_orbit(layer: Node2D, front: bool, orbit: int, amount: float) -> void:
	var t := _design_time()
	var reach := Motion.out((t - 0.055) / 0.125)
	var start := -0.90 + t * 0.8 if orbit == 0 else 1.10 - t * 0.6
	var length := (TAU * 0.73 if orbit == 0 else TAU * 0.54) * reach
	var radii := card_size * (Vector2(0.76, 0.56) if orbit == 0 else Vector2(0.90, 0.43))
	var tilt := -0.34 if orbit == 0 else 0.40
	var color := BLUE if orbit == 0 else GOLD
	var points := PackedVector2Array()
	var no_ink := Rect2(-card_size * 0.5, card_size).grow(4.0)
	for i in 97:
		var angle := start + length * i / 96.0
		var point := _project((Vector2(cos(angle), sin(angle)) * radii).rotated(tilt))
		# Rear arcs are occluded by the artwork; front arcs never cross its text.
		var visible_part := (sin(angle) >= 0.0) == front and (not front or not no_ink.has_point(point))
		if visible_part:
			points.append(point)
		else:
			_stroke(layer, points, color, amount)
			points.clear()
	_stroke(layer, points, color, amount)

func _stroke(layer: Node2D, points: PackedVector2Array, color: Color, amount: float) -> void:
	if points.size() < 2: return
	layer.draw_polyline(points, Color(color, amount * 0.12), 14.0, true)
	layer.draw_polyline(points, Color(color, amount * 0.35), 5.0, true)
	layer.draw_polyline(points, Color(color.lerp(ICE, 0.25), amount * 0.95), 1.6, true)

func _draw_particles(layer: Node2D) -> void:
	var t := _design_time()
	for i in T.CARD_PICK_PARTICLES:
		var p := (t - 0.12 - (i % 5) * 0.010) / 0.23
		if p <= 0.0 or p >= 1.0: continue
		var angle := i * 2.399963 + 0.20
		var direction := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-direction.y, direction.x)
		var edge := minf(card_size.x * 0.5 / maxf(absf(direction.x), 0.001), card_size.y * 0.5 / maxf(absf(direction.y), 0.001)) + 12.0
		var travel := direction * (16.0 + i % 4 * 6.0) + tangent * (20.0 + i % 6 * 6.0) + Vector2(-18, 4)
		var point := _project(direction * edge + travel * p)
		if Rect2(-card_size * 0.5, card_size).grow(5).has_point(point): continue
		var alpha := sin(PI * p) * _opacity * _handoff
		var color := GOLD if i % 4 == 0 else ICE if i % 3 == 0 else BLUE
		var trail := _project(direction * edge + travel * maxf(0.0, p - 0.24))
		layer.draw_line(trail, point, Color(color, alpha * 0.45), 1.1, true)
		layer.draw_circle(point, 7.0, Color(color, alpha * 0.12))
		layer.draw_circle(point, 1.4 + i % 3 * 0.65, Color(color, alpha * 0.95))
		if i % 6 == 0:
			layer.draw_line(point - Vector2(4.5, 0), point + Vector2(4.5, 0), Color(ICE, alpha * 0.75), 1.0, true)
			layer.draw_line(point - Vector2(0, 4.5), point + Vector2(0, 4.5), Color(ICE, alpha * 0.75), 1.0, true)

func _preference_changed() -> void:
	if _frozen or reduced or active_index < 0 or not _motion.reduced(): return
	var index := active_index
	if committed: activate(index)
	else:
		reduced = true
		_refresh()

func freeze() -> void:
	_frozen = true
	_kill(_timeline); _timeline = null
	_kill(_fade); _fade = null

func reset() -> void:
	freeze()
	_frozen = false
	active_index = -1
	committed = false
	elapsed = 0.0
	_opacity = 1.0
	_handoff = 1.0
	_ending = false
	hide()
	_refresh()

func _kill(tween: Tween) -> void:
	if tween == null: return
	if is_instance_valid(_motion): tween.bind_node(_motion)
	tween.kill()

func _exit_tree() -> void:
	freeze()
