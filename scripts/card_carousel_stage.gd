extends Control
## Presentation only: identities may be reordered behind card backs, never drawn.
## Only the dialog supplies a verified receipt ID; no wallet/network/storage here.
signal prepared
signal entered
signal settled(card_id: String)
signal extracted(card_id: String)
signal failed(message: String)
signal chosen(index: int)
const T = preload("res://scripts/ui_tokens.gd")
const Motion = preload("res://scripts/card_modal_motion.gd")
const BackShader = preload("res://shaders/card_carousel.gdshader")
var cards: Array = []
var catalogue_cards: Array = []
var slots: Array[TextureRect] = []
var back_paths: Array[String] = []
var state := "empty"
var phase := 0.0
var focal_index := 0
var result_id := ""
var press_scale := 1.0
var entry_progress := 0.0
var extract_progress := 0.0
var _target_index := -1
var _start_phase := 0.0
var _target_phase := 0.0
var _landing_progress := 0.0
var _entry_requested := false
var _textures_ready := false
var _generation := 0
var _tween: Tween
var _motion: Node
var _destination := Rect2()
var _aspect := 2.0 / 3.0
var _hover_sources: Dictionary = {}
var speed_multiplier := 1.0
var _landing_speed := 1.0
var _landing_duration := 0.0
var _landing_lifts: Array[float] = []
var _landing_press := 1.0
var _centering := false
var _centered := false
var selection_enabled := false
var selected_index := -1
var hovered_index := -1
var _pressed_index := -1
var _press_index := -1
var _pointer := Vector2.ZERO
var _has_pointer := false
var _hover_lifts: Array[float] = []
var _back_images: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion = get_node("/root/UiMotion")
	_motion.preference_changed.connect(_preference_changed)
	resized.connect(_render_frame)
	if get_viewport().has_signal("mouse_exited"):
		get_viewport().connect("mouse_exited", _pointer_exited)
	set_process(false)

func configure(items: Array, season_back: String) -> void:
	_generation += 1
	_kill_tween()
	_motion.cancel(self, false)
	for slot in slots:
		remove_child(slot)
		slot.queue_free()
	slots.clear()
	back_paths.clear()
	catalogue_cards = items.duplicate(true)
	cards = []
	if not catalogue_cards.is_empty():
		for i in maxi(T.CARD_POOL_DISPLAY_COUNT, catalogue_cards.size()):
			cards.append(catalogue_cards[i % catalogue_cards.size()].duplicate(true))
	phase = 0.0
	result_id = ""
	_target_index = -1
	_entry_requested = false
	_textures_ready = false
	entry_progress = 0.0
	extract_progress = 0.0
	_landing_progress = 0.0
	press_scale = 1.0
	_hover_sources.clear()
	_hover_lifts.clear()
	_back_images.clear()
	_landing_lifts.clear()
	_centering = false
	_centered = false
	selected_index = -1
	hovered_index = -1
	_pressed_index = -1
	_press_index = -1
	selection_enabled = false
	speed_multiplier = 1.0
	state = "loading"
	if cards.is_empty():
		_fail("当前卡池暂不可用")
		return
	var resources := get_node("/root/UiResources")
	for i in cards.size():
		var card: Dictionary = cards[i]
		var path := str(card.get("back_image", season_back))
		back_paths.append(path)
		var slot := TextureRect.new()
		slot.name = "PoolCard_%s_%d" % [str(card.id), i]
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_SCALE
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# Picking is resolved in visual z-order below: Godot GUI sibling order
		# alone does not account for this overlapping, animated card ribbon.
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_hover_lifts.append(0.0)
		var mat := ShaderMaterial.new()
		mat.shader = BackShader
		slot.material = mat
		add_child(slot)
		slots.append(slot)
		if not resources.request_texture(path):
			_fail("卡背暂不可用，请稍后重新打开")
			return
	set_process(true)
	_poll_resources()

func has_card(id: String) -> bool:
	return _index_of(id) >= 0

func _index_of(id: String) -> int:
	for i in cards.size():
		if str(cards[i].id) == id: return i
	return -1

