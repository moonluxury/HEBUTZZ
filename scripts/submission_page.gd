extends "res://scripts/minimal_page.gd"
signal snapshot_received(ok: bool)
const Avatar = preload("res://scripts/profile_avatar.gd")
const Word = preload("res://scripts/submission_word.gd")
@export var public_mode := false
var store: Node
var browser: Control
var browser_ready := false
var word: Node
var fallback: Label
var _flush_ticket := ""
var _original_quit := true
var _closing := false
var _avatar_source := ""
var _avatar_data := ""
var _trusted_url := ""
var _caret := Vector2(-1, -1)

func _ready() -> void:
	active_nav = "KaiwuButton" if public_mode else "SubmissionButton"
	store = get_node("/root/AppServices").submission_store()
	store.changed.connect(_state_changed)
	word = Word.new()
	add_child(word)
	super._ready()
	_original_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	get_window().files_dropped.connect(_files_dropped)
	# Run after CefTexture's default process, which uses unzoomed IME bounds.
	process_priority = 100
	_ensure_browser.call_deferred()
	if not public_mode: store.activate(str(get_meta("entry_view", "mine")))
	else: store.refresh_public()

func _build_content() -> void:
	fallback = _label(body, "正在加载投稿编辑器…", 22, muted_color, Rect2(0, 20, 900, 150))
	fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_instance_valid(browser): _push_state("theme")

func _layout_content(_width: float) -> void:
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_height = scroll.size.y
	if is_instance_valid(browser):
		browser.position = scroll.global_position - global_position
		browser.size = scroll.size * canvas.scale
		if browser_ready: browser.call_deferred("eval", "window.hegong && window.hegong.measure();")

func _ensure_browser() -> void:
	if OS.get_name() != "Windows": fallback.text = "投稿写作目前支持 Windows 电脑版。"; return
	var runtime := ProjectSettings.globalize_path("res://addons/godot_cef/bin/x86_64-pc-windows-msvc-quiet")
	var exported := OS.get_executable_path().get_base_dir()
	var packaged := exported.path_join("addons/godot_cef/bin/x86_64-pc-windows-msvc-quiet")
	if FileAccess.file_exists(packaged.path_join("libcef.dll")): runtime = packaged
	elif FileAccess.file_exists(exported.path_join("libcef.dll")): runtime = exported
	elif not runtime.is_absolute_path(): runtime = exported.path_join(runtime)
	runtime = runtime.replace("\\", "/")
	if not FileAccess.file_exists(runtime.path_join("libcef.dll")):
		fallback.text = "编辑器组件缺失，请重新安装完整客户端。"; return
	# Keep disposable browser data separate from account-owned document recovery.
	var cache_root := OS.get_environment("LOCALAPPDATA")
	if cache_root.is_empty(): cache_root = OS.get_user_data_dir().get_base_dir()
	var support_directory := cache_root.path_join("HegongSubmission").replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(support_directory)
	# The packaged CEF runtime removes the vendor's forced enable-logging flag,
	# which makes Chromium allocate a console even when logging to a file.
	var cef_log := support_directory.path_join("cef-" + str(OS.get_process_id()) + ".log")
	ProjectSettings.set_setting("godot_cef/advanced/custom_command_line_switches", "resources-dir-path=" + runtime + "\nlocales-dir-path=" + runtime.path_join("locales") + "\nlog-file=" + cef_log)
	ProjectSettings.set_setting("godot_cef/storage/data_path", cache_root.path_join("HegongSubmission/BrowserCache").replace("\\", "/"))
	if not ClassDB.class_exists("CefTexture"): GDExtensionManager.load_extension("res://addons/godot_cef/godot_cef.gdextension")
	if not ClassDB.class_exists("CefTexture"): fallback.text = "编辑器组件无法启动。"; return
	browser = ClassDB.instantiate("CefTexture")
	browser.name = "SubmissionBrowser"
	browser.z_index = 5
	browser.set("enable_accelerated_osr", false)
	browser.set("permission_policy", 0)
	browser.set("dialog_policy", 2)
	var build: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://ui/submissions/dist/build.json"))
	_trusted_url = "res://ui/submissions/dist/index.html?v=" + str(build.get("version", "1") if build is Dictionary else "1")
	browser.set("url", _trusted_url)
	browser.connect("ipc_message", _message)
	browser.connect("url_changed", _guard_navigation)
	browser.connect("load_error", func(_url: String, _code: int, _text: String): fallback.text = "编辑器加载失败，请重新进入投稿。")
	add_child(browser)
	_layout()
	var startup_timer := Timer.new()
	startup_timer.one_shot = true
	startup_timer.wait_time = 15.0
	startup_timer.timeout.connect(func():
		if not browser_ready and is_instance_valid(browser):
			browser.hide()
			fallback.text = "投稿编辑器未能启动，请重新进入；若问题持续，请重新安装完整客户端。"
		startup_timer.queue_free())
	add_child(startup_timer)
	startup_timer.start()

