extends Control

var grid: GridContainer
var card_nodes: Array[Control] = []

func _ready() -> void:
	var face := SystemFont.new()
	face.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var gallery_theme := Theme.new()
	gallery_theme.default_font = face
	theme = gallery_theme
	var bg := ColorRect.new()
	bg.color = Color("e8eef2")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	var title := Label.new()
	title.text = "HEBUT空天探索系列"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("244d70"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "七张原创收藏卡 · 一张共用卡背"
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color("627d91"))
	column.add_child(subtitle)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 24)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(grid)
	var local_dir := (get_script() as Script).resource_path.get_base_dir()
	var card_scene := load(local_dir.path_join("Card.tscn")) as PackedScene
	for index in range(7):
		var card := card_scene.instantiate() as Control
		card.set("card_index", index)
		grid.add_child(card)
		card_nodes.append(card)
	var back_scene := load(local_dir.path_join("CardBack.tscn")) as PackedScene
	var card_back := back_scene.instantiate() as Control
	grid.add_child(card_back)
	card_nodes.append(card_back)
	resized.connect(_update_columns)
	_update_columns()

func _update_columns() -> void:
	if grid == null:
		return
	var available := maxf(220.0, size.x - 92.0)
	grid.columns = clampi(int((available + 22.0) / 282.0), 1, 4)
	var card_width := minf(300.0, (available - (grid.columns - 1) * 22.0) / grid.columns)
	for card in card_nodes:
		card.custom_minimum_size = Vector2(card_width, card_width * 1.5)
