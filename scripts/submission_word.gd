extends Node
const Runner = preload("res://scripts/python_runner.gd")
const JsonStore = preload("res://scripts/local_json_store.gd")
var pid := -1

func _run(request: Dictionary) -> Dictionary:
	if pid > 0: return {"ok":false,"message":"已有 Word 转换正在进行。"}
	var runtime := Runner.new()
	add_child(runtime)
	var executable: String = runtime.prepare_runtime()
	runtime.queue_free()
	if executable.is_empty(): return {"ok":false,"message":"Word 转换组件暂不可用。"}
	var directory := "user://submission-word/" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	request.work = ProjectSettings.globalize_path(directory)
	var source := FileAccess.get_file_as_string("res://scripts/submission_docx.py")
	var worker := FileAccess.open(directory.path_join("worker.py"), FileAccess.WRITE)
	if worker == null: return {"ok":false,"message":"无法创建 Word 转换文件。"}
	worker.store_string(source); worker.close()
	JsonStore.write(directory.path_join("request.json"), request)
	pid = OS.create_process(executable, PackedStringArray(["-I","-S","-X","utf8",ProjectSettings.globalize_path(directory.path_join("worker.py")),ProjectSettings.globalize_path(directory.path_join("request.json"))]), false)
	if pid <= 0: return {"ok":false,"message":"Word 转换无法启动。"}
	var deadline := Time.get_ticks_msec() + 30000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline: await get_tree().create_timer(0.1).timeout
	if OS.is_process_running(pid): OS.kill(pid)
	pid = -1
	var result: Variant = JsonStore.read(directory.path_join("result.json"))
	return result if result is Dictionary else {"ok":false,"message":"Word 转换未完成，原稿件未改变。"}

func import_file(path: String, store: Node) -> Dictionary:
	var epoch: int = store.epoch
	var result := await _run({"action":"import","path":path})
	if epoch != store.epoch: return {"ok":false,"message":"账号已切换，导入已取消。"}
	if not result.get("ok", false): return result
	var mapping: Dictionary = {}
	for asset in result.get("assets", []):
		var added: Dictionary = store.add_image(str(asset.path))
		if not added.get("ok", false): return added
		mapping[asset.id] = added.asset.id
	_remap(result.document, mapping)
	return result

func _remap(node: Dictionary, mapping: Dictionary) -> void:
	if node.get("type") == "image": node.attrs.asset_id = mapping.get(node.attrs.asset_id, "")
	for child in node.get("content", []): _remap(child, mapping)

func export_file(path: String, store: Node) -> Dictionary:
	if not path.to_lower().ends_with(".docx"): path += ".docx"
	var epoch: int = store.epoch
	var data: Dictionary = store.current.data.duplicate(true)
	var images: Dictionary = {}
	var work := "user://submission-word/images"
	DirAccess.make_dir_recursive_absolute(work)
	for id in store._references(data.document):
		var asset: Dictionary = await store.image_data(id)
		if epoch != store.epoch: return {"ok":false,"message":"账号已切换，导出已取消。"}
		if not asset.get("ok", false): return {"ok":false,"message":"有图片无法读取，请恢复图片后再导出。"}
		var bytes := Marshalls.base64_to_raw(asset.data)
		var extension := ".png" if asset.mime == "image/png" else ".jpg"
		if asset.mime == "image/webp":
			var image := Image.new()
			if image.load_webp_from_buffer(bytes) != OK: return {"ok":false,"message":"WebP 图片转换失败。"}
			bytes = image.save_png_to_buffer(); extension = ".png"
		var file_path := work.path_join(id + extension)
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if file == null: return {"ok":false,"message":"无法准备导出图片。"}
		file.store_buffer(bytes); file.close()
		images[id] = ProjectSettings.globalize_path(file_path)
	return await _run({"action":"export","path":path,"document":data.document,"title":data.title,"assets":images})

func _exit_tree() -> void:
	if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
