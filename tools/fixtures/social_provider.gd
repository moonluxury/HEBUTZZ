extends Node
## ISOLATED CLIENT CONTRACT MODEL. This is not a database or a production backend.
const A := "test-account-a"
const B := "test-account-b"
const C := "test-account-c"
const D := "test-account-d"
const Policy = preload("res://scripts/social_policy.gd")
var actor := A
var users := {A: {"id": A, "public_id": "QA-000001", "name": "隔离账号甲"}, B: {"id": B, "public_id": "QA-000002", "name": "隔离账号乙"}, C: {"id": C, "public_id": "QA-000003", "name": "隔离账号丙"}, D: {"id": D, "public_id": "QA-000004", "name": "系统通知"}}
var stocks := {A: {"0001": 5, "0002": 3}, B: {"0001": 2, "0002": 6}, C: {"0001": 2}, D: {"0001": 1}}
var relationships: Dictionary = {}
var blocks: Dictionary = {}
var convs: Dictionary = {}
var logs: Array = []
var requests: Array = []
var trades: Dictionary = {}
var prefs: Dictionary = {}
var read_positions: Dictionary = {}
var request_reads: Dictionary = {}
var receipts: Dictionary = {}
var gifts: Dictionary = {}
var seq := 0
var revision := 0
var transfers := 0
var message_calls := 0
var delay := 0.0
var fail_action := ""
var lose_response := ""
var late_message_on_read := false
var search_delay := false
var reports: Array = []
var wanted := {A: ["0002"], B: ["0001"], C: []}

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("workbench-check"))
	relationships[pair(A, B)] = true
	for id in users:
		convs["system:" + id] = {"id": "system:" + id, "kind": "system", "members": [id]}
	var cid := conversation_for(A, B)
	append(cid, B, "text", {"text": "这张卡的设计很有意思，我们可以交换看看。"})
	append("system:" + A, "", "notification", {"title": "隔离测试通知", "body": "这条通知仅来自测试服务，用于验证只读会话和独立阅读水位。", "event": "announcement"})

func pair(a: String, b: String) -> String:
	return "|".join([a, b] if a < b else [b, a])

func blocked(a: String, b: String) -> bool:
	return blocks.has(a + ":" + b) or blocks.has(b + ":" + a)

func friend(a: String, b: String) -> bool:
	return relationships.get(pair(a, b), false) and not blocked(a, b)

func conversation_for(a: String, b: String) -> String:
	var id := pair(a, b)
	if not convs.has(id):
		convs[id] = {"id": id, "kind": "direct", "members": [a, b]}
	return id

func public_user(id: String, viewer: String) -> Dictionary:
	var person: Dictionary = users[id].duplicate(true)
	person.remark = prefs.get(viewer + ":" + id, {}).get("remark", "")
	return person

func append(cid: String, sender: String, type: String, fields: Dictionary) -> Dictionary:
	seq += 1
	revision += 1
	var message := {"id": "message-%d" % seq, "conversation_id": cid, "sender_id": sender, "type": type, "seq": seq, "date_label": "2026-10-28", "time_label": "14:%02d" % (seq % 60)}
	message.merge(fields, true)
	logs.append(message)
	return message

func response(account: String, fields: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "account_id": account}
	result.merge(fields, true)
	return result

func failure(account: String, code: String, message := "隔离测试：请求被拒绝。") -> Dictionary:
	return response(account, {"ok": false, "code": code, "message": message, "definitive": true})

func request_profile(account: String) -> Dictionary:
	return response(account, {"profile": {"public_id": users[account].public_id, "display_name": users[account].name}, "editable_fields": {}})

func request_snapshot(account: String) -> Dictionary:
	var inventory := {}
	for id in stocks[account]:
		inventory[id] = {"count": stocks[account][id], "giftable_count": maxi(0, stocks[account][id] - 1), "exchangeable_count": stocks[account][id]}
	return response(account, {"inventory_complete": true, "revision": revision, "inventory": inventory})

func request_friends(account: String, query: String) -> Dictionary:
	return response(account, {"friends": friend_rows(account, query)})

func friend_rows(account: String, query := "") -> Array:
	var found := []
	for id in users:
		if id != account and friend(account, id):
			var person := public_user(id, account)
			if not query.is_empty() and not query in JSON.stringify(person):
				continue
			person.eligible = true
			person.conversation_id = pair(account, id) if convs.has(pair(account, id)) else ""
			found.append(person)
	return found

