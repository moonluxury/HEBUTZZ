extends "res://tools/check_minimal_design.gd"
const Provider = preload("res://tools/fixtures/discussion_http_provider.gd")
const OUTPUT := "res://outputs/discussion-capacity-validation/"
var provider: Node
var store: Node
var bank := "marxism"
var trace: Array = []
var checks := 0

func _expect(value: bool, message: String) -> void:
	checks += 1
	super._expect(value, message)

func _pause() -> void:
	await create_timer(0.32).timeout
	await process_frame

func _idle() -> void:
	for i in 200:
		var s: Dictionary = store.state(bank)
		if not s.loading and s.busy.is_empty() and s.reply_loading.is_empty(): await _pause(); return
		await create_timer(0.025).timeout
	_expect(false, "Network operations settle within timeout")

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + name + ".png")

func _transition(view: Control, mode: String, prefix: String) -> void:
	# Avoid including PNG disk-write latency from the previous capture in Tween delta.
	await _pause()
	# This offscreen, unfocusable test window must not inherit desktop focus changes.
	# Reduced-motion behavior is exercised separately below.
	var motion := root.get_node("UiMotion")
	motion.suspended = false; motion.system_reduced = 0; motion.set_enabled(true)
	var question_rect: Rect2 = view.pane.get_global_rect()
	var clock_rect: Rect2 = view.timer_label.get_global_rect()
	var start := Time.get_ticks_msec()
	var captures: Array[Image] = []
	var intermediate := false
	view.show_right_pane(mode)
	for frame in 24:
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		var sample := {"direction": prefix, "frame": frame, "elapsed_ms": Time.get_ticks_msec() - start, "reduced": motion.reduced(),
			"numbers_x": view.rail.position.x, "numbers_alpha": view.rail.modulate.a,
			"discussion_x": view.discussion_view.position.x, "discussion_alpha": view.discussion_view.modulate.a}
		trace.append(sample)
		if sample.discussion_alpha > 0.01 and sample.discussion_alpha < 0.99: intermediate = true
		_expect(view.pane.get_global_rect() == question_rect and view.timer_label.get_global_rect() == clock_rect, "Transition keeps question and clock coordinates fixed")
		if DisplayServer.get_name() != "headless": captures.append(root.get_texture().get_image())
	for frame in captures.size(): captures[frame].save_png(OUTPUT + "motion-%s-%02d.png" % [prefix, frame])
	await _pause()
	_expect(intermediate, "Recorded real intermediate fade/slide frames")
	_expect(view.right_panes.mode == mode and view.right_mode == mode, "Active pane and toolbar agree")
	_expect(view.right_panes.views[mode].modulate.a == 1.0, "Transition completes without transparent active pane")

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	app = root.get_node("AppState"); stats = root.get_node("StudyStats")
	await process_frame; await process_frame
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(2048, 1195); root.size = Vector2i(2048, 1195)
	_prepare_test_window()
	provider = Provider.new(); root.add_child(provider)
	var accounts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://.godot_appdata/discussion-check-session.json"))
	provider.accept_session(accounts[0])
	store = root.get_node("AppServices").bank_discussions()
	app.subject_id = bank; app.quiz_mode = "all"; app.start_index = 24
	var quiz: Node = await _open("Quiz")
	var view: Control = quiz.minimal_view
	_expect(provider.requests.is_empty(), "Default question rail makes no comment request")
	_expect(view.right_mode == "numbers" and view.rail.visible, "Default view is the question grid")
	_expect(view.mark_button.position.x < view.discussion_button.position.x and view.discussion_button.get_rect().end.x < view.header.get_node("Clock").position.x, "Icon-only header actions stay before timer")
	_expect(view.mark_button.text.is_empty() and view.discussion_button.text.is_empty() and not view.header.has_node("OpenExplanation"), "Only mark and discussion icons are shown")
	await _shot("01-default")
	var wrongs: Dictionary = quiz.wrong_ids.duplicate(true)
	view.mark_button.pressed.emit(); await _pause()
	_expect(view.marks.marked(bank, str(quiz.questions[24].id)), "Mark uses stable bank/question ID")
	_expect(quiz.wrong_ids == wrongs and not quiz.has_answered, "Mark does not answer or add wrong question")
	var mark_disk: Variant = preload("res://scripts/local_json_store.gd").read(view.marks.PATH)
	_expect(mark_disk[accounts[0].account_id][bank][str(quiz.questions[24].id)] == true, "Mark is atomically persisted by stable ID")
	await _shot("04-marked")
	view.number_buttons[24].grab_focus()
	view.discussion_button.grab_focus()
	await _transition(view, "discussion", "open")
	await _idle()
	_expect(store.state(bank).loaded and store.state(bank).items.size() >= 3, "Real backend comments loaded")
	_expect(view.discussion_view.find_children("AuthorCollege", "Label", true, false).size() >= 3, "Author colleges are displayed beside names")
	_expect(not view.discussion_view.status.text.contains("2000") and not view.discussion_view.status.text.contains("容量"), "No individual word limit or capacity notice is shown")
	await _shot("02-discussion")
	view.discussion_view.composer.text = "长评论".repeat(1000); view.discussion_view.composer.text_changed.emit()
	_expect(not view.discussion_view.publish.disabled, "A comment beyond 2000 characters remains publishable")
	view.discussion_view.publish.pressed.emit(); await _idle()
	var long_item: Dictionary = store.state(bank).items[0]
	_expect(str(long_item.body).length() == 3000, "Client publishes a real comment beyond the old limit")
	_expect(view.discussion_view.text_pages.is_empty(), "Long comments start as a bounded preview")
	view.discussion_view._show_text_page(str(long_item.id), 0); await _pause()
	await _shot("10-college-long-comment")
	store.mutate(bank, "comment_delete", {"comment_id":long_item.id}, str(long_item.id)); await _idle()
	view.discussion_view.composer.text = "容量不足时保留的草稿"; view.discussion_view.composer.text_changed.emit()
	provider.fail_next = true; provider.fail_code = "discussion_full"
	view.discussion_view.publish.pressed.emit(); await _idle()
	_expect(store.state(bank).publish_blocked and view.discussion_view.composer.text == "容量不足时保留的草稿", "Capacity refusal preserves unsent text")
	_expect(store.state(bank).error.is_empty() and store.state(bank).notice.is_empty() and not view.discussion_view.status.text.contains("容量"), "Owner-only capacity alerts do not appear in the user interface")
	view.discussion_view.composer.text = "尚未发布的草稿"; view.discussion_view.composer.text_changed.emit()
	var count: int = provider.requests.size()
	view.discussion_view.list_scroll.scroll_vertical = 40
	await process_frame
	var previous_scroll: int = view.discussion_view.list_scroll.scroll_vertical
	quiz._jump_to(25); await _pause()
	_expect(view.right_mode == "discussion" and provider.requests.size() == count, "Changing question neither closes nor reloads bank discussion")
	_expect(view.discussion_view.composer.text == "尚未发布的草稿", "Changing question preserves draft")
	await _transition(view, "numbers", "close")
	_expect(root.gui_get_focus_owner() == view.number_buttons[24], "Closing discussion restores the remembered number-grid focus")
	view.discussion_button.pressed.emit(); await _pause()
	_expect(provider.requests.size() == count and view.discussion_view.composer.text == "尚未发布的草稿", "Reopen restores cached data and draft")
	_expect(view.discussion_view.list_scroll.scroll_vertical == previous_scroll, "Reopening preserves comment scroll position")
	for mode in ["numbers", "discussion", "numbers", "discussion", "numbers"]:
		view.show_right_pane(mode); await create_timer(0.035).timeout
	await _pause()
	_expect(view.rail.visible and not view.discussion_view.visible, "Rapid interruptions leave only final pane visible")
	quiz._on_option_pressed(0); await _pause()
	_expect(quiz.has_answered and not quiz.answer_label.text.is_empty(), "Original answer feedback remains available")
	view.show_right_pane("discussion"); await _pause()
	provider.fail_next = true
	var before_publish: int = provider.requests.size()
	view.discussion_view.publish.pressed.emit(); view.discussion_view.publish.pressed.emit()
	await _idle()
	_expect(provider.requests.size() == before_publish + 1, "Repeated publish click sends one request")
	_expect(store.state(bank).draft == "尚未发布的草稿" and not store.state(bank).error.is_empty(), "Failed submission retains input")
	var request_before_retry: Dictionary = provider.requests.back().payload
	store.publish(bank); await _idle()
	_expect(store.state(bank).draft.is_empty() and provider.requests.back().payload.operation_id == request_before_retry.operation_id, "Retry reuses operation ID and clears draft only after success")
	var posted: Dictionary = store.state(bank).items[0]
	store.reply_to(bank, posted); store.state(bank).draft = "真实接口回复测试"
	store.publish(bank); await _idle()
	_expect(store.state(bank).replies.has(posted.id), "Reply records fetched from server")
	store.mutate(bank, "comment_like", {"comment_id": posted.id, "value": true}, posted.id); await _idle()
	_expect(store.state(bank).items[0].liked, "Like confirmed by real backend")
	await _shot("05-replies")
	provider.read_delay = 0.3
	store.load_page(bank)
	await create_timer(0.08).timeout
	store.mutate(bank, "comment_like", {"comment_id": posted.id, "value": false}, posted.id)
	await _idle()
	_expect(not store.state(bank).items[0].liked, "An older read cannot overwrite a successful unlike")
	store.state(bank).replies.erase(posted.id); store.state(bank).expanded.erase(posted.id)
	store.load_replies(bank, posted.id)
	await create_timer(0.08).timeout
	store.reply_to(bank, posted); store.state(bank).draft = "回复加载期间的新增回复"
	store.publish(bank); await _idle()
	_expect(store.state(bank).replies[posted.id].items.size() == 2, "Late reply pages do not drop a concurrently published reply")
	provider.read_delay = 0
	store.mutate(bank, "comment_like", {"comment_id": posted.id, "value": true}, posted.id); await _idle()
	store.sort_by(bank, "hot"); await _idle()
	_expect(store.state(bank).sort == "hot" and store.state(bank).items[0].id == posted.id, "Popular order uses real like count")
	store.mutate(bank, "comment_delete", {"comment_id": posted.id}, posted.id); await _idle()
	_expect(store.state(bank).items[0].status == "deleted" and store.state(bank).items[0].body.is_empty(), "Own deletion is persisted and rendered as tombstone")
	# Theme and focus layout rebuilds retain the right-pane state and bank draft.
	store.state(bank).draft = "主题切换草稿"
	app.dark_mode = true; app.color_mode_changed.emit(true); await _pause()
	_expect(view.right_mode == "discussion" and view.discussion_view.composer.text == "主题切换草稿", "Theme rebuild keeps discussion and draft")
	await _shot("06-dark")
	app.dark_mode = false; app.color_mode_changed.emit(false); await _pause()
	view._toggle_distraction_free(); await _pause()
	_expect(view.right_mode == "discussion" and not view.header.visible, "F6 preserves discussion")
	view._toggle_distraction_free()
	root.get_node("UiMotion").set_enabled(false)
	view.show_right_pane("numbers"); view.show_right_pane("discussion")
	_expect(view.discussion_view.position.x == 0 and view.discussion_view.modulate.a == 1, "Reduced motion settles immediately")
	root.get_node("UiMotion").set_enabled(true)
	# Session switch invalidates an in-flight read and clears private draft/likes.
	provider.response_delay = 0.25
	store.load_page(bank)
	provider.accept_session(accounts[1])
	await _idle()
	_expect(store.state(bank).draft.is_empty(), "Switching account clears old draft")
	_expect(not view.marks.marked(bank, str(quiz.questions[24].id)), "Marks are isolated by account")
	provider.response_delay = 0
	provider.access_token = ""; provider.account_id = ""
	root.get_node("ProfileStore").use_provider(provider, {"state": "signed_out"})
	await _idle()
	_expect(store.state(bank).loaded and view.discussion_view.publish.text == "登录", "Signed out users can read public bank and must log in to post")
	await _shot("07-signed-out")
	# Real empty bank, no example comments are injected into the client.
	app.subject_id = "python"; bank = "python"; app.start_index = 0
	quiz = await _open("Quiz"); view = quiz.minimal_view
	view.show_right_pane("discussion"); await _idle()
	_expect(store.state(bank).items.is_empty() and store.state(bank).loaded, "Different bank loads its own empty discussion")
	await _shot("08-empty")
	root.content_scale_size = Vector2i(1200, 900); root.size = Vector2i(1200, 900)
	_prepare_test_window(); await _pause()
	_expect(view.discussion_view.composer.get_global_rect().end.y < view.get_global_rect().end.y, "Compact layout retains visible composer")
	_expect(view.pane.get_global_rect().end.x <= view.right_panes.get_global_rect().position.x, "Compact discussion never overlays question")
	await _shot("09-compact")
	var compact_rect: Rect2 = view.pane.get_rect()
	view.show_right_pane("numbers"); await _pause()
	view.show_right_pane("discussion"); await _pause()
	_expect(view.pane.get_rect() == compact_rect, "Compact pane switching keeps question area stable")
	_expect(not quiz.next_button.get_global_rect().intersects(quiz.wrong_toggle.get_global_rect()), "Compact footer controls do not overlap")
	if DisplayServer.get_name() != "headless":
		var file := FileAccess.open(OUTPUT + "motion-trace.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(trace, "  ")); file.close()
	print("WORKBENCH CHECKS: %s (%d assertions, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
