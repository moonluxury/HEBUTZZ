extends "res://scripts/minimal_page.gd"
const Store = preload("res://scripts/collection_store.gd")
const GiftDialog = preload("res://scripts/collection_gift_dialog.gd")
const CardReveal = preload("res://scripts/card_reveal.gd")
const UnownedShader = preload("res://shaders/collection_unowned.gdshader")
var unowned_material: ShaderMaterial
var store: Node
var back_button: Button
var filter := "owned"
var selected_season := ""
var expanded: Dictionary = {}
var selected_id := ""
var in_detail := false
var overview: Dictionary = {}
var tiles: Dictionary = {}
var groups: Dictionary = {}
var content: Control
var detail_panel: Control
var card_scroll: ScrollContainer
var toolbar: Control
var filter_buttons: Dictionary = {}
var summary_label: Label
var status_label: Label
var refresh_button: Button
var recovery_button: Button
var gift_dialog: Window
var _rebuilding := false
var _restore_ticket := 0
var _reveal_serial := 0
var _reveal_session: Dictionary = {}
var reveal: Control
var _reveal_space_down := false

func _button(parent: Node, node_name: String, caption: String, action: Callable, color: Color = Color.TRANSPARENT) -> Button:
	var button := super._button(parent, node_name, caption, action, color)
	# Keep the reused sidebar untouched; only collection content opts out.
	if parent != sidebar:
		_suppress_collection_focus(button)
	return button

func _suppress_collection_focus(control: Control) -> void:
	# Remove focus decoration, retaining keyboard navigation and focus restoration.
	control.set_meta("suppress_focus_feedback", true)
	control.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _ready() -> void:
	active_nav = "CollectionButton"
	var router := get_node("/root/PageRouter")
	store = router.get_node_or_null("CollectionStore")
	if store == null:
		store = Store.new()
		store.name = "CollectionStore"
		router.add_child(store)
	if selected_season.is_empty() and not store.seasons.is_empty():
		selected_season = str(store.seasons[-1].id)
		expanded[selected_season] = true
	store.changed.connect(_on_data_changed)
	super._ready()
	store.refresh()

func _exit_tree() -> void:
	_reveal_space_down = false
	if is_instance_valid(reveal):
		reveal.cancel()
	if is_instance_valid(gift_dialog):
		gift_dialog.queue_free()
		gift_dialog = null
	_restore_ticket += 1

func _build_content() -> void:
	back_button = sidebar.get_node("HomeButton")
	_label(body, "我的收藏", TITLE_SIZE, text_color, Rect2(0, 0, 500, 52), true).name = "Title"
	_label(body, "获取卡片，成为大魔法师", BODY_SIZE, muted_color, Rect2(0, 60, 650, 38)).name = "Subtitle"
	summary_label = _label(body, "", 20, muted_color)
	status_label = _label(body, "", 18, muted_color)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recovery_button = _button(body, "RecoverGift", "查询赠送结果", store.recover_gift)
	toolbar = Control.new()
	toolbar.name = "CollectionToolbar"
	body.add_child(toolbar)
	refresh_button = _button(toolbar, "RefreshInventory", "刷新", store.refresh)
	filter_buttons.clear()
	for item in [["owned", "已拥有"], ["all", "全部卡牌"], ["wanted", "想要"]]:
		filter_buttons[item[0]] = _button(body, "Filter_" + item[0], item[1], _set_filter.bind(item[0]))
		filter_buttons[item[0]].set_meta("foreground_only_feedback", true)
	content = Control.new()
	content.name = "CollectionContent"
	body.add_child(content)
	_render()

func _rebuild(unused: Variant = null) -> void:
	if is_instance_valid(gift_dialog):
		gift_dialog.queue_free()
		gift_dialog = null
	super._rebuild(unused)

func _season_title(season: Dictionary) -> String:
	return str(season.get("name", ""))

func _refresh_cached_content() -> void:
	_on_data_changed()
	store.refresh()