func snapshot(account: String, after := 0) -> Dictionary:
	var rows := []
	var visible_messages := []
	for conv in convs.values():
		if not account in conv.members:
			continue
		var value: Dictionary = conv.duplicate(true)
		value.erase("members")
		var last := {}
		var unread := 0
		value.read_seq = read_positions.get(account + ":" + conv.id, 0)
		for message in logs:
			if message.conversation_id != conv.id:
				continue
			last = message
			if message.seq > value.read_seq and message.sender_id != account:
				unread += 1
			if message.seq > after:
				visible_messages.append(message.duplicate(true))
		value.unread = unread
		value.activity_seq = last.get("seq", 0)
		value.summary = last.get("text", last.get("title", "换卡邀请" if last.get("type") == "trade" else ""))
		value.time_label = last.get("time_label", "")
		if conv.kind == "system":
			value.name = "系统通知"
			value.can_send = false
		else:
			var peer_id: String = conv.members[1] if conv.members[0] == account else conv.members[0]
			value.peer = public_user(peer_id, account)
			value.is_friend = friend(account, peer_id)
			value.blocked_by_me = blocks.has(account + ":" + peer_id)
			value.muted = prefs.get(account + ":" + peer_id, {}).get("muted", false)
			value.can_send = may_send(account, peer_id, conv.id)
			value.send_reason = "已拉黑，无法发送。" if blocked(account, peer_id) else "已发送一条招呼，请等待对方回复。"
		rows.append(value)
	var visible_requests := []
	var pending := 0
	var request_unread := 0
	for item in requests:
		if account not in [item.sender, item.recipient]:
			continue
		var value: Dictionary = item.duplicate(true)
		value.direction = "received" if item.recipient == account else "sent"
		value.peer = public_user(item.sender if item.recipient == account else item.recipient, account)
		visible_requests.append(value)
		if item.recipient == account:
			if item.status == "pending": pending += 1
			if item.seq > request_reads.get(account, 0): request_unread += 1
	var visible_trades := []
	for trade in trades.values():
		if account in [trade.initiator_id, trade.recipient_id]:
			visible_trades.append(trade.duplicate(true))
	return response(account, {"revision": revision, "cursor": str(seq), "friends": friend_rows(account), "conversations": rows, "requests": visible_requests, "pending_requests": pending, "request_unread": request_unread, "messages": visible_messages, "trades": visible_trades, "capabilities": {"exchange": true, "reports": true}})

func may_send(account: String, peer_id: String, cid: String) -> bool:
	if blocked(account, peer_id): return false
	if friend(account, peer_id): return true
	var sent := false
	var replied := false
	for message in logs:
		if message.conversation_id == cid and message.type == "text":
			sent = sent or message.sender_id == account
			replied = replied or message.sender_id == peer_id
	return not sent or replied

func social_request(action: String, payload: Dictionary) -> Dictionary:
	var owner := actor # Simulates server-bound credentials, never payload identity.
	var result := execute(owner, action, payload)
	if action == "find_user" and search_delay:
		await get_tree().create_timer(0.12 if payload.get("public_id") == users[B].public_id else 0.01).timeout
	elif delay > 0:
		await get_tree().create_timer(delay).timeout
	if lose_response == action:
		lose_response = ""
		return response(owner, {"ok": false, "code": "unknown", "message": "隔离测试：响应丢失，使用原操作重试。"})
	return result

func execute(account: String, action: String, p: Dictionary) -> Dictionary:
	if fail_action == action:
		return response(account, {"ok": false, "code": "network", "message": "隔离测试：网络连接失败。"})
	for forbidden in ["sender_id", "account_id", "actor_id", "type", "status"]:
		if p.has(forbidden): return failure(account, "forged_field")
	var key := account + ":" + str(p.get("client_id", p.get("operation_id", "")))
	var fingerprint := action + JSON.stringify(p, "", true)
	var idempotent := p.has("client_id") or p.has("operation_id")
	if idempotent and receipts.has(key):
		if receipts[key].fingerprint != fingerprint: return failure(account, "idempotency_conflict")
		return receipts[key].response.duplicate(true)
	var result := apply(account, action, p)
	if idempotent and result.get("ok", false):
		receipts[key] = {"fingerprint": fingerprint, "response": result.duplicate(true)}
	return result