func present() -> void:
	_entry_requested = true
	if _textures_ready and state == "prepared": _start_entry()

func _poll_resources() -> void:
	if state != "loading": return
	var resources := get_node("/root/UiResources")
	for path in back_paths:
		var status: int = resources.texture_load_status(path)
		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_fail("卡背暂不可用，请稍后重新打开")
			return
		if status != ResourceLoader.THREAD_LOAD_LOADED: return
	for i in slots.size():
		slots[i].texture = resources.textures[back_paths[i]]
		if not _back_images.has(back_paths[i]):
			_back_images[back_paths[i]] = slots[i].texture.get_image()
	_aspect = float(slots[0].texture.get_width()) / slots[0].texture.get_height()
	_textures_ready = true
	state = "prepared"
	set_process(false)
	_render_frame()
	prepared.emit()
	if _entry_requested: _start_entry()

func _start_entry() -> void:
	state = "entering"
	if _motion.reduced():
		_set_entry(1.0)
		_entry_finished()
		return
	var ticket := _generation
	_tween = create_tween()
	_tween.tween_method(_set_entry, 0.0, 1.0, T.CARD_POOL_ENTER)
	_tween.tween_callback(func():
		if ticket == _generation: _entry_finished())

func _set_entry(value: float) -> void:
	entry_progress = clampf(value, 0.0, 1.0)
	_render_frame()

func _entry_finished() -> void:
	_tween = null
	state = "flowing"
	# The last laid card finishes at rest; blend into the existing flow speed.
	speed_multiplier = 0.0
	_update_processing()
	entered.emit()

func requesting(index := -1) -> void:
	if state == "flowing":
		selected_index = index if index >= 0 and index < slots.size() else focal_index
		state = "requesting"
		_start_rotation()
	set_selection_enabled(false)
	_hover_sources.clear()
	_update_processing()

func resume_flow() -> void:
	if state in ["flowing", "requesting"]:
		if state == "requesting":
			_kill_tween()
			_centering = false
			_centered = false
			selected_index = -1
		state = "flowing"
		_update_processing()

func _process(delta: float) -> void:
	if state == "loading":
		_poll_resources()
	elif state in ["flowing", "requesting"]:
		if not is_visible_in_tree() or _motion.reduced(): return
		var dt := minf(delta, 0.05)
		_update_hover()
		var over := state == "flowing" and not _hover_sources.is_empty()
		var blend := 1.0 - exp(-dt / T.CARD_POOL_HOVER_RESPONSE)
		speed_multiplier = lerpf(speed_multiplier, T.CARD_POOL_HOVER_SPEED if over else 1.0, blend)
		for i in _hover_lifts.size():
			_hover_lifts[i] = lerpf(_hover_lifts[i], 1.0 if over and i == hovered_index else 0.0, blend)
		phase = fposmod(phase + dt * speed_multiplier / T.CARD_POOL_STEP, cards.size())
		_render_frame()

func set_hover(source: int, value: bool) -> void:
	if value: _hover_sources[source] = true
	else: _hover_sources.erase(source)

func set_selection_enabled(value: bool) -> void:
	selection_enabled = value
	if not value:
		_hover_sources.clear()
		hovered_index = -1
		_pressed_index = -1
	else:
		_update_hover()

func _pointer_exited() -> void:
	_has_pointer = false
	_hover_sources.clear()
	hovered_index = -1
	_pressed_index = -1
	press(false)

func _update_hover() -> void:
	hovered_index = pick_slot(_pointer) if selection_enabled and _has_pointer and state == "flowing" else -1
	_hover_sources.clear()
	if hovered_index >= 0: set_hover(hovered_index, true)

