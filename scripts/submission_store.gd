extends Node
## One account-scoped working document for settings, writing and private preview.
signal changed(reason: String)
const JsonStore = preload("res://scripts/local_json_store.gd")
const EMPTY := {"title":"", "category_id":"", "course":"", "tags":[], "cover_asset_id":"", "sources":"", "document":{"type":"doc","content":[{"type":"paragraph","content":[]}]}}
const ROOT := "user://submissions_v1"
var profile: Node
var provider: Node
var account_id := ""
var epoch := -1
var current: Dictionary = {}
var records: Array = []
var counts: Dictionary = {}
var config: Dictionary = {}
var article: Dictionary = {}
var public_items: Array = []
var view := "settings"
var status := ""
var error := ""
var conflict: Dictionary = {}
var busy := false
var dirty := false
var sequence := 0
var pending: Dictionary = {}
var pending_action: Dictionary = {}
var assets: Dictionary = {}
var _timer: Timer
var _last_key := ""
var _public_request := 0

func _ready() -> void:
	profile = get_node("/root/ProfileStore")
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 1.5
	_timer.timeout.connect(save)
	add_child(_timer)
	profile.changed.connect(_session_changed)
	_session_changed()

func _session_changed() -> void:
	if epoch == profile.epoch: return
	if not current.is_empty(): persist()
	epoch = profile.epoch
	account_id = profile.account_id if profile.authenticated() else ""
	provider = profile.provider
	current = {}; records = []; counts = {}; assets = {}; article = {}; public_items = []; config = {}; conflict = {}; pending = {}; pending_action = {}
	_public_request += 1
	busy = false; dirty = false; sequence = 0; error = ""; status = ""; view = "settings"
	_last_key = ""
	_timer.stop()
	changed.emit("account")

func _directory() -> String: return ROOT.path_join(account_id.sha256_text())
func _path(key: String) -> String: return _directory().path_join(key + ".json")
func _key() -> String: return Crypto.new().generate_random_bytes(16).hex_encode()

func state() -> Dictionary:
	return {"epoch":epoch,"authenticated":not account_id.is_empty(),"view":view,"draft":current,"items":records,"counts":counts,"config":config,"article":article,"status":status,"error":error,"busy":busy,"dirty":dirty,"conflict":conflict,"pending_action":pending_action,"local_items":local_records()}

func local_records() -> Array:
	var result: Array = []
	if account_id.is_empty(): return result
	var directory := DirAccess.open(_directory())
	if directory == null: return result
	for file in directory.get_files():
		if not file.ends_with(".json") or file == "session.json": continue
		var data: Variant = JsonStore.read(_directory().path_join(file))
		if data is Dictionary and data.get("account_id") == account_id and (data.get("dirty", false) or not data.get("pending_action", {}).is_empty()): result.append(data.draft)
	return result

func persist() -> bool:
	if account_id.is_empty() or current.is_empty(): return true
	var issue := JsonStore.write(_path(str(current.client_key)), {"account_id":account_id,"draft":current,"dirty":dirty,"assets":assets,"pending":pending,"pending_action":pending_action,"sequence":sequence})
	if issue != OK:
		error = "本机草稿保存失败，请检查磁盘空间；当前内容仍在编辑器中。"
		changed.emit("status")
	elif _last_key != str(current.client_key):
		if JsonStore.write(_directory().path_join("session.json"), {"account_id":account_id,"last_key":current.client_key}) == OK: _last_key = str(current.client_key)
	return issue == OK

func activate() -> void:
	if account_id.is_empty(): changed.emit("account"); return
	if view == "article": view = "settings"
	if current.is_empty():
		var previous: Variant = JsonStore.read(_directory().path_join("session.json"))
		var restored: bool = previous is Dictionary and previous.get("account_id") == account_id and load_local(str(previous.get("last_key", "")))
		var recoveries := local_records()
		if restored:
			status = "已恢复上次编辑的稿件"
			if not str(current.id).is_empty(): await open_draft(str(current.id))
		elif not recoveries.is_empty():
			load_local(str(recoveries[0].client_key))
			status = "已恢复此账号的本机草稿；连接后可继续同步"
		else: new_draft()
	await refresh_config()

func refresh_config() -> void:
	var generation := epoch
	var result := await _request_rpc("submission_config", {})
	if generation != epoch: return
	if result.get("ok", false): config = result; error = ""
	else: error = "投稿服务暂不可用；本机草稿会保留，尚未提交。"
	changed.emit("config")

