extends Node
const JsonStore = preload("res://scripts/local_json_store.gd")
const Records = preload("res://scripts/study_record.gd")
const QuestionBank = preload("res://scripts/question_bank.gd")
## Workbench-only records. Wrong questions and program drafts have separate persistence owners.

const FillAnswer = preload("res://scripts/fill_answer.gd")
const OutputAnswer = preload("res://scripts/output_answer.gd")

signal changed

const SAVE_PATH := "user://workbench_study_v1.json"
const TYPE_NAMES := {"single": "单选题", "multiple": "多选题", "judge": "判断题", "fill": "填空题", "output": "输出题", "program": "编程题"}
const TYPE_ORDER := ["single", "multiple", "judge", "fill", "output", "program"]
var history: Dictionary = {}
var learned: Dictionary = {}
var last_question: Dictionary = {}
var banks: Dictionary = {}


func _ready() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var saved = JsonStore.read(SAVE_PATH)
		if saved is Dictionary:
			if saved.get("history") is Dictionary:
				history = saved.history
			if saved.get("learned") is Dictionary:
				learned = saved.learned
			if saved.get("last_question") is Dictionary:
				last_question = saved.last_question
	for record in history.values():
		if record is Dictionary:
			_ensure_subject_records(record)
	var app := get_node("/root/AppState")
	for subject in app.SUBJECTS:
		banks[subject] = _load_questions_from_json(app.SUBJECTS[subject].question_path)


func remember_question(subject: String, question: Dictionary) -> void:
	last_question = {"subject": subject, "id": int(question.get("id", 0))}
	_save()


func record_answer(subject: String, question: Dictionary, correct: bool) -> void:
	_record(subject, question, true, correct)


func record_review(subject: String, question: Dictionary) -> void:
	_record(subject, question, false, false)


func _record(subject: String, question: Dictionary, answered: bool, correct: bool) -> void:
	last_question = Records.record(history, learned, subject, question, answered, correct, get_node("/root/AppState").SUBJECTS)
	_save()
	changed.emit()


func _save() -> void:
	if JsonStore.write(SAVE_PATH, {"version": 2, "history": history, "learned": learned, "last_question": last_question}) != OK:
		push_warning("学习记录保存失败，原文件已保留。")

func answer_count(correct_only := false) -> int:
	return Records.answer_count(history, correct_only)


func _ensure_subject_records(day: Dictionary) -> void:
	Records.ensure_subject_records(day, get_node("/root/AppState").SUBJECTS)


func recent_wrong_days(subject := "", count: int = 7) -> Array:
	var result := recent_days(count)
	for day in result:
		var record: Dictionary = history.get(day.date, {})
		_ensure_subject_records(record)
		var counters: Dictionary = record if subject.is_empty() else record.subjects.get(subject, {})
		day.count = maxi(0, int(counters.get("attempts", 0)) - int(counters.get("correct", 0)))
	return result


func has_unattributed_wrongs(count: int = 7) -> bool:
	for day in recent_days(count):
		var record: Dictionary = history.get(day.date, {})
		_ensure_subject_records(record)
		var attributed := 0
		for counters in record.subjects.values():
			attributed += maxi(0, int(counters.get("attempts", 0)) - int(counters.get("correct", 0)))
		if int(record.get("attempts", 0)) - int(record.get("correct", 0)) > attributed:
			return true
	return false


func day_count(date: String) -> int:
	return Records.day_count(history, date)


func recent_days(count: int = 7) -> Array:
	return Records.recent_days(history, count)


func subject_learned(subject: String) -> int:
	return Records.subject_learned(learned, subject, banks.get(subject, []))


func summary() -> Dictionary:
	var total := 0
	var completed := 0
	var types: Dictionary = {}
	for subject in banks:
		total += banks[subject].size()
		completed += subject_learned(subject)
		for question in banks[subject]:
			var kind := str(question.get("type", "single"))
			types[kind] = int(types.get(kind, 0)) + 1
	var active_days := 0
	for date in history:
		if day_count(str(date)) > 0:
			active_days += 1
	return {"total": total, "learned": completed, "percent": 100.0 * completed / maxi(1, total), "today": day_count(Time.get_date_string_from_system()), "days": active_days, "types": types}


func resume_target() -> Dictionary:
	var subject := str(last_question.get("subject", ""))
	var id := int(last_question.get("id", -1))
	var questions: Array = banks.get(subject, [])
	for index in questions.size():
		if int(questions[index].get("id", 0)) == id:
			return {"subject": subject, "index": index}
	return {}


func _load_questions_from_json(path: String) -> Array:
	return QuestionBank.load_file(path)

func _group_questions_by_type(questions: Array) -> Array:
	return QuestionBank.group_by_type(questions)

func _is_valid_question(value: Variant) -> bool:
	return QuestionBank.is_valid(value)