func pick_slot(viewport_point: Vector2) -> int:
	if not is_visible_in_tree() or not _textures_ready: return -1
	var winner := -1
	var highest := -1
	# Resolve overlapping cards in their rendered order and reject transparent
	# corners. Inverse yaw matches the paper projection in card_carousel.gdshader.
	for i in range(slots.size() - 1, -1, -1):
		var slot := slots[i]
		if slot.modulate.a < 0.08 or slot.z_index <= highest: continue
		var local := slot.get_global_transform_with_canvas().affine_inverse() * viewport_point
		var ratio := slot.size.y / slot.size.x
		var screen := (local / slot.size - Vector2.ONE * 0.5) * Vector2(1.0, ratio)
		var yaw: float = slot.material.get_shader_parameter("yaw")
		var x := screen.x * 5.0 / (5.0 * cos(yaw) - screen.x * sin(yaw))
		var y := screen.y * (5.0 + x * sin(yaw)) / 5.0
		var uv := Vector2(x + 0.5, y / ratio + 0.5)
		if uv.x < 0 or uv.y < 0 or uv.x >= 1 or uv.y >= 1: continue
		var bitmap: Image = _back_images[back_paths[i]]
		if bitmap.get_pixel(int(uv.x * bitmap.get_width()), int(uv.y * bitmap.get_height())).a < 0.1: continue
		winner = i
		highest = slot.z_index
	return winner

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventMouseMotion:
		_pointer = event.position
		_has_pointer = true
		_update_hover()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not selection_enabled or state != "flowing": return
		_pointer = event.position
		_has_pointer = true
		var index := pick_slot(event.position)
		if event.pressed:
			_pressed_index = index
			if index >= 0:
				press(true, index)
				get_viewport().set_input_as_handled()
		else:
			var pressed := _pressed_index
			_pressed_index = -1
			press(false)
			if pressed >= 0:
				get_viewport().set_input_as_handled()
				if index == pressed:
					set_selection_enabled(false)
					chosen.emit(index)

func _update_processing() -> void:
	set_process(state == "loading" or (state == "flowing" and not _motion.reduced()))

func press(down: bool, index := -1) -> void:
	if state not in ["flowing", "requesting"]: return
	if down: _press_index = index if index >= 0 else focal_index
	_motion.animate(self, self, ^"press_scale", 0.98 if down and not _motion.reduced() else 1.0, T.PRESS)

func settle_to(id: String) -> bool:
	if state not in ["flowing", "requesting"] or not has_card(id): return false
	result_id = id
	_target_index = selected_index if selected_index >= 0 else focal_index
	selected_index = _target_index
	# Reorder local display copies only. This pool uses the season's real backs;
	# the RPC has already completed, and no client choice enters its payload.
	var previous := _index_of(id)
	var moved: Dictionary = cards[_target_index]
	cards[_target_index] = cards[previous]
	cards[previous] = moved
	var moved_path := back_paths[_target_index]
	back_paths[_target_index] = back_paths[previous]
	back_paths[previous] = moved_path
	var moved_texture := slots[_target_index].texture
	slots[_target_index].texture = slots[previous].texture
	slots[previous].texture = moved_texture
	state = "aligning"
	set_process(false)
	if _centered:
		_landing_finished()
	elif not _centering:
		_start_rotation()
	return true

func _start_rotation() -> void:
	# Every slot shares this single phase. The selected back stays in the band
	# and travels in the existing direction, including through the wrap if needed.
	_kill_tween()
	_motion.cancel(self, false)
	_start_phase = phase
	var travel := fposmod(float(selected_index) - phase, float(cards.size()))
	_target_phase = phase + travel
	_landing_duration = minf(T.CARD_POOL_TRAVEL_MAX, T.CARD_POOL_SETTLE + travel * T.CARD_POOL_TRAVEL_PER_SLOT)
	_landing_speed = minf(speed_multiplier / T.CARD_POOL_STEP, 3.0 * travel / _landing_duration)
	_landing_lifts = _hover_lifts.duplicate()
	_landing_press = press_scale
	_landing_progress = 0.0
	_centering = true
	_centered = false
	set_process(false)
	if _motion.reduced():
		_set_landing(1.0)
		_landing_finished()
		return
	var ticket := _generation
	_tween = create_tween()
	_tween.tween_method(_set_landing, 0.0, 1.0, _landing_duration)
	_tween.tween_callback(func():
		if ticket == _generation: _landing_finished())

