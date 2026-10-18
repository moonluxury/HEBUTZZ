extends RefCounted


static func is_valid(question: Dictionary) -> bool:
	var answers = question.get("answers", null)
	if typeof(answers) != TYPE_ARRAY or answers.is_empty():
		return false
	for answer in answers:
		if typeof(answer) != TYPE_STRING or answer.strip_edges().is_empty():
			return false
	return true


static func is_correct(answers: Array, entered: String, mode: String = "literal") -> bool:
	if entered.strip_edges().is_empty():
		return false
	var normalized := normalize(entered)
	if mode == "python_value":
		var fill_answer = preload("res://scripts/fill_answer.gd")
		for accepted in answers:
			if fill_answer.normalize(entered) == fill_answer.normalize(str(accepted)):
				return true
		return false
	for accepted in answers:
		if normalized == normalize(str(accepted)):
			return true
	return false


static func normalize(output: String) -> String:
	# Outputs are literal text, not source code: never merge "6 2" into "62",
	# discard punctuation, change case, or remove meaningful line breaks.
	var horizontal_space := RegEx.new()
	horizontal_space.compile("[ \\t]+")
	var lines: Array[String] = []
	for line in output.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
		lines.append(horizontal_space.sub(line.strip_edges(), " ", true))
	return "\n".join(lines).strip_edges()
