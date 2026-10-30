extends "res://tools/check_submissions.gd"
## Interactive native-input check. Only the loopback test account is used.
func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1450, 900)
	root.content_scale_size = root.size
	root.position = Vector2i(60, 45)
	root.title = "河工开物 · 投稿输入验证（隔离账号）"
	session = JSON.parse_string(FileAccess.get_file_as_string("res://.godot_appdata/submission-check-session.json"))
	var api := Provider.new()
	api.base_url = "http://127.0.0.1:8059"
	root.add_child(api)
	api.access_token = session.access_token
	api.account_id = session.account_id
	var profile := root.get_node("ProfileStore")
	profile.use_provider(api, {"state":"authenticated","account_id":api.account_id})
	await until(func(): return not profile.loading)
	store = root.get_node("AppServices").submission_store()
	store.new_draft()
	var data: Dictionary = store.current.data.duplicate(true)
	data.title = "输入兼容性验证"
	data.category_id = "course"
	data.document = {"type":"doc","content":[{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"中文输入与剪贴板"}]},{"type":"paragraph","content":[{"type":"text","text":"在这里验证真实键盘输入。"}]}]}
	store.update(data)
	store.view = "writer"
	root.get_node("PageRouter").go("res://scenes/Submissions.tscn", "writer")
	await scene_changed
	if not await attach_page(): quit(1); return
	print("VISIBLE SUBMISSION CHECK READY")
	var timer := Timer.new()
	timer.wait_time = 2
	timer.timeout.connect(func():
		var file := FileAccess.open(output.path_join("native-input-state.json"), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify({"data":store.current.get("data",{}),"dirty":store.dirty,"status":store.status})))
	root.add_child(timer)
	timer.start()
