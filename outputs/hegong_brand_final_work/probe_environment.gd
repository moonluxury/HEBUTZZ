extends SceneTree

func _initialize() -> void:
	print("JAVA_HOME: ", OS.get_environment("JAVA_HOME"))
	print("JBR BIN EXISTS: ", DirAccess.dir_exists_absolute("F:/IntelliJ IDEA 2025.3.3/jbr/bin"))
	var first = DirAccess.open("F:/IntelliJ IDEA 2025.3.3/jbr/bin")
	print("JBR BIN OPEN: ", first != null, " error: ", DirAccess.get_open_error())
	var second = DirAccess.open("F:/bin")
	print("JDK BIN OPEN: ", second != null, " error: ", DirAccess.get_open_error())
	if Engine.is_editor_hint():
		var settings = EditorInterface.get_editor_settings()
		print("EDITOR JDK: ", settings.get_setting("export/android/java_sdk_path"))
		print("EDITOR SDK: ", settings.get_setting("export/android/android_sdk_path"))
	quit()
