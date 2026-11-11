extends "res://tools/check_card_carousel.gd"
var shots: Array[Dictionary] = []

func mouse_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = down
	root.push_input(event, true)

func center_of(slot: Control) -> Vector2:
	return slot.get_global_transform_with_canvas() * (slot.size * 0.5)

func snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	shots.append({"name": name, "image": root.get_texture().get_image()})

func follows(pool: Node, index: int) -> bool:
	var fx: Node2D = pool.selection_feedback
	var slot: Control = pool.slots[index]
	return fx.position.distance_to(slot.position + slot.pivot_offset) < 0.01 and fx.scale.is_equal_approx(slot.scale) and is_equal_approx(fx.rotation, slot.rotation) and fx.modulate.is_equal_approx(slot.modulate)

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"): quit(2); return
	create_timer(60.0).timeout.connect(func(): push_error("Selection feedback validation timed out"); quit(1))
	await pause()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1920, 1080); root.size = Vector2i(1920, 1080)
	if DisplayServer.get_name() != "headless": root.unfocusable = true; root.position = Vector2i(-10000, -10000)
	output = "res://outputs/card-selection-validation"
	DirAccess.make_dir_recursive_absolute(output)
	profile = root.get_node("ProfileStore"); motion = root.get_node("UiMotion")
	# The off-screen test window must keep animating while the user works in
	# another app. Explicit set_enabled(false) still tests reduced motion.
	motion.preference_changed.connect(func(): motion.system_reduced = 0; motion.suspended = false)
	api = Fixture.new(); root.add_child(api); await login(Fixture.A)
	root.get_node("PageRouter").go("res://scenes/MyCollection.tscn"); await scene_changed
	page = current_scene; draws = page.draw_store; wallet = root.get_node("AppServices").wallet_store()
	api.balances[Fixture.A] = 10000; api.wallet_revisions[Fixture.A] += 1
	wallet.refresh_balance(); await pause()
	motion.system_reduced = 0; motion.suspended = false; motion.set_enabled(true)
	var dialog: Node = await open()
	var pool: Node = dialog.carousel
	var fx: Node2D = pool.selection_feedback
	check(fx.active_index == -1 and not fx.visible, "Opening the card pool does not invent selection feedback")
	var index := 3
	var slot: Control = pool.slots[index]
	await move_to(center_of(slot))
	mouse_button(center_of(slot), true)
	check(fx.active_index == index and fx.visible and fx._glow.material.get_shader_parameter("strength") > 0.0 and api.draw_calls.is_empty(), "Mouse-down immediately lights the clicked PNG edge without buying")
	await pause(0.035)
	mouse_button(dialog.close_button.get_global_rect().get_center(), false)
	await pause(0.10)
	check(fx.active_index == -1 and api.draw_calls.is_empty(), "Releasing outside the card cancels its press feedback without buying")
	check(pool.slots.all(func(card): return is_zero_approx(float(card.material.get_shader_parameter("selection_light")))), "Cancelling the press clears every card-back light")
	index = 4; slot = pool.slots[index]
	api.draw_delay = 0.85
	await move_to(center_of(slot))
	mouse_button(center_of(slot), true)
	await pause(0.025)
	await snapshot("01-pressed-edge")
	mouse_button(center_of(slot), false)
	check(fx.committed and fx.active_index == index and api.draw_calls.size() == 1 and not pool.selection_enabled, "The same selection starts feedback and dispatches exactly one existing request")
	check(not api.draw_calls[0].has("card_id") and not api.draw_calls[0].has("index"), "Feedback never chooses or sends a prize identity")
	dialog.hit.pressed.emit(); dialog.hit.pressed.emit()
	await pause(0.12)
	check(follows(pool, index) and fx.card_scale() > 0.97 and fx.card_scale() <= 1.031, "Orbit feedback follows the selected card's moving pose and controlled rebound")
	await snapshot("02-orbit-unfolding")
	await pause(0.08)
	check(fx.elapsed >= 0.12 and fx.elapsed < Tokens.CARD_PICK_DURATION and follows(pool, index), "Star trails and arcs share the moving card center rather than the original click point")
	await snapshot("03-orbit-and-stars-peak")
	var phase_before: float = pool.phase
	pool.phase = index - pool.cards.size() * 0.5
	pool._render_frame()
	check(fx.modulate.a == 0.0 and slot.modulate.a == 0.0, "The complete effect fades with its card at the carousel wrap")
	pool.phase = phase_before; pool._render_frame()
	await pause(0.27)
	check(fx._timeline == null and fx.active_index == index and is_equal_approx(fx.card_scale(), 1.0), "The burst settles into a stable outline without an idle animation loop")
	check(is_equal_approx(float(slot.material.get_shader_parameter("selection_light")), Tokens.CARD_PICK_BACK_LIGHT), "The selected card back stays illuminated after the orbit burst ends")
	var lit_cards := 0
	for card in pool.slots:
		if float(card.material.get_shader_parameter("selection_light")) > 0.0: lit_cards += 1
	check(lit_cards == 1, "Only the selected card receives the steady card-back light")
	check(api.draw_calls.size() == 1 and not dialog.preview.visible and not dialog.details.visible, "Slow network retains the same selected back without fabricating a reward")
	await snapshot("04-settled-selection")
	await until(func(): return dialog.state == "revealing", "The selected card hands off to the original flip")
	check(not fx.visible and fx.active_index == -1 and fx._timeline == null and fx._fade == null, "Selection effects are gone before the 700ms flip begins")
	check(pool.slots.all(func(card): return is_zero_approx(float(card.material.get_shader_parameter("selection_light")))), "The original card-back colors are restored before reveal handoff")
	await until(func(): return dialog.state == "result", "The original reveal completes")
	check(api.grants == 1 and wallet.balance == 9800 and dialog.preview.session.card.id == "0004", "Visual feedback preserves the actual receipt, one grant and 200 battery price")
	dialog.dismiss(); await pause()
	# Skip cancels all feedback tracks and displays the same result.
	api.draw_delay = 0.03
	dialog = await open(); dialog.hit.pressed.emit()
	await until(func(): return draws.ready_result(), "The next verified receipt arrives")
	key(KEY_SPACE, true); key(KEY_SPACE, false)
	await until(func(): return dialog.state == "result", "Skip reaches the same stable result")
	check(dialog.carousel.selection_feedback.active_index == -1 and dialog.carousel.selection_feedback._timeline == null and api.grants == 2, "Skipping cancels selection feedback without duplicate rewards")
	dialog.dismiss(); await pause()
	# Close on the peak, then recover the late receipt without replaying a click.
	api.draw_delay = 0.85
	dialog = await open(); dialog.hit.pressed.emit(); await pause(0.14)
	fx = dialog.carousel.selection_feedback
	var elapsed: float = fx.elapsed
	dialog.dismiss(); motion.set_enabled(false); await pause(0.05)
	check(fx.elapsed == elapsed and fx._timeline == null and fx._fade == null, "Closing freezes the currently visible effect and cancels its callbacks")
	check(fx._frozen and not fx.reduced, "A preference change during exit cannot restart frozen effects")
	await pause(0.85)
	check(not is_instance_valid(page.acquisition) and draws.ready_result() and api.grants == 3, "A late result persists but cannot reopen a closed effect")
	motion.set_enabled(true)
	dialog = await open()
	check(dialog.carousel.selection_feedback.active_index == -1, "Recovering a prior receipt does not replay click effects")
	await result_ready(dialog)
	check(api.grants == 3 and api.draw_calls.size() == 3, "Recovery does not buy another card")
	dialog.dismiss(); await pause()
	# Reduced motion shows only a short edge highlight, without pulse or arcs.
	motion.set_enabled(false); api.draw_delay = 0.30
	dialog = await open(); dialog.hit.pressed.emit()
	fx = dialog.carousel.selection_feedback
	check(fx.reduced and fx.card_scale() == 1.0 and fx.committed, "Reduced motion preserves a short edge-only response")
	await pause(0.06); await snapshot("05-reduced-motion-edge")
	await pause(0.11)
	check(fx._timeline == null and fx.back_light(0.0) > 0.0 and fx.card_scale() == 1.0, "Reduced motion keeps static card-back light after its short edge response")
	var settled_time: float = fx.elapsed
	motion.preference_changed.emit()
	check(fx._timeline == null and fx.elapsed == settled_time, "Repeated reduced-motion notifications do not restart a settled highlight")
	await until(func(): return dialog.state == "result", "Reduced mode displays the same real result")
	check(not fx.visible and api.grants == 4, "Reduced feedback finishes cleanly and awards once")
	dialog.dismiss(); await pause()
	motion.set_enabled(true); api.draw_delay = 0.60
	dialog = await open(); dialog.hit.pressed.emit(); await pause(0.10)
	fx = dialog.carousel.selection_feedback
	motion.set_enabled(false)
	check(fx.reduced and fx.card_scale() == 1.0, "A mid-effect preference change cancels motion immediately")
	await until(func(): return dialog.state == "result", "Preference change retains the verified result")
	dialog.dismiss(); await pause()
	# Save frames after timing-sensitive checks, avoiding PNG compression stalls.
	for shot in shots: shot.image.save_png(output.path_join(shot.name + ".png"))
	print("SELECTION FEEDBACK ASSERTIONS: ", assertions)
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
