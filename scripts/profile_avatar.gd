extends TextureRect
const DEFAULT = preload("res://assets/profile/default-avatar.svg")
const MASK = preload("res://shaders/profile_avatar.gdshader")
var source_path := ""

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = DEFAULT
	var mask := ShaderMaterial.new()
	mask.shader = MASK
	material = mask

func show_avatar(path: String) -> void:
	if path == source_path and (path.is_empty() or path.begins_with("res://")):
		return
	source_path = path
	texture = DEFAULT
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			texture = resource
	elif not path.is_empty() and FileAccess.file_exists(path):
		var picture := Image.load_from_file(path)
		if picture != null and not picture.is_empty():
			texture = ImageTexture.create_from_image(picture)
