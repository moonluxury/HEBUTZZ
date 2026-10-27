@tool
extends Control
## Shared card back. Text stays editable and PNG lettering is available as fallback.

var _default_series_font: Font

@export var brand_text: String = "HEBUT":
	set(value):
		brand_text = value
		_refresh_if_ready()
@export var series_text: String = "空天探索系列":
	set(value):
		series_text = value
		_refresh_if_ready()
@export var use_raster_text: bool = false:
	set(value):
		use_raster_text = value
		_refresh_if_ready()
@export var chinese_font_override: Font:
	set(value):
		chinese_font_override = value
		_refresh_if_ready()

func _ready() -> void:
	_default_series_font = $Design/Series.get_theme_font("font")
	resized.connect(_layout_card)
	_refresh()
	_layout_card()

func _refresh_if_ready() -> void:
	if is_node_ready():
		_refresh()

func _refresh() -> void:
	$Design/Brand.text = brand_text
	$Design/Series.text = series_text
	$Design/Brand.visible = not use_raster_text
	$Design/Series.visible = not use_raster_text
	$Design/RasterText.visible = use_raster_text
	$Design/Series.add_theme_font_override("font", chinese_font_override if chinese_font_override != null else _default_series_font)

func _layout_card() -> void:
	if not is_node_ready():
		return
	var fit := minf(size.x / 1024.0, size.y / 1536.0)
	$Design.scale = Vector2.ONE * fit
	$Design.position = (size - Vector2(1024, 1536) * fit) * 0.5
