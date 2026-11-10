extends Control
## Presentation only. A shared session survives collection/theme rebuilds.
## No inventory, reward, account or persistence calls belong in this control.
signal presentation_changed
signal geometry_changed
signal completed(card_id: String, session_id: int)
signal action_finished
const FlipShader = preload("res://shaders/card_reveal.gdshader")
const GrayShader = preload("res://shaders/collection_unowned.gdshader")
const Tokens = preload("res://scripts/ui_tokens.gd")
const Motion = preload("res://scripts/card_modal_motion.gd")
# Durations are seconds. Increase REVEAL to slow the flip in both collection
# details and acquisition dialogs; entry and result timing stay independent.
const ENTRY := 0.32
const REVEAL := 0.70
const INFO := 0.16
const REDUCED := 0.14
const TOP_SPACE := 48.0
const BOTTOM_SPACE := 12.0
const EXTRA_HEIGHT := TOP_SPACE + BOTTOM_SPACE
const PARTICLES := 48
var session: Dictionary = {}
var state := "loading"
var front_texture: Texture2D
var back_texture: Texture2D
var face: TextureRect
var entry: Control
var sparks: Control
var status_label: Label
var flip_material: ShaderMaterial
var gray_material: ShaderMaterial
var grayscale := false
var detail_alpha := 0.0
var detail_offset := 4.0
var interactive := false
var card_rect := Rect2()
var orbit_alpha := 0.0
var orbit_progress := 0.0
var sparkle_progress := 0.0
var glow_strength := 0.0
var _tween: Tween
var _generation := 0
var _motion: Node
var _pending: Array[String] = []
var _gate_open := true
var _external_entry := false
var _aspect := 2.0 / 3.0
var top_space := TOP_SPACE
var bottom_space := BOTTOM_SPACE

static func new_session(card: Dictionary, back_path: String, serial: int, animated := true) -> Dictionary:
	return {"id": serial, "card": card.duplicate(true), "back": back_path,
		"state": "loading", "elapsed": 0.0, "reduced": false,
		"static": not animated, "completed": false, "external_entry": false}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion = get_node("/root/UiMotion")
	_motion.preference_changed.connect(_preference_changed)
	entry = Control.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(entry)
	face = TextureRect.new()
	face.name = "CardFace"
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(face)
	flip_material = ShaderMaterial.new()
	flip_material.shader = FlipShader
	gray_material = ShaderMaterial.new()
	gray_material.shader = GrayShader
	sparks = Control.new()
	sparks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sparks)
	sparks.draw.connect(_draw_sparks)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)
	resized.connect(_layout)
	set_process(false)
	_layout()

func present(value: Dictionary, gray := false) -> void:
	_dispose()
	session = value
	_aspect = float(session.get("aspect", 2.0 / 3.0))
	_external_entry = bool(session.get("external_entry", false))
	_gate_open = not _external_entry
	grayscale = gray
	front_texture = null
	back_texture = null
	face.texture = null
	face.material = null
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	entry.modulate.a = 1.0
	entry.scale = Vector2.ONE
	entry.rotation = 0.0
	orbit_alpha = 0.0
	sparkle_progress = 0.0
	glow_strength = 0.0
	state = "loading"
	status_label.text = "正在准备卡片…"
	status_label.show()
	detail_alpha = 0.0
	detail_offset = 4.0
	interactive = false
	accessibility_name = "正在准备收藏卡片"
	_pending.clear()
	var resources := get_node("/root/UiResources")
	var paths := [str(session.card.get("image", ""))]
	if not session.static and not session.completed:
		paths.append(str(session.back))
	for path in paths:
		if not _pending.has(path):
			_pending.append(path)
			if not resources.request_texture(path):
				_fail()
				return
	set_process(true)
	_poll_resources()

func _process(_delta: float) -> void:
	_poll_resources()

