extends CanvasLayer
## Orchestrates presentation only. CardDrawStore retains the paid operation.
const Reveal = preload("res://scripts/card_reveal.gd")
const Carousel = preload("res://scripts/card_carousel_stage.gd")
const Aerospace = preload("res://scripts/card_aerospace_backdrop.gd")
const UI = preload("res://scripts/account_dialog_ui.gd")
const Styles = preload("res://scripts/ui_styles.gd")
const ModalMotion = preload("res://scripts/card_modal_motion.gd")
const DETAILS_Y := 634.0
const PREVIEW_ORIGIN := Vector2(380, 205)
const DEFAULT_SEASON := "season-001" # Verified in data/collection_catalog.json.
signal closed
var page: Control
var store: Node
var shield: Control
var stage: Control
var preview: Control
var carousel: Control
var aerospace: Control
var hit: Button
var close_button: Button
var return_button: Button
var title_label: Label
var hint: Label
var pool_note: Label
var pool_price: Label
var details: VBoxContainer
var name_label: Label
var metadata: Label
var description: Label
var modal: Node
var shade: ColorRect
var title_effect: Node
var state := "entering"
var closing := false
var _epoch := -1
var _shown_id := ""
var _space_down := false
var _skip_requested := false
var _force_skip := false
var _entered := false
var _pool_ready := false
var _pool_season_id := ""
var _pool_error := ""
var _alignment_started := false
var _extraction_started := false
var _handed_off := false
var _result_card: Dictionary = {}
var _counts_before: Dictionary = {}
var _result_lift := 0.0

func _ready() -> void:
	layer = 95
	_epoch = store.epoch
	shield = Control.new()
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shield)
	shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.26)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.add_child(shade)
	aerospace = Aerospace.new()
	aerospace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(aerospace)
	stage = Control.new()
	stage.size = Vector2(1120, 900)
	stage.theme = page.theme
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.add_child(stage)
	modal = ModalMotion.new()
	add_child(modal)
	modal.configure(shade, stage)
	modal.entered.connect(_entry_finished)
	modal.exited.connect(_exit_finished)
	title_label = _label("获取卡牌", 30, Color.WHITE, true)
	title_label.position = Vector2(310, 100)
	title_label.size = Vector2(500, 46)
	hint = _label("从流转的卡池中，选择一张属于你的卡牌", 17, Color.WHITE)
	hint.position = Vector2(160, 161)
	hint.size = Vector2(800, 52)
	carousel = Carousel.new()
	carousel.name = "CardCarouselStage"
	carousel.position = Vector2(0, 205)
	carousel.size = Vector2(1120, 430)
	stage.add_child(carousel)
	carousel.prepared.connect(_sync)
	carousel.entered.connect(_pool_entered)
	carousel.settled.connect(_pool_settled)
	carousel.extracted.connect(_pool_extracted)
	carousel.failed.connect(_pool_failed)
	carousel.chosen.connect(_card_clicked)
	preview = Reveal.new()
	preview.position = PREVIEW_ORIGIN
	preview.size = Vector2(360, 420)
	stage.add_child(preview)
	preview.presentation_changed.connect(_reveal_changed)
	preview.geometry_changed.connect(_align_card)
	preview.hide()
	hit = _button(stage, "", _card_clicked, false)
	hit.name = "AcquireCenterCard"
	hit.accessibility_name = "获取卡牌，200 电池一次，结果随机；鼠标可选择任意卡背"
	hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for value in ["normal", "hover", "pressed", "disabled", "focus"]: hit.add_theme_stylebox_override(value, StyleBoxEmpty.new())
	hit.button_down.connect(carousel.press.bind(true))
	hit.button_up.connect(carousel.press.bind(false))
	hit.mouse_exited.connect(carousel.press.bind(false))
	pool_note = _label("点击任意卡片，开启你的卡牌", 17, Color.WHITE)
	pool_note.position = Vector2(160, 654)
	pool_note.size = Vector2(800, 40)
	pool_price = _label("200 电池/次 · 随机获得 1 张", 14, Color.WHITE)
	pool_price.position = Vector2(160, 700)
	pool_price.size = Vector2(800, 32)
	details = VBoxContainer.new()
	details.position = Vector2(260, DETAILS_Y)
	details.size = Vector2(600, 190)
	details.add_theme_constant_override("separation", 6)
	stage.add_child(details)
	name_label = _detail_label(22, Color.WHITE, true)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 11)
	details.add_child(info)
	metadata = _detail_label(14, Color.WHITE, false, info)
	description = _detail_label(16, Color.WHITE, false, info)
	for text in [metadata, description]:
		text.add_theme_constant_override("line_spacing", text.get_theme_constant("line_spacing") + 5)
	description.max_lines_visible = 3
	return_button = _button(details, "返回我的收藏", dismiss, true)
	details.hide()
	close_button = _button(stage, "", dismiss, false)
	close_button.theme = page.theme
	close_button.add_theme_constant_override("icon_max_width", 20)
	close_button.custom_minimum_size = Vector2(36, 36)
	close_button.size = Vector2(36, 36)
	close_button.accessibility_name = "返回我的收藏"
	close_button.position = Vector2(1040, 70)
	store.changed.connect(_sync)
	get_viewport().size_changed.connect(_layout)
	page.resized.connect(_layout)
	var app := get_node("/root/AppState")
	app.font_scale_changed.connect(_layout.unbind(1))
	app.color_mode_changed.connect(_update_palette.unbind(1))
	_update_palette()
	title_effect = preload("res://scripts/card_title_effect.gd").bind(title_label, app.dark_mode)
	_configure_pool(str(store.operation.get("pool_id", store.options.get("pool_id", DEFAULT_SEASON))))
	_layout()
	_sync()

