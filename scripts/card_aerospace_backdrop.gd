extends Control
## A quiet light PC stage: Earth horizon, sparse stars and native technical lines.
## Background only. Its opacity inherits the modal shade's exit animation.
const T = preload("res://scripts/ui_tokens.gd")
const Horizon = preload("res://assets/collection/stage/earth_horizon.webp")
var dark := false
var progress := 0.0
var earth: TextureRect
var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	earth = TextureRect.new()
	earth.texture = Horizon
	earth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	earth.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	earth.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	earth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	earth.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(earth)
	# Native line art is drawn after the base image, never on the card PNGs.
	move_child(earth, 0)
	var line_layer := Control.new()
	line_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line_layer)
	line_layer.draw.connect(_draw_lines.bind(line_layer))
	resized.connect(func(): line_layer.queue_redraw())
	set_meta("line_layer", line_layer)
	get_node("/root/UiMotion").preference_changed.connect(_preference_changed)
	set_palette(dark)
	_set_progress(0)

func set_palette(value: bool) -> void:
	dark = value
	if is_instance_valid(earth):
		earth.self_modulate = Color(0.20, 0.29, 0.47) if dark else Color.WHITE
		_set_progress(progress)

func present() -> void:
	freeze()
	if get_node("/root/UiMotion").reduced():
		_set_progress(1)
		return
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_progress, 0.0, 1.0, T.CARD_STAGE_ENTER)

func _set_progress(value: float) -> void:
	progress = value
	if is_instance_valid(earth): earth.modulate.a = value * 0.96
	if has_meta("line_layer"): get_meta("line_layer").queue_redraw()

func _draw_lines(layer: Control) -> void:
	if progress <= 0 or size.x < 1: return
	var blue := Color("#9CBCEB") if dark else Color("#5179B5")
	var factor := minf(size.x / 1600.0, size.y / 950.0)
	var center := size * Vector2(0.50, 0.75)
	var expansion := lerpf(0.96, 1.0, progress)
	for ring in 2:
		var points := PackedVector2Array()
		for i in 101:
			var a := lerpf(PI * 1.02, PI * 1.94, i / 100.0)
			points.append(center + Vector2(cos(a) * size.x * (0.52 + ring * 0.04), sin(a) * size.y * 0.23).rotated(-0.10) * expansion)
		layer.draw_polyline(points, Color(blue, progress * (0.10 - ring * 0.025)), maxf(0.75, factor), true)
	for i in 19:
		var x := fposmod(i * 0.6180339 + 0.03, 1.0)
		var y := 0.11 + fposmod(i * 0.381966, 0.48)
		if x > 0.28 and x < 0.72: continue
		layer.draw_circle(Vector2(x, y) * size, (1.0 + i % 3 * 0.3) * factor, Color(blue, progress * 0.16))
	_satellite(layer, size * Vector2(0.85, 0.20), factor * 0.85, -0.24, Color(blue, progress * 0.14))
	_satellite(layer, size * Vector2(0.14, 0.25), factor * 0.56, 0.25, Color(blue, progress * 0.075))

func _satellite(layer: Control, at: Vector2, factor: float, angle: float, ink: Color) -> void:
	layer.draw_set_transform(at, angle, Vector2.ONE * factor)
	layer.draw_rect(Rect2(-13, -18, 26, 36), ink, false, 1.3)
	layer.draw_line(Vector2(-21, 0), Vector2(21, 0), ink, 1.3, true)
	for side in [-1, 1]:
		var left := 21.0 if side > 0 else -75.0
		layer.draw_rect(Rect2(left, -21, 54, 42), Color(ink, ink.a * 0.26))
		layer.draw_rect(Rect2(left, -21, 54, 42), ink, false, 1.2)
		for col in range(1, 4): layer.draw_line(Vector2(left + 13.5 * col, -21), Vector2(left + 13.5 * col, 21), ink, 0.8, true)
		layer.draw_line(Vector2(left, 0), Vector2(left + 54, 0), ink, 0.8, true)
	layer.draw_line(Vector2(0, -18), Vector2(0, -36), ink, 1.2, true)
	layer.draw_arc(Vector2(0, -38), 12, 0, PI, 24, ink, 1.3, true)
	layer.draw_set_transform(Vector2.ZERO)

func _preference_changed() -> void:
	if get_node("/root/UiMotion").reduced():
		freeze()
		_set_progress(1)

func freeze() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null

func _exit_tree() -> void:
	freeze()
