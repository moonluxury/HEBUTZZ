extends RefCounted
## Import old files once. Retired spirit records are archived, never updated.
const ARCHIVED_SPIRIT_PATH := "user://spirit_progress.json"

static func migrate(subjects: Dictionary) -> void:
	if not OS.has_feature("pc"):
		return
	var legacy_dir := OS.get_user_data_dir().get_base_dir().path_join("答题系统")
	var paths: Array[String] = [ARCHIVED_SPIRIT_PATH]
	for subject in subjects.values():
		paths.append(str(subject.wrong_path))
	for path in paths:
		if FileAccess.file_exists(path):
			continue
		var legacy_path := legacy_dir.path_join(path.get_file())
		if not FileAccess.file_exists(legacy_path):
			continue
		var issue := DirAccess.copy_absolute(legacy_path, ProjectSettings.globalize_path(path))
		if issue != OK:
			push_warning("学习记录迁移失败：%s（%s）" % [path.get_file(), error_string(issue)])