func _on_data_changed() -> void:
	if not is_inside_tree() or not is_instance_valid(content):
		return
	var focus_id := _focused_card()
	var old_index := tiles.keys().find(focus_id)
	_reconcile_selection()
	_render()
	if not focus_id.is_empty():
		if not tiles.has(focus_id):
			var keys := tiles.keys()
			focus_id = str(keys[clampi(old_index, 0, keys.size() - 1)]) if not keys.is_empty() else ""
		_restore_focus.call_deferred(focus_id)

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _render() -> void:
	if not is_instance_valid(content) or _rebuilding:
		return
	_rebuilding = true
	var saved_cards_scroll := card_scroll.scroll_vertical if is_instance_valid(card_scroll) else 0
	_clear(content)
	tiles.clear()
	groups.clear()
	detail_panel = null
	card_scroll = null
	var totals: Dictionary = store.summary()
	summary_label.text = "已拥有 %d 款 · 共 %d 张" % [totals.kinds, totals.total] if totals.known else "已拥有 — 款 · 共 — 张"
	status_label.text = "正在读取收藏…" if store.loading else store.status
	refresh_button.visible = is_instance_valid(store.provider)
	refresh_button.disabled = store.loading
	recovery_button.visible = store.pending()
	recovery_button.disabled = store._busy or not is_instance_valid(store.provider)
	for button in filter_buttons.values():
		button.visible = not in_detail
	if in_detail:
		card_scroll = _detail_scroller("CardListScroll")
		var grid := Control.new()
		grid.name = "DetailGrid"
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_scroll.add_child(grid)
		_build_grid(grid, store.results(selected_season, filter))
		detail_panel = Control.new()
		detail_panel.name = "SelectedCardDetails"
		content.add_child(detail_panel)
		_build_detail()
	else:
		for season in store.seasons:
			var group := Control.new()
			group.name = "Season_" + str(season.id)
			content.add_child(group)
			groups[season.id] = group
			var items: Array = store.results(season.id, filter)
			var toggle := _button(group, "Toggle", "", _toggle_group.bind(str(season.id)))
			toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var is_open: bool = expanded.get(season.id, false)
			var chevron := _icon(toggle, "collection-chevron", Rect2(0, 13, 24, 24), text_color)
			chevron.name = "Chevron"
			chevron.pivot_offset = Vector2(12, 12)
			chevron.rotation = PI * 0.5 if is_open else 0.0
			_label(toggle, _season_title(season), BUTTON_SIZE, text_color).name = "SeasonTitle"
			toggle.accessibility_name = ("收起 " if is_open else "展开 ") + _season_title(season)
			var owned := 0
			var total := 0
			for item in items:
				if store.count(item.id) > 0:
					owned += 1
					total += store.count(item.id)
			_label(group, "%s · %d 款%s" % [_filter_name(), items.size(), " · 已拥有 %d 款 / %d 张" % [owned, total] if store.inventory_known else ""], 18, muted_color).name = "Count"
			if items.is_empty():
				continue
			_line(group, Rect2()).name = "Divider"
			if is_open:
				var grid := Control.new()
				grid.name = "Grid"
				group.add_child(grid)
				_build_grid(grid, items)
			else:
				var previews := Control.new()
				previews.name = "Previews"
				previews.mouse_filter = Control.MOUSE_FILTER_IGNORE
				group.add_child(previews)
				for index in mini(3, items.size()):
					_picture(previews, items[index], Rect2(index * 36, 0, 30, 45))
	if store.seasons.is_empty():
		_empty(content, "暂无已公开的卡牌", "目录接入后将按季显示。")
	_rebuilding = false
	_layout()
	if in_detail:
		card_scroll.set_deferred("scroll_vertical", saved_cards_scroll)

func _detail_scroller(node_name: String) -> ScrollContainer:
	var scroller := ScrollContainer.new()
	scroller.name = node_name
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.follow_focus = true
	content.add_child(scroller)
	return scroller

func _filter_name() -> String:
	return {"owned": "已拥有", "all": "全部卡牌", "wanted": "想要"}[filter]

func _update_filter_tabs(animate := false) -> void:
	for id in filter_buttons:
		var button: Button = filter_buttons[id]
		var line_width := maxf(40, button.size.x - 32)
		_tab(button, id == filter, line_width, 48, animate and id == filter)
		button.get_node("SelectionLine").position.x = (button.size.x - line_width) * 0.5

