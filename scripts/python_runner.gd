extends Node

signal output_changed(text: String)
signal finished(message: String)

const ARCHIVE := "res://runtime/python/python-3.13.16-embed-amd64.zip"
const ARCHIVE_HASH := "97dae5274cc54867065e8d5a3226e48c35017ed332a0fdb0e27d5b5821961297"
const CACHE := "user://python_runtime/3.13.16-amd64"
const RUNS := "user://python_runs"
const OUTPUT_LIMIT := 262144
var time_limit_seconds := 10.0
var pid := -1
var directory := ""
var started := 0
var poll_elapsed := 0.0
var last_output := ""


func supported() -> bool:
	return OS.get_name() == "Windows" and Engine.get_architecture_name() == "x86_64"

func prepare_runtime() -> String:
	return _prepare_runtime() if supported() else ""


func is_running() -> bool:
	return pid > 0


func run_code(code: String, input_text: String) -> void:
	if is_running():
		return
	if not supported():
		finished.emit("当前平台尚未提供 Python 运行环境。")
		return
	if code.strip_edges().is_empty():
		finished.emit("请先编写代码。")
		return
	var executable := _prepare_runtime()
	if executable.is_empty():
		finished.emit("Python 环境准备失败，请检查安装包和磁盘空间。")
		return
	directory = ProjectSettings.globalize_path(RUNS.path_join("%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]))
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		finished.emit("无法创建运行目录。")
		return
	var worker := FileAccess.get_file_as_string("res://scripts/python_worker.py")
	if worker.is_empty() or not _write("runner.py", worker) or not _write("main.py", code) or not _write("stdin.txt", input_text + ("\n" if not input_text.is_empty() and not input_text.ends_with("\n") else "")):
		finished.emit("无法保存本次运行文件。")
		return
	last_output = ""
	output_changed.emit("")
	started = Time.get_ticks_msec()
	pid = OS.create_process(executable, PackedStringArray(["-I", "-S", "-u", "-X", "utf8", directory.path_join("runner.py"), directory]), false)
	if pid <= 0:
		pid = -1
		finished.emit("Python 启动失败。")
		return
	poll_elapsed = 0.0
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	poll_elapsed += delta
	if poll_elapsed < 0.1:
		return
	poll_elapsed = 0.0
	var too_much := _read_output()
	if too_much:
		stop("输出超过 256 KB，已停止运行。")
	elif Time.get_ticks_msec() - started > time_limit_seconds * 1000.0:
		stop("运行超过 %.1f 秒，已停止。请检查循环条件。" % time_limit_seconds)
	elif not OS.is_process_running(pid):
		var result_path := directory.path_join("result.json")
		var result = JSON.parse_string(FileAccess.get_file_as_string(result_path)) if FileAccess.file_exists(result_path) else null
		_read_output()
		pid = -1
		set_process(false)
		if result is Dictionary:
			var exit_code := int(result.get("exit_code", 1))
			finished.emit("运行完成（%.2f 秒）" % ((Time.get_ticks_msec() - started) / 1000.0) if exit_code == 0 else "程序出错（退出码 %d）" % exit_code)
		else:
			finished.emit("程序提前退出，未返回运行状态。")


func _read_output() -> bool:
	var path := directory.path_join("output.txt")
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var size := file.get_length()
	var bytes := file.get_buffer(mini(size, OUTPUT_LIMIT))
	# A byte limit can cut through a Chinese character. Keep the complete prefix.
	var lead := bytes.size() - 1
	while lead >= 0 and (bytes[lead] & 0xC0) == 0x80:
		lead -= 1
	if lead >= 0:
		var first := int(bytes[lead])
		var width := 1 if first < 0x80 else (2 if first < 0xE0 else (3 if first < 0xF0 else 4))
		if bytes.size() - lead < width:
			bytes.resize(lead)
	var text := bytes.get_string_from_utf8()
	if text != last_output:
		last_output = text
		output_changed.emit(text)
	return size > OUTPUT_LIMIT


func stop(message: String = "已停止运行。") -> void:
	if pid > 0:
		if OS.is_process_running(pid):
			OS.kill(pid)
		_read_output()
		pid = -1
		set_process(false)
		finished.emit(message)


func _exit_tree() -> void:
	stop()


func _write(filename: String, content: String) -> bool:
	var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	return file.get_error() == OK


func _prepare_runtime() -> String:
	var target := ProjectSettings.globalize_path(CACHE)
	var executable := target.path_join("python.exe")
	var stamp := target.path_join("archive.sha256")
	if FileAccess.file_exists(executable) and FileAccess.file_exists(stamp) and FileAccess.get_file_as_string(stamp) == ARCHIVE_HASH:
		return executable
	if not FileAccess.file_exists(ARCHIVE) or FileAccess.get_sha256(ARCHIVE) != ARCHIVE_HASH:
		return ""
	var archive := ZIPReader.new()
	if archive.open(ARCHIVE) != OK or DirAccess.make_dir_recursive_absolute(target) != OK:
		return ""
	for name in archive.get_files():
		# The official embed archive is flat. Do not extract unexpected paths.
		if name.get_file() != name:
			archive.close()
			return ""
		var file := FileAccess.open(target.path_join(name), FileAccess.WRITE)
		if file == null:
			archive.close()
			return ""
		file.store_buffer(archive.read_file(name))
		if file.get_error() != OK:
			archive.close()
			return ""
	archive.close()
	var marker := FileAccess.open(stamp, FileAccess.WRITE)
	if marker == null:
		return ""
	marker.store_string(ARCHIVE_HASH)
	return executable
