extends Node
## Answers stay local until Finish. Submitted snapshots survive navigation and lost replies.
signal changed
const JsonStore = preload("res://scripts/local_json_store.gd")
var wallet: Node
var account_id := ""
var epoch := 0
var drafts: Dictionary = {}
var preparing: Dictionary = {}
var finishing: Dictionary = {}
var last_message := ""

func _ready() -> void:
	wallet = get_node("/root/AppServices").wallet_store()
	get_node("/root/ProfileStore").changed.connect(_account_changed)
	_account_changed()

func _path() -> String:
	return "user://practice_rewards_v1/" + account_id.sha256_text() + ".json"

func _persist() -> bool:
	return not account_id.is_empty() and JsonStore.write(_path(), {"account_id": account_id, "drafts": drafts}) == OK

func _account_changed() -> void:
	var profile := get_node("/root/ProfileStore")
	var next: String = profile.account_id if profile.authenticated() else ""
	if next == account_id: return
	epoch += 1
	account_id = next
	drafts = {}; preparing = {}; finishing = {}; last_message = ""
	if not account_id.is_empty():
		var saved: Variant = JsonStore.read(_path(), {})
		if saved is Dictionary and saved.get("account_id") == account_id and saved.get("drafts") is Dictionary:
			drafts = saved.drafts
	changed.emit()
	_recover.call_deferred(epoch)

func _recover(generation: int) -> void:
	# Only an explicit Finish marks a draft for recovery. Leaving a page never credits it.
	for id in drafts.keys():
		if generation != epoch: return
		if drafts.has(id) and drafts[id].get("finish_requested", false): await finish(id)

func start(subject: String) -> String:
	if account_id.is_empty() or not wallet.available(): return ""
	_recover.call_deferred(epoch)
	var path: String = get_node("/root/AppState").SUBJECTS.get(subject, {}).get("question_path", "")
	if path.is_empty(): return ""
	var version := FileAccess.get_file_as_string(path).trim_prefix("\ufeff").replace("\r\n", "\n").sha256_text()
	for id in drafts:
		var prior: Dictionary = drafts[id]
		if prior.subject_id == subject and prior.bank_version == version and not prior.get("finish_requested", false):
			_prepare.call_deferred(id)
			return id
	var id := Crypto.new().generate_random_bytes(24).hex_encode()
	drafts[id] = {"request_id": id, "subject_id": subject, "bank_version": version, "practice_id": "", "answers": {}, "finish_requested": false}
	if not _persist():
		drafts.erase(id)
		last_message = "练习奖励记录无法保存，请检查磁盘空间。"
		return ""
	_prepare.call_deferred(id)
	return id

func _prepare(id: String) -> bool:
	var generation := epoch
	while preparing.has(id):
		await changed
		if generation != epoch: return false
	if not drafts.has(id): return false
	if not str(drafts[id].practice_id).is_empty(): return true
	preparing[id] = true
	while wallet.catalog_loading:
		await wallet.changed
		if generation != epoch: return false
	if not wallet.rules.get("quiz", {}).get("practice_batches", false):
		preparing.erase(id)
		changed.emit()
		return false
	var draft: Dictionary = drafts[id]
	var result: Dictionary = await wallet.request("practice_begin", {"request_id": id, "subject_id": draft.subject_id, "bank_version": draft.bank_version})
	if generation != epoch: return false
	preparing.erase(id)
	var ready: bool = result.get("ok", false) and not str(result.get("practice_id", "")).is_empty()
	if ready:
		drafts[id].practice_id = str(result.practice_id)
		ready = _persist()
	changed.emit()
	return ready

func record(id: String, question: Dictionary, selected: Array, entered: Array, locally_correct: bool) -> void:
	if not drafts.has(id) or drafts[id].finish_requested: return
	if str(question.get("type", "single")) not in ["single", "multiple", "judge", "fill", "output"]: return
	if entered.any(func(value): return str(value).length() > 4096): return
	var key := str(int(question.id)) if question.id is float or question.id is int else str(question.id)
	var answers: Dictionary = drafts[id].answers
	if answers.get(key, {}).get("locally_correct", false): return
	# The flag only chooses a local candidate. The server receives and grades raw answers.
	answers[key] = {"question_id": key, "selected_keys": selected.duplicate(), "entered_answers": entered.duplicate(), "locally_correct": locally_correct}
	if not _persist(): last_message = "练习奖励暂未保存到本机，请重试结束练习。"

func finish(id: String) -> Dictionary:
	if not drafts.has(id): return {"ok": true, "empty": true}
	var generation := epoch
	while finishing.has(id):
		await changed
		if generation != epoch: return {"ok": false, "code": "stale"}
		if not drafts.has(id): return {"ok": true}
	drafts[id].finish_requested = true
	if not _persist(): return {"ok": false, "message": "奖励结算记录无法保存，请检查磁盘空间。"}
	finishing[id] = true
	var ready := await _prepare(id)
	if generation != epoch: return {"ok": false, "code": "stale"}
	var result := {"ok": false, "code": "unknown"}
	if ready:
		var answers: Array = []
		for value in drafts[id].answers.values():
			var answer: Dictionary = value.duplicate(true)
			answer.erase("locally_correct")
			answers.append(answer)
		result = await wallet.request("practice_finish", {"practice_id": drafts[id].practice_id, "answers": answers})
	if generation != epoch: return {"ok": false, "code": "stale"}
	finishing.erase(id)
	if result.get("ok", false) and result.get("reward") is Dictionary and wallet.adopt_balance(result):
		last_message = "本次练习获得 %d 电池" % int(result.reward.get("amount", 0))
		drafts.erase(id)
		_persist()
	else:
		last_message = "练习已结束，电池奖励待核实；再次登录或结束练习时会重试原记录。"
	changed.emit()
	return result
