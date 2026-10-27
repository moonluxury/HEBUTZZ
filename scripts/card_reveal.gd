extends Control
## Presentation only. A shared session survives collection/theme rebuilds.
## No inventory, reward, account or persistence calls belong in this control.
signal presentation_changed
signal completed(card_id: String, session_id: int)
signal action_finished
const FlipShader = preload("res://shaders/card_reveal.gdshader")
const GrayShader = preload("res://shaders/collection_unowned.gdshader")
const Tokens = preload("res://scripts/ui_tokens.gd")
const ENTRY := 0.36
const REVEAL := 1.8
const REDUCED := 0.18
const TOP_SPACE := 48.0
const BOTTOM_SPACE := 12.0
const EXTRA_HEIGHT := TOP_SPACE + BOTTOM_SPACE
const PARTICLES := 15
var session: Dictionary = {}
var state := "loading"
var front_texture: Texture2D
var back_texture: Texture2D
var face: TextureRect
var entry: Control
var sparks: Control
var retry_button: Button
var status_label: Label
var flip_material: ShaderMaterial
var gray_material: ShaderMaterial
var grayscale := false
var detail_alpha := 0.0
var detail_offset := 6.0
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

static func new_session(card: Dictionary, back_path: String, serial: int, animated := true) -> Dictionary:
	return {"id": serial, "card": card.duplicate(true), "back": back_path,
		"state": "loading", "elapsed": 0.0, "reduced": false,
		"static": not animated, "completed": false}

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
	retry_button = _action("重新加载", retry)
	resized.connect(_layout)
	set_process(false)
	_layout()

func _action(caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.accessibility_name = caption
	button.add_theme_font_size_override("font_size", 14)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#F5F8FE")
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	for key in ["normal", "hover", "pressed", "focus"]:
		var variant: StyleBoxFlat = style.duplicate()
		if key == "hover" or key == "pressed":
			variant.bg_color = Tokens.SOFT
		if key == "focus":
			variant.set_border_width_all(2)
			variant.border_color = Tokens.PRIMARY
		button.add_theme_stylebox_override(key, variant)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, Tokens.PRIMARY)
	button.pressed.connect(callback)
	button.hide()
	add_child(button)
	return button

func present(value: Dictionary, gray := false) -> void:
	_dispose()
	session = value
	grayscale = gray
	front_texture = null
	back_texture = null
	face.texture = null
	face.material = null
	entry.modulate.a = 1.0
	entry.scale = Vector2.ONE
	orbit_alpha = 0.0
	sparkle_progress = 0.0
	glow_strength = 0.0
	state = "loading"
	status_label.text = "正在准备卡片…"
	status_label.show()
	retry_button.hide()
	detail_alpha = 0.0
	detail_offset = 6.0
	interactive = false
	accessibility_name = "正在准备收藏卡片"
	_pending.clear()
	var resources := get_node("/root/UiResources")
	for path in [str(session.card.get("image", "")), str(session.back)]:
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
		elif path == str(session.back) and back_texture == null:
			back_texture = resources.textures[path] as Texture2D
			face.texture = back_texture
	if not loaded:
		return
	front_texture = resources.textures[str(session.card.image)] as Texture2D
	if front_texture == null or back_texture == null:
		_fail()
		return
	set_process(false)
	flip_material.set_shader_parameter("front_image", front_texture)
	flip_material.set_shader_parameter("back_image", back_texture)
	flip_material.set_shader_parameter("grayscale", grayscale)
	status_label.hide()
	if session.static or session.completed:
		_finish(false)
		return
	if _motion.reduced() and not session.reduced:
		session.reduced = true
		session.elapsed = 0.0
	_play()

func _play() -> void:
	_kill_tween()
	var end := REDUCED if session.reduced else ENTRY + REVEAL
	var start := clampf(float(session.elapsed), 0.0, end)
	_set_elapsed(start)
	var ticket := _generation
	_tween = create_tween()
	_tween.tween_method(_set_elapsed, start, end, maxf(0.001, end - start))
	_tween.tween_callback(func():
		if ticket == _generation and is_inside_tree():
			_finish(true)
	)

