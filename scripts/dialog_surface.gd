extends CanvasLayer
## Prepare straight-alpha pixels for Godot's embedded Window composition.
const SurfaceShader = preload("res://shaders/dialog_surface.gdshader")
const TransparentFill = preload("res://shaders/dialog_transparent_fill.gdshader")
var panel: PanelContainer
var surface_material: ShaderMaterial
var fill_material: ShaderMaterial

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
