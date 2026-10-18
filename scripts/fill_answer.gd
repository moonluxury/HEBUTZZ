extends RefCounted


static func is_valid(question: Dictionary) -> bool:
	var blanks = question.get("blanks", null)
	if typeof(blanks) != TYPE_ARRAY or blanks.is_empty():
		return false
	for blank in blanks:
		if typeof(blank) != TYPE_DICTIONARY:
			return false
		var answers = blank.get("answers", null)
		if typeof(answers) != TYPE_ARRAY or answers.is_empty():
			return false
		for answer in answers:
			if typeof(answer) != TYPE_STRING or answer.strip_edges().is_empty():
				return false
	return true


static func is_correct(blanks: Array, entered: Array, language: String = "python") -> bool:
	if blanks.size() != entered.size():
		return false
	for index in blanks.size():
		if str(entered[index]).strip_edges().is_empty():
			return false
		var matches := false
		for accepted in blanks[index]["answers"]:
			if normalize(str(entered[index]), language) == normalize(str(accepted), language):
				matches = true
				break
		if not matches:
			return false
	return true


static func normalize(answer: String, language: String = "python") -> String:
	# Compare tokens only: never evaluate or run learner input. Keep identifiers,
	# keyword boundaries and string contents. Only Python permits quote-style changes;
	# C++ character literals and string literals are different types.
	var tokenizer := RegEx.new()
	tokenizer.compile(r""""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[A-Za-z_][A-Za-z_0-9]*|[0-9]+(?:\.[0-9]+)?|->\*|<<=|>>=|::|->|\.\*|\+\+|--|&&|\|\||<<|>>|==|!=|<=|>=|\*\*|//|\+=|-=|\*=|/=|%=|&=|\|=|\^=|\S""")
	var tokens: Array[String] = []
	for match_result in tokenizer.search_all(answer.strip_edges()):
		var token: String = match_result.get_string()
		if language == "python" and token.length() >= 2 and (
			(token.begins_with("'") and token.ends_with("'"))
			or (token.begins_with('"') and token.ends_with('"'))
		):
			token = "string:" + token.substr(1, token.length() - 2)
		tokens.append(token)
	return "\u001f".join(tokens)
