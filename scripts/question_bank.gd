extends RefCounted
## Shared bundled question-bank loader; no network access.
const FillAnswer = preload("res://scripts/fill_answer.gd")
const OutputAnswer = preload("res://scripts/output_answer.gd")
const TYPE_ORDER := ["single", "multiple", "judge", "fill", "output", "program"]

static func load_file(path: String) -> Array:
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
		if is_valid(raw_question):
			valid_questions.append(raw_question)
		else:
			push_warning("已跳过一条格式不完整的题目数据")
	return group_by_type(valid_questions)


static func group_by_type(questions: Array) -> Array:
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


static func is_valid(value: Variant) -> bool:
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
