extends Node
## ONLY loaded by check_collection.gd after its isolated-save guard.
var inventory := {"0001": {"count": 3, "giftable_count": 3}, "0002": {"count": 1, "giftable_count": 1}, "0003": {"count": 0, "giftable_count": 0}, "0004": {"count": 2, "giftable_count": 0, "gift_reason": "隔离测试：本卡暂不可赠送"}}
var revision := 1
var mode := "success"
var calls := 0
var transfers := 0
var credits: Dictionary = {}
var operations: Dictionary = {}
var snapshot_delay := 0
var friends_fail := false
var snapshot_fail := false
var friend_data := [{"id": "test-friend-a", "name": "测试好友甲", "eligible": true, "avatar_card_id": "0004"}, {"id": "test-friend-b", "name": "测试好友乙", "eligible": true}]

func snapshot(account: String) -> Dictionary:
	return {"ok": true, "account_id": account, "inventory_complete": true, "revision": revision, "inventory": inventory.duplicate(true)}

func request_snapshot(account: String) -> Dictionary:
	if snapshot_fail:
		return {"ok": false, "message": "隔离测试：网络连接失败，请重试。"}
	var response := snapshot(account)
	var frames := snapshot_delay
	for index in frames:
		await get_tree().process_frame
	return response

func request_friends(_account: String, query: String) -> Dictionary:
	for index in (5 if query == "甲" else 1):
		await get_tree().process_frame
	if friends_fail:
		return {"ok": false, "message": "隔离测试：好友网络连接失败。"}
	var result: Array = []
	for friend in friend_data:
		if query.is_empty() or query in str(friend.name) or query in str(friend.id):
			result.append(friend.duplicate(true))
	return {"ok": true, "friends": result}

func send_gift(operation: Dictionary) -> Dictionary:
	calls += 1
	for index in 3:
		await get_tree().process_frame
	if operations.has(operation.id):
		return operations[operation.id].duplicate(true)
	var response := snapshot(operation.account_id)
	response.operation_id = operation.id
	response.state = "failed"
	if mode == "quota":
		response.message = "隔离测试：服务返回额度不足。"
	elif mode == "stock":
		inventory[operation.card_id].count = 0
		inventory[operation.card_id].giftable_count = 0
		revision += 1
		response.merge(snapshot(operation.account_id), true)
		response.message = "隔离测试：库存不足。"
	elif operation.quantity < 1 or operation.quantity > int(inventory[operation.card_id].giftable_count) or operation.friend_id not in ["test-friend-a", "test-friend-b"]:
		response.message = "隔离测试：赠送资格校验失败。"
	elif int(inventory[operation.card_id].count) - int(operation.quantity) < 1:
		# Model the authoritative transaction's retain-one check, including stale reads.
		response.message = "隔离测试：每种卡片需至少保留 1 张。"
	else:
		inventory[operation.card_id].count -= operation.quantity
		inventory[operation.card_id].giftable_count -= operation.quantity
		credits[operation.friend_id] = int(credits.get(operation.friend_id, 0)) + operation.quantity
		transfers += 1
		revision += 1
		response.merge(snapshot(operation.account_id), true)
		response.state = "succeeded"
	operations[operation.id] = response.duplicate(true)
	if mode == "unknown":
		return {"state": "unknown"}
	return response

func gift_status(_account: String, id: String) -> Dictionary:
	await get_tree().process_frame
	return operations.get(id, {"state": "unknown"}).duplicate(true)
