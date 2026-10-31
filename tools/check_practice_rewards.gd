extends SceneTree
const Fixture = preload("res://tools/fixtures/wallet_provider.gd")
var failures: Array[String] = []
var assertions := 0

func _init() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); push_error(label)

func frames(count := 8) -> void:
	for i in count: await process_frame

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	await frames()
	var api := Fixture.new(); root.add_child(api); api.quiz_enabled = true
	var profile := root.get_node("ProfileStore")
	profile.use_provider(api,{"state":"authenticated","account_id":api.actor})
	var wallet: Node = root.get_node("AppServices").wallet_store()
	var rewards: Node = root.get_node("AppServices").practice_rewards()
	await frames()
	var question: Dictionary = root.get_node("StudyStats").banks.marxism[0]
	var keys: Array = []
	for option in question.options:
		if option.correct: keys.append(str(option.key))
	keys.sort()
	var first: String = rewards.start("marxism")
	await frames()
	var requests: int = api.calls.size()
	rewards.record(first, question, keys, [], true)
	rewards.record(first, question, keys, [], true)
	rewards.record(first, question, [], [], false)
	await frames()
	check(api.calls.size() == requests and wallet.balance == 1280, "Answering and retrying one question produce no network requests or credit")
	check(rewards.drafts[first].answers.size() == 1 and rewards.drafts[first].answers[str(int(question.id))].selected_keys == keys, "One correct answer per question is retained even after a later wrong retry")
	check(rewards.start("marxism") == first, "Returning to an unfinished practice keeps its original identity")
	api.lose_practice_finish = true
	await rewards.finish(first)
	check(api.wallet[api.actor] == 1281 and wallet.balance == 1280 and rewards.drafts[first].finish_requested, "A lost reply stays pending locally without inventing or duplicating credit")
	var next: String = rewards.start("marxism")
	await frames(18)
	check(not rewards.drafts.has(first) and wallet.balance == 1281 and next != first, "Returning retries only the ended practice and adopts its original receipt")
	rewards.record(next, question, keys, [], true)
	profile.use_provider(api,{"state":"signed_out"})
	await frames()
	check(rewards.drafts.is_empty() and wallet.balance == null, "Logout removes another account's pending data from memory")
	api.actor = "wallet-test-b"
	profile.use_provider(api,{"state":"authenticated","account_id":api.actor})
	await frames()
	check(rewards.drafts.is_empty() and wallet.balance == 17, "A different account cannot settle the old draft")
	api.actor = "wallet-test-a"
	profile.use_provider(api,{"state":"authenticated","account_id":api.actor})
	await frames(18)
	check(rewards.drafts.has(next) and wallet.balance == 1281, "Re-login restores an unfinished draft without automatically rewarding it")
	await rewards.finish(next)
	check(wallet.balance == 1282 and api.wallet[api.actor] == 1282, "The next explicit Finish can reward the question once in a new practice")
	await rewards.finish(next)
	check(wallet.balance == 1282, "Repeated Finish after success is a no-op")
	print("PRACTICE REWARD ASSERTIONS: ", assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
