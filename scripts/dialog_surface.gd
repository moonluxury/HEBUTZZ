extends CanvasLayer
## Prepare straight-alpha pixels for Godot's embedded Window composition.
const SurfaceShader = preload("res://shaders/dialog_surface.gdshader")
const TransparentFill = preload("res://shaders/dialog_transparent_fill.gdshader")
var panel: PanelContainer
var surface_material: ShaderMaterial
var fill_material: ShaderMaterial
var _composition_queued := false
var _correcting_scale := false

func _init() -> void:
	name = "DialogSurface"
	layer = -1000
	surface_material = ShaderMaterial.new()
	surface_material.shader = SurfaceShader
	fill_material = ShaderMaterial.new()
	fill_material.shader = TransparentFill
	var fill := ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.material = fill_material
	add_child(fill)
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Include fractional viewport bounds at non-integer display scales.
	fill.offset_left = -2
	fill.offset_top = -2
	fill.offset_right = 2
	fill.offset_bottom = 2

func _ready() -> void:
	(get_parent() as Window).visibility_changed.connect(_update_embedding)
	(get_parent() as Window).size_changed.connect(_schedule_composition_sync)
	_update_embedding()

func configure(content: PanelContainer, color: Color) -> void:
	panel = content
	fill_material.set_shader_parameter("surface_color", color)
	_update_embedding()

func _update_embedding() -> void:
	# Native window compositors already expect premultiplied pixels.
	visible = (get_parent() as Window).is_embedded()
	if is_instance_valid(panel):
		panel.material = surface_material if visible else null
	_schedule_composition_sync()

func _schedule_composition_sync() -> void:
	if _composition_queued or _correcting_scale or not is_inside_tree(): return
	_composition_queued = true
	_sync_composition.call_deferred()

func _covers_window(window: Window) -> bool:
	return window.get_stretch_transform() * window.get_visible_rect() == Rect2(Vector2.ZERO, Vector2(window.size))

func _sync_composition() -> void:
	_composition_queued = false
	var window := get_parent() as Window
	if not window.visible or not window.is_embedded() or window.content_scale_size != Vector2i.ZERO or _covers_window(window): return
	# Godot 4.6 compares the scaled viewport rect with Window.size exactly and
	# draws an opaque black letterbox rectangle on any mismatch. A ~0.0001px
	# float rounding error can therefore show through otherwise transparent
	# corners after resizing. Use the nearest float32 scale that round-trips
	# exactly, preserving the window size, layout, input mapping and sharp text.
	var original := window.content_scale_factor
	var encoded := PackedFloat32Array([original]).to_byte_array()
	var bits := encoded.decode_u32(0)
	_correcting_scale = true
	for step in range(1, 33):
		for direction in [-1, 1]:
			encoded.encode_u32(0, bits + step * direction)
			window.content_scale_factor = encoded.decode_float(0)
			if _covers_window(window):
				_correcting_scale = false
				return
	window.content_scale_factor = original
	_correcting_scale = false