func _set_landing(p: float) -> void:
	_landing_progress = p
	# Monotone Hermite motion preserves the current velocity, then eases the
	# entire ribbon to an exact integer phase. No individual card is dragged.
	var travel := _target_phase - _start_phase
	var tangent := _landing_speed * _landing_duration
	phase = _start_phase + (p*p*p - 2*p*p + p) * tangent + (-2*p*p*p + 3*p*p) * travel
	speed_multiplier = maxf(0.0, ((3*p*p - 4*p + 1) * tangent + (-6*p*p + 6*p) * travel) / _landing_duration) * T.CARD_POOL_STEP
	for i in _hover_lifts.size(): _hover_lifts[i] = _landing_lifts[i] * (1.0 - Motion.out(p))
	press_scale = lerpf(_landing_press, 1.0, Motion.out(p))
	_render_frame()

func _landing_finished() -> void:
	_tween = null
	_centering = false
	_centered = true
	phase = _target_phase
	state = "requesting" if result_id.is_empty() else "aligned"
	_render_frame()
	# Centering can complete before the network; wait with the real back only.
	if not result_id.is_empty(): settled.emit(result_id)

func extract_to(destination: Rect2) -> void:
	if state != "aligned": return
	_destination = destination
	state = "extracting"
	if _motion.reduced():
		_set_extraction(1.0)
		_extraction_finished()
		return
	var ticket := _generation
	_tween = create_tween()
	_tween.tween_method(_set_extraction, 0.0, 1.0, T.CARD_POOL_EXTRACT)
	_tween.tween_callback(func():
		if ticket == _generation: _extraction_finished())

func update_destination(destination: Rect2) -> void:
	_destination = destination
	if state in ["extracting", "extracted"]: _render_frame()

func _set_extraction(value: float) -> void:
	extract_progress = Motion.out(value)
	_render_frame()

func _extraction_finished() -> void:
	_tween = null
	state = "extracted"
	extracted.emit(result_id)

func finish_to(destination: Rect2) -> void:
	if state not in ["aligning", "aligned", "extracting", "extracted"]: return
	_kill_tween()
	_centering = false
	_centered = true
	_landing_progress = 1.0
	phase = _target_phase
	_destination = destination
	extract_progress = 1.0
	state = "extracted"
	_render_frame()
	extracted.emit(result_id)

func focus_rect() -> Rect2:
	var width := minf(184, size.x * 0.25)
	return Rect2(Vector2(size.x * 0.5, size.y * 0.53) - Vector2(width, width / _aspect) * 0.5, Vector2(width, width / _aspect))

func result_rect() -> Rect2:
	if _target_index < 0: return Rect2()
	var slot := slots[_target_index]
	return Rect2(slot.position + slot.pivot_offset - slot.size * slot.scale * 0.5, slot.size * slot.scale)

