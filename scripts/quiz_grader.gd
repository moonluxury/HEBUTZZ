extends RefCounted
## Pure grading: no widgets, files, navigation or account services.
const FillAnswer = preload("res://scripts/fill_answer.gd")
const OutputAnswer = preload("res://scripts/output_answer.gd")

static func correct(question: Dictionary, selected_keys: Array, answers: Array) -> bool:
	if question.is_empty(): return false
	match str(question.get("type", "")):
		"program": return false
		"output":
			return not answers.is_empty() and OutputAnswer.is_correct(question.answers, str(answers[0]), str(question.get("answer_mode", "literal")))
		"fill":
			return FillAnswer.is_correct(question.blanks, answers, str(question.get("language", "python")))
	var expected: Array[String] = []
	for option in question.get("options", []):
		if option.get("correct", false): expected.append(str(option.key))
	var selected := selected_keys.duplicate()
	selected.sort()
	expected.sort()
	return selected == expected
