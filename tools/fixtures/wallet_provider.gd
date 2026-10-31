extends Node
## Isolated UI test double only. Not a payment verifier or production backend.
var actor := "wallet-test-a"
var delay := 0.0
var lose_create := false
var fail_balance := false
var fail_catalog := false
var fail_records := false
var corrupt_owner := false
var corrupt_created_price := false
var wallet := {"wallet-test-a": 1280, "wallet-test-b": 17}
var revisions := {"wallet-test-a": 0, "wallet-test-b": 0}
var orders: Dictionary = {}
var intents: Dictionary = {}
var ledger: Array = []
var calls: Array = []
var attempts: Dictionary = {}
var quiz_enabled := false
var practices: Dictionary = {}
var lose_practice_finish := false
var nickname := "禹浩"
var package_rows: Array = []
var channel_rows := [{"id": "test-wechat", "label": "微信支付 · 测试", "brand": "wechat-pay", "enabled": true}, {"id": "test-alipay", "label": "支付宝 · 测试", "brand": "alipay", "enabled": true}]

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("workbench-check-"))
	for cents in [300, 600, 1200, 3000]:
		package_rows.append({"id": "preview-" + str(cents), "version": "v1", "price_cents": cents, "batteries": cents, "currency": "CNY", "enabled": true})

func request_profile(account: String) -> Dictionary:
	return {"ok": true, "account_id": account, "profile": {"display_name": nickname if account == "wallet-test-a" else "测试账号 B", "public_id": "PREVIEW-A" if account == "wallet-test-a" else "PREVIEW-B"}, "editable_fields": {}}

func wallet_payment_hosts() -> Array: return ["pay.example.invalid"]

func wallet_request(action: String, payload: Dictionary) -> Dictionary:
	var account := actor
	calls.append({"action": action, "payload": payload.duplicate(true), "actor": account})
	var response := execute(account, action, payload)
	if delay > 0: await get_tree().create_timer(delay).timeout
	if action == "create_order" and lose_create:
		lose_create = false
		return {"ok": false, "account_id": account, "code": "unknown"}
	if action == "practice_finish" and lose_practice_finish:
		lose_practice_finish = false
		return {"ok": false, "account_id": account, "code": "unknown"}
	if corrupt_owner: response.account_id = "not-this-user"
	if corrupt_created_price and action == "create_order" and response.get("order") is Dictionary:
		response.order.price_cents += 1
	return response

