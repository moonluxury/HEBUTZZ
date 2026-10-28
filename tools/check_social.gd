extends SceneTree
const Fixture = preload("res://tools/fixtures/social_provider.gd")
var failures: Array[String] = []
var assertions := 0
var router: Node
var profile: Node
var social: Node
var backend: Node
var page: Node
var captures := "res://outputs/social-validation"

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(n := 6) -> void:
	for i in n: await process_frame

func key(window: Window, code: Key, shift := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.shift_pressed = shift
		(root if window.is_embedded() else window).push_input(event)

func visit(name: String) -> Node:
	router.go("res://scenes/" + name + ".tscn")
	await scene_changed
	await frames()
	return current_scene

func capture(name: String, fixture := true) -> void:
	if DisplayServer.get_name() == "headless": return
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	var label := Label.new()
	label.text = "实际 Godot 运行 · 隔离服务替身 / 非正式账号与交易" if fixture else "实际 Godot 运行 · 正式服务尚未接入"
	label.position = Vector2(322, 6)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#092C87"))
	layer.add_child(label)
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(captures.path_join(name + ".png"))
	layer.queue_free()

func login(account: String) -> void:
	backend.actor = account
	profile.use_provider(backend, {"state": "authenticated", "account_id": account})
	router.collection_store().refresh()
	await frames()

func labels(node: Node) -> String:
	var result := ""
	for label in node.find_children("*", "Label", true, false): result += label.text + "\n"
	return result

func dialog(mode: String, context: Dictionary = {}) -> Node:
	page.show_panel(mode, context)
	await frames()
	return page.dialog

func close_dialog() -> void:
	if is_instance_valid(page.dialog): page.dialog.dismiss()
	await frames()

func terms(target: String, give_count := 1, receive_count := 1, same := false) -> Dictionary:
	return {"peer_id": target, "give": [{"card_id": "0001", "season_id": "season-001", "quantity": give_count}], "receive": [{"card_id": "0001" if same else "0002", "season_id": "season-001", "quantity": receive_count}], "terms_version": 1}

func call_as(account: String, action: String, payload: Dictionary) -> Dictionary:
	return backend.execute(account, action, payload)

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	await frames()
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	DirAccess.make_dir_recursive_absolute(captures)
	router = root.get_node("PageRouter")
	profile = root.get_node("ProfileStore")
	root.get_node("UiMotion").set_enabled(false)
	page = await visit("MyFriends")
	social = router.social_store()
	check(page.active_nav == "FriendsButton" and page.sidebar.has_node("FriendsButton"), "Friends is the single additional global navigation entry")
	check(page.sidebar.get_node("FriendsButton").position.y > page.sidebar.get_node("CollectionButton").position.y, "Navigation order and identity header are retained")
	check(social.friends.is_empty() and social.conversations.is_empty() and not social.available(), "Production mode has no seeded accounts, contacts or official impersonation")
	check(page.connection.text.contains("未登录") and not page.composer.visible, "Unavailable authentication is visible and never succeeds locally")
	check(not labels(page).contains("消息请求"), "No request inbox, renamed inbox or placeholder")
	await capture("00-unconfigured", false)
	backend = Fixture.new()
	root.add_child(backend)
	await login(Fixture.A)
	check(social.available() and social.friends.size() == 1, "Existing host session supplies social and collection adapters")
	check(social.conversations.size() == 2, "Server supplies exactly one private official channel plus ordinary conversation")
	social.set_tab("recent")
	check(social.list_items("")[0].kind == "system", "Official conversation is first in recent conversations")
	social.set_tab("friends")
	check(social.list_items("").size() == 1, "Official channel is excluded from friends")
	backend.relationships[backend.pair(Fixture.A, Fixture.D)] = true
	backend.revision += 1
	social.refresh()
	check(social.list_items("").size() == 2, "Friend without last message is present")
	check(social.list_items("QA-000004").size() == 1 and social.list_items("系统通知")[0].id == Fixture.D, "Public ID search and ordinary names do not grant official identity")
	backend.relationships.erase(backend.pair(Fixture.A, Fixture.D))
	backend.revision += 1
	social.refresh()
	page._select(backend.pair(Fixture.A, Fixture.B))
	await frames()
	check(page.composer.visible and page.wants_button.visible, "Friend header and composer are connected")
	page.composer.text = "中文草稿"
	page._draft_changed()
	page.composer.composing = true
	page._send()
	check(backend.message_calls == 0 and page.composer.text == "中文草稿", "IME composition cannot send from button/shortcut submission path")
	page.composer.composing = false
	page.composer.text = "  \n "
	page._draft_changed()
	page._send()
	check(backend.message_calls == 0, "Whitespace cannot be submitted")
	page.composer.text = "[b]普通文本[/b] <script>alert(1)</script>"
	page._draft_changed()
	backend.delay = 0.08
	social._wait = 60.0 # Keep this loss/retry scenario independent of the poll timer.
	# Read receipts also include a sync snapshot and can confirm the accepted
	# message before retry. Isolate that separate reconciliation path here.
	page.set_process(false)
	backend.lose_response = "send_text"
	page._send()
	page._send()
	page.composer.text = "后续草稿不能被回执清空"
	page._draft_changed()
	await create_timer(0.12).timeout
	backend.delay = 0
	var cid: String = backend.pair(Fixture.A, Fixture.B)
	var rows: Array = social.messages[cid]
	var message: Dictionary = rows[-1]
	check(message.state == "failed" and page.composer.text == "后续草稿不能被回执清空", "Lost receipt retains retry bubble and newer draft")
	var count_before: int = backend.logs.size()
	social.retry_text(cid, message.client_id)
	await frames()
	check(backend.logs.size() == count_before and message.state == "sent", "Retry uses original client ID; server accepted once")
	page.set_process(true)
	var saved_message: Dictionary = backend.logs[-1]
	social.merge_message(saved_message)
	social.merge_message(saved_message)
	check(social.messages[cid].filter(func(m): return m.get("id") == saved_message.id).size() == 1, "History, sync and receipt merge into one stable bubble")
	check(labels(page.message_rows).contains("[b]普通文本[/b] <script>"), "Message text is a plain Label with no BBCode/HTML execution")
	page.composer.text = "同步响应也必须清空本条草稿"
	page._draft_changed()
	page._send()
	check(page.composer.text.is_empty() and social.drafts.get(cid, "").is_empty(), "Synchronous successful response cannot restore submitted draft")
	page.composer.text = "快捷键测试"
	page._draft_changed()
	page.composer.grab_focus()
	var calls: int = backend.message_calls
	key(root, KEY_ENTER, true)
	await frames()
	check(page.composer.text.contains("\n") and backend.message_calls == calls, "Shift Enter inserts newline without submission through real input dispatch")
	key(root, KEY_ENTER)
	await frames()
	check(page.composer.text.is_empty() and backend.message_calls == calls + 1, "Enter submits through the same composer handler")
	page.composer.text = "后续草稿不能被回执清空"
	page._draft_changed()
	var conflict := call_as(Fixture.A, "send_text", {"conversation_id": cid, "client_id": message.client_id, "text": "changed"})
	check(conflict.code == "idempotency_conflict", "Contract model rejects changed text using original key")
	var stranger: String = backend.conversation_for(Fixture.A, Fixture.C)
	var hello := call_as(Fixture.A, "send_text", {"conversation_id": stranger, "client_id": "hello-a", "text": "你好"})
	check(hello.ok, "First stranger greeting accepted")
	check(not call_as(Fixture.A, "send_text", {"conversation_id": stranger, "client_id": "hello-a2", "text": "第二条"}).ok, "Second unreturned greeting rejected")
	check(call_as(Fixture.A, "send_text", {"conversation_id": stranger, "client_id": "hello-a", "text": "你好"}).ok, "Greeting retry is idempotent")
	check(not call_as(Fixture.A, "create_trade", terms(Fixture.C)).ok, "Strangers cannot exchange cards")
	check(not call_as(Fixture.C, "wishlist", {"peer_id": Fixture.B}).ok, "Private wishlists require friendship")
	check(call_as(Fixture.C, "send_text", {"conversation_id": stranger, "client_id": "reply", "text": "你好！"}).ok, "Recipient may reply to stranger greeting")
	check(call_as(Fixture.A, "send_text", {"conversation_id": stranger, "client_id": "continued", "text": "谢谢回复"}).ok and not backend.friend(Fixture.A, Fixture.C), "Reply permits text continuation without adding friendship")
	var request := call_as(Fixture.A, "request_friend", {"peer_id": Fixture.C, "note": "一起学习", "operation_id": "request-a"})
	var cross := call_as(Fixture.C, "request_friend", {"peer_id": Fixture.A, "note": "交叉申请", "operation_id": "request-c"})
	check(request.request.id == cross.request.id and backend.requests.size() == 1 and not backend.friend(Fixture.A, Fixture.C), "Crossed requests share one pending request without auto-accept")
	check(call_as(Fixture.A, "request_friend", {"peer_id": Fixture.C, "note": "重复", "operation_id": "request-a2"}).request.id == request.request.id, "Duplicate requests do not create extra relationships")
	check(not call_as(Fixture.A, "respond_request", {"request_id": request.request.id, "decision": "accept"}).ok, "Sender cannot accept its own request")
	check(not call_as(Fixture.A, "request_friend", {"peer_id": Fixture.A}).ok, "Self request is rejected")
	check(not call_as(Fixture.A, "request_friend", {"peer_id": "system:" + Fixture.A}).ok, "Official channel cannot receive a friend request")
	social.refresh()
	await dialog("requests")
	await capture("03-friend-requests")
	await close_dialog()
	var accept := {"request_id": request.request.id, "decision": "accept", "operation_id": "accept-c"}
	check(call_as(Fixture.C, "respond_request", accept).ok and call_as(Fixture.C, "respond_request", accept).ok and backend.friend(Fixture.A, Fixture.C), "Recipient acceptance and duplicate acceptance return consistent relationship")
	check(not call_as(Fixture.C, "history", {"conversation_id": cid}).ok, "Guessing another conversation ID cannot read history in contract model")
	check(not call_as(Fixture.A, "send_text", {"conversation_id": cid, "client_id": "forge", "text": "fake", "sender_id": Fixture.B}).ok, "Client cannot supply sender identity")
	check(not call_as(Fixture.A, "send_text", {"conversation_id": cid, "client_id": "forge2", "text": "fake", "type": "trade"}).ok, "Text endpoint rejects forged business events")
	check(not call_as(Fixture.A, "send_text", {"conversation_id": "system:" + Fixture.A, "client_id": "system-forge", "text": "fake"}).ok, "Official channel rejects ordinary user messages")
	await _trades(cid)
	await _views(cid)
	await _session_tests(cid)
	print("SOCIAL ASSERTIONS: %d (client + isolated contract model; NOT production database validation)" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _trades(cid: String) -> void:
	var original: Dictionary = backend.stocks.duplicate(true)
	var terms_a := terms(Fixture.B)
	terms_a.operation_id = "invite-one"
	var created := call_as(Fixture.A, "create_trade", terms_a)
	check(created.ok and backend.stocks == original, "Invitation does not reserve or deduct inventory")
	check(call_as(Fixture.A, "create_trade", terms_a).trade.id == created.trade.id and backend.trades.size() == 1, "Invitation idempotency reuses fixed terms and record")
	var changed := terms_a.duplicate(true)
	changed.give[0].quantity = 2
	check(call_as(Fixture.A, "create_trade", changed).code == "idempotency_conflict", "Invitation ID cannot be reused with edited terms")
	var trade: Dictionary = created.trade
	check(not call_as(Fixture.C, "trade_detail", {"record_id": trade.id}).ok, "Only transaction parties can read details")
	check(not call_as(Fixture.A, "trade_action", {"trade_id": trade.id, "terms_version": 1, "decision": "confirm"}).ok, "Initiator cannot confirm for recipient")
	check(not call_as(Fixture.B, "trade_action", {"trade_id": trade.id, "terms_version": 2, "decision": "confirm"}).ok, "Mismatched terms version is rejected")
	social.refresh()
	page._select(cid)
	await frames()
	await capture("01-friend-conversation")
	check(page.send_button.text == "发送" and page.send_button.get_theme_color("font_color").a > 0.9 and page.send_button.get_theme_color("font_color").get_luminance() > 0.6, "Enabled send button retains readable primary text")
	await login(Fixture.B)
	page._select(cid)
	await frames()
	var panel := await dialog("trade_review", {"trade": trade})
	check(labels(panel).contains("我送出") and labels(panel).contains("人造卫星") and labels(panel).contains("我获得"), "Recipient receives inverse card perspective in review")
	await capture("04-trade-review")
	check(backend.stocks == original, "Opening confirmation does not transfer cards")
	backend.lose_response = "trade_action"
	var operation := {"trade_id": trade.id, "terms_version": 1, "decision": "confirm"}
	panel._mutate("trade_action", operation, "trade_result")
	await frames()
	check(panel.status.text.contains("响应丢失") and backend.transfers == 1, "Lost transaction response remains retryable without claiming rejection")
	panel._mutate("trade_action", operation, "trade_result")
	await frames()
	check(backend.transfers == 1 and backend.trades[trade.id].status == "completed", "Retry after committed transfer returns same completed result")
	check(backend.stocks[Fixture.A]["0001"] == original[Fixture.A]["0001"] - 1 and backend.stocks[Fixture.B]["0002"] == original[Fixture.B]["0002"] - 1, "Model transfers both agreed sides exactly once")
	await capture("05-trade-completed")
	await close_dialog()
	var cancel := call_as(Fixture.A, "trade_action", {"trade_id": trade.id, "terms_version": 1, "decision": "cancel", "operation_id": "late-cancel"})
	check(cancel.trade.status == "completed" and backend.transfers == 1, "Late cancellation cannot reverse completed model transfer")
	await login(Fixture.A)
	var insufficient := call_as(Fixture.A, "create_trade", terms(Fixture.B, 1, 100))
	var before: Dictionary = backend.stocks.duplicate(true)
	var failed := call_as(Fixture.B, "trade_action", {"trade_id": insufficient.trade.id, "terms_version": 1, "decision": "confirm"})
	check(not failed.ok and backend.stocks == before and backend.trades[insufficient.trade.id].status == "pending", "Insufficient inventory leaves both sides untouched and pending")
	var same := terms(Fixture.B, 1, 100, true)
	var same_created := call_as(Fixture.A, "create_trade", same)
	check(not call_as(Fixture.B, "trade_action", {"trade_id": same_created.trade.id, "terms_version": 1, "decision": "confirm"}).ok, "Same-card exchange checks gross outgoing amounts")
	var duplicate := terms(Fixture.B, 3, 1)
	duplicate.give.append(duplicate.give[0].duplicate())
	check(not call_as(Fixture.A, "create_trade", duplicate).ok, "Duplicate lines aggregate before stock validation")
	for n in [0, -1, 1.5]:
		var invalid := terms(Fixture.B)
		invalid.give[0].quantity = n
		check(not call_as(Fixture.A, "create_trade", invalid).ok, "Nonpositive and fractional quantities rejected")
	var wrong_season := terms(Fixture.B)
	wrong_season.give[0].season_id = "different-season"
	check(not call_as(Fixture.A, "create_trade", wrong_season).ok, "Stable card and season IDs must match")
	call_as(Fixture.A, "relationship", {"peer_id": Fixture.B, "operation": "block"})
	check(backend.trades[insufficient.trade.id].status == "invalidated" and backend.trades[trade.id].status == "completed", "Block invalidates pending invitations and preserves completed records")
	check(not call_as(Fixture.B, "request_friend", {"peer_id": Fixture.A}).ok, "Blocked users cannot request friendship")
	check(not call_as(Fixture.B, "send_text", {"conversation_id": cid, "client_id": "blocked", "text": "hello"}).ok, "Block prevents direct text")
	call_as(Fixture.A, "relationship", {"peer_id": Fixture.B, "operation": "unblock"})
	check(not backend.friend(Fixture.A, Fixture.B) and backend.trades[insufficient.trade.id].status == "invalidated", "Unblock restores neither friendship nor invalidated invitation")
	# Restore only this isolated scenario for gift/UI validation.
	backend.relationships[backend.pair(Fixture.A, Fixture.B)] = true
	backend.revision += 1
	social.refresh()
	router.collection_store().refresh()
	var collection: Node = router.collection_store()
	collection.set_wanted("0001", true)
	var gift: Dictionary = await collection.submit_gift("0001", Fixture.B, 1)
	check(gift.ok and collection.is_wanted("0001"), "Shared collection gift succeeds only on authoritative result and preserves wanted marker")
	var count: int = backend.transfers
	var repeated: Dictionary = await backend.send_gift(collection.operation)
	check(repeated.state == "succeeded" and backend.transfers == count, "Shared gift interface deduplicates original operation")
	check(collection.gift_rule("0001").max == collection.count("0001") - 1, "Original gift keep-one rule remains effective")

func _views(cid: String) -> void:
	social.refresh()
	page._select(cid)
	await frames()
	var peer: Dictionary = social.conversation(cid).peer
	var context := {"peer": peer, "conversation": social.conversation(cid)}
	for mode in ["profile", "remark", "peer_menu", "wishlist", "gift", "exchange", "records", "report", "blacklist", "recent_menu"]:
		var panel: Node
		if mode == "gift":
			page.gift_button.pressed.emit()
			await frames()
			panel = page.dialog
			check(panel.panel_mode == "gift" and panel.context.peer.id == Fixture.B, "Visible gift action opens card selection for current stable peer")
		else:
			panel = await dialog(mode, context)
		check(is_instance_valid(panel) and not panel.column.get_children().is_empty(), "Interactive panel builds: " + mode)
		if mode == "exchange":
			panel._review_create()
			await frames()
			check(labels(panel).contains("发送邀请即同意"), "Create flow requires explicit fixed-term review")
		if mode == "gift":
			panel._gift("0001")
			await frames()
			check(is_instance_valid(page.gift_dialog) and page.gift_dialog.selected_friend.id == Fixture.B, "Conversation gift uses original dialog with stable recipient preselected")
			await capture("08-gift-confirm")
			page.gift_dialog.dismiss()
			await frames()
		else:
			await close_dialog()
	page.add_button.grab_focus()
	var esc_panel := await dialog("add")
	key(esc_panel, KEY_ESCAPE)
	await frames()
	check(not is_instance_valid(page.dialog) and page.add_button.has_focus(), "Escape closes exclusive panel and restores keyboard focus to trigger")
	page.add_button.pressed.emit()
	await frames()
	var panel: Node = page.dialog
	check(panel.panel_mode == "add" and panel.friend_tabs.has("requests"), "Add-friend icon includes the friend requests tab")
	var pending_requests: int = social.pending_requests
	backend.search_delay = true
	panel.query.text = "QA-000002"
	panel._search()
	panel.friend_tabs.requests.pressed.emit()
	await create_timer(0.18).timeout
	check(panel.panel_mode == "requests" and panel.content.get_node_or_null("SearchResult") == null and social.pending_requests == pending_requests, "Switching to requests ignores late user search and does not process applications")
	panel.friend_tabs.add.pressed.emit()
	await frames()
	check(panel.panel_mode == "add" and panel.query.text == "QA-000002", "Returning to add-friend tab retains the lookup draft")
	backend.search_delay = true
	panel.query.text = "QA-000002"
	panel._search()
	panel.query.text = "QA-000004"
	panel._search()
	await create_timer(0.18).timeout
	check(labels(panel.content).contains("QA-000004") and not labels(panel.content).contains("QA-000002"), "Late user search result cannot replace newer result")
	backend.search_delay = false
	backend.delay = 0.05
	panel.query.text = "QA-000002"
	panel._search()
	panel.query.text = "还未提交的新查询"
	panel.query.text_changed.emit(panel.query.text)
	await create_timer(0.07).timeout
	check(panel.content.get_node_or_null("SearchResult") == null, "Editing a query immediately invalidates previous in-flight search")
	backend.delay = 0
	backend.fail_action = "find_user"
	panel._search()
	check(panel.status.text.contains("网络"), "Network error is not presented as user-not-found")
	backend.fail_action = ""
	await close_dialog()
	backend.append("system:" + Fixture.A, "", "notification", {"title": "新的官方通知", "body": "仅用于隔离验证"})
	social.refresh()
	var pending_before: int = social.pending_requests
	backend.late_message_on_read = true
	var result: Dictionary = await social.request("mark_all_read", {})
	social._apply_sync(result.sync)
	check(social.unread_total(true) == 1 and social.pending_requests == pending_before, "Read-all watermark preserves later arrivals and does not accept requests")
	page._bell()
	await frames()
	check(social.selected == "system:" + Fixture.A and not page.composer.visible and page.compose_hint.text == "系统通知无需回复", "Bell prioritizes unread official channel and renders read-only footer")
	check(not page.more_button.visible and not page.exchange_button.visible and not page.wants_button.visible and not page.gift_button.visible, "Official channel has no friend or transfer actions")
	await capture("02-system-notifications")
	backend.append(cid, Fixture.B, "text", {"text": "免打扰仍应保留未读"})
	call_as(Fixture.A, "preferences", {"peer_id": Fixture.B, "muted": true, "remark": "学习伙伴"})
	social.refresh()
	check(social.conversation(cid).unread > 0 and social.unread_total(true) > social.unread_total(), "Mute suppresses active badge but preserves quiet unread")
	social.set_tab("friends")
	check(social.list_items("学习伙伴").size() == 1 and backend.users[Fixture.B].name != "学习伙伴", "Remark is private and searchable without changing nickname")
	page._select(cid)
	await frames()
	page.composer.text = "返回后恢复草稿"
	page._draft_changed()
	for i in 70: backend.append(cid, Fixture.B, "text", {"text": "用于分页与滚动的长消息 %d。阅读旧消息时，后续消息不应把视图拖到底部。" % i})
	social.refresh()
	await frames(10)
	page.transcript.scroll_vertical = 0
	var anchor: Dictionary = page._anchor()
	backend.append(cid, Fixture.B, "text", {"text": "底部新增消息"})
	social.refresh()
	await frames(10)
	check(page._anchor().get("id") == anchor.get("id") and page.new_messages.visible, "Incoming message preserves old reading anchor and offers new-message control")
	social.load_history(cid)
	await frames()
	check(not str(social.history_before.get(cid, "")).is_empty(), "History supplies an older-page cursor")
	page._older()
	await frames(10)
	check(page._anchor().get("id") == anchor.get("id"), "Prepending history preserves reading anchor")
	page = await visit("Workbench")
	page = await visit("MyFriends")
	check(social.selected == cid and page.composer.text == "返回后恢复草稿", "Leaving module restores selected conversation and per-account draft")
	root.size = Vector2i(900, 700)
	root.content_scale_size = Vector2i(900, 700)
	await frames(12)
	page._select(cid)
	await frames(12)
	check(page.chat.visible and not page.contacts.visible and page.back_list.visible, "Narrow window uses list/conversation navigation")
	check(page.composer.position.y + page.composer.size.y <= page.chat.size.y, "Composer remains within viewport while history scrolls")
	await capture("06-narrow")
	check(page.consume_back_action() and page.contacts.visible, "Escape returns to list without losing draft")
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = Vector2i(1600, 1000)
	await frames()
	page._toggle_theme()
	await frames()
	await capture("07-dark")
	page._toggle_theme()
	await frames()

func _session_tests(cid: String) -> void:
	backend.delay = 0.08
	page._select(cid)
	page.composer.text = "不能写入下一账号"
	page._draft_changed()
	page._send()
	await login(Fixture.C)
	await create_timer(0.16).timeout
	backend.delay = 0
	check(social.account_id == Fixture.C and not social.messages.has(cid) and not social.drafts.has(cid), "Account switch cancels stale responses and clears private drafts/messages")
	profile.use_provider(null, {"state": "signed_out"})
	await frames()
	check(social.messages.is_empty() and social.friends.is_empty() and social.trades.is_empty() and not page.composer.visible, "Logout clears all sensitive social views")
	await login(Fixture.A)
	backend.fail_action = "sync"
	social.refresh()
	check(not social.connected and social.error.contains("网络"), "Connection failure is explicit and does not activate a fixture fallback")
	backend.fail_action = ""
	backend.append(cid, Fixture.B, "text", {"text": "断线期间消息"})
	social.refresh()
	await frames()
	check(social.connected and social.messages[cid].any(func(m): return m.get("text") == "断线期间消息"), "Reconnect sync cursor retrieves messages missed while disconnected")
	var id: String = social.intent("create_trade", terms(Fixture.B))
	var second: String = social.intent("create_trade", terms(Fixture.B))
	check(not id.is_empty() and id == second, "Trade intent journal reuses original key before server success")
	social._intents.clear()
	social._load_preferences()
	check(social.intent("create_trade", terms(Fixture.B)) == id, "Trade key survives local store reload without auto-submit")