func _state_changed(reason: String) -> void: _push_state(reason)

func _guard_navigation(url: String) -> void:
	if url != _trusted_url and url != "about:blank":
		browser_ready = false
		browser.call_deferred("load_url", _trusted_url)

func _push_state(reason := "status") -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not browser_ready or not is_instance_valid(browser): return
	var value: Dictionary = store.state()
	value.dark = dark
	value.reduced_motion = get_node("/root/UiMotion").reduced()
	value.testing = OS.get_user_data_dir().contains("workbench-check") and OS.get_environment("HEGONG_SUBMISSION_QA") == "1"
	value.public_items = store.public_items
	if not store.article.is_empty():
		var source: String = Avatar.path_for_card(str(store.article.get("author", {}).get("avatar_card_id", "")))
		if source != _avatar_source:
			_avatar_source = source
			var texture: Texture2D = load(source)
			if texture != null:
				var picture := texture.get_image()
				picture.resize(128, maxi(1, roundi(128.0 * picture.get_height() / picture.get_width())), Image.INTERPOLATE_LANCZOS)
				_avatar_data = "data:image/png;base64," + Marshalls.raw_to_base64(picture.save_png_to_buffer())
		value.author_avatar = _avatar_data
	_send({"kind":"state","reason":reason,"state":value})

func _send(value: Dictionary) -> void:
	if is_instance_valid(browser): browser.call("eval", "window.hegong && window.hegong.receive(" + JSON.stringify(value) + ");")

