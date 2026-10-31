extends Node
## Collect raw answers locally. Only the explicit Finish action settles the practice.
signal feedback_changed
var session: RefCounted
var rewards: Node
var practice_id := ""
var subject_id := ""
var session_epoch := -1
var feedback := ""

func _ready() -> void:
	rewards = get_node("/root/AppServices").practice_rewards()
	rewards.changed.connect(_session_changed)

func _session_changed() -> void:
	if session_epoch == rewards.epoch: return
	practice_id = ""
	feedback = ""
	session_epoch = rewards.epoch
	feedback_changed.emit()

func prepare(subject: String, _question: Dictionary) -> void:
	subject_id = subject
	session_epoch = rewards.epoch
	feedback = ""
	if practice_id.is_empty(): practice_id = rewards.start(subject)

func submit() -> void:
	if practice_id.is_empty() or session_epoch != rewards.epoch: return
	var keys: Array = session.selected_keys()
	keys.sort()
	rewards.record(practice_id, session.current(), keys, session.entered_answers, session.is_correct())
	if session.is_correct():
		feedback = "答题奖励将在结束练习后统一结算"
		feedback_changed.emit()

func finish() -> Dictionary:
	return await rewards.finish(practice_id)
