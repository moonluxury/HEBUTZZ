extends SceneTree
const Display = preload("res://scripts/time_display.gd")
const SocialFixture = preload("res://tools/fixtures/social_provider.gd")
const WalletFixture = preload("res://tools/fixtures/wallet_provider.gd")
const Discussion = preload("res://scripts/bank_discussion_view.gd")
const SOURCE := "2026-10-31T13:44:04.064609+00:00"
var assertions := 0
var failures: Array[String] = []
var output := "res://outputs/time-display-validation"
var page: Node

func _init() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures.append(message); push_error(message)

func frames(count := 10) -> void:
	for i in count: await process_frame

func labels(node: Node) -> String:
	var value := ""
	for label in node.find_children("*", "Label", true, false): value += label.text + "\n"
	return value

func visit(scene: String) -> void:
	root.get_node("PageRouter").go("res://scenes/" + scene + ".tscn")
	await scene_changed
	await frames()
	page = current_scene

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check-"): quit(2); return
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/time_display_cases.json"))
	for example in cases: check(Display.datetime(example.input) == example.expected, "Readable timestamp: " + example.input)
	var now := Time.get_unix_time_from_datetime_string("2026-10-31T14:00:00")
	check(Display.clock(SOURCE) == "21:44", "Chat clock is converted from UTC")
	check(Display.date("2026-10-31T23:30:00Z", "2026-10-31") == "2026-11-01", "Chat grouping uses the Beijing calendar day")
	check(Display.date("14:20", "2026-10-28") == "2026-10-28", "Legacy clock labels retain their separate date")
	check(Display.recent(SOURCE, now) == "21:44", "Today's conversation stamp fits the narrow list")
	check(Display.recent("2026-10-30T13:44:00Z", now) == "10-30", "Older conversation dates remain compact")
	check(Display.recent("2025-10-30T13:44:00Z", now) == "25/10/30", "Previous-year list entries retain year and day")
	check(Display.relative("2026-10-31T21:59:30+08:00", now) == "刚刚", "Relative comment time respects an explicit offset")
	check(Display.relative(SOURCE, now) == "15分钟前", "Fractional UTC comment time remains relative")
	check(Display.relative("2026-10-31T23:30:00Z", now) == "2026-11-01 07:30", "Future time is not mislabeled just now")
	var discussion := Discussion.new()
	check(not discussion._time(SOURCE).contains("T13:"), "Discussion rendering uses the shared display helper")
	discussion.free()
	await frames()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1672, 941)
	root.size = Vector2i(1672, 941)
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	root.get_node("UiMotion").set_enabled(false)
	DirAccess.make_dir_recursive_absolute(output)
	var backend := SocialFixture.new()
	root.add_child(backend)
	await backend.send_gift({"id": "timestamp-gift", "account_id": SocialFixture.A, "card_id": "0001", "friend_id": SocialFixture.B, "quantity": 1})
	backend.gifts["timestamp-gift"].time_label = SOURCE
	backend.execute(SocialFixture.C, "request_friend", {"peer_id": SocialFixture.A, "note": "隔离时间显示检查", "operation_id": "timestamp-request"})
	backend.requests[0].time_label = SOURCE
	for record in backend.logs:
		record.time_label = SOURCE
		record.date_label = "2026-10-31"
	backend.append(backend.conversation_for(SocialFixture.A, SocialFixture.B), SocialFixture.B, "text", {"text": "隔离测试：跨日消息", "time_label": "2026-10-31T23:30:00+00:00", "date_label": "2026-10-31"})
	var profile := root.get_node("ProfileStore")
	profile.use_provider(backend, {"state": "authenticated", "account_id": SocialFixture.A})
	await visit("MyFriends")
	page.store.select(backend.conversation_for(SocialFixture.A, SocialFixture.B))
	await frames()
	var shown := labels(page.message_rows)
	check(shown.contains("21:44") and shown.contains("07:30") and shown.contains("2026-11-01"), "Real chat labels and date divider show local time")
	check(not shown.contains("+00:00") and not shown.contains(".064609"), "Chat and business cards hide raw offset and microseconds")
	await capture("01-chat")
	page.show_panel("gift_detail", {"record_id": "timestamp-gift"})
	await frames()
	check(labels(page.dialog.content).contains("2026-10-31 21:44"), "Gift detail matches the user's timestamp example")
	await capture("02-gift-detail")
	page.dialog.dismiss()
	await frames()
	page.show_panel("requests")
	await frames()
	check(labels(page.dialog.content).contains("2026-10-31 21:44"), "Friend request rows use a readable date and clock")
	await capture("03-friend-requests")
	page.dialog.dismiss()
	await frames()
	check(backend.gifts["timestamp-gift"].time_label == SOURCE and page.store.requests[0].time_label == SOURCE, "Presentation never rewrites stored or transported timestamps")
	var wallet := WalletFixture.new()
	root.add_child(wallet)
	wallet.ledger.append({"id": "time-ledger", "account_id": wallet.actor, "source": "quiz", "delta": 5, "reference": "isolated-practice", "created_at": SOURCE})
	profile.use_provider(wallet, {"state": "authenticated", "account_id": wallet.actor})
	await visit("Recharge")
	page.show_panel("ledger")
	await frames()
	check(labels(page.dialog.content).contains("2026-10-31 21:44"), "Battery ledger uses the same Beijing time format")
	await capture("04-ledger")
	page.dialog.dismiss()
	print("TIME DISPLAY ASSERTIONS: %d" % assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