func _poll_resources() -> void:
	if state != "loading":
		set_process(false)
		return
	var loaded := true
	var resources := get_node("/root/UiResources")
	for path in _pending:
		var status: int = resources.texture_load_status(path)
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail()
			return
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			loaded = false
		elif not session.static and not session.completed and path == str(session.back) and back_texture == null:
			back_texture = resources.textures[path] as Texture2D
			face.texture = back_texture
			_aspect = float(back_texture.get_width()) / back_texture.get_height()
			session.aspect = _aspect
			_layout()
			presentation_changed.emit()
	if not loaded:
		return
	front_texture = resources.textures[str(session.card.image)] as Texture2D
	if front_texture == null or (not session.static and not session.completed and back_texture == null):
		_fail()
		return
	set_process(false)
	status_label.hide()
	if session.static or session.completed:
		_aspect = float(session.get("aspect", float(front_texture.get_width()) / front_texture.get_height()))
		_layout()
		_finish(false)
		return
	flip_material.set_shader_parameter("front_image", front_texture)
	flip_material.set_shader_parameter("back_image", back_texture)
	flip_material.set_shader_parameter("grayscale", grayscale)
	flip_material.set_shader_parameter("front_aspect", float(front_texture.get_width()) / front_texture.get_height())
	flip_material.set_shader_parameter("back_aspect", float(back_texture.get_width()) / back_texture.get_height())
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.material = flip_material
	flip_material.set_shader_parameter("turn", 0.0)
	flip_material.set_shader_parameter("crossfade", false)
	state = "ready"
	session.state = state
	if _motion.reduced() and not session.reduced:
		session.reduced = true
		session.elapsed = 0.0
	if _gate_open: _play()
	presentation_changed.emit()

func allow_reveal() -> void:
	_gate_open = true
	if state == "ready": _play()

func _entry_duration() -> float:
	return 0.0 if _external_entry else REDUCED if session.reduced else ENTRY

func _duration() -> float:
	return _entry_duration() + (REDUCED if session.reduced else REVEAL) + INFO

func _play() -> void:
	_kill_tween()
	var end := _duration()
	var start := clampf(float(session.elapsed), 0.0, end)
	_set_elapsed(start)
	if state == "revealed": return # A queued skip may finish synchronously.
	var ticket := _generation
	_tween = create_tween()
	_tween.tween_method(_set_elapsed, start, end, maxf(0.001, end - start))
	_tween.tween_callback(func():
		if ticket == _generation and is_inside_tree():
			_finish(true)
	)

func _set_elapsed(value: float) -> void:
	session.elapsed = value
	status_label.hide()
	interactive = false
	orbit_alpha = 0.0
	sparkle_progress = 0.0
	glow_strength = 0.0
	face.material = flip_material
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.texture = back_texture
	entry.position = card_rect.position
	entry.scale = Vector2.ONE
	entry.rotation = 0.0
	entry.modulate.a = 1.0
	flip_material.set_shader_parameter("turn", 0.0)
	flip_material.set_shader_parameter("crossfade", session.reduced)
	flip_material.set_shader_parameter("blend_amount", 0.0)
	var entry_time := _entry_duration()
	var flip_time := REDUCED if session.reduced else REVEAL
	var t := maxf(0.0, value - entry_time)
	detail_alpha = Motion.out((t - flip_time) / INFO)
	detail_offset = 0.0 if session.reduced else (1.0 - detail_alpha) * 4.0
	if value < entry_time:
		state = "ready"
		var amount := Motion.out(value / entry_time)
		if not session.reduced:
			entry.position.y += (1.0 - amount) * 16.0
			entry.scale = Vector2.ONE * lerpf(0.96, 1.0, amount)
		entry.modulate.a = Motion.out(value / REDUCED)
	else:
		state = "revealing"
		var p := clampf(t / flip_time, 0.0, 1.0)
		if session.reduced:
			flip_material.set_shader_parameter("blend_amount", _smooth(p))
		else:
			flip_material.set_shader_parameter("turn", PI * Motion.curve(p, Vector2(0.45, 0), Vector2(0.2, 1)))
			# One stronger pulse and a short damped shake, contained within the flip.
			# No image-specific choreography; the pivot and layout never change.
			var pulse := 1.0 - 0.065 * sin(PI * p / 0.38) if p < 0.38 else 1.0 + 0.075 * sin(PI * (p - 0.38) / 0.62)
			entry.scale = Vector2.ONE * pulse
			entry.position.x += sin(p * TAU * 3.0) * 4.0 * pow(1.0 - p, 2.0)
			entry.rotation = deg_to_rad(1.4) * sin(p * TAU * 2.0) * pow(1.0 - p, 2.0)
			if t > REVEAL * 0.55 and t < REVEAL + INFO:
				sparkle_progress = (t - REVEAL * 0.55) / (REVEAL * 0.45 + INFO)
	session.state = state
	queue_redraw()
	sparks.queue_redraw()
	presentation_changed.emit()

func _smooth(value: float) -> float:
	var p := clampf(value, 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p)

func skip() -> void:
	if state not in ["ready", "revealing"] or not _gate_open:
		return
	_finish(true)
	action_finished.emit()

