extends Node
## Owns wrong-question persistence; pages only supply course and stable IDs.
signal changed(subject: String)
const JsonStore = preload("res://scripts/local_json_store.gd")

func ids(subject: String) -> Dictionary:
	var result: Dictionary = {}
	var path := _path(subject)
	if path.is_empty():
		return result
	var saved = JsonStore.read(path, [])
	if saved is Array:
		for id in saved:
			result[str(id)] = true
	return result

func questions(subject: String, bank: Array) -> Array:
	var saved := ids(subject)
	return bank.filter(func(question: Dictionary): return saved.has(str(question.id)))

func save_ids(subject: String, values: Dictionary) -> bool:
	var path := _path(subject)
	if path.is_empty():
		return false
	var saved: Array[int] = []
	for id in values:
		saved.append(int(id))
	saved.sort()
	if JsonStore.write(path, saved) != OK:
		return false
	changed.emit(subject)
	return true

func _path(subject: String) -> String:
	return str(get_node("/root/AppState").SUBJECTS.get(subject, {}).get("wrong_path", ""))
