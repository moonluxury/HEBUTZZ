extends RefCounted
## One disk boundary for local JSON. Failed writes never truncate the prior save.

static func read(path: String, fallback: Variant = null) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback
	var parser := JSON.new()
	return parser.data if parser.parse(file.get_as_text()) == OK else fallback

static func write(path: String, value: Variant) -> Error:
	var directory := path.get_base_dir()
	var issue := DirAccess.make_dir_recursive_absolute(directory)
	if issue != OK:
		return issue
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  "))
	file.flush()
	issue = file.get_error()
	file.close()
	if issue == OK:
		issue = DirAccess.rename_absolute(temp, path)
	if issue != OK and FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
	return issue