func apply(account: String, action: String, p: Dictionary) -> Dictionary:
	match action:
		"sync": return snapshot(account, int(p.get("cursor", "0")))
		"friends": return request_friends(account, str(p.get("query", "")))
		"find_user":
			for id in users:
				if users[id].public_id == p.get("public_id"):
					var state := "self" if id == account else "inaccessible" if blocked(account, id) else "friend" if friend(account, id) else "available"
					for item in requests:
						if pair(item.sender, item.recipient) == pair(account, id) and item.status == "pending":
							state = "outgoing" if item.sender == account else "incoming"
					return response(account, {"state": state, "user": public_user(id, account) if state != "inaccessible" else {}})
			return response(account, {"state": "not_found"})
		"open_conversation":
			var id := str(p.get("peer_id", ""))
			if id == account or not users.has(id) or blocked(account, id): return failure(account, "inaccessible")
			var cid := conversation_for(account, id)
			revision += 1
			var snap := snapshot(account)
			for value in snap.conversations:
				if value.id == cid: return response(account, {"conversation": value, "sync": snap})
		"history":
			var cid := str(p.get("conversation_id", ""))
			if not owns(account, cid): return failure(account, "forbidden")
			var found := []
			var before := int(p.get("before", "0"))
			for message in logs:
				if message.conversation_id == cid and (before == 0 or message.seq < before): found.append(message.duplicate(true))
			var limit := mini(40, int(p.get("limit", 40)))
			var next := str(found[maxi(0, found.size() - limit)].seq) if found.size() > limit else ""
			return response(account, {"messages": found.slice(maxi(0, found.size() - limit)), "next_before": next})
		"send_text":
			message_calls += 1
			var cid := str(p.get("conversation_id", ""))
			if not owns(account, cid) or convs[cid].kind != "direct": return failure(account, "forbidden")
			var peer_id: String = convs[cid].members[1] if convs[cid].members[0] == account else convs[cid].members[0]
			if not may_send(account, peer_id, cid): return failure(account, "greeting_limit")
			var body := str(p.get("text", ""))
			if body.strip_edges().is_empty() or body.length() > Policy.TEXT_LIMIT: return failure(account, "invalid_text")
			return response(account, {"message_record": append(cid, account, "text", {"text": body, "client_id": p.client_id})})
		"request_friend":
			var id := str(p.get("peer_id", ""))
			if id == account or not users.has(id) or blocked(account, id): return failure(account, "inaccessible")
			if Policy.note_length(str(p.get("note", ""))) > Policy.NOTE_LIMIT: return failure(account, "invalid_note")
			for item in requests:
				if pair(item.sender, item.recipient) == pair(account, id) and item.status == "pending":
					return response(account, {"request": item, "sync": snapshot(account), "message": "已有有效申请，请接收方处理。"})
			if friend(account, id): return response(account, {"message": "已经是好友。"})
			seq += 1
			revision += 1
			var item := {"id": "request-%d" % seq, "sender": account, "recipient": id, "status": "pending", "note": p.get("note", ""), "seq": seq, "time_label": "2026-10-28 14:00"}
			requests.append(item)
			return response(account, {"request": item, "sync": snapshot(account), "message": "申请已发送。"})
		"respond_request":
			for item in requests:
				if item.id == p.get("request_id"):
					if item.recipient != account or blocked(item.sender, item.recipient): return failure(account, "forbidden")
					if item.status == "pending":
						item.status = "accepted" if p.get("decision") == "accept" else "ignored"
						if item.status == "accepted": relationships[pair(item.sender, item.recipient)] = true
						revision += 1
					return response(account, {"sync": snapshot(account)})
			return failure(account, "not_found")
		"preferences":
			var key := account + ":" + str(p.get("peer_id", ""))
			if not users.has(p.get("peer_id")): return failure(account, "not_found")
			if not prefs.has(key): prefs[key] = {}
			if p.has("remark"): prefs[key].remark = str(p.remark).left(Policy.REMARK_LIMIT)
			if p.has("muted"): prefs[key].muted = bool(p.muted)
			revision += 1
			return response(account, {"sync": snapshot(account)})
		"relationship":
			var id := str(p.get("peer_id", ""))
			if id == account or not users.has(id): return failure(account, "inaccessible")
			match p.get("operation"):
				"remove": relationships.erase(pair(account, id))
				"block":
					blocks[account + ":" + id] = true
					relationships.erase(pair(account, id))
				"unblock": blocks.erase(account + ":" + id)
				_: return failure(account, "invalid_action")
			if p.operation != "unblock":
				for trade in trades.values():
					if pair(trade.initiator_id, trade.recipient_id) == pair(account, id) and trade.status == "pending":
						trade.status = "invalidated"
						trade.revision += 1
				for item in requests:
					if pair(item.sender, item.recipient) == pair(account, id) and item.status == "pending": item.status = "invalidated"
			revision += 1
			return response(account, {"sync": snapshot(account)})
		"blacklist":
			var found := []
			for id in users:
				if blocks.has(account + ":" + id): found.append(public_user(id, account))
			return response(account, {"users": found})
		"wishlist":
			if not friend(account, str(p.get("peer_id", ""))): return failure(account, "forbidden")
			return response(account, {"visibility": "accessible", "card_ids": wanted.get(p.peer_id, [])})
		"mark_read", "mark_all_read", "mark_requests_read":
			var watermark := seq
			if action == "mark_read":
				var cid := str(p.get("conversation_id", ""))
				if not owns(account, cid): return failure(account, "forbidden")
				read_positions[account + ":" + cid] = maxi(read_positions.get(account + ":" + cid, 0), mini(watermark, int(p.get("through_seq", 0))))
			elif action == "mark_all_read":
				for cid in convs:
					if owns(account, cid): read_positions[account + ":" + cid] = watermark
			if action == "mark_all_read": request_reads[account] = watermark
			elif action == "mark_requests_read": request_reads[account] = maxi(request_reads.get(account, 0), mini(watermark, int(p.get("through_seq", 0))))
			revision += 1
			if late_message_on_read:
				late_message_on_read = false
				append("system:" + account, "", "notification", {"title": "水位后通知", "body": "应继续保持未读"})
			return response(account, {"sync": snapshot(account)})
		"create_trade": return create_trade(account, p)
		"trade_action": return trade_action(account, p)
		"trade_detail":
			var trade: Dictionary = trades.get(str(p.get("record_id", "")), {})
			if trade.is_empty() or account not in [trade.initiator_id, trade.recipient_id]: return failure(account, "forbidden")
			return response(account, {"trade": trade.duplicate(true)})
		"trade_records":
			var found := []
			for trade in trades.values():
				if account in [trade.initiator_id, trade.recipient_id] and (str(p.get("peer_id", "")).is_empty() or p.peer_id in [trade.initiator_id, trade.recipient_id]): found.push_front(trade.duplicate(true))
			var start := int(p.get("before", "0"))
			return response(account, {"trades": found.slice(start, start + 40), "next_before": str(start + 40) if found.size() > start + 40 else ""})
		"gift_detail":
			var value: Dictionary = gifts.get(str(p.get("record_id", "")), {})
			if value.is_empty() or account not in [value.sender, value.recipient]: return failure(account, "forbidden")
			return response(account, {"gift": value})
		"report":
			for id in p.get("message_ids", []):
				var allowed := false
				for message in logs:
					if message.id == id and message.conversation_id == pair(account, str(p.get("peer_id", ""))): allowed = true
				if not allowed: return failure(account, "forbidden")
			reports.append(p.duplicate(true))
			return response(account, {"message": "隔离举报接收器已接收。"})
	return failure(account, "unsupported")

