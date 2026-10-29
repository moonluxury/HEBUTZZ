extends SceneTree
const Fixture = preload("res://tools/fixtures/collection_provider.gd")
const Store = preload("res://scripts/collection_store.gd")
const CardReveal = preload("res://scripts/card_reveal.gd")
var failures: Array[String] = []
var page: Node
var store: Node
var backend: Node
var screenshot_dir := "res://outputs/collection-validation"

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func check_keep_one_limits() -> void:
	var source := Fixture.new()
	root.add_child(source)
	var inventory_store := Store.new()
	root.add_child(inventory_store)
	inventory_store.use_provider(source, "isolated-keep-one")
	check(inventory_store.gift_rule("0001").max == 0, "Unknown inventory never enables gifting")
	await inventory_store.refresh()
	check(inventory_store.gift_rule("0003").max == 0 and inventory_store.gift_rule("0002").max == 0, "Zero and one copy cannot be gifted")
	check(inventory_store.gift_rule("0001").max == 2 and inventory_store.gift_rule("0004").max == 0, "Keep-one cap still respects stricter service restrictions")
	source.inventory["0001"].giftable_count = 1
	source.revision += 1
	await inventory_store.refresh()
	check(inventory_store.gift_rule("0001").max == 1, "A smaller service cap wins over duplicate count")
	source.inventory["0001"].giftable_count = 3
	source.revision += 1
	await inventory_store.refresh()
	var outcome: Dictionary = await inventory_store.submit_gift("0001", "test-friend-a", 3)
	check(not outcome.ok and outcome.message.contains("保留 1 张") and source.calls == 0 and inventory_store.operation.is_empty(), "Direct submission cannot bypass retain-one or create a pending operation")
	outcome = await inventory_store.submit_gift("0001", "test-friend-a", 2)
	check(outcome.ok and inventory_store.count("0001") == 1 and source.credits["test-friend-a"] == 2, "Three copies may gift two while preserving one")
	outcome = await inventory_store.submit_gift("0001", "test-friend-a", 1)
	check(not outcome.ok and source.calls == 1 and source.transfers == 1 and inventory_store.count("0001") == 1, "The remaining copy cannot be submitted again")
	# A trusted service must recheck the same rule when the client's read is stale.
	source.inventory["0001"] = {"count": 3, "giftable_count": 3}
	source.revision += 1
	await inventory_store.refresh()
	source.inventory["0001"].count = 1
	source.revision += 1
	outcome = await inventory_store.submit_gift("0001", "test-friend-a", 2)
	check(not outcome.ok and inventory_store.count("0001") == 1 and source.transfers == 1, "Authoritative race check rejects losing the last copy without crediting the recipient")
	inventory_store.queue_free()
	source.queue_free()

func frames(n := 4) -> void:
	for index in n:
		await process_frame

func settle_reveal() -> void:
	if not is_instance_valid(page) or not is_instance_valid(page.reveal):
		return
	var preview: Control = page.reveal
	for index in 300:
		if preview.state != "loading":
			break
		await create_timer(0.01).timeout
	preview.skip()

func check_unowned_static() -> void:
	# Do not use settle_reveal(): its skip would hide an accidental animation.
	for index in 300:
		if page.reveal.state != "loading":
			break
		await create_timer(0.01).timeout
	check(page.reveal.state == "revealed" and page.reveal.session.static and page.reveal._tween == null, "Unowned card goes straight to a static front without a reveal")
	check(page.reveal.face.material == page.reveal.gray_material and page.reveal.face.texture.resource_path == store.card(page.selected_id).image, "Unowned detail stays grayscale in every filter")
	check(page.reveal.detail_alpha == 1 and page.reveal.interactive and page.reveal.orbit_alpha == 0 and page.reveal.sparkle_progress == 0, "Static unowned detail has no effects and keeps its actions available")