func _message(raw: String) -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	if raw.length() > 1100000: return
	if not is_instance_valid(browser) or str(browser.get("url")) != _trusted_url: return
	var message: Variant = JSON.parse_string(raw)
	if not message is Dictionary: return
	var method := str(message.get("method", ""))
	if method == "ready":
		browser_ready = true
		if OS.get_environment("HEGONG_SUBMISSION_DIAGNOSTICS") == "1": print("SUBMISSION EDITOR READY")
		_push_state("open"); return
	if int(message.get("epoch", -2)) != store.epoch: return
	var params: Dictionary = message.get("params", {}) if message.get("params") is Dictionary else {}
	var generation: int = store.epoch
	var result: Dictionary = {"ok":true}
	match method:
		"caret":
			_caret = Vector2(float(params.get("x", -1)), float(params.get("y", -1)))
		"metrics":
			# CEF applies Windows DPI independently of Godot's canvas scale.
			# Correct browser zoom so both surfaces share the same logical unit.
			var ratio := float(params.get("dpr", 1.0))
			var target := canvas.scale.x * get_viewport().get_stretch_transform().get_scale().x
			if ratio > 0.1 and absf(ratio - target) > 0.015:
				browser.call("set_zoom_level", float(browser.call("get_zoom_level")) + log(target / ratio) / log(1.2))
		"update":
			if params.get("key") != store.current.get("client_key"): return
			result = store.update(params.get("data", {}), params.get("ui", {}))
		"view": store.switch_view(str(params.get("view", "settings")))
		"new": store.new_draft()
		"save": result = await store.save()
		"submit": result = await store.submit()
		"transition": result = await store.transition(str(params.get("action", "")))
		"delete_draft": result = await store.delete_draft(str(params.get("id", "")), str(params.get("key", "")))
		"open_draft":
			result = await store.open_draft(str(params.get("id", "")), str(params.get("key", "")))
			if result.get("ok", false) and public_mode: get_node("/root/PageRouter").go("res://scenes/Submissions.tscn", store.view)
		"open_article":
			result = await store.open_article(str(params.get("id", "")))
			if result.get("ok", false) and not public_mode: get_node("/root/PageRouter").go("res://scenes/SubmissionArticle.tscn")
		"resource_back": get_node("/root/PageRouter").go("res://scenes/HegongKaiwu.tscn")
		"route_back": get_node("/root/PageRouter").go("res://scenes/HegongKaiwu.tscn" if public_mode else "res://scenes/Workbench.tscn")
		"revise_article":
			result = await store.open_draft(str(params.get("id", "")))
			if result.get("ok", false): result = await store.transition("submission_revise")
			if result.get("ok", false): get_node("/root/PageRouter").go("res://scenes/Submissions.tscn", store.view)
		"conflict": store.resolve_conflict(bool(params.get("use_local", false)))
		"asset": result = await store.image_data(str(params.get("id", "")))
		"choose_image":
			var path := await _choose_file(false, PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片"]))
			result = store.add_image(path) if not path.is_empty() and generation == store.epoch else {"ok":false}
		"paste_image":
			if DisplayServer.clipboard_has_image():
				var image := DisplayServer.clipboard_get_image()
				var path: String = store._directory().path_join("clipboard.png")
				DirAccess.make_dir_recursive_absolute(path.get_base_dir())
				if image != null and image.save_png(path) == OK: result = store.add_image(path)
				else: result = {"ok":false,"message":"剪贴板图片暂时无法读取。"}
			else: result = {"ok":false,"message":"剪贴板中没有可读取的图片。请使用插入图片。"}
		"import_docx":
			var path := await _choose_file(false, PackedStringArray(["*.docx ; Word 文档"]))
			result = await word.import_file(path, store) if not path.is_empty() and generation == store.epoch else {"ok":false}
		"export_docx":
			var path := await _choose_file(true, PackedStringArray(["*.docx ; Word 文档"]))
			result = await word.export_file(path, store) if not path.is_empty() and generation == store.epoch else {"ok":false}
		"react": result = await store.react(str(params.get("kind", "")), bool(params.get("value", false)))
		"report": result = await store.report(str(params.get("reason", "")), str(params.get("note", "")))
		"login":
			var provider: Node = get_node("/root/ProfileStore").provider
			result = await provider.begin_login() if is_instance_valid(provider) and provider.has_method("begin_login") else {"ok":false,"message":"登录服务暂不可用。"}
			if result.get("ok", false): store.activate()
		"open_link":
			var url := str(params.get("url", ""))
			if url.begins_with("https://") or url.begins_with("http://") or url.begins_with("mailto:"): OS.shell_open(url)
		"snapshot":
			var saved := true
			if params.get("data") is Dictionary and params.get("key") == store.current.get("client_key"):
				saved = store.update(params.data, params.get("ui", {})).get("ok", false)
			else: saved = store.persist()
			if str(params.get("request_id", "")) == _flush_ticket: snapshot_received.emit(saved)
		"client_error":
			push_warning("投稿编辑器错误：" + str(params.get("message", "")).left(300))
		_: result = {"ok":false,"message":"不支持的操作。"}
	if generation == store.epoch: _send({"kind":"response","id":str(message.get("id", "")),"result":result})

func _process(_delta: float) -> void:
	if _caret.x < 0 or not is_instance_valid(browser) or not get_window().has_focus(): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != browser and (focused == null or not browser.is_ancestor_of(focused)): return
	var point := browser.global_position + _caret * browser.size
	DisplayServer.window_set_ime_position(Vector2i(get_viewport().get_final_transform() * point), get_window().get_window_id())

func _choose_file(saving: bool, filters: PackedStringArray) -> String:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = filters
	if saving: dialog.current_file = "投稿文章.docx"
	add_child(dialog)
	var response := {"done":false,"path":""}
	dialog.file_selected.connect(func(path: String): response.path = path; response.done = true)
	dialog.canceled.connect(func(): response.done = true)
	dialog.popup_centered_ratio(0.7)
	while not response.done: await get_tree().process_frame
	dialog.queue_free()
	return response.path

func _files_dropped(paths: PackedStringArray) -> void:
	if public_mode or not browser_ready or store.view not in ["settings", "writer"]: return
	if store.current.get("state") not in ["draft", "returned"] or not store.conflict.is_empty() or not store.pending_action.is_empty(): return
	var pointer := get_global_mouse_position()
	if not browser.get_global_rect().has_point(pointer): return
	if paths.size() > 9:
		_send({"kind":"toast","message":"每篇稿件最多引用 9 张图片，请分批选择。"}); return
	var location := (pointer - browser.global_position) / browser.size
	for path in paths:
		var added: Dictionary = store.add_image(path)
		if not added.get("ok", false):
			_send({"kind":"toast","message":added.get("message", "图片未能插入。")}); continue
		_send({"kind":"dropped_image","asset":added.asset,"x":location.x,"y":location.y})

func prepare_navigation() -> bool:
	if not browser_ready or not is_instance_valid(browser): return store.persist()
	_flush_ticket = str(Time.get_ticks_usec())
	var answer := {"done":false,"ok":false}
	var receive := func(ok: bool): answer.done = true; answer.ok = ok
	snapshot_received.connect(receive, CONNECT_ONE_SHOT)
	browser.call("eval", "window.hegong.flush(" + JSON.stringify(_flush_ticket) + ");")
	var deadline := Time.get_ticks_msec() + 4000
	while not answer.done and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	if snapshot_received.is_connected(receive): snapshot_received.disconnect(receive)
	if not answer.ok: _send({"kind":"toast","message":"未能确认本机草稿保存，请稍后再离开。"})
	return answer.ok

func consume_back_action() -> bool:
	if browser_ready and is_instance_valid(browser):
		browser.call("eval", "window.hegong && window.hegong.back();")
		return true
	if public_mode: return false
	if store.view == "mine": return false
	store.switch_view("writer" if store.view == "preview" else "mine")
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _closing: _close_safely.call_deferred()

func _close_safely() -> void:
	_closing = true
	if await prepare_navigation(): get_tree().quit()
	else: _closing = false

func _exit_tree() -> void:
	if is_instance_valid(store):
		if store.changed.is_connected(_state_changed): store.changed.disconnect(_state_changed)
		store.persist()
	if get_tree() != null: get_tree().auto_accept_quit = _original_quit