func new_draft() -> void:
	if account_id.is_empty() or busy: return
	if not persist(): return
	current = {"id":"","client_key":_key(),"revision":0,"revision_id":"","state":"draft","data":EMPTY.duplicate(true),"ui":{}}
	assets = {}; pending = {}; pending_action = {}; conflict = {}; sequence = 0; dirty = true; view = "settings"
	status = "本机新草稿，等待同步"
	persist()
	changed.emit("open")

func update(data: Dictionary, ui: Dictionary = {}) -> Dictionary:
	if account_id.is_empty() or current.is_empty() or current.state not in ["draft", "returned"]: return {"ok":false,"message":"此版本不能编辑。"}
	if not pending_action.is_empty(): return {"ok":false,"message":"上次操作结果尚待确认，请先核实。"}
	if JSON.stringify(data).length() > 1000000: return {"ok":false,"message":"正文超过允许大小。"}
	if current.data != data:
		current.data = data.duplicate(true); sequence += 1; dirty = true
		status = "等待自动保存…"
	current.ui = ui.duplicate(true)
	var saved := persist()
	if saved and conflict.is_empty(): _timer.start()
	changed.emit("status")
	return {"ok":saved,"local_saved":saved}

func switch_view(mode: String) -> void:
	if mode not in ["settings","writer","mine","preview"]: return
	if not persist(): return
	view = mode
	changed.emit("view")
	if mode == "mine": refresh_mine()

func load_local(key: String) -> bool:
	if key.length() != 32 or not key.is_valid_hex_number(): return false
	var data: Variant = JsonStore.read(_path(key))
	if not data is Dictionary or data.get("account_id") != account_id: return false
	current = data.draft; assets = data.get("assets", {}); dirty = data.get("dirty", false); pending = data.get("pending", {})
	pending_action = data.get("pending_action", {})
	sequence = int(data.get("sequence", 0)); conflict = {}; view = "settings"
	changed.emit("open")
	return true

func open_draft(id: String, key := "") -> Dictionary:
	if busy: return {"ok":false,"message":"正在保存，请稍后切换稿件。"}
	if not persist(): return {"ok":false,"message":error}
	if id.is_empty() and load_local(key): return {"ok":true}
	var generation := epoch
	var result := await _request_rpc("submission_get", {"submission_id":id})
	if generation != epoch: return {"ok":false}
	if result.get("ok", false):
		var remote: Dictionary = result.submission
		var local: Variant = JsonStore.read(_path(str(remote.client_key)))
		if local is Dictionary and local.get("account_id") == account_id and (local.get("dirty", false) or not local.get("pending_action", {}).is_empty()):
			load_local(str(remote.client_key))
			if int(current.revision) != int(remote.revision): conflict = remote
		else:
			current = remote; assets = local.get("assets", {}) if local is Dictionary else {}; dirty = false; sequence = 0; pending = {}; pending_action = {}; conflict = {}
			if local is Dictionary and local.get("account_id") == account_id:
				current.ui = local.get("draft", {}).get("ui", {}).duplicate(true)
		view = "settings" if current.state in ["draft","returned"] else "preview"
		status = "本机修改待同步" if dirty else "草稿已同步" if current.state in ["draft", "returned"] else "当前版本已保存"
		error = ""; changed.emit("open")
	return result

