extends SceneTree
const Session = preload("res://scripts/quiz_session.gd")
const Grader = preload("res://scripts/quiz_grader.gd")
const JsonStore = preload("res://scripts/local_json_store.gd")
var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	# Pure session behavior runs without creating any question/page controls.
	var single := {"id": 10, "type": "single", "options": [{"key": "A", "correct": true}, {"key": "B", "correct": false}]}
	var multiple := {"id": 99, "type": "multiple", "options": [{"key": "A", "correct": true}, {"key": "B", "correct": true}, {"key": "C", "correct": false}]}
	var fill := {"id": 500, "type": "fill", "language": "python", "blanks": [{"answers": ["x + 1"]}, {"answers": ["'a'"]}]}
	var output := {"id": 700, "type": "output", "answers": ["1 2\n3 4"]}
	var program := {"id": 800, "type": "program", "source_id": "source-program"}
	var bank: Array = [single, multiple, fill, output, program]
	var original := JSON.stringify(bank)
	var session := Session.new()
	session.configure(bank, {"99": true}, false, 0)
	session.open_question(1)
	var option_a: int = session.shuffled_options.find(multiple.options[0])
	session.select_option(option_a)
	check(not session.is_correct() and not session.has_answered, "Incomplete multiple-choice answer stays unsubmitted and incorrect")
	session.open_question(0)
	session.open_question(1)
	check(session.selected_keys() == ["A"], "Unsubmitted selection survives navigation and reshuffling by stable option key")
	session.select_option(session.shuffled_options.find(multiple.options[1]))
	check(session.is_correct(), "All required choices are graded without UI indices or button order")
	check(session.submit() and not session.submit(), "Only the first submission completes an attempt")
	session.open_question(1)
	check(not session.has_answered and session.selected_indices.is_empty() and session.question_states["99"].answered, "Retry clears the old choice but retains the learned number state")
	session.open_question(2)
	check(session.entered_answers.size() == 2 and session.submission_issue().field == 0, "The model initializes fill fields and identifies the first missing answer")
	session.set_answer(0, "x+1")
	session.set_answer(1, '"a"')
	check(session.is_correct(), "Fill grading preserves accepted Python normalization")
	session.open_question(3)
	session.set_answer(0, "1\t2\r\n3 4")
	check(session.is_correct(), "Output grading preserves whitespace and newline normalization")
	check(not Grader.correct(output, [], ["12\n34"]), "Output grading does not merge distinct tokens")
	session.open_question(4, "print('original')")
	session.set_answer(0, "print('edited')")
	session.set_reference(true)
	session.open_question(0)
	session.open_question(4, "stale disk text")
	check(session.entered_answers[0] == "print('edited')" and session.reference_revealed, "The latest program draft and reference state survive navigation")
	check(JSON.stringify(bank) == original, "Session operations do not mutate shared question data")
	var wrong := Session.new()
	wrong.configure(bank, {"99": true, "700": true}, true, 0)
	check(wrong.questions == [multiple, output], "Wrong practice filters by stable IDs and retains the supplied type order")

	# Exercise a real replacement failure, not a mock of the writer.
	var path := "user://architecture-storage/state.json"
	check(JsonStore.write(path, {"revision": 1, "data": [10, 99]}) == OK, "First atomic save creates its directory")
	var before := FileAccess.get_file_as_string(path)
	check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "Create an unwritable temporary-file target")
	check(JsonStore.write(path, {"revision": 2}) != OK, "A failed temporary write is reported")
	check(FileAccess.get_file_as_string(path) == before, "Failed replacement keeps the previous save byte for byte")
	DirAccess.remove_absolute(path + ".tmp")
	check(JsonStore.write(path, {"revision": 3}) == OK and JsonStore.read(path).revision == 3, "Successful retry replaces the old complete document")
	check(not FileAccess.file_exists(path + ".tmp"), "Successful save leaves no pending temporary file")

	var services := root.get_node("AppServices")
	var collection: Node = services.collection_store()
	var social: Node = services.social_store()
	var wallet: Node = services.wallet_store()
	check(collection.get_parent() == services and social.get_parent() == services and wallet.get_parent() == services, "Domain services outlive pages under their own container")
	check(not root.get_node("PageRouter").has_method("collection_store"), "Navigation is not the service factory")
	for name in DirAccess.get_files_at("res://scenes"):
		if name.ends_with(".tscn"):
			var packed := load("res://scenes/" + name) as PackedScene
			check(packed != null, "Every shipped scene has resolvable resources: " + name)
	print("WORKBENCH CHECKS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