func _set_elapsed(value: float) -> void:
	session.elapsed = value
	retry_button.hide()
	status_label.hide()
	interactive = false
	orbit_alpha = 0.0
	sparkle_progress = 0.0
	glow_strength = 0.0
	face.material = flip_material
	face.texture = back_texture
	entry.position = card_rect.position
	entry.scale = Vector2.ONE
	entry.modulate.a = 1.0
	flip_material.set_shader_parameter("turn", 0.0)
	flip_material.set_shader_parameter("rim", 0.0)
	flip_material.set_shader_parameter("shine_strength", 0.0)
	if session.reduced:
		state = "revealing"
		face.texture = front_texture
		face.material = gray_material if grayscale else null
		entry.modulate.a = _smooth(value / REDUCED)
		detail_alpha = entry.modulate.a
		detail_offset = 0.0
	elif value < ENTRY:
		state = "ready"
		var amount := 1.0 - pow(1.0 - value / ENTRY, 3)
		entry.position.y += (1.0 - amount) * 18.0
		entry.scale = Vector2.ONE * lerpf(0.95, 1.0, amount)
		entry.modulate.a = amount
		detail_alpha = 0.0
		detail_offset = 6.0
	else:
		state = "revealing"
		var t := value - ENTRY
		var card_scale := 1.0
		if t < 0.12:
			card_scale = lerpf(1.0, 0.98, _smooth(t / 0.12))
		elif t < 0.44:
			card_scale = lerpf(0.98, 1.01, _smooth((t - 0.12) / 0.32))
		elif t < 1.18:
			card_scale = 1.01 + 0.015 * sin(PI * (t - 0.44) / 0.74)
		else:
			card_scale = lerpf(1.01, 1.0, _smooth((t - 1.18) / 0.32))
		entry.scale = Vector2.ONE * card_scale
		# A single cubic Hermite curve: 90 degrees at 800 ms with a continuous slope.
		var angle := PI
		if t < 0.44:
			angle = 0.0
		elif t < 0.80:
			var p := (t - 0.44) / 0.36
			angle = (p * p * (3.0 - 2.0 * p) * PI * 0.5) + (p * p * (p - 1.0) * 0.36 * 6.0)
		elif t < 1.18:
			var p := (t - 0.80) / 0.38
			angle = PI * 0.5 + (p * p * (3.0 - 2.0 * p) * PI * 0.5) + (p * (p - 1.0) * (p - 1.0) * 0.38 * 6.0)
		flip_material.set_shader_parameter("turn", angle)
		if t >= 0.12 and t < 0.65:
			orbit_alpha = _smooth((t - 0.12) / 0.14) * (1.0 - _smooth((t - 0.44) / 0.21)) * 0.3
			orbit_progress = clampf((t - 0.12) / 0.53, 0.0, 1.0)
		glow_strength = _smooth((t - 0.12) / 0.32) * (1.0 - _smooth((t - 1.18) / 0.32))
		if t >= 0.78 and t < 0.94:
			flip_material.set_shader_parameter("rim", sin((t - 0.78) / 0.16 * PI) * 0.4)
		if t >= 1.20 and t < 1.60:
			var p := (t - 1.20) / 0.40
			flip_material.set_shader_parameter("shine_position", lerpf(-0.25, 1.75, p))
			flip_material.set_shader_parameter("shine_strength", sin(p * PI) * 0.12)
		if t >= 1.18 and t < 1.72:
			sparkle_progress = (t - 1.18) / 0.54
		detail_alpha = _smooth((t - 1.50) / 0.30)
		detail_offset = (1.0 - detail_alpha) * 6.0
	session.state = state
	queue_redraw()
	sparks.queue_redraw()
	presentation_changed.emit()

func _smooth(value: float) -> float:
	var p := clampf(value, 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p)

func skip() -> void:
	if state not in ["ready", "revealing"]:
		return
	_finish(true)
	action_finished.emit()