func _build_grid(parent: Control, items: Array) -> void:
	if items.is_empty():
		var title := "本季还没有获得卡牌" if filter == "owned" else "还没有标记想要的卡牌" if filter == "wanted" else "本季暂无公开卡牌"
		if filter == "owned" and not store.inventory_known:
			title = "暂无收藏"
		var reason := "当前库存尚未接入，可先浏览公开卡牌、标记想要。" if filter == "owned" and not store.inventory_known else "可以切换季或筛选，继续浏览收藏。"
		_empty(parent, title, reason)
		return
	for item in items:
		var id := str(item.id)
		var tile := _button(parent, "Card_" + id, "", _select_card.bind(id))
		tile.set_meta("card_id", id)
		tile.accessibility_name = "%s，%s%s" % [item.name, _count_text(id), "，想要" if store.is_wanted(id) else ""]
		tile.set_meta("motion_fixed", true)
		_style_tile(tile, id)
		_picture(tile, item, Rect2()).name = "Art"
		_label(tile, str(item.name), 21, text_color, Rect2(), true).name = "CardName"
		_label(tile, _count_badge(id), 16, muted_color).name = "Owned"
		var wanted := _icon(tile, "heart-filled", Rect2(), _accent())
		wanted.name = "Wanted"
		wanted.visible = store.is_wanted(id)
		tiles[id] = tile

func _style_tile(tile: Button, id: String) -> void:
	var frame: StyleBoxFlat = tile.get_meta("collection_frame") if tile.has_meta("collection_frame") else null
	if frame == null:
		frame = _style(Color.TRANSPARENT, 4)
		frame.set_border_width_all(0)
		frame.border_color = Color.TRANSPARENT
		tile.set_meta("collection_frame", frame)
		tile.mouse_entered.connect(_update_tile_state.bind(tile, id, Tokens.HOVER))
		tile.mouse_exited.connect(_update_tile_state.bind(tile, id, Tokens.HOVER))
		tile.button_down.connect(_update_tile_state.bind(tile, id, Tokens.PRESS))
		tile.button_up.connect(_update_tile_state.bind(tile, id, Tokens.PRESS))
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		tile.add_theme_stylebox_override(state, frame)
	_update_tile_state(tile, id, Tokens.STATE)

func _update_tile_state(tile: Button, id: String, duration: float) -> void:
	if not is_instance_valid(tile) or not tile.is_inside_tree():
		return
	var frame: StyleBoxFlat = tile.get_meta("collection_frame")
	var selected_color := Tokens.DARK_SOFT if dark else Tokens.SOFT
	var background := Color.TRANSPARENT
	if tile.is_pressed():
		background = selected_color.lightened(0.06) if dark else selected_color.darkened(0.04)
	elif in_detail and selected_id == id:
		background = selected_color
	elif tile.is_hovered() and _motion().hover_enabled:
		background = Tokens.DARK_SOFT if dark else Tokens.SOFT_HOVER
	_motion().animate(tile, frame, ^"bg_color", background, duration)

