extends SceneTree
const Reveal = preload("res://scripts/card_reveal.gd")
const Delayed = preload("res://tools/fixtures/delayed_card_reveal.gd")
var failures: Array[String] = []
var page: Node
var store: Node
var motion: Node
var folder := "res://outputs/card-reveal-validation"
var sheet: Image

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func frames(count := 4) -> void:
	for i in count:
		await process_frame

func loaded(preview: Control) -> void:
	for i in 400:
		if preview.state != "loading":
			return
		await create_timer(0.01).timeout
	check(false, "Texture loading must finish")

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event)
		await process_frame

func capture(name: String, column := -1, row := -1) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await frames(2)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(folder.path_join(name + ".png"))
	if column >= 0:
		var scale_factor := Vector2(image.get_size()) / root.get_visible_rect().size
		var bounds: Rect2 = page.detail_panel.get_global_rect()
		var region := image.get_region(Rect2i(bounds.position * scale_factor, bounds.size * scale_factor))
		var thumb := Image.create(280, 500, false, Image.FORMAT_RGBA8)
		thumb.fill(Color.WHITE)
		var fit := minf(280.0 / region.get_width(), 500.0 / region.get_height())
		region.resize(roundi(region.get_width() * fit), roundi(region.get_height() * fit), Image.INTERPOLATE_LANCZOS)
		thumb.blit_rect(region, Rect2i(Vector2i.ZERO, region.get_size()), Vector2i((280 - region.get_width()) / 2, 0))
		sheet.blit_rect(thumb, Rect2i(0, 0, 280, 500), Vector2i(column * 280, row * 500))

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		quit(2)
		return
	await frames()
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	DirAccess.make_dir_recursive_absolute(folder)
	root.content_scale_size = Vector2i(1920, 1032)
	root.size = Vector2i(1920, 1032)
	root.mode = Window.MODE_WINDOWED
	motion = root.get_node("UiMotion")
	motion.system_reduced = 0
	motion.suspended = false
	motion.set_enabled(true)
	var router := root.get_node("PageRouter")
	router.go("res://scenes/MyCollection.tscn")
	await scene_changed
	await frames()
	page = current_scene
	store = page.store
	var inventory_before: Dictionary = store.inventory.duplicate(true)
	var revision_before: int = store.revision
	page._set_filter("all")
	page._select_card("0001")
	await loaded(page.reveal)
	check(page.reveal.state in ["ready", "revealing"], "Selecting starts the automatic back-to-front presentation")
	check(not page.detail_panel.get_node("Name").visible, "Hidden details cannot expose the unrevealed name")
	check(page.reveal.find_children("*", "Button", true, false).size() == 1 and page.reveal.retry_button.text == "重新加载", "Reveal has only error retry and no skip button")
	check(page.reveal.card_rect.size.x <= 240.01 and is_equal_approx(page.reveal.card_rect.size.y / page.reveal.card_rect.size.x, 1.5), "Card fits existing width and exact 2:3 aspect")
	var serial: int = page._reveal_serial
	var instance: int = page.reveal.get_instance_id()
	page._select_card("0001")
	page._select_card("0001")
	check(page._reveal_serial == serial and page.reveal.get_instance_id() == instance, "Repeated selection during playback does not restart")
	page.reveal._kill_tween()
	page.reveal._set_elapsed(Reveal.ENTRY + 0.79)
	var before: float = page.reveal.flip_material.get_shader_parameter("turn")
	page.reveal._set_elapsed(Reveal.ENTRY + 0.80)
	var middle: float = page.reveal.flip_material.get_shader_parameter("turn")
	page.reveal._set_elapsed(Reveal.ENTRY + 0.81)
	var after: float = page.reveal.flip_material.get_shader_parameter("turn")
	check(before < PI / 2 and is_equal_approx(middle, PI / 2) and after > middle and absf((middle - before) - (after - middle)) < 0.005, "Turn crosses 90 degrees continuously at 800 ms")
	var elapsed: float = page._reveal_session.elapsed
	page._on_data_changed()
	await loaded(page.reveal)
	check(page._reveal_serial == serial and page._reveal_session.elapsed >= elapsed, "Inventory refresh restores the same session and progress")
	root.get_node("AppState").dark_mode = true
	page._rebuild()
	await loaded(page.reveal)
	check(page._reveal_serial == serial and page._reveal_session.elapsed >= elapsed, "Theme rebuild restores the current turn")
	root.get_node("AppState").dark_mode = false
	page._rebuild()
	await loaded(page.reveal)
	var completions := [0]
	page.reveal.completed.connect(func(_card: String, _serial: int): completions[0] += 1)
	page.tiles["0001"].grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	root.push_input(space)
	space = space.duplicate()
	space.echo = true
	root.push_input(space)
	space = space.duplicate()
	space.pressed = false
	space.echo = false
	root.push_input(space)
	await frames()
	await key(KEY_SPACE)
	page.reveal.skip()
	await frames()
	check(page.reveal.state == "revealed" and completions[0] == 1 and page._reveal_serial == serial, "Space, held-key echoes and repeated Space finish once without accidental replay")
	check(root.gui_get_focus_owner() == page.tiles["0001"], "Skip restores focus to the selected tile")
	check(page.reveal.face.texture.resource_path == store.card("0001").image and page.reveal.face.material == null, "Final full-colour surface is the unmodified original texture")
	check(page.detail_panel.get_node("Name").visible and not page.detail_panel.get_node("Want").disabled, "Final details and actions remain usable")
	check(page.reveal.orbit_alpha == 0 and page.reveal.sparkle_progress == 0 and page.reveal._tween == null and not page.reveal.is_processing(), "Skip removes all transient effects and processing")
	page._select_card("0001")
	check(page._reveal_serial == serial + 1, "Selecting the finished card explicitly replays it")
	page._select_card("0002")
	page._select_card("0003")
	await loaded(page.reveal)
	await create_timer(2.25).timeout
	check(page.reveal.state == "revealed" and page.reveal.session.card.id == "0003" and page.reveal.face.texture.resource_path == store.card("0003").image, "Natural playback after rapid switching ends on the last selected card")
	serial = page._reveal_serial
	page._toggle_wanted("0003")
	await loaded(page.reveal)
	check(page._reveal_serial == serial and page.reveal.state == "revealed", "Wanted update preserves finished card without replay")
	page._select_card("0004")
	await loaded(page.reveal)
	var cancelled: Control = page.reveal
	router.go("res://scenes/Workbench.tscn")
	await scene_changed
	await frames()
	check(cancelled.state == "cancelled" and cancelled._tween == null and not cancelled.is_processing(), "Leaving cancels all presentation work on a cached page")
	router.go("res://scenes/MyCollection.tscn")
	await scene_changed
	await loaded(page.reveal)
	check(page.reveal.state == "revealed" and page.selected_id == "0004", "Cached return displays the same static front")
	page.tiles["0005"].grab_focus()
	await key(KEY_ENTER)
	await loaded(page.reveal)
	check(page.selected_id == "0005" and page.reveal.state != "revealed", "Keyboard tile selection starts the intended card")
	await key(KEY_ESCAPE)
	check(not page.in_detail, "Escape returns to overview during the reveal")
	motion.set_enabled(false)
	page._select_card("0006")
	await loaded(page.reveal)
	check(page.reveal.session.reduced and page.reveal.orbit_alpha == 0, "Reduced-motion uses the short fade without orbit")
	await create_timer(0.22).timeout
	check(page.reveal.state == "revealed" and page.reveal.detail_offset == 0, "Reduced-motion fade finishes with full actions")
	motion.set_enabled(true)
	page._select_card("0007")
	await loaded(page.reveal)
	motion.set_enabled(false)
	await create_timer(0.22).timeout
	check(page.reveal.state == "revealed" and page.reveal.sparkle_progress == 0, "Changing preference mid-turn settles the same card")
	motion.set_enabled(true)
	await _loading_and_errors()
	check(store.inventory == inventory_before and store.revision == revision_before and not store.inventory_known, "All reveals, skips, retries and closes leave inventory unchanged")
	await _visual_cards()
	await _layouts()
	# Suppress the destination workbench's unrelated 1.7-second chart reveal.
	motion.set_enabled(false)
	router.go("res://scenes/Workbench.tscn")
	await scene_changed
	await create_timer(0.3).timeout
	check(root.get_node("UiResources")._texture_requests.is_empty(), "Texture cache drains abandoned requests")
	check(motion.tracks.is_empty() and get_processed_tweens().is_empty(), "Leaving leaves no orphaned or looping Tweens")
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _loading_and_errors() -> void:
	var back: String = store.seasons[0].back_image
	var slow := Delayed.new()
	root.add_child(slow)
	slow.size = Vector2(400, 420)
	var first: Dictionary = Reveal.new_session(store.card("0001"), back, 900)
	slow.present(first)
	slow.skip()
	check(slow.state == "loading" and not first.completed, "Skip cannot manufacture a result while loading")
	slow.cancel()
	slow.hold_loading = false
	await frames()
	check(slow.state == "cancelled" and not slow.is_processing(), "Late readiness cannot reopen a cancelled card")
	slow.hold_loading = true
	slow.present(Reveal.new_session(store.card("0002"), back, 901))
	slow.present(Reveal.new_session(store.card("0007"), back, 902))
	slow.hold_loading = false
	await loaded(slow)
	slow.skip()
	check(slow.session.card.id == "0007" and slow.face.texture.resource_path == store.card("0007").image, "Old loading result cannot replace a new session")
	slow.queue_free()
	await frames()
	for bad_back in [false, true]:
		var item: Dictionary = store.card("0006").duplicate(true)
		if not bad_back:
			item.image = "res://missing-reveal-test.png"
		var preview := Reveal.new()
		root.add_child(preview)
		preview.size = Vector2(400, 420)
		var result: Dictionary = Reveal.new_session(item, "res://missing-back-test.png" if bad_back else back, 903)
		preview.present(result)
		check(preview.state == "error" and preview.retry_button.visible and preview.accessibility_name.contains("射电望远镜") and preview.face.texture == null, "Missing face/back exposes exact identity and retry without substitute artwork")
		preview.session.card.image = store.card("0006").image
		preview.session.back = back
		preview.retry()
		await loaded(preview)
		preview.skip()
		check(preview.state == "revealed" and preview.session.id == 903, "Retry loads the same session without another result")
		preview.queue_free()
		await frames()

