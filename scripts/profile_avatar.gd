extends TextureRect
const DEFAULT = preload("res://assets/profile/default-avatar.svg")
const MASK = preload("res://shaders/profile_avatar.gdshader")
static var card_paths: Dictionary = {}
var source_path := ""
var subject_id := ""
var bound_card_id := ""

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	# Native dialogs have their own canvas: do not rely on the page's filter.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = DEFAULT
	var mask := ShaderMaterial.new()
	mask.shader = MASK
	material = mask

func _ready() -> void:
	var profile := get_node_or_null("/root/ProfileStore")
	if profile != null: profile.changed.connect(_refresh_own_avatar)
	_refresh_own_avatar()

func _enter_tree() -> void:
	if is_node_ready(): _refresh_own_avatar.call_deferred()

static func path_for_card(card_id: String) -> String:
	if card_paths.is_empty():
		var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/collection_catalog.json"))
		if catalog is Dictionary:
			for card in catalog.get("cards", []):
				card_paths[str(card.id)] = str(card.get("artwork", card.get("image", "")))
	return str(card_paths.get(card_id, ""))

func show_profile(profile: Dictionary) -> void:
	subject_id = str(profile.get("id", ""))
	bound_card_id = str(profile.get("avatar_card_id", ""))
	show_card(bound_card_id)
	if is_inside_tree(): _refresh_own_avatar()

func _refresh_own_avatar() -> void:
	if subject_id.is_empty() or not is_inside_tree(): return
	var profile := get_node_or_null("/root/ProfileStore")
	if profile != null and profile.authenticated() and profile.account_id == subject_id:
		show_card(str(profile.profile.get("avatar_card_id", "")))
	else:
		show_card(bound_card_id)

func show_card(card_id: String) -> void:
	var path := path_for_card(card_id)
	if path == source_path:
		return
	source_path = path
	texture = DEFAULT
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var resource := load(path)
		if resource is Texture2D:
			texture = resource

func set_unavailable(value: bool) -> void:
	material.set_shader_parameter("grayscale", 1.0 if value else 0.0)
	self_modulate = Color(1, 1, 1, 0.45 if value else 1.0)
