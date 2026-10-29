extends RefCounted
## Shared catalogue artwork presentation; independent of collection/friend pages.

static func create(parent: Node, card: Dictionary, rect := Rect2()) -> TextureRect:
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(picture)
	picture.position = rect.position
	picture.size = rect.size
	var path := str(card.get("artwork", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		picture.texture = parent.get_node("/root/UiResources").texture(path)
	return picture

static func ratio(picture: TextureRect) -> float:
	return picture.texture.get_height() / float(picture.texture.get_width()) if picture.texture != null else 1.5

static func season_title(season: Dictionary) -> String:
	return str(season.get("label", "")) + " · " + str(season.get("name", ""))