func execute(account: String, action: String, p: Dictionary) -> Dictionary:
	var data := {"ok": true, "account_id": account}
	match action:
		"balance":
			if fail_balance: return fail(account, "unknown")
			data.merge({"balance": wallet[account], "revision": revisions[account]})
		"catalog":
			if fail_catalog: return fail(account, "unknown")
			data.merge({"packages": package_rows.duplicate(true), "channels": channel_rows.duplicate(true), "preview": true, "recharge_enabled": true, "default_package_id": "preview-600", "rules": {"summary": "充值档位与兑换比例仅作设计示意", "description": "隔离预览：¥1 = 100 电池，不用于真实收款。", "quiz": {"enabled": quiz_enabled, "trusted_attempts": quiz_enabled, "practice_batches": quiz_enabled, "types": ["single", "multiple", "judge"], "bank_versions": {"marxism": "fixture-v1"}}, "publication": {"entry_enabled": false}}})
		"create_order":
			var key := account + ":" + str(p.get("request_id", ""))
			if intents.has(key):
				if intents[key].payload != p: return fail(account, "conflict")
				data.order = orders[intents[key].id].duplicate(true)
			else:
				var matches := package_rows.filter(func(item): return item.id == p.get("package_id"))
				if matches.is_empty() or matches[0].version != p.get("package_version"): return fail(account, "price_changed", true)
				var item: Dictionary = matches[0]
				var id := "TEST-ORDER-%04d" % (orders.size() + 1)
				var order := {"id": id, "account_id": account, "account_label": nickname + " · PREVIEW-A", "request_id": p.request_id, "package_id": item.id, "package_version": item.version, "price_cents": item.price_cents, "currency": "CNY", "batteries": item.batteries, "channel": p.channel, "channel_label": "隔离测试渠道", "created_at": "2026-10-28 16:00", "payment_status": "pending", "credit_status": "none", "revision": 1}
				orders[id] = order
				intents[key] = {"payload": p.duplicate(true), "id": id}
				data.order = order.duplicate(true)
		"order":
			var item: Dictionary = orders.get(str(p.get("order_id", "")), {})
			if item.is_empty() or item.account_id != account: return fail(account, "not_found")
			data.order = item.duplicate(true)
		"orders", "ledger":
			if fail_records: return fail(account, "unknown")
			var items: Array = []
			for row in orders.values() if action == "orders" else ledger:
				if row.account_id != account: continue
				if action == "orders" and p.get("scope") == "unfinished" and row.credit_status == "credited": continue
				if action == "ledger" and ((p.get("filter") == "income" and int(row.delta) < 0) or (p.get("filter") == "expense" and int(row.delta) > 0)): continue
				items.append(row.duplicate(true))
			var start := int(p.get("cursor", "0"))
			data.items = items.slice(start, start + 2)
			data.next_cursor = str(start + 2) if items.size() > start + 2 else ""
		"quiz_attempt":
			if not quiz_enabled: return fail(account, "disabled")
			var id := "ATTEMPT-" + str(p.request_id)
			attempts[id] = {"account_id": account, "question_id": p.question_id, "subject_id": p.subject_id, "reward": {}}
			data.attempt_id = id
		"practice_begin":
			if not quiz_enabled: return fail(account, "disabled")
			var id := "PRACTICE-" + str(p.request_id)
			if not practices.has(id): practices[id] = {"account_id":account,"subject_id":p.subject_id,"receipt":{},"answers":[]}
			data.practice_id = id
		"practice_finish":
			var practice: Dictionary = practices.get(str(p.get("practice_id", "")), {})
			if practice.is_empty() or practice.account_id != account: return fail(account, "forbidden")
			if not practice.receipt.is_empty():
				return practice.receipt.duplicate(true) if practice.answers == p.answers else fail(account,"conflict")
			var bank: Array = get_node("/root/StudyStats").banks.get(practice.subject_id, [])
			var count := 0
			var seen: Dictionary = {}
			for answer in p.answers:
				if seen.has(answer.question_id): return fail(account,"conflict")
				seen[answer.question_id] = true
				for question in bank:
					if str(int(question.id)) == str(answer.question_id) and preload("res://scripts/quiz_grader.gd").correct(question, answer.selected_keys, answer.entered_answers): count += 1
			var lid := "TEST-PRACTICE-" + str(ledger.size())
			if count > 0:
				wallet[account] += count; revisions[account] += 1
				ledger.append({"id":lid,"account_id":account,"source":"quiz","delta":count,"reference":p.practice_id,"created_at":"2026-10-31 16:00"})
			data.merge({"reward":{"status":"credited" if count else "ineligible","amount":count,"ledger_id":lid if count else ""},"balance":wallet[account],"revision":revisions[account]})
			practice.answers = p.answers.duplicate(true)
			practice.receipt = data.duplicate(true)
		"quiz_submit":
			var attempt: Dictionary = attempts.get(str(p.get("attempt_id", "")), {})
			if attempt.is_empty() or attempt.account_id != account: return fail(account, "forbidden")
			if attempt.reward.is_empty():
				var bank: Array = get_node("/root/StudyStats").banks.get(attempt.subject_id, [])
				var question: Dictionary = {}
				for row in bank:
					if str(row.id) == str(attempt.question_id): question = row
				var keys: Array = []
				for option in question.get("options", []):
					if option.get("correct", false): keys.append(str(option.key))
				keys.sort()
				if keys.is_empty() or keys != p.get("answer", {}).get("selected_keys", []): attempt.reward = {"status": "ineligible"}
				else:
					var lid := "TEST-QUIZ-" + str(ledger.size())
					wallet[account] += 5
					revisions[account] += 1
					ledger.append({"id": lid, "account_id": account, "source": "quiz", "delta": 5, "reference": p.attempt_id, "created_at": "2026-10-28 16:01"})
					attempt.reward = {"status": "credited", "amount": 5, "ledger_id": lid}
			data.reward = attempt.reward.duplicate(true)
		_: return fail(account, "unavailable")
	return data

func fail(account: String, code: String, definitive := false) -> Dictionary:
	return {"ok": false, "account_id": account, "code": code, "definitive": definitive}

func settle(id: String, credit := true) -> void:
	# Explicit test harness event, never callable by wallet_request or the UI.
	var order: Dictionary = orders[id]
	if order.credit_status == "credited": return
	order.payment_status = "paid"
	order.credit_status = "credited" if credit else "pending"
	order.revision += 1
	if credit:
		wallet[order.account_id] += int(order.batteries)
		revisions[order.account_id] += 1
		order.ledger_id = "TEST-LEDGER-" + id
		ledger.append({"id": order.ledger_id, "account_id": order.account_id, "source": "recharge", "delta": order.batteries, "reference": id, "order_id": id, "created_at": "2026-10-28 16:02"})