func _finish(notify: bool) -> void:
	_kill_tween()
	set_process(false)
	state = "revealed"
	session.state = state
	session.elapsed = REDUCED if session.reduced else ENTRY + REVEAL
	face.texture = front_texture
	face.material = gray_material if grayscale else null
	entry.position = card_rect.position
	entry.scale = Vector2.ONE
	entry.modulate.a = 1.0
	orbit_alpha = 0.0
	sparkle_progress = 0.0
	glow_strength = 0.0
	status_label.hide()
	retry_button.hide()
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
	status_label.text = "卡图暂不可用，可重新加载"
	status_label.show()
	retry_button.show()
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
	if _motion.suspended:
		_finish(true)
	else:
		session.reduced = true
		session.elapsed = 0.0
		_play()

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
	var width := minf(240.0, minf(maxf(0.0, size.x - 32.0), maxf(0.0, size.y - EXTRA_HEIGHT) / 1.5))
	card_rect = Rect2((size.x - width) * 0.5, TOP_SPACE, width, width * 1.5)
	entry.position = card_rect.position
	entry.size = card_rect.size
	entry.pivot_offset = card_rect.size * 0.5
	face.size = card_rect.size
	flip_material.set_shader_parameter("card_size", card_rect.size)
	status_label.position = Vector2(0, 0)
	status_label.size = Vector2(size.x - (116 if state == "error" else 0), 44)
	retry_button.position = Vector2(maxf(0, size.x - 108), 0)
	retry_button.size = Vector2(108, 44)
	if state in ["ready", "revealing"]:
		_set_elapsed(float(session.elapsed))
	queue_redraw()
	sparks.queue_redraw()

func _draw() -> void:
	if card_rect.size.x <= 0 or state in ["error", "cancelled"]:
		return
	var center := card_rect.get_center()
	# Static soft ellipses, drawn behind the whole paper card, never a rectangle.
	draw_set_transform(center, 0, Vector2(1.0, 1.15))
	for index in range(16, 0, -1):
		var p := float(index) / 16.0
		draw_circle(Vector2.ZERO, card_rect.size.x * (0.40 + p * 0.22), Color(0.67, 0.80, 1.0, (0.003 + 0.003 * glow_strength) * (1.0 - p * 0.5)))
	draw_set_transform(center + Vector2(0, card_rect.size.y * 0.49), 0, Vector2(1.0, 0.13))
	for index in range(10, 0, -1):
		draw_circle(Vector2.ZERO, card_rect.size.x * (0.28 + index * 0.016), Color(0.04, 0.17, 0.40, 0.006))
	draw_set_transform(Vector2.ZERO)
	if orbit_alpha > 0:
		var points := PackedVector2Array()
		for index in 97:
			points.append(_orbit_point(TAU * index / 96.0))
		draw_polyline(points, Color(0.55, 0.72, 0.96, orbit_alpha), 1.0, true)
		var point := _orbit_point(PI * orbit_progress + PI * 0.08)
		draw_circle(point, 4, Color(1.0, 0.96, 0.81, orbit_alpha * 0.35))
		draw_circle(point, 1.8, Color(0.79, 0.69, 0.42, orbit_alpha * 2.0))

func _orbit_point(angle: float) -> Vector2:
	return card_rect.get_center() + Vector2(cos(angle) * card_rect.size.x * 0.625, sin(angle) * card_rect.size.y * 0.225).rotated(deg_to_rad(18))

func _draw_sparks() -> void:
	if sparkle_progress <= 0 or sparkle_progress >= 1:
		return
	var amount := sin(sparkle_progress * PI) * 0.65 * 1.10
	for index in PARTICLES:
		var angle := TAU * index / PARTICLES + 0.17
		var direction := Vector2(cos(angle), sin(angle))
		# Start beyond the rectangle, not on an ellipse that crosses the artwork.
		var distance := minf(card_rect.size.x * 0.5 / maxf(absf(direction.x), 0.001), card_rect.size.y * 0.5 / maxf(absf(direction.y), 0.001)) + 12.0
		var edge := direction * distance
		var point := card_rect.get_center() + edge + direction * sparkle_progress * (20.0 + (index % 4) * 10.0)
		var color := Color(0.79, 0.69, 0.42, amount * 0.65) if index % 3 == 0 else Color(0.65, 0.78, 0.98, amount)
		sparks.draw_circle(point, 1.0 + (index % 3) * 0.5, color)
