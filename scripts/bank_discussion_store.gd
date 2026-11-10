extends Node
## Lazy, session-scoped bank discussions. No question identifier or reward dependency.
signal changed(bank: String, reason: String)
var profile: Node
var epoch := -1
var banks: Dictionary = {}

func _ready() -> void:
	profile = get_node("/root/ProfileStore")
	profile.changed.connect(_session_changed)
	_session_changed()

func _session_changed() -> void:
	if epoch == profile.epoch: return
	epoch = profile.epoch
	banks.clear()
	changed.emit("", "account")

func state(bank: String) -> Dictionary:
	if not banks.has(bank):
		banks[bank] = {"items": [], "sort": "latest", "cursor": "", "loaded": false, "loading": false,
			"error": "", "notice": "", "draft": "", "reply_id": "", "reply_name": "", "scroll": 0,
			"replies": {}, "expanded": {}, "reply_loading": {}, "reply_serial": {}, "busy": {}, "pending": {}, "serial": 0, "publish_blocked": false}
	return banks[bank]

func _request(action: String, payload: Dictionary) -> Dictionary:
	if not is_instance_valid(profile.provider) or not profile.provider.has_method("comment_request"):
		return {"ok": false, "code": "unavailable", "message": "讨论服务暂不可用，请稍后重试。"}
	return await profile.provider.comment_request(action, payload)

func activate(bank: String) -> void:
	var s := state(bank)
	if (not s.loaded or s.publish_blocked) and not s.loading: load_page(bank)

func load_page(bank: String, more := false) -> void:
	var s := state(bank)
	if s.loading or (more and str(s.cursor).is_empty()): return
	s.loading = true; s.error = ""; s.serial += 1
	var serial: int = s.serial
	var generation := epoch
	changed.emit(bank, "status")
	var result := await _request("comment_list", {"target_type": "bank", "target_id": bank,
		"sort": s.sort, "limit": 20, "cursor": s.cursor if more else ""})
	if generation != epoch or serial != state(bank).serial: return
	s.loading = false
	if result.get("ok", false):
		s.publish_blocked = not result.get("can_publish", true)
		if not more: s.items = []
		for item in result.get("items", []):
			var found := false
			for existing in s.items:
				if existing.id == item.id: found = true; break
			if not found: s.items.append(item)
		s.cursor = str(result.get("cursor", "")); s.loaded = true
	else: s.error = str(result.get("message", "评论加载失败，请重试。"))
	changed.emit(bank, "items")

func sort_by(bank: String, value: String) -> void:
	var s := state(bank)
	if value == s.sort or value not in ["latest", "hot"]: return
	# Supersede an earlier request; its response cannot replace the new ordering.
	s.serial += 1; s.loading = false; s.sort = value; s.cursor = ""; s.scroll = 0
	s.items = []; s.loaded = false
	load_page(bank)

func reply_to(bank: String, item: Dictionary) -> void:
	var s := state(bank)
	s.reply_id = str(item.get("id", "")); s.reply_name = str(item.get("author", {}).get("name", ""))
	changed.emit(bank, "composer")

func load_replies(bank: String, parent: String, more := false) -> void:
	var s := state(bank)
	if s.reply_loading.get(parent, false): return
	if s.expanded.get(parent, false) and not more:
		s.expanded.erase(parent); changed.emit(bank, "items"); return
	s.expanded[parent] = true
	if s.replies.has(parent) and not more: changed.emit(bank, "items"); return
	s.reply_loading[parent] = true
	s.reply_serial[parent] = int(s.reply_serial.get(parent, 0)) + 1
	var serial: int = s.reply_serial[parent]
	var generation := epoch
	changed.emit(bank, "items")
	var page: Dictionary = s.replies.get(parent, {"items": [], "cursor": ""})
	var result := await _request("comment_replies", {"target_type": "bank", "target_id": bank,
		"parent_id": parent, "limit": 20, "cursor": page.cursor if more else ""})
	if generation != epoch or s.reply_serial.get(parent, 0) != serial: return
	s.reply_loading.erase(parent)
	if result.get("ok", false):
		page.items.append_array(result.get("items", [])); page.cursor = str(result.get("cursor", "")); s.replies[parent] = page
	else: s.error = str(result.get("message", "回复加载失败。")); s.expanded.erase(parent)
	changed.emit(bank, "items")

func publish(bank: String) -> void:
	var s := state(bank)
	var body := str(s.draft).strip_edges()
	if body.is_empty(): s.error = "请输入评论内容。"; changed.emit(bank, "status"); return
	await mutate(bank, "comment_create", {"body": body, "parent_id": s.reply_id}, "publish")

func mutate(bank: String, action: String, values: Dictionary, key: String) -> void:
	var s := state(bank)
	if s.busy.get(key, false): return
	if not profile.authenticated():
		s.error = "请先登录后参与讨论。"; changed.emit(bank, "status"); return
	var payload := values.duplicate(true)
	payload.target_type = "bank"; payload.target_id = bank
	# Unknown outcomes retain the exact request key. Editing text starts a new operation.
	var fingerprint := action + JSON.stringify(payload)
	if not s.pending.has(fingerprint): s.pending[fingerprint] = Crypto.new().generate_random_bytes(16).hex_encode()
	payload.operation_id = s.pending[fingerprint]
	s.busy[key] = true; s.error = ""; s.notice = ""
	var generation := epoch
	changed.emit(bank, "status")
	var result := await _request(action, payload)
	if generation != epoch: return
	s.busy.erase(key)
	if not result.get("ok", false):
		if result.get("code") == "discussion_full":
			s.publish_blocked = true; s.error = ""; s.notice = ""
			changed.emit(bank, "status"); return
		s.error = str(result.get("message", "操作失败，请重试；输入内容已保留。"))
		changed.emit(bank, "status"); return
	s.pending.erase(fingerprint)
	# A read started before this write must not overwrite its successful result.
	var reload: bool = s.loading
	if reload: s.serial += 1; s.loading = false
	if action == "comment_create":
		if str(s.draft).strip_edges() == values.body and s.reply_id == values.parent_id:
			s.draft = ""; s.reply_id = ""; s.reply_name = ""
		var item: Dictionary = result.get("comment", {})
		if str(values.parent_id).is_empty(): s.items.push_front(item)
		else:
			var parent := str(values.parent_id)
			s.replies.erase(parent); s.expanded.erase(parent)
			s.reply_loading.erase(parent)
			s.reply_serial[parent] = int(s.reply_serial.get(parent, 0)) + 1
			for root_item in s.items:
				if root_item.id == parent: root_item.reply_count = int(root_item.get("reply_count", 0)) + 1
			load_replies(bank, parent)
		s.notice = "已提交，等待审核。" if item.get("status") == "pending" else "发布成功"
	elif result.has("comment"):
		_replace(s.items, result.comment)
		for page in s.replies.values(): _replace(page.items, result.comment)
	elif action == "comment_report": s.notice = "举报已提交，等待处理。"
	changed.emit(bank, "items")
	if reload: load_page(bank)

func _replace(items: Array, item: Dictionary) -> void:
	for i in items.size():
		if items[i].id == item.id: items[i] = item; return