func _finish(notify: bool) -> void:
	_kill_tween()
	set_process(false)
	state = "revealed"
	session.state = state
	session.elapsed = _duration()
	face.texture = front_texture
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.material = gray_material if grayscale else null
	entry.position = card_rect.position
	entry.scale = Vector2.ONE
	entry.rotation = 0.0
	entry.modulate.a = 1.0
	orbit_alpha = 0.0
	sparkle_progress = 0.0
	glow_strength = 0.0
	status_label.hide()
	detail_alpha = 1.0
	detail_offset = 0.0
	interactive = true
	accessibility_name = "%s，编号 %s，卡片已展示" % [session.card.get("name", "收藏卡片"), session.card.get("number", "")]
	queue_redraw()
	sparks.queue_redraw()
	presentation_changed.emit()
	if notify and not session.completed:
		session.completed = true
		completed.emit(str(session.card.id), int(session.id))

func _fail() -> void:
	_kill_tween()
	set_process(false)
	state = "error"
	session.state = state
	status_label.text = "卡图暂不可用"
	status_label.show()
	face.texture = null
	detail_alpha = 1.0
	detail_offset = 0.0
	interactive = true
	accessibility_name = "%s，卡图暂不可用" % session.card.get("name", "收藏卡片")
	_layout()
	queue_redraw()
	presentation_changed.emit()

func retry() -> void:
	if state != "error":
		return
	session.elapsed = 0.0
	present(session, grayscale)
	action_finished.emit()

func freeze() -> void:
	# Preserve the exact projected face and particles while the outer group exits.
	_dispose()
	state = "exiting"

func cancel() -> void:
	_dispose()
	state = "cancelled"
	if not session.is_empty():
		session.state = state
		session.static = true
	orbit_alpha = 0.0
	sparkle_progress = 0.0
	glow_strength = 0.0
	queue_redraw()
	if is_instance_valid(sparks):
		sparks.queue_redraw()

func _preference_changed() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or session.is_empty() or state not in ["ready", "revealing"] or not _motion.reduced():
		return
	if not _gate_open:
		session.reduced = true
		return
	# A preference change during playback must not jump back to the card back.
	session.reduced = true
	_finish(true)

func _kill_tween() -> void:
	if _tween != null:
		# Detached cached pages otherwise keep killed bound Tweens in SceneTree.
		if is_instance_valid(_motion):
			_tween.bind_node(_motion)
		_tween.kill()
		_tween = null

func _dispose() -> void:
	_generation += 1
	_kill_tween()
	set_process(false)

func _exit_tree() -> void:
	_dispose()

func _layout() -> void:
	if not is_instance_valid(face):
		return
	var width := minf(240.0, minf(maxf(0.0, size.x - 32.0), maxf(0.0, size.y - top_space - bottom_space) * _aspect))
	card_rect = Rect2((size.x - width) * 0.5, top_space, width, width / _aspect)
	entry.position = card_rect.position
	entry.size = card_rect.size
	entry.pivot_offset = card_rect.size * 0.5
	face.size = card_rect.size
	flip_material.set_shader_parameter("card_size", card_rect.size)
	status_label.position = Vector2(0, 0)
	status_label.size = Vector2(size.x, 44)
	if state in ["ready", "revealing"] and _gate_open:
		_set_elapsed(float(session.elapsed))
	queue_redraw()
	sparks.queue_redraw()
	geometry_changed.emit()

func _draw_sparks() -> void:
	if sparkle_progress <= 0 or sparkle_progress >= 1:
		return
	var amount := sin(sparkle_progress * PI) * 0.85
	for index in PARTICLES:
		var angle := TAU * index / PARTICLES + 0.17 + sin(index * 2.4) * 0.06
		var direction := Vector2(cos(angle), sin(angle))
		# Start beyond the rectangle, not on an ellipse that crosses the artwork.
		var distance := minf(card_rect.size.x * 0.5 / maxf(absf(direction.x), 0.001), card_rect.size.y * 0.5 / maxf(absf(direction.y), 0.001)) + 14.0
		var edge := direction * distance
		var point := card_rect.get_center() + edge + direction * sparkle_progress * (18.0 + (index % 5) * 6.0)
		var color := Color(0.79, 0.69, 0.42, amount * 0.65) if index % 3 == 0 else Color(0.65, 0.78, 0.98, amount)
		sparks.draw_circle(point, 1.0 + (index % 3) * 0.5, color)
