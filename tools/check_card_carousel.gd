extends "res://tools/check_card_acquisition.gd"
const Pool = preload("res://scripts/card_carousel_stage.gd")
const Tokens = preload("res://scripts/ui_tokens.gd")
var entry_captures: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	if not ok and is_instance_valid(page) and is_instance_valid(page.acquisition):
		var dialog: Node = page.acquisition
		print("CAROUSEL DIAGNOSTIC: ", {"dialog": dialog.state, "pool": dialog.carousel.state,
			"phase": dialog.carousel.phase, "speed": dialog.carousel.speed_multiplier,
			"pointer": dialog.carousel._has_pointer, "hovered": dialog.carousel.hovered_index,
			"reduced": motion.reduced(), "duration": dialog.carousel._landing_duration,
			"calls": api.draw_calls.size(), "result": draws.ready_result()})
	super.check(ok, message)

func until(condition: Callable, message: String, timeout := 6.0) -> void:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while not condition.call() and Time.get_ticks_msec() < end: await process_frame
	check(condition.call(), message)

func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func move_to(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
	await process_frame

func card_span(pool: Control) -> float:
	var left := INF
	var right := -INF
	for slot in pool.slots:
		var x: float = slot.position.x + slot.pivot_offset.x
		left = minf(left, x)
		right = maxf(right, x)
	return right - left

func capture_entry(_dialog: Node, filename: String) -> void:
	# Capture native frames now; defer PNG compression until after entry so
	# disk/encoder time cannot shift the short animation's later checkpoints.
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	entry_captures.append({"image": root.get_texture().get_image(), "filename": filename})

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	create_timer(90.0).timeout.connect(func(): push_error("Carousel validation timed out"); quit(1))
	await pause()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	if DisplayServer.get_name() != "headless": root.unfocusable = true; root.position = Vector2i(-10000, -10000)
	output = "res://outputs/card-carousel-validation"
	DirAccess.make_dir_recursive_absolute(output)
	profile = root.get_node("ProfileStore")
	motion = root.get_node("UiMotion")
	# Ignore OS focus changes for this isolated off-screen renderer; the suite
	# still toggles the actual enabled preference to verify reduced motion.
	motion.preference_changed.connect(func(): motion.system_reduced = 0; motion.suspended = false)
	api = Fixture.new()
	root.add_child(api)
	await login(Fixture.A)
	root.get_node("PageRouter").go("res://scenes/MyCollection.tscn")
	await scene_changed
	page = current_scene
	draws = page.draw_store
	wallet = root.get_node("AppServices").wallet_store()
	api.balances[Fixture.A] = 10000
	api.wallet_revisions[Fixture.A] += 1
	wallet.refresh_balance()
	await pause()
	motion.system_reduced = 0; motion.suspended = false; motion.set_enabled(true)
	page._set_filter("all")
	page.expanded["season-001"] = false
	page._render()
	var catalogue_before: Array = page.store.cards.duplicate(true)
	var expanded_before: Dictionary = page.expanded.duplicate()
	page._open_acquisition()
	var dialog: Node = page.acquisition
	check(dialog.state == "entering" and dialog.hit.disabled and api.draw_calls.is_empty(), "Entry does not dispatch a paid request")
	await pause(0.15)
	await capture("01-scene-entering")
	await until(func(): return dialog.carousel.state == "entering", "The loaded deck starts its entrance after the modal")
	await pause(Tokens.CARD_POOL_STACK_APPEAR * 0.5)
	var initial_span := card_span(dialog.carousel)
	check(initial_span < 26.0 and dialog.carousel.slots[0].position.x < dialog.carousel.size.x * 0.25, "All eleven backs begin together in a small pile on the left")
	check(dialog.hit.disabled and not dialog.carousel.selection_enabled, "The pile cannot acquire before it has finished spreading")
	var pile_card: Control = dialog.carousel.slots[0]
	await click_at(pile_card.get_global_transform_with_canvas() * (pile_card.size * 0.5))
	check(api.draw_calls.is_empty(), "Clicking the entering pile does not start a paid request")
	await capture_entry(dialog, "01a-left-card-pile")
	await pause(Tokens.CARD_POOL_ENTER * 2.0 / 9.0)
	var middle_span := card_span(dialog.carousel)
	check(middle_span > initial_span + 70.0 and middle_span < 1000.0, "The moving pile spreads cards progressively toward the right (span %.1f, progress %.3f)" % [middle_span, dialog.carousel.entry_progress])
	await capture_entry(dialog, "01b-spreading-right")
	await pause(Tokens.CARD_POOL_ENTER * 5.0 / 18.0)
	check(card_span(dialog.carousel) > middle_span and not dialog._pool_ready, "The spread keeps widening before it unlocks selection")
	await capture_entry(dialog, "01c-almost-unfolded")
	await until(func(): return dialog._pool_ready, "Back textures and card entry complete")
	check(card_span(dialog.carousel) > 1000.0 and dialog.carousel.entry_progress == 1.0, "The complete deck reaches the existing arc before flow begins")
	for frame in entry_captures: frame.image.save_png(output.path_join(frame.filename + ".png"))
	entry_captures.clear()
	check(dialog.state == "ready" and dialog.carousel.catalogue_cards.size() == 7 and dialog.carousel.slots.size() == 11 and not dialog.hit.disabled, "Eleven display backs include all seven real catalogue cards")
	check(dialog.hint.text == "从流转的卡池中，选择一张属于你的卡牌" and dialog.pool_note.text == "点击任意卡片，开启你的卡牌", "Copy explains that every card is selectable")
	check(dialog.carousel.back_paths.all(func(path): return path == page.store.season("season-001").back_image), "The original catalogue back is reused without image substitution")
	var phase_before: float = dialog.carousel.phase
	await pause(0.20)
	check(dialog.carousel.phase > phase_before and dialog.carousel.is_processing(), "The whole pool moves continuously during idle")
	await capture("02-dense-arc-flow")
	await move_to(dialog.hit.get_global_rect().get_center())
	await pause(0.65)
	check(absf(dialog.carousel.speed_multiplier - Tokens.CARD_POOL_HOVER_SPEED) < 0.03, "Native central hover smoothly reaches the configured speed fraction")
	phase_before = dialog.carousel.phase
	var hover_started := Time.get_ticks_msec()
	await pause(0.20)
	var hovered_travel: float = fposmod(dialog.carousel.phase - phase_before, dialog.carousel.cards.size())
	var measured_hover_rate := hovered_travel / ((Time.get_ticks_msec() - hover_started) / 1000.0)
	check(absf(measured_hover_rate - Tokens.CARD_POOL_HOVER_SPEED / Tokens.CARD_POOL_STEP) < 0.08 and hovered_travel > 0 and api.draw_calls.is_empty(), "Visible hovered travel matches the configured speed without dispatching acquisition")
	await capture("02-hover-slowdown")
	await move_to(dialog.close_button.get_global_rect().get_center())
	await pause(0.65)
	check(dialog.carousel.speed_multiplier > 0.97, "Leaving the cards smoothly restores normal flow")
	await move_to(dialog.carousel.slots[3].get_global_rect().get_center())
	await pause(0.65)
	check(absf(dialog.carousel.speed_multiplier - Tokens.CARD_POOL_HOVER_SPEED) < 0.03 and api.draw_calls.is_empty(), "Outer card hover also slows the pool without selecting a prize")
	await move_to(dialog.close_button.get_global_rect().get_center())
	await pause(0.65)
	check(dialog.carousel.speed_multiplier > 0.97, "Leaving an outer card clears its hover source")
	check(is_equal_approx(Reveal.REVEAL, 0.70), "The shared card reveal retains its requested 700ms duration")
	check(dialog.hit.has_focus(), "Keyboard focus reaches the central acquisition button")
	key(KEY_TAB, true); key(KEY_TAB, false)
	check(dialog.close_button.has_focus(), "Tab advances from center to close")
	key(KEY_TAB, true); key(KEY_TAB, false)
	check(dialog.hit.has_focus(), "Tab wraps within the modal")
	key(KEY_SPACE, true); key(KEY_SPACE, false)
	check(api.draw_calls.is_empty(), "Space while waiting never acquires or chooses a result")
	await click_at(dialog.hint.get_global_transform_with_canvas() * Vector2(dialog.hint.size.x * 0.5, 12))
	check(api.draw_calls.is_empty(), "Clicking the background or copy does not acquire")
	var selected := 4
	var chosen_slot: Control = dialog.carousel.slots[selected]
	var click_point := chosen_slot.get_global_transform_with_canvas() * (chosen_slot.size * 0.5)
	var visible_choice: String = dialog.carousel.cards[selected].id
	api.draw_delay = 0.45
	var events: Dictionary = {}
	dialog.carousel.settled.connect(func(id):
		events.aligned_id = id
		events.center_id = dialog.carousel.cards[dialog.carousel.focal_index].id
		events.selected = dialog.carousel._target_index
		events.origin = dialog.carousel.slots[selected].position + dialog.carousel.slots[selected].pivot_offset)
	dialog.carousel.extracted.connect(func(id):
		events.extracted_id = id
		events.rect = dialog.carousel.result_rect())
	await click_at(click_point)
	var click_origin: Vector2 = chosen_slot.position + chosen_slot.pivot_offset
	var positions_before: Array[Vector2] = []
	for slot in dialog.carousel.slots: positions_before.append(slot.position + slot.pivot_offset)
	check(dialog.carousel.selected_index == selected, "The clicked outer card is selected rather than the central card")
	await click_at(dialog.hit.get_global_rect().get_center())
	dialog.hit.pressed.emit(); dialog.hit.pressed.emit()
	check(draws.busy and api.draw_calls.size() == 1 and dialog.hit.disabled and not dialog.carousel.selection_enabled, "Native outer click locks all cards before dispatch; cross-card repeated clicks spend once")
	var request: Dictionary = api.draw_calls[0]
	check(not request.has("card_id") and not request.has("index") and request.expected_price == 200 and request.pool_id == "season-001", "No visual identity or client-selected prize is sent to the service")
	phase_before = dialog.carousel.phase
	await pause(0.12)
	check(dialog.state == "requesting" and dialog.carousel.phase > phase_before and not dialog.preview.visible, "Slow response retains a moving back-only pool")
	var all_moved := true
	for i in dialog.carousel.slots.size():
		var slot: Control = dialog.carousel.slots[i]
		all_moved = all_moved and (slot.position + slot.pivot_offset).distance_to(positions_before[i]) > 0.1
	check(all_moved and (chosen_slot.position + chosen_slot.pivot_offset).distance_to(click_origin) > 0.1, "All eleven backs, including the selected back, keep moving after the click")
	key(KEY_SPACE, true); key(KEY_SPACE, false)
	check(draws.busy and not dialog.details.visible, "Skipping while the result is unknown cannot fabricate a card")
	await until(func(): return draws.ready_result(), "Verified receipt arrives")
	check(dialog.state == "aligning" and not dialog.details.visible and not dialog.preview.visible, "Receipt starts alignment while keeping the unrevealed identity hidden")
	await capture("03-result-aligning")
	await until(func(): return dialog.state == "result", "Natural stop, extraction and shared reveal finish")
	check(events.get("aligned_id") == "0004" and events.get("center_id") == "0004" and events.get("extracted_id") == "0004", "The returned astronaut stops at the center and is the extracted card")
	check(events.get("selected") == selected and events.origin.distance_to(dialog.carousel.focus_rect().get_center()) < 0.01, "The selected card reaches the real center in the band before extraction starts")
	check(visible_choice != "0004", "This request deliberately returned a different identity than the clicked visual position")
	var destination: Rect2 = dialog._reveal_destination()
	check(events.rect.position.distance_to(destination.position) < 0.01 and events.rect.size.distance_to(destination.size) < 0.01, "The extracted back exactly matches CardReveal's position and size")
	check(dialog.preview.get_script() == Reveal and dialog.preview.face.texture.resource_path == page.store.card("0004").image, "The existing CardReveal displays the exact server-selected front")
	check(dialog.metadata.text.contains("本次 +1") and dialog.metadata.text.contains("当前拥有 1 张"), "Receipt quantity and authoritative ownership are displayed")
	check(api.grants == 1 and wallet.balance == 9800 and page.store.cards == catalogue_before, "Presentation reordering never modifies the catalogue, prize, inventory rules or price")
	await capture("04-natural-reveal-result")
	dialog.return_button.pressed.emit(); await pause()
	check(page.filter == "all" and page.expanded == expanded_before and page.acquire_button.has_focus(), "Return restores focus and retains overview filters and expansion")
	# Closing before the reply keeps the store alive but cannot reopen the old UI.
	dialog = await open()
	dialog.hit.pressed.emit()
	dialog.dismiss()
	await pause(0.60)
	check(not is_instance_valid(page.acquisition) and draws.ready_result() and api.grants == 2, "A late paid result persists independently of the closed modal")
	var calls_before: int = api.draw_calls.size()
	dialog = await open()
	await result_ready(dialog)
	check(api.draw_calls.size() == calls_before and api.grants == 2 and dialog.metadata.text.contains("重复获得"), "Reopening recovers the same duplicate receipt without another debit")
	dialog.dismiss(); await pause()
	api.draw_delay = 0.03
	# Stop/skip during alignment: no reveal callback owns another paid operation.
	dialog = await open(); await click_at(dialog.hit.get_global_rect().get_center())
	await until(func(): return dialog.state == "aligning", "Third result reaches alignment")
	key(KEY_SPACE, true); key(KEY_SPACE, true, true); key(KEY_SPACE, false)
	await until(func(): return dialog.state == "result", "Space settles the same verified result immediately")
	check(api.grants == 3 and dialog.carousel._tween == null and dialog.preview._tween == null, "Skip cancels both visual tracks and grants only once")
	key(KEY_SPACE, true); key(KEY_SPACE, false)
	check(is_instance_valid(page.acquisition) and api.grants == 3, "Repeated Space cannot close or acquire again")
	dialog.dismiss(); await pause()
	# Missing front is a truthful presentation error, not another draw.
	var original_image: String = page.store.card("0004").image
	page.store.card("0004").image = "res://missing-carousel-test-front.png"
	dialog = await open(); dialog.hit.pressed.emit()
	await result_ready(dialog)
	check(dialog.preview.state == "error" and dialog.name_label.text == "宇航员" and api.grants == 4, "Image failure displays the real receipt with an explicit error")
	dialog.dismiss(); await pause()
	page.store.card("0004").image = original_image
	# Reduced mode disables the loop and still performs one real request.
	motion.set_enabled(false)
	dialog = await open()
	phase_before = dialog.carousel.phase
	await pause(0.18)
	check(dialog.carousel.phase == phase_before and not dialog.carousel.is_processing(), "Reduced motion has a static central card and no continuous processing")
	await click_at(dialog.carousel.slots[8].get_global_transform_with_canvas() * (dialog.carousel.slots[8].size * 0.5))
	await until(func(): return dialog.state == "result", "Reduced mode reveals and enables its actions")
	check(dialog.preview.session.reduced and api.grants == 5, "Reduced mode uses the existing crossfade for the same server result")
	await capture("05-reduced-motion-result")
	for dimensions in [Vector2i(900, 620), Vector2i(1600, 540), Vector2i(1920, 1080)]:
		root.size = dimensions; root.content_scale_size = dimensions
		await pause(0.10)
		check(root.get_visible_rect().encloses(dialog.preview.face.get_global_rect()) and root.get_visible_rect().encloses(dialog.return_button.get_global_rect()), "Card and return action remain visible at " + str(dimensions))
		await capture("layout-%dx%d" % [dimensions.x, dimensions.y])
	dialog.dismiss(); await pause()
	motion.set_enabled(true)
	# Changing preference mid-alignment finishes the same result, not the next slot.
	dialog = await open(); dialog.hit.pressed.emit()
	await until(func(): return dialog.state == "aligning", "Preference case begins alignment")
	motion.set_enabled(false)
	await until(func(): return dialog.state == "result", "Preference change completes the same result")
	check(dialog.preview.session.card.id == "0004" and api.grants == 6, "Mid-animation preference change does not replace the receipt")
	dialog.dismiss(); await pause()
	motion.set_enabled(true)
	dialog = await open(); dialog.hit.pressed.emit()
	await until(func(): return dialog.state == "aligning", "Esc case reaches alignment")
	var frozen_pool: Control = dialog.carousel
	var frozen_phase: float = frozen_pool.phase
	key(KEY_ESCAPE, true); key(KEY_ESCAPE, false)
	check(dialog.closing and frozen_pool.state == "exiting" and not frozen_pool.is_processing() and frozen_pool._tween == null and frozen_pool.phase == frozen_phase, "Esc freezes current cards without resetting their visible pose")
	await pause()
	check(not is_instance_valid(page.acquisition), "Exit removes the entire modal after its transition")
	# Background follows light/dark preferences and never changes the card art.
	var app := root.get_node("AppState")
	app.dark_mode = true
	dialog = await open(); await result_ready(dialog)
	check(dialog.aerospace.dark and dialog.preview.face.texture.resource_path == original_image, "Dark appearance changes stage palette without touching card imagery")
	await capture("06-dark-result")
	dialog.dismiss(); await pause()
	app.dark_mode = false
	await _all_presentational_targets()
	await _all_clickable_slots()
	await _all_rotation_paths()
	await _entry_lifecycle()
	check(page.store.cards == catalogue_before, "All pool exercises leave the production catalogue unchanged")
	print("CAROUSEL ASSERTIONS: ", assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _all_presentational_targets() -> void:
	var pool := Pool.new()
	pool.position = Vector2(300, 200)
	pool.size = Vector2(1120, 430)
	root.add_child(pool)
	var items: Array = page.store.results("season-001", "all")
	var source: Array = items.duplicate(true)
	var target := Rect2(440, 48, 240, 360)
	for item in items:
		pool.configure(items, page.store.season("season-001").back_image)
		pool.present()
		await until(func(): return pool.state == "flowing", "Independent pool enters for " + str(item.id))
		pool.phase = 2.37
		pool._render_frame()
		check(pool.settle_to(str(item.id)), "Every configured identity can be targeted after a receipt")
		await until(func(): return pool.state == "aligned", "Pool stops on " + str(item.id))
		check(str(pool.cards[pool.focal_index].id) == str(item.id), "Target is the central identity " + str(item.id))
		pool.extract_to(target)
		await until(func(): return pool.state == "extracted", "Extraction finishes for " + str(item.id))
		check(pool.result_rect().position.distance_to(target.position) < 0.01 and pool.result_rect().size.distance_to(target.size) < 0.01, "Every card reaches the same reveal container")
		check(pool.slots[pool.focal_index].texture.get_image().get_pixel(0, 0).a == 0.0, "Original PNG transparent corner is retained")
	check(items == source, "Pool reorders copies, not the passed catalogue objects")
	pool.freeze()
	pool.queue_free()
	await pause(0.05)

func _entry_lifecycle() -> void:
	var calls_before: int = api.draw_calls.size()
	page._open_acquisition()
	var dialog: Node = page.acquisition
	await until(func(): return dialog.carousel.state == "entering", "Close case reaches the spreading deck")
	await pause(Tokens.CARD_POOL_ENTER * 2.0 / 9.0)
	var frozen: float = dialog.carousel.entry_progress
	var poses: Array[Vector2] = []
	for slot in dialog.carousel.slots: poses.append(slot.position)
	dialog.dismiss()
	var retained: bool = dialog.carousel.entry_progress == frozen and dialog.carousel._tween == null
	for i in poses.size(): retained = retained and dialog.carousel.slots[i].position == poses[i]
	check(retained and dialog.carousel.state == "exiting", "Closing mid-spread freezes the current pile instead of resetting it")
	await pause()
	check(not is_instance_valid(page.acquisition) and api.draw_calls.size() == calls_before, "Closing a spreading deck unloads it without spending")
	page._open_acquisition()
	dialog = page.acquisition
	await until(func(): return dialog.carousel.state == "entering", "Reopened modal starts one fresh deck entrance")
	check(card_span(dialog.carousel) < 26.0, "Reopening resets the old spread to a left-hand pile")
	await pause(Tokens.CARD_POOL_ENTER * 0.2)
	motion.set_enabled(false)
	check(dialog._pool_ready and card_span(dialog.carousel) > 1000.0 and dialog.carousel._tween == null and not dialog.carousel.is_processing(), "Reduced motion during spread immediately presents the complete static arc")
	check(api.draw_calls.size() == calls_before and not dialog.hit.disabled, "Reduced mode keeps selection available without creating a request")
	dialog.dismiss(); await pause()
	motion.set_enabled(true)

func _all_clickable_slots() -> void:
	motion.set_enabled(false)
	var pool := Pool.new()
	pool.position = Vector2(300, 200)
	pool.size = Vector2(1120, 430)
	root.add_child(pool)
	var events: Array[int] = []
	pool.chosen.connect(func(index): events.append(index); pool.requesting(index))
	for index in Tokens.CARD_POOL_DISPLAY_COUNT:
		pool.configure(page.store.results("season-001", "all"), page.store.season("season-001").back_image)
		pool.present()
		await until(func(): return pool.state == "flowing", "Independent clickable pool ready")
		pool.set_selection_enabled(true)
		var slot: Control = pool.slots[index]
		var point := slot.get_global_transform_with_canvas() * (slot.size * 0.5)
		await click_at(point)
		check(events.size() == index + 1 and events.back() == index and pool.selected_index == index, "Native mouse can select display card %d, including both ends" % index)
		check(pool.settle_to("0004") and pool._target_index == index, "The verified receipt stays attached to chosen display card %d" % index)
		pool.extract_to(Rect2(440, 48, 240, 360))
		check(pool.result_rect().size.is_equal_approx(Vector2(240, 360)), "Arbitrary selected card reaches the shared reveal size")
	# The visually topmost card wins in an overlap, and transparent outer corners do not intercept.
	pool.configure(page.store.results("season-001", "all"), page.store.season("season-001").back_image)
	pool.present()
	await until(func(): return pool.state == "flowing", "Overlap pool ready")
	var center: Control = pool.slots[0]
	var overlap := center.get_global_transform_with_canvas() * Vector2(center.size.x * 0.90, center.size.y * 0.5)
	check(pool.pick_slot(overlap) == 0, "Overlapping cards select the rendered frontmost card")
	var corner := center.get_global_transform_with_canvas() * Vector2(0.01, 0.01)
	check(pool.pick_slot(corner) != 0, "A transparent PNG corner is not an invisible hit target")
	pool.freeze(); pool.queue_free()
	await pause(0.05)
	motion.set_enabled(true)

func _all_rotation_paths() -> void:
	var pool := Pool.new()
	pool.position = Vector2(300, 200)
	pool.size = Vector2(1120, 430)
	root.add_child(pool)
	var items: Array = page.store.results("season-001", "all")
	for index in Tokens.CARD_POOL_DISPLAY_COUNT:
		pool.configure(items, page.store.season("season-001").back_image)
		pool.present()
		await until(func(): return pool.state == "flowing", "Rotation pool enters")
		pool.phase = 0.15
		pool._render_frame()
		pool.requesting(index)
		var before: Array[Vector2] = []
		for slot in pool.slots: before.append(slot.position + slot.pivot_offset)
		await pause(0.12)
		var moved := true
		for i in pool.slots.size(): moved = moved and (pool.slots[i].position + pool.slots[i].pivot_offset).distance_to(before[i]) > 0.1
		check(moved and pool.phase > 0.15, "Selecting %d moves every card in the existing direction" % index)
		var forward := true
		var last: float = pool.phase
		while pool._centering:
			await process_frame
			forward = forward and pool.phase >= last - 0.00001
			last = pool.phase
		check(forward and pool.focal_index == index and (pool.slots[index].position + pool.slots[index].pivot_offset).distance_to(pool.focus_rect().get_center()) < 0.01 and absf(pool.slots[index].rotation) < 0.00001, "Card %d follows the arc continuously and finishes upright at center" % index)
		check(pool.state == "requesting" and pool.result_id.is_empty(), "Arriving before the network never reveals an invented result")
		pool.settle_to("0004")
		check(pool.state == "aligned" and pool._target_index == index, "A late receipt attaches to the card already centered")
	pool.freeze(); pool.queue_free()
	await pause(0.05)