func _visual_cards() -> void:
	sheet = Image.create(1960, 1500, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	for index in store.cards.size():
		var card: Dictionary = store.cards[index]
		page._select_card(str(card.id))
		await loaded(page.reveal)
		page.reveal._kill_tween()
		page.reveal._set_elapsed(Reveal.ENTRY + 0.28)
		await capture(str(card.number) + "-back-orbit", index, 0)
		page.reveal._set_elapsed(Reveal.ENTRY + 0.91)
		await capture(str(card.number) + "-turn", index, 1)
		page.reveal.skip()
		await capture(str(card.number) + "-front", index, 2)
		check(page.reveal.face.texture.resource_path == card.image and page.reveal.session.card.number == card.number, "Exact configured image and printed number: " + str(card.id))
	if DisplayServer.get_name() != "headless":
		sheet.save_png(folder.path_join("seven-card-contact-sheet.png"))
	# Same geometry/colours for a new identity: no card-ID animation branches.
	var extra: Dictionary = store.cards[0].duplicate(true)
	extra.id = "test-future-card"
	extra.number = "08"
	var preview := Reveal.new()
	root.add_child(preview)
	preview.size = Vector2(400, 420)
	preview.present(Reveal.new_session(extra, store.seasons[0].back_image, 904))
	await loaded(preview)
	preview.skip()
	check(preview.state == "revealed" and preview.session.card.id == "test-future-card", "Additional cards reuse the same control via configuration")
	preview.queue_free()
	await frames()

func _layouts() -> void:
	for dimensions in [Vector2i(1920, 1032), Vector2i(800, 720), Vector2i(1600, 400), Vector2i(960, 540)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		await frames()
		check(is_equal_approx(page.reveal.card_rect.size.y / page.reveal.card_rect.size.x, 1.5), "Card aspect survives layout " + str(dimensions))
		check(page.detail_panel.get_node("Want").get_rect().end.y <= page.detail_panel.size.y + 1, "Actions fit their scrollable/fixed detail " + str(dimensions))
		page._select_card("0001" if page.selected_id != "0001" else "0002")
		await loaded(page.reveal)
		await key(KEY_SPACE)
		check(page.reveal.state == "revealed", "Space skips in every layout " + str(dimensions))
		await capture("layout-%dx%d" % [dimensions.x, dimensions.y])
		if page.scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO:
			await frames()
			check(page.scroll.get_global_rect().encloses(page.reveal.face.get_global_rect()), "Whole card fits short/narrow viewport " + str(dimensions))
			page.scroll.scroll_vertical = int(page.content_height)
			await frames()
			check(page.scroll.get_global_rect().encloses(page.detail_panel.get_node("Want").get_global_rect()), "Actions can be scrolled fully into view " + str(dimensions))
			await capture("layout-%dx%d-actions" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1920, 1032)
	root.content_scale_size = Vector2i(1920, 1032)
	await frames()
