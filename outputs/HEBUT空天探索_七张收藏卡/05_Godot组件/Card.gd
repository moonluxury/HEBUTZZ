@tool
extends Control
## Reusable layered 2:3 card. Artwork and frame are TextureRects; all text is editable.

var _default_chinese_fonts: Dictionary = {}
var _back_component: Control

## Toggle the same shared back for all seven card faces.
@export var show_back: bool = false:
	set(value):
		show_back = value
		if is_node_ready():
			_refresh_side()

@export_range(0, 6, 1) var card_index: int = 0:
	set(value):
		card_index = clampi(value, 0, 6)
		_refresh_if_ready()
@export var title_override: String = "":
	set(value):
		title_override = value
		_refresh_if_ready()
@export var english_override: String = "":
	set(value):
		english_override = value
		_refresh_if_ready()
@export var illustration_override: Texture2D:
	set(value):
		illustration_override = value
		_refresh_if_ready()
## Use the supplied PNG lettering if the target platform has no suitable CJK font.
@export var use_raster_text: bool = false:
	set(value):
		use_raster_text = value
		_refresh_if_ready()
## Optional project-owned font for live Chinese labels. No system font is redistributed.
@export var chinese_font_override: Font:
	set(value):
		chinese_font_override = value
		_refresh_if_ready()

func _ready() -> void:
	for label_name in ["Series", "Title"]:
		_default_chinese_fonts[label_name] = get_node("Design/" + label_name).get_theme_font("font")
	var back_path := (get_script() as Script).resource_path.get_base_dir().path_join("CardBack.tscn")
	_back_component = (load(back_path) as PackedScene).instantiate() as Control
	_back_component.name = "Back"
	# The parent already owns its minimum size; allow the back to follow any resize.
	_back_component.custom_minimum_size = Vector2.ZERO
	add_child(_back_component)
	_back_component.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout_card)
	_apply_card()
	_layout_card()

func _refresh_if_ready() -> void:
	if is_node_ready():
		_apply_card()

func _pack_root() -> String:
	return (get_script() as Script).resource_path.get_base_dir().get_base_dir()

func _apply_card() -> void:
	var pack_root := _pack_root()
	var data_path := pack_root.path_join("06_制作源文件/cards.json")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if not data is Array or data.size() != 7:
		push_error("HEBUT card metadata must contain exactly seven cards.")
		return
	var item: Dictionary = data[card_index]
	var stem := "%s_%s" % [item["id"], item["slug"]]
	var artwork: Texture2D = illustration_override
	if artwork == null:
		artwork = load(pack_root.path_join("02_插画/%s.png" % stem)) as Texture2D
	$Design/Illustration.texture = artwork
	$Design/Title.text = title_override if not title_override.is_empty() else str(item["name"])
	$Design/English.text = english_override if not english_override.is_empty() else str(item["english"])
	$Design/Number.text = str(item["id"])
	$Design/RasterText.texture = load(pack_root.path_join("04_独立文字层/%s_text.png" % stem)) as Texture2D
	$Design/RasterText.visible = use_raster_text
	for label_name in ["Brand", "Series", "Number", "Title", "English"]:
		get_node("Design/" + label_name).visible = not use_raster_text
	for label_name in ["Series", "Title"]:
		var label := get_node("Design/" + label_name) as Label
		if chinese_font_override != null:
			label.add_theme_font_override("font", chinese_font_override)
		else:
			label.add_theme_font_override("font", _default_chinese_fonts[label_name])
	_refresh_side()

func _refresh_side() -> void:
	$Design.visible = not show_back
	if is_instance_valid(_back_component):
		_back_component.visible = show_back
		_back_component.set("use_raster_text", use_raster_text)
		_back_component.set("chinese_font_override", chinese_font_override)

func _layout_card() -> void:
	if not is_node_ready():
		return
	var fit := minf(size.x / 1024.0, size.y / 1536.0)
	$Design.scale = Vector2.ONE * fit
	$Design.position = (size - Vector2(1024, 1536) * fit) * 0.5
