extends Node
## Owns wrong-question persistence; pages only supply course and stable IDs.
signal changed(subject: String)
const Collection = preload("res://scripts/manual_question_collection.gd")
const JsonStore = preload("res://scripts/local_json_store.gd")

func ids(subject: String) -> Dictionary:
	var path := _path(subject)
	return Collection.ids(JsonStore.read(path, [])) if not path.is_empty() else {}


func questions(subject: String, bank: Array) -> Array:
	return Collection.questions(bank, ids(subject))


func save_ids(subject: String, values: Dictionary) -> bool:
	var path := _path(subject)
	if path.is_empty():
		return false
	var saved := Collection.serialized(values)
	if JsonStore.write(path, saved) != OK:
		return false
	changed.emit(subject)
	return true

func _path(subject: String) -> String:
	return str(get_node("/root/AppState").SUBJECTS.get(subject, {}).get("wrong_path", ""))
