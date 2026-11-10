extends RefCounted
## Shared local learning counters. No HTTP, accounts, scenes or disk access.

static func ensure_subject_records(day: Dictionary, subjects: Dictionary) -> void:
	if day.get("subjects") is Dictionary: return
	day["subjects"] = {}
	var questions = day.get("questions", {})
	if not questions is Dictionary or questions.is_empty(): return
	var subject := ""
	for key in questions:
		var candidate := str(key).get_slice(":", 0)
		if not subjects.has(candidate) or (not subject.is_empty() and subject != candidate): return
		subject = candidate
	day.subjects[subject] = {"attempts": int(day.get("attempts", 0)), "correct": int(day.get("correct", 0))}

static func record(history: Dictionary, learned: Dictionary, subject: String, question: Dictionary, answered: bool, correct: bool, subjects: Dictionary, date := "") -> Dictionary:
	if date.is_empty(): date = Time.get_date_string_from_system()
	var key := "%s:%s" % [subject, str(question.get("id", 0))]
	var day: Dictionary = history.get(date, {"questions": {}, "attempts": 0, "correct": 0})
	ensure_subject_records(day, subjects)
	if not day.get("questions") is Dictionary: day["questions"] = {}
	day.questions[key] = true
	if answered:
		day["attempts"] = int(day.get("attempts", 0)) + 1
		day["correct"] = int(day.get("correct", 0)) + int(correct)
		var counters: Dictionary = day.subjects.get(subject, {"attempts": 0, "correct": 0})
		counters["attempts"] = int(counters.get("attempts", 0)) + 1
		counters["correct"] = int(counters.get("correct", 0)) + int(correct)
		day.subjects[subject] = counters
	history[date] = day
	learned[key] = true
	return {"subject": subject, "id": int(question.get("id", 0))}

static func answer_count(history: Dictionary, correct_only := false) -> int:
	var count := 0
	for day in history.values(): count += int(day.get("correct" if correct_only else "attempts", 0))
	return count

static func day_count(history: Dictionary, date: String) -> int:
	var day = history.get(date, {})
	return day.get("questions", {}).size() if day is Dictionary and day.get("questions", {}) is Dictionary else 0

static func recent_days(history: Dictionary, count: int = 7) -> Array:
	var result: Array = []
	var midnight := Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system() + "T00:00:00")
	for offset in range(count - 1, -1, -1):
		var date := Time.get_date_string_from_unix_time(midnight - offset * 86400)
		result.append({"date": date, "count": day_count(history, date)})
	return result

static func subject_learned(learned: Dictionary, subject: String, bank: Array) -> int:
	var count := 0
	for question in bank:
		if learned.has("%s:%s" % [subject, str(question.get("id", 0))]): count += 1
	return count