func key(window: Window, code: Key, shift := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.shift_pressed = shift
		event.pressed = pressed
		# Embedded windows must receive input through their embedder, which invokes
		# the native Window/PopupMenu input path before the Viewport GUI path.
		(root if window.is_embedded() else window).push_input(event)
		await process_frame

func click(control: Control, button: MouseButton) -> void:
	var point := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = point
		event.global_position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func capture(file: String, fixture := true) -> void:
	await settle_reveal()
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)
	var label := Label.new()
	label.text = "隔离测试运行 · 库存与好友为测试数据" if fixture else "实际运行 · 公开目录 / 本机档案 · 未接入库存服务"
	label.add_theme_color_override("font_color", Color("#092C87"))
	label.add_theme_font_size_override("font_size", 18)
	label.position = Vector2(280, 8)
	layer.add_child(label)
	await create_timer(0.26).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(screenshot_dir.path_join(file + ".png"))
	layer.queue_free()

func check_rendered_art(art: Control, gray: bool) -> void:
	await settle_reveal()
	if art is CardReveal:
		art = art.face
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var pixel_scale := Vector2(image.get_size()) / root.get_visible_rect().size
	var rect := art.get_global_rect()
	var chroma := 0.0
	for x in [0.2, 0.5, 0.8]:
		for y in [0.2, 0.5, 0.8]:
			var point := (rect.position + rect.size * Vector2(x, y)) * pixel_scale
			var color := image.get_pixelv(Vector2i(point))
			chroma = maxf(chroma, maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)))
	check(chroma < 0.02 if gray else chroma > 0.1, "Wanted unowned card is grayscale" if gray else "Catalogue artwork retains source colors")

func check_complete_detail() -> void:
	check(not page.content.has_node("CardDetailsScroll") and page.detail_panel.get_parent() == page.content, "Right detail has no independent scroll container")
	var panel: Control = page.detail_panel
	check(panel.get_global_rect().end.y <= page.scroll.get_global_rect().end.y + 1, "Entire fixed detail fits inside the viewport")
	for child in panel.get_children():
		if child is Label and child.text.is_empty():
			continue
		if child is Control:
			check(child.position.y >= 0 and child.position.y + child.size.y <= panel.size.y + 1, "Detail content fits without clipping: " + child.name)
	check(panel.get_node("Preview").card_rect.size.x >= 180, "Detail artwork is larger than the previous compact preview")
	check(panel.get_node("Preview").session.card.image == store.card(page.selected_id).image, "Right detail uses the full framed card with its printed text")

func check_filter_row() -> void:
	for button in page.filter_buttons.values():
		check(button.is_visible_in_tree() == not page.in_detail, "Filters are visible only in the collection overview")
	if page.in_detail:
		return
	var subtitle: Rect2 = page.body.get_node("Subtitle").get_global_rect()
	var first_tab: Rect2 = page.filter_buttons.owned.get_global_rect()
	check(is_equal_approx(subtitle.get_center().y, first_tab.get_center().y) and subtitle.end.x < first_tab.position.x, "Filters align with subtitle without overlapping it")

func check_name_count(title: Label, quantity: Label) -> void:
	check(is_equal_approx(title.get_rect().get_center().y, quantity.get_rect().get_center().y), "Quantity shares the card-name row")
	check(title.get_rect().end.x + 7 <= quantity.position.x and quantity.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "Card name and right-aligned quantity do not overlap")
	check(quantity.text.begins_with("×") and not quantity.text.contains("未接入"), "Quantity is a compact multiplier, not a separate status sentence")

func check_four_columns() -> void:
	var grid: Control = page.card_scroll.get_node("DetailGrid")
	check(grid.get_child_count() >= 5, "Public catalogue can fill four columns")
	for index in 4:
		check(is_zero_approx(grid.get_child(index).position.y), "The first four cards share a row")
	check(grid.get_child(4).position.y > 0, "The fifth card starts the second row")
	for tile in grid.get_children():
		check_name_count(tile.get_node("CardName"), tile.get_node("Owned"))
		var title: Label = tile.get_node("CardName")
		var text_width := title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
		check(text_width <= title.size.x + 1, "Four-column desktop keeps the full public card name visible: " + title.text)
	check_name_count(page.detail_panel.get_node("Name"), page.detail_panel.get_node("Quantity"))