func _picture(parent: Node, item: Dictionary, rect: Rect2, complete_card := false) -> Control:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	_rect(image, rect)
	# Only the right-hand detail uses the composed card. All other artwork is unframed.
	var path := str(item.get("image" if complete_card else "artwork", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		image.texture = _texture(path)
		_set_card_art_state(image, str(item.get("id", "")))
	else:
		var missing := _label(image, "卡图暂不可用", 18, muted_color)
		missing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return image

func _picture_ratio(image: Control) -> float:
	if image is CardReveal:
		return 1.5
	return image.texture.get_height() / float(image.texture.get_width()) if image.texture != null else 1.5

func _set_card_art_state(image: TextureRect, id: String) -> void:
	# The public catalogue always shows the original artwork. Other views may
	# distinguish known unowned cards; unknown inventory is never treated as zero.
	if filter != "all" and store.count(id) == 0:
		if unowned_material == null:
			unowned_material = ShaderMaterial.new()
			unowned_material.shader = UnownedShader
		image.material = unowned_material
	else:
		image.material = null

func _count_text(id: String) -> String:
	var amount: int = store.count(id)
	return "拥有数量未接入" if amount < 0 else "未拥有" if amount == 0 else "拥有 %d 张" % amount

func _count_badge(id: String) -> String:
	var amount: int = store.count(id)
	return "×—" if amount < 0 else "×%d" % amount

func _count_width(quantity: Label, width: float) -> float:
	var text_width := quantity.get_theme_font("font").get_string_size(quantity.text, HORIZONTAL_ALIGNMENT_LEFT, -1, quantity.get_theme_font_size("font_size")).x
	return minf(ceilf(text_width) + 2, width * 0.45)

func _layout_name_count(title: Label, quantity: Label, rect: Rect2) -> void:
	var count_width := _count_width(quantity, rect.size.x)
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity.autowrap_mode = TextServer.AUTOWRAP_OFF
	_rect(title, Rect2(rect.position, Vector2(rect.size.x - count_width - 8, rect.size.y)))
	_rect(quantity, Rect2(rect.end.x - count_width, rect.position.y, count_width, rect.size.y))

func _empty(parent: Control, title: String, reason: String) -> void:
	_label(parent, title, SECTION_SIZE, text_color, Rect2(0, 48, 680, 54), true).name = "EmptyTitle"
	var description := _label(parent, reason, 20, muted_color, Rect2(0, 112, 680, 64))
	description.name = "EmptyReason"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if filter != "all":
		var browse := _button(parent, "BrowseAll", "浏览全部卡牌", _set_filter.bind("all"))
		_rect(browse, Rect2(0, 196, 180, 48))

func _layout_content(width: float) -> void:
	if not is_instance_valid(content):
		return
	_rect(summary_label, Rect2(maxf(0, width - 340), 12 if width > 950 else 108, 340, 36))
	var top := 126.0 if width > 950 else 160.0
	toolbar.visible = refresh_button.visible
	_rect(toolbar, Rect2(0, top, width, 42))
	var filter_width := minf(120, width * 0.17)
	_rect(body.get_node("Subtitle"), Rect2(0, 60, width - filter_width * 3 - 20, 38))
	var index := 0
	for key in filter_buttons:
		_rect(filter_buttons[key], Rect2(width - filter_width * (3 - index), 54, filter_width, 50))
		index += 1
	_update_filter_tabs()
	status_label.visible = not status_label.text.is_empty()
	var status_top := top + (54.0 if toolbar.visible else 0.0)
	_rect(status_label, Rect2(0, status_top, width - (172 if recovery_button.visible else 0), 42))
	_rect(refresh_button, Rect2(0, 0, 88, 42))
	_rect(recovery_button, Rect2(width - 156, status_top, 156, 42))
	_rect(content, Rect2(0, status_top + (54.0 if status_label.visible or recovery_button.visible else 0.0), width, 100))
	var height := 0.0
	var grid_top := 0.0
	var available_height := scroll.size.y - content.position.y - grid_top - 12
	var split_detail := in_detail and width >= 920
	if split_detail:
		# Use normal page flow if the complete detail cannot fit with a readable image.
		# The right panel never has a scroll container of its own.
		var candidate_width := width * 0.41 - 42
		var ratio := _picture_ratio(detail_panel.get_node("Preview")) if detail_panel.has_node("Preview") else 0.0
		split_detail = available_height >= _detail_text_height(_detail_rows(candidate_width)) + CardReveal.EXTRA_HEIGHT + minf(180, candidate_width - 32) * ratio
	# SHOW_NEVER does not impose the child's old minimum height during resizing.
	# The body exactly fits this viewport; only the left card list scrolls.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if split_detail else ScrollContainer.SCROLL_MODE_AUTO
	if in_detail:
		var left_width := width * 0.59 if split_detail else width
		var grid: Control = card_scroll.get_node("DetailGrid")
		var grid_height := _layout_grid(grid, left_width - 16, 4)
		grid.custom_minimum_size.y = grid_height
		var right_width := width - left_width - 42 if split_detail else width
		var panel_height := _layout_detail(right_width, available_height if split_detail else 0.0)
		card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if split_detail else ScrollContainer.SCROLL_MODE_DISABLED
		_rect(card_scroll, Rect2(0, grid_top, left_width, available_height if split_detail else grid_height))
		_rect(detail_panel, Rect2(left_width + 42 if split_detail else 0.0, grid_top if split_detail else grid_height + 90, right_width, panel_height))
		height = available_height + grid_top + 12 if split_detail else grid_height + panel_height + 112
		if split_detail:
			scroll.scroll_vertical = 0
	else:
		for season in store.seasons:
			var group: Control = groups[season.id]
			group.position = Vector2(0, height)
			_rect(group.get_node("Toggle"), Rect2(0, 0, width - 120, 50))
			_rect(group.get_node("Toggle/SeasonTitle"), Rect2(36, 0, width - 156, 50))
			_rect(group.get_node("Count"), Rect2(36, 54, width - 36, 34))
			var group_height := 112.0
			if group.has_node("Grid"):
				group.get_node("Grid").position = Vector2(0, 110)
				group_height = 130 + _layout_grid(group.get_node("Grid"), width)
			elif group.has_node("Previews"):
				_rect(group.get_node("Previews"), Rect2(width - 112, 12, 110, 50))
			if group.has_node("Divider"):
				_rect(group.get_node("Divider"), Rect2(0, group_height, width, 1))
			group.size = Vector2(width, group_height)
			height += group_height + 30
	content.size = Vector2(width, height)
	content_height = scroll.size.y if split_detail else content.position.y + maxf(300, height) + 30

func _layout_grid(grid: Control, width: float, preferred_columns := 0) -> float:
	if grid.has_node("EmptyTitle"):
		grid.get_node("EmptyTitle").size.x = width
		grid.get_node("EmptyReason").size.x = width
		grid.size = Vector2(width, 270)
		return 270
	var columns := maxi(1, floori((width + 20) / 210))
	if preferred_columns > 0:
		# Four columns in the desktop detail; narrower layouts keep cards readable.
		columns = mini(preferred_columns, maxi(1, floori((width + 20) / 170)))
	var tile_width := (width - (columns - 1) * 20) / columns
	var column_gap := 20.0
	var row_gap := 17.0 if preferred_columns > 0 else 19.0
	if preferred_columns > 0 and columns > 1:
		# Grow detail tiles by 2 px within the existing grid width.
		tile_width += 2.0
		column_gap = (width - tile_width * columns) / (columns - 1)
	var art_ratio := 0.0
	for tile in grid.get_children():
		art_ratio = maxf(art_ratio, _picture_ratio(tile.get_node("Art")))
	var art_height := (tile_width - 12) * art_ratio
	var tile_height := art_height + 54
	var index := 0
	for tile in grid.get_children():
		_rect(tile, Rect2((index % columns) * (tile_width + column_gap), floori(float(index) / columns) * (tile_height + row_gap), tile_width, tile_height))
		_rect(tile.get_node("Art"), Rect2(6, 6, tile_width - 12, art_height))
		_layout_name_count(tile.get_node("CardName"), tile.get_node("Owned"), Rect2(8, art_height + 16, tile_width - 16, 30))
		# Overlay the marker inside the artwork; wanted state never changes row height.
		_rect(tile.get_node("Wanted"), Rect2(tile_width - 38, art_height - 26, 24, 24))
		index += 1
	var height := ceilf(float(index) / columns) * (tile_height + row_gap)
	grid.size = Vector2(width, height)
	return height

func _build_detail() -> void:
	_clear(detail_panel)
	reveal = null
	var item: Dictionary = store.card(selected_id)
	if item.is_empty():
		_empty(detail_panel, "没有符合筛选的卡牌", "切换筛选或季，继续浏览。")
		_compact_detail_text()
		return
	if _reveal_session.is_empty() or str(_reveal_session.card.id) != selected_id:
		_start_reveal_session(item, false)
	var unowned: bool = store.count(selected_id) == 0
	if unowned:
		# A refresh may remove the last copy during an active reveal.
		_reveal_session.static = true
	reveal = CardReveal.new()
	reveal.name = "Preview"
	detail_panel.add_child(reveal)
	reveal.status_label.add_theme_color_override("font_color", muted_color)
	reveal.presentation_changed.connect(_apply_detail_reveal)
	reveal.action_finished.connect(func(): _restore_focus.call_deferred(selected_id))
	reveal.present(_reveal_session, unowned)
	_label(detail_panel, str(item.name), SECTION_SIZE, text_color, Rect2(), true).name = "Name"
	_label(detail_panel, _season_title(store.season(item.season_id)) + " · 编号 " + str(item.get("number", "")), 18, muted_color).name = "Metadata"
	var description := _label(detail_panel, str(item.get("description", "")), 20, text_color)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.name = "Description"
	_label(detail_panel, _count_badge(selected_id), 22, muted_color).name = "Quantity"
	var acquired: Dictionary = store.inventory.get(selected_id, {})
	var fields := ""
	for key in ["acquired_label", "source_label"]:
		if not str(acquired.get(key, "")).is_empty():
			fields += str(acquired[key]) + "\n"
	var facts := _label(detail_panel, fields.strip_edges(), 18, muted_color)
	facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.name = "Facts"
	var rule: Dictionary = store.gift_rule(selected_id)
	var amount: int = store.count(selected_id)
	var caption := "未拥有" if amount == 0 else "库存未接入" if amount < 0 else "仅有 1 张" if amount == 1 else "赠送好友"
	var give := _button(detail_panel, "Gift", caption, _open_gift.bind(selected_id))
	if int(rule.max) > 0:
		_style_button(give, BLUE, true)
		_suppress_collection_focus(give)
	else:
		# This disabled state keeps the action's size and requested white/blue palette.
		give.disabled = true
		give.set_meta("motion_fixed", true)
		give.mouse_default_cursor_shape = Control.CURSOR_ARROW
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			give.add_theme_stylebox_override(state, _style(Color.WHITE, 8, BLUE))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
			give.add_theme_color_override(state, BLUE)
	var wanted_button := _button(detail_panel, "Want", "♥ 取消想要" if store.is_wanted(selected_id) else "♡ 想要", _toggle_wanted.bind(selected_id))
	wanted_button.add_theme_color_override("font_color", _accent())
	var reason := _label(detail_panel, str(rule.reason), 18, muted_color)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.name = "GiftReason"
	_compact_detail_text()
	_apply_detail_reveal()

func _start_reveal_session(item: Dictionary, animated: bool) -> void:
	if is_instance_valid(reveal):
		reveal.cancel()
	_reveal_serial += 1
	var season: Dictionary = store.season(str(item.season_id))
	_reveal_session = CardReveal.new_session(item, str(item.get("back_image", season.get("back_image", ""))), _reveal_serial, animated and store.count(str(item.id)) != 0)

func _apply_detail_reveal() -> void:
	if not is_instance_valid(reveal) or not is_instance_valid(detail_panel):
		return
	for control in detail_panel.get_children():
		if not (control is Label or control is Button):
			continue
		control.visible = reveal.detail_alpha > 0.0
		control.modulate.a = reveal.detail_alpha
		if control.has_meta("reveal_y"):
			control.position.y = float(control.get_meta("reveal_y")) + reveal.detail_offset
		if control is Button:
			if not control.has_meta("reveal_disabled"):
				control.set_meta("reveal_disabled", control.disabled)
			control.disabled = bool(control.get_meta("reveal_disabled")) or not reveal.interactive
			control.focus_mode = Control.FOCUS_ALL if reveal.interactive else Control.FOCUS_NONE

func _compact_detail_text() -> void:
	for control in detail_panel.get_children():
		if control is Label or control is Button:
			control.add_theme_font_size_override("font_size", control.get_theme_font_size("font_size") - 4)
		if control is Label:
			control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _detail_rows(width: float) -> Array:
	var rows: Array = []
	var fields := [["Name", 32], ["Metadata", 26], ["Description", 30], ["Facts", 28], ["Gift", 44], ["Want", 40], ["GiftReason", 24]]
	if not detail_panel.has_node("Preview"):
		fields = [["EmptyTitle", 54], ["EmptyReason", 64], ["BrowseAll", 48]]
	for field in fields:
		var control := detail_panel.get_node_or_null(field[0]) as Control
		if control == null or control.text.is_empty():
			continue
		var row_height: float = field[1]
		if control is Label:
			var font := control.get_theme_font("font")
			var text_width := width - _count_width(detail_panel.get_node("Quantity"), width) - 8 if field[0] == "Name" else width
			var text_size := font.get_multiline_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, text_width, control.get_theme_font_size("font_size"), -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
			row_height = maxf(row_height, ceilf(text_size.y) + 4)
		rows.append([control, row_height])
	return rows

func _detail_text_height(rows: Array) -> float:
	var height := 22.0 # Includes the six-pixel result-entry movement.
	for row in rows:
		height += row[1] + 4
	return height

func _layout_detail(width: float, available_height := 0.0) -> float:
	var rows := _detail_rows(width)
	if not detail_panel.has_node("Preview"):
		var empty_y := 16.0
		for row in rows:
			_rect(row[0], Rect2(0, empty_y, width, row[1]))
			empty_y += row[1] + 4
		return empty_y
	var text_height := _detail_text_height(rows)
	var art_width := minf(240, width - 32)
	var art_ratio := _picture_ratio(detail_panel.get_node("Preview"))
	if available_height > 0:
		art_width = minf(art_width, (available_height - text_height - CardReveal.EXTRA_HEIGHT) / art_ratio)
	else:
		# In short stacked layouts the card itself fits the viewport; its details
		# remain reachable through the existing page scroll below it.
		art_width = minf(art_width, maxf(64.0, (scroll.size.y - CardReveal.EXTRA_HEIGHT - 16) / art_ratio))
	var art_height := art_width * art_ratio
	_rect(detail_panel.get_node("Preview"), Rect2(0, 0, width, art_height + CardReveal.EXTRA_HEIGHT))
	var y := art_height + CardReveal.EXTRA_HEIGHT + 16
	for row in rows:
		if row[0].name == "Name":
			_layout_name_count(row[0], detail_panel.get_node("Quantity"), Rect2(0, y, width, row[1]))
		else:
			_rect(row[0], Rect2(0, y, width, row[1]))
		row[0].set_meta("reveal_y", y)
		if row[0].name == "Name":
			detail_panel.get_node("Quantity").set_meta("reveal_y", y)
		y += row[1] + 4
	detail_panel.size = Vector2(width, y + 6)
	_apply_detail_reveal()
	return y + 6

func _reconcile_selection() -> void:
	if not in_detail:
		return
	var items: Array = store.results(selected_season, filter)
	for item in items:
		if item.id == selected_id:
			return
	selected_id = str(items[0].id) if not items.is_empty() else ""

func _select_card(id: String) -> void:
	var item: Dictionary = store.card(id)
	if item.is_empty():
		return
	if in_detail and selected_id == id and is_instance_valid(reveal) and reveal.state in ["loading", "ready", "revealing"]:
		return
	_restore_ticket += 1
	_start_reveal_session(item, true)
	if not in_detail:
		overview = {"filter": filter, "expanded": expanded.duplicate(), "season": selected_season,
			"scroll": scroll.scroll_vertical, "focus": id, "order": tiles.keys()}
		selected_season = str(item.season_id)
		selected_id = id
		in_detail = true
		_render()
		scroll.scroll_vertical = 0
		if store.count(id) == 0:
			_motion().cancel(content)
			content.modulate.a = 1.0
		else:
			_motion().enter(content)
		_restore_focus.call_deferred(id)
	else:
		selected_id = id
		for key in tiles:
			_style_tile(tiles[key], key)
		_build_detail()
		_layout()
		# CardReveal owns entry/reveal transforms; do not fade the entire panel again.
	_show_selected_preview(_reveal_serial)

func _show_selected_preview(serial: int) -> void:
	# Stacked layouts put the preview after the grid. Bring the reveal into view.
	var tree := get_tree()
	for frame in 2:
		await tree.process_frame
		if not is_inside_tree() or serial != _reveal_serial:
			return
	if not is_inside_tree() or serial != _reveal_serial or not in_detail or not is_instance_valid(reveal):
		return
	if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO:
		scroll.scroll_vertical = maxi(0, roundi(content.position.y + detail_panel.position.y - 8))

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.keycode != KEY_SPACE or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	if not in_detail or not is_visible_in_tree() or is_instance_valid(gift_dialog) or not is_instance_valid(reveal):
		return
	if _reveal_space_down:
		# Consume repeats and the release even after the skip has finished. The
		# focused tile must not receive half of a Space press and replay the card.
		get_viewport().set_input_as_handled()
		if not event.pressed:
			_reveal_space_down = false
		return
	if not event.pressed or event.echo:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var same_tile := is_instance_valid(focused) and str(focused.get_meta("card_id", "")) == selected_id
	if reveal.state in ["loading", "ready", "revealing"] or (reveal.state == "revealed" and same_tile):
		_reveal_space_down = true
		get_viewport().set_input_as_handled()
		if reveal.state in ["ready", "revealing"]:
			reveal.skip()

func _return_overview() -> void:
	_reveal_space_down = false
	if is_instance_valid(reveal):
		reveal.cancel()
	_reveal_session = {}
	reveal = null
	in_detail = false
	filter = overview.get("filter", filter)
	expanded = overview.get("expanded", expanded).duplicate()
	selected_season = overview.get("season", selected_season)
	_render()
	_restore_ticket += 1
	_restore_overview(_restore_ticket)
	_motion().enter(content)

func _restore_overview(ticket: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or ticket != _restore_ticket or in_detail:
		return
	var id := str(overview.get("focus", ""))
	var survived := tiles.has(id)
	if not survived:
		var order: Array = overview.get("order", [])
		var at := order.find(id)
		id = ""
		for distance in order.size():
			for index in [at + distance, at - distance]:
				if index >= 0 and index < order.size() and tiles.has(order[index]):
					id = order[index]
					break
			if not id.is_empty():
				break
	_restore_focus(id)
	scroll.scroll_vertical = int(overview.get("scroll", 0))
	if not survived and tiles.has(id):
		scroll.ensure_control_visible(tiles[id])

func _set_filter(value: String) -> void:
	filter = value
	_reconcile_selection()
	_render()
	_update_filter_tabs(true)
	if in_detail:
		_restore_focus(selected_id)
	else:
		filter_buttons[value].grab_focus()

func _toggle_group(id: String) -> void:
	# Rendering replaces group controls; carry the visible angle across rapid clicks.
	var previous: TextureRect = groups[id].get_node("Toggle/Chevron")
	var from_angle := previous.rotation
	expanded[id] = not expanded.get(id, false)
	_render()
	var toggle: Button = groups[id].get_node("Toggle")
	var chevron: TextureRect = toggle.get_node("Chevron")
	chevron.rotation = from_angle
	_motion().animate(chevron, chevron, ^"rotation", PI * 0.5 if expanded[id] else 0.0, Tokens.CHEVRON)
	toggle.grab_focus()

func _toggle_wanted(id: String) -> void:
	var response: Dictionary = store.set_wanted(id, not store.is_wanted(id))
	if not response.ok:
		status_label.text = response.message
		_layout()
	elif in_detail and detail_panel.has_node("Want"):
		detail_panel.get_node("Want").grab_focus()
	elif in_detail:
		_restore_focus(selected_id)
	if response.ok and tiles.has(id):
		_motion().enter(tiles[id].get_node("Wanted"), Tokens.STATE)

func _retire_window(window: Window) -> void:
	# The gift window relinquishes input/focus immediately; only its last pixels fade.
	if not is_inside_tree() or not is_visible_in_tree() or _motion().reduced() or DisplayServer.get_name() == "headless":
		return
	var ghost: Control
	if window.get_child_count() > 0 and window.get_child(0) is Control:
		ghost = window.get_child(0).duplicate(0)
	else:
		return
	ghost.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ghost.position = Vector2(window.position)
	ghost.size = Vector2(window.size)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ghost)
	_motion().retire(ghost)

func _focused_card() -> String:
	var focused := get_viewport().gui_get_focus_owner()
	return str(focused.get_meta("card_id", "")) if is_instance_valid(focused) else ""

func _restore_focus(id: String) -> void:
	if not is_inside_tree() or is_instance_valid(gift_dialog):
		return
	if tiles.has(id):
		tiles[id].grab_focus()
	elif in_detail:
		if detail_panel.has_node("BrowseAll"):
			detail_panel.get_node("BrowseAll").grab_focus()
		else:
			back_button.grab_focus()
	else:
		filter_buttons[filter].grab_focus()

func _open_gift(id: String) -> void:
	if int(store.gift_rule(id).max) <= 0:
		return
	if is_instance_valid(gift_dialog):
		gift_dialog.grab_focus()
		return
	gift_dialog = GiftDialog.new()
	gift_dialog.page = self
	gift_dialog.store = store
	gift_dialog.card_id = id
	add_child(gift_dialog)
	gift_dialog.closed.connect(func(): gift_dialog = null; _restore_focus.call_deferred(id))
	gift_dialog.present()

func consume_back_action() -> bool:
	if is_instance_valid(gift_dialog):
		gift_dialog.dismiss()
	elif in_detail:
		_return_overview()
	else:
		return false
	return true