func present() -> void:
	modal.present()
	aerospace.present()
	title_effect.present()
	close_button.grab_focus()
	store.open()

func _configure_pool(id: String) -> void:
	if _pool_season_id == id: return
	_pool_season_id = id
	_pool_ready = false
	_pool_error = ""
	var season: Dictionary = page.store.season(id)
	carousel.configure(page.store.results(id, "all"), str(season.get("back_image", "")))
	if _entered: carousel.present()

func _label(text: String, font_size: int, color: Color, strong := false) -> Label:
	var label := UI.label(stage, text, font_size, color, strong)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _detail_label(font_size: int, color: Color, strong := false, parent: Node = null) -> Label:
	var label := UI.label(details if parent == null else parent, "", font_size, color, strong)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(parent: Node, text: String, callback: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 17)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: button.add_theme_color_override(key, Color.WHITE)
	for key in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(key, Styles.box(Color("#092C87") if primary else Color.TRANSPARENT, 7))
	Styles.apply_focus(button)
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _layout() -> void:
	if not is_instance_valid(stage): return
	var bounds := get_viewport().get_visible_rect().size
	var factor: float = minf(page.canvas.scale.x, minf(bounds.y / 950, bounds.x / 1160))
	modal.layout((bounds - stage.size) * 0.5, Vector2.ONE * factor)
	_align_card()

func _align_card() -> void:
	if not is_instance_valid(hit): return
	# Halve the visible title-to-art gap in the existing layout. Move the
	# complete result group together, keeping its internal spacing and hit area.
	var title_ink := Rect2()
	for i in title_label.text.length():
		var bounds := title_label.get_character_bounds(i)
		if bounds.has_area(): title_ink = bounds if not title_ink.has_area() else title_ink.merge(bounds)
	if title_ink.has_area():
		var title_bottom := title_label.position.y + title_ink.end.y
		_result_lift = maxf(0.0, PREVIEW_ORIGIN.y + preview.card_rect.position.y - title_bottom) * 0.5
	preview.position = PREVIEW_ORIGIN - Vector2(0, _result_lift)
	details.position.y = DETAILS_Y - _result_lift + preview.detail_offset
	var rect: Rect2 = Rect2(preview.position + preview.card_rect.position, preview.card_rect.size) if _handed_off else Rect2(carousel.position + carousel.focus_rect().position, carousel.focus_rect().size)
	hit.position = rect.position
	hit.size = rect.size
	carousel.update_destination(_reveal_destination())

func _reveal_destination() -> Rect2:
	return Rect2(preview.position + preview.card_rect.position - carousel.position, preview.card_rect.size)