func check_disclosure() -> void:
	var motion: Node = root.get_node("UiMotion")
	motion._resume()
	var id := "season-001"
	var toggle: Button = page.groups[id].get_node("Toggle")
	var arrow: TextureRect = toggle.get_node("Chevron")
	check(toggle.text.is_empty() and toggle.get_node("SeasonTitle").text == store.season(id).name, "Season title uses separate artwork instead of arrow glyphs")
	check(arrow.texture.resource_path == "res://assets/minimal/icons/collection-chevron.png" and arrow.texture.get_width() == 384, "Disclosure uses the dedicated high-resolution asset")
	check(arrow.pivot_offset == arrow.size * 0.5 and is_equal_approx(arrow.rotation, PI * 0.5), "Expanded icon is centered and points down")
	var title_position: Vector2 = toggle.get_node("SeasonTitle").global_position
	page._toggle_group(id)
	arrow = page.groups[id].get_node("Toggle/Chevron")
	check(not page.expanded[id] and not page.groups[id].has_node("Grid"), "Collapse takes effect immediately")
	if not motion.reduced():
		check(is_equal_approx(arrow.rotation, PI * 0.5), "Collapse animation starts at the previous visible angle")
		await create_timer(page.Tokens.CHEVRON * 0.3).timeout
		check(arrow.rotation > 0 and arrow.rotation < PI * 0.5, "Disclosure rotates progressively rather than swapping a glyph")
		var partial := arrow.rotation
		page._toggle_group(id)
		arrow = page.groups[id].get_node("Toggle/Chevron")
		check(is_equal_approx(arrow.rotation, partial), "Rapid reversal starts from the currently displayed angle")
	else:
		page._toggle_group(id)
	for index in 4:
		page._toggle_group(id)
	await create_timer(page.Tokens.CHEVRON + 0.06).timeout
	arrow = page.groups[id].get_node("Toggle/Chevron")
	check(page.expanded[id] and page.groups[id].has_node("Grid") and is_equal_approx(arrow.rotation, PI * 0.5), "Rapid toggles settle to the latest expanded state")
	check(page.groups[id].get_node("Toggle/SeasonTitle").global_position == title_position, "Only the disclosure art rotates, keeping the title in place")
	motion.set_enabled(false)
	page._toggle_group(id)
	check(is_zero_approx(page.groups[id].get_node("Toggle/Chevron").rotation), "Reduced motion shows the collapsed icon immediately")
	page._toggle_group(id)
	motion.set_enabled(true)