func owns(account: String, cid: String) -> bool:
	return convs.has(cid) and account in convs[cid].members

func totals(lines: Array) -> Dictionary:
	var result := {}
	for line in lines:
		var quantity: Variant = line.get("quantity", 0)
		if not (quantity is int or quantity is float) or quantity <= 0 or quantity != floor(quantity) or line.get("season_id") != "season-001" or str(line.get("card_id", "")) not in ["0001", "0002", "0003", "0004", "0005", "0006", "0007"]: return {}
		result[line.card_id] = int(result.get(line.card_id, 0)) + int(quantity)
	return result

func enough(account: String, amount: Dictionary) -> bool:
	if amount.is_empty(): return false
	for id in amount:
		if int(stocks[account].get(id, 0)) < int(amount[id]): return false
	return true

func create_trade(account: String, p: Dictionary) -> Dictionary:
	var target := str(p.get("peer_id", ""))
	if not friend(account, target): return failure(account, "forbidden")
	var give := totals(p.get("give", []))
	var receive := totals(p.get("receive", []))
	if not enough(account, give) or receive.is_empty(): return failure(account, "invalid_stock")
	var id := "trade-%d" % (trades.size() + 1)
	var trade := {"id": id, "initiator_id": account, "recipient_id": target, "initiator": public_user(account, account), "recipient": public_user(target, account), "give": p.give.duplicate(true), "receive": p.receive.duplicate(true), "terms_version": 1, "revision": 1, "status": "pending", "conversation_id": conversation_for(account, target), "time_label": "2026-10-28 14:12"}
	trades[id] = trade
	append(trade.conversation_id, account, "trade", {"record_id": id})
	return response(account, {"trade": trade.duplicate(true), "sync": snapshot(account)})