func _render_frame() -> void:
	if slots.is_empty() or size.x <= 0: return
	var center := Vector2(size.x * 0.5, size.y * 0.53)
	var base := focus_rect().size
	var half := cards.size() * 0.5
	# Equal arc-length spacing, with tangent-aligned cards. Position and angle
	# come from the same circle instead of independent height/tilt curves.
	var spacing := minf(T.CARD_POOL_SPACING, size.x / 10.0)
	var radius := T.CARD_POOL_ARC_RADIUS
	var spreading := entry_progress < 1.0
	var entry_time := entry_progress * T.CARD_POOL_ENTER
	var appear := Motion.out(entry_time / T.CARD_POOL_STACK_APPEAR) if spreading else 1.0
	var unfold := Motion.curve((entry_time - T.CARD_POOL_STACK_APPEAR) / maxf(0.001, T.CARD_POOL_ENTER - T.CARD_POOL_STACK_APPEAR), Vector2(0.32, 0.0), Vector2(0.22, 1.0)) if spreading else 1.0
	var left := -floorf(half)
	var leading_distance := lerpf(left, left + cards.size() - 1.0, unfold)
	var nearest := INF
	for i in slots.size():
		var distance := wrapf(float(i) - phase, -half, half)
		if absf(distance) < nearest:
			nearest = absf(distance)
			focal_index = i
	for i in slots.size():
		var slot := slots[i]
		var distance := wrapf(float(i) - phase, -half, half)
		var normalized := distance / maxf(1.0, half)
		var depth := absf(normalized)
		# Unlaid cards remain together in a small traveling pile. As it crosses
		# each final slot, that card stays behind on the same circular arc.
		var pose_distance := minf(distance, leading_distance) if spreading else distance
		var pile_depth := maxf(0.0, distance - leading_distance) if spreading else 0.0
		var theta := pose_distance * spacing / radius
		var pose_depth := absf(pose_distance / maxf(1.0, half))
		var scale_value := 1.0 - 0.035 * pose_depth * pose_depth
		var point := center + Vector2(radius * sin(theta), radius * (1.0 - cos(theta)))
		point += Vector2(1.8, 0.9) * pile_depth
		if i == _press_index: scale_value *= press_scale
		if not _motion.reduced():
			point.y -= 8 * _hover_lifts[i]
			scale_value *= 1.0 + 0.025 * _hover_lifts[i]
		var alpha := lerpf(1.0, 0.92, depth) * appear
		# Edge fade spans 0.60 card positions; elapsed time follows the flow speed.
		alpha *= 1.0 - smoothstep(half - 0.60, half, absf(distance))
		var rotation_value := theta
		var yaw := -theta * 0.20
		var blur := depth * 0.20
		var tint := Color.WHITE.lerp(Color("#C9D6EC"), depth * 0.07)
		if i == _target_index and state in ["extracting", "extracted", "exiting"] and extract_progress > 0:
			point = point.lerp(_destination.get_center(), extract_progress)
			scale_value = lerpf(scale_value, _destination.size.x / maxf(1.0, base.x), extract_progress)
			rotation_value *= 1.0 - extract_progress
			yaw *= 1.0 - extract_progress
			blur *= 1.0 - extract_progress
			alpha = 1.0
			tint = Color.WHITE
		elif extract_progress > 0:
			alpha *= 1.0 - extract_progress
			point.y += 10 * extract_progress
			scale_value *= 1.0 - 0.03 * extract_progress
		slot.size = base
		slot.pivot_offset = base * 0.5
		slot.position = point - base * 0.5
		slot.scale = Vector2.ONE * scale_value
		slot.rotation = rotation_value
		slot.modulate = Color(tint, alpha)
		slot.z_index = 200 if i == _target_index and extract_progress > 0 else 150 if i == focal_index else int((1-depth) * 100)
		slot.material.set_shader_parameter("card_size", base)
		slot.material.set_shader_parameter("yaw", yaw)
		slot.material.set_shader_parameter("depth_blur", blur)
	queue_redraw()

func _draw() -> void:
	if state in ["empty", "loading", "error"]: return
	var center := focus_rect().get_center() + Vector2(0, focus_rect().size.y * 0.57)
	var strength := entry_progress * (1.0 - extract_progress * 0.75)
	for ring in 3:
		var points := PackedVector2Array()
		for i in 97:
			var a := TAU * i / 96.0
			points.append(center + Vector2(cos(a) * (275 + ring * 12), sin(a) * (30 + ring * 3)))
		draw_polyline(points, Color(0.34, 0.53, 0.83, strength * (0.12 - ring * 0.03)), 1.0, true)

func _preference_changed() -> void:
	if not _motion.reduced():
		_update_processing()
		return
	if state == "entering":
		_kill_tween(); _set_entry(1.0); _entry_finished()
	elif _centering:
		_kill_tween(); _set_landing(1.0); _landing_finished()
	elif state == "extracting":
		_kill_tween(); _set_extraction(1.0); _extraction_finished()
	elif state in ["flowing", "requesting"]:
		phase = roundf(phase)
		_render_frame()
	_update_processing()

func freeze() -> void:
	set_selection_enabled(false)
	_centering = false
	_generation += 1
	_kill_tween()
	_motion.cancel(self, false)
	state = "exiting"
	set_process(false)

func _fail(message: String) -> void:
	state = "error"
	set_process(false)
	failed.emit(message)

func _kill_tween() -> void:
	if _tween != null:
		if is_instance_valid(_motion): _tween.bind_node(_motion)
		_tween.kill()
		_tween = null

func _exit_tree() -> void:
	_generation += 1
	_kill_tween()
	set_process(false)