func _run() -> void:
	if not OS.get_user_data_dir().contains("workbench-check"):
		push_error("Use run_workbench_checks.py; real account data is forbidden.")
		quit(2)
		return
	# Finish the application's initial desktop fitting before sizing the test window.
	await frames()
	if DisplayServer.get_name() != "headless":
		root.unfocusable = true
		root.position = Vector2i(-10000, -10000)
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	root.mode = Window.MODE_WINDOWED
	root.gui_embed_subwindows = true
	var router := root.get_node("PageRouter")
	router.go("res://scenes/MyCollection.tscn")
	await scene_changed
	await frames()
	page = current_scene
	store = page.store
	check(store.cards.size() == 7 and store.seasons.size() == 1, "Approved public seven-card catalogue")
	check(not page.has_node("SeasonNavigation") and store.seasons[0].id == "season-001", "Season dropdown removed without changing catalogue identity")
	check(not page.status_label.visible and page.status_label.text.is_empty(), "Permanent integration banner removed")
	check(not store.inventory_known and page.tiles.is_empty(), "Missing inventory never fabricates holdings")
	check(page.summary_label.text.contains("—"), "Unavailable totals are explicit")
	check_filter_row()
	check(not page.has_node("ReturnCollection") and not page.body.has_node("CollectionToolbar"), "Return-to-collection button is removed")
	check(not page.body.has_node("CollectionToolbar") and is_equal_approx(page.content.position.y, 126), "Overview removes the empty toolbar row and moves its contents upward")
	await capture("01-live-empty", false)
	page._set_filter("all")
	await frames()
	check(page.tiles.size() == 7, "All catalogue cards are visible")
	check(page.tiles["0001"].get_node("Art").material == null, "Unknown inventory is not classified as unowned")
	for item in store.cards:
		check(page.tiles[item.id].get_node("Art").texture.resource_path == item.artwork, "All-cards view loads the standalone illustration: " + item.id)
		check(not page.tiles[item.id].has_node("More"), "Ellipsis removed from tile: " + item.id)
	check(page.find_children("*", "PopupMenu", true, false).is_empty() and not page.has_method("_open_menu"), "Card menu and its behavior are removed")
	await check_disclosure()
	page._select_card("0001")
	await frames()
	check(is_equal_approx(page.content.position.y, 126) and not page.body.has_node("CollectionToolbar"), "Detail shares the raised content position without the removed back-button row")
	check(page.detail_panel.get_node("Gift").disabled and page.detail_panel.get_node("Gift").text == "库存未接入" and page.detail_panel.get_node("Facts").text.is_empty(), "Missing inventory remains explicit and cannot enable gifting")
	root.size = Vector2i(1920, 1032)
	root.content_scale_size = Vector2i(1920, 1032)
	await frames()
	check_complete_detail()
	check_four_columns()
	check(page.tiles["0001"].get_node("Owned").text == "×—" and page.detail_panel.get_node("Quantity").text == "×—", "Unavailable inventory stays unknown in both card list and detail")
	await capture("10-live-compact-detail", false)
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = Vector2i(1600, 1000)
	await frames()
	page._return_overview()
	await frames()
	await capture("02-live-catalogue", false)
	# Only here install controlled backend; formal paths never load this fixture.
	backend = Fixture.new()
	root.add_child(backend)
	store.use_provider(backend, "isolated-account-a")
	await store.refresh()
	check(store.summary().kinds == 3 and store.summary().total == 6, "Copies merge; zero-stock history excluded")
	await check_keep_one_limits()
	backend.snapshot_delay = 12
	await frames()
	check(page.find_child("RefreshInventory", true, false) == null and not page.body.has_node("CollectionToolbar"), "Signed-in collection has no refresh control or reserved toolbar")
	store.refresh()
	check(store.loading, "Existing inventory loading still works without a manual refresh control")
	await frames(15)
	backend.snapshot_delay = 0
	page._set_filter("owned")
	check(page.tiles.size() == 3, "Owned filter uses current positive inventory")
	check(page.tiles["0001"].get_node("Owned").text == "×3", "Known inventory is displayed as a real inline count")
	check(page.tiles["0001"].get_node("Art").texture.resource_path == store.card("0001").artwork, "Owned list also uses unframed artwork")
	page._set_filter("all")
	check(page.tiles.size() == 7 and store.summary().total == 6, "Global summary unaffected by filters")
	await frames()
	await click(page.tiles["0001"], MOUSE_BUTTON_RIGHT)
	check(not page.in_detail and store.wanted.is_empty(), "Right click no longer opens actions or mutates collection")
	page.tiles["0002"].grab_focus()
	await key(root, KEY_F10, true)
	check(not page.in_detail and page.find_children("*", "PopupMenu", true, false).is_empty(), "Removed keyboard menu shortcut has no action")
	await key(root, KEY_ENTER)
	await frames()
	check(page.in_detail and page.selected_id == "0002", "Keyboard Enter on artwork opens exact card detail")
	await settle_reveal()
	check(page.detail_panel.get_node("Gift").disabled and page.detail_panel.get_node("Gift").text == "仅有 1 张" and page.detail_panel.get_node("GiftReason").text.contains("保留 1 张"), "One-copy detail explains why gifting is disabled")
	page._open_gift("0002")
	check(page.gift_dialog == null, "One-copy cards cannot open the gift flow")
	await key(root, KEY_ESCAPE)
	await frames()
	check(not page.in_detail and current_scene == page, "Page-local Escape restores overview, shell stays mounted")
	var result: Dictionary = store.set_wanted("0001", true)
	check(result.ok and store.is_wanted("0001"), "Owned duplicates may also be wanted")
	store.set_wanted("0003", true)
	for value in [false, true, false, true]:
		store.set_wanted("0001", value)
	var copy := Store.new()
	root.add_child(copy)
	copy.use_provider(backend, "isolated-account-a")
	check(copy.is_wanted("0001") and copy.is_wanted("0003"), "Last rapid intent survives reload")
	copy.use_provider(backend, "isolated-account-b")
	check(copy.wanted.is_empty(), "Wanted marks are account scoped")
	copy.queue_free()
	var previous: Dictionary = store.wanted.duplicate()
	DirAccess.make_dir_recursive_absolute(store._path() + ".tmp")
	result = store.set_wanted("0002", true)
	check(not result.ok and store.wanted == previous, "Disk failure rolls back exact wanted state")
	DirAccess.remove_absolute(store._path() + ".tmp")
	check(store.set_wanted("0002", true).ok, "Persistence recovers after writable storage returns")
	store.set_wanted("0002", false)
	page._set_filter("wanted")
	page._select_card("0003")
	await check_unowned_static()
	check(page.detail_panel.get_node("Gift").disabled and page.detail_panel.get_node("Gift").text == "未拥有" and page.detail_panel.get_node("Quantity").text == "×0", "Known zero inventory shows zero and cannot enable gifting")
	check(page.tiles["0003"].get_node("Art").texture.resource_path == store.card("0003").artwork, "Wanted list uses unframed artwork")
	check(page.detail_panel.get_node("Preview").session.card.image == store.card("0003").image, "Wanted detail retains full card design")
	await frames()
	await check_rendered_art(page.tiles["0003"].get_node("Art"), true)
	await check_rendered_art(page.detail_panel.get_node("Preview"), true)
	page._toggle_wanted("0003")
	check(page.selected_id == "0001" and page.tiles.size() == 1, "Removing selected wanted card selects remaining card")
	page._toggle_wanted("0001")
	check(page.selected_id.is_empty() and page.detail_panel.has_node("EmptyTitle"), "Removing last wanted card clears detail")
	page._return_overview()
	page._set_filter("all")
	store.set_wanted("0001", true)
	# Second season only in test memory, with distinct stable card and variant IDs.
	store.seasons.append({"id": "test-season-2", "label": "测试季", "name": "隔离归档"})
	var variant: Dictionary = store.cards[0].duplicate(true)
	variant.id = "test-variant-1"
	variant.season_id = "test-season-2"
	store.cards.append(variant)
	page._rebuild()
	page._toggle_group("test-season-2")
	check(page.expanded["season-001"] and page.expanded["test-season-2"], "Season groups remain independently browsable without the dropdown")
	page._toggle_group("test-season-2")
	page.scroll.scroll_vertical = 200
	await frames()
	var old_scroll: int = page.scroll.scroll_vertical
	page._select_card("0001")
	var tile_id: int = page.tiles["0002"].get_instance_id()
	for id in ["0002", "0004", "0001", "0003", "0002"]:
		page._select_card(id)
		check(page.detail_panel.get_node("Name").text == store.card(id).name and page.detail_panel.get_node("Quantity").text == page._count_badge(id), "Fast selection binds all details to same stable ID")
	check(page.tiles["0002"].get_instance_id() == tile_id, "Switching cards retains left grid controls")
	page._return_overview()
	await frames()
	check(page.filter == "all" and not page.expanded["test-season-2"] and page.scroll.scroll_vertical == old_scroll, "Return restores filter, expansion and exact scroll")
	check(page.get_viewport().gui_get_focus_owner() == page.tiles["0001"], "Return restores initiating stable card focus")
	page._toggle_group("test-season-2")
	page._select_card("test-variant-1")
	check(page.selected_id == "test-variant-1" and page.selected_season == "test-season-2", "Opening a card selects its own season and stable variant")
	page._set_filter("owned")
	check(page.selected_id.is_empty(), "Empty season/filter clears stale selection")
	page._return_overview()
	page._toggle_group("test-season-2")
	# Returning restores focus/scroll over two frames. Headless capture is a no-op;
	# wait before positioning a real click so the target cannot move on mouse-up.
	await frames()
	page.scroll.scroll_vertical = 0
	page.selected_season = "season-001"
	await frames()
	await capture("03-fixture-overview")
	await click(page.tiles["0001"], MOUSE_BUTTON_LEFT)
	await frames()
	check(page.selected_id == "0001" and page.in_detail, "Left click opens the selected card")
	await capture("04-fixture-detail")
	check_complete_detail()
	check_filter_row()
	check_four_columns()
	for tile in page.tiles.values():
		var tile_style: StyleBoxFlat = tile.get_theme_stylebox("normal")
		check(tile_style.border_color.a == 0 and tile_style.get_border_width(SIDE_LEFT) == 0, "Tile selection never adds a colored border")
	var selected_style: StyleBoxFlat = page.tiles["0001"].get_theme_stylebox("normal")
	var idle_style: StyleBoxFlat = page.tiles["0002"].get_theme_stylebox("normal")
	check(selected_style.bg_color.a > 0 and selected_style.bg_color.get_luminance() < page.surface.get_luminance() and selected_style.bg_color != idle_style.bg_color, "Selected tile has a darker background than idle tiles")
	for entry in [["Name", 24], ["Metadata", 14], ["Description", 16], ["Quantity", 18], ["Facts", 14], ["Gift", 18], ["Want", 18], ["GiftReason", 14]]:
		check(page.detail_panel.get_node(entry[0]).get_theme_font_size("font_size") == entry[1], "Right-hand text reduced by four: " + entry[0])
	check(not page.has_method("_open_preview") and not page.detail_panel.has_node("ViewImage"), "Large-image feature and entry are removed")
	await check_rendered_art(page.tiles["0001"].get_node("Art"), false)
	# Seven compact cards may now fit fully. Add isolated cards to exercise overflow.
	var before_overflow: Array = store.cards.duplicate()
	for index in 8:
		var overflow_card: Dictionary = store.cards[0].duplicate(true)
		overflow_card.id = "test-overflow-%d" % index
		store.cards.append(overflow_card)
	page._render()
	await frames()
	var pinned_position: Vector2 = page.detail_panel.global_position
	page.card_scroll.scroll_vertical = 280
	await frames()
	check(page.card_scroll.scroll_vertical > 0 and page.detail_panel.global_position.is_equal_approx(pinned_position) and page.scroll.scroll_vertical == 0, "Left card scrolling keeps right details and page header fixed")
	await capture("09-fixture-fixed-details")
	page.card_scroll.scroll_vertical = 0
	var previous_window_size := root.size
	var previous_scale_size := root.content_scale_size
	root.size = Vector2i(1920, 1032)
	root.content_scale_size = Vector2i(1920, 1032)
	await frames()
	pinned_position = page.detail_panel.global_position
	page.card_scroll.scroll_vertical = 160
	await frames()
	check(page.detail_panel.global_position.is_equal_approx(pinned_position), "Resized desktop retains pinned details")
	check_complete_detail()
	await click(page.detail_panel, MOUSE_BUTTON_WHEEL_DOWN)
	await frames()
	check(page.detail_panel.global_position.is_equal_approx(pinned_position) and page.scroll.scroll_vertical == 0, "Wheel over right detail cannot scroll or hide its content")
	root.size = Vector2i(1600, 400)
	root.content_scale_size = Vector2i(1600, 400)
	await frames()
	check(page.scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO and page.content_height > page.scroll.size.y, "Short windows fall back to scrollable flow instead of clipping actions")
	root.size = previous_window_size
	root.content_scale_size = previous_scale_size
	store.cards = before_overflow
	page._render()
	await frames()
	page.card_scroll.scroll_vertical = 0
	page._select_card("0003")
	await check_unowned_static()
	page._select_card("0003")
	await check_unowned_static()
	page._on_data_changed()
	await check_unowned_static()
	await capture("08-fixture-unowned-detail")
	check(page.tiles["0003"].get_node("Art").material == null, "Public artwork remains in source colors")
	await check_rendered_art(page.tiles["0003"].get_node("Art"), false)
	await check_rendered_art(page.detail_panel.get_node("Preview"), true)
	page._select_card("0001")
	check(not page.reveal.session.static, "Owned cards retain the animated reveal")
	await frames()
	page._open_gift("0001")
	await frames(10)
	var dialog: Window = page.gift_dialog
	check(dialog.card_art.texture.resource_path == store.card("0001").artwork, "Gift thumbnail uses unframed illustration")
	check(dialog.friend_rows.size() == 2 and dialog.confirm.disabled, "Gift waits for real stable recipient selection")
	check(dialog.friend_rows[0].get_node("CardAvatar").source_path == store.card("0004").artwork, "Gift recipients share the circular card-avatar identity")
	await key(dialog, KEY_TAB)
	check(dialog.gui_get_focus_owner() != null and dialog.is_ancestor_of(dialog.gui_get_focus_owner()), "Gift keyboard focus stays in exclusive window")
	dialog._search_friends("甲")
	dialog._search_friends("乙")
	await frames(10)
	check(dialog.friend_rows.size() == 1 and dialog.friend_rows[0].get_meta("friend_id") == "test-friend-b", "Stale friend query cannot overwrite newer query")
	dialog._search_friends("")
	await frames(10)
	dialog._choose_friend(backend.friend_data[0])
	dialog.quantity.get_line_edit().text = "999"
	dialog.quantity.apply()
	check(dialog.quantity.value == 2 and dialog.quantity.max_value == 2, "Three-copy quantity input caps gifts at two")
	dialog.quantity.value = 1
	# SpinBox updates its edit text on the next frame; emulate a real user pause
	# before the next click in headless mode too (visual capture already waits).
	await frames()
	check(dialog.remaining.text == "送出后你将剩余 2 张（至少保留 1 张）。" and not dialog.confirm.disabled, "Gift confirmation shows remainder and retain-one rule")
	await capture("05-fixture-gift-confirm")
	check(dialog.confirm.get_theme_color("font_color") == Color.WHITE, "Enabled gift confirmation retains white primary text")
	dialog._submit()
	dialog._submit()
	await frames(15)
	check(backend.calls == 1 and backend.transfers == 1, "Double confirmation dispatches once")
	check(store.count("0001") == 2 and store.summary().total == 5 and store.summary().kinds == 3, "Three minus one: two copies, total -1, kind unchanged")
	check(store.is_wanted("0001") and backend.credits["test-friend-a"] == 1, "Transfer conserves recipient credit and preserves wanted")
	backend.mode = "quota"
	page._open_gift("0001")
	await frames(10)
	dialog = page.gift_dialog
	dialog._choose_friend(backend.friend_data[1])
	dialog._submit()
	await frames(12)
	check(is_instance_valid(dialog) and dialog.selected_friend.id == "test-friend-b" and dialog.quantity.value == 1 and dialog.error_label.text.contains("额度"), "Failure keeps recipient/quantity and concrete reason")
	check(store.count("0001") == 2 and backend.transfers == 1, "Failure never decrements client inventory")
	dialog.dismiss()
	await frames()
	backend.mode = "unknown"
	page._open_gift("0001")
	await frames(10)
	dialog = page.gift_dialog
	dialog._choose_friend(backend.friend_data[0])
	dialog._submit()
	dialog.dismiss()
	await frames(15)
	check(store.pending() and backend.transfers == 2 and store.count("0001") == 2, "Closing in flight leaves unknown outcome pending without speculative inventory")
	var operation_id: String = store.operation.id
	var call_count: int = backend.calls
	result = await store.submit_gift("0001", "test-friend-a", 1)
	check(not result.ok and backend.calls == call_count, "Unknown result blocks all new sends")
	var reloaded := Store.new()
	root.add_child(reloaded)
	reloaded.use_provider(backend, "isolated-account-a")
	check(reloaded.pending() and reloaded.operation.id == operation_id, "Pending operation survives restart")
	result = await reloaded.recover_gift()
	check(result.ok and reloaded.count("0001") == 1 and backend.transfers == 2, "Recovery queries same ID without second transfer")
	reloaded.queue_free()
	result = await store.recover_gift()
	check(result.ok and store.count("0001") == 1, "Original store reconciles authoritative result")
	call_count = backend.calls
	result = await store.submit_gift("0001", "test-friend-a", 1)
	check(not result.ok and store.count("0001") == 1 and backend.calls == call_count, "Recovered last copy remains protected from a new gift")
	# Isolated service grants another copy, then reports an unrelated stock change.
	backend.inventory["0001"] = {"count": 2, "giftable_count": 2}
	backend.revision += 1
	await store.refresh()
	backend.mode = "stock"
	result = await store.submit_gift("0001", "test-friend-a", 1)
	check(not result.ok and store.count("0001") == 0 and store.summary().kinds == 2, "Inventory failure reconciles authoritative zero stock")
	await check_unowned_static()
	check(store.is_wanted("0001"), "Losing last copy never clears wanted")
	backend.mode = "success"
	# Empty/failing friend sources have distinct prompts and cannot invent recipients.
	backend.inventory["0002"] = {"count": 2, "giftable_count": 2}
	backend.revision += 1
	await store.refresh()
	page._open_gift("0002")
	await frames(10)
	dialog = page.gift_dialog
	dialog._choose_friend(backend.friend_data[0])
	check(not dialog.confirm.disabled and dialog.quantity.max_value == 1, "Two-copy card may gift exactly one")
	backend.inventory["0002"].count = 1
	backend.revision += 1
	await store.refresh()
	check(dialog.confirm.disabled and not dialog.quantity.editable and dialog.error_label.text.contains("保留 1 张"), "Dropping to one while the dialog is open immediately blocks confirmation")
	call_count = backend.calls
	dialog._submit()
	check(backend.calls == call_count, "Stale dialog submission cannot dispatch the last copy")
	backend.inventory["0002"].count = 2
	backend.revision += 1
	await store.refresh()
	check(not dialog.confirm.disabled and dialog.error_label.text.is_empty(), "Refreshed duplicates restore eligibility and clear the stale warning")
	dialog.dismiss()
	await frames()
	page._open_gift("0002")
	await frames(10)
	dialog = page.gift_dialog
	backend.friends_fail = true
	dialog._search_friends("")
	await frames(10)
	check(dialog.friend_status.text.contains("网络连接失败") and dialog.confirm.disabled, "Friend network failure remains actionable without invented choices")
	backend.friends_fail = false
	var saved_friends: Array = backend.friend_data.duplicate(true)
	backend.friend_data.clear()
	dialog._search_friends("")
	await frames(10)
	check(dialog.friend_status.text == "没有可选好友" and dialog.confirm.disabled, "No eligible friends has its own empty state")
	backend.friend_data = saved_friends
	dialog._search_friends("甲")
	dialog.dismiss()
	await frames(10)
	check(page.gift_dialog == null, "Closing during friend search leaves no suspended UI")
	backend.snapshot_fail = true
	await store.refresh()
	check(store.status.contains("网络连接失败"), "Inventory failure exposes server reason and retry")
	backend.snapshot_fail = false
	await store.refresh()
	result = await store.submit_gift("0002", "test-friend-a", 1)
	check(result.ok and store.count("0002") == 1 and store.gift_rule("0002").max == 0, "Gifting one of two keeps the final copy and disables further gifts")
	var latest: int = store.revision
	var stale: Dictionary = backend.snapshot(store.account_id)
	stale.revision = latest - 1
	stale.inventory["0001"].count = 99
	store._apply_snapshot(stale)
	check(store.count("0001") == 0, "Older authoritative read cannot overwrite newer transfer")
	stale.revision = latest + 1
	stale.inventory_complete = false
	check(not store._apply_snapshot(stale), "Partial page cannot masquerade as whole inventory totals")
	backend.snapshot_delay = 5
	store.refresh()
	store.use_provider(backend, "isolated-account-b")
	await frames(10)
	check(not store.inventory_known and store.account_id == "isolated-account-b", "Old-account read ignored")
	await store.refresh()
	page._return_overview()
	page._set_filter("all")
	root.get_node("UiMotion").set_enabled(false)
	page._select_card("0001")
	check(page.content.modulate.a == 1, "Reduced motion immediately displays final state")
	page.consume_back_action()
	await frames()
	check(not page.in_detail, "Escape returns directly to collection")
	root.size = Vector2i(800,720)
	root.content_scale_size = Vector2i(800,720)
	await frames()
	check_filter_row()
	await capture("06-fixture-narrow-reduced-motion")
	var missing: Dictionary = store.cards[6].duplicate(true)
	store.cards[6].image = "res://missing-card-image.png"
	store.cards[6].artwork = "res://missing-artwork.png"
	page._set_filter("all")
	check(page.tiles["0007"].get_node("Art").texture == null and page.tiles["0007"].get_node("Art").get_child_count() == 1, "Missing image retains stable frame and readable fallback")
	store.cards[6] = missing
	root.get_node("AppState").dark_mode = true
	page._rebuild()
	await frames()
	await capture("07-fixture-dark")
	root.get_node("AppState").dark_mode = false
	page._rebuild()
	page._select_card("0001")
	router.go("res://scenes/Workbench.tscn")
	await scene_changed
	await frames()
	check(page.gift_dialog == null, "Leaving collection cleans temporary UI")
	check(current_scene.body.find_children("*", "Button", true, false).size() == 1, "Home retains existing single trend action")
	print("WORKBENCH CHECKS: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