func save() -> Dictionary:
	if busy: return {"ok":false,"message":"正在保存，请稍候。"}
	if not pending_action.is_empty(): return {"ok":false,"message":"请先核实上次操作结果。"}
	if account_id.is_empty() or current.is_empty(): return {"ok":false,"message":"请先登录。"}
	if not conflict.is_empty(): return {"ok":false,"message":"请先处理版本冲突。"}
	if not dirty and pending.is_empty(): return {"ok":true}
	if not persist(): return {"ok":false,"message":error}
	busy = true; status = "保存中…"; error = ""; changed.emit("status")
	var generation := epoch
	var key: String = current.client_key
	var sent_sequence := sequence
	# Keep an uncertain request byte-for-byte stable across retries.
	if pending.is_empty():
		pending = {"action":"submission_create" if str(current.id).is_empty() else "submission_save","sequence":sent_sequence,"payload":{"operation_id":_key(),"data":current.data.duplicate(true)}}
		if str(current.id).is_empty(): pending.payload.client_key = key
		else: pending.payload.merge({"submission_id":current.id,"expected_revision":current.revision})
		persist()
	var uploads_ok := await upload_assets(pending.payload.data)
	if generation != epoch: return {"ok":false}
	var result: Dictionary = await _request_rpc(str(pending.action), pending.payload) if uploads_ok else {"ok":false,"message":error}
	if generation != epoch or current.get("client_key") != key: return {"ok":false}
	busy = false
	if result.get("ok", false):
		var remote: Dictionary = result.submission
		var latest_data: Dictionary = current.data
		var latest_ui: Dictionary = current.get("ui", {})
		var captured_sequence := int(pending.sequence)
		current = remote
		current.ui = latest_ui
		if sequence != captured_sequence: current.data = latest_data
		dirty = sequence != captured_sequence
		pending = {}; status = "草稿已自动保存"; error = ""
		persist()
		if dirty: _timer.start()
	elif result.get("code") == "revision_conflict":
		pending = {}
		var latest := await _request_rpc("submission_get", {"submission_id":current.id})
		if generation != epoch: return {"ok":false}
		conflict = latest.get("submission", {})
		error = "服务器已有更新，本机内容已保留，请选择要继续的版本。"
	else:
		error = str(result.get("message", "同步失败，本机草稿已保留。"))
		status = "保存失败 · 本机草稿已保留"
		if result.get("code") == "inaccessible_asset":
			for id in assets:
				if FileAccess.file_exists(str(assets[id].get("path", ""))): assets[id].uploaded = false
		if result.get("definitive", false): pending = {}
		persist()
	changed.emit("saved")
	return result

func resolve_conflict(use_local: bool) -> void:
	if conflict.is_empty(): return
	if not use_local:
		JsonStore.write(_path(str(current.client_key)) + ".backup", {"account_id":account_id,"draft":current})
		current = conflict.duplicate(true); dirty = false
	else:
		if str(conflict.get("state", "")) not in ["draft", "returned"]:
			error = "服务器上的稿件已进入审核或发表，请保留本机恢复副本，并先撤回审核或创建修订版。"
			changed.emit("status")
			return
		current.revision = conflict.revision; current.revision_id = conflict.revision_id; dirty = true
	conflict = {}; pending = {}; error = ""; persist(); changed.emit("open")
	if dirty: save()

func submit() -> Dictionary:
	var generation := epoch
	if pending_action.get("action") == "submission_submit": return await transition("submission_submit")
	if dirty or not pending.is_empty():
		var saved := await save()
		if not saved.get("ok", false) or generation != epoch or dirty: return {"ok":false,"message":"请先完成当前版本的保存。"}
	return await transition("submission_submit")

func transition(action: String) -> Dictionary:
	if action not in ["submission_submit","submission_withdraw","submission_revise","submission_delete"] or current.is_empty() or busy: return {"ok":false}
	if action == "submission_delete" and str(current.id).is_empty():
		DirAccess.remove_absolute(_path(str(current.client_key)))
		current = {}; dirty = false; pending = {}; view = "mine"; changed.emit("open")
		return {"ok":true}
	busy = true; changed.emit("status")
	var generation := epoch
	if not pending_action.is_empty() and pending_action.get("action") != action:
		busy = false
		return {"ok":false,"message":"请先重试上次未确认的操作。"}
	if pending_action.is_empty(): pending_action = {"action":action,"payload":{"submission_id":current.id,"expected_revision":current.revision,"operation_id":_key()}}
	persist()
	var result := await _request_rpc(action, pending_action.payload)
	if generation != epoch: return {"ok":false}
	busy = false
	if result.get("ok", false):
		pending_action = {}
		if result.has("submission"): current = result.submission; dirty = false; persist()
		else:
			DirAccess.remove_absolute(_path(str(current.client_key))); current = {}; dirty = false
		status = "已提交，待审核" if action == "submission_submit" else "操作已完成"
		view = "mine" if action in ["submission_submit","submission_delete"] else "settings"
		refresh_mine()
	else:
		error = str(result.get("message", "操作未完成，请重试原操作。"))
		if result.get("definitive", false): pending_action = {}
		persist()
	changed.emit("open")
	return result

