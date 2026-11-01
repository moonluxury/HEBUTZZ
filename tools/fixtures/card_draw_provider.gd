extends "res://tools/fixtures/social_provider.gd"
const RULE := "card-draw-20261102-v1"
var balances := {A: 1000, B: 600, C: 200, D: 0}
var wallet_revisions := {A: 1, B: 1, C: 1, D: 1}
var draw_receipts: Dictionary = {}
var draw_calls: Array = []
var grants := 0
var draw_delay := 0.12
var lose_draw_response := false
var miss_status := false
var invalid_receipt := false

func wallet_request(action: String, payload: Dictionary) -> Dictionary:
	var owner := actor
	if action == "balance": return response(owner, {"balance": balances[owner], "revision": wallet_revisions[owner]})
	if action == "catalog": return response(owner, {"packages": [], "channels": [], "rules": {}, "preview": false, "recharge_enabled": false})
	if action == "card_draw_options":
		return response(owner, {"price": 200, "pool_id": "season-001", "rule_version": RULE, "duplicates": true, "odds": [{"card_id": "0004", "percent": 10}, {"card_id": "0007", "percent": 10}, {"card_id": "0005", "percent": 12}, {"card_id": "0003", "percent": 14}, {"card_id": "0001", "percent": 16}, {"card_id": "0006", "percent": 18}, {"card_id": "0002", "percent": 20}]})
	if action not in ["card_draw", "card_draw_status"]: return failure(owner, "unavailable")
	var key := owner + ":" + str(payload.operation_id)
	if action == "card_draw":
		draw_calls.append(payload.duplicate(true))
		await get_tree().create_timer(draw_delay).timeout
		if not draw_receipts.has(key):
			if balances[owner] < 200: return response(owner, {"ok": false, "code": "insufficient_balance", "state": "failed", "operation_id": payload.operation_id, "definitive": true})
			balances[owner] -= 200
			wallet_revisions[owner] += 1
			stocks[owner]["0004"] = stocks[owner].get("0004", 0) + 1
			revision += 1
			grants += 1
			draw_receipts[key] = {"id": "draw-" + str(grants), "operation_id": payload.operation_id, "card_id": "0004", "quantity": 1, "price": 200, "pool_id": "season-001", "rule_version": RULE, "ledger_id": "ledger-" + str(grants)}
		if lose_draw_response:
			lose_draw_response = false
			return response(owner, {"ok": false, "code": "unknown"})
	if not draw_receipts.has(key) or (action == "card_draw_status" and miss_status):
		return response(owner, {"state": "not_found", "operation_id": payload.operation_id})
	var receipt: Dictionary = draw_receipts[key].duplicate(true)
	if invalid_receipt: receipt.card_id = "not-a-card"
	return response(owner, {"state": "succeeded", "draw": receipt, "balance": balances[owner], "revision": wallet_revisions[owner], "collection": await request_snapshot(owner)})
