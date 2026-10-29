extends Node
const JsonStore = preload("res://scripts/local_json_store.gd")
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
	var date := Time.get_date_string_from_system()
	var key := "%s:%s" % [subject, str(question.get("id", 0))]
	var day: Dictionary = history.get(date, {"questions": {}, "attempts": 0, "correct": 0})
	_ensure_subject_records(day)
	if not day.get("questions") is Dictionary:
		day["questions"] = {}
	day.questions[key] = true
	if answered:
		day["attempts"] = int(day.get("attempts", 0)) + 1
		day["correct"] = int(day.get("correct", 0)) + int(correct)
		var subject_record: Dictionary = day.subjects.get(subject, {"attempts": 0, "correct": 0})
		subject_record["attempts"] = int(subject_record.get("attempts", 0)) + 1
		subject_record["correct"] = int(subject_record.get("correct", 0)) + int(correct)
		day.subjects[subject] = subject_record
	history[date] = day
	learned[key] = true
	last_question = {"subject": subject, "id": int(question.get("id", 0))}
	_save()
	changed.emit()


func _save() -> void:
	if JsonStore.write(SAVE_PATH, {"version": 2, "history": history, "learned": learned, "last_question": last_question}) != OK:
		push_warning("学习记录保存失败，原文件已保留。")

func answer_count(correct_only := false) -> int:
	var count := 0
	for day in history.values():
		count += int(day.get("correct" if correct_only else "attempts", 0))
	return count

func _ensure_subject_records(day: Dictionary) -> void:
	if day.get("subjects") is Dictionary:
		return
	day["subjects"] = {}
	# Legacy totals can be attributed only when every recorded question is in one
	# known course. Mixed-course totals stay intact; never estimate their split.
	var questions = day.get("questions", {})
	if not questions is Dictionary or questions.is_empty():
		return
	var subject := ""
	for key in questions:
		var candidate := str(key).get_slice(":", 0)
		if not get_node("/root/AppState").SUBJECTS.has(candidate) or (not subject.is_empty() and subject != candidate):
			return
		subject = candidate
	day.subjects[subject] = {"attempts": int(day.get("attempts", 0)), "correct": int(day.get("correct", 0))}


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
	var day = history.get(date, {})
	return day.get("questions", {}).size() if day is Dictionary and day.get("questions", {}) is Dictionary else 0


func recent_days(count: int = 7) -> Array:
	var result: Array = []
	# Derive from local midnight so the chart follows the learner's local calendar.
	var midnight := Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system() + "T00:00:00")
	for offset in range(count - 1, -1, -1):
		var date := Time.get_date_string_from_unix_time(midnight - offset * 86400)
		result.append({"date": date, "count": day_count(date)})
	return result


func subject_learned(subject: String) -> int:
	var count := 0
	for question in banks.get(subject, []):
		if learned.has("%s:%s" % [subject, str(question.get("id", 0))]):
			count += 1
	return count


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
	if not FileAccess.file_exists(path):
		push_warning("题库文件不存在：%s" % path)
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("题库文件无法打开：%s" % path)
		return []

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		push_warning(
			"题库 JSON 解析失败（第 %d 行）：%s"
			% [json.get_error_line(), json.get_error_message()],
		)
		return []

	var parsed = json.data
	var raw_questions: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		raw_questions = parsed
	elif (
		typeof(parsed) == TYPE_DICTIONARY
		and parsed.has("questions")
		and typeof(parsed["questions"]) == TYPE_ARRAY
	):
		raw_questions = parsed["questions"]
	else:
		push_warning("题库 JSON 根节点必须是数组或包含 questions 数组")
		return []

	var valid_questions: Array = []
	for raw_question in raw_questions:
		if _is_valid_question(raw_question):
			valid_questions.append(raw_question)
		else:
			push_warning("已跳过一条格式不完整的题目数据")
	return _group_questions_by_type(valid_questions)


func _group_questions_by_type(questions: Array) -> Array:
	# Group once in the shared bank so practice, search and wrong reviews agree.
	# Keep source order within each type and preserve IDs used by existing saves.
	var groups: Dictionary = {}
	for kind in TYPE_ORDER:
		groups[kind] = []
	for question in questions:
		var kind := str(question.get("type", "single"))
		if not groups.has(kind):
			groups[kind] = []
		groups[kind].append(question)
	var grouped: Array = []
	for group in groups.values():
		grouped.append_array(group)
	return grouped


func _is_valid_question(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var question: Dictionary = value
	if question.get("type", "") == "fill":
		return question.has("stem") and FillAnswer.is_valid(question)
	if question.get("type", "") == "output":
		return question.has("stem") and OutputAnswer.is_valid(question)
	if question.get("type", "") == "program":
		return question.has("stem") and question.has("reference_code")
	return (
		question.has("stem")
		and question.has("options")
		and typeof(question["options"]) == TYPE_ARRAY
		and not question["options"].is_empty()
	)