func refresh_mine() -> void:
	var generation := epoch
	var cursor := ""
	var loaded: Dictionary = {}
	for page_index in 200:
		var result := await _request_rpc("submission_mine", {"cursor":cursor})
		if generation != epoch: return
		if not result.get("ok", false): error = str(result.get("message", "无法获取投稿列表。")); break
		for item in result.items: loaded[str(item.id)] = item
		counts = result.counts; error = ""
		cursor = str(result.get("next_cursor", ""))
		if cursor.is_empty(): break
	records = loaded.values()
	changed.emit("list")

func open_article(id: String) -> Dictionary:
	var generation := epoch
	var result: Dictionary
	if not account_id.is_empty(): result = await _request_rpc("article_get", {"article_id":id})
	elif is_instance_valid(provider) and provider.has_method("submission_get"): result = await provider.submission_get("/v1/articles/" + id)
	else: result = {"ok":false,"message":"文章服务暂不可用。"}
	if generation != epoch: return {"ok":false}
	if result.get("ok", false): article = result.article; view = "article"; error = ""
	else: article = {}; error = str(result.get("message", "文章未公开或无法访问。"))
	changed.emit("article")
	return result

func refresh_public() -> void:
	var api: Node = profile.provider
	if not is_instance_valid(api) or not api.has_method("submission_get"): return
	_public_request += 1
	var ticket := _public_request
	var generation := epoch
	var cursor := ""
	var loaded: Dictionary = {}
	for page_index in 200:
		var result: Dictionary = await api.submission_get("/v1/articles" + ("?cursor=" + cursor.uri_encode() if not cursor.is_empty() else ""))
		if ticket != _public_request or generation != epoch: return
		if not result.get("ok", false): return
		for item in result.items: loaded[str(item.id)] = item
		cursor = str(result.get("next_cursor", ""))
		if cursor.is_empty(): break
	public_items = loaded.values(); changed.emit("public")

func react(kind: String, value: bool) -> Dictionary:
	if article.is_empty(): return {"ok":false}
	var generation := epoch
	var result := await _request_rpc("article_react", {"article_id":article.id,"kind":kind,"value":value,"operation_id":_key()})
	if generation == epoch and result.get("ok", false): article = result.article; changed.emit("reaction")
	return result

func report(reason: String, note: String) -> Dictionary:
	if article.is_empty(): return {"ok":false}
	return await _request_rpc("article_report", {"article_id":article.id,"reason":reason,"note":note,"operation_id":_key()})

func _request_rpc(action: String, payload: Dictionary) -> Dictionary:
	if account_id.is_empty(): return {"ok":false,"message":"请先登录。"}
	if not is_instance_valid(provider) or not provider.has_method("social_request"): return {"ok":false,"message":"投稿服务暂不可用。"}
	return await provider.social_request(action, payload)

func add_image(path: String) -> Dictionary:
	if account_id.is_empty(): return {"ok":false,"message":"请先登录。"}
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null or input.get_length() > 6291456: return {"ok":false,"message":"请选择不超过 6 MB 的图片。"}
	var bytes := input.get_buffer(input.get_length())
	input.close()
	if bytes.size() < 12: return {"ok":false,"message":"图片内容不完整。"}
	var dimensions := _image_dimensions(bytes)
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > 8192 or dimensions.y > 8192 or dimensions.x * dimensions.y > 20000000:
		return {"ok":false,"message":"图片格式或尺寸不符合要求。"}
	var image := Image.new()
	var mime := ""
	if bytes[0] == 137 and bytes[1] == 80 and image.load_png_from_buffer(bytes) == OK: mime = "image/png"
	elif bytes[0] == 255 and bytes[1] == 216 and image.load_jpg_from_buffer(bytes) == OK: mime = "image/jpeg"
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and image.load_webp_from_buffer(bytes) == OK: mime = "image/webp"
	if mime.is_empty() or image.get_width() > 8192 or image.get_height() > 8192 or image.get_width() * image.get_height() > 20000000: return {"ok":false,"message":"图片格式或尺寸不符合要求。"}
	var id := _key()
	var directory := _directory().path_join("assets")
	DirAccess.make_dir_recursive_absolute(directory)
	var destination := directory.path_join(id)
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null: return {"ok":false,"message":"无法保存本机图片。"}
	file.store_buffer(bytes); file.close()
	assets[id] = {"id":id,"path":destination,"name":path.get_file(),"mime":mime,"uploaded":false,"bytes":bytes.size()}
	persist()
	return {"ok":true,"asset":assets[id]}