func _update_palette() -> void:
	var dark: bool = get_node("/root/AppState").dark_mode
	var colors := Styles.palette(dark)
	aerospace.set_palette(dark)
	for label in [title_label, name_label, description]: label.add_theme_color_override("font_color", colors.text)
	for label in [hint, pool_note, pool_price, metadata, preview.status_label]: label.add_theme_color_override("font_color", colors.muted)
	close_button.icon = UI.glyph("close", colors.text)
	if is_instance_valid(title_effect) and title_effect.material != null:
		title_effect.material.set_shader_parameter("deep_blue", Color("#6D91E0") if dark else Color("#12256B"))
		title_effect.material.set_shader_parameter("campus_blue", Color("#81A8F3") if dark else Color("#164AB9"))
		title_effect.material.set_shader_parameter("bright_blue", Color("#A6C3FF") if dark else Color("#416CD7"))

func _sync() -> void:
	if closing: return
	if store.epoch != _epoch:
		dismiss()
		return
	if store.ready_result():
		title_effect.begin_opening()
		if _shown_id != str(store.operation.id): _prepare_result()
		_try_align()
		_try_skip()
		return
	if not store.options.is_empty() and not store.busy:
		_configure_pool(str(store.options.get("pool_id", DEFAULT_SEASON)))
	state = "requesting" if store.busy else "ready" if _entered and _pool_ready else "entering"
	if not _pool_error.is_empty(): state = "error"
	title_label.text = "正在开卡" if store.busy else "获取卡牌"
	hint.text = "请稍候" if store.busy else store.error if not store.error.is_empty() else _pool_error if not _pool_error.is_empty() else "从流转的卡池中，选择一张属于你的卡牌"
	pool_note.text = "请稍候" if store.busy else "正在准备卡池…" if not _pool_ready and _pool_error.is_empty() else "" if not _pool_error.is_empty() else "点击任意卡片核实上次结果" if store.unresolved() else "点击任意卡片，开启你的卡牌"
	hit.disabled = state != "ready" or store.loading or store._corrupt or not store.available() or (store.options.is_empty() and not store.unresolved())
	hit.accessibility_name = "核实上次获取卡牌结果" if store.unresolved() else "获取卡牌，200 电池一次，结果随机；鼠标可选择任意卡背"
	if store.busy:
		title_effect.begin_opening()
		carousel.requesting()
	else:
		carousel.resume_flow()
	carousel.set_selection_enabled(not hit.disabled)
	title_effect.set_waiting(state == "ready" and not hit.disabled)

func _prepare_result() -> void:
	_shown_id = str(store.operation.id)
	_result_card = page.store.card(str(store.operation.receipt.card_id))
	var season: Dictionary = page.store.season(str(_result_card.season_id))
	if not carousel.has_card(str(_result_card.id)):
		_configure_pool(str(_result_card.season_id))
	name_label.text = str(_result_card.name)
	var amount: int = page.store.count(str(_result_card.id))
	var was_owned := int(_counts_before.get(str(_result_card.id), {}).get("count", -1))
	var received := int(store.operation.receipt.quantity)
	var status := "重复获得" if was_owned > 0 or (_counts_before.is_empty() and amount > received) else "已加入收藏"
	metadata.text = "%s · 编号 %s · %s\n本次 +%d · 当前拥有 %d 张" % [season.get("name", ""), _result_card.get("number", ""), status, received, amount]
	description.text = str(_result_card.get("description", ""))
	state = "aligning"
	title_label.text = "正在开卡"
	hint.text = "请稍候"
	pool_note.text = "即将揭晓"
	hit.disabled = true
	carousel.set_selection_enabled(false)
	var session := Reveal.new_session(_result_card, str(_result_card.get("back_image", season.get("back_image", ""))), get_instance_id(), true)
	session.external_entry = true
	preview.present(session)

func _try_align() -> void:
	if closing or _result_card.is_empty() or _alignment_started or not _entered: return
	if carousel.state == "error":
		_alignment_started = true
		_pool_extracted(str(_result_card.id))
	elif _pool_ready:
		_alignment_started = true
		state = "aligning"
		if not carousel.settle_to(str(_result_card.id)):
			_alignment_started = false