func trade_action(account: String, p: Dictionary) -> Dictionary:
	var trade: Dictionary = trades.get(str(p.get("trade_id", "")), {})
	if trade.is_empty(): return failure(account, "forbidden")
	var decision := str(p.get("decision", ""))
	if account != (trade.initiator_id if decision == "cancel" else trade.recipient_id): return failure(account, "forbidden")
	if int(p.get("terms_version", -1)) != trade.terms_version: return failure(account, "terms_changed")
	if trade.status != "pending": return response(account, {"trade": trade.duplicate(true)})
	if not friend(trade.initiator_id, trade.recipient_id):
		trade.status = "invalidated"
	elif decision == "cancel": trade.status = "cancelled"
	elif decision == "reject": trade.status = "rejected"
	elif decision == "confirm":
		var outgoing := totals(trade.give)
		var incoming := totals(trade.receive)
		if not enough(trade.initiator_id, outgoing) or not enough(trade.recipient_id, incoming): return failure(account, "insufficient_stock", "隔离测试：库存不足，未交割，邀请仍待确认。")
		# Single synchronous model transition, NOT proof of database transaction safety.
		for id in outgoing:
			stocks[trade.initiator_id][id] -= outgoing[id]
		for id in incoming:
			stocks[trade.recipient_id][id] -= incoming[id]
		for id in outgoing:
			stocks[trade.recipient_id][id] = int(stocks[trade.recipient_id].get(id, 0)) + outgoing[id]
		for id in incoming:
			stocks[trade.initiator_id][id] = int(stocks[trade.initiator_id].get(id, 0)) + incoming[id]
		trade.status = "completed"
		transfers += 1
	else: return failure(account, "invalid_action")
	trade.revision += 1
	revision += 1
	return response(account, {"trade": trade.duplicate(true), "sync": snapshot(account)})

func send_gift(operation: Dictionary) -> Dictionary:
	var owner := actor
	var key := owner + ":gift:" + str(operation.id)
	var fingerprint := JSON.stringify([owner, operation.card_id, operation.friend_id, operation.quantity])
	if receipts.has(key):
		if receipts[key].fingerprint != fingerprint: return failure(owner, "idempotency_conflict")
		return receipts[key].response.duplicate(true)
	var result := await request_snapshot(owner)
	result.operation_id = operation.id
	result.state = "failed"
	var id := str(operation.card_id)
	var target := str(operation.friend_id)
	var n := int(operation.quantity)
	if owner != operation.account_id or not friend(owner, target) or n < 1 or int(stocks[owner].get(id, 0)) - n < 1:
		result.message = "隔离测试：好友资格或赠送保留一张规则不满足。"
	else:
		stocks[owner][id] -= n
		stocks[target][id] = int(stocks[target].get(id, 0)) + n
		revision += 1
		transfers += 1
		result.merge(await request_snapshot(owner), true)
		result.state = "succeeded"
		var record := {"sender": owner, "recipient": target, "summary": "%s 向 %s 赠送 %s ×%d" % [users[owner].name, users[target].name, id, n], "time_label": "14:20"}
		gifts[operation.id] = record
		append(conversation_for(owner, target), owner, "gift", {"record_id": operation.id, "title": "赠送成功", "summary": record.summary})
	receipts[key] = {"fingerprint": fingerprint, "response": result.duplicate(true)}
	return result

func gift_status(account: String, id: String) -> Dictionary:
	return receipts.get(account + ":gift:" + id, {}).get("response", {"state": "unknown"})
