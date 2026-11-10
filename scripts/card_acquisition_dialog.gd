extends CanvasLayer
## Full-viewport presentation. The persistent store owns the paid operation.
const Reveal = preload("res://scripts/card_reveal.gd")
const UI = preload("res://scripts/account_dialog_ui.gd")
const Styles = preload("res://scripts/ui_styles.gd")
const DETAILS_Y := 634.0
signal closed
var page: Control
var store: Node
var shield: Control
var stage: Control
var back: TextureRect
var preview: Control
var hit: Button
var close_button: Button
var return_button: Button
var title_label: Label
var hint: Label
var details: VBoxContainer
var name_label: Label
var metadata: Label
var description: Label
var state := "ready"
var closing := false
var _epoch := -1
var _shown_id := ""
var _space_down := false
var _skip_requested := false

const ModalMotion = preload("res://scripts/card_modal_motion.gd")
var modal: Node
var shade: ColorRect
var _entered := false
var press_feedback: Node
var title_effect: Node

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
	stage = Control.new()
	stage.size = Vector2(760, 900)
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
	title_label.position = Vector2(312, 168)
	title_label.size = Vector2(136, 46)
	hint = _label("点击卡牌开启", 17, Color("#CAD1DF"))
	hint.position = Vector2(100, 224)
	hint.size = Vector2(560, 52)
	back = TextureRect.new()
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	back.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.position = Vector2(260, 253)
	back.size = Vector2(240, 360)
	stage.add_child(back)
	var season: Dictionary = page.store.season("season-001")
	back.texture = page._texture(str(season.get("back_image", "")))
	preview = Reveal.new()
	preview.position = Vector2(200, 205)
	preview.size = Vector2(360, 420)
	stage.add_child(preview)
	preview.status_label.add_theme_color_override("font_color", Color("#DCE5F4"))
	preview.presentation_changed.connect(_reveal_changed)
	preview.geometry_changed.connect(_align_card)
	if back.texture != null:
		preview._aspect = float(back.texture.get_width()) / back.texture.get_height()
		preview._layout()
	preview.hide()
	hit = _button(stage, "", _card_clicked, false)
	hit.position = back.position
	hit.size = back.size
	hit.accessibility_name = "获取卡牌，200 电池一次"
	for value in ["normal", "hover", "pressed", "disabled", "focus"]: hit.add_theme_stylebox_override(value, StyleBoxEmpty.new())
	press_feedback = preload("res://scripts/card_press_feedback.gd").bind(hit, back)
	details = VBoxContainer.new()
	details.position = Vector2(110, DETAILS_Y)
	details.size = Vector2(540, 160)
	details.add_theme_constant_override("separation", 6)
	stage.add_child(details)
	name_label = _detail_label(22, Color.WHITE, true)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 11)
	details.add_child(info)
	metadata = _detail_label(14, Color("#C4CDDF"), false, info)
	description = _detail_label(16, Color("#DDE3EE"), false, info)
	for text in [metadata, description]:
		text.add_theme_constant_override("line_spacing", text.get_theme_constant("line_spacing") + 5)
	description.max_lines_visible = 3
	return_button = _button(details, "返回我的收藏", dismiss, true)
	details.hide()
	close_button = _button(stage, "", dismiss, false)
	close_button.theme = page.theme
	close_button.icon = UI.glyph("close", Color("#DCE5F4"))
	close_button.add_theme_constant_override("icon_max_width", 20)
	close_button.custom_minimum_size = Vector2(36, 36)
	close_button.size = Vector2(36, 36)
	close_button.accessibility_name = "返回我的收藏"
	store.changed.connect(_sync)
	get_viewport().size_changed.connect(_layout)
	page.resized.connect(_layout)
	get_node("/root/AppState").font_scale_changed.connect(_layout.unbind(1))
	if not get_node("/root/AppState").dark_mode:
		for label in [title_label, hint, name_label, metadata, description, preview.status_label]:
			label.add_theme_color_override("font_color", Color("#182333"))
		close_button.icon = UI.glyph("close", Color("#182333"))
	title_effect = preload("res://scripts/card_title_effect.gd").bind(title_label, get_node("/root/AppState").dark_mode)
	_layout()
	_sync()

func present() -> void:
	modal.present()
	title_effect.present()
	hit.grab_focus()
	store.open()

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
	button.add_theme_stylebox_override("focus", Styles.box(Color.TRANSPARENT, 7, Color("#ADCAFF")))
	parent.add_child(button)
	button.pressed.connect(callback)
	return button

