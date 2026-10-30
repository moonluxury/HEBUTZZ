extends SceneTree
## Opt-in end-to-end smoke test. Creates two disposable accounts; records IDs for cleanup.
const Provider = preload("res://scripts/backend_provider.gd")
var failures := 0
var ids: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("BACKEND CHECK FAILED: " + label)

func remember(response: Dictionary) -> void:
	if response.get("ok", false):
		ids.append(str(response.account_id))
		var file := FileAccess.open("res://.godot_appdata/backend-live-ids.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(ids))
		file.close()

func _run() -> void:
	if OS.get_environment("HEGONG_BACKEND_LIVE_TEST") != "1":
		printerr("Set HEGONG_BACKEND_LIVE_TEST=1 to authorize disposable live test accounts.")
		quit(1)
		return
	await process_frame
	var api: Node = root.get_node("BackendProvider")
	api.attach()
	var nonce := Crypto.new().generate_random_bytes(8).hex_encode()
	var password := "%06d" % (Crypto.new().generate_random_bytes(4).decode_u32(0) % 1000000)
	var username := "livecheck_" + nonce
	# Exercise the actual login window and provider session propagation.
	api.begin_login()
	await process_frame
	var dialog: Window = api.active_dialog
	check(is_instance_valid(dialog), "login window opens")
	if not is_instance_valid(dialog):
		quit(1)
		return

	dialog._mode_changed(1)
	dialog.username.text = username
	dialog.password.text = password
	dialog.confirmation.text = password
	dialog._submit()
	for attempt in 100:
		if not api.account_id.is_empty():
			break
		await create_timer(0.2).timeout
	check(not api.account_id.is_empty(), "register through UI over verified HTTPS")
	if api.account_id.is_empty():
		if is_instance_valid(dialog):
			printerr("Auth UI status: " + dialog.status.text)
		quit(1)
		return
	remember({"ok": true, "account_id": api.account_id})
	var profile: Node = root.get_node("ProfileStore")
	check(profile.authenticated() and profile.account_id == api.account_id, "profile session attached")
	var peer: Node = Provider.new()
	peer.name = "LiveTestPeer"
	root.add_child(peer)
	var registered: Dictionary = await peer.password_auth("livecheck_" + nonce + "b", password, true)
	remember(registered)
	check(registered.get("ok", false), "second isolated account registered")
	if not registered.get("ok", false):
		quit(1)
		return
	peer.access_token = str(registered.access_token)
	peer.account_id = str(registered.account_id)
	var saved: Dictionary = await api.save_profile(api.account_id, {"display_name": "部署联调测试", "school": "河北工业大学"}, "")
	check(saved.get("persisted", false), "profile saved")
	var fetched: Dictionary = await api.request_profile(api.account_id)
	check(fetched.get("profile", {}).get("display_name") == "部署联调测试", "profile read after write")
	var request: Dictionary = await api.social_request("request_friend", {"peer_id": peer.account_id, "note": "自动化联调", "operation_id": nonce + "request"})
	check(request.get("ok", false), "friend request persisted")
	var accepted: Dictionary = await peer.social_request("respond_request", {"request_id": request.get("request", {}).get("id", ""), "decision": "accept", "operation_id": nonce + "accept"})
	check(accepted.get("ok", false), "friend request accepted")
	var opened: Dictionary = await api.social_request("open_conversation", {"peer_id": peer.account_id})
	var cid: String = str(opened.get("conversation", {}).get("id", ""))
	var message: Dictionary = await api.social_request("send_text", {"conversation_id": cid, "client_id": nonce + "message", "text": "部署联调：消息持久化"})
	check(message.get("ok", false), "message persisted")
	var history: Dictionary = await peer.social_request("history", {"conversation_id": cid, "before": "", "limit": 40})
	check(history.get("messages", []).size() == 1, "peer receives message")
	var snapshot: Dictionary = await api.request_snapshot(api.account_id)
	check(snapshot.get("inventory_complete", false), "authoritative collection snapshot")
	for card in snapshot.get("inventory", {}).values():
		check(int(card.get("count", -1)) == 0, "no synthetic cards granted")
	var state: Dictionary = await api.social_request("sync", {"cursor": ""})
	check(state.get("friends", []).size() == 1, "shared friends snapshot")
	var logout: Dictionary = await api.logout(api.account_id)
	check(logout.get("ok", false), "logout acknowledged")
	var logged_in: Dictionary = await api.password_auth(username, password)
	check(logged_in.get("ok", false), "password login after registration")
	api.accept_session(logged_in)
	await api.logout(api.account_id)
	await peer.logout(peer.account_id)
	profile.use_provider(api, {"state": "signed_out"})
	await process_frame
	print("BACKEND LIVE CHECKS: " + ("PASS" if failures == 0 else "FAIL") + " (temporary account IDs saved for cleanup)")
	quit(0 if failures == 0 else 1)