func _pool_entered() -> void:
	if closing: return
	_pool_ready = true
	_align_card()
	_sync()
	if state == "ready" and not hit.disabled and close_button.has_focus(): hit.grab_focus()

func _pool_settled(id: String) -> void:
	if closing or _result_card.is_empty() or id != str(_result_card.id): return
	if preview.state == "loading": pool_note.text = "正在准备卡面…"
	_try_extract()

func _try_extract() -> void:
	if closing or _extraction_started or _result_card.is_empty() or preview.state == "loading" or carousel.state != "aligned": return
	_extraction_started = true
	state = "extracting"
	carousel.extract_to(_reveal_destination())

func _pool_extracted(id: String) -> void:
	if closing or _handed_off or _result_card.is_empty() or id != str(_result_card.id): return
	if preview.state == "loading": return
	_handed_off = true
	state = "revealing"
	carousel.hide()
	pool_note.hide()
	pool_price.hide()
	preview.show()
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hint.text = ""
	_align_card()
	preview.allow_reveal()
	if _force_skip:
		_force_skip = false
		preview.skip()
	_reveal_changed()

func _reveal_changed() -> void:
	if closing: return
	if not _handed_off:
		_try_extract()
		_try_skip()
		if _alignment_started and carousel.state == "error" and not _result_card.is_empty(): _pool_extracted(str(_result_card.id))
		return
	details.visible = preview.detail_alpha > 0
	details.modulate.a = preview.detail_alpha
	details.position.y = DETAILS_Y - _result_lift + preview.detail_offset
	return_button.disabled = not preview.interactive
	return_button.focus_mode = Control.FOCUS_ALL if preview.interactive else Control.FOCUS_NONE
	if preview.interactive:
		state = "result"
		title_label.text = "获得卡牌"
		hint.text = store.error
		hit.disabled = false
		hit.accessibility_name = "返回我的收藏"

func _try_skip() -> void:
	if not _skip_requested or closing or not _entered or not _alignment_started or preview.state == "loading": return
	_skip_requested = false
	if _handed_off:
		preview.skip()
		return
	_force_skip = true
	carousel.finish_to(_reveal_destination())
	if carousel.state == "error": _pool_extracted(str(_result_card.id))

func _pool_failed(message: String) -> void:
	_pool_error = message
	_sync()

func _card_clicked(index := -1) -> void:
	if closing or hit.disabled: return
	if state == "result":
		dismiss()
	elif state == "ready":
		# Lock before calling the service; the request never receives a visual ID.
		hit.disabled = true
		state = "requesting"
		_counts_before = page.store.inventory.duplicate(true)
		title_effect.begin_opening()
		carousel.requesting(index)
		store.acquire()
		_sync()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	if closing:
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		if not event.pressed: _space_down = false; return
		if event.echo or _space_down: return
		_space_down = true
		if state in ["aligning", "extracting", "revealing"] and store.ready_result():
			_skip_requested = true
			_try_skip()
	elif event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		dismiss()
	elif event.pressed and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		var controls: Array = [hit, return_button, close_button] if state == "result" else [hit, close_button]
		controls = controls.filter(func(c): return not c.disabled and c.is_visible_in_tree())
		if controls.is_empty(): return
		var index := controls.find(get_viewport().gui_get_focus_owner())
		controls[posmod(index + (-1 if event.shift_pressed else 1), controls.size())].grab_focus()

func dismiss() -> void:
	if is_instance_valid(title_effect): title_effect.close()
	if not is_inside_tree():
		closing = true
		if is_instance_valid(preview): preview.freeze()
		if is_instance_valid(carousel): carousel.freeze()
		_exit_finished()
		return
	if closing: return
	closing = true
	if state == "result" and _epoch == store.epoch: store.acknowledge()
	state = "exiting"
	_skip_requested = false
	preview.freeze()
	carousel.freeze()
	aerospace.freeze()
	hit.disabled = true
	return_button.disabled = true
	close_button.disabled = true
	modal.dismiss()

func _entry_finished() -> void:
	if closing: return
	_entered = true
	carousel.present()
	_sync()

func _exit_finished() -> void:
	if state == "closed": return
	state = "closed"
	hide()
	closed.emit()
	queue_free()
