extends Node
## Optional bridge: send answers to a server-issued attempt, never local correctness.
var quiz: Node
var store: Node
var serial := 0
var attempt_id := ""
var prepared := false
var submitted := false
var pending_answer: Dictionary = {}
var session_epoch := -1
var feedback := ""

func _ready() -> void:
	store = get_node("/root/PageRouter").wallet_store()
	store.changed.connect(_session_changed)

func _session_changed() -> void:
	if session_epoch != store.epoch and not feedback.is_empty():
		feedback = ""
		if is_instance_valid(quiz): quiz._refresh_answer_feedback()

func prepare(subject: String, question: Dictionary) -> void:
	serial += 1
	attempt_id = ""
	prepared = false
	submitted = false
	pending_answer = {}
	feedback = ""
	session_epoch = store.epoch
	var request_serial := serial
	# First entry into Quiz can precede the initial asynchronous catalog response.
	# Keep the original answer if the learner submits while rules/attempt load.
	while store.catalog_loading:
		await store.changed
		if request_serial != serial or session_epoch != store.epoch: return
	var rule: Dictionary = store.rules.get("quiz", {})
	if not store.available() or not rule.get("enabled", false) or not rule.get("trusted_attempts", false): return
	var types: Array = rule.get("types", [])
	if question.get("type") not in types: return
	var response: Dictionary = await store.request("quiz_attempt", {"request_id": Crypto.new().generate_random_bytes(24).hex_encode(), "subject_id": subject, "question_id": str(question.get("id", "")), "bank_version": str(rule.get("bank_versions", {}).get(subject, ""))})
	if request_serial != serial or session_epoch != store.epoch: return
	prepared = true
	if response.get("ok", false): attempt_id = str(response.get("attempt_id", ""))
	if not pending_answer.is_empty(): _send()

func submit() -> void:
	if submitted or session_epoch != store.epoch: return
	var keys: Array[String] = []
	for index in quiz.selected_indices: keys.append(str(quiz.shuffled_options[index].get("key", "")))
	keys.sort()
	pending_answer = {"selected_keys": keys, "entered_answers": quiz.entered_answers.duplicate()}
	if prepared: _send()

func _send() -> void:
	if submitted: return
	submitted = true
	if attempt_id.is_empty():
		_feedback("电池奖励暂无法核实")
		return
	var request_serial := serial
	var response: Dictionary = await store.submit_quiz(attempt_id, pending_answer)
	if request_serial != serial or session_epoch != store.epoch: return
	var reward: Dictionary = response.get("reward", {})
	if response.get("ok", false) and reward.get("status") == "credited":
		_feedback("获得 %s 电池" % store.Amount.grouped(int(reward.amount)))
	elif response.get("ok", false) and reward.get("status") == "pending": _feedback("电池奖励待发放")
	elif not response.get("ok", false): _feedback("电池奖励待核实，可查看明细")

func _feedback(value: String) -> void:
	if is_instance_valid(quiz) and quiz.has_answered:
		feedback = value
		quiz._refresh_answer_feedback()
		get_node("/root/UiMotion").enter(quiz.result_label)

func apply_feedback() -> void:
	if session_epoch == store.epoch and not feedback.is_empty() and quiz.has_answered:
		quiz.result_label.text += " · " + feedback