func _image_dimensions(data: PackedByteArray) -> Vector2i:
	# Check headers before allocating decoded pixels from a user-selected file.
	if data.size() >= 24 and data[0] == 137 and data[1] == 80:
		var width := (int(data[16]) << 24) | (int(data[17]) << 16) | (int(data[18]) << 8) | int(data[19])
		var height := (int(data[20]) << 24) | (int(data[21]) << 16) | (int(data[22]) << 8) | int(data[23])
		return Vector2i(width, height)
	if data.size() >= 4 and data[0] == 255 and data[1] == 216:
		var offset := 2
		while offset + 8 < data.size():
			if data[offset] != 255: return Vector2i.ZERO
			while offset < data.size() and data[offset] == 255: offset += 1
			if offset + 7 >= data.size(): return Vector2i.ZERO
			var marker := int(data[offset]); offset += 1
			if marker == 217 or marker == 218: return Vector2i.ZERO
			var length := (int(data[offset]) << 8) | int(data[offset + 1])
			if length < 2 or offset + length > data.size(): return Vector2i.ZERO
			if marker in [192,193,194,195,197,198,199,201,202,203,205,206,207]:
				return Vector2i((int(data[offset + 5]) << 8) | int(data[offset + 6]), (int(data[offset + 3]) << 8) | int(data[offset + 4]))
			offset += length
	if data.size() >= 30 and data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		var kind := data.slice(12, 16).get_string_from_ascii()
		if kind == "VP8X":
			if data[20] & 2: return Vector2i.ZERO
			return Vector2i(1 + int(data[24]) + (int(data[25]) << 8) + (int(data[26]) << 16), 1 + int(data[27]) + (int(data[28]) << 8) + (int(data[29]) << 16))
		if kind == "VP8L" and data[20] == 47:
			return Vector2i(1 + int(data[21]) + ((int(data[22]) & 63) << 8), 1 + (int(data[22]) >> 6) + (int(data[23]) << 2) + ((int(data[24]) & 15) << 10))
		if kind == "VP8 ":
			for index in range(20, mini(80, data.size() - 7)):
				if data[index] == 157 and data[index + 1] == 1 and data[index + 2] == 42:
					return Vector2i((int(data[index + 3]) | (int(data[index + 4]) << 8)) & 16383, (int(data[index + 5]) | (int(data[index + 6]) << 8)) & 16383)
	return Vector2i.ZERO

func _references(document: Dictionary) -> Array:
	var result: Array = []
	if document.get("type") == "image": result.append(str(document.get("attrs", {}).get("asset_id", "")))
	for child in document.get("content", []):
		for id in _references(child):
			if id not in result: result.append(id)
	return result

func upload_assets(data: Dictionary) -> bool:
	var references := _references(data.document)
	if not str(data.get("cover_asset_id", "")).is_empty() and data.cover_asset_id not in references: references.append(data.cover_asset_id)
	for id in references:
		if not assets.has(id) or assets[id].get("uploaded", false): continue
		if not is_instance_valid(provider) or not provider.has_method("submission_upload"): error = "图片上传服务暂不可用。"; return false
		var generation := epoch
		var response: Dictionary = await provider.submission_upload({"asset_id":id,"name":assets[id].name,"data":Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(assets[id].path))})
		if generation != epoch: return false
		if not response.get("ok", false): error = str(response.get("message", "图片上传失败，可再次保存重试。")); return false
		assets[id].uploaded = true; persist()
	return true

func image_data(id: String) -> Dictionary:
	if id.length() != 32 or not id.is_valid_hex_number(): return {"ok":false}
	if assets.has(id) and FileAccess.file_exists(str(assets[id].get("path", ""))):
		return {"ok":true,"id":id,"mime":assets[id].mime,"data":Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(assets[id].path))}
	if not is_instance_valid(provider) or not provider.has_method("submission_get"): return {"ok":false}
	var generation := epoch
	var result: Dictionary = await provider.submission_get("/v1/submission-assets/" + id, true)
	if generation != epoch: return {"ok":false}
	if not result.get("ok", false) or result.get("mime", "") not in ["image/png","image/jpeg","image/webp"]: return {"ok":false}
	return {"ok":true,"id":id,"mime":result.mime,"data":Marshalls.raw_to_base64(result.data)}

func _exit_tree() -> void: persist()
