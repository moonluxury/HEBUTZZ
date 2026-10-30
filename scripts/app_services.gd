extends Node
## Persistent domain services. Navigation never owns their lifetime.

func _service(node_name: String, script: Script) -> Node:
	var instance := get_node_or_null(node_name)
	if instance == null:
		instance = script.new()
		instance.name = node_name
		add_child(instance)
	return instance

func collection_store() -> Node:
	return _service("CollectionStore", preload("res://scripts/collection_store.gd"))

func social_store() -> Node:
	return _service("SocialStore", preload("res://scripts/social_store.gd"))

func wallet_store() -> Node:
	return _service("WalletStore", preload("res://scripts/wallet_store.gd"))

func wrong_questions() -> Node:
	return _service("WrongQuestions", preload("res://scripts/wrong_question_store.gd"))

func submission_store() -> Node:
	return _service("SubmissionStore", preload("res://scripts/submission_store.gd"))

func quiz_marks() -> Node:
	return _service("QuizMarks", preload("res://scripts/quiz_marks.gd"))

func bank_discussions() -> Node:
	return _service("BankDiscussions", preload("res://scripts/bank_discussion_store.gd"))