func _layout() -> void:
	if not is_instance_valid(stage): return
	var bounds := get_viewport().get_visible_rect().size
	var factor: float = minf(page.canvas.scale.x, minf(bounds.y / 950, bounds.x / 800))
	modal.layout((bounds - stage.size) * 0.5, Vector2.ONE * factor)
	close_button.position = Vector2(672, 164)
	_align_card()

func _align_card() -> void:
	if not is_instance_valid(hit): return
	back.position = preview.position + preview.card_rect.position
	back.size = preview.card_rect.size
	hit.position = back.position
	hit.size = back.size

func _sync() -> void:
	if closing: return
	if store.epoch != _epoch:
		dismiss()
		return
	if store.ready_result():
		title_effect.begin_opening()
		if _shown_id == str(store.operation.id): return
		_shown_id = str(store.operation.id)
		var card: Dictionary = page.store.card(str(store.operation.receipt.card_id))
		name_label.text = str(card.name)
		metadata.text = str(page.store.season(str(card.season_id)).get("name", "")) + " · 编号 " + str(card.get("number", ""))
		description.text = str(card.get("description", ""))
		var count: int = page.store.count(str(card.id))
		metadata.text += " · " + ("重复获得" if count > 1 else "已加入收藏") + " · 拥有 %d 张" % count
		state = "revealing"
		title_label.text = "正在开卡"
		hint.text = "请稍候"
		back.show()
		preview.show()
		hit.disabled = true
		var season: Dictionary = page.store.season(str(card.season_id))
		var session := Reveal.new_session(card, str(card.get("back_image", season.get("back_image", ""))), get_instance_id(), true)
		session.external_entry = true
		preview.present(session)
		if _entered: preview.allow_reveal()
		return
	state = "requesting" if store.busy else "ready"
	title_label.text = "正在开卡" if store.busy else "获取卡牌"
	hint.text = "请稍候" if store.busy else store.error if not store.error.is_empty() else "正在准备…" if store.loading else "点击卡牌开启"
	hit.disabled = store.busy or store.loading or store._corrupt
	if store.busy: title_effect.begin_opening()
	title_effect.set_waiting(state == "ready" and not hit.disabled)

func _reveal_changed() -> void:
	if closing: return
	back.visible = preview.state == "loading" and preview.back_texture == null
	if _entered and _skip_requested and preview.state in ["ready", "revealing"]:
		_skip_requested = false
		preview.skip()
		return
	details.visible = preview.detail_alpha > 0
	details.modulate.a = preview.detail_alpha
	details.position.y = DETAILS_Y + preview.detail_offset
	return_button.disabled = not preview.interactive
	return_button.focus_mode = Control.FOCUS_ALL if preview.interactive else Control.FOCUS_NONE
	if preview.interactive:
		state = "result"
		title_label.text = "获得卡牌"
		hint.text = store.error
		hit.disabled = false
		hit.accessibility_name = "返回我的收藏"

func _card_clicked() -> void:
	if closing: return
	if state == "result": dismiss()
	elif state == "ready":
		title_effect.begin_opening()
		store.acquire()

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
		if state == "revealing":
			if preview.state == "loading" or not _entered: _skip_requested = true
			else: preview.skip()
	elif event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		dismiss()
	elif event.pressed and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		var controls: Array = [hit, return_button, close_button] if state == "result" else [hit, close_button]
		controls = controls.filter(func(c): return not c.disabled and c.is_visible_in_tree())
		var index := controls.find(get_viewport().gui_get_focus_owner())
		controls[posmod(index + (-1 if event.shift_pressed else 1), controls.size())].grab_focus()

func dismiss() -> void:
	if is_instance_valid(title_effect): title_effect.close()
	if not is_inside_tree():
		closing = true
		if is_instance_valid(preview): preview.freeze()
		_exit_finished()
		return
	if closing: return
	closing = true
	press_feedback.freeze()
	if state == "result" and _epoch == store.epoch: store.acknowledge()
	state = "exiting"
	_skip_requested = false
	if is_instance_valid(preview): preview.freeze()
	hit.disabled = true
	return_button.disabled = true
	close_button.disabled = true
	modal.dismiss()

func _entry_finished() -> void:
	if closing: return
	_entered = true
	if not preview.session.is_empty(): preview.allow_reveal()

func _exit_finished() -> void:
	if state == "closed": return
	state = "closed"
	hide()
	closed.emit()
	queue_free()
