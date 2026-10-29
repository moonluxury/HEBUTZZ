extends RefCounted
## One practice session. Owns answers and retries independently of any scene.
const Grader = preload("res://scripts/quiz_grader.gd")
var all_questions: Array = []
var questions: Array = []
var wrong_ids: Dictionary = {}
var question_states: Dictionary = {}
var current_index := 0
var shuffled_options: Array = []
var selected_indices: Array = []
var entered_answers: Array[String] = []
var reference_revealed := false
var has_answered := false

func configure(bank: Array, wrongs: Dictionary, wrong_mode: bool, start: int) -> void:
	question_states.clear()
	shuffled_options.clear()
	selected_indices.clear()
	entered_answers.clear()
	reference_revealed = false
	has_answered = false
	all_questions = bank
	wrong_ids = wrongs
	questions = bank.filter(func(question: Dictionary): return wrongs.has(str(question.id))) if wrong_mode else bank.duplicate()
	current_index = clampi(start, 0, maxi(0, questions.size() - 1))

func current() -> Dictionary:
	return questions[current_index] if current_index >= 0 and current_index < questions.size() else {}

func is_kind(kind: String) -> bool:
	return current().get("type", "") == kind

func state_key(index: int) -> String:
	return str(questions[index].get("id", index + 1)) if index >= 0 and index < questions.size() else ""

func open_question(index: int, program_draft := "") -> bool:
	if index < 0 or index >= questions.size(): return false
	current_index = index
	shuffled_options = current().get("options", []).duplicate()
	if not current().get("preserve_option_order", false): shuffled_options.shuffle()
	restore(program_draft)
	return true

func restore(program_draft := "") -> void:
	selected_indices.clear()
	entered_answers.clear()
	has_answered = false
	reference_revealed = false
	if is_kind("program"): entered_answers.append(program_draft)
	var previous: Dictionary = question_states.get(state_key(current_index), {})
	if not previous.is_empty() and (not previous.get("submitted", previous.get("answered", false)) or is_kind("program")):
		reference_revealed = bool(previous.get("reference_revealed", false))
		entered_answers.clear()
		for answer in previous.get("fill_answers", []): entered_answers.append(str(answer))
		for index in shuffled_options.size():
			if str(shuffled_options[index].key) in previous.get("selected_keys", []): selected_indices.append(index)
	var blanks: int = current().get("blanks", []).size() if is_kind("fill") else 1 if is_kind("output") or is_kind("program") else 0
	while entered_answers.size() < blanks: entered_answers.append("")

func selected_keys() -> Array[String]:
	var keys: Array[String] = []
	for index in selected_indices: keys.append(str(shuffled_options[index].key))
	return keys

func is_correct() -> bool:
	return Grader.correct(current(), selected_keys(), entered_answers)

func save() -> void:
	var previous: Dictionary = question_states.get(state_key(current_index), {})
	question_states[state_key(current_index)] = {"selected_keys": selected_keys(), "fill_answers": entered_answers.duplicate(),
		"answered": has_answered or bool(previous.get("answered", false)), "submitted": has_answered,
		"reference_revealed": reference_revealed, "correct": is_correct() if has_answered else bool(previous.get("correct", false))}

func select_option(index: int) -> String:
	if has_answered or index < 0 or index >= shuffled_options.size(): return "ignored"
	if is_kind("multiple"):
		if index in selected_indices: selected_indices.erase(index)
		else: selected_indices.append(index)
		save()
		return "selection"
	selected_indices = [index]
	return "submit"

func submission_issue() -> Dictionary:
	if is_kind("output") and entered_answers[0].strip_edges().is_empty():
		return {"message": "请输入程序输出", "field": 0}
	if is_kind("fill"):
		for index in entered_answers.size():
			if entered_answers[index].strip_edges().is_empty(): return {"message": "请填写第 %d 空" % (index + 1), "field": index}
	elif not is_kind("output") and selected_indices.is_empty():
		return {"message": "请至少选择一个选项", "field": -1}
	return {}

func submit() -> bool:
	if has_answered: return false
	has_answered = true
	save()
	return true

func set_answer(index: int, value: String) -> void:
	if has_answered or index < 0 or index >= entered_answers.size(): return
	entered_answers[index] = value
	save()

func set_reference(revealed: bool) -> void:
	reference_revealed = revealed
	save()
